<script setup>
import { computed, ref, onMounted } from 'vue';
import { useChartTheme } from '@/config/chartTheme';
import { useFormatting } from '@/composables/useFormatting';
import { use as useECharts } from 'echarts/core';
import { CanvasRenderer } from 'echarts/renderers';
import { ScatterChart } from 'echarts/charts';
import {
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
  VisualMapComponent
]);

const props = defineProps({
  farmacias: { type: Array, default: () => [] },
  cnpjAtual: { type: String, required: true },
  regiaoNome: { type: String, default: '' },
  activeMetric: { type: String, default: 'score' } // 'score' ou 'percentual_sem_comprovacao'
});

const { chartTheme } = useChartTheme();
const { formatCurrencyFull } = useFormatting();
const isReady = ref(false);

const yMetric = computed(() => 
  props.activeMetric === 'percentual_sem_comprovacao' ? 'pct' : 'score'
);

import { watch } from 'vue';
watch(yMetric, (nv) => {
  console.log(`[RegionalRankChart] Métrica Y alterada para: ${nv}`);
}, { immediate: true });

watch(() => props.farmacias, (nv) => {
  console.log(`[RegionalRankChart] Dados das farmácias atualizados. Total: ${nv?.length || 0}`);
});

onMounted(() => {
  // O atraso de 400ms ajuda a evitar que o ECharts inicialize enquanto a aba 
  // do PrimeVue ainda está fazendo a animação de transição (opacidade/tamanho 0).
  setTimeout(() => { 
    isReady.value = true; 
  }, 450);
});

// Removemos os logs de amostragem para manter o console limpo, 
// mantendo apenas os de sincronização se necessário.
const chartData = computed(() => {
  if (!props.farmacias?.length) return { others: [], current: [] };

  const allSales = props.farmacias.map(f => f.totalMov || 0);
  const maxSales = Math.max(...allSales, 1000001);

  const mapX = (val) => {
    if (val <= 1000000) return (val / 1000000) * 70;
    const ratio = (val - 1000000) / (maxSales - 1000000);
    return 70 + (ratio * 30);
  };

  const getY = (f) => {
    // Tentamos score_risco ou score_risco_final (depende da API regional)
    const score = f.score_risco ?? f.score_risco_final ?? 0;
    const pct = f.percValSemComp ?? 0;
    return yMetric.value === 'pct' ? pct : score;
  };

  const others = [];
  const current = [];

  props.farmacias.forEach(f => {
    const valRealX = f.totalMov || 0;
    const valY = getY(f);
    
    const point = {
      name: f.razao_social,
      cnpj: f.cnpj,
      value: [mapX(valRealX), valY, valRealX, f.percValSemComp || 0, f.score_risco ?? f.score_risco_final ?? 0]
    };
    if (f.cnpj === props.cnpjAtual) current.push(point);
    else others.push(point);
  });

  return { others, current };
});

const chartOption = computed(() => {
  const c = chartTheme.value;
  const { others, current } = chartData.value;

  return {
    backgroundColor: 'transparent',
    grid: { top: 20, right: 30, bottom: 50, left: 70 },
    tooltip: {
      trigger: 'item',
      backgroundColor: c.tooltip,
      padding: [10, 15],
      borderColor: c.tooltipBorder,
      borderWidth: 1,
      textStyle: { color: c.tooltipText, fontSize: 12 },
      formatter: (params) => {
        const d = params.data;
        const isPct = yMetric.value === 'pct';
        const yLabel = isPct ? '% Não-Comprovação' : 'Score de Risco';
        const yVal   = isPct ? `${d.value[3].toFixed(1)}%` : d.value[4].toFixed(2);
        return `
          <div style="padding: 2px; color: ${c.tooltipText}">
            <div style="font-weight: 600; margin-bottom: 5px;">${d.name}</div>
            <div style="display: flex; justify-content: space-between; gap: 20px; font-size: 11px;">
              <span style="opacity: 0.7;">Vendas:</span>
              <span>${formatCurrencyFull(d.value[2])}</span>
            </div>
            <div style="display: flex; justify-content: space-between; gap: 20px; font-size: 11px; margin-top: 2px;">
              <span style="opacity: 0.7;">${yLabel}:</span>
              <span style="font-weight: 600; color: #f43f5e;">${yVal}</span>
            </div>
          </div>
        `;
      }
    },
    xAxis: {
      name: 'Volume de Vendas (R$)',
      nameLocation: 'middle',
      nameGap: 30,
      nameTextStyle: { color: c.textColor, fontSize: 10, fontWeight: 600 },
      type: 'value',
      min: 0,
      max: 100, // Nossa escala mapeada vai de 0 a 100
      splitLine: { 
        lineStyle: { color: c.grid, type: 'dashed', opacity: 0.5 },
        show: true
      },
      // Definimos ticks manuais para mostrar a quebra de escala
      interval: 10, 
      axisLabel: { 
        color: c.textColor, 
        fontSize: 10,
        formatter: (val) => {
           if (val === 0) return '0';
           if (val === 35) return '500k';
           if (val === 70) return '1M';
           if (val === 85) return 'Média+';
           if (val === 100) return 'Max';
           return ''; // Escondemos os intermediários para não poluir
        }
      }
    },
    yAxis: {
      name: yMetric.value === 'pct' ? '% Não-Comprovação' : 'Score de Risco',
      nameLocation: 'middle',
      nameGap: 45,
      nameTextStyle: { color: c.textColor, fontSize: 10, fontWeight: 600 },
      type: 'value',
      splitLine: { lineStyle: { color: c.grid, type: 'dashed', opacity: 0.5 } },
      axisLabel: {
        color: c.textColor,
        fontSize: 10,
        formatter: yMetric.value === 'pct' ? (v) => `${v}%` : undefined
      }
    },
    series: [
      {
        name: 'Vizinhos',
        type: 'scatter',
        data: others,
        symbolSize: 8,
        itemStyle: { color: c.muted, opacity: 0.4 },
        emphasis: { itemStyle: { opacity: 1, color: c.textColor } }
      },
      {
        name: 'Atual',
        type: 'scatter',
        data: current,
        symbolSize: 22,
        zlevel: 5,
        itemStyle: {
          color: '#f43f5e',
          shadowBlur: 15,
          shadowColor: 'rgba(244, 63, 94, 0.6)',
          borderColor: '#fff',
          borderWidth: 2
        },
        label: {
           show: false
        }
      }
    ]
  };
});
</script>

<template>
  <div class="regional-rank-wrapper">
    <!-- Legenda + Toggle -->
    <div class="chart-header-row">
      <div class="chart-legend-overlay">
        <div class="legend-item">
          <span class="dot-self"></span>
          <span>ESTABELECIMENTO ATUAL</span>
        </div>
        <div class="legend-item">
          <span class="dot-others"></span>
          <span>OUTRAS FARMÁCIAS</span>
        </div>
      </div>
    </div>

    <div class="chart-container">
      <VChart v-if="isReady" :option="chartOption" autoresize class="echart" />
      <div v-else class="loading-state">
        <i class="pi pi-spin pi-spinner" />
        <span>Sincronizando farmácias da região...</span>
      </div>
    </div>
  </div>
</template>

<style scoped>
.regional-rank-wrapper {
  flex: 1;
  display: flex;
  flex-direction: column;
  position: relative;
  width: 100%;
  padding: 1rem;
  min-height: 350px;
}

.chart-container {
  flex: 1;
  width: 100%;
  height: 100%;
}

.echart {
  width: 100%;
  height: 100%;
}

.chart-header-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 0.5rem;
  gap: 0.75rem;
}

.chart-legend-overlay {
  display: flex;
  gap: 1.25rem;
}

.y-metric-toggle {
  display: flex;
  gap: 0.25rem;
  background: color-mix(in srgb, var(--primary-color) 6%, transparent);
  border: 1px solid color-mix(in srgb, var(--primary-color) 20%, transparent);
  border-radius: 8px;
  padding: 3px;
}

.metric-btn {
  background: transparent;
  border: none;
  border-radius: 5px;
  padding: 0.25rem 0.6rem;
  font-size: 0.68rem;
  font-weight: 500;
  color: var(--text-secondary);
  cursor: pointer;
  transition: background 0.18s, color 0.18s;
  white-space: nowrap;
}

.metric-btn:hover {
  color: var(--primary-color);
}

.metric-btn.active {
  background: var(--primary-color);
  color: #fff;
}

.legend-item {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  font-size: 0.7rem;
  font-weight: 700;
  color: var(--text-secondary);
  letter-spacing: 0.03em;
  text-transform: uppercase;
}

.dot-self {
  width: 12px;
  height: 12px;
  background: #f43f5e;
  border-radius: 50%;
  box-shadow: 0 0 8px rgba(244, 63, 94, 0.6);
  border: 1px solid #fff;
}

.dot-others {
  width: 10px;
  height: 10px;
  background: var(--text-muted);
  opacity: 0.5;
  border-radius: 50%;
}

.loading-state {
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

.loading-state i {
  font-size: 1.5rem;
  color: var(--primary-color);
}
</style>
