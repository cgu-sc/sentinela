from typing import List
from datetime import date
import polars as pl
from sqlalchemy.orm import Session
from sqlalchemy import text
from data_cache import get_df, get_rede_df, get_localidades_df, get_df_matriz_risco, get_df_falecidos
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
)

class AnalyticsService:
    @staticmethod
    def get_dashboard_data(db: Session, data_inicio=None, data_fim=None, perc_min=None, perc_max=None, val_min=None, uf=None, regiao_saude=None, municipio=None, situacao_rf=None, conexao_ms=None, porte_empresa=None, grande_rede=None, cnpj_raiz=None) -> AnalyticsResponse:
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

            def build_kpis(cnpjs, total_vendas, val_sem_comp, perc_sem_comp, total_meds):
                return [
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
            if conexao_ms and conexao_ms != 'Todos':      mask = mask & (pl.col("conexao_ms") == conexao_ms)
            if porte_empresa and porte_empresa != 'Todos': mask = mask & (pl.col("porte_empresa") == porte_empresa)
            if grande_rede and grande_rede != 'Todos':     mask = mask & (pl.col("flag_grandes_redes") == grande_rede)
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
            kpis = build_kpis(cnpj_ok.height, tv, tsc, pct, tqv)

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
                    pl.col("flag_grandes_redes").first().alias("flag_grandes_redes"),
                    pl.col("qtd_estabelecimentos_rede").first().alias("qtd_estabelecimentos_rede"),
                    pl.col("situacao_rf").first().alias("situacao_rf"),
                    pl.col("conexao_ms").first().alias("conexao_ms"),
                ])
                .with_columns([
                    (pl.col("valSemComp") / pl.when(pl.col("totalMov") > 0).then(pl.col("totalMov")).otherwise(None) * 100).alias("percValSemComp"),
                    (pl.col("qtdeSemComp") / pl.when(pl.col("totalQtde") > 0).then(pl.col("totalQtde")).otherwise(None) * 100).alias("percQtdeSemComp"),
                    (pl.col("municipio") + " / " + pl.col("uf")).alias("municipio_uf"),
                    (pl.col("cnpj").str.slice(8, 4) == "0001").alias("is_matriz"),
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
                risco_df = (
                    get_df_matriz_risco()
                    .select([
                        "cnpj", "rank_nacional", "total_nacional", "rank_uf", "total_uf",
                        "rank_regiao_saude", "total_regiao_saude", "rank_municipio", "total_municipio"
                    ])
                )
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
        MAPPING = {
            'auditado':              ('pct_auditado',              'med_auditado_reg',             'med_auditado_uf',             'med_auditado_br',             'risco_auditado_reg',             'risco_auditado_uf',             'risco_auditado_br'),
            'falecidos':             ('pct_falecidos',             'med_falecidos_reg',            'med_falecidos_uf',            'med_falecidos_br',            'risco_falecidos_reg',            'risco_falecidos_uf',            'risco_falecidos_br'),
            'clinico':               ('pct_clinico',               'med_clinico_reg',              'med_clinico_uf',              'med_clinico_br',              'risco_clinico_reg',              'risco_clinico_uf',              'risco_clinico_br'),
            'teto':                  ('pct_teto',                  'med_teto_reg',                 'med_teto_uf',                 'med_teto_br',                 'risco_teto_reg',                 'risco_teto_uf',                 'risco_teto_br'),
            'polimedicamento':       ('pct_polimedicamento',       'med_polimedicamento_reg',      'med_polimedicamento_uf',      'med_polimedicamento_br',      'risco_polimedicamento_reg',      'risco_polimedicamento_uf',      'risco_polimedicamento_br'),
            'media_itens':           ('val_media_itens',           'med_media_itens_reg',          'med_media_itens_uf',          'med_media_itens_br',          'risco_media_itens_reg',          'risco_media_itens_uf',          'risco_media_itens_br'),
            'ticket':                ('val_ticket_medio',          'med_ticket_reg',               'med_ticket_uf',               'med_ticket_br',               'risco_ticket_reg',               'risco_ticket_uf',               'risco_ticket_br'),
            'receita_paciente':      ('val_receita_paciente',      'med_receita_paciente_reg',     'med_receita_paciente_uf',     'med_receita_paciente_br',     'risco_receita_paciente_reg',     'risco_receita_paciente_uf',     'risco_receita_paciente_br'),
            'per_capita':            ('val_per_capita',            'med_per_capita_reg',           'med_per_capita_uf',           'med_per_capita_br',           'risco_per_capita_reg',           'risco_per_capita_uf',           'risco_per_capita_br'),
            'alto_custo':            ('pct_alto_custo',            'med_alto_custo_reg',           'med_alto_custo_uf',           'med_alto_custo_br',           'risco_alto_custo_reg',           'risco_alto_custo_uf',           'risco_alto_custo_br'),
            'vendas_rapidas':        ('pct_vendas_rapidas',        'med_vendas_rapidas_reg',       'med_vendas_rapidas_uf',       'med_vendas_rapidas_br',       'risco_vendas_rapidas_reg',       'risco_vendas_rapidas_uf',       'risco_vendas_rapidas_br'),
            'volume_atipico':        ('val_volume_atipico',        'med_volume_atipico_reg',       'med_volume_atipico_uf',       'med_volume_atipico_br',       'risco_volume_atipico_reg',       'risco_volume_atipico_uf',       'risco_volume_atipico_br'),
            'recorrencia_sistemica': ('pct_recorrencia_sistemica', 'med_recorrencia_sistemica_reg','med_recorrencia_sistemica_uf','med_recorrencia_sistemica_br','risco_recorrencia_sistemica_reg','risco_recorrencia_sistemica_uf','risco_recorrencia_sistemica_br'),
            'pico':                  ('pct_pico',                  'med_pico_reg',                 'med_pico_uf',                 'med_pico_br',                 'risco_pico_reg',                 'risco_pico_uf',                 'risco_pico_br'),
            'geografico':            ('pct_geografico',            'med_geografico_reg',           'med_geografico_uf',           'med_geografico_br',           'risco_geografico_reg',           'risco_geografico_uf',           'risco_geografico_br'),
            'pacientes_unicos':      ('pct_pacientes_unicos',      'med_pacientes_unicos_reg',     'med_pacientes_unicos_uf',     'med_pacientes_unicos_br',     'risco_pacientes_unicos_reg',     'risco_pacientes_unicos_uf',     'risco_pacientes_unicos_br'),
            'hhi_crm':               ('val_hhi_crm',               'avg_hhi_crm_reg',              'avg_hhi_crm_uf',              'avg_hhi_crm_br',              'risco_crm_reg',                  'risco_crm_uf',                  'risco_crm_br'),
            'exclusividade_crm':     ('pct_exclusividade_crm',     'med_exclusividade_crm_reg',    'med_exclusividade_crm_uf',    'med_exclusividade_crm_br',    'risco_exclusividade_crm_reg',    'risco_exclusividade_crm_uf',    'risco_exclusividade_crm_br'),
            'crms_irregulares':      ('pct_crms_irregulares',      'med_crms_irregulares_reg',     'med_crms_irregulares_uf',     'med_crms_irregulares_br',     'risco_crms_irregulares_reg',     'risco_crms_irregulares_uf',     'risco_crms_irregulares_br'),
        }
        try:
            df = get_df_matriz_risco()
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
                for key, (c_val, c_mr, c_mu, c_mb, c_rr, c_ru, c_rb) in MAPPING.items()
            }
            return IndicadoresResponse(cnpj=cnpj, indicadores=indicadores)
        except Exception as e:
            import traceback
            print(f"❌ ERRO AO BUSCAR INDICADORES: {e}")
            print(traceback.format_exc())
            return IndicadoresResponse(cnpj=cnpj, indicadores={})

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
    def get_fator_risco_data(db: Session, data_inicio=None, data_fim=None, perc_min=None, perc_max=None, val_min=None, uf=None, regiao_saude=None, municipio=None, situacao_rf=None, conexao_ms=None, porte_empresa=None, grande_rede=None, cnpj_raiz=None) -> FatorRiscoResponseSchema:
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
            if conexao_ms and conexao_ms != 'Todos':       mask = mask & (pl.col("conexao_ms") == conexao_ms)
            if porte_empresa and porte_empresa != 'Todos': mask = mask & (pl.col("porte_empresa") == porte_empresa)
            if grande_rede and grande_rede != 'Todos':     mask = mask & (pl.col("flag_grandes_redes") == grande_rede)
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
    def get_regional_data(regiao_saude: str) -> RegionalResponse:
        """
        Constrói o payload completo da aba 'Região de Saúde'.

        Args:
            regiao_saude: Nome da Região de Saúde (filtro da sidebar, ex: 'GRANDE FLORIANOPOLIS').

        Returns:
            RegionalResponse com resumo de municípios e ranking de farmácias.
        """
        try:
            df_mov   = get_df()
            df_loc   = get_localidades_df()
            df_risco = get_df_matriz_risco()

            # ── Filtra movimentação para a região ───────────────────────────────
            df_reg = df_mov.filter(pl.col("no_regiao_saude") == regiao_saude)

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
                ])
            )

            # Enriquece com população do IBGE (localidades_df)
            loc_pop = df_loc.select(["no_municipio", "sg_uf", "id_regiao_saude", "nu_populacao"]).unique()
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

            # Pega o id_regiao_saude a partir da primeira ocorrência
            id_regiao: str | None = None
            if not loc_pop.filter(pl.col("no_municipio").is_in(mun_agg["no_municipio"])).is_empty():
                id_row = loc_pop.filter(
                    pl.col("no_municipio").is_in(mun_agg["no_municipio"])
                ).row(0, named=True)
                id_regiao = str(id_row.get("id_regiao_saude", ""))

            municipios = [
                RegionalMunicipioSchema(
                    uf=r["uf"],
                    municipio=str(r["no_municipio"]).title(),
                    populacao=int(r["populacao"] or 0),
                    qtd_farmacias=int(r["qtd_farmacias"] or 0),
                    densidade=float(r["densidade"] or 0.0),
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
                    pl.col("conexao_ms").first().alias("conexao_ms"),
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
            for col in ["SCORE_RISCO_FINAL", "CLASSIFICACAO_RISCO"]:
                if col in df_risco.columns:
                    risco_available.append(col)
                    risco_cols.append(col)

            if risco_available:
                df_risco_slim = df_risco.select(risco_cols)
                cnpj_enriched = cnpj_agg.join(df_risco_slim, on="cnpj", how="left")
            else:
                cnpj_enriched = cnpj_agg.with_columns([
                    pl.lit(None).cast(pl.Float64).alias("SCORE_RISCO_FINAL"),
                    pl.lit(None).cast(pl.Utf8).alias("CLASSIFICACAO_RISCO"),
                ])

            # Ordena pelo score de risco (maior risco primeiro)
            cnpj_sorted = cnpj_enriched.sort(
                "SCORE_RISCO_FINAL", descending=True, nulls_last=True
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
                    score_risco=float(r["SCORE_RISCO_FINAL"]) if r.get("SCORE_RISCO_FINAL") is not None else None,
                    classificacao_risco=r.get("CLASSIFICACAO_RISCO"),
                    valSemComp=float(r.get("valSemComp") or 0.0),
                    totalMov=float(r.get("totalMov") or 0.0),
                    percValSemComp=float(r.get("percValSemComp") or 0.0),
                    conexao_ms=r.get("conexao_ms"),
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

