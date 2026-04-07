<script setup>
import { computed, watch, ref, nextTick } from 'vue';
import { useAnalyticsStore } from '@/stores/analytics';
import { useGeoStore } from '@/stores/geo';
import { useFilterStore } from '@/stores/filters';
import { useFormatting } from '@/composables/useFormatting';
import { useChartTheme } from '@/config/chartTheme';
import { useThemeStore } from '@/stores/theme';
import { MAP_VISUAL_SCALE, RISK_COLORS } from '@/config/colors.js';
import { storeToRefs } from 'pinia';
import { use, registerMap } from 'echarts/core';
import { CanvasRenderer } from 'echarts/renderers';
import { MapChart, ScatterChart } from 'echarts/charts';
import { TooltipComponent, VisualMapComponent, GeoComponent } from 'echarts/components';
import VChart from 'vue-echarts';

use([CanvasRenderer, MapChart, ScatterChart, TooltipComponent, VisualMapComponent, GeoComponent]);

const analyticsStore = useAnalyticsStore();
const geoStore = useGeoStore();
const filterStore = useFilterStore();
const { resultadoMunicipios, isLoading } = storeToRefs(analyticsStore);
const { formatBRL, formatPercent } = useFormatting();
const { chartTheme } = useChartTheme();
const themeStore = useThemeStore();
const mapAreaColor   = computed(() => themeStore.isDark ? 'rgba(255,255,255,0.07)' : 'rgba(0,0,0,0.04)');
const mapBorderColor = computed(() => themeStore.isDark ? 'rgba(255,255,255,0.18)' : 'rgba(0,0,0,0.15)');
const hoverColor     = computed(() => {
  const hex = themeStore.tokens.primary;
  return `${hex}4D`; // 30% opacidade
});
const hoverBorder    = computed(() => {
  const hex = themeStore.tokens.primary;
  return `${hex}B3`; // 70% opacidade
});

// ── Cor por classificação de risco ────────────────────────────────────────────
function getRiskPointColor(classificacao) {
  const c = (classificacao ?? '').toUpperCase();
  if (c.includes('CRITICO')) return RISK_COLORS.CRITICAL;
  if (c.includes('ALTO'))    return RISK_COLORS.HIGH;
  if (c.includes('MEDIO'))   return RISK_COLORS.MEDIUM;
  return RISK_COLORS.LOW;
}

const pointBorderColor = computed(() => themeStore.isDark ? 'rgba(255,255,255,0.6)' : 'rgba(0,0,0,0.4)');

// ── Zoom tracking — variável simples (não-reativa) ────────────────────────────
// Usar ref causaria chartOption a recomputar no zoom, resetando center/zoom do mapa.
// A atualização do scatter é feita imperativamente em onGeoRoam.
let _currentZoom = 1;

const onGeoRoam = () => {
  const chart = chartRef.value?.chart;
  if (!chart) return;
  const opt = chart.getOption();
  _currentZoom = opt?.geo?.[0]?.zoom ?? 1;
  // Atualiza apenas a série scatter sem re-renderizar o mapa inteiro
  chart.setOption({
    series: [{}, { data: clusterPoints(scatterData.value, _currentZoom) }],
  });
};

// ── Clustering por grade geográfica ───────────────────────────────────────────
// Agrupa pontos dentro da mesma célula de threshold × threshold graus.
// O(n) — adequado para dezenas de milhares de pontos.
const RISK_PRIORITY = { CRITICO: 4, ALTO: 3, MEDIO: 2, BAIXO: 1 };

function highestRiskColor(group) {
  let best = { priority: 0, color: RISK_COLORS.LOW };
  for (const p of group) {
    const c = (p.classificacao_risco ?? '').toUpperCase();
    const key = Object.keys(RISK_PRIORITY).find(k => c.includes(k)) ?? 'BAIXO';
    const priority = RISK_PRIORITY[key];
    if (priority > best.priority) best = { priority, color: getRiskPointColor(p.classificacao_risco) };
  }
  return best.color;
}

function clusterPoints(rawPoints, zoom) {
  const threshold = 0.08 / Math.max(zoom, 1);
  const grid = new Map();

  for (const p of rawPoints) {
    const cellKey = `${Math.round(p.value[0] / threshold)},${Math.round(p.value[1] / threshold)}`;
    if (!grid.has(cellKey)) grid.set(cellKey, []);
    grid.get(cellKey).push(p);
  }

  const result = [];
  for (const group of grid.values()) {
    if (group.length === 1) {
      result.push(group[0]);
    } else {
      const count = group.length;
      const avgLon = group.reduce((s, p) => s + p.value[0], 0) / count;
      const avgLat = group.reduce((s, p) => s + p.value[1], 0) / count;
      result.push({
        value: [avgLon, avgLat],
        count,
        isCluster: true,
        itemStyle: { color: highestRiskColor(group) },
        label: {
          show: true,
          formatter: String(count),
          color: '#fff',
          fontSize: 10,
          fontWeight: 'bold',
        },
      });
    }
  }
  return result;
}

// ── Pontos dos estabelecimentos filtrados pelos municípios visíveis ────────────
const scatterData = computed(() => {
  const { estabelecimentosPorIbge7 } = geoStore;
  const sel = selectedMunicipioNome.value;
  const regiao = filterStore.selectedRegiaoSaude;

  // Determina os id_ibge7 visíveis com base no filtro ativo
  let ibge7s;
  if (sel) {
    // Município selecionado → só ele
    const match = resultadoMunicipios.value.find(d => d.municipio?.toLowerCase() === sel);
    ibge7s = match?.id_ibge7 ? [match.id_ibge7] : [];
  } else if (regiao && regiao !== 'Todos') {
    // Região selecionada → todos os municípios da região
    ibge7s = geoStore.localidades
      .filter(l => l.no_regiao_saude === regiao && (filterStore.selectedUF === 'Todos' || l.sg_uf === filterStore.selectedUF))
      .map(l => l.id_ibge7)
      .filter(Boolean);
  } else {
    // UF inteira → todos os municípios com dados
    ibge7s = resultadoMunicipios.value.map(d => d.id_ibge7).filter(Boolean);
  }

  const points = [];
  for (const ibge7 of ibge7s) {
    const lista = estabelecimentosPorIbge7.get(Number(ibge7)) ?? [];
    for (const e of lista) {
      points.push({
        value: [e.lon, e.lat],
        cnpj: e.cnpj,
        razao_social: e.razao_social,
        score_risco: e.score_risco,
        classificacao_risco: e.classificacao_risco,
        itemStyle: { color: getRiskPointColor(e.classificacao_risco) },
      });
    }
  }
  return points;
});

const mapKey = ref(0);

// Reset zoom não-reativo quando filtros mudam (o mapa vai ser recriado via mapKey)
watch(mapKey, () => { _currentZoom = 1; });

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

const selectedMunicipioNome = computed(() => {
  const sel = filterStore.selectedMunicipio;
  if (!sel || sel === 'Todos') return null;
  return sel.split('|')[0].toLowerCase();
});

const mapData = computed(() => {
  const selNome = selectedMunicipioNome.value;
  return resultadoMunicipios.value
    .filter(d => d.id_ibge7 && idToGeoName.value[String(d.id_ibge7)])
    .map(d => {
      const geoName = idToGeoName.value[String(d.id_ibge7)];
      const isSelected = selNome && d.municipio?.toLowerCase() === selNome;
      const dimmed = selNome && !isSelected;
      return {
        name: geoName,
        value: d.percValSemComp ?? 0,
        municipio: d.municipio,
        valSemComp: d.valSemComp ?? 0,
        cnpjs: d.cnpjs ?? 0,
        ...(dimmed ? { itemStyle: { areaColor: mapAreaColor.value } } : {}),
      };
    });
});


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
        // Ponto de estabelecimento
        if (params.seriesType === 'scatter') {
          const d = params.data;
          if (d.isCluster) {
            return `
              <div style="font-weight:700;font-size:13px;margin-bottom:4px;">Cluster</div>
              <div style="font-size:12px;">${d.count} farmácias próximas</div>
              <div style="font-size:11px;opacity:0.6;margin-top:4px;">Dê zoom para ver individualmente</div>`;
          }
          const score = d.score_risco != null ? d.score_risco.toFixed(1) : '—';
          const risco = d.classificacao_risco ?? '—';
          const riscoCor = getRiskPointColor(d.classificacao_risco);
          return `
            <div style="font-weight:700;font-size:13px;margin-bottom:6px;">${d.razao_social ?? d.cnpj}</div>
            <div style="font-size:11px;opacity:0.7;margin-bottom:8px;">${d.cnpj}</div>
            <div style="display:flex;flex-direction:column;gap:3px;font-size:12px;">
              <div>Score de Risco: <strong style="color:${riscoCor}">${score} — ${risco}</strong></div>
            </div>`;
        }
        // Polígono do município
        if (selectedMunicipioNome.value && params.data?.municipio?.toLowerCase() !== selectedMunicipioNome.value) return '';
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
    geo: {
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
    },
    visualMap: {
      min: 0,
      max: 100,
      show: false,
      inRange: { color: MAP_VISUAL_SCALE },
      seriesIndex: 0,
    },
    series: [
      {
        type: 'map',
        map: mapName.value,
        nameProperty: 'name',
        geoIndex: 0,
        roam: true,
        emphasis: { label: { show: false } },
        select: { disabled: true },
        label: { show: false },
        data: mapData.value,
      },
      {
        type: 'scatter',
        coordinateSystem: 'geo',
        geoIndex: 0,
        data: clusterPoints(scatterData.value, _currentZoom),
        symbolSize: (_, params) => {
          const count = params.data.count ?? 1;
          return count === 1 ? 6 : Math.min(10 + Math.sqrt(count) * 4, 36);
        },
        itemStyle: {
          borderColor: pointBorderColor.value,
          borderWidth: 0.8,
          opacity: 0.85,
        },
        emphasis: {
          scale: true,
          itemStyle: { opacity: 1, borderWidth: 1.5 },
        },
        zlevel: 5,
      },
    ],
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
        @georoam="onGeoRoam"
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
