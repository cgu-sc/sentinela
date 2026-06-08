USE [temp_CGUSC]
GO

-- ============================================================================
-- INDICADOR DE RECORRENCIA SISTEMICA
-- ============================================================================
-- OBJETIVO: Identificar farmacias com alta proporcao de compras de medicamentos
--           de uso continuo realizadas exatamente no limite do bloqueio legal.
--
-- METRICA PRINCIPAL:
--   O indicador deve ser calculado por periodo a partir dos componentes:
--   valor_renovacoes_sistemicas / valor_total_auditado.
--
-- METRICAS AUXILIARES:
--   total_renovacoes_monitoradas e total_renovacoes_sistemicas permitem recompor
--   o percentual por contagem quando necessario. A regra de volume minimo deve
--   ser aplicada depois da soma do periodo selecionado.
--
-- FONTE DE DADOS:
--   - db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024
--   - temp_CGUSC.fp.medicamentos_patologia
--   - temp_CGUSC.fp.posologia_tempo_bloqueio
--   - temp_CGUSC.fp.dados_farmacia (id_cnpj e contexto territorial)
-- ============================================================================

-- ============================================================================
-- LIMPEZA PREVIA DE TABELAS
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_recorrencia_sistemica;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_recorrencia_sistemica_mun;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_recorrencia_sistemica_uf;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_recorrencia_sistemica_regiao;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_recorrencia_sistemica_br;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_recorrencia_sistemica_detalhado;
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
   OR COL_LENGTH('temp_CGUSC.fp.medicamentos_patologia', 'qnt_comprimidos_caixa') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.medicamentos_patologia sem colunas obrigatorias codigo_barra/principio_ativo/qnt_comprimidos_caixa.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('temp_CGUSC.fp.posologia_tempo_bloqueio', 'U') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.posologia_tempo_bloqueio nao encontrada.', 16, 1);
    RETURN;
END;

IF COL_LENGTH('temp_CGUSC.fp.posologia_tempo_bloqueio', 'PRINCIPIO_ATIVO') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.posologia_tempo_bloqueio', 'PROXIMA_COMPRA') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.posologia_tempo_bloqueio sem colunas obrigatorias PRINCIPIO_ATIVO/PROXIMA_COMPRA.', 16, 1);
    RETURN;
END;

IF EXISTS (
    SELECT 1
    FROM temp_CGUSC.fp.posologia_tempo_bloqueio
    WHERE NULLIF(LTRIM(RTRIM(CAST(PRINCIPIO_ATIVO AS VARCHAR(255)))), '') IS NULL
       OR PROXIMA_COMPRA IS NULL
       OR TRY_CAST(PROXIMA_COMPRA AS INT) IS NULL
)
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.posologia_tempo_bloqueio possui PRINCIPIO_ATIVO/PROXIMA_COMPRA invalidos.', 16, 1);
    RETURN;
END;

IF EXISTS (
    SELECT 1
    FROM temp_CGUSC.fp.posologia_tempo_bloqueio
    GROUP BY UPPER(LTRIM(RTRIM(CAST(PRINCIPIO_ATIVO AS VARCHAR(255)))))
    HAVING COUNT(DISTINCT TRY_CAST(PROXIMA_COMPRA AS INT)) > 1
)
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.posologia_tempo_bloqueio possui PROXIMA_COMPRA conflitante para o mesmo PRINCIPIO_ATIVO.', 16, 1);
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
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'cpf') IS NULL
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'data_hora') IS NULL
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'codigo_barra') IS NULL
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'qnt_autorizada') IS NULL
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'valor_pago') IS NULL
BEGIN
    RAISERROR('Tabela db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 sem colunas obrigatorias para recorrencia sistemica.', 16, 1);
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

DROP TABLE IF EXISTS #medicamentos_recorrencia;

SELECT DISTINCT
    MP.codigo_barra,
    CAST(UPPER(LTRIM(RTRIM(MP.principio_ativo))) AS VARCHAR(255)) AS principio_ativo,
    CAST(MP.qnt_comprimidos_caixa AS DECIMAL(10,0)) AS qnt_comprimidos_caixa,
    CAST(P.PROXIMA_COMPRA AS INT) AS dias_para_bloqueio
INTO #medicamentos_recorrencia
FROM temp_CGUSC.fp.medicamentos_patologia MP
INNER JOIN temp_CGUSC.fp.posologia_tempo_bloqueio P
    ON UPPER(LTRIM(RTRIM(P.PRINCIPIO_ATIVO))) = UPPER(LTRIM(RTRIM(MP.principio_ativo)))
WHERE MP.codigo_barra IS NOT NULL
  AND NULLIF(LTRIM(RTRIM(MP.principio_ativo)), '') IS NOT NULL
  AND TRY_CAST(MP.qnt_comprimidos_caixa AS DECIMAL(10,0)) IS NOT NULL
  AND TRY_CAST(MP.qnt_comprimidos_caixa AS DECIMAL(10,0)) <> 0;

IF NOT EXISTS (SELECT 1 FROM #medicamentos_recorrencia)
BEGIN
    RAISERROR('Nao ha medicamentos auditados com posologia de bloqueio valida para recorrencia sistemica.', 16, 1);
    RETURN;
END;

IF EXISTS (
    SELECT 1
    FROM #medicamentos_recorrencia
    GROUP BY codigo_barra
    HAVING COUNT_BIG(*) > 1
)
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.medicamentos_patologia possui codigo_barra associado a multiplos principios ativos/bloqueios para recorrencia sistemica.', 16, 1);
    RETURN;
END;

CREATE CLUSTERED INDEX IDX_medicamentos_recorrencia_gtin
ON #medicamentos_recorrencia(codigo_barra);


-- ============================================================================
-- PASSO 1: HISTORICO DE COMPRAS POR FARMACIA/CPF/PRINCIPIO ATIVO
-- ============================================================================
DROP TABLE IF EXISTS #ComprasBase;

SELECT
    F.id_cnpj,
    CAST(A.cpf AS VARCHAR(20)) AS cpf,
    M.principio_ativo,
    M.dias_para_bloqueio,
    CAST(A.data_hora AS DATETIME) AS data_compra,
    CAST(SUM(CAST(A.valor_pago AS DECIMAL(19,2))) AS DECIMAL(9,2)) AS valor_compra
INTO #ComprasBase
FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
INNER JOIN #farmacias_dim F
    ON F.cnpj = A.cnpj
INNER JOIN #medicamentos_recorrencia M
    ON M.codigo_barra = A.codigo_barra
WHERE A.data_hora >= @DataInicio
  AND A.data_hora < DATEADD(DAY, 1, @DataFim)
  AND NULLIF(LTRIM(RTRIM(CAST(A.cpf AS VARCHAR(20)))), '') IS NOT NULL
  AND A.codigo_barra IS NOT NULL
  AND A.qnt_autorizada IS NOT NULL
  AND (A.qnt_autorizada / M.qnt_comprimidos_caixa) <> 0
  AND A.valor_pago IS NOT NULL
GROUP BY
    F.id_cnpj,
    CAST(A.cpf AS VARCHAR(20)),
    M.principio_ativo,
    M.dias_para_bloqueio,
    CAST(A.data_hora AS DATETIME);

CREATE CLUSTERED INDEX IDX_ComprasBase_CNPJ_CPF
ON #ComprasBase(id_cnpj, cpf, principio_ativo, data_compra);

DROP TABLE IF EXISTS #HistoricoCompras;

SELECT
    id_cnpj,
    CAST(YEAR(data_compra) AS SMALLINT) AS ano_base,
    cpf,
    principio_ativo,
    dias_para_bloqueio,
    data_compra AS data_compra_atual,
    valor_compra AS valor_compra_atual,
    LAG(data_compra) OVER (
        PARTITION BY id_cnpj, cpf, principio_ativo
        ORDER BY data_compra ASC
    ) AS data_compra_anterior
INTO #HistoricoCompras
FROM #ComprasBase;

CREATE CLUSTERED INDEX IDX_HistoricoCompras_CNPJ_Ano
ON #HistoricoCompras(id_cnpj, ano_base);

DROP TABLE IF EXISTS #ComprasBase;
DROP TABLE IF EXISTS #medicamentos_recorrencia;


-- ============================================================================
-- PASSO 2: CALCULO BASE POR FARMACIA/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_recorrencia_sistemica;

SELECT
    id_cnpj,
    ano_base,
    CAST(COUNT(*) AS INT) AS total_renovacoes_monitoradas,
    CAST(
        SUM(
            CASE
                WHEN DATEDIFF(DAY, data_compra_anterior, data_compra_atual)
                     BETWEEN dias_para_bloqueio AND (dias_para_bloqueio + 1)
                    THEN 1
                ELSE 0
            END
        ) AS INT
    ) AS total_renovacoes_sistemicas,
    CAST(SUM(valor_compra_atual) AS DECIMAL(9,2)) AS valor_total_auditado,
    CAST(
        SUM(
            CASE
                WHEN DATEDIFF(DAY, data_compra_anterior, data_compra_atual)
                     BETWEEN dias_para_bloqueio AND (dias_para_bloqueio + 1)
                    THEN valor_compra_atual
                ELSE CAST(0 AS DECIMAL(9,2))
            END
        ) AS DECIMAL(9,2)
    ) AS valor_renovacoes_sistemicas
INTO temp_CGUSC.fp.indicador_recorrencia_sistemica
FROM #HistoricoCompras
WHERE data_compra_anterior IS NOT NULL
GROUP BY
    id_cnpj,
    ano_base
HAVING SUM(valor_compra_atual) > 0;

CREATE UNIQUE CLUSTERED INDEX IDX_IndRecorrencia_CNPJ_Ano
ON temp_CGUSC.fp.indicador_recorrencia_sistemica(id_cnpj, ano_base);

DROP TABLE IF EXISTS #HistoricoCompras;


-- ============================================================================
-- PASSO 3: TABELA CONSOLIDADA FINAL POR CNPJ/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_recorrencia_sistemica_detalhado;

SELECT
    I.id_cnpj,
    I.ano_base,
    I.total_renovacoes_monitoradas,
    I.total_renovacoes_sistemicas,
    CAST(I.valor_total_auditado AS DECIMAL(9,2)) AS valor_total_auditado,
    CAST(I.valor_renovacoes_sistemicas AS DECIMAL(9,2)) AS valor_renovacoes_sistemicas
INTO temp_CGUSC.fp.indicador_recorrencia_sistemica_detalhado
FROM temp_CGUSC.fp.indicador_recorrencia_sistemica I;

CREATE UNIQUE CLUSTERED INDEX IDX_FinalRecorrencia_CNPJ
ON temp_CGUSC.fp.indicador_recorrencia_sistemica_detalhado(id_cnpj, ano_base);


-- ============================================================================
-- PASSO 4: AGREGADO POR REGIAO DE SAUDE/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_recorrencia_sistemica_regiao;

SELECT
    I.ano_base,
    F.id_regiao_saude,
    SUM(I.total_renovacoes_monitoradas) AS total_renovacoes_monitoradas,
    SUM(I.total_renovacoes_sistemicas) AS total_renovacoes_sistemicas,
    CAST(SUM(I.valor_total_auditado) AS DECIMAL(19,2)) AS valor_total_auditado,
    CAST(SUM(I.valor_renovacoes_sistemicas) AS DECIMAL(19,2)) AS valor_renovacoes_sistemicas,
    CAST(COUNT_BIG(*) AS INT) AS qtd_cnpjs
INTO temp_CGUSC.fp.indicador_recorrencia_sistemica_regiao
FROM temp_CGUSC.fp.indicador_recorrencia_sistemica I
INNER JOIN #farmacias_dim F
    ON F.id_cnpj = I.id_cnpj
GROUP BY
    I.ano_base,
    F.id_regiao_saude;

CREATE UNIQUE CLUSTERED INDEX IDX_IndRecorrReg
ON temp_CGUSC.fp.indicador_recorrencia_sistemica_regiao(ano_base, id_regiao_saude);


-- ============================================================================
-- PASSO 5: AGREGADO POR UF/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_recorrencia_sistemica_uf;

SELECT
    I.ano_base,
    F.uf,
    SUM(I.total_renovacoes_monitoradas) AS total_renovacoes_monitoradas,
    SUM(I.total_renovacoes_sistemicas) AS total_renovacoes_sistemicas,
    CAST(SUM(I.valor_total_auditado) AS DECIMAL(19,2)) AS valor_total_auditado,
    CAST(SUM(I.valor_renovacoes_sistemicas) AS DECIMAL(19,2)) AS valor_renovacoes_sistemicas,
    CAST(COUNT_BIG(*) AS INT) AS qtd_cnpjs
INTO temp_CGUSC.fp.indicador_recorrencia_sistemica_uf
FROM temp_CGUSC.fp.indicador_recorrencia_sistemica I
INNER JOIN #farmacias_dim F
    ON F.id_cnpj = I.id_cnpj
GROUP BY
    I.ano_base,
    F.uf;

CREATE UNIQUE CLUSTERED INDEX IDX_IndRecorrUF
ON temp_CGUSC.fp.indicador_recorrencia_sistemica_uf(ano_base, uf);


-- ============================================================================
-- PASSO 6: AGREGADO BRASIL/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_recorrencia_sistemica_br;

SELECT
    I.ano_base,
    SUM(I.total_renovacoes_monitoradas) AS total_renovacoes_monitoradas,
    SUM(I.total_renovacoes_sistemicas) AS total_renovacoes_sistemicas,
    CAST(SUM(I.valor_total_auditado) AS DECIMAL(19,2)) AS valor_total_auditado,
    CAST(SUM(I.valor_renovacoes_sistemicas) AS DECIMAL(19,2)) AS valor_renovacoes_sistemicas,
    CAST(COUNT_BIG(*) AS INT) AS qtd_cnpjs
INTO temp_CGUSC.fp.indicador_recorrencia_sistemica_br
FROM temp_CGUSC.fp.indicador_recorrencia_sistemica I
GROUP BY
    I.ano_base;

CREATE UNIQUE CLUSTERED INDEX IDX_IndRecorrBR
ON temp_CGUSC.fp.indicador_recorrencia_sistemica_br(ano_base);
GO


-- ============================================================================
-- LIMPEZA DAS TABELAS INTERMEDIARIAS
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_recorrencia_sistemica;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_recorrencia_sistemica_mun;
DROP TABLE IF EXISTS #farmacias_dim;
GO
