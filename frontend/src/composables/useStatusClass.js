/**
 * useStatusClass
 * Composable reutilizável para classificação de badges de status cadastral.
 * Fonte única de verdade — todos os componentes devem importar daqui.
 *
 * Valores possíveis:
 *   situacao_rf : 'Ativa' | 'Suspensa' | 'Baixada' | 'Inapta'
 *   conexao_ms  : 'Ativa' | 'Inativa'
 */
export function useStatusClass() {
  /**
   * Retorna a classe CSS global (components.css) para a Situação RF.
   * @param {string|null} v - valor do campo situacao_rf
   * @returns {string} classe CSS
   */
  function situacaoRfClass(v) {
    if (v === 'Ativa')                     return 'status-success';
    if (v === 'Suspensa')                  return 'status-warn';
    if (v === 'Baixada' || v === 'Inapta') return 'status-danger';
    return 'status-secondary';
  }

  /**
   * Retorna a classe CSS global (components.css) para a Conexão MS.
   * @param {string|null} v - valor do campo conexao_ms
   * @returns {string} classe CSS
   */
  function conexaoMsClass(v) {
    if (v === true || v === 'Ativa')   return 'status-success';
    if (v === false || v === 'Inativa') return 'status-danger';
    return 'status-secondary';
  }

  return { situacaoRfClass, conexaoMsClass };
}
