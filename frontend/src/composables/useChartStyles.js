import { computed } from 'vue';
import { PALETTE } from '@/config/colors.js';

export function useChartStyles(themeStore) {
  /**
   * Configurações base compartilhadas por todos os gráficos do Sentinela.
   * Garante consistência de fontes, cores de texto, grades e tooltips.
   */
  const chartBaseOptions = computed(() => ({
    chart: {
      toolbar: { show: false },
      fontFamily: 'Inter, system-ui, -apple-system, sans-serif',
      animations: {
        enabled: true,
        easing: 'easeinout',
        speed: 800
      },
      foreColor: themeStore.isDark ? PALETTE.slate[400]  : PALETTE.slate[500],
    },
    grid: {
      borderColor: themeStore.isDark ? '#27272a' : '#f1f5f9',
      strokeDashArray: 4,
      padding: { top: 20, right: 20, bottom: 20, left: 20 }
    },
    tooltip: {
      theme: themeStore.isDark ? 'dark' : 'light',
      shared: true,
      intersect: false,
      style: { fontSize: '12px', fontFamily: 'Inter, sans-serif' }
    },
    legend: {
      position: 'top',
      horizontalAlign: 'center',
      labels: {
        colors: themeStore.isDark ? PALETTE.zinc[100] : PALETTE.slate[800],
      },
      markers: { radius: 12 }
    },
    xaxis: {
      axisBorder: { show: false },
      axisTicks:  { show: false },
      labels: { style: { fontSize: '11px', fontWeight: 500 } }
    },
    yaxis: {
      labels: { style: { fontSize: '11px', fontWeight: 500 } }
    }
  }));

  /**
   * Paleta de cores oficial do Sentinela para séries de dados.
   * Importada de colors.js — fonte única de verdade.
   */
  const chartColors = computed(() => themeStore.isDark
    ? {
        primary:   PALETTE.indigo[500],   // '#6366f1'
        secondary: PALETTE.blue[500],     // '#3b82f6'
        warning:   PALETTE.amber[500],    // '#f59e0b'
        danger:    PALETTE.red[500],      // '#ef4444'
        success:   PALETTE.emerald[500],  // '#10b981'
        info:      '#0ea5e9',
        muted:     PALETTE.slate[400],    // '#94a3b8'
      }
    : {
        primary:   PALETTE.indigo[600],   // '#4f46e5'
        secondary: PALETTE.blue[600],     // '#2563eb'
        warning:   PALETTE.amber[600],    // '#d97706'
        danger:    PALETTE.red[600],      // '#dc2626'
        success:   PALETTE.emerald[600],  // '#059669'
        info:      '#0284c7',
        muted:     PALETTE.slate[500],    // '#64748b'
      }
  );

  return { chartBaseOptions, chartColors };
}
