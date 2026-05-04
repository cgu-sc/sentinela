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
        cnpj       VARCHAR(14) NOT NULL,
        dt_inicio  DATETIME    NOT NULL,
        dt_fim     DATETIME    NULL,
        nu_alertas INT         NULL,
        status     VARCHAR(12) NOT NULL,
        CONSTRAINT PK_ConcentracaoUnicoControle PRIMARY KEY CLUSTERED (cnpj)
    );

IF OBJECT_ID('temp_CGUSC.fp.crm_concentracao_unico_alertas') IS NULL
BEGIN
    CREATE TABLE temp_CGUSC.fp.crm_concentracao_unico_alertas (
        cnpj                VARCHAR(14) NOT NULL,
        id_medico           VARCHAR(20) NOT NULL,
        dt_dia              DATE        NOT NULL,
        dt_ini_concentracao DATETIME    NOT NULL,
        dt_fim_concentracao DATETIME    NOT NULL,
        nu_minutos_span     INT         NOT NULL,
        nu_5min             INT         NOT NULL,
        nu_10min            INT         NOT NULL,
        nu_15min            INT         NOT NULL,
        nu_20min            INT         NOT NULL,
        nu_30min            INT         NOT NULL,
        nu_60min            INT         NOT NULL,
        severidade          VARCHAR(10) NOT NULL
    );
    CREATE CLUSTERED INDEX IDX_ConcentracaoUnicoAlertas
        ON temp_CGUSC.fp.crm_concentracao_unico_alertas(cnpj, id_medico, dt_dia);
END


-- ============================================================================
-- PASSO 1: Limpar CNPJs interrompidos para reprocessar do zero
-- ============================================================================
PRINT '>> Passo 1: Limpando CNPJs interrompidos (status PROCESSANDO)...';

DELETE alerta
FROM temp_CGUSC.fp.crm_concentracao_unico_alertas alerta
INNER JOIN temp_CGUSC.fp.crm_concentracao_unico_controle ctrl
    ON ctrl.cnpj = alerta.cnpj
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

SELECT DISTINCT A.cnpj
INTO #cnpjs_pendentes
FROM temp_CGUSC.fp.teste_mov_SC A
INNER JOIN temp_CGUSC.fp.medicamentos_patologia PA ON PA.codigo_barra = A.codigo_barra
WHERE A.crm    IS NOT NULL
  AND A.crm_uf IS NOT NULL
  AND A.crm_uf <> 'BR'
  AND A.data_hora >= @DataInicio
  AND A.data_hora <= @DataFim
  AND A.cnpj NOT IN (
      SELECT cnpj FROM temp_CGUSC.fp.crm_concentracao_unico_controle WHERE status = 'OK'
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

    SELECT TOP (@lote_size) cnpj
    INTO #lote_atual
    FROM #cnpjs_pendentes
    ORDER BY cnpj;

    -- ── Marcar lote como PROCESSANDO ─────────────────────────────────────
    INSERT INTO temp_CGUSC.fp.crm_concentracao_unico_controle (cnpj, dt_inicio, status)
    SELECT cnpj, GETDATE(), 'PROCESSANDO'
    FROM #lote_atual;

    -- ── Self-join INTRA-MÉDICO: B restrito ao mesmo CRM que A ─────────────
    -- A diferença crucial em relação ao multi-CRM: AND B.crm = A.crm / B.crm_uf = A.crm_uf
    -- Isso isola a janela sliding ao volume do próprio médico, sem contaminação.
    DROP TABLE IF EXISTS #concentracao_raw;

    SELECT
        A.cnpj,
        CAST(CAST(A.crm AS VARCHAR(10)) + '/' + A.crm_uf AS VARCHAR(20))  AS id_medico,
        A.data_hora                                                         AS janela_inicio,

        COUNT(DISTINCT CASE WHEN B.data_hora <= DATEADD(MINUTE,  5, A.data_hora)
                            THEN B.num_autorizacao END)                     AS nu_5min,
        COUNT(DISTINCT CASE WHEN B.data_hora <= DATEADD(MINUTE, 10, A.data_hora)
                            THEN B.num_autorizacao END)                     AS nu_10min,
        COUNT(DISTINCT CASE WHEN B.data_hora <= DATEADD(MINUTE, 15, A.data_hora)
                            THEN B.num_autorizacao END)                     AS nu_15min,
        COUNT(DISTINCT CASE WHEN B.data_hora <= DATEADD(MINUTE, 20, A.data_hora)
                            THEN B.num_autorizacao END)                     AS nu_20min,
        COUNT(DISTINCT CASE WHEN B.data_hora <= DATEADD(MINUTE, 30, A.data_hora)
                            THEN B.num_autorizacao END)                     AS nu_30min,
        COUNT(DISTINCT CASE WHEN B.data_hora <= DATEADD(MINUTE, 60, A.data_hora)
                            THEN B.num_autorizacao END)                     AS nu_60min,

        MIN(B.data_hora)                                                    AS dt_ini_raw,
        MAX(B.data_hora)                                                    AS dt_fim_raw

    INTO #concentracao_raw
    FROM temp_CGUSC.fp.teste_mov_SC A
    INNER JOIN temp_CGUSC.fp.teste_mov_SC B
        ON  B.cnpj      = A.cnpj
        AND B.crm       = A.crm
        AND B.crm_uf    = A.crm_uf
        AND B.data_hora BETWEEN A.data_hora AND DATEADD(MINUTE, 60, A.data_hora)
    INNER JOIN temp_CGUSC.fp.medicamentos_patologia PA ON PA.codigo_barra = A.codigo_barra
    INNER JOIN temp_CGUSC.fp.medicamentos_patologia PB ON PB.codigo_barra = B.codigo_barra
    WHERE A.cnpj IN (SELECT cnpj FROM #lote_atual)
      AND A.crm    IS NOT NULL AND A.crm_uf    IS NOT NULL AND A.crm_uf    <> 'BR'
      AND B.crm    IS NOT NULL AND B.crm_uf    IS NOT NULL AND B.crm_uf    <> 'BR'
      AND A.data_hora >= @DataInicio AND A.data_hora <= @DataFim
    GROUP BY A.cnpj, A.crm, A.crm_uf, A.data_hora
    HAVING (
           COUNT(DISTINCT CASE WHEN B.data_hora <= DATEADD(MINUTE,  5, A.data_hora) THEN B.num_autorizacao END) >=  6
        OR COUNT(DISTINCT CASE WHEN B.data_hora <= DATEADD(MINUTE, 10, A.data_hora) THEN B.num_autorizacao END) >=  8
        OR COUNT(DISTINCT CASE WHEN B.data_hora <= DATEADD(MINUTE, 15, A.data_hora) THEN B.num_autorizacao END) >=  8
        OR COUNT(DISTINCT CASE WHEN B.data_hora <= DATEADD(MINUTE, 20, A.data_hora) THEN B.num_autorizacao END) >=  9
        OR COUNT(DISTINCT CASE WHEN B.data_hora <= DATEADD(MINUTE, 30, A.data_hora) THEN B.num_autorizacao END) >=  7
        OR COUNT(DISTINCT CASE WHEN B.data_hora <= DATEADD(MINUTE, 60, A.data_hora) THEN B.num_autorizacao END) >= 10
    );

    -- ── Deduplicação: 1 evento por (cnpj, médico, hora) ──────────────────
    -- PARTITION BY inclui id_medico: dois médicos diferentes no mesmo CNPJ/hora
    -- geram eventos independentes (não se cancelam).
    DROP TABLE IF EXISTS #concentracao_dedup;

    SELECT 
        cnpj, 
        id_medico, 
        janela_inicio,
        nu_5min, 
        nu_10min, 
        nu_15min, 
        nu_20min, 
        nu_30min, 
        nu_60min,
        dt_ini_raw, 
        dt_fim_raw,
        ROW_NUMBER() OVER (
            PARTITION BY
                cnpj,
                id_medico,
                CAST(janela_inicio AS DATE),
                DATEDIFF(MINUTE, 0, janela_inicio) / 60
            ORDER BY janela_inicio ASC
        ) AS rn
    INTO #concentracao_dedup
    FROM #concentracao_raw;

    -- ── INSERT incremental nos alertas ────────────────────────────────────
    INSERT INTO temp_CGUSC.fp.crm_concentracao_unico_alertas
        (cnpj, id_medico, dt_dia, dt_ini_concentracao, dt_fim_concentracao, nu_minutos_span,
         nu_5min, nu_10min, nu_15min, nu_20min, nu_30min, nu_60min, severidade)
    SELECT cnpj, id_medico, dt_dia, dt_ini_concentracao, dt_fim_concentracao, nu_minutos_span,
           nu_5min, nu_10min, nu_15min, nu_20min, nu_30min, nu_60min, severidade
    FROM (
        SELECT
            cnpj,
            id_medico,
            CAST(janela_inicio AS DATE)                                 AS dt_dia,
            dt_ini_raw                                                 AS dt_ini_concentracao,
            dt_fim_raw                                                 AS dt_fim_concentracao,
            DATEDIFF(MINUTE, dt_ini_raw, dt_fim_raw)                   AS nu_minutos_span,
            nu_5min, nu_10min, nu_15min, nu_20min, nu_30min, nu_60min,
            CASE
                WHEN nu_5min  >=  7 THEN 'EXTREMO'   -- 1,4/min
                WHEN nu_10min >= 10 THEN 'EXTREMO'   -- 1,0/min
                WHEN nu_5min  >=  6 THEN 'CRÍTICO'   -- 1,2/min
                WHEN nu_10min >=  8 THEN 'CRÍTICO'   -- 0,8/min
                WHEN nu_15min >=  8 THEN 'GRAVE'     -- 0,5/min
                WHEN nu_20min >=  9 THEN 'GRAVE'     -- 0,5/min
                WHEN nu_30min >=  7 THEN 'ALTO'      -- 0,2/min
                WHEN nu_60min >= 10 THEN 'ALTO'      -- 0,2/min
            END AS severidade
        FROM #concentracao_dedup
        WHERE rn = 1
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
            WHERE a.cnpj = ctrl.cnpj
        ), 0)
    FROM temp_CGUSC.fp.crm_concentracao_unico_controle ctrl
    WHERE ctrl.cnpj IN (SELECT cnpj FROM #lote_atual);

    -- ── Remover lote da fila e atualizar contadores ───────────────────────
    DELETE FROM #cnpjs_pendentes WHERE cnpj IN (SELECT cnpj FROM #lote_atual);

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
    COUNT(DISTINCT cnpj)            AS qtd_cnpjs,
    COUNT(DISTINCT id_medico)       AS qtd_medicos,
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
    cnpj,
    id_medico,
    dt_dia,
    dt_ini_concentracao,
    dt_fim_concentracao,
    nu_minutos_span,
    nu_5min,
    nu_10min,
    nu_15min,
    nu_20min,
    nu_30min,
    nu_60min,
    severidade
FROM temp_CGUSC.fp.crm_concentracao_unico_alertas
ORDER BY
    CASE severidade WHEN 'EXTREMO' THEN 1 WHEN 'CRÍTICO' THEN 2 WHEN 'GRAVE' THEN 3 ELSE 4 END ASC,
    nu_60min DESC;
