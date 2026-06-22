<script setup>
import { computed } from 'vue';
import Dialog from 'primevue/dialog';
import Button from 'primevue/button';
import { useSystemUpdateStore } from '@/stores/systemUpdate';

const updateStore = useSystemUpdateStore();

function onDialogHide() {
  if (!updateStore.isDownloading && !updateStore.downloadDone) {
    updateStore.closeDownloadDialog();
  }
}

const barWidth = computed(() => `${updateStore.downloadProgress}%`);

const barClass = computed(() => {
  if (updateStore.downloadFailed)  return 'update-progress-bar__fill--error';
  if (updateStore.downloadDone)    return 'update-progress-bar__fill--done';
  if (updateStore.downloadStatus === 'applying') return 'update-progress-bar__fill--applying';
  return 'update-progress-bar__fill--active';
});

const headerIcon = computed(() => {
  if (updateStore.downloadFailed) return 'pi pi-times-circle';
  if (updateStore.downloadDone)   return 'pi pi-check-circle';
  return 'pi pi-cloud-download';
});

const headerIconClass = computed(() => {
  if (updateStore.downloadFailed) return 'update-dialog__icon--error';
  if (updateStore.downloadDone)   return 'update-dialog__icon--done';
  return 'update-dialog__icon--active';
});
</script>

<template>
  <Dialog
    v-model:visible="updateStore.downloadDialogVisible"
    :closable="!updateStore.isDownloading"
    :closeOnEscape="!updateStore.isDownloading"
    :modal="true"
    :draggable="false"
    class="update-dialog"
    @hide="onDialogHide"
  >
    <template #header>
      <div class="update-dialog__header">
        <span class="update-dialog__icon" :class="headerIconClass">
          <i :class="headerIcon" />
        </span>
        <div class="update-dialog__title-group">
          <span class="update-dialog__eyebrow">Atualização automática</span>
          <strong class="update-dialog__title">
            Sentinela v{{ updateStore.latestVersion ?? '...' }}
          </strong>
        </div>
      </div>
    </template>

    <div class="update-dialog__body">
      <!-- Barra de progresso -->
      <div class="update-progress-bar" role="progressbar"
           :aria-valuenow="updateStore.downloadProgress"
           aria-valuemin="0" aria-valuemax="100">
        <div class="update-progress-bar__track">
          <div
            class="update-progress-bar__fill"
            :class="barClass"
            :style="{ width: barWidth }"
          />
        </div>
        <span class="update-progress-bar__pct">{{ updateStore.downloadProgress }}%</span>
      </div>

      <!-- Status / countdown / erro numa única linha de status -->
      <div class="update-dialog__status-row">
        <template v-if="updateStore.downloadFailed">
          <i class="pi pi-exclamation-triangle update-dialog__status-icon update-dialog__status-icon--error" />
          <span class="update-dialog__status-text update-dialog__status-text--error">{{ updateStore.downloadError }}</span>
        </template>
        <template v-else-if="updateStore.downloadDone">
          <span class="update-dialog__countdown-badge">{{ updateStore.countdown }}s</span>
          <span class="update-dialog__status-text">O aplicativo fechará e reabrirá automaticamente.</span>
        </template>
        <template v-else>
          <i v-if="updateStore.isDownloading" class="pi pi-spin pi-spinner update-dialog__status-icon" />
          <span class="update-dialog__status-text">{{ updateStore.downloadStatusLabel }}</span>
        </template>
      </div>
    </div>

    <template #footer>
      <div class="update-dialog__footer">
        <Button
          v-if="updateStore.downloadDone"
          label="Cancelar atualização"
          icon="pi pi-times"
          severity="secondary"
          @click="updateStore.cancelUpdate"
        />
        <Button
          v-if="updateStore.downloadFailed"
          label="Fechar"
          icon="pi pi-times"
          severity="secondary"
          @click="updateStore.closeDownloadDialog"
        />
        <Button
          v-if="updateStore.downloadFailed"
          label="Tentar novamente"
          icon="pi pi-refresh"
          severity="warning"
          @click="updateStore.startDownload"
        />
      </div>
    </template>
  </Dialog>
</template>

<style scoped>
/* ─── Dialog container ─────────────────────────────────────────────────────── */
:deep(.p-dialog.update-dialog) {
  width: min(520px, 92vw);
  border-radius: 16px;
  overflow: hidden;
  background: var(--surface-card);
  border: 1px solid var(--surface-border);
  box-shadow: 0 24px 80px rgba(0, 0, 0, 0.45);
}

:deep(.p-dialog.update-dialog .p-dialog-header) {
  background: transparent;
  padding: 1.5rem 1.5rem 0;
  border-bottom: none;
}

:deep(.p-dialog.update-dialog .p-dialog-content) {
  background: transparent;
  padding: 1rem 1.5rem;
}

:deep(.p-dialog.update-dialog .p-dialog-footer) {
  background: transparent;
  padding: 0 1.5rem 1.5rem;
  border-top: none;
}

/* ─── Header ───────────────────────────────────────────────────────────────── */
.update-dialog__header {
  display: flex;
  align-items: center;
  gap: 1rem;
}

.update-dialog__icon {
  width: 48px;
  height: 48px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 1.4rem;
  flex-shrink: 0;
  transition: background 0.3s;
}

.update-dialog__icon--active {
  background: rgba(99, 179, 237, 0.15);
  color: #63b3ed;
}

.update-dialog__icon--done {
  background: rgba(72, 187, 120, 0.15);
  color: #48bb78;
}

.update-dialog__icon--error {
  background: rgba(245, 101, 101, 0.15);
  color: #f56565;
}

.update-dialog__eyebrow {
  font-size: 0.7rem;
  font-weight: 600;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: var(--text-color-secondary);
}

.update-dialog__title {
  display: block;
  font-size: 1.1rem;
  color: var(--text-color);
}

/* ─── Body ─────────────────────────────────────────────────────────────────── */
.update-dialog__body {
  display: flex;
  flex-direction: column;
  gap: 1rem;
  padding: 0.5rem 0;
}

/* ─── Progress bar ─────────────────────────────────────────────────────────── */
.update-progress-bar {
  display: flex;
  align-items: center;
  gap: 0.75rem;
}

.update-progress-bar__track {
  flex: 1;
  height: 8px;
  border-radius: 999px;
  background: var(--surface-border);
  overflow: hidden;
}

.update-progress-bar__fill {
  height: 100%;
  border-radius: 999px;
  transition: width 0.4s ease, background 0.3s;
}

.update-progress-bar__fill--active {
  background: linear-gradient(90deg, #63b3ed, #4299e1);
  animation: shimmer 1.6s infinite linear;
  background-size: 200% 100%;
}

.update-progress-bar__fill--applying {
  background: linear-gradient(90deg, #f6ad55, #ed8936);
  animation: shimmer 1.2s infinite linear;
  background-size: 200% 100%;
}

.update-progress-bar__fill--done {
  background: linear-gradient(90deg, #48bb78, #38a169);
}

.update-progress-bar__fill--error {
  background: #f56565;
}

.update-progress-bar__pct {
  font-size: 0.8rem;
  font-weight: 600;
  color: var(--text-color-secondary);
  min-width: 2.8rem;
  text-align: right;
}

/* ─── Status row (status / countdown / erro) ───────────────────────────────── */
.update-dialog__status-row {
  display: flex;
  align-items: center;
  gap: 0.6rem;
  min-height: 1.6rem;
}

.update-dialog__status-icon {
  font-size: 0.9rem;
  color: #63b3ed;
  flex-shrink: 0;
}

.update-dialog__status-icon--error {
  color: #f56565;
}

.update-dialog__status-text {
  font-size: 0.875rem;
  color: var(--text-color-secondary);
  line-height: 1.3;
}

.update-dialog__status-text--error {
  color: #fc8181;
}

.update-dialog__countdown-badge {
  font-size: 0.8rem;
  font-weight: 600;
  color: #48bb78;
  background: rgba(72, 187, 120, 0.12);
  border: 1px solid rgba(72, 187, 120, 0.3);
  border-radius: 6px;
  padding: 0.1rem 0.45rem;
  flex-shrink: 0;
  min-width: 2.4rem;
  text-align: center;
}

/* ─── Footer ───────────────────────────────────────────────────────────────── */
.update-dialog__footer {
  display: flex;
  justify-content: flex-end;
  align-items: center;
  gap: 0.5rem;
  min-height: 2.5rem;
}

/* ─── Shimmer animation ────────────────────────────────────────────────────── */
@keyframes shimmer {
  0%   { background-position: 200% center; }
  100% { background-position: -200% center; }
}
</style>
