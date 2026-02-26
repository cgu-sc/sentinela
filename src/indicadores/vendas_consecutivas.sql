USE [temp_CGUSC]
GO

-- ============================================================================
-- SCRIPT COMPLETO UNIFICADO: VENDAS CONSECUTIVAS COM RISCO RELATIVO
-- Executa tudo em um único script: processamento + riscos relativos
-- ============================================================================

-- ============================================================================
-- PASSO 0: CRIAR TABELA DE RESULTADOS BASE (SE NÃO EXISTIR)
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.objects 
               WHERE object_id = OBJECT_ID(N'temp_CGUSC.fp.indicadorVendasConsecutivas') 
               AND type in (N'U'))
BEGIN
    CREATE TABLE temp_CGUSC.fp.indicadorVendasConsecutivas (
        id INT IDENTITY(1,1) PRIMARY KEY,
        cnpj VARCHAR(14) NOT NULL UNIQUE,
        total_intervalos_analisados INT,
        qtd_vendas_rapidas INT,
        percentual_vendas_consecutivas DECIMAL(18,4),
        data_calculo DATETIME DEFAULT GETDATE()
    );
    
    CREATE INDEX IDX_Indicador_CNPJ ON temp_CGUSC.fp.indicadorVendasConsecutivas(cnpj);
    CREATE INDEX IDX_Indicador_Percentual ON temp_CGUSC.fp.indicadorVendasConsecutivas(percentual_vendas_consecutivas);
END

-- ============================================================================
-- PASSO 1: TABELA DE CONTROLE DE PROCESSAMENTO
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.objects 
               WHERE object_id = OBJECT_ID(N'temp_CGUSC.fp.controle_processamento_vendas_consecutivas') 
               AND type in (N'U'))
BEGIN
    CREATE TABLE temp_CGUSC.fp.controle_processamento_vendas_consecutivas (
        id INT IDENTITY(1,1) PRIMARY KEY,
        cnpj VARCHAR(14) NOT NULL UNIQUE,
        data_inicio_processamento DATETIME,
        data_fim_processamento DATETIME,
        situacao INT, -- 0=Pendente, 1=Processando, 2=Concluído, 3=Erro
        total_autorizacoes INT,
        total_vendas_rapidas INT,
        percentual_calculado DECIMAL(18,4),
        mensagem_erro VARCHAR(MAX),
        tentativas INT DEFAULT 0
    );

    CREATE INDEX IDX_Controle_Situacao ON temp_CGUSC.fp.controle_processamento_vendas_consecutivas(situacao, cnpj);
END

-- Lista todos os CNPJs que precisam ser processados
INSERT INTO temp_CGUSC.fp.controle_processamento_vendas_consecutivas (cnpj, situacao)
SELECT DISTINCT cnpj, 0 AS situacao
FROM temp_CGUSC.fp.lista_cnpjs
WHERE cnpj NOT IN (SELECT cnpj FROM temp_CGUSC.fp.controle_processamento_vendas_consecutivas)
ORDER BY cnpj;

-- ============================================================================
-- PASSO 2: CONFIGURAÇÃO DO PROCESSAMENTO
-- ============================================================================
DECLARE @LoteTamanho INT = 50; -- Processar 50 CNPJs por execução
DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim DATE = '2024-12-10';

-- ============================================================================
-- PASSO 3: RECUPERAÇÃO DE PROCESSAMENTOS TRAVADOS
-- ============================================================================
UPDATE temp_CGUSC.fp.controle_processamento_vendas_consecutivas
SET situacao = 0, -- Volta para "Pendente"
    mensagem_erro = 'Reprocessamento: execução anterior interrompida'
WHERE situacao = 1 -- Estava "Processando"
  AND DATEDIFF(MINUTE, data_inicio_processamento, GETDATE()) > 30;

-- ============================================================================
-- PASSO 4: PROCESSAMENTO EM LOTE
-- ============================================================================
DECLARE @CNPJAtual VARCHAR(14);
DECLARE @Contador INT = 0;

DECLARE cursor_cnpjs CURSOR FOR
    SELECT TOP (@LoteTamanho) cnpj
    FROM temp_CGUSC.fp.controle_processamento_vendas_consecutivas
    WHERE situacao = 0 -- Apenas pendentes
    ORDER BY cnpj;

OPEN cursor_cnpjs;
FETCH NEXT FROM cursor_cnpjs INTO @CNPJAtual;

WHILE @@FETCH_STATUS = 0 AND @Contador < @LoteTamanho
BEGIN
    BEGIN TRY
        -- ====================================================================
        -- MARCA COMO "PROCESSANDO"
        -- ====================================================================
        UPDATE temp_CGUSC.fp.controle_processamento_vendas_consecutivas
        SET situacao = 1,
            data_inicio_processamento = GETDATE(),
            tentativas = tentativas + 1
        WHERE cnpj = @CNPJAtual;

        -- ====================================================================
        -- CÁLCULO DO INDICADOR
        -- ====================================================================
        
        -- Agrupa por num_autorizacao (colapsa itens da mesma venda)
        DROP TABLE IF EXISTS #AutorizacoesAgrupadas;
        SELECT 
            cnpj,
            num_autorizacao,
            MIN(data_hora) AS data_hora_transacao
        INTO #AutorizacoesAgrupadas
        FROM db_farmaciapopular.fp.relatorio_movimentacao_2015_2024
        WHERE cnpj = @CNPJAtual
          AND data_hora >= @DataInicio 
          AND data_hora <= @DataFim
        GROUP BY cnpj, num_autorizacao;

        -- Calcula LAG entre autorizações
        DROP TABLE IF EXISTS #CalculoVelocidade;
        SELECT 
            cnpj,
            num_autorizacao,
            data_hora_transacao,
            LAG(data_hora_transacao) OVER (PARTITION BY cnpj ORDER BY data_hora_transacao) AS data_hora_anterior
        INTO #CalculoVelocidade
        FROM #AutorizacoesAgrupadas;

        -- Conta vendas rápidas
        DECLARE @TotalIntervalos INT;
        DECLARE @VendasRapidas INT;
        DECLARE @Percentual DECIMAL(18,4);

        SELECT 
            @TotalIntervalos = COUNT(*),
            @VendasRapidas = SUM(CASE WHEN DATEDIFF(SECOND, data_hora_anterior, data_hora_transacao) < 60 THEN 1 ELSE 0 END)
        FROM #CalculoVelocidade
        WHERE data_hora_anterior IS NOT NULL;

        SET @Percentual = CASE 
            WHEN @TotalIntervalos > 0 THEN 
                (CAST(@VendasRapidas AS DECIMAL(18,2)) / CAST(@TotalIntervalos AS DECIMAL(18,2))) * 100.0
            ELSE 0 
        END;

        -- ====================================================================
        -- SALVA RESULTADO INDIVIDUAL
        -- ====================================================================
        
        IF EXISTS (SELECT 1 FROM temp_CGUSC.fp.indicadorVendasConsecutivas WHERE cnpj = @CNPJAtual)
        BEGIN
            UPDATE temp_CGUSC.fp.indicadorVendasConsecutivas
            SET total_intervalos_analisados = @TotalIntervalos,
                qtd_vendas_rapidas = @VendasRapidas,
                percentual_vendas_consecutivas = @Percentual,
                data_calculo = GETDATE()
            WHERE cnpj = @CNPJAtual;
        END
        ELSE
        BEGIN
            INSERT INTO temp_CGUSC.fp.indicadorVendasConsecutivas 
                (cnpj, total_intervalos_analisados, qtd_vendas_rapidas, percentual_vendas_consecutivas)
            VALUES (@CNPJAtual, @TotalIntervalos, @VendasRapidas, @Percentual);
        END

        -- ====================================================================
        -- MARCA COMO CONCLUÍDO
        -- ====================================================================
        UPDATE temp_CGUSC.fp.controle_processamento_vendas_consecutivas
        SET situacao = 2,
            data_fim_processamento = GETDATE(),
            total_autorizacoes = @TotalIntervalos,
            total_vendas_rapidas = @VendasRapidas,
            percentual_calculado = @Percentual,
            mensagem_erro = NULL
        WHERE cnpj = @CNPJAtual;

        SET @Contador = @Contador + 1;

        -- Log de progresso
        IF @Contador % 10 = 0
            PRINT CONCAT('Processados: ', @Contador, ' | Último CNPJ: ', @CNPJAtual);

    END TRY
    BEGIN CATCH
        -- ====================================================================
        -- TRATAMENTO DE ERRO
        -- ====================================================================
        DECLARE @ErrorMsg NVARCHAR(MAX) = ERROR_MESSAGE();
        
        UPDATE temp_CGUSC.fp.controle_processamento_vendas_consecutivas
        SET situacao = 3, -- Erro
            data_fim_processamento = GETDATE(),
            mensagem_erro = @ErrorMsg
        WHERE cnpj = @CNPJAtual;

        PRINT CONCAT('ERRO no CNPJ ', @CNPJAtual, ': ', @ErrorMsg);
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
        WHEN 2 THEN 'Concluído'
        WHEN 3 THEN 'Erro'
    END AS status_descricao
FROM temp_CGUSC.fp.controle_processamento_vendas_consecutivas
GROUP BY situacao
ORDER BY situacao;

-- ============================================================================
-- VERIFICAÇÃO: SÓ CONTINUA SE TODOS OS CNPJs ESTIVEREM CONCLUÍDOS
-- ============================================================================
DECLARE @Pendentes INT;
SELECT @Pendentes = COUNT(*) 
FROM temp_CGUSC.fp.controle_processamento_vendas_consecutivas 
WHERE situacao IN (0, 1); -- Pendente ou Processando

IF @Pendentes > 0
BEGIN
    PRINT '';
    PRINT '=======================================================================';
    PRINT CONCAT('ATENÇÃO: Ainda existem ', @Pendentes, ' CNPJs pendentes de processamento.');
    PRINT 'Execute este script novamente para processar o próximo lote.';
    PRINT 'As tabelas de risco relativo serão geradas apenas quando todos estiverem concluídos.';
    PRINT '=======================================================================';
END
ELSE
BEGIN
    PRINT '';
    PRINT '=======================================================================';
    PRINT 'TODOS OS CNPJs PROCESSADOS! Gerando tabelas de risco relativo...';
    PRINT '=======================================================================';
    
    -- ========================================================================
    -- PASSO 5: CÁLCULO DAS MÉDIAS POR ESTADO (UF)
    -- ========================================================================
    PRINT 'PASSO 5: Calculando médias por UF...';
    
    DROP TABLE IF EXISTS temp_CGUSC.fp.indicadorVendasConsecutivas_UF;
    
    SELECT 
        CAST(F.uf AS VARCHAR(2)) AS uf,
        COUNT(*) AS total_farmacias_uf,
        CAST(AVG(I.percentual_vendas_consecutivas) AS DECIMAL(18,4)) AS percentual_vendas_consecutivas_uf
    INTO temp_CGUSC.fp.indicadorVendasConsecutivas_UF
    FROM temp_CGUSC.fp.indicadorVendasConsecutivas I
    INNER JOIN temp_CGUSC.fp.dadosFarmaciasFP F ON F.cnpj = I.cnpj
    GROUP BY CAST(F.uf AS VARCHAR(2));
    
    CREATE CLUSTERED INDEX IDX_IndVendasConsec_UF ON temp_CGUSC.fp.indicadorVendasConsecutivas_UF(uf);
    
    PRINT CONCAT('? Médias calculadas para ', @@ROWCOUNT, ' estados');
    
    -- ========================================================================
    -- PASSO 6: CÁLCULO DA MÉDIA NACIONAL (BR)
    -- ========================================================================
    PRINT 'PASSO 6: Calculando média nacional...';
    
    DROP TABLE IF EXISTS temp_CGUSC.fp.indicadorVendasConsecutivas_BR;
    
    SELECT 
        'BR' AS pais,
        COUNT(*) AS total_farmacias_br,
        CAST(AVG(percentual_vendas_consecutivas) AS DECIMAL(18,4)) AS percentual_vendas_consecutivas_br
    INTO temp_CGUSC.fp.indicadorVendasConsecutivas_BR
    FROM temp_CGUSC.fp.indicadorVendasConsecutivas;
    
    PRINT '? Média nacional calculada';
    
    -- ========================================================================
    -- PASSO 7: TABELA CONSOLIDADA FINAL COM RISCOS RELATIVOS
    -- ========================================================================
    PRINT 'PASSO 7: Gerando tabela consolidada com riscos relativos...';
    
    DROP TABLE IF EXISTS temp_CGUSC.fp.indicadorVendasConsecutivas_Completo;
    
    SELECT 
        I.cnpj,
        F.razaoSocial,
        F.municipio,
        CAST(F.uf AS VARCHAR(2)) AS uf,
        
        -- Indicadores base
        I.total_intervalos_analisados,
        I.qtd_vendas_rapidas,
        I.percentual_vendas_consecutivas,
        
        -- Médias de referência
        ISNULL(UF.percentual_vendas_consecutivas_uf, 0) AS media_estado,
        BR.percentual_vendas_consecutivas_br AS media_pais,
        
        -- RISCO RELATIVO EM RELAÇÃO AO ESTADO
        CAST(CASE 
            WHEN UF.percentual_vendas_consecutivas_uf > 0 THEN 
                I.percentual_vendas_consecutivas / UF.percentual_vendas_consecutivas_uf
            ELSE 0 
        END AS DECIMAL(18,4)) AS risco_relativo_uf,
    
        -- RISCO RELATIVO EM RELAÇÃO AO PAÍS
        CAST(CASE 
            WHEN BR.percentual_vendas_consecutivas_br > 0 THEN 
                I.percentual_vendas_consecutivas / BR.percentual_vendas_consecutivas_br
            ELSE 0 
        END AS DECIMAL(18,4)) AS risco_relativo_br
    
    INTO temp_CGUSC.fp.indicadorVendasConsecutivas_Completo
    FROM temp_CGUSC.fp.indicadorVendasConsecutivas I
    INNER JOIN temp_CGUSC.fp.dadosFarmaciasFP F ON F.cnpj = I.cnpj
    LEFT JOIN temp_CGUSC.fp.indicadorVendasConsecutivas_UF UF ON CAST(F.uf AS VARCHAR(2)) = UF.uf
    CROSS JOIN temp_CGUSC.fp.indicadorVendasConsecutivas_BR BR;
    
    CREATE CLUSTERED INDEX IDX_FinalVendasConsec_CNPJ ON temp_CGUSC.fp.indicadorVendasConsecutivas_Completo(cnpj);
    CREATE INDEX IDX_FinalVendasConsec_RiscoUF ON temp_CGUSC.fp.indicadorVendasConsecutivas_Completo(risco_relativo_uf);
    CREATE INDEX IDX_FinalVendasConsec_RiscoBR ON temp_CGUSC.fp.indicadorVendasConsecutivas_Completo(risco_relativo_br);
    
    PRINT CONCAT('? Tabela consolidada criada com ', @@ROWCOUNT, ' registros');
    
    -- ========================================================================
    -- RELATÓRIOS FINAIS
    -- ========================================================================
    PRINT '';
    PRINT '=======================================================================';
    PRINT 'ESTATÍSTICAS FINAIS';
    PRINT '=======================================================================';
    
    SELECT 
        COUNT(*) AS total_farmacias,
        CAST(AVG(percentual_vendas_consecutivas) AS DECIMAL(10,2)) AS media_percentual,
        CAST(AVG(risco_relativo_uf) AS DECIMAL(10,2)) AS media_risco_uf,
        CAST(AVG(risco_relativo_br) AS DECIMAL(10,2)) AS media_risco_br,
        CAST(MAX(risco_relativo_br) AS DECIMAL(10,2)) AS maior_risco_br,
        CAST(MIN(risco_relativo_br) AS DECIMAL(10,2)) AS menor_risco_br
    FROM temp_CGUSC.fp.indicadorVendasConsecutivas_Completo;
    
    PRINT '';
    PRINT 'TOP 20 FARMÁCIAS COM MAIOR RISCO (BR):';
    
    SELECT TOP 20
        cnpj,
        razaoSocial,
        municipio,
        uf,
        CAST(percentual_vendas_consecutivas AS DECIMAL(10,2)) AS pct_vendas_consec,
        CAST(media_estado AS DECIMAL(10,2)) AS media_uf,
        CAST(media_pais AS DECIMAL(10,2)) AS media_br,
        CAST(risco_relativo_uf AS DECIMAL(10,2)) AS risco_uf,
        CAST(risco_relativo_br AS DECIMAL(10,2)) AS risco_br
    FROM temp_CGUSC.fp.indicadorVendasConsecutivas_Completo
    ORDER BY risco_relativo_br DESC;
    
    PRINT '';
    PRINT '=======================================================================';
    PRINT 'PROCESSO COMPLETO FINALIZADO COM SUCESSO!';
    PRINT '';
    PRINT 'Tabelas criadas:';
    PRINT '  1. indicadorVendasConsecutivas (base)';
    PRINT '  2. indicadorVendasConsecutivas_UF (médias por estado)';
    PRINT '  3. indicadorVendasConsecutivas_BR (média nacional)';
    PRINT '  4. indicadorVendasConsecutivas_Completo (tabela final com riscos)';
    PRINT '';
    PRINT 'Use a tabela indicadorVendasConsecutivas_Completo para suas análises!';
    PRINT '=======================================================================';
END

GO
