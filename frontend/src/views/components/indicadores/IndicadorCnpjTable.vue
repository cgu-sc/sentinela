<script setup>
import { computed } from 'vue';
import { useRouter } from 'vue-router';
import { useFilterStore } from '@/stores/filters';
import { useFormatting } from '@/composables/useFormatting';
import { useStatusClass } from '@/composables/useStatusClass';
import { FILTER_OPTIONS } from '@/config/filterOptions';
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
});

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
  router.push({ name: 'CnpjDetail', params: { cnpj: event.data.cnpj } });
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

const totalCritico = computed(() => props.cnpjs.filter(c => c.status === 'CRÍTICO').length);
</script>

<template>
  <div class="ind-table-card" :class="{ 'is-refreshing': isLoading }">
    <div class="section-header">
      <div class="header-icon-box">
        <i class="pi pi-list-check" />
      </div>
      <div class="header-text-box">
        <h3>Farmácias por Indicador</h3>
        <span class="subtitle">
          {{ indicadorLabel }} — {{ cnpjs.length }} estabelecimentos
          <Tag v-if="totalCritico > 0" :value="`${totalCritico} CRÍTICO`" class="status-danger" />
        </span>
      </div>
    </div>

    <DataTable
      :value="cnpjs"
      size="small"
      stripedRows
      removableSort
      paginator
      :rows="20"
      sortField="risco_reg"
      :sortOrder="-1"
      class="enterprise-table ind-cnpj-table clickable-rows"
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

      <!-- % Não Comprovação -->
      <Column field="perc_val_sem_comp" header="% Não Comp." sortable style="width:9%; text-align:right">
        <template #body="{ data }">
          <span class="val-cell" :class="{ muted: data.perc_val_sem_comp == null }">
            {{ data.perc_val_sem_comp != null ? data.perc_val_sem_comp.toFixed(1) + '%' : '—' }}
          </span>
        </template>
      </Column>

      <!-- Valor Não Comprovação -->
      <Column field="val_sem_comp" header="Vlr. Não Comp." sortable style="width:10%; text-align:right">
        <template #body="{ data }">
          <span class="val-cell" :class="{ muted: data.val_sem_comp == null }">
            {{ data.val_sem_comp != null ? formatCurrencyFull(data.val_sem_comp) : '—' }}
          </span>
        </template>
      </Column>

      <!-- Risco Região -->
      <Column field="risco_reg" header="Risco Reg." sortable style="width:9%; text-align:center">
        <template #body="{ data }">
          <Tag
            v-if="data.risco_reg != null"
            :value="data.risco_reg.toFixed(1) + 'x'"
            :class="statusClass(data.status)"
          />
          <span v-else class="muted">—</span>
        </template>
      </Column>

      <!-- Status -->
      <Column field="status" header="Status" sortable style="width:9%; text-align:center">
        <template #body="{ data }">
          <Tag :value="data.status" :class="statusClass(data.status)" />
        </template>
      </Column>

      <!-- Conexão MS -->
      <Column field="is_conexao_ativa" header="Conex. MS" sortable style="width:8%; text-align:center">
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
      <Column field="situacao_rf" header="Sit. RF" sortable style="width:8%; text-align:center">
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
  opacity: 0.5;
  pointer-events: none;
}

.section-header {
  display: flex;
  align-items: center;
  gap: 1rem;
  padding: 1.25rem 1.5rem;
  border-bottom: 1px solid var(--tabs-border);
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
</style>
