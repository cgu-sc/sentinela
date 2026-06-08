USE [temp_CGUSC]
GO

-- ============================================================================
-- INDICADOR DE CONCENTRACAO DE CRMs (HHI)
-- ============================================================================
-- OBJETIVO: Calcular, por farmacia e ano, o indice Herfindahl-Hirschman
--           (HHI) da concentracao financeira das autorizacoes do PFPB por CRM.
--
-- METRICA PRINCIPAL:
--   indice_hhi = soma((valor_crm_ano / valor_total_farmacia_ano * 100)^2).
--
-- METRICAS AUXILIARES:
--   total_prescritores, total_prescricoes, valor_total_prescricoes,
--   valor_top1, valor_top5, participacao_top1_pct e participacao_top5_pct
--   permitem recompor a concentracao anual por estabelecimento.
--
-- FONTE DE DADOS:
--   - temp_CGUSC.fp.build_dados_crm_detalhado
--   - temp_CGUSC.fp.dados_farmacia (id_cnpj e contexto cadastral)
--
-- OBSERVACAO METODOLOGICA:
--   Este script salva somente componentes anuais brutos. Medianas, riscos
--   relativos, criticidade e score devem ser calculados posteriormente pela
--   matriz anual/backend, conforme o periodo selecionado.
-- ============================================================================

-- ============================================================================
-- LIMPEZA PREVIA DE TABELAS
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crm_hhi;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crm_hhi_detalhado;
GO

-- ============================================================================
-- PASSO 0: DIMENSOES E FONTES OBRIGATORIAS
-- ============================================================================
IF OBJECT_ID('temp_CGUSC.fp.dados_farmacia', 'U') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.dados_farmacia nao encontrada.', 16, 1);
    RETURN;
END;

IF COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'id') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'cnpj') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.dados_farmacia sem colunas obrigatorias id/cnpj.', 16, 1);
    RETURN;
END;

IF EXISTS (
    SELECT 1
    FROM temp_CGUSC.fp.dados_farmacia
    GROUP BY id
    HAVING COUNT_BIG(*) > 1
)
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.dados_farmacia possui ids duplicados.', 16, 1);
    RETURN;
END;

IF EXISTS (
    SELECT 1
    FROM temp_CGUSC.fp.dados_farmacia
    GROUP BY cnpj
    HAVING COUNT_BIG(*) > 1
)
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.dados_farmacia possui CNPJs duplicados.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('temp_CGUSC.fp.build_dados_crm_detalhado', 'U') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.build_dados_crm_detalhado nao encontrada. Rode o pipeline CRM detalhado antes deste indicador.', 16, 1);
    RETURN;
END;

IF COL_LENGTH('temp_CGUSC.fp.build_dados_crm_detalhado', 'nu_cnpj') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.build_dados_crm_detalhado', 'id_medico') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.build_dados_crm_detalhado', 'competencia') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.build_dados_crm_detalhado', 'nu_prescricoes_medico') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.build_dados_crm_detalhado', 'vl_autorizacoes_medico') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.build_dados_crm_detalhado sem colunas obrigatorias para HHI.', 16, 1);
    RETURN;
END;

IF EXISTS (
    SELECT 1
    FROM temp_CGUSC.fp.build_dados_crm_detalhado
    WHERE NULLIF(LTRIM(RTRIM(CAST(nu_cnpj AS VARCHAR(14)))), '') IS NULL
       OR NULLIF(LTRIM(RTRIM(CAST(id_medico AS VARCHAR(13)))), '') IS NULL
       OR competencia IS NULL
       OR nu_prescricoes_medico IS NULL
       OR vl_autorizacoes_medico IS NULL
)
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.build_dados_crm_detalhado possui valores obrigatorios nulos para HHI.', 16, 1);
    RETURN;
END;

IF EXISTS (
    SELECT 1
    FROM temp_CGUSC.fp.build_dados_crm_detalhado
    WHERE TRY_CAST(competencia AS INT) IS NULL
       OR TRY_CAST(competencia AS INT) < 201501
       OR TRY_CAST(competencia AS INT) > 209912
       OR TRY_CAST(competencia AS INT) % 100 NOT BETWEEN 1 AND 12
)
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.build_dados_crm_detalhado possui competencia invalida para HHI.', 16, 1);
    RETURN;
END;

IF EXISTS (
    SELECT 1
    FROM temp_CGUSC.fp.build_dados_crm_detalhado
    WHERE nu_prescricoes_medico < 0
       OR vl_autorizacoes_medico < 0
)
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.build_dados_crm_detalhado possui valores negativos para HHI.', 16, 1);
    RETURN;
END;

IF EXISTS (
    SELECT 1
    FROM temp_CGUSC.fp.build_dados_crm_detalhado AS D
    LEFT JOIN temp_CGUSC.fp.dados_farmacia AS F
        ON F.cnpj = D.nu_cnpj
    WHERE F.id IS NULL
)
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.build_dados_crm_detalhado possui CNPJs sem id correspondente em dados_farmacia.', 16, 1);
    RETURN;
END;

DROP TABLE IF EXISTS #farmacias_dim;

SELECT
    CAST(F.id AS INT) AS id_cnpj,
    CAST(F.cnpj AS VARCHAR(14)) AS cnpj
INTO #farmacias_dim
FROM temp_CGUSC.fp.dados_farmacia AS F;

CREATE UNIQUE CLUSTERED INDEX IDX_farmacias_dim_cnpj
ON #farmacias_dim(cnpj);

CREATE UNIQUE NONCLUSTERED INDEX IDX_farmacias_dim_id
ON #farmacias_dim(id_cnpj);


-- ============================================================================
-- PASSO 1: COMPONENTES POR FARMACIA/ANO/CRM
-- ============================================================================
DROP TABLE IF EXISTS #CrmAno;

SELECT
    F.id_cnpj,
    CAST(TRY_CAST(D.competencia AS INT) / 100 AS SMALLINT) AS ano_base,
    CAST(D.id_medico AS VARCHAR(13)) AS id_medico,
    CAST(SUM(CAST(D.nu_prescricoes_medico AS BIGINT)) AS BIGINT) AS prescricoes_crm_ano,
    CAST(SUM(CAST(D.vl_autorizacoes_medico AS DECIMAL(19,2))) AS DECIMAL(19,2)) AS valor_crm_ano
INTO #CrmAno
FROM temp_CGUSC.fp.build_dados_crm_detalhado AS D
INNER JOIN #farmacias_dim AS F
    ON F.cnpj = D.nu_cnpj
GROUP BY
    F.id_cnpj,
    CAST(TRY_CAST(D.competencia AS INT) / 100 AS SMALLINT),
    CAST(D.id_medico AS VARCHAR(13))
HAVING SUM(CAST(D.vl_autorizacoes_medico AS DECIMAL(19,2))) > 0;

IF NOT EXISTS (SELECT 1 FROM #CrmAno)
BEGIN
    RAISERROR('Nao ha valores positivos por CRM/ano para calcular HHI.', 16, 1);
    RETURN;
END;

CREATE CLUSTERED INDEX IDX_CrmAno_CNPJ_Ano
ON #CrmAno(id_cnpj, ano_base, id_medico);


-- ============================================================================
-- PASSO 2: TOTAIS ANUAIS DA FARMACIA
-- ============================================================================
DROP TABLE IF EXISTS #TotaisAno;

SELECT
    id_cnpj,
    ano_base,
    CAST(COUNT_BIG(*) AS INT) AS total_prescritores,
    CAST(SUM(prescricoes_crm_ano) AS BIGINT) AS total_prescricoes,
    CAST(SUM(valor_crm_ano) AS DECIMAL(19,2)) AS valor_total_prescricoes
INTO #TotaisAno
FROM #CrmAno
GROUP BY
    id_cnpj,
    ano_base
HAVING SUM(valor_crm_ano) > 0;

CREATE UNIQUE CLUSTERED INDEX IDX_TotaisAno_CNPJ_Ano
ON #TotaisAno(id_cnpj, ano_base);


-- ============================================================================
-- PASSO 3: RANKING ANUAL DOS CRMs POR VALOR
-- ============================================================================
DROP TABLE IF EXISTS #CrmAnoRanked;

SELECT
    C.id_cnpj,
    C.ano_base,
    C.id_medico,
    C.prescricoes_crm_ano,
    C.valor_crm_ano,
    T.total_prescritores,
    T.total_prescricoes,
    T.valor_total_prescricoes,
    ROW_NUMBER() OVER (
        PARTITION BY C.id_cnpj, C.ano_base
        ORDER BY C.valor_crm_ano DESC, C.id_medico ASC
    ) AS ranking_valor
INTO #CrmAnoRanked
FROM #CrmAno AS C
INNER JOIN #TotaisAno AS T
    ON T.id_cnpj = C.id_cnpj
   AND T.ano_base = C.ano_base;

CREATE CLUSTERED INDEX IDX_CrmAnoRanked_CNPJ_Ano
ON #CrmAnoRanked(id_cnpj, ano_base, ranking_valor);


-- ============================================================================
-- PASSO 4: CALCULO BASE POR FARMACIA/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crm_hhi;

SELECT
    R.id_cnpj,
    R.ano_base,
    MAX(R.total_prescritores) AS total_prescritores,
    MAX(R.total_prescricoes) AS total_prescricoes,
    CAST(MAX(R.valor_total_prescricoes) AS DECIMAL(19,2)) AS valor_total_prescricoes,
    CAST(SUM(CASE WHEN R.ranking_valor = 1 THEN R.valor_crm_ano ELSE CAST(0 AS DECIMAL(19,2)) END) AS DECIMAL(19,2)) AS valor_top1,
    CAST(SUM(CASE WHEN R.ranking_valor <= 5 THEN R.valor_crm_ano ELSE CAST(0 AS DECIMAL(19,2)) END) AS DECIMAL(19,2)) AS valor_top5,
    CAST(
        SUM(CASE WHEN R.ranking_valor = 1 THEN R.valor_crm_ano ELSE CAST(0 AS DECIMAL(19,2)) END) * 100.0
        / NULLIF(MAX(R.valor_total_prescricoes), 0)
    AS DECIMAL(18,4)) AS participacao_top1_pct,
    CAST(
        SUM(CASE WHEN R.ranking_valor <= 5 THEN R.valor_crm_ano ELSE CAST(0 AS DECIMAL(19,2)) END) * 100.0
        / NULLIF(MAX(R.valor_total_prescricoes), 0)
    AS DECIMAL(18,4)) AS participacao_top5_pct,
    CAST(
        SUM(
            POWER(
                CAST(R.valor_crm_ano AS DECIMAL(19,4))
                / NULLIF(CAST(R.valor_total_prescricoes AS DECIMAL(19,4)), 0)
                * 100.0,
                2
            )
        )
    AS DECIMAL(18,4)) AS indice_hhi
INTO temp_CGUSC.fp.indicador_crm_hhi
FROM #CrmAnoRanked AS R
GROUP BY
    R.id_cnpj,
    R.ano_base;

IF NOT EXISTS (SELECT 1 FROM temp_CGUSC.fp.indicador_crm_hhi)
BEGIN
    RAISERROR('Nao ha farmacias/ano com valor total positivo para indicador CRM HHI.', 16, 1);
    RETURN;
END;

CREATE UNIQUE CLUSTERED INDEX IDX_IndCrmHHI_CNPJ_Ano
ON temp_CGUSC.fp.indicador_crm_hhi(id_cnpj, ano_base);


-- ============================================================================
-- PASSO 5: TABELA CONSOLIDADA FINAL POR CNPJ/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crm_hhi_detalhado;

SELECT
    I.id_cnpj,
    I.ano_base,
    CAST(I.total_prescritores AS INT) AS total_prescritores,
    CAST(I.total_prescricoes AS BIGINT) AS total_prescricoes,
    CAST(I.valor_total_prescricoes AS DECIMAL(19,2)) AS valor_total_prescricoes,
    CAST(I.valor_top1 AS DECIMAL(19,2)) AS valor_top1,
    CAST(I.valor_top5 AS DECIMAL(19,2)) AS valor_top5,
    CAST(I.participacao_top1_pct AS DECIMAL(18,4)) AS participacao_top1_pct,
    CAST(I.participacao_top5_pct AS DECIMAL(18,4)) AS participacao_top5_pct,
    CAST(I.indice_hhi AS DECIMAL(18,4)) AS indice_hhi
INTO temp_CGUSC.fp.indicador_crm_hhi_detalhado
FROM temp_CGUSC.fp.indicador_crm_hhi AS I;

CREATE UNIQUE CLUSTERED INDEX IDX_FinalCrmHHI_CNPJ_Ano
ON temp_CGUSC.fp.indicador_crm_hhi_detalhado(id_cnpj, ano_base);


-- ============================================================================
-- LIMPEZA DAS TABELAS INTERMEDIARIAS
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crm_hhi;
DROP TABLE IF EXISTS #CrmAnoRanked;
DROP TABLE IF EXISTS #TotaisAno;
DROP TABLE IF EXISTS #CrmAno;
DROP TABLE IF EXISTS #farmacias_dim;
GO
