from ._cache import (
    _get_cnpj_cache_dir,
    _known_cnpj_dirs,
    sync_crm_raiox_tx,
    sync_mediana_autorizacoes_horaria,
)
from .crm import (
    get_crm_data,
    get_crm_perfil_diario,
    get_crm_perfil_horario,
    get_crm_raio_x,
)
from .dashboard import (
    get_dashboard_data,
    get_rede_por_cnpj_raiz,
    get_resultado_sentinela,
)
from .falecidos import get_falecidos_data, get_timeline_cpf
from .farmacia import get_dados_farmacia, get_movimentacao_data
from .financeiro import (
    get_evolucao_financeira,
    get_evolucao_mensal_gtin,
    get_gtin_ranking_periodo,
)
from .indicadores import (
    INDICATOR_MAPPING,
    _INDICATOR_FLAGS,
    get_indicadores,
    get_indicadores_analise,
)
from .regional import (
    get_cnpj_lookup,
    get_fator_risco_data,
    get_metric_percentiles,
    get_metric_percentiles_animation,
    get_regional_benchmarking,
    get_regional_benchmarking_animation,
)
from .nota_tecnica import generate_nota_tecnica

__all__ = ['AnalyticsService', 'INDICATOR_MAPPING', '_INDICATOR_FLAGS']


class AnalyticsService:
    _known_cnpj_dirs = _known_cnpj_dirs
    _get_cnpj_cache_dir = staticmethod(_get_cnpj_cache_dir)
    get_dashboard_data = staticmethod(get_dashboard_data)
    get_resultado_sentinela = staticmethod(get_resultado_sentinela)
    get_rede_por_cnpj_raiz = staticmethod(get_rede_por_cnpj_raiz)
    get_evolucao_financeira = staticmethod(get_evolucao_financeira)
    get_evolucao_mensal_gtin = staticmethod(get_evolucao_mensal_gtin)
    get_gtin_ranking_periodo = staticmethod(get_gtin_ranking_periodo)
    get_indicadores = staticmethod(get_indicadores)
    get_indicadores_analise = staticmethod(get_indicadores_analise)
    get_falecidos_data = staticmethod(get_falecidos_data)
    get_timeline_cpf = staticmethod(get_timeline_cpf)
    get_fator_risco_data = staticmethod(get_fator_risco_data)
    get_regional_benchmarking = staticmethod(get_regional_benchmarking)
    get_regional_benchmarking_animation = staticmethod(get_regional_benchmarking_animation)
    get_crm_data = staticmethod(get_crm_data)
    get_crm_perfil_diario = staticmethod(get_crm_perfil_diario)
    get_crm_perfil_horario = staticmethod(get_crm_perfil_horario)
    sync_crm_raiox_tx = staticmethod(sync_crm_raiox_tx)
    sync_mediana_autorizacoes_horaria = staticmethod(sync_mediana_autorizacoes_horaria)
    get_crm_raio_x = staticmethod(get_crm_raio_x)
    get_dados_farmacia = staticmethod(get_dados_farmacia)
    get_movimentacao_data = staticmethod(get_movimentacao_data)
    get_metric_percentiles = staticmethod(get_metric_percentiles)
    get_metric_percentiles_animation = staticmethod(get_metric_percentiles_animation)
    get_cnpj_lookup = staticmethod(get_cnpj_lookup)
    generate_nota_tecnica = staticmethod(generate_nota_tecnica)
