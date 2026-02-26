USE [temp_CGUSC]
GO

-- ============================================================================
-- INDICADOR DE EXCLUSIVIDADE DE CRMs - VERSÃO FONTE DIRETA
-- ============================================================================
-- OBJETIVO: Medir quantos prescritores atuam EXCLUSIVAMENTE nesta farmácia
-- FONTE: db_FarmaciaPopular.carga_2024.relatorio_movimentacao_2021_2024
-- 
-- INTERPRETAÇÃO:
--   - Alta exclusividade (>80%): Pode indicar CRMs "cativos" ou fictícios
--   - Baixa exclusividade (<20%): Médicos compartilhados (normal em grandes redes)
--   - Exclusividade moderada (40-60%): Padrão esperado para farmácias independentes
-- ============================================================================

-- ============================================================================
-- DEFINIÇÃO DE VARIÁVEIS
-- ============================================================================
DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim DATE = '2024-12-10';

-- ============================================================================
-- PASSO 0: IDENTIFICAR TODOS OS CRMs E EM QUANTOS ESTABELECIMENTOS ATUAM
-- ============================================================================
DROP TABLE IF EXISTS #CRMsGlobal;

SELECT 
    CONCAT(crm, '/', crm_uf) AS id_medico,
    crm AS nu_crm,
    crm_uf AS sg_uf_crm,
    COUNT(DISTINCT cnpj) AS qtd_estabelecimentos_atua,
    COUNT(DISTINCT num_autorizacao) AS total_prescricoes_brasil,
    SUM(valor_pago) AS total_valor_brasil
INTO #CRMsGlobal
FROM db_FarmaciaPopular.carga_2024.relatorio_movimentacao_2021_2024
WHERE 
    data_hora >= @DataInicio 
    AND data_hora <= @DataFim
    AND crm IS NOT NULL 
    AND crm_uf IS NOT NULL 
    AND crm_uf <> 'BR'
    AND crm > 0
GROUP BY crm, crm_uf;

CREATE CLUSTERED INDEX IDX_CRMGlobal_ID ON #CRMsGlobal(id_medico);


-- ============================================================================
-- PASSO 1: BASE DE PRESCRITORES POR FARMÁCIA COM INFO DE EXCLUSIVIDADE
-- ============================================================================
DROP TABLE IF EXISTS #CRMsPorFarmacia;

SELECT 
    R.cnpj,
    CONCAT(R.crm, '/', R.crm_uf) AS id_medico,
    R.crm AS nu_crm,
    R.crm_uf AS sg_uf_crm,
    COUNT(DISTINCT R.num_autorizacao) AS nu_prescricoes,
    SUM(R.valor_pago) AS vl_total_prescricoes,
    
    -- INFO GLOBAL DO CRM
    MAX(G.qtd_estabelecimentos_atua) AS qtd_estabelecimentos_atua,
    MAX(G.total_prescricoes_brasil) AS total_prescricoes_crm_brasil,
    
    -- FLAG DE EXCLUSIVIDADE
    CASE 
        WHEN MAX(G.qtd_estabelecimentos_atua) = 1 THEN 1 
        ELSE 0 
    END AS flag_exclusivo

INTO #CRMsPorFarmacia
FROM db_FarmaciaPopular.carga_2024.relatorio_movimentacao_2021_2024 R
INNER JOIN #CRMsGlobal G 
    ON CONCAT(R.crm, '/', R.crm_uf) = G.id_medico
WHERE 
    R.data_hora >= @DataInicio 
    AND R.data_hora <= @DataFim
    AND R.crm IS NOT NULL 
    AND R.crm_uf IS NOT NULL 
    AND R.crm_uf <> 'BR'
    AND R.crm > 0
GROUP BY R.cnpj, R.crm, R.crm_uf;

CREATE CLUSTERED INDEX IDX_CRMFarm_CNPJ ON #CRMsPorFarmacia(cnpj);


-- ============================================================================
-- PASSO 2: AGREGAÇÃO POR FARMÁCIA
-- ============================================================================
DROP TABLE IF EXISTS #ExclusividadePorFarmacia;

SELECT 
    cnpj,
    
    -- Total de prescritores distintos
    COUNT(DISTINCT id_medico) AS total_prescritores,
    
    -- Prescritores exclusivos (flag_exclusivo = 1)
    SUM(flag_exclusivo) AS qtd_prescritores_exclusivos,
    
    -- Prescritores compartilhados (atuam em 2+ estabelecimentos)
    COUNT(DISTINCT CASE 
        WHEN qtd_estabelecimentos_atua > 1 
        THEN id_medico 
    END) AS qtd_prescritores_compartilhados,
    
    -- Prescritores altamente compartilhados (>10 estabelecimentos)
    COUNT(DISTINCT CASE 
        WHEN qtd_estabelecimentos_atua > 10 
        THEN id_medico 
    END) AS qtd_prescritores_multi_rede,
    
    -- Média de estabelecimentos por prescritor
    AVG(CAST(qtd_estabelecimentos_atua AS DECIMAL(18,2))) AS media_estabelecimentos_por_crm,
    
    -- Volume: Prescrições e Valor
    SUM(nu_prescricoes) AS total_prescricoes_farmacia,
    SUM(vl_total_prescricoes) AS total_valor_farmacia,
    
    -- Volume de prescritores exclusivos
    SUM(CASE WHEN flag_exclusivo = 1 THEN nu_prescricoes ELSE 0 END) AS prescricoes_de_exclusivos,
    SUM(CASE WHEN flag_exclusivo = 1 THEN vl_total_prescricoes ELSE 0 END) AS valor_de_exclusivos

INTO #ExclusividadePorFarmacia
FROM #CRMsPorFarmacia
GROUP BY cnpj;

CREATE CLUSTERED INDEX IDX_Excl_CNPJ ON #ExclusividadePorFarmacia(cnpj);


-- ============================================================================
-- PASSO 3: CÁLCULO BASE POR FARMÁCIA (INDICADOR EXCLUSIVIDADE)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_exclusividade_crm;

SELECT 
    cnpj,
    total_prescritores,
    qtd_prescritores_exclusivos,
    qtd_prescritores_compartilhados,
    qtd_prescritores_multi_rede,
    media_estabelecimentos_por_crm,
    
    total_prescricoes_farmacia,
    total_valor_farmacia,
    prescricoes_de_exclusivos,
    valor_de_exclusivos,
    
    -- ÍNDICE DE EXCLUSIVIDADE (% de CRMs que atuam só aqui)
    CAST(
        CASE 
            WHEN total_prescritores > 0 THEN 
                (CAST(qtd_prescritores_exclusivos AS DECIMAL(18,2)) / 
                 CAST(total_prescritores AS DECIMAL(18,2))) * 100.0
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS percentual_exclusividade,
    
    -- ÍNDICE DE COMPARTILHAMENTO (% de CRMs em múltiplos locais)
    CAST(
        CASE 
            WHEN total_prescritores > 0 THEN 
                (CAST(qtd_prescritores_compartilhados AS DECIMAL(18,2)) / 
                 CAST(total_prescritores AS DECIMAL(18,2))) * 100.0
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS percentual_compartilhamento,
    
    -- ÍNDICE DE DISPERSÃO (% de CRMs em >10 estabelecimentos)
    CAST(
        CASE 
            WHEN total_prescritores > 0 THEN 
                (CAST(qtd_prescritores_multi_rede AS DECIMAL(18,2)) / 
                 CAST(total_prescritores AS DECIMAL(18,2))) * 100.0
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS percentual_multi_rede,
    
    -- PARTICIPAÇÃO DE EXCLUSIVOS NO VOLUME
    CAST(
        CASE 
            WHEN total_prescricoes_farmacia > 0 THEN 
                (CAST(prescricoes_de_exclusivos AS DECIMAL(18,2)) / 
                 CAST(total_prescricoes_farmacia AS DECIMAL(18,2))) * 100.0
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS percentual_volume_exclusivos,
    
    -- PARTICIPAÇÃO DE EXCLUSIVOS NO VALOR
    CAST(
        CASE 
            WHEN total_valor_farmacia > 0 THEN 
                (CAST(valor_de_exclusivos AS DECIMAL(18,2)) / 
                 CAST(total_valor_farmacia AS DECIMAL(18,2))) * 100.0
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS percentual_valor_exclusivos

INTO temp_CGUSC.fp.indicador_exclusividade_crm
FROM #ExclusividadePorFarmacia
WHERE total_prescritores > 0;  -- Apenas farmácias com prescritores

CREATE CLUSTERED INDEX IDX_IndExcl_CNPJ ON temp_CGUSC.fp.indicador_exclusividade_crm(cnpj);

-- Limpeza
DROP TABLE #ExclusividadePorFarmacia;
DROP TABLE #CRMsPorFarmacia;
DROP TABLE #CRMsGlobal;


-- ============================================================================
-- PASSO 4: CÁLCULO DAS MÉDIAS POR ESTADO (UF)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_exclusividade_crm_uf;

SELECT 
    CAST(F.uf AS VARCHAR(2)) AS uf,
    
    -- Médias de contagem
    AVG(CAST(I.total_prescritores AS DECIMAL(18,2))) AS media_prescritores_uf,
    AVG(CAST(I.qtd_prescritores_exclusivos AS DECIMAL(18,2))) AS media_exclusivos_uf,
    AVG(I.media_estabelecimentos_por_crm) AS media_dispersao_crm_uf,
    
    -- Médias percentuais
    AVG(I.percentual_exclusividade) AS percentual_exclusividade_uf,
    AVG(I.percentual_compartilhamento) AS percentual_compartilhamento_uf,
    AVG(I.percentual_multi_rede) AS percentual_multi_rede_uf,
    AVG(I.percentual_volume_exclusivos) AS percentual_volume_exclusivos_uf,
    AVG(I.percentual_valor_exclusivos) AS percentual_valor_exclusivos_uf

INTO temp_CGUSC.fp.indicador_exclusividade_crm_uf
FROM temp_CGUSC.fp.indicador_exclusividade_crm I
INNER JOIN temp_CGUSC.fp.dados_farmacia F 
    ON F.cnpj = I.cnpj
GROUP BY CAST(F.uf AS VARCHAR(2));

CREATE CLUSTERED INDEX IDX_IndExclUF_uf ON temp_CGUSC.fp.indicador_exclusividade_crm_uf(uf);


-- ============================================================================
-- PASSO 5: CÁLCULO DA MÉDIA NACIONAL (BRASIL)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_exclusividade_crm_br;

SELECT 
    'BR' AS pais,
    
    AVG(CAST(total_prescritores AS DECIMAL(18,2))) AS media_prescritores_br,
    AVG(CAST(qtd_prescritores_exclusivos AS DECIMAL(18,2))) AS media_exclusivos_br,
    AVG(media_estabelecimentos_por_crm) AS media_dispersao_crm_br,
    
    AVG(percentual_exclusividade) AS percentual_exclusividade_br,
    AVG(percentual_compartilhamento) AS percentual_compartilhamento_br,
    AVG(percentual_multi_rede) AS percentual_multi_rede_br,
    AVG(percentual_volume_exclusivos) AS percentual_volume_exclusivos_br,
    AVG(percentual_valor_exclusivos) AS percentual_valor_exclusivos_br

INTO temp_CGUSC.fp.indicador_exclusividade_crm_br
FROM temp_CGUSC.fp.indicador_exclusividade_crm;


-- ============================================================================
-- PASSO 6: TABELA CONSOLIDADA FINAL (COMPARATIVO DE RISCO)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_exclusividade_crm_detalhado;

SELECT 
    I.cnpj,
    F.razaoSocial,
    F.municipio,
    CAST(F.uf AS VARCHAR(2)) AS uf,
    
    -- Métricas Absolutas
    I.total_prescritores,
    I.qtd_prescritores_exclusivos,
    I.qtd_prescritores_compartilhados,
    I.qtd_prescritores_multi_rede,
    I.media_estabelecimentos_por_crm,
    
    I.total_prescricoes_farmacia,
    I.total_valor_farmacia,
    I.prescricoes_de_exclusivos,
    I.valor_de_exclusivos,
    
    -- Índices Principais
    I.percentual_exclusividade,
    I.percentual_compartilhamento,
    I.percentual_multi_rede,
    I.percentual_volume_exclusivos,
    I.percentual_valor_exclusivos,
    
    -- Comparativos UF
    ISNULL(UF.percentual_exclusividade_uf, 0) AS media_estado,
    ISNULL(UF.percentual_compartilhamento_uf, 0) AS compartilhamento_estado,
    ISNULL(UF.media_dispersao_crm_uf, 0) AS dispersao_estado,
    ISNULL(UF.percentual_volume_exclusivos_uf, 0) AS volume_exclusivos_estado,
    
    -- Comparativos BR
    BR.percentual_exclusividade_br AS media_pais,
    BR.percentual_compartilhamento_br AS compartilhamento_pais,
    BR.media_dispersao_crm_br AS dispersao_pais,
    BR.percentual_volume_exclusivos_br AS volume_exclusivos_pais,
    
    -- RISCO RELATIVO (Exclusividade vs Média)
    -- Quanto MAIOR a exclusividade vs média, MAIOR o risco
    CAST(
        CASE 
            WHEN UF.percentual_exclusividade_uf > 0 THEN 
                I.percentual_exclusividade / UF.percentual_exclusividade_uf
            ELSE 
                CASE WHEN I.percentual_exclusividade > 0 THEN 99.0 ELSE 0 END
        END 
    AS DECIMAL(18,4)) AS risco_relativo_uf,

    CAST(
        CASE 
            WHEN BR.percentual_exclusividade_br > 0 THEN 
                I.percentual_exclusividade / BR.percentual_exclusividade_br
            ELSE 
                CASE WHEN I.percentual_exclusividade > 0 THEN 99.0 ELSE 0 END
        END 
    AS DECIMAL(18,4)) AS risco_relativo_br,
    
    -- RISCO INVERSO (Dispersão)
    -- Quanto MENOR a dispersão (média de estabelecimentos), MAIOR o risco
    CAST(
        CASE 
            WHEN I.media_estabelecimentos_por_crm > 0 THEN 
                UF.media_dispersao_crm_uf / I.media_estabelecimentos_por_crm
            ELSE 99.0
        END 
    AS DECIMAL(18,4)) AS risco_baixa_dispersao_uf,
    
    CAST(
        CASE 
            WHEN I.media_estabelecimentos_por_crm > 0 THEN 
                BR.media_dispersao_crm_br / I.media_estabelecimentos_por_crm
            ELSE 99.0
        END 
    AS DECIMAL(18,4)) AS risco_baixa_dispersao_br,
    
    -- CLASSIFICAÇÃO DE RISCO
    CASE 
        WHEN I.percentual_exclusividade >= 80 THEN 'MUITO ALTO'
        WHEN I.percentual_exclusividade >= 60 THEN 'ALTO'
        WHEN I.percentual_exclusividade >= 40 THEN 'MODERADO'
        WHEN I.percentual_exclusividade >= 20 THEN 'BAIXO'
        ELSE 'MUITO BAIXO'
    END AS classificacao_exclusividade

INTO temp_CGUSC.fp.indicador_exclusividade_crm_detalhado
FROM temp_CGUSC.fp.indicador_exclusividade_crm I
INNER JOIN temp_CGUSC.fp.dados_farmacia F 
    ON F.cnpj = I.cnpj
LEFT JOIN temp_CGUSC.fp.indicador_exclusividade_crm_uf UF 
    ON CAST(F.uf AS VARCHAR(2)) = UF.uf
CROSS JOIN temp_CGUSC.fp.indicador_exclusividade_crm_br BR;

-- Índices Finais
CREATE CLUSTERED INDEX IDX_FinalExcl_CNPJ ON temp_CGUSC.fp.indicador_exclusividade_crm_detalhado(cnpj);
CREATE NONCLUSTERED INDEX IDX_FinalExcl_Risco ON temp_CGUSC.fp.indicador_exclusividade_crm_detalhado(risco_relativo_uf DESC);
CREATE NONCLUSTERED INDEX IDX_FinalExcl_Percentual ON temp_CGUSC.fp.indicador_exclusividade_crm_detalhado(percentual_exclusividade DESC);
GO

-- ============================================================================
-- VERIFICAÇÕES E ANÁLISES
-- ============================================================================

-- 1. Top 100 farmácias com maior exclusividade
SELECT TOP 100 
    cnpj,
    razaoSocial,
    municipio,
    uf,
    total_prescritores,
    qtd_prescritores_exclusivos,
    percentual_exclusividade,
    percentual_volume_exclusivos,
    classificacao_exclusividade,
    risco_relativo_uf
FROM temp_CGUSC.fp.indicador_exclusividade_crm_detalhado 
ORDER BY percentual_exclusividade DESC;

-- 2. Distribuição por classificação de risco
SELECT 
    classificacao_exclusividade,
    COUNT(*) AS qtd_farmacias,
    AVG(percentual_exclusividade) AS media_exclusividade,
    AVG(total_prescritores) AS media_prescritores,
    AVG(percentual_volume_exclusivos) AS media_volume_exclusivos
FROM temp_CGUSC.fp.indicador_exclusividade_crm_detalhado
GROUP BY classificacao_exclusividade
ORDER BY 
    CASE classificacao_exclusividade
        WHEN 'MUITO ALTO' THEN 1
        WHEN 'ALTO' THEN 2
        WHEN 'MODERADO' THEN 3
        WHEN 'BAIXO' THEN 4
        WHEN 'MUITO BAIXO' THEN 5
    END;

-- 3. Estatísticas por UF
SELECT 
    uf,
    COUNT(*) AS qtd_farmacias,
    AVG(percentual_exclusividade) AS media_exclusividade,
    AVG(media_estabelecimentos_por_crm) AS media_dispersao,
    AVG(percentual_volume_exclusivos) AS media_volume_exclusivos,
    SUM(CASE WHEN percentual_exclusividade >= 80 THEN 1 ELSE 0 END) AS farmacias_risco_muito_alto
FROM temp_CGUSC.fp.indicador_exclusividade_crm_detalhado
GROUP BY uf
ORDER BY media_exclusividade DESC;

-- 4. Correlação entre exclusividade e volume
SELECT 
    CASE 
        WHEN total_prescritores < 10 THEN '< 10 prescritores'
        WHEN total_prescritores < 50 THEN '10-49 prescritores'
        WHEN total_prescritores < 100 THEN '50-99 prescritores'
        ELSE '100+ prescritores'
    END AS faixa_prescritores,
    COUNT(*) AS qtd_farmacias,
    AVG(percentual_exclusividade) AS media_exclusividade,
    AVG(percentual_volume_exclusivos) AS media_volume_exclusivos
FROM temp_CGUSC.fp.indicador_exclusividade_crm_detalhado
GROUP BY 
    CASE 
        WHEN total_prescritores < 10 THEN '< 10 prescritores'
        WHEN total_prescritores < 50 THEN '10-49 prescritores'
        WHEN total_prescritores < 100 THEN '50-99 prescritores'
        ELSE '100+ prescritores'
    END
ORDER BY 
    CASE 
        WHEN MIN(total_prescritores) < 10 THEN 1
        WHEN MIN(total_prescritores) < 50 THEN 2
        WHEN MIN(total_prescritores) < 100 THEN 3
        ELSE 4
    END;

-- 5. Farmácias suspeitas (alta exclusividade + alto volume)
SELECT TOP 50
    cnpj,
    razaoSocial,
    municipio,
    uf,
    total_prescritores,
    qtd_prescritores_exclusivos,
    percentual_exclusividade,
    total_valor_farmacia,
    percentual_volume_exclusivos,
    risco_relativo_uf
FROM temp_CGUSC.fp.indicador_exclusividade_crm_detalhado
WHERE percentual_exclusividade >= 70
  AND total_prescritores >= 20
ORDER BY total_valor_farmacia DESC;

PRINT '============================================================================';
PRINT 'INDICADOR DE EXCLUSIVIDADE DE CRMs CRIADO COM SUCESSO!';
PRINT '============================================================================';
PRINT 'FONTE: relatorio_movimentacao_2021_2024 (FONTE DIRETA)';
PRINT 'PERÍODO: Controlado por @DataInicio e @DataFim';
PRINT '';
PRINT 'TABELAS GERADAS:';
PRINT '  - temp_CGUSC.fp.indicador_exclusividade_crm (base)';
PRINT '  - temp_CGUSC.fp.indicador_exclusividade_crm_uf (médias por estado)';
PRINT '  - temp_CGUSC.fp.indicador_exclusividade_crm_br (médias nacionais)';
PRINT '  - temp_CGUSC.fp.indicador_exclusividade_crm_detalhado (consolidado final)';
PRINT '============================================================================';
GO

