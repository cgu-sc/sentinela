USE [temp_CGUSC]
GO

IF OBJECT_ID('temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_regiao_controle', 'U') IS NOT NULL
   AND COL_LENGTH('temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_regiao_controle', 'qtd_linhas_regiao') IS NULL
BEGIN
    ALTER TABLE temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_regiao_controle
    ADD qtd_linhas_regiao INT NULL;
END;
GO

-- ============================================================================
-- ANALISE GTIN X INCONSISTENCIA CLINICA - PROCESSAMENTO POR REGIAO DE SAUDE
-- ============================================================================
-- OBJETIVO: Processar a base de movimentacao por id_regiao_saude, lendo cada
--           recorte regional uma unica vez e materializando, a partir da mesma
--           base temporaria, os agregados por CNPJ, municipio, regiao e
--           contexto regional por CNPJ com ranking, percentis, participacao
--           regional e excesso observado contra esperado.
--
-- SAIDAS:
--   temp_CGUSC.fp.analise_gtin_inconsistencia_clinica
--   temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_municipio
--   temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_regiao
--
-- CHECKPOINT:
--   temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_regiao_controle
--
-- PERFORMANCE:
--   - Processamento incremental por regiao de saude.
--   - Recortes regionais materializados em #temp tables.
--   - Indices em tabelas temporarias antes das agregacoes.
--   - CPFs da regiao deduplicados antes do join com db_CPF.dbo.CPF.
-- ============================================================================

DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim    DATE = '2024-12-10';
DECLARE @PipelineVersao VARCHAR(40) = 'v1_2026_05_23';
DECLARE @RegiaoSaudeAlvo BIGINT = 31007;
DECLARE @ResetResultados BIT = 0;

DECLARE @InicioProcesso DATETIME2(7) = SYSDATETIME();
DECLARE @InicioEtapa    DATETIME2(7) = @InicioProcesso;
DECLARE @InicioTrecho   DATETIME2(7);
DECLARE @QtdLinhas      INT;
DECLARE @TempoMs        INT;
DECLARE @TempoTrechoMs  INT;
DECLARE @IdRegiaoSaude  BIGINT;
DECLARE @LoteNum        INT = 0;
DECLARE @QtdRegioesOk   INT = 0;
DECLARE @QtdCnpjs       INT;
DECLARE @QtdMunicipios  INT;
DECLARE @QtdCpfs        INT;
DECLARE @QtdMovimentos  BIGINT;
DECLARE @QtdBaseItens   BIGINT;
DECLARE @QtdLinhasCnpj  INT;
DECLARE @QtdLinhasMunicipio INT;
DECLARE @QtdLinhasRegiao INT;
DECLARE @QtdLinhasRegional INT;

RAISERROR('Inicio analise GTIN inconsistencia clinica por regiao de saude.', 0, 1) WITH NOWAIT;

DROP TABLE IF EXISTS #perfil_execucao;

CREATE TABLE #perfil_execucao (
    ordem        INT IDENTITY(1,1) NOT NULL,
    trecho       VARCHAR(160)      NOT NULL,
    id_regiao_saude BIGINT         NULL,
    linhas       BIGINT            NULL,
    tempo_ms     INT               NOT NULL,
    acumulado_ms INT               NOT NULL,
    dt_registro  DATETIME2(7)      NOT NULL DEFAULT SYSDATETIME()
);

-- ============================================================================
-- PASSO 0: VALIDACOES E ESTRUTURA PERSISTENTE
-- ============================================================================
SET @InicioEtapa = SYSDATETIME();

IF OBJECT_ID('temp_CGUSC.fp.dados_farmacia', 'U') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.dados_farmacia nao encontrada.', 16, 1);
    RETURN;
END;

IF COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'id') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'cnpj') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'codibge') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'id_regiao_saude') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.dados_farmacia sem colunas obrigatorias id/cnpj/codibge/id_regiao_saude.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('temp_CGUSC.fp.medicamentos_patologia', 'U') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.medicamentos_patologia nao encontrada.', 16, 1);
    RETURN;
END;

IF COL_LENGTH('temp_CGUSC.fp.medicamentos_patologia', 'codigo_barra') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.medicamentos_patologia', 'Patologia') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.medicamentos_patologia', 'qnt_comprimidos_caixa') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.medicamentos_patologia sem colunas obrigatorias codigo_barra/Patologia/qnt_comprimidos_caixa.', 16, 1);
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
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'qnt_autorizada') IS NULL
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

IF EXISTS (
    SELECT 1
    FROM temp_CGUSC.fp.dados_farmacia
    WHERE codibge IS NOT NULL
      AND id_regiao_saude IS NOT NULL
    GROUP BY codibge
    HAVING COUNT(DISTINCT id_regiao_saude) > 1
)
BEGIN
    RAISERROR('Base possui municipio associado a mais de uma regiao de saude em temp_CGUSC.fp.dados_farmacia.', 16, 1);
    RETURN;
END;

IF @ResetResultados = 1
BEGIN
    DROP TABLE IF EXISTS temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_regiao_controle;
    DROP TABLE IF EXISTS temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_regional;
    DROP TABLE IF EXISTS temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_cnpj_benchmark_regional;
    DROP TABLE IF EXISTS temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_regiao;
    DROP TABLE IF EXISTS temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_municipio;
    DROP TABLE IF EXISTS temp_CGUSC.fp.analise_gtin_inconsistencia_clinica;
END;

IF OBJECT_ID('temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_municipio', 'U') IS NULL
BEGIN
    CREATE TABLE temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_municipio (
        id_ibge7 CHAR(7) NOT NULL,
        patologia VARCHAR(100) NOT NULL,
        regra_clinica VARCHAR(40) NOT NULL,
        ano_base SMALLINT NOT NULL,
        qtd_cpfs_distintos_municipio INT NOT NULL,
        qtd_cpfs_incompativeis_municipio INT NOT NULL,
        qtd_autorizacoes_municipio INT NOT NULL,
        qtd_autorizacoes_incompativeis_municipio INT NOT NULL,
        valor_total_pago_municipio DECIMAL(19,2) NOT NULL,
        valor_incompativel_pago_municipio DECIMAL(19,2) NOT NULL,
        dt_processamento DATETIME2(7) NOT NULL
    );
END;

IF OBJECT_ID('temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_regiao', 'U') IS NULL
BEGIN
    CREATE TABLE temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_regiao (
        id_regiao_saude BIGINT NOT NULL,
        patologia VARCHAR(100) NOT NULL,
        regra_clinica VARCHAR(40) NOT NULL,
        ano_base SMALLINT NOT NULL,
        qtd_cnpjs_regiao INT NOT NULL,
        qtd_municipios_regiao INT NOT NULL,
        qtd_cpfs_distintos_regiao INT NOT NULL,
        qtd_cpfs_incompativeis_regiao INT NOT NULL,
        qtd_autorizacoes_regiao INT NOT NULL,
        qtd_autorizacoes_incompativeis_regiao INT NOT NULL,
        valor_total_pago_regiao DECIMAL(19,2) NOT NULL,
        valor_incompativel_pago_regiao DECIMAL(19,2) NOT NULL,
        percentual_cpfs_incompativeis_regiao DECIMAL(9,6) NULL,
        dt_processamento DATETIME2(7) NOT NULL
    );
END;

IF OBJECT_ID('temp_CGUSC.fp.analise_gtin_inconsistencia_clinica', 'U') IS NULL
BEGIN
    CREATE TABLE temp_CGUSC.fp.analise_gtin_inconsistencia_clinica (
        id_cnpj INT NOT NULL,
        id_regiao_saude BIGINT NOT NULL,
        id_ibge7 CHAR(7) NOT NULL,
        patologia VARCHAR(100) NOT NULL,
        regra_clinica VARCHAR(40) NOT NULL,
        ano_base SMALLINT NOT NULL,
        qtd_cpfs_distintos INT NOT NULL,
        qtd_cpfs_incompativeis INT NOT NULL,
        qtd_autorizacoes INT NOT NULL,
        qtd_autorizacoes_incompativeis INT NOT NULL,
        valor_total_pago DECIMAL(19,2) NOT NULL,
        valor_incompativel_pago DECIMAL(19,2) NOT NULL,
        percentual_cpfs_incompativeis DECIMAL(9,6) NULL,
        rank_regional_qtd_cpfs_incompativeis INT NULL,
        rank_regional_valor_incompativel_pago INT NULL,
        percentil_regional_qtd_cpfs_incompativeis DECIMAL(9,6) NULL,
        percentil_regional_valor_incompativel_pago DECIMAL(9,6) NULL,
        participacao_cpfs_incompativeis_regiao DECIMAL(9,6) NULL,
        participacao_valor_incompativel_regiao DECIMAL(9,6) NULL,
        percentual_regional_cpfs_incompativeis DECIMAL(9,6) NULL,
        razao_percentual_vs_regiao DECIMAL(19,6) NULL,
        cpfs_incompativeis_esperados_regiao DECIMAL(19,6) NULL,
        excesso_cpfs_incompativeis_vs_regiao DECIMAL(19,6) NULL,
        dt_processamento DATETIME2(7) NOT NULL
    );
END;

IF OBJECT_ID('temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_regiao_controle', 'U') IS NULL
BEGIN
    CREATE TABLE temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_regiao_controle (
        id_regiao_saude BIGINT NOT NULL,
        pipeline_versao VARCHAR(40) NOT NULL,
        dt_data_inicio DATE NOT NULL,
        dt_data_fim DATE NOT NULL,
        status VARCHAR(20) NOT NULL,
        etapa VARCHAR(80) NULL,
        dt_inicio DATETIME2(7) NULL,
        dt_fim DATETIME2(7) NULL,
        qtd_cnpjs INT NULL,
        qtd_municipios INT NULL,
        qtd_movimentos BIGINT NULL,
        qtd_base_itens BIGINT NULL,
        qtd_linhas_cnpj INT NULL,
        qtd_linhas_municipio INT NULL,
        qtd_linhas_regiao INT NULL,
        qtd_linhas_regional INT NULL,
        mensagem_erro NVARCHAR(4000) NULL,
        dt_erro DATETIME2(7) NULL,
        CONSTRAINT PK_AnaliseGtinInconsistenciaClinicaRegiaoControle
            PRIMARY KEY CLUSTERED (id_regiao_saude, pipeline_versao, dt_data_inicio, dt_data_fim)
    );
END;

IF COL_LENGTH('temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_regiao_controle', 'qtd_linhas_regiao') IS NULL
BEGIN
    ALTER TABLE temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_regiao_controle
    ADD qtd_linhas_regiao INT NULL;
END;

IF COL_LENGTH('temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_regiao', 'percentual_cpfs_incompativeis_regiao') IS NULL
BEGIN
    RAISERROR('Tabela analise_gtin_inconsistencia_clinica_regiao existe com schema antigo. Recrie a tabela para a versao atual.', 16, 1);
    RETURN;
END;

IF COL_LENGTH('temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_regiao', 'mediana_regional_cpfs_incompativeis') IS NOT NULL
   OR COL_LENGTH('temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_regiao', 'mad_regional_cpfs_incompativeis') IS NOT NULL
   OR COL_LENGTH('temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_regiao', 'flag_mad_zero_regional') IS NOT NULL
BEGIN
    RAISERROR('Tabela analise_gtin_inconsistencia_clinica_regiao existe com colunas de benchmark. Recrie a tabela para a versao atual.', 16, 1);
    RETURN;
END;

IF COL_LENGTH('temp_CGUSC.fp.analise_gtin_inconsistencia_clinica', 'rank_regional_qtd_cpfs_incompativeis') IS NULL
BEGIN
    RAISERROR('Tabela analise_gtin_inconsistencia_clinica existe com schema antigo. Recrie a tabela para a versao atual.', 16, 1);
    RETURN;
END;

IF EXISTS (
    SELECT 1
    FROM sys.columns
    WHERE object_id = OBJECT_ID('temp_CGUSC.fp.analise_gtin_inconsistencia_clinica')
      AND name IN ('rank_regional_qtd_cpfs_incompativeis', 'rank_regional_valor_incompativel_pago')
      AND is_nullable = 0
)
BEGIN
    RAISERROR('Tabela analise_gtin_inconsistencia_clinica existe com ranks NOT NULL. Recrie a tabela para a versao atual.', 16, 1);
    RETURN;
END;

IF COL_LENGTH('temp_CGUSC.fp.analise_gtin_inconsistencia_clinica', 'modified_z_score_cpfs_incompativeis') IS NOT NULL
   OR COL_LENGTH('temp_CGUSC.fp.analise_gtin_inconsistencia_clinica', 'mediana_regional_cpfs_incompativeis') IS NOT NULL
   OR COL_LENGTH('temp_CGUSC.fp.analise_gtin_inconsistencia_clinica', 'mad_regional_cpfs_incompativeis') IS NOT NULL
   OR COL_LENGTH('temp_CGUSC.fp.analise_gtin_inconsistencia_clinica', 'flag_mad_zero_regional') IS NOT NULL
BEGIN
    RAISERROR('Tabela analise_gtin_inconsistencia_clinica existe com colunas de z-score/MAD. Recrie a tabela para a versao atual.', 16, 1);
    RETURN;
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_municipio')
      AND name = 'IX_AnaliseGtinClinicaMunicipio'
)
BEGIN
    CREATE INDEX IX_AnaliseGtinClinicaMunicipio
        ON temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_municipio(id_ibge7, patologia, regra_clinica, ano_base);
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_regiao')
      AND name = 'IX_AnaliseGtinClinicaRegiao'
)
BEGIN
    CREATE INDEX IX_AnaliseGtinClinicaRegiao
        ON temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_regiao(id_regiao_saude, patologia, regra_clinica, ano_base);
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('temp_CGUSC.fp.analise_gtin_inconsistencia_clinica')
      AND name = 'IX_AnaliseGtinClinica_CnpjContextoRegional'
)
BEGIN
    CREATE INDEX IX_AnaliseGtinClinica_CnpjContextoRegional
        ON temp_CGUSC.fp.analise_gtin_inconsistencia_clinica(id_regiao_saude, patologia, regra_clinica, ano_base, id_cnpj);
END;

SET @TempoMs = DATEDIFF(MILLISECOND, @InicioEtapa, SYSDATETIME());
INSERT INTO #perfil_execucao (trecho, id_regiao_saude, linhas, tempo_ms, acumulado_ms)
VALUES ('PASSO 0 - validacoes e estrutura persistente', NULL, NULL, @TempoMs, DATEDIFF(MILLISECOND, @InicioProcesso, SYSDATETIME()));
RAISERROR('Tempo PASSO 0 - validacoes e estrutura persistente: %d ms', 0, 1, @TempoMs) WITH NOWAIT;

-- ============================================================================
-- PASSO 1: DIMENSOES GLOBAIS E FILA DE REGIOES
-- ============================================================================
SET @InicioEtapa = SYSDATETIME();
SET @InicioTrecho = SYSDATETIME();

DROP TABLE IF EXISTS #medicamentos_clinicos;

SELECT DISTINCT
    M.codigo_barra,
    CAST(M.qnt_comprimidos_caixa AS DECIMAL(10,0)) AS qnt_comprimidos_caixa,
    UPPER(LTRIM(RTRIM(M.Patologia))) AS patologia,
    CASE
        WHEN UPPER(LTRIM(RTRIM(M.Patologia))) = 'OSTEOPOROSE'
            THEN 'SEXO_MASCULINO'
        WHEN UPPER(LTRIM(RTRIM(M.Patologia))) = 'DIABETES'
            THEN 'IDADE_MENOR_20'
        WHEN UPPER(LTRIM(RTRIM(M.Patologia))) = 'DOENCA DE PARKINSON'
            THEN 'IDADE_MENOR_50'
        WHEN UPPER(LTRIM(RTRIM(M.Patologia))) = 'HIPERTENSAO'
            THEN 'IDADE_MENOR_20'
    END AS regra_clinica
INTO #medicamentos_clinicos
FROM temp_CGUSC.fp.medicamentos_patologia M
WHERE M.codigo_barra IS NOT NULL
  AND TRY_CAST(M.qnt_comprimidos_caixa AS DECIMAL(10,0)) IS NOT NULL
  AND TRY_CAST(M.qnt_comprimidos_caixa AS DECIMAL(10,0)) <> 0
  AND UPPER(LTRIM(RTRIM(M.Patologia))) IN ('OSTEOPOROSE', 'DIABETES', 'DOENCA DE PARKINSON', 'HIPERTENSAO');

SET @QtdLinhas = @@ROWCOUNT;

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

CREATE UNIQUE CLUSTERED INDEX CX_medicamentos_clinicos
ON #medicamentos_clinicos(codigo_barra);

SET @TempoTrechoMs = DATEDIFF(MILLISECOND, @InicioTrecho, SYSDATETIME());
INSERT INTO #perfil_execucao (trecho, id_regiao_saude, linhas, tempo_ms, acumulado_ms)
VALUES ('PASSO 1A - medicamentos clinicos', NULL, @QtdLinhas, @TempoTrechoMs, DATEDIFF(MILLISECOND, @InicioProcesso, SYSDATETIME()));
RAISERROR('Tempo PASSO 1A - medicamentos clinicos: %d ms | linhas: %d', 0, 1, @TempoTrechoMs, @QtdLinhas) WITH NOWAIT;

INSERT INTO temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_regiao_controle
    (id_regiao_saude, pipeline_versao, dt_data_inicio, dt_data_fim, status, etapa)
SELECT DISTINCT
    CAST(F.id_regiao_saude AS BIGINT),
    @PipelineVersao,
    @DataInicio,
    @DataFim,
    'PENDENTE',
    'AGUARDANDO'
FROM temp_CGUSC.fp.dados_farmacia F
WHERE F.id_regiao_saude IS NOT NULL
  AND (@RegiaoSaudeAlvo IS NULL OR F.id_regiao_saude = @RegiaoSaudeAlvo)
  AND NOT EXISTS (
      SELECT 1
      FROM temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_regiao_controle C
      WHERE C.id_regiao_saude = CAST(F.id_regiao_saude AS BIGINT)
        AND C.pipeline_versao = @PipelineVersao
        AND C.dt_data_inicio = @DataInicio
        AND C.dt_data_fim = @DataFim
  );

UPDATE temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_regiao_controle
SET status = 'PENDENTE',
    etapa = 'RETOMAR_PROCESSAMENTO',
    dt_inicio = NULL,
    dt_fim = NULL,
    mensagem_erro = NULL,
    dt_erro = NULL
WHERE pipeline_versao = @PipelineVersao
  AND dt_data_inicio = @DataInicio
  AND dt_data_fim = @DataFim
  AND status = 'PROCESSANDO'
  AND (@RegiaoSaudeAlvo IS NULL OR id_regiao_saude = @RegiaoSaudeAlvo);

SET @TempoMs = DATEDIFF(MILLISECOND, @InicioEtapa, SYSDATETIME());
INSERT INTO #perfil_execucao (trecho, id_regiao_saude, linhas, tempo_ms, acumulado_ms)
VALUES ('PASSO 1 - fila de regioes', NULL, NULL, @TempoMs, DATEDIFF(MILLISECOND, @InicioProcesso, SYSDATETIME()));
RAISERROR('Tempo PASSO 1 - fila de regioes: %d ms', 0, 1, @TempoMs) WITH NOWAIT;

-- ============================================================================
-- PASSO 2: LOOP POR REGIAO DE SAUDE
-- ============================================================================
WHILE EXISTS (
    SELECT 1
    FROM temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_regiao_controle C
    WHERE C.pipeline_versao = @PipelineVersao
      AND C.dt_data_inicio = @DataInicio
      AND C.dt_data_fim = @DataFim
      AND C.status <> 'OK'
      AND (@RegiaoSaudeAlvo IS NULL OR C.id_regiao_saude = @RegiaoSaudeAlvo)
)
BEGIN
    SELECT TOP 1
        @IdRegiaoSaude = C.id_regiao_saude
    FROM temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_regiao_controle C
    WHERE C.pipeline_versao = @PipelineVersao
      AND C.dt_data_inicio = @DataInicio
      AND C.dt_data_fim = @DataFim
      AND C.status <> 'OK'
      AND (@RegiaoSaudeAlvo IS NULL OR C.id_regiao_saude = @RegiaoSaudeAlvo)
    ORDER BY
        CASE C.status
            WHEN 'ERRO' THEN 1
            WHEN 'PENDENTE' THEN 2
            ELSE 3
        END,
        C.id_regiao_saude;

    SET @LoteNum += 1;
    SET @InicioEtapa = SYSDATETIME();
    SET @QtdCnpjs = 0;
    SET @QtdMunicipios = 0;
    SET @QtdCpfs = 0;
    SET @QtdMovimentos = 0;
    SET @QtdBaseItens = 0;
    SET @QtdLinhasCnpj = 0;
    SET @QtdLinhasMunicipio = 0;
    SET @QtdLinhasRegiao = 0;
    SET @QtdLinhasRegional = 0;

    BEGIN TRY
        RAISERROR('>> Regiao %I64d | lote %d | iniciando...', 0, 1, @IdRegiaoSaude, @LoteNum) WITH NOWAIT;

        UPDATE temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_regiao_controle
        SET status = 'PROCESSANDO',
            etapa = 'CARREGANDO_FARMACIAS',
            dt_inicio = SYSDATETIME(),
            dt_fim = NULL,
            mensagem_erro = NULL,
            dt_erro = NULL
        WHERE id_regiao_saude = @IdRegiaoSaude
          AND pipeline_versao = @PipelineVersao
          AND dt_data_inicio = @DataInicio
          AND dt_data_fim = @DataFim;

        DROP TABLE IF EXISTS #farmacias_regiao;
        DROP TABLE IF EXISTS #municipios_regiao;
        DROP TABLE IF EXISTS #movimentos_raw;
        DROP TABLE IF EXISTS #cpfs_regiao;
        DROP TABLE IF EXISTS #cpf_info;
        DROP TABLE IF EXISTS #base_itens;
        DROP TABLE IF EXISTS #agregado_cnpj_regiao;
        DROP TABLE IF EXISTS #agregado_regiao;

        SET @InicioTrecho = SYSDATETIME();

        SELECT
            F.id AS id_cnpj,
            F.cnpj,
            CAST(F.codibge AS CHAR(7)) AS id_ibge7,
            CAST(F.id_regiao_saude AS BIGINT) AS id_regiao_saude
        INTO #farmacias_regiao
        FROM temp_CGUSC.fp.dados_farmacia F
        WHERE F.id_regiao_saude = @IdRegiaoSaude;

        SET @QtdCnpjs = @@ROWCOUNT;

        IF EXISTS (
            SELECT 1
            FROM #farmacias_regiao
            WHERE id_cnpj IS NULL
               OR cnpj IS NULL
               OR id_ibge7 IS NULL
               OR id_regiao_saude IS NULL
        )
        BEGIN
            RAISERROR('Regiao possui farmacia com id/cnpj/id_ibge7/id_regiao_saude obrigatorio nulo.', 16, 1);
            RETURN;
        END;

        CREATE UNIQUE CLUSTERED INDEX CX_farmacias_regiao_cnpj
        ON #farmacias_regiao(cnpj);

        CREATE NONCLUSTERED INDEX IX_farmacias_regiao_id
        ON #farmacias_regiao(id_cnpj, id_ibge7);

        SELECT DISTINCT id_ibge7
        INTO #municipios_regiao
        FROM #farmacias_regiao;

        SET @QtdMunicipios = @@ROWCOUNT;

        CREATE UNIQUE CLUSTERED INDEX CX_municipios_regiao
        ON #municipios_regiao(id_ibge7);

        SET @TempoTrechoMs = DATEDIFF(MILLISECOND, @InicioTrecho, SYSDATETIME());
        INSERT INTO #perfil_execucao (trecho, id_regiao_saude, linhas, tempo_ms, acumulado_ms)
        VALUES ('PASSO 2A - farmacias da regiao', @IdRegiaoSaude, @QtdCnpjs, @TempoTrechoMs, DATEDIFF(MILLISECOND, @InicioProcesso, SYSDATETIME()));
        RAISERROR('   2A farmacias: %d CNPJs | %d municipios | %d ms', 0, 1, @QtdCnpjs, @QtdMunicipios, @TempoTrechoMs) WITH NOWAIT;

        UPDATE temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_regiao_controle
        SET etapa = 'CARREGANDO_MOVIMENTOS',
            qtd_cnpjs = @QtdCnpjs,
            qtd_municipios = @QtdMunicipios
        WHERE id_regiao_saude = @IdRegiaoSaude
          AND pipeline_versao = @PipelineVersao
          AND dt_data_inicio = @DataInicio
          AND dt_data_fim = @DataFim;

        SET @InicioTrecho = SYSDATETIME();

        SELECT
            F.id_cnpj,
            F.id_regiao_saude,
            F.id_ibge7,
            M.patologia,
            M.regra_clinica,
            CAST(YEAR(A.data_hora) AS SMALLINT) AS ano_base,
            A.cpf,
            A.num_autorizacao,
            A.valor_pago,
            A.data_hora
        INTO #movimentos_raw
        FROM #farmacias_regiao F
        INNER JOIN db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
            ON F.cnpj = A.cnpj
        INNER JOIN #medicamentos_clinicos M
            ON M.codigo_barra = A.codigo_barra
        WHERE A.data_hora >= @DataInicio
          AND A.data_hora < DATEADD(DAY, 1, @DataFim)
          AND A.qnt_autorizada IS NOT NULL
          AND (A.qnt_autorizada / M.qnt_comprimidos_caixa) <> 0;

        SET @QtdMovimentos = @@ROWCOUNT;

        IF EXISTS (
            SELECT 1
            FROM #movimentos_raw
            WHERE cpf IS NULL
               OR num_autorizacao IS NULL
               OR valor_pago IS NULL
               OR patologia IS NULL
        )
        BEGIN
            RAISERROR('Existem itens monitorados sem CPF, autorizacao, valor_pago ou patologia obrigatoria.', 16, 1);
            RETURN;
        END;

        IF @QtdMovimentos = 0
        BEGIN
            DELETE R
            FROM temp_CGUSC.fp.analise_gtin_inconsistencia_clinica R
            WHERE R.id_regiao_saude = @IdRegiaoSaude;

            DELETE R
            FROM temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_regiao R
            WHERE R.id_regiao_saude = @IdRegiaoSaude;

            DELETE M
            FROM temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_municipio M
            INNER JOIN #municipios_regiao F ON F.id_ibge7 = M.id_ibge7;

            UPDATE temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_regiao_controle
            SET status = 'OK',
                etapa = 'SEM_MOVIMENTOS_MONITORADOS',
                dt_fim = SYSDATETIME(),
                qtd_movimentos = 0,
                qtd_base_itens = 0,
                qtd_linhas_cnpj = 0,
                qtd_linhas_municipio = 0,
                qtd_linhas_regiao = 0,
                qtd_linhas_regional = 0
            WHERE id_regiao_saude = @IdRegiaoSaude
              AND pipeline_versao = @PipelineVersao
              AND dt_data_inicio = @DataInicio
              AND dt_data_fim = @DataFim;

            RAISERROR('   Regiao sem movimentos monitorados. Marcada como OK.', 0, 1) WITH NOWAIT;
            CONTINUE;
        END;

        CREATE CLUSTERED INDEX CX_movimentos_raw
        ON #movimentos_raw(id_cnpj, patologia, regra_clinica, ano_base);

        CREATE NONCLUSTERED INDEX IX_movimentos_raw_cpf
        ON #movimentos_raw(cpf);

        SET @TempoTrechoMs = DATEDIFF(MILLISECOND, @InicioTrecho, SYSDATETIME());
        INSERT INTO #perfil_execucao (trecho, id_regiao_saude, linhas, tempo_ms, acumulado_ms)
        VALUES ('PASSO 2B - movimentos monitorados da regiao', @IdRegiaoSaude, @QtdMovimentos, @TempoTrechoMs, DATEDIFF(MILLISECOND, @InicioProcesso, SYSDATETIME()));
        RAISERROR('   2B movimentos: %I64d | %d ms', 0, 1, @QtdMovimentos, @TempoTrechoMs) WITH NOWAIT;

        UPDATE temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_regiao_controle
        SET etapa = 'CARREGANDO_CPFS',
            qtd_movimentos = @QtdMovimentos
        WHERE id_regiao_saude = @IdRegiaoSaude
          AND pipeline_versao = @PipelineVersao
          AND dt_data_inicio = @DataInicio
          AND dt_data_fim = @DataFim;

        SET @InicioTrecho = SYSDATETIME();

        SELECT DISTINCT cpf
        INTO #cpfs_regiao
        FROM #movimentos_raw;

        SET @QtdCpfs = @@ROWCOUNT;

        CREATE UNIQUE CLUSTERED INDEX CX_cpfs_regiao
        ON #cpfs_regiao(cpf);

        SELECT
            B.CPF AS cpf,
            MAX(B.idSexo) AS idSexo,
            MAX(B.dataNascimento) AS dataNascimento,
            COUNT_BIG(*) AS qtd_linhas_cpf
        INTO #cpf_info
        FROM #cpfs_regiao C
        INNER JOIN db_CPF.dbo.CPF B
            ON B.CPF = C.cpf
        GROUP BY B.CPF;

        CREATE UNIQUE CLUSTERED INDEX CX_cpf_info
        ON #cpf_info(cpf);

        IF EXISTS (
            SELECT 1
            FROM #cpf_info
            WHERE qtd_linhas_cpf > 1
        )
        BEGIN
            RAISERROR('Existem CPFs duplicados em db_CPF.dbo.CPF para a base monitorada da regiao.', 16, 1);
            RETURN;
        END;

        SET @TempoTrechoMs = DATEDIFF(MILLISECOND, @InicioTrecho, SYSDATETIME());
        INSERT INTO #perfil_execucao (trecho, id_regiao_saude, linhas, tempo_ms, acumulado_ms)
        VALUES ('PASSO 2C - cpfs da regiao', @IdRegiaoSaude, @QtdCpfs, @TempoTrechoMs, DATEDIFF(MILLISECOND, @InicioProcesso, SYSDATETIME()));
        RAISERROR('   2C CPFs: %d ms | linhas: %d', 0, 1, @TempoTrechoMs, @QtdCpfs) WITH NOWAIT;

        UPDATE temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_regiao_controle
        SET etapa = 'MONTANDO_BASE_ITENS'
        WHERE id_regiao_saude = @IdRegiaoSaude
          AND pipeline_versao = @PipelineVersao
          AND dt_data_inicio = @DataInicio
          AND dt_data_fim = @DataFim;

        SET @InicioTrecho = SYSDATETIME();

        SELECT
            R.id_cnpj,
            R.id_regiao_saude,
            R.id_ibge7,
            R.patologia,
            R.regra_clinica,
            R.ano_base,
            R.cpf,
            R.num_autorizacao,
            R.valor_pago,
            CAST(
                CASE
                    WHEN R.patologia = 'OSTEOPOROSE'
                         AND I.idSexo = 'M'
                        THEN 1
                    WHEN R.patologia = 'DIABETES'
                         AND I.dataNascimento > DATEADD(YEAR, -20, R.data_hora)
                        THEN 1
                    WHEN R.patologia = 'DOENCA DE PARKINSON'
                         AND I.dataNascimento > DATEADD(YEAR, -50, R.data_hora)
                        THEN 1
                    WHEN R.patologia = 'HIPERTENSAO'
                         AND I.dataNascimento > DATEADD(YEAR, -20, R.data_hora)
                        THEN 1
                    ELSE 0
                END AS BIT
            ) AS flag_incompativel
        INTO #base_itens
        FROM #movimentos_raw R
        INNER JOIN #cpf_info I
            ON I.cpf = R.cpf
        WHERE NOT (
                R.patologia IN ('DIABETES', 'DOENCA DE PARKINSON', 'HIPERTENSAO')
                AND I.dataNascimento IS NULL
            )
          AND NOT (
                R.patologia = 'OSTEOPOROSE'
                AND I.idSexo IS NULL
            );

        SET @QtdBaseItens = @@ROWCOUNT;

        CREATE CLUSTERED INDEX CX_base_itens
        ON #base_itens(id_regiao_saude, id_ibge7, id_cnpj, patologia, regra_clinica, ano_base);

        CREATE NONCLUSTERED INDEX IX_base_itens_municipio
        ON #base_itens(id_ibge7, patologia, regra_clinica, ano_base)
        INCLUDE (cpf, num_autorizacao, valor_pago, flag_incompativel);

        SET @TempoTrechoMs = DATEDIFF(MILLISECOND, @InicioTrecho, SYSDATETIME());
        INSERT INTO #perfil_execucao (trecho, id_regiao_saude, linhas, tempo_ms, acumulado_ms)
        VALUES ('PASSO 2D - base itens com flag clinica', @IdRegiaoSaude, @QtdBaseItens, @TempoTrechoMs, DATEDIFF(MILLISECOND, @InicioProcesso, SYSDATETIME()));
        RAISERROR('   2D base itens: %I64d | %d ms', 0, 1, @QtdBaseItens, @TempoTrechoMs) WITH NOWAIT;

        UPDATE temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_regiao_controle
        SET etapa = 'AGREGANDO_CNPJ',
            qtd_base_itens = @QtdBaseItens
        WHERE id_regiao_saude = @IdRegiaoSaude
          AND pipeline_versao = @PipelineVersao
          AND dt_data_inicio = @DataInicio
          AND dt_data_fim = @DataFim;

        SET @InicioTrecho = SYSDATETIME();

        SELECT
            id_cnpj,
            id_regiao_saude,
            id_ibge7,
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
            ) AS valor_incompativel_pago
        INTO #agregado_cnpj_regiao
        FROM #base_itens
        GROUP BY
            id_cnpj,
            id_regiao_saude,
            id_ibge7,
            patologia,
            regra_clinica,
            ano_base;

        SET @QtdLinhasCnpj = @@ROWCOUNT;

        CREATE CLUSTERED INDEX CX_agregado_cnpj_regiao
        ON #agregado_cnpj_regiao(id_regiao_saude, patologia, regra_clinica, ano_base, id_cnpj);

        SET @TempoTrechoMs = DATEDIFF(MILLISECOND, @InicioTrecho, SYSDATETIME());
        INSERT INTO #perfil_execucao (trecho, id_regiao_saude, linhas, tempo_ms, acumulado_ms)
        VALUES ('PASSO 2E - agregado CNPJ temporario', @IdRegiaoSaude, @QtdLinhasCnpj, @TempoTrechoMs, DATEDIFF(MILLISECOND, @InicioProcesso, SYSDATETIME()));
        RAISERROR('   2E agregado CNPJ temp: %d linhas | %d ms', 0, 1, @QtdLinhasCnpj, @TempoTrechoMs) WITH NOWAIT;

        UPDATE temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_regiao_controle
        SET etapa = 'LIMPANDO_SAIDAS_REGIAO',
            qtd_base_itens = @QtdBaseItens,
            qtd_linhas_cnpj = @QtdLinhasCnpj
        WHERE id_regiao_saude = @IdRegiaoSaude
          AND pipeline_versao = @PipelineVersao
          AND dt_data_inicio = @DataInicio
          AND dt_data_fim = @DataFim;

        DELETE R
        FROM temp_CGUSC.fp.analise_gtin_inconsistencia_clinica R
        WHERE R.id_regiao_saude = @IdRegiaoSaude;

        DELETE R
        FROM temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_regiao R
        WHERE R.id_regiao_saude = @IdRegiaoSaude;

        DELETE M
        FROM temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_municipio M
        INNER JOIN #municipios_regiao F ON F.id_ibge7 = M.id_ibge7;

        UPDATE temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_regiao_controle
        SET etapa = 'INSERINDO_MUNICIPIO',
            qtd_linhas_cnpj = @QtdLinhasCnpj
        WHERE id_regiao_saude = @IdRegiaoSaude
          AND pipeline_versao = @PipelineVersao
          AND dt_data_inicio = @DataInicio
          AND dt_data_fim = @DataFim;

        SET @InicioTrecho = SYSDATETIME();

        INSERT INTO temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_municipio
            (id_ibge7, patologia, regra_clinica, ano_base,
             qtd_cpfs_distintos_municipio, qtd_cpfs_incompativeis_municipio,
             qtd_autorizacoes_municipio, qtd_autorizacoes_incompativeis_municipio,
             valor_total_pago_municipio, valor_incompativel_pago_municipio, dt_processamento)
        SELECT
            id_ibge7,
            patologia,
            regra_clinica,
            ano_base,
            CAST(COUNT(DISTINCT cpf) AS INT),
            CAST(COUNT(DISTINCT CASE WHEN flag_incompativel = 1 THEN cpf END) AS INT),
            CAST(COUNT(DISTINCT num_autorizacao) AS INT),
            CAST(COUNT(DISTINCT CASE WHEN flag_incompativel = 1 THEN num_autorizacao END) AS INT),
            CAST(SUM(valor_pago) AS DECIMAL(19,2)),
            CAST(
                SUM(
                    CASE
                        WHEN flag_incompativel = 1 THEN valor_pago
                        ELSE CAST(0 AS DECIMAL(19,2))
                    END
                ) AS DECIMAL(19,2)
            ),
            SYSDATETIME()
        FROM #base_itens
        GROUP BY
            id_ibge7,
            patologia,
            regra_clinica,
            ano_base;

        SET @QtdLinhasMunicipio = @@ROWCOUNT;
        SET @TempoTrechoMs = DATEDIFF(MILLISECOND, @InicioTrecho, SYSDATETIME());
        INSERT INTO #perfil_execucao (trecho, id_regiao_saude, linhas, tempo_ms, acumulado_ms)
        VALUES ('PASSO 2F - insert agregado municipio', @IdRegiaoSaude, @QtdLinhasMunicipio, @TempoTrechoMs, DATEDIFF(MILLISECOND, @InicioProcesso, SYSDATETIME()));
        RAISERROR('   2F municipio: %d linhas | %d ms', 0, 1, @QtdLinhasMunicipio, @TempoTrechoMs) WITH NOWAIT;

        UPDATE temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_regiao_controle
        SET etapa = 'INSERINDO_REGIAO',
            qtd_linhas_municipio = @QtdLinhasMunicipio
        WHERE id_regiao_saude = @IdRegiaoSaude
          AND pipeline_versao = @PipelineVersao
          AND dt_data_inicio = @DataInicio
          AND dt_data_fim = @DataFim;

        SET @InicioTrecho = SYSDATETIME();

        SELECT
            id_regiao_saude,
            patologia,
            regra_clinica,
            ano_base,
            CAST(COUNT(DISTINCT id_cnpj) AS INT) AS qtd_cnpjs_regiao,
            CAST(COUNT(DISTINCT id_ibge7) AS INT) AS qtd_municipios_regiao,
            CAST(COUNT(DISTINCT cpf) AS INT) AS qtd_cpfs_distintos_regiao,
            CAST(COUNT(DISTINCT CASE WHEN flag_incompativel = 1 THEN cpf END) AS INT) AS qtd_cpfs_incompativeis_regiao,
            CAST(COUNT(DISTINCT num_autorizacao) AS INT) AS qtd_autorizacoes_regiao,
            CAST(COUNT(DISTINCT CASE WHEN flag_incompativel = 1 THEN num_autorizacao END) AS INT) AS qtd_autorizacoes_incompativeis_regiao,
            CAST(SUM(valor_pago) AS DECIMAL(19,2)) AS valor_total_pago_regiao,
            CAST(
                SUM(
                    CASE
                        WHEN flag_incompativel = 1 THEN valor_pago
                        ELSE CAST(0 AS DECIMAL(19,2))
                    END
                ) AS DECIMAL(19,2)
            ) AS valor_incompativel_pago_regiao,
            CAST(
                COUNT(DISTINCT CASE WHEN flag_incompativel = 1 THEN cpf END) * 1.0
                / NULLIF(COUNT(DISTINCT cpf), 0)
                AS DECIMAL(9,6)
            ) AS percentual_cpfs_incompativeis_regiao
        INTO #agregado_regiao
        FROM #base_itens
        GROUP BY
            id_regiao_saude,
            patologia,
            regra_clinica,
            ano_base;

        CREATE UNIQUE CLUSTERED INDEX CX_agregado_regiao
        ON #agregado_regiao(id_regiao_saude, patologia, regra_clinica, ano_base);

        INSERT INTO temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_regiao
            (id_regiao_saude, patologia, regra_clinica, ano_base,
             qtd_cnpjs_regiao, qtd_municipios_regiao,
             qtd_cpfs_distintos_regiao, qtd_cpfs_incompativeis_regiao,
             qtd_autorizacoes_regiao, qtd_autorizacoes_incompativeis_regiao,
             valor_total_pago_regiao, valor_incompativel_pago_regiao,
             percentual_cpfs_incompativeis_regiao,
             dt_processamento)
        SELECT
            id_regiao_saude,
            patologia,
            regra_clinica,
            ano_base,
            qtd_cnpjs_regiao,
            qtd_municipios_regiao,
            qtd_cpfs_distintos_regiao,
            qtd_cpfs_incompativeis_regiao,
            qtd_autorizacoes_regiao,
            qtd_autorizacoes_incompativeis_regiao,
            valor_total_pago_regiao,
            valor_incompativel_pago_regiao,
            percentual_cpfs_incompativeis_regiao,
            SYSDATETIME()
        FROM #agregado_regiao;

        SET @QtdLinhasRegiao = @@ROWCOUNT;
        SET @TempoTrechoMs = DATEDIFF(MILLISECOND, @InicioTrecho, SYSDATETIME());
        INSERT INTO #perfil_execucao (trecho, id_regiao_saude, linhas, tempo_ms, acumulado_ms)
        VALUES ('PASSO 2G - insert agregado regiao', @IdRegiaoSaude, @QtdLinhasRegiao, @TempoTrechoMs, DATEDIFF(MILLISECOND, @InicioProcesso, SYSDATETIME()));
        RAISERROR('   2G regiao: %d linhas | %d ms', 0, 1, @QtdLinhasRegiao, @TempoTrechoMs) WITH NOWAIT;

        UPDATE temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_regiao_controle
        SET etapa = 'INSERINDO_CNPJ_CONTEXTO_REGIONAL',
            qtd_linhas_regiao = @QtdLinhasRegiao
        WHERE id_regiao_saude = @IdRegiaoSaude
          AND pipeline_versao = @PipelineVersao
          AND dt_data_inicio = @DataInicio
          AND dt_data_fim = @DataFim;

        SET @InicioTrecho = SYSDATETIME();

        INSERT INTO temp_CGUSC.fp.analise_gtin_inconsistencia_clinica
            (id_cnpj, id_regiao_saude, id_ibge7, patologia, regra_clinica, ano_base,
             qtd_cpfs_distintos, qtd_cpfs_incompativeis,
             qtd_autorizacoes, qtd_autorizacoes_incompativeis,
             valor_total_pago, valor_incompativel_pago,
             percentual_cpfs_incompativeis,
             rank_regional_qtd_cpfs_incompativeis,
             rank_regional_valor_incompativel_pago,
             percentil_regional_qtd_cpfs_incompativeis,
             percentil_regional_valor_incompativel_pago,
             participacao_cpfs_incompativeis_regiao,
             participacao_valor_incompativel_regiao,
             percentual_regional_cpfs_incompativeis,
             razao_percentual_vs_regiao,
             cpfs_incompativeis_esperados_regiao,
             excesso_cpfs_incompativeis_vs_regiao,
             dt_processamento)
        SELECT
            B.id_cnpj,
            B.id_regiao_saude,
            B.id_ibge7,
            B.patologia,
            B.regra_clinica,
            B.ano_base,
            B.qtd_cpfs_distintos,
            B.qtd_cpfs_incompativeis,
            B.qtd_autorizacoes,
            B.qtd_autorizacoes_incompativeis,
            B.valor_total_pago,
            B.valor_incompativel_pago,
            CAST(B.qtd_cpfs_incompativeis * 1.0 / NULLIF(B.qtd_cpfs_distintos, 0) AS DECIMAL(9,6)),
            CAST(
                CASE
                    WHEN B.qtd_cpfs_incompativeis > 0 THEN B.rank_regional_qtd_cpfs_incompativeis_raw
                    ELSE NULL
                END AS INT
            ),
            CAST(
                CASE
                    WHEN B.valor_incompativel_pago > 0 THEN B.rank_regional_valor_incompativel_pago_raw
                    ELSE NULL
                END AS INT
            ),
            CAST(
                CASE
                    WHEN B.qtd_cpfs_incompativeis > 0 THEN B.percentil_regional_qtd_cpfs_incompativeis_raw
                    ELSE NULL
                END AS DECIMAL(9,6)
            ),
            CAST(
                CASE
                    WHEN B.valor_incompativel_pago > 0 THEN B.percentil_regional_valor_incompativel_pago_raw
                    ELSE NULL
                END AS DECIMAL(9,6)
            ),
            CAST(B.qtd_cpfs_incompativeis * 1.0 / NULLIF(B.qtd_cpfs_incompativeis_regiao, 0) AS DECIMAL(9,6)),
            CAST(B.valor_incompativel_pago / NULLIF(B.valor_incompativel_pago_regiao, 0) AS DECIMAL(9,6)),
            B.percentual_cpfs_incompativeis_regiao,
            CAST(
                (B.qtd_cpfs_incompativeis * 1.0 / NULLIF(B.qtd_cpfs_distintos, 0))
                / NULLIF(B.percentual_cpfs_incompativeis_regiao, 0)
                AS DECIMAL(19,6)
            ),
            CAST(B.qtd_cpfs_distintos * B.percentual_cpfs_incompativeis_regiao AS DECIMAL(19,6)),
            CAST(
                B.qtd_cpfs_incompativeis
                - (B.qtd_cpfs_distintos * B.percentual_cpfs_incompativeis_regiao)
                AS DECIMAL(19,6)
            ),
            SYSDATETIME()
        FROM (
            SELECT
                A.id_cnpj,
                A.id_regiao_saude,
                A.id_ibge7,
                A.patologia,
                A.regra_clinica,
                A.ano_base,
                A.qtd_cpfs_distintos,
                A.qtd_cpfs_incompativeis,
                A.qtd_autorizacoes,
                A.qtd_autorizacoes_incompativeis,
                A.valor_total_pago,
                A.valor_incompativel_pago,
                G.qtd_cpfs_incompativeis_regiao,
                G.valor_incompativel_pago_regiao,
                G.percentual_cpfs_incompativeis_regiao,
                RANK() OVER (
                    PARTITION BY A.id_regiao_saude, A.patologia, A.regra_clinica, A.ano_base
                    ORDER BY A.qtd_cpfs_incompativeis DESC
                ) AS rank_regional_qtd_cpfs_incompativeis_raw,
                RANK() OVER (
                    PARTITION BY A.id_regiao_saude, A.patologia, A.regra_clinica, A.ano_base
                    ORDER BY A.valor_incompativel_pago DESC
                ) AS rank_regional_valor_incompativel_pago_raw,
                CUME_DIST() OVER (
                    PARTITION BY A.id_regiao_saude, A.patologia, A.regra_clinica, A.ano_base
                    ORDER BY A.qtd_cpfs_incompativeis
                ) AS percentil_regional_qtd_cpfs_incompativeis_raw,
                CUME_DIST() OVER (
                    PARTITION BY A.id_regiao_saude, A.patologia, A.regra_clinica, A.ano_base
                    ORDER BY A.valor_incompativel_pago
                ) AS percentil_regional_valor_incompativel_pago_raw
            FROM #agregado_cnpj_regiao A
            INNER JOIN #agregado_regiao G
                ON G.id_regiao_saude = A.id_regiao_saude
               AND G.patologia = A.patologia
               AND G.regra_clinica = A.regra_clinica
               AND G.ano_base = A.ano_base
        ) B;

        SET @QtdLinhasRegional = @@ROWCOUNT;
        SET @TempoTrechoMs = DATEDIFF(MILLISECOND, @InicioTrecho, SYSDATETIME());
        INSERT INTO #perfil_execucao (trecho, id_regiao_saude, linhas, tempo_ms, acumulado_ms)
        VALUES ('PASSO 2H - insert CNPJ contexto regional', @IdRegiaoSaude, @QtdLinhasRegional, @TempoTrechoMs, DATEDIFF(MILLISECOND, @InicioProcesso, SYSDATETIME()));
        RAISERROR('   2H CNPJ contexto regional: %d linhas | %d ms', 0, 1, @QtdLinhasRegional, @TempoTrechoMs) WITH NOWAIT;

        UPDATE temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_regiao_controle
        SET status = 'OK',
            etapa = 'FINALIZADO',
            dt_fim = SYSDATETIME(),
            qtd_linhas_regional = @QtdLinhasRegional
        WHERE id_regiao_saude = @IdRegiaoSaude
          AND pipeline_versao = @PipelineVersao
          AND dt_data_inicio = @DataInicio
          AND dt_data_fim = @DataFim;

        SET @QtdRegioesOk += 1;
        SET @TempoMs = DATEDIFF(MILLISECOND, @InicioEtapa, SYSDATETIME());
        RAISERROR('>> Regiao %I64d finalizada em %d ms.', 0, 1, @IdRegiaoSaude, @TempoMs) WITH NOWAIT;
    END TRY
    BEGIN CATCH
        UPDATE temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_regiao_controle
        SET status = 'ERRO',
            etapa = 'ERRO',
            dt_fim = SYSDATETIME(),
            mensagem_erro = ERROR_MESSAGE(),
            dt_erro = SYSDATETIME()
        WHERE id_regiao_saude = @IdRegiaoSaude
          AND pipeline_versao = @PipelineVersao
          AND dt_data_inicio = @DataInicio
          AND dt_data_fim = @DataFim;

        THROW;
    END CATCH;
END;

SET @TempoMs = DATEDIFF(MILLISECOND, @InicioProcesso, SYSDATETIME());
INSERT INTO #perfil_execucao (trecho, id_regiao_saude, linhas, tempo_ms, acumulado_ms)
VALUES ('TOTAL - analise GTIN inconsistencia clinica por regiao', NULL, NULL, @TempoMs, @TempoMs);

RAISERROR('==========================================================', 0, 1) WITH NOWAIT;
RAISERROR('Tempo total analise GTIN inconsistencia clinica por regiao: %d ms', 0, 1, @TempoMs) WITH NOWAIT;
RAISERROR('Regioes finalizadas nesta execucao: %d', 0, 1, @QtdRegioesOk) WITH NOWAIT;
RAISERROR('==========================================================', 0, 1) WITH NOWAIT;

SELECT
    id_regiao_saude,
    status,
    etapa,
    qtd_cnpjs,
    qtd_municipios,
    qtd_movimentos,
    qtd_base_itens,
    qtd_linhas_cnpj,
    qtd_linhas_municipio,
    qtd_linhas_regiao,
    qtd_linhas_regional,
    dt_inicio,
    dt_fim,
    mensagem_erro
FROM temp_CGUSC.fp.analise_gtin_inconsistencia_clinica_regiao_controle
WHERE pipeline_versao = @PipelineVersao
  AND dt_data_inicio = @DataInicio
  AND dt_data_fim = @DataFim
  AND (@RegiaoSaudeAlvo IS NULL OR id_regiao_saude = @RegiaoSaudeAlvo)
ORDER BY id_regiao_saude;

SELECT
    ordem,
    trecho,
    id_regiao_saude,
    linhas,
    tempo_ms,
    acumulado_ms,
    dt_registro
FROM #perfil_execucao
ORDER BY ordem;

DROP TABLE IF EXISTS #perfil_execucao;
DROP TABLE IF EXISTS #medicamentos_clinicos;
GO
