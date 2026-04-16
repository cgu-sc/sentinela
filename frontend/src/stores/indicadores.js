import { defineStore } from 'pinia';
import axios from 'axios';
import { API_ENDPOINTS } from '@/config/api';

const STORAGE_KEY = 'sentinela_indicadores_selected';
let abortController = null;

export const useIndicadoresStore = defineStore('indicadores', {
  state: () => ({
    /** Chave do indicador selecionado. Restaurado do storage para manter o foco do auditor. */
    selectedIndicador: localStorage.getItem(STORAGE_KEY) || null,
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
    async fetchIndicadorAnalise(indicador, params = {}) {
      if (!indicador) return;
      
      this.selectedIndicador = indicador;
      localStorage.setItem(STORAGE_KEY, indicador);
      
      this.isLoading = true;
      this.error = null;

      if (abortController) {
        abortController.abort();
      }
      abortController = new AbortController();

      try {
        const response = await axios.get(API_ENDPOINTS.analyticsIndicadoresAnalise, {
          params: { indicador, ...params },
          signal: abortController.signal,
        });
        
        this.kpis = response.data.kpis;
        this.municipios = response.data.municipios ?? [];
        this.cnpjs = response.data.cnpjs ?? [];
      } catch (err) {
        if (axios.isCancel(err)) {
          return;
        }
        console.error('Erro ao buscar análise de indicadores:', err);
        this.error = 'Não foi possível carregar a análise do indicador.';
      } finally {
        this.isLoading = false;
      }
    },

    reset() {
      this.selectedIndicador = null;
      localStorage.removeItem(STORAGE_KEY);
      this.kpis = null;
      this.municipios = [];
      this.cnpjs = [];
      this.error = null;
    },
  },
});
