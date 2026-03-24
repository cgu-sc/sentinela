<script setup>
import { ref, onMounted, computed } from 'vue';
import { useThemeStore } from '../stores/theme';
const themeStore = useThemeStore();
import Card from 'primevue/card';
import DataTable from 'primevue/datatable';
import Column from 'primevue/column';
import Tag from 'primevue/tag';
import Button from 'primevue/button';
import RadioButton from 'primevue/radiobutton';
import axios from 'axios';

// Dados de Exemplo (Baseados no seu print)
const kpis = ref([
  { id: 'total_cnpjs', label: 'C.NPJs', value: '34.126', color: '#ef4444', icon: 'pi pi-id-card' },       
  { id: 'valor_vendas', label: 'Valor Total de Vendas', value: 'R$ 23,74 Bi', color: '#3b82f6', icon: 'pi pi-money-bill' }, 
  { id: 'perc_valor', label: '% sem comprovação', value: '16,05%', color: '#f59e0b', icon: 'pi pi-percentage' },    
  { id: 'valor_nao_comp', label: 'Valor sem Comprovação', value: 'R$ 3,81 Bi', color: '#10b981', icon: 'pi pi-exclamation-triangle' }, 
  { id: 'total_meds', label: 'Qtde de Medicamentos', value: '3,57 Bi', color: '#8b5cf6', icon: 'pi pi-box' }, 
]);

const analyticData = ref([
  { uf: 'AC', cnpjs: '23', trendCnpjs: 'down', percValSemComp: '36,19%', trendPercVal: 'up', valSemComp: 'R$ 662.008,48', trendValSemComp: 'down', totalMov: 'R$ 1.829.269,01', trendTotalMov: 'down', percQtdeSemComp: '61,11%', trendPercQtde: 'up', qtdeSemComp: '337.508', trendQtdeSemComp: 'down', totalQtde: '552.293', trendTotalQtde: 'down' },
  { uf: 'AL', cnpjs: '412', trendCnpjs: 'up', percValSemComp: '22,45%', trendPercVal: 'down', valSemComp: 'R$ 12.450.120,00', trendValSemComp: 'up', totalMov: 'R$ 55.450.000,00', trendTotalMov: 'up', percQtdeSemComp: '18,30%', trendPercQtde: 'down', qtdeSemComp: '1.240.500', trendQtdeSemComp: 'down', totalQtde: '6.780.000', trendTotalQtde: 'neutral' },
  { uf: 'AM', cnpjs: '615', trendCnpjs: 'neutral', percValSemComp: '15,60%', trendPercVal: 'up', valSemComp: 'R$ 8.900.500,75', trendValSemComp: 'down', totalMov: 'R$ 57.060.400,00', trendTotalMov: 'up', percQtdeSemComp: '12,40%', trendPercQtde: 'up', qtdeSemComp: '850.400', trendQtdeSemComp: 'down', totalQtde: '6.860.000', trendTotalQtde: 'up' },
  { uf: 'AP', cnpjs: '105', trendCnpjs: 'down', percValSemComp: '40,20%', trendPercVal: 'up', valSemComp: 'R$ 2.450.000,00', trendValSemComp: 'neutral', totalMov: 'R$ 6.100.000,00', trendTotalMov: 'down', percQtdeSemComp: '45,00%', trendPercQtde: 'up', qtdeSemComp: '120.000', trendQtdeSemComp: 'down', totalQtde: '266.000', trendTotalQtde: 'down' },
  { uf: 'BA', cnpjs: '3.120', trendCnpjs: 'up', percValSemComp: '18,30%', trendPercVal: 'down', valSemComp: 'R$ 450.600.000,00', trendValSemComp: 'up', totalMov: 'R$ 2.460.000.000,00', trendTotalMov: 'up', percQtdeSemComp: '14,20%', trendPercQtde: 'down', qtdeSemComp: '45.100.200', trendQtdeSemComp: 'neutral', totalQtde: '317.000.000', trendTotalQtde: 'up' },
  { uf: 'CE', cnpjs: '1.850', trendCnpjs: 'up', percValSemComp: '12,45%', trendPercVal: 'neutral', valSemComp: 'R$ 115.400.000,00', trendValSemComp: 'down', totalMov: 'R$ 927.000.000,00', trendTotalMov: 'up', percQtdeSemComp: '9,80%', trendPercQtde: 'down', qtdeSemComp: '12.450.000', trendQtdeSemComp: 'down', totalQtde: '127.000.000', trendTotalQtde: 'up' },
  { uf: 'DF', cnpjs: '510', trendCnpjs: 'down', percValSemComp: '26,31%', trendPercVal: 'neutral', valSemComp: 'R$ 77.475.023,21', trendValSemComp: 'down', totalMov: 'R$ 294.504.490,84', trendTotalMov: 'down', percQtdeSemComp: '25,25%', trendPercQtde: 'neutral', qtdeSemComp: '9.615.002', trendQtdeSemComp: 'down', totalQtde: '38.073.846', trendTotalQtde: 'down' },
  { uf: 'ES', cnpjs: '940', trendCnpjs: 'up', percValSemComp: '14,20%', trendPercVal: 'up', valSemComp: 'R$ 42.100.000,00', trendValSemComp: 'down', totalMov: 'R$ 296.000.000,00', trendTotalMov: 'up', percQtdeSemComp: '11,50%', trendPercQtde: 'down', qtdeSemComp: '4.200.000', trendQtdeSemComp: 'down', totalQtde: '36.500.000', trendTotalQtde: 'neutral' },
  { uf: 'GO', cnpjs: '2.114', trendCnpjs: 'neutral', percValSemComp: '32,48%', trendPercVal: 'up', valSemComp: 'R$ 371.480.723,75', trendValSemComp: 'down', totalMov: 'R$ 1.143.574.758,05', trendTotalMov: 'down', percQtdeSemComp: '29,51%', trendPercQtde: 'neutral', qtdeSemComp: '49.771.949', trendQtdeSemComp: 'down', totalQtde: '168.670.578', trendTotalQtde: 'down' },
  { uf: 'MA', cnpjs: '1.020', trendCnpjs: 'down', percValSemComp: '31,50%', trendPercVal: 'up', valSemComp: 'R$ 89.400.000,00', trendValSemComp: 'up', totalMov: 'R$ 283.000.000,00', trendTotalMov: 'neutral', percQtdeSemComp: '27,30%', trendPercQtde: 'up', qtdeSemComp: '14.200.000', trendQtdeSemComp: 'down', totalQtde: '52.000.000', trendTotalQtde: 'down' },
  { uf: 'MG', cnpjs: '4.850', trendCnpjs: 'up', percValSemComp: '10,20%', trendPercVal: 'down', valSemComp: 'R$ 480.000.000,00', trendValSemComp: 'up', totalMov: 'R$ 4.700.000.000,00', trendTotalMov: 'up', percQtdeSemComp: '8,40%', trendPercQtde: 'down', qtdeSemComp: '62.000.000', trendQtdeSemComp: 'neutral', totalQtde: '738.000.000', trendTotalQtde: 'up' },
  { uf: 'MS', cnpjs: '720', trendCnpjs: 'neutral', percValSemComp: '19,40%', trendPercVal: 'up', valSemComp: 'R$ 34.200.000,00', trendValSemComp: 'down', totalMov: 'R$ 176.000.000,00', trendTotalMov: 'up', percQtdeSemComp: '16,20%', trendPercQtde: 'down', qtdeSemComp: '3.100.000', trendQtdeSemComp: 'down', totalQtde: '19.100.000', trendTotalQtde: 'neutral' },
  { uf: 'MT', cnpjs: '815', trendCnpjs: 'up', percValSemComp: '21,30%', trendPercVal: 'neutral', valSemComp: 'R$ 56.700.000,00', trendValSemComp: 'up', totalMov: 'R$ 266.000.000,00', trendTotalMov: 'up', percQtdeSemComp: '18,50%', trendPercQtde: 'down', qtdeSemComp: '5.200.000', trendQtdeSemComp: 'down', totalQtde: '28.100.000', trendTotalQtde: 'up' },
  { uf: 'PA', cnpjs: '1.450', trendCnpjs: 'down', percValSemComp: '28,60%', trendPercVal: 'up', valSemComp: 'R$ 145.000.000,00', trendValSemComp: 'up', totalMov: 'R$ 506.000.000,00', trendTotalMov: 'neutral', percQtdeSemComp: '24,30%', trendPercQtde: 'up', qtdeSemComp: '21.000.000', trendQtdeSemComp: 'down', totalQtde: '86.000.000', trendTotalQtde: 'down' },
  { uf: 'PB', cnpjs: '610', trendCnpjs: 'up', percValSemComp: '15,40%', trendPercVal: 'down', valSemComp: 'R$ 28.100.000,00', trendValSemComp: 'down', totalMov: 'R$ 182.000.000,00', trendTotalMov: 'up', percQtdeSemComp: '12,60%', trendPercQtde: 'down', qtdeSemComp: '2.400.000', trendQtdeSemComp: 'down', totalQtde: '19.000.000', trendTotalQtde: 'up' },
  { uf: 'PE', cnpjs: '1.680', trendCnpjs: 'up', percValSemComp: '14,80%', trendPercVal: 'up', valSemComp: 'R$ 156.000.000,00', trendValSemComp: 'up', totalMov: 'R$ 1.050.000.000,00', trendTotalMov: 'up', percQtdeSemComp: '11,20%', trendPercQtde: 'down', qtdeSemComp: '16.800.000', trendQtdeSemComp: 'down', totalQtde: '150.000.000', trendTotalQtde: 'up' },
  { uf: 'PI', cnpjs: '515', trendCnpjs: 'down', percValSemComp: '33,20%', trendPercVal: 'up', valSemComp: 'R$ 42.000.000,00', trendValSemComp: 'up', totalMov: 'R$ 126.000.000,00', trendTotalMov: 'down', percQtdeSemComp: '28,10%', trendPercQtde: 'up', qtdeSemComp: '8.400.000', trendQtdeSemComp: 'down', totalQtde: '29.800.000', trendTotalQtde: 'down' },
  { uf: 'PR', cnpjs: '2.850', trendCnpjs: 'up', percValSemComp: '8,40%', trendPercVal: 'down', valSemComp: 'R$ 210.000.000,00', trendValSemComp: 'down', totalMov: 'R$ 2.500.000.000,00', trendTotalMov: 'up', percQtdeSemComp: '6,20%', trendPercQtde: 'down', qtdeSemComp: '24.000.000', trendQtdeSemComp: 'down', totalQtde: '387.000.000', trendTotalQtde: 'neutral' },
  { uf: 'RJ', cnpjs: '3.420', trendCnpjs: 'up', percValSemComp: '11,50%', trendPercVal: 'neutral', valSemComp: 'R$ 480.000.000,00', trendValSemComp: 'up', totalMov: 'R$ 4.170.000.000,00', trendTotalMov: 'neutral', percQtdeSemComp: '9,40%', trendPercQtde: 'neutral', qtdeSemComp: '32.100.000', trendQtdeSemComp: 'up', totalQtde: '341.000.000', trendTotalQtde: 'neutral' },
  { uf: 'RN', cnpjs: '612', trendCnpjs: 'neutral', percValSemComp: '19,80%', trendPercVal: 'up', valSemComp: 'R$ 38.000.000,00', trendValSemComp: 'neutral', totalMov: 'R$ 192.000.000,00', trendTotalMov: 'up', percQtdeSemComp: '16,50%', trendPercQtde: 'down', qtdeSemComp: '3.400.000', trendQtdeSemComp: 'neutral', totalQtde: '20.600.000', trendTotalQtde: 'neutral' },
  { uf: 'RO', cnpjs: '415', trendCnpjs: 'up', percValSemComp: '25,60%', trendPercVal: 'up', valSemComp: 'R$ 32.000.000,00', trendValSemComp: 'up', totalMov: 'R$ 125.000.000,00', trendTotalMov: 'neutral', percQtdeSemComp: '21,50%', trendPercQtde: 'up', qtdeSemComp: '2.100.000', trendQtdeSemComp: 'neutral', totalQtde: '9.770.000', trendTotalQtde: 'neutral' },
  { uf: 'RR', cnpjs: '98', trendCnpjs: 'down', percValSemComp: '38,40%', trendPercVal: 'up', valSemComp: 'R$ 5.400.000,00', trendValSemComp: 'neutral', totalMov: 'R$ 14.100.000,00', trendTotalMov: 'down', percQtdeSemComp: '34,20%', trendPercQtde: 'up', qtdeSemComp: '140.000', trendQtdeSemComp: 'up', totalQtde: '410.000', trendTotalQtde: 'down' },
  { uf: 'RS', cnpjs: '3.150', trendCnpjs: 'up', percValSemComp: '9,20%', trendPercVal: 'down', valSemComp: 'R$ 310.000.000,00', trendValSemComp: 'down', totalMov: 'R$ 3.370.000.000,00', trendTotalMov: 'up', percQtdeSemComp: '7,40%', trendPercQtde: 'down', qtdeSemComp: '41.000.000', trendQtdeSemComp: 'down', totalQtde: '554.000.000', trendTotalQtde: 'up' },
  { uf: 'SC', cnpjs: '2.210', trendCnpjs: 'up', percValSemComp: '7,80%', trendPercVal: 'down', valSemComp: 'R$ 180.000.000,00', trendValSemComp: 'neutral', totalMov: 'R$ 2.300.000.000,00', trendTotalMov: 'up', percQtdeSemComp: '5,60%', trendPercQtde: 'down', qtdeSemComp: '18.000.000', trendQtdeSemComp: 'down', totalQtde: '321.000.000', trendTotalQtde: 'neutral' },
  { uf: 'SE', cnpjs: '415', trendCnpjs: 'neutral', percValSemComp: '21,30%', trendPercVal: 'up', valSemComp: 'R$ 22.100.000,00', trendValSemComp: 'down', totalMov: 'R$ 104.000.000,00', trendTotalMov: 'down', percQtdeSemComp: '19,40%', trendPercQtde: 'neutral', qtdeSemComp: '1.200.000', trendQtdeSemComp: 'neutral', totalQtde: '6.190.000', trendTotalQtde: 'down' },
  { uf: 'SP', cnpjs: '9.820', trendCnpjs: 'up', percValSemComp: '6,20%', trendPercVal: 'down', valSemComp: 'R$ 1.840.000.000,00', trendValSemComp: 'down', totalMov: 'R$ 29.700.000.000,00', trendTotalMov: 'up', percQtdeSemComp: '4,50%', trendPercQtde: 'down', qtdeSemComp: '248.000.000', trendQtdeSemComp: 'up', totalQtde: '5.510.000.000', trendTotalQtde: 'up' },
  { uf: 'TO', cnpjs: '412', trendCnpjs: 'up', percValSemComp: '19,30%', trendPercVal: 'up', valSemComp: 'R$ 18.200.000,00', trendValSemComp: 'down', totalMov: 'R$ 94.000.000,00', trendTotalMov: 'neutral', percQtdeSemComp: '17,20%', trendPercQtde: 'neutral', qtdeSemComp: '1.420.000', trendQtdeSemComp: 'neutral', totalQtde: '8.250.000', trendTotalQtde: 'up' }
]);

// CONFIG GRAFICO COMBO (APEXCHARTS - PADRÃO ARBFLOW)
const chartSeries = ref([
    {
        name: 'Qtd Estab por Faixa',
        type: 'column',
        data: [0.43, 18.49, 5.16, 2.37, 1.49, 1.15, 0.8, 1.0, 1.24, 0.9]
    },
    {
        name: 'Valor Sem Comprovação por Faixa',
        type: 'area',
        data: [0.05, 0.45, 0.61, 0.36, 0.3, 0.35, 0.5, 0.34, 0.23, 0.18]
    }
]);

const chartOptions = computed(() => ({
    chart: {
        height: 350,
        type: 'line',
        toolbar: { show: false },
        zoom: { enabled: false },
        foreColor: themeStore.isDark ? '#94a3b8' : '#64748b'
    },
    colors: [themeStore.isDark ? '#3b82f6' : '#1e293b', '#fbbf24'],
    stroke: {
        width: [0, 2],
        curve: 'smooth'
    },
    fill: {
        type: 'solid',
        opacity: [1, 0.3]
    },
    labels: ['0', '<=10%', '10-20%', '20-30%', '30-40%', '40-50%', '50-60%', '60-70%', '70-80%', '80-100%'],
    xaxis: {
        type: 'category',
        labels: { style: { fontSize: '10px' } }
    },
    yaxis: [
        {
            title: { text: 'Qtd Estab (Mil)', style: { color: themeStore.isDark ? '#3b82f6' : '#1e293b' } },
            labels: { formatter: (val) => val + ' Mil' }
        },
        {
            opposite: true,
            title: { text: 'Valor Sem Comp (Bi)', style: { color: '#fbbf24' } },
            labels: { formatter: (val) => val + ' Bi' }
        }
    ],
    grid: { borderColor: 'rgba(100, 116, 139, 0.1)' },
    legend: { 
        position: 'top', 
        horizontalAlign: 'center',
        labels: { colors: themeStore.isDark ? '#f4f4f5' : '#1e293b' }
    },
    tooltip: { theme: themeStore.isDark ? 'dark' : 'light' }
}));

onMounted(() => {
    // ...
});

// Agrupamento selecionado (para Teleport Sidebar)
const groupBy = ref('uf');
const groupOptions = ref(['UF', 'Município', 'Região de Saúde']);

// Funções de Estilo com ícones baseados no print
const getTrendIcon = (trend) => {
  if (trend === 'up') return 'pi pi-arrow-up';
  if (trend === 'down') return 'pi pi-arrow-down';
  if (trend === 'neutral') return 'pi pi-arrow-up-right'; // Estilo do print para diagonal
  return 'pi pi-minus';
};

const getTrendColor = (trend) => {
  if (trend === 'up') return '#ef4444'; // Vermelho
  if (trend === 'down') return '#22c55e'; // Verde
  if (trend === 'neutral') return '#f59e0b'; // Laranja para diagonal
  return '#94a3b8';
};
</script>

<template>
  <div class="dashboard-container">
    <!-- CARDS DE KPI -->
    <div class="kpi-grid">
      <div 
        v-for="kpi in kpis" 
        :key="kpi.label" 
        class="kpi-card" 
      >
        <div class="kpi-body">
          <div class="kpi-icon-bg" :style="{ backgroundColor: kpi.color + '20', color: kpi.color }">
             <i :class="kpi.icon"></i>
          </div>
          <div class="kpi-content">
            <span class="kpi-label">{{ kpi.label }}</span>
            <span class="kpi-value">{{ kpi.value }}</span>
          </div>
        </div>
      </div>
    </div>

    <!-- MAIN GRID (GRÁFICO E DEPOIS TABELA) -->
    <div class="charts-table-grid">
      <!-- GRÁFICO -->
      <div class="chart-section shadow-card">
         <div class="section-header">
           <i class="pi pi-chart-bar"></i>
           <h3>FATOR RISCO X QTD ESTAB</h3>
           <div class="spacer"></div>
           <Button icon="pi pi-external-link" text severity="secondary" rounded />
        </div>
        <div class="chart-wrapper">
            <apexchart type="line" height="350" :options="chartOptions" :series="chartSeries"></apexchart>
        </div>
      </div>

      <!-- TABELA ANALISE NACIONAL -->
      <div class="table-section shadow-card">
        <div class="section-header">
           <i class="pi pi-table"></i>
           <h3>ANÁLISE NACIONAL</h3>
           <div class="spacer"></div>
           <Button icon="pi pi-info-circle" text severity="secondary" rounded />
        </div>
        
        <DataTable :value="analyticData" size="small" stripedRows class="custom-table enterprise-table">
          <Column field="uf" header="UF" footer="TOTAL" style="width: 5%"></Column>
          
          <Column header="Qtde CNPJs" footer="34.126" style="width: 10%">
             <template #body="slotProps">
                <div class="flex-cell">
                  <i :class="getTrendIcon(slotProps.data.trendCnpjs)" :style="{ color: getTrendColor(slotProps.data.trendCnpjs) }"></i>
                   <span>{{ slotProps.data.cnpjs }}</span>
                </div>
             </template>
          </Column>

          <Column header="% Valor Sem Comprovação" footer="16,05%" style="width: 12%">
             <template #body="slotProps">
                <div class="flex-cell">
                  <i :class="getTrendIcon(slotProps.data.trendPercVal)" :style="{ color: getTrendColor(slotProps.data.trendPercVal) }"></i>
                  <span>{{ slotProps.data.percValSemComp }}</span>
                </div>
             </template>
          </Column>

          <Column header="Valor sem Comprovação" footer="R$ 3.810.451.144,37" style="width: 15%">
             <template #body="slotProps">
                <div class="flex-cell">
                  <i :class="getTrendIcon(slotProps.data.trendValSemComp)" :style="{ color: getTrendColor(slotProps.data.trendValSemComp) }"></i>
                  <span>{{ slotProps.data.valSemComp }}</span>
                </div>
             </template>
          </Column>

          <Column header="Valor Total Movimentado" footer="R$ 23.737.222.862,64" style="width: 15%">
             <template #body="slotProps">
                <div class="flex-cell">
                  <i :class="getTrendIcon(slotProps.data.trendTotalMov)" :style="{ color: getTrendColor(slotProps.data.trendTotalMov) }"></i>
                  <span>{{ slotProps.data.totalMov }}</span>
                </div>
             </template>
          </Column>

          <Column header="% Qtde Medicamentos Vendidos sem Comprovação" footer="15,34%" style="width: 15%">
             <template #body="slotProps">
                <div class="flex-cell">
                  <i :class="getTrendIcon(slotProps.data.trendPercQtde)" :style="{ color: getTrendColor(slotProps.data.trendPercQtde) }"></i>
                  <span>{{ slotProps.data.percQtdeSemComp }}</span>
                </div>
             </template>
          </Column>

          <Column header="Qtde de Medicamentos Vendidos sem Comprovação" footer="548.306.548" style="width: 12%">
             <template #body="slotProps">
                <div class="flex-cell">
                  <i :class="getTrendIcon(slotProps.data.trendQtdeSemComp)" :style="{ color: getTrendColor(slotProps.data.trendQtdeSemComp) }"></i>
                  <span>{{ slotProps.data.qtdeSemComp }}</span>
                </div>
             </template>
          </Column>

          <Column header="Qtde Total de Medicamentos Vendidos" footer="3.574.208.598" style="width: 15%">
             <template #body="slotProps">
                <div class="flex-cell">
                  <i :class="getTrendIcon(slotProps.data.trendTotalQtde)" :style="{ color: getTrendColor(slotProps.data.trendTotalQtde) }"></i>
                  <span>{{ slotProps.data.totalQtde }}</span>
                </div>
             </template>
          </Column>
        </DataTable>
      </div>
    </div>
  </div>
</template>

<style scoped>
.dashboard-container {
  display: flex;
  flex-direction: column;
  gap: 1.5rem;
  max-width: 1600px;
  margin: 0 auto;
}

/* KPI CARDS */
.kpi-grid {
  display: grid;
  grid-template-columns: repeat(5, 1fr); /* 5 cards na linha */
  gap: 1rem;
}

.kpi-card {
  background: var(--card-bg);
  border-radius: 12px;
  padding: 1rem 1.25rem;
  border: 1px solid var(--sidebar-border);
  transition: transform 0.2s, background-color 0.3s ease;
}

.kpi-card:hover { 
  transform: translateY(-2px);
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
}

.kpi-body {
  display: flex;
  justify-content: flex-start; /* changed */
  align-items: center;
  gap: 1rem; /* changed */
}

.kpi-content {
  display: flex;
  flex-direction: column;
}

.kpi-label {
  font-size: 0.75rem;
  color: var(--text-muted);
  font-weight: 600;
  text-transform: uppercase;
}

.kpi-value {
  font-size: 1.5rem;
  font-weight: 800;
  color: var(--text-color);
  opacity: 0.85; /* Softened contrast */
}

.kpi-icon-bg {
  width: 2.75rem;
  height: 2.75rem;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 0.5rem;
  font-size: 1.25rem;
}

/* MAIN GRID */
.charts-table-grid {
  display: flex;
  flex-direction: column;
  gap: 1.5rem;
}

.shadow-card {
  background: var(--card-bg);
  border-radius: 16px;
  padding: 1.5rem;
  box-shadow: 0 1px 3px rgba(0,0,0,0.1);
  border: 1px solid var(--navbar-border);
  transition: background-color 0.3s ease;
}

.section-header {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  margin-bottom: 1.5rem;
}

.section-header h3 {
  font-size: 1rem;
  font-weight: 700;
  color: var(--text-color);
  margin: 0;
}

.spacer { flex: 1; }

.chart-placeholder {
  height: 350px;
  background: color-mix(in srgb, var(--primary-color) 5%, transparent);
  border-radius: 12px;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  border: 2px dashed var(--sidebar-border);
}

/* TABELA ESTILO ENTERPRISE */
:deep(.enterprise-table .p-datatable-thead > tr > th) {
  background: var(--table-header-bg) !important;
  color: var(--table-header-text) !important;
  font-size: 0.75rem;
  font-weight: 700;
  letter-spacing: 0.5px;
  text-transform: uppercase;
  padding: 0.75rem 0.5rem;
  border-bottom: 2px solid var(--sidebar-border) !important;
}

/* O DEFINITIVO PARA AS LINHAS BRANCAS */
:deep(.enterprise-table .p-datatable-tbody > tr > td) {
    background: var(--card-bg) !important;
    color: var(--text-color) !important;
    border-color: var(--sidebar-border) !important;
}

:deep(.enterprise-table.p-datatable-striped .p-datatable-tbody > tr.p-row-odd > td) {
    background: var(--table-stripe) !important;
}

/* Garante que o hover vença a regra da listra zebra */
:deep(.enterprise-table .p-datatable-tbody > tr:hover > td),
:deep(.enterprise-table.p-datatable-striped .p-datatable-tbody > tr.p-row-odd:hover > td) {
    background: var(--table-hover) !important;
}

:deep(.enterprise-table .p-datatable-tfoot td) {
  background: var(--table-header-bg) !important;
  color: var(--table-header-text) !important;
  font-weight: 800;
  padding: 0.75rem 0.5rem;
  font-size: 0.8rem;
  border-top: 2px solid var(--sidebar-border) !important;
}

:deep(.enterprise-table .p-datatable-tbody > tr) {
  font-size: 0.85rem;
  color: var(--text-color);
}

:deep(.enterprise-table .p-datatable-tbody > tr:nth-child(even)) {
  background-color: var(--table-stripe) !important;
}

.flex-cell {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  white-space: nowrap;
}

.flex-cell i {
  font-size: 0.8rem;
}

:global(.view-local-filters) {
  display: flex;
  flex-direction: column;
}

:global(.local-filter-header) {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  font-size: 0.85rem;
  text-transform: uppercase;
  margin-bottom: 1rem;
  font-weight: 800;
  color: var(--text-color);
  letter-spacing: 1px;
}

:global(.local-filter-header i) {
  color: var(--primary-color);
}

:global(.local-filter-section) {
  margin-bottom: 1.5rem;
}

:global(.local-filter-label) {
  display: block;
  font-size: 0.8rem;
  text-transform: uppercase;
  margin-bottom: 0.75rem;
  font-weight: 600;
  color: var(--primary-color);
}

:global(.flex-col) { display: flex; flex-direction: column; }
</style>
