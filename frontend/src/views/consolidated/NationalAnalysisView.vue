<script setup>
import { useFetchAnalytics } from '@/composables/useFetchAnalytics';
import KpiSection from './components/KpiSection.vue';
import RiskAnalysisChart from './components/RiskAnalysisChart.vue';
import BrazilMapChart from './components/BrazilMapChart.vue';
import UfAnalysisTable from './components/UfAnalysisTable.vue';
useFetchAnalytics({ includeFatorRisco: true });
</script>

<template>
  <div class="dashboard-container">
    <KpiSection />
    <div class="charts-row">
      <RiskAnalysisChart />
      <BrazilMapChart />
    </div>
    <UfAnalysisTable />
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
  grid-template-columns: 13fr 7fr;
  gap: 1.5rem;
}
</style>
