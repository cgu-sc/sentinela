# Grupo 2: Indicadores de Padrões de Quantidade

Este grupo contém indicadores que analisam os **padrões de dispensação** e os **volumes por transação**.

---

## 1. Dispensação em Teto Máximo

### 1.1. Definição

Mede a proporção de vendas onde a quantidade dispensada atinge **exatamente o limite máximo** permitido por medicamento.

### 1.2. Script

```
📄 Indicadores/teto.sql
```

### 1.3. Contexto

O Programa Farmácia Popular define limites mensais de dispensação para cada medicamento, visando evitar:

- Acúmulo indevido de medicamentos
- Revenda ilegal
- Desperdício

### 1.4. Lógica de Cálculo

#### Fontes de Dados

| Tabela                    | Uso                               |
| ------------------------- | --------------------------------- |
| `movimentacaoFP`          | Registros de vendas               |
| `medicamentosPatologiaFP` | Limite máximo de cada medicamento |

#### Algoritmo

1. **Cruzamento:** Junta vendas com os limites de cada medicamento
2. **Comparação:** Verifica se `qnt_autorizada == qnt_limite_mensal`
3. **Contagem:** Conta quantas vendas atingem exatamente o teto
4. **Percentual:** Divide pelo total de vendas

### 1.5. Fórmula

$$
\% \text{Teto} = \frac{\text{Nº de Vendas no Teto}}{\text{Nº Total de Vendas}} \times 100
$$

### 1.6. Interpretação

| Valor        | Interpretação        |
| ------------ | -------------------- |
| **0% - 65%** | Normal               |
| **>65%**     | Elevado - investigar |

### 1.7. Comportamento Suspeito

!!! warning "Padrão de Fraude"
Farmácias fraudulentas tendem a **maximizar** cada transação fictícia:

    - Sempre dispensam a quantidade máxima permitida
    - Padrão sistemático em múltiplos medicamentos
    - Mesmo CPF sempre retira no teto

    Farmácias legítimas apresentam variação natural nas quantidades.

---

## 2. Polimedicamentos (4+ Itens por Cupom)

### 2.1. Definição

Mede a proporção de cupons fiscais que contêm **4 ou mais medicamentos distintos** no mesmo ato.

### 2.2. Script

```
📄 Indicadores/polimedicamento.sql
```

### 2.3. Contexto

Embora pacientes com múltiplas condições crônicas possam legitimamente usar vários medicamentos, um excesso de itens por cupom pode indicar:

- **Fracionamento de vendas:** Uma venda grande dividida em várias
- **Vendas fictícias:** Maximização de valor por transação
- **Uso indevido de CPFs:** Mesmo CPF usado para múltiplas famílias

### 2.4. Lógica de Cálculo

#### Algoritmo

1. **Agrupamento:** Agrupa vendas por `nu_autorizacao` (cupom fiscal)
2. **Contagem:** Conta itens distintos (`COUNT(DISTINCT codigo_barra)`)
3. **Filtro:** Seleciona cupons com 4 ou mais itens
4. **Percentual:** Divide pelo total de cupons

### 2.5. Fórmula

$$
\% \text{Polimedicamentos} = \frac{\text{Nº de Cupons com } \geq 4 \text{ itens}}{\text{Nº Total de Cupons}} \times 100
$$

### 2.6. Interpretação

| Valor        | Interpretação        |
| ------------ | -------------------- |
| **0% - 10%** | Normal               |
| **>10%**     | Elevado - investigar |

---

## 3. Média de Itens por Cupom

### 3.1. Definição

Calcula a **média de medicamentos** dispensados por autorização (cupom fiscal).

### 3.2. Script

```
📄 Indicadores/media_itens.sql
```

### 3.3. Lógica de Cálculo

#### Algoritmo

1. **Contagem Total:** Conta todas as linhas de venda
2. **Contagem de Cupons:** Conta autorizações únicas
3. **Divisão:** Calcula a média

### 3.4. Fórmula

$$
\text{Média de Itens} = \frac{\text{Total de Linhas de Venda}}{\text{Total de Autorizações Únicas}}
$$

### 3.5. Interpretação

| Valor         | Interpretação                                          |
| ------------- | ------------------------------------------------------ |
| **1.0 - 2.5** | Normal (a maioria dos pacientes leva 1-2 medicamentos) |
| **>2.5**      | Elevado - investigar                                   |

---

## 4. Resumo do Grupo

| Indicador           | Métrica  | Fórmula                        | Alerta |
| ------------------- | -------- | ------------------------------ | ------ |
| Dispensação em Teto | % vendas | Vendas no teto / Total vendas  | > 65%  |
| Polimedicamentos    | % cupons | Cupons ≥4 itens / Total cupons | > 10%  |
| Média de Itens      | Média    | Total linhas / Total cupons    | > 2.5  |

---

!!! tip "Próximo Grupo"
Veja o [Grupo 3: Padrões Financeiros](grupo3-financeiro.md) para indicadores relacionados a valores e tickets.
