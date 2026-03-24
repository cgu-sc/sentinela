import { computed } from 'vue';

export function useRiskMetrics() {
  /**
   * Retorna a severidade do PrimeVue (success, warn, danger) com base no percentual de não-comprovação.
   * @param {number} value - Percentual de 0 a 100
   */
  const getRiskSeverity = (value) => {
    if (value > 20) return 'danger';
    if (value >= 5) return 'warn';
    return 'success';
  };

  /**
   * Retorna um label amigável para o nível de risco.
   * @param {number} value - Percentual de 0 a 100
   */
  const getRiskLabel = (value) => {
    if (value > 20) return 'Alto';
    if (value >= 5) return 'Médio';
    return 'Baixo';
  };

  const getRiskClass = (value) => {
    if (value > 20) return 'risk-high';
    if (value >= 5) return 'risk-medium';
    return 'risk-low';
  };

  return {
    getRiskSeverity,
    getRiskLabel,
    getRiskClass
  };
}
