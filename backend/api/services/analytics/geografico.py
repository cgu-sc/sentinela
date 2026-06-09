from datetime import date
from typing import Iterable

import polars as pl
from fastapi import HTTPException

from data_cache import get_df_perfil_estabelecimento, scan_geografico_origem_uf
from ...schemas.analytics import (
    GeograficoOrigemUfResponse,
    GeograficoOrigemUfRowSchema,
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
