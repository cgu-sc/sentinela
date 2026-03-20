import { defineStore } from 'pinia';
import { ref, onMounted } from 'vue';

export const useThemeStore = defineStore('theme', () => {
  const isDark = ref(true); // Padrão Dark por ser mais moderno

  const toggleTheme = () => {
    isDark.value = !isDark.value;
    applyTheme();
    localStorage.setItem('sentinela_mode', isDark.value ? 'dark' : 'light');
  };

  const applyTheme = () => {
    const html = document.documentElement;
    if (isDark.value) {
      html.classList.add('dark-mode');
      html.classList.remove('light-mode');
    } else {
      html.classList.add('light-mode');
      html.classList.remove('dark-mode');
    }
  };

  const initTheme = () => {
    const saved = localStorage.getItem('sentinela_mode');
    if (saved) {
      isDark.value = saved === 'dark';
    } else {
      // Opcional: detectar preferência do sistema
      isDark.value = window.matchMedia('(prefers-color-scheme: dark)').matches;
    }
    applyTheme();
  };

  return { isDark, toggleTheme, initTheme };
});
