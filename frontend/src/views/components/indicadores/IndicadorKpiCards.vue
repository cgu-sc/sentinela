<script setup>
import { computed } from 'vue';
import { useFormatting } from '@/composables/useFormatting';
import { INDICATOR_GROUPS } from '@/config/riskConfig';

const props = defineProps({
  /** Objeto kpis retornado pelo endpoint (total_critico, total_atencao, etc.) */
  kpis: { type: Object, default: null },
  /** Chave do indicador selecionado (para mostrar o nome) */
  indicadorKey: { type: String, default: null },
  /** Formato de exibição do valor mediano ('pct' | 'val' | 'dec' | 'pct3') */
  formato: { type: String, default: 'dec' },
  isLoading: { type: Boolean, default: false },
});

const { formatCurrencyFull, formatPercent } = useFormatting();

// Encontra o label do indicador a partir da chave
const indicadorLabel = computed(() => {
  if (!props.indicadorKey) return null;
  for (const grupo of INDICATOR_GROUPS) {
    const ind = grupo.indicators.find(i => i.key === props.indicadorKey);
    if (ind) return ind.label;
  }
  return props.indicadorKey;
});

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
      sub: total > 0 ? ((k.total_critico / total) * 100).toFixed(1) + '% do total' : null,
      color: 'var(--risk-indicator-critical)',
      icon: 'pi pi-exclamation-circle',
    },
    {
      label: 'Atenção',
      value: k.total_atencao ?? 0,
      sub: total > 0 ? ((k.total_atencao / total) * 100).toFixed(1) + '% do total' : null,
      color: 'var(--risk-indicator-warning)',
      icon: 'pi pi-exclamation-triangle',
    },
    {
      label: 'Normal',
      value: k.total_normal ?? 0,
      sub: total > 0 ? ((k.total_normal / total) * 100).toFixed(1) + '% do total' : null,
      color: 'var(--risk-indicator-normal)',
      icon: 'pi pi-check-circle',
    },
    {
      label: 'Sem Dados',
      value: k.total_sem_dados ?? 0,
      sub: null,
      color: 'var(--text-muted)',
      icon: 'pi pi-minus-circle',
    },
    {
      label: 'Mediana Regional',
      value: formatMediana(k.mediana_reg),
      sub: 'benchmark do escopo',
      color: 'var(--primary-color)',
      icon: 'pi pi-chart-bar',
    },
    {
      label: 'Acima do Limiar',
      value: k.pct_acima_limiar != null ? k.pct_acima_limiar.toFixed(1) + '%' : '—',
      sub: 'CRÍTICO + ATENÇÃO',
      color: 'var(--risk-indicator-warning)',
      icon: 'pi pi-percentage',
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
        <div class="ind-kpi-icon" :style="{ backgroundColor: card.color + '20', color: card.color }">
          <i :class="card.icon" />
        </div>
        <div class="ind-kpi-content">
          <span class="ind-kpi-label">{{ card.label }}</span>
          <span class="ind-kpi-value">{{ card.value }}</span>
          <span v-if="card.sub" class="ind-kpi-sub">{{ card.sub }}</span>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.ind-kpi-section {
  display: grid;
  grid-template-columns: repeat(6, minmax(0, 1fr));
  gap: 1rem;
  width: 100%;
  transition: opacity 0.3s ease;
}

.ind-kpi-section.is-refreshing {
  opacity: 0.55;
  pointer-events: none;
}

.ind-kpi-card {
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  border-radius: 10px;
  padding: 0.85rem 1rem;
  box-shadow: 0 1px 4px rgba(0, 0, 0, 0.05);
  transition: transform 0.2s ease, box-shadow 0.2s ease;
}

.ind-kpi-card:hover {
  transform: translateY(-2px);
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
}

.ind-kpi-body {
  display: flex;
  align-items: center;
  gap: 0.75rem;
}

.ind-kpi-icon {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 2.25rem;
  height: 2.25rem;
  border-radius: 8px;
  flex-shrink: 0;
  font-size: 0.95rem;
}

.ind-kpi-content {
  display: flex;
  flex-direction: column;
  gap: 0.1rem;
  min-width: 0;
}

.ind-kpi-label {
  font-size: 0.68rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: var(--text-color);
  opacity: 0.65;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.ind-kpi-value {
  font-size: 1.15rem;
  font-weight: 600;
  color: var(--text-color);
  line-height: 1.2;
}

.ind-kpi-sub {
  font-size: 0.65rem;
  color: var(--text-muted);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
</style>
