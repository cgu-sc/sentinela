from typing import Optional

import polars as pl
from fastapi import HTTPException

from data_cache import (
    get_df_analise_gtin_inconsistencia_clinica_municipio,
    get_df_dados_ibge_demografia,
)
from ...schemas.analytics import (
    MunicipioParkinsonResponse,
    MunicipioParkinsonRowSchema,
    MunicipioPatologiaResponse,
    MunicipioPatologiaRowSchema,
)


_PARKINSON_PREVALENCIA_50_MAIS = 0.0086


def _municipio_patologia_df(id_ibge7: int, patologia: Optional[str], ano_base: Optional[int]) -> pl.DataFrame:
    df = get_df_analise_gtin_inconsistencia_clinica_municipio().with_columns([
        pl.col("id_ibge7").cast(pl.Int64, strict=False),
        pl.col("patologia").cast(pl.Utf8),
        pl.col("regra_clinica").cast(pl.Utf8),
    ])
    filtered = df.filter(pl.col("id_ibge7") == id_ibge7)
    if patologia:
        patologia_normalizada = patologia.strip().lower()
        filtered = filtered.filter(pl.col("patologia").str.to_lowercase() == patologia_normalizada)
    if ano_base is not None:
        filtered = filtered.filter(pl.col("ano_base") == ano_base)
    return filtered.sort(["patologia", "regra_clinica", "ano_base"])


def _row_to_patologia_schema(row: dict) -> MunicipioPatologiaRowSchema:
    return MunicipioPatologiaRowSchema(
        id_ibge7=int(row["id_ibge7"]),
        patologia=str(row["patologia"]),
        regra_clinica=str(row["regra_clinica"]),
        ano_base=int(row["ano_base"]),
        qtd_cpfs_distintos_municipio=int(row["qtd_cpfs_distintos_municipio"]),
        qtd_cpfs_incompativeis_municipio=int(row["qtd_cpfs_incompativeis_municipio"]),
        qtd_autorizacoes_municipio=int(row["qtd_autorizacoes_municipio"]),
        qtd_autorizacoes_incompativeis_municipio=int(row["qtd_autorizacoes_incompativeis_municipio"]),
        valor_total_pago_municipio=float(row["valor_total_pago_municipio"]),
        valor_incompativel_pago_municipio=float(row["valor_incompativel_pago_municipio"]),
        dt_processamento=row["dt_processamento"],
    )


def _populacao_50_mais(id_ibge7: int) -> tuple[int, int]:
    df_demo = get_df_dados_ibge_demografia().with_columns([
        pl.col("id_ibge7").cast(pl.Int64, strict=False),
        pl.col("ano_censo").cast(pl.Int16, strict=False),
        pl.col("idade_min").cast(pl.Int16, strict=False),
        pl.col("nu_populacao").cast(pl.Int64, strict=False),
    ])
    df_municipio = df_demo.filter(pl.col("id_ibge7") == id_ibge7)
    if df_municipio.is_empty():
        raise HTTPException(
            status_code=500,
            detail=f"Demografia IBGE obrigatoria ausente para id_ibge7={id_ibge7}.",
        )

    ano_censo = df_municipio.select(pl.max("ano_censo")).item()
    if ano_censo is None:
        raise HTTPException(
            status_code=500,
            detail=f"Demografia IBGE sem ano_censo valido para id_ibge7={id_ibge7}.",
        )

    pop_50 = (
        df_municipio
        .filter((pl.col("ano_censo") == int(ano_censo)) & (pl.col("idade_min") >= 50))
        .select(pl.sum("nu_populacao"))
        .item()
    )
    if pop_50 is None or int(pop_50) <= 0:
        raise HTTPException(
            status_code=500,
            detail=f"Demografia IBGE sem populacao 50+ valida para id_ibge7={id_ibge7}.",
        )
    return int(ano_censo), int(pop_50)


def get_municipio_patologias(
    id_ibge7: int,
    patologia: Optional[str] = None,
    ano_base: Optional[int] = None,
) -> MunicipioPatologiaResponse:
    df = _municipio_patologia_df(id_ibge7, patologia, ano_base)
    rows = [_row_to_patologia_schema(row) for row in df.to_dicts()]
    return MunicipioPatologiaResponse(
        id_ibge7=id_ibge7,
        patologia=patologia,
        ano_base=ano_base,
        rows=rows,
    )


def get_municipio_parkinson(
    id_ibge7: int,
    ano_base: Optional[int] = None,
) -> MunicipioParkinsonResponse:
    df = get_df_analise_gtin_inconsistencia_clinica_municipio().with_columns([
        pl.col("id_ibge7").cast(pl.Int64, strict=False),
        pl.col("patologia").cast(pl.Utf8),
        pl.col("regra_clinica").cast(pl.Utf8),
    ])
    df = df.filter(
        (pl.col("id_ibge7") == id_ibge7)
        & pl.col("patologia").str.to_lowercase().str.contains("parkinson")
    )
    if ano_base is not None:
        df = df.filter(pl.col("ano_base") == ano_base)
    df = df.sort(["ano_base", "regra_clinica"])

    ano_censo, pop_50 = _populacao_50_mais(id_ibge7)
    casos_esperados = pop_50 * _PARKINSON_PREVALENCIA_50_MAIS

    rows = []
    for row in df.to_dicts():
        base = _row_to_patologia_schema(row).model_dump()
        rows.append(
            MunicipioParkinsonRowSchema(
                **base,
                ano_censo_populacao=ano_censo,
                populacao_50_mais=pop_50,
                prevalencia_referencia=_PARKINSON_PREVALENCIA_50_MAIS,
                casos_esperados_50_mais=round(casos_esperados, 2),
                razao_cpfs_distintos_sobre_esperado=round(
                    int(row["qtd_cpfs_distintos_municipio"]) / casos_esperados,
                    4,
                ),
            )
        )

    return MunicipioParkinsonResponse(
        id_ibge7=id_ibge7,
        ano_base=ano_base,
        ano_censo_populacao=ano_censo,
        populacao_50_mais=pop_50,
        prevalencia_referencia=_PARKINSON_PREVALENCIA_50_MAIS,
        casos_esperados_50_mais=round(casos_esperados, 2),
        rows=rows,
    )
