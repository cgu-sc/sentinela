<script setup>
import { computed } from 'vue';
import { useAnalyticsStore } from '@/stores/analytics';
import { useThemeStore } from '@/stores/theme';
import { useFormatting } from '@/composables/useFormatting';
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

// ── Props ─────────────────────────────────────────────────────────────────
const props = defineProps({
  height: { type: Number, default: 420 },
  grow:   { type: Boolean, default: false },
});

// ── Stores ────────────────────────────────────────────────────────────────
const analyticsStore = useAnalyticsStore();
const themeStore     = useThemeStore();
const { resultadoSentinelaUF, isLoading } = storeToRefs(analyticsStore);
const { formatBRL, formatCurrencyFull } = useFormatting();

// ── Dados ordenados por % Valor decrescente ───────────────────────────────
const sortedData = computed(() =>
  [...resultadoSentinelaUF.value].sort((a, b) => (b.percValSemComp ?? 0) - (a.percValSemComp ?? 0))
);

// ── Tema ──────────────────────────────────────────────────────────────────
const C = computed(() => themeStore.isDark
  ? {
      text: '#e2e8f0', muted: '#94a3b8', grid: '#ffffff0f',
      bg: 'transparent', tooltip: '#1e293b', border: '#334155',
      bar1:     '#6366f1',
      bar1Grad: '#6366f144',
      bar2:     '#10b981',
      bar2Grad: '#10b98144',
      area:     '#3b82f6',
      areaGrad: '#3b82f608',
    }
  : {
      text: '#1e293b', muted: '#64748b', grid: '#0000000d',
      bg: 'transparent', tooltip: '#ffffff', border: '#e2e8f0',
      bar1:     '#4f46e5',
      bar1Grad: '#4f46e522',
      bar2:     '#059669',
      bar2Grad: '#05966922',
      area:     '#2563eb',
      areaGrad: '#2563eb08',
    }
);

// ── Opção ECharts ─────────────────────────────────────────────────────────
const chartOption = computed(() => {
  const c    = C.value;
  const ufs  = sortedData.value.map(i => i.uf ?? 'ND');

  return {
    backgroundColor: c.bg,
    animation: true,
    animationDuration: 1000,
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

    // Dois grids sincronizados
    grid: [
      // Painel superior — Volume Total
      { top: 44, left: 80, right: 24, height: '35%' },
      // Painel inferior — % por UF (sem gap entre os dois)
      { top: '46%', left: 80, right: 24, bottom: 56 },
    ],

    // X axis espelhado nos dois painéis
    xAxis: [
      {
        gridIndex: 0,
        type: 'category',
        data: ufs,
        axisLine:  { lineStyle: { color: c.grid } },
        axisTick:  { show: false },
        axisLabel: { show: false },
        axisPointer: { label: { show: false } },
      },
      {
        gridIndex: 1,
        type: 'category',
        data: ufs,
        axisLine:  { lineStyle: { color: c.grid } },
        axisTick:  { show: false },
        axisLabel: { color: c.muted, fontSize: 11, fontWeight: 700, fontFamily: 'Inter, sans-serif' },
        name: 'UF — ordenado por % Valor s/ Comprovação (decrescente)',
        nameLocation: 'middle',
        nameGap: 40,
        nameTextStyle: { color: c.muted, fontSize: 10, fontWeight: 500 },
      },
    ],

    yAxis: [
      // Painel superior — BRL
      {
        gridIndex: 0,
        type: 'value',
        name: 'Valor Total',
        nameLocation: 'end',
        nameTextStyle: { color: c.area, fontSize: 11, fontWeight: 700 },
        axisLine:  { show: false },
        axisTick:  { show: false },
        splitLine: { lineStyle: { color: c.grid, type: 'dashed' } },
        axisLabel: { color: c.muted, fontSize: 10, formatter: (v) => formatBRL(v) },
      },
      // Painel inferior — %
      {
        gridIndex: 1,
        type: 'value',
        name: '% S/ Comp',
        nameLocation: 'end',
        nameTextStyle: { color: c.muted, fontSize: 11, fontWeight: 700 },
        axisLine:  { show: false },
        axisTick:  { show: false },
        splitLine: { lineStyle: { color: c.grid, type: 'dashed' } },
        axisLabel: { color: c.muted, fontSize: 10, formatter: (v) => `${v}%` },
      },
    ],

axisPointer: {
      link: [{ xAxisIndex: 'all' }],
      label: { backgroundColor: c.tooltip },
    },

    tooltip: {
      trigger: 'axis',
      axisPointer: { type: 'shadow', shadowStyle: { color: 'rgba(255,255,255,0.04)' } },
      backgroundColor: c.tooltip,
      borderColor: c.border,
      borderWidth: 1,
      padding: [12, 16],
      textStyle: { color: c.text, fontFamily: 'Inter, sans-serif', fontSize: 12 },
      formatter: (params) => {
        const idx  = params[0]?.dataIndex;
        const item = sortedData.value[idx];
        if (!item) return '';
        const perc = item.percValSemComp ?? 0;
        const riskColor = perc > 20 ? '#ef4444' : perc > 10 ? '#f97316' : perc > 5 ? '#f59e0b' : '#10b981';
        const riskLabel = perc > 20 ? 'Alto' : perc > 10 ? 'Moderado' : perc > 5 ? 'Médio' : 'Baixo';
        return `
          <div style="font-weight:700;font-size:15px;margin-bottom:10px;display:flex;align-items:center;gap:8px;">
            ${item.uf}
            <span style="font-size:10px;font-weight:700;padding:2px 8px;border-radius:10px;
                         background:${riskColor}22;color:${riskColor};">RISCO ${riskLabel.toUpperCase()}</span>
          </div>
          <div style="display:grid;grid-template-columns:1fr 1fr;gap:8px 18px;">
            <div style="grid-column:1/-1;">
              <div style="font-size:10px;opacity:.6;letter-spacing:.04em;display:flex;align-items:center;gap:5px;">
                <span style="width:10px;height:10px;border-radius:2px;background:${c.area};display:inline-block;"></span>
                VALOR TOTAL MOVIMENTADO
              </div>
              <div style="font-weight:700;font-size:14px;">${formatCurrencyFull(item.totalMov ?? 0)}</div>
            </div>
            <div>
              <div style="font-size:10px;opacity:.6;letter-spacing:.04em;display:flex;align-items:center;gap:5px;">
                <span style="width:10px;height:10px;border-radius:2px;background:#ef4444;display:inline-block;"></span>
                % VALOR S/ COMP
              </div>
              <div style="font-weight:700;font-size:14px;color:${riskColor};">${perc.toFixed(2)}%</div>
            </div>
            <div>
              <div style="font-size:10px;opacity:.6;letter-spacing:.04em;display:flex;align-items:center;gap:5px;">
                <span style="width:10px;height:10px;border-radius:2px;background:#f97316;display:inline-block;"></span>
                % QTDE S/ COMP
              </div>
              <div style="font-weight:700;font-size:14px;">${(item.percQtdeSemComp ?? 0).toFixed(2)}%</div>
            </div>
            <div>
              <div style="font-size:10px;opacity:.6;letter-spacing:.04em;">CNPJs</div>
              <div style="font-weight:600;">${(item.cnpjs ?? 0).toLocaleString('pt-BR')}</div>
            </div>
          </div>`;
      },
    },

    series: [
      // Painel superior — Área: Valor Total Movimentado
      {
        name: 'Valor Total Movimentado',
        type: 'line',
        xAxisIndex: 0,
        yAxisIndex: 0,
        smooth: true,
        symbol: 'none',
        data: sortedData.value.map(i => parseFloat((i.totalMov ?? 0).toFixed(2))),
        lineStyle: { color: c.area, width: 2 },
        areaStyle: {
          color: {
            type: 'linear', x: 0, y: 0, x2: 0, y2: 1,
            colorStops: [
              { offset: 0, color: c.area + 'bb' },
              { offset: 1, color: c.area + '08' },
            ],
          },
        },
        z: 1,
      },

      // Painel inferior — Barra: % Valor s/ Comprovação (vermelho)
      {
        name: '% Valor s/ Comp',
        type: 'bar',
        xAxisIndex: 1,
        yAxisIndex: 1,
        barMaxWidth: 20,
        data: sortedData.value.map(i => parseFloat((i.percValSemComp ?? 0).toFixed(2))),
        itemStyle: {
          borderRadius: [4, 4, 0, 0],
          color: {
            type: 'linear', x: 0, y: 0, x2: 0, y2: 1,
            colorStops: [
              { offset: 0, color: '#ef4444' },
              { offset: 1, color: '#ef444433' },
            ],
          },
        },
        emphasis: { itemStyle: { opacity: 1 } },
        z: 2,
      },

      // Painel inferior — Barra: % Qtde s/ Comprovação (laranja)
      {
        name: '% Qtde s/ Comp',
        type: 'bar',
        xAxisIndex: 1,
        yAxisIndex: 1,
        barMaxWidth: 20,
        data: sortedData.value.map(i => parseFloat((i.percQtdeSemComp ?? 0).toFixed(2))),
        itemStyle: {
          borderRadius: [4, 4, 0, 0],
          color: {
            type: 'linear', x: 0, y: 0, x2: 0, y2: 1,
            colorStops: [
              { offset: 0, color: '#f97316' },
              { offset: 1, color: '#f9731633' },
            ],
          },
        },
        emphasis: { itemStyle: { opacity: 1 } },
        z: 2,
      },
    ],
  };
});
</script>

<template>
  <div class="chart-section shadow-card" :class="{ 'is-refreshing': isLoading, 'grow': props.grow }">
    <div class="section-header">
      <i class="pi pi-chart-bar"></i>
      <h3>% VALOR, % QTDE S/ COMPROVAÇÃO E VOLUME MOVIMENTADO POR UF</h3>
      <div class="spacer"></div>
      <Button
        icon="pi pi-info-circle"
        v-tooltip.top="'Barras = Valor Total Movimentado; Área vermelha = Valor sem Comprovação (exposição ao risco dentro do mercado); Linha = % Valor sem Comprovação.'"
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
}

.chart-section.grow {
  flex: 1;
  min-height: 0;
}

.chart-wrapper {
  height: v-bind('props.height + "px"');
  margin: 0 -1rem -1rem -1rem;
}

.grow .chart-wrapper {
  flex: 1;
  min-height: 0;
  height: auto;
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
