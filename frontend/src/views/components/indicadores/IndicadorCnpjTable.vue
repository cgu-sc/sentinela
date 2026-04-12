<script setup>
import { computed } from 'vue';
import { useRouter } from 'vue-router';
import { useFilterStore } from '@/stores/filters';
import { useFormatting } from '@/composables/useFormatting';
import { useStatusClass } from '@/composables/useStatusClass';
import { INDICATOR_THRESHOLDS } from '@/config/riskConfig';
import { FILTER_OPTIONS } from '@/config/filterOptions';
import DataTable from 'primevue/datatable';
import Column from 'primevue/column';

const props = defineProps({
  /** Array de IndicadorCnpjRowSchema */
  cnpjs: { type: Array, default: () => [] },
  /** Formato de valor: 'pct' | 'pct3' | 'val' | 'dec' */
  formato: { type: String, default: 'dec' },
  /** Chave do indicador (para obter threshold correto) */
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

// Estilo da pill de risco (mesma lógica de IndicatorsTab.vue)
function getStatusColor(status) {
  switch (status) {
    case 'CRÍTICO':  return 'var(--risk-indicator-critical)';
    case 'ATENÇÃO':  return 'var(--risk-indicator-warning)';
    case 'NORMAL':   return 'var(--risk-indicator-normal)';
    default:         return 'var(--text-muted)';
  }
}

function riscoPillStyle(status) {
  const c = getStatusColor(status);
  return { background: `color-mix(in srgb, ${c} 15%, transparent)`, color: c };
}

function goToDetail(event) {
  if (event.originalEvent?.target?.closest('.clickable-badge')) return;
  router.push({ name: 'CnpjDetail', params: { cnpj: event.data.cnpj } });
}

function normalizeToOption(options, raw) {
  return options.find(o => o.toLowerCase() === raw?.toLowerCase()) ?? raw;
}

function applyFilter(field, value) {
  if (field === 'grandeRede') {
    const valStr = typeof value === 'boolean' ? (value ? 'Sim' : 'Não') : value;
    filterStore.selectedGrandeRede = normalizeToOption(FILTER_OPTIONS.grandeRede, valStr);
  }
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
    <div class="table-header">
      <div class="header-icon-box">
        <i class="pi pi-list-check" />
      </div>
      <div class="header-text-box">
        <h3>Farmácias por Indicador</h3>
        <span class="subtitle">
          {{ indicadorLabel }} — {{ cnpjs.length }} estabelecimentos
          <span v-if="totalCritico > 0" class="critico-badge">{{ totalCritico }} CRÍTICO</span>
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
      class="custom-table ind-cnpj-table clickable-rows"
      @row-click="goToDetail"
    >
      <!-- CNPJ -->
      <Column field="cnpj" header="CNPJ" sortable style="width:11%">
        <template #body="{ data }">
          <span class="cnpj-cell">{{ data.cnpj }}</span>
        </template>
      </Column>

      <!-- Razão Social -->
      <Column field="razao_social" header="Razão Social" sortable style="width:22%">
        <template #body="{ data }">
          <span class="razao-cell" :title="data.razao_social">{{ data.razao_social ?? '—' }}</span>
        </template>
      </Column>

      <!-- UF + Município -->
      <Column field="municipio" header="Localização" sortable style="width:14%">
        <template #body="{ data }">
          <span class="loc-cell">
            <span class="uf-tag">{{ data.uf }}</span>
            {{ data.municipio ?? '—' }}
          </span>
        </template>
      </Column>

      <!-- Valor do indicador -->
      <Column field="valor" header="Valor" sortable style="width:9%; text-align:center">
        <template #body="{ data }">
          <span class="val-cell">{{ formatValue(data.valor) }}</span>
        </template>
      </Column>

      <!-- Mediana regional -->
      <Column field="med_reg" header="Mediana Reg." sortable style="width:10%; text-align:center">
        <template #body="{ data }">
          <span class="val-cell muted">{{ formatValue(data.med_reg) }}</span>
        </template>
      </Column>

      <!-- Risco Região -->
      <Column field="risco_reg" header="Risco Reg." sortable style="width:9%; text-align:center">
        <template #body="{ data }">
          <span
            v-if="data.risco_reg != null"
            class="risco-pill"
            :style="riscoPillStyle(data.status)"
          >{{ data.risco_reg.toFixed(1) }}x</span>
          <span v-else class="muted">—</span>
        </template>
      </Column>

      <!-- Status -->
      <Column field="status" header="Status" sortable style="width:9%; text-align:center">
        <template #body="{ data }">
          <span class="status-pill" :style="riscoPillStyle(data.status)">{{ data.status }}</span>
        </template>
      </Column>

      <!-- Grande Rede -->
      <Column field="is_grande_rede" header="Rede" sortable style="width:7%; text-align:center">
        <template #body="{ data }">
          <span
            v-if="data.is_grande_rede"
            class="clickable-badge badge-rede"
            @click.stop="applyFilter('grandeRede', data.is_grande_rede)"
          >Rede</span>
          <span v-else class="muted">—</span>
        </template>
      </Column>

      <!-- Situação RF -->
      <Column field="situacao_rf" header="Sit. RF" sortable style="width:8%; text-align:center">
        <template #body="{ data }">
          <span
            v-if="data.situacao_rf"
            class="clickable-badge"
            :class="situacaoRfClass(data.situacao_rf)"
            @click.stop="applyFilter('situacaoRF', data.situacao_rf)"
          >{{ data.situacao_rf }}</span>
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

.table-header {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  padding: 0.85rem 1.25rem;
  border-bottom: 1px solid var(--tabs-border);
}

.header-icon-box {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 2rem;
  height: 2rem;
  border-radius: 8px;
  background: color-mix(in srgb, var(--primary-color) 12%, var(--card-bg));
  color: var(--primary-color);
  font-size: 0.9rem;
  flex-shrink: 0;
}

.header-text-box h3 {
  margin: 0;
  font-size: 0.85rem;
  font-weight: 600;
  color: var(--text-color);
  opacity: 0.85;
}

.subtitle {
  font-size: 0.72rem;
  color: var(--text-muted);
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.critico-badge {
  display: inline-flex;
  align-items: center;
  padding: 0.1rem 0.45rem;
  background: color-mix(in srgb, var(--risk-indicator-critical) 15%, transparent);
  color: var(--risk-indicator-critical);
  border-radius: 99px;
  font-size: 0.65rem;
  font-weight: 600;
}

.cnpj-cell {
  font-size: 0.78rem;
  font-family: inherit;
  color: var(--text-color);
}

.razao-cell {
  font-size: 0.8rem;
  display: block;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  max-width: 200px;
}

.loc-cell {
  display: flex;
  align-items: center;
  gap: 0.35rem;
  font-size: 0.78rem;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.uf-tag {
  display: inline-block;
  padding: 0.05rem 0.3rem;
  background: color-mix(in srgb, var(--primary-color) 12%, var(--card-bg));
  color: var(--primary-color);
  border-radius: 4px;
  font-size: 0.65rem;
  font-weight: 600;
  flex-shrink: 0;
}

.val-cell {
  font-size: 0.8rem;
  display: block;
  text-align: center;
}

.muted {
  opacity: 0.5;
}

.risco-pill {
  display: inline-block;
  padding: 0.15rem 0.55rem;
  border-radius: 99px;
  font-size: 0.72rem;
  font-weight: 600;
  min-width: 3rem;
  text-align: center;
}

.status-pill {
  display: inline-block;
  padding: 0.2rem 0.5rem;
  border-radius: 99px;
  font-size: 0.62rem;
  font-weight: 600;
  letter-spacing: 0.04em;
  white-space: nowrap;
}

.clickable-badge {
  cursor: pointer;
  display: inline-block;
  padding: 0.15rem 0.45rem;
  border-radius: 99px;
  font-size: 0.68rem;
  font-weight: 600;
  transition: opacity 0.15s ease;
  white-space: nowrap;
}

.clickable-badge:hover {
  opacity: 0.8;
}

.badge-rede {
  background: color-mix(in srgb, var(--primary-color) 15%, transparent);
  color: var(--primary-color);
}

/* Herda os estilos globais de DataTable do projeto */
:deep(.clickable-rows .p-datatable-tbody > tr) {
  cursor: pointer;
}
</style>
