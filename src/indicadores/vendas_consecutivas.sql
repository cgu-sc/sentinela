USE [temp_CGUSC]
GO

-- ============================================================================
-- DEFINICAO DE VARIAVEIS
-- ============================================================================
DECLARE @DataInicio     DATE = '2015-07-01';
DECLARE @DataFim        DATE = '2024-12-10';
DECLARE @LoteTamanho    INT  = 50;

-- ============================================================================
-- PASSO 0: CRIAR TABELA DE RESULTADOS BASE (SE NAO EXISTIR)
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.objects 
               WHERE object_id = OBJECT_ID(N'temp_CGUSC.fp.indicador_vendas_consecutivas') 
               AND type in (N'U'))
BEGIN
    CREATE TABLE temp_CGUSC.fp.indicador_vendas_consecutivas (
        id INT IDENTITY(1,1) PRIMARY KEY,
        cnpj VARCHAR(14) NOT NULL UNIQUE,
        total_intervalos_analisados INT,
        qtd_vendas_rapidas INT,
        percentual_vendas_consecutivas DECIMAL(18,4),
        data_calculo DATETIME DEFAULT GETDATE()
    );

    CREATE INDEX IDX_Indicador_CNPJ       ON temp_CGUSC.fp.indicador_vendas_consecutivas(cnpj);
    CREATE INDEX IDX_Indicador_Percentual ON temp_CGUSC.fp.indicador_vendas_consecutivas(percentual_vendas_consecutivas);
END

-- ============================================================================
-- PASSO 1: TABELA DE CONTROLE DE PROCESSAMENTO
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.objects 
               WHERE object_id = OBJECT_ID(N'temp_CGUSC.fp.indicador_controle_vendas_consecutivas') 
               AND type in (N'U'))
BEGIN
    CREATE TABLE temp_CGUSC.fp.indicador_controle_vendas_consecutivas (
        id INT IDENTITY(1,1) PRIMARY KEY,
        cnpj VARCHAR(14) NOT NULL UNIQUE,
        data_inicio_processamento DATETIME,
        data_fim_processamento DATETIME,
        situacao INT,           -- 0=Pendente, 1=Processando, 2=Concluido, 3=Erro
        total_autorizacoes INT,
        total_vendas_rapidas INT,
        percentual_calculado DECIMAL(18,4),
        mensagem_erro VARCHAR(MAX),
        tentativas INT DEFAULT 0
    );

    CREATE INDEX IDX_Controle_Situacao ON temp_CGUSC.fp.indicador_controle_vendas_consecutivas(situacao, cnpj);
END

-- Popula fila com CNPJs ainda nao processados (fonte alinhada com geografico.sql)
INSERT INTO temp_CGUSC.fp.indicador_controle_vendas_consecutivas (cnpj, situacao)
SELECT DISTINCT A.cnpj, 0 AS situacao
FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
LEFT JOIN temp_CGUSC.fp.indicador_controle_vendas_consecutivas C ON C.cnpj = A.cnpj
WHERE C.cnpj IS NULL;

-- ============================================================================
-- PASSO 2: RECUPERACAO DE PROCESSAMENTOS TRAVADOS
-- ============================================================================
UPDATE temp_CGUSC.fp.indicador_controle_vendas_consecutivas
SET situacao = 0,
    mensagem_erro = 'Reversao para reprocessamento'
WHERE situacao = 1
  AND DATEDIFF(MINUTE, data_inicio_processamento, GETDATE()) > 30;

-- ============================================================================
-- PASSO 3: PROCESSAMENTO EM LOTE
-- ============================================================================
DECLARE @CNPJAtual VARCHAR(14);
DECLARE @Contador  INT = 0;

DECLARE cursor_cnpjs CURSOR FOR
    SELECT TOP (@LoteTamanho) cnpj
    FROM temp_CGUSC.fp.indicador_controle_vendas_consecutivas
    WHERE situacao IN (0, 3) AND tentativas < 3
    ORDER BY cnpj;

OPEN cursor_cnpjs;
FETCH NEXT FROM cursor_cnpjs INTO @CNPJAtual;

WHILE @@FETCH_STATUS = 0 AND @Contador < @LoteTamanho
BEGIN
    BEGIN TRY
        -- Marca como "Processando"
        UPDATE temp_CGUSC.fp.indicador_controle_vendas_consecutivas
        SET situacao = 1,
            data_inicio_processamento = GETDATE(),
            tentativas = tentativas + 1
        WHERE cnpj = @CNPJAtual;

        -- Agrupa por num_autorizacao (colapsa itens da mesma venda)
        DROP TABLE IF EXISTS #AutorizacoesAgrupadas;
        SELECT
            A.cnpj,
            A.num_autorizacao,
            MIN(A.data_hora) AS data_hora_transacao
        INTO #AutorizacoesAgrupadas
        FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
        INNER JOIN temp_CGUSC.fp.medicamentos_patologia C
            ON C.codigo_barra = A.codigo_barra
        WHERE A.cnpj = @CNPJAtual
          AND A.data_hora >= @DataInicio
          AND A.data_hora <= @DataFim
        GROUP BY A.cnpj, A.num_autorizacao;

        -- Calcula LAG entre autorizacoes
        DROP TABLE IF EXISTS #CalculoVelocidade;
        SELECT
            cnpj,
            num_autorizacao,
            data_hora_transacao,
            LAG(data_hora_transacao) OVER (PARTITION BY cnpj ORDER BY data_hora_transacao) AS data_hora_anterior
        INTO #CalculoVelocidade
        FROM #AutorizacoesAgrupadas;

        -- Conta vendas rapidas (< 60 segundos entre autorizacoes)
        DECLARE @TotalIntervalos INT;
        DECLARE @VendasRapidas   INT;
        DECLARE @Percentual      DECIMAL(18,4);

        SELECT
            @TotalIntervalos = COUNT(*),
            @VendasRapidas   = SUM(CASE WHEN DATEDIFF(SECOND, data_hora_anterior, data_hora_transacao) < 60 THEN 1 ELSE 0 END)
        FROM #CalculoVelocidade
        WHERE data_hora_anterior IS NOT NULL;

        SET @Percentual = CASE
            WHEN @TotalIntervalos > 0
                THEN (CAST(@VendasRapidas AS DECIMAL(18,2)) / CAST(@TotalIntervalos AS DECIMAL(18,2))) * 100.0
            ELSE 0
        END;

        -- Salva resultado individual
        IF EXISTS (SELECT 1 FROM temp_CGUSC.fp.indicador_vendas_consecutivas WHERE cnpj = @CNPJAtual)
            UPDATE temp_CGUSC.fp.indicador_vendas_consecutivas
            SET total_intervalos_analisados    = @TotalIntervalos,
                qtd_vendas_rapidas             = @VendasRapidas,
                percentual_vendas_consecutivas = @Percentual,
                data_calculo                   = GETDATE()
            WHERE cnpj = @CNPJAtual;
        ELSE
            INSERT INTO temp_CGUSC.fp.indicador_vendas_consecutivas
                (cnpj, total_intervalos_analisados, qtd_vendas_rapidas, percentual_vendas_consecutivas)
            VALUES (@CNPJAtual, @TotalIntervalos, @VendasRapidas, @Percentual);

        -- Marca como "Concluido"
        UPDATE temp_CGUSC.fp.indicador_controle_vendas_consecutivas
        SET situacao                = 2,
            data_fim_processamento  = GETDATE(),
            total_autorizacoes      = @TotalIntervalos,
            total_vendas_rapidas    = @VendasRapidas,
            percentual_calculado    = @Percentual,
            mensagem_erro           = NULL
        WHERE cnpj = @CNPJAtual;

        SET @Contador = @Contador + 1;

        IF @Contador % 10 = 0
            PRINT CONCAT('Processados: ', @Contador, ' CNPJs');

    END TRY
    BEGIN CATCH
        UPDATE temp_CGUSC.fp.indicador_controle_vendas_consecutivas
        SET situacao               = 3,
            data_fim_processamento = GETDATE(),
            mensagem_erro          = ERROR_MESSAGE()
        WHERE cnpj = @CNPJAtual;
    END CATCH

    FETCH NEXT FROM cursor_cnpjs INTO @CNPJAtual;
END

CLOSE cursor_cnpjs;
DEALLOCATE cursor_cnpjs;

-- ============================================================================
-- RESUMO DO PROCESSAMENTO EM LOTE
-- ============================================================================
SELECT
    situacao,
    COUNT(*) AS quantidade,
    CASE situacao
        WHEN 0 THEN 'Pendente'
        WHEN 1 THEN 'Processando (Travado?)'
        WHEN 2 THEN 'Concluido'
        WHEN 3 THEN 'Erro'
    END AS status_descricao
FROM temp_CGUSC.fp.indicador_controle_vendas_consecutivas
GROUP BY situacao
ORDER BY situacao;

-- ============================================================================
-- VERIFICACAO: SO CONTINUA SE TODOS OS CNPJs ESTIVEREM CONCLUIDOS
-- Inclui situacao=3 com tentativas esgotadas como "concluido com erro"
-- ============================================================================
DECLARE @Pendentes INT;
SELECT @Pendentes = COUNT(*)
FROM temp_CGUSC.fp.indicador_controle_vendas_consecutivas
WHERE situacao IN (0, 1)
   OR (situacao = 3 AND tentativas < 3);

IF @Pendentes > 0
BEGIN
    PRINT '=======================================================================';
    PRINT CONCAT('ATENCAO: Ainda existem ', @Pendentes, ' CNPJs pendentes de processamento.');
    PRINT 'Execute este script novamente para processar o proximo lote.';
    PRINT 'As tabelas de risco relativo serao geradas apenas quando todos estiverem concluidos.';
    PRINT '=======================================================================';
END
ELSE
BEGIN
    PRINT '=======================================================================';
    PRINT 'TODOS OS CNPJs PROCESSADOS! Gerando tabelas de risco relativo...';
    PRINT '=======================================================================';

    -- ========================================================================
    -- PASSO 4: METRICAS POR MUNICIPIO (MEDIA E MEDIANA)
    -- ========================================================================
    PRINT 'PASSO 4: Calculando metricas por municipio...';

    DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_vendas_consecutivas_mun;

    SELECT DISTINCT
        CAST(F.uf AS VARCHAR(2))          AS uf,
        CAST(F.municipio AS VARCHAR(255)) AS municipio,
        CAST(
            PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.percentual_vendas_consecutivas)
            OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255)))
        AS DECIMAL(18,4)) AS mediana_municipio,
        CAST(
            AVG(I.percentual_vendas_consecutivas)
            OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255)))
        AS DECIMAL(18,4)) AS media_municipio
    INTO temp_CGUSC.fp.indicador_vendas_consecutivas_mun
    FROM temp_CGUSC.fp.indicador_vendas_consecutivas I
    INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj;

    CREATE CLUSTERED INDEX IDX_IndVendasConsecMun ON temp_CGUSC.fp.indicador_vendas_consecutivas_mun(uf, municipio);

    -- ========================================================================
    -- PASSO 5: METRICAS POR ESTADO (MEDIA E MEDIANA)
    -- ========================================================================
    PRINT 'PASSO 5: Calculando metricas por estado...';

    DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_vendas_consecutivas_uf;

    SELECT DISTINCT
        CAST(F.uf AS VARCHAR(2)) AS uf,
        CAST(
            PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.percentual_vendas_consecutivas)
            OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)))
        AS DECIMAL(18,4)) AS mediana_estado,
        CAST(
            AVG(I.percentual_vendas_consecutivas)
            OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)))
        AS DECIMAL(18,4)) AS media_estado
    INTO temp_CGUSC.fp.indicador_vendas_consecutivas_uf
    FROM temp_CGUSC.fp.indicador_vendas_consecutivas I
    INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj;

    CREATE CLUSTERED INDEX IDX_IndVendasConsecUF ON temp_CGUSC.fp.indicador_vendas_consecutivas_uf(uf);

    -- ========================================================================
    -- PASSO 6: METRICAS NACIONAIS (MEDIA E MEDIANA)
    -- ========================================================================
    PRINT 'PASSO 6: Calculando metricas nacionais...';

    DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_vendas_consecutivas_br;

    SELECT DISTINCT
        'BR' AS pais,
        CAST(
            PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY percentual_vendas_consecutivas) OVER ()
        AS DECIMAL(18,4)) AS mediana_pais,
        CAST(
            AVG(percentual_vendas_consecutivas) OVER ()
        AS DECIMAL(18,4)) AS media_pais
    INTO temp_CGUSC.fp.indicador_vendas_consecutivas_br
    FROM temp_CGUSC.fp.indicador_vendas_consecutivas;

    -- ========================================================================
    -- PASSO 7: TABELA CONSOLIDADA FINAL
    -- ========================================================================
    PRINT 'PASSO 7: Gerando tabela consolidada com riscos relativos e rankings...';

    DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_vendas_consecutivas_detalhado;

    SELECT
        I.cnpj,
        F.razaoSocial,
        F.municipio,
        CAST(F.uf AS VARCHAR(2)) AS uf,

        -- Indicadores base
        I.total_intervalos_analisados,
        I.qtd_vendas_rapidas,
        I.percentual_vendas_consecutivas,

        -- Rankings (pior risco = posicao 1)
        RANK() OVER (
            ORDER BY I.percentual_vendas_consecutivas DESC
        ) AS ranking_br,
        RANK() OVER (
            PARTITION BY CAST(F.uf AS VARCHAR(2))
            ORDER BY I.percentual_vendas_consecutivas DESC
        ) AS ranking_uf,
        RANK() OVER (
            PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255))
            ORDER BY I.percentual_vendas_consecutivas DESC
        ) AS ranking_municipio,

        -- Benchmarks municipais
        ISNULL(MUN.mediana_municipio, 0) AS municipio_mediana,
        ISNULL(MUN.media_municipio,   0) AS municipio_media,
        CAST((I.percentual_vendas_consecutivas + 0.01) / (ISNULL(MUN.mediana_municipio, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_mediana,
        CAST((I.percentual_vendas_consecutivas + 0.01) / (ISNULL(MUN.media_municipio,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_media,

        -- Benchmarks estaduais
        ISNULL(UF.mediana_estado, 0) AS estado_mediana,
        ISNULL(UF.media_estado,   0) AS estado_media,
        CAST((I.percentual_vendas_consecutivas + 0.01) / (ISNULL(UF.mediana_estado, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_mediana,
        CAST((I.percentual_vendas_consecutivas + 0.01) / (ISNULL(UF.media_estado,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_media,

        -- Benchmarks nacionais
        BR.mediana_pais AS pais_mediana,
        BR.media_pais   AS pais_media,
        CAST((I.percentual_vendas_consecutivas + 0.01) / (BR.mediana_pais + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_mediana,
        CAST((I.percentual_vendas_consecutivas + 0.01) / (BR.media_pais   + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_media

    INTO temp_CGUSC.fp.indicador_vendas_consecutivas_detalhado
    FROM temp_CGUSC.fp.indicador_vendas_consecutivas I
    INNER JOIN temp_CGUSC.fp.dados_farmacia F
        ON F.cnpj = I.cnpj
    LEFT JOIN temp_CGUSC.fp.indicador_vendas_consecutivas_mun MUN
        ON CAST(F.uf AS VARCHAR(2))          = MUN.uf
       AND CAST(F.municipio AS VARCHAR(255)) = MUN.municipio
    LEFT JOIN temp_CGUSC.fp.indicador_vendas_consecutivas_uf UF
        ON CAST(F.uf AS VARCHAR(2)) = UF.uf
    CROSS JOIN temp_CGUSC.fp.indicador_vendas_consecutivas_br BR;

    CREATE CLUSTERED INDEX IDX_FinalVendasConsec_CNPJ    ON temp_CGUSC.fp.indicador_vendas_consecutivas_detalhado(cnpj);
    CREATE NONCLUSTERED INDEX IDX_FinalVendasConsec_Pct  ON temp_CGUSC.fp.indicador_vendas_consecutivas_detalhado(percentual_vendas_consecutivas DESC);
    CREATE NONCLUSTERED INDEX IDX_FinalVendasConsec_Rank ON temp_CGUSC.fp.indicador_vendas_consecutivas_detalhado(ranking_br);

    PRINT CONCAT('Tabela consolidada criada com ', @@ROWCOUNT, ' registros');
    PRINT '=======================================================================';
    PRINT 'PROCESSO COMPLETO FINALIZADO COM SUCESSO!';
    PRINT '';
    PRINT 'Tabelas criadas:';
    PRINT '  1. indicador_vendas_consecutivas (base)';
    PRINT '  2. indicador_vendas_consecutivas_mun (metricas por municipio)';
    PRINT '  3. indicador_vendas_consecutivas_uf (metricas por estado)';
    PRINT '  4. indicador_vendas_consecutivas_br (metricas nacionais)';
    PRINT '  5. indicador_vendas_consecutivas_detalhado (tabela final com riscos e rankings)';
    PRINT '=======================================================================';

    -- Verificacao rapida
    SELECT TOP 100 *
    FROM temp_CGUSC.fp.indicador_vendas_consecutivas_detalhado
    ORDER BY ranking_br;
END
GO