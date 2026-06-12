<script setup>
import { computed } from "vue";
import Dialog from "primevue/dialog";

const props = defineProps({
  visible: { type: Boolean, default: false },
  data: { type: Object, default: null },
});

const emit = defineEmits(["update:visible", "navigate"]);

const dialogVisible = computed({
  get: () => props.visible,
  set: (value) => emit("update:visible", value),
});

const alerts = computed(() => props.data?.alertas ?? []);
const severityLabel = (severity) => severity === "critico" ? "Crítico" : "Atenção";

const scopeLabel = (scope) => {
  if (scope === "cnpj") return "Estabelecimento";
  if (scope === "representante") return "Representante";
  return "Sócio";
};

const formatDocument = (value) => {
  const clean = String(value ?? "").replace(/\D/g, "");
  if (clean.length === 11) {
    return clean.replace(/^(\d{3})(\d{3})(\d{3})(\d{2})$/, "$1.$2.$3-$4");
  }
  if (clean.length === 14) {
    return clean.replace(
      /^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/,
      "$1.$2.$3/$4-$5",
    );
  }
  return value;
};

const navigate = (alert) => {
  dialogVisible.value = false;
  emit("navigate", alert.aba_destino);
};
</script>

<template>
  <Dialog
    v-model:visible="dialogVisible"
    modal
    header="Alertas de integridade"
    :style="{ width: '720px' }"
    class="integrity-alerts-dialog"
  >
    <div class="integrity-summary">
      <div class="integrity-summary-item">
        <span>Total</span>
        <strong>{{ data?.total ?? 0 }}</strong>
      </div>
      <div class="integrity-summary-item integrity-summary-item--critical">
        <span>Críticos</span>
        <strong>{{ data?.total_criticos ?? 0 }}</strong>
      </div>
      <div class="integrity-summary-item integrity-summary-item--attention">
        <span>Atenção</span>
        <strong>{{ data?.total_atencao ?? 0 }}</strong>
      </div>
    </div>

    <div class="integrity-list">
      <article
        v-for="alert in alerts"
        :key="`${alert.tipo}-${alert.entidade_id}`"
        class="integrity-alert-row"
        :class="`integrity-alert-row--${alert.severidade}`"
      >
        <div class="integrity-alert-icon">
          <i
            :class="alert.severidade === 'critico'
              ? 'pi pi-exclamation-triangle'
              : 'pi pi-info-circle'"
          />
        </div>

        <div class="integrity-alert-content">
          <div class="integrity-alert-heading">
            <span class="integrity-alert-title">{{ alert.titulo }}</span>
            <span
              class="integrity-severity"
              :class="`integrity-severity--${alert.severidade}`"
            >
              {{ severityLabel(alert.severidade) }}
            </span>
          </div>
          <span class="integrity-alert-entity">
            {{ scopeLabel(alert.escopo) }}: {{ alert.entidade_nome }}
          </span>
          <span class="integrity-alert-meta">
            {{ formatDocument(alert.entidade_id) }} · Fonte: {{ alert.fonte }}
          </span>
        </div>

        <button
          class="integrity-alert-action"
          type="button"
          @click="navigate(alert)"
        >
          <span>Ver {{ alert.aba_destino }}</span>
          <i class="pi pi-arrow-right" />
        </button>
      </article>
    </div>
  </Dialog>
</template>

<style scoped>
.integrity-summary {
  display: flex;
  gap: 0.75rem;
  padding-bottom: 1rem;
  border-bottom: 1px solid var(--card-border);
}

.integrity-summary-item {
  display: flex;
  align-items: baseline;
  gap: 0.45rem;
  min-width: 110px;
  color: var(--text-muted);
}

.integrity-summary-item span {
  font-size: 0.72rem;
  text-transform: uppercase;
  letter-spacing: 0.04em;
}

.integrity-summary-item strong {
  font-size: 1rem;
  font-weight: 600;
  color: var(--text-color);
  font-variant-numeric: tabular-nums;
}

.integrity-summary-item--critical strong {
  color: var(--risk-critical);
}

.integrity-summary-item--attention strong {
  color: var(--risk-medium);
}

.integrity-list {
  display: flex;
  flex-direction: column;
}

.integrity-alert-row {
  display: grid;
  grid-template-columns: 30px minmax(0, 1fr) auto;
  align-items: center;
  gap: 0.75rem;
  padding: 0.9rem 0;
  border-bottom: 1px solid var(--card-border);
}

.integrity-alert-row:last-child {
  border-bottom: 0;
}

.integrity-alert-icon {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 28px;
  height: 28px;
  border-radius: 6px;
}

.integrity-alert-row--critico .integrity-alert-icon {
  color: var(--risk-critical);
  background: color-mix(in srgb, var(--risk-critical) 12%, transparent);
}

.integrity-alert-row--atencao .integrity-alert-icon {
  color: var(--risk-medium);
  background: color-mix(in srgb, var(--risk-medium) 12%, transparent);
}

.integrity-alert-content {
  display: flex;
  min-width: 0;
  flex-direction: column;
  gap: 0.2rem;
}

.integrity-alert-heading {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.integrity-alert-title,
.integrity-alert-entity {
  font-size: 0.82rem;
  font-weight: 600;
  color: var(--text-color);
}

.integrity-alert-meta {
  font-size: 0.72rem;
  color: var(--text-muted);
}

.integrity-severity {
  min-width: 62px;
  padding: 0.14rem 0.35rem;
  border: 1px solid transparent;
  border-radius: 4px;
  font-size: 0.62rem;
  font-weight: 600;
  text-align: center;
  text-transform: uppercase;
}

.integrity-severity--critico {
  color: var(--risk-critical);
  border-color: color-mix(in srgb, var(--risk-critical) 35%, transparent);
  background: color-mix(in srgb, var(--risk-critical) 10%, transparent);
}

.integrity-severity--atencao {
  color: var(--risk-medium);
  border-color: color-mix(in srgb, var(--risk-medium) 35%, transparent);
  background: color-mix(in srgb, var(--risk-medium) 10%, transparent);
}

.integrity-alert-action {
  display: inline-flex;
  align-items: center;
  gap: 0.4rem;
  border: 0;
  background: transparent;
  color: var(--primary-color);
  font-size: 0.75rem;
  font-weight: 600;
  cursor: pointer;
}

.integrity-alert-action:hover {
  text-decoration: underline;
}
</style>
