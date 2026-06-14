<script setup>
defineProps({
  groups: {
    type: Array,
    default: () => [],
  },
  selectedNodeId: {
    type: [String, Number, null],
    default: null,
  },
  previewedNodeId: {
    type: [String, Number, null],
    default: null,
  },
});

const emit = defineEmits(["preview", "clear-preview", "select"]);
</script>

<template>
  <div class="graph-alerts-overlay" aria-label="Alertas da teia">
    <div class="alerts-title">Alertas</div>
    <div v-for="group in groups" :key="group.key" class="alert-group">
      <div class="alert-group-header">
        <span :class="group.icon"></span>
        <span>{{ group.label }}</span>
        <span class="alert-count">{{ group.items.length }}</span>
      </div>
      <button
        v-for="item in group.items"
        :key="`${group.key}-${item.id}`"
        type="button"
        class="alert-person"
        :class="{
          active: selectedNodeId === item.id,
          preview: previewedNodeId === item.id,
        }"
        @mouseenter="emit('preview', item.id)"
        @mouseleave="emit('clear-preview', item.id)"
        @focus="emit('preview', item.id)"
        @blur="emit('clear-preview', item.id)"
        @click="emit('select', item.id)"
      >
        <span class="alert-person-name">{{ item.name }}</span>
      </button>
    </div>
  </div>
</template>

<style scoped>
.graph-alerts-overlay {
  position: absolute;
  top: 4.35rem;
  right: 1rem;
  z-index: 10;
  width: var(--graph-side-panel-width, 176px);
  max-width: calc(100% - 2rem);
  max-height: 38vh;
  overflow: auto;
  padding: 0.55rem;
  background: color-mix(in srgb, var(--card-bg) 86%, transparent);
  backdrop-filter: blur(12px);
  -webkit-backdrop-filter: blur(12px);
  border: 1px solid color-mix(in srgb, var(--tabs-border) 82%, transparent);
  border-radius: 10px;
  box-shadow: 0 10px 24px -12px rgba(0, 0, 0, 0.55);
}

.alerts-title {
  font-size: 0.62rem;
  font-weight: 800;
  color: var(--text-muted);
  text-transform: uppercase;
  letter-spacing: 0.08em;
  margin: 0 0.1rem 0.42rem;
}

.alert-group + .alert-group {
  margin-top: 0.42rem;
  padding-top: 0.42rem;
  border-top: 1px solid color-mix(in srgb, var(--tabs-border) 58%, transparent);
}

.alert-group-header {
  display: flex;
  align-items: center;
  gap: 0.45rem;
  color: var(--text-secondary);
  font-size: 0.68rem;
  font-weight: 800;
  margin: 0 0.1rem 0.26rem;
}

.legend-cadunico-ring {
  width: 13px;
  height: 13px;
  border-radius: 50%;
  border: 4px double #f59e0b;
  background: #0ea5e9;
  flex-shrink: 0;
}

.legend-esocial-ring {
  width: 13px;
  height: 13px;
  border-radius: 50%;
  border: 3px solid var(--status-success);
  box-shadow: 0 0 0 2px color-mix(in srgb, var(--status-success) 18%, transparent);
  background: color-mix(in srgb, var(--status-success) 20%, transparent);
  flex-shrink: 0;
}

.legend-cnae-alert {
  width: 14px;
  height: 14px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border-radius: 50%;
  background: color-mix(in srgb, #ef4444 18%, transparent);
  border: 1px solid color-mix(in srgb, #ef4444 72%, transparent);
  flex-shrink: 0;
}

.legend-cnae-alert::before {
  content: "!";
  color: #ef4444;
  font-size: 0.62rem;
  font-weight: 900;
  line-height: 1;
}

.legend-par-alert {
  width: 14px;
  height: 14px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border-radius: 4px;
  background: color-mix(in srgb, #dc2626 18%, transparent);
  border: 2px double color-mix(in srgb, #dc2626 82%, transparent);
  flex-shrink: 0;
}

.legend-par-alert::before {
  content: "P";
  color: #dc2626;
  font-size: 0.56rem;
  font-weight: 900;
  line-height: 1;
}

.legend-deceased-cross {
  width: 15px;
  height: 15px;
  position: relative;
  display: inline-block;
  flex-shrink: 0;
}

.legend-deceased-cross::before,
.legend-deceased-cross::after {
  content: "";
  position: absolute;
  left: 50%;
  top: 50%;
  width: 3px;
  border-radius: 999px;
  background: #64748b;
  transform: translate(-50%, -50%);
}

.legend-deceased-cross::before {
  height: 15px;
}

.legend-deceased-cross::after {
  width: 11px;
  height: 3px;
  top: 38%;
}

.alert-count {
  margin-left: auto;
  min-width: 1.1rem;
  height: 1.1rem;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border-radius: 999px;
  background: color-mix(in srgb, var(--text-muted) 14%, transparent);
  color: var(--text-secondary);
  font-size: 0.58rem;
  font-weight: 800;
}

.alert-person {
  width: 100%;
  display: flex;
  align-items: center;
  padding: 0.32rem 0.4rem;
  border: 1px solid transparent;
  border-radius: 6px;
  background: transparent;
  color: var(--text-secondary);
  text-align: left;
  cursor: pointer;
}

.alert-person:hover,
.alert-person.preview,
.alert-person.active {
  background: color-mix(in srgb, var(--primary-color) 10%, transparent);
  border-color: color-mix(in srgb, var(--primary-color) 26%, transparent);
}

.alert-person-name {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 0.72rem;
  font-weight: 700;
  color: var(--text-color);
}
</style>
