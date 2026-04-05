<script setup>
import { useFetchAnalytics } from '@/composables/useFetchAnalytics';
import { useFilterStore } from '@/stores/filters';
import KpiSection from './components/KpiSection.vue';
import RiskAnalysisChart from './components/RiskAnalysisChart.vue';
import MunicipalityMapChart from './components/MunicipalityMapChart.vue';
import CnpjAnalysisTable from './components/CnpjAnalysisTable.vue';

const filterStore = useFilterStore();
useFetchAnalytics({ includeFatorRisco: true });
</script>

<template>
  <div class="dashboard-container">
    <KpiSection />
    <div class="charts-row" :class="{ 'has-map': filterStore.selectedMunicipio && filterStore.selectedMunicipio !== 'Todos' }">
      <RiskAnalysisChart />
      <MunicipalityMapChart v-if="filterStore.selectedMunicipio && filterStore.selectedMunicipio !== 'Todos'" />
    </div>
    <CnpjAnalysisTable />
  </div>
</template>

<style scoped>
.dashboard-container {
  display: flex;
  flex-direction: column;
  gap: 1.5rem;
}

.charts-row {
  display: grid;
  grid-template-columns: 1fr;
  gap: 1.5rem;
}

.charts-row.has-map {
  grid-template-columns: 13fr 7fr;
}
</style>
