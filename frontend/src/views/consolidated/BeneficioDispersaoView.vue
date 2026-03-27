<script setup>
import { watch } from 'vue';
import { useFilterStore } from '@/stores/filters';
import { useAnalyticsStore } from '@/stores/analytics';
import { useFilterParameters } from '@/composables/useFilterParameters';

import KpiSection from './components/KpiSection.vue';
import ScatterChartUF from './components/ScatterChartUF.vue';

const filterStore = useFilterStore();
const analyticsStore = useAnalyticsStore();
const { getApiParams, isPeriodoValido } = useFilterParameters();

const fetchTodos = () => {
  const params = getApiParams();
  analyticsStore.fetchDashboardSummary(
    params.inicio, params.fim, params.percMin, params.percMax, params.valMin,
    params.uf, params.regiaoSaude, params.municipio, params.situacaoRf,
    params.conexaoMs, params.porteEmpresa, params.grandeRede
  );
};

watch(
  () => [
    filterStore.periodo,
    filterStore.percentualNaoComprovacaoFilter,
    filterStore.valorMinSemCompFilter,
    filterStore.selectedUF,
    filterStore.selectedRegiaoSaude,
    filterStore.selectedMunicipio,
    filterStore.selectedSituacao,
    filterStore.selectedMS,
    filterStore.selectedPorte,
    filterStore.selectedGrandeRede,
  ],
  () => { if (isPeriodoValido()) fetchTodos(); },
  { deep: true, immediate: false }
);
</script>

<template>
  <div class="dashboard-container">
    <KpiSection />
    <div class="scatter-wrapper">
      <ScatterChartUF grow />
    </div>
  </div>
</template>

<style scoped>
.dashboard-container {
  display: flex;
  flex-direction: column;
  gap: 1.5rem;
  height: 100%;
  overflow: visible;
}

.scatter-wrapper {
  flex: 1;
  min-height: 0;
  display: flex;
  flex-direction: column;
}
</style>
