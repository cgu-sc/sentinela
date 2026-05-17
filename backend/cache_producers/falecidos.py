from dataclasses import dataclass
import os
import time

import pandas as pd
import polars as pl
from sqlalchemy import text

from cache_files import FALECIDOS_PARQUET


@dataclass(frozen=True)
class CacheLoadResult:
    df: pl.DataFrame | None
    from_cache: bool
    read_time_ms: float | None = None
    query_time_ms: float | None = None
    save_time_ms: float | None = None
    error: str | None = None


def _get_cnpj_cache_dir(cnpj: str) -> str:
    from data_cache import get_cache_dir

    cnpj_dir = os.path.join(get_cache_dir(), cnpj)
    os.makedirs(cnpj_dir, exist_ok=True)
    return cnpj_dir


def _cache_path(cnpj: str) -> str:
    return os.path.join(_get_cnpj_cache_dir(cnpj), FALECIDOS_PARQUET)


def load_or_sync_falecidos(cnpj: str, engine=None) -> CacheLoadResult:
    parquet_path = _cache_path(cnpj)
    df_all: pl.DataFrame | None = None
    from_cache = False
    read_time_ms: float | None = None

    if os.path.exists(parquet_path):
        try:
            t0 = time.perf_counter()
            df_all = pl.read_parquet(parquet_path)
            read_time_ms = round((time.perf_counter() - t0) * 1000, 1)
            from_cache = True
        except Exception as exc:
            print(f"[ CACHE ] {cnpj} - FALECIDOS - erro de leitura ({exc})")

    if df_all is not None:
        return CacheLoadResult(df_all, from_cache=True, read_time_ms=read_time_ms)

    query_time_ms: float | None = None
    save_time_ms: float | None = None

    try:
        if engine is None:
            from database import engine as engine

        with engine.connect() as conn:
            t0 = time.perf_counter()
            pdf = pd.read_sql(
                text("""
                    SELECT f.*
                    FROM [temp_CGUSC].[fp].[falecidos_por_farmacia] f
                    WHERE f.cpf IN (
                        SELECT DISTINCT cpf
                        FROM [temp_CGUSC].[fp].[falecidos_por_farmacia]
                        WHERE cnpj = :cnpj
                    )
                """),
                conn,
                params={"cnpj": cnpj},
            )
            query_time_ms = round((time.perf_counter() - t0) * 1000, 1)

        df_all = pl.from_pandas(pdf).with_columns([
            pl.col("dt_nascimento").cast(pl.Date, strict=False),
            pl.col("dt_obito").cast(pl.Date, strict=False),
            pl.col("data_autorizacao").cast(pl.Date, strict=False),
        ])

        t1 = time.perf_counter()
        df_all.write_parquet(parquet_path, compression="zstd")
        save_time_ms = round((time.perf_counter() - t1) * 1000, 1)
        print(f"Falecidos {cnpj}: SQL {query_time_ms}ms | parquet {save_time_ms}ms")

        return CacheLoadResult(
            df_all,
            from_cache=False,
            query_time_ms=query_time_ms,
            save_time_ms=save_time_ms,
        )
    except Exception:
        print(f"[ ANALYTICS ] {cnpj} - FALECIDOS - indisponivel (sem cache e banco offline)")
        return CacheLoadResult(
            None,
            from_cache=False,
            query_time_ms=query_time_ms,
            save_time_ms=save_time_ms,
            error="Arquivo Parquet local nao encontrado e Banco Offline.",
        )
