USE [temp_CGUSC]
GO

-- ============================================================================
-- DEFINICAO DE VARIAVEIS
-- ============================================================================
DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim    DATE = '2024-12-10';


-- ============================================================================
-- PASSO 1: PRE-CALCULO - AGRUPAR ITENS POR CUPOM (MEDICAMENTOS AUDITADOS)
-- Identifica quantos itens monitorados existem em cada autorizacao.
-- Usamos tabela temporaria (#) pois e mais rapido para volumes massivos.
-- ============================================================================
DROP TABLE IF EXISTS #VendasPorCupom;

SELECT
    A.cnpj,
    A.num_autorizacao,
    COUNT(*) AS qtd_itens_distintos
INTO #VendasPorCupom
FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
INNER JOIN temp_CGUSC.fp.medicamentos_patologia C
    ON C.codigo_barra = A.codigo_barra
WHERE
    A.data_hora >= @DataInicio
    AND A.data_hora <= @DataFim
GROUP BY A.cnpj, A.num_autorizacao;

CREATE CLUSTERED INDEX IDX_TempCupom_CNPJ ON #VendasPorCupom(cnpj);


-- ============================================================================
-- PASSO 2: CALCULO BASE POR FARMACIA (INDICADOR POLIMEDICAMENTO)
-- Conta cupons com 4 ou mais itens monitorados (Cesta Cheia).
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_polimedicamento;

SELECT
    cnpj,
    COUNT(*)                                                            AS total_cupons_monitorados,
    SUM(CASE WHEN qtd_itens_distintos >= 4 THEN 1 ELSE 0 END)          AS qtd_cupons_suspeitos,
    CAST(
        CASE
            WHEN COUNT(*) > 0 THEN
                (CAST(SUM(CASE WHEN qtd_itens_distintos >= 4 THEN 1 ELSE 0 END) AS DECIMAL(18,2)) /
                 CAST(COUNT(*) AS DECIMAL(18,2))) * 100.0
            ELSE 0
        END
    AS DECIMAL(18,4)) AS percentual_polimedicamento

INTO temp_CGUSC.fp.indicador_polimedicamento
FROM #VendasPorCupom
GROUP BY cnpj;

CREATE CLUSTERED INDEX IDX_IndPoli_CNPJ ON temp_CGUSC.fp.indicador_polimedicamento(cnpj);

DROP TABLE #VendasPorCupom;


-- ============================================================================
-- PASSO 3: METRICAS POR MUNICIPIO (MEDIA E MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_polimedicamento_mun;

SELECT DISTINCT
    CAST(F.uf AS VARCHAR(2))          AS uf,
    CAST(F.municipio AS VARCHAR(255)) AS municipio,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.percentual_polimedicamento)
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255)))
    AS DECIMAL(18,4)) AS mediana_municipio,
    CAST(
        AVG(I.percentual_polimedicamento)
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255)))
    AS DECIMAL(18,4)) AS media_municipio
INTO temp_CGUSC.fp.indicador_polimedicamento_mun
FROM temp_CGUSC.fp.indicador_polimedicamento I
INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj;

CREATE CLUSTERED INDEX IDX_IndPoliMun ON temp_CGUSC.fp.indicador_polimedicamento_mun(uf, municipio);


-- ============================================================================
-- PASSO 4: METRICAS POR ESTADO (MEDIA E MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_polimedicamento_uf;

SELECT DISTINCT
    CAST(F.uf AS VARCHAR(2)) AS uf,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.percentual_polimedicamento)
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)))
    AS DECIMAL(18,4)) AS mediana_estado,
    CAST(
        AVG(I.percentual_polimedicamento)
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)))
    AS DECIMAL(18,4)) AS media_estado
INTO temp_CGUSC.fp.indicador_polimedicamento_uf
FROM temp_CGUSC.fp.indicador_polimedicamento I
INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj;

CREATE CLUSTERED INDEX IDX_IndPoliUF ON temp_CGUSC.fp.indicador_polimedicamento_uf(uf);


-- ============================================================================
-- PASSO 5: METRICAS NACIONAIS (MEDIA E MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_polimedicamento_br;

SELECT DISTINCT
    'BR' AS pais,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY percentual_polimedicamento) OVER ()
    AS DECIMAL(18,4)) AS mediana_pais,
    CAST(
        AVG(percentual_polimedicamento) OVER ()
    AS DECIMAL(18,4)) AS media_pais
INTO temp_CGUSC.fp.indicador_polimedicamento_br
FROM temp_CGUSC.fp.indicador_polimedicamento;


-- ============================================================================
-- PASSO 6: TABELA CONSOLIDADA FINAL
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_polimedicamento_detalhado;

SELECT
    I.cnpj,
    F.razaoSocial,
    F.municipio,
    CAST(F.uf AS VARCHAR(2)) AS uf,

    -- Indicadores base
    I.total_cupons_monitorados,
    I.qtd_cupons_suspeitos,
    I.percentual_polimedicamento,

    -- Rankings (pior risco = posicao 1)
    RANK() OVER (
        ORDER BY I.percentual_polimedicamento DESC
    ) AS ranking_br,
    RANK() OVER (
        PARTITION BY CAST(F.uf AS VARCHAR(2))
        ORDER BY I.percentual_polimedicamento DESC
    ) AS ranking_uf,
    RANK() OVER (
        PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255))
        ORDER BY I.percentual_polimedicamento DESC
    ) AS ranking_municipio,

    -- Benchmarks municipais
    ISNULL(MUN.mediana_municipio, 0) AS municipio_mediana,
    ISNULL(MUN.media_municipio,   0) AS municipio_media,
    CAST((I.percentual_polimedicamento + 0.01) / (ISNULL(MUN.mediana_municipio, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_mediana,
    CAST((I.percentual_polimedicamento + 0.01) / (ISNULL(MUN.media_municipio,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_media,

    -- Benchmarks estaduais
    ISNULL(UF.mediana_estado, 0) AS estado_mediana,
    ISNULL(UF.media_estado,   0) AS estado_media,
    CAST((I.percentual_polimedicamento + 0.01) / (ISNULL(UF.mediana_estado, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_mediana,
    CAST((I.percentual_polimedicamento + 0.01) / (ISNULL(UF.media_estado,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_media,

    -- Benchmarks nacionais
    BR.mediana_pais AS pais_mediana,
    BR.media_pais   AS pais_media,
    CAST((I.percentual_polimedicamento + 0.01) / (BR.mediana_pais + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_mediana,
    CAST((I.percentual_polimedicamento + 0.01) / (BR.media_pais   + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_media

INTO temp_CGUSC.fp.indicador_polimedicamento_detalhado
FROM temp_CGUSC.fp.indicador_polimedicamento I
INNER JOIN temp_CGUSC.fp.dados_farmacia F
    ON F.cnpj = I.cnpj
LEFT JOIN temp_CGUSC.fp.indicador_polimedicamento_mun MUN
    ON CAST(F.uf AS VARCHAR(2))          = MUN.uf
   AND CAST(F.municipio AS VARCHAR(255)) = MUN.municipio
LEFT JOIN temp_CGUSC.fp.indicador_polimedicamento_uf UF
    ON CAST(F.uf AS VARCHAR(2)) = UF.uf
CROSS JOIN temp_CGUSC.fp.indicador_polimedicamento_br BR;

CREATE CLUSTERED INDEX    IDX_FinalPoli_CNPJ  ON temp_CGUSC.fp.indicador_polimedicamento_detalhado(cnpj);
CREATE NONCLUSTERED INDEX IDX_FinalPoli_Risco ON temp_CGUSC.fp.indicador_polimedicamento_detalhado(risco_relativo_mun_mediana DESC);
CREATE NONCLUSTERED INDEX IDX_FinalPoli_Rank  ON temp_CGUSC.fp.indicador_polimedicamento_detalhado(ranking_br);
GO

-- Verificacao rapida
SELECT TOP 100 *
FROM temp_CGUSC.fp.indicador_polimedicamento_detalhado
ORDER BY ranking_br;
