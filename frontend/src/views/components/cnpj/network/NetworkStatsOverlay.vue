<script setup>
import { computed } from "vue";

const props = defineProps({
  totalNodes: {
    type: Number,
    required: true,
  },
  totalEdges: {
    type: Number,
    required: true,
  },
  summary: {
    type: Object,
    default: null,
  },
});

const levelOrder = ["n1", "n2", "n3", "n4"];

const levelStats = computed(() =>
  levelOrder
    .map((key) => {
      const level = props.summary?.levels?.[key];
      if (!level) return null;

      return {
        key,
        shortLabel: key.toUpperCase(),
        label: level.label,
        entities: level.entities || 0,
        links: level.links || 0,
        tooltip: {
          value: `${level.label}: ${level.entities || 0} entidades, ${level.links || 0} vínculos`,
          showDelay: 120,
          hideDelay: 80,
        },
      };
    })
    .filter(Boolean),
);
</script>

<template>
  <div class="graph-stats-overlay" aria-label="Resumo da rede">
    <div class="stats-main">
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

    <div v-if="levelStats.length" class="level-stats" aria-label="Entidades por nível">
      <span
        v-for="level in levelStats"
        :key="level.key"
        class="level-chip"
        v-tooltip.top="level.tooltip"
      >
        <span class="level-chip-key">{{ level.shortLabel }}</span>
        <span class="level-chip-value">{{ level.entities }}</span>
      </span>
    </div>
  </div>
</template>

<style scoped>
.graph-stats-overlay {
  position: absolute;
  top: 1rem;
  right: 1rem;
  z-index: 10;
  width: auto;
  max-width: calc(100% - 2rem);
  display: flex;
  align-items: center;
  gap: 0.65rem;
  padding: 0.45rem 0.65rem;
  background: color-mix(in srgb, var(--card-bg) 88%, transparent);
  backdrop-filter: blur(12px);
  -webkit-backdrop-filter: blur(12px);
  border: 1px solid var(--tabs-border);
  border-radius: 12px;
  box-shadow: 0 8px 24px -4px rgba(0, 0, 0, 0.45);
}

.stats-main {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.9rem;
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

.level-stats {
  display: flex;
  align-items: center;
  gap: 0.35rem;
  padding-left: 0.65rem;
  border-left: 1px solid color-mix(in srgb, var(--tabs-border) 55%, transparent);
}

.level-chip {
  min-width: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 0.25rem;
  padding: 0.22rem 0.32rem;
  border: 1px solid color-mix(in srgb, var(--tabs-border) 82%, transparent);
  border-radius: 8px;
  background: color-mix(in srgb, var(--surface-ground) 54%, transparent);
  color: var(--text-color-85);
  cursor: help;
}

.level-chip-key {
  font-size: 0.56rem;
  font-weight: 700;
  color: var(--text-muted);
  line-height: 1;
}

.level-chip-value {
  min-width: 1.1rem;
  font-size: 0.72rem;
  font-weight: 700;
  color: var(--primary-color);
  line-height: 1;
  text-align: right;
}
</style>
