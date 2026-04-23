<script setup>
import { computed, ref, watch } from "vue";
import { storeToRefs } from 'pinia';
import { useCnpjDetailStore } from '@/stores/cnpjDetail';
import { useThemeStore } from '@/stores/theme';
import { useDelayedLoading } from '@/composables/useDelayedLoading';
import { useFormatting } from "@/composables/useFormatting";
import { useChartTheme } from '@/config/chartTheme';
import { API_ENDPOINTS } from '@/config/api';

import VChart from 'vue-echarts';
import { use } from 'echarts/core';
import { BarChart, LineChart } from 'echarts/charts';
import { GridComponent, TooltipComponent, DataZoomComponent, MarkLineComponent, LegendComponent } from 'echarts/components';
import { CanvasRenderer } from 'echarts/renderers';

use([BarChart, LineChart, GridComponent, TooltipComponent, DataZoomComponent, MarkLineComponent, LegendComponent, CanvasRenderer]);

const props = defineProps({
  cnpj: { type: String, required: true },
});

const cnpjDetailStore = useCnpjDetailStore();
const { crmDailyProfile, crmDailyProfileLoading, crmHourlyProfile, crmHourlyProfileLoading } = storeToRefs(cnpjDetailStore);
const { formatarData } = useFormatting();
const { chartTheme, chartUFAccents } = useChartTheme();
const themeStore = useThemeStore();
const raioxBg = computed(() => themeStore.isDark ? 'rgba(0,0,0,0.15)' : 'rgba(255,255,255,0.6)');

// ── Flicker-Free Cache ────────────────────────────────────────────────────
const cachedCrmDailyProfile  = ref(crmDailyProfile.value);
const cachedCrmHourlyProfile = ref(crmHourlyProfile.value);

const showRefreshingDaily  = useDelayedLoading(crmDailyProfileLoading);
const showRefreshingHourly = useDelayedLoading(crmHourlyProfileLoading);

watch([crmDailyProfile, crmDailyProfileLoading], ([newData, loading]) => {
  if (newData && !loading) cachedCrmDailyProfile.value = newData;
}, { immediate: true });

watch([crmHourlyProfile, crmHourlyProfileLoading], ([newData, loading]) => {
  if (newData && !loading) cachedCrmHourlyProfile.value = newData;
}, { immediate: true });

// ── Filtro e Zoom do Gráfico Diário ───────────────────────────────────────
const filterDailyOnlyAnomalous = ref(false);
const dailyZoomStart = ref(0);
const dailyZoomEnd = ref(100);

const filteredDailyDays = computed(() => {
  const days = cachedCrmDailyProfile.value?.days ?? [];
  if (!filterDailyOnlyAnomalous.value) return days;
  return days.filter(d => d.is_anomalo === 1);
});

const dailyDates     = computed(() => filteredDailyDays.value.map(d => d.dt_janela));
const dailyValues    = computed(() => filteredDailyDays.value.map(d => d.nu_prescricoes_dia));
const dailyAnomalous = computed(() => filteredDailyDays.value.map(d => d.is_anomalo === 1));
const dailyMedians   = computed(() => filteredDailyDays.value.map(d => d.mediana_diaria ?? 0));

watch(dailyDates, (newDates) => {
  if (newDates.length > 0) {
    const totalDays = newDates.length;
    const windowSize = Math.min(totalDays, 150);
    dailyZoomStart.value = Math.max(0, 100 - (windowSize / totalDays) * 100);
    dailyZoomEnd.value = 100;
  }
}, { immediate: true });

function onDailyZoom(params) {
  if (params.batch) {
    dailyZoomStart.value = params.batch[0].start;
    dailyZoomEnd.value = params.batch[0].end;
  } else {
    dailyZoomStart.value = params.start;
    dailyZoomEnd.value = params.end;
  }
}

// ── Drill-down Horário ────────────────────────────────────────────────────
const selectedDay = ref(null);
const selectedHourlyHour = ref(null);
const hourlyTransactions = ref([]);
const hourlyTransactionsLoading = ref(false);
const expandedRaioxRows = ref(new Set());

const groupedRaiox = computed(() => {
  const groups = {};
  hourlyTransactions.value.forEach(item => {
    const key = item.num_autorizacao;
    if (!groups[key]) {
      groups[key] = { num_autorizacao: key, data_hora: item.data_hora, crm: item.crm, crm_uf: item.crm_uf, nu_medicamentos: 0, vl_autorizacao: 0, items: [] };
    }
    groups[key].nu_medicamentos += 1;
    groups[key].vl_autorizacao += (item.valor_pago || 0);
    groups[key].items.push(item);
  });
  return Object.values(groups).sort((a, b) => a.data_hora.localeCompare(b.data_hora));
});

const crmFrequencies = computed(() => {
  const freqs = {};
  groupedRaiox.value.forEach(tx => { freqs[tx.crm] = (freqs[tx.crm] || 0) + 1; });
  return freqs;
});

function getCRMColor(crm) {
  if (!crm) return 'var(--primary-color)';
  let hash = 0;
  for (let i = 0; i < crm.length; i++) { hash = crm.charCodeAt(i) + ((hash << 5) - hash); }
  const h = Math.abs(hash % 360);
  const lightness = themeStore.isDark ? 65 : 35;
  return `hsl(${h}, 75%, ${lightness}%)`;
}

function toggleRaioxRow(auth) {
  if (expandedRaioxRows.value.has(auth)) { expandedRaioxRows.value.delete(auth); }
  else { expandedRaioxRows.value.add(auth); }
  expandedRaioxRows.value = new Set(expandedRaioxRows.value);
}

async function loadTransactions(dt_janela, hourInt = null) {
  hourlyTransactionsLoading.value = true;
  try {
    const url = API_ENDPOINTS.analyticsCrmHourlyTransactions(props.cnpj, dt_janela, hourInt);
    const res = await fetch(url);
    if (!res.ok) throw new Error('Falha HTTP');
    const data = await res.json();
    hourlyTransactions.value = data.transactions || [];
  } catch (err) {
    console.error("Erro ao buscar Raio-X Sub-horário:", err);
  } finally {
    hourlyTransactionsLoading.value = false;
  }
}

async function onChartClick(params) {
  const day = filteredDailyDays.value?.[params.dataIndex];
  if (!day || !day.is_anomalo) {
    selectedDay.value = null;
    selectedHourlyHour.value = null;
    return;
  }
  selectedDay.value = day;
  selectedHourlyHour.value = 'all';
  await loadTransactions(day.dt_janela, null);
}

async function onHourlyChartClick(params) {
  const hourStr = params.name.replace('h', '');
  const hourInt = parseInt(hourStr, 10);
  if (!selectedDay.value || isNaN(hourInt)) return;
  if (!params.data || params.data.value === 0 || params.data.is_anomalo_hora !== 1) return;
  if (selectedHourlyHour.value === hourInt) {
    selectedHourlyHour.value = 'all';
    await loadTransactions(selectedDay.value.dt_janela, null);
    return;
  }
  selectedHourlyHour.value = hourInt;
  await loadTransactions(selectedDay.value.dt_janela, hourInt);
}

function truncate(str, n) {
  if (!str) return '';
  return str.length > n ? str.substring(0, n - 1) + '...' : str;
}

// ── Chart Options ─────────────────────────────────────────────────────────
const chartOptionDaily = computed(() => {
  const totalDays = dailyDates.value.length;
  const startZoom = dailyZoomStart.value;
  const endZoom = dailyZoomEnd.value;
  const minSpan = totalDays > 40 ? (40 / totalDays) * 100 : null;
  const maxSpan = totalDays > 150 ? (150 / totalDays) * 100 : null;

  return {
    ...chartTheme.value,
    animation: true,
    animationDuration: 300,
    legend: { show: false },
    grid: { top: 16, right: 20, bottom: 80, left: 50, containLabel: false },
    xAxis: {
      type: 'category',
      data: dailyDates.value,
      axisLabel: {
        formatter: (v) => v.slice(0, 7),
        interval: Math.floor(dailyDates.value.length / 24),
        fontSize: 11,
      },
      axisLine: { lineStyle: { color: chartTheme.value.border } },
    },
    yAxis: {
      type: 'value',
      minInterval: 1,
      axisLabel: { fontSize: 11 },
      splitLine: { lineStyle: { color: chartTheme.value.grid } },
    },
    tooltip: {
      trigger: 'item',
      backgroundColor: chartTheme.value.tooltip,
      borderColor: chartTheme.value.tooltipBorder,
      borderWidth: 1,
      padding: [12, 16],
      confine: true,
      textStyle: { color: chartTheme.value.tooltipText, fontFamily: 'Inter, sans-serif', fontSize: 12 },
      shadowBlur: 10,
      shadowColor: 'rgba(0,0,0,0.15)',
      formatter: (p) => {
        const day = filteredDailyDays.value?.[p.dataIndex];
        if (!day) return '';
        const c = chartTheme.value;
        const points = cachedCrmHourlyProfile.value?.points.filter(pt => pt.dt_janela === day.dt_janela) || [];
        let sparklineHtml = '';
        if (points.length > 0) {
          const maxVal = Math.max(...points.map(pt => pt.nu_prescricoes), 1);
          const bars = Array.from({ length: 24 }, (_, h) => {
            const pt = points.find(x => x.hr_janela === h);
            const hPerc = pt ? (pt.nu_prescricoes / maxVal) * 100 : 0;
            const isPico = pt && pt.hr_janela === day.hr_pico;
            const color = isPico ? '#ef4444' : c.muted;
            const opacity = hPerc > 0 ? 1 : 0.3;
            return `<div style="flex:1; height:${Math.max(hPerc, 2)}%; background:${color}; border-radius:1px; opacity:${opacity};"></div>`;
          }).join('');
          sparklineHtml = `
            <div style="margin-top:10px; border-top:1px solid ${c.tooltipBorder}; padding-top:10px;">
              <div style="font-size:10px; opacity:.6; letter-spacing:.04em; text-transform:uppercase; margin-bottom:6px; text-align:center;">Distribuição Horária</div>
              <div style="display:flex; align-items:flex-end; gap:2px; height:40px;">${bars}</div>
            </div>`;
        }
        const flagAnomalo = day.is_anomalo
          ? `<span style="font-size:10px; background:rgba(239, 68, 68, 0.15); color:#ef4444; padding:2px 8px; border-radius:4px; font-weight:800; border:1px solid rgba(239, 68, 68, 0.3); margin-left:8px;">⚠ ANOMALIA</span>`
          : '';
        return `
          <div style="color: ${c.tooltipText}; min-width: 200px;">
            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:10px;">
              <span style="font-weight:700; font-size:14px;">${formatarData(day.dt_janela)}</span>
              ${flagAnomalo}
            </div>
            <div style="display:flex; flex-direction:column; gap:8px;">
              <div style="display:flex; justify-content:space-between; align-items:center;">
                <span style="font-size:11px; opacity:.6; text-transform:uppercase;">Volume Total</span>
                <span style="font-weight:700; font-size:13px;">${day.nu_prescricoes_dia} <small>autorizações</small></span>
              </div>
              <div style="display:flex; justify-content:space-between; align-items:center;">
                <span style="font-size:11px; opacity:.6; text-transform:uppercase;">Médicos Distintos</span>
                <span style="font-weight:700; font-size:13px;">${day.nu_crms_distintos}</span>
              </div>
              <div style="display:flex; justify-content:space-between; align-items:center;">
                <span style="font-size:11px; opacity:.6; text-transform:uppercase;">Horário de Pico</span>
                <span style="font-weight:700; font-size:13px;">${String(day.hr_pico).padStart(2,'0')}h <small style="color:${day.is_anomalo ? '#ef4444' : c.muted}">(${day.nu_prescricoes_hr_pico})</small></span>
              </div>
            </div>
            ${sparklineHtml}
            <div style="margin-top:10px; font-size:10px; color:#6366f1; text-align:center; opacity:.8; font-style:italic;">Clique para drill-down detalhado</div>
          </div>`;
      },
    },
    dataZoom: [
      { type: 'inside', start: startZoom, end: endZoom, minSpan, maxSpan },
      { type: 'slider', start: startZoom, end: endZoom, height: 20, bottom: 8, handleSize: 14, minSpan, maxSpan },
    ],
    series: [
      {
        name: 'Prescrições',
        type: 'bar',
        barMaxWidth: 40,
        data: dailyValues.value.map((v, i) => {
          const day = filteredDailyDays.value[i];
          const isSelected = selectedDay.value && selectedDay.value.dt_janela === day.dt_janela;
          const hasSelection = !!selectedDay.value;
          return {
            value: v,
            itemStyle: {
              opacity: hasSelection && !isSelected ? 0.5 : 1,
              color: dailyAnomalous.value[i]
                ? { type: 'linear', x: 0, y: 0, x2: 0, y2: 1, colorStops: [{ offset: 0, color: '#ef4444' }, { offset: 1, color: '#ef444440' }] }
                : { type: 'linear', x: 0, y: 0, x2: 0, y2: 1, colorStops: [{ offset: 0, color: chartUFAccents.value.bar1 }, { offset: 1, color: chartUFAccents.value.bar1 + '55' }] },
            },
          };
        }),
      },
      {
        name: 'Mediana Referência (Dia)',
        type: 'line',
        step: 'end',
        symbol: 'none',
        data: dailyMedians.value,
        lineStyle: { color: '#f59e0b', type: 'dashed', width: 1.5, opacity: 0.8 },
        z: 10,
      },
    ],
  };
});

const chartOptionHourly = computed(() => {
  if (!selectedDay.value || !cachedCrmHourlyProfile.value) return {};
  const c = chartTheme.value;
  const targetDate = selectedDay.value.dt_janela;
  const pointsForDay = cachedCrmHourlyProfile.value.points.filter(p => p.dt_janela === targetDate);

  const fullPoints = Array.from({ length: 24 }, (_, h) => {
    const found = pointsForDay.find(p => p.hr_janela === h);
    return found || { hr_janela: h, nu_prescricoes: 0, nu_crms_diferentes: 0, mediana_hora: 0, is_anomalo_hora: 0 };
  });

  const barColors = fullPoints.map(p => {
    if (p.is_anomalo_hora === 1 && p.nu_prescricoes > 0) {
      return { type: 'linear', x: 0, y: 0, x2: 0, y2: 1, colorStops: [{ offset: 0, color: '#ef4444' }, { offset: 1, color: 'rgba(239, 68, 68, 0.4)' }] };
    }
    return { type: 'linear', x: 0, y: 0, x2: 0, y2: 1, colorStops: [{ offset: 0, color: 'rgba(99, 102, 241, 0.65)' }, { offset: 1, color: 'rgba(99, 102, 241, 0.15)' }] };
  });

  return {
    backgroundColor: c.bg,
    animation: true,
    animationDuration: 600,
    animationEasing: 'cubicOut',
    textStyle: { fontFamily: 'Inter, sans-serif' },
    legend: { show: false },
    grid: { top: 16, left: 54, right: 20, bottom: 42, containLabel: false },
    xAxis: {
      type: 'category',
      data: fullPoints.map(p => `${String(p.hr_janela).padStart(2, '0')}h`),
      axisLine: { lineStyle: { color: c.grid } },
      axisTick: { show: false },
      axisLabel: { color: c.muted, fontSize: 10, fontWeight: 600, fontFamily: 'Inter, sans-serif', interval: 1, formatter: (v, i) => (i % 2 === 0 ? v : '') },
    },
    yAxis: [{ type: 'value', minInterval: 1, axisLine: { show: false }, axisTick: { show: false }, splitLine: { lineStyle: { color: c.grid, type: 'dashed' } }, axisLabel: { color: c.muted, fontSize: 10, fontFamily: 'Inter, sans-serif' } }],
    tooltip: {
      trigger: 'axis',
      backgroundColor: c.tooltip,
      borderColor: c.tooltipBorder,
      borderWidth: 1,
      padding: [12, 16],
      confine: true,
      textStyle: { color: c.tooltipText, fontFamily: 'Inter, sans-serif', fontSize: 12 },
      shadowBlur: 10,
      shadowColor: 'rgba(0,0,0,0.15)',
      axisPointer: { type: 'shadow', shadowStyle: { color: c.axisShadow } },
      formatter: (params) => {
        const dataIndex = params[0]?.dataIndex ?? 0;
        const hora = params[0]?.axisValue ?? '';
        const ptInfo = fullPoints[dataIndex];
        const volItem = params.find(p => p.seriesName === 'Autorizações (Volume)');
        const vol  = volItem?.value ?? 0;
        const crms = volItem?.data?.nu_crms ?? 0;
        const med  = params.find(p => p.seriesName === 'Mediana Referência (Hora)')?.value ?? 0;
        const alertaHtml = (ptInfo && ptInfo.is_anomalo_hora === 1)
          ? `<div style="margin-top:8px; font-size:12px; color:#ef4444; font-weight:600;">${(vol / med).toFixed(1)}× acima da mediana</div>`
          : '';
        return `
          <div style="color:${c.tooltipText}; min-width:190px;">
            <div style="font-weight:700; font-size:14px; margin-bottom:10px;">${hora}</div>
            <div style="display:flex; flex-direction:column; gap:8px;">
              <div style="display:flex; justify-content:space-between; align-items:center;">
                <span style="display:flex;align-items:center;gap:6px;"><span style="width:10px;height:10px;border-radius:2px;background:#ef4444;display:inline-block;"></span><span style="font-size:11px; opacity:.6; text-transform:uppercase;">Volume</span></span>
                <span style="font-weight:700; font-size:13px;">${vol} <small>autorizações</small></span>
              </div>
              <div style="display:flex; justify-content:space-between; align-items:center;">
                <span style="display:flex;align-items:center;gap:6px;"><span style="width:10px;height:10px;border-radius:2px;background:#6366f1;display:inline-block;"></span><span style="font-size:11px; opacity:.6; text-transform:uppercase;">CRMs Distintos</span></span>
                <span style="font-weight:700; font-size:13px;">${crms} <small>médicos</small></span>
              </div>
              <div style="border-top:1px solid ${c.tooltipBorder}; padding-top:8px; margin-top:2px; display:flex; justify-content:space-between; align-items:center;">
                <span style="font-size:11px; opacity:.6; text-transform:uppercase;">Mediana Referência</span>
                <span style="font-weight:600; font-size:12px; color:#f59e0b;">${med.toFixed(1)}</span>
              </div>
            </div>
            ${alertaHtml}
          </div>`;
      },
    },
    series: [
      {
        name: 'Autorizações (Volume)',
        type: 'bar',
        barMaxWidth: 28,
        data: fullPoints.map((p, i) => ({ value: p.nu_prescricoes, nu_crms: p.nu_crms_diferentes, is_anomalo_hora: p.is_anomalo_hora, cursor: (p.is_anomalo_hora === 1 && p.nu_prescricoes > 0) ? 'pointer' : 'default', itemStyle: { color: barColors[i] } })),
        emphasis: { itemStyle: { opacity: 1 } },
      },
      {
        name: 'Mediana Referência (Hora)',
        type: 'line',
        step: 'middle',
        data: fullPoints.map(p => p.mediana_hora),
        lineStyle: { color: '#f59e0b', type: 'dashed', width: 1.5 },
        symbol: 'none',
        emphasis: { disabled: true },
      },
    ],
  };
});
</script>

<template>
  <div class="section-container daily-chart-section animate-fade-in" :class="{ 'is-refreshing': showRefreshingDaily }">
    <!-- Cabeçalho -->
    <div class="section-title" style="border-bottom: none; margin-bottom: 0.5rem; display: flex; justify-content: space-between; align-items: center; width: 100%">
      <div style="display: flex; align-items: center; gap: 0.75rem">
        <i class="pi pi-chart-bar" />
        <span>HISTÓRICO DIÁRIO DE DISPENSAÇÕES</span>
        <span v-if="crmDailyProfileLoading" class="chart-loading-badge">
          <i class="pi pi-spinner pi-spin"></i> Carregando...
        </span>
      </div>
      <div class="filter-controls" style="margin-right: 0.5rem">
        <label class="filter-toggle">
          <input type="checkbox" v-model="filterDailyOnlyAnomalous" />
          <span class="toggle-slider"></span>
          <span class="toggle-label">Apenas Anomalias</span>
        </label>
      </div>
    </div>
    <p class="subtitle" style="padding-left: 1.75rem; margin-top: -0.25rem; margin-bottom: 0.75rem">
      Evolução diária de autorizações. Dias com volume anômalo (detecção de lançamentos em sequência ≥ 7× a mediana trimestral) destacados em vermelho.
    </p>

    <!-- Gráfico Diário -->
    <div v-if="!crmDailyProfile && !crmDailyProfileLoading" class="chart-empty">
      <i class="pi pi-chart-bar" style="font-size:1.5rem; opacity:.4"></i>
      <span>Sem dados de perfil diário disponíveis.</span>
    </div>
    <div v-else class="daily-chart-wrapper">
      <div class="chart-legend-html">
        <span class="legend-item">
          <span class="legend-swatch legend-bar" style="background: #ef4444;"></span>
          Autorizações (anomalia)
        </span>
        <span class="legend-item">
          <span class="legend-swatch legend-bar" :style="{ background: chartUFAccents.bar1 }"></span>
          Autorizações (normal)
        </span>
        <span class="legend-item">
          <span class="legend-swatch legend-dashed"></span>
          Mediana Referência
        </span>
      </div>
      <VChart
        :option="chartOptionDaily"
        autoresize
        class="daily-dispensacao-chart"
        @click="onChartClick"
        @datazoom="onDailyZoom"
      />
    </div>

    <!-- Detalhamento Horário (Drill-down) -->
    <div v-if="selectedDay" class="hourly-detail-wrapper animate-fade-in" :class="{ 'is-refreshing': showRefreshingHourly }">
      <div class="hourly-header" style="display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid rgba(255,255,255,0.05); padding-bottom: 1rem; margin-bottom: 1.5rem;">
        <div class="title-group" style="display: flex; align-items: center; gap: 0.75rem;">
          <i class="pi pi-clock" style="color: #6366f1; font-size: 1.1rem;"></i>
          <h3 style="margin:0; font-size: 0.9rem; letter-spacing: 0.05em; font-weight: 700; white-space: nowrap; color: white; opacity: 0.8;">
            ANÁLISE HORÁRIA: {{ formatarData(selectedDay.dt_janela) }}
          </h3>
          <span v-if="selectedDay.is_anomalo" class="anomalo-badge">ANOMALIA DETECTADA</span>
        </div>
        <button class="close-detail-btn" @click="selectedDay = null" style="background: transparent; border: none; color: white; opacity: 0.5; cursor: pointer; padding: 5px;">
          <i class="pi pi-times" />
        </button>
      </div>

      <div class="hourly-body" style="position: relative; min-height: 250px;">
        <p class="hourly-subtitle">
          Distribuição das <strong>{{ selectedDay.nu_prescricoes_dia }} prescrições</strong> ao longo do dia,
          comparando o volume real com a mediana trimestral de cada horário.
        </p>
        <div class="daily-chart-wrapper">
          <div class="chart-legend-html">
            <span class="legend-item">
              <span class="legend-swatch legend-bar" style="background: #ef4444;"></span>
              Autorizações (anomalia)
            </span>
            <span class="legend-item">
              <span class="legend-swatch legend-bar" :style="{ background: chartUFAccents.bar1 }"></span>
              Autorizações (normal)
            </span>
            <span class="legend-item">
              <span class="legend-swatch legend-dashed"></span>
              Mediana Referência
            </span>
          </div>
          <VChart
            :option="chartOptionHourly"
            autoresize
            class="hourly-chart"
            @click="onHourlyChartClick"
          />
        </div>

        <!-- Raio-X Sub-horário -->
        <div v-if="selectedHourlyHour !== null" class="raiox-wrapper animate-fade-in">
          <div class="raiox-header">
            <div class="raiox-title">
              <i class="pi pi-search" />
              <span>RAIO-X: TRANSAÇÕES {{ selectedHourlyHour === 'all' ? 'DO DIA TODO' : `ÀS ${String(selectedHourlyHour).padStart(2, '0')}H` }}</span>
              <span v-if="!hourlyTransactionsLoading && groupedRaiox.length > 0" class="raiox-count-badge">
                {{ groupedRaiox.length }} Autorização{{ groupedRaiox.length !== 1 ? 'es' : '' }}
              </span>
              <i v-if="hourlyTransactionsLoading" class="pi pi-spinner pi-spin raiox-spinner" />
            </div>
            <button class="close-detail-btn" @click="selectedHourlyHour = null">
              <i class="pi pi-times" />
            </button>
          </div>

          <div v-if="!hourlyTransactionsLoading && hourlyTransactions.length === 0" class="raiox-empty">
            <i class="pi pi-inbox raiox-empty-icon" />
            <span>Nenhuma transação encontrada para este horário.</span>
          </div>

          <div v-else class="raiox-table-wrapper" :class="{ 'is-loading': hourlyTransactionsLoading }">
            <table class="premium-table row-hover raiox-table flat-mode">
              <thead class="sticky-thead">
                <tr>
                  <th width="8%" class="col-center">Horário</th>
                  <th width="13%">Nº Autorização</th>
                  <th width="14%">CRM</th>
                  <th width="8%" class="col-center">Qtd.</th>
                  <th width="42%">Descrição / Princípio Ativo</th>
                  <th width="15%" class="col-right">Valor Total</th>
                </tr>
              </thead>
              <tbody>
                <template v-for="tx in groupedRaiox" :key="tx.num_autorizacao">
                  <tr
                    :class="{ 'row-expanded-main': expandedRaioxRows.has(tx.num_autorizacao) }"
                    @click="toggleRaioxRow(tx.num_autorizacao)"
                    class="cursor-pointer"
                  >
                    <td class="col-center raiox-time align-top">
                      <i :class="['pi', expandedRaioxRows.has(tx.num_autorizacao) ? 'pi-chevron-down' : 'pi-chevron-right']" style="font-size: 0.6rem; margin-right: 4px; opacity: 0.5;" />
                      {{ (tx.data_hora.split(' ')[1] || tx.data_hora).split('.')[0] }}
                    </td>
                    <td class="raiox-auth align-top font-mono">{{ tx.num_autorizacao }}</td>
                    <td class="align-top">
                      <div class="crm-badge-container">
                        <span
                          class="issue-tag raiox-crm-tag"
                          :style="crmFrequencies[tx.crm] > 1 ? { borderColor: getCRMColor(tx.crm), color: getCRMColor(tx.crm), background: `color-mix(in srgb, ${getCRMColor(tx.crm)} 15%, transparent)` } : {}"
                        >
                          {{ tx.crm }}/{{ tx.crm_uf }}
                        </span>
                        <span
                          v-if="crmFrequencies[tx.crm] > 1"
                          class="crm-recurrence-badge"
                          :style="{ border: `1px solid ${getCRMColor(tx.crm)}`, color: getCRMColor(tx.crm) }"
                          v-tooltip.top="`Este médico possui ${crmFrequencies[tx.crm]} autorizações nesta hora`"
                        >
                          {{ crmFrequencies[tx.crm] }}x
                        </span>
                      </div>
                    </td>
                    <td class="col-center align-top">
                      <span class="count-pill">{{ tx.items.length }}</span>
                    </td>
                    <td class="align-top">
                      <div class="raiox-item-summary">
                        <span class="flat-item-prod">{{ truncate(tx.items[0].produto || 'PRODUTO NÃO IDENTIFICADO', 40) }}</span>
                        <span class="flat-item-princ"> ({{ truncate(tx.items[0].principio_ativo || '—', 30) }})</span>
                        <span v-if="tx.items.length > 1" class="more-items-pill">
                          <i class="pi pi-plus"></i>
                          {{ tx.items.length - 1 }}
                        </span>
                      </div>
                    </td>
                    <td class="col-right raiox-val-cell align-top">
                      R$ {{ tx.vl_autor_formatado || tx.vl_autorizacao.toFixed(2) }}
                    </td>
                  </tr>

                  <tr v-if="expandedRaioxRows.has(tx.num_autorizacao)" class="raiox-details-expanded-row">
                    <td colspan="6" class="p-0">
                      <div class="expanded-items-list animate-fade-in">
                        <div v-for="(item, idx) in tx.items" :key="idx" class="expanded-item-entry">
                          <div class="item-main-info">
                            <span class="item-name">{{ item.produto }}</span>
                            <span class="item-active">({{ item.principio_ativo || '—' }})</span>
                            <span class="item-gtin">GTIN: {{ item.codigo_barra }}</span>
                          </div>
                          <div class="item-price">R$ {{ item.valor_pago.toFixed(2) }}</div>
                        </div>
                      </div>
                    </td>
                  </tr>
                </template>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.animate-fade-in {
  animation: fadeIn 0.3s ease-out;
}
@keyframes fadeIn {
  from { opacity: 0; transform: translateY(10px); }
  to { opacity: 1; transform: translateY(0); }
}

.section-container {
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  border-radius: 12px;
  padding: 1rem;
  width: 100%;
  box-sizing: border-box;
  overflow: hidden;
}
.section-title {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  font-size: 0.85rem;
  font-weight: 600;
  text-transform: uppercase;
  color: var(--text-color);
  margin-bottom: 1rem;
  letter-spacing: 0.05em;
  border-bottom: 1px solid var(--tabs-border);
  padding-bottom: 0.5rem;
  width: 100%;
  opacity: 0.85;
}
.section-title i { color: var(--primary-color); font-size: 1rem; }
.subtitle { margin: 0.25rem 0 0 0; font-size: 0.8rem; color: var(--text-muted); }

.is-refreshing { opacity: 0.5; pointer-events: none; transition: opacity 0.3s ease; }

.daily-chart-wrapper { display: flex; flex-direction: column; gap: 0; }
.chart-legend-html {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 1.25rem;
  padding: 0.35rem 0;
}
.legend-item { display: flex; align-items: center; gap: 0.4rem; font-size: 0.72rem; color: var(--text-secondary); }
.legend-swatch { width: 14px; height: 8px; border-radius: 2px; display: inline-block; flex-shrink: 0; }
.legend-dashed { background: none; border-top: 2px dashed #f59e0b; height: 0; width: 18px; border-radius: 0; }
.daily-dispensacao-chart { width: 100%; height: 280px; cursor: pointer; }

.chart-loading-badge { margin-left: 0.75rem; font-size: 0.78rem; color: var(--text-muted); font-weight: 500; }
.chart-empty { display: flex; align-items: center; gap: 0.6rem; padding: 1.5rem 1.75rem; color: var(--text-muted); font-size: 0.88rem; }

.filter-controls { display: flex; align-items: center; gap: 1rem; }
.filter-toggle { display: flex; align-items: center; gap: 0.5rem; cursor: pointer; user-select: none; font-size: 0.75rem; text-transform: none; font-weight: 600; color: var(--text-secondary); }
.filter-toggle input { display: none; }
.toggle-slider { position: relative; width: 32px; height: 18px; background-color: var(--tabs-border); border: 1px solid var(--tabs-border); border-radius: 20px; transition: 0.3s; }
.toggle-slider:before { content: ""; position: absolute; height: 12px; width: 12px; left: 3px; bottom: 3px; background-color: white; border-radius: 50%; transition: 0.3s; }
input:checked + .toggle-slider { background-color: var(--primary-color); }
input:checked + .toggle-slider:before { transform: translateX(14px); }
.toggle-label { letter-spacing: normal; }

/* Hourly Detail */
.hourly-detail-wrapper {
  margin-top: 1.5rem;
  padding: 1.25rem;
  background: var(--surface-card);
  border: 1px solid var(--border-color);
  border-left: 4px solid #ef4444;
  border-radius: 8px;
  box-shadow: 0 4px 12px rgba(0,0,0,0.05);
}
.anomalo-badge {
  background: rgba(239, 68, 68, 0.15);
  color: #ef4444;
  border: 1px solid rgba(239, 68, 68, 0.3);
  font-size: 0.7rem;
  font-weight: 700;
  padding: 2px 8px;
  border-radius: 99px;
  letter-spacing: 0.5px;
}
.close-detail-btn { background: none; border: none; color: var(--text-muted); cursor: pointer; padding: 4px; border-radius: 4px; transition: all 0.2s; }
.close-detail-btn:hover { background: var(--surface-hover); color: #ef4444; }
.hourly-subtitle { font-size: 0.9rem; color: var(--text-muted); margin-bottom: 1rem; line-height: 1.4; }
.hourly-chart { height: 240px; }

/* Raio-X */
.raiox-wrapper {
  margin-top: 1.5rem;
  background: v-bind(raioxBg);
  backdrop-filter: blur(8px);
  -webkit-backdrop-filter: blur(8px);
  border: 1px solid var(--card-border);
  border-radius: 8px;
  padding: 1rem 1.25rem;
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
}
.raiox-header { display: flex; justify-content: space-between; align-items: center; }
.raiox-title { display: flex; align-items: center; gap: 0.5rem; font-size: 0.8rem; font-weight: 600; letter-spacing: 0.06em; text-transform: uppercase; color: var(--risk-high); }
.raiox-title .pi-search { font-size: 0.85rem; }
.raiox-count-badge {
  background: color-mix(in srgb, var(--risk-high) 15%, transparent);
  color: var(--risk-high);
  border: 1px solid color-mix(in srgb, var(--risk-high) 30%, transparent);
  border-radius: 99px;
  font-size: 0.68rem;
  font-weight: 500;
  padding: 0.1rem 0.55rem;
  letter-spacing: 0.03em;
}
.raiox-spinner { font-size: 0.8rem; color: var(--text-muted); }
.raiox-empty { display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 0.5rem; padding: 2rem 1rem; color: var(--text-muted); font-size: 0.85rem; min-height: 390px; }
.raiox-empty-icon { font-size: 1.75rem; opacity: 0.4; }
.raiox-table-wrapper { border-radius: 6px; min-height: 390px; background: color-mix(in srgb, var(--card-bg) 40%, transparent); border: 1px solid var(--tabs-border); }
.raiox-table-wrapper.is-loading { opacity: 0.4; pointer-events: none; transition: opacity 0.25s ease; }

.premium-table { width: 100%; border-collapse: collapse; table-layout: fixed; }
.premium-table th { padding: 0.6rem 0.5rem; background: transparent; color: color-mix(in srgb, var(--text-secondary) 85%, transparent); font-size: 0.68rem; font-weight: 500; text-transform: uppercase; letter-spacing: 0.02em; border-bottom: 2px solid var(--tabs-border); text-align: center; }
.premium-table th:first-child { text-align: left; }
.premium-table td { padding: 0.55rem 0.5rem; border-bottom: 1px solid var(--tabs-border); vertical-align: middle; color: color-mix(in srgb, var(--text-color) 85%, transparent); font-size: 0.8rem; text-transform: none !important; }
.premium-table tbody tr:last-child td { border-bottom: none; }
.premium-table.row-hover tbody tr:hover { background: var(--table-hover) !important; cursor: pointer; }

.raiox-table { font-size: 0.75rem; table-layout: fixed; width: 100%; border-collapse: separate; border-spacing: 0; }
.sticky-thead th { position: sticky; top: 0; z-index: 10; background: var(--card-bg) !important; box-shadow: inset 0 -1px 0 var(--tabs-border); }
.raiox-table .col-center { text-align: center; }
.col-center { text-align: center; }
.col-right { text-align: right; }
.align-top { vertical-align: top !important; padding-top: 1rem !important; }

.crm-badge-container { display: flex; align-items: center; gap: 0.4rem; padding-right: 0.8rem; }
.crm-recurrence-badge { font-size: 0.62rem; font-weight: 800; padding: 0.1rem 0.35rem; border-radius: 4px; background: transparent; }

.issue-tag {
  font-size: 0.7rem;
  font-weight: 600;
  padding: 0.25rem 0.65rem;
  border-radius: 6px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 0.35rem;
  white-space: nowrap;
  min-width: 85px;
  letter-spacing: 0.02em;
  text-transform: none !important;
  backdrop-filter: blur(4px);
  -webkit-backdrop-filter: blur(4px);
  transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
  border: 1px solid transparent;
}

.count-pill { background: var(--tabs-border); padding: 1px 6px; border-radius: 4px; font-weight: 600; font-size: 0.75rem; }

.raiox-item-summary { display: flex; align-items: center; gap: 0.5rem; padding-top: 0.85rem; }
.flat-item-prod { font-size: 0.78rem; font-weight: 700; color: var(--primary-color); letter-spacing: -0.01em; }
.flat-item-princ { font-size: 0.68rem; opacity: 0.5; font-style: italic; color: var(--text-color); max-width: 250px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.more-items-pill {
  background: color-mix(in srgb, var(--primary-color) 15%, transparent);
  color: var(--primary-color);
  border: 1px solid color-mix(in srgb, var(--primary-color) 30%, transparent);
  padding: 0.1rem 0.5rem;
  border-radius: 99px;
  font-size: 0.62rem;
  font-weight: 800;
  display: flex;
  align-items: center;
  gap: 2px;
  box-shadow: 0 2px 4px rgba(0,0,0,0.1);
}
.more-items-pill i { font-size: 0.5rem; opacity: 0.8; }

.raiox-val-cell { font-weight: 700; color: var(--text-color); }
.row-expanded-main { background: color-mix(in srgb, var(--primary-color) 5%, transparent) !important; }

.expanded-items-list { background: color-mix(in srgb, var(--card-bg) 95%, white 2%); border-bottom: 2px solid var(--tabs-border); }
.expanded-item-entry { display: flex; justify-content: space-between; align-items: center; padding: 0.6rem 1.5rem 0.6rem 3rem; border-bottom: 1px solid color-mix(in srgb, var(--tabs-border) 30%, transparent); }
.expanded-item-entry:last-child { border-bottom: none; }
.item-main-info { display: flex; align-items: center; gap: 0.6rem; }
.item-name { font-size: 0.75rem; font-weight: 600; color: var(--primary-color); }
.item-active { font-size: 0.7rem; opacity: 0.6; font-style: italic; }
.item-gtin { font-size: 0.6rem; font-family: var(--font-mono); opacity: 0.4; }
.item-price { font-size: 0.75rem; font-weight: 700; font-family: var(--font-mono); }
</style>
