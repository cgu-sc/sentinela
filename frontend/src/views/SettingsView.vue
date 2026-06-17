<script setup>
import { onMounted } from 'vue';
import Dropdown from 'primevue/dropdown';
import { useToast } from 'primevue/usetoast';
import { useNotaTecnicaConfigStore } from '@/stores/notaTecnicaConfig';

const notaTecnicaConfig = useNotaTecnicaConfigStore();
const toast = useToast();

async function saveNotaTecnicaRegional(event) {
  try {
    await notaTecnicaConfig.saveRegionalCodigo(event.value);
  } catch (error) {
    toast.add({
      severity: 'warn',
      summary: 'Regional da Nota Técnica',
      detail: error?.message || 'Não foi possível salvar a regional emissora.',
      life: 6000,
    });
  }
}

onMounted(() => {
  notaTecnicaConfig.ensureLoaded().catch((error) => {
    toast.add({
      severity: 'warn',
      summary: 'Regional da Nota Técnica',
      detail: error?.message || 'Não foi possível carregar a configuração da Nota Técnica.',
      life: 6000,
    });
  });
});
</script>

<template>
  <div class="settings-container">
    <header class="settings-header">
      <div class="header-content">
        <div class="brand">
          <i class="pi pi-cog brand-icon" />
          <div class="brand-text">
            <h1>Configurações do Sistema</h1>
            <span>Parâmetros operacionais persistidos automaticamente</span>
          </div>
        </div>
        <div class="autosave-status">
          <i class="pi pi-sync pi-spin" v-if="notaTecnicaConfig.loading" />
          <i class="pi pi-cloud-upload" v-else />
          <span>Sincronizado</span>
        </div>
      </div>
    </header>

    <main class="settings-main">
      <section class="settings-card anim-fade-in">
        <div class="settings-card-header">
          <div>
            <div class="section-title">
              <i class="pi pi-file-edit" />
              <span>Nota Técnica</span>
            </div>
            <p class="section-desc">Configuração operacional usada no cabeçalho das Notas Técnicas geradas pelo Sentinela.</p>
          </div>
          <span class="regional-status">
            {{ notaTecnicaConfig.selectedRegionalLabel || "Regional não definida" }}
          </span>
        </div>

        <div class="settings-grid">
          <div class="control-item">
            <label>Regional emissora</label>
            <Dropdown
              v-model="notaTecnicaConfig.selectedRegionalCodigo"
              :options="notaTecnicaConfig.regionais"
              optionLabel="estado"
              optionValue="codigo"
              filter
              class="p-inputtext-sm w-full"
              placeholder="Selecione a regional"
              :loading="notaTecnicaConfig.loading"
              @change="saveNotaTecnicaRegional"
            >
              <template #option="{ option }">
                <div class="regional-option">
                  <span>{{ option.codigo }} - {{ option.estado }}</span>
                  <small>{{ option.nome_unidade }}</small>
                </div>
              </template>
              <template #value="{ value }">
                <span v-if="value">{{ notaTecnicaConfig.selectedRegionalLabel }}</span>
                <span v-else>Selecione a regional</span>
              </template>
            </Dropdown>
          </div>

          <div v-if="notaTecnicaConfig.selectedRegional" class="regional-preview">
            <span>{{ notaTecnicaConfig.selectedRegional.nome_unidade }}</span>
            <span>{{ notaTecnicaConfig.selectedRegional.linha_endereco }}</span>
            <span>{{ notaTecnicaConfig.selectedRegional.superintendente }}</span>
          </div>
        </div>
      </section>
    </main>
  </div>
</template>

<style scoped>
.settings-container {
  min-height: 100vh;
  background: var(--bg-color);
  color: var(--text-color-85);
  padding-bottom: 4rem;
}

.settings-header {
  background: var(--card-bg);
  border-bottom: 1px solid var(--card-border);
  padding: 0.75rem 2rem;
  position: sticky;
  top: 0;
  z-index: 1000;
}

.header-content {
  width: 100%;
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.brand {
  display: flex;
  align-items: center;
  gap: 1rem;
}

.brand-icon {
  font-size: 1.25rem;
  color: var(--primary-color);
  background: color-mix(in srgb, var(--primary-color) 10%, transparent);
  padding: 0.6rem;
  border-radius: 10px;
}

.brand-text h1 {
  margin: 0;
  font-size: 1.1rem;
  font-weight: 500;
}

.brand-text span {
  font-size: 0.75rem;
  color: var(--text-muted);
  font-weight: 400;
}

.autosave-status {
  display: flex;
  align-items: center;
  gap: 0.6rem;
  font-size: 0.7rem;
  color: var(--text-muted);
  background: var(--bg-color);
  padding: 0.4rem 0.8rem;
  border-radius: 20px;
  border: 1px solid var(--card-border);
}

.autosave-status i {
  color: var(--primary-color);
}

.settings-main {
  width: 100%;
  margin: 1.5rem 0;
  padding: 0 2rem;
}

.settings-card {
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  border-radius: 12px;
  padding: 1.2rem;
  box-shadow: var(--shadow-sm);
}

.settings-card-header {
  display: flex;
  justify-content: space-between;
  gap: 1rem;
  align-items: flex-start;
  margin-bottom: 1.2rem;
}

.section-title {
  display: flex;
  align-items: center;
  gap: 0.55rem;
  font-size: 1rem;
  font-weight: 600;
}

.section-title i {
  color: var(--primary-color);
}

.section-desc {
  margin: 0.35rem 0 0;
  color: var(--text-muted);
  font-size: 0.78rem;
}

.regional-status {
  border: 1px solid var(--card-border);
  background: var(--bg-color);
  border-radius: 999px;
  color: var(--text-muted);
  padding: 0.35rem 0.75rem;
  font-size: 0.72rem;
  white-space: nowrap;
}

.settings-grid {
  display: grid;
  grid-template-columns: minmax(320px, 420px) 1fr;
  gap: 1rem;
  align-items: stretch;
}

.control-item {
  display: flex;
  flex-direction: column;
  gap: 0.45rem;
}

.control-item label {
  font-size: 0.72rem;
  color: var(--text-muted);
  font-weight: 500;
}

.regional-option {
  display: flex;
  flex-direction: column;
  gap: 0.15rem;
}

.regional-option small {
  color: var(--text-muted);
}

.regional-preview {
  border: 1px solid color-mix(in srgb, var(--primary-color) 28%, var(--card-border));
  background: color-mix(in srgb, var(--primary-color) 8%, var(--card-bg));
  border-radius: 10px;
  padding: 0.85rem;
  display: flex;
  flex-direction: column;
  justify-content: center;
  gap: 0.35rem;
  color: var(--text-color-85);
  font-size: 0.82rem;
}

.regional-preview span:first-child {
  font-weight: 600;
}
</style>
