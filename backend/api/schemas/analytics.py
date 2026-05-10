from pydantic import BaseModel, Field
from typing import Dict, List, Optional
from datetime import date, datetime

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
    totalQtde: Optional[int] = 0
    qtdeSemComp: Optional[int] = 0
    percQtdeSemComp: Optional[float] = 0.0
    is_grande_rede: Optional[bool] = False
    qtd_estabelecimentos_rede: Optional[int] = 0
    situacao_rf: Optional[str] = "ND"
    porte_empresa: Optional[str] = "ND"
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
    is_matriz: Optional[bool] = False
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


class RegionalAnimationQuarterSchema(BaseModel):
    """Dados de um trimestre para animação do scatter de posicionamento regional."""
    trimestre: str          # ex: "2015-Q3"
    inicio: date
    fim: date
    farmacias: List[RegionalFarmaciaSchema]


class RegionalAnimationResponse(BaseModel):
    """Payload completo para animação trimestral — todos os trimestres em uma única chamada."""
    nome_regiao: str
    quarters: List[RegionalAnimationQuarterSchema]


class PercentilesPointSchema(BaseModel):
    percentile: int
    score: float

class PercentilesQuarterSchema(BaseModel):
    """Dados de percentis de uma janela de 2 meses para animação da curva de risco."""
    inicio: date
    fim: date
    percentiles: List[PercentilesPointSchema]

class PercentilesAnimationResponse(BaseModel):
    """Payload completo de percentis por período — todos os períodos em uma única chamada."""
    quarters: List[PercentilesQuarterSchema]

class EvolucaoMesSchema(BaseModel):
    mes: str
    total: float
    regular: float
    irregular: float
    pct_irregular: float

class EvolucaoSemestreSchema(BaseModel):
    semestre: str
    total: float
    regular: float
    irregular: float
    pct_irregular: float
    mes_inicio: Optional[str] = None  # "YYYY-MM" — mês mais antigo no grupo (pode ser parcial)
    mes_fim: Optional[str] = None     # "YYYY-MM" — mês mais recente no grupo
    meses: List[EvolucaoMesSchema] = []

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
    from_cache: bool = False
    tem_historico: bool = False
    query_time_ms: Optional[float] = None
    save_time_ms: Optional[float] = None
    read_time_ms: Optional[float] = None

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
    municipio: Optional[str] = None
    uf: Optional[str] = None
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
    crms_interesse: list
    cnpj_alerts: List[dict] = []
    from_cache: bool = False
    tem_historico: bool = False
    read_time_ms: Optional[float] = None
    query_time_ms: Optional[float] = None
    save_time_ms: Optional[float] = None

class CrmDailyProfileItem(BaseModel):
    dt_janela: str
    competencia: int
    nu_prescricoes_dia: int
    nu_crms_distintos: int
    mediana_diaria: float
    is_dia_com_volume_horario_anomalo: int
    is_anomalo_unico: int
    is_crm_multiplo: int
    score_crm_unico_hora: Optional[float] = None
    score_crm_unico_qtd: Optional[int] = None
    score_crm_unico_minutos: Optional[int] = None
    score_crm_unico_medico: Optional[str] = None
    score_crm_multiplo_hora: Optional[float] = None
    score_crm_multiplo_qtd: Optional[int] = None
    score_crm_multiplo_minutos: Optional[int] = None
    score_crm_multiplo_crms: Optional[int] = None

class CrmDailyProfileResponse(BaseModel):
    cnpj: str
    days: List[CrmDailyProfileItem]
    from_cache: bool = False
    read_time_ms: Optional[float] = None
    query_time_ms: Optional[float] = None
    save_time_ms: Optional[float] = None

class CrmHourlyPointSchema(BaseModel):
    dt_janela: date
    hr_janela: int
    nu_prescricoes: int
    nu_crms_diferentes: int
    mediana_hora: float
    is_hora_com_alerta: int = 0
    is_volume_horario_anomalo: int = 0
    is_crm_unico: int = 0
    is_crm_multiplo: int = 0

class CrmHourlyEventSchema(BaseModel):
    dt_janela: date
    tipo: str
    hora_inicio: str
    hora_fim: str
    minuto_inicio: int
    minuto_fim: int
    severidade: Optional[str] = None
    id_medico: Optional[str] = None
    nu_crms_distintos: Optional[int] = None

class CrmHourlyProfileResponse(BaseModel):
    cnpj: str
    points: List[CrmHourlyPointSchema]
    events: List[CrmHourlyEventSchema] = []
    from_cache: bool = False
    read_time_ms: Optional[float] = None
    query_time_ms: Optional[float] = None
    save_time_ms: Optional[float] = None

# ── Dados Cadastrais e Geográficos ─────────────────────
class DadosFarmaciaSchema(BaseModel):
    cnpj: str
    razao_social: Optional[str] = None
    nome_fantasia: Optional[str] = None
    is_matriz: Optional[bool] = False
    tipo_logradouro: Optional[str] = None
    logradouro: Optional[str] = None
    numero: Optional[str] = None
    complemento: Optional[str] = None
    bairro: Optional[str] = None
    cep: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    id_ibge7: Optional[str] = None
    id_cnae_principal: Optional[str] = None
    cnae_principal: Optional[str] = None
    id_cnae_secundario: Optional[str] = None
    cnae_secundario: Optional[str] = None
    data_abertura: Optional[datetime] = None
    data_processamento: Optional[datetime] = None
    natureza_juridica: Optional[str] = None
    capital_social: Optional[float] = 0.0
    # Dados adicionais de identidade para o Quadro 01 da Nota Técnica
    telefone_1: Optional[str] = None
    telefone_2: Optional[str] = None
    email: Optional[str] = None
    # UF e Município (conveniência para o objeto de cadastro)
    uf: Optional[str] = None
    municipio: Optional[str] = None
    situacao_rf: Optional[str] = None
    porte_empresa: Optional[str] = None

class SocioSchema(BaseModel):
    cnpj: str
    cpf_cnpj_socio: str
    nome_socio: Optional[str] = None
    indicador_socio: Optional[str] = None
    municipio: Optional[str] = None
    uf: Optional[str] = None
    descricao_qualificacao: Optional[str] = None
    data_entrada_sociedade: Optional[date] = None
    data_exclusao_sociedade: Optional[date] = None
    percentual_qualificacao: Optional[float] = 0.0
    # Representante Legal
    cpf_representante: Optional[str] = None
    id_qualificacao_representante: Optional[int] = None
    nome_representante: Optional[str] = None
    descricao_qualificacao_representante: Optional[str] = None
    # Datas de Nascimento (Novidade)
    data_nascimento_socio: Optional[date] = None
    data_nascimento_representante: Optional[date] = None

class SociosResponse(BaseModel):
    cnpj: str
    socios: List[SocioSchema]
    data_processamento: Optional[date] = None
    from_cache: bool = False

# ── Teia Societária (Grafos) ───────────────────────────
class NetworkNodeSchema(BaseModel):
    id: str
    label: str
    type: str                 # 'PF' | 'PJ_ALVO' | 'PJ_FARMACIA_POPULAR' | 'PJ_OUTRAS_FARMACIAS' | 'PJ_DEMAIS_EMPRESAS'
    razao_social: Optional[str] = None
    nome_fantasia: Optional[str] = None
    id_cnae_principal: Optional[int] = None
    municipio: Optional[str] = None
    uf: Optional[str] = None
    situacao_rf: Optional[str] = None
    is_ativo: bool = True

class NetworkEdgeSchema(BaseModel):
    id: str
    source: str               # ID do nó de origem
    target: str               # ID do nó de destino
    label: Optional[str] = None # Ex: '10.00%'
    type: str = "socio"       # 'socio' | 'representante'
    is_ativo: bool = True

class NetworkResponse(BaseModel):
    cnpj: str
    nodes: List[NetworkNodeSchema]
    edges: List[NetworkEdgeSchema]
    query_time_ms: Optional[float] = None


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
    from_cache: bool = False
    read_time_ms: Optional[float] = None
    query_time_ms: Optional[float] = None
    save_time_ms: Optional[float] = None


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


# ── Drill-down da Análise Horária (Raio-X de Transações) ─────────────────────────

class CrmHourlyTransactionSchema(BaseModel):
    """Uma prescrição real capturada no Data Mart de anomalias horárias."""
    data_hora: str
    num_autorizacao: str
    id_medico: str
    codigo_barra: str
    valor_pago: float
    produto: Optional[str] = None
    principio_ativo: Optional[str] = None


class CrmUnicoAlertaSchema(BaseModel):
    """Médico que disparou alerta de concentração num dia específico."""
    id_medico: str
    hr_janela: int
    nu_prescricoes_dia: int
    nu_minutos_dia: int
    taxa_hora: float
    ritmo_hora: float
    ritmo_qtd: int
    ritmo_minutos: int
    severidade: Optional[str] = None
    dt_ini_hora: Optional[str] = None
    dt_fim_hora: Optional[str] = None


# ── Evolução Mensal por GTIN ─────────────────────────────────────────────────

class CrmMultiploAlertaSchema(BaseModel):
    """Alerta coordenado de prescricoes envolvendo multiplos CRMs num intervalo."""
    dt_janela: str
    hr_janela: Optional[int] = None
    nu_prescricoes: int = 0
    nu_crms: int = 0
    ritmo_hora: float = 0
    ritmo_qtd: int = 0
    ritmo_minutos: int = 0
    severidade: Optional[str] = None
    dt_ini_hora: Optional[str] = None
    dt_fim_hora: Optional[str] = None

class CrmRaioXResponse(BaseModel):
    """Contrato unificado do Raio-X de auditoria CRM."""
    cnpj: str
    dt_janela: str
    hour: Optional[int] = None
    transactions: List[CrmHourlyTransactionSchema]
    alertas_unico: List[CrmUnicoAlertaSchema] = Field(default_factory=list)
    alertas_multi: List[CrmMultiploAlertaSchema] = Field(default_factory=list)
    from_cache: bool = False
    read_time_ms: Optional[float] = None

class MesMensalGtinItem(BaseModel):
    mes: str                          # "YYYY-MM"
    qnt_vendas: int
    qnt_vendas_sem_comprovacao: int
    valor_vendas: float
    valor_sem_comprovacao: float
    pct_sem_comprovacao: float        # 0–100

class EvolucaoMensalGtinResponse(BaseModel):
    meses: List[MesMensalGtinItem]
    from_cache: bool = False
    query_time_ms: Optional[float] = None
    save_time_ms: Optional[float] = None
    read_time_ms: Optional[float] = None


# ── Detalhamento Mensal de GTINs (Raio-X Mensal) ─────────────────────────────
class GtinDetalhamentoMensalItem(BaseModel):
    gtin: str
    medicamento: Optional[str] = None
    principio_ativo: Optional[str] = None
    produto: Optional[str] = None
    laboratorio: Optional[str] = None
    qnt_vendas: int = 0
    qnt_vendas_sem_comprovacao: int = 0
    valor_vendas: float = 0.0
    valor_sem_comprovacao: float = 0.0
    pct_sem_comprovacao: float = 0.0

class GtinDetalhamentoMensalSummary(BaseModel):
    total_gtins: int = 0
    gtins_irregulares: int = 0
    gtins_regulares: int = 0

class GtinDetalhamentoMensalResponse(BaseModel):
    cnpj: str
    periodo: str
    summary: GtinDetalhamentoMensalSummary
    ranking: List[GtinDetalhamentoMensalItem]
    from_cache: bool = False
    read_time_ms: Optional[float] = None

