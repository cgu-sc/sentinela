USE [temp_CGUSC]
GO

-- ============================================================================
-- DEFINICAO DE VARIAVEIS DO PERIODO
-- ============================================================================
DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim    DATE = '2024-12-10';


-- ============================================================================
-- PASSO 1: CALCULO BASE POR FARMACIA
-- Identifica vendas com inconsistencia demografica/clinica:
--   - Osteoporose dispensada para paciente do sexo masculino
--   - Diabetes dispensado para paciente com idade < 20 anos
--   - Doenca de Parkinson dispensada para paciente com idade < 50 anos
--   - Hipertensao dispensada para paciente com idade < 20 anos
-- Unidade de analise: num_autorizacao (colapsa itens da mesma venda)
-- ============================================================================
PRINT '=======================================================================';
PRINT 'PASSO 1: Calculando indicador base por farmacia...';
PRINT '=======================================================================';

DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_inconsistencia_clinica;

WITH CalculoDemografico AS (
    SELECT
        A.cnpj,
        A.num_autorizacao,
        MIN(A.data_hora) AS data_hora_venda,
        -- Flag de venda suspeita: basta 1 item inconsistente para marcar a autorizacao
        MAX(CASE
            WHEN C.Patologia = 'Osteoporose'        AND B.idSexo = 'M'                                                                     THEN 1
            WHEN C.Patologia = 'Diabetes'            AND FLOOR(DATEDIFF(DAY, B.dataNascimento, A.data_hora) / 365.25) < 20                  THEN 1
            WHEN C.Patologia = 'Doenca De Parkinson' AND FLOOR(DATEDIFF(DAY, B.dataNascimento, A.data_hora) / 365.25) < 50                  THEN 1
            WHEN C.Patologia = 'Hipertensao'         AND FLOOR(DATEDIFF(DAY, B.dataNascimento, A.data_hora) / 365.25) < 20                  THEN 1
            ELSE 0
        END) AS flag_venda_suspeita
    FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
    INNER JOIN temp_CGUSC.fp.medicamentos_patologia C
        ON C.codigo_barra = A.codigo_barra
    INNER JOIN db_CPF.dbo.CPF B
        ON B.CPF = A.cpf
    WHERE A.data_hora >= @DataInicio
      AND A.data_hora <= @DataFim
      AND B.dataNascimento IS NOT NULL
    GROUP BY A.cnpj, A.num_autorizacao
),
AgregadoPorFarmacia AS (
    SELECT
        cnpj,
        COUNT(*)                 AS total_vendas_monitoradas,
        SUM(flag_venda_suspeita) AS qtd_vendas_suspeitas
    FROM CalculoDemografico
    GROUP BY cnpj
)
SELECT
    cnpj,
    total_vendas_monitoradas,
    qtd_vendas_suspeitas,
    CAST(
        CASE
            WHEN total_vendas_monitoradas > 0
                THEN (CAST(qtd_vendas_suspeitas AS DECIMAL(18,2)) / CAST(total_vendas_monitoradas AS DECIMAL(18,2))) * 100.0
            ELSE 0
        END
    AS DECIMAL(18,4)) AS percentual_inconsistencia
INTO temp_CGUSC.fp.indicador_inconsistencia_clinica
FROM AgregadoPorFarmacia
WHERE total_vendas_monitoradas > 0;

CREATE CLUSTERED INDEX IDX_IndDemo_CNPJ ON temp_CGUSC.fp.indicador_inconsistencia_clinica(cnpj);

PRINT CONCAT('  Farmacias calculadas: ', @@ROWCOUNT);


-- ============================================================================
-- PASSO 2: METRICAS POR MUNICIPIO (MEDIA E MEDIANA)
-- ============================================================================
PRINT 'PASSO 2: Calculando metricas por municipio...';

DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_inconsistencia_clinica_mun;

SELECT DISTINCT
    CAST(F.uf        AS VARCHAR(2))   AS uf,
    CAST(F.municipio AS VARCHAR(255)) AS municipio,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.percentual_inconsistencia)
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255)))
    AS DECIMAL(18,4)) AS mediana_municipio,
    CAST(
        AVG(I.percentual_inconsistencia)
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255)))
    AS DECIMAL(18,4)) AS media_municipio
INTO temp_CGUSC.fp.indicador_inconsistencia_clinica_mun
FROM temp_CGUSC.fp.indicador_inconsistencia_clinica I
INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj;

CREATE CLUSTERED INDEX IDX_IndDemoMun_mun ON temp_CGUSC.fp.indicador_inconsistencia_clinica_mun(uf, municipio);


-- ============================================================================
-- PASSO 3: METRICAS POR ESTADO (MEDIA E MEDIANA)
-- ============================================================================
PRINT 'PASSO 3: Calculando metricas por estado...';

DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_inconsistencia_clinica_uf;

SELECT DISTINCT
    CAST(F.uf AS VARCHAR(2)) AS uf,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.percentual_inconsistencia)
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)))
    AS DECIMAL(18,4)) AS mediana_estado,
    CAST(
        AVG(I.percentual_inconsistencia)
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)))
    AS DECIMAL(18,4)) AS media_estado
INTO temp_CGUSC.fp.indicador_inconsistencia_clinica_uf
FROM temp_CGUSC.fp.indicador_inconsistencia_clinica I
INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj;

CREATE CLUSTERED INDEX IDX_IndDemoUF_uf ON temp_CGUSC.fp.indicador_inconsistencia_clinica_uf(uf);


-- ============================================================================
-- PASSO 4: METRICA NACIONAL (MEDIA E MEDIANA)
-- ============================================================================
PRINT 'PASSO 4: Calculando metricas nacionais...';

DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_inconsistencia_clinica_br;

SELECT DISTINCT
    'BR' AS pais,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY percentual_inconsistencia) OVER ()
    AS DECIMAL(18,4)) AS mediana_pais,
    CAST(
        AVG(percentual_inconsistencia) OVER ()
    AS DECIMAL(18,4)) AS media_pais
INTO temp_CGUSC.fp.indicador_inconsistencia_clinica_br
FROM temp_CGUSC.fp.indicador_inconsistencia_clinica;


-- ============================================================================
-- PASSO 5: TABELA CONSOLIDADA FINAL
-- Rankings, benchmarks e riscos relativos por farmacia.
-- Risco relativo calculado com suavizacao (+0.01) para evitar divisao por zero.
-- ============================================================================
PRINT 'PASSO 5: Gerando tabela consolidada com riscos relativos e rankings...';

DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_inconsistencia_clinica_detalhado;

SELECT
    I.cnpj,
    F.razaoSocial,
    F.municipio,
    CAST(F.uf AS VARCHAR(2)) AS uf,

    -- Indicadores base
    I.total_vendas_monitoradas,
    I.qtd_vendas_suspeitas,
    I.percentual_inconsistencia,

    -- Rankings (pior risco = posicao 1)
    RANK() OVER (
        ORDER BY I.percentual_inconsistencia DESC
    )                                                                   AS ranking_br,
    RANK() OVER (
        PARTITION BY CAST(F.uf AS VARCHAR(2))
        ORDER BY I.percentual_inconsistencia DESC
    )                                                                   AS ranking_uf,
    RANK() OVER (
        PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255))
        ORDER BY I.percentual_inconsistencia DESC
    )                                                                   AS ranking_municipio,

    -- Benchmarks municipais
    ISNULL(MUN.mediana_municipio, 0)                                    AS municipio_mediana,
    ISNULL(MUN.media_municipio,   0)                                    AS municipio_media,
    CAST((I.percentual_inconsistencia + 0.01) / (ISNULL(MUN.mediana_municipio, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_mediana,
    CAST((I.percentual_inconsistencia + 0.01) / (ISNULL(MUN.media_municipio,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_media,

    -- Benchmarks estaduais
    ISNULL(UF.mediana_estado, 0)                                        AS estado_mediana,
    ISNULL(UF.media_estado,   0)                                        AS estado_media,
    CAST((I.percentual_inconsistencia + 0.01) / (ISNULL(UF.mediana_estado, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_mediana,
    CAST((I.percentual_inconsistencia + 0.01) / (ISNULL(UF.media_estado,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_media,

    -- Benchmarks nacionais
    BR.mediana_pais                                                     AS pais_mediana,
    BR.media_pais                                                       AS pais_media,
    CAST((I.percentual_inconsistencia + 0.01) / (BR.mediana_pais + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_mediana,
    CAST((I.percentual_inconsistencia + 0.01) / (BR.media_pais   + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_media

INTO temp_CGUSC.fp.indicador_inconsistencia_clinica_detalhado
FROM temp_CGUSC.fp.indicador_inconsistencia_clinica I
INNER JOIN temp_CGUSC.fp.dados_farmacia F
    ON F.cnpj = I.cnpj
LEFT JOIN temp_CGUSC.fp.indicador_inconsistencia_clinica_mun MUN
    ON CAST(F.uf AS VARCHAR(2))          = MUN.uf
   AND CAST(F.municipio AS VARCHAR(255)) = MUN.municipio
LEFT JOIN temp_CGUSC.fp.indicador_inconsistencia_clinica_uf UF
    ON CAST(F.uf AS VARCHAR(2)) = UF.uf
CROSS JOIN temp_CGUSC.fp.indicador_inconsistencia_clinica_br BR;

CREATE CLUSTERED INDEX IDX_FinalDemo_CNPJ     ON temp_CGUSC.fp.indicador_inconsistencia_clinica_detalhado(cnpj);
CREATE NONCLUSTERED INDEX IDX_FinalDemo_Risco  ON temp_CGUSC.fp.indicador_inconsistencia_clinica_detalhado(percentual_inconsistencia DESC);
CREATE NONCLUSTERED INDEX IDX_FinalDemo_RankBR ON temp_CGUSC.fp.indicador_inconsistencia_clinica_detalhado(ranking_br);

PRINT CONCAT('  Tabela consolidada criada com ', @@ROWCOUNT, ' registros');
PRINT '=======================================================================';
PRINT 'PROCESSO COMPLETO FINALIZADO COM SUCESSO!';
PRINT '';
PRINT 'Tabelas criadas:';
PRINT '  1. indicador_inconsistencia_clinica (base)';
PRINT '  2. indicador_inconsistencia_clinica_mun (metricas por municipio)';
PRINT '  3. indicador_inconsistencia_clinica_uf (metricas por estado)';
PRINT '  4. indicador_inconsistencia_clinica_br (metricas nacionais)';
PRINT '  5. indicador_inconsistencia_clinica_detalhado (tabela final com riscos e rankings)';
PRINT '=======================================================================';
GO

-- ============================================================================
-- VERIFICACAO RAPIDA
-- ============================================================================
SELECT TOP 100 *
FROM temp_CGUSC.fp.indicador_inconsistencia_clinica_detalhado
ORDER BY ranking_br;