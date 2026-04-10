```
<script setup>
import { ref, onMounted, onUnmounted, computed, watch } from "vue";
import { useRoute, useRouter } from "vue-router";
import {
  SYSTEM_MODULES as modules,
  FILTER_DEFAULTS,
  FILTER_ALL_VALUE,
  ANALYSIS_YEARS,
  TIMING,
} from "@/config/constants";
import { useThemeStore } from "@/stores/theme";
import { useFilterStore } from "@/stores/filters";
import { useRecentCnpjStore } from "@/stores/recentCnpj";
import { useGeoStore } from "@/stores/geo";
import { useFarmaciaListsStore } from "@/stores/farmaciaLists";
import { useFormatting } from "@/composables/useFormatting";
import { useSliderPeriodLogic } from "@/composables/useSliderPeriodLogic";
import { useSyncManager } from "@/composables/useSyncManager";
import Button from "primevue/button";
import ThemeSelector from "@/components/ThemeSelector.vue";
import { FILTER_OPTIONS } from "@/config/filterOptions";
import Dropdown from "primevue/dropdown";
import Slider from "primevue/slider";
import InputText from "primevue/inputtext";
import Dialog from "primevue/dialog";
import ProgressBar from "primevue/progressbar";
import SelectButton from "primevue/selectbutton";

const themeStore = useThemeStore();
const filterStore = useFilterStore();
const filtersLocked = computed(() => filterStore.filtersLocked);
const recentCnpjStore = useRecentCnpjStore();
const recentCnpj = computed(() => recentCnpjStore.recent);
const geoStore = useGeoStore();
const farmaciaLists = useFarmaciaListsStore();
const totalListas = computed(() => farmaciaLists.interesse.length);
const route = useRoute();
const router = useRouter();

const activeModule = ref("consolidado");

// Abas dinâmicas baseadas no módulo selecionado
const tabs = computed(() => {
  if (activeModule.value === "consolidado") {
    return [
      { label: "Nacional", path: "/" },
      { label: "Municípios", path: "/municipio" },
      { label: "Farmácias", path: "/cnpj" },
      { label: "Indicadores", path: "/indicadores" },
      { label: "Dispersão Benefício", path: "/dispersao-beneficio" },
    ];
  } else {
    return [
      { label: "Mapa-Cluster", path: "/alvos/cluster" },
      { label: "Situação CNPJ", path: "/alvos/situacao" },
      { label: "Variação Produção", path: "/alvos/variacao" },
      { label: "Rede de Sócios", path: "/alvos/rede" },
    ];
  }
});

// Sincronizar activeModule com a rota atual ao carregar
onMounted(() => {
  themeStore.initTheme();
  if (route.path.startsWith("/alvos")) {
    activeModule.value = "alvos";
  }
  applySliderPeriod(timeSliderValue.value);
});

// Watch para mudar a rota padrão ao trocar de módulo
watch(activeModule, (newVal) => {
  if (
    newVal === "consolidado" &&
    !route.path.match(
      /^\/(?:dispersao-beneficio|dispersao|municipio|empresa|cnpj|$)/,
    )
  ) {
    router.push("/");
  } else if (newVal === "alvos" && !route.path.startsWith("/alvos")) {
    router.push("/alvos/cluster");
  }
});

// Opções dos Selects (Estáticos para Mock)
const ufOptions = computed(() => geoStore.ufs);
const regiaoSaudeOptions = computed(() =>
  geoStore.regioesPorUF(filterStore.selectedUF),
);
const municipioOptions = computed(() =>
  geoStore.municipiosPorFiltro(
    filterStore.selectedUF,
    filterStore.selectedRegiaoSaude,
  ),
);

// Reseta filtros dependentes de forma inteligente (Só se a seleção atual se tornar inválida)
watch(
  () => filterStore.selectedUF,
  (newUF) => {
    const regioesDisponiveis = geoStore.regioesPorUF(newUF);
    if (!regioesDisponiveis.includes(filterStore.selectedRegiaoSaude)) {
      filterStore.selectedRegiaoSaude = "Todos";
    }

    const municipiosDisponiveis = geoStore.municipiosPorFiltro(
      newUF,
      filterStore.selectedRegiaoSaude,
    );
    // Muda de .includes() para .some() ou .find() pois agora é uma lista de objetos { label, value }
    if (
      !municipiosDisponiveis.some(
        (m) => m.value === filterStore.selectedMunicipio,
      )
    ) {
      filterStore.selectedMunicipio = "Todos";
    }
  },
);

watch(
  () => filterStore.selectedRegiaoSaude,
  (newRegiao) => {
    const municipiosDisponiveis = geoStore.municipiosPorFiltro(
      filterStore.selectedUF,
      newRegiao,
    );
    if (
      !municipiosDisponiveis.some(
        (m) => m.value === filterStore.selectedMunicipio,
      )
    ) {
      filterStore.selectedMunicipio = "Todos";
    }
  },
);
const situacaoOptions = FILTER_OPTIONS.situacao;
const msOptions = FILTER_OPTIONS.ms;
const porteOptions = FILTER_OPTIONS.porte;
const grandeRedeOptions = FILTER_OPTIONS.grandeRede;
const clusterOptions = FILTER_OPTIONS.cluster;
const rfaOptions = FILTER_OPTIONS.rfa;

const { formatBRL: formatCurrency } = useFormatting();
const {
  isSyncing,
  showConfirmSync,
  syncProgress,
  syncStatus,
  syncError,
  syncErrorMessage,
  handleSync,
  retrySync,
  dismissError,
} = useSyncManager();

// ── Navbar: busca rápida por CNPJ completo ────────────────────────────────────
const navCnpjInput = ref('');

watch(navCnpjInput, (val) => {
  const digits = val.replace(/\D/g, '');
  if (digits.length === 14) {
    navCnpjInput.value = '';
    router.push(`/estabelecimento/${digits}`);
  }
});

// ── Dialog: CNPJ completo detectado ──────────────────────────────────────────
const showCnpjDialog    = ref(false);
const cnpjCompletoDetectado = ref('');

const formatCnpjMask = (v) => {
  const d = v.replace(/\D/g, '');
  return d.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/, '$1.$2.$3/$4-$5');
};

watch(() => filterStore.selectedCnpjRaiz, (val) => {
  const digits = val.replace(/\D/g, '');
  if (digits.length === 14) {
    cnpjCompletoDetectado.value = digits;
    showCnpjDialog.value = true;
  }
});

const onCnpjDialogKeydown = (e) => {
  if (showCnpjDialog.value && e.key === 'Enter') {
    e.preventDefault();
    abrirDetalhamento();
  }
};

onMounted(() => window.addEventListener('keydown', onCnpjDialogKeydown));
onUnmounted(() => window.removeEventListener('keydown', onCnpjDialogKeydown));

const abrirDetalhamento = () => {
  showCnpjDialog.value = false;
  filterStore.selectedCnpjRaiz = '';
  router.push(`/estabelecimento/${cnpjCompletoDetectado.value}`);
};

const usarComoFiltro = () => {
  showCnpjDialog.value = false;
};

// Controle de Menu — sincronizado com a store para sobreviver a trocas de rota
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

// Rotas que bloqueiam filtros e colapsam a sidebar
const LOCKED_ROUTES = ['/estabelecimento/', '/listas'];
const isLockedRoute = (path) => LOCKED_ROUTES.some(r => path.startsWith(r));

watch(() => route.path, (path) => {
  const locked = isLockedRoute(path);
  filterStore.filtersLocked = locked;
  // Respeita o lock do usuário: só altera sidebarCollapsed se não estiver travado
  if (!filterStore.sidebarLocked) {
    filterStore.sidebarCollapsed = locked;
  }
}, { immediate: true });

const limparFiltros = () => {
  filterStore.resetFilters();
  filterStore.selectedCnpjRaiz = "";
  resetYears();
};

const applyPercentualNaoComprovacao = () => {
  filterStore.percentualNaoComprovacaoFilter = [
    ...filterStore.percentualNaoComprovacaoRange,
  ];
};

// MÁGICA: Função para forçar o foco no campo de busca do Dropdown ao abrir
const onDropdownShow = () => {
  setTimeout(() => {
    const input = document.querySelector(".p-dropdown-filter");
    if (input) input.focus();
  }, TIMING.DROPDOWN_FOCUS_DELAY);
};

// 🎯 LÓGICA DE FILTRO ATIVO: Detecta se o valor mudou em relação ao padrão (Busca no constants.js)
const isFilterActive = (field) => {
  const value = filterStore[field];

  // Mapeamento das chaves do store para as chaves do constants.js
  const mapStoreToConstants = {
    selectedUF: FILTER_DEFAULTS.UF,
    selectedRegiaoSaude: FILTER_DEFAULTS.REGIAO,
    selectedMunicipio: FILTER_DEFAULTS.MUNICIPIO,
    selectedSituacao: FILTER_DEFAULTS.SITUACAO,
    selectedMS: FILTER_DEFAULTS.MS,
    selectedPorte: FILTER_DEFAULTS.PORTE,
    selectedGrandeRede: FILTER_DEFAULTS.GRANDE_REDE,
    selectedCnpjRaiz: "",
    percentualNaoComprovacaoRange: FILTER_DEFAULTS.PERCENTUAL_RANGE,
    valorMinSemComp: FILTER_DEFAULTS.VALOR_MIN,
    clusterSelection: FILTER_DEFAULTS.CLUSTER,
    rfaSelection: FILTER_DEFAULTS.RFA,
    searchTarget: FILTER_DEFAULTS.SEARCH,
    sliderValue: FILTER_DEFAULTS.SLIDER_INDEX_RANGE,
  };

  const defaultValue = mapStoreToConstants[field];

  if (Array.isArray(value)) {
    return JSON.stringify(value) !== JSON.stringify(defaultValue);
  }
  return value !== defaultValue;
};

const activeFilterCount = computed(() => {
  const fields = [
    "selectedUF",
    "selectedRegiaoSaude",
    "selectedMunicipio",
    "selectedSituacao",
    "selectedMS",
    "selectedPorte",
    "selectedGrandeRede",
    "selectedCnpjRaiz",
    "percentualNaoComprovacaoRange",
    "valorMinSemComp",
    "sliderValue",
    "clusterSelection",
    "rfaSelection",
    "searchTarget",
  ];
  return fields.filter((f) => isFilterActive(f)).length;
});

const applyValorMinSemComp = () => {
  filterStore.valorMinSemCompFilter = filterStore.valorMinSemComp;
};

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
</script>

<template>
  <div class="admin-layout" :class="{ collapsed: isCollapsed }">
    <!-- BOTÃO FLUTUANTE ÚNICO (ALÇA) — Segue a borda da sidebar -->
    <button
      class="sidebar-float-btn"
      @click="isCollapsed = !isCollapsed"
      :title="isCollapsed ? 'Abrir painel' : 'Fechar painel'"
    >
      <i :class="isCollapsed ? 'pi pi-angle-right' : 'pi pi-angle-left'"></i>
    </button>

    <!-- BOTÃO DE CADEADO — visível apenas quando colapsado -->
    <button
      class="sidebar-lock-btn"
      :class="{ locked: isSidebarLocked }"
      @click="toggleSidebarLock"
      :title="isSidebarLocked ? 'Sidebar travada — clique para destravar' : 'Travar sidebar colapsada'"
    >
      <i :class="isSidebarLocked ? 'pi pi-lock' : 'pi pi-lock-open'"></i>
    </button>

    <!-- BARRA LATERAL DE FILTROS & MÓDULOS -->
    <aside class="admin-sidebar">
      <div class="sidebar-header" title="Projeto Sentinela">
        <div class="brand">
          <img
            src="/img/logo_sentinela_transparente.png"
            alt="Sentinela V3"
            class="logo-img"
          />
          <div class="brand-text">
            <span class="brand-name">SENTINELA</span>
            <span class="brand-version">AUDITORIA NO FARMÁCIA POPULAR</span>
          </div>
        </div>
        <!-- Botão interno removido em favor da alça unificada -->
      </div>

      <div class="sidebar-content">
        <!-- BANNER DE FILTROS BLOQUEADOS -->
        <div v-if="filtersLocked" class="filters-locked-banner">
          <i class="pi pi-lock" />
          <span>Filtros indisponíveis durante a análise de um CNPJ</span>
        </div>

        <!-- 1. FILTROS GLOBAIS (SEMPRE PRESENTES) -->
        <div class="filter-section" :class="{ 'filter-locked': filtersLocked }">
          <label class="filter-label">
            UF
            <button
              v-if="isFilterActive('selectedUF')"
              class="filter-clear-btn"
              @click="filterStore.selectedUF = FILTER_ALL_VALUE"
              v-tooltip.right="'Limpar filtro'"
            >
              <i class="pi pi-eraser" />
            </button>
          </label>
          <Dropdown
            v-model="filterStore.selectedUF"
            :options="ufOptions"
            placeholder="Estado"
            class="w-full filter-input"
            panelClass="sidebar-panel"
            :class="{ 'filter-active': isFilterActive('selectedUF') }"
          />
        </div>

        <div class="filter-section" :class="{ 'filter-locked': filtersLocked }">
          <label class="filter-label">
            Região de Saúde
            <button
              v-if="isFilterActive('selectedRegiaoSaude')"
              class="filter-clear-btn"
              @click="filterStore.selectedRegiaoSaude = FILTER_ALL_VALUE"
              v-tooltip.right="'Limpar filtro'"
            >
              <i class="pi pi-eraser" />
            </button>
          </label>
          <Dropdown
            v-model="filterStore.selectedRegiaoSaude"
            :options="regiaoSaudeOptions"
            placeholder="Região"
            filter
            reset-filter-on-hide
            auto-option-focus
            filter-match-mode="contains"
            @show="onDropdownShow"
            :virtualScrollerOptions="{ itemSize: 32 }"
            panelClass="sidebar-panel"
            class="w-full filter-input"
            :class="{ 'filter-active': isFilterActive('selectedRegiaoSaude') }"
          />
        </div>

        <div class="filter-section" :class="{ 'filter-locked': filtersLocked }">
          <label class="filter-label">
            Município
            <button
              v-if="isFilterActive('selectedMunicipio')"
              class="filter-clear-btn"
              @click="filterStore.selectedMunicipio = FILTER_ALL_VALUE"
              v-tooltip.right="'Limpar filtro'"
            >
              <i class="pi pi-eraser" />
            </button>
          </label>
          <Dropdown
            v-model="filterStore.selectedMunicipio"
            :options="municipioOptions"
            placeholder="Município"
            filter
            optionLabel="label"
            optionValue="value"
            reset-filter-on-hide
            auto-option-focus
            filter-match-mode="contains"
            @show="onDropdownShow"
            :virtualScrollerOptions="{ itemSize: 32 }"
            panelClass="sidebar-panel"
            class="w-full filter-input"
            :class="{ 'filter-active': isFilterActive('selectedMunicipio') }"
          />
        </div>

        <div class="grid-filters" :class="{ 'filter-locked': filtersLocked }">
          <div class="filter-section">
            <label class="filter-label">Situação RF</label>
            <Dropdown
              v-model="filterStore.selectedSituacao"
              :options="situacaoOptions"
              class="w-full filter-input"
              panelClass="sidebar-panel"
              :class="{ 'filter-active': isFilterActive('selectedSituacao') }"
            />
          </div>
          <div class="filter-section">
            <label class="filter-label">Conexão MS</label>
            <Dropdown
              v-model="filterStore.selectedMS"
              :options="msOptions"
              class="w-full filter-input"
              panelClass="sidebar-panel"
              :class="{ 'filter-active': isFilterActive('selectedMS') }"
            />
          </div>
        </div>

        <div class="grid-filters" :class="{ 'filter-locked': filtersLocked }">
          <div class="filter-section">
            <label class="filter-label">Porte CNPJ</label>
            <Dropdown
              v-model="filterStore.selectedPorte"
              :options="porteOptions"
              class="w-full filter-input"
              panelClass="sidebar-panel"
              :class="{ 'filter-active': isFilterActive('selectedPorte') }"
            />
          </div>
          <div class="filter-section">
            <label class="filter-label">Grande Rede</label>
            <Dropdown
              v-model="filterStore.selectedGrandeRede"
              :options="grandeRedeOptions"
              class="w-full filter-input"
              panelClass="sidebar-panel"
              :class="{ 'filter-active': isFilterActive('selectedGrandeRede') }"
            />
          </div>
        </div>

        <div class="filter-section" :class="{ 'filter-locked': filtersLocked }">
          <label class="filter-label">
            CNPJ
            <i
              class="pi pi-info-circle"
              style="
                font-size: 0.7rem;
                margin-left: 4px;
                opacity: 0.6;
                cursor: default;
              "
              v-tooltip.right="
                'Aceita CNPJ completo (14 dígitos) ou apenas a raiz (8 dígitos), com ou sem máscara. CNPJ completo filtra o estabelecimento exato; raiz filtra toda a rede.'
              "
            />
            <button
              v-if="isFilterActive('selectedCnpjRaiz')"
              class="filter-clear-btn"
              @click="filterStore.selectedCnpjRaiz = ''"
              v-tooltip.right="'Limpar filtro'"
            >
              <i class="pi pi-eraser" />
            </button>
          </label>
          <InputText
            v-model="filterStore.selectedCnpjRaiz"
            placeholder="Digite o CNPJ..."
            class="w-full filter-input"
            :class="{ 'filter-active': isFilterActive('selectedCnpjRaiz') }"
            :maxlength="18"
          />
        </div>

        <div class="filter-section" :class="{ 'filter-locked': filtersLocked }">
          <label class="filter-label">% de não comprovação</label>
          <div
            class="slider-container"
            :class="{
              'filter-active-box': isFilterActive(
                'percentualNaoComprovacaoRange',
              ),
            }"
          >
            <div class="perc-chips">
              <button
                v-for="v in [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]"
                :key="v"
                class="perc-chip"
                :class="{
                  'perc-chip-active':
                    filterStore.percentualNaoComprovacaoRange[0] === v,
                }"
                @click="
                  () => {
                    filterStore.percentualNaoComprovacaoRange = [v, 100];
                    applyPercentualNaoComprovacao();
                  }
                "
              >
                {{ v }}%
              </button>
            </div>
            <div class="slider-values">
              <span>{{ filterStore.percentualNaoComprovacaoRange[0] }}%</span>
              <span>{{ filterStore.percentualNaoComprovacaoRange[1] }}%</span>
            </div>
            <Slider
              v-model="filterStore.percentualNaoComprovacaoRange"
              range
              class="w-full"
              @slideend="applyPercentualNaoComprovacao"
            />
          </div>
        </div>

        <div class="filter-section">
          <label class="filter-label">Período de Análise</label>
          <div
            class="slider-container"
            :class="{ 'filter-active-box': isFilterActive('sliderValue') }"
          >
            <!-- 1. Atalhos Rápidos de Ano -->
            <div class="perc-chips" style="margin-bottom: 0.5rem">
              <button
                v-for="year in ANALYSIS_YEARS"
                :key="year"
                class="perc-chip"
                :class="{
                  'perc-chip-active': isYearActive(year),
                  'perc-chip-disabled': isYearDisabled(year),
                }"
                :disabled="isYearDisabled(year)"
                @click="toggleYear(year)"
              >
                {{ year }}
              </button>
            </div>

            <!-- 2. Time Slider (Para varredura rápida) com Tooltips Flutuantes -->
            <div class="slider-wrapper relative pt-3 mt-0">
              <div
                class="slider-tip"
                :style="{ left: startPos + '%', transform: startTransform }"
              >
                {{ startMonthLabel }}
              </div>
              <div
                class="slider-tip"
                :style="{ left: endPos + '%', transform: endTransform }"
              >
                {{ endMonthLabel }}
              </div>

              <Slider
                v-model="timeSliderValue"
                range
                :min="0"
                :max="availableMonths.length - 1"
                class="w-full time-slider"
                @slideend="
                  () => {
                    applySliderPeriod(timeSliderValue);
                  }
                "
              />
            </div>
          </div>
        </div>

        <div class="filter-section" style="margin-top: 1.8rem" :class="{ 'filter-locked': filtersLocked }">
          <label class="filter-label">Valor mínimo sem comprovação</label>
          <div
            class="slider-container"
            :class="{ 'filter-active-box': isFilterActive('valorMinSemComp') }"
          >
            <div class="slider-values">
              <span>{{ formatCurrency(filterStore.valorMinSemComp) }}</span>
            </div>
            <Slider
              v-model="filterStore.valorMinSemComp"
              :min="0"
              :max="FILTER_DEFAULTS.VALOR_MAX"
              :step="1000"
              class="w-full"
              @slideend="applyValorMinSemComp"
            />
          </div>
        </div>

        <hr class="sidebar-divider my-4" />

        <!-- 2. FILTROS CONTEXTUAIS (DENTRO DO LAYOUT PARA GARANTIR RENDERIZAÇÃO) -->
        <div class="dynamic-filters-box" :class="{ 'filter-locked': filtersLocked }">
          <div class="filter-header">
            <i class="pi pi-filter"></i>
            <span>Filtros da Página</span>
          </div>

          <!-- Filtros para MAPA-CLUSTER -->
          <div
            v-if="route.path === '/alvos/cluster'"
            class="contextual-filters"
          >
            <div class="filter-section mini">
              <label class="filter-label sm">Busca Alvo</label>
              <InputText
                v-model="filterStore.searchTarget"
                placeholder="ID/CNPJ..."
                class="w-full filter-input sm"
                :class="{ 'filter-active': isFilterActive('searchTarget') }"
              />
            </div>
            <div class="filter-section mini">
              <label class="filter-label sm">Target Cluster</label>
              <Dropdown
                v-model="filterStore.clusterSelection"
                :options="clusterOptions"
                class="w-full filter-input sm"
                panelClass="sidebar-panel"
                :class="{ 'filter-active': isFilterActive('clusterSelection') }"
              />
            </div>
            <div class="filter-section mini">
              <label class="filter-label sm">Risco (RFA)</label>
              <Dropdown
                v-model="filterStore.rfaSelection"
                :options="rfaOptions"
                class="w-full filter-input sm"
                panelClass="sidebar-panel"
                :class="{ 'filter-active': isFilterActive('rfaSelection') }"
              />
            </div>
          </div>

          <!-- Filtros para REDE DE SÓCIOS -->
          <div v-if="route.path === '/alvos/rede'" class="contextual-filters">
            <div class="filter-section mini">
              <label class="filter-label sm">CPF/CNPJ Alvo</label>
              <InputText
                v-model="filterStore.searchTarget"
                placeholder="Pesquisar rede..."
                class="w-full filter-input sm"
              />
            </div>
          </div>

          <!-- Filtros para DASHBOARD (CONSOLIDADO) -->
          <div v-if="activeModule === 'consolidado'" class="contextual-filters">
            <p
              class="text-xs px-2 italic"
              style="color: var(--sidebar-text); opacity: 0.7"
            >
              Nenhum filtro extra necessário.
            </p>
          </div>
        </div>

        <div class="sidebar-spacer"></div>
      </div>

      <div class="sidebar-footer">
        <Button
          :label="
            activeFilterCount > 0
              ? `Limpar Filtros (${activeFilterCount})`
              : 'Limpar Filtros'
          "
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

    <!-- ÁREA DE CONTEÚDO PRINCIPAL (NAVBAR + VIEW) -->
    <main class="main-container">
      <nav class="top-navbar">
        <div class="nav-left">
          <SelectButton
            v-model="activeModule"
            :options="modules"
            optionLabel="name"
            optionValue="value"
            class="module-select-button"
          >
            <template #option="slotProps">
              <i
                :class="slotProps.option.icon"
                style="margin-right: 0.5rem; font-size: 0.9rem"
              ></i>
              <span
                style="
                  font-size: 0.75rem;
                  font-weight: 700;
                  text-transform: uppercase;
                  letter-spacing: 0.3px;
                "
                >{{ slotProps.option.name }}</span
              >
            </template>
          </SelectButton>

          <div class="nav-divider"></div>

          <div class="nav-tabs">
            <router-link
              v-for="tab in tabs"
              :key="tab.path"
              :to="tab.path"
              class="nav-tab"
              :class="{ active: route.path === tab.path }"
            >
              {{ tab.label }}
            </router-link>

            <!-- Atalho: último CNPJ analisado -->
            <div v-if="recentCnpj" class="nav-recent-wrapper">
              <router-link
                :to="`/estabelecimento/${recentCnpj.cnpj}`"
                class="nav-tab nav-recent-cnpj"
                :class="{ active: route.path.startsWith('/estabelecimento') }"
                v-tooltip.bottom="recentCnpj.razaoSocial"
              >
                <i class="pi pi-history" />
                {{ recentCnpj.cnpj.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/, '$1.$2.$3/$4-$5') }}
              </router-link>
              <button class="nav-recent-clear" @click.prevent="recentCnpjStore.clear()" v-tooltip.bottom="'Limpar atalho'">
                <i class="pi pi-times" />
              </button>
            </div>
          </div>
        </div>
        <div class="nav-actions">
          <div class="nav-cnpj-search">
            <i class="pi pi-search nav-cnpj-icon" />
            <InputText
              v-model="navCnpjInput"
              placeholder="CNPJ (14 dígitos)"
              class="nav-cnpj-input"
              maxlength="18"
            />
          </div>
          <ThemeSelector />
          <div
            class="lists-nav-btn"
            @click="router.push('/listas')"
            v-tooltip.bottom="'Farmácias Monitoradas'"
          >
            <i class="pi pi-bookmark" />
            <span v-if="totalListas > 0" class="lists-nav-badge">{{
              totalListas
            }}</span>
          </div>
          <Button
            icon="pi pi-refresh"
            text
            rounded
            severity="secondary"
            v-tooltip.bottom="'Sincronizar com CGUData'"
            @click="showConfirmSync = true"
          />
        </div>
      </nav>

      <!-- DIALOG DE CONFIRMAÇÃO -->
      <!-- DIALOG: CNPJ COMPLETO DETECTADO -->
      <Dialog
        v-model:visible="showCnpjDialog"
        header="Abrir detalhamento?"
        :style="{ width: '340px' }"
        modal
      >
        <p style="font-size: 0.9rem; margin: 0;">
          Deseja abrir o detalhamento do CNPJ <strong>{{ formatCnpjMask(cnpjCompletoDetectado) }}</strong>?
        </p>
        <template #footer>
          <button class="cnpj-dialog-btn cnpj-dialog-btn--cancel" @click="usarComoFiltro">Não</button>
          <button class="cnpj-dialog-btn cnpj-dialog-btn--confirm" @click="abrirDetalhamento">
            <i class="pi pi-arrow-right" /> Abrir Detalhamento
          </button>
        </template>
      </Dialog>

      <Dialog
        v-model:visible="showConfirmSync"
        header="Sincronizar Dados"
        :style="{ width: '400px' }"
        modal
        :closable="!isSyncing"
      >
        <div class="flex flex-col items-center gap-4 text-center p-2">
          <i
            class="pi pi-exclamation-triangle text-amber-500"
            style="font-size: 3rem"
          ></i>
          <p class="mt-2">
            Deseja realmente iniciar a sincronização com os dados do
            <strong>CGUData</strong>?
          </p>
          <p class="text-sm text-gray-500">
            Este processo irá atualizar todos os caches do sistema com as
            informações mais recentes do banco de dados.
          </p>
        </div>
        <template #footer>
          <Button
            label="Cancelar"
            icon="pi pi-times"
            text
            severity="secondary"
            @click="showConfirmSync = false"
          />
          <Button
            label="Sincronizar Agora"
            icon="pi pi-sync"
            severity="primary"
            @click="handleSync"
          />
        </template>
      </Dialog>

      <!-- MODAL DE PROCESSAMENTO (SYNCING) -->
      <Dialog
        v-model:visible="isSyncing"
        modal
        :closable="false"
        :draggable="false"
        :show-header="false"
        :style="{ width: '460px' }"
      >
        <div class="sync-modal-content">
          <!-- ── ESTADO: PROGRESSO ── -->
          <template v-if="!syncError">
            <div class="sync-icon-container">
              <i class="pi pi-sync pi-spin"></i>
            </div>
            <h3>Sincronizando com CGUData</h3>
            <p>
              O sistema está reconstruindo os arquivos de cache para garantir
              máxima performance. Por favor, aguarde.
            </p>
            <div class="progress-wrapper">
              <div
                style="
                  display: flex;
                  justify-content: space-between;
                  margin-bottom: 0.5rem;
                  font-size: 0.7rem;
                  font-weight: 800;
                  color: var(--primary-color);
                  letter-spacing: 0.5px;
                "
              >
                <span>{{
                  syncStatus
                    ? syncStatus.toUpperCase()
                    : "PROCESSANDO REGISTROS"
                }}</span>
                <span>{{ syncProgress }}%</span>
              </div>
              <ProgressBar
                :value="syncProgress"
                :show-value="false"
                style="height: 10px"
              ></ProgressBar>
            </div>
            <span class="status-minor">Não feche esta janela...</span>
          </template>

          <!-- ── ESTADO: ERRO ── -->
          <template v-else>
            <div class="sync-icon-container sync-error-icon">
              <i class="pi pi-times-circle"></i>
            </div>
            <h3 class="sync-error-title">Falha na Sincronização</h3>
            <p class="sync-error-msg">{{ syncErrorMessage }}</p>
            <div class="sync-error-actions">
              <Button
                label="Tentar Novamente"
                icon="pi pi-refresh"
                severity="primary"
                @click="retrySync"
              />
              <Button
                label="Fechar"
                icon="pi pi-times"
                severity="secondary"
                outlined
                @click="dismissError"
              />
            </div>
          </template>
        </div>
      </Dialog>

      <div class="page-content">
        <router-view v-slot="{ Component }">
          <Transition name="page-fade" mode="out-in">
            <component :is="Component" />
          </Transition>
        </router-view>
      </div>
    </main>
  </div>
</template>

<style scoped>
.lists-nav-btn {
  position: relative;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 36px;
  height: 36px;
  border-radius: 6px;
  cursor: pointer;
  color: var(--text-secondary);
  transition: all 0.15s ease;
}

.lists-nav-btn:hover {
  background: color-mix(in srgb, var(--text-color) 8%, transparent);
  color: var(--text-color);
}

.lists-nav-btn i {
  font-size: 1rem;
}

.lists-nav-badge {
  position: absolute;
  top: 2px;
  right: 2px;
  min-width: 16px;
  height: 16px;
  padding: 0 4px;
  font-size: 0.68rem;
  font-weight: 700;
  border-radius: 10px;
  background: var(--primary-color);
  color: #fff;
  display: flex;
  align-items: center;
  justify-content: center;
  line-height: 1;
}

/* SISTEMA DE CORES DINÂMICO (DNA ARBFLOW) */
.admin-layout {
  --sidebar-width: 280px;
  display: flex !important;
  height: 100vh !important;
  width: 100vw;
  overflow: hidden;
  color: var(--text-color);
  scrollbar-gutter: stable;
  /* Responde diretamente ao bg-color do themeConfig.js */
  background: var(--bg-color) !important;
}

.admin-layout.collapsed {
  --sidebar-width: 0px; /* Zera a largura na variável */
}

/* SIDEBAR */
.admin-sidebar {
  width: var(--sidebar-width);
  background: var(--sidebar-bg) !important;
  color: var(--sidebar-text);
  transition: width 0.35s cubic-bezier(0.4, 0, 0.2, 1);
  will-change: width;
  display: flex;
  flex-direction: column;
  height: 100vh;
  border-right: 1px solid var(--sidebar-border);
  flex-shrink: 0;
  overflow: hidden;
}

.admin-layout.collapsed .admin-sidebar {
  width: var(--sidebar-width);
  border-right: none;
}

/* Conteúdo: esmaece rápido ao colapsar, aparece com delay ao expandir */
.sidebar-content,
.sidebar-footer {
  opacity: 1;
  pointer-events: auto;
  transition: opacity 0.2s 0.25s ease; /* delay = sidebar já abriu */
}

.admin-layout.collapsed .sidebar-content,
.admin-layout.collapsed .sidebar-footer {
  opacity: 0;
  pointer-events: none;
  transition: opacity 0.15s ease; /* rápido, sem delay — esmaece antes de encolher */
}

/* BOTÃO FLUTUANTE DE REABERTURA */
.sidebar-float-btn {
  position: fixed;
  top: 50%;
  left: var(--sidebar-width); /* MÁGICA: O botão persegue a borda da sidebar */
  transform: translateY(-50%);
  z-index: 300;
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

.sidebar-float-btn i {
  font-size: 0.8rem;
}

/* BOTÃO DE CADEADO */
.sidebar-lock-btn {
  position: fixed;
  top: calc(50% + 28px); /* logo abaixo do float-btn */
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

.sidebar-lock-btn:hover {
  width: 28px;
  box-shadow: 6px 0 15px rgba(0, 0, 0, 0.15);
}

.sidebar-lock-btn.locked {
  opacity: 1;
  color: var(--primary-color);
  background: color-mix(in srgb, var(--primary-color) 12%, var(--sidebar-bg));
}

.sidebar-lock-btn i {
  font-size: 0.8rem;
}

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
  /* Logo mudando de cor conforme o tema */
  filter: var(--logo-filter);
}

:global(.dark-mode) .logo-img {
  --logo-filter: none;
}
:global(.light-mode) .logo-img {
  --logo-filter: none;
}

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
  gap: 0.75rem; /* Reduzido de 1.5rem */
  overflow-y: auto;
  overflow-x: hidden;
  --scrollbar-track: var(--sidebar-bg);
  --scrollbar-thumb: rgba(255, 255, 255, 0.15);
  --scrollbar-thumb-hover: rgba(255, 255, 255, 0.3);
}

.filter-section {
  margin-bottom: 0.35rem;
}

/* Estado bloqueado — análise por CNPJ */
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

.filters-locked-banner .pi {
  font-size: 0.7rem;
}

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

.filter-input-row {
  display: flex;
  align-items: center;
  gap: 0.25rem;
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

.filter-clear-btn:hover {
  opacity: 1;
}

.filter-clear-btn .pi {
  font-size: 0.75rem;
}

/* COMPONENTES COMPACTOS DO PRIMEVUE */
:deep(.filter-input .p-inputtext),
:deep(.filter-input .p-dropdown-label),
:deep(.filter-input .p-calendar .p-inputtext),
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

:deep(.p-calendar .p-inputtext) {
  height: 100%;
  box-sizing: border-box;
}

:deep(.p-calendar-trigger) {
  width: 32px;
  height: 100%;
}

.grid-filters {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 0.5rem;
}

.grid-filters .filter-section {
  min-width: 0;
}

.grid-filters :deep(.p-dropdown-label) {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.slider-container {
  padding: 0.5rem 0.2rem;
}

.slider-values {
  display: flex;
  justify-content: space-between;
  font-size: 0.65rem;
  font-weight: 700;
  margin-bottom: 0.4rem;
  color: var(--sidebar-text);
}

.slider-values.period {
  display: flex;
  justify-content: space-between;
  align-items: center;
  font-size: 0.75rem;
  font-weight: 800;
  margin-bottom: 0.75rem;
  color: var(--primary-color);
  background: color-mix(in srgb, var(--primary-color) 8%, transparent);
  padding: 0.45rem 0.6rem;
  border-radius: 8px;
  border: 1px solid color-mix(in srgb, var(--primary-color) 20%, transparent);
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

.perc-chip-active {
  border-color: var(--primary-color) !important;
  color: var(--primary-color) !important;
  background: color-mix(
    in srgb,
    var(--primary-color) 14%,
    transparent
  ) !important;
  box-shadow: 0 0 6px color-mix(in srgb, var(--primary-color) 20%, transparent);
}

.perc-chip-disabled {
  opacity: 0.25;
  cursor: not-allowed;
  pointer-events: none;
}

.perc-chip:focus {
  outline: none;
}

.year-btn {
  font-size: 0.75rem !important;
  padding: 0.4rem 0.75rem !important;
  font-weight: 700 !important;
  border: 1px solid var(--sidebar-border) !important;
  border-radius: 8px !important;
  color: var(--sidebar-text) !important;
  background: var(--sidebar-input-bg) !important;
  text-transform: uppercase;
  transition: all 0.2s ease;
}

.year-btn:hover {
  border-color: var(--primary-color) !important;
  color: var(--primary-color) !important;
  background: rgba(255, 255, 255, 0.05) !important;
}

.year-btn.year-active {
  border-color: var(--primary-color) !important;
  color: var(--primary-color) !important;
  background: color-mix(
    in srgb,
    var(--primary-color) 12%,
    transparent
  ) !important;
  font-weight: 800 !important;
  box-shadow: 0 0 6px color-mix(in srgb, var(--primary-color) 20%, transparent) !important;
}

/* REMOVER BORDA BRANCA DE FOCO (RIDÍCULO) */
.year-btn:focus,
.year-btn:active,
.year-btn:focus-visible {
  outline: none !important;
  box-shadow: none !important;
  border-color: var(--sidebar-border) !important;
}

/* Se estiver ativo e focado, mantém a cor do tema, não branco */
.year-btn.year-active:focus {
  border-color: var(--primary-color) !important;
}

:deep(.clear-filters-btn.p-button) {
  background: transparent !important;
  transition: all 0.2s ease !important;
}

:deep(.clear-filters-btn.p-button:hover) {
  background: transparent !important;
  border-color: color-mix(
    in srgb,
    var(--primary-color) 50%,
    transparent
  ) !important;
  color: var(--primary-color) !important;
}

:deep(.clear-filters-btn.p-button:focus),
:deep(.clear-filters-btn.p-button:active) {
  outline: none !important;
  box-shadow: none !important;
}

:deep(.clear-filters-btn.p-button:focus-visible) {
  box-shadow: 0 0 0 2px var(--primary-color) !important;
}

/* Estado: filtros ativos */
:deep(.filters-active.p-button) {
  background: transparent !important;
  border-color: var(--primary-color) !important;
  color: var(--primary-color) !important;
  animation: pulse-filter 1.5s ease-in-out infinite !important;
}

:deep(.filters-active.p-button:hover) {
  background: color-mix(
    in srgb,
    var(--primary-color) 12%,
    transparent
  ) !important;
  border-color: var(--primary-color) !important;
  color: var(--primary-color) !important;
}

@keyframes pulse-filter {
  0%,
  100% {
    box-shadow: 0 0 0 0
      color-mix(in srgb, var(--primary-color) 25%, transparent);
  }
  50% {
    box-shadow: 0 0 0 6px
      color-mix(in srgb, var(--primary-color) 0%, transparent);
  }
}

/* Removido estilo do dropdown antigo */

/* TOOLTIPS DO SLIDER */
.slider-wrapper {
  position: relative;
  margin-top: 12px !important; /* Espaço equilibrado */
}

.filter-input {
  margin-bottom: 4px !important;
}

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
  content: "";
  position: absolute;
  top: -4px;
  left: 50%;
  transform: translateX(-50%);
  border-left: 3px solid transparent;
  border-right: 3px solid transparent;
  border-bottom: 4px solid var(--sidebar-border);
}

/* CUSTOMIZAÇÃO DOS SLIDERS (Tema Adaptativo) */
:deep(.p-slider) {
  background: var(--sidebar-border);
  height: 4px !important;
}

:deep(.p-slider .p-slider-range) {
  background: var(--sidebar-border) !important;
}

:deep(.p-slider-handle) {
  border: 2px solid var(--primary-color) !important;
  background: color-mix(in srgb, var(--sidebar-bg) 60%, transparent) !important;
  width: 14px !important;
  height: 14px !important;
  margin-top: -6px !important;
  transition:
    background 0.2s,
    box-shadow 0.2s;
}

:deep(.p-slider:not(.p-disabled) .p-slider-handle:hover) {
  background: var(--primary-color) !important;
  box-shadow: 0 0 0 6px
    color-mix(in srgb, var(--primary-color) 20%, transparent) !important;
}

.sidebar-divider {
  border: 0;
  border-top: 1px solid var(--sidebar-border);
  opacity: 0.5;
  margin: 0.5rem 0;
}

/* SELETOR DE MÓDULO */
.module-selector .filter-label {
  color: var(--text-color);
}

:deep(.custom-listbox) {
  background: transparent;
  border: 1px solid var(--sidebar-border);
}

:deep(.custom-listbox .p-listbox-list) {
  padding: 0.25rem;
}

:deep(.custom-listbox .p-listbox-item) {
  padding: 0.75rem;
  border-radius: 8px;
  margin-bottom: 0.25rem;
  transition: all 0.2s;
  font-weight: 500;
}

:deep(.custom-listbox .p-listbox-item.p-highlight) {
  background: var(--primary-color);
  color: var(--color-on-primary);
}

:deep(.custom-listbox .p-listbox-item:not(.p-highlight):hover) {
  background: color-mix(in srgb, var(--primary-color) 10%, transparent);
}

.sidebar-spacer {
  flex: 1;
}

/* DYNAMIC FILTERS AREA */
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

.filter-header i {
  color: var(--primary-color);
  font-size: 0.9rem;
}
.filter-header span {
  font-size: 0.75rem;
  font-weight: 800;
  text-transform: uppercase;
  color: var(--sidebar-text);
  letter-spacing: 0.5px;
}

.filter-section.mini {
  margin-bottom: 1rem;
  padding: 0 0.5rem;
}

.filter-label.sm {
  font-size: 0.7rem;
  opacity: 0.8;
  margin-bottom: 0.4rem;
}

:deep(.filter-input.sm .p-inputtext),
:deep(.filter-input.sm .p-dropdown-label) {
  padding: 0.5rem;
  font-size: 0.8rem;
}

.sidebar-footer {
  padding: 1rem;
}

/* MAIN CONTENT */
.main-container {
  flex: 1;
  display: flex;
  flex-direction: column;
  height: 100vh;
  overflow-y: auto;
  scrollbar-gutter: stable;
  min-width: 0;
  background: transparent !important; /* MÁGICA: Revela o fundo do layout vindo do themeConfig.js */
}

/* DESTAQUE DE FILTRO ATIVO E FOCO (IMPEDE O HALO SÓLIDO DO PRIMEVUE E BORDA DUPLA) */
:global(.admin-sidebar .p-dropdown.p-focus),
:global(.admin-sidebar .p-calendar.p-focus),
:global(.admin-sidebar .p-inputtext:not(.p-dropdown-label):focus),
:global(.admin-sidebar .filter-active.p-dropdown),
:global(.admin-sidebar .filter-active.p-calendar),
:global(.admin-sidebar .filter-active.p-inputtext:not(.p-dropdown-label)) {
  border: 2px solid color-mix(in srgb, var(--primary-color) 85%, transparent) !important;
  background: rgba(255, 255, 255, 0.05) !important;
  box-shadow: 0 0 0 2px
    color-mix(in srgb, var(--primary-color) 40%, transparent) !important;
  outline: none !important;
}

/* DESTAQUE PARA CONTAINERS (Sliders) */
.filter-active-box {
  background: color-mix(
    in srgb,
    var(--primary-color) 12%,
    transparent
  ) !important;
  border-radius: 4px;
}

.top-navbar {
  height: 56px;
  min-height: 56px;
  max-height: 56px;
  flex-shrink: 0;
  background: color-mix(in srgb, var(--navbar-bg) 75%, transparent);
  backdrop-filter: blur(20px) saturate(160%);
  -webkit-backdrop-filter: blur(20px) saturate(160%);
  border-bottom: 1px solid color-mix(in srgb, var(--navbar-border) 60%, transparent);
  box-shadow: 0 1px 0 color-mix(in srgb, var(--primary-color) 6%, transparent),
              inset 0 -1px 0 color-mix(in srgb, var(--navbar-border) 40%, transparent);
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 0 1.5rem;
  position: sticky;
  top: 0;
  z-index: 100;
  transition: background 0.3s ease, border-color 0.3s ease;
}

.nav-actions {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  flex-shrink: 0;
}

.nav-left {
  display: flex;
  align-items: center;
  gap: 1rem;
}

.nav-divider {
  width: 1px;
  height: 20px;
  background: color-mix(in srgb, var(--text-muted) 30%, transparent);
  flex-shrink: 0;
}

:deep(.module-select-button) {
  border-radius: 8px;
  overflow: hidden;
}

:deep(.module-select-button .p-button) {
  background: color-mix(in srgb, var(--text-muted) 8%, transparent);
  border-color: color-mix(in srgb, var(--text-muted) 20%, transparent);
  color: var(--text-secondary);
  padding: 0.35rem 0.7rem;
  font-size: 0.72rem;
  transition: all 0.2s;
}

:deep(.module-select-button .p-button:not(.p-highlight):hover) {
  background: color-mix(in srgb, var(--primary-color) 8%, transparent) !important;
  border-color: color-mix(in srgb, var(--primary-color) 30%, transparent) !important;
  color: var(--primary-color) !important;
}

:deep(.module-select-button .p-button.p-highlight) {
  background: color-mix(in srgb, var(--primary-color) 12%, transparent) !important;
  border-color: color-mix(in srgb, var(--primary-color) 40%, transparent) !important;
  color: var(--primary-color) !important;
  box-shadow: inset 0 1px 0 color-mix(in srgb, var(--primary-color) 20%, transparent);
  font-weight: 700;
}

/* Abas de navegação — estilo underline moderno */
.nav-tabs {
  display: flex;
  align-items: stretch;
  gap: 0;
}

.nav-tab {
  position: relative;
  padding: 0 0.85rem;
  height: 56px;
  display: flex;
  align-items: center;
  text-decoration: none;
  color: var(--text-muted);
  font-size: 0.72rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  border: none;
  background: transparent;
  transition: color 0.2s ease;
  white-space: nowrap;
}

.nav-tab::after {
  content: '';
  position: absolute;
  bottom: 0;
  left: 0.5rem;
  right: 0.5rem;
  height: 2px;
  border-radius: 2px 2px 0 0;
  background: var(--primary-color);
  transform: scaleX(0);
  transition: transform 0.2s ease;
}

.nav-tab:hover {
  color: var(--text-color);
}

.nav-tab:hover::after {
  transform: scaleX(0.5);
  opacity: 0.4;
}

.nav-tab.active {
  color: var(--primary-color);
}

.nav-tab.active::after {
  transform: scaleX(1);
}

/* Atalho do último CNPJ analisado */
.nav-recent-wrapper {
  position: relative;
  display: flex;
  align-items: center;
}

/* Extensão do nav-tab para o atalho de CNPJ */
.nav-recent-cnpj {
  gap: 0.4rem;
  padding-right: 1.4rem; /* espaço para o clear button */
}

/* Separador antes do atalho */
.nav-recent-cnpj::before {
  content: '';
  position: absolute;
  left: 0;
  width: 1px;
  height: 16px;
  background: color-mix(in srgb, var(--text-muted) 25%, transparent);
}

.nav-recent-cnpj .pi-history {
  font-size: 0.65rem;
  opacity: 0.6;
}

.nav-recent-clear {
  position: absolute;
  right: 0.3rem;
  top: 50%;
  transform: translateY(-50%);
  background: none;
  border: none;
  cursor: pointer;
  padding: 0.2rem;
  color: var(--text-muted);
  opacity: 0.4;
  display: flex;
  align-items: center;
  transition: opacity 0.15s;
}

.nav-recent-clear:hover {
  opacity: 1;
}

.nav-recent-clear .pi {
  font-size: 0.55rem;
}

/* Busca rápida de CNPJ na navbar */
.nav-cnpj-search {
  position: relative;
  display: flex;
  align-items: center;
}

.nav-cnpj-icon {
  position: absolute;
  left: 0.6rem;
  font-size: 0.7rem;
  color: var(--text-muted);
  pointer-events: none;
  z-index: 1;
}

.nav-cnpj-input {
  padding: 0.3rem 0.7rem 0.3rem 1.8rem !important;
  height: 30px !important;
  font-size: 0.72rem !important;
  font-family: 'Inter', sans-serif !important;
  font-weight: 600 !important;
  width: 170px !important;
  background: color-mix(in srgb, var(--card-bg) 80%, transparent) !important;
  border: 1px solid var(--card-border) !important;
  border-radius: 6px !important;
  color: var(--text-color) !important;
  letter-spacing: 0.03em;
  transition: border-color 0.2s, box-shadow 0.2s;
}

.nav-cnpj-input:focus {
  border-color: color-mix(in srgb, var(--primary-color) 60%, transparent) !important;
  box-shadow: 0 0 0 3px color-mix(in srgb, var(--primary-color) 12%, transparent) !important;
  outline: none !important;
}

.nav-cnpj-input::placeholder {
  color: var(--text-muted) !important;
  opacity: 0.6;
}

.page-content {
  padding: 1.3rem 1.5rem 1.5rem;
  flex: 1;
  background: transparent !important;
}

/* Tratamento ultra-específico para inputs na Sidebar (Eliminar empilhamento de fundo) */
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

/* 
  OVERRIDE PRIMEVUE COMPONENTS FOR BOTH MODES 
  (Fixes the styling and ensures it persists on both themes)
*/
:global(.admin-layout) .p-datatable .p-datatable-header,
:global(.admin-layout) .p-datatable .p-datatable-thead > tr > th,
:global(.admin-layout) .p-datatable .p-datatable-tbody > tr > td,
:global(.admin-layout) .p-datatable .p-datatable-tfoot > tr > td,
:global(.admin-layout) .p-paginator {
  background: var(--card-bg) !important;
  color: var(--text-color) !important;
  border-color: var(--sidebar-border) !important;
}

/* Forçar especificamente no dark mode para vencer o tema Lara Light */
:global(.dark-mode) .p-datatable .p-datatable-tbody > tr > td {
  background: var(--card-bg) !important;
}

:global(.admin-layout) .p-datatable .p-datatable-thead > tr > th {
  color: var(
    --table-header-text
  ) !important; /* Usar a variável de texto do header */
  font-size: 0.7rem;
  text-transform: uppercase;
  font-weight: 700;
  border-bottom: 2px solid var(--sidebar-border) !important;
}

:global(.dark-mode) .p-datatable .p-datatable-thead > tr > th,
:global(.dark-mode) .p-datatable .p-datatable-tbody > tr,
:global(.dark-mode) .p-datatable .p-datatable-tfoot > tr > td {
  background: var(--card-bg) !important;
  color: var(--text-color) !important;
  border-color: var(--sidebar-border) !important;
}

:global(.dark-mode)
  .p-datatable.p-datatable-striped
  .p-datatable-tbody
  > tr.p-row-odd {
  background: var(--table-stripe) !important;
}

:global(.admin-layout) .p-datatable .p-datatable-tbody > tr {
  background: var(--card-bg) !important;
  color: var(--text-color) !important;
  font-size: 0.85rem;
}

:global(.admin-layout)
  .p-datatable.p-datatable-striped
  .p-datatable-tbody
  > tr.p-row-odd {
  background: var(--table-stripe) !important;
}

:global(.admin-layout) .p-datatable .p-datatable-tbody > tr:hover {
  background: var(--table-hover);
}

/* Fix text colors for paginator buttons */
:global(.admin-layout) .p-paginator .p-paginator-pages .p-paginator-page,
:global(.admin-layout) .p-paginator .p-paginator-first,
:global(.admin-layout) .p-paginator .p-paginator-prev,
:global(.admin-layout) .p-paginator .p-paginator-next,
:global(.admin-layout) .p-paginator .p-paginator-last {
  color: var(--text-color);
}
:global(.admin-layout)
  .p-paginator
  .p-paginator-pages
  .p-paginator-page.p-highlight {
  background: var(--primary-color);
  color: var(--color-on-primary);
  border-color: var(--primary-color);
}

:global(.dark-mode .p-dropdown),
:global(.dark-mode .p-dropdown-panel),
:global(.dark-mode .p-dropdown-header),
:global(.dark-mode .p-inputtext),
:global(.dark-mode .p-calendar .p-inputtext),
:global(.dark-mode .p-datepicker),
:global(.dark-mode .p-datepicker-header),
:global(.dark-mode .p-monthpicker),
:global(.dark-mode .p-yearpicker) {
  background: var(--card-bg) !important;
  color: var(--text-color) !important;
  border-color: var(--sidebar-border) !important;
}

:global(.dark-mode .p-dropdown:not(.p-disabled):hover),
:global(.p-dropdown:not(.p-disabled):hover) {
  border-color: var(--primary-color) !important;
  background: rgba(255, 255, 255, 0.04) !important;
  box-shadow: none !important;
}

:global(.dark-mode .p-dropdown:not(.p-disabled).p-focus),
:global(.p-dropdown:not(.p-disabled).p-focus) {
  border-color: var(--primary-color) !important;
  box-shadow: 0 0 0 2px
    color-mix(in srgb, var(--primary-color) 25%, transparent) !important;
  outline: none !important;
}

:global(.dark-mode .p-inputtext:enabled:focus),
:global(.p-inputtext:enabled:focus) {
  border-color: var(--primary-color) !important;
  box-shadow: 0 0 0 2px
    color-mix(in srgb, var(--primary-color) 25%, transparent) !important;
  outline: none !important;
}

:global(.dark-mode) .p-datepicker .p-datepicker-header button,
:global(.dark-mode) .p-monthpicker .p-monthpicker-month,
:global(.dark-mode) .p-yearpicker .p-yearpicker-year {
  color: var(--text-color) !important;
}

:global(.dark-mode)
  .p-monthpicker
  .p-monthpicker-month:not(.p-highlight):not(.p-disabled):hover,
:global(.dark-mode)
  .p-yearpicker
  .p-yearpicker-year:not(.p-highlight):not(.p-disabled):hover {
  background: var(--table-hover) !important;
}

:global(.dark-mode) .p-monthpicker .p-monthpicker-month.p-highlight,
:global(.dark-mode) .p-yearpicker .p-yearpicker-year.p-highlight {
  background: var(--primary-color) !important;
  color: var(--color-on-primary) !important;
}

:global(.p-dropdown-item) {
  font-size: 0.75rem !important;
  padding: 0.5rem 0.75rem !important;
}

:global(.dark-mode .p-dropdown-item) {
  color: var(--text-color) !important;
}

:global(
  .dark-mode
    .p-dropdown-panel
    .p-dropdown-items
    .p-dropdown-item:not(.p-highlight):not(.p-disabled):hover
),
:global(
  .dark-mode
    .p-dropdown-panel
    .p-dropdown-items
    .p-dropdown-item.p-focus:not(.p-highlight)
) {
  background: var(--table-hover) !important;
  color: var(--text-color) !important;
}

:global(
  .dark-mode .p-dropdown-panel .p-dropdown-items .p-dropdown-item.p-highlight
) {
  background: var(--primary-color) !important;
  color: var(--color-on-primary) !important;
}

:global(
  .dark-mode
    .p-dropdown-panel
    .p-dropdown-items
    .p-dropdown-item.p-highlight:hover
),
:global(
  .dark-mode
    .p-dropdown-panel
    .p-dropdown-items
    .p-dropdown-item.p-highlight.p-focus
) {
  background: var(--primary-color) !important;
  color: var(--color-on-primary) !important;
  opacity: 0.9;
}

:global(.admin-layout) .p-listbox {
  background: var(--card-bg);
  border-color: var(--sidebar-border);
}

:global(.p-listbox-item) {
  font-size: 0.75rem !important;
}

:global(.admin-layout) .p-calendar .p-datepicker {
  background: var(--card-bg);
  border-color: var(--sidebar-border);
  color: var(--text-color);
}

:global(.p-datepicker) {
  font-size: 0.8rem !important; /* Compacto mas legível para datas */
}

:global(.p-datepicker table td) {
  padding: 0.2rem !important;
}

:global(.admin-layout) .p-calendar .p-datepicker table td > span {
  color: var(--text-color);
}

:global(.admin-layout) .p-calendar .p-datepicker table td > span:hover {
  background: var(
    --sidebar-bg
  ); /* Pode permanecer sidebar-bg pos tem pouca diferenca */
}

:global(.admin-layout) .p-calendar .p-datepicker .p-datepicker-header {
  background: var(--card-bg);
  color: var(--text-color);
  border-color: var(--sidebar-border);
}

:global(.admin-layout) .p-inputtext,
:global(.admin-layout) .p-dropdown,
:global(.admin-layout) .p-calendar .p-inputtext,
:global(.admin-layout) .p-multiselect {
  background: var(--card-bg) !important;
  border-color: var(--sidebar-border) !important;
  color: var(--text-color) !important;
}

/* Forçar especificamente na SIDEBAR (Seletores Atômicos) */
:global(.admin-sidebar) .p-inputtext,
:global(.admin-sidebar) .p-dropdown,
:global(.admin-sidebar) .p-calendar .p-inputtext {
  background: var(--sidebar-input-bg) !important;
  border-color: var(--sidebar-border) !important;
  color: var(--sidebar-text) !important;
}

/* Evitar fundo duplo em sub-elementos */
:global(.admin-sidebar) .p-dropdown-label,
:global(.admin-sidebar) .p-dropdown-trigger {
  background: transparent !important;
}

:global(.admin-layout) .p-inputtext:enabled:hover,
:global(.admin-layout) .p-dropdown:not(.p-disabled):hover {
  border-color: var(--primary-color) !important;
}

/* SCROLLBAR SIDEBAR */
.sidebar-content::-webkit-scrollbar {
  width: 4px;
}
.sidebar-content::-webkit-scrollbar-track {
  background: var(--sidebar-bg);
}
.sidebar-content::-webkit-scrollbar-thumb {
  background: var(--sidebar-border);
  border-radius: 4px;
}
.sidebar-content::-webkit-scrollbar-thumb:hover {
  background: var(--text-muted);
}

/* PAGE TRANSITIONS */
.page-fade-enter-active,
.page-fade-leave-active {
  transition:
    opacity 0.15s ease,
    transform 0.15s ease;
}
.page-fade-enter-from {
  opacity: 0;
  transform: translateY(8px);
}
.page-fade-leave-to {
  opacity: 0;
  transform: translateY(-8px);
}

/* MODAL DE SINCRONIZAÇÃO */
.sync-modal-content {
  padding: 2rem 1.5rem;
  display: flex;
  flex-direction: column;
  align-items: center;
  text-align: center;
  gap: 1rem;
}

/* PAINEL DOS DROPDOWNS NA SIDEBAR */
:global(.p-dropdown-panel.sidebar-panel) {
  background: var(--sidebar-bg) !important;
  border: 1px solid var(--sidebar-border) !important;
  box-shadow: 0 10px 25px rgba(0, 0, 0, 0.4) !important;
}

:global(.sidebar-panel .p-dropdown-items .p-dropdown-item) {
  color: var(--sidebar-text) !important;
  font-size: 0.8rem;
}

:global(
  .sidebar-panel
    .p-dropdown-items
    .p-dropdown-item:not(.p-highlight):not(.p-disabled):hover
) {
  background: var(--sidebar-input-bg) !important;
  color: var(--sidebar-text) !important;
}

:global(.sidebar-panel .p-dropdown-items .p-dropdown-item.p-highlight) {
  background: color-mix(
    in srgb,
    var(--primary-color) 20%,
    transparent
  ) !important;
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
:deep(.p-dialog) {
  background: var(--card-bg);
  color: var(--text-color);
  border: 1px solid var(--sidebar-border);
}

:deep(.p-dialog-header),
:deep(.p-dialog-content),
:deep(.p-dialog-footer) {
  background: var(--card-bg);
  color: var(--text-color);
}

:deep(.p-dialog .p-dialog-header .p-dialog-title) {
  color: var(--text-color);
}

:deep(.p-dialog .p-dialog-header .p-dialog-header-icon) {
  color: var(--text-color);
}

:deep(.p-dialog-content) {
  color: var(--text-color);
}

.sync-icon-container {
  width: 64px;
  height: 64px;
  background: color-mix(in srgb, var(--primary-color) 10%, transparent);
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  margin-bottom: 0.5rem;
}

.sync-icon-container i {
  font-size: 2rem;
  color: var(--primary-color);
}

.sync-modal-content h3 {
  font-size: 1.25rem;
  font-weight: 700;
  margin: 0;
  color: var(--text-color);
}

.sync-modal-content p {
  font-size: 0.9rem;
  color: var(--text-muted);
  margin: 0;
  line-height: 1.5;
}

.progress-wrapper {
  width: 100%;
  margin-top: 1rem;
}

.status-minor {
  font-size: 0.75rem;
  font-style: italic;
  color: var(--text-muted);
  opacity: 0.7;
}

/* ── ESTADO DE ERRO NO MODAL DE SYNC ── */
.sync-error-icon {
  background: color-mix(
    in srgb,
    var(--color-error) 12%,
    transparent
  ) !important;
  animation: shake 0.4s ease;
}

.sync-error-icon i {
  color: var(--color-error) !important;
}

.sync-error-title {
  color: var(--color-error) !important;
}

.sync-error-msg {
  font-size: 0.88rem;
  color: var(--text-muted);
  line-height: 1.55;
  max-width: 360px;
}

.sync-error-actions {
  display: flex;
  gap: 0.75rem;
  justify-content: center;
  flex-wrap: wrap;
  margin-top: 0.5rem;
}

@keyframes shake {
  0%,
  100% {
    transform: translateX(0);
  }
  20% {
    transform: translateX(-6px);
  }
  40% {
    transform: translateX(6px);
  }
  60% {
    transform: translateX(-4px);
  }
  80% {
    transform: translateX(4px);
  }
}

/* ── DIALOG CNPJ: Botões com glassmorphism ── */
.cnpj-dialog-btn {
  display: inline-flex;
  align-items: center;
  gap: 0.4rem;
  padding: 0.45rem 1.1rem;
  font-size: 0.82rem;
  font-weight: 600;
  border-radius: 8px;
  border: 1px solid;
  cursor: pointer;
  transition: all 0.2s ease;
  backdrop-filter: blur(8px);
  -webkit-backdrop-filter: blur(8px);
}

.cnpj-dialog-btn--cancel {
  color: var(--text-muted);
  border-color: rgba(148, 163, 184, 0.25);
  background: var(--card-bg);
}
.cnpj-dialog-btn--cancel:hover {
  background: color-mix(in srgb, var(--card-bg) 85%, var(--text-muted));
  border-color: rgba(148, 163, 184, 0.4);
}

.cnpj-dialog-btn--confirm {
  color: var(--primary-color);
  border-color: color-mix(in srgb, var(--primary-color) 35%, transparent);
  background: color-mix(in srgb, var(--primary-color) 10%, var(--card-bg));
}
.cnpj-dialog-btn--confirm:hover {
  background: color-mix(in srgb, var(--primary-color) 20%, var(--card-bg));
  border-color: color-mix(in srgb, var(--primary-color) 60%, transparent);
  box-shadow: 0 0 12px color-mix(in srgb, var(--primary-color) 25%, transparent);
}
</style>
