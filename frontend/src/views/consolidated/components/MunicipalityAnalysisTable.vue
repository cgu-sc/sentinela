<script setup>
import { computed } from 'vue';
import { useAnalyticsStore } from '@/stores/analytics';
import { useFilterStore } from '@/stores/filters';
import { useRiskMetrics } from '@/composables/useRiskMetrics';
import { useFormatting } from '@/composables/useFormatting';
import { useTableAggregation } from '@/composables/useTableAggregation';
import { storeToRefs } from 'pinia';
import DataTable from 'primevue/datatable';
import Column from 'primevue/column';
import Tag from 'primevue/tag';

const analyticsStore = useAnalyticsStore();
const filterStore = useFilterStore();
const { resultadoMunicipios, isLoading } = storeToRefs(analyticsStore);
const { getRiskClass } = useRiskMetrics();
const { formatBRL, formatNumber, formatPercent } = useFormatting();

// Agregação de rodapé
const { totals } = useTableAggregation(resultadoMunicipios, {
  sums: ['cnpjs', 'valSemComp', 'totalMov', 'qtdeSemComp', 'totalQtde'],
  percents: [
    { field: 'percValSemComp',  numerator: 'valSemComp',  denominator: 'totalMov'   },
    { field: 'percQtdeSemComp', numerator: 'qtdeSemComp', denominator: 'totalQtde'  },
  ],
});

const tableFooter = computed(() => {
  const t = totals.value;
  if (!Object.keys(t).length) return {};
  return {
    cnpjs:          formatNumber(t.cnpjs),
    percValSemComp: formatPercent(t.percValSemComp),
    valSemComp:     formatBRL(t.valSemComp),
    totalMov:       formatBRL(t.totalMov),
    percQtdeSemComp:formatPercent(t.percQtdeSemComp),
    qtdeSemComp:    formatNumber(t.qtdeSemComp),
    totalQtde:      formatNumber(t.totalQtde),
  };
});

const onRowSelect = (event) => {
  const { municipio, uf } = event.data;
  filterStore.selectedMunicipio = `${municipio}|${uf}`;
};
</script>

<template>
  <div class="table-section shadow-card modern-scroll-card" :class="{ 'is-refreshing': isLoading }">
    <div class="section-header">
       <div class="header-icon-box">
         <i class="pi pi-map-marker"></i>
       </div>
       <div class="header-text-box">
         <h3>Análise por município</h3>
         <span class="subtitle">{{ filterStore.selectedUF === 'Todos' ? 'Brasil' : filterStore.selectedUF }} — {{ resultadoMunicipios.length }} Municípios</span>
       </div>
       <div class="spacer"></div>
    </div>

    <DataTable 
      :value="resultadoMunicipios" 
      size="small" 
      stripedRows 
      removableSort 
      paginator 
      :rows="20"
      selectionMode="single"
      @row-click="onRowSelect"
      sortField="valSemComp"
      :sortOrder="-1"
      class="custom-table enterprise-table clickable-rows"
    >
          <Column field="uf" header="UF" sortable style="width: 5%">
            <template #footer>TOTAL</template>
          </Column>

          <Column field="municipio" header="Município" sortable style="width: 15%"></Column>

          <Column field="cnpjs" header="Qtde CNPJs" sortable style="width: 10%">
             <template #body="slotProps">
                <span>{{ formatNumber(slotProps.data.cnpjs) }}</span>
             </template>
             <template #footer>{{ tableFooter.cnpjs }}</template>
          </Column>

          <Column field="percValSemComp" header="% Valor sem Comprovação" sortable style="width: 12%">
             <template #body="slotProps">
                <Tag :value="formatPercent(slotProps.data.percValSemComp)" :class="getRiskClass(slotProps.data.percValSemComp)" />
             </template>
             <template #footer>{{ tableFooter.percValSemComp }}</template>
          </Column>

          <Column field="valSemComp" header="Valor sem Comprovação" sortable style="width: 15%">
             <template #body="slotProps">
                <span>{{ formatBRL(slotProps.data.valSemComp) }}</span>
             </template>
             <template #footer>{{ tableFooter.valSemComp }}</template>
          </Column>

          <Column field="totalMov" header="Valor Total Vendas" sortable style="width: 15%">
             <template #body="slotProps">
                <span>{{ formatBRL(slotProps.data.totalMov) }}</span>
             </template>
             <template #footer>{{ tableFooter.totalMov }}</template>
          </Column>

          <Column field="percQtdeSemComp" header="% Qtde s/ Comp" sortable style="width: 12%">
             <template #body="slotProps">
                <Tag :value="formatPercent(slotProps.data.percQtdeSemComp)" :class="getRiskClass(slotProps.data.percQtdeSemComp)" />
             </template>
             <template #footer>{{ tableFooter.percQtdeSemComp }}</template>
          </Column>
    </DataTable>
  </div>
</template>

<style scoped>
.table-section {
  display: flex;
  flex-direction: column;
  transition: all 0.3s ease;
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
  background: color-mix(in srgb, var(--accent-indigo) 10%, transparent);
  color: var(--accent-indigo);
  border-radius: 10px;
  font-size: 1.25rem;
}

.header-text-box h3 {
  margin: 0;
  font-size: 1.1rem;
  font-weight: 700;
  letter-spacing: -0.01em;
}

.subtitle {
  font-size: 0.85rem;
  color: var(--text-muted, #64748b);
}

.spacer { flex: 1; }

.is-refreshing {
  opacity: 0.5;
  pointer-events: none;
}

:deep(.clickable-rows .p-datatable-tbody > tr) {
  cursor: pointer;
}

/* Garante que o cabeçalho da tabela fique fixo ao rolar */
:deep(.p-datatable-thead) {
  position: sticky;
  top: 0;
  z-index: 10;
}

:deep(.p-datatable-wrapper) {
  border-radius: 0 0 12px 12px;
}

/* Estilização moderna da scrollbar */
:deep(.p-datatable-wrapper::-webkit-scrollbar) {
  width: 8px;
}
:deep(.p-datatable-wrapper::-webkit-scrollbar-track) {
  background: var(--bg-color, #f8fafc);
}
:deep(.p-datatable-wrapper::-webkit-scrollbar-thumb) {
  background: var(--sidebar-border, #e2e8f0);
  border-radius: 10px;
}
:deep(.p-datatable-wrapper::-webkit-scrollbar-thumb:hover) {
  background: #cbd5e1;
}

/* light/dark automático via var(--accent-indigo) — override removido */

/* RESET DE CAIXA ALTA FORÇADA */
:deep(.p-datatable-tbody td),
:deep(.p-tag-value),
:deep(.p-tag) {
  text-transform: none !important;
  font-variant: normal !important;
}
</style>
