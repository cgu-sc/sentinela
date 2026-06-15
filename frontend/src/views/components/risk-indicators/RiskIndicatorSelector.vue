<script setup>
import { computed } from 'vue';
import { storeToRefs } from 'pinia';
import { useRiskIndicatorsStore } from '@/stores/riskIndicators';
import { INDICATOR_GROUPS } from '@/config/riskConfig';

const props = defineProps({
  /** Metadados do indicador ativo { label, metodologia } */
  activeRiskIndicatorMeta: { type: Object, default: null },
});

const emit = defineEmits(['select']);

const riskIndicatorsStore = useRiskIndicatorsStore();
const { selectedRiskIndicator, kpis, isLoading } = storeToRefs(riskIndicatorsStore);



function selectRiskIndicator(key) {
  emit('select', key);
}
</script>

<template>
  <aside class="indicator-selector">
    <div class="selector-header">
      <i class="pi pi-shield selector-header-icon" />
      <span class="selector-header-label">Indicadores</span>
    </div>

    <div class="selector-groups">
      <div
        v-for="grupo in INDICATOR_GROUPS"
        :key="grupo.id"
        class="selector-group"
      >
        <div class="group-title">{{ grupo.label }}</div>

        <button
          v-for="ind in grupo.indicators"
          :key="ind.key"
          class="ind-btn"
          :class="{ 'ind-btn--active': selectedRiskIndicator === ind.key }"
          @click="selectRiskIndicator(ind.key)"
          :title="ind.metodologia"
        >
          <span class="ind-btn-label">{{ ind.label }}</span>

          <i
            v-if="isLoading && selectedRiskIndicator === ind.key"
            class="pi pi-spin pi-spinner ind-loading-icon"
          />
        </button>
      </div>
    </div>

    <!-- Info do indicador ativo -->
    <Transition name="ind-info">
      <div v-if="activeRiskIndicatorMeta" class="ind-info-box">
        <div class="ind-info-label">{{ activeRiskIndicatorMeta.label }}</div>
        <p class="ind-info-metodologia">{{ activeRiskIndicatorMeta.metodologia }}</p>
      </div>
    </Transition>
  </aside>
</template>

<style scoped>
.indicator-selector {
  width: var(--indicator-selector-width, 260px);
  flex-shrink: 0;
  position: sticky;
  top: 0;
  min-height: calc(100dvh - 56px - 1.25rem);
  display: flex;
  flex-direction: column;
  gap: 0;
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  border-radius: 8px;
  overflow: visible;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.06);
  align-self: start;
}

.selector-header {
  display: flex;
  align-items: center;
  gap: 0.6rem;
  padding: 0.9rem 1rem;
  border-bottom: 1px solid var(--card-border);
  background: color-mix(in srgb, var(--primary-color) 6%, var(--card-bg));
}

.selector-header-icon {
  font-size: 0.9rem;
  color: var(--primary-color);
}

.selector-header-label {
  font-size: 0.75rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: var(--text-color-85);
  opacity: 0.85;
}

.selector-groups {
  display: flex;
  flex-direction: column;
  padding: 0.5rem 0;
}

.selector-group {
  display: flex;
  flex-direction: column;
}

.group-title {
  padding: 0.6rem 1rem 0.25rem;
  font-size: 0.65rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.07em;
  color: var(--primary-color);
  opacity: 0.75;
  border-top: 1px solid var(--card-border);
  margin-top: 0.25rem;
}

.selector-group:first-child .group-title {
  border-top: none;
  margin-top: 0;
}

.ind-btn {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.4rem;
  padding: 0.5rem 1rem;
  min-height: 2.4rem;
  background: transparent;
  border: none;
  cursor: pointer;
  text-align: left;
  transition: background 0.15s ease, color 0.15s ease;
  color: var(--text-color-85);
  opacity: 0.8;
  min-width: 0;
}

.ind-btn:hover {
  background: var(--table-hover);
  opacity: 1;
}

.ind-btn--active {
  background: color-mix(in srgb, var(--primary-color) 12%, var(--card-bg));
  opacity: 1;
  border-left: 3px solid var(--primary-color);
  padding-left: calc(1rem - 3px);
}

.ind-btn--active .ind-btn-label {
  color: var(--primary-color);
  font-weight: 600;
}

.ind-btn-label {
  font-size: 0.78rem;
  font-weight: 500;
  line-height: 1.2;
  flex: 1;
  min-width: 0;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}



.ind-loading-icon {
  flex-shrink: 0;
  font-size: 0.7rem;
  color: var(--primary-color);
  opacity: 0.7;
}

/* ── Info do indicador ativo ── */
.ind-info-box {
  margin: 0.5rem 0.75rem 0.75rem;
  padding: 0.7rem 0.85rem;
  background: color-mix(in srgb, var(--primary-color) 7%, var(--card-bg));
  border: 1px solid color-mix(in srgb, var(--primary-color) 20%, transparent);
  border-radius: 8px;
  display: flex;
  flex-direction: column;
  gap: 0.35rem;
}

.ind-info-label {
  font-size: 0.72rem;
  font-weight: 600;
  color: var(--primary-color);
  line-height: 1.3;
}

.ind-info-metodologia {
  margin: 0;
  font-size: 0.68rem;
  color: var(--text-muted);
  line-height: 1.5;
}

/* Transição suave ao aparecer/desaparecer */
.ind-info-enter-active,
.ind-info-leave-active {
  transition: opacity 0.2s ease, transform 0.2s ease;
}
.ind-info-enter-from,
.ind-info-leave-to {
  opacity: 0;
  transform: translateY(4px);
}
</style>
