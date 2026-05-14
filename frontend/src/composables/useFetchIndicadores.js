import { onScopeDispose, watch } from 'vue';
import { useFilterStore } from '@/stores/filters';
import { useIndicadoresStore } from '@/stores/indicadores';

const ESTABELECIMENTO_FETCH_DEBOUNCE_MS = 450;

/**
 * Orquestra o fetch da analise de indicadores reagindo aos filtros globais.
 */
export function useFetchIndicadores() {
  const filterStore = useFilterStore();
  const indicadoresStore = useIndicadoresStore();
  let estabelecimentoFetchTimer = null;
  let lastEstabelecimentoKey = filterStore.estabelecimentoFilterKey;

  function getIndicadorParams() {
    return { ...filterStore.indicadoresApiParams };
  }

  function getIndicadorTabelaParams() {
    return { ...filterStore.indicadoresTabelaApiParams };
  }

  function fetchForIndicador(indicadorKey) {
    indicadoresStore.fetchIndicadorAnalise(indicadorKey, getIndicadorParams());
    indicadoresStore.fetchIndicadorCnpjs(indicadorKey, getIndicadorTabelaParams(), { page: 1 });
  }

  function fetchCnpjsForIndicador(indicadorKey, tableState = {}) {
    indicadoresStore.fetchIndicadorCnpjs(indicadorKey, getIndicadorTabelaParams(), tableState);
  }

  watch(
    () => filterStore.indicadoresTabelaApiParamsKey,
    () => {
      const run = () => {
        if (indicadoresStore.selectedIndicador) {
          fetchForIndicador(indicadoresStore.selectedIndicador);
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

  return { fetchForIndicador, fetchCnpjsForIndicador };
}
