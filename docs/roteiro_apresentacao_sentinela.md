# Roteiro de Apresentacao do Sentinela

## Preparacao

- **Data:** preencher
- **Duracao prevista:** preencher
- **Publico:** preencher
- **Objetivo principal:** demonstrar como o Sentinela transforma um grande volume de dados do PFPB em prioridades de auditoria e evidencias para aprofundamento.
- **Municipio de exemplo:** preencher
- **CNPJ de exemplo:** preencher
- **Indicador de exemplo:** preencher
- **Alvo de exemplo:** Parkinson em menores de 50 anos

## Mensagem Central

O Sentinela e uma ferramenta de apoio a auditoria. Ele organiza dados cadastrais, financeiros, territoriais, clinicos e relacionais para identificar concentracoes, comportamentos atipicos e situacoes que merecem aprofundamento.

O sistema nao declara sozinho que houve irregularidade. Ele reduz o universo de analise, prioriza riscos e facilita o acesso as evidencias.

## Linha Narrativa

> Partimos de uma visao executiva do programa, identificamos concentracoes territoriais, chegamos ao estabelecimento, analisamos os sinais de risco e abrimos as evidencias que sustentam uma investigacao.

Fluxo sugerido:

1. Home: dimensao, cobertura e visao executiva.
2. Municipios: priorizacao territorial.
3. Estabelecimentos: priorizacao de farmacias.
4. Detalhe do CNPJ: leitura integrada do estabelecimento.
5. Indicadores: sinais de risco especializados.
6. Alvos: recortes investigativos objetivos.
7. Evidencias e Nota Tecnica: materializacao do trabalho de auditoria.

---

## 1. Abertura

### Fala sugerida

> Vou apresentar o Sentinela a partir do caminho que um auditor poderia percorrer. Primeiro veremos o universo monitorado. Depois, vamos reduzir esse universo ate chegar a um estabelecimento e as evidencias que justificam seu aprofundamento.

### Cuidados

- Evitar comecar explicando arquitetura ou tecnologia.
- Evitar percorrer menus sem uma pergunta investigativa.
- Diferenciar sempre sinal de risco, evidencia e conclusao de auditoria.

---

## 2. Home

**Rota:** `http://localhost:5173/`

### Objetivo

Apresentar a dimensao do sistema e construir o contexto para a analise.

### 2.1 Status operacional

Mostrar:

- situacao geral do sistema;
- integridade dos modulos carregados;
- data da ultima sincronizacao, quando pertinente.

Fala sugerida:

> Antes da analise, o sistema informa a disponibilidade dos modulos e das bases carregadas. Isso permite verificar se o ambiente esta pronto e quais fontes sustentam a consulta.

Nao aprofundar:

- detalhes de cache;
- nomes de arquivos;
- processo interno de sincronizacao, salvo pergunta do publico.

### 2.2 Escopo da analise

Mostrar:

- quantidade de CNPJs;
- municipios;
- UFs;
- periodo selecionado.

Fala sugerida:

> Aqui temos a dimensao do universo monitorado. O desafio nao e apenas encontrar informacao, mas priorizar onde o olhar da auditoria produz mais resultado.

### 2.3 Movimentacao financeira

Mostrar:

- valor movimentado;
- valor sem comprovacao;
- percentual sem comprovacao.

Fala sugerida:

> A movimentacao financeira dimensiona a materialidade. O valor sem comprovacao e um dos sinais de auditoria, mas ele sera combinado com contexto territorial, temporal e outros indicadores.

### 2.4 Producao semestral

Pergunta que o grafico responde:

> Como a movimentacao evoluiu ao longo do tempo?

Destacar:

- crescimento ou reducao entre periodos;
- mudancas abruptas;
- importancia de analisar tendencia, nao apenas fotografia atual.

### 2.5 Mapa do Brasil

Pergunta que o mapa responde:

> Onde os resultados estao concentrados?

Destacar:

- distribuicao territorial;
- possibilidade de navegacao do Brasil para UF, regiao e municipio;
- uso de IDs territoriais para manter consistencia da analise.

### 2.6 UFs com maior risco

Pergunta que o grafico responde:

> Quais UFs concentram os resultados mais relevantes para priorizacao?

Evitar afirmar que a primeira UF do ranking possui fraude. O ranking representa prioridade analitica dentro dos criterios exibidos.

### 2.7 Distribuicao por risco

Pergunta que o grafico responde:

> Como o universo esta distribuido entre as diferentes faixas de risco?

Fala sugerida:

> O objetivo e transformar um universo amplo em grupos de prioridade. Isso permite organizar o trabalho e aprofundar primeiro os casos de maior criticidade.

### Transicao

Utilizar o botao **Iniciar analise**.

> Agora que entendemos o universo e sua distribuicao, vamos iniciar o aprofundamento territorial.

---

## 3. Municipios

**Rota:** `http://localhost:5173/municipios`

### Objetivo

Mostrar como o sistema reduz o universo nacional para territorios prioritarios.

### Demonstracao

1. Apresentar o mapa nacional.
2. Selecionar uma UF.
3. Selecionar um municipio previamente testado.
4. Mostrar a regiao de saude.
5. Observar a atualizacao suave do Ranking municipal.
6. Usar os botoes de retorno para UF e Brasil.

### Fala sugerida

> O mapa e o ranking trabalham juntos. A navegacao territorial altera o recorte da analise, enquanto a tabela permite comparar materialidade, participacao e criticidade.

### Transicao

> Identificado um territorio prioritario, o proximo passo e descobrir quais estabelecimentos explicam esse resultado.

---

## 4. Estabelecimentos

**Rota:** `http://localhost:5173/estabelecimentos`

### Objetivo

Priorizar farmacias a partir de indicadores de risco e contexto regional.

### Demonstracao

1. Mostrar os KPIs gerais.
2. Selecionar um indicador.
3. Navegar no mapa ate o municipio escolhido.
4. Apresentar a tabela **Farmacias por Indicador**.
5. Explicar o benchmark regional.
6. Mostrar o destaque de valores financeiros elevados.
7. Abrir o CNPJ preparado para a demonstracao.

### Fala sugerida

> Neste ponto deixamos de olhar apenas o territorio e passamos a comparar estabelecimentos. A farmacia e analisada em relacao ao seu proprio comportamento e ao contexto regional.

### Conceitos importantes

- **Critico:** prioridade elevada segundo o criterio do indicador.
- **Atencao:** comportamento que merece acompanhamento.
- **Normal:** dentro dos parametros definidos.
- **Benchmark:** referencia de comparacao, nao prova isolada de irregularidade.

---

## 5. Detalhe do Estabelecimento

**Rota:** `http://localhost:5173/estabelecimentos/{cnpj}`

### Objetivo

Demonstrar que a priorizacao pode ser aprofundada em diferentes dimensoes sem perder o contexto do estabelecimento.

### Sequencia sugerida

1. **Evolucao financeira**
   - tendencia de movimentacao;
   - alteracoes entre periodos;
   - GTINs mais relevantes.

2. **Diagnostico e indicadores**
   - criticidades encontradas;
   - comparacao com referencias;
   - memoria dos criterios usados.

3. **Memoria de calculo**
   - rastreabilidade do resultado;
   - possibilidade de sair do agregado e chegar aos itens.

4. **CRMs**
   - concentracao de prescritores;
   - perfis diario e horario;
   - transacoes de periodos especificos.

5. **Falecidos**
   - vendas associadas a CPFs com registro de obito;
   - linha do tempo;
   - necessidade de verificacao documental.

6. **Socios e teia societaria**
   - relacionamentos diretos e indiretos;
   - empresas relacionadas;
   - alertas cadastrais.

7. **Contexto regional**
   - posicao do estabelecimento perante seus pares;
   - participacao e percentis.

### Fala sugerida

> O detalhe do CNPJ funciona como um dossie analitico. Cada aba responde a uma pergunta diferente, mas todas preservam a identificacao do estabelecimento e o periodo analisado.

---

## 6. Indicadores

### Objetivo

Explicar que o sistema possui diferentes lentes de risco.

### Grupos que podem ser citados

- auditoria e comprovacao;
- elegibilidade e consistencia clinica;
- quantidade e dispensacao;
- financeiro;
- automacao e geografia;
- integridade medica.

### Fala sugerida

> Um estabelecimento pode nao se destacar em um indicador e, ainda assim, apresentar criticidade em outro. Por isso, a avaliacao e multidimensional.

Escolher apenas um ou dois indicadores para demonstracao. Nao percorrer todos.

---

## 7. Alvos Investigativos

**Rota:** `http://localhost:5173/alvos?tipo=parkinson_menor_50`

### Objetivo

Mostrar um recorte investigativo com regra clara e evidencia detalhavel.

### Demonstracao

1. Apresentar os KPIs do alvo.
2. Explicar o recorte de Parkinson em menores de 50 anos.
3. Navegar do Brasil para UF, regiao e municipio.
4. Mostrar CPFs unicos observados e esperados.
5. Explicar a razao observado/esperado.
6. Mostrar o valor dos CPFs abaixo de 50 anos.
7. Destacar valores iguais ou superiores ao limiar financeiro configurado.
8. Abrir **Vendas com incompatibilidade clinica/patologica**.

### Fala sugerida

> O alvo nao parte de uma classificacao generica. Ele aplica uma regra investigativa objetiva e apresenta onde os casos e valores se concentram.

### Cuidado metodologico

- O resultado indica incompatibilidade com a regra monitorada.
- O dado deve orientar verificacao e aprofundamento.
- Nao usar a expressao "fraude comprovada" com base apenas no alvo.

---

## 8. Nota Tecnica

### Objetivo

Mostrar como o sistema ajuda a transformar a exploracao analitica em produto de auditoria.

### Fala sugerida

> Depois da exploracao, o Sentinela consolida informacoes cadastrais, financeiras, comparativas e criticidades em uma nota tecnica. O documento apoia o registro e a comunicacao dos achados, preservando a necessidade de revisao profissional.

Destacar:

- rastreabilidade;
- padronizacao;
- economia de tempo;
- necessidade de revisao pelo responsavel.

---

## 9. Encerramento

### Sintese sugerida

> O Sentinela conecta tres capacidades: visao ampla do programa, priorizacao orientada por risco e aprofundamento ate a evidencia. Ele nao substitui a auditoria. Ele permite que a auditoria concentre tempo e conhecimento onde existem sinais mais relevantes.

### Beneficios

- reducao do universo de analise;
- comparacao territorial e regional;
- integracao de diferentes dimensoes de risco;
- rastreabilidade dos calculos;
- acesso rapido aos detalhes;
- apoio a elaboracao de produtos de auditoria.

### Proximos passos

- inclusao de novos alvos;
- evolucao dos indicadores;
- melhoria continua dos benchmarks;
- ampliacao das fontes e da automacao documental.

---

## Perguntas Provaveis

### O sistema comprova fraude?

Nao. Ele identifica sinais, incompatibilidades e prioridades que devem ser aprofundados.

### Como os limites de risco sao definidos?

Por configuracoes e metodologias especificas de cada indicador. Quando aplicavel, os resultados tambem sao comparados com referencias territoriais.

### Os dados sao atualizados em tempo real?

Explicar a periodicidade real de sincronizacao utilizada no ambiente da apresentacao.

### E possivel chegar aos registros que formaram o indicador?

Sim, nos modulos que possuem detalhamento e memoria de calculo.

### O sistema substitui a analise do auditor?

Nao. Ele organiza, prioriza e apresenta evidencias para apoiar a decisao profissional.

---

## Checklist para o Microsoft Teams

### Ambiente

- [ ] Backend em `http://127.0.0.1:8002`.
- [ ] Frontend em `http://localhost:5173`.
- [ ] Endpoint de saude respondendo.
- [ ] Cache carregado e sem modulos obrigatorios ausentes.
- [ ] Home aberta e graficos renderizados.
- [ ] Municipio de exemplo testado.
- [ ] CNPJ de exemplo testado.
- [ ] Indicador de exemplo testado.
- [ ] Alvo Parkinson testado.
- [ ] Modal de incompatibilidade testado.
- [ ] Nota Tecnica testada, caso seja demonstrada.

### Teams e computador

- [ ] Desativar notificacoes do Windows, e-mail e aplicativos.
- [ ] Fechar abas e janelas sem relacao com a apresentacao.
- [ ] Usar zoom do navegador que permita leitura no compartilhamento.
- [ ] Compartilhar somente a janela do navegador, quando adequado.
- [ ] Manter o roteiro aberto em outro monitor ou dispositivo.
- [ ] Deixar os links importantes abertos em abas.
- [ ] Evitar atualizacoes de sistema durante a reuniao.
- [ ] Ter agua por perto e reservar alguns segundos entre os modulos.

### Abas sugeridas

1. Home.
2. Municipios.
3. Estabelecimentos.
4. CNPJ escolhido.
5. Alvos.

---

## Plano de Contingencia

Se a aplicacao ou a rede falhar:

1. Manter capturas das telas principais.
2. Ter os numeros essenciais anotados.
3. Continuar a narrativa usando as imagens.
4. Explicar a navegacao prevista sem tentar corrigir o ambiente durante muito tempo.

Capturas recomendadas:

- Home completa;
- Home com os quatro graficos;
- mapa municipal no recorte escolhido;
- ranking de estabelecimentos;
- detalhe do CNPJ;
- indicador selecionado;
- alvo Parkinson;
- modal de incompatibilidade;
- trecho da Nota Tecnica.

---

## Controle de Tempo

| Bloco | Tempo |
|---|---:|
| Abertura e objetivo | 2 min |
| Home | 5 min |
| Municipios | 4 min |
| Estabelecimentos | 5 min |
| Detalhe do CNPJ | 8 min |
| Indicadores | 4 min |
| Alvos | 5 min |
| Nota Tecnica e encerramento | 4 min |
| Perguntas | restante |

Para uma apresentacao curta, priorizar:

1. Home.
2. Municipios.
3. Estabelecimento.
4. Alvo Parkinson.
5. Encerramento.
