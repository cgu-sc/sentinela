USE [temp_CGUSC]
GO

-- ============================================================================
-- INDICADOR DE FALECIDOS
-- ============================================================================
-- OBJETIVO: Identificar dispensacoes registradas apos a data de obito dos
--           beneficiarios, preservando o detalhamento nominal por autorizacao
--           e gerando indicador anual por farmacia.
--
-- METRICA PRINCIPAL:
--   O indicador deve ser calculado por periodo a partir dos componentes:
--   valor_falecidos / valor_total_auditado.
--
-- METRICAS AUXILIARES:
--   total_autorizacoes e qtd_autorizacoes_falecidos permitem recompor o
--   percentual por contagem quando necessario.
--
-- FONTE DE DADOS:
--   - db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024
--   - temp_CGUSC.fp.obito_unificada
--   - db_CPF.dbo.CPF
--   - temp_CGUSC.fp.medicamentos_patologia
--   - temp_CGUSC.fp.dados_farmacia
-- ============================================================================

-- ============================================================================
-- LIMPEZA PREVIA DE TABELAS DE STAGING
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.falecidos_por_farmacia_staging;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_falecidos_detalhado_staging;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_falecidos_regiao_staging;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_falecidos_uf_staging;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_falecidos_br_staging;
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
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'cpf') IS NULL
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'num_autorizacao') IS NULL
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'qnt_autorizada') IS NULL
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'valor_pago') IS NULL
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'data_hora') IS NULL
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'codigo_barra') IS NULL
BEGIN
    RAISERROR('Tabela db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 sem colunas obrigatorias para falecidos.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('temp_CGUSC.fp.obito_unificada', 'U') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.obito_unificada nao encontrada.', 16, 1);
    RETURN;
END;

IF COL_LENGTH('temp_CGUSC.fp.obito_unificada', 'cpf') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.obito_unificada', 'dt_nascimento') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.obito_unificada', 'dt_obito') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.obito_unificada', 'fonte') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.obito_unificada sem colunas obrigatorias cpf/dt_nascimento/dt_obito/fonte.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('db_CPF.dbo.CPF', 'U') IS NULL
BEGIN
    RAISERROR('Tabela db_CPF.dbo.CPF nao encontrada.', 16, 1);
    RETURN;
END;

IF COL_LENGTH('db_CPF.dbo.CPF', 'CPF') IS NULL
   OR COL_LENGTH('db_CPF.dbo.CPF', 'nome') IS NULL
   OR COL_LENGTH('db_CPF.dbo.CPF', 'nomeMunicipio') IS NULL
   OR COL_LENGTH('db_CPF.dbo.CPF', 'unidadeFederacao') IS NULL
BEGIN
    RAISERROR('Tabela db_CPF.dbo.CPF sem colunas obrigatorias CPF/nome/nomeMunicipio/unidadeFederacao.', 16, 1);
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


DROP TABLE IF EXISTS #AutorizacoesAuditadas;

SELECT
    F.id_cnpj,
    F.cnpj,
    CAST(YEAR(A.data_hora) AS SMALLINT) AS ano_base,
    A.num_autorizacao,
    A.cpf,
    MIN(A.data_hora) AS data_autorizacao,
    CAST(SUM(CAST(A.valor_pago AS DECIMAL(19,2))) AS DECIMAL(9,2)) AS valor_total_autorizacao,
    CAST(COUNT_BIG(*) AS INT) AS qtd_itens_na_autorizacao
INTO #AutorizacoesAuditadas
FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
INNER JOIN #farmacias_dim F
    ON F.cnpj = A.cnpj
INNER JOIN #medicamentos_patologia_gtin C
    ON C.codigo_barra = A.codigo_barra
WHERE A.data_hora >= @DataInicio
  AND A.data_hora < DATEADD(DAY, 1, @DataFim)
  AND A.cpf IS NOT NULL
  AND A.num_autorizacao IS NOT NULL
  AND A.valor_pago IS NOT NULL
  AND A.valor_pago >= 0
  AND A.codigo_barra IS NOT NULL
  AND A.qnt_autorizada IS NOT NULL
  AND (A.qnt_autorizada / C.qnt_comprimidos_caixa) <> 0
GROUP BY
    F.id_cnpj,
    F.cnpj,
    YEAR(A.data_hora),
    A.num_autorizacao,
    A.cpf;

IF NOT EXISTS (SELECT 1 FROM #AutorizacoesAuditadas)
BEGIN
    RAISERROR('Nao ha autorizacoes auditadas para falecidos no periodo informado.', 16, 1);
    RETURN;
END;

CREATE CLUSTERED INDEX IDX_AutorizacoesAuditadas_CNPJ_Ano
ON #AutorizacoesAuditadas(id_cnpj, ano_base);

CREATE NONCLUSTERED INDEX IDX_AutorizacoesAuditadas_Auto
ON #AutorizacoesAuditadas(id_cnpj, ano_base, num_autorizacao, cpf);

CREATE NONCLUSTERED INDEX IDX_AutorizacoesAuditadas_CPF
ON #AutorizacoesAuditadas(cpf);

DROP TABLE IF EXISTS #cpfs_auditados;

SELECT DISTINCT cpf
INTO #cpfs_auditados
FROM #AutorizacoesAuditadas;

CREATE UNIQUE CLUSTERED INDEX IDX_cpfs_auditados
ON #cpfs_auditados(cpf);

DROP TABLE IF EXISTS #obitos_unificados;

SELECT
    OB.cpf,
    MIN(OB.dt_nascimento) AS dt_nascimento,
    MIN(OB.dt_obito) AS dt_obito,
    MAX(OB.fonte) AS fonte
INTO #obitos_unificados
FROM temp_CGUSC.fp.obito_unificada OB
INNER JOIN #cpfs_auditados C
    ON C.cpf = OB.cpf
WHERE OB.dt_obito IS NOT NULL
GROUP BY OB.cpf;

CREATE UNIQUE CLUSTERED INDEX IDX_obitos_unificados
ON #obitos_unificados(cpf);


-- ============================================================================
-- PASSO 2: AUTORIZACOES REALIZADAS APOS OBITO
-- ============================================================================
DROP TABLE IF EXISTS #FalecidosAutorizacoes;

SELECT
    A.id_cnpj,
    A.cnpj,
    A.ano_base,
    A.cpf,
    OB.dt_nascimento,
    OB.dt_obito,
    OB.fonte AS fonte_obito,
    A.num_autorizacao,
    A.data_autorizacao,
    A.qtd_itens_na_autorizacao,
    A.valor_total_autorizacao,
    DATEDIFF(DAY, OB.dt_obito, A.data_autorizacao) AS dias_apos_obito
INTO #FalecidosAutorizacoes
FROM #AutorizacoesAuditadas A
INNER JOIN #obitos_unificados OB
    ON OB.cpf = A.cpf
WHERE A.data_autorizacao > OB.dt_obito;

CREATE CLUSTERED INDEX IDX_FalecidosAutorizacoes_CNPJ_Ano
ON #FalecidosAutorizacoes(id_cnpj, ano_base);

CREATE NONCLUSTERED INDEX IDX_FalecidosAutorizacoes_Auto
ON #FalecidosAutorizacoes(id_cnpj, ano_base, num_autorizacao, cpf);

CREATE NONCLUSTERED INDEX IDX_FalecidosAutorizacoes_CPF
ON #FalecidosAutorizacoes(cpf);

DROP TABLE IF EXISTS #cpfs_falecidos;

SELECT DISTINCT cpf
INTO #cpfs_falecidos
FROM #FalecidosAutorizacoes;

CREATE UNIQUE CLUSTERED INDEX IDX_cpfs_falecidos
ON #cpfs_falecidos(cpf);

DROP TABLE IF EXISTS #cpf_info;

SELECT
    B.CPF AS cpf,
    MAX(B.nome) AS nome_falecido,
    MAX(B.nomeMunicipio) AS municipio_falecido,
    MAX(B.unidadeFederacao) AS uf_falecido
INTO #cpf_info
FROM #cpfs_falecidos C
INNER JOIN db_CPF.dbo.CPF B
    ON B.CPF = C.cpf
GROUP BY B.CPF;

CREATE UNIQUE CLUSTERED INDEX IDX_cpf_info
ON #cpf_info(cpf);


-- ============================================================================
-- PASSO 3: DETALHAMENTO NOMINAL POR AUTORIZACAO
-- Mantem o contrato historico de colunas consumido pela API/cache.
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.falecidos_por_farmacia_staging;

SELECT
    F.cnpj,
    F.cpf,
    I.nome_falecido,
    I.municipio_falecido,
    I.uf_falecido,
    F.dt_nascimento,
    F.dt_obito,
    F.fonte_obito,
    F.num_autorizacao,
    F.data_autorizacao,
    CAST(F.qtd_itens_na_autorizacao AS TINYINT) AS qtd_itens_na_autorizacao,
    CAST(F.valor_total_autorizacao AS DECIMAL(9,2)) AS valor_total_autorizacao,
    CAST(F.dias_apos_obito AS SMALLINT) AS dias_apos_obito
INTO temp_CGUSC.fp.falecidos_por_farmacia_staging
FROM #FalecidosAutorizacoes F
LEFT JOIN #cpf_info I
    ON I.cpf = F.cpf;

CREATE CLUSTERED INDEX IDX_FalecFarm_CNPJ_Staging
ON temp_CGUSC.fp.falecidos_por_farmacia_staging(cnpj);

CREATE NONCLUSTERED INDEX IDX_FalecFarm_Auto_Staging
ON temp_CGUSC.fp.falecidos_por_farmacia_staging(num_autorizacao);

CREATE NONCLUSTERED INDEX IDX_FalecFarm_CPF_Staging
ON temp_CGUSC.fp.falecidos_por_farmacia_staging(cpf);


-- ============================================================================
-- PASSO 4: CALCULO BASE POR FARMACIA/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_falecidos;
DROP TABLE IF EXISTS #IndicadorFalecidosTotal;
DROP TABLE IF EXISTS #IndicadorFalecidosObitos;

SELECT
    A.id_cnpj,
    A.ano_base,
    CAST(COUNT_BIG(*) AS INT) AS total_autorizacoes,
    CAST(SUM(A.valor_total_autorizacao) AS DECIMAL(9,2)) AS valor_total_auditado
INTO #IndicadorFalecidosTotal
FROM (
    SELECT
        A.id_cnpj,
        A.ano_base,
        A.num_autorizacao,
        SUM(A.valor_total_autorizacao) AS valor_total_autorizacao
    FROM #AutorizacoesAuditadas A
    GROUP BY
        A.id_cnpj,
        A.ano_base,
        A.num_autorizacao
) A
GROUP BY
    A.id_cnpj,
    A.ano_base
HAVING SUM(A.valor_total_autorizacao) > 0;

CREATE UNIQUE CLUSTERED INDEX IDX_IndicadorFalecidosTotal_CNPJ_Ano
ON #IndicadorFalecidosTotal(id_cnpj, ano_base);

SELECT
    F.id_cnpj,
    F.ano_base,
    CAST(COUNT_BIG(*) AS INT) AS qtd_autorizacoes_falecidos,
    CAST(SUM(F.valor_total_autorizacao) AS DECIMAL(9,2)) AS valor_falecidos
INTO #IndicadorFalecidosObitos
FROM (
    SELECT
        F.id_cnpj,
        F.ano_base,
        F.num_autorizacao,
        SUM(F.valor_total_autorizacao) AS valor_total_autorizacao
    FROM #FalecidosAutorizacoes F
    GROUP BY
        F.id_cnpj,
        F.ano_base,
        F.num_autorizacao
) F
GROUP BY
    F.id_cnpj,
    F.ano_base;

CREATE UNIQUE CLUSTERED INDEX IDX_IndicadorFalecidosObitos_CNPJ_Ano
ON #IndicadorFalecidosObitos(id_cnpj, ano_base);

SELECT
    T.id_cnpj,
    T.ano_base,
    T.total_autorizacoes,
    CAST(COALESCE(F.qtd_autorizacoes_falecidos, 0) AS INT) AS qtd_autorizacoes_falecidos,
    T.valor_total_auditado,
    CAST(COALESCE(F.valor_falecidos, 0) AS DECIMAL(9,2)) AS valor_falecidos
INTO temp_CGUSC.fp.indicador_falecidos
FROM #IndicadorFalecidosTotal T
LEFT JOIN #IndicadorFalecidosObitos F
    ON F.id_cnpj = T.id_cnpj
   AND F.ano_base = T.ano_base;

CREATE UNIQUE CLUSTERED INDEX IDX_IndFalecidos_CNPJ_Ano
ON temp_CGUSC.fp.indicador_falecidos(id_cnpj, ano_base);


-- ============================================================================
-- PASSO 5: TABELA CONSOLIDADA FINAL POR CNPJ/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_falecidos_detalhado_staging;

SELECT
    I.id_cnpj,
    I.ano_base,
    I.total_autorizacoes,
    I.qtd_autorizacoes_falecidos,
    CAST(I.valor_total_auditado AS DECIMAL(9,2)) AS valor_total_auditado,
    CAST(I.valor_falecidos AS DECIMAL(9,2)) AS valor_falecidos
INTO temp_CGUSC.fp.indicador_falecidos_detalhado_staging
FROM temp_CGUSC.fp.indicador_falecidos I;

CREATE UNIQUE CLUSTERED INDEX IDX_FinalFalecidos_CNPJ_Staging
ON temp_CGUSC.fp.indicador_falecidos_detalhado_staging(id_cnpj, ano_base);


-- ============================================================================
-- PASSO 6: AGREGADO POR REGIAO DE SAUDE/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_falecidos_regiao_staging;

SELECT
    I.ano_base,
    F.id_regiao_saude,
    SUM(I.total_autorizacoes) AS total_autorizacoes,
    SUM(I.qtd_autorizacoes_falecidos) AS qtd_autorizacoes_falecidos,
    CAST(SUM(I.valor_total_auditado) AS DECIMAL(19,2)) AS valor_total_auditado,
    CAST(SUM(I.valor_falecidos) AS DECIMAL(19,2)) AS valor_falecidos,
    CAST(COUNT_BIG(*) AS INT) AS qtd_cnpjs
INTO temp_CGUSC.fp.indicador_falecidos_regiao_staging
FROM temp_CGUSC.fp.indicador_falecidos I
INNER JOIN #farmacias_dim F
    ON F.id_cnpj = I.id_cnpj
GROUP BY
    I.ano_base,
    F.id_regiao_saude;

CREATE UNIQUE CLUSTERED INDEX IDX_IndFalecidosReg_Staging
ON temp_CGUSC.fp.indicador_falecidos_regiao_staging(ano_base, id_regiao_saude);


-- ============================================================================
-- PASSO 7: AGREGADO POR UF/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_falecidos_uf_staging;

SELECT
    I.ano_base,
    F.uf,
    SUM(I.total_autorizacoes) AS total_autorizacoes,
    SUM(I.qtd_autorizacoes_falecidos) AS qtd_autorizacoes_falecidos,
    CAST(SUM(I.valor_total_auditado) AS DECIMAL(19,2)) AS valor_total_auditado,
    CAST(SUM(I.valor_falecidos) AS DECIMAL(19,2)) AS valor_falecidos,
    CAST(COUNT_BIG(*) AS INT) AS qtd_cnpjs
INTO temp_CGUSC.fp.indicador_falecidos_uf_staging
FROM temp_CGUSC.fp.indicador_falecidos I
INNER JOIN #farmacias_dim F
    ON F.id_cnpj = I.id_cnpj
GROUP BY
    I.ano_base,
    F.uf;

CREATE UNIQUE CLUSTERED INDEX IDX_IndFalecidosUF_Staging
ON temp_CGUSC.fp.indicador_falecidos_uf_staging(ano_base, uf);


-- ============================================================================
-- PASSO 8: AGREGADO BRASIL/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_falecidos_br_staging;

SELECT
    I.ano_base,
    SUM(I.total_autorizacoes) AS total_autorizacoes,
    SUM(I.qtd_autorizacoes_falecidos) AS qtd_autorizacoes_falecidos,
    CAST(SUM(I.valor_total_auditado) AS DECIMAL(19,2)) AS valor_total_auditado,
    CAST(SUM(I.valor_falecidos) AS DECIMAL(19,2)) AS valor_falecidos,
    CAST(COUNT_BIG(*) AS INT) AS qtd_cnpjs
INTO temp_CGUSC.fp.indicador_falecidos_br_staging
FROM temp_CGUSC.fp.indicador_falecidos I
GROUP BY
    I.ano_base;

CREATE UNIQUE CLUSTERED INDEX IDX_IndFalecidosBR_Staging
ON temp_CGUSC.fp.indicador_falecidos_br_staging(ano_base);


-- ============================================================================
-- PASSO 9: TROCA ATOMICA DAS TABELAS FINAIS
-- ============================================================================
BEGIN TRY
    BEGIN TRAN;

    DROP TABLE IF EXISTS temp_CGUSC.fp.falecidos_por_farmacia;
    DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_falecidos_detalhado;
    DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_falecidos_regiao;
    DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_falecidos_uf;
    DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_falecidos_br;
    DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_falecidos_mun;

    EXEC sp_rename 'fp.falecidos_por_farmacia_staging', 'falecidos_por_farmacia', 'OBJECT';
    EXEC sp_rename 'fp.indicador_falecidos_detalhado_staging', 'indicador_falecidos_detalhado', 'OBJECT';
    EXEC sp_rename 'fp.indicador_falecidos_regiao_staging', 'indicador_falecidos_regiao', 'OBJECT';
    EXEC sp_rename 'fp.indicador_falecidos_uf_staging', 'indicador_falecidos_uf', 'OBJECT';
    EXEC sp_rename 'fp.indicador_falecidos_br_staging', 'indicador_falecidos_br', 'OBJECT';

    COMMIT TRAN;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRAN;

    THROW;
END CATCH;
GO


-- ============================================================================
-- LIMPEZA DAS TABELAS INTERMEDIARIAS
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_falecidos;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_falecidos_mun;
DROP TABLE IF EXISTS #AutorizacoesAuditadas;
DROP TABLE IF EXISTS #IndicadorFalecidosTotal;
DROP TABLE IF EXISTS #IndicadorFalecidosObitos;
DROP TABLE IF EXISTS #cpfs_auditados;
DROP TABLE IF EXISTS #obitos_unificados;
DROP TABLE IF EXISTS #FalecidosAutorizacoes;
DROP TABLE IF EXISTS #cpfs_falecidos;
DROP TABLE IF EXISTS #cpf_info;
DROP TABLE IF EXISTS #medicamentos_patologia_gtin;
DROP TABLE IF EXISTS #farmacias_dim;
GO
