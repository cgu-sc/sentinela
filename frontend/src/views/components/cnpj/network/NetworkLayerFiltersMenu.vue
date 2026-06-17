<script setup>
defineProps({
  filters: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(["update-filter"]);

const updateFilter = (key, event) => {
  emit("update-filter", key, event.target.checked);
};
</script>

<template>
  <div class="filters-menu" @click.stop>
    <div class="filters-section">
      <div class="filters-section-title">Tipos de Empresa</div>
      <label class="filter-option" :class="{ muted: !filters.fp }">
        <input
          :checked="filters.fp"
          type="checkbox"
          @change="updateFilter('fp', $event)"
        />
        <span>Farmácia Popular</span>
      </label>
      <label class="filter-option" :class="{ muted: !filters.outrasFarmacias }">
        <input
          :checked="filters.outrasFarmacias"
          type="checkbox"
          @change="updateFilter('outrasFarmacias', $event)"
        />
        <span>Outras Farmácias</span>
      </label>
      <label class="filter-option" :class="{ muted: !filters.outrosSegmentos }">
        <input
          :checked="filters.outrosSegmentos"
          type="checkbox"
          @change="updateFilter('outrosSegmentos', $event)"
        />
        <span>Outros Segmentos</span>
      </label>
    </div>

    <div class="filters-section">
      <div class="filters-section-title">Pessoas e Vínculos</div>
      <label class="filter-option" :class="{ muted: !filters.sociosAtuais }">
        <input
          :checked="filters.sociosAtuais"
          type="checkbox"
          @change="updateFilter('sociosAtuais', $event)"
        />
        <span>Sócios Atuais</span>
      </label>
      <label class="filter-option" :class="{ muted: !filters.sociosInativos }">
        <input
          :checked="filters.sociosInativos"
          type="checkbox"
          @change="updateFilter('sociosInativos', $event)"
        />
        <span>Vínculos Inativos</span>
      </label>
      <label class="filter-option" :class="{ muted: !filters.exSociosAlvo }">
        <input
          :checked="filters.exSociosAlvo"
          type="checkbox"
          @change="updateFilter('exSociosAlvo', $event)"
        />
        <span>Ex-sócios da Empresa</span>
      </label>
      <label class="filter-option" :class="{ muted: !filters.representantes }">
        <input
          :checked="filters.representantes"
          type="checkbox"
          @change="updateFilter('representantes', $event)"
        />
        <span>Representantes Legais</span>
      </label>
    </div>

    <div class="filters-section">
      <div class="filters-section-title">Status Cadastral</div>
      <label class="filter-option" :class="{ muted: !filters.empresasInativas }">
        <input
          :checked="filters.empresasInativas"
          type="checkbox"
          @change="updateFilter('empresasInativas', $event)"
        />
        <span>Empresas Inativas</span>
      </label>
    </div>
  </div>
</template>

<style scoped>
.filters-menu {
  position: absolute;
  top: calc(100% + 0.55rem);
  left: 0;
  z-index: 40;
  width: 244px;
  padding: 0.45rem;
  background: var(--card-bg);
  border: 1px solid var(--tabs-border);
  border-radius: 10px;
  box-shadow:
    0 18px 42px rgba(0, 0, 0, 0.38),
    0 0 0 1px color-mix(in srgb, var(--tabs-border) 34%, transparent);
}

.filters-section {
  padding: 0.45rem 0.35rem;
}

.filters-section + .filters-section {
  border-top: 1px solid color-mix(in srgb, var(--tabs-border) 76%, transparent);
}

.filters-section-title {
  margin-bottom: 0.35rem;
  color: var(--text-muted);
  font-size: 0.58rem;
  font-weight: 700;
  letter-spacing: 0.04em;
  line-height: 1;
  text-transform: uppercase;
}

.filter-option {
  min-height: 1.75rem;
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.25rem 0.3rem;
  border-radius: 6px;
  color: var(--text-secondary);
  cursor: pointer;
  font-size: 0.72rem;
  font-weight: 500;
  transition:
    background 0.18s,
    color 0.18s,
    opacity 0.18s;
}

.filter-option:hover {
  background: color-mix(in srgb, var(--primary-color) 10%, transparent);
  color: var(--text-color-85);
}

.filter-option.muted {
  color: var(--text-muted);
  opacity: 0.74;
}

.filter-option input {
  width: 0.95rem;
  height: 0.95rem;
  accent-color: var(--primary-color);
  cursor: pointer;
  flex-shrink: 0;
}
</style>
