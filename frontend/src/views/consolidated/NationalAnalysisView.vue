<script setup>
import { onMounted, watch } from 'vue';
import { useFilterStore } from '@/stores/filters';
import { useAnalyticsStore } from '@/stores/analytics';
import { useFilterParameters } from '@/composables/useFilterParameters';

// Importação dos Componentes Modulares
import KpiSection from './components/KpiSection.vue';
import RiskAnalysisChart from './components/RiskAnalysisChart.vue';
import UfAnalysisTable from './components/UfAnalysisTable.vue';

const filterStore = useFilterStore();
const analyticsStore = useAnalyticsStore();
const { getApiParams, isPeriodoValido } = useFilterParameters();

// 1. LOGICA DE BUSCA CENTRALIZADA NA VIEW
const fetchTodos = () => {
  const params = getApiParams();
  analyticsStore.fetchFatorRisco(
    params.inicio, params.fim, params.percMin, params.percMax, params.valMin, 
    params.uf, params.regiaoSaude, params.municipio, params.situacaoRf, 
    params.conexaoMs, params.porteEmpresa, params.grandeRede
  );
  analyticsStore.fetchDashboardSummary(
    params.inicio, params.fim, params.percMin, params.percMax, params.valMin, 
    params.uf, params.regiaoSaude, params.municipio, params.situacaoRf, 
    params.conexaoMs, params.porteEmpresa, params.grandeRede
  );
};

// 2. REATIVIDADE AOS FILTROS (WATCHER ÚNICO)
watch(
  () => [
    filterStore.periodo,
    filterStore.percentualNaoComprovacaoFilter,
    filterStore.valorMinSemCompFilter,
    filterStore.selectedUF,
    filterStore.selectedRegiaoSaude,
    filterStore.selectedMunicipio,
    filterStore.selectedSituacao,
    filterStore.selectedMS,
    filterStore.selectedPorte,
    filterStore.selectedGrandeRede,
  ],
  () => { if (isPeriodoValido()) fetchTodos(); },
  { deep: true, immediate: false }
);

onMounted(() => {
    // Note: Cargas gerais são feitas no App.vue ou ao mudar filtros
});
</script>

<template>
  <div class="dashboard-container">
    <!-- 1. SEÇÃO DE CARDS DE KPI -->
    <KpiSection />

    <!-- 2. GRID PRINCIPAL (GRÁFICO E TABELA) -->
    <div class="charts-table-grid">
      <!-- GRÁFICO DE FATOR DE RISCO -->
      <RiskAnalysisChart />

      <!-- TABELA DE ANÁLISE POR UF -->
      <UfAnalysisTable />
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
