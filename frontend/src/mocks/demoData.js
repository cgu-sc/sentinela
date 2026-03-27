/**
 * Dados de Demonstração (Mockups) do Projeto Sentinela.
 * Estes dados são usados para preencher as telas enquanto os endpoints 
 * finais de investigação não estão 100% plugados ou para testes de UI.
 */

// 1. MÓDULO DE ALVOS (MAPA-CLUSTER)
export const CLUSTER_STATS_DEMO = [
  { uf: 'AL', c0: 1, c7: 1, total: 2 },
  { uf: 'DF', c1: 1, c5: 2, total: 3 },
  { uf: 'ES', c0: 1, total: 1 },
  { uf: 'GO', c0: 49, c1: 12, c2: 5, c3: 13, c4: 7, c5: 1, c6: 6, c7: 9, total: 102 }
];

export const TARGET_LIST_DEMO = [
  { uf: 'DF', municipio: 'Brasília', cnpj: '10286770000104', vendas: 'R$ 209.460,12', semComp: 'R$ 191.423,68', perc: '91,39%' },
  { uf: 'MG', municipio: 'Belo Horizonte', cnpj: '10429168000170', vendas: 'R$ 400.160,60', semComp: 'R$ 247.592,42', perc: '61,87%' },
  { uf: 'SP', municipio: 'Campo Limpo Paulista', cnpj: '10813567000130', vendas: 'R$ 1.067.415,83', semComp: 'R$ 15.673,56', perc: '1,47%' },
  { uf: 'GO', municipio: 'Aparecida de Goiânia', cnpj: '11200762000158', vendas: 'R$ 292.339,74', semComp: 'R$ 231.860,36', perc: '79,31%' }
];

// 2. MÓDULO DE SÓCIOS (REDE SOCIETÁRIA)
export const SOCIOS_DATA_DEMO = [
  { nome: 'JOAO SILVA', cpf: '***.123.456-**', cadunico: 'Não', mandado: 'Não', numSociedades: 3 },
  { nome: 'MARIA SANTOS', cpf: '***.789.012-**', cadunico: 'Sim', mandado: 'Não', numSociedades: 1 },
  { nome: 'JOSE OLIVEIRA', cpf: '***.345.678-**', cadunico: 'Não', mandado: 'Sim', numSociedades: 12 }
];

export const EMPRESAS_SOCIO_DEMO = [
  { cnpj: '10000180000156', uf: 'RJ', municipio: 'Cordeiro', situacao: 'ATIVADA' },
  { cnpj: '10135250000115', uf: 'SC', municipio: 'Ipumirim', situacao: 'BAIXADA' }
];
