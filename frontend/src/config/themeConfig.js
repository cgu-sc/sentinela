/**
 * CORES DE SUPERFÍCIE (Backgrounds, Cards, Borders e Textos)
 * Centralizadas para garantir consistência entre CSS e JavaScript (Gráficos).
 */
export const SURFACE_COLORS = {
  azul: {
    light: {
      'bg-color': '#ffffff',
      'bg-gradient': 'linear-gradient(135deg, #ffffff 0%, #f9fafb 100%)',
      'text-color': '#1e293b',
      'text-muted': '#64748b',
      'card-bg': '#f9fafb',
      'sidebar-bg': '#f1f5f9',
      'sidebar-text': '#1e293b',
      'sidebar-border': '#e2e8f0',
      'table-hover': '#f8fafc',
      'table-stripe': '#f9fafb'
    },
    dark: {
      'bg-color': '#0f172a',
      'bg-gradient': 'radial-gradient(circle at 20% 0%, #1e293b 0%, #0f172a 100%)',
      'text-color': '#cbd5e1',
      'text-muted': '#64748b',
      'card-bg': '#1e293b',
      'sidebar-bg': '#0f172a',
      'sidebar-text': '#e2e8f0',
      'sidebar-border': '#334155',
      'table-hover': '#1e293b',
      'table-stripe': '#0f172a'
    }
  },
  carbon: {
    light: {
      'bg-color': '#ffffff',
      'bg-gradient': 'linear-gradient(135deg, #ffffff 0%, #fefcf8 100%)',
      'text-color': '#1e2127',
      'text-muted': '#64748b',
      'card-bg': '#fdf8ec',
      'sidebar-bg': '#ffffff',
      'sidebar-text': '#1e2127',
      'sidebar-border': '#e2e8f0',
      'table-hover': '#f9f4e8',
      'table-stripe': '#fefcf8'
    },
    dark: {
      'bg-color': '#0d1117',
      'bg-gradient': 'radial-gradient(circle at 20% 0%, #1c2533 0%, #0d1117 100%)',
      'text-color': '#e0e5ee',
      'text-muted': '#8b949e',
      'card-bg': '#161b22',
      'sidebar-bg': '#0d1117',
      'sidebar-text': '#e6edf3',
      'sidebar-border': '#30363d',
      'table-hover': '#1f2937',
      'table-stripe': '#131920'
    }
  }
};

/**
 * DEFINIÇÃO DAS PALETAS DE CORES DO SISTEMA
 * Centraliza as cores de destaque e suas variações.
 */
export const THEME_PALETTES = {
  azul: {
    id: 'azul',
    name: 'Azul Padrão',
    description: 'Identidade visual clássica do Sentinela',
    gradient: 'linear-gradient(135deg, #3b82f6, #2563eb)',
    accent: '#3b82f6',
    primary: {
      50: '#eff6ff',
      100: '#dbeafe',
      200: '#bfdbfe',
      300: '#93c5fd',
      400: '#60a5fa',
      500: '#3b82f6',
      600: '#2563eb',
      700: '#1d4ed8',
      800: '#1e40af',
      900: '#1e3a8a',
      color: '#3b82f6',
      text: '#ffffff',
    },
  },
  carbon: {
    id: 'carbon',
    name: 'Carbon Gold',
    description: 'Contraste elevado com tons dourados',
    gradient: 'linear-gradient(135deg, #f59e0b, #d97706)',
    accent: '#d97706',
    primary: {
      50: '#fffbeb',
      100: '#fef3c7',
      200: '#fde68a',
      300: '#fcd34d',
      400: '#fbbf24',
      500: '#f59e0b',
      600: '#d97706',
      700: '#b45309',
      800: '#92400e',
      900: '#78350f',
      color: '#d97706',
      text: '#ffffff',
    },
  },
};

/**
 * Retorna as paletas formatadas para o componente de UI (Dropdown/Seleção)
 */
export const PALETTE_OPTIONS = Object.values(THEME_PALETTES).map(p => ({
  id: p.id,
  name: p.name,
  gradient: p.gradient
}));
