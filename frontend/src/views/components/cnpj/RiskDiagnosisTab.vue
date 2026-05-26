<script setup>
import { computed, ref, watch, onUnmounted, unref } from 'vue';
import { useCnpjDetailStore } from '@/stores/cnpjDetail';
import { useRegional } from '@/composables/useRegional';
import { useFilterStore } from '@/stores/filters';
import { useFilterParameters } from '@/composables/useFilterParameters';
import { useSliderPeriodLogic } from '@/composables/useSliderPeriodLogic';
import { useFormatting } from '@/composables/useFormatting';
import { API_ENDPOINTS } from '@/config/api';
import RegionalRankChart from '../charts/RegionalRankChart.vue';
import RiskDistributionChart from '../charts/RiskDistributionChart.vue';
import TabPlaceholder from './TabPlaceholder.vue';
import Dropdown from 'primevue/dropdown';
import Slider from 'primevue/slider';

const props = defineProps({
  cnpj: { type: String, required: true },
  geoData: { type: Object, default: null },
  cnpjData: { type: Object, default: null },
  periodSummary: { type: Object, default: null },
  periodLoading: { type: Boolean, default: false },
  isActive: { type: Boolean, default: false },
});

const cnpjDetailStore = useCnpjDetailStore();
const filterStore = useFilterStore();
const { getApiParams } = useFilterParameters();
const { toLocalISO } = useFormatting();
const { regionalData, regionalError, fetchRegional } = useRegional();

// Escopo do scatter regional
const regionalScope = ref('regiao');
const regionalScopes = [
  { label: 'Região de Saúde', value: 'regiao' },
  { label: 'Estado (UF)',      value: 'uf'     },
];

// Score da farmácia atual
// Nota: percValSemComp pode exceder 100% por anomalias nos dados de auditoria
// (val_sem_comp > total_mov). Limitamos a 100 para coincidir com a curva de percentis.
const currentScore = computed(() => {
    if (isAnimationPreviewActive.value && previewCurrentFarmacia.value) {
      if (riskMetric.value === 'percentual_sem_comprovacao') {
        return Math.min(Number(previewCurrentFarmacia.value.percValSemComp ?? 0), 100);
      }
      return Number(
        previewCurrentFarmacia.value.score_risco ??
        previewCurrentFarmacia.value.score_risco_final ??
        0
      );
    }
    // Se estivermos vendo %, usamos o valor do período selecionado (se disponível)
    if (riskMetric.value === 'percentual_sem_comprovacao') {
      const val = props.periodSummary?.percValSemComp ?? props.cnpjData?.percValSemComp ?? 0;
      return Math.min(Number(val), 100);
    }
    // Para Score de Risco, usamos o valor consolidado
    return Number(props.cnpjData?.score_risco_final || 0);
});

// Configuração do Escopo da Curva de Risco
const riskScope = ref('brasil');
const riskMetric = ref('percentual_sem_comprovacao');

const riskScopes = [
  { label: 'Região de Saúde', value: 'regiao' },
  { label: 'UF', value: 'uf' },
  { label: 'Brasil', value: 'brasil' }
];

const riskMetricOptions = [
  { label: 'Score de Risco', value: 'score' },
  { label: '% Não-Comprovação', value: 'percentual_sem_comprovacao' }
];

const isAnimationPreviewActive = computed(() => {
  if (!filterStore.animationMode) return false;
  const [inicio, fim] = filterStore.animationFrameRange ?? [];
  return (
    inicio instanceof Date &&
    !Number.isNaN(inicio.getTime()) &&
    fim instanceof Date &&
    !Number.isNaN(fim.getTime())
  );
});

function getEffectivePeriodParams() {
  if (isAnimationPreviewActive.value) {
    const [inicio, fim] = filterStore.animationFrameRange;
    return {
      inicio: toLocalISO(inicio),
      fim: toLocalISO(fim),
    };
  }
  return getApiParams();
}

const updateRiskCurve = () => {
  if (!props.isActive) return;
  if (!props.geoData?.sg_uf) return;
  const { inicio, fim } = getEffectivePeriodParams();

  // Durante animação, serve do cache sem round-trip HTTP
  if (isAnimationPreviewActive.value) {
    const key = `${riskScope.value}|${props.geoData.sg_uf}|${props.geoData.id_regiao_saude ?? ''}|${riskMetric.value}|${inicio}|${fim}`;
    if (percentilesCache.has(key)) {
      cnpjDetailStore.setMetricPercentilesDirectly(percentilesCache.get(key), key);
      return;
    }
  }

  cnpjDetailStore.fetchMetricPercentiles(
    riskScope.value,
    props.geoData.sg_uf,
    props.geoData.id_regiao_saude,
    riskMetric.value,
    inicio,
    fim
  );
};

// ── Cache de animação ────────────────────────────────────────────────────────
// Mapa local: "YYYY-MM-DD|YYYY-MM-DD" → farmacias[] (pré-carregado pelo endpoint único)
const periodsCache = new Map();
// Mapa local: "scope|uf|regioId|metric|YYYY-MM-DD|YYYY-MM-DD" → percentiles[]
const percentilesCache = new Map();

const previewCurrentFarmacia = computed(() => {
  const { inicio, fim } = getEffectivePeriodParams();
  if (!isAnimationPreviewActive.value || !inicio || !fim) return null;
  const frame = periodsCache.get(`${inicio}|${fim}`);
  return frame?.farmacias?.find((item) => String(item.cnpj) === String(props.cnpj)) ?? null;
});

// Máximos globais calculados sobre todos os trimestres — usados para fixar os
// eixos do scatter durante a animação e evitar que a escala salte entre passos.
const animationXMax    = ref(null); // max totalMov
const animationYMax    = ref(null); // max score_risco
const animationYMaxPct = ref(null); // max percValSemComp

const loadRegional = () => {
    if (!props.isActive) return;
    if (!props.geoData?.sg_uf) return;
    const { inicio, fim } = getEffectivePeriodParams();

    // Durante animação, serve direto do cache sem round-trip HTTP
    const cacheKey = `${inicio}|${fim}`;
    if (isAnimationPreviewActive.value && periodsCache.has(cacheKey)) {
      regionalData.value = periodsCache.get(cacheKey);
      return;
    }

    fetchRegional(
      props.geoData.sg_uf,
      inicio,
      fim,
      regionalScope.value === 'regiao' ? (props.geoData.id_regiao_saude ?? null) : null,
    );
};

// Observa o gatilho de preload disparado pelo AppSidebar.
// Faz UM único fetch que retorna todos os trimestres, popula o cache e sinaliza 'ready'.
watch(() => filterStore.animationPreload.status, async (status) => {
  if (status !== 'loading') return;
  if (!props.geoData?.sg_uf) {
    filterStore.animationPreload.status = 'ready';
    return;
  }

  try {
    const scatterUrl = API_ENDPOINTS.analyticsRegionalBenchmarkingAnimation(
      props.geoData.sg_uf,
      filterStore.animationPreload.dataInicio,
      filterStore.animationPreload.dataFim,
      regionalScope.value === 'regiao' ? props.geoData.id_regiao_saude : null,
    );
    const percentilesUrl = API_ENDPOINTS.analyticsMetricPercentilesAnimation(
      riskScope.value,
      props.geoData.sg_uf,
      props.geoData.id_regiao_saude ?? null,
      riskMetric.value,
      filterStore.animationPreload.dataInicio,
      filterStore.animationPreload.dataFim,
    );

    // Ambos os fetches em paralelo — uma única "rodada" de rede antes de animar
    const [scatterRes, percRes] = await Promise.all([
      fetch(scatterUrl),
      fetch(percentilesUrl),
    ]);
    if (!scatterRes.ok) throw new Error(`scatter HTTP ${scatterRes.status}`);
    if (!percRes.ok)    throw new Error(`percentiles HTTP ${percRes.status}`);

    const [scatterData, percData] = await Promise.all([
      scatterRes.json(),
      percRes.json(),
    ]);

    // Popula cache do scatter: cada período vira entrada keyed por "inicio|fim"
    periodsCache.clear();
    let xMax = 0, scoreMax = 0, pctMax = 0;
    for (const q of scatterData.quarters ?? []) {
      periodsCache.set(`${q.inicio}|${q.fim}`, { farmacias: q.farmacias });
      for (const f of q.farmacias ?? []) {
        xMax     = Math.max(xMax,     f.totalMov || 0);
        scoreMax = Math.max(scoreMax, f.score_risco ?? f.score_risco_final ?? 0);
        
        // Capamos o cálculo do máximo global em 100% para evitar que anomalias 
        // de auditoria (val > total) joguem o eixo do scatter para 400%+.
        const valPct = f.percValSemComp ?? 0;
        pctMax = Math.max(pctMax, valPct > 100 ? 100 : valPct);
      }
    }
    animationXMax.value    = xMax     || null;
    animationYMax.value    = scoreMax || null;
    animationYMaxPct.value = pctMax   || null;

    // Popula cache de percentis: keyed por "scope|uf|regioId|metric|inicio|fim"
    percentilesCache.clear();
    for (const q of percData.quarters ?? []) {
      const key = `${riskScope.value}|${props.geoData.sg_uf}|${props.geoData.id_regiao_saude ?? ''}|${riskMetric.value}|${q.inicio}|${q.fim}`;
      percentilesCache.set(key, q.percentiles);
    }
  } catch (e) {
    console.error('[RiskDiagnosis] Erro no preload de animação:', e);
  }

  if (!filterStore.animationMode) {
    clearAnimationState();
    filterStore.animationPreload.status = 'idle';
    return;
  }

  filterStore.animationPreload.status = 'ready';
});

const clearAnimationState = () => {
  periodsCache.clear();
  percentilesCache.clear();
  animationXMax.value    = null;
  animationYMax.value    = null;
  animationYMaxPct.value = null;
};

// ── Lógica de Controle de Playback (Migrado da Sidebar) ──────────────
const { availableMonths, timeSliderValue } = useSliderPeriodLogic();
const isPreloading = computed(() => filterStore.animationPreload.status === 'loading');

const PLAY_DURATION_MS = 450;
const PLAY_INTERVAL_MS = 400;
const PLAY_STEP = 1;
const PLAY_WINDOW_MONTHS = 3;

const isPlaying = ref(false);
let playIntervalId = null;

const animationSliderMin = computed(() => filterStore.animationBaseSliderRange?.[0] ?? 0);
const animationSliderMax = computed(() => {
  if (!filterStore.animationBaseSliderRange) return 0;
  const [startIdx, endIdx] = filterStore.animationBaseSliderRange;
  return Math.max(startIdx, endIdx - PLAY_WINDOW_MONTHS + 1);
});

const getAnimationFrameEndIndex = (startIdx) => {
  if (!filterStore.animationBaseSliderRange) return startIdx;
  return Math.min(startIdx + PLAY_WINDOW_MONTHS - 1, filterStore.animationBaseSliderRange[1]);
};

const syncAnimationFrame = (startIdx) => {
  if (!filterStore.animationBaseSliderRange) return;
  const clampedStart = Math.min(
    Math.max(startIdx, animationSliderMin.value),
    animationSliderMax.value,
  );
  const endIdx = getAnimationFrameEndIndex(clampedStart);
  const months = unref(availableMonths);
  const startDate = months[clampedStart]?.date;
  const rawEndDate = months[endIdx]?.date;
  if (!startDate || !rawEndDate) return;

  filterStore.animationSliderValue = clampedStart;
  filterStore.animationFrameRange = [
    startDate,
    new Date(rawEndDate.getFullYear(), rawEndDate.getMonth() + 1, 0),
  ];
};

const stopPlay = () => {
  isPlaying.value = false;
  filterStore.isAnimating = false;
  filterStore.animationDuration = PLAY_DURATION_MS; // Mantém a suavidade (tweening) nas mudanças manuais
  if (playIntervalId !== null) {
    clearInterval(playIntervalId);
    playIntervalId = null;
  }
};

const resetAnimationPreload = () => {
  filterStore.animationPreload.status = 'idle';
  filterStore.animationPreload.dataInicio = null;
  filterStore.animationPreload.dataFim = null;
};

const closeAnimationPreview = () => {
  stopPlay();
  filterStore.resetAnimationPreview();
};

const canShowAnimationControls = computed(() =>
  props.isActive &&
  !props.periodLoading &&
  Boolean(props.cnpjData) &&
  !regionalError.value &&
  Boolean(props.geoData?.sg_uf)
);

watch(canShowAnimationControls, (canShow) => {
  if (!canShow && filterStore.animationMode) {
    closeAnimationPreview();
  }
});

const playStep = () => {
  if (filterStore.animationSliderValue === null || filterStore.animationSliderValue === undefined) {
    stopPlay();
    return;
  }
  const nextStart = filterStore.animationSliderValue + PLAY_STEP;
  if (nextStart > animationSliderMax.value) {
    stopPlay();
    return;
  }
  syncAnimationFrame(nextStart);
};

const startAnimation = () => {
  if (!filterStore.animationBaseSliderRange) return;
  if (filterStore.animationSliderValue === animationSliderMax.value) {
    syncAnimationFrame(filterStore.animationBaseSliderRange[0]);
  }
  isPlaying.value = true;
  filterStore.isAnimating = true;
  filterStore.animationDuration = PLAY_DURATION_MS;
  playIntervalId = setInterval(playStep, PLAY_INTERVAL_MS);
};

const togglePlay = () => {
  if (!canShowAnimationControls.value) return;

  if (isPlaying.value) {
    stopPlay();
    return;
  }

  if (!filterStore.animationMode) {
     const baseRange = [...unref(timeSliderValue)];
     filterStore.animationMode = true;
     filterStore.animationBaseSliderRange = baseRange;
     filterStore.animationDuration = PLAY_DURATION_MS; // Garante suavidade antes mesmo do startAnimation
     syncAnimationFrame(baseRange[0]);
  }

  if (filterStore.animationPreload.status === 'ready') {
    startAnimation();
    return;
  }

  const { inicio, fim } = getApiParams();
  filterStore.animationPreload.status = 'loading';
  filterStore.animationPreload.dataInicio = inicio;
  filterStore.animationPreload.dataFim = fim;
};

watch(
  () => filterStore.animationPreload.status,
  (status) => {
    if (status !== 'ready') return;
    if (!filterStore.animationMode) {
      resetAnimationPreload();
      return;
    }
    startAnimation();
  }
);

// ── Funções de Slider Manual ─────────────────────────────────────────────────
const animationSliderValue = computed({
  get: () => filterStore.animationSliderValue,
  set: (val) => { filterStore.animationSliderValue = val; }
});

const stepAnimation = (delta) => {
  if (!filterStore.animationMode || isPlaying.value) return;
  syncAnimationFrame((animationSliderValue.value ?? animationSliderMin.value) + delta);
};

const onAnimationSliderEnd = () => {
  if (!filterStore.animationMode) return;
  stopPlay();
  syncAnimationFrame(animationSliderValue.value ?? animationSliderMin.value);
};

watch(animationSliderValue, (val) => {
  if (filterStore.animationMode && !isPlaying.value && val !== null) {
    syncAnimationFrame(val);
  }
});

const animationStartMonthLabel = computed(() => {
  if (animationSliderValue.value === null || animationSliderValue.value === undefined) {
    return "—";
  }
  return unref(availableMonths)[animationSliderValue.value]?.label ?? "—";
});

// Limpa cache e reseta preload se o componente for desmontado durante animação
onUnmounted(() => {
  stopPlay();
  clearAnimationState();
  if (filterStore.animationPreload.status !== 'idle') {
    filterStore.animationPreload.status = 'idle';
  }
});

watch(riskMetric, () => {
    if (filterStore.animationMode) {
      clearAnimationState();
      filterStore.animationPreload.status = 'idle';
    }
    updateRiskCurve();
});

watch(regionalScope, () => {
    clearAnimationState();
    filterStore.animationPreload.status = 'idle';
    loadRegional();
});

watch(riskScope, () => {
    if (filterStore.animationMode) {
      clearAnimationState();
      filterStore.animationPreload.status = 'idle';
    }
    updateRiskCurve();
});

watch(() => props.geoData?.sg_uf, () => {
    updateRiskCurve();
    loadRegional();
}, { immediate: true });

watch(() => props.isActive, (active) => {
    if (!active) return;
    updateRiskCurve();
    loadRegional();
});

// Escuta mudanças no filtro global de período
watch(() => filterStore.periodo, () => {
    if (filterStore.animationMode) return;
    updateRiskCurve();
    loadRegional();
}, { deep: true });

// Sincroniza dados quando o frame da animação muda
watch(() => filterStore.animationFrameRange, () => {
    if (!isAnimationPreviewActive.value) return;
    updateRiskCurve();
    loadRegional();
}, { deep: true });

// Limpa caches ao sair do modo animação
watch(() => filterStore.animationMode, (isActive) => {
    if (!isActive) {
      clearAnimationState();
      updateRiskCurve();
      loadRegional();
      return;
    }
    updateRiskCurve();
    loadRegional();
});


// Texto de ranking baseado no escopo selecionado
const rankingText = computed(() => {
  const d = props.cnpjData;
  if (!d) return null;
  
  // O Rank textual (ex: 4º de 1000) por enquanto só está disponível para o Score final consolidado nos dados do CNPJ
  // Se estiver visualizando apenas a métrica de %, removemos o texto fixo de rank consolidado para não confundir
  if (riskMetric.value !== 'score') return null;

  const map = {
    uf:     { rank: d.rank_uf,           total: d.total_uf,           label: 'no estado' },
    regiao: { rank: d.rank_regiao_saude, total: d.total_regiao_saude, label: 'na região' },
    brasil: { rank: d.rank_nacional,     total: d.total_nacional,     label: 'no Brasil'  },
  };
  const entry = map[riskScope.value];
  if (!entry?.rank) return null;
  return `${entry.rank}º de ${entry.total} ${entry.label}`;
});

// Calcula em qual "topo" de risco a farmácia está — exibido dentro do box do gráfico
const riskRankBadge = computed(() => {
  const data = cnpjDetailStore.metricPercentiles;
  if (!data?.length || currentScore.value === null || currentScore.value === undefined) return null;
  const idx = data.findIndex(d => d.score >= currentScore.value);
  if (idx === -1) return { label: 'Extremo', value: 'TOP 1%', color: '#ef4444' };
  const pct = data[idx].percentile;
  const topPct = 101 - pct;
  if (topPct <= 5)  return { label: 'Crítico', value: `TOP ${topPct}%`,    color: '#ef4444' };
  if (topPct <= 15) return { label: 'Alerta',  value: `TOP ${topPct}%`,    color: '#f59e0b' };
  return             { label: 'Normal',  value: `Percentil ${pct}%`, color: '#10b981' };
});

</script>

<template>
  <div class="tab-content risk-diagnosis-tab">
    
    <!-- Aviso de GeoData ausente -->
    <TabPlaceholder
      v-if="!cnpjData"
      variant="error"
      icon="pi-exclamation-circle"
      title="Erro ao carregar"
      description="Não foi possível carregar os dados. Verifique a conexão com o servidor."
    />

    <TabPlaceholder
      v-else-if="regionalError"
      variant="error"
      icon="pi-exclamation-circle"
      title="Erro ao carregar"
      :description="regionalError"
    />

    <TabPlaceholder
      v-else-if="!geoData?.sg_uf"
      icon="pi-map-marker"
      title="Geolocalização indisponível"
      description="Informações geográficas incompletas para realizar o diagnóstico comparativo."
    />

    <template v-else>
      <div class="diagnosis-grid">
        
        <!-- CARD 1: POSICIONAMENTO REGIONAL (Scatter) -->
        <div class="diagnosis-card">
          <div class="card-header">
             <div class="header-info">
                <i class="pi pi-users" />
                <span>{{ regionalScope === 'uf' ? 'Posicionamento Estadual' : 'Posicionamento Regional' }}</span>
             </div>
             <div class="scope-selector">
                <Dropdown
                  v-model="regionalScope"
                  :options="regionalScopes"
                  optionLabel="label"
                  optionValue="value"
                  class="p-inputtext-sm"
                  panelClass="card-panel"
                >
                  <template #value="slotProps">
                    <div v-if="slotProps.value" class="flex align-items-center gap-2">
                      <span class="dropdown-selected-label">{{ regionalScopes.find(s => s.value === slotProps.value).label }}</span>
                    </div>
                  </template>
                </Dropdown>
             </div>
          </div>
          <div class="card-body relative-body">
             <div class="chart-wrapper">
                <RegionalRankChart
                   v-if="regionalData?.farmacias?.length"
                   :farmacias="regionalData.farmacias"
                   :cnpj-atual="cnpj"
                   :regiao-nome="regionalScope === 'uf' ? geoData.sg_uf : geoData.no_regiao_saude"
                   :active-metric="riskMetric"
                   :x-axis-max="isAnimationPreviewActive ? animationXMax : null"
                   :y-axis-max="isAnimationPreviewActive ? (riskMetric === 'percentual_sem_comprovacao' ? animationYMaxPct : animationYMax) : null"
                 />
             </div>

             <!-- AJUDA CONTEXTUAL CARD 1 -->
             <div class="diagnosis-card-help">
               <i class="pi pi-info-circle" />
               <div class="help-text">
                  <b>Contexto {{ regionalScope === 'uf' ? 'Estadual' : 'Regional' }}:</b> Confronta o score deste CNPJ com os CNPJs {{ regionalScope === 'uf' ? 'do mesmo estado' : 'da mesma região de saúde' }}. Permite detectar se o estabelecimento é um "ponto fora da curva". Quanto mais ao topo e à direita do gráfico, pior e mais anômalo é o cenário avaliado.
               </div>
             </div>
          </div>
        </div>

        <!-- CARD 2: CURVA DE ACÚMULO (CLIFF) -->
        <div class="diagnosis-card risk-curve-container">
          <div class="card-header">
             <div class="header-info">
                <i class="pi pi-chart-line" />
                <span>Percentil de Risco</span>
             </div>
             <div class="header-actions">
               <div class="scope-selector">
                  <Dropdown
                    v-model="riskMetric"
                    :options="riskMetricOptions"
                    optionLabel="label"
                    optionValue="value"
                    class="p-inputtext-sm"
                    panelClass="card-panel"
                  >
                    <template #value="slotProps">
                      <div v-if="slotProps.value" class="flex align-items-center gap-2">
                        <span class="dropdown-selected-label">{{ riskMetricOptions.find(m => m.value === slotProps.value)?.label }}</span>
                      </div>
                    </template>
                  </Dropdown>
               </div>
               <div class="scope-selector">
                  <Dropdown
                    v-model="riskScope"
                    :options="riskScopes"
                    optionLabel="label"
                    optionValue="value"
                    class="p-inputtext-sm"
                    panelClass="card-panel"
                  >
                    <template #value="slotProps">
                      <div v-if="slotProps.value" class="flex align-items-center gap-2">
                         <span class="dropdown-selected-label">{{ riskScopes.find(s => s.value === slotProps.value).label }}</span>
                      </div>
                    </template>
                  </Dropdown>
               </div>
             </div>
          </div>
            <div class="card-body">

              <RiskDistributionChart
                :data="cnpjDetailStore.metricPercentiles"
                :current-score="currentScore"
                :loading="cnpjDetailStore.metricPercentilesLoading"
                :ranking-text="rankingText"
                :metric-label="riskMetric === 'score' ? 'Score de Risco' : '% Não-Comprovação'"
                :rank-badge="riskRankBadge"
                :y-axis-max="isAnimationPreviewActive ? (riskMetric === 'percentual_sem_comprovacao' ? animationYMaxPct : animationYMax) : null"
              />
            <!-- AJUDA CONTEXTUAL CARD 2 -->
            <div class="diagnosis-card-help">
               <i class="pi pi-chart-line" />
               <div class="help-text">
                  <b>Comparativo:</b> Mapeia onde este CNPJ se encontra frente ao universo de estabelecimentos analisados. O deslocamento para a direita indica que este CNPJ possui um score superior à grande maioria dos estabelecimentos.
               </div>
            </div>
          </div>
        </div>

      </div>
    </template>

    <!-- FAB de Controle da Animação Temporal -->
    <!-- Teleport to body: evita que o transform da animação tabContentEntry
         quebre o position:fixed do FAB durante os primeiros 400ms da aba -->
    <Teleport to="body">
    <div v-if="canShowAnimationControls" class="fab-container">
      
      <!-- Painel de Controle de Período (Slider) -->
      <Transition name="fade-slide-right">
        <div v-if="filterStore.animationMode" class="fab-slider-panel">
          <button
            class="period-step-btn"
            :disabled="animationSliderValue === animationSliderMin || isPlaying"
            @click="stepAnimation(-PLAY_STEP)"
          >
            <i class="pi pi-chevron-left"></i>
          </button>

          <span class="period-step-label">{{ animationStartMonthLabel }}</span>

          <div class="animation-slider-wrapper">
            <Slider
              v-model="animationSliderValue"
              :min="animationSliderMin"
              :max="animationSliderMax"
              class="w-full time-slider"
              :disabled="isPreloading || isPlaying"
              @slideend="onAnimationSliderEnd"
            />
          </div>

          <button
            class="period-step-btn"
            :disabled="animationSliderValue === animationSliderMax || isPlaying"
            @click="stepAnimation(PLAY_STEP)"
          >
            <i class="pi pi-chevron-right"></i>
          </button>
        </div>
      </Transition>

      <div class="fab-buttons">
        <Transition name="fade-scale">
          <button
            v-if="filterStore.animationMode"
            class="fab-close-btn"
            v-tooltip.left="'Fechar Animação'"
            @click="closeAnimationPreview"
          >
            <i class="pi pi-times"></i>
          </button>
        </Transition>

        <button
          class="fab-main-btn"
          :class="{ playing: isPlaying, loading: isPreloading }"
          v-tooltip.left="isPlaying ? 'Pausar Animação' : 'Animar Período'"
          @click="togglePlay"
        >
          <i v-if="isPreloading" class="pi pi-spin pi-spinner"></i>
          <i v-else-if="isPlaying" class="pi pi-pause"></i>
          <i v-else class="pi pi-play"></i>
        </button>
      </div>
    </div>
    </Teleport>

  </div>
</template>

<style scoped>
.risk-diagnosis-tab {
  display: flex;
  flex-direction: column;
  gap: 1.5rem;
  min-height: 100%;
  flex: 1;
  position: relative; /* Mantém o banner dentro dos limites da aba */
}

.diagnosis-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 1.5rem;
  align-items: stretch;
  flex: 1;
  min-height: 520px;
  position: relative;
}

.diagnosis-card {
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  border-radius: 12px;
  overflow: hidden;
  display: flex;
  flex-direction: column;
  box-shadow: 0 4px 12px rgba(0,0,0,0.06);
}

.card-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 0.85rem 1.25rem;
  border-bottom: 1px solid var(--card-border);
  background: rgba(255, 255, 255, 0.02);
}

.header-info {
  display: flex;
  align-items: center;
  gap: 0.8rem;
  font-weight: 600;
  font-size: 0.82rem;
  color: var(--text-color);
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

.header-info i { color: var(--primary-color); font-size: 1.1rem; }

.header-actions {
  display: flex;
  align-items: center;
  gap: 0.75rem;
}

.card-body {
  flex: 1;
  display: flex;
  flex-direction: column;
  min-height: 0;
}

.relative-body { position: relative; }

.chart-wrapper {
  flex: 1;
  display: flex;
  flex-direction: column;
}

.scope-selector { min-width: 180px; }

:deep(.scope-selector .p-dropdown) {
  background: color-mix(in srgb, var(--primary-color) 6%, transparent);
  border: 1px solid color-mix(in srgb, var(--primary-color) 30%, transparent);
  border-radius: 8px;
  width: 100%;
}

:deep(.scope-selector .p-dropdown-label) {
  font-size: 0.75rem;
  font-weight: 500;
  color: var(--primary-color);
  padding: 0.35rem 0.5rem;
}

:global(.p-dropdown-panel.card-panel) {
  background: var(--card-bg) !important;
  border: 1px solid var(--card-border) !important;
  border-radius: 8px;
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.15) !important;
}

.diagnosis-card-help {
  display: flex;
  align-items: flex-start;
  gap: 0.85rem;
  padding: 0.85rem 1rem;
  background: color-mix(in srgb, var(--primary-color) 4%, transparent);
  border-left: 4px solid var(--primary-color);
  border-radius: 6px;
  margin: 1.5rem 1.25rem 1.25rem 1.25rem;
  margin-top: auto;
}

.diagnosis-card-help i { color: var(--primary-color); font-size: 1rem; }
.help-text { font-size: 0.78rem; color: var(--text-secondary); line-height: 1.4; }
.help-text b { color: var(--text-color); font-weight: 600; }

/* Animação Pulso */
.animation-pulse {
  animation: pulse-glow 2s infinite ease-in-out;
}

@keyframes pulse-glow {
  0%, 100% { opacity: 1; filter: drop-shadow(0 0 5px var(--primary-color)); }
  50% { opacity: 0.6; filter: drop-shadow(0 0 12px var(--primary-color)); }
}

.diagnosis-grid {
  transition: padding-top 0.4s ease;
}

/* ── Floating Action Button (FAB) e Painel ──────────────────────────────────────── */
.fab-container {
  position: fixed;
  bottom: 2rem;
  right: 2rem;
  z-index: 500;
  display: flex;
  align-items: flex-end;
  gap: 1.25rem;
}

.fab-buttons {
  position: relative;
  display: flex;
  align-items: center;
  justify-content: center;
}

.fab-slider-panel {
  background: color-mix(in srgb, var(--card-bg) 95%, transparent);
  backdrop-filter: blur(8px);
  -webkit-backdrop-filter: blur(8px);
  border: 1px solid var(--card-border);
  border-radius: 999px; /* Pill shape */
  padding: 0 1.25rem;
  box-shadow: 0 4px 16px rgba(0,0,0,0.1);
  display: flex;
  align-items: center;
  gap: 1rem;
  height: 56px; /* Matches fab-main-btn height */
  width: 400px;
}

.period-stepper-group {
  display: flex;
  align-items: center;
  gap: 0.35rem;
}

.period-step-btn {
  width: 24px;
  height: 24px;
  border-radius: 50%;
  border: 1px solid var(--card-border);
  background: transparent;
  color: var(--text-muted);
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  transition: all 0.2s;
  padding: 0;
}
.period-step-btn i { font-size: 0.6rem; }
.period-step-btn:hover:not(:disabled) {
  border-color: var(--primary-color);
  color: var(--primary-color);
  background: color-mix(in srgb, var(--primary-color) 10%, transparent);
}
.period-step-btn:disabled {
  opacity: 0.4;
  cursor: not-allowed;
}

.period-step-label {
  font-size: 0.75rem;
  font-weight: 600;
  color: var(--text-color);
  width: 75px; /* Tamanho fixo para evitar que a barra trema ou mude de tamanho */
  text-align: center;
}

.animation-slider-wrapper {
  flex: 1;
  display: flex;
  align-items: center;
}

:deep(.time-slider) {
  height: 4px;
  background: var(--card-border);
}
:deep(.time-slider .p-slider-range) {
  background: var(--primary-color);
}
:deep(.time-slider .p-slider-handle) {
  width: 14px;
  height: 14px;
  margin-top: -5px;
  border: 2px solid var(--primary-color);
  background: var(--card-bg);
  transition: all 0.2s;
}
:deep(.time-slider .p-slider-handle:hover) {
  background: var(--primary-color);
  box-shadow: 0 0 0 6px color-mix(in srgb, var(--primary-color) 20%, transparent);
}

.fade-slide-right-enter-active,
.fade-slide-right-leave-active {
  transition: all 0.3s cubic-bezier(0.175, 0.885, 0.32, 1.275);
}
.fade-slide-right-enter-from,
.fade-slide-right-leave-to {
  opacity: 0;
  transform: translateX(20px) scale(0.95);
}

.fab-close-btn {
  position: absolute;
  bottom: calc(100% + 0.5rem);
  left: 50%;
  transform: translateX(-50%);
  width: 32px;
  height: 32px;
  border-radius: 50%;
  border: none;
  background: color-mix(in srgb, var(--sidebar-bg) 80%, white);
  color: var(--text-muted);
  box-shadow: 0 4px 12px rgba(0,0,0,0.15);
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: all 0.2s ease;
}
.fab-close-btn:hover {
  background: var(--color-error);
  color: white;
}
.fab-close-btn i {
  font-size: 0.85rem;
}

.fab-main-btn {
  width: 56px;
  height: 56px;
  border-radius: 50%;
  border: none;
  background: var(--primary-color);
  color: white;
  box-shadow: 0 6px 16px color-mix(in srgb, var(--primary-color) 40%, transparent);
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: all 0.3s cubic-bezier(0.175, 0.885, 0.32, 1.275);
}

.fab-main-btn i {
  font-size: 1.5rem;
  margin-left: 4px; /* Centralização visual do Play */
}

.fab-main-btn .pi-pause, .fab-main-btn .pi-spinner {
  margin-left: 0; /* Volta ao normal para outros ícones */
}

.fab-main-btn:hover {
  transform: scale(1.05);
  box-shadow: 0 8px 24px color-mix(in srgb, var(--primary-color) 60%, transparent);
}

.fab-main-btn.playing {
  background: #f97316; /* Laranja Vibrante para Pause */
  box-shadow: 0 6px 16px color-mix(in srgb, #f97316 50%, transparent);
  animation: fab-pulse 2s infinite cubic-bezier(0.66, 0, 0, 1);
}

.fab-main-btn.loading {
  background: var(--sidebar-border);
  color: var(--text-muted);
  cursor: wait;
  transform: scale(0.95);
  box-shadow: none;
}

@keyframes fab-pulse {
  0% { box-shadow: 0 0 0 0 color-mix(in srgb, #f97316 70%, transparent); }
  70% { box-shadow: 0 0 0 15px color-mix(in srgb, #f97316 0%, transparent); }
  100% { box-shadow: 0 0 0 0 color-mix(in srgb, #f97316 0%, transparent); }
}

.fade-scale-enter-active,
.fade-scale-leave-active {
  transition: all 0.3s cubic-bezier(0.175, 0.885, 0.32, 1.275);
}
.fade-scale-enter-from,
.fade-scale-leave-to {
  opacity: 0;
  transform: scale(0.5) translateY(10px);
}
</style>
