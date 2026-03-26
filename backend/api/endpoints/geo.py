from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from database import get_db
from ..schemas.geo import LocalidadesResponseSchema
from ..services.geo import GeoService

router = APIRouter()

@router.get("/localidades", response_model=LocalidadesResponseSchema)
def get_localidades(db: Session = Depends(get_db)):
    """
    Retorna a hierarquia completa UF > Região de Saúde > Município
    para alimentar os filtros em cascata do frontend.
    """
    return GeoService.get_localidades(db)
