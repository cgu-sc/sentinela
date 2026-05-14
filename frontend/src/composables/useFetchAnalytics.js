/**
 * Centraliza a logica de busca dos dados de analytics.
 *
 * @param {Object} options
 * @param {boolean} options.includeFatorRisco - Incluir busca do grafico Fator Risco (default: false)
 * @param {boolean} options.includeProducaoSemestral - Incluir serie semestral de producao (default: false)
 */
import { onScopeDispose, watch } from 'vue';
import { useFilterStore } from '@/stores/filters';
import { useAnalyticsStore, buildAnalyticsParams } from '@/stores/analytics';

const ESTABELECIMENTO_FETCH_DEBOUNCE_MS = 450;

export function useFetchAnalytics({ includeFatorRisco = false, includeNationalContext = true, includeProducaoSemestral = false } = {}) {
  const filterStore = useFilterStore();
  const analyticsStore = useAnalyticsStore();

  const getApiParams = () => ({ ...filterStore.apiParams });
  const isPeriodoValido = () => Boolean(filterStore.isPeriodoValido);

  const fetchAll = () => {
    const filters = getApiParams();
    analyticsStore.fetchDashboardSummary(filters);
    if (includeFatorRisco) analyticsStore.fetchFatorRisco(filters);
    if (includeProducaoSemestral) analyticsStore.fetchProducaoSemestral(filters);
  };

  const fetchNacionalIfNeeded = () => {
    if (
      !includeNationalContext ||
      !isPeriodoValido() ||
      !filterStore.selectedUF ||
      filterStore.selectedUF === 'Todos'
    ) {
      return;
    }
    analyticsStore.fetchSentinelaUFNacional(getApiParams());
  };

  const isFresh = () => {
    const apiReadyParams = buildAnalyticsParams(getApiParams());
    const currentHash = JSON.stringify(apiReadyParams);
    return analyticsStore.lastParamsHash === currentHash;
  };

  let dashboardFirstRun = true;
  let nationalFirstRun = true;
  let estabelecimentoFetchTimer = null;
  let lastEstabelecimentoKey = filterStore.estabelecimentoFilterKey;

  watch(
    () => filterStore.apiParamsKey,
    () => {
      const run = () => {
        const skip = dashboardFirstRun && isFresh();
        if (isPeriodoValido()) {
          if (!skip) {
            fetchAll();
          } else {
            const filters = getApiParams();
            if (includeFatorRisco && !analyticsStore.fatorRisco.length) {
              analyticsStore.fetchFatorRisco(filters);
            }
            if (includeProducaoSemestral && !analyticsStore.producaoSemestral.length) {
              analyticsStore.fetchProducaoSemestral(filters);
            }
          }
        }
        dashboardFirstRun = false;
      };

      const estabelecimentoChanged = filterStore.estabelecimentoFilterKey !== lastEstabelecimentoKey;
      lastEstabelecimentoKey = filterStore.estabelecimentoFilterKey;
      clearTimeout(estabelecimentoFetchTimer);

      if (estabelecimentoChanged) {
        estabelecimentoFetchTimer = setTimeout(run, ESTABELECIMENTO_FETCH_DEBOUNCE_MS);
      } else {
        run();
      }
    },
    { immediate: true }
  );

  watch(
    () => `${filterStore.nationalContextApiParamsKey}|uf=${filterStore.selectedUF !== 'Todos'}`,
    () => {
      const skip = nationalFirstRun && isFresh();
      if (isPeriodoValido() && !skip) {
        fetchNacionalIfNeeded();
      }
      nationalFirstRun = false;
    },
    { immediate: true }
  );

  onScopeDispose(() => {
    clearTimeout(estabelecimentoFetchTimer);
  });

  return { fetchAll };
}
