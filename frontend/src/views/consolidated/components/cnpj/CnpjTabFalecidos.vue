<script setup>
import { computed, ref, watch, onMounted } from 'vue';
import { useFalecidos } from '@/composables/useFalecidos';
import { useMultiCnpjTimeline } from '@/composables/useMultiCnpjTimeline';
import { useFormatting } from '@/composables/useFormatting';
import { useChartTheme } from '@/config/chartTheme';
import VChart from 'vue-echarts';
import { use } from 'echarts/core';
import { ScatterChart } from 'echarts/charts';
import { GridComponent, TooltipComponent, DataZoomComponent } from 'echarts/components';
import { CanvasRenderer } from 'echarts/renderers';
import Tag from 'primevue/tag';
import OverlayPanel from 'primevue/overlaypanel';

use([ScatterChart, GridComponent, TooltipComponent, DataZoomComponent, CanvasRenderer]);

const props = defineProps({
  cnpj: {
    type: String,
    required: true
  }
});

const { falecidosData, falecidosLoading, falecidosLoaded, fetchFalecidos } = useFalecidos();
const { timelineData, timelineLoading, fetchTimeline } = useMultiCnpjTimeline();
const { formatCurrencyFull, formatarData } = useFormatting();
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
        nome:          t.nome_falecido || 'NÃO IDENTIFICADO',
        municipio:     t.municipio_falecido,
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
    g.transacoes.push(t);
    g.total_valor += t.valor_total_autorizacao ?? 0;
    g.max_dias = Math.max(g.max_dias, t.dias_apos_obito ?? 0);
  }
  return [...grupos.values()];
});

const opMultiCnpj = ref(null);
const selectedMultiCpf = ref(null);

const toggleMultiCnpj = (event, grupo) => {
  selectedMultiCpf.value = grupo;
  opMultiCnpj.value.toggle(event);
  if (grupo?.cpf && props.cnpj) {
    fetchTimeline(grupo.cpf, props.cnpj);
  }
};

const parseCnpjs = (s) => (s ? s.split(',').map(v => v.trim()) : []);

const parseDateSafe = (v) => {
  if (!v) return null;
  let d = new Date(v);
  if (isNaN(d.getTime()) && typeof v === 'string') {
    const parts = v.split('/');
    if (parts.length === 3) d = new Date(`${parts[2]}-${parts[1]}-${parts[0]}`);
  }
  return isNaN(d.getTime()) ? null : d.getTime();
};

const timelineChartOption = computed(() => {
  if (!timelineData.value || !timelineData.value.events?.length) return null;

  const td = timelineData.value;
  const cnpjsOrdenados = [props.cnpj];
  td.cnpjs_envolvidos.forEach(c => { if (c !== props.cnpj) cnpjsOrdenados.push(c); });

  const labelMap = {};
  td.events.forEach(e => {
    if (!labelMap[e.cnpj]) {
      labelMap[e.cnpj] = e.razao_social
        ? e.razao_social.substring(0, 22) + (e.razao_social.length > 22 ? '…' : '')
        : e.cnpj;
    }
  });
  const yLabels = cnpjsOrdenados.map((c, i) =>
    i === 0 ? `▶ ${labelMap[c] ?? c}` : (labelMap[c] ?? c)
  );
  const cnpjToIdx = Object.fromEntries(cnpjsOrdenados.map((c, i) => [c, i]));

  const dataPoints = td.events.map(e => {
    const ts = parseDateSafe(e.data_autorizacao);
    if (!ts) return null;
    const yIdx = cnpjToIdx[e.cnpj] ?? 0;
    return {
      value: [ts, yIdx, e.valor_total_autorizacao ?? 0, e.num_autorizacao ?? ''],
      itemStyle: { color: e.is_this_cnpj ? '#3b82f6' : '#f59e0b' }
    };
  }).filter(Boolean);

  const allTs = dataPoints.map(p => p.value[0]);
  const pad = 86400000;
  const minTs = Math.min(...allTs) - pad;
  const maxTs = Math.max(...allTs) + pad;

  return {
    backgroundColor: 'transparent',
    grid: { top: 16, left: 210, right: 30, bottom: 40, containLabel: false },
    tooltip: {
      trigger: 'item',
      backgroundColor: 'rgba(15, 23, 42, 0.95)',
      borderColor: 'rgba(255,255,255,0.15)',
      textStyle: { color: '#fff', fontSize: 11 },
      formatter: (params) => {
        const [ts, yIdx, valor, numAut] = params.value;
        const estLabel = yLabels[yIdx] ?? `CNPJ ${yIdx}`;
        const isRef = yIdx === 0;
        const dataFmt = new Date(ts).toLocaleDateString('pt-BR');
        return `<div style="font-weight:700;margin-bottom:4px;color:${isRef ? '#3b82f6' : '#f59e0b'}">${estLabel}</div>
                <div style="opacity:0.8;">Data: ${dataFmt}</div>
                <div style="margin-top:4px;">Valor: <strong>${formatCurrencyFull(valor)}</strong></div>
                ${numAut ? `<div style="opacity:0.5;font-size:10px;">Aut.: ${numAut}</div>` : ''}`;
      }
    },
    dataZoom: [{ type: 'inside', xAxisIndex: 0, zoomOnMouseWheel: true }],
    xAxis: {
      type: 'time',
      min: minTs,
      max: maxTs,
      axisLine: { lineStyle: { color: 'rgba(255,255,255,0.15)' } },
      splitLine: { show: true, lineStyle: { color: 'rgba(255,255,255,0.06)', type: 'dashed' } },
      axisLabel: {
        color: 'rgba(255,255,255,0.5)',
        fontSize: 9,
        formatter: (v) => {
          const date = new Date(v);
          return date.getFullYear().toString();
        }
      },
      splitNumber: 2,
    },
    yAxis: {
      type: 'category',
      data: yLabels,
      inverse: true,
      axisLine: { show: false },
      axisTick: { show: false },
      axisLabel: {
        color: 'rgba(255,255,255,0.75)',
        fontSize: 9,
        fontWeight: 700,
        width: 160,
        overflow: 'truncate'
      },
      splitLine: { show: true, lineStyle: { color: 'rgba(255,255,255,0.07)' } }
    },
    series: [{
      type: 'scatter',
      data: dataPoints,
      symbolSize: v => Math.max(12, Math.min(24, 12 + Math.log1p(v[2] / 50))),
      encode: { x: 0, y: 1 }
    }]
  };
});

const outrosCnpjList = computed(() => {
  if (timelineData.value?.cnpjs_envolvidos?.length) {
    return timelineData.value.cnpjs_envolvidos.filter(c => c !== props.cnpj);
  }
  if (!selectedMultiCpf.value) return [];
  return parseCnpjs(selectedMultiCpf.value.outros_cnpj);
});

const formatCnpj = (v) => {
  if (!v) return '—';
  const clean = v.replace(/\D/g, '');
  if (clean.length !== 14) return v;
  return clean.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/, '$1.$2.$3/$4-$5');
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
                    <span class="f-nome">{{ t.nome_falecido || 'NÃO IDENTIFICADO' }}</span>
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
  </div>

  <!-- POPOVER MULTI-CNPJ (GRÁFICO DE TRILHAS) -->
  <OverlayPanel ref="opMultiCnpj" class="multi-cnpj-panel" style="width: 900px">
    <div v-if="selectedMultiCpf" class="multi-cnpj-content">
      <header class="multi-header">
        <i class="pi pi-share-alt" />
        <span>Mapa de Relacionamento Temporal</span>
        <i v-if="timelineLoading" class="pi pi-spin pi-spinner" style="margin-left:auto;font-size:0.8rem;opacity:0.6;" />
      </header>

      <div class="multi-cpf-meta">
        <span class="multi-cpf-label">CPF:</span>
        <span class="multi-cpf-val">{{ selectedMultiCpf.cpf }}</span>
        <span class="multi-cpf-sep">·</span>
        <span class="multi-cpf-name">{{ selectedMultiCpf.nome }}</span>
        <span class="multi-cpf-sep">·</span>
        <span class="multi-cpf-obito">Óbito: {{ selectedMultiCpf.dt_obito }}</span>
      </div>

      <p class="multi-desc">Relacionamento gráfico das vendas detectadas nos diferentes estabelecimentos:</p>

      <div class="multi-legend">
        <span class="legend-dot" style="background:#3b82f6"></span><span>Este Estabelecimento</span>
        <span class="legend-dot" style="background:#f59e0b;margin-left:1rem"></span><span>Outro Estabelecimento</span>
      </div>

      <div class="timeline-chart-wrap">
        <div v-if="timelineLoading" class="timeline-loading">
          <i class="pi pi-spin pi-spinner" />
          <span>Buscando transações reais...</span>
        </div>
        <div v-else-if="!timelineChartOption" class="timeline-empty">
          <i class="pi pi-inbox" />
          <span>Sem dados de transações para exibir.</span>
        </div>
        <VChart v-else :option="timelineChartOption" autoresize />
      </div>

      <div class="multi-cnpj-list-section" v-if="outrosCnpjList.length">
        <div class="multi-cnpj-list-title">
          <i class="pi pi-building" />
          <span>CNPJs vinculados ao mesmo CPF</span>
        </div>
        <ul class="multi-list">
          <li v-for="(c, i) in outrosCnpjList" :key="c" class="multi-item">
            <span class="multi-idx">{{ i + 1 }}</span>
            <a :href="`/estabelecimento/${c}`" target="_blank" class="multi-cnpj-link" v-tooltip.bottom="'Abrir detalhamento deste CNPJ em nova aba'">
              {{ formatCnpj(c) }}
              <i class="pi pi-external-link" style="font-size: 0.6rem; margin-left: 0.3rem; opacity: 0.5;" />
            </a>
          </li>
        </ul>
      </div>
    </div>
  </OverlayPanel>
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
  font-weight: 800;
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
  font-size: 0.75rem;
  font-weight: 700;
  text-transform: uppercase;
  color: var(--text-muted);
  margin-bottom: 1rem;
  letter-spacing: 0.05em;
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
  background: color-mix(in srgb, var(--sidebar-border) 40%, var(--card-bg));
  font-size: 0.68rem;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: var(--text-secondary);
  border-bottom: 2px solid var(--sidebar-border);
}

.f-table td {
  padding: 0.75rem 1rem;
  border-bottom: 1px solid var(--sidebar-border);
  font-size: 0.8rem;
  color: var(--text-secondary);
}

.f-row:hover td { background: rgba(255,255,255,0.02); }

.f-beneficiario {
  display: flex;
  flex-direction: column;
}

.f-nome { font-weight: 600; font-size: 0.82rem; }
.f-cpf { font-size: 0.72rem; color: var(--text-muted); font-family: monospace; }

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

/* ── MULTI-CNPJ OVERLAY ────────────────────────────── */
.multi-cnpj-panel {
  background: color-mix(in srgb, var(--card-bg) 85%, transparent) !important;
  backdrop-filter: blur(12px);
  border: 1px solid var(--sidebar-border) !important;
  box-shadow: 0 12px 32px rgba(0,0,0,0.4) !important;
  border-radius: 12px !important;
}

.multi-cnpj-content {
  padding: 0.5rem 0.25rem;
}

.multi-cnpj-panel::before, .multi-cnpj-panel::after {
  display: none !important; /* Remove a seta padrão para um look mais clean */
}

.multi-header {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  font-size: 0.7rem;
  font-weight: 700;
  text-transform: uppercase;
  color: var(--risk-medium);
  margin-bottom: 0.75rem;
  padding-bottom: 0.5rem;
  border-bottom: 1px solid var(--sidebar-border);
}

.multi-desc {
  font-size: 0.75rem;
  color: var(--text-secondary);
  line-height: 1.4;
  margin-bottom: 0.75rem;
}

.multi-list {
  list-style: none;
  padding: 0.75rem 1rem 1rem;
  margin: 0;
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
  gap: 0.6rem;
}

.multi-item {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  padding: 0.25rem 0.6rem;
  background: rgba(255,255,255,0.04);
  border: 1px solid rgba(255,255,255,0.06);
  border-radius: 4px;
  font-size: 0.72rem;
  color: var(--text-secondary);
}

.multi-cnpj-link {
  font-family: monospace;
  font-weight: 600;
  letter-spacing: 0.05em;
  color: var(--primary-color);
  text-decoration: none;
  cursor: pointer;
  transition: all 0.2s;
  display: flex;
  align-items: center;
}

.multi-cnpj-link:hover {
  filter: brightness(1.2);
  text-decoration: underline;
}

/* ── MAPA DE TRILHAS NO POPOVER ─────────────────────── */
.multi-cpf-meta {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.3rem;
  font-size: 0.72rem;
  margin-bottom: 0.5rem;
  padding: 0.4rem 0.6rem;
  background: rgba(255,255,255,0.04);
  border-radius: 6px;
  border: 1px solid rgba(255,255,255,0.06);
}

.multi-cpf-label { color: rgba(255,255,255,0.4); font-weight: 700; text-transform: uppercase; font-size: 0.63rem; }
.multi-cpf-val   { font-family: monospace; font-weight: 700; color: rgba(255,255,255,0.9); letter-spacing: 0.05em; }
.multi-cpf-sep   { color: rgba(255,255,255,0.25); }
.multi-cpf-name  { font-weight: 600; color: rgba(255,255,255,0.75); }
.multi-cpf-obito { font-size: 0.68rem; color: rgba(255,165,0,0.8); font-weight: 600; }

.multi-legend {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  font-size: 0.68rem;
  color: rgba(255,255,255,0.5);
  margin-bottom: 0.4rem;
}

.legend-dot {
  display: inline-block;
  width: 10px;
  height: 10px;
  border-radius: 50%;
  flex-shrink: 0;
}

.timeline-chart-wrap {
  width: 100%;
  height: 400px;
  background: rgba(0,0,0,0.15);
  border-radius: 8px;
  margin: 0.25rem 0 0.5rem;
  padding: 0.25rem;
  border: 1px solid rgba(255,255,255,0.05);
  position: relative;
}

.timeline-loading,
.timeline-empty {
  position: absolute;
  inset: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 0.5rem;
  font-size: 0.75rem;
  color: rgba(255,255,255,0.4);
}

.timeline-loading i,
.timeline-empty i {
  font-size: 1.2rem;
  color: rgba(255,255,255,0.3);
}

.multi-cnpj-list-section {
  margin-top: 0.5rem;
  background: rgba(255,255,255,0.03);
  border: 1px solid rgba(255,255,255,0.07);
  border-radius: 8px;
  overflow: hidden;
  margin-bottom: 0.5rem;
}

.multi-cnpj-list-title {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  padding: 0.4rem 0.75rem;
  font-size: 0.66rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: rgba(255,165,0,0.8);
  border-bottom: 1px solid rgba(255,255,255,0.06);
  background: rgba(255,165,0,0.06);
}

.multi-idx {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 18px;
  height: 18px;
  border-radius: 50%;
  background: rgba(245,158,11,0.2);
  color: #f59e0b;
  font-size: 0.65rem;
  font-weight: 800;
  flex-shrink: 0;
}

.timeline-footer {
  margin-top: 0.25rem;
  padding: 0.6rem 0.75rem;
  background: rgba(255,165,0,0.06);
  border: 1px solid rgba(255,165,0,0.15);
  border-radius: 8px;
  display: flex;
  gap: 0.5rem;
  align-items: flex-start;
}

.timeline-footer i {
  color: orange;
  font-size: 0.8rem;
  margin-top: 0.1rem;
}

.timeline-footer span {
  font-size: 0.68rem;
  color: var(--text-secondary);
  line-height: 1.4;
  font-weight: 500;
}

.f-date, .f-aut, .f-num, .f-val { font-size: 0.78rem; }
.f-num, .f-val { font-weight: 500; }

.txt-center { text-align: center !important; }

.f-days-badge {
  display: inline-block;
  padding: 0.15rem 0.6rem;
  border-radius: 99px;
  font-size: 0.7rem;
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
  background: color-mix(in srgb, var(--primary-color) 10%, var(--card-bg));
  border-top: 2px solid color-mix(in srgb, var(--primary-color) 40%, transparent);
  border-bottom: 1px solid color-mix(in srgb, var(--primary-color) 25%, transparent);
  padding: 0.55rem 1rem;
  font-size: 0.78rem;
}

.f-group-cpf {
  font-family: monospace;
  font-weight: 700;
  color: var(--text-secondary);
  margin-right: 0.6rem;
}

.f-group-nome {
  font-weight: 800;
  font-size: 0.82rem;
  color: var(--text-secondary);
  text-transform: uppercase;
  letter-spacing: 0.03em;
  margin-right: 0.4rem;
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
}

/* ── Linha de subtotal por falecido ── */
.f-subtotal-row td {
  background: color-mix(in srgb, var(--sidebar-border) 30%, var(--card-bg));
  border-top: 1px solid var(--sidebar-border);
  border-bottom: 2px solid var(--sidebar-border);
  padding: 0.4rem 1rem;
}

.f-subtotal-label {
  font-size: 0.72rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: var(--text-secondary);
  text-align: right;
}

.f-subtotal-val {
  font-weight: 800 !important;
  color: var(--text-secondary) !important;
}

/* ── Total geral (tfoot) ── */
.f-grand-total td {
  background: color-mix(in srgb, var(--primary-color) 8%, var(--card-bg));
  border-top: 2px solid color-mix(in srgb, var(--primary-color) 30%, transparent);
  padding: 0.65rem 1rem;
  font-size: 0.78rem;
  font-weight: 800;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: var(--text-secondary);
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
  background: rgba(255,255,255,0.03);
  border: 1px solid rgba(255,255,255,0.08);
  border-radius: 10px;
  padding: 0.75rem 1rem;
  transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
  cursor: pointer;
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
  color: var(--text-primary);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  width: 100%;
}

.r-meta {
  font-size: 0.65rem;
  color: var(--text-muted);
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
  font-weight: 800;
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
  background: rgba(255,255,255,0.05);
  border-radius: 2px;
  overflow: hidden;
}

.r-progress-fill {
  height: 100%;
  background: linear-gradient(90deg, var(--primary-color), color-mix(in srgb, var(--primary-color) 70%, white));
  border-radius: 2px;
}

.r-pct {
  font-size: 0.65rem;
  color: var(--text-muted);
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
