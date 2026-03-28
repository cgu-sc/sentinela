from pydantic import BaseModel
from typing import List, Optional

class AnalyticsKPISchema(BaseModel):
    id: str
    label: str
    value: str
    color: str
    icon: str

class ResultadoSentinelaUFSchema(BaseModel):
    uf: Optional[str] = "ND"
    cnpjs: Optional[int] = 0
    percValSemComp: Optional[float] = 0.0
    valSemComp: Optional[float] = 0.0
    totalMov: Optional[float] = 0.0
    percQtdeSemComp: Optional[float] = 0.0
    qtdeSemComp: Optional[int] = 0
    totalQtde: Optional[int] = 0

class ResultadoSentinelaMunicipioSchema(BaseModel):
    uf: Optional[str] = "ND"
    municipio: Optional[str] = "ND"
    cnpjs: Optional[int] = 0
    percValSemComp: Optional[float] = 0.0
    valSemComp: Optional[float] = 0.0
    totalMov: Optional[float] = 0.0
    percQtdeSemComp: Optional[float] = 0.0
    qtdeSemComp: Optional[int] = 0
    totalQtde: Optional[int] = 0

class ResultadoSentinelaSchema(BaseModel):
    uf: Optional[str] = None
    id_ibge7: Optional[int] = None
    municipio: Optional[str] = None
    nu_populacao: Optional[int] = 0
    cnpj: Optional[str] = None
    razao_social: Optional[str] = None
    qnt_medicamentos_vendidos: Optional[int] = 0
    qnt_medicamentos_vendidos_sem_comprovacao: Optional[int] = 0
    nu_autorizacoes: Optional[int] = 0
    valor_vendas: Optional[float] = 0.0
    valor_sem_comprovacao: Optional[float] = 0.0
    percentual_sem_comprovacao: Optional[float] = 0.0
    num_estabelecimentos_mesmo_municipio: Optional[int] = 0
    num_meses_movimentacao: Optional[int] = 0
    CodPorteEmpresa: Optional[int] = None

class AnalyticsResponse(BaseModel):
    kpis: List[AnalyticsKPISchema]
    resultado_sentinela_uf: List[ResultadoSentinelaUFSchema]
    resultado_municipios: Optional[List[ResultadoSentinelaMunicipioSchema]] = None

class FatorRiscoBucketSchema(BaseModel):
    faixa: str
    qtd: int
    valor: str
    valor_raw: float

class FatorRiscoResponseSchema(BaseModel):
    periodo_formatado: str
    buckets: List[FatorRiscoBucketSchema]
