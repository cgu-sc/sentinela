# Grupo 5: Indicadores de Integridade Médica (CRMs)

Este grupo contém indicadores focados nos **padrões de prescrição médica**, identificando concentração, irregularidades e comportamentos atípicos dos prescritores.

---

## 1. Concentração de Prescritores (Índice HHI)

### 1.1. Definição

O **Índice Herfindahl-Hirschman (HHI)** mede a concentração das vendas em poucos prescritores. Quanto maior o índice, maior a dependência da farmácia de poucos médicos.

### 1.2. Scripts

```
📄 Indicadores/crms.sql
📄 Indicadores/gerador_dados_para_indicador_crms.sql
```

### 1.3. Contexto

Uma farmácia legítima atende pacientes de **diversos médicos**. Concentração excessiva pode indicar:

- **Acordo com médicos:** Direcionamento de pacientes
- **CRMs fictícios:** Uso de poucos CRMs para todas as vendas
- **Esquema organizado:** Médicos "parceiros" da fraude

### 1.4. Lógica de Cálculo

#### Conceito do HHI

O HHI é um índice econômico padrão para medir concentração de mercado. No contexto do Sentinela, mede a concentração de prescritores.

#### Algoritmo

1. **Agrupamento:** Agrupa vendas por CRM
2. **Cálculo de Participação:** Para cada CRM, calcula `participação = vendas_crm / vendas_total`
3. **Quadrado:** Eleva cada participação ao quadrado
4. **Soma:** Soma todos os quadrados
5. **Escala:** Multiplica por 10.000 (convenção HHI)

### 1.5. Fórmula

$$
\text{HHI} = \sum_{i=1}^{n} (S_i \times 100)^2
$$

Onde $S_i$ é a participação percentual do médico $i$ nas vendas.

### 1.6. Interpretação

| HHI               | Classificação         | Interpretação                    |
| ----------------- | --------------------- | -------------------------------- |
| **< 1.500**       | Baixa concentração    | Normal - múltiplos prescritores  |
| **1.500 - 2.500** | Concentração moderada | Atenção                          |
| **> 2.500**       | Alta concentração     | Investigar - poucos CRMs dominam |
| **> 5.000**       | Concentração extrema  | Crítico                          |

### 1.7. Exemplo de Cálculo

!!! example "Exemplo"
**Farmácia A - Diversificada:**

    - CRM 1: 20% das vendas → (20)² = 400
    - CRM 2: 15% das vendas → (15)² = 225
    - CRM 3: 10% das vendas → (10)² = 100
    - Outros 50 CRMs: 55% → ~60 (disperso)

    **HHI ≈ 785** (Baixa concentração ✅)

    ---

    **Farmácia B - Concentrada:**

    - CRM 1: 60% das vendas → (60)² = 3.600
    - CRM 2: 25% das vendas → (25)² = 625
    - CRM 3: 15% das vendas → (15)² = 225

    **HHI = 4.450** (Alta concentração ❌)

---

## 2. Exclusividade de CRM

### 2.1. Definição

Mede a proporção de médicos que prescrevem **exclusivamente** para esta farmácia em todo o Brasil.

### 2.2. Script

```
📄 Indicadores/exclusividade_crm.sql
```

### 2.3. Contexto

Um médico legítimo atende em consultórios e prescreve para diversas farmácias onde seus pacientes se sentem confortáveis. Um CRM que só aparece em **uma única farmácia** no país inteiro é altamente suspeito:

- Pode ser um CRM fictício ou de médico falecido
- Pode indicar acordo exclusivo (ilegal)
- Pode ser fraude com receitas falsas

### 2.4. Lógica de Cálculo

#### Algoritmo

1. **Levantamento:** Para cada CRM, lista todos os CNPJs onde prescreveu
2. **Contagem:** Conta CNPJs distintos por CRM
3. **Filtro:** Identifica CRMs com COUNT(DISTINCT CNPJ) = 1
4. **Soma:** Soma o valor das vendas desses CRMs
5. **Percentual:** Divide pelo faturamento total

### 2.5. Fórmula

$$
\% \text{Exclusividade} = \frac{\sum \text{Vendas de CRMs Exclusivos}}{\sum \text{Faturamento Total}} \times 100
$$

### 2.6. Interpretação

| Valor       | Interpretação        |
| ----------- | -------------------- |
| **0% - 5%** | Normal               |
| **>5%**     | Elevado - Investigar |

---

## 3. Irregularidade de CRM

### 3.1. Definição

Mede a proporção de vendas vinculadas a CRMs **inválidos ou com prescrição anterior ao registro**.

### 3.2. Script

```
📄 Indicadores/crms_irregulares.sql
```

### 3.3. Tipos de Irregularidade

| Tipo                      | Descrição                                    | Gravidade   |
| ------------------------- | -------------------------------------------- | ----------- |
| **CRM Inexistente**       | Não encontrado na base do CFM                | 🔴 Crítico  |
| **CRM Cancelado**         | Médico com registro cancelado                | 🔴 Crítico  |
| **Prescrição Retroativa** | Data da prescrição < Data de registro no CFM | 🔴 Crítico  |
| **CRM de Outra UF**       | Médico prescrevendo fora de sua jurisdição   | 🟡 Moderado |

### 3.4. Lógica de Cálculo

#### Fontes de Dados

| Tabela           | Uso                         |
| ---------------- | --------------------------- |
| `movimentacaoFP` | CRM das vendas              |
| Base CFM         | Registro de médicos e datas |

#### Algoritmo

1. **Cruzamento:** Junta vendas com base do CFM
2. **Verificação 1:** CRM IS NULL (não encontrado)
3. **Verificação 2:** Data_Venda < Data_Inscricao_CRM
4. **Soma:** Agrega valores das vendas irregulares
5. **Percentual:** Divide pelo faturamento total

### 3.5. Fórmula

$$
\% \text{CRM Irregular} = \frac{\sum \text{Vendas com CRM Irregular}}{\sum \text{Faturamento Total}} \times 100
$$

### 3.6. Interpretação

| Valor    | Interpretação    |
| -------- | ---------------- |
| **0%**   | Ideal            |
| **> 0%** | Crítico - fraude |

---

## 4. Resumo do Grupo

| Indicador          | Métrica         | Alerta  |
| ------------------ | --------------- | ------- |
| Concentração HHI   | Índice 0-10.000 | > 2.500 |
| Exclusividade CRM  | % faturamento   | > 5%    |
| Irregularidade CRM | % faturamento   | > 0%    |

---

## 5. Métricas Complementares

Além dos indicadores principais, o sistema calcula:

### 5.1. Concentração Top 1

Percentual das vendas vinculadas ao **principal prescritor**:

$$
\% \text{Top 1} = \frac{\text{Vendas do CRM nº 1}}{\text{Faturamento Total}} \times 100
$$

| Valor         | Interpretação |
| ------------- | ------------- |
| **< 15%**     | Normal        |
| **15% - 30%** | Elevado       |
| **> 30%**     | Crítico       |

### 5.2. Concentração Top 5

Percentual das vendas vinculadas aos **5 maiores prescritores**:

$$
\% \text{Top 5} = \frac{\sum \text{Vendas dos 5 maiores CRMs}}{\text{Faturamento Total}} \times 100
$$

| Valor         | Interpretação |
| ------------- | ------------- |
| **< 50%**     | Normal        |
| **50% - 70%** | Elevado       |
| **> 70%**     | Crítico       |

---

## 6. Análise Integrada de CRMs

### 6.1. Padrão de Fraude Médica

Quando uma farmácia apresenta:

- ✅ Alto HHI
- ✅ Alta exclusividade
- ✅ CRMs irregulares

É forte indicativo de **esquema organizado**.

---

!!! tip "Próximo Passo"
Veja a [Análise de Prescritores](analise-prescritores.md) para mais detalhes sobre a investigação de médicos suspeitos.
