/**
 * CORES DE SUPERFÍCIE (Backgrounds, Cards, Borders e Textos)
 * Centralizadas para garantir consistência entre CSS e JavaScript (Gráficos).
 */
export const SURFACE_COLORS = {
  azul: {
    light: {
      "bg-color": "#ffffff",
      "bg-gradient": "linear-gradient(to bottom, #ffffff 0%, #f1f5f9 100%)",
      "text-color": "#1e293b",
      "text-muted": "#64748b",
      "card-bg": "#f9fafb",
      "sidebar-bg": "#f3f4f6",
      "sidebar-text": "#1e293b",
      "sidebar-border": "#e2e8f0",
      "sidebar-input-bg": "#ffffff",
      "navbar-bg": "#f9fafb",
      "navbar-text": "#1e293b",
      "navbar-border": "#e2e8f0",
      "navbar-text-muted": "#64748b",
      "navbar-active-bg": "rgba(59, 130, 246, 0.15)",
      "navbar-glass-opacity": "0.6",
      "establishment-header-bg": "#ffffff",
      "establishment-header-text": "#1e293b",
      "establishment-header-border": "#e2e8f0",
      "table-hover": "#eef6ff",
      "table-stripe": "#f8fafc",
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
      "table-hover": "#1f2937",
      "table-stripe": "#131920",
    },
  },
  carbon: {
    light: {
      "bg-color": "#F4F3EF",
      "bg-gradient": "linear-gradient(to bottom, #ffffff 0%, #f1f5f9 100%)",
      "text-color": "#1e2127",
      "text-muted": "#64748b",
      "card-bg": "#fdfdfc",
      "sidebar-bg": "#212120",
      "sidebar-text": "#A1A1AA",
      "sidebar-border": "rgba(255, 255, 255, 0.1)",
      "sidebar-input-bg": "rgba(255, 255, 255, 0.06)",
      "navbar-bg": "#F4F3EF",
      "navbar-text": "#1e2127",
      "navbar-border": "#f1f5f9",
      "navbar-text-muted": "#64748b",
      "navbar-active-bg": "rgba(245, 158, 11, 0.12)",
      "navbar-glass-opacity": "0.6",
      "establishment-header-bg": "#fdfdfc",
      "establishment-header-text": "#1e2127",
      "establishment-header-border": "#D1CEC3",
      "table-hover": "#f1f5f9",
      "table-stripe": "#f8fafc",
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
      "table-hover": "#1f2937",
      "table-stripe": "#131920",
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
