<script setup>
/**
 * RegionalAnalysisView.vue
 * Aba "Região de Saúde" do módulo consolidado.
 *
 * Exibe dois painéis:
 *  1. Resumo dos municípios da região (população e densidade de farmácias).
 *  2. Ranking completo de farmácias da região ordenado por Score de Risco.
 *
 * O endpoint é acionado automaticamente ao selecionar uma Região de Saúde
 * no filtro da sidebar. Se nenhuma região estiver selecionada, exibe um
 * estado de orientação para o usuário.
 */
import { ref, watch, computed } from 'vue';
import { useFilterStore } from '@/stores/filters';
import { FILTER_ALL_VALUE } from '@/config/constants';
import { API_ENDPOINTS } from '@/config/api';
import RegionalMunicipalTable from './components/tables/RegionalMunicipalTable.vue';
import RegionalPharmacyTable from './components/tables/RegionalPharmacyTable.vue';
import ProgressBar from 'primevue/progressbar';

const filterStore = useFilterStore();

// ── Estado ──────────────────────────────────────────────────────────────────
const isLoading   = ref(false);
const errorMsg    = ref(null);
const regionalData = ref(null); // { nome_regiao, id_regiao, municipios, farmacias }

// ── Computed ─────────────────────────────────────────────────────────────────
const regiaoSelecionada = computed(() =>
  filterStore.selectedRegiaoSaude !== FILTER_ALL_VALUE
    ? filterStore.selectedRegiaoSaude
    : null
);

// ── Fetch ────────────────────────────────────────────────────────────────────
async function fetchRegional(regiao, uf) {
  if (!regiao) {
    regionalData.value = null;
    return;
  }
  try {
    isLoading.value = true;
    errorMsg.value  = null;
    const url = API_ENDPOINTS.analyticsRegional(regiao, uf);
    const res = await fetch(url);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    regionalData.value = await res.json();
  } catch (e) {
    console.error('❌ Erro ao buscar dados regionais:', e);
    errorMsg.value = 'Não foi possível carregar os dados da região. Verifique a conexão com o backend.';
    regionalData.value = null;
  } finally {
    isLoading.value = false;
  }
}

// Reage ao filtro da sidebar
watch([regiaoSelecionada, () => filterStore.selectedUF], ([novaRegiao, novoUF]) => {
  fetchRegional(novaRegiao, novoUF);
}, { immediate: true });
</script>

<template>
  <div class="regional-view">

    <!-- ── Estado: Nenhuma região selecionada ─────────────────────────────── -->
    <div v-if="!regiaoSelecionada" class="empty-state shadow-card">
      <div class="empty-icon">
        <i class="pi pi-map"></i>
      </div>
      <h2>Selecione uma Região de Saúde</h2>
      <p>
        Utilize o filtro <strong>Região de Saúde</strong> na barra lateral para visualizar
        o resumo municipal e o ranking de risco dos estabelecimentos da região.
      </p>
    </div>

    <!-- ── Estado: Carregando ─────────────────────────────────────────────── -->
    <div v-else-if="isLoading" class="loading-state shadow-card">
      <p class="loading-label">
        <i class="pi pi-spin pi-sync" style="margin-right: 0.5rem"></i>
        Carregando dados — <strong>{{ regiaoSelecionada }}</strong>
      </p>
      <ProgressBar mode="indeterminate" style="height: 6px; border-radius: 3px;" />
    </div>

    <!-- ── Estado: Erro ───────────────────────────────────────────────────── -->
    <div v-else-if="errorMsg" class="error-state shadow-card">
      <i class="pi pi-times-circle error-icon"></i>
      <p>{{ errorMsg }}</p>
    </div>

    <!-- ── Estado: Sem dados ──────────────────────────────────────────────── -->
    <div v-else-if="regionalData && regionalData.farmacias.length === 0" class="empty-state shadow-card">
      <div class="empty-icon warning">
        <i class="pi pi-exclamation-triangle"></i>
      </div>
      <h2>Nenhum dado encontrado</h2>
      <p>A região <strong>{{ regiaoSelecionada }}</strong> não possui farmácias no cache atual.</p>
    </div>

    <!-- ── Conteúdo principal ─────────────────────────────────────────────── -->
    <template v-else-if="regionalData">
      <!-- Cabeçalho da página -->
      <div class="page-header shadow-card">
        <div class="page-title-group">
          <span class="region-badge">
            <i class="pi pi-map-marker"></i>
            Região de Saúde
          </span>
          <h1>{{ regionalData.nome_regiao }}</h1>
          <span v-if="regionalData.id_regiao" class="region-id">ID {{ regionalData.id_regiao }}</span>
        </div>
        <div class="page-stats">
          <div class="stat-chip">
            <i class="pi pi-building"></i>
            <span>{{ regionalData.farmacias.length }} farmácias</span>
          </div>
          <div class="stat-chip">
            <i class="pi pi-map-marker"></i>
            <span>{{ regionalData.municipios.length }} municípios</span>
          </div>
        </div>
      </div>

      <!-- Tabela de municípios -->
      <RegionalMunicipalTable :municipios="regionalData.municipios" />

      <!-- Ranking de farmácias -->
      <RegionalPharmacyTable :farmacias="regionalData.farmacias" />

      <!-- Nota de rodapé -->
      <p class="footnote">
        Este ranking apresenta todas as farmácias da mesma Região de Saúde ordenadas pelo índice de anomalias.
        A posição relativa ajuda a identificar se o comportamento de um estabelecimento é um desvio local ou regional.
      </p>
    </template>

  </div>
</template>

<style scoped>
.regional-view {
  display: flex;
  flex-direction: column;
  gap: 1.5rem;
}

/* ── Empty / Error / Loading states ── */
.empty-state,
.loading-state,
.error-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 1rem;
  padding: 3.5rem 2rem;
  border: 1px solid var(--sidebar-border);
  background: var(--card-bg);
  border-radius: 12px;
  text-align: center;
}

.empty-icon {
  width: 72px;
  height: 72px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 2rem;
  background: color-mix(in srgb, var(--primary-color) 10%, transparent);
  color: var(--primary-color);
}

.empty-icon.warning {
  background: color-mix(in srgb, var(--color-warning, #f59e0b) 10%, transparent);
  color: var(--color-warning, #f59e0b);
}

.empty-state h2 {
  margin: 0;
  font-size: 1.3rem;
  font-weight: 700;
  color: var(--text-color);
}

.empty-state p {
  margin: 0;
  color: var(--text-muted);
  max-width: 420px;
  line-height: 1.6;
}

.error-icon {
  font-size: 2.5rem;
  color: var(--color-error, #ef4444);
}

.loading-label {
  margin: 0 0 0.75rem;
  font-size: 0.95rem;
  color: var(--text-muted);
}

/* ── Cabeçalho ── */
.page-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 1.25rem 1.75rem;
  border: 1px solid var(--sidebar-border);
  background: var(--card-bg);
  border-radius: 12px;
  gap: 1rem;
  flex-wrap: wrap;
}

.page-title-group {
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
}

.region-badge {
  display: inline-flex;
  align-items: center;
  gap: 0.4rem;
  font-size: 0.7rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.6px;
  color: var(--primary-color);
  background: color-mix(in srgb, var(--primary-color) 10%, transparent);
  padding: 0.2rem 0.65rem;
  border-radius: 20px;
  width: fit-content;
}

.page-title-group h1 {
  margin: 0;
  font-size: 1.5rem;
  font-weight: 800;
  color: var(--text-color);
  letter-spacing: -0.02em;
}

.region-id {
  font-size: 0.75rem;
  color: var(--text-muted);
}

.page-stats {
  display: flex;
  gap: 0.75rem;
  flex-wrap: wrap;
}

.stat-chip {
  display: inline-flex;
  align-items: center;
  gap: 0.45rem;
  padding: 0.45rem 0.9rem;
  border-radius: 20px;
  border: 1px solid var(--sidebar-border);
  background: var(--bg-color);
  font-size: 0.82rem;
  font-weight: 600;
  color: var(--text-color);
}

.stat-chip i {
  color: var(--primary-color);
  font-size: 0.85rem;
}

/* ── Rodapé ── */
.footnote {
  margin: 0;
  padding: 0.75rem 1rem;
  font-size: 0.78rem;
  color: var(--text-muted);
  font-style: italic;
  border-left: 3px solid var(--sidebar-border);
  background: color-mix(in srgb, var(--bg-color) 60%, transparent);
  border-radius: 0 6px 6px 0;
  line-height: 1.5;
}
</style>
