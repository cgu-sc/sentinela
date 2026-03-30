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

  /** Cores de dados para séries de gráficos (verde=regular, vermelho=irregular). */
  const chartDataColors = computed(() => themeStore.isDark
    ? {
        green:     '#4ade80',
        greenGrad: '#86efac',
        red:       '#f87171',
        redGrad:   '#fca5a5',
      }
    : {
        green:     '#22c55e',
        greenGrad: '#4ade80',
        red:       '#ef4444',
        redGrad:   '#f87171',
      }
  );

  /** Configuração base compartilhada por todos os gráficos ECharts do projeto. */
  const baseChartConfig = computed(() => ({
    backgroundColor: chartTheme.value.bg,
    animation: true,
    animationDuration: 900,
    animationEasing: 'cubicOut',
    textStyle: { fontFamily: 'Inter, sans-serif' },
  }));

  return { chartTheme, chartDataColors, baseChartConfig };
}
