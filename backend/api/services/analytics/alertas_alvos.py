from typing import Optional

import polars as pl
from fastapi import HTTPException


SOCIO_BENEFICIO_SCOPES = {
    "cadunico_direto",
    "cadunico_n3",
    "cadunico_qualquer",
    "seguro_defeso_direto",
    "seguro_defeso_n3",
    "seguro_defeso_qualquer",
    "qualquer",
}


SOCIO_BENEFICIO_REQUIRED_COLUMNS = {
    "has_cadunico_direto",
    "has_cadunico_n3",
    "has_seguro_defeso_direto",
    "has_seguro_defeso_n3",
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

    missing_columns = SOCIO_BENEFICIO_REQUIRED_COLUMNS - set(df.columns)
    if missing_columns:
        raise HTTPException(
            status_code=500,
            detail=(
                "Filtro socio_beneficio exige colunas no perfil do estabelecimento: "
                + ", ".join(sorted(missing_columns))
            ),
        )

    scope = socio_beneficio.strip().lower()
    filter_expr = _scope_expr(scope)
    return df.filter(filter_expr)
