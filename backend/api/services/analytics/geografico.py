from datetime import date
from typing import Iterable, Literal, TypedDict

import polars as pl
from fastapi import HTTPException

from data_cache import get_df_perfil_estabelecimento, scan_geografico_origem_uf
from ...schemas.analytics import (
    GeograficoBenchmarkResponse,
    GeograficoBenchmarkRowSchema,
    GeograficoBenchmarkScopeSchema,
    GeograficoOrigemUfResponse,
    GeograficoOrigemUfRowSchema,
)
from .matriz_risco_dinamica import build_dynamic_matriz_risco

LIMIAR_ALERTA_UF_NAO_VIZINHA_PCT = 5.0

UF_VIZINHAS: dict[str, set[str]] = {
    "AC": {"AM", "RO"},
    "AL": {"BA", "PE", "SE"},
    "AM": {"AC", "MT", "PA", "RO", "RR"},
    "AP": {"PA"},
    "BA": {"AL", "ES", "GO", "MG", "PE", "PI", "SE", "TO"},
    "CE": {"PB", "PE", "PI", "RN"},
    "DF": {"GO"},
    "ES": {"BA", "MG", "RJ"},
    "GO": {"BA", "DF", "MG", "MS", "MT", "TO"},
    "MA": {"PA", "PI", "TO"},
    "MG": {"BA", "ES", "GO", "MS", "RJ", "SP"},
    "MS": {"GO", "MG", "MT", "PR", "SP"},
    "MT": {"AM", "GO", "MS", "PA", "RO", "TO"},
    "PA": {"AM", "AP", "MA", "MT", "RR", "TO"},
    "PB": {"CE", "PE", "RN"},
    "PE": {"AL", "BA", "CE", "PB", "PI"},
    "PI": {"BA", "CE", "MA", "PE", "TO"},
    "PR": {"MS", "SC", "SP"},
    "RJ": {"ES", "MG", "SP"},
    "RN": {"CE", "PB"},
    "RO": {"AC", "AM", "MT"},
    "RR": {"AM", "PA"},
    "RS": {"SC"},
    "SC": {"PR", "RS"},
    "SE": {"AL", "BA"},
    "SP": {"MG", "MS", "PR", "RJ"},
    "TO": {"BA", "GO", "MA", "MT", "PA", "PI"},
}

UF_BRASILEIRAS = set(UF_VIZINHAS)


class AlertaUfNaoVizinha(TypedDict):
    is_dispersao_uf_nao_vizinha: bool
    pct_dispersao_uf_nao_vizinha: float
    valor_dispersao_uf_nao_vizinha: float


def _clean_cnpj(value: str) -> str:
    return "".join(ch for ch in str(value or "") if ch.isdigit())


def _require_columns(df: pl.DataFrame, columns: Iterable[str], source: str) -> None:
    missing = [column for column in columns if column not in df.columns]
    if missing:
        raise HTTPException(
            status_code=500,
            detail=f"Contrato de cache invalido em {source}. Colunas ausentes: {', '.join(missing)}.",
        )


def _normalizar_uf(value: object) -> str:
    uf = str(value or "").strip().upper()
    if uf not in UF_BRASILEIRAS:
        raise HTTPException(status_code=500, detail=f"UF de farmacia invalida para alerta geografico: {uf}.")
    return uf


def calcular_alerta_uf_nao_vizinha(
    id_cnpj: int,
    uf_farmacia: str,
    data_inicio: date | None = None,
    data_fim: date | None = None,
) -> AlertaUfNaoVizinha:
    uf_origem = _normalizar_uf(uf_farmacia)
    required = ["id_cnpj", "ano_base", "uf_paciente", "valor_autorizado"]
    origem_scan = scan_geografico_origem_uf()
    missing = [column for column in required if column not in origem_scan.collect_schema().names()]
    if missing:
        raise HTTPException(
            status_code=500,
            detail=f"Contrato de cache invalido em geografico_origem_uf. Colunas ausentes: {', '.join(missing)}.",
        )

    origem = origem_scan.filter(pl.col("id_cnpj") == id_cnpj).select(required)
    if data_inicio:
        origem = origem.filter(pl.col("ano_base") >= int(data_inicio.year))
    if data_fim:
        origem = origem.filter(pl.col("ano_base") <= int(data_fim.year))

    origem_df = origem.collect()
    _require_columns(origem_df, required, "geografico_origem_uf")
    if origem_df.is_empty():
        return {
            "is_dispersao_uf_nao_vizinha": False,
            "pct_dispersao_uf_nao_vizinha": 0.0,
            "valor_dispersao_uf_nao_vizinha": 0.0,
        }

    total_valor = float(
        origem_df.select(pl.col("valor_autorizado").cast(pl.Float64).sum()).item() or 0
    )
    if total_valor <= 0:
        return {
            "is_dispersao_uf_nao_vizinha": False,
            "pct_dispersao_uf_nao_vizinha": 0.0,
            "valor_dispersao_uf_nao_vizinha": 0.0,
        }

    ufs_proximas = UF_VIZINHAS[uf_origem] | {uf_origem}
    ufs_distantes = sorted(UF_BRASILEIRAS - ufs_proximas)
    valor_distante = float(
        origem_df.with_columns(
            pl.col("uf_paciente").cast(pl.Utf8).str.strip_chars().str.to_uppercase().alias("uf_paciente_norm")
        )
        .filter(pl.col("uf_paciente_norm").is_in(ufs_distantes))
        .select(pl.col("valor_autorizado").cast(pl.Float64).sum())
        .item()
        or 0
    )
    percentual = (valor_distante / total_valor * 100) if total_valor > 0 else 0.0
    return {
        "is_dispersao_uf_nao_vizinha": percentual > LIMIAR_ALERTA_UF_NAO_VIZINHA_PCT,
        "pct_dispersao_uf_nao_vizinha": percentual,
        "valor_dispersao_uf_nao_vizinha": valor_distante,
    }


def _row_schema(row: dict) -> GeograficoOrigemUfRowSchema:
    percentual_outra_uf = row.get("percentual_sobre_outra_uf")
    return GeograficoOrigemUfRowSchema(
        uf_farmacia=str(row["uf_farmacia"]),
        uf_paciente=str(row["uf_paciente"]),
        is_outra_uf=bool(row["is_outra_uf"]),
        qtd_autorizacoes=int(row["qtd_autorizacoes"] or 0),
        valor_autorizado=float(row["valor_autorizado"] or 0),
        percentual_sobre_total=float(row["percentual_sobre_total"] or 0),
        percentual_sobre_outra_uf=(
            float(percentual_outra_uf) if percentual_outra_uf is not None else None
        ),
    )


def _status_dispersao(row: dict) -> str:
    if int(row.get("flag_dispersao_geografica_critico") or 0) == 1:
        return "CRITICO"
    if int(row.get("flag_dispersao_geografica_atencao") or 0) == 1:
        return "ATENCAO"
    if row.get("pct_geografico") is None:
        return "SEM DADOS"
    return "NORMAL"


def _benchmark_row_schema(row: dict, cnpj_alvo: str) -> GeograficoBenchmarkRowSchema:
    return GeograficoBenchmarkRowSchema(
        cnpj=str(row["cnpj"]),
        razao_social=row.get("razao_social"),
        nome_fantasia=row.get("nome_fantasia"),
        municipio=row.get("no_municipio"),
        uf=row.get("uf"),
        percentual_outra_uf=(
            float(row["pct_geografico"]) if row.get("pct_geografico") is not None else None
        ),
        valor_total=float(row.get("geografico_valor_total") or 0),
        valor_outra_uf=float(row.get("geografico_valor_outra_uf") or 0),
        qtd_vendas_outra_uf=int(row.get("geografico_qtd_vendas_outra_uf") or 0),
        mediana_regiao=(
            float(row["med_geografico_reg"]) if row.get("med_geografico_reg") is not None else None
        ),
        mediana_uf=(
            float(row["med_geografico_uf"]) if row.get("med_geografico_uf") is not None else None
        ),
        risco_regiao=(
            float(row["risco_geografico_reg"]) if row.get("risco_geografico_reg") is not None else None
        ),
        risco_uf=(
            float(row["risco_geografico_uf"]) if row.get("risco_geografico_uf") is not None else None
        ),
        status=_status_dispersao(row),
        is_alvo=str(row["cnpj"]) == cnpj_alvo,
    )


def _benchmark_scope_schema(
    *,
    escopo: Literal["municipio", "regiao_saude"],
    label: str,
    rows_df: pl.DataFrame,
    cnpj_alvo: str,
) -> GeograficoBenchmarkScopeSchema:
    rows = [
        _benchmark_row_schema(row, cnpj_alvo)
        for row in rows_df.iter_rows(named=True)
    ]
    return GeograficoBenchmarkScopeSchema(
        escopo=escopo,
        label=label,
        total_estabelecimentos=len(rows),
        rows=rows,
    )


def get_geografico_benchmark_local(
    cnpj: str,
    data_inicio: date | None = None,
    data_fim: date | None = None,
) -> GeograficoBenchmarkResponse:
    clean_cnpj = _clean_cnpj(cnpj)
    if len(clean_cnpj) != 14:
        raise HTTPException(status_code=422, detail="CNPJ deve conter 14 digitos.")

    perfil = get_df_perfil_estabelecimento()
    perfil_required = [
        "id_cnpj",
        "cnpj",
        "razao_social",
        "no_municipio",
        "uf",
        "id_ibge7",
        "id_regiao_saude",
    ]
    _require_columns(perfil, perfil_required, "perfil_estabelecimento")
    perfil_target = perfil.filter(pl.col("cnpj") == clean_cnpj).select(perfil_required)
    if perfil_target.is_empty():
        raise HTTPException(status_code=404, detail="CNPJ nao encontrado no perfil de estabelecimentos.")

    target = perfil_target.row(0, named=True)
    id_ibge7 = int(target["id_ibge7"])
    id_regiao_saude = str(target["id_regiao_saude"])
    municipio_label = f'{target["no_municipio"]}/{target["uf"]}'
    regiao_label = f'Regiao de Saude {id_regiao_saude}/{target["uf"]}'

    matriz = build_dynamic_matriz_risco(data_inicio=data_inicio, data_fim=data_fim)
    matriz_required = [
        "id_cnpj",
        "pct_geografico",
        "med_geografico_reg",
        "med_geografico_uf",
        "risco_geografico_reg",
        "risco_geografico_uf",
        "geografico_valor_total",
        "geografico_valor_outra_uf",
        "geografico_qtd_vendas_outra_uf",
        "flag_dispersao_geografica_atencao",
        "flag_dispersao_geografica_critico",
    ]
    _require_columns(matriz, matriz_required, "matriz_risco_dinamica")

    base = (
        matriz.select(matriz_required)
        .join(perfil.select(perfil_required), on="id_cnpj", how="inner")
        .with_columns([
            pl.col("id_regiao_saude").cast(pl.Utf8),
            pl.col("id_ibge7").cast(pl.Int64),
            pl.col("pct_geografico").cast(pl.Float64),
            pl.col("geografico_valor_outra_uf").cast(pl.Float64),
        ])
        .sort(
            ["pct_geografico", "geografico_valor_outra_uf", "cnpj"],
            descending=[True, True, False],
            nulls_last=True,
        )
    )

    municipio_df = base.filter(pl.col("id_ibge7") == id_ibge7)
    regiao_df = base.filter(pl.col("id_regiao_saude") == id_regiao_saude)

    return GeograficoBenchmarkResponse(
        cnpj=clean_cnpj,
        periodo_inicio=data_inicio,
        periodo_fim=data_fim,
        municipio=_benchmark_scope_schema(
            escopo="municipio",
            label=municipio_label,
            rows_df=municipio_df,
            cnpj_alvo=clean_cnpj,
        ),
        regiao_saude=_benchmark_scope_schema(
            escopo="regiao_saude",
            label=regiao_label,
            rows_df=regiao_df,
            cnpj_alvo=clean_cnpj,
        ),
    )


def get_geografico_origem_uf(
    cnpj: str,
    data_inicio: date | None = None,
    data_fim: date | None = None,
) -> GeograficoOrigemUfResponse:
    clean_cnpj = _clean_cnpj(cnpj)
    if len(clean_cnpj) != 14:
        raise HTTPException(status_code=422, detail="CNPJ deve conter 14 digitos.")

    perfil = get_df_perfil_estabelecimento()
    _require_columns(perfil, ["id_cnpj", "cnpj", "uf"], "perfil_estabelecimento")
    perfil_cnpj = perfil.filter(pl.col("cnpj") == clean_cnpj).select(["id_cnpj", "cnpj", "uf"])
    if perfil_cnpj.is_empty():
        raise HTTPException(status_code=404, detail="CNPJ nao encontrado no perfil de estabelecimentos.")

    perfil_row = perfil_cnpj.row(0, named=True)
    id_cnpj = int(perfil_row["id_cnpj"])
    uf_perfil = str(perfil_row["uf"]).upper()

    required = [
        "id_cnpj",
        "ano_base",
        "uf_farmacia",
        "uf_paciente",
        "is_outra_uf",
        "qtd_autorizacoes",
        "valor_autorizado",
    ]
    origem_scan = scan_geografico_origem_uf()
    missing = [column for column in required if column not in origem_scan.collect_schema().names()]
    if missing:
        raise HTTPException(
            status_code=500,
            detail=f"Contrato de cache invalido em geografico_origem_uf. Colunas ausentes: {', '.join(missing)}.",
        )

    origem = origem_scan.filter(pl.col("id_cnpj") == id_cnpj).select(required)
    if data_inicio:
        origem = origem.filter(pl.col("ano_base") >= int(data_inicio.year))
    if data_fim:
        origem = origem.filter(pl.col("ano_base") <= int(data_fim.year))

    origem_df = origem.collect()
    _require_columns(origem_df, required, "geografico_origem_uf")
    if origem_df.is_empty():
        raise HTTPException(status_code=404, detail="CNPJ sem detalhamento geografico por UF no periodo.")

    agg_df = (
        origem_df.group_by(["uf_farmacia", "uf_paciente", "is_outra_uf"])
        .agg(
            [
                pl.col("qtd_autorizacoes").cast(pl.Int64).sum().alias("qtd_autorizacoes"),
                pl.col("valor_autorizado").cast(pl.Float64).sum().alias("valor_autorizado"),
            ]
        )
        .sort("valor_autorizado", descending=True)
    )

    total_valor = float(agg_df.select(pl.sum("valor_autorizado")).item() or 0)
    total_autorizacoes = int(agg_df.select(pl.sum("qtd_autorizacoes")).item() or 0)
    if total_valor <= 0:
        raise HTTPException(status_code=422, detail="Detalhamento geografico sem valor autorizado positivo.")

    total_outra_uf = float(
        agg_df.filter(pl.col("is_outra_uf")).select(pl.sum("valor_autorizado")).item() or 0
    )
    autorizacoes_outra_uf = int(
        agg_df.filter(pl.col("is_outra_uf")).select(pl.sum("qtd_autorizacoes")).item() or 0
    )

    rows_df = agg_df.with_columns(
        [
            (pl.col("valor_autorizado") / total_valor * 100).alias("percentual_sobre_total"),
            pl.when(pl.col("is_outra_uf") & (pl.lit(total_outra_uf) > 0))
            .then(pl.col("valor_autorizado") / total_outra_uf * 100)
            .otherwise(None)
            .alias("percentual_sobre_outra_uf"),
        ]
    )

    rows = [_row_schema(row) for row in rows_df.to_dicts()]
    principal_df = rows_df.filter(pl.col("is_outra_uf")).head(1)
    principal_uf_externa = (
        _row_schema(principal_df.row(0, named=True)) if not principal_df.is_empty() else None
    )

    return GeograficoOrigemUfResponse(
        cnpj=clean_cnpj,
        uf_farmacia=uf_perfil,
        periodo_inicio=data_inicio,
        periodo_fim=data_fim,
        total_valor_origem=total_valor,
        total_valor_outra_uf=total_outra_uf,
        total_autorizacoes_origem=total_autorizacoes,
        total_autorizacoes_outra_uf=autorizacoes_outra_uf,
        percentual_financeiro_outra_uf=(total_outra_uf / total_valor * 100) if total_valor > 0 else 0,
        principal_uf_externa=principal_uf_externa,
        rows=rows,
    )
