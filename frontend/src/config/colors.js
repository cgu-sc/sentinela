/**
 * Paleta de cores do sistema Sentinela.
 * Fonte única de verdade — todos os outros módulos importam daqui.
 * Valores baseados em Tailwind CSS v3.
 *
 * NUNCA defina cores hex em outros arquivos de config ou componentes.
 * Adicione aqui e exporte o token correto.
 */

// ── Paleta base ───────────────────────────────────────────────────────────────
// Tokens nomeados por família + escala. Apenas os tons em uso no sistema.
export const PALETTE = {
  red:     { 300: '#fca5a5', 400: '#f87171', 500: '#ef4444', 600: '#dc2626', 700: '#b91c1c', 800: '#991b1b' },
  orange:  { 400: '#fb923c', 500: '#f97316' },
  amber:   { 400: '#fbbf24', 500: '#f59e0b', 600: '#d97706' },
  green:   { 300: '#86efac', 400: '#4ade80', 500: '#22c55e' },
  emerald: { 500: '#10b981', 600: '#059669' },
  blue:    { 500: '#3b82f6', 600: '#2563eb' },
  indigo:  { 500: '#6366f1', 600: '#4f46e5' },
  violet:  { 400: '#a78bfa', 500: '#8b5cf6', 600: '#7c3aed' },
  slate:   { 200: '#e2e8f0', 400: '#94a3b8', 500: '#64748b', 800: '#1e293b' },
  zinc:    { 100: '#f4f4f5' },
};

// ── Cores semânticas de risco ─────────────────────────────────────────────────
// Usadas em badges, tabelas, CSS (via v-bind) e configurações de limiar.
export const RISK_COLORS = {
  CRITICAL: PALETTE.red[800],      // '#991b1b'
  HIGH:     PALETTE.red[500],      // '#ef4444'
  MEDIUM:   PALETTE.amber[500],    // '#f59e0b'
  LOW:      PALETTE.emerald[500],  // '#10b981'
};

// ── Séries de dados — light / dark ────────────────────────────────────────────
// Par regular (verde) / irregular (vermelho) para Volume Financeiro e similares.
export const CHART_SERIES = {
  dark: {
    green:     PALETTE.green[500],   // '#22c55e'
    greenGrad: PALETTE.green[400],   // '#4ade80'
    red:       PALETTE.red[500],     // '#ef4444'
    redGrad:   PALETTE.red[400],     // '#f87171'
  },
  light: {
    green:     PALETTE.green[600],   // '#16a34a'
    greenGrad: PALETTE.green[500],   // '#22c55e'
    red:       PALETTE.red[600],     // '#dc2626'
    redGrad:   PALETTE.red[500],     // '#ef4444'
  },
};

// ── Constantes de tooltip ECharts ─────────────────────────────────────────────
// Sombra do axisPointer — usada em todos os gráficos ECharts do projeto.
export const CHART_TOOLTIP_SHADOW = 'rgba(255, 255, 255, 0.04)';

// ── Acentos do RiskAnalysisChart (barras violeta + linha vermelha) ────────────
export const CHART_RISK_ACCENTS = {
  dark:  { bar: PALETTE.violet[500], barGrad: PALETTE.violet[400] },  // '#8b5cf6', '#a78bfa'
  light: { bar: PALETTE.violet[600], barGrad: PALETTE.violet[500] },  // '#7c3aed', '#8b5cf6'
};

// ── Acentos do UfAnalysisChart (índigo + esmeralda + azul + vermelho + laranja) ─
export const CHART_UF_ACCENTS = {
  dark: {
    bar1:      PALETTE.indigo[500],         // '#6366f1'
    bar1Grad:  PALETTE.indigo[500] + '44',
    bar2:      PALETTE.emerald[500],        // '#10b981'
    bar2Grad:  PALETTE.emerald[500] + '44',
    area:      PALETTE.blue[500],           // '#3b82f6'
    areaGrad:  PALETTE.blue[500] + '08',
    barRed:    PALETTE.red[500],            // '#ef4444'
    barOrange: PALETTE.orange[500],         // '#f97316'
  },
  light: {
    bar1:      PALETTE.indigo[600],         // '#4f46e5'
    bar1Grad:  PALETTE.indigo[600] + '22',
    bar2:      PALETTE.emerald[600],        // '#059669'
    bar2Grad:  PALETTE.emerald[600] + '22',
    area:      PALETTE.blue[600],           // '#2563eb'
    areaGrad:  PALETTE.blue[600] + '08',
    barRed:    PALETTE.red[500],            // '#ef4444' (igual em ambos os modos)
    barOrange: PALETTE.orange[500],         // '#f97316' (igual em ambos os modos)
  },
};
