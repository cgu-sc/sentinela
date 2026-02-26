USE [temp_CGUSC]
GO

-- ============================================================================
-- INDICADOR DE PRESCRITORES - ANÁLISE DE CRM POR FARMÁCIA - VERSÃO 2
-- ============================================================================
-- CORREÇÕES APLICADAS:
--   1. Contagem de prescrições usa COUNT(DISTINCT num_autorizacao) em vez de COUNT(*)
--   2. JOIN com tb_analise_crm_farmacia_popular traz TODOS os alertas (1-6)
--   3. Removido filtro restritivo que excluía registros sem alerta5
--   4. NOVO: Tabela final inclui top20 + TODOS os prescritores com alertas
--   5. NOVO: Alerta6 vem da tb_analise_crm_farmacia_popular (não mais calculado inline)
-- ============================================================================

-- ============================================================================
-- DEFINIÇÃO DE VARIÁVEIS
-- ============================================================================
DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim DATE = '2024-12-10';

-- ============================================================================
-- PASSO 1: BASE DE PRESCRITORES POR FARMÁCIA
-- ============================================================================
-- CORREÇÃO: Usar COUNT(DISTINCT num_autorizacao) para contar prescrições únicas
DROP TABLE IF EXISTS #CRMsPorFarmacia;

SELECT 
    cnpj,
    CONCAT(crm, '/', crm_uf) AS id_medico,
    crm AS nu_crm,
    crm_uf AS sg_uf_crm,
    -- ? CORREÇÃO: Contar autorizações únicas, não linhas
    COUNT(DISTINCT num_autorizacao) AS nu_prescricoes,
    SUM(valor_pago) AS vl_total_prescricoes,
    MIN(data_hora) AS dt_primeira_prescricao,
    MAX(data_hora) AS dt_ultima_prescricao,
    DATEDIFF(DAY, MIN(data_hora), MAX(data_hora)) + 1 AS nu_dias_atividade,
    -- ? CORREÇÃO: Usar COUNT(DISTINCT) também no cálculo de prescrições/dia
    CAST(
        CASE 
            WHEN DATEDIFF(DAY, MIN(data_hora), MAX(data_hora)) + 1 > 0 THEN 
                CAST(COUNT(DISTINCT num_autorizacao) AS DECIMAL(18,2)) / 
                CAST(DATEDIFF(DAY, MIN(data_hora), MAX(data_hora)) + 1 AS DECIMAL(18,2))
            ELSE COUNT(DISTINCT num_autorizacao) 
        END 
    AS DECIMAL(18,2)) AS nu_prescricoes_dia
INTO #CRMsPorFarmacia
FROM db_FarmaciaPopular.carga_2024.relatorio_movimentacaoFP_2021_2024
--FROM TESTE_relatorio_movimentacaoFP_2021_2024
WHERE 
    data_hora >= @DataInicio 
    AND data_hora <= @DataFim
    AND crm IS NOT NULL 
    AND crm_uf IS NOT NULL 
    AND crm_uf <> 'BR'
    AND crm > 0
GROUP BY cnpj, crm, crm_uf;

CREATE CLUSTERED INDEX IDX_Presc_CNPJ ON #CRMsPorFarmacia(cnpj);

-- ============================================================================
-- PASSO 2: TOTAIS POR FARMÁCIA (para calcular participação %)
-- ============================================================================
DROP TABLE IF EXISTS #TotaisFarmacia;

SELECT 
    cnpj,
    SUM(nu_prescricoes) AS total_prescricoes_farmacia,
    SUM(vl_total_prescricoes) AS total_valor_farmacia,
    COUNT(DISTINCT id_medico) AS total_prescritores_distintos
INTO #TotaisFarmacia
FROM #CRMsPorFarmacia
GROUP BY cnpj;

CREATE CLUSTERED INDEX IDX_Totais_CNPJ ON #TotaisFarmacia(cnpj);



-- ============================================================================
-- SUBSTITUIR O PASSO 3 INTEIRO NO ARQUIVO crms.sql
-- Procure por "PASSO 3: CÁLCULO DE MÉTRICAS POR FARMÁCIA"
-- e substitua TODO o bloco até o final do "CREATE CLUSTERED INDEX"
-- ============================================================================

-- ============================================================================
-- PASSO 3: CÁLCULO DE MÉTRICAS POR FARMÁCIA (COM DADOS DE REDE) - CORRIGIDO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicadorCRM;

-- ? NOVO: Tabela intermediária com dados de REDE agregados por prescritor
DROP TABLE IF EXISTS #DadosRedePorPrescritor;

SELECT 
    A.nu_cnpj AS cnpj,
    A.id_medico,
    -- Pegar o valor MÁXIMO (que é o total da rede) pois pode haver duplicatas
    MAX(A.nu_prescricoes_dia_em_todos_estabelecimentos) AS nu_prescricoes_dia_em_todos_estabelecimentos,
    MAX(A.nu_estabelecimentos_com_registro_mesmo_crm) AS nu_estabelecimentos_com_registro_mesmo_crm
INTO #DadosRedePorPrescritor
FROM temp_CGUSC.fp.tb_analise_crm_farmacia_popular A
GROUP BY A.nu_cnpj, A.id_medico;

CREATE CLUSTERED INDEX IDX_DadosRede ON #DadosRedePorPrescritor(cnpj, id_medico);

-- Top 5 por farmácia (mantido igual)
DROP TABLE IF EXISTS #Top5PorFarmacia;
WITH RankedPrescritores AS (
    SELECT 
        P.cnpj, P.id_medico, P.vl_total_prescricoes,
        ROW_NUMBER() OVER (PARTITION BY P.cnpj ORDER BY P.vl_total_prescricoes DESC) AS ranking
    FROM #CRMsPorFarmacia P
)
SELECT 
    cnpj,
    MAX(CASE WHEN ranking = 1 THEN id_medico END) AS id_top1,
    MAX(CASE WHEN ranking = 2 THEN id_medico END) AS id_top2,
    MAX(CASE WHEN ranking = 3 THEN id_medico END) AS id_top3,
    MAX(CASE WHEN ranking = 4 THEN id_medico END) AS id_top4,
    MAX(CASE WHEN ranking = 5 THEN id_medico END) AS id_top5,
    SUM(CASE WHEN ranking = 1 THEN vl_total_prescricoes ELSE 0 END) AS valor_top1,
    SUM(CASE WHEN ranking <= 5 THEN vl_total_prescricoes ELSE 0 END) AS valor_top5_acumulado
INTO #Top5PorFarmacia
FROM RankedPrescritores
WHERE ranking <= 5
GROUP BY cnpj;

CREATE CLUSTERED INDEX IDX_Top5_CNPJ ON #Top5PorFarmacia(cnpj);

-- HHI (mantido igual)
DROP TABLE IF EXISTS #HHIPorFarmacia;
SELECT 
    P.cnpj,
    SUM(POWER(CAST(P.vl_total_prescricoes AS DECIMAL(18,4)) / NULLIF(CAST(T.total_valor_farmacia AS DECIMAL(18,4)), 0) * 100.0, 2)) AS indice_hhi
INTO #HHIPorFarmacia
FROM #CRMsPorFarmacia P
INNER JOIN #TotaisFarmacia T ON T.cnpj = P.cnpj
GROUP BY P.cnpj;
CREATE CLUSTERED INDEX IDX_HHI_CNPJ ON #HHIPorFarmacia(cnpj);

-- Robôs Locais (mantido igual)
DROP TABLE IF EXISTS #RobosPorFarmacia;
SELECT cnpj, COUNT(*) AS qtd_prescritores_robos
INTO #RobosPorFarmacia
FROM #CRMsPorFarmacia
WHERE nu_prescricoes_dia > 30
GROUP BY cnpj;
CREATE CLUSTERED INDEX IDX_Robos_CNPJ ON #RobosPorFarmacia(cnpj);

-- CRM Inválido (mantido igual)
DROP TABLE IF EXISTS #CRMInvalidoPorFarmacia;
SELECT P.cnpj, COUNT(*) AS qtd_crm_invalido
INTO #CRMInvalidoPorFarmacia
FROM #CRMsPorFarmacia P
INNER JOIN temp_CGUSC.fp.tb_uf_crm U ON U.uf = P.sg_uf_crm
WHERE P.nu_crm > U.nu_max_crm
GROUP BY P.cnpj;
CREATE CLUSTERED INDEX IDX_CRMInv_CNPJ ON #CRMInvalidoPorFarmacia(cnpj);

-- Turistas (mantido igual)
DROP TABLE IF EXISTS #TuristasPorFarmacia;
SELECT nu_cnpj AS cnpj, COUNT(DISTINCT id_medico) AS qtd_prescritores_turistas
INTO #TuristasPorFarmacia
FROM temp_CGUSC.fp.tb_analise_crm_farmacia_popular
WHERE alerta5 IS NOT NULL AND alerta5 <> ''
GROUP BY nu_cnpj;
CREATE CLUSTERED INDEX IDX_Turistas_CNPJ ON #TuristasPorFarmacia(cnpj);

-- Pareto (mantido igual)
DROP TABLE IF EXISTS #ParetoPorFarmacia;
WITH PrescritoresAcumulado AS (
    SELECT 
        P.cnpj, P.vl_total_prescricoes, T.total_valor_farmacia,
        SUM(P.vl_total_prescricoes) OVER (PARTITION BY P.cnpj ORDER BY P.vl_total_prescricoes DESC) AS acumulado
    FROM #CRMsPorFarmacia P
    INNER JOIN #TotaisFarmacia T ON T.cnpj = P.cnpj
)
SELECT cnpj, COUNT(*) + 1 AS qtd_prescritores_80pct
INTO #ParetoPorFarmacia
FROM PrescritoresAcumulado
WHERE acumulado <= total_valor_farmacia * 0.80
GROUP BY cnpj;
CREATE CLUSTERED INDEX IDX_Pareto_CNPJ ON #ParetoPorFarmacia(cnpj);

-- ? CORREÇÃO: Dados de Rede usando a tabela intermediária
DROP TABLE IF EXISTS #RedePorFarmacia;
SELECT 
    P.cnpj,
    
    -- ? Robô Oculto: Normal aqui (<=30), mas Robô no total (>30)
    COUNT(DISTINCT CASE 
        WHEN P.nu_prescricoes_dia <= 30 
         AND ISNULL(R.nu_prescricoes_dia_em_todos_estabelecimentos, 0) > 30 
        THEN P.id_medico 
    END) AS qtd_prescritores_robos_ocultos,
    
    -- ? Multi-Farmácia: Atua em > 20 estabelecimentos
    COUNT(DISTINCT CASE 
        WHEN ISNULL(R.nu_estabelecimentos_com_registro_mesmo_crm, 1) > 20 
        THEN P.id_medico 
    END) AS qtd_prescritores_multi_farmacia,
    
    -- Índice de Rede: Média de estabelecimentos por prescritor
    AVG(CAST(ISNULL(R.nu_estabelecimentos_com_registro_mesmo_crm, 1) AS DECIMAL(18,4))) AS indice_rede_suspeita,
    
    -- ? Média de prescrições/dia na rede
    AVG(CAST(ISNULL(R.nu_prescricoes_dia_em_todos_estabelecimentos, P.nu_prescricoes_dia) AS DECIMAL(18,4))) AS media_prescricoes_dia_rede

INTO #RedePorFarmacia
FROM #CRMsPorFarmacia P
LEFT JOIN #DadosRedePorPrescritor R 
    ON R.cnpj = P.cnpj AND R.id_medico = P.id_medico
GROUP BY P.cnpj;

CREATE CLUSTERED INDEX IDX_Rede_CNPJ ON #RedePorFarmacia(cnpj);

-- Monta a tabela final indicadorCRM
SELECT 
    T.cnpj,
    T.total_prescricoes_farmacia,
    T.total_valor_farmacia,
    T.total_prescritores_distintos,
    
    ISNULL(CAST(T5.valor_top1 AS DECIMAL(18,2)) / NULLIF(CAST(T.total_valor_farmacia AS DECIMAL(18,2)), 0) * 100.0, 0) AS pct_concentracao_top1,
    ISNULL(T5.id_top1, '') AS id_top1_prescritor,
    ISNULL(CAST(T5.valor_top5_acumulado AS DECIMAL(18,2)) / NULLIF(CAST(T.total_valor_farmacia AS DECIMAL(18,2)), 0) * 100.0, 0) AS pct_concentracao_top5,
    ISNULL(CONCAT(T5.id_top1, ', ', T5.id_top2, ', ', T5.id_top3, ', ', T5.id_top4, ', ', T5.id_top5), '') AS ids_top5_prescritores,
    
    ISNULL(H.indice_hhi, 0) AS indice_hhi,
    ISNULL(R.qtd_prescritores_robos, 0) AS qtd_prescritores_robos,
    ISNULL(C.qtd_crm_invalido, 0) AS qtd_crm_invalido,
    ISNULL(TU.qtd_prescritores_turistas, 0) AS qtd_prescritores_turistas,
    ISNULL(PA.qtd_prescritores_80pct, 1) AS qtd_prescritores_80pct,
    
    -- ? CAMPOS DE REDE CORRIGIDOS
    ISNULL(RE.qtd_prescritores_robos_ocultos, 0) AS qtd_prescritores_robos_ocultos,
    ISNULL(RE.qtd_prescritores_multi_farmacia, 0) AS qtd_prescritores_multi_farmacia,
    ISNULL(RE.indice_rede_suspeita, 1.0) AS indice_rede_suspeita,
    ISNULL(RE.media_prescricoes_dia_rede, 0.0) AS media_prescricoes_dia_rede

INTO temp_CGUSC.fp.indicadorCRM
FROM #TotaisFarmacia T
LEFT JOIN #Top5PorFarmacia T5 ON T5.cnpj = T.cnpj
LEFT JOIN #HHIPorFarmacia H ON H.cnpj = T.cnpj
LEFT JOIN #RobosPorFarmacia R ON R.cnpj = T.cnpj
LEFT JOIN #CRMInvalidoPorFarmacia C ON C.cnpj = T.cnpj
LEFT JOIN #TuristasPorFarmacia TU ON TU.cnpj = T.cnpj
LEFT JOIN #ParetoPorFarmacia PA ON PA.cnpj = T.cnpj
LEFT JOIN #RedePorFarmacia RE ON RE.cnpj = T.cnpj;

CREATE CLUSTERED INDEX IDX_IndPresc_CNPJ ON temp_CGUSC.fp.indicadorCRM(cnpj);

-- ============================================================================
-- PASSO 4: MÉDIAS POR UF
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicadorCRM_UF;

SELECT 
    CAST(F.uf AS VARCHAR(2)) AS uf,
    AVG(pct_concentracao_top1) AS media_concentracao_uf,
    AVG(pct_concentracao_top5) AS media_concentracao_top5_uf,
    AVG(indice_hhi) AS media_hhi_uf,
    AVG(CAST(qtd_prescritores_robos AS DECIMAL(18,4))) AS media_robos_uf,
    AVG(CAST(qtd_crm_invalido AS DECIMAL(18,4))) AS media_crm_invalido_uf,
    AVG(CAST(qtd_prescritores_turistas AS DECIMAL(18,4))) AS media_turistas_uf,
    AVG(CAST(qtd_prescritores_80pct AS DECIMAL(18,4))) AS media_pareto_uf,
    AVG(CAST(total_prescritores_distintos AS DECIMAL(18,4))) AS media_prescritores_uf
    
INTO temp_CGUSC.fp.indicadorCRM_UF
FROM temp_CGUSC.fp.indicadorCRM I
INNER JOIN temp_CGUSC.fp.dadosFarmaciasFP F ON F.cnpj = I.cnpj
GROUP BY CAST(F.uf AS VARCHAR(2));

CREATE CLUSTERED INDEX IDX_IndPrescUF_UF ON temp_CGUSC.fp.indicadorCRM_UF(uf);


-- ============================================================================
-- PASSO 5: MÉDIAS NACIONAIS
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicadorCRM_BR;

SELECT 
    'BR' AS pais,
    AVG(pct_concentracao_top1) AS media_concentracao_br,
    AVG(pct_concentracao_top5) AS media_concentracao_top5_br,
    AVG(indice_hhi) AS media_hhi_br,
    AVG(CAST(qtd_prescritores_robos AS DECIMAL(18,4))) AS media_robos_br,
    AVG(CAST(qtd_crm_invalido AS DECIMAL(18,4))) AS media_crm_invalido_br,
    AVG(CAST(qtd_prescritores_turistas AS DECIMAL(18,4))) AS media_turistas_br,
    AVG(CAST(qtd_prescritores_80pct AS DECIMAL(18,4))) AS media_pareto_br,
    AVG(CAST(total_prescritores_distintos AS DECIMAL(18,4))) AS media_prescritores_br
INTO temp_CGUSC.fp.indicadorCRM_BR
FROM temp_CGUSC.fp.indicadorCRM;


-- ============================================================================
-- PASSO 6: TABELA CONSOLIDADA COM RISCO RELATIVO - VERSÃO CORRIGIDA
-- Procure por "PASSO 6" no arquivo crms.sql e substitua
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicadorCRM_Completo;

SELECT 
    I.cnpj,
    F.razaoSocial,
    F.municipio,
    CAST(F.uf AS VARCHAR(2)) AS uf,
    
    -- Métricas Absolutas
    I.total_prescricoes_farmacia,
    I.total_valor_farmacia,
    I.total_prescritores_distintos,
    I.pct_concentracao_top1,
    I.id_top1_prescritor,
    I.pct_concentracao_top5,
    I.ids_top5_prescritores,
    I.indice_hhi,
    I.qtd_prescritores_robos,
    I.qtd_crm_invalido,
    
    -- % CRM Inválido
    CAST(CASE 
        WHEN I.total_prescritores_distintos > 0 
        THEN (CAST(I.qtd_crm_invalido AS DECIMAL(18,4)) / I.total_prescritores_distintos) * 100.0
        ELSE 0 
    END AS DECIMAL(18,2)) AS pct_crm_invalido,

    I.qtd_prescritores_turistas,
    I.qtd_prescritores_80pct,
    
    -- ? CAMPOS DE REDE (agora vêm diretamente de I)
    I.qtd_prescritores_robos_ocultos,
    I.qtd_prescritores_multi_farmacia,
    
    -- % Multi-Farmácia
    CAST(CASE 
        WHEN I.total_prescritores_distintos > 0 
        THEN (CAST(I.qtd_prescritores_multi_farmacia AS DECIMAL(18,4)) / I.total_prescritores_distintos) * 100.0
        ELSE 0 
    END AS DECIMAL(18,2)) AS pct_prescritores_multi_farmacia,

    I.indice_rede_suspeita,
    
    -- ? NOVO CAMPO: média_prescricoes_dia_rede
    I.media_prescricoes_dia_rede,
    
    -- Médias UF
    ISNULL(UF.media_concentracao_uf, 0) AS media_concentracao_uf,
    ISNULL(UF.media_concentracao_top5_uf, 0) AS media_concentracao_top5_uf,
    ISNULL(UF.media_hhi_uf, 0) AS media_hhi_uf,
    ISNULL(UF.media_robos_uf, 0) AS media_robos_uf,
    ISNULL(UF.media_crm_invalido_uf, 0) AS media_crm_invalido_uf,
    ISNULL(UF.media_turistas_uf, 0) AS media_turistas_uf,
    
    -- Médias BR
    BR.media_concentracao_br,
    BR.media_concentracao_top5_br,
    BR.media_hhi_br,
    BR.media_robos_br,
    BR.media_crm_invalido_br,
    BR.media_turistas_br,
    
    -- Médias de Rede (valores neutros por enquanto - podem ser calculados no Passo 4 se necessário)
    1.0 AS media_indice_rede_uf,
    1.0 AS media_indice_rede_br,
    0.0 AS risco_rede_uf,
    0.0 AS risco_rede_br,

    -- RISCO RELATIVO
    CAST(CASE WHEN UF.media_concentracao_uf > 0 THEN I.pct_concentracao_top1 / UF.media_concentracao_uf ELSE 0 END AS DECIMAL(18,4)) AS risco_concentracao_uf,
    CAST(CASE WHEN BR.media_concentracao_br > 0 THEN I.pct_concentracao_top1 / BR.media_concentracao_br ELSE 0 END AS DECIMAL(18,4)) AS risco_concentracao_br,
    CAST(CASE WHEN UF.media_concentracao_top5_uf > 0 THEN I.pct_concentracao_top5 / UF.media_concentracao_top5_uf ELSE 0 END AS DECIMAL(18,4)) AS risco_concentracao_top5_uf,
    CAST(CASE WHEN BR.media_concentracao_top5_br > 0 THEN I.pct_concentracao_top5 / BR.media_concentracao_top5_br ELSE 0 END AS DECIMAL(18,4)) AS risco_concentracao_top5_br,
    CAST(CASE WHEN UF.media_hhi_uf > 0 THEN I.indice_hhi / UF.media_hhi_uf ELSE 0 END AS DECIMAL(18,4)) AS risco_hhi_uf,
    CAST(CASE WHEN BR.media_hhi_br > 0 THEN I.indice_hhi / BR.media_hhi_br ELSE 0 END AS DECIMAL(18,4)) AS risco_hhi_br,
    
    -- Riscos Robôs e Turistas com suavização
    CAST(CASE WHEN UF.media_robos_uf > 0 THEN (I.qtd_prescritores_robos + 0.001) / (UF.media_robos_uf + 0.001) ELSE CASE WHEN I.qtd_prescritores_robos > 0 THEN 99.0 ELSE 0 END END AS DECIMAL(18,4)) AS risco_robos_uf,
    CAST(CASE WHEN BR.media_robos_br > 0 THEN (I.qtd_prescritores_robos + 0.001) / (BR.media_robos_br + 0.001) ELSE CASE WHEN I.qtd_prescritores_robos > 0 THEN 99.0 ELSE 0 END END AS DECIMAL(18,4)) AS risco_robos_br,
    CAST(CASE WHEN UF.media_crm_invalido_uf > 0 THEN (I.qtd_crm_invalido + 0.001) / (UF.media_crm_invalido_uf + 0.001) ELSE CASE WHEN I.qtd_crm_invalido > 0 THEN 99.0 ELSE 0 END END AS DECIMAL(18,4)) AS risco_crm_invalido_uf,
    CAST(CASE WHEN BR.media_crm_invalido_br > 0 THEN (I.qtd_crm_invalido + 0.001) / (BR.media_crm_invalido_br + 0.001) ELSE CASE WHEN I.qtd_crm_invalido > 0 THEN 99.0 ELSE 0 END END AS DECIMAL(18,4)) AS risco_crm_invalido_br,
    CAST(CASE WHEN UF.media_turistas_uf > 0 THEN (I.qtd_prescritores_turistas + 0.001) / (UF.media_turistas_uf + 0.001) ELSE CASE WHEN I.qtd_prescritores_turistas > 0 THEN 99.0 ELSE 0 END END AS DECIMAL(18,4)) AS risco_turistas_uf,
    CAST(CASE WHEN BR.media_turistas_br > 0 THEN (I.qtd_prescritores_turistas + 0.001) / (BR.media_turistas_br + 0.001) ELSE CASE WHEN I.qtd_prescritores_turistas > 0 THEN 99.0 ELSE 0 END END AS DECIMAL(18,4)) AS risco_turistas_br,
    
    -- Score de Prescritores
    CAST((
        CASE WHEN UF.media_hhi_uf > 0 THEN I.indice_hhi / UF.media_hhi_uf ELSE 0 END +
        CASE WHEN I.qtd_prescritores_robos > 0 THEN 5.0 ELSE 0 END +
        CASE WHEN I.qtd_crm_invalido > 0 THEN 10.0 ELSE 0 END +
        CASE WHEN I.qtd_prescritores_turistas > 0 THEN 5.0 ELSE 0 END
    ) / 4.0 AS DECIMAL(18,4)) AS score_prescritores

INTO temp_CGUSC.fp.indicadorCRM_Completo
FROM temp_CGUSC.fp.indicadorCRM I
INNER JOIN temp_CGUSC.fp.dadosFarmaciasFP F ON F.cnpj = I.cnpj
LEFT JOIN temp_CGUSC.fp.indicadorCRM_UF UF ON CAST(F.uf AS VARCHAR(2)) = UF.uf
CROSS JOIN temp_CGUSC.fp.indicadorCRM_BR BR;

CREATE CLUSTERED INDEX IDX_FinalPresc_CNPJ ON temp_CGUSC.fp.indicadorCRM_Completo(cnpj);
CREATE NONCLUSTERED INDEX IDX_FinalPresc_Score ON temp_CGUSC.fp.indicadorCRM_Completo(score_prescritores DESC);
GO


-- ============================================================================
-- PASSO 7: TABELA DE CRMs DE INTERESSE POR FARMÁCIA (TOP 20 + ALERTAS)
-- ============================================================================
-- ? CORREÇÃO PRINCIPAL v2: 
--    - Trazer TODOS os alertas (1-6)
--    - Incluir top20 por volume + TODOS os prescritores com qualquer alerta
--    - Alerta6 agora vem da tb_analise_crm_farmacia_popular
--    - Inclui dt_inscricao_crm e flag_prescricao_antes_registro

DROP TABLE IF EXISTS temp_CGUSC.fp.top20CRMsPorFarmacia;

WITH CRMsRankeados AS (
    SELECT 
        P.cnpj,
        P.id_medico,
        P.nu_crm,
        P.sg_uf_crm,
        P.nu_prescricoes,
        P.vl_total_prescricoes,
        P.dt_primeira_prescricao,
        P.dt_ultima_prescricao,
        P.nu_prescricoes_dia,
        
        -- Participação %
        CAST(P.vl_total_prescricoes AS DECIMAL(18,4)) / 
            NULLIF(CAST(T.total_valor_farmacia AS DECIMAL(18,4)), 0) * 100.0 AS pct_participacao,
        
        -- % Acumulado
        SUM(CAST(P.vl_total_prescricoes AS DECIMAL(18,4))) OVER (
            PARTITION BY P.cnpj ORDER BY P.vl_total_prescricoes DESC
        ) / NULLIF(CAST(T.total_valor_farmacia AS DECIMAL(18,4)), 0) * 100.0 AS pct_acumulado,
        
        -- Ranking
        ROW_NUMBER() OVER (PARTITION BY P.cnpj ORDER BY P.vl_total_prescricoes DESC) AS ranking,
        
        -- Flag CRM Inválido (verifica se existe na base do CFM)
        CASE WHEN CFM.NU_CRM IS NULL THEN 1 ELSE 0 END AS flag_crm_invalido,
        
        -- Flag Robô (>30 prescrições/dia neste estabelecimento)
        CASE WHEN P.nu_prescricoes_dia > 30 THEN 1 ELSE 0 END AS flag_robo,
        
        -- ? Dados da rede (total Brasil)
        ISNULL(A.nu_prescricoes_medico_em_todos_estabelecimentos, P.nu_prescricoes) AS prescricoes_total_brasil,
        ISNULL(A.nu_prescricoes_dia_em_todos_estabelecimentos, P.nu_prescricoes_dia) AS prescricoes_dia_total_brasil,
        ISNULL(A.nu_estabelecimentos_com_registro_mesmo_crm, 1) AS qtd_estabelecimentos_atua,
        
        -- % do volume aqui vs total
        CASE 
            WHEN ISNULL(A.nu_prescricoes_medico_em_todos_estabelecimentos, 0) > 0 
            THEN CAST(P.nu_prescricoes AS DECIMAL(18,4)) / 
                 CAST(A.nu_prescricoes_medico_em_todos_estabelecimentos AS DECIMAL(18,4)) * 100.0
            ELSE 100.0
        END AS pct_volume_aqui_vs_total,
        
        -- Flag Robô Oculto (parece normal aqui, mas >30/dia no total Brasil)
        CASE 
            WHEN ISNULL(A.nu_prescricoes_dia_em_todos_estabelecimentos, 0) > 30 
            THEN 1 
            ELSE 0 
        END AS flag_robo_oculto,
        
        -- Flag Multi-Farmácia (>20 estabelecimentos)
        CASE 
            WHEN ISNULL(A.nu_estabelecimentos_com_registro_mesmo_crm, 1) > 20 
            THEN 1 
            ELSE 0 
        END AS flag_multi_farmacia,
        
        -- ? NOVO: Data de inscrição do CRM (da tabela CFM)
        CFM.dt_inscricao_convertida AS dt_inscricao_crm,
        
        -- ? NOVO: Flag para prescrição antes do registro do CRM
        CASE 
            WHEN CFM.dt_inscricao_convertida IS NOT NULL 
             AND P.dt_primeira_prescricao < CFM.dt_inscricao_convertida 
            THEN 1 
            ELSE 0 
        END AS flag_prescricao_antes_registro,
        
        -- ? CORREÇÃO: Trazer TODOS os alertas (incluindo alerta6)
        ISNULL(A.alerta1, '') AS alerta1_crm_invalido,
        ISNULL(A.alerta2, '') AS alerta2_tempo_concentrado,
        ISNULL(A.alerta3, '') AS alerta3_robo_estabelecimento,
        ISNULL(A.alerta4, '') AS alerta4_robo_rede,
        ISNULL(A.alerta5, '') AS alerta5_geografico,
        ISNULL(A.alerta6, '') AS alerta6_prescricao_antes_registro
        
    FROM #CRMsPorFarmacia P
    INNER JOIN #TotaisFarmacia T ON T.cnpj = P.cnpj
    -- ? JOIN sem filtro restritivo - traz TODOS os registros
    LEFT JOIN (
        SELECT 
            nu_cnpj, 
            id_medico,
            nu_prescricoes_medico_em_todos_estabelecimentos,
            nu_prescricoes_dia_em_todos_estabelecimentos,
            nu_estabelecimentos_com_registro_mesmo_crm,
            MAX(alerta1) AS alerta1,
            MAX(alerta2) AS alerta2,
            MAX(alerta3) AS alerta3,
            MAX(alerta4) AS alerta4,
            MAX(alerta5) AS alerta5,
            MAX(alerta6) AS alerta6
        FROM temp_CGUSC.fp.tb_analise_crm_farmacia_popular
        GROUP BY nu_cnpj, id_medico, 
                 nu_prescricoes_medico_em_todos_estabelecimentos,
                 nu_prescricoes_dia_em_todos_estabelecimentos,
                 nu_estabelecimentos_com_registro_mesmo_crm
    ) A ON A.nu_cnpj = P.cnpj AND A.id_medico = P.id_medico
    -- ? JOIN com tabela do CFM para verificar existência e obter data de inscrição
    LEFT JOIN (
        SELECT 
            NU_CRM,
            SG_UF,
            TRY_CONVERT(DATE, DT_INSCRICAO, 103) AS dt_inscricao_convertida
        FROM temp_CFM.fp.medicos_jul_2025_mod
    ) CFM ON CFM.NU_CRM = CAST(P.nu_crm AS VARCHAR(25)) AND CFM.SG_UF = P.sg_uf_crm
)

-- ? CORREÇÃO PRINCIPAL: top20 por volume OU qualquer prescritor com alerta
SELECT *
INTO temp_CGUSC.fp.top20CRMsPorFarmacia
FROM CRMsRankeados
WHERE ranking <= 20
   OR alerta1_crm_invalido <> ''
   OR alerta2_tempo_concentrado <> ''
   OR alerta3_robo_estabelecimento <> ''
   OR alerta4_robo_rede <> ''
   OR alerta5_geografico <> ''
   OR alerta6_prescricao_antes_registro <> '';

CREATE CLUSTERED INDEX IDX_Top20_CNPJ ON temp_CGUSC.fp.top20CRMsPorFarmacia(cnpj, ranking);


-- ============================================================================
-- VERIFICAÇÃO
-- ============================================================================
SELECT TOP 100 * FROM temp_CGUSC.fp.top20CRMsPorFarmacia ORDER BY cnpj, ranking;

-- ? NOVO: Verificar quantos prescritores entraram por alerta (fora do top20)
SELECT 
    'Total de registros' AS metrica,
    COUNT(*) AS valor
FROM temp_CGUSC.fp.top20CRMsPorFarmacia
UNION ALL
SELECT 
    'Registros no top20' AS metrica,
    COUNT(*) AS valor
FROM temp_CGUSC.fp.top20CRMsPorFarmacia
WHERE ranking <= 20
UNION ALL
SELECT 
    'Registros FORA do top20 (só por alerta)' AS metrica,
    COUNT(*) AS valor
FROM temp_CGUSC.fp.top20CRMsPorFarmacia
WHERE ranking > 20;

PRINT '============================================================================';
PRINT 'SCRIPT EXECUTADO COM SUCESSO - CORREÇÕES APLICADAS:';
PRINT '  1. Prescrições contadas por COUNT(DISTINCT num_autorizacao)';
PRINT '  2. Todos os alertas (1-6) incluídos na tabela top20CRMsPorFarmacia';
PRINT '  3. Dados de rede (total Brasil) incluídos para cada prescritor';
PRINT '  4. Flags de robô oculto e multi-farmácia calculados';
PRINT '  5. NOVO: Tabela inclui top20 + TODOS prescritores com alertas';
PRINT '  6. NOVO: Alerta6 (prescrição antes do registro) vem da tabela de análise';
PRINT '  7. NOVO: dt_inscricao_crm e flag_prescricao_antes_registro incluídos';
PRINT '============================================================================';
GO


-- ============================================================================
-- LIMPEZA
-- ============================================================================
DROP TABLE IF EXISTS #CRMsPorFarmacia;
DROP TABLE IF EXISTS #TotaisFarmacia;
DROP TABLE IF EXISTS #Top5PorFarmacia;
DROP TABLE IF EXISTS #HHIPorFarmacia;
DROP TABLE IF EXISTS #RobosPorFarmacia;
DROP TABLE IF EXISTS #CRMInvalidoPorFarmacia;
DROP TABLE IF EXISTS #TuristasPorFarmacia;
DROP TABLE IF EXISTS #ParetoPorFarmacia;


-- ============================================================================
-- VERIFICAÇÃO FINAL
-- ============================================================================
SELECT TOP 100 * FROM temp_CGUSC.fp.indicadorCRM_Completo ORDER BY score_prescritores DESC;
SELECT TOP 50 * FROM temp_CGUSC.fp.top20CRMsPorFarmacia WHERE cnpj = (SELECT TOP 1 cnpj FROM temp_CGUSC.fp.indicadorCRM_Completo ORDER BY score_prescritores DESC);
