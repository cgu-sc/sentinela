/**
 * Thresholds de classificação de risco de não-comprovação.
 * Fonte única de verdade — alterar aqui reflete em todos os gráficos,
 * tabelas e badges do sistema sem necessidade de tocar em outros arquivos.
 *
 * Regra:
 *   > CRITICAL  → Crítico  (vermelho escuro)
 *   > HIGH      → Alto     (vermelho)
 *   > MEDIUM    → Médio    (amarelo)
 *   ≤ MEDIUM    → Baixo    (verde)
 */
export const RISK_THRESHOLDS = {
  CRITICAL: 60,
  HIGH:     20,
  MEDIUM:    5,
};

/** Paleta de cores hex associada a cada nível (para uso em ECharts). */
export const RISK_COLORS = {
  CRITICAL: '#991b1b',
  HIGH:     '#ef4444',
  MEDIUM:   '#f59e0b',
  LOW:      '#10b981',
};

/** Classes CSS associadas a cada nível (para uso em Tags/Badges do PrimeVue). */
export const RISK_CSS_CLASSES = {
  CRITICAL: 'risk-critical',
  HIGH:     'risk-high',
  MEDIUM:   'risk-medium',
  LOW:      'risk-low',
};
