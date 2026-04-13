<script setup>
import { computed } from 'vue';
import VChart from 'vue-echarts';
import { use } from 'echarts/core';
import { CanvasRenderer } from 'echarts/renderers';
import { LineChart } from 'echarts/charts';
import {
  GridComponent,
  TooltipComponent,
  MarkLineComponent,
} from 'echarts/components';

import { useChartTheme } from '@/config/chartTheme';

use([
  CanvasRenderer,
  LineChart,
  GridComponent,
  TooltipComponent,
  MarkLineComponent,
]);

const props = defineProps({
  /** Array de percentis [{ percentile, score }] */
  data: { type: Array, default: () => [] },
  currentScore: { type: Number, default: 0 },
  loading: { type: Boolean, default: false }
});

const { chartTheme } = useChartTheme();

const chartOption = computed(() => {
  if (!props.data?.length) return {};
  const c = chartTheme.value;

  const xData = props.data.map(d => `${d.percentile}%`);
  const yData = props.data.map(d => d.score);

  // Encontra o percentil mais próximo para o score da farmácia atual
  let markerXIndex = props.data.findIndex(d => d.score >= props.currentScore);
  if (markerXIndex === -1) markerXIndex = props.data.length - 1;

  return {
    backgroundColor: 'transparent',
    grid: { top: 60, right: 70, bottom: 40, left: 50 },
    tooltip: {
      trigger: 'axis',
      axisPointer: {
        type: 'line',
        lineStyle: { color: c.grid, width: 1, type: 'dashed' }
      },
      backgroundColor: c.tooltip, // Transparência agora calculada dinamicamente pelo chartTheme
      borderColor: c.tooltipBorder,
      borderWidth: 1,
      textStyle: { color: c.tooltipText, fontSize: 12 },
      formatter: (params) => {
          const p = params[0];
          return `
            <div style="padding: 4px; color: ${c.tooltipText}">
              <div style="opacity: 0.7; font-size: 10px; text-transform: uppercase; margin-bottom: 2px;">Percentil:</div>
              <div style="font-size: 14px; font-weight: 700;">${p.name}</div>
              <hr style="margin: 8px 0; opacity: 0.2; border: 0; border-top: 1px solid ${c.tooltipText};"/>
              <div style="opacity: 0.7; font-size: 10px; text-transform: uppercase; margin-bottom: 2px;">Score de Risco:</div>
              <div style="font-size: 18px; font-weight: 800; color: #ef4444;">${p.value.toFixed(2)}</div>
            </div>
          `;
      }
    },
    xAxis: {
      type: 'category',
      data: xData,
      boundaryGap: false,
      axisLabel: { 
        color: c.textColor, 
        fontSize: 10,
        interval: 19 
      },
      axisLine: { lineStyle: { color: c.borderColor } },
      axisTick: { show: false }
    },
    yAxis: {
      type: 'value',
      splitLine: { lineStyle: { color: c.grid, type: 'dashed', opacity: 0.5 } },
      axisLabel: { color: c.textColor, fontSize: 10 }
    },
    series: [
      {
        name: 'Curva de Risco',
        type: 'line',
        data: yData,
        smooth: true,
        symbol: 'none',
        lineStyle: { 
          width: 3, 
          color: '#ef4444',
          shadowBlur: 10,
          shadowColor: 'rgba(239, 68, 68, 0.4)',
          shadowOffsetY: 5
        },
        areaStyle: {
          color: {
            type: 'linear',
            x: 0, y: 0, x2: 0, y2: 1,
            colorStops: [
              { offset: 0, color: 'rgba(239, 68, 68, 0.3)' }, 
              { offset: 1, color: 'rgba(239, 68, 68, 0.02)' }  
            ]
          }
        },
        markLine: {
          symbol: ['none', 'none'],
          label: {
            show: true,
            position: 'end',
            formatter: () => `{title|ESTABELECIMENTO ATUAL}\n{score|Score: ${props.currentScore?.toFixed(2) || '—'}}`,
            backgroundColor: c.tooltip, // Retorno da transparência exata agora que não tem mais conflito de opacidade do Echarts
            borderColor: c.tooltipBorder,
            color: c.tooltipText,
            borderWidth: 1,
            padding: [8, 12],
            borderRadius: 6,
            align: 'center',
            shadowBlur: 8,
            shadowColor: 'rgba(0,0,0,0.15)',
            rich: {
              title: { fontWeight: 500, fontSize: 11, color: c.tooltipText, padding: [0, 0, 4, 0] },
              score: { fontWeight: 700, fontSize: 13, color: c.tooltipText }
            },
            distance: 6
          },
          lineStyle: {
            color: 'rgba(148, 163, 184, 0.6)', // Cor rgba em vez de opacidade global para não contaminar a Label
            type: 'dashed',
            width: 1.5
          },
          data: [{ xAxis: markerXIndex }]
        }
      }
    ]
  };
});
</script>

<template>
  <div class="risk-cliff-chart" :class="{ 'is-loading': loading }">
    <div v-if="loading" class="chart-loading">
      <i class="pi pi-spin pi-spinner" />
      <span>Calculando Curva de Risco...</span>
    </div>
    
    <div v-else-if="!data?.length" class="chart-empty">
      <i class="pi pi-chart-bar" />
      <p>Dados não disponíveis para o escopo selecionado.</p>
    </div>

    <v-chart v-else class="chart" :option="chartOption" autoresize />
  </div>
</template>

<style scoped>
.risk-cliff-chart {
  flex: 1;
  min-height: 300px;
  position: relative;
  width: 100%;
}

.chart {
  width: 100%;
  height: 100%;
}

.is-loading {
  opacity: 0.5;
}

.chart-loading, .chart-empty {
  position: absolute;
  inset: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 0.75rem;
  color: var(--text-muted);
  font-size: 0.85rem;
}

.chart-loading i {
  font-size: 1.5rem;
  color: var(--primary-color);
}

.chart-empty i {
  font-size: 2rem;
  opacity: 0.3;
}
</style>
