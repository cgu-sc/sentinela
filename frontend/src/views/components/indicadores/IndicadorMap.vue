<script setup>
/**
 * Mapa coroplético de indicadores de risco.
 *
 * Modo UF: exibe municípios coloridos por % farmácias CRÍTICAS.
 * Modo Nacional: exibe UFs coloridas por % farmácias CRÍTICAS (agregado).
 *
 * Diferente de MunicipalMap.vue, este componente é inteiramente prop-based
 * e não lê dados do analyticsStore.
 */
import { computed, watch, ref, onMounted, nextTick } from 'vue';
import { useGeoStore } from '@/stores/geo';
import { useChartTheme } from '@/config/chartTheme';
import { useThemeStore } from '@/stores/theme';
import { MAP_VISUAL_SCALE } from '@/config/colors.js';
import { use, registerMap } from 'echarts/core';
import { CanvasRenderer } from 'echarts/renderers';
import { MapChart } from 'echarts/charts';
import { TooltipComponent, VisualMapComponent } from 'echarts/components';
import VChart from 'vue-echarts';

use([CanvasRenderer, MapChart, TooltipComponent, VisualMapComponent]);

const props = defineProps({
  /** Array de { id_ibge7, municipio, uf, total_cnpjs, total_critico, pct_critico } */
  mapData: { type: Array, default: () => [] },
  /** UF ativa (do filterStore). 'Todos' ou null = modo nacional (UF-level). */
  activeUf: { type: String, default: null },
  isLoading: { type: Boolean, default: false },
  /** Label do indicador para o título */
  indicadorLabel: { type: String, default: 'Indicador' },
});

const geoStore = useGeoStore();
const { chartTheme } = useChartTheme();
const themeStore = useThemeStore();

// ── Escala de cores (reutiliza MAP_VISUAL_SCALE do projeto) ───────────────────
const activeScale = computed(() => MAP_VISUAL_SCALE[themeStore.isDark ? 'dark' : 'light']);
function getRiskPiece(perc) {
  return activeScale.value.find(p => (p.min == null || perc >= p.min) && (p.max == null || perc < p.max))
    ?? activeScale.value[activeScale.value.length - 1];
}

const mapAreaColor = computed(() => themeStore.isDark ? 'rgba(255,255,255,0.07)' : 'rgba(0,0,0,0.04)');
const mapBorderColor = computed(() => themeStore.isDark ? 'rgba(255,255,255,0.15)' : 'rgba(0,0,0,0.15)');
const hoverBorder = computed(() => `${themeStore.tokens.primary}B3`);

// ── Modo de exibição ──────────────────────────────────────────────────────────
const isNational = computed(() => !props.activeUf || props.activeUf === 'Todos');

// ── GeoJSON nacional (para modo nacional) ────────────────────────────────────
const nationalMapReady = ref(false);
const chartRef = ref(null);

onMounted(async () => {
  if (!window.__brasilUfRegistered) {
    const geo = await fetch('/geo/brasil-uf.json').then(r => r.json());
    registerMap('brasil-uf', geo);
    window.__brasilUfRegistered = true;
  }
  nationalMapReady.value = true;
  // Aguarda o DOM atualizar e força resize para que ECharts meça as dimensões corretas
  await nextTick();
  chartRef.value?.chart?.resize();
  mapKey.value++;
});

// ── GeoJSON municipal (para modo UF) ─────────────────────────────────────────
const mapKey = ref(0);
watch(
  () => props.activeUf,
  (uf) => {
    if (!uf || uf === 'Todos') return;
    const geo = geoStore.getMunicipiosGeoByUF(uf);
    if (geo) {
      registerMap(`municipios-${uf}`, geo);
      mapKey.value++;
    }
  },
  { immediate: true },
);

// ── Lookup de dados por id_ibge7 ──────────────────────────────────────────────
const dataByIbge7 = computed(() => {
  const m = new Map();
  for (const row of props.mapData) {
    if (row.id_ibge7) m.set(Number(row.id_ibge7), row);
  }
  return m;
});

// ── Lookup de dados agregados por UF (modo nacional) ─────────────────────────
const dataByUf = computed(() => {
  const m = new Map();
  for (const row of props.mapData) {
    if (!row.uf) continue;
    const existing = m.get(row.uf);
    if (!existing) {
      m.set(row.uf, { uf: row.uf, total_cnpjs: row.total_cnpjs, total_critico: row.total_critico });
    } else {
      existing.total_cnpjs += row.total_cnpjs;
      existing.total_critico += row.total_critico;
    }
  }
  // Recalcula pct_critico após agregação
  m.forEach(v => {
    v.pct_critico = v.total_cnpjs > 0 ? (v.total_critico / v.total_cnpjs) * 100 : 0;
  });
  return m;
});

// ── Nome do mapa registrado ───────────────────────────────────────────────────
const mapName = computed(() => isNational.value ? 'brasil-uf' : `municipios-${props.activeUf}`);

// ── Dados para o ECharts ──────────────────────────────────────────────────────
const echartsMapData = computed(() => {
  if (isNational.value) {
    // Modo nacional: um item por UF
    return [...dataByUf.value.values()].map(d => {
      const perc = d.pct_critico ?? 0;
      const piece = getRiskPiece(perc);
      return {
        name: d.uf,
        value: perc,
        total_cnpjs: d.total_cnpjs,
        total_critico: d.total_critico,
        hasData: d.total_cnpjs > 0,
        itemStyle: { areaColor: d.total_cnpjs > 0 ? piece.color : mapAreaColor.value },
        emphasis: { itemStyle: { areaColor: piece.color, borderColor: piece.borderColor, borderWidth: 1.5 } },
      };
    });
  }

  // Modo UF: um item por município
  const geo = geoStore.getMunicipiosGeoByUF(props.activeUf);
  if (!geo) return [];

  return geo.features.map(f => {
    const ibge7 = Number(f.properties.id);
    const d = dataByIbge7.value.get(ibge7);
    const hasData = !!d && d.total_cnpjs > 0;
    const perc = hasData ? (d.pct_critico ?? 0) : 0;
    const piece = getRiskPiece(perc);
    const baseColor = hasData ? piece.color : mapAreaColor.value;

    return {
      name: f.properties.name,
      ibge7,
      value: hasData ? perc : null,
      municipio: d?.municipio ?? f.properties.name,
      total_cnpjs: d?.total_cnpjs ?? 0,
      total_critico: d?.total_critico ?? 0,
      hasData,
      itemStyle: { areaColor: baseColor },
      emphasis: {
        itemStyle: {
          areaColor: hasData ? piece.color : baseColor,
          borderColor: hasData ? piece.borderColor : hoverBorder.value,
          borderWidth: 1.5,
        },
      },
    };
  });
});

// ── Chart option ──────────────────────────────────────────────────────────────
const chartOption = computed(() => {
  const c = chartTheme.value;
  return {
    backgroundColor: c.bg,
    tooltip: {
      trigger: 'item',
      confine: true,
      backgroundColor: c.tooltip,
      borderColor: c.border,
      borderWidth: 1,
      padding: [12, 16],
      textStyle: { color: c.text, fontFamily: 'Inter, sans-serif', fontSize: 12 },
      formatter: (params) => {
        const d = params.data;
        if (!d) return '';
        const label = isNational.value ? (d.name ?? '—') : (d.municipio ?? d.name ?? '—');
        if (!d.hasData || d.total_cnpjs === 0) {
          return `<div style="font-weight:600;font-size:13px;margin-bottom:6px;">${label}</div>
                  <div style="font-size:11px;opacity:0.7;">Sem dados para este indicador</div>`;
        }
        const pctFmt = (d.value ?? 0).toFixed(1) + '%';
        return `
          <div style="font-weight:600;font-size:13px;margin-bottom:8px;">${label}</div>
          <div style="display:flex;flex-direction:column;gap:4px;font-size:12px;">
            <div>% Farmácias Críticas: <strong>${pctFmt}</strong></div>
            <div>Farmácias Críticas: <strong>${d.total_critico ?? 0}</strong> / ${d.total_cnpjs ?? 0}</div>
          </div>`;
      },
    },
    series: [{
      type: 'map',
      map: mapName.value,
      nameProperty: 'name',
      roam: true,
      scaleLimit: { min: 0.8, max: 15 },
      layoutSize: '95%',
      selectedMode: false,
      label: { show: false },
      itemStyle: { borderColor: mapBorderColor.value, borderWidth: 0.5, areaColor: mapAreaColor.value },
      data: echartsMapData.value,
    }],
  };
});

watch(() => themeStore.isDark, () => mapKey.value++);
</script>

<template>
  <div class="ind-map-card" :class="{ 'is-refreshing': isLoading }">
    <div class="map-header">
      <i class="pi pi-map" />
      <h3>CONCENTRAÇÃO CRÍTICA — {{ indicadorLabel?.toUpperCase() }}</h3>
      <span class="map-subtitle">% de farmácias CRÍTICAS por {{ isNational ? 'UF' : 'município' }}</span>
    </div>

    <!-- v-show em vez de v-if: mantém o elemento no DOM para ECharts medir dimensões -->
    <div v-show="!isNational || nationalMapReady" class="map-wrapper">
      <VChart
        ref="chartRef"
        :key="mapKey"
        class="echart"
        :option="chartOption"
        autoresize
      />
    </div>
    <div v-show="isNational && !nationalMapReady" class="map-loading">
      <i class="pi pi-spin pi-spinner" />
    </div>
  </div>
</template>

<style scoped>
.ind-map-card {
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  border-radius: 12px;
  display: flex;
  flex-direction: column;
  overflow: hidden;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.08);
  transition: opacity 0.3s ease;
}

.ind-map-card.is-refreshing {
  opacity: 0.5;
  pointer-events: none;
}

.map-header {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  padding: 0.75rem 1.25rem;
  border-bottom: 1px solid var(--tabs-border);
  flex-shrink: 0;
}

.map-header i {
  color: var(--primary-color);
  font-size: 1rem;
  flex-shrink: 0;
}

.map-header h3 {
  margin: 0;
  font-size: 0.78rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--text-color);
  opacity: 0.8;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.map-subtitle {
  font-size: 0.68rem;
  color: var(--text-muted);
  margin-left: auto;
  white-space: nowrap;
  flex-shrink: 0;
}

.map-wrapper {
  height: 400px;
}

.echart {
  width: 100%;
  height: 100%;
}

.map-loading {
  height: 400px;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--text-muted);
  font-size: 1.5rem;
}
</style>
