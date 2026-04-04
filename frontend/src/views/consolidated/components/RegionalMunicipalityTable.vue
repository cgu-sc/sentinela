<script setup>
/**
 * RegionalMunicipalityTable.vue
 * Exibe o resumo dos municípios da Região de Saúde selecionada:
 * população, quantidade de farmácias e densidade (hab/farmácia).
 */
import { computed } from 'vue';
import { useFormatting } from '@/composables/useFormatting';
import DataTable from 'primevue/datatable';
import Column from 'primevue/column';
import Chip from 'primevue/chip';
import Button from 'primevue/button';

const props = defineProps({
  /** Array de objetos RegionalMunicipioSchema vindos da API */
  municipios: { type: Array, default: () => [] },
  /** Município de referência para destaque visual inicial */
  municipioAtual: { type: String, default: null },
  /** UF de referência para destaque visual inicial */
  ufAtual: { type: String, default: null },
  /** Nome do município que está sendo usado como filtro (opcional) */
  selectedFilter: { type: String, default: null },
});

/** Row class para destacar o município em análise. */
function rowClass(data) {
  const isCurrent = props.municipioAtual && 
                    data.municipio?.toUpperCase() === props.municipioAtual?.toUpperCase() &&
                    data.uf?.toUpperCase() === props.ufAtual?.toUpperCase();
  return isCurrent ? 'row-highlight' : '';
}

const emits = defineEmits(['select-municipio']);

const { formatNumber } = useFormatting();

function onRowClick(event) {
  // Se clicar no que já está selecionado, poderíamos limpar, 
  // mas vamos apenas emitir e o pai decide se limpa ou troca.
  emits('select-municipio', event.data.municipio);
}

// Totalizador de rodapé
const totals = computed(() => {
  const pop     = props.municipios.reduce((s, m) => s + (m.populacao  || 0), 0);
  const far     = props.municipios.reduce((s, m) => s + (m.qtd_farmacias || 0), 0);
  const dens    = far > 0 ? pop / far : 0;
  return { pop, far, dens: Math.round(dens) };
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
      sortField="populacao"
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

      <Column field="populacao" header="População" sortable style="width: 20%" class="align-right">
        <template #body="{ data }">
          {{ (data.populacao || 0).toLocaleString('pt-BR') }}
        </template>
        <template #footer>
          {{ totals.pop.toLocaleString('pt-BR') }}
        </template>
      </Column>

      <Column field="qtd_farmacias" header="Farmácias" sortable style="width: 15%" class="align-center">
        <template #body="{ data }">
          <span class="badge-count">{{ data.qtd_farmacias }}</span>
        </template>
        <template #footer>
          {{ totals.far }}
        </template>
      </Column>

      <Column field="densidade" header="Hab. / Farmácia" sortable style="width: 20%" class="align-right">
        <template #body="{ data }">
          {{ (data.densidade || 0).toLocaleString('pt-BR', { maximumFractionDigits: 0 }) }}
        </template>
        <template #footer>
          {{ totals.dens.toLocaleString('pt-BR') }}
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
  gap: 0.4rem;
  background: color-mix(in srgb, var(--text-color) 4%, var(--tabs-bg));
  border: 1px solid var(--tabs-border);
  padding: 0 0.5rem;
  height: 24px; /* Altura fixa controlada */
  border-radius: 4px;
  animation: fadeIn 0.2s ease-out;
}

.filter-label {
  font-size: 0.65rem;
  font-weight: 700;
  text-transform: uppercase;
  color: var(--text-muted);
  letter-spacing: 0.05em;
}

.filter-value {
  font-size: 0.72rem;
  font-weight: 600;
  color: var(--text-color);
  letter-spacing: 0.02em;
}

.filter-clear-btn {
  background: transparent;
  border: none;
  cursor: pointer;
  padding: 0 0.2rem;
  display: flex;
  align-items: center;
  transition: all 0.15s ease;
  color: var(--text-muted);
}

.filter-clear-btn:hover {
  color: var(--risk-high);
  transform: scale(1.1);
}

.filter-clear-btn i {
  font-size: 0.7rem;
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
