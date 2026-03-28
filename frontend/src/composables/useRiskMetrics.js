/**
 * Centraliza os thresholds e classificações de risco de não-comprovação.
 * Fonte única de verdade para labels, classes CSS, cores e severidades.
 *
 * Níveis:
 *   > 20%  → Alto      (danger / vermelho)
 *   > 10%  → Moderado  (laranja)
 *   > 5%   → Médio     (amarelo)
 *   <= 5%  → Baixo     (success / verde)
 */
export function useRiskMetrics() {

  const getRiskLabel = (value) => {
    if (value > 20) return 'Alto';
    if (value > 10) return 'Moderado';
    if (value > 5)  return 'Médio';
    return 'Baixo';
  };

  /** Severidade PrimeVue: usado em Tags, Badges etc. */
  const getRiskSeverity = (value) => {
    if (value > 20) return 'danger';
    if (value > 10) return 'warning';
    if (value > 5)  return 'warn';
    return 'success';
  };

  /** Classe CSS para colorir elementos via stylesheet. */
  const getRiskClass = (value) => {
    if (value > 20) return 'risk-high';
    if (value > 10) return 'risk-moderate';
    if (value > 5)  return 'risk-medium';
    return 'risk-low';
  };

  /** Cor hex direta: usado em gráficos ECharts/ApexCharts. */
  const getRiskColor = (value) => {
    if (value > 20) return '#ef4444';
    if (value > 10) return '#f97316';
    if (value > 5)  return '#f59e0b';
    return '#10b981';
  };

  return { getRiskLabel, getRiskSeverity, getRiskClass, getRiskColor };
}
