<script setup>
import { computed } from "vue";
import {
  formatCnaeEvidence,
  formatCpfCnpj,
  formatSocietyDate,
} from "@/utils/network/networkFormatters";

const props = defineProps({
  node: {
    type: Object,
    required: true,
  },
  typeLabels: {
    type: Object,
    required: true,
  },
  copiedKey: {
    type: [String, Number, null],
    default: null,
  },
  canExpand: {
    type: Boolean,
    default: false,
  },
  isExpanding: {
    type: Boolean,
    default: false,
  },
  isExpanded: {
    type: Boolean,
    default: false,
  },
  expansionLabel: {
    type: String,
    default: "",
  },
});

const emit = defineEmits(["close", "copy", "expand"]);

const nodeTitle = computed(
  () =>
    props.node.nome_socio ||
    props.node.nome_fantasia ||
    props.node.razao_social ||
    props.node.fullLabel,
);

const documentLabel = computed(() =>
  String(props.node.id || "").replace(/\D/g, "").length === 11 ? "CPF" : "CNPJ",
);
</script>

<template>
  <transition name="slide-in">
    <div v-if="node" class="node-detail-panel">
      <div class="panel-header">
        <div
          class="panel-type-badge"
          :style="{ background: typeLabels[node.type]?.color }"
        >
          {{ typeLabels[node.type]?.label || node.type }}
        </div>
        <button class="close-btn" @click="emit('close')">
          <i class="pi pi-times" />
        </button>
      </div>

      <div class="panel-names">
        <h3 class="panel-main-name">{{ nodeTitle }}</h3>
        <div v-if="node.nome_fantasia && node.razao_social" class="panel-sub-name">
          {{ node.razao_social }}
        </div>
      </div>

      <div class="panel-id">
        <span class="panel-id-label">{{ documentLabel }}</span>
        <span class="panel-id-value">{{ formatCpfCnpj(node.id) }}</span>
        <i
          :class="[
            'pi',
            copiedKey === node.id ? 'pi-check' : 'pi-copy',
            'copy-btn',
            copiedKey === node.id ? 'text-success' : '',
          ]"
          v-tooltip.top="'Copiar'"
          @click="emit('copy', node.id, node.id)"
        />
      </div>

      <div class="panel-fields">
        <div
          v-if="node.type === 'PF' && node.is_falecido"
          class="panel-field deceased-field"
        >
          <i class="pi pi-times-circle" />
          <span>Falecido</span>
          <span class="deceased-badge">Óbito</span>
        </div>

        <div
          v-if="node.type === 'PF' && node.is_cadunico"
          class="panel-field cadunico-field"
        >
          <i class="pi pi-id-card" />
          <span>CadÚnico</span>
          <span class="cadunico-badge">Inscrito</span>
        </div>

        <div
          v-if="node.type !== 'PF' && node.is_cnae_farmacia_ausente"
          class="panel-field cnae-alert-field"
        >
          <i class="pi pi-exclamation-triangle" />
          <span>CNAE farmácia</span>
          <span class="cnae-alert-badge">Ausente</span>
        </div>

        <div
          v-if="node.type !== 'PF' && node.is_cnae_farmacia_ausente"
          class="cnae-evidence"
        >
          <div class="cnae-evidence-row">
            <span>Principal</span>
            <strong>
              {{ formatCnaeEvidence(node.id_cnae_principal, node.cnae_principal) }}
            </strong>
          </div>
          <div class="cnae-evidence-row">
            <span>Secundário</span>
            <strong>
              {{ formatCnaeEvidence(node.id_cnae_secundario, node.cnae_secundario) }}
            </strong>
          </div>
        </div>

        <div v-if="node.municipio" class="panel-field mt-1">
          <i class="pi pi-map-marker" />
          <span>{{ node.municipio }} / {{ node.uf }}</span>
        </div>

        <div v-if="node.situacao_rf" class="panel-field">
          <i class="pi pi-info-circle" />
          <span>Situação RF: {{ node.situacao_rf }}</span>
        </div>
      </div>

      <div v-if="node.societyLinks?.length" class="panel-relationships">
        <div class="panel-section-title">Vínculos societários</div>
        <div
          v-for="link in node.societyLinks"
          :key="link.id"
          class="relationship-card"
        >
          <div class="relationship-header">
            <span class="relationship-name">{{ link.otherName }}</span>
            <span class="relationship-status" :class="{ inactive: !link.is_ativo }">
              {{ link.is_ativo ? "Ativo" : "Inativo" }}
            </span>
          </div>

          <div class="relationship-meta">
            <span>{{ formatCpfCnpj(link.otherId) }}</span>
            <span v-if="link.label">{{ link.label }}</span>
          </div>

          <div class="relationship-dates">
            <div>
              <span class="field-label">Entrada</span>
              <span class="field-value">
                {{ formatSocietyDate(link.data_entrada_sociedade) }}
              </span>
            </div>
            <div>
              <span class="field-label">Saída</span>
              <span class="field-value">
                {{ formatSocietyDate(link.data_exclusao_sociedade) }}
              </span>
            </div>
          </div>
        </div>
      </div>

      <div v-if="canExpand" class="panel-actions mt-3">
        <button
          class="expand-btn"
          :disabled="isExpanding || isExpanded"
          @click="emit('expand', node.id)"
        >
          <i :class="isExpanding ? 'pi pi-spin pi-spinner' : 'pi pi-plus-circle'" />
          <span>{{ expansionLabel }}</span>
        </button>
      </div>

      <div class="panel-hint">
        <i class="pi pi-mouse" /> Clique no fundo para fechar
      </div>
    </div>
  </transition>
</template>

<style scoped>
.node-detail-panel {
  position: absolute;
  top: 1rem;
  right: 1rem;
  z-index: 1000;
  width: 280px;
  background: color-mix(in srgb, var(--card-bg) 92%, transparent);
  backdrop-filter: blur(10px);
  -webkit-backdrop-filter: blur(10px);
  border: 1px solid var(--tabs-border);
  border-radius: 12px;
  padding: 1.25rem;
  display: flex;
  flex-direction: column;
  gap: 0.8rem;
  max-height: calc(100% - 2rem);
  overflow-y: auto;
  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.25);
  pointer-events: auto;
}

.panel-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.panel-type-badge {
  font-size: 0.62rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: #fff;
  padding: 0.2rem 0.6rem;
  border-radius: 99px;
}

.close-btn {
  background: transparent;
  border: none;
  color: var(--text-muted);
  cursor: pointer;
  font-size: 0.75rem;
  padding: 0.2rem;
  border-radius: 4px;
  transition: color 0.2s;
}

.close-btn:hover {
  color: var(--text-color);
}

.panel-names {
  display: flex;
  flex-direction: column;
  gap: 0.2rem;
}

.panel-main-name {
  margin: 0;
  font-size: 1rem;
  font-weight: 600;
  color: var(--text-color);
  line-height: 1.2;
}

.panel-sub-name {
  font-size: 0.75rem;
  font-weight: 500;
  color: var(--text-muted);
  line-height: 1.3;
  opacity: 0.8;
}

.panel-id {
  font-size: 0.75rem;
  color: var(--text-muted);
  background: var(--bg-secondary);
  border-radius: 6px;
  padding: 0.3rem 0.5rem;
  display: flex;
  align-items: center;
  gap: 0.4rem;
}

.panel-id-label {
  font-size: 0.65rem;
  font-weight: 600;
  color: var(--text-muted);
  opacity: 0.7;
  flex-shrink: 0;
}

.panel-id-value {
  flex: none;
}

.copy-btn {
  font-size: 0.85rem;
  cursor: pointer;
  color: var(--text-muted);
  opacity: 0.4;
  transition: all 0.2s;
  width: 1.4rem;
  display: inline-flex;
  justify-content: center;
  flex-shrink: 0;
}

.copy-btn.text-success {
  color: #10b981 !important;
  opacity: 1 !important;
}

.copy-btn:hover {
  opacity: 1 !important;
  color: var(--primary-color);
  transform: scale(1.1);
}

.copy-btn:active {
  transform: scale(0.9);
}

.panel-fields,
.panel-relationships {
  display: flex;
  flex-direction: column;
}

.panel-fields {
  gap: 0.5rem;
}

.panel-relationships {
  gap: 0.45rem;
}

.panel-section-title {
  font-size: 0.6rem;
  text-transform: uppercase;
  font-weight: 600;
  color: var(--text-muted);
  letter-spacing: 0.03em;
}

.relationship-card {
  display: flex;
  flex-direction: column;
  gap: 0.35rem;
  padding: 0.55rem;
  background: var(--bg-secondary);
  border: 1px solid color-mix(in srgb, var(--tabs-border) 72%, transparent);
  border-radius: 6px;
}

.relationship-header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 0.5rem;
}

.relationship-name {
  min-width: 0;
  color: var(--text-color);
  font-size: 0.74rem;
  font-weight: 650;
  line-height: 1.25;
  overflow-wrap: anywhere;
}

.relationship-status {
  flex-shrink: 0;
  padding: 0.12rem 0.42rem;
  border-radius: 999px;
  background: rgba(16, 185, 129, 0.14);
  color: #34d399;
  font-size: 0.58rem;
  font-weight: 700;
}

.relationship-status.inactive {
  background: rgba(239, 68, 68, 0.14);
  color: #fca5a5;
}

.relationship-meta {
  display: flex;
  flex-wrap: wrap;
  gap: 0.35rem;
  color: var(--text-muted);
  font-size: 0.65rem;
  font-weight: 500;
}

.relationship-dates {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 0.45rem;
}

.relationship-dates > div {
  display: flex;
  flex-direction: column;
  gap: 0.08rem;
}

.panel-field {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  font-size: 0.78rem;
  color: var(--text-secondary);
}

.panel-field i {
  color: var(--primary-color);
  font-size: 0.75rem;
  flex-shrink: 0;
}

.cadunico-field {
  color: color-mix(in srgb, #f59e0b 75%, var(--text-color));
}

.cadunico-field i {
  color: #f59e0b;
}

.cadunico-badge,
.cnae-alert-badge,
.deceased-badge {
  margin-left: auto;
  padding: 0.1rem 0.42rem;
  border-radius: 999px;
  font-size: 0.62rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.02em;
}

.cadunico-badge {
  border: 1px solid color-mix(in srgb, #f59e0b 42%, transparent);
  background: color-mix(in srgb, #f59e0b 16%, transparent);
  color: color-mix(in srgb, #f59e0b 82%, var(--text-color));
}

.cnae-alert-field {
  color: color-mix(in srgb, #ef4444 76%, var(--text-color));
}

.cnae-alert-field i {
  color: #ef4444;
}

.cnae-alert-badge {
  border: 1px solid color-mix(in srgb, #ef4444 44%, transparent);
  background: color-mix(in srgb, #ef4444 14%, transparent);
  color: color-mix(in srgb, #ef4444 84%, var(--text-color));
}

.cnae-evidence {
  display: grid;
  gap: 0.35rem;
  margin-top: -0.1rem;
  padding: 0.55rem 0.6rem;
  border: 1px solid color-mix(in srgb, #ef4444 22%, transparent);
  border-radius: 8px;
  background: color-mix(in srgb, #ef4444 7%, transparent);
}

.cnae-evidence-row {
  display: grid;
  gap: 0.12rem;
}

.cnae-evidence-row span {
  color: var(--text-muted);
  font-size: 0.58rem;
  font-weight: 800;
  letter-spacing: 0.04em;
  text-transform: uppercase;
}

.cnae-evidence-row strong {
  color: var(--text-secondary);
  font-size: 0.7rem;
  font-weight: 650;
  line-height: 1.25;
}

.deceased-field {
  color: color-mix(in srgb, #94a3b8 78%, var(--text-color));
}

.deceased-field i {
  color: #94a3b8;
}

.deceased-badge {
  border: 1px solid color-mix(in srgb, #94a3b8 44%, transparent);
  background: color-mix(in srgb, #94a3b8 15%, transparent);
  color: color-mix(in srgb, #94a3b8 86%, var(--text-color));
}

.field-label {
  font-size: 0.6rem;
  text-transform: uppercase;
  font-weight: 500;
  color: var(--text-muted);
  letter-spacing: 0.02em;
}

.field-value {
  font-size: 0.75rem;
  font-weight: 600;
  color: var(--text-color);
  line-height: 1.2;
}

.mt-1 {
  margin-top: 0.25rem;
}

.mt-3 {
  margin-top: 0.75rem;
}

.panel-hint {
  font-size: 0.65rem;
  color: var(--text-muted);
  opacity: 0.6;
  display: flex;
  align-items: center;
  gap: 0.3rem;
  margin-top: auto;
}

.expand-btn {
  width: 100%;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 0.6rem;
  padding: 0.75rem;
  background: var(--primary-color);
  color: white;
  border: none;
  border-radius: 8px;
  font-size: 0.75rem;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.2s;
  box-shadow: 0 4px 12px
    color-mix(in srgb, var(--primary-color) 30%, transparent);
}

.expand-btn:hover:not(:disabled) {
  background: color-mix(in srgb, var(--primary-color) 85%, black);
  transform: translateY(-1px);
}

.expand-btn:disabled {
  opacity: 0.6;
  cursor: not-allowed;
  background: var(--text-muted);
  box-shadow: none;
}

.slide-in-enter-active,
.slide-in-leave-active {
  transition:
    opacity 0.25s,
    transform 0.25s;
}

.slide-in-enter-from,
.slide-in-leave-to {
  opacity: 0;
  transform: translateX(20px);
}
</style>
