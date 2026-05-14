<script setup>
import { computed, onMounted } from 'vue';
import { storeToRefs } from 'pinia';
import { useFetchAnalytics } from '@/composables/useFetchAnalytics';
import { useAnalyticsStore } from '@/stores/analytics';
import { useFilterStore } from '@/stores/filters';
import RiskChart from './components/charts/RiskChart.vue';
import BrazilMap from './components/maps/BrazilMap.vue';
import TopUfRiskChart from './components/charts/TopUfRiskChart.vue';
import SemesterProductionChart from './components/charts/SemesterProductionChart.vue';

const analyticsStore = useAnalyticsStore();
const filterStore = useFilterStore();
const {
  enrichedKpis,
  fatorRisco,
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

const currencyFormatter = new Intl.NumberFormat('pt-BR', {
  style: 'currency',
  currency: 'BRL',
  maximumFractionDigits: 0,
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

const dominantRiskBucket = computed(() => {
  const buckets = fatorRisco.value || [];
  return buckets.reduce((best, bucket) => {
    const current = Number(bucket?.qtd ?? 0);
    const bestValue = Number(best?.qtd ?? -1);
    return current > bestValue ? bucket : best;
  }, null);
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
  },
]);

const financialCardMetrics = computed(() => [
  {
    label: 'Sem comprovação',
    value: getKpiValue('SEM COMPROVACAO'),
  },
  {
    label: '% sem comprovação',
    value: getKpiValue('% SEM COMPROVACAO'),
  },
]);

const indicatorCardMetrics = computed(() => [
  {
    label: 'Faixas ativas',
    value: `${fatorRisco.value?.length || '-'}`,
  },
  {
    label: 'Estab. na faixa',
    value: dominantRiskBucket.value?.qtd
      ? Number(dominantRiskBucket.value.qtd).toLocaleString('pt-BR')
      : '-',
  },
  {
    label: 'Valor s/ comp.',
    value: dominantRiskBucket.value?.valor_raw
      ? currencyFormatter.format(Number(dominantRiskBucket.value.valor_raw))
      : '-',
  },
]);

const priorityCards = computed(() => [
  {
    title: 'Status operacional',
    eyebrow: 'Sistema',
    value: statusInfo.value.label,
    detail: 'Disponibilidade da visão analítica atual',
    metrics: statusCardMetrics.value,
    icon: statusInfo.value.icon,
    tone: statusInfo.value.tone,
    hasModulePanel: true,
  },
  {
    title: 'Cobertura da análise',
    eyebrow: 'Escopo monitorado',
    value: getKpiValue('CNPJS'),
    detail: 'farmácias com dados no escopo selecionado',
    metrics: coverageCardMetrics.value,
    icon: 'pi pi-map',
    tone: 'info',
  },
  {
    title: 'Movimento financeiro',
    eyebrow: 'Produção auditada',
    value: getKpiValue('VALOR DAS VENDAS'),
    detail: 'valor movimentado no período selecionado',
    metrics: financialCardMetrics.value,
    icon: 'pi pi-money-bill',
    tone: 'critical',
  },
  {
    title: 'Indicadores',
    eyebrow: 'Sinais de auditoria',
    value: dominantRiskBucket.value?.faixa || '-',
    detail: 'faixa com maior concentração de estabelecimentos',
    metrics: indicatorCardMetrics.value,
    icon: 'pi pi-shield',
    tone: 'warning',
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
            <div v-if="card.metrics" class="priority-metrics">
              <div v-for="metric in card.metrics" :key="metric.label" class="priority-metric">
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
  </div>
</template>

<style scoped>
.dashboard-container {
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
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: var(--primary-color);
  opacity: 0.72;
}

.priority-grid {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: 1rem;
}

.priority-card {
  position: relative;
  display: grid;
  grid-template-columns: auto minmax(0, 1fr) auto;
  gap: 0.8rem;
  align-items: flex-start;
  min-height: 8.2rem;
  padding: 0.95rem;
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
  font-weight: 700;
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
  font-weight: 800;
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
  font-weight: 700;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.operational-module strong {
  color: var(--text-muted);
  font-size: 0.72rem;
  font-weight: 800;
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
  font-size: 1.05rem;
  font-weight: 800;
  line-height: 1.15;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.priority-metrics {
  display: grid;
  grid-template-columns: 1fr;
  gap: 0.35rem;
  margin-top: 0.25rem;
}

.priority-metric {
  min-width: 0;
  display: grid;
  grid-template-columns: minmax(0, 0.9fr) minmax(0, 1.1fr);
  gap: 0.45rem;
  align-items: center;
  padding: 0.38rem 0.45rem;
  border: 1px solid color-mix(in srgb, var(--priority-color) 16%, transparent);
  border-radius: 8px;
  background: color-mix(in srgb, var(--priority-color) 6%, transparent);
}

.priority-metric span {
  display: block;
  color: var(--text-muted);
  font-size: 0.58rem;
  font-weight: 700;
  line-height: 1.1;
  text-transform: uppercase;
}

.priority-metric strong {
  display: block;
  color: var(--text-color-85);
  font-size: 0.78rem;
  font-weight: 800;
  line-height: 1;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  text-align: right;
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
