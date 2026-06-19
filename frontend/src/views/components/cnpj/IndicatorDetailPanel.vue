<script setup>
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { storeToRefs } from 'pinia';
import DataTable from 'primevue/datatable';
import Column from 'primevue/column';
import TabView from 'primevue/tabview';
import TabPanel from 'primevue/tabpanel';
import OverlayPanel from 'primevue/overlaypanel';
import { useCnpjDetailStore } from '@/stores/cnpjDetail';
import { useFilterStore } from '@/stores/filters';
import { useMetodologiaConfigStore } from '@/stores/metodologiaConfig';
import { useFormatting } from '@/composables/useFormatting';
import { INDICATOR_DETAIL_CONFIG } from '@/config/indicatorDetailConfig';
import { AUDIT_THRESHOLDS } from '@/config/riskConfig';
import { logCnpjPerf } from '@/utils/cnpjPerfLogger';
import IndicatorEvolutionChart from './IndicatorEvolutionChart.vue';

const props = defineProps({
  cnpj: { type: String, default: '' },
  indicatorKey: { type: String, default: '' },
  showActiveCnpjHeader: { type: Boolean, default: true },
  externalCnpjNavigation: { type: Boolean, default: false },
  perfSession: { type: Object, default: null },
});

const emit = defineEmits(['cnpj-selected', 'active-cnpj-change']);

const cnpjDetailStore = useCnpjDetailStore();
const filterStore = useFilterStore();
const metodologiaConfig = useMetodologiaConfigStore();
const {
  indicadorBenchmarkDataByKey,
  indicadorBenchmarkLoadingByKey,
  indicadorBenchmarkErrorByKey,
  indicadorEvolucaoBenchmarkDataByKey,
  indicadorEvolucaoBenchmarkLoadingByKey,
  indicadorEvolucaoBenchmarkErrorByKey,
} = storeToRefs(cnpjDetailStore);

const {
  formatCurrencyFull,
  formatNumberFull,
  formatPercent,
  toLocalISO,
} = useFormatting();
const auditHighValue = computed(() =>
  metodologiaConfig.loaded
    ? metodologiaConfig.auditHighValue
    : AUDIT_THRESHOLDS.HIGH_VALUE,
);

onMounted(() => {
  metodologiaConfig.ensureLoaded().catch((error) => {
    console.warn('[IndicatorDetailPanel] Não foi possível carregar a configuração metodológica.', error);
  });
});

const config = computed(() => INDICATOR_DETAIL_CONFIG[props.indicatorKey] ?? null);

const periodoInicio = computed(() => {
  const [start] = filterStore.periodo ?? [];
  return start ? toLocalISO(start) : null;
});

const periodoFim = computed(() => {
  const [, end] = filterStore.periodo ?? [];
  return end ? toLocalISO(end) : null;
});

const periodoLabel = computed(() => {
  const start = periodoInicio.value;
  const end = periodoFim.value;
  if (!start || !end) return 'Período atual';
  return `${start.slice(5, 7)}/${start.slice(0, 4)} a ${end.slice(5, 7)}/${end.slice(0, 4)}`;
});

const normalizeCnpj = (value) => {
  const digits = String(value ?? '').replace(/\D/g, '');
  return digits ? digits.padStart(14, '0').slice(-14) : '';
};

const selectedCnpj = ref('');
const baseCnpj = computed(() => normalizeCnpj(props.cnpj));
const activeCnpj = computed(() => selectedCnpj.value || baseCnpj.value);
const isViewingTargetCnpj = computed(() => activeCnpj.value === baseCnpj.value);

const requestKey = computed(() => (
  `${activeCnpj.value}|${props.indicatorKey}|${periodoInicio.value || ''}|${periodoFim.value || ''}`
));

const currentBenchmarkData = computed(() => indicadorBenchmarkDataByKey.value[requestKey.value] ?? null);
const currentEvolutionData = computed(() => indicadorEvolucaoBenchmarkDataByKey.value[requestKey.value] ?? null);
const renderedRequestKey = ref('');
const isPanelUpdating = ref(false);
let panelUpdateToken = 0;
const PANEL_UPDATE_MIN_MS = 220;
const displayedRequestKey = computed(() => {
  if (currentBenchmarkData.value && currentEvolutionData.value) return requestKey.value;
  return renderedRequestKey.value;
});
const benchmarkData = computed(() => (
  displayedRequestKey.value ? indicadorBenchmarkDataByKey.value[displayedRequestKey.value] ?? null : null
));
const evolutionData = computed(() => (
  displayedRequestKey.value ? indicadorEvolucaoBenchmarkDataByKey.value[displayedRequestKey.value] ?? null : null
));
const benchmarkLoading = computed(() => Boolean(indicadorBenchmarkLoadingByKey.value[requestKey.value]));
const evolutionLoading = computed(() => Boolean(indicadorEvolucaoBenchmarkLoadingByKey.value[requestKey.value]));
const benchmarkError = computed(() => (
  indicadorBenchmarkErrorByKey.value[requestKey.value]
  ?? indicadorEvolucaoBenchmarkErrorByKey.value[requestKey.value]
  ?? null
));
const storeRequestLoading = computed(() => benchmarkLoading.value || evolutionLoading.value);
const isLoading = computed(() => isPanelUpdating.value || storeRequestLoading.value);
const hasRenderableData = computed(() => !!config.value && !!benchmarkData.value && !!evolutionData.value);
const isInitialLoading = computed(() => isLoading.value && !hasRenderableData.value);
const showLoadingOverlay = computed(() => isPanelUpdating.value && hasRenderableData.value);
const canRender = computed(() => hasRenderableData.value);

const municipioRows = computed(() => benchmarkData.value?.municipio?.rows ?? []);
const regiaoRows = computed(() => benchmarkData.value?.regiao_saude?.rows ?? []);
const copiedKey = ref(null);
const activeCnpjPreview = ref('');
const activeBenchmarkTab = ref(0);
const benchmarkVirtualScrollerOptions = {
  itemSize: 56,
  delay: 80,
  showLoader: false,
};
const municipioLabel = computed(() => benchmarkData.value?.municipio?.label ?? 'Município');
const regiaoLabel = computed(() => benchmarkData.value?.regiao_saude?.label ?? 'Região de Saúde');

const benchmarkCardTitle = computed(() => {
  if (activeBenchmarkTab.value === 1) {
    return `Comparação com estabelecimentos da Região de Saúde ${regiaoLabel.value}`;
  }
  return `Comparação com estabelecimentos do Município de ${municipioLabel.value}`;
});

function logPanelPerf(event, detail = {}) {
  if (!props.perfSession) return;
  logCnpjPerf(props.perfSession, event, {
    origem: 'indicator_detail_panel',
    indicador: props.indicatorKey,
    cnpj_ativo: activeCnpj.value,
    periodo_inicio: periodoInicio.value,
    periodo_fim: periodoFim.value,
    ...detail,
  });
}

function waitForPanelPaint() {
  return nextTick().then(() => new Promise((resolve) => {
    requestAnimationFrame(() => {
      requestAnimationFrame(resolve);
    });
  }));
}

const formatValueByType = (value, format) => {
  if (value == null) return '—';
  if (format === 'pct' || format === 'pct3') return formatPercent(value);
  if (format === 'val') return formatCurrencyFull(value);
  if (format === 'risco') return `${Number(value).toFixed(1)}x`;
  return formatNumberFull(value);
};

const formatIndicatorValue = (value) => formatValueByType(value, config.value?.valueFormat ?? 'pct');
const formatKpiValue = (kpi) => formatValueByType(kpi?.value, kpi?.formato);
const formatFinancialValue = (value) => (value == null ? '—' : formatCurrencyFull(value));
const benchmarkValueLabel = computed(() => config.value?.benchmarkValueLabel ?? config.value?.valueLabel ?? 'Valor');
const hasFinancialColumn = computed(() => Boolean(config.value?.financialLabel));

function formatCompactFinancialValue(value) {
  if (value == null) return '—';

  const numericValue = Number(value);
  if (!Number.isFinite(numericValue)) return '—';

  const absValue = Math.abs(numericValue);
  const compactRules = [
    { limit: 1_000_000_000, divisor: 1_000_000_000, suffix: 'bi' },
    { limit: 1_000_000, divisor: 1_000_000, suffix: 'mi' },
    { limit: 1_000, divisor: 1_000, suffix: 'k' },
  ];
  const rule = compactRules.find(item => absValue >= item.limit);

  if (!rule) return formatCurrencyFull(numericValue);

  const scaledValue = numericValue / rule.divisor;
  const formattedValue = scaledValue.toLocaleString('pt-BR', {
    minimumFractionDigits: 0,
    maximumFractionDigits: Math.abs(scaledValue) < 10 ? 1 : 0,
  });

  return `R$ ${formattedValue}${rule.suffix}`;
}

const statusLabel = (status) => {
  if (status === 'CRITICO') return 'CRÍTICO';
  if (status === 'ATENCAO') return 'ATENÇÃO';
  if (status === 'NORMAL') return 'NORMAL';
  return 'SEM DADOS';
};

const riskStatusClass = (status) => {
  if (status === 'CRITICO') return 'status-danger';
  if (status === 'ATENCAO') return 'status-warn';
  if (status === 'NORMAL') return 'status-success';
  return 'status-secondary';
};

const rowClass = (row) => ({
  'indicator-benchmark-target': row?.is_alvo,
  'indicator-benchmark-origin': normalizeCnpj(row?.cnpj) === baseCnpj.value && !isViewingTargetCnpj.value,
  'indicator-benchmark-clickable': normalizeCnpj(row?.cnpj) !== activeCnpj.value,
});

function copyAndSignal(text, key) {
  if (!text) return;
  navigator.clipboard.writeText(text);
  copiedKey.value = key;
  setTimeout(() => {
    if (copiedKey.value === key) copiedKey.value = null;
  }, 2000);
}

const formulaPanel = ref(null);
const targetRow = computed(() => {
  return municipioRows.value.find(row => row.is_alvo) || regiaoRows.value.find(row => row.is_alvo) || null;
});
const selectedBenchmarkRow = computed(() => {
  const currentCnpj = activeCnpj.value;
  return (
    municipioRows.value.find(row => normalizeCnpj(row?.cnpj) === currentCnpj)
    || regiaoRows.value.find(row => normalizeCnpj(row?.cnpj) === currentCnpj)
    || targetRow.value
    || null
  );
});
const activeCnpjTitle = computed(() => {
  const row = selectedBenchmarkRow.value;
  if (!row) return activeCnpjPreview.value || activeCnpj.value;
  if (normalizeCnpj(row.cnpj) !== activeCnpj.value && activeCnpjPreview.value) return activeCnpjPreview.value;
  return row.razao_social ? `${row.razao_social} (${row.cnpj})` : row.cnpj;
});

watch(
  () => [activeCnpjTitle.value, isViewingTargetCnpj.value],
  ([title, isTarget]) => {
    emit('active-cnpj-change', {
      title,
      isTarget,
    });
  },
  { immediate: true },
);

const selectedPeriodMemoryRows = computed(() => {
  const series = evolutionData.value?.series ?? [];
  const markedYears = evolutionData.value?.periodo_marcado?.anos ?? [];
  const markedYearSet = new Set(markedYears.map(year => Number(year)));

  if (!markedYearSet.size) return series;
  return series.filter(point => markedYearSet.has(Number(point.ano_base)));
});

const formatFormulaValue = (value, format) => {
  if (value == null) return '—';
  if (format === 'val') return formatCurrencyFull(value);
  if (format === 'pct') return formatPercent(value);
  return formatNumberFull(value);
};

const wait = (ms) => new Promise(resolve => setTimeout(resolve, ms));

async function selectBenchmarkRow(row) {
  const cnpj = normalizeCnpj(row?.cnpj);
  if (!cnpj || cnpj === activeCnpj.value || isLoading.value) return;

  if (props.externalCnpjNavigation) {
    emit('cnpj-selected', row);
    return;
  }

  activeCnpjPreview.value = row?.razao_social ? `${row.razao_social} (${row.cnpj})` : row?.cnpj ?? cnpj;
  isPanelUpdating.value = true;
  await nextTick();
  selectedCnpj.value = cnpj;
  formulaPanel.value?.hide?.();
}

function resetSelectedCnpj() {
  if (isLoading.value) return;
  activeCnpjPreview.value = '';
  selectedCnpj.value = baseCnpj.value;
  formulaPanel.value?.hide?.();
}

defineExpose({
  resetSelectedCnpj,
});

watch(
  () => [baseCnpj.value, props.indicatorKey],
  ([cnpj]) => {
    selectedCnpj.value = cnpj;
  },
  { immediate: true },
);

watch(
  () => [activeCnpj.value, props.indicatorKey, periodoInicio.value, periodoFim.value],
  async ([cnpj, indicatorKey]) => {
    if (!cnpj || !indicatorKey || !config.value) return;

    const nextRequestKey = requestKey.value;
    if (
      indicadorBenchmarkDataByKey.value[nextRequestKey]
      && indicadorEvolucaoBenchmarkDataByKey.value[nextRequestKey]
    ) {
      panelUpdateToken += 1;
      isPanelUpdating.value = false;
      renderedRequestKey.value = nextRequestKey;
      activeCnpjPreview.value = '';
      return;
    }

    const token = ++panelUpdateToken;
    const startedAt = performance.now();
    isPanelUpdating.value = true;

    try {
      await Promise.all([
        cnpjDetailStore.fetchIndicadorBenchmarkLocal(
          cnpj,
          indicatorKey,
          periodoInicio.value,
          periodoFim.value,
        ),
        cnpjDetailStore.fetchIndicadorEvolucaoBenchmark(
          cnpj,
          indicatorKey,
          periodoInicio.value,
          periodoFim.value,
        ),
      ]);

      const elapsed = performance.now() - startedAt;
      if (elapsed < PANEL_UPDATE_MIN_MS) {
        await wait(PANEL_UPDATE_MIN_MS - elapsed);
      }
    } finally {
      if (token === panelUpdateToken) {
        isPanelUpdating.value = false;
      }
    }
  },
  { immediate: true },
);

watch(
  () => [requestKey.value, currentBenchmarkData.value, currentEvolutionData.value],
  ([key, benchmark, evolution]) => {
    if (key && benchmark && evolution) {
      renderedRequestKey.value = key;
      activeCnpjPreview.value = '';
    }
  },
  { immediate: true },
);

watch(
  () => [displayedRequestKey.value, hasRenderableData.value, municipioRows.value.length, regiaoRows.value.length],
  async ([key, renderable, municipioCount, regiaoCount]) => {
    if (!key || !renderable) return;
    logPanelPerf('indicator_detail_panel_render_ready', {
      request_key: key,
      municipio_rows: municipioCount,
      regiao_rows: regiaoCount,
    });
    logPanelPerf('indicator_detail_table_rows_ready', {
      request_key: key,
      municipio_rows: municipioCount,
      regiao_rows: regiaoCount,
      total_rows: Number(municipioCount || 0) + Number(regiaoCount || 0),
    });
    await waitForPanelPaint();
    logPanelPerf('indicator_detail_panel_painted', {
      request_key: key,
      municipio_rows: municipioCount,
      regiao_rows: regiaoCount,
    });
  },
  { immediate: true },
);
</script>

<template>
  <div class="indicator-detail-shell">
    <div v-if="isInitialLoading" class="indicator-state">
      Carregando detalhamento do indicador...
    </div>

    <div v-else-if="benchmarkError && !hasRenderableData" class="indicator-state indicator-state--error">
      {{ benchmarkError }}
    </div>

    <div v-else-if="!canRender" class="indicator-state">
      Detalhamento do indicador indisponível.
    </div>

    <template v-else>
      <div v-if="showActiveCnpjHeader" class="indicator-active-cnpj">
        <div class="indicator-active-cnpj-text">
          <span>CNPJ em análise</span>
          <strong>{{ activeCnpjTitle }}</strong>
        </div>
        <button
          v-if="!isViewingTargetCnpj"
          type="button"
          class="return-target-button"
          @click="resetSelectedCnpj"
        >
          <i class="pi pi-undo" aria-hidden="true" />
          <span>Voltar ao CNPJ alvo</span>
        </button>
      </div>

      <div class="indicator-kpis">
        <div v-for="kpi in benchmarkData.kpis" :key="kpi.label" class="indicator-kpi">
          <span>{{ kpi.label }}</span>
          <strong>{{ formatKpiValue(kpi) }}</strong>
        </div>
        <div class="indicator-kpi indicator-period">
          <span>Período</span>
          <strong class="indicator-period-value">{{ periodoLabel }}</strong>
        </div>
      </div>

      <IndicatorEvolutionChart
        :data="evolutionData"
        :valueLabel="config.valueLabel"
      />

      <section class="indicator-benchmark-card">
        <div class="indicator-card-header">
          <div class="indicator-card-title">{{ benchmarkCardTitle }}</div>
          <div v-if="config?.formula && targetRow" class="formula-trigger-row">
            <button
              type="button"
              class="formula-trigger"
              aria-haspopup="dialog"
              @click="formulaPanel?.toggle($event)"
            >
              <i class="pi pi-calculator" aria-hidden="true" />
              <span class="formula-trigger-main">Fórmula</span>
              <span class="formula-trigger-subtitle">Memória de cálculo</span>
              <i class="pi pi-info-circle formula-trigger-info" aria-hidden="true" />
            </button>

            <OverlayPanel
              ref="formulaPanel"
              class="formula-overlay-panel"
              :dismissable="true"
              appendTo="body"
            >
              <div class="calculation-memory-content calculation-memory-content--floating">
                <div class="formula-overlay-heading">
                  <i class="pi pi-calculator" aria-hidden="true" />
                  <span>Memória de Cálculo</span>
                </div>
                <p class="formula-desc">{{ config.formula.description }}</p>

                <div class="formula-math-box">
                  <span class="math-label">Equação:</span>
                  <div class="math-formula">
                    <span class="math-term math-term--result">{{ config.title }}</span>
                    <span class="math-operator">=</span>
                    <template v-if="config.formula.factor === 100">
                      <span class="math-operator">(</span>
                    </template>
                    <span class="math-term">{{ config.formula.numeratorLabel }}</span>
                    <template v-if="config.formula.operator">
                      <span class="math-operator">{{ config.formula.operator }}</span>
                      <span class="math-term">{{ config.formula.denominatorLabel }}</span>
                    </template>
                    <template v-if="config.formula.factor === 100">
                      <span class="math-operator">)</span>
                      <span class="math-operator">×</span>
                      <span class="math-term">100</span>
                    </template>
                  </div>
                </div>

                <div v-if="selectedPeriodMemoryRows.length" class="memory-evolution-table-wrapper">
                  <div class="memory-table-title">Valores por Ano no Período</div>
                  <table class="memory-evolution-table">
                    <thead>
                      <tr>
                        <th>Ano</th>
                        <th class="text-right">{{ config.formula.numeratorLabel }}</th>
                        <th v-if="config.formula.operator" class="text-center">Operação</th>
                        <th v-if="config.formula.operator" class="text-right">{{ config.formula.denominatorLabel }}</th>
                        <th class="text-right">Resultado</th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr v-for="point in selectedPeriodMemoryRows" :key="point.ano_base">
                        <td class="font-semibold">{{ point.ano_base }}</td>
                        <td class="text-right">{{ formatFormulaValue(point.valor_numerador, config.formula.numeratorFormat) }}</td>
                        <td v-if="config.formula.operator" class="text-center font-bold text-muted">{{ config.formula.operator }}</td>
                        <td v-if="config.formula.operator" class="text-right">{{ formatFormulaValue(point.valor_denominador, config.formula.denominatorFormat) }}</td>
                        <td class="text-right font-semibold text-primary">
                          {{ formatValueByType(point.farmacia, config.valueFormat) }}
                        </td>
                      </tr>
                      <tr class="consolidated-row">
                        <td class="font-bold">Consolidado</td>
                        <td class="text-right font-bold">{{ formatFormulaValue(targetRow.valor_numerador, config.formula.numeratorFormat) }}</td>
                        <td v-if="config.formula.operator" class="text-center font-bold text-muted">{{ config.formula.operator }}</td>
                        <td v-if="config.formula.operator" class="text-right font-bold">{{ formatFormulaValue(targetRow.valor_denominador, config.formula.denominatorFormat) }}</td>
                        <td class="text-right font-bold text-success">
                          {{ formatValueByType(targetRow.valor, config.valueFormat) }}
                        </td>
                      </tr>
                    </tbody>
                  </table>
                </div>
              </div>
            </OverlayPanel>
          </div>
        </div>
        <TabView v-model:activeIndex="activeBenchmarkTab" class="indicator-benchmark-tabs">
          <TabPanel header="Município">
            <DataTable
              v-if="activeBenchmarkTab === 0"
              :value="municipioRows"
              :rowClass="rowClass"
              dataKey="cnpj"
              scrollable
              scrollHeight="300px"
              :virtualScrollerOptions="benchmarkVirtualScrollerOptions"
              class="indicator-table"
              size="small"
              @row-click="selectBenchmarkRow($event.data)"
            >
              <Column header="ESTABELECIMENTO" headerClass="col-name" bodyClass="col-name">
                <template #body="{ data }">
                  <div class="razao-block">
                    <span
                      class="razao-social-cell"
                      v-tooltip.top="data.razao_social"
                    >{{ data.razao_social ?? '—' }}</span>
                    <span class="cnpj-row">
                      <span
                        v-tooltip.top="data.is_matriz ? 'Matriz' : 'Filial'"
                        :class="data.is_matriz ? 'tipo-badge matriz' : 'tipo-badge filial'"
                      >
                        <i :class="data.is_matriz ? 'pi pi-home' : 'pi pi-building'" />
                      </span>
                      <span class="cnpj-text">{{ data.cnpj }}</span>
                      <i
                        :class="['pi', copiedKey === data.cnpj + '-cnpj' ? 'pi-check text-success' : 'pi-copy', 'copy-btn']"
                        v-tooltip.top="'Copiar CNPJ'"
                        @click.stop="copyAndSignal(data.cnpj, data.cnpj + '-cnpj')"
                      />
                    </span>
                  </div>
                </template>
              </Column>
              <Column header="MUNICÍPIO" headerClass="col-location" bodyClass="col-location">
                <template #body="{ data }">
                  <div class="loc-block">
                    <span
                      class="municipio-text"
                      v-tooltip.top="data.municipio"
                    >{{ data.municipio ?? '—' }}</span>
                    <span class="uf-tag">{{ data.uf }}</span>
                  </div>
                </template>
              </Column>
              <Column :header="benchmarkValueLabel.toUpperCase()" headerClass="col-indicator" bodyClass="col-indicator">
                <template #body="{ data }">
                  <div class="indicator-value-cell">
                    <span class="indicator-value-main">{{ formatIndicatorValue(data.valor) }}</span>
                  </div>
                </template>
              </Column>
              <Column v-if="hasFinancialColumn" :header="config.financialLabel.toUpperCase()" headerClass="col-financial" bodyClass="col-financial">
                <template #body="{ data }">{{ formatFinancialValue(data.valor_financeiro) }}</template>
              </Column>
              <Column header="MEDIANA REGIÃO" headerClass="col-median" bodyClass="col-median">
                <template #body="{ data }">{{ formatIndicatorValue(data.mediana_regiao) }}</template>
              </Column>
              <Column header="RISCO" headerClass="col-risk" bodyClass="col-risk">
                <template #body="{ data }">
                  <div class="risk-cell" :class="{ muted: data.risco_regiao == null }">
                    <span
                      v-if="data.risco_regiao != null"
                      class="risk-value"
                      :class="riskStatusClass(data.status)"
                    >
                      {{ Number(data.risco_regiao).toFixed(1) }}x
                    </span>
                    <span v-else>—</span>
                    <span
                      v-if="data.status"
                      class="risk-status"
                      :class="riskStatusClass(data.status)"
                    >
                      {{ statusLabel(data.status) }}
                    </span>
                  </div>
                </template>
              </Column>
              <Column header="VALOR MOVIMENTADO" headerClass="col-movement" bodyClass="col-movement">
                <template #body="{ data }">{{ formatFinancialValue(data.valor_movimentado) }}</template>
              </Column>
              <Column header="NÃO COMPROVAÇÃO" headerClass="col-noncomp" bodyClass="col-noncomp">
                <template #body="{ data }">
                  <div class="noncomp-cell" :class="{ muted: data.valor_sem_comprovacao == null }">
                    <span
                      class="noncomp-value"
                      :class="{ 'high-value-audit': data.valor_sem_comprovacao >= auditHighValue }"
                      v-tooltip.top="data.valor_sem_comprovacao != null ? formatFinancialValue(data.valor_sem_comprovacao) : null"
                    >
                      {{ formatCompactFinancialValue(data.valor_sem_comprovacao) }}
                    </span>
                    <span v-if="data.percentual_nao_comprovacao != null" class="noncomp-percent">
                      {{ Number(data.percentual_nao_comprovacao).toFixed(2) }}%
                    </span>
                  </div>
                </template>
              </Column>
              <Column header="CONEXÃO MS" headerClass="col-ms" bodyClass="col-ms">
                <template #body="{ data }">
                  <span :class="data.is_conexao_ativa ? 'ms-status ms-status--ativo' : 'ms-status ms-status--inativo'">
                    {{ data.is_conexao_ativa ? 'SIM' : 'NÃO' }}
                  </span>
                </template>
              </Column>
            </DataTable>
          </TabPanel>

          <TabPanel header="Região de Saúde">
            <DataTable
              v-if="activeBenchmarkTab === 1"
              :value="regiaoRows"
              :rowClass="rowClass"
              dataKey="cnpj"
              scrollable
              scrollHeight="300px"
              :virtualScrollerOptions="benchmarkVirtualScrollerOptions"
              class="indicator-table"
              size="small"
              @row-click="selectBenchmarkRow($event.data)"
            >
              <Column header="ESTABELECIMENTO" headerClass="col-name" bodyClass="col-name">
                <template #body="{ data }">
                  <div class="razao-block">
                    <span
                      class="razao-social-cell"
                      v-tooltip.top="data.razao_social"
                    >{{ data.razao_social ?? '—' }}</span>
                    <span class="cnpj-row">
                      <span
                        v-tooltip.top="data.is_matriz ? 'Matriz' : 'Filial'"
                        :class="data.is_matriz ? 'tipo-badge matriz' : 'tipo-badge filial'"
                      >
                        <i :class="data.is_matriz ? 'pi pi-home' : 'pi pi-building'" />
                      </span>
                      <span class="cnpj-text">{{ data.cnpj }}</span>
                      <i
                        :class="['pi', copiedKey === data.cnpj + '-cnpj' ? 'pi-check text-success' : 'pi-copy', 'copy-btn']"
                        v-tooltip.top="'Copiar CNPJ'"
                        @click.stop="copyAndSignal(data.cnpj, data.cnpj + '-cnpj')"
                      />
                    </span>
                  </div>
                </template>
              </Column>
              <Column header="MUNICÍPIO" headerClass="col-location" bodyClass="col-location">
                <template #body="{ data }">
                  <div class="loc-block">
                    <span
                      class="municipio-text"
                      v-tooltip.top="data.municipio"
                    >{{ data.municipio ?? '—' }}</span>
                    <span class="uf-tag">{{ data.uf }}</span>
                  </div>
                </template>
              </Column>
              <Column :header="benchmarkValueLabel.toUpperCase()" headerClass="col-indicator" bodyClass="col-indicator">
                <template #body="{ data }">
                  <div class="indicator-value-cell">
                    <span class="indicator-value-main">{{ formatIndicatorValue(data.valor) }}</span>
                  </div>
                </template>
              </Column>
              <Column v-if="hasFinancialColumn" :header="config.financialLabel.toUpperCase()" headerClass="col-financial" bodyClass="col-financial">
                <template #body="{ data }">{{ formatFinancialValue(data.valor_financeiro) }}</template>
              </Column>
              <Column header="MEDIANA REGIÃO" headerClass="col-median" bodyClass="col-median">
                <template #body="{ data }">{{ formatIndicatorValue(data.mediana_regiao) }}</template>
              </Column>
              <Column header="RISCO" headerClass="col-risk" bodyClass="col-risk">
                <template #body="{ data }">
                  <div class="risk-cell" :class="{ muted: data.risco_regiao == null }">
                    <span
                      v-if="data.risco_regiao != null"
                      class="risk-value"
                      :class="riskStatusClass(data.status)"
                    >
                      {{ Number(data.risco_regiao).toFixed(1) }}x
                    </span>
                    <span v-else>—</span>
                    <span
                      v-if="data.status"
                      class="risk-status"
                      :class="riskStatusClass(data.status)"
                    >
                      {{ statusLabel(data.status) }}
                    </span>
                  </div>
                </template>
              </Column>
              <Column header="VALOR MOVIMENTADO" headerClass="col-movement" bodyClass="col-movement">
                <template #body="{ data }">{{ formatFinancialValue(data.valor_movimentado) }}</template>
              </Column>
              <Column header="NÃO COMPROVAÇÃO" headerClass="col-noncomp" bodyClass="col-noncomp">
                <template #body="{ data }">
                  <div class="noncomp-cell" :class="{ muted: data.valor_sem_comprovacao == null }">
                    <span
                      class="noncomp-value"
                      :class="{ 'high-value-audit': data.valor_sem_comprovacao >= auditHighValue }"
                      v-tooltip.top="data.valor_sem_comprovacao != null ? formatFinancialValue(data.valor_sem_comprovacao) : null"
                    >
                      {{ formatCompactFinancialValue(data.valor_sem_comprovacao) }}
                    </span>
                    <span v-if="data.percentual_nao_comprovacao != null" class="noncomp-percent">
                      {{ Number(data.percentual_nao_comprovacao).toFixed(2) }}%
                    </span>
                  </div>
                </template>
              </Column>
              <Column header="CONEXÃO MS" headerClass="col-ms" bodyClass="col-ms">
                <template #body="{ data }">
                  <span :class="data.is_conexao_ativa ? 'ms-status ms-status--ativo' : 'ms-status ms-status--inativo'">
                    {{ data.is_conexao_ativa ? 'SIM' : 'NÃO' }}
                  </span>
                </template>
              </Column>
            </DataTable>
          </TabPanel>
        </TabView>
      </section>

      <transition name="ind-overlay-fade">
        <div
          v-if="showLoadingOverlay"
          class="indicator-loading-overlay"
          aria-live="polite"
          aria-busy="true"
        >
          <div class="indicator-loading-overlay__box">
            <i class="pi pi-spin pi-spinner" aria-hidden="true" />
            <span>Atualizando análise...</span>
          </div>
        </div>
      </transition>
    </template>
  </div>
</template>

<style scoped>
.indicator-detail-shell {
  position: relative;
  display: flex;
  flex-direction: column;
  gap: 0.45rem;
  min-height: 560px;
}

.indicator-loading-overlay {
  position: absolute;
  inset: 0;
  z-index: 5;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 12px;
  background: color-mix(in srgb, var(--bg-color) 62%, transparent);
  backdrop-filter: blur(2px);
}

.indicator-loading-overlay__box {
  display: inline-flex;
  align-items: center;
  gap: 0.75rem;
  padding: 0.9rem 1.1rem;
  border: 1px solid var(--card-border);
  border-radius: 10px;
  background: var(--card-bg);
  color: var(--text-color-85);
  box-shadow: 0 12px 28px color-mix(in srgb, var(--text-color-85) 12%, transparent);
  font-size: 0.86rem;
  font-weight: 600;
}

.indicator-loading-overlay__box i {
  color: var(--primary-color);
  font-size: 1rem;
}

.ind-overlay-fade-enter-active,
.ind-overlay-fade-leave-active {
  transition: opacity 0.18s ease;
}

.ind-overlay-fade-enter-from,
.ind-overlay-fade-leave-to {
  opacity: 0;
}

.indicator-active-cnpj {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.85rem;
  padding: 0.58rem 0.72rem;
  border: 1px solid var(--card-border);
  border-radius: 10px;
  background: color-mix(in srgb, var(--text-color-85) 3%, var(--card-bg));
}

.indicator-active-cnpj-text {
  display: flex;
  flex-direction: column;
  min-width: 0;
  gap: 0.16rem;
}

.indicator-active-cnpj-text span {
  color: var(--text-muted);
  font-size: 0.72rem;
  font-weight: 700;
  letter-spacing: 0.04em;
  text-transform: uppercase;
}

.indicator-active-cnpj-text strong {
  overflow: hidden;
  color: var(--text-color-85);
  font-size: 0.86rem;
  font-weight: 600;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.return-target-button {
  display: inline-flex;
  align-items: center;
  flex-shrink: 0;
  gap: 0.42rem;
  padding: 0.38rem 0.62rem;
  border: 1px solid var(--card-border);
  border-radius: 999px;
  background: color-mix(in srgb, var(--text-color-85) 3%, var(--card-bg));
  color: var(--text-color-85);
  cursor: pointer;
  font-size: 0.72rem;
  font-weight: 700;
  transition: background 0.16s ease, border-color 0.16s ease, transform 0.16s ease;
}

.return-target-button:hover,
.return-target-button:focus-visible {
  border-color: color-mix(in srgb, var(--text-color-85) 28%, var(--card-border));
  background: color-mix(in srgb, var(--text-color-85) 7%, var(--card-bg));
  outline: none;
  transform: translateY(-1px);
}

.indicator-kpis {
  display: flex;
  gap: 0.75rem;
}

.indicator-kpi,
.indicator-benchmark-card {
  border: 1px solid var(--card-border);
  background: var(--card-bg);
  border-radius: 10px;
}

.indicator-kpi {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
  padding: 0.75rem 0.9rem;
}

.indicator-kpi.indicator-period {
  flex: 0 0 auto;
  min-width: 180px;
  background: color-mix(in srgb, var(--primary-color) 8%, var(--card-bg));
  border-color: color-mix(in srgb, var(--primary-color) 20%, var(--card-border));
}

.indicator-period-value {
  color: var(--primary-color) !important;
}

.indicator-kpi span,
.indicator-scope-label {
  font-size: 0.78rem;
  color: var(--text-muted);
}

.indicator-kpi strong {
  font-size: 0.98rem;
  font-weight: 600;
  color: var(--text-color-85);
}

.indicator-benchmark-card {
  min-height: 390px;
  padding: 0.9rem;
}

.indicator-card-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.85rem;
  margin-bottom: 0.55rem;
}

.indicator-card-title {
  font-size: 0.9rem;
  font-weight: 600;
  color: var(--text-color-85);
}

.indicator-scope-label {
  margin: 0.15rem 0 0.65rem;
  font-weight: 600;
}

.indicator-state {
  min-height: 260px;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--text-muted);
}

.indicator-state--error {
  color: var(--risk-indicator-critical);
}

.razao-block {
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
  min-width: 0;
  overflow: hidden;
}

.razao-social-cell {
  display: block;
  max-width: 100%;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  cursor: default;
  font-size: 0.76rem;
  color: var(--text-color-85);
}

.cnpj-row {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.tipo-badge {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 1.25rem;
  height: 1.25rem;
  flex-shrink: 0;
  border-radius: 6px;
  font-size: 0.68rem;
  backdrop-filter: blur(6px);
  -webkit-backdrop-filter: blur(6px);
}

.tipo-badge.matriz {
  background: color-mix(in srgb, var(--accent-indigo) 18%, transparent);
  border: 1px solid color-mix(in srgb, var(--accent-indigo) 35%, transparent);
  color: var(--accent-indigo);
}

.tipo-badge.filial {
  background: color-mix(in srgb, var(--status-secondary) 12%, transparent);
  border: 1px solid color-mix(in srgb, var(--status-secondary) 20%, transparent);
  color: var(--status-secondary);
}

.cnpj-text {
  display: block;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  color: var(--text-muted);
  font-size: 0.76rem;
  letter-spacing: 0.01em;
}

.copy-btn {
  display: inline-flex;
  justify-content: center;
  width: 1.4rem;
  flex-shrink: 0;
  cursor: pointer;
  color: var(--text-muted);
  font-size: 0.85rem;
  opacity: 0.4;
  transition: all 0.2s;
}

.copy-btn.text-success {
  color: var(--status-success) !important;
  opacity: 1 !important;
}

.copy-btn:hover {
  opacity: 1 !important;
  color: var(--primary-color);
  transform: scale(1.1);
}

.copy-btn:active {
  transform: scale(0.9);
}

.loc-block {
  display: flex;
  flex-direction: column;
  gap: 0.2rem;
  min-width: 0;
  overflow: hidden;
}

.municipio-text {
  display: block;
  max-width: 100%;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 0.88rem;
}

.uf-tag {
  display: inline-block;
  align-self: flex-start;
  padding: 0.05rem 0.3rem;
  background: color-mix(in srgb, var(--primary-color) 12%, var(--card-bg));
  color: var(--primary-color);
  border-radius: 4px;
  font-size: 0.78rem;
  font-weight: 600;
}

.ms-status {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 3.4rem;
  padding: 0.16rem 0.45rem;
  border-radius: 999px;
  font-size: 0.68rem;
  font-weight: 700;
  letter-spacing: 0.04em;
}

.ms-status--ativo {
  color: var(--risk-indicator-normal);
  background: color-mix(in srgb, var(--risk-indicator-normal) 12%, transparent);
}

.ms-status--inativo {
  color: var(--text-muted);
  background: color-mix(in srgb, var(--text-muted) 10%, transparent);
}

.noncomp-cell {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 0.12rem;
  line-height: 1.1;
}

.noncomp-cell.muted {
  color: var(--text-muted);
}

.noncomp-value {
  color: var(--text-color-85);
  font-weight: 600;
  white-space: nowrap;
}

.noncomp-percent {
  color: var(--text-muted);
  font-size: 0.68rem;
  font-weight: 600;
  white-space: nowrap;
}

.risk-cell {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 0.14rem;
  min-width: 0;
}

.risk-value {
  display: block;
  padding: 0 !important;
  background: transparent !important;
  border: 0 !important;
  font-size: 0.88rem;
  font-weight: 600;
  line-height: 1.1;
}

.risk-status {
  display: block;
  max-width: 100%;
  padding: 0 !important;
  background: transparent !important;
  border: 0 !important;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 0.78rem;
  font-weight: 500;
  line-height: 1;
  letter-spacing: 0.03em;
}

.risk-value.status-danger,
.risk-status.status-danger {
  color: var(--risk-high);
}

.risk-value.status-warn,
.risk-status.status-warn {
  color: var(--risk-medium);
}

.risk-value.status-success,
.risk-status.status-success {
  color: var(--text-muted) !important;
}

.risk-value.status-secondary,
.risk-status.status-secondary {
  color: var(--text-muted);
}

.high-value-audit {
  color: var(--risk-high);
  display: inline-flex;
  align-items: center;
  justify-content: flex-end;
  gap: 0.4rem;
  padding: 0.15rem 0.65rem;
  background: color-mix(in srgb, var(--risk-high) 10%, transparent);
  border-left: 3px solid var(--risk-high);
  border-radius: 0 6px 6px 0;
  font-size: 0.75rem;
  font-weight: 600;
}

:deep(.indicator-benchmark-tabs .p-tabview-nav) {
  background: transparent;
  border-color: var(--card-border);
}

:deep(.indicator-benchmark-tabs .p-tabview-panels) {
  min-height: 310px;
  padding: 0.55rem 0 0;
  background: transparent;
}

:deep(.indicator-benchmark-tabs .p-tabview-nav-link) {
  padding: 0.68rem 1.05rem;
  background: transparent;
  color: var(--text-color-85);
  border-color: var(--card-border);
  font-size: 0.78rem;
  font-weight: 700;
  line-height: 1.15;
}

:deep(.indicator-table .p-datatable-thead > tr > th) {
  font-size: 0.78rem;
  font-weight: 600;
  background: var(--card-bg);
  color: var(--text-color-85);
  border-color: var(--card-border);
}

:deep(.indicator-table .p-datatable-table) {
  table-layout: fixed;
  width: 100%;
}

:deep(.indicator-table .p-datatable-wrapper) {
  min-height: 300px;
}

:deep(.indicator-table .p-datatable-tbody > tr > td) {
  overflow: hidden;
  font-size: 0.8rem;
  background: var(--card-bg);
  color: var(--text-color-85);
  border-color: var(--card-border);
}

:deep(.indicator-table .col-name) {
  width: 22%;
}

:deep(.indicator-table .col-location) {
  width: 11%;
}

:deep(.indicator-table .col-movement) {
  width: 11%;
  text-align: right;
}

:deep(.indicator-table .col-noncomp) {
  width: 11%;
  text-align: right;
}

:deep(.indicator-table .col-indicator) {
  width: 10%;
  text-align: right;
}

:deep(.indicator-table th.col-indicator) {
  color: var(--primary-color);
}

:deep(.indicator-table td.col-indicator) {
  padding-top: 0.42rem;
  padding-bottom: 0.42rem;
}

:deep(.indicator-table .col-financial) {
  width: 10%;
  text-align: right;
}

:deep(.indicator-table .col-median) {
  width: 10%;
  text-align: right;
}

:deep(.indicator-table .col-risk) {
  width: 10%;
  text-align: center;
}

:deep(.indicator-table .col-ms) {
  width: 8%;
  text-align: center;
}

:deep(.indicator-table .col-movement .p-column-header-content),
:deep(.indicator-table .col-noncomp .p-column-header-content),
:deep(.indicator-table .col-indicator .p-column-header-content),
:deep(.indicator-table .col-financial .p-column-header-content),
:deep(.indicator-table .col-median .p-column-header-content) {
  justify-content: flex-end;
}

:deep(.indicator-table .col-risk .p-column-header-content),
:deep(.indicator-table .col-ms .p-column-header-content) {
  justify-content: center;
}

:deep(.indicator-table .p-datatable-tbody > tr:nth-child(even) > td) {
  background: color-mix(in srgb, var(--text-color-85) 3%, var(--card-bg));
}

:deep(.indicator-table .p-datatable-tbody > tr:hover > td) {
  background: color-mix(in srgb, var(--primary-color) 8%, var(--card-bg));
}

:deep(.indicator-table .p-datatable-tbody > tr.indicator-benchmark-clickable) {
  cursor: pointer;
}

:deep(.indicator-table .p-datatable-tbody > tr.indicator-benchmark-target > td),
:deep(.indicator-table .p-datatable-tbody > tr.indicator-benchmark-target:nth-child(even) > td) {
  background: color-mix(in srgb, var(--primary-color) 7%, var(--card-bg));
  color: var(--text-color-85);
}

:deep(.indicator-table .p-datatable-tbody > tr.indicator-benchmark-target > td:first-child) {
  box-shadow: inset 3px 0 0 color-mix(in srgb, var(--primary-color) 60%, var(--card-bg));
}

:deep(.indicator-table .p-datatable-tbody > tr.indicator-benchmark-origin > td:first-child) {
  box-shadow: inset 3px 0 0 color-mix(in srgb, var(--primary-color) 55%, var(--text-muted));
}

.indicator-value-cell {
  display: inline-flex;
  justify-content: flex-end;
  min-width: 5.4rem;
  padding: 0.38rem 0.52rem;
  border-left: 3px solid var(--primary-color);
  border-radius: 6px;
  background: color-mix(in srgb, var(--primary-color) 9%, var(--card-bg));
  color: var(--text-color-85);
}

.indicator-value-main {
  font-size: 0.82rem;
  font-weight: 650;
  line-height: 1.15;
  white-space: nowrap;
}

.formula-trigger-row {
  display: flex;
  justify-content: flex-end;
  flex-shrink: 0;
}

.formula-trigger {
  display: inline-flex;
  align-items: center;
  gap: 0.45rem;
  padding: 0.42rem 0.68rem;
  border: 1px solid color-mix(in srgb, var(--primary-color) 38%, var(--card-border));
  border-radius: 999px;
  background: color-mix(in srgb, var(--primary-color) 7%, var(--card-bg));
  color: var(--text-color-85);
  cursor: pointer;
  font-size: 0.74rem;
  line-height: 1;
  transition: background 0.16s ease, border-color 0.16s ease, color 0.16s ease, transform 0.16s ease;
}

.formula-trigger:hover,
.formula-trigger:focus-visible {
  border-color: var(--primary-color);
  background: color-mix(in srgb, var(--primary-color) 13%, var(--card-bg));
  color: var(--primary-color);
  outline: none;
  transform: translateY(-1px);
}

.formula-trigger-main {
  font-weight: 700;
}

.formula-trigger-subtitle {
  color: var(--text-muted);
  font-size: 0.7rem;
  font-weight: 600;
}

.formula-trigger-info {
  color: var(--primary-color);
  font-size: 0.78rem;
}

:deep(.formula-overlay-panel.p-overlaypanel) {
  width: min(720px, calc(100vw - 48px));
  border-color: var(--card-border);
  background: var(--card-bg);
}

:deep(.formula-overlay-panel .p-overlaypanel-content) {
  padding: 0;
  background: var(--card-bg);
  color: var(--text-color-85);
}

.calculation-memory-content {
  padding: 0.9rem;
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
}

.calculation-memory-content--floating {
  max-height: min(560px, calc(100vh - 140px));
  overflow: auto;
}

.formula-overlay-heading {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding-bottom: 0.65rem;
  border-bottom: 1px solid var(--card-border);
  color: var(--text-color-85);
  font-size: 0.82rem;
  font-weight: 700;
}

.formula-overlay-heading i {
  color: var(--primary-color);
}

.formula-desc {
  font-size: 0.76rem;
  color: var(--text-muted);
  line-height: 1.35;
  margin: 0;
}

.formula-math-box {
  background: color-mix(in srgb, var(--text-muted) 5%, transparent);
  border-radius: 6px;
  padding: 0.5rem 0.75rem;
  display: flex;
  align-items: center;
  gap: 0.75rem;
  flex-wrap: wrap;
}

.math-label {
  font-size: 0.72rem;
  font-weight: 700;
  color: var(--text-muted);
  text-transform: uppercase;
}

.math-formula {
  display: flex;
  align-items: center;
  gap: 0.35rem;
  font-family: monospace;
  font-size: 0.78rem;
  flex-wrap: wrap;
}

.math-term {
  background: color-mix(in srgb, var(--primary-color) 12%, var(--card-bg));
  color: var(--primary-color);
  padding: 0.1rem 0.4rem;
  border-radius: 4px;
  font-weight: 600;
}

.math-term--result {
  background: color-mix(in srgb, var(--accent-indigo) 12%, var(--card-bg));
  color: var(--accent-indigo);
}

.math-operator {
  color: var(--text-muted);
  font-weight: bold;
}

.memory-evolution-table-wrapper {
  display: flex;
  flex-direction: column;
  gap: 0.4rem;
  margin-top: 0.25rem;
}

.memory-table-title {
  font-size: 0.74rem;
  font-weight: 700;
  color: var(--text-muted);
  text-transform: uppercase;
}

.memory-evolution-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 0.75rem;
}

.memory-evolution-table th {
  text-align: left;
  padding: 0.35rem 0.5rem;
  color: var(--text-muted);
  font-weight: 600;
  border-bottom: 2px solid var(--card-border);
}

.memory-evolution-table td {
  padding: 0.45rem 0.5rem;
  border-bottom: 1px solid var(--card-border);
}

.memory-evolution-table tr:hover td {
  background: color-mix(in srgb, var(--primary-color) 3%, transparent);
}

.memory-evolution-table .consolidated-row td {
  background: color-mix(in srgb, var(--status-success) 6%, var(--card-bg));
  border-top: 2px solid var(--card-border);
  border-bottom: 0;
}

</style>
