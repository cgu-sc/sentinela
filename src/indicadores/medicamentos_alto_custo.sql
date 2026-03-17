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
    F.uf,
    F.municipio,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.percentual_alto_custo, 0))
        OVER (PARTITION BY F.uf, F.municipio)
    AS DECIMAL(18,4)) AS mediana_municipio,
    CAST(
        AVG(ISNULL(I.percentual_alto_custo, 0))
        OVER (PARTITION BY F.uf, F.municipio)
    AS DECIMAL(18,4)) AS media_municipio
INTO temp_CGUSC.fp.indicador_alto_custo_mun
FROM temp_CGUSC.fp.dados_farmacia F
LEFT JOIN temp_CGUSC.fp.indicador_alto_custo I ON I.cnpj = F.cnpj;

CREATE CLUSTERED INDEX IDX_IndAltoCustoMun ON temp_CGUSC.fp.indicador_alto_custo_mun(uf, municipio);


-- ============================================================================
-- PASSO 3: METRICAS POR ESTADO (MEDIA E MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_alto_custo_uf;

SELECT DISTINCT
    F.uf,
    SUM(ISNULL(I.valor_total_vendido, 0))       OVER (PARTITION BY F.uf) AS total_vendido_uf,
    SUM(ISNULL(I.valor_vendas_alto_custo, 0))   OVER (PARTITION BY F.uf) AS total_alto_custo_uf,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.percentual_alto_custo, 0))
        OVER (PARTITION BY F.uf)
    AS DECIMAL(18,4)) AS mediana_estado,
    CAST(
        AVG(ISNULL(I.percentual_alto_custo, 0))
        OVER (PARTITION BY F.uf)
    AS DECIMAL(18,4)) AS media_estado
INTO temp_CGUSC.fp.indicador_alto_custo_uf
FROM temp_CGUSC.fp.dados_farmacia F
LEFT JOIN temp_CGUSC.fp.indicador_alto_custo I ON I.cnpj = F.cnpj;

CREATE CLUSTERED INDEX IDX_IndAltoCustoUF ON temp_CGUSC.fp.indicador_alto_custo_uf(uf);


-- ============================================================================
-- PASSO 3B: METRICAS POR REGIAO DE SAUDE (MEDIA E MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_alto_custo_regiao;

SELECT DISTINCT
    F.id_regiao_saude,
    SUM(ISNULL(I.valor_total_vendido, 0))       OVER (PARTITION BY F.id_regiao_saude) AS total_vendido_regiao,
    SUM(ISNULL(I.valor_vendas_alto_custo, 0))   OVER (PARTITION BY F.id_regiao_saude) AS total_alto_custo_regiao,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.percentual_alto_custo, 0))
        OVER (PARTITION BY F.id_regiao_saude)
    AS DECIMAL(18,4)) AS mediana_regiao,
    CAST(
        AVG(ISNULL(I.percentual_alto_custo, 0))
        OVER (PARTITION BY F.id_regiao_saude)
    AS DECIMAL(18,4)) AS media_regiao
INTO temp_CGUSC.fp.indicador_alto_custo_regiao
FROM temp_CGUSC.fp.dados_farmacia F
LEFT JOIN temp_CGUSC.fp.indicador_alto_custo I ON I.cnpj = F.cnpj
WHERE F.id_regiao_saude IS NOT NULL;

CREATE CLUSTERED INDEX IDX_IndAltoCustoReg ON temp_CGUSC.fp.indicador_alto_custo_regiao(id_regiao_saude);


-- ============================================================================
-- PASSO 4: METRICAS NACIONAIS (MEDIA E MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_alto_custo_br;

SELECT DISTINCT
    'BR' AS pais,
    SUM(ISNULL(valor_total_vendido, 0))     OVER () AS total_vendido_br,
    SUM(ISNULL(valor_vendas_alto_custo, 0)) OVER () AS total_alto_custo_br,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(percentual_alto_custo, 0)) OVER ()
    AS DECIMAL(18,4)) AS mediana_pais,
    CAST(
        AVG(ISNULL(percentual_alto_custo, 0)) OVER ()
    AS DECIMAL(18,4)) AS media_pais
INTO temp_CGUSC.fp.indicador_alto_custo_br
FROM temp_CGUSC.fp.dados_farmacia F
LEFT JOIN temp_CGUSC.fp.indicador_alto_custo I ON I.cnpj = F.cnpj;


-- ============================================================================
-- PASSO 5: TABELA CONSOLIDADA FINAL
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_alto_custo_detalhado;

SELECT
    F.cnpj,
    F.razaoSocial,
    F.municipio,
    F.uf,
    F.no_regiao_saude,
    F.id_regiao_saude,

    -- Indicadores base
    ISNULL(I.valor_total_vendido, 0)      AS valor_total_vendido,
    ISNULL(I.valor_vendas_alto_custo, 0)  AS valor_vendas_alto_custo,
    ISNULL(I.percentual_alto_custo, 0)    AS percentual_alto_custo,

    -- Rankings (pior risco = posicao 1)
    RANK() OVER (
        ORDER BY ISNULL(I.percentual_alto_custo, 0) DESC
    ) AS ranking_br,
    RANK() OVER (
        PARTITION BY F.uf
        ORDER BY ISNULL(I.percentual_alto_custo, 0) DESC
    ) AS ranking_uf,
    RANK() OVER (
        PARTITION BY F.id_regiao_saude
        ORDER BY ISNULL(I.percentual_alto_custo, 0) DESC
    ) AS ranking_regiao_saude,
    RANK() OVER (
        PARTITION BY F.uf, F.municipio
        ORDER BY ISNULL(I.percentual_alto_custo, 0) DESC
    ) AS ranking_municipio,

    -- Benchmarks municipais
    ISNULL(MUN.mediana_municipio, 0) AS municipio_mediana,
    ISNULL(MUN.media_municipio,   0) AS municipio_media,
    CAST((ISNULL(I.percentual_alto_custo, 0) + 0.01) / (ISNULL(MUN.mediana_municipio, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_mediana,
    CAST((ISNULL(I.percentual_alto_custo, 0) + 0.01) / (ISNULL(MUN.media_municipio,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_media,

    -- Benchmarks estaduais
    ISNULL(UF.mediana_estado, 0) AS estado_mediana,
    ISNULL(UF.media_estado,   0) AS estado_media,
    CAST((ISNULL(I.percentual_alto_custo, 0) + 0.01) / (ISNULL(UF.mediana_estado, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_mediana,
    CAST((ISNULL(I.percentual_alto_custo, 0) + 0.01) / (ISNULL(UF.media_estado,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_media,

    -- Benchmarks Regionais (Regiao de Saude)
    ISNULL(REG.mediana_regiao, 0) AS regiao_saude_mediana,
    ISNULL(REG.media_regiao,   0) AS regiao_saude_media,
    CAST((ISNULL(I.percentual_alto_custo, 0) + 0.01) / (ISNULL(REG.mediana_regiao, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_reg_mediana,
    CAST((ISNULL(I.percentual_alto_custo, 0) + 0.01) / (ISNULL(REG.media_regiao,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_reg_media,

    -- Benchmarks nacionais
    BR.mediana_pais AS pais_mediana,
    BR.media_pais   AS pais_media,
    CAST((ISNULL(I.percentual_alto_custo, 0) + 0.01) / (BR.mediana_pais + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_mediana,
    CAST((ISNULL(I.percentual_alto_custo, 0) + 0.01) / (BR.media_pais   + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_media

INTO temp_CGUSC.fp.indicador_alto_custo_detalhado
FROM temp_CGUSC.fp.dados_farmacia F
LEFT JOIN temp_CGUSC.fp.indicador_alto_custo I
    ON I.cnpj = F.cnpj
LEFT JOIN temp_CGUSC.fp.indicador_alto_custo_mun MUN
    ON F.uf        = MUN.uf
   AND F.municipio = MUN.municipio
LEFT JOIN temp_CGUSC.fp.indicador_alto_custo_uf UF
    ON F.uf = UF.uf
LEFT JOIN temp_CGUSC.fp.indicador_alto_custo_regiao REG
    ON F.id_regiao_saude = REG.id_regiao_saude
CROSS JOIN temp_CGUSC.fp.indicador_alto_custo_br BR;

CREATE CLUSTERED INDEX    IDX_FinalAltoCusto_CNPJ  ON temp_CGUSC.fp.indicador_alto_custo_detalhado(cnpj);
CREATE NONCLUSTERED INDEX IDX_FinalAltoCusto_Risco ON temp_CGUSC.fp.indicador_alto_custo_detalhado(risco_relativo_mun_mediana DESC);
CREATE NONCLUSTERED INDEX IDX_FinalAltoCusto_Rank  ON temp_CGUSC.fp.indicador_alto_custo_detalhado(ranking_br);
GO

-- ============================================================================
-- PASSO 6: LIMPEZA DAS TABELAS INTERMEDIARIAS
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_alto_custo;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_alto_custo_mun;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_alto_custo_uf;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_alto_custo_regiao;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_alto_custo_br;
GO

-- Verificacao rapida
SELECT TOP 100 *
FROM temp_CGUSC.fp.indicador_alto_custo_detalhado
ORDER BY ranking_br;
