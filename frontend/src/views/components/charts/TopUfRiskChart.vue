<script setup>
import { computed } from 'vue';
import { storeToRefs } from 'pinia';
import { use } from 'echarts/core';
import { CanvasRenderer } from 'echarts/renderers';
import { BarChart } from 'echarts/charts';
import { GridComponent, TooltipComponent } from 'echarts/components';
import VChart from 'vue-echarts';
import { useAnalyticsStore } from '@/stores/analytics';
import { useFilterStore } from '@/stores/filters';
import { useDelayedLoading } from '@/composables/useDelayedLoading';
import { useFormatting } from '@/composables/useFormatting';
import { useRiskMetrics } from '@/composables/useRiskMetrics';
import { useChartTheme } from '@/config/chartTheme';
import { FILTER_ALL_VALUE } from '@/config/constants';
import { CHART_TOOLTIP_SHADOW } from '@/config/colors';

use([CanvasRenderer, BarChart, GridComponent, TooltipComponent]);

const analyticsStore = useAnalyticsStore();
const filterStore = useFilterStore();
const { resultadoSentinelaUFNacional, isLoading } = storeToRefs(analyticsStore);
const showRefreshing = useDelayedLoading(isLoading);
const { formatBRL, formatPercent } = useFormatting();
const { getRiskColor, getRiskLabel } = useRiskMetrics();
const { chartTheme, chartDataColors } = useChartTheme();

const topUfData = computed(() =>
  [...(resultadoSentinelaUFNacional.value || [])]
    .filter((item) => item?.uf && Number.isFinite(Number(item.percValSemComp)))
    .sort((a, b) => Number(b.percValSemComp ?? 0) - Number(a.percValSemComp ?? 0))
    .slice(0, 10)
    .reverse()
);

const maxPercent = computed(() =>
  Math.max(10, ...topUfData.value.map((item) => Number(item.percValSemComp ?? 0)))
);

const chartOption = computed(() => {
  const c = {
    ...chartTheme.value,
    ...chartDataColors.value,
  };

  return {
    backgroundColor: c.bg,
    animationDuration: 700,
    animationEasing: 'cubicOut',
    textStyle: { fontFamily: 'Inter, sans-serif' },
    grid: {
      top: 12,
      right: 34,
      bottom: 20,
      left: 44,
      containLabel: true,
    },
    tooltip: {
      trigger: 'axis',
      axisPointer: { type: 'shadow', shadowStyle: { color: CHART_TOOLTIP_SHADOW } },
      confine: true,
      backgroundColor: c.tooltip,
      borderColor: c.tooltipBorder,
      borderWidth: 1,
      padding: [12, 14],
      textStyle: {
        color: c.tooltipText,
        fontFamily: 'Inter, sans-serif',
        fontSize: 12,
      },
      formatter: (params) => {
        const index = params?.[0]?.dataIndex;
        const item = topUfData.value[index];
        if (!item) return '';

        const perc = Number(item.percValSemComp ?? 0);
        const riskColor = getRiskColor(perc);
        const riskLabel = getRiskLabel(perc);

        return `
          <div style="color:${c.tooltipText};min-width:190px;">
            <div style="display:flex;align-items:center;justify-content:space-between;gap:12px;margin-bottom:8px;">
              <strong style="font-size:14px;">${item.uf}</strong>
              <span style="font-size:10px;font-weight:700;padding:2px 7px;border-radius:8px;background:${riskColor}22;color:${riskColor};">
                ${riskLabel.toUpperCase()}
              </span>
            </div>
            <div style="display:flex;flex-direction:column;gap:4px;">
              <div>% sem comprovação: <strong style="color:${riskColor};">${formatPercent(perc)}</strong></div>
              <div>Valor sem comprovação: <strong>${formatBRL(item.valSemComp ?? 0)}</strong></div>
              <div>CNPJs: <strong>${(item.cnpjs ?? 0).toLocaleString('pt-BR')}</strong></div>
            </div>
          </div>`;
      },
    },
    xAxis: {
      type: 'value',
      min: 0,
      max: Math.ceil(maxPercent.value / 10) * 10,
      axisLine: { show: false },
      axisTick: { show: false },
      splitLine: { lineStyle: { color: c.grid, type: 'dashed' } },
      axisLabel: {
        color: c.muted,
        fontSize: 10,
        formatter: (value) => `${value}%`,
      },
    },
    yAxis: {
      type: 'category',
      data: topUfData.value.map((item) => item.uf),
      axisLine: { show: false },
      axisTick: { show: false },
      axisLabel: {
        color: c.text,
        fontSize: 11,
        fontWeight: 700,
      },
    },
    series: [
      {
        name: '% sem comprovação',
        type: 'bar',
        data: topUfData.value.map((item) => ({
          value: Number((item.percValSemComp ?? 0).toFixed(2)),
          itemStyle: {
            color: {
              type: 'linear',
              x: 0,
              y: 0,
              x2: 1,
              y2: 0,
              colorStops: [
                { offset: 0, color: `${c.red}55` },
                { offset: 1, color: c.redGrad },
              ],
            },
            borderRadius: [0, 5, 5, 0],
          },
        })),
        barWidth: 14,
        label: {
          show: true,
          position: 'right',
          color: c.muted,
          fontSize: 10,
          fontWeight: 700,
          formatter: ({ value }) => formatPercent(value),
        },
      },
    ],
  };
});

function onClick(params) {
  const uf = topUfData.value[params.dataIndex]?.uf;
  if (!uf) return;
  filterStore.selectedUF = filterStore.selectedUF === uf ? FILTER_ALL_VALUE : uf;
}
</script>

<template>
  <div class="top-uf-chart" :class="{ 'is-refreshing': showRefreshing }">
    <div class="chart-header">
      <i class="pi pi-sort-amount-down-alt"></i>
      <div>
        <h3>TOP 10 UFs</h3>
        <span>% de valor sem comprovação</span>
      </div>
    </div>

    <div class="chart-wrapper">
      <VChart class="echart" :option="chartOption" autoresize @click="onClick" />
    </div>
  </div>
</template>

<style scoped>
.top-uf-chart {
  display: flex;
  flex-direction: column;
  height: 100%;
  min-height: 0;
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  border-radius: 12px;
  box-shadow:
    0 1px 3px rgba(0, 0, 0, 0.08),
    0 1px 2px rgba(0, 0, 0, 0.04);
  overflow: hidden;
  transition: opacity 0.25s ease;
}

.chart-header {
  display: flex;
  align-items: center;
  gap: 0.7rem;
  padding: 0.85rem 1rem 0.2rem;
}

.chart-header i {
  width: 2rem;
  height: 2rem;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  border-radius: 8px;
  color: var(--primary-color);
  background: color-mix(in srgb, var(--primary-color) 10%, transparent);
}

.chart-header h3 {
  margin: 0;
  color: var(--text-color-85);
  font-size: 0.78rem;
  font-weight: 800;
  letter-spacing: 0.02em;
}

.chart-header span {
  color: var(--text-muted);
  font-size: 0.72rem;
}

.chart-wrapper {
  flex: 1;
  min-height: 0;
}

.echart {
  width: 100%;
  height: 100%;
}

.is-refreshing {
  opacity: 0.45;
  pointer-events: none;
}
</style>
