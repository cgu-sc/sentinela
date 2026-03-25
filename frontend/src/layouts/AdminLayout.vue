<script setup>
import { ref, onMounted, computed, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useThemeStore } from '../stores/theme';
import { useFilterStore } from '../stores/filters';
import Button from 'primevue/button';
import ThemeSelector from '../components/ThemeSelector.vue';
import Dropdown from 'primevue/dropdown';
import Calendar from 'primevue/calendar';
import Slider from 'primevue/slider';
import SelectButton from 'primevue/selectbutton'; // Substituindo Listbox
import InputText from 'primevue/inputtext';

const themeStore = useThemeStore();
const filterStore = useFilterStore();
const route = useRoute();
const router = useRouter();

// Configuração de Módulos (DNA Sentinela)
const modules = ref([
    { name: 'Sentinela', value: 'consolidado', icon: 'pi pi-chart-bar' },
    { name: 'Alvos', value: 'alvos', icon: 'pi pi-compass' } // pi-bullseye pode nao existir
]);

const activeModule = ref('consolidado');

// Abas dinâmicas baseadas no módulo selecionado
const tabs = computed(() => {
    if (activeModule.value === 'consolidado') {
        return [
            { label: 'Análise Nacional', path: '/' },
            { label: 'Dispersão Benefício', path: '/dispersao' },
            { label: 'Análise Município', path: '/municipio' },
            { label: 'Análise Empresa', path: '/empresa' },
            { label: 'Análise CNPJ', path: '/cnpj' }
        ];
    } else {
        return [
            { label: 'Mapa-Cluster', path: '/alvos/cluster' },
            { label: 'Situação CNPJ', path: '/alvos/situacao' },
            { label: 'Variação Produção', path: '/alvos/variacao' },
            { label: 'Rede de Sócios', path: '/alvos/rede' }
        ];
    }
});

// Sincronizar activeModule com a rota atual ao carregar
onMounted(() => {
  themeStore.initTheme();
  if (route.path.startsWith('/alvos')) {
      activeModule.value = 'alvos';
  }
});

// Watch para mudar a rota padrão ao trocar de módulo
watch(activeModule, (newVal) => {
    if (newVal === 'consolidado' && !route.path.match(/^\/(?:dispersao|municipio|empresa|cnpj|$)/)) {
        router.push('/');
    } else if (newVal === 'alvos' && !route.path.startsWith('/alvos')) {
        router.push('/alvos/cluster');
    }
});

// Opções dos Selects (Estáticos para Mock)
const ufOptions = ['Todos', 'AC', 'AL', 'AM', 'AP', 'BA', 'CE', 'DF', 'ES', 'GO', 'MA', 'MG', 'MS', 'MT', 'PA', 'PB', 'PE', 'PI', 'PR', 'RJ', 'RN', 'RO', 'RR', 'RS', 'SC', 'SE', 'SP', 'TO'];
const municipioOptions = ['Todos', 'Brasília', 'Goiânia', 'São Paulo', 'Rio de Janeiro', 'Belo Horizonte', 'Curitiba', 'Salvador'];
const situacaoOptions = ['Todos', 'ATIVA', 'BAIXADA', 'SUSPENSA', 'INAPTA'];
const msOptions = ['Todos', 'SIM', 'NÃO'];
const porteOptions = ['Todos', 'ME', 'EPP', 'DEMAIS'];
const clusterOptions = ['Todos', 'Cluster 0 - Risco Crítico', 'Cluster 1 - Risco Alto', 'Cluster 2 - Risco Médio', 'Cluster 3 - Risco Baixo'];
const rfaOptions = ['Todos', 'Acima de R$ 1 Mi', 'Entre R$ 500k e R$ 1 Mi', 'Até R$ 500k'];

// Formatador de Moeda para o Slider
const formatCurrency = (val) => {
    if (val >= 1000000) return `R$ ${(val/1000000).toFixed(1)} Mi`;
    if (val >= 1000) return `R$ ${(val/1000).toFixed(0)}k`;
    return `R$ ${val}`;
};

// Controle de Menu
const isCollapsed = ref(localStorage.getItem('sentinela_sidebar_collapsed') === 'true');

watch(isCollapsed, (val) => {
  localStorage.setItem('sentinela_sidebar_collapsed', String(val));
});

const limparFiltros = () => {
    filterStore.resetFilters();
};

// ⏳ OPÇÃO 3: RANGE SLIDER TEMPORAL (DYNAMIC TIMELINE 2015-2024)
const availableMonths = [];
const monthsLabels = ['JAN', 'FEV', 'MAR', 'ABR', 'MAI', 'JUN', 'JUL', 'AGO', 'SET', 'OUT', 'NOV', 'DEZ'];
for (let y = 2015; y <= 2024; y++) {
  monthsLabels.forEach((m, idx) => {
    availableMonths.push({ label: `${m}/${y.toString().slice(-2)}`, date: new Date(y, idx, 1) });
  });
}

// Inicializar com Abril/24 a Setembro/24 (Índices 111 e 116 na timeline 2015-2024)
const timeSliderValue = ref([111, 116]);

const displayPeriod = computed(() => {
    const start = availableMonths[timeSliderValue.value[0]].label;
    const end = availableMonths[timeSliderValue.value[1]].label;
    return `${start} a ${end}`;
});

const quickSelectYear = (year) => {
    const startIdx = (year - 2015) * 12;
    timeSliderValue.value = [startIdx, startIdx + 11];
};

const selectAll = () => {
    timeSliderValue.value = [0, availableMonths.length - 1];
};

// Tooltips flutuantes para o Slider
const startMonthLabel = computed(() => availableMonths[timeSliderValue.value[0]]?.label);
const endMonthLabel = computed(() => availableMonths[timeSliderValue.value[1]]?.label);
const startPos = computed(() => (timeSliderValue.value[0] / (availableMonths.length - 1)) * 100);
const endPos = computed(() => (timeSliderValue.value[1] / (availableMonths.length - 1)) * 100);

// Sincronizar com Debounce (Poder de processamento amigável - SÓ CHAMA API QUANDO PARAR)
let timer = null;
watch(timeSliderValue, (newIndices) => {
    clearTimeout(timer);
    timer = setTimeout(() => {
        const startDate = availableMonths[newIndices[0]].date;
        const rawEndDate = availableMonths[newIndices[1]].date;
        const endDate = new Date(rawEndDate.getFullYear(), rawEndDate.getMonth() + 1, 0); 
        
        // Evitar disparar o filtro se as datas já forem as mesmas
        if (filterStore.periodo[0]?.getTime() !== startDate.getTime() || 
            filterStore.periodo[1]?.getTime() !== endDate.getTime()) {
            filterStore.periodo = [startDate, endDate];
        }
    }, 450); // 450ms de calma
}, { immediate: true });

// Sincronizar de VOLTA: Se o usuário mudar no CALENDÁRIO, o SLIDER precisa PULAR para o lugar certo
watch(() => filterStore.periodo, (newVal) => {
    if (!newVal || newVal.length < 2 || !newVal[0] || !newVal[1]) return;
    
    const startIdx = availableMonths.findIndex(m => 
        m.date.getFullYear() === newVal[0].getFullYear() && m.date.getMonth() === newVal[0].getMonth()
    );
    const endIdx = availableMonths.findIndex(m => 
        m.date.getFullYear() === newVal[1].getFullYear() && m.date.getMonth() === newVal[1].getMonth()
    );

    if (startIdx !== -1 && endIdx !== -1) {
        if (startIdx !== timeSliderValue.value[0] || endIdx !== timeSliderValue.value[1]) {
            timeSliderValue.value = [startIdx, endIdx];
        }
    }
}, { deep: true });
</script>

<template>
  <div class="admin-layout" :class="{ 'collapsed': isCollapsed }">
    <!-- BARRA LATERAL DE FILTROS & MÓDULOS -->
    <aside class="admin-sidebar">
      <div class="sidebar-header" title="Projeto Sentinela">
        <div class="brand">
          <img src="/logo_sentinela.png" alt="Sentinela V3" class="logo-img" />
          <div class="brand-text" v-show="!isCollapsed">
            <span class="brand-name">SENTINELA</span>
            <span class="brand-version">AUDITORIA NO FARMÁCIA POPULAR</span>
          </div>
        </div>
        <Button 
          :icon="isCollapsed ? 'pi pi-angle-right' : 'pi pi-angle-left'" 
          text rounded size="small" 
          @click="isCollapsed = !isCollapsed" 
          class="collapse-btn"
        />
      </div>

      <div class="sidebar-content" v-show="!isCollapsed">
        
        <!-- 1. FILTROS GLOBAIS (SEMPRE PRESENTES) -->
        <div class="filter-section">
          <label class="filter-label">UF</label>
          <Dropdown v-model="filterStore.selectedUF" :options="ufOptions" placeholder="Estado" class="w-full filter-input" />
        </div>

        <div class="filter-section">
          <label class="filter-label">Município</label>
          <Dropdown v-model="filterStore.selectedMunicipio" :options="municipioOptions" placeholder="Município" filter class="w-full filter-input" />
        </div>

        <div class="grid-filters">
            <div class="filter-section">
                <label class="filter-label">Situação</label>
                <Dropdown v-model="filterStore.selectedSituacao" :options="situacaoOptions" class="w-full filter-input" />
            </div>
            <div class="filter-section">
                <label class="filter-label">Conexão MS</label>
                <Dropdown v-model="filterStore.selectedMS" :options="msOptions" class="w-full filter-input" />
            </div>
        </div>

        <div class="filter-section">
            <label class="filter-label">Porte CNPJ</label>
            <Dropdown v-model="filterStore.selectedPorte" :options="porteOptions" class="w-full filter-input" />
        </div>

        <div class="filter-section">
          <label class="filter-label">% de não comprovação</label>
          <div class="slider-container">
            <div class="slider-values">
              <span>{{ filterStore.naoComprovacaoRange[0] }}%</span>
              <span>{{ filterStore.naoComprovacaoRange[1] }}%</span>
            </div>
            <Slider v-model="filterStore.naoComprovacaoRange" range class="w-full" />
          </div>
        </div>

        <div class="filter-section">
          <label class="filter-label">Valor sem comprovação</label>
          <div class="slider-container">
            <div class="slider-values">
              <span>{{ formatCurrency(filterStore.valorSemCompRange[0]) }}</span>
              <span>{{ formatCurrency(filterStore.valorSemCompRange[1]) }}</span>
            </div>
            <Slider v-model="filterStore.valorSemCompRange" range :min="0" :max="5000000" :step="1000" class="w-full" />
          </div>
        </div>

        <div class="filter-section">
          <label class="filter-label">Período de Análise</label>
          <div class="slider-container">
            <!-- 1. Atalhos Rápidos de Ano (Botões Maiores) -->
            <div class="flex gap-2 mb-3">
                <Button label="2023" class="year-btn flex-1 p-button-secondary p-button-outlined" @click="quickSelectYear(2023)" />
                <Button label="2024" class="year-btn flex-1 p-button-secondary p-button-outlined" @click="quickSelectYear(2024)" />
                <Button label="TUDO" class="year-btn flex-1 p-button-secondary p-button-outlined" @click="selectAll()" />
            </div>

            <!-- 2. Calendário Manual (Híbrido - Sempre visível e sincronizado) -->
            <Calendar 
                v-model="filterStore.periodo" 
                view="month" 
                dateFormat="mm/yy" 
                selectionMode="range" 
                :manualInput="false" 
                showIcon 
                iconDisplay="input" 
                class="w-full filter-input mb-5" 
            />

            <!-- 3. Time Slider (Para varredura rápida) com Tooltips Flutuantes -->
            <div class="slider-wrapper relative pt-6 mt-3">
                <div class="slider-tip" :style="{ left: startPos + '%' }">{{ startMonthLabel }}</div>
                <div class="slider-tip" :style="{ left: endPos + '%' }">{{ endMonthLabel }}</div>
                
                <Slider 
                    v-model="timeSliderValue" 
                    range 
                    :min="0" 
                    :max="availableMonths.length - 1" 
                    class="w-full time-slider" 
                />
            </div>
          </div>
        </div>

        <hr class="sidebar-divider my-4" />
        
        <!-- 2. FILTROS CONTEXTUAIS (DENTRO DO LAYOUT PARA GARANTIR RENDERIZAÇÃO) -->
        <div class="dynamic-filters-box">
             <div class="filter-header">
                <i class="pi pi-filter"></i>
                <span>Filtros da Página</span>
             </div>

             <!-- Filtros para MAPA-CLUSTER -->
             <div v-if="route.path === '/alvos/cluster'" class="contextual-filters">
                <div class="filter-section mini">
                    <label class="filter-label sm">Busca Alvo</label>
                    <InputText v-model="filterStore.searchTarget" placeholder="ID/CNPJ..." class="w-full filter-input sm" />
                </div>
                <div class="filter-section mini">
                    <label class="filter-label sm">Target Cluster</label>
                    <Dropdown v-model="filterStore.clusterSelection" :options="clusterOptions" class="w-full filter-input sm" />
                </div>
                <div class="filter-section mini">
                    <label class="filter-label sm">Risco (RFA)</label>
                    <Dropdown v-model="filterStore.rfaSelection" :options="rfaOptions" class="w-full filter-input sm" />
                </div>
             </div>

             <!-- Filtros para REDE DE SÓCIOS -->
             <div v-if="route.path === '/alvos/rede'" class="contextual-filters">
                <div class="filter-section mini">
                    <label class="filter-label sm">CPF/CNPJ Alvo</label>
                    <InputText v-model="filterStore.searchTarget" placeholder="Pesquisar rede..." class="w-full filter-input sm" />
                </div>
             </div>

             <!-- Filtros para DASHBOARD (CONSOLIDADO) -->
             <div v-if="activeModule === 'consolidado'" class="contextual-filters">
                <p class="text-xs px-2 italic" style="color: var(--text-muted)">Nenhum filtro extra necessário.</p>
             </div>
        </div>

        <div class="sidebar-spacer"></div>

        <Button label="Limpar Filtros" icon="pi pi-undo" outlined severity="secondary" @click="limparFiltros" class="w-full mb-4" />
      </div>

      <div class="sidebar-footer" v-show="!isCollapsed">
        <p>© 2024 CGU - Projeto Sentinela</p>
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
                <i :class="slotProps.option.icon" style="margin-right: 0.5rem; font-size: 0.9rem"></i>
                <span style="font-size: 0.75rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.3px">{{ slotProps.option.name }}</span>
            </template>
          </SelectButton>
          
          <div class="nav-divider"></div>

          <div class="nav-tabs">
            <router-link 
              v-for="tab in tabs" 
              :key="tab.path" 
              :to="tab.path" 
              class="nav-tab"
              active-class="active"
            >
              {{ tab.label }}
            </router-link>
          </div>
        </div>
        <div class="nav-actions">
           <ThemeSelector />
           <Button icon="pi pi-home" text rounded severity="secondary" />
        </div>
      </nav>

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
/* SISTEMA DE CORES DINÂMICO (DNA ARBFLOW) */
.admin-layout {
  --sidebar-width: 280px;
  --sidebar-collapsed: 80px;

  display: block;
  min-height: 100vh;
  background-color: var(--bg-color);
  color: var(--text-color);
  transition: background-color 0.3s ease, color 0.3s ease;
}

:global(.admin-layout) {
  display: flex;
  min-height: 100vh;
  width: 100%;
  background-color: var(--bg-color);
  color: var(--text-color);
  transition: background-color 0.3s ease, color 0.3s ease;
}

/* SIDEBAR */
.admin-sidebar {
  width: var(--sidebar-width);
  background-color: var(--sidebar-bg);
  color: var(--sidebar-text);
  transition: width 0.3s cubic-bezier(0.4, 0, 0.2, 1), background-color 0.3s ease;
  display: flex;
  flex-direction: column;
  box-shadow: 4px 0 10px rgba(0,0,0,0.05);
  position: fixed;
  top: 0;
  left: 0;
  height: 100vh;
  z-index: 200;
  border-right: 1px solid var(--sidebar-border);
  overflow: hidden;
}

.admin-layout.collapsed .admin-sidebar {
  width: var(--sidebar-collapsed);
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
  width: 40px;
  /* Logo mudando de cor conforme o tema */
  filter: var(--logo-filter);
}

:global(.dark-mode) .logo-img { --logo-filter: none; }
:global(.light-mode) .logo-img { --logo-filter: none; }

.brand-name {
  font-weight: 700;
  font-size: 1.2rem;
  display: block;
  color: var(--text-color);
}

.brand-version {
  font-size: 0.7rem;
  opacity: 0.7;
  color: var(--text-color);
}

.sidebar-content {
  flex: 1;
  padding: 0.75rem 1rem;
  display: flex;
  flex-direction: column;
  gap: 0.75rem; /* Reduzido de 1.5rem */
  overflow-y: auto;
  overflow-x: hidden;
}

.filter-section {
    margin-bottom: 0.5rem;
}

.filter-label {
  display: block;
  font-size: 0.65rem;
  font-weight: 700;
  text-transform: uppercase;
  margin-bottom: 0.25rem;
  color: var(--text-muted);
  letter-spacing: 0.5px;
}

/* COMPONENTES COMPACTOS DO PRIMEVUE */
:deep(.filter-input .p-inputtext),
:deep(.filter-input .p-dropdown-label),
:deep(.filter-input .p-calendar .p-inputtext) {
    padding: 0.4rem 0.6rem; /* Reduzido de ~0.75rem */
    font-size: 0.75rem; /* Font-size compacto */
}

:deep(.p-dropdown), :deep(.p-calendar) {
    height: 32px; /* Altura fixa reduzida */
    align-items: center;
}

:deep(.p-calendar-trigger) {
    width: 32px;
}

.grid-filters {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 0.5rem;
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
  color: var(--text-color);
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

.year-btn {
  font-size: 0.65rem !important;
  padding: 0px 8px !important;
  height: 24px !important;
  font-weight: 800 !important;
  border: 1px solid var(--sidebar-border) !important;
  border-radius: 4px !important;
  color: var(--text-muted) !important;
  background: var(--card-bg) !important;
  text-transform: uppercase;
  transition: all 0.2s ease;
  line-height: normal !important;
}

.year-btn:hover {
  border-color: var(--primary-color) !important;
  color: var(--primary-color) !important;
  background: rgba(255, 255, 255, 0.05) !important;
}

/* Removido estilo do dropdown antigo */

/* TOOLTIPS DO SLIDER */
.slider-wrapper {
    position: relative;
    margin-top: 12px !important; /* Espaço equilibrado */
}

.filter-input {
    margin-bottom: 8px !important; /* Aproxima um pouco mais do slider */
}

.slider-tip {
  position: absolute;
  top: 24px; /* Ajuste fino para colar a setinha no controle */
  transform: translateX(-50%);
  background: var(--primary-color);
  color: white;
  padding: 2px 5px;
  border-radius: 4px;
  font-size: 0.55rem;
  font-weight: 900;
  pointer-events: none;
  z-index: 10;
  white-space: nowrap;
  box-shadow: 0 2px 4px rgba(0,0,0,0.3);
}

.slider-tip::after {
  content: '';
  position: absolute;
  top: -3px; /* Setinha agora no topo do tooltip pescando a bolinha */
  left: 50%;
  transform: translateX(-50%);
  border-left: 3px solid transparent;
  border-right: 3px solid transparent;
  border-bottom: 3px solid var(--primary-color);
}

:deep(.p-slider-handle) {
    width: 14px;
    height: 14px;
    margin-top: -7px;
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
    color: #fff;
}

:deep(.custom-listbox .p-listbox-item:not(.p-highlight):hover) {
    background: color-mix(in srgb, var(--primary-color) 10%, transparent);
}

.sidebar-spacer { flex: 1; }

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

.filter-header i { color: var(--primary-color); font-size: 0.9rem; }
.filter-header span { 
    font-size: 0.75rem; 
    font-weight: 800; 
    text-transform: uppercase; 
    color: var(--text-muted); 
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
  text-align: center;
  font-size: 0.7rem;
  opacity: 0.4;
}

/* MAIN CONTENT */
.main-container {
  flex: 1;
  display: flex;
  flex-direction: column;
  margin-left: var(--sidebar-width);
  transition: margin-left 0.3s cubic-bezier(0.4, 0, 0.2, 1);
  min-height: 100vh;
}

.admin-layout.collapsed .main-container {
  margin-left: var(--sidebar-collapsed);
}

.top-navbar {
  height: 64px;
  background: var(--navbar-bg);
  border-bottom: 1px solid var(--navbar-border);
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 0 1.5rem;
  position: sticky;
  top: 0;
  z-index: 100;
  transition: background-color 0.3s ease;
}

.nav-left {
  display: flex;
  align-items: center;
  gap: 1.5rem;
}

.nav-divider {
  width: 1px;
  height: 32px;
  background-color: var(--sidebar-border);
}

:deep(.module-select-button) {
  border-radius: 8px;
  overflow: hidden;
}

:deep(.module-select-button .p-button) {
  background: var(--card-bg);
  border-color: var(--sidebar-border);
  color: var(--text-color);
  padding: 0.4rem 0.75rem;
}

:deep(.module-select-button .p-button.p-highlight) {
  background: color-mix(in srgb, var(--primary-color) 15%, transparent) !important;
  border-color: color-mix(in srgb, var(--primary-color) 40%, transparent) !important;
  color: var(--primary-color) !important;
  box-shadow: 0 0 12px color-mix(in srgb, var(--primary-color) 10%, transparent);
  font-weight: 700;
}

.nav-tabs {
  display: flex;
  gap: 0.5rem;
}

.nav-tab {
  padding: 0.4rem 0.75rem;
  text-decoration: none;
  color: var(--text-color);
  font-size: 0.75rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.3px;
  border-bottom: 2px solid transparent;
  transition: all 0.2s;
  border-radius: 8px;
}

.nav-tab:hover {
  background-color: color-mix(in srgb, var(--primary-color) 12%, transparent);
  opacity: 1;
}

.nav-tab.active {
  background-color: color-mix(in srgb, var(--primary-color) 15%, transparent);
  border: 1px solid color-mix(in srgb, var(--primary-color) 40%, transparent);
  color: var(--primary-color);
  box-shadow: 0 0 12px color-mix(in srgb, var(--primary-color) 10%, transparent);
  font-weight: 700;
  opacity: 1;
}

.page-content {
  padding: 1.5rem;
  flex: 1;
}

/* Tratamento dos inputs do PrimeVue no Tema Escuro da Sidebar */
:deep(.filter-input .p-inputtext) {
  background: var(--card-bg);
  border-color: var(--sidebar-border);
  color: var(--text-color);
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
  color: var(--table-header-text) !important; /* Usar a variável de texto do header */
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

:global(.dark-mode) .p-datatable.p-datatable-striped .p-datatable-tbody > tr.p-row-odd {
  background: var(--table-stripe) !important;
}

:global(.admin-layout) .p-datatable .p-datatable-tbody > tr {
  background: var(--card-bg) !important;
  color: var(--text-color) !important;
  font-size: 0.85rem;
}

:global(.admin-layout) .p-datatable.p-datatable-striped .p-datatable-tbody > tr.p-row-odd {
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
:global(.admin-layout) .p-paginator .p-paginator-pages .p-paginator-page.p-highlight {
    background: var(--primary-color);
    color: #fff;
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

:global(.dark-mode) .p-datepicker .p-datepicker-header button,
:global(.dark-mode) .p-monthpicker .p-monthpicker-month,
:global(.dark-mode) .p-yearpicker .p-yearpicker-year {
    color: var(--text-color) !important;
}

:global(.dark-mode) .p-monthpicker .p-monthpicker-month:not(.p-highlight):not(.p-disabled):hover,
:global(.dark-mode) .p-yearpicker .p-yearpicker-year:not(.p-highlight):not(.p-disabled):hover {
    background: var(--table-hover) !important;
}

:global(.dark-mode) .p-monthpicker .p-monthpicker-month.p-highlight,
:global(.dark-mode) .p-yearpicker .p-yearpicker-year.p-highlight {
    background: var(--primary-color) !important;
    color: #ffffff !important;
}

:global(.p-dropdown-item) {
    font-size: 0.75rem !important;
    padding: 0.5rem 0.75rem !important;
}

:global(.dark-mode .p-dropdown-item) {
    color: var(--text-color) !important;
}

:global(.dark-mode .p-dropdown-panel .p-dropdown-items .p-dropdown-item:not(.p-highlight):not(.p-disabled):hover) {
    background: var(--table-hover) !important;
    color: var(--text-color) !important;
}

:global(.dark-mode .p-dropdown-panel .p-dropdown-items .p-dropdown-item.p-highlight) {
    background: var(--primary-color) !important;
    color: #ffffff !important;
}

:global(.dark-mode .p-dropdown-panel .p-dropdown-items .p-dropdown-item.p-highlight:hover) {
    background: var(--primary-color) !important;
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
  background: var(--sidebar-bg); /* Pode permanecer sidebar-bg pos tem pouca diferenca */
}

:global(.admin-layout) .p-calendar .p-datepicker .p-datepicker-header {
  background: var(--card-bg);
  color: var(--text-color);
  border-color: var(--sidebar-border);
}

:global(.admin-layout) .p-inputtext,
:global(.admin-layout) .p-dropdown,
:global(.admin-layout) .p-calendar .p-inputtext {
  background: var(--card-bg) !important;
  border-color: var(--sidebar-border) !important;
  color: var(--text-color) !important;
}

:global(.admin-layout) .p-inputtext:enabled:hover,
:global(.admin-layout) .p-dropdown:not(.p-disabled):hover {
  border-color: var(--primary-color);
}

/* SCROLLBAR SIDEBAR */
.sidebar-content::-webkit-scrollbar {
  width: 4px;
}
.sidebar-content::-webkit-scrollbar-track {
  background: transparent;
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
  transition: opacity 0.15s ease, transform 0.15s ease;
}
.page-fade-enter-from {
  opacity: 0;
  transform: translateY(8px);
}
.page-fade-leave-to {
  opacity: 0;
  transform: translateY(-8px);
}
</style>
