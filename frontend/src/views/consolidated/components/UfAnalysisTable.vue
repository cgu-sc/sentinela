<script setup>
import { computed } from 'vue';
import { useRouter } from 'vue-router';
import { useAnalyticsStore } from '@/stores/analytics';
import { useFilterStore } from '@/stores/filters';
import { useRiskMetrics } from '@/composables/useRiskMetrics';
import { useFormatting } from '@/composables/useFormatting';
import { useTableAggregation } from '@/composables/useTableAggregation';
import { storeToRefs } from 'pinia';
import DataTable from 'primevue/datatable';
import Column from 'primevue/column';
import Tag from 'primevue/tag';

const router = useRouter();
const analyticsStore = useAnalyticsStore();
const filterStore = useFilterStore();
const { resultadoSentinelaUF, isLoading } = storeToRefs(analyticsStore);
const { getRiskClass } = useRiskMetrics();
const { formatBRL, formatNumber, formatPercent } = useFormatting();

const { totals } = useTableAggregation(resultadoSentinelaUF, {
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
const handleRowClick = (event) => {
  filterStore.selectedUF = event.data.uf;
  router.push('/municipio');
};
</script>

<template>
  <div class="table-section shadow-card" :class="{ 'is-refreshing': isLoading }">
    <div class="section-header">
       <i class="pi pi-table"></i>
       <h3>Análise UF</h3>
       <div class="spacer"></div>
    </div>

    <DataTable 
      :value="resultadoSentinelaUF" 
      size="small" 
      stripedRows 
      removableSort 
      sortField="percValSemComp" 
      :sortOrder="-1" 
      class="custom-table enterprise-table clickable-rows"
      @row-click="handleRowClick"
    >
          <Column field="uf" header="UF" sortable style="width: 5%">
            <template #footer>TOTAL</template>
          </Column>

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

          <Column field="percQtdeSemComp" header="% Qtde Meds s/ Comp" sortable style="width: 15%">
             <template #body="slotProps">
                <Tag :value="formatPercent(slotProps.data.percQtdeSemComp)" :class="getRiskClass(slotProps.data.percQtdeSemComp)" />
             </template>
             <template #footer>{{ tableFooter.percQtdeSemComp }}</template>
          </Column>

          <Column field="qtdeSemComp" header="Qtde Meds s/ Comp" sortable style="width: 12%">
             <template #body="slotProps">
                <span>{{ formatNumber(slotProps.data.qtdeSemComp) }}</span>
             </template>
             <template #footer>{{ tableFooter.qtdeSemComp }}</template>
          </Column>

          <Column field="totalQtde" header="Qtde Total Meds" sortable style="width: 15%">
             <template #body="slotProps">
                <span>{{ formatNumber(slotProps.data.totalQtde) }}</span>
             </template>
             <template #footer>{{ tableFooter.totalQtde }}</template>
          </Column>
    </DataTable>
  </div>
</template>

<style scoped>
.table-section {
  display: flex;
  flex-direction: column;
}

.spacer { flex: 1; }

.is-refreshing {
  opacity: 0.5;
  pointer-events: none;
}

:deep(.clickable-rows .p-datatable-tbody > tr) {
  cursor: pointer;
  transition: background-color 0.2s;
}

:deep(.clickable-rows .p-datatable-tbody > tr:hover) {
  background-color: var(--primary-color-lighter, rgba(0, 0, 0, 0.04)) !important;
}

/* RESET DE CAIXA ALTA FORÇADA */
:deep(.p-datatable-thead th),
:deep(.p-datatable-tbody td),
:deep(.p-tag-value),
:deep(.p-tag) {
  text-transform: none !important;
  font-variant: normal !important;
}
</style>
