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
import { computed, watch, ref, onMounted, onBeforeUnmount, nextTick } from 'vue';
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
  /** ibge7 do município selecionado (controlado pelo pai) */
  selectedIbge7: { type: Number, default: null },
});

const emit = defineEmits(['select-municipio', 'select-uf']);

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

// ── Dimensões reais do container (ResizeObserver) ────────────────────────────
const containerRef = ref(null);
const containerWidth = ref(800);
const containerHeight = ref(400);
const zoomLevel = ref(1);
let _resizeObserver = null;

function handleZoom(delta) {
  const next = zoomLevel.value + delta;
  if (next >= 1 && next <= 15) {
    zoomLevel.value = Number(next.toFixed(1));
  }
}

onMounted(async () => {
  if (!window.__brasilUfRegistered) {
    const geo = await fetch('/geo/brasil-uf.json').then(r => r.json());
    registerMap('brasil-uf', geo);
    window.__brasilUfRegistered = true;
  }
  nationalMapReady.value = true;

  // Observa mudanças no tamanho do container para recalcular o layoutSize
  if (containerRef.value) {
    _resizeObserver = new ResizeObserver(entries => {
      for (const entry of entries) {
        containerWidth.value = entry.contentRect.width;
        containerHeight.value = entry.contentRect.height;
      }
    });
    _resizeObserver.observe(containerRef.value);
    containerWidth.value = containerRef.value.clientWidth;
    containerHeight.value = containerRef.value.clientHeight;
  }

  await nextTick();
  chartRef.value?.chart?.resize();
  mapKey.value++;
});

onBeforeUnmount(() => {
  _resizeObserver?.disconnect();
});

// ── GeoJSON municipal (para modo UF) ─────────────────────────────────────────
const mapKey = ref(0);
watch(
  () => props.activeUf,
  (uf) => {
    if (!uf || uf === 'Todos') {
      mapKey.value++;
      return;
    }
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
        emphasis: { itemStyle: { areaColor: piece.color, borderColor: piece.borderColor, borderWidth: 2 } },
      };
    });
  }

  // Modo UF: um item por município
  const geo = geoStore.getMunicipiosGeoByUF(props.activeUf);
  if (!geo) return [];

  const sel = props.selectedIbge7;
  const hasSel = sel != null;

  return geo.features.map(f => {
    const ibge7 = Number(f.properties.id);
    const d = dataByIbge7.value.get(ibge7);
    const hasData = !!d && d.total_cnpjs > 0;
    const perc = hasData ? (d.pct_critico ?? 0) : 0;
    const piece = getRiskPiece(perc);
    const isSelected = hasSel && ibge7 === sel;
    const dimmed = hasSel && !isSelected;
    const baseColor = hasData ? piece.color : mapAreaColor.value;

    return {
      name: f.properties.name,
      ibge7,
      value: hasData ? perc : null,
      municipio: d?.municipio ?? f.properties.name,
      total_cnpjs: d?.total_cnpjs ?? 0,
      total_critico: d?.total_critico ?? 0,
      hasData,
      itemStyle: {
        areaColor: baseColor,
        opacity: dimmed ? 0.8 : 1,
        borderColor: isSelected ? themeStore.tokens.primary : mapBorderColor.value,
        borderWidth: isSelected ? 2.5 : 0.5,
      },
      emphasis: {
        itemStyle: {
          areaColor: hasData ? piece.color : baseColor,
          borderColor: hasData ? piece.borderColor : hoverBorder.value,
          borderWidth: 2,
          opacity: 1,
        },
      },
    };
  });
});

// ── Bounding box geográfico do mapa ativo ─────────────────────────────────────
// Calcula a proporção real (largura/altura em graus) do GeoJSON da UF ou do Brasil.
// Isso permite calcular o layoutSize ideal: o maior possível sem deformar nem cortar.
const geoAspectRatio = computed(() => {
  if (isNational.value) {
    // Brasil: proporção conhecida (aproximada pelos limites do território)
    return 4500 / 3800; // ~leste-oeste vs norte-sul em km
  }
  const geo = geoStore.getMunicipiosGeoByUF(props.activeUf);
  if (!geo || !geo.features.length) return 1.5;

  let minLon = Infinity, maxLon = -Infinity, minLat = Infinity, maxLat = -Infinity;
  for (const feature of geo.features) {
    const coords = feature.geometry?.coordinates;
    if (!coords) continue;
    // Percorre todos os anéis de coordenadas (Polygon e MultiPolygon)
    const rings = feature.geometry.type === 'MultiPolygon'
      ? coords.flat(1)
      : coords;
    for (const ring of rings) {
      for (const [lon, lat] of ring) {
        if (lon < minLon) minLon = lon;
        if (lon > maxLon) maxLon = lon;
        if (lat < minLat) minLat = lat;
        if (lat > maxLat) maxLat = lat;
      }
    }
  }
  const geoW = maxLon - minLon;
  const geoH = maxLat - minLat;
  return geoH > 0 ? geoW / geoH : 1.5;
});

// Calcula o layoutSize ideal:
// O ECharts dimensiona o mapa com base no MENOR lado do container × layoutSize.
// Se o mapa é mais largo que o container, ele está limitado pela largura → precisamos
// compensar: layoutSize = (containerAspect / geoAspect) * 100%.
const optimalLayoutSize = computed(() => {
  const containerAspect = containerWidth.value / containerHeight.value;
  const geoAspect = geoAspectRatio.value;
  if (geoAspect > containerAspect) {
    // Mapa mais largo que container → limitado pela largura
    // Aumenta o layoutSize para compensar: usa a largura como fator dominante
    const factor = containerAspect / geoAspect;
    return `${Math.round((1 / factor) * 96)}%`;
  }
  // Mapa mais alto que container → limitado pela altura → layoutSize padrão
  return '96%';
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
      borderColor: c.tooltipBorder,
      borderWidth: 1,
      padding: [12, 16],
      textStyle: { color: c.tooltipText, fontFamily: 'Inter, sans-serif', fontSize: 12 },
      shadowBlur: 10,
      shadowColor: 'rgba(0,0,0,0.1)',
      formatter: (params) => {
        const d = params.data;
        if (!d) return '';
        const label = isNational.value ? (d.name ?? '—') : (d.municipio ?? d.name ?? '—');
        
        if (!d.hasData || d.total_cnpjs === 0) {
          return `
            <div style="padding: 2px; min-width: 140px; color: ${c.tooltipText}">
              <div style="font-weight: 700; font-size: 13px; margin-bottom: 8px;">${label}</div>
              <div style="font-size: 11px; opacity: 0.7; text-transform: uppercase;">Sem dados disponíveis</div>
            </div>
          `;
        }
        
        const pctFmt = (d.value ?? 0).toFixed(1) + '%';
        const color = (d.value ?? 0) > 15 ? '#ef4444' : c.tooltipText; // Agora usa o branco do tooltip escuro

        return `
          <div style="padding: 2px; min-width: 180px; color: ${c.tooltipText}">
            <div style="font-weight: 700; font-size: 13px; margin-bottom: 10px; border-bottom: 1px solid ${c.tooltipBorder}; padding-bottom: 6px;">
              ${label}
            </div>
            
            <div style="display: flex; justify-content: space-between; gap: 20px; margin-bottom: 4px; align-items: center;">
              <span style="opacity: 0.7; font-size: 10px; text-transform: uppercase;">% Críticas:</span>
              <strong style="color: ${color}; font-size: 13px;">${pctFmt}</strong>
            </div>
            
            <div style="display: flex; justify-content: space-between; gap: 20px; align-items: center;">
              <span style="opacity: 0.7; font-size: 10px; text-transform: uppercase;">Volume Crítico:</span>
              <span style="font-weight: 600;">${d.total_critico ?? 0} <small style="opacity: 0.5; font-weight: normal;">/ ${d.total_cnpjs ?? 0}</small></span>
            </div>
          </div>
        `;
      },
    },
    visualMap: {
      show: false,
      pieces: activeScale.value,
      seriesIndex: 0,
    },
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
      itemStyle: { borderColor: mapBorderColor.value, borderWidth: 2, areaColor: mapAreaColor.value },
      data: echartsMapData.value,
    }],
  };
});

watch(() => themeStore.isDark, () => mapKey.value++);

// ── Clique no mapa ────────────────────────────────────────────────────────────
function onMapClick(params) {
  if (!params?.data) return;
  const d = params.data;

  // No modo nacional, clicamos na UF para fazer drill-down
  if (isNational.value) {
    emit('select-uf', d.name);
    return;
  }

  // No modo UF, clicamos em municípios para filtrar a tabela abaixo
  const ibge7 = d.ibge7 ?? null;
  if (!ibge7) return;
  // Toggle: clicar no mesmo município desmarca
  const next = ibge7 === props.selectedIbge7 ? null : ibge7;
  emit('select-municipio', next, d.municipio ?? d.name ?? null);
}
</script>

<template>
  <div class="ind-map-card" :class="{ 'is-refreshing': isLoading }">
    <div class="map-header">
      <i class="pi pi-map" />
      <h3>{{ indicadorLabel?.toUpperCase() }}</h3>
      <span class="map-subtitle">% de farmácias CRÍTICAS por {{ isNational ? 'UF' : 'município' }}</span>
    </div>

    <!-- v-show em vez de v-if: mantém o elemento no DOM para ECharts medir dimensões -->
    <div v-show="!isNational || nationalMapReady" ref="containerRef" class="map-wrapper">
      <VChart
        ref="chartRef"
        :key="mapKey"
        class="echart"
        :option="chartOption"
        autoresize
        @click="onMapClick"
      />

      <!-- Controles de Zoom -->
      <div class="map-controls">
        <button class="zoom-btn" @click="handleZoom(0.5)" title="Aumentar Zoom">
          <i class="pi pi-plus" />
        </button>
        <button class="zoom-btn" @click="handleZoom(-0.5)" title="Diminuir Zoom">
          <i class="pi pi-minus" />
        </button>
        <button class="zoom-btn" @click="zoomLevel = 1" title="Resetar Zoom">
          <i class="pi pi-refresh" />
        </button>
      </div>
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
  height: 45vh;
  position: relative;
}

.echart {
  width: 100%;
  height: 100%;
}

.map-loading {
  height: 45vh;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--text-muted);
  font-size: 1.5rem;
}

/* ── CONTROLES DE ZOOM ── */
.map-controls {
  position: absolute;
  bottom: 1.5rem;
  right: 1.5rem;
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
  z-index: 10;
}

.zoom-btn {
  width: 32px;
  height: 32px;
  border-radius: 8px;
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  color: var(--text-color);
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  box-shadow: 0 2px 8px rgba(0,0,0,0.1);
  transition: all 0.2s ease;
}

.zoom-btn:hover {
  background: var(--bg-color);
  border-color: var(--primary-color);
  color: var(--primary-color);
  transform: translateY(-2px);
}

.zoom-btn i {
  font-size: 0.75rem;
}

:global(.dark-mode) .zoom-btn {
  background: rgba(45, 45, 45, 0.85);
  backdrop-filter: blur(4px);
}
</style>
