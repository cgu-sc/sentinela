import { defineStore } from 'pinia';
import { ref, watch } from 'vue';

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

  // 1. FILTROS GLOBAIS
  const selectedUF = ref(saved?.selectedUF ?? 'Todos');
  const selectedRegiaoSaude = ref(saved?.selectedRegiaoSaude ?? 'Todos');
  const selectedMunicipio = ref(saved?.selectedMunicipio ?? 'Todos');
  const selectedSituacao = ref(saved?.selectedSituacao ?? 'Todos');
  const selectedMS = ref(saved?.selectedMS ?? 'Todos');
  const selectedPorte = ref(saved?.selectedPorte ?? 'Todos');

  // 2. FILTROS DE FAIXA (RANGES)
  // *Range: atualiza durante o drag (display)
  // *Filter: atualiza só no slideend (dispara API)
  const percentualNaoComprovacaoRange = ref(saved?.percentualNaoComprovacaoRange ?? [0, 100]);
  const percentualNaoComprovacaoFilter = ref(saved?.percentualNaoComprovacaoFilter ?? [0, 100]);
  const valorMinSemComp = ref(saved?.valorMinSemComp ?? 0);
  const valorMinSemCompFilter = ref(saved?.valorMinSemCompFilter ?? 0);
  const periodo = ref(saved?.periodo ?? [new Date(2015, 6, 1), new Date(2024, 11, 31)]);
  const sliderValue = ref(saved?.sliderValue ?? [0, 113]);

  // 3. FILTROS ESPECÍFICOS DO MÓDULO ALVOS
  const clusterSelection = ref(saved?.clusterSelection ?? 'Todos');
  const statusSelection = ref(saved?.statusSelection ?? 'Todos');
  const rfaSelection = ref(saved?.rfaSelection ?? 'Todos');
  const searchTarget = ref(saved?.searchTarget ?? '');

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
    [selectedUF, selectedRegiaoSaude, selectedMunicipio, selectedSituacao, selectedMS, selectedPorte,
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
    percentualNaoComprovacaoRange.value = [0, 100];
    percentualNaoComprovacaoFilter.value = [0, 100];
    valorMinSemComp.value = 0;
    valorMinSemCompFilter.value = 0;
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
