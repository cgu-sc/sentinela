<script setup>
import { NETWORK_RISK_BORDER_COLORS } from "@/utils/network/networkConstants";

defineProps({
  typeLabels: {
    type: Object,
    required: true,
  },
});
</script>

<template>
  <div v-for="(typeInfo, key) in typeLabels" :key="key" class="legend-item">
    <span class="legend-dot" :style="{ background: typeInfo.color }"></span>
    <span class="legend-label">{{ typeInfo.label }}</span>
  </div>
  <div class="legend-item">
    <span class="legend-line representative"></span>
    <span class="legend-label">Representante</span>
  </div>
  <div class="legend-item">
    <span class="legend-cadunico-ring"></span>
    <span class="legend-label">CadÚnico</span>
  </div>
  <div class="legend-item">
    <span class="legend-par-alert"></span>
    <span class="legend-label">PAR</span>
  </div>
  <div class="legend-item">
    <span class="legend-deceased-cross"></span>
    <span class="legend-label">Falecido</span>
  </div>
  <div class="legend-item risk-legend">
    <span
      class="legend-risk-box"
      :style="{ borderColor: NETWORK_RISK_BORDER_COLORS.NORMAL }"
    ></span>
    <span class="legend-label">Normal</span>
    <span
      class="legend-risk-box"
      :style="{ borderColor: NETWORK_RISK_BORDER_COLORS.ATTENTION }"
    ></span>
    <span class="legend-label">Atenção</span>
    <span
      class="legend-risk-box"
      :style="{ borderColor: NETWORK_RISK_BORDER_COLORS.CRITICAL }"
    ></span>
    <span class="legend-label">Crítico</span>
  </div>
</template>

<style scoped>
.legend-item {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.legend-dot {
  width: 10px;
  height: 10px;
  border-radius: 50%;
  flex-shrink: 0;
}

.legend-cadunico-ring {
  width: 13px;
  height: 13px;
  border-radius: 50%;
  border: 4px double #f59e0b;
  background: #0ea5e9;
  flex-shrink: 0;
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

.legend-line {
  width: 14px;
  height: 0;
  margin-right: 6px;
  background: transparent;
  flex-shrink: 0;
}

.legend-line.representative {
  border-top: 2px dotted #f59e0b;
}

.legend-label {
  font-size: 0.68rem;
  color: var(--text-secondary);
  font-weight: 600;
}
.risk-legend {
  gap: 0.25rem;
}

.legend-risk-box {
  width: 10px;
  height: 10px;
  border: 2px solid;
  border-radius: 3px;
  background: var(--card-bg);
  flex-shrink: 0;
}

.risk-legend .legend-label {
  margin-right: 0.25rem;
}

</style>
