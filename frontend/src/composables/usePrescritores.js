import { ref } from 'vue';
import { API_ENDPOINTS } from '@/config/api';
import axios from 'axios';

/**
 * Gerencia o fetch e estado dos dados de análise de CRMs (Prescritores) de um CNPJ.
 * Lazy: só carrega quando `fetchPrescritores(cnpj)` é chamado pela primeira vez.
 */
export function usePrescritores() {
  const prescritoresData    = ref(null);
  const prescritoresLoading = ref(false);
  const prescritoresLoaded  = ref(false);

  async function fetchPrescritores(cnpj) {
    if (prescritoresLoaded.value) return;
    prescritoresLoading.value = true;
    try {
      const { data } = await axios.get(API_ENDPOINTS.analyticsPrescritores(cnpj));
      prescritoresData.value = data;
      prescritoresLoaded.value = true;
    } catch (e) {
      console.error('Erro ao buscar dados de prescritores:', e);
    } finally {
      prescritoresLoading.value = false;
    }
  }

  return { prescritoresData, prescritoresLoading, prescritoresLoaded, fetchPrescritores };
}
