export const GENERIC_INDICATOR_DETAIL_KEYS = [
  'falecidos',
  'percentual_nao_comprovacao',
  'teto',
];

export const INDICATOR_DETAIL_CONFIG = {
  falecidos: {
    title: 'Vendas p/ Falecidos',
    valueLabel: 'Percentual',
    valueFormat: 'pct3',
    financialLabel: 'Valor para falecidos',
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
    financialLabel: 'Valor em teto máximo',
  },
};
