USE [temp_CGUSC]
GO

-- ============================================================================
-- INDICADOR DE CONCENTRACAO EM DIAS DE PICO
-- ============================================================================
-- OBJETIVO: Identificar farmacias onde o faturamento e altamente concentrado
--           em poucos dias do mes, sugerindo manipulacao de registros ou
--           superdispensacao em periodos especificos (ex.: virada de mes).
--
-- METRICA PRINCIPAL: pct_concentracao_top3_dias
--   Percentual do faturamento mensal concentrado nos 3 dias de maior venda.
--   Calculado mensalmente e sumarizado por farmacia via media e mediana.
--
-- INTERPRETACAO DA mediana_concentracao:
--   - >= 80%: CRITICO  - Quase todo o faturamento concentrado em 3 dias
--   - 60-80%: ALTO     - Concentracao muito acima do esperado
--   - 40-60%: MODERADO - Requer monitoramento
--   - < 40%:  BAIXO    - Padrao habitual de vendas
--
-- FONTE DE DADOS:
--   - db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 (periodo completo)
-- ============================================================================

-- ============================================================================
-- DEFINICAO DE VARIAVEIS DO PERIODO
-- ============================================================================
DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim    DATE = '2024-12-10';


-- ============================================================================
-- PASSO 1: VENDAS DIARIAS POR FARMACIA
-- UNION ALL entre a base historica e a recente para cobrir todo o periodo.
-- ============================================================================
DROP TABLE IF EXISTS #VendasDiarias;

SELECT
    A.cnpj,
    FORMAT(A.data_hora, 'yyyy-MM') AS ano_mes,
    CAST(A.data_hora AS DATE)      AS data_venda,
    SUM(A.valor_pago)              AS valor_dia
INTO #VendasDiarias
FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
WHERE A.data_hora >= @DataInicio
  AND A.data_hora <= @DataFim
GROUP BY A.cnpj, FORMAT(A.data_hora, 'yyyy-MM'), CAST(A.data_hora AS DATE);

CREATE CLUSTERED INDEX IDX_VendasDiarias_CNPJ ON #VendasDiarias(cnpj, ano_mes);


-- ============================================================================
-- PASSO 2: RANQUEAMENTO DOS DIAS DENTRO DE CADA MES
-- ============================================================================
DROP TABLE IF EXISTS #RankingDias;

SELECT
    cnpj,
    ano_mes,
    valor_dia,
    SUM(valor_dia)    OVER (PARTITION BY cnpj, ano_mes)                       AS total_mes,
    ROW_NUMBER()      OVER (PARTITION BY cnpj, ano_mes ORDER BY valor_dia DESC) AS ranking_dia
INTO #RankingDias
FROM #VendasDiarias;

DROP TABLE IF EXISTS #VendasDiarias;


-- ============================================================================
-- PASSO 3: PERCENTUAL DE CONCENTRACAO MENSAL (TOP 3 DIAS)
-- ============================================================================
DROP TABLE IF EXISTS #ConcentracaoMensal;

SELECT
    cnpj,
    ano_mes,
    CAST(
        SUM(CASE WHEN ranking_dia <= 3 THEN valor_dia ELSE 0 END) /
        NULLIF(CAST(MAX(total_mes) AS DECIMAL(18,2)), 0) * 100.0
    AS DECIMAL(18,4)) AS pct_concentracao_top3_dias
INTO #ConcentracaoMensal
FROM #RankingDias
GROUP BY cnpj, ano_mes
HAVING MAX(total_mes) > 0;

DROP TABLE IF EXISTS #RankingDias;


-- ============================================================================
-- PASSO 4: CALCULO BASE POR FARMACIA (MEDIA E MEDIANA DO PERIODO)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_concentracao_pico;

SELECT DISTINCT
    cnpj,
    COUNT(ano_mes) OVER (PARTITION BY cnpj) AS meses_analisados,

    -- Mediana: comportamento tipico da farmacia
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY pct_concentracao_top3_dias)
        OVER (PARTITION BY cnpj)
    AS DECIMAL(18,4)) AS mediana_concentracao,

    -- Media: impacto dos picos no periodo
    CAST(
        AVG(pct_concentracao_top3_dias)
        OVER (PARTITION BY cnpj)
    AS DECIMAL(18,4)) AS media_concentracao

INTO temp_CGUSC.fp.indicador_concentracao_pico
FROM #ConcentracaoMensal;

CREATE CLUSTERED INDEX IDX_IndPico_CNPJ ON temp_CGUSC.fp.indicador_concentracao_pico(cnpj);

DROP TABLE IF EXISTS #ConcentracaoMensal;


-- ============================================================================
-- PASSO 5: METRICAS POR MUNICIPIO (MEDIANA E MEDIA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_concentracao_pico_mun;

SELECT DISTINCT
    CAST(F.uf        AS VARCHAR(2))   AS uf,
    CAST(F.municipio AS VARCHAR(255)) AS municipio,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.mediana_concentracao)
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255)))
    AS DECIMAL(18,4)) AS mediana_municipio,
    CAST(
        AVG(I.media_concentracao)
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255)))
    AS DECIMAL(18,4)) AS media_municipio
INTO temp_CGUSC.fp.indicador_concentracao_pico_mun
FROM temp_CGUSC.fp.indicador_concentracao_pico I
INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj;

CREATE CLUSTERED INDEX IDX_IndPicoMun ON temp_CGUSC.fp.indicador_concentracao_pico_mun(uf, municipio);


-- ============================================================================
-- PASSO 6: METRICAS POR ESTADO (MEDIANA E MEDIA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_concentracao_pico_uf;

SELECT DISTINCT
    CAST(F.uf AS VARCHAR(2)) AS uf,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.mediana_concentracao)
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)))
    AS DECIMAL(18,4)) AS mediana_estado,
    CAST(
        AVG(I.media_concentracao)
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)))
    AS DECIMAL(18,4)) AS media_estado
INTO temp_CGUSC.fp.indicador_concentracao_pico_uf
FROM temp_CGUSC.fp.indicador_concentracao_pico I
INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj;

CREATE CLUSTERED INDEX IDX_IndPicoUF ON temp_CGUSC.fp.indicador_concentracao_pico_uf(uf);


-- ============================================================================
-- PASSO 6B: METRICAS POR REGIAO DE SAUDE (MEDIANA E MEDIA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_concentracao_pico_regiao;

SELECT DISTINCT
    F.id_regiao_saude,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.mediana_concentracao)
        OVER (PARTITION BY F.id_regiao_saude)
    AS DECIMAL(18,4)) AS mediana_regiao,
    CAST(
        AVG(I.media_concentracao)
        OVER (PARTITION BY F.id_regiao_saude)
    AS DECIMAL(18,4)) AS media_regiao
INTO temp_CGUSC.fp.indicador_concentracao_pico_regiao
FROM temp_CGUSC.fp.indicador_concentracao_pico I
INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj
WHERE F.id_regiao_saude IS NOT NULL;

CREATE CLUSTERED INDEX IDX_IndPicoReg ON temp_CGUSC.fp.indicador_concentracao_pico_regiao(id_regiao_saude);


-- ============================================================================
-- PASSO 7: METRICAS NACIONAIS (MEDIANA E MEDIA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_concentracao_pico_br;

SELECT DISTINCT
    'BR' AS pais,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY mediana_concentracao) OVER ()
    AS DECIMAL(18,4)) AS mediana_pais,
    CAST(
        AVG(media_concentracao) OVER ()
    AS DECIMAL(18,4)) AS media_pais
INTO temp_CGUSC.fp.indicador_concentracao_pico_br
FROM temp_CGUSC.fp.indicador_concentracao_pico;


-- ============================================================================
-- PASSO 8: TABELA CONSOLIDADA FINAL
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_concentracao_pico_detalhado;

SELECT
    I.cnpj,
    F.razaoSocial,
    F.municipio,
    CAST(F.uf AS VARCHAR(2)) AS uf,
    F.no_regiao_saude,
    F.id_regiao_saude,

    -- Indicadores base
    I.meses_analisados,
    I.mediana_concentracao,
    I.media_concentracao,

    -- Rankings (pior risco = posicao 1)
    RANK() OVER (
        ORDER BY I.mediana_concentracao DESC
    ) AS ranking_br,
    RANK() OVER (
        PARTITION BY CAST(F.uf AS VARCHAR(2))
        ORDER BY I.mediana_concentracao DESC
    ) AS ranking_uf,
    RANK() OVER (
        PARTITION BY F.id_regiao_saude
        ORDER BY I.mediana_concentracao DESC
    ) AS ranking_regiao_saude,
    RANK() OVER (
        PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255))
        ORDER BY I.mediana_concentracao DESC
    ) AS ranking_municipio,

    -- Benchmarks municipais
    ISNULL(MUN.mediana_municipio, 0) AS municipio_mediana,
    ISNULL(MUN.media_municipio,   0) AS municipio_media,
    CAST((I.mediana_concentracao + 0.01) / (ISNULL(MUN.mediana_municipio, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_mediana,
    CAST((I.media_concentracao   + 0.01) / (ISNULL(MUN.media_municipio,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_media,

    -- Benchmarks estaduais
    ISNULL(UF.mediana_estado, 0) AS estado_mediana,
    ISNULL(UF.media_estado,   0) AS estado_media,
    CAST((I.mediana_concentracao + 0.01) / (ISNULL(UF.mediana_estado, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_mediana,
    CAST((I.media_concentracao   + 0.01) / (ISNULL(UF.media_estado,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_media,

    -- Benchmarks Regionais (Regiao de Saude)
    ISNULL(REG.mediana_regiao, 0) AS regiao_saude_mediana,
    ISNULL(REG.media_regiao,   0) AS regiao_saude_media,
    CAST((I.mediana_concentracao + 0.01) / (ISNULL(REG.mediana_regiao, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_reg_mediana,
    CAST((I.media_concentracao   + 0.01) / (ISNULL(REG.media_regiao,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_reg_media,

    -- Benchmarks nacionais
    BR.mediana_pais AS pais_mediana,
    BR.media_pais   AS pais_media,
    CAST((I.mediana_concentracao + 0.01) / (BR.mediana_pais + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_mediana,
    CAST((I.media_concentracao   + 0.01) / (BR.media_pais   + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_media,

    -- Classificacao de Risco (baseada na mediana do comportamento da farmacia)
    CASE
        WHEN I.mediana_concentracao >= 80 THEN 'CRITICO'
        WHEN I.mediana_concentracao >= 60 THEN 'ALTO'
        WHEN I.mediana_concentracao >= 40 THEN 'MODERADO'
        ELSE 'BAIXO'
    END AS classificacao_risco

INTO temp_CGUSC.fp.indicador_concentracao_pico_detalhado
FROM temp_CGUSC.fp.indicador_concentracao_pico I
INNER JOIN temp_CGUSC.fp.dados_farmacia F
    ON F.cnpj = I.cnpj
LEFT JOIN temp_CGUSC.fp.indicador_concentracao_pico_mun MUN
    ON  CAST(F.uf        AS VARCHAR(2))   = MUN.uf
    AND CAST(F.municipio AS VARCHAR(255)) = MUN.municipio
LEFT JOIN temp_CGUSC.fp.indicador_concentracao_pico_uf UF
    ON CAST(F.uf AS VARCHAR(2)) = UF.uf
LEFT JOIN temp_CGUSC.fp.indicador_concentracao_pico_regiao REG
    ON F.id_regiao_saude = REG.id_regiao_saude
CROSS JOIN temp_CGUSC.fp.indicador_concentracao_pico_br BR;

CREATE CLUSTERED INDEX    IDX_FinalPico_CNPJ  ON temp_CGUSC.fp.indicador_concentracao_pico_detalhado(cnpj);
CREATE NONCLUSTERED INDEX IDX_FinalPico_Risco ON temp_CGUSC.fp.indicador_concentracao_pico_detalhado(risco_relativo_mun_mediana DESC);
CREATE NONCLUSTERED INDEX IDX_FinalPico_Rank  ON temp_CGUSC.fp.indicador_concentracao_pico_detalhado(ranking_br);
GO

-- ============================================================================
-- LIMPEZA DAS TABELAS INTERMEDIARIAS
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_concentracao_pico;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_concentracao_pico_mun;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_concentracao_pico_uf;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_concentracao_pico_regiao;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_concentracao_pico_br;
GO

-- Verificacao rapida
SELECT TOP 100 *
FROM temp_CGUSC.fp.indicador_concentracao_pico_detalhado
ORDER BY ranking_br;
