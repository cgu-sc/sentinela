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
    IBGE.nu_populacao AS populacao_municipio,

    -- Per capita mensal normalizado: (total / meses) / populacao
    CAST(
        CASE
            WHEN IBGE.nu_populacao > 0 AND V.qtd_meses_ativos > 0
                THEN (V.valor_total_periodo / V.qtd_meses_ativos) / IBGE.nu_populacao
            ELSE 0
        END
    AS DECIMAL(18,4)) AS valor_per_capita_mensal

INTO temp_CGUSC.fp.indicador_venda_per_capita
FROM temp_CGUSC.fp.vol_vendas_per_capita V
INNER JOIN temp_CGUSC.fp.dados_farmacia F
    ON F.cnpj = V.cnpj
INNER JOIN temp_CGUSC.sus.tb_ibge IBGE
    ON CAST(F.codibge AS VARCHAR(7)) = IBGE.id_ibge7;

CREATE CLUSTERED INDEX IDX_IndCapita_CNPJ ON temp_CGUSC.fp.indicador_venda_per_capita(cnpj);

DROP TABLE IF EXISTS temp_CGUSC.fp.vol_vendas_per_capita;


-- ============================================================================
-- PASSO 3: METRICAS POR MUNICIPIO (MEDIA E MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_venda_per_capita_mun;

SELECT DISTINCT
    CAST(F.uf AS VARCHAR(2))          AS uf,
    CAST(F.municipio AS VARCHAR(255)) AS municipio,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.valor_per_capita_mensal)
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255)))
    AS DECIMAL(18,4)) AS mediana_municipio,
    CAST(
        AVG(I.valor_per_capita_mensal)
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255)))
    AS DECIMAL(18,4)) AS media_municipio
INTO temp_CGUSC.fp.indicador_venda_per_capita_mun
FROM temp_CGUSC.fp.indicador_venda_per_capita I
INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj;

CREATE CLUSTERED INDEX IDX_IndCapitaMun ON temp_CGUSC.fp.indicador_venda_per_capita_mun(uf, municipio);


-- ============================================================================
-- PASSO 4: METRICAS POR ESTADO (MEDIA E MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_venda_per_capita_uf;

SELECT DISTINCT
    CAST(F.uf AS VARCHAR(2)) AS uf,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.valor_per_capita_mensal)
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)))
    AS DECIMAL(18,4)) AS mediana_estado,
    CAST(
        AVG(I.valor_per_capita_mensal)
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)))
    AS DECIMAL(18,4)) AS media_estado
INTO temp_CGUSC.fp.indicador_venda_per_capita_uf
FROM temp_CGUSC.fp.indicador_venda_per_capita I
INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj;

CREATE CLUSTERED INDEX IDX_IndCapitaUF ON temp_CGUSC.fp.indicador_venda_per_capita_uf(uf);


-- ============================================================================
-- PASSO 5: METRICAS NACIONAIS (MEDIA E MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_venda_per_capita_br;

SELECT DISTINCT
    'BR' AS pais,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY valor_per_capita_mensal) OVER ()
    AS DECIMAL(18,4)) AS mediana_pais,
    CAST(
        AVG(valor_per_capita_mensal) OVER ()
    AS DECIMAL(18,4)) AS media_pais
INTO temp_CGUSC.fp.indicador_venda_per_capita_br
FROM temp_CGUSC.fp.indicador_venda_per_capita;


-- ============================================================================
-- PASSO 6: TABELA CONSOLIDADA FINAL
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_venda_per_capita_detalhado;

SELECT
    I.cnpj,
    F.razaoSocial,
    F.municipio,
    CAST(F.uf AS VARCHAR(2)) AS uf,

    -- Indicadores base
    I.valor_total_periodo,
    I.populacao_municipio,
    I.qtd_meses_ativos,
    I.valor_per_capita_mensal,

    -- Rankings (pior risco = posicao 1)
    RANK() OVER (
        ORDER BY I.valor_per_capita_mensal DESC
    ) AS ranking_br,
    RANK() OVER (
        PARTITION BY CAST(F.uf AS VARCHAR(2))
        ORDER BY I.valor_per_capita_mensal DESC
    ) AS ranking_uf,
    RANK() OVER (
        PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255))
        ORDER BY I.valor_per_capita_mensal DESC
    ) AS ranking_municipio,

    -- Benchmarks municipais
    ISNULL(MUN.mediana_municipio, 0) AS municipio_mediana,
    ISNULL(MUN.media_municipio,   0) AS municipio_media,
    CAST((I.valor_per_capita_mensal + 0.01) / (ISNULL(MUN.mediana_municipio, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_mediana,
    CAST((I.valor_per_capita_mensal + 0.01) / (ISNULL(MUN.media_municipio,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_media,

    -- Benchmarks estaduais
    ISNULL(UF.mediana_estado, 0) AS estado_mediana,
    ISNULL(UF.media_estado,   0) AS estado_media,
    CAST((I.valor_per_capita_mensal + 0.01) / (ISNULL(UF.mediana_estado, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_mediana,
    CAST((I.valor_per_capita_mensal + 0.01) / (ISNULL(UF.media_estado,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_media,

    -- Benchmarks nacionais
    BR.mediana_pais AS pais_mediana,
    BR.media_pais   AS pais_media,
    CAST((I.valor_per_capita_mensal + 0.01) / (BR.mediana_pais + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_mediana,
    CAST((I.valor_per_capita_mensal + 0.01) / (BR.media_pais   + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_media

INTO temp_CGUSC.fp.indicador_venda_per_capita_detalhado
FROM temp_CGUSC.fp.indicador_venda_per_capita I
INNER JOIN temp_CGUSC.fp.dados_farmacia F
    ON F.cnpj = I.cnpj
LEFT JOIN temp_CGUSC.fp.indicador_venda_per_capita_mun MUN
    ON CAST(F.uf AS VARCHAR(2))          = MUN.uf
   AND CAST(F.municipio AS VARCHAR(255)) = MUN.municipio
LEFT JOIN temp_CGUSC.fp.indicador_venda_per_capita_uf UF
    ON CAST(F.uf AS VARCHAR(2)) = UF.uf
CROSS JOIN temp_CGUSC.fp.indicador_venda_per_capita_br BR;

CREATE CLUSTERED INDEX IDX_FinalCapita_CNPJ      ON temp_CGUSC.fp.indicador_venda_per_capita_detalhado(cnpj);
CREATE NONCLUSTERED INDEX IDX_FinalCapita_Mensal  ON temp_CGUSC.fp.indicador_venda_per_capita_detalhado(valor_per_capita_mensal DESC);
CREATE NONCLUSTERED INDEX IDX_FinalCapita_Rank    ON temp_CGUSC.fp.indicador_venda_per_capita_detalhado(ranking_br);
GO

-- ============================================================================
-- LIMPEZA DAS TABELAS INTERMEDIARIAS
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_venda_per_capita;
GO

-- Verificacao rapida
SELECT TOP 100 *
FROM temp_CGUSC.fp.indicador_venda_per_capita_detalhado
ORDER BY ranking_br;