-- ============================================================================
-- DETECÇÃO DE CONCENTRAÇÃO TEMPORAL DE AUTORIZAÇÕES via Sliding Window
-- ============================================================================
-- Severidades: ALTO → GRAVE → CRÍTICO → EXTREMO
--
-- ── MULTI-CRM (nu_crms_distintos >= 2) ─────────────────────────────────────
--   EXTREMO →  8 auth em  5 min (1,6/min)
--   EXTREMO → 11 auth em 10 min (1,1/min)
--   CRÍTICO →  6 auth em  5 min (1,2/min)
--   CRÍTICO →  8 auth em 10 min (0,8/min)
--   GRAVE   → 10 auth em 15 min (0,7/min)
--   GRAVE   → 11 auth em 20 min (0,6/min)
--   ALTO    → 12 auth em 30 min (0,4/min)
--   ALTO    → 18 auth em 60 min (0,3/min)
--   ALTO    →  N auth, taxa ≥ 20/hr p/ N > 5 (ex: 7 em 20 min)
--
-- ── PROCESSAMENTO ───────────────────────────────────────────────────────────
--   Lotes de 20 CNPJs com checkpoint por CNPJ.
--   Reiniciar o script retoma de onde parou (CNPJs OK são pulados).
-- ============================================================================

-- Batch separado: dropa tabelas existentes ANTES de compilar o restante do script.
-- SQL Server valida colunas de tabelas persistentes em compile-time; se a tabela
-- existir sem id_medico_unico, o INSERT lançará Msg 207. O GO força recompilação
-- da próxima batch com as tabelas já ausentes, adiando a validação para runtime.
DROP TABLE IF EXISTS temp_CGUSC.fp.crm_concentracao_multiplo_alertas;
DROP TABLE IF EXISTS temp_CGUSC.fp.crm_concentracao_multiplo_controle;
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

PRINT '>> [CONCENTRACAO] Iniciando detecção de concentração temporal...';
PRINT '   Período: ' + CAST(@DataInicio AS VARCHAR(10)) + ' → ' + CAST(@DataFim AS VARCHAR(10));
PRINT '   Lote: ' + CAST(@lote_size AS VARCHAR) + ' CNPJs por iteração';


-- ============================================================================
-- PASSO 0: Criar tabelas persistentes se não existirem
-- ============================================================================
PRINT '>> Passo 0: Inicializando tabelas persistentes...';

IF OBJECT_ID('temp_CGUSC.fp.crm_concentracao_multiplo_controle') IS NULL
    CREATE TABLE temp_CGUSC.fp.crm_concentracao_multiplo_controle (
        id_cnpj    INT         NOT NULL,
        dt_inicio  DATETIME    NOT NULL,
        dt_fim     DATETIME    NULL,
        nu_alertas INT         NULL,
        status     VARCHAR(12) NOT NULL,
        CONSTRAINT PK_ConcentracaoMultiploControle PRIMARY KEY CLUSTERED (id_cnpj)
    );

IF OBJECT_ID('temp_CGUSC.fp.crm_concentracao_multiplo_alertas') IS NULL
BEGIN
    CREATE TABLE temp_CGUSC.fp.crm_concentracao_multiplo_alertas (
        id_cnpj             INT         NOT NULL,
        dt_dia              DATE        NOT NULL,
        dt_ini_concentracao DATETIME    NOT NULL,
        dt_fim_concentracao DATETIME    NOT NULL,
        nu_minutos_span     INT         NOT NULL,
        nu_crms_distintos   INT         NOT NULL,
        id_medico_unico     VARCHAR(20) NULL,
        nu_5min             INT         NOT NULL,
        nu_10min            INT         NOT NULL,
        nu_15min            INT         NOT NULL,
        nu_20min            INT         NOT NULL,
        nu_30min            INT         NOT NULL,
        nu_60min            INT         NOT NULL,
        severidade          VARCHAR(10) NOT NULL
    );
    CREATE CLUSTERED INDEX IDX_ConcentracaoMultiploAlertas
        ON temp_CGUSC.fp.crm_concentracao_multiplo_alertas(id_cnpj, dt_dia);
END


-- ============================================================================
-- PASSO 1: Limpar CNPJs interrompidos para reprocessar do zero
-- ============================================================================
PRINT '>> Passo 1: Limpando CNPJs interrompidos (status PROCESSANDO)...';

DELETE alerta
FROM temp_CGUSC.fp.crm_concentracao_multiplo_alertas alerta
INNER JOIN temp_CGUSC.fp.crm_concentracao_multiplo_controle ctrl
    ON ctrl.id_cnpj = alerta.id_cnpj
WHERE ctrl.status = 'PROCESSANDO';

DELETE FROM temp_CGUSC.fp.crm_concentracao_multiplo_controle
WHERE status = 'PROCESSANDO';

PRINT '   Limpeza concluída.';


-- ============================================================================
-- PASSO 2: Construir fila de CNPJs pendentes
-- ============================================================================
PRINT '>> Passo 2: Construindo fila de CNPJs pendentes...';
SET @t1 = GETDATE();

DROP TABLE IF EXISTS #cnpjs_pendentes;

SELECT DISTINCT F.id AS id_cnpj
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
      SELECT id_cnpj FROM temp_CGUSC.fp.crm_concentracao_multiplo_controle WHERE status = 'OK'
  );

SET @nu_pendentes      = (SELECT COUNT(*) FROM #cnpjs_pendentes);
SET @nu_ja_processados = (SELECT COUNT(*) FROM temp_CGUSC.fp.crm_concentracao_multiplo_controle WHERE status = 'OK');
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

    SELECT TOP (@lote_size) id_cnpj
    INTO #lote_atual
    FROM #cnpjs_pendentes
    ORDER BY id_cnpj;

    -- ── Marcar lote como PROCESSANDO ─────────────────────────────────────
    INSERT INTO temp_CGUSC.fp.crm_concentracao_multiplo_controle (id_cnpj, dt_inicio, status)
    SELECT id_cnpj, GETDATE(), 'PROCESSANDO'
    FROM #lote_atual;

    -- ── Passo 3.A: Criar base pré-filtrada por patologia para o lote ──────
    -- Isso reduz drasticamente o volume de dados para o self-join sliding window.
    SELECT 
        L.id_cnpj,
        A.data_hora,
        A.num_autorizacao,
        CAST(CAST(A.crm AS VARCHAR(10)) + '/' + A.crm_uf AS VARCHAR(20)) AS id_medico
    INTO #base_lote
    FROM temp_CGUSC.fp.teste_mov_SC A
    INNER JOIN temp_CGUSC.fp.medicamentos_patologia PA ON PA.codigo_barra = A.codigo_barra
    INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = A.cnpj
    INNER JOIN #lote_atual L ON L.id_cnpj = F.id
    WHERE A.crm    IS NOT NULL AND A.crm_uf    IS NOT NULL AND A.crm_uf    <> 'BR'
      AND A.data_hora >= @DataInicio AND A.data_hora < DATEADD(DAY, 1, @DataFim)
    GROUP BY L.id_cnpj, A.data_hora, A.num_autorizacao, A.crm, A.crm_uf;

    CREATE INDEX IDX_BaseLote ON #base_lote(id_cnpj, data_hora);


    -- ── Passo 3.B: Self-join com janela máxima de 60 minutos ─────────────────────────
    -- Usamos uma subconsulta para calcular as agregações uma única vez, 
    -- evitando o custo dobrado de repetir os COUNT(DISTINCT) no HAVING.
    SELECT *
    INTO #concentracao_raw
    FROM (
        SELECT
            A.id_cnpj,
            A.data_hora                                                               AS janela_inicio,

            COUNT(DISTINCT CASE WHEN B.data_hora <= DATEADD(SECOND, 359, A.data_hora)
                                THEN B.num_autorizacao END)                           AS nu_5min,
            COUNT(DISTINCT CASE WHEN B.data_hora <= DATEADD(MINUTE, 10, A.data_hora)
                                THEN B.num_autorizacao END)                           AS nu_10min,
            COUNT(DISTINCT CASE WHEN B.data_hora <= DATEADD(MINUTE, 15, A.data_hora)
                                THEN B.num_autorizacao END)                           AS nu_15min,
            COUNT(DISTINCT CASE WHEN B.data_hora <= DATEADD(MINUTE, 20, A.data_hora)
                                THEN B.num_autorizacao END)                           AS nu_20min,
            COUNT(DISTINCT CASE WHEN B.data_hora <= DATEADD(MINUTE, 30, A.data_hora)
                                THEN B.num_autorizacao END)                           AS nu_30min,
            COUNT(DISTINCT CASE WHEN B.data_hora <= DATEADD(MINUTE, 60, A.data_hora)
                                THEN B.num_autorizacao END)                           AS nu_60min,

            COUNT(DISTINCT B.id_medico)                                               AS nu_crms_distintos,
            CASE WHEN COUNT(DISTINCT B.id_medico) = 1
                 THEN MIN(B.id_medico)
                 END                                                                   AS id_medico_unico,

            -- Timestamps de fim real para cada sub-janela
            MAX(CASE WHEN B.data_hora <= DATEADD(SECOND, 359, A.data_hora) THEN B.data_hora END) AS fim_real_5min,
            MAX(CASE WHEN B.data_hora <= DATEADD(MINUTE, 10, A.data_hora) THEN B.data_hora END) AS fim_real_10min,
            MAX(CASE WHEN B.data_hora <= DATEADD(MINUTE, 15, A.data_hora) THEN B.data_hora END) AS fim_real_15min,
            MAX(CASE WHEN B.data_hora <= DATEADD(MINUTE, 20, A.data_hora) THEN B.data_hora END) AS fim_real_20min,
            MAX(CASE WHEN B.data_hora <= DATEADD(MINUTE, 30, A.data_hora) THEN B.data_hora END) AS fim_real_30min,
            MAX(CASE WHEN B.data_hora <= DATEADD(MINUTE, 60, A.data_hora) THEN B.data_hora END) AS fim_real_60min,

            DATEDIFF(MINUTE, MIN(B.data_hora), MAX(B.data_hora))                     AS nu_minutos_span_full

        FROM #base_lote A
        INNER JOIN #base_lote B
            ON  B.id_cnpj   = A.id_cnpj
            AND B.data_hora BETWEEN A.data_hora AND DATEADD(MINUTE, 60, A.data_hora)
        GROUP BY A.id_cnpj, A.data_hora
    ) Agg
    WHERE nu_crms_distintos >= 2
    AND (
           nu_5min  >=  6
        OR nu_10min >=  8
        OR nu_15min >= 10
        OR nu_20min >= 11
        OR nu_30min >= 12
        OR nu_60min >= 18
        OR (nu_60min >= 6 AND nu_minutos_span_full <= nu_60min * 3)
    );

    -- ── Deduplicação: 1 evento por janela de 60 min por cnpj/hora ─────────
    DROP TABLE IF EXISTS #concentracao_dedup;

    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY
                id_cnpj,
                CAST(janela_inicio AS DATE),
                DATEDIFF(MINUTE, 0, janela_inicio) / 60
            ORDER BY
                CASE
                    WHEN nu_5min  >=  8 THEN 1
                    WHEN nu_10min >= 11 THEN 1
                    WHEN nu_5min  >=  6 THEN 2
                    WHEN nu_10min >=  8 THEN 2
                    WHEN nu_15min >= 10 THEN 3
                    WHEN nu_20min >= 11 THEN 3
                    WHEN nu_30min >= 12 THEN 4
                    WHEN nu_60min >= 18 THEN 4
                    WHEN nu_60min >=  6 AND nu_minutos_span_full <= nu_60min * 3 THEN 4
                    ELSE 99
                END ASC,
                nu_60min DESC,
                nu_30min DESC,
                nu_20min DESC,
                nu_15min DESC,
                nu_10min DESC,
                nu_5min DESC,
                nu_crms_distintos DESC,
                janela_inicio ASC
        ) AS rn
    INTO #concentracao_dedup
    FROM #concentracao_raw;

    -- ── INSERT incremental nos alertas ────────────────────────────────────
    INSERT INTO temp_CGUSC.fp.crm_concentracao_multiplo_alertas
        (id_cnpj, dt_dia, dt_ini_concentracao, dt_fim_concentracao, nu_minutos_span,
         nu_crms_distintos, id_medico_unico, nu_5min, nu_10min, nu_15min, nu_20min, nu_30min, nu_60min, severidade)
    SELECT id_cnpj, dt_dia, dt_ini_concentracao, dt_fim_concentracao, nu_minutos_span,
           nu_crms_distintos, id_medico_unico, nu_5min, nu_10min, nu_15min, nu_20min, nu_30min, nu_60min, severidade
    FROM (
        SELECT
            id_cnpj,
            CAST(janela_inicio AS DATE)                                    AS dt_dia,
            janela_inicio                                                  AS dt_ini_concentracao,
            dt_fim_real                                                    AS dt_fim_concentracao,
            DATEDIFF(MINUTE, janela_inicio, dt_fim_real)                   AS nu_minutos_span,
            nu_crms_distintos,
            id_medico_unico,
            nu_5min, nu_10min, nu_15min, nu_20min, nu_30min, nu_60min,
            severidade
        FROM (
            SELECT
                *,
                CASE
                    WHEN nu_5min  >=  8 THEN fim_real_5min
                    WHEN nu_10min >= 11 THEN fim_real_10min
                    WHEN nu_5min  >=  6 THEN fim_real_5min
                    WHEN nu_10min >=  8 THEN fim_real_10min
                    WHEN nu_15min >= 10 THEN fim_real_15min
                    WHEN nu_20min >= 11 THEN fim_real_20min
                    WHEN nu_30min >= 12 THEN fim_real_30min
                    WHEN nu_60min >= 18 THEN fim_real_60min
                    WHEN nu_60min >=  6 AND nu_minutos_span_full <= nu_60min * 3 THEN fim_real_60min
                END AS dt_fim_real,
                CASE
                    WHEN nu_5min  >=  8 THEN 'EXTREMO'
                    WHEN nu_10min >= 11 THEN 'EXTREMO'
                    WHEN nu_5min  >=  6 THEN 'CRÍTICO'
                    WHEN nu_10min >=  8 THEN 'CRÍTICO'
                    WHEN nu_15min >= 10 THEN 'GRAVE'
                    WHEN nu_20min >= 11 THEN 'GRAVE'
                    WHEN nu_30min >= 12 THEN 'ALTO'
                    WHEN nu_60min >= 18 THEN 'ALTO'
                    WHEN nu_60min >=  6 AND nu_minutos_span_full <= nu_60min * 3 THEN 'ALTO'
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
            FROM temp_CGUSC.fp.crm_concentracao_multiplo_alertas a
            WHERE a.id_cnpj = ctrl.id_cnpj
        ), 0)
    FROM temp_CGUSC.fp.crm_concentracao_multiplo_controle ctrl
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
    'Multi-CRM'                AS tipo,
    COUNT(*)                   AS qtd_alertas,
    COUNT(DISTINCT id_cnpj)    AS qtd_cnpjs,
    AVG(nu_crms_distintos)     AS media_crms_distintos,
    AVG(nu_minutos_span)       AS media_minutos_span,
    MIN(dt_ini_concentracao)   AS primeiro_alerta,
    MAX(dt_ini_concentracao)   AS ultimo_alerta
FROM temp_CGUSC.fp.crm_concentracao_multiplo_alertas
GROUP BY severidade
ORDER BY
    CASE severidade WHEN 'EXTREMO' THEN 1 WHEN 'CRÍTICO' THEN 2 WHEN 'GRAVE' THEN 3 ELSE 4 END,
    tipo;

-- Top 30 piores casos
SELECT TOP 30
    id_cnpj,
    dt_dia,
    dt_ini_concentracao,
    dt_fim_concentracao,
    nu_minutos_span,
    nu_crms_distintos,
    nu_5min,
    nu_10min,
    nu_15min,
    nu_20min,
    nu_30min,
    nu_60min,
    severidade
FROM temp_CGUSC.fp.crm_concentracao_multiplo_alertas
ORDER BY
    CASE severidade WHEN 'EXTREMO' THEN 1 WHEN 'CRÍTICO' THEN 2 WHEN 'GRAVE' THEN 3 ELSE 4 END ASC,
    nu_60min DESC;
