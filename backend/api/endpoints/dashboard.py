from typing import List, Optional
from datetime import date
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from database import get_db
from ..schemas.dashboard import DashboardResponse, ResultadoSentinelaSchema, FatorRiscoResponseSchema
from ..services.dashboard import DashboardService

router = APIRouter()

@router.get("/resumo", response_model=DashboardResponse)
def get_dashboard_resumo(
    data_inicio: Optional[date] = Query(None),
    data_fim: Optional[date] = Query(None),
    perc_min: Optional[float] = Query(None),
    perc_max: Optional[float] = Query(None),
    val_min: Optional[float] = Query(None),
    uf: Optional[str] = Query(None),
    regiao_saude: Optional[str] = Query(None),
    municipio: Optional[str] = Query(None),
    situacao_rf: Optional[str] = Query(None),
    conexao_ms: Optional[str] = Query(None),
    porte_empresa: Optional[str] = Query(None),
    grande_rede: Optional[str] = Query(None),
    db: Session = Depends(get_db)
):
    """
    Retorna o resumo consolidado do dashboard (KPIs e Análise por UF).
    Aceita filtros de período, faixa de %, valor mínimo e filtros geográficos.
    """
    return DashboardService.get_dashboard_data(db, data_inicio, data_fim, perc_min, perc_max, val_min, uf, regiao_saude, municipio, situacao_rf, conexao_ms, porte_empresa, grande_rede)

@router.get("/resultados", response_model=List[ResultadoSentinelaSchema])
def get_resultados_sentinela(db: Session = Depends(get_db)):
    """
    Retorna a lista completa de resultados da tabela resultado_sentinela.
    """
    return DashboardService.get_resultado_sentinela(db)

@router.get("/resultado-faixas-risco", response_model=FatorRiscoResponseSchema)
def get_resultado_faixas_risco(
    data_inicio: Optional[date] = Query(None),
    data_fim: Optional[date] = Query(None),
    perc_min: Optional[float] = Query(None),
    perc_max: Optional[float] = Query(None),
    val_min: Optional[float] = Query(None),
    uf: Optional[str] = Query(None),
    regiao_saude: Optional[str] = Query(None),
    municipio: Optional[str] = Query(None),
    situacao_rf: Optional[str] = Query(None),
    conexao_ms: Optional[str] = Query(None),
    porte_empresa: Optional[str] = Query(None),
    grande_rede: Optional[str] = Query(None),
    db: Session = Depends(get_db)
):
    """
    Retorna os dados do gráfico Fator de Risco x Qtd Estab para um período específico.
    """
    return DashboardService.get_fator_risco_data(db, data_inicio, data_fim, perc_min, perc_max, val_min, uf, regiao_saude, municipio, situacao_rf, conexao_ms, porte_empresa, grande_rede)
