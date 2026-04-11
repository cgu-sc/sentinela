<script setup>
import { ref, computed, onMounted } from 'vue';
import axios from 'axios';
import { API_ENDPOINTS } from '@/config/api';
import { useSyncManager } from '@/composables/useSyncManager';

const { showConfirmSync, isSyncing } = useSyncManager();

const status = ref(null);   // null = ainda carregando
const fetchError = ref(false);

const isReady = computed(() => status.value?.is_ready === true);
const hasCacheError = computed(() => status.value?.status === 'error');
const missingModules = computed(() => {
  if (!status.value?.modules) return [];
  return Object.values(status.value.modules).filter((m) => !m.loaded);
});

onMounted(async () => {
  try {
    const res = await axios.get(API_ENDPOINTS.cacheStatus);
    status.value = res.data;
  } catch {
    fetchError.value = true;
  }
});
</script>

<template>
  <!-- Não exibe nada enquanto carrega ou se tudo estiver ok -->
  <Transition name="banner-fade">
    <div
      v-if="status !== null && !isReady && !isSyncing"
      class="integrity-banner"
      :class="{ 'is-error': hasCacheError }"
    >
      <div class="banner-icon">
        <i :class="hasCacheError ? 'pi pi-exclamation-circle' : 'pi pi-database'" />
      </div>

      <div class="banner-body">
        <p class="banner-title">
          {{ hasCacheError ? 'Falha ao carregar dados' : 'Dados desatualizados' }}
        </p>

        <p v-if="hasCacheError && status.error_message" class="banner-detail error-detail">
          {{ status.error_message }}
        </p>

        <ul v-else-if="missingModules.length" class="banner-modules">
          <li v-for="m in missingModules" :key="m.label">
            <i class="pi pi-times-circle" /> {{ m.label }}
          </li>
        </ul>

        <p class="banner-hint">
          Sincronize para carregar os dados necessários.
        </p>
      </div>

      <button class="banner-sync-btn" @click="showConfirmSync = true">
        <i class="pi pi-refresh" />
        Sincronizar
      </button>
    </div>
  </Transition>
</template>

<style scoped>
.integrity-banner {
  margin: 0.75rem 0.75rem 0;
  padding: 0.75rem;
  border-radius: 8px;
  background: color-mix(in srgb, var(--primary-color) 10%, var(--sidebar-bg));
  border: 1px solid color-mix(in srgb, var(--primary-color) 35%, transparent);
  display: flex;
  gap: 0.6rem;
  align-items: flex-start;
}

.integrity-banner.is-error {
  background: color-mix(in srgb, var(--color-error) 10%, var(--sidebar-bg));
  border-color: color-mix(in srgb, var(--color-error) 35%, transparent);
}

.banner-icon {
  font-size: 1rem;
  color: var(--primary-color);
  flex-shrink: 0;
  margin-top: 1px;
}

.integrity-banner.is-error .banner-icon {
  color: var(--color-error);
}

.banner-body {
  flex: 1;
  min-width: 0;
}

.banner-title {
  margin: 0 0 0.3rem;
  font-size: 0.72rem;
  font-weight: 600;
  color: var(--sidebar-text);
  text-transform: uppercase;
  letter-spacing: 0.03em;
}

.banner-detail {
  margin: 0 0 0.3rem;
  font-size: 0.7rem;
  color: var(--text-muted);
  line-height: 1.4;
}

.error-detail {
  color: var(--color-error);
  opacity: 0.85;
}

.banner-modules {
  margin: 0 0 0.3rem;
  padding: 0;
  list-style: none;
  display: flex;
  flex-direction: column;
  gap: 0.15rem;
}

.banner-modules li {
  display: flex;
  align-items: center;
  gap: 0.3rem;
  font-size: 0.68rem;
  color: var(--text-muted);
}

.banner-modules .pi {
  font-size: 0.6rem;
  color: var(--color-warning, #f59e0b);
  flex-shrink: 0;
}

.banner-hint {
  margin: 0;
  font-size: 0.68rem;
  color: var(--text-muted);
  opacity: 0.75;
}

.banner-sync-btn {
  flex-shrink: 0;
  display: inline-flex;
  align-items: center;
  gap: 0.35rem;
  padding: 0.3rem 0.6rem;
  border-radius: 6px;
  border: 1px solid color-mix(in srgb, var(--primary-color) 50%, transparent);
  background: color-mix(in srgb, var(--primary-color) 15%, transparent);
  color: var(--primary-color);
  font-size: 0.68rem;
  font-weight: 600;
  cursor: pointer;
  transition: background 0.15s, border-color 0.15s;
  white-space: nowrap;
  align-self: center;
}

.banner-sync-btn:hover {
  background: color-mix(in srgb, var(--primary-color) 25%, transparent);
  border-color: color-mix(in srgb, var(--primary-color) 70%, transparent);
}

.banner-sync-btn .pi {
  font-size: 0.7rem;
}

/* Entrada suave */
.banner-fade-enter-active { transition: opacity 0.3s ease, transform 0.3s ease; }
.banner-fade-enter-from   { opacity: 0; transform: translateY(-6px); }
</style>
