<script setup>
import { useRouter } from "vue-router";
import { ref, computed, watchEffect } from "vue";

import { useRiskMetrics } from "@/composables/useRiskMetrics";
import { useFormatting } from "@/composables/useFormatting";
import { useCnpjNavStore } from "@/stores/cnpjNav";
import { useFarmaciaListsStore } from "@/stores/farmaciaLists";
import { useGeoStore } from "@/stores/geo";
import Button from "primevue/button";

const cnpjNav = useCnpjNavStore();
const farmaciaLists = useFarmaciaListsStore();
const geoStore = useGeoStore();

const qtdMunicipiosRegiao = computed(() =>
  geoStore.qtdMunicipiosPorRegiao(props.geoData?.no_regiao_saude),
);

const router = useRouter();
const { getRiskLabel, getRiskClass, getRiskColor } = useRiskMetrics();
const { formatCurrencyFull, formatNumberFull } = useFormatting();

const formatPopulacao = (n) => {
  if (n == null) return "—";
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(2).replace('.', ',')} M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1).replace('.', ',')} mil`;
  return n.toLocaleString("pt-BR");
};

const props = defineProps({
  cnpj: { type: String, required: true },
  cnpjData: { type: Object, default: null },
  geoData: { type: Object, default: null },
  isExporting: { type: Boolean, default: false },
});

const emit = defineEmits(['export']);

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

      <div class="list-actions" v-if="cnpjData">
        <button
          class="list-btn list-btn--export"
          @click="emit('export')"
          :disabled="isExporting"
          v-tooltip.bottom="'Exportar relatório PDF'"
        >
          <i :class="isExporting ? 'pi pi-spin pi-spinner' : 'pi pi-file-pdf'" />
          <span>{{ isExporting ? 'Gerando...' : 'Exportar PDF' }}</span>
        </button>
        <button
          class="list-btn"
          :class="farmaciaLists.isInteresse(cnpj) ? 'list-btn--interesse-active' : 'list-btn--interesse'"
          @click="farmaciaLists.toggleInteresse(cnpj, cnpjData.razao_social)"
          v-tooltip.bottom="farmaciaLists.isInteresse(cnpj) ? 'Remover da Lista de Interesse' : 'Adicionar à Lista de Interesse'"
        >
          <i :class="farmaciaLists.isInteresse(cnpj) ? 'pi pi-star-fill' : 'pi pi-star'" />
          <span>{{ farmaciaLists.isInteresse(cnpj) ? 'Interesse' : 'Interesse' }}</span>
        </button>
        <button
          class="list-btn"
          :class="farmaciaLists.isBlacklisted(cnpj) ? 'list-btn--black-active' : 'list-btn--black'"
          @click="farmaciaLists.toggleBlacklist(cnpj, cnpjData.razao_social)"
          v-tooltip.bottom="farmaciaLists.isBlacklisted(cnpj) ? 'Remover da Blacklist' : 'Adicionar à Blacklist'"
        >
          <i class="pi pi-ban" />
          <span>Blacklist</span>
        </button>
      </div>

    </div>

    <!-- Área Central: Razão Social e Localização -->
    <div class="header-main-info" v-if="cnpjData">
      <div class="title-group">
        <div class="razao-social-row">
          <h1 class="razao-social-new">
            {{ cnpjData.razao_social ?? "—" }}
          </h1>
          <div
            class="cnpj-copy-wrap-new"
            v-tooltip.bottom="'Copiar CNPJ'"
            @click="copyCnpj"
          >
            <span class="cnpj-text">{{ formatCnpj(props.cnpj) }}</span>
            <i :class="['pi', copied ? 'pi-check text-green-400' : 'pi-copy']" />
          </div>
        </div>
        <div class="location-chips">
          <span class="loc-text">
            <i class="pi pi-map-marker" />
            {{ geoData?.no_municipio ?? cnpjData.municipio }},
            {{ geoData?.sg_uf ?? cnpjData.uf }}
          </span>
          <span class="loc-separator">·</span>
          <span class="loc-text">Região de Saúde: {{ geoData?.no_regiao_saude ?? "Não Identificada" }}</span>
          <span class="loc-separator">·</span>

          <div
            v-if="cnpjData.score_risco_final != null"
            class="loc-chip risk-chip"
            :class="[getRiskClass(risco) === 'risk-critical' ? 'risk-high' : getRiskClass(risco)]"
            v-tooltip.bottom="'Score de Risco Consolidado'"
          >
            Score {{ cnpjData.score_risco_final.toFixed(1) }}
          </div>

          <div
            v-if="cnpjData.classificacao_risco"
            class="loc-chip risk-chip"
            :class="[getRiskClass(risco) === 'risk-critical' ? 'risk-high' : getRiskClass(risco)]"
          >
            {{ cnpjData.classificacao_risco }}
          </div>
        </div>
      </div>

      <div class="header-kpis-new">
        <div
          class="kpi-card"
          :class="[getRiskClass(risco) === 'risk-critical' ? 'risk-high' : getRiskClass(risco)]"
        >
          <span class="kpi-card-label">% Sem Comprovação</span>
          <span class="kpi-card-value">{{ cnpjData.percValSemComp?.toFixed(2) }}%</span>
        </div>
        <div class="kpi-card">
          <span class="kpi-card-label">Valor sem Comprovação</span>
          <span class="kpi-card-value">{{ formatCurrencyFull(cnpjData.valSemComp) }}</span>
        </div>
        <div class="kpi-card">
          <span class="kpi-card-label">Total Vendas</span>
          <span class="kpi-card-value">{{ formatCurrencyFull(cnpjData.totalMov) }}</span>
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
          <i class="pi pi-compass silver" />
          <div class="rank-details">
            <span class="rank-label">Rank Estadual</span>
            <span class="rank-val">{{ formatRank(cnpjData.rank_uf) }} <small>/ {{ cnpjData.total_uf }}</small></span>
          </div>
        </div>
        <div class="rank-stat">
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
        <div class="rank-stat" v-if="qtdMunicipiosRegiao">
          <i class="pi pi-map" style="color: #34d399;" />
          <div class="rank-details">
            <span class="rank-label">Municípios da Região</span>
            <span class="rank-val">{{ qtdMunicipiosRegiao }}</span>
          </div>
        </div>
        <div
          class="rank-stat rank-stat--clickable"
          v-if="cnpjData.total_regiao_saude"
          v-tooltip.top="'Ver ranking completo da Região de Saúde'"
          @click="cnpjNav.navigateToRegiao(null)"
        >
          <i class="pi pi-sitemap" style="color: var(--text-muted); opacity: 0.8;" />
          <div class="rank-details">
            <span class="rank-label">Estab. Região</span>
            <span class="rank-val">{{ cnpjData.total_regiao_saude }}</span>
          </div>
        </div>
        <div
          class="rank-stat rank-stat--clickable"
          v-if="cnpjData.total_municipio"
          v-tooltip.top="'Ver ranking do município na Região de Saúde'"
          @click="cnpjNav.navigateToRegiao(geoData?.no_municipio ?? cnpjData.municipio)"
        >
          <i class="pi pi-building" style="color: #a78bfa;" />
          <div class="rank-details">
            <span class="rank-label">Estab. Município</span>
            <span class="rank-val">{{ cnpjData.total_municipio }}</span>
          </div>
        </div>
        <div class="rank-stat" v-if="geoData?.nu_populacao">
          <i class="pi pi-users" style="color: #60a5fa;" />
          <div class="rank-details">
            <span class="rank-label">Pop. Município</span>
            <span class="rank-val">{{ formatPopulacao(geoData.nu_populacao) }}</span>
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
  background: var(--establishment-header-bg);
  padding: 1.25rem 2rem;
  border: 1px solid var(--establishment-header-border);
  border-radius: 12px;
  display: flex;
  flex-direction: column;
  gap: 1rem;
  flex-shrink: 0;
  box-shadow: none;
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

.list-actions {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  margin-left: auto;
}

.list-btn {
  display: inline-flex;
  align-items: center;
  gap: 0.4rem;
  padding: 0.3rem 0.8rem;
  font-size: 0.75rem;
  font-weight: 700;
  border-radius: 20px;
  border: 1px solid;
  cursor: pointer;
  transition: all 0.2s ease;
  text-transform: uppercase;
  letter-spacing: 0.04em;
}

.list-btn--export {
  color: #6366f1;
  border-color: rgba(99, 102, 241, 0.3);
  background: rgba(99, 102, 241, 0.08);
}
.list-btn--export:hover:not(:disabled) {
  background: rgba(99, 102, 241, 0.18);
  border-color: #6366f1;
}
.list-btn--export:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

.list-btn--interesse {
  color: #ca8a04;
  border-color: rgba(202, 138, 4, 0.3);
  background: rgba(202, 138, 4, 0.08);
}
.list-btn--interesse:hover {
  background: rgba(202, 138, 4, 0.18);
  border-color: #ca8a04;
}
.list-btn--interesse-active {
  color: #fff;
  border-color: #ca8a04;
  background: #ca8a04;
}
.list-btn--interesse-active:hover {
  background: #a16207;
  border-color: #a16207;
}

.list-btn--black {
  color: #ef4444;
  border-color: rgba(239, 68, 68, 0.3);
  background: rgba(239, 68, 68, 0.08);
}
.list-btn--black:hover {
  background: rgba(239, 68, 68, 0.18);
  border-color: #ef4444;
}
.list-btn--black-active {
  color: #fff;
  border-color: #dc2626;
  background: #dc2626;
}
.list-btn--black-active:hover {
  background: #b91c1c;
  border-color: #b91c1c;
}

.back-btn-new {
  width: 36px !important;
  height: 36px !important;
}

.risk-chip {
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  font-size: 0.72rem;
  cursor: default;
}

.risk-chip i {
  color: inherit;
}

.risk-chip.risk-high {
  color: var(--risk-high);
  border-color: color-mix(in srgb, var(--risk-high) 30%, transparent);
  background: color-mix(in srgb, var(--risk-high) 10%, transparent);
}

.risk-chip.risk-critical {
  color: var(--risk-critical);
  border-color: color-mix(in srgb, var(--risk-critical) 30%, transparent);
  background: color-mix(in srgb, var(--risk-critical) 10%, transparent);
}

.risk-chip.risk-medium {
  color: var(--risk-medium);
  border-color: color-mix(in srgb, var(--risk-medium) 30%, transparent);
  background: color-mix(in srgb, var(--risk-medium) 10%, transparent);
}

.risk-chip.risk-low {
  color: var(--risk-low);
  border-color: color-mix(in srgb, var(--risk-low) 30%, transparent);
  background: color-mix(in srgb, var(--risk-low) 10%, transparent);
}

.cnpj-copy-wrap-new {
  background: color-mix(in srgb, var(--primary-color) 8%, transparent);
  padding: 0.2rem 0.65rem;
  border-radius: 6px;
  cursor: pointer;
  display: flex;
  align-items: center;
  gap: 0.5rem;
  transition: all 0.2s ease-in-out;
  border: 1px solid color-mix(in srgb, var(--primary-color) 15%, transparent) !important;
}

.cnpj-copy-wrap-new:hover {
  background: color-mix(in srgb, var(--primary-color) 15%, transparent) !important;
  border-color: var(--primary-color) !important;
  transform: translateY(-1px);
}

.cnpj-text {
  font-family: 'Inter', sans-serif;
  font-size: 0.8rem;
  font-weight: 700;
  color: var(--text-secondary);
}

.cnpj-copy-wrap-new i {
  font-size: 0.7rem;
  color: var(--primary-color);
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

.razao-social-row {
  display: flex;
  align-items: center;
  gap: 0.75rem;
}

.razao-social-new {
  font-size: 1.4rem;
  font-weight: 700;
  margin: 0;
  line-height: 1.2;
  letter-spacing: -0.02em;
  color: var(--establishment-header-text);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.location-chips {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
}

.loc-text {
  display: inline-flex;
  align-items: center;
  gap: 0.3rem;
  font-size: 0.8rem;
  font-weight: 500;
  color: var(--text-color);
  opacity: 0.8;
}

.loc-text i {
  font-size: 0.75rem;
}

.loc-separator {
  color: var(--text-color);
  opacity: 0.4;
  font-size: 0.85rem;
}

/* mantido para os risk-chips que ainda usam loc-chip como base */
.loc-chip {
  display: inline-flex;
  align-items: center;
  gap: 0.35rem;
  padding: 0.2rem 0.65rem;
  border: 1px solid color-mix(in srgb, var(--primary-color) 15%, transparent);
  border-radius: 6px;
  font-size: 0.8rem;
  font-weight: 600;
  color: var(--text-secondary);
  cursor: default;
}

.header-kpis-new {
  display: flex;
  align-items: stretch;
  gap: 0.5rem;
}

.kpi-card {
  display: flex;
  flex-direction: column;
  justify-content: center;
  gap: 0.15rem;
  padding: 0.5rem 1rem;
  border-left: 3px solid rgba(255, 255, 255, 0.1);
  background: none;
}

.kpi-card-label {
  font-size: 0.65rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: var(--establishment-header-text);
  opacity: 0.5;
  white-space: nowrap;
}

.kpi-card-value {
  font-size: 1.1rem;
  font-weight: 700;
  color: var(--establishment-header-text);
  font-family: 'Inter', sans-serif;
  line-height: 1.2;
  white-space: nowrap;
}

.kpi-card.risk-high .kpi-card-value   { color: var(--risk-high); }
.kpi-card.risk-high                   { border-left-color: var(--risk-high); }
.kpi-card.risk-critical .kpi-card-value { color: var(--risk-critical); }
.kpi-card.risk-critical               { border-left-color: var(--risk-critical); }
.kpi-card.risk-medium .kpi-card-value  { color: var(--risk-medium); }
.kpi-card.risk-medium                  { border-left-color: var(--risk-medium); }
.kpi-card.risk-low .kpi-card-value     { color: var(--risk-low); }
.kpi-card.risk-low                     { border-left-color: var(--risk-low); }

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
  transition: all 0.3s;
}

.rank-stat--clickable {
  cursor: pointer;
  padding: 0.3rem 0.6rem;
  border-radius: 8px;
  margin: -0.3rem -0.6rem;
}

.rank-stat--clickable:hover {
  background: color-mix(in srgb, #a78bfa 10%, transparent);
  transform: translateY(-1px);
}

.nav-hint {
  font-size: 0.65rem;
  color: #a78bfa;
  opacity: 0;
  transition: opacity 0.2s ease;
}

.rank-stat--clickable:hover .nav-hint {
  opacity: 1;
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
  font-weight: 700;
  text-transform: uppercase;
  color: var(--establishment-header-text);
  opacity: 0.7;
  letter-spacing: 0.05em;
}

.rank-val {
  font-size: 1rem;
  font-weight: 700;
  color: var(--establishment-header-text);
}

.rank-val small {
  font-size: 0.75rem;
  font-weight: 500;
  opacity: 0.8;
}

.pi.gold { color: #ffd700; }
.pi.silver { color: #cbd5e1; }
.pi.bronze { color: #fbbf24; }
.pi.neutral { color: #94a3b8; }

.pi-users-group {
  color: var(--text-muted);
}
</style>
