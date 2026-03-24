import { defineStore } from 'pinia';
import axios from 'axios';

export const useDashboardStore = defineStore('dashboard', {
  state: () => ({
    kpis: [],
    nationalAnalysis: [],
    isLoading: false,
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
        const response = await axios.get('http://localhost:8000/api/v1/dashboard/');
        this.kpis = response.data.kpis;
        this.nationalAnalysis = response.data.national_analysis;
        this.lastSync = new Date();
      } catch (err) {
        console.error('Erro ao buscar resumo do dashboard:', err);
        this.error = 'Não foi possível carregar os KPIs estratégicos.';
      } finally {
        this.isLoading = false;
      }
    }
  },

  getters: {
    // Podemos formatar valores ou criar sub-filtros aqui
    getKpiById: (state) => (id) => state.kpis.find(k => k.id === id)
  }
});
