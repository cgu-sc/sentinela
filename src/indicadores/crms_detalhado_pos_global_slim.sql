-- ============================================================================
-- POS-PROCESSAMENTO GLOBAL CRM - SLIM
-- ============================================================================
-- Gera apenas:
--   1. temp_CGUSC.fp.alertas_crm_registro
--   2. temp_CGUSC.fp.alertas_crm
--   3. temp_CGUSC.fp.crm_export
--
-- Nao recria alertas_crm_geografico, benchmarks ou HHI. Essas tabelas devem
-- existir previamente quando forem usadas pelos joins abaixo.
-- ============================================================================

SET NOCOUNT ON;

DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim    DATE = '2024-12-31';
DECLARE @t0         DATETIME = GETDATE();
DECLARE @t1         DATETIME;
DECLARE @pipeline_nome        VARCHAR(80) = 'crms_detalhado_pos_global_slim';
DECLARE @pipeline_versao      VARCHAR(40) = 'v3_2026_05_12';
DECLARE @etapa               VARCHAR(80);
DECLARE @id_etapa_log        BIGINT;
DECLARE @dt_fim_etapa        DATETIME;
DECLARE @nu_registros_etapa  BIGINT;

PRINT '>> [POS-GLOBAL CRM SLIM] Iniciando...';
PRINT '   Periodo: ' + CAST(@DataInicio AS VARCHAR(10)) + ' -> ' + CAST(@DataFim AS VARCHAR(10));

-- ============================================================================
-- PASSO 0: Validacoes minimas
-- ============================================================================
IF OBJECT_ID('temp_CGUSC.fp.dados_farmacia') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.dados_farmacia nao encontrada.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('temp_CGUSC.fp.dados_medico') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.dados_medico nao encontrada. Rode o pre-global primeiro.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('temp_CGUSC.fp.crm_prescricoes_todos_estabelecimentos') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.crm_prescricoes_todos_estabelecimentos nao encontrada. Rode o pre-global primeiro.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('temp_CGUSC.fp.dados_crm_detalhado') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.dados_crm_detalhado nao encontrada. Rode o loteado primeiro.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('temp_CGUSC.fp.crm_concentracao_unico_alertas') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.crm_concentracao_unico_alertas nao encontrada.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('temp_CGUSC.fp.crm_concentracao_multiplo_alertas') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.crm_concentracao_multiplo_alertas nao encontrada.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('temp_CGUSC.fp.crm_raiox_tx') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.crm_raiox_tx nao encontrada. Rode o loteado primeiro.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('temp_CGUSC.fp.alertas_crm_geografico') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.alertas_crm_geografico nao encontrada. Este slim usa a geografica existente.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('temp_CGUSC.fp.crm_detalhado_pos_global_etapa_log') IS NULL
BEGIN
    CREATE TABLE temp_CGUSC.fp.crm_detalhado_pos_global_etapa_log (
        id_etapa_log        BIGINT IDENTITY(1,1) NOT NULL,
        pipeline_versao     VARCHAR(40)  NOT NULL,
        dt_data_inicio      DATE         NOT NULL,
        dt_data_fim         DATE         NOT NULL,
        etapa               VARCHAR(80)  NOT NULL,
        dt_inicio_etapa     DATETIME     NOT NULL,
        dt_fim_etapa        DATETIME     NULL,
        segundos_etapa      INT          NULL,
        milissegundos_etapa INT          NULL,
        nu_registros        BIGINT       NULL,
        status              VARCHAR(20)  NOT NULL,
        observacao          VARCHAR(400) NULL,
        mensagem_erro       NVARCHAR(4000) NULL,
        CONSTRAINT PK_CrmDetalhadoPosGlobalEtapaLog PRIMARY KEY CLUSTERED (id_etapa_log)
    );

    CREATE INDEX IDX_CrmDetalhadoPosGlobalEtapaLog_Periodo
        ON temp_CGUSC.fp.crm_detalhado_pos_global_etapa_log
            (pipeline_versao, dt_data_inicio, dt_data_fim, etapa, dt_inicio_etapa);
END;

DROP TABLE IF EXISTS temp_CGUSC.fp.crm_detalhado_pos_global_slim_metadata;
DROP TABLE IF EXISTS temp_CGUSC.fp.alertas_crm_registro;
DROP TABLE IF EXISTS temp_CGUSC.fp.alertas_crm;
DROP TABLE IF EXISTS temp_CGUSC.fp.crm_export;

CREATE TABLE temp_CGUSC.fp.crm_detalhado_pos_global_slim_metadata (
    id_pipeline       TINYINT      NOT NULL,
    pipeline_nome     VARCHAR(80)  NOT NULL,
    pipeline_versao   VARCHAR(40)  NOT NULL,
    dt_data_inicio    DATE         NOT NULL,
    dt_data_fim       DATE         NOT NULL,
    nu_alertas_crm_registro BIGINT NULL,
    nu_alertas_crm    BIGINT       NULL,
    nu_crm_export     BIGINT       NULL,
    dt_criacao        DATETIME     NOT NULL,
    dt_atualizacao    DATETIME     NULL,
    status            VARCHAR(20)  NOT NULL,
    observacao        VARCHAR(400) NULL,
    CONSTRAINT PK_CrmDetalhadoPosGlobalSlimMetadata PRIMARY KEY CLUSTERED (id_pipeline),
    CONSTRAINT CK_CrmDetalhadoPosGlobalSlimMetadata_Id CHECK (id_pipeline = 1)
);

INSERT INTO temp_CGUSC.fp.crm_detalhado_pos_global_slim_metadata
    (id_pipeline, pipeline_nome, pipeline_versao, dt_data_inicio, dt_data_fim,
     dt_criacao, dt_atualizacao, status, observacao)
VALUES
    (1, @pipeline_nome, @pipeline_versao, @DataInicio, @DataFim,
     GETDATE(), GETDATE(), 'PROCESSANDO', 'Pos-global slim em processamento.');

DELETE FROM temp_CGUSC.fp.crm_detalhado_pos_global_etapa_log
WHERE pipeline_versao = @pipeline_versao
  AND dt_data_inicio = @DataInicio
  AND dt_data_fim = @DataFim
  AND etapa IN ('SLIM_1_ALERTAS_CRM_REGISTRO', 'SLIM_2_ALERTAS_CRM', 'SLIM_3_CRM_EXPORT');

BEGIN TRY

-- ============================================================================
-- PASSO 1: Motor de registro CFM
-- ============================================================================
PRINT '>> Passo 1: Criando temp_CGUSC.fp.alertas_crm_registro...';
SET @etapa = 'SLIM_1_ALERTAS_CRM_REGISTRO';
SET @t1 = GETDATE();
SET @id_etapa_log = NULL;

INSERT INTO temp_CGUSC.fp.crm_detalhado_pos_global_etapa_log
    (pipeline_versao, dt_data_inicio, dt_data_fim, etapa, dt_inicio_etapa, status, observacao)
VALUES
    (@pipeline_versao, @DataInicio, @DataFim, @etapa, @t1, 'PROCESSANDO', 'Criando alertas_crm_registro.');

SET @id_etapa_log = CONVERT(BIGINT, SCOPE_IDENTITY());

SELECT
    A.nu_cnpj AS cnpj,
    A.id_medico,
    A.competencia,
    CONVERT(VARCHAR(20), MIN(A.dt_prescricao_inicial_medico), 103) AS dt_primeira_presc,
    CAST(NULL AS VARCHAR(20)) AS dt_registro_crm,
    CAST('INEXISTENTE' AS VARCHAR(20)) AS tipo_anomalia,
    SUM(A.nu_prescricoes_medico) AS nu_prescricoes,
    SUM(A.vl_autorizacoes_medico) AS vl_prescricoes
INTO temp_CGUSC.fp.alertas_crm_registro
FROM temp_CGUSC.fp.dados_crm_detalhado A
LEFT JOIN temp_CGUSC.fp.dados_medico M
    ON M.id_medico = A.id_medico
WHERE M.id_medico IS NULL
GROUP BY A.nu_cnpj, A.id_medico, A.competencia;

INSERT INTO temp_CGUSC.fp.alertas_crm_registro
    (cnpj, id_medico, competencia,
     dt_primeira_presc, dt_registro_crm, tipo_anomalia,
     nu_prescricoes, vl_prescricoes)
SELECT
    A.nu_cnpj AS cnpj,
    A.id_medico,
    A.competencia,
    CONVERT(VARCHAR(20), MIN(A.dt_prescricao_inicial_medico), 103) AS dt_primeira_presc,
    CONVERT(VARCHAR(20), M.dt_inscricao, 103) AS dt_registro_crm,
    'IRREGULAR' AS tipo_anomalia,
    SUM(A.nu_prescricoes_medico) AS nu_prescricoes,
    SUM(A.vl_autorizacoes_medico) AS vl_prescricoes
FROM temp_CGUSC.fp.dados_crm_detalhado A
INNER JOIN temp_CGUSC.fp.dados_medico M
    ON M.id_medico = A.id_medico
WHERE M.dt_inscricao > A.dt_prescricao_inicial_medico
GROUP BY A.nu_cnpj, A.id_medico, A.competencia, M.dt_inscricao;

CREATE CLUSTERED INDEX IDX_Registro
    ON temp_CGUSC.fp.alertas_crm_registro(cnpj, id_medico, competencia);

SET @dt_fim_etapa = GETDATE();
SELECT @nu_registros_etapa = COUNT(*) FROM temp_CGUSC.fp.alertas_crm_registro;

UPDATE temp_CGUSC.fp.crm_detalhado_pos_global_etapa_log
SET dt_fim_etapa = @dt_fim_etapa,
    segundos_etapa = DATEDIFF(SECOND, @t1, @dt_fim_etapa),
    milissegundos_etapa = DATEDIFF(MILLISECOND, @t1, @dt_fim_etapa),
    nu_registros = @nu_registros_etapa,
    status = 'OK',
    observacao = 'alertas_crm_registro criada.'
WHERE id_etapa_log = @id_etapa_log;

PRINT '   alertas_crm_registro concluida em: ' + CONVERT(VARCHAR(20), @dt_fim_etapa - @t1, 114);

-- ============================================================================
-- PASSO 2: Consolidador de flags
-- ============================================================================
PRINT '>> Passo 2: Criando temp_CGUSC.fp.alertas_crm...';
SET @etapa = 'SLIM_2_ALERTAS_CRM';
SET @t1 = GETDATE();
SET @id_etapa_log = NULL;

INSERT INTO temp_CGUSC.fp.crm_detalhado_pos_global_etapa_log
    (pipeline_versao, dt_data_inicio, dt_data_fim, etapa, dt_inicio_etapa, status, observacao)
VALUES
    (@pipeline_versao, @DataInicio, @DataFim, @etapa, @t1, 'PROCESSANDO', 'Criando alertas_crm.');

SET @id_etapa_log = CONVERT(BIGINT, SCOPE_IDENTITY());

;WITH multiplo_temporal AS (
    SELECT DISTINCT
        F.cnpj AS nu_cnpj,
        R.id_medico,
        YEAR(MU.dt_dia) * 100 + MONTH(MU.dt_dia) AS competencia
    FROM temp_CGUSC.fp.crm_concentracao_multiplo_alertas MU
    INNER JOIN temp_CGUSC.fp.dados_farmacia F
        ON F.id = MU.id_cnpj
    INNER JOIN temp_CGUSC.fp.crm_raiox_tx R
        ON  R.id_cnpj = MU.id_cnpj
        AND R.data_hora BETWEEN MU.dt_ini_concentracao AND MU.dt_fim_concentracao
),
base AS (
    SELECT DISTINCT
        F.cnpj AS nu_cnpj,
        U.id_medico,
        YEAR(U.dt_dia) * 100 + MONTH(U.dt_dia) AS competencia
    FROM temp_CGUSC.fp.crm_concentracao_unico_alertas U
    INNER JOIN temp_CGUSC.fp.dados_farmacia F
        ON F.id = U.id_cnpj
    UNION
    SELECT G1.cnpj_a AS nu_cnpj, G1.id_medico, G1.competencia
    FROM temp_CGUSC.fp.alertas_crm_geografico G1
    UNION
    SELECT G2.cnpj_b AS nu_cnpj, G2.id_medico, G2.competencia
    FROM temp_CGUSC.fp.alertas_crm_geografico G2
    UNION
    SELECT DISTINCT R1.cnpj AS nu_cnpj, R1.id_medico, R1.competencia
    FROM temp_CGUSC.fp.alertas_crm_registro R1
    UNION
    SELECT MT.nu_cnpj, MT.id_medico, MT.competencia
    FROM multiplo_temporal MT
),
conc_agg AS (
    SELECT
        F.cnpj AS nu_cnpj,
        U.id_medico,
        YEAR(U.dt_dia) * 100 + MONTH(U.dt_dia) AS competencia,
        COUNT(*) AS qtd_dias
    FROM temp_CGUSC.fp.crm_concentracao_unico_alertas U
    INNER JOIN temp_CGUSC.fp.dados_farmacia F
        ON F.id = U.id_cnpj
    GROUP BY F.cnpj, U.id_medico, YEAR(U.dt_dia) * 100 + MONTH(U.dt_dia)
),
geo_cnpj AS (
    SELECT DISTINCT T.nu_cnpj, T.id_medico, T.competencia
    FROM (
        SELECT G3.cnpj_a AS nu_cnpj, G3.id_medico, G3.competencia
        FROM temp_CGUSC.fp.alertas_crm_geografico G3
        UNION ALL
        SELECT G4.cnpj_b AS nu_cnpj, G4.id_medico, G4.competencia
        FROM temp_CGUSC.fp.alertas_crm_geografico G4
    ) T
),
registro AS (
    SELECT DISTINCT R2.cnpj AS nu_cnpj, R2.id_medico, R2.competencia
    FROM temp_CGUSC.fp.alertas_crm_registro R2
),
surto AS (
    SELECT DISTINCT nu_cnpj, id_medico, competencia
    FROM multiplo_temporal
)
SELECT
    B.nu_cnpj,
    B.id_medico,
    B.competencia,
    CAST(CASE WHEN CA.id_medico IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS flag_concentracao,
    CAST(CASE WHEN GC.id_medico IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS flag_geografico,
    CAST(CASE WHEN RE.id_medico IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS flag_registro,
    CAST(CASE WHEN SR.id_medico IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS alerta_concentracao_multiplos_crms,
    ISNULL(CA.qtd_dias, 0) AS qtd_dias_concentracao
INTO temp_CGUSC.fp.alertas_crm
FROM base B
LEFT JOIN conc_agg CA
    ON  CA.nu_cnpj = B.nu_cnpj
    AND CA.id_medico = B.id_medico
    AND CA.competencia = B.competencia
LEFT JOIN surto SR
    ON  SR.nu_cnpj = B.nu_cnpj
    AND SR.id_medico = B.id_medico
    AND SR.competencia = B.competencia
LEFT JOIN geo_cnpj GC
    ON  GC.nu_cnpj = B.nu_cnpj
    AND GC.id_medico = B.id_medico
    AND GC.competencia = B.competencia
LEFT JOIN registro RE
    ON  RE.nu_cnpj = B.nu_cnpj
    AND RE.id_medico = B.id_medico
    AND RE.competencia = B.competencia;

CREATE CLUSTERED INDEX IDX_Alertas_Key
    ON temp_CGUSC.fp.alertas_crm(nu_cnpj, id_medico, competencia);

SET @dt_fim_etapa = GETDATE();
SELECT @nu_registros_etapa = COUNT(*) FROM temp_CGUSC.fp.alertas_crm;

UPDATE temp_CGUSC.fp.crm_detalhado_pos_global_etapa_log
SET dt_fim_etapa = @dt_fim_etapa,
    segundos_etapa = DATEDIFF(SECOND, @t1, @dt_fim_etapa),
    milissegundos_etapa = DATEDIFF(MILLISECOND, @t1, @dt_fim_etapa),
    nu_registros = @nu_registros_etapa,
    status = 'OK',
    observacao = 'alertas_crm criada.'
WHERE id_etapa_log = @id_etapa_log;

PRINT '   alertas_crm concluida em: ' + CONVERT(VARCHAR(20), @dt_fim_etapa - @t1, 114);

-- ============================================================================
-- PASSO 3: Tabela final de exportacao
-- ============================================================================
PRINT '>> Passo 3: Criando temp_CGUSC.fp.crm_export...';
SET @etapa = 'SLIM_3_CRM_EXPORT';
SET @t1 = GETDATE();
SET @id_etapa_log = NULL;

INSERT INTO temp_CGUSC.fp.crm_detalhado_pos_global_etapa_log
    (pipeline_versao, dt_data_inicio, dt_data_fim, etapa, dt_inicio_etapa, status, observacao)
VALUES
    (@pipeline_versao, @DataInicio, @DataFim, @etapa, @t1, 'PROCESSANDO', 'Criando crm_export.');

SET @id_etapa_log = CONVERT(BIGINT, SCOPE_IDENTITY());

SELECT
    A.id_medico,
    FAR.id AS id_cnpj,
    A.competencia,
    A.nu_prescricoes_medico AS nu_prescricoes_mes,
    A.vl_autorizacoes_medico AS vl_total_prescricoes,
    A.nu_prescricoes_pico_h,
    A.taxa_pico_h,
    P.nu_prescricoes_medico_em_todos_estabelecimentos AS nu_prescricoes_total_brasil,
    P.nu_estabelecimentos_com_registro_mesmo_crm AS nu_estabelecimentos,
    CAST(CASE WHEN CONC.nu_cnpj IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS flag_concentracao_mesmo_crm,
    CAST(CASE WHEN G.id_medico IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS flag_distancia_geografica,
    A.dt_prescricao_inicial_medico AS dt_primeira_prescricao,
    M.dt_inscricao AS dt_inscricao_crm,
    CAST(CASE WHEN REG_INV.cnpj IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS flag_crm_invalido,
    CAST(CASE WHEN REG_IRR.cnpj IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS flag_prescricao_antes_registro,
    ISNULL(AL.alerta_concentracao_multiplos_crms, CAST(0 AS BIT)) AS alerta_concentracao_multiplos_crms
INTO temp_CGUSC.fp.crm_export
FROM temp_CGUSC.fp.dados_crm_detalhado A
LEFT JOIN temp_CGUSC.fp.dados_medico M
    ON M.id_medico = A.id_medico
LEFT JOIN temp_CGUSC.fp.dados_farmacia FAR
    ON FAR.cnpj = A.nu_cnpj
LEFT JOIN temp_CGUSC.fp.alertas_crm AL
    ON  AL.nu_cnpj = A.nu_cnpj
    AND AL.id_medico = A.id_medico
    AND AL.competencia = A.competencia
LEFT JOIN temp_CGUSC.fp.crm_prescricoes_todos_estabelecimentos P
    ON  P.id_medico = A.id_medico
    AND P.competencia = A.competencia
LEFT JOIN (
    SELECT DISTINCT
        F.cnpj AS nu_cnpj,
        C.id_medico,
        YEAR(C.dt_dia) * 100 + MONTH(C.dt_dia) AS competencia
    FROM temp_CGUSC.fp.crm_concentracao_unico_alertas C
    INNER JOIN temp_CGUSC.fp.dados_farmacia F
        ON F.id = C.id_cnpj
) CONC
    ON  CONC.nu_cnpj = A.nu_cnpj
    AND CONC.id_medico = A.id_medico
    AND CONC.competencia = A.competencia
LEFT JOIN temp_CGUSC.fp.alertas_crm_geografico G
    ON  G.id_medico = A.id_medico
    AND G.competencia = A.competencia
    AND (G.cnpj_a = A.nu_cnpj OR G.cnpj_b = A.nu_cnpj)
LEFT JOIN temp_CGUSC.fp.alertas_crm_registro REG_INV
    ON  REG_INV.cnpj = A.nu_cnpj
    AND REG_INV.id_medico = A.id_medico
    AND REG_INV.competencia = A.competencia
    AND REG_INV.tipo_anomalia = 'INEXISTENTE'
LEFT JOIN temp_CGUSC.fp.alertas_crm_registro REG_IRR
    ON  REG_IRR.cnpj = A.nu_cnpj
    AND REG_IRR.id_medico = A.id_medico
    AND REG_IRR.competencia = A.competencia
    AND REG_IRR.tipo_anomalia = 'IRREGULAR';

CREATE CLUSTERED INDEX IDX_CrmExport_Key
    ON temp_CGUSC.fp.crm_export(id_cnpj, id_medico, competencia);

SET @dt_fim_etapa = GETDATE();
SELECT @nu_registros_etapa = COUNT(*) FROM temp_CGUSC.fp.crm_export;

UPDATE temp_CGUSC.fp.crm_detalhado_pos_global_etapa_log
SET dt_fim_etapa = @dt_fim_etapa,
    segundos_etapa = DATEDIFF(SECOND, @t1, @dt_fim_etapa),
    milissegundos_etapa = DATEDIFF(MILLISECOND, @t1, @dt_fim_etapa),
    nu_registros = @nu_registros_etapa,
    status = 'OK',
    observacao = 'crm_export criada.'
WHERE id_etapa_log = @id_etapa_log;

PRINT '   crm_export concluida em: ' + CONVERT(VARCHAR(20), @dt_fim_etapa - @t1, 114);

-- ============================================================================
-- FINALIZACAO
-- ============================================================================
UPDATE temp_CGUSC.fp.crm_detalhado_pos_global_slim_metadata
SET nu_alertas_crm_registro = (SELECT COUNT(*) FROM temp_CGUSC.fp.alertas_crm_registro),
    nu_alertas_crm = (SELECT COUNT(*) FROM temp_CGUSC.fp.alertas_crm),
    nu_crm_export = (SELECT COUNT(*) FROM temp_CGUSC.fp.crm_export),
    status = 'OK',
    dt_atualizacao = GETDATE(),
    observacao = 'Pos-global slim finalizado com sucesso.'
WHERE id_pipeline = 1;

PRINT '==========================================================';
PRINT '   TEMPO TOTAL: ' + CONVERT(VARCHAR(20), GETDATE() - @t0, 114);
PRINT '==========================================================';

SELECT
    id_pipeline,
    pipeline_nome,
    pipeline_versao,
    dt_data_inicio,
    dt_data_fim,
    nu_alertas_crm_registro,
    nu_alertas_crm,
    nu_crm_export,
    status,
    dt_criacao,
    dt_atualizacao,
    observacao
FROM temp_CGUSC.fp.crm_detalhado_pos_global_slim_metadata;

SELECT
    (SELECT COUNT(*) FROM temp_CGUSC.fp.alertas_crm_registro) AS qtd_alertas_crm_registro,
    (SELECT COUNT(*) FROM temp_CGUSC.fp.alertas_crm) AS qtd_alertas_crm,
    (SELECT COUNT(*) FROM temp_CGUSC.fp.crm_export) AS qtd_crm_export;

SELECT TOP 30
    id_medico,
    id_cnpj,
    competencia,
    nu_prescricoes_mes,
    vl_total_prescricoes,
    flag_concentracao_mesmo_crm,
    flag_distancia_geografica,
    flag_crm_invalido,
    flag_prescricao_antes_registro,
    alerta_concentracao_multiplos_crms
FROM temp_CGUSC.fp.crm_export
ORDER BY nu_prescricoes_mes DESC;

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

    IF OBJECT_ID('temp_CGUSC.fp.crm_detalhado_pos_global_slim_metadata') IS NOT NULL
    BEGIN
        UPDATE temp_CGUSC.fp.crm_detalhado_pos_global_slim_metadata
        SET status = 'ERRO',
            dt_atualizacao = GETDATE(),
            observacao = LEFT(@mensagem_erro, 400)
        WHERE id_pipeline = 1;
    END;

    IF @id_etapa_log IS NOT NULL
       AND OBJECT_ID('temp_CGUSC.fp.crm_detalhado_pos_global_etapa_log') IS NOT NULL
    BEGIN
        SET @dt_fim_etapa = GETDATE();

        UPDATE temp_CGUSC.fp.crm_detalhado_pos_global_etapa_log
        SET dt_fim_etapa = @dt_fim_etapa,
            segundos_etapa = DATEDIFF(SECOND, @t1, @dt_fim_etapa),
            milissegundos_etapa = DATEDIFF(MILLISECOND, @t1, @dt_fim_etapa),
            status = 'ERRO',
            observacao = LEFT(@mensagem_erro, 400),
            mensagem_erro = @mensagem_erro
        WHERE id_etapa_log = @id_etapa_log;
    END;

    PRINT '   ERRO no pos-global CRM slim.';
    PRINT '   ' + @mensagem_erro;

    THROW;
END CATCH;
