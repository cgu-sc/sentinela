from typing import List, Optional
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
from cache_files import MOVIMENTACAO_MENSAL_GTIN_PARQUET
from data_cache import get_df, get_rede_df, get_localidades_df, get_df_bench_crm_regiao, get_df_bench_crm_br, get_df_dados_farmacia, get_df_perfil_estabelecimento, get_cache_dir, get_df_volume_atipico_semestral
from ...schemas.analytics import (
    AnalyticsKPISchema,
    ResultadoSentinelaUFSchema,
    AnalyticsResponse,
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
    MesMensalGtinItem,
    EvolucaoMensalGtinResponse,
    GtinDetalhamentoMensalResponse,
    GtinDetalhamentoMensalSummary,
    GtinDetalhamentoMensalItem,
)

from ._cache import _get_cnpj_cache_dir
from .volume_atipico import (
    DEFAULT_VOLUME_ATIPICO_AUMENTO_MINIMO,
    is_volume_atipico_relevante,
    normalize_volume_atipico_limite,
)
from cache_producers.financeiro import load_or_sync_movimentacao_mensal_gtin

def get_evolucao_financeira(cnpj: str, data_inicio=None, data_fim=None, volume_atipico_limite=None) -> EvolucaoFinanceiraResponse:
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
        limite_volume_atipico = normalize_volume_atipico_limite(volume_atipico_limite)
        perfil = get_df_perfil_estabelecimento().filter(pl.col("cnpj") == cnpj).select("id_cnpj")
        if perfil.is_empty():
            return EvolucaoFinanceiraResponse(cnpj=cnpj, semestres=[])
        id_cnpj = perfil.item(0, 0)
        df = get_df()
        cnpj_df = df.filter(pl.col("id_cnpj") == id_cnpj).select(["periodo", "total_vendas", "total_sem_comprovacao"])

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

        volume_atipico_by_semestre = {}
        try:
            volume_df = (
                get_df_volume_atipico_semestral()
                .filter(pl.col("id_cnpj") == id_cnpj)
                .select([
                    "chave_semestre",
                    "status_semestre",
                    "qtd_meses_presentes",
                    "chave_semestre_anterior",
                    "aumento_valor_semestre",
                    "taxa_crescimento_pct",
                ])
            )
            volume_atipico_by_semestre = {
                int(row["chave_semestre"]): row
                for row in volume_df.iter_rows(named=True)
            }
        except Exception as volume_error:
            print(f"[EVOLUCAO] volume_atipico_semestral indisponivel para {cnpj}: {volume_error}")

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

        def _optional_float(value):
            return float(value) if value is not None else None

        def _volume_info_for(row):
            chave_semestre = int(row["ano"]) * 100 + int(row["sem_num"])
            info = volume_atipico_by_semestre.get(chave_semestre, {})
            taxa = info.get("taxa_crescimento_pct")
            aumento = info.get("aumento_valor_semestre")
            return (
                chave_semestre,
                info,
                _optional_float(taxa),
                _optional_float(aumento),
            )

        semestres = []
        for r in agg.iter_rows(named=True):
            chave_semestre, volume_info, taxa_crescimento, aumento_valor = _volume_info_for(r)
            semestres.append(EvolucaoSemestreSchema(
                semestre=r["semestre"],
                total=round(r["total"], 2),
                regular=round(r["regular"], 2),
                irregular=round(r["irregular"], 2),
                pct_irregular=r["pct_irregular"],
                mes_inicio=r["dt_inicio"].strftime("%Y-%m") if r.get("dt_inicio") else None,
                mes_fim=r["dt_fim"].strftime("%Y-%m") if r.get("dt_fim") else None,
                chave_semestre=chave_semestre,
                volume_atipico=is_volume_atipico_relevante(
                    taxa_crescimento,
                    aumento_valor,
                    limite_volume_atipico,
                ),
                taxa_crescimento_pct=round(taxa_crescimento, 2) if taxa_crescimento is not None else None,
                chave_semestre_anterior=int(volume_info["chave_semestre_anterior"]) if volume_info.get("chave_semestre_anterior") is not None else None,
                aumento_valor_semestre=round(aumento_valor, 2) if aumento_valor is not None else None,
                status_semestre=int(volume_info["status_semestre"]) if volume_info.get("status_semestre") is not None else None,
                qtd_meses_presentes=int(volume_info["qtd_meses_presentes"]) if volume_info.get("qtd_meses_presentes") is not None else None,
                limite_volume_atipico_pct=limite_volume_atipico,
                limite_aumento_volume_atipico=DEFAULT_VOLUME_ATIPICO_AUMENTO_MINIMO,
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
            ))
        return EvolucaoFinanceiraResponse(cnpj=cnpj, semestres=semestres)

    except Exception as e:
        import traceback
        print(f"❌ ERRO AO CALCULAR EVOLUÇÃO FINANCEIRA: {e}")
        print(traceback.format_exc())
        return EvolucaoFinanceiraResponse(cnpj=cnpj, semestres=[])

def get_evolucao_mensal_gtin(cnpj: str, data_inicio=None, data_fim=None) -> EvolucaoMensalGtinResponse:
    """
    Retorna a série mensal de quantidades e valores (por GTIN agregado) para um CNPJ.
    Lazy cache: gera sentinela_cache/{cnpj}/movimentacao_mensal_gtin na primeira chamada.

    Args:
        cnpj: CNPJ completo (14 dígitos).
        data_inicio: Data inicial opcional para recorte do período (date).
        data_fim: Data final opcional para recorte do período (date).

    Returns:
        EvolucaoMensalGtinResponse com lista de meses ordenados ASC.
    """
    result = load_or_sync_movimentacao_mensal_gtin(cnpj)
    if result.error:
        raise HTTPException(
            status_code=503,
            detail=f"Evolucao mensal por GTIN indisponivel: {result.error}",
        )

    df = result.df
    if df is None:
        raise HTTPException(
            status_code=503,
            detail="Evolucao mensal por GTIN indisponivel: cache sem DataFrame carregado.",
        )
    from_cache = result.from_cache
    query_time_ms = result.query_time_ms
    save_time_ms = result.save_time_ms
    read_time_ms = result.read_time_ms

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
            pl.sum("qnt_caixas_vendidas").alias("qnt_caixas_vendidas"),
            pl.sum("qnt_caixas_sem_comprovacao").alias("qnt_caixas_sem_comprovacao"),
            pl.sum("num_autorizacoes").alias("num_autorizacoes"),
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
            qnt_caixas_vendidas=int(r["qnt_caixas_vendidas"] or 0),
            qnt_caixas_sem_comprovacao=int(r["qnt_caixas_sem_comprovacao"] or 0),
            num_autorizacoes=int(r["num_autorizacoes"] or 0),
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
    Le do parquet mensal GTIN.
    """
    import time
    
    t0 = time.perf_counter()
    cnpj_dir = _get_cnpj_cache_dir(cnpj)
    PARQUET_PATH = os.path.join(cnpj_dir, MOVIMENTACAO_MENSAL_GTIN_PARQUET)
    
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
            pl.sum("qnt_caixas_vendidas").alias("qnt_caixas_vendidas"),
            pl.sum("qnt_caixas_sem_comprovacao").alias("qnt_caixas_sem_comprovacao"),
            pl.sum("num_autorizacoes").alias("num_autorizacoes"),
            pl.sum("valor_vendas").alias("valor_vendas"),
            pl.sum("valor_sem_comprovacao").alias("valor_sem_comprovacao"),
        ])
        .filter(pl.col("qnt_caixas_vendidas") > 0)
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
            qnt_caixas_vendidas=int(r["qnt_caixas_vendidas"]),
            qnt_caixas_sem_comprovacao=int(r["qnt_caixas_sem_comprovacao"]),
            num_autorizacoes=int(r["num_autorizacoes"]),
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


