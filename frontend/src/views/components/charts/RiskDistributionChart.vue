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
    grid: { top: 30, right: 30, bottom: 40, left: 50 },
    tooltip: {
      trigger: 'axis',
      backgroundColor: 'rgba(15, 23, 42, 0.95)',
      borderColor: 'rgba(255,255,255,0.1)',
      borderWidth: 1,
      textStyle: { color: '#fff', fontSize: 12 },
      formatter: (params) => {
          const p = params[0];
          return `
            <div style="padding: 4px;">
              <div style="opacity: 0.7; font-size: 10px; text-transform: uppercase; margin-bottom: 2px;">Percentil Populacional:</div>
              <div style="font-size: 14px; font-weight: 700;">${p.name}</div>
              <hr style="margin: 8px 0; opacity: 0.1; border: 0; border-top: 1px solid #fff;"/>
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
            formatter: `VOCÊ (Score: ${props.currentScore.toFixed(2)})`,
            backgroundColor: '#ef4444',
            color: '#fff',
            padding: [4, 8],
            borderRadius: 4,
            fontWeight: 'bold',
            fontSize: 10,
            distance: 10
          },
          lineStyle: {
            color: c.textColor,
            type: 'dashed',
            width: 2,
            opacity: 0.7
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
