const BASE_URL = import.meta.env.VITE_API_URL || 'http://127.0.0.1:8002';

export const API_ENDPOINTS = {
  dashboardResumo:      `${BASE_URL}/api/v1/dashboard/resumo`,
  dashboardFatorRisco:  `${BASE_URL}/api/v1/dashboard/resultado-faixas-risco`,
  dashboardResultados:  `${BASE_URL}/api/v1/dashboard/resultados`,
  geoLocalidades:       `${BASE_URL}/api/v1/geo/localidades`,
  cacheRefresh:         `${BASE_URL}/api/v1/cache/refresh`,
};
