<script setup>
import { useSyncManager } from '@/composables/useSyncManager';
import Button from 'primevue/button';
import Dialog from 'primevue/dialog';
import ProgressBar from 'primevue/progressbar';

const {
  isSyncing,
  showConfirmSync,
  syncProgress,
  syncStatus,
  syncError,
  syncErrorMessage,
  handleSync,
  retrySync,
  dismissError,
} = useSyncManager();
</script>

<template>
  <!-- Dialog de confirmação -->
  <Dialog
    v-model:visible="showConfirmSync"
    header="Sincronizar Dados"
    :style="{ width: '400px' }"
    modal
    :closable="!isSyncing"
  >
    <div class="flex flex-col items-center gap-4 text-center p-2">
      <i
        class="pi pi-exclamation-triangle text-amber-500"
        style="font-size: 3rem"
      ></i>
      <p class="mt-2">
        Deseja realmente iniciar a sincronização com os dados do
        <strong>CGUData</strong>?
      </p>
      <p class="text-sm text-gray-500">
        Este processo irá atualizar todos os caches do sistema com as
        informações mais recentes do banco de dados.
      </p>
    </div>
    <template #footer>
      <Button
        label="Cancelar"
        icon="pi pi-times"
        text
        severity="secondary"
        @click="showConfirmSync = false"
      />
      <Button
        label="Sincronizar Agora"
        icon="pi pi-sync"
        severity="primary"
        @click="handleSync"
      />
    </template>
  </Dialog>

  <!-- Modal de progresso/erro -->
  <Dialog
    v-model:visible="isSyncing"
    modal
    :closable="false"
    :draggable="false"
    :show-header="false"
    :style="{ width: '460px' }"
  >
    <div class="sync-modal-content">
      <!-- Estado: progresso -->
      <template v-if="!syncError">
        <div class="sync-icon-container">
          <i class="pi pi-sync pi-spin"></i>
        </div>
        <h3>Sincronizando com CGUData</h3>
        <p>
          O sistema está reconstruindo os arquivos de cache para garantir
          máxima performance. Por favor, aguarde.
        </p>
        <div class="progress-wrapper">
          <div
            style="
              display: flex;
              justify-content: space-between;
              margin-bottom: 0.5rem;
              font-size: 0.7rem;
              font-weight: 800;
              color: var(--primary-color);
              letter-spacing: 0.5px;
            "
          >
            <span>{{ syncStatus ? syncStatus.toUpperCase() : 'PROCESSANDO REGISTROS' }}</span>
            <span>{{ syncProgress }}%</span>
          </div>
          <ProgressBar :value="syncProgress" :show-value="false" style="height: 10px" />
        </div>
        <span class="status-minor">Não feche esta janela...</span>
      </template>

      <!-- Estado: erro -->
      <template v-else>
        <div class="sync-icon-container sync-error-icon">
          <i class="pi pi-times-circle"></i>
        </div>
        <h3 class="sync-error-title">Falha na Sincronização</h3>
        <p class="sync-error-msg">{{ syncErrorMessage }}</p>
        <div class="sync-error-actions">
          <Button label="Tentar Novamente" icon="pi pi-refresh" severity="primary" @click="retrySync" />
          <Button label="Fechar" icon="pi pi-times" severity="secondary" outlined @click="dismissError" />
        </div>
      </template>
    </div>
  </Dialog>
</template>

<style scoped>
.sync-modal-content {
  padding: 2rem 1.5rem;
  display: flex;
  flex-direction: column;
  align-items: center;
  text-align: center;
  gap: 1rem;
}

.sync-icon-container {
  width: 64px;
  height: 64px;
  background: color-mix(in srgb, var(--primary-color) 10%, transparent);
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  margin-bottom: 0.5rem;
}

.sync-icon-container i {
  font-size: 2rem;
  color: var(--primary-color);
}

.sync-modal-content h3 {
  font-size: 1.25rem;
  font-weight: 700;
  margin: 0;
  color: var(--text-color);
}

.sync-modal-content p {
  font-size: 0.9rem;
  color: var(--text-muted);
  margin: 0;
  line-height: 1.5;
}

.progress-wrapper {
  width: 100%;
  margin-top: 1rem;
}

.status-minor {
  font-size: 0.75rem;
  font-style: italic;
  color: var(--text-muted);
  opacity: 0.7;
}

.sync-error-icon {
  background: color-mix(in srgb, var(--color-error) 12%, transparent) !important;
  animation: shake 0.4s ease;
}

.sync-error-icon i {
  color: var(--color-error) !important;
}

.sync-error-title {
  color: var(--color-error) !important;
}

.sync-error-msg {
  font-size: 0.88rem;
  color: var(--text-muted);
  line-height: 1.55;
  max-width: 360px;
}

.sync-error-actions {
  display: flex;
  gap: 0.75rem;
  justify-content: center;
  flex-wrap: wrap;
  margin-top: 0.5rem;
}

@keyframes shake {
  0%, 100% { transform: translateX(0); }
  20%       { transform: translateX(-6px); }
  40%       { transform: translateX(6px); }
  60%       { transform: translateX(-4px); }
  80%       { transform: translateX(4px); }
}
</style>
