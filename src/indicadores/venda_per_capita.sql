USE [temp_CGUSC]
GO

-- ============================================================================
-- PASSO 1: PRÉ-CÁLCULO - TOTAL DE VENDAS E MESES DE ATUAÇÃO
-- ============================================================================
DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim DATE = '2024-12-10';

DROP TABLE IF EXISTS #VendasPorFarmacia;

SELECT 
    A.cnpj,
    SUM(A.valor_pago) AS valor_total_periodo,
    -- NOVO: Conta meses reais de operação para normalização
    COUNT(DISTINCT FORMAT(A.data_hora, 'yyyyMM')) AS qtd_meses_ativos
INTO #VendasPorFarmacia
FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
INNER JOIN temp_CGUSC.fp.medicamentos_patologia C 
    ON C.codigo_barra = A.codigo_barra
WHERE 
    A.data_hora >= @DataInicio 
    AND A.data_hora <= @DataFim
GROUP BY A.cnpj;

CREATE CLUSTERED INDEX IDX_TempVendas_CNPJ ON #VendasPorFarmacia(cnpj);
GO 
-- O comando GO acima é essencial para salvar a tabela temporária antes do próximo passo


-- ============================================================================
-- PASSO 2: CÁLCULO BASE POR FARMÁCIA (VENDA PER CAPITA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_venda_per_capita;

SELECT 
    F.cnpj,
    V.valor_total_periodo,
    V.qtd_meses_ativos, 
    IBGE.nu_populacao AS populacao_municipio,
    
    -- MÉTRICA 1 (LEGADO): ACUMULADA
    CAST(
        CASE 
            WHEN IBGE.nu_populacao > 0 THEN 
                V.valor_total_periodo / IBGE.nu_populacao
            ELSE 0 
        END 
    AS DECIMAL(18,2)) AS valor_per_capita,

    -- MÉTRICA 2 (NOVA): MENSAL NORMALIZADA
    -- Lógica: (Total Vendas / Meses Ativos) / População
    CAST(
        CASE 
            WHEN IBGE.nu_populacao > 0 AND V.qtd_meses_ativos > 0 THEN 
                (V.valor_total_periodo / V.qtd_meses_ativos) / IBGE.nu_populacao
            ELSE 0 
        END 
    AS DECIMAL(18,2)) AS valor_per_capita_mensal

INTO temp_CGUSC.fp.indicador_venda_per_capita
FROM #VendasPorFarmacia V
INNER JOIN temp_CGUSC.fp.dados_farmacia F 
    ON F.cnpj = V.cnpj
INNER JOIN temp_CGUSC.sus.tb_ibge IBGE 
    ON CAST(F.codibge AS VARCHAR(7)) = IBGE.id_ibge7;

CREATE CLUSTERED INDEX IDX_IndCapita_CNPJ ON temp_CGUSC.fp.indicador_venda_per_capita(cnpj);
DROP TABLE #VendasPorFarmacia;
GO
-- O comando GO aqui garante que a coluna 'valor_per_capita_mensal' exista para o próximo passo


-- ============================================================================
-- PASSO 3: CÁLCULO DAS MÉDIAS POR ESTADO (UF)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_venda_per_capita_uf;

SELECT 
    CAST(F.uf AS VARCHAR(2)) AS uf,
    
    SUM(I.valor_total_periodo) AS total_vendas_uf,
    SUM(I.populacao_municipio) AS soma_populacao_base_calculo,
    
    -- Média Acumulada
    CAST(
        AVG(I.valor_per_capita) 
    AS DECIMAL(18,2)) AS valor_per_capita_uf,

    -- Média Mensal (Benchmark Justo)
    CAST(
        AVG(I.valor_per_capita_mensal) 
    AS DECIMAL(18,2)) AS valor_per_capita_mensal_uf

INTO temp_CGUSC.fp.indicador_venda_per_capita_uf
FROM temp_CGUSC.fp.indicador_venda_per_capita I
INNER JOIN temp_CGUSC.fp.dados_farmacia F 
    ON F.cnpj = I.cnpj
GROUP BY CAST(F.uf AS VARCHAR(2));

CREATE CLUSTERED INDEX IDX_IndCapitaUF_uf ON temp_CGUSC.fp.indicador_venda_per_capita_uf(uf);
GO


-- ============================================================================
-- PASSO 4: CÁLCULO DA MÉDIA NACIONAL
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_venda_per_capita_br;

SELECT 
    'BR' AS pais,
    
    -- Média Nacional Acumulada
    CAST(
        AVG(valor_per_capita)
    AS DECIMAL(18,2)) AS valor_per_capita_br,

    -- Média Nacional Mensal
    CAST(
        AVG(valor_per_capita_mensal)
    AS DECIMAL(18,2)) AS valor_per_capita_mensal_br

INTO temp_CGUSC.fp.indicador_venda_per_capita_br
FROM temp_CGUSC.fp.indicador_venda_per_capita;
GO


-- ============================================================================
-- PASSO 5: TABELA CONSOLIDADA FINAL
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_venda_per_capita_detalhado;

SELECT 
    I.cnpj,
    F.razaoSocial,
    F.municipio,
    CAST(F.uf AS VARCHAR(2)) AS uf,
    
    I.valor_total_periodo,
    I.populacao_municipio,
    I.qtd_meses_ativos, 
    
    -- Indicador Original
    I.valor_per_capita,

    -- Indicador Novo (Normalizado)
    I.valor_per_capita_mensal,
    
    -- Comparativos (Benchmarks Mensais)
    ISNULL(UF.valor_per_capita_mensal_uf, 0) AS media_mensal_estado,
    BR.valor_per_capita_mensal_br AS media_mensal_pais,
    
    -- RISCO RELATIVO (Baseado na Média Mensal - Matematicamente Justo)
    CAST(
        CASE 
            WHEN UF.valor_per_capita_mensal_uf > 0 THEN 
                I.valor_per_capita_mensal / UF.valor_per_capita_mensal_uf
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS risco_relativo_uf,

    CAST(
        CASE 
            WHEN BR.valor_per_capita_mensal_br > 0 THEN 
                I.valor_per_capita_mensal / BR.valor_per_capita_mensal_br
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS risco_relativo_br

INTO temp_CGUSC.fp.indicador_venda_per_capita_detalhado
FROM temp_CGUSC.fp.indicador_venda_per_capita I
INNER JOIN temp_CGUSC.fp.dados_farmacia F 
    ON F.cnpj = I.cnpj
LEFT JOIN temp_CGUSC.fp.indicador_venda_per_capita_uf UF 
    ON CAST(F.uf AS VARCHAR(2)) = UF.uf
CROSS JOIN temp_CGUSC.fp.indicador_venda_per_capita_br BR;

CREATE CLUSTERED INDEX IDX_FinalCapita_CNPJ ON temp_CGUSC.fp.indicador_venda_per_capita_detalhado(cnpj);
CREATE NONCLUSTERED INDEX IDX_FinalCapita_Risco ON temp_CGUSC.fp.indicador_venda_per_capita_detalhado(risco_relativo_uf DESC);
GO

-- Verificação rápida
SELECT TOP 100 * FROM temp_CGUSC.fp.indicador_venda_per_capita_detalhado ORDER BY risco_relativo_uf DESC;


