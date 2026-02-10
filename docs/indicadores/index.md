# Indicadores de Risco e Fraude

Esta seção detalha os **17 indicadores** utilizados pelo Sistema Sentinela para identificar comportamentos anômalos e potencialmente fraudulentos.

---

## Estrutura dos Indicadores

Os indicadores são organizados em **5 grupos** temáticos:

<div class="grid cards" markdown>

- :material-account-alert:{ .lg .middle } **Grupo 1: Elegibilidade & Clínica**

  ***

  Indicadores que verificam a validade dos beneficiários e compatibilidade clínica.

  [:octicons-arrow-right-24: Ver indicadores](grupo1-elegibilidade.md)

- :material-package-variant:{ .lg .middle } **Grupo 2: Padrões de Quantidade**

  ***

  Indicadores que analisam padrões de dispensação e volumes por cupom.

  [:octicons-arrow-right-24: Ver indicadores](grupo2-quantidade.md)

- :material-currency-usd:{ .lg .middle } **Grupo 3: Padrões Financeiros**

  ***

  Indicadores que analisam valores, tickets e concentração de medicamentos.

  [:octicons-arrow-right-24: Ver indicadores](grupo3-financeiro.md)

- :material-robot:{ .lg .middle } **Grupo 4: Automação & Geografia**

  ***

  Indicadores que detectam automação e anomalias geográficas/temporais.

  [:octicons-arrow-right-24: Ver indicadores](grupo4-automacao.md)

- :material-doctor:{ .lg .middle } **Grupo 5: Integridade Médica (CRMs)**

  ***

  Indicadores focados nos padrões de prescrição médica.

  [:octicons-arrow-right-24: Ver indicadores](grupo5-crms.md)

</div>

---

## Matriz de Risco

<div class="grid cards" markdown>

- :material-chart-box:{ .lg .middle } **Score de Risco Final**

  ***

  Entenda como os indicadores são combinados para gerar um score único e classificação de risco.

  [:octicons-arrow-right-24: Ver metodologia](matriz-risco.md)

- :material-stethoscope:{ .lg .middle } **Análise de Prescritores**

  ***

  Detalhamento especial da análise de CRMs e médicos prescritores.

  [:octicons-arrow-right-24: Ver análise](analise-prescritores.md)

</div>

---

## Visão Geral dos 17 Indicadores

| #   | Indicador                 | Grupo         | O que mede                                     |
| --- | ------------------------- | ------------- | ---------------------------------------------- |
| 1   | Vendas para Falecidos     | Elegibilidade | % de vendas para beneficiários após óbito      |
| 2   | Incompatibilidade Clínica | Elegibilidade | % de vendas com perfil idade/sexo incompatível |
| 3   | Dispensação em Teto       | Quantidade    | % de vendas no limite máximo permitido         |
| 4   | Polimedicamentos          | Quantidade    | % de cupons com 4+ medicamentos                |
| 5   | Média de Itens            | Quantidade    | Média de itens por autorização                 |
| 6   | Ticket Médio              | Financeiro    | Valor médio por autorização                    |
| 7   | Receita por Paciente      | Financeiro    | Faturamento médio por CPF                      |
| 8   | Venda Per Capita          | Financeiro    | Faturamento / população do município           |
| 9   | Medicamentos Alto Custo   | Financeiro    | % de vendas de medicamentos caros              |
| 10  | Vendas Rápidas            | Automação     | % de vendas consecutivas <60 segundos          |
| 11  | Horário Atípico           | Automação     | % de vendas na madrugada (00h-06h)             |
| 12  | Concentração em Pico      | Automação     | % de vendas nos 3 dias de maior movimento      |
| 13  | Dispersão Geográfica      | Automação     | % de pacientes de outras UFs                   |
| 14  | Pacientes Únicos          | Automação     | % de CPFs com apenas uma compra                |
| 15  | Concentração HHI          | CRMs          | Índice de concentração de prescritores         |
| 16  | Exclusividade CRM         | CRMs          | % de CRMs exclusivos da farmácia               |
| 17  | Irregularidade CRM        | CRMs          | % de CRMs inválidos ou retroativos             |

---

## Conceito de Risco Relativo (RR)

Todos os indicadores são normalizados através do conceito de **Risco Relativo**:

$$
RR = \frac{\text{Valor do Indicador na Farmácia}}{\text{Média do Indicador na UF}}
$$

### Interpretação do RR

| Valor RR      | Interpretação            | Nível de Alerta |
| ------------- | ------------------------ | --------------- |
| **< 1.0**     | Abaixo da média          | 🟢 Normal       |
| **≈ 1.0**     | Na média                 | 🟢 Normal       |
| **1.5 - 2.0** | Levemente acima          | 🟡 Atenção      |
| **2.0 - 5.0** | Significativamente acima | 🟠 Alerta       |
| **> 5.0**     | Muito acima              | 🔴 Crítico      |

---

## Fontes de Dados para Indicadores

| Indicador         | Fontes Utilizadas                                       |
| ----------------- | ------------------------------------------------------- |
| Falecidos         | `movimentacaoFP` + `tb_obitos_unificada`                |
| Incompatibilidade | `movimentacaoFP` + `medicamentosPatologiaFP` + `db_CPF` |
| Quantidade        | `movimentacaoFP`                                        |
| Financeiros       | `movimentacaoFP` + `tb_ibge`                            |
| Automação         | `movimentacaoFP` (timestamps)                           |
| CRMs              | `movimentacaoFP` + Base CFM                             |

---

!!! tip "Como usar esta seção"
Clique em cada grupo para ver a **metodologia detalhada** de cálculo de cada indicador, incluindo:

    - Lógica de seleção de dados
    - Fórmula de cálculo
    - Interpretação dos resultados
    - Casos de borda e exceções
