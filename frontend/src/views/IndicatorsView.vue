<script setup>
import { computed, onMounted } from 'vue';
import { storeToRefs } from 'pinia';
import { useFilterStore } from '@/stores/filters';
import { useIndicadoresStore } from '@/stores/indicadores';
import { useFetchIndicadores } from '@/composables/useFetchIndicadores';
import { INDICATOR_GROUPS } from '@/config/riskConfig';

import IndicatorSelector from './components/indicadores/IndicatorSelector.vue';
import IndicadorKpiCards from './components/indicadores/IndicadorKpiCards.vue';
import IndicadorMap from './components/indicadores/IndicadorMap.vue';
import IndicadorCnpjTable from './components/indicadores/IndicadorCnpjTable.vue';

const filterStore = useFilterStore();
const indicadoresStore = useIndicadoresStore();
const { selectedIndicador, kpis, municipios, cnpjs, isLoading, error } = storeToRefs(indicadoresStore);
const { fetchForIndicador } = useFetchIndicadores();

// Metadados do indicador ativo (label, formato, metodologia)
const activeIndicadorMeta = computed(() => {
  if (!selectedIndicador.value) return null;
  for (const grupo of INDICATOR_GROUPS) {
    const ind = grupo.indicators.find(i => i.key === selectedIndicador.value);
    if (ind) return ind;
  }
  return null;
});

const activeUf = computed(() => filterStore.selectedUF);

function onIndicadorSelect(key) {
  localStorage.setItem('sentinela_indicadores_selected', key);
  fetchForIndicador(key);
}

// Restaura o último indicador selecionado ao montar a view
onMounted(() => {
  const saved = localStorage.getItem('sentinela_indicadores_selected');
  if (saved && !selectedIndicador.value) {
    fetchForIndicador(saved);
  }
});
</script>

<template>
  <div class="indicadores-layout">

    <!-- Painel lateral de seleção de indicadores -->
    <IndicatorSelector @select="onIndicadorSelect" />

    <!-- Painel principal de análise -->
    <div class="analysis-panel">

      <!-- Estado vazio: nenhum indicador selecionado -->
      <div v-if="!selectedIndicador && !isLoading" class="empty-state">
        <div class="empty-icon-wrap">
          <i class="pi pi-shield empty-icon" />
        </div>
        <h2 class="empty-title">Selecione um Indicador</h2>
        <p class="empty-desc">
          Escolha um dos 18 indicadores de risco no painel à esquerda para visualizar
          o desempenho das farmácias no escopo atual dos filtros.
        </p>
        <div class="empty-groups">
          <span v-for="grupo in INDICATOR_GROUPS" :key="grupo.id" class="empty-group-chip">
            {{ grupo.label }}
          </span>
        </div>
      </div>

      <!-- Estado de erro -->
      <div v-else-if="error && !isLoading" class="error-state">
        <i class="pi pi-exclamation-circle error-icon" />
        <p>{{ error }}</p>
      </div>

      <!-- Conteúdo (carregado ou carregando) -->
      <template v-else>

        <!-- Cabeçalho do indicador ativo -->
        <div v-if="activeIndicadorMeta || isLoading" class="analysis-header">
          <i class="pi pi-chart-scatter analysis-icon" />
          <div class="analysis-title-block">
            <h2 class="analysis-title">{{ activeIndicadorMeta?.label ?? '...' }}</h2>
            <p class="analysis-metodologia">{{ activeIndicadorMeta?.metodologia }}</p>
          </div>
        </div>

        <!-- KPI Cards -->
        <IndicadorKpiCards
          :kpis="kpis"
          :indicador-key="selectedIndicador"
          :formato="activeIndicadorMeta?.formato ?? 'dec'"
          :is-loading="isLoading"
        />

        <!-- Mapa -->
        <IndicadorMap
          :map-data="municipios"
          :active-uf="activeUf"
          :is-loading="isLoading"
          :indicador-label="activeIndicadorMeta?.label ?? ''"
        />

        <!-- Tabela ranqueada de CNPJs -->
        <IndicadorCnpjTable
          :cnpjs="cnpjs"
          :formato="activeIndicadorMeta?.formato ?? 'dec'"
          :indicador-key="selectedIndicador"
          :indicador-label="activeIndicadorMeta?.label ?? ''"
          :is-loading="isLoading"
        />

      </template>
    </div>

  </div>
</template>

<style scoped>
.indicadores-layout {
  display: flex;
  align-items: flex-start;
  gap: 1.5rem;
  width: 100%;
}

.analysis-panel {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 1.5rem;
}

/* ── Estado vazio ── */
.empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  text-align: center;
  padding: 4rem 2rem;
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  border-radius: 12px;
  gap: 1rem;
}

.empty-icon-wrap {
  width: 4.5rem;
  height: 4.5rem;
  border-radius: 50%;
  background: color-mix(in srgb, var(--primary-color) 10%, var(--card-bg));
  display: flex;
  align-items: center;
  justify-content: center;
}

.empty-icon {
  font-size: 2rem;
  color: var(--primary-color);
  opacity: 0.7;
}

.empty-title {
  margin: 0;
  font-size: 1.1rem;
  font-weight: 600;
  color: var(--text-color);
  opacity: 0.85;
}

.empty-desc {
  margin: 0;
  font-size: 0.85rem;
  color: var(--text-muted);
  max-width: 480px;
  line-height: 1.6;
}

.empty-groups {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
  justify-content: center;
  margin-top: 0.5rem;
}

.empty-group-chip {
  padding: 0.25rem 0.75rem;
  background: color-mix(in srgb, var(--primary-color) 8%, var(--card-bg));
  border: 1px solid var(--card-border);
  border-radius: 99px;
  font-size: 0.7rem;
  color: var(--text-color);
  opacity: 0.75;
}

/* ── Estado de erro ── */
.error-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0.75rem;
  padding: 3rem;
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  border-radius: 12px;
  color: var(--text-muted);
  text-align: center;
}

.error-icon {
  font-size: 2rem;
  color: var(--risk-indicator-critical);
  opacity: 0.7;
}

/* ── Cabeçalho do indicador ativo ── */
.analysis-header {
  display: flex;
  align-items: flex-start;
  gap: 0.75rem;
  padding: 0.85rem 1.25rem;
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  border-radius: 12px;
  border-left: 4px solid var(--primary-color);
}

.analysis-icon {
  font-size: 1.1rem;
  color: var(--primary-color);
  margin-top: 0.2rem;
  flex-shrink: 0;
}

.analysis-title-block {
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
}

.analysis-title {
  margin: 0;
  font-size: 1rem;
  font-weight: 600;
  color: var(--text-color);
  opacity: 0.9;
}

.analysis-metodologia {
  margin: 0;
  font-size: 0.78rem;
  color: var(--text-muted);
  line-height: 1.5;
}
</style>
