/**
 * Tema central para gráficos ECharts.
 * Fonte única de verdade para cores, fontes e estilos visuais.
 * Importar em todos os componentes de gráfico em vez de duplicar as cores.
 */
import { computed } from 'vue';
import { useThemeStore } from '@/stores/theme';

export function useChartTheme() {
  const themeStore = useThemeStore();

  const chartTheme = computed(() => themeStore.isDark
    ? {
        text:    '#e2e8f0',
        muted:   '#94a3b8',
        grid:    '#ffffff0f',
        bg:      'transparent',
        tooltip: '#1e293b',
        border:  '#334155',
      }
    : {
        text:    '#1e293b',
        muted:   '#64748b',
        grid:    '#0000000d',
        bg:      'transparent',
        tooltip: '#ffffff',
        border:  '#e2e8f0',
      }
  );

  return { chartTheme };
}
