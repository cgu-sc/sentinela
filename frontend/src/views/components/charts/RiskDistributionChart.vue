<script setup>
import { computed, ref, watch } from 'vue';
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
  data:         { type: Array,   default: () => [] },
  currentScore: { type: Number,  default: 0 },
  loading:      { type: Boolean, default: false },
  rankingText:  { type: String,  default: null },
  metricLabel:  { type: String,  default: 'Score de Risco' }
});

const { chartTheme } = useChartTheme();

// Cache local: mantém os dados do render anterior visíveis enquanto novos chegam.
// Só atualiza quando há dados reais E não está carregando — exatamente como o RegionalRankChart
// mantém seus pontos visíveis ao trocar de métrica (o ECharts anima internamente).
const localData  = ref([]);
const localScore = ref(0);
const localLabel = ref('Score de Risco');
const isReady    = ref(false);

watch(
  [() => props.data, () => props.currentScore, () => props.metricLabel],
  ([data, score, label]) => {
    if (data?.length && !props.loading) {
      localData.value  = [...data];
      localScore.value = score;
      localLabel.value = label;
      isReady.value    = true;
    }
  },
  { immediate: true }
);

const chartOption = computed(() => {
  if (!localData.value?.length) return {};
  const c = chartTheme.value;

  const xData = localData.value.map(d => `${d.percentile}%`);
  const yData = localData.value.map(d => d.score);

  let markerXIndex = localData.value.findIndex(d => d.score >= localScore.value);
  if (markerXIndex === -1) markerXIndex = localData.value.length - 1;

  // Alinhamento horizontal do label: evita corte nas bordas
  const relPos     = markerXIndex / localData.value.length;
  const labelAlign = relPos < 0.25 ? 'left' : relPos > 0.75 ? 'right' : 'center';

  const isPct          = localLabel.value.includes('%');
  const scoreFormatted = isPct
    ? `${localScore.value.toFixed(1)}%`
    : localScore.value.toFixed(2);

  return {
    animation:         true,
    animationDuration: 500,
    animationEasing:   'cubicOut',
    backgroundColor:   'transparent',
    grid: { top: 80, right: 24, bottom: 36, left: 56, containLabel: false },
    tooltip: {
      trigger:     'axis',
      axisPointer: { type: 'line', lineStyle: { color: c.grid, width: 1, type: 'dashed' } },
      backgroundColor: c.tooltip,
      borderColor:     c.tooltipBorder,
      borderWidth: 1,
      textStyle:   { color: c.tooltipText, fontSize: 12 },
      formatter: (params) => {
        const p            = params[0];
        const valFormatted = isPct ? `${p.value.toFixed(1)}%` : p.value.toFixed(2);
        return `
          <div style="padding:4px 6px;color:${c.tooltipText}">
            <div style="opacity:.65;font-size:10px;text-transform:uppercase;letter-spacing:.06em">Percentil: ${p.name}</div>
            <hr style="margin:6px 0;opacity:.15;border:0;border-top:1px solid currentColor"/>
            <div style="opacity:.65;font-size:10px;text-transform:uppercase;letter-spacing:.06em">${localLabel.value}</div>
            <div style="font-size:17px;font-weight:800;color:#ef4444;margin-top:2px">${valFormatted}</div>
          </div>`;
      }
    },
    xAxis: {
      type:        'category',
      data:        xData,
      boundaryGap: false,
      axisLabel:   { color: c.textColor, fontSize: 10, interval: 19 },
      axisLine:    { lineStyle: { color: c.borderColor } },
      axisTick:    { show: false }
    },
    yAxis: {
      type:      'value',
      splitLine: { lineStyle: { color: c.grid, type: 'dashed', opacity: 0.4 } },
      axisLabel: {
        color:     c.textColor,
        fontSize:  10,
        formatter: (v) => isPct ? `${v}%` : v
      }
    },
    series: [
      {
        name:   'Curva de Risco',
        type:   'line',
        data:   yData,
        smooth: 0.4,
        symbol: 'none',
        lineStyle: { width: 2.5, color: '#ef4444' },
        areaStyle: {
          color: {
            type: 'linear', x: 0, y: 0, x2: 0, y2: 1,
            colorStops: [
              { offset: 0, color: 'rgba(239,68,68,0.28)' },
              { offset: 1, color: 'rgba(239,68,68,0.02)' }
            ]
          }
        },
        markLine: {
          silent:     true,
          symbol:     ['none', 'circle'],
          symbolSize: 5,
          lineStyle:  { color: 'rgba(239,68,68,0.6)', type: 'dashed', width: 1.5 },
          label: {
            show:        true,
            position:    'end',
            distance:    8,
            rotate:      0,
            align:       labelAlign,
            backgroundColor: c.tooltip,
            borderColor:     '#ef4444',
            borderWidth:  1,
            padding:      [5, 9],
            borderRadius: 5,
            formatter: () => `{t|ESTABELECIMENTO}\n{v|${scoreFormatted}}`,
            rich: {
              t: { fontSize: 9,  color: c.tooltipText, opacity: 0.65, lineHeight: 14 },
              v: { fontSize: 13, fontWeight: 700, color: '#ef4444',   lineHeight: 18 }
            }
          },
          data: [{ xAxis: markerXIndex }]
        }
      }
    ]
  };
});
</script>

<template>
  <div class="risk-distribution-wrapper">
    <!-- O container nunca sai do DOM: o ECharts anima a troca de dados internamente -->
    <div class="chart-container" :class="{ 'is-loading': loading && !isReady }">
      <VChart
        v-if="isReady"
        class="chart"
        :option="chartOption"
        autoresize
      />
      <div v-else class="empty-state">
        <i class="pi pi-chart-line" />
        <p>Aguardando dados...</p>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* ─── Wrapper: ocupa toda a área flex do card ─────────────────────────────── */
.risk-distribution-wrapper {
  flex: 1;
  display: flex;
  flex-direction: column;
  min-height: 0;
  position: relative;
}

/* ─── Container: cresce com o wrapper, dim suave durante loading inicial ───── */
.chart-container {
  flex: 1;
  display: flex;
  flex-direction: column;
  min-height: 280px;
  position: relative;
  transition: opacity 0.3s ease;
}

/* Loading apenas no carregamento inicial (antes de isReady) */
.chart-container.is-loading {
  opacity: 0.5;
}

/* ─── O chart ECharts preenche todo o container ───────────────────────────── */
.chart {
  flex: 1;
  width: 100%;
  min-height: 0;
}

/* ─── Empty/loading state inicial ─────────────────────────────────────────── */
.empty-state {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  color: var(--text-muted);
  gap: 1rem;
  font-size: 0.85rem;
}

.empty-state i {
  font-size: 1.5rem;
  opacity: 0.4;
}
</style>
