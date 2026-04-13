/**
 * Tema central para gráficos ECharts.
 * Todos os tokens de cor são importados de colors.js.
 * Importar este composable em todos os componentes de gráfico.
 */
import { computed } from 'vue';
import { useThemeStore } from '@/stores/theme';
import { SURFACE_COLORS } from '@/config/themeConfig';
import { CHART_SERIES, CHART_RISK_ACCENTS, CHART_UF_ACCENTS } from './colors.js';

export function useChartTheme() {
  const themeStore = useThemeStore();

  /** Cores de interface do gráfico (texto, grid, tooltip, fundo). */
  const chartTheme = computed(() => {
    const tokens = themeStore.tokens;
    const currentThemeKey = ['carbon', 'azul_dark'].includes(themeStore.currentPalette) ? themeStore.currentPalette : 'azul';
    const darkTooltipBg = SURFACE_COLORS[currentThemeKey].dark['card-bg'];
    const darkTooltipBorder = SURFACE_COLORS[currentThemeKey].dark['card-border'];

    // Menos transparência no modo Light para evitar "lavagem" da cor escura contra fundo branco
    const opacityHex = themeStore.isDark ? 'cc' : 'e6'; // 80% dark, 90% light

    return {
      text:        tokens.textColor,
      muted:       tokens.mutedColor,
      grid:        themeStore.isDark ? '#ffffff0f' : '#0000000d',
      bg:          'transparent',
      tooltip:     darkTooltipBg + opacityHex, // Opacidade inteligente acoplada ao hex
      tooltipText: '#ffffff',
      tooltipBorder: darkTooltipBorder,
      border:      tokens.borderColor,
      axisShadow:  themeStore.isDark ? 'rgba(255, 255, 255, 0.06)' : 'rgba(0, 0, 0, 0.06)',
    };
  });

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
