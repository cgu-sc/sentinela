<script setup>
import { onMounted, onBeforeUnmount, ref } from 'vue';
import { useResultadoStore } from '@/stores/resultados';
import { useAnalyticsStore } from '@/stores/analytics';
import { useGeoStore } from '@/stores/geo';
import { useFilterParameters } from '@/composables/useFilterParameters';
import axios from 'axios';
import { API_ENDPOINTS } from '@/config/api';
import { TIMING } from '@/config/constants';

const resultadoStore = useResultadoStore();
const analyticsStore = useAnalyticsStore();
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
        }, TIMING.POLL_INTERVAL);
      });
    }

    // 2. Carga padrão dos dados do dashboard (só ocorre após cache pronto)
    statusMessage.value = "Sincronizando Dashboard...";
    const { inicio, fim, percMin, percMax, valMin, uf, regiaoSaude, municipio } = getApiParams();

    await Promise.allSettled([
      resultadoStore.fetchResultados(),
      analyticsStore.fetchDashboardSummary(inicio, fim, percMin, percMax, valMin, uf, regiaoSaude, municipio),
      analyticsStore.fetchFatorRisco(inicio, fim, percMin, percMax, valMin, uf, regiaoSaude, municipio),
      geoStore.fetchLocalidades(),
      geoStore.loadMunicipiosGeo(),
      geoStore.fetchEstabelecimentos(),
    ]);

  } catch (error) {
    console.error("Erro crítico na carga inicial:", error);
    statusMessage.value = "Erro na conexão com o servidor.";
  } finally {
    _bootTimer = setTimeout(() => {
      isAppLoading.value = false;
    }, TIMING.RELOAD_DELAY);
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
/* Estilos específicos do App.vue se necessário no futuro */
</style>
