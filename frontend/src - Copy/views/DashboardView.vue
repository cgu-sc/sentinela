<script setup>
import { ref, onMounted } from 'vue';
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
  { 
    uf: 'AC', cnpjs: '23', trendCnpjs: 'down', 
    percValSemComp: '36,19%', trendPercVal: 'up',
    valSemComp: 'R$ 662.008,48', trendValSemComp: 'down',
    totalMov: 'R$ 1.829.269,01', trendTotalMov: 'down',
    percQtdeSemComp: '61,11%', trendPercQtde: 'up',
    qtdeSemComp: '337.508', trendQtdeSemComp: 'down',
    totalQtde: '552.293', trendTotalQtde: 'down'
  },
  { 
    uf: 'GO', cnpjs: '2.114', trendCnpjs: 'neutral', 
    percValSemComp: '32,48%', trendPercVal: 'up',
    valSemComp: 'R$ 371.480.723,75', trendValSemComp: 'down',
    totalMov: 'R$ 1.143.574.758,05', trendTotalMov: 'down',
    percQtdeSemComp: '29,51%', trendPercQtde: 'neutral',
    qtdeSemComp: '49.771.949', trendQtdeSemComp: 'down',
    totalQtde: '168.670.578', trendTotalQtde: 'down'
  },
  { 
    uf: 'DF', cnpjs: '510', trendCnpjs: 'down', 
    percValSemComp: '26,31%', trendPercVal: 'neutral',
    valSemComp: 'R$ 77.475.023,21', trendValSemComp: 'down',
    totalMov: 'R$ 294.504.490,84', trendTotalMov: 'down',
    percQtdeSemComp: '25,25%', trendPercQtde: 'neutral',
    qtdeSemComp: '9.615.002', trendQtdeSemComp: 'down',
    totalQtde: '38.073.846', trendTotalQtde: 'down'
  }
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

const chartOptions = ref({
    chart: {
        height: 350,
        type: 'line',
        toolbar: { show: false },
        zoom: { enabled: false },
        foreColor: '#64748b'
    },
    colors: ['#1e293b', '#fbbf24'],
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
            title: { text: 'Qtd Estab (Mil)', style: { color: '#1e293b' } },
            labels: { formatter: (val) => val + ' Mil' }
        },
        {
            opposite: true,
            title: { text: 'Valor Sem Comp (Bi)', style: { color: '#fbbf24' } },
            labels: { formatter: (val) => val + ' Bi' }
        }
    ],
    grid: { borderColor: 'rgba(100, 116, 139, 0.1)' },
    legend: { position: 'top', horizontalAlign: 'center' },
    tooltip: { shared: true, intersect: false }
});

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
          <Column field="uf" header="UF" style="width: 5%"></Column>
          
          <Column header="Qtde CNPJs" style="width: 10%">
             <template #body="slotProps">
                <div class="flex-cell">
                  <i :class="getTrendIcon(slotProps.data.trendCnpjs)" :style="{ color: getTrendColor(slotProps.data.trendCnpjs) }"></i>
                  <span>{{ slotProps.data.cnpjs }}</span>
                </div>
             </template>
          </Column>

          <Column header="% Valor Sem Comprovação" style="width: 12%">
             <template #body="slotProps">
                <div class="flex-cell">
                  <i :class="getTrendIcon(slotProps.data.trendPercVal)" :style="{ color: getTrendColor(slotProps.data.trendPercVal) }"></i>
                  <span>{{ slotProps.data.percValSemComp }}</span>
                </div>
             </template>
          </Column>

          <Column header="Valor sem Comprovação" style="width: 15%">
             <template #body="slotProps">
                <div class="flex-cell">
                  <i :class="getTrendIcon(slotProps.data.trendValSemComp)" :style="{ color: getTrendColor(slotProps.data.trendValSemComp) }"></i>
                  <span>{{ slotProps.data.valSemComp }}</span>
                </div>
             </template>
          </Column>

          <Column header="Valor Total Movimentado" style="width: 15%">
             <template #body="slotProps">
                <div class="flex-cell">
                  <i :class="getTrendIcon(slotProps.data.trendTotalMov)" :style="{ color: getTrendColor(slotProps.data.trendTotalMov) }"></i>
                  <span>{{ slotProps.data.totalMov }}</span>
                </div>
             </template>
          </Column>

          <Column header="% Qtde Medicamentos Vendidos sem Comprovação" style="width: 15%">
             <template #body="slotProps">
                <div class="flex-cell">
                  <i :class="getTrendIcon(slotProps.data.trendPercQtde)" :style="{ color: getTrendColor(slotProps.data.trendPercQtde) }"></i>
                  <span>{{ slotProps.data.percQtdeSemComp }}</span>
                </div>
             </template>
          </Column>

          <Column header="Qtde de Medicamentos Vendidos sem Comprovação" style="width: 12%">
             <template #body="slotProps">
                <div class="flex-cell">
                  <i :class="getTrendIcon(slotProps.data.trendQtdeSemComp)" :style="{ color: getTrendColor(slotProps.data.trendQtdeSemComp) }"></i>
                  <span>{{ slotProps.data.qtdeSemComp }}</span>
                </div>
             </template>
          </Column>

          <Column header="Qtde Total de Medicamentos Vendidos" style="width: 15%">
             <template #body="slotProps">
                <div class="flex-cell">
                  <i :class="getTrendIcon(slotProps.data.trendTotalQtde)" :style="{ color: getTrendColor(slotProps.data.trendTotalQtde) }"></i>
                  <span>{{ slotProps.data.totalQtde }}</span>
                </div>
             </template>
          </Column>

          <!-- RODAPÉ DE TOTAIS -->
          <template #footer>
            <div class="table-footer-row">
                 <div style="width: 5%">Total</div>
                 <div style="width: 10%">34.126</div>
                 <div style="width: 12%">16,05%</div>
                 <div style="width: 15%">R$ 3.810.451.144,37</div>
                 <div style="width: 15%">R$ 23.737.222.862,64</div>
                 <div style="width: 15%">15,34%</div>
                 <div style="width: 12%">548.306.548</div>
                 <div style="width: 15%">3.574.208.598</div>
            </div>
          </template>
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
  color: var(--text-color);
  font-weight: 600;
  text-transform: uppercase;
}

.kpi-value {
  font-size: 1.5rem;
  font-weight: 800;
  color: var(--text-color);
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
  background: rgba(var(--accent-color), 0.05);
  border-radius: 12px;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  border: 2px dashed var(--sidebar-border);
}

/* TABELA ESTILO ENTERPRISE */
:deep(.enterprise-table .p-datatable-thead > tr > th) {
  background: #1e293b !important;
  color: #ffffff !important;
  font-size: 0.75rem;
  text-transform: uppercase;
  padding: 1rem 0.5rem;
  border: 1px solid rgba(255,255,255,0.1);
}

:deep(.enterprise-table .p-datatable-tfoot td),
.table-footer-row {
  background: #1e293b !important;
  color: #ffffff !important;
  font-weight: 800;
  display: flex;
  align-items: center;
  padding: 0.75rem 0.5rem;
  font-size: 0.8rem;
}

.table-footer-row div {
  padding: 0 0.5rem;
}

:deep(.enterprise-table .p-datatable-tbody > tr) {
  font-size: 0.85rem;
  color: #1e293b;
}

:deep(.enterprise-table .p-datatable-tbody > tr:nth-child(even)) {
  background-color: #f0f7ff !important;
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
  color: var(--accent-color);
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
  color: var(--accent-color);
}

:global(.flex-col) { display: flex; flex-direction: column; }
</style>
