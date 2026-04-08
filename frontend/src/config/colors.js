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
  red: {
    300: "#fca5a5",
    400: "#f87171",
    500: "#ef4444",
    600: "#dc2626",
    700: "#b91c1c",
    800: "#991b1b",
  },
  orange: { 400: "#fb923c", 500: "#f97316" },
  amber: { 400: "#fbbf24", 500: "#f59e0b", 600: "#d97706" },
  green: { 300: "#86efac", 400: "#4ade80", 500: "#22c55e", 600: "#16a34a" },
  emerald: { 300: "#6ee7b7", 400: "#34d399", 500: "#10b981", 600: "#059669" },
  blue: { 500: "#3b82f6", 600: "#2563eb" },
  indigo: { 500: "#6366f1", 600: "#4f46e5" },
  violet: { 400: "#a78bfa", 500: "#8b5cf6", 600: "#7c3aed" },
  rose: { 500: "#f43f5e", 600: "#e11d48" },
  slate: { 200: "#e2e8f0", 400: "#94a3b8", 500: "#64748b", 800: "#1e293b" },
  zinc: { 100: "#f4f4f5" },
};

// ── Cores semânticas de risco ─────────────────────────────────────────────────
// Usadas em badges, tabelas, CSS (via v-bind) e configurações de limiar.
export const RISK_COLORS = {
  CRITICAL: PALETTE.red[800], // Conservando o Dark/Seriedade
  HIGH: PALETTE.rose[600], // '#e11d48' - O seu novo vermelho Premium
  MEDIUM: PALETTE.amber[500], // '#f59e0b'
  LOW: PALETTE.emerald[500], // '#10b981'
};

// ── Séries de dados — light / dark ────────────────────────────────────────────
// Par regular (verde) / irregular (vermelho) para Volume Financeiro e similares.
export const CHART_SERIES = {
  dark: {
    green: PALETTE.green[500], // '#22c55e'
    greenGrad: PALETTE.green[400], // '#4ade80'
    red: PALETTE.red[500], // '#ef4444'
    redGrad: PALETTE.red[400], // '#f87171'
  },
  light: {
    green: PALETTE.emerald[500], // '#10b981'
    greenGrad: PALETTE.emerald[400], // '#34d399'
    red: PALETTE.rose[600], // '#e11d48' - Premium
    redGrad: PALETTE.rose[500], // '#f43f5e' - Premium
  },
};

// ── Escala de cor do mapa de risco (VisualMap ECharts + PDF) ─────────────────
// Fonte única de verdade. Formato `pieces` do ECharts — breakpoints explícitos.
// `color`: fill do município. `borderColor`: borda ao selecionar.
// Dois temas: `light` usa tons suaves (fundo branco aguenta); `dark` usa tons mais
// saturados/luminosos para furar o fundo escuro.
// Regra de contraste:
//   Light — borda 2 tons mais escura que o fill até 55%; pivot para mais clara em 56%+
//           (fills muito escuros absorvem bordas escuras — precisam de contraste inverso)
//   Dark  — 0–31%: borda escura (mesmo princípio do light)
//            32%+: borda luminosa/brilhante — fill escuro sobre fundo escuro do mapa
//            56%+: orange-glow intencional nos fills críticos (efeito premium de perigo)
export const MAP_VISUAL_SCALE = {
  light: [
    { max: 8, color: "#ffedd5", borderColor: "#fb923c" }, // 0–8%
    { min: 8, max: 12, color: "#fed7aa", borderColor: "#f97316" }, // 8–12%
    { min: 12, max: 16, color: "#fdba74", borderColor: "#ea580c" }, // 12–16%
    { min: 16, max: 20, color: "#fb923c", borderColor: "#c2410c" }, // 16–20%
    { min: 20, max: 25, color: "#fca5a5", borderColor: "#dc2626" }, // 20–25%
    { min: 25, max: 32, color: "#f87171", borderColor: "#b91c1c" }, // 25–32%
    { min: 32, max: 42, color: "#ef4444", borderColor: "#b91c1c" }, // 32–42%
    { min: 42, max: 56, color: "#dc2626", borderColor: "#991b1b" }, // 42–56%
    { min: 56, max: 68, color: "#c81e1e", borderColor: "#ef4444" }, // 56–68%  ← pivot: borda mais clara
    { min: 68, max: 78, color: "#b91c1c", borderColor: "#ef4444" }, // 68–78%
    { min: 78, max: 89, color: "#991b1b", borderColor: "#ef4444" }, // 78–89%
    { min: 89, color: "#7f1d1d", borderColor: "#ef4444" }, // 89–100%
  ],
  dark: [
    { max: 8, color: "#fed7aa", borderColor: "#ea580c" }, // 0–8%
    { min: 8, max: 12, color: "#fdba74", borderColor: "#c2410c" }, // 8–12%
    { min: 12, max: 16, color: "#fb923c", borderColor: "#9a3412" }, // 12–16%
    { min: 16, max: 20, color: "#f97316", borderColor: "#7c2d12" }, // 16–20%
    { min: 20, max: 25, color: "#f87171", borderColor: "#991b1b" }, // 20–25%
    { min: 25, max: 32, color: "#ef4444", borderColor: "#991b1b" }, // 25–32%
    { min: 32, max: 42, color: "#dc2626", borderColor: "#f97316" }, // 32–42%  ← pivot: borda luminosa
    { min: 42, max: 56, color: "#c81e1e", borderColor: "#f97316" }, // 42–56%
    { min: 56, max: 68, color: "#b91c1c", borderColor: "#f97316" }, // 56–68%  ← orange-glow
    { min: 68, max: 78, color: "#991b1b", borderColor: "#f97316" }, // 68–78%
    { min: 78, max: 89, color: "#7f1d1d", borderColor: "#f97316" }, // 78–89%  ← glow mais forte
    { min: 89, color: "#450a0a", borderColor: "#f97316" }, // 89–100%
  ],
};

// ── Constantes de tooltip ECharts ─────────────────────────────────────────────
// Sombra do axisPointer — usada em todos os gráficos ECharts do projeto.
export const CHART_TOOLTIP_SHADOW = "rgba(255, 255, 255, 0.04)";

// ── Acentos do RiskAnalysisChart (barras violeta + linha vermelha) ────────────
export const CHART_RISK_ACCENTS = {
  dark: { bar: PALETTE.violet[500], barGrad: PALETTE.violet[400] }, // '#8b5cf6', '#a78bfa'
  light: { bar: PALETTE.violet[600], barGrad: PALETTE.violet[500] }, // '#7c3aed', '#8b5cf6'
};

// ── Acentos do UfAnalysisChart (índigo + esmeralda + azul + vermelho + laranja) ─
export const CHART_UF_ACCENTS = {
  dark: {
    bar1: PALETTE.indigo[500], // '#6366f1'
    bar1Grad: PALETTE.indigo[500] + "44",
    bar2: PALETTE.emerald[500], // '#10b981'
    bar2Grad: PALETTE.emerald[500] + "44",
    area: PALETTE.blue[500], // '#3b82f6'
    areaGrad: PALETTE.blue[500] + "08",
    barRed: PALETTE.red[500], // '#ef4444'
    barOrange: PALETTE.orange[500], // '#f97316'
  },
  light: {
    bar1: PALETTE.indigo[600], // '#4f46e5'
    bar1Grad: PALETTE.indigo[600] + "22",
    bar2: PALETTE.emerald[600], // '#059669'
    bar2Grad: PALETTE.emerald[600] + "22",
    area: PALETTE.blue[600], // '#2563eb'
    areaGrad: PALETTE.blue[600] + "08",
    barRed: PALETTE.red[500], // '#ef4444' (igual em ambos os modos)
    barOrange: PALETTE.orange[500], // '#f97316' (igual em ambos os modos)
  },
};
