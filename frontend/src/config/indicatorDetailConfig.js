export const GENERIC_INDICATOR_DETAIL_KEYS = [
  'falecidos',
  'percentual_nao_comprovacao',
  'teto',
  'polimedicamento',
  'ticket_medio',
  'receita_paciente',
  'per_capita',
  'alto_custo',
  'vendas_rapidas',
  'volume_atipico',
  'recorrencia_sistemica',
  'dias_pico',
  'hhi_crm',
  'crms_irregulares',
];

export const INDICATOR_DETAIL_CONFIG = {
  falecidos: {
    title: 'Vendas p/ Falecidos',
    valueLabel: 'Percentual',
    valueFormat: 'pct3',
    financialLabel: 'Valor para falecidos',
  },
  incompatibilidade_patologica: {
    title: 'Incompatibilidade Patológica',
    valueLabel: 'Percentual',
    valueFormat: 'pct',
    financialLabel: 'Valor suspeito',
  },
  percentual_nao_comprovacao: {
    title: 'Percentual Não Comprovação',
    valueLabel: 'Percentual',
    valueFormat: 'pct',
    financialLabel: 'Valor sem comprovação',
  },
  teto: {
    title: 'Dispensação em Teto Máximo',
    valueLabel: 'Percentual',
    valueFormat: 'pct',
  },
  polimedicamento: {
    title: '4+ Itens por Autorização',
    valueLabel: 'Percentual',
    valueFormat: 'pct',
  },
  ticket_medio: {
    title: 'Valor do Ticket Médio',
    valueLabel: 'Ticket médio',
    valueFormat: 'val',
  },
  receita_paciente: {
    title: 'Faturamento Médio por Cliente',
    valueLabel: 'Valor',
    valueFormat: 'val',
  },
  per_capita: {
    title: 'Venda Per Capita Mensal',
    valueLabel: 'Valor',
    valueFormat: 'val',
  },
  alto_custo: {
    title: 'Medicamentos de Alto Custo',
    valueLabel: 'Percentual',
    valueFormat: 'pct',
  },
  vendas_rapidas: {
    title: 'Vendas Rápidas (<60s)',
    valueLabel: 'Percentual',
    valueFormat: 'pct',
  },
  volume_atipico: {
    title: 'Aumento atípico de vendas',
    valueLabel: 'Índice',
    valueFormat: 'dec',
  },
  recorrencia_sistemica: {
    title: 'Recorrência Sistêmica',
    valueLabel: 'Percentual',
    valueFormat: 'pct',
  },
  dias_pico: {
    title: 'Concentração em Dias de Pico',
    valueLabel: 'Percentual',
    valueFormat: 'pct',
  },
  hhi_crm: {
    title: 'Concentração de CRMs (HHI)',
    valueLabel: 'HHI',
    valueFormat: 'dec',
  },
  crms_irregulares: {
    title: 'Faturamento CRMs Irregulares',
    valueLabel: 'Percentual',
    valueFormat: 'pct',
  },
};
