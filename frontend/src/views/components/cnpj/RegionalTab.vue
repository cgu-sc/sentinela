<script setup>
import { computed, ref, watch, onMounted, nextTick } from 'vue';
import { storeToRefs } from 'pinia';
import { useRegional } from '@/composables/useRegional';
import { useCnpjNavStore } from '@/stores/cnpjNav';
import { useGeoStore } from '@/stores/geo';
import { useFilterStore } from '@/stores/filters';
import { useFilterParameters } from '@/composables/useFilterParameters';
import { useFrozenData } from '@/composables/useFrozenData';
import RegionalMunicipalTable from '../tables/RegionalMunicipalTable.vue';
import RegionalPharmacyTable from '../tables/RegionalPharmacyTable.vue';
import MunicipalMap from '../maps/MunicipalMap.vue';
const props = defineProps({
  cnpj: { type: String, required: true },
  geoData: { type: Object, default: null },
  cnpjData: { type: Object, default: null }
});

const cnpjNav = useCnpjNavStore();
const geoStore = useGeoStore();
const filterStore = useFilterStore();
const { isAnimating } = storeToRefs(filterStore);
const { getApiParams } = useFilterParameters();
const { regionalData, regionalLoading, regionalLoaded, fetchRegional } = useRegional();

const cachedRegionalData = useFrozenData(regionalData, regionalLoading);
const isRefreshing = computed(() =>
  regionalLoading.value && cachedRegionalData.value !== null && !isAnimating.value
);

// ibge7 do município atual do CNPJ (para pré-selecionar no mapa)
const norm = s => (s ?? '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').trim();
const currentIbge7 = computed(() => {
  if (!props.geoData?.no_municipio || !props.geoData?.sg_uf) return null;
  const target = norm(props.geoData.no_municipio);
  const loc = geoStore.localidades.find(l =>
    norm(l.no_municipio) === target && l.sg_uf === props.geoData.sg_uf
  );
  return loc ? Number(loc.id_ibge7) : null;
});

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

  const targetMun = cachedRegionalData.value?.municipios?.find(m => m.id_ibge7 === filterMunicipioId.value);
  if (!targetMun) return farmacias;

  return farmacias.filter(f =>
    f.municipio?.toLowerCase() === targetMun.municipio?.toLowerCase()
  );
});

const loadData = () => {
  if (props.geoData?.no_regiao_saude) {
    const { inicio, fim } = getApiParams();
    fetchRegional(props.geoData.no_regiao_saude, props.geoData.sg_uf, inicio, fim);
  }
};

onMounted(() => {
  if (props.geoData?.no_regiao_saude) {
    loadData();
  }
});

watch(() => props.geoData?.no_regiao_saude, (newVal) => {
  if (newVal) loadData();
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
      const match = regionalData.value?.municipios?.find(m => 
        m.municipio?.toLowerCase() === municipio.toLowerCase()
      );
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
    <div v-if="!geoData?.no_regiao_saude" class="tab-placeholder">
      <i class="pi pi-map-marker placeholder-icon" />
      <p>Não foi possível identificar a Região de Saúde deste estabelecimento.</p>
    </div>

    <!-- Carregando (apenas na 1ª carga, sem dados prévios) -->
    <div v-else-if="regionalLoading && !cachedRegionalData" class="tab-placeholder">
      <i class="pi pi-spin pi-spinner placeholder-icon" />
      <p>Carregando ranking regional — <span class="semi-bold-text">{{ geoData.no_regiao_saude }}</span>...</p>
    </div>

    <!-- Sem dados carregados ainda (edge case antes do onMounted) -->
    <div v-else-if="!regionalLoaded && !cachedRegionalData" class="tab-placeholder">
      <i class="pi pi-globe placeholder-icon" />
      <p>Carregando o ranking comparativo da <span class="semi-bold-text">{{ geoData.no_regiao_saude }}</span>...</p>
    </div>

    <!-- Sem resultados -->
    <div v-else-if="!cachedRegionalData?.farmacias?.length" class="tab-placeholder">
      <i class="pi pi-exclamation-triangle placeholder-icon" />
      <p>Nenhuma farmácia encontrada para a região <span class="semi-bold-text">{{ geoData.no_regiao_saude }}</span>.</p>
    </div>

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
            :prop-uf="geoData.sg_uf"
            :prop-regiao="geoData.no_regiao_saude"
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
