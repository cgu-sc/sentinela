<script setup>
import { computed } from 'vue';
import Dialog from 'primevue/dialog';
import { INDICATOR_DETAIL_CONFIG } from '@/config/indicatorDetailConfig';
import IndicatorDetailPanel from './IndicatorDetailPanel.vue';

const props = defineProps({
  modelValue: { type: Boolean, default: false },
  cnpj: { type: String, default: '' },
  indicatorKey: { type: String, default: '' },
});

const emit = defineEmits(['update:modelValue']);

const dialogTitle = computed(() => (
  INDICATOR_DETAIL_CONFIG[props.indicatorKey]?.title ?? 'Detalhamento do Indicador'
));
</script>

<template>
  <Dialog
    v-if="modelValue"
    :visible="modelValue"
    :header="dialogTitle"
    modal
    class="indicator-detail-dialog"
    :style="{ width: '92vw', maxWidth: '1320px', height: 'auto', maxHeight: '90vh' }"
    @update:visible="emit('update:modelValue', $event)"
  >
    <IndicatorDetailPanel
      :cnpj="cnpj"
      :indicator-key="indicatorKey"
    />
  </Dialog>
</template>
