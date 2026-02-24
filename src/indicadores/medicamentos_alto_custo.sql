USE [temp_CGUSC]
GO

-- ============================================================================
-- DEFINIO DE VARIVEIS DO PERODO (PADRO PROJETO)
-- ============================================================================
DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim DATE = '2024-12-10';

-- ============================================================================
-- PASSO 0: CALCULAR O PREO DE CORTE (90 PERCENTIL GLOBAL)
-- Calcula uma nica vez o valor que define o que  "Alto Custo"
-- ============================================================================
DROP TABLE IF EXISTS #LimiteAltoCusto;

SELECT DISTINCT
    PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY valor_pago) OVER () AS valor_limite
INTO #LimiteAltoCusto
FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024
WHERE data_hora >= @DataInicio AND data_hora <= @DataFim;

-- Cria ndice para otimizar o join (mesmo sendo tabela de 1 linha, boa prtica)
CREATE CLUSTERED INDEX IDX_Limite ON #LimiteAltoCusto(valor_limite);


-- ============================================================================
-- PASSO 1: CLCULO BASE POR FARMCIA
-- Tabela de Sada: temp_CGUSC.dbo.indicadorAltoCusto
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.dbo.indicadorAltoCusto;

SELECT 
    A.cnpj,
    
    -- Total Vendido pela Farmcia
    SUM(A.valor_pago) AS valor_total_vendido,
    
    -- Total Vendido APENAS itens de Alto Custo
    SUM(CASE 
        WHEN A.valor_pago >= L.valor_limite THEN A.valor_pago 
        ELSE 0 
    END) AS valor_vendas_alto_custo,

    -- Percentual (Indicador Principal)
    CAST(
        CASE 
            WHEN SUM(A.valor_pago) > 0 THEN 
                (SUM(CASE WHEN A.valor_pago >= L.valor_limite THEN A.valor_pago ELSE 0 END) / SUM(A.valor_pago)) * 100.0
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS percentual_alto_custo

INTO temp_CGUSC.dbo.indicadorAltoCusto
FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
CROSS JOIN #LimiteAltoCusto L
WHERE 
    A.data_hora >= @DataInicio 
    AND A.data_hora <= @DataFim
GROUP BY A.cnpj
HAVING SUM(A.valor_pago) > 5000; -- Filtro de corte mnimo conforme solicitado

CREATE CLUSTERED INDEX IDX_IndAltoCusto_CNPJ ON temp_CGUSC.dbo.indicadorAltoCusto(cnpj);


-- ============================================================================
-- PASSO 2: CLCULO DAS MDIAS POR ESTADO (UF)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.dbo.indicadorAltoCusto_UF;

SELECT 
    CAST(F.uf AS VARCHAR(2)) AS uf,
    
    SUM(I.valor_total_vendido) AS total_vendido_uf,
    SUM(I.valor_vendas_alto_custo) AS total_alto_custo_uf,
    
    -- Mdia Ponderada do Estado
    CAST(
        CASE 
            WHEN SUM(I.valor_total_vendido) > 0 THEN 
                (SUM(I.valor_vendas_alto_custo) / SUM(I.valor_total_vendido)) * 100.0
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS percentual_alto_custo_uf

INTO temp_CGUSC.dbo.indicadorAltoCusto_UF
FROM temp_CGUSC.dbo.indicadorAltoCusto I
INNER JOIN temp_CGUSC.dbo.dadosFarmaciasFP F 
    ON F.cnpj = I.cnpj
GROUP BY CAST(F.uf AS VARCHAR(2));

CREATE CLUSTERED INDEX IDX_IndAltoCustoUF_UF ON temp_CGUSC.dbo.indicadorAltoCusto_UF(uf);


-- ============================================================================
-- PASSO 3: CLCULO DA MDIA NACIONAL (BRASIL)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.dbo.indicadorAltoCusto_BR;

SELECT 
    'BR' AS pais,
    SUM(valor_total_vendido) AS total_vendido_br,
    SUM(valor_vendas_alto_custo) AS total_alto_custo_br,
    
    -- Mdia Ponderada Nacional
    CAST(
        CASE 
            WHEN SUM(valor_total_vendido) > 0 THEN 
                (SUM(valor_vendas_alto_custo) / SUM(valor_total_vendido)) * 100.0
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS percentual_alto_custo_br

INTO temp_CGUSC.dbo.indicadorAltoCusto_BR
FROM temp_CGUSC.dbo.indicadorAltoCusto;


-- ============================================================================
-- PASSO 4: TABELA CONSOLIDADA FINAL (COMPARATIVO DE RISCO)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.dbo.indicadorAltoCusto_Completo;

SELECT 
    I.cnpj,
    F.razaoSocial,
    F.municipio,
    CAST(F.uf AS VARCHAR(2)) AS uf,
    
    I.valor_total_vendido,
    I.valor_vendas_alto_custo,
    I.percentual_alto_custo,
    
    -- Comparativos (Mdias)
    ISNULL(UF.percentual_alto_custo_uf, 0) AS media_estado,
    BR.percentual_alto_custo_br AS media_pais,
    
    -- RISCO RELATIVO (4 Casas Decimais)
    -- Quantas vezes a concentrao de alto custo  maior que a mdia do estado?
    CAST(
        CASE 
            WHEN UF.percentual_alto_custo_uf > 0 THEN 
                I.percentual_alto_custo / UF.percentual_alto_custo_uf
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS risco_relativo_uf,

    CAST(
        CASE 
            WHEN BR.percentual_alto_custo_br > 0 THEN 
                I.percentual_alto_custo / BR.percentual_alto_custo_br
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS risco_relativo_br

INTO temp_CGUSC.dbo.indicadorAltoCusto_Completo
FROM temp_CGUSC.dbo.indicadorAltoCusto I
INNER JOIN temp_CGUSC.dbo.dadosFarmaciasFP F 
    ON F.cnpj = I.cnpj
LEFT JOIN temp_CGUSC.dbo.indicadorAltoCusto_UF UF 
    ON CAST(F.uf AS VARCHAR(2)) = UF.uf
CROSS JOIN temp_CGUSC.dbo.indicadorAltoCusto_BR BR;

-- ndices Finais
CREATE CLUSTERED INDEX IDX_FinalAltoCusto_CNPJ ON temp_CGUSC.dbo.indicadorAltoCusto_Completo(cnpj);
CREATE NONCLUSTERED INDEX IDX_FinalAltoCusto_Risco ON temp_CGUSC.dbo.indicadorAltoCusto_Completo(risco_relativo_uf DESC);
GO

-- Verificao rpida
SELECT TOP 100 * FROM temp_CGUSC.dbo.indicadorAltoCusto_Completo ORDER BY risco_relativo_uf DESC;