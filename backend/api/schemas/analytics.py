from pydantic import BaseModel
from typing import Dict, List, Optional
from datetime import date

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
    id_ibge7: Optional[int] = None
    cnpjs: Optional[int] = 0
    percValSemComp: Optional[float] = 0.0
    valSemComp: Optional[float] = 0.0
    totalMov: Optional[float] = 0.0
    percQtdeSemComp: Optional[float] = 0.0
    qtdeSemComp: Optional[int] = 0
    totalQtde: Optional[int] = 0
    populacao: Optional[int] = 0
    densidade: Optional[float] = 0.0

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
    is_grande_rede: Optional[bool] = False
    qtd_estabelecimentos_rede: Optional[int] = 0
    situacao_rf: Optional[str] = "ND"
    is_conexao_ativa: Optional[bool] = False
    is_matriz: Optional[bool] = False
    id_ibge7: Optional[int] = None
    score_risco_final: Optional[float] = None
    classificacao_risco: Optional[str] = None
    data_ultima_venda: Optional[date] = None
    municipio: Optional[str] = None
    uf: Optional[str] = None
    rank_nacional: Optional[int] = None
    total_nacional: Optional[int] = None
    rank_uf: Optional[int] = None
    total_uf: Optional[int] = None
    rank_regiao_saude: Optional[int] = None
    total_regiao_saude: Optional[int] = None
    rank_municipio: Optional[int] = None
    total_municipio: Optional[int] = None

class RedeEstabelecimentoSchema(BaseModel):
    cnpj_raiz: str
    cnpj: str
    razao_social: Optional[str] = None
    uf: Optional[str] = None
    municipio: Optional[str] = None
    is_matriz: bool = False
    qtd_estabelecimentos_rede: Optional[int] = 0
    is_grande_rede: Optional[bool] = False

class AnalyticsResponse(BaseModel):
    kpis: List[AnalyticsKPISchema]
    resultado_sentinela_uf: List[ResultadoSentinelaUFSchema]
    resultado_municipios: Optional[List[ResultadoSentinelaMunicipioSchema]] = None
    resultado_cnpjs: Optional[List[ResultadoSentinelaCnpjSchema]] = None


class RegionalMunicipioSchema(BaseModel):
    """Resumo de um município dentro da Região de Saúde selecionada."""
    uf: Optional[str] = "ND"
    municipio: Optional[str] = "ND"
    id_ibge7: Optional[int] = None
    populacao: Optional[int] = 0
    qtd_farmacias: Optional[int] = 0
    densidade: Optional[float] = 0.0
    totalMov: Optional[float] = 0.0
    valSemComp: Optional[float] = 0.0
    percValSemComp: Optional[float] = 0.0


class RegionalFarmaciaSchema(BaseModel):
    """Dados de uma farmácia no ranking regional de risco."""
    cnpj: str
    razao_social: Optional[str] = None
    municipio: Optional[str] = None
    uf: Optional[str] = None
    score_risco: Optional[float] = None
    classificacao_risco: Optional[str] = None
    valSemComp: Optional[float] = 0.0
    totalMov: Optional[float] = 0.0
    percValSemComp: Optional[float] = 0.0
    is_conexao_ativa: Optional[bool] = False
    data_ultima_venda: Optional[date] = None
    rank: Optional[int] = None


class RegionalResponse(BaseModel):
    """Payload completo da aba Região de Saúde."""
    nome_regiao: str
    id_regiao: Optional[str] = None
    municipios: List[RegionalMunicipioSchema]
    farmacias: List[RegionalFarmaciaSchema]

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

class FalecidoTransactionSchema(BaseModel):
    cpf: str
    nome_falecido: Optional[str] = None
    municipio_falecido: Optional[str] = None
    uf_falecido: Optional[str] = None
    dt_nascimento: Optional[date] = None
    dt_obito: Optional[date] = None
    fonte_obito: Optional[str] = None
    num_autorizacao: Optional[str] = None
    data_autorizacao: Optional[date] = None
    qtd_itens_na_autorizacao: int = 0
    valor_total_autorizacao: float = 0.0
    dias_apos_obito: int = 0
    outros_estabelecimentos: Optional[str] = None

class FalecidosRankingSchema(BaseModel):
    estabelecimento: str
    qtd_cpfs: int
    pct_total: float

class FalecidosSummarySchema(BaseModel):
    cpfs_distintos: int
    total_autorizacoes: int
    valor_total: float
    media_dias: float
    max_dias: int
    pct_faturamento: float
    cpfs_multi_cnpj: int
    pct_multi_cnpj: float

class FalecidosResponse(BaseModel):
    cnpj: str
    summary: FalecidosSummarySchema
    ranking: List[FalecidosRankingSchema]
    transacoes: List[FalecidoTransactionSchema]

class IndicadorDataSchema(BaseModel):
    valor: Optional[float] = None
    med_reg: Optional[float] = None
    med_uf: Optional[float] = None
    med_br: Optional[float] = None
    risco_reg: Optional[float] = None
    risco_uf: Optional[float] = None
    risco_br: Optional[float] = None

class IndicadoresResponse(BaseModel):
    cnpj: str
    indicadores: Dict[str, IndicadorDataSchema]

# ── Multi-CNPJ Timeline (Audit History) ──────────────────
class TimelineEventSchema(BaseModel):
    cnpj: str
    razao_social: Optional[str] = None
    data_autorizacao: Optional[date] = None
    valor_total_autorizacao: float = 0.0
    num_autorizacao: Optional[str] = None
    is_this_cnpj: bool = False

class MultiCnpjTimelineResponse(BaseModel):
    cpf: str
    nome_falecido: Optional[str] = None
    dt_obito: Optional[date] = None
    events: List[TimelineEventSchema]
    cnpjs_envolvidos: List[str]

# ── Análise CRMs (Prescritores) ─────────────────────────
class PrescritoresResponse(BaseModel):
    cnpj: str
    summary: dict
    top20: list

# ── Dados Cadastrais e Geográficos ─────────────────────
class DadosFarmaciaSchema(BaseModel):
    cnpj: str
    razao_social: Optional[str] = None
    nome_fantasia: Optional[str] = None
    tipo_logradouro: Optional[str] = None
    logradouro: Optional[str] = None
    numero: Optional[str] = None
    complemento: Optional[str] = None
    bairro: Optional[str] = None
    cep: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None


# ── Memória de Cálculo — Movimentação por GTIN ──────────
class MovimentacaoRowSchema(BaseModel):
    """
    Representa uma linha processada da Memória de Cálculo.
    O campo `tipo_linha` define como a linha deve ser renderizada no frontend:
      - 'header_medicamento'  : Cabeçalho do GTIN (fundo cinza escuro)
      - 'header_colunas'      : Sub-cabeçalho de colunas (fundo cinza claro)
      - 'venda_normal'        : Venda com comprovação total (fundo verde claro)
      - 'venda_irregular'     : Venda SEM comprovação (fundo vermelho claro)
      - 'resumo_parcial'      : Linha de subtotal do GTIN (negrito)
      - 'total_geral'         : Linha de total geral do CNPJ (azul escuro)
    """
    tipo_linha: str
    gtin: Optional[str] = None
    medicamento: Optional[str] = None
    periodo_inicial: Optional[str] = None
    periodo_inicio_irregular: Optional[str] = None
    periodo_final: Optional[str] = None
    estoque_inicial: Optional[int] = None
    estoque_final: Optional[int] = None
    vendas: Optional[int] = None
    vendas_irregular: Optional[int] = None
    valor: Optional[float] = None
    valor_irregular: Optional[float] = None
    notas: Optional[str] = None


class MovimentacaoSummarySchema(BaseModel):
    """Totalizadores do processamento da Memória de Cálculo."""
    total_vendas: int = 0
    total_vendas_irregular: int = 0
    valor_total: float = 0.0
    valor_irregular: float = 0.0
    pct_irregular: float = 0.0
    from_cache: bool = False  # True se foi carregado do cache Parquet local


class MovimentacaoResponse(BaseModel):
    """Payload completo da aba Movimentação."""
    cnpj: str
    summary: MovimentacaoSummarySchema
    rows: List[MovimentacaoRowSchema]


# ── Análise de Indicadores (Vista /indicadores) ──────────────────────────────

class IndicadorKpiSummarySchema(BaseModel):
    """Contadores de status para um indicador no escopo atual."""
    total_critico: int = 0
    total_atencao: int = 0
    total_normal: int = 0
    total_sem_dados: int = 0
    mediana_reg: Optional[float] = None
    mad_reg: Optional[float] = None
    pct_acima_limiar: Optional[float] = None
    limiar_atencao: Optional[float] = None
    limiar_critico: Optional[float] = None


class IndicadorCnpjRowSchema(BaseModel):
    """Uma linha na tabela ranqueada de CNPJs por indicador."""
    cnpj: str
    razao_social: Optional[str] = None
    municipio: Optional[str] = None
    uf: Optional[str] = None
    id_ibge7: Optional[int] = None
    valor: Optional[float] = None
    med_reg: Optional[float] = None
    risco_reg: Optional[float] = None
    status: str = "SEM DADOS"          # "CRÍTICO" | "ATENÇÃO" | "NORMAL" | "SEM DADOS"
    is_grande_rede: Optional[bool] = False
    situacao_rf: Optional[str] = None
    is_conexao_ativa: Optional[bool] = False
    score_risco_final: Optional[float] = None
    val_sem_comp: Optional[float] = None
    perc_val_sem_comp: Optional[float] = None


class IndicadorMunicipioRowSchema(BaseModel):
    """Agregação municipal para o mapa coroplético de um indicador."""
    municipio: str
    uf: Optional[str] = None
    id_ibge7: Optional[int] = None
    total_cnpjs: int = 0
    total_critico: int = 0
    pct_critico: float = 0.0           # campo usado para colorir o mapa


class IndicadorAnaliseResponse(BaseModel):
    """Payload completo da análise cruzada de um indicador."""
    indicador: str
    kpis: IndicadorKpiSummarySchema
    municipios: List[IndicadorMunicipioRowSchema]
    cnpjs: List[IndicadorCnpjRowSchema]

