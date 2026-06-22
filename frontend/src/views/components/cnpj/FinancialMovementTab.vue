<script setup>
import { computed, ref } from 'vue';
import { useRoute } from 'vue-router';
import { useCnpjDetailStore } from '@/stores/cnpjDetail';
import { storeToRefs } from 'pinia';
import { useStableTabState } from '@/composables/useStableTabState';
import { useFormatting } from '@/composables/useFormatting';
import { useChartTheme } from '@/config/chartTheme';
import { RISK_THRESHOLDS, AUDIT_THRESHOLDS } from '@/config/riskConfig';
import { useFilterStore } from '@/stores/filters';

import VChart from 'vue-echarts';
import { use } from 'echarts/core';
import { BarChart } from 'echarts/charts';
import { GridComponent, TooltipComponent, LegendComponent, DataZoomComponent, MarkPointComponent, MarkAreaComponent } from 'echarts/components';
import { CanvasRenderer } from 'echarts/renderers';

import DataTable from 'primevue/datatable';
import Column from 'primevue/column';
import ColumnGroup from 'primevue/columngroup';
import Row from 'primevue/row';
import Button from 'primevue/button';
import Dialog from 'primevue/dialog';
import GtinDetalhamentoMensalSidebar from './GtinDetalhamentoMensalSidebar.vue';
import TabPlaceholder from './TabPlaceholder.vue';

use([BarChart, GridComponent, TooltipComponent, LegendComponent, DataZoomComponent, MarkPointComponent, MarkAreaComponent, CanvasRenderer]);

const route = useRoute();
const cnpj = computed(() => route.params.cnpj);

const { formatCurrencyFull, formatarData, toLocalISO, formatTitleCase } = useFormatting();
const filterStore = useFilterStore();

const formattedPeriod = computed(() => {
  const [start, end] = filterStore.periodo ?? [];
  if (!start || !end) return null;
  return { start: formatarData(toLocalISO(start)), end: formatarData(toLocalISO(end)) };
});
const { chartTheme, chartDataColors, chartUFAccents } = useChartTheme();

const cnpjDetailStore = useCnpjDetailStore();
const { evolucaoFinanceira: evolucaoData, evolucaoLoading, evolucaoLoaded, evolucaoError, evolucaoMensalGtin, evolucaoMensalGtinLoading, repassesData, repassesLoading, repassesLoaded, repassesError } = storeToRefs(cnpjDetailStore);

// ── Cache de Dados para Transição Suave (Flicker-Free) ──────────────────
const {
  cachedData: cachedEvolucaoData,
  isRefreshing,
} = useStableTabState(evolucaoData, evolucaoLoading, evolucaoError);

const {
  cachedData: cachedRepassesData,
  isRefreshing: isRepassesRefreshing,
} = useStableTabState(repassesData, repassesLoading, repassesError);

const auditHighValue = AUDIT_THRESHOLDS.HIGH_VALUE;
const hoveredSemestreRepasses = ref(null);
const selectedSemestreRepasses = ref(null);

const REPASSES_SCOPE_TOOLTIP =
  'Repasses consolidados do Programa Farmácia Popular (escopo total). '
  + 'Não correspondem à movimentação analisada pelo Sentinela, que exclui itens como fraldas e absorventes. '
  + 'Os pagamentos costumam ocorrer com defasagem em relação à produção.';

const repassesResumo = computed(() => cachedRepassesData.value?.resumo ?? null);
const repassesMensal = computed(() => cachedRepassesData.value?.mensal ?? []);
const repassesPagamentos = computed(() => cachedRepassesData.value?.pagamentos ?? []);

function semestreFromMes(mesStr) {
  if (!mesStr) return '';
  const [year, month] = mesStr.split('-').map(Number);
  return `${month <= 6 ? 1 : 2}S/${year}`;
}

function semestreFromDataPagamento(dateStr) {
  if (!dateStr) return '';
  const iso = String(dateStr).slice(0, 10);
  const [year, month] = iso.split('-').map(Number);
  return `${month <= 6 ? 1 : 2}S/${year}`;
}

const repassesSemestres = computed(() => {
  const buckets = new Map();

  for (const row of repassesPagamentos.value) {
    const semestre = semestreFromDataPagamento(row.data_pagamento);
    if (!semestre) continue;

    if (!buckets.has(semestre)) {
      buckets.set(semestre, {
        semestre,
        valor_repassado: 0,
        ordens: new Set(),
        meses: new Set(),
      });
    }

    const bucket = buckets.get(semestre);
    bucket.valor_repassado += row.valor_pago ?? 0;
    if (row.numero_ordem_bancaria) bucket.ordens.add(row.numero_ordem_bancaria);
    bucket.meses.add(String(row.data_pagamento).slice(0, 7));
  }

  return [...buckets.values()]
    .map((bucket) => {
      const mesesOrdenados = [...bucket.meses].sort();
      return {
        semestre: bucket.semestre,
        valor_repassado: parseFloat(bucket.valor_repassado.toFixed(2)),
        qtd_ordens: bucket.ordens.size,
        mes_inicio: mesesOrdenados[0] ?? null,
        mes_fim: mesesOrdenados.at(-1) ?? null,
      };
    })
    .sort((a, b) => {
      const parseSemestre = (semestre) => {
        const [semPart, yearPart] = semestre.split('S/');
        return [Number(yearPart), Number(semPart)];
      };
      const [yearA, semA] = parseSemestre(a.semestre);
      const [yearB, semB] = parseSemestre(b.semestre);
      if (yearA !== yearB) return yearA - yearB;
      return semA - semB;
    });
});

const repassesMensalComSemestre = computed(() =>
  repassesMensal.value.map((item) => ({
    ...item,
    semestre: semestreFromMes(item.mes),
  })),
);

function onRepassesSemestreAxisPointerUpdate(event) {
  if (event.axesInfo?.[0]) {
    const idx = event.axesInfo[0].value;
    const semestres = repassesSemestres.value;
    if (semestres[idx]) {
      hoveredSemestreRepasses.value = semestres[idx].semestre;
    }
  }
}

function onRepassesSemestreChartMouseOut() {
  hoveredSemestreRepasses.value = null;
}

function onRepassesSemestreClick() {
  const semestre = hoveredSemestreRepasses.value;
  if (!semestre) return;
  selectedSemestreRepasses.value = selectedSemestreRepasses.value === semestre ? null : semestre;
}

function limparFiltroRepasses() {
  selectedSemestreRepasses.value = null;
}

const repassesPagamentosFiltrados = computed(() => {
  if (!selectedSemestreRepasses.value) return [];
  return repassesPagamentos.value.filter(
    row => semestreFromDataPagamento(row.data_pagamento) === selectedSemestreRepasses.value,
  );
});

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

const isMonthlyChartExpanded = ref(false);
const hoveredSemestre = ref(null);

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
}

/**
 * Disparado ao clicar em qualquer lugar do gráfico (incluindo o axisPointer).
 * Usamos a variável hoveredSemestre que já rastreia a posição do cursor.
 */
function onZrClick() {
  const semestre = hoveredSemestre.value;
  if (!semestre) return;
  
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

/**
 * Formata o semestre (ex: "1S/2024") para um modo amigável (ex: "1º Semestre de 2024").
 */
function formatSemestreLabel(semStr) {
  if (!semStr) return '';
  // Formato "1S/2015"
  if (semStr.includes('S/')) {
    const [s, year] = semStr.split('S/');
    return `${s}º Semestre de ${year}`;
  }
  // Formato "2015-S1"
  if (semStr.includes('-S')) {
    const [year, s] = semStr.split('-S');
    const semNum = s.replace('S', '');
    return `${semNum}º Semestre de ${year}`;
  }
  return semStr;
}

function formatSemestreKey(chave) {
  if (!chave) return '';
  const key = String(chave);
  const year = key.slice(0, 4);
  const sem = key.slice(4);
  return `${Number(sem)}º Semestre de ${year}`;
}

function formatGrowthPct(value) {
  if (value == null) return '';
  return `+${Number(value).toLocaleString('pt-BR', {
    minimumFractionDigits: 0,
    maximumFractionDigits: 1,
  })}%`;
}

function formatPositiveCurrency(value) {
  if (value == null) return '';
  return `+${formatCurrencyFull(value)}`;
}

const insightSidebarVisible = ref(false);
const insightSelectedPeriod = ref(null);

function abrirInfratores(mes) {
  insightSelectedPeriod.value = mes;
  insightSidebarVisible.value = true;
}

// Ao clicar em uma barra do gráfico mensal, seleciona o semestre e abre o detalhamento.
function getPeriodoFromMensalChartClick(params) {
  if (params?.name) return params.name;
  if (params?.dataIndex == null) return null;
  return todosMeses.value[params.dataIndex]?.mes ?? null;
}

function onMensalChartClick(params) {
  const mesStr = getPeriodoFromMensalChartClick(params);
  if (!mesStr) return;
  const semestres = cachedEvolucaoData.value?.semestres ?? [];
  const sem = semestres.find(s => mesPertenceAoSemestre(mesStr, s.semestre));
  if (sem) selectedSemestre.value = sem;
  abrirInfratores(mesStr);
}

// Hover sync: disparado quando o cursor entra na área de uma categoria (quadro translúcido)
function onAxisPointerUpdate(event) {
  if (event.axesInfo && event.axesInfo[0]) {
    const idx = event.axesInfo[0].value;
    const semestres = cachedEvolucaoData.value?.semestres ?? [];
    if (semestres[idx]) {
      hoveredSemestre.value = semestres[idx].semestre;
    }
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
  const semestresAtipicos = semestres.filter(s => s.volume_atipico && s.taxa_crescimento_pct != null);
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
      confine: true,
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
        const volumeAtipicoSection = s.volume_atipico ? `
          <div style="margin-top:10px;border-top:1px solid ${c.tooltipBorder};padding-top:8px;">
            <div style="display:flex;align-items:center;gap:8px;margin-bottom:6px;">
              <span style="width:10px;height:10px;border-radius:999px;background:#f59e0b;display:inline-block;"></span>
              <span style="font-size:10px;opacity:.75;letter-spacing:.04em;text-transform:uppercase;font-weight:700;">Aumento semestral atípico</span>
            </div>
            <div style="display:flex;justify-content:space-between;gap:18px;font-size:12px;margin-bottom:4px;">
              <span style="opacity:.68;">Crescimento</span>
              <strong style="color:#f59e0b;">${formatGrowthPct(s.taxa_crescimento_pct)}</strong>
            </div>
            <div style="display:flex;justify-content:space-between;gap:18px;font-size:12px;margin-bottom:4px;">
              <span style="opacity:.68;">Aumento em valor</span>
              <strong style="color:#f59e0b;">${formatPositiveCurrency(s.aumento_valor_semestre) || '—'}</strong>
            </div>
            <div style="display:flex;justify-content:space-between;gap:18px;font-size:12px;margin-bottom:4px;">
              <span style="opacity:.68;">Comparado a</span>
              <strong>${formatSemestreKey(s.chave_semestre_anterior) || 'semestre anterior válido'}</strong>
            </div>
            <div style="display:flex;justify-content:space-between;gap:18px;font-size:12px;margin-bottom:4px;">
              <span style="opacity:.68;">Aumento mínimo para alerta</span>
              <strong>${formatCurrencyFull(s.limite_aumento_volume_atipico ?? 10000)}</strong>
            </div>
            <div style="display:flex;justify-content:space-between;gap:18px;font-size:12px;">
              <span style="opacity:.68;">Meses com movimentação</span>
              <strong>${s.qtd_meses_presentes ?? '—'}</strong>
            </div>
          </div>` : '';
        return `
          <div style="color: ${c.tooltipText}">
            <div style="font-weight:700;font-size:14px;margin-bottom:10px;">${formatSemestreLabel(s.semestre)}</div>
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
              ${volumeAtipicoSection}
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
        markPoint: {
          symbol: 'triangle',
          symbolSize: 13,
          symbolOffset: [0, -6],
          label: {
            show: true,
            position: 'top',
            distance: 6,
            color: '#f59e0b',
            fontSize: 12,
            fontWeight: 800,
            formatter: (p) => p.data.growthLabel,
          },
          itemStyle: {
            color: '#f59e0b',
            borderColor: '#fff7ed',
            borderWidth: 1,
          },
          data: semestresAtipicos.map(s => ({
            name: 'Aumento semestral atípico',
            coord: [s.semestre, s.total],
            value: s.taxa_crescimento_pct,
            growthLabel: formatGrowthPct(s.taxa_crescimento_pct),
          })),
        },
        markArea: {
          silent: true,
          itemStyle: { color: 'rgba(245, 158, 11, 0.08)' },
          data: semestresAtipicos.map(s => ([
            { xAxis: s.semestre },
            { xAxis: s.semestre },
          ])),
        },
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
      confine: true,
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
            <div style="font-weight:600;font-size:13px;margin-bottom:8px;">${formatMesLabel(m.mes)} <span style="opacity: 0.5; font-size: 11px;">(${formatSemestreLabel(m.semestre)})</span></div>
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

function chartOptionRepassesSemestre() {
  const c = C.value;
  const accents = chartUFAccents.value;
  const semestres = repassesSemestres.value;
  const labels = semestres.map((item) => item.semestre);

  const isSemestreSelecionado = (semestre) => !selectedSemestreRepasses.value || semestre === selectedSemestreRepasses.value;

  const valores = semestres.map((item) => ({
    value: parseFloat((item.valor_repassado ?? 0).toFixed(2)),
    itemStyle: {
      opacity: hoveredSemestreRepasses.value
        ? (item.semestre === hoveredSemestreRepasses.value ? 1 : 0.35)
        : (isSemestreSelecionado(item.semestre) ? 1 : 0.35),
    },
    emphasis: {
      itemStyle: {
        opacity: isSemestreSelecionado(item.semestre) ? 1 : 0.35,
      },
    },
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
      confine: true,
      axisPointer: { type: 'shadow', shadowStyle: { color: c.axisShadow } },
      backgroundColor: c.tooltip,
      borderColor: c.tooltipBorder,
      borderWidth: 1,
      padding: [12, 16],
      textStyle: { color: c.tooltipText, fontFamily: 'Inter, sans-serif', fontSize: 12 },
      formatter: (params) => {
        const idx = params[0]?.dataIndex ?? 0;
        const item = semestres[idx];
        if (!item) return '';
        const mesRange = formatMesRange(item.mes_inicio, item.mes_fim);
        return `
          <div style="color:${c.tooltipText}">
            <div style="font-weight:700;font-size:14px;margin-bottom:10px;">${formatSemestreLabel(item.semestre)}</div>
            <div style="display:flex;justify-content:space-between;gap:18px;font-size:12px;margin-bottom:4px;">
              <span style="opacity:.68;">Valor repassado</span>
              <strong>${formatCurrencyFull(item.valor_repassado)}</strong>
            </div>
            <div style="display:flex;justify-content:space-between;gap:18px;font-size:12px;margin-bottom:4px;">
              <span style="opacity:.68;">Ordens bancárias</span>
              <strong>${item.qtd_ordens ?? 0}</strong>
            </div>
            ${mesRange ? `<div style="font-size:11px;opacity:.65;margin-top:6px;">Meses com pagamento: ${mesRange}</div>` : ''}
          </div>`;
      },
    },

    xAxis: {
      type: 'category',
      data: labels,
      axisLine: { lineStyle: { color: c.grid } },
      axisTick: { show: false },
      axisLabel: { color: c.muted, fontSize: 11, fontWeight: 700, fontFamily: 'Inter, sans-serif' },
    },

    yAxis: {
      type: 'value',
      axisLine: { show: false },
      axisTick: { show: false },
      splitLine: { lineStyle: { color: c.grid, type: 'dashed' } },
      axisLabel: { color: c.muted, fontSize: 10, formatter: (v) => formatCurrencyFull(v) },
    },

    series: [
      {
        name: 'Repasses',
        type: 'bar',
        barMaxWidth: 56,
        data: valores,
itemStyle: {
           borderRadius: [6, 6, 0, 0],
           color: {
             type: 'linear',
             x: 0,
             y: 0,
             x2: 0,
             y2: 1,
             colorStops: [
               { offset: 0, color: accents.bar1 },
               { offset: 1, color: accents.bar1Grad },
             ],
           },
         },
         emphasis: { disabled: false },
       },
    ],
  };
}

function chartOptionRepassesMensal(showZoom = false) {
  const c = C.value;
  const accents = chartUFAccents.value;
  const meses = repassesMensalComSemestre.value;
  const labels = meses.map((item) => item.mes);

  const isMesSelecionadoRepasse = (semestre) => !selectedSemestreRepasses.value || semestre === selectedSemestreRepasses.value;

  const valores = meses.map((item) => ({
    value: parseFloat((item.valor_repassado ?? 0).toFixed(2)),
    itemStyle: {
      opacity: hoveredSemestreRepasses.value
        ? (item.semestre === hoveredSemestreRepasses.value ? 1 : 0.25)
        : (isMesSelecionadoRepasse(item.semestre) ? 1 : 0.25),
    },
  }));

  return {
    backgroundColor: 'transparent',
    animation: !hoveredSemestreRepasses.value,
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

    grid: { top: 36, left: 64, right: 16, bottom: showZoom ? 52 : 32, containLabel: false },

    tooltip: {
      trigger: 'axis',
      confine: true,
      axisPointer: { type: 'shadow', shadowStyle: { color: c.axisShadow } },
      backgroundColor: c.tooltip,
      borderColor: c.tooltipBorder,
      borderWidth: 1,
      padding: [10, 14],
      textStyle: { color: c.tooltipText, fontFamily: 'Inter, sans-serif', fontSize: 12 },
      formatter: (params) => {
        const idx = params[0]?.dataIndex ?? 0;
        const item = meses[idx];
        if (!item) return '';
        return `
          <div style="color:${c.tooltipText}">
            <div style="font-weight:600;font-size:13px;margin-bottom:8px;">
              ${formatMesLabel(item.mes)}
              <span style="opacity:0.5;font-size:11px;">(${formatSemestreLabel(item.semestre)})</span>
            </div>
            <div style="display:flex;justify-content:space-between;gap:18px;font-size:12px;margin-bottom:4px;">
              <span style="opacity:.68;">Valor repassado</span>
              <strong>${formatCurrencyFull(item.valor_repassado)}</strong>
            </div>
            <div style="display:flex;justify-content:space-between;gap:18px;font-size:12px;">
              <span style="opacity:.68;">Ordens bancárias</span>
              <strong>${item.qtd_ordens ?? 0}</strong>
            </div>
          </div>`;
      },
    },

    xAxis: {
      type: 'category',
      data: labels,
      axisLine: { lineStyle: { color: c.grid } },
      axisTick: { show: false },
      axisLabel: {
        color: c.muted,
        fontSize: 10,
        fontFamily: 'Inter, sans-serif',
        formatter: formatMesLabel,
        interval: 'auto',
        rotate: 30,
      },
    },

    yAxis: {
      type: 'value',
      axisLine: { show: false },
      axisTick: { show: false },
      splitLine: { lineStyle: { color: c.grid, type: 'dashed' } },
      axisLabel: { color: c.muted, fontSize: 9, formatter: (v) => formatCurrencyFull(v) },
    },

    dataZoom: showZoom ? [
      { type: 'inside', start: 0, end: 100, zoomLock: false },
      {
        type: 'slider',
        start: 0,
        end: 100,
        height: 14,
        bottom: 4,
        borderColor: c.grid,
        fillerColor: c.axisShadow,
        handleStyle: { color: c.muted },
        textStyle: { color: 'transparent' },
      },
    ] : [],

    series: [
      {
        name: 'Repasses',
        type: 'bar',
        barMaxWidth: 40,
        data: valores,
        itemStyle: {
          borderRadius: [4, 4, 0, 0],
          color: {
            type: 'linear',
            x: 0,
            y: 0,
            x2: 0,
            y2: 1,
            colorStops: [
              { offset: 0, color: accents.bar1 },
              { offset: 1, color: accents.bar1Grad },
            ],
          },
        },
        emphasis: { focus: 'series' },
      },
    ],
  };
}

const repassesSemestreChartOption = computed(() => chartOptionRepassesSemestre());
const repassesMensalChartOption = computed(() => chartOptionRepassesMensal(false));

</script>

<template>
  <div class="tab-content evolucao-tab">
    <div
      v-if="evolucaoLoading && !cachedEvolucaoData && !evolucaoError"
      class="evolucao-initial-loading-sentinel"
      aria-hidden="true"
    />

    <TabPlaceholder
      v-else-if="evolucaoError"
      variant="error"
      icon="pi-exclamation-circle"
      title="Erro ao carregar"
      :description="evolucaoError"
    />

    <TabPlaceholder
      v-else-if="evolucaoLoaded && !cachedEvolucaoData?.semestres?.length"
      variant="info"
      icon="pi-chart-bar"
      title="Sem movimentação no período"
    >
      <template #description>
        Não foram encontradas movimentações financeiras para este CNPJ no período de <u>{{ formattedPeriod?.start }}</u> até <u>{{ formattedPeriod?.end }}</u>.
      </template>
    </TabPlaceholder>

    <template v-else-if="cachedEvolucaoData">
      <div class="evolucao-card evolucao-card-highlight repasses-section" :class="{ 'is-refreshing': isRefreshing }">
        <div class="evolucao-card-header">
          <div class="header-title">
            <i class="pi pi-chart-bar" />
            <span>Volume de Vendas por Semestre</span>
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
        <div class="evolucao-chart-wrap" :class="{ 'is-hovering-axis': hoveredSemestre }" @mouseleave="onChartMouseOut">
          <VChart 
            ref="chartRef" 
            :option="chartOption" 
            :update-options="{ notMerge: false, lazyUpdate: true }" 
            autoresize 
            class="evolucao-chart" 
            @zr:click="onZrClick" 
            @updateAxisPointer="onAxisPointerUpdate"
          />
        </div>
      </div>

      <!-- Card permanente: Volume de Vendas Mensal -->
      <div class="evolucao-card evolucao-card-highlight repasses-section" :class="{ 'is-refreshing': isRefreshing }">
        <div class="evolucao-card-header">
          <div class="header-title">
            <i class="pi pi-chart-bar" />
            <span>Volume de Vendas Mensal</span>
          </div>
          <div class="header-actions">
            <span v-if="selectedSemestre" class="sem-badge">
              <i class="pi pi-star-fill" />
              {{ formatSemestreLabel(selectedSemestre.semestre) }}
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
        <div v-if="todosMeses.length" class="evolucao-chart-wrap mensal-chart-clickable">
          <VChart
            :option="mensalChartOption"
            :update-options="{ notMerge: false, lazyUpdate: true }"
            autoresize
            class="evolucao-chart"
            @click="onMensalChartClick"
          />
        </div>
        <TabPlaceholder
          v-else
          variant="loading"
          title="Carregando dados mensais"
        />
      </div>

      <!-- Painel contextual: detalhe do semestre selecionado -->
      <Transition name="context-slide">
        <div v-if="selectedSemestre" class="evolucao-card evolucao-card-highlight context-detail-card">
          <div class="evolucao-card-header">
            <div class="header-title">
              <i class="pi pi-calendar-clock" />
              <span>{{ formatSemestreLabel(selectedSemestre.semestre) }} — Detalhamento Mensal</span>
            </div>
            <div class="header-actions">
              <button class="btn-close-context" @click="limparFiltro" title="Fechar">
                <i class="pi pi-times" />
              </button>
            </div>
          </div>
          <DataTable 
            :value="selectedSemestre.meses ?? []" 
            class="sanfona-table p-datatable-sm" 
            :show-gridlines="false"
            @row-click="(e) => abrirInfratores(e.data.mes)"
          >
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
                <div class="pct-cell" style="text-align: right; padding: 0;">
                  <div class="pct-bar-wrap">
                    <div
                      class="pct-bar"
                      :style="{
                        width: Math.min(m.pct_irregular, 100) + '%',
                        background: m.pct_irregular >= RISK_THRESHOLDS.CRITICAL ? 'var(--risk-critical)'
                                  : m.pct_irregular >= RISK_THRESHOLDS.HIGH     ? 'var(--risk-high)'
                                  : m.pct_irregular >= RISK_THRESHOLDS.MEDIUM   ? 'var(--risk-medium)'
                                  : 'var(--risk-low)'
                      }"
                    />
                  </div>
                  <span class="pct-value" :class="{
                    'pct-critical': m.pct_irregular >= RISK_THRESHOLDS.CRITICAL,
                    'pct-high':     m.pct_irregular >= RISK_THRESHOLDS.HIGH     && m.pct_irregular < RISK_THRESHOLDS.CRITICAL,
                    'pct-medium':   m.pct_irregular >= RISK_THRESHOLDS.MEDIUM   && m.pct_irregular < RISK_THRESHOLDS.HIGH,
                    'pct-low':      m.pct_irregular < RISK_THRESHOLDS.MEDIUM,
                  }">{{ m.pct_irregular.toFixed(1) }}%</span>
                </div>
              </template>
            </Column>
            <Column style="width: 5%">
              <template #body="{ data: m }">
                <Button
                  icon="pi pi-search-plus"
                  class="p-button-text p-button-sm p-button-rounded p-button-danger btn-insight"
                  v-tooltip.left="'Ver mais detalhes'"
                  @click="abrirInfratores(m.mes)"
                />
              </template>
            </Column>
          </DataTable>
        </div>
      </Transition>



      <!-- Modal de Zoom do Histórico Mensal -->
      <Dialog 
        v-model:visible="isMonthlyChartExpanded" 
        modal 
        header="Volume de Vendas Mensal (Detalhamento)" 
        :style="{ width: '90vw', maxWidth: '1400px' }"
        :breakpoints="{ '960px': '95vw' }"
        class="evolucao-zoom-dialog"
      >
        <div style="height: 65vh; min-height: 450px; padding: 1rem 0;">
          <VChart
            v-if="isMonthlyChartExpanded"
            :option="chartOptionMensalGtin(selectedSemestre?.semestre, true)"
            :update-options="{ notMerge: false, lazyUpdate: true }"
            autoresize
            style="width: 100%; height: 100%;"
            @click="onMensalChartClick"
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

    <!-- Repasses: bloco autônomo, sem comparativo com movimentação -->
    <div v-if="repassesLoading || repassesLoaded" class="repasses-block">
      <p class="repasses-scope-note">
        <i class="pi pi-wallet repasses-scope-leading-icon" />
        Repasses consolidados do Tesouro (escopo total do Programa).
        <i
          class="pi pi-info-circle repasses-scope-icon"
          v-tooltip.bottom="REPASSES_SCOPE_TOOLTIP"
        />
      </p>

      <TabPlaceholder
        v-if="repassesError"
        variant="error"
        icon="pi-exclamation-circle"
        title="Repasses indisponíveis"
        :description="repassesError"
      />

      <TabPlaceholder
        v-else-if="repassesLoaded && !repassesMensal.length"
        variant="info"
        icon="pi-wallet"
        title="Sem repasses no período"
      >
        <template #description>
          Não foram encontrados repasses para este CNPJ entre
          <u>{{ formattedPeriod?.start }}</u> e <u>{{ formattedPeriod?.end }}</u>.
        </template>
      </TabPlaceholder>

      <template v-else-if="repassesResumo">
        <div class="repasses-kpi-grid">
          <div class="repasses-kpi-item">
            <span class="repasses-kpi-label">Total repassado</span>
            <span class="repasses-kpi-value">{{ formatCurrencyFull(repassesResumo.total_repassado) }}</span>
          </div>
          <div class="repasses-kpi-item">
            <span class="repasses-kpi-label">Ordens bancárias</span>
            <span class="repasses-kpi-value">{{ repassesResumo.qtd_ordens ?? 0 }}</span>
          </div>
          <div class="repasses-kpi-item">
            <span class="repasses-kpi-label">Maior repasse</span>
            <span
              class="repasses-kpi-value"
              :class="{ 'high-value-audit': (repassesResumo.maior_repasse ?? 0) >= auditHighValue }"
            >
              {{ formatCurrencyFull(repassesResumo.maior_repasse) }}
            </span>
          </div>
          <div class="repasses-kpi-item">
            <span class="repasses-kpi-label">Último repasse</span>
            <span class="repasses-kpi-value repasses-kpi-last">
              <template v-if="repassesResumo.ultimo_repasse_data">
                {{ formatarData(repassesResumo.ultimo_repasse_data) }}
                ·
                {{ formatCurrencyFull(repassesResumo.ultimo_repasse_valor) }}
              </template>
              <template v-else>—</template>
            </span>
          </div>
        </div>

        <div
          class="evolucao-card evolucao-card-highlight repasses-section"
          :class="{ 'is-refreshing': isRepassesRefreshing }"
        >
          <div class="evolucao-card-header">
            <div class="header-title">
              <i class="pi pi-wallet" />
              <span>Repasses por Semestre</span>
            </div>
            <div class="header-actions">
              <i v-if="repassesLoading" class="pi pi-spin pi-spinner refresh-spinner" />
            </div>
          </div>
          <div
            v-if="repassesSemestres.length"
            class="evolucao-chart-wrap"
            :class="{ 'is-hovering-axis': hoveredSemestreRepasses }"
            @mouseleave="onRepassesSemestreChartMouseOut"
          >
            <VChart
              :option="repassesSemestreChartOption"
              :update-options="{ notMerge: false, lazyUpdate: true }"
              autoresize
              class="evolucao-chart"
              @updateAxisPointer="onRepassesSemestreAxisPointerUpdate"
              @zr:click="onRepassesSemestreClick"
            />
          </div>
        </div>

        <div
          class="evolucao-card evolucao-card-highlight repasses-section"
          :class="{ 'is-refreshing': isRepassesRefreshing }"
        >
<div class="evolucao-card-header">
             <div class="header-title">
               <i class="pi pi-wallet" />
               <span>Histórico Mensal de Repasses</span>
             </div>
             <div class="header-actions">
               <span v-if="selectedSemestreRepasses" class="sem-badge">
                 <i class="pi pi-star-fill" />
                 {{ formatSemestreLabel(selectedSemestreRepasses) }}
               </span>
               <Button
                 v-if="selectedSemestreRepasses"
                 icon="pi pi-filter-slash"
                 label="Limpar Filtro"
                 class="p-button-text p-button-sm btn-clear-filter"
                 @click="limparFiltroRepasses"
               />
               <i v-if="repassesLoading" class="pi pi-spin pi-spinner refresh-spinner" />
             </div>
           </div>
          <div v-if="repassesMensal.length" class="evolucao-chart-wrap">
            <VChart
              :option="repassesMensalChartOption"
              :update-options="{ notMerge: false, lazyUpdate: true }"
              autoresize
              class="evolucao-chart"
            />
          </div>
        </div>

        <!-- Painel contextual: ordens bancárias do semestre selecionado -->
        <Transition name="context-slide">
          <div v-if="selectedSemestreRepasses" class="evolucao-card evolucao-card-highlight context-detail-card repasses-section">
            <div class="evolucao-card-header">
              <div class="header-title">
                <i class="pi pi-calendar-clock" />
                <span>{{ formatSemestreLabel(selectedSemestreRepasses) }} — Detalhamento Mensal de Repasses</span>
              </div>
              <div class="header-actions">
                <button class="btn-close-context" @click="limparFiltroRepasses" title="Fechar">
                  <i class="pi pi-times" />
                </button>
              </div>
            </div>
            <DataTable
              :value="repassesPagamentosFiltrados"
              class="evolucao-table repasses-table"
              :show-gridlines="false"
            >
              <Column field="data_pagamento" header="Data Pagamento" style="width: 18%">
                <template #body="{ data: row }">
                  {{ formatarData(row.data_pagamento) }}
                </template>
              </Column>
<Column field="programa_acao" header="Programa" style="width: 14%">
                 <template #body="{ data: row }">
                   {{ row.programa_acao ? formatTitleCase(row.programa_acao) : '—' }}
                 </template>
               </Column>
              <Column field="numero_ordem_bancaria" header="Ordem Bancária" style="width: 38%">
                <template #body="{ data: row }">
                  {{ formatTitleCase(row.numero_ordem_bancaria) }}
                </template>
              </Column>
              <Column field="valor_pago" header="Valor Pago" style="width: 30%">
                <template #body="{ data: row }">
                  <span :class="{ 'high-value-audit': row.valor_pago >= auditHighValue }">
                    {{ formatCurrencyFull(row.valor_pago) }}
                  </span>
                </template>
              </Column>
              <ColumnGroup type="footer">
                <Row>
                  <Column footer="TOTAL" footerStyle="text-align: left; font-weight: 600;" :colspan="3" />
                  <Column :footer="formatCurrencyFull(repassesPagamentosFiltrados.reduce((a, r) => a + (r.valor_pago ?? 0), 0))" />
                </Row>
              </ColumnGroup>
            </DataTable>
          </div>
        </Transition>
      </template>
    </div>

    <GtinDetalhamentoMensalSidebar
      v-model:visible="insightSidebarVisible"
      :cnpj="cnpj"
      :periodo="insightSelectedPeriod"
      :minPeriodo="todosMeses[0]?.mes"
      :maxPeriodo="todosMeses[todosMeses.length - 1]?.mes"
    />
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
  color: var(--text-color-85);
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


:deep(.p-datatable.evolucao-table) { font-size: 0.82rem; background: transparent; }
:deep(.p-datatable.evolucao-table .p-datatable-wrapper) { background: transparent; }

:deep(.p-datatable.evolucao-table .p-datatable-tbody > tr) {
  background: transparent;
  color: var(--text-color-85);
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
:deep(.p-datatable.evolucao-table .p-datatable-tbody > tr:hover > td) {
  background: var(--table-hover);
}
:deep(.p-datatable.evolucao-table .p-datatable-tfoot > tr > td) {
  text-align: right; 
  border-top: 2px solid var(--tabs-border) !important; 
  border-bottom: none !important; 
  background: color-mix(in srgb, var(--tabs-bg) 95%, var(--text-color-85) 5%); 
  font-weight: 600;
  color: var(--text-color-85);
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
  background: color-mix(in srgb, var(--card-bg) 95%, var(--text-color-85) 5%);
}


:deep(.sanfona-table.p-datatable) { background: transparent; }
:deep(.sanfona-table.p-datatable .p-datatable-tbody > tr) { 
  background: transparent; 
  cursor: pointer;
  transition: all 0.2s ease;
}
:deep(.sanfona-table.p-datatable .p-datatable-tbody > tr:hover > td) { 
  background: color-mix(in srgb, var(--primary-color) 10%, transparent) !important; 
}
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


.mensal-gtin-chart-wrapper {
  margin-bottom: 1.25rem;
  border: 1px solid var(--tabs-border);
  border-radius: 8px;
  overflow: hidden;
  background: color-mix(in srgb, var(--card-bg) 98%, var(--text-color-85) 2%);
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
  background: color-mix(in srgb, var(--text-color-85) 8%, transparent);
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

.btn-insight {
  opacity: 0.6;
  transition: all 0.2s ease;
  width: 1.6rem !important;
  height: 1.6rem !important;
  padding: 0 !important;
}
.btn-insight:hover {
  opacity: 1;
  transform: scale(1.1);
}
.btn-insight :deep(.p-button-icon) {
  font-size: 0.85rem !important;
}

.evolucao-chart-wrap.is-hovering-axis :deep(canvas) {
  cursor: pointer !important;
}
.mensal-chart-clickable :deep(canvas) {
  cursor: pointer !important;
}

.repasses-block {
  display: flex;
  flex-direction: column;
  gap: 1.5rem;
  margin-top: 0.5rem;
  padding-top: 1.25rem;
  border-top: 2px solid var(--tabs-border);
}

.repasses-section {
  margin-top: 0;
  border-top: none;
  padding-top: 0.9rem;
}

.repasses-scope-leading-icon {
  margin-right: 0.45rem;
  color: var(--primary-color);
  font-size: 0.85rem;
}

.repasses-table-dialog-body {
  height: 65vh;
  min-height: 420px;
  display: flex;
  flex-direction: column;
}

.repasses-table-dialog :deep(.p-dialog-content) {
  overflow: hidden;
  background: var(--card-bg);
}

.repasses-scope-icon {
  font-size: 0.85rem !important;
  color: var(--text-muted);
  cursor: help;
  opacity: 0.75;
}

.repasses-scope-note {
  margin: 0 0 1rem;
  font-size: 0.78rem;
  line-height: 1.45;
  color: var(--text-muted);
}

.repasses-kpi-grid {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: 0.75rem;
  margin-bottom: 1rem;
}

.repasses-kpi-item {
  display: flex;
  flex-direction: column;
  gap: 0.35rem;
  padding: 0.75rem 0.9rem;
  border: 1px solid var(--tabs-border);
  border-radius: 10px;
  background: color-mix(in srgb, var(--card-bg) 96%, var(--primary-color) 4%);
}

.repasses-kpi-label {
  font-size: 0.68rem;
  font-weight: 600;
  letter-spacing: 0.05em;
  text-transform: uppercase;
  color: var(--text-muted);
}

.repasses-kpi-value {
  font-size: 0.92rem;
  font-weight: 600;
  color: var(--text-color-85);
}

.repasses-kpi-last {
  font-size: 0.82rem;
}

.repasses-table-wrap {
  margin-top: 1rem;
}

.high-value-audit {
  color: var(--risk-high);
  background: color-mix(in srgb, var(--risk-high) 10%, transparent);
  border-left: 3px solid var(--risk-high);
  padding: 0.1rem 0.45rem;
  border-radius: 4px;
  font-weight: 600;
}

:deep(.p-datatable.repasses-table) {
  font-size: 0.82rem;
  background: transparent;
}

:deep(.p-datatable.repasses-table .p-datatable-wrapper),
:deep(.p-datatable.repasses-table .p-datatable-scrollable-header),
:deep(.p-datatable.repasses-table .p-datatable-scrollable-header-box),
:deep(.p-datatable.repasses-table .p-datatable-scrollable-footer) {
  background: transparent;
}

:deep(.p-datatable.repasses-table .p-datatable-thead > tr > th) {
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

:deep(.p-datatable.repasses-table .p-datatable-tbody > tr > td) {
  text-align: right;
  padding: 0.65rem 1rem;
  color: var(--text-secondary);
  border-bottom: 1px solid var(--tabs-border);
  background: transparent;
}

:deep(.p-datatable.repasses-table .p-datatable-tbody > tr:hover > td) {
  background: var(--table-hover);
}

:deep(.p-datatable.repasses-table .p-datatable-tfoot > tr > td) {
  text-align: right;
  border-top: 2px solid var(--tabs-border) !important;
  border-bottom: none !important;
  background: color-mix(in srgb, var(--tabs-bg) 95%, var(--text-color-85) 5%);
  font-weight: 600;
  color: var(--text-color-85);
  padding: 0.85rem 1rem;
}

:deep(.p-datatable.repasses-table .p-datatable-thead > tr > th:nth-child(1)),
:deep(.p-datatable.repasses-table .p-datatable-tbody > tr > td:nth-child(1)),
:deep(.p-datatable.repasses-table .p-datatable-thead > tr > th:nth-child(3)),
:deep(.p-datatable.repasses-table .p-datatable-tbody > tr > td:nth-child(3)) {
  text-align: left !important;
}

:deep(.p-datatable.repasses-table .p-datatable-thead > tr > th:nth-child(1) .p-column-header-content),
:deep(.p-datatable.repasses-table .p-datatable-thead > tr > th:nth-child(3) .p-column-header-content) {
  justify-content: flex-start;
}

:deep(.p-datatable.repasses-table .p-datatable-thead > tr > th .p-column-header-content) {
  justify-content: flex-end;
}

.repasses-table-dialog :deep(.p-dialog-header),
.repasses-table-dialog :deep(.p-dialog-footer) {
  background: var(--card-bg);
  border-color: var(--tabs-border);
}

/* Remover borda branca de foco nos botões */
:deep(.p-button:focus) {
  box-shadow: none !important;
  outline: none !important;
}

</style>
