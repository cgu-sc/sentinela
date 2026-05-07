<script setup>
import { computed } from "vue";
import { storeToRefs } from "pinia";
import { useCnpjDetailStore } from "@/stores/cnpjDetail";
import { useFormatting } from "@/composables/useFormatting";
import ProgressSpinner from "primevue/progressspinner";

const cnpjDetailStore = useCnpjDetailStore();
const { sociosData, sociosLoading, sociosError } = storeToRefs(cnpjDetailStore);
const { formatarData, formatPercent, formatTitleCase } = useFormatting();

const socios = computed(() => sociosData.value?.socios || []);
const dataProcessamento = computed(() => sociosData.value?.data_processamento || null);

const formatCpfCnpj = (v) => {
  if (!v) return "—";
  const clean = v.replace(/\D/g, "");
  if (clean.length === 11) {
    return clean.replace(/^(\d{3})(\d{3})(\d{3})(\d{2})$/, "$1.$2.$3-$4");
  }
  if (clean.length === 14) {
    return clean.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/, "$1.$2.$3/$4-$5");
  }
  return v;
};

const formatTipoSocio = (v) => {
  if (v === "PF") return "Pessoa Física";
  if (v === "PJ") return "Pessoa Jurídica";
  return v;
};

// Determina se o sócio ainda é ativo (sem data de exclusão)
const isAtivo = (socio) => !socio.data_exclusao_sociedade;

</script>

<template>
  <div class="socios-tab tab-content">
    <div class="socios-card animate-fade-in">
      <div class="section-header">
        <div class="header-left">
          <i class="pi pi-users" />
          <div class="header-text">
            <h2 class="title">QUADRO SOCIETÁRIO</h2>
            <p class="subtitle">
              Composição de sócios e administradores registrada na Receita Federal.
              <span 
                v-if="dataProcessamento" 
                class="data-ref" 
                v-tooltip.top="'Data da última sincronização dos dados societários com a base oficial da Receita Federal.'"
              >
                Ref: {{ formatarData(dataProcessamento) }}
                <i class="pi pi-info-circle" style="font-size: 0.65rem; margin-left: 0.2rem; opacity: 0.7" />
              </span>
            </p>
          </div>
        </div>
        <div v-if="socios.length > 0" class="header-badge">
          {{ socios.filter(isAtivo).length }} Sócios Ativos
        </div>
      </div>

      <div v-if="sociosLoading" class="loading-state">
        <ProgressSpinner style="width: 40px; height: 40px" strokeWidth="3" />
        <span>Carregando composição societária...</span>
      </div>

      <div v-else-if="sociosError" class="error-state">
        <i class="pi pi-exclamation-circle" />
        <p>{{ sociosError }}</p>
      </div>

      <div v-else-if="socios.length === 0" class="empty-state">
        <i class="pi pi-info-circle" />
        <p>Nenhum dado societário encontrado para este estabelecimento.</p>
      </div>

      <div v-else class="table-wrapper">
        <table class="premium-table">
          <thead>
            <tr>
              <th>Sócio / Nome Empresarial</th>
              <th class="col-center">CPF / CNPJ</th>
              <th>Qualificação</th>
              <th>Localização</th>
              <th class="col-center">Participação</th>
              <th class="col-center">Entrada</th>
              <th class="col-center">Saída / Situação</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="s in socios" :key="s.cpf_cnpj_socio" :class="{ 'row-inactive': !isAtivo(s) }">
              <td>
                <div class="socio-name">
                  {{ s.nome_socio || 'NOME NÃO INFORMADO' }}
                  <span v-if="s.indicador_socio" class="socio-type">{{ formatTipoSocio(s.indicador_socio) }}</span>
                </div>
              </td>
              <td class="col-center font-mono">{{ formatCpfCnpj(s.cpf_cnpj_socio) }}</td>
              <td class="qualificacao-cell">
                {{ s.descricao_qualificacao || '—' }}
              </td>
              <td class="location-cell">
                <div v-if="s.municipio" class="location-wrapper">
                  <i class="pi pi-map-marker" />
                  <span>{{ s.municipio }} / {{ s.uf }}</span>
                </div>
                <span v-else>—</span>
              </td>
              <td class="col-center">
                <div class="pct-container" v-if="s.percentual_qualificacao > 0">
                  <div class="pct-bar-bg">
                    <div class="pct-bar-fill" :style="{ width: s.percentual_qualificacao + '%' }"></div>
                  </div>
                  <span class="pct-val">{{ formatPercent(s.percentual_qualificacao) }}</span>
                </div>
                <span v-else>—</span>
              </td>
              <td class="col-center">{{ formatarData(s.data_entrada_sociedade) }}</td>
              <td class="col-center">
                <span v-if="s.data_exclusao_sociedade" class="status-badge inactive">
                  Saída em {{ formatarData(s.data_exclusao_sociedade) }}
                </span>
                <span v-else class="status-badge active">Ativo</span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
  </div>
</template>

<style scoped>
.socios-tab {
  height: 100%;
}

.socios-card {
  display: flex;
  flex-direction: column;
  gap: 1.5rem;
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  border-radius: 12px;
  padding: 1.25rem;
  min-height: 20rem;
  backdrop-filter: blur(10px);
  -webkit-backdrop-filter: blur(10px);
  box-shadow: 0 2px 8px rgba(0,0,0,0.06);
}

.section-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 0.5rem 0;
  border-bottom: 1px solid var(--tabs-border);
  margin-bottom: 0.75rem;
}

.header-left {
  display: flex;
  align-items: center;
  gap: 1rem;
}

.header-left i {
  font-size: 1rem;
  color: var(--primary-color);
}

.title {
  margin: 0;
  font-size: 0.85rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: var(--text-color);
  opacity: 0.85;
}

.subtitle {
  margin: 0.2rem 0 0 0;
  font-size: 0.85rem;
  color: var(--text-muted);
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.data-ref {
  background: color-mix(in srgb, var(--text-muted) 10%, transparent);
  color: var(--text-secondary);
  padding: 0.1rem 0.4rem;
  border-radius: 4px;
  font-size: 0.7rem;
  font-weight: 600;
  border: 1px solid color-mix(in srgb, var(--text-muted) 20%, transparent);
  cursor: help;
}

.header-badge {
  background: color-mix(in srgb, var(--primary-color) 15%, transparent);
  color: var(--primary-color);
  padding: 0.4rem 0.8rem;
  border-radius: 99px;
  font-size: 0.75rem;
  font-weight: 600;
  border: 1px solid color-mix(in srgb, var(--primary-color) 30%, transparent);
}

/* Tabela Premium */
.table-wrapper {
  overflow-x: auto;
}

.premium-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 0.9rem;
}

.premium-table th {
  text-align: left;
  padding: 0.8rem 1rem;
  font-size: 0.7rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--text-secondary);
  border-bottom: 2px solid var(--tabs-border);
}

.premium-table td {
  padding: 1rem;
  border-bottom: 1px solid var(--tabs-border);
  color: var(--text-color);
}

.premium-table tbody tr {
  background: transparent !important;
}

.premium-table tbody tr:hover {
  background: var(--table-hover) !important;
}

.row-inactive {
  opacity: 0.6;
  background: color-mix(in srgb, var(--bg-color) 95%, black) !important;
}

.col-center { text-align: center; }
.font-mono { font-family: var(--font-mono, monospace); font-size: 0.85rem; }

.socio-name {
  font-weight: 500;
  display: flex;
  flex-direction: column;
  text-transform: none !important;
}

.socio-type {
  font-size: 0.7rem;
  color: var(--text-muted);
  font-weight: 500;
  text-transform: uppercase;
  letter-spacing: 0.02em;
  margin-top: 0.1rem;
}

.qualificacao-cell {
  font-size: 0.85rem;
  color: var(--text-secondary);
  text-transform: none !important;
}

.location-cell {
  font-size: 0.8rem;
  color: var(--text-secondary);
  min-width: 120px;
}

.location-wrapper {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  opacity: 0.85;
}

.location-wrapper i {
  font-size: 0.75rem;
  color: var(--primary-color);
  opacity: 0.7;
}

/* Barra de Percentual */
.pct-container {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0.3rem;
  min-width: 80px;
}

.pct-bar-bg {
  width: 100%;
  height: 4px;
  background: var(--tabs-border);
  border-radius: 2px;
  overflow: hidden;
}

.pct-bar-fill {
  height: 100%;
  background: var(--primary-color);
  border-radius: 2px;
  transition: width 1s ease-out;
}

.pct-val {
  font-size: 0.75rem;
  font-weight: 600;
  color: var(--primary-color);
}

/* Badges de Status */
.status-badge {
  font-size: 0.7rem;
  font-weight: 600;
  padding: 0.2rem 0.6rem;
  border-radius: 4px;
  display: inline-block;
}

.status-badge.active {
  background: rgba(16, 185, 129, 0.1);
  color: #10b981;
  border: 1px solid rgba(16, 185, 129, 0.2);
}

.status-badge.inactive {
  background: rgba(100, 116, 139, 0.1);
  color: var(--text-muted);
  border: 1px solid rgba(100, 116, 139, 0.2);
}

/* States */
.loading-state, .error-state, .empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 1rem;
  padding: 4rem 0;
  color: var(--text-muted);
}

.error-state i { color: var(--risk-critical); font-size: 2rem; }
.empty-state i { font-size: 2rem; opacity: 0.5; }

.animate-fade-in {
  animation: fadeIn 0.4s ease-out;
}

@keyframes fadeIn {
  from { opacity: 0; transform: translateY(10px); }
  to { opacity: 1; transform: translateY(0); }
}
</style>
