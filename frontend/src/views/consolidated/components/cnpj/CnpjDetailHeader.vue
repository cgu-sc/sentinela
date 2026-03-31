<script setup>
import { useRouter } from "vue-router";
import { ref, computed, watchEffect } from "vue";
import { useFilterStore } from "@/stores/filters";
import { useRiskMetrics } from "@/composables/useRiskMetrics";
import { useFormatting } from "@/composables/useFormatting";
import Button from "primevue/button";

const router = useRouter();
const filtersStore = useFilterStore();
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
    console.log('DEBUG [CnpjDetailHeader]: Chaves disponíveis no objeto:', Object.keys(props.cnpjData));
    console.log('DEBUG [CnpjDetailHeader]: score_risco_final:', props.cnpjData.score_risco_final);
    console.log('DEBUG [CnpjDetailHeader]: classificacao_risco:', props.cnpjData.classificacao_risco);
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

function navigateWithFilter(type) {
  const geo = props.geoData;
  if (!geo) return;

  if (type === "municipio") {
    filtersStore.selectedUF = geo.sg_uf;
    filtersStore.selectedRegiaoSaude = geo.no_regiao_saude;
    filtersStore.selectedMunicipio = `${geo.no_municipio}|${geo.sg_uf}`;
  } else if (type === "uf") {
    filtersStore.selectedMunicipio = "Todos";
    filtersStore.selectedRegiaoSaude = "Todos";
    filtersStore.selectedUF = geo.sg_uf;
  } else if (type === "regiao") {
    filtersStore.selectedMunicipio = "Todos";
    filtersStore.selectedUF = geo.sg_uf;
    filtersStore.selectedRegiaoSaude = geo.no_regiao_saude;
  }

  router.push({ name: "Dashboard" });
}

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
        <div
          class="cnpj-copy-wrap-new"
          v-tooltip.top="'Copiar CNPJ'"
          @click="copyCnpj"
        >
          <span class="cnpj-text">{{ formatCnpj(props.cnpj) }}</span>
          <i :class="['pi', copied ? 'pi-check text-green-400' : 'pi-copy']" />
        </div>

        <!-- Corrigido para score_risco_final conforme Matriz Consolidada -->
        <div 
          v-if="cnpjData.score_risco_final != null" 
          class="score-badge-new" 
          :class="[getRiskClass(risco) === 'risk-critical' ? 'risk-high' : getRiskClass(risco)]"
          v-tooltip.top="'Score de Risco Consolidado'"
        >
          <span class="score-label" style="color: inherit; opacity: 0.75;">Score</span>
          <span class="score-val" style="color: inherit;">
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
        <h1
          class="razao-social-new"
          v-tooltip.bottom="cnpjData.razao_social"
        >
          {{ cnpjData.razao_social ?? "—" }}
        </h1>
        <div class="location-chips">
          <div
            class="loc-chip"
            @click="navigateWithFilter('municipio')"
            v-tooltip.bottom="
              'Filtrar por ' + (geoData?.no_municipio ?? cnpjData.municipio)
            "
          >
            <i class="pi pi-map-marker" />
            {{ geoData?.no_municipio ?? cnpjData.municipio }}
          </div>
          <div
            class="loc-chip"
            @click="navigateWithFilter('uf')"
            v-tooltip.bottom="'Filtrar por ' + (geoData?.sg_uf ?? cnpjData.uf)"
          >
            {{ geoData?.sg_uf ?? cnpjData.uf }}
          </div>
          <div
            class="loc-chip highlight"
            @click="navigateWithFilter('regiao')"
            v-tooltip.bottom="
              'Ver todos da ' + (geoData?.no_regiao_saude ?? 'esta região')
            "
          >
            <i class="pi pi-share-alt" />
            Região: {{ geoData?.no_regiao_saude ?? "Não Identificada" }}
          </div>
          <div class="loc-chip muted" v-if="geoData?.nu_populacao">
            <i class="pi pi-users" />
            {{ formatNumberFull(geoData.nu_populacao) }} hab.
          </div>
        </div>
      </div>

      <div class="header-kpis-new">
        <div class="kpi-item-new large">
          <span class="label">% Valor sem Comprovação</span>
          <span
            class="value"
            :class="[
              getRiskClass(risco) === 'risk-critical'
                ? 'risk-high'
                : getRiskClass(risco),
            ]"
          >
            {{ cnpjData.percValSemComp?.toFixed(2) }}%
          </span>
        </div>
        <div class="kpi-item-new">
          <span class="label">Valor sem Comprovação</span>
          <span class="value">{{
            formatCurrencyFull(cnpjData.valSemComp)
          }}</span>
        </div>
        <div class="kpi-item-new">
          <span class="label">Total Vendas</span>
          <span class="value">{{ formatCurrencyFull(cnpjData.totalMov) }}</span>
        </div>
      </div>
    </div>

    <!-- Painel de Rankings e Estatísticas -->
    <div class="header-ranking-panel" v-if="cnpjData">
      <div class="ranking-grid-new">
        <div class="rank-card-new">
          <div class="rank-icon-box gold"><i class="pi pi-globe" /></div>
          <div class="rank-info-new">
            <span class="rank-label">Rank Nacional</span>
            <span class="rank-val"
              >{{ formatRank(cnpjData.rank_nacional) }}
              <small>/ {{ cnpjData.total_nacional }}</small></span
            >
          </div>
        </div>
        <div class="rank-card-new">
          <div class="rank-icon-box silver"><i class="pi pi-map" /></div>
          <div class="rank-info-new">
            <span class="rank-label">Rank Estadual</span>
            <span class="rank-val"
              >{{ formatRank(cnpjData.rank_uf) }}
              <small>/ {{ cnpjData.total_uf }}</small></span
            >
          </div>
        </div>
        <div class="rank-card-new highlighted">
          <div class="rank-icon-box bronze"><i class="pi pi-share-alt" /></div>
          <div class="rank-info-new">
            <span class="rank-label">Rank Regional</span>
            <span class="rank-val"
              >{{ formatRank(cnpjData.rank_regiao_saude) }}
              <small>/ {{ cnpjData.total_regiao_saude }}</small></span
            >
          </div>
        </div>
        <div class="rank-card-new">
          <div class="rank-icon-box neutral"><i class="pi pi-building" /></div>
          <div class="rank-info-new">
            <span class="rank-label">Rank Municipal</span>
            <span class="rank-val"
              >{{ formatRank(cnpjData.rank_municipio) }}
              <small>/ {{ cnpjData.total_municipio }}</small></span
            >
          </div>
        </div>
      </div>

      <div class="regional-stats-new" v-if="cnpjData.total_regiao_saude">
        <i class="pi pi-info-circle" />
        <span
          >Esta região de saúde possui
          <strong>{{ cnpjData.total_regiao_saude }}</strong> estabelecimentos de
          saúde.</span
        >
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
  padding: 1.5rem 2rem;
  border: 1px solid var(--sidebar-border);
  border-radius: 12px;
  display: flex;
  flex-direction: column;
  gap: 1rem;
  flex-shrink: 0;
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
  z-index: 10;
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
  padding: 0.2rem 0.6rem;
  background: rgba(255,255,255,0.04);
  border: 1px solid var(--sidebar-border);
  border-radius: 6px;
}

.score-label {
  font-size: 0.62rem;
  font-weight: 700;
  text-transform: uppercase;
  color: var(--text-muted);
  letter-spacing: 0.05em;
}

.score-val {
  font-size: 0.85rem;
  font-weight: 800;
  color: var(--primary-color);
  font-family: 'Inter', sans-serif;
}

.cnpj-copy-wrap-new {
  background: color-mix(in srgb, var(--sidebar-border) 40%, transparent);
  padding: 0.25rem 0.75rem;
  border-radius: 6px;
  cursor: pointer;
  display: flex;
  align-items: center;
  gap: 0.5rem;
  transition: all 0.2s;
}

.cnpj-copy-wrap-new:hover {
  background: color-mix(in srgb, var(--sidebar-border) 70%, transparent);
}

.cnpj-text {
  font-family: monospace;
  font-size: 0.85rem;
  font-weight: 700;
  letter-spacing: 0.05em;
  color: var(--text-secondary);
}

.risk-tag-new {
  display: inline-flex;
  align-items: center;
  gap: 0.4rem;
  padding: 0.25rem 0.75rem;
  border-radius: 6px;
  font-size: 0.7rem;
  font-weight: 800;
  text-transform: uppercase;
  letter-spacing: 0.05em;
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
  font-size: 1.4rem; /* Leve redução para um look mais compacto */
  font-weight: 800;
  margin: 0;
  line-height: 1.1;
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

.loc-chip.muted {
  background: transparent;
  border: 1px dashed var(--sidebar-border);
  cursor: default;
}

.header-kpis-new {
  display: flex;
  gap: 2rem;
}

.kpi-item-new {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
}

.kpi-item-new .label {
  font-size: 0.65rem;
  font-weight: 700;
  text-transform: uppercase;
  color: var(--text-muted);
  letter-spacing: 0.05em;
}

.kpi-item-new .value {
  font-size: 1.25rem;
  font-weight: 700;
  color: var(--text-color);
}

.kpi-item-new.large .value {
  font-size: 1.75rem;
  letter-spacing: -0.02em;
}

/* ── RANKING PANEL ── */
.header-ranking-panel {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 1.5rem;
  padding-top: 1rem;
  border-top: 1px solid var(--sidebar-border);
}

.ranking-grid-new {
  display: flex;
  gap: 1rem;
}

.rank-card-new {
  background: color-mix(in srgb, var(--card-bg) 60%, var(--sidebar-border));
  border: 1px solid var(--sidebar-border);
  padding: 0.5rem 0.75rem;
  border-radius: 10px;
  display: flex;
  align-items: center;
  gap: 0.75rem;
  min-width: 160px;
  backdrop-filter: blur(8px);
}

.rank-card-new.highlighted {
  border-color: color-mix(in srgb, var(--primary-color) 30%, transparent);
  background: color-mix(in srgb, var(--primary-color) 5%, var(--card-bg));
  box-shadow: 0 4px 12px rgba(var(--primary-color-rgb), 0.1);
}

.rank-icon-box {
  width: 32px;
  height: 32px;
  border-radius: 8px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 1rem;
}

.rank-icon-box.gold {
  background: rgba(255, 215, 0, 0.15);
  color: #ffd700;
}
.rank-icon-box.silver {
  background: rgba(192, 192, 192, 0.15);
  color: #c0c0c0;
}
.rank-icon-box.bronze {
  background: rgba(205, 127, 50, 0.15);
  color: #cd7f32;
}
.rank-icon-box.neutral {
  background: rgba(148, 163, 184, 0.15);
  color: #94a3b8;
}

.rank-info-new {
  display: flex;
  flex-direction: column;
}

.rank-label {
  font-size: 0.62rem;
  font-weight: 700;
  text-transform: uppercase;
  color: var(--text-muted);
  letter-spacing: 0.04em;
}

.rank-val {
  font-size: 1.1rem;
  font-weight: 800;
  color: var(--text-color);
}

.rank-val small {
  font-size: 0.75rem;
  font-weight: 500;
  opacity: 0.5;
}

.regional-stats-new {
  display: flex;
  align-items: center;
  gap: 0.6rem;
  font-size: 0.8rem;
  color: var(--text-secondary);
  background: color-mix(in srgb, var(--primary-color) 6%, transparent);
  padding: 0.5rem 1rem;
  border-radius: 8px;
}
</style>
