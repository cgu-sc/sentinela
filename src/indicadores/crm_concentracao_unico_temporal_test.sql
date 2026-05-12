-- ============================================================================
-- DETECÇÃO DE CONCENTRAÇÃO TEMPORAL — CRM ÚNICO (Sliding Window)
-- ============================================================================
-- Versão focada em rajadas de UM único médico, com precisão de minuto.
-- Diferença do script multi-CRM: o self-join filtra B.crm = A.crm,
-- isolando a janela sliding exclusivamente para as transações do mesmo médico.
-- Isso elimina a "contaminação" por prescrições de outros CRMs na mesma hora.
--
-- Severidades: ALTO → GRAVE → CRÍTICO → EXTREMO
--
-- ── CRM ÚNICO (1 prescritor, janela intra-médico) ───────────────────────────
--   EXTREMO →  7 auth em  5 min (1,4/min)
--   EXTREMO → 10 auth em 10 min (1,0/min)
--   CRÍTICO →  6 auth em  5 min (1,2/min)
--   CRÍTICO →  8 auth em 10 min (0,8/min)
--   GRAVE   →  8 auth em 15 min (0,5/min)
--   GRAVE   →  9 auth em 20 min (0,5/min)
--   ALTO    →  6 auth em 25 min (0,2/min)
--   ALTO    →  8 auth em 30 min (0,3/min)
--   ALTO    → 12 auth em 60 min (0,2/min)
--   ALTO    →  N auth, taxa ≥ 12/hr p/ N >= 8 (ex: 8 em até 40 min)
--
-- ── PROCESSAMENTO ───────────────────────────────────────────────────────────
--   Lotes de 20 CNPJs com checkpoint por CNPJ.
--   Reiniciar o script retoma de onde parou (CNPJs OK são pulados).
-- ============================================================================

-- A metadata representa a UF/fonte atual; alertas e controle sao preservados
-- para permitir processamento acumulado e retomada por UF/CNPJ.
DROP TABLE IF EXISTS temp_CGUSC.fp.crm_concentracao_unico_uf_metadata;
DROP TABLE IF EXISTS temp_CGUSC.fp.crm_concentracao_unico_metadata;
GO

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
DECLARE @pipeline_nome      VARCHAR(80) = 'crm_concentracao_unico';
DECLARE @pipeline_versao    VARCHAR(40) = 'v2_2026_05_07';
DECLARE @nu_registros_fonte_uf BIGINT;
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

IF OBJECT_ID('temp_CGUSC.fp.crm_pipeline_uf_controle') IS NULL
BEGIN
    CREATE TABLE temp_CGUSC.fp.crm_pipeline_uf_controle (
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
        CONSTRAINT PK_CrmPipelineUfControle PRIMARY KEY CLUSTERED (uf_farmacia, pipeline_versao, dt_data_inicio, dt_data_fim)
    );
END;

IF COL_LENGTH('temp_CGUSC.fp.crm_pipeline_uf_controle', 'dt_criacao') IS NULL
    ALTER TABLE temp_CGUSC.fp.crm_pipeline_uf_controle ADD dt_criacao DATETIME NULL;

IF COL_LENGTH('temp_CGUSC.fp.crm_pipeline_uf_controle', 'dt_atualizacao') IS NULL
    ALTER TABLE temp_CGUSC.fp.crm_pipeline_uf_controle ADD dt_atualizacao DATETIME NULL;

IF COL_LENGTH('temp_CGUSC.fp.crm_pipeline_uf_controle', 'nu_registros_fonte') IS NULL
    ALTER TABLE temp_CGUSC.fp.crm_pipeline_uf_controle ADD nu_registros_fonte BIGINT NULL;

IF COL_LENGTH('temp_CGUSC.fp.crm_pipeline_uf_controle', 'nu_cnpjs_fonte') IS NULL
    ALTER TABLE temp_CGUSC.fp.crm_pipeline_uf_controle ADD nu_cnpjs_fonte INT NULL;

IF COL_LENGTH('temp_CGUSC.fp.crm_pipeline_uf_controle', 'mensagem_erro') IS NULL
    ALTER TABLE temp_CGUSC.fp.crm_pipeline_uf_controle ADD mensagem_erro NVARCHAR(4000) NULL;

IF COL_LENGTH('temp_CGUSC.fp.crm_pipeline_uf_controle', 'dt_erro') IS NULL
    ALTER TABLE temp_CGUSC.fp.crm_pipeline_uf_controle ADD dt_erro DATETIME NULL;

IF COL_LENGTH('temp_CGUSC.fp.crm_pipeline_uf_controle', 'status_concentracao_unico') IS NULL
    ALTER TABLE temp_CGUSC.fp.crm_pipeline_uf_controle ADD status_concentracao_unico VARCHAR(20) NULL;

IF COL_LENGTH('temp_CGUSC.fp.crm_pipeline_uf_controle', 'dt_concentracao_unico') IS NULL
    ALTER TABLE temp_CGUSC.fp.crm_pipeline_uf_controle ADD dt_concentracao_unico DATETIME NULL;

IF OBJECT_ID('temp_CGUSC.fp.crm_concentracao_unico_etapa_log') IS NULL
BEGIN
    CREATE TABLE temp_CGUSC.fp.crm_concentracao_unico_etapa_log (
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
        CONSTRAINT PK_CrmConcentracaoUnicoEtapaLog PRIMARY KEY CLUSTERED (id_etapa_log)
    );

    CREATE INDEX IDX_CrmConcentracaoUnicoEtapaLog_UfPeriodo
        ON temp_CGUSC.fp.crm_concentracao_unico_etapa_log
            (uf_farmacia, pipeline_versao, dt_data_inicio, dt_data_fim, etapa, dt_inicio_etapa);
END;

EXEC sp_executesql
    N'INSERT INTO temp_CGUSC.fp.crm_pipeline_uf_controle
          (uf_farmacia, pipeline_versao, dt_data_inicio, dt_data_fim, status, etapa, dt_criacao, dt_atualizacao)
      SELECT DISTINCT
          CAST(F.uf AS CHAR(2)),
          @versao,
          @inicio,
          @fim,
          ''PENDENTE'',
          ''AGUARDANDO_CONCENTRACAO_UNICO'',
          GETDATE(),
          GETDATE()
      FROM temp_CGUSC.fp.dados_farmacia F
      WHERE F.uf IS NOT NULL
        AND NOT EXISTS (
            SELECT 1
            FROM temp_CGUSC.fp.crm_pipeline_uf_controle C
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
SET @nu_registros_fonte_uf = NULL;
SET @nu_cnpjs_fonte = NULL;
SET @uf_farmacia = @uf_farmacia_alvo;

IF @uf_farmacia_alvo IS NULL
BEGIN
    EXEC sp_executesql
        N'SELECT TOP 1 @uf_out = C.uf_farmacia
          FROM temp_CGUSC.fp.crm_pipeline_uf_controle C
          WHERE C.pipeline_versao = @versao
            AND C.dt_data_inicio = @inicio
            AND C.dt_data_fim = @fim
            AND ISNULL(C.status_concentracao_unico, ''PENDENTE'') <> ''OK''
          ORDER BY
            CASE ISNULL(C.status_concentracao_unico, C.status)
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
    DROP TABLE IF EXISTS #crm_movimentacao_uf_atual;
    DROP TABLE IF EXISTS #crm_movimentacao_uf_atual_metadata;
    DROP TABLE IF EXISTS #crm_cnpjs_fonte_atual;
END;

SET @fonte_atual_ok = 0;

IF OBJECT_ID('tempdb..#crm_movimentacao_uf_atual') IS NOT NULL
   AND OBJECT_ID('tempdb..#crm_movimentacao_uf_atual_metadata') IS NOT NULL
   AND COL_LENGTH('tempdb..#crm_movimentacao_uf_atual', 'id_cnpj') IS NOT NULL
   AND COL_LENGTH('tempdb..#crm_movimentacao_uf_atual_metadata', 'uf_farmacia') IS NOT NULL
BEGIN
    EXEC sp_executesql
        N'SELECT @ok = CASE WHEN EXISTS (
              SELECT 1
              FROM #crm_movimentacao_uf_atual_metadata
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
    id_cnpj INT      NOT NULL,
    cnpj    CHAR(14) NOT NULL
);

CREATE UNIQUE CLUSTERED INDEX IDX_CrmCnpjsFonteAtual
    ON #crm_cnpjs_fonte_atual(id_cnpj);

IF @fonte_atual_ok = 0
BEGIN
    PRINT '>> Materializando movimentacao da UF ' + @uf_farmacia + '...';
    SET @t1 = GETDATE();

    EXEC sp_executesql
        N'UPDATE temp_CGUSC.fp.crm_pipeline_uf_controle
          SET status = ''PROCESSANDO'',
              etapa = ''MATERIALIZANDO_FONTE_UF'',
              status_concentracao_unico = ''PROCESSANDO'',
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

    DROP TABLE IF EXISTS #crm_movimentacao_uf_atual;
    DROP TABLE IF EXISTS #crm_movimentacao_uf_atual_metadata;

    EXEC sp_executesql
        N'UPDATE temp_CGUSC.fp.crm_pipeline_uf_controle
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
        F.id AS id_cnpj,
        CAST(M.cnpj AS CHAR(14)) AS cnpj,
        CAST(M.crm AS VARCHAR(10)) AS crm,
        CAST(M.crm_uf AS CHAR(2)) AS crm_uf,
        CAST(M.data_hora AS DATETIME) AS data_hora,
        M.num_autorizacao,
        CAST(M.valor_pago AS DECIMAL(18,2)) AS valor_pago,
        M.codigo_barra
    INTO #crm_movimentacao_uf_atual
    FROM (
        SELECT cnpj, crm, crm_uf, data_hora, num_autorizacao, valor_pago, codigo_barra
        FROM db_FarmaciaPopular.dbo.Relatorio_movimentacaoFP
        UNION ALL
        SELECT cnpj, crm, crm_uf, data_hora, num_autorizacao, valor_pago, codigo_barra
        FROM db_FarmaciaPopular.carga_2024.relatorio_movimentacaoFP_2021_2024
    ) M
    INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = M.cnpj
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
    SET @nu_registros_fonte_uf = @nu_registros_etapa;
    SET @dt_fim_etapa = GETDATE();

    INSERT INTO temp_CGUSC.fp.crm_concentracao_unico_etapa_log
        (uf_farmacia, pipeline_versao, dt_data_inicio, dt_data_fim, etapa,
         dt_inicio_etapa, dt_fim_etapa, segundos_etapa, milissegundos_etapa,
         nu_registros, observacao)
    VALUES
        (@uf_farmacia, @pipeline_versao, @DataInicio, @DataFim, 'MATERIALIZANDO_FONTE_UF_SELECT_INTO',
         @t_bloco, @dt_fim_etapa, DATEDIFF(SECOND, @t_bloco, @dt_fim_etapa),
         DATEDIFF(MILLISECOND, @t_bloco, @dt_fim_etapa), @nu_registros_etapa,
         'SELECT INTO #crm_movimentacao_uf_atual.');

    EXEC sp_executesql
        N'UPDATE temp_CGUSC.fp.crm_pipeline_uf_controle
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

    CREATE CLUSTERED INDEX IDX_CrmMovimentacaoUfAtual_CnpjData
        ON #crm_movimentacao_uf_atual(id_cnpj, data_hora);

    SET @dt_fim_etapa = GETDATE();

    INSERT INTO temp_CGUSC.fp.crm_concentracao_unico_etapa_log
        (uf_farmacia, pipeline_versao, dt_data_inicio, dt_data_fim, etapa,
         dt_inicio_etapa, dt_fim_etapa, segundos_etapa, milissegundos_etapa, observacao)
    VALUES
        (@uf_farmacia, @pipeline_versao, @DataInicio, @DataFim, 'MATERIALIZANDO_FONTE_UF_IDX_CLUSTERED',
         @t_bloco, @dt_fim_etapa, DATEDIFF(SECOND, @t_bloco, @dt_fim_etapa),
         DATEDIFF(MILLISECOND, @t_bloco, @dt_fim_etapa),
         'Indice clustered #crm_movimentacao_uf_atual(id_cnpj, data_hora).');

    EXEC sp_executesql
        N'UPDATE temp_CGUSC.fp.crm_pipeline_uf_controle
          SET etapa = ''MATERIALIZANDO_FONTE_UF_IDX_CRM_DIA'',
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

    CREATE NONCLUSTERED INDEX IDX_CrmMovimentacaoUfAtual_CrmDia
        ON #crm_movimentacao_uf_atual(id_cnpj, crm, crm_uf, data_hora)
        INCLUDE (cnpj, num_autorizacao, valor_pago, codigo_barra);

    SET @dt_fim_etapa = GETDATE();

    INSERT INTO temp_CGUSC.fp.crm_concentracao_unico_etapa_log
        (uf_farmacia, pipeline_versao, dt_data_inicio, dt_data_fim, etapa,
         dt_inicio_etapa, dt_fim_etapa, segundos_etapa, milissegundos_etapa, observacao)
    VALUES
        (@uf_farmacia, @pipeline_versao, @DataInicio, @DataFim, 'MATERIALIZANDO_FONTE_UF_IDX_CRM_DIA',
         @t_bloco, @dt_fim_etapa, DATEDIFF(SECOND, @t_bloco, @dt_fim_etapa),
         DATEDIFF(MILLISECOND, @t_bloco, @dt_fim_etapa),
         'Indice nonclustered #crm_movimentacao_uf_atual(id_cnpj, crm, crm_uf, data_hora).');

    EXEC sp_executesql
        N'UPDATE temp_CGUSC.fp.crm_pipeline_uf_controle
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

    INSERT INTO #crm_cnpjs_fonte_atual (id_cnpj, cnpj)
    SELECT
        F.id AS id_cnpj,
        CAST(F.cnpj AS CHAR(14)) AS cnpj
    FROM temp_CGUSC.fp.dados_farmacia F
    WHERE F.uf = @uf_farmacia
      AND EXISTS (
          SELECT 1
          FROM #crm_movimentacao_uf_atual M
          WHERE M.id_cnpj = F.id
      );

    SET @nu_cnpjs_fonte = (
        SELECT COUNT(*)
        FROM #crm_cnpjs_fonte_atual
    );

    SET @dt_fim_etapa = GETDATE();

    INSERT INTO temp_CGUSC.fp.crm_concentracao_unico_etapa_log
        (uf_farmacia, pipeline_versao, dt_data_inicio, dt_data_fim, etapa,
         dt_inicio_etapa, dt_fim_etapa, segundos_etapa, milissegundos_etapa,
         nu_registros, observacao)
    VALUES
        (@uf_farmacia, @pipeline_versao, @DataInicio, @DataFim, 'MATERIALIZANDO_FONTE_UF_CONTAGEM',
         @t_bloco, @dt_fim_etapa, DATEDIFF(SECOND, @t_bloco, @dt_fim_etapa),
         DATEDIFF(MILLISECOND, @t_bloco, @dt_fim_etapa), @nu_registros_fonte_uf,
         'Contagem de linhas e CNPJs materializados.');

    CREATE TABLE #crm_movimentacao_uf_atual_metadata (
        id_pipeline       TINYINT     NOT NULL,
        pipeline_nome     VARCHAR(80) NOT NULL,
        pipeline_versao   VARCHAR(40) NOT NULL,
        uf_farmacia       CHAR(2)     NOT NULL,
        dt_data_inicio    DATE        NOT NULL,
        dt_data_fim       DATE        NOT NULL,
        nu_registros      BIGINT      NOT NULL,
        nu_cnpjs          INT         NOT NULL,
        dt_criacao        DATETIME    NOT NULL,
        status            VARCHAR(20) NOT NULL,
        observacao        VARCHAR(400) NULL
    );

    INSERT INTO #crm_movimentacao_uf_atual_metadata
        (id_pipeline, pipeline_nome, pipeline_versao, uf_farmacia, dt_data_inicio, dt_data_fim,
         nu_registros, nu_cnpjs, dt_criacao, status, observacao)
    VALUES
        (1, 'crm_movimentacao_uf_atual', @pipeline_versao, @uf_farmacia, @DataInicio, @DataFim,
         @nu_registros_fonte_uf, @nu_cnpjs_fonte, GETDATE(), 'OK', 'Fonte UF materializada pelo motor CRM unico.');

    EXEC sp_executesql
        N'UPDATE temp_CGUSC.fp.crm_pipeline_uf_controle
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
        @nu_mov = @nu_registros_fonte_uf,
        @nu_cnpjs = @nu_cnpjs_fonte;

    PRINT '   Fonte UF materializada em: ' + CONVERT(VARCHAR(20), GETDATE() - @t1, 114);
END

IF NOT EXISTS (SELECT 1 FROM #crm_cnpjs_fonte_atual)
BEGIN
    INSERT INTO #crm_cnpjs_fonte_atual (id_cnpj, cnpj)
    SELECT
        F.id AS id_cnpj,
        CAST(F.cnpj AS CHAR(14)) AS cnpj
    FROM temp_CGUSC.fp.dados_farmacia F
    WHERE F.uf = @uf_farmacia
      AND EXISTS (
          SELECT 1
          FROM #crm_movimentacao_uf_atual M
          WHERE M.id_cnpj = F.id
      );

    SET @nu_cnpjs_fonte = (
        SELECT COUNT(*)
        FROM #crm_cnpjs_fonte_atual
    );
END;

SELECT @nu_registros_fonte_uf = nu_registros
FROM #crm_movimentacao_uf_atual_metadata
WHERE id_pipeline = 1
  AND pipeline_versao = @pipeline_versao
  AND dt_data_inicio = @DataInicio
  AND dt_data_fim = @DataFim
  AND uf_farmacia = @uf_farmacia
  AND status = 'OK';

PRINT '>> [CRM ÚNICO] Iniciando detecção de concentração temporal por médico...';
PRINT '   UF fonte: ' + @uf_farmacia;
PRINT '   Período: ' + CAST(@DataInicio AS VARCHAR(10)) + ' → ' + CAST(@DataFim AS VARCHAR(10));
PRINT '   Lote: ' + CAST(@lote_size AS VARCHAR) + ' CNPJs por iteração';

DROP TABLE IF EXISTS temp_CGUSC.fp.crm_concentracao_unico_uf_metadata;
DROP TABLE IF EXISTS temp_CGUSC.fp.crm_concentracao_unico_metadata;

CREATE TABLE temp_CGUSC.fp.crm_concentracao_unico_metadata (
    id_pipeline       TINYINT      NOT NULL,
    pipeline_nome     VARCHAR(80)  NOT NULL,
    pipeline_versao   VARCHAR(40)  NOT NULL,
    dt_data_inicio    DATE         NOT NULL,
    dt_data_fim       DATE         NOT NULL,
    nu_registros_fonte_uf BIGINT NOT NULL,
    dt_criacao        DATETIME     NOT NULL,
    dt_atualizacao    DATETIME     NULL,
    status            VARCHAR(20)  NOT NULL,
    observacao        VARCHAR(400) NULL,
    CONSTRAINT PK_CrmConcentracaoUnicoMetadata PRIMARY KEY CLUSTERED (id_pipeline),
    CONSTRAINT CK_CrmConcentracaoUnicoMetadata_Id CHECK (id_pipeline = 1)
);

INSERT INTO temp_CGUSC.fp.crm_concentracao_unico_metadata
    (id_pipeline, pipeline_nome, pipeline_versao, dt_data_inicio, dt_data_fim,
     nu_registros_fonte_uf, dt_criacao, dt_atualizacao, status, observacao)
VALUES
    (1, @pipeline_nome, @pipeline_versao, @DataInicio, @DataFim,
     @nu_registros_fonte_uf, GETDATE(), GETDATE(), 'PROCESSANDO', 'Motor temporal CRM unico em processamento.');

IF OBJECT_ID('temp_CGUSC.fp.crm_pipeline_uf_controle') IS NOT NULL
    EXEC sp_executesql
        N'UPDATE temp_CGUSC.fp.crm_pipeline_uf_controle
          SET status = ''PROCESSANDO'',
              etapa = ''CONCENTRACAO_UNICO'',
              status_concentracao_unico = ''PROCESSANDO'',
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

IF OBJECT_ID('temp_CGUSC.fp.crm_concentracao_unico_controle') IS NULL
    CREATE TABLE temp_CGUSC.fp.crm_concentracao_unico_controle (
        id_cnpj    INT         NOT NULL,
        dt_inicio  DATETIME    NOT NULL,
        dt_fim     DATETIME    NULL,
        nu_alertas INT         NULL,
        status     VARCHAR(12) NOT NULL,
        CONSTRAINT PK_CrmConcentracaoUnicoControle PRIMARY KEY CLUSTERED (id_cnpj)
    );

IF OBJECT_ID('temp_CGUSC.fp.crm_concentracao_unico_lote_log') IS NULL
BEGIN
    CREATE TABLE temp_CGUSC.fp.crm_concentracao_unico_lote_log (
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
        CONSTRAINT PK_CrmConcentracaoUnicoLoteLog PRIMARY KEY CLUSTERED (id_lote_log)
    );

    CREATE INDEX IDX_CrmConcentracaoUnicoLoteLog_UfPeriodo
        ON temp_CGUSC.fp.crm_concentracao_unico_lote_log
            (uf_farmacia, pipeline_versao, dt_data_inicio, dt_data_fim, lote_num);
END;

IF OBJECT_ID('temp_CGUSC.fp.crm_concentracao_unico_alertas') IS NULL
BEGIN
    CREATE TABLE temp_CGUSC.fp.crm_concentracao_unico_alertas (
        id_cnpj             INT             NOT NULL,
        id_medico           VARCHAR(13)     NOT NULL,
        dt_dia              DATE            NOT NULL,
        dt_ini_concentracao SMALLDATETIME   NOT NULL,
        dt_fim_concentracao SMALLDATETIME   NOT NULL,
        nu_minutos_span     TINYINT         NOT NULL,
        nu_5min             SMALLINT        NOT NULL,
        nu_10min            SMALLINT        NOT NULL,
        nu_15min            SMALLINT        NOT NULL,
        nu_20min            SMALLINT        NOT NULL,
        nu_25min            SMALLINT        NOT NULL,
        nu_30min            SMALLINT        NOT NULL,
        nu_60min            SMALLINT        NOT NULL,
        severidade          VARCHAR(10)     NOT NULL
    );
    CREATE CLUSTERED INDEX IDX_ConcentracaoUnicoAlertas
        ON temp_CGUSC.fp.crm_concentracao_unico_alertas(id_cnpj, id_medico, dt_dia);
END

PRINT '   Passo 0 concluido em: ' + CONVERT(VARCHAR(20), GETDATE() - @t1, 114);


-- ============================================================================
-- PASSO 1: Limpar CNPJs interrompidos para reprocessar do zero
-- ============================================================================
PRINT '>> Passo 1: Limpando CNPJs interrompidos (status PROCESSANDO)...';
SET @t1 = GETDATE();

DELETE alerta
FROM temp_CGUSC.fp.crm_concentracao_unico_alertas alerta
INNER JOIN temp_CGUSC.fp.crm_concentracao_unico_controle ctrl
    ON ctrl.id_cnpj = alerta.id_cnpj
WHERE ctrl.status = 'PROCESSANDO';

DELETE FROM temp_CGUSC.fp.crm_concentracao_unico_controle
WHERE status = 'PROCESSANDO';

PRINT '   Limpeza concluida em: ' + CONVERT(VARCHAR(20), GETDATE() - @t1, 114);


-- ============================================================================
-- PASSO 2: Construir fila de CNPJs pendentes
-- ============================================================================
PRINT '>> Passo 2: Construindo fila de CNPJs pendentes...';
SET @t1 = GETDATE();

DROP TABLE IF EXISTS #cnpjs_pendentes;

SELECT
    C.id_cnpj,
    C.cnpj
INTO #cnpjs_pendentes
FROM #crm_cnpjs_fonte_atual C
WHERE NOT EXISTS (
    SELECT 1
    FROM temp_CGUSC.fp.crm_concentracao_unico_controle L
    WHERE L.id_cnpj = C.id_cnpj
      AND L.status = 'OK'
);

SET @nu_pendentes      = (SELECT COUNT(*) FROM #cnpjs_pendentes);
SET @nu_ja_processados = (
    SELECT COUNT(*)
    FROM temp_CGUSC.fp.crm_concentracao_unico_controle C
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

    INSERT INTO temp_CGUSC.fp.crm_concentracao_unico_lote_log
        (uf_farmacia, pipeline_versao, dt_data_inicio, dt_data_fim, lote_num,
         dt_inicio_lote, status, observacao)
    VALUES
        (@uf_farmacia, @pipeline_versao, @DataInicio, @DataFim, @lote_num,
         @t1, 'PROCESSANDO', 'Lote iniciado.');

    SET @id_lote_log = CONVERT(BIGINT, SCOPE_IDENTITY());

    -- ── Pegar próximo lote da fila ────────────────────────────────────────
    SET @t_bloco = GETDATE();
    DROP TABLE IF EXISTS #lote_atual;

    SELECT TOP (@lote_size) id_cnpj, cnpj
    INTO #lote_atual
    FROM #cnpjs_pendentes
    ORDER BY id_cnpj;

    SET @qtd_cnpjs_lote = (SELECT COUNT(*) FROM #lote_atual);

    UPDATE temp_CGUSC.fp.crm_concentracao_unico_lote_log
    SET qtd_cnpjs_lote = @qtd_cnpjs_lote
    WHERE id_lote_log = @id_lote_log;

    PRINT '      3.0 Selecionar lote: ' + CONVERT(VARCHAR(20), GETDATE() - @t_bloco, 114);

    -- ── Marcar lote como PROCESSANDO ─────────────────────────────────────
    SET @t_bloco = GETDATE();
    INSERT INTO temp_CGUSC.fp.crm_concentracao_unico_controle (id_cnpj, dt_inicio, status)
    SELECT id_cnpj, GETDATE(), 'PROCESSANDO'
    FROM #lote_atual L
    WHERE NOT EXISTS (
        SELECT 1
        FROM temp_CGUSC.fp.crm_concentracao_unico_controle C
        WHERE C.id_cnpj = L.id_cnpj
    );

    UPDATE C
    SET status = 'PROCESSANDO',
        dt_inicio = GETDATE(),
        dt_fim = NULL,
        nu_alertas = NULL
    FROM temp_CGUSC.fp.crm_concentracao_unico_controle C
    INNER JOIN #lote_atual L ON L.id_cnpj = C.id_cnpj;

    PRINT '      3.0 Marcar PROCESSANDO: ' + CONVERT(VARCHAR(20), GETDATE() - @t_bloco, 114);

    -- ── Passo 3.A: Criar base pré-filtrada por patologia para o lote ──────
    -- Isso reduz o volume de dados e remove a necessidade de joins repetidos
    -- com a tabela de medicamentos dentro do sliding window.
    -- Isso colapsa múltiplos itens de uma mesma autorização no mesmo instante.
    SET @t_bloco = GETDATE();
    DROP TABLE IF EXISTS #base_lote;

    SELECT 
        L.id_cnpj,
        CAST(A.data_hora AS DATE) AS dt_dia,
        A.data_hora,
        A.num_autorizacao,
        CAST(CAST(A.crm AS VARCHAR(10)) + '/' + A.crm_uf AS VARCHAR(13)) AS id_medico
    INTO #base_lote
    FROM #crm_movimentacao_uf_atual A
    INNER JOIN #lote_atual L ON L.id_cnpj = A.id_cnpj
    GROUP BY L.id_cnpj, A.data_hora, A.num_autorizacao, A.crm, A.crm_uf;

    CREATE INDEX IDX_BaseLote ON #base_lote(id_cnpj, id_medico, dt_dia, data_hora);

    PRINT '      3.A Base lote + indice: ' + CONVERT(VARCHAR(20), GETDATE() - @t_bloco, 114);


    -- ── Passo 3.B: Concentração sobre a base reduzida ────────────────────
    SET @t_bloco = GETDATE();
    DROP TABLE IF EXISTS #concentracao_raw;

    -- Usamos uma subconsulta para calcular as agregações uma única vez, 
    -- evitando o custo dobrado de repetir os COUNT(DISTINCT) no HAVING.
    SELECT *
    INTO #concentracao_raw
    FROM (
        SELECT
            A.id_cnpj,
            A.id_medico,
            A.data_hora                                                     AS janela_inicio,

            COUNT(DISTINCT CASE WHEN B.data_hora <= DATEADD(SECOND, 359, A.data_hora)
                                THEN B.num_autorizacao END)                 AS nu_5min,
            COUNT(DISTINCT CASE WHEN B.data_hora <= DATEADD(MINUTE, 10, A.data_hora)
                                THEN B.num_autorizacao END)                 AS nu_10min,
            COUNT(DISTINCT CASE WHEN B.data_hora <= DATEADD(MINUTE, 15, A.data_hora)
                                THEN B.num_autorizacao END)                 AS nu_15min,
            COUNT(DISTINCT CASE WHEN B.data_hora <= DATEADD(MINUTE, 20, A.data_hora)
                                THEN B.num_autorizacao END)                 AS nu_20min,
            COUNT(DISTINCT CASE WHEN B.data_hora <= DATEADD(MINUTE, 25, A.data_hora)
                                THEN B.num_autorizacao END)                 AS nu_25min,
            COUNT(DISTINCT CASE WHEN B.data_hora <= DATEADD(MINUTE, 30, A.data_hora)
                                THEN B.num_autorizacao END)                 AS nu_30min,
            COUNT(DISTINCT CASE WHEN B.data_hora <= DATEADD(MINUTE, 60, A.data_hora)
                                THEN B.num_autorizacao END)                 AS nu_60min,

            -- Timestamps de fim real para cada sub-janela
            MAX(CASE WHEN B.data_hora <= DATEADD(SECOND, 359, A.data_hora) THEN B.data_hora END) AS fim_real_5min,
            MAX(CASE WHEN B.data_hora <= DATEADD(MINUTE, 10, A.data_hora) THEN B.data_hora END) AS fim_real_10min,
            MAX(CASE WHEN B.data_hora <= DATEADD(MINUTE, 15, A.data_hora) THEN B.data_hora END) AS fim_real_15min,
            MAX(CASE WHEN B.data_hora <= DATEADD(MINUTE, 20, A.data_hora) THEN B.data_hora END) AS fim_real_20min,
            MAX(CASE WHEN B.data_hora <= DATEADD(MINUTE, 25, A.data_hora) THEN B.data_hora END) AS fim_real_25min,
            MAX(CASE WHEN B.data_hora <= DATEADD(MINUTE, 30, A.data_hora) THEN B.data_hora END) AS fim_real_30min,
            MAX(CASE WHEN B.data_hora <= DATEADD(MINUTE, 60, A.data_hora) THEN B.data_hora END) AS fim_real_60min,

            DATEDIFF(MINUTE, MIN(B.data_hora), MAX(B.data_hora))            AS nu_minutos_span_full

        FROM #base_lote A
        INNER JOIN #base_lote B
            ON  B.id_cnpj       = A.id_cnpj
            AND B.id_medico     = A.id_medico
            AND B.dt_dia        = A.dt_dia
            AND B.data_hora BETWEEN A.data_hora AND DATEADD(MINUTE, 60, A.data_hora)
        GROUP BY A.id_cnpj, A.id_medico, A.data_hora
    ) Agg
    WHERE nu_5min >= 6 
       OR nu_10min >= 8 
       OR nu_15min >= 8 
       OR nu_20min >= 9 
       OR nu_25min >= 6 
       OR nu_30min >= 8 
       OR nu_60min >= 12 
       OR (nu_60min >= 8 AND nu_minutos_span_full <= nu_60min * 5);

    PRINT '      3.B Self-join concentracao_raw: ' + CONVERT(VARCHAR(20), GETDATE() - @t_bloco, 114);

    -- ── Deduplicação: 1 evento por (cnpj, médico, hora) ──────────────────
    -- PARTITION BY inclui id_medico: dois médicos diferentes no mesmo CNPJ/hora
    -- geram eventos independentes (não se cancelam).
    SET @t_bloco = GETDATE();
    DROP TABLE IF EXISTS #concentracao_dedup;

    SELECT
        id_cnpj,
        id_medico,
        janela_inicio,
        nu_5min, nu_10min, nu_15min, nu_20min, nu_25min, nu_30min, nu_60min,
        fim_real_5min, fim_real_10min, fim_real_15min, fim_real_20min, 
        fim_real_25min, fim_real_30min, fim_real_60min,
        nu_minutos_span_full,
        ROW_NUMBER() OVER (
            PARTITION BY
                id_cnpj,
                id_medico,
                CAST(janela_inicio AS DATE),
                DATEDIFF(MINUTE, 0, janela_inicio) / 60
            ORDER BY
                CASE
                    WHEN nu_5min  >=  7 THEN 1
                    WHEN nu_10min >= 10 THEN 1
                    WHEN nu_5min  >=  6 THEN 2
                    WHEN nu_10min >=  8 THEN 2
                    WHEN nu_15min >=  8 THEN 3
                    WHEN nu_20min >=  9 THEN 3
                    WHEN nu_30min >=  8 THEN 4
                    WHEN nu_60min >= 12 THEN 4
                    WHEN nu_25min >=  6 THEN 4
                    WHEN nu_60min >=  8 AND nu_minutos_span_full <= nu_60min * 5 THEN 4
                    ELSE 99
                END ASC,
                nu_60min DESC,
                nu_30min DESC,
                nu_25min DESC,
                nu_20min DESC,
                nu_15min DESC,
                nu_10min DESC,
                nu_5min DESC,
                janela_inicio ASC
        ) AS rn
    INTO #concentracao_dedup
    FROM #concentracao_raw;

    PRINT '      3.C Deduplicacao: ' + CONVERT(VARCHAR(20), GETDATE() - @t_bloco, 114);

    -- ── INSERT incremental nos alertas ────────────────────────────────────
    SET @t_bloco = GETDATE();
    INSERT INTO temp_CGUSC.fp.crm_concentracao_unico_alertas
        (id_cnpj, id_medico, dt_dia, dt_ini_concentracao, dt_fim_concentracao, nu_minutos_span,
         nu_5min, nu_10min, nu_15min, nu_20min, nu_25min, nu_30min, nu_60min, severidade)
    SELECT id_cnpj, id_medico, dt_dia, dt_ini_concentracao, dt_fim_concentracao, nu_minutos_span,
           nu_5min, nu_10min, nu_15min, nu_20min, nu_25min, nu_30min, nu_60min, severidade
    FROM (
        SELECT
            id_cnpj,
            id_medico,
            CAST(janela_inicio AS DATE)                                 AS dt_dia,
            CAST(janela_inicio AS SMALLDATETIME)                        AS dt_ini_concentracao,
            CAST(dt_fim_real AS SMALLDATETIME)                          AS dt_fim_concentracao,
            CAST(DATEDIFF(MINUTE, janela_inicio, dt_fim_real) AS TINYINT) AS nu_minutos_span,
            CAST(nu_5min AS SMALLINT)                                   AS nu_5min,
            CAST(nu_10min AS SMALLINT)                                  AS nu_10min,
            CAST(nu_15min AS SMALLINT)                                  AS nu_15min,
            CAST(nu_20min AS SMALLINT)                                  AS nu_20min,
            CAST(nu_25min AS SMALLINT)                                  AS nu_25min,
            CAST(nu_30min AS SMALLINT)                                  AS nu_30min,
            CAST(nu_60min AS SMALLINT)                                  AS nu_60min,
            severidade
        FROM (
            SELECT
                *,
                CASE
                    WHEN nu_5min  >=  7 THEN fim_real_5min
                    WHEN nu_10min >= 10 THEN fim_real_10min
                    WHEN nu_5min  >=  6 THEN fim_real_5min
                    WHEN nu_10min >=  8 THEN fim_real_10min
                    WHEN nu_15min >=  8 THEN fim_real_15min
                    WHEN nu_20min >=  9 THEN fim_real_20min
                    WHEN nu_30min >=  8 THEN fim_real_30min
                    WHEN nu_60min >= 12 THEN fim_real_60min
                    WHEN nu_25min >=  6 THEN fim_real_25min
                    WHEN nu_60min >=  8 AND nu_minutos_span_full <= nu_60min * 5 THEN fim_real_60min
                END AS dt_fim_real,
                CASE
                    WHEN nu_5min  >=  7 THEN 'EXTREMO'
                    WHEN nu_10min >= 10 THEN 'EXTREMO'
                    WHEN nu_5min  >=  6 THEN 'CRÍTICO'
                    WHEN nu_10min >=  8 THEN 'CRÍTICO'
                    WHEN nu_15min >=  8 THEN 'GRAVE'
                    WHEN nu_20min >=  9 THEN 'GRAVE'
                    WHEN nu_30min >=  8 THEN 'ALTO'
                    WHEN nu_60min >= 12 THEN 'ALTO'
                    WHEN nu_25min >=  6 THEN 'ALTO'
                    WHEN nu_60min >=  8 AND nu_minutos_span_full <= nu_60min * 5 THEN 'ALTO'
                END AS severidade
            FROM #concentracao_dedup
            WHERE rn = 1
        ) sub
    ) sub
    WHERE severidade IS NOT NULL;

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
            FROM temp_CGUSC.fp.crm_concentracao_unico_alertas a
            WHERE a.id_cnpj = ctrl.id_cnpj
        ), 0)
    FROM temp_CGUSC.fp.crm_concentracao_unico_controle ctrl
    WHERE ctrl.id_cnpj IN (SELECT id_cnpj FROM #lote_atual);

    PRINT '      3.E Atualizar controle: ' + CONVERT(VARCHAR(20), GETDATE() - @t_bloco, 114);

    -- ── Remover lote da fila e atualizar contadores ───────────────────────
    SET @t_bloco = GETDATE();
    DELETE FROM #cnpjs_pendentes WHERE id_cnpj IN (SELECT id_cnpj FROM #lote_atual);

    SET @nu_processados += (SELECT COUNT(*) FROM #lote_atual);

    PRINT '      3.F Remover da fila: ' + CONVERT(VARCHAR(20), GETDATE() - @t_bloco, 114);

    SET @dt_fim_lote = GETDATE();

    UPDATE temp_CGUSC.fp.crm_concentracao_unico_lote_log
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
END


-- ============================================================================
-- RESULTADOS
-- ============================================================================
Resultados:
UPDATE temp_CGUSC.fp.crm_concentracao_unico_metadata
SET status = CASE
        WHEN EXISTS (
            SELECT 1
            FROM temp_CGUSC.fp.crm_concentracao_unico_controle C
            INNER JOIN #crm_cnpjs_fonte_atual F ON F.id_cnpj = C.id_cnpj
            WHERE C.status <> 'OK'
        ) THEN 'INCOMPLETO'
        ELSE 'OK'
    END,
    dt_atualizacao = GETDATE(),
    observacao = 'Motor temporal CRM unico finalizado.'
WHERE id_pipeline = 1;

IF OBJECT_ID('temp_CGUSC.fp.crm_pipeline_uf_controle') IS NOT NULL
    EXEC sp_executesql
        N'UPDATE temp_CGUSC.fp.crm_pipeline_uf_controle
          SET status = ''PROCESSANDO'',
              etapa = CASE
                  WHEN EXISTS (
                      SELECT 1
                      FROM temp_CGUSC.fp.crm_concentracao_unico_controle C
                      INNER JOIN #crm_cnpjs_fonte_atual F ON F.id_cnpj = C.id_cnpj
                      WHERE C.status <> ''OK''
                  ) THEN ''CONCENTRACAO_UNICO_INCOMPLETA''
                  ELSE ''CONCENTRACAO_UNICO_OK''
              END,
              status_concentracao_unico = CASE
                  WHEN EXISTS (
                      SELECT 1
                      FROM temp_CGUSC.fp.crm_concentracao_unico_controle C
                      INNER JOIN #crm_cnpjs_fonte_atual F ON F.id_cnpj = C.id_cnpj
                      WHERE C.status <> ''OK''
                  ) THEN ''INCOMPLETO''
                  ELSE ''OK''
              END,
              dt_concentracao_unico = GETDATE(),
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

IF OBJECT_ID('temp_CGUSC.fp.crm_concentracao_unico_metadata') IS NOT NULL
BEGIN
    SELECT
        id_pipeline,
        pipeline_nome,
        pipeline_versao,
        dt_data_inicio,
        dt_data_fim,
        nu_registros_fonte_uf,
        status,
        dt_criacao,
        dt_atualizacao,
        observacao
    FROM temp_CGUSC.fp.crm_concentracao_unico_metadata;
END;

EXEC sp_executesql
    N'SELECT
          uf_farmacia,
          status,
          etapa,
          status_concentracao_unico,
          nu_registros_fonte,
          nu_cnpjs_fonte,
          dt_concentracao_unico
      FROM temp_CGUSC.fp.crm_pipeline_uf_controle
      WHERE pipeline_versao = @versao
        AND dt_data_inicio = @inicio
        AND dt_data_fim = @fim
      ORDER BY uf_farmacia;',
    N'@versao VARCHAR(40), @inicio DATE, @fim DATE',
    @versao = @pipeline_versao,
    @inicio = @DataInicio,
    @fim = @DataFim;

IF OBJECT_ID('temp_CGUSC.fp.crm_concentracao_unico_alertas') IS NOT NULL
BEGIN
    -- Distribuição por severidade
    SELECT
        severidade,
        COUNT(*)                        AS qtd_alertas,
        COUNT(DISTINCT id_cnpj)         AS qtd_cnpjs,
        COUNT(DISTINCT id_medico)   AS qtd_medicos,
        AVG(nu_minutos_span)            AS media_minutos_span,
        AVG(nu_60min)                   AS media_rx_60min,
        MIN(dt_ini_concentracao)        AS primeiro_alerta,
        MAX(dt_ini_concentracao)        AS ultimo_alerta
    FROM temp_CGUSC.fp.crm_concentracao_unico_alertas
    GROUP BY severidade
    ORDER BY
        CASE severidade WHEN 'EXTREMO' THEN 1 WHEN 'CRÍTICO' THEN 2 WHEN 'GRAVE' THEN 3 ELSE 4 END;

    -- Top 30 piores casos
    SELECT TOP 30
        id_cnpj,
        id_medico,
        dt_dia,
        dt_ini_concentracao,
        dt_fim_concentracao,
        nu_minutos_span,
        nu_5min,
        nu_10min,
        nu_15min,
        nu_20min,
        nu_25min,
        nu_30min,
        nu_60min,
        severidade
    FROM temp_CGUSC.fp.crm_concentracao_unico_alertas
    ORDER BY
        CASE severidade WHEN 'EXTREMO' THEN 1 WHEN 'CRÍTICO' THEN 2 WHEN 'GRAVE' THEN 3 ELSE 4 END ASC,
        nu_60min DESC;
END;
