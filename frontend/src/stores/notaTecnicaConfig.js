import { computed, ref } from "vue";
import { defineStore } from "pinia";
import axios from "axios";
import { API_ENDPOINTS } from "@/config/api";

export const useNotaTecnicaConfigStore = defineStore("notaTecnicaConfig", () => {
  const regionais = ref([]);
  const selectedRegionalCodigo = ref(null);
  const ultimoNumeroNota = ref("");
  const ultimoNumeroProcesso = ref("");
  const loading = ref(false);
  const saving = ref(false);
  const loaded = ref(false);

  const selectedRegional = computed(() =>
    regionais.value.find((regional) => regional.codigo === selectedRegionalCodigo.value) ?? null,
  );

  const selectedRegionalLabel = computed(() => {
    const regional = selectedRegional.value;
    return regional ? `${regional.codigo} - ${regional.estado}` : null;
  });

  async function ensureLoaded() {
    if (loaded.value) return;

    loading.value = true;
    try {
      const [regionaisResponse, preferencesResponse] = await Promise.all([
        axios.get(API_ENDPOINTS.analyticsNotaTecnicaRegionais),
        axios.get(API_ENDPOINTS.preferences),
      ]);

      if (!Array.isArray(regionaisResponse.data)) {
        throw new Error("Lista de regionais da Nota Técnica inválida.");
      }

      regionais.value = regionaisResponse.data;
      selectedRegionalCodigo.value =
        preferencesResponse.data?.nota_tecnica?.regional_codigo ?? null;
      ultimoNumeroNota.value =
        preferencesResponse.data?.nota_tecnica?.ultimo_numero_nota ?? "";
      ultimoNumeroProcesso.value =
        preferencesResponse.data?.nota_tecnica?.ultimo_numero_processo ?? "";
      loaded.value = true;
    } finally {
      loading.value = false;
    }
  }

  async function saveNotaTecnicaConfig({
    regionalCodigo,
    numeroNota = ultimoNumeroNota.value,
    numeroProcesso = ultimoNumeroProcesso.value,
  }) {
    const normalized = String(regionalCodigo || "").trim().toUpperCase();
    if (!normalized) {
      throw new Error("Selecione a Regional emissora da Nota Técnica.");
    }

    const regional = regionais.value.find((item) => item.codigo === normalized);
    if (!regional) {
      throw new Error(`Regional emissora inválida: ${normalized}.`);
    }

    saving.value = true;
    try {
      const notaTecnica = {
        regional_codigo: normalized,
        ultimo_numero_nota: String(numeroNota || "").trim(),
        ultimo_numero_processo: String(numeroProcesso || "").trim(),
      };
      const { data } = await axios.put(API_ENDPOINTS.preferencesNotaTecnica, {
        nota_tecnica: notaTecnica,
      });
      selectedRegionalCodigo.value = data?.nota_tecnica?.regional_codigo ?? normalized;
      ultimoNumeroNota.value = data?.nota_tecnica?.ultimo_numero_nota ?? notaTecnica.ultimo_numero_nota;
      ultimoNumeroProcesso.value =
        data?.nota_tecnica?.ultimo_numero_processo ?? notaTecnica.ultimo_numero_processo;
      loaded.value = true;
      return selectedRegional.value;
    } finally {
      saving.value = false;
    }
  }

  async function saveRegionalCodigo(codigo) {
    return saveNotaTecnicaConfig({ regionalCodigo: codigo });
  }

  return {
    regionais,
    selectedRegionalCodigo,
    ultimoNumeroNota,
    ultimoNumeroProcesso,
    selectedRegional,
    selectedRegionalLabel,
    loading,
    saving,
    loaded,
    ensureLoaded,
    saveRegionalCodigo,
    saveNotaTecnicaConfig,
  };
});
