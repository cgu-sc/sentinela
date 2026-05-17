from dataclasses import dataclass
import os

import pandas as pd
import polars as pl
from sqlalchemy import text

from cache_files import SOCIOS_PARQUET


@dataclass(frozen=True)
class CacheLoadResult:
    df: pl.DataFrame | None
    from_cache: bool
    error: str | None = None


def load_socios(cnpj: str, engine=None) -> CacheLoadResult:
    from data_cache import get_cache_dir

    parquet_path = os.path.join(get_cache_dir(), SOCIOS_PARQUET)
    if os.path.exists(parquet_path):
        try:
            return CacheLoadResult(pl.read_parquet(parquet_path), from_cache=True)
        except Exception as exc:
            print(f"[ CACHE ] SOCIOS - erro de leitura em {cnpj}: {exc}")

    try:
        if engine is None:
            from database import engine as engine

        with engine.connect() as conn:
            pdf = pd.read_sql(
                text("SELECT * FROM [temp_CGUSC].[fp].[dados_socios] WHERE cnpj = :cnpj"),
                conn,
                params={"cnpj": cnpj},
            )

        if not pdf.empty:
            return CacheLoadResult(pl.from_pandas(pdf), from_cache=False)

        return CacheLoadResult(
            pl.DataFrame(schema={
                "cnpj": pl.Utf8,
                "nome_socio": pl.Utf8,
                "data_processamento": pl.Date,
            }),
            from_cache=False,
        )
    except Exception as exc:
        print(f"[ ANALYTICS ] {cnpj} - SOCIOS - indisponivel (cache ausente e banco offline): {exc}")
        return CacheLoadResult(None, from_cache=False, error="Cache ausente e Banco offline.")
