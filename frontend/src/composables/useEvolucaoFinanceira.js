import { ref } from 'vue';
import { API_ENDPOINTS } from '@/config/api';
import axios from 'axios';

/**
 * Gerencia o fetch e estado da evolução financeira semestral de um CNPJ.
 * Lazy: só carrega quando `fetchEvolucao(cnpj)` é chamado pela primeira vez.
 */
export function useEvolucaoFinanceira() {
  const evolucaoData    = ref(null);
  const evolucaoLoading = ref(false);
  const evolucaoLoaded  = ref(false);

  async function fetchEvolucao(cnpj) {
    if (evolucaoLoaded.value) return;
    evolucaoLoading.value = true;
    try {
      const { data } = await axios.get(API_ENDPOINTS.analyticsEvolucao(cnpj));
      evolucaoData.value = data;
      evolucaoLoaded.value = true;
    } catch (e) {
      console.error('Erro ao buscar evolução financeira:', e);
    } finally {
      evolucaoLoading.value = false;
    }
  }

  return { evolucaoData, evolucaoLoading, evolucaoLoaded, fetchEvolucao };
}
