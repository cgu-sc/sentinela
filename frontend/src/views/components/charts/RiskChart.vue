<script setup>
import { computed } from 'vue';
import { useAnalyticsStore } from '@/stores/analytics';
import { useFormatting } from '@/composables/useFormatting';
import { useChartTheme } from '@/config/chartTheme';
import { CHART_TOOLTIP_SHADOW } from '@/config/colors.js';
import { storeToRefs } from 'pinia';
import Button from 'primevue/button';

// ── ECharts ───────────────────────────────────────────────────────────────
import { use } from 'echarts/core';
import { CanvasRenderer } from 'echarts/renderers';
import { BarChart, LineChart } from 'echarts/charts';
import {
  GridComponent,
  TooltipComponent,
  LegendComponent,
  AxisPointerComponent,
} from 'echarts/components';
import VChart from 'vue-echarts';

use([CanvasRenderer, BarChart, LineChart, GridComponent, TooltipComponent, LegendComponent, AxisPointerComponent]);

// ── Stores ────────────────────────────────────────────────────────────────
const analyticsStore = useAnalyticsStore();
const { fatorRisco, fatorRiscoLoading } = storeToRefs(analyticsStore);
const { formatBRL, formatCurrencyFull, formatNumberFull } = useFormatting();
const { chartTheme, chartDataColors, chartRiskAccents } = useChartTheme();

// ── Tema (cores do gráfico vindas de colors.js via useChartTheme) ─────────
const C = computed(() => ({
  ...chartTheme.value,
  ...chartRiskAccents.value,        // bar, barGrad (violeta)
  area: chartDataColors.value.red,  // mesmo vermelho do Volume Financeiro
}));

// ── Opção ECharts ─────────────────────────────────────────────────────────
const chartOption = computed(() => {
  const c      = C.value;
  const faixas = fatorRisco.value.map(b => b.faixa);

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

    grid: { top: 44, left: 80, right: 80, bottom: 64 },

    xAxis: {
      type: 'category',
      data: faixas,
      axisLine:  { lineStyle: { color: c.grid } },
      axisTick:  { show: false },
      axisLabel: { color: c.muted, fontSize: 11, fontWeight: 700, fontFamily: 'Inter, sans-serif', interval: 0, rotate: 15 },
      name: 'Faixa de Percentual de Não Comprovação',
      nameLocation: 'middle',
      nameGap: 50,
      nameTextStyle: { color: c.muted, fontSize: 10, fontWeight: 500 },
    },

    yAxis: [
      {
        type: 'value',
        name: 'Qtd Estab',
        nameLocation: 'end',
        nameTextStyle: { color: c.bar, fontSize: 11, fontWeight: 700 },
        axisLine:  { show: false },
        axisTick:  { show: false },
        splitLine: { lineStyle: { color: c.grid, type: 'dashed' } },
        axisLabel: { color: c.muted, fontSize: 10, formatter: (v) => v.toLocaleString('pt-BR') },
      },
      {
        type: 'value',
        name: 'Valor S/ Comp',
        nameLocation: 'end',
        nameTextStyle: { color: c.area, fontSize: 11, fontWeight: 700 },
        axisLine:  { show: false },
        axisTick:  { show: false },
        splitLine: { show: false },
        axisLabel: { color: c.muted, fontSize: 10, formatter: (v) => formatBRL(v) },
      },
    ],

    tooltip: {
      trigger: 'axis',
      axisPointer: { type: 'shadow', shadowStyle: { color: CHART_TOOLTIP_SHADOW } },
      backgroundColor: c.tooltip,
      borderColor: c.border,
      borderWidth: 1,
      padding: [12, 16],
      textStyle: { color: c.text, fontFamily: 'Inter, sans-serif', fontSize: 12 },
      formatter: (params) => {
        const bar  = params.find(p => p.seriesIndex === 0);
        const area = params.find(p => p.seriesIndex === 1);
        const faixa = bar?.axisValue ?? '';
        return `
          <div style="font-weight:700;font-size:14px;margin-bottom:10px;">${faixa}</div>
          <div style="display:flex;flex-direction:column;gap:6px;">
            <div style="display:flex;align-items:center;gap:8px;">
              <span style="width:10px;height:10px;border-radius:2px;background:${c.bar};display:inline-block;"></span>
              <span style="font-size:10px;opacity:.6;letter-spacing:.04em;text-transform:uppercase;">Qtd Estabelecimentos</span>
            </div>
            <div style="font-weight:700;font-size:14px;margin-bottom:4px;">${formatNumberFull(bar?.value ?? 0)}</div>
            <div style="display:flex;align-items:center;gap:8px;">
              <span style="width:10px;height:10px;border-radius:2px;background:${c.area};display:inline-block;"></span>
              <span style="font-size:10px;opacity:.6;letter-spacing:.04em;text-transform:uppercase;">Valor Sem Comprovação</span>
            </div>
            <div style="font-weight:700;font-size:14px;color:${c.area};">${formatCurrencyFull(area?.value ?? 0)}</div>
          </div>`;
      },
    },

    series: [
      // Barras — Qtd Estab (eixo Y esquerdo)
      {
        name: 'Qtd Estab',
        type: 'bar',
        yAxisIndex: 0,
        barMaxWidth: 40,
        data: fatorRisco.value.map(b => b.qtd),
        itemStyle: {
          borderRadius: [6, 6, 0, 0],
          color: {
            type: 'linear', x: 0, y: 0, x2: 0, y2: 1,
            colorStops: [
              { offset: 0, color: c.barGrad },
              { offset: 1, color: c.bar + '55' },
            ],
          },
        },
        emphasis: { itemStyle: { opacity: 1 } },
      },

      // Área — Valor Sem Comprovação (eixo Y direito)
      {
        name: 'Valor S/ Comp',
        type: 'line',
        yAxisIndex: 1,
        smooth: true,
        symbol: 'none',
        data: fatorRisco.value.map(b => b.valor_raw),
        lineStyle: { color: c.area, width: 2.5 },
        areaStyle: {
          color: {
            type: 'linear', x: 0, y: 0, x2: 0, y2: 1,
            colorStops: [
              { offset: 0, color: c.area + 'aa' },
              { offset: 1, color: c.area + '08' },
            ],
          },
        },
      },
    ],
  };
});
</script>

<template>
  <div class="chart-section" :class="{ 'is-refreshing': fatorRiscoLoading }">
    <div class="chart-header">
      <i class="pi pi-chart-bar"></i>
      <h3>FATOR RISCO X QTD ESTAB</h3>
      <div class="spacer"></div>
      <Button
        icon="pi pi-info-circle"
        v-tooltip.top="'Este gráfico segmenta os estabelecimentos por faixas de não-comprovação...'"
        text severity="secondary" rounded
      />
    </div>
    <div class="chart-wrapper">
      <v-chart class="echart" :option="chartOption" autoresize />
    </div>
  </div>
</template>

<style scoped>
.chart-section {
  display: flex;
  flex-direction: column;
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  border-radius: 12px;
  box-shadow: 0 1px 3px rgba(0,0,0,0.08), 0 1px 2px rgba(0,0,0,0.04);
  overflow: hidden;
}

.chart-header {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  padding: 1rem 1.5rem;
}

.chart-wrapper {
  height: 35vh;
  min-height: 400px;
}

.echart {
  width: 100%;
  height: 100%;
}

.spacer { flex: 1; }

.is-refreshing {
  opacity: 0.5;
  pointer-events: none;
}
</style>
