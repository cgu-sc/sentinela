const BASE_URL = import.meta.env.VITE_API_URL || 'http://127.0.0.1:8002';

export const API_ENDPOINTS = {
  analyticsResumo:      `${BASE_URL}/api/v1/analytics/resumo`,
  analyticsFatorRisco:  `${BASE_URL}/api/v1/analytics/faixas-risco`,
  analyticsResultados:  `${BASE_URL}/api/v1/analytics/resultados-detalhados`,
  targetsSummary:       `${BASE_URL}/api/v1/targets/summary`,
  geoLocalidades:       `${BASE_URL}/api/v1/geo/localidades`,
  analyticsEvolucao:    (cnpj) => `${BASE_URL}/api/v1/analytics/cnpj/${cnpj}/evolucao`,
  analyticsIndicadores: (cnpj) => `${BASE_URL}/api/v1/analytics/cnpj/${cnpj}/indicadores`,
  analyticsFalecidos:   (cnpj) => `${BASE_URL}/api/v1/analytics/cnpj/${cnpj}/falecidos`,
  analyticsCpfTimeline: (cpf, cnpj) => `${BASE_URL}/api/v1/analytics/cpf/${cpf}/timeline?cnpj=${cnpj}`,
  cacheRefresh: `${BASE_URL}/api/v1/cache/refresh`,
  cacheStatus: `${BASE_URL}/api/v1/cache/status`,
};

