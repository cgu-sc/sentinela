USE [temp_CGUSC]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[procPreparaDados] 
    @classif INT,
    @rowcount INT OUTPUT,
    @validar BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @inicio DATETIME = GETDATE();
    DECLARE @qtd_esperada BIGINT = 0;
    DECLARE @qtd_inserida BIGINT = 0;
    DECLARE @diferenca BIGINT = 0;
    DECLARE @percentual_dif DECIMAL(5,2) = 0;
    DECLARE @status VARCHAR(20) = 'OK';
    DECLARE @mensagem VARCHAR(500) = NULL;
    DECLARE @qtd_cnpjs INT = 0;

    BEGIN TRY

        -- 4. Limpa e Recria a 'movimentacaoFP'
		IF OBJECT_ID('temp_CGUSC.dbo.movimentacaoFP') IS NOT NULL
			DROP TABLE temp_CGUSC.dbo.movimentacaoFP;

		CREATE TABLE temp_CGUSC.dbo.movimentacaoFP (
			[cnpj] [varchar](14) NULL,
			[data_hora] [datetime] NULL,
			[codigo_barra] [varchar](50) NULL,
			[qnt_autorizada] [int] NULL,
			[valor_pago] [decimal](18, 2) NULL
		);

        -- ====================================================================
        -- ETAPA 3: VALIDAÇÃO PRÉVIA
        -- ====================================================================
        IF @validar = 1
        BEGIN
            PRINT '========================================';
            PRINT 'INICIANDO VALIDAÇÃO';
            PRINT '========================================';
            PRINT 'Calculando dados esperados para classif ' + CAST(@classif AS VARCHAR) + '...';
            
            SELECT @qtd_cnpjs = COUNT(*)
            FROM temp_CGUSC.dbo.classif
            WHERE classif = @classif;
            
            IF @qtd_cnpjs = 0
            BEGIN
                SET @mensagem = 'ERRO: Nenhum CNPJ encontrado para classif ' + CAST(@classif AS VARCHAR);
                RAISERROR(@mensagem, 16, 1);
                RETURN;
            END
            
            PRINT 'CNPJs no classif: ' + CAST(@qtd_cnpjs AS VARCHAR);
            PRINT 'Contando registros na base origem...';
            
            SELECT @qtd_esperada = COUNT(*)
            FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 m
            WHERE m.cnpj IN (
                SELECT cnpj 
                FROM temp_CGUSC.dbo.classif 
                WHERE classif = @classif
            );
            
            PRINT 'Registros esperados: ' + CAST(@qtd_esperada AS VARCHAR);
            PRINT '========================================';
        END


        -- ====================================================================
        -- ETAPA 5: Processamento em lotes (ano a ano)
        -- ====================================================================
        PRINT '';
        PRINT '========================================';
        PRINT 'INICIANDO INSERÇÃO DE DADOS';
        PRINT '========================================';
        
        DECLARE @Ano INT = 2015;
        DECLARE @TotalRows INT = 0;
        DECLARE @RowsAno INT = 0;

        WHILE @Ano <= 2024
        BEGIN
            PRINT 'Processando ano: ' + CAST(@Ano AS VARCHAR(4));

            INSERT INTO temp_CGUSC.dbo.movimentacaoFP (
                cnpj, data_hora, 
                codigo_barra, qnt_autorizada, valor_pago
            )
            SELECT 
                a.cnpj, a.data_hora, 
                a.codigo_barra, a.qnt_autorizada, a.valor_pago
            FROM 
                db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 a
            INNER JOIN 
                temp_CGUSC.dbo.classif b ON b.cnpj = a.cnpj
            WHERE 
                b.classif = @classif 
                AND a.data_hora >= DATEFROMPARTS(@Ano, 1, 1) 
                AND a.data_hora <  DATEFROMPARTS(@Ano + 1, 1, 1);

            SET @RowsAno = @@ROWCOUNT;
            SET @TotalRows = @TotalRows + @RowsAno;
            
            PRINT '  -> Inseridos: ' + CAST(@RowsAno AS VARCHAR) + ' registros';
            
            SET @Ano = @Ano + 1;
        END

        SET @qtd_inserida = @TotalRows;
        SET @rowcount = @TotalRows;

        PRINT '';
        PRINT 'Criando índices...';
        CREATE NONCLUSTERED INDEX IX_movimentacaoFP_codigo_barra 
        ON temp_CGUSC.dbo.movimentacaoFP (codigo_barra);
        CREATE NONCLUSTERED INDEX IX_movimentacaoFP_cnpj 
        ON temp_CGUSC.dbo.movimentacaoFP (cnpj);
        CREATE NONCLUSTERED INDEX IX_movimentacaoFP_data_hora 
        ON temp_CGUSC.dbo.movimentacaoFP (data_hora);

        -- ====================================================================
        -- ETAPA 6: VALIDAÇÃO PÓS-PROCESSAMENTO
        -- ====================================================================
        IF @validar = 1
        BEGIN
            SET @diferenca = @qtd_inserida - @qtd_esperada;
            
            IF @qtd_esperada > 0
                SET @percentual_dif = (CAST(@diferenca AS DECIMAL(18,2)) / @qtd_esperada) * 100;
            
            PRINT '';
            PRINT '========================================';
            PRINT 'RESULTADO DA VALIDAÇÃO';
            PRINT '========================================';
            PRINT 'Registros esperados: ' + CAST(@qtd_esperada AS VARCHAR);
            PRINT 'Registros inseridos: ' + CAST(@qtd_inserida AS VARCHAR);
            PRINT 'Diferença: ' + CAST(@diferenca AS VARCHAR) + ' (' + CAST(@percentual_dif AS VARCHAR) + '%)';
            
            IF @diferenca <> 0
            BEGIN
                SET @status = 'ERRO';
                SET @mensagem = 'ERRO: Divergência encontrada. Esperados=' + CAST(@qtd_esperada AS VARCHAR) + ', Inseridos=' + CAST(@qtd_inserida AS VARCHAR);
                PRINT '❌ ATENÇÃO: ' + @mensagem;
                PRINT '========================================';
            END
            ELSE
            BEGIN
                SET @status = 'OK';
                SET @mensagem = 'Processamento validado com sucesso. Contagem exata.';
                PRINT '✅ ' + @mensagem;
                PRINT '========================================';
            END
        END
        ELSE
        BEGIN
            SET @status = 'SEM_VALIDACAO';
            SET @mensagem = 'Validação desabilitada pelo parâmetro @validar = 0';
        END

        PRINT 'Procedure executada com sucesso!';
        PRINT 'Tempo total: ' + CAST(CAST(DATEDIFF(SECOND, @inicio, GETDATE()) / 60.0 AS DECIMAL(10, 2)) AS VARCHAR) + ' minutos';

    END TRY
    BEGIN CATCH
        SET @status = 'ERRO';
        SET @mensagem = ERROR_MESSAGE();
        
        PRINT '';
        PRINT '========================================';
        PRINT '❌ ERRO DURANTE EXECUÇÃO';
        PRINT '========================================';
        PRINT @mensagem;
        PRINT '========================================';
        
        SET @rowcount = -1;
    END CATCH
    
    -- ====================================================================
    -- ETAPA 7: AUDITORIA
    -- ====================================================================
    
    DECLARE @tempo_execucao INT = DATEDIFF(SECOND, ISNULL(@inicio, GETDATE()), GETDATE());
    DECLARE @regs_por_segundo DECIMAL(18, 2) = 
        CAST(ISNULL(@qtd_inserida, 0) AS DECIMAL(18, 2)) / NULLIF(@tempo_execucao, 0);
    
    BEGIN TRY
        INSERT INTO temp_CGUSC.dbo.auditoria_execucoes (
            data_execucao, classif, qtd_cnpjs,
            qtd_esperada, qtd_inserida, diferenca,
            percentual_diferenca, status, mensagem, 
            tempo_execucao_segundos, registros_por_segundo
        )
        VALUES (
            GETDATE(), @classif, ISNULL(@qtd_cnpjs, 0),
            ISNULL(@qtd_esperada, 0), ISNULL(@qtd_inserida, 0), ISNULL(@diferenca, 0),
            ISNULL(@percentual_dif, 0), @status, @mensagem, 
            @tempo_execucao, @regs_por_segundo
        );
        
        PRINT '';
        PRINT '📊 Execução registrada na tabela de auditoria';
    END TRY
    BEGIN CATCH
        PRINT '⚠️  Aviso: Erro ao registrar auditoria: ' + ERROR_MESSAGE();
    END CATCH
    
    IF @status = 'ERRO'
    BEGIN
        RAISERROR (@mensagem, 16, 1);
        RETURN;
    END
END

