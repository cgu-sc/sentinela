import { defineStore } from 'pinia';
import { ref, computed } from 'vue';
import axios from 'axios';
import { API_ENDPOINTS } from '@/config/api';

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

async function saveToBackend(interesse) {
  try {
    await axios.put(API_ENDPOINTS.preferencesWatchlist, {
      interesse: interesse.value,
    });
  } catch (error) {
    console.warn('[farmaciaLists] Falha ao sincronizar lista no backend:', error);
  }
}

export const useFarmaciaListsStore = defineStore('farmaciaLists', () => {
  const stored = loadFromStorage();
  const interesse = ref(stored.interesse || []);

  async function loadFromBackend() {
    try {
      const { data } = await axios.get(API_ENDPOINTS.preferences);
      const backendList = Array.isArray(data?.watchlist) ? data.watchlist : [];

      if (backendList.length > 0 || interesse.value.length === 0) {
        interesse.value = backendList;
        saveToStorage(interesse);
      } else {
        await saveToBackend(interesse);
      }
    } catch (error) {
      console.warn('[farmaciaLists] Usando lista local do navegador:', error);
    }
  }

  const isInteresse = computed(() => (cnpj) =>
    interesse.value.some((e) => e.cnpj === cnpj),
  );

  function toggleInteresse(cnpj, razaoSocial) {
    if (isInteresse.value(cnpj)) {
      interesse.value = interesse.value.filter((e) => e.cnpj !== cnpj);
    } else {
      interesse.value.push({
        cnpj,
        razaoSocial,
        adicionadoEm: new Date().toISOString(),
        observacao: '',
      });
    }
    saveToStorage(interesse);
    saveToBackend(interesse);
  }

  function setObservacao(cnpj, text) {
    const item = interesse.value.find((e) => e.cnpj === cnpj);
    if (item) {
      item.observacao = text;
      item.atualizadoEm = new Date().toISOString();
      saveToStorage(interesse);
      saveToBackend(interesse);
    }
  }

  const getObservacao = computed(() => (cnpj) => {
    const item = interesse.value.find((e) => e.cnpj === cnpj);
    return item ? item.observacao : '';
  });

  loadFromBackend();

  return {
    interesse,
    isInteresse,
    toggleInteresse,
    setObservacao,
    getObservacao,
  };
});
