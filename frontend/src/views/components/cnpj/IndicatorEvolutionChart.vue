<script setup>
import { computed } from 'vue';
import VChart from 'vue-echarts';
import { use } from 'echarts/core';
import { CanvasRenderer } from 'echarts/renderers';
import { BarChart, LineChart } from 'echarts/charts';
import {
  GridComponent,
  LegendComponent,
  MarkAreaComponent,
  MarkLineComponent,
  TooltipComponent,
} from 'echarts/components';
import { useChartTheme } from '@/config/chartTheme';
import { PALETTE } from '@/config/colors';
import { useFormatting } from '@/composables/useFormatting';

use([
  CanvasRenderer,
  BarChart,
  LineChart,
  GridComponent,
  LegendComponent,
  MarkAreaComponent,
  MarkLineComponent,
  TooltipComponent,
]);

const props = defineProps({
  data: { type: Object, required: true },
  valueLabel: { type: String, required: true },
});

const { chartTheme, chartDataColors } = useChartTheme();
const {
  formatCurrencyFull,
  formatNumberFull,
  formatPercent,
} = useFormatting();

const seriesData = computed(() => props.data?.series ?? []);
const years = computed(() => seriesData.value.map(point => String(point.ano_base)));
const hasFinancialSeries = computed(() => seriesData.value.some(point =>
  point.valor_movimentado != null || point.valor_sem_comprovacao != null
));
const markedYears = computed(() => props.data?.periodo_marcado?.anos ?? []);
const selectedSingleYear = computed(() => markedYears.value.length === 1 ? String(markedYears.value[0]) : null);
const markedYearSet = computed(() => new Set(markedYears.value.map(year => String(year))));

function hexToRgba(hex, alpha) {
  const normalized = String(hex ?? '').trim();
  if (!/^#[0-9a-fA-F]{6}$/.test(normalized)) {
    throw new Error('Cor invalida para area marcada do grafico de indicador.');
  }
  const r = parseInt(normalized.slice(1, 3), 16);
  const g = parseInt(normalized.slice(3, 5), 16);
  const b = parseInt(normalized.slice(5, 7), 16);
  return `rgba(${r}, ${g}, ${b}, ${alpha})`;
}

function formatValue(value) {
  if (value == null) return '—';
  const formato = props.data?.formato;
  if (formato === 'pct' || formato === 'pct3') return formatPercent(value);
  if (formato === 'val') return formatCurrencyFull(value);
  if (formato === 'risco') return `${Number(value).toFixed(1)}x`;
  return formatNumberFull(value);
}

function formatCurrencyCompact(value) {
  if (value == null) return '—';
  return Number(value).toLocaleString('pt-BR', {
    style: 'currency',
    currency: 'BRL',
    notation: 'compact',
    maximumFractionDigits: 1,
  });
}

function financialTotal(point) {
  return Number(point?.valor_movimentado ?? 0);
}

function financialIrregular(point) {
  return Number(point?.valor_sem_comprovacao ?? 0);
}

function financialRegular(point) {
  return Math.max(financialTotal(point) - financialIrregular(point), 0);
}

const palette = computed(() => ({
  farmacia: chartDataColors.value.red,
  regiao: PALETTE.indigo[500],
  uf: PALETTE.fuchsia[500],
  regular: chartDataColors.value.green,
  regularGrad: chartDataColors.value.greenGrad,
  irregular: chartDataColors.value.red,
  irregularGrad: chartDataColors.value.redGrad,
  mark: PALETTE.amber[500],
  markFill: 'rgba(150, 150, 150, 0.12)',
  text: chartTheme.value.text,
  muted: chartTheme.value.muted,
  border: chartTheme.value.border,
}));

const markArea = computed(() => {
  const selectedYearsInSeries = years.value.filter(year => markedYearSet.value.has(year));
  if (!selectedYearsInSeries.length) return undefined;
  return {
    silent: true,
    itemStyle: {
      color: palette.value.markFill,
    },
    data: [[
      { xAxis: selectedYearsInSeries[0] },
      { xAxis: selectedYearsInSeries[selectedYearsInSeries.length - 1] },
    ]],
  };
});

const unusedMarkLine = computed(() => {
  if (!selectedSingleYear.value) return undefined;
  return {
    silent: true,
    symbol: 'none',
    lineStyle: {
      color: palette.value.mark,
      width: 1.5,
      type: 'dashed',
    },
    label: {
      formatter: 'Período',
      color: palette.value.mark,
      fontSize: 11,
    },
    data: [{ xAxis: selectedSingleYear.value }],
  };
});

function buildLine(name, key, color, width, extra = {}) {
  const { lineStyle, itemStyle, ...rest } = extra;
  return {
    name,
    type: 'line',
    xAxisIndex: 0,
    yAxisIndex: 0,
    smooth: true,
    symbol: 'circle',
    symbolSize: width >= 3 ? 7 : 5,
    connectNulls: false,
    emphasis: { focus: 'series' },
    lineStyle: { width, color, ...(lineStyle ?? {}) },
    itemStyle: { color, ...(itemStyle ?? {}) },
    data: seriesData.value.map(point => point[key]),
    ...rest,
  };
}

const chartOptions = computed(() => ({
  animationDuration: 350,
  color: [
    palette.value.mark,
    palette.value.farmacia,
    palette.value.regiao,
    palette.value.uf,
    palette.value.regular,
    palette.value.irregular,
  ],
  grid: hasFinancialSeries.value ? [
    {
      left: 46,
      right: 24,
      top: 42,
      height: 190,
      containLabel: true,
    },
    {
      left: 46,
      right: 24,
      top: 250,
      height: 145,
      containLabel: true,
    },
  ] : {
    left: 46,
    right: 24,
    top: 42,
    bottom: 32,
    containLabel: true,
  },
  legend: {
    top: 0,
    left: 0,
    itemWidth: 12,
    itemHeight: 8,
    textStyle: {
      color: palette.value.text,
      fontSize: 11,
    },
  },
  tooltip: {
    trigger: 'axis',
    axisPointer: { type: 'line' },
    backgroundColor: chartTheme.value.tooltip,
    borderColor: chartTheme.value.tooltipBorder,
    borderWidth: 1,
    padding: [12, 16],
    textStyle: {
      color: chartTheme.value.tooltipText,
      fontFamily: 'Inter, sans-serif',
      fontSize: 12,
    },
    formatter(params) {
      if (!Array.isArray(params) || params.length === 0) return '';
      const year = params[0]?.axisValue ?? '';
      const point = seriesData.value.find(item => String(item.ano_base) === String(year));
      const lines = params
        .filter(item => item.seriesName !== 'Periodo selecionado')
        .map(item => {
          const isFinancial = item.seriesName === 'Valor com comprovação' || item.seriesName === 'Valor sem comprovação';
          return `${item.marker}${item.seriesName}: <strong>${isFinancial ? formatCurrencyFull(item.value) : formatValue(item.value)}</strong>`;
        })
        .join('<br/>');
      const financialFooter = point?.valor_movimentado != null || point?.valor_sem_comprovacao != null
        ? `<div style="border-top:1px solid ${chartTheme.value.tooltipBorder}; margin-top:8px; padding-top:8px;">
             Total movimentado: <strong>${point.valor_movimentado != null ? formatCurrencyFull(point.valor_movimentado) : '—'}</strong><br/>
             Não comprovação: <strong>${point.valor_sem_comprovacao != null ? formatCurrencyFull(point.valor_sem_comprovacao) : '—'}</strong>${point.percentual_nao_comprovacao != null ? ` <span style="opacity:.72">(${Number(point.percentual_nao_comprovacao).toFixed(2)}%)</span>` : ''}
           </div>`
        : '';
      return `<div style="color:${chartTheme.value.tooltipText};"><strong>${year}</strong><br/>${lines}${financialFooter}</div>`;
    },
  },
  xAxis: hasFinancialSeries.value ? [
    {
      type: 'category',
      gridIndex: 0,
      data: years.value,
      boundaryGap: true,
      axisLine: { lineStyle: { color: palette.value.border } },
      axisTick: { show: false },
      axisLabel: { color: palette.value.muted, fontSize: 11 },
    },
    {
      type: 'category',
      gridIndex: 1,
      data: years.value,
      boundaryGap: true,
      axisLine: { lineStyle: { color: palette.value.border } },
      axisTick: { show: false },
      axisLabel: { color: palette.value.muted, fontSize: 10 },
    },
  ] : {
    type: 'category',
    data: years.value,
    boundaryGap: true,
    axisLine: { lineStyle: { color: palette.value.border } },
    axisTick: { show: false },
    axisLabel: { color: palette.value.muted, fontSize: 11 },
  },
  yAxis: hasFinancialSeries.value ? [
    {
      type: 'value',
      gridIndex: 0,
      axisLabel: {
        color: palette.value.muted,
        fontSize: 11,
        formatter: value => formatValue(value),
      },
      splitLine: {
        lineStyle: {
          color: palette.value.border,
          type: 'dashed',
        },
      },
    },
    {
      type: 'value',
      gridIndex: 1,
      axisLine: { show: false },
      axisTick: { show: false },
      axisLabel: {
        color: palette.value.muted,
        fontSize: 10,
        formatter: value => formatCurrencyCompact(value),
      },
      splitLine: {
        lineStyle: {
          color: palette.value.border,
          type: 'dashed',
        },
      },
    },
  ] : {
    type: 'value',
    axisLabel: {
      color: palette.value.muted,
      fontSize: 11,
      formatter: value => formatValue(value),
    },
    splitLine: {
      lineStyle: {
        color: palette.value.border,
        type: 'dashed',
      },
    },
  },
  series: [
    {
      name: 'Periodo selecionado',
      type: 'line',
      xAxisIndex: 0,
      yAxisIndex: 0,
      data: seriesData.value.map(() => null),
      symbol: 'none',
      lineStyle: { opacity: 0 },
      itemStyle: { color: palette.value.mark },
      tooltip: { show: false },
      silent: true,
      markArea: markArea.value,
      z: 0,
    },
    buildLine('Farmácia', 'farmacia', palette.value.farmacia, 3.2, {
      z: 5,
    }),
    buildLine('Região de Saúde', 'regiao_saude', palette.value.regiao, 2.6, { z: 4 }),
    buildLine('UF', 'uf', palette.value.uf, 1.6, {
      lineStyle: { opacity: 0.72, type: 'dashed' },
      itemStyle: { opacity: 0.72 },
      z: 2,
    }),
    ...(hasFinancialSeries.value ? [
      {
        name: 'Valor com comprovação',
        type: 'bar',
        xAxisIndex: 1,
        yAxisIndex: 1,
        stack: 'financeiro',
        barMaxWidth: 40,
        data: seriesData.value.map(point => financialRegular(point)),
        itemStyle: {
          color: {
            type: 'linear', x: 0, y: 0, x2: 0, y2: 1,
            colorStops: [
              { offset: 0, color: palette.value.regularGrad },
              { offset: 1, color: palette.value.regular + '55' },
            ],
          },
        },
        emphasis: { focus: 'series' },
        z: 1,
      },
      {
        name: 'Valor sem comprovação',
        type: 'bar',
        xAxisIndex: 1,
        yAxisIndex: 1,
        stack: 'financeiro',
        barMaxWidth: 40,
        data: seriesData.value.map(point => financialIrregular(point)),
        itemStyle: {
          borderRadius: [4, 4, 0, 0],
          color: {
            type: 'linear', x: 0, y: 0, x2: 0, y2: 1,
            colorStops: [
              { offset: 0, color: palette.value.irregularGrad },
              { offset: 1, color: palette.value.irregular + '55' },
            ],
          },
        },
        emphasis: { focus: 'series' },
        z: 2,
      },
    ] : []),
  ],
}));
</script>

<template>
  <section class="indicator-evolution-card">
    <div class="indicator-card-title">Evolução anual do indicador</div>
    <div class="indicator-evolution-subtitle">{{ valueLabel }}</div>
    <VChart
      :option="chartOptions"
      autoresize
      class="indicator-evolution-chart"
    />
  </section>
</template>

<style scoped>
.indicator-evolution-card {
  border: 1px solid var(--card-border);
  background: var(--card-bg);
  border-radius: 10px;
  padding: 0.9rem;
}

.indicator-card-title {
  font-size: 0.9rem;
  font-weight: 600;
  color: var(--text-color-85);
}

.indicator-evolution-subtitle {
  margin-top: 0.18rem;
  font-size: 0.78rem;
  color: var(--text-muted);
}

.indicator-evolution-chart {
  width: 100%;
  height: 420px;
  margin-top: 0.45rem;
}
</style>
