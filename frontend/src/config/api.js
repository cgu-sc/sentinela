const BASE_URL = import.meta.env.VITE_API_URL || 'http://127.0.0.1:8002';

export const API_ENDPOINTS = {
  analyticsResumo:      `${BASE_URL}/api/v1/analytics/resumo`,
  analyticsFatorRisco:  `${BASE_URL}/api/v1/analytics/faixas-risco`,
  analyticsProducaoSemestral: `${BASE_URL}/api/v1/analytics/producao-semestral`,
  analyticsRegionalBenchmarking: (uf, regiaoId = null, inicio = null, fim = null) => {
    const params = new URLSearchParams();
    if (uf)       params.set('uf', uf);
    if (regiaoId) params.set('regiao_id', String(regiaoId));
    if (inicio)   params.set('data_inicio', inicio);
    if (fim)      params.set('data_fim', fim);
    return `${BASE_URL}/api/v1/analytics/regional-benchmarking?${params.toString()}`;
  },
  analyticsRegionalBenchmarkingAnimation: (uf, inicio, fim, regiaoId = null) => {
    const params = new URLSearchParams();
    if (uf)       params.set('uf', uf);
    if (inicio)   params.set('data_inicio', inicio);
    if (fim)      params.set('data_fim', fim);
    if (regiaoId) params.set('regiao_id', String(regiaoId));
    return `${BASE_URL}/api/v1/analytics/regional-benchmarking-animation?${params.toString()}`;
  },
  geoLocalidades:       `${BASE_URL}/api/v1/geo/localidades`,
  geoEstabelecimentos:  `${BASE_URL}/api/v1/geo/estabelecimentos`,
  analyticsCnpjBootstrap: (cnpj) => `${BASE_URL}/api/v1/analytics/cnpj/${cnpj}/bootstrap`,
  analyticsEvolucao:    (cnpj) => `${BASE_URL}/api/v1/analytics/cnpj/${cnpj}/evolucao`,
  analyticsEvolucaoMensalGtin: (cnpj) => `${BASE_URL}/api/v1/analytics/cnpj/${cnpj}/evolucao-mensal-gtin`,
  analyticsGtinDetalhamentoMensal: (cnpj, periodo) => `${BASE_URL}/api/v1/analytics/cnpj/${cnpj}/gtin-detalhamento-mensal?periodo=${periodo}`,
  analyticsIndicadores: (cnpj) => `${BASE_URL}/api/v1/analytics/cnpj/${cnpj}/indicadores`,
  analyticsGeograficoOrigemUf: (cnpj) => `${BASE_URL}/api/v1/analytics/cnpj/${cnpj}/geografico/origem-uf`,
  analyticsIncompatibilidadePatologica: (cnpj) => `${BASE_URL}/api/v1/analytics/cnpj/${cnpj}/clinico/incompatibilidades`,
  analyticsFalecidos:   (cnpj) => `${BASE_URL}/api/v1/analytics/cnpj/${cnpj}/falecidos`,
  analyticsCrmData: (cnpj) => `${BASE_URL}/api/v1/analytics/cnpj/${cnpj}/crm-data`,
  analyticsCrmMedicoAlertas: (cnpj, idMedico) => `${BASE_URL}/api/v1/analytics/cnpj/${cnpj}/crm/medico-alertas/${encodeURIComponent(idMedico)}`,
  analyticsCrmTimelineDataset: (cnpj) => `${BASE_URL}/api/v1/analytics/cnpj/${cnpj}/crm/timeline-dataset`,
  analyticsCrmRaioX: (cnpj, dateStr, hour) => {
    let url = `${BASE_URL}/api/v1/analytics/cnpj/${cnpj}/crm/raio-x?date_str=${dateStr}`;
    if (hour != null) url += `&hour=${hour}`;
    return url;
  },
  analyticsCnpjStatus: (cnpj) => `${BASE_URL}/api/v1/analytics/cnpj/${cnpj}/status`,
  analyticsCadastro: (cnpj) => `${BASE_URL}/api/v1/analytics/cnpj/${cnpj}/cadastro`,
  analyticsSocios:   (cnpj) => `${BASE_URL}/api/v1/analytics/cnpj/${cnpj}/socios`,
  analyticsNetwork:  (cnpj) => `${BASE_URL}/api/v1/analytics/cnpj/${cnpj}/network`,
  analyticsNetworkExpand: (cnpj, targetCnpj) => `${BASE_URL}/api/v1/analytics/cnpj/${cnpj}/network/expand/${targetCnpj}`,
  analyticsNetworkLevel3: (cnpj) => `${BASE_URL}/api/v1/analytics/cnpj/${cnpj}/network/level/3`,
  analyticsNetworkLevel4: (cnpj) => `${BASE_URL}/api/v1/analytics/cnpj/${cnpj}/network/level/4`,
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
  analyticsIndicadoresAnaliseCnpjs: `${BASE_URL}/api/v1/analytics/indicadores-analise/cnpjs`,
  targetParkinsonMenor50: `${BASE_URL}/api/v1/targets/parkinson-menor-50`,
  analyticsClientPerf: `${BASE_URL}/api/v1/analytics/client-perf`,
  cacheRefresh: `${BASE_URL}/api/v1/cache/refresh`,
  cacheStatus: `${BASE_URL}/api/v1/cache/status`,
  analyticsNotaTecnica: (cnpj) => `${BASE_URL}/api/v1/analytics/cnpj/${cnpj}/nota-tecnica`,
  analyticsNotaTecnicaRegionais: `${BASE_URL}/api/v1/analytics/nota-tecnica/regionais`,
  preferences: `${BASE_URL}/api/v1/preferences`,
  preferencesFilters: `${BASE_URL}/api/v1/preferences/filters`,
  preferencesWatchlist: `${BASE_URL}/api/v1/preferences/watchlist`,
  preferencesUi: `${BASE_URL}/api/v1/preferences/ui`,
  preferencesNotaTecnica: `${BASE_URL}/api/v1/preferences/nota-tecnica`,
};

