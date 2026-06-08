USE [temp_CGUSC]
GO

-- ============================================================================
-- INDICADOR DE MEDICAMENTOS DE ALTO CUSTO
-- ============================================================================
-- OBJETIVO: Identificar farmacias com proporcao atipica do faturamento anual
--           concentrada em itens acima do percentil 90 regional do mesmo ano.
--
-- METRICA PRINCIPAL:
--   O indicador deve ser calculado por periodo a partir dos componentes:
--   valor_vendas_alto_custo / valor_total_auditado.
--
-- FONTE DE DADOS:
--   - db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024
--   - temp_CGUSC.fp.medicamentos_patologia (universo de medicamentos auditados)
--   - temp_CGUSC.fp.dados_farmacia (id_cnpj e contexto territorial)
-- ============================================================================

-- ============================================================================
-- LIMPEZA PREVIA DE TABELAS
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_alto_custo;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_alto_custo_mun;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_alto_custo_uf;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_alto_custo_regiao;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_alto_custo_br;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_alto_custo_detalhado;
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
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'qnt_autorizada') IS NULL
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'valor_pago') IS NULL
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'data_hora') IS NULL
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'codigo_barra') IS NULL
BEGIN
    RAISERROR('Tabela db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 sem colunas obrigatorias para alto custo.', 16, 1);
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
-- PASSO 1: BASE REGIONAL/ANUAL PARA LIMITE P90
-- ============================================================================
DROP TABLE IF EXISTS #BaseAltoCustoRegional;

SELECT
    F.id_regiao_saude,
    CAST(YEAR(A.data_hora) AS SMALLINT) AS ano_base,
    CAST(A.valor_pago AS DECIMAL(19,2)) AS valor_pago
INTO #BaseAltoCustoRegional
FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
INNER JOIN #farmacias_dim F
    ON F.cnpj = A.cnpj
INNER JOIN #medicamentos_patologia_gtin C
    ON C.codigo_barra = A.codigo_barra
WHERE A.data_hora >= @DataInicio
  AND A.data_hora < DATEADD(DAY, 1, @DataFim)
  AND A.codigo_barra IS NOT NULL
  AND A.valor_pago IS NOT NULL
  AND A.qnt_autorizada IS NOT NULL
  AND (A.qnt_autorizada / C.qnt_comprimidos_caixa) <> 0;

IF NOT EXISTS (SELECT 1 FROM #BaseAltoCustoRegional)
BEGIN
    RAISERROR('Nao ha registros validos para calcular limite regional/anual de alto custo.', 16, 1);
    RETURN;
END;

CREATE CLUSTERED INDEX CX_BaseAltoCustoRegional
ON #BaseAltoCustoRegional(id_regiao_saude, ano_base, valor_pago);

DROP TABLE IF EXISTS #LimiteAltoCustoRegional;

SELECT DISTINCT
    id_regiao_saude,
    ano_base,
    CAST(
        PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY valor_pago)
            OVER (PARTITION BY id_regiao_saude, ano_base)
        AS DECIMAL(19,2)
    ) AS valor_limite_alto_custo,
    COUNT_BIG(*) OVER (PARTITION BY id_regiao_saude, ano_base) AS qtd_registros_base
INTO #LimiteAltoCustoRegional
FROM #BaseAltoCustoRegional;

CREATE UNIQUE CLUSTERED INDEX CX_LimiteAltoCustoRegional
ON #LimiteAltoCustoRegional(id_regiao_saude, ano_base);


-- ============================================================================
-- PASSO 2: PERSISTENCIA DO LIMITE REGIONAL/ANUAL
-- ============================================================================
IF OBJECT_ID('temp_CGUSC.fp.indicador_alto_custo_limite', 'U') IS NULL
BEGIN
    CREATE TABLE temp_CGUSC.fp.indicador_alto_custo_limite (
        data_inicio               DATE          NOT NULL,
        data_fim                  DATE          NOT NULL,
        percentil                 DECIMAL(5,4)  NOT NULL,
        id_regiao_saude           INT           NOT NULL,
        ano_base                  SMALLINT      NOT NULL,
        valor_limite_alto_custo   DECIMAL(19,2) NOT NULL,
        qtd_registros_base        BIGINT        NOT NULL,
        dt_processamento          DATETIME2(0)  NOT NULL
            CONSTRAINT DF_indicador_alto_custo_limite_dt DEFAULT SYSDATETIME()
    );
END;

IF COL_LENGTH('temp_CGUSC.fp.indicador_alto_custo_limite', 'data_inicio') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.indicador_alto_custo_limite', 'data_fim') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.indicador_alto_custo_limite', 'percentil') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.indicador_alto_custo_limite', 'id_regiao_saude') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.indicador_alto_custo_limite', 'ano_base') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.indicador_alto_custo_limite', 'valor_limite_alto_custo') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.indicador_alto_custo_limite', 'qtd_registros_base') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.indicador_alto_custo_limite', 'dt_processamento') IS NULL
BEGIN
    RAISERROR('Schema invalido em temp_CGUSC.fp.indicador_alto_custo_limite.', 16, 1);
    RETURN;
END;

IF NOT EXISTS (
    SELECT 1
    FROM temp_CGUSC.sys.indexes
    WHERE object_id = OBJECT_ID('temp_CGUSC.fp.indicador_alto_custo_limite')
      AND name = 'CX_indicador_alto_custo_limite_periodo'
)
BEGIN
    CREATE UNIQUE CLUSTERED INDEX CX_indicador_alto_custo_limite_periodo
    ON temp_CGUSC.fp.indicador_alto_custo_limite(data_inicio, data_fim, percentil, id_regiao_saude, ano_base);
END;

IF NOT EXISTS (
    SELECT 1
    FROM temp_CGUSC.sys.indexes
    WHERE object_id = OBJECT_ID('temp_CGUSC.fp.indicador_alto_custo_limite')
      AND name = 'IX_indicador_alto_custo_limite_regiao'
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_indicador_alto_custo_limite_regiao
    ON temp_CGUSC.fp.indicador_alto_custo_limite(id_regiao_saude, ano_base, data_inicio, data_fim, percentil)
    INCLUDE (valor_limite_alto_custo, qtd_registros_base, dt_processamento);
END;

DELETE FROM temp_CGUSC.fp.indicador_alto_custo_limite
WHERE data_inicio = @DataInicio
  AND data_fim = @DataFim
  AND percentil = CAST(0.90 AS DECIMAL(5,4));

INSERT INTO temp_CGUSC.fp.indicador_alto_custo_limite (
    data_inicio,
    data_fim,
    percentil,
    id_regiao_saude,
    ano_base,
    valor_limite_alto_custo,
    qtd_registros_base,
    dt_processamento
)
SELECT
    @DataInicio,
    @DataFim,
    CAST(0.90 AS DECIMAL(5,4)),
    id_regiao_saude,
    ano_base,
    valor_limite_alto_custo,
    qtd_registros_base,
    SYSDATETIME()
FROM #LimiteAltoCustoRegional;

IF NOT EXISTS (
    SELECT 1
    FROM temp_CGUSC.fp.indicador_alto_custo_limite
    WHERE data_inicio = @DataInicio
      AND data_fim = @DataFim
      AND percentil = CAST(0.90 AS DECIMAL(5,4))
)
BEGIN
    RAISERROR('Limite de alto custo nao calculado para o periodo informado.', 16, 1);
    RETURN;
END;


-- ============================================================================
-- PASSO 3: CALCULO BASE POR FARMACIA/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_alto_custo;

SELECT
    F.id_cnpj,
    CAST(YEAR(A.data_hora) AS SMALLINT) AS ano_base,
    CAST(SUM(CAST(A.valor_pago AS DECIMAL(19,2))) AS DECIMAL(19,2)) AS valor_total_auditado,
    CAST(
        SUM(
            CASE
                WHEN CAST(A.valor_pago AS DECIMAL(19,2)) >= L.valor_limite_alto_custo
                    THEN CAST(A.valor_pago AS DECIMAL(19,2))
                ELSE CAST(0 AS DECIMAL(19,2))
            END
        ) AS DECIMAL(19,2)
    ) AS valor_vendas_alto_custo
INTO temp_CGUSC.fp.indicador_alto_custo
FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
INNER JOIN #farmacias_dim F
    ON F.cnpj = A.cnpj
INNER JOIN #medicamentos_patologia_gtin C
    ON C.codigo_barra = A.codigo_barra
INNER JOIN #LimiteAltoCustoRegional L
    ON L.id_regiao_saude = F.id_regiao_saude
   AND L.ano_base = CAST(YEAR(A.data_hora) AS SMALLINT)
WHERE A.data_hora >= @DataInicio
  AND A.data_hora < DATEADD(DAY, 1, @DataFim)
  AND A.codigo_barra IS NOT NULL
  AND A.valor_pago IS NOT NULL
  AND A.qnt_autorizada IS NOT NULL
  AND (A.qnt_autorizada / C.qnt_comprimidos_caixa) <> 0
GROUP BY
    F.id_cnpj,
    YEAR(A.data_hora);

IF NOT EXISTS (SELECT 1 FROM temp_CGUSC.fp.indicador_alto_custo)
BEGIN
    RAISERROR('Nao ha farmacias com valor total vendido valido para alto custo.', 16, 1);
    RETURN;
END;

CREATE UNIQUE CLUSTERED INDEX IDX_IndAltoCusto_CNPJ_Ano
ON temp_CGUSC.fp.indicador_alto_custo(id_cnpj, ano_base);

DROP TABLE IF EXISTS #BaseAltoCustoRegional;
DROP TABLE IF EXISTS #LimiteAltoCustoRegional;
DROP TABLE IF EXISTS #medicamentos_patologia_gtin;


-- ============================================================================
-- PASSO 4: TABELA CONSOLIDADA FINAL POR CNPJ/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_alto_custo_detalhado;

SELECT
    I.id_cnpj,
    I.ano_base,
    I.valor_total_auditado,
    I.valor_vendas_alto_custo
INTO temp_CGUSC.fp.indicador_alto_custo_detalhado
FROM temp_CGUSC.fp.indicador_alto_custo I;

CREATE UNIQUE CLUSTERED INDEX IDX_FinalAltoCusto_CNPJ
ON temp_CGUSC.fp.indicador_alto_custo_detalhado(id_cnpj, ano_base);


-- ============================================================================
-- PASSO 5: AGREGADO POR REGIAO DE SAUDE/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_alto_custo_regiao;

SELECT
    I.ano_base,
    F.id_regiao_saude,
    CAST(SUM(I.valor_total_auditado) AS DECIMAL(19,2)) AS valor_total_auditado,
    CAST(SUM(I.valor_vendas_alto_custo) AS DECIMAL(19,2)) AS valor_vendas_alto_custo,
    CAST(COUNT_BIG(*) AS INT) AS qtd_cnpjs
INTO temp_CGUSC.fp.indicador_alto_custo_regiao
FROM temp_CGUSC.fp.indicador_alto_custo I
INNER JOIN #farmacias_dim F
    ON F.id_cnpj = I.id_cnpj
GROUP BY
    I.ano_base,
    F.id_regiao_saude;

CREATE UNIQUE CLUSTERED INDEX IDX_IndAltoCustoReg
ON temp_CGUSC.fp.indicador_alto_custo_regiao(ano_base, id_regiao_saude);


-- ============================================================================
-- PASSO 6: AGREGADO POR UF/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_alto_custo_uf;

SELECT
    I.ano_base,
    F.uf,
    CAST(SUM(I.valor_total_auditado) AS DECIMAL(19,2)) AS valor_total_auditado,
    CAST(SUM(I.valor_vendas_alto_custo) AS DECIMAL(19,2)) AS valor_vendas_alto_custo,
    CAST(COUNT_BIG(*) AS INT) AS qtd_cnpjs
INTO temp_CGUSC.fp.indicador_alto_custo_uf
FROM temp_CGUSC.fp.indicador_alto_custo I
INNER JOIN #farmacias_dim F
    ON F.id_cnpj = I.id_cnpj
GROUP BY
    I.ano_base,
    F.uf;

CREATE UNIQUE CLUSTERED INDEX IDX_IndAltoCustoUF
ON temp_CGUSC.fp.indicador_alto_custo_uf(ano_base, uf);


-- ============================================================================
-- PASSO 7: AGREGADO BRASIL/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_alto_custo_br;

SELECT
    I.ano_base,
    CAST(SUM(I.valor_total_auditado) AS DECIMAL(19,2)) AS valor_total_auditado,
    CAST(SUM(I.valor_vendas_alto_custo) AS DECIMAL(19,2)) AS valor_vendas_alto_custo,
    CAST(COUNT_BIG(*) AS INT) AS qtd_cnpjs
INTO temp_CGUSC.fp.indicador_alto_custo_br
FROM temp_CGUSC.fp.indicador_alto_custo I
GROUP BY
    I.ano_base;

CREATE UNIQUE CLUSTERED INDEX IDX_IndAltoCustoBR
ON temp_CGUSC.fp.indicador_alto_custo_br(ano_base);
GO


-- ============================================================================
-- LIMPEZA DAS TABELAS INTERMEDIARIAS
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_alto_custo;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_alto_custo_mun;
DROP TABLE IF EXISTS #farmacias_dim;
GO
