import { defineStore } from 'pinia';
import { computed, ref } from 'vue';
import { THEME_PALETTES as palettes, SURFACE_COLORS } from '@/config/themeConfig';

export const useThemeStore = defineStore('theme', () => {
  const isDark = ref(true);
  const currentPalette = ref('azul'); // 'azul' | 'carbon'

  // Escalas de cor para cada paleta (shades do PrimeVue lara)

  const applyTheme = () => {
    const html = document.documentElement;

    // Modo
    html.classList.toggle('dark-mode', isDark.value);
    html.classList.toggle('light-mode', !isDark.value);
    document.body.classList.toggle('dark-mode', isDark.value);

    // Paleta
    html.classList.toggle('palette-azul',   currentPalette.value === 'azul');
    html.classList.toggle('palette-carbon', currentPalette.value === 'carbon');

    // Sobrescreve as variáveis primárias do PrimeVue lara para os componentes
    // Todos os elementos (PrimeVue + CSS customizado) lêem --primary-color automaticamente
    const palette = palettes[currentPalette.value] ?? palettes.azul;
    // (Dropdown, Slider, Calendar, Button, InputText focus, etc.)
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
    const surface = SURFACE_COLORS[isDark.value ? 'dark' : 'light'];
    Object.keys(surface).forEach(key => {
      html.style.setProperty(`--${key}`, surface[key]);
    });
  };

  const setMode = (mode) => {
    isDark.value = mode === 'dark';
    localStorage.setItem('sentinela_mode', mode);
    applyTheme();
  };

  const setPalette = (palette) => {
    currentPalette.value = palette;
    localStorage.setItem('sentinela_palette', palette);
    applyTheme();
  };

  // Mantido para compatibilidade com usos anteriores
  const toggleTheme = () => {
    setMode(isDark.value ? 'light' : 'dark');
  };

  const initTheme = () => {
    const savedMode = localStorage.getItem('sentinela_mode');
    const savedPalette = localStorage.getItem('sentinela_palette');

    if (savedMode) {
      isDark.value = savedMode === 'dark';
    } else {
      // Se for a primeira vez, o padrão agora é sempre Dark
      isDark.value = true;
    }

    if (savedPalette) {
      currentPalette.value = savedPalette;
    }

    applyTheme();
  };

  /**
   * DESIGN TOKENS REATIVOS (Acesso via JavaScript/Script Setup)
   * Permite que você peça a cor de um card ou texto no JS sem hardcodar o HEX.
   */
  const tokens = computed(() => {
    const palette = palettes[currentPalette.value] ?? palettes.azul;
    const isDarkMode = isDark.value;
    const surface = SURFACE_COLORS[isDarkMode ? 'dark' : 'light'];

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
