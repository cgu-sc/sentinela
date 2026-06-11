<script setup>
defineProps({
  mapData: { type: Array, default: () => [] },
  title: { type: String, default: 'Mapa do alvo' },
  subtitle: { type: String, default: 'Municípios por valor incompatível ou casos observados' },
  sourceNotice: { type: String, default: null },
});
</script>

<template>
  <section class="target-map-card">
    <div class="section-header">
      <div class="section-icon-box">
        <i class="pi pi-map" />
      </div>
      <div class="section-title-block">
        <h2>{{ title }}</h2>
        <span>{{ subtitle }}</span>
      </div>
    </div>

    <div v-if="sourceNotice || !mapData.length" class="target-map-empty">
      <i class="pi pi-map-marker" />
      <span>{{ sourceNotice ? 'O mapa será preenchido quando o endpoint do alvo estiver conectado.' : 'Nenhum município encontrado para o alvo no recorte atual.' }}</span>
    </div>

    <div v-else class="target-map-preview">
      <div
        v-for="row in mapData.slice(0, 8)"
        :key="row.id_ibge7"
        class="target-map-preview-row"
      >
        <div>
          <strong>{{ row.municipio }}</strong>
          <span>{{ row.uf }}</span>
        </div>
        <em>{{ Number(row.valor_incompativel || 0).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' }) }}</em>
      </div>
    </div>
  </section>
</template>

<style scoped>
.target-map-card {
  overflow: hidden;
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  border-radius: 8px;
  box-shadow: var(--shadow-sm);
}

.section-header {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  padding: 0.85rem 1rem;
  border-bottom: 1px solid var(--card-border);
}

.section-icon-box {
  width: 2rem;
  height: 2rem;
  border-radius: 8px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  background: color-mix(in srgb, var(--primary-color) 12%, transparent);
  color: var(--primary-color);
  flex-shrink: 0;
}

.section-title-block {
  min-width: 0;
}

.section-title-block h2 {
  margin: 0;
  color: var(--text-color-85);
  font-size: 0.82rem;
  font-weight: 600;
  letter-spacing: 0.05em;
  text-transform: uppercase;
}

.section-title-block span {
  display: block;
  margin-top: 0.15rem;
  color: var(--text-muted);
  font-size: 0.7rem;
}

.target-map-empty {
  min-height: 20rem;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 0.65rem;
  color: var(--text-muted);
  background:
    linear-gradient(color-mix(in srgb, var(--card-border) 36%, transparent) 1px, transparent 1px),
    linear-gradient(90deg, color-mix(in srgb, var(--card-border) 36%, transparent) 1px, transparent 1px);
  background-size: 28px 28px;
}

.target-map-empty i {
  color: var(--primary-color);
  font-size: 1.35rem;
  opacity: 0.75;
}

.target-map-empty span {
  font-size: 0.78rem;
}

.target-map-preview {
  min-height: 20rem;
  padding: 1rem;
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: 0.75rem;
  align-content: start;
}

.target-map-preview-row {
  min-height: 4.4rem;
  padding: 0.75rem;
  border: 1px solid var(--card-border);
  border-radius: 8px;
  background: color-mix(in srgb, var(--primary-color) 5%, var(--card-bg));
  display: flex;
  flex-direction: column;
  justify-content: space-between;
  gap: 0.45rem;
}

.target-map-preview-row strong {
  display: block;
  color: var(--text-color-85);
  font-size: 0.78rem;
  font-weight: 600;
  line-height: 1.25;
}

.target-map-preview-row span {
  display: block;
  margin-top: 0.15rem;
  color: var(--text-muted);
  font-size: 0.66rem;
  font-weight: 600;
  letter-spacing: 0.05em;
  text-transform: uppercase;
}

.target-map-preview-row em {
  color: var(--primary-color);
  font-size: 0.82rem;
  font-style: normal;
  font-weight: 600;
}
</style>
