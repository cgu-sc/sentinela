USE [temp_CGUSC]
GO

-- ============================================================================
-- DEFINICAO DE VARIAVEIS
-- ============================================================================
DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim    DATE = '2024-12-10';


-- ============================================================================
-- PASSO 1: CALCULO BASE POR FARMACIA (HORARIO ATIPICO)
-- Consideramos madrugada: 00:00 até 05:59
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_horario_atipico;

WITH VendasPorHorario AS (
    SELECT 
        A.cnpj,
        A.num_autorizacao,
        MIN(A.data_hora) AS data_hora_venda,
        
        -- Verifica se a venda ocorreu na madrugada
        MAX(CASE 
            WHEN DATEPART(HOUR, A.data_hora) BETWEEN 0 AND 5 THEN 1 
            ELSE 0 
        END) AS flag_madrugada

    FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
    INNER JOIN temp_CGUSC.fp.medicamentos_patologia C 
        ON C.codigo_barra = A.codigo_barra
    INNER JOIN temp_CGUSC.fp.lista_cnpj_processamento L
        ON L.cnpj = A.cnpj
    WHERE 
        A.data_hora >= @DataInicio 
        AND A.data_hora <= @DataFim

    GROUP BY A.cnpj, A.num_autorizacao
),
AgregadoPorFarmacia AS (
    SELECT 
        cnpj,
        COUNT(*) AS total_vendas_monitoradas,
        SUM(flag_madrugada) AS qtd_vendas_madrugada
    FROM VendasPorHorario
    GROUP BY cnpj
)
SELECT 
    cnpj,
    total_vendas_monitoradas,
    qtd_vendas_madrugada,
    CAST(
        CASE 
            WHEN total_vendas_monitoradas > 0 THEN 
                (CAST(qtd_vendas_madrugada AS DECIMAL(18,2)) / CAST(total_vendas_monitoradas AS DECIMAL(18,2))) * 100.0
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS percentual_madrugada
INTO temp_CGUSC.fp.indicador_horario_atipico
FROM AgregadoPorFarmacia
WHERE total_vendas_monitoradas > 0;

CREATE CLUSTERED INDEX IDX_IndHora_CNPJ ON temp_CGUSC.fp.indicador_horario_atipico(cnpj);


-- ============================================================================
-- PASSO 2: METRICAS POR MUNICIPIO (MEDIA E MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_horario_atipico_mun;

SELECT DISTINCT
    CAST(F.uf AS VARCHAR(2))          AS uf,
    CAST(F.municipio AS VARCHAR(255)) AS municipio,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.percentual_madrugada)
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255)))
    AS DECIMAL(18,4)) AS mediana_municipio,
    CAST(
        AVG(I.percentual_madrugada)
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255)))
    AS DECIMAL(18,4)) AS media_municipio
INTO temp_CGUSC.fp.indicador_horario_atipico_mun
FROM temp_CGUSC.fp.indicador_horario_atipico I
INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj;

CREATE CLUSTERED INDEX IDX_IndHoraMun ON temp_CGUSC.fp.indicador_horario_atipico_mun(uf, municipio);


-- ============================================================================
-- PASSO 3: METRICAS POR ESTADO (MEDIA E MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_horario_atipico_uf;

SELECT DISTINCT
    CAST(F.uf AS VARCHAR(2)) AS uf,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.percentual_madrugada)
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)))
    AS DECIMAL(18,4)) AS mediana_estado,
    CAST(
        AVG(I.percentual_madrugada)
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)))
    AS DECIMAL(18,4)) AS media_estado
INTO temp_CGUSC.fp.indicador_horario_atipico_uf
FROM temp_CGUSC.fp.indicador_horario_atipico I
INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj;

CREATE CLUSTERED INDEX IDX_IndHoraUF ON temp_CGUSC.fp.indicador_horario_atipico_uf(uf);


-- ============================================================================
-- PASSO 4: METRICAS NACIONAIS (MEDIA E MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_horario_atipico_br;

SELECT DISTINCT
    'BR' AS pais,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY percentual_madrugada) OVER ()
    AS DECIMAL(18,4)) AS mediana_pais,
    CAST(
        AVG(percentual_madrugada) OVER ()
    AS DECIMAL(18,4)) AS media_pais
INTO temp_CGUSC.fp.indicador_horario_atipico_br
FROM temp_CGUSC.fp.indicador_horario_atipico;


-- ============================================================================
-- PASSO 5: TABELA CONSOLIDADA FINAL
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_horario_atipico_detalhado;

SELECT 
    I.cnpj,
    F.razaoSocial,
    F.municipio,
    CAST(F.uf AS VARCHAR(2)) AS uf,
    
    I.total_vendas_monitoradas,
    I.qtd_vendas_madrugada,
    I.percentual_madrugada,
    
    -- Rankings
    RANK() OVER (ORDER BY I.percentual_madrugada DESC) AS ranking_br,
    RANK() OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)) ORDER BY I.percentual_madrugada DESC) AS ranking_uf,

    -- Benchmarks municipais
    ISNULL(MUN.mediana_municipio, 0) AS municipio_mediana,
    ISNULL(MUN.media_municipio,   0) AS municipio_media,
    CAST((I.percentual_madrugada + 0.01) / (ISNULL(MUN.mediana_municipio, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_mediana,
    CAST((I.percentual_madrugada + 0.01) / (ISNULL(MUN.media_municipio,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_media,

    -- Benchmarks estaduais
    ISNULL(UF.mediana_estado, 0) AS estado_mediana,
    ISNULL(UF.media_estado,   0) AS estado_media,
    CAST((I.percentual_madrugada + 0.01) / (ISNULL(UF.mediana_estado, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_mediana,
    CAST((I.percentual_madrugada + 0.01) / (ISNULL(UF.media_estado,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_media,

    -- Benchmarks nacionais
    BR.mediana_pais AS pais_mediana,
    BR.media_pais   AS pais_media,
    CAST((I.percentual_madrugada + 0.01) / (BR.mediana_pais + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_mediana,
    CAST((I.percentual_madrugada + 0.01) / (BR.media_pais   + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_media

INTO temp_CGUSC.fp.indicador_horario_atipico_detalhado
FROM temp_CGUSC.fp.indicador_horario_atipico I
INNER JOIN temp_CGUSC.fp.dados_farmacia F 
    ON F.cnpj = I.cnpj
LEFT JOIN temp_CGUSC.fp.indicador_horario_atipico_mun MUN 
    ON CAST(F.uf AS VARCHAR(2))          = MUN.uf
   AND CAST(F.municipio AS VARCHAR(255)) = MUN.municipio
LEFT JOIN temp_CGUSC.fp.indicador_horario_atipico_uf UF 
    ON CAST(F.uf AS VARCHAR(2)) = UF.uf
CROSS JOIN temp_CGUSC.fp.indicador_horario_atipico_br BR;

CREATE CLUSTERED INDEX IDX_FinalHora_CNPJ ON temp_CGUSC.fp.indicador_horario_atipico_detalhado(cnpj);
CREATE NONCLUSTERED INDEX IDX_FinalHora_Risco ON temp_CGUSC.fp.indicador_horario_atipico_detalhado(risco_relativo_uf_media DESC);
GO

-- Verificacao rapida
SELECT TOP 100 * FROM temp_CGUSC.fp.indicador_horario_atipico_detalhado ORDER BY ranking_br;
