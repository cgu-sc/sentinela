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
const { 
  crmDailyProfile, 
  crmDailyProfileLoading, 
  crmHourlyProfile, 
  crmHourlyProfileLoading,
  selectedTimelineEvent 
} = storeToRefs(cnpjDetailStore);
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

// Zoom inicial e centralização são controlados pelo watch(filteredDailyDays) abaixo.

function onDailyZoom(params) {
  if (params.batch) {
    dailyZoomStart.value = params.batch[0].start;
    dailyZoomEnd.value = params.batch[0].end;
  } else {
    dailyZoomStart.value = params.start;
    dailyZoomEnd.value = params.end;
  }
}

// Navegação mensal manual
function shiftZoom(direction) {
  const totalDays = dailyDates.value.length;
  if (totalDays === 0) return;

  const currentSpan = dailyZoomEnd.value - dailyZoomStart.value;
  const monthPercent = (30 / totalDays) * 100;
  
  let newStart, newEnd;

  if (direction === 'next') {
    newEnd = Math.min(100, dailyZoomEnd.value + monthPercent);
    newStart = Math.max(0, newEnd - currentSpan);
  } else {
    newStart = Math.max(0, dailyZoomStart.value - monthPercent);
    newEnd = Math.min(100, newStart + currentSpan);
  }

  dailyZoomStart.value = newStart;
  dailyZoomEnd.value = newEnd;
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

const raioxTotalValue = computed(() => {
  return groupedRaiox.value.reduce((sum, tx) => sum + tx.vl_autorizacao, 0);
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
    const t0 = performance.now();
    const res = await fetch(url);
    if (!res.ok) throw new Error('Falha HTTP');
    const data = await res.json();
    cnpjDetailStore.requestTimes['transacoes-horarias'] = {
      label: 'Transações Horárias',
      ms: Math.round(performance.now() - t0),
    };
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
  const fixedSpan = totalDays > 30 ? (30 / totalDays) * 100 : 100;

  return {
    ...chartTheme.value,
    animation: true,
    animationDuration: 100,
    animationDurationUpdate: 100,
    legend: { show: false },
    grid: { top: 16, right: 20, bottom: 80, left: 50, containLabel: false },
    xAxis: {
      type: 'category',
      data: dailyDates.value,
      axisLabel: {
        formatter: (v) => v ? `${v.slice(8, 10)}/${v.slice(5, 7)}` : '',
        interval: 'auto', // O ECharts decide quantos labels mostrar para não embolar
        rotate: 45,       // Inclina para caber mais datas
        fontSize: 10,
        color: chartTheme.value.muted
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
      { type: 'inside', start: startZoom, end: endZoom, zoomLock: true },
      { 
        type: 'slider', 
        start: startZoom, 
        end: endZoom, 
        height: 16, 
        bottom: 10, 
        borderColor: 'transparent',
        backgroundColor: themeStore.isDark ? 'rgba(255,255,255,0.03)' : 'rgba(0,0,0,0.03)',
        fillerColor: themeStore.isDark ? 'rgba(99, 102, 241, 0.3)' : 'rgba(99, 102, 241, 0.2)',
        handleSize: 0, 
        showDetail: false,
        showDataShadow: false,
        zoomLock: true,
        brushSelect: false,
        borderRadius: 8
      },
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
            cursor: day.is_anomalo ? 'pointer' : 'default',
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
        silent: true,
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
        data: fullPoints.map((p, i) => {
          const isSelected = selectedHourlyHour.value === p.hr_janela;
          const hasSelection = selectedHourlyHour.value !== 'all' && selectedHourlyHour.value !== null;
          return { 
            value: p.nu_prescricoes, 
            nu_crms: p.nu_crms_diferentes, 
            is_anomalo_hora: p.is_anomalo_hora, 
            cursor: (p.is_anomalo_hora === 1 && p.nu_prescricoes > 0) ? 'pointer' : 'default', 
            itemStyle: { 
              color: barColors[i],
              opacity: hasSelection && !isSelected ? 0.3 : 1
            } 
          };
        }),
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

// ── Auto-seleção do Dia Mais Anômalo e Ajuste de Foco do Gráfico ──
watch(filteredDailyDays, (newDays) => {
  if (newDays.length > 0 && !selectedDay.value) {
    const anomalousDays = newDays.filter(d => d.is_anomalo === 1);
    if (anomalousDays.length > 0) {
      // 1. Encontra o pior dia (maior volume)
      const maxDay = anomalousDays.reduce((max, d) => 
        (d.nu_prescricoes_dia > max.nu_prescricoes_dia) ? d : max, anomalousDays[0]
      );
      selectedDay.value = maxDay;
      selectedHourlyHour.value = 'all';
      loadTransactions(maxDay.dt_janela, null);

      // 2. Centraliza o Gráfico no dia selecionado
      const idx = newDays.findIndex(d => d.dt_janela === maxDay.dt_janela);
      if (idx !== -1) {
        const total = newDays.length;
        const windowSize = 30; // Mostrar 30 dias ao redor
        const halfWindow = windowSize / 2;
        
        // Calcula porcentagens
        let startIdx = Math.max(0, idx - halfWindow);
        let endIdx = Math.min(total, startIdx + windowSize);
        
        // Ajusta se bater no final
        if (endIdx === total) {
          startIdx = Math.max(0, total - windowSize);
        }

        dailyZoomStart.value = (startIdx / total) * 100;
        dailyZoomEnd.value = (endIdx / total) * 100;
      }
    } else {
      // 3. Caso não haja anomalia, mostra os últimos 30 dias por padrão
      const total = newDays.length;
      const windowSize = 30;
      dailyZoomStart.value = Math.max(0, 100 - (windowSize / total) * 100);
      dailyZoomEnd.value = 100;
    }
  }
}, { immediate: true });

// ── Watch para Navegação Externa (Deep-Link) ──────────────────────────────
// Observa AMBOS: o evento de navegação e o cache de dados.
// Isso garante que mesmo se o evento disparar antes do cache estar pronto,
// o handler tentará novamente assim que os dados chegarem.
watch([selectedTimelineEvent, cachedCrmDailyProfile], async ([evt, profile]) => {
  if (!evt || !profile) return;

  const dayObj = profile.days.find(d => d.dt_janela === evt.date);
  if (!dayObj) return;

  // 1. Seleciona o dia — mostra o dia todo sem filtrar por hora
  selectedDay.value = dayObj;
  selectedHourlyHour.value = 'all';

  // 2. Carrega as transações do dia inteiro
  await loadTransactions(evt.date, null);

  // 3. Centraliza o zoom
  const idx = profile.days.findIndex(d => d.dt_janela === evt.date);
  if (idx !== -1) {
    const total = profile.days.length;
    const windowSize = 30;
    const halfWindow = windowSize / 2;
    let startIdx = Math.max(0, idx - halfWindow);
    let endIdx = Math.min(total, startIdx + windowSize);
    if (endIdx === total) startIdx = Math.max(0, total - windowSize);

    dailyZoomStart.value = (startIdx / total) * 100;
    dailyZoomEnd.value = (endIdx / total) * 100;
  }

  // 4. Limpa o evento para permitir futuras navegações
  cnpjDetailStore.clearTimelineNavigation();
});
</script>

<template>
  <div class="cronologia-flow animate-fade-in">
    
    <!-- Breadcrumb de Navegação Dinâmico -->
    <div class="drill-breadcrumb">
      <span class="crumb-item" :class="{ 'is-current': !selectedDay }">
        <i class="pi pi-chart-bar crumb-icon" />
        <span>Histórico Diário</span>
      </span>
      <template v-if="selectedDay">
        <i class="pi pi-chevron-right crumb-arrow" />
        <span class="crumb-item" :class="{ 'is-current': selectedDay && selectedHourlyHour === null }">
          <i class="pi pi-calendar crumb-icon" />
          <span>{{ formatarData(selectedDay.dt_janela) }}</span>
          <span v-if="selectedDay.is_anomalo" class="crumb-anomaly-dot" />
        </span>
      </template>
      <template v-if="selectedHourlyHour !== null">
        <i class="pi pi-chevron-right crumb-arrow" />
        <span class="crumb-item is-current">
          <i class="pi pi-search crumb-icon" />
          <span>Raio-X · {{ selectedHourlyHour === 'all' ? 'Dia Todo' : `${String(selectedHourlyHour).padStart(2, '0')}h` }}</span>
        </span>
      </template>
    </div>

    <!-- NÍVEL 1: Histórico Diário -->
    <div class="drill-panel level-daily" :class="{ 'is-refreshing': showRefreshingDaily }">
      <div class="drill-panel-header">
        <div class="drill-panel-title">
          <i class="pi pi-chart-bar" />
          <span>HISTÓRICO DIÁRIO DE DISPENSAÇÕES</span>
          <span v-if="crmDailyProfileLoading" class="chart-loading-badge">
            <i class="pi pi-spinner pi-spin"></i> Carregando...
          </span>
        </div>
        <div class="filter-controls">
          <div class="chart-nav-buttons">
            <button class="nav-btn" @click="shiftZoom('prev')" title="Mês Anterior">
              <i class="pi pi-chevron-left" />
            </button>
            <button class="nav-btn" @click="shiftZoom('next')" title="Próximo Mês">
              <i class="pi pi-chevron-right" />
            </button>
          </div>
          <div class="filter-divider"></div>
          <label class="filter-toggle">
            <input type="checkbox" v-model="filterDailyOnlyAnomalous" />
            <span class="toggle-slider"></span>
            <span class="toggle-label">Apenas Anomalias</span>
          </label>
        </div>
      </div>
      <p class="subtitle" style="padding-left: 1.75rem; margin-top: 0; margin-bottom: 0.75rem">
        Evolução diária de autorizações. Dias com volume anômalo (lançamentos ≥ 7× a mediana) destacados em vermelho.
      </p>
      
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
      <div v-if="!selectedDay && crmDailyProfile" class="drill-hint">
        <i class="pi pi-hand-pointer" />
        <span>Clique em um dia no gráfico para ver a análise horária detalhada (apenas dias com registro de anomalia podem ser visualizados)</span>
      </div>
    </div>

    <!-- Conector Diário → Horário -->
    <div v-if="selectedDay" class="drill-connector">
      <div class="connector-line" />
      <div class="connector-dot">
        <i class="pi pi-clock" />
      </div>
    </div>

    <!-- NÍVEL 2: Análise Horária -->
    <div v-if="selectedDay" class="drill-panel level-hourly animate-fade-in" :class="{ 'is-refreshing': showRefreshingHourly }">
      <div class="drill-panel-header">
        <div class="drill-panel-title">
          <i class="pi pi-clock" style="color: #6366f1;" />
          <span>ANÁLISE HORÁRIA</span>
          <span class="drill-context-tag">{{ formatarData(selectedDay.dt_janela) }}</span>
          <span v-if="selectedDay.is_anomalo" class="anomalo-badge">ANOMALIA DETECTADA</span>
        </div>
        <div class="drill-panel-actions">
          <button 
            v-if="selectedHourlyHour !== 'all'" 
            class="reset-filter-btn animate-fade-in"
            @click="selectedHourlyHour = 'all'; loadTransactions(selectedDay.dt_janela, null)"
          >
            <i class="pi pi-filter-slash" />
            <span>Ver Dia Todo</span>
          </button>
          <button class="close-detail-btn" @click="selectedDay = null; selectedHourlyHour = null">
            <i class="pi pi-times" />
          </button>
        </div>
      </div>
      <p class="subtitle" style="padding-left: 1.75rem; margin-top: 0; margin-bottom: 0.75rem">
        Distribuição das <strong>{{ selectedDay.nu_prescricoes_dia }} autorizações</strong> ao longo do dia.
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
      <div v-if="selectedHourlyHour === null" class="drill-hint">
        <i class="pi pi-hand-pointer" />
        <span>Clique em uma barra para ver as transações detalhadas no Raio-X</span>
      </div>
    </div>

    <!-- Conector Horário → Raio-X -->
    <div v-if="selectedHourlyHour !== null" class="drill-connector">
      <div class="connector-line" />
      <div class="connector-dot connector-dot-raiox">
        <i class="pi pi-search" />
      </div>
    </div>

    <!-- NÍVEL 3: Raio-X -->
    <div v-if="selectedHourlyHour !== null" class="drill-panel level-raiox animate-fade-in">
      <div class="drill-panel-header">
        <div class="drill-panel-title">
          <i class="pi pi-search" style="color: #8b5cf6;" />
          <span>RAIO-X: TRANSAÇÕES</span>
          <span class="drill-context-tag drill-context-tag-raiox">
            {{ selectedHourlyHour === 'all' ? 'Dia Todo' : `${String(selectedHourlyHour).padStart(2, '0')}h` }}
          </span>
          <span v-if="!hourlyTransactionsLoading && groupedRaiox.length > 0" class="raiox-count-badge">
            {{ groupedRaiox.length }} Autorização{{ groupedRaiox.length !== 1 ? 'es' : '' }}
          </span>
          <i v-if="hourlyTransactionsLoading" class="pi pi-spinner pi-spin raiox-spinner" />
        </div>
      </div>
      
      <!-- Legenda de Apoio Visual -->
      <div class="raiox-legend-tip animate-fade-in">
        <div class="legend-tip-item">
          <i class="pi pi-palette" />
          <span>Cores identificam <strong>médicos diferentes</strong> para destacar padrões de concentração.</span>
        </div>
        <div class="legend-tip-divider" />
        <div class="legend-tip-item">
          <span class="sample-badge">2x</span>
          <span>Indica a <strong>recorrência</strong> deste médico na mesma janela horária.</span>
        </div>
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
              <tr :class="{ 'row-expanded-main': expandedRaioxRows.has(tx.num_autorizacao) }"
                  @click="toggleRaioxRow(tx.num_autorizacao)"
                  class="cursor-pointer">
                <td class="col-center raiox-time align-top">
                  <i :class="['pi', expandedRaioxRows.has(tx.num_autorizacao) ? 'pi-chevron-down' : 'pi-chevron-right']"
                     style="font-size: 0.6rem; margin-right: 4px; opacity: 0.5;" />
                  {{ (tx.data_hora.split(' ')[1] || tx.data_hora).split('.')[0] }}
                </td>
                <td class="raiox-auth align-top font-mono">{{ tx.num_autorizacao }}</td>
                <td class="align-top">
                  <div class="crm-badge-container">
                    <span class="issue-tag raiox-crm-tag"
                          :style="crmFrequencies[tx.crm] > 1 ? {
                            borderColor: getCRMColor(tx.crm),
                            color: getCRMColor(tx.crm),
                            background: `color-mix(in srgb, ${getCRMColor(tx.crm)} 15%, transparent)`
                          } : {}">
                      {{ tx.crm }}/{{ tx.crm_uf }}
                    </span>
                    <span v-if="crmFrequencies[tx.crm] > 1"
                          class="crm-recurrence-badge"
                          :style="{ border: `1px solid ${getCRMColor(tx.crm)}`, color: getCRMColor(tx.crm) }"
                          v-tooltip.top="`Este médico possui ${crmFrequencies[tx.crm]} autorizações nesta hora`">
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
              <!-- Detalhes Expandidos -->
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
          <tfoot v-if="groupedRaiox.length > 0">
            <tr class="raiox-footer-row">
              <td colspan="5" class="col-right footer-label">VALOR TOTAL DO PERÍODO SELECIONADO:</td>
              <td class="col-right footer-value">R$ {{ raioxTotalValue.toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 }) }}</td>
            </tr>
          </tfoot>
        </table>
      </div>
    </div>

  </div>
</template>

<style scoped>
/* ── Layout Base (Cronologia Flow) ───────────────────────────────────────── */
.cronologia-flow {
  display: flex;
  flex-direction: column;
  gap: 0;
  width: 100%;
}

.animate-fade-in {
  animation: fadeIn 0.4s cubic-bezier(0.4, 0, 0.2, 1);
}
@keyframes fadeIn {
  from { opacity: 0; transform: translateY(15px); }
  to { opacity: 1; transform: translateY(0); }
}

/* ── Breadcrumb Dinâmico ─────────────────────────────────────────────────── */
.drill-breadcrumb {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  padding: 0.5rem 1.25rem;
  background: var(--surface-card);
  border: 1px solid var(--card-border);
  border-radius: 99px;
  margin-bottom: 1.5rem;
  width: fit-content;
  align-self: center;
  box-shadow: 0 4px 12px rgba(0,0,0,0.1);
  backdrop-filter: blur(8px);
}
.crumb-item {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  font-size: 0.75rem;
  font-weight: 500;
  color: var(--text-muted);
  transition: all 0.2s;
}
.crumb-item.is-current { color: var(--primary-color); font-weight: 700; }
.crumb-icon { font-size: 0.85rem; }
.crumb-arrow { font-size: 0.6rem; opacity: 0.3; }
.crumb-anomaly-dot {
  width: 6px;
  height: 6px;
  background: #ef4444;
  border-radius: 50%;
  box-shadow: 0 0 8px #ef4444;
}

/* ── Painéis de Detalhamento (Drill Panels) ──────────────────────────────── */
.drill-panel {
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  border-radius: 12px;
  padding: 1.25rem;
  position: relative;
  transition: all 0.3s ease;
  box-shadow: 0 2px 8px rgba(0,0,0,0.05);
}

.level-daily { border-left: 4px solid var(--primary-color); }
.level-hourly { 
  border-left: 4px solid #6366f1; 
  background: color-mix(in srgb, var(--card-bg) 85%, transparent); 
}
.level-raiox { 
  border-left: 4px solid #8b5cf6; 
  background: color-mix(in srgb, var(--card-bg) 70%, transparent);
  backdrop-filter: blur(12px);
  -webkit-backdrop-filter: blur(12px);
}

.drill-panel-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 1rem;
}
.drill-panel-title {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  font-size: 0.85rem;
  font-weight: 700;
  letter-spacing: 0.05em;
  text-transform: uppercase;
  color: var(--text-color);
}
.drill-panel-title i { font-size: 1.1rem; }

.drill-context-tag {
  font-size: 0.75rem;
  background: rgba(99, 102, 241, 0.15);
  color: #818cf8;
  padding: 2px 10px;
  border-radius: 6px;
  border: 1px solid rgba(99, 102, 241, 0.3);
  margin-left: 0.5rem;
  text-transform: none;
  letter-spacing: 0;
}
.drill-context-tag-raiox { background: rgba(139, 92, 246, 0.15); color: #a78bfa; border-color: rgba(139, 92, 246, 0.3); }

/* ── Conectores Visuais ─────────────────────────────────────────────────── */
.drill-connector {
  height: 40px;
  position: relative;
  display: flex;
  justify-content: center;
  align-items: center;
}
.connector-line {
  position: absolute;
  top: 0;
  bottom: 0;
  width: 2px;
  background: linear-gradient(to bottom, var(--card-border), var(--primary-color), var(--card-border));
  opacity: 0.5;
}
.connector-dot {
  width: 28px;
  height: 28px;
  background: var(--surface-card);
  border: 2px solid var(--primary-color);
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 2;
  box-shadow: 0 0 15px rgba(99, 102, 241, 0.3);
}
.connector-dot i { font-size: 0.75rem; color: var(--primary-color); }
.connector-dot-raiox { border-color: #8b5cf6; box-shadow: 0 0 15px rgba(139, 92, 246, 0.3); }
.connector-dot-raiox i { color: #8b5cf6; }

/* ── Elementos Internos ─────────────────────────────────────────────────── */
.drill-hint {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 0.6rem;
  margin-top: 1.5rem;
  padding: 0.75rem;
  background: rgba(255,255,255,0.03);
  border-radius: 8px;
  font-size: 0.78rem;
  color: var(--text-muted);
  font-style: italic;
}
.drill-hint i { color: var(--primary-color); font-size: 0.9rem; animation: pulseHand 2s infinite; }
@keyframes pulseHand {
  0%, 100% { transform: scale(1); opacity: 0.6; }
  50% { transform: scale(1.2); opacity: 1; }
}

.subtitle { margin: 0; font-size: 0.8rem; color: var(--text-muted); }
.is-refreshing { opacity: 0.6; pointer-events: none; }

.daily-chart-wrapper { display: flex; flex-direction: column; gap: 0.5rem; }
.chart-legend-html { display: flex; align-items: center; justify-content: center; gap: 1.25rem; padding: 0.5rem 0; }
.legend-item { display: flex; align-items: center; gap: 0.4rem; font-size: 0.72rem; color: var(--text-secondary); }
.legend-swatch { width: 14px; height: 8px; border-radius: 2px; }
.legend-dashed { background: none; border-top: 2px dashed #f59e0b; height: 0; width: 18px; }
.daily-dispensacao-chart { width: 100%; height: 280px; }
.hourly-chart { width: 100%; height: 240px; }

.chart-loading-badge { margin-left: 0.75rem; font-size: 0.78rem; color: var(--text-muted); }
.chart-empty { display: flex; align-items: center; gap: 0.6rem; padding: 2rem; color: var(--text-muted); justify-content: center; }

.filter-controls { display: flex; align-items: center; }
.filter-toggle { display: flex; align-items: center; gap: 0.5rem; cursor: pointer; font-size: 0.75rem; color: var(--text-secondary); }

/* ── Botões de Navegação do Gráfico ── */
.chart-nav-buttons {
  display: flex;
  gap: 2px;
  background: rgba(0, 0, 0, 0.04);
  padding: 2px;
  border-radius: 8px;
  border: 1px solid var(--card-border);
}

:global(.dark-mode) .chart-nav-buttons {
  background: rgba(255, 255, 255, 0.06) !important;
  border-color: rgba(255, 255, 255, 0.1) !important;
}

.nav-btn {
  background: transparent !important;
  border: none;
  color: var(--text-color);
  width: 28px;
  height: 28px;
  border-radius: 6px;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
}

:global(.dark-mode) .nav-btn {
  color: rgba(255, 255, 255, 0.8) !important;
}

.nav-btn:hover {
  background: var(--primary-color) !important;
  color: white !important;
  transform: translateY(-1px);
}

.nav-btn:active {
  transform: translateY(0);
}

.filter-divider {
  width: 1px;
  height: 18px;
  background: var(--card-border);
  margin: 0 12px;
  opacity: 0.6;
}

:global(.dark-mode) .filter-divider {
  background: rgba(255, 255, 255, 0.1);
}
.filter-toggle input { display: none; }
.toggle-slider { position: relative; width: 32px; height: 18px; background-color: var(--tabs-border); border-radius: 20px; transition: 0.3s; }
.toggle-slider:before { content: ""; position: absolute; height: 12px; width: 12px; left: 3px; bottom: 3px; background-color: white; border-radius: 50%; transition: 0.3s; }
input:checked + .toggle-slider { background-color: var(--primary-color); }
input:checked + .toggle-slider:before { transform: translateX(14px); }

.anomalo-badge { background: rgba(239, 68, 68, 0.15); color: #ef4444; border: 1px solid rgba(239, 68, 68, 0.3); font-size: 0.65rem; font-weight: 700; padding: 2px 8px; border-radius: 99px; margin-left: 0.75rem; }
.close-detail-btn { background: none; border: none; color: var(--text-muted); cursor: pointer; padding: 4px; border-radius: 4px; transition: all 0.2s; }
.close-detail-btn:hover { background: var(--surface-hover); color: #ef4444; }

.drill-panel-actions {
  display: flex;
  align-items: center;
  gap: 0.75rem;
}

.reset-filter-btn {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  background: rgba(99, 102, 241, 0.1);
  border: 1px solid rgba(99, 102, 241, 0.2);
  color: #818cf8;
  padding: 4px 12px;
  border-radius: 6px;
  font-size: 0.7rem;
  font-weight: 700;
  cursor: pointer;
  transition: all 0.2s;
  text-transform: uppercase;
  letter-spacing: 0.02em;
}

.reset-filter-btn:hover {
  background: #6366f1;
  color: white;
  border-color: #6366f1;
  box-shadow: 0 4px 10px rgba(99, 102, 241, 0.3);
}

.reset-filter-btn i {
  font-size: 0.75rem;
}

/* ── Raio-X Table Styling ───────────────────────────────────────────────── */
.raiox-table-wrapper { border-radius: 8px; background: transparent; border: 1px solid var(--tabs-border); overflow: hidden; }
.premium-table { width: 100%; border-collapse: collapse; }
.premium-table th { padding: 0.75rem 0.5rem; background: var(--card-bg); color: var(--text-secondary); font-size: 0.65rem; text-transform: uppercase; border-bottom: 2px solid var(--tabs-border); }
.premium-table td { padding: 0.75rem 0.5rem; border-bottom: 1px solid var(--tabs-border); color: var(--text-color); font-size: 0.78rem; }
.premium-table tbody tr:hover { background: rgba(255,255,255,0.03); cursor: pointer; }
.premium-table tbody tr.raiox-details-expanded-row:hover { background: transparent !important; cursor: default; }

.raiox-count-badge { background: rgba(139, 92, 246, 0.15); color: #a78bfa; border: 1px solid rgba(139, 92, 246, 0.3); border-radius: 99px; font-size: 0.65rem; padding: 1px 8px; margin-left: 0.75rem; }
.raiox-spinner { font-size: 0.8rem; margin-left: 0.5rem; }
.raiox-legend-tip {
  display: flex;
  align-items: center;
  gap: 1.5rem;
  padding: 0.75rem 1.25rem;
  background: rgba(139, 92, 246, 0.05);
  border: 1px dashed rgba(139, 92, 246, 0.2);
  border-radius: 8px;
  margin-bottom: 1.25rem;
}

.legend-tip-item {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  font-size: 0.72rem;
  color: var(--text-secondary);
}

.legend-tip-item i {
  color: #8b5cf6;
  font-size: 0.85rem;
}

.legend-tip-divider {
  width: 1px;
  height: 16px;
  background: rgba(139, 92, 246, 0.15);
}

.sample-badge {
  font-size: 0.6rem;
  font-weight: 800;
  color: #8b5cf6;
  border: 1px solid #8b5cf6;
  padding: 1px 4px;
  border-radius: 3px;
  background: rgba(139, 92, 246, 0.1);
}

.raiox-empty { display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 1rem; padding: 3rem; color: var(--text-muted); }
.raiox-empty-icon { font-size: 2rem; opacity: 0.3; }

.raiox-footer-row {
  background: rgba(139, 92, 246, 0.08);
  border-top: 2px solid var(--primary-color);
}

.footer-label {
  font-weight: 700;
  font-size: 0.7rem;
  letter-spacing: 0.05em;
  color: var(--text-secondary);
}

.footer-value {
  font-weight: 800;
  font-size: 0.9rem;
  color: var(--primary-color);
  font-family: var(--font-mono);
}

.crm-badge-container { display: flex; align-items: center; gap: 0.4rem; }
.issue-tag { font-size: 0.68rem; font-weight: 600; padding: 0.2rem 0.6rem; border-radius: 4px; }
.crm-recurrence-badge { font-size: 0.6rem; font-weight: 800; padding: 1px 4px; border-radius: 3px; }
.count-pill { background: var(--tabs-border); padding: 1px 6px; border-radius: 4px; font-weight: 600; font-size: 0.7rem; }
.raiox-item-summary { display: flex; align-items: center; gap: 0.5rem; }
.flat-item-prod { font-weight: 700; color: var(--primary-color); }
.flat-item-princ { opacity: 0.5; font-size: 0.65rem; }
.more-items-pill { background: rgba(99, 102, 241, 0.1); color: #818cf8; border: 1px solid rgba(99, 102, 241, 0.2); padding: 1px 6px; border-radius: 99px; font-size: 0.6rem; }
.raiox-val-cell { font-weight: 700; font-family: var(--font-mono); }

.expanded-items-list { background: rgba(0,0,0,0.04); padding: 0.5rem 0; }
:global(.dark-mode) .expanded-items-list { background: rgba(255,255,255,0.04); }
.expanded-item-entry { display: flex; justify-content: space-between; align-items: center; padding: 0.5rem 2rem; border-bottom: 1px solid rgba(255,255,255,0.03); }
.item-name { font-size: 0.75rem; font-weight: 600; color: var(--primary-color); }
.item-active { font-size: 0.68rem; opacity: 0.6; margin-left: 0.5rem; }
.item-gtin { font-size: 0.6rem; opacity: 0.3; margin-left: 0.5rem; }
.item-price { font-size: 0.75rem; font-weight: 700; font-family: var(--font-mono); }

.col-center { text-align: center; }
.col-right { text-align: right; }
.sticky-thead th { position: sticky; top: 0; z-index: 10; }
.cursor-pointer { cursor: pointer; }
</style>
