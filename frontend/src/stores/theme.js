import { defineStore } from 'pinia';
import { computed, ref } from 'vue';
import axios from 'axios';
import { API_ENDPOINTS } from '@/config/api';
import { THEME_PALETTES as palettes, SURFACE_COLORS } from '@/config/themeConfig';

export const useThemeStore = defineStore('theme', () => {
  const isDark = ref(true);
  const DEFAULT_PALETTE = 'carbon';
  const DEFAULT_MODE = 'dark';
  const AVAILABLE_PALETTES = new Set(['azul_dark', 'carbon']);
  const currentPalette = ref(DEFAULT_PALETTE); // 'azul_dark' | 'carbon'

  // Escalas de cor para cada paleta (shades do PrimeVue lara)

  const applyTheme = () => {
    // 1. Para evitar 'piscadas' ou contrastes ruins durante a mudança de tema,
    // desabilitamos temporariamente todas as transições na página.
    const css = document.createElement('style');
    css.appendChild(
      document.createTextNode(
        `* {
          -webkit-transition: none !important;
          -moz-transition: none !important;
          -o-transition: none !important;
          -ms-transition: none !important;
          transition: none !important;
        }`
      )
    );
    document.head.appendChild(css);

    const html = document.documentElement;

    // Modo
    html.classList.toggle('dark-mode', isDark.value);
    html.classList.toggle('light-mode', !isDark.value);
    document.body.classList.toggle('dark-mode', isDark.value);

    // Paleta
    html.classList.toggle('palette-azul-dark', currentPalette.value === 'azul_dark');
    html.classList.toggle('palette-carbon',    currentPalette.value === 'carbon');

    // Sobrescreve as variáveis primárias do PrimeVue lara para os componentes
    const paletteKey = AVAILABLE_PALETTES.has(currentPalette.value) ? currentPalette.value : DEFAULT_PALETTE;
    const palette = palettes[paletteKey];
    const p = palette.primary;
    html.style.setProperty('--primary-50',         p[50]);
    html.style.setProperty('--primary-100',        p[100]);
    html.style.setProperty('--primary-200',        p[200]);
    html.style.setProperty('--primary-300',        p[300]);
    html.style.setProperty('--primary-400',        p[400]);
    html.style.setProperty('--primary-500',        p[500]);
    html.style.setProperty('--primary-600',        p[600]);
    html.style.setProperty('--primary-700',        p[700]);
    html.style.setProperty('--primary-800',        p[800]);
    html.style.setProperty('--primary-900',        p[900]);
    html.style.setProperty('--primary-color',      p.color);
    html.style.setProperty('--primary-color-text', p.text);

    // 3. Aplicar Cores de Superfície (Backgrounds/Cards/Textos) para consistência absoluta
    const themeKey = paletteKey;
    const surface = SURFACE_COLORS[themeKey][isDark.value ? 'dark' : 'light'];
    
    Object.keys(surface).forEach(key => {
      html.style.setProperty(`--${key}`, surface[key]);
    });

    // Variáveis forçadas para o Dark Mode, usadas ex: tela de boot
    const surfaceDark = SURFACE_COLORS[themeKey]['dark'];
    Object.keys(surfaceDark).forEach(key => {
      html.style.setProperty(`--dark-${key}`, surfaceDark[key]);
    });

    // 4. Forçamos o navegador a renderizar as mudanças instantaneamente
    // antes de devolvermos as transições, evitando a "piscada".
    void document.documentElement.offsetHeight; // Força reflow

    // 5. Removemos o bloqueio de transição para interações futuras
    setTimeout(() => {
      document.head.removeChild(css);
    }, 10);
  };

  const saveThemePreferences = async () => {
    try {
      await axios.put(API_ENDPOINTS.preferencesUi, {
        ui: {
          themeMode: isDark.value ? 'dark' : 'light',
          themePalette: currentPalette.value,
        },
      });
    } catch (error) {
      console.warn('[theme] Falha ao sincronizar tema nas preferencias:', error);
    }
  };

  const setMode = (mode) => {
    isDark.value = mode === 'dark';
    applyTheme();
    saveThemePreferences();
  };

  const setPalette = (palette) => {
    currentPalette.value = AVAILABLE_PALETTES.has(palette) ? palette : DEFAULT_PALETTE;
    applyTheme();
    saveThemePreferences();
  };

  // Mantido para compatibilidade com usos anteriores
  const toggleTheme = () => {
    setMode(isDark.value ? 'light' : 'dark');
  };

  const initTheme = async () => {
    isDark.value = DEFAULT_MODE === 'dark';
    currentPalette.value = DEFAULT_PALETTE;
    applyTheme();

    try {
      const { data } = await axios.get(API_ENDPOINTS.preferences);
      const ui = data?.ui;
      if (!ui || typeof ui !== 'object') {
        await saveThemePreferences();
        return;
      }

      if (ui.themeMode === 'dark' || ui.themeMode === 'light') {
        isDark.value = ui.themeMode === 'dark';
      }
      if (AVAILABLE_PALETTES.has(ui.themePalette)) {
        currentPalette.value = ui.themePalette;
      }

      applyTheme();

      const normalizedMode = isDark.value ? 'dark' : 'light';
      if (ui.themeMode !== normalizedMode || ui.themePalette !== currentPalette.value) {
        await saveThemePreferences();
      }
    } catch (error) {
      console.warn('[theme] Usando tema padrao local:', error);
    }
  };

  /**
   * DESIGN TOKENS REATIVOS (Acesso via JavaScript/Script Setup)
   * Permite que você peça a cor de um card ou texto no JS sem hardcodar o HEX.
   */
  const tokens = computed(() => {
    const themeKey = AVAILABLE_PALETTES.has(currentPalette.value) ? currentPalette.value : DEFAULT_PALETTE;
    const palette = palettes[themeKey];
    const isDarkMode = isDark.value;
    const surface = SURFACE_COLORS[themeKey][isDarkMode ? 'dark' : 'light'];

    return {
      primary: palette.primary.color,
      bgColor: surface['bg-color'],
      textColor: surface['text-color'],
      cardBg: surface['card-bg'],
      sidebarBg: surface['sidebar-bg'],
      borderColor: surface['sidebar-border'],
      mutedColor: surface['text-muted']
    };
  });

  return { isDark, currentPalette, tokens, toggleTheme, setMode, setPalette, initTheme };
});
