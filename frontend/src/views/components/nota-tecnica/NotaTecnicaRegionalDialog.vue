<script setup>
import { computed, ref, watch } from "vue";
import Dialog from "primevue/dialog";
import Dropdown from "primevue/dropdown";
import InputText from "primevue/inputtext";
import Button from "primevue/button";
import { useToast } from "primevue/usetoast";
import { useNotaTecnicaConfigStore } from "@/stores/notaTecnicaConfig";

const props = defineProps({
  visible: { type: Boolean, default: false },
  continueLabel: { type: String, default: "Salvar" },
});

const emit = defineEmits(["update:visible", "saved"]);

const toast = useToast();
const notaTecnicaConfig = useNotaTecnicaConfigStore();
const selectedCodigo = ref(null);
const numeroNota = ref("");
const numeroProcesso = ref("");
const numeroProcessoDigitsRaw = ref("");
const anoNota = new Date().getFullYear();

const regionalOptions = computed(() =>
  notaTecnicaConfig.regionais.map((regional) => ({
    ...regional,
    label: `${regional.codigo} - ${regional.estado}`,
  })),
);

const selectedRegionalPreview = computed(() =>
  notaTecnicaConfig.regionais.find((regional) => regional.codigo === selectedCodigo.value) ?? null,
);

const numeroNotaPreview = computed(() => numeroNota.value || "XXX");
const processoDigits = computed(() => numeroProcessoDigitsRaw.value);
const processoFormatado = computed(() => formatProcessoDigits(processoDigits.value.slice(0, 17)));
const processoPreview = computed(() => processoFormatado.value || `00XXX.XXXXXX/${anoNota}-XX`);
const processoInvalido = computed(
  () => processoDigits.value.length > 0 && processoDigits.value.length !== 17,
);
const notaPreview = computed(() => {
  const codigo = selectedRegionalPreview.value?.codigo || "XX";
  return `NOTA TÉCNICA Nº ${numeroNotaPreview.value}/${anoNota}/NAE/${codigo}/Regional/${codigo}`;
});

function formatProcessoDigits(value) {
  const digits = String(value || "").replace(/\D/g, "");
  if (!digits) return "";

  let formatted = digits.slice(0, 5);
  if (digits.length > 5) formatted += `.${digits.slice(5, 11)}`;
  if (digits.length > 11) formatted += `/${digits.slice(11, 15)}`;
  if (digits.length > 15) formatted += `-${digits.slice(15, 17)}`;
  return formatted;
}

function onNumeroNotaInput(event) {
  numeroNota.value = String(event.target.value || "").replace(/\D/g, "").slice(0, 8);
}

function onNumeroProcessoInput(event) {
  const digits = String(event.target.value || "").replace(/\D/g, "");
  numeroProcessoDigitsRaw.value = digits;
  numeroProcesso.value = formatProcessoDigits(digits.slice(0, 17));
}

watch(
  () => props.visible,
  async (visible) => {
    if (!visible) return;
    try {
      await notaTecnicaConfig.ensureLoaded();
      selectedCodigo.value = notaTecnicaConfig.selectedRegionalCodigo;
      numeroNota.value = notaTecnicaConfig.ultimoNumeroNota || "";
      numeroProcesso.value = notaTecnicaConfig.ultimoNumeroProcesso || "";
      numeroProcessoDigitsRaw.value = String(numeroProcesso.value || "").replace(/\D/g, "");
    } catch (error) {
      toast.add({
        severity: "error",
        summary: "Erro ao carregar regionais",
        detail: error?.message || "Não foi possível carregar as regionais da Nota Técnica.",
        life: 7000,
      });
    }
  },
  { immediate: true },
);

function close() {
  emit("update:visible", false);
}

async function save() {
  try {
    if (processoInvalido.value) {
      throw new Error("O número do processo deve conter 17 dígitos ou ficar em branco.");
    }

    const regional = await notaTecnicaConfig.saveNotaTecnicaConfig({
      regionalCodigo: selectedCodigo.value,
      numeroNota: numeroNota.value,
      numeroProcesso: processoFormatado.value,
    });
    emit("saved", {
      regional,
      numeroNota: numeroNota.value || null,
      numeroProcesso: processoFormatado.value || null,
    });
    close();
  } catch (error) {
    toast.add({
      severity: "warn",
      summary: "Dados da Nota Técnica",
      detail: error?.message || "Informe os dados obrigatórios da Nota Técnica.",
      life: 6000,
    });
  }
}
</script>

<template>
  <Dialog
    :visible="visible"
    modal
    :draggable="false"
    class="nt-regional-dialog"
    header="Dados da Nota Técnica"
    @update:visible="emit('update:visible', $event)"
  >
    <div class="nt-regional-content">
      <p class="nt-regional-copy">
        Informe os dados de emissão. Campos numéricos em branco permanecem como marcadores editáveis no documento.
      </p>

      <div class="nt-regional-field">
        <label>Regional emissora</label>
        <Dropdown
          v-model="selectedCodigo"
          :options="regionalOptions"
          option-label="label"
          option-value="codigo"
          filter
          class="w-full"
          placeholder="Selecione a regional"
          :loading="notaTecnicaConfig.loading"
        />
      </div>

      <div v-if="selectedRegionalPreview" class="nt-regional-preview">
        <strong>{{ selectedRegionalPreview.nome_unidade }}</strong>
        <span>{{ selectedRegionalPreview.linha_endereco }}</span>
        <span>{{ selectedRegionalPreview.superintendente }}</span>
      </div>

      <div class="nt-regional-grid">
        <div class="nt-regional-field">
          <label>Número da Nota Técnica</label>
          <InputText
            :model-value="numeroNota"
            placeholder="XXX"
            inputmode="numeric"
            @input="onNumeroNotaInput"
          />
        </div>

        <div class="nt-regional-field">
          <label>Número do processo</label>
          <InputText
            :model-value="numeroProcesso"
            placeholder="00XXX.XXXXXX/2026-XX"
            inputmode="numeric"
            :invalid="processoInvalido"
            @input="onNumeroProcessoInput"
          />
          <small v-if="processoInvalido" class="nt-field-error">
            Informe 17 dígitos ou deixe em branco.
          </small>
        </div>
      </div>

      <div class="nt-document-preview">
        <span>{{ notaPreview }}</span>
        <span>(PROCESSO Nº {{ processoPreview }})</span>
      </div>
    </div>

    <template #footer>
      <Button
        label="Cancelar"
        icon="pi pi-times"
        class="nt-dialog-action nt-dialog-action-secondary"
        @click="close"
      />
      <Button
        :label="continueLabel"
        icon="pi pi-check"
        class="nt-dialog-action nt-dialog-action-primary"
        :loading="notaTecnicaConfig.saving"
        @click="save"
      />
    </template>
  </Dialog>
</template>

<style scoped>
.nt-regional-content {
  width: 520px;
  max-width: 100%;
  display: flex;
  flex-direction: column;
  gap: 1rem;
}

.nt-regional-copy {
  margin: 0;
  color: var(--text-muted);
  font-size: 0.9rem;
  line-height: 1.5;
}

.nt-regional-field label {
  display: block;
  margin-bottom: 0.4rem;
  font-size: 0.78rem;
  color: var(--text-muted);
}

.nt-field-error {
  display: block;
  margin-top: 0.35rem;
  color: var(--risk-indicator-critical);
  font-size: 0.74rem;
}

.nt-regional-grid {
  display: grid;
  grid-template-columns: 0.8fr 1.2fr;
  gap: 0.85rem;
}

.nt-regional-preview {
  display: flex;
  flex-direction: column;
  gap: 0.35rem;
  padding: 0.9rem;
  border: 1px solid var(--card-border);
  border-radius: 10px;
  background: color-mix(in srgb, var(--primary-color) 5%, var(--card-bg));
  color: var(--text-color);
  font-size: 0.82rem;
  line-height: 1.45;
}

.nt-regional-preview strong {
  font-weight: 600;
}

.nt-document-preview {
  display: flex;
  flex-direction: column;
  gap: 0.3rem;
  padding: 0.85rem 0.9rem;
  border: 1px dashed var(--card-border);
  border-radius: 8px;
  color: var(--text-color);
  font-size: 0.86rem;
  line-height: 1.45;
}

:global(.nt-regional-dialog .p-dialog-header-close) {
  width: 2rem !important;
  height: 2rem !important;
  border: 1px solid color-mix(in srgb, var(--text-muted) 16%, transparent) !important;
  border-radius: 8px !important;
  background: color-mix(in srgb, var(--card-bg) 56%, transparent) !important;
  color: var(--text-muted) !important;
  box-shadow: inset 0 1px 0 color-mix(in srgb, #ffffff 8%, transparent);
  transition:
    background 0.2s ease,
    border-color 0.2s ease,
    color 0.2s ease,
    box-shadow 0.2s ease,
    transform 0.2s ease !important;
  backdrop-filter: blur(10px);
  -webkit-backdrop-filter: blur(10px);
}

:global(.nt-regional-dialog .p-dialog-header-close:hover) {
  border-color: color-mix(in srgb, var(--primary-color) 42%, transparent) !important;
  background: color-mix(in srgb, var(--primary-color) 10%, var(--card-bg)) !important;
  color: var(--primary-color) !important;
  box-shadow:
    inset 0 1px 0 color-mix(in srgb, #ffffff 10%, transparent),
    0 10px 22px color-mix(in srgb, var(--primary-color) 12%, transparent);
  transform: translateY(-1px);
}

:global(.nt-regional-dialog .p-dialog-header-close:focus),
:global(.nt-regional-dialog .p-dialog-header-close:active) {
  outline: none !important;
  box-shadow: none !important;
}

:global(.nt-regional-dialog .p-dialog-header-close:focus-visible) {
  box-shadow: 0 0 0 2px color-mix(in srgb, var(--primary-color) 34%, transparent) !important;
}

:global(.nt-regional-dialog .nt-dialog-action.p-button) {
  position: relative;
  overflow: hidden;
  border: 1px solid color-mix(in srgb, var(--primary-color) 30%, var(--card-border)) !important;
  border-radius: 8px !important;
  background: color-mix(in srgb, var(--card-bg) 62%, transparent) !important;
  color: var(--text-color) !important;
  box-shadow:
    inset 0 1px 0 color-mix(in srgb, #ffffff 10%, transparent),
    0 12px 28px color-mix(in srgb, #000000 22%, transparent);
  transition:
    background 0.2s ease,
    border-color 0.2s ease,
    color 0.2s ease,
    box-shadow 0.2s ease,
    transform 0.2s ease !important;
  backdrop-filter: blur(12px);
  -webkit-backdrop-filter: blur(12px);
}

:global(.nt-regional-dialog .nt-dialog-action.p-button:hover) {
  border-color: color-mix(in srgb, var(--primary-color) 56%, transparent) !important;
  background: color-mix(in srgb, var(--primary-color) 12%, var(--card-bg)) !important;
  color: var(--primary-color) !important;
  box-shadow:
    inset 0 1px 0 color-mix(in srgb, #ffffff 12%, transparent),
    0 14px 30px color-mix(in srgb, var(--primary-color) 16%, transparent);
  transform: translateY(-1px);
}

:global(.nt-regional-dialog .nt-dialog-action.p-button:focus),
:global(.nt-regional-dialog .nt-dialog-action.p-button:active) {
  outline: none !important;
  background: color-mix(in srgb, var(--card-bg) 62%, transparent) !important;
  border-color: color-mix(in srgb, var(--primary-color) 44%, transparent) !important;
  color: var(--primary-color) !important;
}

:global(.nt-regional-dialog .nt-dialog-action.p-button:focus-visible) {
  box-shadow:
    0 0 0 2px color-mix(in srgb, var(--primary-color) 38%, transparent),
    0 14px 30px color-mix(in srgb, var(--primary-color) 14%, transparent) !important;
}

:global(.nt-regional-dialog .nt-dialog-action-primary.p-button) {
  border-color: color-mix(in srgb, var(--primary-color) 58%, transparent) !important;
  background: color-mix(in srgb, var(--primary-color) 14%, transparent) !important;
  color: var(--primary-color) !important;
  box-shadow:
    inset 0 1px 0 color-mix(in srgb, #ffffff 12%, transparent),
    0 14px 34px color-mix(in srgb, var(--primary-color) 15%, transparent);
}

:global(.nt-regional-dialog .nt-dialog-action-primary.p-button::after) {
  content: "";
  position: absolute;
  inset: 0;
  pointer-events: none;
  background: linear-gradient(
    110deg,
    transparent 0%,
    color-mix(in srgb, var(--primary-color) 16%, transparent) 45%,
    transparent 70%
  );
  opacity: 0;
  transform: translateX(-100%);
  transition:
    opacity 0.2s ease,
    transform 0.45s ease;
}

:global(.nt-regional-dialog .nt-dialog-action-primary.p-button:hover::after) {
  opacity: 1;
  transform: translateX(100%);
}

:global(.nt-regional-dialog .nt-dialog-action-secondary.p-button) {
  border-color: color-mix(in srgb, var(--text-muted) 22%, var(--card-border)) !important;
  color: var(--text-muted) !important;
}

:global(.nt-regional-dialog .nt-dialog-action-secondary.p-button:hover) {
  border-color: color-mix(in srgb, var(--text-muted) 36%, var(--card-border)) !important;
  background: color-mix(in srgb, var(--text-muted) 8%, transparent) !important;
  color: var(--text-color) !important;
}
</style>
