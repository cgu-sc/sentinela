import { createApp } from 'vue';
import { createPinia } from 'pinia';
import App from './App.vue';
import router from './router';
import PrimeVue from 'primevue/config';

// PrimeVue Estilos (DNA Arbflow)
import 'primevue/resources/themes/lara-light-blue/theme.css';
import 'primevue/resources/primevue.min.css';
import 'primeicons/primeicons.css';

const app = createApp(App);

app.use(createPinia()); // Gerenciamento de Estado
app.use(router);      // Roteamento entre abas
app.use(PrimeVue, { 
    ripple: true,   
    inputStyle: 'filled'  
});

app.mount('#app');
