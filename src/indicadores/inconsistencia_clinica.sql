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
        SUM(A.valor_pago) AS valor_total_autorizacao,
        SUM(CASE
            WHEN C.Patologia = 'OSTEOPOROSE'         AND B.idSexo = 'M'                                                                     THEN A.valor_pago
            WHEN C.Patologia = 'DIABETES'             AND FLOOR(DATEDIFF(DAY, B.dataNascimento, A.data_hora) / 365.25) < 20                  THEN A.valor_pago
            WHEN C.Patologia = 'DOENCA DE PARKINSON'  AND FLOOR(DATEDIFF(DAY, B.dataNascimento, A.data_hora) / 365.25) < 50                  THEN A.valor_pago
            WHEN C.Patologia = 'HIPERTENSAO'          AND FLOOR(DATEDIFF(DAY, B.dataNascimento, A.data_hora) / 365.25) < 20                  THEN A.valor_pago
            ELSE 0
        END) AS valor_itens_suspeitos,
        -- Flag de venda suspeita: basta 1 item inconsistente para marcar a autorizacao
        MAX(CASE
            WHEN C.Patologia = 'OSTEOPOROSE'         AND B.idSexo = 'M'                                                                     THEN 1
            WHEN C.Patologia = 'DIABETES'             AND FLOOR(DATEDIFF(DAY, B.dataNascimento, A.data_hora) / 365.25) < 20                  THEN 1
            WHEN C.Patologia = 'DOENCA DE PARKINSON'  AND FLOOR(DATEDIFF(DAY, B.dataNascimento, A.data_hora) / 365.25) < 50                  THEN 1
            WHEN C.Patologia = 'HIPERTENSAO'          AND FLOOR(DATEDIFF(DAY, B.dataNascimento, A.data_hora) / 365.25) < 20                  THEN 1
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
        SUM(flag_venda_suspeita) AS qtd_vendas_suspeitas,
        SUM(valor_total_autorizacao) AS valor_vendas_monitoradas,
        SUM(CASE WHEN flag_venda_suspeita = 1 THEN valor_itens_suspeitos ELSE 0 END) AS valor_vendas_suspeitas
    FROM CalculoDemografico
    GROUP BY cnpj
)
SELECT
    cnpj,
    total_vendas_monitoradas,
    qtd_vendas_suspeitas,
    CAST(ISNULL(valor_vendas_monitoradas, 0) AS DECIMAL(18,2)) AS valor_vendas_monitoradas,
    CAST(ISNULL(valor_vendas_suspeitas, 0) AS DECIMAL(18,2)) AS valor_vendas_suspeitas,
    CAST(
        CASE
            WHEN total_vendas_monitoradas > 0
                THEN (CAST(qtd_vendas_suspeitas AS DECIMAL(18,2)) / CAST(total_vendas_monitoradas AS DECIMAL(18,2))) * 100.0
            ELSE 0
        END
    AS DECIMAL(18,4)) AS percentual_inconsistencia,
    CAST(
        CASE
            WHEN ISNULL(valor_vendas_monitoradas, 0) > 0
                THEN (CAST(valor_vendas_suspeitas AS DECIMAL(18,2)) / CAST(valor_vendas_monitoradas AS DECIMAL(18,2))) * 100.0
            ELSE 0
        END
    AS DECIMAL(18,4)) AS percentual_valor_inconsistencia
INTO temp_CGUSC.fp.indicador_inconsistencia_clinica
FROM AgregadoPorFarmacia
WHERE total_vendas_monitoradas > 0;

CREATE CLUSTERED INDEX IDX_IndDemo_CNPJ ON temp_CGUSC.fp.indicador_inconsistencia_clinica(cnpj);

PRINT CONCAT('  Farmacias calculadas: ', @@ROWCOUNT);


-- ============================================================================
-- PASSO 2: METRICAS POR MUNICIPIO (MEDIANA)
-- ============================================================================
PRINT 'PASSO 2: Calculando metricas por municipio...';

DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_inconsistencia_clinica_mun;

SELECT DISTINCT
    F.uf,
    F.municipio,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.percentual_inconsistencia, 0))
        OVER (PARTITION BY F.uf, F.municipio)
    AS DECIMAL(18,4)) AS mediana_municipio,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.valor_vendas_suspeitas, 0))
        OVER (PARTITION BY F.uf, F.municipio)
    AS DECIMAL(18,2)) AS mediana_valor_municipio
INTO temp_CGUSC.fp.indicador_inconsistencia_clinica_mun
FROM temp_CGUSC.fp.dados_farmacia F
LEFT JOIN temp_CGUSC.fp.indicador_inconsistencia_clinica I ON I.cnpj = F.cnpj;

CREATE CLUSTERED INDEX IDX_IndDemoMun_mun ON temp_CGUSC.fp.indicador_inconsistencia_clinica_mun(uf, municipio);


-- ============================================================================
-- PASSO 3: METRICAS POR ESTADO (MEDIANA)
-- ============================================================================
PRINT 'PASSO 3: Calculando metricas por estado...';

DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_inconsistencia_clinica_uf;

SELECT DISTINCT
    F.uf,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.percentual_inconsistencia, 0))
        OVER (PARTITION BY F.uf)
    AS DECIMAL(18,4)) AS mediana_estado,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.valor_vendas_suspeitas, 0))
        OVER (PARTITION BY F.uf)
    AS DECIMAL(18,2)) AS mediana_valor_estado
INTO temp_CGUSC.fp.indicador_inconsistencia_clinica_uf
FROM temp_CGUSC.fp.dados_farmacia F
LEFT JOIN temp_CGUSC.fp.indicador_inconsistencia_clinica I ON I.cnpj = F.cnpj;

CREATE CLUSTERED INDEX IDX_IndDemoUF_uf ON temp_CGUSC.fp.indicador_inconsistencia_clinica_uf(uf);


-- ============================================================================
-- PASSO 3B: METRICAS POR REGIAO DE SAUDE (MEDIANA)
-- ============================================================================
PRINT 'PASSO 3B: Calculando metricas por regiao de saude...';

DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_inconsistencia_clinica_regiao;

SELECT DISTINCT
    F.id_regiao_saude,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.percentual_inconsistencia, 0))
        OVER (PARTITION BY F.id_regiao_saude)
    AS DECIMAL(18,4)) AS mediana_regiao,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.valor_vendas_suspeitas, 0))
        OVER (PARTITION BY F.id_regiao_saude)
    AS DECIMAL(18,2)) AS mediana_valor_regiao
INTO temp_CGUSC.fp.indicador_inconsistencia_clinica_regiao
FROM temp_CGUSC.fp.dados_farmacia F
LEFT JOIN temp_CGUSC.fp.indicador_inconsistencia_clinica I ON I.cnpj = F.cnpj
WHERE F.id_regiao_saude IS NOT NULL;

CREATE CLUSTERED INDEX IDX_IndDemoReg ON temp_CGUSC.fp.indicador_inconsistencia_clinica_regiao(id_regiao_saude);


-- ============================================================================
-- PASSO 4: METRICA NACIONAL (MEDIANA)
-- ============================================================================
PRINT 'PASSO 4: Calculando metricas nacionais...';

DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_inconsistencia_clinica_br;

SELECT DISTINCT
    'BR' AS pais,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(percentual_inconsistencia, 0)) OVER ()
    AS DECIMAL(18,4)) AS mediana_pais,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(valor_vendas_suspeitas, 0)) OVER ()
    AS DECIMAL(18,2)) AS mediana_valor_pais
INTO temp_CGUSC.fp.indicador_inconsistencia_clinica_br
FROM temp_CGUSC.fp.dados_farmacia F
LEFT JOIN temp_CGUSC.fp.indicador_inconsistencia_clinica I ON I.cnpj = F.cnpj;


-- ============================================================================
-- PASSO 5: TABELA CONSOLIDADA FINAL
-- Rankings, benchmarks e riscos relativos por farmacia.
-- Risco relativo calculado com suavizacao (+0.01) para evitar divisao por zero.
-- ============================================================================
PRINT 'PASSO 5: Gerando tabela consolidada com riscos relativos e rankings...';

DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_inconsistencia_clinica_detalhado;

SELECT
    F.cnpj,
    F.razaoSocial,
    F.municipio,
    F.uf,
    F.no_regiao_saude,
    F.id_regiao_saude,

    -- Indicadores base
    ISNULL(I.total_vendas_monitoradas, 0) AS total_vendas_monitoradas,
    ISNULL(I.qtd_vendas_suspeitas, 0) AS qtd_vendas_suspeitas,
    ISNULL(I.valor_vendas_monitoradas, 0) AS valor_vendas_monitoradas,
    ISNULL(I.valor_vendas_suspeitas, 0) AS valor_vendas_suspeitas,
    ISNULL(I.percentual_inconsistencia, 0) AS percentual_inconsistencia,
    ISNULL(I.percentual_valor_inconsistencia, 0) AS percentual_valor_inconsistencia,

    -- Rankings (pior risco = posicao 1)
    RANK() OVER (
        ORDER BY ISNULL(I.percentual_inconsistencia, 0) DESC
    )                                                                   AS ranking_br,
    RANK() OVER (
        PARTITION BY F.uf
        ORDER BY ISNULL(I.percentual_inconsistencia, 0) DESC
    )                                                                   AS ranking_uf,
    RANK() OVER (
        PARTITION BY F.id_regiao_saude
        ORDER BY ISNULL(I.percentual_inconsistencia, 0) DESC
    )                                                                   AS ranking_regiao_saude,
    RANK() OVER (
        PARTITION BY F.uf, F.municipio
        ORDER BY ISNULL(I.percentual_inconsistencia, 0) DESC
    )                                                                   AS ranking_municipio,

    -- Benchmarks municipais
    ISNULL(MUN.mediana_municipio, 0)                                    AS municipio_mediana,
    ISNULL(MUN.mediana_valor_municipio, 0)                              AS municipio_valor_mediana,
    CAST((ISNULL(I.percentual_inconsistencia, 0) + 0.01) / (ISNULL(MUN.mediana_municipio, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_mediana,
    CAST((ISNULL(I.valor_vendas_suspeitas, 0) + 0.01) / (ISNULL(MUN.mediana_valor_municipio, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_valor_mun_mediana,

    -- Benchmarks estaduais
    ISNULL(UF.mediana_estado, 0)                                        AS estado_mediana,
    ISNULL(UF.mediana_valor_estado, 0)                                  AS estado_valor_mediana,
    CAST((ISNULL(I.percentual_inconsistencia, 0) + 0.01) / (ISNULL(UF.mediana_estado, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_mediana,
    CAST((ISNULL(I.valor_vendas_suspeitas, 0) + 0.01) / (ISNULL(UF.mediana_valor_estado, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_valor_uf_mediana,

    -- Benchmarks Regionais (Regiao de Saude)
    ISNULL(REG.mediana_regiao, 0)                                       AS regiao_saude_mediana,
    ISNULL(REG.mediana_valor_regiao, 0)                                 AS regiao_saude_valor_mediana,
    CAST((ISNULL(I.percentual_inconsistencia, 0) + 0.01) / (ISNULL(REG.mediana_regiao, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_reg_mediana,
    CAST((ISNULL(I.valor_vendas_suspeitas, 0) + 0.01) / (ISNULL(REG.mediana_valor_regiao, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_valor_reg_mediana,

    -- Benchmarks nacionais
    BR.mediana_pais                                                     AS pais_mediana,
    BR.mediana_valor_pais                                               AS pais_valor_mediana,
    CAST((ISNULL(I.percentual_inconsistencia, 0) + 0.01) / (BR.mediana_pais + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_mediana,
    CAST((ISNULL(I.valor_vendas_suspeitas, 0) + 0.01) / (BR.mediana_valor_pais + 0.01) AS DECIMAL(18,4)) AS risco_relativo_valor_br_mediana

INTO temp_CGUSC.fp.indicador_inconsistencia_clinica_detalhado
FROM temp_CGUSC.fp.dados_farmacia F
LEFT JOIN temp_CGUSC.fp.indicador_inconsistencia_clinica I
    ON I.cnpj = F.cnpj
LEFT JOIN temp_CGUSC.fp.indicador_inconsistencia_clinica_mun MUN
    ON F.uf        = MUN.uf
   AND F.municipio = MUN.municipio
LEFT JOIN temp_CGUSC.fp.indicador_inconsistencia_clinica_uf UF
    ON F.uf = UF.uf
LEFT JOIN temp_CGUSC.fp.indicador_inconsistencia_clinica_regiao REG
    ON F.id_regiao_saude = REG.id_regiao_saude
CROSS JOIN temp_CGUSC.fp.indicador_inconsistencia_clinica_br BR;

CREATE CLUSTERED INDEX IDX_FinalDemo_CNPJ     ON temp_CGUSC.fp.indicador_inconsistencia_clinica_detalhado(cnpj);
CREATE NONCLUSTERED INDEX IDX_FinalDemo_Risco  ON temp_CGUSC.fp.indicador_inconsistencia_clinica_detalhado(percentual_inconsistencia DESC);
CREATE NONCLUSTERED INDEX IDX_FinalDemo_RankBR ON temp_CGUSC.fp.indicador_inconsistencia_clinica_detalhado(ranking_br);

PRINT CONCAT('  Tabela consolidada criada com ', @@ROWCOUNT, ' registros');

-- ============================================================================
-- PASSO 6: LIMPEZA DAS TABELAS INTERMEDIARIAS
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_inconsistencia_clinica;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_inconsistencia_clinica_mun;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_inconsistencia_clinica_uf;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_inconsistencia_clinica_regiao;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_inconsistencia_clinica_br;
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
