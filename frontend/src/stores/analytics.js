import { defineStore } from 'pinia';
import axios from 'axios';
import { API_ENDPOINTS } from '@/config/api';
import { KPI_CONFIGS, DEFAULT_KPI_STYLE } from '@/config/uiConfig';
import { FILTER_ALL_VALUE } from '@/config/constants';

export const useAnalyticsStore = defineStore('analytics', {
  state: () => ({
    kpis: [],
    resultadoSentinelaUF: [],
    resultadoMunicipios: [],
    fatorRisco: [],
    isLoading: false,
    fatorRiscoLoading: false,
    error: null,
    lastSync: null
  }),

  actions: {
    /**
     * Busca os dados estratégicos (KPIs e Agrupamento por UF) no Backend.
     * Esta API traz os dados já calculados (agregados) pelo SQL Server.
     */
    async fetchDashboardSummary(inicio = null, fim = null, percMin = null, percMax = null, valMin = null, uf = null, regiaoSaude = null, municipio = null, situacaoRf = null, conexaoMs = null, porteEmpresa = null, grandeRede = null) {
      this.isLoading = true;
      this.error = null;
      try {
        const params = {};
        if (inicio) params.data_inicio = inicio;
        if (fim) params.data_fim = fim;
        if (percMin !== null && percMin !== 0) params.perc_min = percMin;
        if (percMax !== null && percMax !== 100) params.perc_max = percMax;
        if (valMin !== null && valMin > 0) params.val_min = valMin;
        if (uf && uf !== FILTER_ALL_VALUE) params.uf = uf;
        if (regiaoSaude && regiaoSaude !== FILTER_ALL_VALUE) params.regiao_saude = regiaoSaude;
        if (municipio && municipio !== FILTER_ALL_VALUE) params.municipio = municipio;
        if (situacaoRf) params.situacao_rf = situacaoRf;
        if (conexaoMs) params.conexao_ms = conexaoMs;
        if (porteEmpresa) params.porte_empresa = porteEmpresa;
        if (grandeRede) params.grande_rede = grandeRede;

        const response = await axios.get(API_ENDPOINTS.analyticsResumo, { params });
        this.kpis = response.data.kpis;
        this.resultadoSentinelaUF = response.data.resultado_sentinela_uf;
        this.resultadoMunicipios = response.data.resultado_municipios || [];
        this.lastSync = new Date();
      } catch (err) {
        console.error('Erro ao buscar resumo do dashboard:', err);
        this.error = 'Não foi possível carregar as métricas estratégicas.';
      } finally {
        this.isLoading = false;
      }
    },

    /**
     * Busca os dados do gráfico de Fator de Risco baseado num período customizado.
     * Se inicio/fim forem nulos, o backend retorna o acumulado histórico.
     */
    async fetchFatorRisco(inicio = null, fim = null, percMin = null, percMax = null, valMin = null, uf = null, regiaoSaude = null, municipio = null, situacaoRf = null, conexaoMs = null, porteEmpresa = null, grandeRede = null) {
      this.fatorRiscoLoading = true;
      try {
        const params = {};
        if (inicio) params.data_inicio = inicio;
        if (fim) params.data_fim = fim;
        if (percMin !== null && percMin !== 0) params.perc_min = percMin;
        if (percMax !== null && percMax !== 100) params.perc_max = percMax;
        if (valMin !== null && valMin > 0) params.val_min = valMin;
        if (uf && uf !== FILTER_ALL_VALUE) params.uf = uf;
        if (regiaoSaude && regiaoSaude !== FILTER_ALL_VALUE) params.regiao_saude = regiaoSaude;
        if (municipio && municipio !== FILTER_ALL_VALUE) params.municipio = municipio;
        if (situacaoRf) params.situacao_rf = situacaoRf;
        if (conexaoMs) params.conexao_ms = conexaoMs;
        if (porteEmpresa) params.porte_empresa = porteEmpresa;
        if (grandeRede) params.grande_rede = grandeRede;

        const response = await axios.get(API_ENDPOINTS.analyticsFatorRisco, { params });
        this.fatorRisco = response.data.buckets;
      } catch (err) {
        console.error('Erro ao buscar fator de risco:', err);
        this.error = 'Não foi possível carregar o gráfico de fator de risco.';
      } finally {
        this.fatorRiscoLoading = false;
      }
    }
  },

  getters: {
    /**
     * Retorna os KPIs enriquecidos com metadados de UI (ícones e cores).
     * O Pinia cacheia o resultado deste getter, garantindo performance máxima.
     */
    enrichedKpis: (state) => {
      // Ordem desejada exata conforme as Labels do Banco de Dados (Refletindo o print)
      const priorityOrder = [
        'CNPJS',
        'VALOR TOTAL DE VENDAS',
        'TOTAL DE MEDICAMENTOS',
        'VALOR SEM COMPROVAÇÃO',
        '% SEM COMPROVAÇÃO'
      ];

      const enriched = state.kpis.map(kpi => {
        // Renomeia o KPI de Medicamentos para TOTAL DE MEDICAMENTOS
        let label = kpi.label.toUpperCase();
        if (label === 'QTDE DE MEDICAMENTOS') label = 'TOTAL DE MEDICAMENTOS';

        // Encontra a configuração ignorando se é MAIÚSCULO ou minúsculo
        const labelKey = Object.keys(KPI_CONFIGS).find(
            key => key.toUpperCase() === label
        );
        const config = KPI_CONFIGS[labelKey] || DEFAULT_KPI_STYLE;
        
        return {
          ...kpi,
          label: label, // Aplica o novo nome visual
          icon: kpi.icon || config.icon,
          color: kpi.color || config.color
        };
      });

      // Ordena baseado na nossa lista de prioridade (Sempre respeitando as maiúsculas do banco)
      return enriched.sort((a, b) => {
        const indexA = priorityOrder.indexOf(a.label.toUpperCase());
        const indexB = priorityOrder.indexOf(b.label.toUpperCase());
        
        if (indexA !== -1 && indexB !== -1) return indexA - indexB;
        if (indexA !== -1) return -1;
        if (indexB !== -1) return 1;
        return 0;
      });
    },
    getKpiById: (state) => (id) => state.kpis.find(k => k.id === id)
  }
});
