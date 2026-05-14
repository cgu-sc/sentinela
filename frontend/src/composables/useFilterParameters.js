import { useFilterStore } from '../stores/filters';

/**
 * Compatibility layer for callers that still consume filters through a composable.
 * The normalized API filter contract now lives in the Pinia filter store.
 */
export function useFilterParameters() {
  const filterStore = useFilterStore();

  function getApiParams() {
    return { ...filterStore.apiParams };
  }

  function isPeriodoValido() {
    return Boolean(filterStore.isPeriodoValido);
  }

  return { getApiParams, isPeriodoValido };
}
