USE [temp_CGUSC]
GO

-- ============================================================================
-- INDICADOR DE VOLUME ATIPICO DE FATURAMENTO
-- ============================================================================
-- OBJETIVO: Consolidar, por ano e territorio, os componentes do crescimento
--           semestral atipico calculado em temp_CGUSC.fp.volume_atipico_semestral.
--
-- METRICA PRINCIPAL:
--   O indicador deve ser calculado por periodo a partir dos componentes:
--   soma_excesso_crescimento_pct / total_semestres_comparaveis.
--
-- CRITERIO DE SEMESTRE ATIPICO:
--   taxa_crescimento_pct > @LimiteCrescimentoPct
--   AND aumento_valor_semestre >= @LimiteAumentoValor
--
-- FONTE DE DADOS:
--   - temp_CGUSC.fp.volume_atipico_semestral
--   - temp_CGUSC.fp.dados_farmacia
-- ============================================================================

-- ============================================================================
-- LIMPEZA PREVIA DE TABELAS FINAIS/DERIVADAS
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_volume_atipico;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_volume_atipico_mun;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_volume_atipico_uf;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_volume_atipico_regiao;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_volume_atipico_br;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_volume_atipico_detalhado;
GO

-- ============================================================================
-- DEFINICAO DE VARIAVEIS
-- ============================================================================
DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim    DATE = '2024-12-31';
DECLARE @LimiteCrescimentoPct DECIMAL(9,2) = 50.00;
DECLARE @LimiteAumentoValor   DECIMAL(9,2) = 10000.00;

DECLARE @ChaveSemestreInicio INT =
    (YEAR(@DataInicio) * 100) + CAST(CASE WHEN MONTH(@DataInicio) BETWEEN 1 AND 6 THEN 1 ELSE 2 END AS INT);

DECLARE @ChaveSemestreFim INT =
    (YEAR(@DataFim) * 100) + CAST(CASE WHEN MONTH(@DataFim) BETWEEN 1 AND 6 THEN 1 ELSE 2 END AS INT);


-- ============================================================================
-- PASSO 0: DIMENSOES E FONTES OBRIGATORIAS
-- ============================================================================
IF OBJECT_ID('temp_CGUSC.fp.volume_atipico_semestral', 'U') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.volume_atipico_semestral nao encontrada. Execute volume_atipico_semestral.sql antes deste script.', 16, 1);
    RETURN;
END;

IF COL_LENGTH('temp_CGUSC.fp.volume_atipico_semestral', 'id_cnpj') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.volume_atipico_semestral', 'chave_semestre') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.volume_atipico_semestral', 'status_semestre') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.volume_atipico_semestral', 'qtd_meses_presentes') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.volume_atipico_semestral', 'chave_semestre_anterior') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.volume_atipico_semestral', 'aumento_valor_semestre') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.volume_atipico_semestral', 'taxa_crescimento_pct') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.volume_atipico_semestral sem colunas obrigatorias para volume atipico.', 16, 1);
    RETURN;
END;

IF EXISTS (
    SELECT 1
    FROM temp_CGUSC.fp.volume_atipico_semestral
    GROUP BY id_cnpj, chave_semestre
    HAVING COUNT_BIG(*) > 1
)
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.volume_atipico_semestral possui duplicidade por id_cnpj/chave_semestre.', 16, 1);
    RETURN;
END;

IF EXISTS (
    SELECT 1
    FROM temp_CGUSC.fp.volume_atipico_semestral
    WHERE id_cnpj IS NULL
       OR chave_semestre IS NULL
       OR status_semestre IS NULL
       OR status_semestre NOT IN (1, 2, 3, 4)
       OR chave_semestre % 100 NOT IN (1, 2)
)
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.volume_atipico_semestral possui chaves/status invalidos.', 16, 1);
    RETURN;
END;

IF EXISTS (
    SELECT 1
    FROM temp_CGUSC.fp.volume_atipico_semestral
    WHERE status_semestre = 1
      AND (
            chave_semestre_anterior IS NULL
         OR aumento_valor_semestre IS NULL
         OR taxa_crescimento_pct IS NULL
      )
)
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.volume_atipico_semestral possui semestre comparavel sem crescimento/aumento calculado.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('temp_CGUSC.fp.dados_farmacia', 'U') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.dados_farmacia nao encontrada.', 16, 1);
    RETURN;
END;

IF COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'id') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'cnpj') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'municipio') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'uf') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'id_regiao_saude') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.dados_farmacia sem colunas obrigatorias id/cnpj/municipio/uf/id_regiao_saude.', 16, 1);
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

DROP TABLE IF EXISTS #farmacias_dim;

SELECT
    CAST(F.id AS INT) AS id_cnpj,
    CAST(F.cnpj AS VARCHAR(14)) AS cnpj,
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

IF EXISTS (
    SELECT 1
    FROM temp_CGUSC.fp.volume_atipico_semestral S
    LEFT JOIN #farmacias_dim F
        ON F.id_cnpj = S.id_cnpj
    WHERE F.id_cnpj IS NULL
)
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.volume_atipico_semestral possui id_cnpj sem correspondencia em temp_CGUSC.fp.dados_farmacia.', 16, 1);
    RETURN;
END;


-- ============================================================================
-- PASSO 0B: LIMITES DE ARMAZENAMENTO DOS COMPONENTES
-- ============================================================================
IF EXISTS (
    SELECT 1
    FROM temp_CGUSC.fp.volume_atipico_semestral
    WHERE status_semestre = 1
      AND chave_semestre BETWEEN @ChaveSemestreInicio AND @ChaveSemestreFim
      AND (
            aumento_valor_semestre > 9999999.99
         OR aumento_valor_semestre < -9999999.99
         OR taxa_crescimento_pct > 9999999.99
         OR taxa_crescimento_pct < -9999999.99
      )
)
BEGIN
    RAISERROR('Volume atipico possui componentes semestrais fora do contrato DECIMAL(9,2).', 16, 1);
    RETURN;
END;


-- ============================================================================
-- PASSO 1: COMPONENTES SEMESTRAIS COMPARAVEIS
-- ============================================================================
DROP TABLE IF EXISTS #volume_componentes_semestrais;

SELECT
    S.id_cnpj,
    CAST(S.chave_semestre / 100 AS SMALLINT) AS ano_base,
    CAST(1 AS TINYINT) AS total_semestres_comparaveis,
    CAST(
        CASE
            WHEN S.taxa_crescimento_pct > @LimiteCrescimentoPct
             AND S.aumento_valor_semestre >= @LimiteAumentoValor THEN 1
            ELSE 0
        END
    AS TINYINT) AS total_semestres_atipicos,
    CAST(
        CASE
            WHEN S.taxa_crescimento_pct > @LimiteCrescimentoPct
             AND S.aumento_valor_semestre >= @LimiteAumentoValor
                THEN S.taxa_crescimento_pct - @LimiteCrescimentoPct
            ELSE 0
        END
    AS DECIMAL(9,2)) AS excesso_crescimento_pct,
    CAST(
        CASE
            WHEN S.aumento_valor_semestre > 0 THEN S.aumento_valor_semestre
            ELSE 0
        END
    AS DECIMAL(9,2)) AS valor_aumento,
    CAST(
        CASE
            WHEN S.taxa_crescimento_pct > @LimiteCrescimentoPct
             AND S.aumento_valor_semestre >= @LimiteAumentoValor
                THEN S.aumento_valor_semestre
            ELSE 0
        END
    AS DECIMAL(9,2)) AS valor_aumento_atipico,
    CAST(S.taxa_crescimento_pct AS DECIMAL(9,2)) AS taxa_crescimento_pct
INTO #volume_componentes_semestrais
FROM temp_CGUSC.fp.volume_atipico_semestral S
WHERE S.status_semestre = 1
  AND S.chave_semestre BETWEEN @ChaveSemestreInicio AND @ChaveSemestreFim;

IF NOT EXISTS (SELECT 1 FROM #volume_componentes_semestrais)
BEGIN
    RAISERROR('Nao ha semestres comparaveis em temp_CGUSC.fp.volume_atipico_semestral no periodo informado.', 16, 1);
    RETURN;
END;

CREATE CLUSTERED INDEX IDX_VolCompSem_CNPJ_Ano
ON #volume_componentes_semestrais(id_cnpj, ano_base);

IF EXISTS (
    SELECT 1
    FROM #volume_componentes_semestrais C
    GROUP BY
        C.id_cnpj,
        C.ano_base
    HAVING SUM(C.excesso_crescimento_pct) > 9999999.99
        OR SUM(C.valor_aumento) > 9999999.99
        OR SUM(C.valor_aumento_atipico) > 9999999.99
)
BEGIN
    RAISERROR('Volume atipico possui totais anuais fora do contrato DECIMAL(9,2).', 16, 1);
    RETURN;
END;


-- ============================================================================
-- PASSO 2: CALCULO BASE POR FARMACIA/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_volume_atipico;

SELECT
    C.id_cnpj,
    C.ano_base,
    CAST(SUM(C.total_semestres_comparaveis) AS TINYINT) AS total_semestres_comparaveis,
    CAST(SUM(C.total_semestres_atipicos) AS TINYINT) AS total_semestres_atipicos,
    CAST(SUM(C.excesso_crescimento_pct) AS DECIMAL(9,2)) AS soma_excesso_crescimento_pct,
    CAST(SUM(C.valor_aumento) AS DECIMAL(9,2)) AS valor_aumento_total,
    CAST(SUM(C.valor_aumento_atipico) AS DECIMAL(9,2)) AS valor_aumento_atipico,
    CAST(MAX(C.taxa_crescimento_pct) AS DECIMAL(9,2)) AS maior_taxa_crescimento_pct
INTO temp_CGUSC.fp.indicador_volume_atipico
FROM #volume_componentes_semestrais C
GROUP BY
    C.id_cnpj,
    C.ano_base;

CREATE UNIQUE CLUSTERED INDEX IDX_IndVol_CNPJ_Ano
ON temp_CGUSC.fp.indicador_volume_atipico(id_cnpj, ano_base);


-- ============================================================================
-- PASSO 3: TABELA CONSOLIDADA FINAL POR CNPJ/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_volume_atipico_detalhado;

SELECT
    I.id_cnpj,
    I.ano_base,
    I.total_semestres_comparaveis,
    I.total_semestres_atipicos,
    I.soma_excesso_crescimento_pct,
    I.valor_aumento_total,
    I.valor_aumento_atipico,
    I.maior_taxa_crescimento_pct
INTO temp_CGUSC.fp.indicador_volume_atipico_detalhado
FROM temp_CGUSC.fp.indicador_volume_atipico I;

CREATE UNIQUE CLUSTERED INDEX IDX_FinalVol_CNPJ
ON temp_CGUSC.fp.indicador_volume_atipico_detalhado(id_cnpj, ano_base);


-- ============================================================================
-- PASSO 4: AGREGADO POR REGIAO DE SAUDE/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_volume_atipico_regiao;

SELECT
    I.ano_base,
    F.id_regiao_saude,
    CAST(SUM(I.total_semestres_comparaveis) AS INT) AS total_semestres_comparaveis,
    CAST(SUM(I.total_semestres_atipicos) AS INT) AS total_semestres_atipicos,
    CAST(SUM(I.soma_excesso_crescimento_pct) AS DECIMAL(19,2)) AS soma_excesso_crescimento_pct,
    CAST(SUM(I.valor_aumento_total) AS DECIMAL(19,2)) AS valor_aumento_total,
    CAST(SUM(I.valor_aumento_atipico) AS DECIMAL(19,2)) AS valor_aumento_atipico,
    CAST(MAX(I.maior_taxa_crescimento_pct) AS DECIMAL(9,2)) AS maior_taxa_crescimento_pct,
    CAST(COUNT_BIG(*) AS INT) AS qtd_cnpjs
INTO temp_CGUSC.fp.indicador_volume_atipico_regiao
FROM temp_CGUSC.fp.indicador_volume_atipico I
INNER JOIN #farmacias_dim F
    ON F.id_cnpj = I.id_cnpj
GROUP BY
    I.ano_base,
    F.id_regiao_saude;

CREATE UNIQUE CLUSTERED INDEX IDX_IndVolReg
ON temp_CGUSC.fp.indicador_volume_atipico_regiao(ano_base, id_regiao_saude);


-- ============================================================================
-- PASSO 5: AGREGADO POR UF/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_volume_atipico_uf;

SELECT
    I.ano_base,
    F.uf,
    CAST(SUM(I.total_semestres_comparaveis) AS INT) AS total_semestres_comparaveis,
    CAST(SUM(I.total_semestres_atipicos) AS INT) AS total_semestres_atipicos,
    CAST(SUM(I.soma_excesso_crescimento_pct) AS DECIMAL(19,2)) AS soma_excesso_crescimento_pct,
    CAST(SUM(I.valor_aumento_total) AS DECIMAL(19,2)) AS valor_aumento_total,
    CAST(SUM(I.valor_aumento_atipico) AS DECIMAL(19,2)) AS valor_aumento_atipico,
    CAST(MAX(I.maior_taxa_crescimento_pct) AS DECIMAL(9,2)) AS maior_taxa_crescimento_pct,
    CAST(COUNT_BIG(*) AS INT) AS qtd_cnpjs
INTO temp_CGUSC.fp.indicador_volume_atipico_uf
FROM temp_CGUSC.fp.indicador_volume_atipico I
INNER JOIN #farmacias_dim F
    ON F.id_cnpj = I.id_cnpj
GROUP BY
    I.ano_base,
    F.uf;

CREATE UNIQUE CLUSTERED INDEX IDX_IndVolUF
ON temp_CGUSC.fp.indicador_volume_atipico_uf(ano_base, uf);


-- ============================================================================
-- PASSO 6: AGREGADO BRASIL/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_volume_atipico_br;

SELECT
    I.ano_base,
    CAST(SUM(I.total_semestres_comparaveis) AS INT) AS total_semestres_comparaveis,
    CAST(SUM(I.total_semestres_atipicos) AS INT) AS total_semestres_atipicos,
    CAST(SUM(I.soma_excesso_crescimento_pct) AS DECIMAL(19,2)) AS soma_excesso_crescimento_pct,
    CAST(SUM(I.valor_aumento_total) AS DECIMAL(19,2)) AS valor_aumento_total,
    CAST(SUM(I.valor_aumento_atipico) AS DECIMAL(19,2)) AS valor_aumento_atipico,
    CAST(MAX(I.maior_taxa_crescimento_pct) AS DECIMAL(9,2)) AS maior_taxa_crescimento_pct,
    CAST(COUNT_BIG(*) AS INT) AS qtd_cnpjs
INTO temp_CGUSC.fp.indicador_volume_atipico_br
FROM temp_CGUSC.fp.indicador_volume_atipico I
GROUP BY
    I.ano_base;

CREATE UNIQUE CLUSTERED INDEX IDX_IndVolBR
ON temp_CGUSC.fp.indicador_volume_atipico_br(ano_base);
GO


-- ============================================================================
-- LIMPEZA DAS TABELAS INTERMEDIARIAS
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_volume_atipico;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_volume_atipico_mun;
DROP TABLE IF EXISTS #volume_componentes_semestrais;
DROP TABLE IF EXISTS #farmacias_dim;
GO
