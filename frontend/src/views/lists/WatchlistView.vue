<script setup>
import { computed } from "vue";
import { useRouter } from "vue-router";
import { useFarmaciaListsStore } from "@/stores/farmaciaLists";
import { useAnalyticsStore } from "@/stores/analytics";
import { useGeoStore } from "@/stores/geo";
import { useFormatting } from "@/composables/useFormatting";

const router = useRouter();
const farmaciaLists = useFarmaciaListsStore();
const analyticsStore = useAnalyticsStore();
const geoStore = useGeoStore();
const { formatBRL } = useFormatting();

const formatCnpj = (v) => {
  if (!v) return "—";
  const clean = v.replace(/\D/g, "");
  if (clean.length !== 14) return v;
  return clean.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/, "$1.$2.$3/$4-$5");
};

const formatDate = (iso) => {
  if (!iso) return "—";
  return new Date(iso).toLocaleDateString("pt-BR", {
    day: "2-digit", month: "2-digit", year: "numeric",
  });
};

// Map O(1): cnpj → dados analíticos (percValSemComp, score, totalMov, valSemComp, municipio, uf)
const analyticsMap = computed(() => {
  const map = new Map();
  for (const e of (analyticsStore.resultadoCnpjs || [])) {
    map.set(e.cnpj, e);
  }
  return map;
});

// Map O(1): cnpj → geo (municipio, uf) — fallback quando não está no escopo dos filtros
const geoMap = computed(() => {
  const map = new Map();
  for (const e of geoStore.cnpjLookup) {
    map.set(e.cnpj, e);
  }
  return map;
});

const RISCO_COLOR = {
  'CRÍTICO':  '#ef4444',
  'ALTO':     '#f97316',
  'MÉDIO':    '#f59e0b',
  'BAIXO':    '#10b981',
};

// Lista enriquecida — une store + analytics + geo
const listaEnriquecida = computed(() =>
  farmaciaLists.interesse.map((item) => {
    const a = analyticsMap.value.get(item.cnpj) ?? {};
    const g = geoMap.value.get(item.cnpj)      ?? {};
    return {
      ...item,
      razaoSocial:    item.razaoSocial || a.razao_social || g.razao_social || '—',
      municipio:      a.municipio      || g.municipio    || '—',
      uf:             a.uf             || g.uf           || '—',
      percValSemComp: a.percValSemComp ?? g.percValSemComp ?? null,
      scoreRisco:     a.score_risco_final ?? g.score_risco ?? null,
      classificacao:  a.classificacao_risco ?? g.classificacao_risco ?? null,
      totalMov:       a.totalMov   ?? g.totalMov   ?? null,
      valSemComp:     a.valSemComp ?? g.valSemComp ?? null,
    };
  })
);

const totalBadge = computed(() => farmaciaLists.interesse.length);

function remover(cnpj) {
  farmaciaLists.toggleInteresse(cnpj, "");
}

function abrirEstabelecimento(cnpj) {
  router.push(`/estabelecimentos/${cnpj}`);
}

function formatPerc(v) {
  if (v == null) return '—';
  return `${v.toFixed(1)}%`;
}

function formatScore(v) {
  if (v == null) return '—';
  return v.toFixed(3);
}
</script>

<template>
  <div class="lists-view">
    <div class="lists-header">
      <div class="lists-title">
        <i class="pi pi-bookmark" />
        <h2>Farmácias Monitoradas</h2>
        <span class="total-badge" v-if="totalBadge > 0">{{ totalBadge }}</span>
      </div>
      <p class="lists-subtitle">
        CNPJs adicionados à Lista de Interesse para acompanhamento manual. Os indicadores refletem o escopo de filtros atual.
      </p>
    </div>

    <div class="lists-card">
      <div class="card-header">
        <div class="card-header-left">
          <i class="pi pi-table" />
          <span>Estabelecimentos monitorados</span>
        </div>
        <span v-if="totalBadge > 0" class="card-count">{{ totalBadge }} registros</span>
      </div>

      <div class="lists-content">
        <div v-if="farmaciaLists.interesse.length === 0" class="empty-state">
          <i class="pi pi-star empty-icon" />
          <p>Nenhuma farmácia na Lista de Interesse.</p>
          <span>Acesse o detalhe de um estabelecimento e clique no ícone de estrela.</span>
        </div>

      <table v-else class="lists-table">
        <thead>
          <tr>
            <th>#</th>
            <th>CNPJ</th>
            <th>Razão Social</th>
            <th>Município / UF</th>
            <th class="col-right">% N. Comp.</th>
            <th class="col-right">Score de Risco</th>
            <th class="col-right">Total Movimentado</th>
            <th class="col-right">Valor s/ Comp.</th>
            <th>Adicionado em</th>
            <th class="col-actions">Ações</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="(item, i) in listaEnriquecida" :key="item.cnpj">
            <td class="col-num">{{ i + 1 }}</td>
            <td class="col-cnpj">{{ formatCnpj(item.cnpj) }}</td>
            <td class="col-razao">{{ item.razaoSocial }}</td>
            <td class="col-loc">
              <span v-if="item.municipio !== '—'">{{ item.municipio }}</span>
              <span v-if="item.uf !== '—'" class="col-uf">/{{ item.uf }}</span>
              <span v-if="item.municipio === '—'">—</span>
            </td>
            <td class="col-right col-perc">
              <span v-if="item.percValSemComp != null"
                :class="['perc-badge', item.percValSemComp >= 50 ? 'perc-alto' : item.percValSemComp >= 20 ? 'perc-medio' : 'perc-baixo']">
                {{ formatPerc(item.percValSemComp) }}
              </span>
              <span v-else class="col-vazio">—</span>
            </td>
            <td class="col-right col-score">
              <span v-if="item.scoreRisco != null"
                class="score-badge"
                :style="{ color: RISCO_COLOR[item.classificacao] || 'var(--text-muted)' }">
                {{ formatScore(item.scoreRisco) }}
                <span v-if="item.classificacao" class="score-class">{{ item.classificacao }}</span>
              </span>
              <span v-else class="col-vazio">—</span>
            </td>
            <td class="col-right col-money">
              {{ item.totalMov != null ? formatBRL(item.totalMov) : '—' }}
            </td>
            <td class="col-right col-money col-sem-comp">
              {{ item.valSemComp != null ? formatBRL(item.valSemComp) : '—' }}
            </td>
            <td class="col-date">{{ formatDate(item.adicionadoEm) }}</td>
            <td class="col-actions">
              <div class="action-btns">
                <button
                  class="action-btn open"
                  @click="abrirEstabelecimento(item.cnpj)"
                  v-tooltip.top="'Abrir detalhamento'"
                >
                  <i class="pi pi-arrow-up-right" />
                </button>
                <button
                  class="action-btn remove"
                  @click="remover(item.cnpj)"
                  v-tooltip.top="'Remover da lista'"
                >
                  <i class="pi pi-trash" />
                </button>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
      </div><!-- /lists-content -->
    </div><!-- /lists-card -->
  </div>
</template>

<style scoped>
.lists-view {
  padding: 2rem;
  display: flex;
  flex-direction: column;
  gap: 1.5rem;
  max-width: 1300px;
}

.lists-header {
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
  border-bottom: 1px solid var(--tabs-border);
  padding-bottom: 1.5rem;
}

.lists-title {
  display: flex;
  align-items: center;
  gap: 0.75rem;
}

.lists-title i {
  font-size: 1.2rem;
  color: var(--primary-color);
}

.lists-title h2 {
  font-size: 1.2rem;
  font-weight: 600;
  margin: 0;
  color: var(--text-color);
}

.total-badge {
  font-size: 0.72rem;
  font-weight: 600;
  padding: 0.1rem 0.5rem;
  border-radius: 20px;
  background: color-mix(in srgb, var(--primary-color) 15%, transparent);
  color: var(--primary-color);
  border: 1px solid color-mix(in srgb, var(--primary-color) 25%, transparent);
}

.lists-subtitle {
  font-size: 0.8rem;
  color: var(--text-color);
  opacity: 0.5;
  margin: 0;
}

.empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 6rem 2rem;
  gap: 0.75rem;
  color: var(--text-color);
  opacity: 0.4;
}

.empty-icon { font-size: 2.5rem; }
.empty-state p { font-size: 0.95rem; font-weight: 600; margin: 0; }
.empty-state span { font-size: 0.8rem; }

/* Card container */
.lists-card {
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  border-radius: 14px;
  overflow: hidden;
  box-shadow: 0 4px 16px rgba(0, 0, 0, 0.06);
}

.card-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0.85rem 1.25rem;
  border-bottom: 1px solid var(--card-border);
  background: rgba(255, 255, 255, 0.02);
}

.card-header-left {
  display: flex;
  align-items: center;
  gap: 0.6rem;
  font-size: 0.78rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--text-color);
}

.card-header-left i {
  color: var(--primary-color);
  font-size: 1rem;
}

.card-count {
  font-size: 0.7rem;
  font-weight: 500;
  color: var(--text-muted);
}

.lists-content {
  overflow-x: auto;
}

.lists-table {
  width: 100%;
  border-collapse: collapse;
  background: transparent;
}

.lists-table th {
  padding: 0.7rem 0.9rem;
  font-size: 0.68rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--text-color);
  opacity: 0.5;
  background: color-mix(in srgb, var(--card-bg) 85%, var(--card-border));
  border-bottom: 1px solid var(--card-border);
  text-align: left;
  white-space: nowrap;
}

.lists-table th.col-right { text-align: right; }

.lists-table td {
  padding: 0.7rem 0.9rem;
  font-size: 0.8rem;
  color: var(--text-color);
  border-bottom: 1px solid var(--card-border);
  vertical-align: middle;
}

.lists-table tbody tr:last-child td { border-bottom: none; }
.lists-table tbody tr:hover {
  background: color-mix(in srgb, var(--primary-color) 4%, transparent);
}

.col-num   { width: 36px; opacity: 0.4; font-weight: 600; }
.col-cnpj  { font-family: ui-monospace, monospace; font-size: 0.75rem; white-space: nowrap; }
.col-razao { font-weight: 500; max-width: 220px; }
.col-date  { opacity: 0.55; font-size: 0.76rem; white-space: nowrap; }
.col-right { text-align: right; }
.col-vazio { opacity: 0.3; }
.col-money { font-size: 0.78rem; white-space: nowrap; }
.col-sem-comp { color: var(--risk-critical); opacity: 0.85; }

.col-loc { font-size: 0.78rem; white-space: nowrap; }
.col-uf  { opacity: 0.55; margin-left: 1px; }

/* Badge % Não Comprovação */
.perc-badge {
  display: inline-block;
  padding: 0.15rem 0.45rem;
  border-radius: 4px;
  font-size: 0.75rem;
  font-weight: 600;
}
.perc-alto  { background: color-mix(in srgb, #ef4444 12%, transparent); color: #ef4444; }
.perc-medio { background: color-mix(in srgb, #f59e0b 12%, transparent); color: #f59e0b; }
.perc-baixo { background: color-mix(in srgb, #10b981 12%, transparent); color: #10b981; }

/* Score de Risco */
.score-badge {
  display: inline-flex;
  align-items: center;
  gap: 0.35rem;
  font-size: 0.78rem;
  font-weight: 600;
}
.score-class {
  font-size: 0.65rem;
  font-weight: 500;
  opacity: 0.75;
  background: color-mix(in srgb, currentColor 10%, transparent);
  padding: 0.1rem 0.3rem;
  border-radius: 3px;
}

.col-actions { width: 80px; text-align: center; }

.action-btns {
  display: flex;
  gap: 0.4rem;
  justify-content: center;
}

.action-btn {
  width: 28px;
  height: 28px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border-radius: 6px;
  border: 1px solid var(--tabs-border);
  background: none;
  cursor: pointer;
  transition: all 0.15s ease;
  font-size: 0.72rem;
  color: var(--text-color);
  opacity: 0.6;
}
.action-btn:hover { opacity: 1; }
.action-btn.open:hover {
  border-color: var(--primary-color);
  color: var(--primary-color);
  background: color-mix(in srgb, var(--primary-color) 8%, transparent);
}
.action-btn.remove:hover {
  border-color: var(--risk-critical);
  color: var(--risk-critical);
  background: color-mix(in srgb, var(--risk-critical) 8%, transparent);
}
</style>
