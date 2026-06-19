import { onScopeDispose, watch } from 'vue';
import { useFilterStore } from '@/stores/filters';
import { useRiskIndicatorsStore } from '@/stores/riskIndicators';

const ESTABELECIMENTO_FETCH_DEBOUNCE_MS = 450;

/**
 * Orquestra o fetch da analise de indicadores reagindo aos filtros globais.
 */
export function useRiskIndicatorAnalysis() {
  const filterStore = useFilterStore();
  const riskIndicatorsStore = useRiskIndicatorsStore();
  let estabelecimentoFetchTimer = null;
  let lastEstabelecimentoKey = filterStore.estabelecimentoFilterKey;

  function getRiskIndicatorParams() {
    return { ...filterStore.indicadoresApiParams };
  }

  function getRiskIndicatorTableParams() {
    return { ...filterStore.indicadoresTabelaApiParams };
  }

  function fetchRiskIndicator(indicatorKey) {
    riskIndicatorsStore.fetchRiskIndicatorSummary(indicatorKey, getRiskIndicatorParams());
    riskIndicatorsStore.fetchRiskIndicatorEstablishments(indicatorKey, getRiskIndicatorTableParams(), { page: 1 });
  }

  function fetchRiskIndicatorEstablishmentsPage(indicatorKey, tableState = {}) {
    riskIndicatorsStore.fetchRiskIndicatorEstablishments(indicatorKey, getRiskIndicatorTableParams(), tableState);
  }

  watch(
    () => [filterStore.indicadoresTabelaApiParamsKey, riskIndicatorsStore.preferencesLoaded],
    () => {
      if (!riskIndicatorsStore.preferencesLoaded) return;

      const run = () => {
        if (riskIndicatorsStore.selectedRiskIndicator) {
          fetchRiskIndicator(riskIndicatorsStore.selectedRiskIndicator);
        }
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

  onScopeDispose(() => {
    clearTimeout(estabelecimentoFetchTimer);
  });

  return { fetchRiskIndicator, fetchRiskIndicatorEstablishmentsPage };
}
