export const FILTER_OPTIONS = {
  situacao: ['Todos', 'Ativa', 'Baixada', 'Suspensa', 'Inapta'],
  ms:       ['Todos', 'Ativa', 'Inativa'],
  porte:      ['Todos', 'Microempresa (ME)', 'Empresa de Pequeno Porte (EPP)', 'Demais'],
  grandeRede: ['Todos', 'Sim', 'Não'],
  parTeia: [
    { label: 'Todos', value: 'Todos' },
    { label: 'Alvo com PAR', value: 'alvo' },
    { label: 'Empresa N2 com PAR', value: 'n2' },
    { label: 'Empresa N4 com PAR', value: 'n4' },
    { label: 'Qualquer empresa da teia', value: 'qualquer' },
  ],
  cluster:  ['Todos', 'Cluster 0 - Risco Crítico', 'Cluster 1 - Risco Alto', 'Cluster 2 - Risco Médio', 'Cluster 3 - Risco Baixo'],
  rfa:      ['Todos', 'Acima de R$ 1 Mi', 'Entre R$ 500k e R$ 1 Mi', 'Até R$ 500k'],
};
