# Grupo 4: Indicadores de Automação & Geografia

Este grupo contém indicadores que detectam **padrões operacionais atípicos** e **anomalias geográficas** que podem indicar automação de fraude ou operações fora do padrão normal.

---

## 1. Vendas Consecutivas Rápidas (<60 segundos)

### 1.1. Definição

Mede a proporção de vendas que ocorrem em um intervalo de **menos de 60 segundos** após a venda anterior.

### 1.2. Script

```
📄 Indicadores/vendas_consecutivas.sql
```

### 1.3. Contexto

Uma venda legítima envolve:

- Apresentação de documentos e receita
- Consulta ao sistema
- Conferência dos medicamentos
- Processamento do pagamento

Este processo leva, no mínimo, alguns minutos. Vendas consecutivas em menos de 1 minuto podem indicar:

- **Automação:** Scripts inserindo vendas fictícias
- **Fraude estruturada:** Múltiplas vendas pré-preparadas

### 1.4. Lógica de Cálculo

#### Algoritmo

1. **Ordenação:** Ordena vendas por `data_hora` para cada PDV
2. **Cálculo de Delta:** Usa `LAG()` para obter a venda anterior
3. **Diferença de Tempo:** Calcula `DATEDIFF(SECOND, venda_anterior, venda_atual)`
4. **Filtro:** Seleciona onde delta > 0 e delta < 60
5. **Percentual:** Divide pelo total de vendas

### 1.5. Fórmula

$$
\% \text{Vendas Rápidas} = \frac{\text{Vendas com intervalo } < 60s}{\text{Total de Vendas}} \times 100
$$

### 1.6. Interpretação

| Valor       | Interpretação        |
| ----------- | -------------------- |
| **0% - 5%** | Normal               |
| **>5%**     | Elevado - Investigar |

---

## 2. Horário Atípico (Madrugada)

### 2.1. Definição

Mede a proporção de vendas processadas entre **00h00 e 06h00**.

### 2.2. Script

```
📄 Indicadores/horario_atipico.sql
```

### 2.3. Contexto

A maioria das farmácias opera em horário comercial. Vendas na madrugada podem indicar:

- **Farmácias 24h legítimas:** Algumas farmácias operam neste horário
- **Inserção de vendas fictícias:** Fraudes são inseridas fora do expediente
- **Alteração de timestamps:** Manipulação de registros

### 2.4. Lógica de Cálculo

#### Algoritmo

1. **Extração de Hora:** `DATEPART(HOUR, data_hora)`
2. **Filtro:** Seleciona onde hora >= 0 e hora < 6
3. **Contagem:** Conta vendas neste período
4. **Percentual:** Divide pelo total

### 2.5. Fórmula

$$
\% \text{Madrugada} = \frac{\text{Vendas entre 00h e 06h}}{\text{Total de Vendas}} \times 100
$$

### 2.6. Interpretação

| Valor       | Interpretação        |
| ----------- | -------------------- |
| **0% - 1%** | Normal               |
| **>1%**     | Elevado - Investigar |

---

## 3. Concentração em Dias de Pico

### 3.1. Definição

Mede a proporção do faturamento mensal concentrada nos **3 dias de maior movimento**.

### 3.2. Script

```
📄 Indicadores/concentracao_dias_pico.sql
```

### 3.3. Contexto

Um padrão de vendas natural apresenta distribuição ao longo do mês. Concentração excessiva em poucos dias pode indicar:

- **Inserção de vendas em lote:** Fraudes processadas de uma vez
- **Manipulação de datas:** Alteração de timestamps

### 3.4. Lógica de Cálculo

#### Algoritmo

1. **Agrupamento:** Agrupa vendas por dia do mês
2. **Ordenação:** Ordena por valor decrescente
3. **Seleção:** Seleciona os 3 dias de maior volume
4. **Soma:** Soma o valor desses 3 dias
5. **Percentual:** Divide pelo faturamento mensal total

### 3.5. Fórmula

$$
\% \text{Pico} = \frac{\sum \text{Valor nos 3 maiores dias}}{\sum \text{Faturamento Mensal}} \times 100
$$

### 3.6. Interpretação

| Valor         | Interpretação        |
| ------------- | -------------------- |
| **10% - 30%** | Normal               |
| **>30%**      | Elevado - Investigar |

---

## 4. Dispersão Geográfica

### 4.1. Definição

Mede a proporção de vendas para pacientes residentes em **UF diferente** da localização da farmácia.

### 4.2. Script

```
📄 Indicadores/geografico.sql
```

### 4.3. Contexto

Pacientes geralmente buscam farmácias próximas de sua residência. Alto percentual de pacientes de outras UFs pode indicar:

- **Farmácia em região de fronteira:** Legítimo em cidades-polo
- **Uso de CPFs de outras regiões:** Fraude com identidades distantes
- **Pacientes fictícios:** CPFs de regiões onde não há verificação local

### 4.4. Lógica de Cálculo

#### Fontes de Dados

| Tabela                 | Uso                          |
| ---------------------- | ---------------------------- |
| `movimentacaoFP`       | UF da farmácia               |
| `db_CPF` ou Cartão SUS | UF de residência do paciente |

#### Algoritmo

1. **Cruzamento:** Junta vendas com dados do paciente
2. **Comparação:** Verifica se `UF_farmacia != UF_paciente`
3. **Contagem:** Conta vendas com UF diferente
4. **Percentual:** Divide pelo total

### 4.5. Fórmula

$$
\% \text{Dispersão} = \frac{\text{Vendas para Pacientes de Outra UF}}{\text{Total de Vendas}} \times 100
$$

---

## 5. Compra Única

### 5.1. Definição

Mede a proporção de CPFs que realizaram **apenas uma compra** em todo o período analisado.

### 5.2. Script

```
📄 Indicadores/compra_unica.sql
```

### 5.3. Contexto

Medicamentos para doenças crônicas são de uso contínuo. Pacientes legítimos tendem a retornar periodicamente. Alto percentual de pacientes que realizaram apenas uma compra (compra única) pode indicar:

- **CPFs usados uma vez:** Evitar detecção de padrões
- **Vendas fictícias:** Cada venda usa CPF diferente (falsos positivos em farmácias de passagem)
- **Farmácia de passagem:** Legítimo em locais turísticos

### 5.4. Lógica de Cálculo

#### Algoritmo

1. **Agrupamento:** Agrupa vendas por CPF
2. **Contagem:** Conta compras por CPF
3. **Filtro:** Seleciona CPFs com exatamente 1 compra
4. **Percentual:** Divide pelo total de CPFs distintos

### 5.5. Fórmula

$$
\% \text{Compra Única} = \frac{\text{CPFs com apenas 1 compra}}{\text{Total de CPFs distintos}} \times 100
$$

---

## 6. Resumo do Grupo

| Indicador             | Métrica       | Alerta |
| --------------------- | ------------- | ------ |
| Vendas Rápidas (<60s) | % vendas      | > 5%   |
| Horário Atípico       | % vendas      | > 5%   |
| Concentração em Pico  | % faturamento | > 40%  |
| Dispersão Geográfica  | % vendas      |        |
| Compra Única          | % CPFs        |        |

---

## 7. Padrão de Automação

!!! danger "Combinação Crítica"
Quando uma farmácia apresenta valores elevados em **Vendas Rápidas** E **Horário Atípico** simultaneamente, é forte indicativo de:

    - Scripts automatizados inserindo vendas
    - Processamento em lote fora do expediente
    - Fraude estruturada e sistemática

---

!!! tip "Próximo Grupo"
Veja o [Grupo 5: Integridade Médica (CRMs)](grupo5-crms.md) para indicadores focados nos prescritores.
