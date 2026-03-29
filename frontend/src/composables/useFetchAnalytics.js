/**
 * Centraliza a lógica de busca dos dados de analytics.
 * Evita duplicação do padrão fetchTodos() entre NationalAnalysisView e BeneficioDispersaoView.
 *
 * @param {Object} options
 * @param {boolean} options.includeFatorRisco - Incluir busca do gráfico Fator Risco (default: false)
 */
import { watch } from 'vue';
import { useFilterStore } from '@/stores/filters';
import { useAnalyticsStore } from '@/stores/analytics';
import { useFilterParameters } from '@/composables/useFilterParameters';

export function useFetchAnalytics({ includeFatorRisco = false } = {}) {
  const filterStore    = useFilterStore();
  const analyticsStore = useAnalyticsStore();
  const { getApiParams, isPeriodoValido } = useFilterParameters();

  const fetchAll = () => {
    const p = getApiParams();
    const args = [
      p.inicio, p.fim, p.percMin, p.percMax, p.valMin,
      p.uf, p.regiaoSaude, p.municipio, p.situacaoRf,
      p.conexaoMs, p.porteEmpresa, p.grandeRede, p.cnpjRaiz,
    ];

    analyticsStore.fetchDashboardSummary(...args);
    if (includeFatorRisco) analyticsStore.fetchFatorRisco(...args);
  };

  watch(
    () => [
      filterStore.periodo,
      filterStore.percentualNaoComprovacaoFilter,
      filterStore.valorMinSemCompFilter,
      filterStore.selectedUF,
      filterStore.selectedRegiaoSaude,
      filterStore.selectedMunicipio,
      filterStore.selectedSituacao,
      filterStore.selectedMS,
      filterStore.selectedPorte,
      filterStore.selectedGrandeRede,
    ],
    () => { if (isPeriodoValido()) fetchAll(); },
    { deep: true, immediate: false }
  );

  // Watch separado para cnpjRaiz — string primitiva, não precisa de deep
  watch(
    () => filterStore.selectedCnpjRaiz,
    () => { if (isPeriodoValido()) fetchAll(); }
  );

  return { fetchAll };
}
