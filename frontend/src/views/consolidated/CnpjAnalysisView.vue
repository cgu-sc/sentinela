<script setup>
import { useFetchAnalytics } from '@/composables/useFetchAnalytics';
import KpiSection from './components/KpiSection.vue';
import RiskAnalysisChart from './components/RiskAnalysisChart.vue';
import CnpjAnalysisTable from './components/CnpjAnalysisTable.vue';

useFetchAnalytics({ includeFatorRisco: true });
</script>

<template>
  <div class="dashboard-container">
    <KpiSection />
    <div class="charts-table-grid">
      <RiskAnalysisChart />
      <CnpjAnalysisTable />
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
