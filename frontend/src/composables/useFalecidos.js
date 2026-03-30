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

  async function fetchFalecidos(cnpj) {
    if (falecidosLoaded.value) return;
    falecidosLoading.value = true;
    try {
      const { data } = await axios.get(API_ENDPOINTS.analyticsFalecidos(cnpj));
      falecidosData.value = data;
      falecidosLoaded.value = true;
    } catch (e) {
      console.error('Erro ao buscar dados de falecidos:', e);
    } finally {
      falecidosLoading.value = false;
    }
  }

  return { falecidosData, falecidosLoading, falecidosLoaded, fetchFalecidos };
}
