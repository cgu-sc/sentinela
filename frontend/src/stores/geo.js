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

  // Municípios filtrados por UF e/ou Região de Saúde (Com tratamento de homônimos)
  function municipiosPorFiltro(uf, regiao) {
    let filtradas = localidades.value;
    if (uf !== 'Todos') filtradas = filtradas.filter(l => l.sg_uf === uf);
    if (regiao !== 'Todos') filtradas = filtradas.filter(l => l.no_regiao_saude === regiao);
    
    // Gera lista de objetos únicos { label, value }
    // O valor é sempre 'Nome|UF' para garantir unicidade total
    const list = filtradas.map(l => ({
        label: uf === 'Todos' ? `${l.no_municipio} - ${l.sg_uf}` : l.no_municipio,
        value: `${l.no_municipio}|${l.sg_uf}`,
        nome: l.no_municipio,
        uf: l.sg_uf
    }));

    // Remove duplicatas e ordena
    const unique = Array.from(new Map(list.map(item => [item.value, item])).values());
    unique.sort((a, b) => a.label.localeCompare(b.label));

    return [{ label: 'Todos', value: 'Todos' }, ...unique];
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
