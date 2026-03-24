import { defineStore } from 'pinia';
import { ref } from 'vue';

export const useFilterStore = defineStore('filters', () => {
  // 1. FILTROS GLOBAIS
  const selectedUF = ref('Todos');
  const selectedMunicipio = ref('Todos');
  const selectedSituacao = ref('Todos');
  const selectedMS = ref('Todos');
  const selectedPorte = ref('Todos');
  
  // 2. FILTROS DE FAIXA (RANGES)
  const naoComprovacaoRange = ref([0, 100]);
  const valorSemCompRange = ref([0, 3700000]); // Valor para bater com o print (3.7 MI)
  const periodo = ref([new Date(2024, 3, 1), new Date(2024, 8, 1)]); // Abr/2024 - Set/2024 (do print)
  
  // 3. FILTROS ESPECÍFICOS DO MÓDULO ALVOS
  const clusterSelection = ref('Todos');
  const statusSelection = ref('Todos');
  const rfaSelection = ref('Todos');
  const searchTarget = ref('');

  // 4. ACTION - RESET GLOBAL
  function resetFilters() {
    selectedUF.value = 'Todos';
    selectedMunicipio.value = 'Todos';
    selectedSituacao.value = 'Todos';
    selectedMS.value = 'Todos';
    selectedPorte.value = 'Todos';
    naoComprovacaoRange.value = [0, 100];
    valorSemCompRange.value = [0, 3700000];
    periodo.value = [new Date(2024, 3, 1), new Date(2024, 8, 1)];
    clusterSelection.value = 'Todos';
    statusSelection.value = 'Todos';
    rfaSelection.value = 'Todos';
    searchTarget.value = '';
  }

  return {
    selectedUF,
    selectedMunicipio,
    selectedSituacao,
    selectedMS,
    selectedPorte,
    naoComprovacaoRange,
    valorSemCompRange,
    periodo,
    clusterSelection,
    statusSelection,
    rfaSelection,
    searchTarget,
    resetFilters
  };
});
