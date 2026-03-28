/**
 * Gerencia o fluxo de sincronização/re-cache do servidor.
 * Encapsula polling, tratamento de erros e cleanup do interval.
 */
import { ref, onBeforeUnmount } from 'vue';
import axios from 'axios';
import { useFilterStore } from '@/stores/filters';
import { API_ENDPOINTS } from '@/config/api';

export function useSyncManager() {
  const filterStore = useFilterStore();

  const isSyncing       = ref(false);
  const showConfirmSync = ref(false);
  const syncProgress    = ref(0);
  let _pollTimer        = null;

  const _stopPolling = () => {
    if (_pollTimer) {
      clearInterval(_pollTimer);
      _pollTimer = null;
    }
  };

  const pollSyncStatus = async () => {
    try {
      const response = await axios.get(API_ENDPOINTS.cacheStatus);
      const { progress, status } = response.data;
      syncProgress.value = progress;

      if (status === 'ready' && progress === 100) {
        _stopPolling();
        setTimeout(() => window.location.reload(), 800);
      } else if (status === 'error') {
        _stopPolling();
        alert('Ocorreu um erro durante a sincronização no servidor.');
        isSyncing.value = false;
      }
    } catch (err) {
      console.error('Erro ao consultar status:', err);
    }
  };

  const handleSync = async () => {
    showConfirmSync.value = false;
    isSyncing.value       = true;
    syncProgress.value    = 0;
    filterStore.resetFilters();

    try {
      await axios.post(API_ENDPOINTS.cacheRefresh);
      _pollTimer = setInterval(pollSyncStatus, 1000);
    } catch (err) {
      console.error('Erro ao iniciar sincronização:', err);
      alert('Falha ao conectar com o servidor para sincronização.');
      isSyncing.value = false;
    }
  };

  // Garante limpeza do interval mesmo se o componente for desmontado durante o polling
  onBeforeUnmount(_stopPolling);

  return { isSyncing, showConfirmSync, syncProgress, handleSync };
}
