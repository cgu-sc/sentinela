import { ref } from 'vue';
import { API_ENDPOINTS } from '@/config/api';
import axios from 'axios';

/**
 * Gerencia o fetch e estado dos dados de pacientes falecidos de um CNPJ.
 * Lazy: só carrega quando `fetchFalecidos(cnpj)` é chamado pela primeira vez.
 */
export function useFalecidos() {
  const falecidosData    = ref(null);
  const falecidosLoading = ref(false);
  const falecidosLoaded  = ref(false);
  const falecidosError   = ref(null);

  async function fetchFalecidos(cnpj) {
    if (falecidosLoaded.value) return;
    falecidosLoading.value = true;
    falecidosError.value = null;
    try {
      const { data } = await axios.get(API_ENDPOINTS.analyticsFalecidos(cnpj));
      falecidosData.value = data;
      falecidosLoaded.value = true;
    } catch (e) {
      console.error('Erro ao buscar dados de falecidos:', e);
      falecidosError.value = 'Não foi possível carregar os dados. Verifique a conexão com o servidor.';
    } finally {
      falecidosLoading.value = false;
    }
  }

  function resetFalecidos() {
    falecidosData.value = null;
    falecidosLoaded.value = false;
    falecidosLoading.value = false;
    falecidosError.value = null;
  }

  return { falecidosData, falecidosLoading, falecidosLoaded, falecidosError, fetchFalecidos, resetFalecidos };
}
