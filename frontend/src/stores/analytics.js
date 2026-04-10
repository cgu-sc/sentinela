import { defineStore } from 'pinia';
import axios from 'axios';
import { API_ENDPOINTS } from '@/config/api';
import { KPI_CONFIGS, DEFAULT_KPI_STYLE } from '@/config/uiConfig';
import { FILTER_ALL_VALUE, KPI_LABEL_MAP, KPI_PRIORITY_ORDER } from '@/config/constants';

/**
 * Constrói o objeto de parâmetros para as APIs de analytics.
 * Extrai lógica duplicada que existia em fetchDashboardSummary e fetchFatorRisco.
 */
function buildAnalyticsParams(inicio, fim, percMin, percMax, valMin, uf, regiaoSaude, municipio, situacaoRf, conexaoMs, porteEmpresa, grandeRede, cnpjRaiz) {
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
    evolucaoFinanceira: null,
    dadosCadastro: null,
    // CNPJs abertos fora do fluxo de filtros (ex: URL direta, /listas)
    // Separado de resultadoCnpjs para não contaminar o estado dos filtros globais.
    cnpjsAvulsos: new Map(),
    // Cache de municípios por região — carregado lazily no detalhe do CNPJ
    municipiosRegiao: [],
    municipiosRegiaoKey: null,   // 'UF|regiao' da última carga
    municipiosRegiaoLoading: false,
    isLoading: false,
    fatorRiscoLoading: false,
    evolucaoLoading: false,
    evolucaoLoaded: false,
    dadosCadastroLoading: false,
    error: null,
    lastSync: null
  }),

  actions: {
    async fetchDashboardSummary(inicio = null, fim = null, percMin = null, percMax = null, valMin = null, uf = null, regiaoSaude = null, municipio = null, situacaoRf = null, conexaoMs = null, porteEmpresa = null, grandeRede = null, cnpjRaiz = null) {
      this.isLoading = true;
      this.error = null;
      try {
        const params = buildAnalyticsParams(inicio, fim, percMin, percMax, valMin, uf, regiaoSaude, municipio, situacaoRf, conexaoMs, porteEmpresa, grandeRede, cnpjRaiz);

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
    async fetchSentinelaUFNacional(inicio = null, fim = null, percMin = null, percMax = null, valMin = null, situacaoRf = null, conexaoMs = null, porteEmpresa = null, grandeRede = null) {
      try {
        const params = buildAnalyticsParams(inicio, fim, percMin, percMax, valMin, null, null, null, situacaoRf, conexaoMs, porteEmpresa, grandeRede, null);
        const response = await axios.get(API_ENDPOINTS.analyticsResumo, { params });
        this.resultadoSentinelaUFNacional = response.data.resultado_sentinela_uf;
      } catch (err) {
        console.error('Erro ao buscar dados nacionais por UF:', err);
      }
    },

    async fetchFatorRisco(inicio = null, fim = null, percMin = null, percMax = null, valMin = null, uf = null, regiaoSaude = null, municipio = null, situacaoRf = null, conexaoMs = null, porteEmpresa = null, grandeRede = null, cnpjRaiz = null) {
      this.fatorRiscoLoading = true;
      try {
        const params = buildAnalyticsParams(inicio, fim, percMin, percMax, valMin, uf, regiaoSaude, municipio, situacaoRf, conexaoMs, porteEmpresa, grandeRede, cnpjRaiz);
        const response = await axios.get(API_ENDPOINTS.analyticsFatorRisco, { params });
        this.fatorRisco = response.data.buckets;
      } catch (err) {
        console.error('Erro ao buscar fator de risco:', err);
        this.error = 'Não foi possível carregar o gráfico de fator de risco.';
      } finally {
        this.fatorRiscoLoading = false;
      }
    },

    async fetchEvolucaoFinanceira(cnpj) {
      if (this.evolucaoLoaded) return;
      this.evolucaoLoading = true;
      try {
        const { data } = await axios.get(API_ENDPOINTS.analyticsEvolucao(cnpj));
        this.evolucaoFinanceira = data;
        this.evolucaoLoaded = true;
      } catch (e) {
        console.error('Erro ao buscar evolução financeira:', e);
      } finally {
        this.evolucaoLoading = false;
      }
    },
    
    async fetchDadosCadastro(cnpj) {
      if (!cnpj) return;
      this.dadosCadastroLoading = true;
      try {
        const { data } = await axios.get(API_ENDPOINTS.analyticsCadastro(cnpj));
        this.dadosCadastro = data;
      } catch (e) {
        console.error('Erro ao buscar dados cadastrais:', e);
      } finally {
        this.dadosCadastroLoading = false;
      }
    },

    /**
     * Busca os municípios de uma região de saúde com seus % de não-comprovação,
     * respeitando o período atual (inicio/fim). Usa cache por região.
     */
    async fetchMunicipiosRegiao(uf, regiao, inicio = null, fim = null) {
      if (!uf || !regiao) return;
      const key = `${uf}|${regiao}|${inicio ?? ''}|${fim ?? ''}`;
      if (this.municipiosRegiaoKey === key) return; // já carregado para esta combinação
      this.municipiosRegiaoLoading = true;
      try {
        const params = buildAnalyticsParams(inicio, fim, null, null, null, uf, regiao, null, null, null, null, null, null);
        const response = await axios.get(API_ENDPOINTS.analyticsResumo, { params });
        this.municipiosRegiao    = response.data.resultado_municipios || [];
        this.municipiosRegiaoKey = key;
      } catch (err) {
        console.error('Erro ao buscar municípios da região:', err);
      } finally {
        this.municipiosRegiaoLoading = false;
      }
    },

    /**
     * Carrega um CNPJ avulso (fora do fluxo de filtros) em `cnpjsAvulsos`.
     * Nunca toca em resultadoCnpjs, resultadoMunicipios ou kpis.
     * @param {string} cnpj
     * @param {string|null} inicio
     * @param {string|null} fim
     */
    async fetchCnpjAvulso(cnpj, inicio = null, fim = null) {
      if (!cnpj || this.cnpjsAvulsos.has(cnpj)) return;
      try {
        const params = buildAnalyticsParams(inicio, fim, null, null, null, null, null, null, null, null, null, null, cnpj);
        const response = await axios.get(API_ENDPOINTS.analyticsResumo, { params });
        const found = (response.data.resultado_cnpjs || []).find(c => c.cnpj === cnpj);
        if (found) this.cnpjsAvulsos.set(cnpj, found);
      } catch (err) {
        console.error('Erro ao carregar CNPJ avulso:', err);
      }
    },

    resetEvolucaoFinanceira() {
      this.evolucaoFinanceira = null;
      this.evolucaoLoaded = false;
      this.evolucaoLoading = false;
    },

    resetDadosCadastro() {
      this.dadosCadastro = null;
      this.dadosCadastroLoading = false;
    }
  },

  getters: {
    enrichedKpis: (state) => {
      const enriched = state.kpis.map(kpi => {
        let label = kpi.label.toUpperCase();
        // Aplica mapeamento de labels do backend → UI
        label = KPI_LABEL_MAP[label] ?? label;

        const labelKey = Object.keys(KPI_CONFIGS).find(key => key.toUpperCase() === label);
        const config = KPI_CONFIGS[labelKey] || DEFAULT_KPI_STYLE;

        return {
          ...kpi,
          label,
          icon: kpi.icon || config.icon,
          color: kpi.color || config.color
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
