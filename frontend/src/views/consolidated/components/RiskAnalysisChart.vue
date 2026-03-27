<script setup>
import { computed, ref, watch } from 'vue';
import { useAnalyticsStore } from '@/stores/analytics';
import { useThemeStore } from '@/stores/theme';
import { useFormatting } from '@/composables/useFormatting';
import { useChartStyles } from '@/composables/useChartStyles';
import { storeToRefs } from 'pinia';
import Button from 'primevue/button';

const analyticsStore = useAnalyticsStore();
const themeStore = useThemeStore();
const { fatorRisco, fatorRiscoLoading } = storeToRefs(analyticsStore);
const { formatBRL, formatNumber, formatCurrencyFull, formatNumberFull } = useFormatting();
const { chartBaseOptions, chartColors } = useChartStyles(themeStore);

// Re-render key para o ApexCharts (necessário para o tema Dark/Light)
const chartRenderKey = ref(0);
watch(fatorRisco, () => { chartRenderKey.value++; });
const chartKey = computed(() => `${themeStore.isDark ? 'dark' : 'light'}-${chartRenderKey.value}`);

const chartSeries = computed(() => [
    {
        name: 'Qtd Estab por Faixa',
        type: 'column',
        data: fatorRisco.value.map(b => b.qtd)
    },
    {
        name: 'Valor Sem Comprovação',
        type: 'area',
        data: fatorRisco.value.map(b => b.valor_raw)
    }
]);

const chartOptions = computed(() => ({
    ...chartBaseOptions.value,
    chart: {
        ...chartBaseOptions.value.chart,
        zoom: { enabled: false }
    },
    legend: {
        ...chartBaseOptions.value.legend,
        labels: { colors: chartColors.value.muted },
        fontSize: '12px',
        fontWeight: 600,
    },
    colors: [chartColors.value.primary, chartColors.value.danger],
    stroke: {
        width: [0, 3],
        curve: 'smooth',
        lineCap: 'round'
    },
    plotOptions: {
        bar: {
            columnWidth: '45%',
            borderRadius: 6,
            borderRadiusApplication: 'around',
        }
    },
    fill: {
        type: 'gradient',
        gradient: {
            shade: 'dark',
            type: "vertical",
            shadeIntensity: 0.5,
            gradientToColors: [chartColors.value.secondary, undefined], 
            inverseColors: false,
            opacityFrom: [0.9, 0.6],
            opacityTo: [0.8, 0.1],
            stops: [0, 100, 100]
        }
    },
    labels: fatorRisco.value.map(b => b.faixa),
    xaxis: {
        ...chartBaseOptions.value.xaxis,
        type: 'category',
        title: {
            text: 'Faixa de Percentual de Não Comprovação',
            style: { fontSize: '12px', fontWeight: 600, color: chartColors.value.muted }
        }
    },
    yaxis: [
        {
            ...chartBaseOptions.value.yaxis,
            title: { text: 'Qtd Estab', style: { color: chartColors.value.primary, fontWeight: 700, fontSize: '13px' } },
            labels: {
                ...chartBaseOptions.value.yaxis?.labels,
                formatter: (val) => formatNumber(val)
            }
        },
        {
            ...chartBaseOptions.value.yaxis,
            opposite: true,
            title: { text: 'Valor Sem Comp', style: { color: chartColors.value.danger, fontWeight: 700, fontSize: '13px' } },
            labels: {
                ...chartBaseOptions.value.yaxis?.labels,
                formatter: (val) => formatBRL(val)
            }
        }
    ],
    tooltip: {
        shared: true,
        intersect: false,
        theme: themeStore.isDark ? 'dark' : 'light',
        y: [
            { formatter: (val) => formatNumberFull(val) },
            { formatter: (val) => formatCurrencyFull(val) }
        ]
    }
}));
</script>

<template>
  <div class="chart-section shadow-card" :class="{ 'is-refreshing': fatorRiscoLoading }">
    <div class="section-header">
      <i class="pi pi-chart-bar"></i>
      <h3>FATOR RISCO X QTD ESTAB</h3>
      <div class="spacer"></div>
      <Button 
        icon="pi pi-info-circle" 
        v-tooltip.top="'Este gráfico segmenta os estabelecimentos por faixas de não-comprovação...'" 
        text 
        severity="secondary" 
        rounded 
      />
    </div>
    <div class="chart-wrapper">
      <apexchart :key="chartKey" type="line" height="420" :options="chartOptions" :series="chartSeries"></apexchart>
    </div>
  </div>
</template>

<style scoped>
.chart-section {
  display: flex;
  flex-direction: column;
}

.chart-wrapper {
  height: 420px;
  margin: 0 -1rem -1rem -1rem;
}

.spacer { flex: 1; }

.is-refreshing {
  opacity: 0.5;
  pointer-events: none;
}
</style>
