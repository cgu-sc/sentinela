import json
import os
import time
from datetime import date
from pathlib import Path

import pandas as pd
import polars as pl
from sqlalchemy import text

from cache_files import (
    CRM_CONCENTRACAO_MULTIPLO_ALERTAS_PARQUET,
    CRM_CONCENTRACAO_UNICO_ALERTAS_PARQUET,
    CRM_RAIOX_TX_PARQUET,
    CRM_TIMELINE_DIA_PARQUET,
    CRM_TIMELINE_EVENTOS_PARQUET,
    CRM_TIMELINE_HORA_PARQUET,
    CRM_PRESCRITORES_PARQUET,
    GEOGRAFICO_PARQUET,
)
from cache_producers.types import CacheLoadResult

_CRM_ALERTS_CACHE_VERSION = 4
_CRM_RAIOX_TX_CACHE_VERSION = 3
_CRM_PRESCRITORES_CACHE_VERSION = 2
_CRM_UNICO_RHYTHM_WINDOWS = (5, 10, 15, 20, 25, 30, 60)
_CRM_MULTIPLO_RHYTHM_WINDOWS = (5, 10, 15, 20, 25, 30, 60)


def _get_cnpj_cache_dir(cnpj: str) -> str:
    from data_cache import get_cnpj_cache_root

    cnpj_dir = os.path.join(get_cnpj_cache_root(), cnpj)
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
    parquet_path = _path(cnpj, CRM_PRESCRITORES_PARQUET)
    df, read_time_ms = _read_parquet(parquet_path)
    if df is not None:
        missing_cols = [
            col
            for col in ["no_medico", "dt_inscricao_crm", "_crm_prescritores_cache_version"]
            if col not in df.columns
        ]
        version_ok = (
            "_crm_prescritores_cache_version" in df.columns
            and (df.height == 0 or _to_int(df["_crm_prescritores_cache_version"].max()) >= _CRM_PRESCRITORES_CACHE_VERSION)
        )
        if not missing_cols and version_ok:
            return CacheLoadResult(df, from_cache=True, read_time_ms=read_time_ms)
        motivo = f"cache sem {', '.join(missing_cols)}" if missing_cols else "versao de cache defasada"
        print(f"[ CACHE ] {cnpj} - CRM - {motivo}; regenerando parquet.")

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
                     "E.dt_primeira_prescricao, E.dt_inscricao_crm, "
                     "E.nu_estabelecimentos"
                     " FROM temp_CGUSC.fp.app_crm_export E"
                     " INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.id = E.id_cnpj"
                     " WHERE F.cnpj = :cnpj"),
                conn,
                params={"cnpj": cnpj},
            )
            query_time_ms = round((time.perf_counter() - t0) * 1000, 1)

        df = pl.from_pandas(pdf) if not pdf.empty else pl.DataFrame(schema=_empty_schema(CRM_PRESCRITORES_PARQUET))
        if not df.is_empty():
            from data_cache import scan_dados_medico

            id_medicos = df["id_medico"].cast(pl.Utf8).unique().to_list()
            df_medicos = (
                scan_dados_medico()
                .filter(pl.col("id_medico").is_in(id_medicos))
                .select(["id_medico", "no_medico"])
                .collect()
            )
            df = df.with_columns(pl.col("id_medico").cast(pl.Utf8)).join(
                df_medicos,
                on="id_medico",
                how="left",
            )

        missing_after_build = [col for col in ["no_medico", "dt_inscricao_crm"] if col not in df.columns]
        if missing_after_build:
            raise RuntimeError(
                f"Contrato invalido ao gerar {CRM_PRESCRITORES_PARQUET}: colunas ausentes {', '.join(missing_after_build)}."
            )

        df = df.with_columns([
            pl.col("no_medico").cast(pl.Utf8),
            pl.col("dt_inscricao_crm").cast(pl.Date),
        ])
        for col in ["flag_crm_invalido", "flag_prescricao_antes_registro", "alerta_concentracao_multiplos_crms"]:
            if col in df.columns:
                df = df.with_columns(pl.col(col).cast(pl.Int8))
        df = df.with_columns(pl.lit(_CRM_PRESCRITORES_CACHE_VERSION).alias("_crm_prescritores_cache_version"))

        t1 = time.perf_counter()
        df.write_parquet(parquet_path, compression="zstd")
        save_time_ms = round((time.perf_counter() - t1) * 1000, 1)
        return CacheLoadResult(df, from_cache=False, query_time_ms=query_time_ms, save_time_ms=save_time_ms)
    except Exception:
        print(f"[ ANALYTICS ] {cnpj} - CRM - indisponivel (sem cache e banco offline)")
        return CacheLoadResult(pl.DataFrame(), from_cache=False, error="Arquivo Parquet local nao encontrado e Banco Offline.")


def load_or_sync_geografico(cnpj: str, engine=None) -> CacheLoadResult:
    schema = _empty_schema(GEOGRAFICO_PARQUET)
    required = set(schema)
    parquet_path = _path(cnpj, GEOGRAFICO_PARQUET)
    df, read_time_ms = _read_parquet(parquet_path)
    if df is not None:
        missing_cols = sorted(required - set(df.columns))
        if not missing_cols:
            return CacheLoadResult(df, from_cache=True, read_time_ms=read_time_ms)
        print(f"[ CACHE ] {cnpj} - geografico - cache sem {', '.join(missing_cols)}; regenerando parquet.")

    result = _load_or_sync_sql_cache(
        cnpj,
        GEOGRAFICO_PARQUET,
        text("SELECT * FROM temp_CGUSC.fp.app_alertas_crm_geografico WHERE cnpj_a = :cnpj OR cnpj_b = :cnpj"),
        {"cnpj": cnpj},
        engine,
        read_existing=False,
    )
    result_df = result.df
    if result_df is not None:
        missing_cols = sorted(required - set(result_df.columns))
        if missing_cols:
            result_df = result_df.with_columns([
                pl.lit(None, dtype=schema[col]).alias(col)
                for col in missing_cols
            ])
            result_df.write_parquet(parquet_path, compression="zstd")
            return CacheLoadResult(
                result_df,
                from_cache=result.from_cache,
                read_time_ms=result.read_time_ms,
                query_time_ms=result.query_time_ms,
                save_time_ms=result.save_time_ms,
                error=result.error,
            )
    return result


def load_or_sync_crm_timeline_dia(cnpj: str, engine=None) -> CacheLoadResult:
    schema = _empty_schema(CRM_TIMELINE_DIA_PARQUET)
    required = set(schema)
    parquet_path = _path(cnpj, CRM_TIMELINE_DIA_PARQUET)
    df, read_time_ms = _read_parquet(parquet_path)
    if df is not None:
        missing_cols = sorted(required - set(df.columns))
        if not missing_cols:
            return CacheLoadResult(df, from_cache=True, read_time_ms=read_time_ms)
        print(f"[ CACHE ] {cnpj} - timeline dia - cache sem {', '.join(missing_cols)}; regenerando parquet.")

    return _load_or_sync_sql_cache(
        cnpj,
        CRM_TIMELINE_DIA_PARQUET,
        text(
            "SELECT CONVERT(VARCHAR(10), P.dt_janela, 23) AS dt_janela,"
            " P.competencia, P.nu_prescricoes_dia, P.nu_crms_distintos, P.mediana_diaria,"
            " P.is_dia_com_volume_horario_anomalo, P.is_anomalo_unico, P.is_crm_multiplo,"
            " P.score_crm_unico_hora, P.score_crm_unico_qtd, P.score_crm_unico_minutos,"
            " P.score_crm_unico_medico, P.score_crm_multiplo_hora, P.score_crm_multiplo_qtd,"
            " P.score_crm_multiplo_minutos, P.score_crm_multiplo_crms"
            " FROM temp_CGUSC.fp.app_crm_timeline_dia P"
            " INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.id = P.id_cnpj"
            " WHERE F.cnpj = :cnpj"
            " ORDER BY P.dt_janela"
        ),
        {"cnpj": cnpj},
        engine,
        read_existing=False,
    )


def load_or_sync_crm_timeline_hora(cnpj: str, engine=None) -> CacheLoadResult:
    schema = _empty_schema(CRM_TIMELINE_HORA_PARQUET)
    required = set(schema)
    parquet_path = _path(cnpj, CRM_TIMELINE_HORA_PARQUET)
    df, read_time_ms = _read_parquet(parquet_path)
    if df is not None:
        missing_cols = sorted(required - set(df.columns))
        if not missing_cols:
            return CacheLoadResult(df, from_cache=True, read_time_ms=read_time_ms)
        print(f"[ CACHE ] {cnpj} - timeline hora - cache sem {', '.join(missing_cols)}; regenerando parquet.")

    return _load_or_sync_sql_cache(
        cnpj,
        CRM_TIMELINE_HORA_PARQUET,
        text(
            "SELECT CONVERT(VARCHAR(10), P.dt_janela, 23) AS dt_janela,"
            " P.hr_janela, P.nu_prescricoes, P.nu_crms_diferentes, P.mediana_hora,"
            " P.mad_hora, P.is_hora_com_alerta, P.is_volume_horario_anomalo,"
            " P.is_crm_unico, P.is_crm_multiplo"
            " FROM temp_CGUSC.fp.app_crm_timeline_hora P"
            " INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.id = P.id_cnpj"
            " WHERE F.cnpj = :cnpj"
            " ORDER BY P.dt_janela, P.hr_janela"
        ),
        {"cnpj": cnpj},
        engine,
        read_existing=False,
    )


def load_or_sync_crm_timeline_eventos(cnpj: str, engine=None) -> CacheLoadResult:
    schema = _empty_schema(CRM_TIMELINE_EVENTOS_PARQUET)
    required = set(schema)
    parquet_path = _path(cnpj, CRM_TIMELINE_EVENTOS_PARQUET)
    df, read_time_ms = _read_parquet(parquet_path)
    if df is not None:
        missing_cols = sorted(required - set(df.columns))
        if not missing_cols:
            return CacheLoadResult(df, from_cache=True, read_time_ms=read_time_ms)
        print(f"[ CACHE ] {cnpj} - timeline eventos - cache sem {', '.join(missing_cols)}; regenerando parquet.")

    return _load_or_sync_sql_cache(
        cnpj,
        CRM_TIMELINE_EVENTOS_PARQUET,
        text(
            "SELECT CONVERT(VARCHAR(10), P.dt_janela, 23) AS dt_janela,"
            " P.tipo, P.hora_inicio, P.hora_fim, P.minuto_inicio, P.minuto_fim,"
            " P.severidade, P.id_medico, P.nu_crms_distintos"
            " FROM temp_CGUSC.fp.app_crm_timeline_eventos P"
            " INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.id = P.id_cnpj"
            " WHERE F.cnpj = :cnpj"
            " ORDER BY P.dt_janela, P.minuto_inicio, P.tipo"
        ),
        {"cnpj": cnpj},
        engine,
        read_existing=False,
    )


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
               A.nu_minutos_span AS nu_minutos_intervalo,
               A.taxa_hora_pior_ritmo AS taxa_hora,
               A.dt_ini_concentracao AS dt_ini_hora,
               A.dt_fim_concentracao AS dt_fim_hora,
               A.id_severidade,
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
    if result.error or result.df is None:
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
               A.nu_minutos_span AS nu_minutos_intervalo,
               A.janela_pior_ritmo_minutos AS nu_minutos_span,
               A.taxa_hora_pior_ritmo AS taxa_hora,
               A.id_severidade,
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
    if result.error or result.df is None:
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
        required_columns = {"dt_janela", "hr_janela", "data_hora", "num_autorizacao", "id_medico", "valor_pago"}
        if required_columns.issubset(set(df.columns)) and "codigo_barra" not in df.columns and version_ok:
            return CacheLoadResult(df, from_cache=True, read_time_ms=read_time_ms)

    schema = _empty_schema(CRM_RAIOX_TX_PARQUET)
    engine = _engine_or_default(engine)
    parts_dir = Path(_get_cnpj_cache_dir(cnpj)) / ".parts" / "crm_raiox_tx"
    parts_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = parts_dir / "manifest.json"

    def _month_floor(value) -> date:
        value_date = value.date() if hasattr(value, "date") else value
        return date(value_date.year, value_date.month, 1)

    def _next_month(value: date) -> date:
        if value.month == 12:
            return date(value.year + 1, 1, 1)
        return date(value.year, value.month + 1, 1)

    def _month_key(value: date) -> str:
        return f"{value.year:04d}-{value.month:02d}"

    def _part_path(key: str) -> Path:
        return parts_dir / f"{key}.smod.part"

    def _read_manifest() -> dict:
        if not manifest_path.exists():
            return {}
        with manifest_path.open("r", encoding="utf-8") as handle:
            return json.load(handle)

    def _write_manifest(data: dict) -> None:
        tmp_path = manifest_path.with_suffix(".json.tmp")
        with tmp_path.open("w", encoding="utf-8") as handle:
            json.dump(data, handle, ensure_ascii=False, indent=2, sort_keys=True)
        os.replace(tmp_path, manifest_path)

    try:
        with engine.connect() as conn:
            bounds = conn.execute(
                text(
                    "SELECT MIN(P.dt_janela) AS dt_min, MAX(P.dt_janela) AS dt_max "
                    "FROM temp_CGUSC.fp.app_crm_raiox_tx P "
                    "INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.id = P.id_cnpj "
                    "WHERE F.cnpj = :cnpj"
                ),
                {"cnpj": cnpj},
            ).mappings().first()

            if not bounds or bounds["dt_min"] is None or bounds["dt_max"] is None:
                empty_df = pl.DataFrame(schema=schema)
                empty_df.write_parquet(parquet_path, compression="zstd")
                return CacheLoadResult(empty_df, from_cache=False)

            start_month = _month_floor(bounds["dt_min"])
            end_exclusive = _next_month(_month_floor(bounds["dt_max"]))
            month_starts: list[date] = []
            cursor = start_month
            while cursor < end_exclusive:
                month_starts.append(cursor)
                cursor = _next_month(cursor)

            manifest = _read_manifest()
            manifest_valid = (
                manifest.get("cnpj") == cnpj
                and manifest.get("cache_key") == "crm_raiox_tx"
                and manifest.get("version") == _CRM_RAIOX_TX_CACHE_VERSION
                and manifest.get("start_month") == _month_key(start_month)
                and manifest.get("end_month") == _month_key(_month_floor(bounds["dt_max"]))
            )
            if not manifest_valid:
                manifest = {
                    "cnpj": cnpj,
                    "cache_key": "crm_raiox_tx",
                    "version": _CRM_RAIOX_TX_CACHE_VERSION,
                    "start_month": _month_key(start_month),
                    "end_month": _month_key(_month_floor(bounds["dt_max"])),
                    "parts": {},
                }
                _write_manifest(manifest)

            query = text(
                "SELECT P.dt_janela, P.hr_janela, MIN(P.data_hora) AS data_hora, "
                "P.num_autorizacao, P.id_medico, SUM(P.valor_pago) AS valor_pago "
                "FROM temp_CGUSC.fp.app_crm_raiox_tx P "
                "INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.id = P.id_cnpj "
                "WHERE F.cnpj = :cnpj "
                "AND P.dt_janela >= :dt_inicio "
                "AND P.dt_janela < :dt_fim "
                "GROUP BY P.dt_janela, P.hr_janela, P.num_autorizacao, P.id_medico "
                "ORDER BY MIN(P.data_hora) ASC, P.num_autorizacao ASC"
            )

            query_time_ms = 0.0
            save_time_ms = 0.0
            total_parts = len(month_starts)
            for index, dt_inicio in enumerate(month_starts, 1):
                dt_fim = _next_month(dt_inicio)
                key = _month_key(dt_inicio)
                part_path = _part_path(key)
                part_info = manifest["parts"].get(key, {})
                if part_info.get("status") == "done" and part_path.exists():
                    continue

                print(f"[ CACHE ] {cnpj} - CRM Raio-X - parte {index}/{total_parts}: {key}")
                t0 = time.perf_counter()
                pdf = pd.read_sql(
                    query,
                    conn,
                    params={"cnpj": cnpj, "dt_inicio": dt_inicio, "dt_fim": dt_fim},
                )
                query_time_ms += (time.perf_counter() - t0) * 1000

                if pdf.empty:
                    df_part = pl.DataFrame(schema=schema)
                else:
                    df_part = pl.from_pandas(pdf).with_columns([
                        pl.col("dt_janela").cast(pl.Utf8),
                        pl.col("hr_janela").cast(pl.Int32),
                        pl.col("num_autorizacao").cast(pl.Utf8),
                        pl.col("id_medico").cast(pl.Utf8),
                        pl.col("data_hora").cast(pl.Utf8),
                        pl.col("valor_pago").cast(pl.Float64),
                        pl.lit(_CRM_RAIOX_TX_CACHE_VERSION).alias("_crm_raiox_tx_cache_version"),
                    ])

                missing_cols = sorted(set(schema) - set(df_part.columns))
                if missing_cols:
                    raise RuntimeError(
                        f"Contrato invalido ao gerar parte {key} de {CRM_RAIOX_TX_PARQUET}: "
                        f"colunas ausentes {', '.join(missing_cols)}."
                    )
                df_part = df_part.select(list(schema.keys()))

                tmp_part_path = part_path.with_suffix(part_path.suffix + ".tmp")
                t1 = time.perf_counter()
                df_part.write_parquet(tmp_part_path, compression="zstd")
                os.replace(tmp_part_path, part_path)
                save_time_ms += (time.perf_counter() - t1) * 1000

                manifest["parts"][key] = {
                    "status": "done",
                    "rows": df_part.height,
                    "file": part_path.name,
                }
                _write_manifest(manifest)

        part_paths = [_part_path(_month_key(dt_inicio)) for dt_inicio in month_starts]
        missing_parts = [path.name for path in part_paths if not path.exists()]
        if missing_parts:
            raise RuntimeError(f"Partes pendentes para consolidar {CRM_RAIOX_TX_PARQUET}: {', '.join(missing_parts)}")

        t_merge = time.perf_counter()
        scan = pl.scan_parquet([str(path) for path in part_paths])
        df_final = scan.collect().sort(["data_hora", "num_autorizacao"]).select(list(schema.keys()))
        tmp_final_path = parquet_path + ".tmp"
        df_final.write_parquet(tmp_final_path, compression="zstd")
        os.replace(tmp_final_path, parquet_path)
        save_time_ms = round(save_time_ms + ((time.perf_counter() - t_merge) * 1000), 1)

        manifest["status"] = "done"
        manifest["final_rows"] = df_final.height
        manifest["final_file"] = os.path.basename(parquet_path)
        _write_manifest(manifest)

        return CacheLoadResult(
            df_final,
            from_cache=False,
            query_time_ms=round(query_time_ms, 1),
            save_time_ms=save_time_ms,
        )
    except Exception as exc:
        print(f"[ ANALYTICS ] {cnpj} - {CRM_RAIOX_TX_PARQUET} - erro ao sincronizar em partes: {exc}")
        return CacheLoadResult(
            pl.DataFrame(schema=schema),
            from_cache=False,
            error=f"Erro ao sincronizar {CRM_RAIOX_TX_PARQUET} em partes: {exc}",
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
