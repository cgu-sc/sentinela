from typing import List
from datetime import date
import polars as pl
from sqlalchemy.orm import Session
from sqlalchemy import text
from data_cache import get_df
from ..schemas.dashboard import (
    DashboardKPISchema,
    ResultadoSentinelaUFSchema,
    DashboardResponse,
    ResultadoSentinelaSchema,
    FatorRiscoResponseSchema,
    FatorRiscoBucketSchema
)

class DashboardService:
    @staticmethod
    def get_dashboard_data(db: Session, data_inicio=None, data_fim=None, perc_min=None, perc_max=None, val_min=None, uf=None, regiao_saude=None, municipio=None) -> DashboardResponse:
        """
        Roteamento inteligente por performance:
        MODO 1 — Período completo sem filtro %   → resultado_sentinela         (instantâneo)
        MODO 2 — Período parcial sem filtro %    → resultado_mensal_uf/brasil  (instantâneo)
        MODO 3 — Qualquer período com filtro %  → movimentacao_mensal_cnpj    (dinâmico)
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
                    DashboardKPISchema(id='total_cnpjs', label='CNPJs', value=f"{(cnpjs or 0):,}".replace(',', '.'), color='#3b82f6', icon='pi pi-id-card'),
                    DashboardKPISchema(id='valor_vendas', label='Valor Total de Vendas', value=human_format(total_vendas), color='#10b981', icon='pi pi-dollar'),
                    DashboardKPISchema(id='perc_valor', label='% sem comprovação', value=f"{(perc_sem_comp or 0):.2f}%".replace('.', ','), color='#f59e0b', icon='pi pi-percentage'),
                    DashboardKPISchema(id='valor_nao_comp', label='Valor sem Comprovação', value=human_format(val_sem_comp), color='#ef4444', icon='pi pi-dollar'),
                    DashboardKPISchema(id='total_meds', label='Qtde de Medicamentos', value=human_format_qty(total_meds), color='#8b5cf6', icon='pi pi-box'),
                ]

            MIN_DATA = date(2015, 7, 1)
            MAX_DATA = date(2024, 12, 31)
            p_min = perc_min if perc_min is not None else 0.0
            p_max = perc_max if perc_max is not None else 100.0
            v_min = float(val_min) if val_min is not None and val_min > 0 else None
            has_perc_filter = p_min > 0.0 or p_max < 100.0
            has_val_filter = v_min is not None
            has_geo_filter = bool(uf or regiao_saude or municipio)

            # Cláusulas WHERE dinâmicas para filtro geográfico no Modo 3
            geo_where = ""
            if uf:            geo_where += " AND uf = :uf"
            if regiao_saude:  geo_where += " AND no_regiao_saude = :regiao_saude"
            if municipio:     geo_where += " AND no_municipio = :municipio"

            inicio = (data_inicio if data_inicio and data_inicio >= MIN_DATA else MIN_DATA) if data_inicio else MIN_DATA
            fim = data_fim if data_fim else MAX_DATA
            is_full_period = inicio <= MIN_DATA and fim >= MAX_DATA

            if is_full_period and not has_perc_filter and not has_val_filter and not has_geo_filter:
                # -------------------------------------------------------
                # MODO 1: Período completo → resultado_sentinela
                # -------------------------------------------------------
                sql_kpis = text("""
                    SELECT
                        COUNT(DISTINCT cnpj) as cnpjs,
                        SUM(CAST(valor_vendas AS FLOAT)) as total_vendas,
                        SUM(CAST(valor_sem_comprovacao AS FLOAT)) as val_sem_comp,
                        (SUM(CAST(valor_sem_comprovacao AS FLOAT)) / NULLIF(SUM(CAST(valor_vendas AS FLOAT)), 0)) * 100 as perc_sem_comp,
                        SUM(CAST(qnt_medicamentos_vendidos AS FLOAT)) as total_meds
                    FROM [temp_CGUSC].[fp].[resultado_sentinela]
                """)
                kpi_row = db.execute(sql_kpis).fetchone()

                sql_uf = text("""
                    SELECT
                        uf,
                        COUNT(DISTINCT cnpj) as cnpjs,
                        (SUM(CAST(valor_sem_comprovacao AS FLOAT)) / NULLIF(SUM(CAST(valor_vendas AS FLOAT)), 0)) * 100 as percValSemComp,
                        SUM(CAST(valor_sem_comprovacao AS FLOAT)) as valSemComp,
                        SUM(CAST(valor_vendas AS FLOAT)) as totalMov,
                        (CAST(SUM(qnt_medicamentos_vendidos_sem_comprovacao) AS FLOAT) / NULLIF(SUM(CAST(qnt_medicamentos_vendidos AS FLOAT)), 0)) * 100 as percQtdeSemComp,
                        SUM(CAST(qnt_medicamentos_vendidos_sem_comprovacao AS FLOAT)) as qtdeSemComp,
                        SUM(CAST(qnt_medicamentos_vendidos AS FLOAT)) as totalQtde
                    FROM [temp_CGUSC].[fp].[resultado_sentinela]
                    GROUP BY uf
                    ORDER BY percValSemComp DESC
                """)
                uf_results = db.execute(sql_uf).fetchall()

            elif not has_perc_filter and not has_val_filter and not has_geo_filter:
                # -------------------------------------------------------
                # MODO 2: Período parcial sem filtro % → tabelas pré-computadas
                # -------------------------------------------------------
                sql_kpis = text("""
                    SELECT
                        SUM(CAST(total_vendas AS FLOAT)) as total_vendas,
                        SUM(CAST(total_sem_comprovacao AS FLOAT)) as val_sem_comp,
                        (SUM(CAST(total_sem_comprovacao AS FLOAT)) / NULLIF(SUM(CAST(total_vendas AS FLOAT)), 0)) * 100 as perc_sem_comp,
                        SUM(CAST(total_qnt_vendas AS FLOAT)) as total_meds
                    FROM [temp_CGUSC].[fp].[resultado_mensal_brasil] WITH (NOLOCK)
                    WHERE periodo BETWEEN :inicio AND :fim
                """)
                kpi_row = db.execute(sql_kpis, {"inicio": inicio, "fim": fim}).fetchone()

                # COUNT DISTINCT CNPJ separado (não é somável entre meses)
                sql_cnpjs = text("""
                    SELECT COUNT(DISTINCT cnpj) as cnpjs
                    FROM [temp_CGUSC].[fp].[movimentacao_mensal_cnpj] WITH (NOLOCK)
                    WHERE periodo BETWEEN :inicio AND :fim
                """)
                cnpj_row = db.execute(sql_cnpjs, {"inicio": inicio, "fim": fim}).fetchone()

                sql_uf = text("""
                    SELECT
                        uf,
                        (SUM(CAST(total_sem_comprovacao AS FLOAT)) / NULLIF(SUM(CAST(total_vendas AS FLOAT)), 0)) * 100 as percValSemComp,
                        SUM(CAST(total_sem_comprovacao AS FLOAT)) as valSemComp,
                        SUM(CAST(total_vendas AS FLOAT)) as totalMov,
                        (SUM(CAST(total_qnt_sem_comprovacao AS FLOAT)) / NULLIF(SUM(CAST(total_qnt_vendas AS FLOAT)), 0)) * 100 as percQtdeSemComp,
                        SUM(CAST(total_qnt_sem_comprovacao AS FLOAT)) as qtdeSemComp,
                        SUM(CAST(total_qnt_vendas AS FLOAT)) as totalQtde
                    FROM [temp_CGUSC].[fp].[resultado_mensal_uf] WITH (NOLOCK)
                    WHERE periodo BETWEEN :inicio AND :fim
                    GROUP BY uf
                    ORDER BY percValSemComp DESC
                """)
                uf_rows = db.execute(sql_uf, {"inicio": inicio, "fim": fim}).fetchall()

                # COUNT DISTINCT CNPJ por UF separado
                sql_cnpjs_uf = text("""
                    SELECT uf, COUNT(DISTINCT cnpj) as cnpjs
                    FROM [temp_CGUSC].[fp].[movimentacao_mensal_cnpj] WITH (NOLOCK)
                    WHERE periodo BETWEEN :inicio AND :fim
                    GROUP BY uf
                """)
                cnpjs_por_uf = {r.uf: r.cnpjs for r in db.execute(sql_cnpjs_uf, {"inicio": inicio, "fim": fim}).fetchall()}

                # Monta resultado combinando as duas queries e retorna diretamente
                uf_results_2 = [
                    {**dict(row._mapping), "cnpjs": cnpjs_por_uf.get(row.uf, 0)}
                    for row in uf_rows
                ]
                kpis_2 = build_kpis(
                    cnpj_row.cnpjs, kpi_row.total_vendas, kpi_row.val_sem_comp,
                    kpi_row.perc_sem_comp, kpi_row.total_meds
                )
                resultado_uf_2 = [ResultadoSentinelaUFSchema(**r) for r in uf_results_2]
                return DashboardResponse(kpis=kpis_2, resultado_sentinela_uf=resultado_uf_2)

            else:
                # -------------------------------------------------------
                # MODO 3: Polars in-memory — filtros geo/% /valor
                # -------------------------------------------------------
                df = get_df()

                # Filtro de período + geo
                mask = pl.col("periodo").is_between(inicio, fim)
                if uf:           mask = mask & (pl.col("uf") == uf)
                if regiao_saude: mask = mask & (pl.col("no_regiao_saude") == regiao_saude)
                if municipio:    mask = mask & (pl.col("no_municipio") == municipio)
                period_df = df.filter(mask)

                # Agrega por CNPJ para calcular % (equivalente ao CTE cnpjs_na_faixa)
                cnpj_agg = period_df.group_by("cnpj").agg([
                    pl.sum("total_vendas").alias("tv"),
                    pl.sum("total_sem_comprovacao").alias("tsc"),
                    pl.sum("total_qnt_vendas").alias("tqv"),
                    pl.sum("total_qnt_sem_comprovacao").alias("tqsc"),
                ]).with_columns([
                    (pl.col("tsc") / pl.when(pl.col("tv") > 0).then(pl.col("tv")).otherwise(None) * 100).alias("pct")
                ])

                # Filtro de % e valor mínimo
                cnpj_ok = cnpj_agg.filter((pl.col("pct") >= p_min) & (pl.col("pct") <= p_max))
                if has_val_filter:
                    cnpj_ok = cnpj_ok.filter(pl.col("tsc") >= v_min)

                # KPIs
                tv  = float(cnpj_ok["tv"].sum() or 0)
                tsc = float(cnpj_ok["tsc"].sum() or 0)
                tqv = float(cnpj_ok["tqv"].sum() or 0)
                pct = (tsc / tv * 100) if tv else 0.0
                kpis = build_kpis(cnpj_ok.height, tv, tsc, pct, tqv)

                # UF breakdown — join para pegar dados por UF dos CNPJs elegíveis
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
                return DashboardResponse(kpis=kpis, resultado_sentinela_uf=resultado_sentinela_uf)

            kpis = build_kpis(
                kpi_row.cnpjs, kpi_row.total_vendas, kpi_row.val_sem_comp,
                kpi_row.perc_sem_comp, kpi_row.total_meds
            )

            # Apenas Modo 1 chega aqui (Modos 2 e 3 retornam cedo)
            resultado_sentinela_uf = [
                ResultadoSentinelaUFSchema(**dict(r._mapping))
                for r in uf_results
            ]

            return DashboardResponse(kpis=kpis, resultado_sentinela_uf=resultado_sentinela_uf)
        except Exception as e:
            import traceback
            print("❌ ERRO NO DASHBOARD SERVICE:")
            print(traceback.format_exc())
            return DashboardResponse(kpis=[], resultado_sentinela_uf=[])

    @staticmethod
    def get_resultado_sentinela(db: Session) -> List[ResultadoSentinelaSchema]:
        """
        Busca TODOS os registros da tabela de resultados detalhados.
        Utilizado para alimentar a Store global de resultados no Frontend.
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
            # Mapeamento do SQLAlchemy para a lista de Schemas Pydantic
            return [ResultadoSentinelaSchema(**row._mapping) for row in result]
        except Exception as e:
            import traceback
            print("❌ ERRO AO BUSCAR RESULTADOS DETALHADOS:")
            print(traceback.format_exc())
            return []
    @staticmethod
    def get_fator_risco_data(db: Session, data_inicio=None, data_fim=None, perc_min=None, perc_max=None, val_min=None, uf=None, regiao_saude=None, municipio=None) -> FatorRiscoResponseSchema:
        """
        Calcula as faixas de risco (Buckets de 10%) via Polars in-memory.
        """
        try:
            MIN_DATA = date(2015, 7, 1)
            inicio = max(data_inicio, MIN_DATA) if data_inicio else MIN_DATA
            fim = data_fim if data_fim else date(2199, 12, 31)
            p_min = perc_min if perc_min is not None else 0.0
            p_max = perc_max if perc_max is not None else 100.0
            v_min = float(val_min) if val_min is not None and val_min > 0 else None

            df = get_df()

            # Filtro de período + geo
            mask = pl.col("periodo").is_between(inicio, fim)
            if uf:           mask = mask & (pl.col("uf") == uf)
            if regiao_saude: mask = mask & (pl.col("no_regiao_saude") == regiao_saude)
            if municipio:    mask = mask & (pl.col("no_municipio") == municipio)

            # Agrega por CNPJ no período e calcula %
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

            # Bucketing
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
            import traceback
            print("ERRO NO CALCULO DO FATOR DE RISCO:")
            print(traceback.format_exc())
            return FatorRiscoResponseSchema(periodo_formatado="Erro ao calcular", buckets=[])

