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
from ..schemas.analytics import (
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
)

# ── Mapeamento de indicadores: chave → (col_valor, col_med_reg, col_med_uf, col_med_br, col_risco_reg, col_risco_uf, col_risco_br) ──
INDICATOR_MAPPING: dict[str, tuple[str, str, str, str, str, str, str]] = {
    'percentual_nao_comprovacao': ('pct_auditado',              'med_auditado_reg',             'med_auditado_uf',             'med_auditado_br',             'risco_auditado_reg',             'risco_auditado_uf',             'risco_auditado_br'),
    'falecidos':                   ('pct_falecidos',             'med_falecidos_reg',            'med_falecidos_uf',            'med_falecidos_br',            'risco_falecidos_reg',            'risco_falecidos_uf',            'risco_falecidos_br'),
    'incompatibilidade_patologica':('pct_clinico',               'med_clinico_reg',              'med_clinico_uf',              'med_clinico_br',              'risco_clinico_reg',              'risco_clinico_uf',              'risco_clinico_br'),
    'teto':                  ('pct_teto',                  'med_teto_reg',                 'med_teto_uf',                 'med_teto_br',                 'risco_teto_reg',                 'risco_teto_uf',                 'risco_teto_br'),
    'polimedicamento':       ('pct_polimedicamento',       'med_polimedicamento_reg',      'med_polimedicamento_uf',      'med_polimedicamento_br',      'risco_polimedicamento_reg',      'risco_polimedicamento_uf',      'risco_polimedicamento_br'),
    'ticket_medio':               ('val_ticket_medio',          'med_ticket_reg',               'med_ticket_uf',               'med_ticket_br',               'risco_ticket_reg',               'risco_ticket_uf',               'risco_ticket_br'),
    'receita_paciente':      ('val_receita_paciente',      'med_receita_paciente_reg',     'med_receita_paciente_uf',     'med_receita_paciente_br',     'risco_receita_paciente_reg',     'risco_receita_paciente_uf',     'risco_receita_paciente_br'),
    'per_capita':            ('val_per_capita',            'med_per_capita_reg',           'med_per_capita_uf',           'med_per_capita_br',           'risco_per_capita_reg',           'risco_per_capita_uf',           'risco_per_capita_br'),
    'alto_custo':            ('pct_alto_custo',            'med_alto_custo_reg',           'med_alto_custo_uf',           'med_alto_custo_br',           'risco_alto_custo_reg',           'risco_alto_custo_uf',           'risco_alto_custo_br'),
    'vendas_rapidas':        ('pct_vendas_rapidas',        'med_vendas_rapidas_reg',       'med_vendas_rapidas_uf',       'med_vendas_rapidas_br',       'risco_vendas_rapidas_reg',       'risco_vendas_rapidas_uf',       'risco_vendas_rapidas_br'),
    'volume_atipico':        ('val_volume_atipico',        'med_volume_atipico_reg',       'med_volume_atipico_uf',       'med_volume_atipico_br',       'risco_volume_atipico_reg',       'risco_volume_atipico_uf',       'risco_volume_atipico_br'),
    'recorrencia_sistemica': ('pct_recorrencia_sistemica', 'med_recorrencia_sistemica_reg','med_recorrencia_sistemica_uf','med_recorrencia_sistemica_br','risco_recorrencia_sistemica_reg','risco_recorrencia_sistemica_uf','risco_recorrencia_sistemica_br'),
    'dias_pico':                  ('pct_pico',                  'med_pico_reg',                 'med_pico_uf',                 'med_pico_br',                 'risco_pico_reg',                 'risco_pico_uf',                 'risco_pico_br'),
    'dispersao_geografica':       ('pct_geografico',            'med_geografico_reg',           'med_geografico_uf',           'med_geografico_br',           'risco_geografico_reg',           'risco_geografico_uf',           'risco_geografico_br'),
    'compra_unica':      ('pct_compra_unica',          'med_compra_unica_reg',         'med_compra_unica_uf',         'med_compra_unica_br',         'risco_compra_unica_reg',         'risco_compra_unica_uf',         'risco_compra_unica_br'),
    'hhi_crm':               ('val_hhi_crm',               'med_hhi_crm_reg',              'med_hhi_crm_uf',              'med_hhi_crm_br',              'risco_crm_reg',                  'risco_crm_uf',                  'risco_crm_br'),
    'exclusividade_crm':     ('pct_exclusividade_crm',     'med_exclusividade_crm_reg',    'med_exclusividade_crm_uf',    'med_exclusividade_crm_br',    'risco_exclusividade_crm_reg',    'risco_exclusividade_crm_uf',    'risco_exclusividade_crm_br'),
    'crms_irregulares':      ('pct_crms_irregulares',      'med_crms_irregulares_reg',     'med_crms_irregulares_uf',     'med_crms_irregulares_br',     'risco_crms_irregulares_reg',     'risco_crms_irregulares_uf',     'risco_crms_irregulares_br'),
}

# Mapeamento indicador → (col_flag_atencao, col_flag_critico) na fp.matriz_risco_consolidada.
# Flags calculadas via Modified Z-Score (MAD) no SQL — fonte de verdade para Status na UI.
_INDICATOR_FLAGS: dict[str, tuple[str, str]] = {
    # 1. Auditoria Financeira
    'percentual_nao_comprovacao':   ('flag_percentual_sem_comprovacao_atencao', 'flag_percentual_sem_comprovacao_critico'),
    # 2. Elegibilidade & Clínica
    'falecidos':                    ('flag_falecidos_atencao',                  'flag_falecidos_critico'),
    'incompatibilidade_patologica': ('flag_incompatibilidade_patologica_atencao', 'flag_incompatibilidade_patologica_critico'),
    # 3. Padrões de Quantidade
    'teto':                         ('flag_estouro_teto_atencao',               'flag_estouro_teto_critico'),
    'polimedicamento':               ('flag_polimedicamento_atencao',            'flag_polimedicamento_critico'),
    # 4. Padrões Financeiros
    'ticket_medio':                  ('flag_ticket_medio_atencao',               'flag_ticket_medio_critico'),
    'receita_paciente':              ('flag_receita_paciente_atencao',           'flag_receita_paciente_critico'),
    'per_capita':                    ('flag_per_capita_atencao',                 'flag_per_capita_critico'),
    'alto_custo':                    ('flag_alto_custo_atencao',                 'flag_alto_custo_critico'),
    # 5. Automação & Geografia
    'vendas_rapidas':                ('flag_vendas_rapidas_atencao',             'flag_vendas_rapidas_critico'),
    'volume_atipico':                ('flag_volume_atipico_atencao',             'flag_volume_atipico_critico'),
    'recorrencia_sistemica':         ('flag_recorrencia_sistemica_atencao',      'flag_recorrencia_sistemica_critico'),
    'dias_pico':                     ('flag_concentracao_pico_atencao',          'flag_concentracao_pico_critico'),
    'dispersao_geografica':          ('flag_dispersao_geografica_atencao',       'flag_dispersao_geografica_critico'),
    'compra_unica':                  ('flag_compra_unica_atencao',               'flag_compra_unica_critico'),
    # 6. Integridade Médica
    'hhi_crm':                       ('flag_hhi_crm_atencao',                   'flag_hhi_crm_critico'),
    'exclusividade_crm':             ('flag_exclusividade_crm_atencao',          'flag_exclusividade_crm_critico'),
    'crms_irregulares':              ('flag_crms_irregulares_atencao',           'flag_crms_irregulares_critico'),
}

class AnalyticsService:
    @staticmethod
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

    @staticmethod
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

    @staticmethod
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

    @staticmethod
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

    @staticmethod
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

        cnpj_dir = AnalyticsService._get_cnpj_cache_dir(cnpj)
        PARQUET_PATH = os.path.join(cnpj_dir, "movimentacao_mensal_gtin.parquet")

        df: pl.DataFrame | None = None
        from_cache = False
        query_time_ms: float | None = None
        save_time_ms: float | None = None

        if os.path.exists(PARQUET_PATH):
            try:
                df = pl.read_parquet(PARQUET_PATH)
                from_cache = True
            except Exception as e:
                print(f"⚠️ Erro ao ler parquet gtin '{cnpj}': {e}")

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
                df.write_parquet(PARQUET_PATH, compression="lz4")
                save_time_ms = round((time.perf_counter() - t1) * 1000, 1)

                print(f"⏱  GTIN {cnpj}: SQL {query_time_ms}ms | parquet {save_time_ms}ms")
            except Exception as e:
                import traceback
                print(f"⚠️ Erro ao gerar parquet gtin '{cnpj}': {e}")
                print(traceback.format_exc())
                df = pl.DataFrame()

        if df.is_empty():
            return EvolucaoMensalGtinResponse(
                meses=[],
                from_cache=from_cache,
                query_time_ms=query_time_ms,
                save_time_ms=save_time_ms,
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
        )

    @staticmethod
    def get_indicadores(cnpj: str) -> IndicadoresResponse:
        """Retorna os 18 indicadores de risco para um CNPJ a partir da matriz_risco_consolidada."""
        try:
            df = get_df_matriz_risco()
            df = df.rename({c: c.lower() for c in df.columns})
            rows = df.filter(pl.col("cnpj") == cnpj)
            if rows.is_empty():
                return IndicadoresResponse(cnpj=cnpj, indicadores={})
            row = rows.row(0, named=True)

            def _f(v):
                return float(v) if v is not None else None

            indicadores = {
                key: IndicadorDataSchema(
                    valor=_f(row.get(c_val)),
                    med_reg=_f(row.get(c_mr)),
                    med_uf=_f(row.get(c_mu)),
                    med_br=_f(row.get(c_mb)),
                    risco_reg=_f(row.get(c_rr)),
                    risco_uf=_f(row.get(c_ru)),
                    risco_br=_f(row.get(c_rb)),
                )
                for key, (c_val, c_mr, c_mu, c_mb, c_rr, c_ru, c_rb) in INDICATOR_MAPPING.items()
            }
            return IndicadoresResponse(cnpj=cnpj, indicadores=indicadores)
        except Exception as e:
            print(traceback.format_exc())
            return IndicadoresResponse(cnpj=cnpj, indicadores={})

    @staticmethod
    def get_indicadores_analise(
        indicador: str,
        uf: str | None = None,
        regiao_saude: str | None = None,
        municipio: str | None = None,
        situacao_rf: str | None = None,
        conexao_ms: str | None = None,
        porte_empresa: str | None = None,
        grande_rede: str | None = None,
        cnpj_raiz: str | None = None,
        unidade_pf: str | None = None,
        perc_min: float | None = None,
        perc_max: float | None = None,
        val_min: float | None = None,
    ) -> IndicadorAnaliseResponse:
        """
        Análise cruzada de um indicador de risco: retorna KPIs, mapa municipal
        e tabela de CNPJs ranqueados por risco, filtrados pelo escopo geográfico.

        Operação 100% em memória (Polars) sobre df_matriz_risco + df_movimentacao.
        Não usa filtros de período — a matriz_risco é um snapshot consolidado.
        Mas aceita filtros de percentual e valor mínimo acumulado.

        Args:
            indicador: Chave do indicador (ex: 'auditado', 'teto'). Deve existir em INDICATOR_MAPPING.
            uf: Sigla da UF ou None.
            regiao_saude: Nome da Região de Saúde ou None.
            municipio: Nome do município ou None.
            situacao_rf: Situação na Receita Federal ou None.
            conexao_ms: 'Ativa' | 'Inativa' | None.
            porte_empresa: Porte CNPJ ou None.
            grande_rede: 'Sim' | 'Não' | None.
            cnpj_raiz: 8 ou 14 dígitos ou None.
            unidade_pf: Nome da Unidade PF ou None.
            perc_min: Limiar mínimo de não comprovação (%)
            perc_max: Limiar máximo de não comprovação (%)
            val_min: Valor bruto mínimo sem comprovação (R$)

        Returns:
            IndicadorAnaliseResponse com kpis, municipios e cnpjs.

        Raises:
            HTTPException 400 se a chave do indicador for inválida.
        """
        if indicador not in INDICATOR_MAPPING:
            raise HTTPException(
                status_code=400,
                detail=f"Indicador '{indicador}' inválido. Valores aceitos: {sorted(INDICATOR_MAPPING.keys())}"
            )

        try:
            c_val, c_mr, _c_mu, _c_mb, c_rr, _c_ru, _c_rb = INDICATOR_MAPPING[indicador]
            c_aten, c_crit = _INDICATOR_FLAGS[indicador]

            # ── 1. Snapshot geográfico por CNPJ (última ocorrência de cada campo cadastral) ──
            df_mov = get_df()
            df_geo = df_mov.group_by("cnpj").agg([
                pl.col("uf").last().alias("uf"),
                pl.col("no_municipio").last().alias("no_municipio"),
                pl.col("no_regiao_saude").last().alias("no_regiao_saude"),
                pl.col("razao_social").last().alias("razao_social"),
                pl.col("is_grande_rede").last().alias("is_grande_rede"),
                pl.col("situacao_rf").last().alias("situacao_rf"),
                pl.col("is_conexao_ativa").last().alias("is_conexao_ativa"),
                pl.col("porte_empresa").last().alias("porte_empresa"),
                pl.col("unidade_pf").last().alias("unidade_pf"),
                pl.col("total_vendas").sum().alias("total_vendas"),
                pl.col("total_sem_comprovacao").sum().alias("total_sem_comprovacao"),
            ]).with_columns([
                pl.when(pl.col("total_vendas") > 0)
                  .then((pl.col("total_sem_comprovacao") / pl.col("total_vendas") * 100).round(2))
                  .otherwise(pl.lit(None))
                  .alias("perc_val_sem_comp")
            ])

            # ── 2. Filtros geográficos e cadastrais ──
            mask = pl.lit(True)
            if uf and uf != 'Todos':
                mask = mask & (pl.col("uf") == uf)
            if regiao_saude and regiao_saude != 'Todos':
                mask = mask & (pl.col("no_regiao_saude") == regiao_saude)
            if municipio and municipio != 'Todos':
                mask = mask & (pl.col("no_municipio") == municipio)
            if situacao_rf and situacao_rf != 'Todos':
                mask = mask & (pl.col("situacao_rf") == situacao_rf)
            if conexao_ms and conexao_ms != 'Todos':
                mask = mask & (pl.col("is_conexao_ativa") == (conexao_ms == 'Ativa'))
            if porte_empresa and porte_empresa != 'Todos':
                mask = mask & (pl.col("porte_empresa") == porte_empresa)
            if grande_rede and grande_rede != 'Todos':
                mask = mask & (pl.col("is_grande_rede") == (grande_rede == 'Sim'))
            if unidade_pf and unidade_pf != 'Todos':
                mask = mask & (pl.col("unidade_pf") == unidade_pf)
            if cnpj_raiz:
                cnpj_raiz_clean = cnpj_raiz.replace(".", "").replace("/", "").replace("-", "")
                if len(cnpj_raiz_clean) == 14:
                    mask = mask & (pl.col("cnpj") == cnpj_raiz_clean)
                elif len(cnpj_raiz_clean) >= 8:
                    mask = mask & (pl.col("cnpj").str.slice(0, 8) == cnpj_raiz_clean[:8])

            df_geo = df_geo.filter(mask)

            # ── 2A. Novos Filtros de Valor e Percentual (Snapshot) ──
            if perc_min is not None:
                df_geo = df_geo.filter(pl.col("perc_val_sem_comp") >= perc_min)
            if perc_max is not None:
                df_geo = df_geo.filter(pl.col("perc_val_sem_comp") <= perc_max)
            if val_min is not None:
                df_geo = df_geo.filter(pl.col("total_sem_comprovacao") >= val_min)

            if df_geo.is_empty():
                empty_kpis = IndicadorKpiSummarySchema()
                return IndicadorAnaliseResponse(indicador=indicador, kpis=empty_kpis, municipios=[], cnpjs=[])

            # ── 3. Join com matriz de risco (inner: apenas CNPJs com score calculado) ──
            df_risco = get_df_matriz_risco()
            df_risco = df_risco.rename({c: c.lower() for c in df_risco.columns})

            # Seleciona apenas as colunas necessárias da matriz
            score_col = "score_risco_final"
            risco_cols = ["cnpj", c_val, c_mr, c_rr, c_aten, c_crit, score_col]
            risco_cols_available = [c for c in risco_cols if c in df_risco.columns]

            df_risco_slim = df_risco.select(risco_cols_available)
            df_joined = df_geo.join(df_risco_slim, on="cnpj", how="inner")

            if df_joined.is_empty():
                empty_kpis = IndicadorKpiSummarySchema()
                return IndicadorAnaliseResponse(indicador=indicador, kpis=empty_kpis, municipios=[], cnpjs=[])

            # ── 4. Enriquece id_ibge7 via localidades ──
            df_loc = get_localidades_df()
            loc_slim = df_loc.select(["no_municipio", "sg_uf", "id_ibge7"]).unique(subset=["no_municipio", "sg_uf"])
            df_joined = df_joined.join(
                loc_slim,
                left_on=["no_municipio", "uf"],
                right_on=["no_municipio", "sg_uf"],
                how="left"
            )

            # ── 5. Calcula status via flags MAD (fonte de verdade: fp.matriz_risco_consolidada) ──
            # fl_*_crit e fl_*_aten são calculados no SQL via Modified Z-Score por região/UF.
            rr_col = c_rr if c_rr in df_joined.columns else None
            has_flags = c_crit in df_joined.columns and c_aten in df_joined.columns
            if has_flags:
                df_joined = df_joined.with_columns([
                    pl.when(pl.col(c_val).is_null())
                      .then(pl.lit("SEM DADOS"))
                      .when(pl.col(c_crit).cast(pl.Int32) == 1)
                      .then(pl.lit("CRÍTICO"))
                      .when(pl.col(c_aten).cast(pl.Int32) == 1)
                      .then(pl.lit("ATENÇÃO"))
                      .otherwise(pl.lit("NORMAL"))
                      .alias("status")
                ])
            else:
                df_joined = df_joined.with_columns(pl.lit("SEM DADOS").alias("status"))

            # ── 6. Ordena por risco_reg descendente ──
            if rr_col and rr_col in df_joined.columns:
                df_sorted = df_joined.sort(rr_col, descending=True, nulls_last=True)
            else:
                df_sorted = df_joined

            # ── 7. Monta lista de CNPJs ──
            def _f(v) -> float | None:
                return float(v) if v is not None else None

            cnpjs_list: list[IndicadorCnpjRowSchema] = []
            for row in df_sorted.iter_rows(named=True):
                cnpjs_list.append(IndicadorCnpjRowSchema(
                    cnpj=str(row["cnpj"]),
                    razao_social=row.get("razao_social"),
                    municipio=str(row["no_municipio"]).title() if row.get("no_municipio") else None,
                    uf=row.get("uf"),
                    id_ibge7=int(row["id_ibge7"]) if row.get("id_ibge7") is not None else None,
                    valor=_f(row.get(c_val)),
                    med_reg=_f(row.get(c_mr)),
                    risco_reg=_f(row.get(c_rr)) if rr_col else None,
                    status=row.get("status", "SEM DADOS"),
                    is_grande_rede=bool(row.get("is_grande_rede", False)),
                    situacao_rf=row.get("situacao_rf"),
                    is_conexao_ativa=bool(row.get("is_conexao_ativa", False)),
                    score_risco_final=_f(row.get(score_col)) if score_col in (risco_cols_available) else None,
                    val_sem_comp=_f(row.get("total_sem_comprovacao")),
                    perc_val_sem_comp=_f(row.get("perc_val_sem_comp")),
                ))

            # ── 8. Agregação por município para o mapa ──
            mun_agg = (
                df_joined
                .group_by(["no_municipio", "uf", "id_ibge7"])
                .agg([
                    pl.len().alias("total_cnpjs"),
                    (pl.col("status") == "CRÍTICO").sum().alias("total_critico"),
                ])
                .with_columns([
                    (
                        pl.col("total_critico").cast(pl.Float64) /
                        pl.when(pl.col("total_cnpjs") > 0)
                        .then(pl.col("total_cnpjs").cast(pl.Float64))
                        .otherwise(pl.lit(1.0)) * 100
                    ).round(2).alias("pct_critico")
                ])
                .sort("pct_critico", descending=True)
            )

            municipios_list: list[IndicadorMunicipioRowSchema] = []
            for row in mun_agg.iter_rows(named=True):
                municipios_list.append(IndicadorMunicipioRowSchema(
                    municipio=str(row["no_municipio"]).title() if row.get("no_municipio") else "",
                    uf=row.get("uf"),
                    id_ibge7=int(row["id_ibge7"]) if row.get("id_ibge7") is not None else None,
                    total_cnpjs=int(row["total_cnpjs"] or 0),
                    total_critico=int(row["total_critico"] or 0),
                    pct_critico=float(row["pct_critico"] or 0.0),
                ))

            # ── 9. KPIs de resumo com Contexto Regional de Benchmarking ──
            status_counts = df_joined["status"].value_counts().to_dicts()
            counts = {r["status"]: r["count"] for r in status_counts}

            total_com_dados = counts.get("CRÍTICO", 0) + counts.get("ATENÇÃO", 0) + counts.get("NORMAL", 0)
            pct_acima_limiar = (
                (counts.get("CRÍTICO", 0) + counts.get("ATENÇÃO", 0)) / total_com_dados * 100
                if total_com_dados > 0 else None
            )

            # Identifica a Região de Saúde de referência (mesmo se filtro for municipal)
            ref_regiao = regiao_saude
            if (not ref_regiao or ref_regiao == 'Todos') and (municipio and municipio != 'Todos'):
                # Busca a região de saúde desse município no dataframe original
                sample = df_joined.select("no_regiao_saude").unique().limit(1)
                if not sample.is_empty():
                    ref_regiao = sample.item(0, 0)

            # Cálculo de Mediana/MAD sobre o CONTEXTO (UF + opcionalmente Região de Saúde)
            context_mask = pl.lit(True)
            if uf and uf != 'Todos':
                context_mask = context_mask & (pl.col("uf") == uf)
            if ref_regiao and ref_regiao != 'Todos':
                context_mask = context_mask & (pl.col("no_regiao_saude") == ref_regiao)

            # Buscamos a mediana e MAD do indicador para o contexto regional completo
            mediana_reg = None
            mad_reg = None
            # df_geo original contém todos os CNPJs com geo; filtramos os do contexto
            df_context_geo = df_mov.group_by("cnpj").agg([
                pl.col("uf").last().alias("uf"),
                pl.col("no_regiao_saude").last().alias("no_regiao_saude")
            ]).filter(context_mask)
            
            df_context = df_context_geo.join(df_risco.select(["cnpj", c_val, c_rr]), on="cnpj", how="inner")
            
            if not df_context.is_empty():
                s_valores = df_context.select(c_val).drop_nulls().to_series().sort()
                s_riscos = df_context.select(c_rr).drop_nulls().to_series().sort()
                
                if not s_valores.is_empty():
                    mediana_reg = float(s_valores.median() or 0)
                
                if not s_riscos.is_empty():
                    # Para o MAD/Z-Score, usamos os scores (ratios) onde a mediana teórica é 1.0
                    m_r = float(s_riscos.median() or 1.0)
                    mad_reg = float((s_riscos - m_r).abs().median() or 0.0001)

            kpis = IndicadorKpiSummarySchema(
                total_critico=counts.get("CRÍTICO", 0),
                total_atencao=counts.get("ATENÇÃO", 0),
                total_normal=counts.get("NORMAL", 0),
                total_sem_dados=counts.get("SEM DADOS", 0),
                mediana_reg=mediana_reg,
                mad_reg=mad_reg,
                pct_acima_limiar=round(pct_acima_limiar, 2) if pct_acima_limiar is not None else None,
                limiar_atencao=None,
                limiar_critico=None
            )

            return IndicadorAnaliseResponse(
                indicador=indicador,
                kpis=kpis,
                municipios=municipios_list,
                cnpjs=cnpjs_list,
            )

        except HTTPException:
            raise
        except Exception as e:
            import traceback
            print(f"❌ ERRO EM get_indicadores_analise (indicador={indicador}): {e}")
            print(traceback.format_exc())
            raise HTTPException(status_code=500, detail="Erro interno ao processar análise de indicadores.")

    @staticmethod
    def get_falecidos_data(
        cnpj: str,
        data_inicio: date | None = None,
        data_fim:    date | None = None,
    ) -> FalecidosResponse:
        """
        Retorna os dados detalhados de vendas para falecidos de um CNPJ.

        O parquet por CNPJ armazena as transações do próprio estabelecimento e de todos
        os demais CNPJs onde os mesmos CPFs compraram, permitindo calcular o ranking
        Multi-CNPJ a partir do cache local sem depender do dataset global.
        """
        import time
        import pandas as pd
        from sqlalchemy import text

        PARQUET_PATH = os.path.join(AnalyticsService._get_cnpj_cache_dir(cnpj), "falecidos.parquet")
        from_cache    = False
        query_time_ms: float | None = None
        save_time_ms:  float | None = None
        df_all = None

        # ── 1. Tentar carregar do cache local ────────────────────────────────
        if os.path.exists(PARQUET_PATH):
            try:
                df_all = pl.read_parquet(PARQUET_PATH)
                from_cache = True
            except Exception as e:
                print(f"⚠️ Erro ao ler parquet falecidos '{cnpj}': {e}")

        # ── 2. Gerar parquet via SQL (primeira vez ou cache corrompido) ──────
        if df_all is None:
            try:
                from database import engine as _engine
                with _engine.connect() as conn:
                    t0 = time.perf_counter()
                    pdf = pd.read_sql(
                        text("""
                            SELECT f.*
                            FROM [temp_CGUSC].[fp].[falecidos_por_farmacia] f
                            WHERE f.cpf IN (
                                SELECT DISTINCT cpf
                                FROM [temp_CGUSC].[fp].[falecidos_por_farmacia]
                                WHERE cnpj = :cnpj
                            )
                        """),
                        conn,
                        params={"cnpj": cnpj},
                    )
                    query_time_ms = round((time.perf_counter() - t0) * 1000, 1)

                df_all = pl.from_pandas(pdf).with_columns([
                    pl.col("dt_nascimento").cast(pl.Date, strict=False),
                    pl.col("dt_obito").cast(pl.Date, strict=False),
                    pl.col("data_autorizacao").cast(pl.Date, strict=False),
                ])
                t1 = time.perf_counter()
                df_all.write_parquet(PARQUET_PATH, compression="lz4")
                save_time_ms = round((time.perf_counter() - t1) * 1000, 1)
                print(f"⏱  Falecidos {cnpj}: SQL {query_time_ms}ms | parquet {save_time_ms}ms")

            except Exception as e:
                import traceback
                print(f"⚠️ Erro ao gerar parquet falecidos '{cnpj}': {e}")
                print(traceback.format_exc())
                df_all = pl.DataFrame()

        # ── 3. Filtro de período ─────────────────────────────────────────────
        if data_inicio:
            df_all = df_all.filter(pl.col("data_autorizacao") >= pl.lit(data_inicio).cast(pl.Date))
        if data_fim:
            df_all = df_all.filter(pl.col("data_autorizacao") <= pl.lit(data_fim).cast(pl.Date))

        _empty_response = FalecidosResponse(
            cnpj=cnpj,
            summary=FalecidosSummarySchema(
                cpfs_distintos=0, total_autorizacoes=0, valor_total=0.0,
                media_dias=0.0, max_dias=0, pct_faturamento=0.0,
                cpfs_multi_cnpj=0, pct_multi_cnpj=0.0,
            ),
            ranking=[],
            transacoes=[],
            from_cache=from_cache,
            query_time_ms=query_time_ms,
            save_time_ms=save_time_ms,
        )

        try:
            df_target = df_all.filter(pl.col("cnpj") == cnpj)

            if df_target.is_empty():
                return _empty_response

            # 1. KPIs Básicos
            cpfs_distintos = df_target["cpf"].n_unique()
            total_autorizacoes = df_target.height
            valor_total = float(df_target["valor_total_autorizacao"].sum() or 0.0)
            media_dias = float(df_target["dias_apos_obito"].mean() or 0.0)
            max_dias = int(df_target["dias_apos_obito"].max() or 0)

            # 2. Lógica Multi-CNPJ (Inteligência Cross-Pharmacy)
            # Encontra outros estabelecimentos onde ESSES CPFs compraram
            cpfs_alvo = df_target["cpf"].unique()
            df_outros = df_all.filter((pl.col("cpf").is_in(cpfs_alvo)) & (pl.col("cnpj") != cnpj))
            
            # Mapeia quais CPFs são Multi-CNPJ
            cpfs_multi = df_outros["cpf"].unique().to_list()
            cpfs_multi_cnpj = len(cpfs_multi)
            pct_multi_cnpj = cpfs_multi_cnpj / cpfs_distintos if cpfs_distintos > 0 else 0.0

            # 3. Ranking de Outros Estabelecimentos
            # Precisamos dos nomes das farmácias. Vamos usar a rede_df se possível.
            try:
                rede_df = get_rede_df().select(["cnpj", "razao_social", "municipio", "uf"])
                df_outros_nomes = df_outros.join(rede_df, on="cnpj", how="left")
                
                ranking_df = (
                    df_outros_nomes
                    .with_columns([
                        pl.concat_str([
                            pl.col("cnpj"), pl.lit(" - "), 
                            pl.col("razao_social").fill_null("DESCONHECIDO"),
                            pl.lit(" | "), 
                            pl.col("municipio").fill_null(""),
                            pl.lit("/"),
                            pl.col("uf").fill_null("")
                        ]).alias("estab")
                    ])
                    .group_by("estab")
                    .agg([pl.col("cpf").n_unique().alias("qtd")])
                    .with_columns([
                        (pl.col("qtd") / pl.when(pl.col("qtd").sum() > 0).then(pl.col("qtd").sum()).otherwise(1)).alias("pct")
                    ])
                    .sort("qtd", descending=True)
                    .head(20)
                )
                ranking = [
                    FalecidosRankingSchema(estabelecimento=r["estab"], qtd_cpfs=r["qtd"], pct_total=r["pct"])
                    for r in ranking_df.iter_rows(named=True)
                ]
            except:
                ranking = []

            # 4. Cálculo do % de faturamento (usando o faturamento total cacheado)
            pct_faturamento = 0.0
            try:
                mov_df = get_df().filter(pl.col("cnpj") == cnpj)
                total_faturamento = float(mov_df["total_vendas"].sum() or 1.0)
                pct_faturamento = valor_total / total_faturamento if total_faturamento > 0 else 0.0
            except: pass

            # 5. Lista de Transações (com flag de multi-cnpj)
            # Vamos gerar a string de 'outros_estabelecimentos' para cada CPF
            try:
                outros_info = (
                    df_outros_nomes
                    .with_columns([
                        pl.concat_str([
                            pl.col("cnpj"), pl.lit(" | "), pl.col("municipio"), pl.lit("/"), pl.col("uf")
                        ]).alias("info")
                    ])
                    .group_by("cpf")
                    .agg([pl.col("info").unique().str.join("; ").alias("outros")])
                )
                df_final = df_target.join(outros_info, on="cpf", how="left")
            except:
                df_final = df_target.with_columns(pl.lit(None).alias("outros"))

            transacoes = [
                FalecidoTransactionSchema(
                    cpf=str(r["cpf"]).zfill(11),
                    nome_falecido=r["nome_falecido"],
                    municipio_falecido=r["municipio_falecido"],
                    uf_falecido=r["uf_falecido"],
                    dt_nascimento=r["dt_nascimento"],
                    dt_obito=r["dt_obito"],
                    fonte_obito=r["fonte_obito"],
                    num_autorizacao=str(r["num_autorizacao"]),
                    data_autorizacao=r["data_autorizacao"],
                    qtd_itens_na_autorizacao=int(r["qtd_itens_na_autorizacao"] or 0),
                    valor_total_autorizacao=float(r["valor_total_autorizacao"] or 0.0),
                    dias_apos_obito=int(r["dias_apos_obito"] or 0),
                    outros_estabelecimentos=r["outros"]
                )
                for r in df_final.sort(["cpf", "data_autorizacao"]).iter_rows(named=True)
            ]

            return FalecidosResponse(
                cnpj=cnpj,
                summary=FalecidosSummarySchema(
                    cpfs_distintos=cpfs_distintos,
                    total_autorizacoes=total_autorizacoes,
                    valor_total=valor_total,
                    media_dias=media_dias,
                    max_dias=max_dias,
                    pct_faturamento=pct_faturamento,
                    cpfs_multi_cnpj=cpfs_multi_cnpj,
                    pct_multi_cnpj=pct_multi_cnpj,
                ),
                ranking=ranking,
                transacoes=transacoes,
                from_cache=from_cache,
                query_time_ms=query_time_ms,
                save_time_ms=save_time_ms,
            )

        except Exception as e:
            import traceback
            print(f"❌ ERRO AO CALCULAR DADOS DE FALECIDOS: {e}")
            print(traceback.format_exc())
            return _empty_response

    @staticmethod
    def get_timeline_cpf(cnpj_referencia: str, cpf: str) -> MultiCnpjTimelineResponse:
        """
        Retorna TODAS as transações de um CPF em TODOS os estabelecimentos
        presentes no dataset de falecidos. Permite montar o Mapa de Trilhas
        Temporais com dados 100% reais.

        Args:
            cnpj_referencia: O CNPJ do estabelecimento que originou a consulta
                             (usado para marcar `is_this_cnpj`).
            cpf: O CPF do paciente falecido a ser pesquisado.
        """
        try:
            # O parquet por CNPJ contém todas as transações dos CPFs do estabelecimento
            # (incluindo outras farmácias), suficiente para montar a linha do tempo.
            PARQUET_PATH = os.path.join(
                AnalyticsService._get_cnpj_cache_dir(cnpj_referencia), "falecidos.parquet"
            )
            if not os.path.exists(PARQUET_PATH):
                return MultiCnpjTimelineResponse(
                    cpf=cpf, nome_falecido=None, dt_obito=None, events=[], cnpjs_envolvidos=[]
                )
            df_all = pl.read_parquet(PARQUET_PATH)

            # Normaliza o CPF (remove zeros à esquerda para comparação segura)
            cpf_clean = cpf.strip().lstrip('0').zfill(11)
            df_cpf = df_all.filter(pl.col("cpf").cast(pl.Utf8).str.zfill(11) == cpf_clean)

            if df_cpf.is_empty():
                return MultiCnpjTimelineResponse(
                    cpf=cpf, nome_falecido=None, dt_obito=None,
                    events=[], cnpjs_envolvidos=[]
                )

            # Dados biográficos do falecido (primeira ocorrência)
            row0 = df_cpf.row(0, named=True)
            nome_falecido = row0.get("nome_falecido")
            dt_obito = row0.get("dt_obito")

            # Enriquece com razão social via rede_df
            try:
                rede_df = get_rede_df().select(["cnpj", "razao_social"])
                df_enrich = df_cpf.join(rede_df, on="cnpj", how="left")
            except Exception:
                df_enrich = df_cpf.with_columns(pl.lit(None).cast(pl.Utf8).alias("razao_social"))

            # Monta os eventos
            events = []
            for r in df_enrich.sort("data_autorizacao").iter_rows(named=True):
                events.append(TimelineEventSchema(
                    cnpj=str(r["cnpj"]),
                    razao_social=r.get("razao_social"),
                    data_autorizacao=r.get("data_autorizacao"),
                    valor_total_autorizacao=float(r.get("valor_total_autorizacao") or 0.0),
                    num_autorizacao=str(r.get("num_autorizacao") or ""),
                    is_this_cnpj=(str(r["cnpj"]) == cnpj_referencia),
                ))

            cnpjs_envolvidos = df_cpf["cnpj"].unique().to_list()

            return MultiCnpjTimelineResponse(
                cpf=cpf,
                nome_falecido=nome_falecido,
                dt_obito=dt_obito,
                events=events,
                cnpjs_envolvidos=cnpjs_envolvidos,
            )

        except Exception as e:
            import traceback
            print(f"❌ ERRO AO BUSCAR TIMELINE DO CPF: {e}")
            print(traceback.format_exc())
            return MultiCnpjTimelineResponse(
                cpf=cpf, nome_falecido=None, dt_obito=None,
                events=[], cnpjs_envolvidos=[]
            )

    @staticmethod
    def get_fator_risco_data(db: Session, data_inicio=None, data_fim=None, perc_min=None, perc_max=None, val_min=None, uf=None, regiao_saude=None, municipio=None, situacao_rf=None, conexao_ms=None, porte_empresa=None, grande_rede=None, cnpj_raiz=None, unidade_pf=None, razao_social=None) -> FatorRiscoResponseSchema:
        """
        Calcula as faixas de risco (Buckets de 10%) via Polars.
        """
        try:
            MIN_DATA = date(2015, 7, 1)
            inicio = max(data_inicio, MIN_DATA) if data_inicio else MIN_DATA
            fim = data_fim if data_fim else date(2199, 12, 31)
            p_min = perc_min if perc_min is not None else 0.0
            p_max = perc_max if perc_max is not None else 100.0
            v_min = float(val_min) if val_min is not None and val_min > 0 else None

            df = get_df()
            mask = pl.col("periodo").is_between(inicio, fim)
            if uf:                                        mask = mask & (pl.col("uf") == uf)
            if regiao_saude:                              mask = mask & (pl.col("no_regiao_saude") == regiao_saude)
            if municipio:                                 mask = mask & (pl.col("no_municipio") == municipio)
            if situacao_rf and situacao_rf != 'Todos':     mask = mask & (pl.col("situacao_rf") == situacao_rf)
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

            cnpj_agg = (
                df.filter(mask)
                .group_by("cnpj")
                .agg([
                    pl.sum("total_vendas").alias("tv"),
                    pl.sum("total_sem_comprovacao").alias("tsc"),
                ])
                .with_columns([
                    (pl.col("tsc") / pl.when(pl.col("tv") > 0).then(pl.col("tv")).otherwise(None) * 100).fill_null(0).alias("pct")
                ])
                .filter((pl.col("pct") >= p_min) & (pl.col("pct") <= p_max))
            )

            if v_min is not None:
                cnpj_agg = cnpj_agg.filter(pl.col("tsc") >= v_min)

            faixa_expr = (
                pl.when(pl.col("pct") <= 10).then(pl.lit("00% - 10%"))
                .when(pl.col("pct") <= 20).then(pl.lit("10% - 20%"))
                .when(pl.col("pct") <= 30).then(pl.lit("20% - 30%"))
                .when(pl.col("pct") <= 40).then(pl.lit("30% - 40%"))
                .when(pl.col("pct") <= 50).then(pl.lit("40% - 50%"))
                .when(pl.col("pct") <= 60).then(pl.lit("50% - 60%"))
                .when(pl.col("pct") <= 70).then(pl.lit("60% - 70%"))
                .when(pl.col("pct") <= 80).then(pl.lit("70% - 80%"))
                .when(pl.col("pct") <= 90).then(pl.lit("80% - 90%"))
                .otherwise(pl.lit("90% - 100%"))
            )
            ordem_expr = (
                pl.when(pl.col("pct") <= 10).then(1).when(pl.col("pct") <= 20).then(2)
                .when(pl.col("pct") <= 30).then(3).when(pl.col("pct") <= 40).then(4)
                .when(pl.col("pct") <= 50).then(5).when(pl.col("pct") <= 60).then(6)
                .when(pl.col("pct") <= 70).then(7).when(pl.col("pct") <= 80).then(8)
                .when(pl.col("pct") <= 90).then(9).otherwise(10)
            )

            buckets_df = (
                cnpj_agg
                .with_columns([faixa_expr.alias("faixa"), ordem_expr.alias("ordem")])
                .group_by(["faixa", "ordem"])
                .agg([pl.len().alias("qtd"), pl.sum("tsc").alias("valor_raw")])
                .sort("ordem")
            )

            buckets = [
                FatorRiscoBucketSchema(
                    faixa=r["faixa"],
                    qtd=r["qtd"],
                    valor=f"R$ {r['valor_raw']:,.2f}".replace(',', 'X').replace('.', ',').replace('X', '.'),
                    valor_raw=r["valor_raw"]
                )
                for r in buckets_df.iter_rows(named=True)
            ]

            return FatorRiscoResponseSchema(
                periodo_formatado=f"{inicio} a {fim}" if data_inicio and data_fim else "Acumulado Histórico",
                buckets=buckets
            )
        except Exception as e:
            return FatorRiscoResponseSchema(periodo_formatado="Erro ao calcular", buckets=[])

    @staticmethod
    def get_regional_benchmarking(regiao_saude: str = None, uf: str = None, data_inicio: date = None, data_fim: date = None) -> RegionalResponse:
        """
        Constrói o payload completo de Benchmarking Regional.
        """
        try:
            df_mov   = get_df()
            df_loc   = get_localidades_df()
            df_risco = get_df_matriz_risco()
            df_risco = df_risco.rename({c: c.lower() for c in df_risco.columns})

            # ── Filtros de Período ───────────────────────────────────────────
            MIN_DATA = date(2015, 7, 1)
            MAX_DATA = date(2024, 12, 31)
            inicio = (data_inicio if data_inicio and data_inicio >= MIN_DATA else MIN_DATA) if data_inicio else MIN_DATA
            fim = data_fim if data_fim else MAX_DATA

            # ── Filtra movimentação para a região ou UF ──────────────────────────
            mask = pl.col("periodo").is_between(inicio, fim)
            if regiao_saude:
                mask = mask & (pl.col("no_regiao_saude") == regiao_saude)
                if uf and uf != 'Todos':
                    mask = mask & (pl.col("uf") == uf)
            else:
                mask = mask & (pl.col("uf") == uf)
                
            df_reg = df_mov.filter(mask)
            nome_escopo = f"{regiao_saude or uf or ''}"
            if df_reg.is_empty():
                return RegionalResponse(nome_regiao=nome_escopo, municipios=[], farmacias=[])

            # ── 1. Resumo por Município ─────────────────────────────────────────
            # Agrega CNPJs únicos e valores financeiros por município
            mun_agg = (
                df_reg
                .group_by(["no_municipio", "uf"])
                .agg([
                    pl.n_unique("cnpj").alias("qtd_farmacias"),
                    pl.sum("total_vendas").alias("totalMov"),
                    pl.sum("total_sem_comprovacao").alias("valSemComp"),
                ])
                .with_columns([
                    (
                        pl.col("valSemComp") /
                        pl.when(pl.col("totalMov") > 0)
                        .then(pl.col("totalMov"))
                        .otherwise(pl.lit(1.0)) * 100
                    ).round(2).alias("percValSemComp")
                ])
            )

            # Enriquece com população do IBGE (localidades_df)
            loc_pop = df_loc.select(["no_municipio", "sg_uf", "id_regiao_saude", "nu_populacao", "id_ibge7"]).unique(subset=["no_municipio", "sg_uf"])
            mun_enriched = mun_agg.join(
                loc_pop,
                left_on=["no_municipio", "uf"],
                right_on=["no_municipio", "sg_uf"],
                how="left"
            ).with_columns([
                pl.col("nu_populacao").fill_null(0).alias("populacao"),
                (
                    pl.col("nu_populacao").fill_null(0).cast(pl.Float64) /
                    pl.when(pl.col("qtd_farmacias") > 0)
                    .then(pl.col("qtd_farmacias").cast(pl.Float64))
                    .otherwise(pl.lit(1.0))
                ).round(2).alias("densidade"),
            ]).sort("no_municipio")

            # Pega o id_regiao_saude a partir da primeira ocorrência no dataset filtrado
            id_regiao: str | None = None
            if not mun_enriched.is_empty():
                id_regiao = str(mun_enriched.row(0, named=True).get("id_regiao_saude") or "")

            municipios = [
                RegionalMunicipioSchema(
                    uf=r["uf"],
                    municipio=str(r["no_municipio"]).title(),
                    id_ibge7=int(r["id_ibge7"]) if r.get("id_ibge7") else None,
                    populacao=int(r["populacao"] or 0),
                    qtd_farmacias=int(r["qtd_farmacias"] or 0),
                    densidade=float(r["densidade"] or 0.0),
                    totalMov=float(r.get("totalMov") or 0.0),
                    valSemComp=float(r.get("valSemComp") or 0.0),
                    percValSemComp=float(r.get("percValSemComp") or 0.0),
                )
                for r in mun_enriched.iter_rows(named=True)
            ]

            # ── 2. Ranking de Farmácias ──────────────────────────────────────────
            # Agrega valores financeiros acumulados por CNPJ (histórico completo)
            cnpj_agg = (
                df_reg
                .group_by("cnpj")
                .agg([
                    pl.col("no_municipio").first().alias("municipio"),
                    pl.col("uf").first().alias("uf"),
                    pl.col("razao_social").first().alias("razao_social"),
                    pl.col("is_conexao_ativa").first().alias("is_conexao_ativa"),
                    pl.sum("total_vendas").alias("totalMov"),
                    pl.sum("total_sem_comprovacao").alias("valSemComp"),
                    pl.col("periodo").max().alias("data_ultima_venda"),
                ])
                .with_columns([
                    (
                        pl.col("valSemComp") /
                        pl.when(pl.col("totalMov") > 0)
                        .then(pl.col("totalMov"))
                        .otherwise(pl.lit(1.0)) * 100
                    ).round(2).alias("percValSemComp")
                ])
            )

            # Enriquece com score e classificação de risco da matriz_risco_consolidada
            risco_cols = ["cnpj"]
            risco_available = []
            for col in ["score_risco_final", "classificacao_risco"]:
                if col in df_risco.columns:
                    risco_available.append(col)
                    risco_cols.append(col)

            if risco_available:
                df_risco_slim = df_risco.select(risco_cols)
                cnpj_enriched = cnpj_agg.join(df_risco_slim, on="cnpj", how="left")
            else:
                cnpj_enriched = cnpj_agg.with_columns([
                    pl.lit(None).cast(pl.Float64).alias("score_risco_final"),
                    pl.lit(None).cast(pl.Utf8).alias("classificacao_risco"),
                ])

            # Ordena pelo score de risco (maior risco primeiro)
            cnpj_sorted = cnpj_enriched.sort(
                "score_risco_final", descending=True, nulls_last=True
            ).with_columns(
                pl.lit(range(1, cnpj_enriched.height + 1))
                .alias("rank_")
            )

            farmacias = []
            for i, r in enumerate(cnpj_sorted.iter_rows(named=True), start=1):
                farmacias.append(RegionalFarmaciaSchema(
                    cnpj=r["cnpj"],
                    razao_social=str(r.get("razao_social") or "").title(),
                    municipio=str(r.get("municipio") or "").title(),
                    uf=r.get("uf"),
                    score_risco=float(r["score_risco_final"]) if r.get("score_risco_final") is not None else None,
                    classificacao_risco=r.get("classificacao_risco"),
                    valSemComp=float(r.get("valSemComp") or 0.0),
                    totalMov=float(r.get("totalMov") or 0.0),
                    percValSemComp=float(r.get("percValSemComp") or 0.0),
                    is_conexao_ativa=r.get("is_conexao_ativa"),
                    data_ultima_venda=r.get("data_ultima_venda"),
                    rank=i,
                ))

            return RegionalResponse(
                nome_regiao=nome_escopo,
                id_regiao=id_regiao,
                municipios=municipios,
                farmacias=farmacias,
            )

        except Exception as e:
            import traceback
            print(f"❌ ERRO AO CALCULAR DADOS REGIONAIS: {e}")
            print(traceback.format_exc())
            return RegionalResponse(nome_regiao=regiao_saude, municipios=[], farmacias=[])

    @staticmethod
    def get_regional_benchmarking_animation(
        regiao_saude: str = None,
        uf: str = None,
        data_inicio: date = None,
        data_fim: date = None,
    ) -> RegionalAnimationResponse:
        """
        Retorna todos os trimestres do período em uma única chamada para animação fluida.

        Em vez de N requests separados, o Polars deriva a coluna de trimestre e agrupa
        tudo em uma única passagem sobre o DataFrame em memória.
        """
        try:
            df_mov   = get_df()
            df_risco = get_df_matriz_risco()
            df_risco = df_risco.rename({c: c.lower() for c in df_risco.columns})

            MIN_DATA = date(2015, 7, 1)
            MAX_DATA = date(2024, 12, 31)
            inicio = (data_inicio if data_inicio and data_inicio >= MIN_DATA else MIN_DATA) if data_inicio else MIN_DATA
            fim    = data_fim if data_fim else MAX_DATA

            # ── Filtro geográfico + temporal ────────────────────────────────
            mask = pl.col("periodo").is_between(inicio, fim)
            if regiao_saude:
                mask = mask & (pl.col("no_regiao_saude") == regiao_saude)
                if uf and uf != "Todos":
                    mask = mask & (pl.col("uf") == uf)
            else:
                mask = mask & (pl.col("uf") == uf)

            df_reg = df_mov.filter(mask)
            nome_escopo = regiao_saude or uf or ""

            if df_reg.is_empty():
                return RegionalAnimationResponse(nome_regiao=nome_escopo, quarters=[])

            # ── Deriva índice de período relativo ao início do período ────
            # period_idx = 0 → primeiros 2 meses, 1 → próximos 2 meses, etc.
            # Janela de 2 meses para coincidir com PLAY_STEP=2 do slider de animação.
            inicio_year  = inicio.year
            inicio_month = inicio.month
            df_q = df_reg.with_columns([
                (
                    (pl.col("periodo").dt.year() - inicio_year) * 12
                    + pl.col("periodo").dt.month()
                    - inicio_month
                ).alias("_months_since_start")
            ]).with_columns([
                (pl.col("_months_since_start") // 2).alias("_quarter_idx")
            ])

            # ── Agrega por (trimestre, CNPJ) em uma única operação ──────────
            cnpj_q = (
                df_q
                .group_by(["_quarter_idx", "cnpj"])
                .agg([
                    pl.col("no_municipio").first().alias("municipio"),
                    pl.col("uf").first().alias("uf"),
                    pl.col("razao_social").first().alias("razao_social"),
                    pl.col("is_conexao_ativa").first().alias("is_conexao_ativa"),
                    pl.sum("total_vendas").alias("totalMov"),
                    pl.sum("total_sem_comprovacao").alias("valSemComp"),
                ])
                .with_columns([
                    (
                        pl.col("valSemComp")
                        / pl.when(pl.col("totalMov") > 0)
                          .then(pl.col("totalMov"))
                          .otherwise(pl.lit(1.0))
                        * 100
                    ).round(2).alias("percValSemComp")
                ])
            )

            # ── Enriquece com score de risco consolidado ────────────────────
            risco_cols = ["cnpj"]
            for col in ["score_risco_final", "classificacao_risco"]:
                if col in df_risco.columns:
                    risco_cols.append(col)
            df_risco_slim = df_risco.select(risco_cols)
            cnpj_q = cnpj_q.join(df_risco_slim, on="cnpj", how="left")

            if "score_risco_final" not in cnpj_q.columns:
                cnpj_q = cnpj_q.with_columns(pl.lit(None).cast(pl.Float64).alias("score_risco_final"))
            if "classificacao_risco" not in cnpj_q.columns:
                cnpj_q = cnpj_q.with_columns(pl.lit(None).cast(pl.Utf8).alias("classificacao_risco"))

            # Ordena por trimestre (asc) e risco (desc) para ranking correto
            cnpj_q = cnpj_q.sort(
                ["_quarter_idx", "score_risco_final"],
                descending=[False, True],
                nulls_last=True,
            )

            # ── Monta dicionário de trimestres ──────────────────────────────
            def _add_months(d: date, n: int) -> date:
                """Avança n meses a partir de d, retornando o dia 1 do novo mês."""
                m = d.month - 1 + n
                return date(d.year + m // 12, m % 12 + 1, 1)

            quarters_map: dict = {}
            rank_counter: dict = {}

            for r in cnpj_q.iter_rows(named=True):
                idx = r["_quarter_idx"]
                if idx not in quarters_map:
                    q_start = _add_months(inicio, idx * 2)
                    q_end_first = _add_months(inicio, idx * 2 + 1)
                    last_day = calendar.monthrange(q_end_first.year, q_end_first.month)[1]
                    q_end = min(date(q_end_first.year, q_end_first.month, last_day), fim)
                    quarters_map[idx] = {
                        "trimestre": f"{q_start.year}-{q_start.month:02d}",
                        "inicio": q_start,
                        "fim": q_end,
                        "farmacias": [],
                    }
                    rank_counter[idx] = 1

                quarters_map[idx]["farmacias"].append(RegionalFarmaciaSchema(
                    cnpj=r["cnpj"],
                    razao_social=str(r.get("razao_social") or "").title(),
                    municipio=str(r.get("municipio") or "").title(),
                    uf=r.get("uf"),
                    score_risco=float(r["score_risco_final"]) if r.get("score_risco_final") is not None else None,
                    classificacao_risco=r.get("classificacao_risco"),
                    valSemComp=float(r.get("valSemComp") or 0.0),
                    totalMov=float(r.get("totalMov") or 0.0),
                    percValSemComp=float(r.get("percValSemComp") or 0.0),
                    is_conexao_ativa=bool(r.get("is_conexao_ativa")),
                    data_ultima_venda=None,
                    rank=rank_counter[idx],
                ))
                rank_counter[idx] += 1

            quarters = [
                RegionalAnimationQuarterSchema(
                    trimestre=v["trimestre"],
                    inicio=v["inicio"],
                    fim=v["fim"],
                    farmacias=v["farmacias"],
                )
                for v in sorted(quarters_map.values(), key=lambda x: x["inicio"])
            ]

            return RegionalAnimationResponse(nome_regiao=nome_escopo, quarters=quarters)

        except Exception as e:
            import traceback
            print(f"❌ ERRO AO CALCULAR ANIMAÇÃO REGIONAL: {e}", flush=True)
            print(traceback.format_exc(), flush=True)
            return RegionalAnimationResponse(nome_regiao=regiao_saude or "", quarters=[])

    # Conjunto de diretórios de CNPJ já criados nesta sessão — evita syscalls redundantes.
    _known_cnpj_dirs: set[str] = set()

    @staticmethod
    def _get_cnpj_cache_dir(cnpj: str) -> str:
        """Retorna (e garante a existência de) sentinela_cache/{cnpj}/.

        Usa um cache em memória para evitar chamadas redundantes a makedirs
        em requests frequentes ao mesmo CNPJ.
        """
        from data_cache import get_cache_dir
        cnpj_dir = os.path.join(get_cache_dir(), cnpj)
        if cnpj_dir not in AnalyticsService._known_cnpj_dirs:
            os.makedirs(cnpj_dir, exist_ok=True)
            AnalyticsService._known_cnpj_dirs.add(cnpj_dir)
        return cnpj_dir


    @staticmethod
    def get_crm_data(
        cnpj: str,
        data_inicio: str | None = None,
        data_fim: str | None = None,
    ) -> PrescritoresResponse:
        """Retorna KPIs e top prescritores de um CNPJ a partir do parquet por CNPJ (lazy cache)."""
        import traceback
        import pandas as pd
        from data_cache import get_cache_dir

        cnpj_dir = AnalyticsService._get_cnpj_cache_dir(cnpj)
        PARQUET_PATH = os.path.join(cnpj_dir, "dados_crms.parquet")

        # ── helpers de competência ────────────────────────────────────────────
        def _to_comp(date_str: str) -> int:
            return int(date_str[:7].replace("-", ""))

        comp_ini = _to_comp(data_inicio) if data_inicio else None
        comp_fim = _to_comp(data_fim)    if data_fim    else None

        # ── 1. Carrega ou gera o parquet ──────────────────────────────────────
        df: pl.DataFrame | None = None
        if os.path.exists(PARQUET_PATH):
            try:
                df = pl.read_parquet(PARQUET_PATH)
            except Exception as e:
                print(f"⚠️ Erro ao ler parquet CRM '{cnpj}': {e}", flush=True)

        if df is None:
            try:
                from database import engine as _engine
                with _engine.connect() as conn:
                    pdf = pd.read_sql(
                        text("SELECT id_medico, cnpj, competencia, vl_total_prescricoes, nu_prescricoes, nu_prescricoes_dia, prescricoes_total_brasil, prescricoes_dia_brasil, nu_estabelecimentos, lista_cnpjs_brasil, flag_crm_invalido, flag_prescricao_antes_registro, flag_concentracao_estabelecimento, flag_concentracao_mesmo_crm, flag_distancia_geografica, alerta_distancia_geografica, dt_primeira_prescricao, dt_inscricao_crm"
                             " FROM temp_CGUSC.fp.crm_export WHERE cnpj = :cnpj"),
                        conn,
                        params={"cnpj": cnpj},
                    )
                if pdf.empty:
                    return PrescritoresResponse(cnpj=cnpj, summary={}, crms_interesse=[])
                df = pl.from_pandas(pdf)
                for col in ["flag_crm_invalido", "flag_prescricao_antes_registro", "flag_concentracao_estabelecimento"]:
                    if col in df.columns:
                        df = df.with_columns(pl.col(col).cast(pl.Int8))
                df.write_parquet(PARQUET_PATH, compression="lz4")
            except Exception as e:
                print(f"❌ ERRO ao buscar CRM do banco para {cnpj}: {e}")
                print(traceback.format_exc())
                return PrescritoresResponse(cnpj=cnpj, summary={}, crms_interesse=[])

        # ── 2. Filtro de período ───────────────────────────────────────────────
        if comp_ini:
            df = df.filter(pl.col("competencia") >= comp_ini)
        if comp_fim:
            df = df.filter(pl.col("competencia") <= comp_fim)

        if df.is_empty():
            return PrescritoresResponse(cnpj=cnpj, summary={}, crms_interesse=[])

        # ── 3. Agrega por id_medico (colapsa competências) ────────────────────
        total_valor = float(df["vl_total_prescricoes"].sum() or 0)

        # Para médias ponderadas reais (ritmo médio), precisamos do total de dias ativos.
        # nu_prescricoes_dia = nu_prescricoes / dias_ativos => dias_ativos = nu_prescricoes / nu_prescricoes_dia
        df = df.with_columns([
            pl.when(pl.col("nu_prescricoes_dia") > 0)
              .then(pl.col("nu_prescricoes").cast(pl.Float64) / pl.col("nu_prescricoes_dia"))
              .otherwise(pl.lit(0.0))
              .alias("_dias_ativos_loc"),
            pl.when(pl.col("prescricoes_dia_brasil") > 0)
              .then(pl.col("prescricoes_total_brasil").cast(pl.Float64) / pl.col("prescricoes_dia_brasil"))
              .otherwise(pl.lit(0.0))
              .alias("_dias_ativos_br")
        ])

        df_med = (
            df.group_by("id_medico")
            .agg([
                pl.sum("vl_total_prescricoes").alias("vl_total_prescricoes"),
                pl.sum("nu_prescricoes").alias("nu_prescricoes"),
                pl.sum("_dias_ativos_loc").alias("_total_dias_loc"),
                pl.sum("_dias_ativos_br").alias("_total_dias_br"),
                pl.sum("prescricoes_total_brasil").alias("prescricoes_total_brasil"),
                # Une as listas de CNPJs de todos os meses do período
                pl.col("lista_cnpjs_brasil").str.concat(",").alias("lista_cnpjs_brasil"),
                pl.max("flag_crm_invalido").alias("flag_crm_invalido"),
                pl.max("flag_prescricao_antes_registro").alias("flag_prescricao_antes_registro"),
                pl.max("flag_concentracao_estabelecimento").alias("flag_concentracao_estabelecimento"),
                pl.max("flag_concentracao_mesmo_crm").cast(pl.Int8).alias("alerta_concentracao_mesmo_crm"),
                pl.max("flag_distancia_geografica").cast(pl.Int8).alias("alerta_distancia_geografica"),
                pl.col("alerta_distancia_geografica").drop_nulls().first().alias("alerta5_geografico"),
                pl.min("dt_primeira_prescricao").alias("dt_primeira_prescricao"),
                pl.col("dt_inscricao_crm").first().alias("dt_inscricao_crm"),
            ])
            .with_columns([
                # Cálculo da Média Real (Volume Total / Total de Dias Ativos no Período)
                pl.when(pl.col("_total_dias_loc") > 0)
                  .then(pl.col("nu_prescricoes").cast(pl.Float64) / pl.col("_total_dias_loc"))
                  .otherwise(pl.lit(0.0))
                  .round(2)
                  .alias("nu_prescricoes_dia"),
                pl.when(pl.col("_total_dias_br") > 0)
                  .then(pl.col("prescricoes_total_brasil").cast(pl.Float64) / pl.col("_total_dias_br"))
                  .otherwise(pl.lit(0.0))
                  .round(2)
                  .alias("prescricoes_dia_total_brasil"),
            ])
            .with_columns([
                # Processa a string concatenada para contar CNPJs únicos
                pl.col("lista_cnpjs_brasil")
                .str.split(",")
                .list.unique()
                .list.len()
                .alias("qtd_estabelecimentos_atua"),
                (pl.col("nu_prescricoes_dia") > 30).cast(pl.Int8).alias("flag_robo"),
                (
                    (pl.col("prescricoes_dia_total_brasil") > 30) & (pl.col("nu_prescricoes_dia") <= 30)
                ).cast(pl.Int8).alias("flag_robo_oculto"),
            ])
            .with_columns([
                (pl.col("qtd_estabelecimentos_atua") == 1).cast(pl.Int8).alias("flag_crm_exclusivo"),
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
                pl.when(pl.col("prescricoes_total_brasil") > 0)
                .then(
                    (pl.col("nu_prescricoes").cast(pl.Float64) /
                     pl.col("prescricoes_total_brasil").cast(pl.Float64) * 100).round(2)
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
            "qtd_prescritores_surto":         int(df_med["flag_concentracao_estabelecimento"].sum() or 0),
            "mediana_concentracao_top5_reg":  round(bench_top5_reg, 2),
            "mediana_concentracao_top5_br":   round(bench_top5_br,  2),
            "razaoSocial":                    razao_social,
            "municipio":                      municipio,
            "uf":                             uf_str,
            "from_cache":                     os.path.exists(PARQUET_PATH),
        }

        # ── 7. Alertas diários — injeta em cada médico ────────────────────────
        ALERTAS_DIARIOS_PATH = os.path.join(cnpj_dir, "concentracao_mesmo_crm.parquet")
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
                        text("SELECT id_medico, competencia, dt_alerta, nivel, nu_prescricoes_dia, nu_minutos_dia, taxa_hora"
                             " FROM temp_CGUSC.fp.alertas_crm_concentracao WHERE cnpj = :cnpj"
                             " ORDER BY dt_alerta, id_medico"),
                        conn,
                        params={"cnpj": cnpj},
                    )
                df_ad = pl.from_pandas(pdf_ad) if not pdf_ad.empty else pl.DataFrame(schema={
                    "id_medico": pl.Utf8, "competencia": pl.Int32, "dt_alerta": pl.Utf8, 
                    "nivel": pl.Utf8, "nu_prescricoes_dia": pl.Int32, 
                    "nu_minutos_dia": pl.Int32, "taxa_hora": pl.Float64
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
                    "nivel":          row["nivel"],
                    "nu_prescricoes": row["nu_prescricoes_dia"],
                    "nu_minutos":     row["nu_minutos_dia"],
                    "taxa_hora":      float(row["taxa_hora"] or 0),
                })

        for m in crms_interesse_list:
            m["alertas_diarios"] = alertas_por_medico.get(m["id_medico"], [])

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

        # ── 7.2 Pré-Sincronização do Raio-X (Transações Horárias) ─────────────
        # Garante que o arquivo _transacoes_horarias.parquet exista para uso offline
        try:
            AnalyticsService.sync_crm_hourly_transactions(cnpj)
        except: pass

        # ── 8. Alertas do Estabelecimento (Cross-CRM) ─────────────────────────
        CNPJ_ALERTS_PATH = os.path.join(cnpj_dir, "concentracao_crm_estabelecimento.parquet")
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
                        text("SELECT * FROM temp_CGUSC.fp.alertas_cnpj_concentracao_sequencial WHERE cnpj = :cnpj"),
                        conn, params={"cnpj": cnpj}
                    )
                df_ca = pl.from_pandas(pdf_ca) if not pdf_ca.empty else pl.DataFrame(schema={
                    "cnpj": pl.Utf8, "competencia": pl.Int32, "dt_alerta": pl.Utf8, 
                    "nu_prescricoes_hr_pico": pl.Int32, "taxa_hora": pl.Float64
                })
                df_ca.write_parquet(CNPJ_ALERTS_PATH, compression="lz4")
            except Exception as e:
                print(f"❌ Erro ao buscar/salvar alertas de surto do banco para {cnpj}: {e}")
                df_ca = pl.DataFrame()

        cnpj_alerts_list = []
        if not df_ca.is_empty():
            if comp_ini:
                df_ca = df_ca.filter(pl.col("competencia").cast(pl.Int32) >= comp_ini)
            if comp_fim:
                df_ca = df_ca.filter(pl.col("competencia").cast(pl.Int32) <= comp_fim)
            
            cnpj_alerts_list = [
                {
                    "dt": str(r["dt_alerta"]),
                    "hr": int(r["hr_janela"]),
                    "nivel": r["nivel"],
                    "descricao": r["descricao"],
                    "nu_prescricoes": int(r["nu_prescricoes"]),
                    "nu_crms": int(r["nu_crms"]),
                    "multiplicador": float(r["multiplicador"] or 0)
                }
                for r in df_ca.sort(["dt_alerta", "hr_janela"]).iter_rows(named=True)
            ]

        # ── 9. Cruzamento: Quais surtos do estabelecimento cada CRM participou? ──
        TX_PARQUET_PATH = os.path.join(cnpj_dir, "transacoes_horarias.parquet")
        alertas_surto_por_medico: dict[str, list[dict]] = {}
        
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
                        df_tx.group_by(["dt_janela", "hr_janela", "crm", "crm_uf"])
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
                            df_ca_clean.select(["dt_alerta", "hr_janela", "nu_prescricoes", "nu_crms", "descricao"]),
                            left_on=["dt_janela", "hr_janela"],
                            right_on=["dt_alerta", "hr_janela"],
                            how="inner"
                        )
                        
                        for r in df_surto_full.iter_rows(named=True):
                            mid = f"{r['crm']}/{r['crm_uf']}"
                            alertas_surto_por_medico.setdefault(mid, []).append({
                                "dt": str(r["dt_janela"]),
                                "hr": int(r["hr_janela"]),
                                "nu_presc_crm": int(r["nu_prescricoes_crm"]),
                                "nu_presc_total": int(r["nu_prescricoes"]),
                                "nu_crms_total": int(r["nu_crms"]),
                                "descricao": r["descricao"]
                            })
            except Exception as e:
                print(f"⚠️ Erro ao processar cruzamento de surtos para {cnpj}: {e}")

        # Atribuição final aos médicos
        for m in crms_interesse_list:
            m["alertas_surto"] = alertas_surto_por_medico.get(m["id_medico"], [])


        return PrescritoresResponse(
            cnpj=cnpj, 
            summary=summary_dict, 
            crms_interesse=crms_interesse_list,
            cnpj_alerts=cnpj_alerts_list
        )

    @staticmethod
    def get_crm_daily_profile(
        cnpj: str,
        data_inicio: str | None = None,
        data_fim: str | None = None
    ) -> "CrmDailyProfileResponse":
        """Retorna o perfil diário de dispensação de um CNPJ (lazy parquet cache).

        Args:
            cnpj: CNPJ de 14 dígitos sem formatação.
            data_inicio: Data de início (YYYY-MM-DD ou YYYY-MM).
            data_fim: Data de fim (YYYY-MM-DD ou YYYY-MM).

        Returns:
            CrmDailyProfileResponse com lista de dias ordenada cronologicamente.
        """
        import pandas as pd

        cnpj_dir = AnalyticsService._get_cnpj_cache_dir(cnpj)
        PARQUET_PATH = os.path.join(cnpj_dir, "dispensacao_diaria.parquet")

        df: pl.DataFrame | None = None
        if os.path.exists(PARQUET_PATH):
            try:
                df = pl.read_parquet(PARQUET_PATH)
            except Exception as e:
                print(f"⚠️ Erro ao ler parquet daily '{cnpj}': {e}")

        if df is None:
            try:
                from database import engine as _engine
                with _engine.connect() as conn:
                    pdf = pd.read_sql(
                        text("SELECT * FROM temp_CGUSC.fp.crm_daily_profile"
                             " WHERE cnpj = :cnpj ORDER BY dt_janela"),
                        conn,
                        params={"cnpj": cnpj},
                    )
                df = pl.from_pandas(pdf)
                df.write_parquet(PARQUET_PATH, compression="lz4")
            except Exception as e:
                print(f"⚠️ Erro ao gerar parquet daily '{cnpj}': {e}")
                df = pl.DataFrame()

        if df.is_empty():
            return CrmDailyProfileResponse(cnpj=cnpj, days=[])

        # --- Filtro de Período ---
        if data_inicio:
            # Garante formato YYYY-MM-DD para comparação
            d_ini = data_inicio if len(data_inicio) == 10 else f"{data_inicio}-01"
            df = df.filter(pl.col("dt_janela").cast(pl.Utf8) >= d_ini)
        if data_fim:
            d_fim = data_fim if len(data_fim) == 10 else f"{data_fim}-31"
            df = df.filter(pl.col("dt_janela").cast(pl.Utf8) <= d_fim)

        if df.is_empty():
            return CrmDailyProfileResponse(cnpj=cnpj, days=[])

        days = [
            {
                "dt_janela":             str(r["dt_janela"])[:10],
                "competencia":           int(r["competencia"]),
                "nu_prescricoes_dia":    int(r["nu_prescricoes_dia"]),
                "nu_crms_distintos":     int(r["nu_crms_distintos"]),
                "mediana_diaria":        float(r["mediana_diaria"]),
                "is_anomalo":            int(r["is_anomalo"]),
            }
            for r in df.iter_rows(named=True)
        ]
        return CrmDailyProfileResponse(cnpj=cnpj, days=days)

    @staticmethod
    def get_crm_hourly_profile(
        cnpj: str,
        data_inicio: str | None = None,
        data_fim: str | None = None
    ) -> CrmHourlyProfileResponse:
        """Retorna o detalhamento horário (0-23h) de todos os dias anômalos do CNPJ com cache Parquet e filtro de período."""
        import pandas as pd
        from sqlalchemy import text
        
        cnpj_dir = AnalyticsService._get_cnpj_cache_dir(cnpj)
        PARQUET_PATH = os.path.join(cnpj_dir, "dispensacao_horaria.parquet")

        df: pl.DataFrame | None = None
        if os.path.exists(PARQUET_PATH):
            try:
                df = pl.read_parquet(PARQUET_PATH)
            except Exception as e:
                print(f"⚠️ Erro ao ler parquet hourly '{cnpj}': {e}")

        if df is None:
            try:
                from database import engine as _engine
                with _engine.connect() as conn:
                    pdf = pd.read_sql(
                        text("SELECT dt_janela, hr_janela, nu_prescricoes, nu_crms_diferentes, mediana_hora, is_anomalo_hora "
                             "FROM temp_CGUSC.fp.crm_hourly_profile_anomalo "
                             "WHERE cnpj = :cnpj "
                             "ORDER BY dt_janela, hr_janela"),
                        conn,
                        params={"cnpj": cnpj},
                    )
                df = pl.from_pandas(pdf)
                df.write_parquet(PARQUET_PATH, compression="lz4")
            except Exception as e:
                print(f"⚠️ Erro ao gerar parquet hourly '{cnpj}': {e}")
                df = pl.DataFrame()

        if df.is_empty():
            return CrmHourlyProfileResponse(cnpj=cnpj, points=[])

        # --- Filtro de Período ---
        if data_inicio:
            d_ini = data_inicio if len(data_inicio) == 10 else f"{data_inicio}-01"
            df = df.filter(pl.col("dt_janela").cast(pl.Utf8) >= d_ini)
        if data_fim:
            d_fim = data_fim if len(data_fim) == 10 else f"{data_fim}-31"
            df = df.filter(pl.col("dt_janela").cast(pl.Utf8) <= d_fim)

        if df.is_empty():
            return CrmHourlyProfileResponse(cnpj=cnpj, points=[])

        points = [
            {
                "dt_janela":              str(r["dt_janela"])[:10],
                "hr_janela":              int(r["hr_janela"]),
                "nu_prescricoes":         int(r["nu_prescricoes"]),
                "nu_crms_diferentes":     int(r["nu_crms_diferentes"]),
                "mediana_hora":           float(r["mediana_hora"]),
                "is_anomalo_hora":        int(r.get("is_anomalo_hora", 0)),
            }
            for r in df.iter_rows(named=True)
        ]

        # AUTO-WARMING: Pré-aquece o parquet de Transações Literais (Raio-X)
        # Isso garante que o cache de drill-down esteja pronto antes mesmo do auditor clicar
        AnalyticsService.sync_crm_hourly_transactions(cnpj)

        return CrmHourlyProfileResponse(cnpj=cnpj, points=points, from_cache=os.path.exists(PARQUET_PATH))

    @staticmethod
    def sync_crm_hourly_transactions(cnpj: str) -> None:
        """Sincroniza o cache parquet de transações literais (Raio-X) para um CNPJ."""
        import pandas as pd
        import polars as pl
        from sqlalchemy import text
        from database import engine as _engine
        
        cnpj_dir = AnalyticsService._get_cnpj_cache_dir(cnpj)
        TX_PARQUET_PATH = os.path.join(cnpj_dir, "transacoes_horarias.parquet")

        if os.path.exists(TX_PARQUET_PATH):
            try:
                header = pl.scan_parquet(TX_PARQUET_PATH).limit(0).collect()
                if "codigo_barra" in header.columns and len(header.columns) > 5:
                    return
            except Exception: pass

        try:
            print(f"🗄️ [SYNC] Buscando transações no banco para {cnpj}...")
            with _engine.connect() as conn:
                pdf_tx = pd.read_sql(
                    text("SELECT dt_janela, hr_janela, data_hora, num_autorizacao, crm, crm_uf, codigo_barra, valor_pago "
                         "FROM temp_CGUSC.fp.alertas_cnpj_concentracao_sequencial_detalhe "
                         "WHERE cnpj = :cnpj "
                         "ORDER BY data_hora ASC, num_autorizacao ASC"),
                    conn, params={"cnpj": cnpj}
                )
            df_tx = pl.from_pandas(pdf_tx) if not pdf_tx.empty else pl.DataFrame(schema={
                "dt_janela": pl.Utf8, "hr_janela": pl.Int32, "data_hora": pl.Utf8, 
                "num_autorizacao": pl.Utf8, "crm": pl.Utf8, "crm_uf": pl.Utf8, 
                "codigo_barra": pl.Utf8, "valor_pago": pl.Float64
            })

            if not df_tx.is_empty():
                df_tx = df_tx.with_columns([
                    pl.col("num_autorizacao").cast(pl.Utf8),
                    pl.col("crm").cast(pl.Utf8),
                    pl.col("codigo_barra").cast(pl.Utf8),
                    pl.col("data_hora").cast(pl.Utf8)
                ])
            
            df_tx.write_parquet(TX_PARQUET_PATH, compression="lz4")
        except Exception as e:
            if "IM002" in str(e) or "connection" in str(e).lower():
                print(f"ℹ️  Modo Offline: Cache de transações para {cnpj} não encontrado.")
            else:
                print(f"⚠️ Erro ao sincronizar parquet de transações horárias '{cnpj}': {e}")

    @staticmethod
    def get_crm_hourly_transactions(cnpj: str, date_str: str, hour: Optional[int] = None) -> "CrmHourlyTransactionsResponse":
        """Busca as transações literais e sequenciais de uma hora anômala, utilizando cache Parquet."""
        import pandas as pd
        import polars as pl
        from sqlalchemy import text
        from database import engine as _engine
        from api.schemas.analytics import CrmHourlyTransactionsResponse
        
        cnpj_dir = AnalyticsService._get_cnpj_cache_dir(cnpj)
        PARQUET_PATH = os.path.join(cnpj_dir, "transacoes_horarias.parquet")

        df = pl.DataFrame()
        if not os.path.exists(PARQUET_PATH):
            AnalyticsService.sync_crm_hourly_transactions(cnpj)

        if os.path.exists(PARQUET_PATH):
            try:
                df = pl.read_parquet(PARQUET_PATH)
            except Exception as e:
                print(f"⚠️ Erro ao ler parquet hourly_tx '{cnpj}': {e}")

        if df.is_empty():
            return CrmHourlyTransactionsResponse(transactions=[])

        # O Filtro Rápido do Polars na memória (por Dia e Hora opcional)
        filter_expr = pl.col("dt_janela").cast(pl.Utf8).str.slice(0, 10) == date_str
        if hour is not None:
            filter_expr = filter_expr & (pl.col("hr_janela") == hour)

        filtered_df = df.filter(filter_expr)

        if filtered_df.is_empty():
            return CrmHourlyTransactionsResponse(transactions=[])

        # Join com o cache de medicamentos para trazer nomes e princípios ativos
        from data_cache import get_medicamentos_df
        try:
            df_med = get_medicamentos_df()
            # Selecionamos apenas as colunas necessárias para o join
            df_med_subset = df_med.select(["codigo_barra", "produto", "principio_ativo"])
            enriched_df = filtered_df.join(df_med_subset, on="codigo_barra", how="left")
        except Exception as e:
            print(f"⚠️ Erro ao cruzar com cadastro de medicamentos no Raio-X: {e}")
            enriched_df = filtered_df.with_columns([
                pl.lit(None).alias("produto"),
                pl.lit(None).alias("principio_ativo")
            ])

        # Garante que os campos que o Pydantic espera como String sejam de fato Strings
        # (SQL e Parquet frequentemente inferem tipos numéricos para IDs longos)
        enriched_df = enriched_df.with_columns([
            pl.col("num_autorizacao").cast(pl.Utf8),
            pl.col("crm").cast(pl.Utf8),
            pl.col("codigo_barra").cast(pl.Utf8),
            pl.col("data_hora").cast(pl.Utf8) # Conversão direta para string no Polars é mais eficiente
        ])

        # Converte para o formato do Schema
        transactions = enriched_df.to_dicts()
        
        return CrmHourlyTransactionsResponse(transactions=transactions)

    @staticmethod
    def get_dados_farmacia(cnpj: str) -> DadosFarmaciaSchema:
        """Retorna os dados cadastrais e geográficos de uma farmácia específica."""
        try:
            from data_cache import get_df_dados_farmacia
            df = get_df_dados_farmacia()
            rows = df.filter(pl.col("cnpj") == cnpj)
            if rows.is_empty():
                return DadosFarmaciaSchema(cnpj=cnpj)
            return DadosFarmaciaSchema(**rows.row(0, named=True))
        except Exception as e:
            print(f"⚠️ Erro ao buscar dados cadastrais da farmácia {cnpj}: {e}")
            return DadosFarmaciaSchema(cnpj=cnpj)

    @staticmethod
    def get_movimentacao_data(cnpj: str, engine, check_cache: bool = False) -> MovimentacaoResponse:
        """
        Retorna a memória de cálculo processada (Movimentação por GTIN) de um CNPJ.
        Estratégia de cache em 2 camadas.
        """
        import traceback
        from pathlib import Path
        from data_cache import get_cache_dir
        
        cnpj_dir = AnalyticsService._get_cnpj_cache_dir(cnpj)
        CACHE_PATH = os.path.join(cnpj_dir, "movimentacao_detalhada.parquet")

        empty_summary = MovimentacaoSummarySchema()

        def _build_response_from_df(df: pl.DataFrame, from_cache: bool) -> MovimentacaoResponse:
            """Converte DataFrame Polars para o schema de resposta."""
            rows = [
                MovimentacaoRowSchema(
                    tipo_linha=r["tipo_linha"],
                    gtin=r.get("gtin"),
                    medicamento=r.get("medicamento"),
                    periodo_inicial=r.get("periodo_inicial"),
                    periodo_inicio_irregular=r.get("periodo_inicio_irregular"),
                    periodo_final=r.get("periodo_final"),
                    estoque_inicial=int(r["estoque_inicial"]) if r.get("estoque_inicial") is not None else None,
                    estoque_final=int(r["estoque_final"]) if r.get("estoque_final") is not None else None,
                    vendas=int(r["vendas"]) if r.get("vendas") is not None else None,
                    vendas_irregular=int(r["vendas_irregular"]) if r.get("vendas_irregular") is not None else None,
                    valor=float(r["valor"]) if r.get("valor") is not None else None,
                    valor_irregular=float(r["valor_irregular"]) if r.get("valor_irregular") is not None else None,
                    notas=r.get("notas"),
                )
                for r in df.iter_rows(named=True)
            ]

            # Calcula totalizadores a partir das linhas de venda
            vendas_rows = [r for r in rows if r.tipo_linha in ("venda_normal", "venda_irregular")]
            tv  = sum(r.vendas or 0 for r in vendas_rows)
            tvi = sum(r.vendas_irregular or 0 for r in vendas_rows)
            vv  = sum(r.valor or 0.0 for r in vendas_rows)
            vvi = sum(r.valor_irregular or 0.0 for r in vendas_rows)
            pct = (vvi / vv * 100) if vv else 0.0

            return MovimentacaoResponse(
                cnpj=cnpj,
                summary=MovimentacaoSummarySchema(
                    total_vendas=tv,
                    total_vendas_irregular=tvi,
                    valor_total=round(vv, 2),
                    valor_irregular=round(vvi, 2),
                    pct_irregular=round(pct, 2),
                    from_cache=from_cache,
                ),
                rows=rows,
            )

        # ── 1. Tenta carregar do cache Parquet ─────────────────────────────
        if os.path.exists(CACHE_PATH):
            try:
                df_cached = pl.read_parquet(CACHE_PATH)
                return _build_response_from_df(df_cached, from_cache=True)
            except Exception as e:
                import traceback
                print(f"⚠️ Erro ao ler Parquet '{cnpj}': {e}")

        # ── 1b. Se for apenas check_cache e não existia/corrompeu, retorna vazio
        if check_cache:
            return MovimentacaoResponse(cnpj=cnpj, summary=MovimentacaoSummarySchema(), rows=[])

        # ── 2. Busca e processa a memória de cálculo do SQL Server ─────────
        try:
            from sqlalchemy.exc import InterfaceError as SQLAInterfaceError
            with engine.connect() as conn:
                # 2a. Busca dados comprimidos
                result = conn.execute(text("""
                    SELECT TOP 1 dados_comprimidos, id_processamento
                    FROM temp_CGUSC.fp.memoria_calculo_consolidada
                    WHERE cnpj = :cnpj
                    ORDER BY id_processamento DESC
                """), {"cnpj": cnpj}).fetchone()

                if not result or not result[0]:
                    print(f"⚠️ Nenhum dado no banco para CNPJ {cnpj}")
                    return MovimentacaoResponse(cnpj=cnpj, summary=empty_summary, rows=[])

                dados_comprimidos = result[0]

                # 2b. Busca nomes dos princípios ativos (GTIN → Nome)
                med_rows = conn.execute(text("""
                    SELECT codigo_barra, principio_ativo
                    FROM temp_CGUSC.fp.medicamentos_patologia
                """)).fetchall()
                medicamentos_map = {float(r[0]): r[1] for r in med_rows if r[0]}

            # 2c. Descompacta e desserializa
            json_str = zlib.decompress(dados_comprimidos).decode("utf-8")
            dados = json.loads(json_str)

            # 2d. Converte dates e Decimals
            for item in dados:
                for key in ["periodo_inicial", "periodo_final", "periodo_inicial_nao_comprovacao",
                            "data_aquis_dev_estoq", "data_estoque_inicial", "data_aquisicao", "data_devolucao"]:
                    if key in item and item[key] and isinstance(item[key], str):
                        try:
                            from datetime import datetime as _dt
                            if "T" in item[key]:
                                item[key] = _dt.fromisoformat(item[key]).date()
                            else:
                                item[key] = _dt.strptime(item[key], "%Y-%m-%d").date()
                        except: pass
                
                # Formata campos decimais
                for key in ["valor_movimentado", "valor_sem_comprovacao"]:
                    if key in item and item[key] is not None:
                        from decimal import Decimal
                        item[key] = Decimal(str(item[key]))
        
        except (SQLAInterfaceError, Exception) as e:
            msg = str(e)
            if "IM002" in msg or "ODBC" in msg or "InterfaceError" in msg:
                print(f"❌ [INFO] Driver ODBC não disponível. Consulta 'live' ignorada.")
                return MovimentacaoResponse(
                    cnpj=cnpj, summary=empty_summary, rows=[],
                    error="Arquivo Parquet local não encontrado e Driver ODBC ausente."
                )
            
            print(f"❌ ERRO ao buscar movimentação para {cnpj}: {e}")
            print(traceback.format_exc())
            raise HTTPException(
                status_code=503,
                detail="Erro interno ao processar dados de movimentação. Verifique os logs do servidor."
            )

        # ── 3. Processa linhas (lógica espelhada de gerar_relatorio.py) ──────
        results = copy.deepcopy(dados)

        # Passo A: Enriquece vendas com lista de NFs (campo 'notas')
        contador = 0
        for i, j in enumerate(results):
            if j["tipo"] in ("c", "d"):
                contador += 1
            if j["tipo"] in ("s", "h"):
                contador = 0
            if j["tipo"] == "v":
                lista_nfs = []
                for idx in range(1, contador + 1):
                    item_ant = results[i - idx]
                    if item_ant["tipo"] == "c":
                        dt = item_ant["data_aquis_dev_estoq"].strftime("%d/%m/%Y") if item_ant.get("data_aquis_dev_estoq") else ""
                        qtd = int(item_ant["qnt_aquis_dev"]) if item_ant.get("qnt_aquis_dev") else 0
                        lista_nfs.append(f"NF Aquisição: {item_ant.get('numero_nfe', '')} - {dt} | Qtde: {qtd}")
                    elif item_ant["tipo"] == "d":
                        dt = item_ant["data_aquis_dev_estoq"].strftime("%d/%m/%Y") if item_ant.get("data_aquis_dev_estoq") else ""
                        qtd = int(item_ant["qnt_aquis_dev"]) if item_ant.get("qnt_aquis_dev") else 0
                        lista_nfs.append(f"NF Transferência: {item_ant.get('numero_nfe', '')} - {dt} | Qtde: {qtd}")
                    elif item_ant["tipo"] == "e":
                        est = int(item_ant.get("estoque_inicial", 0))
                        lista_nfs.append(f"Estoque Inicial Estimado: {est} - 01/07/2015")
                if not lista_nfs:
                    for idx in range(i - 1, -1, -1):
                        if results[idx]["tipo"] == "e":
                            est = int(results[idx].get("estoque_inicial", 0))
                            lista_nfs.append(f"Estoque Inicial Estimado: {est} - 01/07/2015")
                            break
                        elif results[idx]["tipo"] == "h":
                            break
                results[i]["notas"] = "; ".join(lista_nfs)
                contador = 0

        # Passo B: Estrutura linhas tipadas (tipo_linha)
        _FMT_DATE = lambda d: d.strftime("%d/%m/%Y") if d else "-"

        lista_linhas: list[dict] = []
        lista_parcial: list[dict] = []
        numero_vendas_gtin = 0
        ultimo_estoque_valido = 0
        gtin_atual: str | None = None
        medicamento_atual: str | None = None

        for i, j in enumerate(results):
            tipo = j["tipo"]

            if tipo == "h":
                numero_vendas_gtin = 0
                cod = int(j["codigo_barra"])
                gtin_atual = str(cod)
                principio = medicamentos_map.get(float(cod), "DESCONHECIDO")
                medicamento_atual = principio
                est = j.get("estoque_inicial", 0) or 0
                ultimo_estoque_valido = est

                lista_parcial.append({
                    "tipo_linha": "header_medicamento",
                    "gtin": gtin_atual,
                    "medicamento": f"{medicamento_atual} (Estoque Inicial: {int(est)} un.)",
                })
                lista_parcial.append({"tipo_linha": "header_colunas"})

            elif tipo == "e":
                ultimo_estoque_valido = j.get("estoque_inicial", 0) or 0

            elif tipo == "v":
                ultimo_estoque_valido = j.get("estoque_final", 0) or 0
                tem_irregular = (j.get("valor_sem_comprovacao") or Decimal(0)) > 0
                numero_vendas_gtin += 1

                dt_nc = j.get("periodo_inicial_nao_comprovacao")
                dt_nc_fmt = "-" if (dt_nc is None or str(dt_nc) == "9999-01-01") else _FMT_DATE(dt_nc)

                lista_parcial.append({
                    "tipo_linha": "venda_irregular" if tem_irregular else "venda_normal",
                    "gtin": gtin_atual,
                    "medicamento": medicamento_atual,
                    "periodo_inicial": _FMT_DATE(j.get("periodo_inicial")),
                    "periodo_inicio_irregular": dt_nc_fmt,
                    "periodo_final": _FMT_DATE(j.get("periodo_final")),
                    "estoque_inicial": int(j.get("estoque_inicial") or 0),
                    "estoque_final": int(j.get("estoque_final") or 0),
                    "vendas": int(j.get("vendas_periodo") or 0),
                    "vendas_irregular": int(j.get("vendas_sem_comprovacao") or 0),
                    "valor": float(Decimal(str(j.get("valor_movimentado") or 0)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)),
                    "valor_irregular": float(Decimal(str(j.get("valor_sem_comprovacao") or 0)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)),
                    "notas": j.get("notas", ""),
                })

            elif tipo in ("c", "d"):
                ultimo_estoque_valido = j.get("estoque_final", 0) or 0

            elif tipo == "s":
                # Resumo Parcial do GTIN — só inclui o GTIN se tiver ao menos 1 venda
                estoque_visual = int(ultimo_estoque_valido)
                for item_rev in reversed(lista_parcial):
                    if item_rev.get("estoque_final") is not None:
                        estoque_visual = item_rev["estoque_final"]
                        break

                lista_parcial.append({
                    "tipo_linha": "resumo_parcial",
                    "gtin": gtin_atual,
                    "medicamento": medicamento_atual,
                    "periodo_inicial": "Resumo Parcial",
                    "estoque_final": estoque_visual,
                    "vendas": int(j.get("vendas_periodo") or 0),
                    "vendas_irregular": int(j.get("vendas_sem_comprovacao") or 0),
                    "valor": float(Decimal(str(j.get("valor_movimentado") or 0)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)),
                    "valor_irregular": float(Decimal(str(j.get("valor_sem_comprovacao") or 0)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)),
                })

                if numero_vendas_gtin > 0:
                    lista_linhas.extend(copy.deepcopy(lista_parcial))

                lista_parcial.clear()
                numero_vendas_gtin = 0

        # ── 4. Converte para Polars e salva Parquet ───────────────────────
        SCHEMA_COLS = [
            "tipo_linha", "gtin", "medicamento",
            "periodo_inicial", "periodo_inicio_irregular", "periodo_final",
            "estoque_inicial", "estoque_final",
            "vendas", "vendas_irregular",
            "valor", "valor_irregular",
            "notas",
        ]

        # Garante que todas as colunas estejam presentes em cada dict
        for row in lista_linhas:
            for col in SCHEMA_COLS:
                row.setdefault(col, None)

        if lista_linhas:
            # Cria o DataFrame com todas as colunas como Utf8 (safe),
            # então faz cast explícito das colunas numéricas.
            # Isso evita erros de schema em linhas de cabeçalho que têm None
            # misturado com int/float nas linhas de venda.
            try:
                df_result = (
                    pl.DataFrame(lista_linhas)
                    .select(SCHEMA_COLS)
                    .with_columns([
                        pl.col("estoque_inicial").cast(pl.Int64, strict=False),
                        pl.col("estoque_final").cast(pl.Int64, strict=False),
                        pl.col("vendas").cast(pl.Int64, strict=False),
                        pl.col("vendas_irregular").cast(pl.Int64, strict=False),
                        pl.col("valor").cast(pl.Float64, strict=False),
                        pl.col("valor_irregular").cast(pl.Float64, strict=False),
                    ])
                )
                df_result.write_parquet(CACHE_PATH, compression="lz4")
                print(f"✅ Cache Parquet salvo: {CACHE_PATH}")
            except Exception as e:
                print(f"⚠️ Erro ao criar/salvar Parquet para {cnpj}: {e}")
                print(traceback.format_exc())
                # Fallback sem persistir: entrega os dados sem cache
                try:
                    df_result = pl.DataFrame(lista_linhas).select(SCHEMA_COLS)
                except Exception:
                    df_result = pl.DataFrame([])
        else:
            df_result = pl.DataFrame([])

        return _build_response_from_df(df_result, from_cache=False)


    @staticmethod
    def get_metric_percentiles(scope: str, uf: str = None, regiao_id: str = None, metric: str = 'score', data_inicio: date = None, data_fim: date = None) -> list[dict]:
        """
        Calcula a curva de percentis de score ou percentual de não comprovação (1% a 100%) para diferentes escopos.
        """
        try:
            # Se houver data e for percentual, calculamos do zero para ser dinâmico
            if (data_inicio or data_fim) and metric == "percentual_sem_comprovacao":
                df_base = get_df()
                MIN_DATA = date(2015, 7, 1)
                MAX_DATA = date(2024, 12, 31)
                inicio = (data_inicio if data_inicio and data_inicio >= MIN_DATA else MIN_DATA) if data_inicio else MIN_DATA
                fim = data_fim if data_fim else MAX_DATA
                
                mask = pl.col("periodo").is_between(inicio, fim)
                
                # Agrega por CNPJ primeiro
                df_agg = (
                    df_base.filter(mask)
                    .group_by("cnpj")
                    .agg([
                        pl.col("uf").first().alias("uf"),
                        pl.col("no_municipio").first().alias("no_municipio"),
                        pl.sum("total_vendas").alias("tv"),
                        pl.sum("total_sem_comprovacao").alias("tsc")
                    ])
                    .with_columns([
                        (pl.col("tsc") / pl.when(pl.col("tv") > 0).then(pl.col("tv")).otherwise(pl.lit(1.0)) * 100).alias("pct_auditado")
                    ])
                )
                
                # Injeta id_regiao_saude via join com localidades para suportar o filtro de escopo
                try:
                    df_loc = get_localidades_df().select(["no_municipio", "sg_uf", "id_regiao_saude"]).unique(subset=["no_municipio", "sg_uf"])
                    df_agg = df_agg.join(
                        df_loc,
                        left_on=["no_municipio", "uf"],
                        right_on=["no_municipio", "sg_uf"],
                        how="left"
                    )
                except Exception as e:
                    print(f"⚠️ Erro ao cruzar regiões em percentis: {e}")
                
                df = df_agg
            else:
                # Caso contrário, usa a matriz consolidada (mais rápido)
                from data_cache import get_df_matriz_risco
                df = get_df_matriz_risco()
                df = df.rename({c: c.lower() for c in df.columns})

            # Mapeamento de colunas conforme o schema real do cache
            col_target = "score_risco_final"
            if metric == "percentual_sem_comprovacao":
                col_target = "pct_auditado"

            # ── 1. Aplica o Filtro de Escopo ──────────────────────────────────
            df_scoped = df
            if scope == 'uf' and uf:
                df_scoped = df.filter(pl.col("uf") == uf)
            elif scope == 'regiao' and regiao_id:
                # Usa o ID da região de saúde (mais preciso que o nome)
                df_scoped = df.filter(pl.col("id_regiao_saude").cast(pl.Utf8) == str(regiao_id))
            elif scope == 'brasil':
                df_scoped = df  # Sem filtro
            
            if df_scoped.is_empty():
                return []

            # ── 2. Calcula 100 percentis (0.01 a 1.0) ─────────────────────────
            percentis_list = [i / 100.0 for i in range(1, 101)]
            
            # Seleciona a coluna correta baseada no metric selecionado
            # Se for percentual, limitamos a 100 para evitar que o eixo Y estique para outliers (ex: 713)
            # Usando uma expressão de clipping do polars para segurança máxima
            if metric == "percentual_sem_comprovacao":
                series_target = df_scoped.select(
                    pl.when(pl.col(col_target) > 100).then(100).otherwise(pl.col(col_target)).alias("val")
                ).to_series().sort()
            else:
                series_target = df_scoped.select(pl.col(col_target)).to_series().sort()
            
            res = []
            for p in percentis_list:
                val = series_target.quantile(p)
                res.append({
                    "percentile": int(p * 100),
                    "score": float(val or 0.0)
                })

            return res
            
        except Exception as e:
            print(f"⚠️ Erro ao calcular percentis de score: {e}")
            return []

    @staticmethod
    def get_metric_percentiles_animation(
        scope: str,
        uf: str = None,
        regiao_id: str = None,
        metric: str = 'score',
        data_inicio: date = None,
        data_fim: date = None,
    ) -> dict:
        """
        Retorna os percentis de métrica para cada janela de 2 meses no período.

        Usado pela animação da curva de risco — evita N round-trips HTTP.
        A janela de 2 meses coincide com PLAY_STEP=2 do slider de animação no frontend.

        Args:
            scope: Escopo geográfico ('brasil', 'uf', 'regiao').
            uf: Sigla do estado (obrigatório para scope 'uf' ou 'regiao').
            regiao_id: ID da região de saúde (obrigatório para scope 'regiao').
            metric: Métrica ('score' ou 'percentual_sem_comprovacao').
            data_inicio: Início do período total.
            data_fim: Fim do período total.

        Returns:
            Dict com lista de quarters, cada um contendo inicio, fim e percentiles.
        """
        MIN_DATA = date(2015, 7, 1)
        MAX_DATA = date(2024, 12, 31)
        inicio = (data_inicio if data_inicio and data_inicio >= MIN_DATA else MIN_DATA) if data_inicio else MIN_DATA
        fim    = data_fim if data_fim else MAX_DATA

        def _add_months(d: date, n: int) -> date:
            m = d.month - 1 + n
            return date(d.year + m // 12, m % 12 + 1, 1)

        def _end_of_month(d: date) -> date:
            last_day = calendar.monthrange(d.year, d.month)[1]
            return date(d.year, d.month, last_day)

        quarters = []
        cursor = inicio
        while cursor <= fim:
            window_start = cursor
            window_end   = min(_end_of_month(_add_months(cursor, 1)), fim)

            percentiles = AnalyticsService.get_metric_percentiles(
                scope, uf, regiao_id, metric, window_start, window_end
            )
            quarters.append({
                "inicio":      window_start,
                "fim":         window_end,
                "percentiles": percentiles,
            })
            cursor = _add_months(cursor, 2)

        return {"quarters": quarters}

    @staticmethod
    def get_cnpj_lookup() -> list[dict]:
        """Retorna lista slim de {cnpj, razao_social, municipio, uf} para autocomplete no frontend.
        Usa get_rede_df() — DataFrame leve de cadastro, sem dados temporais."""
        try:
            df = get_rede_df()
            return (
                df.select(["cnpj", "razao_social", "municipio", "uf"])
                .unique(subset=["cnpj"])
                .sort("razao_social", nulls_last=True)
                .to_dicts()
            )
        except Exception as e:
            print(f"⚠️ Erro ao buscar lookup de CNPJs: {e}")
            return []
