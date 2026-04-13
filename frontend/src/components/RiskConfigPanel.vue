<script setup>
import { ref, computed } from 'vue';
import { useConfigStore } from '@/stores/config';
import { INDICATOR_GROUPS } from '@/config/riskConfig';
import Button from 'primevue/button';
import OverlayPanel from 'primevue/overlaypanel';

const configStore = useConfigStore();
const panel = ref();

function togglePanel(event) {
  panel.value.toggle(event);
}

// Cria uma cópia editável local dos limiares para evitar mutar o store diretamente
const localThresholds = ref({});

function openPanel(event) {
  // Faz uma cópia profunda ao abrir
  localThresholds.value = JSON.parse(JSON.stringify(configStore.thresholds));
  panel.value.toggle(event);
}

function save() {
  configStore.applyLocalThresholds(localThresholds.value);
  panel.value.hide();
}

function reset() {
  configStore.resetToBackend();
  panel.value.hide();
}

// Todos os indicadores achatados com seus grupos
const allIndicators = computed(() =>
  INDICATOR_GROUPS.flatMap(g =>
    g.indicators.map(ind => ({
      key: ind.thresholdKey,
      label: ind.label,
      group: g.label,
    }))
  )
);
</script>

<template>
  <div class="risk-config-wrapper">
    <Button
      @click="openPanel"
      icon="pi pi-sliders-h"
      rounded
      text
      severity="secondary"
      v-tooltip.bottom="'Configurar Limiares de Risco'"
      class="risk-config-trigger"
    />

    <OverlayPanel ref="panel" class="risk-config-panel" :dismissable="true">
      <div class="rcp-content">
        <!-- Header -->
        <div class="rcp-header">
          <div class="rcp-header-icon">
            <i class="pi pi-sliders-h" />
          </div>
          <div>
            <h3 class="rcp-title">Limiares de Risco</h3>
            <p class="rcp-subtitle">Configure os múltiplos de risco por indicador</p>
          </div>
        </div>

        <!-- Tabela de Indicadores -->
        <div class="rcp-table-wrap">
          <table class="rcp-table">
            <thead>
              <tr>
                <th class="col-indicator">Indicador</th>
                <th class="col-value">⚠ Atenção</th>
                <th class="col-value">🔴 Crítico</th>
              </tr>
            </thead>
            <tbody>
              <template v-for="grupo in INDICATOR_GROUPS" :key="grupo.id">
                <tr class="rcp-group-row">
                  <td colspan="3">{{ grupo.label }}</td>
                </tr>
                <tr
                  v-for="ind in grupo.indicators"
                  :key="ind.thresholdKey"
                  class="rcp-data-row"
                >
                  <td class="col-indicator">{{ ind.label }}</td>
                  <td class="col-value">
                    <input
                      v-if="localThresholds[ind.thresholdKey]"
                      v-model.number="localThresholds[ind.thresholdKey].atencao"
                      type="number"
                      step="0.1"
                      min="0"
                      class="rcp-input warn"
                    />
                  </td>
                  <td class="col-value">
                    <input
                      v-if="localThresholds[ind.thresholdKey]"
                      v-model.number="localThresholds[ind.thresholdKey].critico"
                      type="number"
                      step="0.1"
                      min="0"
                      class="rcp-input danger"
                    />
                  </td>
                </tr>
              </template>
            </tbody>
          </table>
        </div>

        <!-- Actions -->
        <div class="rcp-actions">
          <button class="rcp-btn reset" @click="reset">
            <i class="pi pi-refresh" />
            Resetar para Padrão
          </button>
          <button class="rcp-btn save" @click="save">
            <i class="pi pi-check" />
            Salvar e Aplicar
          </button>
        </div>

        <!-- Footer -->
        <div class="rcp-footer">
          <i class="pi pi-info-circle" />
          <span>Os valores são em múltiplos da mediana regional (ex: 2.0x)</span>
        </div>
      </div>
    </OverlayPanel>
  </div>
</template>

<style scoped>
.risk-config-wrapper {
  display: inline-flex;
  align-items: center;
}

/* ── Panel ───────────────────────────────────── */
:deep(.risk-config-panel.p-overlaypanel) {
  background: var(--card-bg);
  border: 1px solid var(--sidebar-border);
  border-radius: 1rem;
  box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.4);
  padding: 0;
  width: 520px;
  max-width: calc(100vw - 2rem);
  max-height: 80vh;
  animation: panelSlideIn 0.2s ease;
}

:deep(.risk-config-panel .p-overlaypanel-content) {
  padding: 0;
}

:deep(.risk-config-panel::before),
:deep(.risk-config-panel::after) {
  border-bottom-color: var(--sidebar-border) !important;
}

@keyframes panelSlideIn {
  from { opacity: 0; transform: translateY(8px); }
  to   { opacity: 1; transform: translateY(0); }
}

/* ── Content ─────────────────────────────────── */
.rcp-content {
  display: flex;
  flex-direction: column;
  gap: 0;
}

/* ── Header ──────────────────────────────────── */
.rcp-header {
  display: flex;
  align-items: center;
  gap: 0.875rem;
  padding: 1.25rem 1.25rem 1rem;
  border-bottom: 1px solid var(--sidebar-border);
}

.rcp-header-icon {
  width: 2.5rem;
  height: 2.5rem;
  border-radius: 0.75rem;
  background: var(--primary-color);
  display: flex;
  align-items: center;
  justify-content: center;
  color: white;
  font-size: 1.05rem;
  flex-shrink: 0;
}

.rcp-title {
  font-size: 1rem;
  font-weight: 700;
  color: var(--text-color);
  margin: 0;
}

.rcp-subtitle {
  font-size: 0.75rem;
  color: var(--text-muted);
  margin: 0;
}

/* ── Table ───────────────────────────────────── */
.rcp-table-wrap {
  overflow-y: auto;
  max-height: calc(80vh - 200px);
}

.rcp-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 0.75rem;
}

.rcp-table thead th {
  position: sticky;
  top: 0;
  background: color-mix(in srgb, var(--card-bg) 95%, var(--primary-color));
  padding: 0.5rem 1rem;
  text-align: left;
  font-size: 0.68rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--text-muted);
  border-bottom: 1px solid var(--sidebar-border);
  z-index: 10;
}

.rcp-table th.col-value,
.rcp-table td.col-value {
  text-align: center;
  width: 100px;
}

.rcp-group-row td {
  padding: 0.45rem 1rem 0.3rem;
  font-size: 0.65rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  color: var(--primary-color);
  background: color-mix(in srgb, var(--primary-color) 5%, transparent);
  border-top: 1px solid color-mix(in srgb, var(--primary-color) 15%, transparent);
}

.rcp-data-row td {
  padding: 0.4rem 1rem;
  border-bottom: 1px solid color-mix(in srgb, var(--sidebar-border) 50%, transparent);
  color: var(--text-color);
}

.rcp-data-row:hover td {
  background: color-mix(in srgb, var(--primary-color) 4%, transparent);
}

td.col-indicator {
  font-size: 0.75rem;
}

/* ── Inputs ──────────────────────────────────── */
.rcp-input {
  width: 72px;
  padding: 0.28rem 0.45rem;
  border-radius: 6px;
  border: 1px solid var(--card-border);
  background: var(--card-bg);
  color: var(--text-color);
  font-size: 0.75rem;
  font-family: inherit;
  font-weight: 600;
  text-align: center;
  transition: border-color 0.15s, box-shadow 0.15s;
  -moz-appearance: textfield;
}

.rcp-input::-webkit-outer-spin-button,
.rcp-input::-webkit-inner-spin-button {
  -webkit-appearance: none;
  margin: 0;
}

.rcp-input:focus {
  outline: none;
}

.rcp-input.warn:focus {
  border-color: #f59e0b;
  box-shadow: 0 0 0 3px rgba(245, 158, 11, 0.15);
}

.rcp-input.danger:focus {
  border-color: #ef4444;
  box-shadow: 0 0 0 3px rgba(239, 68, 68, 0.15);
}

/* Color hints */
.rcp-input.warn {
  color: #d97706;
  border-color: color-mix(in srgb, #f59e0b 30%, var(--card-border));
}

.rcp-input.danger {
  color: #dc2626;
  border-color: color-mix(in srgb, #ef4444 30%, var(--card-border));
}

/* ── Actions ─────────────────────────────────── */
.rcp-actions {
  display: flex;
  gap: 0.5rem;
  padding: 0.875rem 1.25rem;
  border-top: 1px solid var(--sidebar-border);
  justify-content: flex-end;
}

.rcp-btn {
  display: inline-flex;
  align-items: center;
  gap: 0.4rem;
  padding: 0.45rem 0.9rem;
  border-radius: 7px;
  font-size: 0.75rem;
  font-weight: 600;
  font-family: inherit;
  cursor: pointer;
  border: 1px solid transparent;
  transition: all 0.18s ease;
}

.rcp-btn.reset {
  background: transparent;
  border-color: var(--card-border);
  color: var(--text-muted);
}

.rcp-btn.reset:hover {
  background: color-mix(in srgb, var(--text-muted) 8%, transparent);
  color: var(--text-color);
}

.rcp-btn.save {
  background: var(--primary-color);
  color: white;
  box-shadow: 0 2px 8px color-mix(in srgb, var(--primary-color) 40%, transparent);
}

.rcp-btn.save:hover {
  filter: brightness(1.1);
  transform: translateY(-1px);
  box-shadow: 0 4px 14px color-mix(in srgb, var(--primary-color) 45%, transparent);
}

.rcp-btn.save:active {
  transform: translateY(0);
}

/* ── Footer ──────────────────────────────────── */
.rcp-footer {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.6rem 1.25rem;
  background: color-mix(in srgb, var(--primary-color) 5%, transparent);
  border-radius: 0 0 1rem 1rem;
  font-size: 0.7rem;
  color: var(--text-muted);
  border-top: 1px solid var(--sidebar-border);
}

.rcp-footer i {
  color: var(--primary-color);
  font-size: 0.8rem;
  flex-shrink: 0;
}
</style>
