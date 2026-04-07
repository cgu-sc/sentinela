<script setup>
import { ref, computed } from "vue";

import { useRiskMetrics } from "@/composables/useRiskMetrics";
import { useFormatting } from "@/composables/useFormatting";
import { useCnpjNavStore } from "@/stores/cnpjNav";
import { useFarmaciaListsStore } from "@/stores/farmaciaLists";
import { useGeoStore } from "@/stores/geo";


const cnpjNav = useCnpjNavStore();
const farmaciaLists = useFarmaciaListsStore();
const geoStore = useGeoStore();

const qtdMunicipiosRegiao = computed(() =>
  geoStore.qtdMunicipiosPorRegiao(props.geoData?.no_regiao_saude),
);

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
  cadastro: { type: Object, default: null },
  isExporting: { type: Boolean, default: false },
});

const emit = defineEmits(['export']);



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

const razaoSocialDisplay = computed(() => {
  const nome = props.cnpjData?.razao_social;
  if (!nome) return "—";
  return nome.length > 40 ? nome.slice(0, 40) + "..." : nome;
});
const razaoSocialTooltip = computed(() => {
  const nome = props.cnpjData?.razao_social;
  return nome && nome.length > 40 ? nome : null;
});

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

// ── Formatação Robusta de Endereço ────────────────────────
const formattedFullAddress = computed(() => {
  const c = props.cadastro;
  if (!c || !c.logradouro) return null;


  // 1. Parte Principal: Tipo + Logradouro + Número
  let main = [c.tipo_logradouro, c.logradouro].filter(Boolean).join(" ");
  if (c.numero && c.numero !== "None") main += `, ${c.numero}`;

  // 2. Complemento (se existir)
  if (c.complemento && c.complemento !== "None" && c.complemento !== "null") {
    main += ` - ${c.complemento}`;
  }

  // 3. Bairro e CEP
  const parts = [main];
  if (c.bairro && c.bairro !== "None") parts.push(c.bairro);
  if (c.cep && c.cep !== "None") parts.push(`CEP: ${c.cep}`);

  return parts.filter(Boolean).join(" · ");
});


</script>

<template>
  <div class="detail-header-new shadow-sm">
    <!-- Área Central: Razão Social e Localização -->
    <div class="header-main-info" v-if="cnpjData">
      <div class="title-group">
        <div class="razao-social-row">
          <h1
            class="razao-social-new"
            v-tooltip.bottom="razaoSocialTooltip"
          >
            {{ razaoSocialDisplay }}
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
        <!-- NOVO: Linha de Endereço e Geolocalização -->
        <div class="address-row-new" v-if="cadastro && formattedFullAddress">
          <span class="address-text">
            <i class="pi pi-home" />
            {{ formattedFullAddress }}
          </span>
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

      <div class="header-right-col">
        <div class="list-actions">
          <button
            class="list-btn list-btn--icon-only list-btn--export"
            @click="emit('export')"
            :disabled="isExporting"
            v-tooltip.bottom="'Exportar relatório PDF'"
          >
            <i :class="isExporting ? 'pi pi-spin pi-spinner' : 'pi pi-file-pdf'" />
          </button>
          <button
            class="list-btn list-btn--icon-only"
            :class="farmaciaLists.isInteresse(cnpj) ? 'list-btn--interesse-active' : 'list-btn--interesse'"
            @click="farmaciaLists.toggleInteresse(cnpj, cnpjData.razao_social)"
            v-tooltip.bottom="farmaciaLists.isInteresse(cnpj) ? 'Remover da Lista de Interesse' : 'Adicionar à Lista de Interesse'"
          >
            <i :class="farmaciaLists.isInteresse(cnpj) ? 'pi pi-star-fill' : 'pi pi-star'" />
          </button>
        </div>
        <div class="header-kpis-new">
          <!-- Bloco Unificado de Risco -->
          <div 
            class="kpi-pill-group"
            :class="[getRiskClass(risco) === 'risk-critical' ? 'risk-high' : getRiskClass(risco)]"
          >
            <div class="pill-item">
              <span class="pill-label">% Sem Comprovação</span>
              <span class="pill-value">
                {{ cnpjData.percValSemComp?.toFixed(2) }}%
              </span>
            </div>

            <div class="pill-divider"></div>

            <div class="pill-item">
              <span class="pill-label">Valor sem Comprovação</span>
              <span class="pill-value currency">
                {{ formatCurrencyFull(cnpjData.valSemComp) }}
              </span>
            </div>
          </div>

          <!-- Bloco Neutro -->
          <div class="kpi-card-neutral">
            <span class="pill-label">Total Movimentado</span>
            <span class="pill-value total">
              {{ formatCurrencyFull(cnpjData.totalMov) }}
            </span>
          </div>
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

.header-right-col {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  justify-content: space-between;
  gap: 0.75rem;
  flex-shrink: 0;
}

.list-actions {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.list-btn {
  display: inline-flex;
  align-items: center;
  gap: 0.4rem;
  padding: 0.35rem 0.8rem;
  font-size: 0.75rem;
  font-weight: 700;
  border-radius: 8px; /* Padronizado para 8px */
  border: 1px solid;
  cursor: pointer;
  transition: all 0.2s ease;
  text-transform: uppercase;
  letter-spacing: 0.04em;
}

.list-btn--icon-only {
  width: 34px;
  height: 34px;
  padding: 0;
  justify-content: center;
}

.list-btn--icon-only i {
  font-size: 1rem;
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
  align-items: flex-start;
  gap: 2rem;
  min-width: 0;
}

.title-group {
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
  min-width: 0;
  flex: 1;
}

.razao-social-row {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  flex-wrap: nowrap;
}

.razao-social-new {
  font-size: 1.4rem;
  font-weight: 700;
  margin: 0;
  line-height: 1.2;
  letter-spacing: -0.02em;
  color: var(--establishment-header-text);
  white-space: nowrap;
  flex-shrink: 0;
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

.address-row-new {
  display: flex;
  align-items: center;
  gap: 1.25rem;
}

.address-text {
  font-size: 0.82rem;
  font-weight: 500;
  color: var(--text-color);
  display: flex;
  align-items: center;
  gap: 0.4rem;
  opacity: 0.8;
}

.address-text i {
  font-size: 0.75rem;
  color: var(--primary-color);
  opacity: 0.7;
}

.sep-dot {
  margin: 0 0.1rem;
  opacity: 0.4;
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
  align-items: center;
  gap: 0.75rem; /* Reduzido de 1.25rem */
}

/* Cápsula Unificada de Risco */
.kpi-pill-group {
  display: flex;
  align-items: center;
  padding: 0.3rem 0.45rem; /* Compacto em todas as dimensões */
  background: rgba(255, 255, 255, 0.03);
  border: 1px solid rgba(255, 255, 255, 0.08);
  border-radius: 12px; /* Arredondamento um pouco menor para a pill menor */
  position: relative;
  transition: all 0.3s ease;
}

/* Cores dinâmicas da cápsula */
.kpi-pill-group.risk-high {
  background: color-mix(in srgb, var(--risk-high) 8%, transparent);
  border-color: color-mix(in srgb, var(--risk-high) 20%, transparent);
  --accent: var(--risk-high);
}
.kpi-pill-group.risk-critical {
  background: color-mix(in srgb, var(--risk-critical) 8%, transparent);
  border-color: color-mix(in srgb, var(--risk-critical) 20%, transparent);
  --accent: var(--risk-critical);
}
.kpi-pill-group.risk-medium {
  background: color-mix(in srgb, var(--risk-medium) 8%, transparent);
  border-color: color-mix(in srgb, var(--risk-medium) 20%, transparent);
  --accent: var(--risk-medium);
}
.kpi-pill-group.risk-low {
  background: color-mix(in srgb, var(--risk-low) 8%, transparent);
  border-color: color-mix(in srgb, var(--risk-low) 20%, transparent);
  --accent: var(--risk-low);
}

.pill-item {
  display: flex;
  flex-direction: column;
  padding: 0.15rem 0.5rem; /* Padding horizontal reduzido pela metade */
}

.pill-label {
  font-size: 0.62rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: var(--establishment-header-text);
  opacity: 0.7; /* Aumentado para melhor legibilidade */
  margin-bottom: 0.15rem;
}

.pill-value {
  font-size: 1.25rem;
  font-weight: 600;
  font-family: 'Inter', sans-serif;
  color: var(--accent, var(--establishment-header-text));
  line-height: 1.1;
  letter-spacing: -0.02em;
}

.pill-value.currency {
  font-size: 1.15rem;
  opacity: 0.9;
}

.pill-divider {
  width: 1px;
  height: 2rem;
  background: rgba(255, 255, 255, 0.1);
}

/* Card Neutro */
.kpi-card-neutral {
  display: flex;
  flex-direction: column;
  padding-left: 0.75rem; /* Reduzido de 1.25rem */
  border-left: 1px solid rgba(255, 255, 255, 0.1); /* Linha sutil separadora */
}

.pill-value.total {
  font-size: 1.15rem;
  opacity: 0.85; /* Reforçado para melhor leitura */
}

.kpi-card.risk-high .kpi-card-value, 
.kpi-card.risk-high .kpi-badge-value   { color: var(--risk-high); }
.kpi-card.risk-high                   { border-left-color: var(--risk-high); }

.kpi-card.risk-critical .kpi-card-value,
.kpi-card.risk-critical .kpi-badge-value { color: var(--risk-critical); }
.kpi-card.risk-critical               { border-left-color: var(--risk-critical); }

.kpi-card.risk-medium .kpi-card-value,
.kpi-card.risk-medium .kpi-badge-value { color: var(--risk-medium); }
.kpi-card.risk-medium                  { border-left-color: var(--risk-medium); }

.kpi-card.risk-low .kpi-card-value,
.kpi-card.risk-low .kpi-badge-value     { color: var(--risk-low); }
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
  opacity: 0.5; /* Ajustado para 0.5 conforme solicitado */
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
