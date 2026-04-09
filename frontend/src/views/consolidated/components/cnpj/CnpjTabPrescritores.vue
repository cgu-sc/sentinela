<script setup>
import { computed, watch, ref } from "vue";
import { usePrescritores } from "@/composables/usePrescritores";
import { useFormatting } from "@/composables/useFormatting";

const props = defineProps({
  cnpj: {
    type: String,
    required: true,
  },
});

const { prescritoresData, prescritoresLoading, fetchPrescritores } =
  usePrescritores();
const { formatCurrencyFull, formatNumberFull, formatarData } = useFormatting();

watch(
  () => props.cnpj,
  (newCnpj) => {
    if (newCnpj) {
      fetchPrescritores(newCnpj);
    }
  },
  { immediate: true },
);

// --- CÁLCULOS DOS KPIs ---
const summary = computed(() => prescritoresData.value?.summary || {});
const top20 = computed(() => prescritoresData.value?.top20 || []);

const concentracaoTop1 = computed(
  () => summary.value.pct_concentracao_top1 || 0,
);
const concentracaoTop5 = computed(
  () => summary.value.pct_concentracao_top5 || 0,
);

const valorTop1 = computed(() =>
  top20.value.length > 0 ? top20.value[0].vl_total_prescricoes || 0 : 0,
);
const valorTop5 = computed(() =>
  top20.value
    .slice(0, 5)
    .reduce((acc, curr) => acc + (curr.vl_total_prescricoes || 0), 0),
);

// Prescrição Intensiva (Robôs)
const qtdPrescrIntensivaLocal = computed(
  () =>
    summary.value.qtd_prescritores_robos ||
    top20.value.filter((m) => m.flag_robo > 0).length,
);
const qtdPrescrIntensivaOcultos = computed(
  () =>
    summary.value.qtd_prescritores_robos_ocultos ||
    top20.value.filter((m) => m.flag_robo_oculto > 0).length,
);

// CRMs Inválidos e Irregulares
const qtdCrmInvalido = computed(
  () =>
    summary.value.qtd_crm_invalido ??
    top20.value.filter((m) => m.flag_crm_invalido > 0).length,
);
const qtdPrescrAntesRegistro = computed(
  () =>
    summary.value.qtd_crm_antes_registro ??
    top20.value.filter((m) => m.flag_prescricao_antes_registro > 0).length,
);
const totalIrregularesCfm = computed(
  () => qtdCrmInvalido.value + qtdPrescrAntesRegistro.value,
);
const pctFraudeCrm = computed(
  () =>
    (summary.value.pct_valor_crm_invalido || 0) +
    (summary.value.pct_valor_crm_antes_registro || 0),
);
const valorFraudeCrm = computed(
  () =>
    (summary.value.vl_crm_invalido || 0) +
    (summary.value.vl_crm_antes_registro || 0),
);

// Multi-Farmácia (>70 estabelecimentos)
const qtdMultiFarmacia = computed(
  () =>
    summary.value.qtd_prescritores_multi_farmacia ??
    top20.value.filter((m) => m.qtd_estabelecimentos_atua > 70).length,
);

const qtdLancamentosAgrupados = computed(
  () =>
    summary.value.qtd_prescritores_conc_temporal ||
    top20.value.filter((m) => m.alerta2_tempo_concentrado || m.alerta2).length,
);

const qtdAcima400km = computed(
  () => top20.value.filter((m) => m.alerta5_geografico).length,
);

const formatPct = (val) =>
  val != null ? `${Number(val).toFixed(2)}%` : "0.00%";
const filterOnlyIssues = ref(false);
const activeKpiFilter = ref(null);

const kpiFilters = {
  top1: (m) => m.id_medico === top20.value[0]?.id_medico,
  top5: (m) => top20.value.slice(0, 5).some((t) => t.id_medico === m.id_medico),
  agrupamento: (m) => !!(m.alerta2_tempo_concentrado || m.alerta2),
  intensiva_local: (m) => m.flag_robo > 0,
  intensiva_brasil: (m) => m.flag_robo_oculto > 0,
  multi_farmacia: (m) => m.qtd_estabelecimentos_atua > 70,
  fraude_crm: (m) =>
    m.flag_crm_invalido > 0 || m.flag_prescricao_antes_registro > 0,
  distancia: (m) => !!m.alerta5_geografico,
};

const kpiFilterLabels = {
  top1: "Concentração TOP 1",
  top5: "Concentração TOP 5",
  agrupamento: "Lançamentos em Sequência",
  intensiva_local: ">30 Prescrições/Dia neste CNPJ",
  intensiva_brasil: ">30 Prescrições/Dia Brasil",
  multi_farmacia: "Multi-Farmácia",
  fraude_crm: "Fraudes CRM",
  distancia: "Distância (>400km)",
};

function setKpiFilter(key) {
  if (activeKpiFilter.value === key) {
    activeKpiFilter.value = null;
  } else {
    activeKpiFilter.value = key;
    filterOnlyIssues.value = false;
  }
}

function clearFilters() {
  activeKpiFilter.value = null;
  filterOnlyIssues.value = false;
}

const hasAnyIssue = (m) =>
  m.flag_robo > 0 ||
  m.flag_robo_oculto > 0 ||
  m.alerta2_tempo_concentrado ||
  m.alerta2 ||
  m.flag_crm_invalido > 0 ||
  m.flag_prescricao_antes_registro > 0 ||
  m.alerta5_geografico ||
  m.qtd_estabelecimentos_atua === 1;

const filteredTop20 = computed(() => {
  let list = top20.value;
  if (filterOnlyIssues.value) list = list.filter(hasAnyIssue);
  if (activeKpiFilter.value && kpiFilters[activeKpiFilter.value]) {
    list = list.filter(kpiFilters[activeKpiFilter.value]);
  }
  return list;
});

defineExpose({
  getSummary: () => summary.value,
  getTop20: () => top20.value,
  getKpis: () => ({
    concentracaoTop1: concentracaoTop1.value,
    concentracaoTop5: concentracaoTop5.value,
    qtdLancamentosAgrupados: qtdLancamentosAgrupados.value,
    qtdPrescrIntensivaLocal: qtdPrescrIntensivaLocal.value,
    qtdPrescrIntensivaOcultos: qtdPrescrIntensivaOcultos.value,
    qtdMultiFarmacia: qtdMultiFarmacia.value,
    totalIrregularesCfm: totalIrregularesCfm.value,
    qtdCrmInvalido: qtdCrmInvalido.value,
    qtdPrescrAntesRegistro: qtdPrescrAntesRegistro.value,
    valorTop1: valorTop1.value,
    valorTop5: valorTop5.value,
    medianaTop5Reg:
      summary.value.mediana_concentracao_top5_reg ??
      summary.value.mediana_concentracao_top5_br ??
      40,
    qtdAcima400km: qtdAcima400km.value,
  }),
});
</script>

<template>
  <div class="crm-tab-container">
    <div v-if="prescritoresLoading" class="loading-state">
      <i class="pi pi-spinner pi-spin"></i>
      <p>Carregando análise de prescritores...</p>
    </div>

    <div
      v-else-if="!prescritoresData || top20.length === 0"
      class="empty-state"
    >
      <i class="pi pi-users empty-icon"></i>
      <p>
        Não há dados de prescrições registrados para este estabelecimento nos
        meses selecionados.
      </p>
    </div>

    <div v-else class="content-wrapper">
      <!-- 1. KPIs -->
      <div class="no-padding-mobile">
        <div class="alerts-kpi-grid">
          <!-- Concentração TOP 1 -->
          <div
            class="alert-kpi-card"
            :class="[
              concentracaoTop1 > 40
                ? 'highlight-red'
                : concentracaoTop1 > 20
                  ? 'highlight-orange'
                  : '',
              activeKpiFilter === 'top1' ? 'kpi-active' : '',
            ]"
            @click="setKpiFilter('top1')"
          >
            <div class="alert-kpi-header">
              <span class="alert-kpi-label">TOP 1 CRM - VOLUME R$</span>
              <i
                class="pi pi-info-circle kpi-info-icon"
                v-tooltip.top="
                  'Percentual de participação do maior prescritor no volume total da farmácia.'
                "
              />
            </div>
            <div class="alert-kpi-body">
              <span class="alert-kpi-val">{{
                formatPct(concentracaoTop1)
              }}</span>
              <span class="alert-kpi-hint">
                CRM: {{ summary.id_top1_prescritor || "ND" }}
                <strong style="color: var(--text-color)">
                  · {{ formatCurrencyFull(valorTop1) }}</strong
                >
              </span>
            </div>
          </div>

          <!-- Concentração TOP 5 -->
          <div
            class="alert-kpi-card"
            :class="[
              concentracaoTop5 > 70
                ? 'highlight-red'
                : concentracaoTop5 > 50
                  ? 'highlight-orange'
                  : '',
              activeKpiFilter === 'top5' ? 'kpi-active' : '',
            ]"
            @click="setKpiFilter('top5')"
          >
            <div class="alert-kpi-header">
              <span class="alert-kpi-label">TOP 5 CRMs - VOLUME R$</span>
              <i
                class="pi pi-info-circle kpi-info-icon"
                v-tooltip.top="
                  'Percentual de participação dos 5 maiores prescritores acumulados.'
                "
              />
            </div>
            <div class="alert-kpi-body">
              <span class="alert-kpi-val">{{
                formatPct(concentracaoTop5)
              }}</span>
              <span class="alert-kpi-hint">
                Mediana Região:
                {{
                  formatPct(
                    summary.mediana_concentracao_top5_reg ||
                      summary.mediana_concentracao_top5_br ||
                      40,
                  )
                }}
                <strong style="color: var(--text-color)">
                  · {{ formatCurrencyFull(valorTop5) }}</strong
                >
              </span>
            </div>
          </div>

          <!-- Agrupamento de Lançamentos -->
          <div
            class="alert-kpi-card"
            :class="[
              qtdLancamentosAgrupados > 0 ? 'highlight-green' : '',
              activeKpiFilter === 'agrupamento' ? 'kpi-active' : '',
            ]"
            @click="setKpiFilter('agrupamento')"
          >
            <div class="alert-kpi-header">
              <span class="alert-kpi-label">LANÇAMENTOS EM SEQUENCIA</span>
              <i
                class="pi pi-info-circle kpi-info-icon"
                v-tooltip.top="
                  'Médicos que emitiram todas as suas prescrições em um curtíssimo espaço de tempo.'
                "
              />
            </div>
            <div class="alert-kpi-body">
              <span class="alert-kpi-val">{{ qtdLancamentosAgrupados }}</span>
              <span class="alert-kpi-hint"
                >Muitas Autorizações em Intervalo Curto</span
              >
            </div>
          </div>

          <!-- Prescrição Intensiva Local -->
          <div
            class="alert-kpi-card"
            :class="[
              qtdPrescrIntensivaLocal > 0 ? 'highlight-red' : '',
              activeKpiFilter === 'intensiva_local' ? 'kpi-active' : '',
            ]"
            @click="setKpiFilter('intensiva_local')"
          >
            <div class="alert-kpi-header">
              <span class="alert-kpi-label"
                >>30 PRESCRIÇÕES/DIA NESTE CNPJ</span
              >
              <i
                class="pi pi-info-circle kpi-info-icon"
                v-tooltip.top="
                  'Médicos que emitiram mais de 30 prescrições por dia considerando apenas as vendas desta unidade.'
                "
              />
            </div>
            <div class="alert-kpi-body">
              <span class="alert-kpi-val">{{ qtdPrescrIntensivaLocal }}</span>
              <span class="alert-kpi-hint">Na unidade local</span>
            </div>
          </div>

          <!-- Prescrição Intensiva Rede -->
          <div
            class="alert-kpi-card"
            :class="[
              qtdPrescrIntensivaOcultos > 0 ? 'highlight-orange' : '',
              activeKpiFilter === 'intensiva_brasil' ? 'kpi-active' : '',
            ]"
            @click="setKpiFilter('intensiva_brasil')"
          >
            <div class="alert-kpi-header">
              <span class="alert-kpi-label">>30 PRESCRIÇÕES/DIA BRASIL</span>
              <i
                class="pi pi-info-circle kpi-info-icon"
                v-tooltip.top="
                  'Médicos atuando com volume aceitável aqui, mas que emitem mais de 30 prescrições/dia se somadas todas as farmácias do Brasil (Robô Oculto).'
                "
              />
            </div>
            <div class="alert-kpi-body">
              <span class="alert-kpi-val">{{ qtdPrescrIntensivaOcultos }}</span>
              <span class="alert-kpi-hint">Soma de todo o Brasil</span>
            </div>
          </div>

          <!-- Multi-Farmácia (>70) -->
          <div
            class="alert-kpi-card"
            :class="[
              qtdMultiFarmacia > 0 ? 'highlight-purple' : '',
              activeKpiFilter === 'multi_farmacia' ? 'kpi-active' : '',
            ]"
            @click="setKpiFilter('multi_farmacia')"
          >
            <div class="alert-kpi-header">
              <span class="alert-kpi-label">MULTI-FARMÁCIA</span>
              <i
                class="pi pi-info-circle kpi-info-icon"
                v-tooltip.top="
                  'Médicos com atuação simultânea em mais de 70 estabelecimentos.'
                "
              />
            </div>
            <div class="alert-kpi-body">
              <span class="alert-kpi-val">{{ qtdMultiFarmacia }}</span>
              <span class="alert-kpi-hint"
                >CRMs em > 70 farmácias distintas</span
              >
            </div>
          </div>

          <!-- Fraudes CRM -->
          <div
            class="alert-kpi-card"
            :class="[
              totalIrregularesCfm > 0 ? 'highlight-red highlight-fraude' : '',
              activeKpiFilter === 'fraude_crm' ? 'kpi-active' : '',
            ]"
            @click="setKpiFilter('fraude_crm')"
          >
            <div class="alert-kpi-header">
              <span class="alert-kpi-label">FRAUDES CRM</span>
              <i
                class="pi pi-info-circle kpi-info-icon"
                v-tooltip.top="
                  'Fonte: CFM. CRMs inexistentes ou vendas antes do registro oficial.'
                "
              />
            </div>
            <div class="alert-kpi-body">
              <div class="alert-kpi-val-row">
                <span class="alert-kpi-val">{{ totalIrregularesCfm }}</span>
                <span class="alert-kpi-val-sub"
                  >{{ qtdCrmInvalido }} Inexistentes |
                  {{ qtdPrescrAntesRegistro }} Irregulares</span
                >
              </div>
              <span class="alert-kpi-hint">
                <strong style="color: var(--risk-high)">
                  {{ formatCurrencyFull(valorFraudeCrm) }} ({{
                    formatPct(pctFraudeCrm)
                  }})
                </strong>
                da produção
              </span>
            </div>
          </div>

          <!-- Alerta >400km -->
          <div
            class="alert-kpi-card"
            :class="[
              qtdAcima400km > 0 ? 'highlight-purple-geo' : '',
              activeKpiFilter === 'distancia' ? 'kpi-active' : '',
            ]"
            @click="setKpiFilter('distancia')"
          >
            <div class="alert-kpi-header">
              <span class="alert-kpi-label">DISTÂNCIA (>400KM)</span>
              <i
                class="pi pi-info-circle kpi-info-icon"
                v-tooltip.top="
                  'Médicos atuando em farmácias com mais de 400km de distância.'
                "
              />
            </div>
            <div class="alert-kpi-body">
              <span class="alert-kpi-val">{{ qtdAcima400km }}</span>
              <span class="alert-kpi-hint"
                >Prescrições em Locais Distantes</span
              >
            </div>
          </div>
        </div>
      </div>

      <!-- 2. TOP 20 CRMs (TABELA DETALHADA) -->
      <div class="section-container">
        <div
          class="section-title"
          style="border-bottom: none; margin-bottom: 0"
        >
          <div
            style="display: flex; align-items: center; gap: 1.5rem; width: 100%"
          >
            <div style="display: flex; align-items: center; gap: 0.75rem">
              <i class="pi pi-users" />
              <span>CRMs DE INTERESSE - DETALHAMENTO</span>
            </div>

            <div class="filter-controls">
              <label class="filter-toggle">
                <input type="checkbox" v-model="filterOnlyIssues" />
                <span class="toggle-slider"></span>
                <span class="toggle-label">Apenas com Alertas / Anomalias</span>
              </label>
            </div>
          </div>
        </div>
        <p
          class="subtitle"
          style="
            padding-left: 1.75rem;
            margin-top: -0.5rem;
            margin-bottom: 1rem;
          "
        >
          Detalhamento dos médicos que mais aprovaram medicamentos nesta
          unidade, ordenados pelo financeiro.
          <span v-if="activeKpiFilter" class="filter-badge">
            <i class="pi pi-filter-fill"></i>
            {{ kpiFilterLabels[activeKpiFilter] }} —
            {{ filteredTop20.length }} de {{ top20.length }}
            <button class="clear-filter-btn" @click.stop="clearFilters">
              <i class="pi pi-times"></i> Limpar filtro
            </button>
          </span>
          <span
            v-else-if="filterOnlyIssues && filteredTop20.length < top20.length"
            class="text-orange"
            style="font-weight: 600; margin-left: 8px"
          >
            (Filtrado: exibindo {{ filteredTop20.length }} de
            {{ top20.length }})
          </span>
        </p>

        <div class="table-responsive">
          <table class="ind-table premium-table row-hover">
            <thead class="sticky-thead">
              <tr>
                <th>CRM / Médico</th>
                <th>Status / Alertas</th>
                <th class="col-right">Qtd. Total</th>
                <th class="col-right">Valor Total</th>
                <th class="col-center">% Vendas</th>
                <th class="col-center">% Acum.</th>
                <th class="col-center">Rede (Network)</th>
                <th class="col-center">Presc/Dia (Local)</th>
                <th class="col-center">Presc/Dia (Brasil)</th>
                <th class="col-center">% Exclusividade</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="(m, i) in filteredTop20"
                :key="i"
              >
                <td>
                  <div class="med-id">{{ m.id_medico }}</div>
                  <div class="med-sub">
                    Registro:
                    {{
                      m.dt_inscricao_crm
                        ? formatarData(m.dt_inscricao_crm)
                        : "ND"
                    }}
                  </div>
                </td>
                <td class="flags-cell">
                  <div class="tags-container">
                    <span v-if="m.flag_robo" class="issue-tag red" v-tooltip.top="'>30 Prescrições/dia neste CNPJ'">
                      <i class="pi pi-history"></i> >30 Presc/dia (Local)
                    </span>
                    <span v-if="m.flag_robo_oculto && !m.flag_robo" class="issue-tag orange" v-tooltip.top="'>30 Prescrições/dia em todo o Brasil (Robô Oculto)'">
                      <i class="pi pi-globe"></i> >30 Presc/dia BR
                    </span>
                    <span v-if="m.alerta2_tempo_concentrado || m.alerta2" class="issue-tag green-ok" v-tooltip.top="'Lançamentos em sequência (anomalia temporal)'">
                      <i class="pi pi-stopwatch"></i> Sequencial
                    </span>
                    <span v-if="m.flag_crm_invalido" class="issue-tag dark-red" v-tooltip.top="'CRM não encontrado na base de dados oficial do Conselho Federal de Medicina (CFM)'">
                      <i class="pi pi-ban"></i> CRM Inexistente
                    </span>
                    <span v-if="m.flag_prescricao_antes_registro" class="issue-tag dark-red" v-tooltip.top="'Venda anterior ao Registro oficial no CFM'">
                      <i class="pi pi-calendar-times"></i> CRM Irregular
                    </span>
                    <span v-if="m.qtd_estabelecimentos_atua === 1" class="issue-tag orange" v-tooltip.top="'Médico prescreveu exclusivamente para este CNPJ no período'">
                      <i class="pi pi-lock"></i> CNPJ Exclusivo
                    </span>
                    <span v-if="m.alerta5_geografico" class="issue-tag purple-geo" v-tooltip.top="'Distância superior a 400km entre prescritor e farmácia'">
                      <i class="pi pi-map-marker"></i> >400km
                    </span>
                    <span v-if="m.qtd_estabelecimentos_atua >= 70" class="issue-tag blue-network" v-tooltip.top="'Médico com atuação em rede ampla (mais de 70 farmácias distintas)'">
                      <i class="pi pi-share-alt"></i> Multi-Farmácia
                    </span>
                    <i
                      v-if="
                        !m.flag_robo &&
                        !m.flag_robo_oculto &&
                        !m.flag_crm_invalido &&
                        !m.flag_prescricao_antes_registro &&
                        m.pct_volume_aqui_vs_total <= 90 &&
                        !m.alerta5_geografico &&
                        m.qtd_estabelecimentos_atua < 70
                      "
                      class="pi pi-check-circle"
                      style="color: var(--text-muted); font-size: 0.85rem;"
                      v-tooltip.top="'Sem ocorrências identificadas'"
                    />
                  </div>
                </td>
                <td class="col-right">
                  {{ formatNumberFull(m.nu_prescricoes) }}
                </td>
                <td class="col-right text-primary">
                  {{ formatCurrencyFull(m.vl_total_prescricoes) }}
                </td>
                <td class="col-center">
                  <div class="bar-container">
                    <div
                      class="bar-fill"
                      :style="{
                        width: Math.min(m.pct_participacao, 100) + '%',
                      }"
                    ></div>
                    <span class="bar-text">{{
                      formatPct(m.pct_participacao)
                    }}</span>
                  </div>
                </td>
                <td class="col-center">
                  <div class="bar-container">
                    <div
                      class="bar-fill"
                      :style="{
                        width: Math.min(m.pct_acumulado, 100) + '%',
                      }"
                    ></div>
                    <span class="bar-text text-sm">{{
                      formatPct(m.pct_acumulado)
                    }}</span>
                  </div>
                </td>
                <td class="col-center">
                  <span
                    :class="{
                      'text-purple': m.qtd_estabelecimentos_atua > 50,
                    }"
                    >{{ m.qtd_estabelecimentos_atua }}</span
                  >
                  farm.
                </td>
                <td class="col-center">
                  <span
                    :class="{ 'text-red': m.nu_prescricoes_dia > 30 }"
                    >{{ formatNumberFull(m.nu_prescricoes_dia) }}</span
                  >/dia
                </td>
                <td class="col-center">
                  <span
                    :class="{
                      'text-red': m.prescricoes_dia_total_brasil > 30,
                    }"
                    >{{
                      formatNumberFull(m.prescricoes_dia_total_brasil)
                    }}</span
                  >/dia
                </td>
                <td class="col-center">
                  <span
                    :class="{
                      'text-purple': m.pct_volume_aqui_vs_total > 90,
                    }"
                    >{{ formatPct(m.pct_volume_aqui_vs_total) }}</span
                  >
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
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
.empty-icon {
  font-size: 3rem;
  margin-bottom: 1rem;
  opacity: 0.5;
}
.loading-state i {
  font-size: 2rem;
  margin-bottom: 1rem;
  color: var(--primary-color);
}

.content-wrapper {
  display: flex;
  flex-direction: column;
  gap: 1rem;
  width: 100%;
  align-items: stretch;
}

.no-padding-mobile {
  border: none !important;
  background: transparent !important;
  padding: 0 !important;
}

.section-title {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  font-size: 0.85rem;
  font-weight: 700;
  text-transform: uppercase;
  color: var(--text-color);
  margin-bottom: 1rem;
  letter-spacing: 0.05em;
  border-bottom: 1px solid var(--tabs-border);
  padding-bottom: 0.5rem;
  width: 100%;
}

.section-title i {
  color: var(--primary-color);
  font-size: 1rem;
}

.alerts-kpi-grid {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 1rem;
  margin-bottom: 0;
}

.alert-kpi-card {
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
  padding: 1.25rem;
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  border-left: 3px solid var(--card-border);
  border-radius: 12px;
  transition: all 0.2s ease;
  cursor: pointer;
  user-select: none;
}

.alert-kpi-card:hover {
  transform: translateY(-2px);
  box-shadow: 0 4px 15px rgba(0, 0, 0, 0.08);
}

/* Hovers específicos por categoria */
.alert-kpi-card.highlight-red:hover { background: color-mix(in srgb, var(--risk-high) 4%, var(--card-bg)); }
.alert-kpi-card.highlight-orange:hover { background: color-mix(in srgb, var(--risk-medium) 4%, var(--card-bg)); }
.alert-kpi-card.highlight-green:hover { background: color-mix(in srgb, var(--risk-indicator-normal) 4%, var(--card-bg)); }
.alert-kpi-card.highlight-purple:hover { background: color-mix(in srgb, #3b82f6 4%, var(--card-bg)); }
.alert-kpi-card.highlight-purple-geo:hover { background: color-mix(in srgb, #8b5cf6 4%, var(--card-bg)); }

/* Estado ativo (Clicado) — Sincronizado com a cor da categoria */
.alert-kpi-card.kpi-active {
  transform: translateY(-1px);
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
}

.alert-kpi-card.highlight-red.kpi-active {
  background: color-mix(in srgb, var(--risk-high) 10%, var(--card-bg));
  border-color: var(--risk-high) !important;
}
.alert-kpi-card.highlight-orange.kpi-active {
  background: color-mix(in srgb, var(--risk-medium) 10%, var(--card-bg));
  border-color: var(--risk-medium) !important;
}
.alert-kpi-card.highlight-green.kpi-active {
  background: color-mix(in srgb, var(--risk-indicator-normal) 10%, var(--card-bg));
  border-color: var(--risk-indicator-normal) !important;
}
.alert-kpi-card.highlight-purple.kpi-active {
  background: color-mix(in srgb, #3b82f6 10%, var(--card-bg));
  border-color: #3b82f6 !important;
}
.alert-kpi-card.highlight-purple-geo.kpi-active {
  background: color-mix(in srgb, #8b5cf6 10%, var(--card-bg));
  border-color: #8b5cf6 !important;
}

.filter-badge {
  display: inline-flex;
  align-items: center;
  gap: 0.4rem;
  font-size: 0.78rem;
  font-weight: 600;
  color: var(--primary-color);
  margin-left: 0.5rem;
}

.filter-badge i {
  font-size: 0.75rem;
}

.clear-filter-btn {
  display: inline-flex;
  align-items: center;
  gap: 0.25rem;
  margin-left: 0.25rem;
  padding: 0.15rem 0.5rem;
  font-size: 0.72rem;
  font-weight: 600;
  color: var(--text-secondary);
  background: color-mix(in srgb, var(--text-color) 6%, var(--tabs-bg));
  border: 1px solid var(--tabs-border);
  border-radius: 4px;
  cursor: pointer;
  transition: all 0.15s ease;
}

.clear-filter-btn:hover {
  background: color-mix(in srgb, var(--text-color) 12%, var(--tabs-bg));
  color: var(--text-color);
}

.alert-kpi-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.alert-kpi-label {
  font-size: 0.7rem;
  font-weight: 700;
  color: var(--text-secondary);
  text-transform: uppercase;
  letter-spacing: 0.05em;
  opacity: 0.8;
}

.kpi-info-icon {
  font-size: 0.8rem;
  color: var(--text-muted);
  cursor: help;
  transition: color 0.15s;
}

.kpi-info-icon:hover {
  color: var(--primary-color);
}

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
  font-size: 1.5rem;
  font-weight: 800;
  color: var(--text-color);
  line-height: 1;
}

.alert-kpi-val-sub {
  font-size: 0.7rem;
  font-weight: 600;
  color: var(--text-color);
  opacity: 0.7;
}

.alert-kpi-hint {
  font-size: 0.72rem;
  color: var(--text-muted);
  font-weight: 400;
}

/* Semafórica de Risco nos Cards (Apenas Borda) */
.highlight-red {
  border-left: 3px solid var(--risk-high) !important;
}


.highlight-orange {
  border-left: 3px solid var(--risk-medium) !important;
}

.highlight-purple {
  border-left: 3px solid #3b82f6 !important;
}

.highlight-purple-geo {
  border-left: 3px solid #8b5cf6 !important;
}

.highlight-green {
  border-left: 3px solid var(--risk-indicator-normal) !important;
}

/* Filtro Estilizado */
.filter-controls {
  display: flex;
  align-items: center;
  gap: 1rem;
}

.filter-toggle {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  cursor: pointer;
  user-select: none;
  font-size: 0.75rem;
  text-transform: none;
  font-weight: 600;
  color: var(--text-secondary);
}

.filter-toggle input {
  display: none;
}

.toggle-slider {
  position: relative;
  width: 32px;
  height: 18px;
  background-color: var(--tabs-border);
  border: 1px solid var(--tabs-border);
  border-radius: 20px;
  transition: 0.3s;
}

.toggle-slider:before {
  content: "";
  position: absolute;
  height: 12px;
  width: 12px;
  left: 3px;
  bottom: 3px;
  background-color: white;
  border-radius: 50%;
  transition: 0.3s;
}

input:checked + .toggle-slider {
  background-color: var(--primary-color);
}

input:checked + .toggle-slider:before {
  transform: translateX(14px);
}

.toggle-label {
  letter-spacing: normal;
}

.highlight-yellow {
  border-left: 3px solid var(--risk-low) !important;
}

.text-red {
  color: var(--risk-critical) !important;
}

/* 2. SECTION & TABLES */
.section-container {
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  border-radius: 12px;
  padding: 1.25rem;
  width: 100%;
  box-sizing: border-box;
  overflow: hidden; /* Garante que o border-radius se aplique à tabela interna */
}

.section-header {
  padding: 1rem 1.25rem 0.25rem 1.25rem;
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  text-align: left;
  width: 100%;
}

.section-header h3 {
  margin: 0;
  font-size: 1rem;
  color: var(--text-color);
  font-weight: 700;
  line-height: normal;
}
.subtitle {
  margin: 0.25rem 0 0 0;
  font-size: 0.8rem;
  color: var(--text-muted);
}

.table-responsive {
  overflow-x: auto;
  border-top: 1px solid var(--tabs-border);
  border-bottom: 1px solid var(--tabs-border);
  min-height: 35rem;
}

.premium-table {
  width: 100%;
  border-collapse: collapse;
}

.premium-table th {
  padding: 0.65rem 0.5rem;
  background: transparent;
  color: var(--text-secondary);
  font-size: 0.72rem;
  font-weight: 500;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  border-bottom: 2px solid var(--tabs-border);
  text-align: center;
}

.premium-table th:first-child { text-align: left; }

.premium-table td {
  padding: 0.65rem 0.5rem;
  border-bottom: 1px solid var(--tabs-border);
  vertical-align: middle;
  color: var(--text-color);
  font-size: 0.78rem;
  text-transform: none !important;
}

/* Coluna de Status mais larga */
.premium-table th:nth-child(2),
.premium-table td:nth-child(2) {
  min-width: 320px;
  text-align: left;
}

.premium-table tbody tr:last-child td {
  border-bottom: none;
}

.premium-table.row-hover tbody tr:hover {
  background: var(--table-hover) !important;
  cursor: pointer;
}

.sticky-thead th {
  position: sticky;
  top: 0;
  z-index: 10; /* Aumentado para garantir que fique sobre o conteúdo */
  box-shadow: 0 2px 4px rgba(0, 0, 0, 0.2); /* Sombra para separar visualmente o header dos dados */
}

.col-center {
  text-align: center;
}
.col-right {
  text-align: right;
}

/* Table Specific Components */
.severe-row {
  background: color-mix(
    in srgb,
    var(--risk-critical) 4%,
    var(--bg-color)
  ) !important;
}

.med-id {
  font-weight: 500;
  font-size: 0.78rem;
  color: var(--text-color);
}
.med-sub {
  font-size: 0.72rem;
  color: var(--text-muted);
  font-weight: 400;
}

.mt-1 {
  margin-top: 0.25rem;
}
.mt-2 {
  margin-top: 0.5rem;
}
.mt-0 {
  margin-top: 0;
}

.tags-container {
  display: flex;
  flex-wrap: wrap;
  gap: 0.25rem;
}
.issue-tag {
  font-size: 0.7rem;
  font-weight: 500;
  padding: 0.2rem 0.6rem;
  border-radius: 6px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 0.3rem;
  white-space: nowrap;
  min-width: 85px;
  letter-spacing: normal;
  text-transform: none !important;
}
.issue-tag i {
  font-size: 0.7rem;
}
.issue-tag.red {
  background: color-mix(in srgb, var(--risk-high) 10%, var(--tabs-bg));
  color: var(--risk-high);
  border: 1px solid color-mix(in srgb, var(--risk-high) 20%, transparent);
}
.issue-tag.dark-red {
  background: color-mix(in srgb, var(--risk-high) 4%, var(--tabs-bg));
  color: color-mix(in srgb, var(--risk-high) 60%, var(--text-muted));
  border: 1px solid color-mix(in srgb, var(--risk-high) 10%, transparent);
  font-weight: 700;
}
.issue-tag.orange {
  background: color-mix(in srgb, var(--risk-medium) 10%, var(--tabs-bg));
  color: var(--risk-medium);
  border: 1px solid color-mix(in srgb, var(--risk-medium) 20%, transparent);
}
.issue-tag.yellow {
  background: color-mix(in srgb, var(--risk-low) 10%, var(--tabs-bg));
  color: var(--risk-low);
  border: 1px solid color-mix(in srgb, var(--risk-low) 20%, transparent);
}
.issue-tag.blue-network {
  background: color-mix(in srgb, #3b82f6 8%, var(--tabs-bg));
  color: #3b82f6;
  border: 1px solid color-mix(in srgb, #3b82f6 20%, transparent);
}
.issue-tag.purple-geo {
  background: color-mix(in srgb, #8b5cf6 8%, var(--tabs-bg));
  color: #8b5cf6;
  border: 1px solid color-mix(in srgb, #8b5cf6 20%, transparent);
}
.issue-tag.green-ok {
  background: color-mix(in srgb, var(--risk-indicator-normal) 10%, var(--tabs-bg));
  color: var(--risk-indicator-normal);
  border: 1px solid color-mix(in srgb, var(--risk-indicator-normal) 20%, transparent);
}

.bar-container {
  position: relative;
  height: 1.1rem; /* Levemente mais baixa */
  background: rgba(0, 0, 0, 0.05);
  border-radius: 4px;
  overflow: hidden;
  display: flex;
  align-items: center;
  min-width: 45px; /* Reduzido de 60 para 45 */
}
:global(.dark-mode) .bar-container {
  background: rgba(255, 255, 255, 0.1);
}
.bar-fill {
  position: absolute;
  top: 0;
  left: 0;
  bottom: 0;
  background: var(--primary-color);
  opacity: 0.2;
}
.bar-text {
  position: relative;
  z-index: 1;
  width: 100%;
  text-align: center;
  font-size: 0.78rem;
  font-weight: 500;
  color: var(--text-color);
  text-shadow: 0 0 2px var(--bg-color), 0 0 4px var(--bg-color);
}
</style>
