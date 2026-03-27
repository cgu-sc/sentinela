import { createApp } from 'vue';
import { createPinia } from 'pinia';
import App from './App.vue';
import router from './router';
import PrimeVue from 'primevue/config';
import Tooltip from 'primevue/tooltip';
import ToastService from 'primevue/toastservice';
import ConfirmationService from 'primevue/confirmationservice';
import VueApexCharts from 'vue3-apexcharts';

// PrimeVue Estilos (DNA Arbflow)
import 'primevue/resources/themes/lara-light-blue/theme.css';
import 'primevue/resources/primevue.min.css';
import 'primeicons/primeicons.css';
import '@/assets/styles/main.css';

const app = createApp(App);

app.use(createPinia()); // Gerenciamento de Estado
app.use(router);      // Roteamento entre abas
app.use(PrimeVue, { 
    ripple: true,   
    inputStyle: 'filled'  
});
app.use(ToastService);
app.use(ConfirmationService);
app.directive('tooltip', Tooltip);
app.use(VueApexCharts);

app.mount('#app');
