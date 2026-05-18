-- ============================================================================
-- DETECÇÃO DE CONCENTRAÇÃO TEMPORAL DE AUTORIZAÇÕES via Sliding Window
-- ============================================================================
-- Severidades: ALTO → GRAVE → CRÍTICO → EXTREMO
--
-- ── MULTI-CRM (nu_crms_distintos >= 2) ─────────────────────────────────────
--   EXTREMO →  8 auth em  5 min (1,6/min)
--   EXTREMO → 11 auth em 10 min (1,1/min)
--   CRÍTICO →  6 auth em  5 min (1,2/min)
--   CRÍTICO →  8 auth em 10 min (0,8/min)
--   GRAVE   → 10 auth em 15 min (0,7/min)
--   GRAVE   → 11 auth em 20 min (0,6/min)
--   ALTO    → 12 auth em 25 min (0,5/min)
--   ALTO    → 12 auth em 30 min (0,4/min)
--   ALTO    → 18 auth em 60 min (0,3/min)
--   ALTO    →  N auth, taxa ≥ 20/hr p/ N >= 15 (ex: 15 em até 45 min)
--
-- ── PROCESSAMENTO ───────────────────────────────────────────────────────────
--   Lotes de 20 CNPJs com checkpoint por CNPJ.
--   Reiniciar o script retoma de onde parou (CNPJs OK são pulados).
-- ============================================================================

-- Batch separado: dropa tabelas existentes ANTES de compilar o restante do script.
-- SQL Server valida colunas de tabelas persistentes em compile-time; se a tabela
-- existir sem id_medico_unico, o INSERT lançará Msg 207. O GO força recompilação
-- da próxima batch com as tabelas já ausentes, adiando a validação para runtime.
-- A metadata representa a UF/fonte atual; alertas e controle sao preservados
-- para permitir processamento acumulado e retomada por UF/CNPJ.
DROP TABLE IF EXISTS temp_CGUSC.fp.build_crm_concentracao_multiplo_metadata;
GO

SET NOCOUNT ON;

DECLARE @DataInicio  DATE     = '2015-07-01';
DECLARE @DataFim     DATE     = '2024-12-31';
DECLARE @lote_size   INT      = 20;
DECLARE @t0          DATETIME = GETDATE();
DECLARE @t1          DATETIME;
DECLARE @t_bloco     DATETIME;

DECLARE @lote_num           INT = 0;
DECLARE @nu_processados     INT = 0;
DECLARE @nu_alertas_lote    INT = 0;
DECLARE @nu_alertas_total   INT = 0;
DECLARE @nu_pendentes       INT;
DECLARE @nu_ja_processados  INT;
DECLARE @nu_total           INT;
DECLARE @pipeline_nome      VARCHAR(80) = 'crm_concentracao_multiplo';
DECLARE @pipeline_versao    VARCHAR(40) = 'v3_2026_05_12';
DECLARE @nu_registros_teste_mov_sc BIGINT;
DECLARE @uf_farmacia CHAR(2);
DECLARE @uf_farmacia_alvo CHAR(2) = NULL;
DECLARE @reset_fonte_uf BIT = 0;
DECLARE @nu_cnpjs_fonte INT;
DECLARE @nu_ufs_processadas INT = 0;
DECLARE @nu_alertas_total_geral INT = 0;
DECLARE @fonte_atual_ok BIT = 0;
DECLARE @id_lote_log BIGINT;
DECLARE @qtd_cnpjs_lote INT;
DECLARE @dt_fim_lote DATETIME;
DECLARE @dt_fim_etapa DATETIME;
DECLARE @nu_registros_etapa BIGINT;
DECLARE @alertas_criada BIT = 0;

IF OBJECT_ID('db_FarmaciaPopular.dbo.Relatorio_movimentacaoFP') IS NULL
BEGIN
    RAISERROR('Fonte nacional db_FarmaciaPopular.dbo.Relatorio_movimentacaoFP nao encontrada.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('db_FarmaciaPopular.carga_2024.relatorio_movimentacaoFP_2021_2024') IS NULL
BEGIN
    RAISERROR('Fonte nacional db_FarmaciaPopular.carga_2024.relatorio_movimentacaoFP_2021_2024 nao encontrada.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('temp_CGUSC.fp.dados_farmacia') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.dados_farmacia nao encontrada.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('temp_CGUSC.fp.medicamentos_patologia') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.medicamentos_patologia nao encontrada.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('temp_CGUSC.fp.build_crm_pipeline_uf_controle') IS NULL
BEGIN
    CREATE TABLE temp_CGUSC.fp.build_crm_pipeline_uf_controle (
        uf_farmacia        CHAR(2)       NOT NULL,
        pipeline_versao    VARCHAR(40)   NOT NULL,
        dt_data_inicio     DATE          NOT NULL,
        dt_data_fim        DATE          NOT NULL,
        status             VARCHAR(20)   NOT NULL,
        etapa              VARCHAR(80)   NULL,
        nu_registros_fonte BIGINT        NULL,
        nu_cnpjs_fonte     INT           NULL,
        dt_criacao         DATETIME      NOT NULL,
        dt_atualizacao     DATETIME      NULL,
        mensagem_erro      NVARCHAR(4000) NULL,
        dt_erro            DATETIME      NULL,
        CONSTRAINT PK_BuildCrmPipelineUfControle PRIMARY KEY CLUSTERED (uf_farmacia, pipeline_versao, dt_data_inicio, dt_data_fim)
    );
END;

IF COL_LENGTH('temp_CGUSC.fp.build_crm_pipeline_uf_controle', 'dt_criacao') IS NULL
    ALTER TABLE temp_CGUSC.fp.build_crm_pipeline_uf_controle ADD dt_criacao DATETIME NULL;

IF COL_LENGTH('temp_CGUSC.fp.build_crm_pipeline_uf_controle', 'dt_atualizacao') IS NULL
    ALTER TABLE temp_CGUSC.fp.build_crm_pipeline_uf_controle ADD dt_atualizacao DATETIME NULL;

IF COL_LENGTH('temp_CGUSC.fp.build_crm_pipeline_uf_controle', 'nu_registros_fonte') IS NULL
    ALTER TABLE temp_CGUSC.fp.build_crm_pipeline_uf_controle ADD nu_registros_fonte BIGINT NULL;

IF COL_LENGTH('temp_CGUSC.fp.build_crm_pipeline_uf_controle', 'nu_cnpjs_fonte') IS NULL
    ALTER TABLE temp_CGUSC.fp.build_crm_pipeline_uf_controle ADD nu_cnpjs_fonte INT NULL;

IF COL_LENGTH('temp_CGUSC.fp.build_crm_pipeline_uf_controle', 'mensagem_erro') IS NULL
    ALTER TABLE temp_CGUSC.fp.build_crm_pipeline_uf_controle ADD mensagem_erro NVARCHAR(4000) NULL;

IF COL_LENGTH('temp_CGUSC.fp.build_crm_pipeline_uf_controle', 'dt_erro') IS NULL
    ALTER TABLE temp_CGUSC.fp.build_crm_pipeline_uf_controle ADD dt_erro DATETIME NULL;

IF COL_LENGTH('temp_CGUSC.fp.build_crm_pipeline_uf_controle', 'status_concentracao_multiplo') IS NULL
    ALTER TABLE temp_CGUSC.fp.build_crm_pipeline_uf_controle ADD status_concentracao_multiplo VARCHAR(20) NULL;

IF COL_LENGTH('temp_CGUSC.fp.build_crm_pipeline_uf_controle', 'dt_concentracao_multiplo') IS NULL
    ALTER TABLE temp_CGUSC.fp.build_crm_pipeline_uf_controle ADD dt_concentracao_multiplo DATETIME NULL;

IF OBJECT_ID('temp_CGUSC.fp.build_crm_concentracao_multiplo_etapa_log') IS NULL
BEGIN
    CREATE TABLE temp_CGUSC.fp.build_crm_concentracao_multiplo_etapa_log (
        id_etapa_log       BIGINT IDENTITY(1,1) NOT NULL,
        uf_farmacia        CHAR(2)      NOT NULL,
        pipeline_versao    VARCHAR(40)  NOT NULL,
        dt_data_inicio     DATE         NOT NULL,
        dt_data_fim        DATE         NOT NULL,
        etapa              VARCHAR(80)  NOT NULL,
        dt_inicio_etapa    DATETIME     NOT NULL,
        dt_fim_etapa       DATETIME     NULL,
        segundos_etapa     INT          NULL,
        milissegundos_etapa INT         NULL,
        nu_registros       BIGINT       NULL,
        observacao         VARCHAR(400) NULL,
        CONSTRAINT PK_BuildCrmConcentracaoMultiploEtapaLog PRIMARY KEY CLUSTERED (id_etapa_log)
    );

    CREATE INDEX IDX_CrmConcentracaoMultiploEtapaLog_UfPeriodo
        ON temp_CGUSC.fp.build_crm_concentracao_multiplo_etapa_log
            (uf_farmacia, pipeline_versao, dt_data_inicio, dt_data_fim, etapa, dt_inicio_etapa);
END;

EXEC sp_executesql
    N'INSERT INTO temp_CGUSC.fp.build_crm_pipeline_uf_controle
          (uf_farmacia, pipeline_versao, dt_data_inicio, dt_data_fim, status, etapa, dt_criacao, dt_atualizacao)
      SELECT DISTINCT
          CAST(F.uf AS CHAR(2)),
          @versao,
          @inicio,
          @fim,
          ''PENDENTE'',
          ''AGUARDANDO_CONCENTRACAO_MULTIPLO'',
          GETDATE(),
          GETDATE()
      FROM temp_CGUSC.fp.dados_farmacia F
      WHERE F.uf IS NOT NULL
        AND NOT EXISTS (
            SELECT 1
            FROM temp_CGUSC.fp.build_crm_pipeline_uf_controle C
            WHERE C.uf_farmacia = CAST(F.uf AS CHAR(2))
              AND C.pipeline_versao = @versao
              AND C.dt_data_inicio = @inicio
              AND C.dt_data_fim = @fim
        );',
    N'@versao VARCHAR(40), @inicio DATE, @fim DATE',
    @versao = @pipeline_versao,
    @inicio = @DataInicio,
    @fim = @DataFim;

ProximaUF:
SET @lote_num = 0;
SET @nu_processados = 0;
SET @nu_alertas_lote = 0;
SET @nu_alertas_total = 0;
SET @nu_pendentes = NULL;
SET @nu_ja_processados = NULL;
SET @nu_total = NULL;
SET @nu_registros_teste_mov_sc = NULL;
SET @nu_cnpjs_fonte = NULL;
SET @uf_farmacia = @uf_farmacia_alvo;

IF @uf_farmacia_alvo IS NULL
BEGIN
    EXEC sp_executesql
        N'SELECT TOP 1 @uf_out = C.uf_farmacia
          FROM temp_CGUSC.fp.build_crm_pipeline_uf_controle C
          WHERE C.pipeline_versao = @versao
            AND C.dt_data_inicio = @inicio
            AND C.dt_data_fim = @fim
            AND ISNULL(C.status_concentracao_multiplo, ''PENDENTE'') <> ''OK''
          ORDER BY
            CASE ISNULL(C.status_concentracao_multiplo, C.status)
                WHEN ''ERRO'' THEN 1
                WHEN ''PROCESSANDO'' THEN 2
                WHEN ''INCOMPLETO'' THEN 3
                WHEN ''PENDENTE'' THEN 4
                ELSE 5
            END,
            C.uf_farmacia;',
        N'@versao VARCHAR(40), @inicio DATE, @fim DATE, @uf_out CHAR(2) OUTPUT',
        @versao = @pipeline_versao,
        @inicio = @DataInicio,
        @fim = @DataFim,
        @uf_out = @uf_farmacia OUTPUT;
END
ELSE IF @nu_ufs_processadas > 0
BEGIN
    GOTO ResultadosFinais;
END;

IF @uf_farmacia IS NULL
BEGIN
    GOTO ResultadosFinais;
END;

IF @reset_fonte_uf = 1
BEGIN
    DROP TABLE IF EXISTS #crm_mov_fonte_atual;
    DROP TABLE IF EXISTS #crm_mov_fonte_atual_metadata;
    DROP TABLE IF EXISTS #crm_cnpjs_fonte_atual;
END;

SET @fonte_atual_ok = 0;

IF OBJECT_ID('tempdb..#crm_mov_fonte_atual') IS NOT NULL
   AND OBJECT_ID('tempdb..#crm_mov_fonte_atual_metadata') IS NOT NULL
   AND COL_LENGTH('tempdb..#crm_mov_fonte_atual', 'id_cnpj') IS NOT NULL
   AND COL_LENGTH('tempdb..#crm_mov_fonte_atual_metadata', 'uf_farmacia') IS NOT NULL
BEGIN
    EXEC sp_executesql
        N'SELECT @ok = CASE WHEN EXISTS (
              SELECT 1
              FROM #crm_mov_fonte_atual_metadata
              WHERE id_pipeline = 1
                AND pipeline_versao = @versao
                AND dt_data_inicio = @inicio
                AND dt_data_fim = @fim
                AND uf_farmacia = @uf
                AND status = ''OK''
          ) THEN 1 ELSE 0 END;',
        N'@versao VARCHAR(40), @inicio DATE, @fim DATE, @uf CHAR(2), @ok BIT OUTPUT',
        @versao = @pipeline_versao,
        @inicio = @DataInicio,
        @fim = @DataFim,
        @uf = @uf_farmacia,
        @ok = @fonte_atual_ok OUTPUT;
END;

DROP TABLE IF EXISTS #crm_cnpjs_fonte_atual;

CREATE TABLE #crm_cnpjs_fonte_atual (
    id_cnpj INT NOT NULL
);

CREATE UNIQUE CLUSTERED INDEX IDX_CrmCnpjsFonteAtual
    ON #crm_cnpjs_fonte_atual(id_cnpj);

IF @fonte_atual_ok = 0
BEGIN
    PRINT '>> Materializando movimentacao da UF ' + @uf_farmacia + '...';
    SET @t1 = GETDATE();

    EXEC sp_executesql
        N'UPDATE temp_CGUSC.fp.build_crm_pipeline_uf_controle
          SET status = ''PROCESSANDO'',
              etapa = ''MATERIALIZANDO_FONTE_UF'',
              status_concentracao_multiplo = ''PROCESSANDO'',
              dt_atualizacao = GETDATE(),
              mensagem_erro = NULL,
              dt_erro = NULL
          WHERE uf_farmacia = @uf
            AND pipeline_versao = @versao
            AND dt_data_inicio = @inicio
            AND dt_data_fim = @fim;',
        N'@uf CHAR(2), @versao VARCHAR(40), @inicio DATE, @fim DATE',
        @uf = @uf_farmacia,
        @versao = @pipeline_versao,
        @inicio = @DataInicio,
        @fim = @DataFim;

    DROP TABLE IF EXISTS #crm_mov_fonte_atual;
    DROP TABLE IF EXISTS #crm_mov_fonte_atual_metadata;

    EXEC sp_executesql
        N'UPDATE temp_CGUSC.fp.build_crm_pipeline_uf_controle
          SET etapa = ''MATERIALIZANDO_FONTE_UF_SELECT_INTO'',
              dt_atualizacao = GETDATE()
          WHERE uf_farmacia = @uf
            AND pipeline_versao = @versao
            AND dt_data_inicio = @inicio
            AND dt_data_fim = @fim;',
        N'@uf CHAR(2), @versao VARCHAR(40), @inicio DATE, @fim DATE',
        @uf = @uf_farmacia,
        @versao = @pipeline_versao,
        @inicio = @DataInicio,
        @fim = @DataFim;

    SET @t_bloco = GETDATE();

    SELECT
        CAST(F.uf AS CHAR(2)) AS uf_farmacia,
        CAST(F.id AS INT) AS id_cnpj,
        CAST(M.cnpj AS CHAR(14)) AS cnpj,
        CAST(M.crm AS VARCHAR(10)) AS crm,
        CAST(M.crm_uf AS VARCHAR(2)) AS crm_uf,
        CAST(M.data_hora AS DATETIME) AS data_hora,
        CAST(M.num_autorizacao AS VARCHAR(50)) AS num_autorizacao,
        CAST(M.valor_pago AS DECIMAL(18,2)) AS valor_pago,
        M.codigo_barra
    INTO #crm_mov_fonte_atual
    FROM (
        SELECT cnpj, crm, crm_uf, data_hora, num_autorizacao, valor_pago, codigo_barra
        FROM db_FarmaciaPopular.dbo.Relatorio_movimentacaoFP
        UNION ALL
        SELECT cnpj, crm, crm_uf, data_hora, num_autorizacao, valor_pago, codigo_barra
        FROM db_FarmaciaPopular.carga_2024.relatorio_movimentacaoFP_2021_2024
    ) M
    INNER JOIN temp_CGUSC.fp.dados_farmacia F
        ON F.cnpj = M.cnpj
    WHERE F.uf = @uf_farmacia
      AND M.crm IS NOT NULL
      AND M.crm_uf IS NOT NULL
      AND M.crm_uf <> 'BR'
      AND M.data_hora >= @DataInicio
      AND M.data_hora < DATEADD(DAY, 1, @DataFim)
      AND EXISTS (
          SELECT 1
          FROM temp_CGUSC.fp.medicamentos_patologia PAT
          WHERE PAT.codigo_barra = M.codigo_barra
      );

    SET @nu_registros_etapa = @@ROWCOUNT;
    SET @nu_registros_teste_mov_sc = @nu_registros_etapa;
    SET @dt_fim_etapa = GETDATE();

    INSERT INTO temp_CGUSC.fp.build_crm_concentracao_multiplo_etapa_log
        (uf_farmacia, pipeline_versao, dt_data_inicio, dt_data_fim, etapa,
         dt_inicio_etapa, dt_fim_etapa, segundos_etapa, milissegundos_etapa,
         nu_registros, observacao)
    VALUES
        (@uf_farmacia, @pipeline_versao, @DataInicio, @DataFim, 'MATERIALIZANDO_FONTE_UF_SELECT_INTO',
         @t_bloco, @dt_fim_etapa, DATEDIFF(SECOND, @t_bloco, @dt_fim_etapa),
         DATEDIFF(MILLISECOND, @t_bloco, @dt_fim_etapa), @nu_registros_etapa,
         'SELECT INTO #crm_mov_fonte_atual.');

    EXEC sp_executesql
        N'UPDATE temp_CGUSC.fp.build_crm_pipeline_uf_controle
          SET etapa = ''MATERIALIZANDO_FONTE_UF_IDX_CLUSTERED'',
              dt_atualizacao = GETDATE()
          WHERE uf_farmacia = @uf
            AND pipeline_versao = @versao
            AND dt_data_inicio = @inicio
            AND dt_data_fim = @fim;',
        N'@uf CHAR(2), @versao VARCHAR(40), @inicio DATE, @fim DATE',
        @uf = @uf_farmacia,
        @versao = @pipeline_versao,
        @inicio = @DataInicio,
        @fim = @DataFim;

    SET @t_bloco = GETDATE();

    CREATE CLUSTERED INDEX IDX_CrmMovFonteAtual_UfCnpjData
        ON #crm_mov_fonte_atual(uf_farmacia, id_cnpj, data_hora);

    SET @dt_fim_etapa = GETDATE();

    INSERT INTO temp_CGUSC.fp.build_crm_concentracao_multiplo_etapa_log
        (uf_farmacia, pipeline_versao, dt_data_inicio, dt_data_fim, etapa,
         dt_inicio_etapa, dt_fim_etapa, segundos_etapa, milissegundos_etapa, observacao)
    VALUES
        (@uf_farmacia, @pipeline_versao, @DataInicio, @DataFim, 'MATERIALIZANDO_FONTE_UF_IDX_CLUSTERED',
         @t_bloco, @dt_fim_etapa, DATEDIFF(SECOND, @t_bloco, @dt_fim_etapa),
         DATEDIFF(MILLISECOND, @t_bloco, @dt_fim_etapa),
         'Indice clustered #crm_mov_fonte_atual(uf_farmacia, id_cnpj, data_hora).');

    EXEC sp_executesql
        N'UPDATE temp_CGUSC.fp.build_crm_pipeline_uf_controle
          SET etapa = ''MATERIALIZANDO_FONTE_UF_IDX_CNPJ_DATA'',
              dt_atualizacao = GETDATE()
          WHERE uf_farmacia = @uf
            AND pipeline_versao = @versao
            AND dt_data_inicio = @inicio
            AND dt_data_fim = @fim;',
        N'@uf CHAR(2), @versao VARCHAR(40), @inicio DATE, @fim DATE',
        @uf = @uf_farmacia,
        @versao = @pipeline_versao,
        @inicio = @DataInicio,
        @fim = @DataFim;

    SET @t_bloco = GETDATE();

    CREATE NONCLUSTERED INDEX IDX_CrmMovFonteAtual_CnpjData
        ON #crm_mov_fonte_atual(cnpj, data_hora)
        INCLUDE (id_cnpj, crm, crm_uf, num_autorizacao, valor_pago, codigo_barra);

    SET @dt_fim_etapa = GETDATE();

    INSERT INTO temp_CGUSC.fp.build_crm_concentracao_multiplo_etapa_log
        (uf_farmacia, pipeline_versao, dt_data_inicio, dt_data_fim, etapa,
         dt_inicio_etapa, dt_fim_etapa, segundos_etapa, milissegundos_etapa, observacao)
    VALUES
        (@uf_farmacia, @pipeline_versao, @DataInicio, @DataFim, 'MATERIALIZANDO_FONTE_UF_IDX_CNPJ_DATA',
         @t_bloco, @dt_fim_etapa, DATEDIFF(SECOND, @t_bloco, @dt_fim_etapa),
         DATEDIFF(MILLISECOND, @t_bloco, @dt_fim_etapa),
         'Indice nonclustered #crm_mov_fonte_atual(cnpj, data_hora).');

    EXEC sp_executesql
        N'UPDATE temp_CGUSC.fp.build_crm_pipeline_uf_controle
          SET etapa = ''MATERIALIZANDO_FONTE_UF_IDX_CRM_DATA'',
              dt_atualizacao = GETDATE()
          WHERE uf_farmacia = @uf
            AND pipeline_versao = @versao
            AND dt_data_inicio = @inicio
            AND dt_data_fim = @fim;',
        N'@uf CHAR(2), @versao VARCHAR(40), @inicio DATE, @fim DATE',
        @uf = @uf_farmacia,
        @versao = @pipeline_versao,
        @inicio = @DataInicio,
        @fim = @DataFim;

    SET @t_bloco = GETDATE();

    CREATE NONCLUSTERED INDEX IDX_CrmMovFonteAtual_CrmData
        ON #crm_mov_fonte_atual(id_cnpj, crm, crm_uf, data_hora)
        INCLUDE (cnpj, num_autorizacao, valor_pago, codigo_barra);

    SET @dt_fim_etapa = GETDATE();

    INSERT INTO temp_CGUSC.fp.build_crm_concentracao_multiplo_etapa_log
        (uf_farmacia, pipeline_versao, dt_data_inicio, dt_data_fim, etapa,
         dt_inicio_etapa, dt_fim_etapa, segundos_etapa, milissegundos_etapa, observacao)
    VALUES
        (@uf_farmacia, @pipeline_versao, @DataInicio, @DataFim, 'MATERIALIZANDO_FONTE_UF_IDX_CRM_DATA',
         @t_bloco, @dt_fim_etapa, DATEDIFF(SECOND, @t_bloco, @dt_fim_etapa),
         DATEDIFF(MILLISECOND, @t_bloco, @dt_fim_etapa),
         'Indice nonclustered #crm_mov_fonte_atual(id_cnpj, crm, crm_uf, data_hora).');

    EXEC sp_executesql
        N'UPDATE temp_CGUSC.fp.build_crm_pipeline_uf_controle
          SET etapa = ''MATERIALIZANDO_FONTE_UF_CONTAGEM'',
              dt_atualizacao = GETDATE()
          WHERE uf_farmacia = @uf
            AND pipeline_versao = @versao
            AND dt_data_inicio = @inicio
            AND dt_data_fim = @fim;',
        N'@uf CHAR(2), @versao VARCHAR(40), @inicio DATE, @fim DATE',
        @uf = @uf_farmacia,
        @versao = @pipeline_versao,
        @inicio = @DataInicio,
        @fim = @DataFim;

    SET @t_bloco = GETDATE();

    INSERT INTO #crm_cnpjs_fonte_atual (id_cnpj)
    SELECT
        F.id AS id_cnpj
    FROM temp_CGUSC.fp.dados_farmacia F
    WHERE F.uf = @uf_farmacia
      AND EXISTS (
          SELECT 1
          FROM #crm_mov_fonte_atual M
          WHERE M.uf_farmacia = @uf_farmacia
            AND M.id_cnpj = F.id
      );

    SET @nu_cnpjs_fonte = (
        SELECT COUNT(*)
        FROM #crm_cnpjs_fonte_atual
    );

    SET @dt_fim_etapa = GETDATE();

    INSERT INTO temp_CGUSC.fp.build_crm_concentracao_multiplo_etapa_log
        (uf_farmacia, pipeline_versao, dt_data_inicio, dt_data_fim, etapa,
         dt_inicio_etapa, dt_fim_etapa, segundos_etapa, milissegundos_etapa,
         nu_registros, observacao)
    VALUES
        (@uf_farmacia, @pipeline_versao, @DataInicio, @DataFim, 'MATERIALIZANDO_FONTE_UF_CONTAGEM',
         @t_bloco, @dt_fim_etapa, DATEDIFF(SECOND, @t_bloco, @dt_fim_etapa),
         DATEDIFF(MILLISECOND, @t_bloco, @dt_fim_etapa), @nu_registros_teste_mov_sc,
         'Contagem de linhas e CNPJs materializados.');

    CREATE TABLE #crm_mov_fonte_atual_metadata (
        id_pipeline          TINYINT      NOT NULL,
        pipeline_versao      VARCHAR(40)  NOT NULL,
        uf_farmacia          CHAR(2)      NOT NULL,
        dt_data_inicio       DATE         NOT NULL,
        dt_data_fim          DATE         NOT NULL,
        nu_registros_fonte   BIGINT       NOT NULL,
        nu_cnpjs_fonte       INT          NOT NULL,
        dt_criacao           DATETIME     NOT NULL,
        status               VARCHAR(20)  NOT NULL,
        observacao           VARCHAR(400) NULL
    );

    INSERT INTO #crm_mov_fonte_atual_metadata
        (id_pipeline, pipeline_versao, uf_farmacia, dt_data_inicio, dt_data_fim,
         nu_registros_fonte, nu_cnpjs_fonte, dt_criacao, status, observacao)
    VALUES
        (1, @pipeline_versao, @uf_farmacia, @DataInicio, @DataFim,
         @nu_registros_teste_mov_sc, @nu_cnpjs_fonte, GETDATE(), 'OK',
         'Fonte materializada pelo motor CRM multiplo.');

    EXEC sp_executesql
        N'UPDATE temp_CGUSC.fp.build_crm_pipeline_uf_controle
          SET etapa = ''FONTE_UF_MATERIALIZADA'',
              nu_registros_fonte = @nu_mov,
              nu_cnpjs_fonte = @nu_cnpjs,
              dt_atualizacao = GETDATE()
          WHERE uf_farmacia = @uf
            AND pipeline_versao = @versao
            AND dt_data_inicio = @inicio
            AND dt_data_fim = @fim;',
        N'@uf CHAR(2), @versao VARCHAR(40), @inicio DATE, @fim DATE, @nu_mov BIGINT, @nu_cnpjs INT',
        @uf = @uf_farmacia,
        @versao = @pipeline_versao,
        @inicio = @DataInicio,
        @fim = @DataFim,
        @nu_mov = @nu_registros_teste_mov_sc,
        @nu_cnpjs = @nu_cnpjs_fonte;

    PRINT '   Fonte UF materializada em: ' + CONVERT(VARCHAR(20), GETDATE() - @t1, 114);
END

IF NOT EXISTS (SELECT 1 FROM #crm_cnpjs_fonte_atual)
BEGIN
    INSERT INTO #crm_cnpjs_fonte_atual (id_cnpj)
    SELECT
        F.id AS id_cnpj
    FROM temp_CGUSC.fp.dados_farmacia F
    WHERE F.uf = @uf_farmacia
      AND EXISTS (
          SELECT 1
          FROM #crm_mov_fonte_atual M
          WHERE M.uf_farmacia = @uf_farmacia
            AND M.id_cnpj = F.id
      );

    SET @nu_cnpjs_fonte = (
        SELECT COUNT(*)
        FROM #crm_cnpjs_fonte_atual
    );
END;

SELECT @nu_registros_teste_mov_sc = nu_registros_fonte
FROM #crm_mov_fonte_atual_metadata
WHERE id_pipeline = 1
  AND pipeline_versao = @pipeline_versao
  AND dt_data_inicio = @DataInicio
  AND dt_data_fim = @DataFim
  AND status = 'OK';

PRINT '>> [CRM MULTIPLO] Iniciando detecção de concentração temporal...';
PRINT '   UF fonte: ' + @uf_farmacia;
PRINT '   Período: ' + CAST(@DataInicio AS VARCHAR(10)) + ' → ' + CAST(@DataFim AS VARCHAR(10));
PRINT '   Lote: ' + CAST(@lote_size AS VARCHAR) + ' CNPJs por iteração';

DROP TABLE IF EXISTS temp_CGUSC.fp.build_crm_concentracao_multiplo_metadata;

CREATE TABLE temp_CGUSC.fp.build_crm_concentracao_multiplo_metadata (
    id_pipeline       TINYINT      NOT NULL,
    pipeline_nome     VARCHAR(80)  NOT NULL,
    pipeline_versao   VARCHAR(40)  NOT NULL,
    dt_data_inicio    DATE         NOT NULL,
    dt_data_fim       DATE         NOT NULL,
    nu_registros_teste_mov_sc BIGINT NOT NULL,
    dt_criacao        DATETIME     NOT NULL,
    dt_atualizacao    DATETIME     NULL,
    status            VARCHAR(20)  NOT NULL,
    observacao        VARCHAR(400) NULL,
    CONSTRAINT PK_BuildCrmConcentracaoMultiploMetadata PRIMARY KEY CLUSTERED (id_pipeline),
    CONSTRAINT CK_BuildCrmConcentracaoMultiploMetadata_Id CHECK (id_pipeline = 1)
);

INSERT INTO temp_CGUSC.fp.build_crm_concentracao_multiplo_metadata
    (id_pipeline, pipeline_nome, pipeline_versao, dt_data_inicio, dt_data_fim,
     nu_registros_teste_mov_sc, dt_criacao, dt_atualizacao, status, observacao)
VALUES
    (1, @pipeline_nome, @pipeline_versao, @DataInicio, @DataFim,
     @nu_registros_teste_mov_sc, GETDATE(), GETDATE(), 'PROCESSANDO', 'Motor temporal CRM multiplo em processamento.');

IF OBJECT_ID('temp_CGUSC.fp.build_crm_pipeline_uf_controle') IS NOT NULL
    EXEC sp_executesql
        N'UPDATE temp_CGUSC.fp.build_crm_pipeline_uf_controle
          SET status = ''PROCESSANDO'',
              etapa = ''CONCENTRACAO_MULTIPLO'',
              status_concentracao_multiplo = ''PROCESSANDO'',
              dt_atualizacao = GETDATE(),
              mensagem_erro = NULL,
              dt_erro = NULL
          WHERE uf_farmacia = @uf
            AND pipeline_versao = @versao
            AND dt_data_inicio = @inicio
            AND dt_data_fim = @fim;',
        N'@uf CHAR(2), @versao VARCHAR(40), @inicio DATE, @fim DATE',
        @uf = @uf_farmacia,
        @versao = @pipeline_versao,
        @inicio = @DataInicio,
        @fim = @DataFim;


-- ============================================================================
-- PASSO 0: Criar tabelas persistentes se não existirem
-- ============================================================================
PRINT '>> Passo 0: Inicializando tabelas persistentes...';
SET @t1 = GETDATE();

IF OBJECT_ID('temp_CGUSC.fp.build_crm_concentracao_multiplo_controle') IS NULL
    CREATE TABLE temp_CGUSC.fp.build_crm_concentracao_multiplo_controle (
        id_cnpj    INT         NOT NULL,
        dt_inicio  DATETIME    NOT NULL,
        dt_fim     DATETIME    NULL,
        nu_alertas INT         NULL,
        status     VARCHAR(12) NOT NULL,
        CONSTRAINT PK_BuildConcentracaoMultiploControle PRIMARY KEY CLUSTERED (id_cnpj)
    );

IF OBJECT_ID('temp_CGUSC.fp.build_crm_concentracao_multiplo_lote_log') IS NULL
BEGIN
    CREATE TABLE temp_CGUSC.fp.build_crm_concentracao_multiplo_lote_log (
        id_lote_log                    BIGINT IDENTITY(1,1) NOT NULL,
        uf_farmacia                    CHAR(2)      NOT NULL,
        pipeline_versao                VARCHAR(40)  NOT NULL,
        dt_data_inicio                 DATE         NOT NULL,
        dt_data_fim                    DATE         NOT NULL,
        lote_num                       INT          NOT NULL,
        dt_inicio_lote                 DATETIME     NOT NULL,
        dt_fim_lote                    DATETIME     NULL,
        segundos_lote                  INT          NULL,
        milissegundos_lote             INT          NULL,
        qtd_cnpjs_lote                 INT          NULL,
        nu_alertas_lote                INT          NULL,
        nu_alertas_total_uf            INT          NULL,
        nu_cnpjs_processados_acumulado INT          NULL,
        nu_cnpjs_total                 INT          NULL,
        status                         VARCHAR(20)  NOT NULL,
        observacao                     VARCHAR(400) NULL,
        CONSTRAINT PK_BuildCrmConcentracaoMultiploLoteLog PRIMARY KEY CLUSTERED (id_lote_log)
    );

    CREATE INDEX IDX_CrmConcentracaoMultiploLoteLog_UfPeriodo
        ON temp_CGUSC.fp.build_crm_concentracao_multiplo_lote_log
            (uf_farmacia, pipeline_versao, dt_data_inicio, dt_data_fim, lote_num);
END;

SET @alertas_criada = 0;

IF OBJECT_ID('temp_CGUSC.fp.build_crm_concentracao_multiplo_alertas') IS NULL
BEGIN
    SET @alertas_criada = 1;

    CREATE TABLE temp_CGUSC.fp.build_crm_concentracao_multiplo_alertas (
        id_cnpj             INT             NOT NULL,
        dt_dia              DATE            NOT NULL,
        dt_ini_concentracao DATETIME        NOT NULL,
        dt_fim_concentracao DATETIME        NOT NULL,
        nu_minutos_span     TINYINT         NOT NULL,
        nu_crms_distintos   TINYINT         NOT NULL,
        nu_5min             SMALLINT        NOT NULL,
        nu_10min            SMALLINT        NOT NULL,
        nu_15min            SMALLINT        NOT NULL,
        nu_20min            SMALLINT        NOT NULL,
        nu_25min            SMALLINT        NOT NULL,
        nu_30min            SMALLINT        NOT NULL,
        nu_60min            SMALLINT        NOT NULL,
        id_severidade       TINYINT         NOT NULL,
        janela_pior_ritmo_minutos TINYINT   NOT NULL,
        nu_autorizacoes_pior_ritmo SMALLINT NOT NULL,
        taxa_hora_pior_ritmo DECIMAL(7,2)   NOT NULL,
        criterio_pior_ritmo VARCHAR(30)     NOT NULL
    );
    CREATE CLUSTERED INDEX IDX_ConcentracaoMultiploAlertas
        ON temp_CGUSC.fp.build_crm_concentracao_multiplo_alertas(id_cnpj, dt_dia);
END

IF OBJECT_ID('temp_CGUSC.fp.build_crm_concentracao_multiplo_alertas') IS NOT NULL
   AND (
       COL_LENGTH('temp_CGUSC.fp.build_crm_concentracao_multiplo_alertas', 'severidade') IS NOT NULL
       OR COL_LENGTH('temp_CGUSC.fp.build_crm_concentracao_multiplo_alertas', 'id_severidade') IS NULL
       OR COL_LENGTH('temp_CGUSC.fp.build_crm_concentracao_multiplo_alertas', 'janela_pior_ritmo_minutos') IS NULL
       OR COL_LENGTH('temp_CGUSC.fp.build_crm_concentracao_multiplo_alertas', 'nu_autorizacoes_pior_ritmo') IS NULL
       OR COL_LENGTH('temp_CGUSC.fp.build_crm_concentracao_multiplo_alertas', 'taxa_hora_pior_ritmo') IS NULL
       OR COL_LENGTH('temp_CGUSC.fp.build_crm_concentracao_multiplo_alertas', 'criterio_pior_ritmo') IS NULL
   )
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.build_crm_concentracao_multiplo_alertas existe com schema antigo. Recrie a tabela e o controle de lotes para a versao atual.', 16, 1);
    RETURN;
END;

IF @alertas_criada = 1
   AND EXISTS (
       SELECT 1
       FROM temp_CGUSC.fp.build_crm_concentracao_multiplo_controle
       WHERE status = 'OK'
   )
BEGIN
    RAISERROR('Tabela de alertas foi criada vazia, mas o controle de lotes ja possui CNPJs OK. Recrie tambem o controle de lotes para recalcular os alertas.', 16, 1);
    RETURN;
END;

PRINT '   Passo 0 concluido em: ' + CONVERT(VARCHAR(20), GETDATE() - @t1, 114);


-- ============================================================================
-- PASSO 1: Limpar CNPJs interrompidos para reprocessar do zero
-- ============================================================================
PRINT '>> Passo 1: Limpando CNPJs interrompidos (status PROCESSANDO)...';
SET @t1 = GETDATE();

DELETE alerta
FROM temp_CGUSC.fp.build_crm_concentracao_multiplo_alertas alerta
INNER JOIN temp_CGUSC.fp.build_crm_concentracao_multiplo_controle ctrl
    ON ctrl.id_cnpj = alerta.id_cnpj
WHERE ctrl.status = 'PROCESSANDO';

DELETE FROM temp_CGUSC.fp.build_crm_concentracao_multiplo_controle
WHERE status = 'PROCESSANDO';

PRINT '   Limpeza concluida em: ' + CONVERT(VARCHAR(20), GETDATE() - @t1, 114);


-- ============================================================================
-- PASSO 2: Construir fila de CNPJs pendentes
-- ============================================================================
PRINT '>> Passo 2: Construindo fila de CNPJs pendentes...';
SET @t1 = GETDATE();

DROP TABLE IF EXISTS #cnpjs_pendentes;

SELECT
    C.id_cnpj
INTO #cnpjs_pendentes
FROM #crm_cnpjs_fonte_atual C
WHERE NOT EXISTS (
    SELECT 1
    FROM temp_CGUSC.fp.build_crm_concentracao_multiplo_controle L
    WHERE L.id_cnpj = C.id_cnpj
      AND L.status = 'OK'
);

SET @nu_pendentes      = (SELECT COUNT(*) FROM #cnpjs_pendentes);
SET @nu_ja_processados = (
    SELECT COUNT(*)
    FROM temp_CGUSC.fp.build_crm_concentracao_multiplo_controle C
    WHERE C.status = 'OK'
      AND EXISTS (
          SELECT 1
          FROM #crm_cnpjs_fonte_atual F
          WHERE F.id_cnpj = C.id_cnpj
      )
);
SET @nu_total          = @nu_pendentes + @nu_ja_processados;

PRINT '   CNPJs já processados: ' + CAST(@nu_ja_processados AS VARCHAR) + ' / ' + CAST(@nu_total AS VARCHAR);
PRINT '   CNPJs pendentes:      ' + CAST(@nu_pendentes AS VARCHAR);
PRINT '   Passo 2 concluído em: ' + CONVERT(VARCHAR(20), GETDATE() - @t1, 114);

IF @nu_pendentes = 0
BEGIN
    PRINT '   Nada a processar — base já completa.';
    GOTO Resultados;
END

PRINT '>> Passo 3: Iniciando loop de lotes...';


-- ============================================================================
-- PASSO 3: Loop contínuo por lotes de @lote_size CNPJs
-- ============================================================================
WHILE EXISTS (SELECT 1 FROM #cnpjs_pendentes)
BEGIN
    SET @lote_num += 1;
    SET @t1 = GETDATE();
    SET @id_lote_log = NULL;
    SET @qtd_cnpjs_lote = NULL;
    SET @dt_fim_lote = NULL;

    INSERT INTO temp_CGUSC.fp.build_crm_concentracao_multiplo_lote_log
        (uf_farmacia, pipeline_versao, dt_data_inicio, dt_data_fim, lote_num,
         dt_inicio_lote, status, observacao)
    VALUES
        (@uf_farmacia, @pipeline_versao, @DataInicio, @DataFim, @lote_num,
         @t1, 'PROCESSANDO', 'Lote iniciado.');

    SET @id_lote_log = CONVERT(BIGINT, SCOPE_IDENTITY());

    -- ── Pegar próximo lote da fila ────────────────────────────────────────
    SET @t_bloco = GETDATE();
    DROP TABLE IF EXISTS #lote_atual;

    SELECT TOP (@lote_size) id_cnpj
    INTO #lote_atual
    FROM #cnpjs_pendentes
    ORDER BY id_cnpj;

    SET @qtd_cnpjs_lote = (SELECT COUNT(*) FROM #lote_atual);

    UPDATE temp_CGUSC.fp.build_crm_concentracao_multiplo_lote_log
    SET qtd_cnpjs_lote = @qtd_cnpjs_lote
    WHERE id_lote_log = @id_lote_log;

    PRINT '      3.0 Selecionar lote: ' + CONVERT(VARCHAR(20), GETDATE() - @t_bloco, 114);

    -- ── Marcar lote como PROCESSANDO ─────────────────────────────────────
    SET @t_bloco = GETDATE();
    INSERT INTO temp_CGUSC.fp.build_crm_concentracao_multiplo_controle (id_cnpj, dt_inicio, status)
    SELECT id_cnpj, GETDATE(), 'PROCESSANDO'
    FROM #lote_atual L
    WHERE NOT EXISTS (
        SELECT 1
        FROM temp_CGUSC.fp.build_crm_concentracao_multiplo_controle C
        WHERE C.id_cnpj = L.id_cnpj
    );

    UPDATE C
    SET status = 'PROCESSANDO',
        dt_inicio = GETDATE(),
        dt_fim = NULL,
        nu_alertas = NULL
    FROM temp_CGUSC.fp.build_crm_concentracao_multiplo_controle C
    INNER JOIN #lote_atual L ON L.id_cnpj = C.id_cnpj;

    PRINT '      3.0 Marcar PROCESSANDO: ' + CONVERT(VARCHAR(20), GETDATE() - @t_bloco, 114);

    -- ── Passo 3.A: Criar base pré-filtrada por patologia para o lote ──────
    -- Isso reduz drasticamente o volume de dados para o self-join sliding window.
    SET @t_bloco = GETDATE();
    DROP TABLE IF EXISTS #base_lote;

    SELECT 
        L.id_cnpj,
        CAST(A.data_hora AS DATE) AS dt_dia,
        A.data_hora,
        A.num_autorizacao,
        CAST(CAST(A.crm AS VARCHAR(10)) + '/' + A.crm_uf AS VARCHAR(13)) AS id_medico
    INTO #base_lote
    FROM #crm_mov_fonte_atual A
    INNER JOIN #lote_atual L ON L.id_cnpj = A.id_cnpj
    GROUP BY L.id_cnpj, A.data_hora, A.num_autorizacao, A.crm, A.crm_uf;

    CREATE CLUSTERED INDEX IDX_BaseLote
        ON #base_lote(id_cnpj, dt_dia, data_hora);

    PRINT '      3.A Base lote + indice: ' + CONVERT(VARCHAR(20), GETDATE() - @t_bloco, 114);


    -- ── Passo 3.B: Self-join com janela máxima de 60 minutos ─────────────────────────
    -- Usamos uma subconsulta para calcular as agregações uma única vez, 
    -- evitando o custo dobrado de repetir os COUNT(DISTINCT) no HAVING.
    SET @t_bloco = GETDATE();
    DROP TABLE IF EXISTS #concentracao_raw;

    SELECT *
    INTO #concentracao_raw
    FROM (
        SELECT
            A.id_cnpj,
            A.data_hora                                                               AS janela_inicio,

            COUNT(DISTINCT CASE WHEN B.data_hora <= DATEADD(SECOND, 359, A.data_hora)
                                THEN B.num_autorizacao END)                           AS nu_5min,
            COUNT(DISTINCT CASE WHEN B.data_hora <= DATEADD(MINUTE, 10, A.data_hora)
                                THEN B.num_autorizacao END)                           AS nu_10min,
            COUNT(DISTINCT CASE WHEN B.data_hora <= DATEADD(MINUTE, 15, A.data_hora)
                                THEN B.num_autorizacao END)                           AS nu_15min,
            COUNT(DISTINCT CASE WHEN B.data_hora <= DATEADD(MINUTE, 20, A.data_hora)
                                THEN B.num_autorizacao END)                           AS nu_20min,
            COUNT(DISTINCT CASE WHEN B.data_hora <= DATEADD(MINUTE, 25, A.data_hora)
                                THEN B.num_autorizacao END)                           AS nu_25min,
            COUNT(DISTINCT CASE WHEN B.data_hora <= DATEADD(MINUTE, 30, A.data_hora)
                                THEN B.num_autorizacao END)                           AS nu_30min,
            COUNT(DISTINCT CASE WHEN B.data_hora <= DATEADD(MINUTE, 60, A.data_hora)
                                THEN B.num_autorizacao END)                           AS nu_60min,

            COUNT(DISTINCT CASE WHEN B.data_hora <= DATEADD(SECOND, 359, A.data_hora)
                                THEN B.id_medico END)                                AS nu_crms_5min,
            COUNT(DISTINCT CASE WHEN B.data_hora <= DATEADD(MINUTE, 10, A.data_hora)
                                THEN B.id_medico END)                                AS nu_crms_10min,
            COUNT(DISTINCT CASE WHEN B.data_hora <= DATEADD(MINUTE, 15, A.data_hora)
                                THEN B.id_medico END)                                AS nu_crms_15min,
            COUNT(DISTINCT CASE WHEN B.data_hora <= DATEADD(MINUTE, 20, A.data_hora)
                                THEN B.id_medico END)                                AS nu_crms_20min,
            COUNT(DISTINCT CASE WHEN B.data_hora <= DATEADD(MINUTE, 25, A.data_hora)
                                THEN B.id_medico END)                                AS nu_crms_25min,
            COUNT(DISTINCT CASE WHEN B.data_hora <= DATEADD(MINUTE, 30, A.data_hora)
                                THEN B.id_medico END)                                AS nu_crms_30min,
            COUNT(DISTINCT CASE WHEN B.data_hora <= DATEADD(MINUTE, 60, A.data_hora)
                                THEN B.id_medico END)                                AS nu_crms_60min,

            -- Timestamps de fim real para cada sub-janela
            MAX(CASE WHEN B.data_hora <= DATEADD(SECOND, 359, A.data_hora) THEN B.data_hora END) AS fim_real_5min,
            MAX(CASE WHEN B.data_hora <= DATEADD(MINUTE, 10, A.data_hora) THEN B.data_hora END) AS fim_real_10min,
            MAX(CASE WHEN B.data_hora <= DATEADD(MINUTE, 15, A.data_hora) THEN B.data_hora END) AS fim_real_15min,
            MAX(CASE WHEN B.data_hora <= DATEADD(MINUTE, 20, A.data_hora) THEN B.data_hora END) AS fim_real_20min,
            MAX(CASE WHEN B.data_hora <= DATEADD(MINUTE, 25, A.data_hora) THEN B.data_hora END) AS fim_real_25min,
            MAX(CASE WHEN B.data_hora <= DATEADD(MINUTE, 30, A.data_hora) THEN B.data_hora END) AS fim_real_30min,
            MAX(CASE WHEN B.data_hora <= DATEADD(MINUTE, 60, A.data_hora) THEN B.data_hora END) AS fim_real_60min,

            DATEDIFF(MINUTE, MIN(B.data_hora), MAX(B.data_hora))                     AS nu_minutos_span_full

        FROM #base_lote A
        INNER JOIN #base_lote B
            ON  B.id_cnpj   = A.id_cnpj
            AND B.dt_dia    = A.dt_dia
            AND B.data_hora BETWEEN A.data_hora AND DATEADD(MINUTE, 60, A.data_hora)
        GROUP BY A.id_cnpj, A.data_hora
    ) Agg
    WHERE (
           (nu_5min  >=  6 AND nu_crms_5min  >= 2)
        OR (nu_10min >=  8 AND nu_crms_10min >= 2)
        OR (nu_15min >= 10 AND nu_crms_15min >= 2)
        OR (nu_20min >= 11 AND nu_crms_20min >= 2)
        OR (nu_25min >= 12 AND nu_crms_25min >= 2)
        OR (nu_30min >= 12 AND nu_crms_30min >= 2)
        OR (nu_60min >= 18 AND nu_crms_60min >= 2)
        OR (nu_60min >= 15 AND nu_minutos_span_full <= nu_60min * 3 AND nu_crms_60min >= 2)
    );

    PRINT '      3.B Self-join concentracao_raw: ' + CONVERT(VARCHAR(20), GETDATE() - @t_bloco, 114);

    -- Deduplicacao: 1 evento por bloco continuo/sobreposto de concentracao.
    -- Janelas sliding do mesmo CNPJ/dia que se sobrepoem viram um unico alerta,
    -- mantendo a melhor severidade/ritmo dentro do bloco.
    SET @t_bloco = GETDATE();
    DROP TABLE IF EXISTS #concentracao_candidatos;
    DROP TABLE IF EXISTS #concentracao_dedup;

    SELECT id_cnpj, dt_dia, dt_ini_concentracao, dt_fim_concentracao, nu_minutos_span,
           nu_crms_distintos, nu_5min, nu_10min, nu_15min, nu_20min, nu_25min, nu_30min, nu_60min,
           id_severidade, janela_pior_ritmo_minutos, nu_autorizacoes_pior_ritmo,
           taxa_hora_pior_ritmo, criterio_pior_ritmo
    INTO #concentracao_candidatos
    FROM (
        SELECT
            Base.id_cnpj,
            CAST(Base.janela_inicio AS DATE)                                      AS dt_dia,
            CAST(Base.janela_inicio AS DATETIME)                                  AS dt_ini_concentracao,
            CAST(Ritmo.dt_fim_real AS DATETIME)                                   AS dt_fim_concentracao,
            CAST(DATEDIFF(MINUTE, Base.janela_inicio, Ritmo.dt_fim_real) AS TINYINT) AS nu_minutos_span,
            CAST(Ritmo.nu_crms_distintos_ritmo AS TINYINT)                        AS nu_crms_distintos,
            CAST(Base.nu_5min AS SMALLINT)                                        AS nu_5min,
            CAST(Base.nu_10min AS SMALLINT)                                       AS nu_10min,
            CAST(Base.nu_15min AS SMALLINT)                                       AS nu_15min,
            CAST(Base.nu_20min AS SMALLINT)                                       AS nu_20min,
            CAST(Base.nu_25min AS SMALLINT)                                       AS nu_25min,
            CAST(Base.nu_30min AS SMALLINT)                                       AS nu_30min,
            CAST(Base.nu_60min AS SMALLINT)                                       AS nu_60min,
            Ritmo.id_severidade_criterio AS id_severidade,
            Ritmo.janela_pior_ritmo_minutos,
            Ritmo.nu_autorizacoes_pior_ritmo,
            Ritmo.taxa_hora_pior_ritmo,
            Ritmo.criterio_pior_ritmo
        FROM (
            SELECT
                *,
                CASE
                    WHEN nu_5min  >=  8 THEN fim_real_5min
                    WHEN nu_10min >= 11 THEN fim_real_10min
                    WHEN nu_5min  >=  6 THEN fim_real_5min
                    WHEN nu_10min >=  8 THEN fim_real_10min
                    WHEN nu_15min >= 10 THEN fim_real_15min
                    WHEN nu_20min >= 11 THEN fim_real_20min
                    WHEN nu_25min >= 12 THEN fim_real_25min
                    WHEN nu_30min >= 12 THEN fim_real_30min
                    WHEN nu_60min >= 18 THEN fim_real_60min
                    WHEN nu_60min >= 15 AND nu_minutos_span_full <= nu_60min * 3 THEN fim_real_60min
                END AS dt_fim_real,
                CASE
                    WHEN nu_5min  >=  8 THEN 4
                    WHEN nu_10min >= 11 THEN 4
                    WHEN nu_5min  >=  6 THEN 3
                    WHEN nu_10min >=  8 THEN 3
                    WHEN nu_15min >= 10 THEN 2
                    WHEN nu_20min >= 11 THEN 2
                    WHEN nu_25min >= 12 THEN 1
                    WHEN nu_30min >= 12 THEN 1
                    WHEN nu_60min >= 18 THEN 1
                    WHEN nu_60min >= 15 AND nu_minutos_span_full <= nu_60min * 3 THEN 1
                END AS id_severidade
            FROM #concentracao_raw
        ) Base
        CROSS APPLY (
            SELECT TOP 1
                V.dt_fim_real,
                V.janela_pior_ritmo_minutos,
                V.nu_autorizacoes_pior_ritmo,
                V.nu_crms_distintos_ritmo,
                V.id_severidade_criterio,
                CAST(V.nu_autorizacoes_pior_ritmo * 60.0 / NULLIF(V.janela_pior_ritmo_minutos, 0) AS DECIMAL(7,2)) AS taxa_hora_pior_ritmo,
                V.criterio_pior_ritmo
            FROM (VALUES
                (Base.fim_real_5min,  CAST(5 AS TINYINT),  CAST(Base.nu_5min AS SMALLINT),  CAST(Base.nu_crms_5min AS TINYINT),  CAST(4 AS TINYINT), CAST(1 AS TINYINT),  CAST('8_EM_5MIN' AS VARCHAR(30)),    CASE WHEN Base.nu_5min >= 8  AND Base.nu_crms_5min  >= 2 THEN 1 ELSE 0 END),
                (Base.fim_real_10min, CAST(10 AS TINYINT), CAST(Base.nu_10min AS SMALLINT), CAST(Base.nu_crms_10min AS TINYINT), CAST(4 AS TINYINT), CAST(2 AS TINYINT),  CAST('11_EM_10MIN' AS VARCHAR(30)),  CASE WHEN Base.nu_10min >= 11 AND Base.nu_crms_10min >= 2 THEN 1 ELSE 0 END),
                (Base.fim_real_5min,  CAST(5 AS TINYINT),  CAST(Base.nu_5min AS SMALLINT),  CAST(Base.nu_crms_5min AS TINYINT),  CAST(3 AS TINYINT), CAST(3 AS TINYINT),  CAST('6_EM_5MIN' AS VARCHAR(30)),    CASE WHEN Base.nu_5min >= 6  AND Base.nu_crms_5min  >= 2 THEN 1 ELSE 0 END),
                (Base.fim_real_10min, CAST(10 AS TINYINT), CAST(Base.nu_10min AS SMALLINT), CAST(Base.nu_crms_10min AS TINYINT), CAST(3 AS TINYINT), CAST(4 AS TINYINT),  CAST('8_EM_10MIN' AS VARCHAR(30)),   CASE WHEN Base.nu_10min >= 8  AND Base.nu_crms_10min >= 2 THEN 1 ELSE 0 END),
                (Base.fim_real_15min, CAST(15 AS TINYINT), CAST(Base.nu_15min AS SMALLINT), CAST(Base.nu_crms_15min AS TINYINT), CAST(2 AS TINYINT), CAST(5 AS TINYINT),  CAST('10_EM_15MIN' AS VARCHAR(30)),  CASE WHEN Base.nu_15min >= 10 AND Base.nu_crms_15min >= 2 THEN 1 ELSE 0 END),
                (Base.fim_real_20min, CAST(20 AS TINYINT), CAST(Base.nu_20min AS SMALLINT), CAST(Base.nu_crms_20min AS TINYINT), CAST(2 AS TINYINT), CAST(6 AS TINYINT),  CAST('11_EM_20MIN' AS VARCHAR(30)),  CASE WHEN Base.nu_20min >= 11 AND Base.nu_crms_20min >= 2 THEN 1 ELSE 0 END),
                (Base.fim_real_25min, CAST(25 AS TINYINT), CAST(Base.nu_25min AS SMALLINT), CAST(Base.nu_crms_25min AS TINYINT), CAST(1 AS TINYINT), CAST(7 AS TINYINT),  CAST('12_EM_25MIN' AS VARCHAR(30)),  CASE WHEN Base.nu_25min >= 12 AND Base.nu_crms_25min >= 2 THEN 1 ELSE 0 END),
                (Base.fim_real_30min, CAST(30 AS TINYINT), CAST(Base.nu_30min AS SMALLINT), CAST(Base.nu_crms_30min AS TINYINT), CAST(1 AS TINYINT), CAST(8 AS TINYINT),  CAST('12_EM_30MIN' AS VARCHAR(30)),  CASE WHEN Base.nu_30min >= 12 AND Base.nu_crms_30min >= 2 THEN 1 ELSE 0 END),
                (Base.fim_real_60min, CAST(60 AS TINYINT), CAST(Base.nu_60min AS SMALLINT), CAST(Base.nu_crms_60min AS TINYINT), CAST(1 AS TINYINT), CAST(9 AS TINYINT),  CAST('18_EM_60MIN' AS VARCHAR(30)),  CASE WHEN Base.nu_60min >= 18 AND Base.nu_crms_60min >= 2 THEN 1 ELSE 0 END),
                (Base.fim_real_60min, CAST(60 AS TINYINT), CAST(Base.nu_60min AS SMALLINT), CAST(Base.nu_crms_60min AS TINYINT), CAST(1 AS TINYINT), CAST(10 AS TINYINT), CAST('TAXA_20_HORA' AS VARCHAR(30)), CASE WHEN Base.nu_60min >= 15 AND Base.nu_minutos_span_full <= Base.nu_60min * 3 AND Base.nu_crms_60min >= 2 THEN 1 ELSE 0 END)
            ) V(dt_fim_real, janela_pior_ritmo_minutos, nu_autorizacoes_pior_ritmo, nu_crms_distintos_ritmo, id_severidade_criterio, prioridade_criterio, criterio_pior_ritmo, atingiu)
            WHERE V.atingiu = 1
            ORDER BY
                V.nu_autorizacoes_pior_ritmo * 60.0 / NULLIF(V.janela_pior_ritmo_minutos, 0) DESC,
                V.id_severidade_criterio DESC,
                V.prioridade_criterio ASC
        ) Ritmo
        WHERE Base.id_severidade IS NOT NULL
    ) sub
    WHERE id_severidade IS NOT NULL;

    ;WITH ordenado AS (
        SELECT
            C.*,
            MAX(C.dt_fim_concentracao) OVER (
                PARTITION BY C.id_cnpj, C.dt_dia
                ORDER BY C.dt_ini_concentracao, C.dt_fim_concentracao
                ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
            ) AS max_fim_anterior
        FROM #concentracao_candidatos C
    ),
    marcado AS (
        SELECT
            *,
            CASE
                WHEN max_fim_anterior IS NULL THEN 1
                WHEN dt_ini_concentracao > max_fim_anterior THEN 1
                ELSE 0
            END AS novo_bloco
        FROM ordenado
    ),
    agrupado AS (
        SELECT
            *,
            SUM(novo_bloco) OVER (
                PARTITION BY id_cnpj, dt_dia
                ORDER BY dt_ini_concentracao, dt_fim_concentracao
                ROWS UNBOUNDED PRECEDING
            ) AS grupo_sobreposicao
        FROM marcado
    ),
    ranked AS (
        SELECT
            *,
            ROW_NUMBER() OVER (
                PARTITION BY id_cnpj, dt_dia, grupo_sobreposicao
                ORDER BY
                    id_severidade DESC,
                    taxa_hora_pior_ritmo DESC,
                    nu_autorizacoes_pior_ritmo DESC,
                    nu_60min DESC,
                    nu_30min DESC,
                    nu_25min DESC,
                    nu_20min DESC,
                    nu_15min DESC,
                    nu_10min DESC,
                    nu_5min DESC,
                    nu_crms_distintos DESC,
                    dt_ini_concentracao ASC
            ) AS rn_bloco
        FROM agrupado
    )
    SELECT
        id_cnpj,
        dt_dia,
        dt_ini_concentracao,
        dt_fim_concentracao,
        nu_minutos_span,
        nu_crms_distintos,
        nu_5min, nu_10min, nu_15min, nu_20min, nu_25min, nu_30min, nu_60min,
        id_severidade,
        janela_pior_ritmo_minutos,
        nu_autorizacoes_pior_ritmo,
        taxa_hora_pior_ritmo,
        criterio_pior_ritmo
    INTO #concentracao_dedup
    FROM ranked
    WHERE rn_bloco = 1;

    PRINT '      3.C Deduplicacao: ' + CONVERT(VARCHAR(20), GETDATE() - @t_bloco, 114);

    -- ── INSERT incremental nos alertas ────────────────────────────────────
    SET @t_bloco = GETDATE();
    INSERT INTO temp_CGUSC.fp.build_crm_concentracao_multiplo_alertas
        (id_cnpj, dt_dia, dt_ini_concentracao, dt_fim_concentracao, nu_minutos_span,
         nu_crms_distintos, nu_5min, nu_10min, nu_15min, nu_20min, nu_25min, nu_30min, nu_60min,
         id_severidade, janela_pior_ritmo_minutos, nu_autorizacoes_pior_ritmo,
         taxa_hora_pior_ritmo, criterio_pior_ritmo)
    SELECT id_cnpj, dt_dia, dt_ini_concentracao, dt_fim_concentracao, nu_minutos_span,
           nu_crms_distintos, nu_5min, nu_10min, nu_15min, nu_20min, nu_25min, nu_30min, nu_60min,
           id_severidade, janela_pior_ritmo_minutos, nu_autorizacoes_pior_ritmo,
           taxa_hora_pior_ritmo, criterio_pior_ritmo
    FROM #concentracao_dedup;

    SET @nu_alertas_lote  = @@ROWCOUNT;
    SET @nu_alertas_total += @nu_alertas_lote;
    SET @nu_alertas_total_geral += @nu_alertas_lote;

    PRINT '      3.D Insert alertas: ' + CONVERT(VARCHAR(20), GETDATE() - @t_bloco, 114);

    -- ── Marcar lote como OK com contagem de alertas por CNPJ ─────────────
    SET @t_bloco = GETDATE();
    UPDATE ctrl
    SET status     = 'OK',
        dt_fim     = GETDATE(),
        nu_alertas = ISNULL((
            SELECT COUNT(*)
            FROM temp_CGUSC.fp.build_crm_concentracao_multiplo_alertas a
            WHERE a.id_cnpj = ctrl.id_cnpj
        ), 0)
    FROM temp_CGUSC.fp.build_crm_concentracao_multiplo_controle ctrl
    WHERE ctrl.id_cnpj IN (SELECT id_cnpj FROM #lote_atual);

    PRINT '      3.E Atualizar controle: ' + CONVERT(VARCHAR(20), GETDATE() - @t_bloco, 114);

    -- ── Remover lote da fila e atualizar contadores ───────────────────────
    SET @t_bloco = GETDATE();
    DELETE FROM #cnpjs_pendentes WHERE id_cnpj IN (SELECT id_cnpj FROM #lote_atual);

    SET @nu_processados += (SELECT COUNT(*) FROM #lote_atual);

    PRINT '      3.F Remover da fila: ' + CONVERT(VARCHAR(20), GETDATE() - @t_bloco, 114);

    SET @dt_fim_lote = GETDATE();

    UPDATE temp_CGUSC.fp.build_crm_concentracao_multiplo_lote_log
    SET dt_fim_lote = @dt_fim_lote,
        segundos_lote = DATEDIFF(SECOND, @t1, @dt_fim_lote),
        milissegundos_lote = DATEDIFF(MILLISECOND, @t1, @dt_fim_lote),
        qtd_cnpjs_lote = @qtd_cnpjs_lote,
        nu_alertas_lote = @nu_alertas_lote,
        nu_alertas_total_uf = @nu_alertas_total,
        nu_cnpjs_processados_acumulado = @nu_ja_processados + @nu_processados,
        nu_cnpjs_total = @nu_total,
        status = 'OK',
        observacao = 'Lote finalizado.'
    WHERE id_lote_log = @id_lote_log;

    PRINT '   Lote ' + RIGHT('0000' + CAST(@lote_num AS VARCHAR), 4) +
          ' | ' + CAST(@nu_ja_processados + @nu_processados AS VARCHAR) + '/' + CAST(@nu_total AS VARCHAR) + ' CNPJs' +
          ' | Alertas lote: ' + CAST(@nu_alertas_lote AS VARCHAR) +
          ' | Total alertas: ' + CAST(@nu_alertas_total AS VARCHAR) +
          ' | ' + CONVERT(VARCHAR(20), GETDATE() - @t1, 114);

    -- Limpeza sistemática para evitar erro Msg 2714 no próximo lote
    SET @t_bloco = GETDATE();
    DROP TABLE IF EXISTS #base_lote;
    DROP TABLE IF EXISTS #concentracao_raw;
    DROP TABLE IF EXISTS #concentracao_dedup;
    PRINT '      3.G Limpeza temporarias: ' + CONVERT(VARCHAR(20), GETDATE() - @t_bloco, 114);
END


-- ============================================================================
-- RESULTADOS
-- ============================================================================
Resultados:
UPDATE temp_CGUSC.fp.build_crm_concentracao_multiplo_metadata
SET status = CASE
        WHEN EXISTS (
            SELECT 1
            FROM temp_CGUSC.fp.build_crm_concentracao_multiplo_controle C
            INNER JOIN #crm_cnpjs_fonte_atual F ON F.id_cnpj = C.id_cnpj
            WHERE C.status <> 'OK'
        ) THEN 'INCOMPLETO'
        ELSE 'OK'
    END,
    dt_atualizacao = GETDATE(),
    observacao = 'Motor temporal CRM multiplo finalizado.'
WHERE id_pipeline = 1;

IF OBJECT_ID('temp_CGUSC.fp.build_crm_pipeline_uf_controle') IS NOT NULL
    EXEC sp_executesql
        N'UPDATE temp_CGUSC.fp.build_crm_pipeline_uf_controle
          SET status = ''PROCESSANDO'',
              etapa = CASE
                  WHEN EXISTS (
                      SELECT 1
                      FROM temp_CGUSC.fp.build_crm_concentracao_multiplo_controle C
                      INNER JOIN #crm_cnpjs_fonte_atual F ON F.id_cnpj = C.id_cnpj
                      WHERE C.status <> ''OK''
                  ) THEN ''CONCENTRACAO_MULTIPLO_INCOMPLETA''
                  ELSE ''CONCENTRACAO_MULTIPLO_OK''
              END,
              status_concentracao_multiplo = CASE
                  WHEN EXISTS (
                      SELECT 1
                      FROM temp_CGUSC.fp.build_crm_concentracao_multiplo_controle C
                      INNER JOIN #crm_cnpjs_fonte_atual F ON F.id_cnpj = C.id_cnpj
                      WHERE C.status <> ''OK''
                  ) THEN ''INCOMPLETO''
                  ELSE ''OK''
              END,
              dt_concentracao_multiplo = GETDATE(),
              dt_atualizacao = GETDATE(),
              mensagem_erro = NULL,
              dt_erro = NULL
          WHERE uf_farmacia = @uf
            AND pipeline_versao = @versao
            AND dt_data_inicio = @inicio
            AND dt_data_fim = @fim;',
        N'@uf CHAR(2), @versao VARCHAR(40), @inicio DATE, @fim DATE',
        @uf = @uf_farmacia,
        @versao = @pipeline_versao,
        @inicio = @DataInicio,
        @fim = @DataFim;

SET @nu_ufs_processadas += 1;

IF @uf_farmacia_alvo IS NULL
BEGIN
    GOTO ProximaUF;
END;

ResultadosFinais:
PRINT '==========================================================';
PRINT '   TEMPO TOTAL:   ' + CONVERT(VARCHAR(20), GETDATE() - @t0, 114);
PRINT '   UFs processadas: ' + CAST(@nu_ufs_processadas AS VARCHAR);
PRINT '   TOTAL ALERTAS: ' + CAST(@nu_alertas_total_geral AS VARCHAR);
PRINT '==========================================================';

IF OBJECT_ID('temp_CGUSC.fp.build_crm_concentracao_multiplo_metadata') IS NOT NULL
BEGIN
    SELECT
        id_pipeline,
        pipeline_nome,
        pipeline_versao,
        dt_data_inicio,
        dt_data_fim,
        nu_registros_teste_mov_sc,
        status,
        dt_criacao,
        dt_atualizacao,
        observacao
    FROM temp_CGUSC.fp.build_crm_concentracao_multiplo_metadata;
END;

EXEC sp_executesql
    N'SELECT
          uf_farmacia,
          status,
          etapa,
          status_concentracao_multiplo,
          nu_registros_fonte,
          nu_cnpjs_fonte,
          dt_concentracao_multiplo
      FROM temp_CGUSC.fp.build_crm_pipeline_uf_controle
      WHERE pipeline_versao = @versao
        AND dt_data_inicio = @inicio
        AND dt_data_fim = @fim
      ORDER BY uf_farmacia;',
    N'@versao VARCHAR(40), @inicio DATE, @fim DATE',
    @versao = @pipeline_versao,
    @inicio = @DataInicio,
    @fim = @DataFim;

-- Distribuição por severidade
IF OBJECT_ID('temp_CGUSC.fp.build_crm_concentracao_multiplo_alertas') IS NOT NULL
BEGIN
    SELECT
        id_severidade,
        CASE id_severidade
            WHEN 4 THEN 'EXTREMO'
            WHEN 3 THEN 'CRITICO'
            WHEN 2 THEN 'GRAVE'
            WHEN 1 THEN 'ALTO'
        END AS severidade,
        'Multi-CRM'                AS tipo,
        COUNT(*)                   AS qtd_alertas,
        COUNT(DISTINCT id_cnpj)    AS qtd_cnpjs,
        AVG(nu_crms_distintos)     AS media_crms_distintos,
        AVG(nu_minutos_span)       AS media_minutos_span,
        AVG(taxa_hora_pior_ritmo)  AS media_taxa_hora_pior_ritmo,
        MIN(dt_ini_concentracao)   AS primeiro_alerta,
        MAX(dt_ini_concentracao)   AS ultimo_alerta
    FROM temp_CGUSC.fp.build_crm_concentracao_multiplo_alertas
    GROUP BY id_severidade
    ORDER BY
        id_severidade DESC,
        tipo;

    -- Top 30 piores casos
    SELECT TOP 30
        id_cnpj,
        dt_dia,
        dt_ini_concentracao,
        dt_fim_concentracao,
        nu_minutos_span,
        nu_crms_distintos,
        nu_5min,
        nu_10min,
        nu_15min,
        nu_20min,
        nu_25min,
        nu_30min,
        nu_60min,
        id_severidade,
        CASE id_severidade
            WHEN 4 THEN 'EXTREMO'
            WHEN 3 THEN 'CRITICO'
            WHEN 2 THEN 'GRAVE'
            WHEN 1 THEN 'ALTO'
        END AS severidade,
        janela_pior_ritmo_minutos,
        nu_autorizacoes_pior_ritmo,
        taxa_hora_pior_ritmo,
        criterio_pior_ritmo
    FROM temp_CGUSC.fp.build_crm_concentracao_multiplo_alertas
    ORDER BY
        id_severidade DESC,
        taxa_hora_pior_ritmo DESC,
        nu_60min DESC;
END;
