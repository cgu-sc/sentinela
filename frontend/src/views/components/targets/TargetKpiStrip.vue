<script setup>
import { computed } from 'vue';
import { useFormatting } from '@/composables/useFormatting';
import { DEFAULT_KPI_STYLE } from '@/config/uiConfig';
import { TARGET_KPI_CONFIGS } from '@/config/targetConfig';

const props = defineProps({
  kpis: { type: Array, default: () => [] },
  sourceNotice: { type: String, default: null },
});

const { formatCurrencyFull } = useFormatting();

function formatKpiValue(kpi) {
  if (kpi?.value == null) return '—';
  if (kpi.key === 'valor_incompativel') return formatCurrencyFull(kpi.value);
  if (typeof kpi.value === 'number') {
    return kpi.value.toLocaleString('pt-BR', { maximumFractionDigits: 0 });
  }
  return String(kpi.value);
}

const displayKpis = computed(() =>
  props.kpis.map(kpi => ({
    ...kpi,
    ...DEFAULT_KPI_STYLE,
    ...TARGET_KPI_CONFIGS[kpi.key],
    displayValue: formatKpiValue(kpi),
  }))
);
</script>

<template>
  <section class="target-kpi-section">
    <div v-if="sourceNotice" class="target-contract-note">
      <i class="pi pi-database" />
      <span>{{ sourceNotice }}</span>
    </div>

    <div class="target-kpi-grid">
      <article
        v-for="kpi in displayKpis"
        :key="kpi.label"
        class="target-kpi"
        :style="{
          borderBottom: `3px solid color-mix(in srgb, ${kpi.color} 50%, transparent)`,
          background: `linear-gradient(to top, color-mix(in srgb, ${kpi.color} 6%, var(--card-bg)) 0%, var(--card-bg) 60%)`,
        }"
      >
        <div
          class="target-kpi-icon"
          :style="{ backgroundColor: `${kpi.color}20`, color: kpi.color }"
        >
          <i :class="kpi.icon" />
        </div>
        <div class="target-kpi-content">
          <span>{{ kpi.label }}</span>
          <strong>{{ kpi.displayValue }}</strong>
        </div>
      </article>
    </div>
  </section>
</template>

<style scoped>
.target-kpi-section {
  width: 100%;
}

.target-contract-note {
  display: inline-flex;
  align-items: center;
  gap: 0.45rem;
  flex-shrink: 0;
  padding: 0.55rem 0.7rem;
  border: 1px solid color-mix(in srgb, var(--risk-indicator-warning) 38%, var(--card-border));
  border-radius: 8px;
  background: color-mix(in srgb, var(--risk-indicator-warning) 10%, var(--card-bg));
  color: var(--risk-indicator-warning);
  font-size: 0.72rem;
  font-weight: 500;
  margin-bottom: 1rem;
}

.target-kpi-grid {
  display: grid;
  grid-template-columns: repeat(5, minmax(0, 1fr));
  gap: 1.15rem;
  width: 100%;
}

.target-kpi {
  min-height: 0;
  padding: 0.8rem 1rem;
  display: flex;
  align-items: center;
  gap: 0.9rem;
  border: 1px solid color-mix(in srgb, var(--primary-color) 15%, var(--sidebar-border));
  border-radius: 12px;
}

.target-kpi-icon {
  width: 2.75rem;
  height: 2.75rem;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  border-radius: 0.75rem;
  font-size: 1.25rem;
}

.target-kpi-content {
  min-width: 0;
  display: flex;
  flex-direction: column;
}

.target-kpi-content span {
  margin-bottom: 0.3rem;
  color: var(--text-color);
  opacity: 0.7;
  font-size: 0.7rem;
  font-weight: 600;
  line-height: 1;
  white-space: nowrap;
  text-transform: uppercase;
}

.target-kpi-content strong {
  color: var(--text-color);
  opacity: 0.9;
  font-size: 1.3rem;
  font-weight: 600;
  line-height: 1;
  white-space: nowrap;
}
</style>
