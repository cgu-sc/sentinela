<script setup>
import { computed } from "vue";
import { useRouter } from "vue-router";
import { useFarmaciaListsStore } from "@/stores/farmaciaLists";
import { useFormatting } from "@/composables/useFormatting";

const router = useRouter();
const farmaciaLists = useFarmaciaListsStore();
const { formatarData } = useFormatting();

const formatCnpj = (v) => {
  if (!v) return "—";
  const clean = v.replace(/\D/g, "");
  if (clean.length !== 14) return v;
  return clean.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/, "$1.$2.$3/$4-$5");
};

const formatDate = (iso) => {
  if (!iso) return "—";
  return new Date(iso).toLocaleDateString("pt-BR", {
    day: "2-digit", month: "2-digit", year: "numeric",
  });
};

const totalBadge = computed(() => farmaciaLists.interesse.length);

function remover(cnpj) {
  farmaciaLists.toggleInteresse(cnpj, "");
}

function abrirEstabelecimento(cnpj) {
  router.push(`/estabelecimentos/${cnpj}`);
}
</script>

<template>
  <div class="lists-view">
    <div class="lists-header">
      <div class="lists-title">
        <i class="pi pi-bookmark" />
        <h2>Farmácias Monitoradas</h2>
        <span class="total-badge" v-if="totalBadge > 0">{{ totalBadge }}</span>
      </div>
      <p class="lists-subtitle">
        CNPJs adicionados à Lista de Interesse para acompanhamento manual.
      </p>
    </div>

    <div class="lists-content">
      <div v-if="farmaciaLists.interesse.length === 0" class="empty-state">
        <i class="pi pi-star empty-icon" />
        <p>Nenhuma farmácia na Lista de Interesse.</p>
        <span>Acesse o detalhe de um estabelecimento e clique no ícone de estrela.</span>
      </div>

      <table v-else class="lists-table">
        <thead>
          <tr>
            <th>#</th>
            <th>CNPJ</th>
            <th>Razão Social</th>
            <th>Adicionado em</th>
            <th class="col-actions">Ações</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="(item, i) in farmaciaLists.interesse" :key="item.cnpj">
            <td class="col-num">{{ i + 1 }}</td>
            <td class="col-cnpj font-mono">{{ formatCnpj(item.cnpj) }}</td>
            <td class="col-razao">{{ item.razaoSocial || "—" }}</td>
            <td class="col-date">{{ formatDate(item.adicionadoEm) }}</td>
            <td class="col-actions">
              <div class="action-btns">
                <button
                  class="action-btn open"
                  @click="abrirEstabelecimento(item.cnpj)"
                  v-tooltip.top="'Abrir detalhamento'"
                >
                  <i class="pi pi-arrow-up-right" />
                </button>
                <button
                  class="action-btn remove"
                  @click="remover(item.cnpj)"
                  v-tooltip.top="'Remover da lista'"
                >
                  <i class="pi pi-trash" />
                </button>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

<style scoped>
.lists-view {
  padding: 2rem;
  display: flex;
  flex-direction: column;
  gap: 1.5rem;
  max-width: 960px;
}

.lists-header {
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
  border-bottom: 1px solid var(--tabs-border);
  padding-bottom: 1.5rem;
}

.lists-title {
  display: flex;
  align-items: center;
  gap: 0.75rem;
}

.lists-title i {
  font-size: 1.2rem;
  color: var(--primary-color);
}

.lists-title h2 {
  font-size: 1.2rem;
  font-weight: 700;
  margin: 0;
  color: var(--text-color);
}

.total-badge {
  font-size: 0.72rem;
  font-weight: 700;
  padding: 0.1rem 0.5rem;
  border-radius: 20px;
  background: color-mix(in srgb, var(--primary-color) 15%, transparent);
  color: var(--primary-color);
  border: 1px solid color-mix(in srgb, var(--primary-color) 25%, transparent);
}

.lists-subtitle {
  font-size: 0.8rem;
  color: var(--text-color);
  opacity: 0.5;
  margin: 0;
}

.empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 6rem 2rem;
  gap: 0.75rem;
  color: var(--text-color);
  opacity: 0.4;
  background: var(--surface-bg);
  border: 1px dashed var(--border-color);
  border-radius: 12px;
}

.empty-icon {
  font-size: 2.5rem;
}

.empty-state p {
  font-size: 0.95rem;
  font-weight: 600;
  margin: 0;
}

.empty-state span {
  font-size: 0.8rem;
}

.lists-table {
  width: 100%;
  border-collapse: collapse;
  background: var(--surface-bg);
  border: 1px solid var(--border-color);
  border-radius: 12px;
  overflow: hidden;
}

.lists-table th {
  padding: 0.75rem 1rem;
  font-size: 0.7rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--text-color);
  opacity: 0.5;
  background: var(--tabs-bg);
  border-bottom: 1px solid var(--tabs-border);
  text-align: left;
}

.lists-table td {
  padding: 0.75rem 1rem;
  font-size: 0.82rem;
  color: var(--text-color);
  border-bottom: 1px solid var(--tabs-border);
}

.lists-table tbody tr:last-child td {
  border-bottom: none;
}

.lists-table tbody tr:hover {
  background: color-mix(in srgb, var(--text-color) 3%, var(--tabs-bg));
}

.col-num {
  width: 40px;
  opacity: 0.4;
  font-weight: 600;
}

.col-cnpj {
  font-family: ui-monospace, monospace;
  font-size: 0.78rem;
  white-space: nowrap;
}

.col-razao {
  font-weight: 600;
}

.col-date {
  opacity: 0.6;
  font-size: 0.78rem;
  white-space: nowrap;
}

.col-actions {
  width: 90px;
  text-align: center;
}

.action-btns {
  display: flex;
  gap: 0.4rem;
  justify-content: center;
}

.action-btn {
  width: 30px;
  height: 30px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border-radius: 6px;
  border: 1px solid var(--tabs-border);
  background: none;
  cursor: pointer;
  transition: all 0.15s ease;
  font-size: 0.75rem;
  color: var(--text-color);
  opacity: 0.6;
}

.action-btn:hover {
  opacity: 1;
}

.action-btn.open:hover {
  border-color: var(--primary-color);
  color: var(--primary-color);
  background: color-mix(in srgb, var(--primary-color) 8%, transparent);
}

.action-btn.remove:hover {
  border-color: var(--risk-critical);
  color: var(--risk-critical);
  background: color-mix(in srgb, var(--risk-critical) 8%, transparent);
}
</style>
