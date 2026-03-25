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
     */
    async fetchFatorRisco(inicio = '2016-01-01', fim = '2024-12-01') {
      this.fatorRiscoLoading = true;
      try {
        const response = await axios.get('http://127.0.0.1:8002/api/v1/dashboard/fator-risco', {
          params: { data_inicio: inicio, data_fim: fim }
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
