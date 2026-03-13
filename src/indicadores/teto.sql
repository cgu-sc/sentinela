USE [temp_CGUSC]
GO

-- ============================================================================
-- DEFINICAO DE VARIAVEIS DO PERIODO
-- ============================================================================
DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim    DATE = '2024-12-10';


-- ============================================================================
-- PASSO 1: CALCULO BASE POR FARMACIA (INDICADOR TETO MAXIMO)
-- Verifica se qualquer item da autorizacao atingiu a quantidade maxima
-- permitida para o principio ativo (posto na posologia_tempo_bloqueio).
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_teto;

WITH VendasComTeto AS (
    SELECT
        A.cnpj,
        A.num_autorizacao,
        MAX(CASE
            WHEN A.qnt_autorizada >= P.QUANTIDADE_MAXIMA THEN 1
            ELSE 0
        END) AS flag_venda_atingiu_teto

    FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
    INNER JOIN temp_CGUSC.fp.medicamentos_patologia C
        ON C.codigo_barra = A.codigo_barra
    INNER JOIN temp_CGUSC.fp.posologia_tempo_bloqueio P
        ON P.PRINCIPIO_ATIVO = C.principio_ativo

    WHERE
        A.data_hora >= @DataInicio
        AND A.data_hora <= @DataFim
        AND P.QUANTIDADE_MAXIMA > 0

    GROUP BY A.cnpj, A.num_autorizacao
),
AgregadoPorFarmacia AS (
    SELECT
        cnpj,
        COUNT(*)                      AS total_vendas_monitoradas,
        SUM(flag_venda_atingiu_teto)  AS qtd_vendas_teto_maximo
    FROM VendasComTeto
    GROUP BY cnpj
)
SELECT
    cnpj,
    total_vendas_monitoradas,
    qtd_vendas_teto_maximo,
    CAST(
        CASE
            WHEN total_vendas_monitoradas > 0 THEN
                (CAST(qtd_vendas_teto_maximo AS DECIMAL(18,2)) /
                 CAST(total_vendas_monitoradas AS DECIMAL(18,2))) * 100.0
            ELSE 0
        END
    AS DECIMAL(18,4)) AS percentual_teto

INTO temp_CGUSC.fp.indicador_teto
FROM AgregadoPorFarmacia
WHERE total_vendas_monitoradas > 0;

CREATE CLUSTERED INDEX IDX_IndTeto_CNPJ ON temp_CGUSC.fp.indicador_teto(cnpj);


-- ============================================================================
-- PASSO 2: METRICAS POR MUNICIPIO (MEDIA E MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_teto_mun;

SELECT DISTINCT
    CAST(F.uf AS VARCHAR(2))          AS uf,
    CAST(F.municipio AS VARCHAR(255)) AS municipio,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.percentual_teto)
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255)))
    AS DECIMAL(18,4)) AS mediana_municipio,
    CAST(
        AVG(I.percentual_teto)
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255)))
    AS DECIMAL(18,4)) AS media_municipio
INTO temp_CGUSC.fp.indicador_teto_mun
FROM temp_CGUSC.fp.indicador_teto I
INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj;

CREATE CLUSTERED INDEX IDX_IndTetoMun ON temp_CGUSC.fp.indicador_teto_mun(uf, municipio);


-- ============================================================================
-- PASSO 3: METRICAS POR ESTADO (MEDIA E MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_teto_uf;

SELECT DISTINCT
    CAST(F.uf AS VARCHAR(2)) AS uf,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.percentual_teto)
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)))
    AS DECIMAL(18,4)) AS mediana_estado,
    CAST(
        AVG(I.percentual_teto)
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)))
    AS DECIMAL(18,4)) AS media_estado
INTO temp_CGUSC.fp.indicador_teto_uf
FROM temp_CGUSC.fp.indicador_teto I
INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj;

CREATE CLUSTERED INDEX IDX_IndTetoUF ON temp_CGUSC.fp.indicador_teto_uf(uf);


-- ============================================================================
-- PASSO 4: METRICAS NACIONAIS (MEDIA E MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_teto_br;

SELECT DISTINCT
    'BR' AS pais,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY percentual_teto) OVER ()
    AS DECIMAL(18,4)) AS mediana_pais,
    CAST(
        AVG(percentual_teto) OVER ()
    AS DECIMAL(18,4)) AS media_pais
INTO temp_CGUSC.fp.indicador_teto_br
FROM temp_CGUSC.fp.indicador_teto;


-- ============================================================================
-- PASSO 5: TABELA CONSOLIDADA FINAL
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_teto_detalhado;

SELECT
    I.cnpj,
    F.razaoSocial,
    F.municipio,
    CAST(F.uf AS VARCHAR(2)) AS uf,

    -- Indicadores base
    I.total_vendas_monitoradas,
    I.qtd_vendas_teto_maximo,
    I.percentual_teto,

    -- Rankings (pior risco = posicao 1)
    RANK() OVER (
        ORDER BY I.percentual_teto DESC
    ) AS ranking_br,
    RANK() OVER (
        PARTITION BY CAST(F.uf AS VARCHAR(2))
        ORDER BY I.percentual_teto DESC
    ) AS ranking_uf,
    RANK() OVER (
        PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255))
        ORDER BY I.percentual_teto DESC
    ) AS ranking_municipio,

    -- Benchmarks municipais
    ISNULL(MUN.mediana_municipio, 0) AS municipio_mediana,
    ISNULL(MUN.media_municipio,   0) AS municipio_media,
    CAST((I.percentual_teto + 0.01) / (ISNULL(MUN.mediana_municipio, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_mediana,
    CAST((I.percentual_teto + 0.01) / (ISNULL(MUN.media_municipio,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_media,

    -- Benchmarks estaduais
    ISNULL(UF.mediana_estado, 0) AS estado_mediana,
    ISNULL(UF.media_estado,   0) AS estado_media,
    CAST((I.percentual_teto + 0.01) / (ISNULL(UF.mediana_estado, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_mediana,
    CAST((I.percentual_teto + 0.01) / (ISNULL(UF.media_estado,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_media,

    -- Benchmarks nacionais
    BR.mediana_pais AS pais_mediana,
    BR.media_pais   AS pais_media,
    CAST((I.percentual_teto + 0.01) / (BR.mediana_pais + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_mediana,
    CAST((I.percentual_teto + 0.01) / (BR.media_pais   + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_media

INTO temp_CGUSC.fp.indicador_teto_detalhado
FROM temp_CGUSC.fp.indicador_teto I
INNER JOIN temp_CGUSC.fp.dados_farmacia F
    ON F.cnpj = I.cnpj
LEFT JOIN temp_CGUSC.fp.indicador_teto_mun MUN
    ON CAST(F.uf AS VARCHAR(2))          = MUN.uf
   AND CAST(F.municipio AS VARCHAR(255)) = MUN.municipio
LEFT JOIN temp_CGUSC.fp.indicador_teto_uf UF
    ON CAST(F.uf AS VARCHAR(2)) = UF.uf
CROSS JOIN temp_CGUSC.fp.indicador_teto_br BR;

CREATE CLUSTERED INDEX    IDX_FinalTeto_CNPJ  ON temp_CGUSC.fp.indicador_teto_detalhado(cnpj);
CREATE NONCLUSTERED INDEX IDX_FinalTeto_Risco ON temp_CGUSC.fp.indicador_teto_detalhado(risco_relativo_mun_mediana DESC);
CREATE NONCLUSTERED INDEX IDX_FinalTeto_Rank  ON temp_CGUSC.fp.indicador_teto_detalhado(ranking_br);
GO

-- Verificacao rapida
SELECT TOP 100 *
FROM temp_CGUSC.fp.indicador_teto_detalhado
ORDER BY ranking_br;
