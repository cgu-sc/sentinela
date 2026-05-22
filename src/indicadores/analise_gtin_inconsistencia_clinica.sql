USE [temp_CGUSC]
GO

-- ============================================================================
-- ANALISE GTIN X INCONSISTENCIA CLINICA - BASE INTEIRA
-- ============================================================================
-- OBJETIVO: Persistir, para a base inteira, a evolucao anual por
--           farmacia e patologia das
--           dispensacoes associadas as patologias monitoradas na inconsistencia
--           clinica.
--
-- GRANULARIDADE FINAL:
--   id_cnpj + patologia + regra_clinica + ano_base
--
-- ============================================================================

DROP TABLE IF EXISTS temp_CGUSC.fp.analise_gtin_inconsistencia_clinica;
GO

DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim    DATE = '2024-12-10';
DECLARE @InicioProcesso DATETIME2(7) = SYSDATETIME();
DECLARE @InicioEtapa    DATETIME2(7) = @InicioProcesso;
DECLARE @InicioTrecho   DATETIME2(7);
DECLARE @QtdLinhas      INT;
DECLARE @TempoMs        INT;
DECLARE @TempoTrechoMs  INT;

RAISERROR('Inicio analise GTIN inconsistencia clinica teste - SCRIPT: analise_gtin_inconsistencia_clinica_correto.sql.', 0, 1) WITH NOWAIT;

DROP TABLE IF EXISTS #perfil_execucao;

CREATE TABLE #perfil_execucao (
    ordem        INT IDENTITY(1,1) NOT NULL,
    trecho       VARCHAR(160)      NOT NULL,
    linhas       INT               NULL,
    tempo_ms     INT               NOT NULL,
    acumulado_ms INT               NOT NULL,
    dt_registro  DATETIME2(7)      NOT NULL DEFAULT SYSDATETIME()
);


-- ============================================================================
-- PASSO 0: VALIDACOES DE CONTRATO
-- ============================================================================
SET @InicioTrecho = SYSDATETIME();

IF OBJECT_ID('temp_CGUSC.fp.dados_farmacia', 'U') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.dados_farmacia nao encontrada.', 16, 1);
    RETURN;
END;

IF COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'id') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'cnpj') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.dados_farmacia sem colunas obrigatorias id/cnpj.', 16, 1);
    RETURN;
END;

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
    RAISERROR('Tabela db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 sem colunas obrigatorias.', 16, 1);
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

IF EXISTS (
    SELECT 1
    FROM temp_CGUSC.fp.dados_farmacia
    GROUP BY id
    HAVING COUNT_BIG(*) > 1
)
BEGIN
    RAISERROR('Base possui ids duplicados em temp_CGUSC.fp.dados_farmacia.', 16, 1);
    RETURN;
END;

IF EXISTS (
    SELECT 1
    FROM temp_CGUSC.fp.dados_farmacia
    GROUP BY cnpj
    HAVING COUNT_BIG(*) > 1
)
BEGIN
    RAISERROR('Base possui CNPJs duplicados em temp_CGUSC.fp.dados_farmacia.', 16, 1);
    RETURN;
END;

SET @TempoMs = DATEDIFF(MILLISECOND, @InicioEtapa, SYSDATETIME());
INSERT INTO #perfil_execucao (trecho, linhas, tempo_ms, acumulado_ms)
VALUES ('PASSO 0 - validacoes de contrato', NULL, @TempoMs, DATEDIFF(MILLISECOND, @InicioProcesso, SYSDATETIME()));
RAISERROR('Tempo PASSO 0 - validacoes de contrato: %d ms', 0, 1, @TempoMs) WITH NOWAIT;

-- ============================================================================
-- PASSO 1: DIMENSOES DE APOIO
-- ============================================================================
SET @InicioEtapa = SYSDATETIME();

SET @InicioTrecho = SYSDATETIME();

DROP TABLE IF EXISTS #farmacias_municipio;

SELECT
    F.id AS id_cnpj,
    F.cnpj
INTO #farmacias_municipio
FROM temp_CGUSC.fp.dados_farmacia F;

SET @QtdLinhas = @@ROWCOUNT;
SET @TempoTrechoMs = DATEDIFF(MILLISECOND, @InicioTrecho, SYSDATETIME());
INSERT INTO #perfil_execucao (trecho, linhas, tempo_ms, acumulado_ms)
VALUES ('PASSO 1A.1 - carregar farmacias da base', @QtdLinhas, @TempoTrechoMs, DATEDIFF(MILLISECOND, @InicioProcesso, SYSDATETIME()));
RAISERROR('Tempo PASSO 1A.1 - carregar farmacias da base: %d ms | linhas: %d', 0, 1, @TempoTrechoMs, @QtdLinhas) WITH NOWAIT;

SET @InicioTrecho = SYSDATETIME();
IF EXISTS (
    SELECT 1
    FROM #farmacias_municipio
    WHERE id_cnpj IS NULL
       OR cnpj IS NULL
)
BEGIN
    RAISERROR('Base possui farmacia com id/cnpj obrigatorio nulo.', 16, 1);
    RETURN;
END;
SET @TempoTrechoMs = DATEDIFF(MILLISECOND, @InicioTrecho, SYSDATETIME());
INSERT INTO #perfil_execucao (trecho, linhas, tempo_ms, acumulado_ms)
VALUES ('PASSO 1A.2 - validar farmacias obrigatorias', NULL, @TempoTrechoMs, DATEDIFF(MILLISECOND, @InicioProcesso, SYSDATETIME()));
RAISERROR('Tempo PASSO 1A.2 - validar farmacias obrigatorias: %d ms', 0, 1, @TempoTrechoMs) WITH NOWAIT;

SET @TempoMs = DATEDIFF(MILLISECOND, @InicioEtapa, SYSDATETIME());
INSERT INTO #perfil_execucao (trecho, linhas, tempo_ms, acumulado_ms)
VALUES ('PASSO 1A - total farmacias da base', @QtdLinhas, @TempoMs, DATEDIFF(MILLISECOND, @InicioProcesso, SYSDATETIME()));
RAISERROR('Tempo PASSO 1A - farmacias da base: %d ms | linhas: %d', 0, 1, @TempoMs, @QtdLinhas) WITH NOWAIT;

SET @InicioEtapa = SYSDATETIME();
SET @InicioTrecho = SYSDATETIME();

DROP TABLE IF EXISTS #medicamentos_clinicos;

SELECT DISTINCT
    M.codigo_barra,
    M.Patologia AS patologia,
    CASE
        WHEN M.Patologia = 'OSTEOPOROSE'
            THEN 'SEXO_MASCULINO'
        WHEN M.Patologia = 'DIABETES'
            THEN 'IDADE_MENOR_20'
        WHEN M.Patologia = 'DOENCA DE PARKINSON'
            THEN 'IDADE_MENOR_50'
        WHEN M.Patologia = 'HIPERTENSAO'
            THEN 'IDADE_MENOR_20'
    END AS regra_clinica
INTO #medicamentos_clinicos
FROM temp_CGUSC.fp.medicamentos_patologia M
WHERE M.codigo_barra IS NOT NULL
  AND M.Patologia IN ('OSTEOPOROSE', 'DIABETES', 'DOENCA DE PARKINSON', 'HIPERTENSAO');

SET @QtdLinhas = @@ROWCOUNT;
SET @TempoTrechoMs = DATEDIFF(MILLISECOND, @InicioTrecho, SYSDATETIME());
INSERT INTO #perfil_execucao (trecho, linhas, tempo_ms, acumulado_ms)
VALUES ('PASSO 1B.1 - carregar medicamentos clinicos', @QtdLinhas, @TempoTrechoMs, DATEDIFF(MILLISECOND, @InicioProcesso, SYSDATETIME()));
RAISERROR('Tempo PASSO 1B.1 - carregar medicamentos clinicos: %d ms | linhas: %d', 0, 1, @TempoTrechoMs, @QtdLinhas) WITH NOWAIT;

SET @InicioTrecho = SYSDATETIME();
IF NOT EXISTS (SELECT 1 FROM #medicamentos_clinicos)
BEGIN
    RAISERROR('Nao ha medicamentos clinicos monitorados em temp_CGUSC.fp.medicamentos_patologia.', 16, 1);
    RETURN;
END;

IF EXISTS (
    SELECT 1
    FROM #medicamentos_clinicos
    GROUP BY codigo_barra
    HAVING COUNT_BIG(*) > 1
)
BEGIN
    RAISERROR('Um mesmo GTIN esta associado a mais de uma patologia monitorada.', 16, 1);
    RETURN;
END;
SET @TempoTrechoMs = DATEDIFF(MILLISECOND, @InicioTrecho, SYSDATETIME());
INSERT INTO #perfil_execucao (trecho, linhas, tempo_ms, acumulado_ms)
VALUES ('PASSO 1B.2 - validar medicamentos clinicos', NULL, @TempoTrechoMs, DATEDIFF(MILLISECOND, @InicioProcesso, SYSDATETIME()));
RAISERROR('Tempo PASSO 1B.2 - validar medicamentos clinicos: %d ms', 0, 1, @TempoTrechoMs) WITH NOWAIT;

SET @InicioTrecho = SYSDATETIME();
CREATE UNIQUE CLUSTERED INDEX CX_medicamentos_clinicos
ON #medicamentos_clinicos(codigo_barra);
SET @TempoTrechoMs = DATEDIFF(MILLISECOND, @InicioTrecho, SYSDATETIME());
INSERT INTO #perfil_execucao (trecho, linhas, tempo_ms, acumulado_ms)
VALUES ('PASSO 1B.3 - indice clustered medicamentos por gtin', NULL, @TempoTrechoMs, DATEDIFF(MILLISECOND, @InicioProcesso, SYSDATETIME()));
RAISERROR('Tempo PASSO 1B.3 - indice clustered medicamentos por gtin: %d ms', 0, 1, @TempoTrechoMs) WITH NOWAIT;

SET @TempoMs = DATEDIFF(MILLISECOND, @InicioEtapa, SYSDATETIME());
INSERT INTO #perfil_execucao (trecho, linhas, tempo_ms, acumulado_ms)
VALUES ('PASSO 1B - total medicamentos clinicos', @QtdLinhas, @TempoMs, DATEDIFF(MILLISECOND, @InicioProcesso, SYSDATETIME()));
RAISERROR('Tempo PASSO 1B - medicamentos clinicos: %d ms | linhas: %d', 0, 1, @TempoMs, @QtdLinhas) WITH NOWAIT;

-- ============================================================================
-- PASSO 2: MOVIMENTOS MONITORADOS DA BASE
-- ============================================================================
SET @InicioEtapa = SYSDATETIME();
SET @InicioTrecho = SYSDATETIME();

DROP TABLE IF EXISTS #movimentos_monitorados;

SELECT
    F.id_cnpj,
    M.patologia,
    M.regra_clinica,
    CAST(YEAR(A.data_hora) AS SMALLINT) AS ano_base,
    A.cpf,
    B.CPF AS cpf_encontrado,
    B.idSexo,
    B.dataNascimento,
    A.num_autorizacao,
    A.valor_pago,
    A.data_hora
INTO #movimentos_monitorados
FROM #farmacias_municipio F
INNER JOIN db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
    ON F.cnpj = A.cnpj
INNER JOIN #medicamentos_clinicos M
    ON M.codigo_barra = A.codigo_barra
LEFT JOIN db_CPF.dbo.CPF B
    ON B.CPF = A.cpf
WHERE A.data_hora >= @DataInicio
  AND A.data_hora < DATEADD(DAY, 1, @DataFim);

SET @QtdLinhas = @@ROWCOUNT;
SET @TempoTrechoMs = DATEDIFF(MILLISECOND, @InicioTrecho, SYSDATETIME());
INSERT INTO #perfil_execucao (trecho, linhas, tempo_ms, acumulado_ms)
VALUES ('PASSO 2.1 - carregar movimentos monitorados', @QtdLinhas, @TempoTrechoMs, DATEDIFF(MILLISECOND, @InicioProcesso, SYSDATETIME()));
RAISERROR('Tempo PASSO 2.1 - carregar movimentos monitorados: %d ms | linhas: %d', 0, 1, @TempoTrechoMs, @QtdLinhas) WITH NOWAIT;

SET @InicioTrecho = SYSDATETIME();
IF NOT EXISTS (SELECT 1 FROM #movimentos_monitorados)
BEGIN
    RAISERROR('Nao ha itens monitorados para a base no periodo.', 16, 1);
    RETURN;
END;

IF EXISTS (
    SELECT 1
    FROM #movimentos_monitorados
    WHERE cpf IS NULL
       OR num_autorizacao IS NULL
       OR valor_pago IS NULL
       OR patologia IS NULL
)
BEGIN
    RAISERROR('Existem itens monitorados sem CPF, autorizacao, valor_pago ou patologia obrigatoria.', 16, 1);
    RETURN;
END;

IF EXISTS (
    SELECT 1
    FROM #movimentos_monitorados
    WHERE cpf_encontrado IS NULL
)
BEGIN
    RAISERROR('Existem CPFs monitorados sem correspondencia em db_CPF.dbo.CPF.', 16, 1);
    RETURN;
END;

IF EXISTS (
    SELECT 1
    FROM (
        SELECT DISTINCT
            cpf
        FROM #movimentos_monitorados M
    ) M
    INNER JOIN db_CPF.dbo.CPF B
        ON B.CPF = M.cpf
    GROUP BY B.CPF
    HAVING COUNT_BIG(*) > 1
)
BEGIN
    RAISERROR('Existem CPFs duplicados em db_CPF.dbo.CPF para a base monitorada.', 16, 1);
    RETURN;
END;
SET @TempoTrechoMs = DATEDIFF(MILLISECOND, @InicioTrecho, SYSDATETIME());
INSERT INTO #perfil_execucao (trecho, linhas, tempo_ms, acumulado_ms)
VALUES ('PASSO 2.2 - validar movimentos monitorados', NULL, @TempoTrechoMs, DATEDIFF(MILLISECOND, @InicioProcesso, SYSDATETIME()));
RAISERROR('Tempo PASSO 2.2 - validar movimentos monitorados: %d ms', 0, 1, @TempoTrechoMs) WITH NOWAIT;

SET @TempoMs = DATEDIFF(MILLISECOND, @InicioEtapa, SYSDATETIME());
INSERT INTO #perfil_execucao (trecho, linhas, tempo_ms, acumulado_ms)
VALUES ('PASSO 2 - total movimentos monitorados', @QtdLinhas, @TempoMs, DATEDIFF(MILLISECOND, @InicioProcesso, SYSDATETIME()));
RAISERROR('Tempo PASSO 2 - movimentos monitorados: %d ms | linhas: %d', 0, 1, @TempoMs, @QtdLinhas) WITH NOWAIT;

-- ============================================================================
-- PASSO 3: BASE COM FLAG CLINICA
-- ============================================================================
SET @InicioEtapa = SYSDATETIME();
SET @InicioTrecho = SYSDATETIME();

DROP TABLE IF EXISTS #base_itens;

SELECT
    M.id_cnpj,
    M.patologia,
    M.regra_clinica,
    M.ano_base,
    M.cpf,
    M.num_autorizacao,
    M.valor_pago,
    CAST(
        CASE
            WHEN M.patologia = 'OSTEOPOROSE'
                 AND M.idSexo = 'M'
                THEN 1
            WHEN M.patologia = 'DIABETES'
                 AND M.dataNascimento > DATEADD(YEAR, -20, M.data_hora)
                THEN 1
            WHEN M.patologia = 'DOENCA DE PARKINSON'
                 AND M.dataNascimento > DATEADD(YEAR, -50, M.data_hora)
                THEN 1
            WHEN M.patologia = 'HIPERTENSAO'
                 AND M.dataNascimento > DATEADD(YEAR, -20, M.data_hora)
                THEN 1
            ELSE 0
        END AS BIT
    ) AS flag_incompativel
INTO #base_itens
FROM #movimentos_monitorados M;

SET @QtdLinhas = @@ROWCOUNT;
SET @TempoTrechoMs = DATEDIFF(MILLISECOND, @InicioTrecho, SYSDATETIME());
INSERT INTO #perfil_execucao (trecho, linhas, tempo_ms, acumulado_ms)
VALUES ('PASSO 3C.1 - carregar base itens com flag clinica', @QtdLinhas, @TempoTrechoMs, DATEDIFF(MILLISECOND, @InicioProcesso, SYSDATETIME()));
RAISERROR('Tempo PASSO 3C.1 - carregar base itens com flag clinica: %d ms | linhas: %d', 0, 1, @TempoTrechoMs, @QtdLinhas) WITH NOWAIT;

SET @InicioTrecho = SYSDATETIME();
IF EXISTS (
    SELECT 1
    FROM #movimentos_monitorados
    WHERE patologia IN ('DIABETES', 'DOENCA DE PARKINSON', 'HIPERTENSAO')
      AND dataNascimento IS NULL
)
BEGIN
    RAISERROR('Existem itens monitorados sem dataNascimento para regra clinica por idade.', 16, 1);
    RETURN;
END;

IF EXISTS (
    SELECT 1
    FROM #movimentos_monitorados
    WHERE patologia = 'OSTEOPOROSE'
      AND idSexo IS NULL
)
BEGIN
    RAISERROR('Existem itens monitorados sem idSexo para regra clinica de osteoporose.', 16, 1);
    RETURN;
END;
SET @TempoTrechoMs = DATEDIFF(MILLISECOND, @InicioTrecho, SYSDATETIME());
INSERT INTO #perfil_execucao (trecho, linhas, tempo_ms, acumulado_ms)
VALUES ('PASSO 3C.2 - validar dados clinicos obrigatorios', NULL, @TempoTrechoMs, DATEDIFF(MILLISECOND, @InicioProcesso, SYSDATETIME()));
RAISERROR('Tempo PASSO 3C.2 - validar dados clinicos obrigatorios: %d ms', 0, 1, @TempoTrechoMs) WITH NOWAIT;

SET @InicioTrecho = SYSDATETIME();

CREATE CLUSTERED INDEX CX_base_itens
ON #base_itens(id_cnpj, patologia, regra_clinica, ano_base);

SET @TempoTrechoMs = DATEDIFF(MILLISECOND, @InicioTrecho, SYSDATETIME());
INSERT INTO #perfil_execucao (trecho, linhas, tempo_ms, acumulado_ms)
VALUES ('PASSO 3C.3 - indice clustered base itens', NULL, @TempoTrechoMs, DATEDIFF(MILLISECOND, @InicioProcesso, SYSDATETIME()));
RAISERROR('Tempo PASSO 3C.3 - indice clustered base itens: %d ms', 0, 1, @TempoTrechoMs) WITH NOWAIT;

SET @TempoMs = DATEDIFF(MILLISECOND, @InicioEtapa, SYSDATETIME());
INSERT INTO #perfil_execucao (trecho, linhas, tempo_ms, acumulado_ms)
VALUES ('PASSO 3C - total base itens com flag clinica', @QtdLinhas, @TempoMs, DATEDIFF(MILLISECOND, @InicioProcesso, SYSDATETIME()));
RAISERROR('Tempo PASSO 3C - base itens com flag clinica: %d ms | linhas: %d', 0, 1, @TempoMs, @QtdLinhas) WITH NOWAIT;

-- ============================================================================
-- PASSO 4: PERSISTENCIA AGREGADA UNICA
-- ============================================================================
SET @InicioEtapa = SYSDATETIME();
SET @InicioTrecho = SYSDATETIME();

SELECT
    id_cnpj,
    patologia,
    regra_clinica,
    ano_base,
    CAST(COUNT(DISTINCT cpf) AS INT) AS qtd_cpfs_distintos,
    CAST(COUNT(DISTINCT CASE WHEN flag_incompativel = 1 THEN cpf END) AS INT) AS qtd_cpfs_incompativeis,
    CAST(COUNT(DISTINCT num_autorizacao) AS INT) AS qtd_autorizacoes,
    CAST(COUNT(DISTINCT CASE WHEN flag_incompativel = 1 THEN num_autorizacao END) AS INT) AS qtd_autorizacoes_incompativeis,
    CAST(SUM(valor_pago) AS DECIMAL(19,2)) AS valor_total_pago,
    CAST(
        SUM(
            CASE
                WHEN flag_incompativel = 1 THEN valor_pago
                ELSE CAST(0 AS DECIMAL(19,2))
            END
        ) AS DECIMAL(19,2)
    ) AS valor_incompativel_pago,
    SYSDATETIME() AS dt_processamento
INTO temp_CGUSC.fp.analise_gtin_inconsistencia_clinica
FROM #base_itens
GROUP BY
    id_cnpj,
    patologia,
    regra_clinica,
    ano_base;

SET @QtdLinhas = @@ROWCOUNT;
SET @TempoTrechoMs = DATEDIFF(MILLISECOND, @InicioTrecho, SYSDATETIME());
INSERT INTO #perfil_execucao (trecho, linhas, tempo_ms, acumulado_ms)
VALUES ('PASSO 4.1 - persistencia agregada unica', @QtdLinhas, @TempoTrechoMs, DATEDIFF(MILLISECOND, @InicioProcesso, SYSDATETIME()));
RAISERROR('Tempo PASSO 4.1 - persistencia agregada unica: %d ms | linhas: %d', 0, 1, @TempoTrechoMs, @QtdLinhas) WITH NOWAIT;

SET @TempoMs = DATEDIFF(MILLISECOND, @InicioEtapa, SYSDATETIME());
INSERT INTO #perfil_execucao (trecho, linhas, tempo_ms, acumulado_ms)
VALUES ('PASSO 4 - total persistencia agregada unica', @QtdLinhas, @TempoMs, DATEDIFF(MILLISECOND, @InicioProcesso, SYSDATETIME()));
RAISERROR('Tempo PASSO 4 - persistencia agregada unica: %d ms | linhas: %d', 0, 1, @TempoMs, @QtdLinhas) WITH NOWAIT;

SET @InicioEtapa = SYSDATETIME();

DROP TABLE IF EXISTS #base_itens;
DROP TABLE IF EXISTS #movimentos_monitorados;
DROP TABLE IF EXISTS #medicamentos_clinicos;
DROP TABLE IF EXISTS #farmacias_municipio;

SET @TempoMs = DATEDIFF(MILLISECOND, @InicioEtapa, SYSDATETIME());
INSERT INTO #perfil_execucao (trecho, linhas, tempo_ms, acumulado_ms)
VALUES ('LIMPEZA - temp tables do processamento', NULL, @TempoMs, DATEDIFF(MILLISECOND, @InicioProcesso, SYSDATETIME()));
RAISERROR('Tempo limpeza temp tables: %d ms', 0, 1, @TempoMs) WITH NOWAIT;

SET @TempoMs = DATEDIFF(MILLISECOND, @InicioProcesso, SYSDATETIME());
INSERT INTO #perfil_execucao (trecho, linhas, tempo_ms, acumulado_ms)
VALUES ('TOTAL - analise GTIN inconsistencia clinica teste', NULL, @TempoMs, @TempoMs);
RAISERROR('Tempo total analise GTIN inconsistencia clinica teste: %d ms', 0, 1, @TempoMs) WITH NOWAIT;

DROP TABLE IF EXISTS #perfil_execucao;
GO
