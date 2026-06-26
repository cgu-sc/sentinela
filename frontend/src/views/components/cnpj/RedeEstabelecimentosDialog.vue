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

const PAGE_SIZE = 50;

const items = ref([]);
const total = ref(0);
const kpis = ref(null);
const first = ref(0);
const isLoading = ref(false);
const sortField = ref('val_sem_comp');
const sortOrder = ref(-1);

const headerLabel = computed(() => {
  if (!total.value) return `Estabelecimentos da rede ${props.cnpjRaiz}`;
  const qty = total.value;
  const noun = qty === 1 ? 'estabelecimento' : 'estabelecimentos';
  return `Estabelecimentos da rede ${props.cnpjRaiz} — ${qty} ${noun}`;
});

async function fetchPage(page) {
  if (!props.cnpjRaiz) return;
  isLoading.value = true;
  try {
    const { data: resp } = await axios.get(
      API_ENDPOINTS.analyticsIndicadoresAnaliseCnpjs,
      {
        params: {
          indicador: 'percentual_nao_comprovacao',
          cnpj_raiz: props.cnpjRaiz,
          page,
          page_size: PAGE_SIZE,
          sort_field: sortField.value,
          sort_order: sortOrder.value === 1 ? 'asc' : 'desc',
        },
      },
    );
    items.value = resp.items ?? [];
    total.value = resp.total ?? items.value.length;
    kpis.value = resp.kpis ?? null;
    first.value = (page - 1) * PAGE_SIZE;
  } catch (err) {
    console.error(
      '[RedeEstabelecimentosDialog] Falha ao buscar estabelecimentos da rede:',
      err,
    );
    items.value = [];
    total.value = 0;
    kpis.value = null;
  } finally {
    isLoading.value = false;
  }
}

function onLazyLoad(event) {
  if (!event) return;
  const rows = event.rows ?? PAGE_SIZE;
  const firstRow = event.first ?? 0;

  // Atualiza sort se o evento trouxer sortField nao-vazio
  if (event.sortField) {
    sortField.value = event.sortField;
    sortOrder.value = event.sortOrder ?? -1;
  }

  // Sort mudou: reset para pagina 1 (dados reordenados, indices mudaram).
  // Paginator mudou: calcula pagina a partir do `first` recebido.
  const sortChanged = Boolean(event.sortField);
  const newPage = sortChanged ? 1 : Math.floor(firstRow / rows) + 1;
  fetchPage(newPage, rows);
}

watch(
  () => props.visible,
  (open) => {
    if (open) {
      items.value = [];
      total.value = 0;
      kpis.value = null;
      first.value = 0;
      fetchPage(1);
    }
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
    :pt-options="{ mergeSections: false, mergeProps: false }"
  >
    <template #header>
      <div class="rede-dialog__header">
        <i class="pi pi-sitemap" />
        <span class="rede-dialog__title">{{ headerLabel }}</span>
      </div>
    </template>

    <div v-if="!items.length" class="rede-dialog__state">
      <i class="pi pi-info-circle" />
      <span>Nenhum estabelecimento encontrado para esta rede.</span>
    </div>

    <div v-else class="rede-dialog__table-wrapper">
      <EstablishmentRiskTable
        :cnpjs="items"
        :formato="'pct'"
        :indicador-key="'percentual_nao_comprovacao'"
        :indicador-label="'Percentual Não Comprovação'"
        :is-loading="isLoading"
        :total-records="total"
        :first="first"
        :rows="50"
        :sort-field="sortField"
        :sort-order="sortOrder"
        :table-kpis="kpis"
        :selected-regiao-nome="null"
        :selected-municipio-nome="null"
        compact
        @lazy-load="onLazyLoad"
        @row-click="onRowClick"
      />
    </div>

    <!-- Overlay de loading inicial. Copiado do padrao do
         IndicatorDetailPanel.vue:786 (mesma classe .indicator-loading-overlay
         e mesma estrutura). -->
    <transition name="ind-overlay-fade">
      <div
        v-if="isLoading && !items.length"
        class="indicator-loading-overlay"
        aria-live="polite"
        aria-busy="true"
      >
        <div class="indicator-loading-overlay__box">
          <i class="pi pi-spin pi-spinner" aria-hidden="true" />
          <span>Carregando os dados...</span>
        </div>
      </div>
    </transition>
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

/* Overlay de loading inicial. Padrao identico ao
   IndicatorDetailPanel.vue:786-823. */
.indicator-loading-overlay {
  position: absolute;
  inset: 0;
  z-index: 5;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 12px;
  background: color-mix(in srgb, var(--bg-color) 62%, transparent);
  backdrop-filter: blur(2px);
}

.indicator-loading-overlay__box {
  display: inline-flex;
  align-items: center;
  gap: 0.75rem;
  padding: 0.9rem 1.1rem;
  border: 1px solid var(--card-border);
  border-radius: 10px;
  background: var(--card-bg);
  color: var(--text-color-85);
  box-shadow: 0 12px 28px color-mix(in srgb, var(--text-color-85) 12%, transparent);
  font-size: 0.86rem;
  font-weight: 600;
}

.indicator-loading-overlay__box i {
  color: var(--primary-color);
  font-size: 1rem;
}

.ind-overlay-fade-enter-active,
.ind-overlay-fade-leave-active {
  transition: opacity 0.18s ease;
}

.ind-overlay-fade-enter-from,
.ind-overlay-fade-leave-to {
  opacity: 0;
}
</style>
