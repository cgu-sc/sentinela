<script setup>
import { ref, onMounted, onUnmounted, watch } from 'vue';
import { useRouter } from 'vue-router';
import { useFilterStore } from '@/stores/filters';
import Dialog from 'primevue/dialog';

const router = useRouter();
const filterStore = useFilterStore();

const showCnpjDialog = ref(false);
const cnpjCompletoDetectado = ref('');

const formatCnpjMask = (v) => {
  const d = v.replace(/\D/g, '');
  return d.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/, '$1.$2.$3/$4-$5');
};

watch(() => filterStore.selectedCnpjRaiz, (val) => {
  const digits = val.replace(/\D/g, '');
  if (digits.length === 14) {
    cnpjCompletoDetectado.value = digits;
    showCnpjDialog.value = true;
  }
});

const onCnpjDialogKeydown = (e) => {
  if (showCnpjDialog.value && e.key === 'Enter') {
    e.preventDefault();
    abrirDetalhamento();
  }
};

onMounted(() => window.addEventListener('keydown', onCnpjDialogKeydown));
onUnmounted(() => window.removeEventListener('keydown', onCnpjDialogKeydown));

const abrirDetalhamento = () => {
  showCnpjDialog.value = false;
  filterStore.selectedCnpjRaiz = '';
  router.push(`/estabelecimento/${cnpjCompletoDetectado.value}`);
};

const usarComoFiltro = () => {
  showCnpjDialog.value = false;
};
</script>

<template>
  <Dialog
    v-model:visible="showCnpjDialog"
    header="Abrir detalhamento?"
    :style="{ width: '340px' }"
    modal
  >
    <p style="font-size: 0.9rem; margin: 0;">
      Deseja abrir o detalhamento do CNPJ <strong>{{ formatCnpjMask(cnpjCompletoDetectado) }}</strong>?
    </p>
    <template #footer>
      <button class="cnpj-dialog-btn cnpj-dialog-btn--cancel" @click="usarComoFiltro">Não</button>
      <button class="cnpj-dialog-btn cnpj-dialog-btn--confirm" @click="abrirDetalhamento">
        <i class="pi pi-arrow-right" /> Abrir Detalhamento
      </button>
    </template>
  </Dialog>
</template>

<style scoped>
.cnpj-dialog-btn {
  display: inline-flex;
  align-items: center;
  gap: 0.4rem;
  padding: 0.45rem 1.1rem;
  font-size: 0.82rem;
  font-weight: 600;
  border-radius: 8px;
  border: 1px solid;
  cursor: pointer;
  transition: all 0.2s ease;
  backdrop-filter: blur(8px);
  -webkit-backdrop-filter: blur(8px);
}

.cnpj-dialog-btn--cancel {
  color: var(--text-muted);
  border-color: rgba(148, 163, 184, 0.25);
  background: var(--card-bg);
}
.cnpj-dialog-btn--cancel:hover {
  background: color-mix(in srgb, var(--card-bg) 85%, var(--text-muted));
  border-color: rgba(148, 163, 184, 0.4);
}

.cnpj-dialog-btn--confirm {
  color: var(--primary-color);
  border-color: color-mix(in srgb, var(--primary-color) 35%, transparent);
  background: color-mix(in srgb, var(--primary-color) 10%, var(--card-bg));
}
.cnpj-dialog-btn--confirm:hover {
  background: color-mix(in srgb, var(--primary-color) 20%, var(--card-bg));
  border-color: color-mix(in srgb, var(--primary-color) 60%, transparent);
  box-shadow: 0 0 12px color-mix(in srgb, var(--primary-color) 25%, transparent);
}
</style>
