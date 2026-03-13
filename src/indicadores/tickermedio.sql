USE [temp_CGUSC]
GO

-- ============================================================================
-- DEFINICAO DE VARIAVEIS
-- ============================================================================
DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim    DATE = '2024-12-10';


-- ============================================================================
-- PASSO 1: PRE-CALCULO - VALOR TOTAL POR CUPOM (MEDICAMENTOS AUDITADOS)
-- Agrupa os itens para saber quanto custou cada autorizacao inteira.
-- ============================================================================
DROP TABLE IF EXISTS #ValorPorCupom;

SELECT
    A.cnpj,
    A.num_autorizacao,
    SUM(A.valor_pago) AS valor_total_cupom
INTO #ValorPorCupom
FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
INNER JOIN temp_CGUSC.fp.medicamentos_patologia C
    ON C.codigo_barra = A.codigo_barra
WHERE
    A.data_hora >= @DataInicio
    AND A.data_hora <= @DataFim
GROUP BY A.cnpj, A.num_autorizacao;

CREATE CLUSTERED INDEX IDX_TempValor_CNPJ ON #ValorPorCupom(cnpj);


-- ============================================================================
-- PASSO 2: CALCULO BASE POR FARMACIA (TICKET MEDIO)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_ticket_medio;

SELECT
    cnpj,
    SUM(valor_total_cupom)  AS valor_total_periodo,
    COUNT(*)                AS qtd_cupons,
    CAST(
        CASE
            WHEN COUNT(*) > 0 THEN SUM(valor_total_cupom) / COUNT(*)
            ELSE 0
        END
    AS DECIMAL(18,2)) AS valor_ticket_medio
INTO temp_CGUSC.fp.indicador_ticket_medio
FROM #ValorPorCupom
GROUP BY cnpj;

CREATE CLUSTERED INDEX IDX_IndTicket_CNPJ ON temp_CGUSC.fp.indicador_ticket_medio(cnpj);

DROP TABLE #ValorPorCupom;


-- ============================================================================
-- PASSO 3: METRICAS POR MUNICIPIO (MEDIA E MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_ticket_medio_mun;

SELECT DISTINCT
    CAST(F.uf AS VARCHAR(2))          AS uf,
    CAST(F.municipio AS VARCHAR(255)) AS municipio,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.valor_ticket_medio)
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255)))
    AS DECIMAL(18,4)) AS mediana_municipio,
    CAST(
        AVG(I.valor_ticket_medio)
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255)))
    AS DECIMAL(18,4)) AS media_municipio
INTO temp_CGUSC.fp.indicador_ticket_medio_mun
FROM temp_CGUSC.fp.indicador_ticket_medio I
INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj;

CREATE CLUSTERED INDEX IDX_IndTicketMun ON temp_CGUSC.fp.indicador_ticket_medio_mun(uf, municipio);


-- ============================================================================
-- PASSO 4: METRICAS POR ESTADO (MEDIA E MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_ticket_medio_uf;

SELECT DISTINCT
    CAST(F.uf AS VARCHAR(2)) AS uf,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.valor_ticket_medio)
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)))
    AS DECIMAL(18,4)) AS mediana_estado,
    CAST(
        AVG(I.valor_ticket_medio)
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)))
    AS DECIMAL(18,4)) AS media_estado
INTO temp_CGUSC.fp.indicador_ticket_medio_uf
FROM temp_CGUSC.fp.indicador_ticket_medio I
INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj;

CREATE CLUSTERED INDEX IDX_IndTicketUF ON temp_CGUSC.fp.indicador_ticket_medio_uf(uf);


-- ============================================================================
-- PASSO 5: METRICAS NACIONAIS (MEDIA E MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_ticket_medio_br;

SELECT DISTINCT
    'BR' AS pais,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY valor_ticket_medio) OVER ()
    AS DECIMAL(18,4)) AS mediana_pais,
    CAST(
        AVG(valor_ticket_medio) OVER ()
    AS DECIMAL(18,4)) AS media_pais
INTO temp_CGUSC.fp.indicador_ticket_medio_br
FROM temp_CGUSC.fp.indicador_ticket_medio;


-- ============================================================================
-- PASSO 6: TABELA CONSOLIDADA FINAL
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_ticket_medio_detalhado;

SELECT
    I.cnpj,
    F.razaoSocial,
    F.municipio,
    CAST(F.uf AS VARCHAR(2)) AS uf,

    -- Indicadores base
    I.valor_total_periodo,
    I.qtd_cupons,
    I.valor_ticket_medio,

    -- Rankings (pior risco = posicao 1)
    RANK() OVER (
        ORDER BY I.valor_ticket_medio DESC
    ) AS ranking_br,
    RANK() OVER (
        PARTITION BY CAST(F.uf AS VARCHAR(2))
        ORDER BY I.valor_ticket_medio DESC
    ) AS ranking_uf,
    RANK() OVER (
        PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255))
        ORDER BY I.valor_ticket_medio DESC
    ) AS ranking_municipio,

    -- Benchmarks municipais
    ISNULL(MUN.mediana_municipio, 0) AS municipio_mediana,
    ISNULL(MUN.media_municipio,   0) AS municipio_media,
    CAST((I.valor_ticket_medio + 0.01) / (ISNULL(MUN.mediana_municipio, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_mediana,
    CAST((I.valor_ticket_medio + 0.01) / (ISNULL(MUN.media_municipio,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_media,

    -- Benchmarks estaduais
    ISNULL(UF.mediana_estado, 0) AS estado_mediana,
    ISNULL(UF.media_estado,   0) AS estado_media,
    CAST((I.valor_ticket_medio + 0.01) / (ISNULL(UF.mediana_estado, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_mediana,
    CAST((I.valor_ticket_medio + 0.01) / (ISNULL(UF.media_estado,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_media,

    -- Benchmarks nacionais
    BR.mediana_pais AS pais_mediana,
    BR.media_pais   AS pais_media,
    CAST((I.valor_ticket_medio + 0.01) / (BR.mediana_pais + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_mediana,
    CAST((I.valor_ticket_medio + 0.01) / (BR.media_pais   + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_media

INTO temp_CGUSC.fp.indicador_ticket_medio_detalhado
FROM temp_CGUSC.fp.indicador_ticket_medio I
INNER JOIN temp_CGUSC.fp.dados_farmacia F
    ON F.cnpj = I.cnpj
LEFT JOIN temp_CGUSC.fp.indicador_ticket_medio_mun MUN
    ON CAST(F.uf AS VARCHAR(2))          = MUN.uf
   AND CAST(F.municipio AS VARCHAR(255)) = MUN.municipio
LEFT JOIN temp_CGUSC.fp.indicador_ticket_medio_uf UF
    ON CAST(F.uf AS VARCHAR(2)) = UF.uf
CROSS JOIN temp_CGUSC.fp.indicador_ticket_medio_br BR;

CREATE CLUSTERED INDEX    IDX_FinalTicket_CNPJ  ON temp_CGUSC.fp.indicador_ticket_medio_detalhado(cnpj);
CREATE NONCLUSTERED INDEX IDX_FinalTicket_Risco ON temp_CGUSC.fp.indicador_ticket_medio_detalhado(risco_relativo_mun_mediana DESC);
CREATE NONCLUSTERED INDEX IDX_FinalTicket_Rank  ON temp_CGUSC.fp.indicador_ticket_medio_detalhado(ranking_br);
GO

-- Verificacao rapida
SELECT TOP 100 *
FROM temp_CGUSC.fp.indicador_ticket_medio_detalhado
ORDER BY ranking_br;