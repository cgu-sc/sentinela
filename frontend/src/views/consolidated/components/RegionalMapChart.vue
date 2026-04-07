<script setup>
import { computed, watch, ref, nextTick, onMounted } from 'vue';
import { useAnalyticsStore } from '@/stores/analytics';
import { useGeoStore } from '@/stores/geo';
import { useFormatting } from '@/composables/useFormatting';
import { useChartTheme } from '@/config/chartTheme';
import { useThemeStore } from '@/stores/theme';
import { useFilterStore as useGlobalFilterStore } from '@/stores/filters';
import { MAP_VISUAL_SCALE, RISK_COLORS } from '@/config/colors.js';
import { use, registerMap } from 'echarts/core';
import { CanvasRenderer } from 'echarts/renderers';
import { MapChart, ScatterChart } from 'echarts/charts';
import { TooltipComponent, VisualMapComponent, GeoComponent } from 'echarts/components';
import VChart from 'vue-echarts';

use([CanvasRenderer, MapChart, ScatterChart, TooltipComponent, VisualMapComponent, GeoComponent]);

const props = defineProps({
  /** Payload do endpoint /analytics/regional — { municipios, farmacias } */
  regionalData: { type: Object, default: null },
  /** Dados geo da farmácia atual — { sg_uf, no_regiao_saude, no_municipio } */
  geoData: { type: Object, required: true },
  /** id_ibge7 selecionado pelo filtro cruzado (número, ou null) */
  selectedMunicipioId: { type: Number, default: null },
});

const emit = defineEmits(['select-municipio']);

const geoStore     = useGeoStore();
const themeStore   = useThemeStore();
const filterStore  = useGlobalFilterStore();
const { formatBRL, formatPercent } = useFormatting();
const { chartTheme } = useChartTheme();

// ── Cores reativas ao tema ───────────────────────────────────────────────────
const mapAreaColor   = computed(() => themeStore.isDark ? 'rgba(255,255,255,0.07)' : 'rgba(0,0,0,0.04)');
const mapBorderColor = computed(() => themeStore.isDark ? 'rgba(255,255,255,0.18)' : 'rgba(0,0,0,0.15)');
const hoverColor     = computed(() => `${themeStore.tokens.primary}4D`);
const hoverBorder    = computed(() => `${themeStore.tokens.primary}B3`);

// ── Risk helpers ──────────────────────────────────────────────────────────────
function getRiskPointColor(classificacao) {
  const c = (classificacao ?? '').toUpperCase();
  if (c.includes('CRITICO')) return RISK_COLORS.CRITICAL;
  if (c.includes('ALTO'))    return RISK_COLORS.HIGH;
  if (c.includes('MEDIO'))   return RISK_COLORS.MEDIUM;
  return RISK_COLORS.LOW;
}

// ── Clustering por grade geográfica ──────────────────────────────────────────
let _currentZoom = 1;
const RISK_PRIORITY = { CRITICO: 4, ALTO: 3, MEDIO: 2, BAIXO: 1 };

function highestRiskColor(group) {
  let best = { priority: 0, color: RISK_COLORS.LOW };
  for (const p of group) {
    const c   = (p.classificacao_risco ?? '').toUpperCase();
    const key = Object.keys(RISK_PRIORITY).find(k => c.includes(k)) ?? 'BAIXO';
    if (RISK_PRIORITY[key] > best.priority) best = { priority: RISK_PRIORITY[key], color: getRiskPointColor(p.classificacao_risco) };
  }
  return best.color;
}

function getSymbolSize(data, zoom) {
  const count = data.count ?? 1;
  const z = Math.max(zoom, 1);
  if (count === 1) return 7 * Math.min(Math.pow(z, 0.35), 2.5);
  return Math.min((10 + Math.sqrt(count) * 3) * Math.min(Math.pow(z, 0.15), 1.5), 40);
}

function clusterPoints(rawPoints, zoom) {
  if (zoom > 14) return rawPoints;
  const threshold = 0.015 / Math.max(zoom * 0.8, 1);
  const grid = new Map();
  for (const p of rawPoints) {
    const key = `${Math.round(p.value[0] / threshold)},${Math.round(p.value[1] / threshold)}`;
    if (!grid.has(key)) grid.set(key, []);
    grid.get(key).push(p);
  }
  const result = [];
  for (const group of grid.values()) {
    if (group.length === 1) {
      result.push(group[0]);
    } else {
      const count  = group.length;
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
          color: 'rgba(15, 23, 42, 0.9)',
          fontSize: 10,
          fontWeight: '900',
        },
      });
    }
  }
  return result;
}

const onGeoRoam = () => {
  const chart = chartRef.value?.chart;
  if (!chart) return;
  const opt = chart.getOption();
  _currentZoom = opt?.geo?.[0]?.zoom ?? 1;
  chart.setOption({
    series: [{}, {
      data: clusterPoints(scatterData.value, _currentZoom),
      symbolSize: (_, params) => getSymbolSize(params.data, _currentZoom),
    }],
  });
};

// ── GeoJSON filtrado para a região ──────────────────────────────────────────
/**
 * Nome canônico do mapa registrado no ECharts para esta região.
 * Baseia-se na UF + nome da região para ser único e estável.
 */
const mapName = computed(() => {
  const uf     = props.geoData?.sg_uf ?? 'XX';
  const regiao = (props.geoData?.no_regiao_saude ?? 'default')
    .toLowerCase()
    .replace(/\s+/g, '-')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '');
  return `regiao-${uf}-${regiao}`;
});

/**
 * Localidades da região: fonte de verdade para id_ibge7 ↔ feature do GeoJSON.
 * O GeoJSON usa `feature.properties.id` como código IBGE (7 dígitos).
 */
const regiaoLocalidades = computed(() => {
  const regiao = props.geoData?.no_regiao_saude;
  const uf     = props.geoData?.sg_uf;
  if (!regiao || !uf) return [];
  return geoStore.localidades.filter(l => l.no_regiao_saude === regiao && l.sg_uf === uf);
});

/** Set de id_ibge7 (Number) dos municípios da região — usado para filtrar features do GeoJSON */
const regiaoIbge7Set = computed(() => new Set(
  regiaoLocalidades.value.map(l => Number(l.id_ibge7)).filter(Boolean)
));

/** Array de id_ibge7 da região — usado para buscar estabelecimentos */
const regiaoIbge7s = computed(() => regiaoLocalidades.value.map(l => l.id_ibge7).filter(Boolean));

/** mapKey força re-render do VChart ao trocar de região */
const mapKey = ref(0);
watch(mapKey, () => { _currentZoom = 1; });

/**
 * Registra o GeoJSON filtrado (apenas features da região) no ECharts
 * usando id_ibge7 (feature.properties.id) como chave — sem depender de nome.
 */
watch(
  [() => props.geoData?.sg_uf, () => props.geoData?.no_regiao_saude],
  ([uf]) => {
    if (!uf) return;
    const fullGeo = geoStore.getMunicipiosGeoByUF(uf);
    if (!fullGeo) return;

    const ibge7s = regiaoIbge7Set.value;
    const features = fullGeo.features.filter(f => ibge7s.has(Number(f.properties.id)));
    if (!features.length) return;

    registerMap(mapName.value, { type: 'FeatureCollection', features });
    mapKey.value++;
  },
  { immediate: true }
);

// ── mapData: polígonos coloridos por percValSemComp ─────────────────────────
/** Lookup id_ibge7 → dados financeiros do município (fonte: backend) */
const munDataByIbge7 = computed(() => {
  const map = new Map();
  for (const m of (props.regionalData?.municipios ?? [])) {
    if (m.id_ibge7) map.set(Number(m.id_ibge7), m);
  }
  return map;
});

/** id_ibge7 da farmácia atual (município destacado por padrão) */
const norm = (s) => (s ?? '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-z0-9]/g, '');

/** id_ibge7 da farmácia atual (município destacado por padrão) */
const currentIbge7 = computed(() => {
  const target = norm(props.geoData?.no_municipio);
  const loc = regiaoLocalidades.value.find(l => norm(l.no_municipio) === target);
  return loc ? Number(loc.id_ibge7) : null;
});

const mapData = computed(() => {
  const uf = props.geoData?.sg_uf;
  if (!uf) return [];
  const fullGeo = geoStore.getMunicipiosGeoByUF(uf);
  if (!fullGeo) return [];
  
  const ibge7s    = regiaoIbge7Set.value;
  const targetId  = props.selectedMunicipioId;
  
  // Normalização robusta de nomes para garantir o "match" entre tabela e GeoJSON
  const normalize = (s) => s?.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').trim() || '';

  // Encontra o nome do município alvo uma única vez para o loop
  const targetMun = props.regionalData?.municipios?.find(m => Number(m.id_ibge7) === Number(targetId))?.municipio;
  const targetMunNorm = targetMun ? normalize(targetMun) : null;

  return fullGeo.features
    .filter(f => ibge7s.has(Number(f.properties.id)))
    .map(f => {
      const ibge7      = Number(f.properties.id);
      const munData    = munDataByIbge7.value.get(ibge7);
      const isCurrent  = currentIbge7.value && ibge7 === currentIbge7.value;
      const mNome      = munData?.municipio ?? f.properties.name;
      const mNomeNorm  = normalize(mNome);
      
      const isSelected = targetId && (
        Number(ibge7) === Number(targetId) || 
        (targetMunNorm && mNomeNorm === targetMunNorm)
      );
      const isDimmed   = targetId && !isSelected;

      return {
        id:         ibge7,
        ibge7:      ibge7,
        name:       f.properties.name,
        value:      munData?.percValSemComp ?? 0,
        municipio:  mNome,
        valSemComp: munData?.valSemComp ?? 0,
        totalMov:   munData?.totalMov ?? 0,
        cnpjs:      munData?.qtd_farmacias ?? 0,
        isSelected,
        isCurrent,
        isDimmed,
        itemStyle: isSelected ? { 
                     borderColor: themeStore.tokens.primary, 
                     borderWidth: 2,
                     shadowBlur: 10,
                     shadowColor: themeStore.tokens.primary
                   } :
                   isDimmed   ? { 
                     areaColor: themeStore.isDark ? '#1e1e1e' : '#f0f0f0', 
                     opacity: 1 
                   } : {}
      };
    });
});

// ── scatterData: estabelecimentos da região ──────────────────────────────────
const scatterData = computed(() => {
  const points = [];
  for (const ibge7 of regiaoIbge7s.value) {
    const lista = geoStore.estabelecimentosPorIbge7.get(Number(ibge7)) ?? [];
    for (const e of lista) {
      points.push({
        value:              [e.lon, e.lat],
        cnpj:               e.cnpj,
        razao_social:       e.razao_social,
        score_risco:        e.score_risco,
        classificacao_risco: e.classificacao_risco,
        percValSemComp:     e.percValSemComp,
        totalMov:           e.totalMov,
        valSemComp:         e.valSemComp,
        itemStyle: { color: getRiskPointColor(e.classificacao_risco) },
      });
    }
  }
  return points;
});

// ── Chart option ─────────────────────────────────────────────────────────────
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
        if (params.seriesType === 'scatter') {
          const d = params.data;
          if (d.isCluster) {
            return `
              <div style="font-weight:700;font-size:13px;margin-bottom:4px;">Cluster</div>
              <div style="font-size:12px;">${d.count} farmácias próximas</div>
              <div style="font-size:11px;opacity:0.6;margin-top:4px;">Dê zoom para ver individualmente</div>`;
          }
          const score   = d.score_risco != null ? d.score_risco.toFixed(1) : '—';
          const risco   = d.classificacao_risco ?? '—';
          const cor     = getRiskPointColor(d.classificacao_risco);
          return `
            <div style="font-weight:700;font-size:13px;margin-bottom:6px;">${d.razao_social ?? d.cnpj}</div>
            <div style="font-size:11px;opacity:0.7;margin-bottom:8px;">${d.cnpj}</div>
            <div style="display:flex;flex-direction:column;gap:4px;font-size:12px;">
              <div>Score de Risco: <strong style="color:${cor}">${score} — ${risco}</strong></div>
              <div style="margin-top:4px;border-top:1px solid rgba(255,255,255,0.1);padding-top:4px;display:flex;flex-direction:column;gap:2px;">
                <div>Valor Total: <strong>${formatBRL(d.totalMov)}</strong></div>
                <div>Valor s/ Comp: <strong>${formatBRL(d.valSemComp)}</strong></div>
                <div>% s/ Comprovação: <strong style="color:${cor}">${formatPercent(d.percValSemComp)}</strong></div>
              </div>
            </div>`;
        }
        // Polígono do município
        if (!params.data?.municipio) return `
          <div style="font-weight:700;font-size:14px;margin-bottom:4px;">${params.name}</div>
          <div style="font-size:11px;opacity:0.6;">Sem dados financeiros</div>`;
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
      roam: false,
      zoom: 1,
      layoutSize: '95%',
      emphasis: {
        label: { show: false },
        itemStyle: { areaColor: hoverColor.value, borderColor: hoverBorder.value, borderWidth: 1.5 },
      },
      selectedMode: 'single',
      select: {
        label: { show: false },
        itemStyle: {
          borderColor: themeStore.tokens.primary,
          borderWidth: 3,
          shadowColor: themeStore.tokens.primary,
          shadowBlur: 15,
        }
      },
      label: { show: false },
      itemStyle: {
        borderColor: mapBorderColor.value,
        borderWidth: 0.5,
        areaColor: mapAreaColor.value,
      },
      regions: mapData.value
        .filter(d => d.isCurrent && !props.selectedMunicipioId)
        .map(d => ({
          name: d.name,
          itemStyle: { borderColor: themeStore.tokens.primary, borderWidth: 2 },
          emphasis: { itemStyle: { borderColor: themeStore.tokens.primary, borderWidth: 2 } }
        })),
    },
    visualMap: {
      min: 0,
      max: 100,
      show: false,
      inRange: { 
        color: MAP_VISUAL_SCALE,
        opacity: 1 
      },
      seriesIndex: 0,
    },
    series: [
      {
        type: 'map',
        map: mapName.value,
        nameProperty: 'name',
        geoIndex: 0,
        roam: false,
        emphasis: { label: { show: false } },
        select: {
          itemStyle: {
            borderColor: themeStore.tokens.primary,
            borderWidth: 3,
            shadowColor: themeStore.tokens.primary,
            shadowBlur: 15,
          }
        },
        label: { show: false },
        data: mapData.value,
      },
      {
        type: 'scatter',
        coordinateSystem: 'geo',
        geoIndex: 0,
        data: filterStore.showMapaPoints ? clusterPoints(scatterData.value, _currentZoom) : [],
        symbolSize: (_, params) => getSymbolSize(params.data, _currentZoom),
        itemStyle: {
          borderColor: 'rgba(15, 23, 42, 0.7)',
          borderWidth: 1.2,
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

// ── Sincronização: Tabela -> Mapa (Seleção e Hover) ───────────────────
const chartRef = ref(null);
let _prevSelectedName = null;
let _prevHoveredName  = null;

// Sincroniza a Seleção (Click na Tabela)
watch(
  () => [props.selectedMunicipioId, mapKey.value],
  async ([ibgeId]) => {
    await nextTick();
    const chart = chartRef.value?.chart;
    if (!chart) return;

    // Limpa estado anterior (Select persistente)
    if (_prevSelectedName) {
      chart.dispatchAction({ type: 'unselect', seriesIndex: 0, name: _prevSelectedName });
      _prevSelectedName = null;
    }

    if (!ibgeId) return;

    const match = mapData.value.find(d => Number(d.id) === Number(ibgeId) || Number(d.ibge7) === Number(ibgeId));
    if (match?.name) {
      _prevSelectedName = match.name;
      chart.dispatchAction({ type: 'select', seriesIndex: 0, name: match.name });
    }
  },
  { immediate: true }
);

// Sincroniza o Hover (Passar mouse na Tabela)
watch(
  () => filterStore.hoveredMunicipioName,
  async (municipioName) => {
    await nextTick();
    const chart = chartRef.value?.chart;
    if (!chart) return;

    if (_prevHoveredName) {
      chart.dispatchAction({ type: 'downplay', seriesIndex: 0, name: _prevHoveredName });
      _prevHoveredName = null;
    }

    if (municipioName) {
      // Normalização robusta para bater com os nomes da tabela (que podem vir com espaços/acentos)
      const target = municipioName.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');
      const match = mapData.value.find(d => d.municipio?.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '') === target);
      
      if (match?.name) {
        _prevHoveredName = match.name;
        chart.dispatchAction({ type: 'highlight', seriesIndex: 0, name: match.name });
      }
    }
  }
);

const onClick = (params) => {
  if (params.seriesType === 'scatter') return; // Ignora clique nos pontos
  const data = params.data;
  if (data?.id) {
    emit('select-municipio', data.id, data.municipio);
  } else {
    const match = mapData.value.find(d => d.name === params.name);
    if (match) emit('select-municipio', match.id, match.municipio);
  }
};
</script>

<template>
  <div class="regional-map-card">
    <div class="map-header">
      <i class="pi pi-map"></i>
      <span>Mapa da Região</span>
      <span class="region-name">{{ geoData?.no_regiao_saude }}</span>
      <div class="header-actions">
        <button 
          class="toggle-btn" 
          :class="{ 'is-active': filterStore.showMapaPoints }"
          title="Alternar visibilidade dos CNPJs"
          @click="filterStore.showMapaPoints = !filterStore.showMapaPoints"
        >
          <i :class="filterStore.showMapaPoints ? 'pi pi-eye' : 'pi pi-eye-slash'" />
          <span>{{ filterStore.showMapaPoints ? 'Ocultar' : 'Exibir' }} CNPJs</span>
        </button>
      </div>
    </div>
    <div class="map-body">
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
.regional-map-card {
  display: flex;
  flex-direction: column;
  flex: 1;
  min-height: 400px;
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  border-radius: 12px;
  overflow: hidden;
  box-shadow: 0 4px 15px rgba(0, 0, 0, 0.1);
}

.toggle-btn {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  background: color-mix(in srgb, var(--primary-color) 12%, transparent);
  border: 1px solid color-mix(in srgb, var(--primary-color) 25%, transparent);
  color: var(--primary-color);
  padding: 0.28rem 0.8rem;
  border-radius: 100px;
  font-size: 0.65rem;
  font-weight: 700;
  cursor: pointer;
  transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
  text-transform: uppercase;
  letter-spacing: 0.02em;
}

.toggle-btn i {
  font-size: 0.75rem;
  transition: transform 0.2s ease;
}

.toggle-btn:hover {
  background: color-mix(in srgb, var(--primary-color) 20%, transparent);
  border-color: var(--primary-color);
  transform: translateY(-1px);
  box-shadow: 0 4px 12px color-mix(in srgb, var(--primary-color) 15%, transparent);
}

.toggle-btn:hover i {
  transform: scale(1.1);
}

.toggle-btn:not(.is-active) {
  opacity: 0.65;
  filter: grayscale(0.4);
}

.toggle-btn:not(.is-active):hover {
  opacity: 1;
  filter: none;
}

.map-header {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.75rem 1rem;
  border-bottom: 1px solid var(--tabs-border);
  font-size: 0.75rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--text-color);
  flex-shrink: 0;
}

.map-header i {
  color: var(--primary-color);
  font-size: 0.85rem;
}

.region-name {
  margin-left: auto;
  font-size: 0.68rem;
  font-weight: 600;
  color: var(--primary-color);
  background: color-mix(in srgb, var(--primary-color) 10%, transparent);
  padding: 0.15rem 0.55rem;
  border-radius: 20px;
  text-transform: none;
  letter-spacing: 0;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  max-width: 55%;
}

.map-body {
  flex: 1;
  min-height: 400px;
  display: flex;
  flex-direction: column;
}

.echart {
  flex: 1;
  min-height: 400px; /* garante clientHeight > 0 no init; autoresize ajusta ao tamanho real */
  cursor: pointer;
}
</style>
