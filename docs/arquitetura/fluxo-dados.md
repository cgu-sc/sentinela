# Fluxo de Dados

Este documento apresenta uma visão integrada de como os dados fluem através do Sistema Sentinela, desde a entrada até a geração dos produtos finais.

---

## 1. Visão Geral do Pipeline

```mermaid
flowchart TB
    subgraph entrada[" 📥 ENTRADA"]
        direction LR
        MS[(Ministério da Saúde<br/>Vendas PFPB)]
        RFB[(Receita Federal<br/>NF-e)]
        CFM[(CFM<br/>Médicos)]
        IBGE[(IBGE<br/>Demografia)]
        SIM[(SIM/SIRC<br/>Óbitos)]
    end

    subgraph etl[" ⚙️ ETL - Preparação"]
        direction TB
        E1[Extração<br/>Seleção do período]
        E2[Transformação<br/>Limpeza e normalização]
        E3[Carga<br/>Tabelas de trabalho]
    end

    subgraph proc[" 🔄 PROCESSAMENTO"]
        direction TB
        P1[Particionamento<br/>100 lotes]
        P2[Simulação<br/>Fluxo de estoque]
        P3[Detecção<br/>Irregularidades]
        P4[Indicadores<br/>17 métricas]
    end

    subgraph saida[" 📤 SAÍDA"]
        direction LR
        S1[📑 Dossiês Excel]
        S2[📊 Matriz de Risco]
        S3[📈 Painel BI]
        S4[📋 Tabela Consolidada]
    end

    entrada --> etl
    etl --> proc
    proc --> saida
```

---

## 2. Fluxo Detalhado por Fase

### 2.1. Fase 1: Preparação (SQL)

```mermaid
flowchart LR
    subgraph Entrada
        A1[relatorio_movimentacao<br/>2015_2024]
        A2[aquisicoesFazenda<br/>2015_2025]
    end

    subgraph Processamento
        B1[Filtro por período]
        B2[Extração de CNPJs únicos]
        B3[Particionamento NTILE]
        B4[Consolidação cadastral]
        B5[Cálculo estoque inicial]
    end

    subgraph Saida
        C1[lista_cnpjs]
        C2[classif]
        C3[dadosFarmaciasFP]
        C4[estoque_inicialFP]
    end

    A1 --> B1 --> B2 --> C1
    C1 --> B3 --> C2
    A1 --> B4 --> C3
    A2 --> B5 --> C4
```

### 2.2. Fase 2: Processamento (Python)

```mermaid
flowchart TB
    subgraph Entrada
        A1[classif<br/>Lotes de CNPJs]
        A2[procPreparaDados<br/>Stored Procedure]
        A3[movimentacaoFP<br/>Trabalho]
    end

    subgraph Loop["Para cada CNPJ"]
        B1[Query Unificada<br/>Vendas + Aquisições]
        B2[Simulação<br/>Linha a linha]
        B3[Detecção<br/>Estoque negativo]
        B4[Persistência<br/>Banco de dados]
    end

    subgraph Saida
        C1[processamentosFP]
        C2[movimentacaoMensalFP]
        C3[memoria_calculoFP]
    end

    A1 --> A2 --> A3
    A3 --> B1 --> B2 --> B3 --> B4
    B4 --> C1
    B4 --> C2
    B4 --> C3
```

### 2.3. Fase 3: Relatórios (Python)

```mermaid
flowchart LR
    subgraph Entrada
        A1[memoria_calculoFP<br/>JSON comprimido]
        A2[Matriz_Risco_Final<br/>Indicadores]
        A3[indicadorCRM<br/>Prescritores]
    end

    subgraph Processamento
        B1[Descompressão]
        B2[Formatação]
        B3[Geração abas]
    end

    subgraph Saida
        C1[📑 Excel<br/>4 abas]
    end

    A1 --> B1 --> B2
    A2 --> B2
    A3 --> B2
    B2 --> B3 --> C1
```

### 2.4. Fase 4: Análise Gerencial (SQL)

```mermaid
flowchart TB
    subgraph Entrada
        A1[movimentacaoMensalFP]
        A2[Tabelas auxiliares]
    end

    subgraph Indicadores
        B1[Falecidos]
        B2[Clínico]
        B3[Quantidade]
        B4[Financeiro]
        B5[Automação]
        B6[CRMs]
    end

    subgraph Consolidacao
        C1[Cálculo RR]
        C2[Score Final]
        C3[Rankings]
    end

    subgraph Saida
        D1[resultado_Sentinela]
        D2[Matriz_Risco_Final]
    end

    A1 --> B1 & B2 & B3 & B4 & B5 & B6
    A2 --> B1 & B2 & B3 & B4 & B5 & B6
    B1 & B2 & B3 & B4 & B5 & B6 --> C1
    C1 --> C2 --> C3
    C3 --> D1 & D2
```

---

## 3. Mapa de Tabelas

### 3.1. Tabelas de Entrada (Leitura)

| Tabela                           | Base                  | Tipo         | Linhas (est.)       |
| -------------------------------- | --------------------- | ------------ | ------------------- |
| relatorio_movimentacao_2015_2024 | db_farmaciapopular    | Transacional | Bilhões             |
| aquisicoesFazenda_2015_2025      | db_farmaciapopular_nf | Transacional | Centenas de milhões |
| tb_obitos_unificada              | Múltiplas             | Referência   | Milhões             |
| CNPJ                             | db_CNPJ               | Referência   | Milhões             |
| CPF                              | db_CPF                | Referência   | Centenas de milhões |

### 3.2. Tabelas de Trabalho (Temporárias)

| Tabela         | Função                   | Vida Útil     |
| -------------- | ------------------------ | ------------- |
| classif        | Particionamento de CNPJs | Toda execução |
| movimentacaoFP | Dados do lote atual      | Um lote       |
| #temp\_\*      | Cálculos intermediários  | Uma query     |

### 3.3. Tabelas de Saída (Persistência)

| Tabela                          | Função              | Atualização |
| ------------------------------- | ------------------- | ----------- |
| processamentosFP                | Status de cada CNPJ | Por CNPJ    |
| movimentacaoMensalCodigoBarraFP | Movimentação mensal | Por CNPJ    |
| memoria_calculo_consolidadaFP   | Memória de cálculo  | Por CNPJ    |
| resultado_Sentinela_2015_2024   | Consolidação final  | Uma vez     |
| Matriz_Risco_Final              | Scores e rankings   | Uma vez     |

---

## 4. Fluxo de Dados por Campo

### 4.1. Rastreabilidade de um CNPJ

```mermaid
flowchart LR
    A[CNPJ] --> B[lista_cnpjs]
    B --> C[classif]
    C --> D[processamentosFP]
    D --> E[movimentacaoMensalFP]
    D --> F[memoria_calculoFP]
    E --> G[resultado_Sentinela]
    G --> H[Matriz_Risco_Final]
```

### 4.2. Rastreabilidade de uma Venda

```mermaid
flowchart LR
    A[Venda Original<br/>relatorio_movimentacao] --> B[movimentacaoFP<br/>Lote]
    B --> C[Query Unificada<br/>Python]
    C --> D[Simulação<br/>Fluxo Estoque]
    D --> E{Irregular?}
    E -->|Sim| F[memoria_calculo<br/>Tipo 'v']
    E -->|Não| G[Apenas contagem]
    F --> H[movimentacaoMensal<br/>Agregado]
    H --> I[Relatório Excel<br/>Aba Movimentação]
```

---

## 5. Integrações Externas

### 5.1. Entrada de Dados

| Fonte               | Frequência  | Método        |
| ------------------- | ----------- | ------------- |
| Ministério da Saúde | Periódica   | Carga em base |
| Receita Federal     | Periódica   | Carga em base |
| CFM                 | Sob demanda | API/Arquivo   |
| IBGE                | Anual       | Carga em base |
| Bases de Óbitos     | Periódica   | Carga em base |

### 5.2. Saída de Dados

| Destino        | Formato     | Método              |
| -------------- | ----------- | ------------------- |
| Arquivos Excel | .xlsx       | Geração local       |
| Painel BI      | Power BI    | Conexão DirectQuery |
| Auditorias     | Tabelas SQL | Acesso direto       |

---

## 6. Pontos de Verificação

### 6.1. Após Fase 1

- [ ] `lista_cnpjs` populada com CNPJs únicos
- [ ] `classif` com 100 lotes balanceados
- [ ] `estoque_inicialFP` calculado para cada produto/farmácia
- [ ] Coordenadas geográficas atualizadas

### 6.2. Após Fase 2

- [ ] Todos os CNPJs com status != RUNNING
- [ ] `movimentacaoMensalFP` populada
- [ ] `memoria_calculo` salva para CNPJs com irregularidades
- [ ] Relatórios Excel gerados

### 6.3. Após Fase 4

- [ ] Todos os indicadores calculados
- [ ] `resultado_Sentinela` consolidado
- [ ] `Matriz_Risco_Final` com scores e rankings
- [ ] Painel BI atualizado

---

!!! tip "Próximo Passo"
Veja o [Guia de Execução](../execucao/guia-execucao.md) para instruções detalhadas de como executar cada fase.
