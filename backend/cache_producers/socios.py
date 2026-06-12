import os

import pandas as pd
import polars as pl
from sqlalchemy import text

from cache_files import SOCIOS_PARQUET
from cache_producers.types import CacheLoadResult


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
                "cpf_cnpj_socio": pl.Utf8,
                "nome_socio": pl.Utf8,
                "indicador_socio": pl.Utf8,
                "data_exclusao_sociedade": pl.Date,
                "data_processamento": pl.Date,
                "is_falecido": pl.Boolean,
                "is_cadunico": pl.Boolean,
            }),
            from_cache=False,
        )
    except Exception as exc:
        print(f"[ ANALYTICS ] {cnpj} - SOCIOS - indisponivel (cache ausente e banco offline): {exc}")
        return CacheLoadResult(None, from_cache=False, error="Cache ausente e Banco offline.")
