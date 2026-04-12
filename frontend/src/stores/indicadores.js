import { defineStore } from 'pinia';
import axios from 'axios';
import { API_ENDPOINTS } from '@/config/api';

export const useIndicadoresStore = defineStore('indicadores', {
  state: () => ({
    /** Chave do indicador selecionado (ex: 'auditado', 'teto'). null = nada selecionado. */
    selectedIndicador: null,
    /** KPIs de resumo: total_critico, total_atencao, total_normal, total_sem_dados, mediana_reg, pct_acima_limiar */
    kpis: null,
    /** Array de { municipio, uf, id_ibge7, total_cnpjs, total_critico, pct_critico } */
    municipios: [],
    /** Array de CNPJs ranqueados por risco_reg para o indicador selecionado */
    cnpjs: [],
    isLoading: false,
    error: null,
  }),

  actions: {
    /**
     * Busca análise cruzada de um indicador de risco no escopo geográfico atual.
     *
     * @param {string} indicador - Chave do indicador (ex: 'auditado')
     * @param {Object} params - Filtros geográficos e cadastrais (uf, regiao_saude, etc.)
     */
    async fetchIndicadorAnalise(indicador, params = {}) {
      if (!indicador) return;
      this.isLoading = true;
      this.error = null;
      try {
        const response = await axios.get(API_ENDPOINTS.analyticsIndicadoresAnalise, {
          params: { indicador, ...params },
        });
        this.selectedIndicador = indicador;
        this.kpis = response.data.kpis;
        this.municipios = response.data.municipios ?? [];
        this.cnpjs = response.data.cnpjs ?? [];
      } catch (err) {
        console.error('Erro ao buscar análise de indicadores:', err);
        this.error = 'Não foi possível carregar a análise do indicador.';
      } finally {
        this.isLoading = false;
      }
    },

    reset() {
      this.selectedIndicador = null;
      this.kpis = null;
      this.municipios = [];
      this.cnpjs = [];
      this.error = null;
    },
  },
});
