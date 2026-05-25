USE [temp_CGUSC]
GO

-- ============================================================================
-- INDICADOR DE INCONSISTENCIA CLINICA
-- ============================================================================
-- OBJETIVO: Identificar farmacias com proporcao atipica de autorizacoes
--           monitoradas com incompatibilidade clinica/demografica.
--
-- METRICA PRINCIPAL:
--   O indicador deve ser calculado por periodo a partir dos componentes:
--   valor_vendas_suspeitas / valor_vendas_monitoradas.
--
-- METRICAS AUXILIARES:
--   total_vendas_monitoradas e qtd_vendas_suspeitas permitem recompor o
--   percentual por contagem quando necessario.
--
-- REGRAS CLINICAS:
--   - Osteoporose dispensada para paciente do sexo masculino
--   - Diabetes dispensado para paciente com idade < 20 anos
--   - Doenca de Parkinson dispensada para paciente com idade < 50 anos
--   - Hipertensao dispensada para paciente com idade < 20 anos
--
-- FONTE DE DADOS:
--   - db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024
--   - temp_CGUSC.fp.medicamentos_patologia
--   - temp_CGUSC.fp.dados_farmacia (id_cnpj e contexto territorial)
--   - db_CPF.dbo.CPF
-- ============================================================================

-- ============================================================================
-- LIMPEZA PREVIA DE TABELAS
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_inconsistencia_clinica;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_inconsistencia_clinica_mun;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_inconsistencia_clinica_uf;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_inconsistencia_clinica_regiao;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_inconsistencia_clinica_br;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_inconsistencia_clinica_detalhado;
GO

-- ============================================================================
-- DEFINICAO DE VARIAVEIS
-- ============================================================================
DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim    DATE = '2024-12-10';


-- ============================================================================
-- PASSO 0: DIMENSOES E FONTES OBRIGATORIAS
-- ============================================================================
IF OBJECT_ID('temp_CGUSC.fp.medicamentos_patologia', 'U') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.medicamentos_patologia nao encontrada.', 16, 1);
    RETURN;
END;

IF COL_LENGTH('temp_CGUSC.fp.medicamentos_patologia', 'codigo_barra') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.medicamentos_patologia', 'Patologia') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.medicamentos_patologia sem colunas obrigatorias codigo_barra/Patologia.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('temp_CGUSC.fp.dados_farmacia', 'U') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.dados_farmacia nao encontrada.', 16, 1);
    RETURN;
END;

IF COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'id') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'cnpj') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'municipio') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'uf') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'id_regiao_saude') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.dados_farmacia sem colunas obrigatorias id/cnpj/municipio/uf/id_regiao_saude.', 16, 1);
    RETURN;
END;

IF EXISTS (
    SELECT 1
    FROM temp_CGUSC.fp.dados_farmacia
    GROUP BY id
    HAVING COUNT_BIG(*) > 1
)
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.dados_farmacia possui ids duplicados.', 16, 1);
    RETURN;
END;

IF EXISTS (
    SELECT 1
    FROM temp_CGUSC.fp.dados_farmacia
    GROUP BY cnpj
    HAVING COUNT_BIG(*) > 1
)
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.dados_farmacia possui CNPJs duplicados.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'U') IS NULL
BEGIN
    RAISERROR('Tabela db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 nao encontrada.', 16, 1);
    RETURN;
END;

IF COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'cnpj') IS NULL
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'cpf') IS NULL
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'num_autorizacao') IS NULL
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'valor_pago') IS NULL
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'data_hora') IS NULL
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'codigo_barra') IS NULL
BEGIN
    RAISERROR('Tabela db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 sem colunas obrigatorias para inconsistencia clinica.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('db_CPF.dbo.CPF', 'U') IS NULL
BEGIN
    RAISERROR('Tabela db_CPF.dbo.CPF nao encontrada.', 16, 1);
    RETURN;
END;

IF COL_LENGTH('db_CPF.dbo.CPF', 'CPF') IS NULL
   OR COL_LENGTH('db_CPF.dbo.CPF', 'idSexo') IS NULL
   OR COL_LENGTH('db_CPF.dbo.CPF', 'dataNascimento') IS NULL
BEGIN
    RAISERROR('Tabela db_CPF.dbo.CPF sem colunas obrigatorias CPF/idSexo/dataNascimento.', 16, 1);
    RETURN;
END;

DROP TABLE IF EXISTS #farmacias_dim;

SELECT
    CAST(F.id AS INT) AS id_cnpj,
    CAST(F.cnpj AS VARCHAR(14)) AS cnpj,
    CAST(F.municipio AS VARCHAR(255)) AS municipio,
    CAST(UPPER(LTRIM(RTRIM(F.uf))) AS VARCHAR(2)) AS uf,
    CAST(F.id_regiao_saude AS INT) AS id_regiao_saude
INTO #farmacias_dim
FROM temp_CGUSC.fp.dados_farmacia AS F;

IF EXISTS (
    SELECT 1
    FROM #farmacias_dim
    WHERE id_cnpj IS NULL
       OR NULLIF(LTRIM(RTRIM(cnpj)), '') IS NULL
       OR NULLIF(LTRIM(RTRIM(municipio)), '') IS NULL
       OR NULLIF(LTRIM(RTRIM(uf)), '') IS NULL
       OR id_regiao_saude IS NULL
)
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.dados_farmacia possui valores obrigatorios nulos para contexto territorial.', 16, 1);
    RETURN;
END;

CREATE UNIQUE CLUSTERED INDEX IDX_farmacias_dim_cnpj
ON #farmacias_dim(cnpj);

CREATE UNIQUE NONCLUSTERED INDEX IDX_farmacias_dim_id
ON #farmacias_dim(id_cnpj);

DROP TABLE IF EXISTS #medicamentos_clinicos;

SELECT DISTINCT
    C.codigo_barra,
    UPPER(LTRIM(RTRIM(C.Patologia))) AS patologia
INTO #medicamentos_clinicos
FROM temp_CGUSC.fp.medicamentos_patologia C
WHERE C.codigo_barra IS NOT NULL
  AND UPPER(LTRIM(RTRIM(C.Patologia))) IN ('OSTEOPOROSE', 'DIABETES', 'DOENCA DE PARKINSON', 'HIPERTENSAO');

IF NOT EXISTS (SELECT 1 FROM #medicamentos_clinicos)
BEGIN
    RAISERROR('Nao ha medicamentos com patologia valida para monitoramento de inconsistencia clinica.', 16, 1);
    RETURN;
END;

IF EXISTS (
    SELECT 1
    FROM #medicamentos_clinicos
    GROUP BY codigo_barra
    HAVING COUNT_BIG(*) > 1
)
BEGIN
    RAISERROR('Um mesmo codigo_barra esta associado a mais de uma patologia clinica monitorada.', 16, 1);
    RETURN;
END;

CREATE UNIQUE CLUSTERED INDEX IDX_medicamentos_clinicos_gtin
ON #medicamentos_clinicos(codigo_barra);


-- ============================================================================
-- PASSO 1: VENDAS POR AUTORIZACAO
-- ============================================================================
DROP TABLE IF EXISTS #AutorizacoesClinicas;

SELECT
    F.id_cnpj,
    CAST(YEAR(A.data_hora) AS SMALLINT) AS ano_base,
    A.num_autorizacao,
    COUNT_BIG(*) AS qtd_itens_monitorados,
    SUM(A.valor_pago) AS valor_total_autorizacao_raw,
    SUM(
        CASE
            WHEN M.patologia = 'OSTEOPOROSE'
                 AND B.idSexo = 'M'
                THEN A.valor_pago
            WHEN M.patologia = 'DIABETES'
                 AND FLOOR(DATEDIFF(DAY, B.dataNascimento, A.data_hora) / 365.25) < 20
                THEN A.valor_pago
            WHEN M.patologia = 'DOENCA DE PARKINSON'
                 AND FLOOR(DATEDIFF(DAY, B.dataNascimento, A.data_hora) / 365.25) < 50
                THEN A.valor_pago
            WHEN M.patologia = 'HIPERTENSAO'
                 AND FLOOR(DATEDIFF(DAY, B.dataNascimento, A.data_hora) / 365.25) < 20
                THEN A.valor_pago
            ELSE 0
        END
    ) AS valor_itens_suspeitos_raw,
    MAX(
        CASE
            WHEN M.patologia = 'OSTEOPOROSE'
                 AND B.idSexo = 'M'
                THEN 1
            WHEN M.patologia = 'DIABETES'
                 AND FLOOR(DATEDIFF(DAY, B.dataNascimento, A.data_hora) / 365.25) < 20
                THEN 1
            WHEN M.patologia = 'DOENCA DE PARKINSON'
                 AND FLOOR(DATEDIFF(DAY, B.dataNascimento, A.data_hora) / 365.25) < 50
                THEN 1
            WHEN M.patologia = 'HIPERTENSAO'
                 AND FLOOR(DATEDIFF(DAY, B.dataNascimento, A.data_hora) / 365.25) < 20
                THEN 1
            ELSE 0
        END
    ) AS flag_venda_suspeita
INTO #AutorizacoesClinicas
FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
INNER JOIN #farmacias_dim F
    ON F.cnpj = A.cnpj
INNER JOIN #medicamentos_clinicos M
    ON M.codigo_barra = A.codigo_barra
LEFT JOIN db_CPF.dbo.CPF B
    ON B.CPF = A.cpf
WHERE A.data_hora >= @DataInicio
  AND A.data_hora < DATEADD(DAY, 1, @DataFim)
  AND A.num_autorizacao IS NOT NULL
  AND A.cpf IS NOT NULL
  AND A.codigo_barra IS NOT NULL
GROUP BY
    F.id_cnpj,
    YEAR(A.data_hora),
    A.num_autorizacao;

IF NOT EXISTS (SELECT 1 FROM #AutorizacoesClinicas)
BEGIN
    RAISERROR('Nao ha autorizacoes monitoradas para calcular inconsistencia clinica.', 16, 1);
    RETURN;
END;

CREATE CLUSTERED INDEX IDX_AutorizacoesClinicas_CNPJ_Ano
ON #AutorizacoesClinicas(id_cnpj, ano_base);

DROP TABLE IF EXISTS #medicamentos_clinicos;


-- ============================================================================
-- PASSO 2: CALCULO BASE POR FARMACIA/ANO
-- ============================================================================
DROP TABLE IF EXISTS #IndicadorClinicaAgregado;

SELECT
    id_cnpj,
    ano_base,
    CAST(COUNT_BIG(*) AS INT) AS total_vendas_monitoradas,
    CAST(SUM(flag_venda_suspeita) AS INT) AS qtd_vendas_suspeitas,
    SUM(valor_total_autorizacao_raw) AS valor_vendas_monitoradas_raw,
    SUM(valor_itens_suspeitos_raw) AS valor_vendas_suspeitas_raw
INTO #IndicadorClinicaAgregado
FROM #AutorizacoesClinicas
GROUP BY
    id_cnpj,
    ano_base;

IF EXISTS (
    SELECT 1
    FROM #IndicadorClinicaAgregado
    WHERE valor_vendas_monitoradas_raw <= 0
)
BEGIN
    RAISERROR('Existem farmacias/ano com valor monitorado menor ou igual a zero para inconsistencia clinica.', 16, 1);
    RETURN;
END;

CREATE UNIQUE CLUSTERED INDEX IDX_IndicadorClinicaAgregado_CNPJ_Ano
ON #IndicadorClinicaAgregado(id_cnpj, ano_base);

DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_inconsistencia_clinica;

SELECT
    id_cnpj,
    ano_base,
    total_vendas_monitoradas,
    qtd_vendas_suspeitas,
    CAST(valor_vendas_monitoradas_raw AS DECIMAL(9,2)) AS valor_vendas_monitoradas,
    CAST(valor_vendas_suspeitas_raw AS DECIMAL(9,2)) AS valor_vendas_suspeitas
INTO temp_CGUSC.fp.indicador_inconsistencia_clinica
FROM #IndicadorClinicaAgregado;

IF NOT EXISTS (SELECT 1 FROM temp_CGUSC.fp.indicador_inconsistencia_clinica)
BEGIN
    RAISERROR('Nao ha farmacias/ano com valor monitorado positivo para inconsistencia clinica.', 16, 1);
    RETURN;
END;

CREATE UNIQUE CLUSTERED INDEX IDX_IndClinica_CNPJ_Ano
ON temp_CGUSC.fp.indicador_inconsistencia_clinica(id_cnpj, ano_base);

DROP TABLE IF EXISTS #AutorizacoesClinicas;
DROP TABLE IF EXISTS #IndicadorClinicaAgregado;


-- ============================================================================
-- PASSO 3: TABELA CONSOLIDADA FINAL
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_inconsistencia_clinica_detalhado;

SELECT
    I.id_cnpj,
    I.ano_base,
    I.total_vendas_monitoradas,
    I.qtd_vendas_suspeitas,
    I.valor_vendas_monitoradas,
    I.valor_vendas_suspeitas
INTO temp_CGUSC.fp.indicador_inconsistencia_clinica_detalhado
FROM temp_CGUSC.fp.indicador_inconsistencia_clinica I;

CREATE UNIQUE CLUSTERED INDEX IDX_FinalClinica_CNPJ
ON temp_CGUSC.fp.indicador_inconsistencia_clinica_detalhado(id_cnpj, ano_base);


-- ============================================================================
-- PASSO 4: AGREGADO POR REGIAO DE SAUDE/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_inconsistencia_clinica_regiao;

SELECT
    I.ano_base,
    F.id_regiao_saude,
    SUM(I.total_vendas_monitoradas) AS total_vendas_monitoradas,
    SUM(I.qtd_vendas_suspeitas) AS qtd_vendas_suspeitas,
    CAST(SUM(I.valor_vendas_monitoradas) AS DECIMAL(19,2)) AS valor_vendas_monitoradas,
    CAST(SUM(I.valor_vendas_suspeitas) AS DECIMAL(19,2)) AS valor_vendas_suspeitas,
    CAST(COUNT_BIG(*) AS INT) AS qtd_cnpjs
INTO temp_CGUSC.fp.indicador_inconsistencia_clinica_regiao
FROM temp_CGUSC.fp.indicador_inconsistencia_clinica I
INNER JOIN #farmacias_dim F
    ON F.id_cnpj = I.id_cnpj
GROUP BY
    I.ano_base,
    F.id_regiao_saude;

CREATE UNIQUE CLUSTERED INDEX IDX_IndClinicaReg
ON temp_CGUSC.fp.indicador_inconsistencia_clinica_regiao(ano_base, id_regiao_saude);


-- ============================================================================
-- PASSO 5: AGREGADO POR UF/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_inconsistencia_clinica_uf;

SELECT
    I.ano_base,
    F.uf,
    SUM(I.total_vendas_monitoradas) AS total_vendas_monitoradas,
    SUM(I.qtd_vendas_suspeitas) AS qtd_vendas_suspeitas,
    CAST(SUM(I.valor_vendas_monitoradas) AS DECIMAL(19,2)) AS valor_vendas_monitoradas,
    CAST(SUM(I.valor_vendas_suspeitas) AS DECIMAL(19,2)) AS valor_vendas_suspeitas,
    CAST(COUNT_BIG(*) AS INT) AS qtd_cnpjs
INTO temp_CGUSC.fp.indicador_inconsistencia_clinica_uf
FROM temp_CGUSC.fp.indicador_inconsistencia_clinica I
INNER JOIN #farmacias_dim F
    ON F.id_cnpj = I.id_cnpj
GROUP BY
    I.ano_base,
    F.uf;

CREATE UNIQUE CLUSTERED INDEX IDX_IndClinicaUF
ON temp_CGUSC.fp.indicador_inconsistencia_clinica_uf(ano_base, uf);


-- ============================================================================
-- PASSO 6: AGREGADO BRASIL/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_inconsistencia_clinica_br;

SELECT
    I.ano_base,
    SUM(I.total_vendas_monitoradas) AS total_vendas_monitoradas,
    SUM(I.qtd_vendas_suspeitas) AS qtd_vendas_suspeitas,
    CAST(SUM(I.valor_vendas_monitoradas) AS DECIMAL(19,2)) AS valor_vendas_monitoradas,
    CAST(SUM(I.valor_vendas_suspeitas) AS DECIMAL(19,2)) AS valor_vendas_suspeitas,
    CAST(COUNT_BIG(*) AS INT) AS qtd_cnpjs
INTO temp_CGUSC.fp.indicador_inconsistencia_clinica_br
FROM temp_CGUSC.fp.indicador_inconsistencia_clinica I
GROUP BY
    I.ano_base;

CREATE UNIQUE CLUSTERED INDEX IDX_IndClinicaBR
ON temp_CGUSC.fp.indicador_inconsistencia_clinica_br(ano_base);
GO


-- ============================================================================
-- LIMPEZA DAS TABELAS INTERMEDIARIAS
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_inconsistencia_clinica;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_inconsistencia_clinica_mun;
DROP TABLE IF EXISTS #farmacias_dim;
GO
