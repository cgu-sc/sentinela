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
const { resultadoSentinelaUF, isLoading } = storeToRefs(analyticsStore);
const { getRiskClass } = useRiskMetrics();
const { formatBRL, formatNumber, formatPercent } = useFormatting();

const filteredData = computed(() => {
  if (filterStore.selectedUF === 'Todos') {
    return resultadoSentinelaUF.value;
  }
  return resultadoSentinelaUF.value.filter(item => item.uf === filterStore.selectedUF);
});

const { totals } = useTableAggregation(filteredData, {
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
</script>

<template>
  <div class="table-section shadow-card" :class="{ 'is-refreshing': isLoading }">
    <div class="section-header">
       <i class="pi pi-table"></i>
       <h3>ANÁLISE NACIONAL</h3>
       <div class="spacer"></div>
    </div>

    <DataTable :value="filteredData" size="small" stripedRows removableSort sortField="percValSemComp" :sortOrder="-1" class="custom-table enterprise-table">
          <Column field="uf" header="UF" sortable style="width: 5%">
            <template #footer>TOTAL</template>
          </Column>

          <Column field="cnpjs" header="Qtde CNPJs" sortable style="width: 10%">
             <template #body="slotProps">
                <span>{{ formatNumber(slotProps.data.cnpjs) }}</span>
             </template>
             <template #footer>{{ tableFooter.cnpjs }}</template>
          </Column>

          <Column field="percValSemComp" header="% Valor Sem Comprovação" sortable style="width: 12%">
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

          <Column field="totalMov" header="Valor Total Movimentado" sortable style="width: 15%">
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
</style>
