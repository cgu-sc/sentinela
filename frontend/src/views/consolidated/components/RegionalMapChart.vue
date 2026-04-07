<script setup>
import { computed, watch, ref, nextTick } from 'vue';
import { useGeoStore } from '@/stores/geo';
import { useFormatting } from '@/composables/useFormatting';
import { useChartTheme } from '@/config/chartTheme';
import { useThemeStore } from '@/stores/theme';
import { useFilterStore } from '@/stores/filters';
import { MAP_VISUAL_SCALE } from '@/config/colors.js';
import { use, registerMap } from 'echarts/core';
import { CanvasRenderer } from 'echarts/renderers';
import { MapChart } from 'echarts/charts';
import { TooltipComponent, VisualMapComponent } from 'echarts/components';
import VChart from 'vue-echarts';

use([CanvasRenderer, MapChart, TooltipComponent, VisualMapComponent]);

const props = defineProps({
  regionalData:       { type: Object, default: null },
  geoData:            { type: Object, required: true },
  selectedMunicipioId:{ type: Number, default: null },
});

const emit = defineEmits(['select-municipio']);

const geoStore    = useGeoStore();
const themeStore  = useThemeStore();
const filterStore = useFilterStore();
const { formatBRL, formatPercent } = useFormatting();
const { chartTheme } = useChartTheme();

const mapAreaColor   = computed(() => themeStore.isDark ? 'rgba(255,255,255,0.07)' : 'rgba(0,0,0,0.04)');
const mapBorderColor = computed(() => themeStore.isDark ? 'rgba(255,255,255,0.18)' : 'rgba(0,0,0,0.15)');
const hoverColor     = computed(() => `${themeStore.tokens.primary}4D`);
const hoverBorder    = computed(() => `${themeStore.tokens.primary}B3`);

// ── GeoJSON filtrado para a região ───────────────────────────────────────────
const mapName = computed(() => {
  const uf     = props.geoData?.sg_uf ?? 'XX';
  const regiao = (props.geoData?.no_regiao_saude ?? 'default')
    .toLowerCase().replace(/\s+/g, '-').normalize('NFD').replace(/[\u0300-\u036f]/g, '');
  return `regiao-${uf}-${regiao}`;
});

const regiaoLocalidades = computed(() => {
  const regiao = props.geoData?.no_regiao_saude;
  const uf     = props.geoData?.sg_uf;
  if (!regiao || !uf) return [];
  return geoStore.localidades.filter(l => l.no_regiao_saude === regiao && l.sg_uf === uf);
});

const regiaoIbge7Set = computed(() => new Set(
  regiaoLocalidades.value.map(l => Number(l.id_ibge7)).filter(Boolean)
));

const mapKey = ref(0);

watch(
  [() => props.geoData?.sg_uf, () => props.geoData?.no_regiao_saude],
  ([uf]) => {
    if (!uf) return;
    const fullGeo = geoStore.getMunicipiosGeoByUF(uf);
    if (!fullGeo) return;
    const ibge7s   = regiaoIbge7Set.value;
    const features = fullGeo.features.filter(f => ibge7s.has(Number(f.properties.id)));
    if (!features.length) return;
    registerMap(mapName.value, { type: 'FeatureCollection', features });
    mapKey.value++;
  },
  { immediate: true }
);

// ── mapData ──────────────────────────────────────────────────────────────────
const munDataByIbge7 = computed(() => {
  const map = new Map();
  for (const m of (props.regionalData?.municipios ?? [])) {
    if (m.id_ibge7) map.set(Number(m.id_ibge7), m);
  }
  return map;
});

const norm = (s) => (s ?? '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-z0-9]/g, '');

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

  const ibge7s   = regiaoIbge7Set.value;
  const targetId = props.selectedMunicipioId;

  const normalize    = (s) => s?.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').trim() || '';
  const targetMun    = props.regionalData?.municipios?.find(m => Number(m.id_ibge7) === Number(targetId))?.municipio;
  const targetMunNorm = targetMun ? normalize(targetMun) : null;

  return fullGeo.features
    .filter(f => ibge7s.has(Number(f.properties.id)))
    .map(f => {
      const ibge7     = Number(f.properties.id);
      const munData   = munDataByIbge7.value.get(ibge7);
      const isCurrent = currentIbge7.value && ibge7 === currentIbge7.value;
      const mNome     = munData?.municipio ?? f.properties.name;
      const mNomeNorm = normalize(mNome);

      const isSelected = targetId && (
        Number(ibge7) === Number(targetId) ||
        (targetMunNorm && mNomeNorm === targetMunNorm)
      );

      const perc  = munData?.percValSemComp ?? 0;
      const piece = getRiskPiece(perc);
      return {
        id:         ibge7,
        ibge7:      ibge7,
        name:       f.properties.name,
        value:      perc,
        municipio:  mNome,
        valSemComp: munData?.valSemComp ?? 0,
        totalMov:   munData?.totalMov ?? 0,
        cnpjs:      munData?.qtd_farmacias ?? 0,
        isSelected,
        isCurrent,
        select: { itemStyle: { areaColor: piece.color, borderColor: piece.borderColor, borderWidth: 2, shadowColor: piece.borderColor, shadowBlur: 6 } },
      };
    });
});

// ── Escala ativa conforme tema ────────────────────────────────────────────────
const activeScale = computed(() => MAP_VISUAL_SCALE[themeStore.isDark ? 'dark' : 'light']);

const getRiskPiece = (perc) =>
  activeScale.value.find(p =>
    (p.min == null || perc >= p.min) && (p.max == null || perc < p.max)
  ) ?? activeScale.value[activeScale.value.length - 1];

// ── chart option ─────────────────────────────────────────────────────────────
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
    visualMap: {
      show: false,
      pieces: activeScale.value,
      seriesIndex: 0,
    },
    series: [{
      type: 'map',
      map: mapName.value,
      nameProperty: 'name',
      geoIndex: undefined,
      roam: false,
      zoom: 1,
      layoutSize: '95%',
      selectedMode: 'single',
      emphasis: {
        label: { show: false },
        itemStyle: { areaColor: hoverColor.value, borderColor: hoverBorder.value, borderWidth: 1.5 },
      },
      select:     { label: { show: false } },
      unselected: { label: { show: false }, itemStyle: { opacity: 1 } },
      label: { show: false },
      itemStyle: {
        borderColor: mapBorderColor.value,
        borderWidth: 0.5,
        areaColor: mapAreaColor.value,
      },
      // Destaque do município atual (sem seleção ativa)
      regions: mapData.value
        .filter(d => d.isCurrent && !props.selectedMunicipioId)
        .map(d => ({
          name: d.name,
          itemStyle: { borderColor: themeStore.tokens.primary, borderWidth: 2 },
          emphasis: { itemStyle: { borderColor: themeStore.tokens.primary, borderWidth: 2 } },
        })),
      data: mapData.value,
    }],
  };
});

// ── Sincronização: Tabela → Mapa ─────────────────────────────────────────────
const chartRef = ref(null);
let _prevSelectedName = null;
let _prevHoveredName  = null;

watch(
  () => [props.selectedMunicipioId, mapKey.value],
  async ([ibgeId]) => {
    await nextTick();
    const chart = chartRef.value?.chart;
    if (!chart) return;

    if (_prevSelectedName) {
      chart.dispatchAction({ type: 'unselect', seriesIndex: 0, name: _prevSelectedName });
      _prevSelectedName = null;
    }

    if (!ibgeId) return;

    const match = mapData.value.find(d => Number(d.ibge7) === Number(ibgeId));
    if (match?.name) {
      _prevSelectedName = match.name;
      chart.dispatchAction({ type: 'select', seriesIndex: 0, name: match.name });
    }
  },
  { immediate: true }
);

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
      const target = municipioName.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');
      const match  = mapData.value.find(d =>
        d.municipio?.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '') === target
      );
      if (match?.name) {
        _prevHoveredName = match.name;
        chart.dispatchAction({ type: 'highlight', seriesIndex: 0, name: match.name });
      }
    }
  }
);

const onClick = (params) => {
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
  min-height: 400px;
  cursor: pointer;
}
</style>
