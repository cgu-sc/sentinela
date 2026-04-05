<script setup>
import { computed, watch, ref } from 'vue';
import { useAnalyticsStore } from '@/stores/analytics';
import { useGeoStore } from '@/stores/geo';
import { useFilterStore } from '@/stores/filters';
import { useFormatting } from '@/composables/useFormatting';
import { useChartTheme } from '@/config/chartTheme';
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

const mapKey = ref(0);

// Registra o mapa da UF quando a seleção muda
watch(
  () => filterStore.selectedUF,
  (uf) => {
    if (!uf || uf === 'Todos') return;
    const geo = geoStore.getMunicipiosGeoByUF(uf);
    if (geo) {
      registerMap(`municipios-${uf}`, geo);
      mapKey.value++; // força re-render do VChart
    }
  },
  { immediate: true }
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

const maxVal = computed(() =>
  Math.max(...mapData.value.map(d => d.value), 1)
);

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
      max: maxVal.value,
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
      emphasis: {
        label: { show: false },
        itemStyle: { areaColor: 'var(--primary-color)', borderColor: '#fff', borderWidth: 1.5 },
      },
      select: { disabled: true },
      label: { show: false },
      itemStyle: {
        borderColor: c.muted,
        borderWidth: 0.5,
        areaColor: '#d1d5db',
      },
      data: mapData.value,
    }],
  };
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
  border: 1px solid var(--sidebar-border);
  border-radius: 12px;
  box-shadow: 0 2px 8px rgba(0,0,0,0.06);
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
