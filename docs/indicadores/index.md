# Indicadores de Risco e Fraude

Esta seção detalha os **18 indicadores** utilizados pelo Sistema Sentinela para identificar comportamentos anômalos e potencialmente fraudulentos.

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

- :material-chart-box:{ .lg .middle } **Score de Risco Final (V7.0)**

  ***

  A V7 utiliza normalização regional por percentil e penalidade linear por indicadores críticos.

  [:octicons-arrow-right-24: Ver metodologia](matriz-risco.md)

- :material- stethoscope:{ .lg .middle } **Análise de Prescritores**

  ***

  Detalhamento especial da análise de CRMs e médicos prescritores.

  [:octicons-arrow-right-24: Ver análise](analise-prescritores.md)

</div>

---

## Visão Geral dos Indicadores

| # | Indicador | Grupo | O que mede |
| :--- | :--- | :--- | :--- |
| 1 | Vendas para Falecidos | Elegibilidade | % de vendas para beneficiários após óbito |
| 2 | Incompatibilidade Clínica | Elegibilidade | % de vendas com perfil idade/sexo incompatível |
| 3 | Dispensação em Teto | Quantidade | % de vendas no limite máximo permitido |
| 4 | Polimedicamentos | Quantidade | % de cupons com 4+ medicamentos |
| 5 | Ticket Médio | Financeiro | Valor médio por autorização |
| 6 | Receita por Paciente | Financeiro | Faturamento médio por CPF |
| 7 | Venda Per Capita | Financeiro | Faturamento / população do município |
| 8 | Medicamentos Alto Custo | Financeiro | % de vendas de medicamentos caros |
| 9 | Vendas Rápidas | Automação | % de vendas consecutivas <60 segundos |
| 10 | Horário Atípico | Automação | % de vendas na madrugada (00h-06h) |
| 11 | Concentração em Pico | Automação | % de vendas nos 3 dias de maior movimento |
| 12 | Dispersão Geográfica | Automação | % de pacientes de outras UFs |
| 13 | Compra Única | Automação | % de CPFs com apenas uma compra |
| 14 | Concentração HHI | CRMs | Índice de concentração de prescritores |
| 15 | Exclusividade CRM | CRMs | % de CRMs exclusivos da farmácia |
| 16 | Irregularidade CRM | CRMs | % de CRMs inválidos ou retroativos |
| 17 | **Recorrência Sistêmica** | Automação | Padrão repetitivo de horários e datas |
| 18 | **Auditoria Financeira** | Financeiro | % de não comprovação em auditorias prévias |

---

## Normalização por Percentil (Modelo V7.0)

Diferente de versões anteriores, o Sistema Sentinela agora utiliza a função **Percentil Acumulado (CUME_DIST)** para normalizar os resultados:

### A Escala 0-100
- **0.0**: Comportamento padrão (baixa suspeição).
- **50.0**: Posição mediana no benchmark regional.
- **100.0**: Posição máxima de risco no benchmark regional.

### Penalidade Linear por Flags Críticos
Além da escala base, cada indicador que apresenta uma anomalia severa (>5x a média regional) gera um **Flag Crítico**, adicionando **+10 pontos fixos** ao score final.

---

## Fontes de Dados

| Fonte | Descrição |
| :--- | :--- |
| `movimentacaoFP` | Dados transacionais do Farmácia Popular. |
| `tb_obitos_unificada` | Base de óbitos do SISOBI/Cartórios. |
| `base_CFM` | Cadastro nacional de médicos e CRMs. |
| `tb_ibge` | Dados populacionais e geográficos. |

---

!!! tip "Manual Detalhado"
    Clique em cada grupo de indicadores no topo para ver as fórmulas matemáticas e critérios de corte específicos.
