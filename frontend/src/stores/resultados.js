import { defineStore } from 'pinia';
import axios from 'axios';

export const useResultadoStore = defineStore('resultados', {
  state: () => ({
    resultados: [],
    isLoading: false,
    error: null,
    lastUpdated: null
  }),
  
  actions: {
    /**
     * Busca a base completa de resultados detalhados (resultado_sentinela)
     * e armazena globalmente no Pinia para uso em qualquer componente.
     */
    async fetchResultados() {
      this.isLoading = true;
      this.error = null;
      try {
        const response = await axios.get('http://localhost:8000/api/v1/dashboard/resultados');
        this.resultados = response.data;
        this.lastUpdated = new Date();
      } catch (err) {
        console.error('Erro ao carregar resultados sentinela:', err);
        this.error = 'Falha ao sincronizar dados com o servidor. Verifique a conexão do backend.';
      } finally {
        this.isLoading = false;
      }
    }
  },
  
  getters: {
    totalResultados: (state) => state.resultados.length,
    
    // Filtro por UF exemplo
    getByUF: (state) => (uf) => {
      if (uf === 'Todos') return state.resultados;
      return state.resultados.filter(r => r.uf === uf);
    }
  }
});
