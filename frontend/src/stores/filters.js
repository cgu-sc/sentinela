import { defineStore } from 'pinia';
import { ref, reactive, watch } from 'vue';
import axios from 'axios';
import { FILTER_DEFAULTS, FILTER_ALL_VALUE, TIMING } from '@/config/constants';
import { useGeoStore } from './geo';
import { API_ENDPOINTS } from '@/config/api';

const STORAGE_KEY = 'sentinela_filters';

function loadFromStorage() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw);
    // Rehydrate dates
    if (parsed.periodo) {
      parsed.periodo = parsed.periodo.map(d => d ? new Date(d) : null);
    }
    return parsed;
  } catch {
    return null;
  }
}

export const useFilterStore = defineStore('filters', () => {
  const saved = loadFromStorage();
  const geoStore = useGeoStore();

  // 1. FILTROS GLOBAIS
  const selectedUF = ref(saved?.selectedUF ?? FILTER_DEFAULTS.UF);
  const savedRegiao = saved?.selectedRegiaoSaude;
  const savedMunicipio = saved?.selectedMunicipio;
  const selectedRegiaoSaude = ref(
    savedRegiao && savedRegiao !== FILTER_ALL_VALUE && Number.isNaN(Number(savedRegiao))
      ? FILTER_DEFAULTS.REGIAO
      : (savedRegiao ?? FILTER_DEFAULTS.REGIAO)
  );
  const selectedMunicipio = ref(
    savedMunicipio && savedMunicipio !== FILTER_ALL_VALUE && Number.isNaN(Number(savedMunicipio))
      ? FILTER_DEFAULTS.MUNICIPIO
      : (savedMunicipio ?? FILTER_DEFAULTS.MUNICIPIO)
  );
  const selectedSituacao = ref(saved?.selectedSituacao ?? FILTER_DEFAULTS.SITUACAO);
  const selectedMS = ref(saved?.selectedMS ?? FILTER_DEFAULTS.MS);
  const selectedPorte = ref(saved?.selectedPorte ?? FILTER_DEFAULTS.PORTE);
  const selectedGrandeRede = ref(saved?.selectedGrandeRede ?? FILTER_DEFAULTS.GRANDE_REDE);
  const selectedUnidadePf = ref(saved?.selectedUnidadePf ?? FILTER_ALL_VALUE);
  const selectedCnpjRaiz = ref(saved?.selectedCnpjRaiz ?? '');
  const hoveredMunicipioName = ref(null);

  // 2. FILTROS DE FAIXA (RANGES)
  const percentualNaoComprovacaoRange = ref(saved?.percentualNaoComprovacaoRange ?? FILTER_DEFAULTS.PERCENTUAL_RANGE);
  const percentualNaoComprovacaoFilter = ref(saved?.percentualNaoComprovacaoFilter ?? FILTER_DEFAULTS.PERCENTUAL_RANGE);
  const valorMinSemComp = ref(typeof saved?.valorMinSemComp === 'number' ? saved.valorMinSemComp : FILTER_DEFAULTS.VALOR_MIN);
  const valorMinSemCompFilter = ref(typeof saved?.valorMinSemCompFilter === 'number' ? saved.valorMinSemCompFilter : FILTER_DEFAULTS.VALOR_MIN);
  const volumeAtipicoEnabled = ref(typeof saved?.volumeAtipicoEnabled === 'boolean' ? saved.volumeAtipicoEnabled : FILTER_DEFAULTS.VOLUME_ATIPICO_ENABLED);
  const volumeAtipicoPercentual = ref(typeof saved?.volumeAtipicoPercentual === 'number' ? saved.volumeAtipicoPercentual : FILTER_DEFAULTS.VOLUME_ATIPICO_PERCENTUAL);
  const volumeAtipicoPercentualFilter = ref(
    typeof saved?.volumeAtipicoPercentualFilter === 'number'
      ? saved.volumeAtipicoPercentualFilter
      : (typeof saved?.volumeAtipicoPercentual === 'number' ? saved.volumeAtipicoPercentual : FILTER_DEFAULTS.VOLUME_ATIPICO_PERCENTUAL)
  );
  const periodo = ref(saved?.periodo ?? FILTER_DEFAULTS.DATE_RANGE);
  const sliderValue = ref(saved?.sliderValue ?? FILTER_DEFAULTS.SLIDER_INDEX_RANGE);

  // 3. CONTROLE DE CONTEXTO
  const filtersLocked = ref(false);
  const regionMapData = ref(null);
  
  watch(selectedRegiaoSaude, (val) => {
    if (!val || val === FILTER_ALL_VALUE) regionMapData.value = null;
  });

  const sidebarCollapsed = ref(localStorage.getItem('sentinela_sidebar_collapsed') === 'true');
  const sidebarLocked = ref(localStorage.getItem('sentinela_sidebar_locked') === 'true');
  const isAnimating = ref(false);
  const animationMode = ref(false);
  const animationDuration = ref(0);
  const animationBaseSliderRange = ref(null);
  const animationSliderValue = ref(null);
  const animationFrameRange = ref([null, null]);

  const animationPreload = reactive({
    status: 'idle',
    dataInicio: null,
    dataFim: null,
  });

  const serializeFilters = () => ({
    selectedUF: selectedUF.value,
    selectedRegiaoSaude: selectedRegiaoSaude.value,
    selectedMunicipio: selectedMunicipio.value,
    selectedSituacao: selectedSituacao.value,
    selectedMS: selectedMS.value,
    selectedPorte: selectedPorte.value,
    selectedGrandeRede: selectedGrandeRede.value,
    selectedUnidadePf: selectedUnidadePf.value,
    selectedCnpjRaiz: selectedCnpjRaiz.value,
    percentualNaoComprovacaoRange: percentualNaoComprovacaoRange.value,
    percentualNaoComprovacaoFilter: percentualNaoComprovacaoFilter.value,
    valorMinSemComp: valorMinSemComp.value,
    valorMinSemCompFilter: valorMinSemCompFilter.value,
    volumeAtipicoEnabled: volumeAtipicoEnabled.value,
    volumeAtipicoPercentual: volumeAtipicoPercentual.value,
    volumeAtipicoPercentualFilter: volumeAtipicoPercentualFilter.value,
    periodo: periodo.value.map(d => d?.toISOString() ?? null),
    sliderValue: sliderValue.value,
    clusterSelection: clusterSelection.value,
    statusSelection: statusSelection.value,
    rfaSelection: rfaSelection.value,
    searchTarget: searchTarget.value,
  });

  const applySavedFilters = (filters) => {
    if (!filters || typeof filters !== 'object') return;

    if ('selectedUF' in filters) selectedUF.value = filters.selectedUF;
    if ('selectedRegiaoSaude' in filters) {
      selectedRegiaoSaude.value = filters.selectedRegiaoSaude && filters.selectedRegiaoSaude !== FILTER_ALL_VALUE && Number.isNaN(Number(filters.selectedRegiaoSaude))
        ? FILTER_DEFAULTS.REGIAO
        : filters.selectedRegiaoSaude;
    }
    if ('selectedMunicipio' in filters) {
      selectedMunicipio.value = filters.selectedMunicipio && filters.selectedMunicipio !== FILTER_ALL_VALUE && Number.isNaN(Number(filters.selectedMunicipio))
        ? FILTER_DEFAULTS.MUNICIPIO
        : filters.selectedMunicipio;
    }
    if ('selectedSituacao' in filters) selectedSituacao.value = filters.selectedSituacao;
    if ('selectedMS' in filters) selectedMS.value = filters.selectedMS;
    if ('selectedPorte' in filters) selectedPorte.value = filters.selectedPorte;
    if ('selectedGrandeRede' in filters) selectedGrandeRede.value = filters.selectedGrandeRede;
    if ('selectedUnidadePf' in filters) selectedUnidadePf.value = filters.selectedUnidadePf;
    if ('selectedCnpjRaiz' in filters) selectedCnpjRaiz.value = filters.selectedCnpjRaiz;
    if (Array.isArray(filters.percentualNaoComprovacaoRange)) percentualNaoComprovacaoRange.value = filters.percentualNaoComprovacaoRange;
    if (Array.isArray(filters.percentualNaoComprovacaoFilter)) percentualNaoComprovacaoFilter.value = filters.percentualNaoComprovacaoFilter;
    if (typeof filters.valorMinSemComp === 'number') valorMinSemComp.value = filters.valorMinSemComp;
    if (typeof filters.valorMinSemCompFilter === 'number') valorMinSemCompFilter.value = filters.valorMinSemCompFilter;
    if (typeof filters.volumeAtipicoEnabled === 'boolean') volumeAtipicoEnabled.value = filters.volumeAtipicoEnabled;
    if (typeof filters.volumeAtipicoPercentual === 'number') volumeAtipicoPercentual.value = filters.volumeAtipicoPercentual;
    if (typeof filters.volumeAtipicoPercentualFilter === 'number') {
      volumeAtipicoPercentualFilter.value = filters.volumeAtipicoPercentualFilter;
    } else if (typeof filters.volumeAtipicoPercentual === 'number') {
      volumeAtipicoPercentualFilter.value = filters.volumeAtipicoPercentual;
    }
    if (Array.isArray(filters.periodo)) periodo.value = filters.periodo.map(d => d ? new Date(d) : null);
    if (Array.isArray(filters.sliderValue)) sliderValue.value = filters.sliderValue;
    if ('clusterSelection' in filters) clusterSelection.value = filters.clusterSelection;
    if ('statusSelection' in filters) statusSelection.value = filters.statusSelection;
    if ('rfaSelection' in filters) rfaSelection.value = filters.rfaSelection;
    if ('searchTarget' in filters) searchTarget.value = filters.searchTarget;
  };

  const saveFiltersToBackend = async () => {
    try {
      await axios.put(API_ENDPOINTS.preferencesFilters, {
        filters: serializeFilters(),
      });
    } catch (error) {
      console.warn('[filters] Falha ao sincronizar filtros no backend:', error);
    }
  };

  const saveUiToBackend = async () => {
    try {
      await axios.put(API_ENDPOINTS.preferencesUi, {
        ui: {
          sidebarCollapsed: sidebarCollapsed.value,
          sidebarLocked: sidebarLocked.value,
        },
      });
    } catch (error) {
      console.warn('[filters] Falha ao sincronizar UI no backend:', error);
    }
  };

  watch(sidebarCollapsed, (val) => {
    localStorage.setItem('sentinela_sidebar_collapsed', String(val));
    saveUiToBackend();
  });
  watch(sidebarLocked, (val) => {
    localStorage.setItem('sentinela_sidebar_locked', String(val));
    saveUiToBackend();
  });

  // 4. FILTROS ESPECÍFICOS DO MÓDULO ALVOS
  const clusterSelection = ref(saved?.clusterSelection ?? FILTER_DEFAULTS.CLUSTER);
  const statusSelection = ref(saved?.statusSelection ?? FILTER_DEFAULTS.STATUS);
  const rfaSelection = ref(saved?.rfaSelection ?? FILTER_DEFAULTS.RFA);
  const searchTarget = ref(saved?.searchTarget ?? FILTER_DEFAULTS.SEARCH);

  // 4. INTELIGÊNCIA DE DADOS (CASCATA REVERSA)
  watch(selectedUF, (newUF) => {
    if (newUF === FILTER_ALL_VALUE) {
      selectedRegiaoSaude.value = FILTER_ALL_VALUE;
      selectedUnidadePf.value = FILTER_ALL_VALUE;
      selectedMunicipio.value = FILTER_ALL_VALUE;
    }
  });

  watch(selectedUnidadePf, (newUnidade) => {
    if (newUnidade === FILTER_ALL_VALUE) return;
    if (geoStore.localidades.length > 0) {
      const found = geoStore.localidades.find(l => 
        l.unidade_pf === newUnidade &&
        (selectedUF.value === FILTER_ALL_VALUE || l.sg_uf === selectedUF.value)
      );
      if (found && selectedUF.value !== found.sg_uf) {
        selectedUF.value = found.sg_uf;
      }
    }
  });

  watch(selectedRegiaoSaude, (newRegiao) => {
    if (newRegiao === FILTER_ALL_VALUE) {
      selectedMunicipio.value = FILTER_ALL_VALUE;
      return;
    }
    if (geoStore.localidades.length > 0) {
      const found = geoStore.localidades.find(l =>
        String(l.id_regiao_saude) === String(newRegiao) &&
        (selectedUF.value === FILTER_ALL_VALUE || l.sg_uf === selectedUF.value)
      );
      if (found && selectedUF.value !== found.sg_uf) {
        selectedUF.value = found.sg_uf;
      }
    }
  });

  watch(selectedMunicipio, (newMunVal) => {
    if (newMunVal !== FILTER_ALL_VALUE && geoStore.localidades.length > 0) {
      const found = geoStore.localidades.find(l => 
        String(l.id_ibge7) === String(newMunVal)
      );
      
      if (found) {
        if (selectedUF.value !== found.sg_uf) selectedUF.value = found.sg_uf;
        if (selectedRegiaoSaude.value !== String(found.id_regiao_saude)) {
          selectedRegiaoSaude.value = String(found.id_regiao_saude);
        }
      }
    }
  });

  let _saveTimer = null;
  const saveToStorage = () => {
    clearTimeout(_saveTimer);
    _saveTimer = setTimeout(() => {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(serializeFilters()));
      saveFiltersToBackend();
    }, TIMING.FILTER_DEBOUNCE);
  };

  watch(
    [selectedUF, selectedRegiaoSaude, selectedUnidadePf, selectedMunicipio, selectedSituacao, selectedMS, selectedPorte, selectedGrandeRede, selectedCnpjRaiz,
     percentualNaoComprovacaoRange, percentualNaoComprovacaoFilter,
     valorMinSemComp, valorMinSemCompFilter, volumeAtipicoEnabled, volumeAtipicoPercentual, volumeAtipicoPercentualFilter, periodo, sliderValue,
     clusterSelection, statusSelection, rfaSelection, searchTarget],
    saveToStorage,
    { deep: true }
  );

  function resetFilters() {
    selectedUF.value = FILTER_ALL_VALUE;
    selectedRegiaoSaude.value = FILTER_ALL_VALUE;
    selectedMunicipio.value = FILTER_ALL_VALUE;
    selectedSituacao.value = FILTER_ALL_VALUE;
    selectedMS.value = FILTER_ALL_VALUE;
    selectedPorte.value = FILTER_ALL_VALUE;
    selectedGrandeRede.value = FILTER_ALL_VALUE;
    selectedUnidadePf.value = FILTER_ALL_VALUE;
    selectedCnpjRaiz.value = '';
    percentualNaoComprovacaoRange.value = [...FILTER_DEFAULTS.PERCENTUAL_RANGE];
    percentualNaoComprovacaoFilter.value = [...FILTER_DEFAULTS.PERCENTUAL_RANGE];
    valorMinSemComp.value = FILTER_DEFAULTS.VALOR_MIN;
    valorMinSemCompFilter.value = FILTER_DEFAULTS.VALOR_MIN;
    volumeAtipicoEnabled.value = FILTER_DEFAULTS.VOLUME_ATIPICO_ENABLED;
    volumeAtipicoPercentual.value = FILTER_DEFAULTS.VOLUME_ATIPICO_PERCENTUAL;
    volumeAtipicoPercentualFilter.value = FILTER_DEFAULTS.VOLUME_ATIPICO_PERCENTUAL;
    periodo.value = [...FILTER_DEFAULTS.DATE_RANGE];
    sliderValue.value = [...FILTER_DEFAULTS.SLIDER_INDEX_RANGE];
    clusterSelection.value = FILTER_ALL_VALUE;
    statusSelection.value = FILTER_ALL_VALUE;
    rfaSelection.value = FILTER_ALL_VALUE;
    searchTarget.value = '';
    animationMode.value = false;
    isAnimating.value = false;
    animationDuration.value = 0;
    animationBaseSliderRange.value = null;
    animationSliderValue.value = null;
    animationFrameRange.value = [null, null];
    animationPreload.status = 'idle';
    animationPreload.dataInicio = null;
    animationPreload.dataFim = null;
    localStorage.removeItem(STORAGE_KEY);
    saveFiltersToBackend();
  }

  function resetAnimationPreview() {
    animationMode.value = false;
    isAnimating.value = false;
    animationDuration.value = 0;
    animationBaseSliderRange.value = null;
    animationSliderValue.value = null;
    animationFrameRange.value = [null, null];
    animationPreload.status = 'idle';
    animationPreload.dataInicio = null;
    animationPreload.dataFim = null;
  }

  async function loadPreferencesFromBackend() {
    try {
      const { data } = await axios.get(API_ENDPOINTS.preferences);
      const backendFilters = data?.filters && Object.keys(data.filters).length > 0
        ? data.filters
        : null;

      if (backendFilters) {
        applySavedFilters(backendFilters);
        localStorage.setItem(STORAGE_KEY, JSON.stringify(serializeFilters()));
      } else if (saved) {
        await saveFiltersToBackend();
      }

      if (data?.ui && typeof data.ui === 'object') {
        if (typeof data.ui.sidebarCollapsed === 'boolean') {
          sidebarCollapsed.value = data.ui.sidebarCollapsed;
        }
        if (typeof data.ui.sidebarLocked === 'boolean') {
          sidebarLocked.value = data.ui.sidebarLocked;
        }
      } else {
        await saveUiToBackend();
      }
    } catch (error) {
      console.warn('[filters] Usando filtros locais do navegador:', error);
    }
  }

  loadPreferencesFromBackend();

  return {
    selectedUF,
    selectedRegiaoSaude,
    selectedMunicipio,
    selectedSituacao,
    selectedMS,
    selectedPorte,
    selectedGrandeRede,
    selectedUnidadePf,
    selectedCnpjRaiz,
    percentualNaoComprovacaoRange,
    percentualNaoComprovacaoFilter,
    valorMinSemComp,
    valorMinSemCompFilter,
    volumeAtipicoEnabled,
    volumeAtipicoPercentual,
    volumeAtipicoPercentualFilter,
    periodo,
    sliderValue,
    clusterSelection,
    statusSelection,
    rfaSelection,
    searchTarget,
    hoveredMunicipioName,
    filtersLocked,
    regionMapData,
    sidebarCollapsed,
    sidebarLocked,
    isAnimating,
    animationMode,
    animationDuration,
    animationBaseSliderRange,
    animationSliderValue,
    animationFrameRange,
    animationPreload,
    resetFilters,
    resetAnimationPreview
  };
});
