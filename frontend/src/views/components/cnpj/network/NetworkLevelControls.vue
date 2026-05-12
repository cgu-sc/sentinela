<script setup>
defineProps({
  currentLevel: {
    type: String,
    required: true,
  },
  loadingLevel: {
    type: [String, null],
    default: null,
  },
  isBatchExpanding: {
    type: Boolean,
    default: false,
  },
  showHelp: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(["reset-n2", "expand", "toggle-help"]);
</script>

<template>
  <div class="toolbar-pill">
    <button
      class="seg-btn"
      :class="{ 'seg-active': currentLevel === 'N2' }"
      :disabled="isBatchExpanding || currentLevel === 'N2'"
      @click="emit('reset-n2')"
    >
      <i class="pi pi-refresh" />
      <span>Nível 2</span>
    </button>
    <div class="pill-sep"></div>
    <button
      class="seg-btn"
      :class="{ 'seg-active': currentLevel === 'N3' }"
      :disabled="isBatchExpanding || currentLevel === 'N3'"
      @click="emit('expand', 'N3')"
    >
      <i :class="loadingLevel === 'N3' ? 'pi pi-spin pi-spinner' : 'pi pi-users'" />
      <span>Nível 3</span>
    </button>
    <button
      class="seg-btn"
      :class="{ 'seg-active': currentLevel === 'N4' }"
      :disabled="isBatchExpanding || currentLevel === 'N4'"
      @click="emit('expand', 'N4')"
    >
      <i :class="loadingLevel === 'N4' ? 'pi pi-spin pi-spinner' : 'pi pi-sitemap'" />
      <span>Nível 4</span>
    </button>
    <div class="pill-sep"></div>
    <div class="level-help-menu-root">
      <button
        class="seg-btn level-help-btn"
        :class="{ 'seg-active': showHelp }"
        type="button"
        aria-label="Ajuda sobre níveis"
        @click="emit('toggle-help')"
      >
        <i class="pi pi-question-circle" />
      </button>

      <div v-if="showHelp" class="level-help-menu" @click.stop>
        <div class="level-help-item">
          <strong>Nível 2</strong>
          <span>CNPJ em análise, sócios diretos e empresas ligadas a esses sócios.</span>
        </div>
        <div class="level-help-item">
          <strong>Nível 3</strong>
          <span>Adiciona os sócios das empresas encontradas no nível 2.</span>
        </div>
        <div class="level-help-item">
          <strong>Nível 4</strong>
          <span>Adiciona empresas ligadas aos sócios encontrados no nível 3.</span>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.seg-btn {
  background: transparent;
  border: none;
  color: var(--text-secondary);
  padding: 5px 11px;
  border-radius: 20px;
  cursor: pointer;
  display: flex;
  align-items: center;
  gap: 5px;
  font-size: 0.71rem;
  font-weight: 500;
  transition:
    background 0.18s,
    color 0.18s,
    box-shadow 0.18s;
  white-space: nowrap;
}

.seg-btn:hover:not(:disabled) {
  background: rgba(255, 255, 255, 0.07);
  color: #94a3b8;
}

.seg-btn.seg-active {
  background: var(--primary-color);
  color: #fff;
  box-shadow: 0 2px 10px rgba(99, 102, 241, 0.38);
}

.seg-btn:disabled {
  opacity: 0.38;
  cursor: not-allowed;
}

.level-help-menu-root {
  position: relative;
  display: inline-flex;
}

.level-help-btn {
  width: 28px;
  height: 28px;
  justify-content: center;
  padding: 0;
}

.level-help-menu {
  position: absolute;
  top: calc(100% + 0.55rem);
  left: 0;
  z-index: 40;
  width: 286px;
  display: flex;
  flex-direction: column;
  gap: 0.6rem;
  padding: 0.8rem 0.9rem;
  background: var(--card-bg);
  border: 1px solid var(--tabs-border);
  border-radius: 10px;
  box-shadow:
    0 18px 42px rgba(0, 0, 0, 0.38),
    0 0 0 1px color-mix(in srgb, var(--tabs-border) 34%, transparent);
}

.level-help-item {
  display: grid;
  gap: 0.18rem;
  color: var(--text-secondary);
  font-size: 0.72rem;
  line-height: 1.35;
}

.level-help-item strong {
  color: var(--text-primary);
  font-size: 0.75rem;
  font-weight: 650;
}

.pill-sep {
  width: 1px;
  height: 16px;
  background: rgba(255, 255, 255, 0.1);
  margin: 0 2px;
  flex-shrink: 0;
}
</style>
