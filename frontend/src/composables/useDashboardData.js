import { ref } from 'vue';
import axios from 'axios';

export function useDashboardData() {
  const kpis = ref([]);
  const nationalAnalysis = ref([]);
  const isLoading = ref(false);
  const error = ref(null);

  /**
   * Busca os dados consolidados do Dashboard na API FastAPI.
   * Centraliza a lógica de carregamento e tratamento de erros.
   */
  const fetchDashboardData = async () => {
    isLoading.value = true;
    error.value = null;
    try {
      // URL da API modularizada em backend/api/v1/dashboard
      const response = await axios.get('http://localhost:8000/api/v1/dashboard/');
      
      // Atualiza os estados reativos com dados reais do banco (via FastAPI)
      kpis.value = response.data.kpis;
      nationalAnalysis.value = response.data.national_analysis;
    } catch (err) {
      console.error('Erro ao buscar dados do dashboard:', err);
      error.value = 'Não foi possível conectar ao servidor. Verifique se o backend está rodando.';
    } finally {
      isLoading.value = false;
    }
  };

  return {
    kpis,
    nationalAnalysis,
    isLoading,
    error,
    fetchDashboardData
  };
}
