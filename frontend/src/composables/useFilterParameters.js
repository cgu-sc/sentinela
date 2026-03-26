import { useFilterStore } from '../stores/filters';
import { useFormatting } from './useFormatting';

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
    const fim    = p?.[1] ? toLocalISO(p[1]) : null;

    const percMin = filterStore.percentualNaoComprovacaoFilter[0] !== 0   ? filterStore.percentualNaoComprovacaoFilter[0] : null;
    const percMax = filterStore.percentualNaoComprovacaoFilter[1] !== 100 ? filterStore.percentualNaoComprovacaoFilter[1] : null;
    const valMin  = filterStore.valorMinSemCompFilter > 0 ? filterStore.valorMinSemCompFilter : null;

    const uf          = filterStore.selectedUF !== 'Todos'          ? filterStore.selectedUF          : null;
    const regiaoSaude = filterStore.selectedRegiaoSaude !== 'Todos' ? filterStore.selectedRegiaoSaude : null;
    const municipio   = filterStore.selectedMunicipio !== 'Todos'   ? filterStore.selectedMunicipio   : null;

    return { inicio, fim, percMin, percMax, valMin, uf, regiaoSaude, municipio };
  }

  function isPeriodoValido() {
    const p = filterStore.periodo;
    return p && Array.isArray(p) && p.length === 2 && p[0] && p[1];
  }

  return { getApiParams, isPeriodoValido };
}
