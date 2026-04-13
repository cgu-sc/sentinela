<script setup>
import { computed, ref, onMounted } from 'vue';
import { useConfigStore } from '@/stores/config';
import { useIndicadoresStore } from '@/stores/indicadores';
import { useFilterStore } from '@/stores/filters';
import { useGeoStore } from '@/stores/geo';
import { INDICATOR_GROUPS, INDICATOR_THRESHOLDS as SYSTEM_DEFAULTS } from '@/config/riskConfig';
import IndicadorDistribution from './components/indicadores/IndicadorDistribution.vue';
import Button from 'primevue/button';
import InputNumber from 'primevue/inputnumber';
import Dropdown from 'primevue/dropdown';

const configStore = useConfigStore();
const indicadoresStore = useIndicadoresStore();
const filterStore = useFilterStore();
const geoStore = useGeoStore();

// Seleção para o Simulador
const calibrationIndicator = ref('falecidos');
const selectedUf = ref('Todos');

/**
 * Verifica se um valor específico foi alterado em relação ao padrão do sistema
 */
function isModified(key, field) {
  const current = configStore.thresholds[key]?.[field];
  const original = SYSTEM_DEFAULTS[key]?.[field];
  return current !== original;
}

// Mapeamento plano para o dropdown de indicadores
const flatIndicators = computed(() => {
  return INDICATOR_GROUPS.flatMap(g => g.indicators.map(ind => ({
    label: ind.label,
    value: ind.key,
    thresholdKey: ind.thresholdKey
  })));
});

const calibrationMeta = computed(() => {
  return flatIndicators.value.find(i => i.value === calibrationIndicator.value);
});

// ── Inteligência Estatística (Modified Z-Score & Percentis) ──
const statisticalSuggestions = computed(() => {
  const risks = indicadoresStore.cnpjs
    .map(c => c.risco_reg)
    .filter(r => r != null && !isNaN(r))
    .sort((a, b) => a - b);

  if (!risks.length) return null;

  const total = risks.length;
  const median = 1.0; 
  let mad = indicadoresStore.kpis?.mad_reg || 0.0001;

  const getThresholdForM = (m) => {
    let t = median + (m * mad / 0.6745);
    if (t >= risks[total - 1] || isNaN(t) || t <= 1.1) {
      const p = m === 3.5 ? 0.95 : 0.85; 
      t = risks[Math.floor(total * p)] || t;
    }
    return Math.round(t * 100) / 100;
  };

  return {
    atencao: getThresholdForM(2.0),
    critico: getThresholdForM(3.5),
  };
});

/**
 * Aplica a sugestão matemática diretamente no store (Autosave ativa aqui)
 */
function applySuggestion() {
  if (!statisticalSuggestions.value || !calibrationMeta.value) return;
  const key = calibrationMeta.value.thresholdKey;
  
  configStore.thresholds[key].atencao = statisticalSuggestions.value.atencao;
  configStore.thresholds[key].critico = statisticalSuggestions.value.critico;
}

/**
 * Atualiza os dados de amostragem no simulador
 */
function refreshCalibration() {
  const params = {};
  if (selectedUf.value && selectedUf.value !== 'Todos') {
    params.uf = selectedUf.value;
  }
  indicadoresStore.fetchIndicadorAnalise(calibrationIndicator.value, params);
}

onMounted(() => {
  // Inicialização do simulador
  refreshCalibration();
});
</script>

<template>
  <div class="settings-container">
    <!-- Header Minimalista (Sem Botoes de Salvar) -->
    <header class="settings-header">
      <div class="header-content">
        <div class="brand">
          <i class="pi pi-cog brand-icon" />
          <div class="brand-text">
            <h1>Centro de Calibração Sentinela</h1>
            <span>Configurações globais persistidas automaticamente</span>
          </div>
        </div>
        <div class="autosave-status">
          <i class="pi pi-sync pi-spin" v-if="configStore.isLoading" />
          <i class="pi pi-cloud-upload" v-else />
          <span>Sincronizado</span>
        </div>
      </div>
    </header>

    <main v-if="Object.keys(configStore.thresholds).length > 0" class="settings-main">
      <div class="layout-grid">
        
        <!-- SEÇÃO 1: SIMULADOR DE IMPACTO ESPACIAL -->
        <section class="section-sim anim-fade-in">
          <div class="sim-card">
            <div class="sim-sidebar">
              <div class="sidebar-header">
                <i class="pi pi-sliders-h" />
                <span>Sandbox de Calibração</span>
              </div>

              <div class="control-item">
                <label>Filtro por UF</label>
                <Dropdown 
                  v-model="selectedUf" 
                  :options="geoStore.ufs" 
                  class="p-inputtext-sm w-full"
                  @change="refreshCalibration"
                />
              </div>
              
              <div class="control-item">
                <label>Analisar Indicador</label>
                <Dropdown 
                  v-model="calibrationIndicator" 
                  :options="flatIndicators" 
                  optionLabel="label" 
                  optionValue="value"
                  class="p-inputtext-sm w-full"
                  @change="refreshCalibration"
                />
              </div>

              <!-- Sugestão Estatística -->
              <div v-if="statisticalSuggestions" class="magic-box">
                <div class="magic-title">
                  <i class="pi pi-sparkles" />
                  <span>Sugestão MAD</span>
                </div>
                <div class="magic-metrics">
                  <div class="m-item">
                    <span class="l">Atenção</span>
                    <span class="v">{{ statisticalSuggestions.atencao }}x</span>
                  </div>
                  <div class="m-item">
                    <span class="l">Crítico</span>
                    <span class="v">{{ statisticalSuggestions.critico }}x</span>
                  </div>
                </div>
                <Button 
                  label="Aplicar Sugestão" 
                  icon="pi pi-magic" 
                  class="p-button-xs p-button-outlined w-full mt-3" 
                  @click="applySuggestion"
                />
              </div>

              <div class="sim-footer">
                <div class="footer-stat">
                  <i class="pi pi-database" />
                  <span>Amostra: {{ indicadoresStore.cnpjs.length }} cnpjs</span>
                </div>
              </div>
            </div>

            <div class="sim-body">
              <IndicadorDistribution 
                :cnpjs="indicadoresStore.cnpjs"
                :threshold-key="calibrationMeta?.thresholdKey"
                :is-loading="indicadoresStore.loading"
                :regional-median="indicadoresStore.kpis?.mediana_reg"
                :regional-mad="indicadoresStore.kpis?.mad_reg"
                :custom-thresholds="calibrationMeta ? configStore.thresholds[calibrationMeta.thresholdKey] : null"
              />
            </div>
          </div>
        </section>

        <!-- SEÇÃO 2: TABELA DE DEFINIÇÕES (DIRETO NO STORE) -->
        <section class="section-table anim-fade-in-up">
          <div class="grid-card">
            <div class="table-card-header">
              <div class="header-main">
                <div class="table-title">
                  <i class="pi pi-table" />
                  <span>Matriz de Limiares Globais</span>
                </div>
                <p class="table-desc">As alterações abaixo são aplicadas em tempo real em todas as visões do sistema.</p>
              </div>
              <Button 
                label="Resetar para Padrão" 
                icon="pi pi-refresh" 
                class="p-button-text p-button-secondary p-button-sm" 
                @click="configStore.resetToDefaults()"
              />
            </div>

            <table class="grid-table">
              <thead>
                <tr>
                  <th class="col-ind">Indicador Analítico</th>
                  <th class="col-val">Atenção (Mult.)</th>
                  <th class="col-val">Crítico (Mult.)</th>
                  <th class="col-ctx">Metodologia e Contexto</th>
                </tr>
              </thead>
              <tbody>
                <template v-for="group in INDICATOR_GROUPS" :key="group.label">
                  <tr class="group-sep">
                    <td colspan="4">{{ group.label }}</td>
                  </tr>
                  <tr v-for="ind in group.indicators" :key="ind.key" class="data-row">
                    <td>
                      <div class="ind-info">
                        <span class="label">{{ ind.label }}</span>
                      </div>
                    </td>
                    <td>
                      <div v-if="configStore.thresholds[ind.thresholdKey]" 
                           class="input-pill"
                           :class="{ 'is-modified': isModified(ind.thresholdKey, 'atencao') }">
                        <InputNumber 
                          v-model="configStore.thresholds[ind.thresholdKey].atencao" 
                          mode="decimal" 
                          :minFractionDigits="1" 
                          :maxFractionDigits="2"
                          class="grid-input"
                        />
                        <span class="xs-suffix">x</span>
                      </div>
                    </td>
                    <td>
                      <div v-if="configStore.thresholds[ind.thresholdKey]" 
                           class="input-pill highlight"
                           :class="{ 'is-modified': isModified(ind.thresholdKey, 'critico') }">
                        <InputNumber 
                          v-model="configStore.thresholds[ind.thresholdKey].critico" 
                          mode="decimal" 
                          :minFractionDigits="1" 
                          :maxFractionDigits="2"
                          class="grid-input"
                        />
                        <span class="xs-suffix">x</span>
                      </div>
                    </td>
                    <td>
                      <p class="ctx-text">{{ ind.metodologia }}</p>
                    </td>
                  </tr>
                </template>
              </tbody>
            </table>
          </div>
        </section>

      </div>
    </main>
  </div>
</template>

<style scoped>
.settings-container {
  min-height: 100vh;
  background: var(--bg-color); /* Fundo oficial definido no themeConfig.js */
  color: var(--text-color);
  padding-bottom: 4rem;
}

/* ── HEADER MINIMALISTA ── */
.settings-header {
  background: var(--card-bg);
  border-bottom: 1px solid var(--card-border);
  padding: 0.75rem 2rem;
  position: sticky;
  top: 0;
  z-index: 1000;
}

.header-content {
  width: 100%;
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.brand { display: flex; align-items: center; gap: 1rem; }
.brand-icon {
  font-size: 1.25rem;
  color: var(--primary-color);
  background: color-mix(in srgb, var(--primary-color) 10%, transparent);
  padding: 0.6rem;
  border-radius: 10px;
}
.brand-text h1 { margin: 0; font-size: 1.1rem; font-weight: 400; }
.brand-text span { font-size: 0.75rem; color: var(--text-muted); font-weight: 400; }

.autosave-status {
  display: flex;
  align-items: center;
  gap: 0.6rem;
  font-size: 0.7rem;
  color: var(--text-muted);
  background: var(--bg-color);
  padding: 0.4rem 0.8rem;
  border-radius: 20px;
  border: 1px solid var(--card-border);
}

.autosave-status i { color: var(--primary-color); }

/* ── MAIN LAYOUT ── */
.settings-main {
  width: 100%;
  margin: 1.5rem 0;
  padding: 0 2rem;
}

.layout-grid {
  display: flex;
  flex-direction: column;
  gap: 1.5rem;
}

/* ── SIMULADOR ── */
.sim-card {
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  border-radius: 12px;
  display: grid;
  grid-template-columns: 280px 1fr;
  overflow: hidden;
  box-shadow: 0 2px 10px rgba(0,0,0,0.02);
}

.sim-sidebar {
  padding: 1.25rem;
  background: var(--bg-color); /* Neutro */
  border-right: 1px solid var(--card-border);
  display: flex;
  flex-direction: column;
  gap: 1rem;
}

.sidebar-header {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  font-weight: 400;
  font-size: 0.85rem;
  color: var(--text-color);
}

.control-item label {
  display: block;
  font-size: 0.75rem;
  font-weight: 400;
  color: var(--text-muted);
  margin-bottom: 0.4rem;
}

.magic-box {
  background: var(--card-bg); /* Branco/Card puro */
  border: 1px solid var(--card-border);
  border-radius: 10px;
  padding: 0.85rem;
  box-shadow: inset 0 0 10px rgba(0,0,0,0.01);
}

.magic-title {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  font-size: 0.75rem;
  font-weight: 400;
  color: var(--text-muted); /* Neutro */
  margin-bottom: 0.75rem;
}

.magic-metrics { display: grid; grid-template-columns: 1fr 1fr; gap: 0.5rem; }
.m-item { display: flex; flex-direction: column; }
.m-item .l { font-size: 0.65rem; color: var(--text-muted); }
.m-item .v { font-size: 1rem; font-weight: 400; color: var(--text-color); }

.p-button-xs { padding: 0.3rem 0.6rem !important; font-size: 0.65rem !important; font-weight: 400 !important; }

.sim-footer { margin-top: auto; padding-top: 0.75rem; border-top: 1px solid var(--card-border); }
.footer-stat { display: flex; align-items: center; gap: 0.5rem; font-size: 0.65rem; color: var(--text-muted); }
.footer-stat i { color: var(--primary-color); }
.footer-stat strong { font-weight: 500; }

.sim-body { padding: 1rem; }

/* ── GRID TABLE CARD ── */
.table-card-header {
  padding: 0 0 1rem 0;
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.table-title {
  display: flex;
  align-items: center;
  gap: 0.6rem;
  font-weight: 400;
  font-size: 0.95rem;
  color: var(--text-color);
  margin-bottom: 0.25rem;
}
.table-title i { color: var(--primary-color); }
.table-desc { font-size: 0.75rem; color: var(--text-muted); margin: 0; }

.grid-card {
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  border-radius: 12px;
  overflow: hidden;
  padding: 1.5rem;
}

.grid-table { width: 100%; border-collapse: collapse; font-size: 0.9rem; }
.grid-table th {
  background: var(--bg-color);
  padding: 0.75rem 1rem;
  text-align: left;
  font-size: 0.75rem;
  color: var(--text-muted);
  font-weight: 400;
  border-bottom: 1px solid var(--card-border);
  text-transform: none !important;
}

.grid-table td { padding: 0.5rem 1rem; border-bottom: 1px solid var(--card-border); }

.group-sep td {
  background: var(--bg-color); /* Neutro absoluto igual ao fundo */
  color: var(--primary-color);
  font-weight: 400;
  font-size: 0.8rem;
  border-bottom: 2px solid var(--card-border);
  padding-top: 1.25rem !important; /* Espaçamento extra para respirar */
  text-transform: none !important;
}

.data-row:hover { background: color-mix(in srgb, var(--primary-color) 2%, transparent); }

.ind-info { display: flex; flex-direction: column; }
.ind-info .label { 
  font-weight: 400; 
  color: var(--text-color); 
  text-transform: none !important;
}
.ind-info .key { font-size: 0.6rem; color: var(--text-muted); font-family: monospace; }

.input-pill {
  display: flex;
  align-items: center;
  gap: 0.25rem;
  background: var(--bg-color); /* Neutro */
  border: 1px solid var(--card-border);
  padding: 1px 6px;
  border-radius: 6px;
  width: fit-content;
  position: relative;
  transition: all 0.2s ease;
}

.input-pill.is-modified {
  border-color: var(--primary-color);
  background: var(--card-bg); /* Neutro (destaque apenas na borda) */
}

.input-pill.is-modified::after {
  content: '';
  position: absolute;
  top: -2px;
  right: -2px;
  width: 5px;
  height: 5px;
  background: var(--primary-color);
  border-radius: 50%;
  border: 1px solid var(--card-bg);
}

.input-pill.highlight { border-color: color-mix(in srgb, var(--risk-indicator-critical, #ff5252) 30%, var(--card-border)); }

.input-pill.highlight.is-modified {
  border-color: var(--primary-color);
}

.grid-input :deep(.p-inputtext) {
  border: none !important;
  background: transparent !important;
  width: 48px !important;
  padding: 4px !important;
  font-weight: 400 !important;
  text-align: right !important;
  font-size: 0.85rem !important;
}

.xs-suffix { font-size: 0.7rem; font-weight: 400; color: var(--primary-color); opacity: 0.7; }

.ctx-text { 
  font-size: 0.95rem; 
  color: var(--text-muted); 
  margin: 0; 
  line-height: 1.5; 
  max-width: 600px; 
  font-weight: 400 !important;
  text-transform: none !important;
}

.col-val { width: 130px; }
.col-ind { width: 280px; }

/* ── ANIMATIONS ── */
.anim-fade-in { animation: fadeIn 0.4s ease-out; }
.anim-fade-in-up { animation: fadeInUp 0.5s ease-out; }

@keyframes fadeIn { from { opacity: 0; } to { opacity: 1; } }
@keyframes fadeInUp { from { opacity: 0; transform: translateY(10px); } to { opacity: 1; transform: translateY(0); } }
</style>
