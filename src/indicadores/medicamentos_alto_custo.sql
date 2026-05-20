USE [temp_CGUSC]
GO

-- ============================================================================
-- DEFINICAO DE VARIAVEIS DO PERIODO
-- ============================================================================
DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim    DATE = '2024-12-10';


-- ============================================================================
-- PASSO 0: CALCULAR E PERSISTIR O PRECO DE CORTE (90 PERCENTIL REGIONAL)
-- Calcula uma unica vez o valor que define o que e "Alto Custo" em cada
-- id_regiao_saude para o periodo processado, mantendo o resultado disponivel
-- para consultas detalhadas por CNPJ sem recalcular o percentil regional.
-- Filtrado por medicamentos_patologia para consistencia com o escopo auditado.
-- ============================================================================
IF OBJECT_ID('temp_CGUSC.fp.indicador_alto_custo_limite', 'U') IS NULL
BEGIN
    CREATE TABLE temp_CGUSC.fp.indicador_alto_custo_limite (
        data_inicio               DATE          NOT NULL,
        data_fim                  DATE          NOT NULL,
        percentil                 DECIMAL(5,4)  NOT NULL,
        id_regiao_saude           INT           NOT NULL,
        valor_limite_alto_custo   DECIMAL(18,2) NOT NULL,
        qtd_registros_base        BIGINT        NOT NULL,
        dt_processamento          DATETIME2(0)  NOT NULL
            CONSTRAINT DF_indicador_alto_custo_limite_dt DEFAULT SYSDATETIME()
    );
END;

IF COL_LENGTH('temp_CGUSC.fp.indicador_alto_custo_limite', 'data_inicio') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.indicador_alto_custo_limite', 'data_fim') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.indicador_alto_custo_limite', 'percentil') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.indicador_alto_custo_limite', 'id_regiao_saude') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.indicador_alto_custo_limite', 'valor_limite_alto_custo') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.indicador_alto_custo_limite', 'qtd_registros_base') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.indicador_alto_custo_limite', 'dt_processamento') IS NULL
BEGIN
    RAISERROR('Schema invalido em temp_CGUSC.fp.indicador_alto_custo_limite.', 16, 1);
END;

IF NOT EXISTS (
    SELECT 1
    FROM temp_CGUSC.sys.indexes
    WHERE object_id = OBJECT_ID('temp_CGUSC.fp.indicador_alto_custo_limite')
      AND name = 'CX_indicador_alto_custo_limite_periodo'
)
BEGIN
    CREATE UNIQUE CLUSTERED INDEX CX_indicador_alto_custo_limite_periodo
        ON temp_CGUSC.fp.indicador_alto_custo_limite(data_inicio, data_fim, percentil, id_regiao_saude);
END;

IF NOT EXISTS (
    SELECT 1
    FROM temp_CGUSC.sys.indexes
    WHERE object_id = OBJECT_ID('temp_CGUSC.fp.indicador_alto_custo_limite')
      AND name = 'IX_indicador_alto_custo_limite_regiao'
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_indicador_alto_custo_limite_regiao
        ON temp_CGUSC.fp.indicador_alto_custo_limite(id_regiao_saude, data_inicio, data_fim, percentil)
        INCLUDE (valor_limite_alto_custo, qtd_registros_base, dt_processamento);
END;

DELETE FROM temp_CGUSC.fp.indicador_alto_custo_limite
WHERE data_inicio = @DataInicio
  AND data_fim = @DataFim
  AND percentil = CAST(0.90 AS DECIMAL(5,4));

DROP TABLE IF EXISTS #BaseAltoCustoRegional;

SELECT
    F.id_regiao_saude,
    CAST(A.valor_pago AS DECIMAL(18,2)) AS valor_pago
INTO #BaseAltoCustoRegional
FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
INNER JOIN temp_CGUSC.fp.medicamentos_patologia C
    ON C.codigo_barra = A.codigo_barra
INNER JOIN temp_CGUSC.fp.dados_farmacia F
    ON F.cnpj = A.cnpj
WHERE A.data_hora >= @DataInicio
  AND A.data_hora <= @DataFim
  AND F.id_regiao_saude IS NOT NULL;

CREATE CLUSTERED INDEX CX_BaseAltoCustoRegional
    ON #BaseAltoCustoRegional(id_regiao_saude, valor_pago);

DROP TABLE IF EXISTS #LimiteAltoCustoRegional;

SELECT DISTINCT
    id_regiao_saude,
    CAST(
        PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY valor_pago)
            OVER (PARTITION BY id_regiao_saude)
        AS DECIMAL(18,2)
    ) AS valor_limite_alto_custo,
    COUNT_BIG(*) OVER (PARTITION BY id_regiao_saude) AS qtd_registros_base
INTO #LimiteAltoCustoRegional
FROM #BaseAltoCustoRegional;

CREATE UNIQUE CLUSTERED INDEX CX_LimiteAltoCustoRegional
    ON #LimiteAltoCustoRegional(id_regiao_saude);

INSERT INTO temp_CGUSC.fp.indicador_alto_custo_limite (
    data_inicio,
    data_fim,
    percentil,
    id_regiao_saude,
    valor_limite_alto_custo,
    qtd_registros_base,
    dt_processamento
)
SELECT
    @DataInicio,
    @DataFim,
    CAST(0.90 AS DECIMAL(5,4)),
    id_regiao_saude,
    valor_limite_alto_custo,
    qtd_registros_base,
    SYSDATETIME()
FROM #LimiteAltoCustoRegional;

IF NOT EXISTS (
    SELECT 1
    FROM temp_CGUSC.fp.indicador_alto_custo_limite
    WHERE data_inicio = @DataInicio
      AND data_fim = @DataFim
      AND percentil = CAST(0.90 AS DECIMAL(5,4))
)
BEGIN
    RAISERROR('Limite de alto custo nao calculado para o periodo informado.', 16, 1);
END;


-- ============================================================================
-- PASSO 1: CALCULO BASE POR FARMACIA
-- Percentual do faturamento que vem de itens de alto custo (acima do P90).
-- Filtrado por medicamentos_patologia para consistencia com demais indicadores.
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_alto_custo;

SELECT
    A.cnpj,
    SUM(A.valor_pago)                                                        AS valor_total_vendido,
    SUM(CASE WHEN A.valor_pago >= L.valor_limite_alto_custo THEN A.valor_pago ELSE 0 END) AS valor_vendas_alto_custo,
    CAST(
        CASE
            WHEN SUM(A.valor_pago) > 0 THEN
                (SUM(CASE WHEN A.valor_pago >= L.valor_limite_alto_custo THEN A.valor_pago ELSE 0 END) /
                 SUM(A.valor_pago)) * 100.0
            ELSE 0
        END
    AS DECIMAL(18,4)) AS percentual_alto_custo

INTO temp_CGUSC.fp.indicador_alto_custo
FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
INNER JOIN temp_CGUSC.fp.medicamentos_patologia C
    ON C.codigo_barra = A.codigo_barra
INNER JOIN temp_CGUSC.fp.dados_farmacia F
    ON F.cnpj = A.cnpj
INNER JOIN temp_CGUSC.fp.indicador_alto_custo_limite L
    ON L.data_inicio = @DataInicio
   AND L.data_fim = @DataFim
   AND L.percentil = CAST(0.90 AS DECIMAL(5,4))
   AND L.id_regiao_saude = F.id_regiao_saude
WHERE
    A.data_hora >= @DataInicio
    AND A.data_hora <= @DataFim
    AND F.id_regiao_saude IS NOT NULL
GROUP BY A.cnpj
HAVING SUM(A.valor_pago) > 5000; -- Filtro de corte minimo de atividade

CREATE CLUSTERED INDEX IDX_IndAltoCusto_CNPJ ON temp_CGUSC.fp.indicador_alto_custo(cnpj);


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
