USE [temp_CGUSC]
GO

-- ============================================================================
-- INDICADOR DE PRESCRITORES - ANÁLISE DE CRM POR FARMÁCIA - VERSÃO 2
-- ============================================================================
-- CORREÇÕES APLICADAS:
--   1. Contagem de prescrições usa COUNT(DISTINCT num_autorizacao) em vez de COUNT(*)
--   2. JOIN com indicador_crm_detalhado traz TODOS os alertas (1-6)
--   3. Removido filtro restritivo que excluía registros sem alerta5
--   4. NOVO: Tabela final inclui top20 + TODOS os prescritores com alertas
--   5. NOVO: Alerta6 vem da indicador_crm_detalhado (não mais calculado inline)
-- ============================================================================

-- ============================================================================
-- DEFINIÇÃO DE VARIÁVEIS
-- ============================================================================
DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim DATE = '2024-12-10';

-- ============================================================================
-- ============================================================================
-- PASSO 0: AGREGAÇÃO POR MÉDICO/FARMÁCIA (OTIMIZADA)
-- ============================================================================
-- Agregamos cada base separadamente aplicando o filtro de data antes da união.

-- A. Agregação Base Histórica (2015-2020)
DROP TABLE IF EXISTS #CRMs_Hist;
SELECT 
    cnpj, crm, crm_uf,
    COUNT(DISTINCT num_autorizacao) AS nu_prescricoes,
    SUM(valor_pago) AS vl_total,
    MIN(data_hora) AS dt_ini,
    MAX(data_hora) AS dt_fim
INTO #CRMs_Hist
FROM db_FarmaciaPopular.dbo.Relatorio_movimentacaoFP
WHERE data_hora >= @DataInicio AND data_hora <= @DataFim
  AND crm IS NOT NULL AND crm_uf IS NOT NULL AND crm_uf <> 'BR'
GROUP BY cnpj, crm, crm_uf;

-- B. Agregação Base Recente (2021-2024)
DROP TABLE IF EXISTS #CRMs_Recente;
SELECT 
    cnpj, crm, crm_uf,
    COUNT(DISTINCT num_autorizacao) AS nu_prescricoes,
    SUM(valor_pago) AS vl_total,
    MIN(data_hora) AS dt_ini,
    MAX(data_hora) AS dt_fim
INTO #CRMs_Recente
FROM db_FarmaciaPopular.carga_2024.relatorio_movimentacaoFP_2021_2024
WHERE data_hora >= @DataInicio AND data_hora <= @DataFim
  AND crm IS NOT NULL AND crm_uf IS NOT NULL AND crm_uf <> 'BR'
GROUP BY cnpj, crm, crm_uf;

-- C. Consolidação Final
DROP TABLE IF EXISTS #CRMsPorFarmacia;
SELECT 
    cnpj,
    CONCAT(crm, '/', crm_uf) AS id_medico,
    crm AS nu_crm,
    crm_uf AS sg_uf_crm,
    SUM(nu_prescricoes) AS nu_prescricoes,
    SUM(vl_total) AS vl_total_prescricoes,
    MIN(dt_ini) AS dt_primeira_prescricao,
    MAX(dt_fim) AS dt_ultima_prescricao,
    CAST(
        CAST(SUM(nu_prescricoes) AS DECIMAL(18,2)) /
        CAST(DATEDIFF(DAY, MIN(dt_ini), MAX(dt_fim)) + 1 AS DECIMAL(18,2))
    AS DECIMAL(18,2)) AS nu_prescricoes_dia
INTO #CRMsPorFarmacia
FROM (
    SELECT * FROM #CRMs_Hist
    UNION ALL
    SELECT * FROM #CRMs_Recente
) U
GROUP BY cnpj, crm, crm_uf;

CREATE CLUSTERED INDEX IDX_Presc_CNPJ ON #CRMsPorFarmacia(cnpj);

-- ============================================================================
-- PASSO 1: TOTAIS POR FARMÁCIA (para calcular participação %)
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
-- PASSO 3: CÁLCULO DE MÉTRICAS POR FARMÁCIA (COM DADOS DE REDE)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crm;

--NOVO: Tabela intermediária com dados de REDE agregados por prescritor
DROP TABLE IF EXISTS #DadosRedePorPrescritor;

SELECT
    A.id_medico,
    MAX(A.nu_prescricoes_dia_em_todos_estabelecimentos) AS nu_prescricoes_dia_em_todos_estabelecimentos,
    MAX(A.nu_estabelecimentos_com_registro_mesmo_crm) AS nu_estabelecimentos_com_registro_mesmo_crm
INTO #DadosRedePorPrescritor
FROM temp_CGUSC.fp.dados_crm_detalhado A
GROUP BY A.id_medico;

CREATE CLUSTERED INDEX IDX_DadosRede ON #DadosRedePorPrescritor(id_medico);

-- Top 5 por farmácia (mantido igual)
DROP TABLE IF EXISTS #Top5PorFarmacia;
WITH RankedPrescritores AS ( SELECT P.cnpj AS cnpj, P.id_medico, P.vl_total_prescricoes,
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
    P.cnpj AS cnpj,
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

-- CRM Inválido (Atualizado para utilizar a base oficial do CFM)
DROP TABLE IF EXISTS #CRMInvalidoPorFarmacia;
SELECT P.cnpj AS cnpj, 
       COUNT(*) AS qtd_crm_invalido,
       SUM(P.vl_total_prescricoes) AS vl_crm_invalido
INTO #CRMInvalidoPorFarmacia
FROM #CRMsPorFarmacia P
WHERE NOT EXISTS (
    SELECT 1 
    FROM temp_CFM.dbo.medicos_jul_2025_mod CFM
    WHERE TRY_CAST(CFM.NU_CRM AS BIGINT) = TRY_CAST(P.nu_crm AS BIGINT) 
      AND CFM.SG_uf = P.sg_uf_crm
) AND P.nu_prescricoes >= 5
GROUP BY P.cnpj;
CREATE CLUSTERED INDEX IDX_CRMInv_CNPJ ON #CRMInvalidoPorFarmacia(cnpj);

-- Vendas antes do Registro no CFM
DROP TABLE IF EXISTS #CRMAntesRegistroPorFarmacia;
SELECT P.cnpj AS cnpj, 
       COUNT(*) AS qtd_crm_antes_registro,
       SUM(P.vl_total_prescricoes) AS vl_crm_antes_registro
INTO #CRMAntesRegistroPorFarmacia
FROM #CRMsPorFarmacia P
INNER JOIN (
    SELECT NU_CRM, SG_uf, TRY_CONVERT(DATE, DT_INSCRICAO, 103) AS dt_inscricao
    FROM temp_CFM.dbo.medicos_jul_2025_mod
    WHERE DT_INSCRICAO IS NOT NULL AND DT_INSCRICAO <> ''
) CFM ON TRY_CAST(CFM.NU_CRM AS BIGINT) = TRY_CAST(P.nu_crm AS BIGINT)
      AND CFM.SG_uf = P.sg_uf_crm
WHERE CFM.dt_inscricao IS NOT NULL
  AND P.dt_primeira_prescricao < CFM.dt_inscricao
  AND P.nu_prescricoes >= 5
GROUP BY P.cnpj;
CREATE CLUSTERED INDEX IDX_CRMAntesReg_CNPJ ON #CRMAntesRegistroPorFarmacia(cnpj);

-- Turistas (mantido igual)
DROP TABLE IF EXISTS #TuristasPorFarmacia;
SELECT nu_cnpj AS cnpj, COUNT(DISTINCT id_medico) AS qtd_prescritores_turistas
INTO #TuristasPorFarmacia
FROM temp_CGUSC.fp.dados_crm_detalhado
WHERE alerta5 IS NOT NULL AND alerta5 <> ''
GROUP BY nu_cnpj;
CREATE CLUSTERED INDEX IDX_Turistas_CNPJ ON #TuristasPorFarmacia(cnpj);

-- Pareto (CORRIGIDO: acumulado inclusivo, condição pré-cruzamento, sem +1)
DROP TABLE IF EXISTS #ParetoPorFarmacia;
WITH PrescritoresAcumulado AS (
    SELECT 
        P.cnpj AS cnpj, P.vl_total_prescricoes, T.total_valor_farmacia,
        SUM(P.vl_total_prescricoes) OVER (
            PARTITION BY P.cnpj
            ORDER BY P.vl_total_prescricoes DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS acumulado
    FROM #CRMsPorFarmacia P
    INNER JOIN #TotaisFarmacia T ON T.cnpj = P.cnpj
)
-- Conta prescritores cuja contribuicao ainda nao havia cruzado 80% antes desta linha
-- (acumulado - vl_atual) = acumulado antes de incluir o prescritor atual
SELECT cnpj, COUNT(*) AS qtd_prescritores_80pct
INTO #ParetoPorFarmacia
FROM PrescritoresAcumulado
WHERE acumulado - vl_total_prescricoes < total_valor_farmacia * 0.80
GROUP BY cnpj;
CREATE CLUSTERED INDEX IDX_Pareto_CNPJ ON #ParetoPorFarmacia(cnpj);

--CORREÇÃO: Dados de Rede usando a tabela intermediária
DROP TABLE IF EXISTS #RedePorFarmacia;
SELECT 
    P.cnpj AS cnpj,
    
    --Robô Oculto: Normal aqui (<=30), mas Robô no total (>30)
    COUNT(DISTINCT CASE 
        WHEN P.nu_prescricoes_dia <= 30 
         AND ISNULL(R.nu_prescricoes_dia_em_todos_estabelecimentos, 0) > 30 
        THEN P.id_medico 
    END) AS qtd_prescritores_robos_ocultos,
    
    --Multi-Farmácia: Atua em > 70 estabelecimentos
    COUNT(DISTINCT CASE 
        WHEN ISNULL(R.nu_estabelecimentos_com_registro_mesmo_crm, 1) > 70 
        THEN P.id_medico 
    END) AS qtd_prescritores_multi_farmacia,
    
    -- Índice de Rede: Média de estabelecimentos por prescritor
    AVG(CAST(ISNULL(R.nu_estabelecimentos_com_registro_mesmo_crm, 1) AS DECIMAL(18,4))) AS indice_rede_suspeita

INTO #RedePorFarmacia
FROM #CRMsPorFarmacia P
LEFT JOIN #DadosRedePorPrescritor R
    ON R.id_medico = P.id_medico
GROUP BY P.cnpj;

CREATE CLUSTERED INDEX IDX_Rede_CNPJ ON #RedePorFarmacia(cnpj);

-- Monta a tabela final indicador_crm
SELECT T.cnpj AS nu_cnpj,
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
    ISNULL(C.vl_crm_invalido, 0) AS vl_crm_invalido,
    ISNULL(CAST(C.vl_crm_invalido AS DECIMAL(18,2)) / NULLIF(CAST(T.total_valor_farmacia AS DECIMAL(18,2)), 0) * 100.0, 0) AS pct_valor_crm_invalido,
    ISNULL(AR.qtd_crm_antes_registro, 0) AS qtd_crm_antes_registro,
    ISNULL(AR.vl_crm_antes_registro, 0) AS vl_crm_antes_registro,
    ISNULL(CAST(AR.vl_crm_antes_registro AS DECIMAL(18,2)) / NULLIF(CAST(T.total_valor_farmacia AS DECIMAL(18,2)), 0) * 100.0, 0) AS pct_valor_crm_antes_registro,
    ISNULL(TU.qtd_prescritores_turistas, 0) AS qtd_prescritores_turistas,
    ISNULL(PA.qtd_prescritores_80pct, 1) AS qtd_prescritores_80pct,
    
    --CAMPOS DE REDE CORRIGIDOS
    ISNULL(RE.qtd_prescritores_robos_ocultos, 0) AS qtd_prescritores_robos_ocultos,
    ISNULL(RE.qtd_prescritores_multi_farmacia, 0) AS qtd_prescritores_multi_farmacia,
    ISNULL(RE.indice_rede_suspeita, 1.0) AS indice_rede_suspeita

INTO temp_CGUSC.fp.indicador_crm
FROM #TotaisFarmacia T
LEFT JOIN #Top5PorFarmacia T5 ON T5.cnpj = T.cnpj
LEFT JOIN #HHIPorFarmacia H ON H.cnpj = T.cnpj
LEFT JOIN #RobosPorFarmacia R ON R.cnpj = T.cnpj
LEFT JOIN #CRMInvalidoPorFarmacia C ON C.cnpj = T.cnpj
LEFT JOIN #CRMAntesRegistroPorFarmacia AR ON AR.cnpj = T.cnpj
LEFT JOIN #TuristasPorFarmacia TU ON TU.cnpj = T.cnpj
LEFT JOIN #ParetoPorFarmacia PA ON PA.cnpj = T.cnpj
LEFT JOIN #RedePorFarmacia RE ON RE.cnpj = T.cnpj;

CREATE CLUSTERED INDEX IDX_IndPresc_CNPJ ON temp_CGUSC.fp.indicador_crm(nu_cnpj);



-- ============================================================================
-- PASSO 3.5: MEDIANAS POR MUNICÍPIO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crm_mun;

WITH CTE_Mediana_Mun AS (
    SELECT DISTINCT
        CAST(F.uf AS VARCHAR(2)) AS uf,
        CAST(F.municipio AS VARCHAR(255)) AS municipio,
        CAST(
            PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.indice_hhi)
            OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255)))
        AS DECIMAL(18,2)) AS mediana_hhi_mun
    FROM temp_CGUSC.fp.indicador_crm I
    INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.nu_cnpj
)
SELECT uf, municipio, mediana_hhi_mun
INTO temp_CGUSC.fp.indicador_crm_mun
FROM CTE_Mediana_Mun;

CREATE CLUSTERED INDEX IDX_IndPrescMun_loc ON temp_CGUSC.fp.indicador_crm_mun(uf, municipio);


-- ============================================================================
-- PASSO 4: MEDIANAS POR UF
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crm_uf;

WITH CTE_Medians_UF AS (
    SELECT DISTINCT
        CAST(F.uf AS VARCHAR(2)) AS uf,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(pct_concentracao_top1, 0)) OVER (PARTITION BY CAST(F.uf AS VARCHAR(2))) AS mediana_concentracao_uf,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(pct_concentracao_top5, 0)) OVER (PARTITION BY CAST(F.uf AS VARCHAR(2))) AS mediana_concentracao_top5_uf,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(indice_hhi, 0)) OVER (PARTITION BY CAST(F.uf AS VARCHAR(2))) AS mediana_hhi_uf,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(qtd_prescritores_robos, 0)) OVER (PARTITION BY CAST(F.uf AS VARCHAR(2))) AS mediana_robos_uf,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(CAST(CASE WHEN total_prescritores_distintos > 0 THEN (I.qtd_crm_invalido * 100.0 / I.total_prescritores_distintos) ELSE 0 END AS DECIMAL(18,4)), 0)) OVER (PARTITION BY CAST(F.uf AS VARCHAR(2))) AS mediana_pct_crm_invalido_uf,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(qtd_prescritores_turistas, 0)) OVER (PARTITION BY CAST(F.uf AS VARCHAR(2))) AS mediana_turistas_uf,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(indice_rede_suspeita, 0)) OVER (PARTITION BY CAST(F.uf AS VARCHAR(2))) AS mediana_indice_rede_uf
    FROM temp_CGUSC.fp.indicador_crm I
    INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.nu_cnpj
)
SELECT *
INTO temp_CGUSC.fp.indicador_crm_uf
FROM CTE_Medians_UF;

CREATE CLUSTERED INDEX IDX_IndPrescUF_uf ON temp_CGUSC.fp.indicador_crm_uf(uf);


-- ============================================================================
-- PASSO 4B: MEDIANAS POR REGIÃO DE SAÚDE
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crm_regiao;

WITH CTE_Mediana_Reg AS (
    SELECT DISTINCT
        F.id_regiao_saude,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.indice_hhi, 0)) OVER (PARTITION BY F.id_regiao_saude) AS mediana_hhi_reg,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.pct_concentracao_top1, 0)) OVER (PARTITION BY F.id_regiao_saude) AS mediana_concentracao_reg,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.pct_concentracao_top5, 0)) OVER (PARTITION BY F.id_regiao_saude) AS mediana_concentracao_top5_reg,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(CAST(CASE WHEN I.total_prescritores_distintos > 0 THEN (I.qtd_crm_invalido * 100.0 / I.total_prescritores_distintos) ELSE 0 END AS DECIMAL(18,4)), 0)) OVER (PARTITION BY F.id_regiao_saude) AS mediana_crm_invalido_reg,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(qtd_prescritores_robos, 0)) OVER (PARTITION BY F.id_regiao_saude) AS mediana_robos_reg,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(qtd_prescritores_turistas, 0)) OVER (PARTITION BY F.id_regiao_saude) AS mediana_turistas_reg,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(indice_rede_suspeita, 0)) OVER (PARTITION BY F.id_regiao_saude) AS mediana_indice_rede_reg
    FROM temp_CGUSC.fp.dados_farmacia F
    LEFT JOIN temp_CGUSC.fp.indicador_crm I ON I.nu_cnpj = F.cnpj
    WHERE F.id_regiao_saude IS NOT NULL
)
SELECT * INTO temp_CGUSC.fp.indicador_crm_regiao FROM CTE_Mediana_Reg;

CREATE CLUSTERED INDEX IDX_IndCrmReg ON temp_CGUSC.fp.indicador_crm_regiao(id_regiao_saude);



-- ============================================================================
-- PASSO 5: MEDIANAS NACIONAIS
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crm_br;

WITH CTE_Mediana_BR AS (
    SELECT DISTINCT
        CAST('BR' AS VARCHAR(2)) AS pais,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(pct_concentracao_top1, 0)) OVER () AS mediana_concentracao_br,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(pct_concentracao_top5, 0)) OVER () AS mediana_concentracao_top5_br,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(indice_hhi, 0)) OVER () AS mediana_hhi_br,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(qtd_prescritores_robos, 0)) OVER () AS mediana_robos_br,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(CAST(CASE WHEN total_prescritores_distintos > 0 THEN (I.qtd_crm_invalido * 100.0 / I.total_prescritores_distintos) ELSE 0 END AS DECIMAL(18,4)), 0)) OVER () AS mediana_pct_crm_invalido_br,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(qtd_prescritores_turistas, 0)) OVER () AS mediana_turistas_br,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(indice_rede_suspeita, 0)) OVER () AS mediana_indice_rede_br
    FROM temp_CGUSC.fp.indicador_crm I
)
SELECT * INTO temp_CGUSC.fp.indicador_crm_br FROM CTE_Mediana_BR;

-- ============================================================================
-- PASSO 6: TABELA CONSOLIDADA (SUMMARY) indicador_crm_detalhado
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crm_detalhado;

SELECT 
    I.nu_cnpj,
    F.razaoSocial,
    F.municipio,
    CAST(F.uf AS VARCHAR(2)) AS uf,
    F.no_regiao_saude,
    F.id_regiao_saude,
    
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
    I.vl_crm_invalido,
    I.pct_valor_crm_invalido,
    I.qtd_crm_antes_registro,
    I.vl_crm_antes_registro,
    I.pct_valor_crm_antes_registro,
    
    -- Rankings (pior risco = posicao 1)
    RANK() OVER (ORDER BY ISNULL(I.indice_hhi, 0) DESC) AS ranking_br,
    RANK() OVER (PARTITION BY F.uf ORDER BY ISNULL(I.indice_hhi, 0) DESC) AS ranking_uf,
    RANK() OVER (PARTITION BY F.id_regiao_saude ORDER BY ISNULL(I.indice_hhi, 0) DESC) AS ranking_regiao_saude,
    RANK() OVER (PARTITION BY F.uf, F.municipio ORDER BY ISNULL(I.indice_hhi, 0) DESC) AS ranking_municipio,

    -- % CRM Inválido
    CAST(CASE 
        WHEN I.total_prescritores_distintos > 0 
        THEN (CAST(I.qtd_crm_invalido AS DECIMAL(18,4)) / I.total_prescritores_distintos) * 100.0
        ELSE 0 
    END AS DECIMAL(18,2)) AS pct_crm_invalido,

    I.qtd_prescritores_turistas,
    I.qtd_prescritores_80pct,
    
    -- Campos de Rede
    I.qtd_prescritores_robos_ocultos,
    I.qtd_prescritores_multi_farmacia,
    
    CAST(CASE 
        WHEN I.total_prescritores_distintos > 0 
        THEN (CAST(I.qtd_prescritores_multi_farmacia AS DECIMAL(18,4)) / I.total_prescritores_distintos) * 100.0
        ELSE 0 
    END AS DECIMAL(18,2)) AS pct_prescritores_multi_farmacia,

    I.indice_rede_suspeita,
    
    -- Mediana Municipal
    ISNULL(MUN.mediana_hhi_mun, 0) AS mediana_hhi_mun,

    -- Benchmarks Regionais (Regiao de Saude)
    ISNULL(REG.mediana_hhi_reg, 0) AS regiao_saude_mediana,
    CAST((ISNULL(I.indice_hhi, 0) + 0.01) / (ISNULL(REG.mediana_hhi_reg, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_reg_mediana,

    -- Benchmarks Estaduais (Base Mediana)
    ISNULL(UF.mediana_hhi_uf, 0) AS estado_mediana,
    CAST(CASE WHEN UF.mediana_hhi_uf > 0 THEN (I.indice_hhi + 0.01) / (UF.mediana_hhi_uf + 0.01) ELSE 0 END AS DECIMAL(18,4)) AS risco_relativo_uf_mediana,
    
    -- Benchmarks BR (Base Mediana)
    BR.mediana_hhi_br AS pais_mediana,
    CAST(CASE WHEN BR.mediana_hhi_br > 0 THEN (I.indice_hhi + 0.01) / (BR.mediana_hhi_br + 0.01) ELSE 0 END AS DECIMAL(18,4)) AS risco_relativo_br_mediana,
    
    -- EXPORTAÇÃO DAS MEDIANAS PARA O RELATÓRIO (Python)
    ISNULL(REG.mediana_concentracao_reg, 0) AS mediana_concentracao_reg,
    UF.mediana_concentracao_uf AS mediana_concentracao_uf,
    BR.mediana_concentracao_br AS mediana_concentracao_br,
    ISNULL(REG.mediana_concentracao_top5_reg, 0) AS mediana_concentracao_top5_reg,
    UF.mediana_concentracao_top5_uf AS mediana_concentracao_top5_uf,
    BR.mediana_concentracao_top5_br AS mediana_concentracao_top5_br,
    ISNULL(REG.mediana_hhi_reg, 0) AS mediana_hhi_reg,
    UF.mediana_hhi_uf AS mediana_hhi_uf,
    BR.mediana_hhi_br AS mediana_hhi_br,
    ISNULL(REG.mediana_crm_invalido_reg, 0) AS mediana_crm_invalido_reg,
    UF.mediana_pct_crm_invalido_uf AS mediana_crm_invalido_uf,
    BR.mediana_pct_crm_invalido_br AS mediana_crm_invalido_br,
    ISNULL(REG.mediana_robos_reg, 0) AS mediana_robos_reg,
    UF.mediana_robos_uf AS mediana_robos_uf,
    BR.mediana_robos_br AS mediana_robos_br,
    ISNULL(REG.mediana_indice_rede_reg, 0) AS mediana_indice_rede_reg,
    UF.mediana_indice_rede_uf AS mediana_indice_rede_uf,
    BR.mediana_indice_rede_br AS mediana_indice_rede_br,
    ISNULL(REG.mediana_turistas_reg, 0) AS mediana_turistas_reg,
    UF.mediana_turistas_uf AS mediana_turistas_uf,
    BR.mediana_turistas_br AS mediana_turistas_br,

    -- Riscos Relativos Baseados em MEDIANA
    CAST(CASE WHEN REG.mediana_concentracao_reg > 0 THEN I.pct_concentracao_top1 / REG.mediana_concentracao_reg ELSE 0 END AS DECIMAL(18,4)) AS risco_concentracao_reg,
    CAST(CASE WHEN UF.mediana_concentracao_uf > 0 THEN I.pct_concentracao_top1 / UF.mediana_concentracao_uf ELSE 0 END AS DECIMAL(18,4)) AS risco_concentracao_uf,
    CAST(CASE WHEN BR.mediana_concentracao_br > 0 THEN I.pct_concentracao_top1 / BR.mediana_concentracao_br ELSE 0 END AS DECIMAL(18,4)) AS risco_concentracao_br,
    
    CAST(CASE WHEN REG.mediana_concentracao_top5_reg > 0 THEN I.pct_concentracao_top5 / REG.mediana_concentracao_top5_reg ELSE 0 END AS DECIMAL(18,4)) AS risco_concentracao_top5_reg,
    CAST(CASE WHEN UF.mediana_concentracao_top5_uf > 0 THEN I.pct_concentracao_top5 / UF.mediana_concentracao_top5_uf ELSE 0 END AS DECIMAL(18,4)) AS risco_concentracao_top5_uf,
    CAST(CASE WHEN BR.mediana_concentracao_top5_br > 0 THEN I.pct_concentracao_top5 / BR.mediana_concentracao_top5_br ELSE 0 END AS DECIMAL(18,4)) AS risco_concentracao_top5_br,

    -- Riscos Robôs com suavização
    CAST(CASE WHEN REG.mediana_robos_reg > 0 THEN (I.qtd_prescritores_robos + 0.001) / (REG.mediana_robos_reg + 0.001) ELSE CASE WHEN I.qtd_prescritores_robos > 0 THEN 99.0 ELSE 0 END END AS DECIMAL(18,4)) AS risco_robos_reg,
    CAST(CASE WHEN UF.mediana_robos_uf > 0 THEN (I.qtd_prescritores_robos + 0.001) / (UF.mediana_robos_uf + 0.001) ELSE CASE WHEN I.qtd_prescritores_robos > 0 THEN 99.0 ELSE 0 END END AS DECIMAL(18,4)) AS risco_robos_uf,
    CAST(CASE WHEN BR.mediana_robos_br > 0 THEN (I.qtd_prescritores_robos + 0.001) / (BR.mediana_robos_br + 0.001) ELSE CASE WHEN I.qtd_prescritores_robos > 0 THEN 99.0 ELSE 0 END END AS DECIMAL(18,4)) AS risco_robos_br,
    
    -- RISCO CRM INVÁLIDO 
    CAST(CASE WHEN REG.mediana_crm_invalido_reg > 0 THEN 
        ((CAST(I.qtd_crm_invalido AS DECIMAL(18,4)) / NULLIF(I.total_prescritores_distintos, 0) * 100.0) + 0.001) / (REG.mediana_crm_invalido_reg + 0.001) 
    ELSE CASE WHEN I.qtd_crm_invalido > 0 THEN 99.0 ELSE 0 END END AS DECIMAL(18,4)) AS risco_crm_invalido_reg,
    
    CAST(CASE WHEN UF.mediana_pct_crm_invalido_uf > 0 THEN 
        ((CAST(I.qtd_crm_invalido AS DECIMAL(18,4)) / NULLIF(I.total_prescritores_distintos, 0) * 100.0) + 0.001) / (UF.mediana_pct_crm_invalido_uf + 0.001) 
    ELSE CASE WHEN I.qtd_crm_invalido > 0 THEN 99.0 ELSE 0 END END AS DECIMAL(18,4)) AS risco_crm_invalido_uf,
    
    CAST(CASE WHEN BR.mediana_pct_crm_invalido_br > 0 THEN 
        ((CAST(I.qtd_crm_invalido AS DECIMAL(18,4)) / NULLIF(I.total_prescritores_distintos, 0) * 100.0) + 0.001) / (BR.mediana_pct_crm_invalido_br + 0.001) 
    ELSE CASE WHEN I.qtd_crm_invalido > 0 THEN 99.0 ELSE 0 END END AS DECIMAL(18,4)) AS risco_crm_invalido_br,

    -- RISCO REDE
    CAST(CASE WHEN REG.mediana_indice_rede_reg > 0 THEN (I.indice_rede_suspeita + 0.01) / (REG.mediana_indice_rede_reg + 0.01) ELSE 0 END AS DECIMAL(18,4)) AS risco_rede_reg,
    CAST(CASE WHEN UF.mediana_indice_rede_uf > 0 THEN (I.indice_rede_suspeita + 0.01) / (UF.mediana_indice_rede_uf + 0.01) ELSE 0 END AS DECIMAL(18,4)) AS risco_rede_uf,
    CAST(CASE WHEN BR.mediana_indice_rede_br > 0 THEN (I.indice_rede_suspeita + 0.01) / (BR.mediana_indice_rede_br + 0.01) ELSE 0 END AS DECIMAL(18,4)) AS risco_rede_br,

    -- RISCO TURISTAS
    CAST(CASE WHEN REG.mediana_turistas_reg > 0 THEN (I.qtd_prescritores_turistas + 0.001) / (REG.mediana_turistas_reg + 0.001) ELSE CASE WHEN I.qtd_prescritores_turistas > 0 THEN 99.0 ELSE 0 END END AS DECIMAL(18,4)) AS risco_turistas_reg,
    CAST(CASE WHEN UF.mediana_turistas_uf > 0 THEN (I.qtd_prescritores_turistas + 0.001) / (UF.mediana_turistas_uf + 0.001) ELSE CASE WHEN I.qtd_prescritores_turistas > 0 THEN 99.0 ELSE 0 END END AS DECIMAL(18,4)) AS risco_turistas_uf,
    CAST(CASE WHEN BR.mediana_turistas_br > 0 THEN (I.qtd_prescritores_turistas + 0.001) / (BR.mediana_turistas_br + 0.001) ELSE CASE WHEN I.qtd_prescritores_turistas > 0 THEN 99.0 ELSE 0 END END AS DECIMAL(18,4)) AS risco_turistas_br,

    -- Score de Prescritores (componentes normalizados 0-1, ponderados)
    -- HHI relativo (teto 5x normalizado): peso 40%
    -- CRM invalido (flag binaria):         peso 30%
    -- Robos locais (flag binaria):         peso 20%
    -- Prescritores turistas (flag bin.):   peso 10%
    CAST((
        CASE
            WHEN (ISNULL(I.indice_hhi, 0) + 0.01) / (ISNULL(COALESCE(REG.mediana_hhi_reg, BR.mediana_hhi_br), 0) + 0.01) > 5.0
            THEN 1.0
            ELSE CAST((ISNULL(I.indice_hhi, 0) + 0.01) / (ISNULL(COALESCE(REG.mediana_hhi_reg, BR.mediana_hhi_br), 0) + 0.01) AS DECIMAL(18,4)) / 5.0
        END * 0.4 +
        CASE WHEN I.qtd_crm_invalido > 0 THEN 1.0 ELSE 0.0 END * 0.3 +
        CASE WHEN I.qtd_prescritores_robos > 0 THEN 1.0 ELSE 0.0 END * 0.2 +
        CASE WHEN I.qtd_prescritores_turistas > 0 THEN 1.0 ELSE 0.0 END * 0.1
    ) AS DECIMAL(18,4)) AS score_prescritores

INTO temp_CGUSC.fp.indicador_crm_detalhado
FROM temp_CGUSC.fp.indicador_crm I
INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.nu_cnpj
LEFT JOIN temp_CGUSC.fp.indicador_crm_mun MUN ON F.uf = MUN.uf AND F.municipio = MUN.municipio
LEFT JOIN temp_CGUSC.fp.indicador_crm_regiao REG ON F.id_regiao_saude = REG.id_regiao_saude
LEFT JOIN temp_CGUSC.fp.indicador_crm_uf UF ON F.uf = UF.uf
CROSS JOIN temp_CGUSC.fp.indicador_crm_br BR;

CREATE CLUSTERED INDEX IDX_FinalPresc_CNPJ ON temp_CGUSC.fp.indicador_crm_detalhado(nu_cnpj);
CREATE NONCLUSTERED INDEX IDX_FinalPresc_Score ON temp_CGUSC.fp.indicador_crm_detalhado(score_prescritores DESC);
GO


-- ============================================================================
-- PASSO 7: TABELA DE CRMs DE INTERESSE POR FARMÁCIA (TOP 20 + ALERTAS)
-- ============================================================================
--CORREÇÃO PRINCIPAL v2: 
--    - Trazer TODOS os alertas (1-6)
--    - Incluir top20 por volume + TODOS os prescritores com qualquer alerta
--    - Alerta6 agora vem da indicador_crm_detalhado
--    - Inclui dt_inscricao_crm e flag_prescricao_antes_registro

DROP TABLE IF EXISTS temp_CGUSC.fp.top_20_crms_farmacia;

WITH CRMsRankeados AS (
    SELECT 
        P.cnpj AS cnpj,
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
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) / NULLIF(CAST(T.total_valor_farmacia AS DECIMAL(18,4)), 0) * 100.0 AS pct_acumulado,
        
        -- Ranking
        ROW_NUMBER() OVER (PARTITION BY P.cnpj ORDER BY P.vl_total_prescricoes DESC) AS ranking,
        
        -- Flag CRM Inválido (verifica se existe na base do CFM e tem volume >= 5)
        CASE WHEN CFM.NU_CRM IS NULL AND P.nu_prescricoes >= 5 THEN 1 ELSE 0 END AS flag_crm_invalido,
        
        -- Flag Robô (>30 prescrições/dia neste estabelecimento)
        CASE WHEN P.nu_prescricoes_dia > 30 THEN 1 ELSE 0 END AS flag_robo,
        
        --Dados da rede (total Brasil)
        ISNULL(A.nu_prescricoes_medico_em_todos_estabelecimentos, P.nu_prescricoes) AS prescricoes_total_brasil,
        ISNULL(A.nu_prescricoes_dia_em_todos_estabelecimentos, P.nu_prescricoes_dia) AS prescricoes_dia_total_brasil,
        ISNULL(A.nu_estabelecimentos_com_registro_mesmo_crm, 1) AS qtd_estabelecimentos_atua,
        
        -- Flag CRM Exclusivo (VILÃO CORRIGIDO: Só marca se tivermos certeza via tabela A que estab=1)
        CASE WHEN ISNULL(A.nu_estabelecimentos_com_registro_mesmo_crm, 0) = 1 THEN 1 ELSE 0 END AS flag_crm_exclusivo,
        
        -- % do volume aqui vs total
        CASE 
            WHEN ISNULL(A.nu_prescricoes_medico_em_todos_estabelecimentos, 0) > 0 
            THEN CAST(P.nu_prescricoes AS DECIMAL(18,4)) / 
                 CAST(A.nu_prescricoes_medico_em_todos_estabelecimentos AS DECIMAL(18,4)) * 100.0
            ELSE 100.0
        END AS pct_volume_aqui_vs_total,
        
        -- Flag Robô Oculto (parece normal aqui <=30/dia, mas >30/dia no total Brasil)
        CASE
            WHEN P.nu_prescricoes_dia <= 30
             AND ISNULL(A.nu_prescricoes_dia_em_todos_estabelecimentos, 0) > 30
            THEN 1
            ELSE 0
        END AS flag_robo_oculto,
        
        --NOVO: Data de inscrição do CRM (da tabela CFM)
        CFM.dt_inscricao_convertida AS dt_inscricao_crm,
        
        --NOVO: Flag para prescrição antes do registro do CRM
        CASE 
            WHEN CFM.dt_inscricao_convertida IS NOT NULL 
             AND P.dt_primeira_prescricao < CFM.dt_inscricao_convertida 
             AND P.nu_prescricoes >= 5
            THEN 1 
            ELSE 0 
        END AS flag_prescricao_antes_registro,
        
        --CORREÇÃO: Trazer TODOS os alertas (incluindo alerta6)
        ISNULL(A.alerta1, '') AS alerta1_crm_invalido,
        ISNULL(A.alerta2, '') AS alerta2_tempo_concentrado,
        ISNULL(A.alerta3, '') AS alerta3_robo_estabelecimento,
        ISNULL(A.alerta4, '') AS alerta4_robo_rede,
        ISNULL(A.alerta5, '') AS alerta5_geografico,
        ISNULL(A.alerta6, '') AS alerta6_prescricao_antes_registro
        
    FROM #CRMsPorFarmacia P
    INNER JOIN #TotaisFarmacia T ON T.cnpj = P.cnpj
    --JOIN sem filtro restritivo - traz TODOS os registros
    LEFT JOIN (
        SELECT
            nu_cnpj,
            id_medico,
            MAX(nu_prescricoes_medico_em_todos_estabelecimentos) AS nu_prescricoes_medico_em_todos_estabelecimentos,
            MAX(nu_prescricoes_dia_em_todos_estabelecimentos) AS nu_prescricoes_dia_em_todos_estabelecimentos,
            MAX(nu_estabelecimentos_com_registro_mesmo_crm) AS nu_estabelecimentos_com_registro_mesmo_crm,
            MAX(alerta1) AS alerta1,
            MAX(alerta2) AS alerta2,
            MAX(alerta3) AS alerta3,
            MAX(alerta4) AS alerta4,
            MAX(alerta5) AS alerta5,
            MAX(alerta6) AS alerta6
        FROM temp_CGUSC.fp.dados_crm_detalhado
        GROUP BY nu_cnpj, id_medico
    ) A ON A.nu_cnpj = P.cnpj AND A.id_medico = P.id_medico
    --JOIN com tabela do CFM para verificar existência e obter data de inscrição
    LEFT JOIN (
        SELECT 
            NU_CRM,
            SG_uf,
            TRY_CONVERT(DATE, DT_INSCRICAO, 103) AS dt_inscricao_convertida
        FROM temp_CFM.dbo.medicos_jul_2025_mod
    ) CFM ON TRY_CAST(CFM.NU_CRM AS BIGINT) = TRY_CAST(P.nu_crm AS BIGINT) AND CFM.SG_uf = P.sg_uf_crm
)

--CORREÇÃO PRINCIPAL: top30 por volume OU qualquer prescritor com alerta
SELECT *
INTO temp_CGUSC.fp.top_20_crms_farmacia
FROM CRMsRankeados
WHERE ranking <= 30
   OR alerta1_crm_invalido <> ''
   OR alerta2_tempo_concentrado <> ''
   OR alerta3_robo_estabelecimento <> ''
   OR alerta4_robo_rede <> ''
   OR alerta5_geografico <> ''
   OR alerta6_prescricao_antes_registro <> ''
   OR flag_crm_invalido = 1
   OR flag_robo = 1
   OR flag_robo_oculto = 1
   OR flag_crm_exclusivo = 1
   OR flag_prescricao_antes_registro = 1;

CREATE CLUSTERED INDEX IDX_Top20_CNPJ ON temp_CGUSC.fp.top_20_crms_farmacia(cnpj, ranking);


--NOVO: Verificar quantos prescritores entraram por alerta (fora do top20)
SELECT 
    'Total de registros' AS metrica,
    COUNT(*) AS valor
FROM temp_CGUSC.fp.top_20_crms_farmacia
UNION ALL
SELECT 
    'Registros no top30' AS metrica,
    COUNT(*) AS valor
FROM temp_CGUSC.fp.top_20_crms_farmacia
WHERE ranking <= 30
UNION ALL
SELECT 
    'Registros FORA do top30 (só por alerta)' AS metrica,
    COUNT(*) AS valor
FROM temp_CGUSC.fp.top_20_crms_farmacia
WHERE ranking > 30;

PRINT '============================================================================';
PRINT 'SCRIPT EXECUTADO COM SUCESSO - CORREÇÕES APLICADAS:';
PRINT '  1. Prescrições contadas por COUNT(DISTINCT num_autorizacao)';
PRINT '  2. Alertas (1-6) incluídos na tabela top_20_crms_farmacia (filtro Top30)';
PRINT '  3. Dados de rede (total Brasil) incluídos para cada prescritor';
PRINT '  4. Flag de robô oculto calculado (inclusão via Top30)';
PRINT '  5. NOVO: Tabela inclui top30 + TODOS prescritores com alertas';
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
DROP TABLE IF EXISTS #CRMAntesRegistroPorFarmacia;
DROP TABLE IF EXISTS #TuristasPorFarmacia;
DROP TABLE IF EXISTS #ParetoPorFarmacia;
DROP TABLE IF EXISTS #DadosRedePorPrescritor;
DROP TABLE IF EXISTS #RedePorFarmacia;

DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crm_mun;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crm_regiao;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crm_uf;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crm_br;


-- ============================================================================
-- VERIFICAÇÃO FINAL
-- ============================================================================
SELECT TOP 100 * FROM temp_CGUSC.fp.indicador_crm_detalhado ORDER BY score_prescritores DESC;
SELECT TOP 50 * FROM temp_CGUSC.fp.top_20_crms_farmacia WHERE cnpj = (SELECT TOP 1 cnpj FROM temp_CGUSC.fp.indicador_crm_detalhado ORDER BY score_prescritores DESC);
























