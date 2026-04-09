import { defineStore } from 'pinia';
import { ref } from 'vue';

const STORAGE_KEY = 'sentinela_recent_cnpj';

function loadFromStorage() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? JSON.parse(raw) : null;
  } catch {
    return null;
  }
}

/**
 * Armazena o último CNPJ analisado para atalho rápido na navbar.
 * Responsabilidade única: persistir cnpj + razão social do último estabelecimento visitado.
 */
export const useRecentCnpjStore = defineStore('recentCnpj', () => {
  const recent = ref(loadFromStorage());

  function set(cnpj, razaoSocial) {
    recent.value = { cnpj, razaoSocial };
    localStorage.setItem(STORAGE_KEY, JSON.stringify(recent.value));
  }

  function clear() {
    recent.value = null;
    localStorage.removeItem(STORAGE_KEY);
  }

  return { recent, set, clear };
});
