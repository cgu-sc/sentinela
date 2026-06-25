export const SOCIO_BENEFICIO_FILTER_OPTIONS = [
  { label: 'Sem filtro', value: 'Todos' },
  { label: 'Sócio direto', value: 'direto' },
  { label: 'Sócio N3', value: 'n3' },
  { label: 'Sócio direto ou N3', value: 'direto_n3' },
];

export const SOCIO_ESOCIAL_FILTER_OPTIONS = [
  { label: 'Sem filtro', value: 'Todos' },
  { label: 'Sócio direto', value: 'direto' },
  { label: 'Sócio N3', value: 'n3' },
  { label: 'Sócio direto ou N3', value: 'direto_n3' },
];

export const FILTER_OPTIONS = {
  situacao: ['Todos', 'Ativa', 'Baixada', 'Suspensa', 'Inapta'],
  ms:       ['Todos', 'Ativa', 'Inativa'],
  porte:      ['Todos', 'Microempresa (ME)', 'Empresa de Pequeno Porte (EPP)', 'Demais'],
  grandeRede: ['Todos', 'Sim', 'Não'],
  parTeia: [
    { label: 'Sem filtro', value: 'Todos' },
    { label: 'CNPJ Nível 2 da Teia com PAR', value: 'n2' },
    { label: 'CNPJ Nível 4 da Teia com PAR', value: 'n4' },
    { label: 'Qualquer CNPJ com PAR', value: 'qualquer' },
  ],
  socioBeneficio: SOCIO_BENEFICIO_FILTER_OPTIONS,
  socioEsocial: SOCIO_ESOCIAL_FILTER_OPTIONS,
  cluster:  ['Todos', 'Cluster 0 - Risco Crítico', 'Cluster 1 - Risco Alto', 'Cluster 2 - Risco Médio', 'Cluster 3 - Risco Baixo'],
  rfa:      ['Todos', 'Acima de R$ 1 Mi', 'Entre R$ 500k e R$ 1 Mi', 'Até R$ 500k'],
};
