<script setup>
import { onMounted, onBeforeUnmount, ref } from 'vue';
import { useResultadoStore } from './stores/resultados';
import { useDashboardStore } from './stores/dashboard';
import { useGeoStore } from './stores/geo';
import { useFilterParameters } from './composables/useFilterParameters';
import axios from 'axios';
import { API_ENDPOINTS } from './config/api';

const resultadoStore = useResultadoStore();
const dashboardStore = useDashboardStore();
const geoStore = useGeoStore();
const { getApiParams } = useFilterParameters();
const isAppLoading = ref(true);
const syncProgress = ref(0);
const statusMessage = ref("Iniciando Sistema...");
let _bootTimer = null;
let _pollTimer = null;

const pollSyncStatus = async () => {
  try {
    const response = await axios.get(API_ENDPOINTS.cacheStatus);
    const { progress, status } = response.data;
    
    syncProgress.value = progress;
    
    if (status === 'ready' && progress === 100) {
      clearInterval(_pollTimer);
      statusMessage.value = "Finalizando Carga...";
      return true; // Finalizado
    } else if (status === 'fetching') {
      statusMessage.value = `Baixando dados do CGUData... (${progress}%)`;
    } else if (status === 'processing') {
      statusMessage.value = "Otimizando Banco de Dados...";
    }
    return false;
  } catch (err) {
    console.warn("Erro ao checar status:", err);
    return false;
  }
};

onMounted(async () => {
  try {
    // 1. Verifica status do cache
    const statusResp = await axios.get(API_ENDPOINTS.cacheStatus);
    const { is_ready, status } = statusResp.data;

    // Se NÃO estiver pronto, precisamos esperar (e talvez disparar a carga)
    if (!is_ready) {
      if (status === 'idle') {
        statusMessage.value = "Iniciando carga via CGUData...";
        await axios.post(API_ENDPOINTS.cacheRefresh);
      } else {
        statusMessage.value = "Sincronização em andamento no servidor...";
      }
      
      // Trava o boot até que o status seja 'ready'
      await new Promise((resolve) => {
        _pollTimer = setInterval(async () => {
          const finished = await pollSyncStatus();
          if (finished) resolve();
        }, 1000);
      });
    }

    // 2. Carga padrão dos dados do dashboard (só ocorre após cache pronto)
    statusMessage.value = "Sincronizando Dashboard...";
    const { inicio, fim, percMin, percMax, valMin, uf, regiaoSaude, municipio } = getApiParams();

    await Promise.allSettled([
      resultadoStore.fetchResultados(),
      dashboardStore.fetchDashboardSummary(inicio, fim, percMin, percMax, valMin, uf, regiaoSaude, municipio),
      dashboardStore.fetchFatorRisco(inicio, fim, percMin, percMax, valMin, uf, regiaoSaude, municipio),
      geoStore.fetchLocalidades()
    ]);

  } catch (error) {
    console.error("Erro crítico na carga inicial:", error);
    statusMessage.value = "Erro na conexão com o servidor.";
  } finally {
    _bootTimer = setTimeout(() => {
      isAppLoading.value = false;
    }, 800);
  }
});

onBeforeUnmount(() => {
  clearTimeout(_bootTimer);
  clearInterval(_pollTimer);
});
</script>

<template>
  <!-- OVERLAY DE CARREGAMENTO GLOBAL -->
  <div v-if="isAppLoading" class="app-boot-overlay">
     <div class="loader-container">
        <div class="sentinela-brand">
           <img src="/logo_sentinela.png" alt="Sentinela" class="boot-logo" />
           <span class="boot-brand-text">SENTINELA</span>
        </div>
        <div class="spinner-orbit">
           <div class="core"></div>
           <div class="electron one"></div>
           <div class="electron two"></div>
        </div>
         <p class="status-message">{{ statusMessage }}</p>
         <div class="progress-bar-mini" v-if="syncProgress > 0">
            <div class="progress-fill" :style="{ width: syncProgress + '%', animation: 'none' }"></div>
         </div>
         <div class="progress-bar-mini" v-else>
            <div class="progress-fill"></div>
         </div>
     </div>
  </div>

  <!-- O RouterView só aparece quando tudo está pronto -->
  <router-view v-else />
</template>

<style>
/* Estilos Globais Modernos (DNA Arbflow) */
:root {
  /* DESIGN TOKENS GLOBAIS (Arbflow DNA) */
  --sidebar-width: 280px;
  --sidebar-collapsed: 80px;
  --bg-color: #f8fafc;
  --text-color: #1e293b;
  --text-muted: #64748b;
  --card-bg: #ffffff;
  --sidebar-bg: #ffffff;
  --sidebar-text: #1e293b;
  --sidebar-border: #e2e8f0;
  --navbar-bg: #f8fafc;
  --navbar-border: #e2e8f0;

  /* Sobrescreve o surface-ground do PrimeVue Lara Light para o fundo correto */
  --surface-ground: #f8fafc;
  --surface-section: #f8fafc;

  /* Tabelas */
  --table-header-bg: #f8fafc;
  --table-header-text: #475569;
  --table-hover: #f1f5f9;
  --table-stripe: #f8fafc;

  /* Scrollbar */
  --scrollbar-track: #f8fafc;
  --scrollbar-thumb: #cbd5e1;
  --scrollbar-thumb-hover: #94a3b8;

  /* Cor Primária Sentinela */
  --primary-color: #3b82f6; 
}

:root.dark-mode {
  --bg-color: #0d1117;
  --text-color: #cbd5e1;
  --text-muted: #8b949e;
  --card-bg: #161b22;
  --sidebar-bg: #0d1117;
  --sidebar-text: #e6edf3;
  --sidebar-border: #30363d;
  --navbar-bg: #0d1117;
  --navbar-border: #30363d;

  /* Tabelas Dark */
  --table-header-bg: #1c2128;
  --table-header-text: #8b949e;
  --table-hover: #1f2937;
  --table-stripe: #131920;

  /* PRIME VUE INTERNAL SURFACES */
  --surface-0: #161b22;
  --surface-card: #161b22;
  --surface-ground: #0d1117;
  --surface-section: #0d1117;
  --surface-border: #30363d;

  /* Scrollbar Dark */
  --scrollbar-track: #0d1117;
  --scrollbar-thumb: #30363d;
  --scrollbar-thumb-hover: #484f58;

  /* Cor Primária Sentinela (Indigo Vibrante para Dark) */
  --primary-color: #6366f1;
}

/* FILTROS LOCAIS DE VIEW (TELEPORT) — disponível em todas as páginas */
.view-local-filters {
  display: flex;
  flex-direction: column;
}

.local-filter-header {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  font-size: 0.85rem;
  text-transform: uppercase;
  margin-bottom: 1rem;
  font-weight: 800;
  color: var(--text-color);
  letter-spacing: 1px;
}

.local-filter-header i {
  color: var(--primary-color);
}

.local-filter-section {
  margin-bottom: 1.5rem;
}

.local-filter-label {
  display: block;
  font-size: 0.8rem;
  text-transform: uppercase;
  margin-bottom: 0.75rem;
  font-weight: 600;
  color: var(--primary-color);
}

.flex-col { display: flex; flex-direction: column; }

/* COMPONENTES DE UI GLOBAIS (DESIGN SYSTEM SENTINELA) */
.shadow-card {
  background: var(--card-bg);
  border-radius: 16px;
  padding: 1.5rem;
  box-shadow: 0 2px 8px rgba(0,0,0,0.08), 0 0 1px rgba(0,0,0,0.06);
  border: 1px solid var(--navbar-border);
  transition: background-color 0.3s ease, transform 0.2s ease;
}

.section-header {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  margin-bottom: 1.5rem;
}

.section-header h3 {
  font-size: 1rem;
  font-weight: 700;
  color: var(--text-color);
  margin: 0;
  text-transform: uppercase;
  letter-spacing: 0.5px;
}

/* CARDS DE KPI MINI (COMUNS EM DASHBOARDS DE ALVOS/SÓCIOS) */
.kpi-mini-card {
  background: var(--card-bg);
  padding: 1rem 1.25rem;
  border-radius: 12px;
  border: 1px solid var(--sidebar-border);
  transition: transform 0.2s, background-color 0.3s ease;
  display: flex;
  align-items: center;
  gap: 1rem;
}

.kpi-mini-card:hover { 
  transform: translateY(-2px);
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
}

.kpi-mini-card.danger { 
  box-shadow: inset 0 0 0 1px rgba(239, 68, 68, 0.2); 
  border-color: rgba(239, 68, 68, 0.2); 
}

.kpi-content {
  display: flex;
  flex-direction: column;
}

.kpi-mini-card .label { 
  font-size: 0.75rem; 
  display: block; 
  text-transform: uppercase; 
  font-weight: 600; 
  color: var(--text-muted); 
}

.kpi-mini-card .value { 
  font-size: 1.5rem; 
  font-weight: 800; 
  color: var(--text-color); 
}

.kpi-icon {
  width: 2.75rem;
  height: 2.75rem;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 0.5rem;
  font-size: 1.25rem;
}

.kpi-icon.total { background: rgba(99, 102, 241, 0.15); color: #6366f1; } 
.kpi-icon.danger { background: rgba(239, 68, 68, 0.15); color: #ef4444; }

/* 🎨 BADGES ELEGANTES (PADRÃO ADMIN EVENTS) */
.p-tag {
    border-radius: 6px;
    padding: 2px 8px;
    font-weight: 700;
    font-size: 0.75rem;
    letter-spacing: 0.02em;
    min-width: 60px;
    text-align: center;
    border: 1px solid transparent;
}

/* Base Light Mode Badges (Tons mais escuros para o texto ler bem no branco) */
.risk-low {
    background: rgba(34, 197, 94, 0.12) !important;
    color: #166534 !important; /* Green 800 */
    border: 1px solid rgba(34, 197, 94, 0.25) !important;
}

.risk-medium {
    background: rgba(245, 158, 11, 0.15) !important;
    color: #92400e !important; /* Amber 800 */
    border: 1px solid rgba(245, 158, 11, 0.25) !important;
}

.risk-high {
    background: rgba(239, 68, 68, 0.12) !important;
    color: #991b1b !important; /* Red 800 */
    border: 1px solid rgba(239, 68, 68, 0.25) !important;
}

/* Dark Mode Badges (Tons mais claros para destacar no fundo escuro) */
body.dark-mode .risk-low {
    color: #4ade80 !important; /* Green 400 */
}

body.dark-mode .risk-medium {
    color: #fbbf24 !important; /* Amber 400 */
}

body.dark-mode .risk-high {
    color: #f87171 !important; /* Red 400 */
}

/* OVERLAY DE CARREGAMENTO GLOBAL - DESIGN PREMIUM */
.app-boot-overlay {
  position: fixed;
  inset: 0;
  background: radial-gradient(circle at center, #0f172a, #020617);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 9999;
}

.loader-container {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 2rem;
  color: white;
}

.sentinela-brand {
  display: flex;
  align-items: center;
  gap: 1.25rem;
  font-family: 'Outfit', sans-serif;
}

.boot-logo {
  width: 80px;
  filter: drop-shadow(0 0 15px rgba(59, 130, 246, 0.4));
  animation: logo-pulse 2s ease-in-out infinite;
}

@keyframes logo-pulse {
  0%, 100% { transform: scale(1); opacity: 1; }
  50% { transform: scale(1.05); opacity: 0.9; }
}

.boot-brand-text {
  font-size: 1.8rem;
  font-weight: 900;
  letter-spacing: 4px;
  background: linear-gradient(to right, #fff, #cbd5e1);
  -webkit-background-clip: text;
  background-clip: text;
  -webkit-text-fill-color: transparent;
}

/* SPINNER ATÔMICO */
.spinner-orbit {
  position: relative;
  width: 80px;
  height: 80px;
  display: flex;
  align-items: center;
  justify-content: center;
}

.core {
  width: 12px;
  height: 12px;
  background-color: #3b82f6;
  border-radius: 50%;
  box-shadow: 0 0 20px #3b82f6;
}

.electron {
  position: absolute;
  border: 1px solid rgba(148, 163, 184, 0.3);
  border-radius: 50%;
}

.one {
  width: 60px;
  height: 60px;
  animation: orbit 2s linear infinite;
}

.one::after {
  content: '';
  position: absolute;
  top: 50%;
  left: -3px;
  width: 6px;
  height: 6px;
  background: #3b82f6;
  border-radius: 50%;
}

.two {
  width: 40px;
  height: 40px;
  animation: orbit 1.5s linear reverse infinite;
}

.two::after {
  content: '';
  position: absolute;
  top: 0;
  left: 50%;
  width: 4px;
  height: 4px;
  background: #60a5fa;
  border-radius: 50%;
}

@keyframes orbit {
  from { transform: rotate(0deg); }
  to { transform: rotate(360deg); }
}

.status-message {
  font-size: 0.9rem;
  font-weight: 500;
  color: #cbd5e1;
  letter-spacing: 1px;
}

.progress-bar-mini {
  width: 200px;
  height: 2px;
  background: rgba(255, 255, 255, 0.1);
  border-radius: 1px;
  overflow: hidden;
}

.progress-fill {
  width: 100%;
  height: 100%;
  background: #3b82f6;
  animation: loading-bar 2s ease-in-out infinite;
  transform-origin: left;
}

@keyframes loading-bar {
  0% { transform: scaleX(0); }
  50% { transform: scaleX(1); }
  100% { transform: scaleX(0); transform-origin: right; }
}

html, body {
  margin: 0;
  font-family: 'Inter', -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
  background-color: var(--bg-color) !important;
  color: var(--text-color) !important;
  transition: background-color 0.3s ease;
  /* Suporte moderno para Firefox e Chrome 121+ */
  scrollbar-color: var(--scrollbar-thumb) var(--scrollbar-track);
  scrollbar-width: thin;
}

/* Garante que o modo escuro seja aplicado ao root para o scrollbar da janela */
:root.dark-mode {
  color-scheme: dark !important;
}

html.dark-mode {
  scrollbar-color: #30363d #0d1117 !important;
}

/* Scrollbar Bonito Adaptável - AGRESSIVO */
* {
  scrollbar-color: var(--scrollbar-thumb) var(--scrollbar-track) !important;
  scrollbar-width: thin !important;
}

::-webkit-scrollbar {
  width: 10px !important;
  height: 10px !important;
}
::-webkit-scrollbar-track {
  background: var(--scrollbar-track) !important;
}
::-webkit-scrollbar-thumb {
  background: var(--scrollbar-thumb) !important;
  border-radius: 10px !important;
  border: 2px solid var(--scrollbar-track) !important;
}
::-webkit-scrollbar-thumb:hover {
  background: var(--scrollbar-thumb-hover) !important;
}

/* 🎨 SOBREPOSIÇÃO GLOBAL PARA DIÁLOGOS (CORREÇÃO DARK MODE) */
.p-dialog {
    background: var(--card-bg) !important;
    color: var(--text-color) !important;
    border: 1px solid var(--sidebar-border) !important;
    box-shadow: 0 10px 25px rgba(0,0,0,0.5) !important;
}

.p-dialog-header, 
.p-dialog-content, 
.p-dialog-footer {
    background: var(--card-bg) !important;
    color: var(--text-color) !important;
}

.p-dialog .p-dialog-header .p-dialog-title,
.p-dialog .p-dialog-header .p-dialog-header-icon {
    color: var(--text-color) !important;
}

.p-dialog .p-button-label {
    font-weight: 700;
}
</style>
