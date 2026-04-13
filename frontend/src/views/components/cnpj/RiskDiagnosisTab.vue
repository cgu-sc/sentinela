<script setup>
import { computed, ref, watch } from 'vue';
import { useCnpjDetailStore } from '@/stores/cnpjDetail';
import { useRegional } from '@/composables/useRegional';
import RegionalRankChart from '../charts/RegionalRankChart.vue';
import RiskDistributionChart from '../charts/RiskDistributionChart.vue';
import Dropdown from 'primevue/dropdown';

const props = defineProps({
  cnpj: { type: String, required: true },
  geoData: { type: Object, default: null },
  cnpjData: { type: Object, default: null }
});

const cnpjDetailStore = useCnpjDetailStore();
const { regionalData, regionalLoading, fetchRegional } = useRegional();

// Score da farmácia atual
const currentScore = computed(() => {
    const data = props.cnpjData;
    if (!data) return 0;
    return Number(data.score_risco_final || data.percentual_sem_comprovacao || 0);
});

// Configuração do Escopo da Curva de Risco
const riskScope = ref('uf');
const riskScopes = [
  { label: 'Na Região de Saúde', value: 'regiao', icon: 'pi-compass' },
  { label: 'No Estado', value: 'uf', icon: 'pi-map' },
  { label: 'No Brasil (Nacional)', value: 'brasil', icon: 'pi-globe' }
];

const updateRiskCurve = () => {
  if (props.geoData?.sg_uf) {
     cnpjDetailStore.fetchScorePercentiles(
       riskScope.value, 
       props.geoData.sg_uf, 
       props.geoData.id_regiao_saude
     );
  }
};

const loadRegional = () => {
    if (props.geoData?.no_regiao_saude) {
        fetchRegional(props.geoData.no_regiao_saude, props.geoData.sg_uf);
    }
};

watch(riskScope, updateRiskCurve, { immediate: true });
watch(() => props.geoData?.sg_uf, () => {
    updateRiskCurve();
    loadRegional();
}, { immediate: true });

// Calcula em qual "topo" de risco a farmácia está
const riskRankBadge = computed(() => {
  const data = cnpjDetailStore.scorePercentiles;
  if (!data?.length || !currentScore.value) return null;
  const idx = data.findIndex(d => d.score >= currentScore.value);
  if (idx === -1) return { label: 'Extremo', value: 'TOP 1%', color: '#ef4444' };
  const pct = data[idx].percentile;
  const topPct = 101 - pct;
  if (topPct <= 5) return { label: 'Crítico', value: `TOP ${topPct}%`, color: '#ef4444' };
  if (topPct <= 15) return { label: 'Alerta', value: `TOP ${topPct}%`, color: '#f59e0b' };
  return { label: 'Normal', value: 'Dentro da Média', color: '#10b981' };
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
                <span>Posicionamento Regional</span>
             </div>
             <div v-if="geoData?.no_regiao_saude" class="header-context">
                {{ geoData.no_regiao_saude }}
             </div>
          </div>
          <div class="card-body">
             <div v-if="regionalLoading" class="inner-loading">
                <i class="pi pi-spin pi-spinner" />
                <span>Mapeando vizinhança...</span>
             </div>
             <RegionalRankChart 
                v-else-if="regionalData?.farmacias?.length"
                :farmacias="regionalData.farmacias"
                :cnpj-atual="cnpj"
                :regiao-nome="geoData.no_regiao_saude"
              />
          </div>
        </div>

        <!-- CARD 2: CURVA DE ACÚMULO (CLIFF) -->
        <div class="diagnosis-card risk-curve-container">
          <div class="card-header">
             <div class="header-info">
                <i class="pi pi-chart-line" />
                <span>Diagnóstico Comparativo de Risco</span>
                
                <div v-if="riskRankBadge" 
                     class="risk-rank-badge" 
                     :style="{ background: riskRankBadge.color + '15', color: riskRankBadge.color, borderColor: riskRankBadge.color + '40' }">
                   <span class="badge-label">{{ riskRankBadge.label }}</span>
                   <span class="badge-value">{{ riskRankBadge.value }}</span>
                </div>
             </div>
             <div class="scope-selector p-input-filled">
                <Dropdown 
                  v-model="riskScope" 
                  :options="riskScopes" 
                  optionLabel="label" 
                  optionValue="value"
                  class="p-inputtext-sm"
                >
                  <template #value="slotProps">
                    <div v-if="slotProps.value" class="flex align-items-center gap-2">
                       <i :class="riskScopes.find(s => s.value === slotProps.value).icon" />
                       <span class="dropdown-selected-label">{{ riskScopes.find(s => s.value === slotProps.value).label }}</span>
                    </div>
                  </template>
                </Dropdown>
             </div>
          </div>
          <div class="card-body">
            <RiskDistributionChart
              v-if="cnpjDetailStore.scorePercentiles"
              :data="cnpjDetailStore.scorePercentiles"
              :current-score="currentScore"
              :loading="cnpjDetailStore.scorePercentilesLoading"
            />
          </div>
        </div>

      </div>

      <div class="diagnosis-footer-info">
        <i class="pi pi-info-circle" />
        <p>
          Este diagnóstico compara o score desta farmácia com o comportamento estatístico de toda a população de estabelecimentos do escopo selecionado. 
          Resultados no topo da curva indicam atipicidade grave e prioridade de fiscalização.
        </p>
      </div>
    </template>

  </div>
</template>

<style scoped>
.risk-diagnosis-tab {
  display: flex;
  flex-direction: column;
  gap: 1.5rem;
}

.diagnosis-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 1.5rem;
  align-items: stretch;
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
  font-weight: 700;
  font-size: 0.82rem;
  color: var(--text-color);
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

.header-info i { color: var(--primary-color); font-size: 1.1rem; }

.header-context {
  font-size: 0.75rem;
  color: var(--text-muted);
  background: var(--tabs-border);
  padding: 0.2rem 0.6rem;
  border-radius: 4px;
}

.card-body {
  flex: 1;
  min-height: 350px;
  display: flex;
  flex-direction: column;
}

.inner-loading {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 0.75rem;
  color: var(--text-muted);
  font-size: 0.85rem;
}

.inner-loading i { font-size: 1.5rem; color: var(--primary-color); }

/* Badge de Ranking */
.risk-rank-badge {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  padding: 0.2rem 0.5rem;
  border-radius: 4px;
  border: 1px solid;
  font-size: 0.7rem;
  margin-left: 0.5rem;
}

.badge-label { font-weight: 500; opacity: 0.8; border-right: 1px solid currentColor; padding-right: 0.4rem; }
.badge-value { font-weight: 800; }

.scope-selector { min-width: 200px; }

:deep(.p-dropdown) { background: transparent !important; border-color: var(--card-border) !important; }
:deep(.p-dropdown-label) { font-size: 0.75rem; padding: 0.35rem 0.6rem; }

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

.diagnosis-footer-info {
  display: flex;
  align-items: flex-start;
  gap: 0.75rem;
  padding: 1.25rem;
  background: color-mix(in srgb, var(--primary-color) 5%, transparent);
  border-left: 4px solid var(--primary-color);
  border-radius: 8px;
  font-size: 0.85rem;
  color: var(--text-secondary);
  line-height: 1.5;
}

.diagnosis-footer-info i { color: var(--primary-color); font-size: 1.1rem; margin-top: 2px; }
</style>
