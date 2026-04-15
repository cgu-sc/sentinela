<script setup>
import { computed, ref, watch, nextTick } from 'vue';
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
  data: { type: Array, default: () => [] },
  currentScore: { type: Number, default: 0 },
  loading: { type: Boolean, default: false },
  rankingText: { type: String, default: null },
  metricLabel: { type: String, default: 'Score de Risco' }
});

const { chartTheme } = useChartTheme();

// Cache local dos dados — permite manter o gráfico visível enquanto novos dados carregam
const localData = ref([]);
const localScore = ref(0);
const localLabel = ref('Score de Risco');

// Estado de transição para o crossfade suave ao trocar de métrica
const isTransitioning = ref(false);

watch([() => props.data, () => props.metricLabel], async ([nv, newLabel], [_ov, oldLabel]) => {
  // Detecta mudança de métrica (label) para disparar crossfade
  const metricChanged = newLabel !== oldLabel;

  if (metricChanged && localData.value.length) {
    // Inicia a transição de saída
    isTransitioning.value = true;
    await new Promise(r => setTimeout(r, 280)); // aguarda o fade-out
  }

  if (nv?.length && !props.loading) {
    localData.value = [...nv];
    localScore.value = props.currentScore;
    localLabel.value = props.metricLabel;
  }

  if (metricChanged) {
    await nextTick();
    isTransitioning.value = false;
  }
}, { immediate: true });

const chartOption = computed(() => {
  if (!localData.value?.length) return {};
  const c = chartTheme.value;

  const xData = localData.value.map(d => `${d.percentile}%`);
  const yData = localData.value.map(d => d.score);

  let markerXIndex = localData.value.findIndex(d => d.score >= localScore.value);
  if (markerXIndex === -1) markerXIndex = localData.value.length - 1;

  // Alinhamento horizontal do label: evita cortar nas bordas do gráfico
  const totalPoints = localData.value.length;
  const relPos = markerXIndex / totalPoints;
  const labelAlign = relPos < 0.25 ? 'left' : relPos > 0.75 ? 'right' : 'center';

  const isPct = localLabel.value.includes('%');
  const scoreFormatted = isPct
    ? `${localScore.value.toFixed(1)}%`
    : localScore.value.toFixed(2);

  return {
    animation: true,
    animationDuration: 400,
    animationEasing: 'cubicOut',
    backgroundColor: 'transparent',
    grid: { top: 80, right: 24, bottom: 36, left: 56, containLabel: false },
    tooltip: {
      trigger: 'axis',
      axisPointer: { type: 'line', lineStyle: { color: c.grid, width: 1, type: 'dashed' } },
      backgroundColor: c.tooltip,
      borderColor: c.tooltipBorder,
      borderWidth: 1,
      textStyle: { color: c.tooltipText, fontSize: 12 },
      formatter: (params) => {
        const p = params[0];
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
      type: 'category',
      data: xData,
      boundaryGap: false,
      axisLabel: { color: c.textColor, fontSize: 10, interval: 19 },
      axisLine: { lineStyle: { color: c.borderColor } },
      axisTick: { show: false }
    },
    yAxis: {
      type: 'value',
      splitLine: { lineStyle: { color: c.grid, type: 'dashed', opacity: 0.4 } },
      axisLabel: {
        color: c.textColor,
        fontSize: 10,
        formatter: (v) => isPct ? `${v}%` : v
      }
    },
    series: [
      {
        name: 'Curva de Risco',
        type: 'line',
        data: yData,
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
          silent: true,
          symbol: ['none', 'circle'],
          symbolSize: 5,
          lineStyle: { color: 'rgba(239,68,68,0.6)', type: 'dashed', width: 1.5 },
          label: {
            show: true,
            position: 'end',
            distance: 8,
            rotate: 0,
            align: labelAlign,
            backgroundColor: c.tooltip,
            borderColor: '#ef4444',
            borderWidth: 1,
            padding: [5, 9],
            borderRadius: 5,
            // Rich text: linha 1 (titulo) + linha 2 (valor)
            formatter: () => `{t|ESTABELECIMENTO}\n{v|${scoreFormatted}}`,
            rich: {
              t: {
                fontSize: 9,
                color: c.tooltipText,
                opacity: 0.65,
                lineHeight: 14,
                letterSpacing: 1,
              },
              v: {
                fontSize: 13,
                fontWeight: 700,
                color: '#ef4444',
                lineHeight: 18,
              }
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
    <div
      class="chart-container"
      :class="{ 'is-loading': loading, 'is-transitioning': isTransitioning }"
    >
      <transition name="chart-fade" mode="out-in">
        <v-chart
          v-if="localData.length"
          class="chart"
          :option="chartOption"
          autoresize
        />
        <div v-else-if="!loading" class="empty-state" key="empty">
          <i class="pi pi-chart-line" />
          <p>Dados não disponíveis.</p>
        </div>
      </transition>

      <!-- Overlay de loading -->
      <transition name="fade-overlay">
        <div v-if="loading" class="loading-state">
          <i class="pi pi-spin pi-spinner" />
          <span>Sincronizando...</span>
        </div>
      </transition>
    </div>
  </div>
</template>

<style scoped>
/* ─── Wrapper: ocupa toda a área flex do card ─────────────────────────────── */
.risk-distribution-wrapper {
  flex: 1;
  display: flex;
  flex-direction: column;
  min-height: 0; /* essencial para flex-children com overflow */
  position: relative;
}

/* ─── Container do gráfico: cresce com o wrapper ──────────────────────────── */
.chart-container {
  flex: 1;
  display: flex;
  flex-direction: column;
  min-height: 280px;
  position: relative;
  transition: opacity 0.28s ease, filter 0.28s ease;
}

.chart-container.is-loading {
  opacity: 0.4;
  filter: grayscale(0.5);
}

/* Transição de crossfade suave ao trocar de métrica */
.chart-container.is-transitioning {
  opacity: 0.15;
  filter: blur(1.5px) grayscale(0.6);
}

/* ─── O chart ECharts preenche todo o container ───────────────────────────── */
.chart {
  flex: 1;
  width: 100%;
  min-height: 0;
}

/* ─── Overlay de loading (posição absoluta sobre o gráfico) ───────────────── */
.loading-state {
  position: absolute;
  inset: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 0.75rem;
  color: var(--primary-color);
  background: rgba(0,0,0,0.04);
  z-index: 10;
  backdrop-filter: blur(1px);
}

.loading-state i   { font-size: 1.4rem; }
.loading-state span {
  font-size: 0.68rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.12em;
  opacity: 0.8;
}

/* ─── Empty state ─────────────────────────────────────────────────────────── */
.empty-state {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  color: var(--text-muted);
  gap: 1rem;
}

/* ─── Transições Vue ──────────────────────────────────────────────────────── */
.chart-fade-enter-active,
.chart-fade-leave-active {
  transition: opacity 0.25s ease, transform 0.25s ease;
}
.chart-fade-enter-from {
  opacity: 0;
  transform: scaleY(0.97);
}
.chart-fade-leave-to {
  opacity: 0;
  transform: scaleY(0.97);
}

.fade-overlay-enter-active,
.fade-overlay-leave-active {
  transition: opacity 0.2s ease;
}
.fade-overlay-enter-from,
.fade-overlay-leave-to {
  opacity: 0;
}
</style>
