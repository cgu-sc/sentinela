<script setup>
import { computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { storeToRefs } from 'pinia';
import { useFetchAnalytics } from '@/composables/useFetchAnalytics';
import { useAnalyticsStore } from '@/stores/analytics';
import { useFilterStore } from '@/stores/filters';
import { useGeoStore } from '@/stores/geo';
import { useMetodologiaConfigStore } from '@/stores/metodologiaConfig';
import RiskChart from './components/charts/RiskChart.vue';
import BrazilMap from './components/maps/BrazilMap.vue';
import TopUfRiskChart from './components/charts/TopUfRiskChart.vue';
import SemesterProductionChart from './components/charts/SemesterProductionChart.vue';
import { getAppVersionLabel } from '@/config/appInfo';
import { useSystemUpdateStore } from '@/stores/systemUpdate';

const analyticsStore = useAnalyticsStore();
const filterStore = useFilterStore();
const geoStore = useGeoStore();
const metodologiaConfig = useMetodologiaConfigStore();
const router = useRouter();
const {
  enrichedKpis,
  resultadoSentinelaUF,
  cacheStatus,
  isLoading,
  error,
  lastSync,
  alertasPanorama,
  alertasPanoramaLoading,
} = storeToRefs(analyticsStore);

useFetchAnalytics({ includeFatorRisco: true, includeProducaoSemestral: true, includeAlertasPanorama: true });

onMounted(() => {
  analyticsStore.fetchCacheStatus();
  metodologiaConfig.ensureLoaded().catch((error) => {
    console.warn('[HomeView] Não foi possível carregar a configuração metodológica.', error);
  });
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

const integerFormatter = new Intl.NumberFormat('pt-BR', {
  maximumFractionDigits: 0,
});

const currencyFormatter = new Intl.NumberFormat('pt-BR', {
  style: 'currency',
  currency: 'BRL',
  maximumFractionDigits: 0,
});

const alertTooltipTemplates = {
  volume_atipico:
    '{qtd} estabelecimentos apresentaram crescimento semestral superior a 50%, com aumento absoluto mínimo de {aumento_minimo}, em pelo menos um semestre comparável no período selecionado.',
  cnpj_dispersao_uf_nao_vizinha:
    '{qtd} estabelecimentos tiveram mais de 5% do valor autorizado associado a beneficiários residentes em UFs que não fazem fronteira com a UF da farmácia, no período selecionado.',
  cnpj_cnae_farmacia_ausente:
    '{qtd} estabelecimentos possuem CNAE principal e secundários sem identificação de atividade farmacêutica compatível.',
  socio_falecido:
    '{qtd} estabelecimentos possuem ao menos um sócio pessoa física com vínculo societário ativo identificado como falecido na base de óbitos.',
  socio_beneficio_social:
    '{qtd} estabelecimentos possuem ao menos um sócio direto com vínculo ativo identificado no CadÚnico ou como beneficiário do Seguro Defeso.',
  socio_idade_atipica:
    '{qtd} estabelecimentos possuem ao menos um sócio pessoa física com vínculo ativo e idade inferior a 21 anos ou superior a 80 anos na data de referência do período selecionado.',
  socio_esocial:
    '{qtd} estabelecimentos possuem sócios ativos que possuem vínculos em outros CNPJs em funções não gerenciais, conforme registros do eSocial.',
};

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
  if (!cacheStatus.value) {
    return {
      label: 'Verificando',
      detail: 'Validando módulos locais',
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

const appVersionLabel = computed(() => getAppVersionLabel());

const updateStore = useSystemUpdateStore();

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

const cacheModuleSummary = computed(() => {
  const total = cacheModules.value.length;
  const loaded = cacheModules.value.filter((module) => module.loaded).length;

  if (!cacheStatus.value || total === 0) {
    return {
      value: '...',
      label: 'verificando módulos',
      modulesValue: '...',
    };
  }

  const percent = Math.round((loaded / total) * 100);
  const isComplete = loaded === total;

  return {
    value: isComplete ? `${percent}%` : `${loaded}/${total}`,
    label: isComplete ? 'módulos carregados' : 'módulos carregados',
    modulesValue: `${loaded}/${total}`,
  };
});

function getModuleTone(module) {
  if (module.loaded) return 'ok';
  if (module.exists) return 'error';
  return 'missing';
}

function getAlertaTooltip(alerta) {
  const qtd = integerFormatter.format(Number(alerta?.qtd_cnpjs ?? 0));
  const aumentoMinimo = metodologiaConfig.loaded
    ? currencyFormatter.format(Number(metodologiaConfig.volumeAtipicoAumentoMinimo))
    : 'valor configurado';
  const template = alertTooltipTemplates[alerta?.tipo];
  if (!template) {
    throw new Error(`Tooltip do alerta de integridade não configurado: ${alerta?.tipo}`);
  }
  return template
    .replace('{qtd}', qtd)
    .replace('{aumento_minimo}', aumentoMinimo);
}

const displayAlertasPanorama = computed(() => {
  if (alertasPanorama.value) return alertasPanorama.value;
  return null;
});

const showAlertasSkeleton = computed(() => alertasPanoramaLoading.value && !displayAlertasPanorama.value);

</script>

<template>
  <div class="dashboard-container">
    <section class="audit-priorities">
      <div class="priority-grid">
        <!-- Card Sistema — template dedicado -->
        <article
          class="priority-card priority-card--operational priority-card--system"
          :class="`priority-card--${statusInfo.tone}`"
          tabindex="0"
        >
          <div class="system-header">
            <div class="priority-icon">
              <i :class="statusInfo.icon" />
            </div>
            <div class="system-header__text">
              <span class="priority-eyebrow">Sistema</span>
              <strong>Status operacional</strong>
            </div>
          </div>

          <div class="system-hero">
            <span class="system-hero__value">{{ cacheModuleSummary.value }}</span>
            <span class="system-hero__label">{{ cacheModuleSummary.label }}</span>
          </div>

          <div class="system-stats">
            <div class="system-stat system-stat--modules" tabindex="0">
              <span class="system-stat__label">Módulos</span>
              <strong class="system-stat__value">{{ cacheModuleSummary.modulesValue }}</strong>

              <div class="operational-panel">
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
            </div>
            <div class="system-stat">
              <span class="system-stat__label">Status</span>
              <strong class="system-stat__value" :class="`system-stat__value--${statusInfo.tone}`">
                {{ statusInfo.label }}
              </strong>
            </div>
            <div class="system-stat">
              <span class="system-stat__label">Versão</span>
              <strong class="system-stat__value">{{ appVersionLabel }}</strong>
            </div>
            <div
              class="system-stat system-stat--update"
              :class="`system-stat--update-${updateStore.statusTone}`"
              v-tooltip.left="updateStore.checkedAtFormatted
                ? `Última verificação: ${updateStore.checkedAtFormatted}`
                : updateStore.message || 'Verificação pendente'"
            >
              <span class="system-stat__label">Atualização</span>
              <strong class="system-stat__value system-stat__value--update"
                :class="`system-stat__value--update-${updateStore.statusTone}`">
                {{ updateStore.statusLabel || '—' }}
              </strong>
            </div>
          </div>
        </article>

        <!-- Card Integridade — template dedicado -->
        <article class="priority-card priority-card--warning priority-card--alerts priority-card--integrity">
          <div class="integrity-header">
            <div class="priority-icon">
              <i :class="alertasPanoramaLoading ? 'pi pi-spin pi-spinner' : 'pi pi-shield'" />
            </div>
            <div class="integrity-header__text">
              <span class="priority-eyebrow">Integridade</span>
              <strong>Quadro de Alertas</strong>
            </div>
          </div>
          <div class="integrity-hero">
            <span class="integrity-hero__value">
              {{ displayAlertasPanorama?.total_cnpjs_com_alerta ?? (alertasPanoramaLoading ? '...' : '—') }}
            </span>
            <span class="integrity-hero__label">estabelecimentos com ao menos 1 alerta identificado</span>
          </div>
          <div v-if="displayAlertasPanorama" class="alerts-grid">
            <div
              v-for="alerta in displayAlertasPanorama.alertas"
              :key="alerta.tipo"
              class="alert-cell"
              :class="`alert-cell--${alerta.severidade}`"
            >
              <span class="alert-cell__count">
                {{ alerta.qtd_cnpjs }}
                <i
                  v-tooltip.top="getAlertaTooltip(alerta)"
                  class="pi pi-info-circle alert-cell__info"
                  :aria-label="`Critério do alerta ${alerta.titulo}`"
                />
              </span>
              <span class="alert-cell__titulo">{{ alerta.titulo }}</span>
            </div>
          </div>
          <div v-else-if="showAlertasSkeleton" class="alerts-grid alerts-grid--loading">
            <div v-for="n in 6" :key="n" class="alert-cell alert-cell--skeleton" />
          </div>
        </article>

        <!-- Card Escopo da análise — template dedicado -->
        <article class="priority-card priority-card--info priority-card--escopo">
          <div class="escopo-header">
            <div class="priority-icon">
              <i class="pi pi-map" />
            </div>
            <div class="escopo-header__text">
              <span class="priority-eyebrow">Escopo monitorado</span>
              <strong>Escopo da análise</strong>
            </div>
          </div>
          <div class="escopo-hero">
            <span class="escopo-hero__value">{{ getKpiValue('CNPJS') }}</span>
            <span class="escopo-hero__label">CNPJs com movimentação</span>
          </div>
          <div class="escopo-stats">
            <div class="escopo-stat">
              <span class="escopo-stat__label">Municípios</span>
              <strong class="escopo-stat__value">{{ getKpiValue('MUNICIPIOS') }}</strong>
            </div>
            <div class="escopo-stat">
              <span class="escopo-stat__label">UFs</span>
              <strong class="escopo-stat__value">{{ ufCount || '—' }}</strong>
            </div>
            <div class="escopo-stat escopo-stat--wide">
              <span class="escopo-stat__label">Período analisado</span>
              <strong class="escopo-stat__value">{{ periodText }}</strong>
            </div>
          </div>
        </article>

        <!-- Card Produção — template dedicado -->
        <article class="priority-card priority-card--critical priority-card--financeiro">
          <div class="financeiro-header">
            <div class="priority-icon">
              <i class="pi pi-money-bill" />
            </div>
            <div class="financeiro-header__text">
              <span class="priority-eyebrow">Produção</span>
              <strong>Movimentação financeira</strong>
            </div>
          </div>
          <div class="financeiro-hero">
            <span class="financeiro-hero__value">{{ getKpiValue('VALOR DAS VENDAS') }}</span>
            <span class="financeiro-hero__label">valor movimentado no período selecionado</span>
          </div>
          <div class="financeiro-stats">
            <div class="financeiro-stat financeiro-stat--critical">
              <span class="financeiro-stat__label">Valor sem comprovação</span>
              <strong class="financeiro-stat__value">{{ getKpiValue('SEM COMPROVACAO') }}</strong>
            </div>
            <div class="financeiro-stat financeiro-stat--critical">
              <span class="financeiro-stat__label">% sem comprovação</span>
              <strong class="financeiro-stat__value">{{ getKpiValue('% SEM COMPROVACAO') }}</strong>
            </div>
            <div class="financeiro-stat financeiro-stat--wide">
              <span class="financeiro-stat__label">{{ financialScopeMetric.label }}</span>
              <strong class="financeiro-stat__value">{{ financialScopeMetric.value }}</strong>
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
  grid-template-columns: minmax(0, 0.82fr) minmax(0, 1.8fr) minmax(0, 0.9fr) minmax(0, 1fr);
  gap: 1rem;
  align-items: stretch;
}

.priority-card {
  position: relative;
  display: grid;
  grid-template-columns: auto minmax(0, 1fr) auto;
  gap: 0.65rem;
  align-items: flex-start;
  padding: 0.75rem 0.9rem;
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  border-radius: 8px;
  color: inherit;
  overflow: hidden;
  min-height: 16rem;
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
  box-shadow: 0 16px 36px color-mix(in srgb, var(--text-color-85) 15%, transparent);
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

.system-stat--modules:hover .operational-panel,
.system-stat--modules:focus-within .operational-panel {
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
  gap: 0.18rem;
}

.priority-content strong {
  color: var(--text-color-85);
  font-size: 0.84rem;
  line-height: 1.2;
}

.priority-value {
  color: var(--text-color-85);
  font-size: 1.35rem;
  font-weight: 600;
  line-height: 1.15;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.priority-metrics {
  display: grid;
  grid-template-columns: minmax(0, 0.8fr) minmax(0, 0.55fr) minmax(0, 1.65fr);
  gap: 0.35rem;
  margin-top: 0.28rem;
}

.priority-metrics--system {
  grid-template-columns: minmax(0, 0.85fr) minmax(0, 1.55fr);
}

.priority-metric {
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 0.18rem;
  align-items: flex-start;
  justify-content: center;
  padding: 0.38rem 0.5rem;
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

/* ── Card Sistema dedicado ── */
.priority-card--system {
  grid-template-columns: 1fr;
  display: flex;
  flex-direction: column;
  align-items: stretch;
  gap: 0.5rem;
}

.system-header {
  display: flex;
  align-items: center;
  gap: 0.6rem;
}

.system-header__text {
  display: flex;
  flex-direction: column;
  gap: 0.1rem;
  min-width: 0;
}

.system-header__text strong {
  color: var(--text-color-85);
  font-size: 0.84rem;
  line-height: 1.2;
}

.system-hero {
  display: flex;
  flex-direction: column;
  gap: 0.15rem;
  padding: 0.2rem 0 0.1rem;
}

.system-hero__value {
  font-size: 1.85rem;
  font-weight: 700;
  line-height: 1;
  color: var(--text-color-85);
  letter-spacing: -0.01em;
}

.system-hero__label {
  font-size: 0.7rem;
  color: var(--text-muted);
  line-height: 1;
}

.system-stats {
  display: grid;
  grid-template-columns: 1fr;
  gap: 0.36rem;
  margin-top: 0.1rem;
}

.system-stat {
  position: relative;
  min-width: 0;
  display: grid;
  grid-template-columns: minmax(0, 0.8fr) minmax(0, 1.2fr);
  align-items: center;
  gap: 0.45rem;
  padding: 0.38rem 0.55rem;
  border-radius: 6px;
  border: 1px solid color-mix(in srgb, var(--priority-color) 16%, transparent);
  background: color-mix(in srgb, var(--priority-color) 6%, transparent);
}

.system-stat--modules {
  cursor: help;
}

.system-stat--modules:hover,
.system-stat--modules:focus-visible,
.system-stat--modules:focus-within {
  border-color: color-mix(in srgb, var(--priority-color) 30%, transparent);
  background: color-mix(in srgb, var(--priority-color) 9%, transparent);
  outline: none;
}

.system-stat__label {
  font-size: 0.66rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--text-muted);
  line-height: 1;
}

.system-stat__value {
  font-size: 0.9rem;
  font-weight: 600;
  color: var(--text-color-85);
  line-height: 1.15;
  text-align: right;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.system-stat__value--success {
  color: var(--status-success);
}

.system-stat__value--warning {
  color: var(--risk-medium);
}

.system-stat__value--loading {
  color: var(--primary-color);
}

.system-stat__value--update-ok       { color: var(--status-success); }
.system-stat__value--update-warn      { color: var(--risk-medium); }
.system-stat__value--update-critical  { color: var(--status-danger, #ef4444); }
.system-stat__value--update-muted     { color: var(--text-muted); }

.priority-card--alerts {
  --priority-color: var(--risk-medium);
}

/* ── Card Integridade dedicado ── */
.priority-card--integrity {
  grid-template-columns: 1fr;
  display: flex;
  flex-direction: column;
  align-items: stretch;
  gap: 0.5rem;
}

.integrity-header {
  display: flex;
  align-items: center;
  gap: 0.6rem;
}

.integrity-header__text {
  display: flex;
  flex-direction: column;
  gap: 0.1rem;
  min-width: 0;
}

.integrity-header__text strong {
  color: var(--text-color-85);
  font-size: 0.84rem;
  line-height: 1.2;
}

.integrity-hero {
  display: flex;
  flex-direction: column;
  gap: 0.15rem;
  padding: 0.2rem 0 0.1rem;
}

.integrity-hero__value {
  font-size: 1.85rem;
  font-weight: 700;
  line-height: 1;
  color: var(--text-color-85);
  letter-spacing: -0.01em;
}

.integrity-hero__label {
  font-size: 0.7rem;
  color: var(--text-muted);
  line-height: 1;
}

/* ── Card Escopo dedicado ── */
.priority-card--escopo {
  grid-template-columns: 1fr;
  display: flex;
  flex-direction: column;
  align-items: stretch;
  gap: 0.5rem;
  overflow: visible;
}

.escopo-header {
  display: flex;
  align-items: center;
  gap: 0.6rem;
}

.escopo-header__text {
  display: flex;
  flex-direction: column;
  gap: 0.1rem;
  min-width: 0;
}

.escopo-header__text strong {
  color: var(--text-color-85);
  font-size: 0.84rem;
  line-height: 1.2;
}

.escopo-hero {
  display: flex;
  flex-direction: column;
  gap: 0.15rem;
  padding: 0.2rem 0 0.1rem;
}

.escopo-hero__value {
  font-size: 1.85rem;
  font-weight: 700;
  line-height: 1;
  color: var(--text-color-85);
  letter-spacing: -0.01em;
}

.escopo-hero__label {
  font-size: 0.7rem;
  color: var(--text-muted);
  line-height: 1;
}

.escopo-stats {
  flex: 1;
  display: grid;
  grid-template-columns: 1fr 1fr;
  grid-template-rows: 1fr 1fr;
  gap: 0.32rem;
}

.escopo-stat {
  display: flex;
  flex-direction: column;
  justify-content: center;
  gap: 0.22rem;
  padding: 0.4rem 0.6rem;
  border: 1px solid color-mix(in srgb, var(--priority-color) 16%, transparent);
  border-radius: 8px;
  background: color-mix(in srgb, var(--priority-color) 6%, transparent);
  min-height: 2.6rem;
  overflow: hidden;
}

.escopo-stat--wide {
  grid-column: 1 / -1;
}

.escopo-stat__label {
  font-size: 0.6rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--text-muted);
  line-height: 1;
}

.escopo-stat__value {
  font-size: 1.2rem;
  font-weight: 600;
  color: var(--text-color-85);
  line-height: 1.1;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.alerts-grid {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  grid-auto-rows: 1fr;
  flex: 1;
  gap: 0.28rem;
}

.alerts-grid--loading {
  opacity: 0.45;
}

.alert-cell {
  display: flex;
  flex-direction: column;
  gap: 0.1rem;
  padding: 0.28rem 0.4rem;
  border-radius: 5px;
  border: 1px solid color-mix(in srgb, var(--card-border) 60%, transparent);
  background: color-mix(in srgb, var(--card-border) 18%, transparent);
  min-width: 0;
}

.alert-cell--critico {
  border-color: color-mix(in srgb, var(--risk-high) 22%, transparent);
  background: color-mix(in srgb, var(--risk-high) 7%, transparent);
}

.alert-cell--atencao {
  border-color: color-mix(in srgb, var(--risk-medium) 22%, transparent);
  background: color-mix(in srgb, var(--risk-medium) 7%, transparent);
}

.alert-cell--skeleton {
  min-height: 2.4rem;
  animation: skeleton-pulse 1.4s ease-in-out infinite;
}

@keyframes skeleton-pulse {
  0%, 100% { opacity: 0.35; }
  50% { opacity: 0.7; }
}

.alert-cell__count {
  display: inline-flex;
  align-items: center;
  gap: 0.25rem;
  font-size: 1rem;
  font-weight: 600;
  line-height: 1.1;
  color: var(--text-color-85);
}

.alert-cell--critico .alert-cell__count { color: var(--risk-high); }
.alert-cell--atencao .alert-cell__count { color: var(--risk-medium); }

.alert-cell__info {
  font-size: 0.66rem;
  color: var(--text-muted);
  cursor: help;
  opacity: 0.82;
}

.alert-cell__info:hover {
  color: var(--text-color-85);
  opacity: 1;
}

.alert-cell__titulo {
  font-size: 0.75rem;
  font-weight: 500;
  color: var(--text-muted);
  line-height: 1.2;
  overflow: hidden;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
}

/* ── Card Financeiro dedicado ── */
.priority-card--financeiro {
  grid-template-columns: 1fr;
  display: flex;
  flex-direction: column;
  align-items: stretch;
  gap: 0.5rem;
}

.financeiro-header {
  display: flex;
  align-items: center;
  gap: 0.6rem;
}

.financeiro-header__text {
  display: flex;
  flex-direction: column;
  gap: 0.1rem;
  min-width: 0;
}

.financeiro-header__text strong {
  color: var(--text-color-85);
  font-size: 0.84rem;
  line-height: 1.2;
}

.financeiro-hero {
  display: flex;
  flex-direction: column;
  gap: 0.15rem;
  padding: 0.2rem 0 0.1rem;
}

.financeiro-hero__value {
  font-size: 1.85rem;
  font-weight: 700;
  line-height: 1;
  color: var(--text-color-85);
  letter-spacing: -0.01em;
}

.financeiro-hero__label {
  font-size: 0.7rem;
  color: var(--text-muted);
  line-height: 1;
}

.financeiro-stats {
  flex: 1;
  display: grid;
  grid-template-columns: 1fr 1fr;
  grid-template-rows: 1fr 1fr;
  gap: 0.32rem;
}

.financeiro-stat {
  display: flex;
  flex-direction: column;
  justify-content: center;
  gap: 0.22rem;
  padding: 0.4rem 0.6rem;
  border: 1px solid color-mix(in srgb, var(--priority-color) 16%, transparent);
  border-radius: 8px;
  background: color-mix(in srgb, var(--priority-color) 6%, transparent);
  min-height: 2.6rem;
  overflow: hidden;
}

.financeiro-stat--critical {
  border-color: color-mix(in srgb, var(--risk-indicator-critical) 34%, transparent);
  background: color-mix(in srgb, var(--risk-indicator-critical) 10%, transparent);
}

.financeiro-stat--wide {
  grid-column: 1 / -1;
}

.financeiro-stat__label {
  font-size: 0.6rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--text-muted);
  line-height: 1;
}

.financeiro-stat__value {
  font-size: 1.2rem;
  font-weight: 600;
  color: var(--text-color-85);
  line-height: 1.1;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
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
