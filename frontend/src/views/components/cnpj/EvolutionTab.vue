<script setup>
import { computed, ref } from 'vue';
import { useRoute } from 'vue-router';
import { useCnpjDetailStore } from '@/stores/cnpjDetail';
import { storeToRefs } from 'pinia';
import { useFilterStore } from '@/stores/filters';
import { useFrozenData } from '@/composables/useFrozenData';
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
import Button from 'primevue/button';
import Dialog from 'primevue/dialog';

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
const isMonthlyChartExpanded = ref(false);
const hoveredSemestre = ref(null);

const expandedRows = ref([]);
const selectedSemestre = ref(null);

// Todos os meses de todos os semestres (exibição global no card permanente)
const todosMeses = computed(() => {
  const semestres = cachedEvolucaoData.value?.semestres ?? [];
  return semestres.flatMap(sem =>
    (sem.meses ?? []).map(m => ({ ...m, semestre: sem.semestre }))
  );
});

// Verifica se um mês pertence ao semestre selecionado (ou se nada está selecionado)
const isMesSelecionado = (semestre) => !selectedSemestre.value || semestre === selectedSemestre.value?.semestre;

function limparFiltro() {
  selectedSemestre.value = null;
  expandedRows.value = [];
}

/**
 * Alterna a expansão da linha ao clicar em qualquer célula da linha pai.
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
  selectedSemestre.value = selectedSemestre.value?.semestre === semestre ? null : rowData;
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

// Ao clicar em uma barra do gráfico mensal, seleciona o semestre correspondente
function onMensalChartClick(params) {
  if (!params?.name) return;
  const mesStr = params.name; // "YYYY-MM"
  const semestres = cachedEvolucaoData.value?.semestres ?? [];
  const sem = semestres.find(s => mesPertenceAoSemestre(mesStr, s.semestre));
  if (sem) selectedSemestre.value = sem;
}

// Hover sync: quando passa o mouse em um semestre no gráfico de cima
function onChartMouseOver(params) {
  if (params.componentType === 'series' && params.name) {
    hoveredSemestre.value = params.name;
  }
}
function onChartMouseOut() {
  hoveredSemestre.value = null;
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
  const regular   = semestres.map(s => ({
    value: s.regular,
    itemStyle: { opacity: isMesSelecionado(s.semestre) ? 1 : 0.35 },
    emphasis: { itemStyle: { opacity: isMesSelecionado(s.semestre) ? 1 : 0.35 } },
  }));
  const irregular = semestres.map(s => ({
    value: s.irregular,
    itemStyle: { opacity: isMesSelecionado(s.semestre) ? 1 : 0.35 },
    emphasis: { itemStyle: { opacity: isMesSelecionado(s.semestre) ? 1 : 0.35 } },
  }));

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
        emphasis: { disabled: false },
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
        emphasis: { disabled: false },
      },
    ],
  };
});


// ── Gráfico Mensal GTIN ───────────────────────────────────

/** Formata "YYYY-MM" para label compacto de eixo X, ex: "jan/24". */
function formatMesLabel(iso) {
  if (!iso) return '';
  const [y, mo] = iso.split('-');
  return new Date(parseInt(y), parseInt(mo) - 1)
    .toLocaleDateString('pt-BR', { month: 'short', year: '2-digit' })
    .replace(' de ', '/');
}

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

const mensalChartOption = computed(() => chartOptionMensalGtin(selectedSemestre.value?.semestre));

function chartOptionMensalGtin(semestre, showZoom = false) {
  const c     = C.value;
  const meses = todosMeses.value; // Usa todos os meses de todos os semestres

  const labels    = meses.map(m => m.mes);
  const regular   = meses.map(m => ({
    value: Math.max(0, parseFloat((m.total - m.irregular).toFixed(2))),
    itemStyle: { 
      opacity: hoveredSemestre.value 
        ? (m.semestre === hoveredSemestre.value ? 1 : 0.25) 
        : (isMesSelecionado(m.semestre) ? 1 : 0.25) 
    },
  }));
  const irregular = meses.map(m => ({
    value: parseFloat(m.irregular.toFixed(2)),
    itemStyle: { 
      opacity: hoveredSemestre.value 
        ? (m.semestre === hoveredSemestre.value ? 1 : 0.25) 
        : (isMesSelecionado(m.semestre) ? 1 : 0.25) 
    },
  }));

  // O usuário quer que SEMPRE mostre todos os meses, sem zoom automático.
  let zoomStart = 0;
  let zoomEnd   = 100;

  return {
    backgroundColor: 'transparent',
    animation: !hoveredSemestre.value,
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
        const totalVal = m.total;
        const irrVal   = m.irregular;
        const regVal   = totalVal - irrVal;
        return `
          <div style="color:${c.tooltipText}">
            <div style="font-weight:600;font-size:13px;margin-bottom:8px;">${formatMesLabel(m.mes)} <span style="opacity: 0.5; font-size: 11px;">(${m.semestre})</span></div>
            <div style="display:flex;flex-direction:column;gap:5px;">
              <div style="display:flex;align-items:center;gap:8px;">
                <span style="width:9px;height:9px;border-radius:2px;background:${c.green};display:inline-block;"></span>
                <span style="font-size:10px;opacity:.6;text-transform:uppercase;letter-spacing:.04em;">Regulares</span>
              </div>
              <div style="font-weight:600;font-size:12px;margin-bottom:2px;">${formatCurrencyFull(regVal)}</div>
              <div style="display:flex;align-items:center;gap:8px;">
                <span style="width:9px;height:9px;border-radius:2px;background:${c.red};display:inline-block;"></span>
                <span style="font-size:10px;opacity:.6;text-transform:uppercase;letter-spacing:.04em;">Irregulares</span>
              </div>
              <div style="font-weight:600;font-size:12px;color:${c.red};margin-bottom:2px;">${formatCurrencyFull(irrVal)} <span style="opacity:.7">(${m.pct_irregular.toFixed(1)}%)</span></div>
              <div style="border-top:1px solid ${c.tooltipBorder};padding-top:5px;margin-top:2px;font-weight:600;font-size:12px;">Total: ${formatCurrencyFull(totalVal)}</div>
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
        formatter: formatMesLabel,
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

    dataZoom: showZoom ? [
      { type: 'inside', start: zoomStart, end: zoomEnd, zoomLock: false },
      {
        type: 'slider', start: zoomStart, end: zoomEnd, height: 14,
        bottom: 4,
        borderColor: c.grid,
        fillerColor: c.axisShadow,
        handleStyle: { color: c.muted },
        textStyle: { color: 'transparent' },
      },
    ] : [],

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
          <div class="header-title">
            <i class="pi pi-chart-bar" />
            <span>Volume Financeiro por Semestre</span>
          </div>
          <div class="header-actions">
            <Button 
              v-if="selectedSemestre" 
              icon="pi pi-filter-slash" 
              label="Limpar Filtro" 
              class="p-button-text p-button-sm btn-clear-filter"
              @click="limparFiltro" 
            />
            <i v-if="isRefreshing" class="pi pi-spin pi-spinner refresh-spinner" />
          </div>
        </div>
        <div class="evolucao-chart-wrap">
          <VChart 
            ref="chartRef" 
            :option="chartOption" 
            :update-options="{ notMerge: true }" 
            autoresize 
            class="evolucao-chart" 
            @click="onChartClick" 
            @mouseover="onChartMouseOver"
            @mouseout="onChartMouseOut"
          />
        </div>
      </div>

      <!-- Card permanente: Histórico Mensal de Movimentação -->
      <div class="evolucao-card evolucao-card-highlight" :class="{ 'is-refreshing': isRefreshing }">
        <div class="evolucao-card-header">
          <div class="header-title">
            <i class="pi pi-chart-bar" />
            <span>Histórico Mensal de Movimentação</span>
          </div>
          <div class="header-actions">
            <span v-if="selectedSemestre" class="sem-badge">
              <i class="pi pi-star-fill" />
              {{ selectedSemestre.semestre }}
            </span>
            <Button 
              v-if="cachedEvolucaoData"
              icon="pi pi-external-link" 
              label="AMPLIAR" 
              class="p-button-outlined p-button-xs btn-zoom"
              @click="isMonthlyChartExpanded = true" 
            />
            <i v-if="evolucaoMensalGtinLoading" class="pi pi-spin pi-spinner refresh-spinner" />
          </div>
        </div>
        <div v-if="todosMeses.length" class="evolucao-chart-wrap">
          <VChart
            :option="mensalChartOption"
            :update-options="{ notMerge: true }"
            autoresize
            class="evolucao-chart"
            @click="onMensalChartClick"
          />
        </div>
        <div v-else class="tab-placeholder" style="padding: 2rem;">
          <i class="pi pi-spin pi-spinner placeholder-icon" style="font-size: 1.5rem; opacity: 0.4;" />
          <p style="font-size: 0.8rem;">Carregando dados mensais...</p>
        </div>
      </div>

      <!-- Painel contextual: detalhe do semestre selecionado -->
      <Transition name="context-slide">
        <div v-if="selectedSemestre" class="evolucao-card evolucao-card-highlight context-detail-card">
          <div class="evolucao-card-header">
            <div class="header-title">
              <i class="pi pi-calendar-clock" />
              <span>{{ selectedSemestre.semestre }} — Detalhamento Mensal</span>
            </div>
            <div class="header-actions">
              <button class="btn-close-context" @click="limparFiltro" title="Fechar">
                <i class="pi pi-times" />
              </button>
            </div>
          </div>
          <DataTable :value="selectedSemestre.meses ?? []" class="sanfona-table" :show-gridlines="false">
            <Column field="mes" header="Mês" style="width: 20%">
              <template #body="{ data: m }">{{ formatMonth(m.mes) }}</template>
            </Column>
            <Column field="total" header="Total Movimentado" style="width: 20%">
              <template #body="{ data: m }">{{ formatCurrencyFull(m.total) }}</template>
            </Column>
            <Column field="regular" header="Total Regular" style="width: 20%">
              <template #body="{ data: m }">
                {{ formatCurrencyFull(m.total - m.irregular) }}
              </template>
            </Column>
            <Column field="irregular" header="Sem Comprovação" style="width: 20%">
              <template #body="{ data: m }">
                <span class="col-irregular">{{ formatCurrencyFull(m.irregular) }}</span>
              </template>
            </Column>
            <Column field="pct_irregular" header="% S/ Comp" style="width: 20%">
              <template #body="{ data: m }">
                <span :class="{
                  'pct-critical': m.pct_irregular >= RISK_THRESHOLDS.CRITICAL,
                  'pct-high':     m.pct_irregular >= RISK_THRESHOLDS.HIGH     && m.pct_irregular < RISK_THRESHOLDS.CRITICAL,
                  'pct-medium':   m.pct_irregular >= RISK_THRESHOLDS.MEDIUM   && m.pct_irregular < RISK_THRESHOLDS.HIGH,
                  'pct-low':      m.pct_irregular < RISK_THRESHOLDS.MEDIUM,
                }">{{ m.pct_irregular.toFixed(1) }}%</span>
              </template>
            </Column>
          </DataTable>
        </div>
      </Transition>

      <div class="evolucao-card evolucao-card-highlight" :class="{ 'is-refreshing': isRefreshing }">
        <div class="evolucao-card-header">
          <div class="header-title">
            <i class="pi pi-table" />
            <span>Detalhamento Semestral</span>
          </div>
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
                {{ formatCurrencyFull(data.regular) }}
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

            <template #expansion="{ data: sem }">
              <div class="meses-expansion-box">
                <DataTable :value="sem.meses ?? []" class="sanfona-table" :show-gridlines="false">
                  <Column field="mes" header="Mês" style="width: 20%">
                    <template #body="{ data: m }">{{ formatMonth(m.mes) }}</template>
                  </Column>
                  <Column field="total" header="Total Movimentado" style="width: 20%">
                    <template #body="{ data: m }">{{ formatCurrencyFull(m.total) }}</template>
                  </Column>
                  <Column field="regular" header="Total Regular" style="width: 20%">
                    <template #body="{ data: m }">
                      {{ formatCurrencyFull(m.total - m.irregular) }}
                    </template>
                  </Column>
                  <Column field="irregular" header="Sem Comprovação" style="width: 20%">
                    <template #body="{ data: m }">
                      <span class="col-irregular">{{ formatCurrencyFull(m.irregular) }}</span>
                    </template>
                  </Column>
                  <Column field="pct_irregular" header="% S/ Comp" style="width: 20%">
                    <template #body="{ data: m }">
                      <span :class="{
                        'pct-critical': m.pct_irregular >= RISK_THRESHOLDS.CRITICAL,
                        'pct-high':     m.pct_irregular >= RISK_THRESHOLDS.HIGH     && m.pct_irregular < RISK_THRESHOLDS.CRITICAL,
                        'pct-medium':   m.pct_irregular >= RISK_THRESHOLDS.MEDIUM   && m.pct_irregular < RISK_THRESHOLDS.HIGH,
                        'pct-low':      m.pct_irregular < RISK_THRESHOLDS.MEDIUM,
                      }">{{ m.pct_irregular.toFixed(1) }}%</span>
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

      <!-- Modal de Zoom do Histórico Mensal -->
      <Dialog 
        v-model:visible="isMonthlyChartExpanded" 
        modal 
        header="Histórico Mensal de Movimentação (Detalhamento)" 
        :style="{ width: '90vw', maxWidth: '1400px' }"
        :breakpoints="{ '960px': '95vw' }"
        class="evolucao-zoom-dialog"
      >
        <div style="height: 65vh; min-height: 450px; padding: 1rem 0;">
          <VChart
            v-if="isMonthlyChartExpanded"
            :option="chartOptionMensalGtin(selectedSemestre?.semestre, true)"
            :update-options="{ notMerge: true }"
            autoresize
            style="width: 100%; height: 100%;"
          />
        </div>
        <template #footer>
          <div style="display: flex; align-items: center; justify-content: space-between; width: 100%; padding-top: 0.5rem;">
            <div style="font-size: 0.75rem; color: var(--text-muted);">
              <i class="pi pi-info-circle" style="margin-right: 6px; font-size: 0.8rem;" />
              Utilize o mouse ou o slider inferior para navegar pelo histórico.
            </div>
            <Button label="Fechar" icon="pi pi-times" class="p-button-outlined p-button-sm" @click="isMonthlyChartExpanded = false" />
          </div>
        </template>
      </Dialog>
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
  justify-content: space-between;
  gap: 0.75rem;
  padding-bottom: 0.75rem;
  border-bottom: 1px solid var(--tabs-border);
  margin-bottom: 1rem;
}

.header-title {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  font-size: 0.85rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: var(--text-color);
  opacity: 0.85;
}

.header-actions {
  display: flex;
  align-items: center;
  gap: 0.6rem;
}

.evolucao-card-header i { font-size: 1rem; color: var(--primary-color); }

.refresh-spinner {
  margin-left: auto;
  font-size: 0.8rem;
  opacity: 0.5;
}

.btn-clear-filter {
  margin-left: auto;
  margin-right: 1rem;
  font-size: 0.72rem !important;
  font-weight: 600 !important;
  color: var(--primary-color) !important;
  padding: 0.2rem 0.6rem !important;
  border-radius: 6px;
  background: color-mix(in srgb, var(--primary-color) 8%, transparent) !important;
  transition: all 0.2s ease !important;
}
.btn-clear-filter:hover {
  background: color-mix(in srgb, var(--primary-color) 15%, transparent) !important;
  transform: translateY(-1px);
}
.btn-zoom {
  font-size: 0.7rem !important;
  font-weight: 700 !important;
  color: var(--primary-color) !important;
  padding: 0.25rem 0.75rem !important;
  border-radius: 6px;
  border: 1px solid color-mix(in srgb, var(--primary-color) 30%, transparent) !important;
  background: color-mix(in srgb, var(--primary-color) 8%, transparent) !important;
  transition: all 0.2s ease !important;
  white-space: nowrap;
  height: auto !important;
  line-height: 1 !important;
}
.btn-zoom:hover {
  background: color-mix(in srgb, var(--primary-color) 15%, transparent) !important;
  transform: translateY(-1px);
}
.evolucao-chart-wrap { 
  height: 25vh; 
  min-height: 200px; 
  padding: 0.5rem 0 0 0; 
}
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
  background: color-mix(in srgb, var(--primary-color) 4%, var(--card-bg)) !important;
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
  border-left: 3px solid var(--primary-color);
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

.sem-badge {
  font-size: 0.7rem;
  font-weight: 700;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  padding: 2px 10px;
  border-radius: 99px;
  background: color-mix(in srgb, var(--primary-color) 15%, transparent);
  color: var(--primary-color);
  border: 1px solid color-mix(in srgb, var(--primary-color) 30%, transparent);
  display: flex;
  align-items: center;
  gap: 4px;
}
.sem-badge i { font-size: 0.6rem !important; }

/* Label de semestre clicável dentro da tabela mensal */
.mes-sem-label {
  display: inline-block;
  font-size: 0.72rem;
  font-weight: 600;
  letter-spacing: 0.04em;
  padding: 2px 8px;
  border-radius: 99px;
  cursor: pointer;
  color: var(--text-muted);
  border: 1px solid transparent;
  transition: all 0.2s ease;
  opacity: 0.55;
}
.mes-sem-label:hover {
  background: color-mix(in srgb, var(--primary-color) 10%, transparent);
  color: var(--primary-color);
  opacity: 1;
}
.mes-sem-selected {
  background: color-mix(in srgb, var(--primary-color) 15%, transparent);
  color: var(--primary-color) !important;
  border-color: color-mix(in srgb, var(--primary-color) 30%, transparent);
  opacity: 1 !important;
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

/* ── Painel contextual de detalhe mensal ─────────────────────────────── */
.context-detail-card {
  border-left: 3px solid var(--primary-color);
  background: color-mix(in srgb, var(--primary-color) 4%, var(--card-bg));
}

.btn-close-context {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 26px;
  height: 26px;
  border: none;
  border-radius: 6px;
  background: color-mix(in srgb, var(--text-color) 8%, transparent);
  color: var(--text-muted);
  cursor: pointer;
  transition: all 0.15s ease;
}
.btn-close-context:hover {
  background: color-mix(in srgb, var(--color-error) 12%, transparent);
  color: var(--color-error);
}
.btn-close-context i { font-size: 0.7rem; }

/* ── Transição slide-down ────────────────────────────────────────────── */
.context-slide-enter-active,
.context-slide-leave-active {
  transition: opacity 0.25s ease, transform 0.25s ease;
}
.context-slide-enter-from,
.context-slide-leave-to {
  opacity: 0;
  transform: translateY(-10px);
}

.evolucao-zoom-dialog :deep(.p-dialog-header) {
  border-bottom: 1px solid var(--tabs-border);
  padding: 1.25rem 1.5rem;
  background: var(--card-bg);
}
.evolucao-zoom-dialog :deep(.p-dialog-content) {
  background: var(--card-bg);
}
.evolucao-zoom-dialog :deep(.p-dialog-footer) {
  border-top: 1px solid var(--tabs-border);
  padding: 1rem 1.5rem;
  background: var(--card-bg);
}
</style>
