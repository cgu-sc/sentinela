<script setup>
import { ref } from 'vue';
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
const clusterOptions = ref(['Todos', 'Cluster 0 - Risco Crítico', 'Cluster 1 - Risco Alto', 'Cluster 2 - Risco Médio', 'Cluster 3 - Risco Baixo']);
const statusSelection = ref('Todos');
const statusOptions = ref(['Todos', 'ATIVA', 'BAIXADA', 'SUSPENSA', 'INAPTA']);
const rfaSelection = ref('Todos');
const rfaOptions = ref(['Todos', 'Acima de R$ 1 Mi', 'Entre R$ 500k e R$ 1 Mi', 'Até R$ 500k']);

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

/* TELEPORT FILTERS STYLES */
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

.kpi-mini-card {
    background: var(--card-bg);
    padding: 1rem 1.25rem;
    border-radius: 12px;
    border: 1px solid var(--sidebar-border);
    transition: transform 0.2s, background-color 0.3s ease;
    display: flex;
    align-items: center;
    gap: 1rem;
}

.kpi-mini-card:hover { 
  transform: translateY(-2px);
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
}

.kpi-mini-card.danger { box-shadow: inset 0 0 0 1px rgba(239, 68, 68, 0.2); border-color: rgba(239, 68, 68, 0.2); }

.kpi-content {
  display: flex;
  flex-direction: column;
}

.kpi-mini-card .label { font-size: 0.75rem; display: block; text-transform: uppercase; font-weight: 600; color: var(--text-color); }
.kpi-mini-card .value { font-size: 1.5rem; font-weight: 800; color: var(--text-color); }

.kpi-icon {
  width: 2.75rem;
  height: 2.75rem;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 0.5rem;
  font-size: 1.25rem;
}
.kpi-icon.total { background: rgba(99, 102, 241, 0.15); color: #6366f1; } /* Indigo */
.kpi-icon.danger { background: rgba(239, 68, 68, 0.15); color: #ef4444; } /* Red */


.main-grid {
    display: grid;
    grid-template-columns: 1fr 1.5fr;
    gap: 1.5rem;
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

.shadow-card {
  background: var(--card-bg);
  border-radius: 16px;
  padding: 1.5rem;
  box-shadow: 0 1px 3px rgba(0,0,0,0.1);
  border: 1px solid var(--navbar-border);
}

.section-header {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  margin-bottom: 1rem;
}

.section-header h3 { font-size: 1rem; font-weight: 700; margin: 0; }
</style>
