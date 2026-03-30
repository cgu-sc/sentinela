import { ref } from 'vue';
import { API_ENDPOINTS } from '@/config/api';
import axios from 'axios';

/**
 * Gerencia o fetch e estado dos indicadores de risco de um CNPJ.
 * Lazy: só carrega quando `fetchIndicadores(cnpj)` é chamado pela primeira vez.
 */
export function useIndicadores() {
  const indicadoresData    = ref(null);
  const indicadoresLoading = ref(false);
  const indicadoresLoaded  = ref(false);

  async function fetchIndicadores(cnpj) {
    if (indicadoresLoaded.value) return;
    indicadoresLoading.value = true;
    try {
      const { data } = await axios.get(API_ENDPOINTS.analyticsIndicadores(cnpj));
      indicadoresData.value = data;
      indicadoresLoaded.value = true;
    } catch (e) {
      console.error('Erro ao buscar indicadores:', e);
    } finally {
      indicadoresLoading.value = false;
    }
  }

  return { indicadoresData, indicadoresLoading, indicadoresLoaded, fetchIndicadores };
}
