import { defineStore } from 'pinia';
import { ref, watch } from 'vue';
import axios from 'axios';
import { API_ENDPOINTS } from '@/config/api';
import { INDICATOR_THRESHOLDS as DEFAULT_THRESHOLDS } from '@/config/riskConfig';

const STORAGE_KEY = 'sentinela_config_thresholds';

export const useConfigStore = defineStore('config', () => {
  // 1. ESTADO INICIAL: Tenta carregar do LocalStorage, caso contrário usa o padrão
  const saved = localStorage.getItem(STORAGE_KEY);
  const thresholds = ref(saved ? JSON.parse(saved) : { ...DEFAULT_THRESHOLDS });
  
  const isLoading = ref(false);
  const hasLoaded = ref(false);

  // 2. PERSISTÊNCIA AUTOMÁTICA (IGUAL À SIDEBAR)
  let _saveTimer = null;
  watch(thresholds, (newThresholds) => {
    clearTimeout(_saveTimer);
    _saveTimer = setTimeout(() => {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(newThresholds));
      console.log('✅ Configurações de risco persistidas no LocalStorage (Autosave).');
    }, 300); // 300ms de debounce
  }, { deep: true });

  // 3. ACTIONS
  /**
   * Sincroniza com o backend apenas se não houver configurações locais
   * ou se for estritamente necessário.
   */
  async function fetchThresholds(force = false) {
    // Se já temos dados no LocalStorage e não estamos forçando, não buscamos
    if (localStorage.getItem(STORAGE_KEY) && !force) {
      hasLoaded.value = true;
      return;
    }

    isLoading.value = true;
    try {
      const response = await axios.get(API_ENDPOINTS.analyticsConfigThresholds);
      if (response.data) {
        const formatted = {};
        for (const [key, values] of Object.entries(response.data)) {
          formatted[key] = {
            atencao: values[0],
            critico: values[1]
          };
        }
        // Só atualizamos se o usuário ainda não tiver customizado
        thresholds.value = formatted;
        hasLoaded.value = true;
      }
    } catch (err) {
      console.warn('⚠️ Falha ao sincronizar com backend. Usando padrões locais.', err);
    } finally {
      isLoading.value = false;
    }
  }

  /**
   * Substitui os limiares atuais pelos novos (usado no botão Aplicar)
   */
  function applyLocalThresholds(edited) {
    thresholds.value = { ...edited };
  }

  /**
   * Reseta para os padrões do código e limpa o cache
   */
  function resetToDefaults() {
    thresholds.value = { ...DEFAULT_THRESHOLDS };
    localStorage.removeItem(STORAGE_KEY);
    console.log('🗑️ Configurações resetadas para o padrão de fábrica.');
  }

  return {
    thresholds,
    isLoading,
    hasLoaded,
    fetchThresholds,
    applyLocalThresholds,
    resetToDefaults
  };
});
