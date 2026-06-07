USE [temp_CGUSC]
GO

-- ============================================================================
-- INDICADOR DE AUDITORIA FINANCEIRA
-- ============================================================================
-- OBJETIVO: Calcular, por farmacia e ano, o percentual de vendas sem
--           comprovacao em relacao ao valor total movimentado no PFPB.
--
-- METRICA PRINCIPAL:
--   pct_auditado = valor_sem_comprovacao / valor_total_auditado * 100.
--
-- FONTE DE DADOS:
--   - temp_CGUSC.fp.movimentacao_mensal_cnpj
--   - temp_CGUSC.fp.dados_farmacia (id_cnpj e contexto territorial)
--
-- OBSERVACAO METODOLOGICA:
--   Os riscos relativos preservam a mesma estabilizacao historica do indicador:
--   soma-se 0,0001 ao numerador e ao denominador para permitir comparacao
--   quando a mediana territorial e zero.
-- ============================================================================

-- ============================================================================
-- LIMPEZA PREVIA DE TABELAS
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_auditado;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_auditado_mun;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_auditado_uf;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_auditado_regiao;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_auditado_br;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_auditado_detalhado;
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
   OR COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'razaoSocial') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'municipio') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'uf') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'id_regiao_saude') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.dados_farmacia sem colunas obrigatorias id/cnpj/razaoSocial/municipio/uf/id_regiao_saude.', 16, 1);
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

IF OBJECT_ID('temp_CGUSC.fp.movimentacao_mensal_cnpj', 'U') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.movimentacao_mensal_cnpj nao encontrada.', 16, 1);
    RETURN;
END;

IF COL_LENGTH('temp_CGUSC.fp.movimentacao_mensal_cnpj', 'cnpj') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.movimentacao_mensal_cnpj', 'periodo') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.movimentacao_mensal_cnpj', 'total_vendas') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.movimentacao_mensal_cnpj', 'total_sem_comprovacao') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.movimentacao_mensal_cnpj', 'total_qnt_caixas_vendidas') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.movimentacao_mensal_cnpj', 'total_qnt_caixas_sem_comprovacao') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.movimentacao_mensal_cnpj', 'total_num_autorizacoes') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.movimentacao_mensal_cnpj sem colunas obrigatorias para o indicador auditado.', 16, 1);
    RETURN;
END;

IF EXISTS (
    SELECT 1
    FROM temp_CGUSC.fp.movimentacao_mensal_cnpj AS M
    WHERE M.cnpj IS NULL
       OR M.periodo IS NULL
       OR M.total_vendas IS NULL
       OR M.total_sem_comprovacao IS NULL
       OR M.total_qnt_caixas_vendidas IS NULL
       OR M.total_qnt_caixas_sem_comprovacao IS NULL
       OR M.total_num_autorizacoes IS NULL
)
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.movimentacao_mensal_cnpj possui valores obrigatorios nulos.', 16, 1);
    RETURN;
END;

IF EXISTS (
    SELECT 1
    FROM temp_CGUSC.fp.movimentacao_mensal_cnpj AS M
    LEFT JOIN temp_CGUSC.fp.dados_farmacia AS F
        ON F.cnpj = M.cnpj
    WHERE F.id IS NULL
)
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.movimentacao_mensal_cnpj possui CNPJs sem id correspondente em dados_farmacia.', 16, 1);
    RETURN;
END;

DROP TABLE IF EXISTS #farmacias_dim;

SELECT
    CAST(F.id AS INT) AS id_cnpj,
    CAST(F.cnpj AS VARCHAR(14)) AS cnpj,
    CAST(F.razaoSocial AS VARCHAR(255)) AS razaoSocial,
    CAST(F.municipio AS VARCHAR(255)) AS municipio,
    CAST(UPPER(LTRIM(RTRIM(F.uf))) AS VARCHAR(2)) AS uf,
    CAST(F.id_regiao_saude AS INT) AS id_regiao_saude
INTO #farmacias_dim
FROM temp_CGUSC.fp.dados_farmacia AS F;

IF EXISTS (
    SELECT 1
    FROM #farmacias_dim
    WHERE id_cnpj IS NULL
       OR NULLIF(LTRIM(RTRIM(cnpj)), '') IS NULL
       OR NULLIF(LTRIM(RTRIM(razaoSocial)), '') IS NULL
       OR NULLIF(LTRIM(RTRIM(municipio)), '') IS NULL
       OR NULLIF(LTRIM(RTRIM(uf)), '') IS NULL
       OR id_regiao_saude IS NULL
)
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.dados_farmacia possui valores obrigatorios nulos para contexto territorial.', 16, 1);
    RETURN;
END;

CREATE UNIQUE CLUSTERED INDEX IDX_farmacias_dim_cnpj
ON #farmacias_dim(cnpj);

CREATE UNIQUE NONCLUSTERED INDEX IDX_farmacias_dim_id
ON #farmacias_dim(id_cnpj);


-- ============================================================================
-- PASSO 1: CALCULO BASE POR FARMACIA/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_auditado;

SELECT
    F.id_cnpj,
    CAST(YEAR(M.periodo) AS SMALLINT) AS ano_base,
    MIN(CAST(M.periodo AS DATE)) AS periodo_min,
    MAX(CAST(M.periodo AS DATE)) AS periodo_max,
    CAST(SUM(CAST(M.total_vendas AS DECIMAL(19,2))) AS DECIMAL(19,2)) AS valor_total_auditado,
    CAST(SUM(CAST(M.total_sem_comprovacao AS DECIMAL(19,2))) AS DECIMAL(19,2)) AS valor_sem_comprovacao,
    CAST(SUM(CAST(M.total_qnt_caixas_vendidas AS BIGINT)) AS BIGINT) AS total_caixas_vendidas,
    CAST(SUM(CAST(M.total_qnt_caixas_sem_comprovacao AS BIGINT)) AS BIGINT) AS total_caixas_sem_comprovacao,
    CAST(SUM(CAST(M.total_num_autorizacoes AS BIGINT)) AS BIGINT) AS total_autorizacoes,
    CAST(
        (SUM(CAST(M.total_sem_comprovacao AS DECIMAL(19,2))) * 100.0)
        / NULLIF(SUM(CAST(M.total_vendas AS DECIMAL(19,2))), 0)
    AS DECIMAL(18,4)) AS pct_auditado
INTO temp_CGUSC.fp.indicador_auditado
FROM temp_CGUSC.fp.movimentacao_mensal_cnpj AS M
INNER JOIN #farmacias_dim AS F
    ON F.cnpj = M.cnpj
GROUP BY
    F.id_cnpj,
    YEAR(M.periodo)
HAVING SUM(CAST(M.total_vendas AS DECIMAL(19,2))) > 0;

IF NOT EXISTS (SELECT 1 FROM temp_CGUSC.fp.indicador_auditado)
BEGIN
    RAISERROR('Nao ha movimentacao anual com valor_total_auditado positivo para o indicador auditado.', 16, 1);
    RETURN;
END;

CREATE UNIQUE CLUSTERED INDEX IDX_IndAudit_CNPJ_Ano
ON temp_CGUSC.fp.indicador_auditado(id_cnpj, ano_base);


-- ============================================================================
-- PASSO 2: METRICAS POR MUNICIPIO/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_auditado_mun;

SELECT DISTINCT
    I.ano_base,
    F.uf,
    F.municipio,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.pct_auditado)
        OVER (PARTITION BY I.ano_base, F.uf, F.municipio)
    AS DECIMAL(18,4)) AS mediana_municipio,
    CAST(COUNT_BIG(*) OVER (PARTITION BY I.ano_base, F.uf, F.municipio) AS INT) AS qtd_cnpjs
INTO temp_CGUSC.fp.indicador_auditado_mun
FROM temp_CGUSC.fp.indicador_auditado AS I
INNER JOIN #farmacias_dim AS F
    ON F.id_cnpj = I.id_cnpj;

CREATE UNIQUE CLUSTERED INDEX IDX_IndAuditMun
ON temp_CGUSC.fp.indicador_auditado_mun(ano_base, uf, municipio);


-- ============================================================================
-- PASSO 3: METRICAS POR ESTADO/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_auditado_uf;

SELECT DISTINCT
    I.ano_base,
    F.uf,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.pct_auditado)
        OVER (PARTITION BY I.ano_base, F.uf)
    AS DECIMAL(18,4)) AS mediana_estado,
    CAST(COUNT_BIG(*) OVER (PARTITION BY I.ano_base, F.uf) AS INT) AS qtd_cnpjs
INTO temp_CGUSC.fp.indicador_auditado_uf
FROM temp_CGUSC.fp.indicador_auditado AS I
INNER JOIN #farmacias_dim AS F
    ON F.id_cnpj = I.id_cnpj;

CREATE UNIQUE CLUSTERED INDEX IDX_IndAuditUF
ON temp_CGUSC.fp.indicador_auditado_uf(ano_base, uf);


-- ============================================================================
-- PASSO 4: METRICAS POR REGIAO DE SAUDE/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_auditado_regiao;

SELECT DISTINCT
    I.ano_base,
    F.id_regiao_saude,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.pct_auditado)
        OVER (PARTITION BY I.ano_base, F.id_regiao_saude)
    AS DECIMAL(18,4)) AS mediana_regiao,
    CAST(COUNT_BIG(*) OVER (PARTITION BY I.ano_base, F.id_regiao_saude) AS INT) AS qtd_cnpjs
INTO temp_CGUSC.fp.indicador_auditado_regiao
FROM temp_CGUSC.fp.indicador_auditado AS I
INNER JOIN #farmacias_dim AS F
    ON F.id_cnpj = I.id_cnpj;

CREATE UNIQUE CLUSTERED INDEX IDX_IndAuditReg
ON temp_CGUSC.fp.indicador_auditado_regiao(ano_base, id_regiao_saude);


-- ============================================================================
-- PASSO 5: METRICAS NACIONAIS/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_auditado_br;

SELECT DISTINCT
    I.ano_base,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.pct_auditado)
        OVER (PARTITION BY I.ano_base)
    AS DECIMAL(18,4)) AS mediana_pais,
    CAST(COUNT_BIG(*) OVER (PARTITION BY I.ano_base) AS INT) AS qtd_cnpjs
INTO temp_CGUSC.fp.indicador_auditado_br
FROM temp_CGUSC.fp.indicador_auditado AS I;

CREATE UNIQUE CLUSTERED INDEX IDX_IndAuditBR
ON temp_CGUSC.fp.indicador_auditado_br(ano_base);


-- ============================================================================
-- PASSO 6: TABELA CONSOLIDADA FINAL POR CNPJ/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_auditado_detalhado;

SELECT
    F.id_cnpj,
    F.cnpj,
    F.razaoSocial,
    F.municipio,
    F.uf,
    F.id_regiao_saude,
    I.ano_base,
    I.periodo_min,
    I.periodo_max,
    CAST(I.valor_total_auditado AS DECIMAL(19,2)) AS valor_total_auditado,
    CAST(I.valor_sem_comprovacao AS DECIMAL(19,2)) AS valor_sem_comprovacao,
    CAST(I.total_caixas_vendidas AS BIGINT) AS total_caixas_vendidas,
    CAST(I.total_caixas_sem_comprovacao AS BIGINT) AS total_caixas_sem_comprovacao,
    CAST(I.total_autorizacoes AS BIGINT) AS total_autorizacoes,
    CAST(I.pct_auditado AS DECIMAL(18,4)) AS pct_auditado,

    CAST(MUN.mediana_municipio AS DECIMAL(18,4)) AS municipio_mediana,
    CAST((I.pct_auditado + 0.0001) / (MUN.mediana_municipio + 0.0001) AS DECIMAL(18,4)) AS risco_relativo_mun_mediana,

    CAST(UF.mediana_estado AS DECIMAL(18,4)) AS estado_mediana,
    CAST((I.pct_auditado + 0.0001) / (UF.mediana_estado + 0.0001) AS DECIMAL(18,4)) AS risco_relativo_uf_mediana,

    CAST(REG.mediana_regiao AS DECIMAL(18,4)) AS regiao_saude_mediana,
    CAST((I.pct_auditado + 0.0001) / (REG.mediana_regiao + 0.0001) AS DECIMAL(18,4)) AS risco_relativo_reg_mediana,

    CAST(BR.mediana_pais AS DECIMAL(18,4)) AS pais_mediana,
    CAST((I.pct_auditado + 0.0001) / (BR.mediana_pais + 0.0001) AS DECIMAL(18,4)) AS risco_relativo_br_mediana
INTO temp_CGUSC.fp.indicador_auditado_detalhado
FROM temp_CGUSC.fp.indicador_auditado AS I
INNER JOIN #farmacias_dim AS F
    ON F.id_cnpj = I.id_cnpj
INNER JOIN temp_CGUSC.fp.indicador_auditado_mun AS MUN
    ON MUN.ano_base = I.ano_base
   AND MUN.uf = F.uf
   AND MUN.municipio = F.municipio
INNER JOIN temp_CGUSC.fp.indicador_auditado_uf AS UF
    ON UF.ano_base = I.ano_base
   AND UF.uf = F.uf
INNER JOIN temp_CGUSC.fp.indicador_auditado_regiao AS REG
    ON REG.ano_base = I.ano_base
   AND REG.id_regiao_saude = F.id_regiao_saude
INNER JOIN temp_CGUSC.fp.indicador_auditado_br AS BR
    ON BR.ano_base = I.ano_base;

CREATE UNIQUE CLUSTERED INDEX IDX_FinalAudit_CNPJ_Ano
ON temp_CGUSC.fp.indicador_auditado_detalhado(id_cnpj, ano_base);

CREATE NONCLUSTERED INDEX IDX_FinalAudit_CNPJ_Texto_Ano
ON temp_CGUSC.fp.indicador_auditado_detalhado(cnpj, ano_base);


-- ============================================================================
-- LIMPEZA DAS TABELAS INTERMEDIARIAS
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_auditado;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_auditado_mun;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_auditado_uf;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_auditado_regiao;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_auditado_br;
DROP TABLE IF EXISTS #farmacias_dim;
GO
