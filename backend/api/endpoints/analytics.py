from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from typing import List, Optional
from datetime import date
from database import get_db, engine
from ..schemas.analytics import (
    AnalyticsResponse, ResultadoSentinelaSchema, FatorRiscoResponseSchema,
    RedeEstabelecimentoSchema, EvolucaoFinanceiraResponse, IndicadoresResponse,
    FalecidosResponse, MultiCnpjTimelineResponse, RegionalResponse, RegionalAnimationResponse,
    PrescritoresResponse, DadosFarmaciaSchema, MovimentacaoResponse, IndicadorAnaliseResponse
)
from ..services.analytics import AnalyticsService

router = APIRouter()


@router.get("/cnpj/{cnpj}/cadastro", response_model=DadosFarmaciaSchema)
def get_dados_farmacia(cnpj: str):
    """Retorna os dados cadastrais e geográficos (endereço, lat/lon) para um CNPJ."""
    return AnalyticsService.get_dados_farmacia(cnpj)

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
    unidade_pf: Optional[str] = Query(None),
    razao_social: Optional[str] = Query(None),
    db: Session = Depends(get_db)
):
    return AnalyticsService.get_dashboard_data(db, data_inicio, data_fim, perc_min, perc_max, val_min, uf, regiao_saude, municipio, situacao_rf, conexao_ms, porte_empresa, grande_rede, cnpj_raiz, unidade_pf, razao_social)

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
    unidade_pf: Optional[str] = Query(None),
    razao_social: Optional[str] = Query(None),
    db: Session = Depends(get_db)
):
    return AnalyticsService.get_fator_risco_data(db, data_inicio, data_fim, perc_min, perc_max, val_min, uf, regiao_saude, municipio, situacao_rf, conexao_ms, porte_empresa, grande_rede, cnpj_raiz, unidade_pf, razao_social)

@router.get("/cnpj/{cnpj}/evolucao", response_model=EvolucaoFinanceiraResponse)
def get_evolucao_financeira(
    cnpj: str,
    data_inicio: Optional[date] = Query(None),
    data_fim: Optional[date] = Query(None),
):
    """Retorna a série semestral de valores financeiros para um CNPJ, com recorte temporal opcional."""
    return AnalyticsService.get_evolucao_financeira(cnpj, data_inicio, data_fim)

@router.get("/cnpj/{cnpj}/indicadores", response_model=IndicadoresResponse)
def get_indicadores(cnpj: str):
    """Retorna os indicadores detalhados para um CNPJ."""
    return AnalyticsService.get_indicadores(cnpj)

@router.get("/cnpj/{cnpj}/falecidos", response_model=FalecidosResponse)
def get_falecidos(cnpj: str):
    """Retorna os dados detalhados de vendas para falecidos para um CNPJ."""
    return AnalyticsService.get_falecidos_data(cnpj)

@router.get("/rede/{cnpj_raiz}", response_model=List[RedeEstabelecimentoSchema])
def get_rede_estabelecimentos(cnpj_raiz: str):
    """Retorna todos os estabelecimentos de uma rede dado o CNPJ raiz (8 dígitos)."""
    raiz = cnpj_raiz.replace(".", "").replace("/", "").replace("-", "")[:8]
    return AnalyticsService.get_rede_por_cnpj_raiz(raiz)

@router.get("/cpf/{cpf}/timeline", response_model=MultiCnpjTimelineResponse)
def get_cpf_timeline(
    cpf: str,
    cnpj: str = Query(..., description="CNPJ de referência (estabelecimento de origem)")
):
    """
    Retorna todas as transações reais de um CPF falecido em todos os estabelecimentos
    detectados. Usado no Mapa de Trilhas Temporais (Audit History).
    """
    return AnalyticsService.get_timeline_cpf(cnpj_referencia=cnpj, cpf=cpf)

@router.get("/regional-benchmarking", response_model=RegionalResponse)
def get_regional_benchmarking(
    regiao_saude: Optional[str] = Query(None, description="Nome da Região de Saúde (ex: 'GRANDE FLORIANOPOLIS'). Omitir para escopo estadual."),
    uf: Optional[str] = Query(None, description="Sigla do Estado (ex: 'SC')"),
    data_inicio: Optional[date] = Query(None),
    data_fim: Optional[date] = Query(None),
):
    """
    Retorna o resumo municipal e o ranking de farmácias por risco (Benchmarking Regional).
    - Com regiao_saude: filtra pela região de saúde (+ UF opcional para desambiguação).
    - Sem regiao_saude: filtra por UF inteiro (escopo estadual).
    """
    return AnalyticsService.get_regional_benchmarking(regiao_saude, uf, data_inicio, data_fim)


@router.get("/regional-benchmarking-animation", response_model=RegionalAnimationResponse)
def get_regional_benchmarking_animation(
    regiao_saude: Optional[str] = Query(None, description="Nome da Região de Saúde. Omitir para escopo estadual."),
    uf: Optional[str] = Query(None, description="Sigla do Estado (ex: 'SC')"),
    data_inicio: Optional[date] = Query(None),
    data_fim: Optional[date] = Query(None),
):
    """
    Retorna todos os trimestres do período em uma única chamada.
    Usado pela animação do scatter de posicionamento regional — evita N round-trips.
    """
    return AnalyticsService.get_regional_benchmarking_animation(regiao_saude, uf, data_inicio, data_fim)


@router.get("/cnpj/{cnpj}/prescritores", response_model=PrescritoresResponse)
def get_prescritores(cnpj: str):
    """Retorna os dados detalhados e KPIs de prescritores (CRMs) atuantes no CNPJ."""
    return AnalyticsService.get_prescritores_data(cnpj)

@router.get("/indicadores-analise", response_model=IndicadorAnaliseResponse)
def get_indicadores_analise(
    indicador: str = Query(..., description="Chave do indicador (ex: 'auditado', 'teto', 'vendas_rapidas')"),
    uf: Optional[str] = Query(None),
    regiao_saude: Optional[str] = Query(None),
    municipio: Optional[str] = Query(None),
    situacao_rf: Optional[str] = Query(None),
    conexao_ms: Optional[str] = Query(None),
    porte_empresa: Optional[str] = Query(None),
    grande_rede: Optional[str] = Query(None),
    cnpj_raiz: Optional[str] = Query(None),
    unidade_pf: Optional[str] = Query(None),
    perc_min: Optional[float] = Query(None),
    perc_max: Optional[float] = Query(None),
    val_min: Optional[float] = Query(None),
):
    """
    Análise cruzada de um indicador: retorna KPIs, mapa municipal e CNPJs ranqueados.
    Filtros de período não se aplicam (snapshot) — mas limites de valor e percentual funcionam.
    """
    return AnalyticsService.get_indicadores_analise(
        indicador, uf, regiao_saude, municipio,
        situacao_rf, conexao_ms, porte_empresa, grande_rede, cnpj_raiz, unidade_pf,
        perc_min, perc_max, val_min
    )


@router.get("/cnpj/{cnpj}/movimentacao", response_model=MovimentacaoResponse)
def get_movimentacao(
    cnpj: str,
    check_cache: bool = Query(False, description="Se True, retorna vazio caso não exista cache no servidor.")
):
    """
    Retorna a Memória de Cálculo processada (Movimentação por GTIN) de um CNPJ.

    - **Primeira chamada**: busca do SQL Server (`memoria_calculo_consolidada`),
      processa a lógica de linhas e salva cache Parquet.
    - **Chamadas subsequentes**: carrega do cache Parquet local (< 1s).
    - **Parâmetro check_cache**: permite carregar apenas se já existir cache, sem disparar processamento.
    """
    return AnalyticsService.get_movimentacao_data(cnpj, engine, check_cache=check_cache)
@router.get("/cnpj-lookup")
def get_cnpj_lookup():
    """Retorna lista slim [{cnpj, razao_social}] para autocomplete no frontend."""
    return AnalyticsService.get_cnpj_lookup()

@router.get("/metric-percentiles")
def get_metric_percentiles(
    scope: str = Query(..., description="Escopo: 'regiao', 'uf' ou 'brasil'"),
    uf: Optional[str] = Query(None),
    regiao_id: Optional[str] = Query(None),
    metric: str = Query("score", description="Métrica: 'score' ou 'percentual_sem_comprovacao'"),
    data_inicio: Optional[date] = Query(None),
    data_fim: Optional[date] = Query(None),
):
    """Retorna os percentis de score de risco ou não comprovação para o escopo selecionado."""
    return AnalyticsService.get_metric_percentiles(scope, uf, regiao_id, metric, data_inicio, data_fim)
