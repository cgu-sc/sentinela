import { createRouter, createWebHistory } from 'vue-router'
import AppLayout from '@/layouts/AppLayout.vue'
import NationalView from '@/views/NationalView.vue'
import MunicipalView from '@/views/MunicipalView.vue'
import CnpjView from '@/views/CnpjView.vue'

const routes = [
  {
    path: '/',
    component: AppLayout,
    children: [
      { path: '', name: 'Dashboard', component: NationalView },
      { path: 'dispersao', component: NationalView },
      { path: 'dispersao-beneficio', component: () => import('@/views/BenefitDispersionView.vue') },
      { path: 'municipio', component: MunicipalView },
      { path: 'cnpj', component: CnpjView },
      { path: 'indicadores', component: () => import('@/views/IndicatorsView.vue') },
      { path: 'regional', component: () => import('@/views/RegionalView.vue') },
      { path: 'estabelecimento/:cnpj', name: 'CnpjDetail', component: () => import('@/views/CnpjDetailView.vue') },
      { path: 'listas', name: 'FarmaciaLists', component: () => import('@/views/lists/WatchlistView.vue') },
    ]
  }
]

const router = createRouter({
  history: createWebHistory(),
  routes
})

export default router
