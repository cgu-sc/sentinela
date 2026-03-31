import { ref } from 'vue';
import { API_ENDPOINTS } from '@/config/api';
import axios from 'axios';

/**
 * Gerencia o fetch do Mapa de Trilhas Temporais (Audit History) de um CPF.
 * Cacheia por CPF para evitar chamadas repetidas ao abrir o mesmo popover.
 */
export function useMultiCnpjTimeline() {
  const timelineData    = ref(null);   // MultiCnpjTimelineResponse
  const timelineLoading = ref(false);
  const timelineError   = ref(null);

  // Cache em memória: cpf -> dados
  const _cache = new Map();

  /**
   * Busca as transações reais de um CPF em todos os estabelecimentos.
   * @param {string} cpf  - CPF do paciente falecido
   * @param {string} cnpj - CNPJ do estabelecimento de referência
   */
  async function fetchTimeline(cpf, cnpj) {
    if (!cpf || !cnpj) return;

    const cacheKey = `${cpf}__${cnpj}`;
    if (_cache.has(cacheKey)) {
      timelineData.value = _cache.get(cacheKey);
      return;
    }

    timelineLoading.value = true;
    timelineError.value   = null;
    timelineData.value    = null;

    try {
      const { data } = await axios.get(API_ENDPOINTS.analyticsCpfTimeline(cpf, cnpj));
      _cache.set(cacheKey, data);
      timelineData.value = data;
    } catch (e) {
      console.error('Erro ao buscar timeline do CPF:', e);
      timelineError.value = e;
    } finally {
      timelineLoading.value = false;
    }
  }

  function clearTimeline() {
    timelineData.value    = null;
    timelineLoading.value = false;
    timelineError.value   = null;
  }

  return { timelineData, timelineLoading, timelineError, fetchTimeline, clearTimeline };
}
