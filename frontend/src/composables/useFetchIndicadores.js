import { watch } from 'vue';
import { useFilterStore } from '@/stores/filters';
import { useIndicadoresStore } from '@/stores/indicadores';
import { useFilterParameters } from './useFilterParameters';

/**
 * Orquestra o fetch da análise de indicadores reagindo aos filtros da sidebar.
 *
 * Assina apenas filtros geográficos e cadastrais — período, percentual e valor mínimo
 * não se aplicam ao endpoint /indicadores-analise (opera sobre snapshot matriz_risco).
 */
export function useFetchIndicadores() {
  const filterStore = useFilterStore();
  const indicadoresStore = useIndicadoresStore();
  const { getApiParams } = useFilterParameters();

  /**
   * Extrai os parâmetros aceitos pelo endpoint /indicadores-analise.
   * Agora inclui filtros de percentual e valor acumulado.
   */
  function getIndicadorParams() {
    const {
      uf, regiaoId, situacaoRf, conexaoMs, porteEmpresa, grandeRede, cnpjRaiz, razaoSocial, unidadePf, parTeia,
      percMin, percMax, valMin
    } = getApiParams();

    const params = {};
    if (uf) params.uf = uf;

    // Descomentado para desafogar o servidor e retornar dados apenas da região
    if (regiaoId !== null && regiaoId !== undefined) params.regiao_id = regiaoId;
    // O município continua focado apenas localmente para que o usuário veja
    // todo o contexto da região no mapa e na tabela.
    if (situacaoRf)   params.situacao_rf = situacaoRf;
    if (conexaoMs)    params.conexao_ms = conexaoMs;
    if (porteEmpresa) params.porte_empresa = porteEmpresa;
    if (grandeRede)   params.grande_rede = grandeRede;
    if (cnpjRaiz)     params.cnpj_raiz = cnpjRaiz;
    if (razaoSocial)  params.razao_social = razaoSocial;
    if (unidadePf)    params.unidade_pf = unidadePf;
    if (parTeia)      params.par_teia = parTeia;

    // Novos: Filtros de Auditoria (Snapshot)
    if (percMin !== null) params.perc_min = percMin;
    if (percMax !== null) params.perc_max = percMax;
    if (valMin !== null)  params.val_min  = valMin;

    return params;
  }

  function getIndicadorTabelaParams() {
    const params = getIndicadorParams();
    const { idIbge7 } = getApiParams();
    if (idIbge7 !== null && idIbge7 !== undefined) params.id_ibge7 = idIbge7;
    return params;
  }

  /**
   * Dispara o fetch para o indicador informado com os filtros atuais.
   *
   * @param {string} indicadorKey - Chave do indicador (ex: 'auditado')
   */
  function fetchForIndicador(indicadorKey) {
    indicadoresStore.fetchIndicadorAnalise(indicadorKey, getIndicadorParams());
    indicadoresStore.fetchIndicadorCnpjs(indicadorKey, getIndicadorTabelaParams(), { page: 1 });
  }

  function fetchCnpjsForIndicador(indicadorKey, tableState = {}) {
    indicadoresStore.fetchIndicadorCnpjs(indicadorKey, getIndicadorTabelaParams(), tableState);
  }

  // Re-dispara automaticamente quando filtros mudam.
  // Inclui agora percentual e valor mínimo acumulado.
  watch(
    () => [
      filterStore.selectedUF,
      filterStore.selectedRegiaoSaude,
      filterStore.selectedMunicipio,
      filterStore.selectedSituacao,
      filterStore.selectedMS,
      filterStore.selectedPorte,
      filterStore.selectedGrandeRede,
      filterStore.selectedParTeia,
      filterStore.selectedUnidadePf,
      filterStore.selectedCnpjRaiz,
      filterStore.percentualNaoComprovacaoFilter, // Reativo ao Slider de %
      filterStore.valorMinSemCompFilter,          // Reativo ao Slider de Valor
    ],
    () => {
      if (indicadoresStore.selectedIndicador) {
        fetchForIndicador(indicadoresStore.selectedIndicador);
      }
    },
    { immediate: true, deep: true }
  );

  return { fetchForIndicador, fetchCnpjsForIndicador };
}
