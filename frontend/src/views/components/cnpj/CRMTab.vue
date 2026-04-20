<script setup>
import { computed, ref, onMounted } from "vue";
import { storeToRefs } from 'pinia';
import { useCnpjDetailStore } from '@/stores/cnpjDetail';
import { useFormatting } from "@/composables/useFormatting";
import { useChartTheme } from '@/config/chartTheme';

import VChart from 'vue-echarts';
import { use } from 'echarts/core';
import { BarChart, LineChart } from 'echarts/charts';
import { GridComponent, TooltipComponent, DataZoomComponent, MarkLineComponent, LegendComponent } from 'echarts/components';
import { CanvasRenderer } from 'echarts/renderers';

use([BarChart, LineChart, GridComponent, TooltipComponent, DataZoomComponent, MarkLineComponent, LegendComponent, CanvasRenderer]);

const props = defineProps({
  cnpj: {
    type: String,
    required: true,
  },
});

const cnpjDetailStore = useCnpjDetailStore();
const { prescritoresData, prescritoresLoading, prescritoresError, crmDailyProfile, crmDailyProfileLoading, crmHourlyProfile, crmHourlyProfileLoading } = storeToRefs(cnpjDetailStore);
const { formatCurrencyFull, formatNumberFull, formatarData } = useFormatting();
const { chartTheme, chartRiskAccents } = useChartTheme();

onMounted(() => {
  if (props.cnpj) {
    cnpjDetailStore.fetchCrmDailyProfile(props.cnpj);
    cnpjDetailStore.fetchCrmHourlyProfile(props.cnpj);
  }
});

const filterDailyOnlyAnomalous = ref(false);

const filteredDailyDays = computed(() => {
  const days = crmDailyProfile.value?.days ?? [];
  if (!filterDailyOnlyAnomalous.value) return days;
  return days.filter(d => d.is_anomalo === 1);
});

const dailyDates     = computed(() => filteredDailyDays.value.map(d => d.dt_janela));
const dailyValues    = computed(() => filteredDailyDays.value.map(d => d.nu_prescricoes_dia));
const dailyAnomalous = computed(() => filteredDailyDays.value.map(d => d.is_anomalo === 1));
const dailyMedians   = computed(() => filteredDailyDays.value.map(d => d.mediana_diaria ?? 0));

const dailyMediana   = computed(() => {
  const days = crmDailyProfile.value?.days ?? [];
  if (!days.length) return 0;
  // Para exibir no KPI ou Label geral, pegamos a mediana do mês mais recente
  return days[days.length - 1].mediana_diaria ?? 0;
});

const chartOptionDaily = computed(() => {
  const totalDays = dailyDates.value.length;
  // Exibir inicialmente os últimos 180 dias (ou o total se for menor)
  const windowSize = Math.min(totalDays, 180);
  const startZoom = totalDays > 0 ? Math.max(0, 100 - (windowSize / totalDays) * 100) : 0;
  
  // Limites de Span para forçar entre 20 e 180 barras visíveis
  const minSpan = totalDays > 20 ? (20 / totalDays) * 100 : null;
  const maxSpan = totalDays > 180 ? (180 / totalDays) * 100 : null;

  return {
    ...chartTheme.value,
    animation: false,
    grid: { top: 32, right: 20, bottom: 80, left: 50, containLabel: false },
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
        const points = crmHourlyProfile.value?.points.filter(pt => pt.dt_janela === day.dt_janela) || [];
        
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
                <span style="font-weight:700; font-size:13px;">${day.nu_prescricoes_dia} <small>presc.</small></span>
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
          </div>
        `;
      },
    },
    dataZoom: [
      { type: 'inside', start: startZoom, end: 100, minSpan, maxSpan },
      { type: 'slider', start: startZoom, end: 100, height: 20, bottom: 8, handleSize: 14, minSpan, maxSpan },
    ],
    series: [
      {
        name: 'Prescrições',
        type: 'bar',
        barMaxWidth: 40,
        data: dailyValues.value.map((v, i) => ({
          value: v,
          itemStyle: { 
            color: dailyAnomalous.value[i] ? '#ef4444' : chartRiskAccents.value.primary, 
            opacity: dailyAnomalous.value[i] ? 0.9 : 0.6 
          },
        })),
      },
    {
      name: 'Mediana (Mensal)',
      type: 'line',
      step: 'end',
      symbol: 'none',
      data: dailyMedians.value,
      lineStyle: {
        color: '#f59e0b',
        type: 'dashed',
        width: 1.5,
        opacity: 0.8
      },
      z: 10
    }
  ],
};
});

// --- DRILL-DOWN HORÁRIO ---
const selectedDay = ref(null);

async function onChartClick(params) {
  const day = filteredDailyDays.value?.[params.dataIndex];
  if (!day || !day.is_anomalo) {
    selectedDay.value = null;
    return;
  }
  
  // Agora apenas selecionamos o dia. O computed chartOptionHourly cuidará de filtrar os pontos
  // que já foram pré-carregados no store.
  selectedDay.value = day;
}

const chartOptionHourly = computed(() => {
  if (!selectedDay.value || !crmHourlyProfile.value) return {};
  
  const c = chartTheme.value;
  const targetDate = selectedDay.value.dt_janela;
  const pointsForDay = crmHourlyProfile.value.points.filter(p => p.dt_janela === targetDate);
  const hrPico = selectedDay.value.hr_pico;

  // 24 pontos garantidos (0-23)
  const fullPoints = Array.from({ length: 24 }, (_, h) => {
    const found = pointsForDay.find(p => p.hr_janela === h);
    return found || { hr_janela: h, nu_prescricoes: 0, nu_crms_diferentes: 0, mediana_hora: 0 };
  });

  // Cores das barras: pico em vermelho cheio, demais em gradiente temático
  const barColors = fullPoints.map(p => {
    if (p.hr_janela === hrPico && p.nu_prescricoes > 0) {
      return {
        type: 'linear', x: 0, y: 0, x2: 0, y2: 1,
        colorStops: [
          { offset: 0, color: '#ef4444' },
          { offset: 1, color: 'rgba(239, 68, 68, 0.4)' }
        ]
      };
    }
    return {
      type: 'linear', x: 0, y: 0, x2: 0, y2: 1,
      colorStops: [
        { offset: 0, color: 'rgba(239, 68, 68, 0.65)' },
        { offset: 1, color: 'rgba(239, 68, 68, 0.15)' }
      ]
    };
  });

  return {
    backgroundColor: c.bg,
    animation: true,
    animationDuration: 600,
    animationEasing: 'cubicOut',
    textStyle: { fontFamily: 'Inter, sans-serif' },

    legend: {
      top: 6,
      left: 'center',
      textStyle: { color: c.muted, fontSize: 11, fontWeight: 600 },
      itemGap: 20,
      itemWidth: 12,
      itemHeight: 8,
    },

    grid: { top: 44, left: 54, right: 20, bottom: 42, containLabel: false },

    xAxis: {
      type: 'category',
      data: fullPoints.map(p => `${String(p.hr_janela).padStart(2, '0')}h`),
      axisLine:  { lineStyle: { color: c.grid } },
      axisTick:  { show: false },
      axisLabel: {
        color: c.muted,
        fontSize: 10,
        fontWeight: 600,
        fontFamily: 'Inter, sans-serif',
        interval: 1,
        formatter: (v, i) => (i % 2 === 0 ? v : ''), // Mostra apenas horas pares para não poluir
      },
    },

    yAxis: [
      {
        type: 'value',
        minInterval: 1,
        axisLine:  { show: false },
        axisTick:  { show: false },
        splitLine: { lineStyle: { color: c.grid, type: 'dashed' } },
        axisLabel: { color: c.muted, fontSize: 10, fontFamily: 'Inter, sans-serif' },
      },
    ],

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
        const hora = params[0]?.axisValue ?? '';
        const vol  = params.find(p => p.seriesName === 'Prescrições (Volume)')?.value ?? 0;
        const crms = params.find(p => p.seriesName === 'CRMs Distintos')?.value ?? 0;
        const med  = params.find(p => p.seriesName === 'Mediana Mensal (Hora)')?.value ?? 0;
        const isPico = hora === `${String(hrPico).padStart(2,'0')}h`;
        const alertaHtml = vol > med && med > 0
          ? `<div style="margin-top:8px; font-size:12px; color:#ef4444; font-weight:600;">${(vol / med).toFixed(1)}× acima da mediana</div>`
          : '';
        return `
          <div style="color:${c.tooltipText}; min-width:190px;">
            <div style="font-weight:700; font-size:14px; margin-bottom:10px;">${hora}</div>
            <div style="display:flex; flex-direction:column; gap:8px;">
              <div style="display:flex; justify-content:space-between; align-items:center;">
                <span style="display:flex;align-items:center;gap:6px;">
                  <span style="width:10px;height:10px;border-radius:2px;background:#ef4444;display:inline-block;"></span>
                  <span style="font-size:11px; opacity:.6; text-transform:uppercase;">Volume</span>
                </span>
                <span style="font-weight:700; font-size:13px;">${vol} <small>presc.</small></span>
              </div>
              <div style="display:flex; justify-content:space-between; align-items:center;">
                <span style="display:flex;align-items:center;gap:6px;">
                  <span style="width:10px;height:10px;border-radius:2px;background:#6366f1;display:inline-block;"></span>
                  <span style="font-size:11px; opacity:.6; text-transform:uppercase;">CRMs Distintos</span>
                </span>
                <span style="font-weight:700; font-size:13px;">${crms} <small>médicos</small></span>
              </div>
              <div style="border-top:1px solid ${c.tooltipBorder}; padding-top:8px; margin-top:2px; display:flex; justify-content:space-between; align-items:center;">
                <span style="font-size:11px; opacity:.6; text-transform:uppercase;">Mediana Mensal</span>
                <span style="font-weight:600; font-size:12px; color:#f59e0b;">${med.toFixed(1)}</span>
              </div>
            </div>
            ${alertaHtml}
          </div>`;
      },
    },

    series: [
      {
        name: 'Prescrições (Volume)',
        type: 'bar',
        barMaxWidth: 28,
        data: fullPoints.map((p, i) => ({ value: p.nu_prescricoes, itemStyle: { color: barColors[i] } })),
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
      }
    ]
  };
});

// isRefreshing: há dados anteriores visíveis enquanto um novo fetch está em curso
const isRefreshing = computed(() => prescritoresLoading.value && prescritoresData.value !== null);

// --- CÁLCULOS DOS KPIs ---
const summary = computed(() => prescritoresData.value?.summary || {});
const crmsInteresse = computed(() => prescritoresData.value?.crms_interesse || []);

const concentracaoTop1 = computed(
  () => summary.value.pct_concentracao_top1 || 0,
);
const concentracaoTop5 = computed(
  () => summary.value.pct_concentracao_top5 || 0,
);

const valorTop1 = computed(() =>
  crmsInteresse.value.length > 0 ? crmsInteresse.value[0].vl_total_prescricoes || 0 : 0,
);
const valorTop5 = computed(() =>
  crmsInteresse.value
    .slice(0, 5)
    .reduce((acc, curr) => acc + (curr.vl_total_prescricoes || 0), 0),
);

// Prescrição Intensiva (Robôs)
const qtdPrescrIntensivaLocal = computed(
  () =>
    summary.value.qtd_prescritores_robos ||
    crmsInteresse.value.filter((m) => m.flag_robo > 0).length,
);
const qtdPrescrIntensivaOcultos = computed(
  () =>
    summary.value.qtd_prescritores_robos_ocultos ||
    crmsInteresse.value.filter((m) => m.flag_robo_oculto > 0).length,
);

// CRMs Inválidos e Irregulares
const qtdCrmInvalido = computed(
  () =>
    summary.value.qtd_crm_invalido ??
    crmsInteresse.value.filter((m) => m.flag_crm_invalido > 0).length,
);
const qtdPrescrAntesRegistro = computed(
  () =>
    summary.value.qtd_crm_antes_registro ??
    crmsInteresse.value.filter((m) => m.flag_prescricao_antes_registro > 0).length,
);
const totalIrregularesCfm = computed(
  () => qtdCrmInvalido.value + qtdPrescrAntesRegistro.value,
);
const pctFraudeCrm = computed(
  () =>
    (summary.value.pct_valor_crm_invalido || 0) +
    (summary.value.pct_valor_crm_antes_registro || 0),
);
const valorFraudeCrm = computed(
  () =>
    (summary.value.vl_crm_invalido || 0) +
    (summary.value.vl_crm_antes_registro || 0),
);

// CRMs Exclusivos (Atua em 1 único estabelecimento no Brasil)
const qtdCrmExclusivo = computed(
  () => crmsInteresse.value.filter((m) => m.flag_crm_exclusivo > 0).length,
);

const qtdLancamentosAgrupados = computed(
  () =>
    summary.value.qtd_prescritores_conc_temporal ||
    crmsInteresse.value.filter((m) => m.alerta2_tempo_concentrado || m.alerta2).length,
);

const qtdAcima400km = computed(
  () => crmsInteresse.value.filter((m) => m.alerta5_geografico).length,
);

const formatPct = (val) =>
  val != null ? `${Number(val).toFixed(2)}%` : "0.00%";

const expandedAlertasMedico = ref(new Set());
function toggleAlertasDiarios(idMedico) {
  if (expandedAlertasMedico.value.has(idMedico)) {
    expandedAlertasMedico.value.delete(idMedico);
  } else {
    expandedAlertasMedico.value.add(idMedico);
  }
  expandedAlertasMedico.value = new Set(expandedAlertasMedico.value);
}
function formatarDataAlerta(dt) {
  if (!dt) return "";
  const [y, m, d] = dt.split("-");
  return `${d}/${m}/${y}`;
}
function formatarJanela(minutos) {
  if (!minutos) return "—";
  if (minutos === 0) return "simultâneo";
  if (minutos < 60) return `${minutos}min`;
  return `${Math.floor(minutos / 60)}h ${minutos % 60}min`;
}

const filterOnlyIssues = ref(false);
const activeKpiFilter = ref(null);

const kpiFilters = {
  top1: (m) => m.id_medico === crmsInteresse.value[0]?.id_medico,
  top5: (m) => crmsInteresse.value.slice(0, 5).some((t) => t.id_medico === m.id_medico),
  agrupamento: (m) => !!(m.alerta2_tempo_concentrado || m.alerta2),
  intensiva_local: (m) => m.flag_robo > 0,
  intensiva_brasil: (m) => m.flag_robo_oculto > 0,
  exclusivo: (m) => m.flag_crm_exclusivo > 0,
  fraude_crm: (m) =>
    m.flag_crm_invalido > 0 || m.flag_prescricao_antes_registro > 0,
  distancia: (m) => !!m.alerta5_geografico,
};

const kpiFilterLabels = {
  top1: "Concentração TOP 1",
  top5: "Concentração TOP 5",
  agrupamento: "Lançamentos em Sequência",
  intensiva_local: ">30 Prescrições/Dia neste CNPJ",
  intensiva_brasil: ">30 Prescrições/Dia Brasil",
  exclusivo: "CRM Exclusivo",
  fraude_crm: "Fraudes CRM",
  distancia: "Distância (>400km)",
};

function setKpiFilter(key) {
  if (activeKpiFilter.value === key) {
    activeKpiFilter.value = null;
  } else {
    activeKpiFilter.value = key;
    filterOnlyIssues.value = false;
  }
}

function clearFilters() {
  activeKpiFilter.value = null;
  filterOnlyIssues.value = false;
}

const hasAnyIssue = (m) =>
  m.flag_robo > 0 ||
  m.flag_robo_oculto > 0 ||
  m.alerta2_tempo_concentrado ||
  m.alerta2 ||
  m.flag_crm_invalido > 0 ||
  m.flag_prescricao_antes_registro > 0 ||
  m.alerta5_geografico ||
  m.flag_crm_exclusivo > 0;

const filteredCrmsInteresse = computed(() => {
  let list = crmsInteresse.value;
  if (filterOnlyIssues.value) list = list.filter(hasAnyIssue);
  if (activeKpiFilter.value && kpiFilters[activeKpiFilter.value]) {
    list = list.filter(kpiFilters[activeKpiFilter.value]);
  }
  return list;
});

const showAllCrms = ref(false);
const visibleCrms = computed(() =>
  showAllCrms.value ? filteredCrmsInteresse.value : filteredCrmsInteresse.value.slice(0, 10)
);

defineExpose({
  getSummary: () => summary.value,
  getCrmsInteresse: () => crmsInteresse.value,
  getKpis: () => ({
    concentracaoTop1: concentracaoTop1.value,
    concentracaoTop5: concentracaoTop5.value,
    qtdLancamentosAgrupados: qtdLancamentosAgrupados.value,
    qtdPrescrIntensivaLocal: qtdPrescrIntensivaLocal.value,
    qtdPrescrIntensivaOcultos: qtdPrescrIntensivaOcultos.value,
    qtdCrmExclusivo: qtdCrmExclusivo.value,
    totalIrregularesCfm: totalIrregularesCfm.value,
    qtdCrmInvalido: qtdCrmInvalido.value,
    qtdPrescrAntesRegistro: qtdPrescrAntesRegistro.value,
    valorTop1: valorTop1.value,
    valorTop5: valorTop5.value,
    medianaTop5Reg:
      summary.value.mediana_concentracao_top5_reg ??
      summary.value.mediana_concentracao_top5_br ??
      40,
    qtdAcima400km: qtdAcima400km.value,
  }),
});
</script>

<template>
  <div class="crm-tab-container">
    <div v-if="prescritoresLoading && !prescritoresData" class="loading-state">
      <i class="pi pi-spinner pi-spin"></i>
      <p>Carregando análise de prescritores...</p>
    </div>

    <div v-else-if="prescritoresError && !prescritoresData" class="loading-state tab-placeholder--error">
      <i class="pi pi-exclamation-circle" style="font-size: 2rem"></i>
      <p>{{ prescritoresError }}</p>
    </div>

    <div
      v-else-if="!prescritoresData || crmsInteresse.length === 0"
      class="empty-state"
    >
      <i class="pi pi-users empty-icon"></i>
      <p>
        Não há dados de prescrições registrados para este estabelecimento nos
        meses selecionados.
      </p>
    </div>

    <div v-else class="content-wrapper" :class="{ 'is-refreshing': isRefreshing }">
      <!-- 1. KPIs -->
      <div class="no-padding-mobile">
        <div class="alerts-kpi-grid">
          <!-- Concentração TOP 1 -->
          <div
            class="alert-kpi-card"
            :class="[
              concentracaoTop1 > 40
                ? 'highlight-red'
                : concentracaoTop1 > 20
                  ? 'highlight-orange'
                  : '',
              activeKpiFilter === 'top1' ? 'kpi-active' : '',
            ]"
            @click="setKpiFilter('top1')"
          >
            <div class="alert-kpi-header">
              <span class="alert-kpi-label">TOP 1 CRM - VOLUME R$</span>
              <i
                class="pi pi-info-circle kpi-info-icon"
                v-tooltip.top="
                  'Percentual de participação do maior prescritor no volume total da farmácia.'
                "
              />
            </div>
            <div class="alert-kpi-body">
              <span class="alert-kpi-val">{{
                formatPct(concentracaoTop1)
              }}</span>
              <span class="alert-kpi-hint">
                CRM: {{ summary.id_top1_prescritor || "ND" }}
                <strong style="color: var(--text-color)">
                  · {{ formatCurrencyFull(valorTop1) }}</strong
                >
              </span>
            </div>
          </div>

          <!-- Concentração TOP 5 -->
          <div
            class="alert-kpi-card"
            :class="[
              concentracaoTop5 > 70
                ? 'highlight-red'
                : concentracaoTop5 > 50
                  ? 'highlight-orange'
                  : '',
              activeKpiFilter === 'top5' ? 'kpi-active' : '',
            ]"
            @click="setKpiFilter('top5')"
          >
            <div class="alert-kpi-header">
              <span class="alert-kpi-label">TOP 5 CRMs - VOLUME R$</span>
              <i
                class="pi pi-info-circle kpi-info-icon"
                v-tooltip.top="
                  'Percentual de participação dos 5 maiores prescritores acumulados.'
                "
              />
            </div>
            <div class="alert-kpi-body">
              <span class="alert-kpi-val">{{
                formatPct(concentracaoTop5)
              }}</span>
              <span class="alert-kpi-hint">
                Mediana Região:
                {{
                  formatPct(
                    summary.mediana_concentracao_top5_reg ||
                      summary.mediana_concentracao_top5_br ||
                      40,
                  )
                }}
                <strong style="color: var(--text-color)">
                  · {{ formatCurrencyFull(valorTop5) }}</strong
                >
              </span>
            </div>
          </div>

          <!-- Agrupamento de Lançamentos -->
          <div
            class="alert-kpi-card"
            :class="[
              qtdLancamentosAgrupados > 0 ? 'highlight-green' : 'kpi-disabled',
              activeKpiFilter === 'agrupamento' ? 'kpi-active' : '',
            ]"
            @click="setKpiFilter('agrupamento')"
          >
            <div class="alert-kpi-header">
              <span class="alert-kpi-label">LANÇAMENTOS EM SEQUENCIA</span>
              <i
                class="pi pi-info-circle kpi-info-icon"
                v-tooltip.top="
                  'Médicos que emitiram todas as suas prescrições em um curtíssimo espaço de tempo.'
                "
              />
            </div>
            <div class="alert-kpi-body">
              <span class="alert-kpi-val">{{ qtdLancamentosAgrupados }}</span>
              <span class="alert-kpi-hint"
                >Muitas Autorizações em Intervalo Curto</span
              >
            </div>
          </div>

          <!-- Prescrição Intensiva Local -->
          <div
            class="alert-kpi-card"
            :class="[
              qtdPrescrIntensivaLocal > 0 ? 'highlight-red' : 'kpi-disabled',
              activeKpiFilter === 'intensiva_local' ? 'kpi-active' : '',
            ]"
            @click="setKpiFilter('intensiva_local')"
          >
            <div class="alert-kpi-header">
              <span class="alert-kpi-label"
                >>30 PRESCRIÇÕES/DIA NESTE CNPJ</span
              >
              <i
                class="pi pi-info-circle kpi-info-icon"
                v-tooltip.top="
                  'Médicos que emitiram mais de 30 prescrições por dia considerando apenas as vendas desta unidade.'
                "
              />
            </div>
            <div class="alert-kpi-body">
              <span class="alert-kpi-val">{{ qtdPrescrIntensivaLocal }}</span>
              <span class="alert-kpi-hint">Na unidade local</span>
            </div>
          </div>

          <!-- Prescrição Intensiva Rede -->
          <div
            class="alert-kpi-card"
            :class="[
              qtdPrescrIntensivaOcultos > 0 ? 'highlight-orange' : 'kpi-disabled',
              activeKpiFilter === 'intensiva_brasil' ? 'kpi-active' : '',
            ]"
            @click="setKpiFilter('intensiva_brasil')"
          >
            <div class="alert-kpi-header">
              <span class="alert-kpi-label">>30 PRESCRIÇÕES/DIA BRASIL</span>
              <i
                class="pi pi-info-circle kpi-info-icon"
                v-tooltip.top="
                  'Médicos atuando com volume aceitável aqui, mas que emitem mais de 30 prescrições/dia se somadas todas as farmácias do Brasil (Robô Oculto).'
                "
              />
            </div>
            <div class="alert-kpi-body">
              <span class="alert-kpi-val">{{ qtdPrescrIntensivaOcultos }}</span>
              <span class="alert-kpi-hint">Soma de todo o Brasil</span>
            </div>
          </div>

          <!-- CRMs Exclusivos -->
          <div
            class="alert-kpi-card"
            :class="[
              qtdCrmExclusivo > 0 ? 'highlight-purple' : 'kpi-disabled',
              activeKpiFilter === 'exclusivo' ? 'kpi-active' : '',
            ]"
            @click="setKpiFilter('exclusivo')"
          >
            <div class="alert-kpi-header">
              <span class="alert-kpi-label">CRMs EXCLUSIVOS</span>
              <i
                class="pi pi-info-circle kpi-info-icon"
                v-tooltip.top="
                  'Médicos de gaveta: prescrevem exclusivamente para este estabelecimento em todo o Brasil.'
                "
              />
            </div>
            <div class="alert-kpi-body">
              <span class="alert-kpi-val">{{ qtdCrmExclusivo }}</span>
              <span class="alert-kpi-hint">100% de exclusividade local</span>
            </div>
          </div>

          <!-- Fraudes CRM -->
          <div
            class="alert-kpi-card"
            :class="[
              totalIrregularesCfm > 0 ? 'highlight-red highlight-fraude' : 'kpi-disabled',
              activeKpiFilter === 'fraude_crm' ? 'kpi-active' : '',
            ]"
            @click="setKpiFilter('fraude_crm')"
          >
            <div class="alert-kpi-header">
              <span class="alert-kpi-label">FRAUDES CRM</span>
              <i
                class="pi pi-info-circle kpi-info-icon"
                v-tooltip.top="
                  'Fonte: CFM. CRMs inexistentes ou vendas antes do registro oficial.'
                "
              />
            </div>
            <div class="alert-kpi-body">
              <div class="alert-kpi-val-row">
                <span class="alert-kpi-val">{{ totalIrregularesCfm }}</span>
                <span class="alert-kpi-val-sub"
                  >{{ qtdCrmInvalido }} Inexistentes |
                  {{ qtdPrescrAntesRegistro }} Irregulares</span
                >
              </div>
              <span class="alert-kpi-hint">
                <strong style="color: var(--risk-high)">
                  {{ formatCurrencyFull(valorFraudeCrm) }} ({{
                    formatPct(pctFraudeCrm)
                  }})
                </strong>
                da produção
              </span>
            </div>
          </div>

          <!-- Alerta >400km -->
          <div
            class="alert-kpi-card"
            :class="[
              qtdAcima400km > 0 ? 'highlight-purple-geo' : 'kpi-disabled',
              activeKpiFilter === 'distancia' ? 'kpi-active' : '',
            ]"
            @click="setKpiFilter('distancia')"
          >
            <div class="alert-kpi-header">
              <span class="alert-kpi-label">DISTÂNCIA (>400KM)</span>
              <i
                class="pi pi-info-circle kpi-info-icon"
                v-tooltip.top="
                  'Médicos atuando em farmácias com mais de 400km de distância.'
                "
              />
            </div>
            <div class="alert-kpi-body">
              <span class="alert-kpi-val">{{ qtdAcima400km }}</span>
              <span class="alert-kpi-hint"
                >Prescrições em Locais Distantes</span
              >
            </div>
          </div>
        </div>
      </div>

      <!-- 2. GRÁFICO — PERFIL DIÁRIO DE DISPENSAÇÕES -->
      <div class="section-container daily-chart-section">
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
          Evolução diária de autorizações. Dias com volume anômalo (acima de 4× a mediana e ≥ 20 prescrições) destacados em vermelho.
        </p>
        <div v-if="!crmDailyProfile && !crmDailyProfileLoading" class="chart-empty">
          <i class="pi pi-chart-bar" style="font-size:1.5rem; opacity:.4"></i>
          <span>Sem dados de perfil diário disponíveis.</span>
        </div>
        <VChart
          v-else
          :option="chartOptionDaily"
          :update-options="{ notMerge: true }"
          autoresize
          class="daily-dispensacao-chart"
          @click="onChartClick"
        />

        <!-- Detalhamento Horário (Drill-down) -->
        <div v-if="selectedDay" class="hourly-detail-wrapper animate-fade-in">
          <div class="hourly-header">
            <div class="hourly-title">
              <i class="pi pi-clock" />
              <span>Análise Horária: {{ formatarData(selectedDay.dt_janela) }}</span>
              <span class="anomalo-badge">DIA ANÔMALO</span>
            </div>
            <button class="close-detail-btn" @click="selectedDay = null">
              <i class="pi pi-times" />
            </button>
          </div>
          
          <div v-if="crmHourlyProfileLoading" class="hourly-loading">
            <i class="pi pi-spinner pi-spin"></i>
            <span>Buscando registros horários...</span>
          </div>
          <div v-else class="hourly-body">
            <p class="hourly-subtitle">
              Distribuição das <strong>{{ selectedDay.nu_prescricoes_dia }} prescrições</strong> ao longo do dia,
              comparando o volume real com a mediana de cada horário.
            </p>
            <VChart
              :option="chartOptionHourly"
              autoresize
              class="hourly-chart"
            />
          </div>
        </div>
      </div>

      <!-- 3. TOP 20 CRMs (TABELA DETALHADA) -->
      <div class="section-container">
        <div
          class="section-title"
          style="border-bottom: none; margin-bottom: 0"
        >
          <div
            style="display: flex; align-items: center; gap: 1.5rem; width: 100%"
          >
            <div style="display: flex; align-items: center; gap: 0.75rem">
              <i class="pi pi-users" />
              <span>CRMs DE INTERESSE - DETALHAMENTO</span>
            </div>

            <div class="filter-controls">
              <label class="filter-toggle">
                <input type="checkbox" v-model="filterOnlyIssues" />
                <span class="toggle-slider"></span>
                <span class="toggle-label">Apenas com Alertas / Anomalias</span>
              </label>
            </div>
          </div>
        </div>
        <p
          class="subtitle"
          style="
            padding-left: 1.75rem;
            margin-top: -0.5rem;
            margin-bottom: 1rem;
          "
        >
          Detalhamento dos médicos que mais aprovaram medicamentos nesta
          unidade, ordenados pelo financeiro.
          <span v-if="activeKpiFilter" class="filter-badge">
            <i class="pi pi-filter-fill"></i>
            {{ kpiFilterLabels[activeKpiFilter] }} —
            {{ filteredCrmsInteresse.length }} de {{ crmsInteresse.length }}
            <button class="clear-filter-btn" @click.stop="clearFilters">
              <i class="pi pi-times"></i> Limpar filtro
            </button>
          </span>
          <span
            v-else-if="filterOnlyIssues && filteredCrmsInteresse.length < crmsInteresse.length"
            class="text-orange"
            style="font-weight: 600; margin-left: 8px"
          >
            (Filtrado: exibindo {{ filteredCrmsInteresse.length }} de
            {{ crmsInteresse.length }})
          </span>
        </p>

        <div class="table-responsive">
          <table class="ind-table premium-table row-hover">
            <thead class="sticky-thead">
              <tr>
                <th>CRM / Médico</th>
                <th>Status / Alertas</th>
                <th class="col-right">Qtd. Total</th>
                <th class="col-right">Valor Total</th>
                <th class="col-center">% Vendas</th>
                <th class="col-center">% Acum.</th>
                <th class="col-center">Rede (Network)</th>
                <th class="col-center">Presc/Dia (Local)</th>
                <th class="col-center">Presc/Dia (Brasil)</th>
                <th class="col-center">% Exclusividade</th>
              </tr>
            </thead>
            <tbody>
              <template
                v-for="(m, i) in visibleCrms"
                :key="i"
              >
              <tr>
                <td>
                  <div class="med-id">{{ m.id_medico }}</div>
                  <div class="med-sub">
                    Registro:
                    {{
                      m.dt_inscricao_crm
                        ? formatarData(m.dt_inscricao_crm)
                        : "ND"
                    }}
                  </div>
                </td>
                <td class="flags-cell">
                  <div class="tags-container">
                    <span v-if="m.flag_robo" class="issue-tag red" v-tooltip.top="'>30 Prescrições/dia neste CNPJ'">
                      <i class="pi pi-history"></i> >30 Presc/dia (Local)
                    </span>
                    <span v-if="m.flag_robo_oculto && !m.flag_robo" class="issue-tag orange" v-tooltip.top="'>30 Prescrições/dia em todo o Brasil (Robô Oculto)'">
                      <i class="pi pi-globe"></i> >30 Presc/dia BR
                    </span>
                    <span
                      v-if="m.alerta2_tempo_concentrado || m.alerta2"
                      class="issue-tag green-ok clickable-badge"
                      v-tooltip.top="expandedAlertasMedico.has(m.id_medico) ? 'Recolher detalhes' : 'Ver episódios detalhados'"
                      @click.stop="toggleAlertasDiarios(m.id_medico)"
                    >
                      <i class="pi pi-stopwatch"></i> Sequencial
                      <span v-if="m.alertas_diarios?.length > 1" class="badge-count">
                        ({{ m.alertas_diarios.length }}x)
                      </span>
                      <i :class="expandedAlertasMedico.has(m.id_medico) ? 'pi pi-chevron-up' : 'pi pi-chevron-down'" style="font-size:0.6rem; margin-left:0.2rem;" />
                    </span>
                    <span v-if="m.flag_crm_invalido" class="issue-tag dark-red" v-tooltip.top="'CRM não encontrado na base de dados oficial do Conselho Federal de Medicina (CFM)'">
                      <i class="pi pi-ban"></i> CRM Inexistente
                    </span>
                    <span v-if="m.flag_prescricao_antes_registro" class="issue-tag dark-red" v-tooltip.top="'Venda anterior ao Registro oficial no CFM'">
                      <i class="pi pi-calendar-times"></i> CRM Irregular
                    </span>
                    <span v-if="m.flag_crm_exclusivo > 0" class="issue-tag orange" v-tooltip.top="'Médico prescreveu exclusivamente para este CNPJ no total do Brasil'">
                      <i class="pi pi-lock"></i> CRM Exclusivo
                    </span>
                    <span v-if="m.alerta5_geografico" class="issue-tag purple-geo" v-tooltip.top="'Distância superior a 400km entre prescritor e farmácia'">
                      <i class="pi pi-map-marker"></i> >400km
                    </span>
                    <i
                      v-if="
                        !m.flag_robo &&
                        !m.flag_robo_oculto &&
                        !m.flag_crm_invalido &&
                        !m.flag_prescricao_antes_registro &&
                        !m.alerta5_geografico &&
                        (!m.flag_crm_exclusivo || m.flag_crm_exclusivo === 0)
                      "
                      class="pi pi-check-circle"
                      style="color: var(--text-muted); font-size: 0.85rem;"
                      v-tooltip.top="'Sem ocorrências identificadas'"
                    />
                  </div>
                </td>
                <td class="col-right">
                  {{ formatNumberFull(m.nu_prescricoes) }}
                </td>
                <td class="col-right text-primary">
                  {{ formatCurrencyFull(m.vl_total_prescricoes) }}
                </td>
                <td class="col-center">
                  <div class="bar-container">
                    <div
                      class="bar-fill"
                      :style="{
                        width: Math.min(m.pct_participacao, 100) + '%',
                      }"
                    ></div>
                    <span class="bar-text">{{
                      formatPct(m.pct_participacao)
                    }}</span>
                  </div>
                </td>
                <td class="col-center">
                  <div class="bar-container">
                    <div
                      class="bar-fill"
                      :style="{
                        width: Math.min(m.pct_acumulado, 100) + '%',
                      }"
                    ></div>
                    <span class="bar-text text-sm">{{
                      formatPct(m.pct_acumulado)
                    }}</span>
                  </div>
                </td>
                <td class="col-center">
                  <span
                    :class="{
                      'text-purple': m.qtd_estabelecimentos_atua > 50,
                    }"
                    >{{ m.qtd_estabelecimentos_atua }}</span
                  >
                  farm.
                </td>
                <td class="col-center">
                  <span
                    :class="{ 'text-red': m.nu_prescricoes_dia > 30 }"
                    >{{ formatNumberFull(m.nu_prescricoes_dia) }}</span
                  >/dia
                </td>
                <td class="col-center">
                  <span
                    :class="{
                      'text-red': m.prescricoes_dia_total_brasil > 30,
                    }"
                    >{{
                      formatNumberFull(m.prescricoes_dia_total_brasil)
                    }}</span
                  >/dia
                </td>
                <td class="col-center">
                  <span
                    :class="{
                      'text-purple': m.pct_volume_aqui_vs_total > 90,
                    }"
                    >{{ formatPct(m.pct_volume_aqui_vs_total) }}</span
                  >
                </td>
              </tr>
              <tr
                v-if="expandedAlertasMedico.has(m.id_medico) && m.alertas_diarios?.length"
                class="alertas-diarios-row"
              >
                <td colspan="10" class="alertas-diarios-cell">
                  <table class="alertas-diarios-table">
                    <thead>
                      <tr>
                        <th>Data</th>
                        <th>Nível</th>
                        <th>Prescrições</th>
                        <th>Janela</th>
                        <th>Taxa/hora</th>
                        <th>Descrição</th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr v-for="(a, j) in m.alertas_diarios" :key="j" class="alerta-diario-item">
                        <td class="col-date">{{ formatarDataAlerta(a.dt) }}</td>
                        <td><span class="nivel-badge" :class="`nivel-${a.nivel?.toLowerCase().replace(' ', '-')}`">{{ a.nivel }}</span></td>
                        <td class="col-right">{{ a.nu_prescricoes }}</td>
                        <td class="col-center">{{ formatarJanela(a.nu_minutos) }}</td>
                        <td class="col-right">{{ a.taxa_hora?.toFixed(1) }}/h</td>
                        <td class="col-descricao">{{ a.descricao }}</td>
                      </tr>
                    </tbody>
                  </table>
                </td>
              </tr>
              </template>
            </tbody>
          </table>
        </div>

        <div class="crm-table-footer">
          <button
            v-if="filteredCrmsInteresse.length > 10"
            class="crm-more-btn"
            @click="showAllCrms = !showAllCrms"
          >
            <template v-if="!showAllCrms">
              <i class="pi pi-angle-double-down" />
              Exibir mais {{ filteredCrmsInteresse.length - 10 }} registros
            </template>
            <template v-else>
              <i class="pi pi-angle-double-up" />
              Recolher
            </template>
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.crm-tab-container {
  display: flex;
  flex-direction: column;
  gap: 1.5rem;
}

.loading-state,
.empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 4rem 1rem;
  color: var(--text-muted);
  background: var(--surface-bg);
  border-radius: 12px;
  border: 1px dashed var(--border-color);
}
.daily-dispensacao-chart {
  height: 280px;
  cursor: pointer;
}

/* Hourly Detail Styles */
.hourly-detail-wrapper {
  margin-top: 1.5rem;
  padding: 1.25rem;
  background: var(--surface-card);
  border: 1px solid var(--border-color);
  border-left: 4px solid #ef4444;
  border-radius: 8px;
  box-shadow: 0 4px 12px rgba(0,0,0,0.05);
}

.hourly-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 1rem;
}

.hourly-title {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  font-weight: 600;
  color: var(--text-color);
}

.anomalo-badge {
  background: #fee2e2;
  color: #b91c1c;
  font-size: 0.7rem;
  padding: 2px 8px;
  border-radius: 99px;
  letter-spacing: 0.5px;
}

.close-detail-btn {
  background: none;
  border: none;
  color: var(--text-muted);
  cursor: pointer;
  padding: 4px;
  border-radius: 4px;
  transition: all 0.2s;
}
.close-detail-btn:hover {
  background: var(--surface-hover);
  color: #ef4444;
}

.hourly-subtitle {
  font-size: 0.9rem;
  color: var(--text-muted);
  margin-bottom: 1rem;
  line-height: 1.4;
}

.hourly-chart {
  height: 240px;
}

.hourly-loading {
  height: 200px;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 0.75rem;
  color: var(--text-muted);
}

.animate-fade-in {
  animation: fadeIn 0.3s ease-out;
}

@keyframes fadeIn {
  from { opacity: 0; transform: translateY(10px); }
  to { opacity: 1; transform: translateY(0); }
}

.empty-icon {
  font-size: 3rem;
  margin-bottom: 1rem;
  opacity: 0.5;
}
.loading-state i {
  font-size: 2rem;
  margin-bottom: 1rem;
  color: var(--primary-color);
}

.content-wrapper {
  display: flex;
  flex-direction: column;
  gap: 1.25rem;
  width: 100%;
  align-items: stretch;
  transition: opacity 0.25s ease;
}

.content-wrapper.is-refreshing {
  opacity: 0.45;
  pointer-events: none;
}

.crm-table-footer {
  background: var(--card-bg);
  border-bottom: 1px solid color-mix(in srgb, var(--card-border) 60%, transparent);
  display: flex;
  justify-content: center;
  padding: 0.35rem 0;
}

.crm-more-btn {
  background: none;
  border: none;
  font-size: 0.65rem;
  font-weight: 500;
  color: var(--primary-color);
  text-transform: uppercase;
  letter-spacing: 0.05em;
  cursor: pointer;
  display: inline-flex;
  align-items: center;
  gap: 0.4rem;
  padding: 0.2rem 1rem;
  border-radius: 4px;
  transition: all 0.2s;
  opacity: 0.85;
}

.crm-more-btn:hover {
  opacity: 1;
  background: color-mix(in srgb, var(--primary-color) 8%, transparent);
  letter-spacing: 0.08em;
}

.crm-more-btn i {
  font-size: 0.7rem;
}

.no-padding-mobile {
  border: none !important;
  background: transparent !important;
  padding: 0 !important;
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

.section-title i {
  color: var(--primary-color);
  font-size: 1rem;
}

.alerts-kpi-grid {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 1rem;
  margin-bottom: 0;
}

.alert-kpi-card {
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
  padding: 0.9rem 1.1rem;
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  border-left: 4px solid var(--card-border);
  border-radius: 12px;
  transition: all 0.2s ease;
  cursor: pointer;
  user-select: none;
}

.alert-kpi-card:hover {
  transform: translateY(-2px);
  box-shadow: 0 4px 15px rgba(0, 0, 0, 0.08);
}

/* Hovers específicos por categoria */
.alert-kpi-card.highlight-red:hover {
  border-color: color-mix(in srgb, var(--risk-high) 45%, var(--card-border));
  box-shadow: 0 8px 16px -8px color-mix(in srgb, var(--risk-high) 20%, transparent);
}
.alert-kpi-card.highlight-orange:hover {
  border-color: color-mix(in srgb, var(--risk-medium) 45%, var(--card-border));
  box-shadow: 0 8px 16px -8px color-mix(in srgb, var(--risk-medium) 20%, transparent);
}
.alert-kpi-card.highlight-green:hover {
  border-color: color-mix(in srgb, var(--risk-indicator-normal) 45%, var(--card-border));
  box-shadow: 0 8px 16px -8px color-mix(in srgb, var(--risk-indicator-normal) 20%, transparent);
}
.alert-kpi-card.highlight-purple:hover {
  border-color: color-mix(in srgb, #3b82f6 45%, var(--card-border));
  box-shadow: 0 8px 16px -8px color-mix(in srgb, #3b82f6 20%, transparent);
}
.alert-kpi-card.highlight-purple-geo:hover {
  border-color: color-mix(in srgb, #8b5cf6 45%, var(--card-border));
  box-shadow: 0 8px 16px -8px color-mix(in srgb, #8b5cf6 20%, transparent);
}

/* Card desabilitado — valor zero, sem interação */
.alert-kpi-card.kpi-disabled {
  cursor: default;
  pointer-events: none;
  opacity: 0.45;
}

/* Estado ativo (Clicado) — Sincronizado com a cor da categoria */
.alert-kpi-card.kpi-active {
  transform: translateY(-1px);
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
}

.alert-kpi-card.highlight-red.kpi-active {
  background: linear-gradient(to top, color-mix(in srgb, var(--risk-high) 25%, var(--card-bg)) 0%, color-mix(in srgb, var(--risk-high) 5%, var(--card-bg)) 100%);
  border-color: color-mix(in srgb, var(--risk-high) 50%, transparent) !important;
}
.alert-kpi-card.highlight-orange.kpi-active {
  background: linear-gradient(to top, color-mix(in srgb, var(--risk-medium) 25%, var(--card-bg)) 0%, color-mix(in srgb, var(--risk-medium) 5%, var(--card-bg)) 100%);
  border-color: color-mix(in srgb, var(--risk-medium) 50%, transparent) !important;
}
.alert-kpi-card.highlight-green.kpi-active {
  background: linear-gradient(to top, color-mix(in srgb, var(--risk-indicator-normal) 25%, var(--card-bg)) 0%, color-mix(in srgb, var(--risk-indicator-normal) 5%, var(--card-bg)) 100%);
  border-color: color-mix(in srgb, var(--risk-indicator-normal) 50%, transparent) !important;
}
.alert-kpi-card.highlight-purple.kpi-active {
  background: linear-gradient(to top, color-mix(in srgb, #3b82f6 25%, var(--card-bg)) 0%, color-mix(in srgb, #3b82f6 5%, var(--card-bg)) 100%);
  border-color: color-mix(in srgb, #3b82f6 50%, transparent) !important;
}
.alert-kpi-card.highlight-purple-geo.kpi-active {
  background: linear-gradient(to top, color-mix(in srgb, #8b5cf6 25%, var(--card-bg)) 0%, color-mix(in srgb, #8b5cf6 5%, var(--card-bg)) 100%);
  border-color: color-mix(in srgb, #8b5cf6 50%, transparent) !important;
}

.filter-badge {
  display: inline-flex;
  align-items: center;
  gap: 0.4rem;
  font-size: 0.78rem;
  font-weight: 600;
  color: var(--primary-color);
  margin-left: 0.5rem;
}

.filter-badge i {
  font-size: 0.75rem;
}

.clear-filter-btn {
  display: inline-flex;
  align-items: center;
  gap: 0.25rem;
  margin-left: 0.25rem;
  padding: 0.15rem 0.5rem;
  font-size: 0.72rem;
  font-weight: 600;
  color: var(--text-secondary);
  background: color-mix(in srgb, var(--text-color) 6%, var(--tabs-bg));
  border: 1px solid var(--tabs-border);
  border-radius: 4px;
  cursor: pointer;
  transition: all 0.15s ease;
}

.clear-filter-btn:hover {
  background: color-mix(in srgb, var(--text-color) 12%, var(--tabs-bg));
  color: var(--text-color);
}

.alert-kpi-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.alert-kpi-label {
  font-size: 0.7rem;
  font-weight: 600;
  color: var(--text-secondary);
  text-transform: uppercase;
  letter-spacing: 0.05em;
  opacity: 0.85;
}

.kpi-info-icon {
  font-size: 0.8rem;
  color: var(--text-muted);
  cursor: help;
  transition: color 0.15s;
}

.kpi-info-icon:hover {
  color: var(--primary-color);
}

.alert-kpi-body {
  display: flex;
  flex-direction: column;
  gap: 0.2rem;
}

.alert-kpi-val-row {
  display: flex;
  align-items: baseline;
  gap: 0.5rem;
}

.alert-kpi-val {
  font-size: 1.15rem;
  font-weight: 600;
  color: var(--text-color);
  line-height: 1;
}

.alert-kpi-val-sub {
  font-size: 0.7rem;
  font-weight: 500;
  color: var(--text-color);
  opacity: 0.85;
}

.alert-kpi-hint {
  font-size: 0.72rem;
  color: var(--text-muted);
  font-weight: 400;
}

/* Semafórica de Risco nos Cards */
.highlight-red {
  background: linear-gradient(to top, color-mix(in srgb, var(--risk-high) 15%, var(--card-bg)) 0%, var(--card-bg) 80%);
  border: 1px solid color-mix(in srgb, var(--risk-high) 15%, var(--card-border));
  border-left: none;
  border-bottom: 3px solid color-mix(in srgb, var(--risk-high) 65%, transparent) !important;
}

.highlight-orange {
  background: linear-gradient(to top, color-mix(in srgb, var(--risk-medium) 15%, var(--card-bg)) 0%, var(--card-bg) 80%);
  border: 1px solid color-mix(in srgb, var(--risk-medium) 15%, var(--card-border));
  border-left: none;
  border-bottom: 3px solid color-mix(in srgb, var(--risk-medium) 65%, transparent) !important;
}

.highlight-purple {
  background: linear-gradient(to top, color-mix(in srgb, #3b82f6 15%, var(--card-bg)) 0%, var(--card-bg) 80%);
  border: 1px solid color-mix(in srgb, #3b82f6 15%, var(--card-border));
  border-left: none;
  border-bottom: 3px solid color-mix(in srgb, #3b82f6 65%, transparent) !important;
}

.highlight-purple-geo {
  background: linear-gradient(to top, color-mix(in srgb, #8b5cf6 15%, var(--card-bg)) 0%, var(--card-bg) 80%);
  border: 1px solid color-mix(in srgb, #8b5cf6 15%, var(--card-border));
  border-left: none;
  border-bottom: 3px solid color-mix(in srgb, #8b5cf6 65%, transparent) !important;
}

.highlight-green {
  background: linear-gradient(to top, color-mix(in srgb, var(--risk-indicator-normal) 15%, var(--card-bg)) 0%, var(--card-bg) 80%);
  border: 1px solid color-mix(in srgb, var(--risk-indicator-normal) 15%, var(--card-border));
  border-left: none;
  border-bottom: 3px solid color-mix(in srgb, var(--risk-indicator-normal) 65%, transparent) !important;
}

/* Filtro Estilizado */
.filter-controls {
  display: flex;
  align-items: center;
  gap: 1rem;
}

.filter-toggle {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  cursor: pointer;
  user-select: none;
  font-size: 0.75rem;
  text-transform: none;
  font-weight: 600;
  color: var(--text-secondary);
}

.filter-toggle input {
  display: none;
}

.toggle-slider {
  position: relative;
  width: 32px;
  height: 18px;
  background-color: var(--tabs-border);
  border: 1px solid var(--tabs-border);
  border-radius: 20px;
  transition: 0.3s;
}

.toggle-slider:before {
  content: "";
  position: absolute;
  height: 12px;
  width: 12px;
  left: 3px;
  bottom: 3px;
  background-color: white;
  border-radius: 50%;
  transition: 0.3s;
}

input:checked + .toggle-slider {
  background-color: var(--primary-color);
}

input:checked + .toggle-slider:before {
  transform: translateX(14px);
}

.toggle-label {
  letter-spacing: normal;
}

.highlight-yellow {
  border-left: 3px solid var(--risk-low) !important;
}

.text-red {
  color: var(--risk-critical) !important;
}

/* 2. SECTION & TABLES */
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
  overflow: hidden; /* Garante que o border-radius se aplique à tabela interna */
}

.section-header {
  padding: 1rem 1.25rem 0.25rem 1.25rem;
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  text-align: left;
  width: 100%;
}

.section-header h3 {
  margin: 0;
  font-size: 1rem;
  color: var(--text-color);
  font-weight: 700;
  line-height: normal;
}
.subtitle {
  margin: 0.25rem 0 0 0;
  font-size: 0.8rem;
  color: var(--text-muted);
}

.table-responsive {
  overflow-x: auto;
  border-top: 1px solid var(--tabs-border);
  border-bottom: 1px solid var(--tabs-border);
  min-height: 35rem;
}

.premium-table {
  width: 100%;
  border-collapse: collapse;
}

.premium-table th {
  padding: 0.6rem 0.5rem;
  background: transparent;
  color: color-mix(in srgb, var(--text-secondary) 85%, transparent);
  font-size: 0.68rem;
  font-weight: 500;
  text-transform: uppercase;
  letter-spacing: 0.02em;
  border-bottom: 2px solid var(--tabs-border);
  text-align: center;
}

.premium-table th:first-child { text-align: left; }

.premium-table td {
  padding: 0.55rem 0.5rem;
  border-bottom: 1px solid var(--tabs-border);
  vertical-align: middle;
  color: color-mix(in srgb, var(--text-color) 85%, transparent);
  font-size: 0.8rem;
  text-transform: none !important;
}

/* Coluna de Status mais larga */
.premium-table th:nth-child(2),
.premium-table td:nth-child(2) {
  min-width: 320px;
  text-align: left;
}

.premium-table tbody tr:last-child td {
  border-bottom: none;
}

.premium-table.row-hover tbody tr:hover {
  background: var(--table-hover) !important;
  cursor: pointer;
}

.sticky-thead th {
  position: sticky;
  top: 0;
  z-index: 10; /* Aumentado para garantir que fique sobre o conteúdo */
  box-shadow: 0 2px 4px rgba(0, 0, 0, 0.2); /* Sombra para separar visualmente o header dos dados */
}

.col-center {
  text-align: center;
}
.col-right {
  text-align: right;
}

/* Table Specific Components */
.severe-row {
  background: color-mix(
    in srgb,
    var(--risk-critical) 4%,
    var(--bg-color)
  ) !important;
}

.med-id {
  font-weight: 500;
  font-size: 0.78rem;
  color: var(--text-color);
}
.med-sub {
  font-size: 0.72rem;
  color: var(--text-muted);
  font-weight: 400;
}

.mt-1 {
  margin-top: 0.25rem;
}
.mt-2 {
  margin-top: 0.5rem;
}
.mt-0 {
  margin-top: 0;
}

.tags-container {
  display: flex;
  flex-wrap: wrap;
  gap: 0.25rem;
}
.issue-tag {
  font-size: 0.7rem;
  font-weight: 500;
  padding: 0.2rem 0.6rem;
  border-radius: 6px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 0.3rem;
  white-space: nowrap;
  min-width: 85px;
  letter-spacing: normal;
  text-transform: none !important;
}
.issue-tag i {
  font-size: 0.7rem;
}
.issue-tag.red {
  background: color-mix(in srgb, var(--risk-high) 10%, var(--tabs-bg));
  color: var(--risk-high);
  border: 1px solid color-mix(in srgb, var(--risk-high) 20%, transparent);
}
.issue-tag.dark-red {
  background: color-mix(in srgb, var(--risk-high) 4%, var(--tabs-bg));
  color: color-mix(in srgb, var(--risk-high) 60%, var(--text-muted));
  border: 1px solid color-mix(in srgb, var(--risk-high) 10%, transparent);
  font-weight: 500;
}
.issue-tag.orange {
  background: color-mix(in srgb, var(--risk-medium) 10%, var(--tabs-bg));
  color: var(--risk-medium);
  border: 1px solid color-mix(in srgb, var(--risk-medium) 20%, transparent);
}
.issue-tag.yellow {
  background: color-mix(in srgb, var(--risk-low) 10%, var(--tabs-bg));
  color: var(--risk-low);
  border: 1px solid color-mix(in srgb, var(--risk-low) 20%, transparent);
}
.issue-tag.blue-network {
  background: color-mix(in srgb, #3b82f6 8%, var(--tabs-bg));
  color: #3b82f6;
  border: 1px solid color-mix(in srgb, #3b82f6 20%, transparent);
}
.issue-tag.purple-geo {
  background: color-mix(in srgb, #8b5cf6 8%, var(--tabs-bg));
  color: #8b5cf6;
  border: 1px solid color-mix(in srgb, #8b5cf6 20%, transparent);
}
.issue-tag.green-ok {
  background: color-mix(in srgb, var(--risk-indicator-normal) 10%, var(--tabs-bg));
  color: var(--risk-indicator-normal);
  border: 1px solid color-mix(in srgb, var(--risk-indicator-normal) 20%, transparent);
}

.badge-count {
  font-size: 0.7rem;
  font-weight: 600;
  opacity: 0.8;
  margin-left: 0.1rem;
}

.clickable-badge {
  cursor: pointer;
  user-select: none;
}

.alertas-diarios-row {
  background: transparent !important;
}

.alertas-diarios-cell {
  padding: 0 !important;
  border-bottom: 2px solid color-mix(in srgb, var(--risk-indicator-normal) 30%, transparent) !important;
}

.alertas-diarios-table {
  width: 100%;
  border-collapse: collapse;
  background: color-mix(in srgb, var(--risk-indicator-normal) 5%, var(--card-bg));
  font-size: 0.78rem;
}

.alertas-diarios-table thead tr {
  background: color-mix(in srgb, var(--risk-indicator-normal) 12%, transparent);
}

.alertas-diarios-table th {
  padding: 0.35rem 0.75rem;
  font-size: 0.7rem;
  font-weight: 600;
  color: var(--risk-indicator-normal);
  text-transform: uppercase;
  letter-spacing: 0.04em;
  text-align: left;
}

.alertas-diarios-table td {
  padding: 0.4rem 0.75rem;
  border-top: 1px solid color-mix(in srgb, var(--risk-indicator-normal) 10%, transparent);
  color: var(--text-color);
}

.col-date { font-weight: 600; white-space: nowrap; }
.col-descricao { color: var(--text-secondary); font-size: 0.75rem; }

.nivel-badge {
  display: inline-block;
  padding: 0.1rem 0.5rem;
  border-radius: 4px;
  font-size: 0.7rem;
  font-weight: 600;
  background: color-mix(in srgb, var(--risk-indicator-normal) 15%, transparent);
  color: var(--risk-indicator-normal);
  border: 1px solid color-mix(in srgb, var(--risk-indicator-normal) 25%, transparent);
}

.nivel-badge.nivel-rajada,
.nivel-badge.nivel-volume-extremo {
  background: color-mix(in srgb, var(--risk-critical) 15%, transparent);
  color: var(--risk-critical);
  border-color: color-mix(in srgb, var(--risk-critical) 25%, transparent);
}

.nivel-badge.nivel-concentração {
  background: color-mix(in srgb, var(--risk-high) 15%, transparent);
  color: var(--risk-high);
  border-color: color-mix(in srgb, var(--risk-high) 25%, transparent);
}

.bar-container {
  position: relative;
  height: 1.1rem; /* Levemente mais baixa */
  background: rgba(0, 0, 0, 0.05);
  border-radius: 4px;
  overflow: hidden;
  display: flex;
  align-items: center;
  min-width: 45px; /* Reduzido de 60 para 45 */
}
:global(.dark-mode) .bar-container {
  background: rgba(255, 255, 255, 0.1);
}
.bar-fill {
  position: absolute;
  top: 0;
  left: 0;
  bottom: 0;
  background: var(--primary-color);
  opacity: 0.2;
}
.bar-text {
  position: relative;
  z-index: 1;
  width: 100%;
  text-align: center;
  font-size: 0.78rem;
  font-weight: 500;
  color: var(--text-color);
  text-shadow: 0 0 2px var(--bg-color), 0 0 4px var(--bg-color);
}

.daily-dispensacao-chart {
  width: 100%;
  height: 280px;
  cursor: pointer;
}

/* Hourly Detail Styles */
.hourly-detail-wrapper {
  margin-top: 1.5rem;
  padding: 1.25rem;
  background: var(--surface-card);
  border: 1px solid var(--border-color);
  border-left: 4px solid #ef4444;
  border-radius: 8px;
  box-shadow: 0 4px 12px rgba(0,0,0,0.05);
}

.hourly-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 1rem;
}

.hourly-title {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  font-weight: 600;
  color: var(--text-color);
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


.close-detail-btn {
  background: none;
  border: none;
  color: var(--text-muted);
  cursor: pointer;
  padding: 4px;
  border-radius: 4px;
  transition: all 0.2s;
}
.close-detail-btn:hover {
  background: var(--surface-hover);
  color: #ef4444;
}

.hourly-subtitle {
  font-size: 0.9rem;
  color: var(--text-muted);
  margin-bottom: 1rem;
  line-height: 1.4;
}

.hourly-chart {
  height: 240px;
}

.hourly-loading {
  height: 200px;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 0.75rem;
  color: var(--text-muted);
}

.animate-fade-in {
  animation: fadeIn 0.3s ease-out;
}

@keyframes fadeIn {
  from { opacity: 0; transform: translateY(10px); }
  to { opacity: 1; transform: translateY(0); }
}
.chart-loading-badge {
  margin-left: 0.75rem;
  font-size: 0.78rem;
  color: var(--text-muted);
  font-weight: 500;
}
.chart-empty {
  display: flex;
  align-items: center;
  gap: 0.6rem;
  padding: 1.5rem 1.75rem;
  color: var(--text-muted);
  font-size: 0.88rem;
}
</style>
