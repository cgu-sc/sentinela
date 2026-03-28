<script setup>
import { useFetchAnalytics } from '@/composables/useFetchAnalytics';
import KpiSection from './components/KpiSection.vue';
import ScatterChartUF from './components/ScatterChartUF.vue';

useFetchAnalytics();
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
