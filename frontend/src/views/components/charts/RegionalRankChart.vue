<script setup>
import { computed, ref, onMounted, nextTick } from 'vue';
import { useChartTheme } from '@/config/chartTheme';
import { useFormatting } from '@/composables/useFormatting';
import { use as useECharts } from 'echarts/core';
import { CanvasRenderer } from 'echarts/renderers';
import { ScatterChart } from 'echarts/charts';
import {
  TitleComponent,
  TooltipComponent,
  GridComponent,
  VisualMapComponent
} from 'echarts/components';
import VChart from 'vue-echarts';

useECharts([
  CanvasRenderer,
  ScatterChart,
  GridComponent,
  TooltipComponent,
  TitleComponent,
  VisualMapComponent
]);

const props = defineProps({
  farmacias: { type: Array, default: () => [] },
  cnpjAtual: { type: String, required: true },
  regiaoNome: { type: String, default: '' }
});

const { chartTheme } = useChartTheme();
const { formatBRL } = useFormatting();
const isReady = ref(false);

onMounted(() => {
  // Delay de 500ms para garantir que a aba do PrimeVue já renderizou o DOM
  setTimeout(() => {
    isReady.value = true;
  }, 500);
});

const chartData = computed(() => {
  if (!props.farmacias?.length) return { others: [], current: [] };

  const others = [];
  const current = [];

  props.farmacias.forEach(f => {
    const point = {
      name: f.razao_social,
      cnpj: f.cnpj,
      value: [f.totalMov || 0, f.score_risco || 0]
    };

    if (f.cnpj === props.cnpjAtual) {
      current.push(point);
    } else {
      others.push(point);
    }
  });

  return { others, current };
});

const chartOption = computed(() => {
  const c = chartTheme.value;
  const { others, current } = chartData.value;

  return {
    backgroundColor: 'transparent',
    grid: { top: 40, right: 30, bottom: 50, left: 60 },
    tooltip: {
      trigger: 'item',
      backgroundColor: 'rgba(15, 23, 42, 0.9)',
      padding: [10, 15],
      textStyle: { color: '#fff' },
      formatter: (params) => {
        const d = params.data;
        return `<b>${d.name}</b><br/>Vendas: ${formatBRL(d.value[0])}<br/>Score: ${d.value[1].toFixed(2)}`;
      }
    },
    xAxis: {
      name: 'Vendas (R$)',
      nameLocation: 'middle',
      nameGap: 30,
      type: 'value',
      splitLine: { lineStyle: { color: c.splitLine, type: 'dashed' } },
      axisLabel: { color: c.text }
    },
    yAxis: {
      name: 'Score de Risco',
      nameLocation: 'middle',
      nameGap: 40,
      type: 'value',
      splitLine: { lineStyle: { color: c.splitLine, type: 'dashed' } },
      axisLabel: { color: c.text }
    },
    series: [
      {
        name: 'Vizinhos',
        type: 'scatter',
        data: others,
        symbolSize: 10,
        itemStyle: { color: 'rgba(148, 163, 184, 0.5)' }
      },
      {
        name: 'Selecionada',
        type: 'scatter',
        data: current,
        symbolSize: 25,
        zlevel: 1,
        itemStyle: {
          color: '#f43f5e',
          shadowBlur: 10,
          shadowColor: 'rgba(244, 63, 94, 0.8)',
          borderColor: '#fff',
          borderWidth: 2
        }
      }
    ]
  };
});
</script>

<template>
  <div class="regional-rank-card">
    <div class="chart-header">
      <div class="header-left">
        <i class="pi pi-compass section-icon"></i>
        <div class="header-info">
          <h3>Posicionamento de Risco Regional</h3>
          <span class="subtitle">{{ regiaoNome }}</span>
        </div>
      </div>
      <div class="legend">
        <div class="legend-item"><span class="dot self"></span> VOCÊ</div>
        <div class="legend-item"><span class="dot others"></span> Outros</div>
      </div>
    </div>
    
    <div class="chart-wrapper">
      <VChart v-if="isReady" :option="chartOption" autoresize class="echart" />
      <div v-else class="loading-placeholder">
        <i class="pi pi-spin pi-spinner text-2xl mb-2"></i>
        <span>Preparando análise regional...</span>
      </div>
    </div>
  </div>
</template>

<style scoped>
.regional-rank-card {
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.05);
  border-radius: 12px;
  padding: 1.25rem;
  display: flex;
  flex-direction: column;
  gap: 1rem;
}

.chart-header { display: flex; justify-content: space-between; align-items: center; }
.header-left { display: flex; gap: 0.75rem; align-items: center; }
.section-icon { font-size: 1rem; color: var(--primary-color); background: color-mix(in srgb, var(--primary-color) 10%, transparent); padding: 0.5rem; border-radius: 8px; }
.header-info h3 { margin: 0; font-size: 1rem; font-weight: 700; }
.subtitle { font-size: 0.8rem; color: var(--text-muted); }
.legend { display: flex; gap: 1rem; }
.legend-item { display: flex; align-items: center; gap: 0.4rem; font-size: 0.7rem; font-weight: 600; }
.dot { width: 8px; height: 8px; border-radius: 50%; }
.dot.self { background: #f43f5e; }
.dot.others { background: rgba(148, 163, 184, 0.6); }

/* ALTURA FIXA E FUNDO TRANSPARENTE */
.chart-wrapper {
  width: 100%;
  height: 350px;
  position: relative;
  border-radius: 8px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: transparent;
}

.echart { width: 100%; height: 100%; }

.loading-placeholder {
  display: flex;
  flex-direction: column;
  align-items: center;
  color: var(--text-muted);
  font-size: 0.8rem;
}
</style>
