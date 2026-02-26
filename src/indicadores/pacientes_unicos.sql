USE [temp_CGUSC]
GO

-- ============================================================================
-- INDICADOR: PACIENTES FANTASMA (BAIXÍSSIMA RECORRÊNCIA)
-- ============================================================================
-- O que mede: Proporção de CPFs que compraram apenas 1 vez no período de 9 anos
-- Por que importa: Pacientes crônicos deveriam retornar; muitos CPFs únicos 
--                  indicam possível uso fraudulento de documentos
-- Métrica: % de CPFs com apenas 1 compra vs média estadual/nacional
-- ============================================================================

DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim DATE = '2024-12-10';

-- ============================================================================
-- PASSO 1: PRÉ-CÁLCULO - CONTAGEM DE COMPRAS POR CPF EM CADA FARMÁCIA
-- Agrupa para saber quantas vezes cada CPF comprou em cada estabelecimento
-- ============================================================================
DROP TABLE IF EXISTS #RecorrenciaPorCPF;

SELECT 
    A.cnpj,
    A.cpf,
    COUNT(DISTINCT A.num_autorizacao) AS qtd_compras_cpf  -- DISTINCT é crítico aqui!
INTO #RecorrenciaPorCPF
FROM db_farmaciapopular.fp.relatorio_movimentacao_2015_2024 A
INNER JOIN temp_CGUSC.fp.medicamentosPatologiaFP C 
    ON C.codigo_barra = A.codigo_barra
WHERE 
    A.data_hora >= @DataInicio 
    AND A.data_hora <= @DataFim
    AND A.cpf IS NOT NULL
GROUP BY A.cnpj, A.cpf;

CREATE CLUSTERED INDEX IDX_TempRecorrencia_CNPJ ON #RecorrenciaPorCPF(cnpj);

-- ============================================================================
-- PASSO 2: CÁLCULO BASE POR FARMÁCIA (INDICADOR PACIENTES FANTASMA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicadorPacientesFantasma;

SELECT 
    cnpj,
    
    -- Total de CPFs únicos que compraram na farmácia
    COUNT(*) AS total_cpfs_distintos,
    
    -- Contagem de CPFs que compraram apenas 1 vez
    SUM(CASE 
        WHEN qtd_compras_cpf = 1 THEN 1 
        ELSE 0 
    END) AS qtd_cpfs_fantasma,
    
    -- CÁLCULO DO PERCENTUAL (0 a 100, 4 casas decimais)
    CAST(
        CASE 
            WHEN COUNT(*) > 0 THEN 
                (CAST(SUM(CASE WHEN qtd_compras_cpf = 1 THEN 1 ELSE 0 END) AS DECIMAL(18,2)) / CAST(COUNT(*) AS DECIMAL(18,2))) * 100.0
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS percentual_pacientes_unicos,

    -- ESTATÍSTICA ADICIONAL: Média de compras por CPF (para contexto)
    CAST(AVG(CAST(qtd_compras_cpf AS DECIMAL(18,2))) AS DECIMAL(18,2)) AS media_compras_por_cpf

INTO temp_CGUSC.fp.indicadorPacientesFantasma
FROM #RecorrenciaPorCPF
GROUP BY cnpj;

CREATE CLUSTERED INDEX IDX_IndFantasma_CNPJ ON temp_CGUSC.fp.indicadorPacientesFantasma(cnpj);

-- Limpeza
DROP TABLE #RecorrenciaPorCPF;


-- ============================================================================
-- PASSO 3: CÁLCULO DAS MÉDIAS POR ESTADO (UF)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicadorPacientesFantasma_UF;

SELECT 
    CAST(F.uf AS VARCHAR(2)) AS uf,
    
    SUM(I.total_cpfs_distintos) AS total_cpfs_uf,
    SUM(I.qtd_cpfs_fantasma) AS total_fantasma_uf,
    
    -- Média do Estado (calculada como agregação, não média de percentuais)
    CAST(
        CASE 
            WHEN SUM(I.total_cpfs_distintos) > 0 THEN 
                (CAST(SUM(I.qtd_cpfs_fantasma) AS DECIMAL(18,2)) / CAST(SUM(I.total_cpfs_distintos) AS DECIMAL(18,2))) * 100.0
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS percentual_pacientes_unicos_uf

INTO temp_CGUSC.fp.indicadorPacientesFantasma_UF
FROM temp_CGUSC.fp.indicadorPacientesFantasma I
INNER JOIN temp_CGUSC.fp.dadosFarmaciasFP F 
    ON F.cnpj = I.cnpj
GROUP BY CAST(F.uf AS VARCHAR(2));

CREATE CLUSTERED INDEX IDX_IndFantasmaUF_UF ON temp_CGUSC.fp.indicadorPacientesFantasma_UF(uf);



-- ============================================================================
-- PASSO 4: CÁLCULO DA MÉDIA NACIONAL (BRASIL)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicadorPacientesFantasma_BR;

SELECT 
    'BR' AS pais,
    SUM(total_cpfs_distintos) AS total_cpfs_br,
    SUM(qtd_cpfs_fantasma) AS total_fantasma_br,
    
    -- Média Nacional
    CAST(
        CASE 
            WHEN SUM(total_cpfs_distintos) > 0 THEN 
                (CAST(SUM(qtd_cpfs_fantasma) AS DECIMAL(18,2)) / CAST(SUM(total_cpfs_distintos) AS DECIMAL(18,2))) * 100.0
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS percentual_pacientes_unicos_br

INTO temp_CGUSC.fp.indicadorPacientesFantasma_BR
FROM temp_CGUSC.fp.indicadorPacientesFantasma;


-- ============================================================================
-- PASSO 5: TABELA CONSOLIDADA FINAL (COMPARATIVO DE RISCO)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicadorPacientesUnicos_Completo;

SELECT 
    I.cnpj,
    F.razaoSocial,
    F.municipio,
    CAST(F.uf AS VARCHAR(2)) AS uf,
    
    I.total_cpfs_distintos,
    I.qtd_cpfs_fantasma,
    I.percentual_pacientes_unicos,
    I.media_compras_por_cpf,
    
    -- Comparativos
    ISNULL(UF.percentual_pacientes_unicos_uf, 0) AS media_estado,
    BR.percentual_pacientes_unicos_br AS media_pais,
    
    -- RISCO RELATIVO
    -- Ex: 1.5000 = A farmácia tem 50% mais CPFs fantasma que a média do estado
    CAST(
        CASE 
            WHEN UF.percentual_pacientes_unicos_uf > 0 THEN 
                I.percentual_pacientes_unicos / UF.percentual_pacientes_unicos_uf
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS risco_relativo_uf,

    CAST(
        CASE 
            WHEN BR.percentual_pacientes_unicos_br > 0 THEN 
                I.percentual_pacientes_unicos / BR.percentual_pacientes_unicos_br
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS risco_relativo_br

INTO temp_CGUSC.fp.indicadorPacientesUnicos_Completo
FROM temp_CGUSC.fp.indicadorPacientesFantasma I
INNER JOIN temp_CGUSC.fp.dadosFarmaciasFP F 
    ON F.cnpj = I.cnpj
LEFT JOIN temp_CGUSC.fp.indicadorPacientesFantasma_UF UF 
    ON CAST(F.uf AS VARCHAR(2)) = UF.uf
CROSS JOIN temp_CGUSC.fp.indicadorPacientesFantasma_BR BR;

-- Índices Finais
CREATE CLUSTERED INDEX IDX_FinalFantasma_CNPJ ON temp_CGUSC.fp.indicadorPacientesUnicos_Completo(cnpj);
CREATE NONCLUSTERED INDEX IDX_FinalFantasma_Risco ON temp_CGUSC.fp.indicadorPacientesUnicos_Completo(risco_relativo_uf DESC);
GO
-- ============================================================================
-- VERIFICAÇÃO E ESTATÍSTICAS
-- ============================================================================
SELECT TOP 100 * 
FROM temp_CGUSC.fp.indicadorPacientesUnicos_Completo 
ORDER BY risco_relativo_uf DESC;

-- Estatísticas gerais do indicador
SELECT 
    'BRASIL' AS escopo,
    COUNT(*) AS total_farmacias_analisadas,
    AVG(percentual_pacientes_unicos) AS media_percentual,
    MIN(percentual_pacientes_unicos) AS minimo,
    MAX(percentual_pacientes_unicos) AS maximo,
    STDEV(percentual_pacientes_unicos) AS desvio_padrao
FROM temp_CGUSC.fp.indicadorPacientesUnicos_Completo;

-- Mediana em query separada (COM OVER e usando subquery)
SELECT DISTINCT
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY percentual_pacientes_unicos) OVER () AS mediana
FROM temp_CGUSC.fp.indicadorPacientesUnicos_Completo;

-- Distribuição por faixas de risco
SELECT 
    CASE 
        WHEN risco_relativo_uf < 0.5 THEN '1. Muito Abaixo da Média (< 0.5x)'
        WHEN risco_relativo_uf < 0.8 THEN '2. Abaixo da Média (0.5x - 0.8x)'
        WHEN risco_relativo_uf < 1.2 THEN '3. Dentro da Média (0.8x - 1.2x)'
        WHEN risco_relativo_uf < 1.5 THEN '4. Acima da Média (1.2x - 1.5x)'
        WHEN risco_relativo_uf < 2.0 THEN '5. Alto Risco (1.5x - 2.0x)'
        ELSE '6. Risco Crítico (> 2.0x)'
    END AS faixa_risco,
    COUNT(*) AS qtd_farmacias,
    CAST(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS percentual_farmacias
FROM temp_CGUSC.fp.indicadorPacientesUnicos_Completo
GROUP BY 
    CASE 
        WHEN risco_relativo_uf < 0.5 THEN '1. Muito Abaixo da Média (< 0.5x)'
        WHEN risco_relativo_uf < 0.8 THEN '2. Abaixo da Média (0.5x - 0.8x)'
        WHEN risco_relativo_uf < 1.2 THEN '3. Dentro da Média (0.8x - 1.2x)'
        WHEN risco_relativo_uf < 1.5 THEN '4. Acima da Média (1.2x - 1.5x)'
        WHEN risco_relativo_uf < 2.0 THEN '5. Alto Risco (1.5x - 2.0x)'
        ELSE '6. Risco Crítico (> 2.0x)'
    END
ORDER BY faixa_risco;



select top 10 * from indicadorPacientesUnicos_Completo
