from typing import Optional

from pydantic import BaseModel, Field


class TargetKpiSchema(BaseModel):
    key: str
    label: str
    value: int | float | str | None = None


class TargetMapRowSchema(BaseModel):
    id_ibge7: int
    municipio: str
    uf: str
    total_farmacias: int
    valor_incompativel: float
    casos_observados: int
    participacao_uf: Optional[float] = None


class ParkinsonTargetRowSchema(BaseModel):
    id_cnpj: int
    cnpj: str
    razao_social: str
    is_matriz: bool
    is_conexao_ativa: bool
    municipio: str
    uf: str
    id_ibge7: int
    id_regiao_saude: int
    ano_base: int
    populacao_50_mais: int
    casos_esperados: float
    casos_observados: int
    casos_observados_municipio: int
    razao_observado_esperado: Optional[float] = None
    valor_incompativel: float
    autorizacoes: int
    participacao_municipio: Optional[float] = None


class ParkinsonTargetResponse(BaseModel):
    kpis: list[TargetKpiSchema] = Field(default_factory=list)
    mapa: list[TargetMapRowSchema] = Field(default_factory=list)
    items: list[ParkinsonTargetRowSchema] = Field(default_factory=list)
    total: int
    page: int
    page_size: int
    sort_field: str
    sort_order: str
