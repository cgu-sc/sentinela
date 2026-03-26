import { defineStore } from 'pinia';
import { ref, computed } from 'vue';
import axios from 'axios';
import { API_ENDPOINTS } from '../config/api';

export const useGeoStore = defineStore('geo', () => {
  const localidades = ref([]);
  const isLoading = ref(false);

  async function fetchLocalidades() {
    isLoading.value = true;
    try {
      const response = await axios.get(API_ENDPOINTS.geoLocalidades);
      localidades.value = response.data.localidades;
    } catch (err) {
      console.error('Erro ao buscar localidades:', err);
    } finally {
      isLoading.value = false;
    }
  }

  // UFs distintas (sempre fixo, mas derivado dos dados reais)
  const ufs = computed(() => {
    const set = new Set(localidades.value.map(l => l.sg_uf));
    return ['Todos', ...Array.from(set).sort()];
  });

  // Regiões de saúde filtradas pela UF selecionada
  function regioesPorUF(uf) {
    const filtradas = uf === 'Todos'
      ? localidades.value
      : localidades.value.filter(l => l.sg_uf === uf);
    const set = new Set(filtradas.map(l => l.no_regiao_saude));
    return ['Todos', ...Array.from(set).sort()];
  }

  // Municípios filtrados por UF e/ou Região de Saúde
  function municipiosPorFiltro(uf, regiao) {
    let filtradas = localidades.value;
    if (uf !== 'Todos') filtradas = filtradas.filter(l => l.sg_uf === uf);
    if (regiao !== 'Todos') filtradas = filtradas.filter(l => l.no_regiao_saude === regiao);
    const set = new Set(filtradas.map(l => l.no_municipio));
    return ['Todos', ...Array.from(set).sort()];
  }

  return {
    localidades,
    isLoading,
    fetchLocalidades,
    ufs,
    regioesPorUF,
    municipiosPorFiltro,
  };
});
