# Pré-requisitos

Esta página lista todos os componentes de software e dados necessários para executar o Sistema Sentinela.

---

## 1. Software

### 1.1. Banco de Dados

| Software                                | Versão Mínima | Uso                                |
| --------------------------------------- | ------------- | ---------------------------------- |
| **Microsoft SQL Server**                | 2016+         | Armazenamento e processamento      |
| **SQL Server Management Studio (SSMS)** | 18+           | Interface para execução de scripts |

### 1.2. Python

| Software              | Versão             | Uso                                   |
| --------------------- | ------------------ | ------------------------------------- |
| **Python**            | 3.8+               | Processamento e geração de relatórios |
| **IDE** (recomendado) | PyCharm ou VS Code | Desenvolvimento e execução            |

### 1.3. Drivers

| Driver                                      | Obrigatório | Uso                         |
| ------------------------------------------- | ----------- | --------------------------- |
| **Microsoft ODBC Driver 17 for SQL Server** | ✅ Sim      | Conexão Python → SQL Server |

!!! warning "Driver ODBC"
O driver ODBC deve ser instalado **separadamente** do Python. Baixe em:
[https://docs.microsoft.com/sql/connect/odbc/download-odbc-driver-for-sql-server](https://docs.microsoft.com/sql/connect/odbc/download-odbc-driver-for-sql-server)

---

## 2. Bibliotecas Python

### 2.1. Arquivo requirements.txt

Crie um arquivo `requirements.txt` na pasta do projeto com o seguinte conteúdo:

```text
pyodbc==5.1.0
pandas==2.2.2
XlsxWriter==3.2.0
tqdm==4.66.4
art==6.1
```

### 2.2. Instalação

=== "Windows (PowerShell)"

    ```powershell
    # Criar ambiente virtual
    python -m venv venv

    # Ativar ambiente
    .\venv\Scripts\activate

    # Instalar dependências
    pip install -r requirements.txt
    ```

=== "Linux/Mac"

    ```bash
    # Criar ambiente virtual
    python3 -m venv venv

    # Ativar ambiente
    source venv/bin/activate

    # Instalar dependências
    pip install -r requirements.txt
    ```

### 2.3. Detalhamento das Bibliotecas

| Biblioteca   | Versão | Função                                |
| ------------ | ------ | ------------------------------------- |
| `pyodbc`     | 5.1.0  | Conexão com SQL Server via ODBC       |
| `pandas`     | 2.2.2  | Manipulação de dados tabulares        |
| `XlsxWriter` | 3.2.0  | Geração de planilhas Excel formatadas |
| `tqdm`       | 4.66.4 | Barras de progresso no terminal       |
| `art`        | 6.1    | Arte ASCII para interface do terminal |

---

## 3. Bases de Dados

### 3.1. Bases Primárias (Obrigatórias)

| Base                    | Conteúdo                   | Acesso Necessário |
| ----------------------- | -------------------------- | ----------------- |
| `db_farmaciapopular`    | Vendas do programa         | Leitura           |
| `db_farmaciapopular_nf` | Notas Fiscais de aquisição | Leitura           |
| `db_CNPJ`               | Cadastro de empresas       | Leitura           |
| `db_CPF`                | Cadastro de pessoas        | Leitura           |
| `temp_CGUSC`            | Base de trabalho           | Leitura e Escrita |

### 3.2. Bases Complementares

| Base                  | Conteúdo            | Uso                    |
| --------------------- | ------------------- | ---------------------- |
| `db_Cadunico`         | Cadastro Único      | Indicadores            |
| `db_CFM`              | Registro de médicos | Validação de CRMs      |
| `tb_obitos_unificada` | Óbitos              | Indicador de falecidos |
| `tb_ibge`             | Demografia          | Indicadores per capita |

---

## 4. Permissões

### 4.1. SQL Server

| Base                    | Permissão Necessária                                  |
| ----------------------- | ----------------------------------------------------- |
| `db_farmaciapopular`    | SELECT                                                |
| `db_farmaciapopular_nf` | SELECT                                                |
| `db_CNPJ`               | SELECT                                                |
| `db_CPF`                | SELECT                                                |
| `temp_CGUSC`            | SELECT, INSERT, UPDATE, DELETE, CREATE TABLE, EXECUTE |

### 4.2. Sistema de Arquivos

- Permissão de escrita na pasta onde serão salvos os relatórios Excel
- Permissão de escrita para o arquivo de log

---

## 5. Configuração do Ambiente

### 5.1. Conexão com Banco de Dados

O script Python usa autenticação **Windows (Trusted Connection)**. Verifique se seu usuário Windows tem acesso ao SQL Server:

```python
# Configuração no sentinelav8.py
conn_str = (
    'Driver={ODBC Driver 17 for SQL Server};'
    'Server=SDH-DIE-BD;'
    'Database=temp_CGUSC;'
    'Trusted_Connection=yes;'
)
```

### 5.2. Ajuste de Parâmetros

Antes de executar, ajuste os parâmetros de data nos scripts:

| Script                      | Linha      | Parâmetro                                    |
| --------------------------- | ---------- | -------------------------------------------- |
| `01 - preparacao_dados.sql` | 9, 41, 288 | Datas do período                             |
| `sentinelav8.py`            | 46-47      | `DATA_INICIAL_ANALISE`, `DATA_FINAL_ANALISE` |

---

## 6. Checklist de Pré-requisitos

### 6.1. Software

- [ ] SQL Server Management Studio instalado
- [ ] Acesso ao servidor SQL Server
- [ ] Python 3.8+ instalado
- [ ] ODBC Driver 17 instalado
- [ ] IDE Python configurada (opcional)

### 6.2. Dados

- [ ] Acesso a db_farmaciapopular
- [ ] Acesso a db_farmaciapopular_nf
- [ ] Acesso a db_CNPJ
- [ ] Acesso a temp_CGUSC (leitura e escrita)

### 6.3. Ambiente Python

- [ ] Ambiente virtual criado
- [ ] Dependências instaladas
- [ ] Conexão com banco testada

### 6.4. Parâmetros

- [ ] Datas de análise definidas
- [ ] Pasta de saída configurada

---

!!! tip "Próximo Passo"
Após verificar todos os pré-requisitos, siga o [Guia de Execução](guia-execucao.md).
