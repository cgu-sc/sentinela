<script setup>
import { computed, ref, watch } from 'vue';
import Dialog from 'primevue/dialog';
import { INDICATOR_DETAIL_CONFIG } from '@/config/indicatorDetailConfig';
import IndicatorDetailPanel from './IndicatorDetailPanel.vue';

const props = defineProps({
  modelValue: { type: Boolean, default: false },
  cnpj: { type: String, default: '' },
  indicatorKey: { type: String, default: '' },
  perfSession: { type: Object, default: null },
});

const emit = defineEmits(['update:modelValue']);

const dialogTitle = computed(() => (
  INDICATOR_DETAIL_CONFIG[props.indicatorKey]?.title ?? 'Detalhamento do Indicador'
));

const panelRef = ref(null);
const activeCnpjTitle = ref('');
const isViewingTargetCnpj = ref(true);

function handleActiveCnpjChange(payload) {
  activeCnpjTitle.value = payload?.title ?? '';
  isViewingTargetCnpj.value = Boolean(payload?.isTarget);
}

function resetActiveCnpj() {
  panelRef.value?.resetSelectedCnpj?.();
}

watch(
  () => [props.cnpj, props.indicatorKey, props.modelValue],
  () => {
    activeCnpjTitle.value = '';
    isViewingTargetCnpj.value = true;
  },
);
</script>

<template>
  <Dialog
    v-if="modelValue"
    :visible="modelValue"
    modal
    class="indicator-detail-dialog"
    :style="{ width: '92vw', maxWidth: '1320px', height: 'auto', maxHeight: '100vh' }"
    @update:visible="emit('update:modelValue', $event)"
  >
    <template #header>
      <div class="indicator-dialog-header">
        <div class="indicator-dialog-title">{{ dialogTitle }}</div>
        <div v-if="activeCnpjTitle" class="indicator-dialog-active-cnpj">
          <span>CNPJ em análise</span>
          <strong>{{ activeCnpjTitle }}</strong>
          <button
            v-if="!isViewingTargetCnpj"
            type="button"
            class="indicator-dialog-return"
            @click="resetActiveCnpj"
          >
            <i class="pi pi-undo" aria-hidden="true" />
            <span>Voltar ao alvo</span>
          </button>
        </div>
      </div>
    </template>

    <IndicatorDetailPanel
      ref="panelRef"
      :cnpj="cnpj"
      :indicator-key="indicatorKey"
      :show-active-cnpj-header="false"
      :perf-session="perfSession"
      @active-cnpj-change="handleActiveCnpjChange"
    />
  </Dialog>
</template>

<style scoped>
.indicator-dialog-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 1rem;
  width: 100%;
  min-width: 0;
}

.indicator-dialog-title {
  min-width: 0;
  color: var(--text-color-85);
  font-size: 1.05rem;
  font-weight: 600;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.indicator-dialog-active-cnpj {
  display: inline-flex;
  align-items: center;
  gap: 0.55rem;
  min-width: 0;
  max-width: min(56vw, 720px);
  padding: 0.38rem 0.55rem;
  border: 1px solid var(--card-border);
  border-radius: 8px;
  background: var(--surface-ground);
  color: var(--text-color-85);
}

.indicator-dialog-active-cnpj > span {
  flex: 0 0 auto;
  color: var(--text-muted);
  font-size: 0.66rem;
  font-weight: 600;
  letter-spacing: 0.04em;
  text-transform: uppercase;
}

.indicator-dialog-active-cnpj > strong {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 0.82rem;
  font-weight: 600;
}

.indicator-dialog-return {
  display: inline-flex;
  align-items: center;
  gap: 0.35rem;
  flex: 0 0 auto;
  border: 1px solid rgba(245, 158, 11, 0.32);
  border-radius: 999px;
  background: rgba(245, 158, 11, 0.1);
  color: var(--warning-color, #f59e0b);
  padding: 0.22rem 0.5rem;
  font-size: 0.72rem;
  font-weight: 600;
  cursor: pointer;
}

.indicator-dialog-return:hover,
.indicator-dialog-return:focus-visible {
  background: rgba(245, 158, 11, 0.16);
  outline: none;
}
</style>
