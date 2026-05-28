USE [temp_CGUSC]
GO

-- ============================================================================
-- INDICADOR DE DISPERSAO GEOGRAFICA
-- ============================================================================
-- OBJETIVO: Identificar farmacias com proporcao atipica de autorizacoes
--           realizadas para beneficiarios residentes em UF diferente da UF do
--           estabelecimento.
--
-- METRICA PRINCIPAL:
--   O indicador deve ser calculado por periodo a partir dos componentes:
--   valor_vendas_outra_uf / valor_total_auditado.
--
-- FONTE DE DADOS:
--   - db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024
--   - db_CPF.dbo.CPF (UF do beneficiario)
--   - temp_CGUSC.fp.medicamentos_patologia (universo de medicamentos auditados)
--   - temp_CGUSC.fp.dados_farmacia (id_cnpj e contexto territorial)
-- ============================================================================

-- ============================================================================
-- DEFINICAO DE VARIAVEIS
-- ============================================================================
DECLARE @DataInicio  DATE = '2015-07-01';
DECLARE @DataFim     DATE = '2024-12-10';
DECLARE @LoteTamanho INT  = 500;
DECLARE @MaxLotes    INT  = 999;


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
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'cpf') IS NULL
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'num_autorizacao') IS NULL
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'valor_pago') IS NULL
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'data_hora') IS NULL
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'codigo_barra') IS NULL
BEGIN
    RAISERROR('Tabela db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 sem colunas obrigatorias para dispersao geografica.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('db_CPF.dbo.CPF', 'U') IS NULL
BEGIN
    RAISERROR('Tabela db_CPF.dbo.CPF nao encontrada.', 16, 1);
    RETURN;
END;

IF COL_LENGTH('db_CPF.dbo.CPF', 'CPF') IS NULL
   OR COL_LENGTH('db_CPF.dbo.CPF', 'unidadeFederacao') IS NULL
BEGIN
    RAISERROR('Tabela db_CPF.dbo.CPF sem colunas obrigatorias CPF/unidadeFederacao.', 16, 1);
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

-- ============================================================================
-- PASSO 1: TABELA DE RESULTADOS BASE INCREMENTAL
-- ============================================================================
IF OBJECT_ID('temp_CGUSC.fp.indicador_geografico', 'U') IS NULL
BEGIN
    CREATE TABLE temp_CGUSC.fp.indicador_geografico (
        id INT IDENTITY(1,1) PRIMARY KEY,
        id_cnpj INT NOT NULL,
        ano_base SMALLINT NOT NULL,
        total_vendas_monitoradas INT NOT NULL,
        qtd_vendas_outra_uf INT NOT NULL,
        valor_total_auditado DECIMAL(12,2) NOT NULL,
        valor_vendas_outra_uf DECIMAL(12,2) NOT NULL,
        data_calculo DATETIME NOT NULL DEFAULT GETDATE(),
        CONSTRAINT UQ_IndGeografico_CNPJ_Ano UNIQUE (id_cnpj, ano_base)
    );

    CREATE INDEX IDX_IndicadorGeografico_CNPJ_Ano
    ON temp_CGUSC.fp.indicador_geografico(id_cnpj, ano_base);
END
ELSE IF COL_LENGTH('temp_CGUSC.fp.indicador_geografico', 'id_cnpj') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_geografico', 'ano_base') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_geografico', 'total_vendas_monitoradas') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_geografico', 'qtd_vendas_outra_uf') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_geografico', 'valor_total_auditado') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_geografico', 'valor_vendas_outra_uf') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_geografico', 'data_calculo') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_geografico', 'percentual_geografico') IS NOT NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.indicador_geografico existe com schema incompativel. Recrie a tabela antes de executar.', 16, 1);
    RETURN;
END;

ALTER TABLE temp_CGUSC.fp.indicador_geografico
ALTER COLUMN valor_total_auditado DECIMAL(12,2) NOT NULL;

ALTER TABLE temp_CGUSC.fp.indicador_geografico
ALTER COLUMN valor_vendas_outra_uf DECIMAL(12,2) NOT NULL;


-- ============================================================================
-- PASSO 1.1: TABELA AUXILIAR INCREMENTAL POR UF DE ORIGEM DO PACIENTE
-- ============================================================================
IF OBJECT_ID('temp_CGUSC.fp.indicador_geografico_origem_uf', 'U') IS NULL
BEGIN
    CREATE TABLE temp_CGUSC.fp.indicador_geografico_origem_uf (
        id INT IDENTITY(1,1) PRIMARY KEY,
        id_cnpj INT NOT NULL,
        ano_base SMALLINT NOT NULL,
        uf_farmacia VARCHAR(2) NOT NULL,
        uf_paciente VARCHAR(2) NOT NULL,
        total_pacientes_distintos_cnpj_ano INT NOT NULL,
        total_pacientes_distintos_outra_uf INT NOT NULL,
        qtd_pacientes_distintos_uf INT NOT NULL,
        qtd_autorizacoes_uf INT NOT NULL,
        valor_total_uf DECIMAL(12,2) NOT NULL,
        valor_total_cnpj_ano DECIMAL(12,2) NOT NULL,
        data_calculo DATETIME NOT NULL DEFAULT GETDATE(),
        CONSTRAINT UQ_IndGeoOrigemUF_CNPJ_Ano_UF UNIQUE (id_cnpj, ano_base, uf_paciente)
    );

    CREATE INDEX IDX_IndGeoOrigemUF_CNPJ_Ano
    ON temp_CGUSC.fp.indicador_geografico_origem_uf(id_cnpj, ano_base);
END
ELSE IF COL_LENGTH('temp_CGUSC.fp.indicador_geografico_origem_uf', 'id') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_geografico_origem_uf', 'id_cnpj') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_geografico_origem_uf', 'ano_base') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_geografico_origem_uf', 'uf_farmacia') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_geografico_origem_uf', 'uf_paciente') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_geografico_origem_uf', 'total_pacientes_distintos_cnpj_ano') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_geografico_origem_uf', 'total_pacientes_distintos_outra_uf') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_geografico_origem_uf', 'qtd_pacientes_distintos_uf') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_geografico_origem_uf', 'qtd_autorizacoes_uf') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_geografico_origem_uf', 'valor_total_uf') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_geografico_origem_uf', 'valor_total_cnpj_ano') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_geografico_origem_uf', 'data_calculo') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.indicador_geografico_origem_uf existe com schema incompativel. Recrie a tabela antes de executar.', 16, 1);
    RETURN;
END;

ALTER TABLE temp_CGUSC.fp.indicador_geografico_origem_uf
ALTER COLUMN valor_total_uf DECIMAL(12,2) NOT NULL;

ALTER TABLE temp_CGUSC.fp.indicador_geografico_origem_uf
ALTER COLUMN valor_total_cnpj_ano DECIMAL(12,2) NOT NULL;


-- ============================================================================
-- PASSO 2: TABELA DE CONTROLE DE PROCESSAMENTO
-- ============================================================================
IF OBJECT_ID('temp_CGUSC.fp.indicador_controle_geografico', 'U') IS NULL
BEGIN
    CREATE TABLE temp_CGUSC.fp.indicador_controle_geografico (
        id INT IDENTITY(1,1) PRIMARY KEY,
        cnpj VARCHAR(14) NOT NULL UNIQUE,
        data_inicio_processamento DATETIME,
        data_fim_processamento DATETIME,
        situacao INT NOT NULL, -- 0=Pendente, 1=Processando, 2=Concluido, 3=Erro
        total_vendas INT,
        total_outra_uf INT,
        valor_total_auditado DECIMAL(19,2),
        valor_vendas_outra_uf DECIMAL(19,2),
        mensagem_erro VARCHAR(MAX),
        tentativas INT NOT NULL DEFAULT 0
    );

    CREATE INDEX IDX_ControleGeografico_Situacao
    ON temp_CGUSC.fp.indicador_controle_geografico(situacao, cnpj);
END
ELSE IF COL_LENGTH('temp_CGUSC.fp.indicador_controle_geografico', 'cnpj') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_controle_geografico', 'id') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_controle_geografico', 'data_inicio_processamento') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_controle_geografico', 'data_fim_processamento') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_controle_geografico', 'situacao') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_controle_geografico', 'total_vendas') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_controle_geografico', 'total_outra_uf') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_controle_geografico', 'valor_total_auditado') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_controle_geografico', 'valor_vendas_outra_uf') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_controle_geografico', 'mensagem_erro') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_controle_geografico', 'tentativas') IS NULL
     OR COL_LENGTH('temp_CGUSC.fp.indicador_controle_geografico', 'percentual_calculado') IS NOT NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.indicador_controle_geografico existe com schema incompativel. Recrie a tabela antes de executar.', 16, 1);
    RETURN;
END;

INSERT INTO temp_CGUSC.fp.indicador_controle_geografico (cnpj, situacao)
SELECT F.cnpj, 0 AS situacao
FROM #farmacias_dim F
LEFT JOIN temp_CGUSC.fp.indicador_controle_geografico C
    ON C.cnpj = F.cnpj
WHERE C.cnpj IS NULL;

UPDATE temp_CGUSC.fp.indicador_controle_geografico
SET situacao = 0,
    mensagem_erro = 'Reversao para reprocessamento'
WHERE situacao = 1
  AND DATEDIFF(MINUTE, data_inicio_processamento, GETDATE()) > 30;


-- ============================================================================
-- PASSO 3: PROCESSAMENTO INCREMENTAL POR LOTE
-- ============================================================================
DECLARE @Contador INT = 0;
DECLARE @LoteAtual INT = 0;
DECLARE @ContadorLote INT;
DECLARE @DataInicioProcessamento DATETIME;
DECLARE @MensagemErroLote VARCHAR(MAX);
DECLARE @LoteInicio DATETIME;
DECLARE @EtapaInicio DATETIME;
DECLARE @LinhasEtapa BIGINT;
DECLARE @MsgLog VARCHAR(1000);

WHILE @LoteAtual < @MaxLotes
  AND EXISTS (
      SELECT 1
      FROM temp_CGUSC.fp.indicador_controle_geografico
      WHERE situacao IN (0, 3)
        AND tentativas < 3
  )
BEGIN
    SET @LoteAtual = @LoteAtual + 1;
    SET @ContadorLote = 0;
    SET @LoteInicio = GETDATE();

    UPDATE temp_CGUSC.fp.indicador_controle_geografico
    SET situacao = 0,
        mensagem_erro = 'Reversao para reprocessamento'
    WHERE situacao = 1
      AND DATEDIFF(MINUTE, data_inicio_processamento, GETDATE()) > 30;

    PRINT '=======================================================================';
    PRINT CONCAT('Iniciando lote geografico ', @LoteAtual, ' de ate ', @LoteTamanho, ' CNPJs.');
    PRINT '=======================================================================';
    SET @MsgLog = CONCAT('[GEO] Lote ', @LoteAtual, ' iniciado em ', CONVERT(VARCHAR(19), @LoteInicio, 120), '.');
    RAISERROR(@MsgLog, 0, 1) WITH NOWAIT;

    DROP TABLE IF EXISTS #lote_atual;

    SET @EtapaInicio = GETDATE();
    SET @MsgLog = CONCAT('[GEO] Lote ', @LoteAtual, ' | Selecionando CNPJs do lote...');
    RAISERROR(@MsgLog, 0, 1) WITH NOWAIT;

    SELECT TOP (@LoteTamanho)
        C.cnpj,
        F.id_cnpj,
        F.uf
    INTO #lote_atual
    FROM temp_CGUSC.fp.indicador_controle_geografico C
    INNER JOIN #farmacias_dim F
        ON F.cnpj = C.cnpj
    WHERE C.situacao IN (0, 3)
      AND C.tentativas < 3
    ORDER BY C.cnpj;

    SET @ContadorLote = @@ROWCOUNT;
    SET @MsgLog = CONCAT(
        '[GEO] Lote ', @LoteAtual,
        ' | #lote_atual: ', @ContadorLote,
        ' CNPJs | tempo ', DATEDIFF(MILLISECOND, @EtapaInicio, GETDATE()), ' ms.'
    );
    RAISERROR(@MsgLog, 0, 1) WITH NOWAIT;

    IF @ContadorLote = 0
        BREAK;

    SET @EtapaInicio = GETDATE();
    CREATE UNIQUE CLUSTERED INDEX IDX_lote_atual_cnpj
    ON #lote_atual(cnpj);

    CREATE UNIQUE NONCLUSTERED INDEX IDX_lote_atual_id
    ON #lote_atual(id_cnpj);
    SET @MsgLog = CONCAT(
        '[GEO] Lote ', @LoteAtual,
        ' | indices de #lote_atual criados | tempo ', DATEDIFF(MILLISECOND, @EtapaInicio, GETDATE()), ' ms.'
    );
    RAISERROR(@MsgLog, 0, 1) WITH NOWAIT;

    BEGIN TRY
        SET @DataInicioProcessamento = GETDATE();

        SET @EtapaInicio = GETDATE();
        SET @MsgLog = CONCAT('[GEO] Lote ', @LoteAtual, ' | Marcando lote como PROCESSANDO...');
        RAISERROR(@MsgLog, 0, 1) WITH NOWAIT;

        UPDATE C
        SET situacao = 1,
            data_inicio_processamento = @DataInicioProcessamento,
            data_fim_processamento = NULL,
            mensagem_erro = NULL,
            tentativas = tentativas + 1
        FROM temp_CGUSC.fp.indicador_controle_geografico C
        INNER JOIN #lote_atual L
            ON L.cnpj = C.cnpj;

        SET @LinhasEtapa = @@ROWCOUNT;
        SET @MsgLog = CONCAT(
            '[GEO] Lote ', @LoteAtual,
            ' | controle PROCESSANDO: ', @LinhasEtapa,
            ' linhas | tempo ', DATEDIFF(MILLISECOND, @EtapaInicio, GETDATE()), ' ms.'
        );
        RAISERROR(@MsgLog, 0, 1) WITH NOWAIT;

        DROP TABLE IF EXISTS #MovimentacaoGeografica;

        SET @EtapaInicio = GETDATE();
        SET @MsgLog = CONCAT('[GEO] Lote ', @LoteAtual, ' | Agregando movimentacao + medicamentos antes do CPF...');
        RAISERROR(@MsgLog, 0, 1) WITH NOWAIT;

        SELECT
            L.id_cnpj,
            CAST(YEAR(A.data_hora) AS SMALLINT) AS ano_base,
            A.num_autorizacao,
            A.cpf,
            MAX(L.uf) AS uf_farmacia,
            CAST(SUM(CAST(A.valor_pago AS DECIMAL(19,2))) AS DECIMAL(12,2)) AS valor_total_autorizacao
        INTO #MovimentacaoGeografica
        FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
        INNER JOIN #lote_atual L
            ON L.cnpj = A.cnpj
        INNER JOIN #medicamentos_patologia_gtin C
            ON C.codigo_barra = A.codigo_barra
        WHERE A.data_hora >= @DataInicio
          AND A.data_hora < DATEADD(DAY, 1, @DataFim)
          AND A.num_autorizacao IS NOT NULL
          AND A.cpf IS NOT NULL
          AND A.valor_pago IS NOT NULL
          AND A.valor_pago >= 0
          AND A.codigo_barra IS NOT NULL
        GROUP BY
            L.id_cnpj,
            YEAR(A.data_hora),
            A.num_autorizacao,
            A.cpf
        OPTION (RECOMPILE);

        SET @LinhasEtapa = @@ROWCOUNT;
        SET @MsgLog = CONCAT(
            '[GEO] Lote ', @LoteAtual,
            ' | #MovimentacaoGeografica: ', @LinhasEtapa,
            ' autorizacoes/CPF/ano | tempo ', DATEDIFF(SECOND, @EtapaInicio, GETDATE()), ' s.'
        );
        RAISERROR(@MsgLog, 0, 1) WITH NOWAIT;

        SET @EtapaInicio = GETDATE();
        CREATE CLUSTERED INDEX IDX_MovimentacaoGeografica_CPF
        ON #MovimentacaoGeografica(cpf);
        SET @MsgLog = CONCAT(
            '[GEO] Lote ', @LoteAtual,
            ' | indice #MovimentacaoGeografica(cpf) criado | tempo ', DATEDIFF(MILLISECOND, @EtapaInicio, GETDATE()), ' ms.'
        );
        RAISERROR(@MsgLog, 0, 1) WITH NOWAIT;

        DROP TABLE IF EXISTS #AutorizacoesGeograficas;

        SET @EtapaInicio = GETDATE();
        SET @MsgLog = CONCAT('[GEO] Lote ', @LoteAtual, ' | Juntando movimentacao agregada com CPF...');
        RAISERROR(@MsgLog, 0, 1) WITH NOWAIT;

        SELECT
            M.id_cnpj,
            M.ano_base,
            M.num_autorizacao,
            M.cpf,
            CAST(UPPER(LTRIM(RTRIM(MAX(CAST(B.unidadeFederacao AS VARCHAR(2)))))) AS VARCHAR(2)) AS uf_paciente,
            MAX(M.uf_farmacia) AS uf_farmacia,
            CAST(SUM(M.valor_total_autorizacao) AS DECIMAL(12,2)) AS valor_total_autorizacao
        INTO #AutorizacoesGeograficas
        FROM #MovimentacaoGeografica M
        INNER JOIN db_CPF.dbo.CPF B
            ON B.CPF = M.cpf
           -- Excecao operacional autorizada: CPF sem UF nao permite classificar
           -- mesma/outra UF. Esses casos saem do universo monitorado.
           -- Remover este filtro quando unidadeFederacao estiver completa na fonte.
           AND NULLIF(LTRIM(RTRIM(CAST(B.unidadeFederacao AS VARCHAR(2)))), '') IS NOT NULL
        GROUP BY
            M.id_cnpj,
            M.ano_base,
            M.num_autorizacao,
            M.cpf
        OPTION (RECOMPILE);

        SET @LinhasEtapa = @@ROWCOUNT;
        SET @MsgLog = CONCAT(
            '[GEO] Lote ', @LoteAtual,
            ' | #AutorizacoesGeograficas: ', @LinhasEtapa,
            ' autorizacoes/ano com CPF localizado | tempo ', DATEDIFF(SECOND, @EtapaInicio, GETDATE()), ' s.'
        );
        RAISERROR(@MsgLog, 0, 1) WITH NOWAIT;

        IF EXISTS (
            SELECT 1
            FROM #AutorizacoesGeograficas
            WHERE NULLIF(LTRIM(RTRIM(uf_paciente)), '') IS NULL
               OR NULLIF(LTRIM(RTRIM(uf_farmacia)), '') IS NULL
        )
        BEGIN
            RAISERROR('Movimentacao geografica possui UF de paciente ou farmacia ausente apos filtro de CPF com UF obrigatoria.', 16, 1);
            RETURN;
        END;

        SET @EtapaInicio = GETDATE();
        CREATE CLUSTERED INDEX IDX_AutorizacoesGeograficas_CNPJ_Ano
        ON #AutorizacoesGeograficas(id_cnpj, ano_base, uf_paciente, cpf, uf_farmacia);
        SET @MsgLog = CONCAT(
            '[GEO] Lote ', @LoteAtual,
            ' | indice #AutorizacoesGeograficas criado | tempo ', DATEDIFF(MILLISECOND, @EtapaInicio, GETDATE()), ' ms.'
        );
        RAISERROR(@MsgLog, 0, 1) WITH NOWAIT;

        DROP TABLE IF EXISTS #ResultadoLote;

        SET @EtapaInicio = GETDATE();
        SET @MsgLog = CONCAT('[GEO] Lote ', @LoteAtual, ' | Agregando resultado por CNPJ/ano...');
        RAISERROR(@MsgLog, 0, 1) WITH NOWAIT;

        SELECT
            id_cnpj,
            ano_base,
            CAST(COUNT(*) AS INT) AS total_vendas_monitoradas,
            CAST(
                SUM(
                    CASE
                        WHEN uf_paciente <> uf_farmacia THEN 1
                        ELSE 0
                    END
                ) AS INT
            ) AS qtd_vendas_outra_uf,
            CAST(SUM(valor_total_autorizacao) AS DECIMAL(12,2)) AS valor_total_auditado,
            CAST(
                SUM(
                    CASE
                        WHEN uf_paciente <> uf_farmacia THEN valor_total_autorizacao
                        ELSE CAST(0 AS DECIMAL(12,2))
                    END
                ) AS DECIMAL(12,2)
            ) AS valor_vendas_outra_uf
        INTO #ResultadoLote
        FROM #AutorizacoesGeograficas
        GROUP BY
            id_cnpj,
            ano_base
        HAVING SUM(valor_total_autorizacao) > 0;

        SET @LinhasEtapa = @@ROWCOUNT;
        SET @MsgLog = CONCAT(
            '[GEO] Lote ', @LoteAtual,
            ' | #ResultadoLote: ', @LinhasEtapa,
            ' linhas | tempo ', DATEDIFF(MILLISECOND, @EtapaInicio, GETDATE()), ' ms.'
        );
        RAISERROR(@MsgLog, 0, 1) WITH NOWAIT;

        SET @EtapaInicio = GETDATE();
        CREATE UNIQUE CLUSTERED INDEX IDX_ResultadoLote_CNPJ_Ano
        ON #ResultadoLote(id_cnpj, ano_base);
        SET @MsgLog = CONCAT(
            '[GEO] Lote ', @LoteAtual,
            ' | indice #ResultadoLote criado | tempo ', DATEDIFF(MILLISECOND, @EtapaInicio, GETDATE()), ' ms.'
        );
        RAISERROR(@MsgLog, 0, 1) WITH NOWAIT;

        DROP TABLE IF EXISTS #PacientesGeoDistinct;

        SET @EtapaInicio = GETDATE();
        SET @MsgLog = CONCAT('[GEO] Lote ', @LoteAtual, ' | Deduplicando pacientes por CNPJ/ano/UF de origem...');
        RAISERROR(@MsgLog, 0, 1) WITH NOWAIT;

        SELECT DISTINCT
            id_cnpj,
            ano_base,
            cpf,
            uf_farmacia,
            uf_paciente
        INTO #PacientesGeoDistinct
        FROM #AutorizacoesGeograficas;

        SET @LinhasEtapa = @@ROWCOUNT;
        SET @MsgLog = CONCAT(
            '[GEO] Lote ', @LoteAtual,
            ' | #PacientesGeoDistinct: ', @LinhasEtapa,
            ' pacientes/CNPJ/ano/UF | tempo ', DATEDIFF(SECOND, @EtapaInicio, GETDATE()), ' s.'
        );
        RAISERROR(@MsgLog, 0, 1) WITH NOWAIT;

        SET @EtapaInicio = GETDATE();
        CREATE UNIQUE CLUSTERED INDEX IDX_PacientesGeoDistinct_CNPJ_Ano_UF_CPF
        ON #PacientesGeoDistinct(id_cnpj, ano_base, uf_paciente, cpf);
        SET @MsgLog = CONCAT(
            '[GEO] Lote ', @LoteAtual,
            ' | indice #PacientesGeoDistinct criado | tempo ', DATEDIFF(MILLISECOND, @EtapaInicio, GETDATE()), ' ms.'
        );
        RAISERROR(@MsgLog, 0, 1) WITH NOWAIT;

        DROP TABLE IF EXISTS #PacientesGeoDenominador;

        SET @EtapaInicio = GETDATE();
        SET @MsgLog = CONCAT('[GEO] Lote ', @LoteAtual, ' | Calculando denominadores de pacientes por CNPJ/ano...');
        RAISERROR(@MsgLog, 0, 1) WITH NOWAIT;

        SELECT
            id_cnpj,
            ano_base,
            CAST(COUNT(*) AS INT) AS total_pacientes_distintos_cnpj_ano,
            CAST(
                SUM(
                    CASE
                        WHEN uf_paciente <> uf_farmacia THEN 1
                        ELSE 0
                    END
                ) AS INT
            ) AS total_pacientes_distintos_outra_uf
        INTO #PacientesGeoDenominador
        FROM #PacientesGeoDistinct
        GROUP BY
            id_cnpj,
            ano_base;

        SET @LinhasEtapa = @@ROWCOUNT;
        SET @MsgLog = CONCAT(
            '[GEO] Lote ', @LoteAtual,
            ' | #PacientesGeoDenominador: ', @LinhasEtapa,
            ' linhas | tempo ', DATEDIFF(MILLISECOND, @EtapaInicio, GETDATE()), ' ms.'
        );
        RAISERROR(@MsgLog, 0, 1) WITH NOWAIT;

        SET @EtapaInicio = GETDATE();
        CREATE UNIQUE CLUSTERED INDEX IDX_PacientesGeoDenominador_CNPJ_Ano
        ON #PacientesGeoDenominador(id_cnpj, ano_base);
        SET @MsgLog = CONCAT(
            '[GEO] Lote ', @LoteAtual,
            ' | indice #PacientesGeoDenominador criado | tempo ', DATEDIFF(MILLISECOND, @EtapaInicio, GETDATE()), ' ms.'
        );
        RAISERROR(@MsgLog, 0, 1) WITH NOWAIT;

        DROP TABLE IF EXISTS #OrigemUfPacientesLote;

        SET @EtapaInicio = GETDATE();
        SET @MsgLog = CONCAT('[GEO] Lote ', @LoteAtual, ' | Agregando pacientes de outra UF por origem...');
        RAISERROR(@MsgLog, 0, 1) WITH NOWAIT;

        SELECT
            id_cnpj,
            ano_base,
            uf_farmacia,
            uf_paciente,
            CAST(COUNT(*) AS INT) AS qtd_pacientes_distintos_uf
        INTO #OrigemUfPacientesLote
        FROM #PacientesGeoDistinct
        WHERE uf_paciente <> uf_farmacia
        GROUP BY
            id_cnpj,
            ano_base,
            uf_farmacia,
            uf_paciente;

        SET @LinhasEtapa = @@ROWCOUNT;
        SET @MsgLog = CONCAT(
            '[GEO] Lote ', @LoteAtual,
            ' | #OrigemUfPacientesLote: ', @LinhasEtapa,
            ' linhas | tempo ', DATEDIFF(MILLISECOND, @EtapaInicio, GETDATE()), ' ms.'
        );
        RAISERROR(@MsgLog, 0, 1) WITH NOWAIT;

        SET @EtapaInicio = GETDATE();
        CREATE UNIQUE CLUSTERED INDEX IDX_OrigemUfPacientesLote_CNPJ_Ano_UF
        ON #OrigemUfPacientesLote(id_cnpj, ano_base, uf_paciente);
        SET @MsgLog = CONCAT(
            '[GEO] Lote ', @LoteAtual,
            ' | indice #OrigemUfPacientesLote criado | tempo ', DATEDIFF(MILLISECOND, @EtapaInicio, GETDATE()), ' ms.'
        );
        RAISERROR(@MsgLog, 0, 1) WITH NOWAIT;

        DROP TABLE IF EXISTS #OrigemUfAutorizacoesLote;

        SET @EtapaInicio = GETDATE();
        SET @MsgLog = CONCAT('[GEO] Lote ', @LoteAtual, ' | Agregando autorizacoes de outra UF por origem...');
        RAISERROR(@MsgLog, 0, 1) WITH NOWAIT;

        SELECT
            id_cnpj,
            ano_base,
            uf_farmacia,
            uf_paciente,
            CAST(COUNT(*) AS INT) AS qtd_autorizacoes_uf,
            CAST(SUM(valor_total_autorizacao) AS DECIMAL(12,2)) AS valor_total_uf
        INTO #OrigemUfAutorizacoesLote
        FROM #AutorizacoesGeograficas
        WHERE uf_paciente <> uf_farmacia
        GROUP BY
            id_cnpj,
            ano_base,
            uf_farmacia,
            uf_paciente;

        SET @LinhasEtapa = @@ROWCOUNT;
        SET @MsgLog = CONCAT(
            '[GEO] Lote ', @LoteAtual,
            ' | #OrigemUfAutorizacoesLote: ', @LinhasEtapa,
            ' linhas | tempo ', DATEDIFF(MILLISECOND, @EtapaInicio, GETDATE()), ' ms.'
        );
        RAISERROR(@MsgLog, 0, 1) WITH NOWAIT;

        SET @EtapaInicio = GETDATE();
        CREATE UNIQUE CLUSTERED INDEX IDX_OrigemUfAutorizacoesLote_CNPJ_Ano_UF
        ON #OrigemUfAutorizacoesLote(id_cnpj, ano_base, uf_paciente);
        SET @MsgLog = CONCAT(
            '[GEO] Lote ', @LoteAtual,
            ' | indice #OrigemUfAutorizacoesLote criado | tempo ', DATEDIFF(MILLISECOND, @EtapaInicio, GETDATE()), ' ms.'
        );
        RAISERROR(@MsgLog, 0, 1) WITH NOWAIT;

        DROP TABLE IF EXISTS #OrigemUfLote;

        SET @EtapaInicio = GETDATE();
        SET @MsgLog = CONCAT('[GEO] Lote ', @LoteAtual, ' | Consolidando origem de pacientes por UF...');
        RAISERROR(@MsgLog, 0, 1) WITH NOWAIT;

        SELECT
            P.id_cnpj,
            P.ano_base,
            P.uf_farmacia,
            P.uf_paciente,
            D.total_pacientes_distintos_cnpj_ano,
            D.total_pacientes_distintos_outra_uf,
            P.qtd_pacientes_distintos_uf,
            A.qtd_autorizacoes_uf,
            A.valor_total_uf,
            R.valor_total_auditado AS valor_total_cnpj_ano
        INTO #OrigemUfLote
        FROM #OrigemUfPacientesLote P
        INNER JOIN #OrigemUfAutorizacoesLote A
            ON A.id_cnpj = P.id_cnpj
           AND A.ano_base = P.ano_base
           AND A.uf_paciente = P.uf_paciente
        INNER JOIN #PacientesGeoDenominador D
            ON D.id_cnpj = P.id_cnpj
           AND D.ano_base = P.ano_base
        INNER JOIN #ResultadoLote R
            ON R.id_cnpj = P.id_cnpj
           AND R.ano_base = P.ano_base;

        SET @LinhasEtapa = @@ROWCOUNT;
        SET @MsgLog = CONCAT(
            '[GEO] Lote ', @LoteAtual,
            ' | #OrigemUfLote: ', @LinhasEtapa,
            ' linhas | tempo ', DATEDIFF(MILLISECOND, @EtapaInicio, GETDATE()), ' ms.'
        );
        RAISERROR(@MsgLog, 0, 1) WITH NOWAIT;

        SET @EtapaInicio = GETDATE();
        CREATE UNIQUE CLUSTERED INDEX IDX_OrigemUfLote_CNPJ_Ano_UF
        ON #OrigemUfLote(id_cnpj, ano_base, uf_paciente);
        SET @MsgLog = CONCAT(
            '[GEO] Lote ', @LoteAtual,
            ' | indice #OrigemUfLote criado | tempo ', DATEDIFF(MILLISECOND, @EtapaInicio, GETDATE()), ' ms.'
        );
        RAISERROR(@MsgLog, 0, 1) WITH NOWAIT;

        DROP TABLE IF EXISTS #ResumoControleLote;

        SET @EtapaInicio = GETDATE();
        SET @MsgLog = CONCAT('[GEO] Lote ', @LoteAtual, ' | Montando resumo do controle...');
        RAISERROR(@MsgLog, 0, 1) WITH NOWAIT;

        SELECT
            L.cnpj,
            CAST(ISNULL(SUM(R.total_vendas_monitoradas), 0) AS INT) AS total_vendas,
            CAST(ISNULL(SUM(R.qtd_vendas_outra_uf), 0) AS INT) AS total_outra_uf,
            CAST(ISNULL(SUM(R.valor_total_auditado), 0) AS DECIMAL(19,2)) AS valor_total_auditado,
            CAST(ISNULL(SUM(R.valor_vendas_outra_uf), 0) AS DECIMAL(19,2)) AS valor_vendas_outra_uf
        INTO #ResumoControleLote
        FROM #lote_atual L
        LEFT JOIN #ResultadoLote R
            ON R.id_cnpj = L.id_cnpj
        GROUP BY L.cnpj;

        SET @LinhasEtapa = @@ROWCOUNT;
        SET @MsgLog = CONCAT(
            '[GEO] Lote ', @LoteAtual,
            ' | #ResumoControleLote: ', @LinhasEtapa,
            ' CNPJs | tempo ', DATEDIFF(MILLISECOND, @EtapaInicio, GETDATE()), ' ms.'
        );
        RAISERROR(@MsgLog, 0, 1) WITH NOWAIT;

        SET @EtapaInicio = GETDATE();
        CREATE UNIQUE CLUSTERED INDEX IDX_ResumoControleLote_CNPJ
        ON #ResumoControleLote(cnpj);
        SET @MsgLog = CONCAT(
            '[GEO] Lote ', @LoteAtual,
            ' | indice #ResumoControleLote criado | tempo ', DATEDIFF(MILLISECOND, @EtapaInicio, GETDATE()), ' ms.'
        );
        RAISERROR(@MsgLog, 0, 1) WITH NOWAIT;

        SET @EtapaInicio = GETDATE();
        SET @MsgLog = CONCAT('[GEO] Lote ', @LoteAtual, ' | Iniciando transacao final DELETE/INSERT/UPDATE...');
        RAISERROR(@MsgLog, 0, 1) WITH NOWAIT;

        BEGIN TRAN;

        DELETE I
        FROM temp_CGUSC.fp.indicador_geografico I
        INNER JOIN #lote_atual L
            ON L.id_cnpj = I.id_cnpj;

        DELETE O
        FROM temp_CGUSC.fp.indicador_geografico_origem_uf O
        INNER JOIN #lote_atual L
            ON L.id_cnpj = O.id_cnpj;

        INSERT INTO temp_CGUSC.fp.indicador_geografico (
            id_cnpj,
            ano_base,
            total_vendas_monitoradas,
            qtd_vendas_outra_uf,
            valor_total_auditado,
            valor_vendas_outra_uf
        )
        SELECT
            id_cnpj,
            ano_base,
            total_vendas_monitoradas,
            qtd_vendas_outra_uf,
            valor_total_auditado,
            valor_vendas_outra_uf
        FROM #ResultadoLote;

        INSERT INTO temp_CGUSC.fp.indicador_geografico_origem_uf (
            id_cnpj,
            ano_base,
            uf_farmacia,
            uf_paciente,
            total_pacientes_distintos_cnpj_ano,
            total_pacientes_distintos_outra_uf,
            qtd_pacientes_distintos_uf,
            qtd_autorizacoes_uf,
            valor_total_uf,
            valor_total_cnpj_ano
        )
        SELECT
            id_cnpj,
            ano_base,
            uf_farmacia,
            uf_paciente,
            total_pacientes_distintos_cnpj_ano,
            total_pacientes_distintos_outra_uf,
            qtd_pacientes_distintos_uf,
            qtd_autorizacoes_uf,
            valor_total_uf,
            valor_total_cnpj_ano
        FROM #OrigemUfLote;

        UPDATE C
        SET situacao = 2,
            data_fim_processamento = GETDATE(),
            total_vendas = R.total_vendas,
            total_outra_uf = R.total_outra_uf,
            valor_total_auditado = R.valor_total_auditado,
            valor_vendas_outra_uf = R.valor_vendas_outra_uf,
            mensagem_erro = NULL
        FROM temp_CGUSC.fp.indicador_controle_geografico C
        INNER JOIN #ResumoControleLote R
            ON R.cnpj = C.cnpj;

        COMMIT TRAN;

        SET @MsgLog = CONCAT(
            '[GEO] Lote ', @LoteAtual,
            ' | transacao final concluida | tempo ', DATEDIFF(MILLISECOND, @EtapaInicio, GETDATE()), ' ms.'
        );
        RAISERROR(@MsgLog, 0, 1) WITH NOWAIT;

        SET @Contador = @Contador + @ContadorLote;

        PRINT CONCAT('Lote ', @LoteAtual, ': processados ', @ContadorLote, ' CNPJs em bloco.');
        SET @MsgLog = CONCAT(
            '[GEO] Lote ', @LoteAtual,
            ' concluido | CNPJs: ', @ContadorLote,
            ' | tempo total ', DATEDIFF(SECOND, @LoteInicio, GETDATE()), ' s',
            ' | total na execucao: ', @Contador, '.'
        );
        RAISERROR(@MsgLog, 0, 1) WITH NOWAIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRAN;

        SET @MensagemErroLote = ERROR_MESSAGE();

        UPDATE C
        SET situacao = 3,
            data_fim_processamento = GETDATE(),
            mensagem_erro = @MensagemErroLote
        FROM temp_CGUSC.fp.indicador_controle_geografico C
        INNER JOIN #lote_atual L
            ON L.cnpj = C.cnpj;

        PRINT CONCAT('Erro no lote geografico ', @LoteAtual, ': ', @MensagemErroLote);
        SET @MsgLog = CONCAT('[GEO] ERRO lote ', @LoteAtual, ' | ', @MensagemErroLote);
        RAISERROR(@MsgLog, 0, 1) WITH NOWAIT;
        BREAK;
    END CATCH;

    PRINT CONCAT('Lote geografico ', @LoteAtual, ' encerrado. CNPJs concluidos no lote: ', @ContadorLote, '. Total concluido nesta execucao: ', @Contador, '.');

    IF EXISTS (
        SELECT 1
        FROM temp_CGUSC.fp.indicador_controle_geografico
        WHERE situacao = 3
          AND tentativas >= 3
    )
    BEGIN
        PRINT 'Existem CNPJs com erro e tentativas esgotadas. Encerrando processamento automatico antes da geracao final.';
        BREAK;
    END;
END;

IF @LoteAtual >= @MaxLotes
   AND EXISTS (
       SELECT 1
       FROM temp_CGUSC.fp.indicador_controle_geografico
       WHERE situacao IN (0, 3)
         AND tentativas < 3
   )
BEGIN
    RAISERROR('Limite de lotes atingido antes de concluir indicador_geografico. Aumente @MaxLotes ou investigue a fila.', 16, 1);
    RETURN;
END;


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
FROM temp_CGUSC.fp.indicador_controle_geografico
GROUP BY situacao
ORDER BY situacao;

DECLARE @Pendentes INT;
DECLARE @ErrosEsgotados INT;

SELECT @Pendentes = COUNT(*)
FROM temp_CGUSC.fp.indicador_controle_geografico
WHERE situacao IN (0, 1)
   OR (situacao = 3 AND tentativas < 3);

SELECT @ErrosEsgotados = COUNT(*)
FROM temp_CGUSC.fp.indicador_controle_geografico
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
    RAISERROR('Existem CNPJs com erro e tentativas esgotadas em indicador_controle_geografico. Corrija a causa antes de gerar a tabela final.', 16, 1);
    RETURN;
END
ELSE
BEGIN
    DECLARE @RegistrosFinal INT;

    PRINT '=======================================================================';
    PRINT 'TODOS OS CNPJs PROCESSADOS. Gerando tabela final...';
    PRINT '=======================================================================';

    -- Tabelas finais/derivadas antigas so sao substituidas apos conclusao integral.
    DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_geografico_mun;
    DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_geografico_detalhado;
    DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_geografico_origem_uf_detalhado;
    DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_geografico_regiao;
    DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_geografico_uf;
    DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_geografico_br;

    -- ========================================================================
    -- PASSO 5: TABELA CONSOLIDADA FINAL POR CNPJ/ANO
    -- ========================================================================
    SELECT
        I.id_cnpj,
        I.ano_base,
        I.total_vendas_monitoradas,
        I.qtd_vendas_outra_uf,
        CAST(I.valor_total_auditado AS DECIMAL(12,2)) AS valor_total_auditado,
        CAST(I.valor_vendas_outra_uf AS DECIMAL(12,2)) AS valor_vendas_outra_uf
    INTO temp_CGUSC.fp.indicador_geografico_detalhado
    FROM temp_CGUSC.fp.indicador_geografico I;

    SET @RegistrosFinal = @@ROWCOUNT;

    CREATE UNIQUE CLUSTERED INDEX IDX_FinalGeo_CNPJ
    ON temp_CGUSC.fp.indicador_geografico_detalhado(id_cnpj, ano_base);

    -- ========================================================================
    -- PASSO 6: DETALHAMENTO DE PACIENTES DE OUTRA UF POR UF DE ORIGEM
    -- ========================================================================
    IF EXISTS (
        SELECT 1
        FROM temp_CGUSC.fp.indicador_geografico_origem_uf
        WHERE total_pacientes_distintos_cnpj_ano <= 0
           OR total_pacientes_distintos_outra_uf <= 0
           OR qtd_pacientes_distintos_uf <= 0
           OR qtd_autorizacoes_uf <= 0
           OR valor_total_uf < 0
           OR valor_total_cnpj_ano <= 0
    )
    BEGIN
        RAISERROR('Tabela temp_CGUSC.fp.indicador_geografico_origem_uf possui denominadores ou componentes invalidos.', 16, 1);
        RETURN;
    END;

    SELECT
        O.id_cnpj,
        O.ano_base,
        O.uf_farmacia,
        O.uf_paciente,
        O.total_pacientes_distintos_cnpj_ano,
        O.total_pacientes_distintos_outra_uf,
        O.qtd_pacientes_distintos_uf,
        O.qtd_autorizacoes_uf,
        CAST(O.valor_total_uf AS DECIMAL(12,2)) AS valor_total_uf,
        CAST(O.valor_total_cnpj_ano AS DECIMAL(12,2)) AS valor_total_cnpj_ano,
        CAST(
            (CAST(O.qtd_pacientes_distintos_uf AS DECIMAL(19,6)) * 100.0)
            / CAST(O.total_pacientes_distintos_cnpj_ano AS DECIMAL(19,6))
        AS DECIMAL(9,4)) AS percentual_pacientes_sobre_total,
        CAST(
            (CAST(O.qtd_pacientes_distintos_uf AS DECIMAL(19,6)) * 100.0)
            / CAST(O.total_pacientes_distintos_outra_uf AS DECIMAL(19,6))
        AS DECIMAL(9,4)) AS percentual_pacientes_sobre_outra_uf,
        CAST(
            (CAST(O.valor_total_uf AS DECIMAL(19,6)) * 100.0)
            / CAST(O.valor_total_cnpj_ano AS DECIMAL(19,6))
        AS DECIMAL(9,4)) AS percentual_valor_sobre_total
    INTO temp_CGUSC.fp.indicador_geografico_origem_uf_detalhado
    FROM temp_CGUSC.fp.indicador_geografico_origem_uf O;

    CREATE UNIQUE CLUSTERED INDEX IDX_FinalGeoOrigemUF_CNPJ_Ano_UF
    ON temp_CGUSC.fp.indicador_geografico_origem_uf_detalhado(id_cnpj, ano_base, uf_paciente);

    CREATE NONCLUSTERED INDEX IDX_FinalGeoOrigemUF_UF
    ON temp_CGUSC.fp.indicador_geografico_origem_uf_detalhado(ano_base, uf_farmacia, uf_paciente);

    -- ========================================================================
    -- PASSO 7: AGREGADO POR REGIAO DE SAUDE/ANO
    -- ========================================================================
    SELECT
        I.ano_base,
        F.id_regiao_saude,
        SUM(I.total_vendas_monitoradas) AS total_vendas_monitoradas,
        SUM(I.qtd_vendas_outra_uf) AS qtd_vendas_outra_uf,
        CAST(SUM(I.valor_total_auditado) AS DECIMAL(19,2)) AS valor_total_auditado,
        CAST(SUM(I.valor_vendas_outra_uf) AS DECIMAL(19,2)) AS valor_vendas_outra_uf,
        CAST(COUNT_BIG(*) AS INT) AS qtd_cnpjs
    INTO temp_CGUSC.fp.indicador_geografico_regiao
    FROM temp_CGUSC.fp.indicador_geografico I
    INNER JOIN #farmacias_dim F
        ON F.id_cnpj = I.id_cnpj
    GROUP BY
        I.ano_base,
        F.id_regiao_saude;

    CREATE UNIQUE CLUSTERED INDEX IDX_IndGeoReg
    ON temp_CGUSC.fp.indicador_geografico_regiao(ano_base, id_regiao_saude);

    -- ========================================================================
    -- PASSO 8: AGREGADO POR UF/ANO
    -- ========================================================================
    SELECT
        I.ano_base,
        F.uf,
        SUM(I.total_vendas_monitoradas) AS total_vendas_monitoradas,
        SUM(I.qtd_vendas_outra_uf) AS qtd_vendas_outra_uf,
        CAST(SUM(I.valor_total_auditado) AS DECIMAL(19,2)) AS valor_total_auditado,
        CAST(SUM(I.valor_vendas_outra_uf) AS DECIMAL(19,2)) AS valor_vendas_outra_uf,
        CAST(COUNT_BIG(*) AS INT) AS qtd_cnpjs
    INTO temp_CGUSC.fp.indicador_geografico_uf
    FROM temp_CGUSC.fp.indicador_geografico I
    INNER JOIN #farmacias_dim F
        ON F.id_cnpj = I.id_cnpj
    GROUP BY
        I.ano_base,
        F.uf;

    CREATE UNIQUE CLUSTERED INDEX IDX_IndGeoUF
    ON temp_CGUSC.fp.indicador_geografico_uf(ano_base, uf);

    -- ========================================================================
    -- PASSO 9: AGREGADO BRASIL/ANO
    -- ========================================================================
    SELECT
        I.ano_base,
        SUM(I.total_vendas_monitoradas) AS total_vendas_monitoradas,
        SUM(I.qtd_vendas_outra_uf) AS qtd_vendas_outra_uf,
        CAST(SUM(I.valor_total_auditado) AS DECIMAL(19,2)) AS valor_total_auditado,
        CAST(SUM(I.valor_vendas_outra_uf) AS DECIMAL(19,2)) AS valor_vendas_outra_uf,
        CAST(COUNT_BIG(*) AS INT) AS qtd_cnpjs
    INTO temp_CGUSC.fp.indicador_geografico_br
    FROM temp_CGUSC.fp.indicador_geografico I
    GROUP BY
        I.ano_base;

    CREATE UNIQUE CLUSTERED INDEX IDX_IndGeoBR
    ON temp_CGUSC.fp.indicador_geografico_br(ano_base);

    PRINT CONCAT('Tabela final criada com ', @RegistrosFinal, ' registros.');
END;

DROP TABLE IF EXISTS #medicamentos_patologia_gtin;
DROP TABLE IF EXISTS #farmacias_dim;
GO
