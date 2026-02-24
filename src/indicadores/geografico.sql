USE [temp_CGUSC]
GO

-- ============================================================================
-- 1. PREPARAÇÃO DO AMBIENTE (SETUP)
-- ============================================================================

-- Tabela de Controle de Processamento
IF OBJECT_ID('temp_CGUSC.dbo.controle_processamento_geografico', 'U') IS NULL
BEGIN
    CREATE TABLE temp_CGUSC.dbo.controle_processamento_geografico (
        id INT IDENTITY(1,1) PRIMARY KEY,
        cnpj VARCHAR(14) NOT NULL UNIQUE,
        data_inicio_processamento DATETIME,
        data_fim_processamento DATETIME,
        situacao INT DEFAULT 0, -- 0=Pendente, 1=Processando, 2=Concluído, 3=Erro
        total_vendas INT,
        total_outra_uf INT,
        percentual_calculado DECIMAL(18,4),
        mensagem_erro VARCHAR(MAX),
        tentativas INT DEFAULT 0
    );
    CREATE INDEX IDX_ControleGeo_Situacao ON temp_CGUSC.dbo.controle_processamento_geografico(situacao, cnpj);
END

-- Tabela de Resultados (Fase 1)
IF OBJECT_ID('temp_CGUSC.dbo.indicadorGeografico', 'U') IS NULL
BEGIN
    CREATE TABLE temp_CGUSC.dbo.indicadorGeografico (
        cnpj VARCHAR(20) PRIMARY KEY,
        total_vendas_monitoradas INT,
        qtd_vendas_outra_uf INT,
        percentual_geografico DECIMAL(18,4)
    );
END

-- Carga inicial de CNPJs pendentes
INSERT INTO temp_CGUSC.dbo.controle_processamento_geografico (cnpj, situacao)
SELECT DISTINCT cnpj, 0
FROM temp_CGUSC.dbo.dadosFarmaciasFP
WHERE cnpj NOT IN (SELECT cnpj FROM temp_CGUSC.dbo.controle_processamento_geografico);

-- ============================================================================
-- 2. MOTOR DE PROCESSAMENTO EM BLOCOS
-- ============================================================================

DECLARE @LoteTamanho INT = 10; -- Quantas farmácias processar por ciclo de cursor
DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim DATE = '2024-12-10';
DECLARE @LoteAtual INT = 1;

PRINT '>>> Iniciando Processamento Geográfico por Lotes...';

WHILE EXISTS (SELECT 1 FROM temp_CGUSC.dbo.controle_processamento_geografico WHERE situacao IN (0, 3) AND tentativas < 3)
BEGIN
    DECLARE @CNPJAtual VARCHAR(14);
    
    DECLARE cursor_geografico CURSOR FOR
        SELECT TOP (@LoteTamanho) cnpj
        FROM temp_CGUSC.dbo.controle_processamento_geografico
        WHERE situacao IN (0, 3) AND tentativas < 3
        ORDER BY cnpj;

    OPEN cursor_geografico;
    FETCH NEXT FROM cursor_geografico INTO @CNPJAtual;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            UPDATE temp_CGUSC.dbo.controle_processamento_geografico
            SET situacao = 1, data_inicio_processamento = GETDATE(), tentativas = tentativas + 1
            WHERE cnpj = @CNPJAtual;

            -- Cálculo da Dispersão Geográfica por CNPJ
            -- Agrupamos por autorização para garantir que a UF seja consistente por venda
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

            -- Salva na tabela final de indicadores
            IF EXISTS (SELECT 1 FROM temp_CGUSC.dbo.indicadorGeografico WHERE cnpj = @CNPJAtual)
                UPDATE temp_CGUSC.dbo.indicadorGeografico 
                SET total_vendas_monitoradas = @TotalVendas, qtd_vendas_outra_uf = @QtdOutraUF, percentual_geografico = @Pct
                WHERE cnpj = @CNPJAtual;
            ELSE
                INSERT INTO temp_CGUSC.dbo.indicadorGeografico (cnpj, total_vendas_monitoradas, qtd_vendas_outra_uf, percentual_geografico)
                VALUES (@CNPJAtual, @TotalVendas, @QtdOutraUF, @Pct);

            -- Atualiza controle como Concluído
            UPDATE temp_CGUSC.dbo.controle_processamento_geografico
            SET situacao = 2, data_fim_processamento = GETDATE(), total_vendas = @TotalVendas, 
                total_outra_uf = @QtdOutraUF, percentual_calculado = @Pct, mensagem_erro = NULL
            WHERE cnpj = @CNPJAtual;

        END TRY
        BEGIN CATCH
            UPDATE temp_CGUSC.dbo.controle_processamento_geografico
            SET situacao = 3, data_fim_processamento = GETDATE(), mensagem_erro = ERROR_MESSAGE()
            WHERE cnpj = @CNPJAtual;
        END CATCH

        FETCH NEXT FROM cursor_geografico INTO @CNPJAtual;
    END

    CLOSE cursor_geografico;
    DEALLOCATE cursor_geografico;
    
    PRINT 'Lote #' + CAST(@LoteAtual AS VARCHAR) + ' finalizado em ' + CONVERT(VARCHAR, GETDATE(), 120);
    SET @LoteAtual = @LoteAtual + 1;
END

-- ============================================================================
-- 3. CONSOLIDAÇÃO FINAL (MÉDIAS E RISCO)
-- ============================================================================
PRINT '>>> Iniciando Consolidação das Médias Estaduais e Nacionais...';

-- Cálculo por UF
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

-- Cálculo Nacional
DROP TABLE IF EXISTS temp_CGUSC.dbo.indicadorGeografico_BR;
SELECT 
    'BR' AS pais,
    SUM(total_vendas_monitoradas) AS total_vendas_br,
    SUM(qtd_vendas_outra_uf) AS total_outra_br,
    CAST((CAST(SUM(qtd_vendas_outra_uf) AS DECIMAL(18,2)) / NULLIF(SUM(total_vendas_monitoradas), 0)) * 100.0 AS DECIMAL(18,4)) AS percentual_geografico_br
INTO temp_CGUSC.dbo.indicadorGeografico_BR
FROM temp_CGUSC.dbo.indicadorGeografico;

-- Tabela Final Consolidada com Risco Relativo
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
PRINT '>>> Processamento Geográfico Total Concluído!';
GO



select * from controle_processamento_geografico where total_vendas is not null