USE [temp_CGUSC]
GO

-- ============================================================================
-- INDICADOR DE VENDAS CONSECUTIVAS RAPIDAS
-- ============================================================================
-- OBJETIVO: Identificar farmacias com proporcao atipica de autorizacoes
--           realizadas em intervalo inferior a 60 segundos.
--
-- METRICA PRINCIPAL:
--   O indicador deve ser calculado por periodo a partir dos componentes:
--   valor_vendas_rapidas / valor_total_auditado.
--
-- METRICAS AUXILIARES:
--   total_intervalos_analisados e total_vendas_rapidas permitem recompor o
--   percentual por contagem quando necessario.
--
-- FONTE DE DADOS:
--   - db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024
--   - temp_CGUSC.fp.medicamentos_patologia (universo de medicamentos auditados)
--   - temp_CGUSC.fp.dados_farmacia (id_cnpj e contexto territorial)
-- ============================================================================

-- ============================================================================
-- DEFINICAO DE VARIAVEIS
-- ============================================================================
DECLARE @DataInicio  DATE = '2015-07-01';
DECLARE @DataFim     DATE = '2024-12-10';
DECLARE @LoteTamanho INT  = 50;


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
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'data_hora') IS NULL
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'codigo_barra') IS NULL
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'valor_pago') IS NULL
BEGIN
    RAISERROR('Tabela db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 sem colunas obrigatorias para vendas consecutivas.', 16, 1);
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

-- Tabelas finais/derivadas antigas nao podem permanecer apos mudanca de schema.
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_vendas_consecutivas_mun;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_vendas_consecutivas_uf;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_vendas_consecutivas_regiao;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_vendas_consecutivas_br;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_vendas_consecutivas_detalhado;


-- ============================================================================
-- PASSO 1: TABELA DE RESULTADOS BASE INCREMENTAL
-- ============================================================================
IF OBJECT_ID('temp_CGUSC.fp.indicador_vendas_consecutivas', 'U') IS NULL
BEGIN
    CREATE TABLE temp_CGUSC.fp.indicador_vendas_consecutivas (
        id INT IDENTITY(1,1) PRIMARY KEY,
        id_cnpj INT NOT NULL,
        ano_base SMALLINT NOT NULL,
        total_intervalos_analisados INT NOT NULL,
        total_vendas_rapidas INT NOT NULL,
        valor_total_auditado DECIMAL(9,2) NOT NULL,
        valor_vendas_rapidas DECIMAL(9,2) NOT NULL,
        data_calculo DATETIME NOT NULL DEFAULT GETDATE(),
        CONSTRAINT UQ_IndVendasConsec_CNPJ_Ano UNIQUE (id_cnpj, ano_base)
    );

    CREATE INDEX IDX_Indicador_CNPJ_Ano
    ON temp_CGUSC.fp.indicador_vendas_consecutivas(id_cnpj, ano_base);
END
ELSE IF COL_LENGTH('temp_CGUSC.fp.indicador_vendas_consecutivas', 'id_cnpj') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_vendas_consecutivas', 'ano_base') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_vendas_consecutivas', 'total_intervalos_analisados') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_vendas_consecutivas', 'total_vendas_rapidas') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_vendas_consecutivas', 'valor_total_auditado') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_vendas_consecutivas', 'valor_vendas_rapidas') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_vendas_consecutivas', 'data_calculo') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_vendas_consecutivas', 'qtd_vendas_rapidas') IS NOT NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_vendas_consecutivas', 'percentual_vendas_consecutivas') IS NOT NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_vendas_consecutivas', 'valor_total_analisado') IS NOT NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.indicador_vendas_consecutivas existe com schema incompativel. Recrie a tabela antes de executar.', 16, 1);
    RETURN;
END;


-- ============================================================================
-- PASSO 2: TABELA DE CONTROLE DE PROCESSAMENTO
-- ============================================================================
IF OBJECT_ID('temp_CGUSC.fp.indicador_controle_vendas_consecutivas', 'U') IS NULL
BEGIN
    CREATE TABLE temp_CGUSC.fp.indicador_controle_vendas_consecutivas (
        id INT IDENTITY(1,1) PRIMARY KEY,
        cnpj VARCHAR(14) NOT NULL UNIQUE,
        data_inicio_processamento DATETIME,
        data_fim_processamento DATETIME,
        situacao INT NOT NULL, -- 0=Pendente, 1=Processando, 2=Concluido, 3=Erro
        total_intervalos_analisados INT,
        total_vendas_rapidas INT,
        valor_total_auditado DECIMAL(19,2),
        valor_vendas_rapidas DECIMAL(19,2),
        mensagem_erro VARCHAR(MAX),
        tentativas INT NOT NULL DEFAULT 0
    );

    CREATE INDEX IDX_Controle_Situacao
    ON temp_CGUSC.fp.indicador_controle_vendas_consecutivas(situacao, cnpj);
END
ELSE IF COL_LENGTH('temp_CGUSC.fp.indicador_controle_vendas_consecutivas', 'id') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_controle_vendas_consecutivas', 'cnpj') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_controle_vendas_consecutivas', 'data_inicio_processamento') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_controle_vendas_consecutivas', 'data_fim_processamento') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_controle_vendas_consecutivas', 'situacao') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_controle_vendas_consecutivas', 'total_intervalos_analisados') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_controle_vendas_consecutivas', 'total_vendas_rapidas') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_controle_vendas_consecutivas', 'valor_total_auditado') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_controle_vendas_consecutivas', 'valor_vendas_rapidas') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_controle_vendas_consecutivas', 'mensagem_erro') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_controle_vendas_consecutivas', 'tentativas') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_controle_vendas_consecutivas', 'total_autorizacoes') IS NOT NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_controle_vendas_consecutivas', 'percentual_calculado') IS NOT NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.indicador_controle_vendas_consecutivas existe com schema incompativel. Recrie a tabela antes de executar.', 16, 1);
    RETURN;
END;

INSERT INTO temp_CGUSC.fp.indicador_controle_vendas_consecutivas (cnpj, situacao)
SELECT F.cnpj, 0 AS situacao
FROM #farmacias_dim F
LEFT JOIN temp_CGUSC.fp.indicador_controle_vendas_consecutivas C
    ON C.cnpj = F.cnpj
WHERE C.cnpj IS NULL;

UPDATE temp_CGUSC.fp.indicador_controle_vendas_consecutivas
SET situacao = 0,
    mensagem_erro = 'Reversao para reprocessamento'
WHERE situacao = 1
  AND DATEDIFF(MINUTE, data_inicio_processamento, GETDATE()) > 30;


-- ============================================================================
-- PASSO 3: PROCESSAMENTO INCREMENTAL POR LOTE
-- ============================================================================
DECLARE @CNPJAtual VARCHAR(14);
DECLARE @IdCnpjAtual INT;
DECLARE @Contador INT = 0;
DECLARE @TotalIntervalos INT;
DECLARE @VendasRapidas INT;
DECLARE @ValorTotalAuditado DECIMAL(19,2);
DECLARE @ValorVendasRapidas DECIMAL(19,2);

DECLARE cursor_cnpjs CURSOR LOCAL FAST_FORWARD FOR
    SELECT TOP (@LoteTamanho) cnpj
    FROM temp_CGUSC.fp.indicador_controle_vendas_consecutivas
    WHERE situacao IN (0, 3)
      AND tentativas < 3
    ORDER BY cnpj;

OPEN cursor_cnpjs;
FETCH NEXT FROM cursor_cnpjs INTO @CNPJAtual;

WHILE @@FETCH_STATUS = 0
BEGIN
    BEGIN TRY
        SELECT @IdCnpjAtual = F.id_cnpj
        FROM #farmacias_dim F
        WHERE F.cnpj = @CNPJAtual;

        IF @IdCnpjAtual IS NULL
        BEGIN
            RAISERROR('CNPJ da fila nao encontrado em temp_CGUSC.fp.dados_farmacia.', 16, 1);
        END;

        UPDATE temp_CGUSC.fp.indicador_controle_vendas_consecutivas
        SET situacao = 1,
            data_inicio_processamento = GETDATE(),
            data_fim_processamento = NULL,
            mensagem_erro = NULL,
            tentativas = tentativas + 1
        WHERE cnpj = @CNPJAtual;

        DROP TABLE IF EXISTS #AutorizacoesAgrupadas;

        SELECT
            F.id_cnpj,
            CAST(YEAR(A.data_hora) AS SMALLINT) AS ano_base,
            A.num_autorizacao,
            MIN(A.data_hora) AS data_hora_transacao,
            CAST(SUM(CAST(A.valor_pago AS DECIMAL(19,2))) AS DECIMAL(9,2)) AS valor_autorizacao
        INTO #AutorizacoesAgrupadas
        FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
        INNER JOIN #farmacias_dim F
            ON F.cnpj = A.cnpj
        INNER JOIN #medicamentos_patologia_gtin C
            ON C.codigo_barra = A.codigo_barra
        WHERE A.cnpj = @CNPJAtual
          AND A.data_hora >= @DataInicio
          AND A.data_hora < DATEADD(DAY, 1, @DataFim)
          AND A.num_autorizacao IS NOT NULL
          AND A.codigo_barra IS NOT NULL
          AND A.valor_pago IS NOT NULL
        GROUP BY
            F.id_cnpj,
            YEAR(A.data_hora),
            A.num_autorizacao;

        CREATE CLUSTERED INDEX IDX_AutorizacoesAgrupadas_CNPJ_Ano
        ON #AutorizacoesAgrupadas(id_cnpj, ano_base, data_hora_transacao);

        DROP TABLE IF EXISTS #CalculoVelocidade;

        SELECT
            id_cnpj,
            ano_base,
            num_autorizacao,
            data_hora_transacao,
            valor_autorizacao,
            LAG(data_hora_transacao) OVER (
                PARTITION BY id_cnpj, ano_base
                ORDER BY data_hora_transacao, num_autorizacao
            ) AS data_hora_anterior
        INTO #CalculoVelocidade
        FROM #AutorizacoesAgrupadas;

        CREATE CLUSTERED INDEX IDX_CalculoVelocidade_CNPJ_Ano
        ON #CalculoVelocidade(id_cnpj, ano_base);

        DROP TABLE IF EXISTS #ResultadoCNPJ;

        SELECT
            A.id_cnpj,
            A.ano_base,
            CAST(ISNULL(R.total_intervalos_analisados, 0) AS INT) AS total_intervalos_analisados,
            CAST(ISNULL(R.total_vendas_rapidas, 0) AS INT) AS total_vendas_rapidas,
            CAST(SUM(A.valor_autorizacao) AS DECIMAL(9,2)) AS valor_total_auditado,
            CAST(ISNULL(R.valor_vendas_rapidas, 0) AS DECIMAL(9,2)) AS valor_vendas_rapidas
        INTO #ResultadoCNPJ
        FROM #AutorizacoesAgrupadas A
        LEFT JOIN (
            SELECT
                id_cnpj,
                ano_base,
                CAST(COUNT(*) AS INT) AS total_intervalos_analisados,
                CAST(
                    SUM(
                        CASE
                            WHEN DATEDIFF(SECOND, data_hora_anterior, data_hora_transacao) < 60
                                THEN 1
                            ELSE 0
                        END
                    ) AS INT
                ) AS total_vendas_rapidas,
                CAST(
                    SUM(
                        CASE
                            WHEN DATEDIFF(SECOND, data_hora_anterior, data_hora_transacao) < 60
                                THEN valor_autorizacao
                            ELSE CAST(0 AS DECIMAL(9,2))
                        END
                    ) AS DECIMAL(9,2)
                ) AS valor_vendas_rapidas
            FROM #CalculoVelocidade
            WHERE data_hora_anterior IS NOT NULL
            GROUP BY
                id_cnpj,
                ano_base
        ) R
            ON R.id_cnpj = A.id_cnpj
           AND R.ano_base = A.ano_base
        GROUP BY
            A.id_cnpj,
            A.ano_base,
            R.total_intervalos_analisados,
            R.total_vendas_rapidas,
            R.valor_vendas_rapidas
        HAVING SUM(A.valor_autorizacao) > 0;

        DELETE FROM temp_CGUSC.fp.indicador_vendas_consecutivas
        WHERE id_cnpj = @IdCnpjAtual;

        INSERT INTO temp_CGUSC.fp.indicador_vendas_consecutivas (
            id_cnpj,
            ano_base,
            total_intervalos_analisados,
            total_vendas_rapidas,
            valor_total_auditado,
            valor_vendas_rapidas
        )
        SELECT
            id_cnpj,
            ano_base,
            total_intervalos_analisados,
            total_vendas_rapidas,
            valor_total_auditado,
            valor_vendas_rapidas
        FROM #ResultadoCNPJ;

        SELECT
            @TotalIntervalos = SUM(total_intervalos_analisados),
            @VendasRapidas = SUM(total_vendas_rapidas),
            @ValorTotalAuditado = SUM(valor_total_auditado),
            @ValorVendasRapidas = SUM(valor_vendas_rapidas)
        FROM #ResultadoCNPJ;

        SET @TotalIntervalos = CASE WHEN @TotalIntervalos IS NULL THEN 0 ELSE @TotalIntervalos END;
        SET @VendasRapidas = CASE WHEN @VendasRapidas IS NULL THEN 0 ELSE @VendasRapidas END;
        SET @ValorTotalAuditado = CASE WHEN @ValorTotalAuditado IS NULL THEN 0 ELSE @ValorTotalAuditado END;
        SET @ValorVendasRapidas = CASE WHEN @ValorVendasRapidas IS NULL THEN 0 ELSE @ValorVendasRapidas END;

        UPDATE temp_CGUSC.fp.indicador_controle_vendas_consecutivas
        SET situacao = 2,
            data_fim_processamento = GETDATE(),
            total_intervalos_analisados = @TotalIntervalos,
            total_vendas_rapidas = @VendasRapidas,
            valor_total_auditado = @ValorTotalAuditado,
            valor_vendas_rapidas = @ValorVendasRapidas,
            mensagem_erro = NULL
        WHERE cnpj = @CNPJAtual;

        SET @Contador = @Contador + 1;

        IF @Contador % 10 = 0
            PRINT CONCAT('Processados: ', @Contador, ' CNPJs neste lote.');
    END TRY
    BEGIN CATCH
        UPDATE temp_CGUSC.fp.indicador_controle_vendas_consecutivas
        SET situacao = 3,
            data_fim_processamento = GETDATE(),
            mensagem_erro = ERROR_MESSAGE()
        WHERE cnpj = @CNPJAtual;
    END CATCH;

    SET @IdCnpjAtual = NULL;
    SET @TotalIntervalos = NULL;
    SET @VendasRapidas = NULL;
    SET @ValorTotalAuditado = NULL;
    SET @ValorVendasRapidas = NULL;

    FETCH NEXT FROM cursor_cnpjs INTO @CNPJAtual;
END;

CLOSE cursor_cnpjs;
DEALLOCATE cursor_cnpjs;


-- ============================================================================
-- PASSO 4: RESUMO E CONTROLE DE CONCLUSAO
-- ============================================================================
SELECT
    situacao,
    COUNT(*) AS quantidade,
    CASE situacao
        WHEN 0 THEN 'Pendente'
        WHEN 1 THEN 'Processando'
        WHEN 2 THEN 'Concluido'
        WHEN 3 THEN 'Erro'
    END AS status_descricao
FROM temp_CGUSC.fp.indicador_controle_vendas_consecutivas
GROUP BY situacao
ORDER BY situacao;

DECLARE @Pendentes INT;
DECLARE @ErrosEsgotados INT;

SELECT @Pendentes = COUNT(*)
FROM temp_CGUSC.fp.indicador_controle_vendas_consecutivas
WHERE situacao IN (0, 1)
   OR (situacao = 3 AND tentativas < 3);

SELECT @ErrosEsgotados = COUNT(*)
FROM temp_CGUSC.fp.indicador_controle_vendas_consecutivas
WHERE situacao = 3
  AND tentativas >= 3;

IF @Pendentes > 0
BEGIN
    PRINT '=======================================================================';
    PRINT CONCAT('ATENCAO: Ainda existem ', @Pendentes, ' CNPJs pendentes de processamento.');
    PRINT 'Execute este script novamente para processar o proximo lote.';
    PRINT 'A tabela final sera gerada apenas apos 100% de conclusao.';
    PRINT '=======================================================================';
END
ELSE IF @ErrosEsgotados > 0
BEGIN
    RAISERROR('Existem CNPJs com erro e tentativas esgotadas em indicador_controle_vendas_consecutivas. Corrija a causa antes de gerar a tabela final.', 16, 1);
    RETURN;
END
ELSE
BEGIN
    DECLARE @RegistrosFinal INT;

    PRINT '=======================================================================';
    PRINT 'TODOS OS CNPJs PROCESSADOS. Gerando tabela final...';
    PRINT '=======================================================================';

    -- ========================================================================
    -- PASSO 5: TABELA CONSOLIDADA FINAL POR CNPJ/ANO
    -- ========================================================================
    DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_vendas_consecutivas_detalhado;

    SELECT
        I.id_cnpj,
        I.ano_base,
        I.total_intervalos_analisados,
        I.total_vendas_rapidas,
        CAST(I.valor_total_auditado AS DECIMAL(9,2)) AS valor_total_auditado,
        CAST(I.valor_vendas_rapidas AS DECIMAL(9,2)) AS valor_vendas_rapidas
    INTO temp_CGUSC.fp.indicador_vendas_consecutivas_detalhado
    FROM temp_CGUSC.fp.indicador_vendas_consecutivas I;

    SET @RegistrosFinal = @@ROWCOUNT;

    CREATE UNIQUE CLUSTERED INDEX IDX_FinalVendasConsec_CNPJ
    ON temp_CGUSC.fp.indicador_vendas_consecutivas_detalhado(id_cnpj, ano_base);

    -- ========================================================================
    -- PASSO 6: AGREGADO POR REGIAO DE SAUDE/ANO
    -- ========================================================================
    DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_vendas_consecutivas_regiao;

    SELECT
        I.ano_base,
        F.id_regiao_saude,
        SUM(I.total_intervalos_analisados) AS total_intervalos_analisados,
        SUM(I.total_vendas_rapidas) AS total_vendas_rapidas,
        CAST(SUM(I.valor_total_auditado) AS DECIMAL(19,2)) AS valor_total_auditado,
        CAST(SUM(I.valor_vendas_rapidas) AS DECIMAL(19,2)) AS valor_vendas_rapidas,
        CAST(COUNT_BIG(*) AS INT) AS qtd_cnpjs
    INTO temp_CGUSC.fp.indicador_vendas_consecutivas_regiao
    FROM temp_CGUSC.fp.indicador_vendas_consecutivas I
    INNER JOIN #farmacias_dim F
        ON F.id_cnpj = I.id_cnpj
    GROUP BY
        I.ano_base,
        F.id_regiao_saude;

    CREATE UNIQUE CLUSTERED INDEX IDX_IndVendasConsecReg
    ON temp_CGUSC.fp.indicador_vendas_consecutivas_regiao(ano_base, id_regiao_saude);

    -- ========================================================================
    -- PASSO 7: AGREGADO POR UF/ANO
    -- ========================================================================
    DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_vendas_consecutivas_uf;

    SELECT
        I.ano_base,
        F.uf,
        SUM(I.total_intervalos_analisados) AS total_intervalos_analisados,
        SUM(I.total_vendas_rapidas) AS total_vendas_rapidas,
        CAST(SUM(I.valor_total_auditado) AS DECIMAL(19,2)) AS valor_total_auditado,
        CAST(SUM(I.valor_vendas_rapidas) AS DECIMAL(19,2)) AS valor_vendas_rapidas,
        CAST(COUNT_BIG(*) AS INT) AS qtd_cnpjs
    INTO temp_CGUSC.fp.indicador_vendas_consecutivas_uf
    FROM temp_CGUSC.fp.indicador_vendas_consecutivas I
    INNER JOIN #farmacias_dim F
        ON F.id_cnpj = I.id_cnpj
    GROUP BY
        I.ano_base,
        F.uf;

    CREATE UNIQUE CLUSTERED INDEX IDX_IndVendasConsecUF
    ON temp_CGUSC.fp.indicador_vendas_consecutivas_uf(ano_base, uf);

    -- ========================================================================
    -- PASSO 8: AGREGADO BRASIL/ANO
    -- ========================================================================
    DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_vendas_consecutivas_br;

    SELECT
        I.ano_base,
        SUM(I.total_intervalos_analisados) AS total_intervalos_analisados,
        SUM(I.total_vendas_rapidas) AS total_vendas_rapidas,
        CAST(SUM(I.valor_total_auditado) AS DECIMAL(19,2)) AS valor_total_auditado,
        CAST(SUM(I.valor_vendas_rapidas) AS DECIMAL(19,2)) AS valor_vendas_rapidas,
        CAST(COUNT_BIG(*) AS INT) AS qtd_cnpjs
    INTO temp_CGUSC.fp.indicador_vendas_consecutivas_br
    FROM temp_CGUSC.fp.indicador_vendas_consecutivas I
    GROUP BY
        I.ano_base;

    CREATE UNIQUE CLUSTERED INDEX IDX_IndVendasConsecBR
    ON temp_CGUSC.fp.indicador_vendas_consecutivas_br(ano_base);

    PRINT CONCAT('Tabela final criada com ', @RegistrosFinal, ' registros.');
END;

DROP TABLE IF EXISTS #medicamentos_patologia_gtin;
DROP TABLE IF EXISTS #farmacias_dim;
GO
