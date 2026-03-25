import { defineStore } from 'pinia';
import axios from 'axios';

export const useDashboardStore = defineStore('dashboard', {
  state: () => ({
    kpis: [],
    nationalAnalysis: [],
    fatorRisco: [],
    isLoading: false,
    fatorRiscoLoading: false,
    error: null,
    lastSync: null
  }),

  actions: {
    /**
     * Busca os dados estratégicos (KPIs e Agrupamento por UF) no Backend.
     * Esta API traz os dados já calculados (agregados) pelo SQL Server.
     */
    async fetchDashboardSummary() {
      this.isLoading = true;
      this.error = null;
      try {
        const response = await axios.get('http://127.0.0.1:8002/api/v1/dashboard/');
        this.kpis = response.data.kpis;
        this.nationalAnalysis = response.data.national_analysis;
        this.lastSync = new Date();
      } catch (err) {
        console.error('Erro ao buscar resumo do dashboard:', err);
        this.error = 'Não foi possível carregar os KPIs estratégicos.';
      } finally {
        this.isLoading = false;
      }
    },

    /**
     * Busca os dados do gráfico de Fator de Risco baseado num período customizado.
     * Se inicio/fim forem nulos, o backend retorna o acumulado histórico.
     */
    async fetchFatorRisco(inicio = null, fim = null) {
      this.fatorRiscoLoading = true;
      try {
        const params = {};
        if (inicio) params.data_inicio = inicio;
        if (fim) params.data_fim = fim;

        const response = await axios.get('http://127.0.0.1:8002/api/v1/dashboard/fator-risco', {
          params
        });
        this.fatorRisco = response.data.buckets;
      } catch (err) {
        console.error('Erro ao buscar fator de risco:', err);
      } finally {
        this.fatorRiscoLoading = false;
      }
    }
  },

  getters: {
    // Podemos formatar valores ou criar sub-filtros aqui
    getKpiById: (state) => (id) => state.kpis.find(k => k.id === id)
  }
});
