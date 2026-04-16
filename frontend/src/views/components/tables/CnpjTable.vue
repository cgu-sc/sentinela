<script setup>
import { computed, ref, watch } from 'vue';
import { useRouter } from 'vue-router';
import { useAnalyticsStore } from '@/stores/analytics';
import { useFilterStore } from '@/stores/filters';
import { useRiskMetrics } from '@/composables/useRiskMetrics';
import { useFormatting } from '@/composables/useFormatting';
import { useTableAggregation } from '@/composables/useTableAggregation';
import { useDelayedLoading } from '@/composables/useDelayedLoading';
import { storeToRefs } from 'pinia';
import { FILTER_OPTIONS } from '@/config/filterOptions';
import { extractCnpjRaiz } from '@/composables/useParsing';
import { AUDIT_THRESHOLDS } from '@/config/riskConfig';
import { useStatusClass } from '@/composables/useStatusClass';
import DataTable from 'primevue/datatable';
import Column from 'primevue/column';
import Tag from 'primevue/tag';

const router = useRouter();
const analyticsStore = useAnalyticsStore();
const filterStore = useFilterStore();

const goToDetail = (event) => {
  // Ignora cliques em badges para não conflitar com os filtros
  if (event.originalEvent?.target?.closest('.clickable-badge')) return;
  router.push({ name: 'EstablishmentDetail', params: { cnpj: event.data.cnpj } });
};
const { resultadoCnpjs, isLoading } = storeToRefs(analyticsStore);
const { getRiskClass } = useRiskMetrics();
const { formatBRL, formatPercent } = useFormatting();
const { situacaoRfClass, conexaoMsClass } = useStatusClass();

// Mantém os dados anteriores visíveis durante o re-fetch, evitando flash de tabela vazia
const cachedCnpjs = ref(resultadoCnpjs.value);
const showRefreshing = useDelayedLoading(isLoading);
watch([resultadoCnpjs, isLoading], ([newData, loading]) => {
  if (newData?.length > 0 && !loading) cachedCnpjs.value = newData;
}, { immediate: true });

// Agregação de rodapé
const { totals } = useTableAggregation(cachedCnpjs, {
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
  if (field === 'grandeRede') {
    const valStr = typeof value === 'boolean' ? (value ? 'Sim' : 'Não') : value;
    filterStore.selectedGrandeRede = normalizeToOption(FILTER_OPTIONS.grandeRede, valStr);
  }
  if (field === 'situacaoRF') filterStore.selectedSituacao   = normalizeToOption(FILTER_OPTIONS.situacao,   value);
  if (field === 'conexaoMS') {
    const valStr = typeof value === 'boolean' ? (value ? 'Ativa' : 'Inativa') : value;
    filterStore.selectedMS = normalizeToOption(FILTER_OPTIONS.ms, valStr);
  }
}

// Classificação de cor — delegada ao composable useStatusClass
// (situacaoRfClass e conexaoMsClass importados acima)

// Helper para exibir a localização formatada adequadamente
const filteredLocation = computed(() => {
  if (filterStore.selectedMunicipio && filterStore.selectedMunicipio !== 'Todos') {
    return filterStore.selectedMunicipio.split('|')[0];
  }
  if (filterStore.selectedUF && filterStore.selectedUF !== 'Todos') {
    return filterStore.selectedUF;
  }
  return 'Brasil';
});

</script>

<template>
  <div class="table-section shadow-card modern-scroll-card" :class="{ 'is-refreshing': showRefreshing }">
    <div class="section-header">
       <div class="header-icon-box">
         <i class="pi pi-briefcase"></i>
       </div>
       <div class="header-text-box">
         <h3>Análise por CNPJ</h3>
         <span class="subtitle">{{ filteredLocation }} — {{ cachedCnpjs.length }} Estabelecimentos</span>
       </div>
       <div class="spacer"></div>
    </div>

    <DataTable
      :value="cachedCnpjs"
      size="small"
      stripedRows
      removableSort
      paginator
      :rows="20"
      sortField="valSemComp"
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
          
          <Column field="uf" header="UF" sortable style="width: 5%" />

          <Column field="municipio" header="Município" sortable style="width: 10%">
            <template #body="slotProps">
              <span
                v-tooltip.top="slotProps.data.municipio?.length > 14 ? slotProps.data.municipio : undefined"
                class="razao-social-cell"
              >{{ slotProps.data.municipio?.length > 14 ? slotProps.data.municipio.slice(0, 14) + '…' : slotProps.data.municipio }}</span>
            </template>
          </Column>

          <Column field="razao_social" header="Razão Social" sortable style="width: 18%">
             <template #body="slotProps">
                <span
                  v-tooltip.top="slotProps.data.razao_social?.length > 20 ? slotProps.data.razao_social : undefined"
                  class="razao-social-cell"
                >{{ slotProps.data.razao_social?.length > 20 ? slotProps.data.razao_social.slice(0, 20) + '…' : slotProps.data.razao_social }}</span>
             </template>
          </Column>

          <Column field="totalMov" header="Valor Total Vendas" sortable style="width: 10%">
             <template #body="slotProps">
                <span>{{ formatBRL(slotProps.data.totalMov) }}</span>
             </template>
             <template #footer>{{ tableFooter.totalMov }}</template>
          </Column>

          <Column field="valSemComp" header="Valor sem Comprovação" sortable style="width: 10%">
             <template #body="slotProps">
                <span :class="{ 'high-value-audit': slotProps.data.valSemComp >= AUDIT_THRESHOLDS.HIGH_VALUE }">
                  {{ formatBRL(slotProps.data.valSemComp) }}
                </span>
             </template>
             <template #footer>{{ tableFooter.valSemComp }}</template>
          </Column>

          <Column field="percValSemComp" header="% Valor sem Comprovação" sortable style="width: 8%">
             <template #body="slotProps">
                <Tag :value="formatPercent(slotProps.data.percValSemComp)" :class="getRiskClass(slotProps.data.percValSemComp) === 'risk-critical' ? 'risk-high' : getRiskClass(slotProps.data.percValSemComp)" />
             </template>
             <template #footer>{{ tableFooter.percValSemComp }}</template>
          </Column>

          <Column field="is_grande_rede" header="Grande Rede" sortable style="width: 7%">
            <template #body="slotProps">
                <Tag
                  :value="slotProps.data.is_grande_rede ? 'Sim' : 'Não'"
                  :class="[slotProps.data.is_grande_rede ? 'status-info' : 'status-secondary', 'clickable-badge']"
                  v-tooltip.top="'Filtrar por Grande Rede: ' + (slotProps.data.is_grande_rede ? 'Sim' : 'Não')"
                  @click="applyFilter('grandeRede', slotProps.data.is_grande_rede)"
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
                  :class="[situacaoRfClass(slotProps.data.situacao_rf), 'clickable-badge']"
                  v-tooltip.top="'Filtrar por Situação RF: ' + slotProps.data.situacao_rf"
                  @click="applyFilter('situacaoRF', slotProps.data.situacao_rf)"
                />
            </template>
          </Column>

          <Column field="is_conexao_ativa" header="Conexão MS" sortable style="width: 7%">
            <template #body="slotProps">
                <Tag
                  :value="slotProps.data.is_conexao_ativa ? 'Ativa' : 'Inativa'"
                  :class="[conexaoMsClass(slotProps.data.is_conexao_ativa), 'clickable-badge']"
                  v-tooltip.top="'Filtrar por Conexão MS: ' + (slotProps.data.is_conexao_ativa ? 'Ativa' : 'Inativa')"
                  @click="applyFilter('conexaoMS', slotProps.data.is_conexao_ativa)"
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
  transition: opacity 0.25s ease;
}

.modern-scroll-card {
  border: 1px solid var(--card-border);
  background: var(--card-bg);
}

.section-header {
  padding: 1.25rem 1.5rem;
  display: flex;
  align-items: center;
  gap: 1rem;
  border-bottom: 1px solid var(--tabs-border);
}

.header-icon-box {
  width: 42px;
  height: 42px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: color-mix(in srgb, var(--accent-indigo) 10%, transparent);
  color: var(--accent-indigo);
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
  opacity: 0.45;
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
  background: var(--scrollbar-thumb);
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
  background: color-mix(in srgb, var(--accent-indigo)    18%, transparent);
  border: 1px solid color-mix(in srgb, var(--accent-indigo)    35%, transparent);
  color: var(--accent-indigo);
}

.tipo-badge.filial {
  background: color-mix(in srgb, var(--status-secondary) 12%, transparent);
  border: 1px solid color-mix(in srgb, var(--status-secondary) 20%, transparent);
  color: var(--status-secondary);
}

/* ── ESTILOS DE BADGES PREMIUM (Sincronizados com o novo colors.js) ── */
:deep(.p-tag) {
  padding: 0.25rem 0.65rem;
  border-radius: 6px;
  font-weight: 700;
  font-size: 0.82rem;
  border: 1px solid transparent;
}

/* ESTILOS DE BADGES (Sincronizados globalmente via components.css) */

/* ESTILO ROSE/ALERTA (Sincronizado via global components.css) */

:deep(.clickable-badge) {
  cursor: pointer;
  transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
}
:deep(.clickable-badge:hover) {
  opacity: 1;
  transform: translateY(-1px);
  filter: brightness(0.95);
  box-shadow: 0 2px 4px rgba(0,0,0,0.05);
}

/* RESET DE CAIXA ALTA FORÇADA */
:deep(.p-datatable-tbody td),
:deep(.p-tag-value),
:deep(.p-tag) {
  text-transform: none !important;
  font-variant: normal !important;
}


/* DESTAQUE DE ALTO VALOR (VALOR SEM COMPROVAÇÃO) */
.high-value-audit {
  color: var(--risk-high);
  font-weight: 700;
  font-size: 0.82rem;
  display: inline-flex;
  align-items: center;
  gap: 0.4rem;
  padding: 0.25rem 0.65rem;
  background: color-mix(in srgb, var(--risk-high) 10%, transparent);
  border-left: 3px solid var(--risk-high);
  border-radius: 0 6px 6px 0;
}
</style>
