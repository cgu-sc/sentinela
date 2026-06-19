<script setup>
import { ref, onMounted } from 'vue';
import Dropdown from 'primevue/dropdown';
import InputNumber from 'primevue/inputnumber';
import InputText from 'primevue/inputtext';
import { useToast } from 'primevue/usetoast';
import { useNotaTecnicaConfigStore } from '@/stores/notaTecnicaConfig';
import { useMetodologiaConfigStore } from '@/stores/metodologiaConfig';

const notaTecnicaConfig = useNotaTecnicaConfigStore();
const metodologiaConfig = useMetodologiaConfigStore();
const toast = useToast();

const activeSection = ref('nota-tecnica');

const sections = [
  { id: 'nota-tecnica', label: 'Nota Técnica', icon: 'pi-file-edit' },
  { id: 'metodologia', label: 'Metodologia', icon: 'pi-chart-line' },
];

async function saveNotaTecnicaRegional(event) {
  try {
    await notaTecnicaConfig.saveRegionalCodigo(event.value);
    toast.add({ severity: 'success', summary: 'Salvo', detail: 'Regional emissora atualizada.', life: 3000 });
  } catch (error) {
    toast.add({ severity: 'warn', summary: 'Regional da Nota Técnica', detail: error?.message || 'Não foi possível salvar a regional emissora.', life: 6000 });
  }
}

async function saveNotaTecnicaFull() {
  try {
    await notaTecnicaConfig.saveNotaTecnicaConfig({
      regionalCodigo: notaTecnicaConfig.selectedRegionalCodigo,
      numeroNota: notaTecnicaConfig.ultimoNumeroNota,
      numeroProcesso: notaTecnicaConfig.ultimoNumeroProcesso,
      assinantes: notaTecnicaConfig.assinantesTecnicos,
    });
    toast.add({ severity: 'success', summary: 'Salvo', detail: 'Configurações da Nota Técnica atualizadas.', life: 3000 });
  } catch (error) {
    toast.add({ severity: 'warn', summary: 'Nota Técnica', detail: error?.message || 'Não foi possível salvar.', life: 6000 });
  }
}

async function saveVolumeAtipicoAumentoMinimo() {
  try {
    await metodologiaConfig.saveVolumeAtipicoAumentoMinimo(metodologiaConfig.volumeAtipicoAumentoMinimo);
    toast.add({ severity: 'success', summary: 'Salvo', detail: 'Aumento mínimo atualizado.', life: 3000 });
  } catch (error) {
    toast.add({ severity: 'warn', summary: 'Metodologia de Alertas', detail: error?.response?.data?.detail || error?.message || 'Não foi possível salvar.', life: 6000 });
  }
}

async function saveAuditHighValue() {
  try {
    await metodologiaConfig.saveAuditHighValue(metodologiaConfig.auditHighValue);
    toast.add({ severity: 'success', summary: 'Salvo', detail: 'Destaque financeiro atualizado.', life: 3000 });
  } catch (error) {
    toast.add({ severity: 'warn', summary: 'Metodologia de Alertas', detail: error?.response?.data?.detail || error?.message || 'Não foi possível salvar.', life: 6000 });
  }
}

function updateAssinante(index, field, value) {
  const list = notaTecnicaConfig.assinantesTecnicos.slice();
  while (list.length <= index) list.push({ nome: '', cargo: '' });
  list[index] = { ...list[index], [field]: value };
  notaTecnicaConfig.$patch((state) => { state.assinantesTecnicos = list; });
}

const isSyncing = ref(false);
const isSavingNT = ref(false);

async function saveNotaTecnicaFullWithFeedback() {
  isSavingNT.value = true;
  try {
    await saveNotaTecnicaFull();
  } finally {
    isSavingNT.value = false;
  }
}

onMounted(() => {
  notaTecnicaConfig.ensureLoaded().catch((error) => {
    toast.add({ severity: 'warn', summary: 'Nota Técnica', detail: error?.message || 'Não foi possível carregar.', life: 6000 });
  });
  metodologiaConfig.ensureLoaded().catch((error) => {
    toast.add({ severity: 'warn', summary: 'Metodologia', detail: error?.response?.data?.detail || error?.message || 'Não foi possível carregar.', life: 6000 });
  });
});
</script>

<template>
  <div class="cfg-root">
    <div class="cfg-topbar">
      <div class="cfg-topbar-inner">
        <div class="cfg-topbar-left">
          <div class="cfg-topbar-icon">
            <i class="pi pi-sliders-h" />
          </div>
          <div>
            <div class="cfg-topbar-title">Configurações</div>
            <div class="cfg-topbar-sub">Parâmetros operacionais persistidos automaticamente</div>
          </div>
        </div>
        <div class="cfg-sync-badge" :class="{ 'is-syncing': notaTecnicaConfig.loading || metodologiaConfig.loading }">
          <i :class="['pi', notaTecnicaConfig.loading || metodologiaConfig.loading ? 'pi-spin pi-spinner' : 'pi-check-circle']" />
          <span>{{ notaTecnicaConfig.loading || metodologiaConfig.loading ? 'Carregando…' : 'Sincronizado' }}</span>
        </div>
      </div>
    </div>

    <div class="cfg-body">
      <nav class="cfg-nav">
        <button
          v-for="sec in sections"
          :key="sec.id"
          class="cfg-nav-item"
          :class="{ active: activeSection === sec.id }"
          @click="activeSection = sec.id"
        >
          <i :class="['pi', sec.icon]" />
          <span>{{ sec.label }}</span>
        </button>
      </nav>

      <div class="cfg-content">

        <!-- NOTA TÉCNICA -->
        <template v-if="activeSection === 'nota-tecnica'">
          <div class="cfg-section-header">
            <div>
              <div class="cfg-section-title">Nota Técnica</div>
              <div class="cfg-section-desc">Dados institucionais e de emissão usados no cabeçalho e assinatura dos documentos gerados.</div>
            </div>
          </div>

          <div class="cfg-group">
            <div class="cfg-group-label">Regional emissora</div>
            <div class="cfg-group-body">
              <div class="cfg-field">
                <label class="cfg-label">Código da regional</label>
                <Dropdown
                  v-model="notaTecnicaConfig.selectedRegionalCodigo"
                  :options="notaTecnicaConfig.regionais"
                  optionLabel="estado"
                  optionValue="codigo"
                  filter
                  class="cfg-dropdown"
                  placeholder="Selecione a regional"
                  :loading="notaTecnicaConfig.loading"
                  @change="saveNotaTecnicaRegional"
                >
                  <template #option="{ option }">
                    <div class="cfg-dropdown-option">
                      <span>{{ option.codigo }} — {{ option.estado }}</span>
                      <small>{{ option.nome_unidade }}</small>
                    </div>
                  </template>
                  <template #value="{ value }">
                    <span v-if="value">{{ notaTecnicaConfig.selectedRegionalLabel }}</span>
                    <span v-else class="cfg-placeholder">Selecione a regional</span>
                  </template>
                </Dropdown>
              </div>

              <div v-if="notaTecnicaConfig.selectedRegional" class="cfg-detail-grid">
                <div class="cfg-detail-row">
                  <span class="cfg-detail-key">Unidade</span>
                  <span class="cfg-detail-val">{{ notaTecnicaConfig.selectedRegional.nome_unidade }}</span>
                </div>
                <div class="cfg-detail-row">
                  <span class="cfg-detail-key">Endereço</span>
                  <span class="cfg-detail-val">{{ notaTecnicaConfig.selectedRegional.linha_endereco }}</span>
                </div>
                <div class="cfg-detail-row">
                  <span class="cfg-detail-key">Superintendente</span>
                  <span class="cfg-detail-val">{{ notaTecnicaConfig.selectedRegional.superintendente }}</span>
                </div>
              </div>
            </div>
          </div>

          <div class="cfg-group">
            <div class="cfg-group-label">Numeração</div>
            <div class="cfg-group-body cfg-row-2">
              <div class="cfg-field">
                <label class="cfg-label">Último número de nota</label>
                <InputText
                  v-model="notaTecnicaConfig.ultimoNumeroNota"
                  class="cfg-input"
                  placeholder="Ex: 001/2025"
                  :disabled="notaTecnicaConfig.loading"
                />
              </div>
              <div class="cfg-field">
                <label class="cfg-label">Último número de processo</label>
                <InputText
                  v-model="notaTecnicaConfig.ultimoNumeroProcesso"
                  class="cfg-input"
                  placeholder="Ex: 00000.000000/2025-00"
                  :disabled="notaTecnicaConfig.loading"
                />
              </div>
            </div>
          </div>

          <div class="cfg-group">
            <div class="cfg-group-label">Assinantes técnicos <span class="cfg-group-badge">até 3</span></div>
            <div class="cfg-group-body">
              <div
                v-for="(assinante, index) in [0, 1, 2]"
                :key="index"
                class="cfg-assinante"
              >
                <div class="cfg-assinante-index">{{ index + 1 }}</div>
                <div class="cfg-row-2 cfg-assinante-fields">
                  <div class="cfg-field">
                    <label class="cfg-label">Nome</label>
                    <InputText
                      :value="notaTecnicaConfig.assinantesTecnicos[index]?.nome ?? ''"
                      class="cfg-input"
                      placeholder="Nome completo"
                      :disabled="notaTecnicaConfig.loading"
                      @input="updateAssinante(index, 'nome', $event.target.value)"
                    />
                  </div>
                  <div class="cfg-field">
                    <label class="cfg-label">Cargo / Matrícula</label>
                    <InputText
                      :value="notaTecnicaConfig.assinantesTecnicos[index]?.cargo ?? ''"
                      class="cfg-input"
                      placeholder="Auditor Federal de Finanças e Controle"
                      :disabled="notaTecnicaConfig.loading"
                      @input="updateAssinante(index, 'cargo', $event.target.value)"
                    />
                  </div>
                </div>
              </div>
            </div>
          </div>

          <div class="cfg-actions">
            <button
              class="cfg-btn-save"
              :disabled="notaTecnicaConfig.loading || isSavingNT"
              @click="saveNotaTecnicaFullWithFeedback"
            >
              <i :class="['pi', isSavingNT ? 'pi-spin pi-spinner' : 'pi-save']" />
              <span>Salvar configurações da Nota Técnica</span>
            </button>
          </div>
        </template>

        <!-- METODOLOGIA -->
        <template v-else-if="activeSection === 'metodologia'">
          <div class="cfg-section-header">
            <div>
              <div class="cfg-section-title">Metodologia de Alertas</div>
              <div class="cfg-section-desc">Parâmetros usados nas regras dinâmicas de classificação e pontuação dos alertas do sistema.</div>
            </div>
          </div>

          <div class="cfg-group">
            <div class="cfg-group-label">Volume atípico — crescimento semestral</div>
            <div class="cfg-group-body">
              <div class="cfg-field">
                <label class="cfg-label">Aumento absoluto mínimo</label>
                <div class="cfg-input-with-hint">
                  <InputNumber
                    v-model="metodologiaConfig.volumeAtipicoAumentoMinimo"
                    class="cfg-input-number"
                    mode="currency"
                    currency="BRL"
                    locale="pt-BR"
                    :min="metodologiaConfig.volumeAtipicoLimits?.min"
                    :max="metodologiaConfig.volumeAtipicoLimits?.max"
                    :minFractionDigits="2"
                    :maxFractionDigits="2"
                    :disabled="metodologiaConfig.loading || metodologiaConfig.saving || !metodologiaConfig.loaded"
                    @blur="saveVolumeAtipicoAumentoMinimo"
                  />
                  <span class="cfg-input-hint">
                    Padrão:
                    {{ metodologiaConfig.volumeAtipicoDefault?.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' }) }}
                  </span>
                </div>
              </div>

              <div class="cfg-rule-card">
                <div class="cfg-rule-icon"><i class="pi pi-info-circle" /></div>
                <div class="cfg-rule-text">
                  Um estabelecimento é marcado com alerta de volume atípico quando o crescimento semestral supera <strong>50%</strong> e o aumento absoluto é igual ou superior ao valor configurado acima.
                </div>
              </div>
            </div>
          </div>

          <div class="cfg-group">
            <div class="cfg-group-label">Auditoria financeira</div>
            <div class="cfg-group-body">
              <div class="cfg-field">
                <label class="cfg-label">Destaque financeiro de auditoria</label>
                <div class="cfg-input-with-hint">
                  <InputNumber
                    v-model="metodologiaConfig.auditHighValue"
                    class="cfg-input-number"
                    mode="currency"
                    currency="BRL"
                    locale="pt-BR"
                    :min="metodologiaConfig.auditHighValueLimits?.min"
                    :max="metodologiaConfig.auditHighValueLimits?.max"
                    :minFractionDigits="2"
                    :maxFractionDigits="2"
                    :disabled="metodologiaConfig.loading || metodologiaConfig.saving || !metodologiaConfig.loaded"
                    @blur="saveAuditHighValue"
                  />
                  <span class="cfg-input-hint">
                    Padrão:
                    {{ metodologiaConfig.auditHighValueDefault?.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' }) }}
                  </span>
                </div>
              </div>

              <div class="cfg-rule-card">
                <div class="cfg-rule-icon"><i class="pi pi-info-circle" /></div>
                <div class="cfg-rule-text">
                  Valores financeiros auditáveis iguais ou superiores a este limite recebem <strong>destaque visual</strong> nas tabelas de dispensação e memória de cálculo.
                </div>
              </div>
            </div>
          </div>
        </template>

      </div>
    </div>
  </div>
</template>

<style scoped>
/* ── Root ─────────────────────────────────────────────── */
.cfg-root {
  min-height: 100vh;
  background: var(--bg-color);
  color: var(--text-color-85);
  display: flex;
  flex-direction: column;
}

/* ── Topbar ───────────────────────────────────────────── */
.cfg-topbar {
  background: var(--card-bg);
  border-bottom: 1px solid var(--card-border);
  padding: 0 2rem;
  height: 56px;
  display: flex;
  align-items: center;
  position: sticky;
  top: 0;
  z-index: 100;
}

.cfg-topbar-inner {
  width: 100%;
  max-width: 1100px;
  margin: 0 auto;
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.cfg-topbar-left {
  display: flex;
  align-items: center;
  gap: 0.875rem;
}

.cfg-topbar-icon {
  width: 34px;
  height: 34px;
  border-radius: 8px;
  background: color-mix(in srgb, var(--primary-color) 12%, transparent);
  color: var(--primary-color);
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 0.95rem;
  flex-shrink: 0;
}

.cfg-topbar-title {
  font-size: 0.95rem;
  font-weight: 600;
  color: var(--text-color-85);
  line-height: 1.2;
}

.cfg-topbar-sub {
  font-size: 0.72rem;
  color: var(--text-muted);
  margin-top: 1px;
}

.cfg-sync-badge {
  display: flex;
  align-items: center;
  gap: 0.45rem;
  font-size: 0.72rem;
  color: var(--text-muted);
  background: var(--bg-color);
  border: 1px solid var(--card-border);
  border-radius: 999px;
  padding: 0.3rem 0.75rem;
  transition: color 0.2s;
}

.cfg-sync-badge i {
  color: var(--primary-color);
  font-size: 0.8rem;
}

.cfg-sync-badge.is-syncing {
  color: var(--primary-color);
}

/* ── Body layout ──────────────────────────────────────── */
.cfg-body {
  display: flex;
  width: 100%;
  max-width: 1100px;
  margin: 0 auto;
  padding: 2rem 2rem 4rem;
  gap: 2rem;
  align-items: flex-start;
}

/* ── Nav ──────────────────────────────────────────────── */
.cfg-nav {
  width: 190px;
  flex-shrink: 0;
  position: sticky;
  top: 72px;
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.cfg-nav-item {
  display: flex;
  align-items: center;
  gap: 0.6rem;
  padding: 0.6rem 0.8rem;
  border-radius: 8px;
  border: none;
  background: transparent;
  color: var(--text-muted);
  font-size: 0.82rem;
  font-weight: 500;
  cursor: pointer;
  text-align: left;
  width: 100%;
  transition: background 0.15s, color 0.15s;
}

.cfg-nav-item:hover {
  background: color-mix(in srgb, var(--text-color-85) 5%, transparent);
  color: var(--text-color-85);
}

.cfg-nav-item.active {
  background: color-mix(in srgb, var(--primary-color) 12%, transparent);
  color: var(--primary-color);
}

.cfg-nav-item i {
  font-size: 0.85rem;
  width: 16px;
  text-align: center;
}

/* ── Content area ─────────────────────────────────────── */
.cfg-content {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 1.25rem;
}

/* ── Section header ───────────────────────────────────── */
.cfg-section-header {
  padding-bottom: 1rem;
  border-bottom: 1px solid var(--card-border);
}

.cfg-section-title {
  font-size: 1rem;
  font-weight: 600;
  color: var(--text-color-85);
  margin-bottom: 0.3rem;
}

.cfg-section-desc {
  font-size: 0.78rem;
  color: var(--text-muted);
  line-height: 1.55;
}

/* ── Group ────────────────────────────────────────────── */
.cfg-group {
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
}

.cfg-group-label {
  font-size: 0.68rem;
  font-weight: 600;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  color: var(--text-muted);
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.cfg-group-badge {
  background: color-mix(in srgb, var(--text-muted) 12%, transparent);
  color: var(--text-muted);
  border-radius: 999px;
  padding: 0.1rem 0.5rem;
  font-size: 0.62rem;
  letter-spacing: 0.03em;
  text-transform: none;
  font-weight: 500;
}

.cfg-group-body {
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  border-radius: 10px;
  padding: 1.1rem;
  display: flex;
  flex-direction: column;
  gap: 1rem;
}

/* ── Field ────────────────────────────────────────────── */
.cfg-field {
  display: flex;
  flex-direction: column;
  gap: 0.45rem;
}

.cfg-label {
  font-size: 0.72rem;
  font-weight: 600;
  letter-spacing: 0.04em;
  text-transform: uppercase;
  color: var(--text-muted);
}

:deep(.cfg-dropdown),
:deep(.cfg-dropdown.p-dropdown) {
  width: 100%;
}

:deep(.cfg-input) {
  width: 100%;
}

.cfg-input-with-hint {
  display: flex;
  flex-direction: column;
  gap: 0.4rem;
}

:deep(.cfg-input-number),
:deep(.cfg-input-number .p-inputnumber),
:deep(.cfg-input-number .p-inputtext) {
  width: 100%;
}

.cfg-input-hint {
  font-size: 0.71rem;
  color: var(--text-muted);
}

/* ── Two-column row ───────────────────────────────────── */
.cfg-row-2 {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 1rem;
}

/* ── Detail grid (regional preview) ──────────────────── */
.cfg-detail-grid {
  background: color-mix(in srgb, var(--text-color-85) 3%, var(--card-bg));
  border: 1px solid var(--card-border);
  border-radius: 8px;
  padding: 0.8rem 1rem;
  display: flex;
  flex-direction: column;
  gap: 0;
}

.cfg-detail-row {
  display: grid;
  grid-template-columns: 8rem 1fr;
  gap: 1rem;
  padding: 0.5rem 0;
  border-bottom: 1px solid color-mix(in srgb, var(--card-border) 60%, transparent);
}

.cfg-detail-row:first-child { padding-top: 0; }
.cfg-detail-row:last-child { padding-bottom: 0; border-bottom: none; }

.cfg-detail-key {
  font-size: 0.68rem;
  font-weight: 600;
  letter-spacing: 0.04em;
  text-transform: uppercase;
  color: var(--text-muted);
  padding-top: 1px;
}

.cfg-detail-val {
  font-size: 0.8rem;
  font-weight: 500;
  color: var(--text-color-85);
  line-height: 1.4;
}

/* ── Assinantes ───────────────────────────────────────── */
.cfg-assinante {
  display: flex;
  align-items: flex-start;
  gap: 0.85rem;
}

.cfg-assinante + .cfg-assinante {
  padding-top: 0.9rem;
  border-top: 1px solid var(--card-border);
}

.cfg-assinante-index {
  width: 24px;
  height: 24px;
  border-radius: 50%;
  background: color-mix(in srgb, var(--primary-color) 12%, transparent);
  color: var(--primary-color);
  font-size: 0.72rem;
  font-weight: 600;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  margin-top: 1.5rem;
}

.cfg-assinante-fields {
  flex: 1;
  min-width: 0;
}

/* ── Rule card ────────────────────────────────────────── */
.cfg-rule-card {
  display: flex;
  align-items: flex-start;
  gap: 0.65rem;
  background: color-mix(in srgb, var(--primary-color) 5%, transparent);
  border: 1px solid color-mix(in srgb, var(--primary-color) 18%, transparent);
  border-radius: 8px;
  padding: 0.75rem 0.9rem;
}

.cfg-rule-icon {
  color: var(--primary-color);
  font-size: 0.85rem;
  padding-top: 1px;
  flex-shrink: 0;
}

.cfg-rule-text {
  font-size: 0.78rem;
  color: var(--text-muted);
  line-height: 1.55;
}

.cfg-rule-text strong {
  color: var(--text-color-85);
  font-weight: 600;
}

/* ── Dropdown option ──────────────────────────────────── */
.cfg-dropdown-option {
  display: flex;
  flex-direction: column;
  gap: 0.1rem;
}

.cfg-dropdown-option small {
  font-size: 0.72rem;
  color: var(--text-muted);
}

.cfg-placeholder {
  color: var(--text-muted);
}

/* ── Actions ──────────────────────────────────────────── */
.cfg-actions {
  display: flex;
  justify-content: flex-end;
  padding-top: 0.5rem;
}

.cfg-btn-save {
  display: inline-flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.55rem 1.25rem;
  background: var(--primary-color);
  color: var(--color-on-primary);
  border: none;
  border-radius: 8px;
  font-size: 0.82rem;
  font-weight: 500;
  cursor: pointer;
  transition: opacity 0.15s;
}

.cfg-btn-save:hover:not(:disabled) {
  opacity: 0.88;
}

.cfg-btn-save:disabled {
  opacity: 0.45;
  cursor: not-allowed;
}
</style>
