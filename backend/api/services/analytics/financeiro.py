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

from ._cache import _get_cnpj_cache_dir

def get_evolucao_financeira(cnpj: str, data_inicio=None, data_fim=None) -> EvolucaoFinanceiraResponse:
    """
    Retorna a série semestral de valores (total, regular, irregular) para um CNPJ.

    Args:
        cnpj: CNPJ completo (14 dígitos).
        data_inicio: Data inicial opcional para recorte do período (date).
        data_fim: Data final opcional para recorte do período (date).

    Returns:
        EvolucaoFinanceiraResponse com lista de semestres dentro do período informado.
    """
    try:
        df = get_df()
        cnpj_df = df.filter(pl.col("cnpj") == cnpj).select(["periodo", "total_vendas", "total_sem_comprovacao"])

        if data_inicio:
            cnpj_df = cnpj_df.filter(pl.col("periodo") >= pl.lit(data_inicio).cast(pl.Date))
        if data_fim:
            cnpj_df = cnpj_df.filter(pl.col("periodo") <= pl.lit(data_fim).cast(pl.Date))

        if cnpj_df.is_empty():
            return EvolucaoFinanceiraResponse(cnpj=cnpj, semestres=[])

        # Extrai ano e número do semestre (1 ou 2) para agrupar e ordenar
        cnpj_df = cnpj_df.with_columns([
            pl.col("periodo").dt.year().alias("ano"),
            pl.when(pl.col("periodo").dt.month() <= 6)
              .then(pl.lit(1))
              .otherwise(pl.lit(2))
              .alias("sem_num"),
        ])

        # Agrega por (ano, sem_num) — captura min/max de período para exibir
        # os meses reais incluídos (útil quando o semestre é parcial por filtro)
        agg = (
            cnpj_df
            .group_by(["ano", "sem_num"])
            .agg([
                pl.sum("total_vendas").alias("total"),
                pl.sum("total_sem_comprovacao").alias("irregular"),
                pl.col("periodo").min().alias("dt_inicio"),
                pl.col("periodo").max().alias("dt_fim"),
            ])
            .sort(["ano", "sem_num"])
            .with_columns([
                (pl.col("total") - pl.col("irregular")).alias("regular"),
                (pl.col("irregular") / pl.when(pl.col("total") > 0).then(pl.col("total")).otherwise(pl.lit(1.0)) * 100)
                  .round(2).alias("pct_irregular"),
                pl.concat_str([
                    pl.col("sem_num").cast(pl.Utf8),
                    pl.lit("S/"),
                    pl.col("ano").cast(pl.Utf8),
                ]).alias("semestre"),
            ])
        )

        # Preparar o detalhamento mensal para a "sanfona" do frontend
        meses_df = (
            cnpj_df
            .with_columns([
                pl.col("periodo").dt.strftime("%Y-%m").alias("mes"),
            ])
            .group_by(["ano", "sem_num", "mes"])
            .agg([
                pl.sum("total_vendas").alias("total"),
                pl.sum("total_sem_comprovacao").alias("irregular"),
            ])
            .with_columns([
                (pl.col("total") - pl.col("irregular")).alias("regular"),
                (pl.col("irregular") / pl.when(pl.col("total") > 0).then(pl.col("total")).otherwise(pl.lit(1.0)) * 100)
                  .round(2).alias("pct_irregular"),
            ])
            .sort("mes")
        )
        
        meses_by_semestre = {}
        for m in meses_df.iter_rows(named=True):
            k = (m["ano"], m["sem_num"])
            if k not in meses_by_semestre:
                meses_by_semestre[k] = []
            meses_by_semestre[k].append(m)

        semestres = [
            EvolucaoSemestreSchema(
                semestre=r["semestre"],
                total=round(r["total"], 2),
                regular=round(r["regular"], 2),
                irregular=round(r["irregular"], 2),
                pct_irregular=r["pct_irregular"],
                mes_inicio=r["dt_inicio"].strftime("%Y-%m") if r.get("dt_inicio") else None,
                mes_fim=r["dt_fim"].strftime("%Y-%m") if r.get("dt_fim") else None,
                meses=[
                    {
                        "mes": m["mes"],
                        "total": round(m["total"], 2),
                        "regular": round(m["regular"], 2),
                        "irregular": round(m["irregular"], 2),
                        "pct_irregular": m["pct_irregular"]
                    }
                    for m in meses_by_semestre.get((r["ano"], r["sem_num"]), [])
                ]
            )
            for r in agg.iter_rows(named=True)
        ]
        return EvolucaoFinanceiraResponse(cnpj=cnpj, semestres=semestres)

    except Exception as e:
        import traceback
        print(f"❌ ERRO AO CALCULAR EVOLUÇÃO FINANCEIRA: {e}")
        print(traceback.format_exc())
        return EvolucaoFinanceiraResponse(cnpj=cnpj, semestres=[])

def get_evolucao_mensal_gtin(cnpj: str, data_inicio=None, data_fim=None) -> EvolucaoMensalGtinResponse:
    """
    Retorna a série mensal de quantidades e valores (por GTIN agregado) para um CNPJ.
    Lazy cache: gera sentinela_cache/{cnpj}/movimentacao_mensal_gtin.parquet na primeira chamada.

    Args:
        cnpj: CNPJ completo (14 dígitos).
        data_inicio: Data inicial opcional para recorte do período (date).
        data_fim: Data final opcional para recorte do período (date).

    Returns:
        EvolucaoMensalGtinResponse com lista de meses ordenados ASC.
    """
    import pandas as pd
    import time

    cnpj_dir = _get_cnpj_cache_dir(cnpj)
    PARQUET_PATH = os.path.join(cnpj_dir, "movimentacao_mensal_gtin.parquet")

    df: pl.DataFrame | None = None
    from_cache = False
    query_time_ms: float | None = None
    save_time_ms:  float | None = None
    read_time_ms:  float | None = None

    if os.path.exists(PARQUET_PATH):
        try:
            t0 = time.perf_counter()
            df = pl.read_parquet(PARQUET_PATH)
            read_time_ms = round((time.perf_counter() - t0) * 1000, 1)
            from_cache = True
        except Exception as e:
            print(f"[ CACHE ] {cnpj} ● GTIN ● ⚠️ ERRO DE LEITURA ({e})")

    if df is None:
        try:
            from database import engine as _engine
            with _engine.connect() as conn:
                t0 = time.perf_counter()
                pdf = pd.read_sql(
                    text("""
                        SELECT m.codigo_barra, m.periodo,
                               m.qnt_vendas, m.qnt_vendas_sem_comprovacao,
                               CAST(m.valor_vendas AS FLOAT)         AS valor_vendas,
                               CAST(m.valor_sem_comprovacao AS FLOAT) AS valor_sem_comprovacao
                        FROM [temp_CGUSC].[fp].[movimentacao_mensal_gtin] m
                        INNER JOIN [temp_CGUSC].[fp].[processamento] p ON p.id = m.id_processamento
                        WHERE p.cnpj = :cnpj AND p.situacao = 1
                    """),
                    conn,
                    params={"cnpj": cnpj},
                )
                query_time_ms = round((time.perf_counter() - t0) * 1000, 1)

            df = pl.from_pandas(pdf).with_columns([
                pl.col("codigo_barra").cast(pl.String),
                pl.col("periodo").cast(pl.Date),
                pl.col("qnt_vendas").cast(pl.Int64),
                pl.col("qnt_vendas_sem_comprovacao").cast(pl.Int64),
                pl.col("valor_vendas").cast(pl.Float64),
                pl.col("valor_sem_comprovacao").cast(pl.Float64),
            ])
            t1 = time.perf_counter()
            df.write_parquet(PARQUET_PATH, compression="zstd")
            save_time_ms = round((time.perf_counter() - t1) * 1000, 1)

            print(f"⏱  GTIN {cnpj}: SQL {query_time_ms}ms | parquet {save_time_ms}ms")
        except Exception:
            print(f"[ ANALYTICS ] {cnpj} ● GTIN ● ❌ INDISPONÍVEL (Sem Cache e Banco Offline)")
            df = pl.DataFrame()

    if df.is_empty():
        return EvolucaoMensalGtinResponse(
            meses=[],
            from_cache=from_cache,
            query_time_ms=query_time_ms,
            save_time_ms=save_time_ms,
            read_time_ms=read_time_ms,
        )

    # Filtro de período (opera sobre a coluna Date)
    if data_inicio:
        df = df.filter(pl.col("periodo") >= pl.lit(data_inicio).cast(pl.Date))
    if data_fim:
        df = df.filter(pl.col("periodo") <= pl.lit(data_fim).cast(pl.Date))

    if df.is_empty():
        return EvolucaoMensalGtinResponse(
            meses=[],
            from_cache=from_cache,
            query_time_ms=query_time_ms,
            save_time_ms=save_time_ms,
            read_time_ms=read_time_ms,
        )

    agg = (
        df
        .with_columns(pl.col("periodo").dt.strftime("%Y-%m").alias("mes"))
        .group_by("mes")
        .agg([
            pl.sum("qnt_vendas").alias("qnt_vendas"),
            pl.sum("qnt_vendas_sem_comprovacao").alias("qnt_vendas_sem_comprovacao"),
            pl.sum("valor_vendas").alias("valor_vendas"),
            pl.sum("valor_sem_comprovacao").alias("valor_sem_comprovacao"),
        ])
        .sort("mes")
        .with_columns(
            pl.when(pl.col("valor_vendas") > 0)
              .then(pl.col("valor_sem_comprovacao") / pl.col("valor_vendas") * 100)
              .otherwise(pl.lit(0.0))
              .clip(0.0, 100.0)
              .round(2)
              .alias("pct_sem_comprovacao")
        )
    )

    meses = [
        MesMensalGtinItem(
            mes=r["mes"],
            qnt_vendas=int(r["qnt_vendas"] or 0),
            qnt_vendas_sem_comprovacao=int(r["qnt_vendas_sem_comprovacao"] or 0),
            valor_vendas=round(float(r["valor_vendas"] or 0.0), 2),
            valor_sem_comprovacao=round(float(r["valor_sem_comprovacao"] or 0.0), 2),
            pct_sem_comprovacao=float(r["pct_sem_comprovacao"] or 0.0),
        )
        for r in agg.iter_rows(named=True)
    ]
    return EvolucaoMensalGtinResponse(
        meses=meses,
        from_cache=from_cache,
        query_time_ms=query_time_ms,
        save_time_ms=save_time_ms,
        read_time_ms=read_time_ms,
    )

def get_gtin_ranking_periodo(cnpj: str, periodo: str) -> GtinDetalhamentoMensalResponse:
    """
    Retorna o ranking de GTINs para um período (ex: '2019-07' ou '2019-S1').
    Lê do parquet 'movimentacao_mensal_gtin.parquet'.
    """
    import time
    from sqlalchemy import text
    
    t0 = time.perf_counter()
    cnpj_dir = _get_cnpj_cache_dir(cnpj)
    PARQUET_PATH = os.path.join(cnpj_dir, "movimentacao_mensal_gtin.parquet")
    
    if not os.path.exists(PARQUET_PATH):
        get_evolucao_mensal_gtin(cnpj)
        
    if not os.path.exists(PARQUET_PATH):
        return GtinDetalhamentoMensalResponse(cnpj=cnpj, periodo=periodo, summary=GtinDetalhamentoMensalSummary(), ranking=[])
        
    df = pl.read_parquet(PARQUET_PATH)
    
    # Filtro de período
    if len(periodo) == 7 and '-' in periodo:
        import calendar
        if 'S' in periodo:
            ano, sem = periodo.split("-S")
            m_inicio = 1 if sem == "1" else 7
            m_fim = 6 if sem == "1" else 12
            dt_inicio = f"{ano}-{m_inicio:02d}-01"
            last_day = calendar.monthrange(int(ano), m_fim)[1]
            dt_fim = f"{ano}-{m_fim:02d}-{last_day}"
        else:
            ano, mes = periodo.split("-")
            dt_inicio = f"{periodo}-01"
            last_day = calendar.monthrange(int(ano), int(mes))[1]
            dt_fim = f"{periodo}-{last_day}"
            
        df = df.filter((pl.col("periodo") >= pl.lit(dt_inicio).cast(pl.Date)) & 
                       (pl.col("periodo") <= pl.lit(dt_fim).cast(pl.Date)))
                       
    if df.is_empty():
        return GtinDetalhamentoMensalResponse(cnpj=cnpj, periodo=periodo, summary=GtinDetalhamentoMensalSummary(), ranking=[], read_time_ms=round((time.perf_counter() - t0)*1000, 1))
        
    medicamentos_map = {}
    try:
        from data_cache import get_medicamentos_df
        df_med = get_medicamentos_df()
        for r in df_med.iter_rows(named=True):
            codigo = r.get("codigo_barra")
            if codigo:
                val_str = str(codigo)
                clean_val = val_str.split(".")[0] if "." in val_str else val_str
                info = {
                    "medicamento": r.get("principio_ativo") or r.get("produto") or "Substância Não Identificada",
                    "principio_ativo": r.get("principio_ativo"),
                    "produto": r.get("produto"),
                    "laboratorio": r.get("laboratorio")
                }
                medicamentos_map[clean_val] = info
                medicamentos_map[val_str] = info
    except Exception as e:
        print(f"⚠️ Erro ao buscar dicionario de medicamentos do cache: {e}")
        
    agg = (
        df.group_by("codigo_barra")
        .agg([
            pl.sum("qnt_vendas").alias("qnt_vendas"),
            pl.sum("qnt_vendas_sem_comprovacao").alias("qnt_vendas_sem_comprovacao"),
            pl.sum("valor_vendas").alias("valor_vendas"),
            pl.sum("valor_sem_comprovacao").alias("valor_sem_comprovacao"),
        ])
        .filter(pl.col("qnt_vendas") > 0)
        .with_columns(
            pl.when(pl.col("valor_vendas") > 0)
              .then((pl.col("valor_sem_comprovacao") / pl.col("valor_vendas")) * 100)
              .otherwise(pl.lit(0.0))
              .clip(0.0, 100.0)
              .round(2)
              .alias("pct_sem_comprovacao")
        )
        .sort("valor_sem_comprovacao", descending=True)
    )
    
    total_gtins = agg.height
    gtins_irreg = agg.filter(pl.col("valor_sem_comprovacao") > 0).height
    gtins_reg = total_gtins - gtins_irreg
    
    summary = GtinDetalhamentoMensalSummary(
        total_gtins=total_gtins,
        gtins_irregulares=gtins_irreg,
        gtins_regulares=gtins_reg
    )
    
    ranking = []
    for r in agg.iter_rows(named=True):
        gtin_str = str(r["codigo_barra"])
        clean_gtin = gtin_str.split(".")[0] if "." in gtin_str else gtin_str
        info = medicamentos_map.get(clean_gtin) or medicamentos_map.get(gtin_str) or {}
        
        ranking.append(GtinDetalhamentoMensalItem(
            gtin=clean_gtin,
            medicamento=info.get("medicamento", "Substância Não Identificada"),
            principio_ativo=info.get("principio_ativo"),
            produto=info.get("produto"),
            laboratorio=info.get("laboratorio"),
            qnt_vendas=int(r["qnt_vendas"]),
            qnt_vendas_sem_comprovacao=int(r["qnt_vendas_sem_comprovacao"]),
            valor_vendas=round(float(r["valor_vendas"]), 2),
            valor_sem_comprovacao=round(float(r["valor_sem_comprovacao"]), 2),
            pct_sem_comprovacao=float(r["pct_sem_comprovacao"])
        ))
        
    read_time = round((time.perf_counter() - t0) * 1000, 1)
    
    return GtinDetalhamentoMensalResponse(
        cnpj=cnpj,
        periodo=periodo,
        summary=summary,
        ranking=ranking,
        from_cache=True,
        read_time_ms=read_time
    )

