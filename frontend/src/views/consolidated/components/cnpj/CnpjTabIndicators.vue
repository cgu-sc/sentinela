<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useIndicadores } from '@/composables/useIndicadores';
import { useFormatting } from '@/composables/useFormatting';
import { INDICATOR_GROUPS, INDICATOR_THRESHOLDS } from '@/config/riskConfig';

const route = useRoute();
const cnpj = computed(() => route.params.cnpj);

const { formatCurrencyFull } = useFormatting();
const { indicadoresData, indicadoresLoading, indicadoresLoaded, fetchIndicadores } = useIndicadores();
const isAuditExpanded = ref(false); // Começa recolhido por padrão para dar destaque

// Inicializa o filtro a partir do localStorage (persistência)
const showOnlyHighRisk = ref(localStorage.getItem('sentinela_indicators_filter_only_risky') === 'true');

// Salva no localStorage sempre que o filtro for alterado
watch(showOnlyHighRisk, (newVal) => {
  localStorage.setItem('sentinela_indicators_filter_only_risky', newVal);
});

onMounted(() => {
  if (cnpj.value) fetchIndicadores(cnpj.value);
});

// ── Helpers de indicadores ────────────────────────────────
function getIndicadorStatus(riscoUf, thresholdKey = 'default') {
  const t = INDICATOR_THRESHOLDS[thresholdKey] ?? INDICATOR_THRESHOLDS.default;
  const r = riscoUf != null ? Math.round(riscoUf * 10) / 10 : null;
  if (r == null)     return { label: 'SEM DADOS', color: 'var(--text-muted)',  severity: 'secondary' };
  if (r >= t.critico) return { label: 'CRÍTICO',  color: 'var(--risk-indicator-critical)', severity: 'danger'    };
  if (r >= t.atencao) return { label: 'ATENÇÃO',  color: 'var(--risk-indicator-warning)',  severity: 'warning'   };
  return              { label: 'NORMAL',   color: 'var(--risk-indicator-normal)',   severity: 'success'   };
}

function formatIndicadorValue(valor, formato) {
  if (valor == null) return '—';
  if (formato === 'pct')  return valor.toFixed(2) + '%';
  if (formato === 'pct3') return valor.toFixed(3) + '%';
  if (formato === 'val')  return formatCurrencyFull(valor);
  return valor.toFixed(2);
}

// ── Pontos críticos (resumo de auditoria) ────────────────
const pontosCriticos = computed(() => {
  if (!indicadoresData.value?.indicadores) return [];
  const result = [];
  for (const grupo of INDICATOR_GROUPS) {
    for (const ind of grupo.indicators) {
      const d = indicadoresData.value.indicadores[ind.key];
      if (!d || d.valor == null) continue;
      const t = INDICATOR_THRESHOLDS[ind.thresholdKey] ?? INDICATOR_THRESHOLDS.default;
      const riscoReg = d.risco_reg != null ? Math.round(d.risco_reg * 10) / 10 : null;
      const isCriticoReg = riscoReg != null && riscoReg >= t.critico;

      if (isCriticoReg) {
        result.push({
          key:     ind.key,
          label:   ind.label,
          formato: ind.formato,
          riscoReg,
          valor:   d.valor,
          medReg:  d.med_reg,
        });
      }
    }
  }
  return result.sort((a, b) => {
    if (a.key === 'auditado') return -1;
    if (b.key === 'auditado') return 1;
    return (b.riscoReg ?? 0) - (a.riscoReg ?? 0);
  });
});

// Filtra os grupos conforme o toggle de risco
const filteredGroups = computed(() => {
  if (!showOnlyHighRisk.value) return INDICATOR_GROUPS;

  return INDICATOR_GROUPS.map(grupo => {
    const indicators = grupo.indicators.filter(ind => {
      const d = indicadoresData.value?.indicadores?.[ind.key];
      if (!d || d.valor == null) return false;
      const status = getIndicadorStatus(d.risco_reg, ind.thresholdKey);
      return status.label !== 'NORMAL';
    });
    return { ...grupo, indicators };
  }).filter(grupo => grupo.indicators.length > 0);
});

defineExpose({
  getIndicadoresData: () => indicadoresData.value?.indicadores ?? {},
  getPontosCriticos: () => pontosCriticos.value,
});

function riscoPillStyle(risco, thresholdKey = 'default') {
  const s = getIndicadorStatus(risco, thresholdKey);
  const c = s.color;
  return { 
    background: `color-mix(in srgb, ${c} 15%, transparent)`, 
    color: c 
  };
}

function riscoTextStyle(risco, thresholdKey = 'default') {
  const s = getIndicadorStatus(risco, thresholdKey);
  return { color: s.color };
}
</script>

<template>
  <div class="tab-content indicadores-tab">

    <div v-if="indicadoresLoading" class="tab-placeholder">
      <i class="pi pi-spin pi-spinner placeholder-icon" />
      <p>Carregando indicadores...</p>
    </div>

    <div v-else-if="indicadoresLoaded && !Object.keys(indicadoresData?.indicadores ?? {}).length" class="tab-placeholder">
      <i class="pi pi-inbox placeholder-icon" />
      <p>Nenhum indicador encontrado para este CNPJ.</p>
    </div>

    <template v-else-if="indicadoresLoaded">

      <!-- RESUMO DE AUDITORIA (CARD DE PONTOS CRÍTICOS) -->
      <div v-if="pontosCriticos.length" class="audit-card-new" :class="{ 'is-collapsed': !isAuditExpanded }">
        <div class="audit-card-header" @click="isAuditExpanded = !isAuditExpanded" style="cursor: pointer;">
          <div class="audit-title-wrap">
            <i class="pi pi-shield audit-shield-icon" />
            <div class="audit-title-text">
              <h3>Resumo para Auditoria</h3>
              <p>Identificados {{ pontosCriticos.length }} indicador(es) em nível crítico</p>
            </div>
          </div>
          <div class="audit-header-actions">
            <span class="audit-expand-label">{{ isAuditExpanded ? 'Recolher detalhes' : 'Ver detalhes' }}</span>
            <i class="pi" :class="isAuditExpanded ? 'pi-chevron-up' : 'pi-chevron-down'" />
          </div>
        </div>
        
        <transition name="audit-slide">
          <div v-show="isAuditExpanded" class="audit-card-body">
            <div v-for="p in pontosCriticos" :key="p.label" class="audit-row-new">
              <div class="audit-item-main">
                <span class="audit-item-label">{{ p.label }}</span>
                <div class="audit-item-data">
                  <span class="audit-badge-val">{{ p.riscoReg.toFixed(1) }}x</span>
                  <span class="audit-item-desc">acima da mediana regional</span>
                </div>
              </div>
              <div class="audit-item-stats">
                <div class="stat-mini">
                  <span class="s-label">Farmácia</span>
                  <span class="s-val">{{ formatIndicadorValue(p.valor, p.formato) }}</span>
                </div>
                <div class="stat-mini">
                  <span class="s-label">Regional</span>
                  <span class="s-val">{{ formatIndicadorValue(p.medReg, p.formato) }}</span>
                </div>
              </div>
            </div>
          </div>
        </transition>
      </div>

      <div class="ind-section">
        <div class="ind-card">
        <div class="section-title">
          <div class="title-main">
            <i class="pi pi-table" />
            <span>Indicadores de Risco</span>
          </div>
          <div class="title-actions">
            <div class="risk-toggle-pill" :class="{ 'active': showOnlyHighRisk }" @click="showOnlyHighRisk = !showOnlyHighRisk">
              <div class="risk-icon-wrap">
                <i class="pi" :class="showOnlyHighRisk ? 'pi-filter-fill' : 'pi-filter'" />
                <span v-if="showOnlyHighRisk" class="risk-ping" />
              </div>
              <span>Somente itens com risco</span>
            </div>
          </div>
        </div>
        <div class="ind-table-wrap">
        <table class="ind-table">
          <colgroup>
            <col style="width:28%" />
            <col style="width:9%" />
            <col style="width:9%" />
            <col style="width:9%" />
            <col style="width:9%" />
            <col style="width:9%" />
            <col style="width:9%" />
            <col style="width:9%" />
            <col style="width:9%" />
          </colgroup>
          <thead class="ind-thead">
            <tr>
              <th>Indicador</th>
              <th>Farmácia</th>
              <th>Mediana Região</th>
              <th>Mediana UF</th>
              <th>Mediana Nacional</th>
              <th>Risco Região</th>
              <th>Risco UF</th>
              <th>Risco Nacional</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody>
            <template v-for="grupo in filteredGroups" :key="grupo.id">
              <tr class="ind-group-row">
                <td colspan="9">{{ grupo.label }}</td>
              </tr>
              <tr
                v-for="ind in grupo.indicators"
                :key="ind.key"
                class="ind-data-row"
              >
                <td class="ind-nome-cell">
                  <div class="ind-nome-inner">
                    <span>{{ ind.label }}</span>
                    <i
                      class="pi pi-info-circle ind-info-icon"
                      v-tooltip.right="{ value: ind.metodologia, class: 'ind-tooltip' }"
                    />
                  </div>
                </td>

                <template v-if="indicadoresData.indicadores[ind.key]?.valor != null">
                  <td class="ind-val-cell">{{ formatIndicadorValue(indicadoresData.indicadores[ind.key].valor, ind.formato) }}</td>
                  <td class="ind-med-cell">{{ formatIndicadorValue(indicadoresData.indicadores[ind.key].med_reg, ind.formato) }}</td>
                  <td class="ind-med-cell ind-secondary-cell"><span class="ind-muted-text">{{ formatIndicadorValue(indicadoresData.indicadores[ind.key].med_uf,  ind.formato) }}</span></td>
                  <td class="ind-med-cell ind-secondary-cell"><span class="ind-muted-text">{{ formatIndicadorValue(indicadoresData.indicadores[ind.key].med_br,  ind.formato) }}</span></td>
                  <td class="ind-risco-cell">
                    <span
                      class="ind-risco-pill"
                      :style="riscoPillStyle(indicadoresData.indicadores[ind.key].risco_reg, ind.thresholdKey)"
                    >{{ indicadoresData.indicadores[ind.key].risco_reg != null ? indicadoresData.indicadores[ind.key].risco_reg.toFixed(1) + 'x' : '—' }}</span>
                  </td>
                  <td class="ind-risco-cell ind-secondary-cell">
                    <span class="ind-risco-muted" :style="riscoTextStyle(indicadoresData.indicadores[ind.key].risco_uf, ind.thresholdKey)">{{ indicadoresData.indicadores[ind.key].risco_uf != null ? indicadoresData.indicadores[ind.key].risco_uf.toFixed(1) + 'x' : '—' }}</span>
                  </td>
                  <td class="ind-risco-cell ind-secondary-cell">
                    <span class="ind-risco-muted" :style="riscoTextStyle(indicadoresData.indicadores[ind.key].risco_br, ind.thresholdKey)">{{ indicadoresData.indicadores[ind.key].risco_br != null ? indicadoresData.indicadores[ind.key].risco_br.toFixed(1) + 'x' : '—' }}</span>
                  </td>
                  <td class="ind-status-cell">
                    <span
                      class="ind-status-pill"
                      :style="riscoPillStyle(indicadoresData.indicadores[ind.key].risco_reg, ind.thresholdKey)"
                    >{{ getIndicadorStatus(indicadoresData.indicadores[ind.key].risco_reg, ind.thresholdKey).label }}</span>
                  </td>
                </template>
                <template v-else>
                  <td colspan="8" class="ind-sem-dados">SEM DADOS</td>
                </template>
              </tr>
            </template>
          </tbody>
        </table>
        </div><!-- ind-table-wrap -->
        </div><!-- ind-card -->
      </div><!-- ind-section -->
    </template>

    <div v-else class="tab-placeholder">
      <i class="pi pi-shield placeholder-icon" />
      <p>Clique na aba para carregar os indicadores.</p>
    </div>

  </div>
</template>

<style scoped>
/* ── INDICADORES ─────────────────────────────────────── */
.indicadores-tab {
  display: flex;
  flex-direction: column;
  gap: 1.5rem;
}

.section-title {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0.5rem 0;
  border-bottom: 1px solid var(--tabs-border);
  margin-bottom: 0.75rem;
}

.title-main {
  display: flex;
  align-items: center;
  gap: 0.75rem;
}

.title-main i {
  font-size: 1rem;
  color: var(--primary-color);
}

.title-main span {
  font-size: 0.85rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: var(--text-color);
}

.risk-toggle-pill {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.35rem 0.75rem;
  background: var(--bg-color);
  border: 1px solid var(--tabs-border);
  border-radius: 99px;
  cursor: pointer;
  font-size: 0.7rem;
  font-weight: 700;
  color: var(--text-muted);
  transition: all 0.2s ease;
  user-select: none;
}

.risk-toggle-pill:hover {
  border-color: var(--risk-indicator-warning);
  color: var(--text-color);
}

.risk-toggle-pill.active {
  background: color-mix(in srgb, var(--risk-indicator-warning) 18%, var(--card-bg));
  border-color: var(--risk-indicator-warning);
  color: var(--risk-indicator-warning);
  box-shadow: 0 0 12px color-mix(in srgb, var(--risk-indicator-warning) 25%, transparent);
  animation: risk-pulse 2s infinite ease-in-out;
}

.risk-icon-wrap {
  position: relative;
  display: flex;
  align-items: center;
}

.risk-ping {
  position: absolute;
  top: -2px;
  right: -4px;
  width: 6px;
  height: 6px;
  background: var(--risk-indicator-critical);
  border-radius: 50%;
  border: 1px solid var(--card-bg);
  box-shadow: 0 0 4px var(--risk-indicator-critical);
}

@keyframes risk-pulse {
  0% { transform: scale(1); box-shadow: 0 0 8px color-mix(in srgb, var(--risk-indicator-warning) 15%, transparent); }
  50% { transform: scale(1.02); box-shadow: 0 0 15px color-mix(in srgb, var(--risk-indicator-warning) 35%, transparent); }
  100% { transform: scale(1); box-shadow: 0 0 8px color-mix(in srgb, var(--risk-indicator-warning) 15%, transparent); }
}

/* Resumo de auditoria */
/* Novo Card de Auditoria Premiun */
.audit-card-new {
  background: color-mix(in srgb, var(--risk-indicator-critical) 12%, var(--card-bg));
  border: 1px solid color-mix(in srgb, var(--risk-indicator-critical) 25%, transparent);
  border-radius: 12px;
  padding: 0.75rem 1rem;
  margin-bottom: 0.4rem;
  position: relative;
  overflow: hidden;
  box-shadow: 0 4px 15px rgba(0,0,0,0.08); /* Sombra um pouco mais forte para destaque */
  transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
}

.audit-card-new.is-collapsed {
  background: color-mix(in srgb, var(--risk-indicator-critical) 8%, var(--card-bg));
  box-shadow: 0 2px 8px rgba(0,0,0,0.06);
}

.audit-card-new::before {
  content: '';
  position: absolute;
  top: 0;
  left: 0;
  width: 4px;
  height: 100%;
  background: var(--risk-indicator-critical);
  opacity: 0.8;
}

.audit-card-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 0px; /* Removido para transição */
  padding-bottom: 0px; /* Removido para transição */
  border-bottom: 1px solid transparent;
  transition: all 0.3s ease;
}

/* Quando expandido, recupera as margens e borda */
.audit-card-new:not(.is-collapsed) .audit-card-header {
  margin-bottom: 0.75rem;
  padding-bottom: 0.5rem;
  border-bottom: 1px solid color-mix(in srgb, var(--risk-indicator-critical) 20%, transparent);
}

.audit-header-actions {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  color: var(--risk-indicator-critical);
  font-weight: 700;
  font-size: 0.75rem;
}

.audit-expand-label {
  text-transform: uppercase;
  letter-spacing: 0.05em;
  opacity: 0.8;
}

.audit-title-wrap {
  display: flex;
  gap: 0.6rem;
  align-items: center;
}

.audit-shield-icon {
  font-size: 1.1rem;
  color: var(--risk-indicator-critical);
  background: color-mix(in srgb, var(--risk-indicator-critical) 18%, transparent);
  padding: 0.4rem;
  border-radius: 8px;
}

.audit-title-text h3 {
  margin: 0;
  font-size: 1.1rem;
  font-weight: 700;
  color: var(--text-color);
}

.audit-title-text p {
  margin: 0;
  font-size: 0.7rem;
  color: var(--text-secondary);
}

.audit-card-body {
  display: flex;
  flex-direction: column;
  gap: 0.4rem;
}

.audit-row-new {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 0.4rem 0.8rem;
  background: color-mix(in srgb, var(--risk-indicator-critical) 8%, var(--card-bg));
  border: 1px solid color-mix(in srgb, var(--risk-indicator-critical) 15%, transparent);
  border-radius: 8px;
  transition: all 0.2s ease;
}

.audit-row-new:hover {
  background: rgba(239, 68, 68, 0.05);
  border-color: rgba(239, 68, 68, 0.2);
  transform: translateX(4px);
}

.audit-item-main {
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
}

.audit-item-label {
  font-size: 0.8rem;
  font-weight: 500;
  color: var(--text-color);
}

.audit-item-data {
  display: flex;
  align-items: center;
  gap: 0.4rem;
}

.audit-badge-val {
  background: color-mix(in srgb, var(--risk-indicator-critical) 22%, transparent);
  color: var(--risk-indicator-critical);
  font-size: 0.7rem;
  font-weight: 800;
  padding: 0.05rem 0.4rem;
  border-radius: 4px;
}

.audit-item-desc {
  font-size: 0.7rem;
  color: var(--text-secondary);
}

.audit-item-stats {
  display: flex;
  gap: 1rem;
}

.stat-mini {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
}

.stat-mini .s-label {
  font-size: 0.6rem;
  font-weight: 600;
  text-transform: uppercase;
  color: var(--text-color);
  opacity: 0.8;
}

/* Transição Slide */
.audit-slide-enter-active,
.audit-slide-leave-active {
  transition: all 0.3s ease-out;
  max-height: 1000px;
}

.audit-slide-enter-from,
.audit-slide-leave-to {
  max-height: 0;
  opacity: 0;
  margin-top: 0;
  transform: translateY(-8px);
}

.stat-mini .s-val {
  font-size: 0.8rem;
  font-weight: 600;
  color: var(--text-color);
}

.ind-section {
  margin-top: 0;
}

.ind-card {
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  border-radius: 12px;
  padding: 1.25rem 1.25rem 0 1.25rem;
  box-shadow: 0 2px 8px rgba(0,0,0,0.06);
  overflow: hidden;
}

.ind-card .section-title {
  margin-bottom: 1rem;
}

.ind-table-wrap {
  overflow-x: auto;
  margin: 0 -1.25rem;
}

.ind-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 0.8rem;
}

/* Cabeçalho fixo */
.ind-thead th {
  position: sticky;
  top: 0;
  z-index: 2;
  text-align: center;
  padding: 0.75rem 0.75rem;
  background: transparent;
  color: var(--text-secondary);
  font-size: 0.72rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  border-bottom: 2px solid var(--tabs-border);
  white-space: nowrap;
}

.ind-thead th:first-child { text-align: left; }

/* Linha de grupo - Estilo Relatório de Mesa (Refinado) */
.ind-group-row td {
  padding: 1rem 1rem 0.35rem 1rem;
  font-size: 0.72rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  color: var(--primary-color);
  background: transparent !important;
  border-top: 2px solid var(--primary-color) !important;
  border-bottom: none !important;
}

/* Linha de dados - Corrigindo Uniformidade do Hover */
.ind-data-row td {
  padding: 0.65rem 0.75rem;
  border-bottom: 1px solid var(--tabs-border);
  vertical-align: middle;
  text-transform: none;
  color: var(--text-color);
  background: transparent; /* Garante que a célula seja transparente à base do TR */
  transition: background 0.15s ease;
}

.ind-data-row:hover td {
  background: var(--table-hover) !important;
}

/* Célula do nome */
.ind-nome-cell {
  font-size: 0.85rem;
  font-weight: 400;
}

.ind-nome-inner {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  white-space: nowrap;
}

/* Células de valor e mediana */
.ind-val-cell {
  text-align: center;
}

.ind-med-cell {
  text-align: center;
}

/* Colunas coadjuvantes — Mediana UF/BR e Risco UF/BR */
.ind-secondary-cell {
  font-size: 0.74rem;
}

.ind-muted-text {
  color: var(--text-color);
  opacity: 0.7;
}

.ind-risco-muted {
  font-size: 0.74rem;
  font-weight: 600;
  color: var(--text-color);
  opacity: 0.7; /* Transparência age na span e não na TD */
}


/* Células de risco */
.ind-risco-cell {
  text-align: center;
}

.ind-risco-pill {
  display: inline-block;
  padding: 0.15rem 0.55rem;
  border-radius: 99px;
  font-size: 0.72rem;
  font-weight: 700;
  letter-spacing: 0.02em;
  min-width: 3.2rem;
  text-align: center;
}

/* Célula de status */
.ind-status-cell { text-align: center; }

.ind-status-pill {
  display: inline-block;
  padding: 0.2rem 0.6rem;
  border-radius: 99px;
  font-size: 0.65rem;
  font-weight: 700;
  letter-spacing: 0.05em;
  white-space: nowrap;
}

/* Info icon */
.ind-info-icon {
  font-size: 0.7rem;
  color: var(--text-muted); /* Usamos a cor muted em vez de opacidade */
  cursor: pointer;
  flex-shrink: 0;
  transition: color 0.15s;
}
.ind-info-icon:hover { color: var(--text-color); }

/* Sem dados */
.ind-sem-dados {
  text-align: center;
  color: var(--text-muted);
  font-size: 0.75rem;
  font-weight: 600;
  padding: 0.75rem;
}

.tab-placeholder {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 4rem 2rem;
  gap: 1rem;
  color: var(--text-muted);
  text-align: center;
}
.placeholder-icon {
  font-size: 2.5rem;
  color: var(--sidebar-border);
  opacity: 0.7;
}


</style>
