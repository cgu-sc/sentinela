USE [temp_CGUSC]
GO

-- ============================================================================
-- DEFINICAO DE VARIAVEIS
-- ============================================================================
DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim    DATE = '2024-12-10';


-- ============================================================================
-- PASSO 1: PRE-CALCULO - RECORRENCIA POR CPF EM CADA FARMACIA
-- Agrupa para saber quantas vezes cada CPF comprou em cada estabelecimento.
-- COUNT(DISTINCT num_autorizacao) e critico para contar compras unicas.
-- ============================================================================
DROP TABLE IF EXISTS #RecorrenciaPorCPF;

SELECT
    A.cnpj,
    A.cpf,
    COUNT(DISTINCT A.num_autorizacao) AS qtd_compras_cpf
INTO #RecorrenciaPorCPF
FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
INNER JOIN temp_CGUSC.fp.medicamentos_patologia C
    ON C.codigo_barra = A.codigo_barra
WHERE
    A.data_hora >= @DataInicio
    AND A.data_hora <= @DataFim
    AND A.cpf IS NOT NULL   -- Critico: evita CPFs nulos que distorceriam o indicador
GROUP BY A.cnpj, A.cpf;

CREATE CLUSTERED INDEX IDX_TempRecorrencia_CNPJ ON #RecorrenciaPorCPF(cnpj);


-- ============================================================================
-- PASSO 2: CALCULO BASE POR FARMACIA (INDICADOR COMPRA UNICA)
-- Paciente de "compra unica" = CPF que comprou apenas 1 vez na farmacia.
-- Alto percentual indica baixa fidelizacao ou possiveis CPFs ficticios.
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_compra_unica;

SELECT
    cnpj,
    COUNT(*)                                                                             AS total_cpfs_distintos,
    SUM(CASE WHEN qtd_compras_cpf = 1 THEN 1 ELSE 0 END)                                AS qtd_cpfs_compra_unica,
    CAST(
        CASE
            WHEN COUNT(*) > 0 THEN
                (CAST(SUM(CASE WHEN qtd_compras_cpf = 1 THEN 1 ELSE 0 END) AS DECIMAL(18,2)) /
                 CAST(COUNT(*) AS DECIMAL(18,2))) * 100.0
            ELSE 0
        END
    AS DECIMAL(18,4)) AS pct_compra_unica,
    -- Estatistica adicional: media de compras por CPF (para contexto de fidelizacao)
    CAST(AVG(CAST(qtd_compras_cpf AS DECIMAL(18,2))) AS DECIMAL(18,2)) AS media_compras_por_cpf

INTO temp_CGUSC.fp.indicador_compra_unica
FROM #RecorrenciaPorCPF
GROUP BY cnpj;

CREATE CLUSTERED INDEX IDX_IndCompraUnica_CNPJ ON temp_CGUSC.fp.indicador_compra_unica(cnpj);

DROP TABLE #RecorrenciaPorCPF;


-- ============================================================================
-- PASSO 3: METRICAS POR MUNICIPIO (MEDIA E MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_compra_unica_mun;

SELECT DISTINCT
    F.uf,
    F.municipio,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.pct_compra_unica, 0))
        OVER (PARTITION BY F.uf, F.municipio)
    AS DECIMAL(18,4)) AS mediana_municipio,
    CAST(
        AVG(ISNULL(I.pct_compra_unica, 0))
        OVER (PARTITION BY F.uf, F.municipio)
    AS DECIMAL(18,4)) AS media_municipio
INTO temp_CGUSC.fp.indicador_compra_unica_mun
FROM temp_CGUSC.fp.dados_farmacia F
LEFT JOIN temp_CGUSC.fp.indicador_compra_unica I ON I.cnpj = F.cnpj;

CREATE CLUSTERED INDEX IDX_IndCompraUnicaMun ON temp_CGUSC.fp.indicador_compra_unica_mun(uf, municipio);


-- ============================================================================
-- PASSO 4: METRICAS POR ESTADO (MEDIA E MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_compra_unica_uf;

SELECT DISTINCT
    F.uf,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.pct_compra_unica, 0))
        OVER (PARTITION BY F.uf)
    AS DECIMAL(18,4)) AS mediana_estado,
    CAST(
        AVG(ISNULL(I.pct_compra_unica, 0))
        OVER (PARTITION BY F.uf)
    AS DECIMAL(18,4)) AS media_estado
INTO temp_CGUSC.fp.indicador_compra_unica_uf
FROM temp_CGUSC.fp.dados_farmacia F
LEFT JOIN temp_CGUSC.fp.indicador_compra_unica I ON I.cnpj = F.cnpj;

CREATE CLUSTERED INDEX IDX_IndCompraUnicaUF ON temp_CGUSC.fp.indicador_compra_unica_uf(uf);


-- ============================================================================
-- PASSO 4B: METRICAS POR REGIAO DE SAUDE (MEDIA E MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_compra_unica_regiao;

SELECT DISTINCT
    F.id_regiao_saude,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.pct_compra_unica, 0))
        OVER (PARTITION BY F.id_regiao_saude)
    AS DECIMAL(18,4)) AS mediana_regiao,
    CAST(
        AVG(ISNULL(I.pct_compra_unica, 0))
        OVER (PARTITION BY F.id_regiao_saude)
    AS DECIMAL(18,4)) AS media_regiao
INTO temp_CGUSC.fp.indicador_compra_unica_regiao
FROM temp_CGUSC.fp.dados_farmacia F
LEFT JOIN temp_CGUSC.fp.indicador_compra_unica I ON I.cnpj = F.cnpj
WHERE F.id_regiao_saude IS NOT NULL;

CREATE CLUSTERED INDEX IDX_IndCompraUnicaReg ON temp_CGUSC.fp.indicador_compra_unica_regiao(id_regiao_saude);


-- ============================================================================
-- PASSO 5: METRICAS NACIONAIS (MEDIA E MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_compra_unica_br;

SELECT DISTINCT
    'BR' AS pais,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(pct_compra_unica, 0)) OVER ()
    AS DECIMAL(18,4)) AS mediana_pais,
    CAST(
        AVG(ISNULL(pct_compra_unica, 0)) OVER ()
    AS DECIMAL(18,4)) AS media_pais
INTO temp_CGUSC.fp.indicador_compra_unica_br
FROM temp_CGUSC.fp.dados_farmacia F
LEFT JOIN temp_CGUSC.fp.indicador_compra_unica I ON I.cnpj = F.cnpj;


-- ============================================================================
-- PASSO 6: TABELA CONSOLIDADA FINAL
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_compra_unica_detalhado;

SELECT
    F.cnpj,
    F.razaoSocial,
    F.municipio,
    F.uf,
    F.no_regiao_saude,
    F.id_regiao_saude,

    -- Indicadores base
    ISNULL(I.total_cpfs_distintos, 0)        AS total_cpfs_distintos,
    ISNULL(I.qtd_cpfs_compra_unica, 0)           AS qtd_cpfs_compra_unica,
    ISNULL(I.pct_compra_unica, 0) AS pct_compra_unica,
    ISNULL(I.media_compras_por_cpf, 0)        AS media_compras_por_cpf,

    -- Rankings (pior risco = posicao 1)
    RANK() OVER (
        ORDER BY ISNULL(I.pct_compra_unica, 0) DESC
    ) AS ranking_br,
    RANK() OVER (
        PARTITION BY F.uf
        ORDER BY ISNULL(I.pct_compra_unica, 0) DESC
    ) AS ranking_uf,
    RANK() OVER (
        PARTITION BY F.id_regiao_saude
        ORDER BY ISNULL(I.pct_compra_unica, 0) DESC
    ) AS ranking_regiao_saude,
    RANK() OVER (
        PARTITION BY F.uf, F.municipio
        ORDER BY ISNULL(I.pct_compra_unica, 0) DESC
    ) AS ranking_municipio,

    -- Benchmarks municipais
    ISNULL(MUN.mediana_municipio, 0) AS municipio_mediana,
    ISNULL(MUN.media_municipio,   0) AS municipio_media,
    CAST((ISNULL(I.pct_compra_unica, 0) + 0.01) / (ISNULL(MUN.mediana_municipio, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_mediana,
    CAST((ISNULL(I.pct_compra_unica, 0) + 0.01) / (ISNULL(MUN.media_municipio,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_media,

    -- Benchmarks estaduais
    ISNULL(UF.mediana_estado, 0) AS estado_mediana,
    ISNULL(UF.media_estado,   0) AS estado_media,
    CAST((ISNULL(I.pct_compra_unica, 0) + 0.01) / (ISNULL(UF.mediana_estado, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_mediana,
    CAST((ISNULL(I.pct_compra_unica, 0) + 0.01) / (ISNULL(UF.media_estado,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_media,

    -- Benchmarks Regionais (Regiao de Saude)
    ISNULL(REG.mediana_regiao, 0) AS regiao_saude_mediana,
    ISNULL(REG.media_regiao,   0) AS regiao_saude_media,
    CAST((ISNULL(I.pct_compra_unica, 0) + 0.01) / (ISNULL(REG.mediana_regiao, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_reg_mediana,
    CAST((ISNULL(I.pct_compra_unica, 0) + 0.01) / (ISNULL(REG.media_regiao,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_reg_media,

    -- Benchmarks nacionais
    BR.mediana_pais AS pais_mediana,
    BR.media_pais   AS pais_media,
    CAST((ISNULL(I.pct_compra_unica, 0) + 0.01) / (BR.mediana_pais + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_mediana,
    CAST((ISNULL(I.pct_compra_unica, 0) + 0.01) / (BR.media_pais   + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_media

INTO temp_CGUSC.fp.indicador_compra_unica_detalhado
FROM temp_CGUSC.fp.dados_farmacia F
LEFT JOIN temp_CGUSC.fp.indicador_compra_unica I
    ON I.cnpj = F.cnpj
LEFT JOIN temp_CGUSC.fp.indicador_compra_unica_mun MUN
    ON F.uf        = MUN.uf
   AND F.municipio = MUN.municipio
LEFT JOIN temp_CGUSC.fp.indicador_compra_unica_uf UF
    ON F.uf = UF.uf
LEFT JOIN temp_CGUSC.fp.indicador_compra_unica_regiao REG
    ON F.id_regiao_saude = REG.id_regiao_saude
CROSS JOIN temp_CGUSC.fp.indicador_compra_unica_br BR;

CREATE CLUSTERED INDEX    IDX_FinalCompraUnica_CNPJ  ON temp_CGUSC.fp.indicador_compra_unica_detalhado(cnpj);
CREATE NONCLUSTERED INDEX IDX_FinalCompraUnica_Risco ON temp_CGUSC.fp.indicador_compra_unica_detalhado(risco_relativo_mun_mediana DESC);
CREATE NONCLUSTERED INDEX IDX_FinalCompraUnica_Rank  ON temp_CGUSC.fp.indicador_compra_unica_detalhado(ranking_br);
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_compra_unica;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_compra_unica_mun;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_compra_unica_uf;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_compra_unica_regiao;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_compra_unica_br;
GO


-- ============================================================================
-- VERIFICACAO E ESTATISTICAS
-- ============================================================================

-- Top 100 por risco nacional
SELECT TOP 100 *
FROM temp_CGUSC.fp.indicador_compra_unica_detalhado
ORDER BY ranking_br;

-- Estatisticas gerais do indicador
SELECT
    'BRASIL' AS escopo,
    COUNT(*)                                                   AS total_farmacias_analisadas,
    CAST(AVG(pct_compra_unica) AS DECIMAL(10,2))   AS media_percentual,
    CAST(MIN(pct_compra_unica) AS DECIMAL(10,2))   AS minimo,
    CAST(MAX(pct_compra_unica) AS DECIMAL(10,2))   AS maximo,
    CAST(STDEV(pct_compra_unica) AS DECIMAL(10,4)) AS desvio_padrao
FROM temp_CGUSC.fp.indicador_compra_unica_detalhado;

-- Mediana nacional
SELECT DISTINCT
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY pct_compra_unica) OVER () AS mediana
FROM temp_CGUSC.fp.indicador_compra_unica_detalhado;

-- Distribuicao por faixas de risco (baseada no risco relativo municipal)
SELECT
    CASE
        WHEN risco_relativo_mun_mediana < 0.5  THEN '1. Muito Abaixo da Media (< 0.5x)'
        WHEN risco_relativo_mun_mediana < 0.8  THEN '2. Abaixo da Media (0.5x - 0.8x)'
        WHEN risco_relativo_mun_mediana < 1.2  THEN '3. Dentro da Media (0.8x - 1.2x)'
        WHEN risco_relativo_mun_mediana < 1.5  THEN '4. Acima da Media (1.2x - 1.5x)'
        WHEN risco_relativo_mun_mediana < 2.0  THEN '5. Alto Risco (1.5x - 2.0x)'
        ELSE                                        '6. Risco Critico (> 2.0x)'
    END AS faixa_risco,
    COUNT(*) AS qtd_farmacias,
    CAST(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS percentual_farmacias
FROM temp_CGUSC.fp.indicador_compra_unica_detalhado
GROUP BY
    CASE
        WHEN risco_relativo_mun_mediana < 0.5  THEN '1. Muito Abaixo da Media (< 0.5x)'
        WHEN risco_relativo_mun_mediana < 0.8  THEN '2. Abaixo da Media (0.5x - 0.8x)'
        WHEN risco_relativo_mun_mediana < 1.2  THEN '3. Dentro da Media (0.8x - 1.2x)'
        WHEN risco_relativo_mun_mediana < 1.5  THEN '4. Acima da Media (1.2x - 1.5x)'
        WHEN risco_relativo_mun_mediana < 2.0  THEN '5. Alto Risco (1.5x - 2.0x)'
        ELSE                                        '6. Risco Critico (> 2.0x)'
    END
ORDER BY faixa_risco;
