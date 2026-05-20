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
  AND A.data_hora <= @DataFim
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
-- PASSO 5: METRICAS POR MUNICIPIO (MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_concentracao_pico_mun;

SELECT DISTINCT
    I.ano_base,
    CAST(F.uf        AS VARCHAR(2))   AS uf,
    CAST(F.municipio AS VARCHAR(255)) AS municipio,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.mediana_concentracao)
        OVER (
            PARTITION BY
                I.ano_base,
                CAST(F.uf AS VARCHAR(2)),
                CAST(F.municipio AS VARCHAR(255))
        )
    AS DECIMAL(7,4)) AS mediana_municipio
INTO temp_CGUSC.fp.indicador_concentracao_pico_mun
FROM temp_CGUSC.fp.indicador_concentracao_pico I
INNER JOIN #farmacias_dim F ON F.id_cnpj = I.id_cnpj;

CREATE CLUSTERED INDEX IDX_IndPicoMun
ON temp_CGUSC.fp.indicador_concentracao_pico_mun(ano_base, uf, municipio);


-- ============================================================================
-- PASSO 6: METRICAS POR ESTADO (MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_concentracao_pico_uf;

SELECT DISTINCT
    I.ano_base,
    CAST(F.uf AS VARCHAR(2)) AS uf,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.mediana_concentracao)
        OVER (PARTITION BY I.ano_base, CAST(F.uf AS VARCHAR(2)))
    AS DECIMAL(7,4)) AS mediana_estado
INTO temp_CGUSC.fp.indicador_concentracao_pico_uf
FROM temp_CGUSC.fp.indicador_concentracao_pico I
INNER JOIN #farmacias_dim F ON F.id_cnpj = I.id_cnpj;

CREATE CLUSTERED INDEX IDX_IndPicoUF
ON temp_CGUSC.fp.indicador_concentracao_pico_uf(ano_base, uf);


-- ============================================================================
-- PASSO 6B: METRICAS POR REGIAO DE SAUDE (MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_concentracao_pico_regiao;

SELECT DISTINCT
    I.ano_base,
    F.id_regiao_saude,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.mediana_concentracao)
        OVER (PARTITION BY I.ano_base, F.id_regiao_saude)
    AS DECIMAL(7,4)) AS mediana_regiao
INTO temp_CGUSC.fp.indicador_concentracao_pico_regiao
FROM temp_CGUSC.fp.indicador_concentracao_pico I
INNER JOIN #farmacias_dim F ON F.id_cnpj = I.id_cnpj
WHERE F.id_regiao_saude IS NOT NULL;

CREATE CLUSTERED INDEX IDX_IndPicoReg
ON temp_CGUSC.fp.indicador_concentracao_pico_regiao(ano_base, id_regiao_saude);


-- ============================================================================
-- PASSO 7: METRICAS NACIONAIS (MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_concentracao_pico_br;

SELECT DISTINCT
    ano_base,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY mediana_concentracao)
        OVER (PARTITION BY ano_base)
    AS DECIMAL(7,4)) AS mediana_pais
INTO temp_CGUSC.fp.indicador_concentracao_pico_br
FROM temp_CGUSC.fp.indicador_concentracao_pico;

CREATE CLUSTERED INDEX IDX_IndPicoBR
ON temp_CGUSC.fp.indicador_concentracao_pico_br(ano_base);


-- ============================================================================
-- PASSO 8: TABELA CONSOLIDADA FINAL
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_concentracao_pico_detalhado;

SELECT
    I.id_cnpj,
    I.ano_base,

    -- Indicadores base
    I.meses_analisados,
    I.mediana_concentracao,

    -- Benchmarks municipais
    ISNULL(MUN.mediana_municipio, 0) AS municipio_mediana,
    CAST((I.mediana_concentracao + 0.01) / (ISNULL(MUN.mediana_municipio, 0) + 0.01) AS DECIMAL(9,4)) AS risco_relativo_mun_mediana,

    -- Benchmarks estaduais
    ISNULL(UF.mediana_estado, 0) AS estado_mediana,
    CAST((I.mediana_concentracao + 0.01) / (ISNULL(UF.mediana_estado, 0) + 0.01) AS DECIMAL(9,4)) AS risco_relativo_uf_mediana,

    -- Benchmarks Regionais (Regiao de Saude)
    ISNULL(REG.mediana_regiao, 0) AS regiao_saude_mediana,
    CAST((I.mediana_concentracao + 0.01) / (ISNULL(REG.mediana_regiao, 0) + 0.01) AS DECIMAL(9,4)) AS risco_relativo_reg_mediana,

    -- Benchmarks nacionais
    BR.mediana_pais AS pais_mediana,
    CAST((I.mediana_concentracao + 0.01) / (BR.mediana_pais + 0.01) AS DECIMAL(9,4)) AS risco_relativo_br_mediana

INTO temp_CGUSC.fp.indicador_concentracao_pico_detalhado
FROM temp_CGUSC.fp.indicador_concentracao_pico I
INNER JOIN #farmacias_dim F
    ON F.id_cnpj = I.id_cnpj
LEFT JOIN temp_CGUSC.fp.indicador_concentracao_pico_mun MUN
    ON  I.ano_base = MUN.ano_base
    AND CAST(F.uf        AS VARCHAR(2))   = MUN.uf
    AND CAST(F.municipio AS VARCHAR(255)) = MUN.municipio
LEFT JOIN temp_CGUSC.fp.indicador_concentracao_pico_uf UF
    ON I.ano_base = UF.ano_base
   AND CAST(F.uf AS VARCHAR(2)) = UF.uf
LEFT JOIN temp_CGUSC.fp.indicador_concentracao_pico_regiao REG
    ON I.ano_base = REG.ano_base
   AND F.id_regiao_saude = REG.id_regiao_saude
INNER JOIN temp_CGUSC.fp.indicador_concentracao_pico_br BR
    ON I.ano_base = BR.ano_base;

CREATE UNIQUE CLUSTERED INDEX IDX_FinalPico_CNPJ
ON temp_CGUSC.fp.indicador_concentracao_pico_detalhado(id_cnpj, ano_base);

CREATE NONCLUSTERED INDEX IDX_FinalPico_Risco
ON temp_CGUSC.fp.indicador_concentracao_pico_detalhado(ano_base, risco_relativo_mun_mediana DESC);
GO

-- ============================================================================
-- LIMPEZA DAS TABELAS INTERMEDIARIAS
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_concentracao_pico;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_concentracao_pico_mun;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_concentracao_pico_uf;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_concentracao_pico_regiao;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_concentracao_pico_br;
DROP TABLE IF EXISTS #farmacias_dim;
GO

