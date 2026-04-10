<script setup>
import { computed, ref } from 'vue';
import { storeToRefs } from 'pinia';
import { useCnpjDetailStore } from '@/stores/cnpjDetail';
import { useFormatting } from '@/composables/useFormatting';
import { useAnalyticsStore } from '@/stores/analytics';
import { useFarmaciaListsStore } from '@/stores/farmaciaLists';
import Tag from 'primevue/tag';
import Button from 'primevue/button';
import MortalityTimelineOverlay from './MortalityTimelineOverlay.vue';

const props = defineProps({
  cnpj: {
    type: String,
    required: true
  }
});

const { falecidosData, falecidosLoading, falecidosLoaded, falecidosError } = storeToRefs(useCnpjDetailStore());
const { formatCurrencyFull, formatarData, formatTitleCase, formatCnpj } = useFormatting();
const analyticsStore = useAnalyticsStore();
const farmaciaLists = useFarmaciaListsStore();

// Mapa para busca O(1) de dados do CNPJ no Pinia Store para enriquecer o painel.
const cnpjsDict = computed(() => {
  const dict = {};
  if (analyticsStore.resultadoCnpjs) {
    for (const c of analyticsStore.resultadoCnpjs) {
      dict[c.cnpj] = c;
    }
  }
  return dict;
});

const getEstabelecimentoInfo = (estabStr) => {
  if (!estabStr) return { cnpj: '', name: '', geo: '' };
  const rawCnpj = estabStr.split(' - ')[0]?.trim() || '';
  const cleanCnpj = rawCnpj.replace(/\D/g, '');
  
  // Tenta puxar dados otimizados da store do Pinia
  const cnpjData = cnpjsDict.value[cleanCnpj];
  
  let name = estabStr.split(' - ')[1]?.split(' | ')[0]?.trim() || estabStr;
  let cityUF = estabStr.split(' | ')[1]?.trim() || '';
  let regiao = estabStr.split(' | ')[2]?.trim() || '';
  
  // Se existir no Pinia Store, prioriza dados consistentes e mais completos
  if (cnpjData) {
    if (cnpjData.razao_social) name = cnpjData.razao_social;
    if (cnpjData.municipio && cnpjData.uf) cityUF = `${cnpjData.municipio} - ${cnpjData.uf}`;
    if (cnpjData.regiao_saude) regiao = cnpjData.regiao_saude;
  }

  let geo = cityUF;
  if (regiao) {
     geo += ` • ${regiao}`;
  }

  return { 
    cnpj: rawCnpj,
    cleanCnpj: cleanCnpj,
    name: name,
    geo: geo
  };
};

// Função para mapear o risco em 10 níveis térmicos descritivos
function getDayStepClass(days) {
  if (days <= 7)   return 'd-risk-0-7d';
  if (days <= 15)  return 'd-risk-8-15d';
  if (days <= 30)  return 'd-risk-16-30d';
  if (days <= 60)  return 'd-risk-31-60d';
  if (days <= 120) return 'd-risk-61-120d';
  if (days <= 240) return 'd-risk-121-240d';
  if (days <= 365) return 'd-risk-241-1y';
  if (days <= 730) return 'd-risk-1-2y';
  if (days <= 1095) return 'd-risk-2-3y';
  return 'd-risk-over-3y';
}


const falecidosAgrupados = computed(() => {
  const transacoes = falecidosData.value?.transacoes ?? [];
  const grupos = new Map();
  for (const t of transacoes) {
    if (!grupos.has(t.cpf)) {
      grupos.set(t.cpf, {
        cpf:           t.cpf,
        nome:          formatTitleCase(t.nome_falecido) || 'Não Identificado',
        municipio:     formatTitleCase(t.municipio_falecido),
        uf:            t.uf_falecido,
        dt_obito:      formatarData(t.dt_obito),
        dt_nascimento: formatarData(t.dt_nascimento),
        outros_cnpj:   t.outros_estabelecimentos,
        transacoes:    [],
        total_valor:   0,
        max_dias:      0,
      });
    }
    const g = grupos.get(t.cpf);
    g.transacoes.push({ ...t, nome_falecido: formatTitleCase(t.nome_falecido) });
    g.total_valor += t.valor_total_autorizacao ?? 0;
    g.max_dias = Math.max(g.max_dias, t.dias_apos_obito ?? 0);
  }
  return [...grupos.values()];
});

const timelineOverlay = ref(null);

defineExpose({
  getSummary:  () => falecidosData.value?.summary ?? null,
  getAgrupados: () => falecidosAgrupados.value ?? [],
  getRanking:  () => falecidosData.value?.ranking ?? [],
  hasData:     () => !!(falecidosLoaded.value && falecidosData.value?.transacoes?.length),
});

const toggleMultiCnpj = (event, grupo) => {
  timelineOverlay.value?.open(event, grupo);
};

const openEstablishment = (estabStr) => {
  if (!estabStr) return;
  const targetCnpj = estabStr.split(' - ')[0].replace(/\D/g, '');
  window.open(`/estabelecimento/${targetCnpj}`, '_blank');
};

const isRankingExpanded = ref(false);
const visibleRanking = computed(() => {
  const r = falecidosData.value?.ranking || [];
  if (isRankingExpanded.value || r.length <= 3) return r;
  return r.slice(0, 3);
});

const filteredRankingCnpj = ref(null);

const toggleRankingFilter = (cleanCnpj) => {
  filteredRankingCnpj.value = filteredRankingCnpj.value === cleanCnpj ? null : cleanCnpj;
};

const falecidosAgrupadosFiltrados = computed(() => {
  if (!filteredRankingCnpj.value) return falecidosAgrupados.value;
  return falecidosAgrupados.value.filter(
    (g) => g.outros_cnpj && g.outros_cnpj.includes(filteredRankingCnpj.value)
  );
});

</script>

<template>
  <div class="tab-content falecidos-tab">
    <div v-if="falecidosLoading" class="tab-placeholder">
      <i class="pi pi-spin pi-spinner placeholder-icon" />
      <p>Analisando base de óbitos...</p>
    </div>

    <div v-else-if="falecidosError" class="tab-placeholder tab-placeholder--error">
      <i class="pi pi-exclamation-circle placeholder-icon" />
      <p>{{ falecidosError }}</p>
    </div>

    <div v-else-if="falecidosLoaded && !falecidosData?.transacoes?.length" class="tab-placeholder">
      <i class="pi pi-check-circle placeholder-icon" style="color: var(--green-500)" />
      <p>Nenhuma venda para falecidos encontrada neste estabelecimento.</p>
    </div>

    <template v-else-if="falecidosLoaded">
      <!-- 7 CARDS DE KPI -->
      <div class="falecidos-kpi-grid">
        <div class="f-kpi-card" :class="falecidosData.summary.cpfs_distintos > 0 ? 'highlight-red' : ''">
          <span class="f-kpi-label">CPFs Distintos</span>
          <span class="f-kpi-val">{{ falecidosData.summary.cpfs_distintos }}</span>
        </div>
        <div class="f-kpi-card" :class="falecidosData.summary.total_autorizacoes > 0 ? 'highlight-red' : ''">
          <span class="f-kpi-label">Núm. Autorizações</span>
          <span class="f-kpi-val">{{ falecidosData.summary.total_autorizacoes }}</span>
        </div>
        <div class="f-kpi-card" :class="falecidosData.summary.valor_total > 0 ? 'highlight-red highlight-prejuizo' : ''">
          <span class="f-kpi-label">Prejuízo Estimado</span>
          <div class="f-kpi-val-container">
            <span class="f-kpi-val">{{ formatCurrencyFull(falecidosData.summary.valor_total) }}</span>
          </div>
        </div>
        <div class="f-kpi-card" :class="(falecidosData.summary.media_dias || 0) > 0 ? 'highlight-red' : ''">
          <span class="f-kpi-label">Média Dias Pós-Óbito</span>
          <span class="f-kpi-val">{{ falecidosData.summary.media_dias.toFixed(1) }} <small>dias</small></span>
        </div>
        <div class="f-kpi-card" :class="falecidosData.summary.max_dias > 0 ? 'highlight-red' : ''">
          <span class="f-kpi-label">Máximo Dias Pós-Óbito</span>
          <span class="f-kpi-val">{{ falecidosData.summary.max_dias }} <small>dias</small></span>
        </div>
        <div class="f-kpi-card" :class="falecidosData.summary.pct_faturamento > 0 ? 'highlight-orange' : ''">
          <span class="f-kpi-label">% do Faturamento</span>
          <span class="f-kpi-val">{{ (falecidosData.summary.pct_faturamento * 100).toFixed(3) }}%</span>
        </div>
        <div class="f-kpi-card" :class="falecidosData.summary.cpfs_multi_cnpj > 0 ? 'highlight-red' : ''">
          <span class="f-kpi-label">CPFs Multi-CNPJ</span>
          <span class="f-kpi-val">{{ falecidosData.summary.cpfs_multi_cnpj }} <small>({{ (falecidosData.summary.pct_multi_cnpj * 100).toFixed(1) }}%)</small></span>
        </div>
      </div>

      <!-- PAINEL MULTI-CNPJ (REDE DE COINCIDÊNCIA) -->
      <div class="falecidos-ranking-panel" v-if="falecidosData.ranking?.length">
        <div class="ranking-header-flex">
          <div class="title-wrap">
            <i class="pi pi-sitemap" />
            <span>Rede de Coincidência (Cross-CNPJ)</span>
          </div>
          <p class="ranking-subtitle">Outras farmácias monitoradas que aprovaram medicamentos para os mesmos falecidos identificados nesta unidade.</p>
        </div>
        
        <div class="pro-ranking-list">
          <div
             v-for="(r, index) in visibleRanking"
             :key="r.estabelecimento"
             class="pro-ranking-item"
          >
            <div class="rank-badge" :class="`rank-${index + 1}`">#{{ index + 1 }}</div>
            
            <div class="rank-info">
               <div class="rank-info-top">
                   <span class="rank-cnpj">{{ formatCnpj(getEstabelecimentoInfo(r.estabelecimento).cnpj) }}</span>
                   <span class="rank-name">{{ getEstabelecimentoInfo(r.estabelecimento).name }}</span>
               </div>
               <div class="rank-geo" v-if="getEstabelecimentoInfo(r.estabelecimento).geo">
                   <i class="pi pi-map-marker"></i>
                   <span>{{ getEstabelecimentoInfo(r.estabelecimento).geo }}</span>
               </div>
               <div class="rank-bar-wrapper">
                   <div class="rank-bar-bg">
                      <div class="rank-bar-fill" :style="{ width: (r.pct_total * 100) + '%' }"></div>
                   </div>
               </div>
            </div>

            <div class="rank-metrics">
               <span class="metric-val">{{ r.qtd_cpfs }}</span>
               <span class="metric-lbl">CPFs em Comum</span>
               <span class="metric-pct">({{ Math.round(r.pct_total * 100) }}%)</span>
            </div>

             <div class="rank-action">
                <button
                  class="rank-filter-btn"
                  :class="{ active: filteredRankingCnpj === getEstabelecimentoInfo(r.estabelecimento).cleanCnpj }"
                  @click.stop="toggleRankingFilter(getEstabelecimentoInfo(r.estabelecimento).cleanCnpj)"
                  v-tooltip.top="'Filtrar a tabela de transações por este CNPJ'"
                >
                  <i :class="filteredRankingCnpj === getEstabelecimentoInfo(r.estabelecimento).cleanCnpj ? 'pi pi-filter-slash' : 'pi pi-filter'" />
                  <span>Exibir</span>
                </button>
                <button
                  class="rank-filter-btn"
                  :class="{ active: farmaciaLists.isInteresse(getEstabelecimentoInfo(r.estabelecimento).cleanCnpj) }"
                  v-tooltip.top="farmaciaLists.isInteresse(getEstabelecimentoInfo(r.estabelecimento).cleanCnpj) ? 'Remover da lista de interesse' : 'Salvar na lista de interesse para acompanhamento'"
                  @click.stop="farmaciaLists.toggleInteresse(getEstabelecimentoInfo(r.estabelecimento).cleanCnpj, getEstabelecimentoInfo(r.estabelecimento).name)"
                >
                  <i :class="farmaciaLists.isInteresse(getEstabelecimentoInfo(r.estabelecimento).cleanCnpj) ? 'pi pi-star-fill' : 'pi pi-star'" />
                  <span>Interesse</span>
                </button>
                <button
                  class="rank-filter-btn rank-open-btn"
                  v-tooltip.top="'Abrir análise completa deste CNPJ'"
                  @click.stop="openEstablishment(r.estabelecimento)"
                >
                  <i class="pi pi-external-link" />
                  <span>Analisar CNPJ</span>
                </button>
             </div>
          </div>
        </div>

        <div v-if="falecidosData.ranking?.length > 3" class="ranking-expand-action">
           <Button 
              :icon="isRankingExpanded ? 'pi pi-chevron-up' : 'pi pi-chevron-down'" 
              :label="isRankingExpanded ? 'Recolher Lista' : `Ver Mais ${falecidosData.ranking.length - 3} Farmácias Conectadas`" 
              class="p-button-text p-button-sm p-button-secondary"
              @click="isRankingExpanded = !isRankingExpanded" 
           />
        </div>
      </div>

      <!-- TABELA DE TRANSAÇÕES -->
      <div class="falecidos-list-container">
        <div class="section-title">
          <i class="pi pi-list" />
          <span>Detalhamento de Transações (Agrupado por CPF)</span>
        </div>
        <div v-if="filteredRankingCnpj" class="filter-active-banner">
          <i class="pi pi-filter" />
          <span>
            Exibindo apenas CPFs em comum com
            <strong>{{ formatCnpj(filteredRankingCnpj) }}</strong>
            <template v-if="getEstabelecimentoInfo(falecidosData?.ranking?.find(r => getEstabelecimentoInfo(r.estabelecimento).cleanCnpj === filteredRankingCnpj)?.estabelecimento)?.name">
              — {{ getEstabelecimentoInfo(falecidosData?.ranking?.find(r => getEstabelecimentoInfo(r.estabelecimento).cleanCnpj === filteredRankingCnpj)?.estabelecimento)?.name }}
            </template>
            · <strong>{{ falecidosAgrupadosFiltrados.length }}</strong> CPF(s)
          </span>
          <button class="filter-clear-btn" @click="filteredRankingCnpj = null">
            <i class="pi pi-times" /> Limpar filtro
          </button>
        </div>
        <div class="f-table-wrap">
          <table class="f-table">
            <colgroup>
              <col style="width: 10%" />
              <col style="width: 17%" />
              <col style="width: 12%" />
              <col style="width: 6%" />
              <col style="width: 12%" />
              <col style="width: 8%" />
              <col style="width: 10%" />
              <col style="width: 6%" />
              <col style="width: 9%" />
              <col style="width: 10%" />
            </colgroup>
            <thead>
              <tr>
                <th>CPF</th>
                <th>Nome do Falecido</th>
                <th>Município / UF</th>
                <th>Fonte Óbito</th>
                <th>Nº Autorização</th>
                <th>Dt. Óbito</th>
                <th>Data da Venda</th>
                <th>Itens</th>
                <th>Valor (R$)</th>
                <th class="txt-center">Dias após Óbito</th>
              </tr>
            </thead>
            <tbody>
              <template v-for="grupo in falecidosAgrupadosFiltrados" :key="grupo.cpf">
                <tr class="f-group-header">
                  <td colspan="10">
                    <span class="f-group-cpf">{{ grupo.cpf }}</span>
                    <span class="f-group-sep">|</span>
                    <span class="f-group-nome">{{ grupo.nome }}</span>
                    <span class="f-group-sep">—</span>
                    <span class="f-group-meta">{{ grupo.transacoes.length }} autorização(ões)</span>
                    <span class="f-group-sep">|</span>
                    <span class="f-group-meta">{{ formatCurrencyFull(grupo.total_valor) }}</span>
                    <span class="f-group-sep">|</span>
                    <span class="f-group-meta">Óbito: {{ grupo.dt_obito }}</span>
                    <Tag 
                      v-if="grupo.outros_cnpj" 
                      icon="pi pi-share-alt" 
                      value="MULTI-CNPJ" 
                      class="f-multi-tag status-info clickable-badge"
                      @click="(e) => toggleMultiCnpj(e, grupo)"
                      style="margin-left: 0.75rem;" 
                    />
                  </td>
                </tr>
                <tr v-for="t in grupo.transacoes" :key="t.num_autorizacao" class="f-row">
                  <td class="f-cpf-cell">{{ t.cpf }}</td>
                  <td>
                    <span class="f-nome">{{ t.nome_falecido || 'Não Identificado' }}</span>
                  </td>
                  <td class="f-date">{{ grupo.municipio }}/{{ grupo.uf }}</td>
                  <td class="f-fonte">
                    <span v-if="t.fonte_obito && t.fonte_obito.length > 10" v-tooltip.top="t.fonte_obito" style="cursor: default">
                      {{ t.fonte_obito.substring(0, 10) }}...
                    </span>
                    <span v-else>{{ t.fonte_obito }}</span>
                  </td>
                  <td class="f-aut">{{ t.num_autorizacao }}</td>
                  <td class="f-date">{{ formatarData(t.dt_obito) }}</td>
                  <td class="f-date">{{ formatarData(t.data_autorizacao) }}</td>
                  <td class="f-num">{{ t.qtd_itens_na_autorizacao }}</td>
                  <td class="f-val">{{ formatCurrencyFull(t.valor_total_autorizacao) }}</td>
                  <td class="txt-center">
                    <span class="f-days-badge" :class="getDayStepClass(t.dias_apos_obito)">
                      {{ t.dias_apos_obito }} d
                    </span>
                  </td>
                </tr>
                <tr class="f-subtotal-row">
                  <td colspan="8" class="f-subtotal-label">Subtotal — {{ grupo.transacoes.length }} autorização(ões)</td>
                  <td class="f-val f-subtotal-val">{{ formatCurrencyFull(grupo.total_valor) }}</td>
                  <td></td>
                </tr>
              </template>
            </tbody>
            <tfoot>
              <tr class="f-grand-total">
                <td colspan="8">
                  TOTAL GERAL — {{ falecidosAgrupados.length }} CPF(s) distintos — {{ falecidosData.transacoes.length }} autorização(ões)
                </td>
                <td class="f-val">{{ formatCurrencyFull(falecidosData.summary.valor_total) }}</td>
                <td></td>
              </tr>
            </tfoot>
          </table>
        </div>
      </div>
    </template>

    <div v-else class="tab-placeholder">
      <i class="pi pi-exclamation-triangle placeholder-icon" />
      <p>Clique na aba para processar a análise de óbitos.</p>
    </div>

    <MortalityTimelineOverlay ref="timelineOverlay" :current-cnpj="cnpj" />
  </div>
</template>

<style scoped>
.falecidos-tab {
  padding: 1rem 0 0;
  display: flex;
  flex-direction: column;
  gap: 1.5rem;
}

.falecidos-kpi-grid {
  display: grid;
  grid-template-columns: repeat(7, 1fr);
  gap: 0.75rem;
}

.f-kpi-card {
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  padding: 0.85rem;
  border-radius: 12px;
  display: flex;
  flex-direction: column;
  gap: 0.35rem;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.02);
  transition: transform 0.2s ease, box-shadow 0.2s ease;
}

.f-kpi-card:hover {
  /* Efeito de destaque puramente visual, sem movimento gravitacional pois não é clicável */
  box-shadow: 0 4px 12px rgba(0,0,0,0.03);
}

.f-kpi-card.highlight-red:hover {
  border-color: color-mix(in srgb, var(--risk-high) 60%, var(--card-border));
  box-shadow: 0 4px 15px -4px color-mix(in srgb, var(--risk-high) 20%, transparent);
}

.f-kpi-card.highlight-orange:hover {
  border-color: color-mix(in srgb, var(--risk-medium) 60%, var(--card-border));
  box-shadow: 0 4px 15px -4px color-mix(in srgb, var(--risk-medium) 20%, transparent);
}

.f-kpi-card.highlight-yellow:hover {
  border-color: color-mix(in srgb, var(--risk-low) 60%, var(--card-border));
  box-shadow: 0 4px 15px -4px color-mix(in srgb, var(--risk-low) 20%, transparent);
}

.f-kpi-label {
  font-size: 0.65rem;
  font-weight: 600;
  color: var(--text-secondary);
  text-transform: uppercase;
  letter-spacing: 0.06em;
  opacity: 0.85;
}

.f-kpi-val-container {
  display: flex;
  margin-top: 0.2rem;
}

.f-kpi-val {
  font-size: 1.1rem;
  font-weight: 500;
  color: var(--text-primary);
}

.f-kpi-val.risk-high {
  font-size: 0.95rem; /* Leve ajuste para caber no badge */
  padding: 0.1rem 0.6rem;
  border-radius: 99px;
}

.f-kpi-val small {
  font-size: 0.7rem;
  opacity: 0.6;
}

.highlight-red {
  background: linear-gradient(to top, color-mix(in srgb, var(--risk-high) 15%, var(--card-bg)) 0%, var(--card-bg) 80%);
  border: 1px solid color-mix(in srgb, var(--risk-high) 15%, var(--card-border));
  border-left: none;
  border-bottom: 3px solid color-mix(in srgb, var(--risk-high) 65%, transparent) !important;
}

.highlight-orange {
  background: linear-gradient(to top, color-mix(in srgb, var(--risk-medium) 15%, var(--card-bg)) 0%, var(--card-bg) 80%);
  border: 1px solid color-mix(in srgb, var(--risk-medium) 15%, var(--card-border));
  border-left: none;
  border-bottom: 3px solid color-mix(in srgb, var(--risk-medium) 65%, transparent) !important;
}

.highlight-yellow {
  background: linear-gradient(to top, color-mix(in srgb, var(--risk-low) 15%, var(--card-bg)) 0%, var(--card-bg) 80%);
  border: 1px solid color-mix(in srgb, var(--risk-low) 15%, var(--card-border));
  border-left: none;
  border-bottom: 3px solid color-mix(in srgb, var(--risk-low) 65%, transparent) !important;
}

.falecidos-list-container {
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  border-radius: 12px;
  padding: 1.25rem;
  box-shadow: 0 4px 15px rgba(0,0,0,0.1);
}

.section-title {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  font-size: 0.85rem;
  font-weight: 600;
  text-transform: uppercase;
  color: var(--text-color);
  margin-bottom: 1rem;
  letter-spacing: 0.05em;
  border-bottom: 1px solid var(--tabs-border);
  padding-bottom: 0.5rem;
  opacity: 0.85;
}

.section-title i {
  color: var(--primary-color);
  font-size: 0.9rem;
}

/* Tabela de Falecidos */
.f-table-wrap {
  overflow: hidden;
  padding-top: 0.5rem;
}

.f-table {
  width: 100%;
  border-collapse: collapse;
}

.f-table th {
  text-align: left;
  padding: 0.6rem 1rem;
  background: transparent;
  font-size: 0.68rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.02em;
  color: color-mix(in srgb, var(--text-secondary) 85%, transparent);
  border-bottom: 2px solid var(--tabs-border);
}

.f-table td {
  padding: 0.55rem 1rem;
  border-bottom: 1px solid var(--tabs-border);
  font-size: 0.8rem;
  color: color-mix(in srgb, var(--text-color) 85%, transparent);
  transition: background 0.15s ease;
}

.f-row:hover td {
  background: var(--table-stripe) !important;
}

.f-nome { font-weight: 400; font-size: 0.82rem; text-transform: none !important; }

.f-multi-tag {
  align-self: flex-start;
  font-size: 0.65rem !important;
  margin-top: 0.1rem;
  height: auto;
  padding: 0.1rem 0.5rem;
  border-radius: 99px;
}

.clickable-badge {
  cursor: pointer;
  transition: transform 0.1s;
}
.clickable-badge:hover { transform: scale(1.05); }


.f-date, .f-aut, .f-num, .f-val { font-size: 0.78rem; }
.f-date { text-transform: none !important; }
.f-num, .f-val { font-weight: 500; }

.txt-center { text-align: center !important; }

.f-days-badge {
  display: inline-block;
  padding: 0.25rem 0.65rem;
  border-radius: 6px;
  font-size: 0.82rem;
  font-weight: 700;
}

/* 10 Degraus de Risco Térmico Descritivos (Dias após Óbito) */
.d-risk-0-7d    { background: color-mix(in srgb, var(--risk-death-0-7d) 15%, transparent);    color: var(--risk-death-0-7d);    border: 1px solid color-mix(in srgb, var(--risk-death-0-7d) 30%, transparent); }
.d-risk-8-15d   { background: color-mix(in srgb, var(--risk-death-8-15d) 15%, transparent);   color: var(--risk-death-8-15d);   border: 1px solid color-mix(in srgb, var(--risk-death-8-15d) 30%, transparent); }
.d-risk-16-30d  { background: color-mix(in srgb, var(--risk-death-16-30d) 15%, transparent);  color: var(--risk-death-16-30d);  border: 1px solid color-mix(in srgb, var(--risk-death-16-30d) 30%, transparent); }
.d-risk-31-60d  { background: color-mix(in srgb, var(--risk-death-31-60d) 15%, transparent);  color: var(--risk-death-31-60d);  border: 1px solid color-mix(in srgb, var(--risk-death-31-60d) 30%, transparent); }
.d-risk-61-120d { background: color-mix(in srgb, var(--risk-death-61-120d) 15%, transparent); color: var(--risk-death-61-120d); border: 1px solid color-mix(in srgb, var(--risk-death-61-120d) 30%, transparent); }
.d-risk-121-240d{ background: color-mix(in srgb, var(--risk-death-121-240d) 15%, transparent);color: var(--risk-death-121-240d);border: 1px solid color-mix(in srgb, var(--risk-death-121-240d) 30%, transparent); }
.d-risk-241-1y  { background: color-mix(in srgb, var(--risk-death-241-1y) 15%, transparent);   color: var(--risk-death-241-1y);   border: 1px solid color-mix(in srgb, var(--risk-death-241-1y) 30%, transparent); }
.d-risk-1-2y    { background: color-mix(in srgb, var(--risk-death-1-2y) 15%, transparent);    color: var(--risk-death-1-2y);    border: 1px solid color-mix(in srgb, var(--risk-death-1-2y) 30%, transparent); font-weight: 800; }
.d-risk-2-3y    { background: color-mix(in srgb, var(--risk-death-2-3y) 15%, transparent);    color: var(--risk-death-2-3y);    border: 1px solid color-mix(in srgb, var(--risk-death-2-3y) 30%, transparent); font-weight: 800; }
.d-risk-over-3y { background: color-mix(in srgb, var(--risk-death-over-3y) 20%, transparent);  color: var(--risk-death-over-3y);  border: 1px solid color-mix(in srgb, var(--risk-death-over-3y) 40%, transparent); font-weight: 900; }

.f-cpf-cell { font-size: 0.75rem; color: var(--text-secondary); }
.f-fonte { font-size: 0.72rem; color: var(--text-secondary); }

/* ── Linha de cabeçalho do grupo (por falecido) - Estilo Relatório de Mesa (Neutro Ultra-Suave) ── */
.f-group-header td {
  background: color-mix(in srgb, var(--primary-color) 8%, var(--card-bg)) !important;
  border-top: 1px solid var(--tabs-border) !important;
  border-bottom: 1px solid var(--tabs-border) !important;
  padding: 0.5rem 1rem !important;
  font-size: 0.72rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--text-color) !important;
  font-weight: 500;
}

.f-group-cpf {
  font-weight: 700;
  margin-right: 0.75rem;
  color: var(--text-color);
}

.f-group-nome {
  color: var(--text-color);
  opacity: 0.9;
}

.f-group-sep {
  margin: 0 0.5rem;
  opacity: 0.3;
}

.f-group-meta {
  font-weight: 600;
  color: var(--text-secondary);
}

/* ── Linha de subtotal por falecido ── */
.f-subtotal-row td {
  background: transparent;
  border-top: 1px solid var(--tabs-border);
  border-bottom: 2px solid var(--tabs-border);
  padding: 0.45rem 1rem;
}

.f-subtotal-label {
  font-size: 0.72rem;
  font-weight: 500;
  text-transform: none !important;
  letter-spacing: 0.04em;
  color: var(--text-secondary);
  text-align: right;
}

.f-subtotal-val {
  font-weight: 500 !important;
  color: var(--text-secondary) !important;
}

/* ── Total geral (tfoot) ── */
.f-grand-total td {
  background: color-mix(in srgb, var(--bg-color) 95%, var(--text-color) 5%);
  border-top: 2px solid var(--tabs-border);
  padding: 0.75rem 1rem;
  font-size: 0.78rem;
  font-weight: 500;
  color: var(--text-color);
}

.f-grand-total .f-val {
  color: var(--text-secondary) !important;
  font-size: 0.88rem;
}

/* Ranking Panel - PRO Design */
.falecidos-ranking-panel {
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  border-radius: 12px;
  padding: 0.75rem;
  margin-top: 0.75rem;
  box-shadow: 0 4px 15px rgba(0,0,0,0.1);
}

.ranking-header-flex {
  margin-bottom: 0.6rem;
  border-bottom: 1px solid var(--tabs-border);
  padding-bottom: 0.5rem;
}

.ranking-header-flex .title-wrap {
  display: flex;
  align-items: center;
  gap: 0.6rem;
  font-size: 0.85rem;
  font-weight: 600;
  text-transform: uppercase;
  color: var(--text-color);
  letter-spacing: 0.05em;
  opacity: 0.85;
}

.title-wrap i {
  color: var(--primary-color);
  font-size: 1.1rem;
}

.ranking-subtitle {
  font-size: 0.72rem;
  color: var(--text-muted);
  margin-top: 0.3rem;
  margin-left: 1.7rem;
}

.pro-ranking-list {
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
}

.pro-ranking-item {
  display: flex;
  align-items: center;
  gap: 1rem;
  padding: 0.5rem 0.75rem;
  background: color-mix(in srgb, var(--text-color) 2%, transparent);
  border: 1px solid color-mix(in srgb, var(--text-color) 6%, transparent);
  border-radius: 8px;
  transition: none;
}


.rank-badge {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 32px;
  height: 32px;
  background: color-mix(in srgb, var(--text-color) 6%, transparent);
  color: var(--text-secondary);
  font-weight: 800;
  font-size: 0.75rem;
  border-radius: 6px;
}

/* Podium Colors (Contrast-safe for both Light & Dark modes) */
.rank-1 { background: color-mix(in srgb, #D4AF37 12%, transparent); color: #D4AF37; border: 1px solid color-mix(in srgb, #D4AF37 40%, transparent); }
.rank-2 { background: color-mix(in srgb, #9E9E9E 12%, transparent); color: #9E9E9E; border: 1px solid color-mix(in srgb, #9E9E9E 40%, transparent); }
.rank-3 { background: color-mix(in srgb, #B08D57 12%, transparent); color: #B08D57; border: 1px solid color-mix(in srgb, #B08D57 40%, transparent); }

.rank-info {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 0.4rem;
}

.rank-info-top {
  display: flex;
  align-items: baseline;
  gap: 0.75rem;
}

.rank-cnpj {
  font-size: 0.75rem;
  font-weight: 700;
  color: color-mix(in srgb, var(--text-color) 85%, transparent);
}

.ranking-expand-action {
  display: flex;
  justify-content: center;
  align-items: center;
  margin-top: 1rem;
  padding-top: 0.5rem;
  border-top: 1px dashed var(--tabs-border);
}

.ranking-expand-action .p-button {
  font-size: 0.72rem;
  font-weight: 700;
  letter-spacing: 0.05em;
  opacity: 0.7;
  transition: opacity 0.2s;
}

.ranking-expand-action .p-button:hover {
  opacity: 1;
}

.rank-name {
  font-size: 0.75rem;
  color: var(--text-secondary);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.rank-geo {
  font-size: 0.65rem;
  color: var(--text-muted);
  display: flex;
  align-items: center;
  gap: 0.4rem;
  margin-top: -0.1rem;
  opacity: 0.85;
}

.rank-geo i {
  font-size: 0.6rem;
  color: var(--primary-color);
}

.rank-bar-wrapper {
  width: 100%;
  max-width: 300px;
}

.rank-bar-bg {
  height: 4px;
  background: color-mix(in srgb, var(--text-color) 10%, transparent);
  border-radius: 2px;
  overflow: hidden;
}

.rank-bar-fill {
  height: 100%;
  background: linear-gradient(90deg, var(--risk-medium), var(--risk-high));
  border-radius: 2px;
}

.rank-metrics {
  display: flex;
  align-items: baseline;
  gap: 0.4rem;
  text-align: right;
  min-width: 130px;
  justify-content: flex-end;
}

.metric-val {
  font-size: 1.1rem;
  font-weight: 800;
  color: var(--risk-high);
}

.metric-lbl {
  font-size: 0.65rem;
  color: var(--text-muted);
  text-transform: uppercase;
  letter-spacing: 0.5px;
}

.metric-pct {
  font-size: 0.75rem;
  font-weight: 700;
  color: var(--text-secondary);
}

.rank-action {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  margin-left: 0.5rem;
}


.rank-filter-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 0.35rem;
  padding: 0.35rem 0.75rem;
  height: 32px;
  border-radius: 6px;
  border: 1px solid color-mix(in srgb, var(--primary-color) 35%, transparent);
  background: color-mix(in srgb, var(--primary-color) 10%, transparent);
  backdrop-filter: blur(8px);
  -webkit-backdrop-filter: blur(8px);
  color: var(--primary-color);
  cursor: pointer;
  transition: all 0.2s ease;
  font-size: 0.75rem;
  font-weight: 600;
  white-space: nowrap;
  box-shadow: inset 0 1px 0 color-mix(in srgb, white 20%, transparent),
              0 2px 6px color-mix(in srgb, var(--primary-color) 10%, transparent);
}

.rank-filter-btn:hover {
  background: color-mix(in srgb, var(--primary-color) 20%, transparent);
  border-color: color-mix(in srgb, var(--primary-color) 60%, transparent);
  box-shadow: inset 0 1px 0 color-mix(in srgb, white 25%, transparent),
              0 4px 10px color-mix(in srgb, var(--primary-color) 18%, transparent);
}

.rank-filter-btn.active {
  background: color-mix(in srgb, var(--primary-color) 75%, transparent);
  backdrop-filter: blur(8px);
  -webkit-backdrop-filter: blur(8px);
  border-color: var(--primary-color);
  color: #fff;
  box-shadow: inset 0 1px 0 color-mix(in srgb, white 30%, transparent),
              0 4px 12px color-mix(in srgb, var(--primary-color) 35%, transparent);
}

.rank-open-btn {
  color: var(--status-info);
  border-color: color-mix(in srgb, var(--status-info) 35%, transparent);
  background: color-mix(in srgb, var(--status-info) 10%, transparent);
  box-shadow: inset 0 1px 0 color-mix(in srgb, white 15%, transparent),
              0 2px 6px color-mix(in srgb, var(--status-info) 12%, transparent);
}

.rank-open-btn:hover {
  color: var(--status-info);
  background: color-mix(in srgb, var(--status-info) 20%, transparent);
  border-color: color-mix(in srgb, var(--status-info) 60%, transparent);
  box-shadow: inset 0 1px 0 color-mix(in srgb, white 20%, transparent),
              0 4px 10px color-mix(in srgb, var(--status-info) 20%, transparent);
}

.filter-active-banner {
  display: flex;
  align-items: center;
  gap: 0.6rem;
  padding: 0.55rem 1rem;
  border-radius: 8px;
  background: color-mix(in srgb, var(--primary-color) 5%, transparent);
  border: 1px solid color-mix(in srgb, var(--primary-color) 15%, transparent);
  font-size: 0.82rem;
  color: var(--text-color);
  opacity: 0.9;
  margin-bottom: 0.75rem;
}

.filter-active-banner i {
  color: var(--primary-color);
  font-size: 0.85rem;
  opacity: 0.85;
}

.filter-clear-btn {
  display: inline-flex;
  align-items: center;
  gap: 0.3rem;
  margin-left: auto;
  padding: 0.25rem 0.7rem;
  border-radius: 6px;
  border: 1px solid color-mix(in srgb, var(--primary-color) 30%, transparent);
  background: transparent;
  color: var(--primary-color);
  font-size: 0.75rem;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.2s ease;
}

.filter-clear-btn:hover {
  background: color-mix(in srgb, var(--primary-color) 12%, transparent);
}

.tab-placeholder {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 1rem;
  min-height: 300px;
  color: var(--text-muted);
  opacity: 0.5;
}

.placeholder-icon {
  font-size: 3rem;
}

.tab-placeholder p {
  font-size: 0.875rem;
}
</style>
