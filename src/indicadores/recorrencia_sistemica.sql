USE [temp_CGUSC]
GO

-- ============================================================================
-- INDICADOR: Recorrência Sistêmica (Automação de Renovação)
-- OBJETIVO: Identificar compras de medicamentos de uso contínuo que ocorrem no 
-- exato limite do bloqueio legal (PROXIMA_COMPRA), evidenciando automação.
-- ARQUITETURA: Processamento em lote / Fila (mesmo padrão de Vendas Consecutivas)
-- ============================================================================

-- ============================================================================
-- DEFINIÇÃO DE VARIÁVEIS DE LOTE
-- ============================================================================
DECLARE @DataInicio     DATE = '2015-07-01';
DECLARE @DataFim        DATE = '2024-12-31';
DECLARE @LoteTamanho    INT  = 50;

-- ============================================================================
-- PASSO 0: CRIAR TABELA DE RESULTADOS BASE (SE NÃO EXISTIR)
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.objects 
               WHERE object_id = OBJECT_ID(N'temp_CGUSC.fp.indicador_recorrencia_sistemica') 
               AND type in (N'U'))
BEGIN
    CREATE TABLE temp_CGUSC.fp.indicador_recorrencia_sistemica (
        id INT IDENTITY(1,1) PRIMARY KEY,
        cnpj VARCHAR(14) NOT NULL UNIQUE,
        qtd_renovacoes_totais INT,
        qtd_renovacoes_sistemicas INT,
        percentual_recorrencia_sistemica DECIMAL(18,4),
        data_calculo DATETIME DEFAULT GETDATE()
    );

    CREATE NONCLUSTERED INDEX IDX_Indicador_CNPJ_Recorrencia ON temp_CGUSC.fp.indicador_recorrencia_sistemica(cnpj);
    CREATE NONCLUSTERED INDEX IDX_Indicador_Pct_Recorrencia ON temp_CGUSC.fp.indicador_recorrencia_sistemica(percentual_recorrencia_sistemica);
END

-- ============================================================================
-- PASSO 1: TABELA DE CONTROLE DE PROCESSAMENTO (FILA)
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.objects 
               WHERE object_id = OBJECT_ID(N'temp_CGUSC.fp.indicador_controle_recorrencia_sistemica') 
               AND type in (N'U'))
BEGIN
    CREATE TABLE temp_CGUSC.fp.indicador_controle_recorrencia_sistemica (
        id INT IDENTITY(1,1) PRIMARY KEY,
        cnpj VARCHAR(14) NOT NULL UNIQUE,
        data_inicio_processamento DATETIME,
        data_fim_processamento DATETIME,
        situacao INT,           -- 0=Pendente, 1=Processando, 2=Concluído, 3=Erro
        qtd_renovacoes_totais INT,
        qtd_renovacoes_sistemicas INT,
        percentual_calculado DECIMAL(18,4),
        mensagem_erro VARCHAR(MAX),
        tentativas INT DEFAULT 0
    );

    CREATE NONCLUSTERED INDEX IDX_Controle_Situacao_Recorrencia ON temp_CGUSC.fp.indicador_controle_recorrencia_sistemica(situacao, cnpj);
END

-- Popula fila com CNPJs ainda não processados
INSERT INTO temp_CGUSC.fp.indicador_controle_recorrencia_sistemica (cnpj, situacao)
SELECT DISTINCT A.cnpj, 0 AS situacao
FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
LEFT JOIN temp_CGUSC.fp.indicador_controle_recorrencia_sistemica C ON C.cnpj = A.cnpj
WHERE C.cnpj IS NULL;

-- ============================================================================
-- PASSO 2: RECUPERAÇÃO DE PROCESSAMENTOS TRAVADOS
-- ============================================================================
UPDATE temp_CGUSC.fp.indicador_controle_recorrencia_sistemica
SET situacao = 0,
    mensagem_erro = 'Reversão para reprocessamento'
WHERE situacao = 1
  AND DATEDIFF(MINUTE, data_inicio_processamento, GETDATE()) > 30;

-- ============================================================================
-- PASSO 3: PROCESSAMENTO EM LOTE (A MÁGICA TEMPORAL)
-- ============================================================================
DECLARE @CNPJAtual VARCHAR(14);
DECLARE @TotalProcessado INT = 0;
DECLARE @PendenteBatch INT = 1;

WHILE @PendenteBatch > 0
BEGIN
    DECLARE @ContadorBatch INT = 0;

    -- Verifica se tem CNPJs pendentes neste momento
    IF NOT EXISTS (SELECT 1 FROM temp_CGUSC.fp.indicador_controle_recorrencia_sistemica WHERE situacao IN (0, 3) AND tentativas < 3)
    BEGIN
        SET @PendenteBatch = 0;
        BREAK;
    END

    -- Cria o cursor peguntando apenas aquele limite definido no lote
    DECLARE cursor_cnpjs_recorrencia CURSOR LOCAL FAST_FORWARD FOR
        SELECT TOP (@LoteTamanho) cnpj
        FROM temp_CGUSC.fp.indicador_controle_recorrencia_sistemica
        WHERE situacao IN (0, 3) AND tentativas < 3
        ORDER BY cnpj;

    OPEN cursor_cnpjs_recorrencia;
    FETCH NEXT FROM cursor_cnpjs_recorrencia INTO @CNPJAtual;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            -- Marca como "Processando"
            UPDATE temp_CGUSC.fp.indicador_controle_recorrencia_sistemica
            SET situacao = 1,
                data_inicio_processamento = GETDATE(),
                tentativas = tentativas + 1
            WHERE cnpj = @CNPJAtual;

            -- 3.1 Captura o histórico de compras com princípio ativo e calcula o LAG
            DROP TABLE IF EXISTS #HistoricoCompras;
            SELECT
                A.cpf,
                A.data_hora AS data_compra_atual,
                P.PRINCIPIO_ATIVO AS principio_ativo,
                P.PROXIMA_COMPRA AS dias_para_bloqueio,
                LAG(A.data_hora) OVER(
                    PARTITION BY A.cpf, P.PRINCIPIO_ATIVO 
                    ORDER BY A.data_hora ASC
                ) AS data_compra_anterior
            INTO #HistoricoCompras
            FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A (NOLOCK)
            INNER JOIN temp_CGUSC.fp.medicamentos_patologia MP (NOLOCK) 
                ON MP.codigo_barra = A.codigo_barra
            INNER JOIN temp_CGUSC.fp.posologia_tempo_bloqueio P (NOLOCK)
                ON P.PRINCIPIO_ATIVO = MP.principio_ativo
            WHERE A.cnpj = @CNPJAtual
              AND A.data_hora >= @DataInicio
              AND A.data_hora <= @DataFim;

            -- 3.2 Avalia regras e contabiliza as ocorrências no limite
            DECLARE @TotalRenovacoes INT = 0;
            DECLARE @RenovacoesSistemicas INT = 0;
            DECLARE @Percentual DECIMAL(18,4) = 0;

            SELECT 
                @TotalRenovacoes = COUNT(*),
                @RenovacoesSistemicas = SUM(CASE 
                    -- Se a compra ocorrer rente ao limite do bloqueio até 1 dia depois
                    WHEN DATEDIFF(DAY, data_compra_anterior, data_compra_atual) BETWEEN dias_para_bloqueio AND (dias_para_bloqueio + 1)
                    THEN 1 ELSE 0 END)
            FROM #HistoricoCompras
            WHERE data_compra_anterior IS NOT NULL; -- Apenas consideram pacientes que retornaram

            -- 3.3 Calcula o Percentual (considerando relevância > 10 retornos para não mascarar dados reais)
            SET @Percentual = CASE
                WHEN @TotalRenovacoes >= 10 
                    THEN (CAST(@RenovacoesSistemicas AS DECIMAL(18,2)) / CAST(@TotalRenovacoes AS DECIMAL(18,2))) * 100.0
                ELSE 0
            END;

            -- 3.4 Salva resultado individual na tabela base
            IF EXISTS (SELECT 1 FROM temp_CGUSC.fp.indicador_recorrencia_sistemica WHERE cnpj = @CNPJAtual)
                UPDATE temp_CGUSC.fp.indicador_recorrencia_sistemica
                SET qtd_renovacoes_totais            = @TotalRenovacoes,
                qtd_renovacoes_sistemicas        = ISNULL(@RenovacoesSistemicas, 0),
                    percentual_recorrencia_sistemica = @Percentual,
                    data_calculo                     = GETDATE()
                WHERE cnpj = @CNPJAtual;
            ELSE
                INSERT INTO temp_CGUSC.fp.indicador_recorrencia_sistemica
                    (cnpj, qtd_renovacoes_totais, qtd_renovacoes_sistemicas, percentual_recorrencia_sistemica)
                VALUES (@CNPJAtual, @TotalRenovacoes, ISNULL(@RenovacoesSistemicas, 0), @Percentual);

            -- 3.5 Marca como "Concluído"
            UPDATE temp_CGUSC.fp.indicador_controle_recorrencia_sistemica
            SET situacao                  = 2,
                data_fim_processamento    = GETDATE(),
                qtd_renovacoes_totais     = @TotalRenovacoes,
                qtd_renovacoes_sistemicas = ISNULL(@RenovacoesSistemicas, 0),
                percentual_calculado      = @Percentual,
                mensagem_erro             = NULL
            WHERE cnpj = @CNPJAtual;

            SET @ContadorBatch = @ContadorBatch + 1;
            SET @TotalProcessado = @TotalProcessado + 1;

            IF @TotalProcessado % 50 = 0
                PRINT CONCAT('Processados: ', @TotalProcessado, ' CNPJs no geral...');

        END TRY
        BEGIN CATCH
            UPDATE temp_CGUSC.fp.indicador_controle_recorrencia_sistemica
            SET situacao               = 3,
                data_fim_processamento = GETDATE(),
                mensagem_erro          = ERROR_MESSAGE()
            WHERE cnpj = @CNPJAtual;
        END CATCH

        FETCH NEXT FROM cursor_cnpjs_recorrencia INTO @CNPJAtual;
    END

    CLOSE cursor_cnpjs_recorrencia;
    DEALLOCATE cursor_cnpjs_recorrencia;

    -- Se não processou ninguem, encerra para evitar loop infinito
    IF @ContadorBatch = 0
    BEGIN
        SET @PendenteBatch = 0;
    END
END

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
FROM temp_CGUSC.fp.indicador_controle_recorrencia_sistemica
GROUP BY situacao
ORDER BY situacao;

-- ============================================================================
-- VERIFICAÇÃO: SÓ CONTINUA SE TODOS OS CNPJS ESTIVEREM CONCLUÍDOS
-- ============================================================================
DECLARE @Pendentes INT;
SELECT @Pendentes = COUNT(*)
FROM temp_CGUSC.fp.indicador_controle_recorrencia_sistemica
WHERE situacao IN (0, 1)
   OR (situacao = 3 AND tentativas < 3);

IF @Pendentes > 0
BEGIN
    PRINT '=======================================================================';
    PRINT CONCAT('ATENÇÃO: Ainda existem ', @Pendentes, ' CNPJs pendentes de processamento.');
    PRINT 'Execute este script novamente para processar o próximo lote.');
    PRINT 'A matriz de risco e georreferenciamento será gerada apenas após 100% de conclusão.';
    PRINT '=======================================================================';
END
ELSE
BEGIN
    PRINT '=======================================================================';
    PRINT 'TODOS OS CNPJs PROCESSADOS! Gerando matriz final consolidada...';
    PRINT '=======================================================================';

    -- ========================================================================
    -- PASSO 4, 5 e 6: MÉTRICAS MUNICIPAIS, ESTADUAIS e NACIONAL
    -- ========================================================================
    PRINT 'PASSO 4: Calculando métricas geográficas (Mediana/Média MUM, UF, BR)...';

    -- 4.1. MUNICÍPIO (MUM)
    DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_recorrencia_sistemica_mun;
    SELECT DISTINCT
        CAST(F.uf AS VARCHAR(2))          AS uf,
        CAST(F.municipio AS VARCHAR(255)) AS municipio,
        CAST(
            PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.percentual_recorrencia_sistemica)
            OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255)))
        AS DECIMAL(18,4)) AS mediana_municipio,
        CAST(
            AVG(I.percentual_recorrencia_sistemica)
            OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255)))
        AS DECIMAL(18,4)) AS media_municipio
    INTO temp_CGUSC.fp.indicador_recorrencia_sistemica_mun
    FROM temp_CGUSC.fp.indicador_recorrencia_sistemica I
    INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj;
    
    CREATE CLUSTERED INDEX IDX_IndRecorrMun ON temp_CGUSC.fp.indicador_recorrencia_sistemica_mun(uf, municipio);

    -- 4.2. ESTADO (UF)
    DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_recorrencia_sistemica_uf;
    SELECT DISTINCT
        CAST(F.uf AS VARCHAR(2)) AS uf,
        CAST(
            PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.percentual_recorrencia_sistemica)
            OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)))
        AS DECIMAL(18,4)) AS mediana_estado,
        CAST(
            AVG(I.percentual_recorrencia_sistemica)
            OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)))
        AS DECIMAL(18,4)) AS media_estado
    INTO temp_CGUSC.fp.indicador_recorrencia_sistemica_uf
    FROM temp_CGUSC.fp.indicador_recorrencia_sistemica I
    INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj;

    CREATE CLUSTERED INDEX IDX_IndRecorrUF ON temp_CGUSC.fp.indicador_recorrencia_sistemica_uf(uf);

    -- 4.3. BRASIL (BR)
    DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_recorrencia_sistemica_br;
    SELECT DISTINCT
        'BR' AS pais,
        CAST(
            PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY percentual_recorrencia_sistemica) OVER ()
        AS DECIMAL(18,4)) AS mediana_pais,
        CAST(
            AVG(percentual_recorrencia_sistemica) OVER ()
        AS DECIMAL(18,4)) AS media_pais
    INTO temp_CGUSC.fp.indicador_recorrencia_sistemica_br
    FROM temp_CGUSC.fp.indicador_recorrencia_sistemica;

    -- ========================================================================
    -- PASSO 7: TABELA CONSOLIDADA FINAL DETALHADA COM RISCO E RANKING
    -- ========================================================================
    PRINT 'PASSO 7: Gerando tabela descritiva DETALHADA...';

    DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_recorrencia_sistemica_detalhado;

    SELECT
        I.cnpj,
        F.razaoSocial,
        CAST(F.municipio AS VARCHAR(255)) AS municipio,
        CAST(F.uf AS VARCHAR(2)) AS uf,

        -- Indicadores base
        I.qtd_renovacoes_totais,
        I.qtd_renovacoes_sistemicas,
        I.percentual_recorrencia_sistemica,

        -- Rankings (pior risco = posicao 1)
        RANK() OVER (
            ORDER BY I.percentual_recorrencia_sistemica DESC
        ) AS ranking_br,
        RANK() OVER (
            PARTITION BY CAST(F.uf AS VARCHAR(2))
            ORDER BY I.percentual_recorrencia_sistemica DESC
        ) AS ranking_uf,
        RANK() OVER (
            PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255))
            ORDER BY I.percentual_recorrencia_sistemica DESC
        ) AS ranking_municipio,

        -- Benchmarks Municipais & Risco Relativo
        ISNULL(MUN.mediana_municipio, 0) AS municipio_mediana,
        ISNULL(MUN.media_municipio,   0) AS municipio_media,
        CAST((I.percentual_recorrencia_sistemica + 0.01) / (ISNULL(MUN.mediana_municipio, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_mediana,
        CAST((I.percentual_recorrencia_sistemica + 0.01) / (ISNULL(MUN.media_municipio, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_media,

        -- Benchmarks Estaduais & Risco Relativo
        ISNULL(UF.mediana_estado, 0) AS estado_mediana,
        ISNULL(UF.media_estado,   0) AS estado_media,
        CAST((I.percentual_recorrencia_sistemica + 0.01) / (ISNULL(UF.mediana_estado, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_mediana,
        CAST((I.percentual_recorrencia_sistemica + 0.01) / (ISNULL(UF.media_estado, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_media,

        -- Benchmarks Nacionais & Risco Relativo
        BR.mediana_pais AS pais_mediana,
        BR.media_pais   AS pais_media,
        CAST((I.percentual_recorrencia_sistemica + 0.01) / (BR.mediana_pais + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_mediana,
        CAST((I.percentual_recorrencia_sistemica + 0.01) / (BR.media_pais + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_media

    INTO temp_CGUSC.fp.indicador_recorrencia_sistemica_detalhado
    FROM temp_CGUSC.fp.indicador_recorrencia_sistemica I
    INNER JOIN temp_CGUSC.fp.dados_farmacia F
        ON F.cnpj = I.cnpj
    LEFT JOIN temp_CGUSC.fp.indicador_recorrencia_sistemica_mun MUN
        ON CAST(F.uf AS VARCHAR(2))          = MUN.uf
       AND CAST(F.municipio AS VARCHAR(255)) = MUN.municipio
    LEFT JOIN temp_CGUSC.fp.indicador_recorrencia_sistemica_uf UF
        ON CAST(F.uf AS VARCHAR(2)) = UF.uf
    CROSS JOIN temp_CGUSC.fp.indicador_recorrencia_sistemica_br BR;

    CREATE CLUSTERED INDEX IDX_FinalRecorrencia_CNPJ ON temp_CGUSC.fp.indicador_recorrencia_sistemica_detalhado(cnpj);
    
    PRINT CONCAT('Tabela detalhada final criada com sucesso: ', @@ROWCOUNT, ' farmácias.');
    PRINT 'O Indicador "Recorrência Sistêmica" agora pode ser incluído no matriz_risco_final.sql!';
END
GO
