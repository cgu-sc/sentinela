<script setup>
import { onMounted, onBeforeUnmount, ref } from 'vue';
import { useResultadoStore } from '@/stores/resultados';
import { useAnalyticsStore } from '@/stores/analytics';
import { useGeoStore } from '@/stores/geo';
import { useConfigStore } from '@/stores/config';
import { useFilterParameters } from '@/composables/useFilterParameters';
import axios from 'axios';
import { API_ENDPOINTS } from '@/config/api';
import { TIMING } from '@/config/constants';
import { useThemeStore } from '@/stores/theme';

const resultadoStore = useResultadoStore();
const analyticsStore = useAnalyticsStore();
const geoStore = useGeoStore();
const configStore = useConfigStore();
const themeStore = useThemeStore();
const { getApiParams } = useFilterParameters();
const isAppLoading = ref(true);
const syncProgress = ref(0);
const statusMessage = ref("Iniciando Sistema...");
const hasError = ref(false);
const errorMessageDetail = ref("");
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
      return true;
    } else if (status === 'error' || status === 'idle') {
      // Sync falhou ou foi abortada — não fica em loop, deixa o app subir
      clearInterval(_pollTimer);
      return true;
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

const initializeApp = async () => {
  hasError.value = false;
  errorMessageDetail.value = "";
  isAppLoading.value = true;
  statusMessage.value = "Iniciando Sistema...";
  syncProgress.value = 0;

  try {
    // 1. Verifica status do cache
    const statusResp = await axios.get(API_ENDPOINTS.cacheStatus);
    const { is_ready, status } = statusResp.data;

    // Se uma sincronização já estiver em andamento (iniciada externamente),
    // aguarda ela terminar antes de carregar o dashboard.
    // Se o cache estiver ausente mas nenhuma sync estiver rodando (idle/error),
    // o app inicializa normalmente — o DataIntegrityBanner informa o usuário.
    if (!is_ready && (status === 'fetching' || status === 'processing')) {
      statusMessage.value = "Sincronização em andamento no servidor...";
      await new Promise((resolve) => {
        _pollTimer = setInterval(async () => {
          const finished = await pollSyncStatus();
          if (finished) resolve();
        }, TIMING.POLL_INTERVAL);
      });
    }

    // 2. Carga padrão dos dados do dashboard (só ocorre quando cache estiver pronto)
    // Re-lê o status após eventual wait de sync acima
    const currentStatus = await axios.get(API_ENDPOINTS.cacheStatus);
    if (!currentStatus.data.is_ready) {
      // Sistema subirá em "modo degradado". 
      // Não fazemos mais 'return;' aqui, permitindo que a UI carregue o que existir na mémoria.
      console.warn("Alguns caches estão ausentes. Iniciando em Modo Degradado.");
    }

    statusMessage.value = "Sincronizando Dashboard...";
    const { inicio, fim, percMin, percMax, valMin, uf, regiaoSaude, municipio, situacaoRf, conexaoMs, porteEmpresa, grandeRede, cnpjRaiz, unidadePf } = getApiParams();

    const fetchList = [
      resultadoStore.fetchResultados(),
      analyticsStore.fetchDashboardSummary(inicio, fim, percMin, percMax, valMin, uf, regiaoSaude, municipio, situacaoRf, conexaoMs, porteEmpresa, grandeRede, cnpjRaiz, unidadePf),
      analyticsStore.fetchFatorRisco(inicio, fim, percMin, percMax, valMin, uf, regiaoSaude, municipio, situacaoRf, conexaoMs, porteEmpresa, grandeRede, cnpjRaiz, unidadePf),
      geoStore.fetchLocalidades(),
      geoStore.loadMunicipiosGeo(),
      geoStore.fetchEstabelecimentos(),
      geoStore.fetchCnpjLookup(),
      configStore.fetchThresholds(),
    ];

    // Se houver filtros geográficos ativos, o fetchDashboardSummary NÃO popula
    // resultadoSentinelaUFNacional (por design). Forçamos a busca nacional aqui
    // para garantir que o mapa do Brasil sempre seja exibido corretamente.
    if (uf || regiaoSaude || municipio || unidadePf) {
      fetchList.push(
        analyticsStore.fetchSentinelaUFNacional(inicio, fim, percMin, percMax, valMin, situacaoRf, conexaoMs, porteEmpresa, grandeRede, unidadePf)
      );
    }

    await Promise.allSettled(fetchList);

    if (!hasError.value) {
      _bootTimer = setTimeout(() => {
        isAppLoading.value = false;
      }, TIMING.RELOAD_DELAY);
    }

  } catch (error) {
    console.error("Erro crítico na carga inicial:", error);
    statusMessage.value = "Erro na conexão com o servidor.";
    errorMessageDetail.value = error.response?.data?.message || error.message || String(error);
    hasError.value = true;
  }
};

const retryConnection = () => {
  initializeApp();
};

onMounted(() => {
  themeStore.initTheme();
  initializeApp();
});

onBeforeUnmount(() => {
  clearTimeout(_bootTimer);
  clearInterval(_pollTimer);
});
</script>

<template>
  <!-- OVERLAY DE CARREGAMENTO GLOBAL -->
  <div v-if="isAppLoading" class="app-boot-overlay">

     <!-- Logo fixada no topo, independente do conteúdo -->
     <div class="boot-brand-anchor">
        <img src="/img/logo_sentinela_transparente.png" alt="Sentinela" class="boot-logo" />
        <div class="boot-brand-caption">
           <span class="boot-brand-text">SENTINELA</span>
           <span class="boot-brand-sub">Auditoria no Farmácia Popular</span>
        </div>
     </div>

     <!-- Conteúdo central dinâmico (spinner ou erro) -->
     <div class="boot-dynamic-content">
        <template v-if="!hasError">
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
        </template>

        <!-- Estado de Erro Profissional -->
        <template v-else>
           <div class="error-state-container">
              <svg class="error-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                 <circle cx="12" cy="12" r="10"></circle>
                 <line x1="12" y1="8" x2="12" y2="12"></line>
                 <line x1="12" y1="16" x2="12.01" y2="16"></line>
              </svg>
              <h2 class="error-title">Falha de Conexão</h2>
              <p class="status-message error-desc">
                 Não foi possível comunicar com o servidor backend.<br/>
                 Verifique se o serviço está ativo e tente novamente.
              </p>
              <div class="error-detail-box" v-if="errorMessageDetail">
                 <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="#ef4444" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="flex-shrink: 0;">
                    <polyline points="4 17 10 11 4 5"></polyline>
                    <line x1="12" y1="19" x2="20" y2="19"></line>
                 </svg>
                 <code>{{ errorMessageDetail }}</code>
              </div>
              <button @click="retryConnection" class="retry-button">
                 <svg class="retry-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <polyline points="1 4 1 10 7 10"></polyline>
                    <polyline points="23 20 23 14 17 14"></polyline>
                    <path d="M20.49 9A9 9 0 0 0 5.64 5.64L1 10M23 14l-4.64 4.36A9 9 0 0 1 3.51 15"></path>
                 </svg>
                 Tentar Novamente
              </button>
           </div>
        </template>
     </div>

  </div>

  <!-- O RouterView só aparece quando tudo está pronto -->
  <router-view v-else />
</template>

<style scoped>
.error-state-container {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  animation: fadeIn 0.4s ease-out;
  margin-top: 1.5rem;
}

.error-icon {
  width: 56px;
  height: 56px;
  stroke: #ef4444;
  margin-bottom: 1rem;
  filter: drop-shadow(0 0 8px rgba(239, 68, 68, 0.4));
}

.error-title {
  color: #f8fafc;
  font-size: 1.15rem;
  font-weight: 500;
  margin: 0 0 0.5rem 0;
  letter-spacing: 0.5px;
}

.error-desc {
  max-width: 320px;
  line-height: 1.5;
  margin-bottom: 1rem;
  color: #94a3b8;
}

.error-detail-box {
  display: flex !important;
  flex-direction: row !important;
  align-items: center;
  justify-content: flex-start;
  gap: 12px;
  background: rgba(239, 68, 68, 0.05) !important;
  border: 1px solid rgba(239, 68, 68, 0.25) !important;
  border-radius: 8px;
  padding: 12px 16px;
  margin-top: 8px;
  margin-bottom: 32px;
  width: 100%;
  max-width: 450px;
}

.error-detail-box code {
  color: #fca5a5 !important;
  font-size: 0.85rem;
  letter-spacing: 0.5px;
  overflow-wrap: break-word;
  word-break: break-word;
  text-align: left;
  line-height: 1.4;
  margin: 0;
}

.retry-button {
  background: linear-gradient(135deg, #3b82f6 0%, #2563eb 100%);
  color: white;
  border: none;
  padding: 0.65rem 1.25rem;
  border-radius: 8px;
  font-size: 0.9rem;
  font-weight: 500;
  cursor: pointer;
  display: flex;
  align-items: center;
  gap: 0.5rem;
  transition: all 0.2s ease;
  box-shadow: 0 4px 12px rgba(37, 99, 235, 0.25);
  font-family: inherit;
}

.retry-button:hover {
  transform: translateY(-2px);
  box-shadow: 0 6px 16px rgba(37, 99, 235, 0.4);
}

.retry-button:active {
  transform: translateY(0);
}

.retry-icon {
  width: 16px;
  height: 16px;
}

@keyframes fadeIn {
  from { opacity: 0; transform: translateY(10px); }
  to { opacity: 1; transform: translateY(0); }
}
</style>
