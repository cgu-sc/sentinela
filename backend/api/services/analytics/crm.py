from typing import Any, List, Optional
from datetime import date
import calendar
import polars as pl
from sqlalchemy.orm import Session
from sqlalchemy import text
from fastapi import HTTPException
import os
import zlib
import json
import copy
from decimal import Decimal, ROUND_HALF_UP
from data_cache import get_df, get_rede_df, get_localidades_df, get_df_matriz_risco, get_df_bench_crm_regiao, get_df_bench_crm_br, get_df_dados_farmacia, get_cache_dir
from ...schemas.analytics import (
    AnalyticsKPISchema,
    ResultadoSentinelaUFSchema,
    AnalyticsResponse,
    ResultadoSentinelaSchema,
    ResultadoSentinelaMunicipioSchema,
    ResultadoSentinelaCnpjSchema,
    RedeEstabelecimentoSchema,
    FatorRiscoResponseSchema,
    FatorRiscoBucketSchema,
    EvolucaoSemestreSchema,
    EvolucaoFinanceiraResponse,
    IndicadorDataSchema,
    IndicadoresResponse,
    FalecidoTransactionSchema,
    FalecidosRankingSchema,
    FalecidosSummarySchema,
    FalecidosResponse,
    TimelineEventSchema,
    MultiCnpjTimelineResponse,
    RegionalMunicipioSchema,
    RegionalFarmaciaSchema,
    RegionalResponse,
    RegionalAnimationQuarterSchema,
    RegionalAnimationResponse,
    PrescritoresResponse,
    DadosFarmaciaSchema,
    MovimentacaoRowSchema,
    MovimentacaoSummarySchema,
    MovimentacaoResponse,
    IndicadorKpiSummarySchema,
    IndicadorCnpjRowSchema,
    IndicadorMunicipioRowSchema,
    IndicadorAnaliseResponse,
    CrmDailyProfileResponse,
    CrmHourlyProfileResponse,
    CrmRaioXResponse,
    MesMensalGtinItem,
    EvolucaoMensalGtinResponse,
    GtinDetalhamentoMensalResponse,
    GtinDetalhamentoMensalSummary,
    GtinDetalhamentoMensalItem,
)

from ._cache import _get_cnpj_cache_dir, sync_crm_raiox_tx, sync_mediana_autorizacoes_horaria

_CRM_SEVERITY_CACHE_VERSION = 2
_CRM_ALERTS_CACHE_VERSION = 2


def _to_float(value: Any, default: float = 0.0) -> float:
    """Converte valores de linhas Polars/Pandas para float com estreitamento de tipo."""
    if value is None:
        return default
    if isinstance(value, bool):
        return float(int(value))
    if isinstance(value, (int, float, Decimal)):
        return float(value)
    if isinstance(value, bytes):
        value = value.decode("utf-8", errors="ignore")
    if isinstance(value, str):
        text = value.strip()
        if not text:
            return default
        try:
            return float(text.replace(",", "."))
        except ValueError:
            return default
    return default


def _to_int(value: Any, default: int = 0) -> int:
    """Converte valores de linhas Polars/Pandas para int com estreitamento de tipo."""
    if value is None:
        return default
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, int):
        return value
    if isinstance(value, (float, Decimal)):
        return int(value)
    if isinstance(value, bytes):
        value = value.decode("utf-8", errors="ignore")
    if isinstance(value, str):
        text = value.strip()
        if not text:
            return default
        try:
            return int(float(text.replace(",", ".")))
        except ValueError:
            return default
    return default

def get_crm_data(
    cnpj: str,
    data_inicio: str | None = None,
    data_fim: str | None = None,
) -> PrescritoresResponse:
    """Retorna KPIs e top prescritores de um CNPJ a partir do parquet por CNPJ (lazy cache)."""
    import traceback
    import pandas as pd
    from data_cache import get_cache_dir

    cnpj_dir = _get_cnpj_cache_dir(cnpj)
    PARQUET_PATH = os.path.join(cnpj_dir, "dados_crms.parquet")

    # â”€â”€ helpers de competÃªncia â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    def _to_comp(date_str: str) -> int:
        return int(date_str[:7].replace("-", ""))

    comp_ini = _to_comp(data_inicio) if data_inicio else None
    comp_fim = _to_comp(data_fim)    if data_fim    else None

    # â”€â”€ 1. Carrega ou gera o parquet â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    import time as _time
    df: pl.DataFrame | None = None
    from_cache    = False
    read_time_ms: float | None = None
    query_time_ms: float | None = None
    save_time_ms:  float | None = None
    stale_df: pl.DataFrame | None = None

    if os.path.exists(PARQUET_PATH):
        try:
            _t0 = _time.perf_counter()
            df = pl.read_parquet(PARQUET_PATH)
            read_time_ms = round((_time.perf_counter() - _t0) * 1000, 1)
            if "no_medico" in df.columns:
                from_cache = True
            else:
                print(f"[ CACHE ] {cnpj} ● CRM ● cache sem no_medico; regenerando parquet.")
                stale_df = df.with_columns(pl.lit(None, dtype=pl.Utf8).alias("no_medico"))
                df = None
        except Exception as e:
            print(f"âš ï¸ Erro ao ler parquet CRM '{cnpj}': {e}", flush=True)

    if df is None:
        try:
            from database import engine as _engine
            with _engine.connect() as conn:
                _t0 = _time.perf_counter()
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
                query_time_ms = round((_time.perf_counter() - _t0) * 1000, 1)
            if pdf.empty:
                df = pl.DataFrame(schema={
                    "id_medico": pl.Utf8,
                    "competencia": pl.Int32,
                    "vl_total_prescricoes": pl.Float64,
                    "no_medico": pl.Utf8,
                })
            else:
                df = pl.from_pandas(pdf)
            if "no_medico" not in df.columns:
                df = df.with_columns(pl.lit(None, dtype=pl.Utf8).alias("no_medico"))
            for col in ["flag_crm_invalido", "flag_prescricao_antes_registro", "alerta_concentracao_multiplos_crms"]:
                if col in df.columns:
                    df = df.with_columns(pl.col(col).cast(pl.Int8))
            _t1 = _time.perf_counter()
            df.write_parquet(PARQUET_PATH, compression="zstd")
            save_time_ms = round((_time.perf_counter() - _t1) * 1000, 1)
        except Exception:
            print(f"[ ANALYTICS ] {cnpj} ● CRM ● ❌ INDISPONÍVEL (Sem Cache e Banco Offline)")
            if stale_df is not None:
                df = stale_df
                from_cache = True
            else:
                df = None

    # â”€â”€ 2. Filtro de perÃ­odo â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    # ── 2. Validação de Disponibilidade e Histórico ──────────────────────
    if df is None or len(df.columns) == 0:
        raise HTTPException(
            status_code=503,
            detail="Base de dados de prescrições indisponível no momento (Sem cache local e banco de dados offline)."
        )

    # Verifica se há qualquer dado histórico antes dos filtros de período
    tem_historico = not df.is_empty()

    if comp_ini:
        df = df.filter(pl.col("competencia") >= comp_ini)
    if comp_fim:
        df = df.filter(pl.col("competencia") <= comp_fim)

    if df.is_empty():
        return PrescritoresResponse(cnpj=cnpj, summary={}, crms_interesse=[], from_cache=from_cache, tem_historico=tem_historico,
                                    read_time_ms=read_time_ms, query_time_ms=query_time_ms, save_time_ms=save_time_ms)

    # â”€â”€ 3. Agrega por id_medico (colapsa competÃªncias) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    total_valor = _to_float(df["vl_total_prescricoes"].sum())

    # CÃ¡lculo de dias no perÃ­odo para o ritmo diÃ¡rio real
    from datetime import datetime
    import calendar
    try:
        # Assume formato YYYY-MM ou YYYY-MM-DD
        d_ini_str = data_inicio if data_inicio else "2015-01"
        d_fim_str = data_fim if data_fim else datetime.now().strftime("%Y-%m")
        
        d_ini = datetime.strptime(d_ini_str[:7], "%Y-%m")
        d_fim_base = datetime.strptime(d_fim_str[:7], "%Y-%m")
        last_day = calendar.monthrange(d_fim_base.year, d_fim_base.month)[1]
        d_fim = d_fim_base.replace(day=last_day)
        
        dias_periodo = max((d_fim - d_ini).days + 1, 1)
    except Exception:
        dias_periodo = 30

    # â”€â”€ Dias ativos por mÃ©dico (vetorizado, sem Python callback) â”€â”€â”€â”€â”€â”€â”€â”€â”€
    # Calcula quantos dias tem cada competÃªncia (YYYYMM) criando o 1Âº dia do
    # prÃ³ximo mÃªs e subtraindo 1 dia. Trata a virada de ano (dez â†’ jan).
    _ano  = pl.col("competencia") // 100
    _mes  = pl.col("competencia") % 100
    _prox_ano = pl.when(_mes == 12).then(_ano + 1).otherwise(_ano)
    _prox_mes = pl.when(_mes == 12).then(pl.lit(1)).otherwise(_mes + 1)
    df = df.with_columns([
        (
            pl.date(_prox_ano, _prox_mes, pl.lit(1)) - pl.duration(days=1)
        ).dt.day().alias("dias_competencia")
    ])

    df_med = (
        df.group_by("id_medico")
        .agg([
            pl.sum("vl_total_prescricoes").alias("vl_total_prescricoes"),
            pl.sum("nu_prescricoes_mes").alias("nu_prescricoes"),
            pl.sum("nu_prescricoes_total_brasil").alias("nu_prescricoes_total_brasil"),
            pl.sum("dias_competencia").alias("_dias_ativos"),  # dias reais do mÃ©dico
            pl.col("no_medico").drop_nulls().first().alias("no_medico"),
            pl.max("flag_crm_invalido").alias("flag_crm_invalido"),
            pl.max("flag_prescricao_antes_registro").alias("flag_prescricao_antes_registro"),
            pl.max("alerta_concentracao_multiplos_crms").alias("alerta_concentracao_multiplos_crms"),
            pl.max("flag_concentracao_mesmo_crm").cast(pl.Int8).alias("alerta_concentracao_unico_crm"),
            pl.max("flag_distancia_geografica").cast(pl.Int8).alias("alerta_distancia_geografica"),
            pl.max("flag_distancia_geografica").cast(pl.Int8).alias("alerta5_geografico"),
            pl.min("dt_primeira_prescricao").alias("dt_primeira_prescricao"),
            pl.col("dt_inscricao_crm").first().alias("dt_inscricao_crm"),
            pl.max("nu_estabelecimentos").alias("nu_estabelecimentos"),
        ])
        .with_columns([
            # Divide pelo total de dias dos meses em que o mÃ©dico de fato prescreveu
            (pl.col("nu_prescricoes").cast(pl.Float64) / pl.col("_dias_ativos")).round(2).alias("nu_prescricoes_dia"),
            (pl.col("nu_prescricoes_total_brasil").cast(pl.Float64) / pl.col("_dias_ativos")).round(2).alias("prescricoes_dia_total_brasil"),
        ])
        .with_columns([
            (pl.col("nu_prescricoes_dia") > 30).cast(pl.Int8).alias("flag_robo"),
            (
                (pl.col("prescricoes_dia_total_brasil") > 30) & (pl.col("nu_prescricoes_dia") <= 30)
            ).cast(pl.Int8).alias("flag_robo_oculto"),
        ])
        .with_columns([
            (pl.col("nu_estabelecimentos") == 1).cast(pl.Int8).alias("flag_crm_exclusivo"),
        ])
        .sort("vl_total_prescricoes", descending=True)
        .with_row_index("ranking")
        .with_columns([
            (pl.col("ranking") + 1).alias("ranking"),
            # Mantemos o pct_participacao com alta precisÃ£o para o acumulado
            (pl.col("vl_total_prescricoes") / total_valor * 100).alias("_pct_raw")
            if total_valor > 0 else pl.lit(0.0).alias("_pct_raw"),
        ])
        .with_columns([
            pl.col("_pct_raw").round(2).alias("pct_participacao"),
            pl.col("_pct_raw").cum_sum().clip(0, 100).round(2).alias("pct_acumulado"),
            pl.when(pl.col("nu_prescricoes_total_brasil") > 0)
            .then(
                (pl.col("nu_prescricoes").cast(pl.Float64) /
                 pl.col("nu_prescricoes_total_brasil").cast(pl.Float64) * 100).round(2)
            )
            .otherwise(pl.lit(0.0))
            .alias("pct_volume_aqui_vs_total"),
        ])
    )

    crms_interesse_list = [r for r in df_med.iter_rows(named=True)]

    # â”€â”€ 4. Summary â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    top1       = df_med.row(0, named=True)
    top5_valor = _to_float(df_med.head(5)["vl_total_prescricoes"].sum())

    qtd_robos         = _to_int(df_med["flag_robo"].sum())
    qtd_robos_ocultos = _to_int(df_med["flag_robo_oculto"].sum())
    qtd_invalido      = _to_int(df_med["flag_crm_invalido"].sum())
    qtd_antes_reg     = _to_int(df_med["flag_prescricao_antes_registro"].sum())
    qtd_conc_temp     = _to_int(df["flag_concentracao_mesmo_crm"].sum())

    vl_invalido  = _to_float(df_med.filter(pl.col("flag_crm_invalido") == 1)["vl_total_prescricoes"].sum())
    vl_antes_reg = _to_float(df_med.filter(pl.col("flag_prescricao_antes_registro") == 1)["vl_total_prescricoes"].sum())

    pct_top1      = round(top1["vl_total_prescricoes"] / total_valor * 100, 2) if total_valor else 0.0
    pct_top5      = round(top5_valor / total_valor * 100, 2)                  if total_valor else 0.0
    pct_invalido  = round(vl_invalido  / total_valor * 100, 2)                if total_valor else 0.0
    pct_antes_reg = round(vl_antes_reg / total_valor * 100, 2)                if total_valor else 0.0

    # â”€â”€ 5. Benchmarks â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    bench_top5_reg = 0.0
    bench_top5_br  = 0.0
    try:
        df_farm   = get_df_dados_farmacia()
        row_farm  = df_farm.filter(pl.col("cnpj") == cnpj)
        id_regiao = row_farm["id_regiao_saude"][0] if not row_farm.is_empty() else None

        df_br = get_df_bench_crm_br()
        if comp_ini: df_br = df_br.filter(pl.col("competencia") >= comp_ini)
        if comp_fim: df_br = df_br.filter(pl.col("competencia") <= comp_fim)
        bench_top5_br = _to_float(df_br["mediana_concentracao_top5_br"].mean())

        if id_regiao:
            df_reg = get_df_bench_crm_regiao()
            df_reg = df_reg.filter(pl.col("id_regiao_saude") == id_regiao)
            if comp_ini: df_reg = df_reg.filter(pl.col("competencia") >= comp_ini)
            if comp_fim: df_reg = df_reg.filter(pl.col("competencia") <= comp_fim)
            bench_top5_reg = _to_float(df_reg["mediana_concentracao_top5_reg"].mean())
    except Exception:
        pass

    # â”€â”€ 6. Metadados do CNPJ (matriz de risco) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    razao_social = municipio = uf_str = None
    try:
        df_risco  = get_df_matriz_risco()
        df_risco  = df_risco.rename({c: c.lower() for c in df_risco.columns})
        row_risco = df_risco.filter(pl.col("cnpj") == cnpj)
        if not row_risco.is_empty():
            r            = row_risco.row(0, named=True)
            razao_social = r.get("razaosocial") or r.get("razao_social")
            municipio    = r.get("municipio")
            uf_str       = r.get("uf")
    except Exception:
        pass

    summary_dict = {
        "pct_concentracao_top1":          pct_top1,
        "pct_concentracao_top5":          pct_top5,
        "id_top1_prescritor":             top1.get("id_medico", ""),
        "qtd_prescritores_robos":         qtd_robos,
        "qtd_prescritores_robos_ocultos": qtd_robos_ocultos,
        "qtd_crm_invalido":               qtd_invalido,
        "qtd_crm_antes_registro":         qtd_antes_reg,
        "vl_crm_invalido":                round(vl_invalido,  2),
        "vl_crm_antes_registro":          round(vl_antes_reg, 2),
        "pct_valor_crm_invalido":         pct_invalido,
        "pct_valor_crm_antes_registro":   pct_antes_reg,
        "qtd_prescritores_conc_temporal": qtd_conc_temp,
        "qtd_prescritores_surto":         _to_int(df_med["alerta_concentracao_multiplos_crms"].sum()),
        "mediana_concentracao_top5_reg":  round(bench_top5_reg, 2),
        "mediana_concentracao_top5_br":   round(bench_top5_br,  2),
        "razaoSocial":                    razao_social,
        "municipio":                      municipio,
        "uf":                             uf_str,
        "from_cache":                     os.path.exists(PARQUET_PATH),
    }

    # â”€â”€ 7. Alertas diÃ¡rios â€” injeta em cada mÃ©dico â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    df_ad = _load_crm_unico_alertas(cnpj, cnpj_dir)
    alertas_por_medico: dict[str, list[dict]] = {}
    if not df_ad.is_empty():
        # Filtro de perÃ­odo no DataFrame de alertas
        if comp_ini:
            df_ad = df_ad.filter(
                pl.col("competencia").cast(pl.Int32) >= comp_ini
            )
        if comp_fim:
            df_ad = df_ad.filter(
                pl.col("competencia").cast(pl.Int32) <= comp_fim
            )
            
        for row in df_ad.iter_rows(named=True):
            mid = row["id_medico"]
            alertas_por_medico.setdefault(mid, []).append({
                "dt":             str(row["dt_alerta"]),
                "nu_prescricoes": row["nu_prescricoes_dia"],
                "nu_minutos":     row["nu_minutos_dia"],
                "taxa_hora":      _to_float(row.get("taxa_hora")),
            })

    for m in crms_interesse_list:
        m["alertas_crm_unico"] = alertas_por_medico.get(m["id_medico"], [])

    # ——— 7.1 Alertas Geográficos (Distância) ——————————————————————————————————————
    ALERTAS_GEO_PATH = os.path.join(cnpj_dir, "geografico.parquet")
    df_geo: pl.DataFrame | None = None

    if os.path.exists(ALERTAS_GEO_PATH):
        try: df_geo = pl.read_parquet(ALERTAS_GEO_PATH)
        except Exception as e:
            print(f"[ CACHE ] {cnpj} ● GEO ● ⚠️ ERRO DE LEITURA ({e})")
        
    if df_geo is None:
        try:
            from database import engine as _engine
            with _engine.connect() as conn:
                pdf_geo = pd.read_sql(
                    text("SELECT * FROM temp_CGUSC.fp.app_alertas_crm_geografico WHERE cnpj_a = :cnpj OR cnpj_b = :cnpj"),
                    conn, params={"cnpj": cnpj}
                )
            df_geo = pl.from_pandas(pdf_geo) if not pdf_geo.empty else pl.DataFrame(schema={
                "id_medico": pl.Utf8, "competencia": pl.Int32, "cnpj_a": pl.Utf8, 
                "no_municipio_a": pl.Utf8, "sg_uf_a": pl.Utf8, "dt_ini_a": pl.Utf8, 
                "dt_fim_a": pl.Utf8, "nu_prescricoes_a": pl.Int32, "cnpj_b": pl.Utf8, 
                "no_municipio_b": pl.Utf8, "sg_uf_b": pl.Utf8, "dt_ini_b": pl.Utf8, 
                "dt_fim_b": pl.Utf8, "nu_prescricoes_b": pl.Int32, "distancia_km": pl.Float64
            })
            df_geo.write_parquet(ALERTAS_GEO_PATH, compression="zstd")
        except Exception:
            print(f"[ ANALYTICS ] {cnpj} ● GEO ● ❌ INDISPONÍVEL (Sem Cache e Banco Offline)")
            df_geo = pl.DataFrame()

    alertas_geo_por_medico: dict[str, list[dict]] = {}
    if not df_geo.is_empty():
        if comp_ini: df_geo = df_geo.filter(pl.col("competencia").cast(pl.Int32) >= comp_ini)
        if comp_fim: df_geo = df_geo.filter(pl.col("competencia").cast(pl.Int32) <= comp_fim)
        
        for row in df_geo.iter_rows(named=True):
            mid = row["id_medico"]
            alertas_geo_por_medico.setdefault(mid, []).append({
                "competencia":    row["competencia"],
                "cnpj_a":         row["cnpj_a"],
                "municipio_a":    row["no_municipio_a"],
                "uf_a":           row["sg_uf_a"],
                "dt_ini_a":       str(row["dt_ini_a"]),
                "dt_fim_a":       str(row["dt_fim_a"]),
                "nu_presc_a":     row["nu_prescricoes_a"],
                "cnpj_b":         row["cnpj_b"],
                "municipio_b":    row["no_municipio_b"],
                "uf_b":           row["sg_uf_b"],
                "dt_ini_b":       str(row["dt_ini_b"]),
                "dt_fim_b":       str(row["dt_fim_b"]),
                "nu_presc_b":     row["nu_prescricoes_b"],
                "distancia_km":   _to_float(row.get("distancia_km")),
            })

    for m in crms_interesse_list:
        m["alertas_geograficos"] = alertas_geo_por_medico.get(m["id_medico"], [])

    # ——— 7.2 Alertas de Múltiplos CRMs (Surtos Coordenados) ———————————————————————
    df_cm = _load_crm_multi_alertas(cnpj, cnpj_dir)

    # ——— 7.3 Pré-Sincronização do Raio-X Unificado ———————————————————————————————
    # Garante que o arquivo crm_raiox_tx.parquet exista para uso offline
    try:
        sync_crm_raiox_tx(cnpj)
    except Exception as e:
        print(f"[ ANALYTICS ] {cnpj} ● RAIO-X ● ⚠️ ERRO NA SINCRONIZAÇÃO ({e})")

    # ——— 8. Alertas do Estabelecimento (Cross-CRM) ———————————————————————————————
    CNPJ_ALERTS_PATH = os.path.join(cnpj_dir, "volume_horario_anomalo_alertas.parquet")

    df_ca: pl.DataFrame | None = None

    if os.path.exists(CNPJ_ALERTS_PATH):
        try:
            df_ca = pl.read_parquet(CNPJ_ALERTS_PATH)
        except Exception as e:
            print(f"[ CACHE ] {cnpj} ● SURTOS ● ⚠️ ERRO DE LEITURA ({e})")
    
    if df_ca is None:
        try:
            from database import engine as _engine
            with _engine.connect() as conn:
                pdf_ca = pd.read_sql(
                    text("SELECT V.id_cnpj, V.competencia, V.dt_alerta, V.hr_janela,"
                         " V.nu_prescricoes, V.nu_crms, V.mediana_hora, V.multiplicador"
                         " FROM temp_CGUSC.fp.app_volume_horario_anomalo_alertas V"
                         " INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.id = V.id_cnpj"
                         " WHERE F.cnpj = :cnpj"),
                    conn, params={"cnpj": cnpj}
                )
            df_ca = pl.from_pandas(pdf_ca) if not pdf_ca.empty else pl.DataFrame(schema={
                "id_cnpj": pl.Int32, "competencia": pl.Int32, "dt_alerta": pl.Utf8,
                "hr_janela": pl.Int32, "nu_prescricoes": pl.Int32, "nu_crms": pl.Int32,
                "mediana_hora": pl.Float64, "multiplicador": pl.Float64
            })
            df_ca.write_parquet(CNPJ_ALERTS_PATH, compression="zstd")
        except Exception:
            print(f"[ ANALYTICS ] {cnpj} ● SURTOS ● ❌ INDISPONÍVEL (Sem Cache e Banco Offline)")
            df_ca = pl.DataFrame()

    # ——— 8. Alertas do Estabelecimento (Consolidação das 3 Fontes) —————————————————
    cnpj_alerts_list = []
    
    # 8.1 - Alertas de Volume (df_ca)
    if df_ca is not None and not df_ca.is_empty():
        _ca = df_ca
        if comp_ini: _ca = _ca.filter(pl.col("competencia").cast(pl.Int32) >= comp_ini)
        if comp_fim: _ca = _ca.filter(pl.col("competencia").cast(pl.Int32) <= comp_fim)
        for r in _ca.iter_rows(named=True):
            cnpj_alerts_list.append({
                "tipo": "VOLUME",
                "dt": str(r["dt_alerta"]),
                "hr": _to_int(r.get("hr_janela")),
                "nu_prescricoes": _to_int(r.get("nu_prescricoes")),
                "nu_crms": _to_int(r.get("nu_crms")),
                "multiplicador": _to_float(r.get("multiplicador")),
                "mediana_hora":  _to_float(r.get("mediana_hora"))
            })

    # 8.2 - Alertas de Múltiplos CRMs (df_cm)
    if df_cm is not None and not df_cm.is_empty():
        _cm = df_cm
        if comp_ini: _cm = _cm.filter(pl.col("competencia").cast(pl.Int32) >= comp_ini)
        if comp_fim: _cm = _cm.filter(pl.col("competencia").cast(pl.Int32) <= comp_fim)
        for r in _cm.iter_rows(named=True):
            cnpj_alerts_list.append({
                "tipo": "MULTIPLO",
                "dt": str(r["dt_alerta"]),
                "hr": _to_int(r.get("hr_janela")),
                "nu_prescricoes": _to_int(r.get("nu_prescricoes")),
                "nu_crms": _to_int(r.get("nu_crms")),
                "multiplicador": 0.0,
                "mediana_hora": 0.0
            })

    # 8.3 - Alertas de Médico Único (df_ad - Agregado por Janela)
    # Note: df_ad contém múltiplos alertas por médico. No nível de CNPJ,
    # queremos mostrar quando HOUVE um alerta de médico único.
    if df_ad is not None and not df_ad.is_empty():
        _ad = df_ad
        if comp_ini: _ad = _ad.filter(pl.col("competencia").cast(pl.Int32) >= comp_ini)
        if comp_fim: _ad = _ad.filter(pl.col("competencia").cast(pl.Int32) <= comp_fim)
        
        # Agrupamos por janela para não duplicar se 2 médicos tiveram alerta na mesma hora
        # (embora o frontend lide com isso, é mais limpo consolidar)
        _ad_agg = _ad.group_by(["dt_alerta", "hr_janela"]).agg([
            pl.count("id_medico").alias("nu_crms"),
            pl.sum("nu_prescricoes_dia").alias("nu_prescricoes")
        ])
        for r in _ad_agg.iter_rows(named=True):
            cnpj_alerts_list.append({
                "tipo": "UNICO",
                "dt": str(r["dt_alerta"]),
                "hr": _to_int(r.get("hr_janela")),
                "nu_prescricoes": _to_int(r.get("nu_prescricoes")),
                "nu_crms": _to_int(r.get("nu_crms")),
                "multiplicador": 0.0,
                "mediana_hora": 0.0
            })

    # Ordenação Final por Data/Hora
    cnpj_alerts_list.sort(key=lambda x: (x["dt"], x["hr"]))

    # ——— 9. Cruzamento: Quais surtos do estabelecimento cada CRM participou? ———————
    TX_PARQUET_PATH = os.path.join(cnpj_dir, "crm_raiox_tx.parquet")
    alertas_crm_multiplos_por_medico: dict[str, list[dict]] = {}

    if os.path.exists(TX_PARQUET_PATH):
        try:
            # Carregamos as transações anômalas (Raio-X) do estabelecimento
            df_tx = pl.read_parquet(TX_PARQUET_PATH)
            if not df_tx.is_empty():
                # Filtro de período nas transações se necessário
                if comp_ini or comp_fim:
                    # Garantimos que seja Date para os accessors .dt
                    dt_temp = pl.col("dt_janela")
                    if df_tx["dt_janela"].dtype == pl.Utf8:
                        dt_temp = dt_temp.str.to_date("%Y-%m-%d")
                        
                    df_tx = df_tx.with_columns(
                        (dt_temp.dt.year() * 100 + dt_temp.dt.month()).cast(pl.Int32).alias("_comp")
                    )
                    if comp_ini: df_tx = df_tx.filter(pl.col("_comp") >= comp_ini)
                    if comp_fim: df_tx = df_tx.filter(pl.col("_comp") <= comp_fim)

                # Garantimos que dt_janela seja String para o Join posterior (df_ca usa Utf8)
                df_tx = df_tx.with_columns(pl.col("dt_janela").cast(pl.Utf8).str.slice(0, 10))

                df_cm_period = df_cm
                if comp_ini:
                    df_cm_period = df_cm_period.filter(pl.col("competencia").cast(pl.Int32) >= comp_ini)
                if comp_fim:
                    df_cm_period = df_cm_period.filter(pl.col("competencia").cast(pl.Int32) <= comp_fim)

                def _as_datetime(value):
                    if value is None:
                        return None
                    if hasattr(value, "to_pydatetime"):
                        return value.to_pydatetime()
                    if hasattr(value, "strftime"):
                        return value
                    text_value = str(value)
                    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M:%S.%f", "%Y-%m-%dT%H:%M:%S"):
                        try:
                            from datetime import datetime as _datetime
                            return _datetime.strptime(text_value[:26], fmt)
                        except ValueError:
                            continue
                    return None

                tx_by_date: dict[str, list[dict]] = {}
                for tx in df_tx.iter_rows(named=True):
                    tx_by_date.setdefault(str(tx["dt_janela"])[:10], []).append(tx)

                for alerta in df_cm_period.iter_rows(named=True):
                    dt_alerta = str(alerta["dt_alerta"])[:10]
                    dt_ini = _as_datetime(alerta.get("dt_ini_concentracao"))
                    dt_fim = _as_datetime(alerta.get("dt_fim_concentracao"))
                    if dt_ini is None or dt_fim is None:
                        continue

                    por_medico: dict[str, set] = {}
                    for tx in tx_by_date.get(dt_alerta, []):
                        tx_dt = _as_datetime(tx.get("data_hora"))
                        if tx_dt is None or tx_dt < dt_ini or tx_dt > dt_fim:
                            continue
                        mid = str(tx.get("id_medico") or "")
                        if not mid:
                            continue
                        por_medico.setdefault(mid, set()).add(str(tx.get("num_autorizacao") or ""))

                    hr = _to_int(alerta.get("hr_janela"), dt_ini.hour)
                    total = _to_int(alerta.get("nu_prescricoes"))
                    crms_total = _to_int(alerta.get("nu_crms") or alerta.get("nu_crms_distintos"))
                    severidade = alerta.get("severidade") or "ALERTA"
                    inicio = dt_ini.strftime("%H:%M")
                    fim = dt_fim.strftime("%H:%M")
                    desc = f"{total} autorizacoes entre {inicio} e {fim}, envolvendo {crms_total} CRMs ({severidade})"

                    for mid, autorizacoes in por_medico.items():
                        alertas_crm_multiplos_por_medico.setdefault(mid, []).append({
                            "dt": dt_alerta,
                            "hr": hr,
                            "nu_presc_crm": len(autorizacoes),
                            "nu_presc_total": total,
                            "nu_crms_total": crms_total,
                            "multiplicador": 0,
                            "mediana_hora": 0,
                            "severidade": severidade,
                            "criterio_pior_ritmo": alerta.get("criterio_pior_ritmo"),
                            "descricao": desc
                        })

        except Exception:
            # print(f"⚠️ Erro ao processar cruzamento de surtos para {cnpj}: {e}")
            pass

    # Atribuição final aos médicos
    for m in crms_interesse_list:
        m["alertas_crm_multiplos"] = alertas_crm_multiplos_por_medico.get(m["id_medico"], [])
        m["alerta_concentracao_multiplos_crms"] = 1 if m["alertas_crm_multiplos"] else 0


    return PrescritoresResponse(
        cnpj=cnpj,
        summary=summary_dict,
        crms_interesse=crms_interesse_list,
        cnpj_alerts=cnpj_alerts_list,
        from_cache=from_cache,
        tem_historico=tem_historico,
        read_time_ms=read_time_ms,
        query_time_ms=query_time_ms,
        save_time_ms=save_time_ms,
    )

_CRM_UNICO_RHYTHM_WINDOWS = (5, 10, 15, 20, 25, 30, 60)
_CRM_MULTIPLO_RHYTHM_WINDOWS = (5, 10, 15, 20, 25, 30, 60)
_CRM_UNICO_ALERTAS_CACHE_VERSION = 2

def _best_crm_rhythm_from_row(row: dict, windows: tuple[int, ...]) -> tuple[float, int | None, int | None]:
    best_score = 0.0
    best_count = None
    best_minutes = None

    for minutes in windows:
        raw_count = row.get(f"nu_{minutes}min")
        if raw_count is None:
            continue
        try:
            count = _to_int(raw_count)
        except (TypeError, ValueError):
            continue

        score = (count / minutes) * 60
        if score > best_score:
            best_score = score
            best_count = count
            best_minutes = minutes

    return round(best_score, 2), best_count, best_minutes

def _build_crm_rhythm_map(
    df_alertas: pl.DataFrame,
    date_col: str,
    windows: tuple[int, ...],
    id_col: str | None = None,
    crms_col: str | None = None,
) -> dict[str, dict[str, Any]]:
    scores: dict[str, dict[str, Any]] = {}
    if df_alertas.is_empty():
        return scores

    for row in df_alertas.iter_rows(named=True):
        try:
            count = _to_int(row.get("nu_prescricoes"))
            minutes = _to_int(row.get("nu_minutos_span"))
        except (TypeError, ValueError):
            count = 0
            minutes = 0

        if count > 0 and minutes > 0:
            score = round((count * 60.0) / minutes, 2)
        else:
            score, count, minutes = _best_crm_rhythm_from_row(row, windows)

        if score <= 0:
            continue

        day = str(row.get(date_col, ""))[:10]
        if not day:
            continue

        current = scores.get(day)
        if current and score <= current["score"]:
            continue

        item: dict[str, Any] = {"score": score, "qtd": count, "minutos": minutes}
        if id_col:
            item["id_medico"] = str(row.get(id_col) or "")
        if crms_col:
            try:
                item["nu_crms"] = _to_int(row.get(crms_col))
            except (TypeError, ValueError):
                item["nu_crms"] = None
        scores[day] = item

    return scores

def _build_crm_unico_concentration_map(df_alertas: pl.DataFrame) -> dict[str, dict[str, Any]]:
    scores: dict[str, dict[str, Any]] = {}
    if df_alertas.is_empty():
        return scores

    for row in df_alertas.iter_rows(named=True):
        try:
            count = _to_int(row.get("nu_prescricoes_dia"))
            minutes = _to_int(row.get("nu_minutos_dia"))
        except (TypeError, ValueError):
            continue

        if count <= 0 or minutes <= 0:
            continue

        score = round((count * 60.0) / minutes, 2)
        day = str(row.get("dt_alerta", ""))[:10]
        if not day:
            continue

        current = scores.get(day)
        if current and score <= current["score"]:
            continue

        scores[day] = {
            "score": score,
            "qtd": count,
            "minutos": minutes,
            "id_medico": str(row.get("id_medico") or ""),
        }

    return scores

def _load_crm_unico_alertas(cnpj: str, cnpj_dir: str) -> pl.DataFrame:
    alertas_path = os.path.join(cnpj_dir, "crm_concentracao_unico_alertas.parquet")
    rhythm_columns = {f"nu_{minutes}min" for minutes in _CRM_UNICO_RHYTHM_WINDOWS}
    required_columns = {
        "id_medico",
        "competencia",
        "dt_alerta",
        "hr_janela",
        "nu_prescricoes_dia",
        "nu_minutos_dia",
        "taxa_hora",
        "dt_ini_hora",
        "dt_fim_hora",
        "severidade",
        "criterio_pior_ritmo",
        "_crm_alerts_cache_version",
        *rhythm_columns,
    }

    if os.path.exists(alertas_path):
        try:
            cached_df = pl.read_parquet(alertas_path)
            has_current_version = (
                "_crm_alerts_cache_version" in cached_df.columns
                and (cached_df.height == 0 or _to_int(cached_df["_crm_alerts_cache_version"].max()) >= _CRM_ALERTS_CACHE_VERSION)
            )
            if required_columns.issubset(set(cached_df.columns)) and has_current_version:
                return cached_df
        except Exception:
            pass

    schema = {
        "id_medico": pl.Utf8,
        "competencia": pl.Int32,
        "dt_alerta": pl.Utf8,
        "hr_janela": pl.Int32,
        "nu_prescricoes_dia": pl.Int32,
        "nu_minutos_dia": pl.Int32,
        "taxa_hora": pl.Float64,
        "dt_ini_hora": pl.Datetime,
        "dt_fim_hora": pl.Datetime,
        "severidade": pl.Utf8,
        "criterio_pior_ritmo": pl.Utf8,
        "_crm_alerts_cache_version": pl.Int32,
        **{f"nu_{minutes}min": pl.Int32 for minutes in _CRM_UNICO_RHYTHM_WINDOWS},
    }

    try:
        import pandas as pd
        from database import engine as _engine

        with _engine.connect() as conn:
            pdf_alertas = pd.read_sql(
                text("""
                    SELECT
                        A.id_medico,
                        YEAR(A.dt_dia) * 100 + MONTH(A.dt_dia) AS competencia,
                        A.dt_dia AS dt_alerta,
                        DATEPART(HOUR, A.dt_ini_concentracao) AS hr_janela,
                        A.nu_autorizacoes_pior_ritmo AS nu_prescricoes_dia,
                        A.janela_pior_ritmo_minutos AS nu_minutos_dia,
                        A.taxa_hora_pior_ritmo AS taxa_hora,
                        A.dt_ini_concentracao AS dt_ini_hora,
                        A.dt_fim_concentracao AS dt_fim_hora,
                        CASE A.id_severidade
                            WHEN 4 THEN 'EXTREMO'
                            WHEN 3 THEN 'CRITICO'
                            WHEN 2 THEN 'GRAVE'
                            WHEN 1 THEN 'ALTO'
                            ELSE 'ALERTA'
                        END AS severidade,
                        A.criterio_pior_ritmo,
                        A.nu_5min,
                        A.nu_10min,
                        A.nu_15min,
                        A.nu_20min,
                        A.nu_25min,
                        A.nu_30min,
                        A.nu_60min
                    FROM temp_CGUSC.fp.app_crm_concentracao_unico_alertas A
                    INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.id = A.id_cnpj
                    WHERE F.cnpj = :cnpj
                    ORDER BY A.dt_dia, A.id_medico, A.dt_ini_concentracao
                """),
                conn,
                params={"cnpj": cnpj},
            )

        df_alertas = pl.from_pandas(pdf_alertas) if not pdf_alertas.empty else pl.DataFrame(schema=schema)
        df_alertas = df_alertas.with_columns(pl.lit(_CRM_ALERTS_CACHE_VERSION).alias("_crm_alerts_cache_version"))
        df_alertas.write_parquet(alertas_path, compression="zstd")
        return df_alertas
    except Exception as e:
        print(f"Erro ao sincronizar alertas unicos do Raio-X '{cnpj}': {e}")
        return pl.DataFrame(schema=schema)

def get_crm_perfil_diario(
    cnpj: str,
    data_inicio: str | None = None,
    data_fim: str | None = None
) -> "CrmDailyProfileResponse":
    """Retorna o perfil diário unificado de dispensação de um CNPJ.

    Cada dia inclui três flags independentes:
      - is_dia_com_volume_horario_anomalo: surto horário de volume
      - is_anomalo_unico:                  concentração temporal de médico individual
      - is_crm_multiplo:                  concentração temporal com múltiplos CRMs

    Fonte: temp_CGUSC.fp.app_crm_perfil_diario
    Cache: sentinela_cache/<cnpj>/crm_perfil_diario.parquet
    """
    import pandas as pd

    cnpj_dir = _get_cnpj_cache_dir(cnpj)
    PARQUET_PATH = os.path.join(cnpj_dir, "crm_perfil_diario.parquet")

    import time as _time
    df: pl.DataFrame | None = None
    from_cache    = False
    read_time_ms: float | None = None
    query_time_ms: float | None = None
    save_time_ms:  float | None = None

    if os.path.exists(PARQUET_PATH):
        try:
            _t0 = _time.perf_counter()
            df = pl.read_parquet(PARQUET_PATH)
            if "is_crm_multiplo" not in df.columns:
                df = None
                raise ValueError("Parquet crm_perfil_diario sem coluna is_crm_multiplo; regenerando cache.")
            read_time_ms = round((_time.perf_counter() - _t0) * 1000, 1)
            from_cache = True
        except Exception as e:
            print(f"[ CACHE ] {cnpj} ● PERFIL DIÁRIO ● ⚠️ ERRO DE LEITURA ({e})")

    if df is None:
        try:
            from database import engine as _engine
            with _engine.connect() as conn:
                _t0 = _time.perf_counter()
                pdf = pd.read_sql(
                    text("SELECT P.* FROM temp_CGUSC.fp.app_crm_perfil_diario P"
                         " INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.id = P.id_cnpj"
                         " WHERE F.cnpj = :cnpj ORDER BY P.dt_janela"),
                    conn,
                    params={"cnpj": cnpj},
                )
                query_time_ms = round((_time.perf_counter() - _t0) * 1000, 1)
            df = pl.from_pandas(pdf)
            _t1 = _time.perf_counter()
            df.write_parquet(PARQUET_PATH, compression="zstd")
            save_time_ms = round((_time.perf_counter() - _t1) * 1000, 1)
        except Exception:
            print(f"[ ANALYTICS ] {cnpj} ● PERFIL DIÁRIO ● ❌ INDISPONÍVEL (Sem Cache e Banco Offline)")
            df = pl.DataFrame()

    if df.is_empty():
        return CrmDailyProfileResponse(cnpj=cnpj, days=[], from_cache=from_cache,
                                       read_time_ms=read_time_ms, query_time_ms=query_time_ms, save_time_ms=save_time_ms)

    # --- Filtro de Período ---
    if data_inicio:
        d_ini = data_inicio if len(data_inicio) == 10 else f"{data_inicio}-01"
        df = df.filter(pl.col("dt_janela").cast(pl.Utf8) >= d_ini)
    if data_fim:
        d_fim = data_fim if len(data_fim) == 10 else f"{data_fim}-31"
        df = df.filter(pl.col("dt_janela").cast(pl.Utf8) <= d_fim)

    if df.is_empty():
        return CrmDailyProfileResponse(cnpj=cnpj, days=[], from_cache=from_cache,
                                       read_time_ms=read_time_ms, query_time_ms=query_time_ms, save_time_ms=save_time_ms)

    unico_scores: dict[str, dict] = {}
    multi_scores: dict[str, dict] = {}
    try:
        unico_scores = _build_crm_unico_concentration_map(
            _load_crm_unico_alertas(cnpj, cnpj_dir)
        )
        multi_scores = _build_crm_rhythm_map(
            _load_crm_multi_alertas(cnpj, cnpj_dir),
            date_col="dt_dia",
            windows=_CRM_MULTIPLO_RHYTHM_WINDOWS,
            crms_col="nu_crms_distintos",
        )
    except Exception as e:
        print(f"Erro ao calcular scores de criticidade CRM '{cnpj}': {e}")

    days = [
        {
            "dt_janela":             str(r["dt_janela"])[:10],
            "competencia":           _to_int(r.get("competencia")),
            "nu_prescricoes_dia":    _to_int(r.get("nu_prescricoes_dia")),
            "nu_crms_distintos":     _to_int(r.get("nu_crms_distintos")),
            "mediana_diaria":        _to_float(r.get("mediana_diaria")),
            "is_dia_com_volume_horario_anomalo": _to_int(r.get("is_dia_com_volume_horario_anomalo")),
            "is_anomalo_unico":      _to_int(r.get("is_anomalo_unico")),
            "is_crm_multiplo":       _to_int(r.get("is_crm_multiplo")),
            "score_crm_unico_hora":   unico_scores.get(str(r["dt_janela"])[:10], {}).get("score"),
            "score_crm_unico_qtd":    unico_scores.get(str(r["dt_janela"])[:10], {}).get("qtd"),
            "score_crm_unico_minutos": unico_scores.get(str(r["dt_janela"])[:10], {}).get("minutos"),
            "score_crm_unico_medico": unico_scores.get(str(r["dt_janela"])[:10], {}).get("id_medico"),
            "score_crm_multiplo_hora": multi_scores.get(str(r["dt_janela"])[:10], {}).get("score"),
            "score_crm_multiplo_qtd": multi_scores.get(str(r["dt_janela"])[:10], {}).get("qtd"),
            "score_crm_multiplo_minutos": multi_scores.get(str(r["dt_janela"])[:10], {}).get("minutos"),
            "score_crm_multiplo_crms": multi_scores.get(str(r["dt_janela"])[:10], {}).get("nu_crms"),
        }
        for r in df.iter_rows(named=True)
    ]
    return CrmDailyProfileResponse(cnpj=cnpj, days=days, from_cache=from_cache,
                                   read_time_ms=read_time_ms, query_time_ms=query_time_ms, save_time_ms=save_time_ms)

def get_crm_perfil_horario(
    cnpj: str,
    data_inicio: str | None = None,
    data_fim: str | None = None
) -> CrmHourlyProfileResponse:
    """Retorna o detalhamento horário (0-23h) de todos os dias anômalos do CNPJ.

    Inclui is_hora_com_alerta, is_volume_horario_anomalo, is_crm_unico e is_crm_multiplo
    por ponto horário, lidos de temp_CGUSC.fp.app_crm_perfil_horario.
    Cache: sentinela_cache/<cnpj>/crm_horario.parquet
    """
    import pandas as pd
    from sqlalchemy import text
    
    cnpj_dir = _get_cnpj_cache_dir(cnpj)
    PARQUET_PATH = os.path.join(cnpj_dir, "crm_horario.parquet")
    EVENTS_PARQUET_PATH = os.path.join(cnpj_dir, "crm_horario_eventos.parquet")

    import time as _time
    df: pl.DataFrame | None = None
    from_cache    = False
    read_time_ms: float | None = None
    query_time_ms: float | None = None
    save_time_ms:  float | None = None

    if os.path.exists(PARQUET_PATH):
        try:
            _t0 = _time.perf_counter()
            df = pl.read_parquet(PARQUET_PATH)
            if "is_crm_multiplo" not in df.columns or "is_hora_com_alerta" not in df.columns:
                df = None
                raise ValueError("Parquet crm_horario sem colunas atualizadas; regenerando cache.")
            read_time_ms = round((_time.perf_counter() - _t0) * 1000, 1)
            from_cache = True
        except Exception as e:
            print(f"[ CACHE ] {cnpj} ● PERFIL HORÁRIO ● ⚠️ ERRO DE LEITURA ({e})")

    if df is None:
        try:
            from database import engine as _engine
            with _engine.connect() as conn:
                _t0 = _time.perf_counter()
                pdf = pd.read_sql(
                    text("SELECT P.dt_janela, P.hr_janela, P.nu_prescricoes, P.nu_crms_diferentes, P.mediana_hora, "
                         "P.is_hora_com_alerta, P.is_volume_horario_anomalo, P.is_crm_unico, P.is_crm_multiplo "
                         "FROM temp_CGUSC.fp.app_crm_perfil_horario P "
                         "INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.id = P.id_cnpj "
                         "WHERE F.cnpj = :cnpj "
                         "ORDER BY P.dt_janela, P.hr_janela"),
                    conn,
                    params={"cnpj": cnpj},
                )
                query_time_ms = round((_time.perf_counter() - _t0) * 1000, 1)
            df = pl.from_pandas(pdf)
            _t1 = _time.perf_counter()
            df.write_parquet(PARQUET_PATH, compression="zstd")
            save_time_ms = round((_time.perf_counter() - _t1) * 1000, 1)
        except Exception:
            print(f"[ ANALYTICS ] {cnpj} ● PERFIL HORÁRIO ● ❌ INDISPONÍVEL (Sem Cache e Banco Offline)")
            df = pl.DataFrame()

    if df.is_empty():
        return CrmHourlyProfileResponse(cnpj=cnpj, points=[], from_cache=from_cache,
                                        read_time_ms=read_time_ms, query_time_ms=query_time_ms, save_time_ms=save_time_ms)

    # --- Filtro de Período ---
    if data_inicio:
        d_ini = data_inicio if len(data_inicio) == 10 else f"{data_inicio}-01"
        df = df.filter(pl.col("dt_janela").cast(pl.Utf8) >= d_ini)
    if data_fim:
        d_fim = data_fim if len(data_fim) == 10 else f"{data_fim}-31"
        df = df.filter(pl.col("dt_janela").cast(pl.Utf8) <= d_fim)

    if df.is_empty():
        return CrmHourlyProfileResponse(cnpj=cnpj, points=[], events=[], from_cache=from_cache,
                                        read_time_ms=read_time_ms, query_time_ms=query_time_ms, save_time_ms=save_time_ms)

    # --- 2. Carregar/Gerar Eventos Temporais (Trilha) ---
    df_events: pl.DataFrame | None = None
    if os.path.exists(EVENTS_PARQUET_PATH):
        try:
            df_events = pl.read_parquet(EVENTS_PARQUET_PATH)
            if (
                "_crm_severity_cache_version" not in df_events.columns
                or _to_int(df_events["_crm_severity_cache_version"].max()) < _CRM_SEVERITY_CACHE_VERSION
            ):
                df_events = None
                raise ValueError("Parquet crm_horario_eventos com severidade legada; regenerando cache.")
        except Exception as e:
            print(f"[ CACHE ] {cnpj} ● EVENTOS HORÁRIO ● ⚠️ ERRO DE LEITURA ({e})")
            pass

    if df_events is None:
        try:
            from database import engine as _engine
            with _engine.connect() as conn:
                pdf_events = pd.read_sql(
                    text("""
                        SELECT 
                            'UNICO' as tipo,
                            A.dt_dia,
                            A.id_medico,
                            NULL as nu_crms_distintos,
                            A.dt_ini_concentracao,
                            A.dt_fim_concentracao,
                            CASE A.id_severidade
                                WHEN 4 THEN 'EXTREMO'
                                WHEN 3 THEN 'CRITICO'
                                WHEN 2 THEN 'GRAVE'
                                WHEN 1 THEN 'ALTO'
                                ELSE 'ALERTA'
                            END AS severidade
                        FROM temp_CGUSC.fp.app_crm_concentracao_unico_alertas A
                        INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.id = A.id_cnpj
                        WHERE F.cnpj = :cnpj
                        
                        UNION ALL
                        
                        SELECT 
                            'MULTIPLO' as tipo,
                            A.dt_dia,
                            NULL as id_medico,
                            A.nu_crms_distintos,
                            A.dt_ini_concentracao,
                            A.dt_fim_concentracao,
                            CASE A.id_severidade
                                WHEN 4 THEN 'EXTREMO'
                                WHEN 3 THEN 'CRITICO'
                                WHEN 2 THEN 'GRAVE'
                                WHEN 1 THEN 'ALTO'
                                ELSE 'ALERTA'
                            END AS severidade
                        FROM temp_CGUSC.fp.app_crm_concentracao_multiplo_alertas A
                        INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.id = A.id_cnpj
                        WHERE F.cnpj = :cnpj
                        
                        UNION ALL
                        
                        SELECT 
                            'VOLUME' as tipo,
                            V.dt_alerta as dt_dia,
                            NULL as id_medico,
                            V.nu_crms as nu_crms_distintos,
                            DATEADD(HOUR, V.hr_janela, CAST(V.dt_alerta AS DATETIME)) as dt_ini_concentracao,
                            DATEADD(HOUR, V.hr_janela + 1, CAST(V.dt_alerta AS DATETIME)) as dt_fim_concentracao,
                            'CRITICO' as severidade
                        FROM temp_CGUSC.fp.app_volume_horario_anomalo_alertas V
                        INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.id = V.id_cnpj
                        WHERE F.cnpj = :cnpj
                    """),
                    conn,
                    params={"cnpj": cnpj}
                )
                df_events = pl.from_pandas(pdf_events)
                # Cálculos de minutos e formatação
                if not df_events.is_empty():
                    df_events = df_events.with_columns([
                        pl.col("dt_ini_concentracao").dt.strftime("%H:%M").alias("hora_inicio"),
                        pl.col("dt_fim_concentracao").dt.strftime("%H:%M").alias("hora_fim"),
                        (pl.col("dt_ini_concentracao").dt.hour() * 60 + pl.col("dt_ini_concentracao").dt.minute()).alias("minuto_inicio"),
                        (pl.col("dt_fim_concentracao").dt.hour() * 60 + pl.col("dt_fim_concentracao").dt.minute()).alias("minuto_fim"),
                        pl.lit(_CRM_SEVERITY_CACHE_VERSION).alias("_crm_severity_cache_version"),
                    ])
                df_events.write_parquet(EVENTS_PARQUET_PATH, compression="zstd")
        except Exception:
            print(f"[ ANALYTICS ] {cnpj} ● PERFIL HORÁRIO ● ❌ INDISPONÍVEL (Sem Cache e Banco Offline)")
            df_events = pl.DataFrame()

    # Filtro de período nos eventos
    if not df_events.is_empty():
        if data_inicio:
            d_ini = data_inicio if len(data_inicio) == 10 else f"{data_inicio}-01"
            df_events = df_events.filter(pl.col("dt_dia").cast(pl.Utf8) >= d_ini)
        if data_fim:
            d_fim = data_fim if len(data_fim) == 10 else f"{data_fim}-31"
            df_events = df_events.filter(pl.col("dt_dia").cast(pl.Utf8) <= d_fim)

    # Garante que o parquet de medianas existe (auto-warming)
    sync_mediana_autorizacoes_horaria(cnpj)

    # Carrega lookup de medianas: (ano, trimestre, hr_janela) â†’ mediana_hora
    from datetime import datetime as _dt
    MEDIANA_PATH = os.path.join(cnpj_dir, "mediana_autorizacoes_horaria.parquet")
    mediana_lookup: dict = {}
    if os.path.exists(MEDIANA_PATH):
        try:
            df_med = pl.read_parquet(MEDIANA_PATH)
            for r in df_med.iter_rows(named=True):
                mediana_lookup[(_to_int(r.get("ano")), _to_int(r.get("trimestre")), _to_int(r.get("hr_janela")))] = _to_float(r.get("mediana_hora"))
        except Exception:
            pass

    # Indexa atividade real e flags de anomalia por (data, hora)
    activity: dict = {}
    dates_flags: dict = {}
    for r in df.iter_rows(named=True):
        dt = str(r["dt_janela"])[:10]
        activity[(dt, _to_int(r.get("hr_janela")))] = r
        if dt not in dates_flags:
            dates_flags[dt] = {
                "is_volume_horario_anomalo": _to_int(r.get("is_volume_horario_anomalo")),
                "is_crm_unico":              _to_int(r.get("is_crm_unico")),
                "is_crm_multiplo":           _to_int(r.get("is_crm_multiplo")),
            }

    # Expande para 24 horas por dia anÃ´malo com mediana real para todas as horas
    points = []
    for dt in sorted(dates_flags):
        flags = dates_flags[dt]
        try:
            d = _dt.strptime(dt, "%Y-%m-%d")
            ano, trimestre = d.year, (d.month - 1) // 3
        except Exception:
            ano, trimestre = 0, 0
        for h in range(24):
            row = activity.get((dt, h))
            mediana = mediana_lookup.get((ano, trimestre, h), 0.0)
            
            # Pega as flags da HORA especÃ­fica (row), nÃ£o do dia (flags)
            is_vol = _to_int(row.get("is_volume_horario_anomalo")) if row else 0
            is_uni = _to_int(row.get("is_crm_unico")) if row else 0
            is_mul = _to_int(row.get("is_crm_multiplo")) if row else 0
            
            points.append({
                "dt_janela":          dt,
                "hr_janela":          h,
                "nu_prescricoes":     _to_int(row.get("nu_prescricoes"))     if row else 0,
                "nu_crms_diferentes": _to_int(row.get("nu_crms_diferentes")) if row else 0,
                "mediana_hora":       mediana,
                "is_hora_com_alerta": 1 if (is_vol or is_uni or is_mul) else 0,
                "is_volume_horario_anomalo": is_vol,
                "is_crm_unico":              is_uni,
                "is_crm_multiplo":           is_mul,
            })

    # Prepara lista de eventos
    events_list = []
    if not df_events.is_empty():
        events_list = [
            {
                "dt_janela":        str(r["dt_dia"])[:10],
                "tipo":             r["tipo"],
                "hora_inicio":      r["hora_inicio"],
                "hora_fim":         r["hora_fim"],
                "minuto_inicio":    _to_int(r.get("minuto_inicio")),
                "minuto_fim":       _to_int(r.get("minuto_fim")),
                "severidade":       r["severidade"],
                "id_medico":        r["id_medico"],
                "nu_crms_distintos": r["nu_crms_distintos"]
            }
            for r in df_events.iter_rows(named=True)
        ]

    # AUTO-WARMING: PrÃ©-aquece o parquet de TransaÃ§Ãµes Literais (Raio-X Unificado)
    sync_crm_raiox_tx(cnpj)

    return CrmHourlyProfileResponse(cnpj=cnpj, points=points, events=events_list, from_cache=from_cache,
                                    read_time_ms=read_time_ms, query_time_ms=query_time_ms, save_time_ms=save_time_ms)

def _format_alert_time(value) -> Optional[str]:
    if value is None:
        return None
    if hasattr(value, "strftime"):
        return value.strftime("%H:%M")
    text_value = str(value)
    if " " in text_value:
        text_value = text_value.split(" ", 1)[1]
    return text_value[:5]

def _extract_alert_hour(value) -> Optional[int]:
    if value is None:
        return None
    if hasattr(value, "hour"):
        return int(value.hour)
    text_value = str(value)
    if " " in text_value:
        text_value = text_value.split(" ", 1)[1]
    try:
        return int(text_value[:2])
    except (TypeError, ValueError):
        return None

def _alert_overlaps_hour(start_value, end_value, hour: Optional[int]) -> bool:
    if hour is None:
        return True

    target_hour = int(hour)
    start_hour = _extract_alert_hour(start_value)
    end_hour = _extract_alert_hour(end_value)

    if start_hour is None and end_hour is None:
        return False

    if start_hour is None:
        start_hour = end_hour
    if end_hour is None:
        end_hour = start_hour

    if start_hour is None or end_hour is None:
        return False

    if end_hour < start_hour:
        return target_hour >= start_hour or target_hour <= end_hour
    return start_hour <= target_hour <= end_hour

def _load_crm_multi_alertas(cnpj: str, cnpj_dir: str) -> pl.DataFrame:
    alertas_path = os.path.join(cnpj_dir, "crm_concentracao_multiplo_alertas.parquet")
    rhythm_columns = {f"nu_{minutes}min" for minutes in _CRM_MULTIPLO_RHYTHM_WINDOWS}
    required_columns = {
        "id_cnpj",
        "competencia",
        "dt_dia",
        "dt_alerta",
        "hr_janela",
        "dt_ini_concentracao",
        "dt_fim_concentracao",
        "nu_prescricoes",
        "nu_crms",
        "nu_60min",
        "nu_minutos_span",
        "nu_crms_distintos",
        "severidade",
        "criterio_pior_ritmo",
        "_crm_alerts_cache_version",
        *rhythm_columns,
    }

    if os.path.exists(alertas_path):
        try:
            cached_df = pl.read_parquet(alertas_path)
            has_current_version = (
                "_crm_alerts_cache_version" in cached_df.columns
                and (cached_df.height == 0 or _to_int(cached_df["_crm_alerts_cache_version"].max()) >= _CRM_ALERTS_CACHE_VERSION)
            )
            if required_columns.issubset(set(cached_df.columns)) and has_current_version:
                return cached_df
        except Exception:
            pass

    try:
        import pandas as pd
        from database import engine as _engine

        with _engine.connect() as conn:
            pdf_alertas = pd.read_sql(
                text("""
                    SELECT
                        A.id_cnpj,
                        YEAR(A.dt_dia) * 100 + MONTH(A.dt_dia) AS competencia,
                        A.dt_dia,
                        A.dt_ini_concentracao AS dt_alerta,
                        DATEPART(HOUR, A.dt_ini_concentracao) AS hr_janela,
                        A.dt_ini_concentracao,
                        A.dt_fim_concentracao,
                        A.nu_autorizacoes_pior_ritmo AS nu_prescricoes,
                        A.nu_crms_distintos AS nu_crms,
                        A.nu_60min,
                        A.janela_pior_ritmo_minutos AS nu_minutos_span,
                        A.nu_crms_distintos,
                        CASE A.id_severidade
                            WHEN 4 THEN 'EXTREMO'
                            WHEN 3 THEN 'CRITICO'
                            WHEN 2 THEN 'GRAVE'
                            WHEN 1 THEN 'ALTO'
                            ELSE 'ALERTA'
                        END AS severidade,
                        A.criterio_pior_ritmo,
                        A.nu_5min,
                        A.nu_10min,
                        A.nu_15min,
                        A.nu_20min,
                        A.nu_25min,
                        A.nu_30min
                    FROM temp_CGUSC.fp.app_crm_concentracao_multiplo_alertas A
                    INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.id = A.id_cnpj
                    WHERE F.cnpj = :cnpj
                """),
                conn,
                params={"cnpj": cnpj},
            )

        df_alertas = pl.from_pandas(pdf_alertas) if not pdf_alertas.empty else pl.DataFrame(schema={
            "id_cnpj": pl.Int32,
            "competencia": pl.Int32,
            "dt_dia": pl.Utf8,
            "dt_alerta": pl.Utf8,
            "hr_janela": pl.Int32,
            "dt_ini_concentracao": pl.Utf8,
            "dt_fim_concentracao": pl.Utf8,
            "nu_prescricoes": pl.Int32,
            "nu_crms": pl.Int32,
            "nu_60min": pl.Int32,
            "nu_minutos_span": pl.Int32,
            "nu_crms_distintos": pl.Int32,
            "severidade": pl.Utf8,
            "criterio_pior_ritmo": pl.Utf8,
            "_crm_alerts_cache_version": pl.Int32,
            **{f"nu_{minutes}min": pl.Int32 for minutes in _CRM_MULTIPLO_RHYTHM_WINDOWS if minutes != 60},
        })
        df_alertas = df_alertas.with_columns(pl.lit(_CRM_ALERTS_CACHE_VERSION).alias("_crm_alerts_cache_version"))
        df_alertas.write_parquet(alertas_path, compression="zstd")
        return df_alertas
    except Exception as e:
        print(f"Erro ao sincronizar alertas multiplos '{cnpj}': {e}")
        return pl.DataFrame()

def get_crm_raio_x(cnpj: str, date_str: str, hour: Optional[int] = None) -> "CrmRaioXResponse":
    """Retorna transacoes e alertas CRM unificados para uma data/hora."""
    cnpj_dir = _get_cnpj_cache_dir(cnpj)
    parquet_path = os.path.join(cnpj_dir, "crm_raiox_tx.parquet")

    sync_crm_raiox_tx(cnpj)

    read_time_ms = None
    transactions: list[dict] = []

    try:
        import time as _time

        if os.path.exists(parquet_path):
            t0 = _time.perf_counter()
            df = pl.read_parquet(parquet_path)
            read_time_ms = round((_time.perf_counter() - t0) * 1000, 1)

            filter_expr = pl.col("dt_janela").cast(pl.Utf8).str.slice(0, 10) == date_str
            if hour is not None:
                filter_expr = filter_expr & (pl.col("hr_janela") == hour)

            filtered_df = df.filter(filter_expr)
            if not filtered_df.is_empty():
                from data_cache import get_medicamentos_df

                df_med = get_medicamentos_df().select(["codigo_barra", "produto", "principio_ativo"])
                enriched_df = filtered_df.join(df_med, on="codigo_barra", how="left")
                enriched_df = enriched_df.with_columns([
                    pl.col("num_autorizacao").cast(pl.Utf8),
                    pl.col("id_medico").cast(pl.Utf8),
                    pl.col("codigo_barra").cast(pl.Utf8),
                    pl.col("data_hora").cast(pl.Utf8),
                ])
                transactions = enriched_df.to_dicts()

        alertas_unico: list[dict] = []
        unico_path = os.path.join(cnpj_dir, "crm_concentracao_unico_alertas.parquet")
        if os.path.exists(unico_path):
            df_unico = pl.read_parquet(unico_path)
            day_unico = df_unico.filter(pl.col("dt_alerta").cast(pl.Utf8).str.slice(0, 10) == date_str)
            if hour is not None:
                day_unico = day_unico.filter(
                    pl.struct(["dt_ini_hora", "dt_fim_hora"]).map_elements(
                        lambda r: _alert_overlaps_hour(
                            r.get("dt_ini_hora"),
                            r.get("dt_fim_hora"),
                            hour,
                        ),
                        return_dtype=pl.Boolean,
                    )
                )
            for r in day_unico.iter_rows(named=True):
                ritmo_qtd = _to_int(r.get("nu_prescricoes_dia"))
                ritmo_minutos = _to_int(r.get("nu_minutos_dia"))
                ritmo_hora = round((ritmo_qtd * 60.0 / ritmo_minutos), 2) if ritmo_minutos > 0 else 0.0
                alertas_unico.append({
                    "id_medico": str(r["id_medico"]),
                    "hr_janela": _to_int(r.get("hr_janela")),
                    "nu_prescricoes_dia": _to_int(r.get("nu_prescricoes_dia")),
                    "nu_minutos_dia": _to_int(r.get("nu_minutos_dia")),
                    "taxa_hora": _to_float(r.get("taxa_hora")),
                    "ritmo_hora": ritmo_hora,
                    "ritmo_qtd": ritmo_qtd,
                    "ritmo_minutos": ritmo_minutos,
                    "severidade": r.get("severidade"),
                    "criterio_pior_ritmo": r.get("criterio_pior_ritmo"),
                    "dt_ini_hora": _format_alert_time(r.get("dt_ini_hora")),
                    "dt_fim_hora": _format_alert_time(r.get("dt_fim_hora")),
                })

        df_multi = _load_crm_multi_alertas(cnpj, cnpj_dir)
        alertas_multi: list[dict] = []
        if not df_multi.is_empty():
            day_multi = df_multi.filter(pl.col("dt_dia").cast(pl.Utf8).str.slice(0, 10) == date_str)
            if hour is not None:
                day_multi = day_multi.filter(
                    pl.struct(["dt_ini_concentracao", "dt_fim_concentracao"]).map_elements(
                        lambda r: _alert_overlaps_hour(
                            r.get("dt_ini_concentracao"),
                            r.get("dt_fim_concentracao"),
                            hour,
                        ),
                        return_dtype=pl.Boolean,
                    )
                )

            alertas_multi = []
            for r in day_multi.iter_rows(named=True):
                ritmo_qtd = _to_int(r.get("nu_prescricoes"))
                ritmo_minutos = _to_int(r.get("nu_minutos_span"))
                ritmo_hora = round((ritmo_qtd * 60.0 / ritmo_minutos), 2) if ritmo_minutos > 0 else 0.0
                alertas_multi.append({
                    "dt_janela": str(r["dt_dia"])[:10],
                    "hr_janela": _extract_alert_hour(r.get("dt_ini_concentracao")),
                    "nu_prescricoes": ritmo_qtd,
                    "nu_crms": _to_int(r.get("nu_crms_distintos")),
                    "ritmo_hora": ritmo_hora,
                    "ritmo_qtd": ritmo_qtd,
                    "ritmo_minutos": ritmo_minutos,
                    "severidade": r.get("severidade"),
                    "criterio_pior_ritmo": r.get("criterio_pior_ritmo"),
                    "dt_ini_hora": _format_alert_time(r.get("dt_ini_concentracao")),
                    "dt_fim_hora": _format_alert_time(r.get("dt_fim_concentracao")),
                })

        return CrmRaioXResponse(
            cnpj=cnpj,
            dt_janela=date_str,
            hour=hour,
            transactions=transactions,
            alertas_unico=alertas_unico,
            alertas_multi=alertas_multi,
            from_cache=os.path.exists(parquet_path),
            read_time_ms=read_time_ms,
        )
    except Exception as e:
        print(f"Erro no Raio-X CRM unificado: {e}")
        return CrmRaioXResponse(
            cnpj=cnpj,
            dt_janela=date_str,
            hour=hour,
            transactions=[],
            alertas_unico=[],
            alertas_multi=[],
            from_cache=False,
            read_time_ms=read_time_ms,
        )

