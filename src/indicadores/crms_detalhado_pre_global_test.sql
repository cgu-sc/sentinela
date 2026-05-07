-- ============================================================================
-- PRE-PROCESSAMENTO GLOBAL PARA INDICADOR DE CRMs
-- ============================================================================
-- Este script prepara tabelas globais reutilizaveis pelo fluxo loteado do
-- crms_detalhado_test.sql.
--
-- Saidas persistentes:
--   0. temp_CGUSC.fp.crm_detalhado_pre_global_metadata
--      Metadados de versao, periodo e status consumidos pelo script loteado.
--
--   1. temp_CGUSC.fp.dados_medico
--      Mapa CFM normalizado por id_medico.
--
--   2. temp_CGUSC.fp.crm_prescricoes_todos_estabelecimentos
--      Totais nacionais por (id_medico, competencia), equivalentes ao antigo
--      #prescricoes_todos_estabelecimentos.
--
-- Observacao:
--   alertas_crm_geografico e benchmarks dependem de dados_crm_detalhado
--   completo, entao ficam para o script pos-global.
-- ============================================================================

SET NOCOUNT ON;

DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim    DATE = '2024-12-31';
DECLARE @t0         DATETIME = GETDATE();
DECLARE @t1         DATETIME;
DECLARE @pipeline_nome   VARCHAR(80) = 'crms_detalhado_pre_global';
DECLARE @pipeline_versao VARCHAR(40) = 'v1_pre_global_2026_05_07';

PRINT '>> [PRE-GLOBAL CRM] Iniciando pre-processamento global...';
PRINT '   Periodo: ' + CAST(@DataInicio AS VARCHAR(10)) + ' -> ' + CAST(@DataFim AS VARCHAR(10));

DROP TABLE IF EXISTS temp_CGUSC.fp.crm_detalhado_pre_global_metadata;

CREATE TABLE temp_CGUSC.fp.crm_detalhado_pre_global_metadata (
    id_pipeline       TINYINT      NOT NULL,
    pipeline_nome     VARCHAR(80)  NOT NULL,
    pipeline_versao   VARCHAR(40)  NOT NULL,
    dt_data_inicio    DATE         NOT NULL,
    dt_data_fim       DATE         NOT NULL,
    dt_criacao        DATETIME     NOT NULL,
    dt_atualizacao    DATETIME     NULL,
    status            VARCHAR(20)  NOT NULL,
    observacao        VARCHAR(400) NULL,
    CONSTRAINT PK_CrmDetalhadoPreGlobalMetadata PRIMARY KEY CLUSTERED (id_pipeline),
    CONSTRAINT CK_CrmDetalhadoPreGlobalMetadata_Id CHECK (id_pipeline = 1)
);

INSERT INTO temp_CGUSC.fp.crm_detalhado_pre_global_metadata
    (id_pipeline, pipeline_nome, pipeline_versao, dt_data_inicio, dt_data_fim,
     dt_criacao, dt_atualizacao, status, observacao)
VALUES
    (1, @pipeline_nome, @pipeline_versao, @DataInicio, @DataFim,
     GETDATE(), GETDATE(), 'PROCESSANDO', 'Pre-global em processamento.');

BEGIN TRY

-- ============================================================================
-- PASSO 1: MAPA DE MEDICOS PARA ID INT
-- ============================================================================
PRINT '>> Passo 1: Criando temp_CGUSC.fp.dados_medico...';
SET @t1 = GETDATE();

DROP TABLE IF EXISTS temp_CGUSC.fp.dados_medico;

SELECT
    CAST(ROW_NUMBER() OVER (ORDER BY TRY_CAST(NU_CRM AS INT), SG_UF) AS INT) AS id,
    CAST(CAST(TRY_CAST(NU_CRM AS BIGINT) AS VARCHAR(10)) + '/' + SG_UF AS VARCHAR(20)) AS id_medico,
    TRY_CAST(NU_CRM AS BIGINT)                           AS nu_crm,
    SG_UF                                                AS sg_uf,
    NM_MEDICO                                            AS no_medico,
    TRY_CONVERT(DATE, DT_INSCRICAO, 103)                 AS dt_inscricao
INTO temp_CGUSC.fp.dados_medico
FROM temp_CFM.dbo.medicos_jul_2025_mod
WHERE NU_CRM IS NOT NULL
  AND TRY_CAST(NU_CRM AS BIGINT) > 0;

CREATE CLUSTERED INDEX IDX_Join_Medico
    ON temp_CGUSC.fp.dados_medico(id_medico);

CREATE NONCLUSTERED INDEX IDX_ID_Medico
    ON temp_CGUSC.fp.dados_medico(id);

PRINT '   temp_CGUSC.fp.dados_medico concluida em: ' + CONVERT(VARCHAR(20), GETDATE() - @t1, 114);


-- ============================================================================
-- PASSO 2: TOTAIS NACIONAIS POR MEDICO / COMPETENCIA
-- ============================================================================
-- Preserva o grain do fluxo atual:
--   1. conta autorizacoes por (cnpj, medico, competencia);
--   2. soma esses totais para (medico, competencia);
--   3. conta quantos estabelecimentos tiveram registro do medico no mes.
-- ============================================================================
PRINT '>> Passo 2: Criando temp_CGUSC.fp.crm_prescricoes_todos_estabelecimentos...';
SET @t1 = GETDATE();

DROP TABLE IF EXISTS temp_CGUSC.fp.crm_prescricoes_todos_estabelecimentos;

;WITH base_crm_cnpj AS (
    SELECT
        CAST(M.cnpj AS CHAR(14)) AS nu_cnpj,
        CAST(CAST(M.crm AS VARCHAR(10)) + '/' + M.crm_uf AS VARCHAR(20)) AS id_medico,
        YEAR(M.data_hora) * 100 + MONTH(M.data_hora) AS competencia,
        COUNT(DISTINCT M.num_autorizacao) AS nu_prescricoes_medico
    FROM temp_CGUSC.fp.teste_mov_SC M
    INNER JOIN temp_CGUSC.fp.medicamentos_patologia PAT
        ON PAT.codigo_barra = M.codigo_barra
    WHERE M.crm_uf IS NOT NULL
      AND M.crm IS NOT NULL
      AND M.crm_uf <> 'BR'
      AND M.data_hora >= @DataInicio
      AND M.data_hora < DATEADD(DAY, 1, @DataFim)
    GROUP BY
        M.cnpj,
        M.crm,
        M.crm_uf,
        YEAR(M.data_hora),
        MONTH(M.data_hora)
)
SELECT
    id_medico,
    competencia,
    CAST(SUM(nu_prescricoes_medico) AS INT)          AS nu_prescricoes_medico_em_todos_estabelecimentos,
    CAST(COUNT(DISTINCT nu_cnpj) AS INT)             AS nu_estabelecimentos_com_registro_mesmo_crm
INTO temp_CGUSC.fp.crm_prescricoes_todos_estabelecimentos
FROM base_crm_cnpj
GROUP BY id_medico, competencia;

CREATE CLUSTERED INDEX IDX_CrmPrescTodos_Key
    ON temp_CGUSC.fp.crm_prescricoes_todos_estabelecimentos(id_medico, competencia);

PRINT '   temp_CGUSC.fp.crm_prescricoes_todos_estabelecimentos concluida em: ' + CONVERT(VARCHAR(20), GETDATE() - @t1, 114);

UPDATE temp_CGUSC.fp.crm_detalhado_pre_global_metadata
SET status = 'OK',
    dt_atualizacao = GETDATE(),
    observacao = 'Pre-global finalizado com sucesso.'
WHERE id_pipeline = 1;


-- ============================================================================
-- RESULTADOS
-- ============================================================================
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
FROM temp_CGUSC.fp.crm_detalhado_pre_global_metadata;

SELECT
    COUNT(*) AS qtd_medicos_cfm
FROM temp_CGUSC.fp.dados_medico;

SELECT
    COUNT(*) AS qtd_medico_competencia,
    COUNT(DISTINCT id_medico) AS qtd_medicos,
    MIN(competencia) AS primeira_competencia,
    MAX(competencia) AS ultima_competencia,
    SUM(nu_prescricoes_medico_em_todos_estabelecimentos) AS total_prescricoes
FROM temp_CGUSC.fp.crm_prescricoes_todos_estabelecimentos;

SELECT TOP 30
    id_medico,
    competencia,
    nu_prescricoes_medico_em_todos_estabelecimentos,
    nu_estabelecimentos_com_registro_mesmo_crm
FROM temp_CGUSC.fp.crm_prescricoes_todos_estabelecimentos
ORDER BY nu_prescricoes_medico_em_todos_estabelecimentos DESC;

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

    IF OBJECT_ID('temp_CGUSC.fp.crm_detalhado_pre_global_metadata') IS NOT NULL
    BEGIN
        UPDATE temp_CGUSC.fp.crm_detalhado_pre_global_metadata
        SET status = 'ERRO',
            dt_atualizacao = GETDATE(),
            observacao = LEFT(@mensagem_erro, 400)
        WHERE id_pipeline = 1;
    END;

    PRINT '   ERRO no pre-global CRM.';
    PRINT '   ' + @mensagem_erro;

    THROW;
END CATCH;
