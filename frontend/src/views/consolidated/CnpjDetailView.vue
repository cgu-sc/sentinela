<script setup>
import { useRoute, useRouter } from "vue-router";
import { computed, onMounted, ref } from "vue";
import { useAnalyticsStore } from "@/stores/analytics";
import { useGeoStore } from "@/stores/geo";
import { useFilterStore } from "@/stores/filters";
import { useCnpjNavStore } from "@/stores/cnpjNav";
import { useRiskMetrics } from "@/composables/useRiskMetrics";
import { useFormatting } from "@/composables/useFormatting";
import { useFilterParameters } from "@/composables/useFilterParameters";
import CnpjDetailHeader from "./components/cnpj/CnpjDetailHeader.vue";
import CnpjTabFinancialEvolution from "./components/cnpj/CnpjTabFinancialEvolution.vue";
import CnpjTabIndicators from "./components/cnpj/CnpjTabIndicators.vue";
import CnpjTabFalecidos from "./components/cnpj/CnpjTabFalecidos.vue";
import CnpjTabRegional from "./components/cnpj/CnpjTabRegional.vue";
import CnpjTabPrescritores from "./components/cnpj/CnpjTabPrescritores.vue";
import { useChartTheme } from "@/config/chartTheme";
import { CHART_TOOLTIP_SHADOW } from "@/config/colors.js";
import { RISK_COLORS, RISK_THRESHOLDS } from "@/config/riskConfig";
import { storeToRefs } from "pinia";
import TabView from "primevue/tabview";
import TabPanel from "primevue/tabpanel";
import Button from "primevue/button";
import Tag from "primevue/tag";
import Chip from "primevue/chip";

// ── Índices das abas (evita números mágicos no template) ──
const TAB_INDEX = {
  MOVIMENTACAO: 0,
  EVOLUCAO: 1,
  INDICADORES: 2,
  CRMS: 3,
  FALECIDOS: 4,
  REGIAO: 5,
};

const route = useRoute();
const router = useRouter();
const cnpj = computed(() => route.params.cnpj);

// ── Stores ────────────────────────────────────────────────
const analyticsStore = useAnalyticsStore();
const { resultadoCnpjs } = storeToRefs(analyticsStore);

const geoStore = useGeoStore();
const { localidades } = storeToRefs(geoStore);

const cnpjNav = useCnpjNavStore();

// ── Composables ───────────────────────────────────────────
const { getApiParams } = useFilterParameters();
const { getRiskSeverity, getRiskLabel, getRiskColor, getRiskClass } =
  useRiskMetrics();
const { formatCurrencyFull, formatNumberFull, formatarData } = useFormatting();
const { chartTheme, chartDataColors, baseChartConfig } = useChartTheme();
// ── Composables (Fim) ─────────────────────────────────────

// ── Dados do CNPJ ─────────────────────────────────────────
const cnpjData = computed(
  () => resultadoCnpjs.value?.find((c) => c.cnpj === cnpj.value) ?? null,
);

import { watch } from "vue";
watch(
  () => cnpj.value,
  async (newCnpj, oldCnpj) => {
    // Ao trocar de CNPJ, reseta navegação e limpa a evolução financeira
    if (newCnpj !== oldCnpj) {
      analyticsStore.resetEvolucaoFinanceira();
      cnpjNav.reset(TAB_INDEX.EVOLUCAO);
    }
    if (newCnpj && !cnpjData.value) {
      const p = getApiParams();
      try {
        await analyticsStore.fetchDashboardSummary(
          p.inicio,
          p.fim,
          p.percMin,
          p.percMax,
          p.valMin,
          "Todos",
          "Todos",
          "Todos",
          "Todos",
          "Todos",
          "Todos",
          "Todos",
          newCnpj,
        );
      } catch (e) {
        console.error("Erro ao hidratar CNPJ direto:", e);
      }
    }
  },
  { immediate: true },
);


onMounted(() => {
  // Evolução Financeira agora é carregada de forma autônoma pelo componente filho
});

const geoData = computed(() => {
  const data = cnpjData.value;
  if (!data || !localidades.value?.length) return null;

  // Primeiro tenta por id_ibge7, depois por município + UF
  if (data.id_ibge7) {
    const match = localidades.value.find((l) => l.id_ibge7 === data.id_ibge7);
    if (match) return match;
  }

  // Fallback: busca por nome do município e UF
  const municipio = data.municipio?.toUpperCase();
  const uf = data.uf?.toUpperCase();
  if (!municipio || !uf) return null;

  return (
    localidades.value.find(
      (l) =>
        l.no_municipio?.toUpperCase() === municipio &&
        l.sg_uf?.toUpperCase() === uf,
    ) ?? null
  );
});

const formatCnpj = (v) => {
  if (!v) return "—";
  const clean = v.replace(/\D/g, "");
  if (clean.length !== 14) return v;
  return clean.replace(
    /^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/,
    "$1.$2.$3/$4-$5",
  );
};
</script>

<template>
  <div class="cnpj-detail-page">
    <!-- BREADCRUMB -->
    <div class="breadcrumb">
      <span class="breadcrumb-link" @click="router.push('/cnpj')">
        <i class="pi pi-briefcase" />
        Análise CNPJ
      </span>
      <i class="pi pi-angle-right breadcrumb-sep" />
      <span class="breadcrumb-current">{{ cnpjData?.razao_social ?? cnpj }}</span>
    </div>

    <!-- HEADER (COMPONENTE ISOLADO) -->
    <CnpjDetailHeader :cnpj="cnpj" :cnpj-data="cnpjData" :geo-data="geoData" />

    <!-- TABS -->
    <TabView class="detail-tabs" :activeIndex="cnpjNav.activeTabIndex" @tab-change="cnpjNav.activeTabIndex = $event.index">
      <TabPanel>
        <template #header
          ><i class="pi pi-list tab-icon" /><span>Movimentação</span></template
        >
        <div class="tab-content tab-placeholder">
          <i class="pi pi-inbox placeholder-icon" />
          <p>Dados de movimentação serão exibidos aqui.</p>
        </div>
      </TabPanel>

      <TabPanel>
        <template #header
          ><i class="pi pi-chart-line tab-icon" /><span
            >Evolução Financeira</span
          ></template
        >
        <CnpjTabFinancialEvolution class="tab-content" />
      </TabPanel>

      <TabPanel>
        <template #header
          ><i class="pi pi-shield tab-icon" /><span>Indicadores</span></template
        >
        <CnpjTabIndicators class="tab-content" />
      </TabPanel>

      <TabPanel>
        <template #header
          ><i class="pi pi-id-card tab-icon" /><span
            >Análise de CRMs</span
          ></template
        >
        <CnpjTabPrescritores :cnpj="cnpj" class="tab-content" />
      </TabPanel>

      <TabPanel>
        <template #header
          ><i class="pi pi-exclamation-triangle tab-icon" /><span
            >Falecidos</span
          ></template
        >
        <CnpjTabFalecidos :cnpj="cnpj" class="tab-content" />
      </TabPanel>

      <TabPanel>
        <template #header
          ><i class="pi pi-map tab-icon" /><span
            >Região de Saúde</span
          ></template
        >
        <CnpjTabRegional :cnpj="cnpj" :geo-data="geoData" class="tab-content" />
      </TabPanel>
    </TabView>
  </div>
</template>

<style scoped>
.breadcrumb {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  font-size: 0.78rem;
  color: var(--text-muted);
}

.breadcrumb-link {
  display: flex;
  align-items: center;
  gap: 0.35rem;
  cursor: pointer;
  color: var(--primary-color);
  font-weight: 600;
  transition: opacity 0.15s ease;
}
.breadcrumb-link:hover { opacity: 0.75; }
.breadcrumb-link i { font-size: 0.75rem; }

.breadcrumb-sep { font-size: 0.65rem; opacity: 0.5; }

.breadcrumb-current {
  color: var(--text-muted);
  font-weight: 500;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  max-width: 400px;
}

.cnpj-detail-page {
  display: flex;
  flex-direction: column;
  height: 100%;
  overflow-y: auto;
  gap: 0.75rem; /* Ajustado para equilíbrio visual ideal */
  background: transparent;
}

/* ── CARD MESTRE DE DADOS (ABAS + CONTEÚDO UNIFICADOS - OPÇÃO B) ── */
.detail-tabs {
  flex: 1;
  display: flex;
  flex-direction: column;
  overflow: hidden;
  background: var(
    --tabs-bg
  ); /* O conteúdo técnico agora vive dentro deste grande card */
  border: 1px solid var(--tabs-border);
  border-radius: 12px;
  box-shadow: none;
  margin-bottom: 2rem;
}

/* Removemos a redundância de cards aninhados para um visual cleaner */
.detail-tabs :deep(.shadow-card) {
  border: none !important;
  box-shadow: none !important;
  background: transparent !important;
  padding: 0 !important;
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
  background: var(--tabs-bg) !important;
  border-bottom: 1px solid var(--tabs-border);
  padding: 0 1.25rem;
}

:deep(.p-tabview-nav li .p-tabview-nav-link) {
  background: var(--tabs-bg) !important;
  font-size: 0.82rem; /* Leve redução para maior equilíbrio */
  font-weight: 700;
  padding: 0.55rem 1.1rem; /* Mais compacto também no respiro horizontal */
  gap: 0.5rem;
  transition: all 0.2s;
  color: var(--text-secondary) !important;
  text-transform: uppercase !important;
  letter-spacing: 0.04em;
}

:deep(.p-tabview-nav li.p-highlight .p-tabview-nav-link) {
  border: none !important;
  box-shadow: none !important;
  outline: none !important;
  color: var(--primary-color) !important;
  font-weight: 700;
  background: color-mix(
    in srgb,
    var(--primary-color) 12%,
    transparent
  ) !important;
  position: relative;
}

/* O DESIGN FINAL DA CÁPSULA CARBON GOLD */
:deep(.p-tabview-nav li.p-highlight .p-tabview-nav-link::after) {
  content: "";
  position: absolute;
  bottom: 0;
  left: 20%; /* Centralizado e curto */
  width: 60%;
  height: 4px;
  background: var(--primary-color) !important;
  border-radius: 99px; /* Formato Pílula/Cápsula */
  box-shadow: 0 0 10px color-mix(in srgb, var(--primary-color) 50%, transparent);
  transition: all 0.3s ease;
}

.tab-icon {
  font-size: 0.8rem;
}

/* ── PLACEHOLDER E CONTEÚDO ──────────────────────────── */
.tab-content {
  padding: 1.5rem 2rem;
} /* Alinhado horizontalmente com o header */

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

.placeholder-icon {
  font-size: 3rem;
}
.tab-placeholder p {
  font-size: 0.875rem;
}
</style>
