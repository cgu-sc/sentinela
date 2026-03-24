<script setup>
import { ref } from 'vue';
import DataTable from 'primevue/datatable';
import Column from 'primevue/column';
import InputText from 'primevue/inputtext';

// Mockup Data - Rede de Sócios
const sociosData = ref([
    { nome: 'JOAO SILVA', cpf: '***.123.456-**', cadunico: 'Não', mandado: 'Não', numSociedades: 3 },
    { nome: 'MARIA SANTOS', cpf: '***.789.012-**', cadunico: 'Sim', mandado: 'Não', numSociedades: 1 },
    { nome: 'JOSE OLIVEIRA', cpf: '***.345.678-**', cadunico: 'Não', mandado: 'Sim', numSociedades: 12 }
]);

const empresasSocio = ref([
    { cnpj: '10000180000156', uf: 'RJ', municipio: 'Cordeiro', situacao: 'ATIVADA' },
    { cnpj: '10135250000115', uf: 'SC', municipio: 'Ipumirim', situacao: 'BAIXADA' }
]);

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
    color: var(--accent-color);
}

.panel-kpi .unit {
    font-size: 1rem;
    font-weight: 400;
    color: var(--text-color);
}

.shadow-card {
  background: var(--card-bg);
  border-radius: 16px;
  padding: 1.5rem;
  box-shadow: 0 1px 3px rgba(0,0,0,0.1);
  border: 1px solid var(--navbar-border);
}

.panel.highlight {
    border-top: 4px solid var(--accent-color);
}

.section-header {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  margin-bottom: 0.5rem;
}

.section-header h3 { font-size: 0.8rem; font-weight: 700; margin: 0; text-transform: uppercase; color: var(--text-color); }

.placeholder-text {
    padding: 2rem;
    text-align: center;
    opacity: 0.3;
}
</style>
