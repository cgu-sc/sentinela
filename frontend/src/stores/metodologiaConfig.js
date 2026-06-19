import { computed, ref } from "vue";
import { defineStore } from "pinia";
import axios from "axios";
import { API_ENDPOINTS } from "@/config/api";

export const useMetodologiaConfigStore = defineStore("metodologiaConfig", () => {
  const auditHighValue = ref(null);
  const volumeAtipicoAumentoMinimo = ref(null);
  const defaults = ref({});
  const limits = ref({});
  const loading = ref(false);
  const saving = ref(false);
  const loaded = ref(false);

  const auditHighValueLimits = computed(
    () => limits.value.audit_high_value,
  );

  const auditHighValueDefault = computed(
    () => defaults.value.audit_high_value,
  );

  const volumeAtipicoLimits = computed(
    () => limits.value.volume_atipico_aumento_minimo,
  );

  const volumeAtipicoDefault = computed(
    () => defaults.value.volume_atipico_aumento_minimo,
  );

  function applyPayload(payload) {
    const rawAuditHighValue = payload?.audit_high_value;
    const rawAuditHighValueDefault = payload?.defaults?.audit_high_value;
    const rawAuditHighValueLimits = payload?.limits?.audit_high_value;
    const rawValue = payload?.volume_atipico_aumento_minimo;
    const rawDefault = payload?.defaults?.volume_atipico_aumento_minimo;
    const rawLimits = payload?.limits?.volume_atipico_aumento_minimo;
    if (
      rawAuditHighValue == null ||
      rawAuditHighValueDefault == null ||
      !rawAuditHighValueLimits ||
      rawValue == null ||
      rawDefault == null ||
      !rawLimits
    ) {
      throw new Error("Configuração metodológica incompleta.");
    }
    auditHighValue.value = Number(rawAuditHighValue);
    volumeAtipicoAumentoMinimo.value = Number(rawValue);
    defaults.value = payload.defaults;
    limits.value = payload.limits;
    loaded.value = true;
  }

  async function ensureLoaded({ force = false } = {}) {
    if (loaded.value && !force) return;

    loading.value = true;
    try {
      const { data } = await axios.get(API_ENDPOINTS.preferencesMetodologia);
      applyPayload(data);
    } finally {
      loading.value = false;
    }
  }

  async function saveVolumeAtipicoAumentoMinimo(value) {
    saving.value = true;
    try {
      const { data } = await axios.put(API_ENDPOINTS.preferencesMetodologia, {
        metodologia: {
          audit_high_value: auditHighValue.value,
          volume_atipico_aumento_minimo: value,
        },
      });
      applyPayload(data);
    } finally {
      saving.value = false;
    }
  }

  async function saveAuditHighValue(value) {
    saving.value = true;
    try {
      const { data } = await axios.put(API_ENDPOINTS.preferencesMetodologia, {
        metodologia: {
          audit_high_value: value,
          volume_atipico_aumento_minimo: volumeAtipicoAumentoMinimo.value,
        },
      });
      applyPayload(data);
    } finally {
      saving.value = false;
    }
  }

  return {
    auditHighValue,
    auditHighValueLimits,
    auditHighValueDefault,
    volumeAtipicoAumentoMinimo,
    volumeAtipicoLimits,
    volumeAtipicoDefault,
    loading,
    saving,
    loaded,
    ensureLoaded,
    saveAuditHighValue,
    saveVolumeAtipicoAumentoMinimo,
  };
});
