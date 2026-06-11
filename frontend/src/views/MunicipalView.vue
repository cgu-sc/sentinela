<script setup>
import { computed, ref, watch } from 'vue';
import axios from 'axios';
import { storeToRefs } from 'pinia';
import { useAnalyticsStore } from '@/stores/analytics';
import { buildAnalyticsParams } from '@/stores/analytics';
import { useFilterStore } from '@/stores/filters';
import { useRiskIndicatorsStore } from '@/stores/riskIndicators';
import { useGeoStore } from '@/stores/geo';
import { useFetchAnalytics } from '@/composables/useFetchAnalytics';
import { useRiskIndicatorAnalysis } from '@/composables/useRiskIndicatorAnalysis';
import { API_ENDPOINTS } from '@/config/api';
import { INDICATOR_GROUPS } from '@/config/riskConfig';
import KpiSection from './components/KpiSection.vue';
import MunicipalRiskMap from './components/municipios/MunicipalRiskMap.vue';
import MunicipalRiskTable from './components/municipios/MunicipalRiskTable.vue';
import RiskIndicatorSelector from './components/risk-indicators/RiskIndicatorSelector.vue';

const analyticsStore = useAnalyticsStore();
const filterStore = useFilterStore();
const riskIndicatorsStore = useRiskIndicatorsStore();
const geoStore = useGeoStore();
const { resultadoMunicipios, isLoading } = storeToRefs(analyticsStore);
const {
  selectedRiskIndicator,
  kpis,
  municipios: riskIndicatorMunicipios,
  isLoading: isRiskIndicatorLoading,
  error: riskIndicatorError,
} = storeToRefs(riskIndicatorsStore);
const { fetchRiskIndicator } = useRiskIndicatorAnalysis();

useFetchAnalytics({ includeFatorRisco: false, includeNationalContext: false });

const selectedIbge7 = ref(null);
const mapMunicipios = ref([]);
const isMapLoading = ref(false);
const mapError = ref(null);
let mapAbortController = null;
let mapRequestSeq = 0;

const activeUf = computed(() => filterStore.selectedUF);
const metricMode = computed(() => selectedRiskIndicator.value ? 'indicator' : 'audit');
const activeRiskIndicatorMeta = computed(() => {
  if (!selectedRiskIndicator.value) return null;
  for (const group of INDICATOR_GROUPS) {
    const indicador = group.indicators.find((item) => item.key === selectedRiskIndicator.value);
    if (indicador) return indicador;
  }
  return null;
});
function mergeIndicatorRows(baseRows) {
  if (metricMode.value !== 'indicator') return baseRows;

  const indicadorPorMunicipio = new Map(
    riskIndicatorMunicipios.value.map((row) => [Number(row.id_ibge7), row])
  );

  return baseRows.map((municipioRow) => {
    const indicadorRow = indicadorPorMunicipio.get(Number(municipioRow.id_ibge7));
    return {
      ...municipioRow,
      total_cnpjs: indicadorRow?.total_cnpjs ?? 0,
      total_critico: indicadorRow?.total_critico ?? 0,
      pct_critico: indicadorRow?.pct_critico ?? 0,
    };
  });
}

const activeMapData = computed(() => mergeIndicatorRows(mapMunicipios.value));
const activeTableData = computed(() => mergeIndicatorRows(resultadoMunicipios.value));
const activeMapLoading = computed(() =>
  metricMode.value === 'indicator'
    ? (isRiskIndicatorLoading.value || isMapLoading.value)
    : isMapLoading.value
);
const activeTableLoading = computed(() =>
  metricMode.value === 'indicator' ? isRiskIndicatorLoading.value || isLoading.value : isLoading.value
);
const activeMetricLabel = computed(() =>
  metricMode.value === 'indicator'
    ? (activeRiskIndicatorMeta.value?.label ?? 'Indicador')
    : 'Percentual não comprovação'
);
const selectedLocalidade = computed(() => {
  if (selectedIbge7.value == null) return null;
  const localidade = geoStore.localidades.find(
    (item) => Number(item.id_ibge7) === Number(selectedIbge7.value)
  );
  if (!localidade?.id_ibge7 || !localidade?.id_regiao_saude || !localidade?.sg_uf || !localidade?.no_municipio) {
    throw new Error('Municipio selecionado nao encontrado no contrato de localidades.');
  }
  return localidade;
});
const selectedRegiaoNome = computed(() => {
  const regiaoId = filterStore.selectedRegiaoSaude && filterStore.selectedRegiaoSaude !== 'Todos'
    ? filterStore.selectedRegiaoSaude
    : selectedLocalidade.value?.id_regiao_saude;
  if (!regiaoId) return null;
  const nome = geoStore.getRegiaoNomeById(regiaoId);
  if (!nome) throw new Error('Regiao de saude selecionada sem nome no contrato de localidades.');
  return nome;
});

watch(
  () => filterStore.selectedMunicipio,
  (municipio) => {
    selectedIbge7.value = municipio && municipio !== 'Todos'
      ? Number(municipio)
      : null;
  },
  { immediate: true },
);

const mapApiParams = computed(() => {
  const params = { ...filterStore.apiParams, idIbge7: null };
  return buildAnalyticsParams(params);
});

const mapApiParamsKey = computed(() => JSON.stringify(mapApiParams.value));

watch(
  mapApiParamsKey,
  async () => {
    if (!filterStore.isPeriodoValido) return;

    const requestId = ++mapRequestSeq;
    if (mapAbortController) {
      mapAbortController.abort();
    }
    mapAbortController = new AbortController();
    isMapLoading.value = true;
    mapError.value = null;

    try {
      const response = await axios.get(API_ENDPOINTS.analyticsResumo, {
        params: mapApiParams.value,
        signal: mapAbortController.signal,
      });
      if (requestId !== mapRequestSeq) return;
      if (!Array.isArray(response.data?.resultado_municipios)) {
        throw new Error('Contrato invalido em analytics/resumo: resultado_municipios ausente.');
      }
      mapMunicipios.value = response.data.resultado_municipios;
    } catch (error) {
      if (axios.isCancel(error)) return;
      console.error('Erro ao buscar municipios para o mapa:', error);
      mapMunicipios.value = [];
      mapError.value = 'Não foi possível carregar a base municipal do mapa.';
    } finally {
      if (requestId === mapRequestSeq) {
        isMapLoading.value = false;
      }
    }
  },
  { immediate: true },
);

function handleSelectMunicipio(ibge7) {
  if (!ibge7) {
    selectedIbge7.value = null;
    filterStore.selectedMunicipio = 'Todos';
    return;
  }

  const localidade = geoStore.localidades.find(
    (item) => Number(item.id_ibge7) === Number(ibge7)
  );
  if (!localidade?.id_ibge7 || !localidade?.id_regiao_saude || !localidade?.sg_uf) {
    throw new Error('Municipio selecionado sem contrato geografico completo.');
  }

  selectedIbge7.value = Number(localidade.id_ibge7);
  filterStore.selectedMunicipio = String(localidade.id_ibge7);
}

function handleClearRegiaoFilter() {
  filterStore.selectedRegiaoSaude = 'Todos';
  filterStore.selectedMunicipio = 'Todos';
}

function handleSelectUf(uf) {
  filterStore.selectedMunicipio = 'Todos';
  filterStore.selectedRegiaoSaude = 'Todos';
  filterStore.selectedUF = uf;
}

function handleMapBackToUf() {
  filterStore.selectedMunicipio = 'Todos';
  filterStore.selectedRegiaoSaude = 'Todos';
}

function handleMapBackToBrazil() {
  filterStore.selectedMunicipio = 'Todos';
  filterStore.selectedRegiaoSaude = 'Todos';
  filterStore.selectedUF = 'Todos';
}

function handleRiskIndicatorSelect(key) {
  fetchRiskIndicator(key);
}
</script>

<template>
  <div class="municipios-page">
    <KpiSection />

    <div class="municipios-layout">
      <div class="municipios-analysis-panel">
        <div v-if="riskIndicatorError" class="indicator-error">
          <i class="pi pi-exclamation-circle" />
          <span>{{ riskIndicatorError }}</span>
        </div>
        <div v-if="mapError" class="indicator-error">
          <i class="pi pi-exclamation-circle" />
          <span>{{ mapError }}</span>
        </div>

        <MunicipalRiskMap
          :map-data="activeMapData"
          :kpis="kpis"
          :active-uf="activeUf"
          :is-loading="activeMapLoading"
          :selected-ibge7="selectedIbge7"
          :selected-regiao="filterStore.selectedRegiaoSaude"
          :metric-mode="metricMode"
          :metric-label="activeMetricLabel"
          :selected-municipio-nome="selectedLocalidade?.no_municipio ?? null"
          :selected-regiao-nome="selectedRegiaoNome"
          @select-municipio="handleSelectMunicipio"
          @select-uf="handleSelectUf"
          @back-to-uf="handleMapBackToUf"
          @clear-geography="handleMapBackToBrazil"
        />

        <MunicipalRiskTable
          :municipios="activeTableData"
          :participation-rows="activeMapData"
          :is-loading="activeTableLoading"
          :selected-ibge7="selectedIbge7"
          :metric-mode="metricMode"
          :metric-label="activeMetricLabel"
          :selected-regiao-nome="selectedRegiaoNome"
          @select-municipio="handleSelectMunicipio"
          @clear-regiao-filter="handleClearRegiaoFilter"
        />
      </div>

      <RiskIndicatorSelector :active-risk-indicator-meta="activeRiskIndicatorMeta" @select="handleRiskIndicatorSelect" />
    </div>
  </div>
</template>

<style scoped>
.municipios-page {
  --indicator-selector-width: 220px;
  display: flex;
  flex-direction: column;
  gap: 1rem;
  width: 100%;
  min-width: 0;
}

.municipios-layout {
  display: flex;
  align-items: flex-start;
  gap: 1rem;
  width: 100%;
}

.municipios-analysis-panel {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 1rem;
}

.indicator-error {
  display: flex;
  align-items: center;
  gap: 0.55rem;
  padding: 0.75rem 0.9rem;
  border: 1px solid color-mix(in srgb, var(--risk-indicator-critical) 26%, transparent);
  border-radius: 8px;
  background: color-mix(in srgb, var(--risk-indicator-critical) 8%, var(--card-bg));
  color: var(--text-color);
  font-size: 0.78rem;
}

.indicator-error i {
  color: var(--risk-indicator-critical);
}
</style>
