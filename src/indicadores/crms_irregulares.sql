USE [temp_CGUSC]
GO

-- ============================================================================
-- INDICADOR DE CRMs IRREGULARES
-- ============================================================================
-- OBJETIVO: Identificar farmacias com alto volume de prescricoes vinculadas a
--           CRMs irregulares (nao localizados no CFM ou usados antes do registro)
--
-- INTERPRETACAO DO pct_risco_irregularidade:
--   - >= 50%: CRITICO  - Mais da metade do faturamento vem de CRMs irregulares
--   - 30-50%: ALTO     - Parcela significativa irregular
--   - 10-30%: MODERADO - Requer investigacao
--   - < 10%:  BAIXO    - Pode ser erro cadastral isolado
--
-- IRREGULARIDADES DETECTADAS:
--   1. CRM nao localizado na base do CFM
--   2. Prescricao realizada antes da data de inscricao do CRM
--
-- ALTERACOES APLICADAS:
--   1. Fonte dupla: UNION ALL de db_FarmaciaPopular.dbo.Relatorio_movimentacaoFP
--      e db_FarmaciaPopular.carga_2024.relatorio_movimentacao_2021_2024 no
--      Passo 1, garantindo cobertura completa do periodo
--   2. Adicionado nivel municipio (Passo 4: mediana e media), alinhado ao padrao
--      venda_per_capita e exclusividade_crm
--   3. Passos 5 e 6 (UF e BR) agora calculam mediana alem da media, usando
--      a tecnica CTE_Medias + CTE_Mediana conforme exclusividade_crm.sql
--   4. Tabela final nomeada como _detalhado; adicionados rankings explicitos
--      por Brasil, UF e Municipio (pct_risco_irregularidade DESC)
--   5. Adicionados riscos relativos em relacao a mediana e a media de cada
--      nivel geografico, alem do risco relativo original vs media
-- ============================================================================

-- ============================================================================
-- DEFINICAO DE VARIAVEIS
-- ============================================================================
DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim    DATE = '2024-12-10';


-- ============================================================================
-- PASSO 0: PREPARAR BASE DO CFM COM DATA DE INSCRICAO CONVERTIDA
-- ============================================================================
DROP TABLE IF EXISTS #CFM_Base;

SELECT
    NU_CRM,
    SG_uf,
    TRY_CONVERT(DATE, DT_INSCRICAO, 103) AS dt_inscricao_convertida
INTO #CFM_Base
FROM temp_CFM.dbo.medicos_jul_2025_mod;

CREATE CLUSTERED INDEX IDX_CFM_CRM_uf ON #CFM_Base(NU_CRM, SG_uf);


-- ============================================================================
-- PASSO 1: BASE DE PRESCRITORES POR FARMACIA COM FLAGS DE IRREGULARIDADE
-- UNION ALL entre a base historica e a recente para cobrir todo o periodo.
-- O JOIN com #CFM_Base e feito FORA do UNION para evitar duplicacao.
-- ============================================================================
DROP TABLE IF EXISTS #CRMsPorFarmacia;

SELECT
    U.cnpj,
    CONCAT(U.crm, '/', U.crm_uf)     AS id_medico,
    U.crm                             AS nu_crm,
    U.crm_uf                          AS sg_uf_crm,
    COUNT(DISTINCT U.num_autorizacao) AS nu_prescricoes,
    SUM(U.valor_pago)                 AS vl_total_prescricoes,
    MIN(U.data_hora)                  AS dt_primeira_prescricao,

    -- FLAG: CRM nao localizado no CFM
    CASE
        WHEN CFM.NU_CRM IS NULL THEN 1
        ELSE 0
    END AS flag_nao_localizado,

    -- FLAG: Prescricao antes do registro do CRM
    CASE
        WHEN CFM.dt_inscricao_convertida IS NOT NULL
         AND MIN(U.data_hora) < CFM.dt_inscricao_convertida
        THEN 1
        ELSE 0
    END AS flag_antes_registro

INTO #CRMsPorFarmacia
FROM (
    SELECT cnpj, crm, crm_uf, num_autorizacao, valor_pago, data_hora
    FROM db_FarmaciaPopular.dbo.Relatorio_movimentacaoFP
    WHERE data_hora >= @DataInicio
      AND data_hora <= @DataFim
      AND crm IS NOT NULL
      AND crm_uf IS NOT NULL
      AND crm_uf <> 'BR'
      AND crm > 0

    UNION ALL

    SELECT cnpj, crm, crm_uf, num_autorizacao, valor_pago, data_hora
    FROM db_FarmaciaPopular.carga_2024.relatorio_movimentacao_2021_2024
    WHERE data_hora >= @DataInicio
      AND data_hora <= @DataFim
      AND crm IS NOT NULL
      AND crm_uf IS NOT NULL
      AND crm_uf <> 'BR'
      AND crm > 0
) U
LEFT JOIN #CFM_Base CFM
    ON  CFM.NU_CRM = CAST(U.crm AS VARCHAR(25))
    AND CFM.SG_uf  = U.crm_uf
GROUP BY
    U.cnpj,
    U.crm,
    U.crm_uf,
    CFM.NU_CRM,
    CFM.dt_inscricao_convertida;

CREATE CLUSTERED INDEX IDX_CRMFarm_CNPJ ON #CRMsPorFarmacia(cnpj);

DROP TABLE IF EXISTS #CFM_Base;


-- ============================================================================
-- PASSO 2: AGREGACAO POR FARMACIA
-- ============================================================================
DROP TABLE IF EXISTS #IrregularidadePorFarmacia;

SELECT
    cnpj,

    COUNT(DISTINCT id_medico)          AS total_prescritores,
    SUM(vl_total_prescricoes)          AS total_valor_farmacia,

    -- CRMs nao localizados no CFM
    SUM(flag_nao_localizado) AS qtd_crms_nao_localizados,
    SUM(CASE WHEN flag_nao_localizado = 1 THEN vl_total_prescricoes ELSE 0 END) AS valor_crms_nao_localizados,

    -- CRMs com prescricao antes do registro
    SUM(flag_antes_registro) AS qtd_crms_antes_registro,
    SUM(CASE WHEN flag_antes_registro = 1 THEN vl_total_prescricoes ELSE 0 END) AS valor_crms_antes_registro

INTO #IrregularidadePorFarmacia
FROM #CRMsPorFarmacia
GROUP BY cnpj;

CREATE CLUSTERED INDEX IDX_Irreg_CNPJ ON #IrregularidadePorFarmacia(cnpj);

DROP TABLE IF EXISTS #CRMsPorFarmacia;


-- ============================================================================
-- PASSO 3: TABELA BASE POR FARMACIA
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crms_irregulares;

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

INTO temp_CGUSC.fp.indicador_crms_irregulares
FROM #IrregularidadePorFarmacia
WHERE total_prescritores > 0;

CREATE CLUSTERED INDEX IDX_IndIrreg_CNPJ ON temp_CGUSC.fp.indicador_crms_irregulares(cnpj);

DROP TABLE IF EXISTS #IrregularidadePorFarmacia;


-- ============================================================================
-- PASSO 4: METRICAS POR MUNICIPIO (MEDIANA E MEDIA)
-- Alinhado ao padrao venda_per_capita e exclusividade_crm
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crms_irregulares_mun;

SELECT DISTINCT
    CAST(F.uf        AS VARCHAR(2))   AS uf,
    CAST(F.municipio AS VARCHAR(255)) AS municipio,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.pct_risco_irregularidade)
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255)))
    AS DECIMAL(18,4)) AS mediana_municipio,
    CAST(
        AVG(I.pct_risco_irregularidade)
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255)))
    AS DECIMAL(18,4)) AS media_municipio
INTO temp_CGUSC.fp.indicador_crms_irregulares_mun
FROM temp_CGUSC.fp.indicador_crms_irregulares I
INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj;

CREATE CLUSTERED INDEX IDX_IndIrregMun ON temp_CGUSC.fp.indicador_crms_irregulares_mun(uf, municipio);


-- ============================================================================
-- PASSO 5: METRICAS POR ESTADO (MEDIANA E MEDIA)
-- Estrategia: CTE_Medias (AVG via GROUP BY) + CTE_Mediana (PERCENTILE_CONT via OVER)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crms_irregulares_uf;

WITH CTE_Medias AS (
    SELECT
        CAST(F.uf AS VARCHAR(2))            AS uf,
        AVG(I.pct_risco_irregularidade)     AS media_irregularidade_uf,
        SUM(I.total_valor_farmacia)         AS total_valor_uf,
        SUM(I.valor_crms_nao_localizados)   AS valor_nao_localizados_uf,
        SUM(I.valor_crms_antes_registro)    AS valor_antes_registro_uf
    FROM temp_CGUSC.fp.indicador_crms_irregulares I
    INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj
    GROUP BY CAST(F.uf AS VARCHAR(2))
),
CTE_Mediana AS (
    SELECT DISTINCT
        CAST(F.uf AS VARCHAR(2)) AS uf,
        CAST(
            PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.pct_risco_irregularidade)
            OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)))
        AS DECIMAL(18,4)) AS mediana_irregularidade_uf
    FROM temp_CGUSC.fp.indicador_crms_irregulares I
    INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj
)
SELECT
    M.uf,
    M.media_irregularidade_uf,
    M.total_valor_uf,
    M.valor_nao_localizados_uf,
    M.valor_antes_registro_uf,
    D.mediana_irregularidade_uf
INTO temp_CGUSC.fp.indicador_crms_irregulares_uf
FROM CTE_Medias M
INNER JOIN CTE_Mediana D ON D.uf = M.uf;

CREATE CLUSTERED INDEX IDX_IndIrregUF_uf ON temp_CGUSC.fp.indicador_crms_irregulares_uf(uf);


-- ============================================================================
-- PASSO 6: METRICAS NACIONAIS (MEDIANA E MEDIA)
-- Estrategia: CTE_Medias_BR (AVG simples) + CTE_Mediana_BR (PERCENTILE_CONT OVER())
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crms_irregulares_br;

WITH CTE_Medias_BR AS (
    SELECT
        AVG(pct_risco_irregularidade)   AS media_irregularidade_br,
        SUM(total_valor_farmacia)       AS total_valor_br,
        SUM(valor_crms_nao_localizados) AS valor_nao_localizados_br,
        SUM(valor_crms_antes_registro)  AS valor_antes_registro_br
    FROM temp_CGUSC.fp.indicador_crms_irregulares
),
CTE_Mediana_BR AS (
    SELECT DISTINCT
        CAST(
            PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY pct_risco_irregularidade) OVER ()
        AS DECIMAL(18,4)) AS mediana_irregularidade_br
    FROM temp_CGUSC.fp.indicador_crms_irregulares
)
SELECT
    'BR'                        AS pais,
    M.media_irregularidade_br,
    M.total_valor_br,
    M.valor_nao_localizados_br,
    M.valor_antes_registro_br,
    D.mediana_irregularidade_br
INTO temp_CGUSC.fp.indicador_crms_irregulares_br
FROM CTE_Medias_BR M
CROSS JOIN CTE_Mediana_BR D;


-- ============================================================================
-- PASSO 6B: METRICAS POR REGIAO DE SAUDE (MEDIANA E MEDIA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crms_irregulares_regiao;

SELECT DISTINCT
    F.id_regiao_saude,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.pct_risco_irregularidade)
        OVER (PARTITION BY F.id_regiao_saude)
    AS DECIMAL(18,4)) AS mediana_regiao,
    CAST(
        AVG(I.pct_risco_irregularidade)
        OVER (PARTITION BY F.id_regiao_saude)
    AS DECIMAL(18,4)) AS media_regiao
INTO temp_CGUSC.fp.indicador_crms_irregulares_regiao
FROM temp_CGUSC.fp.indicador_crms_irregulares I
INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj
WHERE F.id_regiao_saude IS NOT NULL;

CREATE CLUSTERED INDEX IDX_IndIrregReg ON temp_CGUSC.fp.indicador_crms_irregulares_regiao(id_regiao_saude);


-- ============================================================================
-- PASSO 7: TABELA CONSOLIDADA FINAL
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crms_irregulares_detalhado;

SELECT
    I.cnpj,
    F.razaoSocial,
    F.municipio,
    CAST(F.uf AS VARCHAR(2)) AS uf,
    F.no_regiao_saude,
    F.id_regiao_saude,

    -- Metricas Absolutas
    I.total_prescritores,
    I.total_valor_farmacia,
    I.qtd_crms_nao_localizados,
    I.valor_crms_nao_localizados,
    I.qtd_crms_antes_registro,
    I.valor_crms_antes_registro,

    -- Indicador Principal
    I.pct_risco_irregularidade,

    -- Rankings (pior risco = posicao 1)
    RANK() OVER (
        ORDER BY I.pct_risco_irregularidade DESC
    ) AS ranking_br,
    RANK() OVER (
        PARTITION BY CAST(F.uf AS VARCHAR(2))
        ORDER BY I.pct_risco_irregularidade DESC
    ) AS ranking_uf,
    RANK() OVER (
        PARTITION BY F.id_regiao_saude
        ORDER BY I.pct_risco_irregularidade DESC
    ) AS ranking_regiao_saude,
    RANK() OVER (
        PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255))
        ORDER BY I.pct_risco_irregularidade DESC
    ) AS ranking_municipio,

    -- Benchmarks Municipio
    ISNULL(MUN.mediana_municipio, 0) AS municipio_mediana,
    ISNULL(MUN.media_municipio,   0) AS municipio_media,
    CAST((I.pct_risco_irregularidade + 0.01) / (ISNULL(MUN.mediana_municipio, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_mediana,
    CAST((I.pct_risco_irregularidade + 0.01) / (ISNULL(MUN.media_municipio,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_media,

    -- Benchmarks UF
    ISNULL(UF.mediana_irregularidade_uf, 0) AS estado_mediana,
    ISNULL(UF.media_irregularidade_uf,   0) AS estado_media,
    CAST((I.pct_risco_irregularidade + 0.01) / (ISNULL(UF.mediana_irregularidade_uf, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_mediana,
    CAST((I.pct_risco_irregularidade + 0.01) / (ISNULL(UF.media_irregularidade_uf,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_media,

    -- Benchmarks Regionais (Regiao de Saude)
    ISNULL(REG.mediana_regiao, 0) AS regiao_saude_mediana,
    ISNULL(REG.media_regiao,   0) AS regiao_saude_media,
    CAST((I.pct_risco_irregularidade + 0.01) / (ISNULL(REG.mediana_regiao, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_reg_mediana,
    CAST((I.pct_risco_irregularidade + 0.01) / (ISNULL(REG.media_regiao,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_reg_media,

    -- Benchmarks BR
    BR.mediana_irregularidade_br AS pais_mediana,
    BR.media_irregularidade_br   AS pais_media,
    CAST((I.pct_risco_irregularidade + 0.01) / (BR.mediana_irregularidade_br + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_mediana,
    CAST((I.pct_risco_irregularidade + 0.01) / (BR.media_irregularidade_br   + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_media,

    -- Classificacao de Risco
    CASE
        WHEN I.pct_risco_irregularidade >= 50 THEN 'CRITICO'
        WHEN I.pct_risco_irregularidade >= 30 THEN 'ALTO'
        WHEN I.pct_risco_irregularidade >= 10 THEN 'MODERADO'
        ELSE 'BAIXO'
    END AS classificacao_risco

INTO temp_CGUSC.fp.indicador_crms_irregulares_detalhado
FROM temp_CGUSC.fp.indicador_crms_irregulares I
INNER JOIN temp_CGUSC.fp.dados_farmacia F
    ON F.cnpj = I.cnpj
LEFT JOIN temp_CGUSC.fp.indicador_crms_irregulares_mun MUN
    ON  CAST(F.uf        AS VARCHAR(2))   = MUN.uf
    AND CAST(F.municipio AS VARCHAR(255)) = MUN.municipio
LEFT JOIN temp_CGUSC.fp.indicador_crms_irregulares_uf UF
    ON CAST(F.uf AS VARCHAR(2)) = UF.uf
LEFT JOIN temp_CGUSC.fp.indicador_crms_irregulares_regiao REG
    ON F.id_regiao_saude = REG.id_regiao_saude
CROSS JOIN temp_CGUSC.fp.indicador_crms_irregulares_br BR;

-- Indices Finais
CREATE CLUSTERED INDEX    IDX_FinalIrreg_CNPJ    ON temp_CGUSC.fp.indicador_crms_irregulares_detalhado(cnpj);
CREATE NONCLUSTERED INDEX IDX_FinalIrreg_Pct     ON temp_CGUSC.fp.indicador_crms_irregulares_detalhado(pct_risco_irregularidade DESC);
CREATE NONCLUSTERED INDEX IDX_FinalIrreg_RiscoUF  ON temp_CGUSC.fp.indicador_crms_irregulares_detalhado(risco_relativo_uf_media DESC);
CREATE NONCLUSTERED INDEX IDX_FinalIrreg_RankBR   ON temp_CGUSC.fp.indicador_crms_irregulares_detalhado(ranking_br);
GO


-- ============================================================================
-- LIMPEZA DAS TABELAS INTERMEDIARIAS
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crms_irregulares;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crms_irregulares_mun;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crms_irregulares_uf;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crms_irregulares_regiao;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crms_irregulares_br;
GO


-- ============================================================================
-- VERIFICACAO RAPIDA
-- ============================================================================
SELECT TOP 100 *
FROM temp_CGUSC.fp.indicador_crms_irregulares_detalhado
ORDER BY ranking_br;
GO