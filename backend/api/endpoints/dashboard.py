from typing import List
from datetime import date
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from database import get_db
from ..schemas.dashboard import DashboardResponse, ResultadoSentinelaSchema, FatorRiscoResponseSchema
from ..services.dashboard import DashboardService

router = APIRouter()

@router.get("/", response_model=DashboardResponse)
def get_dashboard_summary(db: Session = Depends(get_db)):
    """
    Retorna o resumo consolidado do dashboard (KPIs e Análise Nacional).
    """
    return DashboardService.get_dashboard_data(db)

@router.get("/resultados", response_model=List[ResultadoSentinelaSchema])
def get_resultados_sentinela(db: Session = Depends(get_db)):
    """
    Retorna a lista completa de resultados da tabela resultado_sentinela.
    """
    return DashboardService.get_resultado_sentinela(db)

@router.get("/fator-risco", response_model=FatorRiscoResponseSchema)
def get_fator_risco_data(
    data_inicio: date = Query("2016-01-01"), 
    data_fim: date = Query("2024-12-01"), 
    db: Session = Depends(get_db)
):
    """
    Retorna os dados do gráfico Fator de Risco x Qtd Estab para um período específico.
    """
    return DashboardService.get_fator_risco_data(db, str(data_inicio), str(data_fim))
