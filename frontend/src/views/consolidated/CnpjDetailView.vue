<script setup>
import { useRoute, useRouter } from 'vue-router';
import { computed } from 'vue';
import { useAnalyticsStore } from '@/stores/analytics';
import { useGeoStore } from '@/stores/geo';
import { useRiskMetrics } from '@/composables/useRiskMetrics';
import { storeToRefs } from 'pinia';
import TabView from 'primevue/tabview';
import TabPanel from 'primevue/tabpanel';
import Button from 'primevue/button';
import Tag from 'primevue/tag';

const route  = useRoute();
const router = useRouter();
const cnpj   = computed(() => route.params.cnpj);

const analyticsStore = useAnalyticsStore();
const { resultadoCnpjs } = storeToRefs(analyticsStore);
const { getRiskSeverity, getRiskLabel } = useRiskMetrics();

const geoStore = useGeoStore();
const { localidades } = storeToRefs(geoStore);

// Busca os dados básicos do CNPJ já carregados no store
const cnpjData = computed(() =>
  resultadoCnpjs.value?.find(c => c.cnpj === cnpj.value) ?? null
);

// Cruza id_ibge7 com localidades para obter dados geográficos completos
const geoData = computed(() => {
  const ibge7 = cnpjData.value?.id_ibge7;
  if (!ibge7 || !localidades.value?.length) return null;
  return localidades.value.find(l => l.id_ibge7 === ibge7) ?? null;
});

const risco = computed(() => cnpjData.value?.percValSemComp ?? 0);

const formatCurrency = (value) => {
  if (value == null) return '—';
  return new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL', maximumFractionDigits: 0 }).format(value);
};

const formatPopulacao = (value) => {
  if (value == null) return '—';
  return new Intl.NumberFormat('pt-BR').format(value) + ' hab.';
};
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
          {{ geoData?.no_municipio ?? cnpjData.municipio }} · {{ geoData?.sg_uf ?? cnpjData.uf }}
          <span v-if="geoData?.no_regiao_saude" class="localidade-sep">|</span>
          <span v-if="geoData?.no_regiao_saude">{{ geoData.no_regiao_saude }}</span>
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
          <span class="mini-kpi-label">% S/ Comprovação</span>
          <span class="mini-kpi-value risk-value">{{ cnpjData.percValSemComp?.toFixed(1) }}%</span>
        </div>
        <div class="mini-kpi">
          <span class="mini-kpi-label">Valor S/ Comp.</span>
          <span class="mini-kpi-value">{{ formatCurrency(cnpjData.valSemComp) }}</span>
        </div>
        <div class="mini-kpi">
          <span class="mini-kpi-label">Total Movimentado</span>
          <span class="mini-kpi-value">{{ formatCurrency(cnpjData.totalMov) }}</span>
        </div>
      </div>
    </div>

    <!-- TABS -->
    <TabView class="detail-tabs">

      <TabPanel>
        <template #header>
          <i class="pi pi-list tab-icon" />
          <span>Movimentação</span>
        </template>
        <div class="tab-content tab-placeholder">
          <i class="pi pi-inbox placeholder-icon" />
          <p>Dados de movimentação serão exibidos aqui.</p>
        </div>
      </TabPanel>

      <TabPanel>
        <template #header>
          <i class="pi pi-chart-line tab-icon" />
          <span>Evolução Financeira</span>
        </template>
        <div class="tab-content tab-placeholder">
          <i class="pi pi-chart-bar placeholder-icon" />
          <p>Gráficos de evolução semestral serão exibidos aqui.</p>
        </div>
      </TabPanel>

      <TabPanel>
        <template #header>
          <i class="pi pi-shield tab-icon" />
          <span>Indicadores</span>
        </template>
        <div class="tab-content tab-placeholder">
          <i class="pi pi-gauge placeholder-icon" />
          <p>Tabela de indicadores de risco comparados com medianas será exibida aqui.</p>
        </div>
      </TabPanel>

      <TabPanel>
        <template #header>
          <i class="pi pi-id-card tab-icon" />
          <span>Análise de CRMs</span>
        </template>
        <div class="tab-content tab-placeholder">
          <i class="pi pi-users placeholder-icon" />
          <p>Perfil de prescritores e alertas de anomalias serão exibidos aqui.</p>
        </div>
      </TabPanel>

      <TabPanel>
        <template #header>
          <i class="pi pi-exclamation-triangle tab-icon" />
          <span>Falecidos</span>
        </template>
        <div class="tab-content tab-placeholder">
          <i class="pi pi-ban placeholder-icon" />
          <p>Transações realizadas após óbito do beneficiário serão exibidas aqui.</p>
        </div>
      </TabPanel>

      <TabPanel>
        <template #header>
          <i class="pi pi-map tab-icon" />
          <span>Região de Saúde</span>
        </template>
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

.back-btn {
  flex-shrink: 0;
}

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

.risk-tag {
  font-size: 0.7rem;
}

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

.risk-value {
  color: #ef4444;
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
  background: var(--bg-color) !important;
}

:deep(.p-tabview-panel) {
  background: var(--bg-color) !important;
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

.tab-icon {
  font-size: 0.8rem;
}

/* ── PLACEHOLDER ─────────────────────────────────────── */
.tab-content {
  padding: 2rem;
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
