"""
Exportador de parquets para o indicador de CRMs.

Execução standalone (fora do servidor):
    python backend/exportar_crms.py

Gera:
    sentinela_cache/crms/{cnpj}_crms.parquet            — dados mensais por farmácia
    sentinela_cache/crms/{cnpj}_alertas_diarios.parquet — alertas diários por farmácia
    sentinela_cache/benchmarks/bench_uf.parquet
    sentinela_cache/benchmarks/bench_regiao.parquet
    sentinela_cache/benchmarks/bench_br.parquet
"""
import os
import sys
import time

import pandas as pd
import polars as pl
from sqlalchemy import text

# Resolve raiz do projeto igual ao data_cache.py
if getattr(sys, "frozen", False):
    BASE_DIR = os.path.dirname(sys.executable)
else:
    BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

sys.path.insert(0, os.path.join(BASE_DIR, "backend"))
from database import engine  # noqa: E402 — import após ajuste de path

CACHE_DIR = os.path.join(BASE_DIR, "sentinela_cache")
CRMS_DIR  = os.path.join(CACHE_DIR, "crms")
BENCH_DIR = os.path.join(CACHE_DIR, "benchmarks")

CHUNK_SIZE = 500_000  # linhas por chunk na leitura do SQL Server

BENCHMARKS = [
    ("bench_crm_uf",     "SELECT * FROM temp_CGUSC.fp.indicador_crm_bench_uf"),
    ("bench_crm_regiao", "SELECT * FROM temp_CGUSC.fp.indicador_crm_bench_regiao"),
    ("bench_crm_br",     "SELECT * FROM temp_CGUSC.fp.indicador_crm_bench_br"),
]

DATE_COLS   = []
INT8_FLAGS  = ["flag_crm_invalido", "flag_prescricao_antes_registro"]
STR_COLS    = ["alerta_concentracao_temporal", "alerta_distancia_geografica"]


# ---------------------------------------------------------------------------
# Benchmarks
# ---------------------------------------------------------------------------

def exportar_benchmarks() -> None:
    os.makedirs(BENCH_DIR, exist_ok=True)
    print("\n[benchmarks]")
    for nome, sql in BENCHMARKS:
        df = pl.from_pandas(pd.read_sql(sql, engine))
        path = os.path.join(BENCH_DIR, f"{nome}.parquet")
        df.write_parquet(path, compression="lz4")
        print(f"  {nome}.parquet  →  {len(df):,} linhas")


# ---------------------------------------------------------------------------
# CRMs por CNPJ
# ---------------------------------------------------------------------------

def _cast_schema(df: pl.DataFrame) -> pl.DataFrame:
    casts = []
    for col in INT8_FLAGS:
        if col in df.columns:
            casts.append(pl.col(col).cast(pl.Int8))
    for col in STR_COLS:
        if col in df.columns:
            casts.append(pl.col(col).cast(pl.Utf8))
    if casts:
        df = df.with_columns(casts)
    return df


def exportar_crms(cnpjs: list[str] | None = None) -> None:
    os.makedirs(CRMS_DIR, exist_ok=True)

    if cnpjs:
        placeholders = ", ".join(f"'{c}'" for c in cnpjs)
        where        = f"WHERE cnpj IN ({placeholders})"
        count_sql    = f"SELECT COUNT(*) FROM temp_CGUSC.fp.crm_export {where}"
        data_sql     = f"SELECT * FROM temp_CGUSC.fp.crm_export {where} ORDER BY cnpj, competencia, id_medico"
        print(f"\n[crms]  filtrando {len(cnpjs)} CNPJ(s)  →  {CRMS_DIR}")
    else:
        count_sql = "SELECT COUNT(*) FROM temp_CGUSC.fp.crm_export"
        data_sql  = "SELECT * FROM temp_CGUSC.fp.crm_export ORDER BY cnpj, competencia, id_medico"

    with engine.connect() as conn:
        total = conn.execute(text(count_sql)).scalar()

    print(f"\n[crms]  {total:,} linhas  →  {CRMS_DIR}")

    sql = data_sql

    # Lê em chunks e acumula frames por CNPJ.
    # Como o SQL retorna ordenado por cnpj, cada CNPJ é contíguo entre chunks.
    buffer: list[pl.DataFrame] = []
    current_cnpj: str | None = None
    cnpjs_escritos = 0
    linhas_lidas = 0
    t0 = time.time()

    for chunk in pd.read_sql(sql, engine, chunksize=CHUNK_SIZE):
        df_chunk = _cast_schema(pl.from_pandas(chunk))

        # Itera sobre grupos de CNPJ preservando a ordem de chegada
        for grupo in df_chunk.partition_by("cnpj", maintain_order=True):
            cnpj_val: str = grupo["cnpj"][0]

            if current_cnpj is None:
                current_cnpj = cnpj_val

            if cnpj_val != current_cnpj:
                # CNPJ anterior completo — escreve e limpa buffer
                _escrever_cnpj(current_cnpj, buffer)
                cnpjs_escritos += 1
                buffer = []
                current_cnpj = cnpj_val

            buffer.append(grupo)

        linhas_lidas += len(chunk)
        pct     = int(linhas_lidas / total * 100)
        elapsed = time.time() - t0
        vel     = linhas_lidas / elapsed if elapsed else 0
        print(
            f"  {pct:3}%  {linhas_lidas:>12,} / {total:,}"
            f"  |  {cnpjs_escritos:,} CNPJs  |  {vel:,.0f} lin/s"
        )

    # Último CNPJ
    if buffer and current_cnpj:
        _escrever_cnpj(current_cnpj, buffer)
        cnpjs_escritos += 1

    elapsed = time.time() - t0
    print(f"\n  Concluído: {cnpjs_escritos:,} arquivos  em  {elapsed:.0f}s")


def _escrever_cnpj(cnpj: str, frames: list[pl.DataFrame]) -> None:
    df = pl.concat(frames)
    df.write_parquet(os.path.join(CRMS_DIR, f"{cnpj}_crms.parquet"), compression="lz4")


# ---------------------------------------------------------------------------
# Alertas diários por CNPJ
# ---------------------------------------------------------------------------

def exportar_alertas_diarios(cnpjs: list[str] | None = None) -> None:
    os.makedirs(CRMS_DIR, exist_ok=True)

    if cnpjs:
        placeholders = ", ".join(f"'{c}'" for c in cnpjs)
        where     = f"WHERE cnpj IN ({placeholders})"
        count_sql = f"SELECT COUNT(*) FROM temp_CGUSC.fp.alertas_crm_diario {where}"
        data_sql  = f"SELECT * FROM temp_CGUSC.fp.alertas_crm_diario {where} ORDER BY cnpj, id_medico, dt_alerta"
    else:
        count_sql = "SELECT COUNT(*) FROM temp_CGUSC.fp.alertas_crm_diario"
        data_sql  = "SELECT * FROM temp_CGUSC.fp.alertas_crm_diario ORDER BY cnpj, id_medico, dt_alerta"

    with engine.connect() as conn:
        total = conn.execute(text(count_sql)).scalar()

    print(f"\n[alertas_diarios]  {total:,} linhas  →  {CRMS_DIR}")

    buffer: list[pl.DataFrame] = []
    current_cnpj: str | None = None
    cnpjs_escritos = 0

    for chunk in pd.read_sql(data_sql, engine, chunksize=CHUNK_SIZE):
        df_chunk = pl.from_pandas(chunk).with_columns(
            pl.col("dt_alerta").cast(pl.Utf8),
            pl.col("nivel").cast(pl.Utf8),
            pl.col("descricao").cast(pl.Utf8),
        )
        for grupo in df_chunk.partition_by("cnpj", maintain_order=True):
            cnpj_val: str = grupo["cnpj"][0]
            if current_cnpj is None:
                current_cnpj = cnpj_val
            if cnpj_val != current_cnpj:
                _escrever_alertas_diarios(current_cnpj, buffer)
                cnpjs_escritos += 1
                buffer = []
                current_cnpj = cnpj_val
            buffer.append(grupo)

    if buffer and current_cnpj:
        _escrever_alertas_diarios(current_cnpj, buffer)
        cnpjs_escritos += 1

    print(f"  Concluído: {cnpjs_escritos:,} arquivos de alertas diários")


def _escrever_alertas_diarios(cnpj: str, frames: list[pl.DataFrame]) -> None:
    df = pl.concat(frames)
    df.write_parquet(os.path.join(CRMS_DIR, f"{cnpj}_alertas_diarios.parquet"), compression="lz4")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    print("=" * 60)
    print("Exportador de CRMs — Sentinela")
    print("=" * 60)
    exportar_benchmarks()
    exportar_crms()
    exportar_alertas_diarios()
    print("\nExportação finalizada.")
