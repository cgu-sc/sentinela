USE [temp_CGUSC]
GO

-- ============================================================================
-- INDICADOR DE PRESCRITORES - ANÁLISE DE CRM POR FARMÁCIA - VERSÃO 3
-- ============================================================================
-- ALTERAÇÕES v3:
--   1. Dimensão COMPETENCIA propagada em toda a cadeia (vem do crms_1 v3)
--   2. Todos os GROUP BY e PARTITION BY incluem competencia
--   3. Tabelas de benchmark renomeadas: indicador_crm_bench_{mun,uf,regiao,br}
--   4. CROSS JOIN com benchmark_br substituído por INNER JOIN em competencia
--   5. Rankings e medianas calculados por (geografia, competencia)
-- ============================================================================


-- ============================================================================
-- PASSO 1: CONSUMO DOS DADOS AGREGADOS (VEM DO CRMS_1)
-- ============================================================================
DROP TABLE IF EXISTS #CRMsPorFarmacia;

SELECT
    nu_cnpj                           AS cnpj,
    CONCAT(nu_crm, '/', sg_uf_crm)   AS id_medico,
    nu_crm,
    sg_uf_crm,
    competencia,
    nu_prescricoes_medico             AS nu_prescricoes,
    vl_autorizacoes_medico            AS vl_total_prescricoes,
    dt_prescricao_inicial_medico      AS dt_primeira_prescricao,
    dt_prescricao_final_medico        AS dt_ultima_prescricao,
    CAST(
        CAST(nu_prescricoes_medico AS DECIMAL(18,2)) /
        NULLIF(CAST(DATEDIFF(DAY, dt_prescricao_inicial_medico, dt_prescricao_final_medico) + 1 AS DECIMAL(18,2)), 0)
    AS DECIMAL(18,2))                 AS nu_prescricoes_dia
INTO #CRMsPorFarmacia
FROM temp_CGUSC.fp.base_agregada_crm_cnpj;

CREATE CLUSTERED INDEX IDX_Presc_CNPJ    ON #CRMsPorFarmacia(cnpj, competencia);
CREATE NONCLUSTERED INDEX IDX_CRMPorchave ON #CRMsPorFarmacia(nu_crm, sg_uf_crm, competencia);


-- ============================================================================
-- PASSO 2: TOTAIS POR FARMÁCIA / COMPETÊNCIA
-- ============================================================================
DROP TABLE IF EXISTS #TotaisFarmacia;

SELECT
    cnpj,
    competencia,
    SUM(nu_prescricoes)        AS total_prescricoes_farmacia,
    SUM(vl_total_prescricoes)  AS total_valor_farmacia,
    COUNT(DISTINCT id_medico)  AS total_prescritores_distintos
INTO #TotaisFarmacia
FROM #CRMsPorFarmacia
GROUP BY cnpj, competencia;

CREATE CLUSTERED INDEX IDX_Totais_CNPJ ON #TotaisFarmacia(cnpj, competencia);


-- ============================================================================
-- PASSO 3: DADOS DE REDE POR PRESCRITOR / COMPETÊNCIA
-- ============================================================================
DROP TABLE IF EXISTS #DadosRedePorPrescritor;

SELECT
    A.id_medico,
    A.competencia,
    MAX(A.nu_prescricoes_dia_em_todos_estabelecimentos) AS nu_prescricoes_dia_em_todos_estabelecimentos,
    MAX(A.nu_estabelecimentos_com_registro_mesmo_crm)   AS nu_estabelecimentos_com_registro_mesmo_crm
INTO #DadosRedePorPrescritor
FROM temp_CGUSC.fp.dados_crm_detalhado A
GROUP BY A.id_medico, A.competencia;

CREATE CLUSTERED INDEX IDX_DadosRede ON #DadosRedePorPrescritor(id_medico, competencia);


-- ============================================================================
-- PASSO 4: TOP 5 POR FARMÁCIA / COMPETÊNCIA
-- ============================================================================
DROP TABLE IF EXISTS #Top5PorFarmacia;

WITH RankedPrescritores AS (
    SELECT
        P.cnpj, P.competencia, P.id_medico, P.vl_total_prescricoes,
        ROW_NUMBER() OVER (PARTITION BY P.cnpj, P.competencia ORDER BY P.vl_total_prescricoes DESC) AS ranking
    FROM #CRMsPorFarmacia P
)
SELECT
    cnpj,
    competencia,
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
GROUP BY cnpj, competencia;

CREATE CLUSTERED INDEX IDX_Top5_CNPJ ON #Top5PorFarmacia(cnpj, competencia);


-- ============================================================================
-- PASSO 5: HHI POR FARMÁCIA / COMPETÊNCIA
-- ============================================================================
DROP TABLE IF EXISTS #HHIPorFarmacia;

SELECT
    P.cnpj,
    P.competencia,
    SUM(POWER(
        CAST(P.vl_total_prescricoes AS DECIMAL(18,4)) /
        NULLIF(CAST(T.total_valor_farmacia AS DECIMAL(18,4)), 0) * 100.0
    , 2)) AS indice_hhi
INTO #HHIPorFarmacia
FROM #CRMsPorFarmacia P
INNER JOIN #TotaisFarmacia T ON T.cnpj = P.cnpj AND T.competencia = P.competencia
GROUP BY P.cnpj, P.competencia;

CREATE CLUSTERED INDEX IDX_HHI_CNPJ ON #HHIPorFarmacia(cnpj, competencia);


-- ============================================================================
-- PASSO 6: ROBÔS LOCAIS (>30 PRESC/DIA) POR FARMÁCIA / COMPETÊNCIA
-- ============================================================================
DROP TABLE IF EXISTS #RobosPorFarmacia;

SELECT cnpj, competencia, COUNT(*) AS qtd_prescritores_robos
INTO #RobosPorFarmacia
FROM #CRMsPorFarmacia
WHERE nu_prescricoes_dia > 30
GROUP BY cnpj, competencia;

CREATE CLUSTERED INDEX IDX_Robos_CNPJ ON #RobosPorFarmacia(cnpj, competencia);


-- ============================================================================
-- PASSO 7: CRM INVÁLIDO (NÃO CONSTA NO CFM) POR FARMÁCIA / COMPETÊNCIA
-- ============================================================================
DROP TABLE IF EXISTS #CRMInvalidoPorFarmacia;

SELECT
    P.cnpj,
    P.competencia,
    COUNT(*)                   AS qtd_crm_invalido,
    SUM(P.vl_total_prescricoes) AS vl_crm_invalido
INTO #CRMInvalidoPorFarmacia
FROM #CRMsPorFarmacia P
WHERE NOT EXISTS (
    SELECT 1
    FROM temp_CFM.dbo.medicos_jul_2025_mod CFM WITH(NOLOCK)
    WHERE CAST(CFM.NU_CRM AS VARCHAR(20)) = CAST(P.nu_crm AS VARCHAR(20))
      AND CFM.SG_uf = P.sg_uf_crm
) AND P.nu_prescricoes >= 5
GROUP BY P.cnpj, P.competencia;

CREATE CLUSTERED INDEX IDX_CRMInv_CNPJ ON #CRMInvalidoPorFarmacia(cnpj, competencia);


-- ============================================================================
-- PASSO 8: VENDAS ANTES DO REGISTRO NO CFM POR FARMÁCIA / COMPETÊNCIA
-- ============================================================================
DROP TABLE IF EXISTS #CRMAntesRegistroPorFarmacia;

SELECT
    P.cnpj,
    P.competencia,
    COUNT(*)                   AS qtd_crm_antes_registro,
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
GROUP BY P.cnpj, P.competencia;

CREATE CLUSTERED INDEX IDX_CRMAntesReg_CNPJ ON #CRMAntesRegistroPorFarmacia(cnpj, competencia);


-- ============================================================================
-- PASSO 9: TURISTAS (ALERTA 5) POR FARMÁCIA / COMPETÊNCIA
-- ============================================================================
DROP TABLE IF EXISTS #TuristasPorFarmacia;

SELECT nu_cnpj AS cnpj, competencia, COUNT(DISTINCT id_medico) AS qtd_prescritores_turistas
INTO #TuristasPorFarmacia
FROM temp_CGUSC.fp.dados_crm_detalhado
WHERE alerta5 IS NOT NULL AND alerta5 <> ''
GROUP BY nu_cnpj, competencia;

CREATE CLUSTERED INDEX IDX_Turistas_CNPJ ON #TuristasPorFarmacia(cnpj, competencia);


-- ============================================================================
-- PASSO 10: PARETO (80% DO VALOR) POR FARMÁCIA / COMPETÊNCIA
-- ============================================================================
DROP TABLE IF EXISTS #ParetoPorFarmacia;

WITH PrescritoresAcumulado AS (
    SELECT
        P.cnpj, P.competencia, P.vl_total_prescricoes, T.total_valor_farmacia,
        SUM(P.vl_total_prescricoes) OVER (
            PARTITION BY P.cnpj, P.competencia
            ORDER BY P.vl_total_prescricoes DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS acumulado
    FROM #CRMsPorFarmacia P
    INNER JOIN #TotaisFarmacia T ON T.cnpj = P.cnpj AND T.competencia = P.competencia
)
SELECT cnpj, competencia, COUNT(*) AS qtd_prescritores_80pct
INTO #ParetoPorFarmacia
FROM PrescritoresAcumulado
WHERE acumulado - vl_total_prescricoes < total_valor_farmacia * 0.80
GROUP BY cnpj, competencia;

CREATE CLUSTERED INDEX IDX_Pareto_CNPJ ON #ParetoPorFarmacia(cnpj, competencia);


-- ============================================================================
-- PASSO 11: REDE (ROBÔ OCULTO / MULTI-FARMÁCIA) POR FARMÁCIA / COMPETÊNCIA
-- ============================================================================
DROP TABLE IF EXISTS #RedePorFarmacia;

SELECT
    P.cnpj,
    P.competencia,
    COUNT(DISTINCT CASE
        WHEN P.nu_prescricoes_dia <= 30
         AND ISNULL(R.nu_prescricoes_dia_em_todos_estabelecimentos, 0) > 30
        THEN P.id_medico
    END) AS qtd_prescritores_robos_ocultos,
    COUNT(DISTINCT CASE
        WHEN ISNULL(R.nu_estabelecimentos_com_registro_mesmo_crm, 1) > 70
        THEN P.id_medico
    END) AS qtd_prescritores_multi_farmacia,
    AVG(CAST(ISNULL(R.nu_estabelecimentos_com_registro_mesmo_crm, 1) AS DECIMAL(18,4))) AS indice_rede_suspeita
INTO #RedePorFarmacia
FROM #CRMsPorFarmacia P
LEFT JOIN #DadosRedePorPrescritor R ON R.id_medico = P.id_medico AND R.competencia = P.competencia
GROUP BY P.cnpj, P.competencia;

CREATE CLUSTERED INDEX IDX_Rede_CNPJ ON #RedePorFarmacia(cnpj, competencia);


-- ============================================================================
-- PASSO 12: TABELA CONSOLIDADA indicador_crm (por farmácia / competência)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crm;

SELECT
    T.cnpj AS nu_cnpj,
    T.competencia,
    T.total_prescricoes_farmacia,
    T.total_valor_farmacia,
    T.total_prescritores_distintos,

    ISNULL(CAST(T5.valor_top1 AS DECIMAL(18,2)) / NULLIF(CAST(T.total_valor_farmacia AS DECIMAL(18,2)), 0) * 100.0, 0) AS pct_concentracao_top1,
    ISNULL(T5.id_top1, '')                                                                                              AS id_top1_prescritor,
    ISNULL(CAST(T5.valor_top5_acumulado AS DECIMAL(18,2)) / NULLIF(CAST(T.total_valor_farmacia AS DECIMAL(18,2)), 0) * 100.0, 0) AS pct_concentracao_top5,
    ISNULL(CONCAT(T5.id_top1, ', ', T5.id_top2, ', ', T5.id_top3, ', ', T5.id_top4, ', ', T5.id_top5), '') AS ids_top5_prescritores,

    ISNULL(H.indice_hhi, 0)                      AS indice_hhi,
    ISNULL(R.qtd_prescritores_robos, 0)           AS qtd_prescritores_robos,
    ISNULL(C.qtd_crm_invalido, 0)                 AS qtd_crm_invalido,
    ISNULL(C.vl_crm_invalido, 0)                  AS vl_crm_invalido,
    ISNULL(CAST(C.vl_crm_invalido AS DECIMAL(18,2)) / NULLIF(CAST(T.total_valor_farmacia AS DECIMAL(18,2)), 0) * 100.0, 0) AS pct_valor_crm_invalido,
    ISNULL(AR.qtd_crm_antes_registro, 0)          AS qtd_crm_antes_registro,
    ISNULL(AR.vl_crm_antes_registro, 0)           AS vl_crm_antes_registro,
    ISNULL(CAST(AR.vl_crm_antes_registro AS DECIMAL(18,2)) / NULLIF(CAST(T.total_valor_farmacia AS DECIMAL(18,2)), 0) * 100.0, 0) AS pct_valor_crm_antes_registro,
    ISNULL(TU.qtd_prescritores_turistas, 0)       AS qtd_prescritores_turistas,
    ISNULL(PA.qtd_prescritores_80pct, 1)          AS qtd_prescritores_80pct,
    ISNULL(RE.qtd_prescritores_robos_ocultos, 0)  AS qtd_prescritores_robos_ocultos,
    ISNULL(RE.qtd_prescritores_multi_farmacia, 0) AS qtd_prescritores_multi_farmacia,
    ISNULL(RE.indice_rede_suspeita, 1.0)          AS indice_rede_suspeita

INTO temp_CGUSC.fp.indicador_crm
FROM #TotaisFarmacia T
LEFT JOIN #Top5PorFarmacia           T5 ON T5.cnpj = T.cnpj AND T5.competencia = T.competencia
LEFT JOIN #HHIPorFarmacia             H ON  H.cnpj = T.cnpj AND  H.competencia = T.competencia
LEFT JOIN #RobosPorFarmacia           R ON  R.cnpj = T.cnpj AND  R.competencia = T.competencia
LEFT JOIN #CRMInvalidoPorFarmacia     C ON  C.cnpj = T.cnpj AND  C.competencia = T.competencia
LEFT JOIN #CRMAntesRegistroPorFarmacia AR ON AR.cnpj = T.cnpj AND AR.competencia = T.competencia
LEFT JOIN #TuristasPorFarmacia       TU ON TU.cnpj = T.cnpj AND TU.competencia = T.competencia
LEFT JOIN #ParetoPorFarmacia         PA ON PA.cnpj = T.cnpj AND PA.competencia = T.competencia
LEFT JOIN #RedePorFarmacia           RE ON RE.cnpj = T.cnpj AND RE.competencia = T.competencia;

CREATE CLUSTERED INDEX IDX_IndPresc_CNPJ ON temp_CGUSC.fp.indicador_crm(nu_cnpj, competencia);
GO
-- GO: indicador_crm já existe com o novo schema antes de criar as tabelas de benchmark


-- (As tabelas e dados de Benchmarks comparativos geográficos foram removidos)


-- ============================================================================
-- PASSO 17: TABELA CONSOLIDADA indicador_crm_detalhado
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crm_detalhado;

SELECT
    I.nu_cnpj,
    I.competencia,
    F.razaoSocial,
    F.municipio,
    CAST(F.uf AS VARCHAR(2))    AS uf,
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

    -- % CRM Inválido
    CAST(CASE
        WHEN I.total_prescritores_distintos > 0
        THEN (CAST(I.qtd_crm_invalido AS DECIMAL(18,4)) / I.total_prescritores_distintos) * 100.0
        ELSE 0
    END AS DECIMAL(18,2)) AS pct_crm_invalido,

    I.qtd_prescritores_turistas,
    I.qtd_prescritores_80pct,
    I.qtd_prescritores_robos_ocultos,
    I.qtd_prescritores_multi_farmacia,

    CAST(CASE
        WHEN I.total_prescritores_distintos > 0
        THEN (CAST(I.qtd_prescritores_multi_farmacia AS DECIMAL(18,4)) / I.total_prescritores_distintos) * 100.0
        ELSE 0
    END AS DECIMAL(18,2)) AS pct_prescritores_multi_farmacia,

    I.indice_rede_suspeita,

    -- Score de Prescritores (Sem ponderações geográficas comparativas)
    CAST((
        -- HHI Absoluto (teto matemático de escala 10.000): peso 40%
        (CAST(ISNULL(I.indice_hhi, 0) AS DECIMAL(18,4)) / 10000.0) * 0.4 +
        CASE WHEN I.qtd_crm_invalido > 0          THEN 1.0 ELSE 0.0 END * 0.3 +
        CASE WHEN I.qtd_prescritores_robos > 0    THEN 1.0 ELSE 0.0 END * 0.2 +
        CASE WHEN I.qtd_prescritores_turistas > 0 THEN 1.0 ELSE 0.0 END * 0.1
    ) AS DECIMAL(18,4)) AS score_prescritores

INTO temp_CGUSC.fp.indicador_crm_detalhado
FROM temp_CGUSC.fp.indicador_crm I
INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.nu_cnpj;

CREATE CLUSTERED INDEX IDX_FinalPresc_CNPJ  ON temp_CGUSC.fp.indicador_crm_detalhado(nu_cnpj, competencia);
CREATE NONCLUSTERED INDEX IDX_FinalPresc_Score ON temp_CGUSC.fp.indicador_crm_detalhado(competencia, score_prescritores DESC);
GO
-- GO: indicador_crm_detalhado existe antes de criar top_20_crms_farmacia


-- ============================================================================
-- PASSO 18: TOP 20 CRMs POR FARMÁCIA / COMPETÊNCIA
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.top_20_crms_farmacia;

WITH CRMsRankeados AS (
    SELECT
        P.cnpj,
        P.competencia,
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
            PARTITION BY P.cnpj, P.competencia
            ORDER BY P.vl_total_prescricoes DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) / NULLIF(CAST(T.total_valor_farmacia AS DECIMAL(18,4)), 0) * 100.0 AS pct_acumulado,

        -- Ranking
        ROW_NUMBER() OVER (PARTITION BY P.cnpj, P.competencia ORDER BY P.vl_total_prescricoes DESC) AS ranking,

        -- Flag CRM Inválido
        CASE WHEN CFM.NU_CRM IS NULL AND P.nu_prescricoes >= 5 THEN 1 ELSE 0 END AS flag_crm_invalido,

        -- Flag Robô Local
        CASE WHEN P.nu_prescricoes_dia > 30 THEN 1 ELSE 0 END AS flag_robo,

        -- Dados de Rede (total Brasil)
        ISNULL(A.nu_prescricoes_medico_em_todos_estabelecimentos, P.nu_prescricoes) AS prescricoes_total_brasil,
        ISNULL(A.nu_prescricoes_dia_em_todos_estabelecimentos, P.nu_prescricoes_dia) AS prescricoes_dia_total_brasil,
        ISNULL(A.nu_estabelecimentos_com_registro_mesmo_crm, 1)                      AS qtd_estabelecimentos_atua,

        -- Flag CRM Exclusivo (só prescreve neste CNPJ no mês)
        CASE WHEN ISNULL(A.nu_estabelecimentos_com_registro_mesmo_crm, 0) = 1 THEN 1 ELSE 0 END AS flag_crm_exclusivo,

        -- % do volume aqui vs total Brasil
        CASE
            WHEN ISNULL(A.nu_prescricoes_medico_em_todos_estabelecimentos, 0) > 0
            THEN CAST(P.nu_prescricoes AS DECIMAL(18,4)) /
                 CAST(A.nu_prescricoes_medico_em_todos_estabelecimentos AS DECIMAL(18,4)) * 100.0
            ELSE 100.0
        END AS pct_volume_aqui_vs_total,

        -- Flag Robô Oculto
        CASE
            WHEN P.nu_prescricoes_dia <= 30
             AND ISNULL(A.nu_prescricoes_dia_em_todos_estabelecimentos, 0) > 30
            THEN 1 ELSE 0
        END AS flag_robo_oculto,

        -- Data de inscrição e flag de prescrição antes do registro
        CFM.dt_inscricao_convertida AS dt_inscricao_crm,
        CASE
            WHEN CFM.dt_inscricao_convertida IS NOT NULL
             AND P.dt_primeira_prescricao < CFM.dt_inscricao_convertida
             AND P.nu_prescricoes >= 5
            THEN 1 ELSE 0
        END AS flag_prescricao_antes_registro,

        -- Alertas de texto
        ISNULL(A.alerta2, '') AS alerta2_tempo_concentrado,
        ISNULL(A.alerta5, '') AS alerta5_geografico

    FROM #CRMsPorFarmacia P
    INNER JOIN #TotaisFarmacia T ON T.cnpj = P.cnpj AND T.competencia = P.competencia

    -- Dados de rede por (cnpj, medico, competencia)
    LEFT JOIN (
        SELECT
            nu_cnpj, id_medico, competencia,
            MAX(nu_prescricoes_medico_em_todos_estabelecimentos) AS nu_prescricoes_medico_em_todos_estabelecimentos,
            MAX(nu_prescricoes_dia_em_todos_estabelecimentos)    AS nu_prescricoes_dia_em_todos_estabelecimentos,
            MAX(nu_estabelecimentos_com_registro_mesmo_crm)      AS nu_estabelecimentos_com_registro_mesmo_crm,
            MAX(alerta2) AS alerta2,
            MAX(alerta5) AS alerta5
        FROM temp_CGUSC.fp.dados_crm_detalhado
        GROUP BY nu_cnpj, id_medico, competencia
    ) A ON A.nu_cnpj = P.cnpj AND A.id_medico = P.id_medico AND A.competencia = P.competencia

    -- JOIN com CFM para validade e data de inscrição
    LEFT JOIN (
        SELECT
            NU_CRM, SG_uf,
            TRY_CONVERT(DATE, DT_INSCRICAO, 103) AS dt_inscricao_convertida
        FROM temp_CFM.dbo.medicos_jul_2025_mod
    ) CFM ON TRY_CAST(CFM.NU_CRM AS BIGINT) = TRY_CAST(P.nu_crm AS BIGINT)
          AND CFM.SG_uf = P.sg_uf_crm
)

-- Top 30 por volume OU qualquer prescritor com alerta
SELECT *
INTO temp_CGUSC.fp.top_20_crms_farmacia
FROM CRMsRankeados
WHERE ranking <= 30
   OR alerta2_tempo_concentrado <> ''
   OR alerta5_geografico        <> ''
   OR flag_crm_invalido          = 1
   OR flag_robo                  = 1
   OR flag_robo_oculto           = 1
   OR flag_crm_exclusivo         = 1
   OR flag_prescricao_antes_registro = 1;

CREATE CLUSTERED INDEX IDX_Top20_CNPJ ON temp_CGUSC.fp.top_20_crms_farmacia(cnpj, competencia, ranking);
GO


-- ============================================================================
-- LIMPEZA DE TABELAS INTERMEDIÁRIAS
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

-- Verificação final
SELECT TOP 5 * FROM temp_CGUSC.fp.indicador_crm_detalhado ORDER BY score_prescritores DESC;
SELECT TOP 5 * FROM temp_CGUSC.fp.top_20_crms_farmacia    ORDER BY cnpj, competencia, ranking;

PRINT '============================================================================';
PRINT 'SCRIPT v3 EXECUTADO COM SUCESSO:';
PRINT '  1. competencia propagada em toda a cadeia';
PRINT '  2. Rankings e comparativos removidos (script mais leve e absoluto)';
PRINT '  3. indicador_crm_detalhado: rankings e medianas por competencia';
PRINT '  4. top_20_crms_farmacia: top30 por (cnpj, competencia)';
PRINT '============================================================================';
GO
