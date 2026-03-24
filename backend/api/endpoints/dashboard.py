from typing import List
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from database import get_db
from ..schemas.dashboard import DashboardResponse, ResultadoSentinelaSchema
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
