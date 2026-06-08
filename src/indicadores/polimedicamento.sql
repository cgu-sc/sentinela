USE [temp_CGUSC]
GO

-- ============================================================================
-- INDICADOR DE POLIMEDICAMENTO
-- ============================================================================
-- OBJETIVO: Identificar farmacias com proporcao atipica de autorizacoes com
--           quatro ou mais itens auditados.
--
-- METRICA PRINCIPAL:
--   O indicador deve ser calculado por periodo a partir dos componentes:
--   valor_autorizacoes_suspeitas / valor_total_auditado.
--
-- METRICAS AUXILIARES:
--   total_autorizacoes_monitoradas e total_autorizacoes_suspeitas permitem
--   recompor o percentual por contagem quando necessario.
--
-- FONTE DE DADOS:
--   - db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024
--   - temp_CGUSC.fp.medicamentos_patologia (universo de medicamentos auditados)
--   - temp_CGUSC.fp.dados_farmacia (id_cnpj e contexto territorial)
-- ============================================================================

-- ============================================================================
-- LIMPEZA PREVIA DE TABELAS
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_polimedicamento;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_polimedicamento_mun;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_polimedicamento_uf;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_polimedicamento_regiao;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_polimedicamento_br;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_polimedicamento_detalhado;
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
   OR COL_LENGTH('temp_CGUSC.fp.medicamentos_patologia', 'qnt_comprimidos_caixa') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.medicamentos_patologia sem colunas obrigatorias codigo_barra/qnt_comprimidos_caixa.', 16, 1);
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

IF OBJECT_ID('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'U') IS NULL
BEGIN
    RAISERROR('Tabela db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 nao encontrada.', 16, 1);
    RETURN;
END;

IF COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'cnpj') IS NULL
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'num_autorizacao') IS NULL
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'qnt_autorizada') IS NULL
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'valor_pago') IS NULL
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'data_hora') IS NULL
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'codigo_barra') IS NULL
BEGIN
    RAISERROR('Tabela db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 sem colunas obrigatorias para polimedicamento.', 16, 1);
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
    C.codigo_barra,
    CAST(C.qnt_comprimidos_caixa AS DECIMAL(10,0)) AS qnt_comprimidos_caixa
INTO #medicamentos_patologia_gtin
FROM temp_CGUSC.fp.medicamentos_patologia C
WHERE C.codigo_barra IS NOT NULL
  AND TRY_CAST(C.qnt_comprimidos_caixa AS DECIMAL(10,0)) IS NOT NULL
  AND TRY_CAST(C.qnt_comprimidos_caixa AS DECIMAL(10,0)) <> 0;

IF NOT EXISTS (SELECT 1 FROM #medicamentos_patologia_gtin)
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.medicamentos_patologia sem codigo_barra valido.', 16, 1);
    RETURN;
END;

CREATE UNIQUE CLUSTERED INDEX IDX_medicamentos_patologia_gtin
ON #medicamentos_patologia_gtin(codigo_barra);


-- ============================================================================
-- PASSO 1: PRE-CALCULO POR AUTORIZACAO
-- ============================================================================
DROP TABLE IF EXISTS #VendasPorAutorizacao;

SELECT
    F.id_cnpj,
    CAST(YEAR(A.data_hora) AS SMALLINT) AS ano_base,
    A.num_autorizacao,
    CAST(COUNT_BIG(*) AS INT) AS qtd_itens_monitorados,
    CAST(SUM(CAST(A.valor_pago AS DECIMAL(19,2))) AS DECIMAL(9,2)) AS valor_autorizacao
INTO #VendasPorAutorizacao
FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
INNER JOIN #farmacias_dim F
    ON F.cnpj = A.cnpj
INNER JOIN #medicamentos_patologia_gtin C
    ON C.codigo_barra = A.codigo_barra
WHERE A.data_hora >= @DataInicio
  AND A.data_hora < DATEADD(DAY, 1, @DataFim)
  AND A.num_autorizacao IS NOT NULL
  AND A.valor_pago IS NOT NULL
  AND A.codigo_barra IS NOT NULL
  AND A.qnt_autorizada IS NOT NULL
  AND (A.qnt_autorizada / C.qnt_comprimidos_caixa) <> 0
GROUP BY
    F.id_cnpj,
    YEAR(A.data_hora),
    A.num_autorizacao;

IF NOT EXISTS (SELECT 1 FROM #VendasPorAutorizacao)
BEGIN
    RAISERROR('Nao ha autorizacoes monitoradas para calcular polimedicamento.', 16, 1);
    RETURN;
END;

CREATE CLUSTERED INDEX IDX_VendasPorAutorizacao_CNPJ_Ano
ON #VendasPorAutorizacao(id_cnpj, ano_base);

DROP TABLE IF EXISTS #medicamentos_patologia_gtin;


-- ============================================================================
-- PASSO 2: CALCULO BASE POR FARMACIA/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_polimedicamento;

SELECT
    id_cnpj,
    ano_base,
    CAST(COUNT_BIG(*) AS INT) AS total_autorizacoes_monitoradas,
    CAST(
        SUM(
            CASE
                WHEN qtd_itens_monitorados >= 4 THEN 1
                ELSE 0
            END
        ) AS INT
    ) AS total_autorizacoes_suspeitas,
    CAST(SUM(valor_autorizacao) AS DECIMAL(9,2)) AS valor_total_auditado,
    CAST(
        SUM(
            CASE
                WHEN qtd_itens_monitorados >= 4 THEN valor_autorizacao
                ELSE CAST(0 AS DECIMAL(9,2))
            END
        ) AS DECIMAL(9,2)
    ) AS valor_autorizacoes_suspeitas
INTO temp_CGUSC.fp.indicador_polimedicamento
FROM #VendasPorAutorizacao
GROUP BY
    id_cnpj,
    ano_base
HAVING SUM(valor_autorizacao) > 0;

CREATE UNIQUE CLUSTERED INDEX IDX_IndPoli_CNPJ_Ano
ON temp_CGUSC.fp.indicador_polimedicamento(id_cnpj, ano_base);

DROP TABLE IF EXISTS #VendasPorAutorizacao;


-- ============================================================================
-- PASSO 3: TABELA CONSOLIDADA FINAL POR CNPJ/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_polimedicamento_detalhado;

SELECT
    I.id_cnpj,
    I.ano_base,
    I.total_autorizacoes_monitoradas,
    I.total_autorizacoes_suspeitas,
    CAST(I.valor_total_auditado AS DECIMAL(9,2)) AS valor_total_auditado,
    CAST(I.valor_autorizacoes_suspeitas AS DECIMAL(9,2)) AS valor_autorizacoes_suspeitas
INTO temp_CGUSC.fp.indicador_polimedicamento_detalhado
FROM temp_CGUSC.fp.indicador_polimedicamento I;

CREATE UNIQUE CLUSTERED INDEX IDX_FinalPoli_CNPJ
ON temp_CGUSC.fp.indicador_polimedicamento_detalhado(id_cnpj, ano_base);


-- ============================================================================
-- PASSO 4: AGREGADO POR REGIAO DE SAUDE/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_polimedicamento_regiao;

SELECT
    I.ano_base,
    F.id_regiao_saude,
    SUM(I.total_autorizacoes_monitoradas) AS total_autorizacoes_monitoradas,
    SUM(I.total_autorizacoes_suspeitas) AS total_autorizacoes_suspeitas,
    CAST(SUM(I.valor_total_auditado) AS DECIMAL(19,2)) AS valor_total_auditado,
    CAST(SUM(I.valor_autorizacoes_suspeitas) AS DECIMAL(19,2)) AS valor_autorizacoes_suspeitas,
    CAST(COUNT_BIG(*) AS INT) AS qtd_cnpjs
INTO temp_CGUSC.fp.indicador_polimedicamento_regiao
FROM temp_CGUSC.fp.indicador_polimedicamento I
INNER JOIN #farmacias_dim F
    ON F.id_cnpj = I.id_cnpj
GROUP BY
    I.ano_base,
    F.id_regiao_saude;

CREATE UNIQUE CLUSTERED INDEX IDX_IndPoliReg
ON temp_CGUSC.fp.indicador_polimedicamento_regiao(ano_base, id_regiao_saude);


-- ============================================================================
-- PASSO 5: AGREGADO POR UF/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_polimedicamento_uf;

SELECT
    I.ano_base,
    F.uf,
    SUM(I.total_autorizacoes_monitoradas) AS total_autorizacoes_monitoradas,
    SUM(I.total_autorizacoes_suspeitas) AS total_autorizacoes_suspeitas,
    CAST(SUM(I.valor_total_auditado) AS DECIMAL(19,2)) AS valor_total_auditado,
    CAST(SUM(I.valor_autorizacoes_suspeitas) AS DECIMAL(19,2)) AS valor_autorizacoes_suspeitas,
    CAST(COUNT_BIG(*) AS INT) AS qtd_cnpjs
INTO temp_CGUSC.fp.indicador_polimedicamento_uf
FROM temp_CGUSC.fp.indicador_polimedicamento I
INNER JOIN #farmacias_dim F
    ON F.id_cnpj = I.id_cnpj
GROUP BY
    I.ano_base,
    F.uf;

CREATE UNIQUE CLUSTERED INDEX IDX_IndPoliUF
ON temp_CGUSC.fp.indicador_polimedicamento_uf(ano_base, uf);


-- ============================================================================
-- PASSO 6: AGREGADO BRASIL/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_polimedicamento_br;

SELECT
    I.ano_base,
    SUM(I.total_autorizacoes_monitoradas) AS total_autorizacoes_monitoradas,
    SUM(I.total_autorizacoes_suspeitas) AS total_autorizacoes_suspeitas,
    CAST(SUM(I.valor_total_auditado) AS DECIMAL(19,2)) AS valor_total_auditado,
    CAST(SUM(I.valor_autorizacoes_suspeitas) AS DECIMAL(19,2)) AS valor_autorizacoes_suspeitas,
    CAST(COUNT_BIG(*) AS INT) AS qtd_cnpjs
INTO temp_CGUSC.fp.indicador_polimedicamento_br
FROM temp_CGUSC.fp.indicador_polimedicamento I
GROUP BY
    I.ano_base;

CREATE UNIQUE CLUSTERED INDEX IDX_IndPoliBR
ON temp_CGUSC.fp.indicador_polimedicamento_br(ano_base);
GO


-- ============================================================================
-- LIMPEZA DAS TABELAS INTERMEDIARIAS
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_polimedicamento;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_polimedicamento_mun;
DROP TABLE IF EXISTS #farmacias_dim;
GO
