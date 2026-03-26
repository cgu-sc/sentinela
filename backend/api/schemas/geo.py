from pydantic import BaseModel
from typing import List, Optional

class LocalidadeSchema(BaseModel):
    sg_uf: Optional[str] = None
    no_regiao_saude: Optional[str] = None
    id_regiao_saude: Optional[int] = None
    no_municipio: Optional[str] = None
    id_ibge7: Optional[int] = None

    class Config:
        from_attributes = True

class LocalidadesResponseSchema(BaseModel):
    localidades: List[LocalidadeSchema]
