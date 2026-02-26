USE [temp_CGUSC]
GO

-- ============================================================================
-- DEFINIÇÃO DE VARIÁVEIS DO PERÍODO
-- ============================================================================
DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim DATE = '2024-12-10';

-- ============================================================================
-- PASSO 1: CÁLCULO BASE POR FARMÁCIA (INDICADOR TETO MÁXIMO)
-- Tabela de Saída: temp_CGUSC.fp.indicadorTeto
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicadorTeto;

WITH VendasComTeto AS (
    SELECT 
        A.cnpj,
        A.num_autorizacao,
        
        -- Verifica se QUALQUER ITEM da venda atingiu o teto
        MAX(CASE 
            WHEN A.qnt_autorizada >= P.QUANTIDADE_MAXIMA THEN 1 
            ELSE 0 
        END) AS flag_venda_atingiu_teto

    FROM db_farmaciapopular.fp.relatorio_movimentacao_2015_2024 A
    INNER JOIN temp_CGUSC.fp.medicamentosPatologiaFP C 
        ON C.codigo_barra = A.codigo_barra
    INNER JOIN temp_CGUSC.fp.posologia_tempo_bloqueio P 
        ON P.PRINCIPIO_ATIVO = C.principio_ativo

    WHERE 
        A.data_hora >= @DataInicio 
        AND A.data_hora <= @DataFim
        AND P.QUANTIDADE_MAXIMA > 0

    GROUP BY A.cnpj, A.num_autorizacao
),
AgregadoPorFarmacia AS (
    SELECT 
        cnpj,
        COUNT(*) AS total_vendas_monitoradas,
        SUM(flag_venda_atingiu_teto) AS qtd_vendas_teto_maximo
    FROM VendasComTeto
    GROUP BY cnpj
)

SELECT 
    cnpj,
    total_vendas_monitoradas,
    qtd_vendas_teto_maximo,
    
    CAST(
        CASE 
            WHEN total_vendas_monitoradas > 0 THEN 
                (CAST(qtd_vendas_teto_maximo AS DECIMAL(18,2)) / CAST(total_vendas_monitoradas AS DECIMAL(18,2))) * 100.0
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS percentual_teto

INTO temp_CGUSC.fp.indicadorTeto
FROM AgregadoPorFarmacia
WHERE total_vendas_monitoradas > 0;

CREATE CLUSTERED INDEX IDX_IndTeto_CNPJ ON temp_CGUSC.fp.indicadorTeto(cnpj);


-- ============================================================================
-- PASSO 2: CÁLCULO DAS MÉDIAS POR ESTADO (UF)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicadorTeto_UF;

SELECT 
    CAST(F.uf AS VARCHAR(2)) AS uf,
    
    SUM(I.total_vendas_monitoradas) AS total_vendas_uf,
    SUM(I.qtd_vendas_teto_maximo) AS total_teto_uf,
    
    -- Média do Estado
    CAST(
        CASE 
            WHEN SUM(I.total_vendas_monitoradas) > 0 THEN 
                (CAST(SUM(I.qtd_vendas_teto_maximo) AS DECIMAL(18,2)) / CAST(SUM(I.total_vendas_monitoradas) AS DECIMAL(18,2))) * 100.0
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS percentual_teto_uf

INTO temp_CGUSC.fp.indicadorTeto_UF
FROM temp_CGUSC.fp.indicadorTeto I
INNER JOIN temp_CGUSC.fp.dadosFarmaciasFP F 
    ON F.cnpj = I.cnpj
GROUP BY CAST(F.uf AS VARCHAR(2));

CREATE CLUSTERED INDEX IDX_IndTetoUF_UF ON temp_CGUSC.fp.indicadorTeto_UF(uf);


-- ============================================================================
-- PASSO 3: CÁLCULO DA MÉDIA NACIONAL (BRASIL)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicadorTeto_BR;

SELECT 
    'BR' AS pais,
    SUM(total_vendas_monitoradas) AS total_vendas_br,
    SUM(qtd_vendas_teto_maximo) AS total_teto_br,
    
    -- Média Nacional
    CAST(
        CASE 
            WHEN SUM(total_vendas_monitoradas) > 0 THEN 
                (CAST(SUM(qtd_vendas_teto_maximo) AS DECIMAL(18,2)) / CAST(SUM(total_vendas_monitoradas) AS DECIMAL(18,2))) * 100.0
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS percentual_teto_br

INTO temp_CGUSC.fp.indicadorTeto_BR
FROM temp_CGUSC.fp.indicadorTeto;


-- ============================================================================
-- PASSO 4: TABELA CONSOLIDADA FINAL (COMPARATIVO DE RISCO)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicadorTeto_Completo;

SELECT 
    I.cnpj,
    F.razaoSocial,
    F.municipio,
    CAST(F.uf AS VARCHAR(2)) AS uf,
    
    I.total_vendas_monitoradas,
    I.qtd_vendas_teto_maximo,
    I.percentual_teto,
    
    -- Comparativos (Médias)
    ISNULL(UF.percentual_teto_uf, 0) AS media_estado,
    BR.percentual_teto_br AS media_pais,
    
    -- RISCO RELATIVO (4 Casas Decimais)
    CAST(
        CASE 
            WHEN UF.percentual_teto_uf > 0 THEN 
                I.percentual_teto / UF.percentual_teto_uf
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS risco_relativo_uf,

    CAST(
        CASE 
            WHEN BR.percentual_teto_br > 0 THEN 
                I.percentual_teto / BR.percentual_teto_br
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS risco_relativo_br

INTO temp_CGUSC.fp.indicadorTeto_Completo
FROM temp_CGUSC.fp.indicadorTeto I
INNER JOIN temp_CGUSC.fp.dadosFarmaciasFP F 
    ON F.cnpj = I.cnpj
LEFT JOIN temp_CGUSC.fp.indicadorTeto_UF UF 
    ON CAST(F.uf AS VARCHAR(2)) = UF.uf
CROSS JOIN temp_CGUSC.fp.indicadorTeto_BR BR;

-- Índices Finais
CREATE CLUSTERED INDEX IDX_FinalTeto_CNPJ ON temp_CGUSC.fp.indicadorTeto_Completo(cnpj);
CREATE NONCLUSTERED INDEX IDX_FinalTeto_Risco ON temp_CGUSC.fp.indicadorTeto_Completo(risco_relativo_uf DESC);
GO

-- Verificação rápida
SELECT TOP 100 * FROM temp_CGUSC.fp.indicadorTeto_Completo ORDER BY risco_relativo_uf DESC;
