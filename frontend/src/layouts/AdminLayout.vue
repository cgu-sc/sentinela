<script setup>
import { ref, onMounted } from 'vue';
import { useThemeStore } from '../stores/theme';
import Button from 'primevue/button';
import InputText from 'primevue/inputtext';
import Dropdown from 'primevue/dropdown';
import Calendar from 'primevue/calendar';
import Slider from 'primevue/slider';

const themeStore = useThemeStore();

// Init Theme on mount
onMounted(() => {
  themeStore.initTheme();
});

// Estado dos Filtros
const ufOptions = ref(['Todos', 'AC', 'AL', 'AM', 'AP', 'BA', 'CE', 'DF', 'ES', 'GO', 'MA', 'MG', 'MS', 'MT', 'PA', 'PB', 'PE', 'PI', 'PR', 'RJ', 'RN', 'RO', 'RR', 'RS', 'SC', 'SE', 'SP', 'TO']);
const selectedUF = ref('Todos');
const naoComprovacaoRange = ref([0, 100]);
const periodo = ref([new Date(2016, 0, 1), new Date(2024, 11, 1)]);

// Controle de Menu
const isCollapsed = ref(false);

const limparFiltros = () => {
    selectedUF.value = 'Todos';
    naoComprovacaoRange.value = [0, 100];
    periodo.value = [new Date(2016, 0, 1), new Date(2024, 11, 1)];
};
</script>

<template>
  <div class="admin-layout" :class="{ 'collapsed': isCollapsed }">
    <!-- BARRA LATERAL DE FILTROS (STYLE: ARBFLOW) -->
    <aside class="admin-sidebar">
      <div class="sidebar-header">
        <div class="brand">
          <img src="/logo_sentinela.png" alt="Sentinela V3" class="logo-img" />
          <div class="brand-text" v-show="!isCollapsed">
            <span class="brand-name">SENTINELA</span>
            <span class="brand-version">V3 CONSOLIDADO</span>
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
        <!-- SEÇÃO: UF -->
        <div class="filter-section">
          <label class="filter-label">UF</label>
          <Dropdown v-model="selectedUF" :options="ufOptions" placeholder="Selecione a UF" class="w-full filter-input" />
        </div>

        <!-- SEÇÃO: % de não comprovação -->
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

        <!-- SEÇÃO: Período -->
        <div class="filter-section">
          <label class="filter-label">Período</label>
          <Calendar v-model="periodo" selectionMode="range" :manualInput="false" showIcon iconDisplay="input" class="w-full filter-input" />
        </div>

        <div class="sidebar-spacer"></div>

        <Button label="Limpar Filtros" icon="pi pi-undo" outlined severity="secondary" @click="limparFiltros" class="w-full mb-4" />
      </div>

      <div class="sidebar-footer" v-show="!isCollapsed">
        <p>© 2024 Sentinela - Auditoria</p>
      </div>
    </aside>

    <!-- ÁREA DE CONTEÚDO PRINCIPAL (NAVBAR + VIEW) -->
    <main class="main-container">
      <nav class="top-navbar">
        <div class="nav-tabs">
          <router-link to="/" class="nav-tab active">Análise Nacional</router-link>
          <router-link to="/dispersao" class="nav-tab">Dispersão Benefício</router-link>
          <router-link to="/municipio" class="nav-tab">Análise Município</router-link>
          <router-link to="/empresa" class="nav-tab">Análise Empresa</router-link>
          <router-link to="/cnpj" class="nav-tab">Análise CNPJ</router-link>
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
}

/* VARIÁVEIS DO MODO ESCURO (ARBITRAGE STYLE) */
:global(.dark-mode) .admin-layout {
  --bg-color: #0f172a; /* Slate 900 */
  --sidebar-bg: #1e293b; /* Slate 800 */
  --sidebar-text: #f8fafc;
  --sidebar-border: #334155;
  --navbar-bg: #1e293b;
  --navbar-border: #334155;
  --text-color: #f8fafc;
  --card-bg: #1e293b;
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
  opacity: 0.6;
}

.sidebar-content {
  padding: 1.5rem;
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 2rem;
}

.filter-label {
  display: block;
  font-size: 0.8rem;
  text-transform: uppercase;
  margin-bottom: 0.75rem;
  font-weight: 600;
  color: var(--accent-color);
  opacity: 0.8;
}

.slider-values {
  display: flex;
  justify-content: space-between;
  font-size: 0.75rem;
  margin-bottom: 0.5rem;
}

.sidebar-spacer { flex: 1; }

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

.nav-tabs {
  display: flex;
  gap: 0.5rem;
}

.nav-tab {
  padding: 0.5rem 1rem;
  text-decoration: none;
  color: var(--text-color);
  opacity: 0.7;
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
</style>
