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
import Button from 'primevue/button';

const props = defineProps({
  visible: { type: Boolean, required: true },
  cnpj: { type: String, required: true },
  periodo: { type: String, default: null }, // 'YYYY-MM' or 'YYYY-S1'
  minPeriodo: { type: String, default: null },
  maxPeriodo: { type: String, default: null },
});

const emit = defineEmits(['update:visible']);

const store = useCnpjDetailStore();
const { gtinDetalhamentoMensalData: data, gtinDetalhamentoMensalLoading: loading, gtinDetalhamentoMensalError: error } = storeToRefs(store);

const { formatCurrencyFull } = useFormatting();
const { chartTheme } = useChartTheme();

const localVisible = computed({
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

const viewRange = ref('Mês');
const rangeOptions = ref(['Mês', 'Semestre']);

const overriddenPeriod = ref(null);

watch(() => props.periodo, () => {
  overriddenPeriod.value = null;
});

const currentActivePeriod = computed(() => overriddenPeriod.value || props.periodo);

// Calcula o período efetivo (seja o mês original ou o semestre correspondente)
const effectivePeriod = computed(() => {
  const base = currentActivePeriod.value;
  if (!base) return null;
  
  const isSem = base.includes('-S') || base.includes('S/');
  
  if (viewRange.value === 'Mês') {
    if (isSem) {
       const parts = base.includes('-S') ? base.split('-S') : base.split('S/');
       const y = base.includes('-S') ? parts[0] : parts[1];
       const s = base.includes('-S') ? parts[1].replace('S', '') : parts[0].replace('S', '');
       return `${y}-${s === '1' ? '01' : '07'}`;
    }
    return base;
  }
  
  // Modo Semestre
  if (!isSem) {
    const parts = base.split('-');
    if (parts.length < 2) return base;
    const y = parts[0];
    const m = parseInt(parts[1]);
    const s = m <= 6 ? '1' : '2';
    return `${y}-S${s}`;
  }
  
  // Normaliza formato S/ para -S
  if (base.includes('S/')) {
    const [s, y] = base.split('S/');
    return `${y}-S${s}`;
  }
  
  return base;
});

// Função para avançar ou voltar no tempo
const changePeriod = (direction) => {
  const base = effectivePeriod.value;
  if (!base) return;

  if (viewRange.value === 'Mês') {
    const [year, month] = base.split('-').map(Number);
    const d = new Date(year, month - 1 + direction, 1);
    const next = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
    
    // Check bounds
    if (props.minPeriodo && next < props.minPeriodo && direction < 0) return;
    if (props.maxPeriodo && next > props.maxPeriodo && direction > 0) return;
    
    overriddenPeriod.value = next;
  } else {
    // Ex: 2019-S1
    const [year, sStr] = base.split('-S');
    let y = parseInt(year);
    let s = parseInt(sStr.replace('S', ''));
    
    s += direction;
    if (s > 2) { s = 1; y++; }
    else if (s < 1) { s = 2; y--; }
    
    const next = `${y}-S${s}`;
    
    // Check bounds for semester
    if (props.minPeriodo && props.maxPeriodo) {
      const semMin = `${y}-${s === 1 ? '01' : '07'}`;
      const semMax = `${y}-${s === 1 ? '06' : '12'}`;
      if (direction < 0 && props.minPeriodo > semMax) return;
      if (direction > 0 && props.maxPeriodo < semMin) return;
    }
    
    overriddenPeriod.value = next;
  }
};

const canGoPrev = computed(() => {
  const base = effectivePeriod.value;
  if (!base || !props.minPeriodo) return true;
  
  if (viewRange.value === 'Mês') {
    const [year, month] = base.split('-').map(Number);
    const d = new Date(year, month - 2, 1);
    const prev = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
    return prev >= props.minPeriodo;
  } else {
    const [year, sStr] = base.split('-S');
    let py = parseInt(year);
    let ps = parseInt(sStr) - 1;
    if (ps < 1) { ps = 2; py--; }
    const prevSemMax = `${py}-${ps === 1 ? '06' : '12'}`;
    return prevSemMax >= props.minPeriodo;
  }
});

const canGoNext = computed(() => {
  const base = effectivePeriod.value;
  if (!base || !props.maxPeriodo) return true;
  
  if (viewRange.value === 'Mês') {
    const [year, month] = base.split('-').map(Number);
    const d = new Date(year, month, 1);
    const next = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
    return next <= props.maxPeriodo;
  } else {
    const [year, sStr] = base.split('-S');
    let ny = parseInt(year);
    let ns = parseInt(sStr) + 1;
    if (ns > 2) { ns = 1; ny++; }
    const nextSemMin = `${ny}-${ns === 1 ? '01' : '07'}`;
    return nextSemMin <= props.maxPeriodo;
  }
});

// Buscar dados ao abrir ou ao trocar o período (ou abrangência)
watch([() => props.visible, effectivePeriod], ([visible, period]) => {
  if (visible && props.cnpj && period) {
    store.fetchGtinDetalhamentoMensal(props.cnpj, period);
  }
});

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
  
  // Trata formato de semestre (ex: 2019-S1 ou 1S/2019)
  if (periodoStr.includes('S')) {
    const isYearFirst = periodoStr.includes('-S');
    const parts = isYearFirst ? periodoStr.split('-S') : periodoStr.split('S/');
    const year = isYearFirst ? parts[0] : parts[1];
    const sem = isYearFirst ? parts[1] : parts[0];
    return `${sem}º Semestre de ${year}`;
  }

  const parts = periodoStr.split('-');
  if (parts.length === 2) {
    const d = new Date(parts[0], parseInt(parts[1]) - 1, 1);
    return d.toLocaleDateString('pt-BR', { month: 'long', year: 'numeric' }).replace(' de ', '/');
  }
  return periodoStr;
};

const periodoFormatado = computed(() => formatMesLabel(effectivePeriod.value));
</script>

<template>
  <Sidebar v-model:visible="localVisible" position="right" class="insight-sidebar" :showCloseIcon="false">
    <template #header>
      <div class="sidebar-header">
        <div class="sh-title">
          <span>Detalhamento {{ viewRange === 'Mês' ? 'Mensal' : 'Semestral' }}</span>
        </div>
        <button class="sh-close" @click="localVisible = false"><i class="pi pi-times" /></button>
      </div>
    </template>

    <div class="sidebar-content">
      <div class="sc-header-row">
        <!-- Toolbar de Filtros no Topo -->
        <div class="filter-toolbar">
          <div class="filter-item">
            <span class="filter-label">Abrangência:</span>
            <SelectButton v-model="viewRange" :options="rangeOptions" class="p-button-sm custom-select-button" :allowEmpty="false" />
          </div>
          <div class="filter-item">
            <span class="filter-label">Agrupar:</span>
            <SelectButton v-model="groupMode" :options="groupOptions" class="p-button-sm custom-select-button" :allowEmpty="false" />
          </div>
        </div>

        <!-- Título e Navegação Abaixo -->
        <div class="title-group-main">
          <div class="nav-wrapper">
            <Button icon="pi pi-chevron-left" class="p-button-text p-button-sm nav-btn" @click="changePeriod(-1)" :disabled="!canGoPrev" v-tooltip.bottom="'Voltar período'" />
            <h2 class="current-period">{{ periodoFormatado }}</h2>
            <Button icon="pi pi-chevron-right" class="p-button-text p-button-sm nav-btn" @click="changePeriod(1)" :disabled="!canGoNext" v-tooltip.bottom="'Avançar período'" />
          </div>
          <p class="sc-subtitle">Análise de concentração de irregularidades.</p>
        </div>
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
              <VChart v-if="localVisible && top5.length > 0" class="chart" :option="chartOption" autoresize />
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
  gap: 1.5rem;
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
  padding: 0.5rem 1.5rem;
  flex-shrink: 0;
}

.sh-title {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  font-weight: 700;
  color: var(--primary-color);
  font-size: 0.85rem;
  letter-spacing: 0.05em;
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
  padding: 0.75rem 1.5rem 1.5rem;
  display: flex;
  flex-direction: column;
  gap: 1.25rem;
  flex: 1;
  min-height: 0; /* Important for nested flex scrolling */
}

.table-section {
  flex: 1;
  display: flex;
  flex-direction: column;
  min-height: 0; /* Fixes PrimeVue table flex scrolling */
}

.sc-header-row {
  display: flex;
  flex-direction: column;
  gap: 1.25rem;
  margin-bottom: 0 !important;
  padding-bottom: 1rem;
  border-bottom: 1px solid color-mix(in srgb, var(--card-border) 40%, transparent);
}

.filter-toolbar {
  display: flex;
  justify-content: space-between;
  align-items: center;
  background: color-mix(in srgb, var(--primary-color) 3%, transparent);
  padding: 0.75rem 1rem;
  border-radius: 8px;
  border: 1px solid color-mix(in srgb, var(--card-border) 60%, transparent);
}

.title-group-main {
  display: flex;
  flex-direction: column;
  align-items: center;
  text-align: center;
}

.nav-wrapper {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 1.5rem;
  margin-bottom: 0.4rem;
}

.current-period {
  margin: 0;
  font-size: 1.4rem;
  font-weight: 800;
  color: var(--text-color);
  letter-spacing: -0.03em;
  min-width: 280px;
}

.sc-subtitle {
  margin: 0 !important;
  color: var(--text-secondary) !important;
  font-size: 0.85rem !important;
}

.filter-item {
  display: flex;
  align-items: center;
  gap: 0.75rem;
}

.filter-label {
  font-size: 0.7rem;
  color: var(--text-muted);
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  opacity: 0.8;
}

.nav-btn {
  color: var(--text-muted) !important;
  opacity: 0.4;
  transition: all 0.2s;
}

.nav-btn:disabled {
  opacity: 0.1 !important;
  cursor: default;
}

.nav-btn:not(:disabled):hover {
  opacity: 1;
  color: var(--primary-color) !important;
  background: color-mix(in srgb, var(--primary-color) 8%, transparent) !important;
}

.nav-btn:focus,
.nav-btn.p-focus {
  box-shadow: none !important;
  outline: none !important;
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
