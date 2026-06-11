<script setup>
import { computed, ref, watch } from 'vue';
import { storeToRefs } from 'pinia';
import { useRoute, useRouter } from 'vue-router';
import { DEFAULT_TARGET_KEY, TARGET_GROUPS } from '@/config/targetConfig';
import { useTargetsStore } from '@/stores/targets';
import { useFilterStore } from '@/stores/filters';
import { useFrozenData } from '@/composables/useFrozenData';
import TargetSelector from './components/targets/TargetSelector.vue';
import TargetKpiStrip from './components/targets/TargetKpiStrip.vue';
import TargetMap from './components/targets/TargetMap.vue';
import TargetTableRenderer from './components/targets/TargetTableRenderer.vue';
import ClinicalIncompatibilityDialog from './components/cnpj/ClinicalIncompatibilityDialog.vue';

const route = useRoute();
const router = useRouter();
const targetsStore = useTargetsStore();
const filterStore = useFilterStore();
const clinicalIncompatibilityDialogVisible = ref(false);
const clinicalIncompatibilityCnpj = ref('');

const {
  selectedTarget,
  selectedTargetMeta,
  targetKpis,
  mapData,
  rows,
  totalRecords,
  page,
  rowsPerPage,
  sortField,
  sortOrder,
  isLoading,
  isTableLoading,
  sourceNotice,
} = storeToRefs(targetsStore);

const enabledTargetKeys = computed(() =>
  TARGET_GROUPS
    .flatMap(group => group.targets)
    .filter(target => target.enabled)
    .map(target => target.key)
);

const first = computed(() => (page.value - 1) * rowsPerPage.value);
const activeUf = computed(() => filterStore.selectedUF);
const displayedTargetMeta = useFrozenData(
  () => selectedTargetMeta.value,
  computed(() => isLoading.value),
);
const selectedMunicipioIbge7 = computed(() => {
  const value = filterStore.selectedMunicipio;
  return value && value !== 'Todos' ? Number(value) : null;
});

function normalizeRouteTarget(rawTarget) {
  const key = String(rawTarget || DEFAULT_TARGET_KEY);
  if (enabledTargetKeys.value.includes(key)) return key;
  return DEFAULT_TARGET_KEY;
}

function selectTarget(key) {
  targetsStore.setSelectedTarget(key);
  router.replace({ path: '/alvos', query: { tipo: key } });
  targetsStore.loadCurrentTarget();
}

function onTableLazyLoad(event) {
  targetsStore.updateTableState(event);
}

function openClinicalIncompatibilityDialog(cnpj) {
  if (!cnpj) return;
  clinicalIncompatibilityCnpj.value = cnpj;
  clinicalIncompatibilityDialogVisible.value = true;
}

function onSelectUf(uf) {
  filterStore.selectedMunicipio = 'Todos';
  filterStore.selectedRegiaoSaude = 'Todos';
  filterStore.selectedUF = uf;
}

function onSelectMunicipio(ibge7) {
  filterStore.selectedMunicipio = ibge7 ? String(ibge7) : 'Todos';
}

function returnMapToUf() {
  filterStore.selectedMunicipio = 'Todos';
  filterStore.selectedRegiaoSaude = 'Todos';
}

function clearMapGeography() {
  filterStore.selectedMunicipio = 'Todos';
  filterStore.selectedRegiaoSaude = 'Todos';
  filterStore.selectedUF = 'Todos';
}

watch(
  () => route.query.tipo,
  (targetFromRoute) => {
    const normalizedTarget = normalizeRouteTarget(targetFromRoute);
    if (route.query.tipo !== normalizedTarget) {
      router.replace({ path: '/alvos', query: { tipo: normalizedTarget } });
      return;
    }

    if (selectedTarget.value !== normalizedTarget) {
      targetsStore.setSelectedTarget(normalizedTarget);
    }
    targetsStore.loadCurrentTarget();
  },
  { immediate: true }
);

watch(
  () => filterStore.indicadoresTabelaApiParamsKey,
  () => {
    targetsStore.page = 1;
    targetsStore.loadCurrentTarget();
  }
);
</script>

<template>
  <div class="targets-page">
    <TargetKpiStrip
      :kpis="targetKpis"
      :source-notice="sourceNotice"
    />

    <div class="targets-layout">
      <div class="targets-main">
        <TargetMap
          :target-meta="displayedTargetMeta"
          :map-data="mapData"
          :active-uf="activeUf"
          :selected-ibge7="selectedMunicipioIbge7"
          :selected-regiao="filterStore.selectedRegiaoSaude"
          :is-loading="isLoading"
          :source-notice="sourceNotice"
          @select-uf="onSelectUf"
          @select-municipio="onSelectMunicipio"
          @back-to-uf="returnMapToUf"
          @clear-geography="clearMapGeography"
        />

        <TargetTableRenderer
          :target-key="selectedTarget"
          :target-meta="displayedTargetMeta"
          :rows="rows"
          :loading="isTableLoading || isLoading"
          :total-records="totalRecords"
          :first="first"
          :rows-per-page="rowsPerPage"
          :sort-field="sortField"
          :sort-order="sortOrder"
          :source-notice="sourceNotice"
          @lazy-load="onTableLazyLoad"
          @open-incompatibility="openClinicalIncompatibilityDialog"
        />
      </div>

      <TargetSelector
        :selected-target="selectedTarget"
        @select="selectTarget"
      />
    </div>

    <ClinicalIncompatibilityDialog
      v-model="clinicalIncompatibilityDialogVisible"
      :cnpj="clinicalIncompatibilityCnpj"
    />
  </div>
</template>

<style scoped>
.targets-page {
  --target-selector-width: 220px;
  display: flex;
  flex-direction: column;
  gap: 1rem;
  width: 100%;
}

.targets-layout {
  display: flex;
  align-items: flex-start;
  gap: 1rem;
  width: 100%;
}

.targets-main {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 1rem;
}
</style>
