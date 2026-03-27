<script setup>
import { ref } from 'vue';
import { FILTER_OPTIONS } from '@/config/filterOptions';
import Card from 'primevue/card';
import DataTable from 'primevue/datatable';
import Column from 'primevue/column';
import Button from 'primevue/button';
import Dropdown from 'primevue/dropdown';
import InputText from 'primevue/inputtext';

// Filtro Principal
const searchTarget = ref('');

// Filtros Secundários
const clusterSelection = ref('Todos');
const clusterOptions = FILTER_OPTIONS.cluster;
const statusSelection = ref('Todos');
const statusOptions = FILTER_OPTIONS.situacao;
const rfaSelection = ref('Todos');
const rfaOptions = FILTER_OPTIONS.rfa;

// Mockup Data - Mapa de Clusters
const clusterStats = ref([
    { uf: 'AL', c0: 1, c7: 1, total: 2 },
    { uf: 'DF', c1: 1, c5: 2, total: 3 },
    { uf: 'ES', c0: 1, total: 1 },
    { uf: 'GO', c0: 49, c1: 12, c2: 5, c3: 13, c4: 7, c5: 1, c6: 6, c7: 9, total: 102 }
]);

const targetList = ref([
    { uf: 'DF', municipio: 'Brasília', cnpj: '10286770000104', vendas: 'R$ 209.460,12', semComp: 'R$ 191.423,68', perc: '91,39%' },
    { uf: 'MG', municipio: 'Belo Horizonte', cnpj: '10429168000170', vendas: 'R$ 400.160,60', semComp: 'R$ 247.592,42', perc: '61,87%' },
    { uf: 'SP', municipio: 'Campo Limpo Paulista', cnpj: '10813567000130', vendas: 'R$ 1.067.415,83', semComp: 'R$ 15.673,56', perc: '1,47%' },
    { uf: 'GO', municipio: 'Aparecida de Goiânia', cnpj: '11200762000158', vendas: 'R$ 292.339,74', semComp: 'R$ 231.860,36', perc: '79,31%' }
]);
</script>

<template>
  <div class="alvos-dashboard">
    <div class="top-row">
        <!-- KPI CARDS (RESUMIDO) -->
        <div class="kpi-mini-grid">
            <div class="kpi-mini-card">
                <div class="kpi-icon total">
                    <i class="pi pi-th-large"></i>
                </div>
                <div class="kpi-content">
                    <span class="label">Total CNPJs</span>
                    <span class="value">102</span>
                </div>
            </div>
            <div class="kpi-mini-card danger">
                <div class="kpi-icon danger">
                    <i class="pi pi-exclamation-triangle"></i>
                </div>
                <div class="kpi-content">
                    <span class="label">Sem Comprovação</span>
                    <span class="value">R$ 9 Mi</span>
                </div>
            </div>
        </div>

        <!-- TABELA DE CLUSTERS -->
        <div class="cluster-table shadow-card">
            <div class="section-header">
                <i class="pi pi-th-large"></i>
                <h3>UF/Município e Cluster</h3>
            </div>
            <DataTable :value="clusterStats" size="small" class="custom-table">
                <Column field="uf" header="UF"></Column>
                <Column field="c0" header="0"></Column>
                <Column field="c1" header="1"></Column>
                <Column field="c5" header="5"></Column>
                <Column field="total" header="Total" class="font-bold"></Column>
            </DataTable>
        </div>
    </div>

    <!-- MAPA & TABELA DETALHADA -->
    <div class="main-grid">
        <div class="map-section shadow-card">
            <div class="section-header">
                <i class="pi pi-map-marker"></i>
                <h3>Mapa de Concentração de Alvos</h3>
            </div>
            <div class="map-placeholder">
                <i class="pi pi-map text-5xl opacity-10"></i>
                <p>Mapa do Brasil (Clusters)</p>
            </div>
        </div>

        <div class="detail-section shadow-card">
            <div class="section-header">
                <i class="pi pi-list"></i>
                <h3>Detalhamento dos Alvos</h3>
            </div>
            <DataTable :value="targetList" size="small" stripedRows paginator :rows="5">
                <Column field="uf" header="UF"></Column>
                <Column field="municipio" header="Município"></Column>
                <Column field="cnpj" header="CNPJ"></Column>
                <Column field="semComp" header="Sem Comp."></Column>
                <Column field="perc" header="%">
                    <template #body="slotProps">
                        <span :class="{'text-red-500 font-bold': parseFloat(slotProps.data.perc) > 50}">
                            {{ slotProps.data.perc }}
                        </span>
                    </template>
                </Column>
            </DataTable>
        </div>
    </div>
  </div>
</template>

<style scoped>
.alvos-dashboard {
    display: flex;
    flex-direction: column;
    gap: 1.5rem;
}



:global(.input-search-icon i) {
  margin-top: -0.5rem;
}

.top-row {
    display: grid;
    grid-template-columns: 250px 1fr;
    gap: 1.5rem;
}

.kpi-mini-grid {
    display: flex;
    flex-direction: column;
    gap: 1rem;
}

.map-placeholder {
    height: 400px;
    background: color-mix(in srgb, var(--primary-color) 5%, transparent);
    border-radius: 12px;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    border: 2px dashed var(--sidebar-border);
}
</style>
