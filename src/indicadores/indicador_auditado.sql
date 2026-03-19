USE [temp_CGUSC]
GO

-- ============================================================================
-- SCRIPT: Indicador de Auditoria Financeira
-- OBJETIVO: Calcular o percentual de não comprovação e comparativos (Medianas)
-- ============================================================================

-- ============================================================================
-- PASSO 1: CALCULO BASE POR FARMACIA (BUSCANDO DO PROCESSAMENTO MAIS RECENTE)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_auditado;

WITH UltimoProcessamento AS (
    SELECT cnpj, MAX(id) as id_processamento
    FROM temp_CGUSC.fp.processamento
    GROUP BY cnpj
)
SELECT
    CAST(U.cnpj AS VARCHAR(14)) AS cnpj,
    SUM(ISNULL(M.valor_vendas, 0)) as valor_vendas,
    SUM(ISNULL(M.valor_sem_comprovacao, 0)) as valor_sem_comprovacao,
    CAST(
        CASE
            WHEN SUM(ISNULL(M.valor_vendas, 0)) > 0 
            THEN (SUM(ISNULL(M.valor_sem_comprovacao, 0)) * 100.0) / SUM(ISNULL(M.valor_vendas, 0))
            ELSE 0
        END
    AS DECIMAL(18,2)) AS pct_auditado
INTO temp_CGUSC.fp.indicador_auditado
FROM UltimoProcessamento U
INNER JOIN temp_CGUSC.fp.movimentacao_mensal_gtin M ON M.id_processamento = U.id_processamento
GROUP BY U.cnpj;

CREATE CLUSTERED INDEX IDX_IndAudit_CNPJ ON temp_CGUSC.fp.indicador_auditado(cnpj);

-- ============================================================================
-- PASSO 2: METRICAS POR MUNICIPIO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_auditado_mun;

SELECT DISTINCT
    F.uf,
    F.municipio,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.pct_auditado, 0))
        OVER (PARTITION BY F.uf, F.municipio)
    AS DECIMAL(18,4)) AS mediana_municipio,
    CAST(
        AVG(ISNULL(I.pct_auditado, 0))
        OVER (PARTITION BY F.uf, F.municipio)
    AS DECIMAL(18,4)) AS media_municipio
INTO temp_CGUSC.fp.indicador_auditado_mun
FROM temp_CGUSC.fp.dados_farmacia F
LEFT JOIN temp_CGUSC.fp.indicador_auditado I ON I.cnpj = F.cnpj;

-- ============================================================================
-- PASSO 3: METRICAS POR ESTADO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_auditado_uf;

SELECT DISTINCT
    F.uf,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.pct_auditado, 0))
        OVER (PARTITION BY F.uf)
    AS DECIMAL(18,4)) AS mediana_estado,
    CAST(
        AVG(ISNULL(I.pct_auditado, 0))
        OVER (PARTITION BY F.uf)
    AS DECIMAL(18,4)) AS media_estado
INTO temp_CGUSC.fp.indicador_auditado_uf
FROM temp_CGUSC.fp.dados_farmacia F
LEFT JOIN temp_CGUSC.fp.indicador_auditado I ON I.cnpj = F.cnpj;

-- ============================================================================
-- PASSO 4: METRICAS POR REGIAO DE SAUDE
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_auditado_regiao;

SELECT DISTINCT
    F.id_regiao_saude,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.pct_auditado, 0))
        OVER (PARTITION BY F.id_regiao_saude)
    AS DECIMAL(18,4)) AS mediana_regiao,
    CAST(
        AVG(ISNULL(I.pct_auditado, 0))
        OVER (PARTITION BY F.id_regiao_saude)
    AS DECIMAL(18,4)) AS media_regiao
INTO temp_CGUSC.fp.indicador_auditado_regiao
FROM temp_CGUSC.fp.dados_farmacia F
LEFT JOIN temp_CGUSC.fp.indicador_auditado I ON I.cnpj = F.cnpj
WHERE F.id_regiao_saude IS NOT NULL;

-- ============================================================================
-- PASSO 5: METRICAS NACIONAIS
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_auditado_br;

SELECT DISTINCT
    'BR' AS pais,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(pct_auditado, 0)) OVER ()
    AS DECIMAL(18,4)) AS mediana_pais,
    CAST(
        AVG(ISNULL(pct_auditado, 0)) OVER ()
    AS DECIMAL(18,4)) AS media_pais
INTO temp_CGUSC.fp.indicador_auditado_br
FROM temp_CGUSC.fp.dados_farmacia F
LEFT JOIN temp_CGUSC.fp.indicador_auditado I ON I.cnpj = F.cnpj;

-- ============================================================================
-- PASSO 6: TABELA CONSOLIDADA FINAL
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_auditado_detalhado;

SELECT
    F.cnpj,
    F.razaoSocial,
    F.municipio,
    F.uf,
    F.no_regiao_saude,
    F.id_regiao_saude,

    -- Indicadores base
    ISNULL(I.pct_auditado, 0) AS pct_auditado,

    -- Benchmarks municipais
    ISNULL(MUN.mediana_municipio, 0) AS municipio_mediana,
    CAST((ISNULL(I.pct_auditado, 0) + 0.0001) / (ISNULL(MUN.mediana_municipio, 0) + 0.0001) AS DECIMAL(18,4)) AS risco_relativo_mun_mediana,

    -- Benchmarks estaduais
    ISNULL(UF.mediana_estado, 0) AS estado_mediana,
    CAST((ISNULL(I.pct_auditado, 0) + 0.0001) / (ISNULL(UF.mediana_estado, 0) + 0.0001) AS DECIMAL(18,4)) AS risco_relativo_uf_mediana,

    -- Benchmarks Regionais
    ISNULL(REG.mediana_regiao, 0) AS regiao_saude_mediana,
    CAST((ISNULL(I.pct_auditado, 0) + 0.0001) / (ISNULL(REG.mediana_regiao, 0) + 0.0001) AS DECIMAL(18,4)) AS risco_relativo_reg_mediana,

    -- Benchmarks nacionais
    BR.mediana_pais AS pais_mediana,
    CAST((ISNULL(I.pct_auditado, 0) + 0.0001) / (BR.mediana_pais + 0.0001) AS DECIMAL(18,4)) AS risco_relativo_br_mediana

INTO temp_CGUSC.fp.indicador_auditado_detalhado
FROM temp_CGUSC.fp.dados_farmacia F
LEFT JOIN temp_CGUSC.fp.indicador_auditado I
    ON I.cnpj = F.cnpj
LEFT JOIN temp_CGUSC.fp.indicador_auditado_mun MUN
    ON F.uf        = MUN.uf
   AND F.municipio = MUN.municipio
LEFT JOIN temp_CGUSC.fp.indicador_auditado_uf UF
    ON F.uf = UF.uf
LEFT JOIN temp_CGUSC.fp.indicador_auditado_regiao REG
    ON F.id_regiao_saude = REG.id_regiao_saude
CROSS JOIN temp_CGUSC.fp.indicador_auditado_br BR;

CREATE CLUSTERED INDEX IDX_FinalAudit_CNPJ ON temp_CGUSC.fp.indicador_auditado_detalhado(cnpj);

-- Limpeza
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_auditado;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_auditado_mun;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_auditado_uf;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_auditado_regiao;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_auditado_br;
GO
