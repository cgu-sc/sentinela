/**
 * CORES DE SUPERFÍCIE (Backgrounds, Cards, Borders, Textos e Risco)
 * Centralizadas para garantir consistência entre CSS e JavaScript (Gráficos).
 * As cores de risco variam por modo (light/dark) para garantir contraste adequado.
 * Fonte de verdade: colors.js (PALETTE) — os hex abaixo devem referenciar aquela paleta.
 */
export const SURFACE_COLORS = {
  azul: {
    light: {
      "bg-color": "#f8fafc",
      "bg-gradient": "linear-gradient(to bottom, #f8fafc 0%, #f1f5f9 100%)",
      "text-color": "#1e293b",
      "text-muted": "#64748b",
      "card-bg": "#ffffff",
      "sidebar-bg": "#212120",
      "sidebar-text": "#A1A1AA",
      "sidebar-border": "rgba(255, 255, 255, 0.1)",
      "sidebar-input-bg": "rgba(255, 255, 255, 0.06)",
      "navbar-bg": "#f8fafc",
      "navbar-text": "#1e293b",
      "navbar-border": "#e2e8f0",
      "navbar-text-muted": "#64748b",
      "navbar-active-bg": "rgba(37, 99, 235, 0.22)",
      "navbar-glass-opacity": "0.6",
      "establishment-header-bg": "#f1f5f9",
      "establishment-header-text": "#1e293b",
      "establishment-header-border": "#e2e8f0",
      "tabs-bg": "#f1f5f9",
      "tabs-border": "#e2e8f0",
      "card-border": "#e2e8f0",
      "table-footer-bg": "#f1f5f9",
      "table-hover": "rgba(37, 99, 235, 0.06)",
      "table-stripe": "#f8fafc",
      // Risco — tons saturados, legíveis sobre fundo claro
      "risk-low": "#faa716", // original amber style
      "risk-medium": "#faa716", // amber-500
      "risk-high": "#e11d48", // rose-600
      "risk-critical": "#991b1b", // red-800
      "status-success": "#10b981", // emerald-500
      "risk-indicator-normal": "#10b981", // emerald-500 (mesmo tom do gráfico)
      "risk-indicator-warning": "#d97706", // amber-600
      "risk-indicator-critical": "#be123c", // rose-700
      // Escala Térmica de Óbito (Iniciando em Laranja Suave)
      "risk-death-0-7d": "#fed7aa",
      "risk-death-8-15d": "#fdba74",
      "risk-death-16-30d": "#fb923c",
      "risk-death-31-60d": "#f97316",
      "risk-death-61-120d": "#ea580c",
      "risk-death-121-240d": "#dc2626",
      "risk-death-241-1y": "#b91c1c",
      "risk-death-1-2y": "#991b1b",
      "risk-death-2-3y": "#7f1d1d",
      "risk-death-over-3y": "#7f1d1d",
    },
    dark: {
      "bg-color": "#0d1117",
      "bg-gradient":
        "radial-gradient(circle at 20% 0%, #1c2533 0%, #0d1117 100%)",
      "text-color": "#e0e5ee",
      "text-muted": "#8b949e",
      "card-bg": "#161b22",
      "sidebar-bg": "#0d1117",
      "sidebar-text": "#9ca3af",
      "sidebar-border": "rgba(255, 255, 255, 0.1)",
      "sidebar-input-bg": "rgba(255, 255, 255, 0.05)",
      "navbar-bg": "#0d1117",
      "navbar-text": "#e0e5ee",
      "navbar-border": "#30363d",
      "navbar-text-muted": "#8b949e",
      "navbar-active-bg": "rgba(59, 130, 246, 0.15)",
      "navbar-glass-opacity": "0.7",
      "establishment-header-bg": "#161b22",
      "establishment-header-text": "#e0e5ee",
      "establishment-header-border": "#30363d",
      "tabs-bg": "#161b22",
      "tabs-border": "rgba(255, 255, 255, 0.1)",
      "card-border": "#30363d",
      "table-footer-bg": "#1c2128",
      "table-hover": "#1f2937",
      "table-stripe": "#131920",
      // Risco — tons luminosos, para furar o fundo escuro
      "risk-low": "#fbbf24", // original amber style
      "risk-medium": "#fbbf24", // amber-400
      "risk-high": "#f87171", // red-400
      "risk-critical": "#fca5a5", // red-300 — mais claro que HIGH para se destacar
      "status-success": "#34d399", // emerald-400
      "risk-indicator-normal": "#22c55e", // green-500 (mais brilhante para dark mode)
      "risk-indicator-warning": "#fbbf24", // amber-400
      "risk-indicator-critical": "#fb7185", // rose-400
      // Escala Térmica de Óbito (Iniciando em Laranja Suave - Modo Escuro)
      "risk-death-0-7d": "#fdba74",
      "risk-death-8-15d": "#fb923c",
      "risk-death-16-30d": "#f97316",
      "risk-death-31-60d": "#f87171",
      "risk-death-61-120d": "#ef4444",
      "risk-death-121-240d": "#dc2626",
      "risk-death-241-1y": "#b91c1c",
      "risk-death-1-2y": "#991b1b",
      "risk-death-2-3y": "#7f1d1d",
      "risk-death-over-3y": "#7f1d1d",
    },
  },
  carbon: {
    light: {
      "bg-color": "#ffffff",
      "bg-gradient": "linear-gradient(to bottom, #ffffff 0%, #f5f5f4 100%)",
      "text-color": "#1c1917",
      "text-muted": "#78716c",
      "card-bg": "#ffffff",
      "sidebar-bg": "#212120",
      "sidebar-text": "#A1A1AA",
      "sidebar-border": "rgba(255, 255, 255, 0.1)",
      "sidebar-input-bg": "rgba(255, 255, 255, 0.06)",
      "navbar-bg": "#fafaf9",
      "navbar-text": "#1c1917",
      "navbar-border": "#e7e5e4",
      "navbar-text-muted": "#78716c",
      "navbar-active-bg": "rgba(245, 158, 11, 0.30)",
      "navbar-glass-opacity": "0.6",
      "establishment-header-bg": "#fafaf9",
      "establishment-header-text": "#1c1917",
      "establishment-header-border": "#e7e5e4",
      "tabs-bg": "#fafaf9",
      "tabs-border": "#e7e5e4",
      "card-border": "#e7e5e4",
      "table-footer-bg": "#f5f5f4",
      "table-hover": "rgba(245, 158, 11, 0.08)",
      "table-stripe": "#fafaf9",
      // Risco — escala quente: amber claro → orange → rose → red
      "risk-low": "#fbbf24", // amber-400 — tom suave, menos intenso que o médio
      "risk-medium": "#f97316", // orange-500 — intermediário entre amber e vermelho
      "risk-high": "#e11d48", // rose-600
      "risk-critical": "#991b1b", // red-800
      "status-success": "#10b981", // emerald-500
      "risk-indicator-normal": "#10b981",
      "risk-indicator-warning": "#d97706",
      "risk-indicator-critical": "#be123c",
      // Escala Térmica de Óbito (Iniciando em Laranja Suave)
      "risk-death-0-7d": "#fed7aa",
      "risk-death-8-15d": "#fdba74",
      "risk-death-16-30d": "#fb923c",
      "risk-death-31-60d": "#f97316",
      "risk-death-61-120d": "#ea580c",
      "risk-death-121-240d": "#dc2626",
      "risk-death-241-1y": "#b91c1c",
      "risk-death-1-2y": "#991b1b",
      "risk-death-2-3y": "#7f1d1d",
      "risk-death-over-3y": "#7f1d1d",
    },
    dark: {
      "bg-color": "#0d1117",
      "bg-gradient":
        "radial-gradient(circle at 20% 0%, #1c2533 0%, #0d1117 100%)",
      "text-color": "#e0e5ee",
      "text-muted": "#8b949e",
      "card-bg": "#161b22",
      "sidebar-bg": "#161b22",
      "sidebar-text": "#e6edf3",
      "sidebar-border": "rgba(255, 255, 255, 0.08)",
      "sidebar-input-bg": "rgba(255, 255, 255, 0.05)",
      "navbar-bg": "#161b22",
      "navbar-text": "#e0e5ee",
      "navbar-border": "#30363d",
      "navbar-text-muted": "#8b949e",
      "navbar-active-bg": "rgba(217, 119, 6, 0.15)",
      "navbar-glass-opacity": "0.75",
      "establishment-header-bg": "#161b22",
      "establishment-header-text": "#e0e5ee",
      "establishment-header-border": "#30363d",
      "tabs-bg": "#161b22",
      "tabs-border": "rgba(255, 255, 255, 0.08)",
      "card-border": "#30363d",
      "table-footer-bg": "#1c2128",
      "table-hover": "#1f2937",
      "table-stripe": "#131920",
      // Risco — escala quente: amber claro → orange → rose → red
      "risk-low": "#fcd34d", // amber-300 — tom suave e legível no dark
      "risk-medium": "#fb923c", // orange-400 — intermediário entre amber e vermelho
      "risk-high": "#f87171", // red-400
      "risk-critical": "#fca5a5", // red-300
      "status-success": "#34d399", // emerald-400
      "risk-indicator-normal": "#22c55e",
      "risk-indicator-warning": "#fbbf24",
      "risk-indicator-critical": "#fb7185",
      // Escala Térmica de Óbito (Iniciando em Laranja Suave - Modo Escuro)
      "risk-death-0-7d": "#fdba74",
      "risk-death-8-15d": "#fb923c",
      "risk-death-16-30d": "#f97316",
      "risk-death-31-60d": "#f87171",
      "risk-death-61-120d": "#ef4444",
      "risk-death-121-240d": "#dc2626",
      "risk-death-241-1y": "#b91c1c",
      "risk-death-1-2y": "#991b1b",
      "risk-death-2-3y": "#7f1d1d",
      "risk-death-over-3y": "#7f1d1d",
    },
  },
};

/**
 * DEFINIÇÃO DAS PALETAS DE CORES DO SISTEMA
 * Centraliza as cores de destaque e suas variações.
 */
export const THEME_PALETTES = {
  azul: {
    id: "azul",
    name: "Azul Padrão",
    description: "Identidade visual clássica do Sentinela",
    gradient: "linear-gradient(135deg, #3b82f6, #2563eb)",
    accent: "#3b82f6",
    primary: {
      50: "#eff6ff",
      100: "#dbeafe",
      200: "#bfdbfe",
      300: "#93c5fd",
      400: "#60a5fa",
      500: "#3b82f6",
      600: "#2563eb",
      700: "#1d4ed8",
      800: "#1e40af",
      900: "#1e3a8a",
      color: "#3b82f6",
      text: "#ffffff",
    },
  },
  carbon: {
    id: "carbon",
    name: "Carbon Gold",
    description: "Contraste elevado com tons dourados",
    gradient: "linear-gradient(135deg, #f59e0b, #d97706)",
    accent: "#d97706",
    primary: {
      50: "#fffbeb",
      100: "#fef3c7",
      200: "#fde68a",
      300: "#fcd34d",
      400: "#fbbf24",
      500: "#f59e0b",
      600: "#d97706",
      700: "#b45309",
      800: "#92400e",
      900: "#78350f",
      color: "#d97706",
      text: "#ffffff",
    },
  },
};

/**
 * Retorna as paletas formatadas para o componente de UI (Dropdown/Seleção)
 */
export const PALETTE_OPTIONS = Object.values(THEME_PALETTES).map((p) => ({
  id: p.id,
  name: p.name,
  gradient: p.gradient,
}));
