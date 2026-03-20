import { createRouter, createWebHistory } from 'vue-router'
import AdminLayout from '../layouts/AdminLayout.vue'
import DashboardView from '../views/DashboardView.vue'

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
      // Aqui você pode adicionar as outras abas conforme criarmos
      // { path: 'dispersao', component: DispersaoView },
      // { path: 'municipio', component: MunicipioView },
    ]
  }
]

const router = createRouter({
  history: createWebHistory(),
  routes
})

export default router
