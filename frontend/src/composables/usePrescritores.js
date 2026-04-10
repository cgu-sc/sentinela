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
  const prescritoresError   = ref(null);

  async function fetchPrescritores(cnpj) {
    if (prescritoresLoaded.value) return;
    prescritoresLoading.value = true;
    prescritoresError.value = null;
    try {
      const { data } = await axios.get(API_ENDPOINTS.analyticsPrescritores(cnpj));
      prescritoresData.value = data;
      prescritoresLoaded.value = true;
    } catch (e) {
      console.error('Erro ao buscar dados de prescritores:', e);
      prescritoresError.value = 'Não foi possível carregar os dados. Verifique a conexão com o servidor.';
    } finally {
      prescritoresLoading.value = false;
    }
  }

  function resetPrescritores() {
    prescritoresData.value = null;
    prescritoresLoaded.value = false;
    prescritoresLoading.value = false;
    prescritoresError.value = null;
  }

  return { prescritoresData, prescritoresLoading, prescritoresLoaded, prescritoresError, fetchPrescritores, resetPrescritores };
}
