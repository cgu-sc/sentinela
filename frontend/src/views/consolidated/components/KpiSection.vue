<script setup>
import { useAnalyticsStore } from '@/stores/analytics';
import { useChartTheme } from '@/config/chartTheme';
import { storeToRefs } from 'pinia';
import Button from 'primevue/button';

const analyticsStore = useAnalyticsStore();
const { enrichedKpis, isLoading, error } = storeToRefs(analyticsStore);
const { chartDataColors } = useChartTheme();
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
  overflow: visible;
}

.kpi-grid {
  display: grid;
  grid-template-columns: repeat(6, minmax(0, 1fr)); /* TRAVA DE LARGURA: Garante colunas de exatos 20% sempre */
  gap: 1.15rem;
  width: 100%;
  padding-top: 4px; /* espaço para o lift do hover não ser cortado */
}

.kpi-card {
  /* MÁGICA BALANCEADA: Gradiente interno e borda com visibilidade ideal */
  background: var(--card-bg);
  border-radius: 12px;
  padding: 0.8rem 1rem; /* MEDIDA DO USUÁRIO */
  border: 1px solid var(--card-border);
  box-shadow: 0 1px 3px rgba(0,0,0,0.08), 0 1px 2px rgba(0,0,0,0.04);
  transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
  min-height: 0; /* TRAVA VERTICAL */
  display: flex;
  align-items: center;
}

.kpi-card:hover { 
  transform: translateY(-3px);
  /* Sombra elegante e visível acompanhando o tema */
  box-shadow: 0 8px 18px -10px color-mix(in srgb, var(--primary-color) 30%, transparent);
  border-color: color-mix(in srgb, var(--primary-color) 30%, var(--sidebar-border));
}

.kpi-body {
  display: flex;
  justify-content: flex-start;
  align-items: center;
  gap: 0.9rem; /* MEDIDA DO USUÁRIO */
  width: 100%;
}

.kpi-content {
  display: flex;
  flex-direction: column;
  min-width: 0;
}

.kpi-label {
  font-size: 0.70rem; /* MEDIDA DO USUÁRIO */
  color: var(--text-muted);
  font-weight: 700;
  text-transform: uppercase;
  white-space: nowrap;
  line-height: 1;
  margin-bottom: 0.3rem;
}

.kpi-value {
  font-size: 1.3rem; /* MEDIDA DO USUÁRIO */
  white-space: nowrap;
  letter-spacing: -0.6px;
  font-weight: 700;
  color: var(--text-color);
  opacity: 0.90;
  line-height: 1;
  white-space: nowrap; /* IMPEDE QUEBRA */
  letter-spacing: -0.6px; /* COMPACTO */
}

.kpi-icon-bg {
  width: 2.75rem;
  height: 2.75rem;
  flex-shrink: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 0.75rem;
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
  background: color-mix(in srgb, v-bind('chartDataColors.red') 10%, transparent);
  border: 1px solid color-mix(in srgb, v-bind('chartDataColors.red') 20%, transparent);
  border-radius: 8px;
  color: v-bind('chartDataColors.red');
  margin-bottom: 2rem;
}
</style>
