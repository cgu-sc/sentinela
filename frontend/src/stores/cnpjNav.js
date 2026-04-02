import { defineStore } from 'pinia';
import { ref } from 'vue';

/**
 * Store de navegação do Detalhe do CNPJ.
 *
 * Responsabilidades:
 *  - Controlar a aba ativa do TabView (activeTabIndex)
 *  - Comunicar um município a ser pré-selecionado na aba Regional (pendingMunicipio)
 */
export const useCnpjNavStore = defineStore('cnpjNav', () => {
  // Índice da aba ativa (espelha TAB_INDEX do CnpjDetailView)
  const activeTabIndex = ref(1); // começa na Evolução Financeira

  // Município a ser pré-selecionado ao abrir a aba de Região de Saúde.
  // Consumido e limpo pelo CnpjTabRegional.
  const pendingMunicipio = ref(null);

  /**
   * Navega para a aba de Região de Saúde e agenda a seleção de um município.
   * @param {string|null} municipioNome - Nome do município ou null para ver todos.
   * @param {number} tabIndex           - Índice da aba Regional (default 5).
   */
  function navigateToRegiao(municipioNome = null, tabIndex = 5) {
    // Se for null, usamos um marcador interno para forçar a limpeza do filtro no destino
    pendingMunicipio.value = municipioNome === null ? '__RESET__' : municipioNome;
    activeTabIndex.value = tabIndex;
  }

  /** Consome e limpa o município pendente após uso. */
  function consumePendingMunicipio() {
    const nome = pendingMunicipio.value;
    pendingMunicipio.value = null;
    return nome;
  }

  /** Reseta o estado ao trocar de CNPJ. */
  function reset(defaultTab = 1) {
    activeTabIndex.value = defaultTab;
    pendingMunicipio.value = null;
  }

  return {
    activeTabIndex,
    pendingMunicipio,
    navigateToRegiao,
    consumePendingMunicipio,
    reset,
  };
});
