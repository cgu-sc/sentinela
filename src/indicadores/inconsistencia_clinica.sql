USE [temp_CGUSC]
GO

-- ============================================================================
-- DEFINICAO DE VARIAVEIS DO PERIODO
-- ============================================================================
DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim    DATE = '2024-12-10';
DECLARE @QtdAutorizacoes INT;
DECLARE @QtdFarmaciasAno INT;
DECLARE @QtdFinal INT;


-- ============================================================================
-- INDICADOR DE INCONSISTENCIA CLINICA - SNAPSHOT ANUAL
-- Unidade final de analise: CNPJ x ano_referencia.
--
-- Identifica vendas com inconsistencia demografica/clinica:
--   - Osteoporose dispensada para paciente do sexo masculino
--   - Diabetes dispensado para paciente com idade < 20 anos
--   - Doenca de Parkinson dispensada para paciente com idade < 50 anos
--   - Hipertensao dispensada para paciente com idade < 20 anos
--
-- Observacao: temp_CGUSC.fp.medicamentos_patologia.Patologia deve estar
-- padronizada em maiusculo e sem acentos.
-- ============================================================================
PRINT '=======================================================================';
PRINT 'INDICADOR INCONSISTENCIA CLINICA - SNAPSHOT ANUAL';
PRINT '=======================================================================';


-- ============================================================================
-- PASSO 0: DIMENSAO TEMPORAL DO PERIODO
-- ============================================================================
DROP TABLE IF EXISTS #Anos;

CREATE TABLE #Anos (
    ano_referencia INT NOT NULL PRIMARY KEY
);

DECLARE @AnoAtual INT = YEAR(@DataInicio);
DECLARE @AnoFim   INT = YEAR(@DataFim);

WHILE @AnoAtual <= @AnoFim
BEGIN
    INSERT INTO #Anos (ano_referencia) VALUES (@AnoAtual);
    SET @AnoAtual += 1;
END;


-- ============================================================================
-- PASSO 1: VENDAS POR AUTORIZACAO MATERIALIZADAS EM TEMP TABLE
-- ============================================================================
PRINT 'PASSO 1: Materializando autorizacoes monitoradas...';

DROP TABLE IF EXISTS #CalculoDemografico;

SELECT
    A.cnpj,
    YEAR(A.data_hora) AS ano_referencia,
    A.num_autorizacao,
    MIN(A.data_hora) AS data_hora_venda,
    SUM(ISNULL(A.valor_pago, 0)) AS valor_total_autorizacao,
    SUM(CASE
        WHEN C.Patologia = 'OSTEOPOROSE'        AND B.idSexo = 'M'                                                        THEN ISNULL(A.valor_pago, 0)
        WHEN C.Patologia = 'DIABETES'            AND FLOOR(DATEDIFF(DAY, B.dataNascimento, A.data_hora) / 365.25) < 20     THEN ISNULL(A.valor_pago, 0)
        WHEN C.Patologia = 'DOENCA DE PARKINSON' AND FLOOR(DATEDIFF(DAY, B.dataNascimento, A.data_hora) / 365.25) < 50     THEN ISNULL(A.valor_pago, 0)
        WHEN C.Patologia = 'HIPERTENSAO'         AND FLOOR(DATEDIFF(DAY, B.dataNascimento, A.data_hora) / 365.25) < 20     THEN ISNULL(A.valor_pago, 0)
        ELSE 0
    END) AS valor_itens_suspeitos,
    MAX(CASE
        WHEN C.Patologia = 'OSTEOPOROSE'        AND B.idSexo = 'M'                                                        THEN 1
        WHEN C.Patologia = 'DIABETES'            AND FLOOR(DATEDIFF(DAY, B.dataNascimento, A.data_hora) / 365.25) < 20     THEN 1
        WHEN C.Patologia = 'DOENCA DE PARKINSON' AND FLOOR(DATEDIFF(DAY, B.dataNascimento, A.data_hora) / 365.25) < 50     THEN 1
        WHEN C.Patologia = 'HIPERTENSAO'         AND FLOOR(DATEDIFF(DAY, B.dataNascimento, A.data_hora) / 365.25) < 20     THEN 1
        ELSE 0
    END) AS flag_venda_suspeita
INTO #CalculoDemografico
FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
INNER JOIN temp_CGUSC.fp.medicamentos_patologia C
    ON C.codigo_barra = A.codigo_barra
INNER JOIN db_CPF.dbo.CPF B
    ON B.CPF = A.cpf
WHERE A.data_hora >= @DataInicio
  AND A.data_hora < DATEADD(DAY, 1, @DataFim)
  AND B.dataNascimento IS NOT NULL
  AND C.Patologia IN ('OSTEOPOROSE', 'DIABETES', 'DOENCA DE PARKINSON', 'HIPERTENSAO')
GROUP BY
    A.cnpj,
    YEAR(A.data_hora),
    A.num_autorizacao;

SET @QtdAutorizacoes = @@ROWCOUNT;

CREATE CLUSTERED INDEX IX_CalcDemo_AnoCnpj
    ON #CalculoDemografico (ano_referencia, cnpj);

CREATE NONCLUSTERED INDEX IX_CalcDemo_CnpjAno
    ON #CalculoDemografico (cnpj, ano_referencia)
    INCLUDE (flag_venda_suspeita, valor_total_autorizacao, valor_itens_suspeitos);

PRINT CONCAT('  Autorizacoes monitoradas: ', @QtdAutorizacoes);


-- ============================================================================
-- PASSO 2: AGREGA CNPJ x ANO
-- ============================================================================
PRINT 'PASSO 2: Agregando indicador por farmacia e ano...';

DROP TABLE IF EXISTS #IndicadorInconsistenciaClinica;

SELECT
    cnpj,
    ano_referencia,
    COUNT(*) AS total_vendas_monitoradas,
    SUM(flag_venda_suspeita) AS qtd_vendas_suspeitas,
    CAST(SUM(valor_total_autorizacao) AS DECIMAL(18,2)) AS valor_vendas_monitoradas,
    CAST(SUM(CASE WHEN flag_venda_suspeita = 1 THEN valor_itens_suspeitos ELSE 0 END) AS DECIMAL(18,2)) AS valor_vendas_suspeitas,
    CAST(
        CASE
            WHEN COUNT(*) > 0
                THEN (CAST(SUM(flag_venda_suspeita) AS DECIMAL(18,2)) / CAST(COUNT(*) AS DECIMAL(18,2))) * 100.0
            ELSE 0
        END
    AS DECIMAL(18,4)) AS percentual_inconsistencia,
    CAST(
        CASE
            WHEN SUM(valor_total_autorizacao) > 0
                THEN (CAST(SUM(CASE WHEN flag_venda_suspeita = 1 THEN valor_itens_suspeitos ELSE 0 END) AS DECIMAL(18,2)) / CAST(SUM(valor_total_autorizacao) AS DECIMAL(18,2))) * 100.0
            ELSE 0
        END
    AS DECIMAL(18,4)) AS percentual_valor_inconsistencia
INTO #IndicadorInconsistenciaClinica
FROM #CalculoDemografico
GROUP BY cnpj, ano_referencia;

SET @QtdFarmaciasAno = @@ROWCOUNT;

CREATE CLUSTERED INDEX IX_IndClinico_AnoCnpj
    ON #IndicadorInconsistenciaClinica (ano_referencia, cnpj);

CREATE NONCLUSTERED INDEX IX_IndClinico_CnpjAno
    ON #IndicadorInconsistenciaClinica (cnpj, ano_referencia);

PRINT CONCAT('  Farmacias/ano calculadas: ', @QtdFarmaciasAno);


-- ============================================================================
-- PASSO 3: METRICAS POR MUNICIPIO (MEDIANA)
-- ============================================================================
PRINT 'PASSO 3: Calculando medianas por municipio...';

DROP TABLE IF EXISTS #IndicadorInconsistenciaClinicaMun;

SELECT DISTINCT
    Y.ano_referencia,
    F.uf,
    F.municipio,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.percentual_inconsistencia, 0))
        OVER (PARTITION BY Y.ano_referencia, F.uf, F.municipio)
    AS DECIMAL(18,4)) AS mediana_municipio,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.valor_vendas_suspeitas, 0))
        OVER (PARTITION BY Y.ano_referencia, F.uf, F.municipio)
    AS DECIMAL(18,2)) AS mediana_valor_municipio
INTO #IndicadorInconsistenciaClinicaMun
FROM temp_CGUSC.fp.dados_farmacia F
CROSS JOIN #Anos Y
LEFT JOIN #IndicadorInconsistenciaClinica I
    ON I.cnpj = F.cnpj
   AND I.ano_referencia = Y.ano_referencia;

CREATE CLUSTERED INDEX IX_IndClinicoMun_AnoUfMun
    ON #IndicadorInconsistenciaClinicaMun (ano_referencia, uf, municipio);


-- ============================================================================
-- PASSO 4: METRICAS POR ESTADO (MEDIANA)
-- ============================================================================
PRINT 'PASSO 4: Calculando medianas por estado...';

DROP TABLE IF EXISTS #IndicadorInconsistenciaClinicaUf;

SELECT DISTINCT
    Y.ano_referencia,
    F.uf,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.percentual_inconsistencia, 0))
        OVER (PARTITION BY Y.ano_referencia, F.uf)
    AS DECIMAL(18,4)) AS mediana_estado,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.valor_vendas_suspeitas, 0))
        OVER (PARTITION BY Y.ano_referencia, F.uf)
    AS DECIMAL(18,2)) AS mediana_valor_estado
INTO #IndicadorInconsistenciaClinicaUf
FROM temp_CGUSC.fp.dados_farmacia F
CROSS JOIN #Anos Y
LEFT JOIN #IndicadorInconsistenciaClinica I
    ON I.cnpj = F.cnpj
   AND I.ano_referencia = Y.ano_referencia;

CREATE CLUSTERED INDEX IX_IndClinicoUf_AnoUf
    ON #IndicadorInconsistenciaClinicaUf (ano_referencia, uf);


-- ============================================================================
-- PASSO 5: METRICAS POR REGIAO DE SAUDE (MEDIANA)
-- ============================================================================
PRINT 'PASSO 5: Calculando medianas por regiao de saude...';

DROP TABLE IF EXISTS #IndicadorInconsistenciaClinicaRegiao;

SELECT DISTINCT
    Y.ano_referencia,
    F.id_regiao_saude,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.percentual_inconsistencia, 0))
        OVER (PARTITION BY Y.ano_referencia, F.id_regiao_saude)
    AS DECIMAL(18,4)) AS mediana_regiao,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.valor_vendas_suspeitas, 0))
        OVER (PARTITION BY Y.ano_referencia, F.id_regiao_saude)
    AS DECIMAL(18,2)) AS mediana_valor_regiao
INTO #IndicadorInconsistenciaClinicaRegiao
FROM temp_CGUSC.fp.dados_farmacia F
CROSS JOIN #Anos Y
LEFT JOIN #IndicadorInconsistenciaClinica I
    ON I.cnpj = F.cnpj
   AND I.ano_referencia = Y.ano_referencia
WHERE F.id_regiao_saude IS NOT NULL;

CREATE CLUSTERED INDEX IX_IndClinicoReg_AnoRegiao
    ON #IndicadorInconsistenciaClinicaRegiao (ano_referencia, id_regiao_saude);


-- ============================================================================
-- PASSO 6: METRICA NACIONAL (MEDIANA)
-- ============================================================================
PRINT 'PASSO 6: Calculando medianas nacionais...';

DROP TABLE IF EXISTS #IndicadorInconsistenciaClinicaBr;

SELECT DISTINCT
    Y.ano_referencia,
    'BR' AS pais,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.percentual_inconsistencia, 0))
        OVER (PARTITION BY Y.ano_referencia)
    AS DECIMAL(18,4)) AS mediana_pais,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.valor_vendas_suspeitas, 0))
        OVER (PARTITION BY Y.ano_referencia)
    AS DECIMAL(18,2)) AS mediana_valor_pais
INTO #IndicadorInconsistenciaClinicaBr
FROM temp_CGUSC.fp.dados_farmacia F
CROSS JOIN #Anos Y
LEFT JOIN #IndicadorInconsistenciaClinica I
    ON I.cnpj = F.cnpj
   AND I.ano_referencia = Y.ano_referencia;

CREATE CLUSTERED INDEX IX_IndClinicoBr_Ano
    ON #IndicadorInconsistenciaClinicaBr (ano_referencia);


-- ============================================================================
-- PASSO 7: TABELA CONSOLIDADA FINAL
-- Rankings, benchmarks e riscos relativos por CNPJ x ano.
-- Risco relativo calculado com suavizacao (+0.01) para evitar divisao por zero.
-- ============================================================================
PRINT 'PASSO 7: Gerando tabela consolidada anual...';

DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_inconsistencia_clinica_detalhado;

SELECT
    F.cnpj,
    Y.ano_referencia,
    F.razaoSocial,
    F.municipio,
    F.uf,
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
        PARTITION BY Y.ano_referencia
        ORDER BY ISNULL(I.percentual_inconsistencia, 0) DESC
    ) AS ranking_br,
    RANK() OVER (
        PARTITION BY Y.ano_referencia, F.uf
        ORDER BY ISNULL(I.percentual_inconsistencia, 0) DESC
    ) AS ranking_uf,
    RANK() OVER (
        PARTITION BY Y.ano_referencia, F.id_regiao_saude
        ORDER BY ISNULL(I.percentual_inconsistencia, 0) DESC
    ) AS ranking_regiao_saude,
    RANK() OVER (
        PARTITION BY Y.ano_referencia, F.uf, F.municipio
        ORDER BY ISNULL(I.percentual_inconsistencia, 0) DESC
    ) AS ranking_municipio,

    -- Benchmarks municipais
    ISNULL(MUN.mediana_municipio, 0) AS municipio_mediana,
    ISNULL(MUN.mediana_valor_municipio, 0) AS municipio_valor_mediana,
    CAST((ISNULL(I.percentual_inconsistencia, 0) + 0.01) / (ISNULL(MUN.mediana_municipio, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_mediana,
    CAST((ISNULL(I.valor_vendas_suspeitas, 0) + 0.01) / (ISNULL(MUN.mediana_valor_municipio, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_valor_mun_mediana,

    -- Benchmarks estaduais
    ISNULL(UF.mediana_estado, 0) AS estado_mediana,
    ISNULL(UF.mediana_valor_estado, 0) AS estado_valor_mediana,
    CAST((ISNULL(I.percentual_inconsistencia, 0) + 0.01) / (ISNULL(UF.mediana_estado, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_mediana,
    CAST((ISNULL(I.valor_vendas_suspeitas, 0) + 0.01) / (ISNULL(UF.mediana_valor_estado, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_valor_uf_mediana,

    -- Benchmarks regionais por id_regiao_saude
    ISNULL(REG.mediana_regiao, 0) AS regiao_saude_mediana,
    ISNULL(REG.mediana_valor_regiao, 0) AS regiao_saude_valor_mediana,
    CAST((ISNULL(I.percentual_inconsistencia, 0) + 0.01) / (ISNULL(REG.mediana_regiao, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_reg_mediana,
    CAST((ISNULL(I.valor_vendas_suspeitas, 0) + 0.01) / (ISNULL(REG.mediana_valor_regiao, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_valor_reg_mediana,

    -- Benchmarks nacionais
    BR.mediana_pais AS pais_mediana,
    BR.mediana_valor_pais AS pais_valor_mediana,
    CAST((ISNULL(I.percentual_inconsistencia, 0) + 0.01) / (BR.mediana_pais + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_mediana,
    CAST((ISNULL(I.valor_vendas_suspeitas, 0) + 0.01) / (BR.mediana_valor_pais + 0.01) AS DECIMAL(18,4)) AS risco_relativo_valor_br_mediana

INTO temp_CGUSC.fp.indicador_inconsistencia_clinica_detalhado
FROM temp_CGUSC.fp.dados_farmacia F
CROSS JOIN #Anos Y
LEFT JOIN #IndicadorInconsistenciaClinica I
    ON I.cnpj = F.cnpj
   AND I.ano_referencia = Y.ano_referencia
LEFT JOIN #IndicadorInconsistenciaClinicaMun MUN
    ON MUN.ano_referencia = Y.ano_referencia
   AND MUN.uf = F.uf
   AND MUN.municipio = F.municipio
LEFT JOIN #IndicadorInconsistenciaClinicaUf UF
    ON UF.ano_referencia = Y.ano_referencia
   AND UF.uf = F.uf
LEFT JOIN #IndicadorInconsistenciaClinicaRegiao REG
    ON REG.ano_referencia = Y.ano_referencia
   AND REG.id_regiao_saude = F.id_regiao_saude
INNER JOIN #IndicadorInconsistenciaClinicaBr BR
    ON BR.ano_referencia = Y.ano_referencia;

SET @QtdFinal = @@ROWCOUNT;

CREATE CLUSTERED INDEX IDX_FinalDemo_AnoCNPJ
    ON temp_CGUSC.fp.indicador_inconsistencia_clinica_detalhado(ano_referencia, cnpj);

CREATE NONCLUSTERED INDEX IDX_FinalDemo_CNPJAno
    ON temp_CGUSC.fp.indicador_inconsistencia_clinica_detalhado(cnpj, ano_referencia);

CREATE NONCLUSTERED INDEX IDX_FinalDemo_Risco
    ON temp_CGUSC.fp.indicador_inconsistencia_clinica_detalhado(ano_referencia, percentual_inconsistencia DESC);

CREATE NONCLUSTERED INDEX IDX_FinalDemo_Regiao
    ON temp_CGUSC.fp.indicador_inconsistencia_clinica_detalhado(ano_referencia, id_regiao_saude, percentual_inconsistencia DESC);

PRINT CONCAT('  Tabela consolidada anual criada com ', @QtdFinal, ' registros');


-- ============================================================================
-- PASSO 8: LIMPEZA EXPLICITA DAS TEMP TABLES
-- ============================================================================
DROP TABLE IF EXISTS #CalculoDemografico;
DROP TABLE IF EXISTS #IndicadorInconsistenciaClinica;
DROP TABLE IF EXISTS #IndicadorInconsistenciaClinicaMun;
DROP TABLE IF EXISTS #IndicadorInconsistenciaClinicaUf;
DROP TABLE IF EXISTS #IndicadorInconsistenciaClinicaRegiao;
DROP TABLE IF EXISTS #IndicadorInconsistenciaClinicaBr;
DROP TABLE IF EXISTS #Anos;

PRINT '=======================================================================';
PRINT 'PROCESSO COMPLETO FINALIZADO COM SUCESSO!';
PRINT '';
PRINT 'Tabela criada:';
PRINT '  temp_CGUSC.fp.indicador_inconsistencia_clinica_detalhado';
PRINT '  Granularidade: cnpj + ano_referencia';
PRINT '=======================================================================';
GO


-- ============================================================================
-- VERIFICACAO RAPIDA
-- ============================================================================
SELECT TOP 100 *
FROM temp_CGUSC.fp.indicador_inconsistencia_clinica_detalhado
ORDER BY ano_referencia DESC, ranking_br;
