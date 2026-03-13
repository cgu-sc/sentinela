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
-- PASSO 2: CALCULO BASE POR FARMACIA (INDICADOR PACIENTES UNICOS / FANTASMA)
-- Paciente "fantasma" = CPF que comprou apenas 1 vez na farmacia.
-- Alto percentual indica possivelmente receitas fraudulentas ou CPFs ficticioss.
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_pacientes_unicos;

SELECT
    cnpj,
    COUNT(*)                                                                             AS total_cpfs_distintos,
    SUM(CASE WHEN qtd_compras_cpf = 1 THEN 1 ELSE 0 END)                                AS qtd_cpfs_fantasma,
    CAST(
        CASE
            WHEN COUNT(*) > 0 THEN
                (CAST(SUM(CASE WHEN qtd_compras_cpf = 1 THEN 1 ELSE 0 END) AS DECIMAL(18,2)) /
                 CAST(COUNT(*) AS DECIMAL(18,2))) * 100.0
            ELSE 0
        END
    AS DECIMAL(18,4)) AS percentual_pacientes_unicos,
    -- Estatistica adicional: media de compras por CPF (para contexto de fidelizacao)
    CAST(AVG(CAST(qtd_compras_cpf AS DECIMAL(18,2))) AS DECIMAL(18,2)) AS media_compras_por_cpf

INTO temp_CGUSC.fp.indicador_pacientes_unicos
FROM #RecorrenciaPorCPF
GROUP BY cnpj;

CREATE CLUSTERED INDEX IDX_IndFantasma_CNPJ ON temp_CGUSC.fp.indicador_pacientes_unicos(cnpj);

DROP TABLE #RecorrenciaPorCPF;


-- ============================================================================
-- PASSO 3: METRICAS POR MUNICIPIO (MEDIA E MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_pacientes_unicos_mun;

SELECT DISTINCT
    CAST(F.uf AS VARCHAR(2))          AS uf,
    CAST(F.municipio AS VARCHAR(255)) AS municipio,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.percentual_pacientes_unicos)
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255)))
    AS DECIMAL(18,4)) AS mediana_municipio,
    CAST(
        AVG(I.percentual_pacientes_unicos)
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255)))
    AS DECIMAL(18,4)) AS media_municipio
INTO temp_CGUSC.fp.indicador_pacientes_unicos_mun
FROM temp_CGUSC.fp.indicador_pacientes_unicos I
INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj;

CREATE CLUSTERED INDEX IDX_IndFantasmaMun ON temp_CGUSC.fp.indicador_pacientes_unicos_mun(uf, municipio);


-- ============================================================================
-- PASSO 4: METRICAS POR ESTADO (MEDIA E MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_pacientes_unicos_uf;

SELECT DISTINCT
    CAST(F.uf AS VARCHAR(2)) AS uf,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.percentual_pacientes_unicos)
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)))
    AS DECIMAL(18,4)) AS mediana_estado,
    CAST(
        AVG(I.percentual_pacientes_unicos)
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)))
    AS DECIMAL(18,4)) AS media_estado
INTO temp_CGUSC.fp.indicador_pacientes_unicos_uf
FROM temp_CGUSC.fp.indicador_pacientes_unicos I
INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj;

CREATE CLUSTERED INDEX IDX_IndFantasmaUF ON temp_CGUSC.fp.indicador_pacientes_unicos_uf(uf);


-- ============================================================================
-- PASSO 5: METRICAS NACIONAIS (MEDIA E MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_pacientes_unicos_br;

SELECT DISTINCT
    'BR' AS pais,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY percentual_pacientes_unicos) OVER ()
    AS DECIMAL(18,4)) AS mediana_pais,
    CAST(
        AVG(percentual_pacientes_unicos) OVER ()
    AS DECIMAL(18,4)) AS media_pais
INTO temp_CGUSC.fp.indicador_pacientes_unicos_br
FROM temp_CGUSC.fp.indicador_pacientes_unicos;


-- ============================================================================
-- PASSO 6: TABELA CONSOLIDADA FINAL
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_pacientes_unicos_detalhado;

SELECT
    I.cnpj,
    F.razaoSocial,
    F.municipio,
    CAST(F.uf AS VARCHAR(2)) AS uf,

    -- Indicadores base
    I.total_cpfs_distintos,
    I.qtd_cpfs_fantasma,
    I.percentual_pacientes_unicos,
    I.media_compras_por_cpf,

    -- Rankings (pior risco = posicao 1)
    RANK() OVER (
        ORDER BY I.percentual_pacientes_unicos DESC
    ) AS ranking_br,
    RANK() OVER (
        PARTITION BY CAST(F.uf AS VARCHAR(2))
        ORDER BY I.percentual_pacientes_unicos DESC
    ) AS ranking_uf,
    RANK() OVER (
        PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255))
        ORDER BY I.percentual_pacientes_unicos DESC
    ) AS ranking_municipio,

    -- Benchmarks municipais
    ISNULL(MUN.mediana_municipio, 0) AS municipio_mediana,
    ISNULL(MUN.media_municipio,   0) AS municipio_media,
    CAST((I.percentual_pacientes_unicos + 0.01) / (ISNULL(MUN.mediana_municipio, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_mediana,
    CAST((I.percentual_pacientes_unicos + 0.01) / (ISNULL(MUN.media_municipio,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_media,

    -- Benchmarks estaduais
    ISNULL(UF.mediana_estado, 0) AS estado_mediana,
    ISNULL(UF.media_estado,   0) AS estado_media,
    CAST((I.percentual_pacientes_unicos + 0.01) / (ISNULL(UF.mediana_estado, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_mediana,
    CAST((I.percentual_pacientes_unicos + 0.01) / (ISNULL(UF.media_estado,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_media,

    -- Benchmarks nacionais
    BR.mediana_pais AS pais_mediana,
    BR.media_pais   AS pais_media,
    CAST((I.percentual_pacientes_unicos + 0.01) / (BR.mediana_pais + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_mediana,
    CAST((I.percentual_pacientes_unicos + 0.01) / (BR.media_pais   + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_media

INTO temp_CGUSC.fp.indicador_pacientes_unicos_detalhado
FROM temp_CGUSC.fp.indicador_pacientes_unicos I
INNER JOIN temp_CGUSC.fp.dados_farmacia F
    ON F.cnpj = I.cnpj
LEFT JOIN temp_CGUSC.fp.indicador_pacientes_unicos_mun MUN
    ON CAST(F.uf AS VARCHAR(2))          = MUN.uf
   AND CAST(F.municipio AS VARCHAR(255)) = MUN.municipio
LEFT JOIN temp_CGUSC.fp.indicador_pacientes_unicos_uf UF
    ON CAST(F.uf AS VARCHAR(2)) = UF.uf
CROSS JOIN temp_CGUSC.fp.indicador_pacientes_unicos_br BR;

CREATE CLUSTERED INDEX    IDX_FinalFantasma_CNPJ  ON temp_CGUSC.fp.indicador_pacientes_unicos_detalhado(cnpj);
CREATE NONCLUSTERED INDEX IDX_FinalFantasma_Risco ON temp_CGUSC.fp.indicador_pacientes_unicos_detalhado(risco_relativo_mun_mediana DESC);
CREATE NONCLUSTERED INDEX IDX_FinalFantasma_Rank  ON temp_CGUSC.fp.indicador_pacientes_unicos_detalhado(ranking_br);
GO


-- ============================================================================
-- VERIFICACAO E ESTATISTICAS
-- ============================================================================

-- Top 100 por risco nacional
SELECT TOP 100 *
FROM temp_CGUSC.fp.indicador_pacientes_unicos_detalhado
ORDER BY ranking_br;

-- Estatisticas gerais do indicador
SELECT
    'BRASIL' AS escopo,
    COUNT(*)                                                   AS total_farmacias_analisadas,
    CAST(AVG(percentual_pacientes_unicos) AS DECIMAL(10,2))   AS media_percentual,
    CAST(MIN(percentual_pacientes_unicos) AS DECIMAL(10,2))   AS minimo,
    CAST(MAX(percentual_pacientes_unicos) AS DECIMAL(10,2))   AS maximo,
    CAST(STDEV(percentual_pacientes_unicos) AS DECIMAL(10,4)) AS desvio_padrao
FROM temp_CGUSC.fp.indicador_pacientes_unicos_detalhado;

-- Mediana nacional
SELECT DISTINCT
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY percentual_pacientes_unicos) OVER () AS mediana
FROM temp_CGUSC.fp.indicador_pacientes_unicos_detalhado;

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
FROM temp_CGUSC.fp.indicador_pacientes_unicos_detalhado
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
