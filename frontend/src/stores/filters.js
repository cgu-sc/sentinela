import { defineStore } from 'pinia';
import { ref, watch } from 'vue';
import { FILTER_DEFAULTS, FILTER_ALL_VALUE, TIMING } from '@/config/constants';
import { useGeoStore } from './geo';

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
  const selectedRegiaoSaude = ref(saved?.selectedRegiaoSaude ?? FILTER_DEFAULTS.REGIAO);
  const selectedMunicipio = ref(saved?.selectedMunicipio ?? FILTER_DEFAULTS.MUNICIPIO);
  const selectedSituacao = ref(saved?.selectedSituacao ?? FILTER_DEFAULTS.SITUACAO);
  const selectedMS = ref(saved?.selectedMS ?? FILTER_DEFAULTS.MS);
  const selectedPorte = ref(saved?.selectedPorte ?? FILTER_DEFAULTS.PORTE);
  const selectedGrandeRede = ref(saved?.selectedGrandeRede ?? FILTER_DEFAULTS.GRANDE_REDE);
  const selectedCnpjRaiz = ref(saved?.selectedCnpjRaiz ?? '');
  const hoveredMunicipioName = ref(null);

  // 2. FILTROS DE FAIXA (RANGES)
  const percentualNaoComprovacaoRange = ref(saved?.percentualNaoComprovacaoRange ?? FILTER_DEFAULTS.PERCENTUAL_RANGE);
  const percentualNaoComprovacaoFilter = ref(saved?.percentualNaoComprovacaoFilter ?? FILTER_DEFAULTS.PERCENTUAL_RANGE);
  const valorMinSemComp = ref(typeof saved?.valorMinSemComp === 'number' ? saved.valorMinSemComp : FILTER_DEFAULTS.VALOR_MIN);
  const valorMinSemCompFilter = ref(typeof saved?.valorMinSemCompFilter === 'number' ? saved.valorMinSemCompFilter : FILTER_DEFAULTS.VALOR_MIN);
  const periodo = ref(saved?.periodo ?? FILTER_DEFAULTS.DATE_RANGE);
  const sliderValue = ref(saved?.sliderValue ?? FILTER_DEFAULTS.SLIDER_INDEX_RANGE);

  // 3. FILTROS ESPECÍFICOS DO MÓDULO ALVOS
  const clusterSelection = ref(saved?.clusterSelection ?? FILTER_DEFAULTS.CLUSTER);
  const statusSelection = ref(saved?.statusSelection ?? FILTER_DEFAULTS.STATUS);
  const rfaSelection = ref(saved?.rfaSelection ?? FILTER_DEFAULTS.RFA);
  const searchTarget       = ref(saved?.searchTarget ?? FILTER_DEFAULTS.SEARCH);
  const showMapaPoints      = ref(saved?.showMapaPoints ?? true);

  // 4. INTELIGÊNCIA DE DADOS (CASCATA REVERSA)
  watch(selectedUF, (newUF) => {
    if (newUF === FILTER_ALL_VALUE) {
      selectedRegiaoSaude.value = FILTER_ALL_VALUE;
      selectedMunicipio.value = FILTER_ALL_VALUE;
    }
  });

  watch(selectedRegiaoSaude, (newRegiao) => {
    if (newRegiao === FILTER_ALL_VALUE) {
      // Limpar região cascateia para município
      selectedMunicipio.value = FILTER_ALL_VALUE;
      return;
    }
    if (geoStore.localidades.length > 0) {
      const found = geoStore.localidades.find(l =>
        l.no_regiao_saude === newRegiao &&
        (selectedUF.value === FILTER_ALL_VALUE || l.sg_uf === selectedUF.value)
      );
      if (found && selectedUF.value !== found.sg_uf) {
        selectedUF.value = found.sg_uf;
      }
    }
  });

  watch(selectedMunicipio, (newMunVal) => {
    if (newMunVal !== FILTER_ALL_VALUE && geoStore.localidades.length > 0) {
      // O valor vem formatado como "Nome|UF" (Garante unicidade)
      const [nome, uf] = newMunVal.split('|');
      const found = geoStore.localidades.find(l => 
        l.no_municipio === nome && l.sg_uf === uf
      );
      
      if (found) {
        if (selectedUF.value !== found.sg_uf) selectedUF.value = found.sg_uf;
        if (selectedRegiaoSaude.value !== found.no_regiao_saude) selectedRegiaoSaude.value = found.no_regiao_saude;
      }
    }
  });

  // Persiste automaticamente no localStorage com debounce de 200ms
  // (evita escrita contínua durante drag de sliders)
  let _saveTimer = null;
  const saveToStorage = () => {
    clearTimeout(_saveTimer);
    _saveTimer = setTimeout(() => {
      localStorage.setItem(STORAGE_KEY, JSON.stringify({
        selectedUF: selectedUF.value,
        selectedRegiaoSaude: selectedRegiaoSaude.value,
        selectedMunicipio: selectedMunicipio.value,
        selectedSituacao: selectedSituacao.value,
        selectedMS: selectedMS.value,
        selectedPorte: selectedPorte.value,
        selectedGrandeRede: selectedGrandeRede.value,
        selectedCnpjRaiz: selectedCnpjRaiz.value,
        percentualNaoComprovacaoRange: percentualNaoComprovacaoRange.value,
        percentualNaoComprovacaoFilter: percentualNaoComprovacaoFilter.value,
        valorMinSemComp: valorMinSemComp.value,
        valorMinSemCompFilter: valorMinSemCompFilter.value,
        periodo: periodo.value.map(d => d?.toISOString() ?? null),
        sliderValue: sliderValue.value,
        clusterSelection: clusterSelection.value,
        statusSelection: statusSelection.value,
        rfaSelection: rfaSelection.value,
        searchTarget: searchTarget.value,
        showMapaPoints: showMapaPoints.value,
      }));
    }, TIMING.FILTER_DEBOUNCE);
  };

  watch(
    [selectedUF, selectedRegiaoSaude, selectedMunicipio, selectedSituacao, selectedMS, selectedPorte, selectedGrandeRede, selectedCnpjRaiz,
     percentualNaoComprovacaoRange, percentualNaoComprovacaoFilter,
     valorMinSemComp, valorMinSemCompFilter, periodo, sliderValue,
     clusterSelection, statusSelection, rfaSelection, searchTarget, showMapaPoints],
    saveToStorage,
    { deep: true }
  );

  // 4. ACTION - RESET GLOBAL
  function resetFilters() {
    selectedUF.value = FILTER_ALL_VALUE;
    selectedRegiaoSaude.value = FILTER_ALL_VALUE;
    selectedMunicipio.value = FILTER_ALL_VALUE;
    selectedSituacao.value = FILTER_ALL_VALUE;
    selectedMS.value = FILTER_ALL_VALUE;
    selectedPorte.value = FILTER_ALL_VALUE;
    selectedGrandeRede.value = FILTER_ALL_VALUE;
    selectedCnpjRaiz.value = '';
    percentualNaoComprovacaoRange.value = [...FILTER_DEFAULTS.PERCENTUAL_RANGE];
    percentualNaoComprovacaoFilter.value = [...FILTER_DEFAULTS.PERCENTUAL_RANGE];
    valorMinSemComp.value = FILTER_DEFAULTS.VALOR_MIN;
    valorMinSemCompFilter.value = FILTER_DEFAULTS.VALOR_MIN;
    periodo.value = [...FILTER_DEFAULTS.DATE_RANGE];
    sliderValue.value = [...FILTER_DEFAULTS.SLIDER_INDEX_RANGE];
    clusterSelection.value = FILTER_ALL_VALUE;
    statusSelection.value = FILTER_ALL_VALUE;
    rfaSelection.value = FILTER_ALL_VALUE;
    searchTarget.value = '';
    showMapaPoints.value = true;
    localStorage.removeItem(STORAGE_KEY);
  }

  return {
    selectedUF,
    selectedRegiaoSaude,
    selectedMunicipio,
    selectedSituacao,
    selectedMS,
    selectedPorte,
    selectedGrandeRede,
    selectedCnpjRaiz,
    percentualNaoComprovacaoRange,
    percentualNaoComprovacaoFilter,
    valorMinSemComp,
    valorMinSemCompFilter,
    periodo,
    sliderValue,
    clusterSelection,
    statusSelection,
    rfaSelection,
    searchTarget,
    hoveredMunicipioName,
    showMapaPoints,
    resetFilters
  };
});
