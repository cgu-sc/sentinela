<script setup>
import { useAnalyticsStore } from '@/stores/analytics';
import { storeToRefs } from 'pinia';
import Button from 'primevue/button';

const analyticsStore = useAnalyticsStore();
const { enrichedKpis, isLoading, error } = storeToRefs(analyticsStore);
</script>

<template>
  <section class="kpi-section">
    <!-- FEEDBACK DE ERRO -->
    <div v-if="error" class="error-banner">
       <i class="pi pi-exclamation-circle"></i>
       <span>{{ error }}</span>
       <Button label="Tentar Novamente" icon="pi pi-refresh" @click="analyticsStore.fetchDashboardSummary()" text size="small" />
    </div>

    <!-- CARDS DE KPI -->
    <div class="kpi-grid" :class="{ 'is-refreshing': isLoading }">
      <div 
        v-for="kpi in enrichedKpis" 
        :key="kpi.label" 
        class="kpi-card" 
      >
        <div class="kpi-body">
          <div class="kpi-icon-bg" :style="{ backgroundColor: kpi.color + '20', color: kpi.color }">
             <i :class="kpi.icon"></i>
          </div>
          <div class="kpi-content">
            <span class="kpi-label">{{ kpi.label }}</span>
            <span class="kpi-value">{{ kpi.value }}</span>
          </div>
        </div>
      </div>
    </div>
  </section>
</template>

<style scoped>
.kpi-section {
  width: 100%;
}

.kpi-grid {
  display: grid;
  grid-template-columns: repeat(5, 1fr);
  gap: 1rem;
}

.kpi-card {
  background: var(--card-bg);
  border-radius: 12px;
  padding: 1rem 1.25rem;
  border: 1px solid var(--sidebar-border);
  transition: transform 0.2s, background-color 0.3s ease;
}

.kpi-card:hover { 
  transform: translateY(-2px);
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
}

.kpi-body {
  display: flex;
  justify-content: flex-start;
  align-items: center;
  gap: 1rem;
}

.kpi-content {
  display: flex;
  flex-direction: column;
}

.kpi-label {
  font-size: 0.75rem;
  color: var(--text-muted);
  font-weight: 600;
  text-transform: uppercase;
}

.kpi-value {
  font-size: 1.5rem;
  font-weight: 800;
  color: var(--text-color);
  opacity: 0.85;
}

.kpi-icon-bg {
  width: 2.75rem;
  height: 2.75rem;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 0.5rem;
  font-size: 1.25rem;
}

.is-refreshing {
  opacity: 0.5;
  pointer-events: none;
}

.error-banner {
  display: flex;
  align-items: center;
  gap: 1rem;
  padding: 1rem;
  background: rgba(239, 68, 68, 0.1);
  border: 1px solid rgba(239, 68, 68, 0.2);
  border-radius: 8px;
  color: #f87171;
  margin-bottom: 2rem;
}
</style>
