<script setup>
/**
 * RegionalMunicipalityTable.vue
 * Exibe o resumo dos municípios da Região de Saúde selecionada:
 * população, quantidade de farmácias e densidade (hab/farmácia).
 */
import { computed } from 'vue';
import { useFormatting } from '@/composables/useFormatting';
import { useRiskMetrics } from '@/composables/useRiskMetrics';
import DataTable from 'primevue/datatable';
import Column from 'primevue/column';
import Tag from 'primevue/tag';

const props = defineProps({
  municipios: { type: Array, default: () => [] },
  municipioAtual: { type: String, default: null },
  ufAtual: { type: String, default: null },
  selectedFilter: { type: String, default: null },
});

const emits = defineEmits(['select-municipio']);

const { formatBRL, formatPercent } = useFormatting();
const { getRiskClass } = useRiskMetrics();

function rowClass(data) {
  const isCurrent = props.municipioAtual &&
                    data.municipio?.toUpperCase() === props.municipioAtual?.toUpperCase() &&
                    data.uf?.toUpperCase() === props.ufAtual?.toUpperCase();
  return isCurrent ? 'row-highlight' : '';
}

function onRowClick(event) {
  emits('select-municipio', event.data.municipio);
}

const totals = computed(() => {
  const pop      = props.municipios.reduce((s, m) => s + (m.populacao      || 0), 0);
  const far      = props.municipios.reduce((s, m) => s + (m.qtd_farmacias  || 0), 0);
  const totalMov = props.municipios.reduce((s, m) => s + (m.totalMov       || 0), 0);
  const valSem   = props.municipios.reduce((s, m) => s + (m.valSemComp     || 0), 0);
  const dens     = far > 0 ? pop / far : 0;
  const perc     = totalMov > 0 ? (valSem / totalMov) * 100 : 0;
  return { pop, far, dens: Math.round(dens), totalMov, valSem, perc };
});
</script>

<template>
  <div class="table-section">
    <div class="section-header">
      <i class="pi pi-map-marker section-icon"></i>
      <div class="header-text-box">
        <div class="title-with-filter">
          <h3 class="section-title-text">MUNICÍPIOS DA REGIÃO</h3>
          <div v-if="selectedFilter" class="active-filter-tag">
            <span class="filter-label">Filtro:</span>
            <span class="filter-value">{{ selectedFilter.toUpperCase() }}</span>
            <button 
              class="filter-clear-btn" 
              title="Limpar Filtro"
              @click="emits('select-municipio', selectedFilter)"
            >
              <i class="pi pi-times" />
            </button>
          </div>
        </div>
        <p class="subtitle">{{ municipios.length }} municípios na região</p>
      </div>
    </div>

    <DataTable
      :value="municipios"
      size="small"
      removableSort
      sortField="valSemComp"
      :sortOrder="-1"
      :row-class="rowClass"
      class="custom-table enterprise-table clickable-rows"
      @row-click="onRowClick"
    >
      <Column field="uf" header="UF" sortable style="width: 6%" />

      <Column field="municipio" header="Município" sortable style="width: 30%; text-transform: none">
        <template #footer>
          {{ municipios.length }} Municípios
        </template>
      </Column>

      <Column field="populacao" header="População" sortable style="width: 10%">
        <template #body="{ data }">
          {{ (data.populacao || 0).toLocaleString('pt-BR') }}
        </template>
        <template #footer>
          {{ totals.pop.toLocaleString('pt-BR') }}
        </template>
      </Column>

      <Column field="qtd_farmacias" header="Farmácias" sortable style="width: 8%" class="align-center">
        <template #body="{ data }">
          <span class="badge-count">{{ data.qtd_farmacias }}</span>
        </template>
        <template #footer>
          {{ totals.far }}
        </template>
      </Column>

      <Column field="densidade" header="Hab./Farm." sortable style="width: 10%">
        <template #body="{ data }">
          {{ (data.densidade || 0).toLocaleString('pt-BR', { maximumFractionDigits: 0 }) }}
        </template>
        <template #footer>
          {{ totals.dens.toLocaleString('pt-BR') }}
        </template>
      </Column>

      <Column field="totalMov" header="Total Vendas" sortable style="width: 14%">
        <template #body="{ data }">
          {{ formatBRL(data.totalMov) }}
        </template>
        <template #footer>
          {{ formatBRL(totals.totalMov) }}
        </template>
      </Column>

      <Column field="valSemComp" header="Valor s/ Comp." sortable style="width: 14%">
        <template #body="{ data }">
          {{ formatBRL(data.valSemComp) }}
        </template>
        <template #footer>
          {{ formatBRL(totals.valSem) }}
        </template>
      </Column>

      <Column field="percValSemComp" header="% s/ Comp." sortable style="width: 10%">
        <template #body="{ data }">
          <Tag :value="formatPercent(data.percValSemComp)" :class="getRiskClass(data.percValSemComp)" />
        </template>
        <template #footer>
          {{ formatPercent(totals.perc) }}
        </template>
      </Column>
    </DataTable>
  </div>
</template>

<style scoped>
.table-section {
  display: flex;
  flex-direction: column;
  background: var(--tabs-bg);
  border: 1px solid var(--tabs-border);
  border-radius: 12px;
  padding: 1.25rem;
  box-shadow: 0 4px 15px rgba(0,0,0,0.1);
}

.section-header {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  padding: 0.5rem 0;
  border-bottom: 1px solid var(--tabs-border);
  margin-bottom: 1rem;
}

.section-icon {
  font-size: 1rem;
  color: var(--primary-color);
}

.header-text-box {
  display: flex;
  flex-direction: column;
}

.header-text-box h3 {
  margin: 0;
  padding: 0;
}

.header-text-box p {
  margin: 0;
  padding: 0;
}

.section-title-text {
  font-size: 0.85rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--text-color);
  line-height: 1.2;
}

.title-with-filter {
  display: flex;
  align-items: center;
  gap: 1rem;
  min-height: 28px; /* Reserva o espaço para evitar o "salto" no layout */
}

.active-filter-tag {
  display: inline-flex;
  align-items: center;
  gap: 0.5rem;
  background: color-mix(in srgb, var(--primary-color) 12%, var(--card-bg));
  border: 1px solid color-mix(in srgb, var(--primary-color) 40%, transparent);
  padding: 0 0.75rem;
  height: 28px;
  border-radius: 6px;
  animation: fadeIn 0.2s ease-out;
  box-shadow: 0 0 0 3px color-mix(in srgb, var(--primary-color) 10%, transparent);
}

.filter-label {
  font-size: 0.65rem;
  font-weight: 700;
  text-transform: uppercase;
  color: var(--primary-color);
  letter-spacing: 0.06em;
}

.filter-value {
  font-size: 0.8rem;
  font-weight: 700;
  color: var(--primary-color);
  letter-spacing: 0.02em;
}

.filter-clear-btn {
  background: transparent;
  border: none;
  cursor: pointer;
  padding: 0 0.15rem;
  display: flex;
  align-items: center;
  transition: all 0.15s ease;
  color: var(--primary-color);
  opacity: 0.7;
}

.filter-clear-btn:hover {
  color: var(--risk-high);
  opacity: 1;
  transform: scale(1.15);
}

.filter-clear-btn i {
  font-size: 0.75rem;
}

@keyframes pulse-mini {
  0%, 100% { box-shadow: 0 0 0 0 color-mix(in srgb, var(--risk-high) 25%, transparent); }
  50%       { box-shadow: 0 0 0 5px color-mix(in srgb, var(--risk-high) 0%, transparent); }
}

@keyframes fadeIn {
  from { opacity: 0; transform: translateX(-10px); }
  to { opacity: 1; transform: translateX(0); }
}

.subtitle {
  font-size: 0.85rem;
  color: var(--text-muted, #64748b);
}

.badge-count {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  padding: 0.15rem 0.55rem;
  border-radius: 20px;
  font-size: 0.78rem;
  font-weight: 700;
  background: color-mix(in srgb, var(--primary-color) 12%, transparent);
  color: var(--primary-color);
}

:deep(.p-datatable),
:deep(.p-datatable-wrapper),
:deep(.p-datatable-table),
:deep(.p-datatable-thead > tr > th),
:deep(.p-datatable-tbody > tr > td),
:deep(.p-datatable-tfoot > tr > td) {
  background: var(--tabs-bg) !important;
  background-color: var(--tabs-bg) !important;
}

:deep(.p-datatable .p-datatable-thead > tr > th) {
  color: var(--text-secondary) !important;
  font-size: 0.72rem !important;
  font-weight: 600 !important;
  text-transform: uppercase !important;
  letter-spacing: 0.05em !important;
  border-bottom: 2px solid var(--tabs-border) !important;
  padding: 0.75rem 1rem !important;
}

:deep(.p-datatable .p-datatable-tbody > tr > td) {
  cursor: pointer;
  border-bottom: 1px solid var(--tabs-border) !important;
  transition: background-color 0.15s ease;
}

:deep(.p-datatable .p-datatable-tbody > tr:hover > td) {
  background: color-mix(in srgb, var(--text-color) 4%, var(--tabs-bg)) !important;
  cursor: pointer;
}

:deep(.p-datatable .p-datatable-tfoot > tr > td) {
  background: color-mix(in srgb, var(--tabs-bg) 95%, var(--text-color) 5%) !important;
  border-top: 2px solid var(--tabs-border) !important;
  font-weight: 600 !important;
  color: var(--text-color) !important;
  padding: 0.75rem 1rem !important;
}

:deep(.p-datatable-thead) {
  position: sticky;
  top: 0;
  z-index: 10;
  background: var(--tabs-bg) !important;
}

/* Padroniza o destaque do município analisado (Estilo Hover Persistente) */
:deep(.p-datatable-tbody > tr.row-highlight > td) {
  background: color-mix(in srgb, var(--primary-color) 8%, var(--tabs-bg)) !important;
}

:deep(.p-datatable .p-datatable-tbody > tr.row-highlight > td:first-child) {
  border-left: 4px solid var(--primary-color) !important;
}

:deep(.enterprise-table .p-datatable-tbody > tr.row-highlight td:first-child) {
  border-left: 4px solid var(--primary-color) !important;
}

/* Força o alinhamento dos cabeçalhos numéricos */
:deep(.align-right .p-column-header-content) {
  justify-content: flex-end !important;
  text-align: right !important;
}

:deep(.align-center .p-column-header-content) {
  justify-content: center !important;
  text-align: center !important;
}

/* Garante que o corpo e o rodapé sigam a mesma regra */
:deep(.align-right) {
  text-align: right !important;
}

:deep(.align-center) {
  text-align: center !important;
}

/* Padroniza todos os headers para o novo padrão Clean */
:deep(.p-datatable-thead th) {
  background: transparent !important;
  color: var(--text-secondary) !important;
  font-size: 0.72rem !important;
  font-weight: 600 !important;
  text-transform: uppercase !important;
  letter-spacing: 0.05em !important;
  border-bottom: 2px solid var(--tabs-border) !important;
  padding: 0.75rem 1rem !important;
}

:deep(.p-datatable-tbody td),
:deep(.p-tag-value),
:deep(.p-tag) {
  text-transform: none !important;
  font-variant: normal !important;
}
</style>
