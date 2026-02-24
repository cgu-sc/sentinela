USE [temp_CGUSC]
GO

-- ============================================================================
-- DEFINIÇÃO DE VARIÁVEIS
-- ============================================================================
DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim DATE = '2024-12-10';

-- ============================================================================
-- PASSO 1: PRÉ-CÁLCULO - VALOR TOTAL POR CUPOM
-- Agrupa os itens para saber quanto custou cada autorização inteira.
-- ============================================================================
DROP TABLE IF EXISTS #ValorPorCupom;

SELECT 
    A.cnpj,
    A.num_autorizacao,
    SUM(A.valor_pago) AS valor_total_cupom
INTO #ValorPorCupom
FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
INNER JOIN temp_CGUSC.dbo.medicamentosPatologiaFP C 
    ON C.codigo_barra = A.codigo_barra
WHERE 
    A.data_hora >= @DataInicio 
    AND A.data_hora <= @DataFim
GROUP BY A.cnpj, A.num_autorizacao;

-- Índice para acelerar a agregação por farmácia
CREATE CLUSTERED INDEX IDX_TempValor_CNPJ ON #ValorPorCupom(cnpj);


-- ============================================================================
-- PASSO 2: CÁLCULO BASE POR FARMÁCIA (TICKET MÉDIO)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.dbo.indicadorTicketMedio;

SELECT 
    cnpj,
    
    -- Total Movimentado (Soma de todos os cupons)
    SUM(valor_total_cupom) AS valor_total_periodo,
    
    -- Quantidade de Vendas (Cupons)
    COUNT(*) AS qtd_cupons,
    
    -- TICKET MÉDIO (Valor / Quantidade)
    CAST(
        CASE 
            WHEN COUNT(*) > 0 THEN 
                SUM(valor_total_cupom) / COUNT(*)
            ELSE 0 
        END 
    AS DECIMAL(18,2)) AS valor_ticket_medio

INTO temp_CGUSC.dbo.indicadorTicketMedio
FROM #ValorPorCupom
GROUP BY cnpj;

CREATE CLUSTERED INDEX IDX_IndTicket_CNPJ ON temp_CGUSC.dbo.indicadorTicketMedio(cnpj);

-- Limpeza
DROP TABLE #ValorPorCupom;


-- ============================================================================
-- PASSO 3: CÁLCULO DAS MÉDIAS POR ESTADO (UF)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.dbo.indicadorTicketMedio_UF;

SELECT 
    CAST(F.uf AS VARCHAR(2)) AS uf,
    
    SUM(I.valor_total_periodo) AS total_valor_uf,
    SUM(I.qtd_cupons) AS total_cupons_uf,
    
    -- Ticket Médio do Estado
    CAST(
        CASE 
            WHEN SUM(I.qtd_cupons) > 0 THEN 
                SUM(I.valor_total_periodo) / SUM(I.qtd_cupons)
            ELSE 0 
        END 
    AS DECIMAL(18,2)) AS ticket_medio_uf

INTO temp_CGUSC.dbo.indicadorTicketMedio_UF
FROM temp_CGUSC.dbo.indicadorTicketMedio I
INNER JOIN temp_CGUSC.dbo.dadosFarmaciasFP F 
    ON F.cnpj = I.cnpj
GROUP BY CAST(F.uf AS VARCHAR(2));

CREATE CLUSTERED INDEX IDX_IndTicketUF_UF ON temp_CGUSC.dbo.indicadorTicketMedio_UF(uf);


-- ============================================================================
-- PASSO 4: CÁLCULO DA MÉDIA NACIONAL (BRASIL)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.dbo.indicadorTicketMedio_BR;

SELECT 
    'BR' AS pais,
    SUM(valor_total_periodo) AS total_valor_br,
    SUM(qtd_cupons) AS total_cupons_br,
    
    -- Ticket Médio Nacional
    CAST(
        CASE 
            WHEN SUM(qtd_cupons) > 0 THEN 
                SUM(valor_total_periodo) / SUM(qtd_cupons)
            ELSE 0 
        END 
    AS DECIMAL(18,2)) AS ticket_medio_br

INTO temp_CGUSC.dbo.indicadorTicketMedio_BR
FROM temp_CGUSC.dbo.indicadorTicketMedio;


-- ============================================================================
-- PASSO 5: TABELA CONSOLIDADA FINAL (COMPARATIVO DE RISCO)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.dbo.indicadorTicketMedio_Completo;

SELECT 
    I.cnpj,
    F.razaoSocial,
    F.municipio,
    CAST(F.uf AS VARCHAR(2)) AS uf,
    
    I.valor_total_periodo,
    I.qtd_cupons,
    I.valor_ticket_medio,
    
    -- Comparativos (Valores Monetários)
    ISNULL(UF.ticket_medio_uf, 0) AS media_estado,
    BR.ticket_medio_br AS media_pais,
    
    -- RISCO RELATIVO (Quantas vezes o ticket é maior que a média?)
    -- Ex: 2.5000 = Ticket é 2,5x maior que a média do estado
    CAST(
        CASE 
            WHEN UF.ticket_medio_uf > 0 THEN 
                I.valor_ticket_medio / UF.ticket_medio_uf
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS risco_relativo_uf,

    CAST(
        CASE 
            WHEN BR.ticket_medio_br > 0 THEN 
                I.valor_ticket_medio / BR.ticket_medio_br
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS risco_relativo_br

INTO temp_CGUSC.dbo.indicadorTicketMedio_Completo
FROM temp_CGUSC.dbo.indicadorTicketMedio I
INNER JOIN temp_CGUSC.dbo.dadosFarmaciasFP F 
    ON F.cnpj = I.cnpj
LEFT JOIN temp_CGUSC.dbo.indicadorTicketMedio_UF UF 
    ON CAST(F.uf AS VARCHAR(2)) = UF.uf
CROSS JOIN temp_CGUSC.dbo.indicadorTicketMedio_BR BR;

-- Índices Finais
CREATE CLUSTERED INDEX IDX_FinalTicket_CNPJ ON temp_CGUSC.dbo.indicadorTicketMedio_Completo(cnpj);
CREATE NONCLUSTERED INDEX IDX_FinalTicket_Risco ON temp_CGUSC.dbo.indicadorTicketMedio_Completo(risco_relativo_uf DESC);
GO

-- Verificação rápida
SELECT TOP 100 * FROM temp_CGUSC.dbo.indicadorTicketMedio_Completo ORDER BY risco_relativo_uf DESC;