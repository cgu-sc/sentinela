<script setup>
import { computed } from 'vue';
import { useRouter } from 'vue-router';
import { useAnalyticsStore } from '@/stores/analytics';
import { useFilterStore } from '@/stores/filters';
import { useRiskMetrics } from '@/composables/useRiskMetrics';
import { useFormatting } from '@/composables/useFormatting';
import { useTableAggregation } from '@/composables/useTableAggregation';
import { storeToRefs } from 'pinia';
import { FILTER_OPTIONS } from '@/config/filterOptions';
import { extractCnpjRaiz } from '@/composables/useParsing';
import DataTable from 'primevue/datatable';
import Column from 'primevue/column';
import Tag from 'primevue/tag';

const router = useRouter();
const analyticsStore = useAnalyticsStore();
const filterStore = useFilterStore();

const goToDetail = (event) => {
  // Ignora cliques em badges para não conflitar com os filtros
  if (event.originalEvent?.target?.closest('.clickable-badge')) return;
  router.push({ name: 'CnpjDetail', params: { cnpj: event.data.cnpj } });
};
const { resultadoCnpjs, isLoading } = storeToRefs(analyticsStore);
const { getRiskClass } = useRiskMetrics();
const { formatBRL, formatPercent } = useFormatting();

// Agregação de rodapé
const { totals } = useTableAggregation(resultadoCnpjs, {
  sums: ['valSemComp', 'totalMov'],
  percents: [
    { field: 'percValSemComp',  numerator: 'valSemComp',  denominator: 'totalMov'   },
  ],
});

const tableFooter = computed(() => {
  const t = totals.value;
  if (!Object.keys(t).length) return {};
  return {
    percValSemComp: formatPercent(t.percValSemComp),
    valSemComp:     formatBRL(t.valSemComp),
    totalMov:       formatBRL(t.totalMov),
  };
});

// Normaliza o valor bruto da API para o valor aceito pelo filtro (case-insensitive)
function normalizeToOption(options, raw) {
  return options.find(o => o.toLowerCase() === raw?.toLowerCase()) ?? raw;
}

// Filtros clicáveis nos badges
function applyFilter(field, value) {
  if (field === 'grandeRede')  filterStore.selectedGrandeRede = normalizeToOption(FILTER_OPTIONS.grandeRede, value);
  if (field === 'situacaoRF') filterStore.selectedSituacao   = normalizeToOption(FILTER_OPTIONS.situacao,   value);
  if (field === 'conexaoMS')  filterStore.selectedMS         = normalizeToOption(FILTER_OPTIONS.ms,         value);
}

// Helper para exibir o município formatado adequadamente
const filteredLocation = computed(() => {
  if (filterStore.selectedMunicipio && filterStore.selectedMunicipio !== 'Todos') {
    return filterStore.selectedMunicipio.split('|')[0];
  }
  return '';
});

</script>

<template>
  <div class="table-section shadow-card modern-scroll-card" :class="{ 'is-refreshing': isLoading }">
    <div class="section-header">
       <div class="header-icon-box">
         <i class="pi pi-briefcase"></i>
       </div>
       <div class="header-text-box">
         <h3>ANÁLISE POR CNPJ</h3>
         <span class="subtitle">{{ filteredLocation }} — {{ resultadoCnpjs.length }} Estabelecimentos</span>
       </div>
       <div class="spacer"></div>
    </div>

    <DataTable
      :value="resultadoCnpjs"
      size="small"
      stripedRows
      removableSort
      paginator
      :rows="20"
      sortField="percValSemComp"
      :sortOrder="-1"
      class="custom-table enterprise-table clickable-rows"
      @row-click="goToDetail"
    >
          <Column field="cnpj" header="CNPJ" sortable style="width: 10%">
            <template #body="slotProps">
              <div class="cnpj-cell">
                <span
                  v-tooltip.top="slotProps.data.is_matriz ? 'Matriz' : 'Filial'"
                  :class="slotProps.data.is_matriz ? 'tipo-badge matriz' : 'tipo-badge filial'"
                >
                  <i :class="slotProps.data.is_matriz ? 'pi pi-home' : 'pi pi-building'"></i>
                </span>
                {{ slotProps.data.cnpj }}
              </div>
            </template>
            <template #footer>TOTAL</template>
          </Column>
          
          <Column field="razao_social" header="Razão Social" sortable style="width: 18%">
             <template #body="slotProps">
                <span
                  v-tooltip.top="slotProps.data.razao_social?.length > 20 ? slotProps.data.razao_social : undefined"
                  class="razao-social-cell"
                >{{ slotProps.data.razao_social?.length > 20 ? slotProps.data.razao_social.slice(0, 20) + '…' : slotProps.data.razao_social }}</span>
             </template>
          </Column>

          <Column field="totalMov" header="Total Vendas" sortable style="width: 10%">
             <template #body="slotProps">
                <span>{{ formatBRL(slotProps.data.totalMov) }}</span>
             </template>
             <template #footer>{{ tableFooter.totalMov }}</template>
          </Column>

          <Column field="valSemComp" header="Total Sem Comprovação" sortable style="width: 10%">
             <template #body="slotProps">
                <span>{{ formatBRL(slotProps.data.valSemComp) }}</span>
             </template>
             <template #footer>{{ tableFooter.valSemComp }}</template>
          </Column>

          <Column field="percValSemComp" header="% Valor s/ Comp" sortable style="width: 8%">
             <template #body="slotProps">
                <Tag :value="formatPercent(slotProps.data.percValSemComp)" :class="getRiskClass(slotProps.data.percValSemComp)" />
             </template>
             <template #footer>{{ tableFooter.percValSemComp }}</template>
          </Column>

          <Column field="flag_grandes_redes" header="Grande Rede" sortable style="width: 7%">
            <template #body="slotProps">
                <Tag
                  :value="slotProps.data.flag_grandes_redes"
                  :class="[slotProps.data.flag_grandes_redes === 'Sim' ? 'status-info' : 'status-secondary', 'clickable-badge']"
                  v-tooltip.top="'Filtrar por Grande Rede: ' + slotProps.data.flag_grandes_redes"
                  @click="applyFilter('grandeRede', slotProps.data.flag_grandes_redes)"
                />
            </template>
          </Column>

          <Column field="qtd_estabelecimentos_rede" header="Estab. Rede" sortable style="width: 7%">
            <template #body="slotProps">
                <Tag
                  v-if="slotProps.data.qtd_estabelecimentos_rede > 1"
                  :value="String(slotProps.data.qtd_estabelecimentos_rede)"
                  class="status-info clickable-badge"
                  v-tooltip.top="'Ver todos os estabelecimentos desta rede'"
                  @click="filterStore.selectedCnpjRaiz = extractCnpjRaiz(slotProps.data.cnpj)"
                />
                <Tag
                  v-else
                  :value="String(slotProps.data.qtd_estabelecimentos_rede)"
                  class="status-secondary"
                />
            </template>
          </Column>

          <Column field="situacao_rf" header="Situação RF" sortable style="width: 7%">
            <template #body="slotProps">
                <Tag
                  :value="slotProps.data.situacao_rf"
                  :class="[slotProps.data.situacao_rf?.toUpperCase() === 'ATIVA' ? 'status-success' : 'status-danger', 'clickable-badge']"
                  v-tooltip.top="'Filtrar por Situação RF: ' + slotProps.data.situacao_rf"
                  @click="applyFilter('situacaoRF', slotProps.data.situacao_rf)"
                />
            </template>
          </Column>

          <Column field="conexao_ms" header="Conexão MS" sortable style="width: 7%">
            <template #body="slotProps">
                <Tag
                  :value="slotProps.data.conexao_ms"
                  :class="[slotProps.data.conexao_ms?.toUpperCase() === 'ATIVA' ? 'status-success' : 'status-danger', 'clickable-badge']"
                  v-tooltip.top="'Filtrar por Conexão MS: ' + slotProps.data.conexao_ms"
                  @click="applyFilter('conexaoMS', slotProps.data.conexao_ms)"
                />
            </template>
          </Column>
    </DataTable>
  </div>
</template>

<style scoped>
:deep(.clickable-rows .p-datatable-tbody > tr) {
  cursor: pointer;
  transition: background-color 0.15s ease;
}

.table-section {
  display: flex;
  flex-direction: column;
  transition: all 0.3s ease;
}

.modern-scroll-card {
  border: 1px solid var(--sidebar-border, #e2e8f0);
  background: var(--card-bg, #ffffff);
}

.section-header {
  padding: 1.25rem 1.5rem;
  display: flex;
  align-items: center;
  gap: 1rem;
  border-bottom: 1px solid var(--sidebar-border, #e2e8f0);
}

.header-icon-box {
  width: 42px;
  height: 42px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(99, 102, 241, 0.1);
  color: #6366f1;
  border-radius: 10px;
  font-size: 1.25rem;
}

.header-text-box h3 {
  margin: 0;
  font-size: 1.1rem;
  font-weight: 700;
  letter-spacing: -0.01em;
}

.subtitle {
  font-size: 0.85rem;
  color: var(--text-muted, #64748b);
}

.spacer { flex: 1; }

.is-refreshing {
  opacity: 0.5;
  pointer-events: none;
}

:deep(.p-datatable-thead) {
  position: sticky;
  top: 0;
  z-index: 10;
}

:deep(.p-datatable-wrapper) {
  border-radius: 0 0 12px 12px;
}

:deep(.p-datatable-wrapper::-webkit-scrollbar) {
  width: 8px;
}
:deep(.p-datatable-wrapper::-webkit-scrollbar-track) {
  background: var(--bg-color, #f8fafc);
}
:deep(.p-datatable-wrapper::-webkit-scrollbar-thumb) {
  background: var(--sidebar-border, #e2e8f0);
  border-radius: 10px;
}
:deep(.p-datatable-wrapper::-webkit-scrollbar-thumb:hover) {
  background: #cbd5e1;
}

.razao-social-cell {
  cursor: default;
  white-space: nowrap;
}

.cnpj-cell {
  display: flex;
  align-items: center;
  gap: 0.4rem;
}

.tipo-badge {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 22px;
  height: 22px;
  border-radius: 6px;
  font-size: 0.7rem;
  flex-shrink: 0;
  backdrop-filter: blur(6px);
  -webkit-backdrop-filter: blur(6px);
}

.tipo-badge.matriz {
  background: rgba(99, 102, 241, 0.18);
  border: 1px solid rgba(99, 102, 241, 0.35);
  color: #818cf8;
}

.tipo-badge.filial {
  background: rgba(100, 116, 139, 0.12);
  border: 1px solid rgba(100, 116, 139, 0.2);
  color: #94a3b8;
}

:deep(.clickable-badge) {
  cursor: pointer;
  transition: opacity 0.15s ease, transform 0.1s ease;
}
:deep(.clickable-badge:hover) {
  opacity: 0.8;
  transform: scale(1.08);
}

body.dark-mode .header-icon-box {
  background: rgba(99, 102, 241, 0.2);
  color: #818cf8;
}
</style>
