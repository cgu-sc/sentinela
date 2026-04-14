from typing import List
from datetime import date
import polars as pl
from sqlalchemy.orm import Session
from sqlalchemy import text
from fastapi import HTTPException
import os
import zlib
import json
import copy
from decimal import Decimal, ROUND_HALF_UP
from data_cache import get_df, get_rede_df, get_localidades_df, get_df_matriz_risco, get_df_falecidos, get_df_crms_detalhado, get_df_top20_crms
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
    PrescritoresResponse,
    DadosFarmaciaSchema,
    MovimentacaoRowSchema,
    MovimentacaoSummarySchema,
    MovimentacaoResponse,
    IndicadorKpiSummarySchema,
    IndicadorCnpjRowSchema,
    IndicadorMunicipioRowSchema,
    IndicadorAnaliseResponse,
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
    'pacientes_unicos':      ('pct_pacientes_unicos',      'med_pacientes_unicos_reg',     'med_pacientes_unicos_uf',     'med_pacientes_unicos_br',     'risco_pacientes_unicos_reg',     'risco_pacientes_unicos_uf',     'risco_pacientes_unicos_br'),
    'hhi_crm':               ('val_hhi_crm',               'avg_hhi_crm_reg',              'avg_hhi_crm_uf',              'avg_hhi_crm_br',              'risco_crm_reg',                  'risco_crm_uf',                  'risco_crm_br'),
    'exclusividade_crm':     ('pct_exclusividade_crm',     'med_exclusividade_crm_reg',    'med_exclusividade_crm_uf',    'med_exclusividade_crm_br',    'risco_exclusividade_crm_reg',    'risco_exclusividade_crm_uf',    'risco_exclusividade_crm_br'),
    'crms_irregulares':      ('pct_crms_irregulares',      'med_crms_irregulares_reg',     'med_crms_irregulares_uf',     'med_crms_irregulares_br',     'risco_crms_irregulares_reg',     'risco_crms_irregulares_uf',     'risco_crms_irregulares_br'),
}

# Caminho para persistência de configurações customizadas
CONFIG_FILE = "data/thresholds_config.json"

# Limiares de risco por indicador (ratio = valor_farmacia / mediana_regional).
# Cada indicador possui sua própria entrada. Espelha riskConfig.js → INDICATOR_THRESHOLDS.
_INDICATOR_THRESHOLDS: dict[str, tuple[float, float]] = {
    # 1. Auditoria Financeira
    'percentual_nao_comprovacao':   (2.0, 4.0),
    # 2. Elegibilidade & Clínica
    'falecidos':                    (2.0, 3.0),
    'incompatibilidade_patologica': (2.0, 3.0),
    # 3. Padrões de Quantidade
    'teto':                   (1.2, 1.39),
    'polimedicamento':        (2.0, 3.0),
    # 4. Padrões Financeiros
    'ticket_medio':                (2.0, 3.0),
    'receita_paciente':       (2.0, 3.0),
    'per_capita':             (2.0, 3.0),
    'alto_custo':             (1.4, 1.7),
    # 5. Automação & Geografia
    'vendas_rapidas':         (2.0, 3.0),
    'volume_atipico':         (2.0, 3.0),
    'recorrencia_sistemica':  (1.4, 1.7),
    'dias_pico':                   (1.4, 1.7),
    'dispersao_geografica':        (2.0, 3.0),
    'pacientes_unicos':       (1.4, 1.7),
    # 6. Integridade Médica
    'hhi_crm':                (2.0, 3.0),
    'exclusividade_crm':      (2.0, 3.0),
    'crms_irregulares':       (2.0, 3.0),
}

# Tenta carregar configurações customizadas do disco
if os.path.exists(CONFIG_FILE):
    try:
        with open(CONFIG_FILE, "r", encoding="utf-8") as f:
            custom = json.load(f)
            # Converte as listas do JSON de volta para tuplas de floats
            for k, v in custom.items():
                if isinstance(v, list) and len(v) == 2:
                    _INDICATOR_THRESHOLDS[k] = (float(v[0]), float(v[1]))
        print(f"✅ Configurações de limiares carregadas do disco: {CONFIG_FILE}")
    except Exception as e:
        print(f"⚠️ Erro ao carregar {CONFIG_FILE}: {e}")

class AnalyticsService:
    @staticmethod
    def get_config_thresholds():
        """Retorna o dicionário mestre de limiares (Source of Truth)."""
        return _INDICATOR_THRESHOLDS

    @staticmethod
    def save_config_thresholds(edited_data: dict):
        """Salva novos limiares na memória e no disco."""
        global _INDICATOR_THRESHOLDS
        
        # 1. Atualiza memória
        for k, v in edited_data.items():
            if isinstance(v, dict) and 'atencao' in v and 'critico' in v:
                _INDICATOR_THRESHOLDS[k] = (float(v['atencao']), float(v['critico']))

        # 2. Persiste no disco
        try:
            os.makedirs(os.path.dirname(CONFIG_FILE), exist_ok=True)
            with open(CONFIG_FILE, "w", encoding="utf-8") as f:
                # Salva como lista simples para ser compatível com JSON
                json.dump(_INDICATOR_THRESHOLDS, f, indent=4)
            return True
        except Exception as e:
            print(f"❌ Erro ao salvar configurações no disco: {e}")
            return False

    @staticmethod
    def get_dashboard_data(db: Session, data_inicio=None, data_fim=None, perc_min=None, perc_max=None, val_min=None, uf=None, regiao_saude=None, municipio=None, situacao_rf=None, conexao_ms=None, porte_empresa=None, grande_rede=None, cnpj_raiz=None, unidade_pf=None) -> AnalyticsResponse:
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
    def get_evolucao_financeira(cnpj: str) -> EvolucaoFinanceiraResponse:
        """
        Retorna a série semestral de valores (total, regular, irregular) para um CNPJ.
        Fonte: DataFrame Polars em memória (movimentacao_mensal_cnpj).
        """
        try:
            df = get_df()
            cnpj_df = df.filter(pl.col("cnpj") == cnpj).select(["periodo", "total_vendas", "total_sem_comprovacao"])

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

            # Agrega por (ano, sem_num) e formata o rótulo depois
            agg = (
                cnpj_df
                .group_by(["ano", "sem_num"])
                .agg([
                    pl.sum("total_vendas").alias("total"),
                    pl.sum("total_sem_comprovacao").alias("irregular"),
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

            semestres = [
                EvolucaoSemestreSchema(
                    semestre=r["semestre"],
                    total=round(r["total"], 2),
                    regular=round(r["regular"], 2),
                    irregular=round(r["irregular"], 2),
                    pct_irregular=r["pct_irregular"],
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
            atencao, critico = _INDICATOR_THRESHOLDS[indicador]

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
            risco_cols = ["cnpj", c_val, c_mr, c_rr]
            score_col = "score_risco_final"
            if score_col in df_risco.columns:
                risco_cols.append(score_col)
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

            # ── 5. Calcula status (CRÍTICO / ATENÇÃO / NORMAL / SEM DADOS) ──
            rr_col = c_rr if c_rr in df_joined.columns else None
            if rr_col:
                df_joined = df_joined.with_columns([
                    pl.when(pl.col(rr_col).is_null())
                      .then(pl.lit("SEM DADOS"))
                      .when(pl.col(rr_col) >= critico)
                      .then(pl.lit("CRÍTICO"))
                      .when(pl.col(rr_col) >= atencao)
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
                limiar_atencao=float(atencao),
                limiar_critico=float(critico)
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
    def get_falecidos_data(cnpj: str) -> FalecidosResponse:
        """
        Retorna os dados detalhados de vendas para falecidos para um CNPJ.
        Utiliza motor Polars para calcular KPIs e ranking Multi-CNPJ em tempo real.
        """
        try:
            df_all = get_df_falecidos()
            df_target = df_all.filter(pl.col("cnpj") == cnpj)

            if df_target.is_empty():
                return FalecidosResponse(
                    cnpj=cnpj,
                    summary=FalecidosSummarySchema(
                        cpfs_distintos=0, total_autorizacoes=0, valor_total=0.0,
                        media_dias=0.0, max_dias=0, pct_faturamento=0.0,
                        cpfs_multi_cnpj=0, pct_multi_cnpj=0.0
                    ),
                    ranking=[],
                    transacoes=[]
                )

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
                    pct_multi_cnpj=pct_multi_cnpj
                ),
                ranking=ranking,
                transacoes=transacoes
            )

        except Exception as e:
            import traceback
            print(f"❌ ERRO AO CALCULAR DADOS DE FALECIDOS: {e}")
            print(traceback.format_exc())
            return FalecidosResponse(
                cnpj=cnpj,
                summary=FalecidosSummarySchema(
                    cpfs_distintos=0, total_autorizacoes=0, valor_total=0.0,
                    media_dias=0.0, max_dias=0, pct_faturamento=0.0,
                    cpfs_multi_cnpj=0, pct_multi_cnpj=0.0
                ),
                ranking=[],
                transacoes=[]
            )

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
            df_all = get_df_falecidos()
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
    def get_fator_risco_data(db: Session, data_inicio=None, data_fim=None, perc_min=None, perc_max=None, val_min=None, uf=None, regiao_saude=None, municipio=None, situacao_rf=None, conexao_ms=None, porte_empresa=None, grande_rede=None, cnpj_raiz=None, unidade_pf=None) -> FatorRiscoResponseSchema:
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
    def get_regional_data(regiao_saude: str, uf: str = None) -> RegionalResponse:
        """
        Constrói o payload completo da aba 'Região de Saúde'.

        Args:
            regiao_saude: Nome da Região de Saúde (filtro da sidebar, ex: 'GRANDE FLORIANOPOLIS').
            uf: Sigla do estado (ex: 'SC'). Evita mistura se o mesmo nome existir em outro estado.

        Returns:
            RegionalResponse com resumo de municípios e ranking de farmácias.
        """
        try:
            df_mov   = get_df()
            df_loc   = get_localidades_df()
            df_risco = get_df_matriz_risco()
            df_risco = df_risco.rename({c: c.lower() for c in df_risco.columns})

            # ── Filtra movimentação para a região ───────────────────────────────
            mask = (pl.col("no_regiao_saude") == regiao_saude)
            if uf and uf != 'Todos':
                mask = mask & (pl.col("uf") == uf)
            df_reg = df_mov.filter(mask)

            if df_reg.is_empty():
                return RegionalResponse(nome_regiao=regiao_saude, municipios=[], farmacias=[])

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
                nome_regiao=regiao_saude,
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
    def get_prescritores_data(cnpj: str) -> PrescritoresResponse:
        """Retorna indicadores consolidados e os top 20 CRMs atuantes em uma farmácia específica."""
        try:
            df_crms = get_df_crms_detalhado()
            df_top20 = get_df_top20_crms()
            
            # 1. Summary
            rows_crms = df_crms.filter(pl.col("nu_cnpj") == cnpj)
            summary_dict = {}
            if not rows_crms.is_empty():
                try:
                    df_risco = get_df_matriz_risco()
                    df_risco = df_risco.rename({c: c.lower() for c in df_risco.columns})
                    row_risco = df_risco.filter(pl.col("cnpj") == cnpj)
                    risco_dict = {}
                    if not row_risco.is_empty():
                        risco_dict = row_risco.row(0, named=True)
                        
                    row_data = rows_crms.row(0, named=True)
                    summary_dict = {
                        **row_data,
                        "razaoSocial": risco_dict.get("razaosocial") or risco_dict.get("razao_social"),
                        "municipio": risco_dict.get("municipio"),
                        "uf": risco_dict.get("uf"),
                        "populacao_cidade": risco_dict.get("populacao"),
                        "estabelecimentos_cidade": risco_dict.get("total_municipio")
                    }
                except:
                    summary_dict = rows_crms.row(0, named=True)

            # 2. Top 20
            rows_top20 = df_top20.filter(pl.col("cnpj") == cnpj).sort("ranking")
            top20_list = []
            if not rows_top20.is_empty():
                top20_list = [r for r in rows_top20.iter_rows(named=True)]
                
            return PrescritoresResponse(cnpj=cnpj, summary=summary_dict, top20=top20_list)

        except Exception as e:
            import traceback
            print(f"❌ ERRO AO CALCULAR DADOS DE PRESCRITORES: {e}")
            print(traceback.format_exc())
            return PrescritoresResponse(cnpj=cnpj, summary={}, top20=[])
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

        Estratégia de cache em 2 camadas:
          1. Se existir `sentinela_cache/mov_cache_{cnpj}.parquet`, carrega direto (< 1s).
          2. Se não existir, busca `memoria_calculo_consolidada` do SQL Server,
             descompacta via zlib, processa a lógica de linhas e salva o Parquet.

        Args:
            cnpj: CNPJ de 14 dígitos (sem formatação).
            engine: Instância SQLAlchemy Engine para conexão ao banco.
        """
        import traceback
        from pathlib import Path

        from data_cache import get_cache_dir
        
        CACHE_DIR = get_cache_dir()
        CACHE_PATH = os.path.join(CACHE_DIR, f"{cnpj}.parquet")

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
    def get_score_percentiles(scope: str, uf: str = None, regiao_id: str = None) -> list[dict]:
        """
        Calcula a curva de percentis de score (1% a 100%) para diferentes escopos.
        Escopos: 'brasil', 'uf', 'regiao'.
        """
        try:
            from data_cache import get_df_matriz_risco
            df = get_df_matriz_risco()
            df = df.rename({c: c.lower() for c in df.columns})

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
            # Usamos uma lista de 1 a 100 para representar os percentis
            percentis_list = [i / 100.0 for i in range(1, 101)]
            
            # O Polars consegue calcular múltiplos quantis de uma vez
            # mas vamos simplificar a iteração para garantir estabilidade
            scores = df_scoped.select(pl.col("score_risco_final")).to_series().sort()
            
            res = []
            for p in percentis_list:
                # Quantile retorna o valor do score naquele percentil
                val = scores.quantile(p)
                res.append({
                    "percentile": int(p * 100),
                    "score": float(val or 0.0)
                })

            return res
            
        except Exception as e:
            print(f"⚠️ Erro ao calcular percentis de score: {e}")
            return []
