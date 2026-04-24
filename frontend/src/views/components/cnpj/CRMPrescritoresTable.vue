<script setup>
import { computed, ref, watch } from "vue";
import { useFormatting } from "@/composables/useFormatting";
import { useCnpjDetailStore } from '@/stores/cnpjDetail';
import CRMRedeOverlay from "./CRMRedeOverlay.vue";

const cnpjDetailStore = useCnpjDetailStore();

const props = defineProps({
  crmsInteresse:    { type: Array,  required: true },
  activeKpiFilter:  { type: String, default: null },
  kpiFilters:       { type: Object, required: true },
  kpiFilterLabels:  { type: Object, required: true },
  currentCnpj:      { type: String, default: '' },
});

const emit = defineEmits(['clear-filters']);


const { formatCurrencyFull, formatNumberFull, formatarData } = useFormatting();
const formatPct = (val) => val != null ? `${Number(val).toFixed(2)}%` : "0.00%";

const filterOnlyIssues = ref(false);
const showAllCrms     = ref(false);
const redeOverlay     = ref(null);
const expandedAlertasMedico = ref(new Set());
const activeAlertTab  = ref({});

watch(() => props.activeKpiFilter, (newVal) => {
  if (newVal !== null) filterOnlyIssues.value = false;
});

function toggleAlertasDiarios(idMedico) {
  if (expandedAlertasMedico.value.has(idMedico)) {
    expandedAlertasMedico.value.delete(idMedico);
  } else {
    expandedAlertasMedico.value.add(idMedico);
    // Define a aba padrão ao abrir: concentração se existir, senão geográfico
    const m = props.crmsInteresse.find(x => x.id_medico === idMedico);
    if (m && !activeAlertTab.value[idMedico]) {
      if (m.alertas_diarios?.length) activeAlertTab.value[idMedico] = 'conc';
      else if (m.alertas_geograficos?.length) activeAlertTab.value[idMedico] = 'geo';
      else if (m.alertas_surto?.length) activeAlertTab.value[idMedico] = 'surto';
    }
  }
  expandedAlertasMedico.value = new Set(expandedAlertasMedico.value);
}

function setAlertTab(idMedico, tab) {
  activeAlertTab.value = { ...activeAlertTab.value, [idMedico]: tab };
}

function handleTimelineNavigation(date, hour) {
  cnpjDetailStore.navigateTimeline(date, hour);
}

function clearAllFilters() {
  filterOnlyIssues.value = false;
  emit('clear-filters');
}

const hasAnyIssue = (m) =>
  m.flag_robo > 0 || m.flag_robo_oculto > 0 || m.alerta_concentracao_mesmo_crm ||
  m.flag_crm_invalido > 0 || m.flag_prescricao_antes_registro > 0 ||
  m.alerta5_geografico || m.flag_crm_exclusivo > 0 || m.flag_concentracao_estabelecimento > 0;

const filteredCrmsInteresse = computed(() => {
  let list = props.crmsInteresse;
  if (filterOnlyIssues.value) list = list.filter(hasAnyIssue);
  if (props.activeKpiFilter && props.kpiFilters[props.activeKpiFilter]) {
    list = list.filter(props.kpiFilters[props.activeKpiFilter]);
  }
  return list;
});

const visibleCrms = computed(() =>
  showAllCrms.value ? filteredCrmsInteresse.value : filteredCrmsInteresse.value.slice(0, 10)
);

function formatarDataAlerta(dt) {
  if (!dt) return "";
  const [y, m, d] = dt.split("-");
  return `${d}/${m}/${y}`;
}

function formatarJanela(minutos) {
  if (!minutos) return "—";
  if (minutos === 0) return "simultâneo";
  if (minutos < 60) return `${minutos}min`;
  return `${Math.floor(minutos / 60)}h ${minutos % 60}min`;
}

function formatDescricao(a) {
  const num = `<span class="desc-num">${a.nu_prescricoes}</span>`;
  if (!a.nu_minutos || a.nu_minutos === 0) {
    return `${num} autorizações de venda <span class="desc-janela">no mesmo instante</span> para o mesmo CRM`;
  }
  const h = Math.floor(a.nu_minutos / 60);
  const min = a.nu_minutos % 60;
  const janela = h > 0 ? `${h}h ${min}min` : `${min}min`;
  const taxa = a.taxa_hora?.toFixed(1) ?? '—';
  return `${num} autorizações de venda <span class="desc-janela">em ${janela} (${taxa}/hora)</span> para o mesmo CRM`;
}
const maxPDOverall = computed(() => {
  if (!props.crmsInteresse?.length) return 40;
  const vals = props.crmsInteresse.flatMap(m => [m.nu_prescricoes_dia, m.prescricoes_dia_total_brasil]);
  return Math.max(...vals, 40);
});
</script>

<template>
  <div class="section-container animate-fade-in">
    <div class="section-title" style="border-bottom: none; margin-bottom: 0">
      <div style="display: flex; align-items: center; gap: 1.5rem; width: 100%">
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

    <p class="subtitle" style="padding-left: 1.75rem; margin-top: -0.5rem; margin-bottom: 1rem">
      Detalhamento dos médicos que mais aprovaram medicamentos nesta unidade, ordenados pelo financeiro.
      <div v-if="activeKpiFilter" class="filter-badge animate-fade-in" v-tooltip.bottom="'Filtro de KPI Ativo'">
        <i class="pi pi-filter-fill" />
        <span class="filter-text">
          <small style="opacity: 0.8; font-weight: 500; margin-right: 2px; text-transform: uppercase; font-size: 0.6rem;">Filtro:</small>
          {{ kpiFilterLabels[activeKpiFilter] }} — <strong class="filter-count">{{ filteredCrmsInteresse.length }} de {{ crmsInteresse.length }}</strong>
        </span>
        <button class="clear-filter-btn" @click.stop="clearAllFilters" title="Limpar filtro">
          <i class="pi pi-times" />
        </button>
      </div>
      <span
        v-else-if="filterOnlyIssues && filteredCrmsInteresse.length < crmsInteresse.length"
        class="text-orange"
        style="font-weight: 600; margin-left: 8px"
      >
        (Filtrado: exibindo {{ filteredCrmsInteresse.length }} de {{ crmsInteresse.length }})
      </span>
    </p>

    <div class="table-responsive">
      <table class="ind-table premium-table row-hover">
        <thead class="sticky-thead">
          <tr>
            <th style="width: 45px;" class="col-center">#</th>
            <th style="width: 160px;">CRM / Médico</th>
            <th style="width: 34%">Status / Alertas</th>
            <th class="col-right" style="width: 15%">Volume / Valor</th>
            <th class="col-center" style="width: 16%">Participação / Acumulado</th>
            <th class="col-center" style="width: 8%">Rede</th>
            <th class="col-center" style="width: 12%">Prescrições por Dia</th>
            <th class="col-center" style="width: 5%">Excl.</th>
          </tr>
        </thead>
        <tbody>
          <template v-for="(m, i) in visibleCrms" :key="i">
            <tr
              :class="{ 'row-expandable': m.alerta_concentracao_mesmo_crm || m.alerta5_geografico || m.flag_concentracao_estabelecimento }"
              @click="(m.alertas_diarios?.length || m.alertas_geograficos?.length || m.alertas_surto?.length) ? toggleAlertasDiarios(m.id_medico) : null"
            >
              <td class="col-center">
                  <div class="rank-badge" :class="{ 'gold': i === 0, 'silver': i === 1, 'bronze': i === 2 }">
                    <span class="rank-val">{{ (i + 1).toString().padStart(2, '0') }}</span>
                  </div>
              </td>
              <td>
                <div class="med-id">{{ m.id_medico }}</div>
                <div class="med-sub">Registro: {{ m.dt_inscricao_crm ? formatarData(m.dt_inscricao_crm) : 'ND' }}</div>
              </td>
              <td class="flags-cell">
                <div class="tags-container">
                  <span v-if="m.flag_robo" class="issue-tag red" v-tooltip.top="'>30 Prescrições/dia neste CNPJ'">
                    <i class="pi pi-history"></i> >30 PRESC/DIA (LOCAL)
                  </span>
                  <span v-if="m.flag_robo_oculto && !m.flag_robo" class="issue-tag orange" v-tooltip.top="'>30 Prescrições/dia em todo o Brasil (Robô Oculto)'">
                    <i class="pi pi-globe"></i> >30 PRESC/DIA (BRASIL)
                  </span>
                  <span
                    v-if="m.alerta_concentracao_mesmo_crm"
                    class="issue-tag violet clickable-badge"
                    v-tooltip.top="expandedAlertasMedico.has(m.id_medico) ? 'Recolher detalhes' : 'Ver episódios detalhados'"
                    @click.stop="toggleAlertasDiarios(m.id_medico)"
                  >
                    <i class="pi pi-stopwatch"></i> CONCENTRAÇÃO MESMO CRM
                    <span v-if="m.alertas_diarios?.length" class="badge-count">({{ m.alertas_diarios.length }}x)</span>
                    <i :class="expandedAlertasMedico.has(m.id_medico) ? 'pi pi-chevron-up' : 'pi pi-chevron-down'" style="font-size:0.6rem; margin-left:0.2rem;" />
                  </span>
                  <span v-if="m.flag_crm_invalido" class="issue-tag red" v-tooltip.top="'CRM não encontrado na base de dados oficial do Conselho Federal de Medicina (CFM)'">
                    <i class="pi pi-ban"></i> CRM INEXISTENTE
                  </span>
                  <span v-if="m.flag_prescricao_antes_registro" class="issue-tag red" v-tooltip.top="'Venda anterior ao Registro oficial no CFM'">
                    <i class="pi pi-calendar-times"></i> CRM IRREGULAR
                  </span>
                  <span v-if="m.flag_crm_exclusivo > 0" class="issue-tag blue-network" v-tooltip.top="'Médico prescreveu exclusivamente para este CNPJ no total do Brasil'">
                    <i class="pi pi-lock"></i> CRM EXCLUSIVO
                  </span>
                  <span 
                    v-if="m.alerta5_geografico" 
                    class="issue-tag purple-geo clickable-badge" 
                    v-tooltip.top="expandedAlertasMedico.has(m.id_medico) ? 'Recolher detalhes' : 'Ver evidências de distância'"
                    @click.stop="toggleAlertasDiarios(m.id_medico)"
                  >
                    <i class="pi pi-map-marker"></i> DISTÂNCIA >400KM
                    <span v-if="m.alertas_geograficos?.length" class="badge-count">({{ m.alertas_geograficos.length }}x)</span>
                    <i :class="expandedAlertasMedico.has(m.id_medico) ? 'pi pi-chevron-up' : 'pi pi-chevron-down'" style="font-size:0.6rem; margin-left:0.2rem;" />
                  </span>
                  <span
                    v-if="m.flag_concentracao_estabelecimento"
                    class="issue-tag amber clickable-badge"
                    v-tooltip.top="expandedAlertasMedico.has(m.id_medico) ? 'Recolher detalhes' : 'Ver episódios de surto geral'"
                    @click.stop="toggleAlertasDiarios(m.id_medico)"
                  >
                    <i class="pi pi-bolt"></i> CONCENTRAÇÃO CRMs DIVERSOS
                    <span v-if="m.alertas_surto?.length" class="badge-count">({{ m.alertas_surto.length }}x)</span>
                    <i :class="expandedAlertasMedico.has(m.id_medico) ? 'pi pi-chevron-up' : 'pi pi-chevron-down'" style="font-size:0.6rem; margin-left:0.2rem;" />
                  </span>
                  <i
                    v-if="!m.alertas_diarios?.length && !m.flag_robo && !m.flag_robo_oculto && !m.flag_crm_invalido && !m.flag_prescricao_antes_registro && !m.alerta5_geografico && !m.flag_concentracao_estabelecimento && (!m.flag_crm_exclusivo || m.flag_crm_exclusivo === 0)"
                    class="pi pi-check-circle"
                    style="color: var(--text-muted); font-size: 0.85rem;"
                    v-tooltip.top="'Sem ocorrências identificadas'"
                  />
                </div>
              </td>
              <td class="col-right">
                <div class="cell-stacked">
                  <span class="cell-main text-primary">{{ formatCurrencyFull(m.vl_total_prescricoes) }}</span>
                  <span class="cell-sub">{{ formatNumberFull(m.nu_prescricoes) }} autorizações</span>
                </div>
              </td>
              <td class="col-center">
                <div class="multi-bar-container">
                  <div class="bar-row">
                    <span class="bar-label">part.</span>
                    <div class="bar-container">
                      <div class="bar-fill part-fill" :style="{ width: Math.min(m.pct_participacao, 100) + '%' }"></div>
                      <span class="bar-text">{{ formatPct(m.pct_participacao) }}</span>
                    </div>
                  </div>
                  <div class="bar-row">
                    <span class="bar-label">acum.</span>
                    <div class="bar-container">
                      <div class="bar-fill acum-fill" :style="{ width: Math.min(m.pct_acumulado, 100) + '%' }"></div>
                      <span class="bar-text">{{ formatPct(m.pct_acumulado) }}</span>
                    </div>
                  </div>
                </div>
              </td>
              <td class="col-center">
                <span
                  :class="{ 'text-purple': m.qtd_estabelecimentos_atua > 50, 'rede-clickable': m.lista_cnpjs_brasil }"
                  v-tooltip.top="m.lista_cnpjs_brasil ? 'Clique para ver a lista de farmácias' : null"
                  @click.stop="m.lista_cnpjs_brasil ? redeOverlay.open($event, m) : null"
                >{{ m.qtd_estabelecimentos_atua }} farm.</span>
              </td>
              <td class="col-center">
                <div class="cell-stacked" style="align-items: center; gap: 0.1rem;">
                  <div :class="{ 'text-red': m.nu_prescricoes_dia > 30 }" style="font-weight: 600; font-size: 0.85rem;">
                    {{ formatNumberFull(m.nu_prescricoes_dia) }} <span style="font-size: 0.68rem; color: var(--text-muted); font-weight: 400">local</span>
                  </div>
                  <div :class="{ 'text-red': m.prescricoes_dia_total_brasil > 30 }" style="font-size: 0.75rem; color: var(--text-secondary);">
                    {{ formatNumberFull(m.prescricoes_dia_total_brasil) }} <span style="font-size: 0.68rem; color: var(--text-muted); font-weight: 400">brasil</span>
                  </div>
                </div>
              </td>
              <td class="col-center">
                <span :class="{ 'text-purple': m.pct_volume_aqui_vs_total > 90 }">{{ formatPct(m.pct_volume_aqui_vs_total) }}</span>
              </td>
            </tr>

            <!-- Linha expandida de alertas (Concentração ou Geográfico) com sistema de abas -->
            <tr v-if="expandedAlertasMedico.has(m.id_medico) && (m.alertas_diarios?.length || m.alertas_geograficos?.length || m.alertas_surto?.length)" class="alertas-diarios-row">
              <td colspan="11" class="alertas-diarios-cell">
                <div
                  class="evidence-panel"
                  :class="{
                    'theme-conc': activeAlertTab[m.id_medico] === 'conc',
                    'theme-geo':  activeAlertTab[m.id_medico] === 'geo',
                    'theme-surto': activeAlertTab[m.id_medico] === 'surto'
                  }"
                >
                  <!-- PANEL HEADER -->
                  <div class="panel-header">
                    <div class="panel-header-left">
                      <i :class="{
                        'pi pi-user': activeAlertTab[m.id_medico] === 'conc',
                        'pi pi-map-marker': activeAlertTab[m.id_medico] === 'geo',
                        'pi pi-users': activeAlertTab[m.id_medico] === 'surto'
                      }" class="panel-icon" />
                      <span class="panel-title">
                        <template v-if="activeAlertTab[m.id_medico] === 'conc'">Lançamentos Sequenciais para um único CRM</template>
                        <template v-else-if="activeAlertTab[m.id_medico] === 'geo'">Evidências de Distância Geográfica</template>
                        <template v-else-if="activeAlertTab[m.id_medico] === 'surto'">Lançamentos Sequenciais com múltiplos CRMs</template>
                      </span>
                      <span class="panel-crm-badge">{{ m.id_medico }}</span>
                    </div>
                    <!-- SEGMENTED CONTROL (Abas Dinâmicas) -->
                    <div class="segmented-control" v-if="(m.alertas_diarios?.length ? 1 : 0) + (m.alertas_geograficos?.length ? 1 : 0) + (m.alertas_surto?.length ? 1 : 0) > 1">
                      <button
                        v-if="m.alertas_diarios?.length"
                        class="segment-btn"
                        :class="{ 'seg-active': activeAlertTab[m.id_medico] === 'conc' }"
                        @click="setAlertTab(m.id_medico, 'conc')"
                      >
                        CRM Único
                        <span class="seg-count">{{ m.alertas_diarios.length }}</span>
                      </button>
                      <button
                        v-if="m.alertas_geograficos?.length"
                        class="segment-btn"
                        :class="{ 'seg-active': activeAlertTab[m.id_medico] === 'geo' }"
                        @click="setAlertTab(m.id_medico, 'geo')"
                      >
                        <i class="pi pi-map-marker" />
                        Distância
                        <span class="seg-count">{{ m.alertas_geograficos.length }}</span>
                      </button>
                      <button
                        v-if="m.alertas_surto?.length"
                        class="segment-btn"
                        :class="{ 'seg-active': activeAlertTab[m.id_medico] === 'surto' }"
                        @click="setAlertTab(m.id_medico, 'surto')"
                      >
                        CRMs Múltiplos
                        <span class="seg-count">{{ m.alertas_surto.length }}</span>
                      </button>
                    </div>
                  </div>

                  <!-- CONTEÚDO: Tabela de Concentração -->
                  <table
                    v-if="activeAlertTab[m.id_medico] === 'conc'"
                    class="evidence-table"
                  >
                    <thead>
                      <tr>
                        <th><i class="pi pi-calendar" /> Data</th>
                        <th><i class="pi pi-id-card" /> CRM</th>
                        <th class="col-right"><i class="pi pi-chart-bar" /> Autorizações</th>
                        <th class="col-center"><i class="pi pi-clock" /> Janela</th>
                        <th class="col-right"><i class="pi pi-chart-line" /> Taxa/hora</th>
                        <th><i class="pi pi-align-left" /> Descrição</th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr v-for="(a, j) in m.alertas_diarios" :key="j" class="alerta-diario-item">
                        <td class="col-date">{{ formatarDataAlerta(a.dt) }}</td>
                        <td class="col-crm">{{ m.id_medico }}</td>
                        <td class="col-right td-metric">{{ a.nu_prescricoes }}</td>
                        <td class="col-center">{{ formatarJanela(a.nu_minutos) }}</td>
                        <td class="col-right td-metric">{{ a.taxa_hora?.toFixed(1) }}/h</td>
                        <td class="col-descricao" v-html="formatDescricao(a)" />
                      </tr>
                    </tbody>
                  </table>

                  <!-- CONTEÚDO: Tabela de Distância Geográfica -->
                  <table
                    v-if="activeAlertTab[m.id_medico] === 'geo'"
                    class="evidence-table"
                  >
                    <thead>
                      <tr>
                        <th style="width: 40%"><i class="pi pi-building" /> Estabelecimento A</th>
                        <th style="width: 40%"><i class="pi pi-building" /> Estabelecimento B</th>
                        <th style="width: 10%" class="col-center"><i class="pi pi-arrows-h" /> Distância</th>
                        <th style="width: 10%" class="col-center"><i class="pi pi-calendar" /> Comp.</th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr v-for="(g, k) in m.alertas_geograficos" :key="'geo-'+k">
                        <td class="geo-cell">
                          <div class="geo-main">{{ g.municipio_a }}/{{ g.uf_a }}</div>
                          <div class="geo-sub">{{ g.cnpj_a }} · {{ g.nu_presc_a }} presc.</div>
                          <div class="geo-sub">{{ formatarDataAlerta(g.dt_ini_a) }} → {{ formatarDataAlerta(g.dt_fim_a) }}</div>
                        </td>
                        <td class="geo-cell">
                          <div class="geo-main">{{ g.municipio_b }}/{{ g.uf_b }}</div>
                          <div class="geo-sub">{{ g.cnpj_b }} · {{ g.nu_presc_b }} presc.</div>
                          <div class="geo-sub">{{ formatarDataAlerta(g.dt_ini_b) }} → {{ formatarDataAlerta(g.dt_fim_b) }}</div>
                        </td>
                        <td class="col-center">
                          <span class="dist-badge">{{ Math.round(g.distancia_km) }}km</span>
                        </td>
                        <td class="col-center" style="font-size: 0.75rem; color: var(--text-muted);">{{ g.competencia }}</td>
                      </tr>
                    </tbody>
                  </table>

                  <!-- CONTEÚDO: Tabela de Surto Geral -->
                  <table
                    v-if="activeAlertTab[m.id_medico] === 'surto'"
                    class="evidence-table"
                  >
                    <thead>
                      <tr>
                        <th><i class="pi pi-calendar" /> Data</th>
                        <th class="col-center"><i class="pi pi-clock" /> Hora</th>
                        <th class="col-right"><i class="pi pi-user-edit" /> Autorizações CRM</th>
                        <th class="col-right"><i class="pi pi-users" /> Total Hora (CNPJ)</th>
                        <th class="col-center"><i class="pi pi-id-card" /> Diversidade</th>
                        <th><i class="pi pi-align-left" /> Descrição</th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr 
                        v-for="(s, l) in m.alertas_surto" 
                        :key="'surto-'+l"
                        class="clickable-surto-row"
                        v-tooltip.top="'Clique para ver no Raio-X'"
                        @click="handleTimelineNavigation(s.dt, s.hr)"
                      >
                        <td class="col-date">{{ formatarDataAlerta(s.dt) }}</td>
                        <td class="col-center">
                          <span class="time-badge">{{ s.hr.toString().padStart(2, '0') }}:00h</span>
                        </td>
                        <td class="col-right td-metric">{{ s.nu_presc_crm }}</td>
                        <td class="col-right">{{ s.nu_presc_total }}</td>
                        <td class="col-center">{{ s.nu_crms_total }} CRMs</td>
                        <td class="col-descricao">
                           <span class="surto-desc">{{ s.descricao.replace('Surto de Volume: ', '') }}</span>
                        </td>
                      </tr>
                    </tbody>
                  </table>

                </div>
              </td>
            </tr>
          </template>
        </tbody>
      </table>
    </div>

    <div class="crm-table-footer">
      <button v-if="filteredCrmsInteresse.length > 10" class="crm-more-btn" @click="showAllCrms = !showAllCrms">
        <template v-if="!showAllCrms">
          <i class="pi pi-angle-double-down" />
          Exibir mais {{ filteredCrmsInteresse.length - 10 }} registros
        </template>
        <template v-else>
          <i class="pi pi-angle-double-up" />
          Recolher
        </template>
      </button>
    </div>

    <!-- Overlay de Rede de Farmácias -->
    <CRMRedeOverlay ref="redeOverlay" :current-cnpj="props.currentCnpj"/>

  </div>
</template>

<style scoped>
.animate-fade-in { animation: fadeIn 0.3s ease-out; }
@keyframes fadeIn { from { opacity: 0; transform: translateY(10px); } to { opacity: 1; transform: translateY(0); } }

.section-container {
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  border-radius: 12px;
  padding: 1rem;
  width: 100%;
  box-sizing: border-box;
  overflow: hidden;
}
.section-title {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  font-size: 0.85rem;
  font-weight: 600;
  text-transform: uppercase;
  color: var(--text-color);
  margin-bottom: 1rem;
  letter-spacing: 0.05em;
  border-bottom: 1px solid var(--tabs-border);
  padding-bottom: 0.5rem;
  width: 100%;
  opacity: 0.85;
}
.section-title i { color: var(--primary-color); font-size: 1rem; }
.subtitle { margin: 0.25rem 0 0 0; font-size: 0.8rem; color: var(--text-muted); }

.filter-controls { display: flex; align-items: center; gap: 1rem; }
.filter-toggle { display: flex; align-items: center; gap: 0.5rem; cursor: pointer; user-select: none; font-size: 0.75rem; text-transform: none; font-weight: 600; color: var(--text-secondary); }
.filter-toggle input { display: none; }
.toggle-slider { position: relative; width: 32px; height: 18px; background-color: var(--tabs-border); border: 1px solid var(--tabs-border); border-radius: 20px; transition: 0.3s; }
.toggle-slider:before { content: ""; position: absolute; height: 12px; width: 12px; left: 3px; bottom: 3px; background-color: white; border-radius: 50%; transition: 0.3s; }
input:checked + .toggle-slider { background-color: var(--primary-color); }
input:checked + .toggle-slider:before { transform: translateX(14px); }
.toggle-label { letter-spacing: normal; }

.filter-badge {
  display: inline-flex;
  align-items: center;
  gap: 0.6rem;
  padding: 0.25rem 0.4rem 0.25rem 0.75rem;
  background: color-mix(in srgb, var(--risk-high) 12%, transparent);
  border: 1px solid color-mix(in srgb, var(--risk-high) 35%, transparent);
  border-radius: 99px;
  color: var(--risk-high);
  font-size: 0.72rem;
  font-weight: 600;
  margin-left: 1rem;
  box-shadow: 0 4px 12px rgba(0,0,0,0.15);
  position: relative;
  overflow: hidden;
  backdrop-filter: blur(8px);
  -webkit-backdrop-filter: blur(8px);
}
.filter-badge::after {
  content: "";
  position: absolute;
  top: 0; left: -100%;
  width: 100%; height: 100%;
  background: linear-gradient(90deg, transparent, rgba(255,255,255,0.05), rgba(255,255,255,0.2), rgba(255,255,255,0.05), transparent);
  animation: shimmer-sweep 4s infinite ease-in-out;
}
@keyframes shimmer-sweep { 0% { left: -100%; } 15% { left: 100%; } 100% { left: 100%; } }
.filter-badge i.pi-filter-fill { font-size: 0.65rem; opacity: 0.8; animation: icon-spin-subtle 4s infinite ease-in-out; }
@keyframes icon-spin-subtle { 0%, 70% { transform: rotate(0deg); } 85% { transform: rotate(-360deg); } 100% { transform: rotate(-360deg); } }
.filter-text { letter-spacing: 0.02em; }
.filter-count { font-weight: 600; margin-left: 0.2rem; }
.clear-filter-btn { display: flex; align-items: center; justify-content: center; width: 18px; height: 18px; background: color-mix(in srgb, var(--risk-high) 15%, transparent); color: var(--risk-high); border: none; border-radius: 50%; cursor: pointer; transition: all 0.2s ease; padding: 0; }
.clear-filter-btn:hover { background: var(--risk-high); color: white; }
.clear-filter-btn i { font-size: 0.55rem; font-weight: 900; }

.table-responsive { overflow-x: auto; border-top: 1px solid var(--tabs-border); border-bottom: 1px solid var(--tabs-border); min-height: 35rem; }

.premium-table { width: 100%; border-collapse: collapse; table-layout: fixed; }
.premium-table th { padding: 0.6rem 0.5rem; background: transparent; color: color-mix(in srgb, var(--text-secondary) 85%, transparent); font-size: 0.68rem; font-weight: 500; text-transform: uppercase; letter-spacing: 0.02em; border-bottom: 2px solid var(--tabs-border); text-align: center; }
.premium-table th:first-child { text-align: left; }
.premium-table td { padding: 0.55rem 0.5rem; border-bottom: 1px solid var(--tabs-border); vertical-align: middle; color: color-mix(in srgb, var(--text-color) 85%, transparent); font-size: 0.8rem; text-transform: none !important; }
.premium-table th:nth-child(2), .premium-table td:nth-child(2) { text-align: left; overflow: hidden; text-overflow: ellipsis; }
.premium-table tbody tr:last-child td { border-bottom: none; }
.premium-table.row-hover tbody tr:hover { background: var(--table-hover) !important; cursor: pointer; }

.sticky-thead th { position: sticky; top: 0; z-index: 10; box-shadow: 0 2px 4px rgba(0, 0, 0, 0.2); }

.col-center { text-align: center; }
.col-right { text-align: right; }

.cell-stacked { display: flex; flex-direction: column; align-items: flex-end; gap: 0.15rem; line-height: 1.2; }
.cell-main { font-size: 0.85rem; font-weight: 600; }
.cell-sub { font-size: 0.7rem; color: var(--text-muted); font-weight: 400; opacity: 0.8; }

.multi-bar-container { display: flex; flex-direction: column; gap: 0.5rem; width: 100%; min-width: 120px; }
.bar-row { display: flex; align-items: center; gap: 0.5rem; width: 100%; }
.bar-row .bar-container { flex: 1; }
.bar-label { font-size: 0.65rem; text-transform: uppercase; color: var(--text-muted); font-weight: 600; min-width: 36px; text-align: left; opacity: 0.7; }
.bar-container { position: relative; height: 1.2rem; background: rgba(0,0,0,0.06); border-radius: 6px; overflow: hidden; display: flex; align-items: center; min-width: 45px; border: 1px solid rgba(128,128,128,0.12); box-shadow: inset 0 1px 3px rgba(0,0,0,0.08); }
:global(.dark-mode) .bar-container { background: rgba(255,255,255,0.07); border-color: rgba(255,255,255,0.06); }
.bar-fill { position: absolute; top: 0; left: 0; bottom: 0; border-radius: 0 5px 5px 0; transition: width 0.5s cubic-bezier(0.4, 0, 0.2, 1); }
.bar-fill::after { content: ''; position: absolute; inset: 0; background: linear-gradient(to bottom, rgba(255,255,255,0.28) 0%, rgba(255,255,255,0.04) 55%, rgba(0,0,0,0.06) 100%); border-radius: inherit; pointer-events: none; }
.bar-text { position: relative; z-index: 1; width: 100%; text-align: center; font-size: 0.78rem; font-weight: 500; color: var(--text-color); text-shadow: 0 0 2px var(--bg-color), 0 0 4px var(--bg-color); }
.part-fill { background: linear-gradient(90deg, rgba(20, 184, 166, 0.5), rgba(45, 212, 191, 0.7)) !important; opacity: 1 !important; }
.acum-fill { background: linear-gradient(90deg, rgba(129, 140, 248, 0.65), rgba(99, 102, 241, 0.85)) !important; opacity: 1 !important; }
.pd-loc-fill { background: linear-gradient(90deg, #f43f5e, #fb7185) !important; opacity: 0.8 !important; }
.pd-br-fill { background: linear-gradient(90deg, #64748b, #94a3b8) !important; opacity: 0.8 !important; }

.med-id {
  font-weight: 700;
  font-size: 0.88rem;
  color: var(--primary-color);
  text-transform: uppercase;
  letter-spacing: 0.01em;
  margin-bottom: 0.1rem;
}
.med-sub { font-size: 0.72rem; color: var(--text-muted); font-weight: 400; opacity: 0.8; }

.tags-container { display: flex; flex-wrap: wrap; gap: 0.25rem; }
.issue-tag {
  font-size: 0.68rem;
  font-weight: 500;
  padding: 0.2rem 0.6rem;
  border-radius: 99px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 0.3rem;
  white-space: nowrap;
  letter-spacing: 0.01em;
  text-transform: none !important;
  backdrop-filter: blur(4px);
  -webkit-backdrop-filter: blur(4px);
  transition: all 0.2s ease;
  border: 1px solid transparent;
}
.issue-tag:hover { transform: translateY(-1px); box-shadow: 0 2px 8px rgba(0,0,0,0.08); }
.issue-tag i { font-size: 0.65rem; opacity: 0.7; }

.issue-tag.red { background: rgba(239, 68, 68, 0.08); color: #ef4444; border-color: rgba(239, 68, 68, 0.15); }
.issue-tag.orange { background: rgba(245, 158, 11, 0.08); color: #f59e0b; border-color: rgba(245, 158, 11, 0.15); }
.issue-tag.blue-network { background: rgba(59, 130, 246, 0.08); color: #3b82f6; border-color: rgba(59, 130, 246, 0.15); }
.issue-tag.purple-geo { background: rgba(139, 92, 246, 0.08); color: #8b5cf6; border-color: rgba(139, 92, 246, 0.15); }
.issue-tag.amber { background: rgba(245, 158, 11, 0.08); color: #f59e0b; border-color: rgba(245, 158, 11, 0.15); }
.issue-tag.violet { background: rgba(129, 140, 248, 0.08); color: #818cf8; border-color: rgba(129, 140, 248, 0.15); }
.issue-tag.green-ok { background: rgba(16, 185, 129, 0.08); color: #10b981; border-color: rgba(16, 185, 129, 0.15); }

.badge-count { font-size: 0.7rem; font-weight: 600; opacity: 0.8; margin-left: 0.1rem; }
.clickable-badge { cursor: pointer; user-select: none; }
.row-expandable { cursor: pointer; user-select: none; }

.text-red { color: var(--risk-critical) !important; }
.text-purple { color: #8b5cf6 !important; }
.text-orange { color: var(--risk-medium) !important; }

.alertas-diarios-row,
.premium-table.row-hover tbody tr.alertas-diarios-row:hover { background: transparent !important; cursor: default !important; }
.alertas-diarios-table tr:hover { background: transparent !important; }
.alertas-diarios-cell { padding: 0.75rem 1rem !important; border-bottom: 2px solid var(--tabs-border) !important; background: transparent !important; }

/* ── Rank & Medals ──────────────────────────────────────────────────────── */
/* ── Rank Styling (Modern Squircle) ─────────────────────────────────────── */
.rank-badge {
  width: 32px;
  height: 24px;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 6px;
  background: rgba(148, 163, 184, 0.05);
  border: 1px solid rgba(148, 163, 184, 0.1);
  position: relative;
  transition: all 0.3s ease;
}
.rank-val {
  font-family: var(--font-mono);
  font-size: 0.75rem;
  font-weight: 700;
  color: var(--text-muted);
  letter-spacing: -0.02em;
}

/* Estilos de Destaque para o Top 3 */
.rank-badge.gold {
  background: rgba(255, 215, 0, 0.08);
  border-color: rgba(255, 215, 0, 0.4);
  box-shadow: 0 0 12px rgba(255, 215, 0, 0.1);
}
.rank-badge.gold .rank-val { color: #d4af37; }

.rank-badge.silver {
  background: rgba(192, 192, 192, 0.1);
  border-color: rgba(192, 192, 192, 0.4);
}
.rank-badge.silver .rank-val { color: #94a3b8; }

.rank-badge.bronze {
  background: rgba(205, 127, 50, 0.08);
  border-color: rgba(205, 127, 50, 0.4);
}
.rank-badge.bronze .rank-val { color: #a0522d; }

/* Efeito Hover na Linha realça o Rank */
tr:hover .rank-badge {
  transform: translateX(2px);
  border-color: var(--primary-color);
}
tr:hover .rank-badge .rank-val { color: var(--primary-color); }

.alertas-diarios-cell {
  background: var(--card-bg) !important;
  padding: 1.25rem !important;
  border-bottom: 1px solid var(--tabs-border);
}
.alertas-diarios-table { width: 100%; border-collapse: collapse; background: transparent; font-size: 0.78rem; }
.alertas-diarios-table thead tr { background: color-mix(in srgb, var(--text-color) 4%, transparent); }
.alertas-diarios-table th { padding: 0.35rem 0.75rem; font-size: 0.7rem; font-weight: 600; color: var(--text-secondary); text-transform: uppercase; letter-spacing: 0.04em; text-align: left; }
.alertas-diarios-table td { padding: 0.4rem 0.75rem; border-top: 1px solid var(--tabs-border); color: var(--text-color); opacity: 0.8; }
.col-date { font-weight: 400; white-space: nowrap; }
.col-crm { white-space: nowrap; color: var(--text-secondary); font-size: 0.75rem; }
.col-descricao { color: var(--text-secondary); font-size: 0.75rem; }
.col-descricao .desc-num { color: var(--primary-color); font-weight: 500; }
.col-descricao .desc-janela { color: var(--risk-high); font-weight: 500; }

.crm-table-footer { background: var(--card-bg); border-bottom: 1px solid color-mix(in srgb, var(--card-border) 60%, transparent); display: flex; justify-content: center; padding: 0.35rem 0; }
.crm-more-btn { background: none; border: none; font-size: 0.65rem; font-weight: 500; color: var(--primary-color); text-transform: uppercase; letter-spacing: 0.05em; cursor: pointer; display: inline-flex; align-items: center; gap: 0.4rem; padding: 0.2rem 1rem; border-radius: 4px; transition: all 0.2s; opacity: 0.85; }
.crm-more-btn:hover { opacity: 1; background: color-mix(in srgb, var(--primary-color) 8%, transparent); letter-spacing: 0.08em; }
.crm-more-btn i { font-size: 0.7rem; }

/* Estilos da Tabela Geográfica */
.table-subgroup-title {
  background: rgba(139, 92, 246, 0.08) !important;
  color: #8b5cf6 !important;
  font-weight: 800 !important;
  text-align: center !important;
  padding: 0.5rem !important;
  letter-spacing: 0.1em;
}

.geo-cell { line-height: 1.4; padding: 0.6rem 0.75rem !important; }
.geo-main { font-weight: 600; color: var(--text-color); font-size: 0.8rem; opacity: 0.85; }
.geo-sub { font-size: 0.68rem; color: var(--text-color); opacity: 0.75; }

.dist-badge {
  background: rgba(239, 68, 68, 0.1);
  color: #ef4444;
  padding: 2px 6px;
  border-radius: 4px;
  font-weight: 600;
  border: 1px solid rgba(239, 68, 68, 0.2);
}

.geo-detail-table {
  border: 1px solid rgba(139, 92, 246, 0.2);
  border-radius: 6px;
  overflow: hidden;
}



/* ── Evidence Panel (Design Premium) ───────────────────────────────── */
.evidence-panel {
  background: var(--table-expansion-bg);
  border-radius: 8px;
  border: 1px solid var(--card-border);
  box-shadow: 0 4px 20px rgba(0, 0, 0, 0.2);
}
.theme-conc { border-left-color: var(--risk-medium) !important; }
.theme-geo { border-left-color: #8b5cf6 !important; }
.theme-surto { border-left-color: var(--amber-500) !important; }

/* Header do painel */
.panel-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0.65rem 1rem;
  background: color-mix(in srgb, var(--table-expansion-bg) 92%, var(--text-color) 8%);
  border-bottom: 1px solid var(--tabs-border);
  gap: 1rem;
}
.panel-header-left {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  min-width: 0;
}
.panel-icon {
  font-size: 0.8rem;
  color: var(--primary-color);
  flex-shrink: 0;
}

.panel-title {
  font-size: 0.7rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.07em;
  color: var(--text-secondary);
  white-space: nowrap;
}
.panel-crm-badge {
  font-size: 0.65rem;
  font-weight: 600;
  color: var(--text-muted);
  background: color-mix(in srgb, var(--text-color) 8%, transparent);
  border: 1px solid var(--tabs-border);
  border-radius: 4px;
  padding: 1px 6px;
  font-family: var(--font-mono, monospace);
}

/* Segmented Control (Refatorado para 3+ abas) */
.segmented-control {
  display: flex;
  align-items: center;
  background: color-mix(in srgb, var(--text-color) 7%, transparent);
  border: 1px solid var(--tabs-border);
  border-radius: 8px;
  padding: 3px;
  gap: 2px;
  flex-shrink: 0;
}

.segment-btn {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  padding: 0.3rem 0.8rem;
  background: none;
  border: none;
  border-radius: 6px;
  font-size: 0.68rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--text-muted);
  cursor: pointer;
  position: relative;
  z-index: 1;
  transition: all 0.2s ease;
  white-space: nowrap;
}
.segment-btn:hover { background: color-mix(in srgb, var(--text-color) 5%, transparent); }
.segment-btn.seg-active { 
  background: var(--card-bg);
  color: var(--primary-color); 
  box-shadow: 0 1px 4px rgba(0,0,0,0.15);
  border: 1px solid var(--tabs-border);
}
.segment-btn i { font-size: 0.68rem; }

.seg-count {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 16px;
  height: 14px;
  padding: 0 4px;
  background: color-mix(in srgb, var(--primary-color) 12%, transparent);
  color: var(--primary-color);
  border-radius: 99px;
  font-size: 0.58rem;
  font-weight: 600;
}

/* Tabela de evidências (unificada) */
.evidence-table {
  width: 100%;
  border-collapse: collapse;
  background: transparent;
  font-size: 0.78rem;
}
.evidence-table thead tr,
.evidence-table thead tr:hover,
.evidence-table thead tr th,
.evidence-table thead tr:hover th {
  background: color-mix(in srgb, var(--text-color) 4%, transparent) !important;
}
.evidence-table th {
  padding: 0.3rem 0.75rem;
  font-size: 0.65rem;
  font-weight: 600;
  color: var(--text-muted);
  text-transform: uppercase;
  letter-spacing: 0.05em;
  text-align: left;
  border-bottom: 1px solid var(--tabs-border);
  cursor: default;
  user-select: none;
}
.evidence-table td {
  padding: 0.45rem 0.75rem;
  border-top: 1px solid var(--tabs-border);
  color: var(--text-color);
  opacity: 0.85;
}
.evidence-table tbody tr:nth-child(even) { background: color-mix(in srgb, var(--text-color) 2%, transparent); }
.evidence-table tbody tr:hover { background: color-mix(in srgb, var(--text-color) 5%, transparent); }
.theme-conc .evidence-table tbody tr:hover { background: color-mix(in srgb, var(--risk-medium) 8%, transparent); }
.theme-surto .evidence-table tbody tr:hover { background: color-mix(in srgb, var(--amber-500) 8%, transparent); }

/* ── Rede: botão de clique ──────────────────────────────────────────── */
.rede-clickable {
  cursor: pointer;
  text-decoration: underline dotted;
  text-underline-offset: 2px;
  transition: color 0.2s ease;
}
.rede-clickable:hover {
  color: var(--primary-color) !important;
  text-decoration: underline;
}

.time-badge {
  background: color-mix(in srgb, var(--text-color) 7%, transparent);
  padding: 1px 5px;
  border-radius: 4px;
  font-weight: 600;
  font-size: 0.72rem;
  font-family: monospace;
}
.surto-desc { 
  font-size: 0.72rem; 
  opacity: 0.85; 
  line-height: 1.3; 
  display: block; 
  max-width: 400px;
  white-space: normal; 
}
.theme-surto .panel-icon { color: var(--amber-500); }
.theme-surto .seg-active { color: var(--amber-500) !important; }
.theme-surto .td-metric { color: var(--amber-500); font-weight: 600; }
.theme-geo .panel-icon { color: #8b5cf6; }
.theme-geo .seg-active { color: #8b5cf6 !important; }
.theme-conc .panel-icon { color: var(--risk-medium); }
.theme-conc .seg-active { color: var(--risk-medium) !important; }
.theme-conc .td-metric { color: var(--risk-medium); font-weight: 600; }

.clickable-surto-row {
  cursor: pointer;
  transition: background 0.2s ease;
}
</style>
