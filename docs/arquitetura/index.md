# Arquitetura do Sistema

Esta seção detalha a arquitetura técnica do Sistema Sentinela, incluindo as fontes de dados, estrutura de tabelas e fluxo de processamento.

## Navegação

<div class="grid cards" markdown>

- :material-database:{ .lg .middle } **Fontes de Dados**

  ***

  As duas tabelas transacionais principais: vendas do PFPB e aquisições por NF-e.

  [:octicons-arrow-right-24: Ver fontes](fontes-dados.md)

- :material-table:{ .lg .middle } **Tabelas de Apoio**

  ***

  Dicionário de medicamentos e outras tabelas auxiliares do sistema.

  [:octicons-arrow-right-24: Ver tabelas](tabelas-apoio.md)

- :material-database-cog:{ .lg .middle } **Estrutura de Tabelas**

  ***

  Detalhamento das tabelas de resultado criadas pelo sistema.

  [:octicons-arrow-right-24: Ver estrutura](estrutura-tabelas.md)

- :material-transit-connection-variant:{ .lg .middle } **Fluxo de Dados**

  ***

  Visão geral do pipeline de processamento de dados.

  [:octicons-arrow-right-24: Ver fluxo](fluxo-dados.md)

</div>

## Fases do Projeto

<div class="grid cards" markdown>

- :material-numeric-1-circle:{ .lg .middle } **Fase 1: Preparação**

  ***

  Estruturação das tabelas, particionamento e cálculo do estoque inicial.

  [:octicons-arrow-right-24: Detalhar](fase1-preparacao.md)

- :material-numeric-2-circle:{ .lg .middle } **Fase 2: Processamento**

  ***

  Simulação de fluxo de estoque e detecção de irregularidades.

  [:octicons-arrow-right-24: Detalhar](fase2-processamento.md)

- :material-numeric-3-circle:{ .lg .middle } **Fase 3: Relatórios**

  ***

  Geração de dossiês Excel e formatação dos resultados.

  [:octicons-arrow-right-24: Detalhar](fase3-relatorios.md)

- :material-numeric-4-circle:{ .lg .middle } **Fase 4: Análise Gerencial**

  ***

  Agregação de resultados e cálculo dos indicadores de risco.

  [:octicons-arrow-right-24: Detalhar](fase4-analise.md)

</div>

---

## Stack Tecnológico

### Camadas do Sistema

| Camada            | Tecnologia       | Função Principal                          |
| ----------------- | ---------------- | ----------------------------------------- |
| **Armazenamento** | SQL Server 2019+ | Persistência de dados e queries complexas |
| **Processamento** | Python 3.8+      | Lógica de negócio e geração de relatórios |
| **Apresentação**  | Excel + Power BI | Visualização e análise                    |

### Bibliotecas Python

| Biblioteca   | Versão | Função                                |
| ------------ | ------ | ------------------------------------- |
| `pyodbc`     | 5.1.0  | Conexão com SQL Server via ODBC       |
| `pandas`     | 2.2.2  | Manipulação de dados tabulares        |
| `XlsxWriter` | 3.2.0  | Geração de planilhas Excel formatadas |
| `tqdm`       | 4.66.4 | Barras de progresso no terminal       |
| `art`        | 6.1    | Arte ASCII para interface             |

### Dependências de Sistema

- Microsoft ODBC Driver 17 for SQL Server
- Acesso de rede à instância SQL Server
- Permissões de leitura/escrita nas bases de dados

---

## Princípios de Design

### 1. Processamento em Lotes

O sistema divide o universo de CNPJs em lotes de **50 CNPJs** por execução para:

- Evitar sobrecarga de memória
- Permitir interrupção e retomada
- Facilitar monitoramento de progresso

### 2. Recuperação de Falhas

O sistema implementa mecanismos de recuperação:

- Detecção automática de processamentos incompletos
- Limpeza de dados parciais antes de reprocessar
- Log detalhado de erros para diagnóstico

### 3. Otimização de Performance

Técnicas utilizadas para otimização:

- Índices dinâmicos nas tabelas de trabalho
- Cache em memória de tabelas de apoio
- Compressão Zlib da memória de cálculo

### 4. Rastreabilidade

Todas as operações são documentadas:

- Memória de cálculo completa para cada CNPJ
- Notas fiscais que compõem cada estoque
- Logs de execução com timestamps

---

!!! tip "Próximo Passo"
Explore as [Fontes de Dados](fontes-dados.md) para entender as tabelas transacionais centrais do sistema.
