/**
 * Centraliza os thresholds e classificações de risco de não-comprovação.
 * Fonte única de verdade para labels, classes CSS, cores e severidades.
 *
 * Níveis:
 *   > CRITICAL (60%) → Crítico   (vermelho escuro)
 *   > HIGH     (20%) → Alto      (vermelho)
 *   > MEDIUM    (5%) → Médio     (amarelo)
 *   ≤ MEDIUM        → Baixo     (verde)
 */
import { RISK_THRESHOLDS, RISK_COLORS, RISK_CSS_CLASSES } from '@/config/riskConfig';

export function useRiskMetrics() {

  const getRiskLabel = (value) => {
    if (value > RISK_THRESHOLDS.CRITICAL) return 'Crítico';
    if (value > RISK_THRESHOLDS.HIGH)     return 'Alto';
    if (value > RISK_THRESHOLDS.MEDIUM)   return 'Médio';
    return 'Baixo';
  };

  /** Severidade PrimeVue: usado em Tags, Badges etc. */
  const getRiskSeverity = (value) => {
    if (value > RISK_THRESHOLDS.CRITICAL) return 'danger';
    if (value > RISK_THRESHOLDS.HIGH)     return 'danger';
    if (value > RISK_THRESHOLDS.MEDIUM)   return 'warn';
    return 'success';
  };

  /** Classe CSS para colorir elementos via stylesheet. */
  const getRiskClass = (value) => {
    if (value > RISK_THRESHOLDS.CRITICAL) return RISK_CSS_CLASSES.CRITICAL;
    if (value > RISK_THRESHOLDS.HIGH)     return RISK_CSS_CLASSES.HIGH;
    if (value > RISK_THRESHOLDS.MEDIUM)   return RISK_CSS_CLASSES.MEDIUM;
    return RISK_CSS_CLASSES.LOW;
  };

  /** Cor hex direta: usado em gráficos ECharts. */
  const getRiskColor = (value) => {
    if (value > RISK_THRESHOLDS.CRITICAL) return RISK_COLORS.CRITICAL;
    if (value > RISK_THRESHOLDS.HIGH)     return RISK_COLORS.HIGH;
    if (value > RISK_THRESHOLDS.MEDIUM)   return RISK_COLORS.MEDIUM;
    return RISK_COLORS.LOW;
  };

  return { getRiskLabel, getRiskSeverity, getRiskClass, getRiskColor };
}
