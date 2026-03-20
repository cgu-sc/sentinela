<script setup>
import { ref, onMounted } from 'vue';
import Card from 'primevue/card';
import DataTable from 'primevue/datatable';
import Column from 'primevue/column';
import Tag from 'primevue/tag';
import axios from 'axios';

// Dados de Exemplo (Baseados no seu print)
const kpis = ref([
  { label: 'C.NPJs', value: '34.126', color: '#1e293b', icon: 'pi pi-id-card' },
  { label: 'Valor Total de Vendas', value: 'R$ 23,74 Bi', color: '#334155', icon: 'pi pi-money-bill' },
  { label: '% Valor sem comprovação', value: '16,05%', color: '#f59e0b', icon: 'pi pi-percentage' },
  { label: 'Valor sem Comprovação', value: 'R$ 3,81 Bi', color: '#991b1b', icon: 'pi pi-exclamation-triangle' },
  { label: 'Qtde Total de Medicamentos', value: '3,57 Bi', color: '#475569', icon: 'pi pi-box' },
  { label: '% Qtde sem comprovação', value: '15,34%', color: '#ea580c', icon: 'pi pi-chart-pie' },
]);

const analyticData = ref([
  { uf: 'AC', cnpjs: 23, percSemComp: '36,19%', valSemComp: 'R$ 662.008,48', totalMov: 'R$ 1.829.269,01', trendCnpjs: 'down', trendPerc: 'up' },
  { uf: 'GO', cnpjs: 2114, percSemComp: '32,48%', valSemComp: 'R$ 371.480.723,75', totalMov: 'R$ 1.143.574.758,05', trendCnpjs: 'up', trendPerc: 'down' },
  { uf: 'DF', cnpjs: 510, percSemComp: '26,31%', valSemComp: 'R$ 77.475.023,21', totalMov: 'R$ 294.504.490,84', trendCnpjs: 'neutral', trendPerc: 'up' },
  { uf: 'MT', cnpjs: 599, percSemComp: '25,18%', valSemComp: 'R$ 40.646.021,29', totalMov: 'R$ 161.427.567,05', trendCnpjs: 'up', trendPerc: 'neutral' },
  { uf: 'MA', cnpjs: 374, percSemComp: '24,95%', valSemComp: 'R$ 59.022.485,41', totalMov: 'R$ 236.552.100,02', trendCnpjs: 'down', trendPerc: 'up' },
]);

// Funções de Estilo
const getTrendIcon = (trend) => {
  if (trend === 'up') return 'pi pi-arrow-up';
  if (trend === 'down') return 'pi pi-arrow-down';
  return 'pi pi-minus';
};

const getTrendColor = (trend) => {
  if (trend === 'up') return '#ef4444'; // Alerta (Vermelho)
  if (trend === 'down') return '#22c55e'; // Melhora (Verde)
  return '#94a3b8'; // Neutro
};

</script>

<template>
  <div class="dashboard-container">
    <!-- CARDS DE KPI (STYLE: SENTINELA PRINT) -->
    <div class="kpi-grid">
      <div 
        v-for="kpi in kpis" 
        :key="kpi.label" 
        class="kpi-card" 
        :style="{ borderTopColor: kpi.color, borderTopWidth: '4px', borderTopStyle: 'solid' }"
      >
        <div class="kpi-body">
          <div class="kpi-content">
            <h2 class="kpi-value">{{ kpi.value }}</h2>
            <p class="kpi-label">{{ kpi.label }}</p>
          </div>
          <div class="kpi-icon-bg" :style="{ backgroundColor: kpi.color + '15' }">
             <i :class="kpi.icon" :style="{ color: kpi.color }"></i>
          </div>
        </div>
      </div>
    </div>

    <!-- MAIN GRID (TABELA + GRÁFICO) -->
    <div class="charts-table-grid">
      <!-- TABELA CENTRAL (STYLE: ARBFLOW DATA-TABLE) -->
      <div class="table-section shadow-card">
        <div class="section-header">
           <i class="pi pi-table"></i>
           <h3>ANÁLISE NACIONAL</h3>
           <div class="spacer"></div>
           <Button icon="pi pi-info-circle" text severity="secondary" rounded />
        </div>
        
        <DataTable :value="analyticData" size="small" stripedRows class="custom-table">
          <Column field="uf" header="UF" style="width: 10%"></Column>
          
          <Column field="cnpjs" header="Qtde CNPJs" style="width: 15%">
             <template #body="slotProps">
                <div class="flex-cell">
                  <span>{{ slotProps.data.cnpjs }}</span>
                  <i :class="getTrendIcon(slotProps.data.trendCnpjs)" :style="{ color: getTrendColor(slotProps.data.trendCnpjs), fontSize: '0.7rem' }"></i>
                </div>
             </template>
          </Column>

          <Column field="percSemComp" header="% Valor Sem Comp." style="width: 20%">
             <template #body="slotProps">
                <div class="flex-cell">
                  <div class="p-progress-simple" :style="{ width: slotProps.data.percSemComp, backgroundColor: '#fcd34d' }"></div>
                  <span>{{ slotProps.data.percSemComp }}</span>
                  <i :class="getTrendIcon(slotProps.data.trendPerc)" :style="{ color: getTrendColor(slotProps.data.trendPerc), fontSize: '0.7rem' }"></i>
                </div>
             </template>
          </Column>

          <Column field="valSemComp" header="Valor Sem Comp." style="width: 25%"></Column>
          <Column field="totalMov" header="Total Movimentado" style="width: 30%"></Column>
        </DataTable>
      </div>

      <!-- GRÁFICO LATERAL (RESERVADO) -->
      <div class="chart-section shadow-card">
         <div class="section-header">
           <i class="pi pi-chart-bar"></i>
           <h3>FATOR RISCO X QTD ESTAB</h3>
           <div class="spacer"></div>
           <Button icon="pi pi-external-link" text severity="secondary" rounded />
        </div>
        <div class="chart-placeholder">
           <i class="pi pi-image text-4xl mb-3 opacity-20"></i>
           <p class="opacity-40">Gráfico de Dispersão aqui</p>
        </div>
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
  grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
  gap: 1rem;
}

.kpi-card {
  background: var(--card-bg);
  border-radius: 12px;
  padding: 1.25rem;
  box-shadow: 0 4px 6px -1px rgba(0,0,0,0.1);
  transition: transform 0.2s, background-color 0.3s ease;
}

.kpi-card:hover { 
  transform: translateY(-4px);
  box-shadow: 0 10px 15px -3px rgba(0,0,0,0.1);
}

.kpi-body {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.kpi-value {
  font-size: 1.5rem;
  font-weight: 800;
  margin: 0;
  color: var(--text-color);
}

.kpi-label {
  font-size: 0.75rem;
  color: var(--text-color);
  opacity: 0.6;
  margin: 0.25rem 0 0 0;
  font-weight: 600;
  text-transform: uppercase;
}

.kpi-icon-bg {
  width: 48px;
  height: 48px;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 12px;
  font-size: 1.25rem;
}

/* MAIN GRID */
.charts-table-grid {
  display: grid;
  grid-template-columns: 1.5fr 1fr;
  gap: 1.5rem;
}

@media (max-width: 1200px) {
  .charts-table-grid { grid-template-columns: 1fr; }
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
  background: #f8fafc;
  border-radius: 12px;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  border: 2px dashed #e2e8f0;
}

/* CUSTOM TABLE */
.flex-cell {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.p-progress-simple {
  height: 8px;
  border-radius: 4px;
}

:deep(.custom-table .p-datatable-thead > tr > th) {
  background: #f8fafc;
  color: #64748b;
  font-size: 0.7rem;
  text-transform: uppercase;
  font-weight: 700;
}

:deep(.custom-table .p-datatable-tbody > tr) {
  font-size: 0.85rem;
}
</style>
