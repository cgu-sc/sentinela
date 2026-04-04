import { createRouter, createWebHistory } from 'vue-router'
import AppLayout from '@/layouts/AppLayout.vue'
import NationalAnalysisView from '@/views/consolidated/NationalAnalysisView.vue'
import MunicipalityAnalysisView from '@/views/consolidated/MunicipalityAnalysisView.vue'
import CnpjAnalysisView from '@/views/consolidated/CnpjAnalysisView.vue'
import TargetClusterView from '@/views/targets/TargetClusterView.vue'
import PartnerNetworkView from '@/views/targets/PartnerNetworkView.vue'

const routes = [
  {
    path: '/',
    component: AppLayout,
    children: [
      {
        path: '',
        name: 'Dashboard',
        component: NationalAnalysisView
      },
      // Rotas do Módulo Consolidado
      { path: 'dispersao', component: NationalAnalysisView }, // Mockup reusando a mesma view por enquanto
      { path: 'dispersao-beneficio', component: () => import('@/views/consolidated/BeneficioDispersaoView.vue') },
      { path: 'municipio', component: MunicipalityAnalysisView },
      { path: 'cnpj', component: CnpjAnalysisView },
      { path: 'regional', component: () => import('@/views/consolidated/RegionalAnalysisView.vue') },

      // Detalhamento de CNPJ
      { path: 'estabelecimento/:cnpj', name: 'CnpjDetail', component: () => import('@/views/consolidated/CnpjDetailView.vue') },

      // Farmácias Monitoradas (Interesse + Blacklist)
      { path: 'listas', name: 'FarmaciaLists', component: () => import('@/views/lists/FarmaciaListsView.vue') },

      // Rotas do Módulo de Alvos
      { path: 'alvos/cluster', component: TargetClusterView },
      { path: 'alvos/situacao', component: TargetClusterView }, // Mockup
      { path: 'alvos/variacao', component: TargetClusterView }, // Mockup
      { path: 'alvos/rede', component: PartnerNetworkView },
    ]
  }
]

const router = createRouter({
  history: createWebHistory(),
  routes
})

export default router
