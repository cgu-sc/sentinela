<script setup>
import { computed, watch } from 'vue';
import { storeToRefs } from 'pinia';
import Dialog from 'primevue/dialog';
import DataTable from 'primevue/datatable';
import Column from 'primevue/column';
import TabView from 'primevue/tabview';
import TabPanel from 'primevue/tabpanel';
import { useCnpjDetailStore } from '@/stores/cnpjDetail';
import { useFilterStore } from '@/stores/filters';
import { useFormatting } from '@/composables/useFormatting';
import { INDICATOR_DETAIL_CONFIG } from '@/config/indicatorDetailConfig';

const props = defineProps({
  modelValue: { type: Boolean, default: false },
  cnpj: { type: String, default: '' },
  indicatorKey: { type: String, default: '' },
});

const emit = defineEmits(['update:modelValue']);

const cnpjDetailStore = useCnpjDetailStore();
const filterStore = useFilterStore();
const {
  indicadorBenchmarkDataByKey,
  indicadorBenchmarkLoadingByKey,
  indicadorBenchmarkErrorByKey,
} = storeToRefs(cnpjDetailStore);
const { formatCurrencyFull, formatNumberFull, formatPercent, toLocalISO } = useFormatting();

const config = computed(() => INDICATOR_DETAIL_CONFIG[props.indicatorKey] ?? null);

const periodoInicio = computed(() => {
  const [start] = filterStore.periodo ?? [];
  return start ? toLocalISO(start) : null;
});

const periodoFim = computed(() => {
  const [, end] = filterStore.periodo ?? [];
  return end ? toLocalISO(end) : null;
});

const requestKey = computed(() => (
  `${props.cnpj}|${props.indicatorKey}|${periodoInicio.value || ''}|${periodoFim.value || ''}`
));

const benchmarkData = computed(() => indicadorBenchmarkDataByKey.value[requestKey.value] ?? null);
const benchmarkLoading = computed(() => Boolean(indicadorBenchmarkLoadingByKey.value[requestKey.value]));
const benchmarkError = computed(() => indicadorBenchmarkErrorByKey.value[requestKey.value] ?? null);
const canRenderDialog = computed(() => !!config.value && !!benchmarkData.value && !benchmarkLoading.value);

const dialogTitle = computed(() => config.value?.title ?? 'Detalhamento do Indicador');
const municipioRows = computed(() => benchmarkData.value?.municipio?.rows ?? []);
const regiaoRows = computed(() => benchmarkData.value?.regiao_saude?.rows ?? []);
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

const statusClass = (status) => {
  if (status === 'CRITICO') return 'indicator-status indicator-status--critico';
  if (status === 'ATENCAO') return 'indicator-status indicator-status--atencao';
  if (status === 'NORMAL') return 'indicator-status indicator-status--normal';
  return 'indicator-status indicator-status--sem-dados';
};

const statusLabel = (status) => {
  if (status === 'CRITICO') return 'CRÍTICO';
  if (status === 'ATENCAO') return 'ATENÇÃO';
  if (status === 'NORMAL') return 'NORMAL';
  return 'SEM DADOS';
};

const rowClass = (row) => ({
  'indicator-benchmark-target': row?.is_alvo,
});

watch(
  () => [props.modelValue, props.cnpj, props.indicatorKey, periodoInicio.value, periodoFim.value],
  async ([visible, cnpj, indicatorKey]) => {
    if (!visible || !cnpj || !indicatorKey || !config.value) return;
    await cnpjDetailStore.fetchIndicadorBenchmarkLocal(
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
  <Dialog
    v-if="canRenderDialog"
    :visible="modelValue"
    :header="dialogTitle"
    modal
    class="indicator-detail-dialog"
    :style="{ width: 'min(1180px, 94vw)' }"
    @update:visible="emit('update:modelValue', $event)"
  >
    <div class="indicator-detail-shell">
      <div v-if="benchmarkError" class="indicator-state indicator-state--error">
        {{ benchmarkError }}
      </div>

      <template v-else>
        <div class="indicator-kpis">
          <div v-for="kpi in benchmarkData.kpis" :key="kpi.label" class="indicator-kpi">
            <span>{{ kpi.label }}</span>
            <strong>{{ formatKpiValue(kpi) }}</strong>
          </div>
        </div>

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
                <Column header="ESTABELECIMENTO" style="min-width: 250px">
                  <template #body="{ data }">
                    <div class="indicator-estab-cell">
                      <span>{{ data.razao_social || data.cnpj }}</span>
                      <small>{{ data.cnpj }}</small>
                    </div>
                  </template>
                </Column>
                <Column header="MUNICÍPIO/UF" style="min-width: 150px">
                  <template #body="{ data }">{{ data.municipio }}/{{ data.uf }}</template>
                </Column>
                <Column :header="config.valueLabel.toUpperCase()" style="width: 120px">
                  <template #body="{ data }">{{ formatIndicatorValue(data.valor) }}</template>
                </Column>
                <Column :header="config.financialLabel.toUpperCase()" style="width: 150px">
                  <template #body="{ data }">{{ formatFinancialValue(data.valor_financeiro) }}</template>
                </Column>
                <Column header="MEDIANA REGIÃO" style="width: 130px">
                  <template #body="{ data }">{{ formatIndicatorValue(data.mediana_regiao) }}</template>
                </Column>
                <Column header="RISCO REGIÃO" style="width: 115px">
                  <template #body="{ data }">{{ data.risco_regiao == null ? '—' : `${Number(data.risco_regiao).toFixed(1)}x` }}</template>
                </Column>
                <Column field="status" header="STATUS" style="width: 116px">
                  <template #body="{ data }">
                    <span :class="statusClass(data.status)">{{ statusLabel(data.status) }}</span>
                  </template>
                </Column>
                <Column header="CONEXÃO MS" style="width: 108px">
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
                <Column header="ESTABELECIMENTO" style="min-width: 250px">
                  <template #body="{ data }">
                    <div class="indicator-estab-cell">
                      <span>{{ data.razao_social || data.cnpj }}</span>
                      <small>{{ data.cnpj }}</small>
                    </div>
                  </template>
                </Column>
                <Column header="MUNICÍPIO/UF" style="min-width: 150px">
                  <template #body="{ data }">{{ data.municipio }}/{{ data.uf }}</template>
                </Column>
                <Column :header="config.valueLabel.toUpperCase()" style="width: 120px">
                  <template #body="{ data }">{{ formatIndicatorValue(data.valor) }}</template>
                </Column>
                <Column :header="config.financialLabel.toUpperCase()" style="width: 150px">
                  <template #body="{ data }">{{ formatFinancialValue(data.valor_financeiro) }}</template>
                </Column>
                <Column header="MEDIANA REGIÃO" style="width: 130px">
                  <template #body="{ data }">{{ formatIndicatorValue(data.mediana_regiao) }}</template>
                </Column>
                <Column header="RISCO REGIÃO" style="width: 115px">
                  <template #body="{ data }">{{ data.risco_regiao == null ? '—' : `${Number(data.risco_regiao).toFixed(1)}x` }}</template>
                </Column>
                <Column field="status" header="STATUS" style="width: 116px">
                  <template #body="{ data }">
                    <span :class="statusClass(data.status)">{{ statusLabel(data.status) }}</span>
                  </template>
                </Column>
                <Column header="CONEXÃO MS" style="width: 108px">
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
  </Dialog>
</template>

<style scoped>
.indicator-detail-shell {
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
}

.indicator-kpis {
  display: grid;
  grid-template-columns: repeat(5, minmax(0, 1fr));
  gap: 0.75rem;
}

.indicator-kpi,
.indicator-benchmark-card {
  border: 1px solid var(--card-border);
  background: var(--card-bg);
  border-radius: 10px;
}

.indicator-kpi {
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
  padding: 0.75rem 0.9rem;
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

.indicator-estab-cell {
  display: flex;
  flex-direction: column;
  gap: 0.15rem;
  min-width: 0;
}

.indicator-estab-cell span {
  color: var(--text-color);
  font-weight: 600;
  line-height: 1.2;
}

.indicator-estab-cell small {
  color: var(--text-muted);
  font-size: 0.7rem;
}

.ms-status,
.indicator-status {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border-radius: 999px;
  font-size: 0.68rem;
  font-weight: 700;
  letter-spacing: 0.04em;
}

.ms-status {
  min-width: 3.4rem;
  padding: 0.16rem 0.45rem;
}

.ms-status--ativo {
  color: var(--risk-indicator-normal);
  background: color-mix(in srgb, var(--risk-indicator-normal) 12%, transparent);
}

.ms-status--inativo {
  color: var(--text-muted);
  background: color-mix(in srgb, var(--text-muted) 10%, transparent);
}

.indicator-status {
  min-width: 5.8rem;
  padding: 0.16rem 0.5rem;
}

.indicator-status--critico {
  color: var(--risk-indicator-critical);
  background: color-mix(in srgb, var(--risk-indicator-critical) 12%, transparent);
}

.indicator-status--atencao {
  color: var(--risk-indicator-warning);
  background: color-mix(in srgb, var(--risk-indicator-warning) 13%, transparent);
}

.indicator-status--normal {
  color: var(--risk-indicator-normal);
  background: color-mix(in srgb, var(--risk-indicator-normal) 12%, transparent);
}

.indicator-status--sem-dados {
  color: var(--text-muted);
  background: color-mix(in srgb, var(--text-muted) 10%, transparent);
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

:deep(.indicator-table .p-datatable-tbody > tr > td) {
  font-size: 0.8rem;
  background: var(--card-bg);
  color: var(--text-color);
  border-color: var(--card-border);
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
