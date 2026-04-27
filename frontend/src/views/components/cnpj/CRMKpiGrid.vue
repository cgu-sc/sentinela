<script setup>
import { useFormatting } from "@/composables/useFormatting";

const props = defineProps({
  kpiData: { type: Object, required: true },
  activeKpiFilter: { type: String, default: null },
});

const emit = defineEmits(['kpi-click']);

const { formatCurrencyFull } = useFormatting();
const formatPct = (val) => val != null ? `${Number(val).toFixed(2)}%` : "0.00%";
</script>

<template>
  <div class="alerts-kpi-grid animate-fade-in">
    <!-- Concentração TOP 1 -->
    <div
      class="alert-kpi-card"
      :class="[
        kpiData.concentracaoTop1 > 40 ? 'highlight-red' : kpiData.concentracaoTop1 > 20 ? 'highlight-orange' : '',
        activeKpiFilter === 'top1' ? 'kpi-active' : '',
      ]"
      @click="emit('kpi-click', 'top1')"
    >
      <div class="alert-kpi-header">
        <span class="alert-kpi-label">TOP 1 CRM - VOLUME R$</span>
        <i class="pi pi-info-circle kpi-info-icon" v-tooltip.top="'Percentual de participação do maior prescritor no volume total da farmácia.'" />
      </div>
      <div class="alert-kpi-body">
        <span class="alert-kpi-val">{{ formatPct(kpiData.concentracaoTop1) }}</span>
        <span class="alert-kpi-hint">
          CRM: {{ kpiData.idTop1Prescritor || 'ND' }}
          <strong style="color: var(--text-color)"> · {{ formatCurrencyFull(kpiData.valorTop1) }}</strong>
        </span>
      </div>
    </div>

    <!-- Concentração TOP 5 -->
    <div
      class="alert-kpi-card"
      :class="[
        kpiData.concentracaoTop5 > 70 ? 'highlight-red' : kpiData.concentracaoTop5 > 50 ? 'highlight-orange' : '',
        activeKpiFilter === 'top5' ? 'kpi-active' : '',
      ]"
      @click="emit('kpi-click', 'top5')"
    >
      <div class="alert-kpi-header">
        <span class="alert-kpi-label">TOP 5 CRMs - VOLUME R$</span>
        <i class="pi pi-info-circle kpi-info-icon" v-tooltip.top="'Percentual de participação dos 5 maiores prescritores acumulados.'" />
      </div>
      <div class="alert-kpi-body">
        <span class="alert-kpi-val">{{ formatPct(kpiData.concentracaoTop5) }}</span>
        <span class="alert-kpi-hint">
          Mediana Região: {{ formatPct(kpiData.medianaTop5Reg) }}
          <strong style="color: var(--text-color)"> · {{ formatCurrencyFull(kpiData.valorTop5) }}</strong>
        </span>
      </div>
    </div>

    <!-- Agrupamento de Lançamentos -->
    <div
      class="alert-kpi-card"
      :class="[
        kpiData.qtdLancamentosAgrupados > 0 ? 'highlight-violet' : 'kpi-disabled',
        activeKpiFilter === 'agrupamento' ? 'kpi-active' : '',
      ]"
      @click="emit('kpi-click', 'agrupamento')"
    >
      <div class="alert-kpi-header">
        <span class="alert-kpi-label">CONCENTRAÇÃO CRM ÚNICO</span>
        <i class="pi pi-info-circle kpi-info-icon" v-tooltip.top="'Médicos que emitiram todas as suas prescrições em um curtíssimo espaço de tempo.'" />
      </div>
      <div class="alert-kpi-body">
        <span class="alert-kpi-val">{{ kpiData.qtdLancamentosAgrupados }}</span>
        <span class="alert-kpi-hint">Muitas Autorizações em Intervalo Curto</span>
      </div>
    </div>

    <!-- Prescrição Intensiva -->
    <div
      class="alert-kpi-card"
      :class="[
        kpiData.qtdPrescrIntensivaTotal > 0 ? 'highlight-red' : 'kpi-disabled',
        activeKpiFilter === 'intensiva' ? 'kpi-active' : '',
      ]"
      @click="emit('kpi-click', 'intensiva')"
    >
      <div class="alert-kpi-header">
        <span class="alert-kpi-label">>30 PRESCRIÇÕES/DIA</span>
        <i class="pi pi-info-circle kpi-info-icon" v-tooltip.top="'Médicos que emitiram mais de 30 prescrições por dia (comportamento de robô), calculado localmente e em todo o Brasil.'" />
      </div>
      <div class="alert-kpi-body">
        <span class="alert-kpi-val">{{ kpiData.qtdPrescrIntensivaTotal }}</span>
        <span class="alert-kpi-hint">
          {{ kpiData.qtdPrescrIntensivaLocal }} local · {{ kpiData.qtdPrescrIntensivaOcultos }} Brasil
        </span>
      </div>
    </div>

    <!-- CRMs Exclusivos -->
    <div
      class="alert-kpi-card"
      :class="[
        kpiData.qtdCrmExclusivo > 0 ? 'highlight-purple' : 'kpi-disabled',
        activeKpiFilter === 'exclusivo' ? 'kpi-active' : '',
      ]"
      @click="emit('kpi-click', 'exclusivo')"
    >
      <div class="alert-kpi-header">
        <span class="alert-kpi-label">CRMs EXCLUSIVOS</span>
        <i class="pi pi-info-circle kpi-info-icon" v-tooltip.top="'Médicos de gaveta: prescrevem exclusivamente para este estabelecimento em todo o Brasil.'" />
      </div>
      <div class="alert-kpi-body">
        <span class="alert-kpi-val">{{ kpiData.qtdCrmExclusivo }}</span>
        <span class="alert-kpi-hint">100% de exclusividade local</span>
      </div>
    </div>

    <!-- Fraudes CRM -->
    <div
      class="alert-kpi-card"
      :class="[
        kpiData.totalIrregularesCfm > 0 ? 'highlight-red highlight-fraude' : 'kpi-disabled',
        activeKpiFilter === 'fraude_crm' ? 'kpi-active' : '',
      ]"
      @click="emit('kpi-click', 'fraude_crm')"
    >
      <div class="alert-kpi-header">
        <span class="alert-kpi-label">FRAUDES CRM</span>
        <i class="pi pi-info-circle kpi-info-icon" v-tooltip.top="'Fonte: CFM. CRMs inexistentes ou vendas antes do registro oficial.'" />
      </div>
      <div class="alert-kpi-body">
        <div class="alert-kpi-val-row">
          <span class="alert-kpi-val">{{ kpiData.totalIrregularesCfm }}</span>
          <span class="alert-kpi-val-sub">{{ kpiData.qtdCrmInvalido }} Inexistentes | {{ kpiData.qtdPrescrAntesRegistro }} Irregulares</span>
        </div>
        <span class="alert-kpi-hint">
          <strong style="color: var(--risk-high)">
            {{ formatCurrencyFull(kpiData.valorFraudeCrm) }} ({{ formatPct(kpiData.pctFraudeCrm) }})
          </strong>
          da produção
        </span>
      </div>
    </div>

    <!-- Alerta >400km -->
    <div
      class="alert-kpi-card"
      :class="[
        kpiData.qtdAcima400km > 0 ? 'highlight-purple-geo' : 'kpi-disabled',
        activeKpiFilter === 'distancia' ? 'kpi-active' : '',
      ]"
      @click="emit('kpi-click', 'distancia')"
    >
      <div class="alert-kpi-header">
        <span class="alert-kpi-label">DISTÂNCIA (>400KM)</span>
        <i class="pi pi-info-circle kpi-info-icon" v-tooltip.top="'Médicos atuando em farmácias com mais de 400km de distância.'" />
      </div>
      <div class="alert-kpi-body">
        <span class="alert-kpi-val">{{ kpiData.qtdAcima400km }}</span>
        <span class="alert-kpi-hint">Prescrições em Locais Distantes</span>
      </div>
    </div>

    <!-- Surtos de Lançamento (Geral CNPJ) -->
    <div
      class="alert-kpi-card"
      :class="[
        kpiData.totalSurtosCnpj > 0 ? 'highlight-amber' : 'kpi-disabled',
        activeKpiFilter === 'surtos_cnpj' ? 'kpi-active' : '',
      ]"
      @click="emit('kpi-click', 'surtos_cnpj')"
    >
      <div class="alert-kpi-header">
        <span class="alert-kpi-label">CONCENTRAÇÃO CRMs MÚLTIPLOS</span>
        <i class="pi pi-info-circle kpi-info-icon" v-tooltip.top="'Identifica se a farmácia registrou volume atípico de dispensações concentrado em poucas horas.'" />
      </div>
      <div class="alert-kpi-body">
        <span class="alert-kpi-val">{{ kpiData.totalSurtosCnpj }}</span>
        <span class="alert-kpi-hint">Registros em {{ kpiData.diasComSurtosCnpj }} dias distintos</span>
      </div>
    </div>
  </div>
</template>

<style scoped>
.animate-fade-in {
  animation: fadeIn 0.3s ease-out;
}
@keyframes fadeIn {
  from { opacity: 0; transform: translateY(10px); }
  to { opacity: 1; transform: translateY(0); }
}

.alerts-kpi-grid {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 1rem;
  margin-bottom: 0;
}

.alert-kpi-card {
  padding: 0.9rem 1.1rem;
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  border-left: 4px solid var(--card-border);
  border-radius: 12px;
  transition: all 0.2s ease;
  cursor: pointer;
  user-select: none;
}

.alert-kpi-card:hover {
  transform: translateY(-2px);
  box-shadow: 0 4px 15px rgba(0, 0, 0, 0.08);
}

.alert-kpi-card.highlight-red:hover {
  border-color: color-mix(in srgb, var(--risk-high) 45%, var(--card-border));
  box-shadow: 0 8px 16px -8px color-mix(in srgb, var(--risk-high) 20%, transparent);
}
.alert-kpi-card.highlight-orange:hover {
  border-color: color-mix(in srgb, var(--risk-medium) 45%, var(--card-border));
  box-shadow: 0 8px 16px -8px color-mix(in srgb, var(--risk-medium) 20%, transparent);
}
.alert-kpi-card.highlight-violet:hover {
  border-color: color-mix(in srgb, #818cf8 45%, var(--card-border));
  box-shadow: 0 8px 16px -8px color-mix(in srgb, #818cf8 20%, transparent);
}
.alert-kpi-card.highlight-purple:hover {
  border-color: color-mix(in srgb, #3b82f6 45%, var(--card-border));
  box-shadow: 0 8px 16px -8px color-mix(in srgb, #3b82f6 20%, transparent);
}
.alert-kpi-card.highlight-amber:hover {
  border-color: color-mix(in srgb, #f59e0b 45%, var(--card-border));
  box-shadow: 0 8px 16px -8px color-mix(in srgb, #f59e0b 20%, transparent);
}
.alert-kpi-card.highlight-purple-geo:hover {
  border-color: color-mix(in srgb, #8b5cf6 45%, var(--card-border));
  box-shadow: 0 8px 16px -8px color-mix(in srgb, #8b5cf6 20%, transparent);
}

.alert-kpi-card.kpi-disabled {
  cursor: default;
  pointer-events: none;
  opacity: 0.45;
}

.alert-kpi-card.kpi-active {
  transform: translateY(-3px) scale(1.01);
  z-index: 2;
  border-left-width: 6px !important;
}

.alert-kpi-card.highlight-red.kpi-active {
  background: color-mix(in srgb, var(--risk-high) 10%, var(--card-bg));
  border-color: var(--risk-high) !important;
  box-shadow: 0 0 25px -5px color-mix(in srgb, var(--risk-high) 60%, transparent), 0 10px 30px rgba(0, 0, 0, 0.2);
}
.alert-kpi-card.highlight-orange.kpi-active {
  background: color-mix(in srgb, var(--risk-medium) 10%, var(--card-bg));
  border-color: var(--risk-medium) !important;
  box-shadow: 0 0 25px -5px color-mix(in srgb, var(--risk-medium) 60%, transparent), 0 10px 30px rgba(0, 0, 0, 0.2);
}
.alert-kpi-card.highlight-violet.kpi-active {
  background: color-mix(in srgb, #818cf8 10%, var(--card-bg));
  border-color: #818cf8 !important;
  box-shadow: 0 0 25px -5px color-mix(in srgb, #818cf8 60%, transparent), 0 10px 30px rgba(0, 0, 0, 0.2);
}
.alert-kpi-card.highlight-purple.kpi-active {
  background: color-mix(in srgb, #3b82f6 10%, var(--card-bg));
  border-color: #3b82f6 !important;
  box-shadow: 0 0 25px -5px color-mix(in srgb, #3b82f6 60%, transparent), 0 10px 30px rgba(0, 0, 0, 0.2);
}
.alert-kpi-card.highlight-amber.kpi-active {
  background: color-mix(in srgb, #f59e0b 10%, var(--card-bg));
  border-color: #f59e0b !important;
  box-shadow: 0 0 25px -5px color-mix(in srgb, #f59e0b 60%, transparent), 0 10px 30px rgba(0, 0, 0, 0.2);
}
.alert-kpi-card.highlight-purple-geo.kpi-active {
  background: color-mix(in srgb, #8b5cf6 10%, var(--card-bg));
  border-color: #8b5cf6 !important;
  box-shadow: 0 0 25px -5px color-mix(in srgb, #8b5cf6 60%, transparent), 0 10px 30px rgba(0, 0, 0, 0.2);
}

.highlight-red {
  background: linear-gradient(to top, color-mix(in srgb, var(--risk-high) 15%, var(--card-bg)) 0%, var(--card-bg) 80%);
  border: 1px solid color-mix(in srgb, var(--risk-high) 15%, var(--card-border));
  border-left: 4px solid var(--risk-high) !important;
}
.highlight-orange {
  background: linear-gradient(to top, color-mix(in srgb, var(--risk-medium) 15%, var(--card-bg)) 0%, var(--card-bg) 80%);
  border: 1px solid color-mix(in srgb, var(--risk-medium) 15%, var(--card-border));
  border-left: 4px solid var(--risk-medium) !important;
}
.highlight-purple {
  background: linear-gradient(to top, color-mix(in srgb, #3b82f6 15%, var(--card-bg)) 0%, var(--card-bg) 80%);
  border: 1px solid color-mix(in srgb, #3b82f6 15%, var(--card-border));
  border-left: 4px solid #3b82f6 !important;
}
.highlight-purple-geo {
  background: linear-gradient(to top, color-mix(in srgb, #8b5cf6 15%, var(--card-bg)) 0%, var(--card-bg) 80%);
  border: 1px solid color-mix(in srgb, #8b5cf6 15%, var(--card-border));
  border-left: 4px solid #8b5cf6 !important;
}
.highlight-amber {
  background: linear-gradient(to top, color-mix(in srgb, #f59e0b 15%, var(--card-bg)) 0%, var(--card-bg) 80%);
  border: 1px solid color-mix(in srgb, #f59e0b 15%, var(--card-border));
  border-left: 4px solid #f59e0b !important;
}
.highlight-violet {
  background: linear-gradient(to top, color-mix(in srgb, #818cf8 15%, var(--card-bg)) 0%, var(--card-bg) 80%);
  border: 1px solid color-mix(in srgb, #818cf8 15%, var(--card-border));
  border-left: 4px solid #818cf8 !important;
}

.alert-kpi-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
}
.alert-kpi-label {
  font-size: 0.7rem;
  font-weight: 600;
  color: var(--text-secondary);
  text-transform: uppercase;
  letter-spacing: 0.05em;
  opacity: 0.85;
}
.kpi-info-icon {
  font-size: 0.8rem;
  color: var(--text-muted);
  cursor: help;
  transition: color 0.15s;
}
.kpi-info-icon:hover { color: var(--primary-color); }

.alert-kpi-body {
  display: flex;
  flex-direction: column;
  gap: 0.2rem;
}
.alert-kpi-val-row {
  display: flex;
  align-items: baseline;
  gap: 0.5rem;
}
.alert-kpi-val {
  font-size: 1.15rem;
  font-weight: 600;
  color: var(--text-color);
  line-height: 1;
}
.alert-kpi-val-sub {
  font-size: 0.7rem;
  font-weight: 500;
  color: var(--text-color);
  opacity: 0.85;
}
.alert-kpi-hint {
  font-size: 0.72rem;
  color: var(--text-muted);
  font-weight: 400;
}
</style>
