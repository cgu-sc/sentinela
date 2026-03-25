import { computed } from 'vue';

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
      foreColor: themeStore.isDark ? '#94a3b8' : '#64748b'
    },
    grid: {
      borderColor: themeStore.isDark ? '#27272a' : '#f1f5f9',
      strokeDashArray: 4,
      padding: {
        top: 20,
        right: 20,
        bottom: 20,
        left: 20
      }
    },
    tooltip: {
      theme: themeStore.isDark ? 'dark' : 'light',
      shared: true,
      intersect: false,
      style: {
        fontSize: '12px',
        fontFamily: 'Inter, sans-serif'
      }
    },
    legend: {
      position: 'top',
      horizontalAlign: 'center',
      labels: {
        colors: themeStore.isDark ? '#f4f4f5' : '#1e293b'
      },
      markers: {
        radius: 12
      }
    },
    xaxis: {
      axisBorder: { show: false },
      axisTicks: { show: false },
      labels: {
        style: {
          fontSize: '11px',
          fontWeight: 500
        }
      }
    },
    yaxis: {
      labels: {
        style: {
          fontSize: '11px',
          fontWeight: 500
        }
      }
    }
  }));

  /**
   * Paleta de cores oficial do Sentinela para séries de dados.
   * Dinamizada para garantir ótimo contraste tanto no claro quanto no escuro.
   */
  const chartColors = computed(() => {
    if (themeStore.isDark) {
      return {
        primary: '#6366f1',  // Indigo 500 (Brilha no claro escuro)
        secondary: '#3b82f6', // Blue 500
        warning: '#f59e0b',  // Amber 500
        danger: '#ef4444',   // Red 500
        success: '#10b981',  // Emerald 500
        info: '#0ea5e9',
        muted: '#94a3b8'
      };
    } else {
      return {
        primary: '#4f46e5',  // Indigo 600 (Melhor contraste no branco)
        secondary: '#2563eb', // Blue 600
        warning: '#d97706',  // Amber 600
        danger: '#dc2626',   // Red 600
        success: '#059669',  // Emerald 600
        info: '#0284c7',
        muted: '#64748b'
      };
    }
  });

  return {
    chartBaseOptions,
    chartColors
  };
}
