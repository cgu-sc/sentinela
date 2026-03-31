<script setup>
import { useRoute, useRouter } from 'vue-router';
import { computed, onMounted, ref } from 'vue';
import { useAnalyticsStore } from '@/stores/analytics';
import { useGeoStore } from '@/stores/geo';
import { useFilterStore } from '@/stores/filters';
import { useRiskMetrics } from '@/composables/useRiskMetrics';
import { useFormatting } from '@/composables/useFormatting';
import { useRegional } from '@/composables/useRegional';
import { useFilterParameters } from '@/composables/useFilterParameters';
import CnpjDetailHeader from './components/cnpj/CnpjDetailHeader.vue';
import CnpjTabFinancialEvolution from './components/cnpj/CnpjTabFinancialEvolution.vue';
import CnpjTabIndicators from './components/cnpj/CnpjTabIndicators.vue';
import CnpjTabFalecidos from './components/cnpj/CnpjTabFalecidos.vue';
import RegionalMunicipalityTable from './components/RegionalMunicipalityTable.vue';
import RegionalPharmacyTable from './components/RegionalPharmacyTable.vue';
import { useChartTheme } from '@/config/chartTheme';
import { CHART_TOOLTIP_SHADOW } from '@/config/colors.js';
import { RISK_COLORS, RISK_THRESHOLDS } from '@/config/riskConfig';
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
      @tab-change="(e) => {
        console.log('🔄 Tab change event:', e.index);
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

/* ── REGIÃO DE SAÚDE ─────────────────────────────────── */
.regional-tab {
  display: flex;
  flex-direction: column;
  gap: 1rem;
  padding: 1.25rem 0;
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
