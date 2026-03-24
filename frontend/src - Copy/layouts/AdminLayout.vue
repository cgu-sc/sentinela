<script setup>
import { ref, onMounted, computed, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useThemeStore } from '../stores/theme';
import Button from 'primevue/button';
import Dropdown from 'primevue/dropdown';
import Calendar from 'primevue/calendar';
import Slider from 'primevue/slider';
import SelectButton from 'primevue/selectbutton'; // Substituindo Listbox
import InputText from 'primevue/inputtext';

const themeStore = useThemeStore();
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

// Estado dos Filtros Globais
const ufOptions = ref(['Todos', 'AC', 'AL', 'AM', 'AP', 'BA', 'CE', 'DF', 'ES', 'GO', 'MA', 'MG', 'MS', 'MT', 'PA', 'PB', 'PE', 'PI', 'PR', 'RJ', 'RN', 'RO', 'RR', 'RS', 'SC', 'SE', 'SP', 'TO']);
const selectedUF = ref('Todos');
const selectedMunicipio = ref('Todos');
const municipioOptions = ref(['Todos', 'Brasília', 'Goiânia', 'São Paulo', 'Rio de Janeiro', 'Belo Horizonte', 'Curitiba', 'Salvador']);
const selectedSituacao = ref('Todos');
const situacaoOptions = ['Todos', 'ATIVA', 'BAIXADA', 'SUSPENSA', 'INAPTA'];
const selectedMS = ref('Todos');
const msOptions = ['Todos', 'SIM', 'NÃO'];
const selectedPorte = ref('Todos');
const porteOptions = ['Todos', 'ME', 'EPP', 'DEMAIS'];

const naoComprovacaoRange = ref([0, 100]);
const valorSemCompRange = ref([0, 5000000]); // Mock 0 a 5 Mi
const periodo = ref([new Date(2016, 0, 1), new Date(2024, 11, 1)]);

// Formatador de Moeda para o Slider
const formatCurrency = (val) => {
    if (val >= 1000000) return `R$ ${(val/1000000).toFixed(1)} Mi`;
    if (val >= 1000) return `R$ ${(val/1000).toFixed(0)}k`;
    return `R$ ${val}`;
};

// Filtros Específicos (Contextuais) que agora moram aqui para estabilidade
const clusterSelection = ref('Todos');
const statusSelection = ref('Todos');
const rfaSelection = ref('Todos');
const searchTarget = ref('');
const clusterOptions = ['Todos', 'Cluster 0 - Risco Crítico', 'Cluster 1 - Risco Alto', 'Cluster 2 - Risco Médio', 'Cluster 3 - Risco Baixo'];
const statusOptions = ['Todos', 'ATIVA', 'BAIXADA', 'SUSPENSA', 'INAPTA'];
const rfaOptions = ['Todos', 'Acima de R$ 1 Mi', 'Entre R$ 500k e R$ 1 Mi', 'Até R$ 500k'];

// Controle de Menu
const isCollapsed = ref(false);

const limparFiltros = () => {
    selectedUF.value = 'Todos';
    selectedMunicipio.value = 'Todos';
    selectedSituacao.value = 'Todos';
    selectedMS.value = 'Todos';
    selectedPorte.value = 'Todos';
    naoComprovacaoRange.value = [0, 100];
    valorSemCompRange.value = [0, 5000000];
    periodo.value = [new Date(2016, 0, 1), new Date(2024, 11, 1)];
    clusterSelection.value = 'Todos';
    statusSelection.value = 'Todos';
    rfaSelection.value = 'Todos';
    searchTarget.value = '';
};
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
            <span class="brand-version">AUDITORIA E RISCOS</span>
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
          <Dropdown v-model="selectedUF" :options="ufOptions" placeholder="Estado" class="w-full filter-input" />
        </div>

        <div class="filter-section">
          <label class="filter-label">Município</label>
          <Dropdown v-model="selectedMunicipio" :options="municipioOptions" placeholder="Município" filter class="w-full filter-input" />
        </div>

        <div class="grid-filters">
            <div class="filter-section">
                <label class="filter-label">Situação</label>
                <Dropdown v-model="selectedSituacao" :options="situacaoOptions" class="w-full filter-input" />
            </div>
            <div class="filter-section">
                <label class="filter-label">Conexão MS</label>
                <Dropdown v-model="selectedMS" :options="msOptions" class="w-full filter-input" />
            </div>
        </div>

        <div class="filter-section">
            <label class="filter-label">Porte CNPJ</label>
            <Dropdown v-model="selectedPorte" :options="porteOptions" class="w-full filter-input" />
        </div>

        <div class="filter-section">
          <label class="filter-label">% de não comprovação</label>
          <div class="slider-container">
            <div class="slider-values">
              <span>{{ naoComprovacaoRange[0] }}%</span>
              <span>{{ naoComprovacaoRange[1] }}%</span>
            </div>
            <Slider v-model="naoComprovacaoRange" range class="w-full" />
          </div>
        </div>

        <div class="filter-section">
          <label class="filter-label">Valor sem comprovação</label>
          <div class="slider-container">
            <div class="slider-values">
              <span>{{ formatCurrency(valorSemCompRange[0]) }}</span>
              <span>{{ formatCurrency(valorSemCompRange[1]) }}</span>
            </div>
            <Slider v-model="valorSemCompRange" range :min="0" :max="5000000" :step="1000" class="w-full" />
          </div>
        </div>

        <div class="filter-section">
          <label class="filter-label">Período de Análise</label>
          <Calendar v-model="periodo" view="month" dateFormat="mm/yy" selectionMode="range" :manualInput="false" showIcon iconDisplay="input" class="w-full filter-input" />
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
                    <InputText v-model="searchTarget" placeholder="ID/CNPJ..." class="w-full filter-input sm" />
                </div>
                <div class="filter-section mini">
                    <label class="filter-label sm">Target Cluster</label>
                    <Dropdown v-model="clusterSelection" :options="clusterOptions" class="w-full filter-input sm" />
                </div>
                <div class="filter-section mini">
                    <label class="filter-label sm">Risco (RFA)</label>
                    <Dropdown v-model="rfaSelection" :options="rfaOptions" class="w-full filter-input sm" />
                </div>
             </div>

             <!-- Filtros para REDE DE SÓCIOS -->
             <div v-if="route.path === '/alvos/rede'" class="contextual-filters">
                <div class="filter-section mini">
                    <label class="filter-label sm">CPF/CNPJ Alvo</label>
                    <InputText v-model="searchTarget" placeholder="Pesquisar rede..." class="w-full filter-input sm" />
                </div>
             </div>

             <!-- Filtros para DASHBOARD (CONSOLIDADO) -->
             <div v-if="activeModule === 'consolidado'" class="contextual-filters">
                <p class="text-xs opacity-50 px-2 italic">Nenhum filtro extra necessário.</p>
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
                <i :class="slotProps.option.icon" style="margin-right: 0.5rem"></i>
                <span class="font-bold text-sm">{{ slotProps.option.name }}</span>
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
           <Button 
             :icon="themeStore.isDark ? 'pi pi-sun' : 'pi pi-moon'" 
             text rounded severity="secondary" 
             @click="themeStore.toggleTheme"
             v-tooltip.bottom="themeStore.isDark ? 'Modo Claro' : 'Modo Escuro'"
           />
           <Button icon="pi pi-home" text rounded severity="secondary" />
        </div>
      </nav>

      <div class="page-content">
        <router-view />
      </div>
    </main>
  </div>
</template>

<style scoped>
/* SISTEMA DE CORES DINÂMICO (DNA ARBFLOW) */
.admin-layout {
  --sidebar-width: 280px;
  --sidebar-collapsed: 80px;
  --accent-color: #3b82f6;
  
  display: flex;
  min-height: 100vh;
  background-color: var(--bg-color);
  color: var(--text-color);
  transition: all 0.3s ease;
}

/* VARIÁVEIS DO MODO CLARO */
:global(.light-mode) .admin-layout {
  --bg-color: #f8fafc;
  --sidebar-bg: #ffffff;
  --sidebar-text: #1e293b;
  --sidebar-border: #e2e8f0;
  --navbar-bg: #ffffff;
  --navbar-border: #e2e8f0;
  --text-color: #1e293b;
  --card-bg: #ffffff;
  --accent-color: #3b82f6; /* Blue 500 */
  --text-muted: #64748b; /* Slate 500 */
  --table-hover: #f1f5f9; /* Slate 100 */
  --table-stripe: #f8fafc; /* Slate 50 */
}

/* VARIÁVEIS DO MODO ESCURO (ARBITRAGE STYLE - CARBON GOLD) */
:global(.dark-mode) .admin-layout {
  --bg-color: #09090b; /* Zinc 950 */
  --sidebar-bg: #09090b; /* Zinc 950 */
  --sidebar-text: #f4f4f5; /* Zinc 100 */
  --sidebar-border: #27272a; /* Zinc 800 */
  --navbar-bg: #09090b; /* Zinc 950 */
  --navbar-border: #27272a; /* Zinc 800 */
  --text-color: #f4f4f5; /* Zinc 100 */
  --card-bg: #202023; /* Zinc 850 */
  --accent-color: #d97706; /* Amber 600 */
  --text-muted: #d4d4d8; /* Zinc 300 - DEIXA CABEÇALHO CONCISO/BRILHANTE */
  --table-hover: #27272a; /* Zinc 800 */
  --table-stripe: #18181b; /* Zinc 900 */
}

/* SIDEBAR */
.admin-sidebar {
  width: var(--sidebar-width);
  background-color: var(--sidebar-bg);
  color: var(--sidebar-text);
  transition: width 0.3s ease, background-color 0.3s ease;
  display: flex;
  flex-direction: column;
  box-shadow: 4px 0 10px rgba(0,0,0,0.05);
  position: sticky;
  top: 0;
  height: 100vh;
  border-right: 1px solid var(--sidebar-border);
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

:global(.dark-mode) .logo-img { --logo-filter: brightness(0) invert(1); }
:global(.light-mode) .logo-img { --logo-filter: none; }

.brand-name {
  font-weight: 700;
  font-size: 1.2rem;
  display: block;
}

.brand-version {
  font-size: 0.7rem;
  opacity: 0.8;
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
  font-size: 0.65rem; /* Reduzido */
  font-weight: 800;
  text-transform: uppercase;
  margin-bottom: 0.25rem; /* Reduzido */
  color: #3b82f6;
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
    background: var(--accent-color);
    color: #fff;
}

:deep(.custom-listbox .p-listbox-item:not(.p-highlight):hover) {
    background: rgba(var(--accent-color), 0.1);
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

.filter-header i { color: var(--accent-color); font-size: 0.9rem; }
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
  padding: 0.5rem 1rem;
}

:deep(.module-select-button .p-button.p-highlight) {
  background: var(--accent-color) !important;
  border-color: var(--accent-color) !important;
  color: #fff !important;
}

.nav-tabs {
  display: flex;
  gap: 0.5rem;
}

.nav-tab {
  padding: 0.5rem 1rem;
  text-decoration: none;
  color: var(--text-color);
  font-weight: 500;
  border-bottom: 2px solid transparent;
  transition: all 0.2s;
  border-radius: 8px;
}

.nav-tab:hover {
  background-color: rgba(var(--accent-color), 0.1);
  opacity: 1;
}

.nav-tab.active {
  background-color: var(--accent-color);
  color: #fff;
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
  background: var(--card-bg);
  color: var(--text-color);
  border-color: var(--sidebar-border);
}

:global(.admin-layout) .p-datatable .p-datatable-thead > tr > th {
  color: var(--text-muted);
  font-size: 0.75rem;
  text-transform: uppercase;
  font-weight: 600;
  border-bottom: 1px solid var(--sidebar-border);
}

:global(.admin-layout) .p-datatable .p-datatable-tbody > tr {
  background: var(--card-bg);
  color: var(--text-color);
  font-size: 0.85rem;
}

:global(.admin-layout) .p-datatable.p-datatable-striped .p-datatable-tbody > tr.p-row-odd {
    background: var(--table-stripe);
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
    background: var(--accent-color);
    color: #fff;
    border-color: var(--accent-color);
}

:global(.admin-layout) .p-dropdown .p-dropdown-panel {
  background: var(--card-bg);
  border-color: var(--sidebar-border);
}

:global(.p-dropdown-item) {
    font-size: 0.75rem !important; /* Tamanho compacto solicitado */
    padding: 0.5rem 0.75rem !important;
}

:global(.p-dropdown-header) {
    padding: 0.5rem !important;
    background: var(--card-bg) !important;
}

:global(.p-dropdown-filter-container .p-inputtext) {
    font-size: 0.75rem !important;
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
  background: var(--card-bg);
  border-color: var(--sidebar-border);
  color: var(--text-color); /* Correctly updates input text format across themes */
}

:global(.admin-layout) .p-inputtext:enabled:hover,
:global(.admin-layout) .p-dropdown:not(.p-disabled):hover {
  border-color: var(--accent-color);
}
</style>
