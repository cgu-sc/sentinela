<script setup>
import { useRoute, useRouter } from 'vue-router';
import { computed } from 'vue';
import { useAnalyticsStore } from '@/stores/analytics';
import { useGeoStore } from '@/stores/geo';
import { useFilterStore } from '@/stores/filters';
import { useRiskMetrics } from '@/composables/useRiskMetrics';
import { useFormatting } from '@/composables/useFormatting';
import { useEvolucaoFinanceira } from '@/composables/useEvolucaoFinanceira';
import { useIndicadores } from '@/composables/useIndicadores';
import { useFalecidos } from '@/composables/useFalecidos';
import { useChartTheme } from '@/config/chartTheme';
import { RISK_COLORS, RISK_THRESHOLDS, INDICATOR_GROUPS, INDICATOR_THRESHOLDS } from '@/config/riskConfig';
import { storeToRefs } from 'pinia';
import VChart from 'vue-echarts';
import { use } from 'echarts/core';
import { BarChart, LineChart } from 'echarts/charts';
import { GridComponent, TooltipComponent, LegendComponent } from 'echarts/components';
import { CanvasRenderer } from 'echarts/renderers';
import TabView from 'primevue/tabview';
import TabPanel from 'primevue/tabpanel';
import Button from 'primevue/button';
import Tag from 'primevue/tag';

use([BarChart, LineChart, GridComponent, TooltipComponent, LegendComponent, CanvasRenderer]);

// ── Índices das abas (evita números mágicos no template) ──
const TAB_INDEX = { MOVIMENTACAO: 0, EVOLUCAO: 1, INDICADORES: 2, CRMS: 3, FALECIDOS: 4, REGIAO: 5 };

const route  = useRoute();
const router = useRouter();
const cnpj   = computed(() => route.params.cnpj);

// ── Stores ────────────────────────────────────────────────
const analyticsStore = useAnalyticsStore();
const { resultadoCnpjs } = storeToRefs(analyticsStore);

const geoStore = useGeoStore();
const { localidades } = storeToRefs(geoStore);

const filtersStore = useFilterStore();

// ── Navegação com filtro ──────────────────────────────────
function navigateWithFilter(type) {
  const geo = geoData.value;
  if (!geo) return;

  // Seta todos os valores explicitamente — não depende de watchers assíncronos do store
  if (type === 'municipio') {
    filtersStore.selectedUF          = geo.sg_uf;
    filtersStore.selectedRegiaoSaude = geo.no_regiao_saude;
    filtersStore.selectedMunicipio   = `${geo.no_municipio}|${geo.sg_uf}`;
  } else if (type === 'uf') {
    filtersStore.selectedMunicipio   = 'Todos';
    filtersStore.selectedRegiaoSaude = 'Todos';
    filtersStore.selectedUF          = geo.sg_uf;
  } else if (type === 'regiao') {
    filtersStore.selectedMunicipio   = 'Todos';
    filtersStore.selectedUF          = geo.sg_uf;
    filtersStore.selectedRegiaoSaude = geo.no_regiao_saude;
  }

  router.push({ name: 'Dashboard' });
}

// ── Composables ───────────────────────────────────────────
const { getRiskSeverity, getRiskLabel, getRiskColor } = useRiskMetrics();
const { formatCurrencyFull, formatNumberFull } = useFormatting();
const { chartTheme, chartDataColors, baseChartConfig } = useChartTheme();
const { evolucaoData, evolucaoLoading, evolucaoLoaded, fetchEvolucao } = useEvolucaoFinanceira();
const { indicadoresData, indicadoresLoading, indicadoresLoaded, fetchIndicadores } = useIndicadores();
const { falecidosData, falecidosLoading, falecidosLoaded, fetchFalecidos } = useFalecidos();

// ── Helpers de indicadores ────────────────────────────────
function getIndicadorStatus(riscoUf, thresholdKey = 'default') {
  const t = INDICATOR_THRESHOLDS[thresholdKey] ?? INDICATOR_THRESHOLDS.default;
  const r = riscoUf != null ? Math.round(riscoUf * 10) / 10 : null;
  if (r == null) return { label: 'SEM DADOS', color: 'var(--text-muted)', severity: 'secondary' };
  if (r >= t.critico) return { label: 'CRÍTICO',  color: RISK_COLORS.CRITICAL, severity: 'danger'  };
  if (r >= t.atencao) return { label: 'ATENÇÃO',  color: RISK_COLORS.MEDIUM,   severity: 'warning' };
  return                      { label: 'NORMAL',   color: RISK_COLORS.LOW,      severity: 'success' };
}

function formatIndicadorValue(valor, formato) {
  if (valor == null) return '—';
  if (formato === 'pct')  return valor.toFixed(2) + '%';
  if (formato === 'pct3') return valor.toFixed(3) + '%';
  if (formato === 'val')  return formatCurrencyFull(valor);
  return valor.toFixed(2);
}

// ── Pontos críticos (resumo de auditoria) ────────────────
const pontosCriticos = computed(() => {
  if (!indicadoresData.value?.indicadores) return [];
  const result = [];
  for (const grupo of INDICATOR_GROUPS) {
    for (const ind of grupo.indicators) {
      const d = indicadoresData.value.indicadores[ind.key];
      if (!d || d.valor == null) continue;
      const t = INDICATOR_THRESHOLDS[ind.thresholdKey] ?? INDICATOR_THRESHOLDS.default;
      const riscoUf  = d.risco_uf  != null ? Math.round(d.risco_uf  * 10) / 10 : null;
      const riscoReg = d.risco_reg != null ? Math.round(d.risco_reg * 10) / 10 : null;
      if (riscoUf != null && riscoUf >= t.critico) {
        result.push({
          key:     ind.key,
          label:   ind.label,
          formato: ind.formato,
          riscoUf,
          riscoReg,
          valor:   d.valor,
          medReg:  d.med_reg,
        });
      }
    }
  }
  return result.sort((a, b) => {
    if (a.key === 'auditado') return -1;
    if (b.key === 'auditado') return 1;
    return (b.riscoReg ?? 0) - (a.riscoReg ?? 0);
  });
});

function riscoPillStyle(risco, thresholdKey = 'default') {
  const s = getIndicadorStatus(risco, thresholdKey);
  // CRITICAL usa a cor HIGH (vermelho vivo) para garantir leitura no dark mode
  const c = s.color === RISK_COLORS.CRITICAL ? RISK_COLORS.HIGH : s.color;
  return { background: c + '28', color: c };
}

// ── Dados do CNPJ ─────────────────────────────────────────
const cnpjData = computed(() =>
  resultadoCnpjs.value?.find(c => c.cnpj === cnpj.value) ?? null
);

const geoData = computed(() => {
  const ibge7 = cnpjData.value?.id_ibge7;
  if (!ibge7 || !localidades.value?.length) return null;
  return localidades.value.find(l => l.id_ibge7 === ibge7) ?? null;
});

const risco = computed(() => cnpjData.value?.percValSemComp ?? 0);

const formatPopulacao = (value) =>
  value == null ? '—' : formatNumberFull(value) + ' hab.';

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
    ...baseChartConfig.value,

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
      axisPointer: { type: 'shadow', shadowStyle: { color: 'rgba(255,255,255,0.04)' } },
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

// ── Opção: área não comprovados ───────────────────────────
const areaOption = computed(() => {
  const c         = C.value;
  const semestres = evolucaoData.value?.semestres ?? [];
  const labels    = semestres.map(s => s.semestre);
  const irregular = semestres.map(s => s.irregular);
  const pct       = semestres.map(s => s.pct_irregular);

  return {
    ...baseChartConfig.value,

    grid: { top: 24, left: 80, right: 24, bottom: 32, containLabel: false },

    tooltip: {
      trigger: 'axis',
      axisPointer: { type: 'shadow', shadowStyle: { color: 'rgba(255,255,255,0.04)' } },
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
          <div style="font-weight:700;font-size:14px;margin-bottom:8px;">${s.semestre}</div>
          <div style="display:flex;align-items:center;gap:8px;margin-bottom:4px;">
            <span style="width:10px;height:10px;border-radius:2px;background:${c.red};display:inline-block;"></span>
            <span style="font-size:10px;opacity:.6;letter-spacing:.04em;text-transform:uppercase;">Não Comprovado</span>
          </div>
          <div style="font-weight:700;font-size:14px;color:${c.red};">${formatCurrencyFull(s.irregular)}</div>
          <div style="margin-top:6px;font-size:11px;opacity:.7;">% do total: ${pct[idx].toFixed(1)}%</div>`;
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
        name: 'Não Comprovado',
        type: 'line',
        smooth: true,
        symbol: 'circle',
        symbolSize: 6,
        data: irregular,
        lineStyle: { color: c.red, width: 2.5 },
        itemStyle: { color: c.red, borderWidth: 2, borderColor: c.red },
        areaStyle: {
          color: {
            type: 'linear', x: 0, y: 0, x2: 0, y2: 1,
            colorStops: [
              { offset: 0, color: c.redGrad + 'bb' },
              { offset: 1, color: c.red + '08' },
            ],
          },
        },
      },
    ],
  };
});
</script>

<template>
  <div class="cnpj-detail-page">

    <!-- HEADER -->
    <div class="detail-header">
      <Button
        icon="pi pi-arrow-left"
        text
        severity="secondary"
        class="back-btn"
        @click="router.back()"
        v-tooltip.right="'Voltar'"
      />

      <div class="header-identity" v-if="cnpjData">
        <div class="header-top">
          <span class="cnpj-badge">{{ cnpj }}</span>
          <Tag
            :value="getRiskLabel(risco)"
            :severity="getRiskSeverity(risco)"
            class="risk-tag"
          />
        </div>
        <h1 class="razao-social">{{ cnpjData.razao_social ?? '—' }}</h1>
        <p class="localidade">
          <i class="pi pi-map-marker" />
          <span
            class="localidade-link"
            @click="navigateWithFilter('municipio')"
            v-tooltip.bottom="'Filtrar por este município'"
          >{{ geoData?.no_municipio ?? cnpjData.municipio }}</span>
          ·
          <span
            class="localidade-link"
            @click="navigateWithFilter('uf')"
            v-tooltip.bottom="'Filtrar por esta UF'"
          >{{ geoData?.sg_uf ?? cnpjData.uf }}</span>
          <span v-if="geoData?.no_regiao_saude" class="localidade-sep">|</span>
          <span
            v-if="geoData?.no_regiao_saude"
            class="localidade-link"
            @click="navigateWithFilter('regiao')"
            v-tooltip.bottom="'Filtrar por esta Região de Saúde'"
          >Região de Saúde: {{ geoData.no_regiao_saude }}</span>
          <span v-if="geoData?.nu_populacao" class="localidade-sep">|</span>
          <i v-if="geoData?.nu_populacao" class="pi pi-users" />
          <span v-if="geoData?.nu_populacao">{{ formatPopulacao(geoData.nu_populacao) }}</span>
        </p>
      </div>

      <div class="header-identity" v-else>
        <span class="cnpj-badge">{{ cnpj }}</span>
        <h1 class="razao-social">Carregando...</h1>
      </div>

      <div class="header-kpis" v-if="cnpjData">
        <div class="mini-kpi">
          <span class="mini-kpi-label">% Sem Comp.</span>
          <span class="mini-kpi-value" :style="{ color: getRiskColor(risco) }">{{ cnpjData.percValSemComp?.toFixed(2) }}%</span>
        </div>
        <div class="mini-kpi">
          <span class="mini-kpi-label">Valor Sem Comp.</span>
          <span class="mini-kpi-value">{{ formatCurrencyFull(cnpjData.valSemComp) }}</span>
        </div>
        <div class="mini-kpi">
          <span class="mini-kpi-label">Total Movimentado</span>
          <span class="mini-kpi-value">{{ formatCurrencyFull(cnpjData.totalMov) }}</span>
        </div>
      </div>
    </div>

    <!-- TABS -->
    <TabView
      class="detail-tabs"
      @tab-change="(e) => {
        if (e.index === TAB_INDEX.EVOLUCAO)    fetchEvolucao(cnpj);
        if (e.index === TAB_INDEX.INDICADORES) fetchIndicadores(cnpj);
        if (e.index === TAB_INDEX.FALECIDOS)   fetchFalecidos(cnpj);
      }"
    >

      <TabPanel>
        <template #header><i class="pi pi-list tab-icon" /><span>Movimentação</span></template>
        <div class="tab-content tab-placeholder">
          <i class="pi pi-inbox placeholder-icon" />
          <p>Dados de movimentação serão exibidos aqui.</p>
        </div>
      </TabPanel>

      <TabPanel>
        <template #header><i class="pi pi-chart-line tab-icon" /><span>Evolução Financeira</span></template>
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
                <VChart :option="chartOption" autoresize class="evolucao-chart" />
              </div>
            </div>

            <div class="evolucao-card">
              <div class="evolucao-card-header">
                <i class="pi pi-chart-line" /><span>Evolução dos Valores Não Comprovados</span>
              </div>
              <div class="evolucao-chart-wrap">
                <VChart :option="areaOption" autoresize class="evolucao-chart" />
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
                      <th>Total</th>
                      <th>Regulares</th>
                      <th>Irregulares</th>
                      <th>% Irregular</th>
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
                              background: s.pct_irregular >= RISK_THRESHOLDS.CRITICAL ? RISK_COLORS.CRITICAL
                                        : s.pct_irregular >= RISK_THRESHOLDS.HIGH     ? RISK_COLORS.HIGH
                                        : s.pct_irregular >= RISK_THRESHOLDS.MEDIUM   ? RISK_COLORS.MEDIUM
                                        : RISK_COLORS.LOW
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
      </TabPanel>

      <TabPanel>
        <template #header><i class="pi pi-shield tab-icon" /><span>Indicadores</span></template>
        <div class="tab-content indicadores-tab">

          <div v-if="indicadoresLoading" class="tab-placeholder">
            <i class="pi pi-spin pi-spinner placeholder-icon" />
            <p>Carregando indicadores...</p>
          </div>

          <div v-else-if="indicadoresLoaded && !Object.keys(indicadoresData?.indicadores ?? {}).length" class="tab-placeholder">
            <i class="pi pi-inbox placeholder-icon" />
            <p>Nenhum indicador encontrado para este CNPJ.</p>
          </div>

          <template v-else-if="indicadoresLoaded">

            <!-- RESUMO DE AUDITORIA -->
            <div v-if="pontosCriticos.length" class="audit-summary">
              <div class="audit-summary-header">
                <i class="pi pi-file-edit" />
                <span>Resumo para Auditoria — Pontos Críticos</span>
                <span class="audit-badge">{{ pontosCriticos.length }}</span>
              </div>
              <ul class="audit-list">
                <li v-for="p in pontosCriticos" :key="p.label" class="audit-item">
                  <i class="pi pi-exclamation-circle audit-item-icon" />
                  <span>
                    <strong>{{ p.label }}</strong>: operação
                    <span class="audit-risco">{{ p.riscoReg?.toFixed(1) ?? p.riscoUf.toFixed(1) }}x</span>
                    acima da mediana regional
                    <span class="audit-detail">(Farmácia: {{ formatIndicadorValue(p.valor, p.formato) }} | Mediana Região: {{ formatIndicadorValue(p.medReg, p.formato) }})</span>
                  </span>
                </li>
              </ul>
            </div>

            <div class="ind-table-wrap">
              <table class="ind-table">
                <colgroup>
                  <col style="width:28%" />
                  <col style="width:9%" />
                  <col style="width:9%" />
                  <col style="width:9%" />
                  <col style="width:9%" />
                  <col style="width:9%" />
                  <col style="width:9%" />
                  <col style="width:9%" />
                  <col style="width:9%" />
                </colgroup>
                <thead class="ind-thead">
                  <tr>
                    <th>Indicador</th>
                    <th>Farmácia</th>
                    <th>Mediana Região</th>
                    <th>Mediana UF</th>
                    <th>Mediana BR</th>
                    <th>Risco Região</th>
                    <th>Risco UF</th>
                    <th>Risco BR</th>
                    <th>Status</th>
                  </tr>
                </thead>
                <tbody>
                  <template v-for="grupo in INDICATOR_GROUPS" :key="grupo.id">
                    <tr class="ind-group-row">
                      <td colspan="9">{{ grupo.label }}</td>
                    </tr>
                    <tr
                      v-for="ind in grupo.indicators"
                      :key="ind.key"
                      class="ind-data-row"
                    >
                      <td class="ind-nome-cell">
                        <div class="ind-nome-inner">
                          <span>{{ ind.label }}</span>
                          <i
                            class="pi pi-info-circle ind-info-icon"
                            v-tooltip.right="{ value: ind.metodologia, class: 'ind-tooltip' }"
                          />
                        </div>
                      </td>

                      <template v-if="indicadoresData.indicadores[ind.key]?.valor != null">
                        <td class="ind-val-cell">{{ formatIndicadorValue(indicadoresData.indicadores[ind.key].valor, ind.formato) }}</td>
                        <td class="ind-med-cell">{{ formatIndicadorValue(indicadoresData.indicadores[ind.key].med_reg, ind.formato) }}</td>
                        <td class="ind-med-cell">{{ formatIndicadorValue(indicadoresData.indicadores[ind.key].med_uf,  ind.formato) }}</td>
                        <td class="ind-med-cell">{{ formatIndicadorValue(indicadoresData.indicadores[ind.key].med_br,  ind.formato) }}</td>
                        <td class="ind-risco-cell">
                          <span
                            class="ind-risco-pill"
                            :style="riscoPillStyle(indicadoresData.indicadores[ind.key].risco_reg, ind.thresholdKey)"
                          >{{ indicadoresData.indicadores[ind.key].risco_reg != null ? indicadoresData.indicadores[ind.key].risco_reg.toFixed(1) + 'x' : '—' }}</span>
                        </td>
                        <td class="ind-risco-cell">
                          <span
                            class="ind-risco-pill"
                            :style="riscoPillStyle(indicadoresData.indicadores[ind.key].risco_uf, ind.thresholdKey)"
                          >{{ indicadoresData.indicadores[ind.key].risco_uf != null ? indicadoresData.indicadores[ind.key].risco_uf.toFixed(1) + 'x' : '—' }}</span>
                        </td>
                        <td class="ind-risco-cell">
                          <span
                            class="ind-risco-pill"
                            :style="riscoPillStyle(indicadoresData.indicadores[ind.key].risco_br, ind.thresholdKey)"
                          >{{ indicadoresData.indicadores[ind.key].risco_br != null ? indicadoresData.indicadores[ind.key].risco_br.toFixed(1) + 'x' : '—' }}</span>
                        </td>
                        <td class="ind-status-cell">
                          <span
                            class="ind-status-pill"
                            :style="riscoPillStyle(indicadoresData.indicadores[ind.key].risco_uf, ind.thresholdKey)"
                          >{{ getIndicadorStatus(indicadoresData.indicadores[ind.key].risco_uf, ind.thresholdKey).label }}</span>
                        </td>
                      </template>
                      <template v-else>
                        <td colspan="8" class="ind-sem-dados">SEM DADOS</td>
                      </template>
                    </tr>
                  </template>
                </tbody>
              </table>
            </div>
          </template>

          <div v-else class="tab-placeholder">
            <i class="pi pi-shield placeholder-icon" />
            <p>Clique na aba para carregar os indicadores.</p>
          </div>

        </div>
      </TabPanel>

      <TabPanel>
        <template #header><i class="pi pi-id-card tab-icon" /><span>Análise de CRMs</span></template>
        <div class="tab-content tab-placeholder">
          <i class="pi pi-users placeholder-icon" />
          <p>Perfil de prescritores e alertas de anomalias serão exibidos aqui.</p>
        </div>
      </TabPanel>

      <TabPanel>
        <template #header><i class="pi pi-exclamation-triangle tab-icon" /><span>Falecidos</span></template>
        <div class="tab-content falecidos-tab">

          <div v-if="falecidosLoading" class="tab-placeholder">
            <i class="pi pi-spin pi-spinner placeholder-icon" />
            <p>Analisando base de óbitos...</p>
          </div>

          <div v-else-if="falecidosLoaded && !falecidosData?.transacoes?.length" class="tab-placeholder">
            <i class="pi pi-check-circle placeholder-icon" style="color: var(--green-500)" />
            <p>Nenhuma venda para falecidos encontrada neste estabelecimento.</p>
          </div>

          <template v-else-if="falecidosLoaded">
            <!-- 7 CARDS DE KPI -->
            <div class="falecidos-kpi-grid">
              <div class="f-kpi-card">
                <span class="f-kpi-label">CPFs Distintos</span>
                <span class="f-kpi-val">{{ falecidosData.summary.cpfs_distintos }}</span>
              </div>
              <div class="f-kpi-card">
                <span class="f-kpi-label">Vendas Afetadas</span>
                <span class="f-kpi-val">{{ falecidosData.summary.total_autorizacoes }}</span>
              </div>
              <div class="f-kpi-card highlight-red">
                <span class="f-kpi-label">Prejuízo Estimado</span>
                <span class="f-kpi-val">{{ formatCurrencyFull(falecidosData.summary.valor_total) }}</span>
              </div>
              <div class="f-kpi-card">
                <span class="f-kpi-label">Média Dias Pós-Óbito</span>
                <span class="f-kpi-val">{{ falecidosData.summary.media_dias.toFixed(1) }} <small>dias</small></span>
              </div>
              <div class="f-kpi-card">
                <span class="f-kpi-label">Máximo Dias Pós-Óbito</span>
                <span class="f-kpi-val">{{ falecidosData.summary.max_dias }} <small>dias</small></span>
              </div>
              <div class="f-kpi-card">
                <span class="f-kpi-label">% do Faturamento</span>
                <span class="f-kpi-val">{{ (falecidosData.summary.pct_faturamento * 100).toFixed(3) }}%</span>
              </div>
              <div class="f-kpi-card warning">
                <span class="f-kpi-label">CPFs Multi-CNPJ</span>
                <span class="f-kpi-val">{{ falecidosData.summary.cpfs_multi_cnpj }} <small>({{ (falecidosData.summary.pct_multi_cnpj * 100).toFixed(1) }}%)</small></span>
              </div>
            </div>

            <div class="falecidos-main-layout">
              <!-- TABELA DE TRANSAÇÕES -->
              <div class="falecidos-list-container">
                <div class="section-title">
                  <i class="pi pi-list" />
                  <span>Detalhamento de Transações (Agrupado por CPF)</span>
                </div>
                
                <div class="f-table-wrap">
                  <table class="f-table">
                    <thead>
                      <tr>
                        <th>Beneficiário / CPF</th>
                        <th>Dt. Óbito</th>
                        <th>Autorização</th>
                        <th>Dt. Venda</th>
                        <th>Itens</th>
                        <th>Valor</th>
                        <th class="txt-center">Dias após Óbito</th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr v-for="t in falecidosData.transacoes" :key="t.num_autorizacao" class="f-row">
                        <td>
                          <div class="f-beneficiario">
                            <span class="f-nome">{{ t.nome_falecido || 'NÃO IDENTIFICADO' }}</span>
                            <span class="f-cpf">{{ t.cpf }}</span>
                            <Tag v-if="t.outros_estabelecimentos" icon="pi pi-share-alt" value="MULTI-CNPJ" severity="warning" class="f-multi-tag" v-tooltip.top="t.outros_estabelecimentos" />
                          </div>
                        </td>
                        <td class="f-date">{{ t.dt_obito }}</td>
                        <td class="f-aut">{{ t.num_autorizacao }}</td>
                        <td class="f-date">{{ t.data_autorizacao }}</td>
                        <td class="f-num">{{ t.qtd_itens_na_autorizacao }}</td>
                        <td class="f-val">{{ formatCurrencyFull(t.valor_total_autorizacao) }}</td>
                        <td class="txt-center">
                          <span class="f-days-badge" :class="{
                            'd-critical': t.dias_apos_obito > 365,
                            'd-high': t.dias_apos_obito > 30 && t.dias_apos_obito <= 365,
                            'd-medium': t.dias_apos_obito <= 30
                          }">
                            {{ t.dias_apos_obito }} d
                          </span>
                        </td>
                      </tr>
                    </tbody>
                  </table>
                </div>
              </div>

              <!-- PAINEL MULTI-CNPJ -->
              <div class="falecidos-ranking-panel" v-if="falecidosData.ranking?.length">
                <div class="section-title">
                  <i class="pi pi-share-alt" />
                  <span>Cross-Pharmacy: Outros Estabelecimentos Relacionados</span>
                </div>
                <div class="ranking-list">
                  <div v-for="r in falecidosData.ranking" :key="r.estabelecimento" class="ranking-item">
                    <div class="ranking-item-top">
                      <span class="ranking-name" :title="r.estabelecimento">{{ r.estabelecimento }}</span>
                      <span class="ranking-qty">{{ r.qtd_cpfs }} CPFs</span>
                    </div>
                    <div class="ranking-bar-bg">
                      <div class="ranking-bar-fill" :style="{ width: (r.pct_total * 100) + '%' }"></div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </template>

          <div v-else class="tab-placeholder">
            <i class="pi pi-exclamation-triangle placeholder-icon" />
            <p>Clique na aba para processar a análise de óbitos.</p>
          </div>

        </div>
      </TabPanel>

      <TabPanel>
        <template #header><i class="pi pi-map tab-icon" /><span>Região de Saúde</span></template>
        <div class="tab-content tab-placeholder">
          <i class="pi pi-globe placeholder-icon" />
          <p>Ranking comparativo das farmácias da mesma região será exibido aqui.</p>
        </div>
      </TabPanel>

    </TabView>
  </div>
</template>

<style scoped>
.cnpj-detail-page {
  display: flex;
  flex-direction: column;
  height: 100%;
  overflow: hidden;
}

/* ── HEADER ─────────────────────────────────────────── */
.detail-header {
  display: flex;
  align-items: center;
  gap: 1.5rem;
  padding: 1rem 1.5rem;
  border-bottom: 1px solid var(--sidebar-border);
  background: var(--card-bg);
  flex-shrink: 0;
}

.back-btn { flex-shrink: 0; }

.header-identity {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 0.2rem;
}

.header-top {
  display: flex;
  align-items: center;
  gap: 0.6rem;
}

.cnpj-badge {
  font-family: monospace;
  font-size: 0.8rem;
  color: var(--text-muted);
  background: var(--sidebar-border);
  padding: 0.15rem 0.5rem;
  border-radius: 4px;
  letter-spacing: 0.05em;
}

.risk-tag { font-size: 0.7rem; }

.razao-social {
  font-size: 1.1rem;
  font-weight: 600;
  color: var(--text-primary);
  margin: 0;
  line-height: 1.2;
}

.localidade {
  font-size: 0.78rem;
  color: var(--text-muted);
  margin: 0;
  display: flex;
  align-items: center;
  gap: 0.3rem;
  flex-wrap: wrap;
}

.localidade-sep {
  opacity: 0.4;
  margin: 0 0.1rem;
}

.localidade-link {
  cursor: pointer;
  border-bottom: 1px dashed currentColor;
  opacity: 0.8;
  transition: opacity 0.15s, color 0.15s;
}

.localidade-link:hover {
  opacity: 1;
  color: var(--primary-color);
}

.header-kpis {
  display: flex;
  gap: 1.5rem;
  flex-shrink: 0;
}

.mini-kpi {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 0.1rem;
}

.mini-kpi-label {
  font-size: 0.65rem;
  color: var(--text-muted);
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

.mini-kpi-value {
  font-size: 1rem;
  font-weight: 600;
  color: var(--text-primary);
}

/* ── TABS ────────────────────────────────────────────── */
.detail-tabs {
  flex: 1;
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

:deep(.p-tabview) {
  display: flex;
  flex-direction: column;
  height: 100%;
}

:deep(.p-tabview-panels) {
  flex: 1;
  overflow-y: auto;
  padding: 0;
  background: transparent !important;
}

:deep(.p-tabview-panel) {
  background: transparent !important;
}

:deep(.p-tabview-nav) {
  background: var(--card-bg) !important;
  border-bottom: 1px solid var(--sidebar-border);
  padding: 0 1rem;
}

:deep(.p-tabview-nav-content) {
  background: var(--card-bg) !important;
}

:deep(.p-tabview-nav li .p-tabview-nav-link) {
  font-size: 0.8rem;
  padding: 0.75rem 1rem;
  gap: 0.4rem;
}

.tab-icon { font-size: 0.8rem; }

/* ── PLACEHOLDER ─────────────────────────────────────── */
.tab-content { padding: 2rem; }

.tab-placeholder {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 1rem;
  min-height: 300px;
  color: var(--text-muted);
  opacity: 0.5;
}

.placeholder-icon { font-size: 3rem; }
.tab-placeholder p { font-size: 0.875rem; }

/* ── EVOLUÇÃO FINANCEIRA ─────────────────────────────── */
.evolucao-tab {
  display: flex;
  flex-direction: column;
  gap: 1rem;
  padding: 1rem 0 0 0;
}

.evolucao-card {
  background: var(--card-bg);
  border-left: none;
  border-right: none;
  border-top: 1px solid var(--sidebar-border);
  border-bottom: 1px solid var(--sidebar-border);
  overflow: hidden;
  box-shadow: 0 1px 4px rgba(0, 0, 0, 0.06);
}

.evolucao-card-header {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.75rem 1rem;
  border-bottom: 1px solid var(--sidebar-border);
  font-size: 0.78rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--text-muted);
}

.evolucao-chart-wrap {
  height: 25vh;
  min-height: 260px;
  padding: 0.5rem;
}

.evolucao-chart {
  width: 100%;
  height: 100%;
}

/* ── Tabela ──────────────────────────────────────────── */
.evolucao-table-wrap { overflow-x: auto; }

.evolucao-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 0.82rem;
}

.evolucao-table th {
  text-align: right;
  padding: 0.5rem 1rem;
  background: var(--card-bg);
  color: var(--text-muted);
  font-weight: 600;
  font-size: 0.7rem;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  border-bottom: 2px solid var(--sidebar-border);
}

.evolucao-table th:first-child,
.evolucao-table td:first-child { text-align: left; }

.evolucao-table td {
  text-align: right;
  padding: 0.5rem 1rem;
  color: var(--text-primary);
  border-bottom: 1px solid var(--sidebar-border);
}

.evolucao-table tbody tr:hover td { background: var(--sidebar-border); }

.evolucao-table tfoot td {
  border-top: 2px solid var(--sidebar-border);
  border-bottom: none;
  background: color-mix(in srgb, var(--card-bg) 80%, var(--sidebar-border));
}

.sem-label   { font-weight: 600; color: var(--text-muted); }
.col-regular { color: v-bind('RISK_COLORS.LOW'); }
.col-irregular { color: v-bind('RISK_COLORS.HIGH'); }

/* ── Barra de progresso % ────────────────────────────── */
.pct-cell {
  text-align: right;
  padding: 0.4rem 1rem;
}

.pct-bar-wrap {
  height: 4px;
  background: var(--sidebar-border);
  border-radius: 99px;
  margin-bottom: 3px;
  overflow: hidden;
}

.pct-bar {
  height: 100%;
  border-radius: 99px;
  transition: width 0.4s ease;
}

.pct-value    { font-weight: 600; font-size: 0.82rem; }
.pct-critical { color: v-bind('RISK_COLORS.CRITICAL'); }
.pct-high     { color: v-bind('RISK_COLORS.HIGH'); }
.pct-medium   { color: v-bind('RISK_COLORS.MEDIUM'); }
.pct-low      { color: v-bind('RISK_COLORS.LOW'); }

/* ── Tendência ───────────────────────────────────────── */
.trend-cell {
  text-align: center;
  font-size: 0.75rem;
  font-weight: 700;
  white-space: nowrap;
}

.trend-up      { color: v-bind('RISK_COLORS.HIGH'); }
.trend-down    { color: v-bind('RISK_COLORS.LOW'); }
.trend-neutral { color: var(--text-muted); font-weight: 400; }

/* ── INDICADORES ─────────────────────────────────────── */
.indicadores-tab {
  padding: 1rem 0 0;
  display: flex;
  flex-direction: column;
  gap: 1rem;
}

/* Resumo de auditoria */
.audit-summary {
  border: 1px solid color-mix(in srgb, v-bind('RISK_COLORS.HIGH') 30%, transparent);
  border-radius: 10px;
  background: color-mix(in srgb, v-bind('RISK_COLORS.HIGH') 6%, var(--card-bg));
  overflow: hidden;
}

.audit-summary-header {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.6rem 1.25rem;
  border-bottom: 1px solid color-mix(in srgb, v-bind('RISK_COLORS.HIGH') 20%, transparent);
  font-size: 0.72rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.07em;
  color: v-bind('RISK_COLORS.HIGH');
}

.audit-badge {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 1.25rem;
  height: 1.25rem;
  padding: 0 0.3rem;
  border-radius: 99px;
  background: v-bind('RISK_COLORS.HIGH');
  color: #fff;
  font-size: 0.65rem;
  font-weight: 700;
  letter-spacing: 0;
}

.audit-list {
  list-style: none;
  margin: 0;
  padding: 0.5rem 1.25rem 0.75rem;
  display: flex;
  flex-direction: column;
  gap: 0.4rem;
  text-transform: none;
}

.audit-item {
  display: flex;
  align-items: baseline;
  gap: 0.5rem;
  font-size: 0.8rem;
  color: var(--text-primary);
  line-height: 1.4;
}

.audit-item-icon {
  font-size: 0.7rem;
  color: v-bind('RISK_COLORS.HIGH');
  flex-shrink: 0;
  margin-top: 0.05rem;
}

.audit-risco {
  font-weight: 700;
  color: v-bind('RISK_COLORS.HIGH');
}

.audit-detail {
  font-size: 0.75rem;
  color: var(--text-muted);
  margin-left: 0.25rem;
}

.ind-table-wrap {
  overflow: hidden;
  border-top: 1px solid var(--sidebar-border);
  border-bottom: 1px solid var(--sidebar-border);
  border-radius: 10px;
}

.ind-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 0.8rem;
}

/* Cabeçalho fixo */
.ind-thead th {
  position: sticky;
  top: 0;
  z-index: 2;
  text-align: center;
  padding: 0.6rem 0.75rem;
  background: color-mix(in srgb, var(--primary-color, #3b82f6) 14%, var(--card-bg));
  color: var(--text-primary);
  font-size: 0.66rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.07em;
  border-bottom: 2px solid var(--primary-color, #3b82f6);
  white-space: nowrap;
}

.ind-thead th:first-child { text-align: left; }

/* Linha de grupo */
.ind-group-row td {
  padding: 0.4rem 1rem;
  font-size: 0.66rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.07em;
  color: var(--text-muted);
  background: color-mix(in srgb, var(--sidebar-border) 60%, var(--card-bg));
  border-top: 1px solid var(--sidebar-border);
  border-left: 3px solid color-mix(in srgb, var(--primary-color, #3b82f6) 50%, transparent);
}

/* Linha de dados */
.ind-data-row td {
  padding: 0.5rem 0.75rem;
  border-bottom: 1px solid var(--sidebar-border);
  vertical-align: middle;
  text-transform: none;
}

.ind-data-row:hover td {
  background: color-mix(in srgb, var(--card-bg) 70%, var(--sidebar-border));
}

/* Célula do nome */
.ind-nome-cell {
  font-weight: 500;
}

.ind-nome-inner {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  white-space: nowrap;
}

/* Células de valor e mediana */
.ind-val-cell {
  text-align: center;
  font-weight: 700;
}

.ind-med-cell {
  text-align: center;
}

/* Células de risco */
.ind-risco-cell {
  text-align: center;
}

.ind-risco-pill {
  display: inline-block;
  padding: 0.15rem 0.55rem;
  border-radius: 99px;
  font-size: 0.72rem;
  font-weight: 700;
  letter-spacing: 0.02em;
  min-width: 3.2rem;
  text-align: center;
}

/* Célula de status */
.ind-status-cell { text-align: center; }

.ind-status-pill {
  display: inline-block;
  padding: 0.2rem 0.6rem;
  border-radius: 99px;
  font-size: 0.65rem;
  font-weight: 700;
  letter-spacing: 0.05em;
  white-space: nowrap;
}

/* Info icon */
.ind-info-icon {
  font-size: 0.7rem;
  opacity: 0.4;
  cursor: pointer;
  flex-shrink: 0;
  transition: opacity 0.15s;
}
.ind-info-icon:hover { opacity: 1; }

/* Sem dados */
.ind-sem-dados {
  text-align: center;
  color: var(--text-muted);
  opacity: 0.5;
  font-size: 0.75rem;
  font-weight: 600;
  padding: 0.5rem;
}

/* ── FALECIDOS ────────────────────────────────────────── */
.falecidos-tab {
  padding: 1rem;
  display: flex;
  flex-direction: column;
  gap: 1.5rem;
}

.falecidos-kpi-grid {
  display: grid;
  grid-template-columns: repeat(7, 1fr);
  gap: 0.75rem;
}

.f-kpi-card {
  background: var(--card-bg);
  border: 1px solid var(--sidebar-border);
  padding: 0.75rem;
  border-radius: 8px;
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
}

.f-kpi-label {
  font-size: 0.62rem;
  font-weight: 700;
  color: var(--text-muted);
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

.f-kpi-val {
  font-size: 1.1rem;
  font-weight: 700;
  color: var(--text-primary);
}

.f-kpi-val small {
  font-size: 0.7rem;
  opacity: 0.6;
}

.highlight-red .f-kpi-val { color: v-bind('RISK_COLORS.CRITICAL'); }
.warning .f-kpi-val { color: v-bind('RISK_COLORS.MEDIUM'); }

.falecidos-main-layout {
  display: grid;
  grid-template-columns: 1fr 320px;
  gap: 1.5rem;
  align-items: start;
}

.section-title {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  font-size: 0.75rem;
  font-weight: 700;
  text-transform: uppercase;
  color: var(--text-muted);
  margin-bottom: 1rem;
  letter-spacing: 0.05em;
}

/* Tabela de Falecidos */
.f-table-wrap {
  background: var(--card-bg);
  border: 1px solid var(--sidebar-border);
  border-radius: 10px;
  overflow: hidden;
}

.f-table {
  width: 100%;
  border-collapse: collapse;
}

.f-table th {
  text-align: left;
  padding: 0.75rem 1rem;
  background: color-mix(in srgb, var(--sidebar-border) 40%, var(--card-bg));
  font-size: 0.68rem;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: var(--text-muted);
  border-bottom: 2px solid var(--sidebar-border);
}

.f-table td {
  padding: 0.75rem 1rem;
  border-bottom: 1px solid var(--sidebar-border);
  font-size: 0.8rem;
  color: var(--text-primary);
}

.f-row:hover td { background: rgba(255,255,255,0.02); }

.f-beneficiario {
  display: flex;
  flex-direction: column;
}

.f-nome { font-weight: 600; font-size: 0.82rem; }
.f-cpf { font-size: 0.72rem; color: var(--text-muted); font-family: monospace; }

.f-multi-tag {
  align-self: flex-start;
  font-size: 0.6rem !important;
  margin-top: 0.3rem;
  height: 1.2rem;
}

.f-date, .f-aut, .f-num, .f-val { font-size: 0.78rem; }
.f-num, .f-val { font-weight: 500; }

.txt-center { text-align: center !important; }

.f-days-badge {
  display: inline-block;
  padding: 0.15rem 0.6rem;
  border-radius: 99px;
  font-size: 0.7rem;
  font-weight: 700;
}

.d-medium { background: rgba(255, 193, 7, 0.15); color: #ffc107; }
.d-high { background: rgba(255, 87, 34, 0.15); color: #ff5722; }
.d-critical { background: rgba(244, 67, 54, 0.15); color: #f44336; }

/* Ranking Panel */
.falecidos-ranking-panel {
  background: var(--card-bg);
  border: 1px solid var(--sidebar-border);
  border-radius: 10px;
  padding: 1rem;
  position: sticky;
  top: 1rem;
}

.ranking-list {
  display: flex;
  flex-direction: column;
  gap: 0.85rem;
}

.ranking-item {
  display: flex;
  flex-direction: column;
  gap: 0.35rem;
}

.ranking-item-top {
  display: flex;
  justify-content: space-between;
  font-size: 0.72rem;
}

.ranking-name {
  font-weight: 600;
  color: var(--text-primary);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  max-width: 200px;
}

.ranking-qty { color: var(--text-muted); font-weight: 700; }

.ranking-bar-bg {
  height: 6px;
  background: var(--sidebar-border);
  border-radius: 99px;
  overflow: hidden;
}

.ranking-bar-fill {
  height: 100%;
  background: linear-gradient(90deg, var(--primary-color), v-bind('RISK_COLORS.HIGH'));
  border-radius: 99px;
}
</style>
