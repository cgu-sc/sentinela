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
import SelectButton from 'primevue/selectbutton';
import InputSwitch from 'primevue/inputswitch';

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

const groupMode = ref('GTIN');
const groupOptions = ref(['GTIN', 'Princípio Ativo']);
const showOnlyIrregular = ref(false);

const dynamicSummary = computed(() => {
  const list = ranking.value;
  const total = list.length;
  const irregulares = list.filter(item => item.valor_sem_comprovacao > 0).length;
  const regulares = total - irregulares;
  return { total, regulares, irregulares };
});

const ranking = computed(() => {
  const raw = localData.value?.ranking || [];
  if (groupMode.value === 'GTIN') return raw;

  // Agrupamento por Princípio Ativo
  const grouped = {};
  raw.forEach(item => {
    const key = item.principio_ativo || item.medicamento || 'Substância Não Identificada';
    if (!grouped[key]) {
      grouped[key] = {
        medicamento: key,
        principio_ativo: item.principio_ativo,
        gtin_count: 0,
        qnt_vendas: 0,
        qnt_vendas_sem_comprovacao: 0,
        valor_vendas: 0,
        valor_sem_comprovacao: 0
      };
    }
    grouped[key].gtin_count += 1;
    grouped[key].qnt_vendas += item.qnt_vendas;
    grouped[key].qnt_vendas_sem_comprovacao += item.qnt_vendas_sem_comprovacao;
    grouped[key].valor_vendas += item.valor_vendas;
    grouped[key].valor_sem_comprovacao += item.valor_sem_comprovacao;
  });

  return Object.values(grouped).map(g => {
    // Recalcular a porcentagem
    g.pct_sem_comprovacao = g.valor_vendas > 0 
      ? parseFloat(((g.valor_sem_comprovacao / g.valor_vendas) * 100).toFixed(2))
      : 0;
    return g;
  }).sort((a, b) => b.valor_sem_comprovacao - a.valor_sem_comprovacao);
});

const displayedRanking = computed(() => {
  if (showOnlyIrregular.value) {
    return ranking.value.filter(item => item.valor_sem_comprovacao > 0);
  }
  return ranking.value;
});

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

  const labels = items.map(item => {
    const name = formatMedName(item.medicamento);
    return groupMode.value === 'GTIN' ? name : `${name} (${item.gtin_count})`;
  });

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
        const isGrouped = groupMode.value === 'Princípio Ativo';
        const subInfo = isGrouped 
          ? `<div style="font-size:10px;color:var(--primary-color);font-weight:600;margin-bottom:4px;">${item.gtin_count} GTIN(s) agrupados</div>`
          : `<div style="font-size:10px;opacity:0.6;margin-bottom:4px;">GTIN: ${item.gtin}</div>`;

        return `
          <div style="font-weight:600;margin-bottom:2px;max-width:250px;white-space:normal;">${formatMedName(item.medicamento)}</div>
          ${subInfo}
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
      <div class="sc-title-area" style="display: flex; justify-content: space-between; align-items: flex-start; gap: 1rem;">
        <div>
          <h2>{{ periodoFormatado }}</h2>
          <p>Análise de concentração de irregularidades.</p>
        </div>
        <SelectButton v-model="groupMode" :options="groupOptions" class="p-button-sm custom-select-button" :allowEmpty="false" />
      </div>

      <div v-if="error" class="error-state">
        <i class="pi pi-exclamation-triangle" />
        <p>{{ error }}</p>
      </div>

      <div v-else-if="localData" class="content-wrapper" :class="{ 'is-loading': loading }">
          <!-- KPIs -->
          <div class="kpi-grid">
            <div class="kpi-card">
              <span class="kpi-label">{{ groupMode === 'GTIN' ? 'GTINs' : 'Princípios Ativos' }}</span>
              <span class="kpi-val">{{ dynamicSummary.total }}</span>
            </div>
            <div class="kpi-card">
              <span class="kpi-label">100% Regulares</span>
              <span class="kpi-val">{{ dynamicSummary.regulares }}</span>
            </div>
            <div class="kpi-card is-danger">
              <span class="kpi-label">Com Irregularidade</span>
              <span class="kpi-val">{{ dynamicSummary.irregulares }}</span>
            </div>
          </div>

          <!-- Pareto Chart -->
          <div class="chart-section" v-if="top5.length > 0">
            <div class="section-title">
              <h3>Top 5</h3>
              <span class="subtitle">Itens com maior valor de não comprovação.</span>
            </div>
            <div class="chart-container">
              <VChart class="chart" :option="chartOption" autoresize />
            </div>
          </div>

          <!-- Table -->
          <div class="table-section" v-if="ranking.length > 0">
            <div class="section-title" style="display: flex; justify-content: space-between; align-items: flex-end;">
              <h3>Detalhamento ({{ displayedRanking.length }} itens)</h3>
              <div style="display: flex; align-items: center; gap: 8px;">
                <label for="filter-irregular" style="font-size: 0.75rem; color: var(--text-secondary); font-weight: 600; cursor: pointer;">Apenas Irregulares</label>
                <InputSwitch inputId="filter-irregular" v-model="showOnlyIrregular" />
              </div>
            </div>
            <DataTable :value="displayedRanking" class="insight-table p-datatable-sm" scrollable scrollHeight="flex" tableStyle="table-layout: fixed; width: 100%">
              <Column field="medicamento" header="Detalhamento do Item" style="width: 50%">
                <template #body="slotProps">
                  <div class="med-cell">
                    <template v-if="groupMode === 'GTIN'">
                      <span class="med-name" v-tooltip.bottom="formatMedName(slotProps.data.produto || slotProps.data.medicamento)">
                        {{ formatMedName(slotProps.data.produto || slotProps.data.medicamento) }}
                        <span v-if="slotProps.data.laboratorio" class="med-lab">({{ slotProps.data.laboratorio }})</span>
                      </span>
                      <span class="med-sub" v-if="slotProps.data.principio_ativo && slotProps.data.principio_ativo !== slotProps.data.produto">
                        {{ slotProps.data.principio_ativo }}
                      </span>
                      <span class="med-gtin">GTIN: {{ slotProps.data.gtin }}</span>
                    </template>
                    <template v-else>
                      <span class="med-name" v-tooltip.bottom="formatMedName(slotProps.data.medicamento)">
                        {{ formatMedName(slotProps.data.medicamento) }}
                      </span>
                      <span class="med-gtin">{{ slotProps.data.gtin_count }} GTIN(s) associado(s)</span>
                    </template>
                  </div>
                </template>
              </Column>
              <Column field="valor_sem_comprovacao" header="Sem Comprovação" style="width: 25%; text-align: right">
                <template #body="slotProps">
                  <div class="val-cell">
                    <span :class="slotProps.data.valor_sem_comprovacao > 0 ? 'val-danger' : 'val-regular'">{{ formatCurrencyFull(slotProps.data.valor_sem_comprovacao) }}</span>
                    <span class="val-pct">{{ slotProps.data.pct_sem_comprovacao }}% (irregular)</span>
                  </div>
                </template>
              </Column>
              <Column header="Comprovado" style="width: 25%; text-align: right">
                <template #body="slotProps">
                  <div class="val-cell">
                    <span class="val-regular">{{ formatCurrencyFull(slotProps.data.valor_vendas - slotProps.data.valor_sem_comprovacao) }}</span>
                    <span class="val-pct">{{ (100 - slotProps.data.pct_sem_comprovacao).toFixed(1).replace('.0', '') }}% (regular)</span>
                  </div>
                </template>
              </Column>
              <template #footer>
                <div class="custom-dt-footer">
                  <div class="cf-label">Total do Período:</div>
                  <div class="cf-val" :class="totalSemComprovacao > 0 ? 'val-danger' : 'val-regular'">{{ formatCurrencyFull(totalSemComprovacao) }}</div>
                  <div class="cf-val val-regular">{{ formatCurrencyFull(totalComprovado) }}</div>
                </div>
              </template>
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

.med-sub {
  font-size: 0.75rem;
  color: var(--text-secondary);
  opacity: 0.8;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.med-lab {
  font-size: 0.7rem;
  color: var(--text-muted);
  font-weight: 400;
  margin-left: 4px;
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

.custom-dt-footer {
  display: flex;
  align-items: center;
  width: 100%;
}

.cf-label {
  width: 50%;
  text-align: right;
  font-weight: 700;
  color: color-mix(in srgb, var(--text-color) 85%, transparent);
  padding-right: 1.5rem;
  font-size: 0.85rem;
}

.cf-val {
  width: 25%;
  text-align: right;
  font-size: 0.95rem;
  padding: 0 0.5rem;
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
  display: flex;
  flex-direction: column;
  flex: 1;
  min-height: 0;
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

:global(.insight-table.p-datatable .p-datatable-footer) {
  background: color-mix(in srgb, var(--card-bg) 95%, var(--text-color) 5%);
  padding: 0.75rem 0;
  border-top: 1px solid var(--card-border);
  margin-top: auto;
}

:global(.insight-table.p-datatable .p-datatable-tbody > tr > td) {
  padding: 0.5rem;
  background: transparent;
  border-bottom: 1px dashed var(--card-border);
}

:global(.insight-table.p-datatable .p-datatable-wrapper) {
  overflow-x: hidden !important;
}

:global(.insight-sidebar .custom-select-button .p-button) {
  padding: 0.4rem 0.75rem;
  font-size: 0.75rem;
  font-weight: 600;
  background: color-mix(in srgb, var(--card-bg) 50%, transparent);
  border-color: var(--card-border);
  color: var(--text-secondary);
  transition: all 0.2s;
}

:global(.insight-sidebar .custom-select-button .p-button.p-highlight) {
  background: color-mix(in srgb, var(--primary-color) 15%, transparent);
  border: 1px solid var(--primary-color) !important;
  color: var(--primary-color);
  position: relative;
  z-index: 2 !important;
}

:global(.insight-sidebar .custom-select-button .p-button:not(.p-highlight):hover) {
  background: color-mix(in srgb, var(--text-color) 5%, transparent);
  color: var(--text-color);
}

:global(.insight-sidebar .custom-select-button .p-button:focus),
:global(.insight-sidebar .custom-select-button .p-button.p-focus) {
  box-shadow: none !important;
  outline: none !important;
}

:global(.insight-sidebar .p-inputswitch.p-inputswitch-checked .p-inputswitch-slider),
:global(.insight-sidebar .p-inputswitch.p-highlight .p-inputswitch-slider),
:global(.insight-sidebar .p-inputswitch:has(input:checked) .p-inputswitch-slider) {
  background: var(--primary-color) !important;
}

:global(.insight-sidebar .p-inputswitch .p-inputswitch-slider) {
  background: color-mix(in srgb, var(--text-muted) 30%, transparent);
}

:global(.insight-sidebar .p-inputswitch.p-focus .p-inputswitch-slider) {
  box-shadow: none !important;
}
</style>
