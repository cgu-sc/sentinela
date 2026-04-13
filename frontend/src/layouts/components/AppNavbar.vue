<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { SYSTEM_MODULES as modules } from '@/config/constants';
import { useRecentCnpjStore } from '@/stores/recentCnpj';
import { useFarmaciaListsStore } from '@/stores/farmaciaLists';
import { useSyncManager } from '@/composables/useSyncManager';
import ThemeSelector from '@/components/ThemeSelector.vue';
import Button from 'primevue/button';
import SelectButton from 'primevue/selectbutton';
import InputText from 'primevue/inputtext';

const props = defineProps({
  modelValue: { type: String, required: true },
});
const emit = defineEmits(['update:modelValue']);

const activeModule = computed({
  get: () => props.modelValue,
  set: (val) => emit('update:modelValue', val),
});

const route = useRoute();
const router = useRouter();
const recentCnpjStore = useRecentCnpjStore();
const recentCnpj = computed(() => recentCnpjStore.recent);
const farmaciaLists = useFarmaciaListsStore();
const totalListas = computed(() => farmaciaLists.interesse.length);
const { showConfirmSync } = useSyncManager();

// Abas dinâmicas baseadas no módulo selecionado
const tabs = computed(() => {
  if (activeModule.value === 'consolidado') {
    return [
      { label: 'Nacional',             path: '/' },
      { label: 'Municípios',           path: '/municipios' },
      { label: 'Estabelecimentos',     path: '/estabelecimentos' },
      { label: 'Indicadores',          path: '/indicadores' },
      { label: 'Dispersão Benefício',  path: '/dispersao-beneficio' },
    ];
  } else {
    return [
      { label: 'Mapa-Cluster',      path: '/alvos/cluster' },
      { label: 'Situação CNPJ',     path: '/alvos/situacao' },
      { label: 'Variação Produção', path: '/alvos/variacao' },
      { label: 'Rede de Sócios',    path: '/alvos/rede' },
    ];
  }
});

// Sincroniza activeModule com a rota ao carregar
onMounted(() => {
  if (route.path.startsWith('/alvos')) {
    activeModule.value = 'alvos';
  }
});

// Muda a rota padrão ao trocar de módulo
watch(activeModule, (newVal) => {
  if (
    newVal === 'consolidado' &&
    !route.path.match(/^\/(?:dispersao-beneficio|dispersao|municipios|empresa|estabelecimentos|$)/)
  ) {
    router.push('/');
  } else if (newVal === 'alvos' && !route.path.startsWith('/alvos')) {
    router.push('/alvos/cluster');
  }
});

// Busca rápida por CNPJ completo
const navCnpjInput = ref('');
watch(navCnpjInput, (val) => {
  const digits = val.replace(/\D/g, '');
  if (digits.length === 14) {
    navCnpjInput.value = '';
    router.push(`/estabelecimentos/${digits}`);
  }
});
</script>

<template>
  <nav class="top-navbar">
    <div class="nav-left">
      <SelectButton
        v-model="activeModule"
        :options="modules"
        optionLabel="name"
        optionValue="value"
        class="module-select-button"
      >
        <template #option="slotProps">
          <i :class="slotProps.option.icon" style="margin-right: 0.5rem; font-size: 0.9rem"></i>
          <span style="font-size: 0.75rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.3px;">
            {{ slotProps.option.name }}
          </span>
        </template>
      </SelectButton>

      <div class="nav-divider"></div>

      <div class="nav-tabs">
        <router-link
          v-for="tab in tabs"
          :key="tab.path"
          :to="tab.path"
          class="nav-tab"
          :class="{ active: route.path === tab.path }"
        >
          {{ tab.label }}
        </router-link>

        <!-- Atalho: último CNPJ analisado -->
        <div v-if="recentCnpj" class="nav-recent-wrapper">
          <router-link
            :to="`/estabelecimentos/${recentCnpj.cnpj}`"
            class="nav-tab nav-recent-cnpj"
            :class="{ active: route.path.startsWith('/estabelecimentos/') }"
            v-tooltip.bottom="recentCnpj.razaoSocial"
          >
            <i class="pi pi-history" />
            {{ recentCnpj.cnpj.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/, '$1.$2.$3/$4-$5') }}
          </router-link>
          <button class="nav-recent-clear" @click.prevent="recentCnpjStore.clear()" v-tooltip.bottom="'Limpar atalho'">
            <i class="pi pi-times" />
          </button>
        </div>
      </div>
    </div>

    <div class="nav-actions">
      <div class="nav-cnpj-search">
        <i class="pi pi-search nav-cnpj-icon" />
        <InputText
          v-model="navCnpjInput"
          placeholder="CNPJ (14 dígitos)"
          class="nav-cnpj-input"
          maxlength="18"
        />
      </div>
      <ThemeSelector />
      <div
        class="lists-nav-btn"
        @click="router.push('/listas')"
        v-tooltip.bottom="'Farmácias Monitoradas'"
      >
        <i class="pi pi-bookmark" />
        <span v-if="totalListas > 0" class="lists-nav-badge">{{ totalListas }}</span>
      </div>
      <Button
        icon="pi pi-refresh"
        text
        rounded
        severity="secondary"
        v-tooltip.bottom="'Sincronizar com CGUData'"
        @click="showConfirmSync = true"
      />
    </div>
  </nav>
</template>

<style scoped>
.top-navbar {
  height: 56px;
  min-height: 56px;
  max-height: 56px;
  flex-shrink: 0;
  background: color-mix(in srgb, var(--navbar-bg) 75%, transparent);
  backdrop-filter: blur(20px) saturate(160%);
  -webkit-backdrop-filter: blur(20px) saturate(160%);
  border-bottom: 1px solid color-mix(in srgb, var(--navbar-border) 60%, transparent);
  box-shadow: 0 1px 0 color-mix(in srgb, var(--primary-color) 6%, transparent),
              inset 0 -1px 0 color-mix(in srgb, var(--navbar-border) 40%, transparent);
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 0 1.5rem;
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  z-index: 300;
  transition: background 0.3s ease, border-color 0.3s ease;
}

.nav-actions {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  flex-shrink: 0;
}

.nav-left {
  display: flex;
  align-items: center;
  gap: 1rem;
}

.nav-divider {
  width: 1px;
  height: 20px;
  background: color-mix(in srgb, var(--text-muted) 30%, transparent);
  flex-shrink: 0;
}

:deep(.module-select-button) {
  border-radius: 8px;
  overflow: hidden;
}

:deep(.module-select-button .p-button) {
  background: color-mix(in srgb, var(--text-muted) 8%, transparent);
  border-color: color-mix(in srgb, var(--text-muted) 20%, transparent);
  color: var(--text-secondary);
  padding: 0.35rem 0.7rem;
  font-size: 0.72rem;
  transition: all 0.2s;
}

:deep(.module-select-button .p-button:not(.p-highlight):hover) {
  background: color-mix(in srgb, var(--primary-color) 8%, transparent) !important;
  border-color: color-mix(in srgb, var(--primary-color) 30%, transparent) !important;
  color: var(--primary-color) !important;
}

:deep(.module-select-button .p-button.p-highlight) {
  background: color-mix(in srgb, var(--primary-color) 12%, transparent) !important;
  border-color: color-mix(in srgb, var(--primary-color) 40%, transparent) !important;
  color: var(--primary-color) !important;
  box-shadow: inset 0 1px 0 color-mix(in srgb, var(--primary-color) 20%, transparent);
  font-weight: 700;
}

.nav-tabs {
  display: flex;
  align-items: stretch;
  gap: 0;
}

.nav-tab {
  position: relative;
  padding: 0 0.85rem;
  height: 56px;
  display: flex;
  align-items: center;
  text-decoration: none;
  color: var(--text-muted);
  font-size: 0.72rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  border: none;
  background: transparent;
  transition: color 0.2s ease;
  white-space: nowrap;
}

.nav-tab::after {
  content: '';
  position: absolute;
  bottom: 0;
  left: 0.5rem;
  right: 0.5rem;
  height: 2px;
  border-radius: 2px 2px 0 0;
  background: var(--primary-color);
  transform: scaleX(0);
  transition: transform 0.2s ease;
}

.nav-tab:hover {
  color: var(--text-color);
}

.nav-tab:hover::after {
  transform: scaleX(0.5);
  opacity: 0.4;
}

.nav-tab.active {
  color: var(--primary-color);
}

.nav-tab.active::after {
  transform: scaleX(1);
}

.nav-recent-wrapper {
  position: relative;
  display: flex;
  align-items: center;
}

.nav-recent-cnpj {
  gap: 0.4rem;
  padding-right: 1.4rem;
}

.nav-recent-cnpj::before {
  content: '';
  position: absolute;
  left: 0;
  width: 1px;
  height: 16px;
  background: color-mix(in srgb, var(--text-muted) 25%, transparent);
}

.nav-recent-cnpj .pi-history {
  font-size: 0.65rem;
  opacity: 0.6;
}

.nav-recent-clear {
  position: absolute;
  right: 0.3rem;
  top: 50%;
  transform: translateY(-50%);
  background: none;
  border: none;
  cursor: pointer;
  padding: 0.2rem;
  color: var(--text-muted);
  opacity: 0.4;
  display: flex;
  align-items: center;
  transition: opacity 0.15s;
}

.nav-recent-clear:hover {
  opacity: 1;
}

.nav-recent-clear .pi {
  font-size: 0.55rem;
}

.nav-cnpj-search {
  position: relative;
  display: flex;
  align-items: center;
}

.nav-cnpj-icon {
  position: absolute;
  left: 0.6rem;
  font-size: 0.7rem;
  color: var(--text-muted);
  pointer-events: none;
  z-index: 1;
}

.nav-cnpj-input {
  padding: 0.3rem 0.7rem 0.3rem 1.8rem !important;
  height: 30px !important;
  font-size: 0.72rem !important;
  font-family: 'Inter', sans-serif !important;
  font-weight: 600 !important;
  width: 170px !important;
  background: color-mix(in srgb, var(--card-bg) 80%, transparent) !important;
  border: 1px solid var(--card-border) !important;
  border-radius: 6px !important;
  color: var(--text-color) !important;
  letter-spacing: 0.03em;
  transition: border-color 0.2s, box-shadow 0.2s;
}

.nav-cnpj-input:focus {
  border-color: color-mix(in srgb, var(--primary-color) 60%, transparent) !important;
  box-shadow: 0 0 0 3px color-mix(in srgb, var(--primary-color) 12%, transparent) !important;
  outline: none !important;
}

.nav-cnpj-input::placeholder {
  color: var(--text-muted) !important;
  opacity: 0.6;
}

.lists-nav-btn {
  position: relative;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 36px;
  height: 36px;
  border-radius: 6px;
  cursor: pointer;
  color: var(--text-secondary);
  transition: all 0.15s ease;
}

.lists-nav-btn:hover {
  background: color-mix(in srgb, var(--text-color) 8%, transparent);
  color: var(--text-color);
}

.lists-nav-btn i {
  font-size: 1rem;
}

.lists-nav-badge {
  position: absolute;
  top: 2px;
  right: 2px;
  min-width: 16px;
  height: 16px;
  padding: 0 4px;
  font-size: 0.68rem;
  font-weight: 700;
  border-radius: 10px;
  background: var(--primary-color);
  color: #fff;
  display: flex;
  align-items: center;
  justify-content: center;
  line-height: 1;
}
</style>
