import { defineStore } from 'pinia';
import axios from 'axios';
import { API_ENDPOINTS } from '@/config/api';
import { KPI_CONFIGS, DEFAULT_KPI_STYLE } from '@/config/uiConfig';
import { FILTER_ALL_VALUE, KPI_LABEL_MAP, KPI_PRIORITY_ORDER } from '@/config/constants';
import { RISK_COLORS } from '@/config/colors';
import { RISK_THRESHOLDS } from '@/config/riskConfig';

/**
 * Constrói o objeto de parâmetros para as APIs de analytics.
 * Extrai lógica duplicada que existia em fetchDashboardSummary e fetchFatorRisco.
 */
function buildAnalyticsParams(inicio, fim, percMin, percMax, valMin, uf, regiaoSaude, municipio, situacaoRf, conexaoMs, porteEmpresa, grandeRede, cnpjRaiz, unidadePf = null) {
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
  if (cnpjRaiz) params.cnpj_raiz = cnpjRaiz;
  if (unidadePf) params.unidade_pf = unidadePf;
  return params;
}

export const useAnalyticsStore = defineStore('analytics', {
  state: () => ({
    kpis: [],
    resultadoSentinelaUF: [],
    resultadoSentinelaUFNacional: [], // dados de todas as UFs — só atualiza sem filtro de UF
    resultadoMunicipios: [],
    resultadoCnpjs: [],
    fatorRisco: [],
    isLoading: false,
    fatorRiscoLoading: false,
    error: null,
    lastSync: null
  }),

  actions: {
    async fetchDashboardSummary(inicio = null, fim = null, percMin = null, percMax = null, valMin = null, uf = null, regiaoSaude = null, municipio = null, situacaoRf = null, conexaoMs = null, porteEmpresa = null, grandeRede = null, cnpjRaiz = null, unidadePf = null) {
      this.isLoading = true;
      this.error = null;
      try {
        const params = buildAnalyticsParams(inicio, fim, percMin, percMax, valMin, uf, regiaoSaude, municipio, situacaoRf, conexaoMs, porteEmpresa, grandeRede, cnpjRaiz, unidadePf);

        const response = await axios.get(API_ENDPOINTS.analyticsResumo, { params });
        this.kpis = response.data.kpis;
        this.resultadoSentinelaUF = response.data.resultado_sentinela_uf;
        if (!uf || uf === FILTER_ALL_VALUE) {
          this.resultadoSentinelaUFNacional = response.data.resultado_sentinela_uf;
        }
        this.resultadoMunicipios = response.data.resultado_municipios || [];
        this.resultadoCnpjs = response.data.resultado_cnpjs || [];
        this.lastSync = new Date();
      } catch (err) {
        console.error('Erro ao buscar resumo do dashboard:', err);
        this.error = 'Não foi possível carregar as métricas estratégicas.';
      } finally {
        this.isLoading = false;
      }
    },

    /**
     * Atualiza apenas resultadoSentinelaUFNacional (mapa do Brasil).
     * Chamado quando filtros de valor/percentual mudam com UF selecionada.
     * Nunca inclui filtros de UF/região/município para garantir dados nacionais.
     */
    async fetchSentinelaUFNacional(inicio = null, fim = null, percMin = null, percMax = null, valMin = null, situacaoRf = null, conexaoMs = null, porteEmpresa = null, grandeRede = null, unidadePf = null) {
      try {
        const params = buildAnalyticsParams(inicio, fim, percMin, percMax, valMin, null, null, null, situacaoRf, conexaoMs, porteEmpresa, grandeRede, null, unidadePf);
        const response = await axios.get(API_ENDPOINTS.analyticsResumo, { params });
        this.resultadoSentinelaUFNacional = response.data.resultado_sentinela_uf;
      } catch (err) {
        console.error('Erro ao buscar dados nacionais por UF:', err);
      }
    },

    async fetchFatorRisco(inicio = null, fim = null, percMin = null, percMax = null, valMin = null, uf = null, regiaoSaude = null, municipio = null, situacaoRf = null, conexaoMs = null, porteEmpresa = null, grandeRede = null, cnpjRaiz = null, unidadePf = null) {
      this.fatorRiscoLoading = true;
      try {
        const params = buildAnalyticsParams(inicio, fim, percMin, percMax, valMin, uf, regiaoSaude, municipio, situacaoRf, conexaoMs, porteEmpresa, grandeRede, cnpjRaiz, unidadePf);
        const response = await axios.get(API_ENDPOINTS.analyticsFatorRisco, { params });
        this.fatorRisco = response.data.buckets;
      } catch (err) {
        console.error('Erro ao buscar fator de risco:', err);
        this.error = 'Não foi possível carregar o gráfico de fator de risco.';
      } finally {
        this.fatorRiscoLoading = false;
      }
    },

  },

  getters: {
    enrichedKpis: (state) => {
      const enriched = state.kpis.map(kpi => {
        let label = kpi.label.toUpperCase();
        // Aplica mapeamento de labels do backend → UI
        label = KPI_LABEL_MAP[label] ?? label;

        const labelKey = Object.keys(KPI_CONFIGS).find(key => key.toUpperCase() === label);
        const config = KPI_CONFIGS[labelKey] || DEFAULT_KPI_STYLE;

        let finalColor = kpi.color || config.color;

        // Regra Dinâmica Estrita para o KPI: % SEM COMPROVAÇÃO
        if (label === '% SEM COMPROVAÇÃO' && kpi.value !== undefined) {
          const valStr = String(kpi.value).replace('%', '').replace(/\s/g, '').replace(',', '.');
          const percent = parseFloat(valStr);
          if (!isNaN(percent)) {
            if (percent <= RISK_THRESHOLDS.MEDIUM) {
               finalColor = RISK_COLORS.LOW;     // Verde (Seguro)
            } else if (percent <= RISK_THRESHOLDS.HIGH) {
               finalColor = RISK_COLORS.MEDIUM;  // Laranja/Alerta
            } else {
               finalColor = RISK_COLORS.HIGH;    // Vermelho/Crítico
            }
          }
        }

        return {
          ...kpi,
          label,
          icon: kpi.icon || config.icon,
          color: finalColor
        };
      });

      return enriched.sort((a, b) => {
        const indexA = KPI_PRIORITY_ORDER.indexOf(a.label.toUpperCase());
        const indexB = KPI_PRIORITY_ORDER.indexOf(b.label.toUpperCase());
        if (indexA !== -1 && indexB !== -1) return indexA - indexB;
        if (indexA !== -1) return -1;
        if (indexB !== -1) return 1;
        return 0;
      });
    },
    getKpiById: (state) => (id) => state.kpis.find(k => k.id === id)
  }
});
