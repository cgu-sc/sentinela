<script setup>
import { computed, nextTick, ref, watch } from "vue";
import Dialog from "primevue/dialog";
import Textarea from "primevue/textarea";
import { useFarmaciaListsStore } from "@/stores/farmaciaLists";

const props = defineProps({
  visible: { type: Boolean, default: false },
  cnpj: { type: String, required: true },
  entityName: { type: String, default: "farmacia" },
});

const emit = defineEmits(["update:visible"]);
const farmaciaLists = useFarmaciaListsStore();
const tempObs = ref("");
const textareaRef = ref(null);

const dialogVisible = computed({
  get: () => props.visible,
  set: (value) => emit("update:visible", value),
});

watch(
  () => props.visible,
  async (visible) => {
    if (visible) tempObs.value = farmaciaLists.getObservacao(props.cnpj);
    if (visible) {
      await nextTick();
      textareaRef.value?.$el?.focus?.();
      textareaRef.value?.$el?.select?.();
    }
  },
);

const saveObs = () => {
  farmaciaLists.setObservacao(props.cnpj, tempObs.value);
  dialogVisible.value = false;
};
</script>

<template>
  <Dialog
    v-model:visible="dialogVisible"
    modal
    header="Observação da Farmácia"
    :style="{ width: '450px' }"
    class="obs-dialog-custom"
  >
    <div class="p-fluid">
      <div class="field mb-4">
        <label for="obs" class="block font-semibold mb-2" style="font-size: 0.9rem; color: var(--text-color)">
          Sua anotação para {{ entityName }}:
        </label>
        <Textarea
          id="obs"
          ref="textareaRef"
          v-model="tempObs"
          rows="5"
          autoResize
          placeholder="Digite aqui os motivos do interesse ou observações importantes..."
          class="custom-textarea"
        />
      </div>
    </div>
    <template #footer>
      <div class="dialog-footer-actions">
        <button class="footer-btn footer-btn--cancel" @click="dialogVisible = false">Cancelar</button>
        <button class="footer-btn footer-btn--save" @click="saveObs">Salvar Observação</button>
      </div>
    </template>
  </Dialog>
</template>

<style scoped>
.dialog-footer-actions {
  display: flex;
  justify-content: flex-end;
  gap: 0.75rem;
  padding-top: 1rem;
}

.footer-btn {
  padding: 0.5rem 1.25rem;
  border-radius: 8px;
  font-size: 0.85rem;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.2s ease;
  border: 1px solid transparent;
}

.footer-btn--cancel {
  background: transparent;
  color: var(--text-muted);
}

.footer-btn--cancel:hover {
  background: rgba(0,0,0,0.05);
}

.footer-btn--save {
  background: var(--primary-color);
  color: white;
}

.footer-btn--save:hover {
  background: color-mix(in srgb, var(--primary-color) 90%, black);
  transform: translateY(-1px);
  box-shadow: 0 4px 12px color-mix(in srgb, var(--primary-color) 20%, transparent);
}

.custom-textarea {
  background: var(--bg-secondary);
  border: 1px solid var(--establishment-header-border);
  border-radius: 8px;
  color: var(--text-color);
  padding: 0.75rem;
  font-family: inherit;
  font-size: 0.9rem;
}

.custom-textarea:focus {
  border-color: var(--primary-color);
  box-shadow: 0 0 0 2px color-mix(in srgb, var(--primary-color) 20%, transparent);
}
</style>
