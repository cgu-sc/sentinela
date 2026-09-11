/**
 * Textos explicativos da tabela de indicadores do detalhe de estabelecimento.
 *
 * O componente transforma esta estrutura em HTML para o PrimeVue Tooltip.
 * Manter o conteúdo separado da renderização evita duplicação e concentra a
 * metodologia exibida ao usuário em um único ponto de manutenção.
 */
export const INDICATOR_TABLE_TOOLTIP_COPY = {
  title: 'Como interpretar esta tabela',
  intro: 'Cada linha representa um indicador calculado para a farmácia selecionada no período analisado.',
  sections: [
    {
      label: 'Farmácia',
      text: 'Apresenta o resultado observado no estabelecimento. A unidade depende do indicador: percentual, valor em reais ou pontos de índice.',
    },
    {
      label: 'Medianas',
      text: 'Mediana Região é o valor central do mesmo indicador entre estabelecimentos da mesma região de saúde. Mediana UF usa estabelecimentos do mesmo estado. Mediana Nacional considera os estabelecimentos incluídos em todo o Brasil.',
    },
    {
      label: 'Riscos',
      text: 'Mostram quantas vezes o resultado da farmácia é maior ou menor que cada referência: região de saúde, UF e Brasil. São multiplicadores comparativos, não probabilidades.',
    },
    {
      label: 'Status',
      text: 'Consolida as regras do indicador em CRÍTICO, ATENÇÃO, NORMAL ou SEM DADOS. A classificação prioriza a região de saúde quando há base regional suficiente; caso contrário, utiliza a UF.',
    },
  ],
};

export const INDICATOR_COLUMN_TOOLTIP_COPY = {
  farmacia: {
    title: 'Farmácia',
    intro: 'Resultado efetivamente calculado para a farmácia selecionada no período de análise.',
    sections: [
      {
        label: 'Unidade do resultado',
        text: 'Percentuais são apresentados em %, indicadores financeiros em R$ e índices de concentração em pontos.',
      },
      {
        label: 'Exceção importante',
        text: 'Em Crescimento semestral atípico, o valor exibido é a soma dos aumentos financeiros classificados como atípicos, e não o percentual de crescimento.',
      },
    ],
  },
  medianaRegiao: {
    title: 'Mediana Região',
    intro: 'Valor central do mesmo indicador entre os estabelecimentos localizados na mesma região de saúde da farmácia.',
    sections: [
      {
        label: 'Como é obtida',
        text: 'Os resultados dos estabelecimentos da região de saúde são ordenados, e o valor central dessa distribuição é selecionado.',
      },
      {
        label: 'Como interpretar',
        text: 'Não é necessariamente uma média aritmética. Metade dos estabelecimentos possui resultado igual ou inferior, e a outra metade possui resultado igual ou superior.',
      },
    ],
  },
  medianaUf: {
    title: 'Mediana UF',
    intro: 'Valor central do mesmo indicador entre os estabelecimentos localizados no mesmo estado da federação.',
    sections: [
      {
        label: 'Base de comparação',
        text: 'Utiliza o mesmo período e universo de dados da análise, agrupando os estabelecimentos pela UF.',
      },
      {
        label: 'Objetivo',
        text: 'Permite identificar se o resultado da farmácia está acima ou abaixo do padrão observado no estado.',
      },
    ],
  },
  medianaNacional: {
    title: 'Mediana Nacional',
    intro: 'Valor central do mesmo indicador entre os estabelecimentos incluídos na análise em todo o Brasil.',
    sections: [
      {
        label: 'Objetivo',
        text: 'Oferece a referência mais ampla da tabela para contextualizar o resultado da farmácia no cenário nacional.',
      },
      {
        label: 'Importante',
        text: 'A mediana nacional utiliza o universo de estabelecimentos válido para o período e os filtros considerados no cálculo.',
      },
    ],
  },
  riscoRegiao: {
    title: 'Risco Região',
    intro: 'Compara o resultado da farmácia com a mediana dos estabelecimentos da mesma região de saúde.',
    sections: [
      {
        label: 'Cálculo',
        formula: 'Resultado da farmácia ÷ Mediana da Região',
      },
      {
        label: 'Como interpretar',
        text: '1,0x significa resultado igual à mediana regional; 2,0x significa resultado duas vezes maior; 0,5x significa metade da mediana.',
      },
      {
        label: 'Importante',
        text: 'É um multiplicador comparativo, não uma probabilidade de irregularidade e não determina sozinho o status.',
      },
    ],
  },
  riscoUf: {
    title: 'Risco UF',
    intro: 'Compara o resultado da farmácia com a mediana dos estabelecimentos do mesmo estado.',
    sections: [
      {
        label: 'Cálculo',
        formula: 'Resultado da farmácia ÷ Mediana da UF',
      },
      {
        label: 'Como interpretar',
        text: 'O multiplicador mostra quantas vezes o resultado da farmácia é maior ou menor que o padrão observado na UF.',
      },
    ],
  },
  riscoNacional: {
    title: 'Risco Nacional',
    intro: 'Compara o resultado da farmácia com a mediana dos estabelecimentos incluídos na análise em todo o Brasil.',
    sections: [
      {
        label: 'Cálculo',
        formula: 'Resultado da farmácia ÷ Mediana Nacional',
      },
      {
        label: 'Como interpretar',
        text: 'O multiplicador mostra como o estabelecimento se posiciona em relação ao comportamento nacional do indicador.',
      },
    ],
  },
  status: {
    title: 'Status do indicador',
    intro: 'Classificação consolidada conforme as regras de atenção e criticidade definidas para cada indicador.',
    sections: [
      {
        label: 'CRÍTICO',
        text: 'Pelo menos uma regra de criticidade foi atingida.',
      },
      {
        label: 'ATENÇÃO',
        text: 'Uma regra de atenção foi atingida, sem ocorrência de criticidade.',
      },
      {
        label: 'NORMAL',
        text: 'Nenhuma regra de atenção ou criticidade foi atingida.',
      },
      {
        label: 'SEM DADOS',
        text: 'Não existe valor válido disponível para o indicador.',
      },
      {
        label: 'Referência utilizada',
        text: 'Quando existe base regional suficiente, a classificação comparativa prioriza a região de saúde. Caso contrário, utiliza a UF. A referência nacional não determina sozinha o status.',
      },
    ],
  },
};

export const INDICATOR_TOOLTIP_COPY = {
  percentual_nao_comprovacao: {
    title: 'Percentual de Não Comprovação',
    intro: 'Mede a parcela do valor comercializado pela farmácia que não possui comprovação válida no escopo auditado.',
    sections: [
      { label: 'Como funciona', text: 'O sistema soma o valor das vendas sem comprovação e compara esse montante com o valor total comercializado.' },
      { label: 'Cálculo', formula: 'Valor não comprovado ÷ Valor total comercializado × 100' },
    ],
    financialMeaning: 'valor das vendas sem comprovação considerado no cálculo do indicador',
  },
  falecidos: {
    title: 'Vendas para Falecidos',
    intro: 'Mede o percentual do valor de vendas associado a dispensações realizadas após a data oficial de óbito do beneficiário.',
    sections: [
      { label: 'Como funciona', text: 'A data de cada dispensação é comparada com a data de óbito registrada nas bases oficiais utilizadas pelo sistema, como SIM, SIRC e SISOBI.' },
      { label: 'Cálculo', formula: 'Valor das vendas após o óbito ÷ Valor total monitorado × 100' },
    ],
    financialMeaning: 'valor das vendas identificadas após a data oficial de óbito',
  },
  incompatibilidade_patologica: {
    title: 'Incompatibilidade Patológica',
    intro: 'Mede o percentual do valor monitorado associado a situações de incompatibilidade entre a indicação terapêutica e o perfil do beneficiário.',
    sections: [
      { label: 'Como funciona', text: 'O sistema aplica regras que relacionam medicamento, idade e sexo do beneficiário.' },
      {
        label: 'Regras consideradas',
        items: [
          'Osteoporose dispensada para beneficiário do sexo masculino.',
          'Parkinson para pessoa com menos de 50 anos.',
          'Hipertensão para pessoa com menos de 20 anos.',
          'Diabetes para pessoa com menos de 20 anos.',
        ],
      },
      { label: 'Cálculo', formula: 'Valor das vendas suspeitas ÷ Valor das vendas monitoradas × 100' },
    ],
    financialMeaning: 'valor das vendas enquadradas nas regras de incompatibilidade patológica',
  },
  teto: {
    title: 'Dispensação em Teto Máximo',
    intro: 'Mede o percentual do valor das dispensações em que a quantidade autorizada atinge ou ultrapassa o limite máximo permitido para o medicamento.',
    sections: [
      { label: 'Como funciona', text: 'A quantidade dispensada é comparada com a quantidade máxima definida pelas regras de posologia e pelo período de bloqueio do medicamento.' },
      { label: 'Regra aplicada', formula: 'Quantidade autorizada ≥ Quantidade máxima permitida' },
      { label: 'Cálculo', formula: 'Valor das dispensações no teto ou acima dele ÷ Valor total × 100' },
    ],
    financialMeaning: 'valor das dispensações que atingiram ou ultrapassaram o teto permitido',
  },
  polimedicamento: {
    title: '4+ Itens por Autorização',
    intro: 'Mede o percentual do valor associado a autorizações que contêm quatro ou mais medicamentos distintos no mesmo ato de dispensação.',
    sections: [
      { label: 'Como funciona', text: 'Os itens são agrupados por autorização e o sistema conta quantos medicamentos diferentes foram registrados em cada operação.' },
      { label: 'Cálculo', formula: 'Valor das autorizações com 4 ou mais itens ÷ Faturamento total × 100' },
    ],
    financialMeaning: 'valor das autorizações que continham quatro ou mais medicamentos distintos',
  },
  ticket_medio: {
    title: 'Valor do Ticket Médio',
    intro: 'Mede o valor monetário médio de cada autorização ou operação de dispensação realizada pela farmácia.',
    sections: [
      { label: 'Como funciona', text: 'O faturamento total é dividido pela quantidade total de autorizações registradas no período.' },
      { label: 'Cálculo', formula: 'Faturamento total ÷ Número de autorizações' },
    ],
    financialMeaning: 'faturamento total utilizado para calcular o valor médio por autorização',
  },
  receita_paciente: {
    title: 'Faturamento Médio por Cliente',
    intro: 'Mede o valor médio de faturamento associado aos pacientes atendidos pela farmácia durante o período analisado.',
    sections: [
      { label: 'Como funciona', text: 'O faturamento é relacionado à quantidade de pacientes distintos observados e ao tempo de atividade considerado no cálculo.' },
      { label: 'Cálculo metodológico', formula: 'Faturamento total ÷ Clientes/mês ativos' },
      { label: 'Como interpretar', text: 'A normalização pelo período de atividade permite comparar estabelecimentos observados por diferentes quantidades de meses.' },
    ],
    financialMeaning: 'faturamento total relacionado à base de clientes utilizada no cálculo',
  },
  per_capita: {
    title: 'Venda Per Capita Mensal',
    intro: 'Mede o faturamento médio mensal da farmácia em relação à população do município onde ela está localizada.',
    sections: [
      { label: 'Como funciona', text: 'O faturamento total é dividido pela população municipal de referência e pela quantidade de meses ativos do estabelecimento.' },
      { label: 'Cálculo', formula: 'Faturamento total ÷ (População do município × Meses ativos)' },
      { label: 'Fonte populacional', text: 'Utiliza a estimativa populacional de referência disponível na base do IBGE.' },
    ],
    financialMeaning: 'faturamento total utilizado para calcular a venda mensal por habitante',
  },
  alto_custo: {
    title: 'Medicamentos de Alto Custo',
    intro: 'Mede o percentual do faturamento associado a medicamentos com preço situado na faixa superior da distribuição regional de preços.',
    sections: [
      { label: 'Como funciona', text: 'Para cada medicamento, o preço é comparado com a distribuição regional de preços do ano de referência.' },
      { label: 'Regra aplicada', text: 'São classificados como de alto custo os medicamentos cujo preço seja igual ou superior ao percentil 90 da distribuição regional correspondente.' },
      { label: 'Cálculo', formula: 'Valor dos medicamentos de alto custo ÷ Faturamento total × 100' },
    ],
    financialMeaning: 'valor dos medicamentos cujo preço atingiu o percentil regional de alto custo',
  },
  vendas_rapidas: {
    title: 'Vendas Rápidas (<60s)',
    intro: 'Mede o percentual do valor associado a vendas consecutivas realizadas em intervalos inferiores a 60 segundos.',
    sections: [
      { label: 'Como funciona', text: 'As transações são ordenadas por horário e o intervalo entre operações consecutivas é calculado.' },
      { label: 'Regra aplicada', formula: 'Intervalo entre vendas consecutivas < 60 segundos' },
      { label: 'Cálculo', formula: 'Valor das vendas rápidas ÷ Faturamento total × 100' },
    ],
    financialMeaning: 'valor das vendas consecutivas realizadas em intervalos inferiores a 60 segundos',
  },
  volume_atipico: {
    title: 'Crescimento Semestral Atípico',
    intro: 'Identifica aumentos financeiros considerados atípicos na comparação entre semestres consecutivos com dados suficientes.',
    sections: [
      { label: 'Como funciona', text: 'Cada semestre válido é comparado com o semestre anterior. A regra exige crescimento superior a 50% e aumento financeiro acima do limite mínimo configurado.' },
      { label: 'Regra padrão atual', text: 'A matriz utiliza aumento mínimo de R$ 10.000 como referência padrão, sujeito à configuração vigente do sistema.' },
      { label: 'Valor exibido', text: 'Na coluna Farmácia, o resultado é a soma dos aumentos financeiros classificados como atípicos, e não o percentual de crescimento.' },
    ],
    financialMeaning: 'soma dos aumentos financeiros classificados como atípicos',
  },
  recorrencia_sistemica: {
    title: 'Recorrência Sistêmica',
    intro: 'Mede o percentual do valor associado a compras recorrentes realizadas exatamente no intervalo de renovação definido pelo sistema.',
    sections: [
      { label: 'Como funciona', text: 'O intervalo entre compras sucessivas é comparado com o período de bloqueio ou renovação previsto para o medicamento.' },
      { label: 'Regra aplicada', text: 'Compras que se repetem exatamente no limite definido pelo sistema são classificadas como recorrências sistêmicas.' },
      { label: 'Cálculo', formula: 'Valor das recorrências sistêmicas ÷ Valor total das renovações × 100' },
    ],
    financialMeaning: 'valor das compras recorrentes realizadas exatamente no intervalo de renovação do sistema',
  },
  dias_pico: {
    title: 'Concentração em Dias de Pico',
    intro: 'Mede o percentual do faturamento mensal concentrado nos três dias de maior movimentação financeira de cada mês.',
    sections: [
      { label: 'Como funciona', text: 'Em cada mês, o sistema identifica os três dias com maior valor de vendas e compara esse montante com o faturamento mensal.' },
      { label: 'Cálculo mensal', formula: 'Valor dos três dias de maior movimento ÷ Faturamento mensal × 100' },
      { label: 'Consolidação', text: 'O resultado consolidado utiliza a mediana das concentrações mensais válidas.' },
    ],
    financialMeaning: 'valor das vendas realizadas nos três dias de maior movimento dos meses considerados',
  },
  dispersao_geografica: {
    title: 'Dispersão Interestadual',
    intro: 'Mede o percentual do valor de vendas destinado a beneficiários que residem em uma UF diferente daquela da farmácia.',
    sections: [
      { label: 'Como funciona', text: 'A UF de residência do beneficiário é comparada com a UF do estabelecimento. Quando são diferentes, o valor da venda é classificado como interestadual.' },
      { label: 'Cálculo', formula: 'Valor das vendas interestaduais ÷ Valor total de vendas × 100' },
    ],
    financialMeaning: 'valor das vendas destinadas a beneficiários residentes em outra UF',
  },
  hhi_crm: {
    title: 'Concentração de CRMs — HHI',
    intro: 'Mede o grau de concentração financeira das prescrições entre os médicos identificados por seus respectivos CRMs.',
    sections: [
      { label: 'Como funciona', text: 'O sistema calcula a participação financeira de cada CRM no valor total prescrito, eleva cada participação ao quadrado e soma os resultados.' },
      { label: 'Cálculo', formula: 'HHI = Σ (participação financeira de cada CRM em %)²' },
      { label: 'Como interpretar', text: 'Quanto maior o HHI, maior a concentração das prescrições em poucos profissionais e maior a dependência financeira de um grupo restrito de CRMs.' },
    ],
    financialMeaning: 'valor financeiro total utilizado para medir a participação relativa dos CRMs',
  },
  crms_irregulares: {
    title: 'Faturamento de CRMs Irregulares',
    intro: 'Mede o percentual do valor prescrito associado a CRMs classificados como irregulares nas bases de validação profissional.',
    sections: [
      {
        label: 'Regras consideradas',
        items: [
          'CRM não localizado no cadastro do CFM para a UF correspondente.',
          'Prescrição realizada antes da primeira inscrição ou registro daquele CRM na UF.',
        ],
      },
      { label: 'Como funciona', text: 'Quando a situação irregular é identificada para determinado CRM e período, o valor anual associado às prescrições desse profissional é considerado no indicador.' },
      { label: 'Cálculo', formula: 'Valor prescrito por CRMs irregulares ÷ Valor total prescrito × 100' },
    ],
    financialMeaning: 'valor prescrito associado aos CRMs classificados como irregulares',
  },
};
