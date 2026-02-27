USE [temp_CGUSC]
GO

-- ============================================================================
-- DEFINIÇÃO DE VARIÁVEIS DO PERÍODO
-- ============================================================================
DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim DATE = '2024-12-10';

-- ============================================================================
-- PASSO 1: VENDAS DIÁRIAS POR FARMÁCIA (APENAS ITENS AUDITADOS)
-- ============================================================================
DROP TABLE IF EXISTS #VendasDiarias;

SELECT 
    A.cnpj,
    FORMAT(A.data_hora, 'yyyy-MM') AS ano_mes,
    CAST(A.data_hora AS DATE) AS data_venda,
    SUM(A.valor_pago) AS valor_dia
INTO #VendasDiarias
FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
INNER JOIN temp_CGUSC.fp.medicamentos_patologia C ON C.codigo_barra = A.codigo_barra
WHERE A.data_hora >= @DataInicio AND A.data_hora <= @DataFim
GROUP BY A.cnpj, FORMAT(A.data_hora, 'yyyy-MM'), CAST(A.data_hora AS DATE);

CREATE CLUSTERED INDEX IDX_Dias_CNPJ ON #VendasDiarias(cnpj, ano_mes);

-- ============================================================================
-- PASSO 2: RANQUEAMENTO DOS DIAS DENTRO DE CADA MÊS
-- ============================================================================
DROP TABLE IF EXISTS #RankingDias;

SELECT 
    cnpj,
    ano_mes,
    valor_dia,
    SUM(valor_dia) OVER (PARTITION BY cnpj, ano_mes) AS total_mes,
    ROW_NUMBER() OVER (PARTITION BY cnpj, ano_mes ORDER BY valor_dia DESC) AS ranking_dia
INTO #RankingDias
FROM #VendasDiarias;

-- ============================================================================
-- PASSO 3: CÁLCULO MENSAL DA CONCENTRAÇÃO (TOP 3 DIAS)
-- ============================================================================
DROP TABLE IF EXISTS #ConcentracaoMensal;

SELECT 
    cnpj,
    ano_mes,
    CAST(SUM(CASE WHEN ranking_dia <= 3 THEN valor_dia ELSE 0 END) AS DECIMAL(18,2)) / 
    CAST(MAX(total_mes) AS DECIMAL(18,2)) * 100.0 AS pct_concentracao_top3_dias
INTO #ConcentracaoMensal
FROM #RankingDias
GROUP BY cnpj, ano_mes
HAVING MAX(total_mes) > 0;

-- ============================================================================
-- PASSO 4: CÁLCULO BASE POR FARMÁCIA (MÉDIA E MEDIANA DO PERÍODO)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_concentracao_pico;

SELECT DISTINCT
    cnpj,
    COUNT(ano_mes) OVER (PARTITION BY cnpj) AS meses_analisados,
    -- MÉDIA (Impacto dos picos)
    CAST(AVG(pct_concentracao_top3_dias) OVER (PARTITION BY cnpj) AS DECIMAL(18,4)) AS media_concentracao,
    -- MEDIANA (Comportamento típico)
    CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY pct_concentracao_top3_dias) OVER (PARTITION BY cnpj) AS DECIMAL(18,4)) AS mediana_concentracao
INTO temp_CGUSC.fp.indicador_concentracao_pico
FROM #ConcentracaoMensal;

CREATE CLUSTERED INDEX IDX_IndPico_CNPJ ON temp_CGUSC.fp.indicador_concentracao_pico(cnpj);

-- Limpeza
DROP TABLE #VendasDiarias;
DROP TABLE #RankingDias;
DROP TABLE #ConcentracaoMensal;

-- ============================================================================
-- PASSO 5: CÁLCULO DAS MÉTRICAS POR MUNICÍPIO (MÉDIA + MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_concentracao_pico_mun;

SELECT DISTINCT
    CAST(F.uf AS VARCHAR(2)) AS uf,
    CAST(F.municipio AS VARCHAR(255)) AS municipio,
    -- Mediana das Medianas (Régua Justa)
    CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.mediana_concentracao) OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255))) AS DECIMAL(18,4)) AS mediana_municipio,
    -- Média das Médias (Impacto Global)
    CAST(AVG(I.media_concentracao) OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255))) AS DECIMAL(18,4)) AS media_municipio
INTO temp_CGUSC.fp.indicador_concentracao_pico_mun
FROM temp_CGUSC.fp.indicador_concentracao_pico I
INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj;

CREATE CLUSTERED INDEX IDX_IndPicoMun_mun ON temp_CGUSC.fp.indicador_concentracao_pico_mun(uf, municipio);


-- ============================================================================
-- PASSO 6: CÁLCULO DAS MÉTRICAS POR ESTADO (UF)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_concentracao_pico_uf;

SELECT DISTINCT
    CAST(F.uf AS VARCHAR(2)) AS uf,
    CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.mediana_concentracao) OVER (PARTITION BY CAST(F.uf AS VARCHAR(2))) AS DECIMAL(18,4)) AS mediana_estado,
    CAST(AVG(I.media_concentracao) OVER (PARTITION BY CAST(F.uf AS VARCHAR(2))) AS DECIMAL(18,4)) AS media_estado
INTO temp_CGUSC.fp.indicador_concentracao_pico_uf
FROM temp_CGUSC.fp.indicador_concentracao_pico I
INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj;


-- ============================================================================
-- PASSO 7: CÁLCULO DA MÉTRICA NACIONAL (BRASIL)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_concentracao_pico_br;

SELECT DISTINCT
    'BR' AS pais,
    CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY mediana_concentracao) OVER () AS DECIMAL(18,4)) AS mediana_pais,
    CAST(AVG(media_concentracao) OVER () AS DECIMAL(18,4)) AS media_pais
INTO temp_CGUSC.fp.indicador_concentracao_pico_br
FROM temp_CGUSC.fp.indicador_concentracao_pico;


-- ============================================================================
-- PASSO 8: TABELA CONSOLIDADA FINAL (COM DUPLO RISCO)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_concentracao_pico_detalhado;

SELECT 
    I.cnpj,
    F.razaoSocial,
    F.municipio,
    CAST(F.uf AS VARCHAR(2)) AS uf,
    I.meses_analisados,
    I.mediana_concentracao,
    I.media_concentracao,
    
    -- Riscos Municipais
    ISNULL(MUN.mediana_municipio, 0) AS municipio_mediana,
    ISNULL(MUN.media_municipio, 0) AS municipio_media,
    CAST((I.mediana_concentracao + 0.01) / (ISNULL(MUN.mediana_municipio, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_mediana,
    CAST((I.media_concentracao + 0.01) / (ISNULL(MUN.media_municipio, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_media,

    -- Riscos Estaduais
    ISNULL(UF.mediana_estado, 0) AS estado_mediana,
    ISNULL(UF.media_estado, 0) AS estado_media,
    CAST((I.mediana_concentracao + 0.01) / (ISNULL(UF.mediana_estado, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_mediana,
    CAST((I.media_concentracao + 0.01) / (ISNULL(UF.media_estado, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_media,

    -- Riscos Nacionais
    BR.mediana_pais AS pais_mediana,
    BR.media_pais AS pais_media,
    CAST((I.mediana_concentracao + 0.01) / (BR.mediana_pais + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_mediana,
    CAST((I.media_concentracao + 0.01) / (BR.media_pais + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_media

INTO temp_CGUSC.fp.indicador_concentracao_pico_detalhado
FROM temp_CGUSC.fp.indicador_concentracao_pico I
INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj
LEFT JOIN temp_CGUSC.fp.indicador_concentracao_pico_mun MUN ON CAST(F.uf AS VARCHAR(2)) = MUN.uf AND CAST(F.municipio AS VARCHAR(255)) = MUN.municipio
LEFT JOIN temp_CGUSC.fp.indicador_concentracao_pico_uf UF ON CAST(F.uf AS VARCHAR(2)) = UF.uf
CROSS JOIN temp_CGUSC.fp.indicador_concentracao_pico_br BR;

CREATE CLUSTERED INDEX IDX_FinalPico_CNPJ ON temp_CGUSC.fp.indicador_concentracao_pico_detalhado(cnpj);
GO

SELECT TOP 100 * FROM temp_CGUSC.fp.indicador_concentracao_pico_detalhado ORDER BY risco_relativo_mun_mediana DESC;
