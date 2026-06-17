<script setup>
/**
 * TabPlaceholder — Estado vazio/erro/loading padronizado para as abas do CnpjDetailView.
 *
 * Props:
 *  icon        (String)  — Classe do ícone PrimeIcons. Ex: 'pi-database'.
 *                          Para 'loading', pode omitir (usa spinner automaticamente).
 *  title       (String)  — Título principal (obrigatório).
 *  description (String)  — Subtítulo explicativo (opcional).
 *  variant     (String)  — 'default' | 'info' | 'error' | 'success' | 'loading'
 */
const props = defineProps({
  icon:        { type: String,  default: 'pi-inbox' },
  title:       { type: String,  required: true },
  description: { type: String,  default: '' },
  variant:     { type: String,  default: 'default',
                 validator: (v) => ['default', 'info', 'error', 'success', 'loading'].includes(v) },
});
</script>

<template>
  <div class="tab-ph" :class="`tab-ph--${variant}`">
    <!-- Ícone ou Spinner -->
    <div class="tab-ph__icon-wrap">
      <i v-if="variant === 'loading'" class="pi pi-spin pi-spinner tab-ph__spinner" />
      <i v-else :class="['pi', icon, 'tab-ph__icon']" />
    </div>

    <!-- Textos -->
    <div class="tab-ph__body">
      <p class="tab-ph__title">{{ title }}</p>
      <div v-if="description || $slots.description" class="tab-ph__desc">
        <slot name="description">{{ description }}</slot>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* ── Container ─────────────────────────────────────────────── */
.tab-ph {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: flex-start; /* Subiu de center para flex-start */
  gap: 1.25rem;
  width: 100%;
  min-height: calc(100vh - 520px);
  padding: 6rem 2rem; /* Aumentei o padding superior para não colar no topo */
  text-align: center;
}

/* ── Badge do ícone ─────────────────────────────────────────── */
.tab-ph__icon-wrap {
  width: 80px;
  height: 80px;
  border-radius: 22px;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;

  /* Default: azul primário */
  background: color-mix(in srgb, var(--primary-color) 10%, transparent);
  border: 1px solid color-mix(in srgb, var(--primary-color) 18%, transparent);
  box-shadow:
    0 8px 20px -4px color-mix(in srgb, var(--primary-color) 12%, transparent),
    inset 0 1px 0 color-mix(in srgb, white 8%, transparent);
}

.tab-ph__icon {
  font-size: 2.2rem;
  color: var(--primary-color);
  opacity: 0.75;
}

.tab-ph__spinner {
  font-size: 2rem;
  color: var(--primary-color);
  opacity: 0.6;
}

/* ── Variantes ──────────────────────────────────────────────── */
.tab-ph--error .tab-ph__icon-wrap {
  background: color-mix(in srgb, var(--risk-high, #ef4444) 10%, transparent);
  border-color: color-mix(in srgb, var(--risk-high, #ef4444) 18%, transparent);
  box-shadow: 0 8px 20px -4px color-mix(in srgb, var(--risk-high, #ef4444) 12%, transparent),
              inset 0 1px 0 color-mix(in srgb, white 8%, transparent);
}
.tab-ph--error .tab-ph__icon {
  color: var(--risk-high, #ef4444);
}

.tab-ph--success .tab-ph__icon-wrap {
  background: color-mix(in srgb, var(--green-500, #22c55e) 10%, transparent);
  border-color: color-mix(in srgb, var(--green-500, #22c55e) 18%, transparent);
  box-shadow: 0 8px 20px -4px color-mix(in srgb, var(--green-500, #22c55e) 12%, transparent),
              inset 0 1px 0 color-mix(in srgb, white 8%, transparent);
}
.tab-ph--success .tab-ph__icon {
  color: var(--green-500, #22c55e);
  opacity: 0.8;
}

.tab-ph--info .tab-ph__icon-wrap {
  background: color-mix(in srgb, var(--info-color, var(--primary-color)) 10%, transparent);
  border-color: color-mix(in srgb, var(--info-color, var(--primary-color)) 18%, transparent);
  box-shadow: 0 8px 20px -4px color-mix(in srgb, var(--info-color, var(--primary-color)) 12%, transparent),
              inset 0 1px 0 color-mix(in srgb, white 8%, transparent);
}
.tab-ph--info .tab-ph__icon {
  color: var(--info-color, var(--primary-color));
  opacity: 0.8;
}

.tab-ph--loading .tab-ph__icon-wrap {
  border-style: dashed;
}

/* ── Textos ─────────────────────────────────────────────────── */
.tab-ph__body {
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
  max-width: 400px;
}

.tab-ph__title {
  margin: 0;
  font-size: 1rem;
  font-weight: 600;
  color: var(--text-color-85);
  letter-spacing: -0.01em;
  opacity: 0.7;
}

.tab-ph__desc {
  margin: 0;
  font-size: 0.85rem;
  line-height: 1.6;
  color: var(--text-muted);
  opacity: 0.7;
}
</style>
