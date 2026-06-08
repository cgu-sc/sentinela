USE [temp_CGUSC]
GO

-- ============================================================================
-- INDICADOR DE CONCENTRACAO EM DIAS DE PICO
-- ============================================================================
-- OBJETIVO: Identificar farmacias onde o faturamento e altamente concentrado
--           em poucos dias do mes, sugerindo manipulacao de registros ou
--           superdispensacao em periodos especificos (ex.: virada de mes).
--
-- METRICA PRINCIPAL: pct_concentracao_top3_dias
--   Percentual do faturamento mensal concentrado nos 3 dias de maior venda.
--   Calculado mensalmente e sumarizado por farmacia/ano via mediana.
--
-- VALOR FINAL:
--   mediana_concentracao representa o percentual anual tipico da farmacia.
--
-- FONTE DE DADOS:
--   - db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 (periodo completo)
--   - temp_CGUSC.fp.medicamentos_patologia (universo de medicamentos auditados)
--   - temp_CGUSC.fp.dados_farmacia (id_cnpj e contexto territorial)
-- ============================================================================

-- ============================================================================
-- DEFINICAO DE VARIAVEIS DO PERIODO
-- ============================================================================
DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim    DATE = '2024-12-10';


-- ============================================================================
-- PASSO 0: UNIVERSO DE GTINS AUDITADOS
-- Garante uma linha por codigo_barra antes do join com movimentacao.
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
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'data_hora') IS NULL
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'valor_pago') IS NULL
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'qnt_autorizada') IS NULL
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'codigo_barra') IS NULL
BEGIN
    RAISERROR('Tabela db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 sem colunas obrigatorias para concentracao de dias de pico.', 16, 1);
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
-- PASSO 1: VENDAS DIARIAS POR FARMACIA
-- Filtrado pelo universo de medicamentos auditados.
-- ============================================================================
DROP TABLE IF EXISTS #VendasDiarias;

SELECT
    F.id_cnpj,
    CAST(YEAR(A.data_hora) AS SMALLINT) AS ano_base,
    CAST(MONTH(A.data_hora) AS TINYINT) AS mes_base,
    DATEFROMPARTS(YEAR(A.data_hora), MONTH(A.data_hora), 1) AS competencia_mes,
    CAST(A.data_hora AS DATE) AS data_venda,
    SUM(A.valor_pago) AS valor_dia
INTO #VendasDiarias
FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
INNER JOIN #farmacias_dim F
    ON F.cnpj = A.cnpj
INNER JOIN #medicamentos_patologia_gtin C
    ON C.codigo_barra = A.codigo_barra
WHERE A.data_hora >= @DataInicio
  AND A.data_hora < DATEADD(DAY, 1, @DataFim)
  AND A.qnt_autorizada IS NOT NULL
  AND (A.qnt_autorizada / C.qnt_comprimidos_caixa) <> 0
GROUP BY
    F.id_cnpj,
    YEAR(A.data_hora),
    MONTH(A.data_hora),
    DATEFROMPARTS(YEAR(A.data_hora), MONTH(A.data_hora), 1),
    CAST(A.data_hora AS DATE);

CREATE CLUSTERED INDEX IDX_VendasDiarias_CNPJ
ON #VendasDiarias(id_cnpj, ano_base, mes_base);


-- ============================================================================
-- PASSO 2: RANQUEAMENTO DOS DIAS DENTRO DE CADA MES
-- ============================================================================
DROP TABLE IF EXISTS #RankingDias;

SELECT
    id_cnpj,
    ano_base,
    mes_base,
    competencia_mes,
    valor_dia,
    SUM(valor_dia) OVER (
        PARTITION BY id_cnpj, ano_base, mes_base
    ) AS total_mes,
    ROW_NUMBER() OVER (
        PARTITION BY id_cnpj, ano_base, mes_base
        ORDER BY valor_dia DESC
    ) AS ranking_dia
INTO #RankingDias
FROM #VendasDiarias;

CREATE CLUSTERED INDEX IDX_RankingDias_CNPJ_AnoMes
ON #RankingDias(id_cnpj, ano_base, mes_base, ranking_dia);

DROP TABLE IF EXISTS #VendasDiarias;


-- ============================================================================
-- PASSO 3: PERCENTUAL DE CONCENTRACAO MENSAL (TOP 3 DIAS)
-- ============================================================================
DROP TABLE IF EXISTS #ConcentracaoMensal;

SELECT
    id_cnpj,
    ano_base,
    mes_base,
    competencia_mes,
    CAST(SUM(CASE WHEN ranking_dia <= 3 THEN valor_dia ELSE 0 END) AS DECIMAL(19,2)) AS valor_top3_dias,
    CAST(MAX(total_mes) AS DECIMAL(19,2)) AS valor_total_auditado,
    CAST(
        SUM(CASE WHEN ranking_dia <= 3 THEN valor_dia ELSE 0 END) /
        NULLIF(CAST(MAX(total_mes) AS DECIMAL(18,2)), 0) * 100.0
    AS DECIMAL(7,4)) AS pct_concentracao_top3_dias
INTO #ConcentracaoMensal
FROM #RankingDias
GROUP BY
    id_cnpj,
    ano_base,
    mes_base,
    competencia_mes
HAVING MAX(total_mes) > 0;

CREATE CLUSTERED INDEX IDX_ConcentracaoMensal_CNPJ_Ano
ON #ConcentracaoMensal(id_cnpj, ano_base, mes_base);

DROP TABLE IF EXISTS #RankingDias;
DROP TABLE IF EXISTS #medicamentos_patologia_gtin;


-- ============================================================================
-- PASSO 4: CALCULO BASE POR FARMACIA/ANO (MEDIANA ANUAL)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_concentracao_pico;

SELECT DISTINCT
    id_cnpj,
    ano_base,
    CAST(COUNT(mes_base) OVER (PARTITION BY id_cnpj, ano_base) AS TINYINT) AS meses_analisados,
    CAST(SUM(valor_top3_dias) OVER (PARTITION BY id_cnpj, ano_base) AS DECIMAL(19,2)) AS valor_top3_dias,
    CAST(SUM(valor_total_auditado) OVER (PARTITION BY id_cnpj, ano_base) AS DECIMAL(19,2)) AS valor_total_auditado,

    -- Mediana: comportamento tipico anual da farmacia
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY pct_concentracao_top3_dias)
        OVER (PARTITION BY id_cnpj, ano_base)
    AS DECIMAL(7,4)) AS mediana_concentracao

INTO temp_CGUSC.fp.indicador_concentracao_pico
FROM #ConcentracaoMensal;

CREATE UNIQUE CLUSTERED INDEX IDX_IndPico_CNPJ
ON temp_CGUSC.fp.indicador_concentracao_pico(id_cnpj, ano_base);

DROP TABLE IF EXISTS #ConcentracaoMensal;


-- ============================================================================
-- PASSO 5: TABELA CONSOLIDADA FINAL POR CNPJ/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_concentracao_pico_detalhado;

SELECT
    I.id_cnpj,
    I.ano_base,
    I.meses_analisados,
    CAST(I.valor_top3_dias AS DECIMAL(19,2)) AS valor_top3_dias,
    CAST(I.valor_total_auditado AS DECIMAL(19,2)) AS valor_total_auditado,
    CAST(I.mediana_concentracao AS DECIMAL(7,4)) AS mediana_concentracao
INTO temp_CGUSC.fp.indicador_concentracao_pico_detalhado
FROM temp_CGUSC.fp.indicador_concentracao_pico I;

CREATE UNIQUE CLUSTERED INDEX IDX_FinalPico_CNPJ
ON temp_CGUSC.fp.indicador_concentracao_pico_detalhado(id_cnpj, ano_base);


-- ============================================================================
-- PASSO 6: AGREGADO POR REGIAO DE SAUDE/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_concentracao_pico_regiao;

SELECT
    I.ano_base,
    F.id_regiao_saude,
    SUM(I.meses_analisados) AS meses_analisados,
    CAST(SUM(I.valor_top3_dias) AS DECIMAL(19,2)) AS valor_top3_dias,
    CAST(SUM(I.valor_total_auditado) AS DECIMAL(19,2)) AS valor_total_auditado,
    CAST(COUNT_BIG(*) AS INT) AS qtd_cnpjs
INTO temp_CGUSC.fp.indicador_concentracao_pico_regiao
FROM temp_CGUSC.fp.indicador_concentracao_pico I
INNER JOIN #farmacias_dim F
    ON F.id_cnpj = I.id_cnpj
GROUP BY
    I.ano_base,
    F.id_regiao_saude;

CREATE UNIQUE CLUSTERED INDEX IDX_IndPicoReg
ON temp_CGUSC.fp.indicador_concentracao_pico_regiao(ano_base, id_regiao_saude);


-- ============================================================================
-- PASSO 7: AGREGADO POR UF/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_concentracao_pico_uf;

SELECT
    I.ano_base,
    F.uf,
    SUM(I.meses_analisados) AS meses_analisados,
    CAST(SUM(I.valor_top3_dias) AS DECIMAL(19,2)) AS valor_top3_dias,
    CAST(SUM(I.valor_total_auditado) AS DECIMAL(19,2)) AS valor_total_auditado,
    CAST(COUNT_BIG(*) AS INT) AS qtd_cnpjs
INTO temp_CGUSC.fp.indicador_concentracao_pico_uf
FROM temp_CGUSC.fp.indicador_concentracao_pico I
INNER JOIN #farmacias_dim F
    ON F.id_cnpj = I.id_cnpj
GROUP BY
    I.ano_base,
    F.uf;

CREATE UNIQUE CLUSTERED INDEX IDX_IndPicoUF
ON temp_CGUSC.fp.indicador_concentracao_pico_uf(ano_base, uf);


-- ============================================================================
-- PASSO 8: AGREGADO BRASIL/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_concentracao_pico_br;

SELECT
    I.ano_base,
    SUM(I.meses_analisados) AS meses_analisados,
    CAST(SUM(I.valor_top3_dias) AS DECIMAL(19,2)) AS valor_top3_dias,
    CAST(SUM(I.valor_total_auditado) AS DECIMAL(19,2)) AS valor_total_auditado,
    CAST(COUNT_BIG(*) AS INT) AS qtd_cnpjs
INTO temp_CGUSC.fp.indicador_concentracao_pico_br
FROM temp_CGUSC.fp.indicador_concentracao_pico I
GROUP BY
    I.ano_base;

CREATE UNIQUE CLUSTERED INDEX IDX_IndPicoBR
ON temp_CGUSC.fp.indicador_concentracao_pico_br(ano_base);
GO

-- ============================================================================
-- LIMPEZA DAS TABELAS INTERMEDIARIAS
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_concentracao_pico;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_concentracao_pico_mun;
DROP TABLE IF EXISTS #farmacias_dim;
GO

