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
      { path: 'municipios', name: 'Municipalities', component: MunicipalView },
      { path: 'estabelecimentos', name: 'Establishments', component: CnpjView },
      { path: 'estabelecimentos/:cnpj', name: 'EstablishmentDetail', component: () => import('@/views/CnpjDetailView.vue') },
      
      // Redirecionamentos para legibilidade e retrocompatibilidade
      { path: 'municipio', redirect: '/municipios' },
      { path: 'cnpj', redirect: '/estabelecimentos' },
      { path: 'estabelecimento/:cnpj', redirect: to => `/estabelecimentos/${to.params.cnpj}` },

      { path: 'indicadores', component: () => import('@/views/IndicatorsView.vue') },
      { path: 'regional', component: () => import('@/views/RegionalView.vue') },
      { path: 'listas', name: 'FarmaciaLists', component: () => import('@/views/lists/WatchlistView.vue') },
    ]
  }
]

const router = createRouter({
  history: createWebHistory(),
  routes
})

export default router
