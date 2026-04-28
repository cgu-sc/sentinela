<script setup>
import { computed, watch, ref } from 'vue';
import { useCnpjDetailStore } from '@/stores/cnpjDetail';
import { storeToRefs } from 'pinia';
import { useFormatting } from '@/composables/useFormatting';
import { useChartTheme } from '@/config/chartTheme';

import Sidebar from 'primevue/sidebar';
import DataTable from 'primevue/datatable';
import Column from 'primevue/column';
import Skeleton from 'primevue/skeleton';
import VChart from 'vue-echarts';

const props = defineProps({
  visible: { type: Boolean, required: true },
  cnpj: { type: String, required: true },
  periodo: { type: String, default: null }, // 'YYYY-MM' or 'YYYY-S1'
});

const emit = defineEmits(['update:visible']);

const store = useCnpjDetailStore();
const { gtinDetalhamentoMensalData: data, gtinDetalhamentoMensalLoading: loading, gtinDetalhamentoMensalError: error } = storeToRefs(store);

const { formatCurrencyFull } = useFormatting();
const { chartTheme } = useChartTheme();

// Buscar dados ao abrir ou ao trocar o período
watch(() => props.visible, (newVal) => {
  if (newVal && props.cnpj && props.periodo) {
    store.fetchGtinDetalhamentoMensal(props.cnpj, props.periodo);
  }
});

const isVisible = computed({
  get: () => props.visible,
  set: (val) => emit('update:visible', val)
});

const localData = ref(null);
watch(() => data.value, (newVal) => {
  if (newVal) localData.value = newVal;
}, { immediate: true });

const summary = computed(() => localData.value?.summary);
const ranking = computed(() => localData.value?.ranking || []);

const formatMedName = (name) => {
  if (!name) return 'Substância Não Identificada';
  const exceptions = ['de', 'da', 'do', 'das', 'dos', 'com', 'sem', 'e', 'em'];
  return name.split(' ').map(word => {
    const w = word.toLowerCase();
    if (exceptions.includes(w)) return w;
    // Mantém maiúsculas para siglas após números se for uma estrutura com barra, mas para simplificar, Title Case padrão.
    return w.charAt(0).toUpperCase() + w.slice(1);
  }).join(' ');
};

const top5 = computed(() => {
  return ranking.value
    .filter(item => item.valor_sem_comprovacao > 0)
    .slice(0, 5);
});

const totalSemComprovacao = computed(() => {
  return ranking.value.reduce((acc, item) => acc + item.valor_sem_comprovacao, 0);
});

const totalComprovado = computed(() => {
  return ranking.value.reduce((acc, item) => acc + (item.valor_vendas - item.valor_sem_comprovacao), 0);
});

const chartOption = computed(() => {
  const c = chartTheme.value;
  // Pareto Inverso (para mostrar o maior em cima no ECharts bar-horizontal, a ordem deve ser inversa no data)
  const items = [...top5.value].reverse();

  const labels = items.map(item => formatMedName(item.medicamento));

  const values = items.map(item => item.valor_sem_comprovacao);

  return {
    backgroundColor: 'transparent',
    grid: { left: 10, right: 60, top: 20, bottom: 20 },
    tooltip: {
      trigger: 'axis',
      axisPointer: { type: 'shadow', shadowStyle: { color: c.axisShadow } },
      backgroundColor: c.tooltip,
      borderColor: c.tooltipBorder,
      textStyle: { color: c.tooltipText, fontSize: 12 },
      formatter: (params) => {
        const item = items[params[0].dataIndex];
        return `
          <div style="font-weight:600;margin-bottom:6px;max-width:250px;white-space:normal;">${formatMedName(item.medicamento)}</div>
          <div style="color:#ef4444;font-weight:700;">Prejuízo: ${formatCurrencyFull(item.valor_sem_comprovacao)}</div>
          <div style="font-size:11px;opacity:0.7;">Vendas Totais: ${formatCurrencyFull(item.valor_vendas)}</div>
          <div style="font-size:11px;opacity:0.7;">Irregularidade: ${item.pct_sem_comprovacao}%</div>
        `;
      }
    },
    xAxis: {
      type: 'value',
      axisLabel: { show: false },
      splitLine: { show: false }
    },
    yAxis: {
      type: 'category',
      data: labels,
      axisLabel: { 
        show: true,
        inside: true,
        verticalAlign: 'bottom',
        align: 'left',
        padding: [0, 0, 10, 0], // Move o texto para cima da barra
        color: c.text,
        opacity: 0.85,
        fontSize: 11, 
        fontWeight: 600
      },
      axisLine: { show: false },
      axisTick: { show: false }
    },
    series: [
      {
        type: 'bar',
        barWidth: 14, // Fina o suficiente para dar espaço ao texto acima
        data: values,
        label: {
          show: true,
          position: 'right',
          formatter: (p) => formatCurrencyFull(p.value),
          color: c.text,
          fontSize: 11,
          fontWeight: 600
        },
        itemStyle: {
          borderRadius: [0, 4, 4, 0],
          color: {
            type: 'linear', x: 0, y: 0, x2: 1, y2: 0,
            colorStops: [
              { offset: 0, color: 'rgba(239, 68, 68, 0.5)' },
              { offset: 1, color: '#ef4444' }
            ]
          }
        }
      }
    ]
  };
});

const formatMesLabel = (periodoStr) => {
  if (!periodoStr) return '';
  if (periodoStr.includes('S')) return periodoStr.replace('-', ' — ');
  const parts = periodoStr.split('-');
  if (parts.length === 2) {
    const d = new Date(parts[0], parseInt(parts[1]) - 1, 1);
    return d.toLocaleDateString('pt-BR', { month: 'long', year: 'numeric' }).replace(' de ', '/');
  }
  return periodoStr;
};

const periodoFormatado = computed(() => formatMesLabel(props.periodo));
</script>

<template>
  <Sidebar v-model:visible="isVisible" position="right" class="insight-sidebar" :showCloseIcon="false">
    <template #header>
      <div class="sidebar-header">
        <div class="sh-title">
          <i class="pi pi-bolt" />
          <span>Detalhamento Mensal</span>
        </div>
        <button class="sh-close" @click="isVisible = false"><i class="pi pi-times" /></button>
      </div>
    </template>

    <div class="sidebar-content">
      <div class="sc-title-area">
        <h2>{{ periodoFormatado }}</h2>
        <p>Análise de concentração de irregularidades por GTIN.</p>
      </div>

      <div v-if="error" class="error-state">
        <i class="pi pi-exclamation-triangle" />
        <p>{{ error }}</p>
      </div>

      <div v-else-if="summary" class="content-wrapper" :class="{ 'is-loading': loading }">
          <!-- KPIs -->
          <div class="kpi-grid">
            <div class="kpi-card">
              <span class="kpi-label">GTINs</span>
              <span class="kpi-val">{{ summary.total_gtins }}</span>
            </div>
            <div class="kpi-card">
              <span class="kpi-label">100% Regulares</span>
              <span class="kpi-val text-green">{{ summary.gtins_regulares }}</span>
            </div>
            <div class="kpi-card is-danger">
              <span class="kpi-label">Com Irregularidade</span>
              <span class="kpi-val">{{ summary.gtins_irregulares }}</span>
            </div>
          </div>

          <!-- Pareto Chart -->
          <div class="chart-section" v-if="top5.length > 0">
            <div class="section-title">
              <h3>Top 5 GTINs sem Comprovação</h3>
              <span class="subtitle">GTINs com maior valor de não comprovação.</span>
            </div>
            <div class="chart-container">
              <VChart class="chart" :option="chartOption" autoresize />
            </div>
          </div>

          <!-- Table -->
          <div class="table-section" v-if="ranking.length > 0">
            <div class="section-title">
              <h3>Detalhamento ({{ ranking.length }} itens)</h3>
            </div>
            <DataTable :value="ranking" class="insight-table p-datatable-sm" scrollable scrollHeight="flex" tableStyle="table-layout: fixed; width: 100%">
              <Column field="medicamento" header="Medicamento" style="width: 50%">
                <template #body="slotProps">
                  <div class="med-cell">
                    <span class="med-name" v-tooltip.bottom="formatMedName(slotProps.data.medicamento)">{{ formatMedName(slotProps.data.medicamento) }}</span>
                    <span class="med-gtin">{{ slotProps.data.gtin }}</span>
                  </div>
                </template>
                <template #footer>
                  <div style="text-align: right; font-weight: 700; color: color-mix(in srgb, var(--text-color) 85%, transparent); padding-right: 0.5rem; font-size: 0.85rem;">
                    Total do Período:
                  </div>
                </template>
              </Column>
              <Column field="valor_sem_comprovacao" header="Sem Comprovação" style="width: 25%; text-align: right">
                <template #body="slotProps">
                  <div class="val-cell">
                    <span class="val-danger">{{ formatCurrencyFull(slotProps.data.valor_sem_comprovacao) }}</span>
                    <span class="val-pct">{{ slotProps.data.pct_sem_comprovacao }}% (irregular)</span>
                  </div>
                </template>
                <template #footer>
                  <span class="val-danger" style="font-size: 0.95rem;">{{ formatCurrencyFull(totalSemComprovacao) }}</span>
                </template>
              </Column>
              <Column header="Comprovado" style="width: 25%; text-align: right">
                <template #body="slotProps">
                  <div class="val-cell">
                    <span class="val-regular">{{ formatCurrencyFull(slotProps.data.valor_vendas - slotProps.data.valor_sem_comprovacao) }}</span>
                    <span class="val-pct">{{ (100 - slotProps.data.pct_sem_comprovacao).toFixed(1).replace('.0', '') }}% (regular)</span>
                  </div>
                </template>
                <template #footer>
                  <span class="val-regular" style="font-size: 0.95rem;">{{ formatCurrencyFull(totalComprovado) }}</span>
                </template>
              </Column>
            </DataTable>
          </div>
          
          <div v-else class="empty-state">
            Nenhuma irregularidade neste período.
          </div>
        </div>
    </div>
  </Sidebar>
</template>

<style scoped>
.content-wrapper {
  transition: opacity 0.3s ease;
  display: flex;
  flex-direction: column;
  flex: 1;
  min-height: 0;
  gap: 2rem;
}

.content-wrapper.is-loading {
  opacity: 0.5;
  pointer-events: none;
}

:global(.insight-sidebar) {
  width: 600px !important;
  max-width: 100vw !important;
  background: var(--card-bg) !important;
  border-left: 1px solid var(--card-border) !important;
  padding: 0 !important;
}

:global(.insight-sidebar .p-sidebar-header) {
  padding: 0 !important;
  border-bottom: 1px solid var(--card-border) !important;
  background: color-mix(in srgb, var(--primary-color) 4%, transparent);
}

:global(.insight-sidebar .p-sidebar-content) {
  padding: 0 !important;
  overflow-y: hidden !important;
  overflow-x: hidden !important;
  display: flex;
  flex-direction: column;
}

.sidebar-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  width: 100%;
  padding: 1rem 1.5rem;
  flex-shrink: 0;
}

.sh-title {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  font-weight: 700;
  color: var(--primary-color);
  font-size: 1rem;
  letter-spacing: 0.03em;
  text-transform: uppercase;
}

.sh-close {
  background: none;
  border: none;
  color: var(--text-secondary);
  cursor: pointer;
  width: 32px;
  height: 32px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: all 0.2s;
}

.sh-close:hover {
  background: color-mix(in srgb, var(--text-color) 8%, transparent);
  color: var(--text-color);
}

.sidebar-content {
  padding: 1.5rem;
  display: flex;
  flex-direction: column;
  gap: 2rem;
  flex: 1;
  min-height: 0; /* Important for nested flex scrolling */
}

.table-section {
  flex: 1;
  display: flex;
  flex-direction: column;
  min-height: 0; /* Fixes PrimeVue table flex scrolling */
}

.sc-title-area h2 {
  margin: 0;
  font-size: 1.5rem;
  font-weight: 700;
  color: color-mix(in srgb, var(--text-color) 85%, transparent);
  text-transform: capitalize;
}

.sc-title-area p {
  margin: 0.25rem 0 0;
  font-size: 0.85rem;
  color: var(--text-secondary);
}

.kpi-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 1rem;
}

.kpi-card {
  background: transparent;
  border: 1px solid var(--card-border);
  border-radius: 8px;
  padding: 1rem;
  display: flex;
  flex-direction: column;
  align-items: center;
  text-align: center;
  gap: 0.5rem;
}

.kpi-card.is-danger {
  background: color-mix(in srgb, var(--risk-high, #ef4444) 4%, transparent);
  border-color: color-mix(in srgb, var(--risk-high, #ef4444) 30%, transparent);
}

.kpi-label {
  font-size: 0.7rem;
  text-transform: uppercase;
  font-weight: 600;
  color: var(--text-muted);
  letter-spacing: 0.05em;
}

.kpi-val {
  font-size: 1.5rem;
  font-weight: 700;
  color: color-mix(in srgb, var(--text-color) 85%, transparent);
}

.kpi-card.is-danger .kpi-val {
  color: var(--risk-high, #ef4444);
}

.text-green {
  color: var(--risk-low, #22c55e) !important;
}

.section-title {
  margin-bottom: 1rem;
}

.section-title h3 {
  margin: 0;
  font-size: 1rem;
  font-weight: 600;
  color: color-mix(in srgb, var(--text-color) 85%, transparent);
}

.section-title .subtitle {
  font-size: 0.75rem;
  color: var(--text-secondary);
}

.chart-container {
  height: 250px;
  width: 100%;
}

.med-cell {
  display: flex;
  flex-direction: column;
  min-width: 0;
  overflow: hidden;
}

.med-name {
  font-weight: 600;
  font-size: 0.8rem;
  color: color-mix(in srgb, var(--text-color) 85%, transparent);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  width: 100%;
}

.med-gtin {
  font-size: 0.7rem;
  color: var(--text-muted);
}

.val-cell {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 2px;
}

.val-danger {
  font-weight: 600;
  color: var(--risk-high, #ef4444);
  font-size: 0.85rem;
}

.val-regular {
  font-weight: 600;
  color: color-mix(in srgb, var(--text-color) 85%, transparent);
  font-size: 0.85rem;
}

.val-pct {
  font-size: 0.7rem;
  color: var(--text-muted);
  font-weight: 500;
}

.empty-state, .error-state {
  padding: 3rem;
  text-align: center;
  color: var(--text-secondary);
  background: transparent;
  border-radius: 8px;
  border: 1px dashed var(--card-border);
}

.error-state {
  color: var(--risk-high, #ef4444);
  border-color: color-mix(in srgb, var(--risk-high, #ef4444) 30%, transparent);
}

.error-state i {
  font-size: 2rem;
  margin-bottom: 1rem;
  opacity: 0.5;
}

/* Tabelas nativas para integrar com o tema Arbflow */
:global(.insight-table.p-datatable) {
  background: transparent;
}
:global(.insight-table.p-datatable .p-datatable-tbody > tr) {
  background: transparent;
  color: var(--text-secondary);
}
:global(.insight-table.p-datatable .p-datatable-tbody > tr:hover > td) {
  background: color-mix(in srgb, var(--text-color) 4%, transparent) !important;
}
:global(.insight-table.p-datatable .p-datatable-thead > tr > th) {
  background: color-mix(in srgb, var(--card-bg) 95%, var(--text-color) 5%);
  font-size: 0.75rem;
  text-transform: uppercase;
  color: var(--text-muted);
  font-weight: 600;
  padding: 0.5rem;
  border-bottom: 1px solid var(--card-border);
}

:global(.insight-table.p-datatable .p-datatable-tfoot > tr > td) {
  background: color-mix(in srgb, var(--card-bg) 95%, var(--text-color) 5%);
  padding: 0.75rem 0.5rem;
  border-top: 1px solid var(--card-border);
}

:global(.insight-table.p-datatable .p-datatable-tbody > tr > td) {
  padding: 0.5rem;
  background: transparent;
  border-bottom: 1px dashed var(--card-border);
}

:global(.insight-table.p-datatable .p-datatable-wrapper) {
  overflow-x: hidden !important;
}
</style>
