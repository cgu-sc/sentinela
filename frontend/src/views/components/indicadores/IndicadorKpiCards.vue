<script setup>
import { computed } from 'vue';
import { useFormatting } from '@/composables/useFormatting';

const props = defineProps({
  /** Objeto kpis retornado pelo endpoint (total_critico, total_atencao, etc.) */
  kpis: { type: Object, default: null },
  /** Formato de exibição do valor mediano ('pct' | 'val' | 'dec' | 'pct3') */
  formato: { type: String, default: 'dec' },
  isLoading: { type: Boolean, default: false },
});

const { formatCurrencyFull } = useFormatting();

function formatMediana(value) {
  if (value == null) return '—';
  const fmt = props.formato;
  if (fmt === 'pct')  return value.toFixed(2) + '%';
  if (fmt === 'pct3') return value.toFixed(3) + '%';
  if (fmt === 'val')  return formatCurrencyFull(value);
  return value.toFixed(2);
}

const cards = computed(() => {
  if (!props.kpis) return [];
  const k = props.kpis;
  const total = (k.total_critico ?? 0) + (k.total_atencao ?? 0) + (k.total_normal ?? 0) + (k.total_sem_dados ?? 0);

  return [
    {
      label: 'Crítico',
      value: k.total_critico ?? 0,
      sub: total > 0 ? ((k.total_critico / total) * 100).toFixed(1) + '%' : null,
      color: 'var(--risk-indicator-critical)',
      icon: 'pi pi-exclamation-circle',
    },
    {
      label: 'Atenção',
      value: k.total_atencao ?? 0,
      sub: total > 0 ? ((k.total_atencao / total) * 100).toFixed(1) + '%' : null,
      color: 'var(--risk-indicator-warning)',
      icon: 'pi pi-exclamation-triangle',
    },
    {
      label: 'Normal',
      value: k.total_normal ?? 0,
      sub: total > 0 ? ((k.total_normal / total) * 100).toFixed(1) + '%' : null,
      color: 'var(--risk-indicator-normal)',
      icon: 'pi pi-check-circle',
    },
    {
      label: 'Mediana Regional',
      value: formatMediana(k.mediana_reg),
      sub: null,
      color: 'var(--primary-color)',
      icon: 'pi pi-chart-bar',
    },
    {
      label: 'Acima do Limiar',
      value: k.pct_acima_limiar != null ? k.pct_acima_limiar.toFixed(1) + '%' : '—',
      sub: null,
      color: 'var(--risk-indicator-warning)',
      icon: 'pi pi-chart-pie',
    },
  ];
});
</script>

<template>
  <div class="ind-kpi-section" :class="{ 'is-refreshing': isLoading }">
    <div
      v-for="card in cards"
      :key="card.label"
      class="ind-kpi-card"
      :style="{
        borderBottom: `3px solid color-mix(in srgb, ${card.color} 50%, transparent)`,
        background: `linear-gradient(to top, color-mix(in srgb, ${card.color} 6%, var(--card-bg)) 0%, var(--card-bg) 60%)`
      }"
    >
      <div class="ind-kpi-body">
        <div class="ind-kpi-icon" :style="{ backgroundColor: `color-mix(in srgb, ${card.color} 20%, transparent)`, color: card.color }">
          <i :class="card.icon" />
        </div>
        <div class="ind-kpi-content">
          <span class="ind-kpi-label">{{ card.label }}</span>
          <div class="value-row">
            <span class="ind-kpi-value">{{ card.value }}</span>
            <span v-if="card.sub" class="ind-kpi-sub-inline">{{ card.sub }}</span>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.ind-kpi-section {
  display: grid;
  grid-template-columns: repeat(5, minmax(0, 1fr));
  gap: 1rem;
  width: 100%;
}

.ind-kpi-section.is-refreshing {
  opacity: 0.5;
  pointer-events: none;
}

.ind-kpi-card {
  background: var(--card-bg);
  border-radius: 12px;
  padding: 0.8rem 1rem;
  border: 1px solid color-mix(in srgb, var(--primary-color) 15%, var(--sidebar-border));
  min-height: 0;
  display: flex;
  align-items: center;
}

.ind-kpi-body {
  display: flex;
  justify-content: flex-start;
  align-items: center;
  gap: 0.9rem;
  width: 100%;
}

.ind-kpi-icon {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 2.75rem;
  height: 2.75rem;
  border-radius: 0.75rem;
  flex-shrink: 0;
  font-size: 1.25rem;
}

.ind-kpi-content {
  display: flex;
  flex-direction: column;
  gap: 0.15rem;
  min-width: 0;
}

.ind-kpi-label {
  font-size: 0.70rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: var(--text-color);
  opacity: 0.7; /* Hierarquia via transparência */
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  line-height: 1;
}

.value-row {
  display: flex;
  align-items: baseline;
  gap: 0.4rem;
}

.ind-kpi-value {
  font-size: 1.35rem;
  font-weight: 700;
  color: var(--text-color);
  opacity: 0.9; /* Suavização unificada */
  line-height: 1.1;
  letter-spacing: -0.02em;
}

.ind-kpi-sub-inline {
  font-size: 0.75rem;
  font-weight: 600;
  color: var(--text-muted);
  opacity: 0.7;
}
</style>
