<script setup>
import { computed } from 'vue';
import ClinicalTargetTable from './tables/ClinicalTargetTable.vue';

const props = defineProps({
  targetKey: { type: String, required: true },
  targetMeta: { type: Object, required: true },
  rows: { type: Array, default: () => [] },
  loading: { type: Boolean, default: false },
  totalRecords: { type: Number, default: 0 },
  first: { type: Number, default: 0 },
  rowsPerPage: { type: Number, default: 20 },
  sortField: { type: String, default: null },
  sortOrder: { type: Number, default: -1 },
  sourceNotice: { type: String, default: null },
});

const emit = defineEmits(['lazy-load', 'open-incompatibility']);

const tableComponent = computed(() => {
  if (props.targetMeta.tableComponent === 'ClinicalTargetTable') return ClinicalTargetTable;
  throw new Error(`Tabela sem componente para alvo: ${props.targetKey}`);
});
</script>

<template>
  <component
    :is="tableComponent"
    :target-meta="targetMeta"
    :rows="rows"
    :loading="loading"
    :total-records="totalRecords"
    :first="first"
    :rows-per-page="rowsPerPage"
    :sort-field="sortField"
    :sort-order="sortOrder"
    :source-notice="sourceNotice"
    @lazy-load="emit('lazy-load', $event)"
    @open-incompatibility="emit('open-incompatibility', $event)"
  />
</template>
