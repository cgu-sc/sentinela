<script setup>
import { computed, ref, watch } from "vue";
import { useThemeStore } from '@/stores/theme';
import { useFormatting } from "@/composables/useFormatting";

const props = defineProps({
  crmsInteresse:    { type: Array,  required: true },
  activeKpiFilter:  { type: String, default: null },
  kpiFilters:       { type: Object, required: true },
  kpiFilterLabels:  { type: Object, required: true },
});

const emit = defineEmits(['clear-filters']);

const themeStore = useThemeStore();
const raioxBg = computed(() => themeStore.isDark ? 'rgba(0,0,0,0.15)' : 'rgba(255,255,255,0.6)');

const { formatCurrencyFull, formatNumberFull, formatarData } = useFormatting();
const formatPct = (val) => val != null ? `${Number(val).toFixed(2)}%` : "0.00%";

const filterOnlyIssues = ref(false);
const showAllCrms = ref(false);
const expandedAlertasMedico = ref(new Set());

watch(() => props.activeKpiFilter, (newVal) => {
  if (newVal !== null) filterOnlyIssues.value = false;
});

function toggleAlertasDiarios(idMedico) {
  if (expandedAlertasMedico.value.has(idMedico)) { expandedAlertasMedico.value.delete(idMedico); }
  else { expandedAlertasMedico.value.add(idMedico); }
  expandedAlertasMedico.value = new Set(expandedAlertasMedico.value);
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
              :class="{ 'row-expandable': m.alerta_concentracao_mesmo_crm }"
              @click="m.alerta_concentracao_mesmo_crm && toggleAlertasDiarios(m.id_medico)"
            >
              <td class="col-center">
                <div class="rank-container">
                  <div v-if="i === 0" class="rank-medal gold" v-tooltip.top="'Líder de Volume'">
                    <i class="pi pi-award"></i>
                  </div>
                  <div v-else-if="i === 1" class="rank-medal silver">
                    <span>2</span>
                  </div>
                  <div v-else-if="i === 2" class="rank-medal bronze">
                    <span>3</span>
                  </div>
                  <div v-else class="rank-number">
                    {{ i + 1 }}
                  </div>
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
                    <span v-if="m.alertas_diarios?.length > 1" class="badge-count">({{ m.alertas_diarios.length }}x)</span>
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
                  <span v-if="m.alerta5_geografico" class="issue-tag purple-geo" v-tooltip.top="'Distância superior a 400km entre prescritor e farmácia'">
                    <i class="pi pi-map-marker"></i> DISTÂNCIA >400KM
                  </span>
                  <span v-if="m.flag_concentracao_estabelecimento" class="issue-tag amber" v-tooltip.top="'O registro deste médico ocorreu durante uma concentração horária anômala no estabelecimento'">
                    <i class="pi pi-bolt"></i> CONCENTRAÇÃO CRMs DIVERSOS
                  </span>
                  <i
                    v-if="!m.flag_robo && !m.flag_robo_oculto && !m.flag_crm_invalido && !m.flag_prescricao_antes_registro && !m.alerta5_geografico && !m.flag_concentracao_estabelecimento && (!m.flag_crm_exclusivo || m.flag_crm_exclusivo === 0)"
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
                <span :class="{ 'text-purple': m.qtd_estabelecimentos_atua > 50 }">{{ m.qtd_estabelecimentos_atua }}</span> farm.
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

            <!-- Linha expandida de alertas diários -->
            <tr v-if="expandedAlertasMedico.has(m.id_medico) && m.alertas_diarios?.length" class="alertas-diarios-row">
              <td colspan="11" class="alertas-diarios-cell">
                <div class="alertas-wrapper">
                  <table class="alertas-diarios-table">
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
                        <td class="col-right">{{ a.nu_prescricoes }}</td>
                        <td class="col-center">{{ formatarJanela(a.nu_minutos) }}</td>
                        <td class="col-right">{{ a.taxa_hora?.toFixed(1) }}/h</td>
                        <td class="col-descricao" v-html="formatDescricao(a)" />
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
.filter-count { font-weight: 800; margin-left: 0.2rem; }
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
.rank-container { display: flex; align-items: center; justify-content: center; }
.rank-medal {
  width: 24px;
  height: 24px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 0.7rem;
  font-weight: 800;
  box-shadow: 0 2px 6px rgba(0,0,0,0.15);
  position: relative;
}
.rank-medal::after {
  content: '';
  position: absolute;
  inset: -2px;
  border-radius: 50%;
  opacity: 0.3;
  border: 1px solid currentColor;
}
.rank-medal.gold { background: linear-gradient(135deg, #FFD700, #B8860B); color: #fff; text-shadow: 0 1px 2px rgba(0,0,0,0.2); }
.rank-medal.silver { background: linear-gradient(135deg, #C0C0C0, #708090); color: #fff; }
.rank-medal.bronze { background: linear-gradient(135deg, #CD7F32, #8B4513); color: #fff; }
.rank-medal i { font-size: 0.85rem; }
.rank-number { font-size: 0.75rem; font-weight: 600; color: var(--text-muted); opacity: 0.6; }

.alertas-wrapper {
  background: v-bind(raioxBg);
  backdrop-filter: blur(8px);
  -webkit-backdrop-filter: blur(8px);
  border: 1px solid var(--card-border);
  border-left: 3px solid color-mix(in srgb, var(--risk-high) 50%, transparent);
  border-radius: 8px;
  overflow: hidden;
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
</style>
