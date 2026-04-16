import { ref, watch } from 'vue';
import { useFilterStore } from '@/stores/filters';

/**
 * Mantém uma versão "congelada" dos dados que não se altera durante a animação global.
 * Útil para evitar flicker em componentes que não devem ser atualizados enquanto o usuário
 * está navegando rapidamente entre períodos (autoplay).
 * 
 * @param {Ref} sourceRef - A ref de dados original (ex: vindo de um store)
 * @param {Ref} loadingRef - A ref que indica se um novo fetch está em curso
 * @param {Object} options - Configurações adicionais
 * @returns {Ref} - Uma ref reativa com os dados congelados/estáveis
 */
export function useFrozenData(sourceRef, loadingRef, options = {}) {
  const filterStore = useFilterStore();
  
  // Se initialValue for passado, usamos ele. Caso contrário, tentamos pegar o valor atual da sourceRef.
  const getInitial = () => {
    if (options.initialValue !== undefined) return options.initialValue;
    return typeof sourceRef === 'function' ? sourceRef() : sourceRef.value;
  };

  const cachedData = ref(getInitial());

  watch(
    [typeof sourceRef === 'function' ? sourceRef : () => sourceRef.value, loadingRef],
    ([newData, loading]) => {
      // Regra central: se a animação global (autoplay) estiver ativa, 
      // ignoramos qualquer mudança nos dados para manter a UI estável.
      if (filterStore.isAnimating) return;

      // Só atualizamos o cache quando o carregamento termina. 
      if (!loading) {
        cachedData.value = newData;
      }
    },
    { immediate: true, deep: options.deep ?? false }
  );

  return cachedData;
}
