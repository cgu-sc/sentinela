from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from typing import List, Optional
from datetime import date
from database import get_db
from ..schemas.analytics import AnalyticsResponse, ResultadoSentinelaSchema, FatorRiscoResponseSchema, RedeEstabelecimentoSchema
from ..services.analytics import AnalyticsService

router = APIRouter()

@router.get("/resumo", response_model=AnalyticsResponse)
def get_analytics_summary(
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
    cnpj_raiz: Optional[str] = Query(None),
    db: Session = Depends(get_db)
):
    return AnalyticsService.get_dashboard_data(db, data_inicio, data_fim, perc_min, perc_max, val_min, uf, regiao_saude, municipio, situacao_rf, conexao_ms, porte_empresa, grande_rede, cnpj_raiz)

@router.get("/resultados-detalhados", response_model=List[ResultadoSentinelaSchema])
def get_resultados_detalhados(db: Session = Depends(get_db)):
    return AnalyticsService.get_resultado_sentinela(db)

@router.get("/faixas-risco", response_model=FatorRiscoResponseSchema)
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
    cnpj_raiz: Optional[str] = Query(None),
    db: Session = Depends(get_db)
):
    return AnalyticsService.get_fator_risco_data(db, data_inicio, data_fim, perc_min, perc_max, val_min, uf, regiao_saude, municipio, situacao_rf, conexao_ms, porte_empresa, grande_rede, cnpj_raiz)

@router.get("/rede/{cnpj_raiz}", response_model=List[RedeEstabelecimentoSchema])
def get_rede_estabelecimentos(cnpj_raiz: str):
    """Retorna todos os estabelecimentos de uma rede dado o CNPJ raiz (8 dígitos)."""
    raiz = cnpj_raiz.replace(".", "").replace("/", "").replace("-", "")[:8]
    return AnalyticsService.get_rede_por_cnpj_raiz(raiz)
