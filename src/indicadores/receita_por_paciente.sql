USE [temp_CGUSC]
GO

-- ============================================================================
-- INDICADOR DE RECEITA POR PACIENTE
-- ============================================================================
-- OBJETIVO: Identificar farmacias com faturamento medio mensal por paciente
--           muito superior ao observado em estabelecimentos comparaveis.
--
-- METRICA PRINCIPAL:
--   O indicador deve ser calculado por periodo a partir dos componentes:
--   valor_total_auditado / total_pacientes_distintos.
--
-- METRICA AUXILIAR:
--   receita_por_paciente_mensal usa valor_total_auditado dividido pelo total
--   de pacientes-mes observado no periodo.
--
-- FONTE DE DADOS:
--   - db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024
--   - temp_CGUSC.fp.medicamentos_patologia (universo de medicamentos auditados)
--   - temp_CGUSC.fp.dados_farmacia (id_cnpj e contexto territorial)
-- ============================================================================

-- ============================================================================
-- LIMPEZA PREVIA DE TABELAS
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_receita_por_paciente;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_receita_por_paciente_mun;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_receita_por_paciente_uf;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_receita_por_paciente_regiao;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_receita_por_paciente_br;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_receita_por_paciente_detalhado;
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
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.medicamentos_patologia sem coluna obrigatoria codigo_barra.', 16, 1);
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
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'valor_pago') IS NULL
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'data_hora') IS NULL
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'codigo_barra') IS NULL
BEGIN
    RAISERROR('Tabela db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 sem colunas obrigatorias para receita por paciente.', 16, 1);
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

DROP TABLE IF EXISTS #medicamentos_patologia_gtin;

SELECT DISTINCT
    C.codigo_barra
INTO #medicamentos_patologia_gtin
FROM temp_CGUSC.fp.medicamentos_patologia C
WHERE C.codigo_barra IS NOT NULL;

IF NOT EXISTS (SELECT 1 FROM #medicamentos_patologia_gtin)
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.medicamentos_patologia sem codigo_barra valido.', 16, 1);
    RETURN;
END;

CREATE UNIQUE CLUSTERED INDEX IDX_medicamentos_patologia_gtin
ON #medicamentos_patologia_gtin(codigo_barra);


-- ============================================================================
-- PASSO 1: CONSOLIDADO POR FARMACIA/PACIENTE/ANO
-- ============================================================================
DROP TABLE IF EXISTS #ConsolidadoPacientes;

SELECT
    F.id_cnpj,
    CAST(YEAR(A.data_hora) AS SMALLINT) AS ano_base,
    CAST(COUNT(DISTINCT CAST(A.cpf AS VARCHAR(20))) AS INT) AS total_pacientes_distintos,
    CAST(SUM(CAST(A.valor_pago AS DECIMAL(19,2))) AS DECIMAL(9,2)) AS valor_total_auditado,
    CAST(COUNT(DISTINCT DATEFROMPARTS(YEAR(A.data_hora), MONTH(A.data_hora), 1)) AS TINYINT) AS total_meses_ativos
INTO #ConsolidadoPacientes
FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
INNER JOIN #farmacias_dim F
    ON F.cnpj = A.cnpj
INNER JOIN #medicamentos_patologia_gtin C
    ON C.codigo_barra = A.codigo_barra
WHERE A.data_hora >= @DataInicio
  AND A.data_hora < DATEADD(DAY, 1, @DataFim)
  AND NULLIF(LTRIM(RTRIM(CAST(A.cpf AS VARCHAR(20)))), '') IS NOT NULL
  AND A.valor_pago IS NOT NULL
  AND A.codigo_barra IS NOT NULL
GROUP BY
    F.id_cnpj,
    YEAR(A.data_hora)
HAVING COUNT(DISTINCT CAST(A.cpf AS VARCHAR(20))) > 0
   AND COUNT(DISTINCT DATEFROMPARTS(YEAR(A.data_hora), MONTH(A.data_hora), 1)) > 0;

CREATE CLUSTERED INDEX IDX_ConsolidadoPacientes_CNPJ_Ano
ON #ConsolidadoPacientes(id_cnpj, ano_base);

DROP TABLE IF EXISTS #medicamentos_patologia_gtin;


-- ============================================================================
-- PASSO 2: CALCULO BASE POR FARMACIA/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_receita_por_paciente;

SELECT
    id_cnpj,
    ano_base,
    CAST(valor_total_auditado AS DECIMAL(9,2)) AS valor_total_auditado,
    total_pacientes_distintos,
    total_meses_ativos,
    CAST(
        CAST(valor_total_auditado AS DECIMAL(12,4)) /
        CAST(total_pacientes_distintos AS DECIMAL(12,4))
    AS DECIMAL(9,2)) AS receita_por_paciente,
    CAST(
        CAST(valor_total_auditado AS DECIMAL(12,4)) /
        (
            CAST(total_pacientes_distintos AS DECIMAL(12,4)) *
            CAST(total_meses_ativos AS DECIMAL(12,4))
        )
    AS DECIMAL(9,2)) AS receita_por_paciente_mensal
INTO temp_CGUSC.fp.indicador_receita_por_paciente
FROM #ConsolidadoPacientes;

CREATE UNIQUE CLUSTERED INDEX IDX_IndRecPac_CNPJ_Ano
ON temp_CGUSC.fp.indicador_receita_por_paciente(id_cnpj, ano_base);

DROP TABLE IF EXISTS #ConsolidadoPacientes;


-- ============================================================================
-- PASSO 3: TABELA CONSOLIDADA FINAL POR CNPJ/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_receita_por_paciente_detalhado;

SELECT
    I.id_cnpj,
    I.ano_base,
    CAST(I.valor_total_auditado AS DECIMAL(9,2)) AS valor_total_auditado,
    I.total_pacientes_distintos,
    I.total_meses_ativos,
    CAST(I.receita_por_paciente AS DECIMAL(9,2)) AS receita_por_paciente,
    CAST(I.receita_por_paciente_mensal AS DECIMAL(9,2)) AS receita_por_paciente_mensal
INTO temp_CGUSC.fp.indicador_receita_por_paciente_detalhado
FROM temp_CGUSC.fp.indicador_receita_por_paciente I;

CREATE UNIQUE CLUSTERED INDEX IDX_FinalRecPac_CNPJ
ON temp_CGUSC.fp.indicador_receita_por_paciente_detalhado(id_cnpj, ano_base);


-- ============================================================================
-- PASSO 4: AGREGADO POR REGIAO DE SAUDE/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_receita_por_paciente_regiao;

SELECT
    I.ano_base,
    F.id_regiao_saude,
    CAST(SUM(I.valor_total_auditado) AS DECIMAL(19,2)) AS valor_total_auditado,
    SUM(I.total_pacientes_distintos) AS total_pacientes_distintos,
    SUM(I.total_meses_ativos) AS total_meses_ativos,
    CAST(
        CAST(SUM(I.valor_total_auditado) AS DECIMAL(19,4)) /
        CAST(SUM(I.total_pacientes_distintos) AS DECIMAL(19,4))
    AS DECIMAL(9,2)) AS receita_por_paciente,
    CAST(
        CAST(SUM(I.valor_total_auditado) AS DECIMAL(19,4)) /
        CAST(SUM(I.total_pacientes_distintos * I.total_meses_ativos) AS DECIMAL(19,4))
    AS DECIMAL(9,2)) AS receita_por_paciente_mensal,
    CAST(COUNT_BIG(*) AS INT) AS qtd_cnpjs
INTO temp_CGUSC.fp.indicador_receita_por_paciente_regiao
FROM temp_CGUSC.fp.indicador_receita_por_paciente I
INNER JOIN #farmacias_dim F
    ON F.id_cnpj = I.id_cnpj
GROUP BY
    I.ano_base,
    F.id_regiao_saude;

CREATE UNIQUE CLUSTERED INDEX IDX_IndRecPacReg
ON temp_CGUSC.fp.indicador_receita_por_paciente_regiao(ano_base, id_regiao_saude);


-- ============================================================================
-- PASSO 5: AGREGADO POR UF/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_receita_por_paciente_uf;

SELECT
    I.ano_base,
    F.uf,
    CAST(SUM(I.valor_total_auditado) AS DECIMAL(19,2)) AS valor_total_auditado,
    SUM(I.total_pacientes_distintos) AS total_pacientes_distintos,
    SUM(I.total_meses_ativos) AS total_meses_ativos,
    CAST(
        CAST(SUM(I.valor_total_auditado) AS DECIMAL(19,4)) /
        CAST(SUM(I.total_pacientes_distintos) AS DECIMAL(19,4))
    AS DECIMAL(9,2)) AS receita_por_paciente,
    CAST(
        CAST(SUM(I.valor_total_auditado) AS DECIMAL(19,4)) /
        CAST(SUM(I.total_pacientes_distintos * I.total_meses_ativos) AS DECIMAL(19,4))
    AS DECIMAL(9,2)) AS receita_por_paciente_mensal,
    CAST(COUNT_BIG(*) AS INT) AS qtd_cnpjs
INTO temp_CGUSC.fp.indicador_receita_por_paciente_uf
FROM temp_CGUSC.fp.indicador_receita_por_paciente I
INNER JOIN #farmacias_dim F
    ON F.id_cnpj = I.id_cnpj
GROUP BY
    I.ano_base,
    F.uf;

CREATE UNIQUE CLUSTERED INDEX IDX_IndRecPacUF
ON temp_CGUSC.fp.indicador_receita_por_paciente_uf(ano_base, uf);


-- ============================================================================
-- PASSO 6: AGREGADO BRASIL/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_receita_por_paciente_br;

SELECT
    I.ano_base,
    CAST(SUM(I.valor_total_auditado) AS DECIMAL(19,2)) AS valor_total_auditado,
    SUM(I.total_pacientes_distintos) AS total_pacientes_distintos,
    SUM(I.total_meses_ativos) AS total_meses_ativos,
    CAST(
        CAST(SUM(I.valor_total_auditado) AS DECIMAL(19,4)) /
        CAST(SUM(I.total_pacientes_distintos) AS DECIMAL(19,4))
    AS DECIMAL(9,2)) AS receita_por_paciente,
    CAST(
        CAST(SUM(I.valor_total_auditado) AS DECIMAL(19,4)) /
        CAST(SUM(I.total_pacientes_distintos * I.total_meses_ativos) AS DECIMAL(19,4))
    AS DECIMAL(9,2)) AS receita_por_paciente_mensal,
    CAST(COUNT_BIG(*) AS INT) AS qtd_cnpjs
INTO temp_CGUSC.fp.indicador_receita_por_paciente_br
FROM temp_CGUSC.fp.indicador_receita_por_paciente I
GROUP BY
    I.ano_base;

CREATE UNIQUE CLUSTERED INDEX IDX_IndRecPacBR
ON temp_CGUSC.fp.indicador_receita_por_paciente_br(ano_base);
GO


-- ============================================================================
-- LIMPEZA DAS TABELAS INTERMEDIARIAS
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_receita_por_paciente;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_receita_por_paciente_mun;
DROP TABLE IF EXISTS #farmacias_dim;
GO
