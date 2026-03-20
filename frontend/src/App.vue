<template>
  <!-- O RouterView injeta a página atual dentro do AdminLayout -->
  <router-view />
</template>

<style>
/* Estilos Globais Modernos (DNA Arbflow) */
:root {
  --p-primary-color: #3b82f6; /* Azul Sentinela */
}

body {
  margin: 0;
  font-family: 'Inter', -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
  background-color: #f1f5f9;
}

/* Scrollbar Bonito */
::-webkit-scrollbar {
  width: 8px;
  height: 8px;
}
::-webkit-scrollbar-track {
  background: #f1f5f9;
}
::-webkit-scrollbar-thumb {
  background: #cbd5e1;
  border-radius: 4px;
}
::-webkit-scrollbar-thumb:hover {
  background: #94a3b8;
}
</style>
