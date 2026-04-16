const BASE_URL = import.meta.env.VITE_API_URL || 'http://127.0.0.1:8002';

export const API_ENDPOINTS = {
  analyticsResumo:      `${BASE_URL}/api/v1/analytics/resumo`,
  analyticsFatorRisco:  `${BASE_URL}/api/v1/analytics/faixas-risco`,
  analyticsResultados:  `${BASE_URL}/api/v1/analytics/resultados-detalhados`,
  analyticsRegionalBenchmarking: (regiao, uf) => {
    const params = new URLSearchParams();
    if (regiao) params.set('regiao_saude', regiao);
    if (uf)     params.set('uf', uf);
    return `${BASE_URL}/api/v1/analytics/regional-benchmarking?${params.toString()}`;
  },
  analyticsRegionalBenchmarkingAnimation: (regiao, uf, inicio, fim) => {
    const params = new URLSearchParams();
    if (regiao) params.set('regiao_saude', regiao);
    if (uf)     params.set('uf', uf);
    if (inicio) params.set('data_inicio', inicio);
    if (fim)    params.set('data_fim', fim);
    return `${BASE_URL}/api/v1/analytics/regional-benchmarking-animation?${params.toString()}`;
  },
  geoLocalidades:       `${BASE_URL}/api/v1/geo/localidades`,
  geoEstabelecimentos:  `${BASE_URL}/api/v1/geo/estabelecimentos`,
  analyticsEvolucao:    (cnpj) => `${BASE_URL}/api/v1/analytics/cnpj/${cnpj}/evolucao`,
  analyticsIndicadores: (cnpj) => `${BASE_URL}/api/v1/analytics/cnpj/${cnpj}/indicadores`,
  analyticsFalecidos:   (cnpj) => `${BASE_URL}/api/v1/analytics/cnpj/${cnpj}/falecidos`,
  analyticsPrescritores: (cnpj) => `${BASE_URL}/api/v1/analytics/cnpj/${cnpj}/prescritores`,
  analyticsCadastro: (cnpj) => `${BASE_URL}/api/v1/analytics/cnpj/${cnpj}/cadastro`,
  analyticsMovimentacao: (cnpj) => `${BASE_URL}/api/v1/analytics/cnpj/${cnpj}/movimentacao`,
  analyticsCnpjLookup: `${BASE_URL}/api/v1/analytics/cnpj-lookup`,
  analyticsMetricPercentiles: `${BASE_URL}/api/v1/analytics/metric-percentiles`,
  analyticsMetricPercentilesAnimation: (scope, uf, regioId, metric, inicio, fim) => {
    const params = new URLSearchParams({ scope });
    if (uf)      params.set('uf', uf);
    if (regioId) params.set('regiao_id', regioId);
    if (metric)  params.set('metric', metric);
    if (inicio)  params.set('data_inicio', inicio);
    if (fim)     params.set('data_fim', fim);
    return `${BASE_URL}/api/v1/analytics/metric-percentiles-animation?${params.toString()}`;
  },
  analyticsCpfTimeline: (cpf, cnpj) => `${BASE_URL}/api/v1/analytics/cpf/${cpf}/timeline?cnpj=${cnpj}`,
   analyticsIndicadoresAnalise: `${BASE_URL}/api/v1/analytics/indicadores-analise`,
  analyticsConfigThresholds: `${BASE_URL}/api/v1/analytics/config/thresholds`,
  cacheRefresh: `${BASE_URL}/api/v1/cache/refresh`,
  cacheStatus: `${BASE_URL}/api/v1/cache/status`,
};

