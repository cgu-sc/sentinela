-- ============================================================================
-- MATERIALIZADOR DE FONTE CRM POR UF
-- ============================================================================
-- Prepara uma fatia estadual da movimentacao nacional para os scripts CRM.
--
-- Fluxo esperado por UF:
--   1. Rodar este script para materializar temp_CGUSC.fp.crm_mov_fonte_atual.
--   2. Rodar crms_detalhado_pre_global_test.sql.
--   3. Rodar crm_concentracao_unico_temporal_test.sql.
--   4. Rodar crm_concentracao_multiplo_temporal_test.sql.
--   5. Rodar crms_detalhado_loteado_test.sql.
--
-- Retomada:
--   - Se @uf_farmacia vier NULL, o script prioriza UFs em ERRO/PROCESSANDO
--     antes de pegar a proxima PENDENTE.
--   - Se uma UF ja estiver OK, ela e pulada.
--   - Use @reset_uf = 1 apenas quando quiser refazer a UF atual do zero.
-- ============================================================================

SET NOCOUNT ON;

DECLARE @uf_farmacia CHAR(2) = NULL; -- Ex.: 'MG'. NULL pega a proxima UF pendente.
DECLARE @reset_uf    BIT     = 0;
DECLARE @DataInicio  DATE    = '2015-07-01';
DECLARE @DataFim     DATE    = '2024-12-31';
DECLARE @pipeline_versao VARCHAR(40) = 'v2_2026_05_07';

DECLARE @t0 DATETIME = GETDATE();
DECLARE @t1 DATETIME;
DECLARE @nu_registros_fonte BIGINT;
DECLARE @nu_cnpjs_fonte INT;
DECLARE @mensagem_erro NVARCHAR(4000);

IF OBJECT_ID('temp_CGUSC.fp.dados_farmacia') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.dados_farmacia nao encontrada.', 16, 1);
    RETURN;
END;

IF COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'uf') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.dados_farmacia nao possui coluna uf.', 16, 1);
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
        uf_farmacia          CHAR(2)       NOT NULL,
        pipeline_versao      VARCHAR(40)   NOT NULL,
        dt_data_inicio       DATE          NOT NULL,
        dt_data_fim          DATE          NOT NULL,
        status               VARCHAR(20)   NOT NULL,
        etapa                VARCHAR(80)   NULL,
        dt_inicio            DATETIME      NULL,
        dt_fim               DATETIME      NULL,
        dt_atualizacao       DATETIME      NULL,
        nu_registros_fonte   BIGINT        NULL,
        nu_cnpjs_fonte       INT           NULL,
        mensagem_erro        NVARCHAR(4000) NULL,
        dt_erro              DATETIME      NULL,
        CONSTRAINT PK_CrmPipelineUfControle PRIMARY KEY CLUSTERED (uf_farmacia)
    );
END;

INSERT INTO temp_CGUSC.fp.crm_pipeline_uf_controle
    (uf_farmacia, pipeline_versao, dt_data_inicio, dt_data_fim, status, etapa, dt_atualizacao)
SELECT DISTINCT
    CAST(F.uf AS CHAR(2)),
    @pipeline_versao,
    @DataInicio,
    @DataFim,
    'PENDENTE',
    'AGUARDANDO_MATERIALIZACAO',
    GETDATE()
FROM temp_CGUSC.fp.dados_farmacia F
WHERE F.uf IS NOT NULL
  AND LEN(LTRIM(RTRIM(F.uf))) = 2
  AND NOT EXISTS (
      SELECT 1
      FROM temp_CGUSC.fp.crm_pipeline_uf_controle C
      WHERE C.uf_farmacia = CAST(F.uf AS CHAR(2))
  );

IF @uf_farmacia IS NULL
BEGIN
    SELECT TOP 1 @uf_farmacia = uf_farmacia
    FROM temp_CGUSC.fp.crm_pipeline_uf_controle
    WHERE pipeline_versao = @pipeline_versao
      AND dt_data_inicio = @DataInicio
      AND dt_data_fim = @DataFim
      AND status IN ('ERRO', 'MATERIALIZANDO', 'MATERIALIZADA', 'PROCESSANDO')
    ORDER BY
        CASE status
            WHEN 'ERRO' THEN 1
            WHEN 'MATERIALIZANDO' THEN 2
            WHEN 'MATERIALIZADA' THEN 3
            WHEN 'PROCESSANDO' THEN 4
            ELSE 9
        END,
        uf_farmacia;

    IF @uf_farmacia IS NULL
    BEGIN
        SELECT TOP 1 @uf_farmacia = uf_farmacia
        FROM temp_CGUSC.fp.crm_pipeline_uf_controle
        WHERE pipeline_versao = @pipeline_versao
          AND dt_data_inicio = @DataInicio
          AND dt_data_fim = @DataFim
          AND status = 'PENDENTE'
        ORDER BY uf_farmacia;
    END;
END;

IF @uf_farmacia IS NULL
BEGIN
    PRINT '>> Todas as UFs estao OK ou nao ha UF pendente para esta versao/periodo.';
    SELECT * FROM temp_CGUSC.fp.crm_pipeline_uf_controle ORDER BY uf_farmacia;
    RETURN;
END;

IF EXISTS (
    SELECT 1
    FROM temp_CGUSC.fp.crm_pipeline_uf_controle
    WHERE uf_farmacia = @uf_farmacia
      AND status = 'OK'
      AND @reset_uf = 0
)
BEGIN
    PRINT '>> UF ' + @uf_farmacia + ' ja esta OK. Nada a materializar.';
    SELECT * FROM temp_CGUSC.fp.crm_pipeline_uf_controle WHERE uf_farmacia = @uf_farmacia;
    RETURN;
END;

IF @reset_uf = 0
   AND OBJECT_ID('temp_CGUSC.fp.crm_mov_fonte_atual') IS NOT NULL
   AND OBJECT_ID('temp_CGUSC.fp.crm_mov_fonte_atual_metadata') IS NOT NULL
   AND EXISTS (
        SELECT 1
        FROM temp_CGUSC.fp.crm_mov_fonte_atual_metadata
        WHERE id_pipeline = 1
          AND pipeline_versao = @pipeline_versao
          AND uf_farmacia = @uf_farmacia
          AND dt_data_inicio = @DataInicio
          AND dt_data_fim = @DataFim
          AND status = 'OK'
   )
BEGIN
    SELECT
        @nu_registros_fonte = nu_registros_fonte,
        @nu_cnpjs_fonte = nu_cnpjs_fonte
    FROM temp_CGUSC.fp.crm_mov_fonte_atual_metadata
    WHERE id_pipeline = 1;

    UPDATE temp_CGUSC.fp.crm_pipeline_uf_controle
    SET status = CASE WHEN status IN ('PROCESSANDO', 'ERRO') THEN status ELSE 'MATERIALIZADA' END,
        etapa = 'FONTE_REUTILIZADA',
        dt_atualizacao = GETDATE(),
        nu_registros_fonte = @nu_registros_fonte,
        nu_cnpjs_fonte = @nu_cnpjs_fonte
    WHERE uf_farmacia = @uf_farmacia;

    PRINT '>> Fonte ja materializada para UF ' + @uf_farmacia + '. Reaproveitando crm_mov_fonte_atual.';
    SELECT * FROM temp_CGUSC.fp.crm_mov_fonte_atual_metadata;
    SELECT * FROM temp_CGUSC.fp.crm_pipeline_uf_controle ORDER BY uf_farmacia;
    RETURN;
END;

BEGIN TRY
    PRINT '>> [CRM FONTE UF] Materializando UF ' + @uf_farmacia + '...';
    PRINT '   Periodo: ' + CAST(@DataInicio AS VARCHAR(10)) + ' -> ' + CAST(@DataFim AS VARCHAR(10));

    UPDATE temp_CGUSC.fp.crm_pipeline_uf_controle
    SET status = 'MATERIALIZANDO',
        etapa = 'MATERIALIZANDO_FONTE',
        dt_inicio = ISNULL(dt_inicio, GETDATE()),
        dt_fim = NULL,
        dt_atualizacao = GETDATE(),
        mensagem_erro = NULL,
        dt_erro = NULL
    WHERE uf_farmacia = @uf_farmacia;

    SET @t1 = GETDATE();

    DROP TABLE IF EXISTS temp_CGUSC.fp.crm_mov_fonte_atual;
    DROP TABLE IF EXISTS temp_CGUSC.fp.crm_mov_fonte_atual_metadata;

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
    INTO temp_CGUSC.fp.crm_mov_fonte_atual
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
        ON temp_CGUSC.fp.crm_mov_fonte_atual(uf_farmacia, id_cnpj, data_hora);

    CREATE NONCLUSTERED INDEX IDX_CrmMovFonteAtual_CnpjData
        ON temp_CGUSC.fp.crm_mov_fonte_atual(cnpj, data_hora)
        INCLUDE (id_cnpj, crm, crm_uf, num_autorizacao, valor_pago, codigo_barra);

    CREATE NONCLUSTERED INDEX IDX_CrmMovFonteAtual_CrmData
        ON temp_CGUSC.fp.crm_mov_fonte_atual(id_cnpj, crm, crm_uf, data_hora)
        INCLUDE (cnpj, num_autorizacao, valor_pago, codigo_barra);

    SELECT @nu_registros_fonte = ISNULL(SUM(P.rows), 0)
    FROM temp_CGUSC.sys.partitions P
    WHERE P.object_id = OBJECT_ID('temp_CGUSC.fp.crm_mov_fonte_atual')
      AND P.index_id IN (0, 1);

    SELECT @nu_cnpjs_fonte = COUNT(DISTINCT id_cnpj)
    FROM temp_CGUSC.fp.crm_mov_fonte_atual;

    CREATE TABLE temp_CGUSC.fp.crm_mov_fonte_atual_metadata (
        id_pipeline          TINYINT      NOT NULL,
        pipeline_versao      VARCHAR(40)  NOT NULL,
        uf_farmacia          CHAR(2)      NOT NULL,
        dt_data_inicio       DATE         NOT NULL,
        dt_data_fim          DATE         NOT NULL,
        nu_registros_fonte   BIGINT       NOT NULL,
        nu_cnpjs_fonte       INT          NOT NULL,
        dt_criacao           DATETIME     NOT NULL,
        status               VARCHAR(20)  NOT NULL,
        observacao           VARCHAR(400) NULL,
        CONSTRAINT PK_CrmMovFonteAtualMetadata PRIMARY KEY CLUSTERED (id_pipeline),
        CONSTRAINT CK_CrmMovFonteAtualMetadata_Id CHECK (id_pipeline = 1)
    );

    INSERT INTO temp_CGUSC.fp.crm_mov_fonte_atual_metadata
        (id_pipeline, pipeline_versao, uf_farmacia, dt_data_inicio, dt_data_fim,
         nu_registros_fonte, nu_cnpjs_fonte, dt_criacao, status, observacao)
    VALUES
        (1, @pipeline_versao, @uf_farmacia, @DataInicio, @DataFim,
         @nu_registros_fonte, @nu_cnpjs_fonte, GETDATE(), 'OK',
         'Fonte materializada para a UF atual.');

    IF @reset_uf = 1
    BEGIN
        PRINT '>> Reset UF habilitado: limpando checkpoints e saidas da UF ' + @uf_farmacia + '...';

        IF OBJECT_ID('temp_CGUSC.fp.crm_concentracao_unico_alertas') IS NOT NULL
            DELETE A
            FROM temp_CGUSC.fp.crm_concentracao_unico_alertas A
            INNER JOIN temp_CGUSC.fp.crm_mov_fonte_atual F ON F.id_cnpj = A.id_cnpj;

        IF OBJECT_ID('temp_CGUSC.fp.crm_concentracao_unico_controle') IS NOT NULL
            DELETE C
            FROM temp_CGUSC.fp.crm_concentracao_unico_controle C
            INNER JOIN temp_CGUSC.fp.crm_mov_fonte_atual F ON F.id_cnpj = C.id_cnpj;

        IF OBJECT_ID('temp_CGUSC.fp.crm_concentracao_multiplo_alertas') IS NOT NULL
            DELETE A
            FROM temp_CGUSC.fp.crm_concentracao_multiplo_alertas A
            INNER JOIN temp_CGUSC.fp.crm_mov_fonte_atual F ON F.id_cnpj = A.id_cnpj;

        IF OBJECT_ID('temp_CGUSC.fp.crm_concentracao_multiplo_controle') IS NOT NULL
            DELETE C
            FROM temp_CGUSC.fp.crm_concentracao_multiplo_controle C
            INNER JOIN temp_CGUSC.fp.crm_mov_fonte_atual F ON F.id_cnpj = C.id_cnpj;

        IF OBJECT_ID('temp_CGUSC.fp.crm_detalhado_lote_controle') IS NOT NULL
            DELETE C
            FROM temp_CGUSC.fp.crm_detalhado_lote_controle C
            INNER JOIN temp_CGUSC.fp.crm_mov_fonte_atual F ON F.id_cnpj = C.id_cnpj;

        IF OBJECT_ID('temp_CGUSC.fp.crm_crms_em_surto') IS NOT NULL
            DELETE T
            FROM temp_CGUSC.fp.crm_crms_em_surto T
            INNER JOIN (SELECT DISTINCT cnpj FROM temp_CGUSC.fp.crm_mov_fonte_atual) F
                ON F.cnpj = T.nu_cnpj;

        IF OBJECT_ID('temp_CGUSC.fp.crm_perfil_diario') IS NOT NULL
            DELETE T
            FROM temp_CGUSC.fp.crm_perfil_diario T
            INNER JOIN temp_CGUSC.fp.crm_mov_fonte_atual F ON F.id_cnpj = T.id_cnpj;

        IF OBJECT_ID('temp_CGUSC.fp.crm_perfil_horario') IS NOT NULL
            DELETE T
            FROM temp_CGUSC.fp.crm_perfil_horario T
            INNER JOIN temp_CGUSC.fp.crm_mov_fonte_atual F ON F.id_cnpj = T.id_cnpj;

        IF OBJECT_ID('temp_CGUSC.fp.mediana_autorizacoes_horaria') IS NOT NULL
            DELETE T
            FROM temp_CGUSC.fp.mediana_autorizacoes_horaria T
            INNER JOIN temp_CGUSC.fp.crm_mov_fonte_atual F ON F.id_cnpj = T.id_cnpj;

        IF OBJECT_ID('temp_CGUSC.fp.volume_horario_anomalo_alertas') IS NOT NULL
            DELETE T
            FROM temp_CGUSC.fp.volume_horario_anomalo_alertas T
            INNER JOIN temp_CGUSC.fp.crm_mov_fonte_atual F ON F.id_cnpj = T.id_cnpj;

        IF OBJECT_ID('temp_CGUSC.fp.crm_raiox_tx') IS NOT NULL
            DELETE T
            FROM temp_CGUSC.fp.crm_raiox_tx T
            INNER JOIN temp_CGUSC.fp.crm_mov_fonte_atual F ON F.id_cnpj = T.id_cnpj;

        IF OBJECT_ID('temp_CGUSC.fp.dados_crm_detalhado') IS NOT NULL
            DELETE T
            FROM temp_CGUSC.fp.dados_crm_detalhado T
            INNER JOIN (SELECT DISTINCT cnpj FROM temp_CGUSC.fp.crm_mov_fonte_atual) F
                ON F.cnpj = T.nu_cnpj;
    END;

    UPDATE temp_CGUSC.fp.crm_pipeline_uf_controle
    SET status = 'MATERIALIZADA',
        etapa = 'FONTE_OK',
        dt_atualizacao = GETDATE(),
        nu_registros_fonte = @nu_registros_fonte,
        nu_cnpjs_fonte = @nu_cnpjs_fonte
    WHERE uf_farmacia = @uf_farmacia;

    PRINT '   Registros fonte: ' + CAST(@nu_registros_fonte AS VARCHAR(30));
    PRINT '   CNPJs fonte:     ' + CAST(@nu_cnpjs_fonte AS VARCHAR(20));
    PRINT '   Tempo:           ' + CONVERT(VARCHAR(20), GETDATE() - @t1, 114);
END TRY
BEGIN CATCH
    SET @mensagem_erro = CONCAT(
        'Erro ', ERROR_NUMBER(),
        ' | Severidade ', ERROR_SEVERITY(),
        ' | Estado ', ERROR_STATE(),
        ' | Linha ', ERROR_LINE(),
        ' | ', ERROR_MESSAGE()
    );

    UPDATE temp_CGUSC.fp.crm_pipeline_uf_controle
    SET status = 'ERRO',
        etapa = 'MATERIALIZACAO_ERRO',
        dt_fim = GETDATE(),
        dt_atualizacao = GETDATE(),
        mensagem_erro = @mensagem_erro,
        dt_erro = GETDATE()
    WHERE uf_farmacia = @uf_farmacia;

    PRINT '>> ERRO ao materializar UF ' + ISNULL(@uf_farmacia, 'NI');
    PRINT @mensagem_erro;
    THROW;
END CATCH;

PRINT '==========================================================';
PRINT '   TEMPO TOTAL: ' + CONVERT(VARCHAR(20), GETDATE() - @t0, 114);
PRINT '==========================================================';

SELECT * FROM temp_CGUSC.fp.crm_mov_fonte_atual_metadata;
SELECT * FROM temp_CGUSC.fp.crm_pipeline_uf_controle ORDER BY uf_farmacia;
