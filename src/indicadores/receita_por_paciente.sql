USE [temp_CGUSC]
GO

-- ============================================================================
-- DEFINICAO DE VARIAVEIS DO PERIODO
-- ============================================================================
DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim    DATE = '2024-12-10';


-- ============================================================================
-- PASSO 1: PRE-CALCULO - CONSOLIDADO POR FARMACIA E PACIENTE
-- Conta pacientes distintos, valor total e meses de atividade.
-- Considera apenas medicamentos do escopo auditado.
-- ============================================================================
DROP TABLE IF EXISTS #ConsolidadoPacientes;

SELECT
    A.cnpj,
    COUNT(DISTINCT A.cpf)                            AS qtd_pacientes_distintos,
    SUM(A.valor_pago)                                AS valor_total_periodo,
    COUNT(DISTINCT FORMAT(A.data_hora, 'yyyyMM'))    AS qtd_meses_ativos
INTO #ConsolidadoPacientes
FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
INNER JOIN temp_CGUSC.fp.medicamentos_patologia C
    ON C.codigo_barra = A.codigo_barra
WHERE
    A.data_hora >= @DataInicio
    AND A.data_hora <= @DataFim
GROUP BY A.cnpj;

CREATE CLUSTERED INDEX IDX_TempPacientes_CNPJ ON #ConsolidadoPacientes(cnpj);


-- ============================================================================
-- PASSO 2: CALCULO BASE POR FARMACIA
-- Gera as duas metricas: receita total por paciente e receita mensal por paciente.
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_receita_por_paciente;

SELECT
    cnpj,
    valor_total_periodo,
    qtd_pacientes_distintos,
    qtd_meses_ativos,

    -- Metrica 1: Receita total acumulada por paciente (periodo completo)
    CAST(
        CASE
            WHEN qtd_pacientes_distintos > 0
                THEN valor_total_periodo / qtd_pacientes_distintos
            ELSE 0
        END
    AS DECIMAL(18,2)) AS receita_por_paciente,

    -- Metrica 2: Receita mensal media por paciente (base para riscos relativos)
    CAST(
        CASE
            WHEN qtd_pacientes_distintos > 0 AND qtd_meses_ativos > 0
                THEN (valor_total_periodo / qtd_pacientes_distintos) / qtd_meses_ativos
            ELSE 0
        END
    AS DECIMAL(18,2)) AS receita_por_paciente_mensal

INTO temp_CGUSC.fp.indicador_receita_por_paciente
FROM #ConsolidadoPacientes;

CREATE CLUSTERED INDEX IDX_IndRecPac_CNPJ ON temp_CGUSC.fp.indicador_receita_por_paciente(cnpj);

DROP TABLE #ConsolidadoPacientes;


-- ============================================================================
-- PASSO 3: METRICAS POR MUNICIPIO (MEDIA E MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_receita_por_paciente_mun;

SELECT DISTINCT
    CAST(F.uf AS VARCHAR(2))          AS uf,
    CAST(F.municipio AS VARCHAR(255)) AS municipio,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.receita_por_paciente_mensal)
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255)))
    AS DECIMAL(18,4)) AS mediana_municipio,
    CAST(
        AVG(I.receita_por_paciente_mensal)
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255)))
    AS DECIMAL(18,4)) AS media_municipio
INTO temp_CGUSC.fp.indicador_receita_por_paciente_mun
FROM temp_CGUSC.fp.indicador_receita_por_paciente I
INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj;

CREATE CLUSTERED INDEX IDX_IndRecPacMun ON temp_CGUSC.fp.indicador_receita_por_paciente_mun(uf, municipio);


-- ============================================================================
-- PASSO 4: METRICAS POR ESTADO (MEDIA E MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_receita_por_paciente_uf;

SELECT DISTINCT
    CAST(F.uf AS VARCHAR(2)) AS uf,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.receita_por_paciente_mensal)
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)))
    AS DECIMAL(18,4)) AS mediana_estado,
    CAST(
        AVG(I.receita_por_paciente_mensal)
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)))
    AS DECIMAL(18,4)) AS media_estado
INTO temp_CGUSC.fp.indicador_receita_por_paciente_uf
FROM temp_CGUSC.fp.indicador_receita_por_paciente I
INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj;

CREATE CLUSTERED INDEX IDX_IndRecPacUF ON temp_CGUSC.fp.indicador_receita_por_paciente_uf(uf);


-- ============================================================================
-- PASSO 5: METRICAS NACIONAIS (MEDIA E MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_receita_por_paciente_br;

SELECT DISTINCT
    'BR' AS pais,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY receita_por_paciente_mensal) OVER ()
    AS DECIMAL(18,4)) AS mediana_pais,
    CAST(
        AVG(receita_por_paciente_mensal) OVER ()
    AS DECIMAL(18,4)) AS media_pais
INTO temp_CGUSC.fp.indicador_receita_por_paciente_br
FROM temp_CGUSC.fp.indicador_receita_por_paciente;


-- ============================================================================
-- PASSO 6: TABELA CONSOLIDADA FINAL
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_receita_por_paciente_detalhado;

SELECT
    I.cnpj,
    F.razaoSocial,
    F.municipio,
    CAST(F.uf AS VARCHAR(2)) AS uf,

    -- Indicadores base
    I.valor_total_periodo,
    I.qtd_pacientes_distintos,
    I.qtd_meses_ativos,
    I.receita_por_paciente,
    I.receita_por_paciente_mensal,

    -- Rankings baseados na receita mensal por paciente (pior risco = posicao 1)
    RANK() OVER (
        ORDER BY I.receita_por_paciente_mensal DESC
    ) AS ranking_br,
    RANK() OVER (
        PARTITION BY CAST(F.uf AS VARCHAR(2))
        ORDER BY I.receita_por_paciente_mensal DESC
    ) AS ranking_uf,
    RANK() OVER (
        PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255))
        ORDER BY I.receita_por_paciente_mensal DESC
    ) AS ranking_municipio,

    -- Benchmarks municipais
    ISNULL(MUN.mediana_municipio, 0) AS municipio_mediana,
    ISNULL(MUN.media_municipio,   0) AS municipio_media,
    CAST((I.receita_por_paciente_mensal + 0.01) / (ISNULL(MUN.mediana_municipio, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_mediana,
    CAST((I.receita_por_paciente_mensal + 0.01) / (ISNULL(MUN.media_municipio,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_media,

    -- Benchmarks estaduais
    ISNULL(UF.mediana_estado, 0) AS estado_mediana,
    ISNULL(UF.media_estado,   0) AS estado_media,
    CAST((I.receita_por_paciente_mensal + 0.01) / (ISNULL(UF.mediana_estado, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_mediana,
    CAST((I.receita_por_paciente_mensal + 0.01) / (ISNULL(UF.media_estado,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_media,

    -- Benchmarks nacionais
    BR.mediana_pais AS pais_mediana,
    BR.media_pais   AS pais_media,
    CAST((I.receita_por_paciente_mensal + 0.01) / (BR.mediana_pais + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_mediana,
    CAST((I.receita_por_paciente_mensal + 0.01) / (BR.media_pais   + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_media

INTO temp_CGUSC.fp.indicador_receita_por_paciente_detalhado
FROM temp_CGUSC.fp.indicador_receita_por_paciente I
INNER JOIN temp_CGUSC.fp.dados_farmacia F
    ON F.cnpj = I.cnpj
LEFT JOIN temp_CGUSC.fp.indicador_receita_por_paciente_mun MUN
    ON CAST(F.uf AS VARCHAR(2))          = MUN.uf
   AND CAST(F.municipio AS VARCHAR(255)) = MUN.municipio
LEFT JOIN temp_CGUSC.fp.indicador_receita_por_paciente_uf UF
    ON CAST(F.uf AS VARCHAR(2)) = UF.uf
CROSS JOIN temp_CGUSC.fp.indicador_receita_por_paciente_br BR;

CREATE CLUSTERED INDEX    IDX_FinalRecPac_CNPJ  ON temp_CGUSC.fp.indicador_receita_por_paciente_detalhado(cnpj);
CREATE NONCLUSTERED INDEX IDX_FinalRecPac_Risco ON temp_CGUSC.fp.indicador_receita_por_paciente_detalhado(risco_relativo_mun_mediana DESC);
CREATE NONCLUSTERED INDEX IDX_FinalRecPac_Rank  ON temp_CGUSC.fp.indicador_receita_por_paciente_detalhado(ranking_br);
GO

-- Verificacao rapida
SELECT TOP 100 *
FROM temp_CGUSC.fp.indicador_receita_por_paciente_detalhado
ORDER BY ranking_br;
