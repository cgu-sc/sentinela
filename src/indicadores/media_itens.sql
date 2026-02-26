USE [temp_CGUSC]
GO

-- ============================================================================
-- DEFINIÇÃO DE VARIÁVEIS
-- ============================================================================
DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim DATE = '2024-12-10';

-- ============================================================================
-- PASSO 1: PRÉ-CÁLCULO - CONTAGEM DE ITENS POR AUTORIZAÇÃO
-- Agrupa os medicamentos vendidos dentro de cada autorização única.
-- ============================================================================
DROP TABLE IF EXISTS #ContagemItensAutorizacao;

SELECT 
    A.cnpj,
    A.num_autorizacao,
    COUNT(*) AS qtd_itens
INTO #ContagemItensAutorizacao
FROM db_farmaciapopular.fp.relatorio_movimentacao_2015_2024 A
INNER JOIN temp_CGUSC.fp.medicamentosPatologiaFP C 
    ON C.codigo_barra = A.codigo_barra
WHERE 
    A.data_hora >= @DataInicio 
    AND A.data_hora <= @DataFim
GROUP BY A.cnpj, A.num_autorizacao;

CREATE CLUSTERED INDEX IDX_TempCont_CNPJ ON #ContagemItensAutorizacao(cnpj);


-- ============================================================================
-- PASSO 2: CÁLCULO BASE POR FARMÁCIA (MÉDIA SIMPLES)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicadorMediaItens;

SELECT 
    cnpj,
    SUM(qtd_itens) AS total_medicamentos_vendidos,
    COUNT(num_autorizacao) AS total_autorizacoes,
    
    -- MÉDIA DE ITENS POR AUTORIZAÇÃO
    -- Ex: 2.5 itens por venda em média
    CAST(
        CASE 
            WHEN COUNT(num_autorizacao) > 0 THEN 
                CAST(SUM(qtd_itens) AS DECIMAL(18,2)) / CAST(COUNT(num_autorizacao) AS DECIMAL(18,2))
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS media_itens_autorizacao

INTO temp_CGUSC.fp.indicadorMediaItens
FROM #ContagemItensAutorizacao
GROUP BY cnpj;

CREATE CLUSTERED INDEX IDX_IndMedia_CNPJ ON temp_CGUSC.fp.indicadorMediaItens(cnpj);

-- Limpeza da tabela temporária
DROP TABLE #ContagemItensAutorizacao;


-- ============================================================================
-- PASSO 3: CÁLCULO DAS MÉDIAS POR ESTADO (UF)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicadorMediaItens_UF;

SELECT 
    CAST(F.uf AS VARCHAR(2)) AS uf,
    
    SUM(I.total_medicamentos_vendidos) AS total_medicamentos_uf,
    SUM(I.total_autorizacoes) AS total_autorizacoes_uf,
    
    -- Média do Estado
    CAST(
        CASE 
            WHEN SUM(I.total_autorizacoes) > 0 THEN 
                CAST(SUM(I.total_medicamentos_vendidos) AS DECIMAL(18,2)) / CAST(SUM(I.total_autorizacoes) AS DECIMAL(18,2))
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS media_itens_autorizacao_uf

INTO temp_CGUSC.fp.indicadorMediaItens_UF
FROM temp_CGUSC.fp.indicadorMediaItens I
INNER JOIN temp_CGUSC.fp.dadosFarmaciasFP F 
    ON F.cnpj = I.cnpj
GROUP BY CAST(F.uf AS VARCHAR(2));

CREATE CLUSTERED INDEX IDX_IndMediaUF_UF ON temp_CGUSC.fp.indicadorMediaItens_UF(uf);


-- ============================================================================
-- PASSO 4: CÁLCULO DA MÉDIA NACIONAL
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicadorMediaItens_BR;

SELECT 
    'BR' AS pais,
    SUM(total_medicamentos_vendidos) AS total_medicamentos_br,
    SUM(total_autorizacoes) AS total_autorizacoes_br,
    
    -- Média Nacional
    CAST(
        CASE 
            WHEN SUM(total_autorizacoes) > 0 THEN 
                CAST(SUM(total_medicamentos_vendidos) AS DECIMAL(18,2)) / CAST(SUM(total_autorizacoes) AS DECIMAL(18,2))
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS media_itens_autorizacao_br

INTO temp_CGUSC.fp.indicadorMediaItens_BR
FROM temp_CGUSC.fp.indicadorMediaItens;


-- ============================================================================
-- PASSO 5: TABELA CONSOLIDADA FINAL (COMPARATIVO DE RISCO)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicadorMediaItens_Completo;

SELECT 
    I.cnpj,
    F.razaoSocial,
    F.municipio,
    CAST(F.uf AS VARCHAR(2)) AS uf,
    
    I.total_medicamentos_vendidos,
    I.total_autorizacoes,
    I.media_itens_autorizacao,
    
    -- Comparativos
    ISNULL(UF.media_itens_autorizacao_uf, 0) AS media_estado,
    BR.media_itens_autorizacao_br AS media_pais,
    
    -- RISCO RELATIVO
    CAST(
        CASE 
            WHEN UF.media_itens_autorizacao_uf > 0 THEN 
                I.media_itens_autorizacao / UF.media_itens_autorizacao_uf
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS risco_relativo_uf,

    CAST(
        CASE 
            WHEN BR.media_itens_autorizacao_br > 0 THEN 
                I.media_itens_autorizacao / BR.media_itens_autorizacao_br
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS risco_relativo_br

INTO temp_CGUSC.fp.indicadorMediaItens_Completo
FROM temp_CGUSC.fp.indicadorMediaItens I
INNER JOIN temp_CGUSC.fp.dadosFarmaciasFP F 
    ON F.cnpj = I.cnpj
LEFT JOIN temp_CGUSC.fp.indicadorMediaItens_UF UF 
    ON CAST(F.uf AS VARCHAR(2)) = UF.uf
CROSS JOIN temp_CGUSC.fp.indicadorMediaItens_BR BR;

CREATE CLUSTERED INDEX IDX_FinalMedia_CNPJ ON temp_CGUSC.fp.indicadorMediaItens_Completo(cnpj);
CREATE NONCLUSTERED INDEX IDX_FinalMedia_Risco ON temp_CGUSC.fp.indicadorMediaItens_Completo(risco_relativo_uf DESC);
GO

-- Verificação rápida
SELECT TOP 100 * FROM temp_CGUSC.fp.indicadorMediaItens_Completo ORDER BY risco_relativo_uf DESC;
