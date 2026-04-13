/**
 * Thresholds de classificação de risco de não-comprovação.
 * Fonte única de verdade — alterar aqui reflete em todos os gráficos,
 * tabelas e badges do sistema sem necessidade de tocar em outros arquivos.
 *
 * Regra:
 *   > CRITICAL  → Crítico  (vermelho escuro)
 *   > HIGH      → Alto     (vermelho)
 *   > MEDIUM    → Médio    (amarelo)
 *   ≤ MEDIUM    → Baixo    (verde)
 */
export const RISK_THRESHOLDS = {
  CRITICAL: 60,
  HIGH:     20,
  MEDIUM:    5,
};

/** Limiares para destaques de auditoria financeira */
export const AUDIT_THRESHOLDS = {
  HIGH_VALUE: 150000, // Valores acima de 150K recebem destaque especial
};

/** Paleta de cores hex associada a cada nível (para uso em ECharts e CSS via v-bind). */
export { RISK_COLORS } from './colors.js';

/**
 * Equivalentes RGB dos RISK_COLORS para uso em jsPDF (pdf.setFillColor/setTextColor).
 * Mantidos em sincronia com RISK_COLORS em colors.js.
 */
export const RISK_COLORS_RGB = {
  CRITICAL: [153,  27,  27],   // red-800   #991b1b
  HIGH:     [225,  29,  72],   // rose-600  #e11d48
  MEDIUM:   [245, 158,  11],   // amber-500 #f59e0b
  LOW:      [ 16, 185, 129],   // emerald-500 #10b981
  NONE:     [203, 213, 225],   // slate-300 — sem dados
};

/** Classes CSS associadas a cada nível (para uso em Tags/Badges do PrimeVue). */
export const RISK_CSS_CLASSES = {
  CRITICAL: 'risk-critical',
  HIGH:     'risk-high',
  MEDIUM:   'risk-medium',
  LOW:      'risk-low',
};

/**
 * Regras de semáforo para os cards de KPI da aba Análise de CRMs.
 * Nível de alerta: 'red' | 'orange' | 'yellow'  (verde implícito quando valor = 0)
 *
 * TOP 1 / TOP 5 usam dois limiares (3 níveis); demais são binários (0 = verde, >0 = alerta).
 */
// Mapeamento de nível → variável CSS e RGB para PDF
// 'red'    → --risk-high/critical  #ef4444  [239,68,68]
// 'orange' → --risk-medium         #f97316  [249,115,22]
// 'green'  → --risk-low            #10b981  [16,185,129]

/**
 * Regras de semáforo para os cards de KPI da aba Análise de CRMs.
 * TOP 1 / TOP 5 usam dois limiares (ambos disparam 'red'); demais são binários.
 */
export const CRM_KPI_THRESHOLDS = {
  concentracaoTop1:       { atencao: 20, critico: 40, alert: 'red'    },
  concentracaoTop5:       { atencao: 50, critico: 70, alert: 'red'    },
  lancamentosAgrupados:   { alert: 'red'    },
  prescrIntensivaLocal:   { alert: 'red'    },
  prescrIntensivaOcultos: { alert: 'red'    },
  multiFarmacia:          { alert: 'red'    },
  fraudesCrm:             { alert: 'red'    },
  distancia400km:         { alert: 'orange' },  // risco médio — prescrições distantes
};

/**
 * Regras de semáforo para os cards de KPI da aba Falecidos.
 * Binários: verde quando 0, cor de alerta quando > 0.
 */
export const FALECIDOS_KPI_THRESHOLDS = {
  cpfsDistintos:     { alert: 'red'    },
  totalAutorizacoes: { alert: 'red'    },
  valorTotal:        { alert: 'red'    },
  mediaDias:         { alert: 'red'    },
  maxDias:           { alert: 'red'    },
  pctFaturamento:    { alert: 'orange' },
  cpfsMultiCnpj:     { alert: 'red'    },
};

/**
 * Limiares de risco por indicador (ratio = valor_farmacia / mediana_regional).
 * Cada indicador possui sua própria entrada para calibragem independente.
 * Fonte: gerar_relatorio.py → get_limiares_indicador()
 */
export const INDICATOR_THRESHOLDS = {
  // 1. Auditoria Financeira
  percentual_nao_comprovacao:    { atencao: 2.0, critico: 3.0 },

  // 2. Elegibilidade & Clínica
  falecidos:                     { atencao: 2.0, critico: 3.0 },
  incompatibilidade_patologica:  { atencao: 2.0, critico: 3.0 },

  // 3. Padrões de Quantidade
  teto:                   { atencao: 1.2, critico: 1.39 },
  polimedicamento:        { atencao: 2.0, critico: 3.0 },
  media_itens:            { atencao: 1.3, critico: 1.5 },

  // 4. Padrões Financeiros
  ticket_medio:           { atencao: 2.0, critico: 3.0 },
  receita_paciente:       { atencao: 2.0, critico: 3.0 },
  per_capita:             { atencao: 2.0, critico: 3.0 },
  alto_custo:             { atencao: 1.4, critico: 1.7 },

  // 5. Automação & Geografia
  vendas_rapidas:         { atencao: 2.0, critico: 3.0 },
  volume_atipico:         { atencao: 2.0, critico: 3.0 },
  recorrencia_sistemica:  { atencao: 1.4, critico: 1.7 },
  dias_pico:              { atencao: 1.4, critico: 1.7 },
  dispersao_geografica:   { atencao: 2.0, critico: 3.0 },
  pacientes_unicos:       { atencao: 1.4, critico: 1.7 },

  // 6. Integridade Médica
  hhi_crm:                { atencao: 2.0, critico: 3.0 },
  exclusividade_crm:      { atencao: 2.0, critico: 3.0 },
  crms_irregulares:       { atencao: 2.0, critico: 3.0 },
};

/**
 * Definição dos 6 grupos de indicadores e seus 18 indicadores.
 * - key:          identificador no objeto `indicadores` retornado pela API
 * - label:        nome exibido no card
 * - formato:      'pct' | 'pct3' | 'val' | 'dec'
 * - thresholdKey: chave em INDICATOR_THRESHOLDS (igual ao key do indicador)
 * - metodologia:  texto exibido no tooltip ℹ️
 */
export const INDICATOR_GROUPS = [
  {
    id: 'auditoria',
    label: '1. Auditoria Financeira',
    indicators: [
      { key: 'percentual_nao_comprovacao', label: 'Percentual de Não Comprovação', formato: 'pct', thresholdKey: 'percentual_nao_comprovacao',
        metodologia: 'Percentual do valor total de vendas sem comprovação fiscal/clínica na auditoria.' },
    ],
  },
  {
    id: 'elegibilidade',
    label: '2. Elegibilidade & Clínica',
    indicators: [
      { key: 'falecidos', label: 'Vendas p/ Falecidos', formato: 'pct3', thresholdKey: 'falecidos',
        metodologia: 'Confronto direto entre a data da dispensação e a data oficial de óbito (SIM/SIRC/SISOBI).' },
      { key: 'incompatibilidade_patologica', label: 'Incompatibilidade Patológica', formato: 'pct', thresholdKey: 'incompatibilidade_patologica',
        metodologia: 'Confronta a indicação terapêutica com os dados do beneficiário (Idade e Sexo). Sinaliza: Osteoporose em homens, Parkinson <50 anos, Hipertensão <20 anos, Diabetes <20 anos.' },
    ],
  },
  {
    id: 'quantidades',
    label: '3. Padrões de Quantidade',
    indicators: [
      { key: 'teto', label: 'Dispensação em Teto Máximo', formato: 'pct', thresholdKey: 'teto',
        metodologia: 'Percentual de dispensações onde a quantidade vendida atinge exatamente o limite máximo permitido por medicamento.' },
      { key: 'polimedicamento', label: '4+ Itens por Autorização', formato: 'pct', thresholdKey: 'polimedicamento',
        metodologia: 'Percentual de autorizações (cupons fiscais) que contêm 4 ou mais medicamentos distintos dispensados no mesmo ato.' },
      { key: 'media_itens', label: 'Itens por Autorização', formato: 'dec', thresholdKey: 'media_itens',
        metodologia: 'Quantidade média de itens dispensados por cupom fiscal (Total de Caixas / Total de Autorizações).' },
    ],
  },
  {
    id: 'financeiro',
    label: '4. Padrões Financeiros',
    indicators: [
      { key: 'ticket_medio', label: 'Valor do Ticket Médio', formato: 'val', thresholdKey: 'ticket_medio',
        metodologia: 'Valor monetário médio de cada autorização de venda.' },
      { key: 'receita_paciente', label: 'Faturamento Médio por Cliente', formato: 'val', thresholdKey: 'receita_paciente',
        metodologia: 'Faturamento médio mensal da farmácia dividido pelo número de CPFs distintos atendidos (normalizado pelo tempo de atividade).' },
      { key: 'per_capita', label: 'Venda Per Capita Mensal', formato: 'val', thresholdKey: 'per_capita',
        metodologia: 'Faturamento médio mensal da farmácia dividido pela população total do município (estimativa IBGE).' },
      { key: 'alto_custo', label: 'Medicamentos de Alto Custo', formato: 'pct', thresholdKey: 'alto_custo',
        metodologia: 'Percentual do faturamento total proveniente de medicamentos no 90º percentil de preço.' },
    ],
  },
  {
    id: 'automacao',
    label: '5. Automação & Geografia',
    indicators: [
      { key: 'vendas_rapidas', label: 'Vendas Rápidas (<60s)', formato: 'pct', thresholdKey: 'vendas_rapidas',
        metodologia: 'Percentual de vendas consecutivas realizadas em intervalo inferior a 60 segundos.' },
      { key: 'volume_atipico', label: 'Volume Atípico', formato: 'dec', thresholdKey: 'volume_atipico',
        metodologia: 'Mede explosões de crescimento semestral atípicas no faturamento do programa.' },
      { key: 'recorrencia_sistemica', label: 'Recorrência Sistêmica', formato: 'pct', thresholdKey: 'recorrencia_sistemica',
        metodologia: 'Percentual de compras sequenciais realizadas precisamente na linha de corte do sistema (ex: 30 dias exatos), indicando possível automação.' },
      { key: 'dias_pico', label: 'Concentração em Dias de Pico', formato: 'pct', thresholdKey: 'dias_pico',
        metodologia: 'Percentual do faturamento mensal concentrado nos 3 dias de maior movimento do mês.' },
      { key: 'dispersao_geografica', label: 'Dispersão Geográfica Interestadual', formato: 'pct', thresholdKey: 'dispersao_geografica',
        metodologia: 'Percentual de vendas para pacientes cuja UF de residência difere da UF da farmácia.' },
      { key: 'pacientes_unicos', label: 'Pacientes Únicos', formato: 'pct', thresholdKey: 'pacientes_unicos',
        metodologia: 'Proporção de CPFs que realizaram apenas uma única compra durante todo o período analisado (2015-2024).' },
    ],
  },
  {
    id: 'crm',
    label: '6. Integridade Médica',
    indicators: [
      { key: 'hhi_crm', label: 'Concentração de CRMs (HHI)', formato: 'dec', thresholdKey: 'hhi_crm',
        metodologia: 'Índice Herfindahl-Hirschman (HHI) que mede a concentração de prescrições. HHI elevado indica dependência excessiva de poucos CRMs.' },
      { key: 'exclusividade_crm', label: 'Exclusividade de CRMs', formato: 'pct', thresholdKey: 'exclusividade_crm',
        metodologia: 'Percentual de médicos que prescrevem EXCLUSIVAMENTE nesta farmácia em todo o Brasil.' },
      { key: 'crms_irregulares', label: 'Faturamento Atrelado a CRMs Irregulares', formato: 'pct', thresholdKey: 'crms_irregulares',
        metodologia: 'Percentual do faturamento vinculado a CRMs inexistentes no CFM ou com prescrições anteriores à data de inscrição do médico.' },
    ],
  },
];
