<script setup>
import { computed } from 'vue';
import { storeToRefs } from 'pinia';
import { useIndicadoresStore } from '@/stores/indicadores';
import { INDICATOR_GROUPS } from '@/config/riskConfig';

const emit = defineEmits(['select']);

const indicadoresStore = useIndicadoresStore();
const { selectedIndicador, kpis, isLoading } = storeToRefs(indicadoresStore);

// Badge de contagem CRÍTICO para o indicador ativo
const criticoCount = computed(() => kpis.value?.total_critico ?? 0);

function selectIndicador(key) {
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
          :class="{ 'ind-btn--active': selectedIndicador === ind.key }"
          @click="selectIndicador(ind.key)"
          :title="ind.metodologia"
        >
          <span class="ind-btn-label">{{ ind.label }}</span>
          <span
            v-if="selectedIndicador === ind.key && criticoCount > 0 && !isLoading"
            class="ind-critico-badge"
          >{{ criticoCount }}</span>
          <i
            v-if="isLoading && selectedIndicador === ind.key"
            class="pi pi-spin pi-spinner ind-loading-icon"
          />
        </button>
      </div>
    </div>
  </aside>
</template>

<style scoped>
.indicator-selector {
  width: 260px;
  flex-shrink: 0;
  display: flex;
  flex-direction: column;
  gap: 0;
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  border-radius: 12px;
  overflow-y: auto;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.06);
  align-self: flex-start;
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
  color: var(--text-color);
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
  color: var(--text-color);
  opacity: 0.8;
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
  line-height: 1.4;
  flex: 1;
}

.ind-critico-badge {
  flex-shrink: 0;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 1.4rem;
  height: 1.4rem;
  padding: 0 0.3rem;
  background: var(--risk-indicator-critical);
  color: #fff;
  font-size: 0.65rem;
  font-weight: 600;
  border-radius: 99px;
}

.ind-loading-icon {
  flex-shrink: 0;
  font-size: 0.7rem;
  color: var(--primary-color);
  opacity: 0.7;
}
</style>
