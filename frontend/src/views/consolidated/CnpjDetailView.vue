<script setup>
import { useRoute, useRouter } from 'vue-router';
import { computed, onMounted, ref } from 'vue';
import { useAnalyticsStore } from '@/stores/analytics';
import { useGeoStore } from '@/stores/geo';
import { useFilterStore } from '@/stores/filters';
import { useRiskMetrics } from '@/composables/useRiskMetrics';
import { useFormatting } from '@/composables/useFormatting';
import { useFilterParameters } from '@/composables/useFilterParameters';
import CnpjDetailHeader from './components/cnpj/CnpjDetailHeader.vue';
import CnpjTabFinancialEvolution from './components/cnpj/CnpjTabFinancialEvolution.vue';
import CnpjTabIndicators from './components/cnpj/CnpjTabIndicators.vue';
import CnpjTabFalecidos from './components/cnpj/CnpjTabFalecidos.vue';
import CnpjTabRegional from './components/cnpj/CnpjTabRegional.vue';
import { useChartTheme } from '@/config/chartTheme';
import { CHART_TOOLTIP_SHADOW } from '@/config/colors.js';
import { RISK_COLORS, RISK_THRESHOLDS } from '@/config/riskConfig';
import { storeToRefs } from 'pinia';
import TabView from 'primevue/tabview';
import TabPanel from 'primevue/tabpanel';
import Button from 'primevue/button';
import Tag from 'primevue/tag';
import Chip from 'primevue/chip';

// ── Índices das abas (evita números mágicos no template) ──
const TAB_INDEX = { MOVIMENTACAO: 0, EVOLUCAO: 1, INDICADORES: 2, CRMS: 3, FALECIDOS: 4, REGIAO: 5 };

const route  = useRoute();
const cnpj   = computed(() => route.params.cnpj);

// ── Stores ────────────────────────────────────────────────
const analyticsStore = useAnalyticsStore();
const { resultadoCnpjs } = storeToRefs(analyticsStore);

const geoStore = useGeoStore();
const { localidades } = storeToRefs(geoStore);

// ── Composables ───────────────────────────────────────────
const { getApiParams } = useFilterParameters();
const { getRiskSeverity, getRiskLabel, getRiskColor, getRiskClass } = useRiskMetrics();
const { formatCurrencyFull, formatNumberFull, formatarData } = useFormatting();
const { chartTheme, chartDataColors, baseChartConfig } = useChartTheme();
// ── Composables (Fim) ─────────────────────────────────────

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
  // Evolução Financeira agora é carregada de forma autônoma pelo componente filho
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



const formatCnpj = (v) => {
  if (!v) return '—';
  const clean = v.replace(/\D/g, '');
  if (clean.length !== 14) return v;
  return clean.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/, '$1.$2.$3/$4-$5');
};

</script>

<template>
  <div class="cnpj-detail-page">

    <!-- HEADER (COMPONENTE ISOLADO) -->
    <CnpjDetailHeader :cnpj="cnpj" :cnpj-data="cnpjData" :geo-data="geoData" />

    <!-- TABS -->
    <TabView
      class="detail-tabs"
      :activeIndex="TAB_INDEX.EVOLUCAO"
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
        <CnpjTabFinancialEvolution />
      </TabPanel>

      <TabPanel>
        <template #header><i class="pi pi-shield tab-icon" /><span>Indicadores</span></template>
        <CnpjTabIndicators />
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
        <CnpjTabFalecidos :cnpj="cnpj" />
      </TabPanel>

      <TabPanel>
        <template #header><i class="pi pi-map tab-icon" /><span>Região de Saúde</span></template>
        <CnpjTabRegional :cnpj="cnpj" :geo-data="geoData" />
      </TabPanel>

    </TabView>


  </div>
</template>

<style scoped>
.cnpj-detail-page {
  display: flex;
  flex-direction: column;
  height: 100%;
  overflow-y: auto;
  gap: 1.25rem; /* Respiro clássico entre os grandes blocos (Header e Dados) */
  background: transparent;
}



/* ── CARD MESTRE DE DADOS (ABAS + CONTEÚDO UNIFICADOS - OPÇÃO B) ── */
.detail-tabs {
  flex: 1;
  display: flex;
  flex-direction: column;
  overflow: hidden;
  background: var(--card-bg); /* O conteúdo técnico agora vive dentro deste grande card */
  border: 1px solid var(--sidebar-border);
  border-radius: 12px;
  box-shadow: 0 4px 15px rgba(0, 0, 0, 0.1);
  margin-bottom: 2rem;
}

/* Removemos a redundância de cards aninhados para um visual cleaner */
.detail-tabs :deep(.shadow-card) {
  border: none !important;
  box-shadow: none !important;
  background: transparent !important;
  padding: 0 !important;
}

.detail-tabs :deep(.table-section) {
  padding: 1.5rem;
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
  background: color-mix(in srgb, var(--card-bg) 95%, var(--sidebar-border)) !important; /* Ligeiro destaque na barra de navegação */
  border-bottom: 1px solid var(--sidebar-border);
  padding: 0 1.25rem;
}

:deep(.p-tabview-nav li .p-tabview-nav-link) {
  font-size: 0.78rem;
  font-weight: 700;
  padding: 0.65rem 1.25rem;
  gap: 0.5rem;
  transition: all 0.2s;
  color: var(--text-secondary) !important;
  text-transform: none !important;
}

:deep(.p-tabview-nav li.p-highlight .p-tabview-nav-link) {
  border-bottom-color: var(--primary-color) !important;
  color: var(--primary-color) !important;
  background: color-mix(in srgb, var(--primary-color) 8%, transparent) !important;
}

.tab-icon { font-size: 0.8rem; }

/* ── PLACEHOLDER E CONTEÚDO ──────────────────────────── */
.tab-content { padding: 1.5rem 2rem; } /* Alinhado horizontalmente com o header */

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


</style>
