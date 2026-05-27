from ._cache import (
    _get_cnpj_cache_dir,
    _known_cnpj_dirs,
)
from cache_producers.crm import (
    sync_crm_raiox_tx,
    sync_mediana_autorizacoes_horaria,
    sync_mediana_autorizacoes_horaria_movel,
)
from cache_producers.network import (
    sync_network,
)
from .crm import (
    get_crm_data,
    get_crm_medico_alertas,
    get_crm_raio_x,
    get_crm_timeline_dataset,
)
from .dashboard import (
    get_dashboard_data,
    get_producao_semestral_data,
    get_rede_por_cnpj_raiz,
    get_resultado_sentinela,
)
from .bootstrap import get_cnpj_bootstrap
from .falecidos import get_falecidos_data, get_timeline_cpf
from .farmacia import get_cnpj_access_status, get_dados_farmacia, get_movimentacao_data
from .fator_risco import get_fator_risco_data
from .socios import get_socios_farmacia
from .network import (
    get_teia_grafo_nivel2, 
    get_teia_grafo_nivel3_expansao, 
    get_teia_grafo_nivel4_expansao,
    get_teia_grafo_nivel3_full,
    get_teia_grafo_nivel4_full,
)
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
    get_indicadores_analise_cnpjs,
)
from .regional import (
    get_cnpj_lookup,
    get_metric_percentiles,
    get_metric_percentiles_animation,
    get_regional_benchmarking,
    get_regional_benchmarking_animation,
)
from .nota_tecnica import generate_nota_tecnica
from .volume_atipico import (
    get_volume_atipico_id_cnpjs_df,
    get_volume_atipico_period_metrics,
)

__all__ = ['AnalyticsService', 'INDICATOR_MAPPING', '_INDICATOR_FLAGS']


class AnalyticsService:
    _known_cnpj_dirs = _known_cnpj_dirs
    _get_cnpj_cache_dir = staticmethod(_get_cnpj_cache_dir)
    get_cnpj_bootstrap = staticmethod(get_cnpj_bootstrap)
    get_dashboard_data = staticmethod(get_dashboard_data)
    get_producao_semestral_data = staticmethod(get_producao_semestral_data)
    get_resultado_sentinela = staticmethod(get_resultado_sentinela)
    get_rede_por_cnpj_raiz = staticmethod(get_rede_por_cnpj_raiz)
    get_evolucao_financeira = staticmethod(get_evolucao_financeira)
    get_evolucao_mensal_gtin = staticmethod(get_evolucao_mensal_gtin)
    get_gtin_ranking_periodo = staticmethod(get_gtin_ranking_periodo)
    get_indicadores = staticmethod(get_indicadores)
    get_indicadores_analise = staticmethod(get_indicadores_analise)
    get_indicadores_analise_cnpjs = staticmethod(get_indicadores_analise_cnpjs)
    get_falecidos_data = staticmethod(get_falecidos_data)
    get_timeline_cpf = staticmethod(get_timeline_cpf)
    get_fator_risco_data = staticmethod(get_fator_risco_data)
    get_regional_benchmarking = staticmethod(get_regional_benchmarking)
    get_regional_benchmarking_animation = staticmethod(get_regional_benchmarking_animation)
    get_crm_data = staticmethod(get_crm_data)
    get_crm_medico_alertas = staticmethod(get_crm_medico_alertas)
    get_crm_timeline_dataset = staticmethod(get_crm_timeline_dataset)
    sync_crm_raiox_tx = staticmethod(sync_crm_raiox_tx)
    sync_mediana_autorizacoes_horaria = staticmethod(sync_mediana_autorizacoes_horaria)
    sync_mediana_autorizacoes_horaria_movel = staticmethod(sync_mediana_autorizacoes_horaria_movel)
    get_crm_raio_x = staticmethod(get_crm_raio_x)
    get_dados_farmacia = staticmethod(get_dados_farmacia)
    get_cnpj_access_status = staticmethod(get_cnpj_access_status)
    get_movimentacao_data = staticmethod(get_movimentacao_data)
    get_socios_farmacia = staticmethod(get_socios_farmacia)
    get_teia_grafo_nivel2 = staticmethod(get_teia_grafo_nivel2)
    get_teia_grafo_nivel3_expansao = staticmethod(get_teia_grafo_nivel3_expansao)
    get_teia_grafo_nivel4_expansao = staticmethod(get_teia_grafo_nivel4_expansao)
    get_teia_grafo_nivel3_full = staticmethod(get_teia_grafo_nivel3_full)
    get_teia_grafo_nivel4_full = staticmethod(get_teia_grafo_nivel4_full)
    sync_network = staticmethod(sync_network)
    get_metric_percentiles = staticmethod(get_metric_percentiles)
    get_metric_percentiles_animation = staticmethod(get_metric_percentiles_animation)
    get_cnpj_lookup = staticmethod(get_cnpj_lookup)
    generate_nota_tecnica = staticmethod(generate_nota_tecnica)
    get_volume_atipico_id_cnpjs_df = staticmethod(get_volume_atipico_id_cnpjs_df)
    get_volume_atipico_period_metrics = staticmethod(get_volume_atipico_period_metrics)
