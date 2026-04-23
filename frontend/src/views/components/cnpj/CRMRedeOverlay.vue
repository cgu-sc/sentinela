<script setup>
import { computed, ref } from 'vue';
import Dialog from 'primevue/dialog';

// ──────────────────────────────────────────────
// Props
// ──────────────────────────────────────────────
const props = defineProps({
  currentCnpj: { type: String, required: true },
});

import axios from 'axios';
import { useGeoStore } from '@/stores/geo';
import { useFormatting } from '@/composables/useFormatting';
import { useFilterParameters } from '@/composables/useFilterParameters';
import { API_ENDPOINTS } from '@/config/api';

const geoStore = useGeoStore();
const { formatCurrencyFull } = useFormatting();
const { getApiParams } = useFilterParameters();

// ──────────────────────────────────────────────
// Estado interno
// ──────────────────────────────────────────────
const visible        = ref(false);
const medico         = ref(null);    // { id_medico, lista_cnpjs_brasil, ... }
const redeData       = ref([]);      // dados enriquecidos vindos da API
const isLoading      = ref(false);
const periodoExibido = ref('');      // ex: "jan/2023 – dez/2023"

// ──────────────────────────────────────────────
// Utilitários
// ──────────────────────────────────────────────
const formatCnpj = (v) => {
  if (!v) return '—';
  const c = v.replace(/\D/g, '');
  if (c.length !== 14) return v;
  return c.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/, '$1.$2.$3/$4-$5');
};

// ──────────────────────────────────────────────
// Lista de CNPJs bruta (para contagem no header)
// ──────────────────────────────────────────────
const cnpjsRaw = computed(() => {
  if (!medico.value?.lista_cnpjs_brasil) return [];
  return [...new Set(
    medico.value.lista_cnpjs_brasil
      .split(',')
      .map(s => s.trim())
      .filter(Boolean)
  )].sort();
});

// ──────────────────────────────────────────────
// Lista enriquecida (dados do período + fallback geo)
// ──────────────────────────────────────────────
const enrichedList = computed(() => {
  return cnpjsRaw.value.map(cnpj => {
    // Dados do período (vindos da chamada ao /resumo)
    const apiData = redeData.value.find(r => r.cnpj === cnpj);

    // Fallback geográfico via geoStore (UF/Município apenas)
    const geoData = !apiData
      ? geoStore.estabelecimentos.find(e => e.cnpj === cnpj)
      : null;
    const lookupData = (!apiData && !geoData)
      ? geoStore.cnpjLookup.find(l => l.cnpj === cnpj)
      : null;

    return {
      cnpj,
      municipio:       apiData?.municipio    || geoData?.municipio    || lookupData?.municipio || 'N/I',
      uf:              apiData?.uf           || geoData?.uf           || lookupData?.uf        || '??',
      totalMov:        apiData?.totalMov     ?? 0,
      valSemComp:      apiData?.valSemComp   ?? 0,
      percValSemComp:  apiData?.percValSemComp ?? 0,
    };
  });
});

// ──────────────────────────────────────────────
// Busca dados do período no backend
// ──────────────────────────────────────────────
function formatPeriodo(dateStr) {
  if (!dateStr) return '';
  const [y, m] = dateStr.split('-');
  const meses = ['jan','fev','mar','abr','mai','jun','jul','ago','set','out','nov','dez'];
  return `${meses[parseInt(m, 10) - 1]}/${y}`;
}

async function fetchRedeMetrics(cnpjs) {
  if (!cnpjs.length) return;
  isLoading.value = true;
  redeData.value  = [];
  try {
    const { inicio, fim } = getApiParams();

    // Formata o período para exibição
    periodoExibido.value = [formatPeriodo(inicio), formatPeriodo(fim)]
      .filter(Boolean).join(' – ');

    const params = new URLSearchParams();
    if (inicio) params.set('data_inicio', inicio);
    if (fim)    params.set('data_fim',    fim);
    cnpjs.forEach(c => params.append('cnpjs', c));

    const { data } = await axios.get(
      `${API_ENDPOINTS.analyticsResumo}?${params.toString()}`
    );
    redeData.value = data.resultado_cnpjs || [];
  } catch (e) {
    console.error('Erro ao buscar métricas da rede:', e);
  } finally {
    isLoading.value = false;
  }
}

const isCurrentCnpj = (cnpj) => cnpj === props.currentCnpj;

// ──────────────────────────────────────────────
// API pública — chamada pelo pai
// ──────────────────────────────────────────────
const open = (_event, medicoRow) => {
  medico.value  = medicoRow;
  visible.value = true;

  // Extrai lista e busca métricas do período
  const cnpjs = [...new Set(
    (medicoRow.lista_cnpjs_brasil || '')
      .split(',').map(s => s.trim()).filter(Boolean)
  )];
  fetchRedeMetrics(cnpjs);
};

defineExpose({ open });
</script>

<template>
  <Dialog
    v-model:visible="visible"
    modal
    :draggable="false"
    :closable="true"
    :style="{ width: '740px', padding: '0' }"
    :pt="{ root: { class: 'rede-dialog-root' }, header: { style: 'display:none' }, content: { style: 'padding:0; border-radius: 12px; overflow: hidden;' } }"
  >
    <div v-if="medico" class="rede-root">

      <!-- ══ HEADER ══════════════════════════════════════════════════════════ -->
      <div class="rede-header">
        <div class="rede-header-left">
          <div class="rede-header-icon">
            <i class="pi pi-sitemap" />
          </div>
          <div class="rede-header-info">
            <span class="rede-header-title">Rede de Dispensação</span>
            <span class="rede-header-sub">
              CRM <strong>{{ medico.id_medico }}</strong>
              &nbsp;·&nbsp;
              <strong>{{ cnpjsRaw.length }}</strong>
              {{ cnpjsRaw.length === 1 ? 'estabelecimento' : 'estabelecimentos' }}
            </span>
          </div>
        </div>
        <button class="rede-close-btn" @click="visible = false" v-tooltip.left="'Fechar'">
          <i class="pi pi-times" />
        </button>
      </div>

      <!-- ══ PERÍODO ══════════════════════════════════════════════════════════ -->
      <div v-if="periodoExibido" class="rede-periodo-bar">
        <i class="pi pi-calendar" />
        <span class="rede-periodo-label">Período de análise:</span>
        <span class="rede-periodo-val">{{ periodoExibido }}</span>
      </div>

      <!-- ══ LOADING ══════════════════════════════════════════════════════════ -->
      <div v-if="isLoading" class="rede-loading">
        <div class="rede-loading-pulse">
          <i class="pi pi-spin pi-spinner" />
        </div>
        <span>Calculando valores do período selecionado...</span>
      </div>

      <!-- ══ TABELA ══════════════════════════════════════════════════════════ -->
      <div v-else-if="cnpjsRaw.length" class="rede-table-wrap">
        <!-- Cabeçalho fixo -->
        <div class="rede-thead">
          <span class="col-num">#</span>
          <span class="col-cnpj">CNPJ</span>
          <span class="col-loc">Município / UF</span>
          <span class="col-mov">Movimentação</span>
          <span class="col-irr">Irregular</span>
          <span class="col-bar"></span>
        </div>

        <!-- Linhas -->
        <div class="rede-tbody">
          <div
            v-for="(item, idx) in enrichedList"
            :key="item.cnpj"
            class="rede-row"
            :class="{
              'rede-row--current': isCurrentCnpj(item.cnpj),
              'rede-row--risk':    item.percValSemComp > 30
            }"
          >
            <!-- # -->
            <span class="col-num">
              <span class="row-num">{{ (idx + 1).toString().padStart(2, '0') }}</span>
            </span>

            <!-- CNPJ -->
            <div class="col-cnpj">
              <a
                v-if="!isCurrentCnpj(item.cnpj)"
                :href="`/estabelecimentos/${item.cnpj}`"
                target="_blank"
                class="cnpj-link"
                v-tooltip.top="'Abrir em nova aba'"
              >
                {{ formatCnpj(item.cnpj) }}
                <i class="pi pi-external-link cnpj-ext" />
              </a>
              <span v-else class="cnpj-current">
                {{ formatCnpj(item.cnpj) }}
                <span class="badge-atual">ATUAL</span>
              </span>
            </div>

            <!-- Localização -->
            <div class="col-loc">
              <span class="loc-mun">{{ item.municipio }}</span>
              <span class="loc-uf">{{ item.uf }}</span>
            </div>

            <!-- Movimentação -->
            <div class="col-mov">
              <span class="val-mov">{{ formatCurrencyFull(item.totalMov) }}</span>
            </div>

            <!-- Irregular + barra -->
            <div class="col-irr">
              <span
                class="val-irr"
                :class="{
                  'val-irr--zero': item.valSemComp === 0,
                  'val-irr--mid':  item.percValSemComp > 0 && item.percValSemComp <= 30,
                  'val-irr--high': item.percValSemComp > 30
                }"
              >
                {{ formatCurrencyFull(item.valSemComp) }}
              </span>
              <span v-if="item.percValSemComp > 0" class="val-perc">
                {{ item.percValSemComp.toFixed(1) }}%
              </span>
            </div>

            <!-- Barra de risco -->
            <div class="col-bar">
              <div class="risk-bar-track">
                <div
                  class="risk-bar-fill"
                  :class="{
                    'fill--low':  item.percValSemComp <= 15,
                    'fill--mid':  item.percValSemComp > 15 && item.percValSemComp <= 30,
                    'fill--high': item.percValSemComp > 30
                  }"
                  :style="{ width: Math.min(item.percValSemComp, 100) + '%' }"
                />
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- ══ VAZIO ══════════════════════════════════════════════════════════ -->
      <div v-else class="rede-empty">
        <i class="pi pi-inbox" />
        <span>Nenhuma farmácia encontrada no período selecionado.</span>
      </div>

    </div>
  </Dialog>
</template>

<style scoped>
/* ══ ROOT ════════════════════════════════════════════════════════════════ */
.rede-root {
  display: flex;
  flex-direction: column;
  overflow: hidden;
  border-radius: 12px;
}

/* ══ HEADER ═════════════════════════════════════════════════════════════ */
.rede-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 1rem 1.25rem 0.9rem;
  background: linear-gradient(135deg,
    color-mix(in srgb, var(--primary-color) 14%, transparent),
    color-mix(in srgb, var(--primary-color) 6%, transparent)
  );
  border-bottom: 1px solid color-mix(in srgb, var(--primary-color) 20%, transparent);
}

.rede-header-left {
  display: flex;
  align-items: center;
  gap: 0.75rem;
}

.rede-header-icon {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 36px;
  height: 36px;
  border-radius: 10px;
  background: color-mix(in srgb, var(--primary-color) 20%, transparent);
  border: 1px solid color-mix(in srgb, var(--primary-color) 35%, transparent);
  color: var(--primary-color);
  font-size: 1rem;
  flex-shrink: 0;
}

.rede-header-title {
  display: block;
  font-size: 0.78rem;
  font-weight: 800;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  color: var(--primary-color);
}

.rede-header-sub {
  display: block;
  font-size: 0.8rem;
  color: var(--text-secondary);
  margin-top: 0.1rem;
}

.rede-header-sub strong {
  color: var(--text-color);
  font-weight: 700;
}

.rede-close-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 28px;
  height: 28px;
  border-radius: 8px;
  border: 1px solid var(--card-border);
  background: transparent;
  color: var(--text-muted);
  cursor: pointer;
  transition: all 0.18s ease;
  font-size: 0.7rem;
  flex-shrink: 0;
}
.rede-close-btn:hover {
  background: color-mix(in srgb, var(--text-muted) 14%, transparent);
  color: var(--text-color);
  border-color: var(--text-muted);
}

/* ══ PERÍODO ════════════════════════════════════════════════════════════ */
.rede-periodo-bar {
  display: flex;
  align-items: center;
  gap: 0.45rem;
  padding: 0.5rem 1.25rem;
  background: color-mix(in srgb, var(--text-color) 3%, transparent);
  border-bottom: 1px solid var(--card-border);
  font-size: 0.75rem;
  color: var(--text-muted);
}
.rede-periodo-bar i { font-size: 0.78rem; color: var(--primary-color); }
.rede-periodo-label { font-weight: 600; }
.rede-periodo-val {
  font-weight: 800;
  color: var(--text-color);
  font-family: var(--font-mono, monospace);
  font-size: 0.78rem;
}

/* ══ LOADING ═════════════════════════════════════════════════════════════ */
.rede-loading {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 0.75rem;
  padding: 3rem 1rem;
  font-size: 0.82rem;
  color: var(--text-muted);
}

.rede-loading-pulse i {
  font-size: 1.5rem;
  color: var(--primary-color);
}

/* ══ TABELA ══════════════════════════════════════════════════════════════ */
.rede-table-wrap {
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

/* Colunas compartilhadas */
.col-num      { width: 36px;  flex-shrink: 0; text-align: center; }
.col-cnpj     { width: 165px; flex-shrink: 0; }
.col-loc      { flex: 1;      min-width: 0;   }
.col-mov      { width: 130px; flex-shrink: 0; text-align: right; }
.col-irr      { width: 120px; flex-shrink: 0; text-align: right; }
.col-bar      { width: 64px;  flex-shrink: 0; }

/* Cabeçalho */
.rede-thead {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.45rem 1rem;
  background: var(--tabs-bg);
  border-bottom: 1px solid var(--card-border);
  font-size: 0.62rem;
  font-weight: 800;
  text-transform: uppercase;
  letter-spacing: 0.07em;
  color: var(--text-muted);
  position: sticky;
  top: 0;
  z-index: 2;
}

/* Body */
.rede-tbody {
  max-height: 380px;
  overflow-y: auto;
  display: flex;
  flex-direction: column;
}

/* Scrollbar discreta */
.rede-tbody::-webkit-scrollbar { width: 4px; }
.rede-tbody::-webkit-scrollbar-track { background: transparent; }
.rede-tbody::-webkit-scrollbar-thumb {
  background: color-mix(in srgb, var(--text-muted) 30%, transparent);
  border-radius: 2px;
}

/* Linha */
.rede-row {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.55rem 1rem;
  border-bottom: 1px solid color-mix(in srgb, var(--card-border) 60%, transparent);
  transition: background 0.15s ease;
}
.rede-row:last-child { border-bottom: none; }
.rede-row:hover {
  background: color-mix(in srgb, var(--primary-color) 5%, transparent);
}

.rede-row--current {
  background: color-mix(in srgb, var(--primary-color) 8%, transparent) !important;
  border-left: 3px solid var(--primary-color);
  padding-left: calc(1rem - 3px);
}

.rede-row--risk {
  border-left: 3px solid #ef4444;
  padding-left: calc(1rem - 3px);
}
.rede-row--risk.rede-row--current {
  border-left-color: var(--primary-color);
}

/* Numeração */
.row-num {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 24px;
  height: 20px;
  border-radius: 4px;
  background: color-mix(in srgb, var(--text-color) 6%, transparent);
  color: var(--text-muted);
  font-size: 0.62rem;
  font-weight: 800;
  font-family: var(--font-mono, monospace);
}

/* CNPJ */
.cnpj-link {
  display: inline-flex;
  align-items: center;
  gap: 0.3rem;
  font-family: var(--font-mono, monospace);
  font-size: 0.8rem;
  font-weight: 700;
  color: var(--primary-color);
  text-decoration: none;
  transition: opacity 0.15s;
}
.cnpj-link:hover { text-decoration: underline; opacity: 0.85; }
.cnpj-ext { font-size: 0.6rem; opacity: 0.55; }

.cnpj-current {
  display: inline-flex;
  align-items: center;
  gap: 0.4rem;
  font-family: var(--font-mono, monospace);
  font-size: 0.8rem;
  font-weight: 700;
  color: var(--text-color);
}

.badge-atual {
  font-size: 0.55rem;
  font-weight: 800;
  letter-spacing: 0.06em;
  color: var(--primary-color);
  background: color-mix(in srgb, var(--primary-color) 12%, transparent);
  border: 1px solid color-mix(in srgb, var(--primary-color) 28%, transparent);
  border-radius: 4px;
  padding: 1px 5px;
}

/* Localização */
.loc-mun {
  display: block;
  font-size: 0.8rem;
  font-weight: 500;
  color: var(--text-color);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.loc-uf {
  display: inline-block;
  margin-top: 0.1rem;
  font-size: 0.62rem;
  font-weight: 800;
  color: var(--text-muted);
  background: color-mix(in srgb, var(--text-color) 7%, transparent);
  border-radius: 3px;
  padding: 0 4px;
}

/* Valores */
.val-mov {
  font-family: var(--font-mono, monospace);
  font-size: 0.8rem;
  font-weight: 600;
  color: var(--text-secondary);
  display: block;
}

.val-irr {
  font-family: var(--font-mono, monospace);
  font-size: 0.8rem;
  font-weight: 700;
  display: block;
}
.val-irr--zero { color: var(--text-muted); }
.val-irr--mid  { color: #f59e0b; }
.val-irr--high { color: #ef4444; }

.val-perc {
  font-size: 0.68rem;
  font-weight: 700;
  color: var(--text-muted);
  display: block;
}

/* Barra de risco */
.risk-bar-track {
  height: 4px;
  border-radius: 99px;
  background: color-mix(in srgb, var(--text-color) 8%, transparent);
  overflow: hidden;
}
.risk-bar-fill {
  height: 100%;
  border-radius: 99px;
  transition: width 0.4s ease;
}
.fill--low  { background: #22c55e; }
.fill--mid  { background: #f59e0b; }
.fill--high { background: #ef4444; }

/* ══ VAZIO ═══════════════════════════════════════════════════════════════ */
.rede-empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 0.6rem;
  padding: 3rem 1rem;
  font-size: 0.82rem;
  color: var(--text-muted);
  opacity: 0.7;
}
.rede-empty i { font-size: 1.8rem; }
</style>
