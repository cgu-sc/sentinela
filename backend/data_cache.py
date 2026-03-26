import pandas as pd
import polars as pl
from sqlalchemy import text
import os

_df: pl.DataFrame | None = None
_cache_progress: int = 0
_cache_status: str = "idle"

_PARQUET_PATH = os.path.join(os.path.dirname(__file__), "cache_movimentacao.parquet")


def load_cache(engine, force_refresh: bool = False) -> None:
    """
    Carrega movimentacao_mensal_cnpj em memória com rastreamento de progresso real.
    """
    global _df, _cache_progress, _cache_status
    import time

    if not force_refresh and os.path.exists(_PARQUET_PATH):
        _cache_status = "loading_parquet"
        print("Carregando cache do Parquet...")
        _df = pl.read_parquet(_PARQUET_PATH)
        _cache_progress = 100
        _cache_status = "ready"
        print("🚀 Cache pronto via Parquet.")
        return
    
    # Se não tem Parquet e não foi forçado o refresh (primeiro boot da vida)
    if not force_refresh:
        print("⚠️ Cache vazio e Parquet não detectado. Aguardando sincronização do frontend...")
        _cache_status = "idle"
        _cache_progress = 0
        return

    _cache_status = "counting"
    _cache_progress = 0
    print("Iniciando sincronização real com SQL Server...")
    t0 = time.perf_counter()

    try:
        with engine.connect() as conn:
            total_rows = conn.execute(text("SELECT COUNT(*) FROM [temp_CGUSC].[fp].[movimentacao_mensal_cnpj]")).scalar()
        
        print(f"Total de registros para carregar: {total_rows:,}")
        
        sql = """
            SELECT
                cnpj, uf, no_regiao_saude, no_municipio, periodo,
                CAST(total_vendas AS FLOAT)              AS total_vendas,
                CAST(total_sem_comprovacao AS FLOAT)     AS total_sem_comprovacao,
                CAST(total_qnt_vendas AS FLOAT)          AS total_qnt_vendas,
                CAST(total_qnt_sem_comprovacao AS FLOAT) AS total_qnt_sem_comprovacao
            FROM [temp_CGUSC].[fp].[movimentacao_mensal_cnpj]
        """
        
        _cache_status = "fetching"
        chunk_list = []
        rows_processed = 0
        CHUNK_SIZE = 250_000 # Bloco razoável para feedback rápido
        
        # Lendo em chunks para calcular o progresso
        for chunk in pd.read_sql(sql, engine, chunksize=CHUNK_SIZE):
            chunk_list.append(chunk)
            rows_processed += len(chunk)
            _cache_progress = int((rows_processed / total_rows) * 90) # 90% para leitura, 10% para casting/parquet
            print(f"Progresso: {_cache_progress}% ({rows_processed:,}/{total_rows:,})")

        _cache_status = "processing"
        pdf = pd.concat(chunk_list, ignore_index=True)
        
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

        _cache_progress = 95
        print(f"Salvando Parquet em: {_PARQUET_PATH}")
        _df.write_parquet(_PARQUET_PATH, compression="lz4")

        elapsed = time.perf_counter() - t0
        _cache_progress = 100
        _cache_status = "ready"
        print(f"🚀 Cache Sincronizado: {len(_df):,} linhas em {elapsed:.1f}s")

    except Exception as e:
        _cache_status = "error"
        print(f"❌ Erro na sincronização: {e}")
        raise e


def refresh_cache(engine) -> None:
    """Força re-leitura do SQL e regera o Parquet. Chamar após pos_processamento.sql."""
    load_cache(engine, force_refresh=True)


def get_df() -> pl.DataFrame:
    if _df is None:
        raise RuntimeError("Cache Polars nao foi carregado. Verifique o startup.")
    return _df

def get_cache_status() -> dict:
    """Retorna o estado atual da sincronização para o frontend."""
    return {
        "progress": _cache_progress,
        "status": _cache_status,
        "is_ready": _df is not None
    }
