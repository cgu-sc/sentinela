import os
import time

import pandas as pd
import polars as pl
from sqlalchemy import text

from cache_files import MOVIMENTACAO_MENSAL_GTIN_PARQUET
from cache_producers.types import CacheLoadResult


def _get_cnpj_cache_dir(cnpj: str) -> str:
    from data_cache import get_cnpj_cache_root

    cnpj_dir = os.path.join(get_cnpj_cache_root(), cnpj)
    os.makedirs(cnpj_dir, exist_ok=True)
    return cnpj_dir


def _cache_path(cnpj: str) -> str:
    return os.path.join(_get_cnpj_cache_dir(cnpj), MOVIMENTACAO_MENSAL_GTIN_PARQUET)


def load_or_sync_movimentacao_mensal_gtin(cnpj: str, engine=None) -> CacheLoadResult:
    parquet_path = _cache_path(cnpj)
    df: pl.DataFrame | None = None
    from_cache = False
    read_time_ms: float | None = None

    if os.path.exists(parquet_path):
        try:
            t0 = time.perf_counter()
            df = pl.read_parquet(parquet_path)
            read_time_ms = round((time.perf_counter() - t0) * 1000, 1)
            from_cache = True
        except Exception as exc:
            print(f"[ CACHE ] {cnpj} - GTIN - erro de leitura ({exc})")

    if df is not None:
        return CacheLoadResult(df=df, from_cache=from_cache, read_time_ms=read_time_ms)

    query_time_ms: float | None = None
    save_time_ms: float | None = None

    try:
        if engine is None:
            from database import engine as engine

        with engine.connect() as conn:
            t0 = time.perf_counter()
            pdf = pd.read_sql(
                text("""
                    SELECT gtin.codigo_barra, m.periodo,
                           m.qnt_caixas_vendidas, m.qnt_caixas_sem_comprovacao,
                           m.num_autorizacoes,
                           CAST(m.valor_vendas AS FLOAT) AS valor_vendas,
                           CAST(m.valor_sem_comprovacao AS FLOAT) AS valor_sem_comprovacao
                    FROM [temp_CGUSC].[fp].[movimentacao_mensal_gtin] m
                    INNER JOIN [temp_CGUSC].[fp].[processamento] p ON p.id = m.id_processamento
                    INNER JOIN [temp_CGUSC].[fp].[medicamentos_patologia_chave] gtin ON gtin.id = m.id_gtin
                    WHERE p.cnpj = :cnpj AND p.situacao = 1
                """),
                conn,
                params={"cnpj": cnpj},
            )
            query_time_ms = round((time.perf_counter() - t0) * 1000, 1)

        df = pl.from_pandas(pdf).with_columns([
            pl.col("codigo_barra").cast(pl.String),
            pl.col("periodo").cast(pl.Date),
            pl.col("qnt_caixas_vendidas").cast(pl.Int64),
            pl.col("qnt_caixas_sem_comprovacao").cast(pl.Int64),
            pl.col("num_autorizacoes").cast(pl.Int64),
            pl.col("valor_vendas").cast(pl.Float64),
            pl.col("valor_sem_comprovacao").cast(pl.Float64),
        ])

        t1 = time.perf_counter()
        df.write_parquet(parquet_path, compression="zstd")
        save_time_ms = round((time.perf_counter() - t1) * 1000, 1)
        print(f"GTIN {cnpj}: SQL {query_time_ms}ms | parquet {save_time_ms}ms")

        return CacheLoadResult(
            df=df,
            from_cache=False,
            query_time_ms=query_time_ms,
            save_time_ms=save_time_ms,
        )
    except Exception:
        print(f"[ ANALYTICS ] {cnpj} - GTIN - indisponivel (sem cache e banco offline)")
        return CacheLoadResult(
            df=pl.DataFrame(),
            from_cache=False,
            query_time_ms=query_time_ms,
            save_time_ms=save_time_ms,
            error="Arquivo Parquet local nao encontrado e Banco Offline.",
        )
