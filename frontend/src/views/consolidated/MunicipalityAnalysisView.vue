<script setup>
import { useFetchAnalytics } from '@/composables/useFetchAnalytics';
import KpiSection from './components/KpiSection.vue';
import RiskAnalysisChart from './components/RiskAnalysisChart.vue';
import MunicipalityMapChart from './components/MunicipalityMapChart.vue';
import MunicipalityAnalysisTable from './components/MunicipalityAnalysisTable.vue';
import { useFilterStore } from '@/stores/filters';

const filterStore = useFilterStore();
useFetchAnalytics({ includeFatorRisco: true });
</script>

<template>
  <div class="dashboard-container">
    <KpiSection />
    <div class="charts-row" :class="{ 'has-map': filterStore.selectedUF !== 'Todos' }">
      <RiskAnalysisChart />
      <MunicipalityMapChart v-if="filterStore.selectedUF !== 'Todos'" />
    </div>
    <MunicipalityAnalysisTable />
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
  grid-template-columns: 3fr 2fr;
}
</style>
