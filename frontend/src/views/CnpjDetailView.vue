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
  MOVEMENT: 0,
  EVOLUTION: 1,
  INDICATORS: 2,
  CRMS: 3,
  MORTALITY: 4,
  REGIONAL: 5,
};

const route = useRoute();
const cnpj = computed(() => route.params.cnpj);

// Só monta CnpjTabRegional quando a aba for ativada pela primeira vez,
// evitando que o ECharts tente inicializar dentro de um painel oculto (display:none).
const regionalTabMounted = ref(false);

// ── Stores ────────────────────────────────────────────────
const analyticsStore  = useAnalyticsStore();
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

import { usePdfExport } from '@/composables/usePdfExport';
const { isExporting, exportCnpjPdf } = usePdfExport();

const evolutionTabRef = ref(null);
const indicatorsTabRef = ref(null);
const crmsTabRef = ref(null);
const falecidosTabRef = ref(null);

const qtdMunicipiosRegiao = computed(() =>
  geoStore.qtdMunicipiosPorRegiao?.(geoData.value?.no_regiao_saude) ?? null,
);

const handleExport = async () => {
  // Garante que temos os dados de risco de todos os municípios da região
  const geo = geoData.value;
  if (geo?.sg_uf && geo?.no_regiao_saude) {
    const p = getApiParams();
    await cnpjDetailStore.fetchMunicipiosRegiao(geo.sg_uf, geo.no_regiao_saude, p.inicio, p.fim);
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

// Ativa o mount de CnpjTabRegional na primeira vez que a aba for aberta
watch(() => cnpjNav.activeTabIndex, (idx) => {
  if (idx === TAB_INDEX.REGIONAL) regionalTabMounted.value = true;
}, { immediate: true });

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


const recentCnpjStore = useRecentCnpjStore();

// Registra o CNPJ atual como recente assim que os dados estiverem disponíveis
watch(cnpjData, (data) => {
  if (data?.razao_social) {
    recentCnpjStore.set(cnpj.value, data.razao_social);
  }
}, { immediate: true });

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
    <CnpjHeader :cnpj="cnpj" :cnpj-data="cnpjData" :geo-data="geoData" :cadastro="dadosCadastro" :is-exporting="isExporting" @export="handleExport" />

    <!-- TABS -->
    <TabView class="detail-tabs" :activeIndex="cnpjNav.activeTabIndex" @tab-change="cnpjNav.activeTabIndex = $event.index">
      <TabPanel>
        <template #header
          ><i class="pi pi-list tab-icon" /><span>Movimentação</span></template
        >
        <MovementTab :cnpj="cnpj" class="tab-content" />
      </TabPanel>

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
        <RegionalTab v-if="regionalTabMounted" :cnpj="cnpj" :geo-data="geoData" class="tab-content" />
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
  background: var(--tabs-bg) !important;
  border-bottom: 1px solid var(--tabs-border);
  padding: 0 1.25rem;
}

:deep(.p-tabview-nav li .p-tabview-nav-link) {
  background: var(--tabs-bg) !important;
  font-size: 0.82rem;
  font-weight: 700;
  padding: 0.7rem 1.1rem !important; /* Padding fixo e aumentado para respiro */
  gap: 0.5rem;
  transition: all 0.2s;
  color: var(--text-secondary) !important;
  text-transform: uppercase !important;
  letter-spacing: 0.04em;
  border-bottom: 3px solid transparent !important; /* Espaço reservado para a "pílula" */
  margin-bottom: -1px; /* Compensa o border-bottom do nav */
}

:deep(.p-tabview-nav li.p-highlight .p-tabview-nav-link) {
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
  border-bottom-color: transparent !important; /* Mantém o border mas transparente */
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
