import { useFilterStore } from '../stores/filters';
import { useFormatting } from './useFormatting';
import { FILTER_ALL_VALUE } from '@/config/constants';

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

    const uf = filterStore.selectedUF !== FILTER_ALL_VALUE ? filterStore.selectedUF : null;
    const regiaoSaude = filterStore.selectedRegiaoSaude !== FILTER_ALL_VALUE ? filterStore.selectedRegiaoSaude : null;
    const municipio = filterStore.selectedMunicipio !== FILTER_ALL_VALUE ? filterStore.selectedMunicipio : null;
    const situacaoRf = filterStore.selectedSituacao !== FILTER_ALL_VALUE ? filterStore.selectedSituacao : null;
    const conexaoMs = filterStore.selectedMS !== FILTER_ALL_VALUE ? filterStore.selectedMS : null;
    const porteEmpresa = filterStore.selectedPorte !== FILTER_ALL_VALUE ? filterStore.selectedPorte : null;
    const grandeRede   = filterStore.selectedGrandeRede !== FILTER_ALL_VALUE ? filterStore.selectedGrandeRede : null;

    return { inicio, fim, percMin, percMax, valMin, uf, regiaoSaude, municipio, situacaoRf, conexaoMs, porteEmpresa, grandeRede };
  }

  function isPeriodoValido() {
    const p = filterStore.periodo;
    return p && Array.isArray(p) && p.length === 2 && p[0] && p[1];
  }

  return { getApiParams, isPeriodoValido };
}
