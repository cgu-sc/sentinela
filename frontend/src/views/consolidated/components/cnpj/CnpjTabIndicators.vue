<script setup>
import { computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useIndicadores } from '@/composables/useIndicadores';
import { useFormatting } from '@/composables/useFormatting';
import { INDICATOR_GROUPS, INDICATOR_THRESHOLDS } from '@/config/riskConfig';

const route = useRoute();
const cnpj = computed(() => route.params.cnpj);

const { formatCurrencyFull } = useFormatting();
const { indicadoresData, indicadoresLoading, indicadoresLoaded, fetchIndicadores } = useIndicadores();

onMounted(() => {
  if (cnpj.value) fetchIndicadores(cnpj.value);
});

// ── Helpers de indicadores ────────────────────────────────
function getIndicadorStatus(riscoUf, thresholdKey = 'default') {
  const t = INDICATOR_THRESHOLDS[thresholdKey] ?? INDICATOR_THRESHOLDS.default;
  const r = riscoUf != null ? Math.round(riscoUf * 10) / 10 : null;
  if (r == null)     return { label: 'SEM DADOS', color: 'var(--text-muted)',      severity: 'secondary' };
  if (r >= t.critico) return { label: 'CRÍTICO',  color: 'var(--risk-critical)', severity: 'danger'    };
  if (r >= t.atencao) return { label: 'ATENÇÃO',  color: 'var(--risk-medium)',   severity: 'warning'   };
  return              { label: 'NORMAL',   color: 'var(--risk-low)',      severity: 'success'   };
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
      const riscoUf  = d.risco_uf  != null ? Math.round(d.risco_uf  * 10) / 10 : null;
      const riscoReg = d.risco_reg != null ? Math.round(d.risco_reg * 10) / 10 : null;
      const isCritico = riscoUf != null && riscoUf >= t.critico;
      const isAuditadoComValor = ind.key === 'auditado' && d.valor > 0;

      if (isCritico || isAuditadoComValor) {
        result.push({
          key:     ind.key,
          label:   ind.label,
          formato: ind.formato,
          riscoUf,
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

function riscoPillStyle(risco, thresholdKey = 'default') {
  const s = getIndicadorStatus(risco, thresholdKey);
  const c = s.color;
  return { 
    background: `color-mix(in srgb, ${c} 15%, transparent)`, 
    color: c 
  };
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
      <div v-if="pontosCriticos.length" class="audit-card-new">
        <div class="audit-card-header">
          <div class="audit-title-wrap">
            <i class="pi pi-shield audit-shield-icon" />
            <div class="audit-title-text">
              <h3>Resumo para Auditoria</h3>
              <p>Identificados {{ pontosCriticos.length }} pontos críticos de alto risco</p>
            </div>
          </div>
        </div>
        
        <div class="audit-card-body">
          <div v-for="p in pontosCriticos" :key="p.label" class="audit-row-new">
            <div class="audit-item-main">
              <span class="audit-item-label">{{ p.label }}</span>
              <div class="audit-item-data">
                <span class="audit-badge-val">{{ p.riscoReg?.toFixed(1) ?? p.riscoUf.toFixed(1) }}x</span>
                <span class="audit-item-desc">acima da média regional</span>
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
      </div>

      <div class="ind-section">
        <div class="section-title">
          <i class="pi pi-table" />
          <span>Indicadores de Risco</span>
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
              <th>Mediana BR</th>
              <th>Risco Região</th>
              <th>Risco UF</th>
              <th>Risco BR</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody>
            <template v-for="grupo in INDICATOR_GROUPS" :key="grupo.id">
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
                  <td class="ind-med-cell">{{ formatIndicadorValue(indicadoresData.indicadores[ind.key].med_uf,  ind.formato) }}</td>
                  <td class="ind-med-cell">{{ formatIndicadorValue(indicadoresData.indicadores[ind.key].med_br,  ind.formato) }}</td>
                  <td class="ind-risco-cell">
                    <span
                      class="ind-risco-pill"
                      :style="riscoPillStyle(indicadoresData.indicadores[ind.key].risco_reg, ind.thresholdKey)"
                    >{{ indicadoresData.indicadores[ind.key].risco_reg != null ? indicadoresData.indicadores[ind.key].risco_reg.toFixed(1) + 'x' : '—' }}</span>
                  </td>
                  <td class="ind-risco-cell">
                    <span
                      class="ind-risco-pill"
                      :style="riscoPillStyle(indicadoresData.indicadores[ind.key].risco_uf, ind.thresholdKey)"
                    >{{ indicadoresData.indicadores[ind.key].risco_uf != null ? indicadoresData.indicadores[ind.key].risco_uf.toFixed(1) + 'x' : '—' }}</span>
                  </td>
                  <td class="ind-risco-cell">
                    <span
                      class="ind-risco-pill"
                      :style="riscoPillStyle(indicadoresData.indicadores[ind.key].risco_br, ind.thresholdKey)"
                    >{{ indicadoresData.indicadores[ind.key].risco_br != null ? indicadoresData.indicadores[ind.key].risco_br.toFixed(1) + 'x' : '—' }}</span>
                  </td>
                  <td class="ind-status-cell">
                    <span
                      class="ind-status-pill"
                      :style="riscoPillStyle(indicadoresData.indicadores[ind.key].risco_uf, ind.thresholdKey)"
                    >{{ getIndicadorStatus(indicadoresData.indicadores[ind.key].risco_uf, ind.thresholdKey).label }}</span>
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

/* Títulos de Sessão Padronizados */
.section-title {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  padding: 0.5rem 0;
  border-bottom: 1px solid var(--sidebar-border);
  font-size: 0.85rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: var(--text-color);
  margin-bottom: 0.75rem;
}

.section-title i {
  font-size: 1rem;
  color: var(--primary-color);
}

/* Resumo de auditoria */
/* Novo Card de Auditoria Premiun */
.audit-card-new {
  background: linear-gradient(135deg, rgba(239, 68, 68, 0.08), rgba(239, 68, 68, 0.04));
  border: 1px solid rgba(239, 68, 68, 0.15);
  border-radius: 12px;
  padding: 0.75rem 1rem;
  margin-bottom: 0.75rem;
  backdrop-filter: blur(10px);
  position: relative;
  overflow: hidden;
  box-shadow: 0 4px 20px rgba(0, 0, 0, 0.15);
}

.audit-card-new::before {
  content: '';
  position: absolute;
  top: 0;
  left: 0;
  width: 4px;
  height: 100%;
  background: var(--risk-critical);
  opacity: 0.8;
}

.audit-card-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 0.75rem;
  padding-bottom: 0.5rem;
  border-bottom: 1px solid rgba(239, 68, 68, 0.1);
}

.audit-title-wrap {
  display: flex;
  gap: 0.6rem;
  align-items: center;
}

.audit-shield-icon {
  font-size: 1.1rem;
  color: var(--risk-critical);
  background: rgba(239, 68, 68, 0.1);
  padding: 0.4rem;
  border-radius: 8px;
}

.audit-title-text h3 {
  margin: 0;
  font-size: 0.9rem;
  font-weight: 800;
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
  background: rgba(0, 0, 0, 0.15);
  border: 1px solid rgba(255, 255, 255, 0.04);
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
  font-weight: 700;
  color: var(--text-color);
}

.audit-item-data {
  display: flex;
  align-items: center;
  gap: 0.4rem;
}

.audit-badge-val {
  background: rgba(239, 68, 68, 0.15);
  color: var(--risk-critical);
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
  font-size: 0.55rem;
  font-weight: 700;
  text-transform: uppercase;
  color: #fff;
}

.stat-mini .s-val {
  font-size: 0.8rem;
  font-weight: 700;
  color: #fff;
}

.ind-section {
  margin-top: 0.5rem;
}

.ind-table-wrap {
  overflow-x: auto;
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
  padding: 0.6rem 0.75rem;
  background: color-mix(in srgb, var(--primary-color, #3b82f6) 14%, var(--card-bg));
  color: var(--text-secondary);
  font-size: 0.66rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.07em;
  border-bottom: 2px solid var(--primary-color, #3b82f6);
  white-space: nowrap;
}

.ind-thead th:first-child { text-align: left; }

/* Linha de grupo */
.ind-group-row td {
  padding: 0.4rem 1rem;
  font-size: 0.66rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.07em;
  color: var(--text-secondary);
  background: color-mix(in srgb, var(--sidebar-border) 60%, var(--card-bg));
  border-top: 1px solid var(--sidebar-border);
  border-left: 3px solid color-mix(in srgb, var(--primary-color, #3b82f6) 50%, transparent);
}

/* Linha de dados */
.ind-data-row td {
  padding: 0.5rem 0.75rem;
  border-bottom: 1px solid var(--sidebar-border);
  vertical-align: middle;
  text-transform: none;
  color: var(--text-secondary);
}

.ind-data-row:hover td {
  background: color-mix(in srgb, var(--card-bg) 70%, var(--sidebar-border));
}

/* Célula do nome */
.ind-nome-cell {
  font-weight: 500;
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
  font-weight: 700;
}

.ind-med-cell {
  text-align: center;
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
  opacity: 0.4;
  cursor: pointer;
  flex-shrink: 0;
  transition: opacity 0.15s;
}
.ind-info-icon:hover { opacity: 1; }

/* Sem dados */
.ind-sem-dados {
  text-align: center;
  color: var(--text-muted);
  opacity: 0.5;
  font-size: 0.75rem;
  font-weight: 600;
  padding: 0.5rem;
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
