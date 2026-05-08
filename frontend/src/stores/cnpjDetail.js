import { defineStore } from 'pinia';
import axios from 'axios';
import { API_ENDPOINTS } from '@/config/api';

const ERROR_MSG = 'Não foi possível carregar os dados. Verifique a conexão com o servidor.';

function buildTimingDetail(data) {
  if (!('from_cache' in data)) return null;
  if (data.from_cache) {
    return data.read_time_ms != null ? `parquet ${data.read_time_ms}ms` : 'cache';
  }
  return [
    data.query_time_ms != null ? `servidor: SQL ${data.query_time_ms}ms` : null,
    data.save_time_ms  != null ? `disco ${data.save_time_ms}ms`          : null,
  ].filter(Boolean).join(' | ') || null;
}

export const useCnpjDetailStore = defineStore('cnpjDetail', {
  state: () => ({
    // ── Cadastro ──────────────────────────────────────────────────────────────
    dadosCadastro:        null,
    dadosCadastroLoading: false,

    // ── Movimentação Financeira ───────────────────────────────────────────────
    evolucaoFinanceira: null,
    evolucaoLoading:    false,
    evolucaoLoaded:     false,
    evolucaoError:      null,
    evolucaoKey:        null,   // Cache key: "cnpj|inicio|fim" — evita re-fetch desnecessário

    // ── Memória de Cálculo ────────────────────────────────────────────────────
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
    falecidosLoaded:  null,   // Cache key: "cnpj|inicio|fim"
    falecidosError:   null,

    // ── Prescritores / CRMs ───────────────────────────────────────────────────
    prescritoresData:    null,
    prescritoresLoading: false,
    prescritoresLoaded:  null,   // Cache key: "cnpj|inicio|fim"
    prescritoresError:   null,

    // ── Perfil Diário Unificado (CRM Múltiplos + CRM Único) ──────────────────
    crmPerfilDiario:        null,
    crmPerfilDiarioLoading: false,
    crmPerfilDiarioLoaded:  null,  // Cache key: "cnpj|inicio|fim"

    // ── Perfil Horário Unificado (CRM Múltiplos + CRM Único) ──────────────────
    crmPerfilHorario:        null,
    crmPerfilHorarioLoading: false,
    crmPerfilHorarioLoaded:  null,  // Cache key: "cnpj|inicio|fim"

    // ── CNPJs abertos por URL direta (fora do fluxo de filtros globais) ───────
    cnpjsAvulsos:        new Map(),
    cnpjsAvulsosLoading: false,

    // ── Municípios da região do CNPJ (para RegionalTab) ──────────────────────
    municipiosRegiao:        [],
    municipiosRegiaoKey:     null,
    municipiosRegiaoLoading: false,

    // ── Curva de Percentis (Contexto Regional/UF/Brasil) ────────────────────
    metricPercentiles:        null,
    metricPercentilesLoading: false,
    metricPercentilesLoaded:  false, // Guarda a chave do escopo atual
    
    // ── Evolução Mensal GTIN ─────────────────────────────────────────────────
    evolucaoMensalGtin:        null,
    evolucaoMensalGtinLoading: false,
    evolucaoMensalGtinKey:     null,

    // ── Navegação Deep-Link (Timeline) ──────────────────────────────────────
    selectedTimelineEvent: null, // { date: 'YYYY-MM-DD', hour: number | 'all' }
    activeCrmViewMode:     'medicos', // 'medicos' | 'cronologia'

    // ── Ranking GTINs ─────────────────────────────────────────────────────────
    gtinDetalhamentoMensalData: null,
    gtinDetalhamentoMensalLoading: false,
    gtinDetalhamentoMensalError: null,
    
    // ── Quadro Societário ─────────────────────────────────────────────────────
    sociosData:    null,
    sociosLoading: false,
    sociosLoaded:  false,
    sociosError:   null,

    // ── Timing de Requisições (diagnóstico de performance) ───────────────────
    // Chave → { label: string, ms: number }  — preenchido após cada fetch bem-sucedido.
    requestTimes: {},
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

    // ── Movimentação Financeira ───────────────────────────────────────────────
    async fetchEvolucaoFinanceira(cnpj, inicio = null, fim = null) {
      const key = `${cnpj}|${inicio ?? ''}|${fim ?? ''}`;
      if (this.evolucaoKey === key) return;

      this.evolucaoLoading = true;

      try {
        const params = {};
        if (inicio) params.data_inicio = inicio;
        if (fim)    params.data_fim    = fim;

        const t0 = performance.now();
        const { data } = await axios.get(API_ENDPOINTS.analyticsEvolucao(cnpj), { params });
        this.requestTimes['evolucao'] = { label: 'Movimentação Financeira', ms: Math.round(performance.now() - t0) };
        this.evolucaoFinanceira = data;
        this.evolucaoKey        = key;
        this.evolucaoLoaded     = true;
        this.evolucaoError      = null;
      } catch (e) {
        console.error('Erro ao buscar evolução financeira:', e);
        this.evolucaoError = ERROR_MSG;
      } finally {
        this.evolucaoLoading = false;
      }
    },

    // ── Evolução Mensal GTIN ─────────────────────────────────────────────────
    async fetchEvolucaoMensalGtin(cnpj, inicio = null, fim = null) {
      const key = `${cnpj}|${inicio ?? ''}|${fim ?? ''}`;
      if (this.evolucaoMensalGtinKey === key) return;
      this.evolucaoMensalGtinLoading = true;
      try {
        const params = {};
        if (inicio) params.data_inicio = inicio;
        if (fim)    params.data_fim    = fim;
        const t0 = performance.now();
        const { data } = await axios.get(API_ENDPOINTS.analyticsEvolucaoMensalGtin(cnpj), { params });
        const ms = Math.round(performance.now() - t0);
        this.requestTimes['movimentacao-gtin'] = { label: 'Movimentação GTIN', ms, detail: buildTimingDetail(data) };
        this.evolucaoMensalGtin    = data;
        this.evolucaoMensalGtinKey = key;
      } catch (e) {
        console.error('Erro ao buscar evolução mensal GTIN:', e);
      } finally {
        this.evolucaoMensalGtinLoading = false;
      }
    },

    // ── Ranking de GTINs Infratores ──────────────────────────────────────────
    async fetchGtinDetalhamentoMensal(cnpj, periodo) {
      this.gtinDetalhamentoMensalLoading = true;
      this.gtinDetalhamentoMensalError = null;
      try {
        const { data } = await axios.get(API_ENDPOINTS.analyticsGtinDetalhamentoMensal(cnpj, periodo));
        // Agrupar os resultados diretamente usando o "periodo" fornecido como chave.
        // Diferente das outras chamadas que vêm com listas longas, o Raio-X Mensal traz o ranking de um mês específico
        this.gtinDetalhamentoMensalData = data;
      } catch (error) {
        console.error('Erro ao buscar detalhamento mensal de GTINs:', error);
        this.gtinDetalhamentoMensalError = ERROR_MSG;
        this.gtinDetalhamentoMensalData = null;
      } finally {
        this.gtinDetalhamentoMensalLoading = false;
      }
    },

    // ── Memória de Cálculo ────────────────────────────────────────────────────
    async fetchMovimentacao(cnpj) {
      if (!cnpj) return;
      this.movimentacaoLoading = true;
      try {
        const t0 = performance.now();
        const { data } = await axios.get(API_ENDPOINTS.analyticsMovimentacao(cnpj));
        const ms = Math.round(performance.now() - t0);
        this.requestTimes['movimentacao'] = { label: 'Memória de Cálculo', ms, detail: buildTimingDetail(data) };
        this.movimentacaoData   = data;
        this.movimentacaoLoaded = true;
        this.movimentacaoError  = null;
      } catch (e) {
        console.error('Erro ao buscar movimentação:', e);
        this.movimentacaoError = ERROR_MSG;
      } finally {
        this.movimentacaoLoading = false;
      }
    },

    // ── Indicadores ───────────────────────────────────────────────────────────
    async fetchIndicadores(cnpj) {
      if (this.indicadoresLoaded) return;
      this.indicadoresLoading = true;
      try {
        const t0 = performance.now();
        const { data } = await axios.get(API_ENDPOINTS.analyticsIndicadores(cnpj));
        this.requestTimes['indicadores'] = { label: 'Indicadores de Risco', ms: Math.round(performance.now() - t0) };
        this.indicadoresData   = data;
        this.indicadoresLoaded = true;
        this.indicadoresError  = null;
      } catch (e) {
        console.error('Erro ao buscar indicadores:', e);
        this.indicadoresError = ERROR_MSG;
      } finally {
        this.indicadoresLoading = false;
      }
    },

    // ── Quadro Societário ─────────────────────────────────────────────────────
    async fetchSocios(cnpj) {
      if (!cnpj || this.sociosLoaded === cnpj) return;
      this.sociosLoading = true;
      this.sociosError   = null;
      try {
        const t0 = performance.now();
        const { data } = await axios.get(API_ENDPOINTS.analyticsSocios(cnpj));
        this.requestTimes['socios'] = { label: 'Quadro Societário', ms: Math.round(performance.now() - t0) };
        this.sociosData   = data;
        this.sociosLoaded = cnpj;
      } catch (e) {
        console.error('Erro ao buscar quadro societário:', e);
        this.sociosError = ERROR_MSG;
      } finally {
        this.sociosLoading = false;
      }
    },

    // ── Falecidos ─────────────────────────────────────────────────────────────
    async fetchFalecidos(cnpj, inicio = null, fim = null) {
      const key = `${cnpj}|${inicio ?? ''}|${fim ?? ''}`;
      if (this.falecidosLoaded === key) return;

      this.falecidosLoading = true;
      try {
        const params = {};
        if (inicio) params.data_inicio = inicio;
        if (fim)    params.data_fim    = fim;

        const t0 = performance.now();
        const { data } = await axios.get(API_ENDPOINTS.analyticsFalecidos(cnpj), { params });
        const ms = Math.round(performance.now() - t0);
        this.requestTimes['falecidos'] = { label: 'Falecidos', ms, detail: buildTimingDetail(data) };

        this.falecidosData   = data;
        this.falecidosLoaded = key;
        this.falecidosError  = null;
      } catch (e) {
        console.error('Erro ao buscar dados de falecidos:', e);
        this.falecidosError = ERROR_MSG;
      } finally {
        this.falecidosLoading = false;
      }
    },

    // ── Prescritores / CRMs ───────────────────────────────────────────────────
    async fetchCrmData(cnpj, inicio = null, fim = null) {
      const key = `${cnpj}|${inicio ?? ''}|${fim ?? ''}`;
      if (this.prescritoresLoaded === key) return;
      this.prescritoresLoading = true;
      try {
        const params = {};
        if (inicio) params.data_inicio = inicio;
        if (fim)    params.data_fim    = fim;
        const t0 = performance.now();
        const { data } = await axios.get(API_ENDPOINTS.analyticsCrmData(cnpj), { params });
        const ms = Math.round(performance.now() - t0);
        this.requestTimes['crm-data'] = { label: 'CRM Data', ms, detail: buildTimingDetail(data) };
        this.prescritoresData   = data;
        this.prescritoresLoaded = key;
        this.prescritoresError  = null;
      } catch (e) {
        console.error('Erro ao buscar dados de prescritores:', e);
        this.prescritoresError = ERROR_MSG;
      } finally {
        this.prescritoresLoading = false;
      }
    },

    // ── Perfil Diário Unificado ─────────────────────────────────────────────────
    async fetchCrmPerfilDiario(cnpj, inicio = null, fim = null) {
      const key = `${cnpj}|${inicio ?? ''}|${fim ?? ''}`;
      if (!cnpj || this.crmPerfilDiarioLoaded === key) return;
      this.crmPerfilDiarioLoading = true;
      try {
        const params = {};
        if (inicio) params.data_inicio = inicio;
        if (fim)    params.data_fim    = fim;
        const t0 = performance.now();
        const { data } = await axios.get(API_ENDPOINTS.analyticsCrmPerfilDiario(cnpj), { params });
        const ms = Math.round(performance.now() - t0);
        this.requestTimes['crm-daily'] = { label: 'Perfil Diário CRM', ms, detail: buildTimingDetail(data) };
        this.crmPerfilDiario        = data;
        this.crmPerfilDiarioLoaded  = key;
      } catch (e) {
        console.error('Erro ao buscar perfil diário de CRM:', e);
      } finally {
        this.crmPerfilDiarioLoading = false;
      }
    },


    async fetchCrmPerfilHorario(cnpj, inicio = null, fim = null) {
      const key = `${cnpj}|${inicio ?? ''}|${fim ?? ''}`;
      if (!cnpj || this.crmPerfilHorarioLoaded === key) return;
      this.crmPerfilHorarioLoading = true;
      try {
        const params = {};
        if (inicio) params.data_inicio = inicio;
        if (fim)    params.data_fim    = fim;
        const t0 = performance.now();
        const { data } = await axios.get(API_ENDPOINTS.analyticsCrmPerfilHorario(cnpj), { params });
        const ms = Math.round(performance.now() - t0);
        this.requestTimes['crm-hourly'] = { label: 'Perfil Horário CRM', ms, detail: buildTimingDetail(data) };
        this.crmPerfilHorario        = data;
        this.crmPerfilHorarioLoaded  = key;
      } catch (e) {
        console.error('Erro ao buscar perfil horário:', e);
      } finally {
        this.crmPerfilHorarioLoading = false;
      }
    },

    // ── CNPJs Avulsos ─────────────────────────────────────────────────────────
    async fetchCnpjAvulso(cnpj, inicio = null, fim = null) {
      if (!cnpj || this.cnpjsAvulsos.has(cnpj)) return;
      this.cnpjsAvulsosLoading = true;
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
      } finally {
        this.cnpjsAvulsosLoading = false;
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

    // ── Navegação ─────────────────────────────────────────────────────────────
    navigateTimeline(date, hour = 'all') {
      this.selectedTimelineEvent = { date, hour, ts: Date.now() };
      this.activeCrmViewMode     = 'cronologia';
    },

    setCrmViewMode(mode) {
      this.activeCrmViewMode = mode;
    },

    clearTimelineNavigation() {
      this.selectedTimelineEvent = null;
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

      this.evolucaoMensalGtin        = null;
      this.evolucaoMensalGtinLoading = false;
      this.evolucaoMensalGtinKey     = null;

      this.gtinDetalhamentoMensalData    = null;
      this.gtinDetalhamentoMensalLoading = false;
      this.gtinDetalhamentoMensalError   = null;

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
      this.falecidosLoaded  = null;
      this.falecidosError   = null;

      this.prescritoresData    = null;
      this.prescritoresLoading = false;
      this.prescritoresLoaded  = null;
      this.prescritoresError   = null;

      this.crmPerfilDiario        = null;
      this.crmPerfilDiarioLoading = false;
      this.crmPerfilDiarioLoaded  = null;

      this.activeCrmViewMode = 'medicos';
      this.selectedTimelineEvent = null;

      this.requestTimes = {};

      this.cnpjsAvulsos        = new Map();
      this.cnpjsAvulsosLoading = false;

      this.municipiosRegiao        = [];
      this.municipiosRegiaoKey     = null;
      this.municipiosRegiaoLoading = false;

      this.metricPercentiles        = null;
      this.metricPercentilesLoading = false;
      this.metricPercentilesLoaded  = false;

      this.sociosData    = null;
      this.sociosLoading = false;
      this.sociosLoaded  = false;
      this.sociosError   = null;
    },
  },
});
