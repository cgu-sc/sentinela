import { computed } from 'vue';
import { useFilterStore } from '@/stores/filters';
import { useFrozenData } from '@/composables/useFrozenData';

/**
 * Centraliza a regra visual das abas que recarregam dados por periodo:
 * preserva o dado/erro anterior durante refetch, mostra loading apenas no
 * primeiro carregamento e marca refresh sem trocar a tela por estados vazios.
 */
export function useStableTabState(dataRef, loadingRef, errorRef, options = {}) {
  const filterStore = useFilterStore();
  const cachedData = useFrozenData(dataRef, loadingRef, options);

  const hasCachedData = computed(() => {
    if (typeof options.hasCachedData === 'function') {
      return options.hasCachedData(cachedData.value);
    }
    return cachedData.value !== null && cachedData.value !== undefined;
  });

  const shouldShowInitialLoading = computed(() =>
    loadingRef.value &&
    !hasCachedData.value &&
    !errorRef.value
  );

  const isRefreshing = computed(() =>
    loadingRef.value &&
    hasCachedData.value &&
    !filterStore.isAnimating
  );

  return {
    cachedData,
    hasCachedData,
    shouldShowInitialLoading,
    isRefreshing,
  };
}
