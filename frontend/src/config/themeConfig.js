/**
 * Configuração de Temas e Paletas do Projeto Sentinela.
 * Define as cores primárias, contrastes e metadados para o seletor de temas.
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
