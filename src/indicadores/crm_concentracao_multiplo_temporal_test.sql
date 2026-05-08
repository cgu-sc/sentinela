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
DROP TABLE IF EXISTS temp_CGUSC.fp.crm_concentracao_multiplo_metadata;
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
DECLARE @pipeline_versao    VARCHAR(40) = 'v2_2026_05_07';
DECLARE @nu_registros_teste_mov_sc BIGINT;
DECLARE @uf_farmacia CHAR(2);
DECLARE @uf_farmacia_alvo CHAR(2) = NULL;
DECLARE @reset_fonte_uf BIT = 0;
DECLARE @nu_cnpjs_fonte INT;
DECLARE @nu_ufs_processadas INT = 0;
DECLARE @nu_alertas_total_geral INT = 0;
DECLARE @fonte_atual_ok BIT = 0;

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

IF COL_LENGTH('temp_CGUSC.fp.crm_pipeline_uf_controle', 'status_concentracao_multiplo') IS NULL
    ALTER TABLE temp_CGUSC.fp.crm_pipeline_uf_controle ADD status_concentracao_multiplo VARCHAR(20) NULL;

IF COL_LENGTH('temp_CGUSC.fp.crm_pipeline_uf_controle', 'dt_concentracao_multiplo') IS NULL
    ALTER TABLE temp_CGUSC.fp.crm_pipeline_uf_controle ADD dt_concentracao_multiplo DATETIME NULL;

EXEC sp_executesql
    N'INSERT INTO temp_CGUSC.fp.crm_pipeline_uf_controle
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
SET @nu_registros_teste_mov_sc = NULL;
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

IF @fonte_atual_ok = 0
BEGIN
    PRINT '>> Materializando movimentacao da UF ' + @uf_farmacia + '...';
    SET @t1 = GETDATE();

    EXEC sp_executesql
        N'UPDATE temp_CGUSC.fp.crm_pipeline_uf_controle
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

    CREATE CLUSTERED INDEX IDX_CrmMovFonteAtual_UfCnpjData
        ON #crm_mov_fonte_atual(uf_farmacia, id_cnpj, data_hora);

    CREATE NONCLUSTERED INDEX IDX_CrmMovFonteAtual_CnpjData
        ON #crm_mov_fonte_atual(cnpj, data_hora)
        INCLUDE (id_cnpj, crm, crm_uf, num_autorizacao, valor_pago, codigo_barra);

    CREATE NONCLUSTERED INDEX IDX_CrmMovFonteAtual_CrmData
        ON #crm_mov_fonte_atual(id_cnpj, crm, crm_uf, data_hora)
        INCLUDE (cnpj, num_autorizacao, valor_pago, codigo_barra);

    SELECT @nu_registros_teste_mov_sc = ISNULL(SUM(P.rows), 0)
    FROM tempdb.sys.partitions P
    WHERE P.object_id = OBJECT_ID('tempdb..#crm_mov_fonte_atual')
      AND P.index_id IN (0, 1);

    SET @nu_cnpjs_fonte = (
        SELECT COUNT(DISTINCT id_cnpj)
        FROM #crm_mov_fonte_atual
    );

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
        @nu_mov = @nu_registros_teste_mov_sc,
        @nu_cnpjs = @nu_cnpjs_fonte;

    PRINT '   Fonte UF materializada em: ' + CONVERT(VARCHAR(20), GETDATE() - @t1, 114);
END

SELECT @nu_registros_teste_mov_sc = ISNULL(SUM(P.rows), 0)
FROM tempdb.sys.partitions P
WHERE P.object_id = OBJECT_ID('tempdb..#crm_mov_fonte_atual')
  AND P.index_id IN (0, 1);

PRINT '>> [CRM MULTIPLO] Iniciando detecção de concentração temporal...';
PRINT '   UF fonte: ' + @uf_farmacia;
PRINT '   Período: ' + CAST(@DataInicio AS VARCHAR(10)) + ' → ' + CAST(@DataFim AS VARCHAR(10));
PRINT '   Lote: ' + CAST(@lote_size AS VARCHAR) + ' CNPJs por iteração';

DROP TABLE IF EXISTS temp_CGUSC.fp.crm_concentracao_multiplo_metadata;

CREATE TABLE temp_CGUSC.fp.crm_concentracao_multiplo_metadata (
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
    CONSTRAINT PK_CrmConcentracaoMultiploMetadata PRIMARY KEY CLUSTERED (id_pipeline),
    CONSTRAINT CK_CrmConcentracaoMultiploMetadata_Id CHECK (id_pipeline = 1)
);

INSERT INTO temp_CGUSC.fp.crm_concentracao_multiplo_metadata
    (id_pipeline, pipeline_nome, pipeline_versao, dt_data_inicio, dt_data_fim,
     nu_registros_teste_mov_sc, dt_criacao, dt_atualizacao, status, observacao)
VALUES
    (1, @pipeline_nome, @pipeline_versao, @DataInicio, @DataFim,
     @nu_registros_teste_mov_sc, GETDATE(), GETDATE(), 'PROCESSANDO', 'Motor temporal CRM multiplo em processamento.');

IF OBJECT_ID('temp_CGUSC.fp.crm_pipeline_uf_controle') IS NOT NULL
    EXEC sp_executesql
        N'UPDATE temp_CGUSC.fp.crm_pipeline_uf_controle
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

IF OBJECT_ID('temp_CGUSC.fp.crm_concentracao_multiplo_controle') IS NULL
    CREATE TABLE temp_CGUSC.fp.crm_concentracao_multiplo_controle (
        id_cnpj    INT         NOT NULL,
        dt_inicio  DATETIME    NOT NULL,
        dt_fim     DATETIME    NULL,
        nu_alertas INT         NULL,
        status     VARCHAR(12) NOT NULL,
        CONSTRAINT PK_ConcentracaoMultiploControle PRIMARY KEY CLUSTERED (id_cnpj)
    );

IF OBJECT_ID('temp_CGUSC.fp.crm_concentracao_multiplo_alertas') IS NULL
BEGIN
    CREATE TABLE temp_CGUSC.fp.crm_concentracao_multiplo_alertas (
        id_cnpj             INT             NOT NULL,
        dt_dia              DATE            NOT NULL,
        dt_ini_concentracao SMALLDATETIME   NOT NULL,
        dt_fim_concentracao SMALLDATETIME   NOT NULL,
        nu_minutos_span     TINYINT         NOT NULL,
        nu_crms_distintos   TINYINT         NOT NULL,
        nu_5min             SMALLINT        NOT NULL,
        nu_10min            SMALLINT        NOT NULL,
        nu_15min            SMALLINT        NOT NULL,
        nu_20min            SMALLINT        NOT NULL,
        nu_25min            SMALLINT        NOT NULL,
        nu_30min            SMALLINT        NOT NULL,
        nu_60min            SMALLINT        NOT NULL,
        severidade          VARCHAR(10)     NOT NULL
    );
    CREATE CLUSTERED INDEX IDX_ConcentracaoMultiploAlertas
        ON temp_CGUSC.fp.crm_concentracao_multiplo_alertas(id_cnpj, dt_dia);
END

PRINT '   Passo 0 concluido em: ' + CONVERT(VARCHAR(20), GETDATE() - @t1, 114);


-- ============================================================================
-- PASSO 1: Limpar CNPJs interrompidos para reprocessar do zero
-- ============================================================================
PRINT '>> Passo 1: Limpando CNPJs interrompidos (status PROCESSANDO)...';
SET @t1 = GETDATE();

DELETE alerta
FROM temp_CGUSC.fp.crm_concentracao_multiplo_alertas alerta
INNER JOIN temp_CGUSC.fp.crm_concentracao_multiplo_controle ctrl
    ON ctrl.id_cnpj = alerta.id_cnpj
WHERE ctrl.status = 'PROCESSANDO';

DELETE FROM temp_CGUSC.fp.crm_concentracao_multiplo_controle
WHERE status = 'PROCESSANDO';

PRINT '   Limpeza concluida em: ' + CONVERT(VARCHAR(20), GETDATE() - @t1, 114);


-- ============================================================================
-- PASSO 2: Construir fila de CNPJs pendentes
-- ============================================================================
PRINT '>> Passo 2: Construindo fila de CNPJs pendentes...';
SET @t1 = GETDATE();

DROP TABLE IF EXISTS #cnpjs_pendentes;

SELECT DISTINCT F.id AS id_cnpj
INTO #cnpjs_pendentes
FROM #crm_mov_fonte_atual A
INNER JOIN temp_CGUSC.fp.medicamentos_patologia PA ON PA.codigo_barra = A.codigo_barra
INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = A.cnpj
WHERE A.crm    IS NOT NULL
  AND A.crm_uf IS NOT NULL
  AND A.crm_uf <> 'BR'
  AND A.data_hora >= @DataInicio
  AND A.data_hora < DATEADD(DAY, 1, @DataFim)
  AND F.id NOT IN (
      SELECT id_cnpj FROM temp_CGUSC.fp.crm_concentracao_multiplo_controle WHERE status = 'OK'
  );

SET @nu_pendentes      = (SELECT COUNT(*) FROM #cnpjs_pendentes);
SET @nu_ja_processados = (
    SELECT COUNT(*)
    FROM temp_CGUSC.fp.crm_concentracao_multiplo_controle C
    WHERE C.status = 'OK'
      AND EXISTS (
          SELECT 1
          FROM #crm_mov_fonte_atual F
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

    -- ── Pegar próximo lote da fila ────────────────────────────────────────
    SET @t_bloco = GETDATE();
    DROP TABLE IF EXISTS #lote_atual;

    SELECT TOP (@lote_size) id_cnpj
    INTO #lote_atual
    FROM #cnpjs_pendentes
    ORDER BY id_cnpj;

    PRINT '      3.0 Selecionar lote: ' + CONVERT(VARCHAR(20), GETDATE() - @t_bloco, 114);

    -- ── Marcar lote como PROCESSANDO ─────────────────────────────────────
    SET @t_bloco = GETDATE();
    INSERT INTO temp_CGUSC.fp.crm_concentracao_multiplo_controle (id_cnpj, dt_inicio, status)
    SELECT id_cnpj, GETDATE(), 'PROCESSANDO'
    FROM #lote_atual L
    WHERE NOT EXISTS (
        SELECT 1
        FROM temp_CGUSC.fp.crm_concentracao_multiplo_controle C
        WHERE C.id_cnpj = L.id_cnpj
    );

    UPDATE C
    SET status = 'PROCESSANDO',
        dt_inicio = GETDATE(),
        dt_fim = NULL,
        nu_alertas = NULL
    FROM temp_CGUSC.fp.crm_concentracao_multiplo_controle C
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
    INNER JOIN temp_CGUSC.fp.medicamentos_patologia PA ON PA.codigo_barra = A.codigo_barra
    INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = A.cnpj
    INNER JOIN #lote_atual L ON L.id_cnpj = F.id
    WHERE A.crm    IS NOT NULL AND A.crm_uf    IS NOT NULL AND A.crm_uf    <> 'BR'
      AND A.data_hora >= @DataInicio AND A.data_hora < DATEADD(DAY, 1, @DataFim)
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

            COUNT(DISTINCT B.id_medico)                                            AS nu_crms_distintos,

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
    WHERE nu_crms_distintos >= 2
    AND (
           nu_5min  >=  6
        OR nu_10min >=  8
        OR nu_15min >= 10
        OR nu_20min >= 11
        OR nu_25min >= 12
        OR nu_30min >= 12
        OR nu_60min >= 18
        OR (nu_60min >= 15 AND nu_minutos_span_full <= nu_60min * 3)
    );

    PRINT '      3.B Self-join concentracao_raw: ' + CONVERT(VARCHAR(20), GETDATE() - @t_bloco, 114);

    -- ── Deduplicação: 1 evento por janela de 60 min por cnpj/hora ─────────
    SET @t_bloco = GETDATE();
    DROP TABLE IF EXISTS #concentracao_dedup;

    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY
                id_cnpj,
                CAST(janela_inicio AS DATE),
                DATEDIFF(MINUTE, 0, janela_inicio) / 60
            ORDER BY
                CASE
                    WHEN nu_5min  >=  8 THEN 1
                    WHEN nu_10min >= 11 THEN 1
                    WHEN nu_5min  >=  6 THEN 2
                    WHEN nu_10min >=  8 THEN 2
                    WHEN nu_15min >= 10 THEN 3
                    WHEN nu_20min >= 11 THEN 3
                    WHEN nu_25min >= 12 THEN 4
                    WHEN nu_30min >= 12 THEN 4
                    WHEN nu_60min >= 18 THEN 4
                    WHEN nu_60min >= 15 AND nu_minutos_span_full <= nu_60min * 3 THEN 4
                    ELSE 99
                END ASC,
                nu_60min DESC,
                nu_30min DESC,
                nu_25min DESC,
                nu_20min DESC,
                nu_15min DESC,
                nu_10min DESC,
                nu_5min DESC,
                nu_crms_distintos DESC,
                janela_inicio ASC
        ) AS rn
    INTO #concentracao_dedup
    FROM #concentracao_raw;

    PRINT '      3.C Deduplicacao: ' + CONVERT(VARCHAR(20), GETDATE() - @t_bloco, 114);

    -- ── INSERT incremental nos alertas ────────────────────────────────────
    SET @t_bloco = GETDATE();
    INSERT INTO temp_CGUSC.fp.crm_concentracao_multiplo_alertas
        (id_cnpj, dt_dia, dt_ini_concentracao, dt_fim_concentracao, nu_minutos_span,
         nu_crms_distintos, nu_5min, nu_10min, nu_15min, nu_20min, nu_25min, nu_30min, nu_60min, severidade)
    SELECT id_cnpj, dt_dia, dt_ini_concentracao, dt_fim_concentracao, nu_minutos_span,
           nu_crms_distintos, nu_5min, nu_10min, nu_15min, nu_20min, nu_25min, nu_30min, nu_60min, severidade
    FROM (
        SELECT
            id_cnpj,
            CAST(janela_inicio AS DATE)                                     AS dt_dia,
            CAST(janela_inicio AS SMALLDATETIME)                            AS dt_ini_concentracao,
            CAST(dt_fim_real AS SMALLDATETIME)                              AS dt_fim_concentracao,
            CAST(DATEDIFF(MINUTE, janela_inicio, dt_fim_real) AS TINYINT)    AS nu_minutos_span,
            CAST(nu_crms_distintos AS TINYINT)                              AS nu_crms_distintos,
            CAST(nu_5min AS SMALLINT)                                       AS nu_5min,
            CAST(nu_10min AS SMALLINT)                                      AS nu_10min,
            CAST(nu_15min AS SMALLINT)                                      AS nu_15min,
            CAST(nu_20min AS SMALLINT)                                      AS nu_20min,
            CAST(nu_25min AS SMALLINT)                                      AS nu_25min,
            CAST(nu_30min AS SMALLINT)                                      AS nu_30min,
            CAST(nu_60min AS SMALLINT)                                      AS nu_60min,
            severidade
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
                    WHEN nu_5min  >=  8 THEN 'EXTREMO'
                    WHEN nu_10min >= 11 THEN 'EXTREMO'
                    WHEN nu_5min  >=  6 THEN 'CRÍTICO'
                    WHEN nu_10min >=  8 THEN 'CRÍTICO'
                    WHEN nu_15min >= 10 THEN 'GRAVE'
                    WHEN nu_20min >= 11 THEN 'GRAVE'
                    WHEN nu_25min >= 12 THEN 'ALTO'
                    WHEN nu_30min >= 12 THEN 'ALTO'
                    WHEN nu_60min >= 18 THEN 'ALTO'
                    WHEN nu_60min >= 15 AND nu_minutos_span_full <= nu_60min * 3 THEN 'ALTO'
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
            FROM temp_CGUSC.fp.crm_concentracao_multiplo_alertas a
            WHERE a.id_cnpj = ctrl.id_cnpj
        ), 0)
    FROM temp_CGUSC.fp.crm_concentracao_multiplo_controle ctrl
    WHERE ctrl.id_cnpj IN (SELECT id_cnpj FROM #lote_atual);

    PRINT '      3.E Atualizar controle: ' + CONVERT(VARCHAR(20), GETDATE() - @t_bloco, 114);

    -- ── Remover lote da fila e atualizar contadores ───────────────────────
    SET @t_bloco = GETDATE();
    DELETE FROM #cnpjs_pendentes WHERE id_cnpj IN (SELECT id_cnpj FROM #lote_atual);

    SET @nu_processados += (SELECT COUNT(*) FROM #lote_atual);

    PRINT '      3.F Remover da fila: ' + CONVERT(VARCHAR(20), GETDATE() - @t_bloco, 114);

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
UPDATE temp_CGUSC.fp.crm_concentracao_multiplo_metadata
SET status = CASE
        WHEN EXISTS (
            SELECT 1
            FROM temp_CGUSC.fp.crm_concentracao_multiplo_controle C
            INNER JOIN #crm_mov_fonte_atual F ON F.id_cnpj = C.id_cnpj
            WHERE C.status <> 'OK'
        ) THEN 'INCOMPLETO'
        ELSE 'OK'
    END,
    dt_atualizacao = GETDATE(),
    observacao = 'Motor temporal CRM multiplo finalizado.'
WHERE id_pipeline = 1;

IF OBJECT_ID('temp_CGUSC.fp.crm_pipeline_uf_controle') IS NOT NULL
    EXEC sp_executesql
        N'UPDATE temp_CGUSC.fp.crm_pipeline_uf_controle
          SET status = ''PROCESSANDO'',
              etapa = CASE
                  WHEN EXISTS (
                      SELECT 1
                      FROM temp_CGUSC.fp.crm_concentracao_multiplo_controle C
                      INNER JOIN #crm_mov_fonte_atual F ON F.id_cnpj = C.id_cnpj
                      WHERE C.status <> ''OK''
                  ) THEN ''CONCENTRACAO_MULTIPLO_INCOMPLETA''
                  ELSE ''CONCENTRACAO_MULTIPLO_OK''
              END,
              status_concentracao_multiplo = CASE
                  WHEN EXISTS (
                      SELECT 1
                      FROM temp_CGUSC.fp.crm_concentracao_multiplo_controle C
                      INNER JOIN #crm_mov_fonte_atual F ON F.id_cnpj = C.id_cnpj
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

IF OBJECT_ID('temp_CGUSC.fp.crm_concentracao_multiplo_metadata') IS NOT NULL
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
    FROM temp_CGUSC.fp.crm_concentracao_multiplo_metadata;
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
      FROM temp_CGUSC.fp.crm_pipeline_uf_controle
      WHERE pipeline_versao = @versao
        AND dt_data_inicio = @inicio
        AND dt_data_fim = @fim
      ORDER BY uf_farmacia;',
    N'@versao VARCHAR(40), @inicio DATE, @fim DATE',
    @versao = @pipeline_versao,
    @inicio = @DataInicio,
    @fim = @DataFim;

-- Distribuição por severidade
IF OBJECT_ID('temp_CGUSC.fp.crm_concentracao_multiplo_alertas') IS NOT NULL
BEGIN
    SELECT
        severidade,
        'Multi-CRM'                AS tipo,
        COUNT(*)                   AS qtd_alertas,
        COUNT(DISTINCT id_cnpj)    AS qtd_cnpjs,
        AVG(nu_crms_distintos)     AS media_crms_distintos,
        AVG(nu_minutos_span)       AS media_minutos_span,
        MIN(dt_ini_concentracao)   AS primeiro_alerta,
        MAX(dt_ini_concentracao)   AS ultimo_alerta
    FROM temp_CGUSC.fp.crm_concentracao_multiplo_alertas
    GROUP BY severidade
    ORDER BY
        CASE severidade WHEN 'EXTREMO' THEN 1 WHEN 'CRÍTICO' THEN 2 WHEN 'GRAVE' THEN 3 ELSE 4 END,
        tipo;

    -- Top 30 piores casos
    SELECT TOP 30
        id_cnpj,
        dt_dia,
        dt_ini_concentracao,
        dt_fim_concentracao,
        nu_minutos_span,
        nu_crms_distintos,
        nu_10min,
        nu_15min,
        nu_20min,
        nu_25min,
        nu_30min,
        nu_60min,
        severidade
    FROM temp_CGUSC.fp.crm_concentracao_multiplo_alertas
    ORDER BY
        CASE severidade WHEN 'EXTREMO' THEN 1 WHEN 'CRÍTICO' THEN 2 WHEN 'GRAVE' THEN 3 ELSE 4 END ASC,
        nu_60min DESC;
END;
