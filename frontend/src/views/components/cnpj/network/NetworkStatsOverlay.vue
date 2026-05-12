<script setup>
defineProps({
  totalNodes: {
    type: Number,
    required: true,
  },
  totalEdges: {
    type: Number,
    required: true,
  },
});
</script>

<template>
  <div class="graph-stats-overlay" aria-label="Resumo da rede">
    <div class="stat-item">
      <span class="stat-value">{{ totalNodes }}</span>
      <span class="stat-label">Entidades</span>
    </div>
    <div class="stat-divider"></div>
    <div class="stat-item">
      <span class="stat-value">{{ totalEdges }}</span>
      <span class="stat-label">Vínculos</span>
    </div>
  </div>
</template>

<style scoped>
.graph-stats-overlay {
  position: absolute;
  top: 1rem;
  right: 1rem;
  z-index: 10;
  width: var(--graph-side-panel-width);
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.9rem;
  padding: 0.45rem 0.65rem;
  background: color-mix(in srgb, var(--card-bg) 88%, transparent);
  backdrop-filter: blur(12px);
  -webkit-backdrop-filter: blur(12px);
  border: 1px solid var(--tabs-border);
  border-radius: 12px;
  box-shadow: 0 8px 24px -4px rgba(0, 0, 0, 0.45);
  pointer-events: none;
}

.stat-item {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
}

.stat-value {
  font-size: 1rem;
  font-weight: 600;
  color: var(--primary-color);
  line-height: 1;
}

.stat-label {
  font-size: 0.56rem;
  text-transform: uppercase;
  font-weight: 500;
  color: var(--text-muted);
  letter-spacing: 0.04em;
}

.stat-divider {
  width: 1px;
  height: 1.65rem;
  background: var(--tabs-border);
  opacity: 0.5;
}
</style>
