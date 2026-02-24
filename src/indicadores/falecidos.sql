

USE [temp_CGUSC]
GO

-- ============================================================================
-- DEFINIÇÃO DE VARIÁVEIS DO PERÍODO
-- ============================================================================
DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim DATE = '2024-12-10';

-- ============================================================================
-- PASSO 1: CÁLCULO BASE POR FARMÁCIA (INDICADOR INDIVIDUAL)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.dbo.indicadorFalecidos;

WITH CalculoUnificado AS (
    SELECT 
        A.cnpj,
        
        -- Soma TOTAL de Vendas (Denominador)
        SUM(A.valor_pago) AS valor_total_vendas,
        
        -- Soma APENAS Vendas Irregulares para Falecidos (Numerador)
        SUM(CASE 
            WHEN B.dt_obito IS NOT NULL AND A.data_hora > B.dt_obito THEN A.valor_pago 
            ELSE 0 
        END) AS valor_falecidos,

        -- Contagem de Vendas Irregulares
        COUNT(CASE 
            WHEN B.dt_obito IS NOT NULL AND A.data_hora > B.dt_obito THEN 1 
            ELSE NULL 
        END) AS qtd_vendas_falecidos,

        -- Média de dias após o óbito
        AVG(CASE 
            WHEN B.dt_obito IS NOT NULL AND A.data_hora > B.dt_obito 
            THEN DATEDIFF(DAY, B.dt_obito, A.data_hora) 
            ELSE NULL 
        END) AS media_dias_apos_obito

    FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
    INNER JOIN temp_CGUSC.dbo.medicamentosPatologiaFP C 
        ON C.codigo_barra = A.codigo_barra
    LEFT JOIN temp_CGUSC.dbo.obitos_unificada B 
        ON B.cpf = A.CPF
    WHERE 
        A.data_hora >= @DataInicio 
        AND A.data_hora <= @DataFim
    GROUP BY A.cnpj
)

SELECT 
    cnpj,
    valor_total_vendas,
    valor_falecidos,
    qtd_vendas_falecidos,
    
    -- CÁLCULO DO PERCENTUAL (ESCALA 0 a 100 com 4 casas decimais)
    CAST(
        CASE 
            WHEN valor_total_vendas > 0 THEN 
                (CAST(valor_falecidos AS DECIMAL(18,2)) / CAST(valor_total_vendas AS DECIMAL(18,2))) * 100.0
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS percentual_falecidos,

    ISNULL(media_dias_apos_obito, 0) AS media_dias_irregularidade

INTO temp_CGUSC.dbo.indicadorFalecidos
FROM CalculoUnificado
WHERE valor_total_vendas > 0;

CREATE CLUSTERED INDEX IDX_IndFalecidos_CNPJ ON temp_CGUSC.dbo.indicadorFalecidos(cnpj);


-- ============================================================================
-- PASSO 2: CÁLCULO DAS MÉDIAS POR ESTADO (UF)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.dbo.indicadorFalecidos_UF;

SELECT 
    CAST(F.uf AS VARCHAR(2)) AS uf,
    SUM(I.valor_total_vendas) AS total_vendas_uf,
    SUM(I.valor_falecidos) AS total_falecidos_uf,
    
    -- Média Ponderada do Estado (4 casas decimais)
    CAST(
        CASE 
            WHEN SUM(I.valor_total_vendas) > 0 THEN 
                (CAST(SUM(I.valor_falecidos) AS DECIMAL(18,2)) / CAST(SUM(I.valor_total_vendas) AS DECIMAL(18,2))) * 100.0
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS percentual_falecidos_uf,

    AVG(I.media_dias_irregularidade) AS media_dias_uf

INTO temp_CGUSC.dbo.indicadorFalecidos_UF
FROM temp_CGUSC.dbo.indicadorFalecidos I
INNER JOIN temp_CGUSC.dbo.dadosFarmaciasFP F 
    ON F.cnpj = I.cnpj
GROUP BY CAST(F.uf AS VARCHAR(2));

CREATE CLUSTERED INDEX IDX_IndFalecidosUF_UF ON temp_CGUSC.dbo.indicadorFalecidos_UF(uf);


-- ============================================================================
-- PASSO 3: CÁLCULO DA MÉDIA NACIONAL (BRASIL)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.dbo.indicadorFalecidos_BR;

SELECT 
    'BR' AS pais,
    SUM(valor_total_vendas) AS total_vendas_br,
    SUM(valor_falecidos) AS total_falecidos_br,
    
    -- Média Ponderada Nacional (4 casas decimais)
    CAST(
        CASE 
            WHEN SUM(valor_total_vendas) > 0 THEN 
                (CAST(SUM(valor_falecidos) AS DECIMAL(18,2)) / CAST(SUM(valor_total_vendas) AS DECIMAL(18,2))) * 100.0
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS percentual_falecidos_br,

    AVG(media_dias_irregularidade) AS media_dias_br

INTO temp_CGUSC.dbo.indicadorFalecidos_BR
FROM temp_CGUSC.dbo.indicadorFalecidos;


-- ============================================================================
-- PASSO 4: TABELA CONSOLIDADA FINAL
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.dbo.indicadorFalecidos_Completo;

SELECT 
    I.cnpj,
    F.razaoSocial,
    F.municipio,
    CAST(F.uf AS VARCHAR(2)) AS uf,
    
    I.valor_total_vendas,
    I.valor_falecidos,
    I.qtd_vendas_falecidos,
    I.media_dias_irregularidade,
    
    -- Percentuais (já vêm com 4 casas dos passos anteriores)
    I.percentual_falecidos,
    ISNULL(UF.percentual_falecidos_uf, 0) AS media_estado,
    BR.percentual_falecidos_br AS media_pais,
    
    -- Risco Relativo (Forçamos 4 casas decimais aqui também para padronizar)
    CAST(
        CASE 
            WHEN UF.percentual_falecidos_uf > 0 THEN 
                I.percentual_falecidos / UF.percentual_falecidos_uf
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS risco_relativo_uf,

    CAST(
        CASE 
            WHEN BR.percentual_falecidos_br > 0 THEN 
                I.percentual_falecidos / BR.percentual_falecidos_br
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS risco_relativo_br

INTO temp_CGUSC.dbo.indicadorFalecidos_Completo
FROM temp_CGUSC.dbo.indicadorFalecidos I
INNER JOIN temp_CGUSC.dbo.dadosFarmaciasFP F 
    ON F.cnpj = I.cnpj
LEFT JOIN temp_CGUSC.dbo.indicadorFalecidos_UF UF 
    ON CAST(F.uf AS VARCHAR(2)) = UF.uf
CROSS JOIN temp_CGUSC.dbo.indicadorFalecidos_BR BR;

-- Índices Finais
CREATE CLUSTERED INDEX IDX_Final_CNPJ ON temp_CGUSC.dbo.indicadorFalecidos_Completo(cnpj);
CREATE NONCLUSTERED INDEX IDX_Final_Risco ON temp_CGUSC.dbo.indicadorFalecidos_Completo(risco_relativo_uf DESC);
GO

-- Verificação final
SELECT TOP 100 * FROM temp_CGUSC.dbo.indicadorFalecidos_Completo ORDER BY risco_relativo_uf DESC;