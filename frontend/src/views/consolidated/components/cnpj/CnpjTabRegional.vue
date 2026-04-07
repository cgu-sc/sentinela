<script setup>
import { computed, ref, watch, onMounted, nextTick } from 'vue';
import { useRegional } from '@/composables/useRegional';
import { useCnpjNavStore } from '@/stores/cnpjNav';
import RegionalMunicipalityTable from '../RegionalMunicipalityTable.vue';
import RegionalPharmacyTable from '../RegionalPharmacyTable.vue';
import RegionalMapChart from '../RegionalMapChart.vue';

const props = defineProps({
  cnpj: { type: String, required: true },
  geoData: { type: Object, default: null }
});

const cnpjNav = useCnpjNavStore();
const { regionalData, regionalLoading, regionalLoaded, fetchRegional } = useRegional();

const filterMunicipioId = ref(null);

function toggleMunicipioFilter(ibge7) {
  if (filterMunicipioId.value === ibge7) {
    filterMunicipioId.value = null;
  } else {
    filterMunicipioId.value = ibge7;
  }
}

const filteredFarmacias = computed(() => {
  const farmacias = regionalData.value?.farmacias ?? [];
  if (!filterMunicipioId.value) return farmacias;
  
  // Encontra o nome do município pelo ID para filtrar a lista de farmácias (que só tem o nome)
  const targetMun = regionalData.value?.municipios?.find(m => m.id_ibge7 === filterMunicipioId.value);
  if (!targetMun) return farmacias;

  return farmacias.filter(f => 
    f.municipio?.toLowerCase() === targetMun.municipio?.toLowerCase()
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

// ── Consome o múnicipio pendente do store (navegação via header) ──────────
watch(
  () => cnpjNav.pendingMunicipio,
  async (municipio) => {
    if (!municipio) return;

    // Garante que os dados regionais estejam carregados primeiro
    if (!regionalLoaded.value) {
      loadData();
      // Aguarda até os dados estarem prontos
      await new Promise((resolve) => {
        const stop = watch(regionalLoaded, (loaded) => {
          if (loaded) { stop(); resolve(); }
        });
      });
    }

    // Aplica o filtro e consome o estado
    await nextTick();
    if (municipio === '__RESET__') {
      filterMunicipioId.value = null;
    } else {
      // Tenta encontrar o ID pelo nome fornecido pelo store
      const match = regionalData.value?.municipios?.find(m => 
        m.municipio?.toLowerCase() === municipio.toLowerCase()
      );
      if (match) filterMunicipioId.value = match.id_ibge7;
    }
    cnpjNav.consumePendingMunicipio();

    // Scroll suave para a tabela de farmácias (Ranking)
    setTimeout(() => {
      const el = document.querySelector('.pharmacy-ranking-section');
      if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }, 300);
  },
  { immediate: true }
);

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
      <p>Carregando ranking regional — <span class="semi-bold-text">{{ geoData.no_regiao_saude }}</span>...</p>
    </div>

    <!-- Sem dados carregados ainda -->
    <div v-else-if="!regionalLoaded" class="tab-placeholder">
      <i class="pi pi-globe placeholder-icon" />
      <p>Carregando o ranking comparativo da <span class="semi-bold-text">{{ geoData.no_regiao_saude }}</span>...</p>
    </div>

    <!-- Sem resultados -->
    <div v-else-if="!regionalData?.farmacias?.length" class="tab-placeholder">
      <i class="pi pi-exclamation-triangle placeholder-icon" />
      <p>Nenhuma farmácia encontrada para a região <span class="semi-bold-text">{{ geoData.no_regiao_saude }}</span>.</p>
    </div>

    <!-- Conteúdo principal -->
    <template v-else>
      <div class="regional-top-row">
        <div class="table-wrapper-col">
          <RegionalMunicipalityTable 
            :municipios="regionalData.municipios"
            :municipio-atual="geoData.no_municipio"
            :uf-atual="geoData.sg_uf"
            :regiao-nome="geoData.no_regiao_saude"
            :selected-filter="filterMunicipioId"
            @select-municipio="toggleMunicipioFilter"
          />
        </div>
        <div class="map-wrapper-col">
          <RegionalMapChart
            :regional-data="regionalData"
            :geo-data="geoData"
            :selected-municipio-id="filterMunicipioId"
            @select-municipio="toggleMunicipioFilter"
          />
        </div>
      </div>

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
}

.regional-top-row {
  display: flex;
  gap: 1.5rem;
  align-items: stretch;
}

.table-wrapper-col {
  flex: 3;
}

.map-wrapper-col {
  flex: 2;
  display: flex;
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
