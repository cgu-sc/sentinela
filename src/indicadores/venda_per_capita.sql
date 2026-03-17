USE [temp_CGUSC]
GO

-- ============================================================================
-- DEFINICAO DE VARIAVEIS
-- ============================================================================
DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim    DATE = '2024-12-10';


-- ============================================================================
-- PASSO 1: TOTAL DE VENDAS E MESES DE ATUACAO POR FARMACIA
-- Apenas medicamentos auditados, apenas CNPJs da lista de processamento
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.vol_vendas_per_capita;

SELECT
    A.cnpj,
    SUM(A.valor_pago)                                    AS valor_total_periodo,
    COUNT(DISTINCT FORMAT(A.data_hora, 'yyyyMM'))        AS qtd_meses_ativos
INTO temp_CGUSC.fp.vol_vendas_per_capita
FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
INNER JOIN temp_CGUSC.fp.medicamentos_patologia C
    ON C.codigo_barra = A.codigo_barra
INNER JOIN temp_CGUSC.fp.lista_cnpj_processamento L
    ON L.cnpj = A.cnpj
WHERE A.data_hora >= @DataInicio
  AND A.data_hora <= @DataFim
GROUP BY A.cnpj;

CREATE CLUSTERED INDEX IDX_VolCapita_CNPJ ON temp_CGUSC.fp.vol_vendas_per_capita(cnpj);


-- ============================================================================
-- PASSO 2: CALCULO BASE POR FARMACIA (VENDA PER CAPITA MENSAL)
-- Logica: (Total Vendas / Meses Ativos) / Populacao do municipio
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_venda_per_capita;

SELECT
    F.cnpj,
    V.valor_total_periodo,
    V.qtd_meses_ativos,
    CAST(
        CASE
            WHEN F.populacao2019 > 0 AND V.qtd_meses_ativos > 0
                THEN (V.valor_total_periodo / V.qtd_meses_ativos) / F.populacao2019
            ELSE 0
        END
    AS DECIMAL(18,4)) AS valor_per_capita_mensal,
    F.populacao2019 AS populacao_municipio

INTO temp_CGUSC.fp.indicador_venda_per_capita
FROM temp_CGUSC.fp.vol_vendas_per_capita V
INNER JOIN temp_CGUSC.fp.dados_farmacia F
    ON F.cnpj = V.cnpj; -- Nota: Populacao agora ja vem em F.populacao2019

CREATE CLUSTERED INDEX IDX_IndCapita_CNPJ ON temp_CGUSC.fp.indicador_venda_per_capita(cnpj);

DROP TABLE IF EXISTS temp_CGUSC.fp.vol_vendas_per_capita;


-- ============================================================================
-- PASSO 3: METRICAS POR MUNICIPIO (MEDIA E MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_venda_per_capita_mun;

SELECT DISTINCT
    F.uf,
    F.municipio,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.valor_per_capita_mensal, 0))
        OVER (PARTITION BY F.uf, F.municipio)
    AS DECIMAL(18,4)) AS mediana_municipio,
    CAST(
        AVG(ISNULL(I.valor_per_capita_mensal, 0))
        OVER (PARTITION BY F.uf, F.municipio)
    AS DECIMAL(18,4)) AS media_municipio
INTO temp_CGUSC.fp.indicador_venda_per_capita_mun
FROM temp_CGUSC.fp.dados_farmacia F
LEFT JOIN temp_CGUSC.fp.indicador_venda_per_capita I ON I.cnpj = F.cnpj;

CREATE CLUSTERED INDEX IDX_IndCapitaMun ON temp_CGUSC.fp.indicador_venda_per_capita_mun(uf, municipio);


-- ============================================================================
-- PASSO 4: METRICAS POR ESTADO (MEDIA E MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_venda_per_capita_uf;

SELECT DISTINCT
    F.uf,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.valor_per_capita_mensal, 0))
        OVER (PARTITION BY F.uf)
    AS DECIMAL(18,4)) AS mediana_estado,
    CAST(
        AVG(ISNULL(I.valor_per_capita_mensal, 0))
        OVER (PARTITION BY F.uf)
    AS DECIMAL(18,4)) AS media_estado
INTO temp_CGUSC.fp.indicador_venda_per_capita_uf
FROM temp_CGUSC.fp.dados_farmacia F
LEFT JOIN temp_CGUSC.fp.indicador_venda_per_capita I ON I.cnpj = F.cnpj;

CREATE CLUSTERED INDEX IDX_IndCapitaUF ON temp_CGUSC.fp.indicador_venda_per_capita_uf(uf);


-- ============================================================================
-- PASSO 4B: METRICAS POR REGIAO DE SAUDE (MEDIA E MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_venda_per_capita_regiao;

SELECT DISTINCT
    F.id_regiao_saude,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.valor_per_capita_mensal, 0))
        OVER (PARTITION BY F.id_regiao_saude)
    AS DECIMAL(18,4)) AS mediana_regiao,
    CAST(
        AVG(ISNULL(I.valor_per_capita_mensal, 0))
        OVER (PARTITION BY F.id_regiao_saude)
    AS DECIMAL(18,4)) AS media_regiao
INTO temp_CGUSC.fp.indicador_venda_per_capita_regiao
FROM temp_CGUSC.fp.dados_farmacia F
LEFT JOIN temp_CGUSC.fp.indicador_venda_per_capita I ON I.cnpj = F.cnpj
WHERE F.id_regiao_saude IS NOT NULL;

CREATE CLUSTERED INDEX IDX_IndCapitaReg ON temp_CGUSC.fp.indicador_venda_per_capita_regiao(id_regiao_saude);


-- ============================================================================
-- PASSO 5: METRICAS NACIONAIS (MEDIA E MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_venda_per_capita_br;

SELECT DISTINCT
    'BR' AS pais,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(valor_per_capita_mensal, 0)) OVER ()
    AS DECIMAL(18,4)) AS mediana_pais,
    CAST(
        AVG(ISNULL(valor_per_capita_mensal, 0)) OVER ()
    AS DECIMAL(18,4)) AS media_pais
INTO temp_CGUSC.fp.indicador_venda_per_capita_br
FROM temp_CGUSC.fp.dados_farmacia F
LEFT JOIN temp_CGUSC.fp.indicador_venda_per_capita I ON I.cnpj = F.cnpj;


-- ============================================================================
-- PASSO 6: TABELA CONSOLIDADA FINAL
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_venda_per_capita_detalhado;

SELECT
    F.cnpj,
    F.razaoSocial,
    F.municipio,
    F.uf,
    F.no_regiao_saude,
    F.id_regiao_saude,

    -- Indicadores base
    ISNULL(I.valor_total_periodo, 0)      AS valor_total_periodo,
    F.populacao2019                       AS populacao_municipio,
    ISNULL(I.qtd_meses_ativos, 0)         AS qtd_meses_ativos,
    ISNULL(I.valor_per_capita_mensal, 0)  AS valor_per_capita_mensal,

    -- Rankings (pior risco = posicao 1)
    RANK() OVER (
        ORDER BY ISNULL(I.valor_per_capita_mensal, 0) DESC
    ) AS ranking_br,
    RANK() OVER (
        PARTITION BY F.uf
        ORDER BY ISNULL(I.valor_per_capita_mensal, 0) DESC
    ) AS ranking_uf,
    RANK() OVER (
        PARTITION BY F.id_regiao_saude
        ORDER BY ISNULL(I.valor_per_capita_mensal, 0) DESC
    ) AS ranking_regiao_saude,
    RANK() OVER (
        PARTITION BY F.uf, F.municipio
        ORDER BY ISNULL(I.valor_per_capita_mensal, 0) DESC
    ) AS ranking_municipio,

    -- Benchmarks municipais
    ISNULL(MUN.mediana_municipio, 0) AS municipio_mediana,
    ISNULL(MUN.media_municipio,   0) AS municipio_media,
    CAST((ISNULL(I.valor_per_capita_mensal, 0) + 0.01) / (ISNULL(MUN.mediana_municipio, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_mediana,
    CAST((ISNULL(I.valor_per_capita_mensal, 0) + 0.01) / (ISNULL(MUN.media_municipio,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_media,

    -- Benchmarks estaduais
    ISNULL(UF.mediana_estado, 0) AS estado_mediana,
    ISNULL(UF.media_estado,   0) AS estado_media,
    CAST((ISNULL(I.valor_per_capita_mensal, 0) + 0.01) / (ISNULL(UF.mediana_estado, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_mediana,
    CAST((ISNULL(I.valor_per_capita_mensal, 0) + 0.01) / (ISNULL(UF.media_estado,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_media,

    -- Benchmarks Regionais (Regiao de Saude)
    ISNULL(REG.mediana_regiao, 0) AS regiao_saude_mediana,
    ISNULL(REG.media_regiao,   0) AS regiao_saude_media,
    CAST((ISNULL(I.valor_per_capita_mensal, 0) + 0.01) / (ISNULL(REG.mediana_regiao, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_reg_mediana,
    CAST((ISNULL(I.valor_per_capita_mensal, 0) + 0.01) / (ISNULL(REG.media_regiao,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_reg_media,

    -- Benchmarks nacionais
    BR.mediana_pais AS pais_mediana,
    BR.media_pais   AS pais_media,
    CAST((ISNULL(I.valor_per_capita_mensal, 0) + 0.01) / (BR.mediana_pais + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_mediana,
    CAST((ISNULL(I.valor_per_capita_mensal, 0) + 0.01) / (BR.media_pais   + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_media

INTO temp_CGUSC.fp.indicador_venda_per_capita_detalhado
FROM temp_CGUSC.fp.dados_farmacia F
LEFT JOIN temp_CGUSC.fp.indicador_venda_per_capita I
    ON I.cnpj = F.cnpj
LEFT JOIN temp_CGUSC.fp.indicador_venda_per_capita_mun MUN
    ON F.uf        = MUN.uf
   AND F.municipio = MUN.municipio
LEFT JOIN temp_CGUSC.fp.indicador_venda_per_capita_uf UF
    ON F.uf = UF.uf
LEFT JOIN temp_CGUSC.fp.indicador_venda_per_capita_regiao REG
    ON F.id_regiao_saude = REG.id_regiao_saude
CROSS JOIN temp_CGUSC.fp.indicador_venda_per_capita_br BR;

CREATE CLUSTERED INDEX IDX_FinalCapita_CNPJ      ON temp_CGUSC.fp.indicador_venda_per_capita_detalhado(cnpj);
CREATE NONCLUSTERED INDEX IDX_FinalCapita_Mensal  ON temp_CGUSC.fp.indicador_venda_per_capita_detalhado(valor_per_capita_mensal DESC);
CREATE NONCLUSTERED INDEX IDX_FinalCapita_Rank    ON temp_CGUSC.fp.indicador_venda_per_capita_detalhado(ranking_br);
GO

-- ============================================================================
-- LIMPEZA DAS TABELAS INTERMEDIARIAS
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_venda_per_capita;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_venda_per_capita_mun;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_venda_per_capita_uf;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_venda_per_capita_regiao;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_venda_per_capita_br;
GO

-- Verificacao rapida
SELECT TOP 100 *
FROM temp_CGUSC.fp.indicador_venda_per_capita_detalhado
ORDER BY ranking_br;