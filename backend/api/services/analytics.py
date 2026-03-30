from typing import List
from datetime import date
import polars as pl
from sqlalchemy.orm import Session
from sqlalchemy import text
from data_cache import get_df, get_rede_df, get_localidades_df
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

            # 6. Detalhamento por Município (Se UF estiver selecionada)
            resultado_municipios = None
            if uf and uf != 'Todos':
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

            # 7. Detalhamento por CNPJ (Se Município estiver selecionado)
            resultado_cnpjs = None
            if municipio and municipio != 'Todos':
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
                # Enrich with id_ibge7 from localidades
                try:
                    loc_df = get_localidades_df().select(["no_municipio", "sg_uf", "id_ibge7"])
                    cnpj_df = cnpj_df.join(
                        loc_df,
                        left_on=["municipio", "uf"],
                        right_on=["no_municipio", "sg_uf"],
                        how="left"
                    )
                except Exception:
                    cnpj_df = cnpj_df.with_columns(pl.lit(None).cast(pl.Int64).alias("id_ibge7"))

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
