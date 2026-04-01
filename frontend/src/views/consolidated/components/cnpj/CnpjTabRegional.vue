<script setup>
import { computed, ref, watch, onMounted } from 'vue';
import { useRegional } from '@/composables/useRegional';
import RegionalMunicipalityTable from '../RegionalMunicipalityTable.vue';
import RegionalPharmacyTable from '../RegionalPharmacyTable.vue';

const props = defineProps({
  cnpj: { type: String, required: true },
  geoData: { type: Object, default: null }
});

const { regionalData, regionalLoading, regionalLoaded, fetchRegional } = useRegional();

// ── Filtro Cruzado de Município (Regional) ────────────────
const filterMunicipio = ref(null);

function toggleMunicipioFilter(nome) {
  if (filterMunicipio.value?.toLowerCase() === nome?.toLowerCase()) {
    filterMunicipio.value = null;
  } else {
    filterMunicipio.value = nome;
  }
}

const filteredFarmacias = computed(() => {
  const farmacias = regionalData.value?.farmacias ?? [];
  if (!filterMunicipio.value) return farmacias;
  
  return farmacias.filter(f => 
    f.municipio?.toLowerCase() === filterMunicipio.value.toLowerCase()
  );
});

const loadData = () => {
    if (props.geoData?.no_regiao_saude && !regionalLoaded.value) {
        fetchRegional(props.geoData.no_regiao_saude, props.geoData.sg_uf);
    }
}

onMounted(() => {
  if (props.geoData?.no_regiao_saude) {
    loadData();
  }
});

watch(() => props.geoData?.no_regiao_saude, (newVal) => {
    if (newVal) loadData();
});

</script>

<template>
  <div class="tab-content regional-tab">
    <!-- Sem geo data -->
    <div v-if="!geoData?.no_regiao_saude" class="tab-placeholder">
      <i class="pi pi-map-marker placeholder-icon" />
      <p>Não foi possível identificar a Região de Saúde deste estabelecimento.</p>
    </div>

    <!-- Carregando -->
    <div v-else-if="regionalLoading" class="tab-placeholder">
      <i class="pi pi-spin pi-spinner placeholder-icon" />
      <p>Carregando ranking regional — <strong>{{ geoData.no_regiao_saude }}</strong>...</p>
    </div>

    <!-- Sem dados carregados ainda -->
    <div v-else-if="!regionalLoaded" class="tab-placeholder">
      <i class="pi pi-globe placeholder-icon" />
      <p>Carregando o ranking comparativo da <strong>{{ geoData.no_regiao_saude }}</strong>...</p>
    </div>

    <!-- Sem resultados -->
    <div v-else-if="!regionalData?.farmacias?.length" class="tab-placeholder">
      <i class="pi pi-exclamation-triangle placeholder-icon" />
      <p>Nenhuma farmácia encontrada para a região <strong>{{ geoData.no_regiao_saude }}</strong>.</p>
    </div>

    <!-- Conteúdo principal -->
    <template v-else>
      <RegionalMunicipalityTable 
        :municipios="regionalData.municipios"
        :municipio-atual="filterMunicipio || geoData.no_municipio"
        :uf-atual="geoData.sg_uf"
        :selected-filter="filterMunicipio"
        @select-municipio="toggleMunicipioFilter"
      />

      <RegionalPharmacyTable
        :farmacias="filteredFarmacias"
        :cnpj-atual="cnpj"
        :municipio-atual="geoData.no_municipio"
        :uf-atual="geoData.sg_uf"
      />
    </template>
  </div>
</template>

<style scoped>
.regional-tab {
  display: flex;
  flex-direction: column;
  gap: 1.5rem;
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

.tab-placeholder p {
  font-size: 0.875rem;
}

.filter-status-row {
  display: flex;
  align-items: center;
  gap: 1rem;
  padding: 0.75rem 1.5rem;
  background: color-mix(in srgb, var(--primary-color) 4%, var(--card-bg));
  border: 1px dashed var(--sidebar-border);
  border-radius: 8px;
  margin: 1rem 0;
}

.filter-label {
  font-size: 0.85rem;
  font-weight: 600;
  color: var(--text-secondary);
  text-transform: uppercase;
  letter-spacing: 0.02em;
}

:deep(.municipio-chip) {
  background: var(--primary-color) !important;
  color: white !important;
  font-weight: 600;
  font-size: 0.9rem;
}
</style>
