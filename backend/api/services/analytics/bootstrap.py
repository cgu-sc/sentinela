from datetime import date
from decimal import Decimal, InvalidOperation
from typing import Iterable

import polars as pl
from fastapi import HTTPException

from data_cache import (
    get_df,
    get_df_dados_farmacia,
    get_df_perfil_estabelecimento,
    get_localidades_df,
)
from .farmacia import get_cnaes_secundarios_farmacia
from .matriz_risco_dinamica import build_dynamic_matriz_risco
from ...schemas.analytics import (
    CnpjAccessStatusSchema,
    CnpjBootstrapResponse,
    CnpjGeoDataSchema,
    CnpjPeriodSummarySchema,
    DadosFarmaciaSchema,
    ResultadoSentinelaCnpjSchema,
)


def _clean_cnpj(value: str) -> str:
    return "".join(ch for ch in str(value or "") if ch.isdigit())


def _require_columns(df: pl.DataFrame, columns: Iterable[str], source: str) -> None:
    missing = [column for column in columns if column not in df.columns]
    if missing:
        raise HTTPException(
            status_code=500,
            detail=f"Contrato de cache invalido em {source}. Colunas ausentes: {', '.join(missing)}.",
        )


def _first_row(df: pl.DataFrame, description: str) -> dict:
    if df.is_empty():
        raise HTTPException(status_code=404, detail=f"{description} nao encontrado.")
    return df.row(0, named=True)


def _period_summary(
    id_cnpj: int,
    data_inicio: date | None,
    data_fim: date | None,
) -> CnpjPeriodSummarySchema:
    df = get_df()
    _require_columns(
        df,
        [
            "id_cnpj",
            "periodo",
            "total_vendas",
            "total_sem_comprovacao",
            "total_qnt_caixas_vendidas",
            "total_qnt_caixas_sem_comprovacao",
        ],
        "movimentacao",
    )

    cnpj_df = df.filter(pl.col("id_cnpj") == id_cnpj)
    if data_inicio:
        cnpj_df = cnpj_df.filter(pl.col("periodo") >= pl.lit(data_inicio).cast(pl.Date))
    if data_fim:
        cnpj_df = cnpj_df.filter(pl.col("periodo") <= pl.lit(data_fim).cast(pl.Date))

    if cnpj_df.is_empty():
        return CnpjPeriodSummarySchema()

    row = cnpj_df.select(
        [
            pl.sum("total_vendas").alias("totalMov"),
            pl.sum("total_sem_comprovacao").alias("valSemComp"),
            pl.col("total_qnt_caixas_vendidas").cast(pl.Int64).sum().alias("totalQtde"),
            pl.col("total_qnt_caixas_sem_comprovacao").cast(pl.Int64).sum().alias("qtdeSemComp"),
        ]
    ).with_columns(
        [
            (
                pl.col("valSemComp")
                / pl.when(pl.col("totalMov") > 0).then(pl.col("totalMov")).otherwise(None)
                * 100
            ).fill_null(0).alias("percValSemComp"),
            (
                pl.col("qtdeSemComp")
                / pl.when(pl.col("totalQtde") > 0).then(pl.col("totalQtde")).otherwise(None)
                * 100
            ).fill_null(0).alias("percQtdeSemComp"),
        ]
    ).row(0, named=True)

    return CnpjPeriodSummarySchema(
        totalMov=float(row["totalMov"] or 0),
        valSemComp=float(row["valSemComp"] or 0),
        percValSemComp=float(row["percValSemComp"] or 0),
        totalQtde=int(row["totalQtde"] or 0),
        qtdeSemComp=int(row["qtdeSemComp"] or 0),
        percQtdeSemComp=float(row["percQtdeSemComp"] or 0),
    )


def _scope_total(df: pl.DataFrame, scope_col: str | None, scope_value: object) -> int | None:
    if df.is_empty() or "score_risco_final" not in df.columns:
        return None

    scoped = df
    if scope_col:
        if scope_col not in df.columns or scope_value is None:
            return None
        scoped = scoped.filter(pl.col(scope_col).cast(pl.Utf8) == str(scope_value))

    return int(
        scoped.select(pl.col("score_risco_final").is_not_null().sum().alias("total"))
        .item()
        or 0
    )


def _optional_float(value: object, field_name: str) -> float | None:
    if value is None:
        return None
    if isinstance(value, bool):
        raise HTTPException(status_code=500, detail=f"Campo {field_name} deve ser numerico.")
    if isinstance(value, (int, float, Decimal)):
        return float(value)
    if isinstance(value, str):
        try:
            return float(Decimal(value.strip()))
        except (InvalidOperation, ValueError):
            raise HTTPException(status_code=500, detail=f"Campo {field_name} deve ser numerico.")
    raise HTTPException(status_code=500, detail=f"Campo {field_name} deve ser numerico.")


def _optional_int(value: object, field_name: str) -> int | None:
    if value is None:
        return None
    if isinstance(value, bool):
        raise HTTPException(status_code=500, detail=f"Campo {field_name} deve ser inteiro.")
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        if value.is_integer():
            return int(value)
        raise HTTPException(status_code=500, detail=f"Campo {field_name} deve ser inteiro.")
    if isinstance(value, Decimal):
        try:
            if value == value.to_integral_value():
                return int(value)
        except InvalidOperation:
            pass
        raise HTTPException(status_code=500, detail=f"Campo {field_name} deve ser inteiro.")
    if isinstance(value, str):
        try:
            parsed = Decimal(value.strip())
            if parsed == parsed.to_integral_value():
                return int(parsed)
        except (InvalidOperation, ValueError):
            pass
        raise HTTPException(status_code=500, detail=f"Campo {field_name} deve ser inteiro.")
    raise HTTPException(status_code=500, detail=f"Campo {field_name} deve ser inteiro.")


def _optional_str(value: object, field_name: str) -> str | None:
    if value is None:
        return None
    if isinstance(value, str):
        return value
    raise HTTPException(status_code=500, detail=f"Campo {field_name} deve ser texto.")


def _risk_row(
    cnpj: str,
    uf: str | None,
    id_regiao_saude: int | str | None,
    id_ibge7: int | str | None,
    data_inicio: date | None,
    data_fim: date | None,
) -> dict[str, object]:
    risco_df = build_dynamic_matriz_risco(
        data_inicio=data_inicio,
        data_fim=data_fim,
    )
    required = [
        "cnpj",
        "score_risco_final",
        "classificacao_risco",
        "rank_nacional",
        "total_nacional",
        "rank_uf",
        "total_uf",
        "rank_regiao_saude",
        "total_regiao_saude",
        "rank_municipio",
        "total_municipio",
    ]
    _require_columns(risco_df, required, "matriz_risco_dinamica")
    row_df = risco_df.filter(pl.col("cnpj") == cnpj).select(required)
    if row_df.is_empty():
        totals: dict[str, object] = {column: None for column in required}
        totals["cnpj"] = cnpj
        totals["total_nacional"] = _scope_total(risco_df, None, None)
        totals["total_uf"] = _scope_total(risco_df, "uf", uf)
        totals["total_regiao_saude"] = _scope_total(risco_df, "id_regiao_saude", id_regiao_saude)
        totals["total_municipio"] = _scope_total(risco_df, "id_ibge7", id_ibge7)
        return totals

    row = _first_row(row_df, "Registro da matriz dinamica de risco para CNPJ")
    return row


def _geo_row(perfil_row: dict) -> tuple[CnpjGeoDataSchema, int]:
    id_ibge7 = perfil_row.get("id_ibge7")
    if id_ibge7 is None:
        raise HTTPException(status_code=422, detail="CNPJ sem id_ibge7 obrigatorio para bootstrap.")

    localidades = get_localidades_df()
    required = [
        "sg_uf",
        "no_regiao_saude",
        "id_regiao_saude",
        "no_municipio",
        "id_ibge7",
        "nu_populacao",
        "unidade_pf",
    ]
    _require_columns(localidades, required, "localidades")

    geo_df = localidades.filter(pl.col("id_ibge7").cast(pl.Int64) == int(id_ibge7)).select(required)
    geo = _first_row(geo_df, "Localidade do CNPJ")
    regiao_id = geo.get("id_regiao_saude")
    if regiao_id is None:
        raise HTTPException(status_code=422, detail="Localidade sem id_regiao_saude obrigatorio.")

    qtd_municipios_regiao = localidades.filter(
        pl.col("id_regiao_saude").cast(pl.Int64) == int(regiao_id)
    ).select(pl.n_unique("id_ibge7")).item()

    return (
        CnpjGeoDataSchema(
            sg_uf=str(geo["sg_uf"]),
            no_regiao_saude=str(geo["no_regiao_saude"]),
            id_regiao_saude=int(regiao_id),
            no_municipio=str(geo["no_municipio"]),
            id_ibge7=int(geo["id_ibge7"]),
            nu_populacao=int(geo["nu_populacao"]) if geo.get("nu_populacao") is not None else None,
            unidade_pf=geo.get("unidade_pf"),
        ),
        int(qtd_municipios_regiao or 0),
    )


def get_cnpj_bootstrap(
    cnpj: str,
    data_inicio: date | None = None,
    data_fim: date | None = None,
) -> CnpjBootstrapResponse:
    clean_cnpj = _clean_cnpj(cnpj)
    if len(clean_cnpj) != 14:
        raise HTTPException(
            status_code=422,
            detail={
                "status": "invalid_format",
                "message": "A tela de estabelecimento aceita apenas CNPJ com 14 digitos.",
                "cnpj": clean_cnpj,
            },
        )

    dados_farmacia = get_df_dados_farmacia()
    _require_columns(
        dados_farmacia,
        ["cnpj", "razao_social", "nome_fantasia", "municipio", "uf"],
        "dados_farmacia",
    )
    cadastro_df = dados_farmacia.filter(pl.col("cnpj") == clean_cnpj)
    if cadastro_df.is_empty():
        raise HTTPException(
            status_code=404,
            detail={
                "status": "not_in_program",
                "message": "CNPJ nao encontrado na base carregada do Programa Farmacia Popular.",
                "cnpj": clean_cnpj,
            },
        )
    cadastro_row = cadastro_df.row(0, named=True)
    perfil = get_df_perfil_estabelecimento()
    perfil_required = [
        "id_cnpj",
        "cnpj",
        "no_municipio",
        "id_ibge7",
        "id_regiao_saude",
        "uf",
        "razao_social",
        "is_grande_rede",
        "qtd_estabelecimentos_rede",
        "situacao_rf",
        "porte_empresa",
        "is_conexao_ativa",
        "is_matriz",
        "is_cnae_incompativel_farmaceutico",
    ]
    _require_columns(perfil, perfil_required, "perfil_estabelecimento")
    perfil_row = _first_row(
        perfil.filter(pl.col("cnpj") == clean_cnpj).select(perfil_required),
        "Perfil do CNPJ",
    )
    is_cnae_incompativel = bool(perfil_row["is_cnae_incompativel_farmaceutico"])

    id_cnpj = int(perfil_row["id_cnpj"])
    period_summary = _period_summary(id_cnpj, data_inicio, data_fim)
    risco = _risk_row(
        clean_cnpj,
        perfil_row.get("uf"),
        perfil_row.get("id_regiao_saude"),
        perfil_row.get("id_ibge7"),
        data_inicio,
        data_fim,
    )
    geo_data, qtd_municipios_regiao = _geo_row(perfil_row)

    cnpj_data = ResultadoSentinelaCnpjSchema(
        municipio_uf=f"{perfil_row['no_municipio']} / {perfil_row['uf']}",
        cnpj=clean_cnpj,
        razao_social=perfil_row.get("razao_social"),
        totalMov=period_summary.totalMov,
        valSemComp=period_summary.valSemComp,
        percValSemComp=period_summary.percValSemComp,
        totalQtde=period_summary.totalQtde,
        qtdeSemComp=period_summary.qtdeSemComp,
        percQtdeSemComp=period_summary.percQtdeSemComp,
        is_grande_rede=bool(perfil_row.get("is_grande_rede")),
        qtd_estabelecimentos_rede=int(perfil_row.get("qtd_estabelecimentos_rede") or 0),
        situacao_rf=perfil_row.get("situacao_rf"),
        porte_empresa=perfil_row.get("porte_empresa"),
        is_conexao_ativa=bool(perfil_row.get("is_conexao_ativa")),
        is_matriz=bool(perfil_row.get("is_matriz")),
        id_ibge7=int(perfil_row["id_ibge7"]),
        score_risco_final=_optional_float(risco.get("score_risco_final"), "score_risco_final"),
        classificacao_risco=_optional_str(risco.get("classificacao_risco"), "classificacao_risco"),
        municipio=perfil_row.get("no_municipio"),
        uf=perfil_row.get("uf"),
        rank_nacional=_optional_int(risco.get("rank_nacional"), "rank_nacional"),
        total_nacional=_optional_int(risco.get("total_nacional"), "total_nacional"),
        rank_uf=_optional_int(risco.get("rank_uf"), "rank_uf"),
        total_uf=_optional_int(risco.get("total_uf"), "total_uf"),
        rank_regiao_saude=_optional_int(risco.get("rank_regiao_saude"), "rank_regiao_saude"),
        total_regiao_saude=_optional_int(risco.get("total_regiao_saude"), "total_regiao_saude"),
        rank_municipio=_optional_int(risco.get("rank_municipio"), "rank_municipio"),
        total_municipio=_optional_int(risco.get("total_municipio"), "total_municipio"),
    )

    cadastro_payload = dict(cadastro_row)
    cadastro_payload["is_cnae_incompativel_farmaceutico"] = is_cnae_incompativel
    cadastro_payload["is_cnae_farmacia_ausente"] = is_cnae_incompativel

    return CnpjBootstrapResponse(
        status=CnpjAccessStatusSchema(
            cnpj=clean_cnpj,
            status="valid",
            in_program=True,
            razao_social=cadastro_row.get("razao_social"),
            nome_fantasia=cadastro_row.get("nome_fantasia"),
            municipio=cadastro_row.get("municipio"),
            uf=cadastro_row.get("uf"),
        ),
        cadastro=DadosFarmaciaSchema(
            **cadastro_payload,
            cnaes_secundarios=get_cnaes_secundarios_farmacia(clean_cnpj),
        ),
        cnpj_data=cnpj_data,
        geo_data=geo_data,
        qtd_municipios_regiao=qtd_municipios_regiao,
        period_summary=period_summary,
    )
