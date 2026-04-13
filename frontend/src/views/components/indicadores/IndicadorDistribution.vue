<script setup>
import { computed, ref, watch, onMounted } from 'vue';
import { useChartTheme } from '@/config/chartTheme';
import { INDICATOR_THRESHOLDS } from '@/config/riskConfig';
import VChart from 'vue-echarts';
import { use } from 'echarts/core';
import { CanvasRenderer } from 'echarts/renderers';
import { BarChart, LineChart } from 'echarts/charts';
import {
  GridComponent,
  TooltipComponent,
  LegendComponent,
  MarkLineComponent,
  VisualMapComponent,
} from 'echarts/components';

const RISK_COLORS = {
  normal: '#00c853',
  warning: '#ffd600',
  critical: '#ff5252'
};

use([
  CanvasRenderer,
  BarChart,
  LineChart,
  GridComponent,
  TooltipComponent,
  LegendComponent,
  MarkLineComponent,
  VisualMapComponent,
]);

const props = defineProps({
  /** Array de CNPJs { cnpj, risco_reg, status, ... } */
  cnpjs: { type: Array, default: () => [] },
  /** Chave do indicador de threshold (default, teto, etc.) */
  thresholdKey: { type: String, default: 'default' },
  isLoading: { type: Boolean, default: false },
  /** Benchmarking Regional (MAD e Mediana vindos do contexto superior) */
  regionalMedian: { type: Number, default: null },
  regionalMad: { type: Number, default: null },
});

const { chartTheme, chartUFAccents } = useChartTheme();

// Limiares ativos (baseado na config global)
const thresholds = computed(() => {
  return INDICATOR_THRESHOLDS[props.thresholdKey] || INDICATOR_THRESHOLDS.default;
});

// Processamento dos dados para a Curva Acumulada (CDF)
const distributionData = computed(() => {
  if (!props.cnpjs.length) return { axis: [], values: [] };

  const risks = props.cnpjs
    .map(c => c.risco_reg)
    .filter(r => r != null && !isNaN(r))
    .sort((a, b) => a - b);

  if (!risks.length) return { axis: [], values: [] };

  const total = risks.length;

  // Cálculo do Limiar Estatístico (Modified Z-Score - Iglewicz & Hoaglin)
  // Se recebemos o MAD regional do backend, usamos ele (Benchmarking Superior)
  // Caso contrário, calculamos sobre a amostra local (Calculo Local)
  const isRegional = props.regionalMad !== null;
  const median = isRegional ? 1.0 : risks[Math.floor(total / 2)];
  
  let mad = 0.0001;
  if (isRegional) {
    mad = props.regionalMad;
  } else {
    const absDeviations = risks.map(r => Math.abs(r - median)).sort((a, b) => a - b);
    mad = absDeviations[Math.floor(total / 2)] || 0.0001;
  }

  // Ponto onde Modified Z-Score atinge 3.5 (Limite de anomalia extrema)
  let threshold = median + (3.5 * mad / 0.6745);
  let method = isRegional ? 'Modified Z-Score (Regional)' : 'Modified Z-Score (Local)';

  // Se o limiar calculado cobrir 100% da rede, usamos o Percentil 95 como salvaguarda
  if (threshold >= risks[total - 1] || isNaN(threshold)) {
    threshold = risks[Math.floor(total * 0.95)];
    method = 'Percentil 95 (Cauda)';
  }

  const suggestion = parseFloat(threshold.toFixed(2));

  // ── Eixo X DINÂMICO ──
  // O gráfico se expande se a sugestão ou os dados forem além de 5.0x
  const maxPossible = risks[total - 1] || 0;
  const limitX = Math.max(5.0, Math.ceil(Math.min(suggestion + 1, maxPossible + 0.5)));
  
  const axis = [];
  for (let i = 0; i <= limitX; i += 0.2) {
    axis.push(`${i.toFixed(1)}x`);
  }

  const values = axis.map(label => {
    const val = parseFloat(label);
    const count = risks.filter(r => r <= val).length;
    return parseFloat(((count / total) * 100).toFixed(1));
  });

  // Contagem exata de alvos (sem arredondamentos de bins)
  const countCritico = risks.filter(r => r >= thresholds.value.critico).length;
  const countSuggestion = risks.filter(r => r >= threshold).length;

  // Porcentagem de Cobertura (População protegida / abaixo do limiar)
  const pctCritico = total > 0 ? (((total - countCritico) / total) * 100).toFixed(1) : 0;
  const pctSuggestion = total > 0 ? (((total - countSuggestion) / total) * 100).toFixed(1) : 0;

  return { 
    axis, 
    values, 
    total, 
    suggestion: parseFloat(threshold.toFixed(2)), 
    method,
    isRegional,
    countCritico,
    countSuggestion,
    pctCritico,
    pctSuggestion
  };
});

const chartOption = computed(() => {
  const { axis, values, total, suggestion } = distributionData.value;
  const t = thresholds.value;
  const c = chartTheme.value;
  const acc = chartUFAccents.value;

  return {
    backgroundColor: 'transparent',
    animation: true,
    animationDuration: 1000,
    animationEasing: 'cubicOut',
    textStyle: { fontFamily: 'Inter, sans-serif' },
    
    tooltip: {
      trigger: 'axis',
      axisPointer: {
        type: 'line',
        lineStyle: { color: c.grid, width: 1, type: 'dashed' }
      },
      backgroundColor: c.tooltip,
      borderColor: c.tooltipBorder,
      borderWidth: 1,
      textStyle: { color: c.tooltipText, fontSize: 12 },
      shadowBlur: 10,
      shadowColor: 'rgba(0,0,0,0.1)', // Sombra ajustada para temas claros tb aparecerem suaves
      formatter: (params) => {
        const p = params[0];
        const count = Math.round((p.value / 100) * total);
        const rem = total - count;
        return `
          <div style="padding: 4px; min-width: 140px; color: ${c.tooltipText}">
            <div style="opacity: 0.7; font-size: 10px; text-transform: uppercase; margin-bottom: 2px;">Limiar Geográfico:</div>
            <div style="font-size: 14px; font-weight: 700; margin-bottom: 8px;">${p.name}</div>
            
            <div style="display: flex; justify-content: space-between; gap: 15px; margin-bottom: 2px;">
              <span style="opacity: 0.7; font-size: 10px; text-transform: uppercase;">Cobertura:</span>
              <span style="font-weight: 700;">${p.value}%</span>
            </div>
            
            <div style="display: flex; justify-content: space-between; gap: 15px;">
              <span style="opacity: 0.7; font-size: 10px; text-transform: uppercase;">Alvos:</span>
              <span style="font-weight: 800; color: ${RISK_COLORS.critical}">${rem}</span>
            </div>
          </div>
        `;
      },
    },
    grid: {
      top: 80,
      left: 50,
      right: 60, // Aumentado para evitar corte lateral
      bottom: 40,
    },
    xAxis: {
      type: 'category',
      data: axis,
      boundaryGap: false,
      axisLabel: { color: c.muted, fontSize: 10, interval: 4 },
      axisLine: { lineStyle: { color: c.borderColor } },
      axisTick: { show: false },
    },
    yAxis: {
      type: 'value',
      min: 0,
      max: 100,
      axisLabel: { formatter: '{value}%', color: c.muted, fontSize: 10 },
      splitLine: { lineStyle: { color: c.borderColor, type: 'dashed', opacity: 0.5 } },
    },
    series: [
      {
        name: 'Cobertura Acumulada',
        type: 'line',
        data: values,
        smooth: true,
        showSymbol: false,
        lineStyle: { 
          width: 2.5, 
          color: acc.area,
          shadowBlur: 8,
          shadowColor: acc.area + '44',
          shadowOffsetY: 2
        },
        areaStyle: {
          color: {
            type: 'linear',
            x: 0, y: 0, x2: 0, y2: 1,
            colorStops: [
              { offset: 0, color: acc.area + '44' },
              { offset: 1, color: acc.area + '02' },
            ]
          }
        },
        markLine: {
          symbol: ['none', 'none'],
          label: {
            show: true,
            position: 'end',
            fontSize: 10,
            fontWeight: 700,
            backgroundColor: c.tooltipBg,
            padding: [4, 8],
            borderRadius: 4,
            borderColor: c.borderColor,
            borderWidth: 1,
            color: c.textColor,
          },
          data: [
            {
              xAxis: Math.round(t.critico / 0.2),
              lineStyle: { color: RISK_COLORS.critical, type: 'solid', width: 2.5, opacity: 0.8 },
              label: { 
                formatter: `Crítico: ${t.critico}x | ${distributionData.value.countCritico} alvos (${distributionData.value.pctCritico}% cobertura)`, 
                color: RISK_COLORS.critical,
                position: 'end',
                distance: 10,
                align: Math.round(t.critico / 0.2) > axis.length / 2 ? 'right' : 'left'
              },
            },
            {
              xAxis: Math.round(suggestion / 0.2),
              lineStyle: { color: c.muted, type: 'dotted', width: 1.5, opacity: 0.5 },
              label: { 
                formatter: `Sugestão: ${suggestion}x | ${distributionData.value.countSuggestion} alvos (${distributionData.value.pctSuggestion}% cobertura)`, 
                color: c.muted,
                position: 'end',
                distance: 40,
                align: Math.round(suggestion / 0.2) > axis.length / 2 ? 'right' : 'left',
                fontSize: 9,
                fontWeight: 500
              },
            },
          ],
        },
      },
    ],
  };
});
</script>

<template>
  <div class="ind-dist-card" :class="{ 'is-loading': isLoading }">
    <div class="dist-header">
      <div class="dist-title-wrap">
        <i class="pi pi-chart-line dist-icon" />
        <div class="dist-text">
          <h3 class="dist-title">Distribuição e Calibração de Risco</h3>
          <p class="dist-subtitle">Frequência de estabelecimentos por múltiplos da mediana regional</p>
        </div>
      </div>
      
      <div class="dist-impact-summary">
        <template v-if="!isLoading && cnpjs.length">
          <div class="impact-badge critical">
            <span class="impact-label">Crítico ({{ thresholds.critico }}x)</span>
            <span class="impact-value">{{ distributionData.countCritico }} alvos</span>
            <span class="impact-pct">{{ distributionData.pctCritico }}% cobertura</span>
          </div>
          <div class="impact-badge suggestion">
            <span class="impact-label">Sugestão ({{ distributionData.suggestion }}x)</span>
            <span class="impact-value">{{ distributionData.countSuggestion }} alvos</span>
            <span class="impact-pct">{{ distributionData.pctSuggestion }}% cobertura</span>
          </div>
        </template>
        <template v-else-if="isLoading">
          <div class="impact-skeleton"></div>
          <div class="impact-skeleton"></div>
        </template>
      </div>

      <div class="dist-legend">
        <div class="legend-item">
          <span class="dot normal"></span>
          <span>Normal</span>
        </div>
        <div class="legend-item">
          <span class="dot critical"></span>
          <span>Crítico (>{{ thresholds.critico }}x)</span>
        </div>
      </div>
    </div>

    <div class="dist-chart-wrap">
      <div v-if="!cnpjs.length && !isLoading" class="empty-dist">
        <i class="pi pi-info-circle" />
        <p>Dados insuficientes para gerar a curva de distribuição.</p>
      </div>
      <v-chart v-else class="dist-chart" :option="chartOption" autoresize />
    </div>

    <div class="dist-footer">
      <div class="footer-grid">
        <div class="info-alert info" :class="{ 'is-regional': distributionData.isRegional }">
          <i :class="distributionData.isRegional ? 'pi pi-compass' : 'pi pi-info-circle'" />
          <span v-if="distributionData.isRegional">
            <strong>Benchmarking Regional Ativo</strong>. Calibragem baseada na <strong>Região de Saúde</strong>. 
            Amostra municipal integrada ao contexto regional para maior precisão.
          </span>
          <span v-else>
            Esta análise utiliza a <strong>Mediana Local</strong> como base. 
            O valor de 1.0x representa o comportamento padrão da seleção atual. 
          </span>
        </div>

        <div v-if="distributionData.suggestion" class="info-alert suggestion">
          <i class="pi pi-sparkles" />
          <span>
            <strong>Sugestão Matemática: {{ distributionData.suggestion }}x</strong>. 
            Baseado no método de {{ distributionData.method }} (Iglewicz & Hoaglin), este é o ponto onde o desvio (escore > 3.5) indica uma anomalia extrema.
          </span>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.ind-dist-card {
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  border-radius: 12px;
  padding: 1.25rem;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.05);
  display: flex;
  flex-direction: column;
  gap: 1rem;
  transition: opacity 0.3s ease;
}

.ind-dist-card.is-loading {
  opacity: 0.6;
  pointer-events: none;
}

.dist-header {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  gap: 1.5rem;
}

.dist-title-wrap {
  display: flex;
  gap: 0.75rem;
  align-items: center;
}

.dist-icon {
  font-size: 1.25rem;
  color: var(--primary-color);
  background: color-mix(in srgb, var(--primary-color) 10%, transparent);
  padding: 0.5rem;
  border-radius: 8px;
}

.dist-title {
  margin: 0;
  font-size: 0.95rem;
  font-weight: 600;
  color: var(--text-color);
}

.dist-subtitle {
  margin: 0;
  font-size: 0.72rem;
  color: var(--text-muted);
}

.dist-impact-summary {
  display: flex;
  gap: 1.5rem;
  margin-left: auto;
  margin-right: 2rem;
  min-height: 48px; /* Trava a altura para evitar pulos */
  align-items: center;
}

.impact-skeleton {
  width: 100px;
  height: 36px;
  background: color-mix(in srgb, var(--card-border) 40%, transparent);
  border-radius: 6px;
  animation: pulse-impact 1.5s infinite ease-in-out;
}

@keyframes pulse-impact {
  0% { opacity: 0.3; }
  50% { opacity: 0.6; }
  100% { opacity: 0.3; }
}

.impact-badge {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  animation: fade-in-impact 0.3s ease-out;
}

@keyframes fade-in-impact {
  from { opacity: 0; transform: translateY(4px); }
  to { opacity: 1; transform: translateY(0); }
}

.impact-label {
  font-size: 0.65rem;
  text-transform: uppercase;
  color: var(--text-muted);
  font-weight: 500;
  letter-spacing: 0.05em;
}

.impact-value {
  font-size: 1rem;
  font-weight: 700;
  line-height: 1;
  margin-top: 0.2rem;
}

.impact-pct {
  font-size: 0.6rem;
  color: var(--text-muted);
  margin-top: 0.15rem;
}

.impact-badge.critical .impact-value { color: var(--risk-indicator-critical); }
.impact-badge.suggestion .impact-value { color: var(--text-color); }

.dist-legend {
  display: flex;
  gap: 1rem;
}

.legend-item {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  font-size: 0.65rem;
  font-weight: 600;
  color: var(--text-muted);
  text-transform: uppercase;
  letter-spacing: 0.03em;
}

.dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
}
.dot.normal { background: var(--risk-indicator-normal); }
.dot.warning { background: var(--risk-indicator-warning); }
.dot.critical { background: var(--risk-indicator-critical); }

.dist-chart-wrap {
  height: 20vh;
  min-height: 180px;
  width: 100%;
  position: relative;
}

.dist-chart {
  width: 100%;
  height: 100%;
}

.empty-dist {
  position: absolute;
  inset: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 0.5rem;
  color: var(--text-muted);
  font-size: 0.8rem;
}

.dist-footer {
  padding-top: 0.25rem;
  border-top: 1px solid var(--card-border);
}

.footer-grid {
  display: grid;
  grid-template-columns: 1fr 1.2fr;
  gap: 1rem;
}

.info-alert {
  display: flex;
  gap: 0.6rem;
  padding: 0.65rem 0.85rem;
  border-radius: 6px;
  font-size: 0.72rem;
  color: var(--text-color);
  line-height: 1.4;
}

.info-alert.info.is-regional {
  background: color-mix(in srgb, var(--primary-color) 12%, var(--card-bg));
  border: 1px solid color-mix(in srgb, var(--primary-color) 25%, transparent);
  opacity: 1;
}

.info-alert.suggestion {
  background: color-mix(in srgb, var(--risk-indicator-warning) 8%, var(--card-bg));
  border: 1px dashed color-mix(in srgb, var(--risk-indicator-warning) 30%, transparent);
}

.info-alert.info i { color: var(--primary-color); }
.info-alert.suggestion i { color: var(--risk-indicator-warning); }

.info-alert i {
  margin-top: 2px;
}

.info-alert strong {
  font-weight: 600;
}
</style>
