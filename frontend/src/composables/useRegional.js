/**
 * useRegional.js
 * Composable para buscar os dados da aba Região de Saúde em CnpjDetailView.
 * Recebe o nome da região de saúde e retorna o payload completo (municípios + farmácias).
 */
import { ref } from 'vue';
import { API_ENDPOINTS } from '@/config/api';

export function useRegional() {
  const regionalData    = ref(null);
  const regionalLoading = ref(false);
  const regionalLoaded  = ref(false);

  /**
   * Busca os dados regionais para a região informada.
   * @param {string} nomeRegiao - Nome exato da Região de Saúde (ex: 'GRANDE FLORIANOPOLIS').
   * @param {string} uf - Sigla do estado (ex: 'SC').
   */
  const loadedRegion = ref(null);

  /**
   * @param {string|null} nomeRegiao - Nome da Região de Saúde, ou null para escopo estadual.
   * @param {string}      uf         - Sigla do estado (obrigatório quando nomeRegiao é null).
   */
  async function fetchRegional(nomeRegiao, uf, inicio = null, fim = null) {
    if (!nomeRegiao && !uf) return;
    const cacheKey = `${nomeRegiao ?? 'UF'}|${uf}|${inicio ?? ''}|${fim ?? ''}`;
    
    if (regionalLoaded.value && loadedRegion.value === cacheKey) {
      return;
    }

    try {
      regionalLoading.value = true;
      regionalLoaded.value  = false;
      
      let url = API_ENDPOINTS.analyticsRegionalBenchmarking(nomeRegiao, uf);
      if (inicio) url += `&data_inicio=${inicio}`;
      if (fim)    url += `&data_fim=${fim}`;

      const res = await fetch(url);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      regionalData.value = await res.json();
      loadedRegion.value = cacheKey;
    } catch (e) {
      console.error('❌ Erro ao buscar dados regionais:', e);
      regionalData.value = null;
    } finally {
      regionalLoading.value = false;
      regionalLoaded.value  = true;
    }
  }

  return { regionalData, regionalLoading, regionalLoaded, fetchRegional };
}
