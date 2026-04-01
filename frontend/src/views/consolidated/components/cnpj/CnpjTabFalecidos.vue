<script setup>
import { computed, ref, watch, onMounted } from 'vue';
import { useFalecidos } from '@/composables/useFalecidos';
import { useFormatting } from '@/composables/useFormatting';
import { useChartTheme } from '@/config/chartTheme';
import Tag from 'primevue/tag';
import FalecidosTimelineOverlay from './FalecidosTimelineOverlay.vue';

const props = defineProps({
  cnpj: {
    type: String,
    required: true
  }
});

const { falecidosData, falecidosLoading, falecidosLoaded, fetchFalecidos } = useFalecidos();
const { formatCurrencyFull, formatarData, formatTitleCase, formatCnpj } = useFormatting();
const { chartDataColors } = useChartTheme();

onMounted(() => {
  if (props.cnpj && !falecidosLoaded.value) {
    fetchFalecidos(props.cnpj);
  }
});

watch(() => props.cnpj, (newCnpj) => {
  if (newCnpj) fetchFalecidos(newCnpj);
});

const falecidosAgrupados = computed(() => {
  const transacoes = falecidosData.value?.transacoes ?? [];
  const grupos = new Map();
  for (const t of transacoes) {
    if (!grupos.has(t.cpf)) {
      grupos.set(t.cpf, {
        cpf:           t.cpf,
        nome:          formatTitleCase(t.nome_falecido) || 'Não Identificado',
        municipio:     formatTitleCase(t.municipio_falecido),
        uf:            t.uf_falecido,
        dt_obito:      formatarData(t.dt_obito),
        dt_nascimento: formatarData(t.dt_nascimento),
        outros_cnpj:   t.outros_estabelecimentos,
        transacoes:    [],
        total_valor:   0,
        max_dias:      0,
      });
    }
    const g = grupos.get(t.cpf);
    g.transacoes.push({ ...t, nome_falecido: formatTitleCase(t.nome_falecido) });
    g.total_valor += t.valor_total_autorizacao ?? 0;
    g.max_dias = Math.max(g.max_dias, t.dias_apos_obito ?? 0);
  }
  return [...grupos.values()];
});

const timelineOverlay = ref(null);

const toggleMultiCnpj = (event, grupo) => {
  timelineOverlay.value?.open(event, grupo);
};

const openEstablishment = (estabStr) => {
  if (!estabStr) return;
  const targetCnpj = estabStr.split(' - ')[0];
  window.open(`/estabelecimento/${targetCnpj}`, '_blank');
};

</script>

<template>
  <div class="tab-content falecidos-tab">
    <div v-if="falecidosLoading" class="tab-placeholder">
      <i class="pi pi-spin pi-spinner placeholder-icon" />
      <p>Analisando base de óbitos...</p>
    </div>

    <div v-else-if="falecidosLoaded && !falecidosData?.transacoes?.length" class="tab-placeholder">
      <i class="pi pi-check-circle placeholder-icon" style="color: var(--green-500)" />
      <p>Nenhuma venda para falecidos encontrada neste estabelecimento.</p>
    </div>

    <template v-else-if="falecidosLoaded">
      <!-- 7 CARDS DE KPI -->
      <div class="falecidos-kpi-grid">
        <div class="f-kpi-card">
          <span class="f-kpi-label">CPFs Distintos</span>
          <span class="f-kpi-val">{{ falecidosData.summary.cpfs_distintos }}</span>
        </div>
        <div class="f-kpi-card">
          <span class="f-kpi-label">Vendas Afetadas</span>
          <span class="f-kpi-val">{{ falecidosData.summary.total_autorizacoes }}</span>
        </div>
        <div class="f-kpi-card highlight-red">
          <span class="f-kpi-label">Prejuízo Estimado</span>
          <div class="f-kpi-val-container">
            <span class="f-kpi-val risk-high">{{ formatCurrencyFull(falecidosData.summary.valor_total) }}</span>
          </div>
        </div>
        <div class="f-kpi-card">
          <span class="f-kpi-label">Média Dias Pós-Óbito</span>
          <span class="f-kpi-val">{{ falecidosData.summary.media_dias.toFixed(1) }} <small>dias</small></span>
        </div>
        <div class="f-kpi-card">
          <span class="f-kpi-label">Máximo Dias Pós-Óbito</span>
          <span class="f-kpi-val">{{ falecidosData.summary.max_dias }} <small>dias</small></span>
        </div>
        <div class="f-kpi-card">
          <span class="f-kpi-label">% do Faturamento</span>
          <span class="f-kpi-val">{{ (falecidosData.summary.pct_faturamento * 100).toFixed(3) }}%</span>
        </div>
        <div class="f-kpi-card warning">
          <span class="f-kpi-label">CPFs Multi-CNPJ</span>
          <span class="f-kpi-val">{{ falecidosData.summary.cpfs_multi_cnpj }} <small>({{ (falecidosData.summary.pct_multi_cnpj * 100).toFixed(1) }}%)</small></span>
        </div>
      </div>

      <!-- PAINEL MULTI-CNPJ -->
      <div class="falecidos-ranking-panel" v-if="falecidosData.ranking?.length">
        <div class="section-title">
          <i class="pi pi-share-alt" />
          <span>Rank de Coincidência em Outros Estabelecimentos</span>
        </div>
        <div class="ranking-grid">
          <div v-for="r in falecidosData.ranking" :key="r.estabelecimento" class="ranking-card" @click="openEstablishment(r.estabelecimento)" v-tooltip.top="'Clique para abrir detalhamento desta farmácia'">
            <div class="r-card-header">
              <div class="r-icon-box">
                <i class="pi pi-building" />
              </div>
              <div class="r-info">
                <span class="r-name" :title="r.estabelecimento">{{ r.estabelecimento.split(' - ')[1]?.split(' | ')[0] || r.estabelecimento }}</span>
                <span class="r-meta">{{ formatCnpj(r.estabelecimento.split(' - ')[0]) }}</span>
              </div>
            </div>
            <div class="r-card-body">
              <div class="r-stats">
                <span class="r-qty">{{ r.qtd_cpfs }}</span>
                <span class="r-label">CPFs Concomitantes</span>
              </div>
              <div class="r-progress-wrap">
                <div class="r-progress-bg">
                  <div class="r-progress-fill" :style="{ width: (r.pct_total * 100) + '%' }"></div>
                </div>
                <span class="r-pct">{{ Math.round(r.pct_total * 100) }}%</span>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- TABELA DE TRANSAÇÕES -->
      <div class="falecidos-list-container">
        <div class="section-title">
          <i class="pi pi-list" />
          <span>Detalhamento de Transações (Agrupado por CPF)</span>
        </div>
        <div class="f-table-wrap">
          <table class="f-table">
            <colgroup>
              <col style="width: 10%" />
              <col style="width: 18%" />
              <col style="width: 12%" />
              <col style="width: 6%" />
              <col style="width: 13%" />
              <col style="width: 8%" />
              <col style="width: 10%" />
              <col style="width: 6%" />
              <col style="width: 9%" />
              <col style="width: 8%" />
            </colgroup>
            <thead>
              <tr>
                <th>CPF</th>
                <th>Nome do Falecido</th>
                <th>Município / UF</th>
                <th>Fonte Óbito</th>
                <th>Nº Autorização</th>
                <th>Dt. Óbito</th>
                <th>Data da Venda</th>
                <th>Itens</th>
                <th>Valor (R$)</th>
                <th class="txt-center">Dias após Óbito</th>
              </tr>
            </thead>
            <tbody>
              <template v-for="grupo in falecidosAgrupados" :key="grupo.cpf">
                <tr class="f-group-header">
                  <td colspan="10">
                    <span class="f-group-cpf">{{ grupo.cpf }}</span>
                    <span class="f-group-nome">{{ grupo.nome }}</span>
                    <span class="f-group-sep">—</span>
                    <span class="f-group-meta">{{ grupo.transacoes.length }} autorização(ões)</span>
                    <span class="f-group-sep">|</span>
                    <span class="f-group-meta">{{ formatCurrencyFull(grupo.total_valor) }}</span>
                    <span class="f-group-sep">|</span>
                    <span class="f-group-meta">Óbito: {{ grupo.dt_obito }}</span>
                    <Tag 
                      v-if="grupo.outros_cnpj" 
                      icon="pi pi-share-alt" 
                      value="MULTI-CNPJ" 
                      class="f-multi-tag risk-medium clickable-badge" 
                      @click="(e) => toggleMultiCnpj(e, grupo)"
                      style="margin-left: 0.75rem;" 
                    />
                  </td>
                </tr>
                <tr v-for="t in grupo.transacoes" :key="t.num_autorizacao" class="f-row">
                  <td class="f-cpf-cell">{{ t.cpf }}</td>
                  <td>
                    <span class="f-nome">{{ t.nome_falecido || 'Não Identificado' }}</span>
                  </td>
                  <td class="f-date">{{ grupo.municipio }}/{{ grupo.uf }}</td>
                  <td class="f-fonte">
                    <span v-if="t.fonte_obito && t.fonte_obito.length > 10" v-tooltip.top="t.fonte_obito" style="cursor: default">
                      {{ t.fonte_obito.substring(0, 10) }}...
                    </span>
                    <span v-else>{{ t.fonte_obito }}</span>
                  </td>
                  <td class="f-aut">{{ t.num_autorizacao }}</td>
                  <td class="f-date">{{ formatarData(t.dt_obito) }}</td>
                  <td class="f-date">{{ formatarData(t.data_autorizacao) }}</td>
                  <td class="f-num">{{ t.qtd_itens_na_autorizacao }}</td>
                  <td class="f-val">{{ formatCurrencyFull(t.valor_total_autorizacao) }}</td>
                  <td class="txt-center">
                    <span class="f-days-badge" :class="{
                      'd-critical': t.dias_apos_obito > 365,
                      'd-high': t.dias_apos_obito > 30 && t.dias_apos_obito <= 365,
                      'd-medium': t.dias_apos_obito <= 30
                    }">
                      {{ t.dias_apos_obito }} d
                    </span>
                  </td>
                </tr>
                <tr class="f-subtotal-row">
                  <td colspan="8" class="f-subtotal-label">Subtotal — {{ grupo.transacoes.length }} autorização(ões)</td>
                  <td class="f-val f-subtotal-val">{{ formatCurrencyFull(grupo.total_valor) }}</td>
                  <td></td>
                </tr>
              </template>
            </tbody>
            <tfoot>
              <tr class="f-grand-total">
                <td colspan="8">
                  TOTAL GERAL — {{ falecidosAgrupados.length }} CPF(s) distintos — {{ falecidosData.transacoes.length }} autorização(ões)
                </td>
                <td class="f-val">{{ formatCurrencyFull(falecidosData.summary.valor_total) }}</td>
                <td></td>
              </tr>
            </tfoot>
          </table>
        </div>
      </div>
    </template>

    <div v-else class="tab-placeholder">
      <i class="pi pi-exclamation-triangle placeholder-icon" />
      <p>Clique na aba para processar a análise de óbitos.</p>
    </div>

    <FalecidosTimelineOverlay ref="timelineOverlay" :current-cnpj="cnpj" />
  </div>
</template>

<style scoped>
.falecidos-tab {
  padding: 1rem 0 0;
  display: flex;
  flex-direction: column;
  gap: 1.5rem;
}

.falecidos-kpi-grid {
  display: grid;
  grid-template-columns: repeat(7, 1fr);
  gap: 0.75rem;
}

.f-kpi-card {
  background: var(--card-bg);
  border: 1px solid var(--sidebar-border);
  padding: 0.75rem;
  border-radius: 8px;
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
}

.f-kpi-label {
  font-size: 0.62rem;
  font-weight: 700;
  color: var(--text-secondary);
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

.f-kpi-val-container {
  display: flex;
  margin-top: 0.2rem;
}

.f-kpi-val {
  font-size: 1.1rem;
  font-weight: 700;
  color: var(--text-primary);
}

.f-kpi-val.risk-high {
  font-size: 0.95rem; /* Leve ajuste para caber no badge */
  padding: 0.1rem 0.6rem;
  border-radius: 99px;
}

.f-kpi-val small {
  font-size: 0.7rem;
  opacity: 0.6;
}

.highlight-red {
  background: color-mix(in srgb, var(--risk-high) 8%, var(--card-bg)) !important;
  border-color: color-mix(in srgb, var(--risk-high) 25%, transparent) !important;
  border-left: 3px solid v-bind('chartDataColors.red') !important;
}

.highlight-red .f-kpi-label { color: var(--risk-high) !important; opacity: 0.75; }
.highlight-red .f-kpi-val {
  color: v-bind('chartDataColors.red') !important;
  font-weight: 700;
}

.warning {
  background: color-mix(in srgb, var(--risk-medium) 12%, var(--card-bg)) !important;
  border-color: color-mix(in srgb, var(--risk-medium) 35%, transparent) !important;
}
.warning .f-kpi-val { color: var(--risk-medium) !important; }
.warning .f-kpi-label { color: var(--risk-medium) !important; opacity: 0.85; }

.falecidos-list-container {
  margin-top: 1.5rem;
}

.section-title {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  font-size: 0.85rem;
  font-weight: 700;
  text-transform: uppercase;
  color: var(--text-color);
  margin-bottom: 1rem;
  letter-spacing: 0.05em;
}

.section-title i {
  color: var(--primary-color);
  font-size: 0.9rem;
}

/* Tabela de Falecidos */
.f-table-wrap {
  background: var(--card-bg);
  border: 1px solid var(--sidebar-border);
  border-radius: 10px;
  overflow: hidden;
}

.f-table {
  width: 100%;
  border-collapse: collapse;
}

.f-table th {
  text-align: left;
  padding: 0.75rem 1rem;
  background: var(--table-header-bg);
  font-size: 0.85rem;
  font-weight: 700;
  text-transform: none;
  letter-spacing: 0.06em;
  color: var(--table-header-text);
  border-bottom: 1px solid var(--sidebar-border);
}

.f-table td {
  padding: 0.75rem 1rem;
  border-bottom: 1px solid var(--sidebar-border);
  font-size: 0.8rem;
  color: var(--text-color);
}

.f-row:hover td { background: rgba(255,255,255,0.02); }

.f-nome { font-weight: 600; font-size: 0.82rem; text-transform: none !important; }

.f-multi-tag {
  align-self: flex-start;
  font-size: 0.65rem !important;
  margin-top: 0.1rem;
  height: auto;
  padding: 0.1rem 0.5rem;
  background: transparent;
  border-radius: 99px;
}

.clickable-badge {
  cursor: pointer;
  transition: transform 0.1s;
}
.clickable-badge:hover { transform: scale(1.05); }


.f-date, .f-aut, .f-num, .f-val { font-size: 0.78rem; }
.f-date { text-transform: none !important; }
.f-num, .f-val { font-weight: 500; }

.txt-center { text-align: center !important; }

.f-days-badge {
  display: inline-block;
  padding: 0.25rem 0.65rem;
  border-radius: 6px;
  font-size: 0.82rem;
  font-weight: 700;
}

.d-medium   { background: color-mix(in srgb, var(--risk-medium)   15%, transparent); color: var(--risk-medium);   border: 1px solid color-mix(in srgb, var(--risk-medium) 30%, transparent); }
.d-high     { background: color-mix(in srgb, var(--risk-high)     15%, transparent); color: var(--risk-high);     border: 1px solid color-mix(in srgb, var(--risk-high)   30%, transparent); }
.d-critical { 
  background: color-mix(in srgb, var(--risk-critical) 15%, transparent); 
  color: var(--risk-critical); 
  border: 1px solid color-mix(in srgb, var(--risk-critical) 30%, transparent); 
  font-weight: 800; 
}

.f-cpf-cell { font-family: monospace; font-size: 0.75rem; color: var(--text-secondary); }
.f-fonte { font-size: 0.72rem; color: var(--text-secondary); }

/* ── Linha de cabeçalho do grupo (por falecido) ── */
.f-group-header td {
  background: color-mix(in srgb, var(--primary-color) 5%, var(--card-bg));
  border-top: 1px solid var(--sidebar-border);
  padding: 0.55rem 1rem;
  font-size: 0.78rem;
}

.f-group-cpf {
  font-family: monospace;
  font-weight: 600;
  color: var(--text-secondary);
  margin-right: 0.6rem;
}

.f-group-nome {
  font-weight: 600;
  font-size: 0.82rem;
  color: var(--text-color);
  letter-spacing: 0.03em;
  margin-right: 0.4rem;
  text-transform: none !important;
}

.f-group-sep {
  color: var(--text-secondary);
  margin: 0 0.4rem;
  opacity: 0.6;
}

.f-group-meta {
  font-size: 0.76rem;
  font-weight: 600;
  color: var(--text-secondary);
  text-transform: none !important;
}

/* ── Linha de subtotal por falecido ── */
.f-subtotal-row td {
  background: var(--card-bg);
  border-top: 1px solid var(--sidebar-border);
  border-bottom: 2px solid var(--sidebar-border);
  padding: 0.4rem 1rem;
}

.f-subtotal-label {
  font-size: 0.72rem;
  font-weight: 700;
  text-transform: none !important;
  letter-spacing: 0.04em;
  color: var(--text-secondary);
  text-align: right;
}

.f-subtotal-val {
  font-weight: 700 !important;
  color: var(--text-secondary) !important;
}

/* ── Total geral (tfoot) ── */
.f-grand-total td {
  background: var(--table-header-bg);
  border-top: 1px solid var(--sidebar-border);
  padding: 0.65rem 1rem;
  font-size: 0.78rem;
  font-weight: 700;
  text-transform: none !important;
  letter-spacing: 0.04em;
  color: var(--table-header-text);
}

.f-grand-total .f-val {
  color: var(--text-secondary) !important;
  font-size: 0.88rem;
}

/* Ranking Panel */
.falecidos-ranking-panel {
  background: var(--card-bg);
  border: 1px solid var(--sidebar-border);
  border-radius: 12px;
  padding: 1.25rem;
  margin-top: 1.5rem;
  box-shadow: 0 4px 15px rgba(0,0,0,0.1);
}

.ranking-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
  gap: 0.75rem;
  margin-top: 0.75rem;
}

.ranking-card {
  background: rgba(0,0,0,0.03);
  border: 1px solid var(--sidebar-border);
  border-radius: 10px;
  padding: 0.75rem 1rem;
  transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
  cursor: pointer;
}

:global(.dark-mode) .ranking-card {
  background: rgba(255,255,255,0.03);
  border-color: rgba(255,255,255,0.08);
}

.ranking-card:hover {
  background: rgba(255,255,255,0.05);
  border-color: var(--primary-color);
  transform: translateY(-2px);
  box-shadow: 0 4px 12px rgba(0,0,0,0.15);
}

.r-card-header {
  display: flex;
  align-items: center;
  gap: 0.6rem;
}

.r-icon-box {
  width: 28px;
  height: 28px;
  background: color-mix(in srgb, var(--primary-color) 12%, transparent);
  border-radius: 6px;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--primary-color);
  font-size: 0.8rem;
}

.r-info {
  display: flex;
  flex-direction: column;
  overflow: hidden;
  min-width: 0; 
  flex: 1;
}

.r-name {
  font-size: 0.72rem;
  font-weight: 700;
  color: var(--text-secondary);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  width: 100%;
}

.r-meta {
  font-size: 0.65rem;
  color: var(--text-secondary);
  font-family: monospace;
}

.r-card-body {
  display: flex;
  flex-direction: column;
  gap: 0.35rem;
}

.r-stats {
  display: flex;
  align-items: center;
  gap: 0.35rem;
}

.r-qty {
  font-size: 1.1rem;
  font-weight: 700;
  color: var(--primary-color);
}

.r-label {
  font-size: 0.62rem;
  color: var(--text-secondary);
}

.r-progress-wrap {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  width: 100%;
}

.r-progress-bg {
  flex: 1;
  height: 4px;
  background: rgba(0,0,0,0.05);
  border-radius: 2px;
  overflow: hidden;
}

:global(.dark-mode) .r-progress-bg {
  background: rgba(255,255,255,0.05);
}

.r-progress-fill {
  height: 100%;
  background: linear-gradient(90deg, var(--primary-color), color-mix(in srgb, var(--primary-color) 70%, white));
  border-radius: 2px;
}

.r-pct {
  font-size: 0.65rem;
  color: var(--text-secondary);
  font-weight: 700;
  min-width: 25px;
}

.tab-placeholder {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 1rem;
  min-height: 300px;
  color: var(--text-muted);
  opacity: 0.5;
}

.placeholder-icon {
  font-size: 3rem;
}

.tab-placeholder p {
  font-size: 0.875rem;
}
</style>
