import { defineStore } from 'pinia';
import { ref, computed } from 'vue';

const STORAGE_KEY = 'sentinela_farmacia_lists';

function loadFromStorage() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw) return JSON.parse(raw);
  } catch {}
  return { interesse: [] };
}

function saveToStorage(interesse) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify({
      interesse: interesse.value,
    }));
  } catch {}
}

export const useFarmaciaListsStore = defineStore('farmaciaLists', () => {
  const stored = loadFromStorage();
  const interesse = ref(stored.interesse || []);

  const isInteresse = computed(() => (cnpj) =>
    interesse.value.some((e) => e.cnpj === cnpj),
  );

  function toggleInteresse(cnpj, razaoSocial) {
    if (isInteresse.value(cnpj)) {
      interesse.value = interesse.value.filter((e) => e.cnpj !== cnpj);
    } else {
      interesse.value.push({ cnpj, razaoSocial, adicionadoEm: new Date().toISOString() });
    }
    saveToStorage(interesse);
  }

  return {
    interesse,
    isInteresse,
    toggleInteresse,
  };
});
