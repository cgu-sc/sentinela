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
};

// ── Expansão local de linhas (Exibir mais) ───────────────────────────────────
const _rowsExpanded = ref(new Set());
const isRowsExpanded = (gtin) => _rowsExpanded.value.has(gtin);
const toggleRowsExpanded = (gtin) => {
  const next = new Set(_rowsExpanded.value);
  next.has(gtin) ? next.delete(gtin) : next.add(gtin);
  _rowsExpanded.value = next;
};


// ── Filtro: exibir apenas linhas irregulares ─────────────────────────────────
const showOnlyIrregular = ref(true);

const hasIrregular = (section) =>
  (section.subtotal?.vendas_irregular ?? 0) > 0 ||
  section.rows.some(r => r.tipo_linha === 'venda_irregular');

const filteredRows = (sectionRows) => {
  // Agora não filtramos as linhas individualmente. 
  // O filtro "Apenas Irregulares" agora atua no nível do GRUPO (GTIN).
  return sectionRows;
};

const visibleSections = computed(() => {
  if (!showOnlyIrregular.value) return sections.value;
  // Filtra apenas os grupos que possuem ao menos uma irregularidade
  return sections.value.filter(s => hasIrregular(s));
});

const getVisibleRows = (section) => {
  const fRows = filteredRows(section.rows);
  if (isRowsExpanded(section.gtin)) return fRows;
  return fRows.slice(0, 2);
};

// ── Ranking de Substâncias Irregulares (Top Focos) ───────────────────────
const showMoreRanking = ref(false);
const rankingData = computed(() => {
  const groups = {};
  
  sections.value.forEach(s => {
    const st = s.subtotal;
    if (!st || (st.valor_irregular ?? 0) <= 0) return;
    
    // Heurística de limpeza: pegar o nome até o primeiro número (dosagem)
    // Se houver um campo substancia no futuro, trocar aqui.
    const rawName = s.medicamento || 'SUBSTÂNCIA NÃO IDENTIFICADA';
    const cleanName = rawName.split(/\s\d/)[0].trim(); 
    
    if (!groups[cleanName]) {
      groups[cleanName] = {
        substancia: cleanName,
        prejuizo: 0,
        qtd_total: 0,
        qtd_irreg: 0,
        gtins: new Set(),
        firstGtin: s.gtin, // Para o link de scroll (primeiro da lista)
        minStart: null,
        maxEnd: null,
        tickets: []
      };
    }
    
    const g = groups[cleanName];
    g.prejuizo += st.valor_irregular;
    g.qtd_total += st.vendas;
    g.qtd_irreg += st.vendas_irregular;
    g.gtins.add(s.gtin);
    g.tickets.push(st.valor_irregular / (st.vendas_irregular || 1));
    
    const irrRows = s.rows.filter(r => r.tipo_linha === 'venda_irregular');
    if (irrRows.length) {
      const start = irrRows[0].periodo_inicio_irregular;
      const end   = irrRows[irrRows.length - 1].periodo_final;
      if (!g.minStart || start < g.minStart) g.minStart = start;
      if (!g.maxEnd || end > g.maxEnd) g.maxEnd = end;
    }
  });

  return Object.values(groups)
    .map(g => ({
      ...g,
      periodo: `${g.minStart || '—'} a ${g.maxEnd || '—'}`,
      gtinCount: g.gtins.size,
      ticket: g.tickets.reduce((a, b) => a + b, 0) / g.tickets.length,
      peso: (g.prejuizo / (summary.value?.valor_irregular || 1)) * 100
    }))
    .sort((a, b) => b.prejuizo - a.prejuizo);
});

const visibleRanking = computed(() => {
  if (showMoreRanking.value) return rankingData.value;
  return rankingData.value.slice(0, 5);
});

const scrollToGtin = (gtin) => {
  toggleRowsExpanded(gtin); // Garante que as linhas do gtin estão expandidas se houver muitas
  const next = new Set(_expanded.value);
  next.add(gtin);
  _expanded.value = next;
  
  setTimeout(() => {
    const el = document.getElementById(`gtin-${gtin}`);
    if (el) el.scrollIntoView({ behavior: 'smooth', block: 'center' });
  }, 100);
};

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
      
      <!-- Ranking de Maior Impacto -->
      <div class="mov-ranking-card" v-if="rankingData.length">
        <div class="ranking-header">
          <span class="rh-title">💊 Ranking de Substâncias (Foco de Prejuízo)</span>
          <span class="rh-sub" v-if="rankingData.length > 5 && !showMoreRanking">Exibindo Top 5 de {{ rankingData.length }} substâncias críticas</span>
        </div>
        
        <div class="ranking-table-wrapper">
          <table class="ranking-table">
            <colgroup>
              <col style="width: 35%;">
              <col style="width: 18%;">
              <col style="width: 12%;">
              <col style="width: 12%;">
              <col style="width: 9%;">
              <col style="width: 9%;">
              <col style="width: 5%;">
            </colgroup>
            <thead>
              <tr>
                  <th>Princípio Ativo</th>
                  <th>Período de Irregularidade</th>
                  <th class="text-right">Vendas (Tot/Irr)</th>
                  <th class="text-right">Prejuízo (R$)</th>
                  <th class="text-right">Ticket Médio</th>
                  <th class="text-right">Peso %</th>
                  <th class="text-center">Detalhes</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="item in visibleRanking" :key="item.substancia">
                <td>
                  <div class="rank-med-cell">
                    <span class="rank-nome">{{ item.substancia }}</span>
                    <span class="rank-gtin">{{ item.gtinCount }} apresentações (GTINs)</span>
                  </div>
                </td>
                <td class="rank-periodo">{{ item.periodo }}</td>
                <td class="text-right">
                  <span class="r-val-tot">{{ item.qtd_total }}</span> 
                  <span class="r-sep">/</span> 
                  <span class="r-val-irreg">{{ item.qtd_irreg }}</span>
                </td>
                <td class="text-right rank-prejuizo">{{ fmt(item.prejuizo) }}</td>
                <td class="text-right">{{ fmt(item.ticket) }}</td>
                <td class="text-right">
                  <div class="rank-peso-container">
                    <div class="rank-peso-bar" :style="{ width: item.peso + '%' }"></div>
                    <span class="rank-peso-txt">{{ item.peso.toFixed(1) }}%</span>
                  </div>
                </td>
                <td class="text-center">
                  <button class="rank-goto-btn" @click="scrollToGtin(item.firstGtin)" v-tooltip.top="'Ir para o primeiro GTIN desta substância'">
                    <i class="pi pi-arrow-down" />
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div v-if="rankingData.length > 5" class="ranking-footer">
          <button class="ranking-more-btn" @click="showMoreRanking = !showMoreRanking">
            {{ showMoreRanking ? 'Recolher Ranking' : `Ver todos os ${rankingData.length} medicamentos críticos` }}
            <i class="pi" :class="showMoreRanking ? 'pi-angle-up' : 'pi-angle-down'" />
          </button>
        </div>
      </div>

      <!-- Toolbar -->
      <div class="mov-toolbar">
        <span class="toolbar-count">
          Exibindo {{ visibleSections.length }} de {{ sections.length }} medicamentos
        </span>
        <div class="toolbar-actions">
          <button class="tb-btn" :class="{ 'tb-btn-active': showOnlyIrregular }" @click="showOnlyIrregular = !showOnlyIrregular" v-tooltip.top="'Exibe o histórico completo apenas de medicamentos com irregularidades'">
            <i :class="showOnlyIrregular ? 'pi pi-filter-fill' : 'pi pi-filter'" />
            {{ showOnlyIrregular ? 'Apenas Irregulares' : 'Todas as Linhas' }}
          </button>
          <div class="tb-divider" />
          <button class="tb-btn" @click="expandAll"><i class="pi pi-plus-circle" /> Expandir</button>
          <button class="tb-btn" @click="collapseAll"><i class="pi pi-minus-circle" /> Recolher</button>
        </div>
      </div>

      <div class="mov-body">
        <div v-for="section in visibleSections" :key="section.gtin" :id="'gtin-' + section.gtin" class="gtin-accordion" :class="{ 'is-expanded': expanded.has(section.gtin), 'has-irregular': hasIrregular(section) }">

          <button class="gtin-header" @click="toggle(section.gtin)">
            <i class="pi header-chevron" :class="expanded.has(section.gtin) ? 'pi-chevron-down' : 'pi-chevron-right'" />
            <span class="gtin-badge" @click.stop="copyToClipboard(section.gtin)" v-tooltip.top="'Clique para copiar o GTIN'">
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

            <div v-for="(row, ri) in getVisibleRows(section)" :key="ri" class="gtin-row" :class="{ 'row-irregular': row.tipo_linha === 'venda_irregular', 'row-normal': row.tipo_linha === 'venda_normal' }">
              <div class="gcol gcol-date">{{ row.periodo_inicial ?? '—' }}</div>
              <div class="gcol gcol-date">{{ row.periodo_inicio_irregular ?? '—' }}</div>
              <div class="gcol gcol-date">{{ row.periodo_final ?? '—' }}</div>
              <div class="gcol gcol-num">{{ row.estoque_inicial?.toLocaleString('pt-BR') ?? '—' }}</div>
              <div class="gcol gcol-num">{{ row.estoque_final?.toLocaleString('pt-BR') ?? '—' }}</div>
              <div class="gcol gcol-num">{{ row.vendas?.toLocaleString('pt-BR') ?? '—' }}</div>
              <div class="gcol gcol-num" :class="(row.vendas_irregular ?? 0) > 0 ? 'cell-irreg-num' : ''">{{ row.vendas_irregular?.toLocaleString('pt-BR') ?? '—' }}</div>
              <div class="gcol gcol-cur">{{ fmt(row.valor) }}</div>
              <div class="gcol gcol-cur" :class="(row.valor_irregular ?? 0) > 0 ? 'cell-irreg-cur' : ''">{{ fmt(row.valor_irregular) }}</div>
              <div class="gcol gcol-nf" v-tooltip.top="row.notas"><span class="nf-text">{{ row.notas || '—' }}</span></div>
            </div>

            <!-- Botão Exibir Mais / Recolher -->
            <div v-if="filteredRows(section.rows).length > 2" class="rows-pagination-row">
              <button class="rows-pagination-btn" @click="toggleRowsExpanded(section.gtin)">
                <template v-if="!isRowsExpanded(section.gtin)">
                  <i class="pi pi-angle-double-down" /> 
                  Exibir mais {{ filteredRows(section.rows).length - 2 }} registros
                </template>
                <template v-else>
                  <i class="pi pi-angle-double-up" /> 
                  Recolher registros
                </template>
              </button>
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
.row-irregular { background: color-mix(in srgb, var(--risk-high) 8%, var(--card-bg)); }
.cell-irreg-date, .cell-irreg-num, .cell-irreg-cur { color: var(--risk-high) !important; font-weight: 600; }
.nf-text { font-size: 0.67rem; color: var(--text-muted); display: block; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; max-width: 100%; }
.gtin-subtotal { background: var(--card-bg); border-top: 1px dashed color-mix(in srgb, var(--primary-color) 40%, transparent); }
.gtin-subtotal .gcol { font-size: 0.73rem; font-weight: 600; color: var(--text-secondary); padding: 0.45rem 0.55rem; }
.sub-label { font-weight: 700; opacity: 1; font-size: 0.7rem !important; text-transform: uppercase; letter-spacing: 0.03em; color: var(--text-secondary); }
.gtin-grand-total { 
  display: flex; 
  align-items: center; 
  flex-wrap: wrap; 
  gap: 0.6rem; 
  padding: 0.85rem 1.2rem; 
  background: color-mix(in srgb, var(--primary-color) 10%, var(--card-bg)); 
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

.rows-pagination-row {
  background: color-mix(in srgb, var(--text-color) 2%, var(--card-bg));
  border-bottom: 1px solid color-mix(in srgb, var(--card-border) 60%, transparent);
  display: flex;
  justify-content: center;
  padding: 0.35rem 0;
}
.rows-pagination-btn {
  background: none;
  border: none;
  font-size: 0.65rem;
  font-weight: 700;
  color: var(--primary-color);
  text-transform: uppercase;
  letter-spacing: 0.05em;
  cursor: pointer;
  display: flex;
  align-items: center;
  gap: 0.4rem;
  padding: 0.2rem 1rem;
  border-radius: 4px;
  transition: all 0.2s;
  opacity: 0.85;
}
.rows-pagination-btn:hover {
  opacity: 1;
  background: color-mix(in srgb, var(--primary-color) 8%, transparent);
  letter-spacing: 0.08em;
}
.rows-pagination-btn i {
  font-size: 0.7rem;
}

/* ── ESTILOS DO RANKING ─────────────────────────────────────────────────── */
.mov-stats-grid { display: flex; flex-direction: column; gap: 1.5rem; }

.mov-ranking-card {
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  border-radius: 12px;
  overflow: hidden;
  box-shadow: 0 4px 20px rgba(0, 0, 0, 0.05);
}
.ranking-header { padding: 1rem 1.2rem; border-bottom: 1px solid var(--card-border); display: flex; align-items: baseline; gap: 1rem; }
.rh-title { font-size: 0.85rem; font-weight: 800; color: var(--text-primary); text-transform: uppercase; letter-spacing: 0.02em; }
.rh-sub { font-size: 0.68rem; color: var(--text-muted); }

.ranking-table-wrapper { overflow-x: auto; }
.ranking-table { width: 100%; border-collapse: collapse; table-layout: fixed; }
.ranking-table th { 
  background: color-mix(in srgb, var(--text-color) 2%, var(--card-bg)); 
  padding: 0.7rem 1rem; 
  font-size: 0.62rem; 
  text-transform: uppercase; 
  color: var(--text-muted); 
  text-align: left; 
  border-bottom: 1px solid var(--card-border);
}
.ranking-table td { 
  padding: 0.7rem 1rem; 
  font-size: 0.75rem; 
  border-bottom: 1px solid color-mix(in srgb, var(--card-border) 40%, transparent); 
  overflow: hidden; 
  text-overflow: ellipsis; 
  white-space: nowrap; 
}
.ranking-table .text-right { text-align: right !important; }
.ranking-table .text-center { text-align: center !important; }

.rank-med-cell { display: flex; flex-direction: column; gap: 0.1rem; overflow: hidden; }
.rank-gtin { font-size: 0.6rem; color: var(--text-muted); font-weight: 700; }
.rank-nome { font-weight: 600; color: var(--text-primary); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.rank-periodo { font-size: 0.68rem; color: var(--text-secondary); }
.rank-prejuizo { color: var(--risk-high) !important; font-weight: 800; font-variant-numeric: tabular-nums; }
.r-val-tot { color: var(--text-muted); }
.r-sep { margin: 0 0.2rem; opacity: 0.3; }
.r-val-irreg { font-weight: 700; color: var(--text-primary); }

.rank-peso-container { display: flex; align-items: center; gap: 0.6rem; justify-content: flex-end; }
.rank-peso-bar { height: 4px; background: color-mix(in srgb, var(--primary-color) 60%, transparent); border-radius: 2px; }
.rank-peso-txt { font-size: 0.65rem; font-weight: 700; color: var(--text-secondary); min-width: 35px; }

.rank-goto-btn { 
  background: color-mix(in srgb, var(--text-color) 5%, var(--card-bg)); 
  border: 1px solid color-mix(in srgb, var(--text-color) 15%, transparent); 
  color: color-mix(in srgb, var(--text-color) 70%, transparent); 
  width: 24px; 
  height: 24px; 
  border-radius: 6px; 
  cursor: pointer; 
  display: inline-flex; 
  align-items: center; 
  justify-content: center; 
  transition: all 0.2s; 
}
.rank-goto-btn:hover { background: var(--primary-color); color: white; transform: translateY(2px); border-color: var(--primary-color); }

.ranking-footer { padding: 0.7rem; display: flex; justify-content: center; background: color-mix(in srgb, var(--text-color) 1%, var(--card-bg)); }
.ranking-more-btn { 
  background: none; 
  border: none; 
  color: color-mix(in srgb, var(--text-color) 60%, transparent); 
  font-size: 0.68rem; 
  font-weight: 800; 
  text-transform: uppercase; 
  display: flex; 
  align-items: center; 
  gap: 0.5rem; 
  cursor: pointer;
  padding: 0.3rem 1.5rem;
  border-radius: 20px;
  transition: all 0.2s;
}
.ranking-more-btn:hover { color: var(--primary-color); background: color-mix(in srgb, var(--primary-color) 5%, transparent); letter-spacing: 0.02em; }

@media (max-width: 1200px) {
  .ranking-table th:nth-child(2), .ranking-table td:nth-child(2) { display: none; }
  .ranking-table th:nth-child(3), .ranking-table td:nth-child(3) { display: none; }
}
</style>
