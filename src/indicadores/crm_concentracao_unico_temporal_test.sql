-- ============================================================================
-- DETECÇÃO DE CONCENTRAÇÃO TEMPORAL — CRM ÚNICO (Sliding Window)
-- ============================================================================
-- Versão focada em rajadas de UM único médico, com precisão de minuto.
-- Diferença do script multi-CRM: o self-join filtra B.crm = A.crm,
-- isolando a janela sliding exclusivamente para as transações do mesmo médico.
-- Isso elimina a "contaminação" por prescrições de outros CRMs na mesma hora.
--
-- Severidades: ALTO → GRAVE → CRÍTICO → EXTREMO
--
-- ── CRM ÚNICO (1 prescritor, janela intra-médico) ───────────────────────────
--   EXTREMO →  7 auth em  5 min (1,4/min)
--   EXTREMO → 10 auth em 10 min (1,0/min)
--   CRÍTICO →  6 auth em  5 min (1,2/min)
--   CRÍTICO →  8 auth em 10 min (0,8/min)
--   GRAVE   →  8 auth em 15 min (0,5/min)
--   GRAVE   →  9 auth em 20 min (0,5/min)
--   ALTO    →  7 auth em 30 min (0,2/min)
--   ALTO    → 10 auth em 60 min (0,2/min)
--   ALTO    →  5 auth em 25 min (taxa ≥ 12/hr, janela fixa)
--   ALTO    →  N auth, taxa ≥ 12/hr p/ N > 5 (ex: 8 em 40 min)
--
-- ── PROCESSAMENTO ───────────────────────────────────────────────────────────
--   Lotes de 20 CNPJs com checkpoint por CNPJ.
--   Reiniciar o script retoma de onde parou (CNPJs OK são pulados).
-- ============================================================================

-- Batch separado: dropa tabelas existentes ANTES de compilar o restante do script.
-- SQL Server valida colunas de tabelas persistentes em compile-time; o GO força
-- recompilação da próxima batch com as tabelas ausentes.
DROP TABLE IF EXISTS temp_CGUSC.fp.crm_concentracao_unico_alertas;
DROP TABLE IF EXISTS temp_CGUSC.fp.crm_concentracao_unico_controle;
GO

DECLARE @DataInicio  DATE     = '2015-07-01';
DECLARE @DataFim     DATE     = '2024-12-31';
DECLARE @lote_size   INT      = 20;
DECLARE @t0          DATETIME = GETDATE();
DECLARE @t1          DATETIME;

DECLARE @lote_num           INT = 0;
DECLARE @nu_processados     INT = 0;
DECLARE @nu_alertas_lote    INT = 0;
DECLARE @nu_alertas_total   INT = 0;
DECLARE @nu_pendentes       INT;
DECLARE @nu_ja_processados  INT;
DECLARE @nu_total           INT;

PRINT '>> [CRM ÚNICO] Iniciando detecção de concentração temporal por médico...';
PRINT '   Período: ' + CAST(@DataInicio AS VARCHAR(10)) + ' → ' + CAST(@DataFim AS VARCHAR(10));
PRINT '   Lote: ' + CAST(@lote_size AS VARCHAR) + ' CNPJs por iteração';


-- ============================================================================
-- PASSO 0: Criar tabelas persistentes se não existirem
-- ============================================================================
PRINT '>> Passo 0: Inicializando tabelas persistentes...';

IF OBJECT_ID('temp_CGUSC.fp.crm_concentracao_unico_controle') IS NULL
    CREATE TABLE temp_CGUSC.fp.crm_concentracao_unico_controle (
        id_cnpj    INT         NOT NULL,
        dt_inicio  DATETIME    NOT NULL,
        dt_fim     DATETIME    NULL,
        nu_alertas INT         NULL,
        status     VARCHAR(12) NOT NULL,
        CONSTRAINT PK_ConcentracaoUnicoControle PRIMARY KEY CLUSTERED (id_cnpj)
    );

IF OBJECT_ID('temp_CGUSC.fp.crm_concentracao_unico_alertas') IS NULL
BEGIN
    CREATE TABLE temp_CGUSC.fp.crm_concentracao_unico_alertas (
        id_cnpj             INT             NOT NULL,
        id_medico_int       INT             NOT NULL,
        dt_dia              DATE            NOT NULL,
        dt_ini_concentracao SMALLDATETIME   NOT NULL,
        dt_fim_concentracao SMALLDATETIME   NOT NULL,
        nu_minutos_span     TINYINT         NOT NULL,
        nu_5min             SMALLINT        NOT NULL,
        nu_10min            SMALLINT        NOT NULL,
        nu_15min            SMALLINT        NOT NULL,
        nu_20min            SMALLINT        NOT NULL,
        nu_25min            SMALLINT        NOT NULL,
        nu_30min            SMALLINT        NOT NULL,
        nu_60min            SMALLINT        NOT NULL,
        severidade          VARCHAR(10)     NOT NULL
    );
    CREATE CLUSTERED INDEX IDX_ConcentracaoUnicoAlertas
        ON temp_CGUSC.fp.crm_concentracao_unico_alertas(id_cnpj, id_medico_int, dt_dia);
END


-- ============================================================================
-- PASSO 1: Limpar CNPJs interrompidos para reprocessar do zero
-- ============================================================================
PRINT '>> Passo 1: Limpando CNPJs interrompidos (status PROCESSANDO)...';

DELETE alerta
FROM temp_CGUSC.fp.crm_concentracao_unico_alertas alerta
INNER JOIN temp_CGUSC.fp.crm_concentracao_unico_controle ctrl
    ON ctrl.id_cnpj = alerta.id_cnpj
WHERE ctrl.status = 'PROCESSANDO';

DELETE FROM temp_CGUSC.fp.crm_concentracao_unico_controle
WHERE status = 'PROCESSANDO';

PRINT '   Limpeza concluída.';


-- ============================================================================
-- PASSO 2: Construir fila de CNPJs pendentes
-- ============================================================================
PRINT '>> Passo 2: Construindo fila de CNPJs pendentes...';
SET @t1 = GETDATE();

DROP TABLE IF EXISTS #cnpjs_pendentes;

SELECT DISTINCT F.id AS id_cnpj, A.cnpj
INTO #cnpjs_pendentes
FROM temp_CGUSC.fp.teste_mov_SC A
INNER JOIN temp_CGUSC.fp.medicamentos_patologia PA ON PA.codigo_barra = A.codigo_barra
INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = A.cnpj
WHERE A.crm    IS NOT NULL
  AND A.crm_uf IS NOT NULL
  AND A.crm_uf <> 'BR'
  AND A.data_hora >= @DataInicio
  AND A.data_hora < DATEADD(DAY, 1, @DataFim)
  AND F.id NOT IN (
      SELECT id_cnpj FROM temp_CGUSC.fp.crm_concentracao_unico_controle WHERE status = 'OK'
  );

SET @nu_pendentes      = (SELECT COUNT(*) FROM #cnpjs_pendentes);
SET @nu_ja_processados = (SELECT COUNT(*) FROM temp_CGUSC.fp.crm_concentracao_unico_controle WHERE status = 'OK');
SET @nu_total          = @nu_pendentes + @nu_ja_processados;

PRINT '   CNPJs já processados: ' + CAST(@nu_ja_processados AS VARCHAR) + ' / ' + CAST(@nu_total AS VARCHAR);
PRINT '   CNPJs pendentes:      ' + CAST(@nu_pendentes AS VARCHAR);
PRINT '   Passo 2 concluído em: ' + CONVERT(VARCHAR(20), GETDATE() - @t1, 114);

IF @nu_pendentes = 0
BEGIN
    PRINT '   Nada a processar — base já completa.';
    GOTO Resultados;
END

PRINT '>> Passo 3: Iniciando loop de lotes...';


-- ============================================================================
-- PASSO 3: Loop contínuo por lotes de @lote_size CNPJs
-- ============================================================================
WHILE EXISTS (SELECT 1 FROM #cnpjs_pendentes)
BEGIN
    SET @lote_num += 1;
    SET @t1 = GETDATE();

    -- ── Pegar próximo lote da fila ────────────────────────────────────────
    DROP TABLE IF EXISTS #lote_atual;

    SELECT TOP (@lote_size) id_cnpj, cnpj
    INTO #lote_atual
    FROM #cnpjs_pendentes
    ORDER BY id_cnpj;

    -- ── Marcar lote como PROCESSANDO ─────────────────────────────────────
    INSERT INTO temp_CGUSC.fp.crm_concentracao_unico_controle (id_cnpj, dt_inicio, status)
    SELECT id_cnpj, GETDATE(), 'PROCESSANDO'
    FROM #lote_atual;

    -- ── Passo 3.A: Criar base pré-filtrada por patologia para o lote ──────
    -- Isso reduz o volume de dados e remove a necessidade de joins repetidos
    -- com a tabela de medicamentos dentro do sliding window.
    -- Isso colapsa múltiplos itens de uma mesma autorização no mesmo instante.
    DROP TABLE IF EXISTS #base_lote;

    SELECT 
        L.id_cnpj,
        A.cnpj,
        M.id AS id_medico_int,
        A.crm,
        A.crm_uf,
        A.data_hora,
        A.num_autorizacao
    INTO #base_lote
    FROM temp_CGUSC.fp.teste_mov_SC A
    INNER JOIN temp_CGUSC.fp.medicamentos_patologia PA ON PA.codigo_barra = A.codigo_barra
    INNER JOIN #lote_atual L ON L.cnpj = A.cnpj
    LEFT JOIN temp_CGUSC.fp.dados_medico M 
        ON M.id_medico = CAST(CAST(A.crm AS VARCHAR(10)) + '/' + A.crm_uf AS VARCHAR(20))
    WHERE A.crm IS NOT NULL AND A.crm_uf IS NOT NULL AND A.crm_uf <> 'BR'
      AND A.data_hora >= @DataInicio AND A.data_hora < DATEADD(DAY, 1, @DataFim)
    GROUP BY L.id_cnpj, A.cnpj, M.id, A.crm, A.crm_uf, A.data_hora, A.num_autorizacao;

    CREATE INDEX IDX_BaseLote ON #base_lote(id_cnpj, id_medico_int, data_hora);


    -- ── Passo 3.B: Concentração sobre a base reduzida ────────────────────
    DROP TABLE IF EXISTS #concentracao_raw;

    -- Usamos uma subconsulta para calcular as agregações uma única vez, 
    -- evitando o custo dobrado de repetir os COUNT(DISTINCT) no HAVING.
    SELECT *
    INTO #concentracao_raw
    FROM (
        SELECT
            A.id_cnpj,
            A.id_medico_int,
            A.data_hora                                                     AS janela_inicio,

            COUNT(DISTINCT CASE WHEN B.data_hora <= DATEADD(SECOND, 359, A.data_hora)
                                THEN B.num_autorizacao END)                 AS nu_5min,
            COUNT(DISTINCT CASE WHEN B.data_hora <= DATEADD(MINUTE, 10, A.data_hora)
                                THEN B.num_autorizacao END)                 AS nu_10min,
            COUNT(DISTINCT CASE WHEN B.data_hora <= DATEADD(MINUTE, 15, A.data_hora)
                                THEN B.num_autorizacao END)                 AS nu_15min,
            COUNT(DISTINCT CASE WHEN B.data_hora <= DATEADD(MINUTE, 20, A.data_hora)
                                THEN B.num_autorizacao END)                 AS nu_20min,
            COUNT(DISTINCT CASE WHEN B.data_hora <= DATEADD(MINUTE, 25, A.data_hora)
                                THEN B.num_autorizacao END)                 AS nu_25min,
            COUNT(DISTINCT CASE WHEN B.data_hora <= DATEADD(MINUTE, 30, A.data_hora)
                                THEN B.num_autorizacao END)                 AS nu_30min,
            COUNT(DISTINCT CASE WHEN B.data_hora <= DATEADD(MINUTE, 60, A.data_hora)
                                THEN B.num_autorizacao END)                 AS nu_60min,

            -- Timestamps de fim real para cada sub-janela
            MAX(CASE WHEN B.data_hora <= DATEADD(SECOND, 359, A.data_hora) THEN B.data_hora END) AS fim_real_5min,
            MAX(CASE WHEN B.data_hora <= DATEADD(MINUTE, 10, A.data_hora) THEN B.data_hora END) AS fim_real_10min,
            MAX(CASE WHEN B.data_hora <= DATEADD(MINUTE, 15, A.data_hora) THEN B.data_hora END) AS fim_real_15min,
            MAX(CASE WHEN B.data_hora <= DATEADD(MINUTE, 20, A.data_hora) THEN B.data_hora END) AS fim_real_20min,
            MAX(CASE WHEN B.data_hora <= DATEADD(MINUTE, 25, A.data_hora) THEN B.data_hora END) AS fim_real_25min,
            MAX(CASE WHEN B.data_hora <= DATEADD(MINUTE, 30, A.data_hora) THEN B.data_hora END) AS fim_real_30min,
            MAX(CASE WHEN B.data_hora <= DATEADD(MINUTE, 60, A.data_hora) THEN B.data_hora END) AS fim_real_60min,

            DATEDIFF(MINUTE, MIN(B.data_hora), MAX(B.data_hora))            AS nu_minutos_span_full

        FROM #base_lote A
        INNER JOIN #base_lote B
            ON  B.id_cnpj       = A.id_cnpj
            AND B.id_medico_int = A.id_medico_int
            AND B.data_hora BETWEEN A.data_hora AND DATEADD(MINUTE, 60, A.data_hora)
        GROUP BY A.id_cnpj, A.id_medico_int, A.data_hora
    ) Agg
    WHERE nu_5min >= 6 
       OR nu_10min >= 8 
       OR nu_15min >= 8 
       OR nu_20min >= 9 
       OR nu_25min >= 5 
       OR nu_30min >= 7 
       OR nu_60min >= 10
       OR (nu_60min >= 5 AND nu_minutos_span_full <= nu_60min * 5);

    -- ── Deduplicação: 1 evento por (cnpj, médico, hora) ──────────────────
    -- PARTITION BY inclui id_medico: dois médicos diferentes no mesmo CNPJ/hora
    -- geram eventos independentes (não se cancelam).
    DROP TABLE IF EXISTS #concentracao_dedup;

    SELECT
        id_cnpj,
        id_medico_int,
        janela_inicio,
        nu_5min, nu_10min, nu_15min, nu_20min, nu_25min, nu_30min, nu_60min,
        fim_real_5min, fim_real_10min, fim_real_15min, fim_real_20min, 
        fim_real_25min, fim_real_30min, fim_real_60min,
        nu_minutos_span_full,
        ROW_NUMBER() OVER (
            PARTITION BY
                id_cnpj,
                id_medico_int,
                CAST(janela_inicio AS DATE),
                DATEDIFF(MINUTE, 0, janela_inicio) / 60
            ORDER BY
                CASE
                    WHEN nu_5min  >=  7 THEN 1
                    WHEN nu_10min >= 10 THEN 1
                    WHEN nu_5min  >=  6 THEN 2
                    WHEN nu_10min >=  8 THEN 2
                    WHEN nu_15min >=  8 THEN 3
                    WHEN nu_20min >=  9 THEN 3
                    WHEN nu_30min >=  7 THEN 4
                    WHEN nu_60min >= 10 THEN 4
                    WHEN nu_25min >=  5 THEN 4
                    WHEN nu_60min >=  5 AND nu_minutos_span_full <= nu_60min * 5 THEN 4
                    ELSE 99
                END ASC,
                nu_60min DESC,
                nu_30min DESC,
                nu_25min DESC,
                nu_20min DESC,
                nu_15min DESC,
                nu_10min DESC,
                nu_5min DESC,
                janela_inicio ASC
        ) AS rn
    INTO #concentracao_dedup
    FROM #concentracao_raw;

    -- ── INSERT incremental nos alertas ────────────────────────────────────
    INSERT INTO temp_CGUSC.fp.crm_concentracao_unico_alertas
        (id_cnpj, id_medico_int, dt_dia, dt_ini_concentracao, dt_fim_concentracao, nu_minutos_span,
         nu_5min, nu_10min, nu_15min, nu_20min, nu_25min, nu_30min, nu_60min, severidade)
    SELECT id_cnpj, id_medico_int, dt_dia, dt_ini_concentracao, dt_fim_concentracao, nu_minutos_span,
           nu_5min, nu_10min, nu_15min, nu_20min, nu_25min, nu_30min, nu_60min, severidade
    FROM (
        SELECT
            id_cnpj,
            id_medico_int,
            CAST(janela_inicio AS DATE)                                 AS dt_dia,
            CAST(janela_inicio AS SMALLDATETIME)                        AS dt_ini_concentracao,
            CAST(dt_fim_real AS SMALLDATETIME)                          AS dt_fim_concentracao,
            CAST(DATEDIFF(MINUTE, janela_inicio, dt_fim_real) AS TINYINT) AS nu_minutos_span,
            CAST(nu_5min AS SMALLINT)                                   AS nu_5min,
            CAST(nu_10min AS SMALLINT)                                  AS nu_10min,
            CAST(nu_15min AS SMALLINT)                                  AS nu_15min,
            CAST(nu_20min AS SMALLINT)                                  AS nu_20min,
            CAST(nu_25min AS SMALLINT)                                  AS nu_25min,
            CAST(nu_30min AS SMALLINT)                                  AS nu_30min,
            CAST(nu_60min AS SMALLINT)                                  AS nu_60min,
            severidade
        FROM (
            SELECT
                *,
                CASE
                    WHEN nu_5min  >=  7 THEN fim_real_5min
                    WHEN nu_10min >= 10 THEN fim_real_10min
                    WHEN nu_5min  >=  6 THEN fim_real_5min
                    WHEN nu_10min >=  8 THEN fim_real_10min
                    WHEN nu_15min >=  8 THEN fim_real_15min
                    WHEN nu_20min >=  9 THEN fim_real_20min
                    WHEN nu_30min >=  7 THEN fim_real_30min
                    WHEN nu_60min >= 10 THEN fim_real_60min
                    WHEN nu_25min >=  5 THEN fim_real_25min
                    WHEN nu_60min >=  5 AND nu_minutos_span_full <= nu_60min * 5 THEN fim_real_60min
                END AS dt_fim_real,
                CASE
                    WHEN nu_5min  >=  7 THEN 'EXTREMO'
                    WHEN nu_10min >= 10 THEN 'EXTREMO'
                    WHEN nu_5min  >=  6 THEN 'CRÍTICO'
                    WHEN nu_10min >=  8 THEN 'CRÍTICO'
                    WHEN nu_15min >=  8 THEN 'GRAVE'
                    WHEN nu_20min >=  9 THEN 'GRAVE'
                    WHEN nu_30min >=  7 THEN 'ALTO'
                    WHEN nu_60min >= 10 THEN 'ALTO'
                    WHEN nu_25min >=  5 THEN 'ALTO'
                    WHEN nu_60min >=  5 AND nu_minutos_span_full <= nu_60min * 5 THEN 'ALTO'
                END AS severidade
            FROM #concentracao_dedup
            WHERE rn = 1
        ) sub
    ) sub
    WHERE severidade IS NOT NULL;

    SET @nu_alertas_lote  = @@ROWCOUNT;
    SET @nu_alertas_total += @nu_alertas_lote;

    -- ── Marcar lote como OK com contagem de alertas por CNPJ ─────────────
    UPDATE ctrl
    SET status     = 'OK',
        dt_fim     = GETDATE(),
        nu_alertas = ISNULL((
            SELECT COUNT(*)
            FROM temp_CGUSC.fp.crm_concentracao_unico_alertas a
            WHERE a.id_cnpj = ctrl.id_cnpj
        ), 0)
    FROM temp_CGUSC.fp.crm_concentracao_unico_controle ctrl
    WHERE ctrl.id_cnpj IN (SELECT id_cnpj FROM #lote_atual);

    -- ── Remover lote da fila e atualizar contadores ───────────────────────
    DELETE FROM #cnpjs_pendentes WHERE id_cnpj IN (SELECT id_cnpj FROM #lote_atual);

    SET @nu_processados += (SELECT COUNT(*) FROM #lote_atual);

    PRINT '   Lote ' + RIGHT('0000' + CAST(@lote_num AS VARCHAR), 4) +
          ' | ' + CAST(@nu_ja_processados + @nu_processados AS VARCHAR) + '/' + CAST(@nu_total AS VARCHAR) + ' CNPJs' +
          ' | Alertas lote: ' + CAST(@nu_alertas_lote AS VARCHAR) +
          ' | Total alertas: ' + CAST(@nu_alertas_total AS VARCHAR) +
          ' | ' + CONVERT(VARCHAR(20), GETDATE() - @t1, 114);
END


-- ============================================================================
-- RESULTADOS
-- ============================================================================
Resultados:
PRINT '==========================================================';
PRINT '   TEMPO TOTAL:   ' + CONVERT(VARCHAR(20), GETDATE() - @t0, 114);
PRINT '   TOTAL ALERTAS: ' + CAST(@nu_alertas_total AS VARCHAR);
PRINT '==========================================================';

-- Distribuição por severidade
SELECT
    severidade,
    COUNT(*)                        AS qtd_alertas,
    COUNT(DISTINCT id_cnpj)         AS qtd_cnpjs,
    COUNT(DISTINCT id_medico_int)   AS qtd_medicos,
    AVG(nu_minutos_span)            AS media_minutos_span,
    AVG(nu_60min)                   AS media_rx_60min,
    MIN(dt_ini_concentracao)        AS primeiro_alerta,
    MAX(dt_ini_concentracao)        AS ultimo_alerta
FROM temp_CGUSC.fp.crm_concentracao_unico_alertas
GROUP BY severidade
ORDER BY
    CASE severidade WHEN 'EXTREMO' THEN 1 WHEN 'CRÍTICO' THEN 2 WHEN 'GRAVE' THEN 3 ELSE 4 END;

-- Top 30 piores casos
SELECT TOP 30
    id_cnpj,
    id_medico_int,
    dt_dia,
    dt_ini_concentracao,
    dt_fim_concentracao,
    nu_minutos_span,
    nu_5min,
    nu_10min,
    nu_15min,
    nu_20min,
    nu_25min,
    nu_30min,
    nu_60min,
    severidade
FROM temp_CGUSC.fp.crm_concentracao_unico_alertas
ORDER BY
    CASE severidade WHEN 'EXTREMO' THEN 1 WHEN 'CRÍTICO' THEN 2 WHEN 'GRAVE' THEN 3 ELSE 4 END ASC,
    nu_60min DESC;
