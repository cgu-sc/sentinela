<script setup>
import { useFetchAnalytics } from '@/composables/useFetchAnalytics';
import KpiSection from './components/KpiSection.vue';
import RiskChart from './components/charts/RiskChart.vue';
import MunicipalMap from './components/maps/MunicipalMap.vue';
import UFDrillMap from './components/maps/UFDrillMap.vue';
import MunicipalTable from './components/tables/MunicipalTable.vue';
import { useFilterStore } from '@/stores/filters';

const filterStore = useFilterStore();
useFetchAnalytics({ includeFatorRisco: true });
</script>

<template>
  <div class="dashboard-container">
    <KpiSection />
    <div class="charts-row has-map">
      <RiskChart />
      <UFDrillMap v-if="filterStore.selectedUF === 'Todos'" />
      <MunicipalMap v-else />
    </div>
    <MunicipalTable />
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
  grid-template-columns: 1fr;
  gap: 1rem;
}

.charts-row.has-map {
  grid-template-columns: 13fr 7fr;
}
</style>
