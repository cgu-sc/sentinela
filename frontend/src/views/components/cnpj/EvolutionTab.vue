<script setup>
import { computed, ref, nextTick } from 'vue';
import { useRoute } from 'vue-router';
import { useCnpjDetailStore } from '@/stores/cnpjDetail';
import { storeToRefs } from 'pinia';
import { useFilterStore } from '@/stores/filters';
import { useFrozenData } from '@/composables/useFrozenData';
import { watch } from 'vue';
import { useFormatting } from '@/composables/useFormatting';
import { useChartTheme } from '@/config/chartTheme';
import { RISK_THRESHOLDS } from '@/config/riskConfig';

import VChart from 'vue-echarts';
import { use } from 'echarts/core';
import { BarChart } from 'echarts/charts';
import { GridComponent, TooltipComponent, LegendComponent, DataZoomComponent } from 'echarts/components';
import { CanvasRenderer } from 'echarts/renderers';

import DataTable from 'primevue/datatable';
import Column from 'primevue/column';
import ColumnGroup from 'primevue/columngroup';
import Row from 'primevue/row';

use([BarChart, GridComponent, TooltipComponent, LegendComponent, DataZoomComponent, CanvasRenderer]);

const route = useRoute();
const cnpj = computed(() => route.params.cnpj);

const { formatCurrencyFull } = useFormatting();
const { chartTheme, chartDataColors } = useChartTheme();
const filterStore = useFilterStore();

const cnpjDetailStore = useCnpjDetailStore();
const { evolucaoFinanceira: evolucaoData, evolucaoLoading, evolucaoLoaded, evolucaoError, evolucaoMensalGtin, evolucaoMensalGtinLoading } = storeToRefs(cnpjDetailStore);

// ── Cache de Dados para Transição Suave (Flicker-Free) ──────────────────
// Mantém os dados do semestre anterior visíveis durante a animação de período.
const cachedEvolucaoData = useFrozenData(evolucaoData, evolucaoLoading);

const chartRef = ref(null);

/**
 * Formata o intervalo real de meses de um semestre (ex: "mai – jun").
 * Quando o semestre é completo (jan–jun ou jul–dez) retorna null — não é
 * necessário repetir o óbvio. Quando é parcial, exibe os meses reais.
 */
function formatMesRange(mesInicio, mesFim) {
  if (!mesInicio || !mesFim) return null;
  const fmt = (iso) =>
    new Date(iso + '-02')
      .toLocaleDateString('pt-BR', { month: 'short' })
      .replace('.', '');
  const mi = fmt(mesInicio);
  const mf = fmt(mesFim);
  return mi === mf ? mi : `${mi} – ${mf}`;
}

// Verdadeiro quando há dados anteriores visíveis E um novo fetch está em curso.
// Usado para dimir os cards suavemente em vez de exibir o spinner novamente.
// NOTA: Durante a animação (autoplay), mantemos a opacidade total para evitar flicker.
const isRefreshing = computed(() => evolucaoLoading.value && cachedEvolucaoData.value !== null && !filterStore.isAnimating);

const expandedRows = ref([]);

/**
 * Alterna a expansão da linha ao clicar em qualquer célula da linha pai.
 * O PrimeVue usa um objeto { [dataKey]: rowData } para controlar as linhas expandidas.
 */
function toggleRow(event) {
  const row = event.data;
  const key = row.semestre;
  const current = { ...expandedRows.value };
  if (current[key]) {
    delete current[key];
  } else {
    current[key] = row;
  }
  expandedRows.value = current;
}

/**
 * Disparado ao clicar em uma barra no gráfico ECharts.
 * O `params.name` neste gráfico contém a label do Eixo X (o Semestre, ex: "1S/2021").
 */
function onChartClick(params) {
  if (!params || !params.name) return;
  const semestre = params.name;
  
  if (!cachedEvolucaoData.value?.semestres) return;
  
  const rowData = cachedEvolucaoData.value.semestres.find(s => s.semestre === semestre);
  if (!rowData) return;

  // Auto-expande a sanfona do respectivo semestre (fechando as outras se existirem)
  expandedRows.value = { [semestre]: rowData };

  // Localiza o elemento renderizado da tabela no DOM para rolar a tela suavemente até ele
  nextTick(() => {
    const labels = document.querySelectorAll('.sem-label');
    for (let el of labels) {
      if (el.textContent.includes(semestre)) {
        el.closest('tr').scrollIntoView({ behavior: 'smooth', block: 'center' });
        break;
      }
    }
  });
}

function formatMonth(mesIso) {
  if (!mesIso) return '';
  const [year, month] = mesIso.split('-');
  const date = new Date(year, parseInt(month) - 1);
  return date.toLocaleDateString('pt-BR', { month: 'short', year: 'numeric' }).replace(' de ', '/').toUpperCase();
}

function abrirInfratores(mes) {
  console.log("Abrir modal de inflatores do mês:", mes);
  // Futuro: abrir um dialog/sidebar com os top N medicamentes do mês.
}

defineExpose({
  getChartImage: (pixelRatio = 2) =>
    chartRef.value?.chart?.getDataURL({ type: 'jpeg', pixelRatio, backgroundColor: '#ffffff', quality: 0.85 }) ?? null,
  getSemestresData: () => cachedEvolucaoData.value?.semestres ?? [],
});

// ── Cores dos gráficos ────────────────────────────────────
const C = computed(() => ({
  ...chartTheme.value,
  ...chartDataColors.value,
}));

// ── Opção: barras empilhadas ──────────────────────────────
const chartOption = computed(() => {
  const c         = C.value;
  const semestres = cachedEvolucaoData.value?.semestres ?? [];
  const labels    = semestres.map(s => s.semestre);
  const regular   = semestres.map(s => s.regular);
  const irregular = semestres.map(s => s.irregular);

  return {
    backgroundColor: c.bg,
    animation: true,
    animationDuration: 900,
    animationEasing: 'cubicOut',
    textStyle: { fontFamily: 'Inter, sans-serif' },

    legend: {
      top: 6,
      left: 'center',
      textStyle: { color: c.muted, fontSize: 12, fontWeight: 600 },
      itemGap: 24,
      itemWidth: 14,
      itemHeight: 8,
    },

    grid: { top: 44, left: 80, right: 24, bottom: 32, containLabel: false },

    tooltip: {
      trigger: 'axis',
      axisPointer: { type: 'shadow', shadowStyle: { color: c.axisShadow } },
      backgroundColor: c.tooltip,
      borderColor: c.tooltipBorder,
      borderWidth: 1,
      padding: [12, 16],
      textStyle: { color: c.tooltipText, fontFamily: 'Inter, sans-serif', fontSize: 12 },
      shadowBlur: 10,
      shadowColor: 'rgba(0,0,0,0.15)',
      formatter: (params) => {
        const idx = params[0]?.dataIndex ?? 0;
        const s   = semestres[idx];
        if (!s) return '';
        return `
          <div style="color: ${c.tooltipText}">
            <div style="font-weight:700;font-size:14px;margin-bottom:10px;">${s.semestre}</div>
            <div style="display:flex;flex-direction:column;gap:6px;">
              <div style="display:flex;align-items:center;gap:8px;">
                <span style="width:10px;height:10px;border-radius:2px;background:${c.green};display:inline-block;"></span>
                <span style="font-size:10px;opacity:.6;letter-spacing:.04em;text-transform:uppercase;">Regulares</span>
              </div>
              <div style="font-weight:700;font-size:13px;margin-bottom:2px;">${formatCurrencyFull(s.regular)}</div>
              <div style="display:flex;align-items:center;gap:8px;">
                <span style="width:10px;height:10px;border-radius:2px;background:${c.red};display:inline-block;"></span>
                <span style="font-size:10px;opacity:.6;letter-spacing:.04em;text-transform:uppercase;">Irregulares</span>
              </div>
              <div style="font-weight:700;font-size:13px;color:${c.red};margin-bottom:2px;">${formatCurrencyFull(s.irregular)} <span style="opacity:.7">(${s.pct_irregular.toFixed(1)}%)</span></div>
              <div style="border-top:1px solid ${c.tooltipBorder};padding-top:6px;margin-top:2px;font-weight:700;font-size:13px;">Total: ${formatCurrencyFull(s.total)}</div>
            </div>
          </div>`;
      },
    },

    xAxis: {
      type: 'category',
      data: labels,
      axisLine:  { lineStyle: { color: c.grid } },
      axisTick:  { show: false },
      axisLabel: { color: c.muted, fontSize: 11, fontWeight: 700, fontFamily: 'Inter, sans-serif' },
    },

    yAxis: {
      type: 'value',
      axisLine:  { show: false },
      axisTick:  { show: false },
      splitLine: { lineStyle: { color: c.grid, type: 'dashed' } },
      axisLabel: { color: c.muted, fontSize: 10, formatter: v => formatCurrencyFull(v) },
    },

    series: [
      {
        name: 'Regulares',
        type: 'bar',
        stack: 'total',
        barMaxWidth: 56,
        data: regular,
        itemStyle: {
          color: {
            type: 'linear', x: 0, y: 0, x2: 0, y2: 1,
            colorStops: [
              { offset: 0, color: c.greenGrad },
              { offset: 1, color: c.green + '55' },
            ],
          },
        },
        emphasis: { focus: 'series' },
      },
      {
        name: 'Irregulares',
        type: 'bar',
        stack: 'total',
        barMaxWidth: 56,
        data: irregular,
        itemStyle: {
          borderRadius: [6, 6, 0, 0],
          color: {
            type: 'linear', x: 0, y: 0, x2: 0, y2: 1,
            colorStops: [
              { offset: 0, color: c.redGrad },
              { offset: 1, color: c.red + '55' },
            ],
          },
        },
        emphasis: { focus: 'series' },
      },
    ],
  };
});


// ── Gráfico Mensal GTIN ───────────────────────────────────

/**
 * Retorna true se o mês "YYYY-MM" pertence ao semestre "1S/2024" ou "2S/2024".
 */
function mesPertenceAoSemestre(mesStr, semestre) {
  if (!mesStr || !semestre) return false;
  const [semPart, anoPart] = semestre.split('/');
  const semNum = parseInt(semPart);
  const anoNum = parseInt(anoPart);
  const [y, m] = mesStr.split('-').map(Number);
  return y === anoNum && (semNum === 1 ? m <= 6 : m > 6);
}

function chartOptionMensalGtin(semestre) {
  const c    = C.value;
  const meses = evolucaoMensalGtin.value?.meses ?? [];

  const labels    = meses.map(m => m.mes);
  const regular   = meses.map(m => ({
    value: parseFloat((m.valor_vendas - m.valor_sem_comprovacao).toFixed(2)),
    itemStyle: { opacity: mesPertenceAoSemestre(m.mes, semestre) ? 1 : 0.35 },
  }));
  const irregular = meses.map(m => ({
    value: parseFloat(m.valor_sem_comprovacao.toFixed(2)),
    itemStyle: { opacity: mesPertenceAoSemestre(m.mes, semestre) ? 1 : 0.35 },
  }));

  // Centraliza o zoom no semestre selecionado
  const total = meses.length;
  let zoomStart = 0, zoomEnd = 100;
  if (total > 0 && semestre) {
    const [semPart, anoPart] = semestre.split('/');
    const semNum = parseInt(semPart);
    const anoNum = parseInt(anoPart);
    const indices = meses.reduce((acc, m, i) => {
      const [y, mo] = m.mes.split('-').map(Number);
      if (y === anoNum && (semNum === 1 ? mo <= 6 : mo > 6)) acc.push(i);
      return acc;
    }, []);
    if (indices.length) {
      const pad = 2;
      const first = Math.max(0, indices[0] - pad);
      const last  = Math.min(total - 1, indices[indices.length - 1] + pad);
      zoomStart = Math.round((first / total) * 100);
      zoomEnd   = Math.round(((last + 1) / total) * 100);
    }
  }

  const formatLabel = (iso) => {
    if (!iso) return '';
    const [y, mo] = iso.split('-');
    return new Date(parseInt(y), parseInt(mo) - 1)
      .toLocaleDateString('pt-BR', { month: 'short', year: '2-digit' })
      .replace(' de ', '/');
  };

  return {
    backgroundColor: 'transparent',
    animation: true,
    animationDuration: 600,
    animationEasing: 'cubicOut',
    textStyle: { fontFamily: 'Inter, sans-serif' },

    legend: {
      top: 4,
      left: 'center',
      textStyle: { color: c.muted, fontSize: 11, fontWeight: 600 },
      itemGap: 20,
      itemWidth: 12,
      itemHeight: 7,
    },

    grid: { top: 36, left: 64, right: 16, bottom: 52, containLabel: false },

    tooltip: {
      trigger: 'axis',
      axisPointer: { type: 'shadow', shadowStyle: { color: c.axisShadow } },
      backgroundColor: c.tooltip,
      borderColor: c.tooltipBorder,
      borderWidth: 1,
      padding: [10, 14],
      textStyle: { color: c.tooltipText, fontFamily: 'Inter, sans-serif', fontSize: 12 },
      formatter: (params) => {
        const idx = params[0]?.dataIndex ?? 0;
        const m   = meses[idx];
        if (!m) return '';
        const total = m.valor_vendas;
        const irr   = m.valor_sem_comprovacao;
        const reg   = total - irr;
        return `
          <div style="color:${c.tooltipText}">
            <div style="font-weight:600;font-size:13px;margin-bottom:8px;">${formatLabel(m.mes)}</div>
            <div style="display:flex;flex-direction:column;gap:5px;">
              <div style="display:flex;align-items:center;gap:8px;">
                <span style="width:9px;height:9px;border-radius:2px;background:${c.green};display:inline-block;"></span>
                <span style="font-size:10px;opacity:.6;text-transform:uppercase;letter-spacing:.04em;">Regulares</span>
              </div>
              <div style="font-weight:600;font-size:12px;margin-bottom:2px;">${formatCurrencyFull(reg)}</div>
              <div style="display:flex;align-items:center;gap:8px;">
                <span style="width:9px;height:9px;border-radius:2px;background:${c.red};display:inline-block;"></span>
                <span style="font-size:10px;opacity:.6;text-transform:uppercase;letter-spacing:.04em;">Irregulares</span>
              </div>
              <div style="font-weight:600;font-size:12px;color:${c.red};margin-bottom:2px;">${formatCurrencyFull(irr)} <span style="opacity:.7">(${m.pct_sem_comprovacao.toFixed(1)}%)</span></div>
              <div style="border-top:1px solid ${c.tooltipBorder};padding-top:5px;margin-top:2px;font-weight:600;font-size:12px;">Total: ${formatCurrencyFull(total)}</div>
            </div>
          </div>`;
      },
    },

    xAxis: {
      type: 'category',
      data: labels,
      axisLine:  { lineStyle: { color: c.grid } },
      axisTick:  { show: false },
      axisLabel: {
        color: c.muted, fontSize: 10, fontFamily: 'Inter, sans-serif',
        formatter: formatLabel,
        interval: 'auto',
        rotate: 30,
      },
    },

    yAxis: {
      type: 'value',
      axisLine:  { show: false },
      axisTick:  { show: false },
      splitLine: { lineStyle: { color: c.grid, type: 'dashed' } },
      axisLabel: { color: c.muted, fontSize: 9, formatter: v => formatCurrencyFull(v) },
    },

    dataZoom: [
      { type: 'inside', start: zoomStart, end: zoomEnd, zoomLock: false },
      {
        type: 'slider', start: zoomStart, end: zoomEnd, height: 14,
        bottom: 4,
        borderColor: c.grid,
        fillerColor: c.axisShadow,
        handleStyle: { color: c.muted },
        textStyle: { color: 'transparent' },
      },
    ],

    series: [
      {
        name: 'Regulares',
        type: 'bar',
        stack: 'total',
        barMaxWidth: 40,
        data: regular,
        itemStyle: {
          color: {
            type: 'linear', x: 0, y: 0, x2: 0, y2: 1,
            colorStops: [
              { offset: 0, color: c.greenGrad },
              { offset: 1, color: c.green + '55' },
            ],
          },
        },
        emphasis: { focus: 'series' },
      },
      {
        name: 'Irregulares',
        type: 'bar',
        stack: 'total',
        barMaxWidth: 40,
        data: irregular,
        itemStyle: {
          borderRadius: [4, 4, 0, 0],
          color: {
            type: 'linear', x: 0, y: 0, x2: 0, y2: 1,
            colorStops: [
              { offset: 0, color: c.redGrad },
              { offset: 1, color: c.red + '55' },
            ],
          },
        },
        emphasis: { focus: 'series' },
      },
    ],
  };
}

</script>

<template>
  <div class="tab-content evolucao-tab">
    <div v-if="evolucaoLoading && !cachedEvolucaoData" class="tab-placeholder">
      <i class="pi pi-spin pi-spinner placeholder-icon" />
      <p>Carregando dados...</p>
    </div>

    <div v-else-if="evolucaoError" class="tab-placeholder tab-placeholder--error">
      <i class="pi pi-exclamation-circle placeholder-icon" />
      <p>{{ evolucaoError }}</p>
    </div>

    <div v-else-if="evolucaoLoaded && !cachedEvolucaoData?.semestres?.length" class="tab-placeholder">
      <i class="pi pi-inbox placeholder-icon" />
      <p>Nenhum dado de movimentação encontrado para este CNPJ.</p>
    </div>

    <template v-else-if="cachedEvolucaoData">
      <div class="evolucao-card evolucao-card-highlight" :class="{ 'is-refreshing': isRefreshing }">
        <div class="evolucao-card-header">
          <i class="pi pi-chart-bar" /><span>Volume Financeiro por Semestre</span>
          <i v-if="isRefreshing" class="pi pi-spin pi-spinner refresh-spinner" />
        </div>
        <div class="evolucao-chart-wrap">
          <VChart ref="chartRef" :option="chartOption" :update-options="{ notMerge: true }" autoresize class="evolucao-chart" @click="onChartClick" />
        </div>
      </div>

      <div class="evolucao-card evolucao-card-highlight" :class="{ 'is-refreshing': isRefreshing }">
        <div class="evolucao-card-header">
          <i class="pi pi-table" /><span>Detalhamento Semestral</span>
        </div>
        <div class="evolucao-table-wrap">
          <DataTable 
            :value="cachedEvolucaoData.semestres" 
            v-model:expandedRows="expandedRows" 
            dataKey="semestre" 
            class="evolucao-table"
            @row-click="toggleRow"
          >

            <Column field="semestre" header="Semestre" style="width: 15%">
              <template #body="{ data }">
                <div class="sem-label">
                  <div style="display: flex; align-items: center; gap: 8px;">
                    <i class="pi" :class="expandedRows[data.semestre] ? 'pi-chevron-down' : 'pi-chevron-right'" style="font-size: 0.70rem; color: var(--text-muted); opacity: 0.8;"></i>
                    {{ data.semestre }}
                  </div>
                  <span v-if="formatMesRange(data.mes_inicio, data.mes_fim)" class="sem-months" style="margin-left: 20px;">
                    {{ formatMesRange(data.mes_inicio, data.mes_fim) }}
                  </span>
                </div>
              </template>
            </Column>

            <Column field="total" header="Total Movimentado" style="width: 18%">
              <template #body="{ data }">
                {{ formatCurrencyFull(data.total) }}
              </template>
            </Column>

            <Column field="regular" header="Total Regular" style="width: 18%">
              <template #body="{ data }">
                <span class="col-regular">{{ formatCurrencyFull(data.regular) }}</span>
              </template>
            </Column>

            <Column field="irregular" header="Sem Comprovação" style="width: 18%">
              <template #body="{ data }">
                <span class="col-irregular">{{ formatCurrencyFull(data.irregular) }}</span>
              </template>
            </Column>

            <Column field="pct_irregular" header="% S/ Comp" style="width: 18%">
              <template #body="{ data }">
                <div class="pct-cell" style="text-align: right; padding: 0;">
                  <div class="pct-bar-wrap">
                    <div
                      class="pct-bar"
                      :style="{
                        width: Math.min(data.pct_irregular, 100) + '%',
                        background: data.pct_irregular >= RISK_THRESHOLDS.CRITICAL ? 'var(--risk-critical)'
                                  : data.pct_irregular >= RISK_THRESHOLDS.HIGH     ? 'var(--risk-high)'
                                  : data.pct_irregular >= RISK_THRESHOLDS.MEDIUM   ? 'var(--risk-medium)'
                                  : 'var(--risk-low)'
                      }"
                    />
                  </div>
                  <span class="pct-value" :class="{
                    'pct-critical': data.pct_irregular >= RISK_THRESHOLDS.CRITICAL,
                    'pct-high':     data.pct_irregular >= RISK_THRESHOLDS.HIGH     && data.pct_irregular < RISK_THRESHOLDS.CRITICAL,
                    'pct-medium':   data.pct_irregular >= RISK_THRESHOLDS.MEDIUM   && data.pct_irregular < RISK_THRESHOLDS.HIGH,
                    'pct-low':      data.pct_irregular < RISK_THRESHOLDS.MEDIUM,
                  }">{{ data.pct_irregular.toFixed(1) }}%</span>
                </div>
              </template>
            </Column>

            <Column header="Tendência" style="width: 13%">
              <template #body="{ data, index }">
                <div class="trend-cell">
                  <template v-if="index === 0">
                    <span class="trend-neutral">—</span>
                  </template>
                  <template v-else>
                    <span
                      v-if="data.pct_irregular > cachedEvolucaoData.semestres[index-1].pct_irregular"
                      class="trend-up"
                      :title="`+${(data.pct_irregular - cachedEvolucaoData.semestres[index-1].pct_irregular).toFixed(1)}pp`"
                    >▲ {{ (data.pct_irregular - cachedEvolucaoData.semestres[index-1].pct_irregular).toFixed(1) }}pp</span>
                    <span
                      v-else-if="data.pct_irregular < cachedEvolucaoData.semestres[index-1].pct_irregular"
                      class="trend-down"
                      :title="`-${(cachedEvolucaoData.semestres[index-1].pct_irregular - data.pct_irregular).toFixed(1)}pp`"
                    >▼ {{ (cachedEvolucaoData.semestres[index-1].pct_irregular - data.pct_irregular).toFixed(1) }}pp</span>
                    <span v-else class="trend-neutral">= 0pp</span>
                  </template>
                </div>
              </template>
            </Column>

            <!-- Expanded content (Meses) -->
            <template #expansion="slotProps">
              <div class="meses-expansion-box p-3">
                <div class="mb-3" style="color: var(--text-secondary); font-size: 0.8rem; font-weight: 600; text-transform: uppercase;">
                  Detalhamento de {{ slotProps.data.semestre }}
                </div>

                <!-- Gráfico Mensal de Movimentação -->
                <div v-if="evolucaoMensalGtin?.meses?.length" class="mensal-gtin-chart-wrapper">
                  <div class="mensal-gtin-chart-header">
                    <i class="pi pi-chart-bar" />
                    <span>Histórico Mensal de Movimentação</span>
                    <i v-if="evolucaoMensalGtinLoading" class="pi pi-spin pi-spinner" style="margin-left:auto;font-size:0.75rem;opacity:0.5;" />
                  </div>
                  <VChart :option="chartOptionMensalGtin(slotProps.data.semestre)" :update-options="{ notMerge: true }" autoresize style="height: 210px;" />
                </div>

                <DataTable :value="slotProps.data.meses" class="sanfona-table">
                  <Column field="mes" header="Mês" style="width: 15%" headerStyle="text-align: left" bodyStyle="text-align: left">
                    <template #body="{ data }">
                      <span style="font-weight: 500;">{{ formatMonth(data.mes) }}</span>
                    </template>
                  </Column>
                  <Column field="total" header="Total Movimentado" style="width: 20%" headerStyle="text-align: right" bodyStyle="text-align: right">
                    <template #body="{ data }">{{ formatCurrencyFull(data.total) }}</template>
                  </Column>
                  <Column field="irregular" header="Sem Comprovação" style="width: 20%" headerStyle="text-align: right" bodyStyle="text-align: right">
                    <template #body="{ data }">
                      <a 
                        v-if="data.irregular > 0" 
                        @click.prevent="abrirInfratores(data.mes)" 
                        style="color: var(--risk-high); cursor: pointer; text-decoration: none; font-weight: 600; transition: opacity 0.2s;"
                        onmouseover="this.style.opacity=0.8; this.style.textDecoration='underline'"
                        onmouseout="this.style.opacity=1; this.style.textDecoration='none'"
                      >
                        {{ formatCurrencyFull(data.irregular) }} <i class="pi pi-search" style="font-size: 0.7rem; margin-left: 4px;"></i>
                      </a>
                      <span v-else>{{ formatCurrencyFull(data.irregular) }}</span>
                    </template>
                  </Column>
                  <Column field="pct_irregular" header="% SEM COMPROVAÇÃO" style="width: 45%" headerStyle="text-align: right" bodyStyle="text-align: right">
                    <template #body="{ data }">
                      <div style="display: flex; align-items: center; justify-content: flex-end; gap: 12px; width: 100%;">
                        <div style="flex: 1; max-width: 250px; height: 5px; background: color-mix(in srgb, var(--text-color) 8%, var(--tabs-border)); border-radius: 99px; overflow: hidden; display: flex;">
                          <div
                            :style="{
                              width: Math.min(data.pct_irregular, 100) + '%',
                              height: '100%',
                              background: data.pct_irregular >= RISK_THRESHOLDS.CRITICAL ? 'var(--risk-critical)'
                                        : data.pct_irregular >= RISK_THRESHOLDS.HIGH     ? 'var(--risk-high)'
                                        : data.pct_irregular >= RISK_THRESHOLDS.MEDIUM   ? 'var(--risk-medium)'
                                        : 'var(--risk-low)'
                            }"
                          ></div>
                        </div>
                        <span :class="{
                          'pct-critical': data.pct_irregular >= RISK_THRESHOLDS.CRITICAL,
                          'pct-high':     data.pct_irregular >= RISK_THRESHOLDS.HIGH     && data.pct_irregular < RISK_THRESHOLDS.CRITICAL,
                          'pct-medium':   data.pct_irregular >= RISK_THRESHOLDS.MEDIUM   && data.pct_irregular < RISK_THRESHOLDS.HIGH,
                          'pct-low':      data.pct_irregular < RISK_THRESHOLDS.MEDIUM,
                        }" style="font-weight: 600; font-size: 0.8rem; min-width: 42px; text-align: right;">
                          {{ data.pct_irregular.toFixed(1) }}%
                        </span>
                      </div>
                    </template>
                  </Column>
                </DataTable>
              </div>
            </template>

            <ColumnGroup type="footer">
              <Row>
                <Column footer="TOTAL" footerStyle="text-align: left; font-weight: 600;" />
                <Column :footer="formatCurrencyFull(cachedEvolucaoData.semestres.reduce((a, s) => a + s.total, 0))" />
                <Column :footer="formatCurrencyFull(cachedEvolucaoData.semestres.reduce((a, s) => a + s.regular, 0))" />
                <Column :footer="formatCurrencyFull(cachedEvolucaoData.semestres.reduce((a, s) => a + s.irregular, 0))" footerStyle="color: var(--risk-high)" />
                <Column :colspan="2" />
              </Row>
            </ColumnGroup>
          </DataTable>
        </div>
      </div>
    </template>
    <div v-else class="tab-placeholder">
      <i class="pi pi-chart-bar placeholder-icon" />
      <p>Clique na aba para carregar os dados.</p>
    </div>
  </div>
</template>

<style scoped>
/* COPIAR CSS DO PAI */
.evolucao-tab {
  display: flex;
  flex-direction: column;
  gap: 1.5rem;
}

.evolucao-card {
  background: transparent;
  border: none;
  border-radius: 0;
  overflow: visible;
  box-shadow: none;
  margin-bottom: 0;
}

.evolucao-card-highlight {
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  border-radius: 12px;
  overflow: hidden;
  box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.05), 0 2px 4px -1px rgba(0, 0, 0, 0.03);
  padding: 1.25rem;
  transition: transform 0.2s ease, box-shadow 0.2s ease, opacity 0.25s ease;
}

.evolucao-card-highlight:hover {
  box-shadow: 0 10px 15px -3px rgba(0, 0, 0, 0.08);
}

.evolucao-card-highlight.is-refreshing {
  opacity: 0.45;
  pointer-events: none;
}

.evolucao-card-header {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  padding-bottom: 0.75rem;
  border-bottom: 1px solid var(--tabs-border);
  margin-bottom: 1rem;
  font-size: 0.85rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: var(--text-color);
  opacity: 0.85;
}

.evolucao-card-header i { font-size: 1rem; color: var(--primary-color); }

.refresh-spinner {
  margin-left: auto;
  font-size: 0.8rem;
  opacity: 0.5;
}
.evolucao-chart-wrap { height: 350px; padding: 0.5rem 0 0 0; }
.evolucao-chart { width: 100%; height: 100%; }

.evolucao-table-wrap { overflow-x: auto; padding-top: 0.5rem; }

:deep(.p-datatable.evolucao-table) { font-size: 0.82rem; background: transparent; }
:deep(.p-datatable.evolucao-table .p-datatable-wrapper) { background: transparent; }

:deep(.p-datatable.evolucao-table .p-datatable-tbody > tr) {
  background: transparent;
  color: var(--text-color);
}

:deep(.p-datatable.evolucao-table .p-datatable-thead > tr > th) {
  text-align: right; 
  padding: 0.75rem 1rem; 
  background: transparent; 
  color: var(--text-secondary); 
  font-weight: 600; 
  font-size: 0.72rem; 
  text-transform: uppercase; 
  letter-spacing: 0.05em; 
  border-bottom: 2px solid var(--tabs-border); 
  opacity: 0.85;
}
:deep(.p-datatable.evolucao-table .p-datatable-tbody > tr > td) {
  text-align: right; 
  padding: 0.65rem 1rem; 
  color: var(--text-secondary); 
  border-bottom: 1px solid var(--tabs-border); 
  transition: background 0.2s ease;
  background: transparent;
}
:deep(.p-datatable.evolucao-table .p-datatable-tbody > tr:not(.p-datatable-row-expansion)) {
  cursor: pointer;
}
:deep(.p-datatable.evolucao-table .p-datatable-tbody > tr:not(.p-datatable-row-expansion):hover > td) {
  background: var(--table-hover);
}
/* Linha de expansão: sem hover, sem cursor, sem background diferente */
:deep(.p-datatable.evolucao-table .p-datatable-tbody > tr.p-datatable-row-expansion) {
  cursor: default;
}
:deep(.p-datatable.evolucao-table .p-datatable-tbody > tr.p-datatable-row-expansion > td) {
  background: var(--table-expansion-bg) !important;
  padding: 0 !important;
  border-bottom: 2px solid var(--tabs-border);
}
:deep(.p-datatable.evolucao-table .p-datatable-tfoot > tr > td) {
  text-align: right; 
  border-top: 2px solid var(--tabs-border) !important; 
  border-bottom: none !important; 
  background: color-mix(in srgb, var(--tabs-bg) 95%, var(--text-color) 5%); 
  font-weight: 600;
  color: var(--text-color);
  padding: 0.85rem 1rem;
}
:deep(.p-datatable.evolucao-table .p-datatable-thead > tr > th:nth-child(1)),
:deep(.p-datatable.evolucao-table .p-datatable-tbody > tr > td:nth-child(1)) { 
  text-align: left !important; 
}

/* Override explícito do flexbox das headers do PrimeVue */
:deep(.p-datatable.evolucao-table .p-datatable-thead > tr > th .p-column-header-content),
:deep(.sanfona-table.p-datatable .p-datatable-thead > tr > th .p-column-header-content) {
  justify-content: flex-end;
}
:deep(.p-datatable.evolucao-table .p-datatable-thead > tr > th:first-child .p-column-header-content),
:deep(.sanfona-table.p-datatable .p-datatable-thead > tr > th:first-child .p-column-header-content) {
  justify-content: flex-start;
}
:deep(.p-datatable.evolucao-table .p-datatable-thead > tr > th:last-child .p-column-header-content) {
  justify-content: center;
}
:deep(.sanfona-table.p-datatable .p-datatable-thead > tr > th:last-child .p-column-header-content) {
  justify-content: flex-end !important;
}

/* Fix text colors */
:deep(.p-datatable.evolucao-table .col-regular) { color: var(--risk-low); }
:deep(.p-datatable.evolucao-table .col-irregular) { color: var(--risk-high); }

/* expansion row */
:deep(.p-datatable-row-expansion > td) {
  padding: 0 !important;
  background: color-mix(in srgb, var(--card-bg) 95%, var(--text-color) 5%);
}

.meses-expansion-box {
  border-bottom: 1px solid var(--tabs-border);
  padding: 1.5rem 2.5rem;
}

:deep(.sanfona-table.p-datatable) { background: transparent; }
:deep(.sanfona-table.p-datatable .p-datatable-tbody > tr) { background: transparent; }
:deep(.sanfona-table.p-datatable .p-datatable-tbody > tr:hover > td) { background: transparent !important; }
:deep(.sanfona-table.p-datatable .p-datatable-thead > tr > th) {
  padding: 0.5rem 1rem;
  background: transparent;
  color: var(--text-muted);
  font-weight: 600;
  font-size: 0.72rem;
  text-transform: uppercase;
  border-bottom: 1px solid var(--sidebar-border);
  text-align: right !important;
}
:deep(.sanfona-table.p-datatable .p-datatable-tbody > tr > td) {
  padding: 0.5rem 1rem;
  font-size: 0.78rem;
  background: transparent;
  border-bottom: 1px dashed var(--sidebar-border);
  color: var(--text-secondary);
  text-align: right !important;
}
:deep(.sanfona-table.p-datatable .p-datatable-thead > tr > th:first-child),
:deep(.sanfona-table.p-datatable .p-datatable-tbody > tr > td:first-child) {
  text-align: left !important;
}

.sem-label {
  font-weight: 600;
  color: var(--text-secondary);
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.sem-months {
  font-size: 0.68rem;
  font-weight: 400;
  color: var(--text-muted);
  opacity: 0.7;
  letter-spacing: 0.01em;
}
.col-regular { color: var(--risk-low); }
.col-irregular { color: var(--risk-high); }

.pct-cell { text-align: right; padding: 0.4rem 1rem; }
.pct-bar-wrap { height: 4px; background: var(--tabs-border); border-radius: 99px; margin-bottom: 3px; overflow: hidden; }
.pct-bar { height: 100%; border-radius: 99px; transition: width 0.4s ease; }
.pct-value { font-weight: 600; font-size: 0.82rem; }

.pct-critical { color: var(--risk-critical); }
.pct-high     { color: var(--risk-high); }
.pct-medium   { color: var(--risk-medium); }
.pct-low      { color: var(--risk-low); }

.trend-cell { text-align: center; font-size: 0.75rem; font-weight: 600; white-space: nowrap; }
.trend-up      { color: var(--risk-high); }
.trend-down    { color: var(--risk-low); }
.trend-neutral { color: var(--text-muted); font-weight: 400; }

.tab-placeholder {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 4rem 2rem;
  gap: 1rem;
  color: var(--text-muted);
  text-align: center;
}
.placeholder-icon {
  font-size: 2.5rem;
  color: var(--sidebar-border);
  opacity: 0.7;
}

.mensal-gtin-chart-wrapper {
  margin-bottom: 1.25rem;
  border: 1px solid var(--tabs-border);
  border-radius: 8px;
  overflow: hidden;
  background: color-mix(in srgb, var(--card-bg) 98%, var(--text-color) 2%);
}

.mensal-gtin-chart-header {
  display: flex;
  align-items: center;
  gap: 0.6rem;
  padding: 0.6rem 1rem;
  border-bottom: 1px solid var(--tabs-border);
  font-size: 0.75rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: var(--text-secondary);
  opacity: 0.85;
}

.mensal-gtin-chart-header i { color: var(--primary-color); font-size: 0.9rem; }
</style>
