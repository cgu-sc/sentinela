-- ============================================================================
-- GERADOR DE DADOS PARA INDICADOR DE CRMs - PROCESSAMENTO LOTEADO
-- ============================================================================
-- Script 2 do pipeline:
--   - processa CNPJs em lotes com checkpoint;
--   - gera tabelas locais/incrementais do indicador;
--   - usa tabelas pre-globais ja persistidas pelo script:
--       src/indicadores/crms_detalhado_pre_global_test.sql
--
-- Pre-requisitos:
--   1. temp_CGUSC.fp.dados_medico
--   2. temp_CGUSC.fp.crm_prescricoes_todos_estabelecimentos
--   3. temp_CGUSC.fp.crm_concentracao_unico_alertas
--   4. temp_CGUSC.fp.crm_concentracao_multiplo_alertas
--
-- O pos-global deve rodar depois deste script completar todos os CNPJs:
--   - alertas_crm_geografico
--   - alertas_crm_registro
--   - alertas_crm
--   - crm_export
--   - benchmarks
-- ============================================================================

SET NOCOUNT ON;

-- ============================================================================
-- PASSO 0: Reset opcional e inicializacao de tabelas persistentes
-- ============================================================================
DECLARE @reset BIT = 0;
DECLARE @pipeline_nome    VARCHAR(80) = 'crms_detalhado_loteado';
DECLARE @pipeline_versao  VARCHAR(40) = 'v1_loteado_2026_05_07';
DECLARE @pre_global_nome   VARCHAR(80) = 'crms_detalhado_pre_global';
DECLARE @pre_global_versao VARCHAR(40) = 'v1_pre_global_2026_05_07';
DECLARE @DataInicio       DATE        = '2015-07-01';
DECLARE @DataFim          DATE        = '2024-12-31';
DECLARE @existia_tabela_loteada BIT   = CASE WHEN
        OBJECT_ID('temp_CGUSC.fp.crm_detalhado_lote_controle') IS NOT NULL
     OR OBJECT_ID('temp_CGUSC.fp.crm_crms_em_surto') IS NOT NULL
     OR OBJECT_ID('temp_CGUSC.fp.crm_perfil_diario') IS NOT NULL
     OR OBJECT_ID('temp_CGUSC.fp.crm_perfil_horario') IS NOT NULL
     OR OBJECT_ID('temp_CGUSC.fp.mediana_autorizacoes_horaria') IS NOT NULL
     OR OBJECT_ID('temp_CGUSC.fp.volume_horario_anomalo_alertas') IS NOT NULL
     OR OBJECT_ID('temp_CGUSC.fp.crm_raiox_tx') IS NOT NULL
     OR OBJECT_ID('temp_CGUSC.fp.dados_crm_detalhado') IS NOT NULL
    THEN 1 ELSE 0 END;

IF OBJECT_ID('temp_CGUSC.fp.crm_prescricoes_todos_estabelecimentos') IS NULL
BEGIN
    RAISERROR('Tabela pre-global temp_CGUSC.fp.crm_prescricoes_todos_estabelecimentos nao encontrada. Rode crms_detalhado_pre_global_test.sql primeiro.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('temp_CGUSC.fp.dados_medico') IS NULL
BEGIN
    RAISERROR('Tabela pre-global temp_CGUSC.fp.dados_medico nao encontrada. Rode crms_detalhado_pre_global_test.sql primeiro.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('temp_CGUSC.fp.crm_detalhado_pre_global_metadata') IS NULL
BEGIN
    RAISERROR('Metadata pre-global temp_CGUSC.fp.crm_detalhado_pre_global_metadata nao encontrada. Rode crms_detalhado_pre_global_test.sql atualizado antes do loteado.', 16, 1);
    RETURN;
END;

IF NOT EXISTS (
    SELECT 1
    FROM temp_CGUSC.fp.crm_detalhado_pre_global_metadata
    WHERE id_pipeline = 1
      AND pipeline_nome = @pre_global_nome
      AND pipeline_versao = @pre_global_versao
      AND dt_data_inicio = @DataInicio
      AND dt_data_fim = @DataFim
      AND status = 'OK'
)
BEGIN
    RAISERROR('Pre-global incompativel com o loteado: metadata ausente, status diferente de OK, periodo divergente ou versao inesperada. Rode crms_detalhado_pre_global_test.sql para o mesmo periodo.', 16, 1);
    RETURN;
END;

IF @reset = 1
BEGIN
    PRINT '>> Reset habilitado: removendo tabelas loteadas...';

    DROP TABLE IF EXISTS temp_CGUSC.fp.crm_detalhado_lote_metadata;
    DROP TABLE IF EXISTS temp_CGUSC.fp.crm_detalhado_lote_controle;
    DROP TABLE IF EXISTS temp_CGUSC.fp.crm_crms_em_surto;
    DROP TABLE IF EXISTS temp_CGUSC.fp.crm_perfil_diario;
    DROP TABLE IF EXISTS temp_CGUSC.fp.crm_perfil_horario;
    DROP TABLE IF EXISTS temp_CGUSC.fp.mediana_autorizacoes_horaria;
    DROP TABLE IF EXISTS temp_CGUSC.fp.volume_horario_anomalo_alertas;
    DROP TABLE IF EXISTS temp_CGUSC.fp.crm_raiox_tx;
    DROP TABLE IF EXISTS temp_CGUSC.fp.dados_crm_detalhado;
END;

IF OBJECT_ID('temp_CGUSC.fp.crm_detalhado_lote_metadata') IS NULL
BEGIN
    CREATE TABLE temp_CGUSC.fp.crm_detalhado_lote_metadata (
        id_pipeline       TINYINT      NOT NULL,
        pipeline_nome     VARCHAR(80)  NOT NULL,
        pipeline_versao   VARCHAR(40)  NOT NULL,
        dt_data_inicio    DATE         NOT NULL,
        dt_data_fim       DATE         NOT NULL,
        dt_criacao        DATETIME     NOT NULL,
        dt_atualizacao    DATETIME     NULL,
        status            VARCHAR(20)  NOT NULL,
        observacao        VARCHAR(400) NULL,
        CONSTRAINT PK_CrmDetalhadoLoteMetadata PRIMARY KEY CLUSTERED (id_pipeline),
        CONSTRAINT CK_CrmDetalhadoLoteMetadata_Id CHECK (id_pipeline = 1)
    );
END;

IF NOT EXISTS (SELECT 1 FROM temp_CGUSC.fp.crm_detalhado_lote_metadata WHERE id_pipeline = 1)
BEGIN
    IF @reset = 0 AND @existia_tabela_loteada = 1
    BEGIN
        RAISERROR('Estado loteado existente sem metadata. Para evitar mistura com dados antigos, rode uma primeira execucao limpa com @reset = 1.', 16, 1);
        RETURN;
    END;

    INSERT INTO temp_CGUSC.fp.crm_detalhado_lote_metadata
        (id_pipeline, pipeline_nome, pipeline_versao, dt_data_inicio, dt_data_fim,
         dt_criacao, dt_atualizacao, status, observacao)
    VALUES
        (1, @pipeline_nome, @pipeline_versao, @DataInicio, @DataFim,
         GETDATE(), GETDATE(), 'PROCESSANDO', 'Metadata criada pelo script loteado.');
END
ELSE IF NOT EXISTS (
    SELECT 1
    FROM temp_CGUSC.fp.crm_detalhado_lote_metadata
    WHERE id_pipeline = 1
      AND pipeline_nome = @pipeline_nome
      AND pipeline_versao = @pipeline_versao
      AND dt_data_inicio = @DataInicio
      AND dt_data_fim = @DataFim
)
BEGIN
    RAISERROR('Metadata existente incompativel com este script/periodo. Rode com @reset = 1 para iniciar uma base limpa.', 16, 1);
    RETURN;
END
ELSE
BEGIN
    UPDATE temp_CGUSC.fp.crm_detalhado_lote_metadata
    SET status = 'PROCESSANDO',
        dt_atualizacao = GETDATE(),
        observacao = 'Execucao retomada/validada pelo script loteado.'
    WHERE id_pipeline = 1;
END;

IF OBJECT_ID('temp_CGUSC.fp.crm_detalhado_lote_controle') IS NULL
BEGIN
    CREATE TABLE temp_CGUSC.fp.crm_detalhado_lote_controle (
        id_cnpj             INT          NOT NULL,
        cnpj                CHAR(14)     NOT NULL,
        dt_inicio           DATETIME     NOT NULL,
        dt_fim              DATETIME     NULL,
        status              VARCHAR(12)  NOT NULL,
        nu_dados_crm        INT          NULL,
        nu_volume_alertas   INT          NULL,
        nu_raiox_tx         INT          NULL,
        etapa               VARCHAR(80)  NULL,
        mensagem_erro       NVARCHAR(4000) NULL,
        dt_erro             DATETIME     NULL,
        CONSTRAINT PK_CrmDetalhadoLoteControle PRIMARY KEY CLUSTERED (id_cnpj)
    );
END;

IF COL_LENGTH('temp_CGUSC.fp.crm_detalhado_lote_controle', 'etapa') IS NULL
    ALTER TABLE temp_CGUSC.fp.crm_detalhado_lote_controle ADD etapa VARCHAR(80) NULL;

IF COL_LENGTH('temp_CGUSC.fp.crm_detalhado_lote_controle', 'mensagem_erro') IS NULL
    ALTER TABLE temp_CGUSC.fp.crm_detalhado_lote_controle ADD mensagem_erro NVARCHAR(4000) NULL;

IF COL_LENGTH('temp_CGUSC.fp.crm_detalhado_lote_controle', 'dt_erro') IS NULL
    ALTER TABLE temp_CGUSC.fp.crm_detalhado_lote_controle ADD dt_erro DATETIME NULL;

IF OBJECT_ID('temp_CGUSC.fp.crm_crms_em_surto') IS NULL
BEGIN
    CREATE TABLE temp_CGUSC.fp.crm_crms_em_surto (
        nu_cnpj     CHAR(14)     NOT NULL,
        id_medico   VARCHAR(20)  NOT NULL,
        competencia INT          NOT NULL
    );
END;

IF OBJECT_ID('temp_CGUSC.fp.crm_perfil_diario') IS NULL
BEGIN
    CREATE TABLE temp_CGUSC.fp.crm_perfil_diario (
        id_cnpj                              INT           NOT NULL,
        competencia                          INT           NOT NULL,
        dt_janela                            DATE          NOT NULL,
        nu_prescricoes_dia                   SMALLINT      NOT NULL,
        nu_crms_distintos                    SMALLINT      NOT NULL,
        mediana_diaria                       DECIMAL(7,2)  NULL,
        is_dia_com_volume_horario_anomalo    BIT           NOT NULL,
        is_anomalo_unico                     BIT           NOT NULL,
        is_crm_multiplo                      BIT           NOT NULL
    );
END;

IF OBJECT_ID('temp_CGUSC.fp.crm_perfil_horario') IS NULL
BEGIN
    CREATE TABLE temp_CGUSC.fp.crm_perfil_horario (
        id_cnpj                      INT           NOT NULL,
        dt_janela                    DATE          NOT NULL,
        hr_janela                    TINYINT       NOT NULL,
        nu_prescricoes               SMALLINT      NOT NULL,
        nu_crms_diferentes           SMALLINT      NOT NULL,
        mediana_hora                 DECIMAL(6,2)  NULL,
        is_hora_com_alerta           BIT           NOT NULL,
        is_volume_horario_anomalo    BIT           NOT NULL,
        is_crm_unico                 BIT           NOT NULL,
        is_crm_multiplo              BIT           NOT NULL
    );
END;

IF OBJECT_ID('temp_CGUSC.fp.mediana_autorizacoes_horaria') IS NULL
BEGIN
    CREATE TABLE temp_CGUSC.fp.mediana_autorizacoes_horaria (
        id_cnpj       INT           NOT NULL,
        ano           SMALLINT      NOT NULL,
        trimestre     TINYINT       NOT NULL,
        hr_janela     TINYINT       NOT NULL,
        mediana_hora  DECIMAL(6,2)  NULL
    );
END;

IF OBJECT_ID('temp_CGUSC.fp.volume_horario_anomalo_alertas') IS NULL
BEGIN
    CREATE TABLE temp_CGUSC.fp.volume_horario_anomalo_alertas (
        id_cnpj          INT           NOT NULL,
        competencia      INT           NOT NULL,
        dt_alerta        DATE          NOT NULL,
        hr_janela        TINYINT       NOT NULL,
        nu_prescricoes   SMALLINT      NOT NULL,
        nu_crms          SMALLINT      NOT NULL,
        mediana_hora     DECIMAL(6,2)  NULL,
        multiplicador    DECIMAL(10,1) NULL
    );
END;

IF OBJECT_ID('temp_CGUSC.fp.crm_raiox_tx') IS NULL
BEGIN
    CREATE TABLE temp_CGUSC.fp.crm_raiox_tx (
        id_cnpj          INT           NOT NULL,
        dt_janela        DATE          NOT NULL,
        hr_janela        TINYINT       NOT NULL,
        data_hora        SMALLDATETIME NOT NULL,
        num_autorizacao  VARCHAR(50)   NOT NULL,
        id_medico        VARCHAR(20)   NOT NULL,
        id_gtin          INT           NOT NULL,
        valor_pago       DECIMAL(9,2)  NULL
    );
END;

IF OBJECT_ID('temp_CGUSC.fp.dados_crm_detalhado') IS NULL
BEGIN
    CREATE TABLE temp_CGUSC.fp.dados_crm_detalhado (
        nu_cnpj                         CHAR(14)      NOT NULL,
        competencia                     INT           NOT NULL,
        id_medico                       VARCHAR(20)   NOT NULL,
        nu_prescricoes_medico           SMALLINT      NOT NULL,
        vl_autorizacoes_medico          DECIMAL(18,2) NOT NULL,
        nu_prescricoes_pico_h           SMALLINT      NOT NULL,
        taxa_pico_h                     DECIMAL(7,2)  NOT NULL,
        dt_prescricao_inicial_medico    DATE          NOT NULL,
        dt_prescricao_final_medico      DATE          NOT NULL
    );
END;

IF NOT EXISTS (SELECT 1 FROM temp_CGUSC.sys.indexes WHERE object_id = OBJECT_ID('temp_CGUSC.fp.crm_crms_em_surto') AND name = 'IDX_CrmSurto_Key')
    CREATE CLUSTERED INDEX IDX_CrmSurto_Key ON temp_CGUSC.fp.crm_crms_em_surto(nu_cnpj, id_medico, competencia);

IF NOT EXISTS (SELECT 1 FROM temp_CGUSC.sys.indexes WHERE object_id = OBJECT_ID('temp_CGUSC.fp.crm_perfil_diario') AND name = 'IDX_DailyProfile')
    CREATE CLUSTERED INDEX IDX_DailyProfile ON temp_CGUSC.fp.crm_perfil_diario(id_cnpj, dt_janela);

IF NOT EXISTS (SELECT 1 FROM temp_CGUSC.sys.indexes WHERE object_id = OBJECT_ID('temp_CGUSC.fp.crm_perfil_horario') AND name = 'IDX_PerfilHorario')
    CREATE CLUSTERED INDEX IDX_PerfilHorario ON temp_CGUSC.fp.crm_perfil_horario(id_cnpj, dt_janela, hr_janela);

IF NOT EXISTS (SELECT 1 FROM temp_CGUSC.sys.indexes WHERE object_id = OBJECT_ID('temp_CGUSC.fp.mediana_autorizacoes_horaria') AND name = 'IDX_MedianaHoraria')
    CREATE CLUSTERED INDEX IDX_MedianaHoraria ON temp_CGUSC.fp.mediana_autorizacoes_horaria(id_cnpj, ano, trimestre, hr_janela);

IF NOT EXISTS (SELECT 1 FROM temp_CGUSC.sys.indexes WHERE object_id = OBJECT_ID('temp_CGUSC.fp.volume_horario_anomalo_alertas') AND name = 'IDX_AlertaSequencialCNPJ')
    CREATE CLUSTERED INDEX IDX_AlertaSequencialCNPJ ON temp_CGUSC.fp.volume_horario_anomalo_alertas(id_cnpj, dt_alerta, hr_janela);

-- As duas maiores tabelas ficam como heap durante a carga loteada.
-- Os clustered indexes sao criados apenas ao final para evitar custo de
-- manutencao do indice em cada INSERT incremental.


-- ============================================================================
-- PASSO 1: Processamento por lotes de CNPJ
-- ============================================================================
DECLARE @lote_size  INT      = 20;
DECLARE @t0         DATETIME = GETDATE();
DECLARE @t1         DATETIME;
DECLARE @t_bloco    DATETIME;

DECLARE @lote_num          INT = 0;
DECLARE @nu_processados    INT = 0;
DECLARE @nu_pendentes      INT;
DECLARE @nu_ja_processados INT;
DECLARE @nu_total          INT;
DECLARE @nu_lote           INT;
DECLARE @etapa             VARCHAR(80);

PRINT '>> [CRM DETALHADO LOTEADO] Iniciando processamento...';
PRINT '   Periodo: ' + CAST(@DataInicio AS VARCHAR(10)) + ' -> ' + CAST(@DataFim AS VARCHAR(10));
PRINT '   Lote: ' + CAST(@lote_size AS VARCHAR(10)) + ' CNPJs por iteracao';


-- Limpa lote interrompido para reprocessar do zero.
PRINT '>> Passo 1.0: Limpando CNPJs interrompidos...';
SET @t1 = GETDATE();

DELETE T
FROM temp_CGUSC.fp.crm_crms_em_surto T
INNER JOIN temp_CGUSC.fp.crm_detalhado_lote_controle C ON C.cnpj = T.nu_cnpj
WHERE C.status = 'PROCESSANDO';

DELETE T
FROM temp_CGUSC.fp.crm_perfil_diario T
INNER JOIN temp_CGUSC.fp.crm_detalhado_lote_controle C ON C.id_cnpj = T.id_cnpj
WHERE C.status = 'PROCESSANDO';

DELETE T
FROM temp_CGUSC.fp.crm_perfil_horario T
INNER JOIN temp_CGUSC.fp.crm_detalhado_lote_controle C ON C.id_cnpj = T.id_cnpj
WHERE C.status = 'PROCESSANDO';

DELETE T
FROM temp_CGUSC.fp.mediana_autorizacoes_horaria T
INNER JOIN temp_CGUSC.fp.crm_detalhado_lote_controle C ON C.id_cnpj = T.id_cnpj
WHERE C.status = 'PROCESSANDO';

DELETE T
FROM temp_CGUSC.fp.volume_horario_anomalo_alertas T
INNER JOIN temp_CGUSC.fp.crm_detalhado_lote_controle C ON C.id_cnpj = T.id_cnpj
WHERE C.status = 'PROCESSANDO';

DELETE T
FROM temp_CGUSC.fp.crm_raiox_tx T
INNER JOIN temp_CGUSC.fp.crm_detalhado_lote_controle C ON C.id_cnpj = T.id_cnpj
WHERE C.status = 'PROCESSANDO';

DELETE T
FROM temp_CGUSC.fp.dados_crm_detalhado T
INNER JOIN temp_CGUSC.fp.crm_detalhado_lote_controle C ON C.cnpj = T.nu_cnpj
WHERE C.status = 'PROCESSANDO';

DELETE FROM temp_CGUSC.fp.crm_detalhado_lote_controle
WHERE status = 'PROCESSANDO';

PRINT '   Limpeza concluida em: ' + CONVERT(VARCHAR(20), GETDATE() - @t1, 114);


-- Fila de CNPJs pendentes.
PRINT '>> Passo 1.1: Construindo fila de CNPJs pendentes...';
SET @t1 = GETDATE();

DROP TABLE IF EXISTS #cnpjs_pendentes;

SELECT DISTINCT
    F.id AS id_cnpj,
    CAST(F.cnpj AS CHAR(14)) AS cnpj
INTO #cnpjs_pendentes
FROM temp_CGUSC.fp.teste_mov_SC M
INNER JOIN temp_CGUSC.fp.medicamentos_patologia PAT ON PAT.codigo_barra = M.codigo_barra
INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = M.cnpj
WHERE M.crm_uf IS NOT NULL
  AND M.crm IS NOT NULL
  AND M.crm_uf <> 'BR'
  AND M.data_hora >= @DataInicio
  AND M.data_hora < DATEADD(DAY, 1, @DataFim)
  AND F.id NOT IN (
      SELECT id_cnpj
      FROM temp_CGUSC.fp.crm_detalhado_lote_controle
      WHERE status = 'OK'
  );

SET @nu_pendentes      = (SELECT COUNT(*) FROM #cnpjs_pendentes);
SET @nu_ja_processados = (SELECT COUNT(*) FROM temp_CGUSC.fp.crm_detalhado_lote_controle WHERE status = 'OK');
SET @nu_total          = @nu_pendentes + @nu_ja_processados;

PRINT '   CNPJs ja processados: ' + CAST(@nu_ja_processados AS VARCHAR(20)) + ' / ' + CAST(@nu_total AS VARCHAR(20));
PRINT '   CNPJs pendentes:      ' + CAST(@nu_pendentes AS VARCHAR(20));
PRINT '   Fila concluida em:    ' + CONVERT(VARCHAR(20), GETDATE() - @t1, 114);

IF @nu_pendentes = 0
BEGIN
    PRINT '   Nada a processar. Base loteada ja esta completa.';
    GOTO Finalizar;
END;

PRINT '>> Preparando tabelas grandes para carga em heap...';
SET @t1 = GETDATE();

IF EXISTS (SELECT 1 FROM temp_CGUSC.sys.indexes WHERE object_id = OBJECT_ID('temp_CGUSC.fp.crm_raiox_tx') AND name = 'IDX_RaioX_Cnpj_Data')
    DROP INDEX IDX_RaioX_Cnpj_Data ON temp_CGUSC.fp.crm_raiox_tx;

IF EXISTS (SELECT 1 FROM temp_CGUSC.sys.indexes WHERE object_id = OBJECT_ID('temp_CGUSC.fp.dados_crm_detalhado') AND name = 'IDX_DadosDet')
    DROP INDEX IDX_DadosDet ON temp_CGUSC.fp.dados_crm_detalhado;

PRINT '   Preparacao concluida em: ' + CONVERT(VARCHAR(20), GETDATE() - @t1, 114);


WHILE EXISTS (SELECT 1 FROM #cnpjs_pendentes)
BEGIN
    SET @lote_num += 1;
    SET @t1 = GETDATE();

    DROP TABLE IF EXISTS #lote_atual;

    SELECT TOP (@lote_size)
        id_cnpj,
        cnpj
    INTO #lote_atual
    FROM #cnpjs_pendentes
    ORDER BY id_cnpj;

    SET @nu_lote = (SELECT COUNT(*) FROM #lote_atual);

    INSERT INTO temp_CGUSC.fp.crm_detalhado_lote_controle (id_cnpj, cnpj, dt_inicio, status)
    SELECT L.id_cnpj, L.cnpj, GETDATE(), 'PROCESSANDO'
    FROM #lote_atual L
    WHERE NOT EXISTS (
        SELECT 1
        FROM temp_CGUSC.fp.crm_detalhado_lote_controle C
        WHERE C.id_cnpj = L.id_cnpj
    );

    SET @etapa = 'INICIO_LOTE';

    UPDATE C
    SET status = 'PROCESSANDO',
        dt_inicio = GETDATE(),
        dt_fim = NULL,
        etapa = @etapa,
        mensagem_erro = NULL,
        dt_erro = NULL
    FROM temp_CGUSC.fp.crm_detalhado_lote_controle C
    INNER JOIN #lote_atual L ON L.id_cnpj = C.id_cnpj;

    BEGIN TRY
    SET @etapa = 'IDEMPOTENCIA_LOTE';

    UPDATE C
    SET etapa = @etapa
    FROM temp_CGUSC.fp.crm_detalhado_lote_controle C
    INNER JOIN #lote_atual L ON L.id_cnpj = C.id_cnpj;

    -- Garante idempotencia do lote atual.
    DELETE T FROM temp_CGUSC.fp.crm_crms_em_surto T INNER JOIN #lote_atual L ON L.cnpj = T.nu_cnpj;
    DELETE T FROM temp_CGUSC.fp.crm_perfil_diario T INNER JOIN #lote_atual L ON L.id_cnpj = T.id_cnpj;
    DELETE T FROM temp_CGUSC.fp.crm_perfil_horario T INNER JOIN #lote_atual L ON L.id_cnpj = T.id_cnpj;
    DELETE T FROM temp_CGUSC.fp.mediana_autorizacoes_horaria T INNER JOIN #lote_atual L ON L.id_cnpj = T.id_cnpj;
    DELETE T FROM temp_CGUSC.fp.volume_horario_anomalo_alertas T INNER JOIN #lote_atual L ON L.id_cnpj = T.id_cnpj;
    DELETE T FROM temp_CGUSC.fp.crm_raiox_tx T INNER JOIN #lote_atual L ON L.id_cnpj = T.id_cnpj;
    DELETE T FROM temp_CGUSC.fp.dados_crm_detalhado T INNER JOIN #lote_atual L ON L.cnpj = T.nu_cnpj;

    PRINT '>> Lote ' + RIGHT('0000' + CAST(@lote_num AS VARCHAR(10)), 4) +
          ' | CNPJs no lote: ' + CAST(@nu_lote AS VARCHAR(10));


    -- ========================================================================
    -- 2.A: Base horaria mestra do lote
    -- ========================================================================
    SET @etapa = '2.A_BASE_HORARIA_MESTRA';
    UPDATE C SET etapa = @etapa FROM temp_CGUSC.fp.crm_detalhado_lote_controle C INNER JOIN #lote_atual L ON L.id_cnpj = C.id_cnpj;

    SET @t_bloco = GETDATE();
    DROP TABLE IF EXISTS #base_horaria_mestra;

    SELECT
        L.cnpj AS nu_cnpj,
        CAST(CAST(M.crm AS VARCHAR(10)) + '/' + M.crm_uf AS VARCHAR(20)) AS id_medico,
        YEAR(M.data_hora) * 100 + MONTH(M.data_hora) AS competencia,
        CAST(M.data_hora AS DATE) AS dt_dia,
        CAST(DATEPART(HOUR, M.data_hora) AS TINYINT) AS hr_janela,
        CAST(COUNT(DISTINCT M.num_autorizacao) AS SMALLINT) AS nu_prescricoes_hora,
        CAST(SUM(M.valor_pago) AS DECIMAL(18,2)) AS vl_autorizacoes_hora,
        CAST(MIN(M.data_hora) AS SMALLDATETIME) AS dt_ini_hora,
        CAST(MAX(M.data_hora) AS SMALLDATETIME) AS dt_fim_hora,
        CAST(DATEDIFF(MINUTE, MIN(M.data_hora), MAX(M.data_hora)) AS TINYINT) AS nu_minutos_hora
    INTO #base_horaria_mestra
    FROM temp_CGUSC.fp.teste_mov_SC M
    INNER JOIN temp_CGUSC.fp.medicamentos_patologia PAT ON PAT.codigo_barra = M.codigo_barra
    INNER JOIN #lote_atual L ON L.cnpj = M.cnpj
    WHERE M.crm_uf IS NOT NULL
      AND M.crm IS NOT NULL
      AND M.crm_uf <> 'BR'
      AND M.data_hora >= @DataInicio
      AND M.data_hora < DATEADD(DAY, 1, @DataFim)
    GROUP BY
        L.cnpj,
        M.crm,
        M.crm_uf,
        YEAR(M.data_hora),
        MONTH(M.data_hora),
        CAST(M.data_hora AS DATE),
        DATEPART(HOUR, M.data_hora);

    CREATE CLUSTERED INDEX IDX_Mestra ON #base_horaria_mestra(nu_cnpj, id_medico, competencia);

    PRINT '      2.A base_horaria_mestra: ' + CONVERT(VARCHAR(20), GETDATE() - @t_bloco, 114);


    -- ========================================================================
    -- 2.B: Derivacoes mensais/horarias/estabelecimento
    -- ========================================================================
    SET @etapa = '2.B_DERIVACOES_BASE';
    UPDATE C SET etapa = @etapa FROM temp_CGUSC.fp.crm_detalhado_lote_controle C INNER JOIN #lote_atual L ON L.id_cnpj = C.id_cnpj;

    SET @t_bloco = GETDATE();

    DROP TABLE IF EXISTS #base_agregada_crm_cnpj;
    SELECT
        CONCAT(nu_cnpj, '|', id_medico, '|', CAST(competencia AS VARCHAR(6))) AS chave,
        id_medico,
        nu_cnpj,
        competencia,
        CAST(SUM(nu_prescricoes_hora) AS SMALLINT) AS nu_prescricoes_medico,
        CAST(SUM(vl_autorizacoes_hora) AS DECIMAL(18,2)) AS vl_autorizacoes_medico,
        CAST(MIN(dt_ini_hora) AS DATE) AS dt_prescricao_inicial_medico,
        CAST(MAX(dt_fim_hora) AS DATE) AS dt_prescricao_final_medico
    INTO #base_agregada_crm_cnpj
    FROM #base_horaria_mestra
    GROUP BY nu_cnpj, id_medico, competencia;

    CREATE CLUSTERED INDEX IDX_BaseAgreg_Key ON #base_agregada_crm_cnpj(nu_cnpj, id_medico, competencia);

    DROP TABLE IF EXISTS #base_horaria_crm;
    SELECT * INTO #base_horaria_crm FROM #base_horaria_mestra;
    CREATE CLUSTERED INDEX IDX_BaseHora_Mestra ON #base_horaria_crm(nu_cnpj, id_medico, dt_dia, hr_janela);

    DROP TABLE IF EXISTS #tb_info_estabelecimento;
    SELECT
        nu_cnpj AS cnpj,
        competencia,
        CAST(SUM(nu_prescricoes_hora) AS INT) AS nu_autorizacoes_estabelecimento,
        CAST(SUM(vl_autorizacoes_hora) AS DECIMAL(18,2)) AS vl_autorizacoes_estabelecimento,
        MIN(dt_ini_hora) AS dt_venda_inicial_estabelecimento,
        MAX(dt_fim_hora) AS dt_venda_final_estabelecimento
    INTO #tb_info_estabelecimento
    FROM #base_horaria_mestra
    GROUP BY nu_cnpj, competencia;

    CREATE CLUSTERED INDEX IDX_InfoEst ON #tb_info_estabelecimento(cnpj, competencia);

    DROP TABLE IF EXISTS #whitelist_crms_relevantes;
    SELECT nu_cnpj, id_medico
    INTO #whitelist_crms_relevantes
    FROM #base_agregada_crm_cnpj
    GROUP BY nu_cnpj, id_medico
    HAVING SUM(nu_prescricoes_medico) >= 5;

    CREATE CLUSTERED INDEX IDX_Whitelist ON #whitelist_crms_relevantes(nu_cnpj, id_medico);

    PRINT '      2.B derivacoes base:       ' + CONVERT(VARCHAR(20), GETDATE() - @t_bloco, 114);


    -- ========================================================================
    -- 2.C: Anomalias horarias e medianas
    -- ========================================================================
    SET @etapa = '2.C_ANOMALIAS_HORARIAS';
    UPDATE C SET etapa = @etapa FROM temp_CGUSC.fp.crm_detalhado_lote_controle C INNER JOIN #lote_atual L ON L.id_cnpj = C.id_cnpj;

    SET @t_bloco = GETDATE();

    DROP TABLE IF EXISTS #base_horaria;
    SELECT
        nu_cnpj AS cnpj,
        competencia,
        dt_dia AS dt_janela,
        hr_janela,
        CAST(SUM(nu_prescricoes_hora) AS SMALLINT) AS nu_prescricoes_hora,
        CAST(COUNT(DISTINCT id_medico) AS SMALLINT) AS nu_crms_distintos_hora
    INTO #base_horaria
    FROM #base_horaria_mestra
    GROUP BY nu_cnpj, competencia, dt_dia, hr_janela;

    CREATE CLUSTERED INDEX IDX_BH_Surto ON #base_horaria(cnpj, dt_janela, hr_janela);

    DROP TABLE IF EXISTS #mediana_hora;
    SELECT DISTINCT
        cnpj,
        competencia,
        hr_janela,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY nu_prescricoes_hora)
            OVER (PARTITION BY cnpj, (competencia / 100), ((competencia % 100 - 1) / 3), hr_janela) AS mediana_hora
    INTO #mediana_hora
    FROM #base_horaria;

    DROP TABLE IF EXISTS #mad_hora;
    SELECT DISTINCT
        H.cnpj,
        H.competencia,
        H.hr_janela,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ABS(H.nu_prescricoes_hora - M.mediana_hora))
            OVER (PARTITION BY H.cnpj, (H.competencia / 100), ((H.competencia % 100 - 1) / 3), H.hr_janela) AS mad_hora
    INTO #mad_hora
    FROM #base_horaria H
    INNER JOIN #mediana_hora M
        ON  M.cnpj = H.cnpj
        AND M.competencia = H.competencia
        AND M.hr_janela = H.hr_janela;

    DROP TABLE IF EXISTS #anomalias_horarias;
    SELECT
        H.*,
        CAST(M.mediana_hora AS DECIMAL(6,2)) AS mediana_hora,
        CAST(MAD.mad_hora AS DECIMAL(10,4)) AS mad_hora,
        CASE
            WHEN H.nu_prescricoes_hora >= 10
             AND MAD.mad_hora > 0
             AND (0.6745 * (H.nu_prescricoes_hora - M.mediana_hora) / MAD.mad_hora) > 4.5
            THEN 1
            WHEN H.nu_prescricoes_hora >= 10
             AND MAD.mad_hora = 0
             AND H.nu_prescricoes_hora > M.mediana_hora
            THEN 1
            ELSE 0
        END AS is_anomalo_hora
    INTO #anomalias_horarias
    FROM #base_horaria H
    INNER JOIN #mediana_hora M
        ON  M.cnpj = H.cnpj
        AND M.competencia = H.competencia
        AND M.hr_janela = H.hr_janela
    INNER JOIN #mad_hora MAD
        ON  MAD.cnpj = H.cnpj
        AND MAD.competencia = H.competencia
        AND MAD.hr_janela = H.hr_janela;

    CREATE CLUSTERED INDEX IDX_AnomaliaH ON #anomalias_horarias(cnpj, dt_janela, hr_janela);

    PRINT '      2.C anomalias horarias:    ' + CONVERT(VARCHAR(20), GETDATE() - @t_bloco, 114);


    -- ========================================================================
    -- 2.D: Pior hora por CRM/mes, surtos e totais diarios
    -- ========================================================================
    SET @etapa = '2.D_SURTOS_PIORES_HORAS';
    UPDATE C SET etapa = @etapa FROM temp_CGUSC.fp.crm_detalhado_lote_controle C INNER JOIN #lote_atual L ON L.id_cnpj = C.id_cnpj;

    SET @t_bloco = GETDATE();

    DROP TABLE IF EXISTS #pior_dia_crm;
    ;WITH calc_taxa AS (
        SELECT
            nu_cnpj,
            id_medico,
            competencia,
            dt_dia,
            hr_janela,
            nu_prescricoes_hora,
            dt_ini_hora,
            dt_fim_hora,
            nu_minutos_hora,
            CASE
                WHEN nu_minutos_hora = 0 THEN CAST(nu_prescricoes_hora AS FLOAT) * 60.0
                ELSE CAST(nu_prescricoes_hora AS DECIMAL(10,2)) / (CAST(NULLIF(nu_minutos_hora, 0) AS DECIMAL(10,2)) / 60.0)
            END AS taxa_hora
        FROM #base_horaria_crm
        WHERE nu_prescricoes_hora >= 5
    ),
    ranked AS (
        SELECT
            *,
            ROW_NUMBER() OVER (
                PARTITION BY nu_cnpj, id_medico, competencia
                ORDER BY
                    CASE
                        WHEN nu_prescricoes_hora >= 5  AND nu_minutos_hora <= 5 THEN 1
                        WHEN nu_prescricoes_hora >= 5  AND taxa_hora >= 12 THEN 2
                        WHEN nu_prescricoes_hora >= 10 AND (taxa_hora >= 7 OR nu_minutos_hora <= 60) THEN 3
                        ELSE 99
                    END ASC,
                    taxa_hora DESC,
                    nu_prescricoes_hora DESC
            ) AS rn
        FROM calc_taxa
    )
    SELECT
        nu_cnpj,
        id_medico,
        competencia,
        dt_dia,
        CAST(nu_prescricoes_hora AS SMALLINT) AS nu_prescricoes_pico_h,
        dt_ini_hora AS dt_ini_dia,
        dt_fim_hora AS dt_fim_dia,
        nu_minutos_hora AS nu_minutos_dia,
        CAST(taxa_hora AS DECIMAL(7,2)) AS taxa_dia
    INTO #pior_dia_crm
    FROM ranked
    WHERE rn = 1;

    CREATE CLUSTERED INDEX IDX_PiorDia ON #pior_dia_crm(nu_cnpj, id_medico, competencia);

    DROP TABLE IF EXISTS #crms_em_surto_raw;
    SELECT DISTINCT
        M.nu_cnpj,
        M.id_medico,
        M.competencia
    INTO #crms_em_surto_raw
    FROM #base_horaria_mestra M
    INNER JOIN #anomalias_horarias A
        ON  A.cnpj = M.nu_cnpj
        AND A.dt_janela = M.dt_dia
        AND A.hr_janela = M.hr_janela
    WHERE A.is_anomalo_hora = 1;

    INSERT INTO temp_CGUSC.fp.crm_crms_em_surto (nu_cnpj, id_medico, competencia)
    SELECT nu_cnpj, id_medico, competencia
    FROM #crms_em_surto_raw;

    DROP TABLE IF EXISTS #totais_diarios;
    SELECT
        cnpj,
        competencia,
        dt_janela,
        CAST(SUM(nu_prescricoes_hora) AS SMALLINT) AS nu_prescricoes_dia,
        CAST(MAX(is_anomalo_hora) AS BIT) AS dia_tem_anomalia_hora
    INTO #totais_diarios
    FROM #anomalias_horarias
    GROUP BY cnpj, competencia, dt_janela;

    DROP TABLE IF EXISTS #mediana_diaria;
    SELECT DISTINCT
        cnpj,
        competencia,
        CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY nu_prescricoes_dia)
            OVER (PARTITION BY cnpj, (competencia / 100), ((competencia % 100 - 1) / 3)) AS DECIMAL(7,2)) AS mediana_diaria
    INTO #mediana_diaria
    FROM #totais_diarios;

    CREATE CLUSTERED INDEX IDX_MedianaDia ON #mediana_diaria(cnpj, competencia);

    PRINT '      2.D surtos e piores horas: ' + CONVERT(VARCHAR(20), GETDATE() - @t_bloco, 114);


    -- ========================================================================
    -- 2.E: Tabelas de perfil e alertas locais
    -- ========================================================================
    SET @etapa = '2.E_PERFIS_ALERTAS';
    UPDATE C SET etapa = @etapa FROM temp_CGUSC.fp.crm_detalhado_lote_controle C INNER JOIN #lote_atual L ON L.id_cnpj = C.id_cnpj;

    SET @t_bloco = GETDATE();

    ;WITH crms_distintos_dia AS (
        SELECT
            nu_cnpj AS cnpj,
            dt_dia AS dt_janela,
            CAST(COUNT(DISTINCT id_medico) AS SMALLINT) AS nu_crms_distintos
        FROM #base_horaria_mestra
        GROUP BY nu_cnpj, dt_dia
    ),
    anomalias_unico_dia AS (
        SELECT DISTINCT U.id_cnpj, U.dt_dia AS dt_alerta
        FROM temp_CGUSC.fp.crm_concentracao_unico_alertas U
        INNER JOIN #lote_atual L ON L.id_cnpj = U.id_cnpj
    ),
    anomalias_multiplo_dia AS (
        SELECT DISTINCT MU.id_cnpj, MU.dt_dia AS dt_alerta
        FROM temp_CGUSC.fp.crm_concentracao_multiplo_alertas MU
        INNER JOIN #lote_atual L ON L.id_cnpj = MU.id_cnpj
    )
    INSERT INTO temp_CGUSC.fp.crm_perfil_diario
        (id_cnpj, competencia, dt_janela, nu_prescricoes_dia, nu_crms_distintos, mediana_diaria,
         is_dia_com_volume_horario_anomalo, is_anomalo_unico, is_crm_multiplo)
    SELECT
        F.id,
        T.competencia,
        T.dt_janela,
        T.nu_prescricoes_dia,
        ISNULL(C.nu_crms_distintos, CAST(0 AS SMALLINT)),
        M.mediana_diaria,
        CAST(T.dia_tem_anomalia_hora AS BIT),
        CAST(CASE WHEN U.dt_alerta IS NOT NULL THEN 1 ELSE 0 END AS BIT),
        CAST(CASE WHEN MU.dt_alerta IS NOT NULL THEN 1 ELSE 0 END AS BIT)
    FROM #totais_diarios T
    INNER JOIN #lote_atual L ON L.cnpj = T.cnpj
    INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.id = L.id_cnpj
    INNER JOIN #mediana_diaria M ON M.cnpj = T.cnpj AND M.competencia = T.competencia
    LEFT JOIN crms_distintos_dia C ON C.cnpj = T.cnpj AND C.dt_janela = T.dt_janela
    LEFT JOIN anomalias_unico_dia U ON U.id_cnpj = F.id AND U.dt_alerta = T.dt_janela
    LEFT JOIN anomalias_multiplo_dia MU ON MU.id_cnpj = F.id AND MU.dt_alerta = T.dt_janela;

    INSERT INTO temp_CGUSC.fp.crm_perfil_horario
        (id_cnpj, dt_janela, hr_janela, nu_prescricoes, nu_crms_diferentes, mediana_hora,
         is_hora_com_alerta, is_volume_horario_anomalo, is_crm_unico, is_crm_multiplo)
    SELECT
        F.id,
        H.dt_janela,
        H.hr_janela,
        H.nu_prescricoes_hora,
        H.nu_crms_distintos_hora,
        H.mediana_hora,
        CAST(CASE
            WHEN H.is_anomalo_hora = 1 THEN 1
            WHEN U.has_unico IS NOT NULL THEN 1
            WHEN MU.has_multiplo IS NOT NULL THEN 1
            ELSE 0
        END AS BIT) AS is_hora_com_alerta,
        CAST(CASE WHEN H.is_anomalo_hora = 1 THEN 1 ELSE 0 END AS BIT),
        CAST(CASE WHEN U.has_unico IS NOT NULL THEN 1 ELSE 0 END AS BIT),
        CAST(CASE WHEN MU.has_multiplo IS NOT NULL THEN 1 ELSE 0 END AS BIT)
    FROM #anomalias_horarias H
    INNER JOIN #lote_atual L ON L.cnpj = H.cnpj
    INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.id = L.id_cnpj
    INNER JOIN temp_CGUSC.fp.crm_perfil_diario D
        ON  D.id_cnpj = F.id
        AND D.dt_janela = H.dt_janela
    OUTER APPLY (
        SELECT TOP 1 1 AS has_unico
        FROM temp_CGUSC.fp.crm_concentracao_unico_alertas U
        WHERE U.id_cnpj = F.id
          AND U.dt_dia = H.dt_janela
          AND H.hr_janela BETWEEN DATEPART(HOUR, U.dt_ini_concentracao) AND DATEPART(HOUR, U.dt_fim_concentracao)
    ) U
    OUTER APPLY (
        SELECT TOP 1 1 AS has_multiplo
        FROM temp_CGUSC.fp.crm_concentracao_multiplo_alertas MU
        WHERE MU.id_cnpj = F.id
          AND MU.dt_dia = H.dt_janela
          AND H.hr_janela BETWEEN DATEPART(HOUR, MU.dt_ini_concentracao) AND DATEPART(HOUR, MU.dt_fim_concentracao)
    ) MU
    WHERE D.is_dia_com_volume_horario_anomalo = 1
       OR D.is_anomalo_unico = 1
       OR D.is_crm_multiplo = 1;

    INSERT INTO temp_CGUSC.fp.mediana_autorizacoes_horaria
        (id_cnpj, ano, trimestre, hr_janela, mediana_hora)
    SELECT DISTINCT
        F.id,
        CAST(M.competencia / 100 AS SMALLINT),
        CAST((M.competencia % 100 - 1) / 3 AS TINYINT),
        M.hr_janela,
        CAST(M.mediana_hora AS DECIMAL(6,2))
    FROM #mediana_hora M
    INNER JOIN #lote_atual L ON L.cnpj = M.cnpj
    INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.id = L.id_cnpj;

    INSERT INTO temp_CGUSC.fp.volume_horario_anomalo_alertas
        (id_cnpj, competencia, dt_alerta, hr_janela, nu_prescricoes, nu_crms, mediana_hora, multiplicador)
    SELECT
        F.id,
        H.competencia,
        H.dt_janela,
        H.hr_janela,
        H.nu_prescricoes_hora,
        H.nu_crms_distintos_hora,
        H.mediana_hora,
        CAST(CAST(H.nu_prescricoes_hora AS DECIMAL(10,2)) / NULLIF(H.mediana_hora, 0) AS DECIMAL(10,1))
    FROM #anomalias_horarias H
    INNER JOIN #lote_atual L ON L.cnpj = H.cnpj
    INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.id = L.id_cnpj
    WHERE H.is_anomalo_hora = 1;

    PRINT '      2.E perfis e alertas:      ' + CONVERT(VARCHAR(20), GETDATE() - @t_bloco, 114);


    -- ========================================================================
    -- 2.F: Raio-X transacional dos dias suspeitos
    -- ========================================================================
    SET @etapa = '2.F_CRM_RAIOX_TX';
    UPDATE C SET etapa = @etapa FROM temp_CGUSC.fp.crm_detalhado_lote_controle C INNER JOIN #lote_atual L ON L.id_cnpj = C.id_cnpj;

    SET @t_bloco = GETDATE();

    ;WITH DiasSuspeitos AS (
        SELECT V.id_cnpj, V.dt_alerta
        FROM temp_CGUSC.fp.volume_horario_anomalo_alertas V
        INNER JOIN #lote_atual L ON L.id_cnpj = V.id_cnpj
        UNION
        SELECT U.id_cnpj, U.dt_dia AS dt_alerta
        FROM temp_CGUSC.fp.crm_concentracao_unico_alertas U
        INNER JOIN #lote_atual L ON L.id_cnpj = U.id_cnpj
        UNION
        SELECT MU.id_cnpj, MU.dt_dia AS dt_alerta
        FROM temp_CGUSC.fp.crm_concentracao_multiplo_alertas MU
        INNER JOIN #lote_atual L ON L.id_cnpj = MU.id_cnpj
    )
    INSERT INTO temp_CGUSC.fp.crm_raiox_tx
        (id_cnpj, dt_janela, hr_janela, data_hora, num_autorizacao, id_medico, id_gtin, valor_pago)
    SELECT
        D.id_cnpj,
        CAST(M.data_hora AS DATE),
        CAST(DATEPART(HOUR, M.data_hora) AS TINYINT),
        CAST(M.data_hora AS SMALLDATETIME),
        M.num_autorizacao,
        CAST(CAST(M.crm AS VARCHAR(10)) + '/' + M.crm_uf AS VARCHAR(20)),
        PAT.id,
        CAST(M.valor_pago AS DECIMAL(9,2))
    FROM DiasSuspeitos D
    INNER JOIN #lote_atual L ON L.id_cnpj = D.id_cnpj
    INNER JOIN temp_CGUSC.fp.teste_mov_SC M
        ON  M.cnpj = L.cnpj
        AND CAST(M.data_hora AS DATE) = D.dt_alerta
    INNER JOIN temp_CGUSC.fp.medicamentos_patologia PAT ON PAT.codigo_barra = M.codigo_barra
    WHERE M.crm_uf IS NOT NULL
      AND M.crm IS NOT NULL
      AND M.crm_uf <> 'BR'
      AND M.data_hora >= @DataInicio
      AND M.data_hora < DATEADD(DAY, 1, @DataFim);

    PRINT '      2.F crm_raiox_tx:          ' + CONVERT(VARCHAR(20), GETDATE() - @t_bloco, 114);


    -- ========================================================================
    -- 2.G: Base de alertas e dados_crm_detalhado
    -- ========================================================================
    SET @etapa = '2.G_DADOS_CRM_DETALHADO';
    UPDATE C SET etapa = @etapa FROM temp_CGUSC.fp.crm_detalhado_lote_controle C INNER JOIN #lote_atual L ON L.id_cnpj = C.id_cnpj;

    SET @t_bloco = GETDATE();

    DROP TABLE IF EXISTS #lista_alertas_temp;
    SELECT
        A.nu_cnpj,
        A.id_medico,
        A.competencia,
        A.nu_prescricoes_medico,
        A.vl_autorizacoes_medico,
        A.dt_prescricao_inicial_medico,
        A.dt_prescricao_final_medico,
        DATEDIFF(DAY, A.dt_prescricao_inicial_medico, A.dt_prescricao_final_medico) + 1 AS nu_dias,
        ISNULL(P.nu_prescricoes_pico_h, 0) AS nu_prescricoes_pico_h,
        ISNULL(P.nu_minutos_dia, 0) AS nu_minutos_pico_h,
        ISNULL(P.taxa_dia, 0) AS taxa_pico_h,
        C.nu_autorizacoes_estabelecimento,
        C.dt_venda_inicial_estabelecimento,
        C.dt_venda_final_estabelecimento,
        TRY_CAST(A.nu_prescricoes_medico AS DECIMAL(10,2)) /
            NULLIF(TRY_CAST(C.nu_autorizacoes_estabelecimento AS DECIMAL(10,2)), 0) AS percentual
    INTO #lista_alertas_temp
    FROM #base_agregada_crm_cnpj A
    INNER JOIN #tb_info_estabelecimento C
        ON  C.cnpj = A.nu_cnpj
        AND C.competencia = A.competencia
    LEFT JOIN #pior_dia_crm P
        ON  P.nu_cnpj = A.nu_cnpj
        AND P.id_medico = A.id_medico
        AND P.competencia = A.competencia
    WHERE EXISTS (
            SELECT 1
            FROM #whitelist_crms_relevantes W
            WHERE W.nu_cnpj = A.nu_cnpj
              AND W.id_medico = A.id_medico
        )
       OR EXISTS (
            SELECT 1
            FROM #crms_em_surto_raw SR
            WHERE SR.nu_cnpj = A.nu_cnpj
              AND SR.id_medico = A.id_medico
              AND SR.competencia = A.competencia
        );

    INSERT INTO temp_CGUSC.fp.dados_crm_detalhado
        (nu_cnpj, competencia, id_medico, nu_prescricoes_medico, vl_autorizacoes_medico,
         nu_prescricoes_pico_h, taxa_pico_h, dt_prescricao_inicial_medico, dt_prescricao_final_medico)
    SELECT
        A.nu_cnpj,
        A.competencia,
        A.id_medico,
        A.nu_prescricoes_medico,
        A.vl_autorizacoes_medico,
        A.nu_prescricoes_pico_h,
        A.taxa_pico_h,
        A.dt_prescricao_inicial_medico,
        A.dt_prescricao_final_medico
    FROM #lista_alertas_temp A
    INNER JOIN temp_CGUSC.fp.crm_prescricoes_todos_estabelecimentos P
        ON  P.id_medico = A.id_medico
        AND P.competencia = A.competencia;

    PRINT '      2.G dados_crm_detalhado:   ' + CONVERT(VARCHAR(20), GETDATE() - @t_bloco, 114);


    -- ========================================================================
    -- 2.H: Fecha checkpoint do lote
    -- ========================================================================
    SET @etapa = '2.H_CHECKPOINT';
    UPDATE C SET etapa = @etapa FROM temp_CGUSC.fp.crm_detalhado_lote_controle C INNER JOIN #lote_atual L ON L.id_cnpj = C.id_cnpj;

    SET @t_bloco = GETDATE();

    UPDATE C
    SET status = 'OK',
        dt_fim = GETDATE(),
        etapa = 'OK',
        mensagem_erro = NULL,
        dt_erro = NULL,
        nu_dados_crm = ISNULL((
            SELECT COUNT(*)
            FROM temp_CGUSC.fp.dados_crm_detalhado D
            WHERE D.nu_cnpj = C.cnpj
        ), 0),
        nu_volume_alertas = ISNULL((
            SELECT COUNT(*)
            FROM temp_CGUSC.fp.volume_horario_anomalo_alertas V
            WHERE V.id_cnpj = C.id_cnpj
        ), 0),
        nu_raiox_tx = ISNULL((
            SELECT COUNT(*)
            FROM temp_CGUSC.fp.crm_raiox_tx R
            WHERE R.id_cnpj = C.id_cnpj
        ), 0)
    FROM temp_CGUSC.fp.crm_detalhado_lote_controle C
    INNER JOIN #lote_atual L ON L.id_cnpj = C.id_cnpj;

    DELETE P
    FROM #cnpjs_pendentes P
    INNER JOIN #lote_atual L ON L.id_cnpj = P.id_cnpj;

    SET @nu_processados += @nu_lote;

    PRINT '      2.H checkpoint:            ' + CONVERT(VARCHAR(20), GETDATE() - @t_bloco, 114);

    PRINT '   Lote ' + RIGHT('0000' + CAST(@lote_num AS VARCHAR(10)), 4) +
          ' | ' + CAST(@nu_ja_processados + @nu_processados AS VARCHAR(20)) + '/' + CAST(@nu_total AS VARCHAR(20)) + ' CNPJs' +
          ' | ' + CONVERT(VARCHAR(20), GETDATE() - @t1, 114);
    END TRY
    BEGIN CATCH
        DECLARE @mensagem_erro NVARCHAR(4000);

        SET @mensagem_erro = CONCAT(
            'Erro ', ERROR_NUMBER(),
            ' | Severidade ', ERROR_SEVERITY(),
            ' | Estado ', ERROR_STATE(),
            ' | Linha ', ERROR_LINE(),
            ' | ', ERROR_MESSAGE()
        );

        UPDATE C
        SET status = 'ERRO',
            dt_fim = GETDATE(),
            etapa = @etapa,
            mensagem_erro = @mensagem_erro,
            dt_erro = GETDATE()
        FROM temp_CGUSC.fp.crm_detalhado_lote_controle C
        INNER JOIN #lote_atual L ON L.id_cnpj = C.id_cnpj;

        UPDATE temp_CGUSC.fp.crm_detalhado_lote_metadata
        SET status = 'ERRO',
            dt_atualizacao = GETDATE(),
            observacao = LEFT(@mensagem_erro, 400)
        WHERE id_pipeline = 1;

        PRINT '   ERRO no lote ' + RIGHT('0000' + CAST(@lote_num AS VARCHAR(10)), 4) +
              ' | Etapa: ' + ISNULL(@etapa, 'N/I');
        PRINT '   ' + @mensagem_erro;

        THROW;
    END CATCH;
END;


-- ============================================================================
-- PASSO 2: Indices finais das maiores tabelas
-- ============================================================================
Finalizar:
PRINT '>> Criando indices finais das tabelas grandes...';
SET @t1 = GETDATE();

IF NOT EXISTS (SELECT 1 FROM temp_CGUSC.sys.indexes WHERE object_id = OBJECT_ID('temp_CGUSC.fp.crm_raiox_tx') AND name = 'IDX_RaioX_Cnpj_Data')
    CREATE CLUSTERED INDEX IDX_RaioX_Cnpj_Data
        ON temp_CGUSC.fp.crm_raiox_tx(id_cnpj, dt_janela);

IF NOT EXISTS (SELECT 1 FROM temp_CGUSC.sys.indexes WHERE object_id = OBJECT_ID('temp_CGUSC.fp.dados_crm_detalhado') AND name = 'IDX_DadosDet')
    CREATE CLUSTERED INDEX IDX_DadosDet
        ON temp_CGUSC.fp.dados_crm_detalhado(nu_cnpj, id_medico, competencia);

UPDATE temp_CGUSC.fp.crm_detalhado_lote_metadata
SET status = CASE
        WHEN EXISTS (SELECT 1 FROM temp_CGUSC.fp.crm_detalhado_lote_controle WHERE status <> 'OK') THEN 'INCOMPLETO'
        ELSE 'OK'
    END,
    dt_atualizacao = GETDATE(),
    observacao = 'Execucao finalizada pelo script loteado.'
WHERE id_pipeline = 1;

PRINT '   Indices finais concluidos em: ' + CONVERT(VARCHAR(20), GETDATE() - @t1, 114);


-- ============================================================================
-- RESULTADOS
-- ============================================================================
Resultados:
PRINT '==========================================================';
PRINT '   TEMPO TOTAL: ' + CONVERT(VARCHAR(20), GETDATE() - @t0, 114);
PRINT '==========================================================';

SELECT
    id_pipeline,
    pipeline_nome,
    pipeline_versao,
    dt_data_inicio,
    dt_data_fim,
    status,
    dt_criacao,
    dt_atualizacao,
    observacao
FROM temp_CGUSC.fp.crm_detalhado_lote_metadata;

SELECT
    status,
    COUNT(*) AS qtd_cnpjs,
    SUM(ISNULL(nu_dados_crm, 0)) AS total_dados_crm,
    SUM(ISNULL(nu_volume_alertas, 0)) AS total_volume_alertas,
    SUM(ISNULL(nu_raiox_tx, 0)) AS total_raiox_tx,
    MIN(dt_inicio) AS primeiro_inicio,
    MAX(dt_fim) AS ultimo_fim
FROM temp_CGUSC.fp.crm_detalhado_lote_controle
GROUP BY status;

SELECT
    id_cnpj,
    cnpj,
    status,
    etapa,
    mensagem_erro,
    dt_inicio,
    dt_fim,
    dt_erro
FROM temp_CGUSC.fp.crm_detalhado_lote_controle
WHERE status <> 'OK'
ORDER BY dt_inicio DESC, id_cnpj;

SELECT
    (SELECT COUNT(*) FROM temp_CGUSC.fp.dados_crm_detalhado) AS qtd_dados_crm_detalhado,
    (SELECT COUNT(*) FROM temp_CGUSC.fp.crm_perfil_diario) AS qtd_perfil_diario,
    (SELECT COUNT(*) FROM temp_CGUSC.fp.crm_perfil_horario) AS qtd_perfil_horario,
    (SELECT COUNT(*) FROM temp_CGUSC.fp.volume_horario_anomalo_alertas) AS qtd_volume_alertas,
    (SELECT COUNT(*) FROM temp_CGUSC.fp.crm_raiox_tx) AS qtd_raiox_tx,
    (SELECT COUNT(*) FROM temp_CGUSC.fp.crm_crms_em_surto) AS qtd_crms_em_surto;
