<script setup>
import { ref } from 'vue';
import { FILTER_OPTIONS } from '@/config/filterOptions';
import Card from 'primevue/card';
import DataTable from 'primevue/datatable';
import Column from 'primevue/column';
import Button from 'primevue/button';
import Dropdown from 'primevue/dropdown';
import InputText from 'primevue/inputtext';

import { CLUSTER_STATS_DEMO, TARGET_LIST_DEMO } from '@/mocks/demoData';

// Filtro Principal
const searchTarget = ref('');

// Filtros Secundários
const clusterSelection = ref('Todos');
const clusterOptions = FILTER_OPTIONS.cluster;
const statusSelection = ref('Todos');
const statusOptions = FILTER_OPTIONS.situacao;
const rfaSelection = ref('Todos');
const rfaOptions = FILTER_OPTIONS.rfa;

// Data (Mocks centralizados)
const clusterStats = ref(CLUSTER_STATS_DEMO);
const targetList = ref(TARGET_LIST_DEMO);
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
