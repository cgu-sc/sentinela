<script setup>
defineProps({
  modelValue: {
    type: String,
    default: "",
  },
  matchCount: {
    type: Number,
    default: 0,
  },
  hasActiveSearch: {
    type: Boolean,
    default: false,
  },
  searchHasNoMatch: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(["update:modelValue", "clear"]);
</script>

<template>
  <div
    class="toolbar-pill search-pill"
    :class="{
      searching: hasActiveSearch,
      'no-match': searchHasNoMatch,
    }"
  >
    <i class="pi pi-search search-icon" />
    <input
      :value="modelValue"
      class="node-search-input"
      type="text"
      placeholder="Localizar nó"
      aria-label="Localizar nó por CNPJ, CPF ou nome"
      @input="emit('update:modelValue', $event.target.value)"
      @keydown.esc="emit('clear')"
    />
    <span v-if="hasActiveSearch" class="search-count">{{ matchCount }}</span>
    <button
      v-if="hasActiveSearch"
      class="search-clear-btn"
      type="button"
      @click="emit('clear')"
      v-tooltip.bottom="'Limpar busca'"
    >
      <i class="pi pi-times" />
    </button>
  </div>
</template>

<style scoped>
.search-pill {
  gap: 6px;
  min-width: 210px;
  max-width: 280px;
  padding: 4px 8px;
  transition:
    border-color 0.18s,
    box-shadow 0.18s;
}

.search-pill.searching {
  border-color: rgba(56, 189, 248, 0.35);
  box-shadow:
    0 8px 24px -4px rgba(0, 0, 0, 0.45),
    0 0 0 1px rgba(56, 189, 248, 0.1);
}

.search-pill.no-match {
  border-color: rgba(251, 191, 36, 0.45);
}

.search-icon {
  color: #64748b;
  font-size: 0.75rem;
  flex-shrink: 0;
}

.node-search-input {
  width: 100%;
  min-width: 0;
  height: 24px;
  background: transparent;
  border: none;
  outline: none;
  color: #e2e8f0;
  font-size: 0.72rem;
  font-weight: 500;
}

.node-search-input::placeholder {
  color: #64748b;
  opacity: 1;
}

.search-count {
  min-width: 1rem;
  height: 1rem;
  padding: 0 0.28rem;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border-radius: 999px;
  background: rgba(56, 189, 248, 0.14);
  color: #7dd3fc;
  font-size: 0.6rem;
  font-weight: 700;
  line-height: 1;
}

.search-pill.no-match .search-count {
  background: rgba(251, 191, 36, 0.14);
  color: #fbbf24;
}

.search-clear-btn {
  width: 1.35rem;
  height: 1.35rem;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border: none;
  border-radius: 999px;
  background: rgba(255, 255, 255, 0.06);
  color: #94a3b8;
  cursor: pointer;
  font-size: 0.58rem;
  flex-shrink: 0;
  transition:
    background 0.18s,
    color 0.18s;
}

.search-clear-btn:hover {
  background: rgba(255, 255, 255, 0.12);
  color: #e2e8f0;
}
</style>
