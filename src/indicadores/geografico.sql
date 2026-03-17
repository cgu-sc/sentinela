USE [temp_CGUSC]
GO

-- ============================================================================
-- DEFINIÇÃO DE VARIÁVEIS
-- ============================================================================
DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim DATE = '2024-12-10';
DECLARE @LoteTamanho INT = 500;

-- ============================================================================
-- PASSO 1: GARANTIR TABELAS DE CONTROLE (Independente se já existem)
-- ============================================================================
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'temp_CGUSC.fp.indicador_geografico'))
BEGIN
    CREATE TABLE temp_CGUSC.fp.indicador_geografico (
        cnpj VARCHAR(14) PRIMARY KEY,
        total_vendas_monitoradas INT,
        qtd_vendas_outra_uf INT,
        percentual_geografico DECIMAL(18,4),
        data_calculo DATETIME DEFAULT GETDATE()
    );
END

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'temp_CGUSC.fp.indicador_controle_geografico'))
BEGIN
    CREATE TABLE temp_CGUSC.fp.indicador_controle_geografico (
        cnpj VARCHAR(14) PRIMARY KEY,
        situacao INT DEFAULT 0, -- 0:Pendente, 1:Processando, 2:Concluído, 3:Erro
        tentativas INT DEFAULT 0,
        data_inicio_processamento DATETIME,
        data_fim_processamento DATETIME,
        total_vendas INT,
        total_outra_uf INT,
        percentual_calculado DECIMAL(18,4),
        mensagem_erro VARCHAR(MAX)
    );
END

-- POPULAÇÃO (FORA DO IF NOT EXISTS - Garante que novos CNPJs entrem na fila)
INSERT INTO temp_CGUSC.fp.indicador_controle_geografico (cnpj)
SELECT DISTINCT A.cnpj 
FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
LEFT JOIN temp_CGUSC.fp.indicador_controle_geografico C ON C.cnpj = A.cnpj
WHERE C.cnpj IS NULL;

-- ============================================================================
-- PASSO 2: RECUPERAÇÃO DE PROCESSAMENTOS TRAVADOS
-- ============================================================================
UPDATE temp_CGUSC.fp.indicador_controle_geografico
SET situacao = 0, mensagem_erro = 'Reversão para modelo estável'
WHERE situacao = 1 AND DATEDIFF(MINUTE, data_inicio_processamento, GETDATE()) > 30;

-- ============================================================================
-- PASSO 3: O MOTOR (CURSOR POR LOTES) - IDÊNTICO AO ORIGINAL
-- ============================================================================
DECLARE @CNPJAtual VARCHAR(14);
DECLARE @PendentesAgua INT;

-- Verifica quantos faltam no início do lote
SELECT @PendentesAgua = COUNT(*) 
FROM temp_CGUSC.fp.indicador_controle_geografico 
WHERE situacao IN (0, 3) AND tentativas < 3;

WHILE @PendentesAgua > 0
BEGIN
    PRINT CONCAT('>>> Iniciando novo lote. Pendentes: ', @PendentesAgua);

    DECLARE cursor_cnpjs CURSOR FOR
        SELECT TOP (@LoteTamanho) cnpj
        FROM temp_CGUSC.fp.indicador_controle_geografico
        WHERE situacao IN (0, 3) AND tentativas < 3 ORDER BY cnpj;

    OPEN cursor_cnpjs;
    FETCH NEXT FROM cursor_cnpjs INTO @CNPJAtual;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            -- MARCA COMO "PROCESSANDO"
            UPDATE temp_CGUSC.fp.indicador_controle_geografico 
            SET situacao = 1, data_inicio_processamento = GETDATE(), tentativas = tentativas + 1 
            WHERE cnpj = @CNPJAtual;

            -- CÁLCULO DO INDICADOR (APENAS ITENS AUDITADOS E CPF IDENTIFICADO)
            DROP TABLE IF EXISTS #VendasTemp;
            SELECT 
                A.num_autorizacao,
                MAX(B.unidadeFederacao) AS uf_paciente,
                MAX(F.uf) AS uf_farmacia
            INTO #VendasTemp
            FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A WITH(NOLOCK)
            INNER JOIN temp_CGUSC.fp.dados_farmacia F WITH(NOLOCK) ON F.cnpj = A.cnpj
            INNER JOIN db_CPF.dbo.CPF B WITH(NOLOCK) ON B.CPF = A.cpf
            INNER JOIN temp_CGUSC.fp.medicamentos_patologia Pat ON Pat.codigo_barra = A.codigo_barra

            WHERE A.cnpj = @CNPJAtual AND A.data_hora >= @DataInicio AND A.data_hora <= @DataFim
            GROUP BY A.num_autorizacao;

            DECLARE @TotalVendas INT, @QtdOutraUF INT, @Pct DECIMAL(18,4);
            SELECT 
                @TotalVendas = COUNT(*),
                @QtdOutraUF = SUM(CASE WHEN uf_paciente IS NOT NULL AND uf_farmacia IS NOT NULL 
                                       AND CAST(uf_paciente AS VARCHAR(2)) <> CAST(uf_farmacia AS VARCHAR(2)) THEN 1 ELSE 0 END)
            FROM #VendasTemp;

            SET @Pct = CASE WHEN @TotalVendas > 0 THEN (CAST(@QtdOutraUF AS DECIMAL(18,2)) / @TotalVendas) * 100.0 ELSE 0 END;

            -- Salva Resultados individuais
            IF EXISTS (SELECT 1 FROM temp_CGUSC.fp.indicador_geografico WHERE cnpj = @CNPJAtual)
                UPDATE temp_CGUSC.fp.indicador_geografico SET total_vendas_monitoradas = @TotalVendas, qtd_vendas_outra_uf = @QtdOutraUF, percentual_geografico = @Pct, data_calculo = GETDATE() WHERE cnpj = @CNPJAtual;
            ELSE
                INSERT INTO temp_CGUSC.fp.indicador_geografico (cnpj, total_vendas_monitoradas, qtd_vendas_outra_uf, percentual_geografico) VALUES (@CNPJAtual, @TotalVendas, @QtdOutraUF, @Pct);

            -- MARCA COMO "CONCLUÍDO"
            UPDATE temp_CGUSC.fp.indicador_controle_geografico 
            SET situacao = 2, data_fim_processamento = GETDATE(), total_vendas = @TotalVendas, total_outra_uf = @QtdOutraUF, percentual_calculado = @Pct, mensagem_erro = NULL 
            WHERE cnpj = @CNPJAtual;

        END TRY
        BEGIN CATCH
            UPDATE temp_CGUSC.fp.indicador_controle_geografico 
            SET situacao = 3, data_fim_processamento = GETDATE(), mensagem_erro = ERROR_MESSAGE() 
            WHERE cnpj = @CNPJAtual;
        END CATCH
        
        FETCH NEXT FROM cursor_cnpjs INTO @CNPJAtual;
    END
    CLOSE cursor_cnpjs; DEALLOCATE cursor_cnpjs;

    -- Atualiza contagem para o próximo lote
    SELECT @PendentesAgua = COUNT(*) 
    FROM temp_CGUSC.fp.indicador_controle_geografico 
    WHERE situacao IN (0, 3) AND tentativas < 3;
END

-- ============================================================================
-- PASSO 4: CONSOLIDAÇÃO FINAL (APENAS QUANDO TODOS FOREM CONCLUÍDOS)
-- ============================================================================
IF NOT EXISTS (SELECT 1 FROM temp_CGUSC.fp.indicador_controle_geografico WHERE situacao IN (0, 1, 3))
BEGIN
PRINT 'PASSO 3: Calculando metricas por municipio...';

DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_geografico_mun;

SELECT DISTINCT
    F.uf,
    F.municipio,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.percentual_geografico, 0))
        OVER (PARTITION BY F.uf, F.municipio)
    AS DECIMAL(18,4)) AS mediana_municipio,
    CAST(
        AVG(ISNULL(I.percentual_geografico, 0))
        OVER (PARTITION BY F.uf, F.municipio)
    AS DECIMAL(18,4)) AS media_municipio
INTO temp_CGUSC.fp.indicador_geografico_mun
FROM temp_CGUSC.fp.dados_farmacia F
LEFT JOIN temp_CGUSC.fp.indicador_geografico I ON I.cnpj = F.cnpj;

CREATE CLUSTERED INDEX IDX_IndGeoMun_mun ON temp_CGUSC.fp.indicador_geografico_mun(uf, municipio);


-- ============================================================================
-- PASSO 4: METRICAS POR ESTADO (MEDIA E MEDIANA)
-- ============================================================================
PRINT 'PASSO 4: Calculando metricas por estado...';

DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_geografico_uf;

SELECT DISTINCT
    F.uf,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.percentual_geografico, 0))
        OVER (PARTITION BY F.uf)
    AS DECIMAL(18,4)) AS mediana_estado,
    CAST(
        AVG(ISNULL(I.percentual_geografico, 0))
        OVER (PARTITION BY F.uf)
    AS DECIMAL(18,4)) AS media_estado
INTO temp_CGUSC.fp.indicador_geografico_uf
FROM temp_CGUSC.fp.dados_farmacia F
LEFT JOIN temp_CGUSC.fp.indicador_geografico I ON I.cnpj = F.cnpj;

CREATE CLUSTERED INDEX IDX_IndGeoUF_uf ON temp_CGUSC.fp.indicador_geografico_uf(uf);


-- ============================================================================
-- PASSO 4B: METRICAS POR REGIAO DE SAUDE (MEDIA E MEDIANA)
-- ============================================================================
PRINT 'PASSO 4B: Calculando metricas por regiao de saude...';

DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_geografico_regiao;

SELECT DISTINCT
    F.id_regiao_saude,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.percentual_geografico, 0))
        OVER (PARTITION BY F.id_regiao_saude)
    AS DECIMAL(18,4)) AS mediana_regiao,
    CAST(
        AVG(ISNULL(I.percentual_geografico, 0))
        OVER (PARTITION BY F.id_regiao_saude)
    AS DECIMAL(18,4)) AS media_regiao
INTO temp_CGUSC.fp.indicador_geografico_regiao
FROM temp_CGUSC.fp.dados_farmacia F
LEFT JOIN temp_CGUSC.fp.indicador_geografico I ON I.cnpj = F.cnpj
WHERE F.id_regiao_saude IS NOT NULL;

CREATE CLUSTERED INDEX IDX_IndGeoReg ON temp_CGUSC.fp.indicador_geografico_regiao(id_regiao_saude);

PRINT 'PASSO 5: Calculando metricas nacionais...';

DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_geografico_br;

SELECT DISTINCT
    'BR' AS pais,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(percentual_geografico, 0)) OVER ()
    AS DECIMAL(18,4)) AS mediana_pais,
    CAST(
        AVG(ISNULL(percentual_geografico, 0)) OVER ()
    AS DECIMAL(18,4)) AS media_pais
INTO temp_CGUSC.fp.indicador_geografico_br
FROM temp_CGUSC.fp.dados_farmacia F
LEFT JOIN temp_CGUSC.fp.indicador_geografico I ON I.cnpj = F.cnpj;

PRINT 'PASSO 6: Gerando tabela consolidada com riscos relativos e rankings...';

DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_geografico_detalhado;

SELECT
    F.cnpj,
    F.razaoSocial,
    F.municipio,
    F.uf,
    F.no_regiao_saude,
    F.id_regiao_saude,

    -- Indicadores base
    ISNULL(I.total_vendas_monitoradas, 0) AS total_vendas_monitoradas,
    ISNULL(I.qtd_vendas_outra_uf, 0)       AS qtd_vendas_outra_uf,
    ISNULL(I.percentual_geografico, 0)    AS percentual_geografico,

    -- Rankings (pior risco = posicao 1)
    RANK() OVER (
        ORDER BY ISNULL(I.percentual_geografico, 0) DESC
    ) AS ranking_br,
    RANK() OVER (
        PARTITION BY F.uf
        ORDER BY ISNULL(I.percentual_geografico, 0) DESC
    ) AS ranking_uf,
    RANK() OVER (
        PARTITION BY F.id_regiao_saude
        ORDER BY ISNULL(I.percentual_geografico, 0) DESC
    ) AS ranking_regiao_saude,
    RANK() OVER (
        PARTITION BY F.uf, F.municipio
        ORDER BY ISNULL(I.percentual_geografico, 0) DESC
    ) AS ranking_municipio,

    -- Benchmarks municipais
    ISNULL(MUN.mediana_municipio, 0) AS municipio_mediana,
    ISNULL(MUN.media_municipio,   0) AS municipio_media,
    CAST((ISNULL(I.percentual_geografico, 0) + 0.01) / (ISNULL(MUN.mediana_municipio, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_mediana,
    CAST((ISNULL(I.percentual_geografico, 0) + 0.01) / (ISNULL(MUN.media_municipio,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_media,

    -- Benchmarks estaduais
    ISNULL(UF.mediana_estado, 0) AS estado_mediana,
    ISNULL(UF.media_estado,   0) AS estado_media,
    CAST((ISNULL(I.percentual_geografico, 0) + 0.01) / (ISNULL(UF.mediana_estado, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_mediana,
    CAST((ISNULL(I.percentual_geografico, 0) + 0.01) / (ISNULL(UF.media_estado,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_media,

    -- Benchmarks Regionais (Regiao de Saude)
    ISNULL(REG.mediana_regiao, 0) AS regiao_saude_mediana,
    ISNULL(REG.media_regiao,   0) AS regiao_saude_media,
    CAST((ISNULL(I.percentual_geografico, 0) + 0.01) / (ISNULL(REG.mediana_regiao, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_reg_mediana,
    CAST((ISNULL(I.percentual_geografico, 0) + 0.01) / (ISNULL(REG.media_regiao,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_reg_media,

    -- Benchmarks nacionais
    BR.mediana_pais AS pais_mediana,
    BR.media_pais   AS pais_media,
    CAST((ISNULL(I.percentual_geografico, 0) + 0.01) / (BR.mediana_pais + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_mediana,
    CAST((ISNULL(I.percentual_geografico, 0) + 0.01) / (BR.media_pais   + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_media

INTO temp_CGUSC.fp.indicador_geografico_detalhado
FROM temp_CGUSC.fp.dados_farmacia F
LEFT JOIN temp_CGUSC.fp.indicador_geografico I
    ON I.cnpj = F.cnpj
LEFT JOIN temp_CGUSC.fp.indicador_geografico_mun MUN
    ON F.uf        = MUN.uf
   AND F.municipio = MUN.municipio
LEFT JOIN temp_CGUSC.fp.indicador_geografico_uf UF
    ON F.uf = UF.uf
LEFT JOIN temp_CGUSC.fp.indicador_geografico_regiao REG
    ON F.id_regiao_saude = REG.id_regiao_saude
CROSS JOIN temp_CGUSC.fp.indicador_geografico_br BR;

CREATE CLUSTERED INDEX IDX_FinalGeo_CNPJ     ON temp_CGUSC.fp.indicador_geografico_detalhado(cnpj);
CREATE NONCLUSTERED INDEX IDX_FinalGeo_Risco  ON temp_CGUSC.fp.indicador_geografico_detalhado(percentual_geografico DESC);
CREATE NONCLUSTERED INDEX IDX_FinalGeo_RankBR ON temp_CGUSC.fp.indicador_geografico_detalhado(ranking_br);

-- ============================================================================
-- PASSO 7: LIMPEZA DAS TABELAS INTERMEDIARIAS
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_geografico_mun;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_geografico_uf;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_geografico_regiao;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_geografico_br;

PRINT 'CONSOLIDAÇÃO FINAL CONCLUÍDA COM SUCESSO!';
END
ELSE
BEGIN
    DECLARE @Faltam INT;
    SELECT @Faltam = COUNT(*) FROM temp_CGUSC.fp.indicador_controle_geografico WHERE situacao IN (0, 1, 3);
    PRINT CONCAT('Lote concluído, mas ainda faltam ', @Faltam, ' CNPJs. Execute o script novamente para o próximo lote.');
END
GO
