USE [temp_CGUSC]
GO

-- ============================================================================
-- INDICADOR DE CRMs IRREGULARES - VERSÃO COMPLETA
-- ============================================================================
-- OBJETIVO: Identificar farmácias com alto volume de prescrições vinculadas a
--           CRMs irregulares (não localizados no CFM ou usados antes do registro)
-- 
-- FONTE: db_FarmaciaPopular.carga_2024.relatorio_movimentacaoFP_2021_2024
-- 
-- IRREGULARIDADES DETECTADAS:
--   1. CRM não localizado na base do CFM
--   2. Prescrição realizada antes da data de inscrição do CRM
--
-- INTERPRETAÇÃO DO pct_risco_irregularidade:
--   - >50%: CRÍTICO - Mais da metade do faturamento vem de CRMs irregulares
--   - 30-50%: ALTO - Parcela significativa irregular
--   - 10-30%: MODERADO - Requer investigação
--   - <10%: BAIXO - Pode ser erro cadastral isolado
-- ============================================================================

-- ============================================================================
-- DEFINIÇÃO DE VARIÁVEIS
-- ============================================================================
DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim DATE = '2024-12-10';

-- ============================================================================
-- PASSO 0: PREPARAR BASE DO CFM COM DATA DE INSCRIÇÃO CONVERTIDA
-- ============================================================================
DROP TABLE IF EXISTS #CFM_Base;

SELECT 
    NU_CRM,
    SG_UF,
    TRY_CONVERT(DATE, DT_INSCRICAO, 103) AS dt_inscricao_convertida
INTO #CFM_Base
FROM temp_CFM.fp.medicos_jul_2025_mod;

CREATE CLUSTERED INDEX IDX_CFM_CRM_UF ON #CFM_Base(NU_CRM, SG_UF);


-- ============================================================================
-- PASSO 1: BASE DE PRESCRITORES POR FARMÁCIA COM FLAGS DE IRREGULARIDADE
-- ============================================================================
DROP TABLE IF EXISTS #CRMsPorFarmacia;

SELECT 
    R.cnpj,
    CONCAT(R.crm, '/', R.crm_uf) AS id_medico,
    R.crm AS nu_crm,
    R.crm_uf AS sg_uf_crm,
    COUNT(DISTINCT R.num_autorizacao) AS nu_prescricoes,
    SUM(R.valor_pago) AS vl_total_prescricoes,
    MIN(R.data_hora) AS dt_primeira_prescricao,
    
    -- FLAG: CRM não localizado no CFM
    CASE 
        WHEN CFM.NU_CRM IS NULL THEN 1 
        ELSE 0 
    END AS flag_nao_localizado,
    
    -- FLAG: Prescrição antes do registro do CRM
    CASE 
        WHEN CFM.dt_inscricao_convertida IS NOT NULL 
         AND MIN(R.data_hora) < CFM.dt_inscricao_convertida 
        THEN 1 
        ELSE 0 
    END AS flag_antes_registro

INTO #CRMsPorFarmacia
FROM db_FarmaciaPopular.carga_2024.relatorio_movimentacaoFP_2021_2024 R
LEFT JOIN #CFM_Base CFM 
    ON CFM.NU_CRM = CAST(R.crm AS VARCHAR(25)) 
   AND CFM.SG_UF = R.crm_uf
WHERE 
    R.data_hora >= @DataInicio 
    AND R.data_hora <= @DataFim
    AND R.crm IS NOT NULL 
    AND R.crm_uf IS NOT NULL 
    AND R.crm_uf <> 'BR'
    AND R.crm > 0
GROUP BY 
    R.cnpj, 
    R.crm, 
    R.crm_uf,
    CFM.NU_CRM,
    CFM.dt_inscricao_convertida;

CREATE CLUSTERED INDEX IDX_CRMFarm_CNPJ ON #CRMsPorFarmacia(cnpj);


-- ============================================================================
-- PASSO 2: AGREGAÇÃO POR FARMÁCIA
-- ============================================================================
DROP TABLE IF EXISTS #IrregularidadePorFarmacia;

SELECT 
    cnpj,
    
    -- Total de prescritores distintos
    COUNT(DISTINCT id_medico) AS total_prescritores,
    
    -- Total de valor da farmácia
    SUM(vl_total_prescricoes) AS total_valor_farmacia,
    
    -- CRMs não localizados no CFM
    SUM(flag_nao_localizado) AS qtd_crms_nao_localizados,
    SUM(CASE WHEN flag_nao_localizado = 1 THEN vl_total_prescricoes ELSE 0 END) AS valor_crms_nao_localizados,
    
    -- CRMs com prescrição antes do registro
    SUM(flag_antes_registro) AS qtd_crms_antes_registro,
    SUM(CASE WHEN flag_antes_registro = 1 THEN vl_total_prescricoes ELSE 0 END) AS valor_crms_antes_registro

INTO #IrregularidadePorFarmacia
FROM #CRMsPorFarmacia
GROUP BY cnpj;

CREATE CLUSTERED INDEX IDX_Irreg_CNPJ ON #IrregularidadePorFarmacia(cnpj);


-- ============================================================================
-- PASSO 3: TABELA BASE POR FARMÁCIA
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicadorCRMsIrregulares;

SELECT 
    cnpj,
    total_prescritores,
    total_valor_farmacia,
    qtd_crms_nao_localizados,
    valor_crms_nao_localizados,
    qtd_crms_antes_registro,
    valor_crms_antes_registro,
    
    -- PERCENTUAL DE RISCO: % do valor que veio de CRMs irregulares
    CAST(
        CASE 
            WHEN total_valor_farmacia > 0 THEN 
                ((ISNULL(valor_crms_nao_localizados, 0) + ISNULL(valor_crms_antes_registro, 0)) / 
                 total_valor_farmacia) * 100.0
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS pct_risco_irregularidade

INTO temp_CGUSC.fp.indicadorCRMsIrregulares
FROM #IrregularidadePorFarmacia
WHERE total_prescritores > 0;

CREATE CLUSTERED INDEX IDX_IndIrreg_CNPJ ON temp_CGUSC.fp.indicadorCRMsIrregulares(cnpj);


-- ============================================================================
-- PASSO 4: CÁLCULO DAS MÉDIAS POR ESTADO (UF)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicadorCRMsIrregulares_UF;

SELECT 
    CAST(F.uf AS VARCHAR(2)) AS uf,
    
    SUM(I.total_valor_farmacia) AS total_valor_uf,
    SUM(I.valor_crms_nao_localizados) AS valor_nao_localizados_uf,
    SUM(I.valor_crms_antes_registro) AS valor_antes_registro_uf,
    
    -- Média do Estado (% do valor irregular)
    CAST(
        CASE 
            WHEN SUM(I.total_valor_farmacia) > 0 THEN 
                ((SUM(ISNULL(I.valor_crms_nao_localizados, 0)) + SUM(ISNULL(I.valor_crms_antes_registro, 0))) / 
                 SUM(I.total_valor_farmacia)) * 100.0
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS pct_risco_irregularidade_uf

INTO temp_CGUSC.fp.indicadorCRMsIrregulares_UF
FROM temp_CGUSC.fp.indicadorCRMsIrregulares I
INNER JOIN temp_CGUSC.fp.dadosFarmaciasFP F 
    ON F.cnpj = I.cnpj
GROUP BY CAST(F.uf AS VARCHAR(2));

CREATE CLUSTERED INDEX IDX_IndIrregUF_UF ON temp_CGUSC.fp.indicadorCRMsIrregulares_UF(uf);


-- ============================================================================
-- PASSO 5: CÁLCULO DA MÉDIA NACIONAL (BRASIL)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicadorCRMsIrregulares_BR;

SELECT 
    'BR' AS pais,
    
    SUM(total_valor_farmacia) AS total_valor_br,
    SUM(valor_crms_nao_localizados) AS valor_nao_localizados_br,
    SUM(valor_crms_antes_registro) AS valor_antes_registro_br,
    
    -- Média Nacional (% do valor irregular)
    CAST(
        CASE 
            WHEN SUM(total_valor_farmacia) > 0 THEN 
                ((SUM(ISNULL(valor_crms_nao_localizados, 0)) + SUM(ISNULL(valor_crms_antes_registro, 0))) / 
                 SUM(total_valor_farmacia)) * 100.0
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS pct_risco_irregularidade_br

INTO temp_CGUSC.fp.indicadorCRMsIrregulares_BR
FROM temp_CGUSC.fp.indicadorCRMsIrregulares;


-- ============================================================================
-- PASSO 6: TABELA CONSOLIDADA FINAL (COMPARATIVO DE RISCO)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicadorCRMsIrregulares_Completo;

SELECT 
    I.cnpj,
    F.razaoSocial,
    F.municipio,
    CAST(F.uf AS VARCHAR(2)) AS uf,
    
    -- Métricas Absolutas
    I.total_prescritores,
    I.total_valor_farmacia,
    
    -- CRMs não localizados
    I.qtd_crms_nao_localizados,
    I.valor_crms_nao_localizados,
    
    -- CRMs antes do registro
    I.qtd_crms_antes_registro,
    I.valor_crms_antes_registro,
    
    -- Percentual de risco da farmácia
    I.pct_risco_irregularidade,
    
    -- Comparativos
    ISNULL(UF.pct_risco_irregularidade_uf, 0) AS media_estado,
    BR.pct_risco_irregularidade_br AS media_pais,
    
    -- RISCO RELATIVO UF
    CAST(
        CASE 
            WHEN UF.pct_risco_irregularidade_uf > 0 THEN 
                I.pct_risco_irregularidade / UF.pct_risco_irregularidade_uf
            ELSE 
                CASE WHEN I.pct_risco_irregularidade > 0 THEN 99.0 ELSE 0 END
        END 
    AS DECIMAL(18,4)) AS risco_relativo_uf,

    -- RISCO RELATIVO BR
    CAST(
        CASE 
            WHEN BR.pct_risco_irregularidade_br > 0 THEN 
                I.pct_risco_irregularidade / BR.pct_risco_irregularidade_br
            ELSE 
                CASE WHEN I.pct_risco_irregularidade > 0 THEN 99.0 ELSE 0 END
        END 
    AS DECIMAL(18,4)) AS risco_relativo_br,
    
    -- CLASSIFICAÇÃO DE RISCO
    CASE 
        WHEN I.pct_risco_irregularidade >= 50 THEN 'CRÍTICO'
        WHEN I.pct_risco_irregularidade >= 30 THEN 'ALTO'
        WHEN I.pct_risco_irregularidade >= 10 THEN 'MODERADO'
        ELSE 'BAIXO'
    END AS classificacao_risco

INTO temp_CGUSC.fp.indicadorCRMsIrregulares_Completo
FROM temp_CGUSC.fp.indicadorCRMsIrregulares I
INNER JOIN temp_CGUSC.fp.dadosFarmaciasFP F 
    ON F.cnpj = I.cnpj
LEFT JOIN temp_CGUSC.fp.indicadorCRMsIrregulares_UF UF 
    ON CAST(F.uf AS VARCHAR(2)) = UF.uf
CROSS JOIN temp_CGUSC.fp.indicadorCRMsIrregulares_BR BR;

-- Índices Finais
CREATE CLUSTERED INDEX IDX_FinalIrreg_CNPJ ON temp_CGUSC.fp.indicadorCRMsIrregulares_Completo(cnpj);
CREATE NONCLUSTERED INDEX IDX_FinalIrreg_Risco ON temp_CGUSC.fp.indicadorCRMsIrregulares_Completo(risco_relativo_uf DESC);
CREATE NONCLUSTERED INDEX IDX_FinalIrreg_Pct ON temp_CGUSC.fp.indicadorCRMsIrregulares_Completo(pct_risco_irregularidade DESC);
GO


-- ============================================================================
-- LIMPEZA
-- ============================================================================
DROP TABLE IF EXISTS #CFM_Base;
DROP TABLE IF EXISTS #CRMsPorFarmacia;
DROP TABLE IF EXISTS #IrregularidadePorFarmacia;

