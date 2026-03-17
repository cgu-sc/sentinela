USE [temp_CGUSC]
GO

-- ============================================================================
-- DEFINICAO DE VARIAVEIS
-- ============================================================================
DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim    DATE = '2024-12-10';


-- ============================================================================
-- PASSO 1: PRE-CALCULO - CONTAGEM DE ITENS POR AUTORIZACAO
-- Agrupa os medicamentos monitorados dentro de cada autorizacao unica.
-- Tabela temporaria (#) para performance em grandes volumes.
-- ============================================================================
DROP TABLE IF EXISTS #ContagemItensAutorizacao;

SELECT
    A.cnpj,
    A.num_autorizacao,
    COUNT(*) AS qtd_itens
INTO #ContagemItensAutorizacao
FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
INNER JOIN temp_CGUSC.fp.medicamentos_patologia C
    ON C.codigo_barra = A.codigo_barra
WHERE
    A.data_hora >= @DataInicio
    AND A.data_hora <= @DataFim
GROUP BY A.cnpj, A.num_autorizacao;

CREATE CLUSTERED INDEX IDX_TempCont_CNPJ ON #ContagemItensAutorizacao(cnpj);



-- ============================================================================
-- PASSO 2: CALCULO BASE POR FARMACIA (MEDIA DE ITENS POR AUTORIZACAO)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_media_itens;

SELECT
    cnpj,
    SUM(qtd_itens) AS total_medicamentos_vendidos,
    COUNT(*)       AS total_autorizacoes,

    -- Media de itens por autorizacao (ex: 2.5 itens por venda)
    CAST(
        CASE
            WHEN COUNT(*) > 0 THEN
                CAST(SUM(qtd_itens) AS DECIMAL(18,2)) /
                CAST(COUNT(*)       AS DECIMAL(18,2))
            ELSE 0
        END
    AS DECIMAL(18,4)) AS media_itens_autorizacao

INTO temp_CGUSC.fp.indicador_media_itens
FROM #ContagemItensAutorizacao
GROUP BY cnpj;

CREATE CLUSTERED INDEX IDX_IndMedia_CNPJ ON temp_CGUSC.fp.indicador_media_itens(cnpj);

DROP TABLE #ContagemItensAutorizacao;


-- ============================================================================
-- PASSO 3: METRICAS POR MUNICIPIO (MEDIA E MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_media_itens_mun;

SELECT DISTINCT
    F.uf,
    F.municipio,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.media_itens_autorizacao, 0))
        OVER (PARTITION BY F.uf, F.municipio)
    AS DECIMAL(18,4)) AS mediana_municipio,
    CAST(
        AVG(ISNULL(I.media_itens_autorizacao, 0))
        OVER (PARTITION BY F.uf, F.municipio)
    AS DECIMAL(18,4)) AS media_municipio
INTO temp_CGUSC.fp.indicador_media_itens_mun
FROM temp_CGUSC.fp.dados_farmacia F
LEFT JOIN temp_CGUSC.fp.indicador_media_itens I ON I.cnpj = F.cnpj;

CREATE CLUSTERED INDEX IDX_IndMediaMun ON temp_CGUSC.fp.indicador_media_itens_mun(uf, municipio);


-- ============================================================================
-- PASSO 4: METRICAS POR ESTADO (MEDIA E MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_media_itens_uf;

SELECT DISTINCT
    F.uf,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.media_itens_autorizacao, 0))
        OVER (PARTITION BY F.uf)
    AS DECIMAL(18,4)) AS mediana_estado,
    CAST(
        AVG(ISNULL(I.media_itens_autorizacao, 0))
        OVER (PARTITION BY F.uf)
    AS DECIMAL(18,4)) AS media_estado
INTO temp_CGUSC.fp.indicador_media_itens_uf
FROM temp_CGUSC.fp.dados_farmacia F
LEFT JOIN temp_CGUSC.fp.indicador_media_itens I ON I.cnpj = F.cnpj;

CREATE CLUSTERED INDEX IDX_IndMediaUF_uf ON temp_CGUSC.fp.indicador_media_itens_uf(uf);


-- ============================================================================
-- PASSO 4B: METRICAS POR REGIAO DE SAUDE (MEDIA E MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_media_itens_regiao;

SELECT DISTINCT
    F.id_regiao_saude,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.media_itens_autorizacao, 0))
        OVER (PARTITION BY F.id_regiao_saude)
    AS DECIMAL(18,4)) AS mediana_regiao,
    CAST(
        AVG(ISNULL(I.media_itens_autorizacao, 0))
        OVER (PARTITION BY F.id_regiao_saude)
    AS DECIMAL(18,4)) AS media_regiao
INTO temp_CGUSC.fp.indicador_media_itens_regiao
FROM temp_CGUSC.fp.dados_farmacia F
LEFT JOIN temp_CGUSC.fp.indicador_media_itens I ON I.cnpj = F.cnpj
WHERE F.id_regiao_saude IS NOT NULL;

CREATE CLUSTERED INDEX IDX_IndMediaReg ON temp_CGUSC.fp.indicador_media_itens_regiao(id_regiao_saude);


-- ============================================================================
-- PASSO 5: METRICAS NACIONAIS (MEDIA E MEDIANA)
-- Usa SELECT TOP 1 para garantir exatamente 1 linha no CROSS JOIN posterior.
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_media_itens_br;

SELECT DISTINCT
    'BR' AS pais,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(media_itens_autorizacao, 0)) OVER ()
    AS DECIMAL(18,4)) AS mediana_pais,
    CAST(
        AVG(ISNULL(media_itens_autorizacao, 0)) OVER ()
    AS DECIMAL(18,4)) AS media_pais
INTO temp_CGUSC.fp.indicador_media_itens_br
FROM temp_CGUSC.fp.dados_farmacia F
LEFT JOIN temp_CGUSC.fp.indicador_media_itens I ON I.cnpj = F.cnpj;


-- ============================================================================
-- PASSO 6: TABELA CONSOLIDADA FINAL (COMPARATIVO DE RISCO)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_media_itens_detalhado;

SELECT
    F.cnpj,
    F.razaoSocial,
    F.municipio,
    F.uf,
    F.no_regiao_saude,
    F.id_regiao_saude,

    -- Indicadores base
    ISNULL(I.total_medicamentos_vendidos, 0) AS total_medicamentos_vendidos,
    ISNULL(I.total_autorizacoes, 0)           AS total_autorizacoes,
    ISNULL(I.media_itens_autorizacao, 0)      AS media_itens_autorizacao,

    -- Rankings (maior media = maior risco = posicao 1)
    RANK() OVER (
        ORDER BY ISNULL(I.media_itens_autorizacao, 0) DESC
    ) AS ranking_br,
    RANK() OVER (
        PARTITION BY F.uf
        ORDER BY ISNULL(I.media_itens_autorizacao, 0) DESC
    ) AS ranking_uf,
    RANK() OVER (
        PARTITION BY F.id_regiao_saude
        ORDER BY ISNULL(I.media_itens_autorizacao, 0) DESC
    ) AS ranking_regiao_saude,
    RANK() OVER (
        PARTITION BY F.uf, F.municipio
        ORDER BY ISNULL(I.media_itens_autorizacao, 0) DESC
    ) AS ranking_municipio,

    -- Benchmarks municipais
    ISNULL(MUN.mediana_municipio, 0) AS municipio_mediana,
    ISNULL(MUN.media_municipio,   0) AS municipio_media,
    CAST((ISNULL(I.media_itens_autorizacao, 0) + 0.01) / (ISNULL(MUN.mediana_municipio, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_mediana,
    CAST((ISNULL(I.media_itens_autorizacao, 0) + 0.01) / (ISNULL(MUN.media_municipio,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_media,

    -- Benchmarks estaduais
    ISNULL(UF.mediana_estado, 0) AS estado_mediana,
    ISNULL(UF.media_estado,   0) AS estado_media,
    CAST((ISNULL(I.media_itens_autorizacao, 0) + 0.01) / (ISNULL(UF.mediana_estado, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_mediana,
    CAST((ISNULL(I.media_itens_autorizacao, 0) + 0.01) / (ISNULL(UF.media_estado,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_media,

    -- Benchmarks Regionais (Regiao de Saude)
    ISNULL(REG.mediana_regiao, 0) AS regiao_saude_mediana,
    ISNULL(REG.media_regiao,   0) AS regiao_saude_media,
    CAST((ISNULL(I.media_itens_autorizacao, 0) + 0.01) / (ISNULL(REG.mediana_regiao, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_reg_mediana,
    CAST((ISNULL(I.media_itens_autorizacao, 0) + 0.01) / (ISNULL(REG.media_regiao,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_reg_media,

    -- Benchmarks nacionais
    BR.mediana_pais AS pais_mediana,
    BR.media_pais   AS pais_media,
    CAST((ISNULL(I.media_itens_autorizacao, 0) + 0.01) / (BR.mediana_pais + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_mediana,
    CAST((ISNULL(I.media_itens_autorizacao, 0) + 0.01) / (BR.media_pais   + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_media

INTO temp_CGUSC.fp.indicador_media_itens_detalhado
FROM temp_CGUSC.fp.dados_farmacia F
LEFT JOIN temp_CGUSC.fp.indicador_media_itens I
    ON I.cnpj = F.cnpj
LEFT JOIN temp_CGUSC.fp.indicador_media_itens_mun MUN
    ON  F.uf        = MUN.uf
    AND F.municipio = MUN.municipio
LEFT JOIN temp_CGUSC.fp.indicador_media_itens_uf UF
    ON F.uf = UF.uf
LEFT JOIN temp_CGUSC.fp.indicador_media_itens_regiao REG
    ON F.id_regiao_saude = REG.id_regiao_saude
CROSS JOIN temp_CGUSC.fp.indicador_media_itens_br BR;

CREATE CLUSTERED INDEX    IDX_FinalMedia_CNPJ  ON temp_CGUSC.fp.indicador_media_itens_detalhado(cnpj);
CREATE NONCLUSTERED INDEX IDX_FinalMedia_Risco ON temp_CGUSC.fp.indicador_media_itens_detalhado(risco_relativo_mun_mediana DESC);
CREATE NONCLUSTERED INDEX IDX_FinalMedia_Rank  ON temp_CGUSC.fp.indicador_media_itens_detalhado(ranking_br);
GO

-- ============================================================================
-- PASSO 7: LIMPEZA DAS TABELAS INTERMEDIARIAS
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_media_itens;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_media_itens_mun;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_media_itens_uf;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_media_itens_regiao;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_media_itens_br;
GO

-- Verificacao rapida
SELECT TOP 100 *
FROM temp_CGUSC.fp.indicador_media_itens_detalhado
ORDER BY ranking_br;
