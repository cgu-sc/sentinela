import { defineStore } from 'pinia';
import axios from 'axios';
import { API_ENDPOINTS } from '@/config/api';

let summaryAbortController = null;
let cnpjsAbortController = null;

export const useRiskIndicatorsStore = defineStore('riskIndicators', {
  state: () => ({
    /** Chave do indicador de risco selecionado. Restaurado das preferencias para manter o foco do auditor. */
    selectedRiskIndicator: null,
    preferencesLoaded: false,
    /** KPIs de resumo: total_critico, total_atencao, total_normal, total_sem_dados, mediana_reg, pct_acima_limiar */
    kpis: null,
    /** KPIs do escopo da tabela, util para filtro municipal sem perder o mapa da UF/regiao. */
    cnpjKpis: null,
    /** Array de { municipio, uf, id_ibge7, total_cnpjs, total_critico, pct_critico } */
    municipios: [],
    /** Pagina atual de CNPJs ranqueados no backend. */
    cnpjs: [],
    cnpjsTotal: 0,
    cnpjsPage: 1,
    cnpjsRows: 20,
    cnpjsSortField: 'val_sem_comp',
    cnpjsSortOrder: -1,
    isLoading: false,
    isTableLoading: false,
    error: null,
  }),

  actions: {
    async loadPreferences() {
      try {
        const { data } = await axios.get(API_ENDPOINTS.preferences);
        const ui = data?.ui;
        if (ui && typeof ui === 'object' && typeof ui.selectedRiskIndicator === 'string') {
          this.selectedRiskIndicator = ui.selectedRiskIndicator.trim() || null;
        }
      } catch (error) {
        console.warn('[riskIndicators] Nao foi possivel carregar preferencias do indicador:', error);
      } finally {
        this.preferencesLoaded = true;
      }
    },

    async saveSelectedRiskIndicator() {
      try {
        await axios.put(API_ENDPOINTS.preferencesUi, {
          ui: {
            selectedRiskIndicator: this.selectedRiskIndicator,
          },
        });
      } catch (error) {
        console.warn('[riskIndicators] Nao foi possivel salvar indicador selecionado:', error);
      }
    },

    setSelectedRiskIndicator(indicador) {
      if (!indicador) return;
      this.selectedRiskIndicator = indicador;
      this.saveSelectedRiskIndicator();
    },

    async fetchRiskIndicatorSummary(indicador, params = {}) {
      if (!indicador) return;
      this.setSelectedRiskIndicator(indicador);
      this.isLoading = true;
      this.error = null;

      if (summaryAbortController) {
        summaryAbortController.abort();
      }
      summaryAbortController = new AbortController();

      try {
        const response = await axios.get(API_ENDPOINTS.analyticsIndicadoresAnalise, {
          params: { indicador, ...params },
          signal: summaryAbortController.signal,
        });

        this.kpis = response.data.kpis;
        this.municipios = response.data.municipios ?? [];
      } catch (err) {
        if (axios.isCancel(err)) {
          return;
        }
        console.error('Erro ao buscar analise de indicadores:', err);
        this.error = 'Nao foi possivel carregar a analise do indicador.';
      } finally {
        this.isLoading = false;
      }
    },

    async fetchRiskIndicatorEstablishments(indicador, params = {}, tableState = {}) {
      if (!indicador) return;
      this.setSelectedRiskIndicator(indicador);

      const page = tableState.page ?? this.cnpjsPage;
      const pageSize = tableState.pageSize ?? this.cnpjsRows;
      const sortField = tableState.sortField ?? this.cnpjsSortField;
      const sortOrder = tableState.sortOrder ?? this.cnpjsSortOrder;

      this.isTableLoading = true;
      this.error = null;

      if (cnpjsAbortController) {
        cnpjsAbortController.abort();
      }
      cnpjsAbortController = new AbortController();

      try {
        const response = await axios.get(API_ENDPOINTS.analyticsIndicadoresAnaliseCnpjs, {
          params: {
            indicador,
            ...params,
            page,
            page_size: pageSize,
            sort_field: sortField,
            sort_order: sortOrder === 1 ? 'asc' : 'desc',
          },
          signal: cnpjsAbortController.signal,
        });

        this.cnpjs = response.data.items ?? [];
        this.cnpjKpis = response.data.kpis ?? null;
        this.cnpjsTotal = response.data.total ?? 0;
        this.cnpjsPage = response.data.page ?? page;
        this.cnpjsRows = response.data.page_size ?? pageSize;
        this.cnpjsSortField = response.data.sort_field ?? sortField;
        this.cnpjsSortOrder = response.data.sort_order === 'asc' ? 1 : -1;
      } catch (err) {
        if (axios.isCancel(err)) {
          return;
        }
        console.error('Erro ao buscar CNPJs do indicador:', err);
        this.error = 'Nao foi possivel carregar a tabela de farmacias do indicador.';
      } finally {
        this.isTableLoading = false;
      }
    },

    reset() {
      this.selectedRiskIndicator = null;
      this.saveSelectedRiskIndicator();
      this.kpis = null;
      this.cnpjKpis = null;
      this.municipios = [];
      this.cnpjs = [];
      this.cnpjsTotal = 0;
      this.cnpjsPage = 1;
      this.cnpjsRows = 20;
      this.cnpjsSortField = 'val_sem_comp';
      this.cnpjsSortOrder = -1;
      this.error = null;
    },
  },
});
