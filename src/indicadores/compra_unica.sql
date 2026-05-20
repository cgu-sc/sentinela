USE [temp_CGUSC]
GO

-- ============================================================================
-- INDICADOR DE COMPRA UNICA
-- ============================================================================
-- OBJETIVO: Identificar farmacias com alta proporcao de CPFs que tiveram
--           somente uma compra no estabelecimento em cada ano.
--
-- VALOR FINAL:
--   pct_compra_unica representa o percentual anual de CPFs distintos com
--   apenas uma autorizacao na farmacia.
--
-- FONTE DE DADOS:
--   - db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024
--   - temp_CGUSC.fp.medicamentos_patologia (universo de medicamentos auditados)
--   - temp_CGUSC.fp.dados_farmacia (id_cnpj e contexto territorial)
-- ============================================================================

-- ============================================================================
-- DEFINICAO DE VARIAVEIS
-- ============================================================================
DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim    DATE = '2024-12-10';


-- ============================================================================
-- PASSO 0: DIMENSOES OBRIGATORIAS
-- ============================================================================
IF OBJECT_ID('temp_CGUSC.fp.medicamentos_patologia', 'U') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.medicamentos_patologia nao encontrada.', 16, 1);
    RETURN;
END;

IF COL_LENGTH('temp_CGUSC.fp.medicamentos_patologia', 'codigo_barra') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.medicamentos_patologia sem coluna obrigatoria codigo_barra.', 16, 1);
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

DROP TABLE IF EXISTS #medicamentos_patologia_gtin;

SELECT DISTINCT
    C.codigo_barra
INTO #medicamentos_patologia_gtin
FROM temp_CGUSC.fp.medicamentos_patologia C
WHERE C.codigo_barra IS NOT NULL;

IF NOT EXISTS (SELECT 1 FROM #medicamentos_patologia_gtin)
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.medicamentos_patologia sem codigo_barra valido.', 16, 1);
    RETURN;
END;

CREATE UNIQUE CLUSTERED INDEX IDX_medicamentos_patologia_gtin
ON #medicamentos_patologia_gtin(codigo_barra);


-- ============================================================================
-- PASSO 1: RECORRENCIA POR CPF EM CADA FARMACIA/ANO
-- Paciente de compra unica = CPF com apenas uma autorizacao na farmacia no ano.
-- ============================================================================
DROP TABLE IF EXISTS #RecorrenciaPorCPF;

SELECT
    F.id_cnpj,
    CAST(YEAR(A.data_hora) AS SMALLINT) AS ano_base,
    CAST(A.cpf AS VARCHAR(11)) AS cpf,
    CAST(COUNT(DISTINCT A.num_autorizacao) AS INT) AS qtd_compras_cpf
INTO #RecorrenciaPorCPF
FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
INNER JOIN #farmacias_dim F
    ON F.cnpj = A.cnpj
INNER JOIN #medicamentos_patologia_gtin C
    ON C.codigo_barra = A.codigo_barra
WHERE A.data_hora >= @DataInicio
  AND A.data_hora < DATEADD(DAY, 1, @DataFim)
  AND NULLIF(LTRIM(RTRIM(CAST(A.cpf AS VARCHAR(20)))), '') IS NOT NULL
  AND A.num_autorizacao IS NOT NULL
GROUP BY
    F.id_cnpj,
    YEAR(A.data_hora),
    CAST(A.cpf AS VARCHAR(11));

CREATE CLUSTERED INDEX IDX_TempRecorrencia_CNPJ_Ano
ON #RecorrenciaPorCPF(id_cnpj, ano_base, cpf);

DROP TABLE IF EXISTS #medicamentos_patologia_gtin;


-- ============================================================================
-- PASSO 2: CALCULO BASE POR FARMACIA/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_compra_unica;

SELECT
    id_cnpj,
    ano_base,
    CAST(COUNT(*) AS INT) AS total_cpfs_distintos,
    CAST(SUM(CASE WHEN qtd_compras_cpf = 1 THEN 1 ELSE 0 END) AS INT) AS qtd_cpfs_compra_unica,
    CAST(
        CASE
            WHEN COUNT(*) > 0 THEN
                (CAST(SUM(CASE WHEN qtd_compras_cpf = 1 THEN 1 ELSE 0 END) AS DECIMAL(18,2)) /
                 CAST(COUNT(*) AS DECIMAL(18,2))) * 100.0
            ELSE 0
        END
    AS DECIMAL(7,4)) AS pct_compra_unica
INTO temp_CGUSC.fp.indicador_compra_unica
FROM #RecorrenciaPorCPF
GROUP BY id_cnpj, ano_base;

CREATE UNIQUE CLUSTERED INDEX IDX_IndCompraUnica_CNPJ
ON temp_CGUSC.fp.indicador_compra_unica(id_cnpj, ano_base);

DROP TABLE IF EXISTS #RecorrenciaPorCPF;


-- ============================================================================
-- PASSO 3: METRICAS POR MUNICIPIO (MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_compra_unica_mun;

SELECT DISTINCT
    I.ano_base,
    F.uf,
    F.municipio,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.pct_compra_unica)
        OVER (PARTITION BY I.ano_base, F.uf, F.municipio)
    AS DECIMAL(7,4)) AS mediana_municipio
INTO temp_CGUSC.fp.indicador_compra_unica_mun
FROM temp_CGUSC.fp.indicador_compra_unica I
INNER JOIN #farmacias_dim F
    ON F.id_cnpj = I.id_cnpj;

CREATE CLUSTERED INDEX IDX_IndCompraUnicaMun
ON temp_CGUSC.fp.indicador_compra_unica_mun(ano_base, uf, municipio);


-- ============================================================================
-- PASSO 4: METRICAS POR ESTADO (MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_compra_unica_uf;

SELECT DISTINCT
    I.ano_base,
    F.uf,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.pct_compra_unica)
        OVER (PARTITION BY I.ano_base, F.uf)
    AS DECIMAL(7,4)) AS mediana_estado
INTO temp_CGUSC.fp.indicador_compra_unica_uf
FROM temp_CGUSC.fp.indicador_compra_unica I
INNER JOIN #farmacias_dim F
    ON F.id_cnpj = I.id_cnpj;

CREATE CLUSTERED INDEX IDX_IndCompraUnicaUF
ON temp_CGUSC.fp.indicador_compra_unica_uf(ano_base, uf);


-- ============================================================================
-- PASSO 4B: METRICAS POR REGIAO DE SAUDE (MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_compra_unica_regiao;

SELECT DISTINCT
    I.ano_base,
    F.id_regiao_saude,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.pct_compra_unica)
        OVER (PARTITION BY I.ano_base, F.id_regiao_saude)
    AS DECIMAL(7,4)) AS mediana_regiao
INTO temp_CGUSC.fp.indicador_compra_unica_regiao
FROM temp_CGUSC.fp.indicador_compra_unica I
INNER JOIN #farmacias_dim F
    ON F.id_cnpj = I.id_cnpj
WHERE F.id_regiao_saude IS NOT NULL;

CREATE CLUSTERED INDEX IDX_IndCompraUnicaReg
ON temp_CGUSC.fp.indicador_compra_unica_regiao(ano_base, id_regiao_saude);


-- ============================================================================
-- PASSO 5: METRICAS NACIONAIS (MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_compra_unica_br;

SELECT DISTINCT
    ano_base,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY pct_compra_unica)
        OVER (PARTITION BY ano_base)
    AS DECIMAL(7,4)) AS mediana_pais
INTO temp_CGUSC.fp.indicador_compra_unica_br
FROM temp_CGUSC.fp.indicador_compra_unica;

CREATE CLUSTERED INDEX IDX_IndCompraUnicaBR
ON temp_CGUSC.fp.indicador_compra_unica_br(ano_base);


-- ============================================================================
-- PASSO 6: TABELA CONSOLIDADA FINAL
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_compra_unica_detalhado;

SELECT
    I.id_cnpj,
    I.ano_base,

    -- Indicadores base
    I.total_cpfs_distintos,
    I.qtd_cpfs_compra_unica,
    I.pct_compra_unica,

    -- Benchmarks municipais
    ISNULL(MUN.mediana_municipio, 0) AS municipio_mediana,
    CAST((I.pct_compra_unica + 0.01) / (ISNULL(MUN.mediana_municipio, 0) + 0.01) AS DECIMAL(9,4)) AS risco_relativo_mun_mediana,

    -- Benchmarks estaduais
    ISNULL(UF.mediana_estado, 0) AS estado_mediana,
    CAST((I.pct_compra_unica + 0.01) / (ISNULL(UF.mediana_estado, 0) + 0.01) AS DECIMAL(9,4)) AS risco_relativo_uf_mediana,

    -- Benchmarks Regionais (Regiao de Saude)
    ISNULL(REG.mediana_regiao, 0) AS regiao_saude_mediana,
    CAST((I.pct_compra_unica + 0.01) / (ISNULL(REG.mediana_regiao, 0) + 0.01) AS DECIMAL(9,4)) AS risco_relativo_reg_mediana,

    -- Benchmarks nacionais
    BR.mediana_pais AS pais_mediana,
    CAST((I.pct_compra_unica + 0.01) / (BR.mediana_pais + 0.01) AS DECIMAL(9,4)) AS risco_relativo_br_mediana
INTO temp_CGUSC.fp.indicador_compra_unica_detalhado
FROM temp_CGUSC.fp.indicador_compra_unica I
INNER JOIN #farmacias_dim F
    ON F.id_cnpj = I.id_cnpj
LEFT JOIN temp_CGUSC.fp.indicador_compra_unica_mun MUN
    ON I.ano_base = MUN.ano_base
   AND F.uf = MUN.uf
   AND F.municipio = MUN.municipio
LEFT JOIN temp_CGUSC.fp.indicador_compra_unica_uf UF
    ON I.ano_base = UF.ano_base
   AND F.uf = UF.uf
LEFT JOIN temp_CGUSC.fp.indicador_compra_unica_regiao REG
    ON I.ano_base = REG.ano_base
   AND F.id_regiao_saude = REG.id_regiao_saude
INNER JOIN temp_CGUSC.fp.indicador_compra_unica_br BR
    ON I.ano_base = BR.ano_base;

CREATE UNIQUE CLUSTERED INDEX IDX_FinalCompraUnica_CNPJ
ON temp_CGUSC.fp.indicador_compra_unica_detalhado(id_cnpj, ano_base);

CREATE NONCLUSTERED INDEX IDX_FinalCompraUnica_Risco
ON temp_CGUSC.fp.indicador_compra_unica_detalhado(ano_base, risco_relativo_mun_mediana DESC);


-- ============================================================================
-- LIMPEZA DAS TABELAS INTERMEDIARIAS
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_compra_unica;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_compra_unica_mun;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_compra_unica_uf;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_compra_unica_regiao;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_compra_unica_br;
DROP TABLE IF EXISTS #farmacias_dim;
GO
