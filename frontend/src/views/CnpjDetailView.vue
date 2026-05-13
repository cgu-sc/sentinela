<script setup>
import { useRoute, useRouter } from "vue-router";
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
import FinancialMovementTab from "./components/cnpj/FinancialMovementTab.vue";
import IndicatorsTab from "./components/cnpj/IndicatorsTab.vue";
import MortalityTab from "./components/cnpj/MortalityTab.vue";
import RegionalTab from "./components/cnpj/RegionalTab.vue";
import CRMTab from "./components/cnpj/CRMTab.vue";
import CalculationMemoryTab from "./components/cnpj/CalculationMemoryTab.vue";
import RiskDiagnosisTab from "./components/cnpj/RiskDiagnosisTab.vue";
import SociosTab from "./components/cnpj/SociosTab.vue";
import NetworkTab from "./components/cnpj/NetworkTab.vue";
import { useChartTheme } from "@/config/chartTheme";
import { CHART_TOOLTIP_SHADOW } from "@/config/colors.js";
import { RISK_COLORS, RISK_THRESHOLDS } from "@/config/riskConfig";
import { storeToRefs } from "pinia";
import TabView from "primevue/tabview";
import TabPanel from "primevue/tabpanel";
import Tag from "primevue/tag";
import Chip from "primevue/chip";
import ProgressSpinner from "primevue/progressspinner";
import { useToast } from "primevue/usetoast";
import { API_ENDPOINTS } from "@/config/api";

// ── Índices das abas (evita números mágicos no template) ──
const TAB_INDEX = {
  EVOLUTION: 0,
  DIAGNOSIS: 1,
  MOVEMENT: 2,
  INDICATORS: 3,
  CRMS: 4,
  MORTALITY: 5,
  SOCIOS: 6,
  NETWORK: 7,
  REGIONAL: 8,
};

const route = useRoute();
const router = useRouter();
const normalizeCnpj = (value) => String(value ?? "").replace(/\D/g, "");
const cnpj = computed(() => normalizeCnpj(route.params.cnpj));

// ── Stores ────────────────────────────────────────────────
const analyticsStore = useAnalyticsStore();
const cnpjDetailStore = useCnpjDetailStore();
const { resultadoCnpjs } = storeToRefs(analyticsStore);
const { dadosCadastro, evolucaoFinanceira, evolucaoLoading } =
  storeToRefs(cnpjDetailStore);

const geoStore = useGeoStore();
const { localidades } = storeToRefs(geoStore);

const filterStore = useFilterStore();
const cnpjNav = useCnpjNavStore();

// ── Composables ───────────────────────────────────────────
const { getApiParams } = useFilterParameters();
const { getRiskSeverity, getRiskLabel, getRiskColor, getRiskClass } =
  useRiskMetrics();
const { formatCurrencyFull, formatNumberFull, formatarData } = useFormatting();
const { chartTheme, chartDataColors, baseChartConfig } = useChartTheme();
const toast = useToast();

import { usePdfExport } from "@/composables/usePdfExport";
const { isExporting, exportCnpjPdf } = usePdfExport();

const financialMovementTabRef = ref(null);
const indicatorsTabRef = ref(null);
const crmsTabRef = ref(null);
const falecidosTabRef = ref(null);

const qtdMunicipiosRegiao = computed(
  () =>
    geoStore.qtdMunicipiosPorRegiao?.(geoData.value?.id_regiao_saude) ?? null,
);

const handleExport = async () => {
  // Garante que temos os dados de risco de todos os municípios da região
  const geo = geoData.value;
  if (geo?.sg_uf && geo?.id_regiao_saude) {
    const p = getApiParams();
    await cnpjDetailStore.fetchMunicipiosRegiao(
      geo.sg_uf,
      geo.id_regiao_saude,
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
    financialMovementTabRef,
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
const isGeneratingNote = ref(false);
const handleGenerateNote = async () => {
  const { inicio, fim } = getApiParams();
  const url = `${API_ENDPOINTS.analyticsNotaTecnica(cnpj.value)}?data_inicio=${inicio}&data_fim=${fim}`;

  try {
    isGeneratingNote.value = true;

    // Baixa o arquivo como blob para não sair da página
    const response = await fetch(url);
    if (!response.ok) throw new Error("Erro ao gerar nota técnica");

    const blob = await response.blob();
    const blobUrl = window.URL.createObjectURL(blob);

    // Cria um link temporário para o download
    const link = document.createElement("a");
    link.href = blobUrl;
    link.setAttribute("download", `Nota_Tecnica_${cnpj.value}.docx`);
    document.body.appendChild(link);
    link.click();

    // Cleanup
    document.body.removeChild(link);
    window.URL.revokeObjectURL(blobUrl);
  } catch (error) {
    console.error("Erro ao gerar Nota Técnica:", error);
    toast.add({
      severity: "error",
      summary: "Erro ao gerar Nota Técnica",
      detail: "Não foi possível gerar o arquivo. Tente novamente em instantes.",
      life: 5000,
    });
  } finally {
    isGeneratingNote.value = false;
  }
};
// ── Composables (Fim) ─────────────────────────────────────

// ── Dados do CNPJ ─────────────────────────────────────────
const cnpjData = computed(
  () =>
    resultadoCnpjs.value?.find((c) => c.cnpj === cnpj.value) ??
    cnpjDetailStore.cnpjsAvulsos.get(cnpj.value) ??
    null,
);

// Totais calculados a partir dos semestres da evolução financeira —
// refletem exatamente o período de análise selecionado (incluindo semestres parciais).
// Substitui valSemComp/totalMov do cnpjData quando disponível.
const periodSummary = computed(() => {
  const semestres = evolucaoFinanceira.value?.semestres;
  if (!semestres?.length) return null;
  const totalMov = semestres.reduce((a, s) => a + s.total, 0);
  const valSemComp = semestres.reduce((a, s) => a + s.irregular, 0);
  const percValSemComp = totalMov > 0 ? (valSemComp / totalMov) * 100 : 0;
  return { totalMov, valSemComp, percValSemComp };
});

const hasCnpjAccessIssue = computed(() =>
  ["invalid_format", "not_in_program", "error"].includes(
    cnpjDetailStore.cnpjAccessStatus,
  ),
);

const canRenderDetail = computed(
  () => cnpjDetailStore.cnpjAccessStatus === "valid",
);

const accessState = computed(() => {
  const status = cnpjDetailStore.cnpjAccessStatus;
  if (status === "invalid_format") {
    return {
      icon: "pi pi-id-card",
      badge: "Formato invalido",
      title: "Identificador invalido",
      description: "A rota recebeu um identificador que nao possui 14 digitos. A tela de estabelecimento aceita apenas CNPJ completo.",
      severity: "warning",
    };
  }
  if (status === "not_in_program") {
    return {
      icon: "pi pi-search",
      badge: "Fora da base PFPB",
      title: "CNPJ nao encontrado no Farmacia Popular",
      description: "O CNPJ informado tem formato valido, mas nao consta na base carregada do Programa Farmacia Popular.",
      severity: "warning",
    };
  }
  return {
    icon: "pi pi-exclamation-triangle",
    badge: "Servico indisponivel",
    title: "Validacao indisponivel",
    description: "Nao foi possivel consultar a base de estabelecimentos neste momento.",
    severity: "error",
  };
});

const goToEstablishments = () => {
  router.push("/estabelecimentos");
};

let cnpjValidationRequest = 0;

watch(
  () => cnpj.value,
  async (newCnpj, oldCnpj) => {
    // Ao trocar de CNPJ, reseta tudo e dispara todos os fetches em paralelo
    if (newCnpj !== oldCnpj) {
      cnpjDetailStore.resetAll();
      cnpjNav.reset(TAB_INDEX.EVOLUTION);
    }
    const requestId = ++cnpjValidationRequest;
    if (!newCnpj) {
      cnpjDetailStore.setInvalidCnpjFormat(newCnpj);
      return;
    }

    const access = await cnpjDetailStore.validateCnpjAccess(newCnpj);
    if (requestId !== cnpjValidationRequest || cnpj.value !== newCnpj) return;
    if (access?.status !== "valid") return;

    if (newCnpj) {
      // Eager load: dispara todos os fetches ao carregar a página
      const { inicio, fim } = getApiParams();
      cnpjDetailStore.fetchDadosCadastro(newCnpj);
      cnpjDetailStore.fetchEvolucaoFinanceira(newCnpj, inicio, fim);
      cnpjDetailStore.fetchEvolucaoMensalGtin(newCnpj, inicio, fim);
      cnpjDetailStore.fetchMovimentacao(newCnpj);
      cnpjDetailStore.fetchIndicadores(newCnpj);
      cnpjDetailStore.fetchFalecidos(newCnpj, inicio, fim);
      cnpjDetailStore.fetchCrmData(newCnpj, inicio, fim);
      cnpjDetailStore.fetchCrmPerfilDiario(newCnpj, inicio, fim);
      cnpjDetailStore.fetchCrmPerfilHorario(newCnpj, inicio, fim);
      cnpjDetailStore.fetchSocios(newCnpj);
      cnpjDetailStore.fetchNetwork(newCnpj);
      if (!cnpjData.value) {
        const p = getApiParams();
        await cnpjDetailStore.fetchCnpjAvulso(newCnpj, p.inicio, p.fim);
      }
    }
  },
  { immediate: true },
);

// Re-fetch quando o período de análise muda
watch(
  () => filterStore.periodo,
  () => {
    if (!cnpj.value) return;
    if (cnpjDetailStore.cnpjAccessStatus !== "valid") return;
    if (filterStore.isAnimating) return;
    const { inicio, fim } = getApiParams();
    cnpjDetailStore.fetchEvolucaoFinanceira(cnpj.value, inicio, fim);
    cnpjDetailStore.fetchEvolucaoMensalGtin(cnpj.value, inicio, fim);
    cnpjDetailStore.fetchFalecidos(cnpj.value, inicio, fim);
    cnpjDetailStore.fetchCrmData(cnpj.value, inicio, fim);
    cnpjDetailStore.fetchCrmPerfilDiario(cnpj.value, inicio, fim);
    cnpjDetailStore.fetchCrmPerfilHorario(cnpj.value, inicio, fim);
  },
  { deep: true },
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
  // Movimentação Financeira agora é carregada de forma autônoma pelo componente filho
});

const geoData = computed(() => {
  const data = cnpjData.value;
  if (!data || !localidades.value?.length) return null;

  if (!data.id_ibge7) return null;
  return localidades.value.find((l) => String(l.id_ibge7) === String(data.id_ibge7)) ?? null;
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

// ── Controle de Carregamento Global ───────────────────────
const isInitialLoading = computed(() => {
  // Consideramos carregamento inicial se os dados básicos ou os dashboards principais ainda não voltaram
  return (
    cnpjDetailStore.cnpjAccessStatus === "checking" ||
    cnpjDetailStore.dadosCadastroLoading ||
    cnpjDetailStore.cnpjsAvulsosLoading ||
    (cnpjDetailStore.prescritoresLoading &&
      !cnpjDetailStore.prescritoresData) ||
    (cnpjDetailStore.crmPerfilDiarioLoading &&
      !cnpjDetailStore.crmPerfilDiario) ||
    (cnpjDetailStore.evolucaoLoading && !cnpjDetailStore.evolucaoFinanceira)
  );
});
</script>

<template>
  <div class="cnpj-detail-page">
    <!-- OVERLAY DE CARREGAMENTO GLOBAL -->
    <Transition name="fade-blur">
      <div v-if="isInitialLoading" class="global-loading-overlay">
        <div class="loader-content">
          <ProgressSpinner
            style="width: 64px; height: 64px"
            strokeWidth="3"
            animationDuration=".8s"
          />
          <div class="loader-text">
            <h3>Sincronizando Dados</h3>
            <p>Buscando indicadores e perfil cronológico...</p>
          </div>
        </div>
      </div>
    </Transition>

    <section
      v-if="hasCnpjAccessIssue"
      class="cnpj-access-state"
      :class="`cnpj-access-state--${accessState.severity}`"
    >
      <div class="access-state-glow" />
      <div class="access-state-icon">
        <i :class="accessState.icon" />
      </div>
      <div class="access-state-copy">
        <div class="access-state-meta">
          <p class="access-state-kicker">Consulta de estabelecimento</p>
          <span class="access-state-badge">{{ accessState.badge }}</span>
        </div>
        <h2>{{ accessState.title }}</h2>
        <p>{{ accessState.description }}</p>
        <div v-if="cnpjDetailStore.cnpjAccessCnpj" class="access-state-query">
          <span>CNPJ pesquisado</span>
          <strong>{{ formatCnpj(cnpjDetailStore.cnpjAccessCnpj) }}</strong>
        </div>
      </div>
      <button class="access-state-action" type="button" @click="goToEstablishments">
        <i class="pi pi-arrow-left" />
        <span>Voltar para estabelecimentos</span>
      </button>
    </section>

    <!-- HEADER (COMPONENTE ISOLADO) -->
    <CnpjHeader
      v-if="canRenderDetail"
      :cnpj="cnpj"
      :cnpj-data="cnpjData"
      :geo-data="geoData"
      :cadastro="dadosCadastro"
      :is-exporting="isExporting"
      :is-generating-note="isGeneratingNote"
      :period-summary="periodSummary"
      :period-loading="evolucaoLoading"
      @export="handleExport"
      @generate-note="handleGenerateNote"
    />

    <!-- TABS -->
    <TabView
      v-if="canRenderDetail"
      class="detail-tabs"
      :activeIndex="cnpjNav.activeTabIndex"
      @tab-change="cnpjNav.activeTabIndex = $event.index"
    >
      <TabPanel>
        <template #header
          ><i class="pi pi-chart-line tab-icon" /><span
            >Movimentação Financeira</span
          ></template
        >
        <FinancialMovementTab
          ref="financialMovementTabRef"
          class="tab-content"
        />
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
          :period-summary="periodSummary"
          :period-loading="evolucaoLoading"
          :is-active="cnpjNav.activeTabIndex === 1"
          class="tab-content"
        />
      </TabPanel>

      <TabPanel>
        <template #header
          ><i class="pi pi-list tab-icon" /><span
            >Memória de Cálculo</span
          ></template
        >
        <CalculationMemoryTab :cnpj="cnpj" class="tab-content" />
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
            >Análise de Autorizações</span
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
          ><i class="pi pi-users tab-icon" /><span
            >Quadro Societário</span
          ></template
        >
        <SociosTab class="tab-content" />
      </TabPanel>

      <TabPanel>
        <template #header>
          <i class="pi pi-share-alt tab-icon" /><span>Teia Societária</span>
        </template>
        <KeepAlive>
          <NetworkTab
            v-if="cnpjNav.activeTabIndex === TAB_INDEX.NETWORK"
            class="tab-content"
          />
        </KeepAlive>
      </TabPanel>

      <TabPanel>
        <template #header>
          <i class="pi pi-map tab-icon" /><span>Região de Saúde</span>
        </template>
        <RegionalTab
          :cnpj="cnpj"
          :geo-data="geoData"
          :cnpj-data="cnpjData"
          :is-active="cnpjNav.activeTabIndex === TAB_INDEX.REGIONAL"
          class="tab-content"
        />
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
  position: relative; /* Referência para o overlay de loading */
  gap: 0;
  background: transparent;
}

/* Estado de acesso da rota do estabelecimento */
.cnpj-access-state {
  --access-accent: var(--primary-color);
  --access-accent-strong: var(--primary-color);
  --access-glass-highlight: color-mix(in srgb, var(--text-color) 6%, transparent);
  --access-soft-shadow: color-mix(in srgb, var(--text-color) 8%, transparent);
  min-height: 22rem;
  margin: 1rem 0 2rem;
  padding: 3rem 3.5rem;
  border: 1px solid color-mix(in srgb, var(--tabs-border) 72%, var(--text-color) 8%);
  border-radius: 14px;
  background:
    linear-gradient(
      135deg,
      color-mix(in srgb, var(--card-bg) 94%, var(--primary-color) 2%),
      color-mix(in srgb, var(--card-bg) 96%, transparent)
    );
  backdrop-filter: blur(8px);
  -webkit-backdrop-filter: blur(8px);
  box-shadow:
    0 12px 34px var(--access-soft-shadow),
    inset 0 1px 0 var(--access-glass-highlight);
  display: grid;
  grid-template-columns: auto minmax(0, 1fr) auto;
  align-items: center;
  gap: 2rem;
  overflow: hidden;
  position: relative;
  isolation: isolate;
}

.access-state-glow {
  position: absolute;
  inset: -35% auto auto -8%;
  width: 22rem;
  height: 22rem;
  border-radius: 999px;
  background: radial-gradient(
    circle,
    color-mix(in srgb, var(--primary-color) 8%, transparent) 0%,
    transparent 66%
  );
  opacity: 0.45;
  pointer-events: none;
  z-index: -1;
}

.cnpj-access-state--warning {
  --access-accent: var(--amber-500);
  --access-accent-strong: color-mix(in srgb, var(--amber-500) 78%, var(--text-color));
}

.cnpj-access-state--error {
  --access-accent: var(--color-error);
  --access-accent-strong: color-mix(in srgb, var(--color-error) 82%, var(--text-color));
}

.access-state-icon {
  width: 4.5rem;
  height: 4.5rem;
  border-radius: 14px;
  display: grid;
  place-items: center;
  background:
    linear-gradient(
      145deg,
      color-mix(in srgb, var(--access-accent) 11%, var(--card-bg)),
      color-mix(in srgb, var(--access-accent) 4%, transparent)
    );
  border: 1px solid color-mix(in srgb, var(--access-accent) 20%, var(--tabs-border));
  color: var(--access-accent-strong);
  font-size: 1.75rem;
  box-shadow: inset 0 1px 0 var(--access-glass-highlight);
}

.cnpj-access-state--warning .access-state-icon {
  --access-accent: var(--amber-500);
  --access-accent-strong: color-mix(in srgb, var(--amber-500) 78%, var(--text-color));
  background:
    linear-gradient(
      145deg,
      color-mix(in srgb, var(--access-accent) 11%, var(--card-bg)),
      color-mix(in srgb, var(--access-accent) 4%, transparent)
    );
  border-color: color-mix(in srgb, var(--access-accent) 22%, var(--tabs-border));
  color: var(--access-accent-strong);
}

.cnpj-access-state--error .access-state-icon {
  --access-accent: var(--color-error);
  --access-accent-strong: color-mix(in srgb, var(--color-error) 82%, var(--text-color));
  background:
    linear-gradient(
      145deg,
      color-mix(in srgb, var(--access-accent) 11%, var(--card-bg)),
      color-mix(in srgb, var(--access-accent) 4%, transparent)
    );
  border-color: color-mix(in srgb, var(--access-accent) 22%, var(--tabs-border));
  color: var(--access-accent-strong);
}

.access-state-copy {
  min-width: 0;
  max-width: 58rem;
}

.access-state-meta {
  display: flex;
  align-items: center;
  gap: 0.85rem;
  margin-bottom: 0.65rem;
}

.access-state-kicker {
  margin: 0;
  color: var(--text-muted);
  font-size: 0.75rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.08em;
}

.access-state-badge {
  height: 1.65rem;
  padding: 0 0.65rem;
  border-radius: 999px;
  border: 1px solid color-mix(in srgb, var(--access-accent) 28%, transparent);
  background: color-mix(in srgb, var(--access-accent) 7%, transparent);
  color: var(--text-secondary);
  display: inline-flex;
  align-items: center;
  font-size: 0.72rem;
  font-weight: 800;
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

.cnpj-access-state--error .access-state-badge {
  border-color: color-mix(in srgb, var(--access-accent) 28%, transparent);
  background: color-mix(in srgb, var(--access-accent) 7%, transparent);
  color: var(--text-secondary);
}

.access-state-copy h2 {
  margin: 0;
  color: color-mix(in srgb, var(--text-color) 85%, transparent);
  font-size: 2.05rem;
  font-weight: 800;
  letter-spacing: 0;
}

.access-state-copy p:not(.access-state-kicker) {
  max-width: 46rem;
  margin: 0.65rem 0 0;
  color: var(--text-secondary);
  font-size: 0.98rem;
  line-height: 1.65;
}

.access-state-query {
  display: inline-flex;
  align-items: center;
  gap: 0.85rem;
  margin-top: 1rem;
}

.access-state-query span {
  color: var(--text-muted);
  font-size: 0.72rem;
  font-weight: 800;
  text-transform: uppercase;
  letter-spacing: 0.06em;
}

.access-state-query strong {
  color: color-mix(in srgb, var(--text-color) 85%, transparent);
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", monospace;
  font-size: 0.92rem;
  font-weight: 800;
  letter-spacing: 0;
}

.access-state-action {
  height: 2.75rem;
  padding: 0 1rem;
  border: 1px solid color-mix(in srgb, var(--primary-color) 22%, var(--tabs-border));
  border-radius: 10px;
  background:
    linear-gradient(
      180deg,
      color-mix(in srgb, var(--primary-color) 8%, var(--card-bg)),
      color-mix(in srgb, var(--primary-color) 4%, transparent)
    );
  color: color-mix(in srgb, var(--text-color) 85%, transparent);
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 0.5rem;
  font-weight: 700;
  cursor: pointer;
  white-space: nowrap;
  box-shadow: inset 0 1px 0 var(--access-glass-highlight);
}

.access-state-action i {
  color: var(--primary-color);
}

.access-state-action:hover {
  transform: translateY(-1px);
  background:
    linear-gradient(
      180deg,
      color-mix(in srgb, var(--primary-color) 10%, var(--card-bg)),
      color-mix(in srgb, var(--primary-color) 5%, transparent)
    );
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
  border-top: 3px solid
    color-mix(in srgb, var(--primary-color) 40%, var(--tabs-border));
  border-bottom: 1px solid var(--tabs-border);
  padding: 0.5rem 1.25rem 0;
  display: flex;
  flex-wrap: nowrap;
  min-width: max-content;
}

:deep(.p-tabview-nav-container),
:deep(.p-tabview-nav-content) {
  overflow-x: auto !important;
  overflow-y: hidden !important;
  scrollbar-width: thin;
  scrollbar-color: color-mix(in srgb, var(--text-secondary) 45%, transparent)
    transparent;
}

:deep(.p-tabview-nav-container::-webkit-scrollbar),
:deep(.p-tabview-nav-content::-webkit-scrollbar) {
  height: 6px;
}

:deep(.p-tabview-nav-container::-webkit-scrollbar-track),
:deep(.p-tabview-nav-content::-webkit-scrollbar-track) {
  background: transparent;
}

:deep(.p-tabview-nav-container::-webkit-scrollbar-thumb),
:deep(.p-tabview-nav-content::-webkit-scrollbar-thumb) {
  background: color-mix(in srgb, var(--text-secondary) 35%, transparent);
  border-radius: 999px;
}

/* Reset de indicadores padrão do PrimeVue */
:deep(.p-tabview-ink-bar) {
  display: none !important;
}

:deep(.p-tabview-nav li) {
  border: none !important;
  background: transparent !important;
  flex: 0 0 auto;
}

:deep(.p-tabview-nav li .p-tabview-nav-link) {
  background: transparent !important;
  font-size: 0.75rem;
  font-weight: 700;
  min-width: 9.5rem;
  min-height: 2.75rem;
  padding: 0.35rem 1rem !important;
  gap: 0.5rem;
  align-items: center;
  justify-content: center;
  /* Transição cirúrgica: apenas no que importa, sem animar bordas (evita o flash) */
  transition:
    color 0.2s,
    background-color 0.2s;
  color: var(--text-secondary) !important;
  text-transform: uppercase !important;
  letter-spacing: 0.04em;
  border: none !important;
  border-bottom: 3px solid transparent !important;
  margin-bottom: -1px !important;
}

:deep(.p-tabview-nav li .p-tabview-nav-link span) {
  display: inline-block;
  line-height: 1.1;
  text-align: left;
  white-space: normal;
  max-width: 7.25rem;
}

/* Estado Ativo Cirúrgico (Sem Linha Dupla e Sem Flash) */
:deep(.p-tabview-nav li.p-highlight .p-tabview-nav-link),
:deep(.p-tabview-nav li .p-tabview-nav-link[aria-selected="true"]) {
  background: color-mix(
    in srgb,
    var(--primary-color) 10%,
    transparent
  ) !important;
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
  padding: 1rem;
  min-height: calc(
    100vh - 450px
  ); /* Garante que a aba tenha uma altura mínima respeitável */
}

/* ── GLOBAL LOADING OVERLAY (PREMIUM & ESTÁVEL) ── */
.global-loading-overlay {
  position: fixed;
  inset: 0;
  z-index: 9999;
  background: color-mix(in srgb, var(--body-bg) 75%, transparent);
  backdrop-filter: blur(10px);
  -webkit-backdrop-filter: blur(10px);
  display: flex;
  align-items: center;
  justify-content: center;
  pointer-events: all;

  /* Ajuste de contexto de layout: compensa sidebar e navbar */
  padding-left: var(--sidebar-width, 280px);
  padding-top: 56px;

  /* Sincronização com as transições do layout global */
  transition:
    padding-left 0.35s cubic-bezier(0.4, 0, 0.2, 1),
    opacity 0.4s ease;
}

.loader-content {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 1.5rem;
  text-align: center;
}

.loader-text h3 {
  margin: 0;
  font-size: 1.25rem;
  font-weight: 700;
  color: var(--primary-color);
  letter-spacing: -0.01em;
}

.loader-text p {
  margin: 0.25rem 0 0;
  font-size: 0.9rem;
  color: var(--text-muted);
}

/* Transição suave */
.fade-blur-enter-active,
.fade-blur-leave-active {
  transition:
    opacity 0.5s ease,
    backdrop-filter 0.5s ease;
}

.fade-blur-enter-from,
.fade-blur-leave-to {
  opacity: 0;
  backdrop-filter: blur(0px);
  -webkit-backdrop-filter: blur(0px);
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
