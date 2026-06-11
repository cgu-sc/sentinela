<script setup>
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { use, registerMap } from 'echarts/core';
import { MapChart } from 'echarts/charts';
import { TooltipComponent, VisualMapComponent } from 'echarts/components';
import { CanvasRenderer } from 'echarts/renderers';
import VChart from 'vue-echarts';
import { useGeoStore } from '@/stores/geo';
import { useThemeStore } from '@/stores/theme';
import { useChartTheme } from '@/config/chartTheme';
import { MAP_VISUAL_SCALE } from '@/config/colors';

use([CanvasRenderer, MapChart, TooltipComponent, VisualMapComponent]);

const props = defineProps({
  mapData: { type: Array, default: () => [] },
  activeUf: { type: String, default: null },
  selectedIbge7: { type: Number, default: null },
  selectedRegiao: { type: String, default: null },
  isLoading: { type: Boolean, default: false },
  sourceNotice: { type: String, default: null },
});

const emit = defineEmits(['select-uf', 'select-municipio', 'back-to-uf', 'clear-geography']);

const geoStore = useGeoStore();
const themeStore = useThemeStore();
const { chartTheme } = useChartTheme();
const chartRef = ref(null);
const containerRef = ref(null);
const nationalMapReady = ref(false);
const mapKey = ref(0);
const zoomLevel = ref(1);
const containerWidth = ref(800);
const containerHeight = ref(400);
let resizeObserver = null;

const isNational = computed(() => !props.activeUf || props.activeUf === 'Todos');
const hasRegionScope = computed(
  () => Boolean(props.selectedRegiao && props.selectedRegiao !== 'Todos')
);
const backButtonLabel = computed(() => hasRegionScope.value ? props.activeUf : 'Brasil');
const backButtonTooltip = computed(
  () => hasRegionScope.value
    ? `Voltar ao mapa de ${props.activeUf}`
    : 'Voltar ao mapa do Brasil'
);

function handleBackClick() {
  emit(hasRegionScope.value ? 'back-to-uf' : 'clear-geography');
}
const activeScale = computed(() => MAP_VISUAL_SCALE[themeStore.isDark ? 'dark' : 'light']);
const mapAreaColor = computed(() => themeStore.isDark ? 'rgba(255,255,255,0.07)' : 'rgba(0,0,0,0.04)');
const mapBorderColor = computed(() => themeStore.isDark ? 'rgba(255,255,255,0.18)' : 'rgba(0,0,0,0.18)');

function getScalePiece(value, maxValue) {
  const normalized = maxValue > 0 ? (value / maxValue) * 100 : 0;
  return activeScale.value.find(
    piece => (piece.min == null || normalized >= piece.min)
      && (piece.max == null || normalized < piece.max)
  ) ?? activeScale.value[activeScale.value.length - 1];
}

function formatCurrency(value) {
  return Number(value || 0).toLocaleString('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  });
}

function formatInteger(value) {
  return Number(value || 0).toLocaleString('pt-BR');
}

function formatPercent(value) {
  return `${(Number(value || 0) * 100).toLocaleString('pt-BR', {
    minimumFractionDigits: 1,
    maximumFractionDigits: 1,
  })}%`;
}

const dataByIbge7 = computed(() => {
  const result = new Map();
  for (const row of props.mapData) {
    result.set(Number(row.id_ibge7), row);
  }
  return result;
});

const dataByUf = computed(() => {
  const result = new Map();
  for (const row of props.mapData) {
    const current = result.get(row.uf) ?? {
      uf: row.uf,
      total_farmacias: 0,
      valor_incompativel: 0,
      casos_observados: 0,
    };
    current.total_farmacias += Number(row.total_farmacias || 0);
    current.valor_incompativel += Number(row.valor_incompativel || 0);
    current.casos_observados += Number(row.casos_observados || 0);
    result.set(row.uf, current);
  }
  return result;
});

const mapTotalValue = computed(() =>
  props.mapData.reduce((total, row) => total + Number(row.valor_incompativel || 0), 0)
);

const summaryItems = computed(() => [
  {
    label: 'Valor dos CPFs < 50 anos',
    value: formatCurrency(mapTotalValue.value),
  },
  {
    label: 'CPFs únicos',
    value: formatInteger(
      props.mapData.reduce((total, row) => total + Number(row.casos_observados || 0), 0)
    ),
  },
  {
    label: 'Farmácias',
    value: formatInteger(
      props.mapData.reduce((total, row) => total + Number(row.total_farmacias || 0), 0)
    ),
  },
]);

const visibleGeo = computed(() => {
  if (isNational.value) return null;
  const ufGeo = geoStore.getMunicipiosGeoByUF(props.activeUf);
  if (!ufGeo) return null;

  const regiao = props.selectedRegiao && props.selectedRegiao !== 'Todos'
    ? String(props.selectedRegiao)
    : null;
  if (!regiao) return ufGeo;

  const ids = new Set(
    geoStore.localidades
      .filter(localidade =>
        localidade.sg_uf === props.activeUf
        && String(localidade.id_regiao_saude) === regiao
      )
      .map(localidade => Number(localidade.id_ibge7))
  );

  return {
    type: 'FeatureCollection',
    features: ufGeo.features.filter(feature => ids.has(Number(feature.properties.id))),
  };
});

const mapName = computed(() => {
  if (isNational.value) return 'target-brasil-uf';
  const regiao = props.selectedRegiao && props.selectedRegiao !== 'Todos'
    ? `-${props.selectedRegiao}`
    : '';
  return `target-municipios-${props.activeUf}${regiao}`;
});

const geoAspectRatio = computed(() => {
  if (isNational.value) return 4500 / 3800;

  const features = visibleGeo.value?.features ?? [];
  if (!features.length) return 1.5;

  let minLon = Infinity;
  let maxLon = -Infinity;
  let minLat = Infinity;
  let maxLat = -Infinity;

  function visitCoordinates(coordinates) {
    if (!Array.isArray(coordinates)) return;
    if (
      coordinates.length >= 2
      && typeof coordinates[0] === 'number'
      && typeof coordinates[1] === 'number'
    ) {
      const [lon, lat] = coordinates;
      minLon = Math.min(minLon, lon);
      maxLon = Math.max(maxLon, lon);
      minLat = Math.min(minLat, lat);
      maxLat = Math.max(maxLat, lat);
      return;
    }
    coordinates.forEach(visitCoordinates);
  }

  features.forEach(feature => visitCoordinates(feature.geometry?.coordinates));

  const width = maxLon - minLon;
  const height = maxLat - minLat;
  return Number.isFinite(width) && Number.isFinite(height) && height > 0
    ? width / height
    : 1.5;
});

const optimalLayoutSize = computed(() => {
  const containerAspect = containerWidth.value / containerHeight.value;
  const geoAspect = geoAspectRatio.value;

  if (geoAspect > containerAspect) {
    return `${Math.round((geoAspect / containerAspect) * 94)}%`;
  }

  const availableBoost = Math.min(1.02, 1 + Math.max(0, containerAspect / geoAspect - 1) * 0.06);
  return `${Math.round(94 * availableBoost)}%`;
});

watch(
  [visibleGeo, mapName],
  ([geo, name]) => {
    if (!geo || isNational.value) return;
    registerMap(name, geo);
    mapKey.value += 1;
  },
  { immediate: true }
);

const chartData = computed(() => {
  if (isNational.value) {
    const rows = [...dataByUf.value.values()];
    const maxValue = Math.max(0, ...rows.map(row => row.valor_incompativel));
    const totalValue = rows.reduce((total, row) => total + row.valor_incompativel, 0);

    return rows.map(row => {
      const piece = getScalePiece(row.valor_incompativel, maxValue);
      return {
        name: row.uf,
        ...row,
        participacao: totalValue > 0 ? row.valor_incompativel / totalValue : 0,
        hasData: row.total_farmacias > 0,
        itemStyle: { areaColor: piece.color },
        emphasis: {
          itemStyle: {
            areaColor: piece.color,
            borderColor: piece.borderColor,
            borderWidth: 2,
          },
        },
      };
    });
  }

  const features = visibleGeo.value?.features ?? [];
  const visibleRows = features
    .map(feature => dataByIbge7.value.get(Number(feature.properties.id)))
    .filter(Boolean);
  const maxValue = Math.max(0, ...visibleRows.map(row => Number(row.valor_incompativel || 0)));

  return features.map(feature => {
    const ibge7 = Number(feature.properties.id);
    const row = dataByIbge7.value.get(ibge7);
    const value = Number(row?.valor_incompativel || 0);
    const hasData = Boolean(row && row.total_farmacias > 0);
    const piece = getScalePiece(value, maxValue);
    const selected = props.selectedIbge7 === ibge7;

    return {
      name: feature.properties.name,
      ibge7,
      municipio: row?.municipio ?? feature.properties.name,
      uf: props.activeUf,
      total_farmacias: Number(row?.total_farmacias || 0),
      valor_incompativel: value,
      casos_observados: Number(row?.casos_observados || 0),
      participacao: Number(row?.participacao_uf || 0),
      hasData,
      itemStyle: {
        areaColor: hasData ? piece.color : mapAreaColor.value,
        borderColor: selected ? themeStore.tokens.primary : mapBorderColor.value,
        borderWidth: selected ? 2.5 : 0.6,
      },
      emphasis: {
        itemStyle: {
          areaColor: hasData ? piece.color : mapAreaColor.value,
          borderColor: hasData ? piece.borderColor : themeStore.tokens.primary,
          borderWidth: 2,
        },
      },
    };
  });
});

const chartOption = computed(() => {
  const colors = chartTheme.value;
  return {
    backgroundColor: colors.bg,
    tooltip: {
      trigger: 'item',
      confine: true,
      backgroundColor: colors.tooltip,
      borderColor: colors.tooltipBorder,
      borderWidth: 1,
      padding: [12, 16],
      textStyle: {
        color: colors.tooltipText,
        fontFamily: 'Inter, sans-serif',
        fontSize: 12,
      },
      formatter: ({ data }) => {
        if (!data) return '';
        const label = isNational.value ? data.name : data.municipio;
        if (!data.hasData) {
          return `<div style="color:${colors.tooltipText};font-weight:600">${label}</div>
            <div style="margin-top:6px;opacity:.7">Sem ocorrências no recorte atual</div>`;
        }
        return `<div style="min-width:210px;color:${colors.tooltipText}">
          <div style="font-weight:600;font-size:13px;margin-bottom:8px;padding-bottom:6px;border-bottom:1px solid ${colors.tooltipBorder}">${label}</div>
          <div style="display:flex;justify-content:space-between;gap:20px;margin-bottom:5px"><span style="opacity:.7">Valor</span><strong>${formatCurrency(data.valor_incompativel)}</strong></div>
          <div style="display:flex;justify-content:space-between;gap:20px;margin-bottom:5px"><span style="opacity:.7">CPFs únicos</span><strong>${formatInteger(data.casos_observados)}</strong></div>
          <div style="display:flex;justify-content:space-between;gap:20px;margin-bottom:5px"><span style="opacity:.7">Farmácias</span><strong>${formatInteger(data.total_farmacias)}</strong></div>
          <div style="display:flex;justify-content:space-between;gap:20px"><span style="opacity:.7">Participação</span><strong>${formatPercent(data.participacao)}</strong></div>
        </div>`;
      },
    },
    visualMap: { show: false },
    series: [{
      type: 'map',
      map: mapName.value,
      nameProperty: isNational.value ? 'UF' : 'name',
      roam: 'move',
      zoom: zoomLevel.value,
      scaleLimit: { min: 1, max: 15 },
      layoutCenter: ['50%', '50%'],
      layoutSize: optimalLayoutSize.value,
      aspectScale: 1,
      selectedMode: false,
      label: { show: false },
      emphasis: { label: { show: false } },
      itemStyle: {
        areaColor: mapAreaColor.value,
        borderColor: mapBorderColor.value,
        borderWidth: 1,
      },
      data: chartData.value,
    }],
  };
});

function handleMapClick({ data }) {
  if (!data?.hasData) return;
  if (isNational.value) {
    emit('select-uf', data.name);
    return;
  }
  if (!data.ibge7) return;
  emit('select-municipio', data.ibge7 === props.selectedIbge7 ? null : data.ibge7);
}

function handleZoom(delta) {
  const next = zoomLevel.value + delta;
  if (next >= 1 && next <= 15) zoomLevel.value = Number(next.toFixed(1));
}

watch(
  [() => themeStore.isDark, () => props.activeUf],
  () => {
    zoomLevel.value = 1;
    mapKey.value += 1;
  }
);

onMounted(async () => {
  if (!window.__targetBrasilUfRegistered) {
    const response = await fetch('/geo/brasil-uf.json');
    if (!response.ok) throw new Error(`Falha ao carregar GeoJSON nacional: HTTP ${response.status}`);
    registerMap('target-brasil-uf', await response.json());
    window.__targetBrasilUfRegistered = true;
  }
  nationalMapReady.value = true;

  if (containerRef.value) {
    resizeObserver = new ResizeObserver(entries => {
      for (const entry of entries) {
        containerWidth.value = entry.contentRect.width;
        containerHeight.value = entry.contentRect.height;
      }
      requestAnimationFrame(() => chartRef.value?.chart?.resize());
    });
    resizeObserver.observe(containerRef.value);
    containerWidth.value = containerRef.value.clientWidth;
    containerHeight.value = containerRef.value.clientHeight;
  }
  await nextTick();
  chartRef.value?.chart?.resize();
});

onBeforeUnmount(() => resizeObserver?.disconnect());
</script>

<template>
  <section class="target-map-card" :class="{ 'is-refreshing': isLoading }">
    <div class="map-header">
      <div class="map-heading">
        <i class="pi pi-map" />
        <div>
          <h2>Mapa do alvo</h2>
          <span>Valor dos CPFs abaixo de 50 anos por {{ isNational ? 'UF' : 'município' }}</span>
        </div>
      </div>

      <button
        v-if="!isNational"
        type="button"
        class="back-button"
        v-tooltip.bottom="backButtonTooltip"
        @click="handleBackClick"
      >
        <i class="pi pi-arrow-left" />
        <span>{{ backButtonLabel }}</span>
      </button>

      <div class="map-summary">
        <div v-for="item in summaryItems" :key="item.label" class="summary-item">
          <span>{{ item.label }}</span>
          <strong>{{ item.value }}</strong>
        </div>
      </div>
    </div>

    <div
      v-if="sourceNotice || (!mapData.length && !isLoading)"
      class="map-empty"
    >
      <i class="pi pi-map-marker" />
      <span>{{ sourceNotice || 'Nenhum município encontrado para o alvo no recorte atual.' }}</span>
    </div>

    <div v-else ref="containerRef" class="map-wrapper">
      <VChart
        v-if="!isNational || nationalMapReady"
        ref="chartRef"
        :key="mapKey"
        class="target-map"
        :option="chartOption"
        autoresize
        @click="handleMapClick"
      />

      <div class="map-controls">
        <button type="button" @click="handleZoom(0.5)" v-tooltip.bottom="'Aumentar zoom'">
          <i class="pi pi-plus" />
        </button>
        <button type="button" @click="handleZoom(-0.5)" v-tooltip.bottom="'Diminuir zoom'">
          <i class="pi pi-minus" />
        </button>
        <button type="button" @click="zoomLevel = 1" v-tooltip.bottom="'Reiniciar zoom'">
          <i class="pi pi-refresh" />
        </button>
      </div>
    </div>
  </section>
</template>

<style scoped>
.target-map-card {
  height: calc(40vh + 42px);
  min-height: 28rem;
  overflow: hidden;
  display: flex;
  flex-direction: column;
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  border-radius: 8px;
  box-shadow: var(--shadow-sm);
  transition: opacity 0.2s ease;
}

.target-map-card.is-refreshing {
  opacity: 0.72;
}

.map-header {
  min-height: 4.5rem;
  display: flex;
  align-items: center;
  gap: 1rem;
  padding: 0.75rem 1rem;
  border-bottom: 1px solid var(--card-border);
}

.map-heading {
  min-width: 15rem;
  display: flex;
  align-items: center;
  gap: 0.75rem;
}

.map-heading > i {
  width: 2rem;
  height: 2rem;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  border-radius: 8px;
  background: color-mix(in srgb, var(--primary-color) 12%, transparent);
  color: var(--primary-color);
}

.map-heading h2 {
  margin: 0;
  color: var(--text-color-85);
  font-size: 0.82rem;
  font-weight: 600;
  text-transform: uppercase;
}

.map-heading span {
  display: block;
  margin-top: 0.15rem;
  color: var(--text-muted);
  font-size: 0.7rem;
}

.back-button,
.map-controls button {
  border: 1px solid var(--card-border);
  background: color-mix(in srgb, var(--card-bg) 92%, var(--primary-color) 8%);
  color: var(--text-muted);
  cursor: pointer;
}

.back-button {
  height: 2rem;
  padding: 0 0.65rem;
  display: inline-flex;
  align-items: center;
  gap: 0.4rem;
  border-radius: 6px;
  font-size: 0.7rem;
  font-weight: 500;
}

.back-button:hover,
.map-controls button:hover {
  border-color: color-mix(in srgb, var(--primary-color) 42%, var(--card-border));
  color: var(--primary-color);
}

.back-button:focus,
.map-controls button:focus {
  outline: none;
  box-shadow: none;
}

.back-button:focus-visible,
.map-controls button:focus-visible {
  outline: 1px solid var(--primary-color);
  outline-offset: 2px;
}

.map-summary {
  margin-left: auto;
  display: flex;
  align-items: stretch;
}

.summary-item {
  min-width: 7.5rem;
  padding: 0 0.85rem;
  display: flex;
  flex-direction: column;
  justify-content: center;
  gap: 0.15rem;
  border-left: 1px solid var(--card-border);
}

.summary-item span {
  color: var(--text-muted);
  font-size: 0.62rem;
  text-transform: uppercase;
}

.summary-item strong {
  color: var(--text-color-85);
  font-size: 0.78rem;
  font-weight: 600;
  white-space: nowrap;
}

.map-wrapper {
  position: relative;
  flex: 1;
  min-height: 0;
  overflow: hidden;
}

.target-map {
  width: 100%;
  height: 100%;
}

.map-controls {
  position: absolute;
  right: 0.85rem;
  bottom: 0.85rem;
  display: flex;
  overflow: hidden;
  border-radius: 6px;
  box-shadow: var(--shadow-sm);
}

.map-controls button {
  width: 2rem;
  height: 2rem;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border-radius: 0;
  border-right-width: 0;
}

.map-controls button:last-child {
  border-right-width: 1px;
}

.map-controls i {
  font-size: 0.72rem;
}

.map-empty {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 0.65rem;
  color: var(--text-muted);
}

.map-empty i {
  color: var(--primary-color);
  font-size: 1.4rem;
}

.map-empty span {
  font-size: 0.78rem;
}
</style>
