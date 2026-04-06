<script setup>
import { computed, watch, ref, nextTick } from 'vue';
import { useAnalyticsStore } from '@/stores/analytics';
import { useGeoStore } from '@/stores/geo';
import { useFilterStore } from '@/stores/filters';
import { useFormatting } from '@/composables/useFormatting';
import { useChartTheme } from '@/config/chartTheme';
import { useThemeStore } from '@/stores/theme';
import { storeToRefs } from 'pinia';
import { use, registerMap } from 'echarts/core';
import { CanvasRenderer } from 'echarts/renderers';
import { MapChart } from 'echarts/charts';
import { TooltipComponent, VisualMapComponent } from 'echarts/components';
import VChart from 'vue-echarts';

use([CanvasRenderer, MapChart, TooltipComponent, VisualMapComponent]);

const analyticsStore = useAnalyticsStore();
const geoStore = useGeoStore();
const filterStore = useFilterStore();
const { resultadoMunicipios, isLoading } = storeToRefs(analyticsStore);
const { formatBRL, formatPercent } = useFormatting();
const { chartTheme } = useChartTheme();
const themeStore = useThemeStore();
const mapAreaColor   = computed(() => themeStore.isDark ? 'rgba(255,255,255,0.07)' : 'rgba(0,0,0,0.04)');
const mapBorderColor = computed(() => themeStore.isDark ? 'rgba(255,255,255,0.18)' : 'rgba(0,0,0,0.15)');
const hoverColor     = computed(() => themeStore.isDark ? 'rgba(255,255,255,0.15)' : 'rgba(0,0,0,0.15)');
const hoverBorder    = computed(() => themeStore.isDark ? 'rgba(255,255,255,0.4)' : 'rgba(0,0,0,0.3)');

const mapKey = ref(0);

// Registra o mapa da UF quando a seleção muda
watch(
  () => filterStore.selectedUF,
  (uf) => {
    if (!uf || uf === 'Todos') return;
    const geo = geoStore.getMunicipiosGeoByUF(uf);
    if (geo) {
      registerMap(`municipios-${uf}`, geo);
      mapKey.value++;
    }
  },
  { immediate: true }
);

// Força re-render ao mudar município ou região (atualiza zoom)
watch(
  () => [filterStore.selectedMunicipio, filterStore.selectedRegiaoSaude],
  () => { mapKey.value++; }
);

const mapName = computed(() => `municipios-${filterStore.selectedUF}`);

// Lookup id_ibge7 → nome do GeoJSON (para usar nameProperty: 'name')
const idToGeoName = computed(() => {
  const geo = geoStore.getMunicipiosGeoByUF(filterStore.selectedUF);
  if (!geo) return {};
  const map = {};
  geo.features.forEach(f => { map[String(f.properties.id)] = f.properties.name; });
  return map;
});

const mapData = computed(() =>
  resultadoMunicipios.value
    .filter(d => d.id_ibge7 && idToGeoName.value[String(d.id_ibge7)])
    .map(d => ({
      name: idToGeoName.value[String(d.id_ibge7)],
      value: d.percValSemComp ?? 0,
      municipio: d.municipio,
      valSemComp: d.valSemComp ?? 0,
      cnpjs: d.cnpjs ?? 0,
    }))
);


// Extrai coords de uma feature (Polygon ou MultiPolygon)
function featureCoords(feature) {
  if (feature.geometry.type === 'Polygon') return feature.geometry.coordinates[0];
  if (feature.geometry.type === 'MultiPolygon')
    return feature.geometry.coordinates.reduce((a, b) => a[0].length >= b[0].length ? a : b)[0];
  return [];
}

// Bounding box → { center, zoom }
function bboxToView(lons, lats) {
  if (!lons.length) return null;
  const minLon = Math.min(...lons), maxLon = Math.max(...lons);
  const minLat = Math.min(...lats), maxLat = Math.max(...lats);
  const span = Math.max(maxLon - minLon, maxLat - minLat);
  const zoom = span > 3 ? 4 : span > 1.5 ? 5 : span > 0.7 ? 7 : span > 0.3 ? 9 : span > 0.1 ? 12 : 15;
  return { center: [(minLon + maxLon) / 2, (minLat + maxLat) / 2], zoom };
}

// Zoom num único município (pelo nome GeoJSON)
function getFeatureView(geoName) {
  const geo = geoStore.getMunicipiosGeoByUF(filterStore.selectedUF);
  if (!geo) return null;
  const feature = geo.features.find(f => f.properties.name === geoName);
  if (!feature) return null;
  const coords = featureCoords(feature);
  return bboxToView(coords.map(c => c[0]), coords.map(c => c[1]));
}

// Zoom na bounding box de todos os municípios de uma região de saúde
function getRegiaoView(regiao) {
  const geo = geoStore.getMunicipiosGeoByUF(filterStore.selectedUF);
  if (!geo) return null;
  const normalize = s => s?.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');
  const munNomes = geoStore.localidades
    .filter(l => l.no_regiao_saude === regiao && (filterStore.selectedUF === 'Todos' || l.sg_uf === filterStore.selectedUF))
    .map(l => normalize(l.no_municipio));
  const features = geo.features.filter(f => munNomes.includes(normalize(f.properties.name)));
  if (!features.length) return null;
  const allLons = [], allLats = [];
  features.forEach(f => {
    featureCoords(f).forEach(c => { allLons.push(c[0]); allLats.push(c[1]); });
  });
  const result = bboxToView(allLons, allLats);
  if (!result) return null;
  return { ...result, zoom: Math.max(result.zoom - 2, 4) };
}

const selectedGeoName = computed(() => {
  const sel = filterStore.selectedMunicipio;
  if (!sel || sel === 'Todos') return null;
  const nome = sel.split('|')[0];
  const match = mapData.value.find(d => d.municipio?.toLowerCase() === nome.toLowerCase());
  return match?.name ?? null;
});

const mapView = computed(() => {
  // 1. Município selecionado → zoom no município
  if (selectedGeoName.value) {
    const view = getFeatureView(selectedGeoName.value);
    if (view) return { center: view.center, zoom: view.zoom };
  }
  // 2. Região selecionada → zoom na região
  if (filterStore.selectedRegiaoSaude && filterStore.selectedRegiaoSaude !== 'Todos') {
    const view = getRegiaoView(filterStore.selectedRegiaoSaude);
    if (view) return { center: view.center, zoom: view.zoom };
  }
  // 3. Sem filtro → auto-fit na UF
  return {};
});

const chartOption = computed(() => {
  const c = chartTheme.value;
  return {
    backgroundColor: c.bg,
    tooltip: {
      trigger: 'item',
      backgroundColor: c.tooltip,
      borderColor: c.border,
      borderWidth: 1,
      padding: [12, 16],
      textStyle: { color: c.text, fontFamily: 'Inter, sans-serif', fontSize: 12 },
      formatter: (params) => {
        if (!params.data?.municipio) return `
          <div style="font-weight:700;font-size:14px;margin-bottom:4px;">${params.name}</div>
          <div style="font-size:11px;opacity:0.6;">Sem Estabelecimentos</div>`;
        const d = params.data;
        return `
          <div style="font-weight:700;font-size:14px;margin-bottom:8px;">${d.municipio}</div>
          <div style="display:flex;flex-direction:column;gap:4px;font-size:12px;">
            <div>% s/ Comp: <strong>${formatPercent(d.value)}</strong></div>
            <div>Valor s/ Comp: <strong>${formatBRL(d.valSemComp)}</strong></div>
            <div>CNPJs: <strong>${(d.cnpjs ?? 0).toLocaleString('pt-BR')}</strong></div>
          </div>`;
      },
    },
    visualMap: {
      min: 0,
      max: 100,
      show: false,
      inRange: {
        color: ['#fef9c3', '#fde68a', '#fca5a5', '#ef4444', '#7f1d1d'],
      },
    },
    series: [{
      type: 'map',
      map: mapName.value,
      nameProperty: 'name',
      roam: true,
      ...mapView.value,
      emphasis: {
        label: { show: false },
        itemStyle: { areaColor: hoverColor.value, borderColor: hoverBorder.value, borderWidth: 1.5 },
      },
      select: { disabled: true },
      label: { show: false },
      itemStyle: {
        borderColor: mapBorderColor.value,
        borderWidth: 0.5,
        areaColor: mapAreaColor.value,
      },
      data: mapData.value,
    }],
  };
});

const chartRef = ref(null);
let _prevGeoName = null;

watch(() => filterStore.hoveredMunicipioName, async (municipioName) => {
  await nextTick();
  const chart = chartRef.value?.chart;
  if (!chart) return;

  if (_prevGeoName) {
    chart.dispatchAction({ type: 'downplay', seriesIndex: 0, name: _prevGeoName });
    _prevGeoName = null;
  }

  if (municipioName) {
    const match = mapData.value.find(d => d.municipio?.toLowerCase() === municipioName.toLowerCase());
    if (match?.name) {
      _prevGeoName = match.name;
      chart.dispatchAction({ type: 'highlight', seriesIndex: 0, name: match.name });
    }
  }
});

const onClick = (params) => {
  if (!params.data?.municipio) return;
  filterStore.selectedMunicipio = `${params.data.municipio}|${filterStore.selectedUF}`;
};
</script>

<template>
  <div class="chart-section" :class="{ 'is-refreshing': isLoading }">
    <div class="chart-header">
      <i class="pi pi-map"></i>
      <h3>MAPA DE RISCO — {{ filterStore.selectedUF }}</h3>
      <div class="spacer"></div>
    </div>
    <div class="chart-wrapper">
      <VChart
        ref="chartRef"
        :key="mapKey"
        class="echart"
        :option="chartOption"
        autoresize
        @click="onClick"
      />
    </div>
  </div>
</template>

<style scoped>
.chart-section {
  display: flex;
  flex-direction: column;
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  border-radius: 12px;
  box-shadow: 0 1px 3px rgba(0,0,0,0.08), 0 1px 2px rgba(0,0,0,0.04);
  overflow: hidden;
}

.chart-header {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  padding: 1rem 1.5rem;
}

.chart-wrapper {
  height: 35vh;
  min-height: 400px;
}

.echart {
  width: 100%;
  height: 100%;
  cursor: pointer;
}

.spacer { flex: 1; }

.is-refreshing {
  opacity: 0.5;
  pointer-events: none;
}
</style>
