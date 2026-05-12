<script setup>
defineProps({
  zoom: {
    type: Number,
    required: true,
  },
  reorganizeTooltip: {
    type: String,
    required: true,
  },
  variant: {
    type: String,
    default: "floating",
    validator: (value) => ["floating", "pill"].includes(value),
  },
});

const emit = defineEmits(["zoom-in", "zoom-out", "fit", "reset-layout"]);

</script>

<template>
  <div v-if="variant === 'pill'" class="toolbar-pill zoom-pill">
    <button
      class="ctrl-btn"
      @click="emit('zoom-in')"
      v-tooltip.bottom="'Ampliar'"
    >
      <i class="pi pi-plus" />
    </button>
    <span class="zoom-level">{{ zoom }}%</span>
    <button
      class="ctrl-btn"
      @click="emit('zoom-out')"
      v-tooltip.bottom="'Reduzir'"
    >
      <i class="pi pi-minus" />
    </button>
    <div class="pill-sep"></div>
    <button
      class="ctrl-btn"
      @click="emit('fit')"
      v-tooltip.bottom="'Ajustar à tela'"
    >
      <i class="pi pi-arrows-alt" />
    </button>
    <button
      class="ctrl-btn"
      :title="reorganizeTooltip"
      :aria-label="reorganizeTooltip"
      @click="emit('reset-layout')"
      v-tooltip.bottom="reorganizeTooltip"
    >
      <i class="pi pi-sync" />
    </button>
  </div>

  <div v-else class="graph-controls">
    <button class="ctrl-btn" @click="emit('zoom-in')" v-tooltip.left="'Ampliar'">
      <i class="pi pi-plus" />
    </button>
    <span class="zoom-level">{{ zoom }}%</span>
    <button class="ctrl-btn" @click="emit('zoom-out')" v-tooltip.left="'Reduzir'">
      <i class="pi pi-minus" />
    </button>
    <div class="ctrl-sep"></div>
    <button class="ctrl-btn" @click="emit('fit')" v-tooltip.left="'Ajustar à tela'">
      <i class="pi pi-arrows-alt" />
    </button>
    <button
      class="ctrl-btn"
      :title="reorganizeTooltip"
      :aria-label="reorganizeTooltip"
      @click="emit('reset-layout')"
      v-tooltip.left="reorganizeTooltip"
    >
      <i class="pi pi-sync" />
    </button>
  </div>
</template>

<style scoped>
.zoom-pill {
  gap: 3px;
}

.zoom-pill .ctrl-btn {
  width: 1.65rem;
  height: 1.65rem;
}

.zoom-pill .zoom-level {
  width: 2.15rem;
}

.graph-controls {
  position: absolute;
  bottom: 1.5rem;
  right: 1.5rem;
  z-index: 10;
  display: flex;
  flex-direction: column;
  align-items: center;
  background: color-mix(in srgb, var(--card-bg) 85%, transparent);
  backdrop-filter: blur(10px);
  border: 1px solid var(--tabs-border);
  border-radius: 12px;
  padding: 0.5rem;
  gap: 0.4rem;
  box-shadow: 0 8px 24px -4px rgba(0, 0, 0, 0.35);
}

.graph-controls {
  display: none;
}

.ctrl-btn {
  width: 2rem;
  height: 2rem;
  display: flex;
  align-items: center;
  justify-content: center;
  background: transparent;
  border: none;
  border-radius: 6px;
  color: var(--text-secondary);
  cursor: pointer;
  font-size: 0.75rem;
  transition:
    background 0.2s,
    color 0.2s;
}

.ctrl-btn:hover {
  background: color-mix(in srgb, var(--primary-color) 15%, transparent);
  color: var(--primary-color);
}

.zoom-level {
  font-size: 0.65rem;
  font-weight: 500;
  color: var(--text-muted);
  width: 2rem;
  text-align: center;
}

.pill-sep {
  width: 1px;
  height: 16px;
  background: rgba(255, 255, 255, 0.1);
  margin: 0 2px;
  flex-shrink: 0;
}

.ctrl-sep {
  width: 1.5rem;
  height: 1px;
  background: var(--tabs-border);
  opacity: 0.5;
  margin: 0.1rem 0;
}
</style>
