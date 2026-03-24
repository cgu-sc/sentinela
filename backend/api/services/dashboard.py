from typing import List
from sqlalchemy.orm import Session
from sqlalchemy import text
from ..schemas.dashboard import (
    DashboardKPISchema, 
    NationalAnalysisRowSchema, 
    DashboardResponse,
    ResultadoSentinelaSchema
)

class DashboardService:
    @staticmethod
    def get_dashboard_data(db: Session) -> DashboardResponse:
        """
        Consolida os dados estratégicos (KPIs e Ranking UF) reais do banco de dados.
        """
        try:
            # 1. KPIs (Resumo Geral do Brasil)
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
            
            # Helper para formatar Bilhões/Milhões estilo "R$ 29,7B" requisitado antes
            def human_format(num):
                if num is None: return "0"
                num = float(num) # Garante que é float (evita erro com Decimal)
                if num >= 1_000_000_000:
                    return f"R$ {num/1_000_000_000:.2f} Bi".replace('.', ',')
                if num >= 1_000_000:
                    return f"R$ {num/1_000_000:.2f} Mi".replace('.', ',')
                return f"R$ {num:,.2f}".replace(',', 'X').replace('.', ',').replace('X', '.')

            kpis = [
                DashboardKPISchema(id='total_cnpjs', label='CNPJs', value=f"{(kpi_row.cnpjs or 0):,}".replace(',', '.'), color='#ef4444', icon='pi pi-id-card'),
                DashboardKPISchema(id='valor_vendas', label='Valor Total de Vendas', value=human_format(kpi_row.total_vendas), color='#3b82f6', icon='pi pi-money-bill'),
                DashboardKPISchema(id='perc_valor', label='% sem comprovação', value=f"{(kpi_row.perc_sem_comp or 0):.2f}%".replace('.', ','), color='#f59e0b', icon='pi pi-percentage'),
                DashboardKPISchema(id='valor_nao_comp', label='Valor sem Comprovação', value=human_format(kpi_row.val_sem_comp), color='#10b981', icon='pi pi-exclamation-triangle'),
                DashboardKPISchema(id='total_meds', label='Qtde de Medicamentos', value=f"{(float(kpi_row.total_meds or 0)/1_000_000_000):.2f} Bi".replace('.', ','), color='#8b5cf6', icon='pi pi-box'),
            ]
            
            # 2. Análise Nacional (Agrupamento por UF)
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
            
            national_analysis = [NationalAnalysisRowSchema(**row._mapping) for row in uf_results]
            
            return DashboardResponse(kpis=kpis, national_analysis=national_analysis)
        except Exception as e:
            import traceback
            print("❌ ERRO NO DASHBOARD SERVICE:")
            print(traceback.format_exc())
            # Fallback para não quebrar a API, mas os dados virão zerados/vazios
            return DashboardResponse(kpis=[], national_analysis=[])

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
