<script setup>
import { computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useAnalyticsStore } from '@/stores/analytics';
import { storeToRefs } from 'pinia';
import { useFormatting } from '@/composables/useFormatting';
import { useChartTheme } from '@/config/chartTheme';
import { CHART_TOOLTIP_SHADOW } from '@/config/colors.js';
import { RISK_THRESHOLDS } from '@/config/riskConfig';

import VChart from 'vue-echarts';
import { use } from 'echarts/core';
import { BarChart } from 'echarts/charts';
import { GridComponent, TooltipComponent, LegendComponent } from 'echarts/components';
import { CanvasRenderer } from 'echarts/renderers';

use([BarChart, GridComponent, TooltipComponent, LegendComponent, CanvasRenderer]);

const route = useRoute();
const cnpj = computed(() => route.params.cnpj);

const { formatCurrencyFull } = useFormatting();
const { chartTheme, chartDataColors } = useChartTheme();

const analyticsStore = useAnalyticsStore();
const { evolucaoFinanceira: evolucaoData, evolucaoLoading, evolucaoLoaded } = storeToRefs(analyticsStore);

onMounted(() => {
  if (cnpj.value) analyticsStore.fetchEvolucaoFinanceira(cnpj.value);
});

// ── Cores dos gráficos ────────────────────────────────────
const C = computed(() => ({
  ...chartTheme.value,
  ...chartDataColors.value,
}));

// ── Opção: barras empilhadas ──────────────────────────────
const chartOption = computed(() => {
  const c         = C.value;
  const semestres = evolucaoData.value?.semestres ?? [];
  const labels    = semestres.map(s => s.semestre);
  const regular   = semestres.map(s => s.regular);
  const irregular = semestres.map(s => s.irregular);

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

    grid: { top: 44, left: 80, right: 24, bottom: 32, containLabel: false },

    tooltip: {
      trigger: 'axis',
      axisPointer: { type: 'shadow', shadowStyle: { color: CHART_TOOLTIP_SHADOW } },
      backgroundColor: c.tooltip,
      borderColor: c.border,
      borderWidth: 1,
      padding: [12, 16],
      textStyle: { color: c.text, fontFamily: 'Inter, sans-serif', fontSize: 12 },
      formatter: (params) => {
        const idx = params[0]?.dataIndex ?? 0;
        const s   = semestres[idx];
        if (!s) return '';
        return `
          <div style="font-weight:700;font-size:14px;margin-bottom:10px;">${s.semestre}</div>
          <div style="display:flex;flex-direction:column;gap:6px;">
            <div style="display:flex;align-items:center;gap:8px;">
              <span style="width:10px;height:10px;border-radius:2px;background:${c.green};display:inline-block;"></span>
              <span style="font-size:10px;opacity:.6;letter-spacing:.04em;text-transform:uppercase;">Regulares</span>
            </div>
            <div style="font-weight:700;font-size:13px;margin-bottom:2px;">${formatCurrencyFull(s.regular)}</div>
            <div style="display:flex;align-items:center;gap:8px;">
              <span style="width:10px;height:10px;border-radius:2px;background:${c.red};display:inline-block;"></span>
              <span style="font-size:10px;opacity:.6;letter-spacing:.04em;text-transform:uppercase;">Irregulares</span>
            </div>
            <div style="font-weight:700;font-size:13px;color:${c.red};margin-bottom:2px;">${formatCurrencyFull(s.irregular)} <span style="opacity:.7">(${s.pct_irregular.toFixed(1)}%)</span></div>
            <div style="border-top:1px solid ${c.border};padding-top:6px;font-weight:700;font-size:13px;">Total: ${formatCurrencyFull(s.total)}</div>
          </div>`;
      },
    },

    xAxis: {
      type: 'category',
      data: labels,
      axisLine:  { lineStyle: { color: c.grid } },
      axisTick:  { show: false },
      axisLabel: { color: c.muted, fontSize: 11, fontWeight: 700, fontFamily: 'Inter, sans-serif' },
    },

    yAxis: {
      type: 'value',
      axisLine:  { show: false },
      axisTick:  { show: false },
      splitLine: { lineStyle: { color: c.grid, type: 'dashed' } },
      axisLabel: { color: c.muted, fontSize: 10, formatter: v => formatCurrencyFull(v) },
    },

    series: [
      {
        name: 'Regulares',
        type: 'bar',
        stack: 'total',
        barMaxWidth: 56,
        data: regular,
        itemStyle: {
          color: {
            type: 'linear', x: 0, y: 0, x2: 0, y2: 1,
            colorStops: [
              { offset: 0, color: c.greenGrad },
              { offset: 1, color: c.green + '55' },
            ],
          },
        },
        emphasis: { focus: 'series' },
      },
      {
        name: 'Irregulares',
        type: 'bar',
        stack: 'total',
        barMaxWidth: 56,
        data: irregular,
        itemStyle: {
          borderRadius: [6, 6, 0, 0],
          color: {
            type: 'linear', x: 0, y: 0, x2: 0, y2: 1,
            colorStops: [
              { offset: 0, color: c.redGrad },
              { offset: 1, color: c.red + '55' },
            ],
          },
        },
        emphasis: { focus: 'series' },
      },
    ],
  };
});

</script>

<template>
  <div class="tab-content evolucao-tab">
    <div v-if="evolucaoLoading" class="tab-placeholder">
      <i class="pi pi-spin pi-spinner placeholder-icon" />
      <p>Carregando dados...</p>
    </div>

    <div v-else-if="evolucaoLoaded && !evolucaoData?.semestres?.length" class="tab-placeholder">
      <i class="pi pi-inbox placeholder-icon" />
      <p>Nenhum dado de movimentação encontrado para este CNPJ.</p>
    </div>

    <template v-else-if="evolucaoLoaded">
      <div class="evolucao-card">
        <div class="evolucao-card-header">
          <i class="pi pi-chart-bar" /><span>Volume Financeiro por Semestre</span>
        </div>
        <div class="evolucao-chart-wrap">
          <VChart :option="chartOption" :update-options="{ notMerge: true }" autoresize class="evolucao-chart" />
        </div>
      </div>

      <div class="evolucao-card">
        <div class="evolucao-card-header">
          <i class="pi pi-table" /><span>Detalhamento Semestral</span>
        </div>
        <div class="evolucao-table-wrap">
          <table class="evolucao-table">
            <colgroup>
              <col style="width: 10%" />
              <col style="width: 18%" />
              <col style="width: 18%" />
              <col style="width: 18%" />
              <col style="width: 24%" />
              <col style="width: 12%" />
            </colgroup>
            <thead>
              <tr>
                <th>Semestre</th>
                <th>Valor Total Vendas</th>
                <th>Valor Regular</th>
                <th>Valor sem Comprovação</th>
                <th>% Valor sem Comprovação</th>
                <th>Tendência</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="(s, i) in evolucaoData.semestres" :key="s.semestre">
                <td class="sem-label">{{ s.semestre }}</td>
                <td>{{ formatCurrencyFull(s.total) }}</td>
                <td class="col-regular">{{ formatCurrencyFull(s.regular) }}</td>
                <td class="col-irregular">{{ formatCurrencyFull(s.irregular) }}</td>
                <td class="pct-cell">
                  <div class="pct-bar-wrap">
                    <div
                      class="pct-bar"
                      :style="{
                        width: Math.min(s.pct_irregular, 100) + '%',
                        background: s.pct_irregular >= RISK_THRESHOLDS.CRITICAL ? 'var(--risk-critical)'
                                  : s.pct_irregular >= RISK_THRESHOLDS.HIGH     ? 'var(--risk-high)'
                                  : s.pct_irregular >= RISK_THRESHOLDS.MEDIUM   ? 'var(--risk-medium)'
                                  : 'var(--risk-low)'
                      }"
                    />
                  </div>
                  <span class="pct-value" :class="{
                    'pct-critical': s.pct_irregular >= RISK_THRESHOLDS.CRITICAL,
                    'pct-high':     s.pct_irregular >= RISK_THRESHOLDS.HIGH     && s.pct_irregular < RISK_THRESHOLDS.CRITICAL,
                    'pct-medium':   s.pct_irregular >= RISK_THRESHOLDS.MEDIUM   && s.pct_irregular < RISK_THRESHOLDS.HIGH,
                    'pct-low':      s.pct_irregular < RISK_THRESHOLDS.MEDIUM,
                  }">{{ s.pct_irregular.toFixed(1) }}%</span>
                </td>
                <td class="trend-cell">
                  <template v-if="i === 0">
                    <span class="trend-neutral">—</span>
                  </template>
                  <template v-else>
                    <span
                      v-if="s.pct_irregular > evolucaoData.semestres[i-1].pct_irregular"
                      class="trend-up"
                      :title="`+${(s.pct_irregular - evolucaoData.semestres[i-1].pct_irregular).toFixed(1)}pp`"
                    >▲ {{ (s.pct_irregular - evolucaoData.semestres[i-1].pct_irregular).toFixed(1) }}pp</span>
                    <span
                      v-else-if="s.pct_irregular < evolucaoData.semestres[i-1].pct_irregular"
                      class="trend-down"
                      :title="`-${(evolucaoData.semestres[i-1].pct_irregular - s.pct_irregular).toFixed(1)}pp`"
                    >▼ {{ (evolucaoData.semestres[i-1].pct_irregular - s.pct_irregular).toFixed(1) }}pp</span>
                    <span v-else class="trend-neutral">= 0pp</span>
                  </template>
                </td>
              </tr>
            </tbody>
            <tfoot>
              <tr>
                <td><b>TOTAL</b></td>
                <td><b>{{ formatCurrencyFull(evolucaoData.semestres.reduce((a, s) => a + s.total, 0)) }}</b></td>
                <td><b>{{ formatCurrencyFull(evolucaoData.semestres.reduce((a, s) => a + s.regular, 0)) }}</b></td>
                <td class="col-irregular"><b>{{ formatCurrencyFull(evolucaoData.semestres.reduce((a, s) => a + s.irregular, 0)) }}</b></td>
                <td></td>
                <td></td>
              </tr>
            </tfoot>
          </table>
        </div>
      </div>
    </template>
    <div v-else class="tab-placeholder">
      <i class="pi pi-chart-bar placeholder-icon" />
      <p>Clique na aba para carregar os dados.</p>
    </div>
  </div>
</template>

<style scoped>
/* COPIAR CSS DO PAI */
.evolucao-tab {
  display: flex;
  flex-direction: column;
  gap: 1.5rem;
}

.evolucao-card {
  background: transparent;
  border: none;
  border-radius: 0;
  overflow: visible;
  box-shadow: none;
  margin-bottom: 0;
}

.evolucao-card-header {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  padding: 0.5rem 0 0.5rem 0;
  border-bottom: 1px solid var(--sidebar-border);
  margin-bottom: 0.5rem;
  font-size: 0.85rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: var(--text-color);
}

.evolucao-card-header i { font-size: 1rem; color: var(--primary-color); }
.evolucao-chart-wrap { height: 350px; padding: 0.5rem 0 0 0; }
.evolucao-chart { width: 100%; height: 100%; }

.evolucao-table-wrap { overflow-x: auto; }
.evolucao-table { width: 100%; border-collapse: collapse; font-size: 0.82rem; }
.evolucao-table th { text-align: right; padding: 0.5rem 1rem; background: var(--card-bg); color: var(--text-secondary); font-weight: 600; font-size: 0.7rem; text-transform: uppercase; letter-spacing: 0.04em; border-bottom: 2px solid var(--sidebar-border); }
.evolucao-table th:first-child, .evolucao-table td:first-child { text-align: left; }
.evolucao-table td { text-align: right; padding: 0.5rem 1rem; color: var(--text-secondary); border-bottom: 1px solid var(--sidebar-border); }
.evolucao-table tbody tr:hover td { background: var(--sidebar-border); }
.evolucao-table tfoot td { border-top: 2px solid var(--sidebar-border); border-bottom: none; background: color-mix(in srgb, var(--card-bg) 80%, var(--sidebar-border)); }

.sem-label { font-weight: 600; color: var(--text-secondary); }
.col-regular { color: var(--risk-low); }
.col-irregular { color: var(--risk-high); }

.pct-cell { text-align: right; padding: 0.4rem 1rem; }
.pct-bar-wrap { height: 4px; background: var(--sidebar-border); border-radius: 99px; margin-bottom: 3px; overflow: hidden; }
.pct-bar { height: 100%; border-radius: 99px; transition: width 0.4s ease; }
.pct-value { font-weight: 600; font-size: 0.82rem; }

.pct-critical { color: var(--risk-critical); }
.pct-high     { color: var(--risk-high); }
.pct-medium   { color: var(--risk-medium); }
.pct-low      { color: var(--risk-low); }

.trend-cell { text-align: center; font-size: 0.75rem; font-weight: 700; white-space: nowrap; }
.trend-up      { color: var(--risk-high); }
.trend-down    { color: var(--risk-low); }
.trend-neutral { color: var(--text-muted); font-weight: 400; }

.tab-placeholder {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 4rem 2rem;
  gap: 1rem;
  color: var(--text-muted);
  text-align: center;
}
.placeholder-icon {
  font-size: 2.5rem;
  color: var(--sidebar-border);
  opacity: 0.7;
}
</style>
