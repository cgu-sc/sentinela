USE [temp_CGUSC]
GO

-- ============================================================================
-- INDICADOR DE TETO MAXIMO POR ITEM
-- ============================================================================
-- OBJETIVO: Identificar farmacias com proporcao atipica de itens dispensados
--           na quantidade maxima permitida para o principio ativo.
--
-- METRICA PRINCIPAL:
--   O indicador deve ser calculado por periodo a partir dos componentes:
--   valor_itens_teto_maximo / valor_total_auditado.
--
-- METRICAS AUXILIARES:
--   total_itens_monitorados e total_itens_teto_maximo permitem recompor o
--   percentual por contagem quando necessario.
--
-- FONTE DE DADOS:
--   - db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024
--   - temp_CGUSC.fp.medicamentos_patologia (GTIN e principio ativo)
--   - temp_CGUSC.fp.posologia_tempo_bloqueio (teto por principio ativo)
--   - temp_CGUSC.fp.dados_farmacia (id_cnpj e contexto territorial)
-- ============================================================================

-- ============================================================================
-- LIMPEZA PREVIA DE TABELAS
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_teto;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_teto_mun;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_teto_uf;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_teto_regiao;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_teto_br;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_teto_detalhado;
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
   OR COL_LENGTH('temp_CGUSC.fp.medicamentos_patologia', 'principio_ativo') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.medicamentos_patologia sem colunas obrigatorias codigo_barra/principio_ativo.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('temp_CGUSC.fp.posologia_tempo_bloqueio', 'U') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.posologia_tempo_bloqueio nao encontrada.', 16, 1);
    RETURN;
END;

IF COL_LENGTH('temp_CGUSC.fp.posologia_tempo_bloqueio', 'PRINCIPIO_ATIVO') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.posologia_tempo_bloqueio', 'QUANTIDADE_MAXIMA') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.posologia_tempo_bloqueio sem colunas obrigatorias PRINCIPIO_ATIVO/QUANTIDADE_MAXIMA.', 16, 1);
    RETURN;
END;

IF EXISTS (
    SELECT 1
    FROM temp_CGUSC.fp.posologia_tempo_bloqueio
    WHERE QUANTIDADE_MAXIMA > 0
    GROUP BY UPPER(LTRIM(RTRIM(CAST(PRINCIPIO_ATIVO AS VARCHAR(255)))))
    HAVING COUNT_BIG(*) > 1
)
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.posologia_tempo_bloqueio possui PRINCIPIO_ATIVO duplicado com QUANTIDADE_MAXIMA valida.', 16, 1);
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
    RAISERROR('Tabela db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 sem colunas obrigatorias para teto.', 16, 1);
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

DROP TABLE IF EXISTS #medicamentos_teto;

SELECT DISTINCT
    C.codigo_barra,
    CAST(P.QUANTIDADE_MAXIMA AS DECIMAL(18,4)) AS quantidade_maxima
INTO #medicamentos_teto
FROM temp_CGUSC.fp.medicamentos_patologia C
INNER JOIN temp_CGUSC.fp.posologia_tempo_bloqueio P
    ON UPPER(LTRIM(RTRIM(CAST(P.PRINCIPIO_ATIVO AS VARCHAR(255))))) = UPPER(LTRIM(RTRIM(CAST(C.principio_ativo AS VARCHAR(255)))))
WHERE C.codigo_barra IS NOT NULL
  AND C.principio_ativo IS NOT NULL
  AND P.QUANTIDADE_MAXIMA > 0;

IF NOT EXISTS (SELECT 1 FROM #medicamentos_teto)
BEGIN
    RAISERROR('Nao ha medicamentos com teto maximo valido para monitoramento.', 16, 1);
    RETURN;
END;

IF EXISTS (
    SELECT 1
    FROM #medicamentos_teto
    GROUP BY codigo_barra
    HAVING COUNT_BIG(*) > 1
)
BEGIN
    RAISERROR('Um mesmo codigo_barra esta associado a mais de um teto maximo. Corrija o mapeamento antes de executar.', 16, 1);
    RETURN;
END;

CREATE UNIQUE CLUSTERED INDEX IDX_medicamentos_teto_gtin
ON #medicamentos_teto(codigo_barra);


-- ============================================================================
-- PASSO 1: CALCULO BASE POR ITEM/FARMACIA/ANO
-- ============================================================================
DROP TABLE IF EXISTS #ItensTetoAgregado;

SELECT
    F.id_cnpj,
    CAST(YEAR(A.data_hora) AS SMALLINT) AS ano_base,
    CAST(COUNT_BIG(*) AS INT) AS total_itens_monitorados,
    CAST(SUM(CAST(
        CASE
            WHEN CAST(A.qnt_autorizada AS DECIMAL(18,4)) >= M.quantidade_maxima
                THEN 1
            ELSE 0
        END AS INT
    )) AS INT) AS total_itens_teto_maximo,
    CAST(SUM(CAST(A.valor_pago AS DECIMAL(19,2))) AS DECIMAL(9,2)) AS valor_total_auditado,
    CAST(SUM(CAST(
        CASE
            WHEN CAST(A.qnt_autorizada AS DECIMAL(18,4)) >= M.quantidade_maxima
                THEN A.valor_pago
            ELSE 0
        END AS DECIMAL(9,2)
    )) AS DECIMAL(9,2)) AS valor_itens_teto_maximo
INTO #ItensTetoAgregado
FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
INNER JOIN #farmacias_dim F
    ON F.cnpj = A.cnpj
INNER JOIN #medicamentos_teto M
    ON M.codigo_barra = A.codigo_barra
WHERE A.data_hora >= @DataInicio
  AND A.data_hora < DATEADD(DAY, 1, @DataFim)
  AND A.codigo_barra IS NOT NULL
  AND A.qnt_autorizada IS NOT NULL
  AND A.valor_pago IS NOT NULL
GROUP BY
    F.id_cnpj,
    YEAR(A.data_hora)
HAVING SUM(CAST(A.valor_pago AS DECIMAL(19,2))) > 0;

IF NOT EXISTS (SELECT 1 FROM #ItensTetoAgregado)
BEGIN
    RAISERROR('Nao ha itens monitorados para calcular o indicador de teto.', 16, 1);
    RETURN;
END;

CREATE UNIQUE CLUSTERED INDEX IDX_ItensTetoAgregado_CNPJ_Ano
ON #ItensTetoAgregado(id_cnpj, ano_base);

DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_teto;

SELECT
    id_cnpj,
    ano_base,
    total_itens_monitorados,
    total_itens_teto_maximo,
    valor_total_auditado,
    valor_itens_teto_maximo
INTO temp_CGUSC.fp.indicador_teto
FROM #ItensTetoAgregado;

CREATE UNIQUE CLUSTERED INDEX IDX_IndTeto_CNPJ_Ano
ON temp_CGUSC.fp.indicador_teto(id_cnpj, ano_base);

DROP TABLE IF EXISTS #ItensTetoAgregado;
DROP TABLE IF EXISTS #medicamentos_teto;


-- ============================================================================
-- PASSO 2: TABELA CONSOLIDADA FINAL POR CNPJ/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_teto_detalhado;

SELECT
    I.id_cnpj,
    I.ano_base,
    CAST(I.total_itens_monitorados AS INT) AS total_itens_monitorados,
    CAST(I.total_itens_teto_maximo AS INT) AS total_itens_teto_maximo,
    CAST(I.valor_total_auditado AS DECIMAL(9,2)) AS valor_total_auditado,
    CAST(I.valor_itens_teto_maximo AS DECIMAL(9,2)) AS valor_itens_teto_maximo
INTO temp_CGUSC.fp.indicador_teto_detalhado
FROM temp_CGUSC.fp.indicador_teto I;

CREATE UNIQUE CLUSTERED INDEX IDX_FinalTeto_CNPJ
ON temp_CGUSC.fp.indicador_teto_detalhado(id_cnpj, ano_base);


-- ============================================================================
-- PASSO 3: AGREGADO POR REGIAO DE SAUDE/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_teto_regiao;

SELECT
    I.ano_base,
    F.id_regiao_saude,
    SUM(I.total_itens_monitorados) AS total_itens_monitorados,
    SUM(I.total_itens_teto_maximo) AS total_itens_teto_maximo,
    CAST(SUM(I.valor_total_auditado) AS DECIMAL(19,2)) AS valor_total_auditado,
    CAST(SUM(I.valor_itens_teto_maximo) AS DECIMAL(19,2)) AS valor_itens_teto_maximo,
    CAST(COUNT_BIG(*) AS INT) AS qtd_cnpjs
INTO temp_CGUSC.fp.indicador_teto_regiao
FROM temp_CGUSC.fp.indicador_teto I
INNER JOIN #farmacias_dim F
    ON F.id_cnpj = I.id_cnpj
GROUP BY
    I.ano_base,
    F.id_regiao_saude;

CREATE UNIQUE CLUSTERED INDEX IDX_IndTetoReg
ON temp_CGUSC.fp.indicador_teto_regiao(ano_base, id_regiao_saude);


-- ============================================================================
-- PASSO 4: AGREGADO POR UF/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_teto_uf;

SELECT
    I.ano_base,
    F.uf,
    SUM(I.total_itens_monitorados) AS total_itens_monitorados,
    SUM(I.total_itens_teto_maximo) AS total_itens_teto_maximo,
    CAST(SUM(I.valor_total_auditado) AS DECIMAL(19,2)) AS valor_total_auditado,
    CAST(SUM(I.valor_itens_teto_maximo) AS DECIMAL(19,2)) AS valor_itens_teto_maximo,
    CAST(COUNT_BIG(*) AS INT) AS qtd_cnpjs
INTO temp_CGUSC.fp.indicador_teto_uf
FROM temp_CGUSC.fp.indicador_teto I
INNER JOIN #farmacias_dim F
    ON F.id_cnpj = I.id_cnpj
GROUP BY
    I.ano_base,
    F.uf;

CREATE UNIQUE CLUSTERED INDEX IDX_IndTetoUF
ON temp_CGUSC.fp.indicador_teto_uf(ano_base, uf);


-- ============================================================================
-- PASSO 5: AGREGADO BRASIL/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_teto_br;

SELECT
    I.ano_base,
    SUM(I.total_itens_monitorados) AS total_itens_monitorados,
    SUM(I.total_itens_teto_maximo) AS total_itens_teto_maximo,
    CAST(SUM(I.valor_total_auditado) AS DECIMAL(19,2)) AS valor_total_auditado,
    CAST(SUM(I.valor_itens_teto_maximo) AS DECIMAL(19,2)) AS valor_itens_teto_maximo,
    CAST(COUNT_BIG(*) AS INT) AS qtd_cnpjs
INTO temp_CGUSC.fp.indicador_teto_br
FROM temp_CGUSC.fp.indicador_teto I
GROUP BY
    I.ano_base;

CREATE UNIQUE CLUSTERED INDEX IDX_IndTetoBR
ON temp_CGUSC.fp.indicador_teto_br(ano_base);
GO


-- ============================================================================
-- LIMPEZA DAS TABELAS INTERMEDIARIAS
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_teto;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_teto_mun;
DROP TABLE IF EXISTS #farmacias_dim;
GO
