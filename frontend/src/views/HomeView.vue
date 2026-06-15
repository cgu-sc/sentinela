<script setup>
import { computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { storeToRefs } from 'pinia';
import { useFetchAnalytics } from '@/composables/useFetchAnalytics';
import { useAnalyticsStore } from '@/stores/analytics';
import { useFilterStore } from '@/stores/filters';
import { useGeoStore } from '@/stores/geo';
import RiskChart from './components/charts/RiskChart.vue';
import BrazilMap from './components/maps/BrazilMap.vue';
import TopUfRiskChart from './components/charts/TopUfRiskChart.vue';
import SemesterProductionChart from './components/charts/SemesterProductionChart.vue';

const analyticsStore = useAnalyticsStore();
const filterStore = useFilterStore();
const geoStore = useGeoStore();
const router = useRouter();
const {
  enrichedKpis,
  resultadoSentinelaUF,
  cacheStatus,
  isLoading,
  error,
  lastSync,
} = storeToRefs(analyticsStore);

useFetchAnalytics({ includeFatorRisco: true, includeProducaoSemestral: true });

onMounted(() => {
  analyticsStore.fetchCacheStatus();
});

const dateFormatter = new Intl.DateTimeFormat('pt-BR', {
  day: '2-digit',
  month: '2-digit',
  year: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
});

const monthFormatter = new Intl.DateTimeFormat('pt-BR', {
  month: 'short',
  year: 'numeric',
});

function normalizeLabel(label) {
  return String(label || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toUpperCase();
}

function getKpiValue(labelPart) {
  const normalizedPart = normalizeLabel(labelPart);
  return enrichedKpis.value?.find((kpi) =>
    normalizeLabel(kpi.label).includes(normalizedPart)
  )?.value ?? '-';
}

const statusInfo = computed(() => {
  if (error.value) {
    return {
      label: 'Atenção',
      detail: 'Falha ao carregar métricas',
      icon: 'pi pi-exclamation-triangle',
      tone: 'warning',
    };
  }
  if (isLoading.value) {
    return {
      label: 'Atualizando',
      detail: 'Sincronizando dados da visão atual',
      icon: 'pi pi-spin pi-spinner',
      tone: 'loading',
    };
  }
  if (cacheStatus.value && cacheStatus.value.is_ready === false) {
    return {
      label: 'Atenção',
      detail: 'Há módulos de cache pendentes',
      icon: 'pi pi-exclamation-triangle',
      tone: 'warning',
    };
  }
  return {
    label: 'Operacional',
    detail: 'Base local disponível',
    icon: 'pi pi-check-circle',
    tone: 'success',
  };
});

const syncText = computed(() => {
  if (!lastSync.value) return 'Aguardando primeira atualização';
  return dateFormatter.format(new Date(lastSync.value));
});

const periodText = computed(() => {
  const [start, end] = filterStore.periodo || [];
  if (!start || !end) return 'Período não definido';
  return `${monthFormatter.format(new Date(start))} - ${monthFormatter.format(new Date(end))}`;
});

const ufCount = computed(() =>
  (resultadoSentinelaUF.value || []).filter((item) => item?.uf).length
);

const financialScopeMetric = computed(() => {
  const municipio = filterStore.selectedMunicipio;
  if (municipio && municipio !== 'Todos') {
    const nome = geoStore.getMunicipioNomeByIbge7(municipio);
    if (!nome) throw new Error('Municipio selecionado sem nome no contrato de localidades.');
    return { label: 'Município', value: nome };
  }

  const regiao = filterStore.selectedRegiaoSaude;
  if (regiao && regiao !== 'Todos') {
    const nome = geoStore.getRegiaoNomeById(regiao);
    if (!nome) throw new Error('Regiao selecionada sem nome no contrato de localidades.');
    return { label: 'Região', value: nome };
  }

  const uf = filterStore.selectedUF;
  if (uf && uf !== 'Todos') return { label: 'UF', value: uf };

  return { label: 'Escopo', value: 'Brasil' };
});

const cacheModules = computed(() =>
  Object.entries(cacheStatus.value?.modules || {}).map(([key, module]) => ({
    key,
    label: module.label,
    status: module.status,
    loaded: Boolean(module.loaded),
    exists: Boolean(module.exists),
  }))
);

const cacheSummaryText = computed(() => {
  if (!cacheStatus.value) return 'Verificando módulos';
  if (cacheStatus.value.modules_summary_label) return cacheStatus.value.modules_summary_label;
  const loaded = cacheModules.value.filter((module) => module.loaded).length;
  const total = cacheModules.value.length;
  return `${loaded}/${total} módulos carregados`;
});

function getModuleTone(module) {
  if (module.loaded) return 'ok';
  if (module.exists) return 'error';
  return 'missing';
}

function goToMunicipios() {
  router.push('/municipios');
}

const statusCardMetrics = computed(() => [
  {
    label: 'Módulos',
    value: cacheSummaryText.value,
  },
  {
    label: 'Última atualização',
    value: syncText.value,
  },
]);

const coverageCardMetrics = computed(() => [
  {
    label: 'Municípios',
    value: getKpiValue('MUNICIPIOS'),
  },
  {
    label: 'UFs',
    value: `${ufCount.value || '-'}`,
  },
  {
    label: 'Período',
    value: periodText.value,
    wide: true,
  },
]);

const financialCardMetrics = computed(() => [
  {
    label: 'Valor sem comprovação',
    value: getKpiValue('SEM COMPROVACAO'),
    tone: 'critical',
  },
  {
    label: '% sem comprovação',
    value: getKpiValue('% SEM COMPROVACAO'),
    tone: 'critical',
  },
  financialScopeMetric.value,
]);

const priorityCards = computed(() => [
  {
    title: 'Status operacional',
    eyebrow: 'Sistema',
    value: statusInfo.value.label,
    detail: 'Integridade dos módulos carregados',
    metrics: statusCardMetrics.value,
    metricsLayout: 'system',
    icon: statusInfo.value.icon,
    tone: statusInfo.value.tone,
    hasModulePanel: true,
  },
  {
    title: 'Escopo da análise',
    eyebrow: 'Escopo monitorado',
    value: getKpiValue('CNPJS'),
    detail: 'CNPJs com movimentação',
    metrics: coverageCardMetrics.value,
    icon: 'pi pi-map',
    tone: 'info',
  },
  {
    title: 'Movimentação financeira',
    eyebrow: 'Produção',
    value: getKpiValue('VALOR DAS VENDAS'),
    detail: 'valor movimentado no período selecionado',
    metrics: financialCardMetrics.value,
    icon: 'pi pi-money-bill',
    tone: 'critical',
  },
]);
</script>

<template>
  <div class="dashboard-container">
    <section class="audit-priorities">
      <div class="priority-grid">
        <article
          v-for="card in priorityCards"
          :key="card.title"
          class="priority-card"
          :class="[`priority-card--${card.tone}`, { 'priority-card--operational': card.hasModulePanel }]"
          :tabindex="card.hasModulePanel ? 0 : undefined"
        >
          <div class="priority-icon">
            <i :class="card.icon" />
          </div>
          <div class="priority-content">
            <span class="priority-eyebrow">{{ card.eyebrow }}</span>
            <strong>{{ card.title }}</strong>
            <span class="priority-value">{{ card.value }}</span>
            <p>{{ card.detail }}</p>
            <div
              v-if="card.metrics"
              class="priority-metrics"
              :class="card.metricsLayout ? `priority-metrics--${card.metricsLayout}` : null"
            >
              <div
                v-for="metric in card.metrics"
                :key="metric.label"
                class="priority-metric"
                :class="[metric.tone ? `priority-metric--${metric.tone}` : null, { 'priority-metric--wide': metric.wide }]"
              >
                <span>{{ metric.label }}</span>
                <strong>{{ metric.value }}</strong>
              </div>
            </div>
          </div>
          <button
            v-if="card.hasModulePanel"
            type="button"
            class="operational-toggle"
            aria-label="Ver integridade dos módulos"
            title="Ver integridade dos módulos"
          >
            <i class="pi pi-info-circle" />
          </button>
          <div v-if="card.hasModulePanel" class="operational-panel">
            <div class="operational-panel__header">
              <strong>Integridade dos módulos</strong>
              <span>{{ cacheSummaryText }}</span>
            </div>
            <div class="operational-panel__list">
              <div
                v-for="module in cacheModules"
                :key="module.key"
                class="operational-module"
                :class="`operational-module--${getModuleTone(module)}`"
              >
                <span class="operational-module__status">
                  {{ module.loaded ? 'OK' : module.exists ? 'Erro' : 'Ausente' }}
                </span>
                <span class="operational-module__name">{{ module.label }}</span>
                <strong>{{ module.loaded ? 'Carregado' : 'Não carregado' }}</strong>
              </div>
            </div>
          </div>
        </article>
      </div>
    </section>

    <div class="charts-row">
      <SemesterProductionChart />
      <BrazilMap />
    </div>
    <div class="insight-charts-row">
      <TopUfRiskChart />
      <RiskChart />
    </div>
    <button type="button" class="floating-start-button" @click="goToMunicipios">
      <span>Iniciar análise</span>
      <i class="pi pi-arrow-right" aria-hidden="true" />
    </button>
  </div>
</template>

<style scoped>
.dashboard-container {
  position: relative;
  display: flex;
  flex-direction: column;
  gap: 1rem;
  height: calc(100vh - 56px - 1.25rem - 1.5rem);
  min-height: 0;
  overflow: hidden;
}

.audit-priorities {
  display: flex;
  flex-direction: column;
  gap: 0.85rem;
  flex: 0 0 auto;
}

.priority-eyebrow {
  font-size: 0.64rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: var(--primary-color);
  opacity: 0.72;
}

.priority-grid {
  display: grid;
  grid-template-columns: minmax(0, 0.85fr) minmax(0, 1.1fr) minmax(0, 1.35fr);
  gap: 1rem;
}

.floating-start-button {
  position: fixed;
  right: 1.35rem;
  top: calc(56px + 2.35rem);
  z-index: 20;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 0.62rem;
  min-height: 2.7rem;
  padding: 0.78rem 1.08rem;
  border: 1px solid color-mix(in srgb, var(--primary-color) 44%, transparent);
  border-radius: 999px;
  background:
    linear-gradient(
      135deg,
      color-mix(in srgb, var(--primary-color) 22%, var(--surface-card)),
      color-mix(in srgb, var(--primary-color) 10%, var(--surface-card))
    );
  box-shadow: 0 14px 34px color-mix(in srgb, var(--primary-color) 18%, transparent);
  color: var(--text-color);
  cursor: pointer;
  font-size: 0.8rem;
  font-weight: 600;
  letter-spacing: 0.02em;
  text-transform: uppercase;
  transition:
    transform 0.16s ease,
    border-color 0.16s ease,
    box-shadow 0.16s ease,
    background 0.16s ease;
}

.floating-start-button:hover {
  transform: translateY(-2px);
  border-color: color-mix(in srgb, var(--primary-color) 68%, transparent);
  box-shadow: 0 18px 42px color-mix(in srgb, var(--primary-color) 24%, transparent);
}

.floating-start-button:focus-visible {
  outline: 2px solid color-mix(in srgb, var(--primary-color) 46%, transparent);
  outline-offset: 2px;
}

.floating-start-button i {
  font-size: 0.85rem;
  color: var(--primary-color);
}

.priority-card {
  position: relative;
  display: grid;
  grid-template-columns: auto minmax(0, 1fr) auto;
  gap: 0.8rem;
  align-items: flex-start;
  min-height: 8.8rem;
  padding: 1rem;
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  border-radius: 8px;
  color: inherit;
  overflow: hidden;
}

.priority-card::before {
  content: "";
  position: absolute;
  inset: 0 auto 0 0;
  width: 3px;
  background: var(--priority-color, var(--primary-color));
  opacity: 0.75;
}

.priority-card--operational {
  overflow: visible;
}

.priority-card--operational:hover,
.priority-card--operational:focus-within {
  z-index: 30;
}

.operational-toggle {
  width: 2rem;
  height: 2rem;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border: 1px solid color-mix(in srgb, var(--priority-color) 18%, transparent);
  border-radius: 8px;
  color: var(--priority-color);
  background: color-mix(in srgb, var(--priority-color) 7%, transparent);
  cursor: pointer;
  transition: background 140ms ease, border-color 140ms ease, transform 140ms ease;
}

.operational-toggle:hover,
.operational-toggle:focus-visible {
  border-color: color-mix(in srgb, var(--priority-color) 36%, transparent);
  background: color-mix(in srgb, var(--priority-color) 12%, transparent);
  outline: none;
  transform: translateY(-1px);
}

.operational-panel {
  position: absolute;
  top: 0;
  left: calc(100% + 0.4rem);
  z-index: 40;
  width: min(28rem, calc(100vw - 2rem));
  max-height: min(26rem, calc(100vh - 7rem));
  padding: 0.7rem;
  border: 1px solid var(--card-border);
  border-radius: 8px;
  background: var(--card-bg);
  box-shadow: 0 16px 36px color-mix(in srgb, var(--text-color) 15%, transparent);
  opacity: 0;
  pointer-events: none;
  transform: translateX(-0.35rem);
  transition: opacity 160ms ease, transform 160ms ease;
}

.operational-panel::before {
  content: "";
  position: absolute;
  top: 0;
  right: 100%;
  width: 0.5rem;
  height: 100%;
}

.priority-card--operational:hover .operational-panel,
.priority-card--operational:focus-within .operational-panel {
  opacity: 1;
  pointer-events: auto;
  transform: translateX(0);
}

.operational-panel__header {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 1rem;
  padding-bottom: 0.55rem;
  border-bottom: 1px solid var(--card-border);
}

.operational-panel__header strong {
  color: var(--text-color-85);
  font-size: 0.82rem;
}

.operational-panel__header span {
  color: var(--text-muted);
  font-size: 0.72rem;
  font-weight: 600;
  white-space: nowrap;
}

.operational-panel__list {
  display: flex;
  flex-direction: column;
  gap: 0.3rem;
  max-height: 21.25rem;
  overflow: auto;
  padding-top: 0.45rem;
}

.operational-module {
  display: grid;
  grid-template-columns: 4rem minmax(0, 1fr) 6.7rem;
  gap: 0.55rem;
  align-items: center;
  min-height: 1.9rem;
  padding: 0.28rem 0.4rem;
  border: 1px solid color-mix(in srgb, var(--card-border) 70%, transparent);
  border-radius: 8px;
  background: color-mix(in srgb, var(--module-status-color, var(--text-muted)) 4%, transparent);
}

.operational-module__status {
  display: inline-flex;
  align-items: center;
  gap: 0.35rem;
  color: var(--text-muted);
  font-size: 0.64rem;
  font-weight: 600;
  text-transform: uppercase;
}

.operational-module__status::before {
  content: "";
  width: 0.45rem;
  height: 0.45rem;
  flex: 0 0 0.45rem;
  border-radius: 50%;
  background: var(--module-status-color, var(--text-muted));
}

.operational-module--ok {
  --module-status-color: var(--status-success, #10b981);
}

.operational-module--ok .operational-module__status {
  color: var(--status-success, #10b981);
}

.operational-module--error {
  --module-status-color: var(--status-error, var(--risk-indicator-critical));
}

.operational-module--missing {
  --module-status-color: var(--status-warning, var(--risk-indicator-medium));
}

.operational-module__name {
  min-width: 0;
  overflow: hidden;
  color: var(--text-color-85);
  font-size: 0.75rem;
  font-weight: 600;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.operational-module strong {
  color: var(--text-muted);
  font-size: 0.72rem;
  font-weight: 600;
  white-space: nowrap;
}

.priority-card--critical {
  --priority-color: var(--risk-indicator-critical);
}

.priority-card--success {
  --priority-color: var(--risk-indicator-low);
}

.priority-card--loading {
  --priority-color: var(--primary-color);
}

.priority-card--warning {
  --priority-color: var(--risk-indicator-medium);
}

.priority-card--info {
  --priority-color: var(--primary-color);
}

.priority-card--neutral {
  --priority-color: var(--text-muted);
}

.priority-icon {
  width: 2.2rem;
  height: 2.2rem;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  border-radius: 8px;
  color: var(--priority-color);
  background: color-mix(in srgb, var(--priority-color) 9%, transparent);
}

.priority-content {
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 0.26rem;
}

.priority-content strong {
  color: var(--text-color-85);
  font-size: 0.84rem;
  line-height: 1.2;
}

.priority-value {
  color: var(--text-color-85);
  font-size: 1.55rem;
  font-weight: 600;
  line-height: 1.15;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.priority-metrics {
  display: grid;
  grid-template-columns: minmax(0, 0.8fr) minmax(0, 0.55fr) minmax(0, 1.65fr);
  gap: 0.45rem;
  margin-top: 0.35rem;
}

.priority-metrics--system {
  grid-template-columns: minmax(0, 0.85fr) minmax(0, 1.55fr);
}

.priority-metric {
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 0.22rem;
  align-items: flex-start;
  justify-content: center;
  padding: 0.52rem 0.58rem;
  border: 1px solid color-mix(in srgb, var(--priority-color) 16%, transparent);
  border-radius: 8px;
  background: color-mix(in srgb, var(--priority-color) 6%, transparent);
}

.priority-metric--critical {
  border-color: color-mix(in srgb, var(--risk-indicator-critical) 34%, transparent);
  background: color-mix(in srgb, var(--risk-indicator-critical) 10%, transparent);
}

.priority-metric--warning {
  border-color: color-mix(in srgb, var(--risk-indicator-medium) 34%, transparent);
  background: color-mix(in srgb, var(--risk-indicator-medium) 10%, transparent);
}

.priority-metric span {
  display: block;
  color: var(--text-muted);
  font-size: 0.66rem;
  font-weight: 600;
  line-height: 1.1;
  text-transform: uppercase;
}

.priority-metric strong {
  display: block;
  color: var(--text-color-85);
  font-size: 0.98rem;
  font-weight: 600;
  line-height: 1.08;
  white-space: nowrap;
  overflow: hidden;
  max-width: 100%;
  text-overflow: ellipsis;
}

.priority-content p {
  margin: 0;
  color: var(--text-muted);
  font-size: 0.72rem;
  line-height: 1.35;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}

.charts-row {
  display: grid;
  grid-template-columns: 12fr 8fr;
  gap: 1rem;
  flex: 1.12 1 0;
  min-height: 0;
}

.insight-charts-row {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 1rem;
  align-items: stretch;
  flex: 0.88 1 0;
  min-height: 0;
}

@media (max-width: 1380px) {
  .priority-grid {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
}

@media (max-width: 980px) {
  .dashboard-container {
    height: auto;
    overflow: visible;
  }

  .charts-row,
  .insight-charts-row {
    grid-template-columns: 1fr;
    flex: none;
  }
}

@media (max-width: 680px) {
  .priority-grid {
    grid-template-columns: 1fr;
  }
}
</style>
