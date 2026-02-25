USE [temp_CGUSC]
GO

-- 1. Garante que a coluna nova existe se a tabela já existir
IF OBJECT_ID('temp_CGUSC.dbo.indicadorGeografico', 'U') IS NOT NULL
BEGIN
    IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('temp_CGUSC.dbo.indicadorGeografico') AND name = 'data_calculo')
    BEGIN
        ALTER TABLE temp_CGUSC.dbo.indicadorGeografico ADD data_calculo DATETIME DEFAULT GETDATE();
    END
END
GO

-- ============================================================================
-- SCRIPT COMPLETO UNIFICADO: RISCO GEOGRÁFICO COM RISCO RELATIVO
-- ============================================================================

-- ============================================================================
-- PASSO 0: CRIAR TABELA DE RESULTADOS BASE (SE NÃO EXISTIR)
-- ============================================================================
IF OBJECT_ID('temp_CGUSC.dbo.indicadorGeografico', 'U') IS NULL
BEGIN
    CREATE TABLE temp_CGUSC.dbo.indicadorGeografico (
        id INT IDENTITY(1,1) PRIMARY KEY,
        cnpj VARCHAR(14) NOT NULL UNIQUE,
        total_vendas_monitoradas INT,
        qtd_vendas_outra_uf INT,
        percentual_geografico DECIMAL(18,4),
        data_calculo DATETIME DEFAULT GETDATE()
    );
    
    CREATE INDEX IDX_IndGeo_CNPJ ON temp_CGUSC.dbo.indicadorGeografico(cnpj);
END

-- ============================================================================
-- PASSO 1: TABELA DE CONTROLE DE PROCESSAMENTO
-- ============================================================================
IF OBJECT_ID('temp_CGUSC.dbo.controle_processamento_geografico', 'U') IS NULL
BEGIN
    CREATE TABLE temp_CGUSC.dbo.controle_processamento_geografico (
        id INT IDENTITY(1,1) PRIMARY KEY,
        cnpj VARCHAR(14) NOT NULL UNIQUE,
        data_inicio_processamento DATETIME,
        data_fim_processamento DATETIME,
        situacao INT, -- 0=Pendente, 1=Processando, 2=Concluído, 3=Erro
        total_vendas INT,
        total_outra_uf INT,
        percentual_calculado DECIMAL(18,4),
        mensagem_erro VARCHAR(MAX),
        tentativas INT DEFAULT 0
    );

    CREATE INDEX IDX_ControleGeo_Situacao ON temp_CGUSC.dbo.controle_processamento_geografico(situacao, cnpj);
END

-- Carga inicial de CNPJs pendentes
INSERT INTO temp_CGUSC.dbo.controle_processamento_geografico (cnpj, situacao)
SELECT DISTINCT cnpj, 0 AS situacao
FROM temp_CGUSC.dbo.dadosFarmaciasFP
WHERE cnpj NOT IN (SELECT cnpj FROM temp_CGUSC.dbo.controle_processamento_geografico)
ORDER BY cnpj;

-- ============================================================================
-- PASSO 2: CONFIGURAÇÃO DO PROCESSAMENTO
-- ============================================================================
DECLARE @LoteTamanho INT = 50; -- Voltamos para 50 CNPJs por execução no modelo de cursor
DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim DATE = '2024-12-10';

-- ============================================================================
-- PASSO 3: RECUPERAÇÃO DE PROCESSAMENTOS TRAVADOS
-- ============================================================================
UPDATE temp_CGUSC.dbo.controle_processamento_geografico
SET situacao = 0, -- Volta para "Pendente"
    mensagem_erro = 'Reprocessamento (Reversão para modelo estável)'
WHERE situacao = 1 -- Estava "Processando"
  AND DATEDIFF(MINUTE, data_inicio_processamento, GETDATE()) > 30;

-- ============================================================================
-- PASSO 4: PROCESSAMENTO EM LOTE (MODELO ESTÁVEL COM CURSOR)
-- ============================================================================
DECLARE @CNPJAtual VARCHAR(14);
DECLARE @Contador INT = 0;

DECLARE cursor_cnpjs CURSOR FOR
    SELECT TOP (@LoteTamanho) cnpj
    FROM temp_CGUSC.dbo.controle_processamento_geografico
    WHERE situacao IN (0, 3) 
      AND tentativas < 3
    ORDER BY cnpj;

OPEN cursor_cnpjs;
FETCH NEXT FROM cursor_cnpjs INTO @CNPJAtual;

WHILE @@FETCH_STATUS = 0 AND @Contador < @LoteTamanho
BEGIN
    SET @Contador = @Contador + 1;
    
    BEGIN TRY
        -- MARCA COMO "PROCESSANDO"
        UPDATE temp_CGUSC.dbo.controle_processamento_geografico
        SET situacao = 1,
            data_inicio_processamento = GETDATE(),
            tentativas = tentativas + 1
        WHERE cnpj = @CNPJAtual;

        -- CALCULO DO INDICADOR
        DROP TABLE IF EXISTS #VendasTemp;
        SELECT 
            A.num_autorizacao,
            MAX(B.unidadeFederacao) AS uf_paciente,
            MAX(F.uf) AS uf_farmacia
        INTO #VendasTemp
        FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A WITH(NOLOCK)
        INNER JOIN temp_CGUSC.dbo.dadosFarmaciasFP F WITH(NOLOCK) ON F.cnpj = A.cnpj
        INNER JOIN db_CPF.dbo.CPF B WITH(NOLOCK) ON B.CPF = A.cpf
        WHERE A.cnpj = @CNPJAtual
          AND A.data_hora >= @DataInicio AND A.data_hora <= @DataFim
        GROUP BY A.num_autorizacao;

        DECLARE @TotalVendas INT, @QtdOutraUF INT, @Pct DECIMAL(18,4);

        SELECT 
            @TotalVendas = COUNT(*),
            @QtdOutraUF = SUM(CASE WHEN uf_paciente IS NOT NULL AND uf_farmacia IS NOT NULL 
                                   AND CAST(uf_paciente AS VARCHAR(2)) <> CAST(uf_farmacia AS VARCHAR(2)) THEN 1 ELSE 0 END)
        FROM #VendasTemp;

        SET @Pct = CASE WHEN @TotalVendas > 0 THEN (CAST(@QtdOutraUF AS DECIMAL(18,2)) / @TotalVendas) * 100.0 ELSE 0 END;

        -- SALVA RESULTADO INDIVIDUAL
        IF EXISTS (SELECT 1 FROM temp_CGUSC.dbo.indicadorGeografico WHERE cnpj = @CNPJAtual)
            UPDATE temp_CGUSC.dbo.indicadorGeografico 
            SET total_vendas_monitoradas = @TotalVendas, 
                qtd_vendas_outra_uf = @QtdOutraUF, 
                percentual_geografico = @Pct,
                data_calculo = GETDATE()
            WHERE cnpj = @CNPJAtual;
        ELSE
            INSERT INTO temp_CGUSC.dbo.indicadorGeografico (cnpj, total_vendas_monitoradas, qtd_vendas_outra_uf, percentual_geografico)
            VALUES (@CNPJAtual, @TotalVendas, @QtdOutraUF, @Pct);

        -- MARCA COMO "CONCLUÍDO"
        UPDATE temp_CGUSC.dbo.controle_processamento_geografico
        SET situacao = 2,
            data_fim_processamento = GETDATE(),
            total_vendas = @TotalVendas,
            total_outra_uf = @QtdOutraUF,
            percentual_calculado = @Pct,
            mensagem_erro = NULL
        WHERE cnpj = @CNPJAtual;

    END TRY
    BEGIN CATCH
        UPDATE temp_CGUSC.dbo.controle_processamento_geografico
        SET situacao = 3,
            data_fim_processamento = GETDATE(),
            mensagem_erro = ERROR_MESSAGE()
        WHERE cnpj = @CNPJAtual;
        
        PRINT CONCAT('ERRO no CNPJ ', @CNPJAtual, ': ', ERROR_MESSAGE());
    END CATCH

    FETCH NEXT FROM cursor_cnpjs INTO @CNPJAtual;
END

CLOSE cursor_cnpjs;
DEALLOCATE cursor_cnpjs;

-- ============================================================================
-- VERIFICAÇÃO E CONSOLIDAÇÃO FINAL
-- ============================================================================
DECLARE @Pendentes INT;
SELECT @Pendentes = COUNT(*) FROM temp_CGUSC.dbo.controle_processamento_geografico WHERE situacao IN (0, 1);

IF @Pendentes > 0
BEGIN
    PRINT '';
    PRINT '=======================================================================';
    PRINT CONCAT('ATENÇÃO: Ainda existem ', @Pendentes, ' CNPJs pendentes de processamento.');
    PRINT 'Execute este script novamente para processar o próximo lote.';
    PRINT '=======================================================================';
END
ELSE
BEGIN
    PRINT '';
    PRINT '=======================================================================';
    PRINT 'TODOS OS CNPJs PROCESSADOS! Gerando tabelas de risco relativo...';
    PRINT '=======================================================================';

    -- Médias por UF
    DROP TABLE IF EXISTS temp_CGUSC.dbo.indicadorGeografico_UF;
    SELECT 
        CAST(F.uf AS VARCHAR(2)) AS uf,
        SUM(I.total_vendas_monitoradas) AS total_vendas_uf,
        SUM(I.qtd_vendas_outra_uf) AS total_outra_uf,
        CAST((CAST(SUM(I.qtd_vendas_outra_uf) AS DECIMAL(18,2)) / NULLIF(SUM(I.total_vendas_monitoradas), 0)) * 100.0 AS DECIMAL(18,4)) AS percentual_geografico_uf
    INTO temp_CGUSC.dbo.indicadorGeografico_UF
    FROM temp_CGUSC.dbo.indicadorGeografico I
    INNER JOIN temp_CGUSC.dbo.dadosFarmaciasFP F ON F.cnpj = I.cnpj
    GROUP BY CAST(F.uf AS VARCHAR(2));
    
    CREATE CLUSTERED INDEX IDX_IndGeoUF_UF ON temp_CGUSC.dbo.indicadorGeografico_UF(uf);
    
    -- Médias BR
    DROP TABLE IF EXISTS temp_CGUSC.dbo.indicadorGeografico_BR;
    SELECT 
        'BR' AS pais,
        SUM(total_vendas_monitoradas) AS total_vendas_br,
        SUM(qtd_vendas_outra_uf) AS total_outra_br,
        CAST((CAST(SUM(qtd_vendas_outra_uf) AS DECIMAL(18,2)) / NULLIF(SUM(total_vendas_monitoradas), 0)) * 100.0 AS DECIMAL(18,4)) AS percentual_geografico_br
    INTO temp_CGUSC.dbo.indicadorGeografico_BR
    FROM temp_CGUSC.dbo.indicadorGeografico;

    -- Tabela Final
    DROP TABLE IF EXISTS temp_CGUSC.dbo.indicadorGeografico_Completo;
    SELECT 
        I.cnpj, F.razaoSocial, F.municipio, CAST(F.uf AS VARCHAR(2)) AS uf,
        I.total_vendas_monitoradas, I.qtd_vendas_outra_uf, I.percentual_geografico,
        UF.percentual_geografico_uf AS media_estado,
        BR.percentual_geografico_br AS media_pais,
        CAST(I.percentual_geografico / NULLIF(UF.percentual_geografico_uf, 0) AS DECIMAL(18,4)) AS risco_relativo_uf,
        CAST(I.percentual_geografico / NULLIF(BR.percentual_geografico_br, 0) AS DECIMAL(18,4)) AS risco_relativo_br
    INTO temp_CGUSC.dbo.indicadorGeografico_Completo
    FROM temp_CGUSC.dbo.indicadorGeografico I
    INNER JOIN temp_CGUSC.dbo.dadosFarmaciasFP F ON F.cnpj = I.cnpj
    LEFT JOIN temp_CGUSC.dbo.indicadorGeografico_UF UF ON CAST(F.uf AS VARCHAR(2)) = UF.uf
    CROSS JOIN temp_CGUSC.dbo.indicadorGeografico_BR BR;

    CREATE CLUSTERED INDEX IDX_FinalGeo_CNPJ ON temp_CGUSC.dbo.indicadorGeografico_Completo(cnpj);
    
    PRINT '=======================================================================';
    PRINT 'PROCESSO COMPLETO FINALIZADO COM SUCESSO!';
    PRINT '=======================================================================';
END
GO
