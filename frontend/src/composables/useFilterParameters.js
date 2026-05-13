import { useFilterStore } from '../stores/filters';
import { useFormatting } from './useFormatting';
import { extractCnpjFilter } from './useParsing';
import { FILTER_ALL_VALUE, FILTER_DEFAULTS } from '@/config/constants';

/**
 * Converte os filtros do Pinia em parâmetros prontos para a API.
 * Centraliza toda a lógica de conversão (datas ISO, nulos, "Todos" → null).
 */
export function useFilterParameters() {
  const filterStore = useFilterStore();
  const { toLocalISO } = useFormatting();

  function getApiParams() {
    const p = filterStore.periodo;
    const inicio = p?.[0] ? toLocalISO(p[0]) : null;
    const fim = p?.[1] ? toLocalISO(p[1]) : null;

    const percMin = filterStore.percentualNaoComprovacaoFilter[0] !== 0 ? filterStore.percentualNaoComprovacaoFilter[0] : null;
    const percMax = filterStore.percentualNaoComprovacaoFilter[1] !== 100 ? filterStore.percentualNaoComprovacaoFilter[1] : null;
    const valMin = filterStore.valorMinSemCompFilter > 0 ? filterStore.valorMinSemCompFilter : null;
    const volumeAtipicoEnabled = Boolean(filterStore.volumeAtipicoEnabled);
    const volumeAtipicoPercentual = volumeAtipicoEnabled
      ? Math.max(
          FILTER_DEFAULTS.VOLUME_ATIPICO_MIN,
          Math.min(FILTER_DEFAULTS.VOLUME_ATIPICO_MAX, Number(filterStore.volumeAtipicoPercentualFilter) || FILTER_DEFAULTS.VOLUME_ATIPICO_PERCENTUAL)
        )
      : null;

    const uf = filterStore.selectedUF !== FILTER_ALL_VALUE ? filterStore.selectedUF : null;
    const rawRegiao = filterStore.selectedRegiaoSaude !== FILTER_ALL_VALUE ? filterStore.selectedRegiaoSaude : null;
    const regiaoId = rawRegiao ? Number(rawRegiao) : null;
    if (rawRegiao && Number.isNaN(regiaoId)) {
      throw new Error('Filtro regional invalido: use id_regiao_saude.');
    }

    const rawMunicipio = filterStore.selectedMunicipio !== FILTER_ALL_VALUE ? filterStore.selectedMunicipio : null;
    const idIbge7 = rawMunicipio ? Number(rawMunicipio) : null;
    if (rawMunicipio && Number.isNaN(idIbge7)) {
      throw new Error('Filtro municipal invalido: use id_ibge7.');
    }
    const situacaoRf = filterStore.selectedSituacao !== FILTER_ALL_VALUE ? filterStore.selectedSituacao : null;
    const conexaoMs = filterStore.selectedMS !== FILTER_ALL_VALUE ? filterStore.selectedMS : null;
    const porteEmpresa = filterStore.selectedPorte !== FILTER_ALL_VALUE ? filterStore.selectedPorte : null;
    const grandeRede   = filterStore.selectedGrandeRede !== FILTER_ALL_VALUE ? filterStore.selectedGrandeRede : null;
    // Detecção automática: ≥8 dígitos numéricos → CNPJ; texto livre → razão social
    // Coerção defensiva: AutoComplete pode entregar objeto antes do onSelect handler
    const raw = filterStore.selectedCnpjRaiz;
    const rawSearch = typeof raw === 'string' ? raw : (raw?.cnpj ?? raw?.label ?? '');
    const numericOnly = rawSearch.replace(/\D/g, '');
    const cnpjRaiz   = numericOnly.length >= 8 ? extractCnpjFilter(rawSearch) : null;
    const razaoSocial = numericOnly.length < 8 && rawSearch.trim().length >= 2 ? rawSearch.trim() : null;

    const unidadePf    = filterStore.selectedUnidadePf !== FILTER_ALL_VALUE ? filterStore.selectedUnidadePf : null;

    return { 
      inicio, 
      fim, 
      percMin, 
      percMax, 
      valMin, 
      uf, 
      regiaoId, 
      idIbge7,
      situacaoRf, 
      conexaoMs, 
      porteEmpresa, 
      grandeRede, 
      cnpjRaiz, 
      razaoSocial, 
      unidadePf,
      volumeAtipicoEnabled,
      volumeAtipicoPercentual
    };
  }

  function isPeriodoValido() {
    const p = filterStore.periodo;
    return p && Array.isArray(p) && p.length === 2 && p[0] && p[1];
  }

  return { getApiParams, isPeriodoValido };
}
