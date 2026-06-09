<script setup>
import { computed, ref, watch } from 'vue';
import { storeToRefs } from 'pinia';
import Dialog from 'primevue/dialog';
import DataTable from 'primevue/datatable';
import Column from 'primevue/column';
import { graphic, use } from 'echarts/core';
import { CanvasRenderer } from 'echarts/renderers';
import { BarChart, LineChart } from 'echarts/charts';
import { GridComponent, LegendComponent, TooltipComponent } from 'echarts/components';
import VChart from 'vue-echarts';
import { useCnpjDetailStore } from '@/stores/cnpjDetail';
import { useFilterStore } from '@/stores/filters';
import { useThemeStore } from '@/stores/theme';
import { useFormatting } from '@/composables/useFormatting';
import { useChartTheme } from '@/config/chartTheme';
import { PALETTE } from '@/config/colors';

use([CanvasRenderer, BarChart, LineChart, GridComponent, LegendComponent, TooltipComponent]);

const props = defineProps({
  modelValue: { type: Boolean, default: false },
  cnpj: { type: String, default: '' },
});

const emit = defineEmits(['update:modelValue']);

const filterStore = useFilterStore();
const themeStore = useThemeStore();
const cnpjDetailStore = useCnpjDetailStore();
const { chartTheme } = useChartTheme();
const {
  incompatibilidadePatologicaData,
  incompatibilidadePatologicaLoading,
  incompatibilidadePatologicaError,
} = storeToRefs(cnpjDetailStore);

const {
  formatCurrencyFull,
  formatNumberFull,
  formatPercent,
  formatCnpj,
  toLocalISO,
} = useFormatting();

const activeIndex = ref(0);

const periodoInicio = computed(() => {
  const [start] = filterStore.periodo ?? [];
  return start ? toLocalISO(start) : null;
});

const periodoFim = computed(() => {
  const [, end] = filterStore.periodo ?? [];
  return end ? toLocalISO(end) : null;
});

watch(
  () => [props.modelValue, props.cnpj, periodoInicio.value, periodoFim.value],
  async ([visible, cnpj]) => {
    if (!visible || !cnpj) return;
    await cnpjDetailStore.fetchIncompatibilidadePatologica(cnpj, periodoInicio.value, periodoFim.value);
  },
  { immediate: true },
);

watch(
  () => incompatibilidadePatologicaData.value?.patologias,
  (patologias) => {
    if (!Array.isArray(patologias) || activeIndex.value >= patologias.length) {
      activeIndex.value = 0;
    }
  },
);

const patologias = computed(() => incompatibilidadePatologicaData.value?.patologias ?? []);
const activePatologia = computed(() => patologias.value[activeIndex.value] ?? null);
const parkinson = computed(() => activePatologia.value?.demografia_parkinson ?? null);

const formatRatioPercent = (value) => {
  if (value === null || value === undefined) return '—';
  return formatPercent(Number(value) * 100);
};

const pathologyCards = computed(() => {
  const item = activePatologia.value;
  if (!item) return [];
  return [
    {
      label: 'Valor incompatível',
      value: formatCurrencyFull(item.valor_incompativel_pago ?? 0),
    },
    {
      label: 'CPFs incompatíveis',
      value: formatNumberFull(item.qtd_cpfs_incompativeis ?? 0),
    },
    {
      label: 'Autorizações',
      value: formatNumberFull(item.qtd_autorizacoes_incompativeis ?? 0),
    },
    {
      label: 'Razão vs. região',
      value: item.razao_media_percentual_vs_regiao == null
        ? '—'
        : `${Number(item.razao_media_percentual_vs_regiao).toLocaleString('pt-BR', { maximumFractionDigits: 2 })}x`,
    },
  ];
});

const chartText = computed(() => chartTheme.value);

const verticalGradient = (start, end) => new graphic.LinearGradient(0, 0, 0, 1, [
  { offset: 0, color: start },
  { offset: 1, color: end },
]);

const horizontalGradient = (start, end) => new graphic.LinearGradient(0, 0, 1, 0, [
  { offset: 0, color: start },
  { offset: 1, color: end },
]);

const blueBarGradient = computed(() => verticalGradient(PALETTE.blue[500], PALETTE.blue[600]));
const roseBarGradient = computed(() => verticalGradient(PALETTE.rose[500], PALETTE.red[700]));
const blueHorizontalGradient = computed(() => horizontalGradient(PALETTE.blue[500], PALETTE.blue[600]));
const slateHorizontalGradient = computed(() => horizontalGradient(PALETTE.slate[400], PALETTE.slate[500]));

const parkinsonCompareOption = computed(() => {
  const demo = parkinson.value;
  const c = chartText.value;
  const expected = demo?.casos_esperados ?? 0;
  const observed = demo?.cpfs_observados ?? 0;
  return {
    backgroundColor: c.bg,
    color: [PALETTE.blue[500], PALETTE.rose[500]],
    grid: { left: 48, right: 20, top: 26, bottom: 34 },
    tooltip: {
      trigger: 'axis',
      confine: true,
      backgroundColor: c.tooltip,
      borderColor: c.tooltipBorder,
      textStyle: { color: c.tooltipText, fontFamily: 'Inter, sans-serif', fontSize: 12 },
    },
    xAxis: {
      type: 'category',
      data: ['Casos esperados', 'CPFs observados'],
      axisLabel: { color: c.axis, fontSize: 11 },
      axisLine: { lineStyle: { color: c.grid } },
    },
    yAxis: {
      type: 'value',
      axisLabel: { color: c.axis, fontSize: 10 },
      splitLine: { lineStyle: { color: c.grid } },
    },
    series: [
      {
        type: 'bar',
        data: [
          { value: expected, itemStyle: { color: blueBarGradient.value } },
          { value: observed, itemStyle: { color: roseBarGradient.value } },
        ],
        barMaxWidth: 52,
        itemStyle: { borderRadius: [5, 5, 0, 0] },
      },
    ],
  };
});

const parkinsonAgeOption = computed(() => {
  const demo = parkinson.value;
  const c = chartText.value;
  const rows = demo?.faixas_etarias ?? [];
  return {
    backgroundColor: c.bg,
    color: [PALETTE.slate[400], PALETTE.blue[500]],
    grid: { left: 72, right: 20, top: 18, bottom: 32 },
    tooltip: {
      trigger: 'axis',
      confine: true,
      backgroundColor: c.tooltip,
      borderColor: c.tooltipBorder,
      textStyle: { color: c.tooltipText, fontFamily: 'Inter, sans-serif', fontSize: 12 },
      formatter: (params) => {
        const item = params?.[0]?.data?.raw;
        if (!item) return '';
        return `
          <div>
            <div style="font-size:14px;margin-bottom:8px;">${item.faixa}</div>
            <div>População: <strong>${formatNumberFull(item.populacao)}</strong></div>
            <div>Participação: <strong>${formatRatioPercent(item.percentual)}</strong></div>
          </div>`;
      },
    },
    xAxis: {
      type: 'value',
      axisLabel: { color: c.axis, fontSize: 10 },
      splitLine: { lineStyle: { color: c.grid } },
    },
    yAxis: {
      type: 'category',
      inverse: true,
      data: rows.map((row) => row.faixa),
      axisLabel: { color: c.axis, fontSize: 10 },
      axisLine: { lineStyle: { color: c.grid } },
    },
    series: [
      {
        type: 'bar',
        data: rows.map((row) => ({
          value: row.populacao,
          raw: row,
          itemStyle: {
            color: row.destacar_50_mais ? blueHorizontalGradient.value : slateHorizontalGradient.value,
          },
        })),
        barMaxWidth: 16,
        itemStyle: { borderRadius: [0, 4, 4, 0] },
      },
    ],
  };
});

const rowClass = (row) => ({
  'clin-row-target': row?.is_alvo || row?.grupo === 'Farmácia analisada',
});

const close = () => emit('update:modelValue', false);
</script>

<template>
  <Dialog
    :visible="modelValue"
    modal
    dismissableMask
    :header="'Vendas com incompatibilidade clínica/patológica'"
    class="clin-dialog"
    :style="{ width: '92vw', maxWidth: '1320px' }"
    @update:visible="emit('update:modelValue', $event)"
    @hide="close"
  >
    <div class="clin-shell">
      <div v-if="incompatibilidadePatologicaLoading" class="clin-loading">
        Carregando detalhamento clínico...
      </div>

      <div v-else-if="incompatibilidadePatologicaError" class="clin-empty">
        {{ incompatibilidadePatologicaError }}
      </div>

      <div v-else-if="!patologias.length" class="clin-empty">
        Sem incompatibilidades patológicas no período.
      </div>

      <template v-else>
        <div class="clin-tabs" role="tablist" aria-label="Recortes clínicos">
          <button
            v-for="(item, index) in patologias"
            :key="`${item.patologia}-${item.regra_clinica}`"
            type="button"
            class="clin-tab"
            :class="{ active: index === activeIndex }"
            @click="activeIndex = index"
          >
            <span>{{ item.titulo }}</span>
            <small>{{ item.criterio }}</small>
          </button>
        </div>

        <section v-if="activePatologia" class="clin-panel">
          <div class="clin-kpis clin-kpis-small">
            <div v-for="card in pathologyCards" :key="card.label" class="clin-kpi">
              <span>{{ card.label }}</span>
              <strong>{{ card.value }}</strong>
            </div>
          </div>

          <div class="clin-grid clin-grid-single">
            <div class="clin-card">
              <h4>Comparativo municipal</h4>
              <DataTable
                :value="activePatologia.municipal_resumo"
                size="small"
                :rowClass="rowClass"
                class="clin-table"
              >
                <Column field="grupo" header="Grupo" />
                <Column field="qtd_farmacias" header="Farmácias">
                  <template #body="{ data }">{{ formatNumberFull(data.qtd_farmacias) }}</template>
                </Column>
                <Column field="valor_incompativel_pago" header="Valor incompatível">
                  <template #body="{ data }">{{ formatCurrencyFull(data.valor_incompativel_pago) }}</template>
                </Column>
                <Column field="participacao_valor_municipal" header="Participação">
                  <template #body="{ data }">{{ formatRatioPercent(data.participacao_valor_municipal) }}</template>
                </Column>
              </DataTable>
            </div>
          </div>

          <div v-if="parkinson" class="clin-parkinson">
            <div class="clin-section-head">
              <div>
                <h3>Doença de Parkinson: beneficiários com menos de 50 anos</h3>
                <p>Comparação entre a dispensação observada na farmácia e a estimativa epidemiológica municipal.</p>
              </div>
            </div>

            <div class="clin-kpis clin-kpis-small">
              <div class="clin-kpi">
                <span>CPFs observados</span>
                <strong>{{ formatNumberFull(parkinson.cpfs_observados) }}</strong>
              </div>
              <div class="clin-kpi">
                <span>Casos esperados</span>
                <strong>{{ parkinson.casos_esperados.toLocaleString('pt-BR', { maximumFractionDigits: 2 }) }}</strong>
              </div>
              <div class="clin-kpi">
                <span>Razão observado/esperado</span>
                <strong>{{ parkinson.razao_observado_esperado?.toLocaleString('pt-BR', { maximumFractionDigits: 2 }) ?? '—' }}x</strong>
              </div>
              <div class="clin-kpi">
                <span>População 50+</span>
                <strong>{{ formatNumberFull(parkinson.populacao_50_mais) }}</strong>
              </div>
            </div>

            <div class="clin-grid">
              <div class="clin-card clin-card-chart">
                <h4>Observado x esperado</h4>
                <VChart class="clin-chart clin-chart-small" :option="parkinsonCompareOption" autoresize />
              </div>
              <div class="clin-card clin-card-chart">
                <h4>Distribuição etária municipal</h4>
                <VChart class="clin-chart clin-chart-small" :option="parkinsonAgeOption" autoresize />
              </div>
            </div>

            <div class="clin-card">
              <h4>Memória de cálculo epidemiológica</h4>
              <DataTable :value="[parkinson]" size="small" class="clin-table">
                <Column field="municipio" header="Município">
                  <template #body="{ data }">{{ data.municipio }}/{{ data.uf }}</template>
                </Column>
                <Column field="ano_censo" header="Censo" />
                <Column field="populacao_total" header="Pop. total">
                  <template #body="{ data }">{{ formatNumberFull(data.populacao_total) }}</template>
                </Column>
                <Column field="populacao_50_mais" header="Pop. 50+">
                  <template #body="{ data }">{{ formatNumberFull(data.populacao_50_mais) }}</template>
                </Column>
                <Column field="prevalencia_50_mais" header="Prev. ref.">
                  <template #body="{ data }">{{ formatRatioPercent(data.prevalencia_50_mais) }}</template>
                </Column>
                <Column field="casos_esperados" header="Esperados">
                  <template #body="{ data }">{{ data.casos_esperados.toLocaleString('pt-BR', { maximumFractionDigits: 2 }) }}</template>
                </Column>
                <Column field="cpfs_observados" header="Observados">
                  <template #body="{ data }">{{ formatNumberFull(data.cpfs_observados) }}</template>
                </Column>
              </DataTable>
            </div>
          </div>

          <div class="clin-card">
            <h4>Ranking municipal de farmácias</h4>
            <DataTable
              :value="activePatologia.ranking_municipal"
              size="small"
              scrollable
              scrollHeight="300px"
              :rowClass="rowClass"
              class="clin-table"
            >
              <Column field="posicao" header="#" />
              <Column field="razao_social" header="Farmácia">
                <template #body="{ data }">
                  <div class="clin-pharmacy-cell">
                    <strong>{{ data.razao_social }}</strong>
                    <span>{{ formatCnpj(data.cnpj) }}</span>
                  </div>
                </template>
              </Column>
              <Column field="valor_incompativel_pago" header="Valor incompatível">
                <template #body="{ data }">{{ formatCurrencyFull(data.valor_incompativel_pago) }}</template>
              </Column>
              <Column field="qtd_cpfs_incompativeis" header="CPFs">
                <template #body="{ data }">{{ formatNumberFull(data.qtd_cpfs_incompativeis) }}</template>
              </Column>
              <Column field="qtd_autorizacoes_incompativeis" header="Autorizações">
                <template #body="{ data }">{{ formatNumberFull(data.qtd_autorizacoes_incompativeis) }}</template>
              </Column>
              <Column field="participacao_municipal" header="Part. municipal">
                <template #body="{ data }">{{ formatRatioPercent(data.participacao_municipal) }}</template>
              </Column>
            </DataTable>
          </div>
        </section>
      </template>
    </div>
  </Dialog>
</template>

<style scoped>
.clin-shell {
  display: flex;
  flex-direction: column;
  gap: 1rem;
  color: var(--text-color);
}

.clin-kpis {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: 1rem;
}

.clin-kpis-small {
  margin-bottom: 1rem;
}

.clin-kpi {
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
  min-height: 4.25rem;
  padding: 0.75rem 0.9rem;
  border: 1px solid var(--card-border);
  border-radius: 10px;
  background: var(--card-bg);
  justify-content: center;
}

.clin-kpi span {
  font-size: 0.78rem;
  line-height: 1.2;
  color: var(--text-muted);
}

.clin-kpi strong {
  font-size: 0.98rem;
  font-weight: 600;
  color: var(--text-color);
  line-height: 1.15;
}

.clin-loading,
.clin-empty {
  min-height: 12rem;
  border: 1px solid var(--border-color);
  border-radius: 0.5rem;
  background: var(--surface-card);
  display: grid;
  place-items: center;
  color: var(--text-muted);
}

.clin-tabs {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
}

.clin-tab {
  border: 1px solid var(--border-color);
  border-radius: 0.5rem;
  background: var(--surface-card);
  color: var(--text-color);
  padding: 0.62rem 0.82rem;
  text-align: left;
  min-width: 12rem;
  cursor: pointer;
  transition: border-color 0.16s ease, transform 0.16s ease, background 0.16s ease;
}

.clin-tab:hover,
.clin-tab.active {
  border-color: var(--primary-color);
  background: color-mix(in srgb, var(--primary-color) 12%, var(--surface-card));
}

.clin-tab.active {
  transform: translateY(-1px);
}

.clin-tab span,
.clin-tab small {
  display: block;
}

.clin-tab span {
  font-size: 0.86rem;
  font-weight: 600;
}

.clin-tab small {
  margin-top: 0.18rem;
  font-size: 0.72rem;
  color: var(--text-muted);
}

.clin-panel,
.clin-parkinson {
  display: flex;
  flex-direction: column;
  gap: 1rem;
}

.clin-section-head {
  display: flex;
  justify-content: space-between;
  gap: 1rem;
  align-items: flex-start;
}

.clin-section-head h3 {
  margin: 0;
  font-size: 1rem;
  font-weight: 600;
}

.clin-section-head p {
  margin: 0.25rem 0 0;
  color: var(--text-muted);
  font-size: 0.82rem;
  line-height: 1.45;
}

.clin-period-badge {
  flex: 0 0 auto;
  border: 1px solid var(--border-color);
  border-radius: 999px;
  color: var(--text-muted);
  padding: 0.32rem 0.7rem;
  font-size: 0.78rem;
  background: var(--surface-card);
}

.clin-grid {
  display: grid;
  grid-template-columns: minmax(0, 1.25fr) minmax(0, 1fr);
  gap: 1rem;
}

.clin-grid-single {
  grid-template-columns: minmax(0, 1fr);
}

.clin-card {
  border: 1px solid var(--card-border);
  border-radius: 12px;
  background: var(--card-bg);
  padding: 0.9rem;
  min-width: 0;
}

.clin-card h4 {
  margin: 0 0 0.75rem;
  font-size: 0.78rem;
  font-weight: 600;
  line-height: 1.2;
  color: var(--text-muted);
}

.clin-chart {
  width: 100%;
  height: 19rem;
}

.clin-chart-small {
  height: 17rem;
}

.clin-pharmacy-cell {
  display: flex;
  flex-direction: column;
  gap: 0.12rem;
  align-items: flex-start;
}

.clin-pharmacy-cell strong {
  font-weight: 600;
  color: var(--text-color);
}

.clin-pharmacy-cell span {
  color: var(--text-muted);
  font-size: 0.74rem;
}

:deep(.clin-table .p-datatable-table) {
  background: var(--card-bg);
  color: var(--text-color);
}

:deep(.clin-table .p-datatable-thead > tr > th) {
  background: var(--card-bg);
  color: var(--text-color);
  border-color: var(--card-border);
  font-size: 0.78rem;
  font-weight: 600;
}

:deep(.clin-table .p-datatable-tbody > tr > td) {
  background: var(--card-bg);
  color: var(--text-color);
  border-color: var(--card-border);
  font-size: 0.8rem;
}

:deep(.clin-table.p-datatable),
:deep(.clin-table .p-datatable-wrapper),
:deep(.clin-table .p-datatable-table) {
  background: var(--card-bg);
  color: var(--text-color);
}

:deep(.clin-table .p-datatable-tbody > tr) {
  background: var(--card-bg);
  color: var(--text-color);
}

:deep(.clin-table .p-datatable-tbody > tr:hover > td) {
  background: color-mix(in srgb, var(--primary-color) 8%, var(--card-bg));
}

:deep(.clin-table .p-datatable-tbody > tr.clin-row-target > td),
:deep(.clin-table .p-datatable-tbody > tr.clin-row-target:hover > td) {
  background: color-mix(in srgb, var(--primary-color) 15%, var(--card-bg));
  color: var(--text-color);
}

:deep(.clin-table .p-datatable-tbody > tr.clin-row-target > td:first-child) {
  box-shadow: inset 3px 0 0 var(--primary-color);
}

:deep(.clin-table .p-datatable-scrollable-body),
:deep(.clin-table .p-datatable-wrapper) {
  scrollbar-color: var(--card-border) var(--card-bg);
}

:deep(.clin-dialog .p-dialog-content) {
  background: var(--bg-color);
}

:deep(.clin-dialog .p-dialog-header) {
  background: var(--bg-color);
  color: var(--text-color);
  border-bottom: 1px solid var(--border-color);
}
</style>
