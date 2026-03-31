<script setup>
import { useRoute, useRouter } from 'vue-router';
import { computed, onMounted, ref } from 'vue';
import { useAnalyticsStore } from '@/stores/analytics';
import { useGeoStore } from '@/stores/geo';
import { useFilterStore } from '@/stores/filters';
import { useRiskMetrics } from '@/composables/useRiskMetrics';
import { useFormatting } from '@/composables/useFormatting';
import { useEvolucaoFinanceira } from '@/composables/useEvolucaoFinanceira';
import { useIndicadores } from '@/composables/useIndicadores';
import { useFalecidos } from '@/composables/useFalecidos';
import { useMultiCnpjTimeline } from '@/composables/useMultiCnpjTimeline';
import { useRegional } from '@/composables/useRegional';
import { useFilterParameters } from '@/composables/useFilterParameters';
import RegionalMunicipalityTable from './components/RegionalMunicipalityTable.vue';
import RegionalPharmacyTable from './components/RegionalPharmacyTable.vue';
import { useChartTheme } from '@/config/chartTheme';
import { CHART_TOOLTIP_SHADOW } from '@/config/colors.js';
import { RISK_COLORS, RISK_THRESHOLDS, INDICATOR_GROUPS, INDICATOR_THRESHOLDS } from '@/config/riskConfig';
import { storeToRefs } from 'pinia';
import VChart from 'vue-echarts';
import { use } from 'echarts/core';
import { BarChart, LineChart, ScatterChart } from 'echarts/charts';
import { GridComponent, TooltipComponent, LegendComponent, DataZoomComponent } from 'echarts/components';
import { CanvasRenderer } from 'echarts/renderers';
import TabView from 'primevue/tabview';
import TabPanel from 'primevue/tabpanel';
import Button from 'primevue/button';
import Tag from 'primevue/tag';
import OverlayPanel from 'primevue/overlaypanel';
import Chip from 'primevue/chip';
import Timeline from 'primevue/timeline';

use([BarChart, LineChart, ScatterChart, GridComponent, TooltipComponent, LegendComponent, DataZoomComponent, CanvasRenderer]);

// ── Índices das abas (evita números mágicos no template) ──
const TAB_INDEX = { MOVIMENTACAO: 0, EVOLUCAO: 1, INDICADORES: 2, CRMS: 3, FALECIDOS: 4, REGIAO: 5 };

const route  = useRoute();
const router = useRouter();
const cnpj   = computed(() => route.params.cnpj);

const copied = ref(false);
const copyCnpj = () => {
  if (navigator.clipboard) {
    navigator.clipboard.writeText(cnpj.value);
    copied.value = true;
    setTimeout(() => { copied.value = false; }, 2000);
  }
};

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
const { getApiParams } = useFilterParameters();
const { getRiskSeverity, getRiskLabel, getRiskColor, getRiskClass } = useRiskMetrics();
const { formatCurrencyFull, formatNumberFull, formatarData } = useFormatting();
const { chartTheme, chartDataColors, baseChartConfig } = useChartTheme();
const { evolucaoData, evolucaoLoading, evolucaoLoaded, fetchEvolucao } = useEvolucaoFinanceira();
const { indicadoresData, indicadoresLoading, indicadoresLoaded, fetchIndicadores } = useIndicadores();
const { falecidosData, falecidosLoading, falecidosLoaded, fetchFalecidos } = useFalecidos();
const { timelineData, timelineLoading, fetchTimeline } = useMultiCnpjTimeline();
const { regionalData, regionalLoading, regionalLoaded, fetchRegional } = useRegional();

// ── Filtro Cruzado de Município (Regional) ────────────────
const filterMunicipio = ref(null);

function toggleMunicipioFilter(nome) {
  // Se clicar no mesmo que já está selecionado, limpa o filtro
  if (filterMunicipio.value?.toLowerCase() === nome?.toLowerCase()) {
    filterMunicipio.value = null;
  } else {
    filterMunicipio.value = nome;
  }
}

const filteredFarmacias = computed(() => {
  const farmacias = regionalData.value?.farmacias ?? [];
  if (!filterMunicipio.value) return farmacias;
  
  return farmacias.filter(f => 
    f.municipio?.toLowerCase() === filterMunicipio.value.toLowerCase()
  );
});

// ── Composables (Fim) ─────────────────────────────────────


// ── Agrupamento de falecidos por CPF (igual ao print) ─────
const falecidosAgrupados = computed(() => {
  const transacoes = falecidosData.value?.transacoes ?? [];
  const grupos = new Map();
  for (const t of transacoes) {
    if (!grupos.has(t.cpf)) {
      grupos.set(t.cpf, {
        cpf:           t.cpf,
        nome:          t.nome_falecido || 'NÃO IDENTIFICADO',
        municipio:     t.municipio_falecido,
        uf:            t.uf_falecido,
        dt_obito:      formatarData(t.dt_obito),
        dt_nascimento: formatarData(t.dt_nascimento),
        outros_cnpj:   t.outros_estabelecimentos,
        transacoes:    [],
        total_valor:   0,
        max_dias:      0,
      });
    }
    const g = grupos.get(t.cpf);
    g.transacoes.push(t);
    g.total_valor += t.valor_total_autorizacao ?? 0;
    g.max_dias = Math.max(g.max_dias, t.dias_apos_obito ?? 0);
  }
  return [...grupos.values()];
});

const opMultiCnpj = ref(null);
const selectedMultiCpf = ref(null);

const toggleMultiCnpj = (event, grupo) => {
  selectedMultiCpf.value = grupo;
  opMultiCnpj.value.toggle(event);
  // Dispara o fetch real ao abrir o painel
  if (grupo?.cpf && cnpj.value) {
    fetchTimeline(grupo.cpf, cnpj.value);
  }
};

const parseCnpjs = (s) => (s ? s.split(',').map(v => v.trim()) : []);

const parseDateSafe = (v) => {
  if (!v) return null;
  let d = new Date(v);
  if (isNaN(d.getTime()) && typeof v === 'string') {
    const parts = v.split('/');
    if (parts.length === 3) d = new Date(`${parts[2]}-${parts[1]}-${parts[0]}`);
  }
  return isNaN(d.getTime()) ? null : d.getTime();
};


// ── Gráfico de Trilhas Temporais — usa dados REAIS da API ──
const timelineChartOption = computed(() => {
  // Enquanto carrega, retorna null (o template mostra o spinner)
  if (!timelineData.value || !timelineData.value.events?.length) return null;

  const td = timelineData.value;

  // 1. Mapeia CNPJs únicos → rótulos do eixo Y
  //    O CNPJ de referência sempre fica no índice 0 (topo com inverse:true)
  const cnpjsOrdenados = [cnpj.value];
  td.cnpjs_envolvidos.forEach(c => { if (c !== cnpj.value) cnpjsOrdenados.push(c); });

  // Rótulos: tenta usar a razão social do primeiro evento daquele CNPJ
  const labelMap = {};
  td.events.forEach(e => {
    if (!labelMap[e.cnpj]) {
      labelMap[e.cnpj] = e.razao_social
        ? e.razao_social.substring(0, 22) + (e.razao_social.length > 22 ? '…' : '')
        : e.cnpj;
    }
  });
  const yLabels = cnpjsOrdenados.map((c, i) =>
    i === 0 ? `▶ ${labelMap[c] ?? c}` : (labelMap[c] ?? c)
  );
  const cnpjToIdx = Object.fromEntries(cnpjsOrdenados.map((c, i) => [c, i]));

  // 2. Monta os pontos do scatter
  const dataPoints = td.events.map(e => {
    const ts = parseDateSafe(e.data_autorizacao);
    if (!ts) return null;
    const yIdx = cnpjToIdx[e.cnpj] ?? 0;
    return {
      value: [ts, yIdx, e.valor_total_autorizacao ?? 0, e.num_autorizacao ?? ''],
      itemStyle: { color: e.is_this_cnpj ? '#3b82f6' : '#f59e0b' }
    };
  }).filter(Boolean);

  const allTs = dataPoints.map(p => p.value[0]);
  const pad = 86400000; // 1 dia de margem
  const minTs = Math.min(...allTs) - pad;
  const maxTs = Math.max(...allTs) + pad;

  return {
    backgroundColor: 'transparent',
    grid: { top: 16, left: 210, right: 30, bottom: 40, containLabel: false },
    tooltip: {
      trigger: 'item',
      backgroundColor: 'rgba(15, 23, 42, 0.95)',
      borderColor: 'rgba(255,255,255,0.15)',
      textStyle: { color: '#fff', fontSize: 11 },
      formatter: (params) => {
        const [ts, yIdx, valor, numAut] = params.value;
        const estLabel = yLabels[yIdx] ?? `CNPJ ${yIdx}`;
        const isRef = yIdx === 0;
        const dataFmt = new Date(ts).toLocaleDateString('pt-BR');
        return `<div style="font-weight:700;margin-bottom:4px;color:${isRef ? '#3b82f6' : '#f59e0b'}">${estLabel}</div>
                <div style="opacity:0.8;">Data: ${dataFmt}</div>
                <div style="margin-top:4px;">Valor: <strong>${formatCurrencyFull(valor)}</strong></div>
                ${numAut ? `<div style="opacity:0.5;font-size:10px;">Aut.: ${numAut}</div>` : ''}`;
      }
    },
    dataZoom: [{ type: 'inside', xAxisIndex: 0, zoomOnMouseWheel: true }],
    xAxis: {
      type: 'time',
      min: minTs,
      max: maxTs,
      axisLine: { lineStyle: { color: 'rgba(255,255,255,0.15)' } },
      splitLine: { show: true, lineStyle: { color: 'rgba(255,255,255,0.06)', type: 'dashed' } },
      axisLabel: {
        color: 'rgba(255,255,255,0.5)',
        fontSize: 9,
        formatter: (v) => {
          const date = new Date(v);
          return date.getFullYear().toString();
        }
      },
      splitNumber: 2, // Isso força 3 marcas (Início, Meio e Fim)
    },
    yAxis: {
      type: 'category',
      data: yLabels,
      inverse: true,
      axisLine: { show: false },
      axisTick: { show: false },
      axisLabel: {
        color: 'rgba(255,255,255,0.75)',
        fontSize: 9,
        fontWeight: 700,
        width: 160,
        overflow: 'truncate'
      },
      splitLine: { show: true, lineStyle: { color: 'rgba(255,255,255,0.07)' } }
    },
    series: [{
      type: 'scatter',
      data: dataPoints,
      symbolSize: v => Math.max(12, Math.min(24, 12 + Math.log1p(v[2] / 50))),
      encode: { x: 0, y: 1 }
    }]
  };
});

// CNPJs envolvidos — usa dados reais quando disponíveis
const outrosCnpjList = computed(() => {
  if (timelineData.value?.cnpjs_envolvidos?.length) {
    // Exclui o CNPJ de referência da lista
    return timelineData.value.cnpjs_envolvidos.filter(c => c !== cnpj.value);
  }
  if (!selectedMultiCpf.value) return [];
  return parseCnpjs(selectedMultiCpf.value.outros_cnpj);
});

const openEstablishment = (estabStr) => {
  if (!estabStr) return;
  const targetCnpj = estabStr.split(' - ')[0];
  window.open(`/estabelecimento/${targetCnpj}`, '_blank');
};



// ── Helpers de indicadores ────────────────────────────────
function getIndicadorStatus(riscoUf, thresholdKey = 'default') {
  const t = INDICATOR_THRESHOLDS[thresholdKey] ?? INDICATOR_THRESHOLDS.default;
  const r = riscoUf != null ? Math.round(riscoUf * 10) / 10 : null;
  if (r == null)     return { label: 'SEM DADOS', color: 'var(--text-muted)',      severity: 'secondary' };
  if (r >= t.critico) return { label: 'CRÍTICO',  color: 'var(--risk-critical)', severity: 'danger'    };
  if (r >= t.atencao) return { label: 'ATENÇÃO',  color: 'var(--risk-medium)',   severity: 'warning'   };
  return              { label: 'NORMAL',   color: 'var(--risk-low)',      severity: 'success'   };
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
      const isCritico = riscoUf != null && riscoUf >= t.critico;
      const isAuditadoComValor = ind.key === 'auditado' && d.valor > 0;

      if (isCritico || isAuditadoComValor) {
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
  const c = s.color;
  return { 
    background: `color-mix(in srgb, ${c} 15%, transparent)`, 
    color: c 
  };
}

// ── Dados do CNPJ ─────────────────────────────────────────
const cnpjData = computed(() =>
  resultadoCnpjs.value?.find(c => c.cnpj === cnpj.value) ?? null
);

import { watch } from 'vue';
watch(
  () => cnpj.value,
  async (newCnpj) => {
    if (newCnpj && !cnpjData.value) {
      const p = getApiParams();
      try {
        await analyticsStore.fetchDashboardSummary(
          p.inicio, p.fim, p.percMin, p.percMax, p.valMin,
          'Todos', 'Todos', 'Todos', 'Todos',
          'Todos', 'Todos', 'Todos', newCnpj
        );
      } catch (e) {
        console.error('Erro ao hidratar CNPJ direto:', e);
      }
    }
  },
  { immediate: true }
);

onMounted(() => {
  if (cnpj.value) fetchEvolucao(cnpj.value);
});

const geoData = computed(() => {
  const data = cnpjData.value;
  if (!data || !localidades.value?.length) return null;

  // Primeiro tenta por id_ibge7, depois por município + UF
  if (data.id_ibge7) {
    const match = localidades.value.find(l => l.id_ibge7 === data.id_ibge7);
    if (match) return match;
  }

  // Fallback: busca por nome do município e UF
  const municipio = data.municipio?.toUpperCase();
  const uf = data.uf?.toUpperCase();
  if (!municipio || !uf) return null;

  return localidades.value.find(l =>
    l.no_municipio?.toUpperCase() === municipio &&
    l.sg_uf?.toUpperCase() === uf
  ) ?? null;
});

const risco = computed(() => cnpjData.value?.percValSemComp ?? 0);

const formatPopulacao = (value) =>
  value == null ? '—' : formatNumberFull(value) + ' hab.';

const formatRank = (rank) => {
  if (rank == null) return '—';
  return `${rank}º`;
};

const formatCnpj = (v) => {
  if (!v) return '—';
  const clean = v.replace(/\D/g, '');
  if (clean.length !== 14) return v;
  return clean.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/, '$1.$2.$3/$4-$5');
};

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

    <!-- HEADER REFORMULADO -->
    <div class="detail-header-new shadow-sm">
      
      <!-- Linha superior: Navegação e Identidade Base -->
      <div class="header-top-bar">
        <Button
          icon="pi pi-arrow-left"
          text
          severity="secondary"
          class="back-btn-new"
          @click="router.back()"
          v-tooltip.right="'Voltar para a lista'"
        />
        
        <div class="identity-badges" v-if="cnpjData">
          <div class="cnpj-copy-wrap-new" v-tooltip.top="'Copiar CNPJ'" @click="copyCnpj">
            <span class="cnpj-text">{{ formatCnpj(cnpj) }}</span>
            <i :class="['pi', copied ? 'pi-check text-green-400' : 'pi-copy']" />
          </div>
          <span
            class="risk-tag-new"
            :class="[getRiskClass(risco) === 'risk-critical' ? 'risk-high' : getRiskClass(risco)]"
          >
            <i class="pi pi-exclamation-triangle" />
             Risco {{ getRiskLabel(risco) }}
          </span>
        </div>
      </div>

      <!-- Área Central: Razão Social e Localização -->
      <div class="header-main-info" v-if="cnpjData">
        <div class="title-group">
          <h1 class="razao-social-new">{{ cnpjData.razao_social ?? '—' }}</h1>
          <div class="location-chips">
            <div class="loc-chip" @click="navigateWithFilter('municipio')" v-tooltip.bottom="'Filtrar por ' + (geoData?.no_municipio ?? cnpjData.municipio)">
              <i class="pi pi-map-marker" />
              {{ geoData?.no_municipio ?? cnpjData.municipio }}
            </div>
            <div class="loc-chip" @click="navigateWithFilter('uf')" v-tooltip.bottom="'Filtrar por ' + (geoData?.sg_uf ?? cnpjData.uf)">
              {{ geoData?.sg_uf ?? cnpjData.uf }}
            </div>
            <div class="loc-chip highlight" @click="navigateWithFilter('regiao')" v-tooltip.bottom="'Ver todos da ' + (geoData?.no_regiao_saude ?? 'esta região')">
              <i class="pi pi-share-alt" />
              Região: {{ geoData?.no_regiao_saude ?? 'Não Identificada' }}
            </div>
            <div class="loc-chip muted" v-if="geoData?.nu_populacao">
              <i class="pi pi-users" />
              {{ formatNumberFull(geoData.nu_populacao) }} hab.
            </div>
          </div>
        </div>

        <div class="header-kpis-new">
          <div class="kpi-item-new large">
            <span class="label">% Valor sem Comprovação</span>
            <span class="value" :class="[getRiskClass(risco) === 'risk-critical' ? 'risk-high' : getRiskClass(risco)]">
              {{ cnpjData.percValSemComp?.toFixed(2) }}%
            </span>
          </div>
          <div class="kpi-item-new">
            <span class="label">Valor sem Comprovação</span>
            <span class="value">{{ formatCurrencyFull(cnpjData.valSemComp) }}</span>
          </div>
          <div class="kpi-item-new">
            <span class="label">Total Vendas</span>
            <span class="value">{{ formatCurrencyFull(cnpjData.totalMov) }}</span>
          </div>
        </div>
      </div>

      <!-- Painel de Rankings e Estatísticas -->
      <div class="header-ranking-panel" v-if="cnpjData">
        <div class="ranking-grid-new">
          <div class="rank-card-new">
            <div class="rank-icon-box gold"><i class="pi pi-globe" /></div>
            <div class="rank-info-new">
              <span class="rank-label">Rank Nacional</span>
              <span class="rank-val">{{ formatRank(cnpjData.rank_nacional) }} <small>/ {{ cnpjData.total_nacional }}</small></span>
            </div>
          </div>
          <div class="rank-card-new">
            <div class="rank-icon-box silver"><i class="pi pi-map" /></div>
            <div class="rank-info-new">
              <span class="rank-label">Rank Estadual</span>
              <span class="rank-val">{{ formatRank(cnpjData.rank_uf) }} <small>/ {{ cnpjData.total_uf }}</small></span>
            </div>
          </div>
          <div class="rank-card-new highlighted">
            <div class="rank-icon-box bronze"><i class="pi pi-share-alt" /></div>
            <div class="rank-info-new">
              <span class="rank-label">Rank Regional</span>
              <span class="rank-val">{{ formatRank(cnpjData.rank_regiao_saude) }} <small>/ {{ cnpjData.total_regiao_saude }}</small></span>
            </div>
          </div>
          <div class="rank-card-new">
            <div class="rank-icon-box neutral"><i class="pi pi-building" /></div>
            <div class="rank-info-new">
              <span class="rank-label">Rank Municipal</span>
              <span class="rank-val">{{ formatRank(cnpjData.rank_municipio) }} <small>/ {{ cnpjData.total_municipio }}</small></span>
            </div>
          </div>
        </div>
        
        <div class="regional-stats-new" v-if="cnpjData.total_regiao_saude">
           <i class="pi pi-info-circle" />
           <span>Esta região de saúde possui <strong>{{ cnpjData.total_regiao_saude }}</strong> estabelecimentos de saúde.</span>
        </div>
      </div>

      <div class="header-loading" v-else>
         <i class="pi pi-spin pi-spinner" /> Carregando perfil do estabelecimento...
      </div>
    </div>

    <!-- TABS -->
    <TabView
      class="detail-tabs"
      :activeIndex="TAB_INDEX.EVOLUCAO"
      @tab-change="(e) => {
        console.log('🔄 Tab change event:', e.index);
        if (e.index === TAB_INDEX.EVOLUCAO)    fetchEvolucao(cnpj);
        if (e.index === TAB_INDEX.INDICADORES) fetchIndicadores(cnpj);
        if (e.index === TAB_INDEX.FALECIDOS)   fetchFalecidos(cnpj);
        if (e.index === TAB_INDEX.REGIAO) {
           console.log('📍 Aba Região selecionada. GeoData:', geoData);
           if (geoData?.no_regiao_saude) fetchRegional(geoData.no_regiao_saude);
        }
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

            <div class="shadow-card ind-card">
              <div class="section-header">
                <i class="pi pi-table" />
                <h3>Indicadores de Risco</h3>
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
              </div><!-- ind-table-wrap -->
            </div><!-- ind-card -->
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
                <div class="f-kpi-val-container">
                  <span class="f-kpi-val risk-high">{{ formatCurrencyFull(falecidosData.summary.valor_total) }}</span>
                </div>
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

              <!-- PAINEL MULTI-CNPJ (MOVIDO PARA CIMA) -->
              <div class="falecidos-ranking-panel" v-if="falecidosData.ranking?.length">
                <div class="section-title">
                  <i class="pi pi-share-alt" />
                  <span>Rank de Coincidência em Outros Estabelecimentos</span>
                </div>
                <div class="ranking-grid">
                  <div 
                    v-for="r in falecidosData.ranking" 
                    :key="r.estabelecimento" 
                    class="ranking-card"
                    @click="openEstablishment(r.estabelecimento)"
                    v-tooltip.top="'Clique para abrir detalhamento desta farmácia'"
                  >
                    <div class="r-card-header">
                      <div class="r-icon-box">
                        <i class="pi pi-building" />
                      </div>
                      <div class="r-info">
                        <span class="r-name" :title="r.estabelecimento">{{ r.estabelecimento.split(' - ')[1]?.split(' | ')[0] || r.estabelecimento }}</span>
                        <span class="r-meta">{{ formatCnpj(r.estabelecimento.split(' - ')[0]) }}</span>
                      </div>
                    </div>
                    
                    <div class="r-card-body">
                      <div class="r-stats">
                        <span class="r-qty">{{ r.qtd_cpfs }}</span>
                        <span class="r-label">CPFs Concomitantes</span>
                      </div>
                      
                      <div class="r-progress-wrap">
                        <div class="r-progress-bg">
                          <div class="r-progress-fill" :style="{ width: (r.pct_total * 100) + '%' }"></div>
                        </div>
                        <span class="r-pct">{{ Math.round(r.pct_total * 100) }}%</span>
                      </div>
                    </div>
                  </div>
                </div>
              </div>

              <!-- TABELA DE TRANSAÇÕES -->
              <div class="falecidos-list-container">
                <div class="section-title">
                  <i class="pi pi-list" />
                  <span>Detalhamento de Transações (Agrupado por CPF)</span>
                </div>
                
                <div class="f-table-wrap">
                  <table class="f-table">
                    <colgroup>
                      <col style="width: 10%" /> <!-- CPF -->
                      <col style="width: 18%" /> <!-- Nome do Falecido -->
                      <col style="width: 12%" /> <!-- Município / UF -->
                      <col style="width: 6%" />  <!-- Fonte Óbito -->
                      <col style="width: 13%" /> <!-- Nº Autorização -->
                      <col style="width: 8%" />  <!-- Dt. Óbito -->
                      <col style="width: 10%" /> <!-- Data da Venda -->
                      <col style="width: 6%" />  <!-- Itens -->
                      <col style="width: 9%" />  <!-- Valor -->
                      <col style="width: 8%" />  <!-- Dias -->
                    </colgroup>
                    <thead>
                      <tr>
                        <th>CPF</th>
                        <th>Nome do Falecido</th>
                        <th>Município / UF</th>
                        <th>Fonte Óbito</th>
                        <th>Nº Autorização</th>
                        <th>Dt. Óbito</th>
                        <th>Data da Venda</th>
                        <th>Itens</th>
                        <th>Valor (R$)</th>
                        <th class="txt-center">Dias após Óbito</th>
                      </tr>
                    </thead>
                    <tbody>
                      <template v-for="grupo in falecidosAgrupados" :key="grupo.cpf">
                        <!-- ── LINHA DE CABEÇALHO DO FALECIDO ── -->
                        <tr class="f-group-header">
                          <td colspan="10">
                            <span class="f-group-cpf">{{ grupo.cpf }}</span>
                            <span class="f-group-nome">{{ grupo.nome }}</span>
                            <span class="f-group-sep">—</span>
                            <span class="f-group-meta">{{ grupo.transacoes.length }} autorização(ões)</span>
                            <span class="f-group-sep">|</span>
                            <span class="f-group-meta">{{ formatCurrencyFull(grupo.total_valor) }}</span>
                            <span class="f-group-sep">|</span>
                            <span class="f-group-meta">Óbito: {{ grupo.dt_obito }}</span>
                            <Tag 
                              v-if="grupo.outros_cnpj" 
                              icon="pi pi-share-alt" 
                              value="MULTI-CNPJ" 
                              class="f-multi-tag risk-medium clickable-badge" 
                              @click="(e) => toggleMultiCnpj(e, grupo)"
                              style="margin-left: 0.75rem;" 
                            />
                          </td>
                        </tr>
                        <!-- ── LINHAS DE TRANSAÇÃO ── -->
                        <tr v-for="t in grupo.transacoes" :key="t.num_autorizacao" class="f-row">
                          <td class="f-cpf-cell">{{ t.cpf }}</td>
                          <td>
                            <span class="f-nome">{{ t.nome_falecido || 'NÃO IDENTIFICADO' }}</span>
                          </td>
                          <td class="f-date">{{ grupo.municipio }}/{{ grupo.uf }}</td>
                          <td class="f-fonte">
                            <span v-if="t.fonte_obito && t.fonte_obito.length > 10" v-tooltip.top="t.fonte_obito" style="cursor: default">
                              {{ t.fonte_obito.substring(0, 10) }}...
                            </span>
                            <span v-else>{{ t.fonte_obito }}</span>
                          </td>
                          <td class="f-aut">{{ t.num_autorizacao }}</td>
                          <td class="f-date">{{ formatarData(t.dt_obito) }}</td>
                          <td class="f-date">{{ formatarData(t.data_autorizacao) }}</td>
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
                        <!-- ── LINHA DE SUBTOTAL ── -->
                        <tr class="f-subtotal-row">
                          <td colspan="8" class="f-subtotal-label">Subtotal — {{ grupo.transacoes.length }} autorização(ões)</td>
                          <td class="f-val f-subtotal-val">{{ formatCurrencyFull(grupo.total_valor) }}</td>
                          <td></td>
                        </tr>
                      </template>
                    </tbody>
                    <!-- ── TOTAL GERAL ── -->
                    <tfoot>
                      <tr class="f-grand-total">
                        <td colspan="8">
                          TOTAL GERAL — {{ falecidosAgrupados.length }} CPF(s) distintos — {{ falecidosData.transacoes.length }} autorização(ões)
                        </td>
                        <td class="f-val">{{ formatCurrencyFull(falecidosData.summary.valor_total) }}</td>
                        <td></td>
                      </tr>
                    </tfoot>
                  </table>
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
        <div class="tab-content regional-tab">

          <!-- Sem geo data -->
          <div v-if="!geoData?.no_regiao_saude" class="tab-placeholder">
            <i class="pi pi-map-marker placeholder-icon" />
            <p>Não foi possível identificar a Região de Saúde deste estabelecimento.</p>
          </div>

          <!-- Carregando -->
          <div v-else-if="regionalLoading" class="tab-placeholder">
            <i class="pi pi-spin pi-spinner placeholder-icon" />
            <p>Carregando ranking regional — <strong>{{ geoData.no_regiao_saude }}</strong>...</p>
          </div>

          <!-- Sem dados carregados ainda -->
          <div v-else-if="!regionalLoaded" class="tab-placeholder">
            <i class="pi pi-globe placeholder-icon" />
            <p>Clique na aba para carregar o ranking comparativo da <strong>{{ geoData.no_regiao_saude }}</strong>.</p>
          </div>

          <!-- Sem resultados -->
          <div v-else-if="!regionalData?.farmacias?.length" class="tab-placeholder">
            <i class="pi pi-exclamation-triangle placeholder-icon" />
            <p>Nenhuma farmácia encontrada para a região <strong>{{ geoData.no_regiao_saude }}</strong>.</p>
          </div>

          <!-- Conteúdo principal -->
          <template v-else>
            <RegionalMunicipalityTable 
              :municipios="regionalData.municipios"
              :municipio-atual="filterMunicipio || geoData.no_municipio"
              :uf-atual="geoData.sg_uf"
              :selected-filter="filterMunicipio"
              @select-municipio="toggleMunicipioFilter"
            />

            <RegionalPharmacyTable
              :farmacias="filteredFarmacias"
              :cnpj-atual="cnpj"
              :municipio-atual="geoData.no_municipio"
              :uf-atual="geoData.sg_uf"
            />
          </template>

        </div>
      </TabPanel>

    </TabView>

    <!-- POPOVER MULTI-CNPJ (GRÁFICO DE TRILHAS) -->
    <OverlayPanel ref="opMultiCnpj" class="multi-cnpj-panel" style="width: 900px">
      <div v-if="selectedMultiCpf" class="multi-cnpj-content">
        <header class="multi-header">
          <i class="pi pi-share-alt" />
          <span>Mapa de Relacionamento Temporal</span>
          <i v-if="timelineLoading" class="pi pi-spin pi-spinner" style="margin-left:auto;font-size:0.8rem;opacity:0.6;" />
        </header>

        <!-- Meta do CPF -->
        <div class="multi-cpf-meta">
          <span class="multi-cpf-label">CPF:</span>
          <span class="multi-cpf-val">{{ selectedMultiCpf.cpf }}</span>
          <span class="multi-cpf-sep">·</span>
          <span class="multi-cpf-name">{{ selectedMultiCpf.nome }}</span>
          <span class="multi-cpf-sep">·</span>
          <span class="multi-cpf-obito">Óbito: {{ selectedMultiCpf.dt_obito }}</span>
        </div>

        <p class="multi-desc">Relacionamento gráfico das vendas detectadas nos diferentes estabelecimentos:</p>

        <!-- Legenda -->
        <div class="multi-legend">
          <span class="legend-dot" style="background:#3b82f6"></span><span>Este Estabelecimento</span>
          <span class="legend-dot" style="background:#f59e0b;margin-left:1rem"></span><span>Outro Estabelecimento</span>
        </div>

        <!-- Área do gráfico: spinner | gráfico | sem dados -->
        <div class="timeline-chart-wrap">
          <div v-if="timelineLoading" class="timeline-loading">
            <i class="pi pi-spin pi-spinner" />
            <span>Buscando transações reais...</span>
          </div>
          <div v-else-if="!timelineChartOption" class="timeline-empty">
            <i class="pi pi-inbox" />
            <span>Sem dados de transações para exibir.</span>
          </div>
          <VChart v-else :option="timelineChartOption" autoresize />
        </div>

        <!-- Lista dos CNPJs vinculados -->
        <div class="multi-cnpj-list-section" v-if="outrosCnpjList.length">
          <div class="multi-cnpj-list-title">
            <i class="pi pi-building" />
            <span>CNPJs vinculados ao mesmo CPF</span>
          </div>
          <ul class="multi-list">
            <li v-for="(c, i) in outrosCnpjList" :key="c" class="multi-item">
              <span class="multi-idx">{{ i + 1 }}</span>
              <a 
                :href="`/estabelecimento/${c}`" 
                target="_blank" 
                class="multi-cnpj-link"
                v-tooltip.bottom="'Abrir detalhamento deste CNPJ em nova aba'"
              >
                {{ formatCnpj(c) }}
                <i class="pi pi-external-link" style="font-size: 0.6rem; margin-left: 0.3rem; opacity: 0.5;" />
              </a>
            </li>
          </ul>
        </div>
      </div>
    </OverlayPanel>
  </div>
</template>

<style scoped>
.cnpj-detail-page {
  display: flex;
  flex-direction: column;
  height: 100%;
  overflow: hidden;
}

/* ── HEADER REFORMULADO (FULL WIDTH) ──────────────────── */
.detail-header-new {
  background: var(--card-bg);
  padding: 1.5rem 2rem;
  border-bottom: 1px solid var(--sidebar-border);
  display: flex;
  flex-direction: column;
  gap: 1.5rem;
  flex-shrink: 0;
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
  z-index: 10;
}

.header-top-bar {
  display: flex;
  align-items: center;
  gap: 1.5rem;
}

.back-btn-new {
  width: 36px !important;
  height: 36px !important;
}

.identity-badges {
  display: flex;
  align-items: center;
  gap: 0.75rem;
}

.cnpj-copy-wrap-new {
  background: color-mix(in srgb, var(--sidebar-border) 40%, transparent);
  padding: 0.25rem 0.75rem;
  border-radius: 6px;
  cursor: pointer;
  display: flex;
  align-items: center;
  gap: 0.5rem;
  transition: all 0.2s;
}

.cnpj-copy-wrap-new:hover {
  background: color-mix(in srgb, var(--sidebar-border) 70%, transparent);
}

.cnpj-text {
  font-family: monospace;
  font-size: 0.85rem;
  font-weight: 700;
  letter-spacing: 0.05em;
  color: var(--text-secondary);
}

.risk-tag-new {
  display: inline-flex;
  align-items: center;
  gap: 0.4rem;
  padding: 0.25rem 0.75rem;
  border-radius: 6px;
  font-size: 0.7rem;
  font-weight: 800;
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

.header-main-info {
  display: flex;
  justify-content: space-between;
  align-items: flex-end;
  gap: 2rem;
}

.title-group {
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
  min-width: 0;
}

.razao-social-new {
  font-size: 1.75rem;
  font-weight: 800;
  margin: 0;
  line-height: 1.1;
  letter-spacing: -0.02em;
  color: var(--text-primary);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.location-chips {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
}

.loc-chip {
  display: flex;
  align-items: center;
  gap: 0.35rem;
  padding: 0.2rem 0.6rem;
  background: color-mix(in srgb, var(--primary-color) 8%, transparent);
  border: 1px solid color-mix(in srgb, var(--primary-color) 15%, transparent);
  border-radius: 6px;
  font-size: 0.75rem;
  font-weight: 600;
  color: var(--text-secondary);
  cursor: pointer;
  transition: all 0.2s;
}

.loc-chip:hover {
  background: color-mix(in srgb, var(--primary-color) 15%, transparent);
  border-color: var(--primary-color);
}

.loc-chip.highlight {
  background: color-mix(in srgb, var(--risk-low) 10%, transparent);
  border-color: color-mix(in srgb, var(--risk-low) 20%, transparent);
}

.loc-chip.muted {
  background: transparent;
  border: 1px dashed var(--sidebar-border);
  cursor: default;
}

.header-kpis-new {
  display: flex;
  gap: 2rem;
}

.kpi-item-new {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
}

.kpi-item-new .label {
  font-size: 0.65rem;
  font-weight: 700;
  text-transform: uppercase;
  color: var(--text-muted);
  letter-spacing: 0.05em;
}

.kpi-item-new .value {
  font-size: 1.25rem;
  font-weight: 700;
  color: var(--text-primary);
}

.kpi-item-new.large .value {
  font-size: 1.75rem;
  letter-spacing: -0.02em;
}

/* ── RANKING PANEL ── */
.header-ranking-panel {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 1.5rem;
  padding-top: 1rem;
  border-top: 1px solid var(--sidebar-border);
}

.ranking-grid-new {
  display: flex;
  gap: 1rem;
}

.rank-card-new {
  background: color-mix(in srgb, var(--card-bg) 60%, var(--sidebar-border));
  border: 1px solid var(--sidebar-border);
  padding: 0.5rem 0.75rem;
  border-radius: 10px;
  display: flex;
  align-items: center;
  gap: 0.75rem;
  min-width: 160px;
  backdrop-filter: blur(8px);
}

.rank-card-new.highlighted {
  border-color: color-mix(in srgb, var(--primary-color) 30%, transparent);
  background: color-mix(in srgb, var(--primary-color) 5%, var(--card-bg));
  box-shadow: 0 4px 12px rgba(var(--primary-color-rgb), 0.1);
}

.rank-icon-box {
  width: 32px;
  height: 32px;
  border-radius: 8px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 1rem;
}

.rank-icon-box.gold   { background: rgba(255, 215, 0, 0.15); color: #ffd700; }
.rank-icon-box.silver { background: rgba(192, 192, 192, 0.15); color: #c0c0c0; }
.rank-icon-box.bronze { background: rgba(205, 127, 50, 0.15); color: #cd7f32; }
.rank-icon-box.neutral { background: rgba(148, 163, 184, 0.15); color: #94a3b8; }

.rank-info-new {
  display: flex;
  flex-direction: column;
}

.rank-label {
  font-size: 0.62rem;
  font-weight: 700;
  text-transform: uppercase;
  color: var(--text-muted);
  letter-spacing: 0.04em;
}

.rank-val {
  font-size: 1.1rem;
  font-weight: 800;
  color: var(--text-primary);
}

.rank-val small {
  font-size: 0.75rem;
  font-weight: 500;
  opacity: 0.5;
}

.regional-stats-new {
  display: flex;
  align-items: center;
  gap: 0.6rem;
  font-size: 0.8rem;
  color: var(--text-secondary);
  background: color-mix(in srgb, var(--primary-color) 6%, transparent);
  padding: 0.5rem 1rem;
  border-radius: 8px;
  border: 1px dashed color-mix(in srgb, var(--primary-color) 30%, transparent);
}

.header-loading {
  padding: 2rem;
  text-align: center;
  font-size: 0.9rem;
  color: var(--text-muted);
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
  background: transparent !important;
  border-bottom: 1px solid var(--sidebar-border);
  padding: 0 1.25rem;
}

:deep(.p-tabview-nav-content) {
  background: var(--card-bg) !important;
}

:deep(.p-tabview-nav li .p-tabview-nav-link) {
  font-size: 0.8rem;
  padding: 0.75rem 1rem;
  gap: 0.4rem;
  transition: all 0.2s;
  color: var(--text-secondary) !important;
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

/* ── REGIÃO DE SAÚDE ─────────────────────────────────── */
.regional-tab {
  display: flex;
  flex-direction: column;
  gap: 1rem;
  padding: 1rem 0 1rem 0;
}

/* ── EVOLUÇÃO FINANCEIRA ─────────────────────────────── */
.evolucao-tab {
  display: flex;
  flex-direction: column;
  gap: 1.25rem;
  padding: 1rem 0 0; /* Removido padding lateral para alinhar com o cabeçalho */
}

.evolucao-card {
  background: var(--card-bg);
  border: 1px solid var(--sidebar-border);
  border-radius: 12px;
  overflow: hidden;
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.05);
  margin-bottom: 0.5rem;
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
  color: var(--text-secondary);
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
  color: var(--text-secondary);
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
  color: var(--text-secondary);
  border-bottom: 1px solid var(--sidebar-border);
}

.evolucao-table tbody tr:hover td { background: var(--sidebar-border); }

.evolucao-table tfoot td {
  border-top: 2px solid var(--sidebar-border);
  border-bottom: none;
  background: color-mix(in srgb, var(--card-bg) 80%, var(--sidebar-border));
}

.sem-label   { font-weight: 600; color: var(--text-secondary); }
.col-regular { color: var(--risk-low); }
.col-irregular { color: var(--risk-high); }

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
.pct-critical { color: var(--risk-critical); }
.pct-high     { color: var(--risk-high); }
.pct-medium   { color: var(--risk-medium); }
.pct-low      { color: var(--risk-low); }

/* ── Tendência ───────────────────────────────────────── */
.trend-cell {
  text-align: center;
  font-size: 0.75rem;
  font-weight: 700;
  white-space: nowrap;
}

.trend-up      { color: var(--risk-high); }
.trend-down    { color: var(--risk-low); }
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
  border: 1px solid color-mix(in srgb, var(--risk-high) 30%, transparent);
  border-radius: 10px;
  background: color-mix(in srgb, var(--risk-high) 6%, var(--card-bg));
  overflow: hidden;
}

.audit-summary-header {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.6rem 1.25rem;
  border-bottom: 1px solid color-mix(in srgb, var(--risk-high) 20%, transparent);
  font-size: 0.72rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.07em;
  color: var(--risk-high);
}

.audit-badge {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 1.25rem;
  height: 1.25rem;
  padding: 0 0.3rem;
  border-radius: 99px;
  background: color-mix(in srgb, var(--risk-high) 20%, transparent);
  color: var(--risk-high);
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
  color: var(--text-secondary);
  line-height: 1.4;
}

.audit-item-icon {
  font-size: 0.7rem;
  color: var(--risk-critical);
  flex-shrink: 0;
  margin-top: 0.05rem;
}

.audit-risco {
  font-weight: 700;
  color: var(--risk-critical);
}

.audit-detail {
  font-size: 0.75rem;
  color: var(--text-muted);
  margin-left: 0.25rem;
}

.ind-card {
  padding-bottom: 0;
}

.ind-card .section-header {
  margin-bottom: 0;
  padding-bottom: 0.75rem;
  border-bottom: 1px solid var(--sidebar-border);
}

.ind-table-wrap {
  overflow: hidden;
  border-radius: 0 0 16px 16px;
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
  color: var(--text-secondary);
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
  color: var(--text-secondary);
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
  color: var(--text-secondary);
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
  padding: 1rem 0 0;
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
  color: var(--text-secondary);
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

.f-kpi-val-container {
  display: flex;
  margin-top: 0.2rem;
}

.f-kpi-val {
  font-size: 1.1rem;
  font-weight: 700;
  color: var(--text-primary);
}

.f-kpi-val.risk-high {
  font-size: 0.95rem; /* Leve ajuste para caber no badge */
  padding: 0.1rem 0.6rem;
  border-radius: 99px;
}

.f-kpi-val small {
  font-size: 0.7rem;
  opacity: 0.6;
}

.highlight-red {
  background: color-mix(in srgb, var(--risk-high) 8%, var(--card-bg)) !important;
  border-color: color-mix(in srgb, var(--risk-high) 25%, transparent) !important;
}
.highlight-red .f-kpi-label { color: var(--risk-high) !important; opacity: 0.75; }

.warning {
  background: color-mix(in srgb, var(--risk-medium) 12%, var(--card-bg)) !important;
  border-color: color-mix(in srgb, var(--risk-medium) 35%, transparent) !important;
}
.warning .f-kpi-val { color: var(--risk-medium) !important; }
.warning .f-kpi-label { color: var(--risk-medium) !important; opacity: 0.85; }

.falecidos-list-container {
  margin-top: 1.5rem;
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
  color: var(--text-secondary);
  border-bottom: 2px solid var(--sidebar-border);
}

.f-table td {
  padding: 0.75rem 1rem;
  border-bottom: 1px solid var(--sidebar-border);
  font-size: 0.8rem;
  color: var(--text-secondary);
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
  font-size: 0.65rem !important;
  margin-top: 0.1rem;
  height: auto;
  padding: 0.1rem 0.5rem;
  background: transparent;
  border-radius: 99px;
}

.clickable-badge {
  cursor: pointer;
  transition: transform 0.1s;
}
.clickable-badge:hover { transform: scale(1.05); }

/* ── MULTI-CNPJ OVERLAY ────────────────────────────── */
.multi-cnpj-panel {
  background: color-mix(in srgb, var(--card-bg) 85%, transparent) !important;
  backdrop-filter: blur(12px);
  border: 1px solid var(--sidebar-border) !important;
  box-shadow: 0 12px 32px rgba(0,0,0,0.4) !important;
  border-radius: 12px !important;
}

.multi-cnpj-content {
  padding: 0.5rem 0.25rem;
}

.multi-cnpj-panel::before, .multi-cnpj-panel::after {
  display: none !important; /* Remove a seta padrão para um look mais clean */
}

.multi-header {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  font-size: 0.7rem;
  font-weight: 700;
  text-transform: uppercase;
  color: var(--risk-medium);
  margin-bottom: 0.75rem;
  padding-bottom: 0.5rem;
  border-bottom: 1px solid var(--sidebar-border);
}

.multi-desc {
  font-size: 0.75rem;
  color: var(--text-secondary);
  line-height: 1.4;
  margin-bottom: 0.75rem;
}

.multi-list {
  list-style: none;
  padding: 0.75rem 1rem 1rem;
  margin: 0;
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
  gap: 0.6rem;
}

.multi-item {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  padding: 0.25rem 0.6rem;
  background: rgba(255,255,255,0.04);
  border: 1px solid rgba(255,255,255,0.06);
  border-radius: 4px;
  font-size: 0.72rem;
  color: var(--text-secondary);
}

.multi-cnpj-link {
  font-family: monospace;
  font-weight: 600;
  letter-spacing: 0.05em;
  color: var(--primary-color);
  text-decoration: none;
  cursor: pointer;
  transition: all 0.2s;
  display: flex;
  align-items: center;
}

.multi-cnpj-link:hover {
  filter: brightness(1.2);
  text-decoration: underline;
}

/* ── MAPA DE TRILHAS NO POPOVER ─────────────────────── */
.multi-cpf-meta {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.3rem;
  font-size: 0.72rem;
  margin-bottom: 0.5rem;
  padding: 0.4rem 0.6rem;
  background: rgba(255,255,255,0.04);
  border-radius: 6px;
  border: 1px solid rgba(255,255,255,0.06);
}

.multi-cpf-label { color: rgba(255,255,255,0.4); font-weight: 700; text-transform: uppercase; font-size: 0.63rem; }
.multi-cpf-val   { font-family: monospace; font-weight: 700; color: rgba(255,255,255,0.9); letter-spacing: 0.05em; }
.multi-cpf-sep   { color: rgba(255,255,255,0.25); }
.multi-cpf-name  { font-weight: 600; color: rgba(255,255,255,0.75); }
.multi-cpf-obito { font-size: 0.68rem; color: rgba(255,165,0,0.8); font-weight: 600; }

.multi-legend {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  font-size: 0.68rem;
  color: rgba(255,255,255,0.5);
  margin-bottom: 0.4rem;
}

.legend-dot {
  display: inline-block;
  width: 10px;
  height: 10px;
  border-radius: 50%;
  flex-shrink: 0;
}

.timeline-chart-wrap {
  width: 100%;
  height: 400px;
  background: rgba(0,0,0,0.15);
  border-radius: 8px;
  margin: 0.25rem 0 0.5rem;
  padding: 0.25rem;
  border: 1px solid rgba(255,255,255,0.05);
  position: relative;
}

.timeline-loading,
.timeline-empty {
  position: absolute;
  inset: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 0.5rem;
  font-size: 0.75rem;
  color: rgba(255,255,255,0.4);
}

.timeline-loading i,
.timeline-empty i {
  font-size: 1.2rem;
  color: rgba(255,255,255,0.3);
}

.multi-cnpj-list-section {
  margin-top: 0.5rem;
  background: rgba(255,255,255,0.03);
  border: 1px solid rgba(255,255,255,0.07);
  border-radius: 8px;
  overflow: hidden;
  margin-bottom: 0.5rem;
}

.multi-cnpj-list-title {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  padding: 0.4rem 0.75rem;
  font-size: 0.66rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: rgba(255,165,0,0.8);
  border-bottom: 1px solid rgba(255,255,255,0.06);
  background: rgba(255,165,0,0.06);
}

.multi-idx {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 18px;
  height: 18px;
  border-radius: 50%;
  background: rgba(245,158,11,0.2);
  color: #f59e0b;
  font-size: 0.65rem;
  font-weight: 800;
  flex-shrink: 0;
}

.timeline-footer {
  margin-top: 0.25rem;
  padding: 0.6rem 0.75rem;
  background: rgba(255,165,0,0.06);
  border: 1px solid rgba(255,165,0,0.15);
  border-radius: 8px;
  display: flex;
  gap: 0.5rem;
  align-items: flex-start;
}

.timeline-footer i {
  color: orange;
  font-size: 0.8rem;
  margin-top: 0.1rem;
}

.timeline-footer span {
  font-size: 0.68rem;
  color: var(--text-secondary);
  line-height: 1.4;
  font-weight: 500;
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

.d-medium   { background: color-mix(in srgb, var(--risk-medium)   15%, transparent); color: var(--risk-medium);   border: 1px solid color-mix(in srgb, var(--risk-medium) 30%, transparent); }
.d-high     { background: color-mix(in srgb, var(--risk-high)     15%, transparent); color: var(--risk-high);     border: 1px solid color-mix(in srgb, var(--risk-high)   30%, transparent); }
.d-critical { 
  background: color-mix(in srgb, var(--risk-critical) 15%, transparent); 
  color: var(--risk-critical); 
  border: 1px solid color-mix(in srgb, var(--risk-critical) 30%, transparent); 
  font-weight: 800; 
}

.f-cpf-cell { font-family: monospace; font-size: 0.75rem; color: var(--text-secondary); }
.f-fonte { font-size: 0.72rem; color: var(--text-secondary); }

/* ── Linha de cabeçalho do grupo (por falecido) ── */
.f-group-header td {
  background: color-mix(in srgb, var(--primary-color) 10%, var(--card-bg));
  border-top: 2px solid color-mix(in srgb, var(--primary-color) 40%, transparent);
  border-bottom: 1px solid color-mix(in srgb, var(--primary-color) 25%, transparent);
  padding: 0.55rem 1rem;
  font-size: 0.78rem;
}

.f-group-cpf {
  font-family: monospace;
  font-weight: 700;
  color: var(--text-secondary);
  margin-right: 0.6rem;
}

.f-group-nome {
  font-weight: 800;
  font-size: 0.82rem;
  color: var(--text-secondary);
  text-transform: uppercase;
  letter-spacing: 0.03em;
  margin-right: 0.4rem;
}

.f-group-sep {
  color: var(--text-secondary);
  margin: 0 0.4rem;
  opacity: 0.6;
}

.f-group-meta {
  font-size: 0.76rem;
  font-weight: 600;
  color: var(--text-secondary);
}

/* ── Linha de subtotal por falecido ── */
.f-subtotal-row td {
  background: color-mix(in srgb, var(--sidebar-border) 30%, var(--card-bg));
  border-top: 1px solid var(--sidebar-border);
  border-bottom: 2px solid var(--sidebar-border);
  padding: 0.4rem 1rem;
}

.f-subtotal-label {
  font-size: 0.72rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: var(--text-secondary);
  text-align: right;
}

.f-subtotal-val {
  font-weight: 800 !important;
  color: var(--text-secondary) !important;
}

/* ── Total geral (tfoot) ── */
.f-grand-total td {
  background: color-mix(in srgb, var(--primary-color) 8%, var(--card-bg));
  border-top: 2px solid color-mix(in srgb, var(--primary-color) 30%, transparent);
  padding: 0.65rem 1rem;
  font-size: 0.78rem;
  font-weight: 800;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: var(--text-secondary);
}

.f-grand-total .f-val {
  color: var(--text-secondary) !important;
  font-size: 0.88rem;
}

/* Ranking Panel */
.falecidos-ranking-panel {
  background: var(--card-bg);
  border: 1px solid var(--sidebar-border);
  border-radius: 12px;
  padding: 1.25rem;
  margin-top: 1.5rem;
  box-shadow: 0 4px 15px rgba(0,0,0,0.1);
}

.ranking-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
  gap: 0.75rem;
  margin-top: 0.75rem;
}

.ranking-card {
  background: rgba(255,255,255,0.03);
  border: 1px solid rgba(255,255,255,0.08);
  border-radius: 10px;
  padding: 0.75rem 1rem;
  transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
  cursor: pointer;
}

.ranking-card:hover {
  background: rgba(255,255,255,0.05);
  border-color: var(--primary-color);
  transform: translateY(-2px);
  box-shadow: 0 4px 12px rgba(0,0,0,0.15);
}

.r-card-header {
  display: flex;
  align-items: center;
  gap: 0.6rem;
}

.r-icon-box {
  width: 28px;
  height: 28px;
  background: color-mix(in srgb, var(--primary-color) 12%, transparent);
  border-radius: 6px;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--primary-color);
  font-size: 0.8rem;
}

.r-info {
  display: flex;
  flex-direction: column;
  overflow: hidden;
  min-width: 0; 
  flex: 1;
}

.r-name {
  font-size: 0.72rem;
  font-weight: 700;
  color: var(--text-primary);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  width: 100%;
}

.r-meta {
  font-size: 0.65rem;
  color: var(--text-muted);
  font-family: monospace;
}

.r-card-body {
  display: flex;
  flex-direction: column;
  gap: 0.35rem;
}

.r-stats {
  display: flex;
  align-items: center;
  gap: 0.35rem;
}

.r-qty {
  font-size: 1.1rem;
  font-weight: 800;
  color: var(--primary-color);
}

.r-label {
  font-size: 0.62rem;
  color: var(--text-secondary);
}

.r-progress-wrap {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  width: 100%;
}

.r-progress-bg {
  flex: 1;
  height: 4px;
  background: rgba(255,255,255,0.05);
  border-radius: 2px;
  overflow: hidden;
}

.r-progress-fill {
  height: 100%;
  background: linear-gradient(90deg, var(--primary-color), color-mix(in srgb, var(--primary-color) 70%, white));
  border-radius: 2px;
}

.r-pct {
  font-size: 0.65rem;
  color: var(--text-muted);
  font-weight: 700;
  min-width: 25px;
}
.highlight-red {
  border-left: 3px solid v-bind('chartDataColors.red') !important;
  background: color-mix(in srgb, v-bind('chartDataColors.red') 10%, var(--card-bg)) !important;
}

.highlight-red .f-kpi-val {
  color: v-bind('chartDataColors.red') !important;
  font-weight: 800;
}

.filter-status-row {
  display: flex;
  align-items: center;
  gap: 1rem;
  padding: 0.75rem 1.5rem;
  background: color-mix(in srgb, var(--primary-color) 4%, var(--card-bg));
  border: 1px dashed var(--sidebar-border);
  border-radius: 8px;
  margin: 1rem 0;
}

.filter-label {
  font-size: 0.85rem;
  font-weight: 600;
  color: var(--text-secondary);
  text-transform: uppercase;
  letter-spacing: 0.02em;
}

:deep(.municipio-chip) {
  background: var(--primary-color) !important;
  color: white !important;
  font-weight: 600;
  font-size: 0.9rem;
}
</style>
