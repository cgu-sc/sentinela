import { defineStore } from 'pinia';
import { ref, watch } from 'vue';
import { FILTER_DEFAULTS } from '@/config/constants';
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

  // 2. FILTROS DE FAIXA (RANGES)
  const percentualNaoComprovacaoRange = ref(saved?.percentualNaoComprovacaoRange ?? FILTER_DEFAULTS.PERCENTUAL_RANGE);
  const percentualNaoComprovacaoFilter = ref(saved?.percentualNaoComprovacaoFilter ?? FILTER_DEFAULTS.PERCENTUAL_RANGE);
  const valorMinSemComp = ref(Array.isArray(saved?.valorMinSemComp) ? saved.valorMinSemComp : FILTER_DEFAULTS.VALOR_RANGE);
  const valorMinSemCompFilter = ref(Array.isArray(saved?.valorMinSemCompFilter) ? saved.valorMinSemCompFilter : FILTER_DEFAULTS.VALOR_RANGE);
  const periodo = ref(saved?.periodo ?? FILTER_DEFAULTS.DATE_RANGE);
  const sliderValue = ref(saved?.sliderValue ?? FILTER_DEFAULTS.SLIDER_INDEX_RANGE);

  // 3. FILTROS ESPECÍFICOS DO MÓDULO ALVOS
  const clusterSelection = ref(saved?.clusterSelection ?? FILTER_DEFAULTS.CLUSTER);
  const statusSelection = ref(saved?.statusSelection ?? FILTER_DEFAULTS.STATUS);
  const rfaSelection = ref(saved?.rfaSelection ?? FILTER_DEFAULTS.RFA);
  const searchTarget = ref(saved?.searchTarget ?? FILTER_DEFAULTS.SEARCH);

  // 4. INTELIGÊNCIA DE DADOS (CASCATA REVERSA)
  watch(selectedRegiaoSaude, (newRegiao) => {
    if (newRegiao !== 'Todos' && geoStore.localidades.length > 0) {
      // Tenta encontrar a região dentro do UF já selecionado (se houver um)
      const found = geoStore.localidades.find(l => 
        l.no_regiao_saude === newRegiao && 
        (selectedUF.value === 'Todos' || l.sg_uf === selectedUF.value)
      );
      if (found && selectedUF.value !== found.sg_uf) {
        selectedUF.value = found.sg_uf;
      }
    }
  });

  watch(selectedMunicipio, (newMunVal) => {
    if (newMunVal !== 'Todos' && geoStore.localidades.length > 0) {
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
      }));
    }, 200);
  };

  watch(
    [selectedUF, selectedRegiaoSaude, selectedMunicipio, selectedSituacao, selectedMS, selectedPorte, selectedGrandeRede,
     percentualNaoComprovacaoRange, percentualNaoComprovacaoFilter,
     valorMinSemComp, valorMinSemCompFilter, periodo, sliderValue,
     clusterSelection, statusSelection, rfaSelection, searchTarget],
    saveToStorage,
    { deep: true }
  );

  // 4. ACTION - RESET GLOBAL
  function resetFilters() {
    selectedUF.value = 'Todos';
    selectedRegiaoSaude.value = 'Todos';
    selectedMunicipio.value = 'Todos';
    selectedSituacao.value = 'Todos';
    selectedMS.value = 'Todos';
    selectedPorte.value = 'Todos';
    selectedGrandeRede.value = 'Todos';
    percentualNaoComprovacaoRange.value = [0, 100];
    percentualNaoComprovacaoFilter.value = [0, 100];
    valorMinSemComp.value = [0, 1000000];
    valorMinSemCompFilter.value = [0, 1000000];
    periodo.value = [new Date(2015, 6, 1), new Date(2024, 11, 31)];
    sliderValue.value = [0, 113];
    clusterSelection.value = 'Todos';
    statusSelection.value = 'Todos';
    rfaSelection.value = 'Todos';
    searchTarget.value = '';
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
    resetFilters
  };
});
