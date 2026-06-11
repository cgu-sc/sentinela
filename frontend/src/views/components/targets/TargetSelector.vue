<script setup>
import { computed } from 'vue';
import { TARGET_GROUPS } from '@/config/targetConfig';

const props = defineProps({
  selectedTarget: { type: String, required: true },
});

const emit = defineEmits(['select']);

const activeTargetMeta = computed(() => {
  for (const group of TARGET_GROUPS) {
    const target = group.targets.find(item => item.key === props.selectedTarget);
    if (target) return target;
  }
  throw new Error(`Alvo selecionado sem configuração: ${props.selectedTarget}`);
});

function selectTarget(target) {
  if (!target.enabled) return;
  emit('select', target.key);
}
</script>

<template>
  <aside class="target-selector">
    <div class="selector-header">
      <i class="pi pi-bullseye selector-header-icon" />
      <span class="selector-header-label">Alvos</span>
    </div>

    <div class="selector-groups">
      <div
        v-for="group in TARGET_GROUPS"
        :key="group.id"
        class="selector-group"
      >
        <div class="group-title">{{ group.label }}</div>

        <button
          v-for="target in group.targets"
          :key="target.key"
          type="button"
          class="target-btn"
          :class="{
            'target-btn--active': selectedTarget === target.key,
            'target-btn--disabled': !target.enabled,
          }"
          :disabled="!target.enabled"
          v-tooltip.left="{ value: target.description, class: 'target-tooltip' }"
          @click="selectTarget(target)"
        >
          <span class="target-btn-label">{{ target.label }}</span>
          <span v-if="!target.enabled" class="target-btn-badge">Em breve</span>
        </button>
      </div>
    </div>

    <Transition name="target-info">
      <div class="target-info-box">
        <div class="target-info-label">{{ activeTargetMeta.label }}</div>
        <p class="target-info-description">{{ activeTargetMeta.description }}</p>
      </div>
    </Transition>
  </aside>
</template>

<style scoped>
.target-selector {
  width: var(--target-selector-width, 220px);
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

.target-btn {
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
  transition: background 0.15s ease, color 0.15s ease, opacity 0.15s ease;
  color: var(--text-color-85);
  opacity: 0.8;
  min-width: 0;
}

.target-btn:hover:not(:disabled) {
  background: var(--table-hover);
  opacity: 1;
}

.target-btn--active {
  background: color-mix(in srgb, var(--primary-color) 12%, var(--card-bg));
  opacity: 1;
  border-left: 3px solid var(--primary-color);
  padding-left: calc(1rem - 3px);
}

.target-btn--active .target-btn-label {
  color: var(--primary-color);
  font-weight: 600;
}

.target-btn--disabled {
  cursor: not-allowed;
  opacity: 0.42;
}

.target-btn-label {
  font-size: 0.78rem;
  font-weight: 500;
  line-height: 1.2;
  flex: 1;
  min-width: 0;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.target-btn-badge {
  flex-shrink: 0;
  font-size: 0.58rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--text-muted);
}

.target-info-box {
  margin: 0.5rem 0.75rem 0.75rem;
  padding: 0.7rem 0.85rem;
  background: color-mix(in srgb, var(--primary-color) 7%, var(--card-bg));
  border: 1px solid color-mix(in srgb, var(--primary-color) 20%, transparent);
  border-radius: 8px;
  display: flex;
  flex-direction: column;
  gap: 0.35rem;
}

.target-info-label {
  font-size: 0.72rem;
  font-weight: 600;
  color: var(--primary-color);
  line-height: 1.3;
}

.target-info-description {
  margin: 0;
  font-size: 0.68rem;
  color: var(--text-muted);
  line-height: 1.5;
}

.target-info-enter-active,
.target-info-leave-active {
  transition: opacity 0.2s ease, transform 0.2s ease;
}

.target-info-enter-from,
.target-info-leave-to {
  opacity: 0;
  transform: translateY(4px);
}
</style>
