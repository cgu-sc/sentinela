<script setup>
import { computed, onMounted, ref } from 'vue';
import { storeToRefs } from 'pinia';
import { useFilterStore } from '@/stores/filters';
import { useIndicadoresStore } from '@/stores/indicadores';
import { useFetchIndicadores } from '@/composables/useFetchIndicadores';
import { INDICATOR_GROUPS } from '@/config/riskConfig';

import IndicatorSelector from './components/indicadores/IndicatorSelector.vue';
import IndicadorKpiCards from './components/indicadores/IndicadorKpiCards.vue';
import IndicadorDistribution from './components/indicadores/IndicadorDistribution.vue';
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

// ── Seleção de município no mapa ──────────────────────────────────────────────
const selectedMunicipioIbge7 = ref(null);
const selectedMunicipioNome = ref(null);

function onSelectMunicipio(ibge7, nome) {
  selectedMunicipioIbge7.value = ibge7;
  selectedMunicipioNome.value = nome;
}

function clearMunicipioFilter() {
  selectedMunicipioIbge7.value = null;
  selectedMunicipioNome.value = null;
}

function onSelectUf(uf) {
  clearMunicipioFilter();
  filterStore.selectedUF = uf;
}

// CNPJs filtrados pelo município selecionado (se houver)
const filteredCnpjs = computed(() => {
  if (!selectedMunicipioIbge7.value) return cnpjs.value;
  return cnpjs.value.filter(c => c.id_ibge7 === selectedMunicipioIbge7.value);
});

function onIndicadorSelect(key) {
  clearMunicipioFilter();
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

    <!-- Painel principal de análise -->
    <div class="analysis-panel">

      <!-- Estado vazio: nenhum indicador selecionado -->
      <div v-if="!selectedIndicador && !isLoading" class="empty-state">
        <div class="empty-icon-wrap">
          <i class="pi pi-shield empty-icon" />
        </div>
        <h2 class="empty-title">Selecione um Indicador</h2>
        <p class="empty-desc">
          Escolha um dos 18 indicadores de risco no painel à direita para visualizar
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

        <!-- KPI Cards -->
        <IndicadorKpiCards
          :kpis="kpis"
          :formato="activeIndicadorMeta?.formato ?? 'dec'"
          :is-loading="isLoading"
        />

        <!-- Distribuição/Calibração -->
        <IndicadorDistribution
          :cnpjs="cnpjs"
          :threshold-key="activeIndicadorMeta?.thresholdKey"
          :regional-median="kpis?.mediana_reg"
          :regional-mad="kpis?.mad_reg"
          :is-loading="isLoading"
        />

        <!-- Mapa -->
        <IndicadorMap
          :map-data="municipios"
          :active-uf="activeUf"
          :is-loading="isLoading"
          :indicador-label="activeIndicadorMeta?.label ?? ''"
          :selected-ibge7="selectedMunicipioIbge7"
          @select-municipio="onSelectMunicipio"
          @select-uf="onSelectUf"
        />

        <!-- Filtro de município ativo -->
        <div v-if="selectedMunicipioNome" class="municipio-filter-chip">
          <i class="pi pi-map-marker" />
          <span>Filtrando: <strong>{{ selectedMunicipioNome }}</strong></span>
          <button class="chip-clear" @click="clearMunicipioFilter" title="Limpar filtro">
            <i class="pi pi-times" />
          </button>
        </div>

        <!-- Tabela ranqueada de CNPJs -->
        <IndicadorCnpjTable
          :cnpjs="filteredCnpjs"
          :formato="activeIndicadorMeta?.formato ?? 'dec'"
          :indicador-key="selectedIndicador"
          :indicador-label="activeIndicadorMeta?.label ?? ''"
          :is-loading="isLoading"
        />

      </template>
    </div>

    <!-- Painel lateral de seleção de indicadores (direita) -->
    <IndicatorSelector :active-indicador-meta="activeIndicadorMeta" @select="onIndicadorSelect" />

  </div>
</template>

<style scoped>
.indicadores-layout {
  display: flex;
  align-items: flex-start;
  gap: 1rem;
  width: 100%;
}

.analysis-panel {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 1rem;
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


/* ── Chip de filtro de município ── */
.municipio-filter-chip {
  display: inline-flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.4rem 0.85rem;
  background: color-mix(in srgb, var(--primary-color) 10%, var(--card-bg));
  border: 1px solid color-mix(in srgb, var(--primary-color) 30%, transparent);
  border-radius: 99px;
  font-size: 0.78rem;
  color: var(--text-color);
  align-self: flex-start;
}

.municipio-filter-chip i.pi-map-marker {
  color: var(--primary-color);
  font-size: 0.75rem;
}

.chip-clear {
  display: flex;
  align-items: center;
  justify-content: center;
  background: none;
  border: none;
  cursor: pointer;
  padding: 0.1rem;
  color: var(--text-muted);
  font-size: 0.65rem;
  margin-left: 0.15rem;
  opacity: 0.7;
  transition: opacity 0.15s ease;
}

.chip-clear:hover {
  opacity: 1;
}
</style>
