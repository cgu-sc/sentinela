<script setup>
import { computed, ref, watch, onMounted, onBeforeUnmount } from 'vue';
import { useRoute } from 'vue-router';
import {
  FILTER_DEFAULTS,
  FILTER_ALL_VALUE,
  ANALYSIS_YEARS,
  TIMING,
} from '@/config/constants';
import { useFilterStore } from '@/stores/filters';
import { useGeoStore } from '@/stores/geo';
import { useFormatting } from '@/composables/useFormatting';
import { useSliderPeriodLogic } from '@/composables/useSliderPeriodLogic';
import { useFilterParameters } from '@/composables/useFilterParameters';
import { FILTER_OPTIONS } from '@/config/filterOptions';
import Button from 'primevue/button';
import Dropdown from 'primevue/dropdown';
import Slider from 'primevue/slider';
import InputText from 'primevue/inputtext';
import AutoComplete from 'primevue/autocomplete';
import DataIntegrityBanner from '@/layouts/components/DataIntegrityBanner.vue';

const props = defineProps({
  activeModule: { type: String, required: true },
});

const filterStore = useFilterStore();
const filtersLocked = computed(() => filterStore.filtersLocked);
const geoStore = useGeoStore();
const route = useRoute();

// ── Opções dos Selects ───────────────────────────────────────────────────────
const ufOptions = computed(() => geoStore.ufs);
const regiaoSaudeOptions = computed(() => geoStore.regioesPorUF(filterStore.selectedUF));
const unidadePfOptions = computed(() =>
  geoStore.jurisdicoesPorFiltro(
    filterStore.selectedUF,
    filterStore.selectedRegiaoSaude,
    filterStore.selectedMunicipio,
  ),
);
const municipioOptions = computed(() =>
  geoStore.municipiosPorFiltro(
    filterStore.selectedUF,
    filterStore.selectedRegiaoSaude,
    filterStore.selectedUnidadePf,
  ),
);

// ── Watches de cascata: reseta filtros dependentes quando pai muda ───────────
watch(
  () => filterStore.selectedUF,
  (newUF) => {
    const regioesDisponiveis = geoStore.regioesPorUF(newUF);
    if (!regioesDisponiveis.includes(filterStore.selectedRegiaoSaude)) {
      filterStore.selectedRegiaoSaude = 'Todos';
    }
    const unidadesDisponiveis = geoStore.jurisdicoesPorFiltro(
      newUF, filterStore.selectedRegiaoSaude, filterStore.selectedMunicipio,
    );
    if (!unidadesDisponiveis.includes(filterStore.selectedUnidadePf)) {
      filterStore.selectedUnidadePf = 'Todos';
    }
    const municipiosDisponiveis = geoStore.municipiosPorFiltro(
      newUF, filterStore.selectedRegiaoSaude, filterStore.selectedUnidadePf,
    );
    if (!municipiosDisponiveis.some((m) => m.value === filterStore.selectedMunicipio)) {
      filterStore.selectedMunicipio = 'Todos';
    }
  },
);

watch(
  () => filterStore.selectedRegiaoSaude,
  (newRegiao) => {
    const unidadesDisponiveis = geoStore.jurisdicoesPorFiltro(
      filterStore.selectedUF, newRegiao, filterStore.selectedMunicipio,
    );
    if (!unidadesDisponiveis.includes(filterStore.selectedUnidadePf)) {
      filterStore.selectedUnidadePf = 'Todos';
    }
    const municipiosDisponiveis = geoStore.municipiosPorFiltro(
      filterStore.selectedUF, newRegiao, filterStore.selectedUnidadePf,
    );
    if (!municipiosDisponiveis.some((m) => m.value === filterStore.selectedMunicipio)) {
      filterStore.selectedMunicipio = 'Todos';
    }
  },
);

watch(
  () => filterStore.selectedMunicipio,
  (newMun) => {
    const unidadesDisponiveis = geoStore.jurisdicoesPorFiltro(
      filterStore.selectedUF, filterStore.selectedRegiaoSaude, newMun,
    );
    if (!unidadesDisponiveis.includes(filterStore.selectedUnidadePf)) {
      filterStore.selectedUnidadePf = 'Todos';
    }
  },
);

watch(
  () => filterStore.selectedUnidadePf,
  (newUnidade) => {
    const municipiosDisponiveis = geoStore.municipiosPorFiltro(
      filterStore.selectedUF, filterStore.selectedRegiaoSaude, newUnidade,
    );
    if (!municipiosDisponiveis.some((m) => m.value === filterStore.selectedMunicipio)) {
      filterStore.selectedMunicipio = 'Todos';
    }
  },
);

const situacaoOptions  = FILTER_OPTIONS.situacao;
const msOptions        = FILTER_OPTIONS.ms;
const porteOptions     = FILTER_OPTIONS.porte;
const grandeRedeOptions = FILTER_OPTIONS.grandeRede;
const clusterOptions   = FILTER_OPTIONS.cluster;
const rfaOptions       = FILTER_OPTIONS.rfa;

const { formatBRL: formatCurrency } = useFormatting();

// ── Autocomplete de Estabelecimento (CNPJ / Razão Social) ───────────────────
const cnpjSuggestions = ref([]);

function searchEstabelecimento(event) {
  const q = (event.query || '').trim().toLowerCase();
  if (q.length < 2) { cnpjSuggestions.value = []; return; }
  const lista = geoStore.cnpjLookup;
  const numericQ = q.replace(/\D/g, '');
  // Divide a query em tokens e exige que TODOS estejam presentes (qualquer ordem)
  const tokens = q.split(/\s+/).filter(Boolean);
  cnpjSuggestions.value = lista
    .filter(e => {
      if (numericQ.length >= 4 && e.cnpj?.includes(numericQ)) return true;
      const nome = e.razao_social?.toLowerCase() ?? '';
      return tokens.every(t => nome.includes(t));
    })
    .slice(0, 40)
    .map(e => ({ label: e.razao_social, cnpj: e.cnpj, municipio: e.municipio, uf: e.uf }));
}

function onEstabelecimentoSelect(event) {
  // Ao selecionar uma sugestão, preenche com o CNPJ completo
  filterStore.selectedCnpjRaiz = event.value.cnpj;
}

// ── Controle collapse/lock da sidebar ───────────────────────────────────────
const isCollapsed = computed({
  get: () => filterStore.sidebarCollapsed,
  set: (val) => { filterStore.sidebarCollapsed = val; },
});

const isSidebarLocked = computed({
  get: () => filterStore.sidebarLocked,
  set: (val) => { filterStore.sidebarLocked = val; },
});

const toggleSidebarLock = () => {
  isSidebarLocked.value = !isSidebarLocked.value;
};

// ── Rotas que bloqueiam todos os filtros e colapsam a sidebar ────────────────
const LOCKED_ROUTES = ['/listas'];
const isLockedRoute = (path) => LOCKED_ROUTES.some((r) => path.startsWith(r));

// Em telas de detalhe de CNPJ apenas o Período de Análise fica disponível
const isEstabelecimentoRoute = computed(() => route.path.startsWith('/estabelecimentos/'));

// Bloqueia todos os filtros exceto o Período (usado pelo template em cada seção)
const allFiltersLocked = computed(() => filtersLocked.value || isEstabelecimentoRoute.value);

watch(
  () => route.path,
  (path) => {
    const locked = isLockedRoute(path);
    filterStore.filtersLocked = locked;
    if (!filterStore.sidebarLocked) {
      filterStore.sidebarCollapsed = locked;
    }
  },
  { immediate: true },
);

// ── Operações de filtro ──────────────────────────────────────────────────────
const limparFiltros = () => {
  filterStore.resetFilters();
  filterStore.selectedCnpjRaiz = '';
  resetYears();
};

const applyPercentualNaoComprovacao = () => {
  filterStore.percentualNaoComprovacaoFilter = [...filterStore.percentualNaoComprovacaoRange];
};

const stepPercStart = (delta) => {
  const [s, e] = filterStore.percentualNaoComprovacaoRange;
  const newS = Math.max(0, Math.min(e - 1, s + delta));
  if (newS === s) return;
  filterStore.percentualNaoComprovacaoRange = [newS, e];
  applyPercentualNaoComprovacao();
};

const stepPercEnd = (delta) => {
  const [s, e] = filterStore.percentualNaoComprovacaoRange;
  const newE = Math.max(s + 1, Math.min(100, e + delta));
  if (newE === e) return;
  filterStore.percentualNaoComprovacaoRange = [s, newE];
  applyPercentualNaoComprovacao();
};

const applyValorMinSemComp = () => {
  filterStore.valorMinSemCompFilter = filterStore.valorMinSemComp;
};

// Força foco no campo de busca do Dropdown ao abrir
const onDropdownShow = () => {
  setTimeout(() => {
    const input = document.querySelector('.p-dropdown-filter');
    if (input) input.focus();
  }, TIMING.DROPDOWN_FOCUS_DELAY);
};

// Detecta se o valor do filtro mudou em relação ao padrão
const isFilterActive = (field) => {
  const value = filterStore[field];
  const mapStoreToConstants = {
    selectedUF:                    FILTER_DEFAULTS.UF,
    selectedRegiaoSaude:           FILTER_DEFAULTS.REGIAO,
    selectedMunicipio:             FILTER_DEFAULTS.MUNICIPIO,
    selectedUnidadePf:             FILTER_DEFAULTS.UNIDADE_PF,
    selectedSituacao:              FILTER_DEFAULTS.SITUACAO,
    selectedMS:                    FILTER_DEFAULTS.MS,
    selectedPorte:                 FILTER_DEFAULTS.PORTE,
    selectedGrandeRede:            FILTER_DEFAULTS.GRANDE_REDE,
    selectedCnpjRaiz:              '',
    percentualNaoComprovacaoRange: FILTER_DEFAULTS.PERCENTUAL_RANGE,
    valorMinSemComp:               FILTER_DEFAULTS.VALOR_MIN,
    clusterSelection:              FILTER_DEFAULTS.CLUSTER,
    rfaSelection:                  FILTER_DEFAULTS.RFA,
    searchTarget:                  FILTER_DEFAULTS.SEARCH,
    sliderValue:                   FILTER_DEFAULTS.SLIDER_INDEX_RANGE,
  };
  const defaultValue = mapStoreToConstants[field];
  if (Array.isArray(value)) return JSON.stringify(value) !== JSON.stringify(defaultValue);
  return value !== defaultValue;
};

const isIndicadoresRoute = computed(() => route.path.startsWith('/indicadores'));

const activeFilterCount = computed(() => {
  const fields = [
    'selectedUF', 'selectedRegiaoSaude', 'selectedMunicipio', 'selectedUnidadePf',
    'selectedSituacao', 'selectedMS', 'selectedPorte', 'selectedGrandeRede',
    'selectedCnpjRaiz', 'percentualNaoComprovacaoRange', 'valorMinSemComp',
    'sliderValue', 'clusterSelection', 'rfaSelection', 'searchTarget',
  ];
  return fields.filter((f) => isFilterActive(f)).length;
});

// ── Período de análise (slider) ──────────────────────────────────────────────
const displayYears = computed(() => ANALYSIS_YEARS.filter((y) => y >= 2020));

const {
  availableMonths,
  timeSliderValue,
  applySliderPeriod,
  toggleYear,
  isYearActive,
  isYearDisabled,
  resetYears,
  startMonthLabel,
  endMonthLabel,
} = useSliderPeriodLogic();

const { getApiParams } = useFilterParameters();

// Move a ponta inicial do slider em `delta` meses (+1 ou -1)
const stepStart = (delta) => {
  const [s, e] = timeSliderValue.value;
  const newS = Math.max(0, Math.min(e - 1, s + delta));
  if (newS === s) return;
  timeSliderValue.value = [newS, e];
  applySliderPeriod([newS, e]);
};

// Move a ponta final do slider em `delta` meses (+1 ou -1)
const stepEnd = (delta) => {
  const [s, e] = timeSliderValue.value;
  const newE = Math.max(s + 1, Math.min(availableMonths.length - 1, e + delta));
  if (newE === e) return;
  timeSliderValue.value = [s, newE];
  applySliderPeriod([s, newE]);
};

onMounted(() => applySliderPeriod(timeSliderValue.value));

// ── Play automático do Período de Análise ────────────────────────────────────
const PLAY_INTERVAL_MS = 350;
const PLAY_STEP = 3; // trimestral: avança 3 meses por tick

const isPlaying = ref(false);
let playIntervalId = null;

// Range salvo ao iniciar o play, para restaurar ao final ou no reset
const savedRange = ref(null);

const stopPlay = () => {
  isPlaying.value = false;
  filterStore.isAnimating = false;
  if (playIntervalId !== null) {
    clearInterval(playIntervalId);
    playIntervalId = null;
  }
};

const playStep = () => {
  const [s] = timeSliderValue.value;
  const maxE = savedRange.value[1];
  const nextS = s + PLAY_STEP;
  if (nextS > maxE) {
    // Chegou ao fim: para e restaura o range original
    stopPlay();
    timeSliderValue.value = [...savedRange.value];
    applySliderPeriod(savedRange.value);
    savedRange.value = null;
    return;
  }
  const nextE = Math.min(nextS + PLAY_STEP - 1, maxE);
  timeSliderValue.value = [nextS, nextE];
  applySliderPeriod([nextS, nextE]);
};

const isPreloading = computed(() => filterStore.animationPreload.status === 'loading');

const startAnimation = () => {
  if (!savedRange.value) return;
  const startIdx = savedRange.value[0];
  const endIdx = Math.min(startIdx + PLAY_STEP - 1, savedRange.value[1]);
  timeSliderValue.value = [startIdx, endIdx];
  applySliderPeriod([startIdx, endIdx]);
  isPlaying.value = true;
  filterStore.isAnimating = true;
  playIntervalId = setInterval(playStep, PLAY_INTERVAL_MS);
};

const togglePlay = () => {
  if (isPlaying.value) {
    stopPlay();
    return;
  }

  // Pausa → retoma de onde parou (preload já está pronto)
  if (savedRange.value && filterStore.animationPreload.status === 'ready') {
    isPlaying.value = true;
    filterStore.isAnimating = true;
    playIntervalId = setInterval(playStep, PLAY_INTERVAL_MS);
    return;
  }

  // Início limpo: salva range e dispara preload (RiskDiagnosisTab observa e busca os dados)
  savedRange.value = [...timeSliderValue.value];
  const { inicio, fim } = getApiParams();
  filterStore.animationPreload.status = 'loading';
  filterStore.animationPreload.dataInicio = inicio;
  filterStore.animationPreload.dataFim = fim;
};

// Auto-inicia a animação quando o RiskDiagnosisTab sinalizar que o preload concluiu
watch(() => filterStore.animationPreload.status, (status) => {
  if (status === 'ready') startAnimation();
});

const resetPlayback = () => {
  stopPlay();
  if (savedRange.value) {
    timeSliderValue.value = [...savedRange.value];
    applySliderPeriod(savedRange.value);
    savedRange.value = null;
  }
  filterStore.animationPreload.status = 'idle';
  filterStore.animationPreload.dataInicio = null;
  filterStore.animationPreload.dataFim = null;
};

// Para o play e reseta preload ao navegar para outra rota
watch(() => route.path, () => {
  stopPlay();
  savedRange.value = null;
  filterStore.animationPreload.status = 'idle';
});

// Limpa o intervalo ao desmontar o componente
onBeforeUnmount(stopPlay);
</script>

<template>
  <!-- BOTÃO FLUTUANTE (ALÇA) — Segue a borda da sidebar -->
  <button
    class="sidebar-float-btn"
    @click="isCollapsed = !isCollapsed"
    :title="isCollapsed ? 'Abrir painel' : 'Fechar painel'"
  >
    <i :class="isCollapsed ? 'pi pi-angle-right' : 'pi pi-angle-left'"></i>
  </button>

  <!-- BOTÃO DE CADEADO -->
  <button
    class="sidebar-lock-btn"
    :class="{ locked: isSidebarLocked }"
    @click="toggleSidebarLock"
    :title="isSidebarLocked ? 'Sidebar travada — clique para destravar' : 'Travar sidebar colapsada'"
  >
    <i :class="isSidebarLocked ? 'pi pi-lock' : 'pi pi-lock-open'"></i>
  </button>

  <!-- BARRA LATERAL -->
  <aside class="admin-sidebar">
    <DataIntegrityBanner />

    <div class="sidebar-content">
      <div class="sidebar-title-simple">
        <i class="pi pi-sliders-h"></i>
        <span>FILTROS DE PESQUISA</span>
      </div>

      <!-- BANNER DE FILTROS BLOQUEADOS -->
      <div v-if="allFiltersLocked" class="filters-locked-banner">
        <i class="pi pi-lock" />
        <span v-if="isEstabelecimentoRoute">Apenas o Período de Análise está disponível nesta tela</span>
        <span v-else>Filtros indisponíveis nesta tela</span>
      </div>

      <!-- FILTROS GLOBAIS -->
      <div class="filter-section" :class="{ 'filter-locked': allFiltersLocked }">
        <label class="filter-label">
          UF
          <button v-if="isFilterActive('selectedUF')" class="filter-clear-btn" @click="filterStore.selectedUF = FILTER_ALL_VALUE" v-tooltip.right="'Limpar filtro'">
            <i class="pi pi-eraser" />
          </button>
        </label>
        <Dropdown v-model="filterStore.selectedUF" :options="ufOptions" placeholder="Estado" class="w-full filter-input" panelClass="sidebar-panel" :class="{ 'filter-active': isFilterActive('selectedUF') }" />
      </div>

      <div class="filter-section" :class="{ 'filter-locked': allFiltersLocked }">
        <label class="filter-label">
          Região de Saúde
          <button v-if="isFilterActive('selectedRegiaoSaude')" class="filter-clear-btn" @click="filterStore.selectedRegiaoSaude = FILTER_ALL_VALUE" v-tooltip.right="'Limpar filtro'">
            <i class="pi pi-eraser" />
          </button>
        </label>
        <Dropdown v-model="filterStore.selectedRegiaoSaude" :options="regiaoSaudeOptions" placeholder="Região" filter reset-filter-on-hide auto-option-focus filter-match-mode="contains" @show="onDropdownShow" :virtualScrollerOptions="{ itemSize: 32 }" panelClass="sidebar-panel" class="w-full filter-input" :class="{ 'filter-active': isFilterActive('selectedRegiaoSaude') }" />
      </div>

      <div class="filter-section" :class="{ 'filter-locked': allFiltersLocked }">
        <label class="filter-label">
          Município
          <button v-if="isFilterActive('selectedMunicipio')" class="filter-clear-btn" @click="filterStore.selectedMunicipio = FILTER_ALL_VALUE" v-tooltip.right="'Limpar filtro'">
            <i class="pi pi-eraser" />
          </button>
        </label>
        <Dropdown v-model="filterStore.selectedMunicipio" :options="municipioOptions" placeholder="Município" filter optionLabel="label" optionValue="value" reset-filter-on-hide auto-option-focus filter-match-mode="contains" @show="onDropdownShow" :virtualScrollerOptions="{ itemSize: 32 }" panelClass="sidebar-panel" class="w-full filter-input" :class="{ 'filter-active': isFilterActive('selectedMunicipio') }" />
      </div>

      <div class="grid-filters" :class="{ 'filter-locked': allFiltersLocked }">
        <div class="filter-section">
          <label class="filter-label">
            Situação RF
            <button v-if="isFilterActive('selectedSituacao')" class="filter-clear-btn" @click="filterStore.selectedSituacao = FILTER_ALL_VALUE" v-tooltip.right="'Limpar filtro'">
              <i class="pi pi-eraser" />
            </button>
          </label>
          <Dropdown v-model="filterStore.selectedSituacao" :options="situacaoOptions" class="w-full filter-input" panelClass="sidebar-panel" :class="{ 'filter-active': isFilterActive('selectedSituacao') }" />
        </div>
        <div class="filter-section">
          <label class="filter-label">
            Conexão MS
            <button v-if="isFilterActive('selectedMS')" class="filter-clear-btn" @click="filterStore.selectedMS = FILTER_ALL_VALUE" v-tooltip.right="'Limpar filtro'">
              <i class="pi pi-eraser" />
            </button>
          </label>
          <Dropdown v-model="filterStore.selectedMS" :options="msOptions" class="w-full filter-input" panelClass="sidebar-panel" :class="{ 'filter-active': isFilterActive('selectedMS') }" />
        </div>
      </div>

      <div class="grid-filters" :class="{ 'filter-locked': allFiltersLocked }">
        <div class="filter-section">
          <label class="filter-label">
            Porte CNPJ
            <button v-if="isFilterActive('selectedPorte')" class="filter-clear-btn" @click="filterStore.selectedPorte = FILTER_ALL_VALUE" v-tooltip.right="'Limpar filtro'">
              <i class="pi pi-eraser" />
            </button>
          </label>
          <Dropdown v-model="filterStore.selectedPorte" :options="porteOptions" class="w-full filter-input" panelClass="sidebar-panel" :class="{ 'filter-active': isFilterActive('selectedPorte') }" />
        </div>
        <div class="filter-section">
          <label class="filter-label">
            Grande Rede
            <button v-if="isFilterActive('selectedGrandeRede')" class="filter-clear-btn" @click="filterStore.selectedGrandeRede = FILTER_ALL_VALUE" v-tooltip.right="'Limpar filtro'">
              <i class="pi pi-eraser" />
            </button>
          </label>
          <Dropdown v-model="filterStore.selectedGrandeRede" :options="grandeRedeOptions" class="w-full filter-input" panelClass="sidebar-panel" :class="{ 'filter-active': isFilterActive('selectedGrandeRede') }" />
        </div>
      </div>

      <div class="filter-section" :class="{ 'filter-locked': allFiltersLocked }">
        <label class="filter-label">
          Estabelecimento
          <i class="pi pi-info-circle" style="font-size: 0.7rem; margin-left: 4px; opacity: 0.6; cursor: default;" v-tooltip.right="'Digite o CNPJ (completo ou raiz de 8 dígitos) ou parte da razão social. CNPJ completo filtra o estabelecimento exato; raiz filtra toda a rede; texto livre filtra por razão social.'" />
          <button v-if="isFilterActive('selectedCnpjRaiz')" class="filter-clear-btn" @click="filterStore.selectedCnpjRaiz = ''" v-tooltip.right="'Limpar filtro'">
            <i class="pi pi-eraser" />
          </button>
        </label>
        <AutoComplete
          v-model="filterStore.selectedCnpjRaiz"
          :suggestions="cnpjSuggestions"
          optionLabel="label"
          @complete="searchEstabelecimento"
          @option-select="onEstabelecimentoSelect"
          placeholder="CNPJ ou razão social..."
          class="w-full filter-input estabelecimento-ac"
          :class="{ 'filter-active': isFilterActive('selectedCnpjRaiz') }"
          :delay="200"
          :forceSelection="false"
          panelClass="sidebar-ac-panel"
          :pt="{ input: { maxlength: 60 } }"
        >
          <template #option="{ option }">
            <div class="ac-option">
              <span class="ac-razao">{{ option.label }}</span>
              <div class="ac-meta">
                <span class="ac-cnpj">{{ option.cnpj }}</span>
                <span v-if="option.municipio" class="ac-loc">{{ option.municipio }}/{{ option.uf }}</span>
              </div>
            </div>
          </template>
        </AutoComplete>
      </div>

      <div class="filter-section" :class="{ 'filter-locked': allFiltersLocked }">
        <label class="filter-label">
          % de não comprovação
          <button v-if="isFilterActive('percentualNaoComprovacaoRange')" class="filter-clear-btn" @click="() => { filterStore.percentualNaoComprovacaoRange = [0, 100]; applyPercentualNaoComprovacao(); }" v-tooltip.right="'Limpar filtro'">
            <i class="pi pi-eraser" />
          </button>
        </label>
        <div class="slider-container" :class="{ 'filter-active-box': isFilterActive('percentualNaoComprovacaoRange') }">
          <div class="perc-chips">
            <button
              v-for="v in [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]"
              :key="v"
              class="perc-chip"
              :class="{ 'perc-chip-active': filterStore.percentualNaoComprovacaoRange[0] === v }"
              @click="() => { filterStore.percentualNaoComprovacaoRange = [v, 100]; applyPercentualNaoComprovacao(); }"
            >
              {{ v }}%
            </button>
          </div>
          <div class="period-steppers">
            <div class="period-stepper-group">
              <button class="period-step-btn" :disabled="filterStore.percentualNaoComprovacaoRange[0] === 0" @click="stepPercStart(-1)">
                <i class="pi pi-chevron-left" />
              </button>
              <span class="period-step-label">{{ filterStore.percentualNaoComprovacaoRange[0] }}%</span>
              <button class="period-step-btn" :disabled="filterStore.percentualNaoComprovacaoRange[0] >= filterStore.percentualNaoComprovacaoRange[1] - 1" @click="stepPercStart(1)">
                <i class="pi pi-chevron-right" />
              </button>
            </div>
            <div class="period-stepper-group">
              <button class="period-step-btn" :disabled="filterStore.percentualNaoComprovacaoRange[1] <= filterStore.percentualNaoComprovacaoRange[0] + 1" @click="stepPercEnd(-1)">
                <i class="pi pi-chevron-left" />
              </button>
              <span class="period-step-label">{{ filterStore.percentualNaoComprovacaoRange[1] }}%</span>
              <button class="period-step-btn" :disabled="filterStore.percentualNaoComprovacaoRange[1] === 100" @click="stepPercEnd(1)">
                <i class="pi pi-chevron-right" />
              </button>
            </div>
          </div>
          <Slider v-model="filterStore.percentualNaoComprovacaoRange" range class="w-full" @slideend="applyPercentualNaoComprovacao" />
        </div>
      </div>

      <div class="filter-section" :class="{ 'filter-locked-alt': filtersLocked || isIndicadoresRoute }">
        <label class="filter-label" style="pointer-events: auto;">
          Período de Análise
          <button v-if="isFilterActive('sliderValue') && !isIndicadoresRoute" class="filter-clear-btn" @click="resetYears" v-tooltip.right="'Limpar filtro'">
            <i class="pi pi-eraser" />
          </button>
          <i v-if="isIndicadoresRoute" class="pi pi-info-circle" style="font-size: 0.75rem; margin-left: auto; color: var(--primary-color); cursor: help;" v-tooltip.right="'Indicadores utilizam snapshots consolidados da Matriz de Risco. O filtro de período não se aplica a esta tela.'" />
        </label>
        <div class="slider-container" :class="{ 'filter-locked': filtersLocked || isIndicadoresRoute, 'filter-active-box': isFilterActive('sliderValue') }">
          <div class="perc-chips" style="margin-bottom: 0.5rem">
            <button
              v-for="year in displayYears"
              :key="year"
              class="perc-chip"
              :class="{ 'perc-chip-active': isYearActive(year), 'perc-chip-disabled': isYearDisabled(year) }"
              :disabled="isYearDisabled(year) || isIndicadoresRoute"
              @click="toggleYear(year)"
            >
              {{ year }}
            </button>
          </div>
          <div class="period-steppers">
            <div class="period-stepper-group">
              <button class="period-step-btn" :disabled="timeSliderValue[0] === 0 || isIndicadoresRoute" @click="stepStart(-1)">
                <i class="pi pi-chevron-left" />
              </button>
              <span class="period-step-label">{{ startMonthLabel }}</span>
              <button class="period-step-btn" :disabled="timeSliderValue[0] >= timeSliderValue[1] - 1 || isIndicadoresRoute" @click="stepStart(1)">
                <i class="pi pi-chevron-right" />
              </button>
            </div>
            <div class="period-stepper-group">
              <button class="period-step-btn" :disabled="timeSliderValue[1] <= timeSliderValue[0] + 1 || isIndicadoresRoute" @click="stepEnd(-1)">
                <i class="pi pi-chevron-left" />
              </button>
              <span class="period-step-label">{{ endMonthLabel }}</span>
              <button class="period-step-btn" :disabled="timeSliderValue[1] === availableMonths.length - 1 || isIndicadoresRoute" @click="stepEnd(1)">
                <i class="pi pi-chevron-right" />
              </button>
            </div>
          </div>
          <div class="slider-wrapper">
            <Slider v-model="timeSliderValue" range :min="0" :max="availableMonths.length - 1" class="w-full time-slider" :disabled="isIndicadoresRoute" @slideend="() => { stopPlay(); savedRange.value = null; applySliderPeriod(timeSliderValue); }" />
          </div>

          <!-- Controles de Playback -->
          <div class="playback-controls" :class="{ disabled: isIndicadoresRoute }">
            <button
              class="play-btn"
              :class="{ playing: isPlaying, loading: isPreloading }"
              :disabled="isIndicadoresRoute || isPreloading"
              :title="isPreloading ? 'Carregando dados...' : isPlaying ? 'Pausar animação' : 'Animar trimestre a trimestre'"
              @click="togglePlay"
            >
              <i :class="isPreloading ? 'pi pi-spin pi-spinner' : isPlaying ? 'pi pi-pause' : 'pi pi-play'" />
              <span>{{ isPreloading ? 'Carregando...' : isPlaying ? 'Pausar' : 'Animar' }}</span>
            </button>
            <button
              class="period-step-btn reset-btn"
              :disabled="isIndicadoresRoute"
              title="Voltar ao início"
              @click="resetPlayback"
            >
              <i class="pi pi-step-backward" />
            </button>
          </div>
        </div>
      </div>

      <div class="filter-section" style="margin-top: 1.8rem" :class="{ 'filter-locked': allFiltersLocked }">
        <label class="filter-label">
          Valor mínimo sem comprovação
          <button v-if="isFilterActive('valorMinSemComp')" class="filter-clear-btn" @click="() => { filterStore.valorMinSemComp = 0; applyValorMinSemComp(); }" v-tooltip.right="'Limpar filtro'">
            <i class="pi pi-eraser" />
          </button>
        </label>
        <div class="slider-container" :class="{ 'filter-active-box': isFilterActive('valorMinSemComp') }">
          <div class="slider-values">
            <span>{{ formatCurrency(filterStore.valorMinSemComp) }}</span>
          </div>
          <Slider v-model="filterStore.valorMinSemComp" :min="0" :max="FILTER_DEFAULTS.VALOR_MAX" :step="1000" class="w-full" @slideend="applyValorMinSemComp" />
        </div>
      </div>

      <div class="filter-section" :class="{ 'filter-locked': allFiltersLocked }">
        <label class="filter-label">
          Jurisdição PF
          <button v-if="isFilterActive('selectedUnidadePf')" class="filter-clear-btn" @click="filterStore.selectedUnidadePf = FILTER_ALL_VALUE" v-tooltip.right="'Limpar filtro'">
            <i class="pi pi-eraser" />
          </button>
        </label>
        <Dropdown v-model="filterStore.selectedUnidadePf" :options="unidadePfOptions" placeholder="Delegacia / Unidade PF" filter reset-filter-on-hide auto-option-focus filter-match-mode="contains" @show="onDropdownShow" :virtualScrollerOptions="{ itemSize: 32 }" class="w-full filter-input" panelClass="sidebar-panel" :class="{ 'filter-active': isFilterActive('selectedUnidadePf') }" />
      </div>

      <hr class="sidebar-divider my-4" />

      <!-- FILTROS CONTEXTUAIS -->
      <div class="dynamic-filters-box" :class="{ 'filter-locked': allFiltersLocked }">
        <div class="filter-header">
          <i class="pi pi-filter"></i>
          <span>Filtros da Página</span>
        </div>

        <div v-if="route.path === '/alvos/cluster'" class="contextual-filters">
          <div class="filter-section mini">
            <label class="filter-label sm">
              Busca Alvo
              <button v-if="isFilterActive('searchTarget')" class="filter-clear-btn" @click="filterStore.searchTarget = ''" v-tooltip.right="'Limpar filtro'">
                <i class="pi pi-eraser" />
              </button>
            </label>
            <InputText v-model="filterStore.searchTarget" placeholder="ID/CNPJ..." class="w-full filter-input sm" :class="{ 'filter-active': isFilterActive('searchTarget') }" />
          </div>
          <div class="filter-section mini">
            <label class="filter-label sm">
              Target Cluster
              <button v-if="isFilterActive('clusterSelection')" class="filter-clear-btn" @click="filterStore.clusterSelection = FILTER_ALL_VALUE" v-tooltip.right="'Limpar filtro'">
                <i class="pi pi-eraser" />
              </button>
            </label>
            <Dropdown v-model="filterStore.clusterSelection" :options="clusterOptions" class="w-full filter-input sm" panelClass="sidebar-panel" :class="{ 'filter-active': isFilterActive('clusterSelection') }" />
          </div>
          <div class="filter-section mini">
            <label class="filter-label sm">
              Risco (RFA)
              <button v-if="isFilterActive('rfaSelection')" class="filter-clear-btn" @click="filterStore.rfaSelection = FILTER_ALL_VALUE" v-tooltip.right="'Limpar filtro'">
                <i class="pi pi-eraser" />
              </button>
            </label>
            <Dropdown v-model="filterStore.rfaSelection" :options="rfaOptions" class="w-full filter-input sm" panelClass="sidebar-panel" :class="{ 'filter-active': isFilterActive('rfaSelection') }" />
          </div>
        </div>

        <div v-if="route.path === '/alvos/rede'" class="contextual-filters">
          <div class="filter-section mini">
            <label class="filter-label sm">
              CPF/CNPJ Alvo
              <button v-if="isFilterActive('searchTarget')" class="filter-clear-btn" @click="filterStore.searchTarget = ''" v-tooltip.right="'Limpar filtro'">
                <i class="pi pi-eraser" />
              </button>
            </label>
            <InputText v-model="filterStore.searchTarget" placeholder="Pesquisar rede..." class="w-full filter-input sm" />
          </div>
        </div>

        <div v-if="activeModule === 'consolidado'" class="contextual-filters">
          <p class="text-xs px-2 italic" style="color: var(--sidebar-text); opacity: 0.7">
            Nenhum filtro extra necessário.
          </p>
        </div>
      </div>

      <div class="sidebar-spacer"></div>
    </div>

    <div class="sidebar-footer">
      <Button
        :label="activeFilterCount > 0 ? `Limpar Filtros (${activeFilterCount})` : 'Limpar Filtros'"
        icon="pi pi-undo"
        outlined
        :severity="activeFilterCount > 0 ? 'warn' : 'secondary'"
        @click="limparFiltros"
        class="w-full clear-filters-btn"
        :class="{ 'filters-active': activeFilterCount > 0 }"
        :disabled="allFiltersLocked"
      />
    </div>
  </aside>
</template>

<style scoped>
/* SIDEBAR */
.admin-sidebar {
  position: fixed;
  top: 56px;
  left: 0;
  z-index: 200;
  width: var(--sidebar-width);
  background: var(--sidebar-bg) !important;
  color: var(--sidebar-text);
  transition: width 0.35s cubic-bezier(0.4, 0, 0.2, 1);
  will-change: width;
  display: flex;
  flex-direction: column;
  height: calc(100vh - 56px);
  border-right: 1px solid var(--sidebar-border);
  overflow: hidden;
}

/* BOTÃO FLUTUANTE DE REABERTURA */
.sidebar-float-btn {
  position: fixed;
  top: calc(50% + 28px);
  left: var(--sidebar-width);
  transform: translateY(-50%);
  z-index: 250;
  will-change: left;
  width: 20px;
  height: 48px;
  background: color-mix(in srgb, var(--sidebar-bg) 80%, white);
  border: 1px solid var(--sidebar-border);
  border-left: none;
  border-radius: 0 8px 8px 0;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--text-muted);
  transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
  box-shadow: 4px 0 10px rgba(0, 0, 0, 0.1);
}

.sidebar-float-btn:hover {
  width: 28px;
  box-shadow: 6px 0 15px rgba(0, 0, 0, 0.15);
}

.sidebar-float-btn i { font-size: 0.8rem; }

/* BOTÃO DE CADEADO */
.sidebar-lock-btn {
  position: fixed;
  top: calc(50% + 60px);
  left: var(--sidebar-width);
  z-index: 300;
  will-change: left;
  width: 20px;
  height: 36px;
  background: color-mix(in srgb, var(--sidebar-bg) 80%, white);
  border: 1px solid var(--sidebar-border);
  border-left: none;
  border-radius: 0 8px 8px 0;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--primary-color);
  cursor: pointer;
  transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
  box-shadow: 4px 0 10px rgba(0, 0, 0, 0.1);
}

.sidebar-lock-btn:hover { width: 28px; box-shadow: 6px 0 15px rgba(0, 0, 0, 0.15); }

.sidebar-lock-btn.locked {
  opacity: 1;
  color: var(--primary-color);
  background: color-mix(in srgb, var(--primary-color) 12%, var(--sidebar-bg));
}

.sidebar-lock-btn i { font-size: 0.8rem; }


.sidebar-title-simple {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 0.5rem;
  font-size: 0.72rem;
  font-weight: 800;
  color: var(--sidebar-text);
  opacity: 0.45;
  letter-spacing: 0.12em;
  text-transform: uppercase;
  padding: 0.2rem 0.5rem 0.3rem;
  margin-bottom: 0rem;
  border-bottom: 1px solid var(--sidebar-border);
}

.sidebar-title-simple i {
  font-size: 0.8rem;
}

.sidebar-content {
  flex: 1;
  padding: 0.75rem 1rem;
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
  overflow-y: auto;
  overflow-x: hidden;
  --scrollbar-track: var(--sidebar-bg);
  --scrollbar-thumb: rgba(255, 255, 255, 0.15);
  --scrollbar-thumb-hover: rgba(255, 255, 255, 0.3);
}

.sidebar-content::-webkit-scrollbar       { width: 4px; }
.sidebar-content::-webkit-scrollbar-track { background: var(--sidebar-bg); }
.sidebar-content::-webkit-scrollbar-thumb { background: var(--sidebar-border); border-radius: 4px; }
.sidebar-content::-webkit-scrollbar-thumb:hover { background: var(--text-muted); }

.sidebar-footer   { padding: 1rem; }
.sidebar-spacer   { flex: 1; }
.sidebar-divider  { border: 0; border-top: 1px solid var(--sidebar-border); opacity: 0.5; margin: 0.5rem 0; }

.filter-section { margin-bottom: 0.35rem; }

.filter-locked {
  pointer-events: none;
  opacity: 0.38;
  user-select: none;
}

.filter-locked-alt {
  opacity: 0.38;
  user-select: none;
}

.filters-locked-banner {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.6rem 0.8rem;
  margin-bottom: 0.75rem;
  /* Usa o fundo da sidebar para evitar o flash branco em modo light */
  background: color-mix(in srgb, var(--primary-color) 12%, var(--sidebar-bg));
  border: 1px solid color-mix(in srgb, var(--primary-color) 30%, transparent);
  border-radius: 8px;
  font-size: 0.7rem;
  font-weight: 600;
  color: var(--primary-color);
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.15);
}

.filters-locked-banner .pi { font-size: 0.7rem; }

.filter-label {
  display: flex;
  align-items: center;
  gap: 0.25rem;
  font-size: 0.65rem;
  font-weight: 700;
  text-transform: uppercase;
  margin-bottom: 0.25rem;
  color: var(--sidebar-text);
  letter-spacing: 0.5px;
}

.filter-clear-btn {
  margin-left: auto;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 14px;
  height: 14px;
  border: none;
  background: none;
  cursor: pointer;
  padding: 0;
  color: var(--color-error);
  opacity: 0.7;
  transition: opacity 0.15s;
  flex-shrink: 0;
}

.filter-clear-btn:hover { opacity: 1; }
.filter-clear-btn .pi   { font-size: 0.75rem; }

.grid-filters {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 0.5rem;
}

.grid-filters .filter-section { min-width: 0; }

.grid-filters :deep(.p-dropdown-label) {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

/* COMPONENTES COMPACTOS DO PRIMEVUE */
:deep(.filter-input .p-inputtext),
:deep(.filter-input .p-dropdown-label),
:deep(.filter-input.p-inputtext) {
  padding: 0.4rem 0.6rem;
  font-size: 0.75rem;
  text-transform: none;
}

:deep(.p-dropdown),
:deep(.p-calendar),
:deep(.filter-input.p-inputtext) {
  height: 32px;
  align-items: center;
  box-sizing: border-box;
}

:deep(.filter-input.p-dropdown),
:deep(.filter-input.p-inputtext) {
  background: var(--sidebar-input-bg) !important;
  border-color: var(--sidebar-border) !important;
  color: var(--sidebar-text) !important;
}

:deep(.filter-input .p-dropdown-label),
:deep(.filter-input .p-dropdown-trigger) {
  background: transparent !important;
  color: inherit !important;
}

:global(.admin-sidebar .p-dropdown.p-focus),
:global(.admin-sidebar .p-inputtext:not(.p-dropdown-label):focus),
:global(.admin-sidebar .filter-active.p-dropdown),
:global(.admin-sidebar .filter-active.p-inputtext:not(.p-dropdown-label)) {
  border: 2px solid color-mix(in srgb, var(--primary-color) 50%, transparent) !important;
  background: rgba(255, 255, 255, 0.03) !important;
  box-shadow: 0 0 0 2px color-mix(in srgb, var(--primary-color) 15%, transparent) !important;
  outline: none !important;
}

:global(.admin-sidebar) .p-inputtext,
:global(.admin-sidebar) .p-dropdown {
  background: var(--sidebar-input-bg) !important;
  border-color: var(--sidebar-border) !important;
  color: var(--sidebar-text) !important;
}

:global(.admin-sidebar) .p-dropdown-label,
:global(.admin-sidebar) .p-dropdown-trigger {
  background: transparent !important;
}

/* PAINEL DOS DROPDOWNS */
:global(.p-dropdown-panel.sidebar-panel) {
  background: var(--sidebar-bg) !important;
  border: 1px solid var(--sidebar-border) !important;
  box-shadow: 0 10px 25px rgba(0, 0, 0, 0.4) !important;
}

:global(.sidebar-panel .p-dropdown-items .p-dropdown-item) {
  color: var(--sidebar-text) !important;
  font-size: 0.8rem;
}

:global(.sidebar-panel .p-dropdown-items .p-dropdown-item:not(.p-highlight):not(.p-disabled):hover) {
  background: var(--sidebar-input-bg) !important;
  color: var(--sidebar-text) !important;
}

:global(.sidebar-panel .p-dropdown-items .p-dropdown-item.p-highlight) {
  background: color-mix(in srgb, var(--primary-color) 20%, transparent) !important;
  color: var(--primary-color) !important;
}

:global(.sidebar-panel .p-dropdown-header) {
  background: var(--sidebar-bg) !important;
  border-bottom: 1px solid var(--sidebar-border) !important;
}

:global(.sidebar-panel .p-dropdown-filter-container .p-inputtext) {
  background: var(--sidebar-input-bg) !important;
  color: var(--sidebar-text) !important;
}

/* SLIDERS */
.slider-container { padding: 0.5rem 0.2rem; }

.slider-values {
  display: flex;
  justify-content: space-between;
  font-size: 0.65rem;
  font-weight: 700;
  margin-bottom: 0.4rem;
  color: var(--sidebar-text);
}

.perc-chips {
  display: grid;
  grid-template-columns: repeat(5, 1fr);
  gap: 0.3rem;
  margin-bottom: 0.5rem;
}

.perc-chip {
  font-size: 0.68rem;
  font-weight: 700;
  padding: 0.28rem 0;
  border-radius: 6px;
  border: 1px solid var(--sidebar-border);
  color: var(--sidebar-text);
  background: var(--sidebar-input-bg);
  cursor: pointer;
  transition: all 0.2s ease;
  font-family: inherit;
}

.perc-chip:hover {
  border-color: var(--primary-color);
  color: var(--primary-color);
  background: color-mix(in srgb, var(--primary-color) 8%, transparent);
}

.perc-chip:focus { outline: none; }

.perc-chip-active {
  border-color: var(--primary-color) !important;
  color: var(--primary-color) !important;
  background: color-mix(in srgb, var(--primary-color) 14%, transparent) !important;
  box-shadow: 0 0 6px color-mix(in srgb, var(--primary-color) 20%, transparent);
}

.perc-chip-disabled {
  opacity: 0.25;
  cursor: not-allowed;
  pointer-events: none;
}

.slider-wrapper {
  position: relative;
  margin-top: 8px;
}

.filter-input { margin-bottom: 4px !important; }

.period-steppers {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 4px;
  gap: 0.25rem;
}

.period-stepper-group {
  display: flex;
  align-items: center;
  gap: 2px;
  flex: 1;
}

.period-step-label {
  font-size: 0.68rem;
  font-weight: 600;
  color: var(--sidebar-text);
  background: var(--sidebar-input-bg);
  border: 1px solid var(--sidebar-border);
  border-radius: 4px;
  padding: 2px 6px;
  min-width: 62px;
  flex: 1;
  text-align: center;
  white-space: nowrap;
}

.period-step-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 20px;
  height: 20px;
  padding: 0;
  border: 1px solid var(--sidebar-border);
  border-radius: 4px;
  background: var(--sidebar-input-bg);
  color: var(--text-muted);
  cursor: pointer;
  transition: background 0.15s, color 0.15s, border-color 0.15s;
  flex-shrink: 0;
}

.period-step-btn i {
  font-size: 0.55rem;
}

.period-step-btn:hover:not(:disabled) {
  background: color-mix(in srgb, var(--primary-color) 12%, var(--sidebar-input-bg));
  border-color: var(--primary-color);
  color: var(--primary-color);
}

.period-step-btn:disabled {
  opacity: 0.3;
  cursor: not-allowed;
}

:deep(.p-slider) {
  background: var(--sidebar-border);
  height: 4px !important;
}

:deep(.p-slider .p-slider-range) { background: var(--sidebar-border) !important; }

:deep(.p-slider-handle) {
  border: 2px solid var(--accent-indigo) !important;
  background: var(--sidebar-bg) !important;
  width: 14px !important;
  height: 14px !important;
  margin-top: -6px !important;
  transition: background 0.2s, box-shadow 0.2s;
}

:deep(.p-slider:not(.p-disabled) .p-slider-handle:hover) {
  background: var(--accent-indigo) !important;
  box-shadow: 0 0 0 6px color-mix(in srgb, var(--accent-indigo) 20%, transparent) !important;
}

.filter-active-box :deep(.p-slider-handle) {
  border-color: var(--primary-color) !important;
}

.filter-active-box :deep(.p-slider:not(.p-disabled) .p-slider-handle:hover) {
  background: var(--primary-color) !important;
  box-shadow: 0 0 0 6px color-mix(in srgb, var(--primary-color) 20%, transparent) !important;
}

/* FILTROS ATIVOS */
.filter-active-box {
  background: color-mix(in srgb, var(--primary-color) 12%, transparent) !important;
  border-radius: 4px;
}

/* BOTÃO LIMPAR FILTROS */
:deep(.clear-filters-btn.p-button) {
  background: transparent !important;
  transition: all 0.2s ease !important;
}

:deep(.clear-filters-btn.p-button:hover) {
  background: transparent !important;
  border-color: color-mix(in srgb, var(--primary-color) 50%, transparent) !important;
  color: var(--primary-color) !important;
}

:deep(.clear-filters-btn.p-button:focus),
:deep(.clear-filters-btn.p-button:active) { outline: none !important; box-shadow: none !important; }

:deep(.clear-filters-btn.p-button:focus-visible) { box-shadow: 0 0 0 2px var(--primary-color) !important; }

:deep(.filters-active.p-button) {
  background: color-mix(in srgb, var(--primary-color) 12%, transparent) !important;
  border-color: var(--primary-color) !important;
  color: var(--primary-color) !important;
  position: relative;
  overflow: hidden; /* Necessário para o efeito de brilho (shimmer) */
}

/* Efeito Shimmer (Brilho que atravessa o botão) */
:deep(.filters-active.p-button::after) {
  content: "";
  position: absolute;
  top: 0;
  left: -100%;
  width: 100%;
  height: 100%;
  background: linear-gradient(
    90deg,
    transparent,
    rgba(255, 255, 255, 0.1),
    rgba(255, 255, 255, 0.2),
    rgba(255, 255, 255, 0.1),
    transparent
  );
  animation: shimmer-sweep 3s infinite ease-in-out;
}

/* Animação do Ícone (Micro-interação) */
:deep(.filters-active.p-button .p-button-icon) {
  animation: icon-spin-subtle 3s infinite ease-in-out;
}

@keyframes shimmer-sweep {
  0%   { left: -100%; }
  20%  { left: 100%; }  /* Passa rápido no início do ciclo */
  100% { left: 100%; }  /* Fica invisível no resto do tempo */
}

@keyframes icon-spin-subtle {
  0%, 75% { transform: rotate(0deg); }
  90%     { transform: rotate(-360deg); }
  100%    { transform: rotate(-360deg); }
}

@keyframes pulse-filter {
  0%, 100% { box-shadow: 0 0 0 0 color-mix(in srgb, var(--primary-color) 25%, transparent); }
  50%       { box-shadow: 0 0 0 6px color-mix(in srgb, var(--primary-color) 0%, transparent); }
}

/* FILTROS CONTEXTUAIS */
.dynamic-filters-box {
  margin-top: 1rem;
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
}

.filter-header {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0 0.5rem 0.5rem;
  border-bottom: 1px solid var(--sidebar-border);
  margin-bottom: 1rem;
}

.filter-header i    { color: var(--primary-color); font-size: 0.9rem; }
.filter-header span { font-size: 0.75rem; font-weight: 800; text-transform: uppercase; color: var(--sidebar-text); letter-spacing: 0.5px; }

.filter-section.mini { margin-bottom: 1rem; padding: 0 0.5rem; }

.filter-label.sm { font-size: 0.7rem; opacity: 0.8; margin-bottom: 0.4rem; }

:deep(.filter-input.sm .p-inputtext),
:deep(.filter-input.sm .p-dropdown-label) {
  padding: 0.5rem;
  font-size: 0.8rem;
}

/* AUTOCOMPLETE DE ESTABELECIMENTO */
:deep(.estabelecimento-ac) {
  width: 100%;
  height: 32px;
  box-sizing: border-box;
}

:deep(.estabelecimento-ac .p-autocomplete-input) {
  width: 100%;
  height: 32px;
  box-sizing: border-box;
  padding: 0.4rem 0.6rem;
  font-size: 0.75rem;
  background: var(--sidebar-input-bg) !important;
  border-color: var(--sidebar-border) !important;
  color: var(--sidebar-text) !important;
}

:global(.admin-sidebar .estabelecimento-ac .p-autocomplete-input:focus) {
  border: 2px solid color-mix(in srgb, var(--primary-color) 50%, transparent) !important;
  background: rgba(255, 255, 255, 0.03) !important;
  box-shadow: 0 0 0 2px color-mix(in srgb, var(--primary-color) 15%, transparent) !important;
  outline: none !important;
}

:global(.admin-sidebar .filter-active.estabelecimento-ac .p-autocomplete-input) {
  border: 2px solid color-mix(in srgb, var(--primary-color) 50%, transparent) !important;
}

:global(.sidebar-ac-panel) {
  background: var(--sidebar-bg) !important;
  border: 1px solid var(--sidebar-border) !important;
  box-shadow: 0 10px 25px rgba(0, 0, 0, 0.4) !important;
  border-radius: 8px !important;
  max-height: 280px !important;
}

:global(.sidebar-ac-panel .p-autocomplete-item) {
  padding: 0 !important;
  background: transparent !important;
}

:global(.sidebar-ac-panel .p-autocomplete-item:hover),
:global(.sidebar-ac-panel .p-autocomplete-item.p-highlight) {
  background: color-mix(in srgb, var(--primary-color) 10%, transparent) !important;
}

.ac-option {
  display: flex;
  flex-direction: column;
  padding: 0.45rem 0.75rem;
  gap: 0.15rem;
}

.ac-razao {
  font-size: 0.75rem;
  color: var(--sidebar-text);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  max-width: 240px;
}

.ac-meta {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.ac-cnpj {
  font-size: 0.65rem;
  color: var(--text-muted);
  letter-spacing: 0.02em;
}

.ac-loc {
  font-size: 0.65rem;
  color: var(--primary-color);
  opacity: 0.75;
}

/* CONTROLES DE PLAYBACK */
.playback-controls {
  display: flex;
  align-items: center;
  gap: 0.35rem;
  margin-top: 0.6rem;
}

.playback-controls.disabled {
  opacity: 0.3;
  pointer-events: none;
}

.play-btn {
  flex: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 0.4rem;
  height: 26px;
  padding: 0 0.75rem;
  border-radius: 6px;
  border: 1px solid color-mix(in srgb, var(--primary-color) 40%, transparent);
  background: color-mix(in srgb, var(--primary-color) 8%, transparent);
  color: var(--primary-color);
  font-size: 0.68rem;
  font-weight: 600;
  cursor: pointer;
  transition: background 0.18s, border-color 0.18s, box-shadow 0.18s;
  letter-spacing: 0.03em;
}

.play-btn i {
  font-size: 0.6rem;
}

.play-btn:hover {
  background: color-mix(in srgb, var(--primary-color) 16%, transparent);
  border-color: var(--primary-color);
}

.play-btn.loading {
  opacity: 0.75;
  cursor: wait;
}

.play-btn.playing {
  background: color-mix(in srgb, var(--primary-color) 18%, transparent);
  border-color: var(--primary-color);
  box-shadow: 0 0 0 2px color-mix(in srgb, var(--primary-color) 20%, transparent);
  animation: play-pulse 1.6s ease-in-out infinite;
}

.reset-btn {
  width: 26px;
  height: 26px;
  flex-shrink: 0;
}

@keyframes play-pulse {
  0%, 100% { box-shadow: 0 0 0 2px color-mix(in srgb, var(--primary-color) 20%, transparent); }
  50%       { box-shadow: 0 0 0 4px color-mix(in srgb, var(--primary-color) 10%, transparent); }
}
</style>
