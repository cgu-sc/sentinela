<script setup>
const props = defineProps({
  visible: { type: Boolean, default: false },
  title: { type: String, default: "Visualizacao do documento" },
  fileUrl: { type: String, default: "" },
  filePath: { type: String, default: "" },
});

const emit = defineEmits(["close", "open-file"]);
</script>

<template>
  <div v-if="visible" class="document-preview" role="dialog" aria-modal="true">
    <div class="document-preview__panel">
      <header class="document-preview__header">
        <div class="document-preview__title-group">
          <span class="document-preview__eyebrow">Pre-visualizacao</span>
          <h2 class="document-preview__title">{{ title }}</h2>
        </div>
        <div class="document-preview__actions">
          <button
            v-if="filePath"
            type="button"
            class="document-preview__button"
            @click="emit('open-file')"
          >
            <i class="pi pi-external-link" />
            Abrir arquivo
          </button>
          <button
            type="button"
            class="document-preview__close"
            aria-label="Fechar visualizacao"
            @click="emit('close')"
          >
            <i class="pi pi-times" />
          </button>
        </div>
      </header>

      <div class="document-preview__body">
        <iframe
          v-if="fileUrl"
          class="document-preview__frame"
          :src="fileUrl"
          title="Pre-visualizacao do documento PDF"
        />
        <div v-else class="document-preview__empty">
          <i class="pi pi-file-pdf" />
          <span>PDF indisponivel para visualizacao.</span>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.document-preview {
  position: fixed;
  inset: 0;
  z-index: 100000;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 12px;
  background: color-mix(in srgb, var(--bg-color) 72%, black 28%);
  backdrop-filter: blur(8px);
}

.document-preview__panel {
  width: calc(100vw - 24px);
  height: calc(100vh - 24px);
  display: flex;
  flex-direction: column;
  overflow: hidden;
  border-radius: 10px;
  border: 1px solid var(--card-border);
  background: var(--card-bg);
  box-shadow: 0 28px 90px rgba(0, 0, 0, 0.45);
}

.document-preview__header {
  min-height: 64px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 1rem;
  padding: 0.85rem 1rem;
  border-bottom: 1px solid var(--card-border);
  background: var(--tabs-bg);
}

.document-preview__title-group {
  min-width: 0;
}

.document-preview__eyebrow {
  display: block;
  color: var(--text-muted);
  font-size: 0.7rem;
  font-weight: 600;
  letter-spacing: 0.08em;
  text-transform: uppercase;
}

.document-preview__title {
  margin: 0.12rem 0 0;
  color: var(--text-color-85);
  font-size: 1rem;
  font-weight: 600;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.document-preview__actions {
  display: flex;
  align-items: center;
  gap: 0.55rem;
}

.document-preview__button,
.document-preview__close {
  min-height: 2.15rem;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 0.4rem;
  border-radius: 7px;
  border: 1px solid var(--card-border);
  background: var(--bg-color);
  color: var(--text-color-85);
  cursor: pointer;
}

.document-preview__button {
  padding: 0 0.75rem;
  font-size: 0.82rem;
  font-weight: 600;
}

.document-preview__close {
  width: 2.15rem;
  padding: 0;
}

.document-preview__button:hover,
.document-preview__close:hover {
  border-color: color-mix(in srgb, var(--primary-color) 42%, var(--card-border));
  color: var(--primary-color);
}

.document-preview__body {
  flex: 1;
  min-height: 0;
  background: var(--bg-color);
}

.document-preview__frame {
  width: 100%;
  height: 100%;
  display: block;
  border: 0;
  background: white;
}

.document-preview__empty {
  height: 100%;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 0.65rem;
  color: var(--text-muted);
  font-size: 0.95rem;
}
</style>
