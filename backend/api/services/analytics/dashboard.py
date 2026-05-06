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

def get_dashboard_data(db: Session, data_inicio=None, data_fim=None, perc_min=None, perc_max=None, val_min=None, uf=None, regiao_saude=None, municipio=None, situacao_rf=None, conexao_ms=None, porte_empresa=None, grande_rede=None, cnpj_raiz=None, unidade_pf=None, razao_social=None, cnpjs: List[str] = None) -> AnalyticsResponse:
    """
    Versão Unificada (Motor Polars): Calcula KPIs e análise por UF em tempo real.
    Garante consistência total entre as telas e alta performance via processamento em memória.
    """
    try:
        def human_format(num):
            if num is None: return "0"
            num = float(num)
            if num >= 1_000_000_000:
                return f"R$ {num/1_000_000_000:.2f} Bi".replace('.', ',')
            if num >= 1_000_000:
                return f"R$ {num/1_000_000:.2f} Mi".replace('.', ',')
            if num >= 1_000:
                return f"R$ {num/1_000:.0f} K"
            return f"R$ {num:,.2f}".replace(',', 'X').replace('.', ',').replace('X', '.')

        def human_format_qty(num):
            if num is None: return "0"
            num = float(num)
            if num >= 1_000_000_000:
                return f"{num/1_000_000_000:.2f} Bi".replace('.', ',')
            if num >= 1_000_000:
                return f"{num/1_000_000:.2f} Mi".replace('.', ',')
            if num >= 1_000:
                return f"{num/1_000:.0f} K"
            return f"{num:.0f}"

        def build_kpis(cnpjs, total_vendas, val_sem_comp, perc_sem_comp, total_meds, qtd_municipios):
            return [
                AnalyticsKPISchema(id='total_municipios', label='Municípios', value=f"{(qtd_municipios or 0):,}".replace(',', '.'), color='#06b6d4', icon='pi pi-map-marker'),
                AnalyticsKPISchema(id='total_cnpjs', label='CNPJs', value=f"{(cnpjs or 0):,}".replace(',', '.'), color='#3b82f6', icon='pi pi-id-card'),
                AnalyticsKPISchema(id='valor_vendas', label='Valor Total de Vendas', value=human_format(total_vendas), color='#10b981', icon='pi pi-dollar'),
                AnalyticsKPISchema(id='perc_valor', label='% sem comprovação', value=f"{(perc_sem_comp or 0):.2f}%".replace('.', ','), color='#f59e0b', icon='pi pi-percentage'),
                AnalyticsKPISchema(id='valor_nao_comp', label='Valor sem Comprovação', value=human_format(val_sem_comp), color='#ef4444', icon='pi pi-dollar'),
                AnalyticsKPISchema(id='total_meds', label='Qtde de Medicamentos', value=human_format_qty(total_meds), color='#8b5cf6', icon='pi pi-box'),
            ]

        # 1. Parâmetros e DataFrame Base
        MIN_DATA = date(2015, 7, 1)
        MAX_DATA = date(2024, 12, 31)
        p_min = perc_min if perc_min is not None else 0.0
        p_max = perc_max if perc_max is not None else 100.0
        v_min = float(val_min) if val_min is not None and val_min > 0 else None
        
        inicio = (data_inicio if data_inicio and data_inicio >= MIN_DATA else MIN_DATA) if data_inicio else MIN_DATA
        fim = data_fim if data_fim else MAX_DATA

        df = get_df()

        # 2. Pipeline Polars - Filtros de Período e Geografia (Pré-agregação por CNPJ)
        mask = pl.col("periodo").is_between(inicio, fim)
        if uf and uf != 'Todos':                      mask = mask & (pl.col("uf") == uf)
        if regiao_saude and regiao_saude != 'Todos':  mask = mask & (pl.col("no_regiao_saude") == regiao_saude)
        if municipio and municipio != 'Todos':        mask = mask & (pl.col("no_municipio") == municipio)
        if situacao_rf and situacao_rf != 'Todos':    mask = mask & (pl.col("situacao_rf") == situacao_rf)
        if conexao_ms and conexao_ms != 'Todos':
            mask = mask & (pl.col("is_conexao_ativa") == (conexao_ms == 'Ativa'))
        if porte_empresa and porte_empresa != 'Todos': mask = mask & (pl.col("porte_empresa") == porte_empresa)
        if grande_rede and grande_rede != 'Todos':
            mask = mask & (pl.col("is_grande_rede") == (grande_rede == 'Sim'))
        if unidade_pf and unidade_pf != 'Todos':
            mask = mask & (pl.col("unidade_pf") == unidade_pf)
        if cnpj_raiz:
            if len(cnpj_raiz) == 14:
                mask = mask & (pl.col("cnpj") == cnpj_raiz)
            else:
                mask = mask & (pl.col("cnpj").str.slice(0, 8) == cnpj_raiz)
        if razao_social:
            mask = mask & (pl.col("razao_social").str.to_lowercase().str.contains(razao_social.lower()))
        if cnpjs:
            mask = mask & (pl.col("cnpj").is_in(cnpjs))

        period_df = df.filter(mask)

        # 3. Agregação Granular (CNPJ) para aplicação de filtros de Risco (% e Valor)
        cnpj_agg = period_df.group_by("cnpj").agg([
            pl.sum("total_vendas").alias("tv"),
            pl.sum("total_sem_comprovacao").alias("tsc"),
            pl.sum("total_qnt_vendas").alias("tqv"),
            pl.sum("total_qnt_sem_comprovacao").alias("tqsc"),
        ]).with_columns([
            (pl.col("tsc") / pl.when(pl.col("tv") > 0).then(pl.col("tv")).otherwise(None) * 100).fill_null(0).alias("pct")
        ])

        # Aplicação dos filtros de corte
        cnpj_ok = cnpj_agg.filter((pl.col("pct") >= p_min) & (pl.col("pct") <= p_max))
        if v_min is not None:
            cnpj_ok = cnpj_ok.filter(pl.col("tsc") >= v_min)

        # 4. Cálculo dos KPIs Globais
        tv  = float(cnpj_ok["tv"].sum() or 0)
        tsc = float(cnpj_ok["tsc"].sum() or 0)
        tqv = float(cnpj_ok["tqv"].sum() or 0)
        pct = (tsc / tv * 100) if tv else 0.0
        qtd_mun = int(period_df.join(cnpj_ok.select("cnpj"), on="cnpj", how="inner").select(pl.n_unique("no_municipio")).item() or 0)
        kpis = build_kpis(cnpj_ok.height, tv, tsc, pct, tqv, qtd_mun)

        # 5. Detalhamento por UF (Breakdown)
        uf_df = (
            period_df
            .join(cnpj_ok.select("cnpj"), on="cnpj", how="inner")
            .group_by("uf")
            .agg([
                pl.n_unique("cnpj").alias("cnpjs"),
                pl.sum("total_vendas").alias("totalMov"),
                pl.sum("total_sem_comprovacao").alias("valSemComp"),
                pl.sum("total_qnt_vendas").alias("totalQtde"),
                pl.sum("total_qnt_sem_comprovacao").alias("qtdeSemComp"),
            ])
            .with_columns([
                (pl.col("valSemComp") / pl.when(pl.col("totalMov") > 0).then(pl.col("totalMov")).otherwise(None) * 100).alias("percValSemComp"),
                (pl.col("qtdeSemComp") / pl.when(pl.col("totalQtde") > 0).then(pl.col("totalQtde")).otherwise(None) * 100).alias("percQtdeSemComp"),
            ])
            .sort("percValSemComp", descending=True, nulls_last=True)
        )

        resultado_sentinela_uf = [
            ResultadoSentinelaUFSchema(**r)
            for r in uf_df.iter_rows(named=True)
        ]

        # 6. Detalhamento por Município (Sempre calculado)
        muni_df = (
            period_df
            .join(cnpj_ok.select("cnpj"), on="cnpj", how="inner")
            .group_by(["uf", "no_municipio"])
            .agg([
                pl.n_unique("cnpj").alias("cnpjs"),
                pl.sum("total_vendas").alias("totalMov"),
                pl.sum("total_sem_comprovacao").alias("valSemComp"),
                pl.sum("total_qnt_vendas").alias("totalQtde"),
                pl.sum("total_qnt_sem_comprovacao").alias("qtdeSemComp"),
            ])
            .with_columns([
                (pl.col("valSemComp") / pl.when(pl.col("totalMov") > 0).then(pl.col("totalMov")).otherwise(None) * 100).alias("percValSemComp"),
                (pl.col("qtdeSemComp") / pl.when(pl.col("totalQtde") > 0).then(pl.col("totalQtde")).otherwise(None) * 100).alias("percQtdeSemComp"),
            ])
            .sort("percValSemComp", descending=True, nulls_last=True)
        )
        # Enrich muni_df with id_ibge7 from localidades
        try:
            loc_muni = (
                get_localidades_df()
                .select(["no_municipio", "sg_uf", "id_ibge7"])
                .group_by(["no_municipio", "sg_uf"])
                .agg(pl.col("id_ibge7").first())
            )
            muni_df = muni_df.join(
                loc_muni,
                left_on=["no_municipio", "uf"],
                right_on=["no_municipio", "sg_uf"],
                how="left"
            )
        except Exception:
            muni_df = muni_df.with_columns(pl.lit(None).cast(pl.Int64).alias("id_ibge7"))
        resultado_municipios = [
            ResultadoSentinelaMunicipioSchema(municipio=r["no_municipio"], **r)
            for r in muni_df.iter_rows(named=True)
        ]

        # 7. Detalhamento por CNPJ (Sempre calculado)
        cnpj_df = (
            period_df
            .join(cnpj_ok.select("cnpj"), on="cnpj", how="inner")
            .group_by("cnpj")
            .agg([
                pl.col("no_municipio").first().alias("municipio"),
                pl.col("uf").first().alias("uf"),
                pl.col("razao_social").first().alias("razao_social"),
                pl.sum("total_vendas").alias("totalMov"),
                pl.sum("total_sem_comprovacao").alias("valSemComp"),
                pl.sum("total_qnt_vendas").alias("totalQtde"),
                pl.sum("total_qnt_sem_comprovacao").alias("qtdeSemComp"),
                pl.col("is_grande_rede").first().alias("is_grande_rede"),
                pl.col("qtd_estabelecimentos_rede").first().alias("qtd_estabelecimentos_rede"),
                pl.col("situacao_rf").first().alias("situacao_rf"),
                pl.col("porte_empresa").first().alias("porte_empresa"),
                pl.col("is_conexao_ativa").first().alias("is_conexao_ativa"),
                (pl.col("is_matriz").cast(pl.Boolean).first().fill_null(False) if "is_matriz" in period_df.columns else pl.lit(False).alias("is_matriz")),
            ])
            .with_columns([
                (pl.col("valSemComp") / pl.when(pl.col("totalMov") > 0).then(pl.col("totalMov")).otherwise(None) * 100).alias("percValSemComp"),
                (pl.col("qtdeSemComp") / pl.when(pl.col("totalQtde") > 0).then(pl.col("totalQtde")).otherwise(None) * 100).alias("percQtdeSemComp"),
                (pl.col("municipio") + " / " + pl.col("uf")).alias("municipio_uf"),
            ])
            .sort("percValSemComp", descending=True, nulls_last=True)
        )
        # Enrich with id_ibge7 from localidades (unique por município/UF para evitar duplicatas)
        try:
            loc_df = (
                get_localidades_df()
                .select(["no_municipio", "sg_uf", "id_ibge7"])
                .group_by(["no_municipio", "sg_uf"])
                .agg(pl.col("id_ibge7").first())
            )
            cnpj_df = cnpj_df.join(
                loc_df,
                left_on=["municipio", "uf"],
                right_on=["no_municipio", "sg_uf"],
                how="left"
            )
        except Exception:
            cnpj_df = cnpj_df.with_columns(pl.lit(None).cast(pl.Int64).alias("id_ibge7"))

        # Enrich with rankings and counts from matriz_risco_consolidada
        try:
            risco_df = get_df_matriz_risco()
            # Tornar colunas case-insensitive de forma segura (cria novo DataFrame devido ao copy-on-write construtivo)
            risco_df = risco_df.rename({c: c.lower() for c in risco_df.columns})
            
            expected_cols = [
                "cnpj", "rank_nacional", "total_nacional", "rank_uf", "total_uf",
                "rank_regiao_saude", "total_regiao_saude", "rank_municipio", "total_municipio",
                "score_risco_final", "classificacao_risco"
            ]
            # Apenas seleciona colunas que de fato existem na matriz
            available_cols = [c for c in expected_cols if c in risco_df.columns]
            
            if "cnpj" in available_cols and len(available_cols) > 1:
                risco_df = risco_df.select(available_cols)
                cnpj_df = cnpj_df.join(risco_df, on="cnpj", how="left")
        except Exception as e:
            print(f"⚠️ Erro ao cruzar rankings: {e}")
            cnpj_df = cnpj_df.with_columns([
                pl.lit(None).cast(pl.Int64).alias("rank_nacional"),
                pl.lit(None).cast(pl.Int64).alias("total_nacional"),
                pl.lit(None).cast(pl.Int64).alias("rank_uf"),
                pl.lit(None).cast(pl.Int64).alias("total_uf"),
                pl.lit(None).cast(pl.Int64).alias("rank_regiao_saude"),
                pl.lit(None).cast(pl.Int64).alias("total_regiao_saude"),
                pl.lit(None).cast(pl.Int64).alias("rank_municipio"),
                pl.lit(None).cast(pl.Int64).alias("total_municipio"),
            ])

        resultado_cnpjs = [
            ResultadoSentinelaCnpjSchema(**r)
            for r in cnpj_df.iter_rows(named=True)
        ]

        return AnalyticsResponse(
            kpis=kpis, 
            resultado_sentinela_uf=resultado_sentinela_uf,
            resultado_municipios=resultado_municipios,
            resultado_cnpjs=resultado_cnpjs
        )

    except Exception as e:
        import traceback
        print(f"❌ ERRO NO MOTOR POLARS (Analytics): {e}")
        print(traceback.format_exc())
        return AnalyticsResponse(kpis=[], resultado_sentinela_uf=[], resultado_municipios=None)

def get_resultado_sentinela(db: Session) -> List[ResultadoSentinelaSchema]:
    """
    Busca TODOS os registros da tabela de resultados detalhados (CNPJs).
    """
    try:
        sql = text("""
            SELECT 
                uf, id_ibge7, municipio, nu_populacao, cnpj, razao_social, 
                qnt_medicamentos_vendidos, qnt_medicamentos_vendidos_sem_comprovacao, 
                nu_autorizacoes, valor_vendas, valor_sem_comprovacao, 
                percentual_sem_comprovacao, num_estabelecimentos_mesmo_municipio, 
                num_meses_movimentacao, CodPorteEmpresa
            FROM [temp_CGUSC].[fp].[resultado_sentinela]
        """)
        result = db.execute(sql).fetchall()
        return [ResultadoSentinelaSchema(**row._mapping) for row in result]
    except Exception as e:
        import traceback
        print("❌ ERRO AO BUSCAR RESULTADOS DETALHADOS:")
        print(traceback.format_exc())
        return []

def get_rede_por_cnpj_raiz(cnpj_raiz: str) -> List[RedeEstabelecimentoSchema]:
    """Retorna todos os estabelecimentos de uma rede dado o CNPJ raiz (8 dígitos)."""
    try:
        df = get_rede_df()
        result = df.filter(pl.col("cnpj_raiz") == cnpj_raiz).sort("is_matriz", descending=True)
        return [RedeEstabelecimentoSchema(**r) for r in result.iter_rows(named=True)]
    except Exception as e:
        import traceback
        print(f"❌ ERRO AO BUSCAR REDE: {e}")
        print(traceback.format_exc())
        return []

