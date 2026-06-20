<template>
  <Transition name="cnpj-tab-loading-fade">
    <div v-if="visible" class="cnpj-tab-loading-overlay" aria-live="polite" aria-busy="true">
      <div class="cnpj-tab-loading-overlay__box">
        <i class="pi pi-spin pi-spinner" aria-hidden="true" />
        <span>Carregando...</span>
      </div>
    </div>
  </Transition>
</template>

<script setup>
defineProps({
  visible: {
    type: Boolean,
    default: false,
  },
});
</script>

<style scoped>
.cnpj-tab-loading-overlay {
  position: absolute;
  inset: 0;
  z-index: 20;
  display: flex;
  align-items: center;
  justify-content: center;
  min-height: 18rem;
  background: color-mix(in srgb, var(--bg-color) 68%, transparent);
  backdrop-filter: blur(2px);
  -webkit-backdrop-filter: blur(2px);
  pointer-events: all;
}

.cnpj-tab-loading-overlay__box {
  display: inline-flex;
  align-items: center;
  gap: 0.75rem;
  padding: 0.9rem 1.1rem;
  border: 1px solid var(--card-border);
  border-radius: 10px;
  background: var(--card-bg);
  color: var(--text-color-85);
  box-shadow: 0 12px 28px color-mix(in srgb, var(--text-color-85) 12%, transparent);
  font-size: 0.9rem;
  font-weight: 600;
}

.cnpj-tab-loading-overlay__box i {
  color: var(--primary-color);
  font-size: 1rem;
}

.cnpj-tab-loading-fade-enter-active,
.cnpj-tab-loading-fade-leave-active {
  transition: opacity 0.18s ease;
}

.cnpj-tab-loading-fade-enter-from,
.cnpj-tab-loading-fade-leave-to {
  opacity: 0;
}
</style>
