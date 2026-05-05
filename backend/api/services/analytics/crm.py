from typing import List, Optional
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
    CrmMultiplosRaioXResponse,
    CrmUnicoRaioXResponse,
    MesMensalGtinItem,
    EvolucaoMensalGtinResponse,
    GtinDetalhamentoMensalResponse,
    GtinDetalhamentoMensalSummary,
    GtinDetalhamentoMensalItem,
)

from ._cache import _get_cnpj_cache_dir, sync_crm_raiox_tx, sync_mediana_autorizacoes_horaria

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

    # ── helpers de competência ────────────────────────────────────────────
    def _to_comp(date_str: str) -> int:
        return int(date_str[:7].replace("-", ""))

    comp_ini = _to_comp(data_inicio) if data_inicio else None
    comp_fim = _to_comp(data_fim)    if data_fim    else None

    # ── 1. Carrega ou gera o parquet ──────────────────────────────────────
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
            read_time_ms = round((_time.perf_counter() - _t0) * 1000, 1)
            from_cache = True
        except Exception as e:
            print(f"⚠️ Erro ao ler parquet CRM '{cnpj}': {e}", flush=True)

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
                         "E.dt_primeira_prescricao, E.dt_inscricao_crm, "
                         "E.nu_estabelecimentos"
                         " FROM temp_CGUSC.fp.crm_export E"
                         " INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.id = E.id_cnpj"
                         " WHERE F.cnpj = :cnpj"),
                    conn,
                    params={"cnpj": cnpj},
                )
                query_time_ms = round((_time.perf_counter() - _t0) * 1000, 1)
            if pdf.empty:
                return PrescritoresResponse(cnpj=cnpj, summary={}, crms_interesse=[], from_cache=False, query_time_ms=query_time_ms)
            df = pl.from_pandas(pdf)
            for col in ["flag_crm_invalido", "flag_prescricao_antes_registro", "alerta_concentracao_multiplos_crms"]:
                if col in df.columns:
                    df = df.with_columns(pl.col(col).cast(pl.Int8))
            _t1 = _time.perf_counter()
            df.write_parquet(PARQUET_PATH, compression="lz4")
            save_time_ms = round((_time.perf_counter() - _t1) * 1000, 1)
        except Exception as e:
            print(f"❌ ERRO ao buscar CRM do banco para {cnpj}: {e}")
            print(traceback.format_exc())
            return PrescritoresResponse(cnpj=cnpj, summary={}, crms_interesse=[], query_time_ms=query_time_ms)

    # ── 2. Filtro de período ───────────────────────────────────────────────
    if comp_ini:
        df = df.filter(pl.col("competencia") >= comp_ini)
    if comp_fim:
        df = df.filter(pl.col("competencia") <= comp_fim)

    if df.is_empty():
        return PrescritoresResponse(cnpj=cnpj, summary={}, crms_interesse=[], from_cache=from_cache,
                                    read_time_ms=read_time_ms, query_time_ms=query_time_ms, save_time_ms=save_time_ms)

    # ── 3. Agrega por id_medico (colapsa competências) ────────────────────
    total_valor = float(df["vl_total_prescricoes"].sum() or 0)

    # Cálculo de dias no período para o ritmo diário real
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

    # ── Dias ativos por médico (vetorizado, sem Python callback) ─────────
    # Calcula quantos dias tem cada competência (YYYYMM) criando o 1º dia do
    # próximo mês e subtraindo 1 dia. Trata a virada de ano (dez → jan).
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
            pl.sum("dias_competencia").alias("_dias_ativos"),  # dias reais do médico
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
            # Divide pelo total de dias dos meses em que o médico de fato prescreveu
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
            # Mantemos o pct_participacao com alta precisão para o acumulado
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

    # ── 4. Summary ────────────────────────────────────────────────────────
    top1       = df_med.row(0, named=True)
    top5_valor = float(df_med.head(5)["vl_total_prescricoes"].sum() or 0)

    qtd_robos         = int(df_med["flag_robo"].sum() or 0)
    qtd_robos_ocultos = int(df_med["flag_robo_oculto"].sum() or 0)
    qtd_invalido      = int(df_med["flag_crm_invalido"].sum() or 0)
    qtd_antes_reg     = int(df_med["flag_prescricao_antes_registro"].sum() or 0)
    qtd_conc_temp     = int(df["flag_concentracao_mesmo_crm"].sum() or 0)

    vl_invalido  = float(df_med.filter(pl.col("flag_crm_invalido") == 1)["vl_total_prescricoes"].sum() or 0)
    vl_antes_reg = float(df_med.filter(pl.col("flag_prescricao_antes_registro") == 1)["vl_total_prescricoes"].sum() or 0)

    pct_top1      = round(top1["vl_total_prescricoes"] / total_valor * 100, 2) if total_valor else 0.0
    pct_top5      = round(top5_valor / total_valor * 100, 2)                  if total_valor else 0.0
    pct_invalido  = round(vl_invalido  / total_valor * 100, 2)                if total_valor else 0.0
    pct_antes_reg = round(vl_antes_reg / total_valor * 100, 2)                if total_valor else 0.0

    # ── 5. Benchmarks ─────────────────────────────────────────────────────
    bench_top5_reg = 0.0
    bench_top5_br  = 0.0
    try:
        df_farm   = get_df_dados_farmacia()
        row_farm  = df_farm.filter(pl.col("cnpj") == cnpj)
        id_regiao = row_farm["id_regiao_saude"][0] if not row_farm.is_empty() else None

        df_br = get_df_bench_crm_br()
        if comp_ini: df_br = df_br.filter(pl.col("competencia") >= comp_ini)
        if comp_fim: df_br = df_br.filter(pl.col("competencia") <= comp_fim)
        bench_top5_br = float(df_br["mediana_concentracao_top5_br"].mean() or 0)

        if id_regiao:
            df_reg = get_df_bench_crm_regiao()
            df_reg = df_reg.filter(pl.col("id_regiao_saude") == id_regiao)
            if comp_ini: df_reg = df_reg.filter(pl.col("competencia") >= comp_ini)
            if comp_fim: df_reg = df_reg.filter(pl.col("competencia") <= comp_fim)
            bench_top5_reg = float(df_reg["mediana_concentracao_top5_reg"].mean() or 0)
    except Exception:
        pass

    # ── 6. Metadados do CNPJ (matriz de risco) ────────────────────────────
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
        "qtd_prescritores_surto":         int(df_med["alerta_concentracao_multiplos_crms"].sum() or 0),
        "mediana_concentracao_top5_reg":  round(bench_top5_reg, 2),
        "mediana_concentracao_top5_br":   round(bench_top5_br,  2),
        "razaoSocial":                    razao_social,
        "municipio":                      municipio,
        "uf":                             uf_str,
        "from_cache":                     os.path.exists(PARQUET_PATH),
    }

    # ── 7. Alertas diários — injeta em cada médico ────────────────────────
    ALERTAS_DIARIOS_PATH = os.path.join(cnpj_dir, "crm_concentracao_unico_alertas.parquet")
    df_ad: pl.DataFrame | None = None

    # Tenta carregar do cache parquet
    if os.path.exists(ALERTAS_DIARIOS_PATH):
        try:
            df_ad = pl.read_parquet(ALERTAS_DIARIOS_PATH)
        except Exception as e:
            print(f"⚠️ Erro ao ler parquet alertas diários '{cnpj}': {e}")
    
    # Se não houver cache, busca no banco e salva (Auto-Healing)
    if df_ad is None:
        try:
            from database import engine as _engine
            with _engine.connect() as conn:
                pdf_ad = pd.read_sql(
                    text("SELECT A.id_medico, "
                         " YEAR(A.dt_dia) * 100 + MONTH(A.dt_dia) AS competencia, "
                         " A.dt_dia AS dt_alerta, "
                         " DATEPART(HOUR, A.dt_ini_concentracao) AS hr_janela, "
                         " CASE "
                         "   WHEN A.nu_5min  >=  7 THEN A.nu_5min "
                         "   WHEN A.nu_10min >= 10 THEN A.nu_10min "
                         "   WHEN A.nu_5min  >=  6 THEN A.nu_5min "
                         "   WHEN A.nu_10min >=  8 THEN A.nu_10min "
                         "   WHEN A.nu_15min >=  8 THEN A.nu_15min "
                         "   WHEN A.nu_20min >=  9 THEN A.nu_20min "
                         "   WHEN A.nu_30min >=  9 THEN A.nu_30min "
                         "   WHEN A.nu_60min >= 14 THEN A.nu_60min "
                         "   WHEN A.nu_25min >=  8 THEN A.nu_25min "
                         "   WHEN A.nu_60min >= 10 THEN A.nu_60min "
                         " END AS nu_prescricoes_dia, "
                         " A.nu_minutos_span AS nu_minutos_dia, "
                         " CASE WHEN A.nu_minutos_span = 0 THEN 0 "
                         "      ELSE CAST((CASE "
                         "          WHEN A.nu_5min  >=  7 THEN A.nu_5min "
                         "          WHEN A.nu_10min >= 10 THEN A.nu_10min "
                         "          WHEN A.nu_5min  >=  6 THEN A.nu_5min "
                         "          WHEN A.nu_10min >=  8 THEN A.nu_10min "
                         "          WHEN A.nu_15min >=  8 THEN A.nu_15min "
                         "          WHEN A.nu_20min >=  9 THEN A.nu_20min "
                         "          WHEN A.nu_30min >=  9 THEN A.nu_30min "
                         "          WHEN A.nu_60min >= 14 THEN A.nu_60min "
                         "          WHEN A.nu_25min >=  8 THEN A.nu_25min "
                         "          WHEN A.nu_60min >= 10 THEN A.nu_60min "
                         "      END) * 60.0 / A.nu_minutos_span AS DECIMAL(10,2)) END AS taxa_hora, "
                         " A.dt_ini_concentracao AS dt_ini_hora, "
                         " A.dt_fim_concentracao AS dt_fim_hora "
                         " FROM temp_CGUSC.fp.crm_concentracao_unico_alertas A"
                         " INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.id = A.id_cnpj"
                         " WHERE F.cnpj = :cnpj"
                         " ORDER BY A.dt_dia, A.id_medico, A.dt_ini_concentracao"),
                    conn,
                    params={"cnpj": cnpj},
                )
            df_ad = pl.from_pandas(pdf_ad) if not pdf_ad.empty else pl.DataFrame(schema={
                "id_medico": pl.Utf8, "competencia": pl.Int32, "dt_alerta": pl.Utf8, "hr_janela": pl.Int32,
                "nu_prescricoes_dia": pl.Int32, "nu_minutos_dia": pl.Int32, "taxa_hora": pl.Float64,
                "dt_ini_hora": pl.Datetime, "dt_fim_hora": pl.Datetime
            })
            df_ad.write_parquet(ALERTAS_DIARIOS_PATH, compression="lz4")
        except Exception as e:
            print(f"❌ Erro ao buscar alertas diários do banco para {cnpj}: {e}")
            df_ad = pl.DataFrame()

    alertas_por_medico: dict[str, list[dict]] = {}
    if not df_ad.is_empty():
        # Filtro de período no DataFrame de alertas
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
                "taxa_hora":      float(row["taxa_hora"] or 0),
            })

    for m in crms_interesse_list:
        m["alertas_crm_unico"] = alertas_por_medico.get(m["id_medico"], [])

    # ── 7.1 Alertas Geográficos (Distância) ──────────────────────────────
    ALERTAS_GEO_PATH = os.path.join(cnpj_dir, "geografico.parquet")
    df_geo: pl.DataFrame | None = None

    if os.path.exists(ALERTAS_GEO_PATH):
        try: df_geo = pl.read_parquet(ALERTAS_GEO_PATH)
        except: pass
        
    if df_geo is None:
        try:
            from database import engine as _engine
            with _engine.connect() as conn:
                pdf_geo = pd.read_sql(
                    text("SELECT * FROM temp_CGUSC.fp.alertas_crm_geografico WHERE cnpj_a = :cnpj OR cnpj_b = :cnpj"),
                    conn, params={"cnpj": cnpj}
                )
            df_geo = pl.from_pandas(pdf_geo) if not pdf_geo.empty else pl.DataFrame(schema={
                "id_medico": pl.Utf8, "competencia": pl.Int32, "cnpj_a": pl.Utf8, 
                "no_municipio_a": pl.Utf8, "sg_uf_a": pl.Utf8, "dt_ini_a": pl.Utf8, 
                "dt_fim_a": pl.Utf8, "nu_prescricoes_a": pl.Int32, "cnpj_b": pl.Utf8, 
                "no_municipio_b": pl.Utf8, "sg_uf_b": pl.Utf8, "dt_ini_b": pl.Utf8, 
                "dt_fim_b": pl.Utf8, "nu_prescricoes_b": pl.Int32, "distancia_km": pl.Float64
            })
            df_geo.write_parquet(ALERTAS_GEO_PATH, compression="lz4")
        except Exception as e:
            # Se falhar a conexão (comum em modo offline), apenas avisa de forma amigável
            if "IM002" in str(e) or "connection" in str(e).lower():
                print(f"ℹ️  Modo Offline: Alertas geográficos para {cnpj} não encontrados no cache e banco inacessível.")
            else:
                print(f"⚠️ Erro ao buscar alertas geográficos para {cnpj}: {e}")
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
                "distancia_km":   float(row["distancia_km"] or 0),
            })

    for m in crms_interesse_list:
        m["alertas_geograficos"] = alertas_geo_por_medico.get(m["id_medico"], [])

    # ── 7.2 Alertas de Múltiplos CRMs (Surtos Coordenados) ───────────────
    ALERTAS_MULTI_PATH = os.path.join(cnpj_dir, "crm_concentracao_multiplo_alertas.parquet")
    df_cm: pl.DataFrame | None = None

    if os.path.exists(ALERTAS_MULTI_PATH):
        try: df_cm = pl.read_parquet(ALERTAS_MULTI_PATH)
        except: pass
        
    if df_cm is None:
        try:
            from database import engine as _engine
            with _engine.connect() as conn:
                pdf_cm = pd.read_sql(
                    text("SELECT A.id_cnpj, "
                         " YEAR(A.dt_dia)*100 + MONTH(A.dt_dia) AS competencia, "
                         " A.dt_ini_concentracao AS dt_alerta, "
                         " DATEPART(HOUR, A.dt_ini_concentracao) AS hr_janela,"
                         " A.nu_60min AS nu_prescricoes, "
                         " A.nu_crms_distintos AS nu_crms "
                         " FROM temp_CGUSC.fp.crm_concentracao_multiplo_alertas A"
                         " INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.id = A.id_cnpj"
                         " WHERE F.cnpj = :cnpj"),
                    conn, params={"cnpj": cnpj}
                )
            df_cm = pl.from_pandas(pdf_cm) if not pdf_cm.empty else pl.DataFrame(schema={
                "id_cnpj": pl.Int32, "competencia": pl.Int32, "dt_alerta": pl.Datetime,
                "hr_janela": pl.Int32, "nu_prescricoes": pl.Int32, "nu_crms": pl.Int32
            })
            df_cm.write_parquet(ALERTAS_MULTI_PATH, compression="lz4")
        except Exception as e:
            print(f"⚠️ Erro ao buscar alertas múltiplos para {cnpj}: {e}")
            df_cm = pl.DataFrame()

    # ── 7.3 Pré-Sincronização do Raio-X Unificado ────────────────────────
    # Garante que o arquivo crm_raiox_tx.parquet exista para uso offline
    try:
        sync_crm_raiox_tx(cnpj)
    except: pass

    # ── 8. Alertas do Estabelecimento (Cross-CRM) ─────────────────────────
    CNPJ_ALERTS_PATH = os.path.join(cnpj_dir, "volume_horario_anomalo_alertas.parquet")

    df_ca: pl.DataFrame | None = None

    if os.path.exists(CNPJ_ALERTS_PATH):
        try:
            df_ca = pl.read_parquet(CNPJ_ALERTS_PATH)
        except: pass
    
    if df_ca is None:
        try:
            from database import engine as _engine
            with _engine.connect() as conn:
                pdf_ca = pd.read_sql(
                    text("SELECT V.id_cnpj, V.competencia, V.dt_alerta, V.hr_janela,"
                         " V.nu_prescricoes, V.nu_crms, V.mediana_hora, V.multiplicador"
                         " FROM temp_CGUSC.fp.volume_horario_anomalo_alertas V"
                         " INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.id = V.id_cnpj"
                         " WHERE F.cnpj = :cnpj"),
                    conn, params={"cnpj": cnpj}
                )
            df_ca = pl.from_pandas(pdf_ca) if not pdf_ca.empty else pl.DataFrame(schema={
                "id_cnpj": pl.Int32, "competencia": pl.Int32, "dt_alerta": pl.Utf8,
                "hr_janela": pl.Int32, "nu_prescricoes": pl.Int32, "nu_crms": pl.Int32,
                "mediana_hora": pl.Float64, "multiplicador": pl.Float64
            })
            df_ca.write_parquet(CNPJ_ALERTS_PATH, compression="lz4")
        except Exception as e:
            print(f"❌ Erro ao buscar/salvar alertas de surto do banco para {cnpj}: {e}")
            df_ca = pl.DataFrame()

    # ── 8. Alertas do Estabelecimento (Consolidação das 3 Fontes) ─────────
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
                "hr": int(r["hr_janela"]),
                "nu_prescricoes": int(r["nu_prescricoes"]),
                "nu_crms": int(r["nu_crms"]),
                "multiplicador": float(r.get("multiplicador", 0)),
                "mediana_hora":  float(r.get("mediana_hora", 0))
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
                "hr": int(r["hr_janela"]),
                "nu_prescricoes": int(r["nu_prescricoes"]),
                "nu_crms": int(r["nu_crms"]),
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
                "hr": int(r["hr_janela"]),
                "nu_prescricoes": int(r["nu_prescricoes"]),
                "nu_crms": int(r["nu_crms"]),
                "multiplicador": 0.0,
                "mediana_hora": 0.0
            })

    # Ordenação Final por Data/Hora
    cnpj_alerts_list.sort(key=lambda x: (x["dt"], x["hr"]))

    # ── 9. Cruzamento: Quais surtos do estabelecimento cada CRM participou? ──
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

                # Agregamos volume por CRM e Hora de Surto
                df_surto_agg = (
                    df_tx.group_by(["dt_janela", "hr_janela", "id_medico"])
                    .agg([
                        pl.n_unique("num_autorizacao").alias("nu_prescricoes_crm"),
                        pl.sum("valor_pago").alias("vl_prescricoes_crm")
                    ])
                )
                
                # Cruzamos com os alertas do CNPJ para trazer o contexto (descrição/total)
                if not df_ca.is_empty():
                    # Garantimos que dt_alerta também seja String no mesmo formato
                    df_ca_clean = df_ca.with_columns(pl.col("dt_alerta").cast(pl.Utf8).str.slice(0, 10))
                    
                    df_surto_full = df_surto_agg.join(
                        df_ca_clean.select(["dt_alerta", "hr_janela", "nu_prescricoes", "nu_crms", "multiplicador", "mediana_hora"]),
                        left_on=["dt_janela", "hr_janela"],
                        right_on=["dt_alerta", "hr_janela"],
                        how="inner"
                    )
                    
                    for r in df_surto_full.iter_rows(named=True):
                        mid = r['id_medico']
                        vol = int(r.get("nu_prescricoes", 0))
                        hr  = int(r.get("hr_janela", 0))
                        mult = r.get("multiplicador", 0)
                        med = r.get("mediana_hora", 0)
                        
                        # Frase técnica padronizada (Backend-only)
                        desc = f"{vol} prescrições às {hr:02d}h ({mult}x a mediana da farmácia: {med}/h)"
                        
                        alertas_crm_multiplos_por_medico.setdefault(mid, []).append({
                            "dt": str(r["dt_janela"]),
                            "hr": hr,
                            "nu_presc_crm": int(r["nu_prescricoes_crm"]),
                            "nu_presc_total": vol,
                            "nu_crms_total": int(r["nu_crms"]),
                            "multiplicador": mult,
                            "mediana_hora": med,
                            "descricao": desc
                        })
        except Exception as e:
            print(f"⚠️ Erro ao processar cruzamento de surtos para {cnpj}: {e}")

    # Atribuição final aos médicos
    for m in crms_interesse_list:
        m["alertas_crm_multiplos"] = alertas_crm_multiplos_por_medico.get(m["id_medico"], [])


    return PrescritoresResponse(
        cnpj=cnpj,
        summary=summary_dict,
        crms_interesse=crms_interesse_list,
        cnpj_alerts=cnpj_alerts_list,
        from_cache=from_cache,
        read_time_ms=read_time_ms,
        query_time_ms=query_time_ms,
        save_time_ms=save_time_ms,
    )

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

    Fonte: temp_CGUSC.fp.crm_perfil_diario
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
            print(f"⚠️ Erro ao ler parquet crm_perfil_diario '{cnpj}': {e}")

    if df is None:
        try:
            from database import engine as _engine
            with _engine.connect() as conn:
                _t0 = _time.perf_counter()
                pdf = pd.read_sql(
                    text("SELECT P.* FROM temp_CGUSC.fp.crm_perfil_diario P"
                         " INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.id = P.id_cnpj"
                         " WHERE F.cnpj = :cnpj ORDER BY P.dt_janela"),
                    conn,
                    params={"cnpj": cnpj},
                )
                query_time_ms = round((_time.perf_counter() - _t0) * 1000, 1)
            df = pl.from_pandas(pdf)
            _t1 = _time.perf_counter()
            df.write_parquet(PARQUET_PATH, compression="lz4")
            save_time_ms = round((_time.perf_counter() - _t1) * 1000, 1)
        except Exception as e:
            print(f"⚠️ Erro ao gerar parquet crm_perfil_diario '{cnpj}': {e}")
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

    days = [
        {
            "dt_janela":             str(r["dt_janela"])[:10],
            "competencia":           int(r["competencia"]),
            "nu_prescricoes_dia":    int(r["nu_prescricoes_dia"]),
            "nu_crms_distintos":     int(r["nu_crms_distintos"]),
            "mediana_diaria":        float(r["mediana_diaria"]),
            "is_dia_com_volume_horario_anomalo": int(r["is_dia_com_volume_horario_anomalo"]),
            "is_anomalo_unico":      int(r["is_anomalo_unico"]),
            "is_crm_multiplo":       int(r.get("is_crm_multiplo", 0)),
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
    por ponto horário, lidos de temp_CGUSC.fp.crm_perfil_horario.
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
            print(f"⚠️ Erro ao ler parquet hourly '{cnpj}': {e}")

    if df is None:
        try:
            from database import engine as _engine
            with _engine.connect() as conn:
                _t0 = _time.perf_counter()
                pdf = pd.read_sql(
                    text("SELECT P.dt_janela, P.hr_janela, P.nu_prescricoes, P.nu_crms_diferentes, P.mediana_hora, "
                         "P.is_hora_com_alerta, P.is_volume_horario_anomalo, P.is_crm_unico, P.is_crm_multiplo "
                         "FROM temp_CGUSC.fp.crm_perfil_horario P "
                         "INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.id = P.id_cnpj "
                         "WHERE F.cnpj = :cnpj "
                         "ORDER BY P.dt_janela, P.hr_janela"),
                    conn,
                    params={"cnpj": cnpj},
                )
                query_time_ms = round((_time.perf_counter() - _t0) * 1000, 1)
            df = pl.from_pandas(pdf)
            _t1 = _time.perf_counter()
            df.write_parquet(PARQUET_PATH, compression="lz4")
            save_time_ms = round((_time.perf_counter() - _t1) * 1000, 1)
        except Exception as e:
            print(f"⚠️ Erro ao gerar parquet hourly '{cnpj}': {e}")
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
        except Exception: pass

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
                            A.severidade
                        FROM temp_CGUSC.fp.crm_concentracao_unico_alertas A
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
                            A.severidade
                        FROM temp_CGUSC.fp.crm_concentracao_multiplo_alertas A
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
                            'CRÍTICO' as severidade
                        FROM temp_CGUSC.fp.volume_horario_anomalo_alertas V
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
                    ])
                df_events.write_parquet(EVENTS_PARQUET_PATH, compression="lz4")
        except Exception as e:
            print(f"⚠️ Erro ao buscar eventos hourly '{cnpj}': {e}")
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

    # Carrega lookup de medianas: (ano, trimestre, hr_janela) → mediana_hora
    from datetime import datetime as _dt
    MEDIANA_PATH = os.path.join(cnpj_dir, "mediana_autorizacoes_horaria.parquet")
    mediana_lookup: dict = {}
    if os.path.exists(MEDIANA_PATH):
        try:
            df_med = pl.read_parquet(MEDIANA_PATH)
            for r in df_med.iter_rows(named=True):
                mediana_lookup[(int(r["ano"]), int(r["trimestre"]), int(r["hr_janela"]))] = float(r["mediana_hora"])
        except Exception:
            pass

    # Indexa atividade real e flags de anomalia por (data, hora)
    activity: dict = {}
    dates_flags: dict = {}
    for r in df.iter_rows(named=True):
        dt = str(r["dt_janela"])[:10]
        activity[(dt, int(r["hr_janela"]))] = r
        if dt not in dates_flags:
            dates_flags[dt] = {
                "is_volume_horario_anomalo": int(r.get("is_volume_horario_anomalo", 0)),
                "is_crm_unico":              int(r.get("is_crm_unico", 0)),
                "is_crm_multiplo":           int(r.get("is_crm_multiplo", 0)),
            }

    # Expande para 24 horas por dia anômalo com mediana real para todas as horas
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
            
            # Pega as flags da HORA específica (row), não do dia (flags)
            is_vol = int(row.get("is_volume_horario_anomalo", 0)) if row else 0
            is_uni = int(row.get("is_crm_unico", 0)) if row else 0
            is_mul = int(row.get("is_crm_multiplo", 0)) if row else 0
            
            # Se a tabela perfil_horario não tiver as flags específicas, 
            # podemos usar a is_anomalo_hora como fallback para volume
            if row and is_vol == 0 and is_uni == 0 and is_mul == 0:
                if int(row.get("is_anomalo_hora", 0)) == 1:
                    is_vol = 1

            points.append({
                "dt_janela":          dt,
                "hr_janela":          h,
                "nu_prescricoes":     int(row["nu_prescricoes"])     if row else 0,
                "nu_crms_diferentes": int(row["nu_crms_diferentes"]) if row else 0,
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
                "minuto_inicio":    int(r["minuto_inicio"]),
                "minuto_fim":       int(r["minuto_fim"]),
                "severidade":       r["severidade"],
                "id_medico":        r["id_medico"],
                "nu_crms_distintos": r["nu_crms_distintos"]
            }
            for r in df_events.iter_rows(named=True)
        ]

    # AUTO-WARMING: Pré-aquece o parquet de Transações Literais (Raio-X Unificado)
    sync_crm_raiox_tx(cnpj)

    return CrmHourlyProfileResponse(cnpj=cnpj, points=points, events=events_list, from_cache=from_cache,
                                    read_time_ms=read_time_ms, query_time_ms=query_time_ms, save_time_ms=save_time_ms)

def get_crm_multiplos_raio_x(cnpj: str, date_str: str, hour: Optional[int] = None) -> "CrmMultiplosRaioXResponse":
    """Busca as transações de uma hora anômala ou do dia todo, utilizando o cache unificado."""
    import polars as pl
    from api.schemas.analytics import CrmMultiplosRaioXResponse
    
    cnpj_dir = _get_cnpj_cache_dir(cnpj)
    PARQUET_PATH = os.path.join(cnpj_dir, "crm_raiox_tx.parquet")

    if not os.path.exists(PARQUET_PATH):
        sync_crm_raiox_tx(cnpj)

    if not os.path.exists(PARQUET_PATH):
        return CrmMultiplosRaioXResponse(transactions=[], from_cache=False)

    try:
        import time as _time
        _t0 = _time.perf_counter()
        df = pl.read_parquet(PARQUET_PATH)
        read_time_ms = round((_time.perf_counter() - _t0) * 1000, 1)
        
        # Filtro por Dia e Hora opcional
        filter_expr = pl.col("dt_janela").cast(pl.Utf8).str.slice(0, 10) == date_str
        if hour is not None:
            filter_expr = filter_expr & (pl.col("hr_janela") == hour)

        filtered_df = df.filter(filter_expr)
        if filtered_df.is_empty():
            return CrmMultiplosRaioXResponse(transactions=[], from_cache=True, read_time_ms=read_time_ms)

        # Enriquece com nomes dos medicamentos
        from data_cache import get_medicamentos_df
        df_med = get_medicamentos_df().select(["codigo_barra", "produto", "principio_ativo"])
        enriched_df = filtered_df.join(df_med, on="codigo_barra", how="left")
        
        # Garante tipos de string para o Pydantic
        enriched_df = enriched_df.with_columns([
            pl.col("num_autorizacao").cast(pl.Utf8),
            pl.col("id_medico").cast(pl.Utf8),
            pl.col("codigo_barra").cast(pl.Utf8),
            pl.col("data_hora").cast(pl.Utf8)
        ])

        return CrmMultiplosRaioXResponse(transactions=enriched_df.to_dicts(), from_cache=True, read_time_ms=read_time_ms)
    except Exception as e:
        print(f"⚠️ Erro no Raio-X Múltiplos: {e}")
        return CrmMultiplosRaioXResponse(transactions=[], from_cache=False)

def get_crm_unico_raio_x(cnpj: str, date_str: str, hour: Optional[int] = None) -> "CrmUnicoRaioXResponse":
    """Retorna as transações da farmácia num dia com alerta de CRM único, utilizando o cache unificado.
    
    Args:
        cnpj: CNPJ de 14 dígitos sem formatação.
        date_str: Data no formato YYYY-MM-DD.
        hour: Hora opcional para filtrar transações (0-23).

    Returns:
        CrmUnicoRaioXResponse com transações (enriquecidas com produto) e lista de alertas do dia.
    """
    import polars as pl
    from api.schemas.analytics import CrmUnicoRaioXResponse

    cnpj_dir = _get_cnpj_cache_dir(cnpj)
    PARQUET_PATH = os.path.join(cnpj_dir, "crm_raiox_tx.parquet")

    if not os.path.exists(PARQUET_PATH):
        sync_crm_raiox_tx(cnpj)

    empty = CrmUnicoRaioXResponse(cnpj=cnpj, dt_janela=date_str, transactions=[], alertas=[], from_cache=True)

    if not os.path.exists(PARQUET_PATH):
        return empty

    try:
        import time as _time
        _t0 = _time.perf_counter()
        df = pl.read_parquet(PARQUET_PATH)
        read_time_ms = round((_time.perf_counter() - _t0) * 1000, 1)

        # Filtro por Dia e Hora opcional
        filter_expr = pl.col("dt_janela").cast(pl.Utf8).str.slice(0, 10) == date_str
        if hour is not None:
            filter_expr = filter_expr & (pl.col("hr_janela") == hour)

        filtered_df = df.filter(filter_expr)
        
        if filtered_df.is_empty():
            return CrmUnicoRaioXResponse(cnpj=cnpj, dt_janela=date_str, transactions=[], alertas=[], from_cache=True, read_time_ms=read_time_ms)

        # Enriquece com medicamentos
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

        # Busca os médicos-gatilho do dia (usando o cache de alertas diários)
        alertas: list[dict] = []
        alertas_parquet = os.path.join(cnpj_dir, "crm_concentracao_unico_alertas.parquet")
        if os.path.exists(alertas_parquet):
            df_alertas = pl.read_parquet(alertas_parquet)
            day_alertas = df_alertas.filter(pl.col("dt_alerta").cast(pl.Utf8).str.slice(0, 10) == date_str)
            alertas = [
                {
                    "id_medico":         str(r["id_medico"]),
                    "hr_janela":         int(r["hr_janela"]),
                    "nu_prescricoes_dia": int(r["nu_prescricoes_dia"]),
                    "nu_minutos_dia":     int(r["nu_minutos_dia"]),
                    "taxa_hora":          float(r["taxa_hora"]),
                    "dt_ini_hora":        r["dt_ini_hora"].strftime("%H:%M") if r.get("dt_ini_hora") else None,
                    "dt_fim_hora":        r["dt_fim_hora"].strftime("%H:%M") if r.get("dt_fim_hora") else None,
                }
                for r in day_alertas.iter_rows(named=True)
            ]

        return CrmUnicoRaioXResponse(cnpj=cnpj, dt_janela=date_str, transactions=transactions, alertas=alertas, from_cache=True, read_time_ms=read_time_ms)
    except Exception as e:
        print(f"⚠️ Erro no Raio-X Único: {e}")
        return empty

