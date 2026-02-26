USE [temp_CGUSC]
GO

-- ============================================================================
-- DEFINIÇÃO DE VARIÁVEIS
-- ============================================================================
DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim DATE = '2024-12-10';

-- ============================================================================
-- PASSO 1: PRÉ-CÁLCULO - AGRUPAR ITENS POR CUPOM
-- Identifica quantos itens monitorados existem em cada autorização.
-- ============================================================================
-- Usamos Tabela Temporária (#) aqui pois é mais rápido para volumes massivos 
-- de agrupamento do que CTE.
DROP TABLE IF EXISTS #VendasPorCupom;

SELECT 
    A.cnpj,
    A.num_autorizacao,
    COUNT(*) AS qtd_itens_distintos
INTO #VendasPorCupom
FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
INNER JOIN temp_CGUSC.fp.medicamentos_patologia C 
    ON C.codigo_barra = A.codigo_barra
WHERE 
    A.data_hora >= @DataInicio 
    AND A.data_hora <= @DataFim
GROUP BY A.cnpj, A.num_autorizacao;

-- Cria índice para acelerar a agregação final
CREATE CLUSTERED INDEX IDX_TempCupom_CNPJ ON #VendasPorCupom(cnpj);


-- ============================================================================
-- PASSO 2: CÁLCULO BASE POR FARMÁCIA (INDICADOR CESTA CHEIA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_polimedicamento;

SELECT 
    cnpj,
    
    -- Total de Cupons/Autorizações Analisadas
    COUNT(*) AS total_cupons_monitorados,
    
    -- Contagem de Cupons com 4 ou mais itens ("Cesta Cheia")
    SUM(CASE 
        WHEN qtd_itens_distintos >= 4 THEN 1 
        ELSE 0 
    END) AS qtd_cupons_suspeitos,
    
    -- CÁLCULO DO PERCENTUAL (0 a 100, 4 casas decimais)
    CAST(
        CASE 
            WHEN COUNT(*) > 0 THEN 
                (CAST(SUM(CASE WHEN qtd_itens_distintos >= 4 THEN 1 ELSE 0 END) AS DECIMAL(18,2)) / CAST(COUNT(*) AS DECIMAL(18,2))) * 100.0
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS percentual_polimedicamento

INTO temp_CGUSC.fp.indicador_polimedicamento
FROM #VendasPorCupom
GROUP BY cnpj;

CREATE CLUSTERED INDEX IDX_IndPoli_CNPJ ON temp_CGUSC.fp.indicador_polimedicamento(cnpj);

-- Limpeza da temp table para liberar espaço
DROP TABLE #VendasPorCupom;


-- ============================================================================
-- PASSO 3: CÁLCULO DAS MÉDIAS POR ESTADO (UF)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_polimedicamento_uf;

SELECT 
    CAST(F.uf AS VARCHAR(2)) AS uf,
    
    SUM(I.total_cupons_monitorados) AS total_cupons_uf,
    SUM(I.qtd_cupons_suspeitos) AS total_suspeitos_uf,
    
    -- Média do Estado
    CAST(
        CASE 
            WHEN SUM(I.total_cupons_monitorados) > 0 THEN 
                (CAST(SUM(I.qtd_cupons_suspeitos) AS DECIMAL(18,2)) / CAST(SUM(I.total_cupons_monitorados) AS DECIMAL(18,2))) * 100.0
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS percentual_polimedicamento_uf

INTO temp_CGUSC.fp.indicador_polimedicamento_uf
FROM temp_CGUSC.fp.indicador_polimedicamento I
INNER JOIN temp_CGUSC.fp.dados_farmacia F 
    ON F.cnpj = I.cnpj
GROUP BY CAST(F.uf AS VARCHAR(2));

CREATE CLUSTERED INDEX IDX_IndPoliUF_uf ON temp_CGUSC.fp.indicador_polimedicamento_uf(uf);


-- ============================================================================
-- PASSO 4: CÁLCULO DA MÉDIA NACIONAL (BRASIL)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_polimedicamento_br;

SELECT 
    'BR' AS pais,
    SUM(total_cupons_monitorados) AS total_cupons_br,
    SUM(qtd_cupons_suspeitos) AS total_suspeitos_br,
    
    -- Média Nacional
    CAST(
        CASE 
            WHEN SUM(total_cupons_monitorados) > 0 THEN 
                (CAST(SUM(qtd_cupons_suspeitos) AS DECIMAL(18,2)) / CAST(SUM(total_cupons_monitorados) AS DECIMAL(18,2))) * 100.0
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS percentual_polimedicamento_br

INTO temp_CGUSC.fp.indicador_polimedicamento_br
FROM temp_CGUSC.fp.indicador_polimedicamento;


-- ============================================================================
-- PASSO 5: TABELA CONSOLIDADA FINAL (COMPARATIVO DE RISCO)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_polimedicamento_detalhado;

SELECT 
    I.cnpj,
    F.razaoSocial,
    F.municipio,
    CAST(F.uf AS VARCHAR(2)) AS uf,
    
    I.total_cupons_monitorados,
    I.qtd_cupons_suspeitos,
    I.percentual_polimedicamento,
    
    -- Comparativos
    ISNULL(UF.percentual_polimedicamento_uf, 0) AS media_estado,
    BR.percentual_polimedicamento_br AS media_pais,
    
    -- RISCO RELATIVO
    CAST(
        CASE 
            WHEN UF.percentual_polimedicamento_uf > 0 THEN 
                I.percentual_polimedicamento / UF.percentual_polimedicamento_uf
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS risco_relativo_uf,

    CAST(
        CASE 
            WHEN BR.percentual_polimedicamento_br > 0 THEN 
                I.percentual_polimedicamento / BR.percentual_polimedicamento_br
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS risco_relativo_br

INTO temp_CGUSC.fp.indicador_polimedicamento_detalhado
FROM temp_CGUSC.fp.indicador_polimedicamento I
INNER JOIN temp_CGUSC.fp.dados_farmacia F 
    ON F.cnpj = I.cnpj
LEFT JOIN temp_CGUSC.fp.indicador_polimedicamento_uf UF 
    ON CAST(F.uf AS VARCHAR(2)) = UF.uf
CROSS JOIN temp_CGUSC.fp.indicador_polimedicamento_br BR;

-- Índices Finais
CREATE CLUSTERED INDEX IDX_FinalPoli_CNPJ ON temp_CGUSC.fp.indicador_polimedicamento_detalhado(cnpj);
CREATE NONCLUSTERED INDEX IDX_FinalPoli_Risco ON temp_CGUSC.fp.indicador_polimedicamento_detalhado(risco_relativo_uf DESC);
GO

-- Verificação rápida
SELECT TOP 100 * FROM temp_CGUSC.fp.indicador_polimedicamento_detalhado ORDER BY risco_relativo_uf DESC;


