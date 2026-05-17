import os
import time

import pandas as pd
import polars as pl
from sqlalchemy import text

from cache_files import (
    CRM_CONCENTRACAO_MULTIPLO_ALERTAS_PARQUET,
    CRM_CONCENTRACAO_UNICO_ALERTAS_PARQUET,
    CRM_HORARIO_EVENTOS_PARQUET,
    CRM_HORARIO_PARQUET,
    CRM_PERFIL_DIARIO_PARQUET,
    CRM_RAIOX_TX_PARQUET,
    DADOS_CRMS_PARQUET,
    GEOGRAFICO_PARQUET,
    MEDIANA_AUTORIZACOES_HORARIA_PARQUET,
    VOLUME_HORARIO_ANOMALO_ALERTAS_PARQUET,
)
from cache_producers.types import CacheLoadResult

_CRM_ALERTS_CACHE_VERSION = 2
_CRM_SEVERITY_CACHE_VERSION = 2
_CRM_RAIOX_TX_CACHE_VERSION = 2
_CRM_UNICO_RHYTHM_WINDOWS = (5, 10, 15, 20, 25, 30, 60)
_CRM_MULTIPLO_RHYTHM_WINDOWS = (5, 10, 15, 20, 25, 30, 60)


def _get_cnpj_cache_dir(cnpj: str) -> str:
    from data_cache import get_cache_dir

    cnpj_dir = os.path.join(get_cache_dir(), cnpj)
    os.makedirs(cnpj_dir, exist_ok=True)
    return cnpj_dir


def _engine_or_default(engine=None):
    if engine is not None:
        return engine
    from database import engine as default_engine

    return default_engine


def _to_int(value, default: int = 0) -> int:
    if value is None:
        return default
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return default


def _path(cnpj: str, filename: str) -> str:
    return os.path.join(_get_cnpj_cache_dir(cnpj), filename)


def _read_parquet(path: str) -> tuple[pl.DataFrame | None, float | None]:
    if not os.path.exists(path):
        return None, None
    try:
        t0 = time.perf_counter()
        df = pl.read_parquet(path)
        return df, round((time.perf_counter() - t0) * 1000, 1)
    except Exception as exc:
        print(f"[ CACHE ] erro de leitura ({exc})")
        return None, None


def _empty_schema(filename: str) -> dict:
    import cache_registry

    schemas = cache_registry.get_cnpj_parquet_schemas()
    return schemas[filename]


def load_or_sync_crm_data(cnpj: str, engine=None) -> CacheLoadResult:
    parquet_path = _path(cnpj, DADOS_CRMS_PARQUET)
    df, read_time_ms = _read_parquet(parquet_path)
    if df is not None:
        missing_cols = [col for col in ["no_medico", "dt_inscricao_crm"] if col not in df.columns]
        if not missing_cols:
            return CacheLoadResult(df, from_cache=True, read_time_ms=read_time_ms)
        print(f"[ CACHE ] {cnpj} - CRM - cache sem {', '.join(missing_cols)}; regenerando parquet.")

    query_time_ms: float | None = None
    save_time_ms: float | None = None
    try:
        engine = _engine_or_default(engine)
        with engine.connect() as conn:
            t0 = time.perf_counter()
            pdf = pd.read_sql(
                text("SELECT E.id_medico, E.competencia, E.vl_total_prescricoes, "
                     "E.nu_prescricoes_mes, E.nu_prescricoes_total_brasil, "
                     "E.flag_crm_invalido, "
                     "E.flag_prescricao_antes_registro, E.alerta_concentracao_multiplos_crms, "
                     "E.flag_concentracao_mesmo_crm, E.flag_distancia_geografica, "
                     "E.dt_primeira_prescricao, M.no_medico, M.dt_inscricao AS dt_inscricao_crm, "
                     "E.nu_estabelecimentos"
                     " FROM temp_CGUSC.fp.app_crm_export E"
                     " LEFT JOIN temp_CGUSC.fp.build_dados_medico M ON M.id_medico = E.id_medico"
                     " INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.id = E.id_cnpj"
                     " WHERE F.cnpj = :cnpj"),
                conn,
                params={"cnpj": cnpj},
            )
            query_time_ms = round((time.perf_counter() - t0) * 1000, 1)

        df = pl.from_pandas(pdf) if not pdf.empty else pl.DataFrame(schema=_empty_schema(DADOS_CRMS_PARQUET))
        if "no_medico" not in df.columns:
            df = df.with_columns(pl.lit(None, dtype=pl.Utf8).alias("no_medico"))
        if "dt_inscricao_crm" not in df.columns:
            df = df.with_columns(pl.lit(None, dtype=pl.Date).alias("dt_inscricao_crm"))
        for col in ["flag_crm_invalido", "flag_prescricao_antes_registro", "alerta_concentracao_multiplos_crms"]:
            if col in df.columns:
                df = df.with_columns(pl.col(col).cast(pl.Int8))

        t1 = time.perf_counter()
        df.write_parquet(parquet_path, compression="zstd")
        save_time_ms = round((time.perf_counter() - t1) * 1000, 1)
        return CacheLoadResult(df, from_cache=False, query_time_ms=query_time_ms, save_time_ms=save_time_ms)
    except Exception:
        print(f"[ ANALYTICS ] {cnpj} - CRM - indisponivel (sem cache e banco offline)")
        return CacheLoadResult(pl.DataFrame(), from_cache=False, error="Arquivo Parquet local nao encontrado e Banco Offline.")


def load_or_sync_geografico(cnpj: str, engine=None) -> CacheLoadResult:
    return _load_or_sync_sql_cache(
        cnpj,
        GEOGRAFICO_PARQUET,
        text("SELECT * FROM temp_CGUSC.fp.app_alertas_crm_geografico WHERE cnpj_a = :cnpj OR cnpj_b = :cnpj"),
        {"cnpj": cnpj},
        engine,
    )


def load_or_sync_volume_horario_anomalo(cnpj: str, engine=None) -> CacheLoadResult:
    return _load_or_sync_sql_cache(
        cnpj,
        VOLUME_HORARIO_ANOMALO_ALERTAS_PARQUET,
        text("SELECT V.id_cnpj, V.competencia, V.dt_alerta, V.hr_janela,"
             " V.nu_prescricoes, V.nu_crms, V.mediana_hora, V.multiplicador"
             " FROM temp_CGUSC.fp.app_volume_horario_anomalo_alertas V"
             " INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.id = V.id_cnpj"
             " WHERE F.cnpj = :cnpj"),
        {"cnpj": cnpj},
        engine,
    )


def load_or_sync_crm_perfil_diario(cnpj: str, engine=None) -> CacheLoadResult:
    parquet_path = _path(cnpj, CRM_PERFIL_DIARIO_PARQUET)
    df, read_time_ms = _read_parquet(parquet_path)
    if df is not None and "is_crm_multiplo" in df.columns:
        return CacheLoadResult(df, from_cache=True, read_time_ms=read_time_ms)
    return _load_or_sync_sql_cache(
        cnpj,
        CRM_PERFIL_DIARIO_PARQUET,
        text("SELECT P.* FROM temp_CGUSC.fp.app_crm_perfil_diario P"
             " INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.id = P.id_cnpj"
             " WHERE F.cnpj = :cnpj ORDER BY P.dt_janela"),
        {"cnpj": cnpj},
        engine,
        read_existing=False,
    )


def load_or_sync_crm_perfil_horario(cnpj: str, engine=None) -> CacheLoadResult:
    parquet_path = _path(cnpj, CRM_HORARIO_PARQUET)
    df, read_time_ms = _read_parquet(parquet_path)
    if df is not None and {"is_crm_multiplo", "is_hora_com_alerta"}.issubset(df.columns):
        return CacheLoadResult(df, from_cache=True, read_time_ms=read_time_ms)
    return _load_or_sync_sql_cache(
        cnpj,
        CRM_HORARIO_PARQUET,
        text("SELECT P.dt_janela, P.hr_janela, P.nu_prescricoes, P.nu_crms_diferentes, P.mediana_hora, "
             "P.is_hora_com_alerta, P.is_volume_horario_anomalo, P.is_crm_unico, P.is_crm_multiplo "
             "FROM temp_CGUSC.fp.app_crm_perfil_horario P "
             "INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.id = P.id_cnpj "
             "WHERE F.cnpj = :cnpj "
             "ORDER BY P.dt_janela, P.hr_janela"),
        {"cnpj": cnpj},
        engine,
        read_existing=False,
    )


def load_or_sync_crm_horario_eventos(cnpj: str, engine=None) -> CacheLoadResult:
    parquet_path = _path(cnpj, CRM_HORARIO_EVENTOS_PARQUET)
    df, read_time_ms = _read_parquet(parquet_path)
    if (
        df is not None
        and "_crm_severity_cache_version" in df.columns
        and _to_int(df["_crm_severity_cache_version"].max()) >= _CRM_SEVERITY_CACHE_VERSION
    ):
        return CacheLoadResult(df, from_cache=True, read_time_ms=read_time_ms)

    query_time_ms: float | None = None
    save_time_ms: float | None = None
    try:
        engine = _engine_or_default(engine)
        with engine.connect() as conn:
            t0 = time.perf_counter()
            pdf = pd.read_sql(
                text("""
                    SELECT 'UNICO' as tipo, A.dt_dia, A.id_medico, NULL as nu_crms_distintos,
                           A.dt_ini_concentracao, A.dt_fim_concentracao,
                           CASE A.id_severidade WHEN 4 THEN 'EXTREMO' WHEN 3 THEN 'CRITICO'
                                WHEN 2 THEN 'GRAVE' WHEN 1 THEN 'ALTO' ELSE 'ALERTA' END AS severidade
                    FROM temp_CGUSC.fp.app_crm_concentracao_unico_alertas A
                    INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.id = A.id_cnpj
                    WHERE F.cnpj = :cnpj
                    UNION ALL
                    SELECT 'MULTIPLO' as tipo, A.dt_dia, NULL as id_medico, A.nu_crms_distintos,
                           A.dt_ini_concentracao, A.dt_fim_concentracao,
                           CASE A.id_severidade WHEN 4 THEN 'EXTREMO' WHEN 3 THEN 'CRITICO'
                                WHEN 2 THEN 'GRAVE' WHEN 1 THEN 'ALTO' ELSE 'ALERTA' END AS severidade
                    FROM temp_CGUSC.fp.app_crm_concentracao_multiplo_alertas A
                    INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.id = A.id_cnpj
                    WHERE F.cnpj = :cnpj
                    UNION ALL
                    SELECT 'VOLUME' as tipo, V.dt_alerta as dt_dia, NULL as id_medico, V.nu_crms as nu_crms_distintos,
                           DATEADD(HOUR, V.hr_janela, CAST(V.dt_alerta AS DATETIME)) as dt_ini_concentracao,
                           DATEADD(HOUR, V.hr_janela + 1, CAST(V.dt_alerta AS DATETIME)) as dt_fim_concentracao,
                           'CRITICO' as severidade
                    FROM temp_CGUSC.fp.app_volume_horario_anomalo_alertas V
                    INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.id = V.id_cnpj
                    WHERE F.cnpj = :cnpj
                """),
                conn,
                params={"cnpj": cnpj},
            )
            query_time_ms = round((time.perf_counter() - t0) * 1000, 1)

        df = pl.from_pandas(pdf) if not pdf.empty else pl.DataFrame(schema=_empty_schema(CRM_HORARIO_EVENTOS_PARQUET))
        if not df.is_empty():
            df = df.with_columns([
                pl.col("dt_ini_concentracao").dt.strftime("%H:%M").alias("hora_inicio"),
                pl.col("dt_fim_concentracao").dt.strftime("%H:%M").alias("hora_fim"),
                (pl.col("dt_ini_concentracao").dt.hour() * 60 + pl.col("dt_ini_concentracao").dt.minute()).alias("minuto_inicio"),
                (pl.col("dt_fim_concentracao").dt.hour() * 60 + pl.col("dt_fim_concentracao").dt.minute()).alias("minuto_fim"),
                pl.lit(_CRM_SEVERITY_CACHE_VERSION).alias("_crm_severity_cache_version"),
            ])
        else:
            df = df.with_columns(pl.lit(_CRM_SEVERITY_CACHE_VERSION).alias("_crm_severity_cache_version"))

        t1 = time.perf_counter()
        df.write_parquet(parquet_path, compression="zstd")
        save_time_ms = round((time.perf_counter() - t1) * 1000, 1)
        return CacheLoadResult(df, from_cache=False, query_time_ms=query_time_ms, save_time_ms=save_time_ms)
    except Exception:
        print(f"[ ANALYTICS ] {cnpj} - EVENTOS CRM - indisponivel (sem cache e banco offline)")
        return CacheLoadResult(pl.DataFrame(schema=_empty_schema(CRM_HORARIO_EVENTOS_PARQUET)), from_cache=False, error="Banco Offline.")


def load_or_sync_crm_unico_alertas(cnpj: str, engine=None) -> CacheLoadResult:
    schema = _empty_schema(CRM_CONCENTRACAO_UNICO_ALERTAS_PARQUET)
    required = set(schema)
    parquet_path = _path(cnpj, CRM_CONCENTRACAO_UNICO_ALERTAS_PARQUET)
    df, read_time_ms = _read_parquet(parquet_path)
    if df is not None:
        version_ok = "_crm_alerts_cache_version" in df.columns and (
            df.height == 0 or _to_int(df["_crm_alerts_cache_version"].max()) >= _CRM_ALERTS_CACHE_VERSION
        )
        if required.issubset(df.columns) and version_ok:
            return CacheLoadResult(df, from_cache=True, read_time_ms=read_time_ms)

    query = text("""
        SELECT A.id_medico, YEAR(A.dt_dia) * 100 + MONTH(A.dt_dia) AS competencia,
               A.dt_dia AS dt_alerta, DATEPART(HOUR, A.dt_ini_concentracao) AS hr_janela,
               A.nu_autorizacoes_pior_ritmo AS nu_prescricoes_dia,
               A.janela_pior_ritmo_minutos AS nu_minutos_dia,
               A.taxa_hora_pior_ritmo AS taxa_hora,
               A.dt_ini_concentracao AS dt_ini_hora,
               A.dt_fim_concentracao AS dt_fim_hora,
               CASE A.id_severidade WHEN 4 THEN 'EXTREMO' WHEN 3 THEN 'CRITICO'
                    WHEN 2 THEN 'GRAVE' WHEN 1 THEN 'ALTO' ELSE 'ALERTA' END AS severidade,
               A.criterio_pior_ritmo, A.nu_5min, A.nu_10min, A.nu_15min,
               A.nu_20min, A.nu_25min, A.nu_30min, A.nu_60min
        FROM temp_CGUSC.fp.app_crm_concentracao_unico_alertas A
        INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.id = A.id_cnpj
        WHERE F.cnpj = :cnpj
        ORDER BY A.dt_dia, A.id_medico, A.dt_ini_concentracao
    """)
    result = _load_or_sync_sql_cache(cnpj, CRM_CONCENTRACAO_UNICO_ALERTAS_PARQUET, query, {"cnpj": cnpj}, engine, read_existing=False)
    if result.error:
        return result

    df = result.df.with_columns(pl.lit(_CRM_ALERTS_CACHE_VERSION).alias("_crm_alerts_cache_version"))
    df.write_parquet(parquet_path, compression="zstd")
    return CacheLoadResult(df, result.from_cache, result.read_time_ms, result.query_time_ms, result.save_time_ms, result.error)


def load_or_sync_crm_multi_alertas(cnpj: str, engine=None) -> CacheLoadResult:
    schema = _empty_schema(CRM_CONCENTRACAO_MULTIPLO_ALERTAS_PARQUET)
    required = set(schema)
    parquet_path = _path(cnpj, CRM_CONCENTRACAO_MULTIPLO_ALERTAS_PARQUET)
    df, read_time_ms = _read_parquet(parquet_path)
    if df is not None:
        version_ok = "_crm_alerts_cache_version" in df.columns and (
            df.height == 0 or _to_int(df["_crm_alerts_cache_version"].max()) >= _CRM_ALERTS_CACHE_VERSION
        )
        if required.issubset(df.columns) and version_ok:
            return CacheLoadResult(df, from_cache=True, read_time_ms=read_time_ms)

    query = text("""
        SELECT A.id_cnpj, YEAR(A.dt_dia) * 100 + MONTH(A.dt_dia) AS competencia,
               A.dt_dia, A.dt_ini_concentracao AS dt_alerta,
               DATEPART(HOUR, A.dt_ini_concentracao) AS hr_janela,
               A.dt_ini_concentracao, A.dt_fim_concentracao,
               A.nu_autorizacoes_pior_ritmo AS nu_prescricoes,
               A.nu_crms_distintos AS nu_crms, A.nu_60min,
               A.janela_pior_ritmo_minutos AS nu_minutos_span,
               A.nu_crms_distintos,
               CASE A.id_severidade WHEN 4 THEN 'EXTREMO' WHEN 3 THEN 'CRITICO'
                    WHEN 2 THEN 'GRAVE' WHEN 1 THEN 'ALTO' ELSE 'ALERTA' END AS severidade,
               A.criterio_pior_ritmo, A.nu_5min, A.nu_10min, A.nu_15min,
               A.nu_20min, A.nu_25min, A.nu_30min
        FROM temp_CGUSC.fp.app_crm_concentracao_multiplo_alertas A
        INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.id = A.id_cnpj
        WHERE F.cnpj = :cnpj
    """)
    result = _load_or_sync_sql_cache(cnpj, CRM_CONCENTRACAO_MULTIPLO_ALERTAS_PARQUET, query, {"cnpj": cnpj}, engine, read_existing=False)
    if result.error:
        return result

    df = result.df.with_columns(pl.lit(_CRM_ALERTS_CACHE_VERSION).alias("_crm_alerts_cache_version"))
    df.write_parquet(parquet_path, compression="zstd")
    return CacheLoadResult(df, result.from_cache, result.read_time_ms, result.query_time_ms, result.save_time_ms, result.error)


def sync_crm_raiox_tx(cnpj: str, engine=None) -> CacheLoadResult:
    parquet_path = _path(cnpj, CRM_RAIOX_TX_PARQUET)
    df, read_time_ms = _read_parquet(parquet_path)
    if df is not None:
        version_ok = "_crm_raiox_tx_cache_version" in df.columns and (
            df.height == 0 or _to_int(df["_crm_raiox_tx_cache_version"].max()) >= _CRM_RAIOX_TX_CACHE_VERSION
        )
        if "codigo_barra" in df.columns and version_ok:
            return CacheLoadResult(df, from_cache=True, read_time_ms=read_time_ms)

    query = text("SELECT P.dt_janela, P.hr_janela, P.data_hora, P.num_autorizacao, P.id_medico, MED.codigo_barra, P.valor_pago "
                 "FROM temp_CGUSC.fp.app_crm_raiox_tx P "
                 "INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.id = P.id_cnpj "
                 "INNER JOIN temp_CGUSC.fp.medicamentos_patologia MED ON MED.id = P.id_gtin "
                 "WHERE F.cnpj = :cnpj "
                 "ORDER BY P.data_hora ASC, P.num_autorizacao ASC")
    result = _load_or_sync_sql_cache(cnpj, CRM_RAIOX_TX_PARQUET, query, {"cnpj": cnpj}, engine, read_existing=False)
    if result.error:
        return result

    df = result.df.with_columns(pl.lit(_CRM_RAIOX_TX_CACHE_VERSION).alias("_crm_raiox_tx_cache_version"))
    df.write_parquet(parquet_path, compression="zstd")
    return CacheLoadResult(df, result.from_cache, result.read_time_ms, result.query_time_ms, result.save_time_ms, result.error)


def sync_mediana_autorizacoes_horaria(cnpj: str, engine=None) -> CacheLoadResult:
    parquet_path = _path(cnpj, MEDIANA_AUTORIZACOES_HORARIA_PARQUET)
    df, read_time_ms = _read_parquet(parquet_path)
    if df is not None and "mediana_hora" in df.columns:
        return CacheLoadResult(df, from_cache=True, read_time_ms=read_time_ms)
    return _load_or_sync_sql_cache(
        cnpj,
        MEDIANA_AUTORIZACOES_HORARIA_PARQUET,
        text("SELECT M.ano, M.trimestre, M.hr_janela, M.mediana_hora "
             "FROM temp_CGUSC.fp.app_mediana_autorizacoes_horaria M "
             "INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.id = M.id_cnpj "
             "WHERE F.cnpj = :cnpj "
             "ORDER BY M.ano, M.trimestre, M.hr_janela"),
        {"cnpj": cnpj},
        engine,
        read_existing=False,
    )


def _load_or_sync_sql_cache(
    cnpj: str,
    filename: str,
    query,
    params: dict,
    engine=None,
    read_existing: bool = True,
) -> CacheLoadResult:
    parquet_path = _path(cnpj, filename)
    if read_existing:
        df, read_time_ms = _read_parquet(parquet_path)
        if df is not None:
            return CacheLoadResult(df, from_cache=True, read_time_ms=read_time_ms)

    query_time_ms: float | None = None
    save_time_ms: float | None = None
    try:
        engine = _engine_or_default(engine)
        with engine.connect() as conn:
            t0 = time.perf_counter()
            pdf = pd.read_sql(query, conn, params=params)
            query_time_ms = round((time.perf_counter() - t0) * 1000, 1)

        df = pl.from_pandas(pdf) if not pdf.empty else pl.DataFrame(schema=_empty_schema(filename))
        t1 = time.perf_counter()
        df.write_parquet(parquet_path, compression="zstd")
        save_time_ms = round((time.perf_counter() - t1) * 1000, 1)
        return CacheLoadResult(df, from_cache=False, query_time_ms=query_time_ms, save_time_ms=save_time_ms)
    except Exception:
        print(f"[ ANALYTICS ] {cnpj} - {filename} - indisponivel (sem cache e banco offline)")
        return CacheLoadResult(pl.DataFrame(schema=_empty_schema(filename)), from_cache=False, error="Banco Offline.")
