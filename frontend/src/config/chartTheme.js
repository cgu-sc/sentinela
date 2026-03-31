/**
 * Tema central para gráficos ECharts.
 * Todos os tokens de cor são importados de colors.js.
 * Importar este composable em todos os componentes de gráfico.
 */
import { computed } from 'vue';
import { useThemeStore } from '@/stores/theme';
import { CHART_SERIES, CHART_RISK_ACCENTS, CHART_UF_ACCENTS } from './colors.js';

export function useChartTheme() {
  const themeStore = useThemeStore();

  /** Cores de interface do gráfico (texto, grid, tooltip, fundo). */
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

  /** Par regular (verde) / irregular (vermelho) — Volume Financeiro e similares. */
  const chartDataColors = computed(() =>
    themeStore.isDark ? CHART_SERIES.dark : CHART_SERIES.light
  );

  /** Acentos do RiskAnalysisChart (barras violeta). */
  const chartRiskAccents = computed(() =>
    themeStore.isDark ? CHART_RISK_ACCENTS.dark : CHART_RISK_ACCENTS.light
  );

  /** Acentos do UfAnalysisChart (índigo, esmeralda, azul, vermelho, laranja). */
  const chartUFAccents = computed(() =>
    themeStore.isDark ? CHART_UF_ACCENTS.dark : CHART_UF_ACCENTS.light
  );

  /** Configuração base compartilhada por todos os gráficos ECharts do projeto. */
  const baseChartConfig = computed(() => ({
    backgroundColor: chartTheme.value.bg,
    animation: true,
    animationDuration: 900,
    animationEasing: 'cubicOut',
    textStyle: { fontFamily: 'Inter, sans-serif' },
  }));

  return { chartTheme, chartDataColors, chartRiskAccents, chartUFAccents, baseChartConfig };
}
