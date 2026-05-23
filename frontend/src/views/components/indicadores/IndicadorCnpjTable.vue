<script setup>
import { computed, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useFilterStore } from '@/stores/filters';
import { useFormatting } from '@/composables/useFormatting';
import { useStatusClass } from '@/composables/useStatusClass';
import { extractCnpjRaiz } from '@/composables/useParsing';
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
  tableKpis: { type: Object, default: null },
  selectedRegiaoNome: { type: String, default: null },
  selectedMunicipioNome: { type: String, default: null },
});

const emit = defineEmits(['lazy-load', 'clear-regiao-filter', 'clear-municipio-filter']);

const router = useRouter();
const filterStore = useFilterStore();
const { formatCurrencyFull } = useFormatting();
const { conexaoMsClass } = useStatusClass();
const copiedKey = ref(null);

function formatValue(valor) {
  if (valor == null) return '—';
  const fmt = props.formato;
  if (fmt === 'pct')  return valor.toFixed(2) + '%';
  if (fmt === 'pct3') return valor.toFixed(3) + '%';
  if (fmt === 'val')  return formatCurrencyFull(valor);
  return valor.toFixed(2);
}

function formatCurrencyCompact(valor) {
  if (valor == null) return '—';

  const numericValue = Number(valor);
  if (!Number.isFinite(numericValue)) return '—';

  const absValue = Math.abs(numericValue);
  const compactRules = [
    { limit: 1_000_000_000, divisor: 1_000_000_000, suffix: 'bi' },
    { limit: 1_000_000, divisor: 1_000_000, suffix: 'mi' },
    { limit: 1_000, divisor: 1_000, suffix: 'k' },
  ];
  const rule = compactRules.find(item => absValue >= item.limit);

  if (!rule) return formatCurrencyFull(numericValue);

  const scaledValue = numericValue / rule.divisor;
  const formattedValue = scaledValue.toLocaleString('pt-BR', {
    minimumFractionDigits: 0,
    maximumFractionDigits: Math.abs(scaledValue) < 10 ? 1 : 0,
  });

  return `R$ ${formattedValue}${rule.suffix}`;
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

function copyAndSignal(text, key) {
  if (!text) return;
  navigator.clipboard.writeText(text);
  copiedKey.value = key;
  setTimeout(() => {
    if (copiedKey.value === key) copiedKey.value = null;
  }, 2000);
}

function normalizeToOption(options, raw) {
  return options.find(o => o.toLowerCase() === raw?.toLowerCase()) ?? raw;
}

function applyFilter(field, value) {
  if (field === 'grandeRede') {
    const valStr = typeof value === 'boolean' ? (value ? 'Sim' : 'Não') : value;
    filterStore.selectedGrandeRede = normalizeToOption(FILTER_OPTIONS.grandeRede, valStr);
  }
  if (field === 'conexaoMS') {
    const valStr = typeof value === 'boolean' ? (value ? 'Ativa' : 'Inativa') : value;
    filterStore.selectedMS = normalizeToOption(FILTER_OPTIONS.ms, valStr);
  }
}

function onLazyLoad(event) {
  emit('lazy-load', event);
}

const tableFooter = computed(() => {
  const totalSemComprovacao = Number(props.tableKpis?.total_sem_comprovacao ?? 0);
  const totalMov = Number(props.tableKpis?.total_mov ?? 0);

  return {
    totalSemComprovacao: formatCurrencyCompact(totalSemComprovacao),
    totalSemComprovacaoFull: formatCurrencyFull(totalSemComprovacao),
    totalMov: formatCurrencyCompact(totalMov),
    totalMovFull: formatCurrencyFull(totalMov),
  };
});

const indicatorColumnHeader = computed(() => props.indicadorLabel?.trim() || 'Indicador');
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
      <Column
        field="razao_social"
        header="Razão Social"
        sortable
        headerClass="col-name"
        bodyClass="col-name"
      >
        <template #body="{ data }">
          <div class="razao-block">
            <span
              class="razao-social-cell"
              v-tooltip.top="data.razao_social"
            >{{ data.razao_social ?? '—' }}</span>
            <span class="cnpj-row">
              <span
                v-tooltip.top="data.is_matriz ? 'Matriz' : 'Filial'"
                :class="data.is_matriz ? 'tipo-badge matriz' : 'tipo-badge filial'"
              >
                <i :class="data.is_matriz ? 'pi pi-home' : 'pi pi-building'" />
              </span>
              <span class="cnpj-text">{{ data.cnpj }}</span>
              <i
                :class="['pi', copiedKey === data.cnpj + '-cnpj' ? 'pi-check text-success' : 'pi-copy', 'copy-btn']"
                v-tooltip.top="'Copiar CNPJ'"
                @click.stop="copyAndSignal(data.cnpj, data.cnpj + '-cnpj')"
              />
            </span>
          </div>
        </template>
        <template #footer>
          <span class="table-total-label">TOTAL</span>
        </template>
      </Column>

      <!-- UF + Município -->
      <Column
        field="municipio"
        header="Localização"
        sortable
        headerClass="col-location"
        bodyClass="col-location"
      >
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

      <!-- Valor do indicador + Mediana regional -->
      <Column
        field="valor"
        sortable
        headerClass="col-indicator"
        bodyClass="col-indicator"
      >
        <template #header>
          <span class="indicator-column-title" v-tooltip.top="indicatorColumnHeader">
            {{ indicatorColumnHeader }}
          </span>
        </template>
        <template #body="{ data }">
          <div class="indicator-cell" :class="{ muted: data.valor == null }">
            <span class="indicator-value">{{ formatValue(data.valor) }}</span>
            <span class="indicator-median">região {{ formatValue(data.med_reg) }}</span>
          </div>
        </template>
      </Column>

      <Column
        field="risco_reg"
        header="Risco"
        sortable
        headerClass="col-risk"
        bodyClass="col-risk"
      >
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

      <!-- Valor Movimentado -->
      <Column
        field="valor_movimentado"
        header="Valor Movimentado"
        sortable
        headerClass="col-movement"
        bodyClass="col-movement"
      >
        <template #body="{ data }">
          <span
            class="movement-value"
            v-tooltip.top="data.valor_movimentado != null ? formatCurrencyFull(data.valor_movimentado) : null"
          >
            {{ formatCurrencyCompact(data.valor_movimentado) }}
          </span>
        </template>
        <template #footer>
          <span
            class="movement-value table-total-movement"
            v-tooltip.top="tableFooter.totalMovFull"
          >{{ tableFooter.totalMov }}</span>
        </template>
      </Column>

      <!-- Não Comprovação -->
      <Column
        field="val_sem_comp"
        header="Não Comprovação"
        sortable
        headerClass="col-noncomp"
        bodyClass="col-noncomp"
      >
        <template #body="{ data }">
          <div class="noncomp-cell" :class="{ muted: data.val_sem_comp == null }">
            <span
              class="noncomp-value"
              :class="{ 'high-value-audit': data.val_sem_comp >= AUDIT_THRESHOLDS.HIGH_VALUE }"
              v-tooltip.top="data.val_sem_comp != null ? formatCurrencyFull(data.val_sem_comp) : null"
            >
              {{ formatCurrencyCompact(data.val_sem_comp) }}
            </span>
            <span v-if="data.perc_val_sem_comp != null" class="noncomp-percent">
              {{ data.perc_val_sem_comp.toFixed(2) }}%
            </span>
          </div>
        </template>
        <template #footer>
          <div class="noncomp-cell table-total-cell">
            <span
              class="noncomp-value"
              v-tooltip.top="tableFooter.totalSemComprovacaoFull"
            >{{ tableFooter.totalSemComprovacao }}</span>
          </div>
        </template>
      </Column>

      <!-- Grande Rede -->
      <Column
        field="is_grande_rede"
        header="Grande Rede"
        headerClass="col-network-flag"
        bodyClass="col-network-flag"
      >
        <template #body="{ data }">
          <Tag
            :value="data.is_grande_rede ? 'Sim' : 'Não'"
            :class="[data.is_grande_rede ? 'status-info' : 'status-secondary', 'clickable-badge']"
            v-tooltip.top="'Filtrar por Grande Rede: ' + (data.is_grande_rede ? 'Sim' : 'Não')"
            @click.stop="applyFilter('grandeRede', data.is_grande_rede)"
          />
        </template>
      </Column>

      <!-- Estabelecimentos da Rede -->
      <Column
        field="qtd_estabelecimentos_rede"
        header="Estab. Rede"
        headerClass="col-network-count"
        bodyClass="col-network-count"
      >
        <template #body="{ data }">
          <Tag
            v-if="data.qtd_estabelecimentos_rede > 1"
            :value="String(data.qtd_estabelecimentos_rede)"
            class="status-info clickable-badge"
            v-tooltip.top="'Ver todos os estabelecimentos desta rede'"
            @click.stop="filterStore.selectedCnpjRaiz = extractCnpjRaiz(data.cnpj)"
          />
          <Tag
            v-else-if="data.qtd_estabelecimentos_rede === 1"
            value="1"
            class="status-secondary"
          />
          <span v-else class="network-count-muted">—</span>
        </template>
      </Column>

      <!-- Conexão MS -->
      <Column
        field="is_conexao_ativa"
        header="Conexão MS"
        headerClass="col-badge-filter"
        bodyClass="col-badge-filter"
      >
        <template #body="{ data }">
          <Tag
            :value="data.is_conexao_ativa ? 'Ativa' : 'Inativa'"
            :class="[conexaoMsClass(data.is_conexao_ativa), 'clickable-badge']"
            v-tooltip.top="'Filtrar por Conexão MS: ' + (data.is_conexao_ativa ? 'Ativa' : 'Inativa')"
            @click.stop="applyFilter('conexaoMS', data.is_conexao_ativa)"
          />
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
  color: var(--text-color-85);
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
  color: var(--text-color-85);
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
  font-size: 0.88rem;
}

.cnpj-row {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.tipo-badge {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 1.25rem;
  height: 1.25rem;
  border-radius: 6px;
  font-size: 0.68rem;
  flex-shrink: 0;
  backdrop-filter: blur(6px);
  -webkit-backdrop-filter: blur(6px);
}

.tipo-badge.matriz {
  background: color-mix(in srgb, var(--accent-indigo) 18%, transparent);
  border: 1px solid color-mix(in srgb, var(--accent-indigo) 35%, transparent);
  color: var(--accent-indigo);
}

.tipo-badge.filial {
  background: color-mix(in srgb, var(--status-secondary) 12%, transparent);
  border: 1px solid color-mix(in srgb, var(--status-secondary) 20%, transparent);
  color: var(--status-secondary);
}

.cnpj-text {
  font-size: 0.78rem;
  color: var(--text-muted);
  letter-spacing: 0.01em;
}

.copy-btn {
  display: inline-flex;
  justify-content: center;
  width: 1.4rem;
  flex-shrink: 0;
  cursor: pointer;
  color: var(--text-muted);
  font-size: 0.85rem;
  opacity: 0.4;
  transition: all 0.2s;
}

.copy-btn.text-success {
  color: var(--status-success) !important;
  opacity: 1 !important;
}

.copy-btn:hover {
  opacity: 1 !important;
  color: var(--primary-color);
  transform: scale(1.1);
}

.copy-btn:active {
  transform: scale(0.9);
}

.loc-block {
  display: flex;
  flex-direction: column;
  gap: 0.2rem;
  min-width: 0;
  overflow: hidden;
}

.municipio-text {
  font-size: 0.88rem;
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
  font-size: 0.78rem;
  font-weight: 600;
}

.val-cell {
  display: block;
  text-align: right;
}

.indicator-cell {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 0.12rem;
  min-width: 0;
}

.indicator-value {
  display: block;
  max-width: 100%;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 0.88rem;
}

.indicator-median {
  display: block;
  max-width: 100%;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 0.78rem;
  font-weight: 500;
  line-height: 1;
  color: var(--text-muted);
  opacity: 0.72;
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
  font-size: 0.88rem;
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
  color: var(--text-muted) !important;
}

.risk-value.status-secondary,
.risk-status.status-secondary {
  color: var(--text-muted);
}

.movement-value {
  display: block;
  max-width: 100%;
  overflow: hidden;
  color: var(--text-color-85);
  font-size: 0.88rem;
  text-align: right;
  text-overflow: ellipsis;
  white-space: nowrap;
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
  font-size: 0.78rem;
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
  font-size: 0.88rem;
}

.noncomp-percent {
  font-size: 0.78rem;
  font-weight: 600;
  line-height: 1;
  color: var(--text-muted);
  opacity: 0.72;
}

.table-total-label {
  color: var(--text-color-85);
  font-size: 0.72rem;
  font-weight: 800;
  letter-spacing: 0.04em;
}

.table-total-cell .noncomp-value {
  color: var(--text-color-85);
  font-weight: 800;
}

.table-total-cell .noncomp-percent {
  font-weight: 800;
  opacity: 0.9;
}

.table-total-movement {
  font-weight: 800;
}

.network-count-muted {
  display: block;
  max-width: 100%;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 0.62rem;
  font-weight: 500;
  line-height: 1;
  color: var(--text-muted);
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

:deep(.ind-cnpj-table .col-name) {
  width: 29%;
}

:deep(.ind-cnpj-table .p-datatable-thead > tr > th:first-child),
:deep(.ind-cnpj-table .p-datatable-tbody > tr > td:first-child) {
  padding-left: 1.25rem;
}

:deep(.ind-cnpj-table .p-datatable-tbody > tr > td) {
  color: var(--text-color-85) !important;
}

:deep(.ind-cnpj-table .col-location) {
  width: 12%;
}

:deep(.ind-cnpj-table .col-indicator) {
  width: 11%;
  text-align: right;
}

:deep(.ind-cnpj-table .col-risk) {
  width: 7%;
  text-align: center;
}

:deep(.ind-cnpj-table .col-movement) {
  width: 10%;
  text-align: right;
}

:deep(.ind-cnpj-table .col-noncomp) {
  width: 10%;
  text-align: right;
}

:deep(.ind-cnpj-table .col-network-flag) {
  width: 7%;
  text-align: center;
  padding-left: 0.25rem;
  padding-right: 0.25rem;
}

:deep(.ind-cnpj-table .col-network-count) {
  width: 7%;
  text-align: center;
  padding-left: 0.25rem;
  padding-right: 0.25rem;
}

:deep(.ind-cnpj-table .col-badge-filter) {
  width: 7%;
  text-align: center;
  padding-left: 0.25rem;
  padding-right: 0.25rem;
}

:deep(.ind-cnpj-table .col-indicator .p-column-header-content),
:deep(.ind-cnpj-table .col-movement .p-column-header-content),
:deep(.ind-cnpj-table .col-noncomp .p-column-header-content) {
  justify-content: flex-end;
}

:deep(.ind-cnpj-table .col-indicator .p-column-title) {
  min-width: 0;
}

.indicator-column-title {
  display: -webkit-box;
  max-width: 100%;
  overflow: hidden;
  text-align: right;
  text-overflow: ellipsis;
  white-space: normal;
  line-height: 1.1;
  -webkit-box-orient: vertical;
  -webkit-line-clamp: 2;
}

:deep(.ind-cnpj-table .col-risk .p-column-header-content),
:deep(.ind-cnpj-table .col-network-flag .p-column-header-content),
:deep(.ind-cnpj-table .col-network-count .p-column-header-content),
:deep(.ind-cnpj-table .col-badge-filter .p-column-header-content) {
  justify-content: center;
}

:deep(.ind-cnpj-table .col-badge-filter .p-sortable-column-icon) {
  display: none;
}

:deep(.ind-cnpj-table .col-badge-filter .p-tag) {
  max-width: 100%;
  padding-left: 0.38rem;
  padding-right: 0.38rem;
}

:deep(.ind-cnpj-table .col-badge-filter .p-tag-value) {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

:deep(.ind-cnpj-table .col-network-flag .p-tag) {
  max-width: 100%;
  padding-left: 0.38rem;
  padding-right: 0.38rem;
}

:deep(.ind-cnpj-table .col-network-flag .p-tag-value) {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

:deep(.ind-cnpj-table .p-datatable-thead > tr > th) {
  text-transform: uppercase;
  letter-spacing: 0.04em;
}

:deep(.ind-cnpj-table .p-datatable-tfoot > tr > td) {
  color: var(--text-color-85);
  background: color-mix(in srgb, var(--primary-color) 5%, var(--card-bg));
  border-top: 1px solid var(--card-border);
  font-size: 0.72rem;
}

:deep(.p-datatable-thead) {
  position: sticky;
  top: 0;
  z-index: 10;
}

:deep(.p-datatable-wrapper) {
  border-radius: 0 0 12px 12px;
  min-height: calc(20 * 2.625rem);
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
