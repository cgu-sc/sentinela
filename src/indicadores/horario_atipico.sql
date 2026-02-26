USE [temp_CGUSC]
GO

-- ============================================================================
-- DEFINIÇÃO DE VARIÁVEIS
-- ============================================================================
DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim DATE = '2024-12-10';

-- ============================================================================
-- PASSO 1: CÁLCULO BASE POR FARMÁCIA (HORÁRIO ATÍPICO)
-- Consideramos madrugada: 00:00 até 05:59
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicadorHorarioAtipico;

WITH VendasPorHorario AS (
    SELECT 
        A.cnpj,
        A.num_autorizacao,
        MIN(A.data_hora) AS data_hora_venda,
        
        -- Verifica se a venda ocorreu na madrugada (considera o horário da primeira linha)
        MAX(CASE 
            WHEN DATEPART(HOUR, A.data_hora) BETWEEN 0 AND 5 THEN 1 
            ELSE 0 
        END) AS flag_madrugada

    FROM db_farmaciapopular.fp.relatorio_movimentacao_2015_2024 A
    INNER JOIN temp_CGUSC.fp.medicamentosPatologiaFP C 
        ON C.codigo_barra = A.codigo_barra
    WHERE 
        A.data_hora >= @DataInicio 
        AND A.data_hora <= @DataFim

    GROUP BY A.cnpj, A.num_autorizacao
),
AgregadoPorFarmacia AS (
    SELECT 
        cnpj,
        COUNT(*) AS total_vendas_monitoradas,
        SUM(flag_madrugada) AS qtd_vendas_madrugada
    FROM VendasPorHorario
    GROUP BY cnpj
)

SELECT 
    cnpj,
    total_vendas_monitoradas,
    qtd_vendas_madrugada,
    
    CAST(
        CASE 
            WHEN total_vendas_monitoradas > 0 THEN 
                (CAST(qtd_vendas_madrugada AS DECIMAL(18,2)) / CAST(total_vendas_monitoradas AS DECIMAL(18,2))) * 100.0
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS percentual_madrugada

INTO temp_CGUSC.fp.indicadorHorarioAtipico
FROM AgregadoPorFarmacia
WHERE total_vendas_monitoradas > 0;

CREATE CLUSTERED INDEX IDX_IndHora_CNPJ ON temp_CGUSC.fp.indicadorHorarioAtipico(cnpj);


-- ============================================================================
-- PASSO 2: CÁLCULO DAS MÉDIAS POR ESTADO (UF)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicadorHorarioAtipico_UF;

SELECT 
    CAST(F.uf AS VARCHAR(2)) AS uf,
    
    SUM(I.total_vendas_monitoradas) AS total_vendas_uf,
    SUM(I.qtd_vendas_madrugada) AS total_madrugada_uf,
    
    -- Média do Estado
    CAST(
        CASE 
            WHEN SUM(I.total_vendas_monitoradas) > 0 THEN 
                (CAST(SUM(I.qtd_vendas_madrugada) AS DECIMAL(18,2)) / CAST(SUM(I.total_vendas_monitoradas) AS DECIMAL(18,2))) * 100.0
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS percentual_madrugada_uf

INTO temp_CGUSC.fp.indicadorHorarioAtipico_UF
FROM temp_CGUSC.fp.indicadorHorarioAtipico I
INNER JOIN temp_CGUSC.fp.dadosFarmaciasFP F 
    ON F.cnpj = I.cnpj
GROUP BY CAST(F.uf AS VARCHAR(2));

CREATE CLUSTERED INDEX IDX_IndHoraUF_UF ON temp_CGUSC.fp.indicadorHorarioAtipico_UF(uf);


-- ============================================================================
-- PASSO 3: CÁLCULO DA MÉDIA NACIONAL
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicadorHorarioAtipico_BR;

SELECT 
    'BR' AS pais,
    SUM(total_vendas_monitoradas) AS total_vendas_br,
    SUM(qtd_vendas_madrugada) AS total_madrugada_br,
    
    -- Média Nacional
    CAST(
        CASE 
            WHEN SUM(total_vendas_monitoradas) > 0 THEN 
                (CAST(SUM(qtd_vendas_madrugada) AS DECIMAL(18,2)) / CAST(SUM(total_vendas_monitoradas) AS DECIMAL(18,2))) * 100.0
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS percentual_madrugada_br

INTO temp_CGUSC.fp.indicadorHorarioAtipico_BR
FROM temp_CGUSC.fp.indicadorHorarioAtipico;


-- ============================================================================
-- PASSO 4: TABELA CONSOLIDADA FINAL
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicadorHorarioAtipico_Completo;

SELECT 
    I.cnpj,
    F.razaoSocial,
    F.municipio,
    CAST(F.uf AS VARCHAR(2)) AS uf,
    
    I.total_vendas_monitoradas,
    I.qtd_vendas_madrugada,
    I.percentual_madrugada,
    
    -- Comparativos
    ISNULL(UF.percentual_madrugada_uf, 0) AS media_estado,
    BR.percentual_madrugada_br AS media_pais,
    
    -- RISCO RELATIVO
    CAST(
        CASE 
            WHEN UF.percentual_madrugada_uf > 0 THEN 
                I.percentual_madrugada / UF.percentual_madrugada_uf
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS risco_relativo_uf,

    CAST(
        CASE 
            WHEN BR.percentual_madrugada_br > 0 THEN 
                I.percentual_madrugada / BR.percentual_madrugada_br
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS risco_relativo_br

INTO temp_CGUSC.fp.indicadorHorarioAtipico_Completo
FROM temp_CGUSC.fp.indicadorHorarioAtipico I
INNER JOIN temp_CGUSC.fp.dadosFarmaciasFP F 
    ON F.cnpj = I.cnpj
LEFT JOIN temp_CGUSC.fp.indicadorHorarioAtipico_UF UF 
    ON CAST(F.uf AS VARCHAR(2)) = UF.uf
CROSS JOIN temp_CGUSC.fp.indicadorHorarioAtipico_BR BR;

CREATE CLUSTERED INDEX IDX_FinalHora_CNPJ ON temp_CGUSC.fp.indicadorHorarioAtipico_Completo(cnpj);
CREATE NONCLUSTERED INDEX IDX_FinalHora_Risco ON temp_CGUSC.fp.indicadorHorarioAtipico_Completo(risco_relativo_uf DESC);
GO


select top 1000 * from indicadorHorarioAtipico_Completo order by risco_relativo_uf desc
