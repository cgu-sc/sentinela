/**
 * Centraliza a lógica de busca dos dados de analytics.
 * Evita duplicação do padrão fetchTodos() entre NationalAnalysisView e BeneficioDispersaoView.
 *
 * @param {Object} options
 * @param {boolean} options.includeFatorRisco - Incluir busca do gráfico Fator Risco (default: false)
 */
import { watch } from 'vue';
import { useFilterStore } from '@/stores/filters';
import { useAnalyticsStore, buildAnalyticsParams } from '@/stores/analytics';
import { useFilterParameters } from '@/composables/useFilterParameters';

export function useFetchAnalytics({ includeFatorRisco = false, includeNationalContext = true } = {}) {
  const filterStore    = useFilterStore();
  const analyticsStore = useAnalyticsStore();
  const { getApiParams, isPeriodoValido } = useFilterParameters();

  const fetchAll = () => {
    const p = getApiParams();
    const args = [
      p.inicio, p.fim, p.percMin, p.percMax, p.valMin,
      p.uf, p.regiaoSaude, p.municipio, p.situacaoRf,
      p.conexaoMs, p.porteEmpresa, p.grandeRede, p.cnpjRaiz, p.unidadePf, p.razaoSocial,
    ];

    analyticsStore.fetchDashboardSummary(...args);
    if (includeFatorRisco) analyticsStore.fetchFatorRisco(...args);
  };

  // Filtros que afetam os dados nacionais do mapa do Brasil (sem UF/região/município)
  const fetchNacionalIfNeeded = () => {
    // Só buscamos os dados nacionais (mapa) separadamente se houver um filtro de UF/Região/Mun ativo
    // e se o componente solicitar explicitamente esse contexto (ex: telas que mantêm o mapa do Brasil visível).
    if (!includeNationalContext || !isPeriodoValido() || !filterStore.selectedUF || filterStore.selectedUF === 'Todos') return;
    const p = getApiParams();
    analyticsStore.fetchSentinelaUFNacional(
      p.inicio, p.fim, p.percMin, p.percMax, p.valMin,
      p.situacaoRf, p.conexaoMs, p.porteEmpresa, p.grandeRede, p.unidadePf,
    );
  };

  const isFresh = () => {
    const p = getApiParams();
    // Usamos a mesma função do store para garantir que o hash das chaves seja idêntico (ex: data_inicio vs inicio)
    const apiReadyParams = buildAnalyticsParams(
      p.inicio, p.fim, p.percMin, p.percMax, p.valMin,
      p.uf, p.regiaoSaude, p.municipio, p.situacaoRf,
      p.conexaoMs, p.porteEmpresa, p.grandeRede, p.cnpjRaiz, p.unidadePf, p.razaoSocial
    );
    const currentHash = JSON.stringify(apiReadyParams);
    return analyticsStore.lastParamsHash === currentHash;
  };
  
  let isFirstRun = true;

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
      filterStore.selectedUnidadePf,
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
    () => { if (isPeriodoValido()) fetchAll(); }
  );

  return { fetchAll };
}
