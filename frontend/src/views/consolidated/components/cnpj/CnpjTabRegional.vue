<script setup>
import { computed, ref, watch, onMounted, nextTick } from 'vue';
import { useRegional } from '@/composables/useRegional';
import { useCnpjNavStore } from '@/stores/cnpjNav';
import RegionalMunicipalityTable from '../RegionalMunicipalityTable.vue';
import RegionalPharmacyTable from '../RegionalPharmacyTable.vue';

const props = defineProps({
  cnpj: { type: String, required: true },
  geoData: { type: Object, default: null }
});

const cnpjNav = useCnpjNavStore();
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
      filterMunicipio.value = null; // Limpa qualquer filtro anterior
    } else {
      filterMunicipio.value = municipio;
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
            :municipio-atual="filterMunicipio || geoData.no_municipio"
            :uf-atual="geoData.sg_uf"
            :regiao-nome="geoData.no_regiao_saude"
            :selected-filter="filterMunicipio"
            @select-municipio="toggleMunicipioFilter"
          />
        </div>
        <div class="map-wrapper-col">
          <div class="map-placeholder-card">
             <div class="placeholder-header">
                <i class="pi pi-map"></i>
                <span>Mapa da Região</span>
             </div>
             <div class="placeholder-content">
                <i class="pi pi-compass placeholder-main-icon"></i>
                <p>Visualização Geográfica da Região de Saúde</p>
             </div>
          </div>
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

.map-placeholder-card {
  flex: 1;
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  border-radius: 12px;
  display: flex;
  flex-direction: column;
  overflow: hidden;
  box-shadow: 0 4px 15px rgba(0,0,0,0.1);
}

.placeholder-header {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.75rem 1rem;
  border-bottom: 1px solid var(--tabs-border);
  font-size: 0.75rem;
  font-weight: 700;
  text-transform: uppercase;
  color: var(--text-color);
  opacity: 0.8;
}

.placeholder-content {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 1rem;
  color: var(--text-muted);
  background: radial-gradient(circle at center, rgba(255,255,255,0.03) 0%, transparent 70%);
}

.placeholder-main-icon {
  font-size: 3rem;
  opacity: 0.2;
}

.placeholder-content p {
  font-size: 0.85rem;
  opacity: 0.5;
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
