<script setup>
import { computed, ref, onMounted, watch } from "vue";
import { useDelayedLoading } from '@/composables/useDelayedLoading';
import { storeToRefs } from 'pinia';
import { useCnpjDetailStore } from '@/stores/cnpjDetail';
import { useFilterParameters } from "@/composables/useFilterParameters";

import CRMKpiGrid from './CRMKpiGrid.vue';
import CRMCronologia from './CRMCronologia.vue';
import CRMPrescritoresTable from './CRMPrescritoresTable.vue';

const props = defineProps({
  cnpj: { type: String, required: true },
});

const cnpjDetailStore = useCnpjDetailStore();
const { prescritoresData, prescritoresLoading, prescritoresError, activeCrmViewMode } = storeToRefs(cnpjDetailStore);
const { getApiParams } = useFilterParameters();
// ── Flicker-Free Cache ────────────────────────────────────────────────────
const cachedPrescritoresData = ref(prescritoresData.value);
const showRefreshingKPIs = useDelayedLoading(prescritoresLoading);

watch([prescritoresData, prescritoresLoading], ([newData, loading]) => {
  if (newData && !loading) cachedPrescritoresData.value = newData;
}, { immediate: true });

onMounted(() => {
  if (props.cnpj) {
    const { inicio, fim } = getApiParams();
    cnpjDetailStore.fetchCrmDailyProfile(props.cnpj, inicio, fim);
    cnpjDetailStore.fetchCrmHourlyProfile(props.cnpj, inicio, fim);
  }
});

// ── Estado de Navegação (Agora via Store) ─────────────────────────────────
const activeKpiFilter = ref(null);

const isRefreshing = computed(() => showRefreshingKPIs.value && cachedPrescritoresData.value !== null);

// ── Dados Base ────────────────────────────────────────────────────────────
const summary = computed(() => cachedPrescritoresData.value?.summary || {});
const crmsInteresse = computed(() => cachedPrescritoresData.value?.crms_interesse || []);
const cnpjAlerts = computed(() => cachedPrescritoresData.value?.cnpj_alerts || []);

// ── KPIs (mantidos aqui para defineExpose) ────────────────────────────────
const concentracaoTop1 = computed(() => summary.value.pct_concentracao_top1 || 0);
const concentracaoTop5 = computed(() => summary.value.pct_concentracao_top5 || 0);

const valorTop1 = computed(() => crmsInteresse.value.length > 0 ? crmsInteresse.value[0].vl_total_prescricoes || 0 : 0);
const valorTop5 = computed(() => crmsInteresse.value.slice(0, 5).reduce((acc, curr) => acc + (curr.vl_total_prescricoes || 0), 0));

const doctorsIntensivaLocal  = computed(() => crmsInteresse.value.filter(m => m.flag_robo > 0));
const doctorsIntensivaBrasil = computed(() => crmsInteresse.value.filter(m => m.flag_robo_oculto > 0));
const qtdPrescrIntensivaLocal   = computed(() => doctorsIntensivaLocal.value.length);
const qtdPrescrIntensivaOcultos = computed(() => doctorsIntensivaBrasil.value.length);
const qtdPrescrIntensivaTotal   = computed(() => {
  const ids = new Set([...doctorsIntensivaLocal.value.map(m => m.id_medico), ...doctorsIntensivaBrasil.value.map(m => m.id_medico)]);
  return ids.size;
});

const qtdCrmInvalido          = computed(() => crmsInteresse.value.filter(m => m.flag_crm_invalido > 0).length);
const qtdPrescrAntesRegistro  = computed(() => crmsInteresse.value.filter(m => m.flag_prescricao_antes_registro > 0).length);
const totalIrregularesCfm     = computed(() => qtdCrmInvalido.value + qtdPrescrAntesRegistro.value);
const pctFraudeCrm            = computed(() => (summary.value.pct_valor_crm_invalido || 0) + (summary.value.pct_valor_crm_antes_registro || 0));
const valorFraudeCrm          = computed(() => (summary.value.vl_crm_invalido || 0) + (summary.value.vl_crm_antes_registro || 0));

const qtdCrmExclusivo         = computed(() => crmsInteresse.value.filter(m => m.flag_crm_exclusivo > 0).length);
const qtdLancamentosAgrupados = computed(() => crmsInteresse.value.filter(m => m.alerta_concentracao_mesmo_crm).length);
const totalSurtosCnpj         = computed(() => cnpjAlerts.value.length);
const diasComSurtosCnpj       = computed(() => new Set(cnpjAlerts.value.map(a => a.dt)).size);
const qtdAcima400km           = computed(() => crmsInteresse.value.filter(m => m.alerta5_geografico).length);

// Objeto passado como prop para CRMKpiGrid
const kpiData = computed(() => ({
  concentracaoTop1: concentracaoTop1.value,
  concentracaoTop5: concentracaoTop5.value,
  valorTop1: valorTop1.value,
  valorTop5: valorTop5.value,
  medianaTop5Reg: summary.value.mediana_concentracao_top5_reg ?? summary.value.mediana_concentracao_top5_br ?? 40,
  idTop1Prescritor: summary.value.id_top1_prescritor,
  qtdPrescrIntensivaTotal: qtdPrescrIntensivaTotal.value,
  qtdPrescrIntensivaLocal: qtdPrescrIntensivaLocal.value,
  qtdPrescrIntensivaOcultos: qtdPrescrIntensivaOcultos.value,
  qtdLancamentosAgrupados: qtdLancamentosAgrupados.value,
  qtdCrmExclusivo: qtdCrmExclusivo.value,
  totalIrregularesCfm: totalIrregularesCfm.value,
  qtdCrmInvalido: qtdCrmInvalido.value,
  qtdPrescrAntesRegistro: qtdPrescrAntesRegistro.value,
  valorFraudeCrm: valorFraudeCrm.value,
  pctFraudeCrm: pctFraudeCrm.value,
  qtdAcima400km: qtdAcima400km.value,
  totalSurtosCnpj: totalSurtosCnpj.value,
  diasComSurtosCnpj: diasComSurtosCnpj.value,
}));

// ── Filtros de KPI ────────────────────────────────────────────────────────
const kpiFilters = {
  top1:        (m) => m.id_medico === crmsInteresse.value[0]?.id_medico,
  top5:        (m) => crmsInteresse.value.slice(0, 5).some(t => t.id_medico === m.id_medico),
  agrupamento: (m) => !!m.alerta_concentracao_mesmo_crm,
  intensiva:   (m) => m.flag_robo > 0 || m.flag_robo_oculto > 0,
  exclusivo:   (m) => m.flag_crm_exclusivo > 0,
  fraude_crm:  (m) => m.flag_crm_invalido > 0 || m.flag_prescricao_antes_registro > 0,
  distancia:   (m) => !!m.alerta5_geografico,
  surtos_cnpj: (m) => m.flag_concentracao_estabelecimento > 0,
};

const kpiFilterLabels = {
  top1:        "Concentração TOP 1",
  top5:        "Concentração TOP 5",
  agrupamento: "CONCENTRAÇÃO MESMO CRM",
  intensiva:   ">30 Prescrições/Dia",
  exclusivo:   "CRM Exclusivo",
  fraude_crm:  "Fraudes CRM",
  distancia:   "Distância (>400km)",
  surtos_cnpj: "CONCENTRAÇÃO CRMs DIVERSOS",
};

function setKpiFilter(key) {
  activeKpiFilter.value = activeKpiFilter.value === key ? null : key;
}

function clearFilters() {
  activeKpiFilter.value = null;
}

defineExpose({
  getSummary: () => summary.value,
  getCrmsInteresse: () => crmsInteresse.value,
  getKpis: () => ({
    concentracaoTop1: concentracaoTop1.value,
    concentracaoTop5: concentracaoTop5.value,
    qtdLancamentosAgrupados: qtdLancamentosAgrupados.value,
    qtdPrescrIntensivaLocal: qtdPrescrIntensivaLocal.value,
    qtdPrescrIntensivaOcultos: qtdPrescrIntensivaOcultos.value,
    qtdCrmExclusivo: qtdCrmExclusivo.value,
    totalIrregularesCfm: totalIrregularesCfm.value,
    qtdCrmInvalido: qtdCrmInvalido.value,
    qtdPrescrAntesRegistro: qtdPrescrAntesRegistro.value,
    valorTop1: valorTop1.value,
    valorTop5: valorTop5.value,
    medianaTop5Reg: summary.value.mediana_concentracao_top5_reg ?? summary.value.mediana_concentracao_top5_br ?? 40,
    qtdAcima400km: qtdAcima400km.value,
    totalSurtosCnpj: totalSurtosCnpj.value,
    diasComSurtosCnpj: diasComSurtosCnpj.value,
  }),
});
</script>

<template>
  <div class="crm-tab-container">
    <div v-if="prescritoresLoading && !prescritoresData" class="loading-state">
      <i class="pi pi-spinner pi-spin"></i>
      <p>Carregando análise de prescritores...</p>
    </div>

    <div v-else-if="prescritoresError && !prescritoresData" class="loading-state tab-placeholder--error">
      <i class="pi pi-exclamation-circle" style="font-size: 2rem"></i>
      <p>{{ prescritoresError }}</p>
    </div>

    <div v-else-if="!prescritoresData || crmsInteresse.length === 0" class="empty-state">
      <i class="pi pi-users empty-icon"></i>
      <p>Não há dados de prescrições registrados para este estabelecimento nos meses selecionados.</p>
    </div>

    <div v-else class="content-wrapper" :class="{ 'is-refreshing': isRefreshing }">
      <!-- Seletor de Visão -->
      <div class="view-mode-container animate-fade-in">
        <div class="view-mode-selector">
          <button class="view-mode-btn" :class="{ active: activeCrmViewMode === 'medicos' }" @click="cnpjDetailStore.setCrmViewMode('medicos')">
            <i class="pi pi-users" />
            <span>PERFIL DE CRMs</span>
          </button>
          <button class="view-mode-btn" :class="{ active: activeCrmViewMode === 'cronologia' }" @click="cnpjDetailStore.setCrmViewMode('cronologia')">
            <i class="pi pi-chart-line" />
            <span>LINHA DO TEMPO & RAIO-X</span>
          </button>
        </div>
      </div>

      <!-- Visão: KPIs + Tabela de CRMs -->
      <template v-if="activeCrmViewMode === 'medicos'">
        <CRMKpiGrid
          :kpi-data="kpiData"
          :active-kpi-filter="activeKpiFilter"
          @kpi-click="setKpiFilter"
        />
        <CRMPrescritoresTable
          :crms-interesse="crmsInteresse"
          :active-kpi-filter="activeKpiFilter"
          :kpi-filters="kpiFilters"
          :kpi-filter-labels="kpiFilterLabels"
          :current-cnpj="cnpj"
          @clear-filters="clearFilters"
        />
      </template>

      <!-- Visão: Cronologia — v-show preserva estado do drill-down entre troca de abas -->
      <CRMCronologia v-show="activeCrmViewMode === 'cronologia'" :cnpj="cnpj" />
    </div>
  </div>
</template>

<style scoped>
.crm-tab-container {
  display: flex;
  flex-direction: column;
  gap: 1.5rem;
}

.loading-state,
.empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 4rem 1rem;
  color: var(--text-muted);
  background: var(--surface-bg);
  border-radius: 12px;
  border: 1px dashed var(--border-color);
}

.loading-state i { font-size: 2rem; margin-bottom: 1rem; color: var(--primary-color); }
.empty-icon { font-size: 3rem; margin-bottom: 1rem; opacity: 0.5; }

.content-wrapper {
  display: flex;
  flex-direction: column;
  gap: 1.25rem;
  width: 100%;
  align-items: stretch;
  transition: opacity 0.25s ease;
}
.content-wrapper.is-refreshing { opacity: 0.45; pointer-events: none; }

.animate-fade-in { animation: fadeIn 0.3s ease-out; }
@keyframes fadeIn { from { opacity: 0; transform: translateY(10px); } to { opacity: 1; transform: translateY(0); } }

.view-mode-container { display: flex; flex-direction: column; align-items: center; margin: 0.5rem 0 1.5rem; padding: 0 1rem; }
.view-mode-selector {
  display: flex;
  background: color-mix(in srgb, var(--card-bg) 40%, transparent);
  backdrop-filter: blur(8px);
  -webkit-backdrop-filter: blur(8px);
  border: 1px solid color-mix(in srgb, white 5%, transparent);
  padding: 4px;
  border-radius: 12px;
  box-shadow: 0 2px 10px rgba(0,0,0,0.1);
  gap: 4px;
}
.view-mode-btn {
  display: flex;
  align-items: center;
  gap: 0.6rem;
  padding: 0.55rem 1.4rem;
  border: none;
  background: transparent;
  color: var(--text-secondary);
  font-size: 0.75rem;
  font-weight: 600;
  border-radius: 9px;
  cursor: pointer;
  transition: all 0.2s ease;
  letter-spacing: 0.02em;
}
.view-mode-btn i { font-size: 1rem; opacity: 0.6; }
.view-mode-btn:hover { color: var(--text-color); background: color-mix(in srgb, var(--text-color) 5%, transparent); }
.view-mode-btn.active { background: color-mix(in srgb, var(--primary-color) 10%, transparent); color: var(--primary-color); }
:global(.dark-mode) .view-mode-btn.active { background: color-mix(in srgb, var(--primary-color) 12%, transparent); color: white; box-shadow: none; }
.view-mode-btn.active i { opacity: 1; }
</style>
