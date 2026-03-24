import { defineStore } from 'pinia';
import { ref } from 'vue';

export const useThemeStore = defineStore('theme', () => {
  const isDark = ref(true);
  const currentPalette = ref('azul'); // 'azul' | 'carbon'

  // Escalas de cor para cada paleta (shades do PrimeVue lara)
  const palettes = {
    azul: {
      accent: '#3b82f6',
      primary: {
        50:    '#eff6ff',
        100:   '#dbeafe',
        200:   '#bfdbfe',
        300:   '#93c5fd',
        400:   '#60a5fa',
        500:   '#3b82f6',
        600:   '#2563eb',
        700:   '#1d4ed8',
        800:   '#1e40af',
        900:   '#1e3a8a',
        color: '#3b82f6',
        text:  '#ffffff',
      },
    },
    carbon: {
      accent: '#d97706',
      primary: {
        50:    '#fffbeb',
        100:   '#fef3c7',
        200:   '#fde68a',
        300:   '#fcd34d',
        400:   '#fbbf24',
        500:   '#f59e0b',
        600:   '#d97706',
        700:   '#b45309',
        800:   '#92400e',
        900:   '#78350f',
        color: '#d97706',
        text:  '#ffffff',
      },
    },
  };

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
      isDark.value = window.matchMedia('(prefers-color-scheme: dark)').matches;
    }

    if (savedPalette) {
      currentPalette.value = savedPalette;
    }

    applyTheme();
  };

  return { isDark, currentPalette, toggleTheme, setMode, setPalette, initTheme };
});
