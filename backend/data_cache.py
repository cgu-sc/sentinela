import polars as pl
import pandas as pd
import os

_df: pl.DataFrame | None = None

_PARQUET_PATH = os.path.join(os.path.dirname(__file__), "cache_movimentacao.parquet")


def load_cache(engine, force_refresh: bool = False) -> None:
    """
    Carrega movimentacao_mensal_cnpj em memória como DataFrame Polars.

    - Se o .parquet existir no disco: carrega em ~1-2s.
    - Se não existir (ou force_refresh=True): lê do SQL, salva o .parquet e carrega.

    Para atualizar os dados após rodar pos_processamento.sql, chame
    refresh_cache(engine) ou DELETE o arquivo cache_movimentacao.parquet.
    """
    global _df
    import time

    if not force_refresh and os.path.exists(_PARQUET_PATH):
        print("Carregando cache do Parquet...")
        t0 = time.perf_counter()
        _df = pl.read_parquet(_PARQUET_PATH)
        elapsed = time.perf_counter() - t0
        print(f"Cache Polars pronto (Parquet): {len(_df):,} linhas | {_df.estimated_size('mb'):.1f} MB | {elapsed:.1f}s")
        return

    print("Carregando cache do SQL Server (isso ocorre apenas na primeira vez ou apos refresh)...")
    t0 = time.perf_counter()

    sql = """
        SELECT
            cnpj,
            uf,
            no_regiao_saude,
            no_municipio,
            periodo,
            CAST(total_vendas AS FLOAT)              AS total_vendas,
            CAST(total_sem_comprovacao AS FLOAT)     AS total_sem_comprovacao,
            CAST(total_qnt_vendas AS FLOAT)          AS total_qnt_vendas,
            CAST(total_qnt_sem_comprovacao AS FLOAT) AS total_qnt_sem_comprovacao
        FROM [temp_CGUSC].[fp].[movimentacao_mensal_cnpj]
    """

    pdf = pd.read_sql(sql, engine)

    _df = (
        pl.from_pandas(pdf)
        .with_columns([
            pl.col("periodo").cast(pl.Date),
            pl.col("uf").cast(pl.Categorical),
            pl.col("no_regiao_saude").cast(pl.Categorical),
            pl.col("no_municipio").cast(pl.Categorical),
            pl.col("total_vendas").cast(pl.Float64),
            pl.col("total_sem_comprovacao").cast(pl.Float64),
            pl.col("total_qnt_vendas").cast(pl.Float64),
            pl.col("total_qnt_sem_comprovacao").cast(pl.Float64),
        ])
    )

    print(f"Salvando Parquet em: {_PARQUET_PATH}")
    _df.write_parquet(_PARQUET_PATH, compression="lz4")

    elapsed = time.perf_counter() - t0
    print(f"Cache Polars pronto (SQL): {len(_df):,} linhas | {_df.estimated_size('mb'):.1f} MB | {elapsed:.1f}s")
    print("Parquet salvo — proximos startups serao muito mais rapidos.")


def refresh_cache(engine) -> None:
    """Força re-leitura do SQL e regera o Parquet. Chamar após pos_processamento.sql."""
    load_cache(engine, force_refresh=True)


def get_df() -> pl.DataFrame:
    if _df is None:
        raise RuntimeError("Cache Polars nao foi carregado. Verifique o startup.")
    return _df
