/**
 * Centraliza os thresholds e classificações de risco de não-comprovação.
 * Fonte única de verdade para labels, classes CSS, cores e severidades.
 *
 * Níveis (Novos Thresholds):
 *   > 60%  → Crítico   (maroon / vermelho escuro)
 *   > 20%  → Alto      (danger / vermelho)
 *   > 5%   → Médio     (warn / amarelo)
 *   <= 5%  → Baixo     (success / verde)
 */
export function useRiskMetrics() {

  const getRiskLabel = (value) => {
    if (value > 60) return 'Crítico';
    if (value > 20) return 'Alto';
    if (value > 5)  return 'Médio';
    return 'Baixo';
  };

  /** Severidade PrimeVue: usado em Tags, Badges etc. */
  const getRiskSeverity = (value) => {
    if (value > 60) return 'danger'; // Será customizado via CSS .risk-critical
    if (value > 20) return 'danger';
    if (value > 5)  return 'warn';
    return 'success';
  };

  /** Classe CSS para colorir elementos via stylesheet. */
  const getRiskClass = (value) => {
    if (value > 60) return 'risk-critical';
    if (value > 20) return 'risk-high';
    if (value > 5)  return 'risk-medium';
    return 'risk-low';
  };

  /** Cor hex direta: usado em gráficos ECharts/ApexCharts. */
  const getRiskColor = (value) => {
    if (value > 60) return '#991b1b'; // Maroon
    if (value > 20) return '#ef4444'; // Red
    if (value > 5)  return '#f59e0b'; // Gold/Yellow
    return '#10b981'; // Green
  };

  return { getRiskLabel, getRiskSeverity, getRiskClass, getRiskColor };
}
