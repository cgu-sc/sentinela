from typing import Optional

import polars as pl
from fastapi import HTTPException

from data_cache import get_df_par_teia_alvos


PAR_TEIA_COLUMN_BY_SCOPE = {
    "alvo": "has_par_alvo",
    "n2": "has_par_n2",
    "n4": "has_par_n4",
    "qualquer": "has_par_qualquer",
}


def apply_par_teia_filter(df: pl.DataFrame, par_teia: Optional[str]) -> pl.DataFrame:
    if not par_teia or par_teia == "Todos":
        return df

    scope = par_teia.strip().lower()
    column = PAR_TEIA_COLUMN_BY_SCOPE.get(scope)
    if column is None:
        raise HTTPException(
            status_code=400,
            detail=f"Filtro par_teia invalido: {par_teia}. Valores aceitos: {sorted(PAR_TEIA_COLUMN_BY_SCOPE)}",
        )

    if "cnpj" not in df.columns:
        raise HTTPException(status_code=500, detail="Filtro par_teia exige coluna cnpj no DataFrame alvo.")

    try:
        par_df = get_df_par_teia_alvos().select(["cnpj", column])
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc

    return (
        df.join(par_df.filter(pl.col(column) == True).select("cnpj"), on="cnpj", how="semi")
    )
