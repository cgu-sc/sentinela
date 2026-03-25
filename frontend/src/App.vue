<script setup>
import { onMounted, ref } from 'vue';
import { useResultadoStore } from './stores/resultados';
import { useDashboardStore } from './stores/dashboard';

const resultadoStore = useResultadoStore();
const dashboardStore = useDashboardStore();
const isAppLoading = ref(true);

onMounted(async () => {
  try {
    // Dispara a carga simultânea (Paralelo) de toda a inteligência do sistema
    // Aguardamos todas terminarem antes de liberar a UI
    await Promise.all([
      resultadoStore.fetchResultados(),
      dashboardStore.fetchDashboardSummary(),
      dashboardStore.fetchFatorRisco()
    ]);
  } catch (error) {
    console.error("Erro crítico na carga inicial:", error);
  } finally {
    // Pequeno delay para suavidade na transição visual
    setTimeout(() => {
      isAppLoading.value = false;
    }, 800);
  }
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
        <p class="status-message">Sincronizando Dados...</p>
        <div class="progress-bar-mini">
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
  --p-primary-color: #3b82f6; 
  
  /* DESIGN TOKENS GLOBAIS (Arbflow DNA) */
  --sidebar-width: 280px;
  --bg-color: color-mix(in srgb, var(--p-primary-color) 4%, #f8fafc);
  --text-color: #1e293b;
  --text-muted: #64748b;
  --card-bg: #ffffff;
  --sidebar-bg: #ffffff;
  --sidebar-text: #1e293b;
  --sidebar-border: #e2e8f0;
  --navbar-bg: #ffffff;
  --navbar-border: #e2e8f0;

  /* Tabelas */
  --table-header-bg: #f8fafc;
  --table-header-text: #475569;
  --table-hover: #f1f5f9;
  --table-stripe: #fcfcfd;
}

body.dark-mode {
  --bg-color: color-mix(in srgb, var(--p-primary-color) 2%, #09090b);
  --text-color: #cbd5e1; /* Slate 300 - Muito mais confortável */
  --text-muted: #71717a; /* Zinc 400 */
  --card-bg: #18181b; 
  --sidebar-bg: #09090b;
  --sidebar-text: #f4f4f5;
  --sidebar-border: #27272a;
  --navbar-bg: #09090b;
  --navbar-border: #27272a;

  /* Tabelas Dark */
  --table-header-bg: #202023; 
  --table-header-text: #94a3b8;
  --table-hover: #212124;
  --table-stripe: #121214;

  /* PRIME VUE INTERNAL SURFACES - O SEGREDO PARA A TABELA */
  --surface-0: #18181b;
  --surface-card: #18181b;
  --surface-ground: #0c0c0e;
  --surface-section: #0c0c0e;
  --surface-border: #27272a;
}

/* COMPONENTES DE UI GLOBAIS (DESIGN SYSTEM SENTINELA) */
.shadow-card {
  background: var(--card-bg);
  border-radius: 16px;
  padding: 1.5rem;
  box-shadow: 0 1px 3px rgba(0,0,0,0.1);
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

body {
  margin: 0;
  font-family: 'Inter', -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
  background-color: #f1f5f9;
  transition: background-color 0.3s ease;
}

body.dark-mode {
  background-color: #09090b;
}

/* Scrollbar Bonito */
::-webkit-scrollbar {
  width: 8px;
  height: 8px;
}
::-webkit-scrollbar-track {
  background: #f1f5f9;
}
::-webkit-scrollbar-thumb {
  background: #cbd5e1;
  border-radius: 4px;
}
::-webkit-scrollbar-thumb:hover {
  background: #94a3b8;
}
</style>
