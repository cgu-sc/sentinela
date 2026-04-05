import { defineStore } from 'pinia';
import { ref, computed } from 'vue';
import axios from 'axios';
import { API_ENDPOINTS } from '../config/api';

export const useGeoStore = defineStore('geo', () => {
  const localidades = ref([]);
  const isLoading = ref(false);

  // GeoJSON de municípios — carregado no boot, filtrado por UF sob demanda
  const municipiosGeoJson = ref(null);

  async function loadMunicipiosGeo() {
    try {
      municipiosGeoJson.value = await fetch('/geo/brasil-mun.json').then(r => r.json());
    } catch (err) {
      console.error('Erro ao carregar GeoJSON de municípios:', err);
    }
  }

  const UF_IBGE = {
    RO:'11', AC:'12', AM:'13', RR:'14', PA:'15', AP:'16', TO:'17',
    MA:'21', PI:'22', CE:'23', RN:'24', PB:'25', PE:'26', AL:'27', SE:'28', BA:'29',
    MG:'31', ES:'32', RJ:'33', SP:'35',
    PR:'41', SC:'42', RS:'43',
    MS:'50', MT:'51', GO:'52', DF:'53',
  };

  function getMunicipiosGeoByUF(uf) {
    if (!municipiosGeoJson.value || !uf || uf === 'Todos') return null;
    const prefix = UF_IBGE[uf];
    if (!prefix) return null;
    return {
      type: 'FeatureCollection',
      features: municipiosGeoJson.value.features.filter(f =>
        String(f.properties.id).startsWith(prefix)
      ),
    };
  }


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
  function qtdMunicipiosPorRegiao(regiao) {
    if (!regiao) return null;
    const municipios = new Set(
      localidades.value
        .filter((l) => l.no_regiao_saude === regiao)
        .map((l) => l.no_municipio)
    );
    return municipios.size || null;
  }

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
    qtdMunicipiosPorRegiao,
    municipiosGeoJson,
    loadMunicipiosGeo,
    getMunicipiosGeoByUF,
  };
});
