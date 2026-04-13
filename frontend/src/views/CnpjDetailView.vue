<script setup>
import { useRoute } from "vue-router";
import { computed, onMounted, ref, watch } from "vue";
import { useAnalyticsStore } from "@/stores/analytics";
import { useCnpjDetailStore } from "@/stores/cnpjDetail";
import { useGeoStore } from "@/stores/geo";
import { useFilterStore } from "@/stores/filters";
import { useCnpjNavStore } from "@/stores/cnpjNav";
import { useRecentCnpjStore } from "@/stores/recentCnpj";
import { useRiskMetrics } from "@/composables/useRiskMetrics";
import { useFormatting } from "@/composables/useFormatting";
import { useFilterParameters } from "@/composables/useFilterParameters";
import CnpjHeader from "./components/cnpj/CnpjHeader.vue";
import EvolutionTab from "./components/cnpj/EvolutionTab.vue";
import IndicatorsTab from "./components/cnpj/IndicatorsTab.vue";
import MortalityTab from "./components/cnpj/MortalityTab.vue";
import RegionalTab from "./components/cnpj/RegionalTab.vue";
import CRMTab from "./components/cnpj/CRMTab.vue";
import MovementTab from "./components/cnpj/MovementTab.vue";
import RiskDiagnosisTab from "./components/cnpj/RiskDiagnosisTab.vue";
import { useChartTheme } from "@/config/chartTheme";
import { CHART_TOOLTIP_SHADOW } from "@/config/colors.js";
import { RISK_COLORS, RISK_THRESHOLDS } from "@/config/riskConfig";
import { storeToRefs } from "pinia";
import TabView from "primevue/tabview";
import TabPanel from "primevue/tabpanel";
import Tag from "primevue/tag";
import Chip from "primevue/chip";

// ── Índices das abas (evita números mágicos no template) ──
const TAB_INDEX = {
  EVOLUTION: 0,
  DIAGNOSIS: 1,
  MOVEMENT: 2,
  INDICATORS: 3,
  CRMS: 4,
  MORTALITY: 5,
  REGIONAL: 6,
};

const route = useRoute();
const cnpj = computed(() => route.params.cnpj);

// ── Stores ────────────────────────────────────────────────
const analyticsStore = useAnalyticsStore();
const cnpjDetailStore = useCnpjDetailStore();
const { resultadoCnpjs } = storeToRefs(analyticsStore);
const { dadosCadastro } = storeToRefs(cnpjDetailStore);

const geoStore = useGeoStore();
const { localidades } = storeToRefs(geoStore);

const cnpjNav = useCnpjNavStore();

// ── Composables ───────────────────────────────────────────
const { getApiParams } = useFilterParameters();
const { getRiskSeverity, getRiskLabel, getRiskColor, getRiskClass } =
  useRiskMetrics();
const { formatCurrencyFull, formatNumberFull, formatarData } = useFormatting();
const { chartTheme, chartDataColors, baseChartConfig } = useChartTheme();

import { usePdfExport } from "@/composables/usePdfExport";
const { isExporting, exportCnpjPdf } = usePdfExport();

const evolutionTabRef = ref(null);
const indicatorsTabRef = ref(null);
const crmsTabRef = ref(null);
const falecidosTabRef = ref(null);

const qtdMunicipiosRegiao = computed(
  () =>
    geoStore.qtdMunicipiosPorRegiao?.(geoData.value?.no_regiao_saude) ?? null,
);

const handleExport = async () => {
  // Garante que temos os dados de risco de todos os municípios da região
  const geo = geoData.value;
  if (geo?.sg_uf && geo?.no_regiao_saude) {
    const p = getApiParams();
    await cnpjDetailStore.fetchMunicipiosRegiao(
      geo.sg_uf,
      geo.no_regiao_saude,
      p.inicio,
      p.fim,
    );
  }

  exportCnpjPdf({
    cnpjData: cnpjData.value,
    geoData: geoData.value,
    cadastro: dadosCadastro.value,
    cnpj: cnpj.value,
    qtdMunicipiosRegiao: qtdMunicipiosRegiao.value,
    evolutionTabRef,
    indicatorsTabRef,
    crmsTabRef,
    falecidosTabRef,
    cnpjNavStore: cnpjNav,
    geoStore,
    resultadoMunicipios: cnpjDetailStore.municipiosRegiao,
    formatCurrencyFull,
    formatNumberFull,
    formatarData,
  });
};
// ── Composables (Fim) ─────────────────────────────────────

// ── Dados do CNPJ ─────────────────────────────────────────
const cnpjData = computed(
  () =>
    resultadoCnpjs.value?.find((c) => c.cnpj === cnpj.value) ??
    cnpjDetailStore.cnpjsAvulsos.get(cnpj.value) ??
    null,
);

watch(
  () => cnpj.value,
  async (newCnpj, oldCnpj) => {
    // Ao trocar de CNPJ, reseta tudo e dispara todos os fetches em paralelo
    if (newCnpj !== oldCnpj) {
      cnpjDetailStore.resetAll();
      cnpjNav.reset(TAB_INDEX.EVOLUTION);
    }
    if (newCnpj) {
      // Eager load: dispara todos os fetches ao carregar a página
      cnpjDetailStore.fetchDadosCadastro(newCnpj);
      cnpjDetailStore.fetchEvolucaoFinanceira(newCnpj);
      cnpjDetailStore.fetchMovimentacao(newCnpj);
      cnpjDetailStore.fetchIndicadores(newCnpj);
      cnpjDetailStore.fetchFalecidos(newCnpj);
      cnpjDetailStore.fetchPrescritores(newCnpj);
      if (!cnpjData.value) {
        const p = getApiParams();
        await cnpjDetailStore.fetchCnpjAvulso(newCnpj, p.inicio, p.fim);
      }
    }
  },
  { immediate: true },
);

// Watch auxilar para quando o cnpjData (e a UF) chegar via fetchCnpjAvulso
watch(
  () => cnpjData.value?.uf,
  (val) => {
    if (val) {
      cnpjDetailStore.fetchScorePercentiles('uf', val);
    }
  }
);

const recentCnpjStore = useRecentCnpjStore();

// Registra o CNPJ atual como recente assim que os dados estiverem disponíveis
watch(
  cnpjData,
  (data) => {
    if (data?.razao_social) {
      recentCnpjStore.set(cnpj.value, data.razao_social);
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
    <!-- HEADER (COMPONENTE ISOLADO) -->
    <CnpjHeader
      :cnpj="cnpj"
      :cnpj-data="cnpjData"
      :geo-data="geoData"
      :cadastro="dadosCadastro"
      :is-exporting="isExporting"
      @export="handleExport"
    />

    <!-- TABS -->
    <TabView
      class="detail-tabs"
      :activeIndex="cnpjNav.activeTabIndex"
      @tab-change="cnpjNav.activeTabIndex = $event.index"
    >
      <TabPanel>
        <template #header
          ><i class="pi pi-chart-line tab-icon" /><span
            >Evolução Financeira</span
          ></template
        >
        <EvolutionTab ref="evolutionTabRef" class="tab-content" />
      </TabPanel>

      <TabPanel>
        <template #header
          ><i class="pi pi-chart-bar tab-icon" /><span
            >Diagnóstico de Risco</span
          ></template
        >
        <RiskDiagnosisTab 
          :cnpj="cnpj"
          :cnpj-data="cnpjData"
          :geo-data="geoData"
          class="tab-content" 
        />
      </TabPanel>

      <TabPanel>
        <template #header
          ><i class="pi pi-list tab-icon" /><span>Movimentação</span></template
        >
        <MovementTab :cnpj="cnpj" class="tab-content" />
      </TabPanel>

      <TabPanel>
        <template #header
          ><i class="pi pi-shield tab-icon" /><span>Indicadores</span></template
        >
        <IndicatorsTab ref="indicatorsTabRef" class="tab-content" />
      </TabPanel>

      <TabPanel>
        <template #header
          ><i class="pi pi-id-card tab-icon" /><span
            >Análise de CRMs</span
          ></template
        >
        <CRMTab ref="crmsTabRef" :cnpj="cnpj" class="tab-content" />
      </TabPanel>

      <TabPanel>
        <template #header
          ><i class="pi pi-exclamation-triangle tab-icon" /><span
            >Falecidos</span
          ></template
        >
        <MortalityTab ref="falecidosTabRef" :cnpj="cnpj" class="tab-content" />
      </TabPanel>

      <TabPanel>
        <template #header
          ><i class="pi pi-map tab-icon" /><span
            >Região de Saúde</span
          ></template
        >
        <RegionalTab :cnpj="cnpj" :geo-data="geoData" :cnpj-data="cnpjData" class="tab-content" />
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
  gap: 0; /* Unificado: header + tabs formam um card único */
  background: transparent;
}

/* ── CARD MESTRE DE DADOS (ABAS + CONTEÚDO UNIFICADOS - OPÇÃO B) ── */
.detail-tabs {
  flex: 1;
  display: flex;
  flex-direction: column;
  overflow: hidden;
  background: var(--tabs-bg);
  border: 1px solid var(--tabs-border);
  border-top: none; /* Fundido com o header acima */
  border-radius: 0 0 12px 12px; /* Apenas cantos inferiores */
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
  overflow: hidden !important; /* Estabiliza o container para evitar flashes de scroll do pai */
  padding: 0;
  background: transparent !important;
}

/* ── ANIMAÇÃO DE ENTRADA DO CONTEÚDO (PADRÃO PREMIUM) ── */
:deep(.p-tabview-panel) {
  height: 100%;
  overflow-y: auto; /* Cada aba agora gerencia seu próprio scroll de forma isolada */
  background: transparent !important;
  animation: tabContentEntry 0.4s cubic-bezier(0.4, 0, 0.2, 1);
}

@keyframes tabContentEntry {
  from {
    opacity: 0;
    transform: translateY(15px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

:deep(.p-tabview-nav) {
  background: var(--establishment-header-bg) !important;
  border-top: 2px solid color-mix(in srgb, var(--primary-color) 40%, var(--tabs-border));
  border-bottom: 1px solid var(--tabs-border);
  padding: 0.75rem 1.25rem 0;
}

/* Reset de indicadores padrão do PrimeVue */
:deep(.p-tabview-ink-bar) {
  display: none !important;
}

:deep(.p-tabview-nav li) {
  border: none !important;
  background: transparent !important;
}

:deep(.p-tabview-nav li .p-tabview-nav-link) {
  background: transparent !important;
  font-size: 0.82rem;
  font-weight: 700;
  padding: 0.7rem 1.1rem !important;
  gap: 0.5rem;
  /* Transição cirúrgica: apenas no que importa, sem animar bordas (evita o flash) */
  transition: color 0.2s, background-color 0.2s;
  color: var(--text-secondary) !important;
  text-transform: uppercase !important;
  letter-spacing: 0.04em;
  border: none !important;
  border-bottom: 3px solid transparent !important;
  margin-bottom: -1px !important;
}

/* Estado Ativo Cirúrgico (Sem Linha Dupla e Sem Flash) */
:deep(.p-tabview-nav li.p-highlight .p-tabview-nav-link),
:deep(.p-tabview-nav li .p-tabview-nav-link[aria-selected="true"]) {
  background: color-mix(in srgb, var(--primary-color) 10%, transparent) !important;
  color: var(--primary-color) !important;
  position: relative;
  border: 0 !important;
  border-bottom: 3px solid transparent !important;
  border-width: 0 !important;
  box-shadow: none !important;
  outline: none !important;
  border-radius: 8px 8px 0 0;
  /* Garante que a transição de borda seja instantânea */
  transition: none !important;
}

:deep(.p-tabview-nav li .p-tabview-nav-link:focus),
:deep(.p-tabview-nav li .p-tabview-nav-link:active) {
  box-shadow: none !important;
  outline: none !important;
  border-bottom-color: transparent !important;
}

/* O INDICADOR: Pílula flutuante centralizada */
:deep(.p-tabview-nav li.p-highlight .p-tabview-nav-link::after) {
  content: "";
  position: absolute;
  bottom: 0px;
  left: 20%;
  width: 60%;
  height: 4px;
  background: var(--primary-color) !important;
  border-radius: 99px;
  box-shadow: 0 0 10px color-mix(in srgb, var(--primary-color) 50%, transparent);
  transition: all 0.3s ease;
}

.tab-icon {
  font-size: 0.8rem;
}

/* ── PLACEHOLDER E CONTEÚDO ──────────────────────────── */
:deep(.p-tabview-panels) {
  padding: 0 !important;
  background: transparent !important;
}

.tab-content {
  padding: 2rem;
  min-height: calc(100vh - 450px); /* Garante que a aba tenha uma altura mínima respeitável */
}

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

<style>
/* Estado de erro nos tabs — não-scoped para alcançar componentes filhos */
.tab-placeholder--error .placeholder-icon,
.tab-placeholder--error i {
  color: var(--red-400, #f87171) !important;
}
.tab-placeholder--error p {
  color: var(--text-color);
  opacity: 0.75;
}
</style>
