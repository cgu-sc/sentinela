<script setup>
import { computed, watch, onMounted } from 'vue';
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
import { FILTER_OPTIONS } from '@/config/filterOptions';
import Button from 'primevue/button';
import Dropdown from 'primevue/dropdown';
import Slider from 'primevue/slider';
import InputText from 'primevue/inputtext';
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

// ── Rotas que bloqueiam filtros e colapsam a sidebar ─────────────────────────
const LOCKED_ROUTES = ['/estabelecimento/', '/listas'];
const isLockedRoute = (path) => LOCKED_ROUTES.some((r) => path.startsWith(r));

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
  startPos,
  endPos,
  startTransform,
  endTransform,
} = useSliderPeriodLogic();

onMounted(() => applySliderPeriod(timeSliderValue.value));
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
    <div class="sidebar-header" title="Projeto Sentinela">
      <div class="brand">
        <img src="/img/logo_sentinela_transparente.png" alt="Sentinela V3" class="logo-img" />
        <div class="brand-text">
          <span class="brand-name">SENTINELA</span>
          <span class="brand-version">AUDITORIA NO FARMÁCIA POPULAR</span>
        </div>
      </div>
    </div>

    <DataIntegrityBanner />

    <div class="sidebar-content">
      <!-- BANNER DE FILTROS BLOQUEADOS -->
      <div v-if="filtersLocked" class="filters-locked-banner">
        <i class="pi pi-lock" />
        <span>Filtros indisponíveis durante a análise de um CNPJ</span>
      </div>

      <!-- FILTROS GLOBAIS -->
      <div class="filter-section" :class="{ 'filter-locked': filtersLocked }">
        <label class="filter-label">
          UF
          <button v-if="isFilterActive('selectedUF')" class="filter-clear-btn" @click="filterStore.selectedUF = FILTER_ALL_VALUE" v-tooltip.right="'Limpar filtro'">
            <i class="pi pi-eraser" />
          </button>
        </label>
        <Dropdown v-model="filterStore.selectedUF" :options="ufOptions" placeholder="Estado" class="w-full filter-input" panelClass="sidebar-panel" :class="{ 'filter-active': isFilterActive('selectedUF') }" />
      </div>

      <div class="filter-section" :class="{ 'filter-locked': filtersLocked }">
        <label class="filter-label">
          Região de Saúde
          <button v-if="isFilterActive('selectedRegiaoSaude')" class="filter-clear-btn" @click="filterStore.selectedRegiaoSaude = FILTER_ALL_VALUE" v-tooltip.right="'Limpar filtro'">
            <i class="pi pi-eraser" />
          </button>
        </label>
        <Dropdown v-model="filterStore.selectedRegiaoSaude" :options="regiaoSaudeOptions" placeholder="Região" filter reset-filter-on-hide auto-option-focus filter-match-mode="contains" @show="onDropdownShow" :virtualScrollerOptions="{ itemSize: 32 }" panelClass="sidebar-panel" class="w-full filter-input" :class="{ 'filter-active': isFilterActive('selectedRegiaoSaude') }" />
      </div>

      <div class="filter-section" :class="{ 'filter-locked': filtersLocked }">
        <label class="filter-label">
          Município
          <button v-if="isFilterActive('selectedMunicipio')" class="filter-clear-btn" @click="filterStore.selectedMunicipio = FILTER_ALL_VALUE" v-tooltip.right="'Limpar filtro'">
            <i class="pi pi-eraser" />
          </button>
        </label>
        <Dropdown v-model="filterStore.selectedMunicipio" :options="municipioOptions" placeholder="Município" filter optionLabel="label" optionValue="value" reset-filter-on-hide auto-option-focus filter-match-mode="contains" @show="onDropdownShow" :virtualScrollerOptions="{ itemSize: 32 }" panelClass="sidebar-panel" class="w-full filter-input" :class="{ 'filter-active': isFilterActive('selectedMunicipio') }" />
      </div>

      <div class="grid-filters" :class="{ 'filter-locked': filtersLocked }">
        <div class="filter-section">
          <label class="filter-label">Situação RF</label>
          <Dropdown v-model="filterStore.selectedSituacao" :options="situacaoOptions" class="w-full filter-input" panelClass="sidebar-panel" :class="{ 'filter-active': isFilterActive('selectedSituacao') }" />
        </div>
        <div class="filter-section">
          <label class="filter-label">Conexão MS</label>
          <Dropdown v-model="filterStore.selectedMS" :options="msOptions" class="w-full filter-input" panelClass="sidebar-panel" :class="{ 'filter-active': isFilterActive('selectedMS') }" />
        </div>
      </div>

      <div class="grid-filters" :class="{ 'filter-locked': filtersLocked }">
        <div class="filter-section">
          <label class="filter-label">Porte CNPJ</label>
          <Dropdown v-model="filterStore.selectedPorte" :options="porteOptions" class="w-full filter-input" panelClass="sidebar-panel" :class="{ 'filter-active': isFilterActive('selectedPorte') }" />
        </div>
        <div class="filter-section">
          <label class="filter-label">Grande Rede</label>
          <Dropdown v-model="filterStore.selectedGrandeRede" :options="grandeRedeOptions" class="w-full filter-input" panelClass="sidebar-panel" :class="{ 'filter-active': isFilterActive('selectedGrandeRede') }" />
        </div>
      </div>

      <div class="filter-section" :class="{ 'filter-locked': filtersLocked }">
        <label class="filter-label">
          CNPJ
          <i class="pi pi-info-circle" style="font-size: 0.7rem; margin-left: 4px; opacity: 0.6; cursor: default;" v-tooltip.right="'Aceita CNPJ completo (14 dígitos) ou apenas a raiz (8 dígitos), com ou sem máscara. CNPJ completo filtra o estabelecimento exato; raiz filtra toda a rede.'" />
          <button v-if="isFilterActive('selectedCnpjRaiz')" class="filter-clear-btn" @click="filterStore.selectedCnpjRaiz = ''" v-tooltip.right="'Limpar filtro'">
            <i class="pi pi-eraser" />
          </button>
        </label>
        <InputText v-model="filterStore.selectedCnpjRaiz" placeholder="Digite o CNPJ..." class="w-full filter-input" :class="{ 'filter-active': isFilterActive('selectedCnpjRaiz') }" :maxlength="18" />
      </div>

      <div class="filter-section" :class="{ 'filter-locked': filtersLocked }">
        <label class="filter-label">% de não comprovação</label>
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
          <div class="slider-values">
            <span>{{ filterStore.percentualNaoComprovacaoRange[0] }}%</span>
            <span>{{ filterStore.percentualNaoComprovacaoRange[1] }}%</span>
          </div>
          <Slider v-model="filterStore.percentualNaoComprovacaoRange" range class="w-full" @slideend="applyPercentualNaoComprovacao" />
        </div>
      </div>

      <div class="filter-section">
        <label class="filter-label">Período de Análise</label>
        <div class="slider-container" :class="{ 'filter-active-box': isFilterActive('sliderValue') }">
          <div class="perc-chips" style="margin-bottom: 0.5rem">
            <button
              v-for="year in ANALYSIS_YEARS"
              :key="year"
              class="perc-chip"
              :class="{ 'perc-chip-active': isYearActive(year), 'perc-chip-disabled': isYearDisabled(year) }"
              :disabled="isYearDisabled(year)"
              @click="toggleYear(year)"
            >
              {{ year }}
            </button>
          </div>
          <div class="slider-wrapper relative pt-3 mt-0">
            <div class="slider-tip" :style="{ left: startPos + '%', transform: startTransform }">{{ startMonthLabel }}</div>
            <div class="slider-tip" :style="{ left: endPos + '%', transform: endTransform }">{{ endMonthLabel }}</div>
            <Slider v-model="timeSliderValue" range :min="0" :max="availableMonths.length - 1" class="w-full time-slider" @slideend="() => applySliderPeriod(timeSliderValue)" />
          </div>
        </div>
      </div>

      <div class="filter-section" style="margin-top: 1.8rem" :class="{ 'filter-locked': filtersLocked }">
        <label class="filter-label">Valor mínimo sem comprovação</label>
        <div class="slider-container" :class="{ 'filter-active-box': isFilterActive('valorMinSemComp') }">
          <div class="slider-values">
            <span>{{ formatCurrency(filterStore.valorMinSemComp) }}</span>
          </div>
          <Slider v-model="filterStore.valorMinSemComp" :min="0" :max="FILTER_DEFAULTS.VALOR_MAX" :step="1000" class="w-full" @slideend="applyValorMinSemComp" />
        </div>
      </div>

      <div class="filter-section" :class="{ 'filter-locked': filtersLocked }">
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
      <div class="dynamic-filters-box" :class="{ 'filter-locked': filtersLocked }">
        <div class="filter-header">
          <i class="pi pi-filter"></i>
          <span>Filtros da Página</span>
        </div>

        <div v-if="route.path === '/alvos/cluster'" class="contextual-filters">
          <div class="filter-section mini">
            <label class="filter-label sm">Busca Alvo</label>
            <InputText v-model="filterStore.searchTarget" placeholder="ID/CNPJ..." class="w-full filter-input sm" :class="{ 'filter-active': isFilterActive('searchTarget') }" />
          </div>
          <div class="filter-section mini">
            <label class="filter-label sm">Target Cluster</label>
            <Dropdown v-model="filterStore.clusterSelection" :options="clusterOptions" class="w-full filter-input sm" panelClass="sidebar-panel" :class="{ 'filter-active': isFilterActive('clusterSelection') }" />
          </div>
          <div class="filter-section mini">
            <label class="filter-label sm">Risco (RFA)</label>
            <Dropdown v-model="filterStore.rfaSelection" :options="rfaOptions" class="w-full filter-input sm" panelClass="sidebar-panel" :class="{ 'filter-active': isFilterActive('rfaSelection') }" />
          </div>
        </div>

        <div v-if="route.path === '/alvos/rede'" class="contextual-filters">
          <div class="filter-section mini">
            <label class="filter-label sm">CPF/CNPJ Alvo</label>
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
        :disabled="filtersLocked"
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

.sidebar-header {
  padding: 1.5rem;
  display: flex;
  align-items: center;
  justify-content: space-between;
  border-bottom: 1px solid var(--sidebar-border);
}

.brand {
  display: flex;
  align-items: center;
  gap: 1rem;
}

.logo-img {
  width: 52px;
  filter: var(--logo-filter);
}

:global(.dark-mode) .logo-img  { --logo-filter: none; }
:global(.light-mode) .logo-img { --logo-filter: none; }

.brand-name {
  font-weight: 700;
  font-size: 1.2rem;
  display: block;
  color: var(--sidebar-text);
}

.brand-version {
  font-size: 0.7rem;
  opacity: 0.7;
  color: var(--sidebar-text);
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

.filters-locked-banner {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.45rem 0.65rem;
  margin-bottom: 0.75rem;
  background: color-mix(in srgb, var(--primary-color) 8%, var(--card-bg));
  border: 1px solid color-mix(in srgb, var(--primary-color) 20%, transparent);
  border-radius: 8px;
  font-size: 0.65rem;
  font-weight: 600;
  color: var(--primary-color);
  opacity: 0.85;
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
:deep(.p-calendar) {
  height: 32px;
  align-items: center;
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
  margin-top: 12px !important;
}

.filter-input { margin-bottom: 4px !important; }

.slider-tip {
  position: absolute;
  top: 16px;
  transform: translateX(-50%);
  background: var(--sidebar-input-bg);
  color: var(--sidebar-text);
  border: 1px solid var(--sidebar-border);
  padding: 3px 7px;
  border-radius: 4px;
  font-size: 0.7rem;
  font-weight: 700;
  pointer-events: none;
  z-index: 10;
  white-space: nowrap;
  box-shadow: 0 2px 6px rgba(0, 0, 0, 0.15);
}

.slider-tip::after {
  content: '';
  position: absolute;
  top: -4px;
  left: 50%;
  transform: translateX(-50%);
  border-left: 3px solid transparent;
  border-right: 3px solid transparent;
  border-bottom: 4px solid var(--sidebar-border);
}

:deep(.p-slider) {
  background: var(--sidebar-border);
  height: 4px !important;
}

:deep(.p-slider .p-slider-range) { background: var(--sidebar-border) !important; }

:deep(.p-slider-handle) {
  border: 2px solid var(--primary-color) !important;
  background: color-mix(in srgb, var(--sidebar-bg) 60%, transparent) !important;
  width: 14px !important;
  height: 14px !important;
  margin-top: -6px !important;
  transition: background 0.2s, box-shadow 0.2s;
}

:deep(.p-slider:not(.p-disabled) .p-slider-handle:hover) {
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
  background: transparent !important;
  border-color: var(--primary-color) !important;
  color: var(--primary-color) !important;
  animation: pulse-filter 1.5s ease-in-out infinite !important;
}

:deep(.filters-active.p-button:hover) {
  background: color-mix(in srgb, var(--primary-color) 12%, transparent) !important;
  border-color: var(--primary-color) !important;
  color: var(--primary-color) !important;
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
</style>
