<script setup>
import { computed, onMounted, ref } from 'vue';
import { useAnalyticsStore } from '@/stores/analytics';
import { useFormatting } from '@/composables/useFormatting';
import { useChartTheme } from '@/config/chartTheme';
import { useThemeStore } from '@/stores/theme';
import { useFilterStore } from '@/stores/filters';
import { storeToRefs } from 'pinia';
import { use, registerMap } from 'echarts/core';
import { CanvasRenderer } from 'echarts/renderers';
import { MapChart } from 'echarts/charts';
import { TooltipComponent, VisualMapComponent } from 'echarts/components';
import VChart from 'vue-echarts';

use([CanvasRenderer, MapChart, TooltipComponent, VisualMapComponent]);

const analyticsStore = useAnalyticsStore();
const filterStore = useFilterStore();
const { resultadoSentinelaUF, isLoading } = storeToRefs(analyticsStore);
const { formatBRL, formatPercent } = useFormatting();
const { chartTheme } = useChartTheme();
const themeStore = useThemeStore();
const mapAreaColor   = computed(() => themeStore.isDark ? 'rgba(255,255,255,0.07)' : 'rgba(0,0,0,0.04)');
const mapBorderColor = computed(() => themeStore.isDark ? 'rgba(255,255,255,0.18)' : 'rgba(0,0,0,0.15)');
const hoverColor     = computed(() => themeStore.isDark ? 'rgba(255,255,255,0.15)' : 'rgba(0,0,0,0.15)');

const mapReady = ref(false);

onMounted(async () => {
  const geo = await fetch('/geo/brasil-uf.json').then(r => r.json());
  registerMap('brasil-uf', geo);
  mapReady.value = true;
});

const mapData = computed(() =>
  resultadoSentinelaUF.value.map(d => ({
    name: d.uf,
    value: d.percValSemComp ?? 0,
    valSemComp: d.valSemComp ?? 0,
    cnpjs: d.cnpjs ?? 0,
  }))
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
        if (!params.data) return params.name;
        const d = params.data;
        return `
          <div style="font-weight:700;font-size:14px;margin-bottom:8px;">${params.name}</div>
          <div style="display:flex;flex-direction:column;gap:4px;font-size:12px;">
            <div>% s/ Comp: <strong>${formatPercent(d.value)}</strong></div>
            <div>Valor s/ Comp: <strong>${formatBRL(d.valSemComp)}</strong></div>
            <div>CNPJs: <strong>${(d.cnpjs ?? 0).toLocaleString('pt-BR')}</strong></div>
          </div>`;
      },
    },
    visualMap: {
      min: 0,
      max: 40,
      show: false,
      inRange: {
        color: ['#fef9c3', '#fde68a', '#fca5a5', '#ef4444', '#7f1d1d'],
      },
    },
    series: [{
      type: 'map',
      map: 'brasil-uf',
      nameProperty: 'UF',
      roam: false,
      layoutCenter: ['50%', '45%'],
      layoutSize: '95%',
      aspectScale: 1,
      emphasis: {
        label: { show: true, fontSize: 10, fontWeight: 700, color: '#fff' },
        itemStyle: { areaColor: hoverColor.value, borderColor: themeStore.isDark ? 'rgba(255,255,255,0.4)' : 'rgba(0,0,0,0.3)', borderWidth: 1.5 },
      },
      select: { disabled: true },
      label: {
        show: true,
        fontSize: 9,
        fontWeight: 600,
        color: c.text,
        fontFamily: 'Inter, sans-serif',
      },
      itemStyle: {
        borderColor: mapBorderColor.value,
        borderWidth: 1,
        areaColor: mapAreaColor.value,
      },
      data: mapData.value,
    }],
  };
});

const onClick = (params) => {
  if (params.data?.name) {
    filterStore.selectedUF = params.data.name;
  }
};
</script>

<template>
  <div class="chart-section" :class="{ 'is-refreshing': isLoading }">
    <div class="chart-header">
      <i class="pi pi-map"></i>
      <h3>MAPA DE RISCO — UFs</h3>
      <div class="spacer"></div>
    </div>
    <div class="chart-wrapper">
      <VChart
        v-if="mapReady"
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
