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

/** Paleta de cores hex associada a cada nível (para uso em ECharts). */
export const RISK_COLORS = {
  CRITICAL: '#991b1b',
  HIGH:     '#ef4444',
  MEDIUM:   '#f59e0b',
  LOW:      '#10b981',
};

/** Classes CSS associadas a cada nível (para uso em Tags/Badges do PrimeVue). */
export const RISK_CSS_CLASSES = {
  CRITICAL: 'risk-critical',
  HIGH:     'risk-high',
  MEDIUM:   'risk-medium',
  LOW:      'risk-low',
};

/**
 * Limiares de risco por indicador (ratio = valor_farmacia / mediana).
 * Fonte: gerar_relatorio.py → get_limiares_indicador()
 */
export const INDICATOR_THRESHOLDS = {
  default:               { atencao: 2.0, critico: 3.0 },
  teto:                  { atencao: 1.2, critico: 1.3 },
  alto_custo:            { atencao: 1.4, critico: 1.7 },
  pico:                  { atencao: 1.4, critico: 1.7 },
  pacientes_unicos:      { atencao: 1.4, critico: 1.7 },
  recorrencia_sistemica: { atencao: 1.4, critico: 1.7 },
};

/**
 * Definição dos 6 grupos de indicadores e seus 18 indicadores.
 * - key:          identificador no objeto `indicadores` retornado pela API
 * - label:        nome exibido no card
 * - formato:      'pct' | 'pct3' | 'val' | 'dec'
 * - thresholdKey: chave em INDICATOR_THRESHOLDS (default se omitido)
 * - metodologia:  texto exibido no tooltip ℹ️
 */
export const INDICATOR_GROUPS = [
  {
    id: 'auditoria',
    label: '1. Auditoria Financeira',
    indicators: [
      { key: 'auditado', label: 'Percentual de Não Comprovação', formato: 'pct', thresholdKey: 'default',
        metodologia: 'Percentual do valor total de vendas sem comprovação fiscal/clínica na auditoria.' },
    ],
  },
  {
    id: 'elegibilidade',
    label: '2. Elegibilidade & Clínica',
    indicators: [
      { key: 'falecidos', label: 'Vendas p/ Falecidos', formato: 'pct3', thresholdKey: 'default',
        metodologia: 'Confronto direto entre a data da dispensação e a data oficial de óbito (SIM/SIRC/SISOBI).' },
      { key: 'clinico', label: 'Incompatibilidade Patológica', formato: 'pct', thresholdKey: 'default',
        metodologia: 'Confronta a indicação terapêutica com os dados do beneficiário (Idade e Sexo). Sinaliza: Osteoporose em homens, Parkinson <50 anos, Hipertensão <20 anos, Diabetes <20 anos.' },
    ],
  },
  {
    id: 'quantidades',
    label: '3. Padrões de Quantidade',
    indicators: [
      { key: 'teto', label: 'Dispensação em Teto Máximo', formato: 'pct', thresholdKey: 'teto',
        metodologia: 'Percentual de dispensações onde a quantidade vendida atinge exatamente o limite máximo permitido por medicamento.' },
      { key: 'polimedicamento', label: '4+ Itens por Autorização', formato: 'pct', thresholdKey: 'default',
        metodologia: 'Percentual de autorizações (cupons fiscais) que contêm 4 ou mais medicamentos distintos dispensados no mesmo ato.' },
      { key: 'media_itens', label: 'Itens por Autorização', formato: 'dec', thresholdKey: 'default',
        metodologia: 'Quantidade média de itens dispensados por cupom fiscal (Total de Caixas / Total de Autorizações).' },
    ],
  },
  {
    id: 'financeiro',
    label: '4. Padrões Financeiros',
    indicators: [
      { key: 'ticket', label: 'Valor do Ticket Médio', formato: 'val', thresholdKey: 'default',
        metodologia: 'Valor monetário médio de cada autorização de venda.' },
      { key: 'receita_paciente', label: 'Faturamento Médio por Cliente', formato: 'val', thresholdKey: 'default',
        metodologia: 'Faturamento médio mensal da farmácia dividido pelo número de CPFs distintos atendidos (normalizado pelo tempo de atividade).' },
      { key: 'per_capita', label: 'Venda Per Capita Mensal', formato: 'val', thresholdKey: 'default',
        metodologia: 'Faturamento médio mensal da farmácia dividido pela população total do município (estimativa IBGE).' },
      { key: 'alto_custo', label: 'Medicamentos de Alto Custo', formato: 'pct', thresholdKey: 'alto_custo',
        metodologia: 'Percentual do faturamento total proveniente de medicamentos no 90º percentil de preço.' },
    ],
  },
  {
    id: 'automacao',
    label: '5. Automação & Geografia',
    indicators: [
      { key: 'vendas_rapidas', label: 'Vendas Rápidas (<60s)', formato: 'pct', thresholdKey: 'default',
        metodologia: 'Percentual de vendas consecutivas realizadas em intervalo inferior a 60 segundos.' },
      { key: 'volume_atipico', label: 'Volume Atípico', formato: 'dec', thresholdKey: 'default',
        metodologia: 'Mede explosões de crescimento semestral atípicas no faturamento do programa.' },
      { key: 'recorrencia_sistemica', label: 'Recorrência Sistêmica', formato: 'pct', thresholdKey: 'recorrencia_sistemica',
        metodologia: 'Percentual de compras sequenciais realizadas precisamente na linha de corte do sistema (ex: 30 dias exatos), indicando possível automação.' },
      { key: 'pico', label: 'Concentração em Dias de Pico', formato: 'pct', thresholdKey: 'pico',
        metodologia: 'Percentual do faturamento mensal concentrado nos 3 dias de maior movimento do mês.' },
      { key: 'geografico', label: 'Dispersão Geográfica Interestadual', formato: 'pct', thresholdKey: 'default',
        metodologia: 'Percentual de vendas para pacientes cuja UF de residência difere da UF da farmácia.' },
      { key: 'pacientes_unicos', label: 'Pacientes Únicos', formato: 'pct', thresholdKey: 'pacientes_unicos',
        metodologia: 'Proporção de CPFs que realizaram apenas uma única compra durante todo o período analisado (2015-2024).' },
    ],
  },
  {
    id: 'crm',
    label: '6. Integridade Médica',
    indicators: [
      { key: 'hhi_crm', label: 'Concentração de CRMs (HHI)', formato: 'dec', thresholdKey: 'default',
        metodologia: 'Índice Herfindahl-Hirschman (HHI) que mede a concentração de prescrições. HHI elevado indica dependência excessiva de poucos CRMs.' },
      { key: 'exclusividade_crm', label: 'Exclusividade de CRMs', formato: 'pct', thresholdKey: 'default',
        metodologia: 'Percentual de médicos que prescrevem EXCLUSIVAMENTE nesta farmácia em todo o Brasil.' },
      { key: 'crms_irregulares', label: 'Irregularidade de CRMs', formato: 'pct', thresholdKey: 'default',
        metodologia: 'Percentual do faturamento vinculado a CRMs inexistentes no CFM ou com prescrições anteriores à data de inscrição do médico.' },
    ],
  },
];
