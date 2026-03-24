import { createRouter, createWebHistory } from 'vue-router'
import AdminLayout from '../layouts/AdminLayout.vue'
import DashboardView from '../views/DashboardView.vue'
import AlvosClusterView from '../views/AlvosClusterView.vue'
import AlvosSociosView from '../views/AlvosSociosView.vue'

const routes = [
  {
    path: '/',
    component: AdminLayout,
    children: [
      {
        path: '',
        name: 'Dashboard',
        component: DashboardView
      },
      // Rotas do Módulo Consolidado
      { path: 'dispersao', component: DashboardView }, // Mockup reusando a mesma view por enquanto
      { path: 'municipio', component: DashboardView },
      { path: 'empresa', component: DashboardView },
      { path: 'cnpj', component: DashboardView },

      // Rotas do Módulo de Alvos
      { path: 'alvos/cluster', component: AlvosClusterView },
      { path: 'alvos/situacao', component: AlvosClusterView }, // Mockup
      { path: 'alvos/variacao', component: AlvosClusterView }, // Mockup
      { path: 'alvos/rede', component: AlvosSociosView },
    ]
  }
]

const router = createRouter({
  history: createWebHistory(),
  routes
})

export default router
