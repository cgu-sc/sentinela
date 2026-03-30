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

class ResultadoSentinelaCnpjSchema(BaseModel):
    municipio_uf: str
    cnpj: str
    razao_social: Optional[str] = None
    totalMov: float = 0.0
    valSemComp: float = 0.0
    percValSemComp: Optional[float] = 0.0
    percQtdeSemComp: Optional[float] = 0.0
    flag_grandes_redes: Optional[str] = "Não"
    qtd_estabelecimentos_rede: Optional[int] = 0
    situacao_rf: Optional[str] = "ND"
    conexao_ms: Optional[str] = "Inativa"
    is_matriz: Optional[bool] = False
    id_ibge7: Optional[int] = None

class RedeEstabelecimentoSchema(BaseModel):
    cnpj_raiz: str
    cnpj: str
    razao_social: Optional[str] = None
    uf: Optional[str] = None
    municipio: Optional[str] = None
    is_matriz: bool = False
    qtd_estabelecimentos_rede: Optional[int] = 0
    flag_grandes_redes: Optional[str] = "Não"

class AnalyticsResponse(BaseModel):
    kpis: List[AnalyticsKPISchema]
    resultado_sentinela_uf: List[ResultadoSentinelaUFSchema]
    resultado_municipios: Optional[List[ResultadoSentinelaMunicipioSchema]] = None
    resultado_cnpjs: Optional[List[ResultadoSentinelaCnpjSchema]] = None

class EvolucaoSemestreSchema(BaseModel):
    semestre: str
    total: float
    regular: float
    irregular: float
    pct_irregular: float

class EvolucaoFinanceiraResponse(BaseModel):
    cnpj: str
    semestres: List[EvolucaoSemestreSchema]

class FatorRiscoBucketSchema(BaseModel):
    faixa: str
    qtd: int
    valor: str
    valor_raw: float

class FatorRiscoResponseSchema(BaseModel):
    periodo_formatado: str
    buckets: List[FatorRiscoBucketSchema]
