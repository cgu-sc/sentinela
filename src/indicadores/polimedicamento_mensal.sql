USE [temp_CGUSC]
GO

-- ============================================================================
-- SCRIPT: Indicador de Polimedicamento (VERSÃO MENSAL)
-- OBJETIVO: Gerar scores de risco por CNPJ e por Mês para análise temporal.
-- ============================================================================

DECLARE @DataInicio DATE = '2015-07-01'; -- Período Total Histórico
DECLARE @DataFim    DATE = '2024-12-31';

PRINT '>> INICIANDO CÁLCULO MENSAL DE POLIMEDICAMENTO...';

-- ============================================================================
-- PASSO 1: AGRUPAR ITEMS POR CUPOM E MÊS
-- ============================================================================
DROP TABLE IF EXISTS #VendasPorCupomMensal;

SELECT
    A.cnpj,
    A.num_autorizacao,
    -- Criamos a chave mensal (Primeiro dia do mês para facilitar JOINs e ordenação)
    CAST(DATEADD(MONTH, DATEDIFF(MONTH, 0, A.data_hora), 0) AS DATE) AS mes_referencia,
    COUNT(*) AS qtd_itens_distintos
INTO #VendasPorCupomMensal
FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
INNER JOIN temp_CGUSC.fp.medicamentos_patologia C
    ON C.codigo_barra = A.codigo_barra
WHERE
    A.data_hora >= @DataInicio
    AND A.data_hora <= @DataFim
GROUP BY A.cnpj, A.num_autorizacao, DATEADD(MONTH, DATEDIFF(MONTH, 0, A.data_hora), 0);

CREATE CLUSTERED INDEX IDX_TempCupom_CNPJ_Mes ON #VendasPorCupomMensal(cnpj, mes_referencia);


-- ============================================================================
-- PASSO 2: CÁLCULO MENSAL POR FARMÁCIA
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_polimedicamento_mensal_base;

SELECT
    cnpj,
    mes_referencia,
    COUNT(*)                                                            AS total_cupons_monitorados,
    SUM(CASE WHEN qtd_itens_distintos >= 4 THEN 1 ELSE 0 END)          AS qtd_cupons_suspeitos,
    CAST(
        CASE
            WHEN COUNT(*) > 0 THEN
                (CAST(SUM(CASE WHEN qtd_itens_distintos >= 4 THEN 1 ELSE 0 END) AS DECIMAL(18,2)) /
                 CAST(COUNT(*) AS DECIMAL(18,2))) * 100.0
            ELSE 0
        END
    AS DECIMAL(18,4)) AS percentual_polimedicamento
INTO temp_CGUSC.fp.indicador_polimedicamento_mensal_base
FROM #VendasPorCupomMensal
GROUP BY cnpj, mes_referencia;

CREATE CLUSTERED INDEX IDX_Base_CNPJ_Mes ON temp_CGUSC.fp.indicador_polimedicamento_mensal_base(cnpj, mes_referencia);


-- ============================================================================
-- PASSO 3: BENCHMARKS POR TEMPO E GEOGRAFIA (MENSAL)
-- Isso garante que comparamos Jan/2024 com Jan/2024.
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_polimedicamento_benchmarks_mensais;

SELECT DISTINCT
    F.uf,
    F.municipio,
    F.id_regiao_saude,
    I.mes_referencia,
    -- Mediana Municipal do Mês
    CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.percentual_polimedicamento, 0))
        OVER (PARTITION BY F.uf, F.municipio, I.mes_referencia) AS DECIMAL(18,4)) AS mediana_mun_mes,
    -- Mediana Estadual do Mês
    CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.percentual_polimedicamento, 0))
        OVER (PARTITION BY F.uf, I.mes_referencia) AS DECIMAL(18,4)) AS mediana_uf_mes,
    -- Mediana Nacional do Mês
    CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.percentual_polimedicamento, 0))
        OVER (PARTITION BY I.mes_referencia) AS DECIMAL(18,4)) AS mediana_br_mes
INTO temp_CGUSC.fp.indicador_polimedicamento_benchmarks_mensais
FROM temp_CGUSC.fp.indicador_polimedicamento_mensal_base I
INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj;


-- ============================================================================
-- PASSO 4: TABELA FINAL TEMPORAL
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_polimedicamento_mensal_detalhado;

SELECT
    I.cnpj,
    I.mes_referencia,
    F.razaoSocial,
    F.municipio,
    F.uf,
    I.total_cupons_monitorados,
    I.qtd_cupons_suspeitos,
    I.percentual_polimedicamento,

    -- Benchmarks Relativos ao Mês
    B.mediana_mun_mes,
    B.mediana_uf_mes,
    B.mediana_br_mes,

    -- Risco Relativo (Comparando o desempenho naquele mês específico)
    CAST((I.percentual_polimedicamento + 0.01) / (B.mediana_mun_mes + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun,
    CAST((I.percentual_polimedicamento + 0.01) / (B.mediana_uf_mes + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf,
    CAST((I.percentual_polimedicamento + 0.01) / (B.mediana_br_mes + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br

INTO temp_CGUSC.fp.indicador_polimedicamento_mensal_detalhado
FROM temp_CGUSC.fp.indicador_polimedicamento_mensal_base I
INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj
INNER JOIN temp_CGUSC.fp.indicador_polimedicamento_benchmarks_mensais B
    ON B.mes_referencia = I.mes_referencia
    AND B.uf = F.uf
    AND B.municipio = F.municipio;

-- Limpeza
DROP TABLE #VendasPorCupomMensal;
DROP TABLE temp_CGUSC.fp.indicador_polimedicamento_mensal_base;
DROP TABLE temp_CGUSC.fp.indicador_polimedicamento_benchmarks_mensais;

PRINT '>> Tabela temp_CGUSC.fp.indicador_polimedicamento_mensal_detalhado criada.';
GO
