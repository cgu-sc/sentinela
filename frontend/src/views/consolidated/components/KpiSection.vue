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
  grid-template-columns: repeat(5, minmax(0, 1fr)); /* TRAVA DE LARGURA: Garante colunas de exatos 20% sempre */
  gap: 1.25rem;
  width: 100%;
}

.kpi-card {
  /* MÁGICA BALANCEADA: Gradiente interno e borda com visibilidade ideal */
  background: linear-gradient(135deg, var(--card-bg) 75%, color-mix(in srgb, var(--primary-color) 3%, var(--card-bg)) 100%);
  border-radius: 12px;
  padding: 1.10rem 1.2rem; /* MEDIDA DO USUÁRIO */
  border: 1px solid color-mix(in srgb, var(--primary-color) 12%, var(--sidebar-border));
  transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
  min-height: 86px; /* TRAVA VERTICAL */
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
  font-size: 0.75rem; /* MEDIDA DO USUÁRIO */
  color: var(--text-muted);
  font-weight: 700;
  text-transform: uppercase;
  white-space: nowrap;
  line-height: 1;
  margin-bottom: 0.3rem;
}

.kpi-value {
  font-size: 1.4rem; /* MEDIDA DO USUÁRIO */
  white-space: nowrap;
  letter-spacing: -0.6px;
  font-weight: 800;
  color: var(--text-color);
  opacity: 0.95;
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
  background: rgba(239, 68, 68, 0.1);
  border: 1px solid rgba(239, 68, 68, 0.2);
  border-radius: 8px;
  color: #f87171;
  margin-bottom: 2rem;
}
</style>
