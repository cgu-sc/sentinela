USE [temp_CGUSC]
GO

-- ============================================================================
-- INDICADOR DE CRMs IRREGULARES
-- ============================================================================
-- OBJETIVO: Identificar farmacias com alto volume de prescricoes vinculadas a
--           CRMs irregulares em cada ano.
--
-- METRICA PRINCIPAL:
--   pct_risco_irregularidade representa o percentual anual do valor pago
--   vinculado a CRMs nao localizados no CFM ou utilizados antes da data de
--   inscricao do medico no conselho.
--
-- FONTE DE DADOS:
--   - db_FarmaciaPopular.dbo.Relatorio_movimentacaoFP
--   - db_FarmaciaPopular.carga_2024.relatorio_movimentacao_2021_2024
--   - temp_CFM.dbo.medicos_jul_2025_mod
--   - temp_CGUSC.fp.medicamentos_patologia (universo de medicamentos auditados)
--   - temp_CGUSC.fp.dados_farmacia (id_cnpj e contexto territorial)
-- ============================================================================

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

IF OBJECT_ID('db_FarmaciaPopular.carga_2024.relatorio_movimentacao_2021_2024', 'U') IS NULL
BEGIN
    RAISERROR('Tabela db_FarmaciaPopular.carga_2024.relatorio_movimentacao_2021_2024 nao encontrada.', 16, 1);
    RETURN;
END;

IF COL_LENGTH('db_FarmaciaPopular.carga_2024.relatorio_movimentacao_2021_2024', 'cnpj') IS NULL
   OR COL_LENGTH('db_FarmaciaPopular.carga_2024.relatorio_movimentacao_2021_2024', 'crm') IS NULL
   OR COL_LENGTH('db_FarmaciaPopular.carga_2024.relatorio_movimentacao_2021_2024', 'crm_uf') IS NULL
   OR COL_LENGTH('db_FarmaciaPopular.carga_2024.relatorio_movimentacao_2021_2024', 'num_autorizacao') IS NULL
   OR COL_LENGTH('db_FarmaciaPopular.carga_2024.relatorio_movimentacao_2021_2024', 'valor_pago') IS NULL
   OR COL_LENGTH('db_FarmaciaPopular.carga_2024.relatorio_movimentacao_2021_2024', 'data_hora') IS NULL
   OR COL_LENGTH('db_FarmaciaPopular.carga_2024.relatorio_movimentacao_2021_2024', 'codigo_barra') IS NULL
BEGIN
    RAISERROR('Tabela db_FarmaciaPopular.carga_2024.relatorio_movimentacao_2021_2024 sem colunas obrigatorias para CRMs irregulares.', 16, 1);
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
-- PASSO 1: BASE DO CFM COM DATA DE INSCRICAO CONVERTIDA
-- ============================================================================
DROP TABLE IF EXISTS #CFM_Base;

SELECT
    CAST(NU_CRM AS VARCHAR(25)) AS NU_CRM,
    CAST(UPPER(LTRIM(RTRIM(SG_uf))) AS VARCHAR(2)) AS SG_uf,
    MIN(TRY_CONVERT(DATE, DT_INSCRICAO, 103)) AS dt_inscricao_convertida
INTO #CFM_Base
FROM temp_CFM.dbo.medicos_jul_2025_mod
WHERE NU_CRM IS NOT NULL
  AND NULLIF(LTRIM(RTRIM(SG_uf)), '') IS NOT NULL
GROUP BY
    CAST(NU_CRM AS VARCHAR(25)),
    CAST(UPPER(LTRIM(RTRIM(SG_uf))) AS VARCHAR(2));

CREATE UNIQUE CLUSTERED INDEX IDX_CFM_CRM_uf
ON #CFM_Base(NU_CRM, SG_uf);


-- ============================================================================
-- PASSO 2: BASE DE PRESCRITORES POR FARMACIA/ANO
-- ============================================================================
DROP TABLE IF EXISTS #CRMsPorFarmaciaAno;

SELECT
    F.id_cnpj,
    CAST(YEAR(U.data_hora) AS SMALLINT) AS ano_base,
    CONCAT(CAST(U.crm AS VARCHAR(25)), '/', U.crm_uf) AS id_medico,
    CAST(U.crm AS VARCHAR(25)) AS nu_crm,
    U.crm_uf AS sg_uf_crm,
    CAST(COUNT(DISTINCT U.num_autorizacao) AS INT) AS nu_prescricoes,
    CAST(SUM(CAST(U.valor_pago AS DECIMAL(19,2))) AS DECIMAL(19,2)) AS vl_total_prescricoes,
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
      AND crm_uf <> 'BR'
      AND crm > 0
      AND num_autorizacao IS NOT NULL
      AND valor_pago IS NOT NULL
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
    FROM db_FarmaciaPopular.carga_2024.relatorio_movimentacao_2021_2024
    WHERE data_hora >= @DataInicio
      AND data_hora < DATEADD(DAY, 1, @DataFim)
      AND crm IS NOT NULL
      AND crm_uf IS NOT NULL
      AND crm_uf <> 'BR'
      AND crm > 0
      AND num_autorizacao IS NOT NULL
      AND valor_pago IS NOT NULL
      AND codigo_barra IS NOT NULL
) U
INNER JOIN #farmacias_dim F
    ON F.cnpj = U.cnpj
INNER JOIN #medicamentos_patologia_gtin C
    ON C.codigo_barra = U.codigo_barra
LEFT JOIN #CFM_Base CFM
    ON CFM.NU_CRM = CAST(U.crm AS VARCHAR(25))
   AND CFM.SG_uf = U.crm_uf
GROUP BY
    F.id_cnpj,
    YEAR(U.data_hora),
    U.crm,
    U.crm_uf,
    CFM.NU_CRM,
    CFM.dt_inscricao_convertida;

CREATE CLUSTERED INDEX IDX_CRMFarmAno_CNPJ
ON #CRMsPorFarmaciaAno(id_cnpj, ano_base);

DROP TABLE IF EXISTS #CFM_Base;
DROP TABLE IF EXISTS #medicamentos_patologia_gtin;


-- ============================================================================
-- PASSO 3: AGREGACAO POR FARMACIA/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crms_irregulares;

SELECT
    id_cnpj,
    ano_base,
    CAST(COUNT(DISTINCT id_medico) AS INT) AS total_prescritores,
    CAST(SUM(vl_total_prescricoes) AS DECIMAL(19,2)) AS total_valor_farmacia,
    CAST(SUM(flag_nao_localizado) AS INT) AS qtd_crms_nao_localizados,
    CAST(SUM(CASE WHEN flag_nao_localizado = 1 THEN vl_total_prescricoes ELSE 0 END) AS DECIMAL(19,2)) AS valor_crms_nao_localizados,
    CAST(SUM(flag_antes_registro) AS INT) AS qtd_crms_antes_registro,
    CAST(SUM(CASE WHEN flag_antes_registro = 1 THEN vl_total_prescricoes ELSE 0 END) AS DECIMAL(19,2)) AS valor_crms_antes_registro,
    CAST(
        CASE
            WHEN SUM(vl_total_prescricoes) > 0 THEN
                (
                    CAST(
                        SUM(CASE WHEN flag_nao_localizado = 1 THEN vl_total_prescricoes ELSE 0 END) +
                        SUM(CASE WHEN flag_antes_registro = 1 THEN vl_total_prescricoes ELSE 0 END)
                        AS DECIMAL(19,4)
                    ) /
                    CAST(SUM(vl_total_prescricoes) AS DECIMAL(19,4))
                ) * 100.0
            ELSE 0
        END AS DECIMAL(7,4)
    ) AS pct_risco_irregularidade
INTO temp_CGUSC.fp.indicador_crms_irregulares
FROM #CRMsPorFarmaciaAno
GROUP BY
    id_cnpj,
    ano_base
HAVING COUNT(DISTINCT id_medico) > 0;

CREATE UNIQUE CLUSTERED INDEX IDX_IndIrreg_CNPJ_Ano
ON temp_CGUSC.fp.indicador_crms_irregulares(id_cnpj, ano_base);

DROP TABLE IF EXISTS #CRMsPorFarmaciaAno;


-- ============================================================================
-- PASSO 4: METRICAS POR MUNICIPIO (MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crms_irregulares_mun;

SELECT DISTINCT
    I.ano_base,
    F.uf,
    F.municipio,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.pct_risco_irregularidade)
        OVER (PARTITION BY I.ano_base, F.uf, F.municipio)
    AS DECIMAL(7,4)) AS mediana_municipio
INTO temp_CGUSC.fp.indicador_crms_irregulares_mun
FROM temp_CGUSC.fp.indicador_crms_irregulares I
INNER JOIN #farmacias_dim F
    ON F.id_cnpj = I.id_cnpj;

CREATE CLUSTERED INDEX IDX_IndIrregMun
ON temp_CGUSC.fp.indicador_crms_irregulares_mun(ano_base, uf, municipio);


-- ============================================================================
-- PASSO 5: METRICAS POR ESTADO (MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crms_irregulares_uf;

SELECT DISTINCT
    I.ano_base,
    F.uf,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.pct_risco_irregularidade)
        OVER (PARTITION BY I.ano_base, F.uf)
    AS DECIMAL(7,4)) AS mediana_estado
INTO temp_CGUSC.fp.indicador_crms_irregulares_uf
FROM temp_CGUSC.fp.indicador_crms_irregulares I
INNER JOIN #farmacias_dim F
    ON F.id_cnpj = I.id_cnpj;

CREATE CLUSTERED INDEX IDX_IndIrregUF_uf
ON temp_CGUSC.fp.indicador_crms_irregulares_uf(ano_base, uf);


-- ============================================================================
-- PASSO 5B: METRICAS POR REGIAO DE SAUDE (MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crms_irregulares_regiao;

SELECT DISTINCT
    I.ano_base,
    F.id_regiao_saude,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.pct_risco_irregularidade)
        OVER (PARTITION BY I.ano_base, F.id_regiao_saude)
    AS DECIMAL(7,4)) AS mediana_regiao
INTO temp_CGUSC.fp.indicador_crms_irregulares_regiao
FROM temp_CGUSC.fp.indicador_crms_irregulares I
INNER JOIN #farmacias_dim F
    ON F.id_cnpj = I.id_cnpj;

CREATE CLUSTERED INDEX IDX_IndIrregReg
ON temp_CGUSC.fp.indicador_crms_irregulares_regiao(ano_base, id_regiao_saude);


-- ============================================================================
-- PASSO 6: METRICAS NACIONAIS (MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crms_irregulares_br;

SELECT DISTINCT
    ano_base,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY pct_risco_irregularidade)
        OVER (PARTITION BY ano_base)
    AS DECIMAL(7,4)) AS mediana_pais
INTO temp_CGUSC.fp.indicador_crms_irregulares_br
FROM temp_CGUSC.fp.indicador_crms_irregulares;

CREATE CLUSTERED INDEX IDX_IndIrregBR
ON temp_CGUSC.fp.indicador_crms_irregulares_br(ano_base);


-- ============================================================================
-- PASSO 7: TABELA CONSOLIDADA FINAL
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crms_irregulares_detalhado;

SELECT
    I.id_cnpj,
    I.ano_base,
    I.total_prescritores,
    I.total_valor_farmacia,
    I.qtd_crms_nao_localizados,
    I.valor_crms_nao_localizados,
    I.qtd_crms_antes_registro,
    I.valor_crms_antes_registro,
    I.pct_risco_irregularidade,

    MUN.mediana_municipio AS municipio_mediana,
    CAST((I.pct_risco_irregularidade + 0.01) / (MUN.mediana_municipio + 0.01) AS DECIMAL(9,4)) AS risco_relativo_mun_mediana,

    UF.mediana_estado AS estado_mediana,
    CAST((I.pct_risco_irregularidade + 0.01) / (UF.mediana_estado + 0.01) AS DECIMAL(9,4)) AS risco_relativo_uf_mediana,

    REG.mediana_regiao AS regiao_saude_mediana,
    CAST((I.pct_risco_irregularidade + 0.01) / (REG.mediana_regiao + 0.01) AS DECIMAL(9,4)) AS risco_relativo_reg_mediana,

    BR.mediana_pais AS pais_mediana,
    CAST((I.pct_risco_irregularidade + 0.01) / (BR.mediana_pais + 0.01) AS DECIMAL(9,4)) AS risco_relativo_br_mediana
INTO temp_CGUSC.fp.indicador_crms_irregulares_detalhado
FROM temp_CGUSC.fp.indicador_crms_irregulares I
INNER JOIN #farmacias_dim F
    ON F.id_cnpj = I.id_cnpj
INNER JOIN temp_CGUSC.fp.indicador_crms_irregulares_mun MUN
    ON I.ano_base = MUN.ano_base
   AND F.uf = MUN.uf
   AND F.municipio = MUN.municipio
INNER JOIN temp_CGUSC.fp.indicador_crms_irregulares_uf UF
    ON I.ano_base = UF.ano_base
   AND F.uf = UF.uf
INNER JOIN temp_CGUSC.fp.indicador_crms_irregulares_regiao REG
    ON I.ano_base = REG.ano_base
   AND F.id_regiao_saude = REG.id_regiao_saude
INNER JOIN temp_CGUSC.fp.indicador_crms_irregulares_br BR
    ON I.ano_base = BR.ano_base;

CREATE UNIQUE CLUSTERED INDEX IDX_FinalIrreg_CNPJ
ON temp_CGUSC.fp.indicador_crms_irregulares_detalhado(id_cnpj, ano_base);

CREATE NONCLUSTERED INDEX IDX_FinalIrreg_RiscoReg
ON temp_CGUSC.fp.indicador_crms_irregulares_detalhado(ano_base, risco_relativo_reg_mediana DESC);
GO


-- ============================================================================
-- LIMPEZA DAS TABELAS INTERMEDIARIAS
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crms_irregulares;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crms_irregulares_mun;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crms_irregulares_uf;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crms_irregulares_regiao;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crms_irregulares_br;
DROP TABLE IF EXISTS #farmacias_dim;
GO
