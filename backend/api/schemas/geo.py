from pydantic import BaseModel
from typing import List, Optional

class LocalidadeSchema(BaseModel):
    sg_uf: Optional[str] = None
    no_regiao_saude: Optional[str] = None
    id_regiao_saude: Optional[int] = None
    no_municipio: Optional[str] = None
    id_ibge7: Optional[int] = None
    nu_populacao: Optional[int] = None

    class Config:
        from_attributes = True

class LocalidadesResponseSchema(BaseModel):
    localidades: List[LocalidadeSchema]

class EstabelecimentoGeoSchema(BaseModel):
    cnpj: str
    razao_social: Optional[str] = None
    lat: float
    lon: float
    id_ibge7: Optional[int] = None
    score_risco: Optional[float] = None
    classificacao_risco: Optional[str] = None

class EstabelecimentosGeoResponseSchema(BaseModel):
    estabelecimentos: List[EstabelecimentoGeoSchema]
