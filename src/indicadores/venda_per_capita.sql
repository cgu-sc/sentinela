USE [temp_CGUSC]
GO

-- ============================================================================
-- INDICADOR DE VENDA PER CAPITA
-- ============================================================================
-- OBJETIVO: Identificar farmacias com faturamento mensal por habitante do
--           municipio muito superior ao observado em estabelecimentos comparaveis.
--
-- METRICA PRINCIPAL:
--   valor_per_capita_mensal representa o faturamento mensal medio dividido pela
--   populacao do municipio da farmacia em cada ano.
--
-- FONTE DE DADOS:
--   - db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024
--   - temp_CGUSC.fp.medicamentos_patologia (universo de medicamentos auditados)
--   - temp_CGUSC.fp.dados_farmacia (id_cnpj, contexto territorial e populacao)
-- ============================================================================

-- ============================================================================
-- LIMPEZA PREVIA DE TABELAS
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.vol_vendas_per_capita;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_venda_per_capita;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_venda_per_capita_mun;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_venda_per_capita_uf;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_venda_per_capita_regiao;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_venda_per_capita_br;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_venda_per_capita_detalhado;
GO

-- ============================================================================
-- DEFINICAO DE VARIAVEIS
-- ============================================================================
DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim    DATE = '2024-12-10';


-- ============================================================================
-- PASSO 0: DIMENSOES E FONTES OBRIGATORIAS
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
   OR COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'populacao2019') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.dados_farmacia sem colunas obrigatorias id/cnpj/municipio/uf/id_regiao_saude/populacao2019.', 16, 1);
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

IF OBJECT_ID('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'U') IS NULL
BEGIN
    RAISERROR('Tabela db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 nao encontrada.', 16, 1);
    RETURN;
END;

IF COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'cnpj') IS NULL
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'valor_pago') IS NULL
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'data_hora') IS NULL
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'codigo_barra') IS NULL
BEGIN
    RAISERROR('Tabela db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 sem colunas obrigatorias para venda per capita.', 16, 1);
    RETURN;
END;

DROP TABLE IF EXISTS #farmacias_dim;

SELECT
    CAST(F.id AS INT) AS id_cnpj,
    CAST(F.cnpj AS VARCHAR(14)) AS cnpj,
    CAST(F.municipio AS VARCHAR(255)) AS municipio,
    CAST(UPPER(LTRIM(RTRIM(F.uf))) AS VARCHAR(2)) AS uf,
    CAST(F.id_regiao_saude AS INT) AS id_regiao_saude,
    CAST(F.populacao2019 AS INT) AS populacao_municipio
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
       OR populacao_municipio IS NULL
       OR populacao_municipio <= 0
)
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.dados_farmacia possui valores obrigatorios nulos/invalidos para contexto territorial ou populacao.', 16, 1);
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
-- PASSO 1: TOTAL DE VENDAS E MESES DE ATUACAO POR FARMACIA/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.vol_vendas_per_capita;

SELECT
    F.id_cnpj,
    CAST(YEAR(A.data_hora) AS SMALLINT) AS ano_base,
    CAST(SUM(CAST(A.valor_pago AS DECIMAL(19,2))) AS DECIMAL(19,2)) AS valor_total_periodo,
    CAST(COUNT(DISTINCT DATEFROMPARTS(YEAR(A.data_hora), MONTH(A.data_hora), 1)) AS TINYINT) AS qtd_meses_ativos,
    F.populacao_municipio
INTO temp_CGUSC.fp.vol_vendas_per_capita
FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
INNER JOIN #farmacias_dim F
    ON F.cnpj = A.cnpj
INNER JOIN #medicamentos_patologia_gtin C
    ON C.codigo_barra = A.codigo_barra
WHERE A.data_hora >= @DataInicio
  AND A.data_hora < DATEADD(DAY, 1, @DataFim)
  AND A.valor_pago IS NOT NULL
  AND A.codigo_barra IS NOT NULL
GROUP BY
    F.id_cnpj,
    YEAR(A.data_hora),
    F.populacao_municipio
HAVING COUNT(DISTINCT DATEFROMPARTS(YEAR(A.data_hora), MONTH(A.data_hora), 1)) > 0;

CREATE UNIQUE CLUSTERED INDEX IDX_VolCapita_CNPJ_Ano
ON temp_CGUSC.fp.vol_vendas_per_capita(id_cnpj, ano_base);

DROP TABLE IF EXISTS #medicamentos_patologia_gtin;


-- ============================================================================
-- PASSO 2: CALCULO BASE POR FARMACIA/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_venda_per_capita;

SELECT
    id_cnpj,
    ano_base,
    valor_total_periodo,
    qtd_meses_ativos,
    populacao_municipio,
    CAST(
        CAST(valor_total_periodo AS DECIMAL(19,4)) /
        (
            CAST(qtd_meses_ativos AS DECIMAL(19,4)) *
            CAST(populacao_municipio AS DECIMAL(19,4))
        )
    AS DECIMAL(19,4)) AS valor_per_capita_mensal
INTO temp_CGUSC.fp.indicador_venda_per_capita
FROM temp_CGUSC.fp.vol_vendas_per_capita;

CREATE UNIQUE CLUSTERED INDEX IDX_IndCapita_CNPJ_Ano
ON temp_CGUSC.fp.indicador_venda_per_capita(id_cnpj, ano_base);

DROP TABLE IF EXISTS temp_CGUSC.fp.vol_vendas_per_capita;


-- ============================================================================
-- PASSO 3: METRICAS POR MUNICIPIO (MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_venda_per_capita_mun;

SELECT DISTINCT
    I.ano_base,
    F.uf,
    F.municipio,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.valor_per_capita_mensal)
        OVER (PARTITION BY I.ano_base, F.uf, F.municipio)
    AS DECIMAL(19,4)) AS mediana_municipio
INTO temp_CGUSC.fp.indicador_venda_per_capita_mun
FROM temp_CGUSC.fp.indicador_venda_per_capita I
INNER JOIN #farmacias_dim F
    ON F.id_cnpj = I.id_cnpj;

CREATE CLUSTERED INDEX IDX_IndCapitaMun
ON temp_CGUSC.fp.indicador_venda_per_capita_mun(ano_base, uf, municipio);


-- ============================================================================
-- PASSO 4: METRICAS POR ESTADO (MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_venda_per_capita_uf;

SELECT DISTINCT
    I.ano_base,
    F.uf,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.valor_per_capita_mensal)
        OVER (PARTITION BY I.ano_base, F.uf)
    AS DECIMAL(19,4)) AS mediana_estado
INTO temp_CGUSC.fp.indicador_venda_per_capita_uf
FROM temp_CGUSC.fp.indicador_venda_per_capita I
INNER JOIN #farmacias_dim F
    ON F.id_cnpj = I.id_cnpj;

CREATE CLUSTERED INDEX IDX_IndCapitaUF
ON temp_CGUSC.fp.indicador_venda_per_capita_uf(ano_base, uf);


-- ============================================================================
-- PASSO 4B: METRICAS POR REGIAO DE SAUDE (MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_venda_per_capita_regiao;

SELECT DISTINCT
    I.ano_base,
    F.id_regiao_saude,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.valor_per_capita_mensal)
        OVER (PARTITION BY I.ano_base, F.id_regiao_saude)
    AS DECIMAL(19,4)) AS mediana_regiao
INTO temp_CGUSC.fp.indicador_venda_per_capita_regiao
FROM temp_CGUSC.fp.indicador_venda_per_capita I
INNER JOIN #farmacias_dim F
    ON F.id_cnpj = I.id_cnpj;

CREATE CLUSTERED INDEX IDX_IndCapitaReg
ON temp_CGUSC.fp.indicador_venda_per_capita_regiao(ano_base, id_regiao_saude);


-- ============================================================================
-- PASSO 5: METRICAS NACIONAIS (MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_venda_per_capita_br;

SELECT DISTINCT
    ano_base,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY valor_per_capita_mensal)
        OVER (PARTITION BY ano_base)
    AS DECIMAL(19,4)) AS mediana_pais
INTO temp_CGUSC.fp.indicador_venda_per_capita_br
FROM temp_CGUSC.fp.indicador_venda_per_capita;

CREATE CLUSTERED INDEX IDX_IndCapitaBR
ON temp_CGUSC.fp.indicador_venda_per_capita_br(ano_base);


-- ============================================================================
-- PASSO 6: TABELA CONSOLIDADA FINAL
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_venda_per_capita_detalhado;

SELECT
    I.id_cnpj,
    I.ano_base,
    I.valor_total_periodo,
    I.populacao_municipio,
    I.qtd_meses_ativos,
    I.valor_per_capita_mensal,

    MUN.mediana_municipio AS municipio_mediana,
    CAST((I.valor_per_capita_mensal + 0.1) / (MUN.mediana_municipio + 0.1) AS DECIMAL(9,4)) AS risco_relativo_mun_mediana,

    UF.mediana_estado AS estado_mediana,
    CAST((I.valor_per_capita_mensal + 0.1) / (UF.mediana_estado + 0.1) AS DECIMAL(9,4)) AS risco_relativo_uf_mediana,

    REG.mediana_regiao AS regiao_saude_mediana,
    CAST((I.valor_per_capita_mensal + 0.1) / (REG.mediana_regiao + 0.1) AS DECIMAL(9,4)) AS risco_relativo_reg_mediana,

    BR.mediana_pais AS pais_mediana,
    CAST((I.valor_per_capita_mensal + 0.1) / (BR.mediana_pais + 0.1) AS DECIMAL(9,4)) AS risco_relativo_br_mediana
INTO temp_CGUSC.fp.indicador_venda_per_capita_detalhado
FROM temp_CGUSC.fp.indicador_venda_per_capita I
INNER JOIN #farmacias_dim F
    ON F.id_cnpj = I.id_cnpj
INNER JOIN temp_CGUSC.fp.indicador_venda_per_capita_mun MUN
    ON I.ano_base = MUN.ano_base
   AND F.uf = MUN.uf
   AND F.municipio = MUN.municipio
INNER JOIN temp_CGUSC.fp.indicador_venda_per_capita_uf UF
    ON I.ano_base = UF.ano_base
   AND F.uf = UF.uf
INNER JOIN temp_CGUSC.fp.indicador_venda_per_capita_regiao REG
    ON I.ano_base = REG.ano_base
   AND F.id_regiao_saude = REG.id_regiao_saude
INNER JOIN temp_CGUSC.fp.indicador_venda_per_capita_br BR
    ON I.ano_base = BR.ano_base;

CREATE UNIQUE CLUSTERED INDEX IDX_FinalCapita_CNPJ
ON temp_CGUSC.fp.indicador_venda_per_capita_detalhado(id_cnpj, ano_base);
GO


-- ============================================================================
-- LIMPEZA DAS TABELAS INTERMEDIARIAS
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_venda_per_capita;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_venda_per_capita_mun;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_venda_per_capita_uf;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_venda_per_capita_regiao;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_venda_per_capita_br;
DROP TABLE IF EXISTS #farmacias_dim;
GO
