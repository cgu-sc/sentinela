<script setup>
import { computed, ref, watch } from 'vue';
import { use, registerMap } from 'echarts/core';
import { CanvasRenderer } from 'echarts/renderers';
import { MapChart } from 'echarts/charts';
import { TooltipComponent } from 'echarts/components';
import VChart from 'vue-echarts';
import { useGeoStore } from '@/stores/geo';
import { useThemeStore } from '@/stores/theme';
import { useFormatting } from '@/composables/useFormatting';
import { useChartTheme } from '@/config/chartTheme';
import { buildHealthRegionGeoJson } from '@/utils/geo/municipalTerritory';

use([CanvasRenderer, MapChart, TooltipComponent]);

const props = defineProps({
  geoData: { type: Object, required: true },
  riskClass: {
    type: String,
    default: '',
    validator: (value) => ['', 'risk-low', 'risk-medium', 'risk-high', 'risk-critical'].includes(value),
  },
});

const geoStore = useGeoStore();
const themeStore = useThemeStore();
const { formatTitleCase } = useFormatting();
const { chartTheme } = useChartTheme();
const mapKey = ref(0);

const uf = computed(() => props.geoData?.sg_uf ?? null);
const regiaoId = computed(() => props.geoData?.id_regiao_saude ?? null);
const municipioId = computed(() => Number(props.geoData?.id_ibge7));
const municipioNome = computed(() => props.geoData?.no_municipio ?? null);

const territoryState = computed(() => {
  if (!uf.value || !regiaoId.value || !Number.isFinite(municipioId.value)) {
    return { status: 'error', message: 'Territorio nao identificado para este CNPJ.' };
  }
  if (!geoStore.municipiosGeoJson || geoStore.localidades.length === 0) {
    return { status: 'loading', message: null };
  }
  if (!municipioNome.value) {
    return { status: 'error', message: 'Municipio do estabelecimento nao identificado.' };
  }

  try {
    const ufGeoJson = geoStore.getMunicipiosGeoByUF(uf.value);
    const geoJson = buildHealthRegionGeoJson({
      ufGeoJson,
      localidades: geoStore.localidades,
      uf: uf.value,
      regiaoId: regiaoId.value,
    });
    const hasSelectedMunicipio = geoJson.features.some(
      (feature) => Number(feature.properties?.id) === municipioId.value,
    );
    if (!hasSelectedMunicipio) {
      throw new Error('Municipio do CNPJ ausente no GeoJSON da regiao de saude.');
    }
    return { status: 'ready', geoJson, message: null };
  } catch (error) {
    return { status: 'error', message: error.message };
  }
});

const mapName = computed(() =>
  `cnpj-territory-${uf.value}-${String(regiaoId.value).replace(/[^a-zA-Z0-9_-]/g, '-')}`,
);

const riskCssVariable = computed(() => ({
  'risk-low': '--risk-low',
  'risk-medium': '--risk-medium',
  'risk-high': '--risk-high',
  'risk-critical': '--risk-critical',
}[props.riskClass] ?? '--text-muted'));

watch(
  territoryState,
  (state) => {
    if (state.status !== 'ready') return;
    registerMap(mapName.value, state.geoJson);
    mapKey.value += 1;
  },
  { immediate: true },
);

const chartOption = computed(() => {
  if (territoryState.value.status !== 'ready') return {};

  const isDark = themeStore.isDark;
  const theme = chartTheme.value;
  const riskColor = getComputedStyle(document.documentElement)
    .getPropertyValue(riskCssVariable.value)
    .trim();
  const neutralArea = isDark ? 'rgba(230, 237, 243, 0.08)' : 'rgba(30, 41, 59, 0.08)';
  const neutralBorder = isDark ? 'rgba(230, 237, 243, 0.28)' : 'rgba(30, 41, 59, 0.24)';

  const data = territoryState.value.geoJson.features.map((feature) => {
    const id = Number(feature.properties?.id);
    const selected = id === municipioId.value;
    return {
      name: feature.properties?.name,
      selected,
      itemStyle: {
        areaColor: selected ? riskColor : neutralArea,
        borderColor: selected ? riskColor : neutralBorder,
        borderWidth: selected ? 2.2 : 0.7,
        opacity: selected ? 0.92 : 1,
      },
      emphasis: {
        disabled: true,
      },
    };
  });

  return {
    backgroundColor: 'transparent',
    animationDuration: 350,
    tooltip: {
      trigger: 'item',
      confine: true,
      backgroundColor: theme.tooltip,
      borderColor: theme.tooltipBorder,
      borderWidth: 1,
      padding: [7, 9],
      textStyle: { color: theme.tooltipText, fontFamily: 'Inter, sans-serif', fontSize: 11 },
      formatter: ({ data: item }) => item?.selected
        ? `${formatTitleCase(item.name)}<br><span style="opacity:.72">Município do estabelecimento</span>`
        : formatTitleCase(item?.name ?? ''),
    },
    series: [{
      type: 'map',
      map: mapName.value,
      nameProperty: 'name',
      roam: false,
      silent: false,
      selectedMode: false,
      layoutCenter: ['50%', '50%'],
      layoutSize: '94%',
      aspectScale: 1,
      label: { show: false },
      emphasis: { disabled: true, label: { show: false } },
      itemStyle: { areaColor: neutralArea, borderColor: neutralBorder, borderWidth: 0.7 },
      data,
    }],
  };
});
</script>

<template>
  <section class="territory-card">
    <div v-if="territoryState.status === 'ready'" class="territory-map">
      <VChart :key="mapKey" class="territory-chart" :option="chartOption" autoresize />
    </div>
    <div v-else-if="territoryState.status === 'loading'" class="territory-state">
      <i class="pi pi-spin pi-spinner" />
      <span>Carregando mapa</span>
    </div>
    <div v-else class="territory-state territory-state--error" v-tooltip.bottom="territoryState.message">
      <i class="pi pi-exclamation-circle" />
      <span>Mapa indisponível</span>
    </div>
  </section>
</template>

<style scoped>
.territory-card {
  display: flex;
  flex-direction: column;
  width: 180px;
  min-width: 180px;
  min-height: 146px;
  overflow: hidden;
  border-right: 1px solid var(--card-border);
  background: color-mix(in srgb, var(--text-muted) 3%, var(--establishment-header-bg));
}

.territory-map {
  min-height: 144px;
  flex: 1;
}

.territory-chart {
  width: 100%;
  height: 100%;
  min-height: 144px;
}

.territory-state {
  display: flex;
  min-height: 144px;
  flex: 1;
  align-items: center;
  justify-content: center;
  gap: 0.4rem;
  color: var(--text-muted);
  font-size: 0.67rem;
}

.territory-state--error {
  color: var(--risk-medium);
}
</style>
