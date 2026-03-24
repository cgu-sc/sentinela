<script setup>
import { ref, computed } from 'vue';
import { useThemeStore } from '../stores/theme';
import Button from 'primevue/button';
import OverlayPanel from 'primevue/overlaypanel';

const themeStore = useThemeStore();
const panel = ref();

const palettes = [
  {
    id: 'azul',
    name: 'Azul',
    gradient: 'linear-gradient(135deg, #3b82f6, #2563eb)',
  },
  {
    id: 'carbon',
    name: 'Carbon Gold',
    gradient: 'linear-gradient(135deg, #f59e0b, #d97706)',
  },
];

const isDarkMode = computed(() => themeStore.isDark);
const currentPalette = computed(() => themeStore.currentPalette);

function togglePanel(event) {
  panel.value.toggle(event);
}
</script>

<template>
  <div class="theme-selector-wrapper">
    <Button
      @click="togglePanel"
      icon="pi pi-palette"
      rounded
      text
      severity="secondary"
      v-tooltip.bottom="'Personalizar aparência'"
      class="theme-trigger"
    />

    <OverlayPanel ref="panel" class="theme-panel" :dismissable="true">
      <div class="theme-panel-content">
        <!-- Header -->
        <div class="panel-header">
          <div class="header-icon">
            <i class="pi pi-palette"></i>
          </div>
          <div>
            <h3 class="header-title">Aparência</h3>
            <p class="header-subtitle">Personalize sua experiência</p>
          </div>
        </div>

        <!-- Mode Toggle -->
        <div class="mode-section">
          <label class="section-label">Modo de Cor</label>
          <div class="mode-toggle">
            <button
              @click="themeStore.setMode('light')"
              :class="['mode-option', { active: !isDarkMode }]"
            >
              <i class="pi pi-sun"></i>
              <span>Claro</span>
            </button>
            <button
              @click="themeStore.setMode('dark')"
              :class="['mode-option', { active: isDarkMode }]"
            >
              <i class="pi pi-moon"></i>
              <span>Escuro</span>
            </button>
          </div>
        </div>

        <!-- Palette Grid -->
        <div class="theme-section">
          <label class="section-label">Paleta de Cores</label>
          <div class="theme-grid">
            <button
              v-for="palette in palettes"
              :key="palette.id"
              @click="themeStore.setPalette(palette.id)"
              :class="['theme-card', { active: currentPalette === palette.id }]"
            >
              <div class="theme-preview">
                <div
                  class="preview-gradient"
                  :style="{ background: palette.gradient }"
                >
                  <div class="preview-shine"></div>
                </div>
                <div v-if="currentPalette === palette.id" class="active-badge">
                  <i class="pi pi-check"></i>
                </div>
              </div>
              <div class="theme-info">
                <span class="theme-name">{{ palette.name }}</span>
              </div>
            </button>
          </div>
        </div>

        <!-- Footer -->
        <div class="panel-footer">
          <i class="pi pi-info-circle"></i>
          <span>Suas preferências são salvas automaticamente</span>
        </div>
      </div>
    </OverlayPanel>
  </div>
</template>

<style scoped>
.theme-selector-wrapper {
  display: inline-flex;
  align-items: center;
}

/* ==================== PANEL ==================== */
:deep(.theme-panel.p-overlaypanel) {
  background: var(--card-bg);
  border: 1px solid var(--sidebar-border);
  border-radius: 1rem;
  box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.4);
  padding: 0;
  width: 380px;
  max-width: calc(100vw - 2rem);
  animation: panelSlideIn 0.2s ease;
}

:deep(.theme-panel .p-overlaypanel-content) {
  padding: 0;
}

:deep(.theme-panel::before),
:deep(.theme-panel::after) {
  border-bottom-color: var(--sidebar-border) !important;
}

@keyframes panelSlideIn {
  from { opacity: 0; transform: translateY(8px); }
  to   { opacity: 1; transform: translateY(0); }
}

.theme-panel-content {
  display: flex;
  flex-direction: column;
  gap: 1.25rem;
  padding: 1.25rem;
}

/* ==================== HEADER ==================== */
.panel-header {
  display: flex;
  align-items: center;
  gap: 0.875rem;
}

.header-icon {
  width: 2.5rem;
  height: 2.5rem;
  border-radius: 0.75rem;
  background: var(--primary-color);
  display: flex;
  align-items: center;
  justify-content: center;
  color: white;
  font-size: 1.1rem;
  flex-shrink: 0;
}

.header-title {
  font-size: 1rem;
  font-weight: 700;
  color: var(--text-color);
  margin: 0;
  line-height: 1.3;
}

.header-subtitle {
  font-size: 0.75rem;
  color: var(--text-muted);
  margin: 0;
}

/* ==================== SECTIONS ==================== */
.mode-section,
.theme-section {
  display: flex;
  flex-direction: column;
  gap: 0.625rem;
}

.section-label {
  font-size: 0.75rem;
  font-weight: 700;
  color: var(--text-muted);
  text-transform: uppercase;
  letter-spacing: 0.06em;
}

/* ==================== MODE TOGGLE ==================== */
.mode-toggle {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 0.375rem;
  padding: 0.25rem;
  background: var(--sidebar-border);
  border-radius: 0.625rem;
}

.mode-option {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 0.5rem;
  padding: 0.625rem 1rem;
  border-radius: 0.5rem;
  border: none;
  background: transparent;
  color: var(--text-muted);
  font-size: 0.875rem;
  font-weight: 500;
  cursor: pointer;
  transition: all 0.2s ease;
}

.mode-option:hover {
  color: var(--text-color);
  background: color-mix(in srgb, var(--text-color) 8%, transparent);
}

.mode-option.active {
  background: var(--card-bg);
  color: var(--text-color);
  font-weight: 600;
  box-shadow: 0 1px 4px rgba(0, 0, 0, 0.15);
}

/* ==================== THEME GRID ==================== */
.theme-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 0.625rem;
}

.theme-card {
  display: flex;
  flex-direction: column;
  gap: 0;
  padding: 0;
  border: 2px solid transparent;
  border-radius: 0.75rem;
  background: var(--sidebar-border);
  cursor: pointer;
  transition: all 0.2s ease;
  overflow: hidden;
}

.theme-card:hover {
  transform: translateY(-3px);
  border-color: color-mix(in srgb, var(--primary-color) 50%, transparent);
  box-shadow: 0 6px 20px -4px rgba(0, 0, 0, 0.25);
}

.theme-card.active {
  border-color: var(--primary-color);
  background: color-mix(in srgb, var(--primary-color) 8%, transparent);
}

/* Preview */
.theme-preview {
  position: relative;
  aspect-ratio: 16/9;
  border-radius: 0.4rem;
  margin: 0.4rem 0.4rem 0;
  overflow: hidden;
}

.preview-gradient {
  width: 100%;
  height: 100%;
  position: relative;
  overflow: hidden;
}

.preview-shine {
  position: absolute;
  top: -50%;
  left: -50%;
  width: 200%;
  height: 200%;
  background: linear-gradient(45deg, transparent, rgba(255,255,255,0.15), transparent);
  animation: shine 3s infinite;
}

@keyframes shine {
  0%   { transform: translateX(-100%) translateY(-100%) rotate(45deg); }
  100% { transform: translateX(100%) translateY(100%) rotate(45deg); }
}

.active-badge {
  position: absolute;
  top: 0.35rem;
  right: 0.35rem;
  width: 1.25rem;
  height: 1.25rem;
  border-radius: 50%;
  background: white;
  color: #1e293b;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 0.65rem;
  font-weight: 700;
  box-shadow: 0 2px 6px rgba(0,0,0,0.3);
}

.theme-info {
  padding: 0.4rem 0.6rem 0.6rem;
}

.theme-name {
  font-size: 0.75rem;
  font-weight: 600;
  color: var(--text-color);
  text-align: center;
  display: block;
}

/* ==================== FOOTER ==================== */
.panel-footer {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.75rem;
  background: color-mix(in srgb, var(--primary-color) 6%, transparent);
  border-radius: 0.5rem;
  font-size: 0.75rem;
  color: var(--text-muted);
  border: 1px solid var(--sidebar-border);
}

.panel-footer i {
  color: var(--primary-color);
  font-size: 0.85rem;
  flex-shrink: 0;
}
</style>
