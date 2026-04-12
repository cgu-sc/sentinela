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
   * Extrai apenas os parâmetros aceitos pelo endpoint /indicadores-analise.
   */
  function getIndicadorParams() {
    const { uf, regiaoSaude, municipio, situacaoRf, conexaoMs, porteEmpresa, grandeRede, cnpjRaiz, unidadePf } = getApiParams();
    const params = {};
    if (uf)           params.uf = uf;
    if (regiaoSaude)  params.regiao_saude = regiaoSaude;
    if (municipio)    params.municipio = municipio;
    if (situacaoRf)   params.situacao_rf = situacaoRf;
    if (conexaoMs)    params.conexao_ms = conexaoMs;
    if (porteEmpresa) params.porte_empresa = porteEmpresa;
    if (grandeRede)   params.grande_rede = grandeRede;
    if (cnpjRaiz)     params.cnpj_raiz = cnpjRaiz;
    if (unidadePf)    params.unidade_pf = unidadePf;
    return params;
  }

  /**
   * Dispara o fetch para o indicador informado com os filtros atuais.
   *
   * @param {string} indicadorKey - Chave do indicador (ex: 'auditado')
   */
  function fetchForIndicador(indicadorKey) {
    indicadoresStore.fetchIndicadorAnalise(indicadorKey, getIndicadorParams());
  }

  // Re-dispara automaticamente quando filtros geográficos/cadastrais mudam,
  // mas apenas se um indicador já estiver selecionado.
  watch(
    () => [
      filterStore.selectedUF,
      filterStore.selectedRegiaoSaude,
      filterStore.selectedMunicipio,
      filterStore.selectedSituacao,
      filterStore.selectedMS,
      filterStore.selectedPorte,
      filterStore.selectedGrandeRede,
      filterStore.selectedUnidadePf,
      filterStore.selectedCnpjRaiz,
    ],
    () => {
      if (indicadoresStore.selectedIndicador) {
        fetchForIndicador(indicadoresStore.selectedIndicador);
      }
    },
  );

  return { fetchForIndicador };
}
