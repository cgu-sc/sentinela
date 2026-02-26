USE [temp_CGUSC]
GO

-- ============================================================================
-- DEFINIÇÃO DE VARIÁVEIS
-- ============================================================================
DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim DATE = '2024-12-10';

-- ============================================================================
-- PASSO 1: VENDAS DIÁRIAS POR FARMÁCIA
-- ============================================================================
DROP TABLE IF EXISTS #VendasDiarias;

SELECT 
    cnpj,
    FORMAT(data_hora, 'yyyy-MM') AS ano_mes,
    CAST(data_hora AS DATE) AS data_venda,
    SUM(valor_pago) AS valor_dia
INTO #VendasDiarias
FROM db_farmaciapopular.fp.relatorio_movimentacao_2015_2024
WHERE data_hora >= @DataInicio AND data_hora <= @DataFim
GROUP BY cnpj, FORMAT(data_hora, 'yyyy-MM'), CAST(data_hora AS DATE);

CREATE CLUSTERED INDEX IDX_Dias_CNPJ ON #VendasDiarias(cnpj, ano_mes);

-- ============================================================================
-- PASSO 2: RANQUEAMENTO DOS DIAS DENTRO DE CADA MÊS
-- Identifica quais foram o 1º, 2º e 3º dias mais rentáveis de cada mês
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
    -- Soma o valor dos 3 maiores dias e divide pelo total do mês
    CAST(SUM(CASE WHEN ranking_dia <= 3 THEN valor_dia ELSE 0 END) AS DECIMAL(18,2)) / 
    CAST(MAX(total_mes) AS DECIMAL(18,2)) * 100.0 AS pct_concentracao_top3_dias
INTO #ConcentracaoMensal
FROM #RankingDias
GROUP BY cnpj, ano_mes
HAVING MAX(total_mes) > 0; -- Evita divisão por zero

-- ============================================================================
-- PASSO 4: CÁLCULO BASE POR FARMÁCIA (MÉDIA DO PERÍODO)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_concentracao_pico;

SELECT 
    cnpj,
    COUNT(DISTINCT ano_mes) AS meses_analisados,
    -- Média das concentrações mensais
    CAST(AVG(pct_concentracao_top3_dias) AS DECIMAL(18,4)) AS percentual_concentracao_pico
INTO temp_CGUSC.fp.indicador_concentracao_pico
FROM #ConcentracaoMensal
GROUP BY cnpj;

CREATE CLUSTERED INDEX IDX_IndPico_CNPJ ON temp_CGUSC.fp.indicador_concentracao_pico(cnpj);

-- Limpeza
DROP TABLE #VendasDiarias;
DROP TABLE #RankingDias;
DROP TABLE #ConcentracaoMensal;

-- ============================================================================
-- PASSO 5: CÁLCULO DAS MÉDIAS POR ESTADO (UF)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_concentracao_pico_uf;

SELECT 
    CAST(F.uf AS VARCHAR(2)) AS uf,
    CAST(AVG(I.percentual_concentracao_pico) AS DECIMAL(18,4)) AS percentual_concentracao_pico_uf
INTO temp_CGUSC.fp.indicador_concentracao_pico_uf
FROM temp_CGUSC.fp.indicador_concentracao_pico I
INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj
GROUP BY CAST(F.uf AS VARCHAR(2));

CREATE CLUSTERED INDEX IDX_IndPicoUF_uf ON temp_CGUSC.fp.indicador_concentracao_pico_uf(uf);

-- ============================================================================
-- PASSO 6: CÁLCULO DA MÉDIA NACIONAL
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_concentracao_pico_br;

SELECT 
    'BR' AS pais,
    CAST(AVG(percentual_concentracao_pico) AS DECIMAL(18,4)) AS percentual_concentracao_pico_br
INTO temp_CGUSC.fp.indicador_concentracao_pico_br
FROM temp_CGUSC.fp.indicador_concentracao_pico;

-- ============================================================================
-- PASSO 7: TABELA CONSOLIDADA FINAL
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_concentracao_pico_detalhado;

SELECT 
    I.cnpj,
    F.razaoSocial,
    F.municipio,
    CAST(F.uf AS VARCHAR(2)) AS uf,
    
    I.percentual_concentracao_pico,
    
    ISNULL(UF.percentual_concentracao_pico_uf, 0) AS media_estado,
    BR.percentual_concentracao_pico_br AS media_pais,
    
    -- RISCO RELATIVO
    CAST(CASE 
        WHEN UF.percentual_concentracao_pico_uf > 0 THEN I.percentual_concentracao_pico / UF.percentual_concentracao_pico_uf
        ELSE 0 
    END AS DECIMAL(18,4)) AS risco_relativo_uf,

    CAST(CASE 
        WHEN BR.percentual_concentracao_pico_br > 0 THEN I.percentual_concentracao_pico / BR.percentual_concentracao_pico_br
        ELSE 0 
    END AS DECIMAL(18,4)) AS risco_relativo_br

INTO temp_CGUSC.fp.indicador_concentracao_pico_detalhado
FROM temp_CGUSC.fp.indicador_concentracao_pico I
INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj
LEFT JOIN temp_CGUSC.fp.indicador_concentracao_pico_uf UF ON CAST(F.uf AS VARCHAR(2)) = UF.uf
CROSS JOIN temp_CGUSC.fp.indicador_concentracao_pico_br BR;

CREATE CLUSTERED INDEX IDX_FinalPico_CNPJ ON temp_CGUSC.fp.indicador_concentracao_pico_detalhado(cnpj);
GO

