USE [temp_CGUSC]
GO

-- ============================================================================
-- INDICADOR DE CRMs IRREGULARES
-- ============================================================================
-- OBJETIVO: Identificar farmacias com alto volume de prescricoes vinculadas a
--           CRMs irregulares em cada ano.
--
-- METRICA PRINCIPAL:
--   O indicador deve ser calculado por periodo a partir dos componentes:
--   valor_crms_irregulares / valor_total_auditado.
--
-- CRITERIOS DE IRREGULARIDADE:
--   1. CRM/UF nao localizado no CFM.
--   2. CRM/UF utilizado antes da data de inscricao no CFM.
--
-- REGRA METODOLOGICA:
--   Quando a primeira prescricao anual do CRM na farmacia ocorre antes da data
--   de inscricao no CFM, todo o valor anual daquele CRM/farmacia e considerado
--   irregular.
--
-- FONTE DE DADOS:
--   As fontes abaixo sao mantidas porque possuem os campos CRM e UF do CRM,
--   ausentes na movimentacao consolidada usada por outros indicadores.
--   - db_FarmaciaPopular.dbo.Relatorio_movimentacaoFP
--   - db_FarmaciaPopular.carga_2024.relatorio_movimentacaoFP_2021_2024
--   - temp_CFM.dbo.medicos_jul_2025_mod
--   - temp_CGUSC.fp.medicamentos_patologia (universo de medicamentos auditados)
--   - temp_CGUSC.fp.dados_farmacia (id_cnpj e contexto territorial)
-- ============================================================================

-- ============================================================================
-- LIMPEZA PREVIA DE TABELAS
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crms_irregulares;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crms_irregulares_mun;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crms_irregulares_uf;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crms_irregulares_regiao;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crms_irregulares_br;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crms_irregulares_detalhado;
GO

-- ============================================================================
-- DEFINICAO DE VARIAVEIS
-- ============================================================================
DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim    DATE = '2024-12-10';


-- ============================================================================
-- PASSO 0: DIMENSOES E FONTES OBRIGATORIAS
-- ============================================================================
IF OBJECT_ID('temp_CFM.dbo.medicos_jul_2025_mod', 'U') IS NULL
BEGIN
    RAISERROR('Tabela temp_CFM.dbo.medicos_jul_2025_mod nao encontrada.', 16, 1);
    RETURN;
END;

IF COL_LENGTH('temp_CFM.dbo.medicos_jul_2025_mod', 'NU_CRM') IS NULL
   OR COL_LENGTH('temp_CFM.dbo.medicos_jul_2025_mod', 'SG_uf') IS NULL
   OR COL_LENGTH('temp_CFM.dbo.medicos_jul_2025_mod', 'DT_INSCRICAO') IS NULL
BEGIN
    RAISERROR('Tabela temp_CFM.dbo.medicos_jul_2025_mod sem colunas obrigatorias NU_CRM/SG_uf/DT_INSCRICAO.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('temp_CGUSC.fp.medicamentos_patologia', 'U') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.medicamentos_patologia nao encontrada.', 16, 1);
    RETURN;
END;

IF COL_LENGTH('temp_CGUSC.fp.medicamentos_patologia', 'codigo_barra') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.medicamentos_patologia sem coluna obrigatoria codigo_barra.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('temp_CGUSC.fp.dados_farmacia', 'U') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.dados_farmacia nao encontrada.', 16, 1);
    RETURN;
END;

IF COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'id') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'cnpj') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'municipio') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'uf') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'id_regiao_saude') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.dados_farmacia sem colunas obrigatorias id/cnpj/municipio/uf/id_regiao_saude.', 16, 1);
    RETURN;
END;

IF EXISTS (
    SELECT 1
    FROM temp_CGUSC.fp.dados_farmacia
    GROUP BY id
    HAVING COUNT_BIG(*) > 1
)
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.dados_farmacia possui ids duplicados.', 16, 1);
    RETURN;
END;

IF EXISTS (
    SELECT 1
    FROM temp_CGUSC.fp.dados_farmacia
    GROUP BY cnpj
    HAVING COUNT_BIG(*) > 1
)
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.dados_farmacia possui CNPJs duplicados.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('db_FarmaciaPopular.dbo.Relatorio_movimentacaoFP', 'U') IS NULL
BEGIN
    RAISERROR('Tabela db_FarmaciaPopular.dbo.Relatorio_movimentacaoFP nao encontrada.', 16, 1);
    RETURN;
END;

IF COL_LENGTH('db_FarmaciaPopular.dbo.Relatorio_movimentacaoFP', 'cnpj') IS NULL
   OR COL_LENGTH('db_FarmaciaPopular.dbo.Relatorio_movimentacaoFP', 'crm') IS NULL
   OR COL_LENGTH('db_FarmaciaPopular.dbo.Relatorio_movimentacaoFP', 'crm_uf') IS NULL
   OR COL_LENGTH('db_FarmaciaPopular.dbo.Relatorio_movimentacaoFP', 'num_autorizacao') IS NULL
   OR COL_LENGTH('db_FarmaciaPopular.dbo.Relatorio_movimentacaoFP', 'valor_pago') IS NULL
   OR COL_LENGTH('db_FarmaciaPopular.dbo.Relatorio_movimentacaoFP', 'data_hora') IS NULL
   OR COL_LENGTH('db_FarmaciaPopular.dbo.Relatorio_movimentacaoFP', 'codigo_barra') IS NULL
BEGIN
    RAISERROR('Tabela db_FarmaciaPopular.dbo.Relatorio_movimentacaoFP sem colunas obrigatorias para CRMs irregulares.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('db_FarmaciaPopular.carga_2024.relatorio_movimentacaoFP_2021_2024', 'U') IS NULL
BEGIN
    RAISERROR('Tabela db_FarmaciaPopular.carga_2024.relatorio_movimentacaoFP_2021_2024 nao encontrada.', 16, 1);
    RETURN;
END;

IF COL_LENGTH('db_FarmaciaPopular.carga_2024.relatorio_movimentacaoFP_2021_2024', 'cnpj') IS NULL
   OR COL_LENGTH('db_FarmaciaPopular.carga_2024.relatorio_movimentacaoFP_2021_2024', 'crm') IS NULL
   OR COL_LENGTH('db_FarmaciaPopular.carga_2024.relatorio_movimentacaoFP_2021_2024', 'crm_uf') IS NULL
   OR COL_LENGTH('db_FarmaciaPopular.carga_2024.relatorio_movimentacaoFP_2021_2024', 'num_autorizacao') IS NULL
   OR COL_LENGTH('db_FarmaciaPopular.carga_2024.relatorio_movimentacaoFP_2021_2024', 'valor_pago') IS NULL
   OR COL_LENGTH('db_FarmaciaPopular.carga_2024.relatorio_movimentacaoFP_2021_2024', 'data_hora') IS NULL
   OR COL_LENGTH('db_FarmaciaPopular.carga_2024.relatorio_movimentacaoFP_2021_2024', 'codigo_barra') IS NULL
BEGIN
    RAISERROR('Tabela db_FarmaciaPopular.carga_2024.relatorio_movimentacaoFP_2021_2024 sem colunas obrigatorias para CRMs irregulares.', 16, 1);
    RETURN;
END;

DROP TABLE IF EXISTS #farmacias_dim;

SELECT
    CAST(F.id AS INT) AS id_cnpj,
    CAST(F.cnpj AS VARCHAR(14)) AS cnpj,
    CAST(F.municipio AS VARCHAR(255)) AS municipio,
    CAST(UPPER(LTRIM(RTRIM(F.uf))) AS VARCHAR(2)) AS uf,
    CAST(F.id_regiao_saude AS INT) AS id_regiao_saude
INTO #farmacias_dim
FROM temp_CGUSC.fp.dados_farmacia AS F;

IF EXISTS (
    SELECT 1
    FROM #farmacias_dim
    WHERE id_cnpj IS NULL
       OR NULLIF(LTRIM(RTRIM(cnpj)), '') IS NULL
       OR NULLIF(LTRIM(RTRIM(municipio)), '') IS NULL
       OR NULLIF(LTRIM(RTRIM(uf)), '') IS NULL
       OR id_regiao_saude IS NULL
)
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.dados_farmacia possui valores obrigatorios nulos para contexto territorial.', 16, 1);
    RETURN;
END;

CREATE UNIQUE CLUSTERED INDEX IDX_farmacias_dim_cnpj
ON #farmacias_dim(cnpj);

CREATE UNIQUE NONCLUSTERED INDEX IDX_farmacias_dim_id
ON #farmacias_dim(id_cnpj);

DROP TABLE IF EXISTS #medicamentos_patologia_gtin;

SELECT DISTINCT
    C.codigo_barra
INTO #medicamentos_patologia_gtin
FROM temp_CGUSC.fp.medicamentos_patologia C
WHERE C.codigo_barra IS NOT NULL;

IF NOT EXISTS (SELECT 1 FROM #medicamentos_patologia_gtin)
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.medicamentos_patologia sem codigo_barra valido.', 16, 1);
    RETURN;
END;

CREATE UNIQUE CLUSTERED INDEX IDX_medicamentos_patologia_gtin
ON #medicamentos_patologia_gtin(codigo_barra);


-- ============================================================================
-- PASSO 1: BASE DO CFM VALIDADA
-- ============================================================================
IF EXISTS (
    SELECT 1
    FROM temp_CFM.dbo.medicos_jul_2025_mod
    WHERE NU_CRM IS NOT NULL
      AND NULLIF(LTRIM(RTRIM(CAST(SG_uf AS VARCHAR(10)))), '') IS NOT NULL
      -- Excecao operacional autorizada: CRM/UF existente no CFM sem
      -- DT_INSCRICAO permanece localizado, mas nao gera alerta por uso
      -- antes da inscricao. Data preenchida e invalida continua bloqueante.
      AND DT_INSCRICAO IS NOT NULL
      AND TRY_CONVERT(DATE, DT_INSCRICAO, 103) IS NULL
)
BEGIN
    RAISERROR('Tabela temp_CFM.dbo.medicos_jul_2025_mod possui DT_INSCRICAO preenchida e invalida para CRM/UF valido.', 16, 1);
    RETURN;
END;

DROP TABLE IF EXISTS #CFM_Normalizado;

SELECT
    CAST(LTRIM(RTRIM(CAST(NU_CRM AS VARCHAR(25)))) AS VARCHAR(25)) AS NU_CRM,
    CAST(UPPER(LTRIM(RTRIM(CAST(SG_uf AS VARCHAR(10))))) AS VARCHAR(10)) AS SG_uf,
    TRY_CONVERT(DATE, DT_INSCRICAO, 103) AS dt_inscricao_convertida
INTO #CFM_Normalizado
FROM temp_CFM.dbo.medicos_jul_2025_mod
WHERE NU_CRM IS NOT NULL
  AND NULLIF(LTRIM(RTRIM(CAST(SG_uf AS VARCHAR(10)))), '') IS NOT NULL;

IF EXISTS (
    SELECT 1
    FROM #CFM_Normalizado
    WHERE NULLIF(LTRIM(RTRIM(NU_CRM)), '') IS NULL
       OR LEN(SG_uf) <> 2
)
BEGIN
    RAISERROR('Tabela temp_CFM.dbo.medicos_jul_2025_mod possui CRM/UF invalido apos normalizacao.', 16, 1);
    RETURN;
END;

IF EXISTS (
    SELECT 1
    FROM #CFM_Normalizado
    GROUP BY NU_CRM, SG_uf
    HAVING COUNT(DISTINCT dt_inscricao_convertida) > 1
)
BEGIN
    RAISERROR('Tabela temp_CFM.dbo.medicos_jul_2025_mod possui datas de inscricao conflitantes para o mesmo CRM/UF.', 16, 1);
    RETURN;
END;

DROP TABLE IF EXISTS #CFM_Base;

SELECT
    NU_CRM,
    CAST(SG_uf AS VARCHAR(2)) AS SG_uf,
    MIN(dt_inscricao_convertida) AS dt_inscricao_convertida
INTO #CFM_Base
FROM #CFM_Normalizado
GROUP BY
    NU_CRM,
    SG_uf;

CREATE UNIQUE CLUSTERED INDEX IDX_CFM_CRM_uf
ON #CFM_Base(NU_CRM, SG_uf);

DROP TABLE IF EXISTS #CFM_Normalizado;


-- ============================================================================
-- PASSO 2: MOVIMENTACAO COM CRM NORMALIZADO
-- ============================================================================
DROP TABLE IF EXISTS #MovimentacaoCRM;

SELECT
    CAST(cnpj AS VARCHAR(14)) AS cnpj,
    CAST(LTRIM(RTRIM(CAST(crm AS VARCHAR(25)))) AS VARCHAR(25)) AS nu_crm,
    CAST(UPPER(LTRIM(RTRIM(CAST(crm_uf AS VARCHAR(10))))) AS VARCHAR(10)) AS sg_uf_crm,
    num_autorizacao,
    CAST(valor_pago AS DECIMAL(19,2)) AS valor_pago,
    data_hora,
    codigo_barra
INTO #MovimentacaoCRM
FROM (
    SELECT
        cnpj,
        crm,
        crm_uf,
        num_autorizacao,
        valor_pago,
        data_hora,
        codigo_barra
    FROM db_FarmaciaPopular.dbo.Relatorio_movimentacaoFP
    WHERE data_hora >= @DataInicio
      AND data_hora < DATEADD(DAY, 1, @DataFim)
      AND crm IS NOT NULL
      AND crm_uf IS NOT NULL
      AND crm > 0
      AND num_autorizacao IS NOT NULL
      AND valor_pago IS NOT NULL
      AND valor_pago >= 0
      AND codigo_barra IS NOT NULL

    UNION ALL

    SELECT
        cnpj,
        crm,
        crm_uf,
        num_autorizacao,
        valor_pago,
        data_hora,
        codigo_barra
    FROM db_FarmaciaPopular.carga_2024.relatorio_movimentacaoFP_2021_2024
    WHERE data_hora >= @DataInicio
      AND data_hora < DATEADD(DAY, 1, @DataFim)
      AND crm IS NOT NULL
      AND crm_uf IS NOT NULL
      AND crm > 0
      AND num_autorizacao IS NOT NULL
      AND valor_pago IS NOT NULL
      AND valor_pago >= 0
      AND codigo_barra IS NOT NULL
) U
WHERE NULLIF(LTRIM(RTRIM(CAST(crm AS VARCHAR(25)))), '') IS NOT NULL
  AND NULLIF(LTRIM(RTRIM(CAST(crm_uf AS VARCHAR(10)))), '') IS NOT NULL
  AND UPPER(LTRIM(RTRIM(CAST(crm_uf AS VARCHAR(10))))) <> 'BR';

IF EXISTS (
    SELECT 1
    FROM #MovimentacaoCRM
    WHERE NULLIF(LTRIM(RTRIM(cnpj)), '') IS NULL
       OR NULLIF(LTRIM(RTRIM(nu_crm)), '') IS NULL
       OR LEN(sg_uf_crm) <> 2
       OR num_autorizacao IS NULL
       OR valor_pago IS NULL
       OR data_hora IS NULL
       OR codigo_barra IS NULL
)
BEGIN
    RAISERROR('Movimentacao de CRM possui campos obrigatorios invalidos apos normalizacao.', 16, 1);
    RETURN;
END;

CREATE CLUSTERED INDEX IDX_MovimentacaoCRM_CNPJ
ON #MovimentacaoCRM(cnpj, data_hora);

CREATE NONCLUSTERED INDEX IDX_MovimentacaoCRM_Gtin
ON #MovimentacaoCRM(codigo_barra);


-- ============================================================================
-- PASSO 3: BASE DE PRESCRITORES POR FARMACIA/ANO
-- ============================================================================
DROP TABLE IF EXISTS #CRMsPorFarmaciaAno;

SELECT
    F.id_cnpj,
    CAST(YEAR(U.data_hora) AS SMALLINT) AS ano_base,
    CONCAT(U.nu_crm, '/', U.sg_uf_crm) AS id_medico,
    U.nu_crm,
    U.sg_uf_crm,
    CAST(COUNT(DISTINCT U.num_autorizacao) AS INT) AS total_prescricoes,
    CAST(SUM(U.valor_pago) AS DECIMAL(19,2)) AS valor_total_prescricoes,
    CAST(MIN(U.data_hora) AS DATE) AS dt_primeira_prescricao,
    CAST(CASE WHEN CFM.NU_CRM IS NULL THEN 1 ELSE 0 END AS TINYINT) AS flag_nao_localizado,
    CAST(
        CASE
            WHEN CFM.dt_inscricao_convertida IS NOT NULL
             AND CAST(MIN(U.data_hora) AS DATE) < CFM.dt_inscricao_convertida
                THEN 1
            ELSE 0
        END AS TINYINT
    ) AS flag_antes_registro
INTO #CRMsPorFarmaciaAno
FROM #MovimentacaoCRM U
INNER JOIN #farmacias_dim F
    ON F.cnpj = U.cnpj
INNER JOIN #medicamentos_patologia_gtin C
    ON C.codigo_barra = U.codigo_barra
LEFT JOIN #CFM_Base CFM
    ON CFM.NU_CRM = U.nu_crm
   AND CFM.SG_uf = U.sg_uf_crm
GROUP BY
    F.id_cnpj,
    YEAR(U.data_hora),
    U.nu_crm,
    U.sg_uf_crm,
    CFM.NU_CRM,
    CFM.dt_inscricao_convertida
HAVING SUM(U.valor_pago) > 0;

IF NOT EXISTS (SELECT 1 FROM #CRMsPorFarmaciaAno)
BEGIN
    RAISERROR('Nao ha prescricoes com CRM valido para calcular o indicador de CRMs irregulares.', 16, 1);
    RETURN;
END;

CREATE CLUSTERED INDEX IDX_CRMFarmAno_CNPJ
ON #CRMsPorFarmaciaAno(id_cnpj, ano_base);

DROP TABLE IF EXISTS #CFM_Base;
DROP TABLE IF EXISTS #MovimentacaoCRM;
DROP TABLE IF EXISTS #medicamentos_patologia_gtin;


-- ============================================================================
-- PASSO 4: CALCULO BASE POR FARMACIA/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crms_irregulares;

SELECT
    id_cnpj,
    ano_base,
    CAST(COUNT(*) AS INT) AS total_prescritores,
    CAST(SUM(total_prescricoes) AS INT) AS total_prescricoes,
    CAST(SUM(valor_total_prescricoes) AS DECIMAL(19,2)) AS valor_total_auditado,
    CAST(SUM(flag_nao_localizado) AS INT) AS qtd_crms_nao_localizados,
    CAST(
        SUM(
            CASE
                WHEN flag_nao_localizado = 1 THEN valor_total_prescricoes
                ELSE CAST(0 AS DECIMAL(19,2))
            END
        ) AS DECIMAL(19,2)
    ) AS valor_crms_nao_localizados,
    CAST(SUM(flag_antes_registro) AS INT) AS qtd_crms_antes_registro,
    CAST(
        SUM(
            CASE
                WHEN flag_antes_registro = 1 THEN valor_total_prescricoes
                ELSE CAST(0 AS DECIMAL(19,2))
            END
        ) AS DECIMAL(19,2)
    ) AS valor_crms_antes_registro,
    CAST(
        SUM(
            CASE
                WHEN flag_nao_localizado = 1 OR flag_antes_registro = 1 THEN 1
                ELSE 0
            END
        ) AS INT
    ) AS qtd_crms_irregulares,
    CAST(
        SUM(
            CASE
                WHEN flag_nao_localizado = 1 OR flag_antes_registro = 1 THEN valor_total_prescricoes
                ELSE CAST(0 AS DECIMAL(19,2))
            END
        ) AS DECIMAL(19,2)
    ) AS valor_crms_irregulares
INTO temp_CGUSC.fp.indicador_crms_irregulares
FROM #CRMsPorFarmaciaAno
GROUP BY
    id_cnpj,
    ano_base
HAVING SUM(valor_total_prescricoes) > 0;

CREATE UNIQUE CLUSTERED INDEX IDX_IndIrreg_CNPJ_Ano
ON temp_CGUSC.fp.indicador_crms_irregulares(id_cnpj, ano_base);

DROP TABLE IF EXISTS #CRMsPorFarmaciaAno;


-- ============================================================================
-- PASSO 5: TABELA CONSOLIDADA FINAL POR CNPJ/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crms_irregulares_detalhado;

SELECT
    I.id_cnpj,
    I.ano_base,
    I.total_prescritores,
    I.total_prescricoes,
    CAST(I.valor_total_auditado AS DECIMAL(19,2)) AS valor_total_auditado,
    I.qtd_crms_nao_localizados,
    CAST(I.valor_crms_nao_localizados AS DECIMAL(19,2)) AS valor_crms_nao_localizados,
    I.qtd_crms_antes_registro,
    CAST(I.valor_crms_antes_registro AS DECIMAL(19,2)) AS valor_crms_antes_registro,
    I.qtd_crms_irregulares,
    CAST(I.valor_crms_irregulares AS DECIMAL(19,2)) AS valor_crms_irregulares
INTO temp_CGUSC.fp.indicador_crms_irregulares_detalhado
FROM temp_CGUSC.fp.indicador_crms_irregulares I;

CREATE UNIQUE CLUSTERED INDEX IDX_FinalIrreg_CNPJ
ON temp_CGUSC.fp.indicador_crms_irregulares_detalhado(id_cnpj, ano_base);


-- ============================================================================
-- PASSO 6: AGREGADO POR REGIAO DE SAUDE/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crms_irregulares_regiao;

SELECT
    I.ano_base,
    F.id_regiao_saude,
    SUM(I.total_prescritores) AS total_prescritores,
    SUM(I.total_prescricoes) AS total_prescricoes,
    CAST(SUM(I.valor_total_auditado) AS DECIMAL(19,2)) AS valor_total_auditado,
    SUM(I.qtd_crms_nao_localizados) AS qtd_crms_nao_localizados,
    CAST(SUM(I.valor_crms_nao_localizados) AS DECIMAL(19,2)) AS valor_crms_nao_localizados,
    SUM(I.qtd_crms_antes_registro) AS qtd_crms_antes_registro,
    CAST(SUM(I.valor_crms_antes_registro) AS DECIMAL(19,2)) AS valor_crms_antes_registro,
    SUM(I.qtd_crms_irregulares) AS qtd_crms_irregulares,
    CAST(SUM(I.valor_crms_irregulares) AS DECIMAL(19,2)) AS valor_crms_irregulares,
    CAST(COUNT_BIG(*) AS INT) AS qtd_cnpjs
INTO temp_CGUSC.fp.indicador_crms_irregulares_regiao
FROM temp_CGUSC.fp.indicador_crms_irregulares I
INNER JOIN #farmacias_dim F
    ON F.id_cnpj = I.id_cnpj
GROUP BY
    I.ano_base,
    F.id_regiao_saude;

CREATE UNIQUE CLUSTERED INDEX IDX_IndIrregReg
ON temp_CGUSC.fp.indicador_crms_irregulares_regiao(ano_base, id_regiao_saude);


-- ============================================================================
-- PASSO 7: AGREGADO POR UF/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crms_irregulares_uf;

SELECT
    I.ano_base,
    F.uf,
    SUM(I.total_prescritores) AS total_prescritores,
    SUM(I.total_prescricoes) AS total_prescricoes,
    CAST(SUM(I.valor_total_auditado) AS DECIMAL(19,2)) AS valor_total_auditado,
    SUM(I.qtd_crms_nao_localizados) AS qtd_crms_nao_localizados,
    CAST(SUM(I.valor_crms_nao_localizados) AS DECIMAL(19,2)) AS valor_crms_nao_localizados,
    SUM(I.qtd_crms_antes_registro) AS qtd_crms_antes_registro,
    CAST(SUM(I.valor_crms_antes_registro) AS DECIMAL(19,2)) AS valor_crms_antes_registro,
    SUM(I.qtd_crms_irregulares) AS qtd_crms_irregulares,
    CAST(SUM(I.valor_crms_irregulares) AS DECIMAL(19,2)) AS valor_crms_irregulares,
    CAST(COUNT_BIG(*) AS INT) AS qtd_cnpjs
INTO temp_CGUSC.fp.indicador_crms_irregulares_uf
FROM temp_CGUSC.fp.indicador_crms_irregulares I
INNER JOIN #farmacias_dim F
    ON F.id_cnpj = I.id_cnpj
GROUP BY
    I.ano_base,
    F.uf;

CREATE UNIQUE CLUSTERED INDEX IDX_IndIrregUF
ON temp_CGUSC.fp.indicador_crms_irregulares_uf(ano_base, uf);


-- ============================================================================
-- PASSO 8: AGREGADO BRASIL/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crms_irregulares_br;

SELECT
    I.ano_base,
    SUM(I.total_prescritores) AS total_prescritores,
    SUM(I.total_prescricoes) AS total_prescricoes,
    CAST(SUM(I.valor_total_auditado) AS DECIMAL(19,2)) AS valor_total_auditado,
    SUM(I.qtd_crms_nao_localizados) AS qtd_crms_nao_localizados,
    CAST(SUM(I.valor_crms_nao_localizados) AS DECIMAL(19,2)) AS valor_crms_nao_localizados,
    SUM(I.qtd_crms_antes_registro) AS qtd_crms_antes_registro,
    CAST(SUM(I.valor_crms_antes_registro) AS DECIMAL(19,2)) AS valor_crms_antes_registro,
    SUM(I.qtd_crms_irregulares) AS qtd_crms_irregulares,
    CAST(SUM(I.valor_crms_irregulares) AS DECIMAL(19,2)) AS valor_crms_irregulares,
    CAST(COUNT_BIG(*) AS INT) AS qtd_cnpjs
INTO temp_CGUSC.fp.indicador_crms_irregulares_br
FROM temp_CGUSC.fp.indicador_crms_irregulares I
GROUP BY
    I.ano_base;

CREATE UNIQUE CLUSTERED INDEX IDX_IndIrregBR
ON temp_CGUSC.fp.indicador_crms_irregulares_br(ano_base);
GO


-- ============================================================================
-- LIMPEZA DAS TABELAS INTERMEDIARIAS
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crms_irregulares;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crms_irregulares_mun;
DROP TABLE IF EXISTS #farmacias_dim;
GO
