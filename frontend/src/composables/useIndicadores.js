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
  const indicadoresError   = ref(null);

  async function fetchIndicadores(cnpj) {
    if (indicadoresLoaded.value) return;
    indicadoresLoading.value = true;
    indicadoresError.value = null;
    try {
      const { data } = await axios.get(API_ENDPOINTS.analyticsIndicadores(cnpj));
      indicadoresData.value = data;
      indicadoresLoaded.value = true;
    } catch (e) {
      console.error('Erro ao buscar indicadores:', e);
      indicadoresError.value = 'Não foi possível carregar os dados. Verifique a conexão com o servidor.';
    } finally {
      indicadoresLoading.value = false;
    }
  }

  function resetIndicadores() {
    indicadoresData.value = null;
    indicadoresLoaded.value = false;
    indicadoresLoading.value = false;
    indicadoresError.value = null;
  }

  return { indicadoresData, indicadoresLoading, indicadoresLoaded, indicadoresError, fetchIndicadores, resetIndicadores };
}
