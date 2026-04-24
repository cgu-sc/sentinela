<script setup>
import { computed, ref, defineExpose } from 'vue';
import { useMultiCnpjTimeline } from '@/composables/useMultiCnpjTimeline';
import { useFormatting } from '@/composables/useFormatting';
import { useThemeStore } from '@/stores/theme';
import VChart from 'vue-echarts';
import { use } from 'echarts/core';
import { ScatterChart } from 'echarts/charts';
import { GridComponent, TooltipComponent, DataZoomComponent } from 'echarts/components';
import { CanvasRenderer } from 'echarts/renderers';
import OverlayPanel from 'primevue/overlaypanel';

use([ScatterChart, GridComponent, TooltipComponent, DataZoomComponent, CanvasRenderer]);

const props = defineProps({
  currentCnpj: {
    type: String,
    required: true
  }
});

const { timelineData, timelineLoading, fetchTimeline } = useMultiCnpjTimeline();
const { formatCurrencyFull } = useFormatting();
const themeStore = useThemeStore();

const opMultiCnpj = ref(null);
const selectedMultiCpf = ref(null);

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

const formatCnpj = (v) => {
  if (!v) return '—';
  const clean = v.replace(/\D/g, '');
  if (clean.length !== 14) return v;
  return clean.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/, '$1.$2.$3/$4-$5');
};

const timelineChartOption = computed(() => {
  if (!timelineData.value || !timelineData.value.events?.length) return null;

  const td = timelineData.value;
  const cnpjsOrdenados = [props.currentCnpj];
  td.cnpjs_envolvidos.forEach(c => { if (c !== props.currentCnpj) cnpjsOrdenados.push(c); });

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

  const isDark = themeStore.isDark;
  const textColor = themeStore.tokens.textColor;
  const mutedColor = themeStore.tokens.mutedColor;
  const axisLineColor = isDark ? 'rgba(255,255,255,0.12)' : 'rgba(0,0,0,0.1)';
  const splitLineColor = isDark ? 'rgba(255,255,255,0.05)' : 'rgba(0,0,0,0.06)';
  const tooltipBg = isDark ? 'rgba(15,23,42,0.95)' : 'rgba(255,255,255,0.97)';
  const tooltipBorder = isDark ? 'rgba(255,255,255,0.15)' : 'rgba(0,0,0,0.12)';
  const tooltipText = isDark ? '#fff' : '#1e293b';

  return {
    backgroundColor: 'transparent',
    grid: { top: 16, left: 230, right: 30, bottom: 40, containLabel: false },
    tooltip: {
      trigger: 'item',
      backgroundColor: tooltipBg,
      borderColor: tooltipBorder,
      textStyle: { color: tooltipText, fontSize: 11 },
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
      axisLine: { lineStyle: { color: axisLineColor } },
      splitLine: { show: true, lineStyle: { color: splitLineColor, type: 'dashed' } },
      axisLabel: {
        color: mutedColor,
        fontSize: 9,
        formatter: (v) => new Date(v).getFullYear().toString()
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
        color: textColor + 'cc',
        fontSize: 12,
        fontWeight: 600,
        width: 180,
        overflow: 'truncate'
      },
      splitLine: { show: true, lineStyle: { color: splitLineColor } }
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
  if (timelineData.value?.events?.length) {
    const seen = new Map();
    for (const e of timelineData.value.events) {
      if (e.cnpj !== props.currentCnpj && !seen.has(e.cnpj)) {
        seen.set(e.cnpj, {
          cnpj: e.cnpj,
          razao_social: e.razao_social ?? null,
          municipio: e.municipio ?? null,
          uf: e.uf ?? null,
        });
      }
    }
    return [...seen.values()];
  }
  if (!selectedMultiCpf.value) return [];
  return parseCnpjs(selectedMultiCpf.value.outros_cnpj).map(c => ({ cnpj: c, razao_social: null, municipio: null, uf: null }));
});

// Método exposto para abrir o overlay
const open = (event, grupo) => {
  selectedMultiCpf.value = grupo;
  opMultiCnpj.value.toggle(event);
  if (grupo?.cpf && props.currentCnpj) {
    fetchTimeline(grupo.cpf, props.currentCnpj);
  }
};

defineExpose({ open });
</script>

<template>
  <OverlayPanel ref="opMultiCnpj" class="multi-cnpj-panel" style="width: 900px">
    <div v-if="selectedMultiCpf" class="multi-cnpj-content">
      <header class="multi-header">
        <i class="pi pi-share-alt" />
        <span>Mapa de Relacionamento Temporal</span>
        <i v-if="timelineLoading" class="pi pi-spin pi-spinner" style="margin-left:auto;font-size:0.8rem;opacity:0.6;" />
        <button class="multi-close-btn" @click="opMultiCnpj.hide()" v-tooltip.left="'Fechar'">
          <i class="pi pi-times" />
        </button>
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
          <li v-for="(item, i) in outrosCnpjList" :key="item.cnpj" class="multi-item">
            <span class="multi-idx">#{{ i + 1 }}</span>
            <div class="multi-item-body">
              <a :href="`/estabelecimento/${item.cnpj}`" target="_blank" class="multi-cnpj-link">
                {{ formatCnpj(item.cnpj) }}
                <i class="pi pi-external-link" style="font-size: 0.6rem; margin-left: 0.3rem; opacity: 0.5;" />
              </a>
              <span v-if="item.razao_social" class="multi-razao">{{ item.razao_social }}</span>
              <span v-if="item.municipio || item.uf" class="multi-localizacao">
                <i class="pi pi-map-marker" />
                {{ [item.municipio, item.uf].filter(Boolean).join('/') }}
              </span>
            </div>
          </li>
        </ul>
      </div>
    </div>
  </OverlayPanel>
</template>

<style scoped>
/* ── MULTI-CNPJ OVERLAY ────────────────────────────── */
.multi-cnpj-content {
  padding: 0.5rem 0.25rem;
}

.multi-header {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  font-size: 0.82rem;
  font-weight: 700;
  text-transform: uppercase;
  color: var(--risk-medium);
  margin-bottom: 0.75rem;
  padding-bottom: 0.5rem;
  border-bottom: 1px solid var(--sidebar-border);
}

.multi-close-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 26px;
  height: 26px;
  margin-left: auto;
  border-radius: 6px;
  border: 1px solid var(--card-border);
  background: transparent;
  color: var(--text-muted);
  cursor: pointer;
  transition: all 0.2s ease;
  font-size: 0.75rem;
}

.multi-close-btn:hover {
  background: color-mix(in srgb, var(--text-muted) 12%, transparent);
  color: var(--text-color);
}

.multi-desc {
  font-size: 0.85rem;
  color: var(--text-secondary);
  line-height: 1.4;
  margin-bottom: 0.75rem;
}

.multi-list {
  list-style: none;
  padding: 0.75rem 1rem 1rem;
  margin: 0;
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
  gap: 0.5rem;
}

.multi-item {
  display: flex;
  align-items: flex-start;
  gap: 0.5rem;
  padding: 0.4rem 0.6rem;
  background: color-mix(in srgb, var(--text-color) 4%, transparent);
  border: 1px solid var(--card-border);
  border-radius: 6px;
  font-size: 0.82rem;
  color: var(--text-secondary);
}

.multi-item-body {
  display: flex;
  flex-direction: column;
  gap: 0.15rem;
  min-width: 0;
}

.multi-razao {
  font-size: 0.78rem;
  color: var(--text-color);
  opacity: 0.75;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.multi-localizacao {
  display: flex;
  align-items: center;
  gap: 0.25rem;
  font-size: 0.72rem;
  color: var(--text-muted);
}

.multi-localizacao .pi {
  font-size: 0.65rem;
  opacity: 0.7;
}

.multi-cnpj-link {
  font-weight: 600;
  letter-spacing: normal;
  color: var(--text-color);
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

.multi-cpf-meta {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.3rem;
  font-size: 0.85rem;
  margin-bottom: 0.5rem;
  padding: 0.4rem 0.6rem;
  background: color-mix(in srgb, var(--text-color) 4%, transparent);
  border-radius: 6px;
  border: 1px solid var(--card-border);
}

.multi-cpf-label { color: var(--text-muted); font-weight: 700; text-transform: uppercase; font-size: 0.72rem; }
.multi-cpf-val   { font-weight: 700; color: var(--text-color); }
.multi-cpf-sep   { color: var(--text-muted); opacity: 0.5; }
.multi-cpf-name  { font-weight: 600; color: var(--text-color); opacity: 0.8; }
.multi-cpf-obito { font-size: 0.82rem; color: var(--risk-high); font-weight: 600; }

.multi-legend {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  font-size: 0.82rem;
  color: var(--text-muted);
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
  background: transparent;
  border-radius: 8px;
  margin: 0.25rem 0 0.5rem;
  padding: 0.25rem;
  border: 1px solid var(--card-border);
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
  color: var(--text-muted);
}

.timeline-loading i,
.timeline-empty i {
  font-size: 1.2rem;
  color: var(--text-muted);
  opacity: 0.6;
}

.multi-cnpj-list-section {
  margin-top: 0.5rem;
  background: color-mix(in srgb, var(--text-color) 2%, transparent);
  border: 1px solid var(--card-border);
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
  color: var(--text-muted);
  border-bottom: 1px solid var(--card-border);
  background: var(--tabs-bg);
}

.multi-cnpj-list-title i {
  color: var(--primary-color);
  font-size: 1.1rem;
}

.multi-idx {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 28px;
  height: 28px;
  border-radius: 6px;
  background: color-mix(in srgb, var(--text-color) 6%, transparent);
  color: var(--text-muted);
  font-size: 0.7rem;
  font-weight: 800;
  flex-shrink: 0;
}
</style>
