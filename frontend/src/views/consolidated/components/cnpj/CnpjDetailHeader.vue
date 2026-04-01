<script setup>
import { useRouter } from "vue-router";
import { ref, computed, watchEffect } from "vue";

import { useRiskMetrics } from "@/composables/useRiskMetrics";
import { useFormatting } from "@/composables/useFormatting";
import Button from "primevue/button";

const router = useRouter();
const { getRiskLabel, getRiskClass, getRiskColor } = useRiskMetrics();
const { formatCurrencyFull, formatNumberFull } = useFormatting();

const props = defineProps({
  cnpj: { type: String, required: true },
  cnpjData: { type: Object, default: null },
  geoData: { type: Object, default: null },
});

// DEBUG: Identificando o campo correto do score
watchEffect(() => {
  if (props.cnpjData) {
    console.log(
      "DEBUG [CnpjDetailHeader]: Chaves disponíveis no objeto:",
      Object.keys(props.cnpjData),
    );
    console.log(
      "DEBUG [CnpjDetailHeader]: score_risco_final:",
      props.cnpjData.score_risco_final,
    );
    console.log(
      "DEBUG [CnpjDetailHeader]: classificacao_risco:",
      props.cnpjData.classificacao_risco,
    );
  }
});

const copied = ref(false);
const copyCnpj = () => {
  if (navigator.clipboard) {
    navigator.clipboard.writeText(props.cnpj);
    copied.value = true;
    setTimeout(() => {
      copied.value = false;
    }, 2000);
  }
};



const risco = computed(() => props.cnpjData?.percValSemComp ?? 0);

const formatRank = (rank) => {
  if (rank == null) return "—";
  return `${rank}º`;
};

const formatCnpj = (v) => {
  if (!v) return "—";
  const clean = v.replace(/\D/g, "");
  if (clean.length !== 14) return v;
  return clean.replace(
    /^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/,
    "$1.$2.$3/$4-$5",
  );
};
</script>

<template>
  <div class="detail-header-new shadow-sm">
    <!-- Linha superior: Navegação e Identidade Base -->
    <div class="header-top-bar">
      <Button
        icon="pi pi-arrow-left"
        text
        severity="secondary"
        class="back-btn-new"
        @click="router.back()"
        v-tooltip.right="'Voltar para a lista'"
      />

      <div class="identity-badges" v-if="cnpjData">
        <!-- Corrigido para score_risco_final conforme Matriz Consolidada -->
        <div
          v-if="cnpjData.score_risco_final != null"
          class="score-badge-new"
          :class="[
            getRiskClass(risco) === 'risk-critical'
              ? 'risk-high'
              : getRiskClass(risco),
          ]"
          v-tooltip.top="'Score de Risco Consolidado'"
        >
          <span class="score-label" style="color: inherit; opacity: 0.75"
            >Score</span
          >
          <span class="score-val" style="color: inherit">
            {{ cnpjData.score_risco_final.toFixed(1) }}
          </span>
        </div>

        <span
          v-if="cnpjData.classificacao_risco"
          class="risk-tag-new"
          :class="[
            getRiskClass(risco) === 'risk-critical'
              ? 'risk-high'
              : getRiskClass(risco),
          ]"
        >
          <i class="pi pi-exclamation-triangle" />
          {{ cnpjData.classificacao_risco }}
        </span>
      </div>
    </div>

    <!-- Área Central: Razão Social e Localização -->
    <div class="header-main-info" v-if="cnpjData">
      <div class="title-group">
        <h1 class="razao-social-new">
          {{ cnpjData.razao_social ?? "—" }}
        </h1>
        <div class="location-chips">
          <div class="loc-chip static">
            <i class="pi pi-map-marker" />
            {{ geoData?.no_municipio ?? cnpjData.municipio }}
          </div>
          <div class="loc-chip static">
            {{ geoData?.sg_uf ?? cnpjData.uf }}
          </div>
          <div class="loc-chip static highlight">
            <i class="pi pi-share-alt" />
            Região: {{ geoData?.no_regiao_saude ?? "Não Identificada" }}
          </div>

          <div
            class="cnpj-copy-wrap-new"
            v-tooltip.bottom="'Copiar CNPJ'"
            @click="copyCnpj"
          >
            <span class="cnpj-text">{{ formatCnpj(props.cnpj) }}</span>
            <i :class="['pi', copied ? 'pi-check text-green-400' : 'pi-copy']" />
          </div>
        </div>
      </div>

      <div class="header-kpis-new">
        <div class="kpi-item-new">
          <span class="label">% Valor sem Comprovação</span>
          <span
            class="value"
            :class="[getRiskClass(risco) === 'risk-critical' ? 'risk-high' : getRiskClass(risco)]"
          >
            {{ cnpjData.percValSemComp?.toFixed(2) }}%
          </span>
        </div>
        <div class="kpi-divider"></div>
        <div class="kpi-item-new">
          <span class="label">Valor sem Comprovação</span>
          <span class="value">{{ formatCurrencyFull(cnpjData.valSemComp) }}</span>
        </div>
        <div class="kpi-divider"></div>
        <div class="kpi-item-new">
          <span class="label">Total Vendas</span>
          <span class="value">{{ formatCurrencyFull(cnpjData.totalMov) }}</span>
        </div>
      </div>
    </div>

    <!-- Painel de Rankings e Estatísticas -->
    <div class="header-ranking-panel" v-if="cnpjData">
      <div class="ranking-grid-new">
        <div class="rank-stat">
          <i class="pi pi-globe gold" />
          <div class="rank-details">
            <span class="rank-label">Rank Nacional</span>
            <span class="rank-val">{{ formatRank(cnpjData.rank_nacional) }} <small>/ {{ cnpjData.total_nacional }}</small></span>
          </div>
        </div>
        <div class="rank-stat">
          <i class="pi pi-map silver" />
          <div class="rank-details">
            <span class="rank-label">Rank Estadual</span>
            <span class="rank-val">{{ formatRank(cnpjData.rank_uf) }} <small>/ {{ cnpjData.total_uf }}</small></span>
          </div>
        </div>
        <div class="rank-stat active">
          <i class="pi pi-share-alt bronze" />
          <div class="rank-details">
            <span class="rank-label">Rank Regional</span>
            <span class="rank-val">{{ formatRank(cnpjData.rank_regiao_saude) }} <small>/ {{ cnpjData.total_regiao_saude }}</small></span>
          </div>
        </div>
        <div class="rank-stat">
          <i class="pi pi-building neutral" />
          <div class="rank-details">
            <span class="rank-label">Rank Municipal</span>
            <span class="rank-val">{{ formatRank(cnpjData.rank_municipio) }} <small>/ {{ cnpjData.total_municipio }}</small></span>
          </div>
        </div>
        <div class="rank-stat" v-if="cnpjData.total_regiao_saude">
          <i class="pi pi-users-group" style="color: var(--text-muted); opacity: 0.8;" />
          <div class="rank-details">
            <span class="rank-label">Estabelecimentos</span>
            <span class="rank-val">{{ cnpjData.total_regiao_saude }}</span>
          </div>
        </div>
      </div>
    </div>

    <div class="header-loading" v-else>
      <i class="pi pi-spin pi-spinner" /> Carregando perfil do
      estabelecimento...
    </div>
  </div>
</template>

<style scoped>
/* ── CABEÇALHO RESUMO (SOLTO) ────────────────── */
.detail-header-new {
  background: var(--card-bg);
  padding: 1.25rem 2rem;
  border: 1px solid var(--sidebar-border);
  border-radius: 12px;
  display: flex;
  flex-direction: column;
  gap: 1rem;
  flex-shrink: 0;
  box-shadow: 0 4px 20px rgba(0, 0, 0, 0.1);
  z-index: 10;
  position: relative;
  overflow: hidden;
}

.detail-header-new::after {
  content: '';
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  height: 2px;
  background: linear-gradient(90deg, var(--primary-color), transparent);
  opacity: 0.3;
}

.header-top-bar {
  display: flex;
  align-items: center;
  gap: 1.5rem;
}

.back-btn-new {
  width: 36px !important;
  height: 36px !important;
}

.identity-badges {
  display: flex;
  align-items: center;
  gap: 1.25rem;
}

.score-badge-new {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.3rem 0.75rem;
  background: rgba(255, 255, 255, 0.03);
  border: 1px solid rgba(255, 255, 255, 0.1);
  border-radius: 12px;
}

.score-label {
  font-size: 0.6rem;
  font-weight: 800;
  text-transform: uppercase;
  color: var(--text-muted);
  letter-spacing: 0.05em;
}

.score-val {
  font-size: 0.9rem;
  font-weight: 800;
  color: var(--primary-color);
}

.cnpj-copy-wrap-new {
  background: rgba(255, 255, 255, 0.04);
  padding: 0.2rem 0.6rem;
  border-radius: 6px;
  cursor: pointer;
  display: flex;
  align-items: center;
  gap: 0.5rem;
  transition: all 0.2s;
  border: 1px solid rgba(255, 255, 255, 0.08);
}

.cnpj-copy-wrap-new:hover {
  background: rgba(255, 255, 255, 0.08);
  border-color: rgba(255, 255, 255, 0.15);
}

.cnpj-text {
  font-family: 'Inter', sans-serif;
  font-size: 0.75rem;
  font-weight: 700;
  color: var(--text-muted);
}

.cnpj-copy-wrap-new i {
  font-size: 0.7rem;
  opacity: 0.7;
}

.risk-tag-new {
  display: inline-flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.35rem 1rem;
  border-radius: 20px;
  font-size: 0.75rem;
  font-weight: 800;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.05);
}

.header-main-info {
  display: flex;
  justify-content: space-between;
  align-items: flex-end;
  gap: 2rem;
}

.title-group {
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
  min-width: 0;
}

.razao-social-new {
  font-size: 1.4rem;
  font-weight: 800;
  margin: 0;
  line-height: 1.2;
  letter-spacing: -0.02em;
  color: var(--text-secondary);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.location-chips {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
}

.loc-chip {
  display: flex;
  align-items: center;
  gap: 0.35rem;
  padding: 0.2rem 0.6rem;
  background: color-mix(in srgb, var(--primary-color) 8%, transparent);
  border: 1px solid color-mix(in srgb, var(--primary-color) 15%, transparent);
  border-radius: 6px;
  font-size: 0.75rem;
  font-weight: 600;
  color: var(--text-secondary);
  cursor: pointer;
  transition: all 0.2s;
}

.loc-chip:hover {
  background: color-mix(in srgb, var(--primary-color) 15%, transparent);
  border-color: var(--primary-color);
}

.loc-chip.highlight {
  background: color-mix(in srgb, var(--risk-low) 10%, transparent);
  border-color: color-mix(in srgb, var(--risk-low) 20%, transparent);
}

.loc-chip.static {
  cursor: default;
  opacity: 0.8;
}

.loc-chip.muted {
  background: transparent;
  border: 1px dashed var(--sidebar-border);
  cursor: default;
}

.header-kpis-new {
  display: flex;
  align-items: center;
  gap: 2rem;
  background: rgba(255, 255, 255, 0.03);
  padding: 0.75rem 1.5rem;
  border-radius: 10px;
  border: 1px solid rgba(255, 255, 255, 0.05);
}

.kpi-divider {
  width: 1px;
  height: 20px;
  background: rgba(255, 255, 255, 0.1);
}

.kpi-item-new {
  display: flex;
  flex-direction: column;
}

.kpi-item-new .label {
  font-size: 0.7rem;
  font-weight: 700;
  text-transform: uppercase;
  color: var(--text-muted);
  letter-spacing: 0.05em;
}

.kpi-item-new .value {
  font-size: 1.2rem;
  font-weight: 800;
  color: var(--text-secondary);
  font-family: 'Inter', sans-serif;
  background: none !important;
  background-color: transparent !important;
  border: none !important;
  padding: 0 !important;
  box-shadow: none !important;
}

/* Garante que as classes de risco não tragam fundo para este componente */
.kpi-item-new .value.risk-high,
.kpi-item-new .value.risk-critical,
.kpi-item-new .value.risk-medium,
.kpi-item-new .value.risk-low {
  background: none !important;
  background-color: transparent !important;
  box-shadow: none !important;
  border: none !important;
}

/* ── RANKING PANEL ── */
.header-ranking-panel {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 2rem;
  padding-top: 1.25rem;
  border-top: 1px solid rgba(255, 255, 255, 0.08);
}

.ranking-grid-new {
  display: flex;
  gap: 3rem;
}

.rank-stat {
  display: flex;
  align-items: center;
  gap: 0.8rem;
  opacity: 0.7;
  transition: all 0.3s;
}

.rank-stat:hover {
  opacity: 1;
  transform: translateY(-1px);
}

.rank-stat.active {
  opacity: 1;
  position: relative;
}

.rank-stat i {
  font-size: 1.25rem;
}

.rank-details {
  display: flex;
  flex-direction: column;
}

.rank-label {
  font-size: 0.6rem;
  font-weight: 800;
  text-transform: uppercase;
  color: var(--text-muted);
  letter-spacing: 0.05em;
}

.rank-val {
  font-size: 1rem;
  font-weight: 800;
  color: var(--text-secondary);
}

.rank-val small {
  font-size: 0.75rem;
  font-weight: 500;
  opacity: 0.4;
}

.pi.gold { color: #ffd700; }
.pi.silver { color: #cbd5e1; }
.pi.bronze { color: #fbbf24; }
.pi.neutral { color: #94a3b8; }

.pi-users-group {
  color: var(--text-muted);
}
</style>
