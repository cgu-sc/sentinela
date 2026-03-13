USE [temp_CGUSC]
GO

-- ============================================================================
-- DEFINICAO DE VARIAVEIS DO PERIODO
-- ============================================================================
DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim    DATE = '2024-12-10';


-- ============================================================================
-- PASSO 0: CALCULAR O PRECO DE CORTE (90 PERCENTIL GLOBAL)
-- Calcula uma unica vez o valor que define o que e "Alto Custo".
-- Filtrado por medicamentos_patologia para consistencia com o escopo auditado.
-- ============================================================================
DROP TABLE IF EXISTS #LimiteAltoCusto;

SELECT DISTINCT
    PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY A.valor_pago) OVER () AS valor_limite
INTO #LimiteAltoCusto
FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
INNER JOIN temp_CGUSC.fp.medicamentos_patologia C
    ON C.codigo_barra = A.codigo_barra
WHERE A.data_hora >= @DataInicio
  AND A.data_hora <= @DataFim;

CREATE CLUSTERED INDEX IDX_Limite ON #LimiteAltoCusto(valor_limite);


-- ============================================================================
-- PASSO 1: CALCULO BASE POR FARMACIA
-- Percentual do faturamento que vem de itens de alto custo (acima do P90).
-- Filtrado por medicamentos_patologia para consistencia com demais indicadores.
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_alto_custo;

SELECT
    A.cnpj,
    SUM(A.valor_pago)                                                        AS valor_total_vendido,
    SUM(CASE WHEN A.valor_pago >= L.valor_limite THEN A.valor_pago ELSE 0 END) AS valor_vendas_alto_custo,
    CAST(
        CASE
            WHEN SUM(A.valor_pago) > 0 THEN
                (SUM(CASE WHEN A.valor_pago >= L.valor_limite THEN A.valor_pago ELSE 0 END) /
                 SUM(A.valor_pago)) * 100.0
            ELSE 0
        END
    AS DECIMAL(18,4)) AS percentual_alto_custo

INTO temp_CGUSC.fp.indicador_alto_custo
FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
INNER JOIN temp_CGUSC.fp.medicamentos_patologia C
    ON C.codigo_barra = A.codigo_barra
CROSS JOIN #LimiteAltoCusto L
WHERE
    A.data_hora >= @DataInicio
    AND A.data_hora <= @DataFim
GROUP BY A.cnpj
HAVING SUM(A.valor_pago) > 5000; -- Filtro de corte minimo de atividade

CREATE CLUSTERED INDEX IDX_IndAltoCusto_CNPJ ON temp_CGUSC.fp.indicador_alto_custo(cnpj);

DROP TABLE #LimiteAltoCusto;


-- ============================================================================
-- PASSO 2: METRICAS POR MUNICIPIO (MEDIA E MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_alto_custo_mun;

SELECT DISTINCT
    CAST(F.uf AS VARCHAR(2))          AS uf,
    CAST(F.municipio AS VARCHAR(255)) AS municipio,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.percentual_alto_custo)
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255)))
    AS DECIMAL(18,4)) AS mediana_municipio,
    CAST(
        AVG(I.percentual_alto_custo)
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255)))
    AS DECIMAL(18,4)) AS media_municipio
INTO temp_CGUSC.fp.indicador_alto_custo_mun
FROM temp_CGUSC.fp.indicador_alto_custo I
INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj;

CREATE CLUSTERED INDEX IDX_IndAltoCustoMun ON temp_CGUSC.fp.indicador_alto_custo_mun(uf, municipio);


-- ============================================================================
-- PASSO 3: METRICAS POR ESTADO (MEDIA E MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_alto_custo_uf;

SELECT DISTINCT
    CAST(F.uf AS VARCHAR(2)) AS uf,
    SUM(I.valor_total_vendido)       OVER (PARTITION BY CAST(F.uf AS VARCHAR(2))) AS total_vendido_uf,
    SUM(I.valor_vendas_alto_custo)   OVER (PARTITION BY CAST(F.uf AS VARCHAR(2))) AS total_alto_custo_uf,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.percentual_alto_custo)
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)))
    AS DECIMAL(18,4)) AS mediana_estado,
    CAST(
        AVG(I.percentual_alto_custo)
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)))
    AS DECIMAL(18,4)) AS media_estado
INTO temp_CGUSC.fp.indicador_alto_custo_uf
FROM temp_CGUSC.fp.indicador_alto_custo I
INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj;

CREATE CLUSTERED INDEX IDX_IndAltoCustoUF ON temp_CGUSC.fp.indicador_alto_custo_uf(uf);


-- ============================================================================
-- PASSO 4: METRICAS NACIONAIS (MEDIA E MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_alto_custo_br;

SELECT DISTINCT
    'BR' AS pais,
    SUM(valor_total_vendido)     OVER () AS total_vendido_br,
    SUM(valor_vendas_alto_custo) OVER () AS total_alto_custo_br,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY percentual_alto_custo) OVER ()
    AS DECIMAL(18,4)) AS mediana_pais,
    CAST(
        AVG(percentual_alto_custo) OVER ()
    AS DECIMAL(18,4)) AS media_pais
INTO temp_CGUSC.fp.indicador_alto_custo_br
FROM temp_CGUSC.fp.indicador_alto_custo;


-- ============================================================================
-- PASSO 5: TABELA CONSOLIDADA FINAL
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_alto_custo_detalhado;

SELECT
    I.cnpj,
    F.razaoSocial,
    F.municipio,
    CAST(F.uf AS VARCHAR(2)) AS uf,

    -- Indicadores base
    I.valor_total_vendido,
    I.valor_vendas_alto_custo,
    I.percentual_alto_custo,

    -- Rankings (pior risco = posicao 1)
    RANK() OVER (
        ORDER BY I.percentual_alto_custo DESC
    ) AS ranking_br,
    RANK() OVER (
        PARTITION BY CAST(F.uf AS VARCHAR(2))
        ORDER BY I.percentual_alto_custo DESC
    ) AS ranking_uf,
    RANK() OVER (
        PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255))
        ORDER BY I.percentual_alto_custo DESC
    ) AS ranking_municipio,

    -- Benchmarks municipais
    ISNULL(MUN.mediana_municipio, 0) AS municipio_mediana,
    ISNULL(MUN.media_municipio,   0) AS municipio_media,
    CAST((I.percentual_alto_custo + 0.01) / (ISNULL(MUN.mediana_municipio, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_mediana,
    CAST((I.percentual_alto_custo + 0.01) / (ISNULL(MUN.media_municipio,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_media,

    -- Benchmarks estaduais
    ISNULL(UF.mediana_estado, 0) AS estado_mediana,
    ISNULL(UF.media_estado,   0) AS estado_media,
    CAST((I.percentual_alto_custo + 0.01) / (ISNULL(UF.mediana_estado, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_mediana,
    CAST((I.percentual_alto_custo + 0.01) / (ISNULL(UF.media_estado,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_media,

    -- Benchmarks nacionais
    BR.mediana_pais AS pais_mediana,
    BR.media_pais   AS pais_media,
    CAST((I.percentual_alto_custo + 0.01) / (BR.mediana_pais + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_mediana,
    CAST((I.percentual_alto_custo + 0.01) / (BR.media_pais   + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_media

INTO temp_CGUSC.fp.indicador_alto_custo_detalhado
FROM temp_CGUSC.fp.indicador_alto_custo I
INNER JOIN temp_CGUSC.fp.dados_farmacia F
    ON F.cnpj = I.cnpj
LEFT JOIN temp_CGUSC.fp.indicador_alto_custo_mun MUN
    ON CAST(F.uf AS VARCHAR(2))          = MUN.uf
   AND CAST(F.municipio AS VARCHAR(255)) = MUN.municipio
LEFT JOIN temp_CGUSC.fp.indicador_alto_custo_uf UF
    ON CAST(F.uf AS VARCHAR(2)) = UF.uf
CROSS JOIN temp_CGUSC.fp.indicador_alto_custo_br BR;

CREATE CLUSTERED INDEX    IDX_FinalAltoCusto_CNPJ  ON temp_CGUSC.fp.indicador_alto_custo_detalhado(cnpj);
CREATE NONCLUSTERED INDEX IDX_FinalAltoCusto_Risco ON temp_CGUSC.fp.indicador_alto_custo_detalhado(risco_relativo_mun_mediana DESC);
CREATE NONCLUSTERED INDEX IDX_FinalAltoCusto_Rank  ON temp_CGUSC.fp.indicador_alto_custo_detalhado(ranking_br);
GO

-- Verificacao rapida
SELECT TOP 100 *
FROM temp_CGUSC.fp.indicador_alto_custo_detalhado
ORDER BY ranking_br;
