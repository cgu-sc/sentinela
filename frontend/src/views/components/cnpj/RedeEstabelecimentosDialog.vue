<script setup>
import { computed, ref, watch } from 'vue';
import { useRouter } from 'vue-router';
import axios from 'axios';
import { API_ENDPOINTS } from '@/config/api';
import EstablishmentRiskTable from '@/views/components/establishments/EstablishmentRiskTable.vue';
import Dialog from 'primevue/dialog';

const props = defineProps({
  visible: { type: Boolean, default: false },
  cnpjRaiz: { type: String, required: true },
  cnpjOrigem: { type: String, default: null },
});

const emit = defineEmits(['update:visible']);

const router = useRouter();
const isLoading = ref(false);
const data = ref({ items: [], total: 0, kpis: null });

const headerLabel = computed(() => {
  if (!data.value.total) return `Estabelecimentos da rede ${props.cnpjRaiz}`;
  const qty = data.value.total;
  const noun = qty === 1 ? 'estabelecimento' : 'estabelecimentos';
  return `Estabelecimentos da rede ${props.cnpjRaiz} — ${qty} ${noun}`;
});

async function fetchData() {
  if (!props.cnpjRaiz) {
    data.value = { items: [], total: 0, kpis: null };
    return;
  }
  isLoading.value = true;
  try {
    const { data: resp } = await axios.get(
      API_ENDPOINTS.analyticsIndicadoresAnaliseCnpjs,
      {
        params: {
          indicador: 'percentual_nao_comprovacao',
          cnpj_raiz: props.cnpjRaiz,
          page: 1,
          page_size: 200,
        },
      },
    );
    data.value = {
      items: resp.items ?? [],
      total: resp.total ?? (resp.items?.length ?? 0),
      kpis: resp.kpis ?? null,
    };
  } catch (err) {
    console.error('[RedeEstabelecimentosDialog] Falha ao buscar estabelecimentos da rede:', err);
    data.value = { items: [], total: 0, kpis: null };
  } finally {
    isLoading.value = false;
  }
}

watch(
  () => props.visible,
  (open) => {
    if (open) fetchData();
  },
);

function onRowClick({ data: row }) {
  if (!row?.cnpj) return;
  emit('update:visible', false);
  router.push(`/estabelecimentos/${row.cnpj}`);
}
</script>

<template>
  <Dialog
    :visible="visible"
    @update:visible="emit('update:visible', $event)"
    modal
    :draggable="false"
    :dismissable-mask="true"
    :style="{ width: '70vw', height: '70vh' }"
    :breakpoints="{ '960px': '70vw', '960px': '70vh' }"
    class="rede-dialog"
    pt-options="{ mergeSections: false, mergeProps: false }"
  >
    <template #header>
      <div class="rede-dialog__header">
        <i class="pi pi-sitemap" />
        <span class="rede-dialog__title">{{ headerLabel }}</span>
      </div>
    </template>

    <div v-if="isLoading" class="rede-dialog__state">
      <i class="pi pi-spin pi-spinner" />
      <span>Carregando estabelecimentos da rede...</span>
    </div>

    <div v-else-if="!data.items.length" class="rede-dialog__state">
      <i class="pi pi-info-circle" />
      <span>Nenhum estabelecimento encontrado para esta rede.</span>
    </div>

    <div v-else class="rede-dialog__table-wrapper">
      <EstablishmentRiskTable
        :cnpjs="data.items"
        :formato="'pct'"
        :indicador-key="'percentual_nao_comprovacao'"
        :indicador-label="'Percentual Não Comprovação'"
        :is-loading="isLoading"
        :total-records="data.total"
        :first="0"
        :rows="data.items.length"
        :sort-field="'val_sem_comp'"
        :sort-order="-1"
        :table-kpis="data.kpis"
        :selected-regiao-nome="null"
        :selected-municipio-nome="null"
        compact
        @row-click="onRowClick"
      />
    </div>
  </Dialog>
</template>

<style scoped>
.rede-dialog__header {
  display: flex;
  align-items: center;
  gap: 0.75rem;
}

.rede-dialog__header i {
  font-size: 1.2rem;
  color: var(--primary-color);
}

.rede-dialog__title {
  font-size: 1rem;
  font-weight: 600;
  color: var(--text-color);
}

.rede-dialog__state {
  display: flex;
  align-items: center;
  justify-content: center;
  min-height: 220px;
  color: var(--text-muted);
  gap: 0.6rem;
  font-size: 0.95rem;
}

.rede-dialog__state i {
  font-size: 1.05rem;
}

/* Wrapper da tabela: o EstablishmentRiskTable eh um componente separado
   (com seu proprio data-v-), entao :deep() no .p-datatable-wrapper nao
   funciona via CSS scoped. Aplicamos as restricoes no wrapper pai, que
   esta dentro do nosso template e portanto compartilha nosso data-v-.

   min-height: 0 eh o truque-chave: faz o wrapper (e tudo dentro dele,
   incluindo a DataTable) respeitar a altura fixa do modal (70vh) em vez
   de crescer ate o conteudo. Combinado com flex: 1, o wrapper ocupa
   todo o espaco restante do Dialog apos o header. O p-dialog-content
   do PrimeVue tem overflow-y: auto nativo, entao se a tabela for
   maior que o wrapper, o scroll aparece no dialog. */
.rede-dialog__table-wrapper {
  flex: 1 1 auto;
  min-height: 0;
  display: flex;
  flex-direction: column;
}
</style>
