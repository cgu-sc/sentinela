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
  <div class="table-section shadow-card modern-scroll-card">
    <div class="section-header">
      <div class="header-icon-box">
        <i class="pi pi-map-marker"></i>
      </div>
      <div class="header-text-box">
        <div class="title-with-filter">
          <h3>MUNICÍPIOS DA REGIÃO</h3>
          <div v-if="selectedFilter" class="active-filter-inline">
            <i class="pi pi-angle-right sep-icon" />
            <Chip 
              :label="selectedFilter" 
              class="municipio-chip-mini" 
            />
            <Button 
              label="Limpar" 
              icon="pi pi-refresh" 
              outlined 
              severity="warn"
              size="small"
              class="clear-filter-btn filters-active"
              @click="emits('select-municipio', selectedFilter)"
            />
          </div>
        </div>
        <span class="subtitle">{{ municipios.length }} municípios na região</span>
      </div>
    </div>

    <DataTable
      :value="municipios"
      size="small"
      stripedRows
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
          <strong>{{ municipios.length }} Municípios</strong>
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
}

.modern-scroll-card {
  border: 1px solid var(--sidebar-border, #e2e8f0);
  background: var(--card-bg, #ffffff);
}

.section-header {
  padding: 1.25rem 1.5rem;
  display: flex;
  align-items: center;
  gap: 1rem;
  border-bottom: 1px solid var(--sidebar-border, #e2e8f0);
}

.header-icon-box {
  width: 42px;
  height: 42px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: color-mix(in srgb, var(--accent-teal, #0d9488) 10%, transparent);
  color: var(--accent-teal, #0d9488);
  border-radius: 10px;
  font-size: 1.25rem;
}

.header-text-box h3 {
  margin: 0;
  font-size: 1.1rem;
  font-weight: 700;
  letter-spacing: -0.01em;
}

.title-with-filter {
  display: flex;
  align-items: center;
  gap: 0.75rem;
}

.active-filter-inline {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  animation: fadeIn 0.2s ease-out;
}

.sep-icon {
  font-size: 0.8rem;
  opacity: 0.3;
}

:deep(.municipio-chip-mini) {
  background: color-mix(in srgb, var(--primary-color) 12%, transparent) !important;
  color: var(--primary-color) !important;
  border: 1px solid color-mix(in srgb, var(--primary-color) 25%, transparent) !important;
  font-weight: 700 !important;
  font-size: 0.75rem !important;
  height: 24px !important;
  padding: 0 8px !important;
}

/* BOTÃO LIMPAR (Igual Sidebar) */
:deep(.clear-filter-btn.p-button) {
  height: 24px !important;
  font-size: 0.72rem !important;
  padding: 0 10px !important;
  background: transparent !important;
  font-weight: 700 !important;
  text-transform: uppercase !important;
  letter-spacing: 0.02em !important;
}

:deep(.filters-active.p-button),
:deep(.filters-active.p-button:enabled:hover) {
  background: transparent !important;
  border-color: var(--risk-high) !important;
  color: var(--risk-high) !important;
  animation: pulse-mini 1.5s ease-in-out infinite !important;
}

:deep(.filters-active.p-button .p-button-label),
:deep(.filters-active.p-button .p-button-icon),
:deep(.filters-active.p-button:enabled:hover .p-button-label),
:deep(.filters-active.p-button:enabled:hover .p-button-icon) {
  color: var(--risk-high) !important;
}

:deep(.filters-active.p-button:enabled:hover) {
  background: color-mix(in srgb, var(--risk-high) 8%, transparent) !important;
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

:deep(.clickable-rows .p-datatable-tbody > tr) {
  cursor: pointer;
  transition: background-color 0.15s ease;
}

:deep(.clickable-rows .p-datatable-tbody > tr:hover td) {
  background: color-mix(in srgb, var(--primary-color) 4%, var(--card-bg)) !important;
}

:deep(.p-datatable-thead) {
  position: sticky;
  top: 0;
  z-index: 10;
}

/* Linha destacada para o Município em análise */
:deep(.enterprise-table .p-datatable-tbody > tr.row-highlight td) {
  background: color-mix(in srgb, var(--primary-color) 12%, var(--card-bg)) !important;
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
</style>
