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
DROP TABLE IF EXISTS temp_CGUSC.fp.build_crm_concentracao_unico_uf_metadata;
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
DECLARE @pipeline_versao    VARCHAR(40) = 'v3_2026_05_12';
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

IF COL_LENGTH('temp_CGUSC.fp.build_crm_pipeline_uf_controle', 'status_concentracao_unico') IS NULL
    ALTER TABLE temp_CGUSC.fp.build_crm_pipeline_uf_controle ADD status_concentracao_unico VARCHAR(20) NULL;

IF COL_LENGTH('temp_CGUSC.fp.build_crm_pipeline_uf_controle', 'dt_concentracao_unico') IS NULL
    ALTER TABLE temp_CGUSC.fp.build_crm_pipeline_uf_controle ADD dt_concentracao_unico DATETIME NULL;

IF OBJECT_ID('temp_CGUSC.fp.build_crm_concentracao_unico_etapa_log') IS NULL
BEGIN
    CREATE TABLE temp_CGUSC.fp.build_crm_concentracao_unico_etapa_log (
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
        CONSTRAINT PK_BuildCrmConcentracaoUnicoEtapaLog PRIMARY KEY CLUSTERED (id_etapa_log)
    );

    CREATE INDEX IDX_CrmConcentracaoUnicoEtapaLog_UfPeriodo
        ON temp_CGUSC.fp.build_crm_concentracao_unico_etapa_log
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
          ''AGUARDANDO_CONCENTRACAO_UNICO'',
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
SET @nu_registros_fonte_uf = NULL;
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

IF @fonte_atual_ok = 0
BEGIN
    PRINT '>> Materializando movimentacao da UF ' + @uf_farmacia + '...';
    SET @t1 = GETDATE();

    EXEC sp_executesql
        N'UPDATE temp_CGUSC.fp.build_crm_pipeline_uf_controle
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
    DROP TABLE IF EXISTS #crm_cnpjs_fonte_atual;

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

    INSERT INTO temp_CGUSC.fp.build_crm_concentracao_unico_etapa_log
        (uf_farmacia, pipeline_versao, dt_data_inicio, dt_data_fim, etapa,
         dt_inicio_etapa, dt_fim_etapa, segundos_etapa, milissegundos_etapa,
         nu_registros, observacao)
    VALUES
        (@uf_farmacia, @pipeline_versao, @DataInicio, @DataFim, 'MATERIALIZANDO_FONTE_UF_SELECT_INTO',
         @t_bloco, @dt_fim_etapa, DATEDIFF(SECOND, @t_bloco, @dt_fim_etapa),
         DATEDIFF(MILLISECOND, @t_bloco, @dt_fim_etapa), @nu_registros_etapa,
         'SELECT INTO #crm_movimentacao_uf_atual.');

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

    CREATE CLUSTERED INDEX IDX_CrmMovimentacaoUfAtual_CnpjData
        ON #crm_movimentacao_uf_atual(id_cnpj, data_hora);

    SET @dt_fim_etapa = GETDATE();

    INSERT INTO temp_CGUSC.fp.build_crm_concentracao_unico_etapa_log
        (uf_farmacia, pipeline_versao, dt_data_inicio, dt_data_fim, etapa,
         dt_inicio_etapa, dt_fim_etapa, segundos_etapa, milissegundos_etapa, observacao)
    VALUES
        (@uf_farmacia, @pipeline_versao, @DataInicio, @DataFim, 'MATERIALIZANDO_FONTE_UF_IDX_CLUSTERED',
         @t_bloco, @dt_fim_etapa, DATEDIFF(SECOND, @t_bloco, @dt_fim_etapa),
         DATEDIFF(MILLISECOND, @t_bloco, @dt_fim_etapa),
         'Indice clustered #crm_movimentacao_uf_atual(id_cnpj, data_hora).');

    EXEC sp_executesql
        N'UPDATE temp_CGUSC.fp.build_crm_pipeline_uf_controle
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

    INSERT INTO temp_CGUSC.fp.build_crm_concentracao_unico_etapa_log
        (uf_farmacia, pipeline_versao, dt_data_inicio, dt_data_fim, etapa,
         dt_inicio_etapa, dt_fim_etapa, segundos_etapa, milissegundos_etapa, observacao)
    VALUES
        (@uf_farmacia, @pipeline_versao, @DataInicio, @DataFim, 'MATERIALIZANDO_FONTE_UF_IDX_CRM_DIA',
         @t_bloco, @dt_fim_etapa, DATEDIFF(SECOND, @t_bloco, @dt_fim_etapa),
         DATEDIFF(MILLISECOND, @t_bloco, @dt_fim_etapa),
         'Indice nonclustered #crm_movimentacao_uf_atual(id_cnpj, crm, crm_uf, data_hora).');

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

END

IF OBJECT_ID('tempdb..#crm_movimentacao_uf_atual') IS NULL
BEGIN
    RAISERROR('Tabela temporaria #crm_movimentacao_uf_atual nao encontrada apos materializacao/reuso da fonte UF.', 16, 1);
    RETURN;
END;

SET @t_bloco = GETDATE();

DROP TABLE IF EXISTS #crm_cnpjs_fonte_atual;

CREATE TABLE #crm_cnpjs_fonte_atual (
    id_cnpj INT      NOT NULL,
    cnpj    CHAR(14) NOT NULL
);

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

CREATE UNIQUE CLUSTERED INDEX IDX_CrmCnpjsFonteAtual
    ON #crm_cnpjs_fonte_atual(id_cnpj);

SET @nu_cnpjs_fonte = (
    SELECT COUNT(*)
    FROM #crm_cnpjs_fonte_atual
);

SET @dt_fim_etapa = GETDATE();

IF @fonte_atual_ok = 0
BEGIN
    INSERT INTO temp_CGUSC.fp.build_crm_concentracao_unico_etapa_log
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
        @nu_mov = @nu_registros_fonte_uf,
        @nu_cnpjs = @nu_cnpjs_fonte;

    PRINT '   Fonte UF materializada em: ' + CONVERT(VARCHAR(20), GETDATE() - @t1, 114);
END

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

DROP TABLE IF EXISTS temp_CGUSC.fp.build_crm_concentracao_unico_uf_metadata;

CREATE TABLE temp_CGUSC.fp.build_crm_concentracao_unico_uf_metadata (
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
    CONSTRAINT PK_BuildCrmConcentracaoUnicoUfMetadata PRIMARY KEY CLUSTERED (id_pipeline),
    CONSTRAINT CK_BuildCrmConcentracaoUnicoUfMetadata_Id CHECK (id_pipeline = 1)
);

INSERT INTO temp_CGUSC.fp.build_crm_concentracao_unico_uf_metadata
    (id_pipeline, pipeline_nome, pipeline_versao, dt_data_inicio, dt_data_fim,
     nu_registros_fonte_uf, dt_criacao, dt_atualizacao, status, observacao)
VALUES
    (1, @pipeline_nome, @pipeline_versao, @DataInicio, @DataFim,
     @nu_registros_fonte_uf, GETDATE(), GETDATE(), 'PROCESSANDO', 'Motor temporal CRM unico em processamento.');

IF OBJECT_ID('temp_CGUSC.fp.build_crm_pipeline_uf_controle') IS NOT NULL
    EXEC sp_executesql
        N'UPDATE temp_CGUSC.fp.build_crm_pipeline_uf_controle
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

IF OBJECT_ID('temp_CGUSC.fp.build_crm_concentracao_unico_lote_controle') IS NULL
    CREATE TABLE temp_CGUSC.fp.build_crm_concentracao_unico_lote_controle (
        id_cnpj    INT         NOT NULL,
        dt_inicio  DATETIME    NOT NULL,
        dt_fim     DATETIME    NULL,
        nu_alertas INT         NULL,
        status     VARCHAR(12) NOT NULL,
        CONSTRAINT PK_BuildConcentracaoUnicoLoteControle PRIMARY KEY CLUSTERED (id_cnpj)
    );

IF OBJECT_ID('temp_CGUSC.fp.build_crm_concentracao_unico_lote_log') IS NULL
BEGIN
    CREATE TABLE temp_CGUSC.fp.build_crm_concentracao_unico_lote_log (
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
        CONSTRAINT PK_BuildCrmConcentracaoUnicoLoteLog PRIMARY KEY CLUSTERED (id_lote_log)
    );

    CREATE INDEX IDX_CrmConcentracaoUnicoLoteLog_UfPeriodo
        ON temp_CGUSC.fp.build_crm_concentracao_unico_lote_log
            (uf_farmacia, pipeline_versao, dt_data_inicio, dt_data_fim, lote_num);
END;

SET @alertas_criada = 0;

IF OBJECT_ID('temp_CGUSC.fp.build_crm_concentracao_unico_alertas') IS NULL
BEGIN
    SET @alertas_criada = 1;

    CREATE TABLE temp_CGUSC.fp.build_crm_concentracao_unico_alertas (
        id_cnpj             INT             NOT NULL,
        id_medico           VARCHAR(12)     NOT NULL,
        dt_dia              DATE            NOT NULL,
        dt_ini_concentracao DATETIME        NOT NULL,
        dt_fim_concentracao DATETIME        NOT NULL,
        nu_minutos_span     TINYINT         NOT NULL,
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
    CREATE CLUSTERED INDEX IDX_ConcentracaoUnicoAlertas
        ON temp_CGUSC.fp.build_crm_concentracao_unico_alertas(id_cnpj, id_medico, dt_dia);
END

IF OBJECT_ID('temp_CGUSC.fp.build_crm_concentracao_unico_alertas') IS NOT NULL
   AND (
       COL_LENGTH('temp_CGUSC.fp.build_crm_concentracao_unico_alertas', 'id_medico') <> 12
       OR COL_LENGTH('temp_CGUSC.fp.build_crm_concentracao_unico_alertas', 'severidade') IS NOT NULL
       OR COL_LENGTH('temp_CGUSC.fp.build_crm_concentracao_unico_alertas', 'id_severidade') IS NULL
       OR COL_LENGTH('temp_CGUSC.fp.build_crm_concentracao_unico_alertas', 'janela_pior_ritmo_minutos') IS NULL
       OR COL_LENGTH('temp_CGUSC.fp.build_crm_concentracao_unico_alertas', 'nu_autorizacoes_pior_ritmo') IS NULL
       OR COL_LENGTH('temp_CGUSC.fp.build_crm_concentracao_unico_alertas', 'taxa_hora_pior_ritmo') IS NULL
       OR COL_LENGTH('temp_CGUSC.fp.build_crm_concentracao_unico_alertas', 'criterio_pior_ritmo') IS NULL
   )
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.build_crm_concentracao_unico_alertas existe com schema antigo. Recrie a tabela e o controle de lotes para a versao atual.', 16, 1);
    RETURN;
END;

IF @alertas_criada = 1
   AND EXISTS (
       SELECT 1
       FROM temp_CGUSC.fp.build_crm_concentracao_unico_lote_controle
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
FROM temp_CGUSC.fp.build_crm_concentracao_unico_alertas alerta
INNER JOIN temp_CGUSC.fp.build_crm_concentracao_unico_lote_controle ctrl
    ON ctrl.id_cnpj = alerta.id_cnpj
WHERE ctrl.status = 'PROCESSANDO';

DELETE FROM temp_CGUSC.fp.build_crm_concentracao_unico_lote_controle
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
    FROM temp_CGUSC.fp.build_crm_concentracao_unico_lote_controle L
    WHERE L.id_cnpj = C.id_cnpj
      AND L.status = 'OK'
);

SET @nu_pendentes      = (SELECT COUNT(*) FROM #cnpjs_pendentes);
SET @nu_ja_processados = (
    SELECT COUNT(*)
    FROM temp_CGUSC.fp.build_crm_concentracao_unico_lote_controle C
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

    INSERT INTO temp_CGUSC.fp.build_crm_concentracao_unico_lote_log
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

    UPDATE temp_CGUSC.fp.build_crm_concentracao_unico_lote_log
    SET qtd_cnpjs_lote = @qtd_cnpjs_lote
    WHERE id_lote_log = @id_lote_log;

    PRINT '      3.0 Selecionar lote: ' + CONVERT(VARCHAR(20), GETDATE() - @t_bloco, 114);

    -- ── Marcar lote como PROCESSANDO ─────────────────────────────────────
    SET @t_bloco = GETDATE();
    INSERT INTO temp_CGUSC.fp.build_crm_concentracao_unico_lote_controle (id_cnpj, dt_inicio, status)
    SELECT id_cnpj, GETDATE(), 'PROCESSANDO'
    FROM #lote_atual L
    WHERE NOT EXISTS (
        SELECT 1
        FROM temp_CGUSC.fp.build_crm_concentracao_unico_lote_controle C
        WHERE C.id_cnpj = L.id_cnpj
    );

    UPDATE C
    SET status = 'PROCESSANDO',
        dt_inicio = GETDATE(),
        dt_fim = NULL,
        nu_alertas = NULL
    FROM temp_CGUSC.fp.build_crm_concentracao_unico_lote_controle C
    INNER JOIN #lote_atual L ON L.id_cnpj = C.id_cnpj;

    PRINT '      3.0 Marcar PROCESSANDO: ' + CONVERT(VARCHAR(20), GETDATE() - @t_bloco, 114);

    -- ── Passo 3.A: Criar base pré-filtrada por patologia para o lote ──────
    -- Isso reduz o volume de dados e remove a necessidade de joins repetidos
    -- com a tabela de medicamentos dentro do sliding window.
    -- Isso colapsa múltiplos itens de uma mesma autorização no mesmo instante.
    SET @t_bloco = GETDATE();
    DROP TABLE IF EXISTS #base_lote;

    IF EXISTS (
        SELECT 1
        FROM #crm_movimentacao_uf_atual A
        INNER JOIN #lote_atual L ON L.id_cnpj = A.id_cnpj
        WHERE LEN(A.crm) > 9
    )
    BEGIN
        RAISERROR('CRM com mais de 9 caracteres encontrado. id_medico VARCHAR(12) exige CRM com ate 9 caracteres mais /UF.', 16, 1);
        RETURN;
    END;

    SELECT 
        L.id_cnpj,
        CAST(A.data_hora AS DATE) AS dt_dia,
        A.data_hora,
        A.num_autorizacao,
        CAST(A.crm + '/' + A.crm_uf AS VARCHAR(12)) AS id_medico
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

    -- Deduplicacao: 1 evento por bloco continuo/sobreposto de concentracao.
    -- Janelas sliding do mesmo medico que se sobrepoem viram um unico alerta,
    -- mantendo a melhor severidade/ritmo dentro do bloco.
    SET @t_bloco = GETDATE();
    DROP TABLE IF EXISTS #concentracao_candidatos;
    DROP TABLE IF EXISTS #concentracao_dedup;

    SELECT id_cnpj, id_medico, dt_dia, dt_ini_concentracao, dt_fim_concentracao, nu_minutos_span,
           nu_5min, nu_10min, nu_15min, nu_20min, nu_25min, nu_30min, nu_60min,
           id_severidade, janela_pior_ritmo_minutos, nu_autorizacoes_pior_ritmo,
           taxa_hora_pior_ritmo, criterio_pior_ritmo
    INTO #concentracao_candidatos
    FROM (
        SELECT
            Base.id_cnpj,
            Base.id_medico,
            CAST(Base.janela_inicio AS DATE)                                  AS dt_dia,
            CAST(Base.janela_inicio AS DATETIME)                              AS dt_ini_concentracao,
            CAST(Ritmo.dt_fim_real AS DATETIME)                               AS dt_fim_concentracao,
            CAST(
                CASE
                    WHEN DATEDIFF(SECOND, Base.janela_inicio, Ritmo.dt_fim_real) <= 0 THEN 1
                    ELSE CEILING(DATEDIFF(SECOND, Base.janela_inicio, Ritmo.dt_fim_real) / 60.0)
                END AS TINYINT
            ) AS nu_minutos_span,
            CAST(Base.nu_5min AS SMALLINT)                                    AS nu_5min,
            CAST(Base.nu_10min AS SMALLINT)                                   AS nu_10min,
            CAST(Base.nu_15min AS SMALLINT)                                   AS nu_15min,
            CAST(Base.nu_20min AS SMALLINT)                                   AS nu_20min,
            CAST(Base.nu_25min AS SMALLINT)                                   AS nu_25min,
            CAST(Base.nu_30min AS SMALLINT)                                   AS nu_30min,
            CAST(Base.nu_60min AS SMALLINT)                                   AS nu_60min,
            Base.id_severidade,
            Ritmo.janela_pior_ritmo_minutos,
            Ritmo.nu_autorizacoes_pior_ritmo,
            Ritmo.taxa_hora_pior_ritmo,
            Ritmo.criterio_pior_ritmo
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
                    WHEN nu_5min  >=  7 THEN 4
                    WHEN nu_10min >= 10 THEN 4
                    WHEN nu_5min  >=  6 THEN 3
                    WHEN nu_10min >=  8 THEN 3
                    WHEN nu_15min >=  8 THEN 2
                    WHEN nu_20min >=  9 THEN 2
                    WHEN nu_30min >=  8 THEN 1
                    WHEN nu_60min >= 12 THEN 1
                    WHEN nu_25min >=  6 THEN 1
                    WHEN nu_60min >=  8 AND nu_minutos_span_full <= nu_60min * 5 THEN 1
                END AS id_severidade
            FROM #concentracao_raw
        ) Base
        CROSS APPLY (
            SELECT TOP 1
                V.dt_fim_real,
                V.janela_pior_ritmo_minutos,
                V.nu_autorizacoes_pior_ritmo,
                CAST(
                    V.nu_autorizacoes_pior_ritmo * 60.0 /
                    NULLIF(
                        CASE
                            WHEN DATEDIFF(SECOND, Base.janela_inicio, V.dt_fim_real) <= 0 THEN 1
                            ELSE CEILING(DATEDIFF(SECOND, Base.janela_inicio, V.dt_fim_real) / 60.0)
                        END,
                        0
                    ) AS DECIMAL(7,2)
                ) AS taxa_hora_pior_ritmo,
                V.criterio_pior_ritmo
            FROM (VALUES
                (Base.fim_real_5min,  CAST(5 AS TINYINT),  CAST(Base.nu_5min AS SMALLINT),  CAST(4 AS TINYINT), CAST(1 AS TINYINT),  CAST('7_EM_5MIN' AS VARCHAR(30)),    CASE WHEN Base.nu_5min >= 7 THEN 1 ELSE 0 END),
                (Base.fim_real_10min, CAST(10 AS TINYINT), CAST(Base.nu_10min AS SMALLINT), CAST(4 AS TINYINT), CAST(2 AS TINYINT),  CAST('10_EM_10MIN' AS VARCHAR(30)),  CASE WHEN Base.nu_10min >= 10 THEN 1 ELSE 0 END),
                (Base.fim_real_5min,  CAST(5 AS TINYINT),  CAST(Base.nu_5min AS SMALLINT),  CAST(3 AS TINYINT), CAST(3 AS TINYINT),  CAST('6_EM_5MIN' AS VARCHAR(30)),    CASE WHEN Base.nu_5min >= 6 THEN 1 ELSE 0 END),
                (Base.fim_real_10min, CAST(10 AS TINYINT), CAST(Base.nu_10min AS SMALLINT), CAST(3 AS TINYINT), CAST(4 AS TINYINT),  CAST('8_EM_10MIN' AS VARCHAR(30)),   CASE WHEN Base.nu_10min >= 8 THEN 1 ELSE 0 END),
                (Base.fim_real_15min, CAST(15 AS TINYINT), CAST(Base.nu_15min AS SMALLINT), CAST(2 AS TINYINT), CAST(5 AS TINYINT),  CAST('8_EM_15MIN' AS VARCHAR(30)),   CASE WHEN Base.nu_15min >= 8 THEN 1 ELSE 0 END),
                (Base.fim_real_20min, CAST(20 AS TINYINT), CAST(Base.nu_20min AS SMALLINT), CAST(2 AS TINYINT), CAST(6 AS TINYINT),  CAST('9_EM_20MIN' AS VARCHAR(30)),   CASE WHEN Base.nu_20min >= 9 THEN 1 ELSE 0 END),
                (Base.fim_real_30min, CAST(30 AS TINYINT), CAST(Base.nu_30min AS SMALLINT), CAST(1 AS TINYINT), CAST(7 AS TINYINT),  CAST('8_EM_30MIN' AS VARCHAR(30)),   CASE WHEN Base.nu_30min >= 8 THEN 1 ELSE 0 END),
                (Base.fim_real_60min, CAST(60 AS TINYINT), CAST(Base.nu_60min AS SMALLINT), CAST(1 AS TINYINT), CAST(8 AS TINYINT),  CAST('12_EM_60MIN' AS VARCHAR(30)),  CASE WHEN Base.nu_60min >= 12 THEN 1 ELSE 0 END),
                (Base.fim_real_25min, CAST(25 AS TINYINT), CAST(Base.nu_25min AS SMALLINT), CAST(1 AS TINYINT), CAST(9 AS TINYINT),  CAST('6_EM_25MIN' AS VARCHAR(30)),   CASE WHEN Base.nu_25min >= 6 THEN 1 ELSE 0 END),
                (Base.fim_real_60min, CAST(60 AS TINYINT), CAST(Base.nu_60min AS SMALLINT), CAST(1 AS TINYINT), CAST(10 AS TINYINT), CAST('TAXA_12_HORA' AS VARCHAR(30)), CASE WHEN Base.nu_60min >= 8 AND Base.nu_minutos_span_full <= Base.nu_60min * 5 THEN 1 ELSE 0 END)
            ) V(dt_fim_real, janela_pior_ritmo_minutos, nu_autorizacoes_pior_ritmo, id_severidade_criterio, prioridade_criterio, criterio_pior_ritmo, atingiu)
            WHERE V.atingiu = 1
            ORDER BY
                V.nu_autorizacoes_pior_ritmo * 60.0 /
                    NULLIF(
                        CASE
                            WHEN DATEDIFF(SECOND, Base.janela_inicio, V.dt_fim_real) <= 0 THEN 1
                            ELSE CEILING(DATEDIFF(SECOND, Base.janela_inicio, V.dt_fim_real) / 60.0)
                        END,
                        0
                    ) DESC,
                V.id_severidade_criterio DESC,
                V.prioridade_criterio ASC
        ) Ritmo
        WHERE Base.id_severidade IS NOT NULL
    ) sub
    WHERE id_severidade IS NOT NULL;

    IF EXISTS (
        SELECT 1
        FROM #concentracao_candidatos
        WHERE nu_minutos_span <= 0
           OR taxa_hora_pior_ritmo IS NULL
    )
    BEGIN
        RAISERROR('Alerta CRM unico com intervalo real invalido para calcular taxa/hora.', 16, 1);
        RETURN;
    END;

    ;WITH ordenado AS (
        SELECT
            C.*,
            MAX(C.dt_fim_concentracao) OVER (
                PARTITION BY C.id_cnpj, C.id_medico, C.dt_dia
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
                PARTITION BY id_cnpj, id_medico, dt_dia
                ORDER BY dt_ini_concentracao, dt_fim_concentracao
                ROWS UNBOUNDED PRECEDING
            ) AS grupo_sobreposicao
        FROM marcado
    ),
    ranked AS (
        SELECT
            *,
            ROW_NUMBER() OVER (
                PARTITION BY id_cnpj, id_medico, dt_dia, grupo_sobreposicao
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
                    dt_ini_concentracao ASC
            ) AS rn_bloco
        FROM agrupado
    )
    SELECT
        id_cnpj,
        id_medico,
        dt_dia,
        dt_ini_concentracao,
        dt_fim_concentracao,
        nu_minutos_span,
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
    INSERT INTO temp_CGUSC.fp.build_crm_concentracao_unico_alertas
        (id_cnpj, id_medico, dt_dia, dt_ini_concentracao, dt_fim_concentracao, nu_minutos_span,
         nu_5min, nu_10min, nu_15min, nu_20min, nu_25min, nu_30min, nu_60min,
         id_severidade, janela_pior_ritmo_minutos, nu_autorizacoes_pior_ritmo,
         taxa_hora_pior_ritmo, criterio_pior_ritmo)
    SELECT id_cnpj, id_medico, dt_dia, dt_ini_concentracao, dt_fim_concentracao, nu_minutos_span,
           nu_5min, nu_10min, nu_15min, nu_20min, nu_25min, nu_30min, nu_60min,
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
            FROM temp_CGUSC.fp.build_crm_concentracao_unico_alertas a
            WHERE a.id_cnpj = ctrl.id_cnpj
        ), 0)
    FROM temp_CGUSC.fp.build_crm_concentracao_unico_lote_controle ctrl
    WHERE ctrl.id_cnpj IN (SELECT id_cnpj FROM #lote_atual);

    PRINT '      3.E Atualizar controle: ' + CONVERT(VARCHAR(20), GETDATE() - @t_bloco, 114);

    -- ── Remover lote da fila e atualizar contadores ───────────────────────
    SET @t_bloco = GETDATE();
    DELETE FROM #cnpjs_pendentes WHERE id_cnpj IN (SELECT id_cnpj FROM #lote_atual);

    SET @nu_processados += (SELECT COUNT(*) FROM #lote_atual);

    PRINT '      3.F Remover da fila: ' + CONVERT(VARCHAR(20), GETDATE() - @t_bloco, 114);

    SET @dt_fim_lote = GETDATE();

    UPDATE temp_CGUSC.fp.build_crm_concentracao_unico_lote_log
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
UPDATE temp_CGUSC.fp.build_crm_concentracao_unico_uf_metadata
SET status = CASE
        WHEN EXISTS (
            SELECT 1
            FROM temp_CGUSC.fp.build_crm_concentracao_unico_lote_controle C
            INNER JOIN #crm_cnpjs_fonte_atual F ON F.id_cnpj = C.id_cnpj
            WHERE C.status <> 'OK'
        ) THEN 'INCOMPLETO'
        ELSE 'OK'
    END,
    dt_atualizacao = GETDATE(),
    observacao = 'Motor temporal CRM unico finalizado.'
WHERE id_pipeline = 1;

IF OBJECT_ID('temp_CGUSC.fp.build_crm_pipeline_uf_controle') IS NOT NULL
    EXEC sp_executesql
        N'UPDATE temp_CGUSC.fp.build_crm_pipeline_uf_controle
          SET status = ''PROCESSANDO'',
              etapa = CASE
                  WHEN EXISTS (
                      SELECT 1
                      FROM temp_CGUSC.fp.build_crm_concentracao_unico_lote_controle C
                      INNER JOIN #crm_cnpjs_fonte_atual F ON F.id_cnpj = C.id_cnpj
                      WHERE C.status <> ''OK''
                  ) THEN ''CONCENTRACAO_UNICO_INCOMPLETA''
                  ELSE ''CONCENTRACAO_UNICO_OK''
              END,
              status_concentracao_unico = CASE
                  WHEN EXISTS (
                      SELECT 1
                      FROM temp_CGUSC.fp.build_crm_concentracao_unico_lote_controle C
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

IF OBJECT_ID('temp_CGUSC.fp.build_crm_concentracao_unico_uf_metadata') IS NOT NULL
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
    FROM temp_CGUSC.fp.build_crm_concentracao_unico_uf_metadata;
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
      FROM temp_CGUSC.fp.build_crm_pipeline_uf_controle
      WHERE pipeline_versao = @versao
        AND dt_data_inicio = @inicio
        AND dt_data_fim = @fim
      ORDER BY uf_farmacia;',
    N'@versao VARCHAR(40), @inicio DATE, @fim DATE',
    @versao = @pipeline_versao,
    @inicio = @DataInicio,
    @fim = @DataFim;

IF OBJECT_ID('temp_CGUSC.fp.build_crm_concentracao_unico_alertas') IS NOT NULL
BEGIN
    -- Distribuição por severidade
    SELECT
        id_severidade,
        CASE id_severidade
            WHEN 4 THEN 'EXTREMO'
            WHEN 3 THEN 'CRITICO'
            WHEN 2 THEN 'GRAVE'
            WHEN 1 THEN 'ALTO'
        END AS severidade,
        COUNT(*)                        AS qtd_alertas,
        COUNT(DISTINCT id_cnpj)         AS qtd_cnpjs,
        COUNT(DISTINCT id_medico)   AS qtd_medicos,
        AVG(nu_minutos_span)            AS media_minutos_span,
        AVG(nu_60min)                   AS media_rx_60min,
        AVG(taxa_hora_pior_ritmo)       AS media_taxa_hora_pior_ritmo,
        MIN(dt_ini_concentracao)        AS primeiro_alerta,
        MAX(dt_ini_concentracao)        AS ultimo_alerta
    FROM temp_CGUSC.fp.build_crm_concentracao_unico_alertas
    GROUP BY id_severidade
    ORDER BY id_severidade DESC;

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
    FROM temp_CGUSC.fp.build_crm_concentracao_unico_alertas
    ORDER BY
        id_severidade DESC,
        taxa_hora_pior_ritmo DESC,
        nu_60min DESC;
END;
