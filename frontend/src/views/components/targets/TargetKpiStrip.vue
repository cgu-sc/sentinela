<script setup>
import { computed } from 'vue';
import { useFormatting } from '@/composables/useFormatting';

const props = defineProps({
  title: { type: String, required: true },
  description: { type: String, required: true },
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
  props.kpis.map(kpi => ({ ...kpi, displayValue: formatKpiValue(kpi) }))
);
</script>

<template>
  <section class="target-kpi-card">
    <div class="target-kpi-header">
      <div class="target-title-block">
        <span class="target-eyebrow">Alvo investigativo</span>
        <h1>{{ title }}</h1>
        <p>{{ description }}</p>
      </div>

      <div v-if="sourceNotice" class="target-contract-note">
        <i class="pi pi-database" />
        <span>{{ sourceNotice }}</span>
      </div>
    </div>

    <div class="target-kpi-grid">
      <article
        v-for="kpi in displayKpis"
        :key="kpi.label"
        class="target-kpi"
      >
        <span>{{ kpi.label }}</span>
        <strong>{{ kpi.displayValue }}</strong>
      </article>
    </div>
  </section>
</template>

<style scoped>
.target-kpi-card {
  padding: 1rem;
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  border-radius: 8px;
  box-shadow: var(--shadow-sm);
}

.target-kpi-header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 1rem;
  margin-bottom: 1rem;
}

.target-title-block {
  min-width: 0;
}

.target-eyebrow {
  display: block;
  margin-bottom: 0.25rem;
  color: var(--primary-color);
  font-size: 0.66rem;
  font-weight: 600;
  letter-spacing: 0.07em;
  text-transform: uppercase;
}

.target-title-block h1 {
  margin: 0;
  color: var(--text-color-85);
  font-size: 1.08rem;
  font-weight: 600;
  letter-spacing: 0;
}

.target-title-block p {
  margin: 0.35rem 0 0;
  color: var(--text-muted);
  font-size: 0.78rem;
  line-height: 1.45;
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
}

.target-kpi-grid {
  display: grid;
  grid-template-columns: repeat(5, minmax(0, 1fr));
  gap: 0.8rem;
}

.target-kpi {
  min-height: 4.2rem;
  padding: 0.75rem;
  border: 1px solid var(--card-border);
  border-radius: 8px;
  background: color-mix(in srgb, var(--primary-color) 4%, var(--card-bg));
  display: flex;
  flex-direction: column;
  justify-content: center;
  gap: 0.25rem;
}

.target-kpi span {
  color: var(--text-muted);
  font-size: 0.66rem;
  font-weight: 600;
  letter-spacing: 0.05em;
  text-transform: uppercase;
}

.target-kpi strong {
  color: var(--text-color-85);
  font-size: 1rem;
  font-weight: 600;
}
</style>
