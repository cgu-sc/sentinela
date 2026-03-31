<script setup>
/**
 * RegionalPharmacyTable.vue
 * Ranking de farmácias da Região de Saúde ordenado por Score de Risco.
 * A classificação de risco usa o campo `classificacao_risco` da matriz_risco_consolidada,
 * espelhando a lógica da coluna "Classificação" do relatório Excel (aba_regiao.py).
 * A coluna "Conexão" usa o campo `conexao_ms` já presente no backend.
 */
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
</script>

<template>
  <div class="table-section shadow-card modern-scroll-card">
    <div class="section-header">
      <div class="header-icon-box">
        <i class="pi pi-chart-bar"></i>
      </div>
      <div class="header-text-box">
        <h3>RANKING DE RISCO DA REGIÃO</h3>
        <span class="subtitle">{{ farmacias.length }} estabelecimentos · ordenado por Score de Risco</span>
      </div>
    </div>

    <DataTable
      :value="farmacias"
      size="small"
      stripedRows
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
      <Column field="rank" header="#" sortable style="width: 4%" bodyStyle="text-align:center; font-weight:700; color: var(--text-muted)" />

      <!-- CNPJ -->
      <Column field="cnpj" header="CNPJ" sortable style="width: 12%">
        <template #body="{ data }">
          <span class="cnpj-text">{{ data.cnpj }}</span>
        </template>
      </Column>

      <!-- Razão Social -->
      <Column field="razao_social" header="Razão Social" sortable style="width: 22%; text-transform: none">
        <template #body="{ data }">
          <span
            v-tooltip.top="data.razao_social?.length > 24 ? data.razao_social : undefined"
            class="razao-social-cell"
          >{{ formatTitleCase(data.razao_social?.length > 24 ? data.razao_social.slice(0, 24) + '…' : data.razao_social) }}</span>
        </template>
      </Column>

      <!-- Município -->
      <Column field="municipio" header="Município" sortable style="width: 14%; text-transform: none">
        <template #body="{ data }">
          {{ formatTitleCase(data.municipio) }}
        </template>
      </Column>

      <!-- Score de Risco -->
      <Column field="score_risco" header="Score" sortable style="width: 7%" bodyStyle="text-align:center">
        <template #body="{ data }">
          <span
            v-if="data.score_risco != null"
            class="score-text"
          >{{ data.score_risco?.toFixed(2) }}</span>
          <span v-else class="text-muted">—</span>
        </template>
      </Column>

      <!-- Classificação -->
      <Column field="classificacao_risco" header="Classificação" sortable style="width: 12%">
        <template #body="{ data }">
          <Tag
            v-if="data.classificacao_risco"
            :value="formatClassifLabel(data.classificacao_risco)"
            :class="classifToRiskClass(data.classificacao_risco)"
          />
          <span v-else class="text-muted">—</span>
        </template>
      </Column>

      <Column field="valSemComp" header="Valor s/ Comp." sortable style="width: 10%" bodyStyle="text-align:right">
        <template #body="{ data }">
          <span :class="{ 'high-value-audit': data.valSemComp >= AUDIT_THRESHOLDS.HIGH_VALUE }">
            {{ formatBRL(data.valSemComp) }}
          </span>
        </template>
      </Column>

      <!-- Faturamento total -->
      <Column field="totalMov" header="Faturamento" sortable style="width: 10%" bodyStyle="text-align:right">
        <template #body="{ data }">{{ formatBRL(data.totalMov) }}</template>
      </Column>

      <!-- % sem comprovação -->
      <Column field="percValSemComp" header="% s/ Comp." sortable style="width: 8%" bodyStyle="text-align:center">
        <template #body="{ data }">
          <Tag :value="formatPercent(data.percValSemComp)" :class="getPercentClass(data.percValSemComp)" />
        </template>
      </Column>

      <!-- Última venda -->
      <Column field="data_ultima_venda" header="Última Venda" sortable style="width: 8%" bodyStyle="text-align:center">
        <template #body="{ data }">
          <span v-if="data.data_ultima_venda">
            {{ new Date(data.data_ultima_venda).toLocaleDateString('pt-BR') }}
          </span>
          <span v-else class="text-muted">—</span>
        </template>
      </Column>

      <!-- Conexão MS -->
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

.cnpj-text {
  font-family: monospace;
  font-size: 0.8rem;
  letter-spacing: 0.5px;
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
  font-size: 0.9rem;
  font-weight: 700;
  color: var(--text-color);
}

/* Linha do CNPJ específico em análise (Forte) */
:deep(.enterprise-table .p-datatable-tbody > tr.row-highlight td) {
  background: color-mix(in srgb, var(--primary-color) 12%, var(--card-bg)) !important;
}

:deep(.enterprise-table .p-datatable-tbody > tr.row-highlight td:first-child) {
  border-left: 4px solid var(--primary-color) !important;
}

/* DESTAQUE DE ALTO VALOR (VERMELHO - IGUAL CONEXÃO MS) */
.high-value-audit {
  color: var(--risk-high);
  font-weight: 700;
  display: inline-block;
  padding: 0 6px;
  border-left: 3px solid color-mix(in srgb, var(--risk-high) 40%, transparent);
}

/* Linhas do mesmo município (Sutil) */
:deep(.enterprise-table .p-datatable-tbody > tr.municipio-highlight td) {
  background: color-mix(in srgb, var(--primary-color) 6%, var(--card-bg)) !important;
}

:deep(.enterprise-table .p-datatable-tbody > tr.municipio-highlight td:first-child) {
  border-left: 2px solid color-mix(in srgb, var(--primary-color) 40%, transparent) !important;
}

:deep(.clickable-rows .p-datatable-tbody > tr) {
  cursor: pointer;
  transition: background-color 0.15s ease;
}

:deep(.p-datatable-thead) {
  position: sticky;
  top: 0;
  z-index: 10;
}

:deep(.p-datatable-wrapper) {
  border-radius: 0 0 12px 12px;
  /* Altura fixa para 15 linhas (modo small) para evitar pulos de layout */
  min-height: 700px;
}

/* RESET DE CAIXA ALTA FORÇADA */
:deep(.p-datatable-tbody td),
:deep(.p-tag-value),
:deep(.p-tag) {
  text-transform: none !important;
  font-variant: normal !important;
}
</style>
