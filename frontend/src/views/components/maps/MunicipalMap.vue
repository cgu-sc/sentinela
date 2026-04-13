<script setup>
import { computed, watch, ref, onMounted, nextTick } from "vue";
import { useAnalyticsStore } from "@/stores/analytics";
import { useGeoStore } from "@/stores/geo";
import { useFilterStore } from "@/stores/filters";
import { useFormatting } from "@/composables/useFormatting";
import { useChartTheme } from "@/config/chartTheme";
import { useThemeStore } from "@/stores/theme";
import { MAP_VISUAL_SCALE } from "@/config/colors.js";
import { storeToRefs } from "pinia";
import { use, registerMap } from "echarts/core";
import { CanvasRenderer } from "echarts/renderers";
import { MapChart } from "echarts/charts";
import { TooltipComponent, VisualMapComponent } from "echarts/components";
import VChart from "vue-echarts";

use([CanvasRenderer, MapChart, TooltipComponent, VisualMapComponent]);

// ── Props (modo embutido — ex: CnpjTabRegional) ───────────────────────────────
// Quando propUf é fornecido, o componente opera em modo embutido:
// usa as props em vez do filterStore e emite eventos em vez de escrever no store.
const props = defineProps({
  propUf: { type: String, default: null },
  propRegiao: { type: String, default: null },
  propMunicipioIbge7: { type: Number, default: null }, // ibge7 pré-selecionado
  propMunicipiosData: { type: Array, default: null }, // substitui resultadoMunicipios
});

const emit = defineEmits(["select-municipio"]);

const embeddedMode = computed(() => !!props.propUf);

const analyticsStore = useAnalyticsStore();
const geoStore = useGeoStore();
const filterStore = useFilterStore();
const { resultadoMunicipios, isLoading } = storeToRefs(analyticsStore);
const { formatBRL, formatPercent } = useFormatting();
const { chartTheme } = useChartTheme();
const themeStore = useThemeStore();

const mapAreaColor = computed(() =>
  themeStore.isDark ? "rgba(255,255,255,0.07)" : "rgba(0,0,0,0.04)",
);
const mapBorderColor = computed(() =>
  themeStore.isDark ? "rgba(255,255,255,0.15)" : "rgba(0,0,0,0.15)",
);
const hoverColor = computed(() => `${themeStore.tokens.primary}4D`);
const hoverBorder = computed(() => `${themeStore.tokens.primary}B3`);

const activeScale = computed(
  () => MAP_VISUAL_SCALE[themeStore.isDark ? "dark" : "light"],
);
const getRiskPiece = (perc) =>
  activeScale.value.find(
    (p) => (p.min == null || perc >= p.min) && (p.max == null || perc < p.max),
  ) ?? activeScale.value[activeScale.value.length - 1];

const norm = (s) =>
  (s ?? "")
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .trim();

// UF ativa: prop ou filterStore
const activeUf = computed(() => props.propUf ?? filterStore.selectedUF);

// ── Estado interno de seleção ─────────────────────────────────────────────────
const selectedIbge7 = ref(props.propMunicipioIbge7 ?? null);

// Sync com a prop quando muda externamente (ex: usuário muda CNPJ)
watch(
  () => props.propMunicipioIbge7,
  (val) => {
    selectedIbge7.value = val ?? null;
  },
);

// Região do município selecionado via clique
const selectedRegiao = computed(() => {
  if (!selectedIbge7.value) return null;
  const loc = geoStore.localidades.find(
    (l) =>
      Number(l.id_ibge7) === Number(selectedIbge7.value) &&
      (activeUf.value === "Todos" || l.sg_uf === activeUf.value),
  );
  return loc?.no_regiao_saude ?? null;
});

// Região efetiva: prop > clique > filterStore
const effectiveRegiao = computed(
  () =>
    props.propRegiao ||
    selectedRegiao.value ||
    (filterStore.selectedRegiaoSaude !== "Todos"
      ? filterStore.selectedRegiaoSaude
      : null),
);

// ── Registro de mapas GeoJSON ─────────────────────────────────────────────────
const mapKey = ref(0);

watch(
  () => activeUf.value,
  (uf) => {
    if (!uf || uf === "Todos") return;
    const geo = geoStore.getMunicipiosGeoByUF(uf);
    if (geo) {
      registerMap(`municipios-${uf}`, geo);
      mapKey.value++;
    }
  },
  { immediate: true },
);

onMounted(async () => {
  // Garante o registro inicial caso o watch immediate já tenha o dado
  if (activeUf.value && activeUf.value !== "Todos") {
    const geo = geoStore.getMunicipiosGeoByUF(activeUf.value);
    if (geo) registerMap(`municipios-${activeUf.value}`, geo);
  }
  
  // O autoresize do vue-echarts resolve a maioria dos problemas de tamanho,
  // mas esperamos um tick para garantir que o contêiner grid está estável.
  await nextTick();
  chartRef.value?.chart?.resize();
});

watch(
  [selectedIbge7, effectiveRegiao],
  ([ibge7, regiao]) => {
    if (!regiao) return;
    const geo = geoStore.getMunicipiosGeoByUF(activeUf.value);
    if (!geo) return;
    const ibge7sRegiao = new Set(
      geoStore.localidades
        .filter(
          (l) =>
            l.no_regiao_saude === regiao &&
            (activeUf.value === "Todos" || l.sg_uf === activeUf.value),
        )
        .map((l) => Number(l.id_ibge7)),
    );
    const features = geo.features.filter((f) =>
      ibge7sRegiao.has(Number(f.properties.id)),
    );
    if (!features.length) return;
    const key = ibge7 ? `regiao-drill-${ibge7}` : `regiao-filter-${regiao}`;
    registerMap(key, { type: "FeatureCollection", features });
    mapKey.value++;
  },
  { immediate: true },
);

const mapName = computed(() => {
  if (selectedIbge7.value) return `regiao-drill-${selectedIbge7.value}`;
  if (effectiveRegiao.value) return `regiao-filter-${effectiveRegiao.value}`;
  return `municipios-${activeUf.value}`;
});

// ── Dados por ibge7 ───────────────────────────────────────────────────────────
const munDataByIbge7 = computed(() => {
  const source = props.propMunicipiosData ?? resultadoMunicipios.value;
  const map = new Map();
  for (const m of source) {
    if (m.id_ibge7) map.set(Number(m.id_ibge7), m);
  }
  return map;
});

// Snapshot dos dados da região (modo standalone):
// evita que re-fetch filtrado por município apague as cores dos demais.
// Em modo embutido os dados são estáticos (prop), snapshot desnecessário.
// Snapshot local (vive enquanto o componente existe).
// filterStore.regionMapData é o fallback persistente entre desmontagens.
// Em modo embutido não usa o snapshot do filterStore (que pode conter dados de outra UF)
const regionSnapshot = ref(props.propUf ? null : (filterStore.regionMapData ?? null));
const mapMunData = computed(() => {
  if (embeddedMode.value) return munDataByIbge7.value;
  return (
    regionSnapshot.value ?? filterStore.regionMapData ?? munDataByIbge7.value
  );
});

// ── mapData ───────────────────────────────────────────────────────────────────
const mapData = computed(() => {
  const geo = geoStore.getMunicipiosGeoByUF(activeUf.value);
  if (!geo) return [];

  let features = geo.features;
  if (effectiveRegiao.value) {
    const ibge7sRegiao = new Set(
      geoStore.localidades
        .filter(
          (l) =>
            l.no_regiao_saude === effectiveRegiao.value &&
            (activeUf.value === "Todos" || l.sg_uf === activeUf.value),
        )
        .map((l) => Number(l.id_ibge7)),
    );
    features = features.filter((f) =>
      ibge7sRegiao.has(Number(f.properties.id)),
    );
  }

  return features.map((f) => {
    const ibge7 = Number(f.properties.id);
    const munData = mapMunData.value.get(ibge7);
    const hasData = !!munData;
    const isSelected =
      !!selectedIbge7.value && ibge7 === Number(selectedIbge7.value);
    const dimmed = !!selectedIbge7.value && !isSelected;
    const opacity = dimmed ? 0.8 : 1;
    const perc = hasData ? (munData.percValSemComp ?? 0) : 0;
    const piece = getRiskPiece(perc);
    const baseColor = hasData ? piece.color : chartTheme.value.bg;
    const bColor = hasData ? piece.borderColor : (themeStore.isDark ? '#555555' : '#aaaaaa');

    return {
      name: f.properties.name,
      ibge7,
      value: hasData ? perc : null,
      municipio: munData?.municipio ?? f.properties.name,
      valSemComp: munData?.valSemComp ?? 0,
      cnpjs: munData?.cnpjs ?? 0,
      hasData,
      selected: isSelected,
      itemStyle: {
        areaColor: baseColor,
        opacity,
      },
      select: hasData
        ? {
            itemStyle: {
              areaColor: piece.color,
              borderColor: piece.borderColor,
              borderWidth: 2.5,
              shadowColor: piece.borderColor,
              shadowBlur: 14,
            },
          }
        : { itemStyle: { opacity: 1 } },
      emphasis: {
        itemStyle: {
          areaColor: hasData ? piece.color : baseColor,
          borderColor: hasData ? piece.borderColor : hoverBorder.value,
          borderWidth: 2,
          opacity: 1,
        },
      },
      silent: false,
    };
  });
});

// ── Chart option ──────────────────────────────────────────────────────────────
const chartOption = computed(() => {
  const c = chartTheme.value;
  return {
    backgroundColor: c.bg,
    tooltip: {
      trigger: "item",
      confine: true,
      backgroundColor: c.tooltip,
      borderColor: c.tooltipBorder,
      borderWidth: 1,
      padding: [12, 16],
      textStyle: {
        color: c.tooltipText,
        fontFamily: "Inter, sans-serif",
        fontSize: 12,
      },
      formatter: (params) => {
        const d = params.data;
        if (!d) return '';
        if (!d.hasData || d.cnpjs === 0) {
          return `
            <div style="color:${c.tooltipText}">
              <div style="font-weight:700;font-size:14px;margin-bottom:8px;">${d.municipio}</div>
              <div style="font-size:12px;opacity:0.8;"><strong>0 estabelecimentos</strong></div>
            </div>`;
        }
        return `
          <div style="color:${c.tooltipText}">
            <div style="font-weight:700;font-size:14px;margin-bottom:8px;">${d.municipio}</div>
            <div style="display:flex;flex-direction:column;gap:4px;font-size:12px;">
              <div>% sem comprovação: <strong>${formatPercent(d.value)}</strong></div>
              <div>Valor sem comprovação: <strong>${formatBRL(d.valSemComp)}</strong></div>
              <div>CNPJs: <strong>${(d.cnpjs ?? 0).toLocaleString("pt-BR")}</strong></div>
            </div>
          </div>`;
      },
    },
    series: [
      {
        type: "map",
        map: mapName.value,
        nameProperty: "name",
        roam: true,
        scaleLimit: { min: 0.8, max: 15 },
        layoutSize: "95%",
        selectedMode: "single",
        select: { label: { show: false } },
        emphasis: {
          label: { show: false },
          itemStyle: {
            areaColor: hoverColor.value,
            borderColor: hoverBorder.value,
            borderWidth: 2,
          },
        },
        label: { show: false },
        itemStyle: {
          borderColor: mapBorderColor.value,
          borderWidth: 0.5,
          areaColor: mapAreaColor.value,
        },
        data: mapData.value,
      },
    ],
  };
});

const chartRef = ref(null);

// ── Watches do store (apenas modo standalone) ────────────────────────────────
watch(
  () => filterStore.selectedRegiaoSaude,
  (regiao) => {
    if (embeddedMode.value) return;
    if (!regiao || regiao === "Todos") {
      selectedIbge7.value = null;
      regionSnapshot.value = null;
      filterStore.regionMapData = null;
    }
  },
);

watch(
  () => filterStore.selectedMunicipio,
  (sel) => {
    if (embeddedMode.value) return;
    if (!sel || sel === "Todos") {
      selectedIbge7.value = null;
      return;
    }
    const nome = sel.split("|")[0];
    const loc = geoStore.localidades.find(
      (l) =>
        norm(l.no_municipio) === norm(nome) &&
        (activeUf.value === "Todos" || l.sg_uf === activeUf.value),
    );
    selectedIbge7.value = loc ? Number(loc.id_ibge7) : null;
  },
  { immediate: true },
);

watch(
  () => filterStore.sidebarCollapsed,
  () => {
    setTimeout(() => chartRef.value?.chart?.resize(), 420);
  },
);

// ── Click ─────────────────────────────────────────────────────────────────────
const onClick = (params) => {
  const ibge7 = params.data?.ibge7;
  const hasData = params.data?.hasData;

  if (!ibge7 || !hasData) {
    chartRef.value?.chart?.dispatchAction({
      type: "unselect",
      seriesIndex: 0,
      name: params.name,
    });
    return;
  }

  if (Number(ibge7) === Number(selectedIbge7.value)) {
    selectedIbge7.value = null;
    if (!embeddedMode.value) filterStore.selectedMunicipio = "Todos";
    emit("select-municipio", null);
    return;
  }

  if (!embeddedMode.value && !regionSnapshot.value) {
    const snap = new Map(munDataByIbge7.value);
    regionSnapshot.value = snap;
    filterStore.regionMapData = snap; // persiste entre desmontagens
  }

  selectedIbge7.value = Number(ibge7);

  const munData = mapMunData.value.get(Number(ibge7));

  if (!embeddedMode.value) {
    if (selectedRegiao.value)
      filterStore.selectedRegiaoSaude = selectedRegiao.value;
    if (munData?.municipio)
      filterStore.selectedMunicipio = `${munData.municipio}|${activeUf.value}`;
  }

  emit("select-municipio", Number(ibge7), munData?.municipio);
};

const onBackClick = () => {
  selectedIbge7.value = null;
  regionSnapshot.value = null;
  filterStore.regionMapData = null;
  if (!embeddedMode.value) {
    filterStore.selectedMunicipio = "Todos";
    filterStore.selectedRegiaoSaude = "Todos";
  }
  emit("select-municipio", null);
};
</script>

<template>
  <div
    class="chart-section"
    :class="{ 'is-refreshing': isLoading && !embeddedMode }"
  >
    <div class="chart-header">
      <i class="pi pi-map"></i>
      <h3>MAPA DE RISCO — {{ effectiveRegiao ?? activeUf }}</h3>
      <div class="spacer"></div>
      <button
        v-if="effectiveRegiao && !embeddedMode"
        class="back-btn"
        @click="onBackClick"
        title="Voltar à visão da UF"
      >
        <i class="pi pi-arrow-left" /> UF
      </button>
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
  width: 100%;
  box-shadow:
    0 1px 3px rgba(0, 0, 0, 0.08),
    0 1px 2px rgba(0, 0, 0, 0.04);
  overflow: hidden;
}

.chart-header {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  padding: 0.75rem 1.25rem;
  border-bottom: 1px solid var(--tabs-border);
  flex-shrink: 0;
}

.chart-header h3 {
  margin: 0;
  font-size: 0.85rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--text-color);
  opacity: 0.8;
}

.chart-header i {
  color: var(--primary-color);
  font-size: 1rem;
}

.chart-wrapper {
  flex: 1;
  min-height: 400px;
}

.echart {
  width: 100%;
  height: 100%;
  cursor: pointer;
}

.spacer {
  flex: 1;
}

.back-btn {
  display: flex;
  align-items: center;
  gap: 0.35rem;
  font-size: 0.7rem;
  font-weight: 600;
  color: var(--text-muted);
  background: none;
  border: 1px solid var(--card-border);
  border-radius: 6px;
  padding: 0.2rem 0.5rem;
  cursor: pointer;
  transition: all 0.15s ease;
}

.back-btn:hover {
  color: var(--primary-color);
  border-color: var(--primary-color);
}

.back-btn i {
  font-size: 0.65rem;
}

.is-refreshing {
  opacity: 0.5;
  pointer-events: none;
}
</style>
