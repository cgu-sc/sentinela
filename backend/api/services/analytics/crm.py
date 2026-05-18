from typing import Any, List, Optional
from datetime import date
import calendar
import polars as pl
from sqlalchemy.orm import Session
from fastapi import HTTPException
import os
import zlib
import json
import copy
from decimal import Decimal, ROUND_HALF_UP
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

from ._cache import _get_cnpj_cache_dir
from cache_producers.crm import (
    load_or_sync_crm_data,
    load_or_sync_crm_horario_eventos,
    load_or_sync_crm_multi_alertas,
    load_or_sync_crm_perfil_diario,
    load_or_sync_crm_perfil_horario,
    load_or_sync_crm_unico_alertas,
    load_or_sync_geografico,
    load_or_sync_volume_horario_anomalo,
    sync_crm_raiox_tx,
    sync_mediana_autorizacoes_horaria,
)

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


def _raise_cache_unavailable(area: str, error: str | None) -> None:
    raise HTTPException(
        status_code=503,
        detail=f"{area} indisponivel: {error or 'falha ao sincronizar cache local.'}",
    )

def get_crm_data(
    cnpj: str,
    data_inicio: str | None = None,
    data_fim: str | None = None,
) -> PrescritoresResponse:
    """Retorna KPIs e top prescritores de um CNPJ a partir do parquet por CNPJ (lazy cache)."""
    import traceback
    cnpj_dir = _get_cnpj_cache_dir(cnpj)

    # â”€â”€ helpers de competÃªncia â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    def _to_comp(date_str: str) -> int:
        return int(date_str[:7].replace("-", ""))

    comp_ini = _to_comp(data_inicio) if data_inicio else None
    comp_fim = _to_comp(data_fim)    if data_fim    else None

    # â”€â”€ 1. Carrega ou gera o parquet â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    result = load_or_sync_crm_data(cnpj)
    if result.error:
        _raise_cache_unavailable("Base de dados de prescricoes", result.error)

    df = result.df
    from_cache = result.from_cache
    read_time_ms = result.read_time_ms
    query_time_ms = result.query_time_ms
    save_time_ms = result.save_time_ms

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
        "from_cache":                     from_cache,
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
                "dt_ini_hora":    str(row.get("dt_ini_hora") or ""),
                "dt_fim_hora":    str(row.get("dt_fim_hora") or ""),
            })

    for m in crms_interesse_list:
        m["alertas_crm_unico"] = alertas_por_medico.get(m["id_medico"], [])

    # ——— 7.1 Alertas Geográficos (Distância) ——————————————————————————————————————
    geo_result = load_or_sync_geografico(cnpj)
    if geo_result.error:
        _raise_cache_unavailable("Alertas geograficos CRM", geo_result.error)
    df_geo = geo_result.df

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
    # Garante que o parquet Raio-X exista para uso offline
    raio_x_result = sync_crm_raiox_tx(cnpj)
    if raio_x_result.error:
        _raise_cache_unavailable("Raio-X CRM", raio_x_result.error)

    # ——— 8. Alertas do Estabelecimento (Cross-CRM) ———————————————————————————————
    cnpj_alerts_list = []
    volume_result = load_or_sync_volume_horario_anomalo(cnpj)
    if volume_result.error:
        _raise_cache_unavailable("Alertas de volume horario CRM", volume_result.error)
    df_ca = volume_result.df

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
            nu_prescricoes = _to_int(r.get("nu_prescricoes"))
            nu_minutos = _to_int(r.get("nu_minutos_span"))
            cnpj_alerts_list.append({
                "tipo": "MULTIPLO",
                "dt": str(r["dt_alerta"]),
                "hr": _to_int(r.get("hr_janela")),
                "nu_prescricoes": nu_prescricoes,
                "nu_crms": _to_int(r.get("nu_crms")),
                "nu_minutos": nu_minutos,
                "taxa_hora": (nu_prescricoes * 60.0 / nu_minutos) if nu_minutos > 0 else 0.0,
                "dt_ini_hora": str(r.get("dt_ini_concentracao") or ""),
                "dt_fim_hora": str(r.get("dt_fim_concentracao") or ""),
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
    TX_PARQUET_PATH = os.path.join(cnpj_dir, CRM_RAIOX_TX_PARQUET)
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
    result = load_or_sync_crm_unico_alertas(cnpj)
    if result.error:
        _raise_cache_unavailable("Alertas de concentracao CRM unico", result.error)
    return result.df


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
    Cache: sentinela_cache/<cnpj>/crm_perfil_diario.
    """
    cnpj_dir = _get_cnpj_cache_dir(cnpj)
    result = load_or_sync_crm_perfil_diario(cnpj)
    if result.error:
        _raise_cache_unavailable("Perfil diario CRM", result.error)

    df = result.df
    from_cache = result.from_cache
    read_time_ms = result.read_time_ms
    query_time_ms = result.query_time_ms
    save_time_ms = result.save_time_ms

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
    except HTTPException:
        raise
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
    Cache: sentinela_cache/<cnpj>/crm_horario.
    """
    cnpj_dir = _get_cnpj_cache_dir(cnpj)
    result = load_or_sync_crm_perfil_horario(cnpj)
    if result.error:
        _raise_cache_unavailable("Perfil horario CRM", result.error)

    df = result.df
    from_cache = result.from_cache
    read_time_ms = result.read_time_ms
    query_time_ms = result.query_time_ms
    save_time_ms = result.save_time_ms

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
    events_result = load_or_sync_crm_horario_eventos(cnpj)
    if events_result.error:
        _raise_cache_unavailable("Eventos horarios CRM", events_result.error)
    df_events = events_result.df
    # Filtro de período nos eventos
    if not df_events.is_empty():
        if data_inicio:
            d_ini = data_inicio if len(data_inicio) == 10 else f"{data_inicio}-01"
            df_events = df_events.filter(pl.col("dt_dia").cast(pl.Utf8) >= d_ini)
        if data_fim:
            d_fim = data_fim if len(data_fim) == 10 else f"{data_fim}-31"
            df_events = df_events.filter(pl.col("dt_dia").cast(pl.Utf8) <= d_fim)

    # Garante que o parquet de medianas existe (auto-warming)
    mediana_result = sync_mediana_autorizacoes_horaria(cnpj)
    if mediana_result.error:
        _raise_cache_unavailable("Mediana horaria CRM", mediana_result.error)

    # Carrega lookup de medianas: (ano, trimestre, hr_janela) â†’ mediana_hora
    from datetime import datetime as _dt
    MEDIANA_PATH = os.path.join(cnpj_dir, MEDIANA_AUTORIZACOES_HORARIA_PARQUET)
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
    raio_x_result = sync_crm_raiox_tx(cnpj)
    if raio_x_result.error:
        _raise_cache_unavailable("Raio-X CRM", raio_x_result.error)

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

    target_hour = hour
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
    result = load_or_sync_crm_multi_alertas(cnpj)
    if result.error:
        _raise_cache_unavailable("Alertas de concentracao CRM multiplo", result.error)
    return result.df


def get_crm_raio_x(cnpj: str, date_str: str, hour: Optional[int] = None) -> "CrmRaioXResponse":
    """Retorna transacoes e alertas CRM unificados para uma data/hora."""
    cnpj_dir = _get_cnpj_cache_dir(cnpj)
    parquet_path = os.path.join(cnpj_dir, CRM_RAIOX_TX_PARQUET)

    raio_x_result = sync_crm_raiox_tx(cnpj)
    if raio_x_result.error:
        _raise_cache_unavailable("Raio-X CRM", raio_x_result.error)

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
        df_unico = _load_crm_unico_alertas(cnpj, cnpj_dir)
        if not df_unico.is_empty():
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
    except HTTPException:
        raise
    except Exception as e:
        print(f"Erro no Raio-X CRM unificado: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Erro no Raio-X CRM unificado: {e}",
        )

