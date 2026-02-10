# Grupo 1: Indicadores de Elegibilidade & Clínica

Este grupo contém indicadores que verificam a **validade dos beneficiários** e a **compatibilidade clínica** das dispensações.

---

## 1. Vendas para Falecidos

### 1.1. Definição

Mede a ocorrência de vendas para beneficiários **após a data de seu óbito**.

!!! danger "Gravidade"
Este é um dos indicadores mais fortes de fraude, pois representa uma transação **factualmente impossível**. Uma pessoa falecida não pode ir a uma farmácia retirar medicamentos.

### 1.2. Script

```
📄 Indicadores/falecidos.sql
```

### 1.3. Lógica de Cálculo

#### Fontes de Dados

| Tabela                | Uso                                |
| --------------------- | ---------------------------------- |
| `movimentacaoFP`      | Registros de vendas                |
| `tb_obitos_unificada` | Base de óbitos (SIM, SIRC, SISOBI) |

#### Algoritmo

1. **Cruzamento:** Junta as vendas com a base de óbitos usando o CPF do beneficiário como chave
2. **Filtro:** Seleciona apenas vendas onde `data_hora > dt_obito`
3. **Agregação:** Soma os valores das vendas filtradas por CNPJ
4. **Cálculo do Percentual:** Divide pelo faturamento total da farmácia

### 1.4. Fórmula

$$
\\% \text{Falecidos} = \frac{\sum \text{Valor das Vendas após Óbito}}{\sum \text{Faturamento Total}} \times 100
$$

### 1.5. Interpretação

| Valor            | Interpretação                                 |
| ---------------- | --------------------------------------------- |
| **0%**           | Normal (ideal)                                |
| **> 0.1%**       | Alerta - investigar                           |

### 1.6. Considerações

!!! warning "Fontes de Dados"
A base de óbitos é composta por múltiplas fontes:

    - **SIM:** Sistema de Informações sobre Mortalidade
    - **SIRC:** Sistema de Informações do Registro Civil
    - **SISOBI:** Sistema de Controle de Óbitos

---

## 2. Incompatibilidade Patológica (Clínica)

### 2.1. Definição

Identifica vendas de medicamentos para beneficiários com **perfil demográfico incompatível** com a indicação terapêutica.

### 2.2. Script

```
📄 Indicadores/inconsistencia_clinica.sql
```

### 2.3. Lógica de Cálculo

#### Fontes de Dados

| Tabela                    | Uso                                       |
| ------------------------- | ----------------------------------------- |
| `movimentacaoFP`          | Registros de vendas                       |
| `medicamentosPatologiaFP` | Indicação terapêutica de cada medicamento |
| `db_CPF`                  | Dados do beneficiário (idade, sexo)       |

#### Regras de Incompatibilidade

| Patologia           | Critério de Incompatibilidade | Justificativa                             |
| ------------------- | ----------------------------- | ----------------------------------------- |
| **Osteoporose**     | Paciente do sexo masculino    | Prevalência >90% em mulheres              |
| **Parkinson**       | Paciente com idade < 50 anos  | Raramente diagnosticado antes dessa idade |
| **Hipertensão**     | Paciente com idade < 20 anos  | Crianças/adolescentes raramente têm HAS   |
| **Diabetes Tipo 2** | Paciente com idade < 20 anos  | DM2 é típica de adultos                   |

#### Algoritmo

1. **Cruzamento:** Junta vendas com dados do medicamento e do paciente
2. **Aplicação de Regras:** Verifica cada regra de incompatibilidade
3. **Flag:** Marca transações que violam as regras
4. **Agregação:** Soma valores das transações flagradas

### 2.4. Fórmula

$$
\% \text{Incompatibilidade} = \frac{\sum \text{Valor das Vendas Incompatíveis}}{\sum \text{Faturamento Total}} \times 100
$$

### 2.5. Interpretação

| Valor         | Interpretação                                     |
| ------------- | ------------------------------------------------- |
| **0% - 0.3%** | Normal (possíveis exceções médicas válidas)       |
| **> 0.3%**    | Elevado - necessita justificativa                 |

### 2.6. Considerações

!!! info "Exceções Médicas"
Existem casos legítimos de prescrição fora do perfil típico:

    - Osteoporose secundária em homens (ex: uso de corticoides)
    - Parkinson juvenil (raro, mas existe)
    - Hipertensão secundária em jovens

    O indicador deve ser usado como **triagem**, não como prova definitiva.

---

## 3. Resumo do Grupo

| Indicador                 | Métrica          | Alerta |
| ------------------------- | ---------------- | ------ |
| Vendas para Falecidos     | % do faturamento | > 0.1% |
| Incompatibilidade Clínica | % do faturamento | > 0.3% |

---

!!! tip "Próximo Grupo"
Veja o [Grupo 2: Padrões de Quantidade](grupo2-quantidade.md) para indicadores relacionados a volumes de dispensação.
