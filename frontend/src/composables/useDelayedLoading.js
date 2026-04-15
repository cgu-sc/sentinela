import { ref, watch, onUnmounted } from 'vue';

/**
 * Retorna um ref booleano que só se torna `true` se `loadingRef` permanecer
 * verdadeiro por mais de `delay` ms. Requisições rápidas passam sem acionar
 * o indicador visual, evitando o flash em respostas instantâneas.
 *
 * @param {import('vue').Ref<boolean>} loadingRef - Ref do estado de loading
 * @param {number} delay - Tempo mínimo (ms) antes de mostrar o indicador
 */
export function useDelayedLoading(loadingRef, delay = 500) {
  const showRefreshing = ref(false);
  let timer = null;

  watch(loadingRef, (val) => {
    if (val) {
      timer = setTimeout(() => { showRefreshing.value = true; }, delay);
    } else {
      clearTimeout(timer);
      showRefreshing.value = false;
    }
  });

  onUnmounted(() => clearTimeout(timer));

  return showRefreshing;
}
