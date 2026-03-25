<script setup>
import { ref, onMounted, computed, watch } from 'vue';
import { useThemeStore } from '../stores/theme';
import { useFilterStore } from '../stores/filters';
import { useRiskMetrics } from '../composables/useRiskMetrics';
import { useFormatting } from '../composables/useFormatting';
import { useChartStyles } from '../composables/useChartStyles';
import { useDashboardStore } from '../stores/dashboard';
import { storeToRefs } from 'pinia';

const themeStore = useThemeStore();
const filterStore = useFilterStore();
const { getRiskSeverity, getRiskClass } = useRiskMetrics();
const { formatBRL, formatNumber, formatPercent, formatCurrencyFull, formatNumberFull } = useFormatting();
const { chartBaseOptions, chartColors } = useChartStyles(themeStore);
const dashboardStore = useDashboardStore();

// Destruturação reativa para manter os dados sincronizados
const { kpis, nationalAnalysis, fatorRisco, isLoading, error } = storeToRefs(dashboardStore);
import Card from 'primevue/card';
import DataTable from 'primevue/datatable';
import Column from 'primevue/column';
import Tag from 'primevue/tag';
import Button from 'primevue/button';
import RadioButton from 'primevue/radiobutton';
import axios from 'axios';

// 4. LOGICA DE FILTRAGEM (O PODER DO PINIA)
const filteredData = computed(() => {
  if (filterStore.selectedUF === 'Todos') {
    return nationalAnalysis.value;
  }
  return nationalAnalysis.value.filter(item => item.uf === filterStore.selectedUF);
});

// CONFIG GRAFICO COMBO (DADOS REAIS DA API)
const chartSeries = computed(() => [
    {
        name: 'Qtd Estab por Faixa',
        type: 'column',
        data: fatorRisco.value.map(b => b.qtd)
    },
    {
        name: 'Valor Sem Comprovação',
        type: 'area',
        data: fatorRisco.value.map(b => b.valor_raw)
    }
]);

// Configuração de Estilo do Gráfico (Mesclando com Base Global)
const chartOptions = computed(() => ({
    ...chartBaseOptions.value, // Herança de Estilo Global
    colors: [chartColors.value.primary, chartColors.value.danger], // Azul = Estabelecimento | Vermelho (Danger) = Valor R$
    stroke: {
        width: [0, 3],
        curve: 'smooth',
        lineCap: 'round'
    },
    plotOptions: {
        bar: {
            columnWidth: '45%',
            borderRadius: 6,
            borderRadiusApplication: 'around',
        }
    },
    fill: {
        type: 'gradient',
        gradient: {
            shade: 'dark',
            type: "vertical",
            shadeIntensity: 0.5,
            gradientToColors: [chartColors.value.secondary, undefined], 
            inverseColors: false,
            opacityFrom: [0.9, 0.6],
            opacityTo: [0.8, 0.1],
            stops: [0, 100, 100]
        }
    },
    labels: fatorRisco.value.map(b => b.faixa),
    xaxis: {
        ...chartBaseOptions.value.xaxis,
        type: 'category',
    },
    yaxis: [
        {
            ...chartBaseOptions.value.yaxis,
            title: { text: 'Qtd Estab', style: { color: chartColors.value.primary, fontWeight: 700 } },
            labels: {
                ...chartBaseOptions.value.yaxis?.labels,
                formatter: (val) => formatNumber(val)
            }
        },
        {
            ...chartBaseOptions.value.yaxis,
            opposite: true,
            title: { text: 'Valor Sem Comp', style: { color: chartColors.value.danger, fontWeight: 700 } },
            labels: {
                ...chartBaseOptions.value.yaxis?.labels,
                formatter: (val) => formatBRL(val)
            }
        }
    ],
    tooltip: {
        shared: true,
        intersect: false,
        theme: themeStore.isDark ? 'dark' : 'light',
        y: [
            {
                formatter: (val) => formatNumberFull(val)
            },
            {
                formatter: (val) => formatCurrencyFull(val)
            }
        ]
    }
}));
// 5. REATIVIDADE AO PERÍODO DE ANÁLISE
// Helper para pegar a data ISO local YYYY-MM-DD sem shift de timezone
const toLocalISO = (date) => {
  if (!date || !(date instanceof Date)) return null;
  const d = new Date(date);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
};

watch(
  () => filterStore.periodo,
  (newVal) => {
    if (newVal && Array.isArray(newVal) && newVal.length === 2 && newVal[0] && newVal[1]) {
      const inicio = toLocalISO(newVal[0]);
      const fim = toLocalISO(newVal[1]);
      
      console.log(`[SENTINELA] Período alterado: ${inicio} até ${fim}. Buscando dados...`);
      dashboardStore.fetchFatorRisco(inicio, fim);
    }
  },
  { deep: true, immediate: false }
);

onMounted(() => {
    // Note: Cargas gerais são feitas no App.vue
    // O fetchFatorRisco agora é controlado pelo Watcher do Filtro
});

// Agrupamento selecionado (para Teleport Sidebar)
const groupBy = ref('uf');
const groupOptions = ref(['UF', 'Município', 'Região de Saúde']);

// Funções de Estilo com ícones baseados no print
const getTrendIcon = (trend) => {
  if (trend === 'up') return 'pi pi-arrow-up';
  if (trend === 'down') return 'pi pi-arrow-down';
  if (trend === 'neutral') return 'pi pi-arrow-up-right'; // Estilo do print para diagonal
  return 'pi pi-minus';
};

const getTrendColor = (trend) => {
  if (trend === 'up') return '#ef4444'; // Vermelho
  if (trend === 'down') return '#22c55e'; // Verde
  if (trend === 'neutral') return '#f59e0b'; // Laranja para diagonal
  return '#94a3b8';
};
</script>

<template>
  <div class="dashboard-container">
    <!-- FEEDBACK DE CARREGAMENTO E ERRO -->
    <div v-if="isLoading" class="loading-overlay">
       <i class="pi pi-spin pi-spinner" style="font-size: 2rem; color: var(--primary-color)"></i>
       <span style="margin-top: 1rem; font-weight: 500;">Carregando dados reais do Sentinela...</span>
    </div>

    <div v-else-if="error" class="error-banner">
       <i class="pi pi-exclamation-circle"></i>
       <span>{{ error }}</span>
       <Button label="Tentar Novamente" icon="pi pi-refresh" @click="dashboardStore.fetchDashboardSummary" text size="small" />
    </div>

    <!-- CARDS DE KPI -->
    <div v-else class="kpi-grid">
      <div 
        v-for="kpi in kpis" 
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

    <!-- MAIN GRID (GRÁFICO E DEPOIS TABELA) -->
    <div class="charts-table-grid">
      <!-- GRÁFICO -->
      <div class="chart-section shadow-card">
         <div class="section-header">
           <i class="pi pi-chart-bar"></i>
           <h3>FATOR RISCO X QTD ESTAB</h3>
           <div class="spacer"></div>
           <Button icon="pi pi-info-circle" v-tooltip.top="'Este gráfico segmenta os estabelecimentos por faixas de não-comprovação (ex: 0-10%, 10-20%), cruzando a quantidade de farmácias com o respectivo valor financeiro não comprovado em cada faixa para identificar a concentração de irregularidades.'" text severity="secondary" rounded />
        </div>
        <div class="chart-wrapper">
            <apexchart :key="themeStore.isDark ? 'dark-chart' : 'light-chart'" type="line" height="350" :options="chartOptions" :series="chartSeries"></apexchart>
        </div>
      </div>

      <!-- TABELA ANALISE NACIONAL -->
      <div class="table-section shadow-card">
        <div class="section-header">
           <i class="pi pi-table"></i>
           <h3>ANÁLISE NACIONAL</h3>
           <div class="spacer"></div>
        </div>
        
        <DataTable :value="filteredData" size="small" stripedRows removableSort sortField="percValSemComp" :sortOrder="-1" class="custom-table enterprise-table">
          <Column field="uf" header="UF" sortable footer="TOTAL" style="width: 5%"></Column>
          
          <Column field="cnpjs" header="Qtde CNPJs" sortable footer="34K" style="width: 10%">
             <template #body="slotProps">
                <span>{{ formatNumber(slotProps.data.cnpjs) }}</span>
             </template>
          </Column>

          <Column field="percValSemComp" header="% Valor Sem Comprovação" sortable footer="16,05%" style="width: 12%">
             <template #body="slotProps">
                <Tag :value="formatPercent(slotProps.data.percValSemComp)" :class="getRiskClass(slotProps.data.percValSemComp)" />
             </template>
          </Column>

          <Column field="valSemComp" header="Valor sem Comprovação" sortable footer="R$ 3,8B" style="width: 15%">
             <template #body="slotProps">
                <span>{{ formatBRL(slotProps.data.valSemComp) }}</span>
             </template>
          </Column>

          <Column field="totalMov" header="Valor Total Movimentado" sortable footer="R$ 23,7B" style="width: 15%">
             <template #body="slotProps">
                <span>{{ formatBRL(slotProps.data.totalMov) }}</span>
             </template>
          </Column>

          <Column field="percQtdeSemComp" header="% Qtde Meds s/ Comp" sortable footer="15,34%" style="width: 15%">
             <template #body="slotProps">
                <Tag :value="formatPercent(slotProps.data.percQtdeSemComp)" :class="getRiskClass(slotProps.data.percQtdeSemComp)" />
             </template>
          </Column>

          <Column field="qtdeSemComp" header="Qtde Meds s/ Comp" sortable footer="548M" style="width: 12%">
             <template #body="slotProps">
                <span>{{ formatNumber(slotProps.data.qtdeSemComp) }}</span>
             </template>
          </Column>

          <Column field="totalQtde" header="Qtde Total Meds" sortable footer="3,5B" style="width: 15%">
             <template #body="slotProps">
                <span>{{ formatNumber(slotProps.data.totalQtde) }}</span>
             </template>
          </Column>
        </DataTable>
      </div>
    </div>
  </div>
</template>

<style scoped>
.dashboard-container {
  display: flex;
  flex-direction: column;
  gap: 1.5rem;
  max-width: 1600px;
  margin: 0 auto;
}

/* KPI CARDS */
.kpi-grid {
  display: grid;
  grid-template-columns: repeat(5, 1fr); /* 5 cards na linha */
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
  justify-content: flex-start; /* changed */
  align-items: center;
  gap: 1rem; /* changed */
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
  opacity: 0.85; /* Softened contrast */
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

/* MAIN GRID */
.charts-table-grid {
  display: flex;
  flex-direction: column;
  gap: 1.5rem;
}

.spacer { flex: 1; }

.chart-placeholder {
  height: 350px;
  background: color-mix(in srgb, var(--primary-color) 5%, transparent);
  border-radius: 12px;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  border: 2px dashed var(--sidebar-border);
}

/* TABELA ESTILO ENTERPRISE */
:deep(.enterprise-table .p-datatable-thead > tr > th) {
  background: var(--table-header-bg) !important;
  color: var(--table-header-text) !important;
  font-size: 0.75rem;
  font-weight: 700;
  letter-spacing: 0.5px;
  text-transform: uppercase;
  padding: 0.75rem 0.5rem;
  border-bottom: 2px solid var(--sidebar-border) !important;
}

/* O DEFINITIVO PARA AS LINHAS BRANCAS */
:deep(.enterprise-table .p-datatable-tbody > tr > td) {
    background: var(--card-bg) !important;
    color: var(--text-color) !important;
    border-color: var(--sidebar-border) !important;
}

:deep(.enterprise-table.p-datatable-striped .p-datatable-tbody > tr.p-row-odd > td) {
    background: var(--table-stripe) !important;
}

/* Garante que o hover vença a regra da listra zebra */
:deep(.enterprise-table .p-datatable-tbody > tr:hover > td),
:deep(.enterprise-table.p-datatable-striped .p-datatable-tbody > tr.p-row-odd:hover > td) {
    background: var(--table-hover) !important;
}

:deep(.enterprise-table .p-datatable-tfoot td) {
  background: var(--table-header-bg) !important;
  color: var(--table-header-text) !important;
  font-weight: 800;
  padding: 0.75rem 0.5rem;
  font-size: 0.8rem;
  border-top: 2px solid var(--sidebar-border) !important;
}

:deep(.enterprise-table .p-datatable-tbody > tr) {
  font-size: 0.85rem;
  color: var(--text-color);
}

:deep(.enterprise-table .p-datatable-tbody > tr:nth-child(even)) {
  background-color: var(--table-stripe) !important;
}

.flex-cell {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  white-space: nowrap;
}

.flex-cell i {
  font-size: 0.8rem;
}

/* 🔄 FEEDBACK VISUAL (LOADING & ERROR) */
.loading-overlay {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  min-height: 200px;
  background: rgba(0, 0, 0, 0.05);
  border-radius: 12px;
  margin-bottom: 2rem;
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

:global(.view-local-filters) {
  display: flex;
  flex-direction: column;
}

:global(.local-filter-header) {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  font-size: 0.85rem;
  text-transform: uppercase;
  margin-bottom: 1rem;
  font-weight: 800;
  color: var(--text-color);
  letter-spacing: 1px;
}

:global(.local-filter-header i) {
  color: var(--primary-color);
}

:global(.local-filter-section) {
  margin-bottom: 1.5rem;
}

:global(.local-filter-label) {
  display: block;
  font-size: 0.8rem;
  text-transform: uppercase;
  margin-bottom: 0.75rem;
  font-weight: 600;
  color: var(--primary-color);
}

:global(.flex-col) { display: flex; flex-direction: column; }
</style>
