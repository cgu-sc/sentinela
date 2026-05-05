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

