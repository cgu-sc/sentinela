<script setup>
import { useRouter } from 'vue-router';
import { useFilterStore } from '@/stores/filters';
import { useFormatting } from '@/composables/useFormatting';
import { useStatusClass } from '@/composables/useStatusClass';
import { FILTER_OPTIONS } from '@/config/filterOptions';
import { AUDIT_THRESHOLDS } from '@/config/riskConfig';
import DataTable from 'primevue/datatable';
import Column from 'primevue/column';
import Tag from 'primevue/tag';

const props = defineProps({
  /** Array de IndicadorCnpjRowSchema */
  cnpjs: { type: Array, default: () => [] },
  /** Formato de valor: 'pct' | 'pct3' | 'val' | 'dec' */
  formato: { type: String, default: 'dec' },
  /** Chave do indicador */
  indicadorKey: { type: String, default: null },
  isLoading: { type: Boolean, default: false },
  indicadorLabel: { type: String, default: 'Indicador' },
  totalRecords: { type: Number, default: 0 },
  first: { type: Number, default: 0 },
  rows: { type: Number, default: 20 },
  sortField: { type: String, default: 'risco_reg' },
  sortOrder: { type: Number, default: -1 },
  selectedRegiaoNome: { type: String, default: null },
  selectedMunicipioNome: { type: String, default: null },
});

const emit = defineEmits(['lazy-load', 'clear-regiao-filter', 'clear-municipio-filter']);

const router = useRouter();
const filterStore = useFilterStore();
const { formatCurrencyFull } = useFormatting();
const { situacaoRfClass, conexaoMsClass } = useStatusClass();

function formatValue(valor) {
  if (valor == null) return '—';
  const fmt = props.formato;
  if (fmt === 'pct')  return valor.toFixed(2) + '%';
  if (fmt === 'pct3') return valor.toFixed(3) + '%';
  if (fmt === 'val')  return formatCurrencyFull(valor);
  return valor.toFixed(2);
}

function statusClass(status) {
  switch (status) {
    case 'CRÍTICO': return 'status-danger';
    case 'ATENÇÃO':  return 'status-warn';
    case 'NORMAL':   return 'status-success';
    default:         return 'status-secondary';
  }
}

function goToDetail(event) {
  if (event.originalEvent?.target?.closest('.clickable-badge, .copy-btn')) return;
  router.push({ name: 'EstablishmentDetail', params: { cnpj: event.data.cnpj } });
}

async function copyCnpj(cnpj) {
  await navigator.clipboard.writeText(cnpj);
}

function normalizeToOption(options, raw) {
  return options.find(o => o.toLowerCase() === raw?.toLowerCase()) ?? raw;
}

function applyFilter(field, value) {
  if (field === 'situacaoRF') filterStore.selectedSituacao = normalizeToOption(FILTER_OPTIONS.situacao, value);
  if (field === 'conexaoMS') {
    const valStr = typeof value === 'boolean' ? (value ? 'Ativa' : 'Inativa') : value;
    filterStore.selectedMS = normalizeToOption(FILTER_OPTIONS.ms, valStr);
  }
}

function onLazyLoad(event) {
  emit('lazy-load', event);
}
</script>

<template>
  <div class="ind-table-card" :class="{ 'is-refreshing': isLoading }">
    <div class="section-header">
      <div class="header-icon-box">
        <i class="pi pi-list" />
      </div>
      <div class="header-text-box">
        <h3>Farmácias por Indicador</h3>
        <span class="subtitle">
          {{ indicadorLabel }} — {{ totalRecords }} estabelecimentos
        </span>
      </div>
      <div v-if="selectedRegiaoNome || selectedMunicipioNome" class="header-filter-chips">
        <div v-if="selectedRegiaoNome" class="scope-filter-chip">
          <i class="pi pi-directions" />
          <span>Região: <strong>{{ selectedRegiaoNome }}</strong></span>
          <button class="chip-clear" @click="$emit('clear-regiao-filter')" title="Limpar Região">
            <i class="pi pi-times" />
          </button>
        </div>

        <div v-if="selectedMunicipioNome" class="scope-filter-chip">
          <i class="pi pi-map-marker" />
          <span>Município: <strong>{{ selectedMunicipioNome }}</strong></span>
          <button class="chip-clear" @click="$emit('clear-municipio-filter')" title="Limpar Município">
            <i class="pi pi-times" />
          </button>
        </div>
      </div>
    </div>

    <DataTable
      :value="cnpjs"
      size="small"
      stripedRows
      removableSort
      paginator
      lazy
      :first="first"
      :rows="rows"
      :totalRecords="totalRecords"
      :sortField="sortField"
      :sortOrder="sortOrder"
      class="enterprise-table ind-cnpj-table clickable-rows"
      @page="onLazyLoad"
      @sort="onLazyLoad"
      @row-click="goToDetail"
    >
      <!-- Razão Social + CNPJ -->
      <Column field="razao_social" header="Razão Social" sortable style="width:15%">
        <template #body="{ data }">
          <div class="razao-block">
            <span
              class="razao-social-cell"
              v-tooltip.top="data.razao_social"
            >{{ data.razao_social ?? '—' }}</span>
            <span class="cnpj-row">
              <span class="cnpj-text">{{ data.cnpj }}</span>
              <button
                class="copy-btn"
                v-tooltip.top="'Copiar CNPJ'"
                @click.stop="copyCnpj(data.cnpj)"
              ><i class="pi pi-copy" /></button>
            </span>
          </div>
        </template>
      </Column>

      <!-- UF + Município -->
      <Column field="municipio" header="Localização" sortable style="width:12%">
        <template #body="{ data }">
          <div class="loc-block">
            <span
              class="municipio-text"
              v-tooltip.top="data.municipio"
            >{{ data.municipio ?? '—' }}</span>
            <span class="uf-tag">{{ data.uf }}</span>
          </div>
        </template>
      </Column>

      <!-- Valor do indicador -->
      <Column field="valor" header="Valor" sortable style="width:8%; text-align:right">
        <template #body="{ data }">
          <span class="val-cell">{{ formatValue(data.valor) }}</span>
        </template>
      </Column>

      <!-- Mediana regional -->
      <Column field="med_reg" header="Mediana Reg." sortable style="width:10%; text-align:right">
        <template #body="{ data }">
          <span class="val-cell muted">{{ formatValue(data.med_reg) }}</span>
        </template>
      </Column>

      <Column field="risco_reg" header="Risco" sortable style="width:10%; text-align:center">
        <template #body="{ data }">
          <div class="risk-cell" :class="{ muted: data.risco_reg == null }">
            <span
              v-if="data.risco_reg != null"
              class="risk-value"
              :class="statusClass(data.status)"
            >
              {{ data.risco_reg.toFixed(1) }}x
            </span>
            <span v-else>—</span>
            <span
              v-if="data.status"
              class="risk-status"
              :class="statusClass(data.status)"
            >
              {{ data.status }}
            </span>
          </div>
        </template>
      </Column>

      <!-- Não Comprovação -->
      <Column field="val_sem_comp" header="Não Comprovação" sortable style="width:13%; text-align:right">
        <template #body="{ data }">
          <div class="noncomp-cell" :class="{ muted: data.val_sem_comp == null }">
            <span
              class="noncomp-value"
              :class="{ 'high-value-audit': data.val_sem_comp >= AUDIT_THRESHOLDS.HIGH_VALUE }"
            >
              {{ data.val_sem_comp != null ? formatCurrencyFull(data.val_sem_comp) : '—' }}
            </span>
            <span v-if="data.perc_val_sem_comp != null" class="noncomp-percent">
              {{ data.perc_val_sem_comp.toFixed(1) }}%
            </span>
          </div>
        </template>
      </Column>

      <!-- Conexão MS -->
      <Column field="is_conexao_ativa" header="Conex. MS" style="width:8%; text-align:center">
        <template #body="{ data }">
          <Tag
            :value="data.is_conexao_ativa ? 'Ativa' : 'Inativa'"
            :class="[conexaoMsClass(data.is_conexao_ativa), 'clickable-badge']"
            v-tooltip.top="'Filtrar por Conexão MS: ' + (data.is_conexao_ativa ? 'Ativa' : 'Inativa')"
            @click.stop="applyFilter('conexaoMS', data.is_conexao_ativa)"
          />
        </template>
      </Column>

      <!-- Situação RF -->
      <Column field="situacao_rf" header="Sit. RF" style="width:8%; text-align:center">
        <template #body="{ data }">
          <Tag
            v-if="data.situacao_rf"
            :value="data.situacao_rf"
            :class="[situacaoRfClass(data.situacao_rf), 'clickable-badge']"
            v-tooltip.top="'Filtrar por Situação RF: ' + data.situacao_rf"
            @click.stop="applyFilter('situacaoRF', data.situacao_rf)"
          />
          <span v-else class="muted">—</span>
        </template>
      </Column>
    </DataTable>
  </div>
</template>

<style scoped>
.ind-table-card {
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  border-radius: 12px;
  overflow: hidden;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.08);
  transition: opacity 0.3s ease;
}

.ind-table-card.is-refreshing {
  pointer-events: none;
}

.ind-table-card.is-refreshing :deep(.p-datatable-tbody) {
  opacity: 0.58;
}

.section-header {
  display: flex;
  align-items: center;
  gap: 1rem;
  padding: 1.25rem 1.5rem;
  border-bottom: 1px solid var(--tabs-border);
}

.header-text-box {
  flex: 1;
  min-width: 0;
}

.header-filter-chips {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  flex-wrap: wrap;
  gap: 0.5rem;
  margin-left: auto;
  min-width: 0;
}

.scope-filter-chip {
  display: inline-flex;
  align-items: center;
  gap: 0.45rem;
  max-width: 18rem;
  min-height: 1.8rem;
  padding: 0.35rem 0.7rem;
  background: color-mix(in srgb, var(--risk-indicator-critical, #ef4444) 10%, var(--card-bg));
  border: 1px solid color-mix(in srgb, var(--risk-indicator-critical, #ef4444) 35%, transparent);
  border-radius: 999px;
  font-size: 0.74rem;
  color: var(--text-color);
}

.scope-filter-chip span {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.scope-filter-chip i.pi-directions,
.scope-filter-chip i.pi-map-marker {
  color: var(--risk-indicator-critical, #ef4444);
  font-size: 0.72rem;
  flex-shrink: 0;
}

.chip-clear {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  background: none;
  border: none;
  cursor: pointer;
  padding: 0.1rem;
  color: var(--text-muted);
  font-size: 0.65rem;
  border-radius: 4px;
  opacity: 0.7;
  transition: opacity 0.15s ease, color 0.15s ease;
  flex-shrink: 0;
}

.chip-clear:hover {
  opacity: 1;
  color: var(--risk-indicator-critical, #ef4444);
}

.header-icon-box {
  width: 42px;
  height: 42px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: color-mix(in srgb, var(--primary-color) 10%, transparent);
  color: var(--primary-color);
  border-radius: 10px;
  font-size: 1.1rem;
  flex-shrink: 0;
}

.header-text-box h3 {
  margin: 0;
  font-size: 1rem;
  font-weight: 600;
  letter-spacing: -0.01em;
  color: var(--text-color);
}

.subtitle {
  font-size: 0.82rem;
  color: var(--text-muted);
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.razao-block {
  display: flex;
  flex-direction: column;
  gap: 0.2rem;
  min-width: 0;
  overflow: hidden;
}

.razao-social-cell {
  cursor: default;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  display: block;
  max-width: 100%;
  font-size: 0.78rem;
}

.cnpj-row {
  display: flex;
  align-items: center;
  gap: 0.3rem;
}

.cnpj-text {
  font-size: 0.68rem;
  color: var(--text-muted);
  letter-spacing: 0.01em;
}

.copy-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  background: none;
  border: none;
  padding: 0.1rem 0.2rem;
  cursor: pointer;
  color: var(--text-muted);
  font-size: 0.65rem;
  border-radius: 4px;
  opacity: 0;
  transition: opacity 0.15s ease, color 0.15s ease;
}

:deep(tr:hover) .copy-btn {
  opacity: 1;
}

.copy-btn:hover {
  color: var(--primary-color);
}

.loc-block {
  display: flex;
  flex-direction: column;
  gap: 0.2rem;
  min-width: 0;
  overflow: hidden;
}

.municipio-text {
  font-size: 0.78rem;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  display: block;
  max-width: 100%;
}

.uf-tag {
  display: inline-block;
  align-self: flex-start;
  padding: 0.05rem 0.3rem;
  background: color-mix(in srgb, var(--primary-color) 12%, var(--card-bg));
  color: var(--primary-color);
  border-radius: 4px;
  font-size: 0.65rem;
  font-weight: 600;
}

.val-cell {
  display: block;
  text-align: right;
}

.risk-cell {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 0.14rem;
  min-width: 0;
}

.risk-value {
  display: block;
  padding: 0 !important;
  background: transparent !important;
  border: 0 !important;
  font-size: 0.78rem;
  font-weight: 600;
  line-height: 1.1;
}

.risk-value.status-danger,
.risk-status.status-danger {
  color: var(--risk-high);
}

.risk-value.status-warn,
.risk-status.status-warn {
  color: var(--risk-medium);
}

.risk-value.status-success,
.risk-status.status-success {
  color: var(--text-color) !important;
}

.risk-value.status-secondary,
.risk-status.status-secondary {
  color: var(--text-muted);
}

.risk-status {
  display: block;
  max-width: 100%;
  padding: 0 !important;
  background: transparent !important;
  border: 0 !important;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 0.62rem;
  font-weight: 500;
  line-height: 1;
  letter-spacing: 0.03em;
}

.noncomp-cell {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 0.12rem;
  min-width: 0;
}

.noncomp-value {
  display: block;
  max-width: 100%;
  text-align: right;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.noncomp-percent {
  font-size: 0.68rem;
  font-weight: 600;
  line-height: 1;
  color: var(--text-muted);
  opacity: 0.72;
}

.muted {
  opacity: 0.45;
}

/* ── Deep overrides (padrão CnpjTable) ── */
:deep(.clickable-rows .p-datatable-tbody > tr) {
  cursor: pointer;
  transition: background-color 0.15s ease;
}

:deep(.ind-cnpj-table.p-datatable .p-datatable-tbody > tr) {
  font-size: 0.75rem;
}

:deep(.ind-cnpj-table.p-datatable .p-datatable-tbody) {
  transition: opacity 0.18s ease;
}

:deep(.ind-cnpj-table .p-datatable-table) {
  table-layout: fixed;
  width: 100%;
}

:deep(.ind-cnpj-table .p-datatable-tbody > tr > td) {
  overflow: hidden;
}

:deep(.ind-cnpj-table .p-datatable-thead > tr > th) {
  text-transform: uppercase;
  letter-spacing: 0.04em;
}

:deep(.p-datatable-thead) {
  position: sticky;
  top: 0;
  z-index: 10;
}

:deep(.p-datatable-wrapper) {
  border-radius: 0 0 12px 12px;
  min-height: calc(10 * 2.625rem);
}

:deep(.p-tag) {
  padding: 0.2rem 0.5rem;
  border-radius: 6px;
  font-weight: 600;
  font-size: 0.65rem;
  border: 1px solid transparent;
}

:deep(.clickable-badge) {
  cursor: pointer;
  transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
}
:deep(.clickable-badge:hover) {
  opacity: 1;
  transform: translateY(-1px);
  filter: brightness(0.95);
  box-shadow: 0 2px 4px rgba(0, 0, 0, 0.05);
}

:deep(.p-datatable-tbody td) {
  text-transform: none !important;
  font-variant: normal !important;
}

:deep(.p-tag-value),
:deep(.p-tag) {
  text-transform: uppercase !important;
  letter-spacing: 0.03em;
}

/* DESTAQUE DE ALTO VALOR (Sincronizado com CnpjTable) */
.high-value-audit {
  color: var(--risk-high);
  font-weight: 600;
  font-size: 0.75rem; /* Ajustado para caber na tabela densa de indicadores */
  display: inline-flex;
  align-items: center;
  justify-content: flex-end;
  gap: 0.4rem;
  padding: 0.15rem 0.65rem;
  background: color-mix(in srgb, var(--risk-high) 10%, transparent);
  border-left: 3px solid var(--risk-high);
  border-radius: 0 6px 6px 0;
}
</style>
