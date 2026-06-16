<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { storeToRefs } from 'pinia';
import Dialog from 'primevue/dialog';
import DataTable from 'primevue/datatable';
import Column from 'primevue/column';
import TabView from 'primevue/tabview';
import TabPanel from 'primevue/tabpanel';
import { use } from 'echarts/core';
import { CanvasRenderer } from 'echarts/renderers';
import { MapChart } from 'echarts/charts';
import { TooltipComponent, VisualMapComponent } from 'echarts/components';
import { registerMap } from 'echarts/core';
import VChart from 'vue-echarts';
import { useThemeStore } from '@/stores/theme';
import { useFilterStore } from '@/stores/filters';
import { useCnpjDetailStore } from '@/stores/cnpjDetail';
import { useFormatting } from '@/composables/useFormatting';
import { useChartTheme } from '@/config/chartTheme';
import { GEOGRAPHIC_DISTRIBUTION_SCALE, PALETTE } from '@/config/colors';

use([CanvasRenderer, MapChart, TooltipComponent, VisualMapComponent]);

const props = defineProps({
  modelValue: { type: Boolean, default: false },
  cnpj: { type: String, default: '' },
});

const emit = defineEmits(['update:modelValue']);

const themeStore = useThemeStore();
const filterStore = useFilterStore();
const cnpjDetailStore = useCnpjDetailStore();
const { formatCurrencyFull, formatNumberFull, formatPercent, toLocalISO } = useFormatting();
const { chartTheme } = useChartTheme();
const {
  geograficoOrigemUfData,
  geograficoOrigemUfLoading,
  geograficoOrigemUfError,
  geograficoBenchmarkData,
  geograficoBenchmarkLoading,
  geograficoBenchmarkError,
} = storeToRefs(cnpjDetailStore);

const mapReady = ref(false);
const mapKey = ref(0);
const mapError = ref(null);

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

onMounted(async () => {
  try {
    if (!window.__brasilUfGeograficoOrigemRegistered) {
      const response = await fetch('/geo/brasil-uf.json');
      if (!response.ok) {
        throw new Error(`GeoJSON do mapa indisponivel (HTTP ${response.status}).`);
      }
      const geo = await response.json();
      registerMap('brasil-uf-geografico-origem', geo);
      window.__brasilUfGeograficoOrigemRegistered = true;
    }
    mapReady.value = true;
    mapKey.value += 1;
  } catch (error) {
    mapError.value = error?.message || 'Mapa geográfico indisponível.';
  }
});

watch(
  () => [props.modelValue, props.cnpj, periodoInicio.value, periodoFim.value],
  async ([visible, cnpj]) => {
    if (!visible || !cnpj) return;
    await Promise.all([
      cnpjDetailStore.fetchGeograficoOrigemUf(cnpj, periodoInicio.value, periodoFim.value),
      cnpjDetailStore.fetchGeograficoBenchmarkLocal(cnpj, periodoInicio.value, periodoFim.value),
    ]);
  },
  { immediate: true },
);

const rows = computed(() => geograficoOrigemUfData.value?.rows ?? []);

const rowClass = (row) => ({
  'geo-table-home-uf': row?.uf_paciente === geograficoOrigemUfData.value?.uf_farmacia,
});

const benchmarkRowClass = (row) => ({
  'geo-benchmark-target': row?.is_alvo,
});

const benchmarkMunicipioRows = computed(() => geograficoBenchmarkData.value?.municipio?.rows ?? []);
const benchmarkRegiaoRows = computed(() => geograficoBenchmarkData.value?.regiao_saude?.rows ?? []);

const benchmarkMunicipioLabel = computed(() => geograficoBenchmarkData.value?.municipio?.label ?? 'Município');
const benchmarkRegiaoLabel = computed(() => geograficoBenchmarkData.value?.regiao_saude?.label ?? 'Região de Saúde');

const benchmarkErrorMessage = computed(() => geograficoBenchmarkError.value);

const statusClass = (status) => {
  if (status === 'CRITICO') return 'geo-status geo-status--critico';
  if (status === 'ATENCAO') return 'geo-status geo-status--atencao';
  if (status === 'NORMAL') return 'geo-status geo-status--normal';
  return 'geo-status geo-status--sem-dados';
};

const statusLabel = (status) => {
  if (status === 'CRITICO') return 'CRÍTICO';
  if (status === 'ATENCAO') return 'ATENÇÃO';
  if (status === 'NORMAL') return 'NORMAL';
  return 'SEM DADOS';
};

const estabelecimentoLabel = (row) => row?.nome_fantasia || row?.razao_social || row?.cnpj || '—';

const activeScale = computed(() => GEOGRAPHIC_DISTRIBUTION_SCALE);

const getPiece = (value) =>
  activeScale.value.find((piece) => {
    const minOk = piece.min == null || value >= piece.min;
    const maxOk = piece.max == null || value < piece.max;
    return minOk && maxOk;
  }) ?? activeScale.value[activeScale.value.length - 1];

const mapData = computed(() => {
  const ufFarmacia = geograficoOrigemUfData.value?.uf_farmacia ?? null;
  return rows.value.map((row) => {
    const piece = getPiece(row.percentual_sobre_total ?? 0);
    const isUfFarmacia = row.uf_paciente === ufFarmacia;
    const labelColor = (row.percentual_sobre_total ?? 0) >= 20
      ? PALETTE.zinc[100]
      : PALETTE.slate[800];
    return {
      name: row.uf_paciente,
      value: row.percentual_sobre_total ?? 0,
      valor_autorizado: row.valor_autorizado ?? 0,
      qtd_autorizacoes: row.qtd_autorizacoes ?? 0,
      isUfFarmacia,
      label: {
        color: labelColor,
      },
      itemStyle: {
        areaColor: piece.color,
        borderColor: isUfFarmacia ? themeStore.tokens.primary : piece.borderColor,
        borderWidth: isUfFarmacia ? 2.5 : 1.5,
      },
      emphasis: {
        itemStyle: {
          areaColor: piece.color,
          borderColor: themeStore.tokens.primary,
          borderWidth: 2.5,
        },
      },
    };
  });
});

const chartOption = computed(() => {
  const c = chartTheme.value;
  return {
    backgroundColor: c.bg,
    tooltip: {
      trigger: 'item',
      confine: true,
      backgroundColor: c.tooltip,
      borderColor: c.tooltipBorder,
      borderWidth: 1,
      padding: [12, 16],
      textStyle: {
        color: c.tooltipText,
        fontFamily: 'Inter, sans-serif',
        fontSize: 12,
      },
      formatter: (params) => {
        if (!params.data || !Number.isFinite(Number(params.data.value))) {
          return `
            <div style="color:${c.tooltipText};">
              <div style="font-size:14px;margin-bottom:4px;">${params.name}</div>
              <div style="font-size:11px;opacity:0.7;">Sem vendas registradas no período</div>
            </div>`;
        }
        const d = params.data;
        return `
          <div style="color:${c.tooltipText};">
            <div style="font-size:14px;margin-bottom:8px;">${params.name}</div>
            <div style="display:flex;flex-direction:column;gap:4px;font-size:12px;">
              <div>Participação no valor: <strong>${formatPercent(d.value)}</strong></div>
              <div>Valor autorizado: <strong>${formatCurrencyFull(d.valor_autorizado)}</strong></div>
              <div>Autorizações: <strong>${formatNumberFull(d.qtd_autorizacoes)}</strong></div>
            </div>
          </div>`;
      },
    },
    visualMap: {
      show: false,
      pieces: activeScale.value,
      seriesIndex: 0,
    },
    series: [
      {
        type: 'map',
        map: 'brasil-uf-geografico-origem',
        nameProperty: 'UF',
        roam: false,
        layoutCenter: ['50%', '45%'],
        layoutSize: '96%',
        aspectScale: 1,
        selectedMode: false,
        label: {
          show: true,
          fontSize: 9,
          fontWeight: 600,
          color: c.text,
          fontFamily: 'Inter, sans-serif',
        },
        emphasis: {
          label: { show: true, fontSize: 10, color: c.text },
          itemStyle: {
            borderColor: themeStore.tokens.primary,
            borderWidth: 2.5,
          },
        },
        itemStyle: {
          borderColor: themeStore.isDark ? 'rgba(255,255,255,0.15)' : 'rgba(0,0,0,0.15)',
          borderWidth: 1.5,
          areaColor: themeStore.isDark ? 'rgba(255,255,255,0.07)' : 'rgba(0,0,0,0.04)',
        },
        data: mapData.value,
      },
    ],
  };
});

const summaryCards = computed(() => {
  const data = geograficoOrigemUfData.value;
  if (!data) return [];
  return [
    {
      label: 'UF da farmácia',
      value: data.uf_farmacia,
    },
    {
      label: 'Valor fora da UF',
      value: formatCurrencyFull(data.total_valor_outra_uf ?? 0),
    },
    {
      label: 'Participação fora da UF',
      value: formatPercent(data.percentual_financeiro_outra_uf ?? 0),
    },
    {
      label: 'Autorizações fora da UF',
      value: formatNumberFull(data.total_autorizacoes_outra_uf ?? 0),
    },
  ];
});

const close = () => emit('update:modelValue', false);
</script>

<template>
  <Dialog
    :visible="modelValue"
    modal
    dismissableMask
    :header="'Dispersão Interestadual'"
    class="geo-dialog"
    :style="{ width: '92vw', maxWidth: '1320px' }"
    @update:visible="emit('update:modelValue', $event)"
    @hide="close"
  >
    <div class="geo-shell">
      <div class="geo-hero">
        <div class="geo-kpis">
          <div v-for="card in summaryCards" :key="card.label" class="geo-kpi">
            <span>{{ card.label }}</span>
            <strong>{{ card.value }}</strong>
          </div>
        </div>
        <div class="geo-kpi geo-period">
          <span>Período</span>
          <strong class="geo-period-value">{{ periodoLabel }}</strong>
        </div>
      </div>

      <div v-if="geograficoOrigemUfLoading" class="geo-loading">
        Carregando detalhamento geográfico...
      </div>

      <div v-else-if="mapError" class="geo-error">
        {{ mapError }}
      </div>

      <div v-else-if="geograficoOrigemUfError" class="geo-error">
        {{ geograficoOrigemUfError }}
      </div>

      <template v-else-if="geograficoOrigemUfData">
        <div class="geo-grid">
          <section class="geo-map-panel">
            <div class="panel-title">Distribuição do valor autorizado por UF de residência</div>
            <VChart
              v-if="mapReady"
              :key="`geo-${mapKey}`"
              class="geo-chart"
              :option="chartOption"
              autoresize
            />
          </section>

          <section class="geo-table-panel">
            <div class="panel-title">Distribuição das autorizações por UF de residência</div>
            <DataTable
              :value="rows"
              :rowClass="rowClass"
              stripedRows
              size="small"
              scrollable
              scrollHeight="420px"
              class="geo-table"
            >
              <Column field="uf_paciente" header="UF" style="width: 90px" />
              <Column field="qtd_autorizacoes" header="Autorizações" style="width: 130px">
                <template #body="{ data }">
                  {{ formatNumberFull(data.qtd_autorizacoes ?? 0) }}
                </template>
              </Column>
              <Column field="valor_autorizado" header="Valor autorizado" style="width: 160px">
                <template #body="{ data }">
                  {{ formatCurrencyFull(data.valor_autorizado ?? 0) }}
                </template>
              </Column>
              <Column field="percentual_sobre_total" header="% total" style="width: 110px">
                <template #body="{ data }">
                  {{ formatPercent(data.percentual_sobre_total ?? 0) }}
                </template>
              </Column>
              <Column field="percentual_sobre_outra_uf" header="% outras UFs" style="width: 120px">
                <template #body="{ data }">
                  <span v-if="data.percentual_sobre_outra_uf != null">
                    {{ formatPercent(data.percentual_sobre_outra_uf) }}
                  </span>
                  <span v-else>—</span>
                </template>
              </Column>
            </DataTable>
          </section>
        </div>

        <section class="geo-benchmark-card">
          <div class="panel-title">Comparação com estabelecimentos do território</div>
          <div v-if="geograficoBenchmarkLoading" class="geo-benchmark-state">
            Carregando comparação territorial...
          </div>
          <div v-else-if="benchmarkErrorMessage" class="geo-error geo-benchmark-state">
            {{ benchmarkErrorMessage }}
          </div>
          <TabView v-else-if="geograficoBenchmarkData" class="geo-benchmark-tabs">
            <TabPanel>
              <template #header>
                <span>Município</span>
              </template>
              <div class="geo-scope-label">{{ benchmarkMunicipioLabel }}</div>
              <DataTable
                :value="benchmarkMunicipioRows"
                :rowClass="benchmarkRowClass"
                stripedRows
                size="small"
                scrollable
                scrollHeight="260px"
                class="geo-table geo-benchmark-table"
              >
                <Column header="ESTABELECIMENTO" style="min-width: 260px">
                  <template #body="{ data }">
                    <div class="geo-estab-cell">
                      <span>{{ estabelecimentoLabel(data) }}</span>
                      <small>{{ data.cnpj }}</small>
                    </div>
                  </template>
                </Column>
                <Column field="municipio" header="MUNICÍPIO/UF" style="width: 150px">
                  <template #body="{ data }">
                    {{ data.municipio || '—' }}/{{ data.uf || '—' }}
                  </template>
                </Column>
                <Column field="percentual_outra_uf" header="% FORA DA UF" style="width: 130px">
                  <template #body="{ data }">
                    {{ data.percentual_outra_uf == null ? '—' : formatPercent(data.percentual_outra_uf) }}
                  </template>
                </Column>
                <Column field="valor_outra_uf" header="VALOR FORA DA UF" style="width: 165px">
                  <template #body="{ data }">
                    {{ formatCurrencyFull(data.valor_outra_uf ?? 0) }}
                  </template>
                </Column>
                <Column field="valor_total" header="VALOR TOTAL" style="width: 150px">
                  <template #body="{ data }">
                    {{ formatCurrencyFull(data.valor_total ?? 0) }}
                  </template>
                </Column>
                <Column field="qtd_vendas_outra_uf" header="AUTORIZAÇÕES" style="width: 140px">
                  <template #body="{ data }">
                    {{ formatNumberFull(data.qtd_vendas_outra_uf ?? 0) }}
                  </template>
                </Column>
                <Column field="risco_regiao" header="RISCO REGIÃO" style="width: 130px">
                  <template #body="{ data }">
                    {{ data.risco_regiao == null ? '—' : `${data.risco_regiao.toFixed(1)}x` }}
                  </template>
                </Column>
                <Column field="status" header="STATUS" style="width: 120px">
                  <template #body="{ data }">
                    <span :class="statusClass(data.status)">{{ statusLabel(data.status) }}</span>
                  </template>
                </Column>
              </DataTable>
            </TabPanel>
            <TabPanel>
              <template #header>
                <span>Região de Saúde</span>
              </template>
              <div class="geo-scope-label">{{ benchmarkRegiaoLabel }}</div>
              <DataTable
                :value="benchmarkRegiaoRows"
                :rowClass="benchmarkRowClass"
                stripedRows
                size="small"
                scrollable
                scrollHeight="260px"
                class="geo-table geo-benchmark-table"
              >
                <Column header="ESTABELECIMENTO" style="min-width: 260px">
                  <template #body="{ data }">
                    <div class="geo-estab-cell">
                      <span>{{ estabelecimentoLabel(data) }}</span>
                      <small>{{ data.cnpj }}</small>
                    </div>
                  </template>
                </Column>
                <Column field="municipio" header="MUNICÍPIO/UF" style="width: 150px">
                  <template #body="{ data }">
                    {{ data.municipio || '—' }}/{{ data.uf || '—' }}
                  </template>
                </Column>
                <Column field="percentual_outra_uf" header="% FORA DA UF" style="width: 130px">
                  <template #body="{ data }">
                    {{ data.percentual_outra_uf == null ? '—' : formatPercent(data.percentual_outra_uf) }}
                  </template>
                </Column>
                <Column field="valor_outra_uf" header="VALOR FORA DA UF" style="width: 165px">
                  <template #body="{ data }">
                    {{ formatCurrencyFull(data.valor_outra_uf ?? 0) }}
                  </template>
                </Column>
                <Column field="valor_total" header="VALOR TOTAL" style="width: 150px">
                  <template #body="{ data }">
                    {{ formatCurrencyFull(data.valor_total ?? 0) }}
                  </template>
                </Column>
                <Column field="qtd_vendas_outra_uf" header="AUTORIZAÇÕES" style="width: 140px">
                  <template #body="{ data }">
                    {{ formatNumberFull(data.qtd_vendas_outra_uf ?? 0) }}
                  </template>
                </Column>
                <Column field="risco_regiao" header="RISCO REGIÃO" style="width: 130px">
                  <template #body="{ data }">
                    {{ data.risco_regiao == null ? '—' : `${data.risco_regiao.toFixed(1)}x` }}
                  </template>
                </Column>
                <Column field="status" header="STATUS" style="width: 120px">
                  <template #body="{ data }">
                    <span :class="statusClass(data.status)">{{ statusLabel(data.status) }}</span>
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
.geo-shell {
  display: flex;
  flex-direction: column;
  gap: 0.65rem;
}

.geo-hero {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr)) minmax(170px, 0.75fr);
  align-items: stretch;
  gap: 0.75rem;
  padding-bottom: 0;
}

.geo-kpis {
  display: contents;
}

.geo-kpi {
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
  padding: 0.75rem 0.9rem;
  border: 1px solid var(--card-border);
  border-radius: 10px;
  background: var(--card-bg);
}

.geo-kpi span,
.panel-title {
  font-size: 0.78rem;
  line-height: 1.2;
  color: var(--text-muted);
}

.geo-kpi strong {
  font-size: 0.98rem;
  font-weight: 600;
  color: var(--text-color);
}

.geo-period {
  white-space: nowrap;
}

.geo-period-value {
  font-size: 0.78rem;
  line-height: 1.2;
  white-space: normal;
}

.geo-grid {
  display: grid;
  grid-template-columns: 1.35fr 0.95fr;
  gap: 0.8rem;
  min-height: 500px;
}

.geo-map-panel,
.geo-table-panel,
.geo-benchmark-card {
  display: flex;
  flex-direction: column;
  min-height: 0;
  padding: 0.9rem;
  border: 1px solid var(--card-border);
  border-radius: 12px;
  background: var(--card-bg);
}

.panel-title {
  margin-bottom: 0.75rem;
  color: var(--text-color);
}

.geo-chart {
  flex: 1;
  min-height: 420px;
  width: 100%;
}

.geo-loading,
.geo-error {
  min-height: 280px;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--text-muted);
}

.geo-error {
  color: var(--risk-indicator-critical);
}

.geo-benchmark-card {
  gap: 0.6rem;
  min-height: 390px;
}

.geo-benchmark-state {
  min-height: 290px;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--text-muted);
}

.geo-scope-label {
  margin: 0.15rem 0 0.65rem;
  font-size: 0.78rem;
  font-weight: 600;
  color: var(--text-muted);
}

.geo-estab-cell {
  display: flex;
  flex-direction: column;
  gap: 0.15rem;
  min-width: 0;
}

.geo-estab-cell span {
  color: var(--text-color);
  font-weight: 600;
  line-height: 1.2;
}

.geo-estab-cell small {
  color: var(--text-muted);
  font-size: 0.7rem;
}

.geo-status {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 5.8rem;
  padding: 0.16rem 0.5rem;
  border-radius: 999px;
  font-size: 0.68rem;
  font-weight: 700;
  letter-spacing: 0.04em;
}

.geo-status--critico {
  color: var(--risk-indicator-critical);
  background: color-mix(in srgb, var(--risk-indicator-critical) 12%, transparent);
}

.geo-status--atencao {
  color: var(--risk-indicator-warning);
  background: color-mix(in srgb, var(--risk-indicator-warning) 13%, transparent);
}

.geo-status--normal {
  color: var(--risk-indicator-normal);
  background: color-mix(in srgb, var(--risk-indicator-normal) 12%, transparent);
}

.geo-status--sem-dados {
  color: var(--text-muted);
  background: color-mix(in srgb, var(--text-muted) 10%, transparent);
}

:deep(.geo-dialog.p-dialog .p-dialog-content) {
  padding-top: 0.45rem;
}

:deep(.geo-dialog.p-dialog .p-dialog-header) {
  padding-bottom: 0.45rem;
}

:deep(.geo-benchmark-tabs .p-tabview-nav) {
  background: transparent;
  border-color: var(--card-border);
}

:deep(.geo-benchmark-tabs .p-tabview-panels) {
  padding: 0.55rem 0 0;
  background: transparent;
  min-height: 310px;
}

:deep(.geo-benchmark-tabs .p-tabview-nav-link) {
  background: transparent;
  color: var(--text-color);
  border-color: var(--card-border);
  padding: 0.45rem 0.75rem;
  font-size: 0.78rem;
  font-weight: 700;
  line-height: 1.15;
}

:deep(.geo-table .p-datatable-thead > tr > th) {
  font-size: 0.78rem;
  font-weight: 600;
  background: var(--card-bg);
  color: var(--text-color);
  border-color: var(--card-border);
}

:deep(.geo-table .p-datatable-tbody > tr > td) {
  font-size: 0.8rem;
  background: var(--card-bg);
  color: var(--text-color);
  border-color: var(--card-border);
}

:deep(.geo-table.p-datatable),
:deep(.geo-table .p-datatable-wrapper),
:deep(.geo-table .p-datatable-table) {
  background: var(--card-bg);
  color: var(--text-color);
}

:deep(.geo-table .p-datatable-tbody > tr) {
  background: var(--card-bg);
  color: var(--text-color);
}

:deep(.geo-table .p-datatable-tbody > tr:nth-child(even) > td) {
  background: color-mix(in srgb, var(--text-color) 3%, var(--card-bg));
}

:deep(.geo-table .p-datatable-tbody > tr:hover > td) {
  background: color-mix(in srgb, var(--primary-color) 8%, var(--card-bg));
}

:deep(.geo-table .p-datatable-tbody > tr.geo-table-home-uf > td),
:deep(.geo-table .p-datatable-tbody > tr.geo-table-home-uf:nth-child(even) > td) {
  background: color-mix(in srgb, var(--primary-color) 15%, var(--card-bg));
  color: var(--text-color);
}

:deep(.geo-table .p-datatable-tbody > tr.geo-benchmark-target > td),
:deep(.geo-table .p-datatable-tbody > tr.geo-benchmark-target:nth-child(even) > td) {
  background: color-mix(in srgb, var(--primary-color) 15%, var(--card-bg));
  color: var(--text-color);
}

:deep(.geo-table .p-datatable-tbody > tr.geo-table-home-uf > td:first-child) {
  box-shadow: inset 3px 0 0 var(--primary-color);
}

:deep(.geo-table .p-datatable-tbody > tr.geo-benchmark-target > td:first-child) {
  box-shadow: inset 3px 0 0 var(--primary-color);
}

:deep(.geo-table .p-datatable-tbody > tr.geo-table-home-uf:hover > td) {
  background: color-mix(in srgb, var(--primary-color) 22%, var(--card-bg));
}

:deep(.geo-table .p-datatable-scrollable-body),
:deep(.geo-table .p-datatable-wrapper) {
  scrollbar-color: var(--card-border) var(--card-bg);
}

@media (max-width: 1200px) {
  .geo-hero {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }

  .geo-grid {
    grid-template-columns: 1fr;
  }
}
</style>
