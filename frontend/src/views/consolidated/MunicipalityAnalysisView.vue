<script setup>
import { useFetchAnalytics } from '@/composables/useFetchAnalytics';
import KpiSection from './components/KpiSection.vue';
import RiskAnalysisChart from './components/RiskAnalysisChart.vue';
import MunicipalityAnalysisTable from './components/MunicipalityAnalysisTable.vue';
import { useFilterStore } from '@/stores/filters';

const filterStore = useFilterStore();
useFetchAnalytics({ includeFatorRisco: true });
</script>

<template>
  <div class="dashboard-container">
    <KpiSection />
    <div class="charts-table-grid">
      <RiskAnalysisChart />
      <MunicipalityAnalysisTable />
    </div>
  </div>
</template>

<style scoped>
.dashboard-container {
  display: flex;
  flex-direction: column;
  gap: 1.5rem;
}

.charts-table-grid {
  display: flex;
  flex-direction: column;
  gap: 1.5rem;
}
</style>
