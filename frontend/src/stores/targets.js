import { defineStore } from 'pinia';
import axios from 'axios';
import { API_ENDPOINTS } from '@/config/api';
import { DEFAULT_TARGET_KEY, TARGET_GROUPS } from '@/config/targetConfig';
import { useFilterStore } from '@/stores/filters';

const STORAGE_KEY = 'sentinela_targets_selected';
let targetAbortController = null;

function allTargets() {
  return TARGET_GROUPS.flatMap(group => group.targets);
}

function getTargetMeta(key) {
  const target = allTargets().find(item => item.key === key);
  if (!target) throw new Error(`Alvo sem configuração: ${key}`);
  return target;
}

function getEnabledTargetMeta(key) {
  const target = getTargetMeta(key);
  if (!target.enabled) throw new Error(`Alvo desabilitado não pode ser selecionado: ${key}`);
  return target;
}

export const useTargetsStore = defineStore('targets', {
  state: () => {
    const storedTarget = localStorage.getItem(STORAGE_KEY) || DEFAULT_TARGET_KEY;
    const selectedTarget = allTargets().some(item => item.key === storedTarget && item.enabled)
      ? storedTarget
      : DEFAULT_TARGET_KEY;
    const meta = getEnabledTargetMeta(selectedTarget);

    return {
      selectedTarget,
      kpis: [],
      mapData: [],
      rows: [],
      totalRecords: 0,
      page: 1,
      rowsPerPage: 20,
      sortField: meta.defaultSortField,
      sortOrder: meta.defaultSortOrder,
      isLoading: false,
      isTableLoading: false,
      error: null,
      sourceNotice: meta.sourceStatus === 'pending' ? 'Fonte de dados do alvo ainda não conectada.' : null,
    };
  },

  getters: {
    selectedTargetMeta(state) {
      return getEnabledTargetMeta(state.selectedTarget);
    },

    targetKpis(state) {
      if (state.kpis.length > 0) return state.kpis;
      return [
        { label: 'Farmácias', value: '—' },
        { label: 'Valor incompatível', value: '—' },
        { label: 'CPFs envolvidos', value: '—' },
        { label: 'Municípios', value: '—' },
        { label: 'UFs', value: '—' },
      ];
    },
  },

  actions: {
    setSelectedTarget(key) {
      const meta = getEnabledTargetMeta(key);
      this.selectedTarget = key;
      this.page = 1;
      this.rowsPerPage = 20;
      this.sortField = meta.defaultSortField;
      this.sortOrder = meta.defaultSortOrder;
      this.kpis = [];
      this.mapData = [];
      this.rows = [];
      this.totalRecords = 0;
      this.error = null;
      this.sourceNotice = meta.sourceStatus === 'pending'
        ? 'Fonte de dados do alvo ainda não conectada.'
        : null;
      localStorage.setItem(STORAGE_KEY, key);
    },

    _buildParams() {
      const filterStore = useFilterStore();
      const params = { ...filterStore.indicadoresTabelaApiParams };
      params.page = this.page;
      params.page_size = this.rowsPerPage;
      params.sort_field = this.sortField;
      params.sort_order = this.sortOrder === 1 ? 'asc' : 'desc';
      return params;
    },

    async loadCurrentTarget() {
      const meta = this.selectedTargetMeta;
      if (meta.sourceStatus === 'pending') {
        this.kpis = [];
        this.mapData = [];
        this.rows = [];
        this.totalRecords = 0;
        this.sourceNotice = 'Fonte de dados do alvo ainda não conectada.';
        return;
      }

      if (meta.key !== 'parkinson_menor_50') {
        throw new Error(`Fonte de dados do alvo sem implementação: ${meta.key}`);
      }

      this.isLoading = true;
      this.isTableLoading = true;
      this.error = null;

      if (targetAbortController) {
        targetAbortController.abort();
      }
      targetAbortController = new AbortController();

      try {
        const response = await axios.get(API_ENDPOINTS[meta.endpoint], {
          params: this._buildParams(),
          signal: targetAbortController.signal,
        });

        this.kpis = response.data.kpis ?? [];
        this.mapData = response.data.mapa ?? [];
        this.rows = response.data.items ?? [];
        this.totalRecords = response.data.total ?? 0;
        this.page = response.data.page ?? this.page;
        this.rowsPerPage = response.data.page_size ?? this.rowsPerPage;
        this.sortField = response.data.sort_field ?? this.sortField;
        this.sortOrder = response.data.sort_order === 'asc' ? 1 : -1;
        this.sourceNotice = null;
      } catch (err) {
        if (axios.isCancel(err)) return;
        console.error('Erro ao carregar alvo:', err);
        this.error = 'Nao foi possivel carregar o alvo selecionado.';
      } finally {
        this.isLoading = false;
        this.isTableLoading = false;
      }
    },

    updateTableState(event = {}) {
      const rows = event.rows ?? this.rowsPerPage;
      const first = event.first ?? 0;
      this.rowsPerPage = rows;
      this.page = Math.floor(first / rows) + 1;
      this.sortField = event.sortField ?? this.sortField;
      this.sortOrder = event.sortOrder ?? this.sortOrder;
      this.loadCurrentTarget();
    },
  },
});
