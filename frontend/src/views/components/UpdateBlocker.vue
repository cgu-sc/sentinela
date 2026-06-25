<script setup>
import { computed } from 'vue';
import { useSystemUpdateStore } from '@/stores/systemUpdate';

const updateStore = useSystemUpdateStore();

const mode = computed(() =>
  updateStore.isExecutionBlocked ? 'execution_blocked' : 'update_required'
);

const title = computed(() => {
  if (mode.value === 'execution_blocked') {
    return updateStore.blockTitle || 'Execução bloqueada';
  }
  return 'Atualização obrigatória';
});

const message = computed(() => {
  if (mode.value === 'execution_blocked') {
    return (
      updateStore.blockMessage ||
      'Esta versão do Sentinela foi temporariamente bloqueada pela política de atualização. Atualize para a versão mais recente para continuar utilizando o sistema.'
    );
  }
  return 'Esta versão do Sentinela não é mais suportada e precisa ser atualizada para continuar.';
});

const blockedSinceFormatted = computed(() => {
  if (!updateStore.blockedSince) return null;
  try {
    return new Intl.DateTimeFormat('pt-BR', {
      day: '2-digit', month: '2-digit', year: 'numeric',
      hour: '2-digit', minute: '2-digit',
    }).format(new Date(updateStore.blockedSince));
  } catch {
    return null;
  }
});

const showDownload = computed(() => Boolean(updateStore.downloadUrl));
const showChangelog = computed(() => Boolean(updateStore.releaseNotesUrl));
const isDesktop = computed(() => Boolean(window.pywebview?.api));

const openDownload = () => {
  if (updateStore.downloadUrl) window.open(updateStore.downloadUrl, '_blank');
};
const openChangelog = () => {
  if (updateStore.releaseNotesUrl) window.open(updateStore.releaseNotesUrl, '_blank');
};
const recheck = () => {
  updateStore.forceCheckUpdate();
};
const exitApp = () => {
  if (window.pywebview?.api?.exit_app) {
    window.pywebview.api.exit_app();
  } else {
    window.close();
  }
};
</script>

<template>
  <div class="update-blocker" :class="`update-blocker--${mode}`">
    <div class="update-blocker__card">
      <div
        class="update-blocker__icon-wrap"
        :class="`update-blocker__icon-wrap--${mode}`"
      >
        <svg
          v-if="mode === 'execution_blocked'"
          class="update-blocker__icon"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="1.5"
          stroke-linecap="round"
          stroke-linejoin="round"
        >
          <path d="M12 2 4 5v6c0 5 3.5 9.5 8 11 4.5-1.5 8-6 8-11V5l-8-3Z" />
          <line x1="9" y1="12" x2="15" y2="12" />
          <line x1="12" y1="9" x2="12" y2="15" />
        </svg>
        <svg
          v-else
          class="update-blocker__icon"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="1.5"
          stroke-linecap="round"
          stroke-linejoin="round"
        >
          <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
          <polyline points="17 8 12 3 7 8" />
          <line x1="12" y1="3" x2="12" y2="15" />
        </svg>
      </div>

      <h1 class="update-blocker__title">{{ title }}</h1>
      <p class="update-blocker__subtitle">{{ message }}</p>

      <div v-if="blockedSinceFormatted" class="update-blocker__since">
        <span class="update-blocker__since-label">Bloqueado desde</span>
        <span class="update-blocker__since-value">{{ blockedSinceFormatted }}</span>
      </div>

      <div class="update-blocker__versions">
        <div class="update-version-row">
          <span class="update-version-row__label">Sua versão</span>
          <span class="update-version-row__value update-version-row__value--old">
            {{ updateStore.currentVersion ?? '—' }}
          </span>
        </div>
        <div class="update-version-row">
          <span class="update-version-row__label">Versão mínima</span>
          <span class="update-version-row__value update-version-row__value--min">
            {{ updateStore.minimumVersion ?? '—' }}
          </span>
        </div>
        <div class="update-version-row">
          <span class="update-version-row__label">Versão mais recente</span>
          <span class="update-version-row__value update-version-row__value--latest">
            {{ updateStore.latestVersion ?? '—' }}
          </span>
        </div>
      </div>

      <div class="update-blocker__actions">
        <button
          v-if="showDownload"
          class="update-action update-action--primary"
          @click="openDownload"
        >
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
            stroke-linecap="round" stroke-linejoin="round" width="16" height="16">
            <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
            <polyline points="7 10 12 15 17 10" />
            <line x1="12" y1="15" x2="12" y2="3" />
          </svg>
          Baixar atualização
        </button>
        <button
          v-if="mode === 'execution_blocked'"
          class="update-action update-action--primary"
          :class="{ 'update-action--only': !showDownload }"
          @click="recheck"
        >
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
            stroke-linecap="round" stroke-linejoin="round" width="16" height="16">
            <polyline points="23 4 23 10 17 10" />
            <polyline points="1 20 1 14 7 14" />
            <path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15" />
          </svg>
          Verificar novamente
        </button>
        <button
          v-if="showChangelog"
          class="update-action update-action--secondary"
          @click="openChangelog"
        >
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
            stroke-linecap="round" stroke-linejoin="round" width="16" height="16">
            <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
            <polyline points="14 2 14 8 20 8" />
            <line x1="16" y1="13" x2="8" y2="13" />
            <line x1="16" y1="17" x2="8" y2="17" />
          </svg>
          Ver alterações
        </button>
        <button
          v-if="isDesktop"
          class="update-action update-action--ghost"
          @click="exitApp"
        >
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
            stroke-linecap="round" stroke-linejoin="round" width="16" height="16">
            <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4" />
            <polyline points="16 17 21 12 16 7" />
            <line x1="21" y1="12" x2="9" y2="12" />
          </svg>
          Sair
        </button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.update-blocker {
  position: fixed;
  inset: 0;
  z-index: 99999;
  display: flex;
  align-items: center;
  justify-content: center;
  background:
    radial-gradient(circle at 50% 42%, rgba(22, 27, 34, 0.97) 0%, rgba(13, 17, 23, 0.99) 58%, #0d1117 100%);
  color: #f8fafc;
  font-family: inherit;
}

.update-blocker__card {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 1.25rem;
  max-width: 480px;
  width: 100%;
  padding: 2.5rem 2rem;
  background: rgba(255, 255, 255, 0.03);
  border: 1px solid rgba(255, 255, 255, 0.08);
  border-radius: 16px;
  backdrop-filter: blur(12px);
  box-shadow: 0 24px 64px rgba(0, 0, 0, 0.5);
  text-align: center;
}

.update-blocker__icon-wrap {
  width: 64px;
  height: 64px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
}

.update-blocker__icon-wrap--update_required {
  background: rgba(239, 68, 68, 0.1);
  border: 1px solid rgba(239, 68, 68, 0.25);
}

.update-blocker__icon-wrap--execution_blocked {
  background: rgba(220, 38, 38, 0.14);
  border: 1px solid rgba(220, 38, 38, 0.4);
}

.update-blocker__icon {
  width: 32px;
  height: 32px;
}

.update-blocker__icon-wrap--update_required .update-blocker__icon {
  stroke: #ef4444;
  filter: drop-shadow(0 0 8px rgba(239, 68, 68, 0.4));
}

.update-blocker__icon-wrap--execution_blocked .update-blocker__icon {
  stroke: #f87171;
  filter: drop-shadow(0 0 10px rgba(220, 38, 38, 0.55));
}

.update-blocker__title {
  margin: 0;
  font-size: 1.35rem;
  font-weight: 600;
  color: #f8fafc;
  letter-spacing: 0.3px;
}

.update-blocker__subtitle {
  margin: 0;
  font-size: 0.9rem;
  color: #94a3b8;
  line-height: 1.55;
  max-width: 380px;
}

.update-blocker__since {
  display: inline-flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.4rem 0.8rem;
  border-radius: 999px;
  background: rgba(220, 38, 38, 0.08);
  border: 1px solid rgba(220, 38, 38, 0.25);
  font-size: 0.78rem;
}

.update-blocker__since-label {
  color: #94a3b8;
  letter-spacing: 0.3px;
  text-transform: uppercase;
  font-size: 0.7rem;
  font-weight: 600;
}

.update-blocker__since-value {
  color: #fecaca;
  font-weight: 600;
  letter-spacing: 0.3px;
}

.update-blocker__versions {
  width: 100%;
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
  background: rgba(255, 255, 255, 0.03);
  border: 1px solid rgba(255, 255, 255, 0.07);
  border-radius: 10px;
  padding: 1rem 1.25rem;
}

.update-version-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 1rem;
}

.update-version-row__label {
  font-size: 0.85rem;
  color: #64748b;
}

.update-version-row__value {
  font-size: 0.9rem;
  font-weight: 600;
  letter-spacing: 0.5px;
}

.update-version-row__value--old    { color: #ef4444; }
.update-version-row__value--min    { color: #f59e0b; }
.update-version-row__value--latest { color: #22c55e; }

.update-blocker__actions {
  display: flex;
  flex-direction: column;
  gap: 0.6rem;
  width: 100%;
}

.update-action {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 0.5rem;
  width: 100%;
  padding: 0.7rem 1.25rem;
  border-radius: 9px;
  font-size: 0.9rem;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.2s ease;
  font-family: inherit;
  letter-spacing: 0.02em;
}

.update-action--primary {
  background: var(--primary-color, #d97706);
  color: #fff;
  border: none;
  box-shadow: 0 4px 14px color-mix(in srgb, var(--primary-color, #d97706) 35%, transparent);
}

.update-blocker--execution_blocked .update-action--primary {
  background: #dc2626;
  box-shadow: 0 4px 14px rgba(220, 38, 38, 0.4);
}

.update-action--primary:hover {
  filter: brightness(1.1);
  transform: translateY(-1px);
}

.update-action--only {
  background: #1f2937;
  border: 1px solid rgba(255, 255, 255, 0.12);
  box-shadow: none;
  color: #f1f5f9;
}

.update-action--only:hover {
  background: #27313f;
  filter: none;
}

.update-action--secondary {
  background: rgba(255, 255, 255, 0.05);
  color: #cbd5e1;
  border: 1px solid rgba(255, 255, 255, 0.1);
}

.update-action--secondary:hover {
  background: rgba(255, 255, 255, 0.09);
  color: #f1f5f9;
}

.update-action--ghost {
  background: transparent;
  color: #64748b;
  border: 1px solid rgba(255, 255, 255, 0.06);
}

.update-action--ghost:hover {
  color: #94a3b8;
  border-color: rgba(255, 255, 255, 0.12);
}
</style>
