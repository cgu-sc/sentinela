<script setup>
import { computed } from 'vue';
import { useSystemUpdateStore } from '@/stores/systemUpdate';

const updateStore = useSystemUpdateStore();

const title = computed(() => updateStore.blockTitle || 'Execução bloqueada');

const message = computed(
  () =>
    updateStore.blockMessage ||
    'Esta versão do Sentinela foi temporariamente bloqueada pela política de atualização. Atualize para a versão mais recente para continuar utilizando o sistema.'
);

const blockedSinceFormatted = computed(() => {
  if (!updateStore.blockedSince) return null;
  try {
    return new Intl.DateTimeFormat('pt-BR', {
      day: '2-digit',
      month: '2-digit',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    }).format(new Date(updateStore.blockedSince));
  } catch {
    return null;
  }
});

const recheck = () => {
  updateStore.forceCheckUpdate();
};
</script>

<template>
  <div class="execution-blocker" role="alertdialog" aria-modal="true" aria-labelledby="execution-blocker-title">
    <div class="execution-blocker__card">
      <div class="execution-blocker__icon-wrap">
        <svg
          class="execution-blocker__icon"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="1.5"
          stroke-linecap="round"
          stroke-linejoin="round"
          aria-hidden="true"
        >
          <path d="M12 2 4 5v6c0 5 3.5 9.5 8 11 4.5-1.5 8-6 8-11V5l-8-3Z" />
          <line x1="9" y1="12" x2="15" y2="12" />
          <line x1="12" y1="9" x2="12" y2="15" />
        </svg>
      </div>

      <h1 id="execution-blocker-title" class="execution-blocker__title">{{ title }}</h1>
      <p class="execution-blocker__message">{{ message }}</p>

      <div v-if="blockedSinceFormatted" class="execution-blocker__since">
        <span class="execution-blocker__since-label">Bloqueado desde</span>
        <span class="execution-blocker__since-value">{{ blockedSinceFormatted }}</span>
      </div>

      <div class="execution-blocker__version">
        <span class="execution-blocker__version-label">Versão instalada</span>
        <span class="execution-blocker__version-value">v{{ updateStore.currentVersion ?? '—' }}</span>
      </div>

      <div class="execution-blocker__actions">
        <button class="execution-action execution-action--primary" @click="recheck">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
            stroke-linecap="round" stroke-linejoin="round" width="16" height="16" aria-hidden="true">
            <polyline points="23 4 23 10 17 10" />
            <polyline points="1 20 1 14 7 14" />
            <path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15" />
          </svg>
          Verificar novamente
        </button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.execution-blocker {
  position: fixed;
  inset: 0;
  z-index: 99999;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 2rem;
  background:
    radial-gradient(circle at 50% 38%, rgba(28, 16, 16, 0.97) 0%, rgba(13, 8, 10, 0.99) 60%, #0a0608 100%);
  color: #f8fafc;
  font-family: inherit;
}

.execution-blocker__card {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 1.1rem;
  max-width: 520px;
  width: 100%;
  padding: 3rem 2.25rem 2.5rem;
  background: rgba(255, 255, 255, 0.02);
  border: 1px solid rgba(220, 38, 38, 0.22);
  border-radius: 18px;
  backdrop-filter: blur(14px);
  box-shadow:
    0 24px 64px rgba(0, 0, 0, 0.6),
    inset 0 1px 0 rgba(255, 255, 255, 0.04);
  text-align: center;
}

.execution-blocker__icon-wrap {
  width: 80px;
  height: 80px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(220, 38, 38, 0.12);
  border: 1px solid rgba(220, 38, 38, 0.4);
  margin-top: 0.25rem;
}

.execution-blocker__icon {
  width: 42px;
  height: 42px;
  stroke: #f87171;
  filter: drop-shadow(0 0 12px rgba(220, 38, 38, 0.55));
}

.execution-blocker__title {
  margin: 0;
  font-size: 1.6rem;
  font-weight: 600;
  color: #fef2f2;
  letter-spacing: 0.2px;
  line-height: 1.25;
}

.execution-blocker__message {
  margin: 0;
  font-size: 0.95rem;
  color: #cbd5e1;
  line-height: 1.6;
  max-width: 420px;
}

.execution-blocker__since {
  display: inline-flex;
  align-items: center;
  gap: 0.6rem;
  padding: 0.5rem 0.95rem;
  border-radius: 999px;
  background: rgba(220, 38, 38, 0.08);
  border: 1px solid rgba(220, 38, 38, 0.25);
  margin-top: 0.25rem;
}

.execution-blocker__since-label {
  color: #94a3b8;
  font-size: 0.7rem;
  font-weight: 600;
  letter-spacing: 1px;
  text-transform: uppercase;
}

.execution-blocker__since-value {
  color: #fecaca;
  font-size: 0.85rem;
  font-weight: 600;
  letter-spacing: 0.3px;
}

.execution-blocker__version {
  display: flex;
  align-items: center;
  gap: 0.6rem;
  padding: 0.5rem 1rem;
  border-radius: 8px;
  background: rgba(255, 255, 255, 0.03);
  border: 1px solid rgba(255, 255, 255, 0.07);
  margin-top: 0.25rem;
}

.execution-blocker__version-label {
  color: #94a3b8;
  font-size: 0.78rem;
  letter-spacing: 0.3px;
}

.execution-blocker__version-value {
  color: #f1f5f9;
  font-size: 0.85rem;
  font-weight: 600;
  letter-spacing: 0.3px;
}

.execution-blocker__actions {
  display: flex;
  flex-direction: column;
  gap: 0.55rem;
  width: 100%;
  margin-top: 0.5rem;
}

.execution-action {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 0.5rem;
  width: 100%;
  padding: 0.75rem 1.25rem;
  border-radius: 9px;
  font-size: 0.9rem;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.2s ease;
  font-family: inherit;
  letter-spacing: 0.02em;
}

.execution-action--primary {
  background: #dc2626;
  color: #fff;
  border: 1px solid rgba(255, 255, 255, 0.08);
  box-shadow: 0 4px 14px rgba(220, 38, 38, 0.4);
}

.execution-action--primary:hover {
  background: #b91c1c;
  transform: translateY(-1px);
  box-shadow: 0 6px 18px rgba(220, 38, 38, 0.55);
}
</style>
