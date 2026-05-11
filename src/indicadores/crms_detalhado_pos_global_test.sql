-- ============================================================================
-- POS-PROCESSAMENTO GLOBAL PARA INDICADOR DE CRMs
-- ============================================================================
-- Script 3 do pipeline:
--   - valida que o pre-global e o loteado terminaram com sucesso;
--   - consolida alertas globais;
--   - gera tabela final de exportacao;
--   - gera benchmarks e matriz HHI.
--
-- Pre-requisitos:
--   1. temp_CGUSC.fp.crm_detalhado_pre_global_metadata com status OK
--   2. temp_CGUSC.fp.crm_detalhado_lote_metadata com status OK
--   3. temp_CGUSC.fp.crm_pipeline_uf_controle com UFs OK no loteado
--   4. temp_CGUSC.fp.dados_medico
--   5. temp_CGUSC.fp.crm_prescricoes_todos_estabelecimentos
--   6. temp_CGUSC.fp.dados_crm_detalhado
--   7. temp_CGUSC.fp.crm_crms_em_surto
--
-- Saidas persistentes:
--   - temp_CGUSC.fp.alertas_crm_geografico
--   - temp_CGUSC.fp.alertas_crm_registro
--   - temp_CGUSC.fp.alertas_crm
--   - temp_CGUSC.fp.crm_export
--   - temp_CGUSC.fp.indicador_crm_bench_uf
--   - temp_CGUSC.fp.indicador_crm_bench_regiao
--   - temp_CGUSC.fp.indicador_crm_bench_br
--   - temp_CGUSC.fp.indicador_crm_hhi
-- ============================================================================

-- Batch separado: valida o estado do pipeline antes de remover qualquer saida
-- pos-global ja existente. Assim, uma execucao acidental antes do loteado
-- terminar nao apaga resultados bons de uma rodada anterior.
SET NOCOUNT ON;

DECLARE @PrecheckDataInicio DATE = '2015-07-01';
DECLARE @PrecheckDataFim    DATE = '2024-12-31';
DECLARE @PrecheckVersao     VARCHAR(40) = 'v2_2026_05_07';
DECLARE @PrecheckOk         BIT;

IF OBJECT_ID('temp_CGUSC.fp.dados_farmacia') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.dados_farmacia nao encontrada.', 16, 1);
    RETURN;
END;

IF COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'cnpj') IS NULL
    OR COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'id') IS NULL
    OR COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'uf') IS NULL
    OR COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'codibge') IS NULL
    OR COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'id_regiao_saude') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.dados_farmacia existe, mas nao possui o schema minimo esperado: id, cnpj, uf, codibge, id_regiao_saude.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('temp_CGUSC.sus.tb_ibge') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.sus.tb_ibge nao encontrada.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('temp_CGUSC.fp.fnCalcular_Distancia_KM') IS NULL
BEGIN
    RAISERROR('Funcao temp_CGUSC.fp.fnCalcular_Distancia_KM nao encontrada.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('temp_CGUSC.fp.crm_detalhado_pre_global_metadata') IS NULL
BEGIN
    RAISERROR('Metadata pre-global temp_CGUSC.fp.crm_detalhado_pre_global_metadata nao encontrada. Rode crms_detalhado_pre_global_test.sql primeiro.', 16, 1);
    RETURN;
END;

SET @PrecheckOk = 0;
SELECT @PrecheckOk = CASE WHEN EXISTS (
    SELECT 1
    FROM temp_CGUSC.fp.crm_detalhado_pre_global_metadata
    WHERE id_pipeline = 1
      AND pipeline_nome = 'crms_detalhado_pre_global'
      AND pipeline_versao = @PrecheckVersao
      AND dt_data_inicio = @PrecheckDataInicio
      AND dt_data_fim = @PrecheckDataFim
      AND status = 'OK'
) THEN 1 ELSE 0 END;

IF @PrecheckOk = 0
BEGIN
    RAISERROR('Pre-global incompativel ou nao finalizado com OK para esta versao/periodo.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('temp_CGUSC.fp.crm_detalhado_lote_metadata') IS NULL
BEGIN
    RAISERROR('Metadata loteada temp_CGUSC.fp.crm_detalhado_lote_metadata nao encontrada. Rode crms_detalhado_loteado_test.sql primeiro.', 16, 1);
    RETURN;
END;

SET @PrecheckOk = 0;
SELECT @PrecheckOk = CASE WHEN EXISTS (
    SELECT 1
    FROM temp_CGUSC.fp.crm_detalhado_lote_metadata
    WHERE id_pipeline = 1
      AND pipeline_nome = 'crms_detalhado_loteado'
      AND pipeline_versao = @PrecheckVersao
      AND dt_data_inicio = @PrecheckDataInicio
      AND dt_data_fim = @PrecheckDataFim
      AND status = 'OK'
) THEN 1 ELSE 0 END;

IF @PrecheckOk = 0
BEGIN
    RAISERROR('Loteado incompativel ou nao finalizado com OK para esta versao/periodo.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('temp_CGUSC.fp.crm_pipeline_uf_controle') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.crm_pipeline_uf_controle nao encontrada.', 16, 1);
    RETURN;
END;

IF EXISTS (
    SELECT 1
    FROM temp_CGUSC.fp.crm_pipeline_uf_controle
    WHERE pipeline_versao = @PrecheckVersao
      AND dt_data_inicio = @PrecheckDataInicio
      AND dt_data_fim = @PrecheckDataFim
      AND (
             ISNULL(status_concentracao_unico, '') <> 'OK'
          OR ISNULL(status_concentracao_multiplo, '') <> 'OK'
          OR ISNULL(status_crm_detalhado_loteado, '') <> 'OK'
      )
)
BEGIN
    RAISERROR('Ainda ha UF sem concentracoes e/ou loteado OK no crm_pipeline_uf_controle para esta versao/periodo.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('temp_CGUSC.fp.crm_detalhado_lote_controle') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.crm_detalhado_lote_controle nao encontrada.', 16, 1);
    RETURN;
END;

IF EXISTS (SELECT 1 FROM temp_CGUSC.fp.crm_detalhado_lote_controle WHERE status <> 'OK')
BEGIN
    RAISERROR('Ainda ha CNPJ sem status OK em temp_CGUSC.fp.crm_detalhado_lote_controle.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('temp_CGUSC.fp.dados_medico') IS NULL
    OR OBJECT_ID('temp_CGUSC.fp.crm_prescricoes_todos_estabelecimentos') IS NULL
    OR OBJECT_ID('temp_CGUSC.fp.dados_crm_detalhado') IS NULL
    OR OBJECT_ID('temp_CGUSC.fp.crm_crms_em_surto') IS NULL
    OR OBJECT_ID('temp_CGUSC.fp.crm_concentracao_unico_alertas') IS NULL
BEGIN
    RAISERROR('Uma ou mais tabelas de entrada do pos-global nao existem. Rode pre-global, concentracoes e loteado antes.', 16, 1);
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

IF COL_LENGTH('temp_CGUSC.fp.crm_detalhado_pos_global_etapa_log', 'dt_fim_etapa') IS NULL
    ALTER TABLE temp_CGUSC.fp.crm_detalhado_pos_global_etapa_log ADD dt_fim_etapa DATETIME NULL;

IF COL_LENGTH('temp_CGUSC.fp.crm_detalhado_pos_global_etapa_log', 'segundos_etapa') IS NULL
    ALTER TABLE temp_CGUSC.fp.crm_detalhado_pos_global_etapa_log ADD segundos_etapa INT NULL;

IF COL_LENGTH('temp_CGUSC.fp.crm_detalhado_pos_global_etapa_log', 'milissegundos_etapa') IS NULL
    ALTER TABLE temp_CGUSC.fp.crm_detalhado_pos_global_etapa_log ADD milissegundos_etapa INT NULL;

IF COL_LENGTH('temp_CGUSC.fp.crm_detalhado_pos_global_etapa_log', 'nu_registros') IS NULL
    ALTER TABLE temp_CGUSC.fp.crm_detalhado_pos_global_etapa_log ADD nu_registros BIGINT NULL;

IF COL_LENGTH('temp_CGUSC.fp.crm_detalhado_pos_global_etapa_log', 'status') IS NULL
    ALTER TABLE temp_CGUSC.fp.crm_detalhado_pos_global_etapa_log ADD status VARCHAR(20) NULL;

IF COL_LENGTH('temp_CGUSC.fp.crm_detalhado_pos_global_etapa_log', 'observacao') IS NULL
    ALTER TABLE temp_CGUSC.fp.crm_detalhado_pos_global_etapa_log ADD observacao VARCHAR(400) NULL;

IF COL_LENGTH('temp_CGUSC.fp.crm_detalhado_pos_global_etapa_log', 'mensagem_erro') IS NULL
    ALTER TABLE temp_CGUSC.fp.crm_detalhado_pos_global_etapa_log ADD mensagem_erro NVARCHAR(4000) NULL;

-- Batch separado: remove saidas pos-globais antigas antes da compilacao da
-- batch principal. Isso evita Msg 207 quando uma tabela antiga existe com
-- schema diferente, mas sera recriada abaixo.
DROP TABLE IF EXISTS temp_CGUSC.fp.crm_detalhado_pos_global_metadata;
DROP TABLE IF EXISTS temp_CGUSC.fp.alertas_crm_geografico;
DROP TABLE IF EXISTS temp_CGUSC.fp.alertas_crm_registro;
DROP TABLE IF EXISTS temp_CGUSC.fp.alertas_crm;
DROP TABLE IF EXISTS temp_CGUSC.fp.crm_export;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crm_bench_uf;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crm_bench_regiao;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crm_bench_br;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crm_hhi;
GO

SET NOCOUNT ON;

DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim    DATE = '2024-12-31';
DECLARE @t0         DATETIME = GETDATE();
DECLARE @t1         DATETIME;
DECLARE @pipeline_nome        VARCHAR(80) = 'crms_detalhado_pos_global';
DECLARE @pipeline_versao      VARCHAR(40) = 'v2_2026_05_07';
DECLARE @pre_global_nome      VARCHAR(80) = 'crms_detalhado_pre_global';
DECLARE @loteado_nome         VARCHAR(80) = 'crms_detalhado_loteado';
DECLARE @metadata_ok          BIT;
DECLARE @etapa               VARCHAR(80);
DECLARE @id_etapa_log        BIGINT;
DECLARE @dt_fim_etapa        DATETIME;
DECLARE @nu_registros_etapa  BIGINT;

PRINT '>> [POS-GLOBAL CRM] Iniciando pos-processamento global...';
PRINT '   Periodo: ' + CAST(@DataInicio AS VARCHAR(10)) + ' -> ' + CAST(@DataFim AS VARCHAR(10));

-- ============================================================================
-- PASSO 0: Validacoes de pre-requisitos e estado do pipeline
-- ============================================================================
IF OBJECT_ID('temp_CGUSC.fp.dados_farmacia') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.dados_farmacia nao encontrada.', 16, 1);
    RETURN;
END;

IF COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'cnpj') IS NULL
    OR COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'id') IS NULL
    OR COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'uf') IS NULL
    OR COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'codibge') IS NULL
    OR COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'id_regiao_saude') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.dados_farmacia existe, mas nao possui o schema minimo esperado: id, cnpj, uf, codibge, id_regiao_saude.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('temp_CGUSC.sus.tb_ibge') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.sus.tb_ibge nao encontrada.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('temp_CGUSC.fp.fnCalcular_Distancia_KM') IS NULL
BEGIN
    RAISERROR('Funcao temp_CGUSC.fp.fnCalcular_Distancia_KM nao encontrada.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('temp_CGUSC.fp.crm_detalhado_pre_global_metadata') IS NULL
BEGIN
    RAISERROR('Metadata pre-global temp_CGUSC.fp.crm_detalhado_pre_global_metadata nao encontrada. Rode crms_detalhado_pre_global_test.sql primeiro.', 16, 1);
    RETURN;
END;

SET @metadata_ok = 0;
EXEC sp_executesql
    N'SELECT @ok = CASE WHEN EXISTS (
          SELECT 1
          FROM temp_CGUSC.fp.crm_detalhado_pre_global_metadata
          WHERE id_pipeline = 1
            AND pipeline_nome = @nome
            AND pipeline_versao = @versao
            AND dt_data_inicio = @inicio
            AND dt_data_fim = @fim
            AND status = ''OK''
      ) THEN 1 ELSE 0 END;',
    N'@nome VARCHAR(80), @versao VARCHAR(40), @inicio DATE, @fim DATE, @ok BIT OUTPUT',
    @nome = @pre_global_nome,
    @versao = @pipeline_versao,
    @inicio = @DataInicio,
    @fim = @DataFim,
    @ok = @metadata_ok OUTPUT;

IF @metadata_ok = 0
BEGIN
    RAISERROR('Pre-global incompativel ou nao finalizado com OK para esta versao/periodo.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('temp_CGUSC.fp.crm_detalhado_lote_metadata') IS NULL
BEGIN
    RAISERROR('Metadata loteada temp_CGUSC.fp.crm_detalhado_lote_metadata nao encontrada. Rode crms_detalhado_loteado_test.sql primeiro.', 16, 1);
    RETURN;
END;

SET @metadata_ok = 0;
EXEC sp_executesql
    N'SELECT @ok = CASE WHEN EXISTS (
          SELECT 1
          FROM temp_CGUSC.fp.crm_detalhado_lote_metadata
          WHERE id_pipeline = 1
            AND pipeline_nome = @nome
            AND pipeline_versao = @versao
            AND dt_data_inicio = @inicio
            AND dt_data_fim = @fim
            AND status = ''OK''
      ) THEN 1 ELSE 0 END;',
    N'@nome VARCHAR(80), @versao VARCHAR(40), @inicio DATE, @fim DATE, @ok BIT OUTPUT',
    @nome = @loteado_nome,
    @versao = @pipeline_versao,
    @inicio = @DataInicio,
    @fim = @DataFim,
    @ok = @metadata_ok OUTPUT;

IF @metadata_ok = 0
BEGIN
    RAISERROR('Loteado incompativel ou nao finalizado com OK para esta versao/periodo.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('temp_CGUSC.fp.crm_pipeline_uf_controle') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.crm_pipeline_uf_controle nao encontrada.', 16, 1);
    RETURN;
END;

IF EXISTS (
    SELECT 1
    FROM temp_CGUSC.fp.crm_pipeline_uf_controle
    WHERE pipeline_versao = @pipeline_versao
      AND dt_data_inicio = @DataInicio
      AND dt_data_fim = @DataFim
      AND (
             ISNULL(status_concentracao_unico, '') <> 'OK'
          OR ISNULL(status_concentracao_multiplo, '') <> 'OK'
          OR ISNULL(status_crm_detalhado_loteado, '') <> 'OK'
      )
)
BEGIN
    RAISERROR('Ainda ha UF sem concentracoes e/ou loteado OK no crm_pipeline_uf_controle para esta versao/periodo.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('temp_CGUSC.fp.crm_detalhado_lote_controle') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.crm_detalhado_lote_controle nao encontrada.', 16, 1);
    RETURN;
END;

IF EXISTS (SELECT 1 FROM temp_CGUSC.fp.crm_detalhado_lote_controle WHERE status <> 'OK')
BEGIN
    RAISERROR('Ainda ha CNPJ sem status OK em temp_CGUSC.fp.crm_detalhado_lote_controle.', 16, 1);
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

IF OBJECT_ID('temp_CGUSC.fp.crm_crms_em_surto') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.crm_crms_em_surto nao encontrada. Rode o loteado primeiro.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('temp_CGUSC.fp.crm_concentracao_unico_alertas') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.crm_concentracao_unico_alertas nao encontrada.', 16, 1);
    RETURN;
END;

DROP TABLE IF EXISTS temp_CGUSC.fp.crm_detalhado_pos_global_metadata;
DROP TABLE IF EXISTS temp_CGUSC.fp.alertas_crm_geografico;
DROP TABLE IF EXISTS temp_CGUSC.fp.alertas_crm_registro;
DROP TABLE IF EXISTS temp_CGUSC.fp.alertas_crm;
DROP TABLE IF EXISTS temp_CGUSC.fp.crm_export;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crm_bench_uf;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crm_bench_regiao;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crm_bench_br;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crm_hhi;

CREATE TABLE temp_CGUSC.fp.crm_detalhado_pos_global_metadata (
    id_pipeline       TINYINT      NOT NULL,
    pipeline_nome     VARCHAR(80)  NOT NULL,
    pipeline_versao   VARCHAR(40)  NOT NULL,
    dt_data_inicio    DATE         NOT NULL,
    dt_data_fim       DATE         NOT NULL,
    nu_alertas_crm    BIGINT       NULL,
    nu_crm_export     BIGINT       NULL,
    nu_bench_uf       BIGINT       NULL,
    nu_bench_regiao   BIGINT       NULL,
    nu_bench_br       BIGINT       NULL,
    nu_hhi            BIGINT       NULL,
    dt_criacao        DATETIME     NOT NULL,
    dt_atualizacao    DATETIME     NULL,
    status            VARCHAR(20)  NOT NULL,
    observacao        VARCHAR(400) NULL,
    CONSTRAINT PK_CrmDetalhadoPosGlobalMetadata PRIMARY KEY CLUSTERED (id_pipeline),
    CONSTRAINT CK_CrmDetalhadoPosGlobalMetadata_Id CHECK (id_pipeline = 1)
);

INSERT INTO temp_CGUSC.fp.crm_detalhado_pos_global_metadata
    (id_pipeline, pipeline_nome, pipeline_versao, dt_data_inicio, dt_data_fim,
     dt_criacao, dt_atualizacao, status, observacao)
VALUES
    (1, @pipeline_nome, @pipeline_versao, @DataInicio, @DataFim,
     GETDATE(), GETDATE(), 'PROCESSANDO', 'Pos-global em processamento.');

DELETE FROM temp_CGUSC.fp.crm_detalhado_pos_global_etapa_log
WHERE pipeline_versao = @pipeline_versao
  AND dt_data_inicio = @DataInicio
  AND dt_data_fim = @DataFim;

BEGIN TRY

-- ============================================================================
-- PASSO 1: Motor geografico
-- ============================================================================
PRINT '>> Passo 1: Criando temp_CGUSC.fp.alertas_crm_geografico...';
SET @etapa = '1_ALERTAS_CRM_GEOGRAFICO';
SET @t1 = GETDATE();
SET @id_etapa_log = NULL;

INSERT INTO temp_CGUSC.fp.crm_detalhado_pos_global_etapa_log
    (pipeline_versao, dt_data_inicio, dt_data_fim, etapa, dt_inicio_etapa, status, observacao)
VALUES
    (@pipeline_versao, @DataInicio, @DataFim, @etapa, @t1, 'PROCESSANDO', 'Criando alertas_crm_geografico.');

SET @id_etapa_log = CONVERT(BIGINT, SCOPE_IDENTITY());

DROP TABLE IF EXISTS #base_com_geo;

SELECT
    D.nu_cnpj,
    D.id_medico,
    D.competencia,
    D.nu_prescricoes_medico,
    D.dt_prescricao_inicial_medico,
    D.dt_prescricao_final_medico,
    G.latitude,
    G.longitude,
    F.uf AS sg_uf
INTO #base_com_geo
FROM temp_CGUSC.fp.dados_crm_detalhado D
LEFT JOIN temp_CGUSC.fp.dados_farmacia F
    ON F.cnpj = D.nu_cnpj
LEFT JOIN temp_CGUSC.sus.tb_ibge G
    ON G.id_ibge7 = F.codibge
WHERE D.nu_prescricoes_medico >= 30
  AND G.latitude IS NOT NULL
  AND G.longitude IS NOT NULL;

CREATE CLUSTERED INDEX IDX_GeoBase
    ON #base_com_geo(id_medico, competencia);

;WITH PairedWithDistance AS (
    SELECT
        T1.competencia,
        T1.id_medico,
        T1.nu_cnpj AS cnpj_a,
        T1.dt_prescricao_inicial_medico AS dt_ini_a,
        T1.dt_prescricao_final_medico AS dt_fim_a,
        T1.sg_uf AS sg_uf_a,
        T1.nu_prescricoes_medico AS nu_prescricoes_a,
        T2.nu_cnpj AS cnpj_b,
        T2.dt_prescricao_inicial_medico AS dt_ini_b,
        T2.dt_prescricao_final_medico AS dt_fim_b,
        T2.sg_uf AS sg_uf_b,
        T2.nu_prescricoes_medico AS nu_prescricoes_b,
        CASE
            WHEN ABS(T1.latitude - T2.latitude) > 2.0
              OR ABS(T1.longitude - T2.longitude) > 2.0
            THEN temp_CGUSC.fp.fnCalcular_Distancia_KM(T1.latitude, T1.longitude, T2.latitude, T2.longitude)
            ELSE 0
        END AS distancia_km
    FROM #base_com_geo T1
    INNER JOIN #base_com_geo T2
        ON  T2.id_medico = T1.id_medico
        AND T1.nu_cnpj < T2.nu_cnpj
        AND T1.competencia = T2.competencia
),
ParesFiltrados AS (
    SELECT *
    FROM PairedWithDistance
    WHERE distancia_km > 400
),
ParesPriorizados AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY id_medico, competencia
            ORDER BY (nu_prescricoes_a + nu_prescricoes_b) DESC, distancia_km DESC
        ) AS rn
    FROM ParesFiltrados
),
TotaisPorMedico AS (
    SELECT id_medico, competencia, COUNT(*) AS total_pares
    FROM ParesPriorizados
    GROUP BY id_medico, competencia
)
SELECT
    P.id_medico,
    P.competencia,
    P.cnpj_a,
    CAST(P.sg_uf_a AS VARCHAR(2)) AS sg_uf_a,
    P.dt_ini_a,
    P.dt_fim_a,
    P.nu_prescricoes_a,
    P.cnpj_b,
    CAST(P.sg_uf_b AS VARCHAR(2)) AS sg_uf_b,
    P.dt_ini_b,
    P.dt_fim_b,
    P.nu_prescricoes_b,
    CAST(P.distancia_km AS DECIMAL(10,2)) AS distancia_km,
    T.total_pares
INTO temp_CGUSC.fp.alertas_crm_geografico
FROM ParesPriorizados P
INNER JOIN TotaisPorMedico T
    ON  T.id_medico = P.id_medico
    AND T.competencia = P.competencia
WHERE P.rn = 1;

CREATE CLUSTERED INDEX IDX_GeoAlerta
    ON temp_CGUSC.fp.alertas_crm_geografico(id_medico, competencia);

SET @dt_fim_etapa = GETDATE();
SELECT @nu_registros_etapa = COUNT(*) FROM temp_CGUSC.fp.alertas_crm_geografico;

UPDATE temp_CGUSC.fp.crm_detalhado_pos_global_etapa_log
SET dt_fim_etapa = @dt_fim_etapa,
    segundos_etapa = DATEDIFF(SECOND, @t1, @dt_fim_etapa),
    milissegundos_etapa = DATEDIFF(MILLISECOND, @t1, @dt_fim_etapa),
    nu_registros = @nu_registros_etapa,
    status = 'OK',
    observacao = 'alertas_crm_geografico criada.'
WHERE id_etapa_log = @id_etapa_log;

PRINT '   alertas_crm_geografico concluida em: ' + CONVERT(VARCHAR(20), @dt_fim_etapa - @t1, 114);


-- ============================================================================
-- PASSO 2: Motor de registro CFM
-- ============================================================================
PRINT '>> Passo 2: Criando temp_CGUSC.fp.alertas_crm_registro...';
SET @etapa = '2_ALERTAS_CRM_REGISTRO';
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
-- PASSO 3: Consolidador de flags
-- ============================================================================
PRINT '>> Passo 3: Criando temp_CGUSC.fp.alertas_crm...';
SET @etapa = '3_ALERTAS_CRM';
SET @t1 = GETDATE();
SET @id_etapa_log = NULL;

INSERT INTO temp_CGUSC.fp.crm_detalhado_pos_global_etapa_log
    (pipeline_versao, dt_data_inicio, dt_data_fim, etapa, dt_inicio_etapa, status, observacao)
VALUES
    (@pipeline_versao, @DataInicio, @DataFim, @etapa, @t1, 'PROCESSANDO', 'Criando alertas_crm.');

SET @id_etapa_log = CONVERT(BIGINT, SCOPE_IDENTITY());

;WITH base AS (
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
    SELECT S1.nu_cnpj, S1.id_medico, S1.competencia
    FROM temp_CGUSC.fp.crm_crms_em_surto S1
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
    FROM temp_CGUSC.fp.crm_crms_em_surto
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
-- PASSO 4: Tabela final de exportacao
-- ============================================================================
PRINT '>> Passo 4: Criando temp_CGUSC.fp.crm_export...';
SET @etapa = '4_CRM_EXPORT';
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
-- PASSO 5: Base temporaria para benchmarks
-- ============================================================================
PRINT '>> Passo 5: Criando #indicador_crm...';
SET @etapa = '5_INDICADOR_CRM_BASE';
SET @t1 = GETDATE();
SET @id_etapa_log = NULL;

INSERT INTO temp_CGUSC.fp.crm_detalhado_pos_global_etapa_log
    (pipeline_versao, dt_data_inicio, dt_data_fim, etapa, dt_inicio_etapa, status, observacao)
VALUES
    (@pipeline_versao, @DataInicio, @DataFim, @etapa, @t1, 'PROCESSANDO', 'Criando base temporaria #indicador_crm.');

SET @id_etapa_log = CONVERT(BIGINT, SCOPE_IDENTITY());

DROP TABLE IF EXISTS #indicador_crm;

;WITH
Totais AS (
    SELECT
        nu_cnpj AS cnpj,
        competencia,
        SUM(nu_prescricoes_medico) AS total_prescricoes,
        SUM(vl_autorizacoes_medico) AS total_valor,
        COUNT(DISTINCT id_medico) AS total_prescritores
    FROM temp_CGUSC.fp.dados_crm_detalhado
    GROUP BY nu_cnpj, competencia
),
Top5 AS (
    SELECT
        cnpj,
        competencia,
        MAX(CASE WHEN rk = 1 THEN id_medico END) AS id_top1,
        SUM(CASE WHEN rk = 1 THEN vl_total_prescricoes ELSE 0 END) AS vl_top1,
        SUM(CASE WHEN rk <= 5 THEN vl_total_prescricoes ELSE 0 END) AS vl_top5
    FROM (
        SELECT
            nu_cnpj AS cnpj,
            competencia,
            id_medico,
            vl_autorizacoes_medico AS vl_total_prescricoes,
            ROW_NUMBER() OVER (
                PARTITION BY nu_cnpj, competencia
                ORDER BY vl_autorizacoes_medico DESC
            ) AS rk
        FROM temp_CGUSC.fp.dados_crm_detalhado
    ) R
    WHERE rk <= 5
    GROUP BY cnpj, competencia
),
Anomalias AS (
    SELECT
        A.nu_cnpj AS cnpj,
        A.competencia,
        COUNT(CASE WHEN REG_INV.cnpj IS NOT NULL THEN 1 END) AS qtd_crm_invalido,
        COUNT(CASE WHEN REG_IRR.cnpj IS NOT NULL THEN 1 END) AS qtd_antes_registro
    FROM temp_CGUSC.fp.dados_crm_detalhado A
    LEFT JOIN temp_CGUSC.fp.alertas_crm_registro REG_INV
        ON  REG_INV.cnpj = A.nu_cnpj
        AND REG_INV.id_medico = A.id_medico
        AND REG_INV.competencia = A.competencia
        AND REG_INV.tipo_anomalia = 'INEXISTENTE'
    LEFT JOIN temp_CGUSC.fp.alertas_crm_registro REG_IRR
        ON  REG_IRR.cnpj = A.nu_cnpj
        AND REG_IRR.id_medico = A.id_medico
        AND REG_IRR.competencia = A.competencia
        AND REG_IRR.tipo_anomalia = 'IRREGULAR'
    GROUP BY A.nu_cnpj, A.competencia
),
HHI AS (
    SELECT
        E.nu_cnpj AS cnpj,
        E.competencia,
        SUM(POWER(
            CAST(E.vl_autorizacoes_medico AS DECIMAL(18,4)) /
            NULLIF(CAST(T.total_valor AS DECIMAL(18,4)), 0) * 100.0
        , 2)) AS indice_hhi
    FROM temp_CGUSC.fp.dados_crm_detalhado E
    INNER JOIN Totais T
        ON T.cnpj = E.nu_cnpj
       AND T.competencia = E.competencia
    GROUP BY E.nu_cnpj, E.competencia
),
Turistas AS (
    SELECT
        nu_cnpj AS cnpj,
        competencia,
        COUNT(DISTINCT id_medico) AS qtd_turistas
    FROM temp_CGUSC.fp.alertas_crm
    WHERE flag_geografico = 1
    GROUP BY nu_cnpj, competencia
)
SELECT
    I.cnpj,
    I.competencia,
    I.total_prescricoes AS qtd_prescricoes_mes,
    I.total_valor AS vl_total_prescricoes,
    I.total_prescritores AS qtd_prescritores,
    T.id_top1,
    ISNULL(T.vl_top1, 0) AS vl_top1,
    ISNULL(T.vl_top5, 0) AS vl_top5,
    ISNULL(H.indice_hhi, 0) AS indice_hhi,
    ISNULL(AN.qtd_crm_invalido, 0) AS qtd_crm_invalido,
    ISNULL(AN.qtd_antes_registro, 0) AS qtd_crm_antes_registro,
    ISNULL(TU.qtd_turistas, 0) AS qtd_prescritores_turistas
INTO #indicador_crm
FROM Totais I
LEFT JOIN Top5 T
    ON T.cnpj = I.cnpj
   AND T.competencia = I.competencia
LEFT JOIN HHI H
    ON H.cnpj = I.cnpj
   AND H.competencia = I.competencia
LEFT JOIN Anomalias AN
    ON AN.cnpj = I.cnpj
   AND AN.competencia = I.competencia
LEFT JOIN Turistas TU
    ON TU.cnpj = I.cnpj
   AND TU.competencia = I.competencia;

CREATE CLUSTERED INDEX IDX_IndCrm
    ON #indicador_crm(cnpj, competencia);

SET @dt_fim_etapa = GETDATE();
SELECT @nu_registros_etapa = COUNT(*) FROM #indicador_crm;

UPDATE temp_CGUSC.fp.crm_detalhado_pos_global_etapa_log
SET dt_fim_etapa = @dt_fim_etapa,
    segundos_etapa = DATEDIFF(SECOND, @t1, @dt_fim_etapa),
    milissegundos_etapa = DATEDIFF(MILLISECOND, @t1, @dt_fim_etapa),
    nu_registros = @nu_registros_etapa,
    status = 'OK',
    observacao = '#indicador_crm criada.'
WHERE id_etapa_log = @id_etapa_log;

PRINT '   #indicador_crm concluida em: ' + CONVERT(VARCHAR(20), @dt_fim_etapa - @t1, 114);


-- ============================================================================
-- PASSO 6: Benchmarks UF, regiao de saude e Brasil
-- ============================================================================
PRINT '>> Passo 6.A: Criando temp_CGUSC.fp.indicador_crm_bench_uf...';
SET @etapa = '6.A_BENCH_UF';
SET @t1 = GETDATE();
SET @id_etapa_log = NULL;

INSERT INTO temp_CGUSC.fp.crm_detalhado_pos_global_etapa_log
    (pipeline_versao, dt_data_inicio, dt_data_fim, etapa, dt_inicio_etapa, status, observacao)
VALUES
    (@pipeline_versao, @DataInicio, @DataFim, @etapa, @t1, 'PROCESSANDO', 'Criando indicador_crm_bench_uf.');

SET @id_etapa_log = CONVERT(BIGINT, SCOPE_IDENTITY());

;WITH CTE AS (
    SELECT
        I.competencia,
        F.uf,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.indice_hhi, 0))
            OVER (PARTITION BY F.uf, I.competencia) AS mediana_hhi_uf,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.vl_top1 / NULLIF(I.vl_total_prescricoes, 0) * 100, 0))
            OVER (PARTITION BY F.uf, I.competencia) AS mediana_concentracao_top1_uf,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.vl_top5 / NULLIF(I.vl_total_prescricoes, 0) * 100, 0))
            OVER (PARTITION BY F.uf, I.competencia) AS mediana_concentracao_top5_uf,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(CAST(
            CASE
                WHEN I.qtd_prescritores > 0
                THEN I.qtd_crm_invalido * 100.0 / I.qtd_prescritores
                ELSE 0
            END AS DECIMAL(18,4)), 0))
            OVER (PARTITION BY F.uf, I.competencia) AS mediana_pct_crm_invalido_uf,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.qtd_prescritores_turistas, 0))
            OVER (PARTITION BY F.uf, I.competencia) AS mediana_turistas_uf
    FROM #indicador_crm I
    INNER JOIN temp_CGUSC.fp.dados_farmacia F
        ON F.cnpj = I.cnpj
)
SELECT *
INTO temp_CGUSC.fp.indicador_crm_bench_uf
FROM CTE;

CREATE CLUSTERED INDEX IDX_BenchUF
    ON temp_CGUSC.fp.indicador_crm_bench_uf(uf, competencia);

SET @dt_fim_etapa = GETDATE();
SELECT @nu_registros_etapa = COUNT(*) FROM temp_CGUSC.fp.indicador_crm_bench_uf;

UPDATE temp_CGUSC.fp.crm_detalhado_pos_global_etapa_log
SET dt_fim_etapa = @dt_fim_etapa,
    segundos_etapa = DATEDIFF(SECOND, @t1, @dt_fim_etapa),
    milissegundos_etapa = DATEDIFF(MILLISECOND, @t1, @dt_fim_etapa),
    nu_registros = @nu_registros_etapa,
    status = 'OK',
    observacao = 'indicador_crm_bench_uf criada.'
WHERE id_etapa_log = @id_etapa_log;

PRINT '   indicador_crm_bench_uf concluida em: ' + CONVERT(VARCHAR(20), @dt_fim_etapa - @t1, 114);

PRINT '>> Passo 6.B: Criando temp_CGUSC.fp.indicador_crm_bench_regiao...';
SET @etapa = '6.B_BENCH_REGIAO';
SET @t1 = GETDATE();
SET @id_etapa_log = NULL;

INSERT INTO temp_CGUSC.fp.crm_detalhado_pos_global_etapa_log
    (pipeline_versao, dt_data_inicio, dt_data_fim, etapa, dt_inicio_etapa, status, observacao)
VALUES
    (@pipeline_versao, @DataInicio, @DataFim, @etapa, @t1, 'PROCESSANDO', 'Criando indicador_crm_bench_regiao.');

SET @id_etapa_log = CONVERT(BIGINT, SCOPE_IDENTITY());

;WITH CTE AS (
    SELECT DISTINCT
        F.id_regiao_saude,
        I.competencia,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.indice_hhi, 0))
            OVER (PARTITION BY F.id_regiao_saude, I.competencia) AS mediana_hhi_reg,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.vl_top1 / NULLIF(I.vl_total_prescricoes, 0) * 100, 0))
            OVER (PARTITION BY F.id_regiao_saude, I.competencia) AS mediana_concentracao_reg,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.vl_top5 / NULLIF(I.vl_total_prescricoes, 0) * 100, 0))
            OVER (PARTITION BY F.id_regiao_saude, I.competencia) AS mediana_concentracao_top5_reg,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(CAST(
            CASE
                WHEN I.qtd_prescritores > 0
                THEN I.qtd_crm_invalido * 100.0 / I.qtd_prescritores
                ELSE 0
            END AS DECIMAL(18,4)), 0))
            OVER (PARTITION BY F.id_regiao_saude, I.competencia) AS mediana_crm_invalido_reg,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.qtd_prescritores_turistas, 0))
            OVER (PARTITION BY F.id_regiao_saude, I.competencia) AS mediana_turistas_reg
    FROM temp_CGUSC.fp.dados_farmacia F
    LEFT JOIN #indicador_crm I
        ON I.cnpj = F.cnpj
    WHERE F.id_regiao_saude IS NOT NULL
      AND I.competencia IS NOT NULL
)
SELECT *
INTO temp_CGUSC.fp.indicador_crm_bench_regiao
FROM CTE;

CREATE CLUSTERED INDEX IDX_BenchReg
    ON temp_CGUSC.fp.indicador_crm_bench_regiao(id_regiao_saude, competencia);

SET @dt_fim_etapa = GETDATE();
SELECT @nu_registros_etapa = COUNT(*) FROM temp_CGUSC.fp.indicador_crm_bench_regiao;

UPDATE temp_CGUSC.fp.crm_detalhado_pos_global_etapa_log
SET dt_fim_etapa = @dt_fim_etapa,
    segundos_etapa = DATEDIFF(SECOND, @t1, @dt_fim_etapa),
    milissegundos_etapa = DATEDIFF(MILLISECOND, @t1, @dt_fim_etapa),
    nu_registros = @nu_registros_etapa,
    status = 'OK',
    observacao = 'indicador_crm_bench_regiao criada.'
WHERE id_etapa_log = @id_etapa_log;

PRINT '   indicador_crm_bench_regiao concluida em: ' + CONVERT(VARCHAR(20), @dt_fim_etapa - @t1, 114);

PRINT '>> Passo 6.C: Criando temp_CGUSC.fp.indicador_crm_bench_br...';
SET @etapa = '6.C_BENCH_BR';
SET @t1 = GETDATE();
SET @id_etapa_log = NULL;

INSERT INTO temp_CGUSC.fp.crm_detalhado_pos_global_etapa_log
    (pipeline_versao, dt_data_inicio, dt_data_fim, etapa, dt_inicio_etapa, status, observacao)
VALUES
    (@pipeline_versao, @DataInicio, @DataFim, @etapa, @t1, 'PROCESSANDO', 'Criando indicador_crm_bench_br.');

SET @id_etapa_log = CONVERT(BIGINT, SCOPE_IDENTITY());

;WITH CTE AS (
    SELECT DISTINCT
        I.competencia,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.vl_top1 / NULLIF(I.vl_total_prescricoes, 0) * 100, 0))
            OVER (PARTITION BY I.competencia) AS mediana_concentracao_br,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.vl_top5 / NULLIF(I.vl_total_prescricoes, 0) * 100, 0))
            OVER (PARTITION BY I.competencia) AS mediana_concentracao_top5_br,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.indice_hhi, 0))
            OVER (PARTITION BY I.competencia) AS mediana_hhi_br,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(CAST(
            CASE
                WHEN I.qtd_prescritores > 0
                THEN I.qtd_crm_invalido * 100.0 / I.qtd_prescritores
                ELSE 0
            END AS DECIMAL(18,4)), 0))
            OVER (PARTITION BY I.competencia) AS mediana_pct_crm_invalido_br,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.qtd_prescritores_turistas, 0))
            OVER (PARTITION BY I.competencia) AS mediana_turistas_br
    FROM #indicador_crm I
)
SELECT *
INTO temp_CGUSC.fp.indicador_crm_bench_br
FROM CTE;

CREATE CLUSTERED INDEX IDX_BenchBR
    ON temp_CGUSC.fp.indicador_crm_bench_br(competencia);

SET @dt_fim_etapa = GETDATE();
SELECT @nu_registros_etapa = COUNT(*) FROM temp_CGUSC.fp.indicador_crm_bench_br;

UPDATE temp_CGUSC.fp.crm_detalhado_pos_global_etapa_log
SET dt_fim_etapa = @dt_fim_etapa,
    segundos_etapa = DATEDIFF(SECOND, @t1, @dt_fim_etapa),
    milissegundos_etapa = DATEDIFF(MILLISECOND, @t1, @dt_fim_etapa),
    nu_registros = @nu_registros_etapa,
    status = 'OK',
    observacao = 'indicador_crm_bench_br criada.'
WHERE id_etapa_log = @id_etapa_log;

PRINT '   indicador_crm_bench_br concluida em: ' + CONVERT(VARCHAR(20), @dt_fim_etapa - @t1, 114);


-- ============================================================================
-- PASSO 7: Matriz HHI
-- ============================================================================
PRINT '>> Passo 7: Criando temp_CGUSC.fp.indicador_crm_hhi...';
SET @etapa = '7_INDICADOR_CRM_HHI';
SET @t1 = GETDATE();
SET @id_etapa_log = NULL;

INSERT INTO temp_CGUSC.fp.crm_detalhado_pos_global_etapa_log
    (pipeline_versao, dt_data_inicio, dt_data_fim, etapa, dt_inicio_etapa, status, observacao)
VALUES
    (@pipeline_versao, @DataInicio, @DataFim, @etapa, @t1, 'PROCESSANDO', 'Criando indicador_crm_hhi.');

SET @id_etapa_log = CONVERT(BIGINT, SCOPE_IDENTITY());

;WITH HHI_por_cnpj AS (
    SELECT
        I.cnpj,
        AVG(I.indice_hhi) AS indice_hhi,
        F.id_regiao_saude,
        CAST(F.uf AS VARCHAR(2)) AS uf
    FROM #indicador_crm I
    INNER JOIN temp_CGUSC.fp.dados_farmacia F
        ON F.cnpj = I.cnpj
    GROUP BY I.cnpj, F.id_regiao_saude, F.uf
),
Bench AS (
    SELECT
        uf,
        AVG(mediana_hhi_uf) AS mediana_hhi_uf
    FROM temp_CGUSC.fp.indicador_crm_bench_uf
    GROUP BY uf
),
BenchReg AS (
    SELECT
        id_regiao_saude,
        AVG(mediana_hhi_reg) AS mediana_hhi_reg
    FROM temp_CGUSC.fp.indicador_crm_bench_regiao
    GROUP BY id_regiao_saude
),
BenchBR AS (
    SELECT AVG(mediana_hhi_br) AS mediana_hhi_br
    FROM temp_CGUSC.fp.indicador_crm_bench_br
)
SELECT
    H.cnpj,
    CAST(H.indice_hhi AS DECIMAL(18,4)) AS indice_hhi,
    ISNULL(CAST(BU.mediana_hhi_uf AS DECIMAL(18,4)), 0) AS estado_mediana,
    ISNULL(CAST(BR.mediana_hhi_br AS DECIMAL(18,4)), 0) AS pais_mediana,
    ISNULL(CAST(BR2.mediana_hhi_reg AS DECIMAL(18,4)), 0) AS regiao_saude_mediana,
    CAST(CASE
        WHEN BU.mediana_hhi_uf > 0
        THEN (H.indice_hhi + 0.01) / (BU.mediana_hhi_uf + 0.01)
        ELSE 0
    END AS DECIMAL(18,4)) AS risco_relativo_uf_mediana,
    CAST(CASE
        WHEN BR.mediana_hhi_br > 0
        THEN (H.indice_hhi + 0.01) / (BR.mediana_hhi_br + 0.01)
        ELSE 0
    END AS DECIMAL(18,4)) AS risco_relativo_br_mediana,
    CAST(CASE
        WHEN BR2.mediana_hhi_reg > 0
        THEN (H.indice_hhi + 0.01) / (BR2.mediana_hhi_reg + 0.01)
        ELSE 0
    END AS DECIMAL(18,4)) AS risco_relativo_reg_mediana
INTO temp_CGUSC.fp.indicador_crm_hhi
FROM HHI_por_cnpj H
LEFT JOIN Bench BU
    ON BU.uf = H.uf
LEFT JOIN BenchReg BR2
    ON BR2.id_regiao_saude = H.id_regiao_saude
CROSS JOIN BenchBR BR;

CREATE CLUSTERED INDEX IDX_CrmHHI
    ON temp_CGUSC.fp.indicador_crm_hhi(cnpj);

SET @dt_fim_etapa = GETDATE();
SELECT @nu_registros_etapa = COUNT(*) FROM temp_CGUSC.fp.indicador_crm_hhi;

UPDATE temp_CGUSC.fp.crm_detalhado_pos_global_etapa_log
SET dt_fim_etapa = @dt_fim_etapa,
    segundos_etapa = DATEDIFF(SECOND, @t1, @dt_fim_etapa),
    milissegundos_etapa = DATEDIFF(MILLISECOND, @t1, @dt_fim_etapa),
    nu_registros = @nu_registros_etapa,
    status = 'OK',
    observacao = 'indicador_crm_hhi criada.'
WHERE id_etapa_log = @id_etapa_log;

SET @id_etapa_log = NULL;

PRINT '   indicador_crm_hhi concluida em: ' + CONVERT(VARCHAR(20), @dt_fim_etapa - @t1, 114);


-- ============================================================================
-- FINALIZACAO E RESULTADOS
-- ============================================================================
UPDATE temp_CGUSC.fp.crm_detalhado_pos_global_metadata
SET nu_alertas_crm = (SELECT COUNT(*) FROM temp_CGUSC.fp.alertas_crm),
    nu_crm_export = (SELECT COUNT(*) FROM temp_CGUSC.fp.crm_export),
    nu_bench_uf = (SELECT COUNT(*) FROM temp_CGUSC.fp.indicador_crm_bench_uf),
    nu_bench_regiao = (SELECT COUNT(*) FROM temp_CGUSC.fp.indicador_crm_bench_regiao),
    nu_bench_br = (SELECT COUNT(*) FROM temp_CGUSC.fp.indicador_crm_bench_br),
    nu_hhi = (SELECT COUNT(*) FROM temp_CGUSC.fp.indicador_crm_hhi),
    status = 'OK',
    dt_atualizacao = GETDATE(),
    observacao = 'Pos-global finalizado com sucesso.'
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
    nu_alertas_crm,
    nu_crm_export,
    nu_bench_uf,
    nu_bench_regiao,
    nu_bench_br,
    nu_hhi,
    status,
    dt_criacao,
    dt_atualizacao,
    observacao
FROM temp_CGUSC.fp.crm_detalhado_pos_global_metadata;

SELECT TOP 30
    etapa,
    dt_inicio_etapa,
    dt_fim_etapa,
    segundos_etapa,
    milissegundos_etapa,
    nu_registros,
    status,
    observacao,
    mensagem_erro
FROM temp_CGUSC.fp.crm_detalhado_pos_global_etapa_log
WHERE pipeline_versao = @pipeline_versao
  AND dt_data_inicio = @DataInicio
  AND dt_data_fim = @DataFim
ORDER BY id_etapa_log DESC;

SELECT
    (SELECT COUNT(*) FROM temp_CGUSC.fp.alertas_crm_geografico) AS qtd_alertas_crm_geografico,
    (SELECT COUNT(*) FROM temp_CGUSC.fp.alertas_crm_registro) AS qtd_alertas_crm_registro,
    (SELECT COUNT(*) FROM temp_CGUSC.fp.alertas_crm) AS qtd_alertas_crm,
    (SELECT COUNT(*) FROM temp_CGUSC.fp.crm_export) AS qtd_crm_export,
    (SELECT COUNT(*) FROM temp_CGUSC.fp.indicador_crm_bench_uf) AS qtd_bench_uf,
    (SELECT COUNT(*) FROM temp_CGUSC.fp.indicador_crm_bench_regiao) AS qtd_bench_regiao,
    (SELECT COUNT(*) FROM temp_CGUSC.fp.indicador_crm_bench_br) AS qtd_bench_br,
    (SELECT COUNT(*) FROM temp_CGUSC.fp.indicador_crm_hhi) AS qtd_hhi;

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

    IF OBJECT_ID('temp_CGUSC.fp.crm_detalhado_pos_global_metadata') IS NOT NULL
    BEGIN
        UPDATE temp_CGUSC.fp.crm_detalhado_pos_global_metadata
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

    PRINT '   ERRO no pos-global CRM.';
    PRINT '   ' + @mensagem_erro;

    THROW;
END CATCH;
