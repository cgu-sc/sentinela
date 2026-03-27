<script setup>
import { ref } from 'vue';
import DataTable from 'primevue/datatable';
import Column from 'primevue/column';
import InputText from 'primevue/inputtext';

import { SOCIOS_DATA_DEMO, EMPRESAS_SOCIO_DEMO } from '@/mocks/demoData';

// Data (Mocks centralizados)
const sociosData = ref(SOCIOS_DATA_DEMO);
const empresasSocio = ref(EMPRESAS_SOCIO_DEMO);

const searchCNPJ = ref('');
</script>

<template>
  <div class="socios-view">
    <!-- PAINÉIS LADO A LADO -->
    <div class="triple-grid">
        <!-- 1. SÓCIOS -->
        <div class="panel shadow-card">
            <div class="section-header">
                <i class="pi pi-users"></i>
                <h3>SÓCIOS DOS ALVOS</h3>
            </div>
            <div class="panel-kpi">85.380 <span class="unit">Sócios vinculados</span></div>
            <DataTable :value="sociosData" size="small" class="p-datatable-sm">
                <Column field="nome" header="Sócio"></Column>
                <Column field="cadunico" header="CadÚnico"></Column>
                <Column field="mandado" header="Mandado"></Column>
                <Column field="numSociedades" header="Sociedades"></Column>
            </DataTable>
        </div>

        <!-- 2. EMPRESAS DOS SÓCIOS -->
        <div class="panel shadow-card highlight">
            <div class="section-header">
                <i class="pi pi-briefcase"></i>
                <h3>OUTRAS EMPRESAS DOS SÓCIOS</h3>
            </div>
            <div class="panel-kpi">34.061 <span class="unit">Empresas encontradas</span></div>
            <DataTable :value="empresasSocio" size="small">
                <Column field="cnpj" header="CNPJ"></Column>
                <Column field="uf" header="UF"></Column>
                <Column field="situacao" header="Situação"></Column>
            </DataTable>
        </div>

        <!-- 3. LISTA FILTRADA -->
        <div class="panel shadow-card">
            <div class="section-header">
                <i class="pi pi-filter"></i>
                <h3>CPF OU CNPJ FILTRADOS</h3>
            </div>
            <div class="panel-kpi">85.380</div>
             <div class="placeholder-text">Selecione um item para ver detalhes da rede societária.</div>
        </div>
    </div>
  </div>
</template>

<style scoped>
.socios-view {
    display: flex;
    flex-direction: column;
    gap: 1.5rem;
}

.triple-grid {
    display: grid;
    grid-template-columns: 1.2fr 1fr 1fr;
    gap: 1.5rem;
}

.panel-kpi {
    font-size: 2rem;
    font-weight: 800;
    margin-bottom: 1rem;
    color: var(--primary-color);
}

.panel-kpi .unit {
    font-size: 1rem;
    font-weight: 400;
    color: var(--text-color);
}

.panel.highlight {
    border-top: 4px solid var(--primary-color);
}

.placeholder-text {
    padding: 2rem;
    text-align: center;
    opacity: 0.3;
}
</style>
