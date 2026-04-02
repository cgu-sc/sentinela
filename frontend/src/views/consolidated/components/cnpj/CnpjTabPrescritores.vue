<script setup>
import { computed, watch } from 'vue';
import { usePrescritores } from '@/composables/usePrescritores';
import { useFormatting } from '@/composables/useFormatting';

const props = defineProps({
  cnpj: {
    type: String,
    required: true
  }
});

const { prescritoresData, prescritoresLoading, fetchPrescritores } = usePrescritores();
const { formatCurrencyFull, formatNumberFull, formatarData } = useFormatting();

watch(() => props.cnpj, (newCnpj) => {
  console.log('[DEBUG CRMs] Vendo mudança no CNPJ Prop, novo:', newCnpj)
  if (newCnpj) {
    console.log('[DEBUG CRMs] Chamando fetchPrescritores:', newCnpj)
    fetchPrescritores(newCnpj);
  }
}, { immediate: true });

// --- CÁLCULOS DOS KPIs ---
const summary = computed(() => {
  console.log('[DEBUG CRMs] summary computed ativado, data:', prescritoresData.value)
  return prescritoresData.value?.summary || {}
});
const top20 = computed(() => {
  console.log('[DEBUG CRMs] top20 computed ativado, tamanho:', prescritoresData.value?.top20?.length || 0)
  return prescritoresData.value?.top20 || []
});

const concentracaoTop1 = computed(() => summary.value.pct_concentracao_top1 || 0);
const concentracaoTop5 = computed(() => summary.value.pct_concentracao_top5 || 0);
const indiceHHI = computed(() => summary.value.indice_hhi || 0);

// Robôs (Flags no Top 20)
const qtdRobosLocal = computed(() => top20.value.filter(m => m.flag_robo > 0).length);
const qtdRobosOcultos = computed(() => top20.value.filter(m => m.flag_robo_oculto > 0).length);
const qtdRobosTotal = computed(() => qtdRobosLocal.value + qtdRobosOcultos.value);
const mediaRobosBr = computed(() => summary.value.media_robos_brasil || 0);

// CRMs Inválidos
const qtdCrmInvalido = computed(() => summary.value.qtd_crm_inv || top20.value.filter(m => m.flag_crm_invalido > 0).length);

// Antes Registro
const qtdPrescrAntesRegistro = computed(() => top20.value.filter(m => m.flag_prescricao_antes_registro > 0).length);

// Exclusividade
const maxExclusivos = computed(() => summary.value.max_exclusivos || Math.max(...top20.value.map(m => m.pct_volume_aqui_vs_total || 0), 0));
const qtdExclusivos = computed(() => top20.value.filter(m => m.pct_volume_aqui_vs_total > 90).length); // Médicos >90% de exclusividade

// Multi-Farmácia (>20 estabelecimentos)
const qtdMultiFarmacia = computed(() => summary.value.qtd_multi_farmacia || top20.value.filter(m => m.qtd_estabelecimentos_atua > 20).length);
const pctMultiFarmacia = computed(() => summary.value.pct_multi_farmacia || 0);
const multiFarmaciaDetalhe = computed(() => {
  const suspeitos = top20.value.filter(m => m.qtd_estabelecimentos_atua > 20).slice(0, 5);
  return suspeitos.map(m => `${m.id_medico} (${m.qtd_estabelecimentos_atua} farm.)`).join(', ');
});

// Detalhamentos textuais para os cards (Top 5 exemplos)
const robosDetalhe = computed(() => {
  const robos = top20.value.filter(m => m.prescricoes_dia_total_brasil > 30).slice(0, 5);
  return robos.map(m => `${m.id_medico} (${Number(m.prescricoes_dia_total_brasil).toFixed(1)}/dia)`).join(', ');
});

const antesRegistroDetalhe = computed(() => {
  const anormais = top20.value.filter(m => m.flag_prescricao_antes_registro > 0).slice(0, 5);
  return anormais.map(m => `${m.id_medico}`).join(', ');
});

const qtdAcima400km = computed(() => top20.value.filter(m => m.alerta5_geografico).length);
const acima400kmDetalhe = computed(() => {
  const longe = top20.value.filter(m => m.alerta5_geografico).slice(0, 5);
  return longe.map(m => `${m.id_medico}`).join(', ');
});

const qtdTempoConcentrado = computed(() => top20.value.filter(m => m.alerta2_tempo_concentrado || m.alerta2).length);
const tempoConcentradoDetalhe = computed(() => {
  const anormais = top20.value.filter(m => m.alerta2_tempo_concentrado || m.alerta2).slice(0, 5);
  return anormais.map(m => `${m.id_medico}`).join(', ');
});
const indiceRedeSuspeita = computed(() => summary.value.indice_rede_suspeita || 0);

// Helpers de Cor
const getRiskColor = (severity) => {
  if (severity === 'CRITICAL') return 'var(--red-500)';
  if (severity === 'HIGH') return 'var(--orange-500)';
  if (severity === 'MEDIUM') return 'var(--yellow-500)';
  return 'var(--green-500)';
};

// Tooltip e formatting local
const formatPct = (val) => val != null ? `${Number(val).toFixed(2)}%` : '0.00%';
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
      <div class="audit-summary-section">
        <h3 class="section-title"><i class="pi pi-bullseye"></i> Alertas e Anomalias de CRMs</h3>
        
        <div class="alerts-grid">
          <!-- HHI e Concentração -->
          <div class="alert-card shadow-card" :class="(indiceHHI > 2500 || concentracaoTop1 > 20) ? 'highlight-red' : ''">
            <div class="alert-icon"><i class="pi pi-chart-pie"></i></div>
            <div class="alert-content">
              <h4>Concentração (HHI)</h4>
              <p>HHI: <b>{{ formatNumberFull(indiceHHI) }}</b></p>
              <p>Top 1 Médico domina <b>{{ formatPct(concentracaoTop1) }}</b></p>
              <p>Top 5 Médicos dominam <b>{{ formatPct(concentracaoTop5) }}</b></p>
            </div>
          </div>

          <!-- Prescrições Concentradas (Tempo) -->
          <div class="alert-card shadow-card" :class="qtdTempoConcentrado > 0 ? 'highlight-red' : ''">
            <div class="alert-icon"><i class="pi pi-stopwatch"></i></div>
            <div class="alert-content">
              <h4>Presc. Concentradas</h4>
              <p>Todas receitas emitidas em intervalo curto: <b>{{ qtdTempoConcentrado }}</b> médicos</p>
            </div>
          </div>

          <!-- Robôs Local -->
          <div class="alert-card shadow-card" :class="qtdRobosLocal > 0 ? 'highlight-orange' : ''">
            <div class="alert-icon"><i class="pi pi-android"></i></div>
            <div class="alert-content">
              <h4>Comportamento "Robô" (Local)</h4>
              <p>> 30 Prescrições por dia Neste CNPJ: <b>{{ qtdRobosLocal }}</b> médicos</p>
            </div>
          </div>

          <!-- Robôs Nacional -->
          <div class="alert-card shadow-card" :class="qtdRobosOcultos > 0 ? 'highlight-orange' : ''">
            <div class="alert-icon"><i class="pi pi-globe"></i></div>
            <div class="alert-content">
              <h4>Comportamento "Robô" (Nacional)</h4>
              <p>> 30 Prescrições por dia em todos os CNPJs: <b>{{ qtdRobosOcultos }}</b> médicos</p>
            </div>
          </div>

          <!-- Multi-Farmácia (>20) -->
          <div class="alert-card shadow-card" :class="qtdMultiFarmacia > 0 ? 'highlight-orange' : ''">
            <div class="alert-icon"><i class="pi pi-sitemap"></i></div>
            <div class="alert-content">
              <h4>Atuação Multi-Farmácia</h4>
              <p>Atuação em >20 estabelecimentos: <b>{{ qtdMultiFarmacia }}</b> médicos</p>
            </div>
          </div>

          <!-- Exclusividade -->
          <div class="alert-card shadow-card" :class="qtdExclusivos > 0 ? 'highlight-yellow' : ''">
            <div class="alert-icon"><i class="pi pi-lock"></i></div>
            <div class="alert-content">
              <h4>Exclusividade (Teto)</h4>
              <p>Há <b>{{ qtdExclusivos }}</b> médicos que prescrevem quase 100% apenas nesta unidade.</p>
            </div>
          </div>

          <!-- Fraudes Lógicas -->
          <div class="alert-card shadow-card" :class="(qtdCrmInvalido > 0 || qtdPrescrAntesRegistro > 0) ? 'highlight-red' : ''">
            <div class="alert-icon"><i class="pi pi-id-card"></i></div>
            <div class="alert-content">
              <h4>Fraudes Identificáveis</h4>
              <p>CRMs Inválidos: <b class="text-red">{{ qtdCrmInvalido }}</b> médicos</p>
              <p class="mt-2">Vendas ANTES do registro CRM: <b class="text-red">{{ qtdPrescrAntesRegistro }}</b> médicos</p>
            </div>
          </div>

          <!-- Alerta >400km -->
          <div class="alert-card shadow-card" :class="qtdAcima400km > 0 ? 'highlight-yellow' : ''">
            <div class="alert-icon"><i class="pi pi-map-marker"></i></div>
            <div class="alert-content">
              <h4>Alerta >400km</h4>
              <p>Médicos com registro a mais de 400km da farmácia: <b>{{ qtdAcima400km }}</b></p>
            </div>
          </div>
        </div>
      </div>

      <!-- ALERTAS IDENTIFICADOS (DETALHAMENTO TEXTUAL) -->
      <div v-if="robosDetalhe.length > 0 || antesRegistroDetalhe.length > 0 || multiFarmaciaDetalhe.length > 0" class="alerts-details-section section-container">
        <div class="section-header line-header">
           <i class="pi pi-exclamation-triangle text-primary"></i>
           <h3>Alertas Identificados</h3>
        </div>
        
        <div class="alerts-list">
           <div v-if="robosDetalhe.length > 0" class="alert-row">
              <span class="bullet-point bg-orange"></span>
              <div class="alert-row-content">
                 <p class="text-orange">>30 Prescrições por dia em todos os estabelecimentos em que atuam: <b>{{ qtdRobosLocal + qtdRobosOcultos }} médico(s)</b>.</p>
                 <p class="text-muted text-sm">• CRMs: {{ robosDetalhe }}</p>
              </div>
           </div>

           <div v-if="antesRegistroDetalhe.length > 0" class="alert-row">
              <span class="bullet-point bg-red"></span>
              <div class="alert-row-content">
                 <p class="text-red">Prescrição emitida antes do Registro do CRM: <b>{{ qtdPrescrAntesRegistro }} médico(s)</b>.</p>
                 <p class="text-muted text-sm">• CRMs: {{ antesRegistroDetalhe }}</p>
              </div>
           </div>

           <div v-if="tempoConcentradoDetalhe.length > 0" class="alert-row">
              <span class="bullet-point bg-red"></span>
              <div class="alert-row-content">
                 <p class="text-red">Todas as prescrições foram feitas em um intervalo de tempo muito curto: <b>{{ qtdTempoConcentrado }} médico(s)</b>.</p>
                 <p class="text-muted text-sm">• CRMs: {{ tempoConcentradoDetalhe }}</p>
              </div>
           </div>

           <div v-if="multiFarmaciaDetalhe.length > 0" class="alert-row">
              <span class="bullet-point bg-orange"></span>
              <div class="alert-row-content">
                 <p class="text-orange">Médicos com prescrições em >20 estabelecimentos: <b>{{ qtdMultiFarmacia }} médico(s)</b>. ({{ formatPct(summary.pct_multi_farmacia) }})</p>
                 <p class="text-muted text-sm">CRMs Suspeitos: {{ multiFarmaciaDetalhe }}</p>
              </div>
           </div>

           <div v-if="acima400kmDetalhe.length > 0" class="alert-row">
              <span class="bullet-point bg-yellow"></span>
              <div class="alert-row-content">
                 <p class="text-yellow">Distância maior que 400km do CRM até a farmácia: <b>{{ qtdAcima400km }} médico(s)</b>.</p>
                 <p class="text-muted text-sm">• CRMs: {{ acima400kmDetalhe }}</p>
              </div>
           </div>
        </div>
      </div>

      <!-- 2. TABELA COMPARATIVA (MEDIANAS) -->
      <div class="section-container">
         <div class="section-header">
            <h3>Indicadores vs Mercado (Região / Brasil)</h3>
            <p class="subtitle">Compara o comportamento dos médicos que atuam aqui com a média de outras farmácias da região de <b>{{ summary.municipio }}/{{ summary.uf }}</b></p>
         </div>

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
                     <td><i class="pi pi-star text-primary"></i> Concentração % (Top 5)</td>
                     <td class="col-center value-cell">{{ formatPct(summary.pct_concentracao_top5) }}</td>
                     <td class="col-center">{{ formatPct(summary.med_concentracao_top5_reg) }}</td>
                     <td class="col-center">{{ formatPct(summary.media_concentracao_top5_br) }}</td>
                     <td class="col-center risk-cell" :class="{'high-risk': summary.risco_concentracao_top5_reg >= 2}">
                        {{ summary.risco_concentracao_top5_reg ? Number(summary.risco_concentracao_top5_reg).toFixed(1) + 'x' : '—' }}
                     </td>
                  </tr>
                  <tr>
                     <td><i class="pi pi-bullseye text-primary"></i> Índice de Rede (Suspeita)</td>
                     <td class="col-center value-cell">{{ formatPct(summary.indice_rede_suspeita) }}</td>
                     <td class="col-center">{{ formatPct(summary.med_indice_rede_reg) }}</td>
                     <td class="col-center">{{ formatPct(summary.med_indice_rede_br) }}</td>
                     <td class="col-center risk-cell" :class="{'high-risk': summary.risco_indice_rede_reg >= 2}">
                        {{ summary.risco_indice_rede_reg ? Number(summary.risco_indice_rede_reg).toFixed(1) + 'x' : '—' }}
                     </td>
                  </tr>
                  <tr>
                     <td><i class="pi pi-plus-circle text-primary"></i> Médicos Multi-Farmácia</td>
                     <td class="col-center value-cell">{{ formatPct(summary.pct_multi_farmacia) }}</td>
                     <td class="col-center">{{ formatPct(summary.med_multi_farmacia_reg) }}</td>
                     <td class="col-center">{{ formatPct(summary.med_multi_farmacia_br) }}</td>
                     <td class="col-center risk-cell" :class="{'high-risk': summary.risco_multi_farmacia_reg >= 2}">
                        {{ summary.risco_multi_farmacia_reg ? Number(summary.risco_multi_farmacia_reg).toFixed(1) + 'x' : '—' }}
                     </td>
                  </tr>
                  <tr>
                     <td><i class="pi pi-ban text-primary"></i> CRMs Inválidos Encontrados</td>
                     <td class="col-center value-cell">{{ formatPct(summary.pct_crm_invalido) }}</td>
                     <td class="col-center">{{ formatPct(summary.med_crm_invalido_reg) }}</td>
                     <td class="col-center">{{ formatPct(summary.med_crm_invalido_br) }}</td>
                     <td class="col-center risk-cell" :class="{'high-risk': summary.risco_crm_invalido_reg >= 2}">
                        {{ summary.risco_crm_invalido_reg ? Number(summary.risco_crm_invalido_reg).toFixed(1) + 'x' : '—' }}
                     </td>
                  </tr>
               </tbody>
            </table>
         </div>
      </div>

      <!-- 3. TOP 20 CRMs (TABELA DETALHADA) -->
      <div class="section-container">
         <div class="section-header">
            <h3>Top 20 Prescritores Concentrados</h3>
            <p class="subtitle">Detalhamento dos médicos que mais aprovaram medicamentos nesta unidade, ordenados pelo financeiro.</p>
         </div>

         <div class="table-responsive" style="max-height: 500px; overflow-y: auto;">
            <table class="ind-table premium-table row-hover">
               <thead class="sticky-thead">
                  <tr>
                     <th style="width: 40px">#</th>
                     <th>Médico / CRM</th>
                     <th>Flags / Alertas Ocultos</th>
                     <th class="col-right">Autorizações</th>
                     <th class="col-right">Vol (R$)</th>
                     <th class="col-center">% Part. CNPJ</th>
                     <th class="col-center">Qtd / Dia (Nacional)</th>
                     <th class="col-center">Exclusividade Aqui</th>
                  </tr>
               </thead>
               <tbody>
                  <tr v-for="(m, i) in top20" :key="i" :class="{'severe-row': m.flag_robo > 0 || m.flag_crm_invalido > 0 || m.flag_prescricao_antes_registro > 0}">
                     <td><b>{{ i + 1 }}</b></td>
                     <td>
                        <div class="med-id">{{ m.id_medico }}</div>
                        <div class="med-sub">Registro: {{ m.dt_inscricao_crm ? formatarData(m.dt_inscricao_crm) : 'ND' }}</div>
                     </td>
                     <td class="flags-cell">
                        <div class="tags-container">
                           <span v-if="m.flag_robo" class="issue-tag red"><i class="pi pi-android"></i> Robô Aqui</span>
                           <span v-if="m.flag_robo_oculto && !m.flag_robo" class="issue-tag orange"><i class="pi pi-globe"></i> Robô BR</span>
                           <span v-if="m.alerta2_tempo_concentrado || m.alerta2" class="issue-tag red"><i class="pi pi-stopwatch"></i> Curto Espaço</span>
                           <span v-if="m.flag_crm_invalido" class="issue-tag dark-red"><i class="pi pi-ban"></i> Inválido</span>
                           <span v-if="m.flag_prescricao_antes_registro" class="issue-tag dark-red"><i class="pi pi-calendar-times"></i> Fraude Data</span>
                           <span v-if="m.pct_volume_aqui_vs_total > 90" class="issue-tag purple"><i class="pi pi-lock"></i> Exclusivo</span>
                           <span v-if="m.alerta5_geografico" class="issue-tag yellow"><i class="pi pi-map-marker"></i> >400km</span>
                           <span v-if="!m.flag_robo && !m.flag_robo_oculto && !m.flag_crm_invalido && !m.flag_prescricao_antes_registro && m.pct_volume_aqui_vs_total <= 90 && !m.alerta5_geografico" class="text-muted text-xs">Regular</span>
                        </div>
                     </td>
                     <td class="col-right font-mono">{{ formatNumberFull(m.nu_prescricoes) }}</td>
                     <td class="col-right font-mono text-primary font-bold">{{ formatCurrencyFull(m.vl_total_prescricoes) }}</td>
                     <td class="col-center">
                        <div class="bar-container">
                           <div class="bar-fill" :style="{ width: Math.min(m.pct_participacao, 100) + '%' }"></div>
                           <span class="bar-text">{{ formatPct(m.pct_participacao) }}</span>
                        </div>
                     </td>
                     <td class="col-center font-mono">
                        <span :class="{'text-red font-bold': m.prescricoes_dia_total_brasil > 30}">{{ formatNumberFull(m.prescricoes_dia_total_brasil) }}</span> / dia
                     </td>
                     <td class="col-center">
                        <span :class="{'text-purple font-bold': m.pct_volume_aqui_vs_total > 90}">{{ formatPct(m.pct_volume_aqui_vs_total) }}</span>
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

.loading-state, .empty-state {
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
.empty-icon { font-size: 3rem; margin-bottom: 1rem; opacity: 0.5; }
.loading-state i { font-size: 2rem; margin-bottom: 1rem; color: var(--primary-color); }

.content-wrapper {
  display: flex;
  flex-direction: column;
  gap: 2rem;
}

/* 1. RESUMO AUDITORIA */
.audit-summary-section {
  display: flex;
  flex-direction: column;
  gap: 1rem;
}
.section-title {
  margin: 0;
  font-size: 1.1rem;
  font-weight: 700;
  color: var(--text-color);
  display: flex;
  align-items: center;
  gap: 0.5rem;
}
.section-title i { color: var(--primary-color); }

.alerts-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
  gap: 1rem;
}

.alert-card {
  position: relative;
  display: flex;
  align-items: flex-start;
  gap: 1rem;
  padding: 1.25rem;
  background: var(--table-stripe); /* Fallback nativo: um tom ligeiramente distinto do fundo */
  border: 1px solid var(--sidebar-border); /* Borda padrão do sentinela importada do themeConfig */
  border-radius: 12px;
  overflow: hidden;
  transition: transform 0.2s, box-shadow 0.2s;
}
.alert-card:hover {
  transform: translateY(-2px);
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
  background: var(--table-hover);
}
.alert-icon {
  font-size: 1.5rem;
  padding: 0.75rem;
  background: var(--card-bg);
  border: 1px solid var(--sidebar-border);
  border-radius: 8px;
  color: var(--text-color);
  flex-shrink: 0;
}

.alert-content {
  flex: 1;
  min-width: 0;
  padding-right: 5rem; /* Evita que o badge absoluto sobreponha o texto */
}

.alert-content h4 {
  margin: 0 0 0.5rem 0;
  font-size: 0.85rem;
  font-weight: 700;
  color: var(--text-color);
  text-transform: none; /* Garante que mantenha o case das outras abas se possivel */
}
.alert-content p {
  margin: 0.25rem 0;
  font-size: 0.75rem;
  color: var(--text-secondary);
  text-transform: none;
}
.alert-content b { color: var(--text-color); }

.risk-badge {
  position: absolute;
  top: 0;
  right: 0;
  padding: 0.35rem 0.6rem;
  font-size: 0.7rem;
  font-weight: 700;
  text-transform: uppercase;
  border-bottom-left-radius: 8px;
}
.risk-badge.red { background: rgba(239,68,68,0.2); color: #ef4444; }
.risk-badge.orange { background: rgba(249,115,22,0.2); color: #f97316; }
.risk-badge.yellow { background: rgba(234,179,8,0.2); color: #eab308; }

.highlight-red { border-color: rgba(239,68,68,0.4) !important; background: rgba(239,68,68,0.05) !important; }
.highlight-red .alert-icon { color: #ef4444; background: rgba(239,68,68,0.1); }
.text-red { color: #ef4444 !important; }

.highlight-orange { border-color: rgba(249,115,22,0.4) !important; background: rgba(249,115,22,0.05) !important; }
.highlight-orange .alert-icon { color: #f97316; background: rgba(249,115,22,0.1); }

.highlight-yellow { border-color: rgba(234,179,8,0.4) !important; background: rgba(234,179,8,0.05) !important; }
.highlight-yellow .alert-icon { color: #eab308; background: rgba(234,179,8,0.1); }

/* 2. SECTION & TABLES */
.section-container {
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
  background: var(--surface-bg);
  border: 1px solid var(--border-color);
  border-radius: 12px;
  padding: 1.25rem;
}
.section-header h3 { margin: 0; font-size: 1rem; color: var(--text-color); }
.subtitle { margin: 0.25rem 0 0 0; font-size: 0.8rem; color: var(--text-muted); }

.table-responsive {
  overflow-x: auto;
  border-radius: 8px;
  border: 1px solid var(--border-color);
}

.premium-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 0.85rem;
}
.premium-table th {
  background: rgba(0,0,0,0.03);
  color: var(--text-secondary);
  font-weight: 600;
  text-transform: uppercase;
  font-size: 0.75rem;
  padding: 0.75rem 1rem;
  letter-spacing: 0.04em;
  border-bottom: 2px solid var(--border-color);
  white-space: nowrap;
}
:global(.dark-mode) .premium-table th {
  background: rgba(255,255,255,0.03);
}
.premium-table td {
  padding: 0.75rem 1rem;
  border-bottom: 1px solid var(--border-color);
  color: var(--text-color);
}
.premium-table tbody tr:last-child td { border-bottom: none; }
.premium-table.row-hover tbody tr:hover { background: rgba(0,0,0,0.03); }
:global(.dark-mode) .premium-table.row-hover tbody tr:hover { background: rgba(255,255,255,0.05); }

.sticky-thead th {
  position: sticky;
  top: 0;
  z-index: 2;
}

.col-center { text-align: center; }
.col-right { text-align: right; }
.font-mono { font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace; }

/* Table Specific Components */
.value-cell { font-weight: 700; color: var(--text-color); }
.risk-cell { font-weight: 700; font-family: monospace; color: var(--text-secondary); }
.high-risk { color: #ef4444; background: rgba(239,68,68,0.1); border-radius: 4px; }

.severe-row { background: rgba(239,68,68,0.02); }

.med-id { font-weight: 600; font-size: 0.85rem; }
.med-sub { font-size: 0.7rem; color: var(--text-muted); }

.mt-1 { margin-top: 0.25rem; }
.mt-2 { margin-top: 0.5rem; }
.mt-0 { margin-top: 0; }

/* Alerts List Section */
.alerts-details-section { gap: 1rem; }
.line-header {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  background: var(--table-stripe);
  padding: 0.5rem 1rem;
  border-radius: 6px;
  border-left: 4px solid var(--primary-color);
  color: var(--text-color);
}
.line-header h3 { font-size: 0.9rem; margin: 0; text-transform: uppercase; letter-spacing: 0.03em; }

.alerts-list {
  display: flex;
  flex-direction: column;
  gap: 1.25rem;
  padding: 0.5rem;
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
.bg-orange { background: #f97316; }
.bg-red { background: #dc2626; }
.bg-yellow { background: #eab308; }

.alert-row-content p { margin: 0; font-size: 0.85rem; }
.alert-row-content .text-orange { color: #f97316; font-weight: 600; }
.alert-row-content .text-red { color: #ef4444; font-weight: 600; }
.alert-row-content .text-yellow { color: #ca8a04; font-weight: 600; }
.alert-row-content .text-sm { font-size: 0.80rem; margin-top: 0.25rem; color: var(--text-secondary); }

.tags-container {
  display: flex;
  flex-wrap: wrap;
  gap: 0.25rem;
}
.issue-tag {
  font-size: 0.65rem;
  font-weight: 700;
  padding: 0.1rem 0.4rem;
  border-radius: 4px;
  display: inline-flex;
  align-items: center;
  gap: 0.25rem;
  white-space: nowrap;
}
.issue-tag i { font-size: 0.65rem; }
.issue-tag.red { background: rgba(239,68,68,0.1); color: #ef4444; border: 1px solid rgba(239,68,68,0.2); }
.issue-tag.dark-red { background: rgba(220,38,38,0.1); color: #dc2626; border: 1px solid rgba(220,38,38,0.2); }
.issue-tag.orange { background: rgba(249,115,22,0.1); color: #f97316; border: 1px solid rgba(249,115,22,0.2); }
.issue-tag.yellow { background: rgba(234,179,8,0.1); color: #eab308; border: 1px solid rgba(234,179,8,0.2); }
.issue-tag.purple { background: rgba(168,85,247,0.1); color: #a855f7; border: 1px solid rgba(168,85,247,0.2); }

.bar-container {
  position: relative;
  height: 1.25rem;
  background: rgba(0,0,0,0.05);
  border-radius: 4px;
  overflow: hidden;
  display: flex;
  align-items: center;
  min-width: 60px;
}
:global(.dark-mode) .bar-container {
  background: rgba(255,255,255,0.1);
}
.bar-fill {
  position: absolute;
  top: 0; left: 0; bottom: 0;
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
