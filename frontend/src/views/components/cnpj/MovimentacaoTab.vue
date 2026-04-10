<script setup>
import { computed, ref, watch } from 'vue';
import { useCnpjDetailStore } from '@/stores/cnpjDetail';
import { useFormatting } from '@/composables/useFormatting';

const props = defineProps({
  cnpj: { type: String, required: true }
});

const cnpjDetailStore = useCnpjDetailStore();
const { formatCurrencyFull: _fmt } = useFormatting();

// Wrapper null-safe
const fmt = (val) => (val === null || val === undefined) ? '—' : _fmt(val);
const fmtPct = (val) => (val === null || val === undefined) ? '—' : val.toFixed(2) + '%';

const loading = computed(() => cnpjDetailStore.movimentacaoLoading);
const loaded  = computed(() => cnpjDetailStore.movimentacaoLoaded);
const error   = computed(() => cnpjDetailStore.movimentacaoError);
const data    = computed(() => cnpjDetailStore.movimentacaoData);
const rows    = computed(() => data.value?.rows ?? []);
const summary = computed(() => data.value?.summary ?? null);

// ── Agrupa linhas em seções por GTIN ─────────────────────────────────────────
const sections = computed(() => {
  const result = [];
  let cur = null;

  for (const row of rows.value) {
    if (row.tipo_linha === 'header_medicamento') {
      if (cur) result.push(cur);
      cur = { gtin: row.gtin, medicamento: '', rows: [], subtotal: null };
    } else if (row.tipo_linha === 'resumo_parcial' && cur) {
      cur.subtotal = row;
      // Resumo parcial também contém o nome limpo caso não tenha havido vendas no período exibido (raro)
      if (!cur.medicamento) cur.medicamento = row.medicamento;
    } else if (cur && (row.tipo_linha === 'venda_normal' || row.tipo_linha === 'venda_irregular')) {
      // Captura o nome limpo diretamente da linha de venda
      if (!cur.medicamento) cur.medicamento = row.medicamento;
      cur.rows.push(row);
    } else if (cur && row.tipo_linha !== 'header_colunas') {
      cur.rows.push(row);
    }
  }
  if (cur) result.push(cur);
  return result;
});

// ── Estado de expansão ────────────────────────────────────────────────────────
const _expanded = ref(new Set());
const expanded = computed({
  get: () => _expanded.value,
  set: (v) => { _expanded.value = v; }
});

// Quando os dados carregam, abre automaticamente os GTINs irregulares
watch(sections, (newSections) => {
  const irregulares = new Set(
    newSections.filter(s => hasIrregular(s)).map(s => s.gtin)
  );
  _expanded.value = irregulares;
}, { immediate: true });

function toggle(gtin) {
  const next = new Set(_expanded.value);
  next.has(gtin) ? next.delete(gtin) : next.add(gtin);
  _expanded.value = next;
}
function expandAll()   { _expanded.value = new Set(sections.value.map(s => s.gtin)); }
function collapseAll() { _expanded.value = new Set(); }

const processarMovimentacao = () => { cnpjDetailStore.fetchMovimentacao(props.cnpj); };

const copyToClipboard = (text) => {
  if (!text) return;
  navigator.clipboard.writeText(text);
  // Feedback visual simples ou via store se houvesse Toast global acessível aqui
};


// ── Filtro: exibir apenas linhas irregulares ─────────────────────────────────
const showOnlyIrregular = ref(true);

const hasIrregular = (section) =>
  (section.subtotal?.vendas_irregular ?? 0) > 0 ||
  section.rows.some(r => r.tipo_linha === 'venda_irregular');

const filteredRows = (sectionRows) => {
  if (!showOnlyIrregular.value) return sectionRows;
  return sectionRows.filter(r => r.tipo_linha === 'venda_irregular');
};

const visibleSections = computed(() => {
  if (!showOnlyIrregular.value) return sections.value;
  return sections.value.filter(s => hasIrregular(s));
});

const pctIrregular = (section) => {
  const st = section.subtotal;
  if (!st || !st.valor) return 0;
  return ((st.valor_irregular ?? 0) / st.valor * 100);
};

// ── Novos KPIs Sugeridos ───────────────────────────────────────────────────
const kpiTopSubstance = computed(() => {
  if (!sections.value.length) return null;
  
  const groups = {};
  sections.value.forEach(s => {
    // Usamos o nome limpo (Substância) para agrupar
    const name = s.medicamento;
    if (!name) return;
    
    if (!groups[name]) {
      groups[name] = { name, valorIrregular: 0, gtinCount: 0 };
    }
    groups[name].valorIrregular += (s.subtotal?.valor_irregular ?? 0);
    groups[name].gtinCount += 1;
  });

  const sorted = Object.values(groups).sort((a, b) => b.valorIrregular - a.valorIrregular);
  const top = sorted[0];
  
  if (!top || top.valorIrregular === 0) return null;
  return top;
});

const totalItensIrregulares = computed(() => {
  return sections.value.reduce((acc, s) => acc + (s.subtotal?.vendas_irregular ?? 0), 0);
});

const totalValorIrregularGeral = computed(() => {
  return sections.value.reduce((acc, s) => acc + (s.subtotal?.valor_irregular ?? 0), 0);
});

const concentrationTop1 = computed(() => {
  const total = totalValorIrregularGeral.value;
  if (!total || !kpiTopSubstance.value) return 0;
  return (kpiTopSubstance.value.valorIrregular / total) * 100;
});

const totalItensGeral = computed(() => {
  return sections.value.reduce((acc, s) => acc + (s.subtotal?.vendas ?? 0), 0);
});

const pctItensIrregulares = computed(() => {
  const total = totalItensGeral.value;
  if (!total) return 0;
  return (totalItensIrregulares.value / total) * 100;
});
</script>

<template>
  <div class="mov-tab">

    <!-- ── ESTADO: Erro ──────────────────────────────────────────────────── -->
    <div v-if="error" class="mov-loading-state tab-placeholder--error">
      <div class="loading-inner">
        <i class="pi pi-exclamation-circle loading-icon" style="color: var(--red-400)" />
        <p class="loading-title">Falha ao carregar</p>
        <p style="font-size: 0.85rem; opacity: 0.7; margin: 0;">{{ error }}</p>
        <div class="mov-workspace-note">
          <i class="pi pi-info-circle" />
          <span>O acesso à Memória de Cálculo requer conexão à rede da CGU via <strong>WorkSpace</strong>.</span>
        </div>
        <button class="retry-btn" @click="processarMovimentacao">
          <i class="pi pi-refresh" />
          Tentar novamente
        </button>
      </div>
    </div>

    <!-- ── ESTADO: Carregando (inclui aguardando início do fetch) ───────────── -->
    <div v-else-if="loading || (!loaded && !error)" class="mov-loading-state">
      <div class="loading-inner">
        <i class="pi pi-spin pi-spinner loading-icon" />
        <p class="loading-title">Processando…</p>
      </div>
    </div>

    <!-- ── ESTADO: Sem dados ───────────────────────────────────────────────── -->
    <div v-else-if="loaded && !rows.length" class="mov-empty-state">
      <i class="pi pi-inbox placeholder-icon" />
      <p>Nenhum dado encontrado.</p>
    </div>

    <!-- ── ESTADO: Dados carregados ───────────────────────────────────────── -->
    <template v-else-if="loaded && rows.length">

      <!-- KPI Strip -->
      <div class="mov-kpi-strip" v-if="summary">
        <div class="mov-kpi" :class="sections.filter(hasIrregular).length > 0 ? 'kpi-danger' : 'kpi-ok'"
             v-tooltip.top="'Total de códigos de barras (GTINs) que apresentaram venda sem comprovação no período.'">
          <span class="kpi-label">GTINs Irregulares</span>
          <span class="kpi-val">{{ sections.filter(hasIrregular).length }} <small>de {{ sections.length }} GTINs</small></span>
        </div>

        <div class="mov-kpi" :class="kpiTopSubstance ? 'kpi-danger' : ''">
          <span class="kpi-label">Principal Foco de Prejuízo</span>
          <span class="kpi-val" v-tooltip.top="kpiTopSubstance ? `Substância que concentra o maior valor financeiro de irregularidades: ${kpiTopSubstance.name}` : ''">
            {{ kpiTopSubstance ? (kpiTopSubstance.name.length > 20 ? kpiTopSubstance.name.slice(0, 18) + '...' : kpiTopSubstance.name) : 'Nenhum' }}
            <small v-if="kpiTopSubstance" style="font-size: 0.75rem; opacity: 0.8; display: block; margin-top: -2px;">
              ({{ kpiTopSubstance.gtinCount }} {{ kpiTopSubstance.gtinCount > 1 ? 'GTINs' : 'GTIN' }} · {{ concentrationTop1.toFixed(1) }}% do prejuízo)
            </small>
          </span>
        </div>

        <div class="mov-kpi" :class="totalItensIrregulares > 0 ? 'kpi-danger' : ''"
             v-tooltip.top="'Quantidade física total (unidades) de medicamentos vendidos sem comprovação fiscal.'">
          <span class="kpi-label">Itens Irregulares (Qtd)</span>
          <span class="kpi-val">{{ totalItensIrregulares.toLocaleString('pt-BR') }} <small>unid.</small></span>
        </div>

        <div class="mov-kpi" :class="pctItensIrregulares > 5 ? 'kpi-warning' : ''"
             v-tooltip.top="'Percentual físico de itens irregulares em relação ao volume total movimentado pela farmácia.'">
          <span class="kpi-label">% Volume Irregular</span>
          <span class="kpi-val">{{ pctItensIrregulares.toFixed(2) }}% <small>do total</small></span>
        </div>

        <div class="mov-kpi" v-tooltip.top="'Volume total de unidades físicas (Regulares + Irregulares) movimentadas no período analisado.'">
          <span class="kpi-label">Total Movimentado</span>
          <span class="kpi-val">{{ totalItensGeral.toLocaleString('pt-BR') }} <small>unid.</small></span>
        </div>
      </div>

      <!-- Toolbar -->
      <div class="mov-toolbar">
        <span class="toolbar-count">
          Exibindo {{ visibleSections.length }} de {{ sections.length }} medicamentos
        </span>
        <div class="toolbar-actions">
          <button class="tb-btn" :class="{ 'tb-btn-active': showOnlyIrregular }" @click="showOnlyIrregular = !showOnlyIrregular">
            <i :class="showOnlyIrregular ? 'pi pi-filter-fill' : 'pi pi-filter'" />
            {{ showOnlyIrregular ? 'Apenas Irregulares' : 'Todas as Linhas' }}
          </button>
          <div class="tb-divider" />
          <button class="tb-btn" @click="expandAll"><i class="pi pi-plus-circle" /> Expandir</button>
          <button class="tb-btn" @click="collapseAll"><i class="pi pi-minus-circle" /> Recolher</button>
        </div>
      </div>

      <div class="mov-body">
        <div v-for="section in visibleSections" :key="section.gtin" class="gtin-accordion" :class="{ 'is-expanded': expanded.has(section.gtin), 'has-irregular': hasIrregular(section) }">

          <button class="gtin-header" @click="toggle(section.gtin)">
            <i class="pi header-chevron" :class="expanded.has(section.gtin) ? 'pi-chevron-down' : 'pi-chevron-right'" />
            <span class="gtin-badge" @click.stop="copyToClipboard(section.gtin)" title="Clique para copiar o GTIN">
              {{ section.gtin }}
              <i class="pi pi-copy gtin-copy-icon" />
            </span>
            <span class="gtin-nome">{{ section.medicamento }}</span>
            <div class="header-kpis" @click.stop>
              <span class="hk-item">
                <span class="hk-label">Sem Comprovação</span>
                <span class="hk-val" :class="(section.subtotal?.valor_irregular ?? 0) > 0 ? 'hk-irreg' : ''">{{ fmt(section.subtotal?.valor_irregular) }}</span>
              </span>
              <span v-if="hasIrregular(section)" class="hk-badge-irreg">{{ fmtPct(pctIrregular(section)) }} irreg.</span>
              <span v-else class="hk-badge-ok">Regular</span>
            </div>
          </button>

          <div class="gtin-content" v-show="expanded.has(section.gtin)">
            <div class="gtin-col-headers">
              <div class="gcol gcol-date">1ª Venda</div>
              <div class="gcol gcol-date">Início Irreg.</div>
              <div class="gcol gcol-date">Última Venda</div>
              <div class="gcol gcol-num">Est. Ini.</div>
              <div class="gcol gcol-num">Est. Fin.</div>
              <div class="gcol gcol-num">Vendas</div>
              <div class="gcol gcol-num">Irreg.</div>
              <div class="gcol gcol-cur">Total</div>
              <div class="gcol gcol-cur gcol-irreg-hdr">Irreg.</div>
              <div class="gcol gcol-nf">Notas Fiscais</div>
            </div>

            <div v-for="(row, ri) in filteredRows(section.rows)" :key="ri" class="gtin-row" :class="{ 'row-irregular': row.tipo_linha === 'venda_irregular', 'row-normal': row.tipo_linha === 'venda_normal' }">
              <div class="gcol gcol-date">{{ row.periodo_inicial ?? '—' }}</div>
              <div class="gcol gcol-date">{{ row.periodo_inicio_irregular ?? '—' }}</div>
              <div class="gcol gcol-date">{{ row.periodo_final ?? '—' }}</div>
              <div class="gcol gcol-num">{{ row.estoque_inicial?.toLocaleString('pt-BR') ?? '—' }}</div>
              <div class="gcol gcol-num">{{ row.estoque_final?.toLocaleString('pt-BR') ?? '—' }}</div>
              <div class="gcol gcol-num">{{ row.vendas?.toLocaleString('pt-BR') ?? '—' }}</div>
              <div class="gcol gcol-num" :class="(row.vendas_irregular ?? 0) > 0 ? 'cell-irreg-num' : ''">{{ row.vendas_irregular?.toLocaleString('pt-BR') ?? '—' }}</div>
              <div class="gcol gcol-cur">{{ fmt(row.valor) }}</div>
              <div class="gcol gcol-cur" :class="(row.valor_irregular ?? 0) > 0 ? 'cell-irreg-cur' : ''">{{ fmt(row.valor_irregular) }}</div>
              <div class="gcol gcol-nf" :title="row.notas"><span class="nf-text">{{ row.notas || '—' }}</span></div>
            </div>

            <div v-if="section.subtotal" class="gtin-subtotal">
              <div class="gcol gcol-date sub-label">Resumo Parcial</div>
              <div class="gcol gcol-date"></div><div class="gcol gcol-date"></div><div class="gcol gcol-num"></div>
              <div class="gcol gcol-num">{{ section.subtotal.estoque_final?.toLocaleString('pt-BR') ?? '—' }}</div>
              <div class="gcol gcol-num">{{ section.subtotal.vendas?.toLocaleString('pt-BR') ?? '—' }}</div>
              <div class="gcol gcol-num" :class="(section.subtotal.vendas_irregular ?? 0) > 0 ? 'cell-irreg-num' : ''">{{ section.subtotal.vendas_irregular?.toLocaleString('pt-BR') ?? '—' }}</div>
              <div class="gcol gcol-cur">{{ fmt(section.subtotal.valor) }}</div>
              <div class="gcol gcol-cur" :class="(section.subtotal.valor_irregular ?? 0) > 0 ? 'cell-irreg-cur' : ''">{{ fmt(section.subtotal.valor_irregular) }}</div>
              <div class="gcol gcol-nf"></div>
            </div>
          </div>
        </div>

        <div class="gtin-grand-total" v-if="summary">
          <span class="grand-label">TOTAL GERAL</span>
          <span class="grand-sep">—</span>
          <span class="grand-item"><span class="grand-sub">Total:</span><span class="grand-val">{{ fmt(summary.valor_total) }}</span></span>
          <span class="grand-sep">|</span>
          <span class="grand-item"><span class="grand-sub">Sem Comprovação:</span><span class="grand-val grand-irreg">{{ fmt(summary.valor_irregular) }}</span></span>
          <span class="grand-sep">|</span>
          <span class="grand-item"><span class="grand-sub">%:</span><span class="grand-val" :class="summary.pct_irregular > 5 ? 'grand-irreg' : ''">{{ fmtPct(summary.pct_irregular) }}</span></span>
        </div>
      </div>
    </template>
  </div>
</template>

<style scoped>
.mov-tab { padding: 0; display: flex; flex-direction: column; gap: 1.5rem; min-height: 300px; }
.mov-workspace-note {
  display: flex;
  align-items: flex-start;
  gap: 0.5rem;
  padding: 0.6rem 1rem;
  background: color-mix(in srgb, var(--primary-color) 6%, var(--card-bg));
  border: 1px solid color-mix(in srgb, var(--primary-color) 20%, transparent);
  border-radius: 8px;
  font-size: 0.78rem;
  color: var(--text-color);
  opacity: 0.85;
  text-align: left;
  line-height: 1.5;
  max-width: 360px;
}
.mov-workspace-note i {
  color: var(--primary-color);
  margin-top: 0.15rem;
  flex-shrink: 0;
}
.retry-btn {
  display: inline-flex;
  align-items: center;
  gap: 0.5rem;
  margin-top: 0.5rem;
  padding: 0.55rem 1.5rem;
  font-size: 0.82rem;
  font-weight: 700;
  font-family: inherit;
  letter-spacing: 0.04em;
  border-radius: 8px;
  cursor: pointer;
  color: var(--primary-color);
  background: color-mix(in srgb, var(--primary-color) 12%, transparent);
  border: 1px solid color-mix(in srgb, var(--primary-color) 35%, transparent);
  backdrop-filter: blur(8px);
  -webkit-backdrop-filter: blur(8px);
  transition: background 0.2s, border-color 0.2s, box-shadow 0.2s;
}
.retry-btn:hover {
  background: color-mix(in srgb, var(--primary-color) 20%, transparent);
  border-color: color-mix(in srgb, var(--primary-color) 55%, transparent);
  box-shadow: 0 0 12px color-mix(in srgb, var(--primary-color) 20%, transparent);
}
.mov-loading-state { flex: 1; display: flex; align-items: center; justify-content: center; padding: 4rem 2rem; }
.loading-inner { display: flex; flex-direction: column; align-items: center; gap: 1rem; max-width: 400px; text-align: center; }
.loading-icon { font-size: 2.5rem; color: var(--primary-color); opacity: 0.8; }
.loading-title { font-size: 1rem; font-weight: 600; color: var(--text-primary); margin: 0; }
.mov-empty-state { flex: 1; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 1rem; color: var(--text-muted); opacity: 0.5; padding: 3rem; }
.placeholder-icon { font-size: 3rem; }
.mov-empty-state p { font-size: 0.875rem; margin: 0; }
.mov-kpi-strip {
  display: grid;
  grid-template-columns: repeat(5, 1fr);
  gap: 1rem;
  padding: 0;
}
.mov-kpi {
  flex: 1;
  min-width: 110px;
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  border-left: 4px solid var(--card-border);
  border-radius: 12px;
  padding: 0.8rem 1rem;
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
  transition: all 0.2s ease;
  cursor: pointer;
}
.mov-kpi:hover {
  transform: translateY(-2px);
  box-shadow: 0 4px 15px rgba(0, 0, 0, 0.08);
}
.mov-kpi.kpi-danger {
  border: 1px solid color-mix(in srgb, var(--risk-high) 15%, var(--card-border));
  border-left: 3px solid var(--risk-high) !important;
  box-shadow: 0 8px 18px -10px color-mix(in srgb, var(--risk-high) 30%, transparent);
}
.mov-kpi.kpi-warning {
  border: 1px solid color-mix(in srgb, var(--risk-medium) 15%, var(--card-border));
  border-left: 3px solid var(--risk-medium) !important;
  box-shadow: 0 8px 18px -10px color-mix(in srgb, var(--risk-medium) 30%, transparent);
}
.mov-kpi.kpi-ok {
  border: 1px solid color-mix(in srgb, #22c55e 15%, var(--card-border));
  border-left: 3px solid #22c55e !important;
  box-shadow: 0 8px 18px -10px color-mix(in srgb, #22c55e 30%, transparent);
}
.kpi-label {
  font-size: 0.7rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--text-secondary);
  opacity: 0.85;
}
.kpi-val {
  font-size: 1rem;
  font-weight: 600;
  color: var(--text-primary);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.mov-toolbar { display: flex; align-items: center; justify-content: space-between; padding: 0; }
.toolbar-count { font-size: 0.72rem; color: var(--text-muted); }
.toolbar-actions { display: flex; gap: 0.5rem; }
.tb-btn { 
  display: flex; 
  align-items: center; 
  gap: 0.4rem; 
  padding: 0.4rem 0.9rem; 
  border-radius: 8px; 
  border: 1px solid var(--card-border); 
  background: var(--card-bg); 
  color: var(--text-secondary); 
  font-size: 0.75rem; 
  font-weight: 600;
  cursor: pointer; 
  transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1); 
  white-space: nowrap; 
}
.tb-btn:hover { 
  background: color-mix(in srgb, var(--text-color) 4%, var(--card-bg)); 
  border-color: var(--card-border-hover);
}
.tb-btn-active { 
  background: color-mix(in srgb, var(--risk-high) 12%, var(--card-bg)) !important; 
  color: var(--risk-high) !important; 
  border-color: color-mix(in srgb, var(--risk-high) 40%, transparent) !important; 
  box-shadow: 0 0 12px -2px color-mix(in srgb, var(--risk-high) 25%, transparent);
}
.tb-btn:active {
  transform: scale(0.96);
}
.tb-divider { width: 1px; height: 18px; background: var(--card-border); align-self: center; margin: 0 0.1rem; }
.mov-body { padding: 0 0 1.5rem; display: flex; flex-direction: column; gap: 0.5rem; }
.gtin-accordion { border: 1px solid var(--card-border); border-radius: 12px; overflow: hidden; background: var(--card-bg); transition: border-color 0.2s, box-shadow 0.2s; }
.gtin-accordion.has-irregular { border-left: 3px solid color-mix(in srgb, var(--risk-high) 60%, transparent); }
.gtin-header { width: 100%; display: flex; align-items: center; gap: 0.65rem; padding: 0.6rem 0.9rem; background: none; border: none; cursor: pointer; text-align: left; color: inherit; transition: background 0.15s; min-height: 46px; }
.gtin-header:hover { background: color-mix(in srgb, var(--text-color) 2%, var(--card-bg)); }
.is-expanded .gtin-header { background: var(--card-bg); border-bottom: 1px solid var(--card-border); }
.header-chevron { font-size: 0.7rem; color: var(--text-muted); flex-shrink: 0; transition: transform 0.2s; }
.gtin-badge { 
  display: inline-flex; 
  align-items: center; 
  padding: 0.2rem 0.6rem; 
  border-radius: 4px; 
  background: transparent; 
  color: var(--text-muted); 
  border: 1px solid var(--card-border);
  font-size: 0.82rem; 
  font-weight: 700; 
  letter-spacing: 0.08em; 
  white-space: nowrap; 
  flex-shrink: 0; 
  opacity: 0.85;
  cursor: copy;
  transition: all 0.2s;
}
.gtin-badge:hover {
  background: color-mix(in srgb, var(--primary-color) 6%, transparent);
  border-color: var(--primary-color);
  color: var(--primary-color);
  opacity: 1;
}
.gtin-copy-icon {
  font-size: 0.65rem;
  margin-left: 0.5rem;
  opacity: 0.5;
}
.gtin-nome { font-size: 0.76rem; font-weight: 600; color: var(--text-primary); flex: 1; text-overflow: ellipsis; overflow: hidden; white-space: nowrap; }
.header-kpis { display: flex; align-items: center; gap: 0.5rem; margin-left: auto; flex-shrink: 0; }
.hk-item { display: flex; flex-direction: column; align-items: flex-end; }
.hk-label { font-size: 0.57rem; color: var(--text-muted); text-transform: uppercase; letter-spacing: 0.04em; line-height: 1; }
.hk-val { font-size: 0.75rem; font-weight: 600; color: var(--text-primary); white-space: nowrap; }
.hk-irreg { color: var(--risk-high) !important; }
.hk-badge-irreg { padding: 0.15rem 0.55rem; border-radius: 20px; font-size: 0.65rem; font-weight: 700; background: color-mix(in srgb, var(--risk-high) 12%, transparent); color: var(--risk-high); border: 1px solid color-mix(in srgb, var(--risk-high) 25%, transparent); }
.hk-badge-ok { padding: 0.15rem 0.55rem; border-radius: 20px; font-size: 0.65rem; font-weight: 700; background: color-mix(in srgb, #22c55e 10%, transparent); color: #16a34a; border: 1px solid color-mix(in srgb, #22c55e 25%, transparent); }
.gtin-content { overflow-x: auto; }
.gtin-col-headers, .gtin-row, .gtin-subtotal { display: grid; grid-template-columns: 1.2fr 1.2fr 1.2fr 1fr 1fr 0.8fr 0.8fr 1.4fr 1.4fr 4fr; min-width: 700px; align-items: center; }
.gtin-col-headers { background: var(--card-bg); border-bottom: 1px solid var(--card-border); }
.gcol { padding: 0.38rem 0.55rem; font-size: 0.71rem; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; border-right: 1px solid color-mix(in srgb, var(--card-border) 45%, transparent); }
.gtin-col-headers .gcol { font-weight: 700; text-transform: uppercase; letter-spacing: 0.04em; font-size: 0.6rem; color: var(--text-secondary); opacity: 0.8; }
.gcol-num, .gcol-cur { text-align: right; font-variant-numeric: tabular-nums; }
.gcol-irreg-hdr { color: var(--risk-high) !important; }
.gtin-row { border-bottom: 1px solid color-mix(in srgb, var(--card-border) 50%, transparent); transition: background 0.12s; }
.row-normal:hover { background: color-mix(in srgb, var(--text-color) 3%, var(--card-bg)); }
.row-irregular { background: color-mix(in srgb, var(--risk-high) 4%, var(--card-bg)); }
.cell-irreg-date, .cell-irreg-num, .cell-irreg-cur { color: var(--risk-high) !important; font-weight: 600; }
.nf-text { font-size: 0.67rem; color: var(--text-muted); display: block; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; max-width: 100%; }
.gtin-subtotal { background: color-mix(in srgb, var(--primary-color) 4%, var(--card-bg)); border-top: 2px solid var(--card-border); }
.gtin-subtotal .gcol { font-size: 0.73rem; font-weight: 600; color: var(--text-secondary); padding: 0.45rem 0.55rem; }
.sub-label { font-style: italic; opacity: 0.7; font-size: 0.65rem !important; }
.gtin-grand-total { 
  display: flex; 
  align-items: center; 
  flex-wrap: wrap; 
  gap: 0.6rem; 
  padding: 0.85rem 1.2rem; 
  background: color-mix(in srgb, var(--primary-color) 4%, var(--card-bg)); 
  border: 1px solid var(--card-border); 
  border-radius: 12px; 
  font-size: 0.78rem; 
}
.grand-label { font-weight: 800; font-size: 0.7rem; text-transform: uppercase; letter-spacing: 0.06em; color: var(--primary-color); }
.grand-sep { color: var(--text-muted); opacity: 0.4; }
.grand-item { display: flex; align-items: center; gap: 0.35rem; }
.grand-sub { font-size: 0.66rem; color: var(--text-muted); text-transform: uppercase; letter-spacing: 0.03em; }
.grand-val { font-weight: 700; color: var(--text-primary); }
.grand-irreg { color: var(--risk-critical) !important; font-weight: 800; }
</style>
