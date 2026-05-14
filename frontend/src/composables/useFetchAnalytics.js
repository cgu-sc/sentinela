/**
 * Centraliza a lógica de busca dos dados de analytics.
 * Evita duplicação do padrão fetchTodos() entre NationalAnalysisView e BeneficioDispersaoView.
 *
 * @param {Object} options
 * @param {boolean} options.includeFatorRisco - Incluir busca do gráfico Fator Risco (default: false)
 */
import { onScopeDispose, watch } from 'vue';
import { useFilterStore } from '@/stores/filters';
import { useAnalyticsStore, buildAnalyticsParams } from '@/stores/analytics';
import { useFilterParameters } from '@/composables/useFilterParameters';

const ESTABELECIMENTO_FETCH_DEBOUNCE_MS = 450;

export function useFetchAnalytics({ includeFatorRisco = false, includeNationalContext = true } = {}) {
  const filterStore    = useFilterStore();
  const analyticsStore = useAnalyticsStore();
  const { getApiParams, isPeriodoValido } = useFilterParameters();

  const fetchAll = () => {
    const filters = getApiParams();
    analyticsStore.fetchDashboardSummary(filters);
    if (includeFatorRisco) analyticsStore.fetchFatorRisco(filters);
  };

  // Filtros que afetam os dados nacionais do mapa do Brasil (sem UF/região/município)
  const fetchNacionalIfNeeded = () => {
    // Só buscamos os dados nacionais (mapa) separadamente se houver um filtro de UF/Região/Mun ativo
    // e se o componente solicitar explicitamente esse contexto (ex: telas que mantêm o mapa do Brasil visível).
    if (!includeNationalContext || !isPeriodoValido() || !filterStore.selectedUF || filterStore.selectedUF === 'Todos') return;
    analyticsStore.fetchSentinelaUFNacional(getApiParams());
  };

  const isFresh = () => {
    // Usamos a mesma função do store para garantir que o hash das chaves seja idêntico (ex: data_inicio vs inicio)
    const apiReadyParams = buildAnalyticsParams(getApiParams());
    const currentHash = JSON.stringify(apiReadyParams);
    return analyticsStore.lastParamsHash === currentHash;
  };
  
  let isFirstRun = true;
  let estabelecimentoFetchTimer = null;

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
      filterStore.selectedParTeia,
      filterStore.selectedUnidadePf,
      filterStore.volumeAtipicoEnabled,
      filterStore.volumeAtipicoPercentualFilter,
    ],
    () => { 
      const skip = isFirstRun && isFresh();
      if (isPeriodoValido() && !skip) {
        fetchAll(); 
      }
    },
    { deep: true, immediate: true }
  );

  // Watch separado para filtros que atualizam o mapa nacional quando UF está selecionada
  watch(
    () => [
      filterStore.periodo,
      filterStore.percentualNaoComprovacaoFilter,
      filterStore.valorMinSemCompFilter,
      filterStore.selectedSituacao,
      filterStore.selectedMS,
      filterStore.selectedPorte,
      filterStore.selectedGrandeRede,
      filterStore.selectedParTeia,
      filterStore.volumeAtipicoEnabled,
      filterStore.volumeAtipicoPercentualFilter,
    ],
    () => {
      const skip = isFirstRun && isFresh();
      if (isPeriodoValido() && !skip) {
        fetchNacionalIfNeeded();
      }
      isFirstRun = false; // Após a primeira execução de ambos, liberamos o bloqueio
    },
    { deep: true, immediate: true }
  );

  // Watch separado para cnpjRaiz — string primitiva, não precisa de deep
  watch(
    () => filterStore.selectedCnpjRaiz,
    () => {
      clearTimeout(estabelecimentoFetchTimer);
      estabelecimentoFetchTimer = setTimeout(() => {
        if (isPeriodoValido()) fetchAll();
      }, ESTABELECIMENTO_FETCH_DEBOUNCE_MS);
    }
  );

  onScopeDispose(() => {
    clearTimeout(estabelecimentoFetchTimer);
  });

  return { fetchAll };
}
