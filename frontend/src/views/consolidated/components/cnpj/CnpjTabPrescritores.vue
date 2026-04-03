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

const { prescritoresData, prescritoresLoading, fetchPrescritores } = usePrescritores();
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

const concentracaoTop1 = computed(() => summary.value.pct_concentracao_top1 || 0);
const concentracaoTop5 = computed(() => summary.value.pct_concentracao_top5 || 0);

const valorTop1 = computed(() => top20.value.length > 0 ? (top20.value[0].vl_total_prescricoes || 0) : 0);
const valorTop5 = computed(() => top20.value.slice(0, 5).reduce((acc, curr) => acc + (curr.vl_total_prescricoes || 0), 0));

// Prescrição Intensiva (Robôs)
const qtdPrescrIntensivaLocal = computed(() => summary.value.qtd_prescritores_robos || top20.value.filter(m => m.flag_robo > 0).length);
const qtdPrescrIntensivaOcultos = computed(() => summary.value.qtd_prescritores_robos_ocultos || top20.value.filter(m => m.flag_robo_oculto > 0).length);

// CRMs Inválidos e Irregulares
const qtdCrmInvalido = computed(() => summary.value.qtd_crm_invalido ?? top20.value.filter(m => m.flag_crm_invalido > 0).length);
const qtdPrescrAntesRegistro = computed(() => summary.value.qtd_crm_antes_registro ?? top20.value.filter(m => m.flag_prescricao_antes_registro > 0).length);
const totalIrregularesCfm = computed(() => qtdCrmInvalido.value + qtdPrescrAntesRegistro.value);
const pctFraudeCrm = computed(() => (summary.value.pct_valor_crm_invalido || 0) + (summary.value.pct_valor_crm_antes_registro || 0));
const valorFraudeCrm = computed(() => (summary.value.vl_crm_invalido || 0) + (summary.value.vl_crm_antes_registro || 0));

// Exclusividade
const maxExclusivos = computed(() => summary.value.max_exclusivos || Math.max(...top20.value.map(m => m.pct_volume_aqui_vs_total || 0), 0));
const qtdExclusivos = computed(() => top20.value.filter(m => m.qtd_estabelecimentos_atua === 1).length);

// Multi-Farmácia (>70 estabelecimentos)
const qtdMultiFarmacia = computed(() => summary.value.qtd_prescritores_multi_farmacia ?? top20.value.filter(m => m.qtd_estabelecimentos_atua > 70).length);
const multiFarmaciaDetalhe = computed(() => {
  const suspeitos = top20.value.filter(m => m.qtd_estabelecimentos_atua > 70).slice(0, 5);
  return suspeitos.map(m => `${m.id_medico} (${m.qtd_estabelecimentos_atua} farm.)`).join(', ');
});

// Detalhamentos textuais
const prescrIntensivaDetalhe = computed(() => {
  const suspeitos = top20.value.filter(m => m.prescricoes_dia_total_brasil > 30).slice(0, 5);
  return suspeitos.map(m => `${m.id_medico} (${Number(m.prescricoes_dia_total_brasil).toFixed(1)}/dia)`).join(', ');
});

const antesRegistroDetalhe = computed(() => {
  const suspeitos = top20.value.filter(m => m.flag_prescricao_antes_registro > 0).slice(0, 5);
  return suspeitos.map(m => `${m.id_medico}`).join(', ');
});

const agrupamentoDetalhe = computed(() => {
  const suspeitos = top20.value.filter(m => m.alerta2_tempo_concentrado || m.alerta2).slice(0, 5);
  return suspeitos.map(m => `${m.id_medico}`).join(', ');
});

const qtdLancamentosAgrupados = computed(() => summary.value.qtd_prescritores_conc_temporal || top20.value.filter(m => m.alerta2_tempo_concentrado || m.alerta2).length);

const qtdAcima400km = computed(() => top20.value.filter(m => m.alerta5_geografico).length);
const showAllPrescrIntensiva = ref(false);
const showAllAntesRegistro = ref(false);
const showAllAgrupamento = ref(false);
const showAllMultiFarmacia = ref(false);

const acima400kmDetalhe = computed(() => {
  const longe = top20.value.filter(m => m.alerta5_geografico).slice(0, 5);
  return longe.map(m => `${m.id_medico}`).join(', ');
});
const showAllAcima400km = ref(false);

const exclusividadeDetalhe = computed(() => {
  const suspeitos = top20.value.filter(m => m.qtd_estabelecimentos_atua === 1).slice(0, 5);
  return suspeitos.map(m => `${m.id_medico}`).join(', ');
});

const indiceRedeSuspeita = computed(() => summary.value.indice_rede_suspeita || 0);

const formatting = {
  formatPct: (val) => val != null ? `${Number(val).toFixed(2)}%` : '0.00%'
};
const formatPct = formatting.formatPct;
</script>

<template>
  <div class="crm-tab-container">
    <div v-if="prescritoresLoading" class="loading-state">
      <i class="pi pi-spinner pi-spin"></i>
      <p>Carregando análise de prescritores...</p>
    </div>

    <div v-else-if="!prescritoresData || top20.length === 0" class="empty-state">
      <i class="pi pi-users empty-icon"></i>
      <p>Não há dados de prescrições registrados para este estabelecimento nos meses selecionados.</p>
    </div>

    <div v-else class="content-wrapper">
      <!-- 1. RESUMO DE AUDITORIA (KPIs) -->
      <div class="section-title">
        <i class="pi pi-chart-bar" />
        <span>Resumo de Auditoria de CRMs</span>
      </div>
      <div class="no-padding-mobile">
        <div class="alerts-kpi-grid">
          <!-- Concentração TOP 1 -->
          <div class="alert-kpi-card" :class="concentracaoTop1 > 40 ? 'highlight-red' : (concentracaoTop1 > 20 ? 'highlight-orange' : '')">
            <div class="alert-kpi-header">
              <span class="alert-kpi-label">CONCENTRAÇÃO TOP 1</span>
              <i class="pi pi-info-circle kpi-info-icon" v-tooltip.top="'Percentual de participação do maior prescritor no volume total da farmácia.'" />
            </div>
            <div class="alert-kpi-body">
              <span class="alert-kpi-val">{{ formatPct(concentracaoTop1) }}</span>
              <span class="alert-kpi-hint">CRM: {{ summary.id_top1_prescritor || 'ND' }}<br/><strong style="color: var(--text-color)">{{ formatCurrencyFull(valorTop1) }}</strong></span>
            </div>
          </div>

          <!-- Concentração TOP 5 -->
          <div class="alert-kpi-card" :class="concentracaoTop5 > 70 ? 'highlight-red' : (concentracaoTop5 > 50 ? 'highlight-orange' : '')">
            <div class="alert-kpi-header">
              <span class="alert-kpi-label">CONCENTRAÇÃO TOP 5</span>
              <i class="pi pi-info-circle kpi-info-icon" v-tooltip.top="'Percentual de participação dos 5 maiores prescritores acumulados.'" />
            </div>
            <div class="alert-kpi-body">
              <span class="alert-kpi-val">{{ formatPct(concentracaoTop5) }}</span>
              <span class="alert-kpi-hint">Mediana BR: {{ formatPct(summary.mediana_concentracao_top5_br || 40) }}<br/><strong style="color: var(--text-color)">{{ formatCurrencyFull(valorTop5) }}</strong></span>
            </div>
          </div>

          <!-- Agrupamento de Lançamentos -->
          <div class="alert-kpi-card" :class="qtdLancamentosAgrupados > 0 ? 'highlight-red' : ''">
            <div class="alert-kpi-header">
              <span class="alert-kpi-label">LANÇAMENTOS EM SEQUENCIA</span>
              <i class="pi pi-info-circle kpi-info-icon" v-tooltip.top="'Médicos que emitiram todas as suas prescrições em um curtíssimo espaço de tempo.'" />
            </div>
            <div class="alert-kpi-body">
              <span class="alert-kpi-val">{{ qtdLancamentosAgrupados }}</span>
              <span class="alert-kpi-hint">Muitas Autorizações em Intervalo curto para o mesmo CRM</span>
            </div>
          </div>

          <!-- Prescrição Intensiva Local -->
          <div class="alert-kpi-card" :class="qtdPrescrIntensivaLocal > 0 ? 'highlight-orange' : ''">
            <div class="alert-kpi-header">
              <span class="alert-kpi-label">>30 PRESCRIÇÕES/DIA NESTE CNPJ</span>
              <i class="pi pi-info-circle kpi-info-icon" v-tooltip.top="'Médicos que emitiram mais de 30 prescrições por dia considerando apenas as vendas desta unidade.'" />
            </div>
            <div class="alert-kpi-body">
              <span class="alert-kpi-val">{{ qtdPrescrIntensivaLocal }}</span>
              <span class="alert-kpi-hint">Na unidade local</span>
            </div>
          </div>

          <!-- Prescrição Intensiva Rede -->
          <div class="alert-kpi-card" :class="qtdPrescrIntensivaOcultos > 0 ? 'highlight-orange' : ''">
            <div class="alert-kpi-header">
              <span class="alert-kpi-label">>30 PRESCRIÇÕES/DIA BRASIL</span>
              <i class="pi pi-info-circle kpi-info-icon" v-tooltip.top="'Médicos atuando com volume aceitável aqui, mas que emitem mais de 30 prescrições/dia se somadas todas as farmácias do Brasil (Robô Oculto).'" />
            </div>
            <div class="alert-kpi-body">
              <span class="alert-kpi-val">{{ qtdPrescrIntensivaOcultos }}</span>
              <span class="alert-kpi-hint">Soma de todo o Brasil</span>
            </div>
          </div>

          <!-- Multi-Farmácia (>70) -->
          <div class="alert-kpi-card" :class="qtdMultiFarmacia > 0 ? 'highlight-orange' : ''">
            <div class="alert-kpi-header">
              <span class="alert-kpi-label">MULTI-FARMÁCIA</span>
              <i class="pi pi-info-circle kpi-info-icon" v-tooltip.top="'Médicos com atuação simultânea em mais de 70 estabelecimentos.'" />
            </div>
            <div class="alert-kpi-body">
              <span class="alert-kpi-val">{{ qtdMultiFarmacia }}</span>
              <span class="alert-kpi-hint">CRMs com registro em > 70 farmácias distintas</span>
            </div>
          </div>

          <!-- Fraudes CRM -->
          <div class="alert-kpi-card" :class="(totalIrregularesCfm > 0) ? 'highlight-red' : ''">
            <div class="alert-kpi-header">
              <span class="alert-kpi-label">FRAUDES CRM</span>
              <i class="pi pi-info-circle kpi-info-icon" v-tooltip.top="'Fonte: CFM. CRMs inexistentes ou vendas antes do registro oficial.'" />
            </div>
            <div class="alert-kpi-body">
              <span class="alert-kpi-val">{{ totalIrregularesCfm }}</span>
              <span class="alert-kpi-hint">{{ qtdCrmInvalido }} Inválidos | {{ qtdPrescrAntesRegistro }} Irregulares<br/><strong style="color: var(--risk-critical)">{{ formatCurrencyFull(valorFraudeCrm) }} ({{ formatPct(pctFraudeCrm) }})</strong> da produção</span>
            </div>
          </div>

          <!-- Alerta >400km -->
          <div class="alert-kpi-card" :class="qtdAcima400km > 0 ? 'highlight-yellow' : ''">
            <div class="alert-kpi-header">
              <span class="alert-kpi-label">DISTÂNCIA (>400KM)</span>
              <i class="pi pi-info-circle kpi-info-icon" v-tooltip.top="'Médicos atuando em farmácias com mais de 400km de distância.'" />
            </div>
            <div class="alert-kpi-body">
              <span class="alert-kpi-val">{{ qtdAcima400km }}</span>
              <span class="alert-kpi-hint">CRMs com Prescrições simultâneas em locais distantes</span>
            </div>
          </div>
        </div>
      </div>

      <!-- ALERTAS IDENTIFICADOS (DETALHAMENTO TEXTUAL) -->
      <div v-if="prescrIntensivaDetalhe.length > 0 || antesRegistroDetalhe.length > 0 || multiFarmaciaDetalhe.length > 0 || agrupamentoDetalhe.length > 0 || qtdAcima400km > 0" class="alerts-details-section">
        <div class="section-title">
          <i class="pi pi-exclamation-triangle" />
          <span>Alertas Identificados (Detalhes)</span>
        </div>
        
        <div class="alerts-list">
           <div v-if="prescrIntensivaDetalhe.length > 0" class="alert-row">
              <span class="bullet-point bg-orange"></span>
              <div class="alert-row-content">
                 <p class="text-orange">>30 PRESCRIÇÕES/DIA considerando todos os CNPJs do BRASIL: <b>{{ qtdPrescrIntensivaLocal + qtdPrescrIntensivaOcultos }} médico(s)</b>.</p>
                 <p class="text-muted text-sm">• CRMs: 
                    <template v-if="!showAllPrescrIntensiva">
                       {{ prescrIntensivaDetalhe }}
                       <span v-if="top20.filter(m => m.prescricoes_dia_total_brasil > 30).length > 5">
                          e mais {{ top20.filter(m => m.prescricoes_dia_total_brasil > 30).length - 5 }} detectados no ranking. 
                          <a href="#" @click.prevent="showAllPrescrIntensiva = true" style="margin-left: 4px; text-decoration: underline; cursor: pointer;">Ver mais</a>
                       </span>
                    </template>
                    <template v-else>
                       {{ top20.filter(m => m.prescricoes_dia_total_brasil > 30).map(m => `${m.id_medico} (${Number(m.prescricoes_dia_total_brasil).toFixed(1)}/dia)`).join(', ') }}.
                       <a href="#" @click.prevent="showAllPrescrIntensiva = false" style="margin-left: 4px; text-decoration: underline; cursor: pointer;">Ver menos</a>
                    </template>
                 </p>
              </div>
           </div>

           <div v-if="qtdCrmInvalido > 0" class="alert-row">
              <span class="bullet-point bg-red"></span>
              <div class="alert-row-content">
                 <p class="text-red">CRMs Inválidos (Inexistentes no CFM): <b>{{ qtdCrmInvalido }} médico(s)</b>.</p>
              </div>
           </div>

           <div v-if="antesRegistroDetalhe.length > 0" class="alert-row">
              <span class="bullet-point bg-red"></span>
              <div class="alert-row-content">
                  <p class="text-red">CRMs Irregulares (Vendas antes do Registro no CRM): <b>{{ qtdPrescrAntesRegistro }} médico(s)</b>.</p>
                 <p class="text-muted text-sm">• CRMs: 
                    <template v-if="!showAllAntesRegistro">
                       {{ antesRegistroDetalhe }}
                       <span v-if="top20.filter(m => m.flag_prescricao_antes_registro > 0).length > 5">
                          e mais {{ top20.filter(m => m.flag_prescricao_antes_registro > 0).length - 5 }} detectados no ranking. 
                          <a href="#" @click.prevent="showAllAntesRegistro = true" style="margin-left: 4px; text-decoration: underline; cursor: pointer;">Ver mais</a>
                       </span>
                    </template>
                    <template v-else>
                       {{ top20.filter(m => m.flag_prescricao_antes_registro > 0).map(m => m.id_medico).join(', ') }}.
                       <a href="#" @click.prevent="showAllAntesRegistro = false" style="margin-left: 4px; text-decoration: underline; cursor: pointer;">Ver menos</a>
                    </template>
                 </p>
              </div>
           </div>

           <div v-if="agrupamentoDetalhe.length > 0" class="alert-row">
              <span class="bullet-point bg-red"></span>
              <div class="alert-row-content">
                 <p class="text-red">LANÇAMENTOS EM SEQUENCIA (Intervalos curtos): <b>{{ qtdLancamentosAgrupados }} médico(s)</b>.</p>
                 <p class="text-muted text-sm">• CRMs: 
                    <template v-if="!showAllAgrupamento">
                       {{ agrupamentoDetalhe }}
                       <span v-if="top20.filter(m => m.alerta2_tempo_concentrado || m.alerta2).length > 5">
                          e mais {{ top20.filter(m => m.alerta2_tempo_concentrado || m.alerta2).length - 5 }} detectados no ranking. 
                          <a href="#" @click.prevent="showAllAgrupamento = true" style="margin-left: 4px; text-decoration: underline; cursor: pointer;">Ver mais</a>
                       </span>
                    </template>
                    <template v-else>
                       {{ top20.filter(m => m.alerta2_tempo_concentrado || m.alerta2).map(m => m.id_medico).join(', ') }}.
                       <a href="#" @click.prevent="showAllAgrupamento = false" style="margin-left: 4px; text-decoration: underline; cursor: pointer;">Ver menos</a>
                    </template>
                 </p>
              </div>
           </div>

           <div v-if="multiFarmaciaDetalhe.length > 0" class="alert-row">
              <span class="bullet-point bg-orange"></span>
              <div class="alert-row-content">
                 <p class="text-orange">Médicos com prescrições em >70 estabelecimentos: <b>{{ qtdMultiFarmacia }} médico(s)</b>.</p>
                 <p class="text-muted text-sm">No Top 20: 
                    <template v-if="!showAllMultiFarmacia">
                       {{ multiFarmaciaDetalhe }}
                       <span v-if="top20.filter(m => m.qtd_estabelecimentos_atua > 70).length > 5">
                          e mais {{ top20.filter(m => m.qtd_estabelecimentos_atua > 70).length - 5 }} detectados no ranking. 
                          <a href="#" @click.prevent="showAllMultiFarmacia = true" style="margin-left: 4px; text-decoration: underline; cursor: pointer;">Ver mais</a>
                       </span>
                    </template>
                    <template v-else>
                       {{ top20.filter(m => m.qtd_estabelecimentos_atua > 70).map(m => `${m.id_medico} (${m.qtd_estabelecimentos_atua} farm.)`).join(', ') }}.
                       <a href="#" @click.prevent="showAllMultiFarmacia = false" style="margin-left: 4px; text-decoration: underline; cursor: pointer;">Ver menos</a>
                    </template>
                 </p>
              </div>
           </div>

           <div v-if="qtdAcima400km > 0" class="alert-row">
              <span class="bullet-point bg-yellow"></span>
              <div class="alert-row-content">
                 <p class="text-yellow">DISTÂNCIA (>400KM): <b>{{ qtdAcima400km }} médico(s) com prescrições simultâneas geograficamente incompatíveis</b>.</p>
                 <p class="text-muted text-sm">
                    CRMs detectados no ranking: 
                    <template v-if="!showAllAcima400km">
                       {{ acima400kmDetalhe }}
                       <span v-if="top20.filter(m => m.alerta5_geografico).length > 5">
                          e mais {{ top20.filter(m => m.alerta5_geografico).length - 5 }} detectados no ranking. 
                          <a href="#" @click.prevent="showAllAcima400km = true" style="margin-left: 4px; text-decoration: underline; cursor: pointer;">
                             Ver mais
                          </a>
                       </span>
                    </template>
                    <template v-else>
                       {{ top20.filter(m => m.alerta5_geografico).map(m => m.id_medico).join(', ') }}.
                       <a href="#" @click.prevent="showAllAcima400km = false" style="margin-left: 4px; color: #ca8a04; text-decoration: underline; cursor: pointer;">
                          Ver menos
                       </a>
                    </template>
                 </p>
              </div>
           </div>
        </div>
      </div>

      <!-- 2. TABELA COMPARATIVA (MEDIANAS) -->
      <div class="section-container">
        <div class="section-title" style="border-bottom: none; margin-bottom: 0;">
          <i class="pi pi-globe" />
          <span>Indicadores vs Mercado (Região / Brasil)</span>
        </div>
        <p class="subtitle" style="padding-left: 1.75rem; margin-top: -0.5rem; margin-bottom: 1rem;">
          Compara o comportamento dos médicos que atuam aqui com a média de outras farmácias da região de <b>{{ summary.municipio }}/{{ summary.uf }}</b>
        </p>

        <div class="table-responsive">
          <table class="ind-table premium-table">
            <thead>
              <tr>
                <th>Métrica de Prescrição</th>
                <th class="col-center">Valor Farmácia</th>
                <th class="col-center">Média Região</th>
                <th class="col-center">Média Brasil</th>
                <th class="col-center">Anomalia Local (vs Região)</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td>
                  <i class="pi pi-star text-primary"></i> Concentração % (Top 5)
                </td>
                <td class="col-center value-cell">
                  {{ formatPct(summary.pct_concentracao_top5) }}
                </td>
                <td class="col-center">
                  {{ formatPct(summary.med_concentracao_top5_reg) }}
                </td>
                <td class="col-center">
                  {{ formatPct(summary.media_concentracao_top5_br) }}
                </td>
                <td
                  class="col-center risk-cell"
                  :class="{
                    'high-risk': summary.risco_concentracao_top5_reg >= 2,
                  }"
                >
                  {{
                    summary.risco_concentracao_top5_reg
                      ? Number(summary.risco_concentracao_top5_reg).toFixed(1) +
                        "x"
                      : "—"
                  }}
                </td>
              </tr>
              <tr>
                <td>
                  <i class="pi pi-bullseye text-primary"></i> Índice de Rede
                  (Suspeita)
                </td>
                <td class="col-center value-cell">
                  {{ formatPct(summary.indice_rede_suspeita) }}
                </td>
                <td class="col-center">
                  {{ formatPct(summary.med_indice_rede_reg) }}
                </td>
                <td class="col-center">
                  {{ formatPct(summary.med_indice_rede_br) }}
                </td>
                <td
                  class="col-center risk-cell"
                  :class="{ 'high-risk': summary.risco_indice_rede_reg >= 2 }"
                >
                  {{
                    summary.risco_indice_rede_reg
                      ? Number(summary.risco_indice_rede_reg).toFixed(1) + "x"
                      : "—"
                  }}
                </td>
              </tr>
              <tr>
                <td>
                  <i class="pi pi-plus-circle text-primary"></i> Médicos
                  Multi-Farmácia
                </td>
                <td class="col-center value-cell">
                  {{ formatPct(summary.pct_multi_farmacia) }}
                </td>
                <td class="col-center">
                  {{ formatPct(summary.med_multi_farmacia_reg) }}
                </td>
                <td class="col-center">
                  {{ formatPct(summary.med_multi_farmacia_br) }}
                </td>
                <td
                  class="col-center risk-cell"
                  :class="{
                    'high-risk': summary.risco_multi_farmacia_reg >= 2,
                  }"
                >
                  {{
                    summary.risco_multi_farmacia_reg
                      ? Number(summary.risco_multi_farmacia_reg).toFixed(1) +
                        "x"
                      : "—"
                  }}
                </td>
              </tr>
              <tr>
                <td>
                  <i class="pi pi-ban text-primary"></i> CRMs Inválidos
                  Encontrados
                </td>
                <td class="col-center value-cell">
                  {{ formatPct(summary.pct_crm_invalido) }}
                </td>
                <td class="col-center">
                  {{ formatPct(summary.med_crm_invalido_reg) }}
                </td>
                <td class="col-center">
                  {{ formatPct(summary.med_crm_invalido_br) }}
                </td>
                <td
                  class="col-center risk-cell"
                  :class="{ 'high-risk': summary.risco_crm_invalido_reg >= 2 }"
                >
                  {{
                    summary.risco_crm_invalido_reg
                      ? Number(summary.risco_crm_invalido_reg).toFixed(1) + "x"
                      : "—"
                  }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <!-- 3. TOP 20 CRMs (TABELA DETALHADA) -->
      <div class="section-container">
        <div class="section-title" style="border-bottom: none; margin-bottom: 0;">
          <i class="pi pi-users" />
          <span>CRMs DE INTERESSE - DETALHAMENTO</span>
        </div>
        <p class="subtitle" style="padding-left: 1.75rem; margin-top: -0.5rem; margin-bottom: 1rem;">
          Detalhamento dos médicos que mais aprovaram medicamentos nesta unidade, ordenados pelo financeiro.
        </p>

        <div
          class="table-responsive"
          style="max-height: 500px; overflow-y: auto"
        >
          <table class="ind-table premium-table row-hover">
            <thead class="sticky-thead">
              <tr>
                <th style="width: 40px">#</th>
                <th>CRM do<br />Médico</th>
                <th>Status e Alertas de Auditoria</th>
                <th class="col-right">Qtd. Total Autorizada</th>
                <th class="col-right">Volume Total (R$) CRM</th>
                <th class="col-center">% Vendas CRM</th>
                <th class="col-center">% Vendas Acumulado</th>
                <th class="col-center">Network / Rede (Farm.)</th>
                <th class="col-center">Presc/Dia Neste CNPJ</th>
                <th class="col-center">Presc/Dia em todo o Brasil</th>
                <th class="col-center">% Exclusividade CRM Neste CNPJ</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="(m, i) in top20"
                :key="i"
                :class="{
                  'severe-row':
                    m.flag_robo > 0 ||
                    m.flag_crm_invalido > 0 ||
                    m.flag_prescricao_antes_registro > 0,
                }"
              >
                <td>
                  <b>{{ i + 1 }}</b>
                </td>
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
                    <span v-if="m.flag_robo" class="issue-tag red"
                      ><i class="pi pi-history"></i> Intensiva Local</span
                    >
                    <span
                      v-if="m.flag_robo_oculto && !m.flag_robo"
                      class="issue-tag orange"
                      ><i class="pi pi-globe"></i> Intensiva Nacional</span
                    >
                    <span
                      v-if="m.alerta2_tempo_concentrado || m.alerta2"
                      class="issue-tag red"
                      ><i class="pi pi-stopwatch"></i> Emissão Agrupada</span
                    >
                    <span v-if="m.flag_crm_invalido" class="issue-tag dark-red"
                      ><i class="pi pi-ban"></i> Inválido</span
                    >
                    <span
                      v-if="m.flag_prescricao_antes_registro"
                      class="issue-tag dark-red"
                      ><i class="pi pi-calendar-times"></i> Fraude Data</span
                    >
                    <span
                      v-if="m.qtd_estabelecimentos_atua === 1"
                      class="issue-tag purple"
                      ><i class="pi pi-lock"></i> Exclusivo</span
                    >
                    <span v-if="m.alerta5_geografico" class="issue-tag yellow"
                      ><i class="pi pi-map-marker"></i> >400km</span
                    >
                    <span
                      v-if="
                        !m.flag_robo &&
                        !m.flag_robo_oculto &&
                        !m.flag_crm_invalido &&
                        !m.flag_prescricao_antes_registro &&
                        m.pct_volume_aqui_vs_total <= 90 &&
                        !m.alerta5_geografico
                      "
                      class="text-muted text-xs"
                      >Regular</span
                    >
                  </div>
                </td>
                <td class="col-right font-mono">
                  {{ formatNumberFull(m.nu_prescricoes) }}
                </td>
                <td class="col-right font-mono text-primary font-bold">
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
                    <span class="bar-text text-sm font-mono">{{
                      formatPct(m.pct_acumulado)
                    }}</span>
                  </div>
                </td>
                <td class="col-center font-mono">
                  <span
                    :class="{
                      'text-purple font-bold': m.qtd_estabelecimentos_atua > 50,
                    }"
                    >{{ m.qtd_estabelecimentos_atua }}</span
                  >
                  farm.
                </td>
                <td class="col-center font-mono">
                  <span
                    :class="{ 'text-red font-bold': m.nu_prescricoes_dia > 30 }"
                    >{{ formatNumberFull(m.nu_prescricoes_dia) }}</span
                  >
                  / dia
                </td>
                <td class="col-center font-mono">
                  <span
                    :class="{
                      'text-red font-bold': m.prescricoes_dia_total_brasil > 30,
                    }"
                    >{{
                      formatNumberFull(m.prescricoes_dia_total_brasil)
                    }}</span
                  >
                  / dia
                </td>
                <td class="col-center">
                  <span
                    :class="{
                      'text-purple font-bold': m.pct_volume_aqui_vs_total > 90,
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
  gap: 1.5rem;
  width: 100%;
  align-items: stretch;
}

.no-padding-mobile {
  border: none !important;
  background: transparent !important;
  padding: 0 !important;
}

/* 1. RESUMO AUDITORIA */
.audit-summary-section {
  display: flex;
  flex-direction: column;
  gap: 1rem;
  width: 100%;
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
  margin-bottom: 2rem;
}

.alert-kpi-card {
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
  padding: 1.25rem;
  background: color-mix(in srgb, var(--text-color) 2.5%, var(--tabs-bg));
  border: 1px solid var(--sidebar-border);
  border-radius: 12px;
  transition: all 0.2s ease;
}

.alert-kpi-card:hover {
  transform: translateY(-2px);
  background: color-mix(in srgb, var(--text-color) 4%, var(--tabs-bg));
  box-shadow: 0 4px 15px rgba(0, 0, 0, 0.06);
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

.alert-kpi-val {
  font-size: 1.5rem;
  font-weight: 800;
  color: var(--text-color);
  line-height: 1;
}

.alert-kpi-hint {
  font-size: 0.72rem;
  color: var(--text-muted);
  font-weight: 400;
}

/* Semafórica de Risco nos Cards */
.highlight-red .alert-kpi-val {
  color: var(--risk-critical);
}
.highlight-red {
  border-top: 4px solid var(--risk-critical) !important;
}

.highlight-orange .alert-kpi-val {
  color: var(--risk-high);
}
.highlight-orange {
  border-top: 4px solid var(--risk-high) !important;
}

.highlight-yellow .alert-kpi-val {
  color: var(--risk-medium);
}
.highlight-yellow {
  border-top: 4px solid var(--risk-medium) !important;
}

.text-red {
  color: var(--risk-critical) !important;
}

.text-red {
  color: var(--risk-critical) !important;
}

/* 2. SECTION & TABLES */
.section-container {
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
  background: var(--surface-bg);
  border: 1px solid var(--border-color);
  border-radius: 12px;
  padding: 0; /* Removido padding para a tabela ocupar largura total */
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
  border-radius: 8px;
  border: 1px solid var(--tabs-border);
}

.premium-table {
  width: 100%;
  border-collapse: collapse;
}

.premium-table th {
  background-color: var(--tabs-bg) !important; /* Usando o fundo da aba que é sólido */
  color: var(--text-secondary);
  font-weight: 700; /* Mais negrito para destacar */
  text-transform: uppercase;
  font-size: 0.72rem;
  padding: 0.75rem 0.4rem; /* Um pouco mais de respiro vertical */
  letter-spacing: 0.02em;
  border-bottom: 2px solid var(--tabs-border);
  white-space: normal;
  line-height: 1.2;
  text-align: left;
  vertical-align: bottom;
  opacity: 1 !important;
}

.premium-table td {
  padding: 0.6rem 0.4rem; /* Reduzido padding lateral */
  border-bottom: 1px solid var(--tabs-border);
  color: var(--text-color);
  font-size: 0.72rem;
}

.premium-table tbody tr:last-child td {
  border-bottom: none;
}

.premium-table.row-hover tbody tr:hover {
  background: color-mix(
    in srgb,
    var(--text-color) 4%,
    var(--tabs-bg)
  ) !important;
  cursor: pointer;
}

.sticky-thead th {
  position: sticky;
  top: 0;
  z-index: 10; /* Aumentado para garantir que fique sobre o conteúdo */
  box-shadow: 0 2px 4px rgba(0,0,0,0.2); /* Sombra para separar visualmente o header dos dados */
}

.col-center {
  text-align: center;
}
.col-right {
  text-align: right;
}
.font-mono {
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
}

/* Table Specific Components */
.severe-row {
  background: color-mix(
    in srgb,
    var(--risk-critical) 4%,
    var(--tabs-bg)
  ) !important;
}

.med-id {
  font-weight: 600;
  font-size: 0.85rem;
}
.med-sub {
  font-size: 0.7rem;
  color: var(--text-muted);
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

/* Alerts List Section */
.alerts-details-section {
  display: flex;
  flex-direction: column;
  gap: 1rem;
}
.line-header {
  display: none; /* Desativada em favor do novo padrão de títulos */
}
.line-header h3 {
  font-size: 0.9rem;
  margin: 0;
  text-transform: uppercase;
  letter-spacing: 0.03em;
}

.alerts-list {
  display: flex;
  flex-direction: column;
  gap: 1rem;
  padding: 0.5rem 1.25rem;
}
.alert-row {
  display: flex;
  gap: 0.75rem;
  align-items: flex-start;
}
.bullet-point {
  width: 12px;
  height: 12px;
  border-radius: 50%;
  margin-top: 0.25rem;
  flex-shrink: 0;
}
.bg-orange {
  background: #f97316;
}
.bg-red {
  background: #dc2626;
}
.bg-yellow {
  background: #eab308;
}

.alert-row-content p {
  margin: 0;
  font-size: 0.85rem;
}
.alert-row-content .text-orange {
  color: #f97316;
  font-weight: 600;
}
.alert-row-content .text-red {
  color: #ef4444;
  font-weight: 600;
}
.alert-row-content .text-yellow {
  color: #ca8a04;
  font-weight: 600;
}
.alert-row-content .text-sm {
  font-size: 0.8rem;
  margin-top: 0.25rem;
  color: var(--text-secondary);
}

.tags-container {
  display: flex;
  flex-wrap: wrap;
  gap: 0.25rem;
}
.issue-tag {
  font-size: 0.6rem; /* Reduzido de 0.65 para 0.6 */
  font-weight: 700;
  padding: 0.05rem 0.3rem; /* Padding mais justo */
  border-radius: 4px;
  display: inline-flex;
  align-items: center;
  gap: 0.2rem;
  white-space: nowrap;
}
.issue-tag i {
  font-size: 0.65rem;
}
.issue-tag.red {
  background: color-mix(in srgb, var(--risk-critical) 10%, var(--tabs-bg));
  color: var(--risk-critical);
  border: 1px solid color-mix(in srgb, var(--risk-critical) 20%, transparent);
}
.issue-tag.dark-red {
  background: color-mix(in srgb, var(--risk-critical) 15%, var(--tabs-bg));
  color: var(--risk-critical);
  border: 1px solid color-mix(in srgb, var(--risk-critical) 30%, transparent);
  font-weight: 800;
}
.issue-tag.orange {
  background: color-mix(in srgb, var(--risk-high) 10%, var(--tabs-bg));
  color: var(--risk-high);
  border: 1px solid color-mix(in srgb, var(--risk-high) 20%, transparent);
}
.issue-tag.yellow {
  background: color-mix(in srgb, var(--risk-medium) 10%, var(--tabs-bg));
  color: var(--risk-medium);
  border: 1px solid color-mix(in srgb, var(--risk-medium) 20%, transparent);
}
.issue-tag.purple {
  background: color-mix(in srgb, var(--primary-color) 10%, var(--tabs-bg));
  color: var(--primary-color);
  border: 1px solid color-mix(in srgb, var(--primary-color) 20%, transparent);
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
  font-size: 0.75rem;
  font-weight: 600;
  color: var(--text-color);
}
</style>
