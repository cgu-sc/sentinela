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
    MesMensalGtinItem,
    EvolucaoMensalGtinResponse,
    GtinDetalhamentoMensalResponse,
    GtinDetalhamentoMensalSummary,
    GtinDetalhamentoMensalItem,
)
_known_cnpj_dirs: set[str] = set()

def _get_cnpj_cache_dir(cnpj: str) -> str:
    """Retorna (e garante a existência de) sentinela_cache/{cnpj}/.

    Usa um cache em memória para evitar chamadas redundantes a makedirs
    em requests frequentes ao mesmo CNPJ.
    """
    from data_cache import get_cache_dir
    cnpj_dir = os.path.join(get_cache_dir(), cnpj)
    if not os.path.exists(cnpj_dir):
        os.makedirs(cnpj_dir, exist_ok=True)
        _known_cnpj_dirs.add(cnpj_dir)
    return cnpj_dir

def sync_crm_raiox_tx(cnpj: str) -> None:
    """Sincroniza o cache parquet de transações literais unificadas (Raio-X) para um CNPJ."""
    import pandas as pd
    import polars as pl
    from sqlalchemy import text
    from database import engine as _engine
    
    cnpj_dir = _get_cnpj_cache_dir(cnpj)
    TX_PARQUET_PATH = os.path.join(cnpj_dir, "crm_raiox_tx.parquet")

    # Se o cache já existe e parece saudável, não faz nada
    if os.path.exists(TX_PARQUET_PATH):
        try:
            header = pl.scan_parquet(TX_PARQUET_PATH).limit(0).collect()
            if "codigo_barra" in header.columns:
                return
        except Exception: pass

    try:
        print(f"🗄️ [SYNC] Buscando transações Raio-X unificadas no banco para {cnpj}...")
        with _engine.connect() as conn:
            pdf_tx = pd.read_sql(
                text("SELECT P.dt_janela, P.hr_janela, P.data_hora, P.num_autorizacao, P.id_medico, MED.codigo_barra, P.valor_pago "
                     "FROM temp_CGUSC.fp.crm_raiox_tx P "
                     "INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.id = P.id_cnpj "
                     "INNER JOIN temp_CGUSC.fp.medicamentos_patologia MED ON MED.id = P.id_gtin "
                     "WHERE F.cnpj = :cnpj "
                     "ORDER BY P.data_hora ASC, P.num_autorizacao ASC"),
                conn, params={"cnpj": cnpj}
            )
        df_tx = pl.from_pandas(pdf_tx) if not pdf_tx.empty else pl.DataFrame(schema={
            "dt_janela": pl.Utf8, "hr_janela": pl.Int32, "data_hora": pl.Utf8,
            "num_autorizacao": pl.Utf8, "id_medico": pl.Utf8,
            "codigo_barra": pl.Utf8, "valor_pago": pl.Float64
        })

        if not df_tx.is_empty():
            df_tx = df_tx.with_columns([
                pl.col("num_autorizacao").cast(pl.Utf8),
                pl.col("id_medico").cast(pl.Utf8),
                pl.col("codigo_barra").cast(pl.Utf8),
                pl.col("data_hora").cast(pl.Utf8)
            ])
        
        df_tx.write_parquet(TX_PARQUET_PATH, compression="lz4")
        print(f"✅ Cache Raio-X salvo para {cnpj}")
    except Exception as e:
        if "IM002" in str(e) or "connection" in str(e).lower():
            print(f"ℹ️  Modo Offline: Tabela de transações crm_raiox_tx não disponível.")
        else:
            print(f"⚠️ Erro ao sincronizar parquet de transações Raio-X '{cnpj}': {e}")

def sync_mediana_autorizacoes_horaria(cnpj: str) -> None:
    """Sincroniza o cache parquet de medianas horárias de autorizações para um CNPJ.

    Lê temp_CGUSC.fp.mediana_autorizacoes_horaria e grava
    sentinela_cache/<cnpj>/mediana_autorizacoes_horaria.parquet.
    Usado pelo get_crm_perfil_horario para preencher a mediana de referência
    em horas sem atividade no dia selecionado.
    """
    import pandas as pd
    import polars as pl
    from sqlalchemy import text
    from database import engine as _engine

    cnpj_dir = _get_cnpj_cache_dir(cnpj)
    PARQUET_PATH = os.path.join(cnpj_dir, "mediana_autorizacoes_horaria.parquet")

    if os.path.exists(PARQUET_PATH):
        try:
            header = pl.scan_parquet(PARQUET_PATH).limit(0).collect()
            if "mediana_hora" in header.columns:
                return
        except Exception:
            pass

    try:
        print(f"🗄️ [SYNC] Buscando medianas horárias para {cnpj}...")
        with _engine.connect() as conn:
            pdf = pd.read_sql(
                text("SELECT M.ano, M.trimestre, M.hr_janela, M.mediana_hora "
                     "FROM temp_CGUSC.fp.mediana_autorizacoes_horaria M "
                     "INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.id = M.id_cnpj "
                     "WHERE F.cnpj = :cnpj "
                     "ORDER BY M.ano, M.trimestre, M.hr_janela"),
                conn, params={"cnpj": cnpj}
            )
        df = pl.from_pandas(pdf) if not pdf.empty else pl.DataFrame(schema={
            "ano": pl.Int32, "trimestre": pl.Int32,
            "hr_janela": pl.Int32, "mediana_hora": pl.Float64
        })
        df.write_parquet(PARQUET_PATH, compression="lz4")
        print(f"✅ Cache medianas horárias salvo para {cnpj}")
    except Exception as e:
        if "IM002" in str(e) or "connection" in str(e).lower():
            print(f"ℹ️  Modo Offline: Tabela mediana_autorizacoes_horaria não disponível.")
        else:
            print(f"⚠️ Erro ao sincronizar parquet de medianas horárias '{cnpj}': {e}")

