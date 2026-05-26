<script setup>
import { computed, ref, watch, onMounted, nextTick } from 'vue';
import { storeToRefs } from 'pinia';
import { useRegional } from '@/composables/useRegional';
import { useCnpjNavStore } from '@/stores/cnpjNav';
import { useFilterStore } from '@/stores/filters';
import { useFilterParameters } from '@/composables/useFilterParameters';
import { useStableTabState } from '@/composables/useStableTabState';
import RegionalMunicipalTable from '../tables/RegionalMunicipalTable.vue';
import RegionalPharmacyTable from '../tables/RegionalPharmacyTable.vue';
import MunicipalMap from '../maps/MunicipalMap.vue';
import TabPlaceholder from './TabPlaceholder.vue';
const props = defineProps({
  cnpj: { type: String, required: true },
  geoData: { type: Object, default: null },
  cnpjData: { type: Object, default: null },
  isActive: { type: Boolean, default: false }
});

const cnpjNav = useCnpjNavStore();
const filterStore = useFilterStore();
const { isAnimating } = storeToRefs(filterStore);
const { getApiParams } = useFilterParameters();
const { regionalData, regionalLoading, regionalLoaded, regionalError, fetchRegional } = useRegional();

const {
  cachedData: cachedRegionalData,
  isRefreshing,
} = useStableTabState(regionalData, regionalLoading, regionalError);

const currentIbge7 = computed(() => props.geoData?.id_ibge7 ? Number(props.geoData.id_ibge7) : null);

const filterMunicipioId = ref(null);

function toggleMunicipioFilter(ibge7) {
  const id = ibge7 ? Number(ibge7) : null;
  if (filterMunicipioId.value === id) {
    filterMunicipioId.value = null;
  } else {
    filterMunicipioId.value = id;
  }
}

const filteredFarmacias = computed(() => {
  const farmacias = cachedRegionalData.value?.farmacias ?? [];
  if (!filterMunicipioId.value) return farmacias;

  return farmacias.filter(f => Number(f.id_ibge7) === Number(filterMunicipioId.value));
});

const loadData = () => {
  if (!props.isActive) return;
  if (props.geoData?.id_regiao_saude || props.geoData?.sg_uf) {
    const { inicio, fim } = getApiParams();
    fetchRegional(
      props.geoData.sg_uf,
      inicio,
      fim,
      props.geoData.id_regiao_saude ?? null,
    );
  }
};

onMounted(() => {
  if (props.geoData?.id_regiao_saude || props.geoData?.sg_uf) {
    loadData();
  }
});

watch(() => [props.geoData?.id_regiao_saude, props.geoData?.sg_uf], ([regiaoId, uf]) => {
  if (regiaoId || uf) loadData();
});

watch(() => props.isActive, (active) => {
  if (active) loadData();
});

watch(
  () => filterStore.periodo,
  () => {
    if (isAnimating.value) return;
    loadData();
  },
  { deep: true }
);

watch(
  () => cnpjNav.pendingMunicipio,
  async (municipio) => {
    if (!municipio) return;
    if (!props.isActive) return;

    if (!regionalLoaded.value) {
      loadData();
      await new Promise((resolve) => {
        const stop = watch(regionalLoaded, (loaded) => {
          if (loaded) { stop(); resolve(); }
        });
      });
    }

    await nextTick();
    if (municipio === '__RESET__') {
      filterMunicipioId.value = null;
    } else {
      const municipioId = typeof municipio === 'object' ? municipio.id_ibge7 : null;
      const municipioNome = typeof municipio === 'object' ? municipio.municipio : municipio;
      const match = regionalData.value?.municipios?.find(m => {
        if (municipioId) return Number(m.id_ibge7) === Number(municipioId);
        return m.municipio?.toLowerCase() === String(municipioNome).toLowerCase();
      });
      if (match) filterMunicipioId.value = match.id_ibge7;
    }
    cnpjNav.consumePendingMunicipio();

    setTimeout(() => {
      const el = document.querySelector('.pharmacy-ranking-section');
      if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }, 300);
  },
  { immediate: true }
);

</script>

<template>
  <div class="tab-content regional-tab" :class="{ 'is-refreshing': isRefreshing }">
    <!-- Sem geo data -->
    <TabPlaceholder
      v-if="!cnpjData"
      variant="error"
      icon="pi-exclamation-circle"
      title="Erro ao carregar"
      description="Não foi possível carregar os dados. Verifique a conexão com o servidor."
    />

    <TabPlaceholder
      v-else-if="!geoData?.sg_uf"
      icon="pi-map-marker"
      title="Geolocalização indisponível"
      description="Não foi possível identificar a Região de Saúde deste estabelecimento para gerar o ranking comparativo."
    />

    <TabPlaceholder
      v-else-if="regionalError"
      variant="error"
      icon="pi-exclamation-circle"
      title="Erro ao carregar"
      :description="regionalError"
    />

    <div
      v-else-if="!regionalLoaded && !cachedRegionalData"
      class="regional-initial-loading-sentinel"
      aria-hidden="true"
    />

    <TabPlaceholder
      v-else-if="!cachedRegionalData?.farmacias?.length"
      icon="pi-map"
      title="Nenhuma farmácia encontrada"
      :description="`Não há estabelecimentos registrados na região ${geoData.no_regiao_saude} no período selecionado.`"
    />

    <!-- Conteúdo principal -->
    <template v-else>
      <div class="regional-top-row">
        <div class="table-wrapper-col">
          <RegionalMunicipalTable
            :municipios="cachedRegionalData.municipios"
            :municipio-atual="geoData.no_municipio"
            :uf-atual="geoData.sg_uf"
            :regiao-nome="geoData.no_regiao_saude"
            :selected-filter="filterMunicipioId"
            @select-municipio="toggleMunicipioFilter"
          />
        </div>
        <div class="map-wrapper-col">
          <MunicipalMap
            v-if="isActive"
            :prop-uf="geoData.sg_uf"
            :prop-regiao="geoData.id_regiao_saude ? String(geoData.id_regiao_saude) : null"
            :prop-municipio-ibge7="filterMunicipioId ?? currentIbge7"
            :prop-municipios-data="cachedRegionalData.municipios"
            @select-municipio="(ibge7) => toggleMunicipioFilter(ibge7)"
          />
        </div>
      </div>

      <!-- SEÇÃO DE GEOGRAFIA: Mapa + Detalhamento Municipal -->
      <RegionalPharmacyTable
        :farmacias="filteredFarmacias"
        :cnpj-atual="cnpj"
        :municipio-atual="geoData.no_municipio"
        :uf-atual="geoData.sg_uf"
        class="pharmacy-ranking-section"
      />
    </template>
  </div>
</template>

<style scoped>
.regional-tab {
  display: flex;
  flex-direction: column;
  gap: 1.5rem;
  width: 100%;
}

.regional-top-row {
  display: flex;
  gap: 1.5rem;
  align-items: stretch;
  width: 100%;
}

.table-wrapper-col {
  flex: 60;
  min-width: 0;
}

.map-wrapper-col {
  flex: 40;
  display: flex;
  min-width: 0;
}

.tab-placeholder {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 1rem;
  min-height: 300px;
  color: var(--text-muted);
  opacity: 0.5;
}

.placeholder-icon {
  font-size: 3rem;
}

.semi-bold-text {
  font-weight: 600;
}

.tab-placeholder p {
  font-size: 0.875rem;
}

.regional-tab.is-refreshing {
  opacity: 0.6;
  pointer-events: none;
  transition: opacity 0.2s ease;
}

:deep(.municipio-chip) {
  background: var(--primary-color) !important;
  color: white !important;
  font-weight: 600;
  font-size: 0.9rem;
}
</style>
