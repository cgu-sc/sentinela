from datetime import date
from typing import Any, Iterable
import unicodedata

import polars as pl
from fastapi import HTTPException

from data_cache import (
    get_df_dados_ibge_demografia,
    get_df_perfil_estabelecimento,
    scan_analise_gtin_inconsistencia_clinica,
)
from .indicator_rules import CLINICA_VALOR_MINIMO_DETALHAMENTO
from ...schemas.analytics import (
    ClinicoEvolucaoAnualSchema,
    ClinicoFaixaEtariaSchema,
    ClinicoIncompatibilidadeResponse,
    ClinicoIncompatibilidadeSummarySchema,
    ClinicoMunicipalRankingRowSchema,
    ClinicoMunicipalResumoRowSchema,
    ClinicoParkinsonDemografiaSchema,
    ClinicoPatologiaSchema,
)


_PARKINSON_PREVALENCIA_50_MAIS = 0.0086
_IBGE_ANO_CENSO_DEMOGRAFIA = 2022

_CLINICA_PATOLOGIA_META = {
    ("DOENCA DE PARKINSON", "IDADE_MENOR_50"): {
        "titulo": "Doença de Parkinson",
        "objeto": "Parkinson",
        "criterio": "beneficiários com menos de 50 anos",
        "descricao": "medicamentos destinados ao tratamento da doença de Parkinson, cuja ocorrência é incomum em pessoas com menos de 50 anos",
    },
    ("OSTEOPOROSE", "SEXO_MASCULINO"): {
        "titulo": "Osteoporose",
        "objeto": "osteoporose",
        "criterio": "beneficiários do sexo masculino",
        "descricao": "medicamentos destinados ao tratamento de osteoporose, cuja utilização é incomum em homens biológicos",
    },
    ("DIABETES", "IDADE_MENOR_20"): {
        "titulo": "Diabetes",
        "objeto": "diabetes",
        "criterio": "beneficiários com menos de 20 anos",
        "descricao": "medicamentos destinados ao tratamento de diabetes, cuja utilização é incomum em pessoas abaixo de 20 anos no recorte monitorado",
    },
    ("HIPERTENSAO", "IDADE_MENOR_20"): {
        "titulo": "Hipertensão",
        "objeto": "hipertensão",
        "criterio": "beneficiários com menos de 20 anos",
        "descricao": "medicamentos destinados ao tratamento de hipertensão, cuja utilização é incomum em pessoas abaixo de 20 anos no recorte monitorado",
    },
}

_CLINICA_COLUNAS_OBRIGATORIAS = {
    "id_cnpj",
    "id_ibge7",
    "patologia",
    "regra_clinica",
    "ano_base",
    "qtd_cpfs_distintos",
    "qtd_cpfs_incompativeis",
    "qtd_autorizacoes",
    "qtd_autorizacoes_incompativeis",
    "valor_total_pago",
    "valor_incompativel_pago",
    "percentual_cpfs_incompativeis",
    "rank_regional_qtd_cpfs_incompativeis",
    "percentil_regional_qtd_cpfs_incompativeis",
    "participacao_cpfs_incompativeis_regiao",
    "percentual_regional_cpfs_incompativeis",
    "razao_percentual_vs_regiao",
    "cpfs_incompativeis_esperados_regiao",
    "excesso_cpfs_incompativeis_vs_regiao",
}


def _clean_cnpj(value: str) -> str:
    return "".join(ch for ch in str(value or "") if ch.isdigit())


def _require_columns(df: pl.DataFrame, columns: Iterable[str], source: str) -> None:
    missing = [column for column in columns if column not in df.columns]
    if missing:
        raise HTTPException(
            status_code=500,
            detail=f"Contrato de cache invalido em {source}. Colunas ausentes: {', '.join(missing)}.",
        )


def _require_lazy_columns(lf: pl.LazyFrame, columns: Iterable[str], source: str) -> None:
    schema_names = lf.collect_schema().names()
    missing = [column for column in columns if column not in schema_names]
    if missing:
        raise HTTPException(
            status_code=500,
            detail=f"Contrato de cache invalido em {source}. Colunas ausentes: {', '.join(missing)}.",
        )


def _normalize_ascii_upper(value: Any) -> str:
    text = unicodedata.normalize("NFKD", str(value or ""))
    text = text.encode("ascii", "ignore").decode("ascii")
    return " ".join(text.replace("_", " ").split()).upper()


def _clinica_meta_key(patologia: Any, regra_clinica: Any) -> tuple[str, str]:
    return _normalize_ascii_upper(patologia), _normalize_ascii_upper(regra_clinica).replace(" ", "_")


def _clinica_raw_key_expr() -> pl.Expr:
    return pl.concat_str(
        [
            pl.col("patologia").cast(pl.Utf8),
            pl.lit("\u001f"),
            pl.col("regra_clinica").cast(pl.Utf8),
        ]
    )


def _clinica_raw_key_value(patologia: Any, regra_clinica: Any) -> str:
    return f"{str(patologia)}\u001f{str(regra_clinica)}"


def _ratio(numerator: Any, denominator: Any) -> float | None:
    den = float(denominator or 0)
    if den == 0:
        return None
    return float(numerator or 0) / den


def _sum_numeric(rows: list[dict[str, Any]], key: str) -> float:
    total = 0.0
    for row in rows:
        total += float(row.get(key) or 0)
    return total


def _periodo_label(data_inicio: date | None, data_fim: date | None) -> str:
    if data_inicio and data_fim:
        return (
            f"{data_inicio.year}"
            if data_inicio.year == data_fim.year
            else f"{data_inicio.year} a {data_fim.year}"
        )
    return "período analisado"


def _build_municipal_context(
    item: dict[str, Any],
    clinica_municipio: pl.DataFrame,
    perfil_estabelecimento: pl.DataFrame,
    id_cnpj_alvo: int,
    ranking_municipal_limite: int = 10,
) -> tuple[list[ClinicoMunicipalResumoRowSchema], list[ClinicoMunicipalRankingRowSchema]]:
    if ranking_municipal_limite < 0:
        raise HTTPException(status_code=422, detail="ranking_municipal_limite deve ser maior ou igual a zero.")

    clinica_recorte = clinica_municipio.filter(
        _clinica_raw_key_expr() == _clinica_raw_key_value(item["patologia"], item["regra_clinica"])
    )
    if clinica_recorte.is_empty():
        raise HTTPException(
            status_code=500,
            detail=(
                "Cache clinico municipal sem linhas para recorte obrigatorio: "
                f"patologia={item['patologia']}; regra={item['regra_clinica']}."
            ),
        )

    agregado = (
        clinica_recorte
        .group_by("id_cnpj")
        .agg(
            pl.sum("qtd_cpfs_distintos").alias("qtd_cpfs_distintos"),
            pl.sum("qtd_cpfs_incompativeis").alias("qtd_cpfs_incompativeis"),
            pl.sum("qtd_autorizacoes").alias("qtd_autorizacoes"),
            pl.sum("qtd_autorizacoes_incompativeis").alias("qtd_autorizacoes_incompativeis"),
            pl.sum("valor_total_pago").alias("valor_total_pago"),
            pl.sum("valor_incompativel_pago").alias("valor_incompativel_pago"),
        )
        .with_columns(pl.col("id_cnpj").cast(pl.Int64))
    )
    alvo_df = agregado.filter(pl.col("id_cnpj") == id_cnpj_alvo)
    if alvo_df.is_empty():
        raise HTTPException(status_code=500, detail="Comparativo municipal clinico sem CNPJ alvo.")

    all_rows = agregado.to_dicts()
    alvo = alvo_df.row(0, named=True)
    total = {
        "qtd_farmacias": len(all_rows),
        "qtd_cpfs_distintos": _sum_numeric(all_rows, "qtd_cpfs_distintos"),
        "qtd_cpfs_incompativeis": _sum_numeric(all_rows, "qtd_cpfs_incompativeis"),
        "qtd_autorizacoes_incompativeis": _sum_numeric(all_rows, "qtd_autorizacoes_incompativeis"),
        "valor_incompativel_pago": _sum_numeric(all_rows, "valor_incompativel_pago"),
    }
    demais = {
        "qtd_farmacias": max(int(total["qtd_farmacias"]) - 1, 0),
        "qtd_cpfs_distintos": float(total["qtd_cpfs_distintos"]) - float(alvo["qtd_cpfs_distintos"]),
        "qtd_cpfs_incompativeis": float(total["qtd_cpfs_incompativeis"]) - float(alvo["qtd_cpfs_incompativeis"]),
        "qtd_autorizacoes_incompativeis": (
            float(total["qtd_autorizacoes_incompativeis"]) - float(alvo["qtd_autorizacoes_incompativeis"])
        ),
        "valor_incompativel_pago": float(total["valor_incompativel_pago"]) - float(alvo["valor_incompativel_pago"]),
    }

    total_valor = float(total["valor_incompativel_pago"] or 0)
    resumo = [
        ClinicoMunicipalResumoRowSchema(
            grupo="Farmácia analisada",
            qtd_farmacias=1,
            qtd_cpfs_distintos=int(alvo["qtd_cpfs_distintos"] or 0),
            qtd_cpfs_incompativeis=int(alvo["qtd_cpfs_incompativeis"] or 0),
            qtd_autorizacoes_incompativeis=int(alvo["qtd_autorizacoes_incompativeis"] or 0),
            valor_incompativel_pago=float(alvo["valor_incompativel_pago"] or 0),
            participacao_valor_municipal=_ratio(alvo["valor_incompativel_pago"], total_valor),
        ),
        ClinicoMunicipalResumoRowSchema(
            grupo="Demais farmácias do município",
            qtd_farmacias=int(demais["qtd_farmacias"]),
            qtd_cpfs_distintos=int(demais["qtd_cpfs_distintos"]),
            qtd_cpfs_incompativeis=int(demais["qtd_cpfs_incompativeis"]),
            qtd_autorizacoes_incompativeis=int(demais["qtd_autorizacoes_incompativeis"]),
            valor_incompativel_pago=float(demais["valor_incompativel_pago"]),
            participacao_valor_municipal=_ratio(demais["valor_incompativel_pago"], total_valor),
        ),
        ClinicoMunicipalResumoRowSchema(
            grupo="Total do município",
            qtd_farmacias=int(total["qtd_farmacias"]),
            qtd_cpfs_distintos=int(total["qtd_cpfs_distintos"]),
            qtd_cpfs_incompativeis=int(total["qtd_cpfs_incompativeis"]),
            qtd_autorizacoes_incompativeis=int(total["qtd_autorizacoes_incompativeis"]),
            valor_incompativel_pago=total_valor,
            participacao_valor_municipal=1.0 if total_valor > 0 else None,
        ),
    ]

    _require_columns(perfil_estabelecimento, ["id_cnpj", "cnpj", "razao_social"], "perfil_estabelecimento")
    perfil = (
        perfil_estabelecimento
        .select(["id_cnpj", "cnpj", "razao_social"])
        .with_columns(
            pl.col("id_cnpj").cast(pl.Int64),
            pl.col("cnpj").cast(pl.Utf8).str.replace_all(r"\D", "").str.zfill(14),
            pl.col("razao_social").cast(pl.Utf8),
        )
        .unique(subset=["id_cnpj"], keep="first")
    )
    ranking_base = (
        agregado
        .sort(
            ["valor_incompativel_pago", "qtd_autorizacoes_incompativeis", "valor_total_pago"],
            descending=[True, True, True],
        )
    )
    if ranking_municipal_limite > 0:
        ranking_base = ranking_base.head(ranking_municipal_limite)

    top = (
        ranking_base
        .join(perfil, on="id_cnpj", how="left")
        .with_row_index("posicao", offset=1)
    )
    if top.filter(pl.col("cnpj").is_null() | pl.col("razao_social").is_null()).height > 0:
        ids = top.filter(pl.col("cnpj").is_null() | pl.col("razao_social").is_null()).get_column("id_cnpj").to_list()
        raise HTTPException(status_code=500, detail=f"Perfil ausente para ranking clinico municipal: id_cnpj={ids}.")

    ranking = [
        ClinicoMunicipalRankingRowSchema(
            posicao=int(row["posicao"]),
            id_cnpj=int(row["id_cnpj"]),
            cnpj=str(row["cnpj"]),
            razao_social=str(row["razao_social"]),
            is_alvo=int(row["id_cnpj"]) == id_cnpj_alvo,
            qtd_autorizacoes=int(row["qtd_autorizacoes"] or 0),
            qtd_autorizacoes_incompativeis=int(row["qtd_autorizacoes_incompativeis"] or 0),
            valor_total_pago=float(row["valor_total_pago"] or 0),
            valor_incompativel_pago=float(row["valor_incompativel_pago"] or 0),
            participacao_municipal=_ratio(row["valor_incompativel_pago"], total_valor),
        )
        for row in top.to_dicts()
    ]
    return resumo, ranking


def _build_parkinson_demografia(
    farmacia_row: dict[str, Any],
    evolucao_anual: list[ClinicoEvolucaoAnualSchema],
) -> ClinicoParkinsonDemografiaSchema:
    if not evolucao_anual:
        raise HTTPException(status_code=500, detail="Evolucao anual de Parkinson ausente.")

    observacao = max(evolucao_anual, key=lambda row: (row.qtd_cpfs_distintos, row.ano_base))
    if observacao.qtd_cpfs_distintos <= 0:
        raise HTTPException(status_code=500, detail="CPFs observados de Parkinson invalidos.")

    id_ibge7 = str(farmacia_row.get("id_ibge7") or "").strip()
    municipio = str(farmacia_row.get("no_municipio") or "").strip()
    uf = str(farmacia_row.get("uf") or "").strip().upper()
    if not id_ibge7 or not municipio or not uf:
        raise HTTPException(status_code=500, detail="Perfil sem no_municipio/UF/id_ibge7 para Parkinson.")

    demografia = get_df_dados_ibge_demografia()
    _require_columns(demografia, ["id_ibge7", "ano_censo", "idade_min", "nu_populacao"], "dados_ibge_demografia")
    demo = (
        demografia
        .with_columns(
            pl.col("id_ibge7").cast(pl.Utf8),
            pl.col("ano_censo").cast(pl.Int16, strict=False),
            pl.col("idade_min").cast(pl.Int16, strict=False),
            pl.col("nu_populacao").cast(pl.Int64, strict=False),
        )
        .filter((pl.col("id_ibge7") == id_ibge7) & (pl.col("ano_censo") == _IBGE_ANO_CENSO_DEMOGRAFIA))
    )
    if demo.is_empty():
        raise HTTPException(status_code=500, detail=f"Demografia IBGE ausente para id_ibge7={id_ibge7}.")
    if demo.filter(pl.col("idade_min").is_null() | pl.col("nu_populacao").is_null()).height > 0:
        raise HTTPException(status_code=500, detail=f"Demografia IBGE com idade/populacao nula para id_ibge7={id_ibge7}.")

    pop_total = int(demo.select(pl.sum("nu_populacao")).item() or 0)
    pop_50_mais = int(demo.filter(pl.col("idade_min") >= 50).select(pl.sum("nu_populacao")).item() or 0)
    if pop_total <= 0 or pop_50_mais <= 0:
        raise HTTPException(status_code=500, detail=f"Demografia IBGE invalida para id_ibge7={id_ibge7}.")

    faixas: dict[int, int] = {}
    for row in demo.select(["idade_min", "nu_populacao"]).to_dicts():
        idade = int(row["idade_min"])
        populacao = int(row["nu_populacao"])
        if idade < 0 or populacao < 0:
            raise HTTPException(status_code=500, detail=f"Demografia IBGE invalida para id_ibge7={id_ibge7}.")
        faixa_inicio = 80 if idade >= 80 else (idade // 10) * 10
        faixas[faixa_inicio] = faixas.get(faixa_inicio, 0) + populacao

    casos_esperados = pop_50_mais * _PARKINSON_PREVALENCIA_50_MAIS
    faixas_etarias = [
        ClinicoFaixaEtariaSchema(
            faixa="80+" if faixa >= 80 else f"{faixa} a {faixa + 9}",
            faixa_inicio=faixa,
            populacao=populacao,
            percentual=populacao / pop_total,
            destacar_50_mais=faixa >= 50,
        )
        for faixa, populacao in sorted(faixas.items())
    ]

    return ClinicoParkinsonDemografiaSchema(
        municipio=municipio,
        uf=uf,
        ano_censo=_IBGE_ANO_CENSO_DEMOGRAFIA,
        ano_observado=observacao.ano_base,
        prevalencia_50_mais=_PARKINSON_PREVALENCIA_50_MAIS,
        populacao_total=pop_total,
        populacao_50_mais=pop_50_mais,
        casos_esperados=casos_esperados,
        cpfs_observados=observacao.qtd_cpfs_distintos,
        razao_observado_esperado=observacao.qtd_cpfs_distintos / casos_esperados if casos_esperados > 0 else None,
        faixas_etarias=faixas_etarias,
    )


def get_incompatibilidade_patologica_data(
    cnpj: str,
    data_inicio: date | None = None,
    data_fim: date | None = None,
    ranking_municipal_limite: int = 10,
) -> ClinicoIncompatibilidadeResponse:
    if ranking_municipal_limite < 0:
        raise HTTPException(status_code=422, detail="ranking_municipal_limite deve ser maior ou igual a zero.")

    clean_cnpj = _clean_cnpj(cnpj)
    if len(clean_cnpj) != 14:
        raise HTTPException(status_code=422, detail="CNPJ deve conter 14 digitos.")

    perfil = get_df_perfil_estabelecimento()
    _require_columns(perfil, ["id_cnpj", "cnpj", "id_ibge7", "no_municipio", "uf", "razao_social"], "perfil_estabelecimento")
    perfil_cnpj = (
        perfil
        .with_columns(pl.col("cnpj").cast(pl.Utf8).str.replace_all(r"\D", "").str.zfill(14).alias("_cnpj_limpo"))
        .filter(pl.col("_cnpj_limpo") == clean_cnpj)
    )
    if perfil_cnpj.is_empty():
        raise HTTPException(status_code=404, detail="CNPJ nao encontrado no perfil de estabelecimentos.")
    farmacia_row = perfil_cnpj.row(0, named=True)
    id_cnpj = int(farmacia_row["id_cnpj"])
    id_ibge7 = str(farmacia_row["id_ibge7"] or "").strip()
    if not id_ibge7:
        raise HTTPException(status_code=500, detail="Perfil de estabelecimento sem id_ibge7.")

    clinica_scan = scan_analise_gtin_inconsistencia_clinica()
    _require_lazy_columns(clinica_scan, _CLINICA_COLUNAS_OBRIGATORIAS, "analise_gtin_inconsistencia_clinica")

    clinica = clinica_scan.filter(pl.col("id_cnpj") == id_cnpj)
    if data_inicio:
        clinica = clinica.filter(pl.col("ano_base") >= data_inicio.year)
    if data_fim:
        clinica = clinica.filter(pl.col("ano_base") <= data_fim.year)

    clinica_df = clinica.collect()
    _require_columns(clinica_df, _CLINICA_COLUNAS_OBRIGATORIAS, "analise_gtin_inconsistencia_clinica")

    if clinica_df.is_empty():
        summary_row = {
            "qtd_cpfs_distintos": 0,
            "qtd_cpfs_incompativeis": 0,
            "qtd_autorizacoes": 0,
            "qtd_autorizacoes_incompativeis": 0,
            "valor_total_pago": 0,
            "valor_incompativel_pago": 0,
        }
        clinica_incompativel = clinica_df
    else:
        summary_row = (
            clinica_df
            .select(
                pl.sum("qtd_cpfs_distintos").alias("qtd_cpfs_distintos"),
                pl.sum("qtd_cpfs_incompativeis").alias("qtd_cpfs_incompativeis"),
                pl.sum("qtd_autorizacoes").alias("qtd_autorizacoes"),
                pl.sum("qtd_autorizacoes_incompativeis").alias("qtd_autorizacoes_incompativeis"),
                pl.sum("valor_total_pago").alias("valor_total_pago"),
                pl.sum("valor_incompativel_pago").alias("valor_incompativel_pago"),
            )
            .row(0, named=True)
        )
        clinica_incompativel = clinica_df.filter(pl.col("qtd_cpfs_incompativeis") > 0)
    valor_total = float(summary_row["valor_total_pago"] or 0)
    valor_incompativel = float(summary_row["valor_incompativel_pago"] or 0)
    summary = ClinicoIncompatibilidadeSummarySchema(
        qtd_cpfs_distintos=int(summary_row["qtd_cpfs_distintos"] or 0),
        qtd_cpfs_incompativeis=int(summary_row["qtd_cpfs_incompativeis"] or 0),
        qtd_autorizacoes=int(summary_row["qtd_autorizacoes"] or 0),
        qtd_autorizacoes_incompativeis=int(summary_row["qtd_autorizacoes_incompativeis"] or 0),
        valor_total_pago=valor_total,
        valor_incompativel_pago=valor_incompativel,
        percentual_valor_incompativel=(valor_incompativel / valor_total * 100) if valor_total > 0 else None,
    )

    ranking_df = (
        clinica_incompativel
        .group_by(["patologia", "regra_clinica"])
        .agg(
            pl.sum("qtd_cpfs_distintos").alias("qtd_cpfs_distintos"),
            pl.sum("qtd_cpfs_incompativeis").alias("qtd_cpfs_incompativeis"),
            pl.sum("qtd_autorizacoes").alias("qtd_autorizacoes"),
            pl.sum("qtd_autorizacoes_incompativeis").alias("qtd_autorizacoes_incompativeis"),
            pl.sum("valor_total_pago").alias("valor_total_pago"),
            pl.sum("valor_incompativel_pago").alias("valor_incompativel_pago"),
            pl.sum("cpfs_incompativeis_esperados_regiao").alias("cpfs_incompativeis_esperados_regiao"),
            pl.sum("excesso_cpfs_incompativeis_vs_regiao").alias("excesso_cpfs_incompativeis_vs_regiao"),
            pl.mean("percentual_cpfs_incompativeis").alias("percentual_medio_cpfs_incompativeis"),
            pl.mean("percentual_regional_cpfs_incompativeis").alias("percentual_medio_regional_cpfs_incompativeis"),
            pl.mean("razao_percentual_vs_regiao").alias("razao_media_percentual_vs_regiao"),
            pl.min("rank_regional_qtd_cpfs_incompativeis").alias("melhor_rank_regional_qtd_cpfs_incompativeis"),
            pl.max("percentil_regional_qtd_cpfs_incompativeis").alias("maior_percentil_regional_qtd_cpfs_incompativeis"),
            pl.max("participacao_cpfs_incompativeis_regiao").alias("maior_participacao_cpfs_incompativeis_regiao"),
            pl.min("ano_base").alias("ano_inicio"),
            pl.max("ano_base").alias("ano_fim"),
            pl.len().alias("qtd_linhas_anuais"),
        )
        .filter(pl.col("valor_incompativel_pago") >= CLINICA_VALOR_MINIMO_DETALHAMENTO)
    )
    ranking_items = list(ranking_df.iter_rows(named=True))

    clinica_municipio_df = pl.DataFrame()
    if ranking_items:
        raw_keys = [
            _clinica_raw_key_value(item["patologia"], item["regra_clinica"])
            for item in ranking_items
        ]
        clinica_municipio = (
            clinica_scan
            .filter(pl.col("id_ibge7").cast(pl.Utf8) == id_ibge7)
            .filter(_clinica_raw_key_expr().is_in(raw_keys))
        )
        if data_inicio:
            clinica_municipio = clinica_municipio.filter(pl.col("ano_base") >= data_inicio.year)
        if data_fim:
            clinica_municipio = clinica_municipio.filter(pl.col("ano_base") <= data_fim.year)
        clinica_municipio_df = clinica_municipio.collect()
        _require_columns(
            clinica_municipio_df,
            _CLINICA_COLUNAS_OBRIGATORIAS,
            "analise_gtin_inconsistencia_clinica municipal",
        )

    patologias: list[ClinicoPatologiaSchema] = []
    for item in ranking_items:
        key = _clinica_meta_key(item["patologia"], item["regra_clinica"])
        meta = _CLINICA_PATOLOGIA_META.get(key)
        if meta is None:
            raise HTTPException(
                status_code=500,
                detail=(
                    "Recorte clinico sem mapeamento textual: "
                    f"patologia={item['patologia']}; regra={item['regra_clinica']}."
                ),
            )

        evolucao_rows = [
            row
            for row in clinica_df.iter_rows(named=True)
            if _clinica_meta_key(row["patologia"], row["regra_clinica"]) == key
        ]
        evolucao = [
            ClinicoEvolucaoAnualSchema(
                ano_base=int(row["ano_base"]),
                qtd_cpfs_distintos=int(row["qtd_cpfs_distintos"] or 0),
                qtd_cpfs_incompativeis=int(row["qtd_cpfs_incompativeis"] or 0),
                qtd_autorizacoes=int(row["qtd_autorizacoes"] or 0),
                qtd_autorizacoes_incompativeis=int(row["qtd_autorizacoes_incompativeis"] or 0),
                valor_total_pago=float(row["valor_total_pago"] or 0),
                valor_incompativel_pago=float(row["valor_incompativel_pago"] or 0),
                percentual_cpfs_incompativeis=float(row["percentual_cpfs_incompativeis"] or 0),
                percentual_autorizacoes_incompativeis=_ratio(
                    row["qtd_autorizacoes_incompativeis"],
                    row["qtd_autorizacoes"],
                ),
            )
            for row in sorted(evolucao_rows, key=lambda value: int(value["ano_base"]))
        ]
        municipal_resumo, ranking_municipal = _build_municipal_context(
            item,
            clinica_municipio_df,
            perfil,
            id_cnpj,
            ranking_municipal_limite=ranking_municipal_limite,
        )
        demografia = (
            _build_parkinson_demografia(farmacia_row, evolucao)
            if key == ("DOENCA DE PARKINSON", "IDADE_MENOR_50")
            else None
        )
        patologias.append(
            ClinicoPatologiaSchema(
                patologia=str(item["patologia"]),
                regra_clinica=str(item["regra_clinica"]),
                titulo=meta["titulo"],
                objeto=meta["objeto"],
                criterio=meta["criterio"],
                descricao=meta["descricao"],
                ano_inicio=int(item["ano_inicio"]),
                ano_fim=int(item["ano_fim"]),
                qtd_cpfs_distintos=int(item["qtd_cpfs_distintos"] or 0),
                qtd_cpfs_incompativeis=int(item["qtd_cpfs_incompativeis"] or 0),
                qtd_autorizacoes=int(item["qtd_autorizacoes"] or 0),
                qtd_autorizacoes_incompativeis=int(item["qtd_autorizacoes_incompativeis"] or 0),
                valor_total_pago=float(item["valor_total_pago"] or 0),
                valor_incompativel_pago=float(item["valor_incompativel_pago"] or 0),
                percentual_medio_cpfs_incompativeis=float(item["percentual_medio_cpfs_incompativeis"] or 0),
                percentual_medio_regional_cpfs_incompativeis=(
                    float(item["percentual_medio_regional_cpfs_incompativeis"])
                    if item["percentual_medio_regional_cpfs_incompativeis"] is not None
                    else None
                ),
                razao_media_percentual_vs_regiao=(
                    float(item["razao_media_percentual_vs_regiao"])
                    if item["razao_media_percentual_vs_regiao"] is not None
                    else None
                ),
                excesso_cpfs_incompativeis_vs_regiao=(
                    float(item["excesso_cpfs_incompativeis_vs_regiao"])
                    if item["excesso_cpfs_incompativeis_vs_regiao"] is not None
                    else None
                ),
                melhor_rank_regional_qtd_cpfs_incompativeis=(
                    int(item["melhor_rank_regional_qtd_cpfs_incompativeis"])
                    if item["melhor_rank_regional_qtd_cpfs_incompativeis"] is not None
                    else None
                ),
                maior_percentil_regional_qtd_cpfs_incompativeis=(
                    float(item["maior_percentil_regional_qtd_cpfs_incompativeis"])
                    if item["maior_percentil_regional_qtd_cpfs_incompativeis"] is not None
                    else None
                ),
                maior_participacao_cpfs_incompativeis_regiao=(
                    float(item["maior_participacao_cpfs_incompativeis_regiao"])
                    if item["maior_participacao_cpfs_incompativeis_regiao"] is not None
                    else None
                ),
                evolucao_anual=evolucao,
                municipal_resumo=municipal_resumo,
                ranking_municipal=ranking_municipal,
                demografia_parkinson=demografia,
            )
        )

    patologias.sort(
        key=lambda item: (
            item.excesso_cpfs_incompativeis_vs_regiao if item.excesso_cpfs_incompativeis_vs_regiao is not None else -1,
            item.qtd_cpfs_incompativeis,
            item.valor_incompativel_pago,
            item.percentual_medio_cpfs_incompativeis,
        ),
        reverse=True,
    )

    return ClinicoIncompatibilidadeResponse(
        cnpj=clean_cnpj,
        razao_social=str(farmacia_row["razao_social"]),
        municipio=str(farmacia_row["no_municipio"]),
        uf=str(farmacia_row["uf"]).upper(),
        periodo_inicio=data_inicio,
        periodo_fim=data_fim,
        periodo_label=_periodo_label(data_inicio, data_fim),
        summary=summary,
        patologias=patologias,
    )
