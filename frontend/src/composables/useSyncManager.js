/**
 * Gerencia o fluxo de sincronização/re-cache do servidor.
 * Encapsula polling, tratamento de erros e cleanup do interval.
 */
import { ref, onBeforeUnmount } from 'vue';
import axios from 'axios';
import { useFilterStore } from '@/stores/filters';
import { API_ENDPOINTS } from '@/config/api';
import { TIMING } from '@/config/constants';

export function useSyncManager() {
  const filterStore = useFilterStore();

  const isSyncing        = ref(false);
  const showConfirmSync  = ref(false);
  const syncProgress     = ref(0);
  const syncError        = ref(false);
  const syncErrorMessage = ref('');
  let _pollTimer         = null;

  const _stopPolling = () => {
    if (_pollTimer) {
      clearInterval(_pollTimer);
      _pollTimer = null;
    }
  };

  const _setError = (msg) => {
    _stopPolling();
    syncError.value        = true;
    syncErrorMessage.value = msg;
  };

  const dismissError = () => {
    syncError.value        = false;
    syncErrorMessage.value = '';
    isSyncing.value        = false;
    syncProgress.value     = 0;
  };

  const _startPolling = () => {
    _pollTimer = setInterval(pollSyncStatus, TIMING.POLL_INTERVAL);
  };

  const pollSyncStatus = async () => {
    try {
      const response = await axios.get(API_ENDPOINTS.cacheStatus);
      const { progress, status } = response.data;
      syncProgress.value = progress;

      if (status === 'ready' && progress === 100) {
        _stopPolling();
        setTimeout(() => window.location.reload(), TIMING.RELOAD_DELAY);
      } else if (status === 'error') {
        _setError('Ocorreu um erro durante a sincronização no servidor. Verifique a conectividade com o banco de dados e tente novamente.');
      }
    } catch (err) {
      console.error('Erro ao consultar status:', err);
    }
  };

  const handleSync = async () => {
    showConfirmSync.value  = false;
    isSyncing.value        = true;
    syncProgress.value     = 0;
    syncError.value        = false;
    syncErrorMessage.value = '';
    filterStore.resetFilters();

    try {
      await axios.post(API_ENDPOINTS.cacheRefresh);
      _startPolling();
    } catch (err) {
      console.error('Erro ao iniciar sincronização:', err);
      _setError('Falha ao conectar com o servidor para iniciar a sincronização. Verifique se o serviço está ativo.');
    }
  };

  const retrySync = () => {
    syncError.value        = false;
    syncErrorMessage.value = '';
    handleSync();
  };

  // Garante limpeza do interval mesmo se o componente for desmontado durante o polling
  onBeforeUnmount(_stopPolling);

  return { isSyncing, showConfirmSync, syncProgress, syncError, syncErrorMessage, handleSync, retrySync, dismissError };
}
