<script setup>
/**
 * RegionalPharmacyTable.vue
 * Ranking de farmácias da Região de Saúde ordenado por Score de Risco.
 * A classificação de risco usa o campo `classificacao_risco` da matriz_risco_consolidada,
 * espelhando a lógica da coluna "Classificação" do relatório Excel (aba_regiao.py).
 * A coluna "Conexão" usa o campo `conexao_ms` já presente no backend.
 */
import { computed } from 'vue';
import { useRouter } from 'vue-router';
import { useFormatting } from '@/composables/useFormatting';
import { RISK_THRESHOLDS, RISK_CSS_CLASSES, AUDIT_THRESHOLDS } from '@/config/riskConfig';
import DataTable from 'primevue/datatable';
import Column from 'primevue/column';
import Tag from 'primevue/tag';

const props = defineProps({
  /** Array de objetos RegionalFarmaciaSchema vindos da API */
  farmacias: { type: Array, default: () => [] },
  /** CNPJ atualmente em análise (se vier do CnpjDetailView), para destacar a linha */
  cnpjAtual: { type: String, default: null },
  /** Município de referência para destaque de grupo */
  municipioAtual: { type: String, default: null },
  /** UF de referência para destaque de grupo */
  ufAtual: { type: String, default: null },
});

const router = useRouter();
const { formatBRL, formatPercent, formatTitleCase } = useFormatting();

const goToDetail = (event) => {
  // Gera o link para o CNPJ clicado e abre em uma nova aba (mais prático para comparação)
  const routeDetail = router.resolve({ 
    name: 'CnpjDetail', 
    params: { cnpj: event.data.cnpj } 
  });
  window.open(routeDetail.href, '_blank');
};

/** Mapeia a string de classificação para a classe CSS de risco do sistema. */
function classifToRiskClass(classif) {
  if (!classif) return 'risk-low';
  const c = classif.toUpperCase();
  if (c.includes('CRÍT') || c.includes('CRIT')) return 'risk-critical';
  if (c.includes('ALTO'))                        return 'risk-high';
  if (c.includes('MÉDIO') || c.includes('MEDIO')) return 'risk-medium';
  return 'risk-low';
}

/** Formata o rótulo de classificação para Capitalizado (ex: CRÍTICO -> Crítico) */
function formatClassifLabel(v) {
  return formatTitleCase(v);
}

/** Classe CSS para a coluna Conexão MS. */
function conexaoClass(v) {
  return v?.toUpperCase() === 'ATIVA' ? 'status-success' : 'status-danger';
}

/** Row class para destacar apenas o CNPJ em análise (Forte). */
function rowClass(data) {
  if (props.cnpjAtual && data.cnpj === props.cnpjAtual) return 'row-highlight';
  return '';
}

/** Calcula a classe de risco para o percentual com base no config global. */
function getPercentClass(v) {
  if (v == null) return 'status-secondary';
  if (v >= RISK_THRESHOLDS.CRITICAL) return RISK_CSS_CLASSES.CRITICAL;
  if (v >= RISK_THRESHOLDS.HIGH)     return RISK_CSS_CLASSES.HIGH;
  if (v >= RISK_THRESHOLDS.MEDIUM)   return RISK_CSS_CLASSES.MEDIUM;
  return RISK_CSS_CLASSES.LOW;
}

/** Totais para o rodapé da tabela */
const totals = computed(() => {
  const semComp = props.farmacias.reduce((s, f) => s + (f.valSemComp || 0), 0);
  const total   = props.farmacias.reduce((s, f) => s + (f.totalMov   || 0), 0);
  // Multiplicamos por 100 para bater com a escala 0-100 das linhas
  const perc    = total > 0 ? (semComp / total) * 100 : 0;
  
  // Cálculo da média de Score
  const scoreSum = props.farmacias.reduce((s, f) => s + (f.score_risco || 0), 0);
  const avgScore = props.farmacias.length > 0 ? scoreSum / props.farmacias.length : 0;

  return { semComp, total, perc, avgScore };
});
</script>

<template>
  <div class="table-section">
    <div class="section-header">
      <i class="pi pi-chart-bar section-icon"></i>
      <div class="header-text-box">
        <h3 class="section-title-text">Ranking de Risco da Região</h3>
        <p class="subtitle">{{ farmacias.length }} estabelecimentos · Score de Risco</p>
      </div>
    </div>

    <DataTable
      :value="farmacias"
      size="small"
      removableSort
      paginator
      :rows="15"
      sortField="score_risco"
      :sortOrder="-1"
      :row-class="rowClass"
      class="custom-table enterprise-table clickable-rows"
      @row-click="goToDetail"
    >
      <!-- Ranking -->
      <Column field="rank" header="#" sortable style="width: 3%" bodyStyle="text-align:center; font-weight:700; color: var(--text-muted)" />
      <!-- CNPJ -->
      <Column field="cnpj" header="CNPJ" sortable style="width: 9%">
        <template #body="{ data }">
          <span class="cnpj-text">{{ data.cnpj }}</span>
        </template>
      </Column>
      <Column field="razao_social" header="Razão Social" sortable style="width: 14%; text-transform: none" footerStyle="text-align: right">
        <template #body="{ data }">
          <span
            v-tooltip.top="data.razao_social?.length > 20 ? data.razao_social : undefined"
            class="razao-social-cell"
          >{{ formatTitleCase(data.razao_social?.length > 20 ? data.razao_social.slice(0, 20) + '…' : data.razao_social) }}</span>
        </template>
        <template #footer>
          <span class="f-footer-label">Totais da Região:</span>
        </template>
      </Column>
      <!-- Município -->
      <Column field="municipio" header="Município" sortable style="width: 10%; text-transform: none">
        <template #body="{ data }">
          {{ formatTitleCase(data.municipio) }}
        </template>
      </Column>
      <Column field="score_risco" header="Score" sortable style="width: 6%" bodyStyle="text-align:center" footerStyle="text-align: center">
        <template #body="{ data }">
          <span
            v-if="data.score_risco != null"
            class="score-text"
          >{{ data.score_risco?.toFixed(2) }}</span>
          <span v-else class="text-muted">—</span>
        </template>
        <template #footer>
          {{ totals.avgScore.toFixed(2) }}
        </template>
      </Column>
      <!-- Classificação -->
      <Column field="classificacao_risco" header="Classificação" sortable style="width: 10%">
        <template #body="{ data }">
          <Tag
            v-if="data.classificacao_risco"
            :value="formatClassifLabel(data.classificacao_risco)"
            :class="classifToRiskClass(data.classificacao_risco)"
          />
          <span v-else class="text-muted">—</span>
        </template>
      </Column>
      <Column field="valSemComp" header="Valor s/ Comp." sortable style="width: 10%" bodyStyle="text-align:right" footerStyle="text-align: right">
        <template #body="{ data }">
          <span :class="{ 'high-value-audit': data.valSemComp >= AUDIT_THRESHOLDS.HIGH_VALUE }">
            {{ formatBRL(data.valSemComp) }}
          </span>
        </template>
        <template #footer>
          {{ formatBRL(totals.semComp) }}
        </template>
      </Column>
      <Column field="totalMov" header="Valor Total" sortable style="width: 10%" bodyStyle="text-align:right" footerStyle="text-align: right">
        <template #body="{ data }">{{ formatBRL(data.totalMov) }}</template>
        <template #footer>
          {{ formatBRL(totals.total) }}
        </template>
      </Column>
      <Column field="percValSemComp" header="% s/ Comp." sortable style="width: 10%" bodyStyle="text-align:center" footerStyle="text-align: center">
        <template #body="{ data }">
          <Tag :value="formatPercent(data.percValSemComp)" :class="getPercentClass(data.percValSemComp)" />
        </template>
        <template #footer>
          {{ formatPercent(totals.perc) }}
        </template>
      </Column>
      <Column field="data_ultima_venda" header="Última Venda" sortable style="width: 10%" bodyStyle="text-align:center">
        <template #body="{ data }">
          <span v-if="data.data_ultima_venda">
            {{ new Date(data.data_ultima_venda).toLocaleDateString('pt-BR') }}
          </span>
          <span v-else class="text-muted">—</span>
        </template>
      </Column>
      <Column field="conexao_ms" header="Conexão MS" sortable style="width: 8%" bodyStyle="text-align:center">
        <template #body="{ data }">
          <Tag :value="data.conexao_ms ?? '—'" :class="conexaoClass(data.conexao_ms)" />
        </template>
      </Column>
    </DataTable>
  </div>
</template>

<style scoped>
.table-section {
  display: flex;
  flex-direction: column;
  background: var(--tabs-bg);
  border: 1px solid var(--tabs-border);
  border-radius: 12px;
  padding: 1.25rem;
  box-shadow: 0 4px 15px rgba(0,0,0,0.1);
}

.section-header {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  padding: 0.5rem 0;
  border-bottom: 1px solid var(--tabs-border);
  margin-bottom: 1rem;
}

.section-icon {
  font-size: 1rem;
  color: var(--primary-color);
}

.header-text-box {
  display: flex;
  flex-direction: column;
}

.header-text-box h3 {
  margin: 0;
  padding: 0;
}

.header-text-box p {
  margin: 0;
  padding: 0;
}

.section-title-text {
  font-size: 0.85rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--text-color);
}

.subtitle {
  font-size: 0.85rem;
  color: var(--text-muted, #64748b);
}

.cnpj-text {
  font-family: monospace;
  font-size: 0.75rem;
  letter-spacing: 0.2px;
}

.razao-social-cell,
.municipio-cell {
  white-space: nowrap;
  text-transform: none !important;
  font-variant: normal !important;
}

.text-muted {
  color: var(--text-muted, #94a3b8);
  font-size: 0.8rem;
}

/* Score text — Cor padrão (limpeza visual) */
.score-text {
  font-size: 0.75rem;
  font-weight: 700;
  color: var(--text-color);
}

/* Linha do CNPJ específico em análise (Estilo Hover Persistente) */
:deep(.p-datatable-tbody > tr.row-highlight > td) {
  background: color-mix(in srgb, var(--primary-color) 8%, var(--tabs-bg)) !important;
}

:deep(.p-datatable-tbody > tr.row-highlight > td:first-child) {
  border-left: 4px solid var(--primary-color) !important;
}

:deep(.enterprise-table .p-datatable-tbody > tr.row-highlight td:first-child) {
  border-left: 4px solid var(--primary-color) !important;
}

/* DESTAQUE DE ALTO VALOR (VALOR SEM COMPROVAÇÃO) */
.high-value-audit {
  color: var(--risk-high);
  font-weight: 700;
  font-size: 0.75rem;
  display: inline-flex;
  align-items: center;
  gap: 0.3rem;
  padding: 0.15rem 0.5rem;
  background: color-mix(in srgb, var(--risk-high) 10%, transparent);
  border-left: 3px solid var(--risk-high);
  border-radius: 0 4px 4px 0;
}

/* Linhas do mesmo município (Sutil) */
:deep(.p-datatable-tbody > tr.municipio-highlight > td) {
  background: color-mix(in srgb, var(--primary-color) 6%, var(--tabs-bg)) !important;
}

/* Linha de dados — Hover Neutro Suave 4% */
.f-row:hover td {
  background: color-mix(in srgb, var(--text-color) 4%, var(--tabs-bg)) !important;
}

:deep(.enterprise-table .p-datatable-tbody > tr.municipio-highlight td:first-child) {
  border-left: 2px solid color-mix(in srgb, var(--primary-color) 40%, transparent) !important;
}

:deep(.p-datatable),
:deep(.p-datatable-wrapper),
:deep(.p-datatable-table),
:deep(.p-datatable-thead > tr > th),
:deep(.p-datatable-tbody > tr > td) {
  background: var(--tabs-bg) !important;
  background-color: var(--tabs-bg) !important;
}

:deep(.p-datatable .p-datatable-thead > tr > th) {
  color: var(--text-secondary) !important;
  font-size: 0.72rem !important;
  font-weight: 600 !important;
  text-transform: uppercase !important;
  letter-spacing: 0.04em !important;
  border-bottom: 2px solid var(--tabs-border) !important;
  padding: 0.65rem 0.5rem !important;
  line-height: 1.1 !important;
}

:deep(.p-datatable .p-datatable-tbody > tr > td) {
  border-bottom: 1px solid var(--tabs-border) !important;
  font-size: 0.75rem !important;
}

:deep(.p-datatable .p-datatable-tbody > tr:hover > td) {
  background: color-mix(in srgb, var(--text-color) 4%, var(--tabs-bg)) !important;
  cursor: pointer;
}

:deep(.p-datatable-thead) {
  position: sticky;
  top: 0;
  z-index: 10;
  background: var(--tabs-bg) !important;
}

:deep(.p-datatable .p-datatable-tfoot > tr > td) {
  background: color-mix(in srgb, var(--tabs-bg) 95%, var(--text-color) 5%) !important;
  border-top: 2px solid var(--tabs-border) !important;
  font-weight: 600 !important;
  font-size: 0.75rem !important;
  color: var(--text-color) !important;
  padding: 0.65rem 1rem !important;
}

.f-footer-label {
  display: block;
  font-size: 0.75rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  opacity: 0.7;
  text-align: right;
  padding-right: 0.5rem;
}

:deep(.p-datatable-wrapper) {
  border-radius: 0 0 12px 12px;
  /* Altura fixa para 15 linhas (modo small) para evitar pulos de layout */
  min-height: 500px; /* Reduzi levemente para acomodar o footer sem barra vertical */
}

:deep(.p-datatable-tbody td),
:deep(.p-tag-value),
:deep(.p-tag) {
  text-transform: none !important;
  font-variant: normal !important;
}
</style>
