import { defineStore } from 'pinia';
import axios from 'axios';
import { API_ENDPOINTS } from '@/config/api';

const ERROR_MSG = 'Não foi possível carregar os dados. Verifique a conexão com o servidor.';

export const useCnpjDetailStore = defineStore('cnpjDetail', {
  state: () => ({
    // ── Cadastro ──────────────────────────────────────────────────────────────
    dadosCadastro:        null,
    dadosCadastroLoading: false,

    // ── Evolução Financeira ───────────────────────────────────────────────────
    evolucaoFinanceira: null,
    evolucaoLoading:    false,
    evolucaoLoaded:     false,
    evolucaoError:      null,
    evolucaoKey:        null,   // Cache key: "cnpj|inicio|fim" — evita re-fetch desnecessário

    // ── Movimentação (Memória de Cálculo) ─────────────────────────────────────
    movimentacaoData:    null,
    movimentacaoLoading: false,
    movimentacaoLoaded:  false,
    movimentacaoError:   null,

    // ── Indicadores de Risco ──────────────────────────────────────────────────
    indicadoresData:    null,
    indicadoresLoading: false,
    indicadoresLoaded:  false,
    indicadoresError:   null,

    // ── Falecidos ─────────────────────────────────────────────────────────────
    falecidosData:    null,
    falecidosLoading: false,
    falecidosLoaded:  false,
    falecidosError:   null,

    // ── Prescritores / CRMs ───────────────────────────────────────────────────
    prescritoresData:    null,
    prescritoresLoading: false,
    prescritoresLoaded:  null,   // Cache key: "cnpj|inicio|fim"
    prescritoresError:   null,

    // ── Perfil Diário de Dispensações (gráfico CRM) ──────────────────────────
    crmDailyProfile:        null,
    crmDailyProfileLoading: false,
    crmDailyProfileLoaded:  null,

    // ── Perfil Horário de Detalhamento (Drill-down pré-carregado) ─────────────
    crmHourlyProfile:        null,
    crmHourlyProfileLoading: false,
    crmHourlyProfileLoaded:  null,

    // ── CNPJs abertos por URL direta (fora do fluxo de filtros globais) ───────
    cnpjsAvulsos: new Map(),

    // ── Municípios da região do CNPJ (para RegionalTab) ──────────────────────
    municipiosRegiao:        [],
    municipiosRegiaoKey:     null,
    municipiosRegiaoLoading: false,

    // ── Curva de Percentis (Contexto Regional/UF/Brasil) ────────────────────
    metricPercentiles:        null,
    metricPercentilesLoading: false,
    metricPercentilesLoaded:  false, // Guarda a chave do escopo atual
  }),

  actions: {
    // ── Cadastro ──────────────────────────────────────────────────────────────
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

    // ── Evolução Financeira ───────────────────────────────────────────────────
    async fetchEvolucaoFinanceira(cnpj, inicio = null, fim = null) {
      const key = `${cnpj}|${inicio ?? ''}|${fim ?? ''}`;
      if (this.evolucaoKey === key) return;   // Já carregado para este escopo exato

      this.evolucaoLoading = true;
      this.evolucaoError   = null;
      // Não limpa evolucaoFinanceira/evolucaoLoaded aqui — mantém o dado
      // anterior visível enquanto o novo carrega (evita flash na troca de período).

      try {
        const params = {};
        if (inicio) params.data_inicio = inicio;
        if (fim)    params.data_fim    = fim;

        const { data } = await axios.get(API_ENDPOINTS.analyticsEvolucao(cnpj), { params });
        this.evolucaoFinanceira = data;
        this.evolucaoKey        = key;
        this.evolucaoLoaded     = true;
      } catch (e) {
        console.error('Erro ao buscar evolução financeira:', e);
        this.evolucaoError = ERROR_MSG;
      } finally {
        this.evolucaoLoading = false;
      }
    },

    // ── Movimentação ──────────────────────────────────────────────────────────
    async fetchMovimentacao(cnpj) {
      if (!cnpj) return;
      this.movimentacaoLoading = true;
      this.movimentacaoError   = null;
      try {
        const { data } = await axios.get(API_ENDPOINTS.analyticsMovimentacao(cnpj));
        this.movimentacaoData   = data;
        this.movimentacaoLoaded = true;
      } catch (e) {
        console.error('Erro ao buscar movimentação:', e);
        this.movimentacaoError = 'Não foi possível carregar os dados. Verifique a conexão com o servidor.';
      } finally {
        this.movimentacaoLoading = false;
      }
    },

    // ── Indicadores ───────────────────────────────────────────────────────────
    async fetchIndicadores(cnpj) {
      if (this.indicadoresLoaded) return;
      this.indicadoresLoading = true;
      this.indicadoresError   = null;
      try {
        const { data } = await axios.get(API_ENDPOINTS.analyticsIndicadores(cnpj));
        this.indicadoresData   = data;
        this.indicadoresLoaded = true;
      } catch (e) {
        console.error('Erro ao buscar indicadores:', e);
        this.indicadoresError = ERROR_MSG;
      } finally {
        this.indicadoresLoading = false;
      }
    },

    // ── Falecidos ─────────────────────────────────────────────────────────────
    async fetchFalecidos(cnpj) {
      if (this.falecidosLoaded) return;
      this.falecidosLoading = true;
      this.falecidosError   = null;
      try {
        const { data } = await axios.get(API_ENDPOINTS.analyticsFalecidos(cnpj));
        this.falecidosData   = data;
        this.falecidosLoaded = true;
      } catch (e) {
        console.error('Erro ao buscar dados de falecidos:', e);
        this.falecidosError = ERROR_MSG;
      } finally {
        this.falecidosLoading = false;
      }
    },

    // ── Prescritores / CRMs ───────────────────────────────────────────────────
    async fetchPrescritores(cnpj, inicio = null, fim = null) {
      const key = `${cnpj}|${inicio ?? ''}|${fim ?? ''}`;
      if (this.prescritoresLoaded === key) return;
      this.prescritoresLoading = true;
      this.prescritoresError   = null;
      try {
        const params = {};
        if (inicio) params.data_inicio = inicio;
        if (fim)    params.data_fim    = fim;
        const { data } = await axios.get(API_ENDPOINTS.analyticsPrescritores(cnpj), { params });
        this.prescritoresData   = data;
        this.prescritoresLoaded = key;
      } catch (e) {
        console.error('Erro ao buscar dados de prescritores:', e);
        this.prescritoresError = ERROR_MSG;
      } finally {
        this.prescritoresLoading = false;
      }
    },

    // ── Perfil Diário de Dispensações ────────────────────────────────────────
    async fetchCrmDailyProfile(cnpj, inicio = null, fim = null) {
      const key = `${cnpj}|${inicio ?? ''}|${fim ?? ''}`;
      if (!cnpj || this.crmDailyProfileLoaded === key) return;
      this.crmDailyProfileLoading = true;
      try {
        const params = {};
        if (inicio) params.data_inicio = inicio;
        if (fim)    params.data_fim    = fim;
        const { data } = await axios.get(API_ENDPOINTS.analyticsCrmDailyProfile(cnpj), { params });
        this.crmDailyProfile        = data;
        this.crmDailyProfileLoaded  = key;
      } catch (e) {
        console.error('Erro ao buscar perfil diário de CRM:', e);
      } finally {
        this.crmDailyProfileLoading = false;
      }
    },

    async fetchCrmHourlyProfile(cnpj, inicio = null, fim = null) {
      const key = `${cnpj}|${inicio ?? ''}|${fim ?? ''}`;
      if (!cnpj || this.crmHourlyProfileLoaded === key) return;
      this.crmHourlyProfileLoading = true;
      try {
        const params = {};
        if (inicio) params.data_inicio = inicio;
        if (fim)    params.data_fim    = fim;
        const { data } = await axios.get(API_ENDPOINTS.analyticsCrmHourlyProfile(cnpj), { params });
        this.crmHourlyProfile       = data;
        this.crmHourlyProfileLoaded = key;
      } catch (e) {
        console.error('Erro ao buscar perfil horário:', e);
      } finally {
        this.crmHourlyProfileLoading = false;
      }
    },

    // ── CNPJs Avulsos ─────────────────────────────────────────────────────────
    async fetchCnpjAvulso(cnpj, inicio = null, fim = null) {
      if (!cnpj || this.cnpjsAvulsos.has(cnpj)) return;
      try {
        const params = {};
        if (inicio) params.data_inicio = inicio;
        if (fim)    params.data_fim    = fim;
        params.cnpj_raiz = cnpj;
        const response = await axios.get(API_ENDPOINTS.analyticsResumo, { params });
        const found = (response.data.resultado_cnpjs || []).find(c => c.cnpj === cnpj);
        if (found) this.cnpjsAvulsos.set(cnpj, found);
      } catch (err) {
        console.error('Erro ao carregar CNPJ avulso:', err);
      }
    },

    // ── Municípios da Região ──────────────────────────────────────────────────
    async fetchMunicipiosRegiao(uf, regiao, inicio = null, fim = null) {
      if (!uf || !regiao) return;
      const key = `${uf}|${regiao}|${inicio ?? ''}|${fim ?? ''}`;
      if (this.municipiosRegiaoKey === key) return;
      this.municipiosRegiaoLoading = true;
      try {
        const params = {};
        if (inicio) params.data_inicio = inicio;
        if (fim)    params.data_fim    = fim;
        params.uf           = uf;
        params.regiao_saude = regiao;
        const response = await axios.get(API_ENDPOINTS.analyticsResumo, { params });
        this.municipiosRegiao    = response.data.resultado_municipios || [];
        this.municipiosRegiaoKey = key;
      } catch (err) {
        console.error('Erro ao buscar municípios da região:', err);
      } finally {
        this.municipiosRegiaoLoading = false;
      }
    },

    setMetricPercentilesDirectly(data, cacheKey) {
      this.metricPercentiles = data || [];
      this.metricPercentilesLoaded = cacheKey;
    },

    async fetchMetricPercentiles(scope, uf = null, regiao_id = null, metric = 'score', inicio = null, fim = null) {
      const key = `${scope}|${uf ?? ''}|${regiao_id ?? ''}|${metric}|${inicio ?? ''}|${fim ?? ''}`;
      if (this.metricPercentilesLoaded === key) return;
      
      this.metricPercentilesLoading = true;
      try {
        const params = { scope, uf, regiao_id, metric };
        if (inicio) params.data_inicio = inicio;
        if (fim)    params.data_fim    = fim;

        const { data } = await axios.get(API_ENDPOINTS.analyticsMetricPercentiles, { params });
        this.metricPercentiles = data || [];
        this.metricPercentilesLoaded = key;
      } catch (e) {
        console.error('Erro ao buscar percentis da métrica:', e);
      } finally {
        this.metricPercentilesLoading = false;
      }
    },

    // ── Reset completo ao trocar de CNPJ ──────────────────────────────────────
    resetAll() {
      this.dadosCadastro        = null;
      this.dadosCadastroLoading = false;

      this.evolucaoFinanceira = null;
      this.evolucaoLoading    = false;
      this.evolucaoLoaded     = false;
      this.evolucaoError      = null;
      this.evolucaoKey        = null;

      this.movimentacaoData    = null;
      this.movimentacaoLoading = false;
      this.movimentacaoLoaded  = false;
      this.movimentacaoError   = null;

      this.indicadoresData    = null;
      this.indicadoresLoading = false;
      this.indicadoresLoaded  = false;
      this.indicadoresError   = null;

      this.falecidosData    = null;
      this.falecidosLoading = false;
      this.falecidosLoaded  = false;
      this.falecidosError   = null;

      this.prescritoresData    = null;
      this.prescritoresLoading = false;
      this.prescritoresLoaded  = null;
      this.prescritoresError   = null;

      this.crmDailyProfile        = null;
      this.crmDailyProfileLoading = false;
      this.crmDailyProfileLoaded  = null;

      this.municipiosRegiao        = [];
      this.municipiosRegiaoKey     = null;
      this.municipiosRegiaoLoading = false;

      this.metricPercentiles        = null;
      this.metricPercentilesLoading = false;
      this.metricPercentilesLoaded  = false;
    },
  },
});
