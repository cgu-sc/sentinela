import { defineStore } from 'pinia';
import { ref, computed } from 'vue';

const STORAGE_KEY = 'sentinela_farmacia_lists';

function loadFromStorage() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw) return JSON.parse(raw);
  } catch {}
  return { blacklist: [], interesse: [] };
}

function saveToStorage(blacklist, interesse) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify({
      blacklist: blacklist.value,
      interesse: interesse.value,
    }));
  } catch {}
}

export const useFarmaciaListsStore = defineStore('farmaciaLists', () => {
  const stored = loadFromStorage();
  const blacklist = ref(stored.blacklist);
  const interesse = ref(stored.interesse);

  const isBlacklisted = computed(() => (cnpj) =>
    blacklist.value.some((e) => e.cnpj === cnpj),
  );

  const isInteresse = computed(() => (cnpj) =>
    interesse.value.some((e) => e.cnpj === cnpj),
  );

  function toggleBlacklist(cnpj, razaoSocial) {
    if (isBlacklisted.value(cnpj)) {
      blacklist.value = blacklist.value.filter((e) => e.cnpj !== cnpj);
    } else {
      interesse.value = interesse.value.filter((e) => e.cnpj !== cnpj);
      blacklist.value.push({ cnpj, razaoSocial, adicionadoEm: new Date().toISOString() });
    }
    saveToStorage(blacklist, interesse);
  }

  function toggleInteresse(cnpj, razaoSocial) {
    if (isInteresse.value(cnpj)) {
      interesse.value = interesse.value.filter((e) => e.cnpj !== cnpj);
    } else {
      blacklist.value = blacklist.value.filter((e) => e.cnpj !== cnpj);
      interesse.value.push({ cnpj, razaoSocial, adicionadoEm: new Date().toISOString() });
    }
    saveToStorage(blacklist, interesse);
  }

  return {
    blacklist,
    interesse,
    isBlacklisted,
    isInteresse,
    toggleBlacklist,
    toggleInteresse,
  };
});
