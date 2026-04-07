from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from database import get_db
from ..schemas.geo import LocalidadesResponseSchema, EstabelecimentosGeoResponseSchema
from ..services.geo import GeoService

router = APIRouter()

@router.get("/localidades", response_model=LocalidadesResponseSchema)
def get_localidades(db: Session = Depends(get_db)):
    """
    Retorna a hierarquia completa UF > Região de Saúde > Município
    para alimentar os filtros em cascata do frontend.
    """
    return GeoService.get_localidades(db)

@router.get("/estabelecimentos", response_model=EstabelecimentosGeoResponseSchema)
def get_estabelecimentos_geo():
    """
    Retorna lat/lon + score de risco de todos os estabelecimentos geocodificados.
    Usado para plotar pontos no mapa interativo e no PDF.
    """
    return GeoService.get_estabelecimentos_geo()
