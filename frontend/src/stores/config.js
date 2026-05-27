import { defineStore } from 'pinia';
import { ref, watch } from 'vue';
import { INDICATOR_THRESHOLDS as DEFAULT_THRESHOLDS } from '@/config/riskConfig';

const STORAGE_KEY = 'sentinela_config_thresholds';

export const useConfigStore = defineStore('config', () => {
  const saved = localStorage.getItem(STORAGE_KEY);
  const thresholds = ref(saved
    ? { ...DEFAULT_THRESHOLDS, ...JSON.parse(saved) }
    : { ...DEFAULT_THRESHOLDS }
  );

  const isLoading = ref(false);
  const hasLoaded = ref(false);

  let saveTimer = null;
  watch(thresholds, (newThresholds) => {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(() => {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(newThresholds));
    }, 500);
  }, { deep: true });

  function fetchThresholds() {
    hasLoaded.value = true;
  }

  function applyLocalThresholds(edited) {
    thresholds.value = { ...edited };
  }

  function resetToDefaults() {
    thresholds.value = { ...DEFAULT_THRESHOLDS };
    localStorage.removeItem(STORAGE_KEY);
  }

  return {
    thresholds,
    isLoading,
    hasLoaded,
    fetchThresholds,
    applyLocalThresholds,
    resetToDefaults,
  };
});
