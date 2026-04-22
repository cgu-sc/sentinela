<script setup>
import { computed, ref, onMounted, watch } from "vue";
import { useDelayedLoading } from '@/composables/useDelayedLoading';
import { storeToRefs } from 'pinia';
import { useCnpjDetailStore } from '@/stores/cnpjDetail';
import { useThemeStore } from '@/stores/theme';
import { useFormatting } from "@/composables/useFormatting";
import { useFilterParameters } from "@/composables/useFilterParameters";
import { useChartTheme } from '@/config/chartTheme';
import { API_ENDPOINTS } from '@/config/api';

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
const { chartTheme, chartUFAccents } = useChartTheme();
const themeStore = useThemeStore();
const raioxBg = computed(() => themeStore.isDark ? 'rgba(0,0,0,0.15)' : 'rgba(255,255,255,0.6)');

// ── Cache de Dados para Transição Suave (Flicker-Free) ──────────────────
// Mantém os dados anteriores visíveis para evitar o flash de tela vazia/loading duro
const cachedPrescritoresData = ref(prescritoresData.value);
const cachedCrmDailyProfile  = ref(crmDailyProfile.value);
const cachedCrmHourlyProfile = ref(crmHourlyProfile.value);

const showRefreshingKPIs  = useDelayedLoading(prescritoresLoading);
const showRefreshingDaily = useDelayedLoading(crmDailyProfileLoading);
const showRefreshingHourly = useDelayedLoading(crmHourlyProfileLoading);

watch([prescritoresData, prescritoresLoading], ([newData, loading]) => {
  if (newData && !loading) cachedPrescritoresData.value = newData;
}, { immediate: true });

watch([crmDailyProfile, crmDailyProfileLoading], ([newData, loading]) => {
  if (newData && !loading) cachedCrmDailyProfile.value = newData;
}, { immediate: true });

watch([crmHourlyProfile, crmHourlyProfileLoading], ([newData, loading]) => {
  if (newData && !loading) cachedCrmHourlyProfile.value = newData;
}, { immediate: true });

const { getApiParams } = useFilterParameters();

onMounted(() => {
  if (props.cnpj) {
    const { inicio, fim } = getApiParams();
    cnpjDetailStore.fetchCrmDailyProfile(props.cnpj, inicio, fim);
    cnpjDetailStore.fetchCrmHourlyProfile(props.cnpj, inicio, fim);
  }
});

const filterDailyOnlyAnomalous = ref(false);

const filteredDailyDays = computed(() => {
  const days = cachedCrmDailyProfile.value?.days ?? [];
  if (!filterDailyOnlyAnomalous.value) return days;
  return days.filter(d => d.is_anomalo === 1);
});

const dailyDates     = computed(() => filteredDailyDays.value.map(d => d.dt_janela));
const dailyValues    = computed(() => filteredDailyDays.value.map(d => d.nu_prescricoes_dia));
const dailyAnomalous = computed(() => filteredDailyDays.value.map(d => d.is_anomalo === 1));
const dailyMedians   = computed(() => filteredDailyDays.value.map(d => d.mediana_diaria ?? 0));

const dailyMediana   = computed(() => {
  const days = cachedCrmDailyProfile.value?.days ?? [];
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
    animation: true,
    animationDuration: 1000,
    animationEasing: 'cubicOut',
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
            color: dailyAnomalous.value[i]
              ? { type: 'linear', x: 0, y: 0, x2: 0, y2: 1, colorStops: [{ offset: 0, color: '#ef4444' }, { offset: 1, color: '#ef444440' }] }
              : { type: 'linear', x: 0, y: 0, x2: 0, y2: 1, colorStops: [{ offset: 0, color: chartUFAccents.value.bar1 }, { offset: 1, color: chartUFAccents.value.bar1 + '55' }] },
          },
        })),
      },
    {
      name: 'Mediana Referência (Dia)',
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
const selectedHourlyHour = ref(null);
const hourlyTransactions = ref([]);
const hourlyTransactionsLoading = ref(false);

const RAIOX_PAGE_SIZE = 8;
const raioxPage = ref(0);
const expandedRaioxRows = ref(new Set());

const groupedRaiox = computed(() => {
  const groups = {};
  hourlyTransactions.value.forEach(item => {
    const key = item.num_autorizacao;
    if (!groups[key]) {
      groups[key] = {
        num_autorizacao: key,
        data_hora: item.data_hora,
        crm: item.crm,
        crm_uf: item.crm_uf,
        nu_medicamentos: 0,
        vl_autorizacao: 0,
        items: []
      };
    }
    groups[key].nu_medicamentos += 1;
    groups[key].vl_autorizacao += (item.valor_pago || 0);
    groups[key].items.push(item);
  });
  return Object.values(groups).sort((a, b) => a.data_hora.localeCompare(b.data_hora));
});

// Inteligência de Recorrência de CRM
const crmFrequencies = computed(() => {
  const freqs = {};
  groupedRaiox.value.forEach(tx => {
    freqs[tx.crm] = (freqs[tx.crm] || 0) + 1;
  });
  return freqs;
});

function getCRMColor(crm) {
  if (!crm) return 'var(--primary-color)';
  let hash = 0;
  for (let i = 0; i < crm.length; i++) {
    hash = crm.charCodeAt(i) + ((hash << 5) - hash);
  }
  const h = Math.abs(hash % 360);
  // No Dark Mode, usamos cores mais vibrantes/claras (65% lightness)
  return `hsl(${h}, 70%, 65%)`;
}

const raioxTotalPages = computed(() => Math.ceil(groupedRaiox.value.length / RAIOX_PAGE_SIZE));
const raioxPagedTransactions = computed(() =>
  groupedRaiox.value.slice(raioxPage.value * RAIOX_PAGE_SIZE, (raioxPage.value + 1) * RAIOX_PAGE_SIZE)
);

function toggleRaioxRow(auth) {
  if (expandedRaioxRows.value.has(auth)) {
    expandedRaioxRows.value.delete(auth);
  } else {
    expandedRaioxRows.value.add(auth);
  }
}

async function onChartClick(params) {
  const day = filteredDailyDays.value?.[params.dataIndex];
  if (!day || !day.is_anomalo) {
    selectedDay.value = null;
    selectedHourlyHour.value = null;
    return;
  }
  
  // Agora apenas selecionamos o dia. O computed chartOptionHourly cuidará de filtrar os pontos
  // que já foram pré-carregados no store.
  selectedDay.value = day;
  selectedHourlyHour.value = null;
}

async function onHourlyChartClick(params) {
  const hourStr = params.name.replace('h', '');
  const hourInt = parseInt(hourStr, 10);
  
  if (!selectedDay.value || isNaN(hourInt)) return;
  if (!params.data || params.data.value === 0 || params.data.is_anomalo_hora !== 1) return; // ignora vazias e horas comuns
  
  if (selectedHourlyHour.value === hourInt) return; // ignora clique na mesma hora
  
  selectedHourlyHour.value = hourInt;
  raioxPage.value = 0;
  hourlyTransactionsLoading.value = true;
  // Não limpo mais o array aqui para manter a tabela renderizada na DOM e evitar Layout Shift
  
  try {
    const url = API_ENDPOINTS.analyticsCrmHourlyTransactions(props.cnpj, selectedDay.value.dt_janela, hourInt);
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

// Helper para truncar texto
function truncate(str, n) {
  if (!str) return '';
  return str.length > n ? str.substring(0, n - 1) + '...' : str;
}

const chartOptionHourly = computed(() => {
  if (!selectedDay.value || !cachedCrmHourlyProfile.value) return {};
  
  const c = chartTheme.value;
  const targetDate = selectedDay.value.dt_janela;
  const pointsForDay = cachedCrmHourlyProfile.value.points.filter(p => p.dt_janela === targetDate);
  const hrPico = selectedDay.value.hr_pico;

  // 24 pontos garantidos (0-23)
  const fullPoints = Array.from({ length: 24 }, (_, h) => {
    const found = pointsForDay.find(p => p.hr_janela === h);
    return found || { hr_janela: h, nu_prescricoes: 0, nu_crms_diferentes: 0, mediana_hora: 0, is_anomalo_hora: 0 };
  });

  // Cores das barras: usa a flag direta do banco, permitindo múltiplas anomalias no mesmo dia
  const barColors = fullPoints.map(p => {
    if (p.is_anomalo_hora === 1 && p.nu_prescricoes > 0) {
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
        { offset: 0, color: 'rgba(99, 102, 241, 0.65)' },
        { offset: 1, color: 'rgba(99, 102, 241, 0.15)' }
      ]
    };
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
        const dataIndex = params[0]?.dataIndex ?? 0;
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
                <span style="display:flex;align-items:center;gap:6px;">
                  <span style="width:10px;height:10px;border-radius:2px;background:#ef4444;display:inline-block;"></span>
                  <span style="font-size:11px; opacity:.6; text-transform:uppercase;">Volume</span>
                </span>
                <span style="font-weight:700; font-size:13px;">${vol} <small>autorizações</small></span>
              </div>
              <div style="display:flex; justify-content:space-between; align-items:center;">
                <span style="display:flex;align-items:center;gap:6px;">
                  <span style="width:10px;height:10px;border-radius:2px;background:#6366f1;display:inline-block;"></span>
                  <span style="font-size:11px; opacity:.6; text-transform:uppercase;">CRMs Distintos</span>
                </span>
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
        data: fullPoints.map((p, i) => ({ 
          value: p.nu_prescricoes, 
          nu_crms: p.nu_crms_diferentes,
          is_anomalo_hora: p.is_anomalo_hora,
          cursor: (p.is_anomalo_hora === 1 && p.nu_prescricoes > 0) ? 'pointer' : 'default',
          itemStyle: { color: barColors[i] } 
        })),
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
const isRefreshing = computed(() => showRefreshingKPIs.value && cachedPrescritoresData.value !== null);

// --- CÁLCULOS DOS KPIs ---
const summary = computed(() => cachedPrescritoresData.value?.summary || {});
const crmsInteresse = computed(() => cachedPrescritoresData.value?.crms_interesse || []);

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
const doctorsIntensivaLocal = computed(() => crmsInteresse.value.filter((m) => m.flag_robo > 0));
const doctorsIntensivaBrasil = computed(() => crmsInteresse.value.filter((m) => m.flag_robo_oculto > 0));

const qtdPrescrIntensivaLocal = computed(() => doctorsIntensivaLocal.value.length);
const qtdPrescrIntensivaOcultos = computed(() => doctorsIntensivaBrasil.value.length);

const qtdPrescrIntensivaTotal = computed(() => {
  const ids = new Set([
    ...doctorsIntensivaLocal.value.map(m => m.id_medico),
    ...doctorsIntensivaBrasil.value.map(m => m.id_medico)
  ]);
  return ids.size;
});

// CRMs Inválidos e Irregulares
const qtdCrmInvalido = computed(
  () => crmsInteresse.value.filter((m) => m.flag_crm_invalido > 0).length,
);
const qtdPrescrAntesRegistro = computed(
  () => crmsInteresse.value.filter((m) => m.flag_prescricao_antes_registro > 0).length,
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
  () => crmsInteresse.value.filter((m) => m.alerta_concentracao_mesmo_crm).length,
);

// Surtos de Lançamento (Frequência horária do Estabelecimento)
const cnpjAlerts = computed(() => cachedPrescritoresData.value?.cnpj_alerts || []);
const totalSurtosCnpj = computed(() => cnpjAlerts.value.length);
const totalDiasSurtosCnpj = computed(() => {
  const uniqueDays = new Set(cnpjAlerts.value.map(a => a.dt));
  return uniqueDays.size;
});

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

function formatDescricao(a) {
  const num = `<span class="desc-num">${a.nu_prescricoes}</span>`;
  if (!a.nu_minutos || a.nu_minutos === 0) {
    return `${num} autorizações de venda <span class="desc-janela">no mesmo instante</span> para o mesmo CRM`;
  }
  const h = Math.floor(a.nu_minutos / 60);
  const min = a.nu_minutos % 60;
  const janela = h > 0 ? `${h}h ${min}min` : `${min}min`;
  const taxa = a.taxa_hora?.toFixed(1) ?? '—';
  return `${num} autorizações de venda <span class="desc-janela">em ${janela} (${taxa}/hora)</span> para o mesmo CRM`;
}

const filterOnlyIssues = ref(false);
const activeKpiFilter = ref(null);
const viewMode = ref('medicos'); // 'medicos' ou 'cronologia'

const kpiFilters = {
  top1: (m) => m.id_medico === crmsInteresse.value[0]?.id_medico,
  top5: (m) => crmsInteresse.value.slice(0, 5).some((t) => t.id_medico === m.id_medico),
  agrupamento: (m) => !!m.alerta_concentracao_mesmo_crm,
  intensiva: (m) => m.flag_robo > 0 || m.flag_robo_oculto > 0,
  exclusivo: (m) => m.flag_crm_exclusivo > 0,
  fraude_crm: (m) =>
    m.flag_crm_invalido > 0 || m.flag_prescricao_antes_registro > 0,
  distancia: (m) => !!m.alerta5_geografico,
  surtos_cnpj: (m) => m.flag_concentracao_estabelecimento > 0,
};

const kpiFilterLabels = {
  top1: "Concentração TOP 1",
  top5: "Concentração TOP 5",
  agrupamento: "CONCENTRAÇÃO MESMO CRM",
  intensiva: ">30 Prescrições/Dia",
  exclusivo: "CRM Exclusivo",
  fraude_crm: "Fraudes CRM",
  distancia: "Distância (>400km)",
  surtos_cnpj: "CONCENTRAÇÃO CRMs DIVERSOS",
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
  m.alerta_concentracao_mesmo_crm ||
  m.flag_crm_invalido > 0 ||
  m.flag_prescricao_antes_registro > 0 ||
  m.alerta5_geografico ||
  m.flag_crm_exclusivo > 0 ||
  m.flag_concentracao_estabelecimento > 0;

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
    totalSurtosCnpj: totalSurtosCnpj.value,
    diasComSurtosCnpj: diasComSurtosCnpj.value,
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

    <div v-else class="content-wrapper" :class="{ 'is-refreshing': showRefreshingKPIs }">
      <!-- SELETOR DE VISÃO (TOP LEVEL) -->
      <div class="view-mode-container animate-fade-in">
        <div class="view-mode-selector">
          <button 
            class="view-mode-btn" 
            :class="{ active: viewMode === 'medicos' }" 
            @click="viewMode = 'medicos'"
          >
            <i class="pi pi-users" />
            <span>PERFIL DE CRMs</span>
          </button>
          <button 
            class="view-mode-btn" 
            :class="{ active: viewMode === 'cronologia' }" 
            @click="viewMode = 'cronologia'"
          >
            <i class="pi pi-chart-line" />
            <span>LINHA DO TEMPO & RAIO-X</span>
          </button>
        </div>
      </div>

      <!-- 1. KPIs (EXIBIDOS APENAS NA VISÃO MÉDICOS) -->
      <div v-if="viewMode === 'medicos'" class="no-padding-mobile animate-fade-in">
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
              <span class="alert-kpi-label">CONCENTRAÇÃO MESMO CRM</span>
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

          <!-- Prescrição Intensiva Unified -->
          <div
            class="alert-kpi-card"
            :class="[
              qtdPrescrIntensivaTotal > 0 ? 'highlight-red' : 'kpi-disabled',
              activeKpiFilter === 'intensiva' ? 'kpi-active' : '',
            ]"
            @click="setKpiFilter('intensiva')"
          >
            <div class="alert-kpi-header">
              <span class="alert-kpi-label">>30 PRESCRIÇÕES/DIA</span>
              <i
                class="pi pi-info-circle kpi-info-icon"
                v-tooltip.top="
                  'Médicos que emitiram mais de 30 prescrições por dia (comportamento de robô), calculado localmente e em todo o Brasil.'
                "
              />
            </div>
            <div class="alert-kpi-body">
              <span class="alert-kpi-val">{{ qtdPrescrIntensivaTotal }}</span>
              <span class="alert-kpi-hint">
                {{ qtdPrescrIntensivaLocal }} local · {{ qtdPrescrIntensivaOcultos }} Brasil
              </span>
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

          <!-- Surtos de Lançamento (Geral CNPJ) -->
          <div
            class="alert-kpi-card"
            :class="[
              totalSurtosCnpj > 0 ? 'highlight-red' : 'kpi-disabled',
              activeKpiFilter === 'surtos_cnpj' ? 'kpi-active' : '',
            ]"
            @click="setKpiFilter('surtos_cnpj')"
          >
            <div class="alert-kpi-header">
              <span class="alert-kpi-label">CONCENTRAÇÃO CRMs DIVERSOS</span>
              <i
                class="pi pi-info-circle kpi-info-icon"
                v-tooltip.top="
                  'Identifica se a farmácia registrou volume atípico de dispensações concentrado em poucas horas.'
                "
              />
            </div>
            <div class="alert-kpi-body">
              <span class="alert-kpi-val">{{ totalSurtosCnpj }}</span>
              <span class="alert-kpi-hint">
                Registros em {{ totalDiasSurtosCnpj }} dias distintos
              </span>
            </div>
          </div>
        </div>
      </div>

      <!-- 2. GRÁFICO — PERFIL DIÁRIO DE DISPENSAÇÕES (VISÃO CRONOLOGIA) -->
      <div v-if="viewMode === 'cronologia'" class="section-container daily-chart-section animate-fade-in" :class="{ 'is-refreshing': showRefreshingDaily }">
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
              <span v-if="selectedDay.is_anomalo" class="anomalo-badge" style="background: rgba(239, 68, 68, 0.15); color: #ef4444; border: 1px solid rgba(239, 68, 68, 0.3); font-size: 10px; padding: 2px 8px; border-radius: 4px; font-weight: 800; white-space: nowrap;">
                ANOMALIA DETECTADA
              </span>
            </div>
            <button class="close-detail-btn" @click="selectedDay = null" style="background: transparent; border: none; color: white; opacity: 0.5; cursor: pointer; padding: 5px;">
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

            <!-- Tabela Raio-X Sub-horário (Transactions Literal) -->
            <div v-if="selectedHourlyHour !== null" class="raiox-wrapper animate-fade-in">
              <div class="raiox-header">
                <div class="raiox-title">
                  <i class="pi pi-search" />
                  <span>RAIO-X: TRANSAÇÕES ÀS {{ String(selectedHourlyHour).padStart(2, '0') }}H</span>
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
                    <template v-for="tx in raioxPagedTransactions" :key="tx.num_autorizacao">
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

                      <!-- Linha de Detalhes Expandida -->
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

              <div v-if="raioxTotalPages > 1" class="raiox-pagination">
                <span>{{ raioxPage * RAIOX_PAGE_SIZE + 1 }}–{{ Math.min((raioxPage + 1) * RAIOX_PAGE_SIZE, groupedRaiox.length) }} de {{ groupedRaiox.length }}</span>
                <div class="raiox-pagination-controls">
                  <button class="raiox-page-btn" :disabled="raioxPage === 0" @click="raioxPage--">
                    <i class="pi pi-chevron-left" /> Anterior
                  </button>
                  <span class="raiox-page-info">{{ raioxPage + 1 }} / {{ raioxTotalPages }}</span>
                  <button class="raiox-page-btn" :disabled="raioxPage >= raioxTotalPages - 1" @click="raioxPage++">
                    Próximo <i class="pi pi-chevron-right" />
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- 3. TOP 20 CRMs (TABELA DETALHADA) (VISÃO MEDICOS) -->
      <div v-if="viewMode === 'medicos'" class="section-container animate-fade-in">
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
          <div v-if="activeKpiFilter" class="filter-badge animate-fade-in" v-tooltip.bottom="'Filtro de KPI Ativo'">
            <i class="pi pi-filter-fill" />
            <span class="filter-text">
              <small style="opacity: 0.8; font-weight: 500; margin-right: 2px; text-transform: uppercase; font-size: 0.6rem;">Filtro:</small>
              {{ kpiFilterLabels[activeKpiFilter] }} — <strong class="filter-count">{{ filteredCrmsInteresse.length }} de {{ crmsInteresse.length }}</strong>
            </span>
            <button class="clear-filter-btn" @click.stop="clearFilters" title="Limpar filtro">
              <i class="pi pi-times" />
            </button>
          </div>
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
                <th style="width: 10%">CRM / Médico</th>
                <th style="width: 34%">Status / Alertas</th>
                <th class="col-right" style="width: 15%">Volume / Valor</th>
                <th class="col-center" style="width: 16%">Participação / Acumulado</th>
                <th class="col-center" style="width: 8%">Rede</th>
                <th class="col-center" style="width: 6%">P/D Loc.</th>
                <th class="col-center" style="width: 6%">P/D BR</th>
                <th class="col-center" style="width: 5%">Excl.</th>
              </tr>
            </thead>
            <tbody>
              <template
                v-for="(m, i) in visibleCrms"
                :key="i"
              >
              <tr
                :class="{ 'row-expandable': m.alerta_concentracao_mesmo_crm }"
                @click="m.alerta_concentracao_mesmo_crm && toggleAlertasDiarios(m.id_medico)"
              >
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
                      <i class="pi pi-history"></i> >30 PRESC/DIA (LOCAL)
                    </span>
                    <span v-if="m.flag_robo_oculto && !m.flag_robo" class="issue-tag orange" v-tooltip.top="'>30 Prescrições/dia em todo o Brasil (Robô Oculto)'">
                      <i class="pi pi-globe"></i> >30 PRESC/DIA (BRASIL)
                    </span>
                    <span
                      v-if="m.alerta_concentracao_mesmo_crm"
                      class="issue-tag green-ok clickable-badge"
                      v-tooltip.top="expandedAlertasMedico.has(m.id_medico) ? 'Recolher detalhes' : 'Ver episódios detalhados'"
                      @click.stop="toggleAlertasDiarios(m.id_medico)"
                    >
                      <i class="pi pi-stopwatch"></i> CONCENTRAÇÃO MESMO CRM
                      <span v-if="m.alertas_diarios?.length > 1" class="badge-count">
                        ({{ m.alertas_diarios.length }}x)
                      </span>
                      <i :class="expandedAlertasMedico.has(m.id_medico) ? 'pi pi-chevron-up' : 'pi pi-chevron-down'" style="font-size:0.6rem; margin-left:0.2rem;" />
                    </span>
                    <span v-if="m.flag_crm_invalido" class="issue-tag red" v-tooltip.top="'CRM não encontrado na base de dados oficial do Conselho Federal de Medicina (CFM)'">
                      <i class="pi pi-ban"></i> CRM INEXISTENTE
                    </span>
                    <span v-if="m.flag_prescricao_antes_registro" class="issue-tag dark-red" v-tooltip.top="'Venda anterior ao Registro oficial no CFM'">
                      <i class="pi pi-calendar-times"></i> CRM IRREGULAR
                    </span>
                    <span v-if="m.flag_crm_exclusivo > 0" class="issue-tag blue-network" v-tooltip.top="'Médico prescreveu exclusivamente para este CNPJ no total do Brasil'">
                      <i class="pi pi-lock"></i> CRM EXCLUSIVO
                    </span>
                    <span v-if="m.alerta5_geografico" class="issue-tag purple-geo" v-tooltip.top="'Distância superior a 400km entre prescritor e farmácia'">
                      <i class="pi pi-map-marker"></i> DISTÂNCIA >400KM
                    </span>
                    <span v-if="m.flag_concentracao_estabelecimento" class="issue-tag red" v-tooltip.top="'O registro deste médico ocorreu durante uma concentração horária anômala no estabelecimento'">
                      <i class="pi pi-bolt"></i> CONCENTRAÇÃO CRMs DIVERSOS
                    </span>
                    <i
                      v-if="
                        !m.flag_robo &&
                        !m.flag_robo_oculto &&
                        !m.flag_crm_invalido &&
                        !m.flag_prescricao_antes_registro &&
                        !m.alerta5_geografico &&
                        !m.flag_concentracao_estabelecimento &&
                        (!m.flag_crm_exclusivo || m.flag_crm_exclusivo === 0)
                      "
                      class="pi pi-check-circle"
                      style="color: var(--text-muted); font-size: 0.85rem;"
                      v-tooltip.top="'Sem ocorrências identificadas'"
                    />
                  </div>
                </td>
                <td class="col-right">
                  <div class="cell-stacked">
                    <span class="cell-main text-primary">{{ formatCurrencyFull(m.vl_total_prescricoes) }}</span>
                    <span class="cell-sub">{{ formatNumberFull(m.nu_prescricoes) }} autorizações</span>
                  </div>
                </td>
                <td class="col-center">
                  <div class="multi-bar-container">
                    <div class="bar-row">
                      <span class="bar-label">part.</span>
                      <div class="bar-container">
                        <div class="bar-fill part-fill" :style="{ width: Math.min(m.pct_participacao, 100) + '%' }"></div>
                        <span class="bar-text">{{ formatPct(m.pct_participacao) }}</span>
                      </div>
                    </div>
                    <div class="bar-row">
                      <span class="bar-label">acum.</span>
                      <div class="bar-container">
                        <div class="bar-fill acum-fill" :style="{ width: Math.min(m.pct_acumulado, 100) + '%' }"></div>
                        <span class="bar-text">{{ formatPct(m.pct_acumulado) }}</span>
                      </div>
                    </div>
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
                  <div class="alertas-wrapper">
                  <table class="alertas-diarios-table">
                    <thead>
                      <tr>
                        <th><i class="pi pi-calendar" /> Data</th>
                        <th><i class="pi pi-id-card" /> CRM</th>
                        <th class="col-right"><i class="pi pi-chart-bar" /> Autorizações</th>
                        <th class="col-center"><i class="pi pi-clock" /> Janela</th>
                        <th class="col-right"><i class="pi pi-chart-line" /> Taxa/hora</th>
                        <th><i class="pi pi-align-left" /> Descrição</th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr v-for="(a, j) in m.alertas_diarios" :key="j" class="alerta-diario-item">
                        <td class="col-date">{{ formatarDataAlerta(a.dt) }}</td>
                        <td class="col-crm">{{ m.id_medico }}</td>
                        <td class="col-right">{{ a.nu_prescricoes }}</td>
                        <td class="col-center">{{ formatarJanela(a.nu_minutos) }}</td>
                        <td class="col-right">{{ a.taxa_hora?.toFixed(1) }}/h</td>
                        <td class="col-descricao" v-html="formatDescricao(a)" />
                      </tr>
                    </tbody>
                  </table>
                  </div>
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
.is-refreshing {
  opacity: 0.5;
  pointer-events: none;
  transition: opacity 0.3s ease;
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

/* ── Raio-X Sub-horário ─────────────────────────────────────────────────── */
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

.raiox-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.raiox-title {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  font-size: 0.8rem;
  font-weight: 600;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  color: var(--risk-high);
}

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

.raiox-spinner {
  font-size: 0.8rem;
  color: var(--text-muted);
}

.raiox-empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 0.5rem;
  padding: 2rem 1rem;
  color: var(--text-muted);
  font-size: 0.85rem;
  min-height: 390px;
}

.raiox-empty-icon {
  font-size: 1.75rem;
  opacity: 0.4;
}

.raiox-table-wrapper {
  border-radius: 6px;
  min-height: 390px;
}

.raiox-table-wrapper.is-loading {
  opacity: 0.4;
  pointer-events: none;
  transition: opacity 0.25s ease;
}

/* Estilos de Detalhamento de Itens */
.row-expanded {
  background: color-mix(in srgb, var(--primary-color) 5%, transparent) !important;
}

.raiox-val-cell {
  font-weight: 700;
  color: var(--text-color);
}

.count-pill {
  background: var(--tabs-border);
  padding: 1px 6px;
  border-radius: 4px;
  font-weight: 600;
  font-size: 0.75rem;
}

/* Estilos de Detalhamento Flat */
.align-top {
  vertical-align: top !important;
  padding-top: 1rem !important;
}

.raiox-item-summary {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding-top: 0.85rem;
}

.flat-item-prod {
  font-size: 0.78rem;
  font-weight: 700;
  color: var(--primary-color);
  letter-spacing: -0.01em;
}

.flat-item-princ {
  font-size: 0.68rem;
  opacity: 0.5;
  font-style: italic;
  color: var(--text-color);
  max-width: 250px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

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

.more-items-pill i {
  font-size: 0.5rem;
  opacity: 0.8;
}

.expanded-items-list {
  background: color-mix(in srgb, var(--card-bg) 95%, white 2%);
  border-bottom: 2px solid var(--tabs-border);
}

.expanded-item-entry {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 0.6rem 1.5rem 0.6rem 3rem;
  border-bottom: 1px solid color-mix(in srgb, var(--tabs-border) 30%, transparent);
}

.expanded-item-entry:last-child {
  border-bottom: none;
}

.item-main-info {
  display: flex;
  align-items: center;
  gap: 0.6rem;
}

.item-name {
  font-size: 0.75rem;
  font-weight: 600;
  color: var(--primary-color);
}

.item-active {
  font-size: 0.7rem;
  opacity: 0.6;
  font-style: italic;
}

.item-gtin {
  font-size: 0.6rem;
  font-family: var(--font-mono);
  opacity: 0.4;
}

.item-price {
  font-size: 0.75rem;
  font-weight: 700;
  font-family: var(--font-mono);
}

.row-expanded-main {
  background: color-mix(in srgb, var(--primary-color) 5%, transparent) !important;
}

.raiox-table-wrapper {
  border-radius: 6px;
  max-height: 480px; /* Limite máximo de altura */
  overflow-y: auto;  /* Habilita scroll interno */
  background: color-mix(in srgb, var(--card-bg) 40%, transparent);
  border: 1px solid var(--tabs-border);
  scrollbar-width: thin;
  scrollbar-color: var(--primary-color) transparent;
}

.raiox-table { 
  font-size: 0.75rem; 
  table-layout: fixed;
  width: 100%;
  border-collapse: separate; /* Necessário para sticky header funcionar bem */
  border-spacing: 0;
}

.sticky-thead th {
  position: sticky;
  top: 0;
  z-index: 10;
  background: var(--card-bg) !important; /* Fundo sólido para cobrir os itens ao rolar */
  box-shadow: inset 0 -1px 0 var(--tabs-border);
}

.raiox-table .col-center { text-align: center; }

.crm-badge-container {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  padding-right: 0.8rem; /* Espaço para não encostar na descrição */
}

.crm-recurrence-badge {
  font-size: 0.62rem;
  font-weight: 800;
  padding: 0.1rem 0.35rem;
  border-radius: 4px;
  background: transparent;
  animation: pulse-soft 2.5s infinite;
}

@keyframes pulse-soft {
  0% { opacity: 0.7; transform: scale(1); }
  50% { opacity: 1; transform: scale(1.05); }
  100% { opacity: 0.7; transform: scale(1); }
}

.raiox-pagination {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0.85rem 0.5rem 0.25rem 0.5rem;
  margin-top: 0.5rem;
  border-top: 1px solid var(--tabs-border);
  font-size: 0.72rem;
  font-weight: 600;
  color: var(--text-color);
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

.raiox-pagination-controls {
  display: flex;
  align-items: center;
  gap: 0.75rem;
}

.raiox-page-btn {
  background: color-mix(in srgb, var(--card-bg) 60%, white 5%);
  border: 1px solid var(--tabs-border);
  color: var(--text-color);
  padding: 0.35rem 0.75rem;
  border-radius: 4px;
  cursor: pointer;
  display: flex;
  align-items: center;
  gap: 0.4rem;
  font-size: 0.7rem;
  font-weight: 600;
  transition: all 0.2s ease;
}

.raiox-page-btn:hover:not(:disabled) {
  background: var(--primary-color);
  color: white;
  border-color: var(--primary-color);
  transform: translateY(-1px);
}

.raiox-page-btn:disabled {
  opacity: 0.3;
  cursor: not-allowed;
}

.raiox-page-info {
  font-size: 0.75rem;
  font-family: var(--font-mono);
  color: var(--text-muted);
  background: var(--tabs-border);
  padding: 0.15rem 0.5rem;
  border-radius: 4px;
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

/* Estado ativo (Clicado) — Destaque com Aura e Tingimento */
.alert-kpi-card.kpi-active {
  transform: translateY(-3px) scale(1.01);
  z-index: 2;
  border-left-width: 6px !important;
}

.alert-kpi-card.highlight-red.kpi-active {
  background: color-mix(in srgb, var(--risk-high) 10%, var(--card-bg));
  border-color: var(--risk-high) !important;
  box-shadow: 0 0 25px -5px color-mix(in srgb, var(--risk-high) 60%, transparent), 0 10px 30px rgba(0, 0, 0, 0.2);
}

.alert-kpi-card.highlight-orange.kpi-active {
  background: color-mix(in srgb, var(--risk-medium) 10%, var(--card-bg));
  border-color: var(--risk-medium) !important;
  box-shadow: 0 0 25px -5px color-mix(in srgb, var(--risk-medium) 60%, transparent), 0 10px 30px rgba(0, 0, 0, 0.2);
}

.alert-kpi-card.highlight-green.kpi-active {
  background: color-mix(in srgb, var(--risk-indicator-normal) 10%, var(--card-bg));
  border-color: var(--risk-indicator-normal) !important;
  box-shadow: 0 0 25px -5px color-mix(in srgb, var(--risk-indicator-normal) 60%, transparent), 0 10px 30px rgba(0, 0, 0, 0.2);
}

.alert-kpi-card.highlight-purple.kpi-active {
  background: color-mix(in srgb, #3b82f6 10%, var(--card-bg));
  border-color: #3b82f6 !important;
  box-shadow: 0 0 25px -5px color-mix(in srgb, #3b82f6 60%, transparent), 0 10px 30px rgba(0, 0, 0, 0.2);
}

.alert-kpi-card.highlight-purple-geo.kpi-active {
  background: color-mix(in srgb, #8b5cf6 10%, var(--card-bg));
  border-color: #8b5cf6 !important;
  box-shadow: 0 0 25px -5px color-mix(in srgb, #8b5cf6 60%, transparent), 0 10px 30px rgba(0, 0, 0, 0.2);
}

/* ── Célula Empilhada (Volume / Valor) ─────────────────────────────────── */
.cell-stacked {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 0.15rem;
  line-height: 1.2;
}

.cell-main {
  font-size: 0.85rem;
  font-weight: 600;
}

.cell-sub {
  font-size: 0.7rem;
  color: var(--text-muted);
  font-weight: 400;
  opacity: 0.8;
}

/* ── Multi-Bar Layout (Part. / Acum.) ─────────────────────────────────── */
.multi-bar-container {
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
  width: 100%;
  min-width: 120px;
}

.bar-row {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  width: 100%;
}

.bar-row .bar-container {
  flex: 1;
}

.bar-label {
  font-size: 0.65rem;
  text-transform: uppercase;
  color: var(--text-muted);
  font-weight: 600;
  min-width: 36px; /* Aumentado levemente para acomodar "acum." com folga */
  text-align: left;
  opacity: 0.7;
}

.part-fill {
  background: linear-gradient(90deg, rgba(99, 102, 241, 0.55), rgba(129, 140, 248, 0.82)) !important;
  opacity: 1 !important;
}

.acum-fill {
  background: linear-gradient(90deg, rgba(245, 158, 11, 0.55), rgba(251, 191, 36, 0.82)) !important;
  opacity: 1 !important;
}

.filter-badge {
  display: inline-flex;
  align-items: center;
  gap: 0.6rem;
  padding: 0.25rem 0.4rem 0.25rem 0.75rem;
  background: color-mix(in srgb, var(--risk-high) 12%, transparent);
  border: 1px solid color-mix(in srgb, var(--risk-high) 35%, transparent);
  border-radius: 99px;
  color: var(--risk-high);
  font-size: 0.72rem;
  font-weight: 600;
  margin-left: 1rem;
  box-shadow: 0 4px 12px rgba(0,0,0,0.15);
  position: relative;
  overflow: hidden;
  backdrop-filter: blur(8px); /* Efeito Glassmorphism */
  -webkit-backdrop-filter: blur(8px);
}

/* Efeito Shimmer (Brilho dinâmico) */
.filter-badge::after {
  content: "";
  position: absolute;
  top: 0;
  left: -100%;
  width: 100%;
  height: 100%;
  background: linear-gradient(
    90deg,
    transparent,
    rgba(255, 255, 255, 0.05),
    rgba(255, 255, 255, 0.2),
    rgba(255, 255, 255, 0.05),
    transparent
  );
  animation: shimmer-sweep 4s infinite ease-in-out;
}

@keyframes shimmer-sweep {
  0% { left: -100%; }
  15% { left: 100%; }
  100% { left: 100%; }
}

.filter-badge i.pi-filter-fill {
  font-size: 0.65rem;
  opacity: 0.8;
  animation: icon-spin-subtle 4s infinite ease-in-out;
}

@keyframes icon-spin-subtle {
  0%, 70% { transform: rotate(0deg); }
  85% { transform: rotate(-360deg); }
  100% { transform: rotate(-360deg); }
}

.filter-text {
  letter-spacing: 0.02em;
}

.filter-count {
  font-weight: 800;
  margin-left: 0.2rem;
}

.clear-filter-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 18px;
  height: 18px;
  background: color-mix(in srgb, var(--risk-high) 15%, transparent);
  color: var(--risk-high);
  border: none;
  border-radius: 50%;
  cursor: pointer;
  transition: all 0.2s ease;
  padding: 0;
}

.clear-filter-btn:hover {
  background: var(--risk-high);
  color: white;
}

.clear-filter-btn i {
  font-size: 0.55rem;
  font-weight: 900;
}

/* SELETOR DE VISÃO */
.view-mode-container {
  display: flex;
  flex-direction: column;
  align-items: center;
  margin: 0.5rem 0 1.5rem;
  padding: 0 1rem;
}

.view-mode-selector {
  display: flex;
  background: color-mix(in srgb, var(--card-bg) 40%, transparent);
  backdrop-filter: blur(8px);
  -webkit-backdrop-filter: blur(8px);
  border: 1px solid color-mix(in srgb, white 5%, transparent);
  padding: 4px;
  border-radius: 12px;
  box-shadow: 0 2px 10px rgba(0,0,0,0.1);
  gap: 4px;
}

.view-mode-btn {
  display: flex;
  align-items: center;
  gap: 0.6rem;
  padding: 0.55rem 1.4rem;
  border: none;
  background: transparent;
  color: var(--text-secondary);
  font-size: 0.75rem;
  font-weight: 600;
  border-radius: 9px;
  cursor: pointer;
  transition: all 0.2s ease;
  letter-spacing: 0.02em;
}

.view-mode-btn i {
  font-size: 1rem;
  opacity: 0.6;
}

.view-mode-btn:hover {
  color: var(--text-color);
  background: color-mix(in srgb, var(--text-color) 5%, transparent);
}

.view-mode-btn.active {
  background: color-mix(in srgb, var(--primary-color) 10%, transparent);
  color: var(--primary-color);
}

:global(.dark-mode) .view-mode-btn.active {
  background: color-mix(in srgb, var(--primary-color) 12%, transparent);
  color: white;
  box-shadow: none;
}

.view-mode-btn.active i {
  opacity: 1;
}

.view-mode-hint {
  font-size: 0.72rem;
  color: var(--text-secondary);
  margin-top: 0.75rem;
  opacity: 0.7;
  font-style: italic;
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
  border-left: 4px solid var(--risk-high) !important;
}

.highlight-orange {
  background: linear-gradient(to top, color-mix(in srgb, var(--risk-medium) 15%, var(--card-bg)) 0%, var(--card-bg) 80%);
  border: 1px solid color-mix(in srgb, var(--risk-medium) 15%, var(--card-border));
  border-left: 4px solid var(--risk-medium) !important;
}

.highlight-purple {
  background: linear-gradient(to top, color-mix(in srgb, #3b82f6 15%, var(--card-bg)) 0%, var(--card-bg) 80%);
  border: 1px solid color-mix(in srgb, #3b82f6 15%, var(--card-border));
  border-left: 4px solid #3b82f6 !important;
}

.highlight-purple-geo {
  background: linear-gradient(to top, color-mix(in srgb, #8b5cf6 15%, var(--card-bg)) 0%, var(--card-bg) 80%);
  border: 1px solid color-mix(in srgb, #8b5cf6 15%, var(--card-border));
  border-left: 4px solid #8b5cf6 !important;
}

.highlight-green {
  background: linear-gradient(to top, color-mix(in srgb, var(--risk-indicator-normal) 15%, var(--card-bg)) 0%, var(--card-bg) 80%);
  border: 1px solid color-mix(in srgb, var(--risk-indicator-normal) 15%, var(--card-border));
  border-left: 4px solid var(--risk-indicator-normal) !important;
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
  table-layout: fixed;
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
  text-align: left;
  overflow: hidden;
  text-overflow: ellipsis;
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
.issue-tag:hover {
  transform: translateY(-1px);
  filter: brightness(1.1);
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
}
.issue-tag i {
  font-size: 0.7rem;
}
.issue-tag.red {
  background: color-mix(in srgb, var(--risk-high) 12%, transparent);
  color: var(--risk-high);
  border-color: color-mix(in srgb, var(--risk-high) 25%, transparent);
}
.issue-tag.dark-red {
  background: color-mix(in srgb, var(--risk-critical) 12%, transparent);
  color: var(--risk-critical);
  border-color: color-mix(in srgb, var(--risk-critical) 25%, transparent);
}
.issue-tag.orange {
  background: color-mix(in srgb, var(--risk-medium) 12%, transparent);
  color: var(--risk-medium);
  border-color: color-mix(in srgb, var(--risk-medium) 25%, transparent);
}
.issue-tag.yellow {
  background: color-mix(in srgb, var(--risk-low) 12%, transparent);
  color: var(--risk-low);
  border-color: color-mix(in srgb, var(--risk-low) 25%, transparent);
}
.issue-tag.blue-network {
  background: color-mix(in srgb, #3b82f6 12%, transparent);
  color: #3b82f6;
  border-color: color-mix(in srgb, #3b82f6 25%, transparent);
}
.issue-tag.purple-geo {
  background: color-mix(in srgb, #8b5cf6 12%, transparent);
  color: #8b5cf6;
  border-color: color-mix(in srgb, #8b5cf6 25%, transparent);
}
.issue-tag.green-ok {
  background: color-mix(in srgb, var(--risk-indicator-normal) 12%, transparent);
  color: var(--risk-indicator-normal);
  border-color: color-mix(in srgb, var(--risk-indicator-normal) 25%, transparent);
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

.row-expandable {
  cursor: pointer;
  user-select: none;
}

.alertas-diarios-row,
.premium-table.row-hover tbody tr.alertas-diarios-row:hover {
  background: transparent !important;
  cursor: default !important;
}
.alertas-diarios-table tr:hover {
  background: transparent !important;
}

.alertas-diarios-cell {
  padding: 0.75rem 1rem !important;
  border-bottom: 2px solid var(--tabs-border) !important;
  background: transparent !important;
}

.alertas-wrapper {
  background: v-bind(raioxBg);
  backdrop-filter: blur(8px);
  -webkit-backdrop-filter: blur(8px);
  border: 1px solid var(--card-border);
  border-left: 3px solid color-mix(in srgb, var(--risk-high) 50%, transparent);
  border-radius: 8px;
  overflow: hidden;
}

.alertas-diarios-table {
  width: 100%;
  border-collapse: collapse;
  background: transparent;
  font-size: 0.78rem;
}

.alertas-diarios-table thead tr {
  background: color-mix(in srgb, var(--text-color) 4%, transparent);
}

.alertas-diarios-table th {
  padding: 0.35rem 0.75rem;
  font-size: 0.7rem;
  font-weight: 600;
  color: var(--text-secondary);
  text-transform: uppercase;
  letter-spacing: 0.04em;
  text-align: left;
}

.alertas-diarios-table td {
  padding: 0.4rem 0.75rem;
  border-top: 1px solid var(--tabs-border);
  color: var(--text-color);
  opacity: 0.8;
}

.col-date { font-weight: 400; white-space: nowrap; }
.col-crm { white-space: nowrap; color: var(--text-secondary); font-size: 0.75rem; }
.col-descricao { color: var(--text-secondary); font-size: 0.75rem; }
.col-descricao .desc-num { color: var(--primary-color); font-weight: 500; }
.col-descricao .desc-janela { color: var(--risk-high); font-weight: 500; }

.nivel-badge {
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
  border: 1px solid transparent;
}

.nivel-badge.nivel-autorizacoes-em-sequencia {
  background: color-mix(in srgb, var(--risk-high) 10%, var(--tabs-bg));
  color: var(--risk-high);
  border-color: color-mix(in srgb, var(--risk-high) 20%, transparent);
}

.bar-container {
  position: relative;
  height: 1.2rem;
  background: rgba(0, 0, 0, 0.06);
  border-radius: 6px;
  overflow: hidden;
  display: flex;
  align-items: center;
  min-width: 45px;
  border: 1px solid rgba(128, 128, 128, 0.12);
  box-shadow: inset 0 1px 3px rgba(0, 0, 0, 0.08);
}
:global(.dark-mode) .bar-container {
  background: rgba(255, 255, 255, 0.07);
  border-color: rgba(255, 255, 255, 0.06);
}
.bar-fill {
  position: absolute;
  top: 0;
  left: 0;
  bottom: 0;
  border-radius: 0 5px 5px 0;
  transition: width 0.5s cubic-bezier(0.4, 0, 0.2, 1);
}
.bar-fill::after {
  content: '';
  position: absolute;
  inset: 0;
  background: linear-gradient(
    to bottom,
    rgba(255, 255, 255, 0.28) 0%,
    rgba(255, 255, 255, 0.04) 55%,
    rgba(0, 0, 0, 0.06) 100%
  );
  border-radius: inherit;
  pointer-events: none;
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

.daily-chart-wrapper {
  display: flex;
  flex-direction: column;
  gap: 0;
}

.chart-legend-html {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 1.25rem;
  padding: 0.35rem 0;
}

.legend-item {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  font-size: 0.72rem;
  color: var(--text-secondary);
}

.legend-swatch {
  width: 14px;
  height: 8px;
  border-radius: 2px;
  display: inline-block;
  flex-shrink: 0;
}

.legend-dashed {
  background: none;
  border-top: 2px dashed #f59e0b;
  height: 0;
  width: 18px;
  border-radius: 0;
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
