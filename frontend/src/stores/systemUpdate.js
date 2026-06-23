import { defineStore } from 'pinia';
import { ref, computed } from 'vue';
import axios from 'axios';
import { API_ENDPOINTS } from '@/config/api';

export const useSystemUpdateStore = defineStore('systemUpdate', () => {
  // ─── Estado de verificação ──────────────────────────────────────────────────
  const status = ref(null);       // 'current' | 'update_available' | 'update_required' | 'offline_cached' | 'verification_unavailable'
  const currentVersion = ref(null);
  const latestVersion = ref(null);
  const minimumVersion = ref(null);
  const downloadUrl = ref(null);
  const releaseNotesUrl = ref(null);
  const checkedAt = ref(null);
  const source = ref(null);       // 'remote' | 'cache' | 'none'
  const message = ref('');
  const loading = ref(false);

  // ─── Estado de download automático ──────────────────────────────────────────
  const downloadStatus = ref('idle');   // idle | downloading | applying | done | error
  const downloadProgress = ref(0);      // 0–100 (percentual inteiro para a barra)
  const downloadError = ref(null);
  const downloadDialogVisible = ref(false);
  let _progressInterval = null;

  // ─── Computed de verificação ─────────────────────────────────────────────────
  const isBlocked = computed(() => status.value === 'update_required');
  const hasUpdate = computed(() => status.value === 'update_available');
  const isOffline = computed(() => status.value === 'offline_cached');
  const isUnavailable = computed(() => status.value === 'verification_unavailable');
  const isCurrent = computed(() => status.value === 'current');

  const statusLabel = computed(() => {
    switch (status.value) {
      case 'current':                  return 'Atualizado';
      case 'update_available':         return 'Atualização disponível';
      case 'update_required':          return 'Atualização obrigatória';
      case 'offline_cached':           return 'Verificação offline';
      case 'verification_unavailable': return 'Não verificado';
      default:                         return '—';
    }
  });

  const statusTone = computed(() => {
    switch (status.value) {
      case 'current':                  return 'ok';
      case 'update_available':         return 'warn';
      case 'update_required':          return 'critical';
      case 'offline_cached':           return 'muted';
      case 'verification_unavailable': return 'muted';
      default:                         return 'muted';
    }
  });

  const checkedAtFormatted = computed(() => {
    if (!checkedAt.value) return null;
    try {
      return new Intl.DateTimeFormat('pt-BR', {
        day: '2-digit', month: '2-digit', year: 'numeric',
        hour: '2-digit', minute: '2-digit',
      }).format(new Date(checkedAt.value));
    } catch {
      return null;
    }
  });

  // ─── Computed de download ────────────────────────────────────────────────────
  const isDownloading = computed(() =>
    downloadStatus.value === 'downloading' || downloadStatus.value === 'applying'
  );
  const downloadDone = computed(() => downloadStatus.value === 'done');
  const downloadFailed = computed(() => downloadStatus.value === 'error');

  const downloadStatusLabel = computed(() => {
    switch (downloadStatus.value) {
      case 'idle':        return 'Aguardando';
      case 'downloading': return `Baixando... ${downloadProgress.value}%`;
      case 'applying':    return 'Preparando arquivos...';
      case 'done':        return 'Aguarde, iniciando a atualização...';
      case 'error':       return 'Falha no download';
      default:            return '';
    }
  });

  // ─── Ações de verificação ────────────────────────────────────────────────────
  function _applyResponse(data) {
    status.value          = data.status;
    currentVersion.value  = data.current_version;
    latestVersion.value   = data.latest_version;
    minimumVersion.value  = data.minimum_supported_version;
    downloadUrl.value     = data.download_url;
    releaseNotesUrl.value = data.release_notes_url;
    checkedAt.value       = data.checked_at;
    source.value          = data.source;
    message.value         = data.message;
  }

  async function fetchUpdateStatus() {
    try {
      const { data } = await axios.get(API_ENDPOINTS.systemUpdateStatus);
      _applyResponse(data);
    } catch (err) {
      console.warn('[systemUpdate] Erro ao buscar status de atualização:', err);
      if (!status.value) {
        status.value = 'verification_unavailable';
        message.value = 'Não foi possível verificar atualizações.';
        source.value = 'none';
      }
    }
  }

  async function forceCheckUpdate() {
    loading.value = true;
    try {
      const { data } = await axios.post(API_ENDPOINTS.systemCheckUpdate);
      _applyResponse(data);
    } catch (err) {
      console.warn('[systemUpdate] Erro ao forçar verificação:', err);
    } finally {
      loading.value = false;
    }
  }

  // ─── Ações de download automático ────────────────────────────────────────────

  function _startProgressPolling() {
    if (_progressInterval) return;
    _progressInterval = setInterval(async () => {
      try {
        const { data } = await axios.get(API_ENDPOINTS.systemDownloadProgress);
        downloadStatus.value   = data.status;
        downloadProgress.value = Math.round((data.progress ?? 0) * 100);
        downloadError.value    = data.error ?? null;

        if (data.status === 'done') {
          _stopProgressPolling();
          applyUpdate();
        } else if (data.status === 'error') {
          _stopProgressPolling();
        }
      } catch (err) {
        console.warn('[systemUpdate] Erro ao consultar progresso:', err);
      }
    }, 800);
  }

  function _stopProgressPolling() {
    if (_progressInterval) {
      clearInterval(_progressInterval);
      _progressInterval = null;
    }
  }

  async function applyUpdate() {
    try {
      await axios.post(API_ENDPOINTS.systemApplyUpdate);
    } catch (err) {
      console.warn('[systemUpdate] Erro ao aplicar atualização:', err);
    }
  }

  async function startDownload(overrideUrl = null) {
    downloadStatus.value   = 'downloading';
    downloadProgress.value = 0;
    downloadError.value    = null;
    downloadDialogVisible.value = true;

    try {
      await axios.post(API_ENDPOINTS.systemDownloadUpdate, overrideUrl ? { download_url: overrideUrl } : undefined);
      _startProgressPolling();
    } catch (err) {
      const detail = err?.response?.data?.detail ?? err?.message ?? 'Erro desconhecido.';
      downloadStatus.value  = 'error';
      downloadError.value   = detail;
      console.error('[systemUpdate] Falha ao iniciar download:', detail);
    }
  }

  function openDownloadDialog() {
    downloadDialogVisible.value = true;
  }

  function closeDownloadDialog() {
    if (isDownloading.value) return; // bloqueia fechar durante download
    downloadDialogVisible.value = false;
    if (downloadStatus.value === 'done' || downloadStatus.value === 'error') {
      downloadStatus.value   = 'idle';
      downloadProgress.value = 0;
      downloadError.value    = null;
    }
  }

  return {
    // verificação
    status, currentVersion, latestVersion, minimumVersion,
    downloadUrl, releaseNotesUrl, checkedAt, source, message, loading,
    isBlocked, hasUpdate, isOffline, isUnavailable, isCurrent,
    statusLabel, statusTone, checkedAtFormatted,
    fetchUpdateStatus, forceCheckUpdate,
    // download automático
    downloadStatus, downloadProgress, downloadError, downloadDialogVisible,
    isDownloading, downloadDone, downloadFailed, downloadStatusLabel,
    startDownload, openDownloadDialog, closeDownloadDialog,
    applyUpdate,
  };
});
