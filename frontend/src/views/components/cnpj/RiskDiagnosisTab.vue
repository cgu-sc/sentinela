<script setup>
import { computed, ref, watch, onUnmounted } from 'vue';
import { useCnpjDetailStore } from '@/stores/cnpjDetail';
import { useRegional } from '@/composables/useRegional';
import { useFilterStore } from '@/stores/filters';
import { useFilterParameters } from '@/composables/useFilterParameters';
import { API_ENDPOINTS } from '@/config/api';
import RegionalRankChart from '../charts/RegionalRankChart.vue';
import RiskDistributionChart from '../charts/RiskDistributionChart.vue';
import Dropdown from 'primevue/dropdown';

const props = defineProps({
  cnpj: { type: String, required: true },
  geoData: { type: Object, default: null },
  cnpjData: { type: Object, default: null },
  periodSummary: { type: Object, default: null },
  periodLoading: { type: Boolean, default: false }
});

const cnpjDetailStore = useCnpjDetailStore();
const filterStore = useFilterStore();
const { getApiParams } = useFilterParameters();
const { regionalData, regionalLoading, fetchRegional } = useRegional();

// Escopo do scatter regional
const regionalScope = ref('regiao');
const regionalScopes = [
  { label: 'Região de Saúde', value: 'regiao' },
  { label: 'Estado (UF)',      value: 'uf'     },
];

// Score da farmácia atual
// Nota: percValSemComp pode exceder 100% por anomalias nos dados de auditoria
// (val_sem_comp > total_mov). Limitamos a 100 para coincidir com a curva de percentis.
const currentScore = computed(() => {
    // Se estivermos vendo %, usamos o valor do período selecionado (se disponível)
    if (riskMetric.value === 'percentual_sem_comprovacao') {
      const val = props.periodSummary?.percValSemComp ?? props.cnpjData?.percValSemComp ?? 0;
      return Math.min(Number(val), 100);
    }
    // Para Score de Risco, usamos o valor consolidado
    return Number(props.cnpjData?.score_risco_final || 0);
});

// Configuração do Escopo da Curva de Risco
const riskScope = ref('brasil');
const riskMetric = ref('percentual_sem_comprovacao');

const riskScopes = [
  { label: 'Região de Saúde', value: 'regiao' },
  { label: 'UF', value: 'uf' },
  { label: 'Brasil', value: 'brasil' }
];

const riskMetricOptions = [
  { label: 'Score de Risco', value: 'score' },
  { label: '% Não-Comprovação', value: 'percentual_sem_comprovacao' }
];

const updateRiskCurve = () => {
  if (!props.geoData?.sg_uf) return;
  const { inicio, fim } = getApiParams();

  // Durante animação, serve do cache sem round-trip HTTP
  if (filterStore.isAnimating) {
    const key = `${riskScope.value}|${props.geoData.sg_uf}|${props.geoData.id_regiao_saude ?? ''}|${riskMetric.value}|${inicio}|${fim}`;
    if (percentilesCache.has(key)) {
      cnpjDetailStore.setMetricPercentilesDirectly(percentilesCache.get(key), key);
      return;
    }
  }

  cnpjDetailStore.fetchMetricPercentiles(
    riskScope.value,
    props.geoData.sg_uf,
    props.geoData.id_regiao_saude,
    riskMetric.value,
    inicio,
    fim
  );
};

// ── Cache de animação ────────────────────────────────────────────────────────
// Mapa local: "YYYY-MM-DD|YYYY-MM-DD" → farmacias[] (pré-carregado pelo endpoint único)
const periodsCache = new Map();
// Mapa local: "scope|uf|regioId|metric|YYYY-MM-DD|YYYY-MM-DD" → percentiles[]
const percentilesCache = new Map();

// Máximos globais calculados sobre todos os trimestres — usados para fixar os
// eixos do scatter durante a animação e evitar que a escala salte entre passos.
const animationXMax    = ref(null); // max totalMov
const animationYMax    = ref(null); // max score_risco
const animationYMaxPct = ref(null); // max percValSemComp

const loadRegional = () => {
    if (!props.geoData?.sg_uf) return;
    const { inicio, fim } = getApiParams();

    // Durante animação, serve direto do cache sem round-trip HTTP
    const cacheKey = `${inicio}|${fim}`;
    if (periodsCache.has(cacheKey)) {
      regionalData.value = periodsCache.get(cacheKey);
      return;
    }

    const regiao = regionalScope.value === 'regiao' ? props.geoData.no_regiao_saude : null;
    fetchRegional(regiao, props.geoData.sg_uf, inicio, fim);
};

// Observa o gatilho de preload disparado pelo AppSidebar.
// Faz UM único fetch que retorna todos os trimestres, popula o cache e sinaliza 'ready'.
watch(() => filterStore.animationPreload.status, async (status) => {
  if (status !== 'loading') return;
  if (!props.geoData?.sg_uf) {
    filterStore.animationPreload.status = 'ready';
    return;
  }

  try {
    const regiao = regionalScope.value === 'regiao' ? props.geoData.no_regiao_saude : null;
    const scatterUrl = API_ENDPOINTS.analyticsRegionalBenchmarkingAnimation(
      regiao,
      props.geoData.sg_uf,
      filterStore.animationPreload.dataInicio,
      filterStore.animationPreload.dataFim,
    );
    const percentilesUrl = API_ENDPOINTS.analyticsMetricPercentilesAnimation(
      riskScope.value,
      props.geoData.sg_uf,
      props.geoData.id_regiao_saude ?? null,
      riskMetric.value,
      filterStore.animationPreload.dataInicio,
      filterStore.animationPreload.dataFim,
    );

    // Ambos os fetches em paralelo — uma única "rodada" de rede antes de animar
    const [scatterRes, percRes] = await Promise.all([
      fetch(scatterUrl),
      fetch(percentilesUrl),
    ]);
    if (!scatterRes.ok) throw new Error(`scatter HTTP ${scatterRes.status}`);
    if (!percRes.ok)    throw new Error(`percentiles HTTP ${percRes.status}`);

    const [scatterData, percData] = await Promise.all([
      scatterRes.json(),
      percRes.json(),
    ]);

    // Popula cache do scatter: cada período vira entrada keyed por "inicio|fim"
    periodsCache.clear();
    let xMax = 0, scoreMax = 0, pctMax = 0;
    for (const q of scatterData.quarters ?? []) {
      periodsCache.set(`${q.inicio}|${q.fim}`, { farmacias: q.farmacias });
      for (const f of q.farmacias ?? []) {
        xMax     = Math.max(xMax,     f.totalMov || 0);
        scoreMax = Math.max(scoreMax, f.score_risco ?? f.score_risco_final ?? 0);
        pctMax   = Math.max(pctMax,   f.percValSemComp ?? 0);
      }
    }
    animationXMax.value    = xMax     || null;
    animationYMax.value    = scoreMax || null;
    animationYMaxPct.value = pctMax   || null;

    // Popula cache de percentis: keyed por "scope|uf|regioId|metric|inicio|fim"
    percentilesCache.clear();
    for (const q of percData.quarters ?? []) {
      const key = `${riskScope.value}|${props.geoData.sg_uf}|${props.geoData.id_regiao_saude ?? ''}|${riskMetric.value}|${q.inicio}|${q.fim}`;
      percentilesCache.set(key, q.percentiles);
    }
  } catch (e) {
    console.error('[RiskDiagnosis] Erro no preload de animação:', e);
  }

  filterStore.animationPreload.status = 'ready';
});

const clearAnimationState = () => {
  periodsCache.clear();
  percentilesCache.clear();
  animationXMax.value    = null;
  animationYMax.value    = null;
  animationYMaxPct.value = null;
};

// Limpa cache e reseta preload se o componente for desmontado durante animação
onUnmounted(() => {
  clearAnimationState();
  if (filterStore.animationPreload.status !== 'idle') {
    filterStore.animationPreload.status = 'idle';
  }
});

watch(riskScope, updateRiskCurve, { immediate: true });
watch(riskMetric, updateRiskCurve);
watch(() => props.geoData?.sg_uf, () => {
    updateRiskCurve();
    loadRegional();
}, { immediate: true });

// Escuta mudanças no filtro global de período
watch(() => filterStore.periodo, () => {
    updateRiskCurve();
    loadRegional();
}, { deep: true });


watch(regionalScope, () => {
    // Escopo mudou — cache de animação é inválido (regiao vs uf)
    clearAnimationState();
    filterStore.animationPreload.status = 'idle';
    loadRegional();
});

// Texto de ranking baseado no escopo selecionado
const rankingText = computed(() => {
  const d = props.cnpjData;
  if (!d) return null;
  
  // O Rank textual (ex: 4º de 1000) por enquanto só está disponível para o Score final consolidado nos dados do CNPJ
  // Se estiver visualizando apenas a métrica de %, removemos o texto fixo de rank consolidado para não confundir
  if (riskMetric.value !== 'score') return null;

  const map = {
    uf:     { rank: d.rank_uf,           total: d.total_uf,           label: 'no estado' },
    regiao: { rank: d.rank_regiao_saude, total: d.total_regiao_saude, label: 'na região' },
    brasil: { rank: d.rank_nacional,     total: d.total_nacional,     label: 'no Brasil'  },
  };
  const entry = map[riskScope.value];
  if (!entry?.rank) return null;
  return `${entry.rank}º de ${entry.total} ${entry.label}`;
});

// Calcula em qual "topo" de risco a farmácia está — exibido dentro do box do gráfico
const riskRankBadge = computed(() => {
  const data = cnpjDetailStore.metricPercentiles;
  if (!data?.length || currentScore.value === null || currentScore.value === undefined) return null;
  const idx = data.findIndex(d => d.score >= currentScore.value);
  if (idx === -1) return { label: 'Extremo', value: 'TOP 1%', color: '#ef4444' };
  const pct = data[idx].percentile;
  const topPct = 101 - pct;
  if (topPct <= 5)  return { label: 'Crítico', value: `TOP ${topPct}%`,    color: '#ef4444' };
  if (topPct <= 15) return { label: 'Alerta',  value: `TOP ${topPct}%`,    color: '#f59e0b' };
  return             { label: 'Normal',  value: `Percentil ${pct}%`, color: '#10b981' };
});
</script>

<template>
  <div class="tab-content risk-diagnosis-tab">
    
    <!-- Aviso de GeoData ausente -->
    <div v-if="!geoData?.no_regiao_saude" class="placeholder-card">
       <i class="pi pi-exclamation-triangle" />
       <p>Informações geográficas incompletas para realizar o diagnóstico comparativo.</p>
    </div>

    <template v-else>
      <div class="diagnosis-grid">
        
        <!-- CARD 1: POSICIONAMENTO REGIONAL (Scatter) -->
        <div class="diagnosis-card">
          <div class="card-header">
             <div class="header-info">
                <i class="pi pi-users" />
                <span>{{ regionalScope === 'uf' ? 'Posicionamento Estadual' : 'Posicionamento Regional' }}</span>
             </div>
             <div class="scope-selector">
                <Dropdown
                  v-model="regionalScope"
                  :options="regionalScopes"
                  optionLabel="label"
                  optionValue="value"
                  class="p-inputtext-sm"
                  panelClass="card-panel"
                >
                  <template #value="slotProps">
                    <div v-if="slotProps.value" class="flex align-items-center gap-2">
                      <span class="dropdown-selected-label">{{ regionalScopes.find(s => s.value === slotProps.value).label }}</span>
                    </div>
                  </template>
                </Dropdown>
             </div>
          </div>
          <div class="card-body relative-body">
             <div class="chart-wrapper">
                <RegionalRankChart
                   v-if="regionalData?.farmacias?.length"
                   :farmacias="regionalData.farmacias"
                   :cnpj-atual="cnpj"
                   :regiao-nome="regionalScope === 'uf' ? geoData.sg_uf : geoData.no_regiao_saude"
                   :active-metric="riskMetric"
                   :x-axis-max="filterStore.isAnimating ? animationXMax : null"
                   :y-axis-max="filterStore.isAnimating ? (riskMetric === 'percentual_sem_comprovacao' ? animationYMaxPct : animationYMax) : null"
                 />
             </div>

             <!-- AJUDA CONTEXTUAL CARD 1 -->
             <div class="diagnosis-card-help">
               <i class="pi pi-info-circle" />
               <div class="help-text">
                  <b>Contexto {{ regionalScope === 'uf' ? 'Estadual' : 'Regional' }}:</b> Confronta o score deste CNPJ com os CNPJs {{ regionalScope === 'uf' ? 'do mesmo estado' : 'da mesma região de saúde' }}. Permite detectar se o estabelecimento é um "ponto fora da curva". Quanto mais ao topo e à direita do gráfico, pior e mais anômalo é o cenário avaliado.
               </div>
             </div>
          </div>
        </div>

        <!-- CARD 2: CURVA DE ACÚMULO (CLIFF) -->
        <div class="diagnosis-card risk-curve-container">
          <div class="card-header">
             <div class="header-info">
                <i class="pi pi-chart-line" />
                <span>Percentil de Risco</span>
             </div>
             <div class="header-actions">
               <div class="scope-selector">
                  <Dropdown
                    v-model="riskMetric"
                    :options="riskMetricOptions"
                    optionLabel="label"
                    optionValue="value"
                    class="p-inputtext-sm"
                    panelClass="card-panel"
                  >
                    <template #value="slotProps">
                      <div v-if="slotProps.value" class="flex align-items-center gap-2">
                        <span class="dropdown-selected-label">{{ riskMetricOptions.find(m => m.value === slotProps.value)?.label }}</span>
                      </div>
                    </template>
                  </Dropdown>
               </div>
               <div class="scope-selector">
                  <Dropdown
                    v-model="riskScope"
                    :options="riskScopes"
                    optionLabel="label"
                    optionValue="value"
                    class="p-inputtext-sm"
                    panelClass="card-panel"
                  >
                    <template #value="slotProps">
                      <div v-if="slotProps.value" class="flex align-items-center gap-2">
                         <span class="dropdown-selected-label">{{ riskScopes.find(s => s.value === slotProps.value).label }}</span>
                      </div>
                    </template>
                  </Dropdown>
               </div>
             </div>
          </div>
            <div class="card-body">

              <RiskDistributionChart
                :data="cnpjDetailStore.metricPercentiles"
                :current-score="currentScore"
                :loading="cnpjDetailStore.metricPercentilesLoading"
                :ranking-text="rankingText"
                :metric-label="riskMetric === 'score' ? 'Score de Risco' : '% Não-Comprovação'"
                :rank-badge="riskRankBadge"
              />
            <!-- AJUDA CONTEXTUAL CARD 2 -->
            <div class="diagnosis-card-help">
               <i class="pi pi-chart-line" />
               <div class="help-text">
                  <b>Comparativo:</b> Mapeia onde este CNPJ se encontra frente ao universo de estabelecimentos analisados. O deslocamento para a direita indica que este CNPJ possui um score superior à grande maioria dos estabelecimentos.
               </div>
            </div>
          </div>
        </div>

      </div>
    </template>

  </div>
</template>

<style scoped>
.risk-diagnosis-tab {
  display: flex;
  flex-direction: column;
  gap: 1.5rem;
  min-height: 100%;
  flex: 1;
}

.diagnosis-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 1.5rem;
  align-items: stretch;
  flex: 1;
  min-height: 520px;
}

.diagnosis-card {
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  border-radius: 12px;
  overflow: hidden;
  display: flex;
  flex-direction: column;
  box-shadow: 0 4px 12px rgba(0,0,0,0.06);
}

.card-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 0.85rem 1.25rem;
  border-bottom: 1px solid var(--card-border);
  background: rgba(255, 255, 255, 0.02);
}

.header-info {
  display: flex;
  align-items: center;
  gap: 0.8rem;
  font-weight: 600;
  font-size: 0.82rem;
  color: var(--text-color);
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

.header-info i { color: var(--primary-color); font-size: 1.1rem; }
.header-actions {
  display: flex;
  align-items: center;
  gap: 0.75rem;
}

.card-body {
  flex: 1;
  display: flex;
  flex-direction: column;
  min-height: 0; /* permite que flex-children usem height: 100% corretamente */
}

.relative-body {
  position: relative;
}

.chart-wrapper {
  flex: 1;
  display: flex;
  flex-direction: column;
}

.scope-selector { min-width: 180px; }

:deep(.scope-selector .p-dropdown) {
  background: color-mix(in srgb, var(--primary-color) 6%, transparent);
  border: 1px solid color-mix(in srgb, var(--primary-color) 30%, transparent);
  border-radius: 8px;
  transition: border-color 0.2s, background 0.2s;
  width: 100%;
}

:deep(.scope-selector .p-dropdown:hover),
:deep(.scope-selector .p-dropdown.p-focus) {
  border-color: var(--primary-color) !important;
  background: color-mix(in srgb, var(--primary-color) 10%, transparent);
  box-shadow: none !important;
}

:deep(.scope-selector .p-dropdown-label) {
  font-size: 0.75rem;
  font-weight: 500;
  color: var(--primary-color);
  padding: 0.35rem 0.5rem;
}

:deep(.scope-selector .p-dropdown-trigger) {
  color: var(--primary-color);
  width: 2rem;
}

:deep(.scope-selector .p-dropdown-trigger .p-dropdown-trigger-icon) {
  font-size: 0.7rem;
}

/* O painel do Dropdown é renderizado no body (fora do DOM do componente),
   por isso precisa de :global() em vez de :deep() para os estilos alcançarem. */
:global(.p-dropdown-panel.card-panel) {
  background: var(--card-bg) !important;
  border: 1px solid var(--card-border) !important;
  border-radius: 8px;
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.15) !important;
}

:global(.card-panel .p-dropdown-items .p-dropdown-item) {
  font-size: 0.78rem;
  color: var(--text-color) !important;
  padding: 0.5rem 0.85rem;
}

:global(.card-panel .p-dropdown-items .p-dropdown-item:not(.p-highlight):not(.p-disabled):hover) {
  background: color-mix(in srgb, var(--primary-color) 8%, transparent) !important;
  color: var(--primary-color) !important;
}

:global(.card-panel .p-dropdown-items .p-dropdown-item.p-highlight) {
  background: color-mix(in srgb, var(--primary-color) 12%, transparent) !important;
  color: var(--primary-color) !important;
}

.dropdown-selected-label {
  font-size: 0.75rem;
  font-weight: 500;
}

.placeholder-card {
  padding: 4rem;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 1rem;
  color: var(--text-muted);
  background: var(--card-bg);
  border: 1px dashed var(--card-border);
  border-radius: 12px;
}

.placeholder-card i { font-size: 2.5rem; opacity: 0.4; }

.diagnosis-card-help {
  display: flex;
  align-items: flex-start;
  gap: 0.85rem;
  padding: 0.85rem 1rem;
  background: color-mix(in srgb, var(--primary-color) 4%, transparent);
  border-left: 4px solid var(--primary-color);
  border-radius: 6px;
  margin: 1.5rem 1.25rem 1.25rem 1.25rem; /* Descola o texto das bordas e do gráfico */
  margin-top: auto; /* Garante que fique no rodapé da coluna */
}

.diagnosis-card-help i {
  color: var(--primary-color);
  font-size: 1rem;
  margin-top: 2px;
}

.help-text {
  font-size: 0.78rem;
  color: var(--text-secondary);
  line-height: 1.4;
}

.help-text b {
  color: var(--text-color);
  font-weight: 600;
}

</style>
