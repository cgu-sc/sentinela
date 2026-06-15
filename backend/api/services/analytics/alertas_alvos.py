from typing import Optional

import polars as pl
from fastapi import HTTPException

from data_cache import get_df_alertas_alvos


SOCIO_BENEFICIO_SCOPES = {
    "cadunico_direto",
    "cadunico_n3",
    "cadunico_qualquer",
    "seguro_defeso_direto",
    "seguro_defeso_n3",
    "seguro_defeso_qualquer",
    "qualquer",
}


def _scope_expr(scope: str) -> pl.Expr:
    if scope == "cadunico_direto":
        return pl.col("has_cadunico_direto")
    if scope == "cadunico_n3":
        return pl.col("has_cadunico_n3")
    if scope == "cadunico_qualquer":
        return pl.col("has_cadunico_direto") | pl.col("has_cadunico_n3")
    if scope == "seguro_defeso_direto":
        return pl.col("has_seguro_defeso_direto")
    if scope == "seguro_defeso_n3":
        return pl.col("has_seguro_defeso_n3")
    if scope == "seguro_defeso_qualquer":
        return pl.col("has_seguro_defeso_direto") | pl.col("has_seguro_defeso_n3")
    if scope == "qualquer":
        return (
            pl.col("has_cadunico_direto")
            | pl.col("has_cadunico_n3")
            | pl.col("has_seguro_defeso_direto")
            | pl.col("has_seguro_defeso_n3")
        )
    raise HTTPException(
        status_code=400,
        detail=(
            f"Filtro socio_beneficio invalido: {scope}. "
            f"Valores aceitos: {sorted(SOCIO_BENEFICIO_SCOPES)}"
        ),
    )


def apply_socio_beneficio_filter(
    df: pl.DataFrame,
    socio_beneficio: Optional[str],
) -> pl.DataFrame:
    if not socio_beneficio or socio_beneficio == "Todos":
        return df

    if "cnpj" not in df.columns:
        raise HTTPException(
            status_code=500,
            detail="Filtro socio_beneficio exige coluna cnpj no DataFrame alvo.",
        )

    scope = socio_beneficio.strip().lower()
    filter_expr = _scope_expr(scope)

    try:
        alertas_df = get_df_alertas_alvos()
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc

    cnpjs_filtrados = (
        alertas_df
        .filter(filter_expr)
        .select("cnpj")
    )
    return df.join(cnpjs_filtrados, on="cnpj", how="semi")
