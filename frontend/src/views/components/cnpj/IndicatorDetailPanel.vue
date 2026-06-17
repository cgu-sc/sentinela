<script setup>
import { computed, ref, watch } from 'vue';
import { storeToRefs } from 'pinia';
import DataTable from 'primevue/datatable';
import Column from 'primevue/column';
import TabView from 'primevue/tabview';
import TabPanel from 'primevue/tabpanel';
import { useCnpjDetailStore } from '@/stores/cnpjDetail';
import { useFilterStore } from '@/stores/filters';
import { useFormatting } from '@/composables/useFormatting';
import { INDICATOR_DETAIL_CONFIG } from '@/config/indicatorDetailConfig';
import { AUDIT_THRESHOLDS } from '@/config/riskConfig';
import IndicatorEvolutionChart from './IndicatorEvolutionChart.vue';

const props = defineProps({
  cnpj: { type: String, default: '' },
  indicatorKey: { type: String, default: '' },
});

const cnpjDetailStore = useCnpjDetailStore();
const filterStore = useFilterStore();
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

const requestKey = computed(() => (
  `${props.cnpj}|${props.indicatorKey}|${periodoInicio.value || ''}|${periodoFim.value || ''}`
));

const benchmarkData = computed(() => indicadorBenchmarkDataByKey.value[requestKey.value] ?? null);
const evolutionData = computed(() => indicadorEvolucaoBenchmarkDataByKey.value[requestKey.value] ?? null);
const benchmarkLoading = computed(() => Boolean(indicadorBenchmarkLoadingByKey.value[requestKey.value]));
const evolutionLoading = computed(() => Boolean(indicadorEvolucaoBenchmarkLoadingByKey.value[requestKey.value]));
const benchmarkError = computed(() => (
  indicadorBenchmarkErrorByKey.value[requestKey.value]
  ?? indicadorEvolucaoBenchmarkErrorByKey.value[requestKey.value]
  ?? null
));
const isLoading = computed(() => benchmarkLoading.value || evolutionLoading.value);
const canRender = computed(() => !!config.value && !!benchmarkData.value && !!evolutionData.value && !isLoading.value);

const municipioRows = computed(() => benchmarkData.value?.municipio?.rows ?? []);
const regiaoRows = computed(() => benchmarkData.value?.regiao_saude?.rows ?? []);
const copiedKey = ref(null);
const municipioLabel = computed(() => benchmarkData.value?.municipio?.label ?? 'Município');
const regiaoLabel = computed(() => benchmarkData.value?.regiao_saude?.label ?? 'Região de Saúde');

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
});

function copyAndSignal(text, key) {
  if (!text) return;
  navigator.clipboard.writeText(text);
  copiedKey.value = key;
  setTimeout(() => {
    if (copiedKey.value === key) copiedKey.value = null;
  }, 2000);
}

watch(
  () => [props.cnpj, props.indicatorKey, periodoInicio.value, periodoFim.value],
  async ([cnpj, indicatorKey]) => {
    if (!cnpj || !indicatorKey || !config.value) return;
    await cnpjDetailStore.fetchIndicadorBenchmarkLocal(
      cnpj,
      indicatorKey,
      periodoInicio.value,
      periodoFim.value,
    );
    await cnpjDetailStore.fetchIndicadorEvolucaoBenchmark(
      cnpj,
      indicatorKey,
      periodoInicio.value,
      periodoFim.value,
    );
  },
  { immediate: true },
);
</script>

<template>
  <div class="indicator-detail-shell">
    <div v-if="isLoading" class="indicator-state">
      Carregando detalhamento do indicador...
    </div>

    <div v-else-if="benchmarkError" class="indicator-state indicator-state--error">
      {{ benchmarkError }}
    </div>

    <div v-else-if="!canRender" class="indicator-state">
      Detalhamento do indicador indisponível.
    </div>

    <template v-else>
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
        <div class="indicator-card-title">Comparação com estabelecimentos do território</div>
        <TabView class="indicator-benchmark-tabs">
          <TabPanel header="Município">
            <div class="indicator-scope-label">{{ municipioLabel }}</div>
            <DataTable
              :value="municipioRows"
              :rowClass="rowClass"
              dataKey="cnpj"
              scrollable
              scrollHeight="300px"
              class="indicator-table"
              size="small"
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
              <Column header="VALOR MOVIMENTADO" headerClass="col-movement" bodyClass="col-movement">
                <template #body="{ data }">{{ formatFinancialValue(data.valor_movimentado) }}</template>
              </Column>
              <Column header="NÃO COMPROVAÇÃO" headerClass="col-noncomp" bodyClass="col-noncomp">
                <template #body="{ data }">
                  <div class="noncomp-cell" :class="{ muted: data.valor_sem_comprovacao == null }">
                    <span
                      class="noncomp-value"
                      :class="{ 'high-value-audit': data.valor_sem_comprovacao >= AUDIT_THRESHOLDS.HIGH_VALUE }"
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
              <Column :header="config.valueLabel.toUpperCase()" headerClass="col-indicator" bodyClass="col-indicator">
                <template #body="{ data }">{{ formatIndicatorValue(data.valor) }}</template>
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
            <div class="indicator-scope-label">{{ regiaoLabel }}</div>
            <DataTable
              :value="regiaoRows"
              :rowClass="rowClass"
              dataKey="cnpj"
              scrollable
              scrollHeight="300px"
              class="indicator-table"
              size="small"
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
              <Column header="VALOR MOVIMENTADO" headerClass="col-movement" bodyClass="col-movement">
                <template #body="{ data }">{{ formatFinancialValue(data.valor_movimentado) }}</template>
              </Column>
              <Column header="NÃO COMPROVAÇÃO" headerClass="col-noncomp" bodyClass="col-noncomp">
                <template #body="{ data }">
                  <div class="noncomp-cell" :class="{ muted: data.valor_sem_comprovacao == null }">
                    <span
                      class="noncomp-value"
                      :class="{ 'high-value-audit': data.valor_sem_comprovacao >= AUDIT_THRESHOLDS.HIGH_VALUE }"
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
              <Column :header="config.valueLabel.toUpperCase()" headerClass="col-indicator" bodyClass="col-indicator">
                <template #body="{ data }">{{ formatIndicatorValue(data.valor) }}</template>
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
    </template>
  </div>
</template>

<style scoped>
.indicator-detail-shell {
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
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
  color: var(--text-color);
}

.indicator-benchmark-card {
  min-height: 390px;
  padding: 0.9rem;
}

.indicator-card-title {
  margin-bottom: 0.55rem;
  font-size: 0.9rem;
  font-weight: 600;
  color: var(--text-color);
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
  color: var(--text-color);
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
  color: var(--text-color);
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
  padding: 0.55rem 0.9rem;
  background: transparent;
  color: var(--text-color);
  border-color: var(--card-border);
  font-size: 0.78rem;
  font-weight: 700;
  line-height: 1.15;
}

:deep(.indicator-table .p-datatable-thead > tr > th) {
  font-size: 0.78rem;
  font-weight: 600;
  background: var(--card-bg);
  color: var(--text-color);
  border-color: var(--card-border);
}

:deep(.indicator-table .p-datatable-table) {
  table-layout: fixed;
  width: 100%;
}

:deep(.indicator-table .p-datatable-tbody > tr > td) {
  overflow: hidden;
  font-size: 0.8rem;
  background: var(--card-bg);
  color: var(--text-color);
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
  background: color-mix(in srgb, var(--text-color) 3%, var(--card-bg));
}

:deep(.indicator-table .p-datatable-tbody > tr:hover > td) {
  background: color-mix(in srgb, var(--primary-color) 8%, var(--card-bg));
}

:deep(.indicator-table .p-datatable-tbody > tr.indicator-benchmark-target > td),
:deep(.indicator-table .p-datatable-tbody > tr.indicator-benchmark-target:nth-child(even) > td) {
  background: color-mix(in srgb, var(--primary-color) 15%, var(--card-bg));
  color: var(--text-color);
}

:deep(.indicator-table .p-datatable-tbody > tr.indicator-benchmark-target > td:first-child) {
  box-shadow: inset 3px 0 0 var(--primary-color);
}
</style>
