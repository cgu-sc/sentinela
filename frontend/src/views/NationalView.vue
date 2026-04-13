<script setup>
import { useFetchAnalytics } from '@/composables/useFetchAnalytics';
import KpiSection from './components/KpiSection.vue';
import RiskChart from './components/charts/RiskChart.vue';
import BrazilMap from './components/maps/BrazilMap.vue';
import UFTable from './components/tables/UFTable.vue';
useFetchAnalytics({ includeFatorRisco: true });
</script>

<template>
  <div class="dashboard-container">
    <KpiSection />
    <div class="charts-row">
      <RiskChart />
      <BrazilMap />
    </div>
    <UFTable />
  </div>
</template>

<style scoped>
.dashboard-container {
  display: flex;
  flex-direction: column;
  gap: 1rem;
}

.charts-row {
  display: grid;
  grid-template-columns: 13fr 7fr;
  gap: 1rem;
}
</style>
