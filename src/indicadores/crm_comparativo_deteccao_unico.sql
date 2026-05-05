-- ============================================================================
-- ANÁLISE COMPARATIVA: crm_unico_alertas vs crm_concentracao_unico_alertas
-- ============================================================================
-- Método A: crm_unico_alertas          → bucket horário pré-agregado
-- Método B: crm_concentracao_unico_alertas → sliding window minuto-a-minuto
--
-- Grain de comparação: (cnpj, id_medico VARCHAR, dt_alerta DATE, hr_janela)
-- ============================================================================

-- ============================================================================
-- PREP: Normalizar ambas as tabelas para o mesmo grain
-- ============================================================================
DROP TABLE IF EXISTS #base_a;   -- crm_unico_alertas normalizado

SELECT
    F.cnpj,
    M.id_medico,
    U.dt_alerta,
    U.hr_janela,
    U.nu_prescricoes_dia   AS nu_prescricoes,
    U.nu_minutos_dia       AS nu_minutos,
    U.taxa_hora,
    U.severidade
INTO #base_a
FROM temp_CGUSC.fp.crm_unico_alertas U
INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.id = U.id_cnpj
INNER JOIN temp_CGUSC.fp.dados_medico   M ON M.id_medico = U.id_medico;

CREATE CLUSTERED INDEX IDX_A ON #base_a(cnpj, id_medico, dt_alerta, hr_janela);

DROP TABLE IF EXISTS #base_b;   -- crm_concentracao_unico_alertas normalizado

SELECT
    C.cnpj,
    C.id_medico,
    C.dt_dia                                                    AS dt_alerta,
    CAST(DATEPART(HOUR, C.dt_ini_concentracao) AS TINYINT)      AS hr_janela,
    C.nu_60min                                                  AS nu_prescricoes,
    C.nu_minutos_span                                           AS nu_minutos,
    C.dt_ini_concentracao,
    C.dt_fim_concentracao,
    C.nu_5min, C.nu_10min, C.nu_15min, C.nu_20min, C.nu_30min, C.nu_60min,
    C.severidade
INTO #base_b
FROM temp_CGUSC.fp.crm_concentracao_unico_alertas C;

CREATE CLUSTERED INDEX IDX_B ON #base_b(cnpj, id_medico, dt_alerta, hr_janela);



-- ============================================================================
-- SEÇÃO 0: TOTAIS GERAIS
-- ============================================================================
PRINT '=== SEÇÃO 0: TOTAIS GERAIS ===';

SELECT
    'A — crm_unico_alertas (bucket horário)'          AS metodo,
    COUNT(*)                                           AS total_eventos,
    COUNT(DISTINCT cnpj)                               AS qtd_cnpjs,
    COUNT(DISTINCT id_medico)                          AS qtd_medicos,
    COUNT(DISTINCT cnpj + '|' + id_medico)             AS pares_cnpj_medico
FROM #base_a
UNION ALL
SELECT
    'B — crm_concentracao_unico (sliding window)'     AS metodo,
    COUNT(*)                                          AS total_eventos,
    COUNT(DISTINCT cnpj)                              AS qtd_cnpjs,
    COUNT(DISTINCT id_medico)                         AS qtd_medicos,
    COUNT(DISTINCT cnpj + '|' + id_medico)            AS pares_cnpj_medico
FROM #base_b;



-- ============================================================================
-- SEÇÃO 1: INTERSECÇÃO — capturados por ambos
-- ============================================================================
PRINT '=== SEÇÃO 1: CAPTURADOS POR AMBOS ===';

SELECT
    COUNT(*)                                           AS total_em_ambos,
    COUNT(DISTINCT A.cnpj + '|' + A.id_medico)        AS pares_cnpj_medico,
    -- Concordância de severidade
    SUM(CASE WHEN A.severidade = B.severidade THEN 1 ELSE 0 END) AS severidade_igual,
    SUM(CASE WHEN A.severidade <> B.severidade THEN 1 ELSE 0 END) AS severidade_diferente
FROM #base_a A
INNER JOIN #base_b B
    ON  B.cnpj       = A.cnpj
    AND B.id_medico  = A.id_medico
    AND B.dt_alerta  = A.dt_alerta
    AND B.hr_janela  = A.hr_janela;

-- Detalhamento quando severidades divergem
SELECT
    A.severidade                                       AS severidade_bucket,
    B.severidade                                       AS severidade_sliding,
    COUNT(*)                                           AS qtd_eventos,
    AVG(A.nu_prescricoes)                              AS media_rx_bucket,
    AVG(A.nu_minutos)                                  AS media_min_bucket,
    AVG(B.nu_minutos)                                  AS media_min_sliding
FROM #base_a A
INNER JOIN #base_b B
    ON  B.cnpj       = A.cnpj
    AND B.id_medico  = A.id_medico
    AND B.dt_alerta  = A.dt_alerta
    AND B.hr_janela  = A.hr_janela
WHERE A.severidade <> B.severidade
GROUP BY A.severidade, B.severidade
ORDER BY A.severidade, B.severidade;



-- ============================================================================
-- SEÇÃO 2: APENAS NO MÉTODO A — eventos que o sliding window NÃO capturou
-- ============================================================================
PRINT '=== SEÇÃO 2: APENAS NO BUCKET HORÁRIO (não capturado pelo sliding window) ===';

-- Totais e distribuição por severidade
SELECT
    A.severidade,
    COUNT(*)                           AS qtd_eventos,
    COUNT(DISTINCT A.cnpj)             AS qtd_cnpjs,
    COUNT(DISTINCT A.id_medico)        AS qtd_medicos,
    AVG(A.nu_prescricoes)              AS media_rx,
    AVG(CAST(A.nu_minutos AS FLOAT))   AS media_minutos,
    AVG(A.taxa_hora)                   AS media_taxa_hora,
    MIN(A.nu_prescricoes)              AS min_rx,
    MAX(A.nu_prescricoes)              AS max_rx,
    MIN(A.nu_minutos)                  AS min_minutos,
    MAX(A.nu_minutos)                  AS max_minutos
FROM #base_a A
WHERE NOT EXISTS (
    SELECT 1 FROM #base_b B
    WHERE B.cnpj      = A.cnpj
      AND B.id_medico = A.id_medico
      AND B.dt_alerta = A.dt_alerta
      AND B.hr_janela = A.hr_janela
)
GROUP BY A.severidade
ORDER BY
    CASE A.severidade WHEN 'EXTREMO' THEN 1 WHEN 'CRÍTICO' THEN 2 WHEN 'GRAVE' THEN 3 ELSE 4 END;

-- Perfil detalhado: distribuição de nu_prescricoes e nu_minutos dos eventos perdidos
-- (ajuda a entender se estão próximos dos limiares do sliding window)
SELECT
    A.nu_prescricoes                                   AS rx_na_hora,
    A.nu_minutos                                       AS minutos_span,
    CAST(A.taxa_hora AS DECIMAL(6,1))                  AS taxa_hora,
    A.severidade,
    COUNT(*)                                           AS qtd_eventos
FROM #base_a A
WHERE NOT EXISTS (
    SELECT 1 FROM #base_b B
    WHERE B.cnpj      = A.cnpj
      AND B.id_medico = A.id_medico
      AND B.dt_alerta = A.dt_alerta
      AND B.hr_janela = A.hr_janela
)
GROUP BY A.nu_prescricoes, A.nu_minutos, A.taxa_hora, A.severidade
ORDER BY qtd_eventos DESC
OFFSET 0 ROWS FETCH NEXT 40 ROWS ONLY;

-- Top 20 casos individuais mais relevantes perdidos pelo sliding window
SELECT TOP 20
    A.cnpj,
    A.id_medico,
    A.dt_alerta,
    A.hr_janela,
    A.nu_prescricoes  AS rx_na_hora,
    A.nu_minutos      AS minutos_span,
    CAST(A.taxa_hora AS DECIMAL(6,1)) AS taxa_hora,
    A.severidade      AS severidade_bucket
FROM #base_a A
WHERE NOT EXISTS (
    SELECT 1 FROM #base_b B
    WHERE B.cnpj      = A.cnpj
      AND B.id_medico = A.id_medico
      AND B.dt_alerta = A.dt_alerta
      AND B.hr_janela = A.hr_janela
)
ORDER BY
    CASE A.severidade WHEN 'EXTREMO' THEN 1 WHEN 'CRÍTICO' THEN 2 WHEN 'GRAVE' THEN 3 ELSE 4 END,
    A.taxa_hora DESC;



-- ============================================================================
-- SEÇÃO 3: APENAS NO MÉTODO B — novos alertas do sliding window
-- ============================================================================
PRINT '=== SEÇÃO 3: APENAS NO SLIDING WINDOW (não capturado pelo bucket horário) ===';

-- Totais e distribuição por severidade
SELECT
    B.severidade,
    COUNT(*)                           AS qtd_eventos,
    COUNT(DISTINCT B.cnpj)             AS qtd_cnpjs,
    COUNT(DISTINCT B.id_medico)        AS qtd_medicos,
    AVG(B.nu_prescricoes)              AS media_rx_60min,
    AVG(CAST(B.nu_minutos AS FLOAT))   AS media_minutos_span,
    AVG(CAST(B.nu_5min  AS FLOAT))     AS media_rx_5min,
    AVG(CAST(B.nu_10min AS FLOAT))     AS media_rx_10min
FROM #base_b B
WHERE NOT EXISTS (
    SELECT 1 FROM #base_a A
    WHERE A.cnpj      = B.cnpj
      AND A.id_medico = B.id_medico
      AND A.dt_alerta = B.dt_alerta
      AND A.hr_janela = B.hr_janela
)
GROUP BY B.severidade
ORDER BY
    CASE B.severidade WHEN 'EXTREMO' THEN 1 WHEN 'CRÍTICO' THEN 2 WHEN 'GRAVE' THEN 3 ELSE 4 END;

-- Top 20 casos exclusivos do sliding window
SELECT TOP 20
    B.cnpj,
    B.id_medico,
    B.dt_alerta,
    B.hr_janela,
    B.dt_ini_concentracao,
    B.dt_fim_concentracao,
    B.nu_minutos      AS minutos_span,
    B.nu_5min,
    B.nu_10min,
    B.nu_30min,
    B.nu_60min,
    B.severidade      AS severidade_sliding
FROM #base_b B
WHERE NOT EXISTS (
    SELECT 1 FROM #base_a A
    WHERE A.cnpj      = B.cnpj
      AND A.id_medico = B.id_medico
      AND A.dt_alerta = B.dt_alerta
      AND A.hr_janela = B.hr_janela
)
ORDER BY
    CASE B.severidade WHEN 'EXTREMO' THEN 1 WHEN 'CRÍTICO' THEN 2 WHEN 'GRAVE' THEN 3 ELSE 4 END,
    B.nu_5min DESC;



-- ============================================================================
-- SEÇÃO 4: ANÁLISE DE COBERTURA — por par (CNPJ, médico)
-- Mostra para cada par se foi detectado só por A, só por B, ou por ambos
-- ============================================================================
PRINT '=== SEÇÃO 4: COBERTURA POR PAR (CNPJ, MÉDICO) ===';

;WITH pares_a AS (
    SELECT DISTINCT cnpj, id_medico FROM #base_a
),
pares_b AS (
    SELECT DISTINCT cnpj, id_medico FROM #base_b
),
todos AS (
    SELECT cnpj, id_medico FROM pares_a
    UNION
    SELECT cnpj, id_medico FROM pares_b
)
SELECT
    CASE
        WHEN A.id_medico IS NOT NULL AND B.id_medico IS NOT NULL THEN 'AMBOS'
        WHEN A.id_medico IS NOT NULL AND B.id_medico IS NULL     THEN 'SÓ BUCKET HORÁRIO'
        ELSE                                                           'SÓ SLIDING WINDOW'
    END                                    AS cobertura,
    COUNT(*)                               AS qtd_pares,
    CAST(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS DECIMAL(5,1)) AS pct
FROM todos T
LEFT JOIN pares_a A ON A.cnpj = T.cnpj AND A.id_medico = T.id_medico
LEFT JOIN pares_b B ON B.cnpj = T.cnpj AND B.id_medico = T.id_medico
GROUP BY
    CASE
        WHEN A.id_medico IS NOT NULL AND B.id_medico IS NOT NULL THEN 'AMBOS'
        WHEN A.id_medico IS NOT NULL AND B.id_medico IS NULL     THEN 'SÓ BUCKET HORÁRIO'
        ELSE                                                           'SÓ SLIDING WINDOW'
    END
ORDER BY qtd_pares DESC;



-- ============================================================================
-- SEÇÃO 5: CONCORDÂNCIA DE SEVERIDADE nos eventos em comum
-- ============================================================================
PRINT '=== SEÇÃO 5: CONCORDÂNCIA DE SEVERIDADE (eventos em ambos) ===';

SELECT
    A.severidade                                       AS severidade_bucket,
    B.severidade                                       AS severidade_sliding,
    COUNT(*)                                           AS qtd_eventos,
    CAST(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER ()
         AS DECIMAL(5,1))                              AS pct_do_total
FROM #base_a A
INNER JOIN #base_b B
    ON  B.cnpj       = A.cnpj
    AND B.id_medico  = A.id_medico
    AND B.dt_alerta  = A.dt_alerta
    AND B.hr_janela  = A.hr_janela
GROUP BY A.severidade, B.severidade
ORDER BY
    CASE A.severidade WHEN 'EXTREMO' THEN 1 WHEN 'CRÍTICO' THEN 2 WHEN 'GRAVE' THEN 3 ELSE 4 END,
    CASE B.severidade WHEN 'EXTREMO' THEN 1 WHEN 'CRÍTICO' THEN 2 WHEN 'GRAVE' THEN 3 ELSE 4 END;



-- ============================================================================
-- SEÇÃO 6: RESUMO EXECUTIVO — tabela única de diagnóstico
-- ============================================================================
PRINT '=== SEÇÃO 6: RESUMO EXECUTIVO ===';

;WITH
total_a  AS (SELECT COUNT(*) AS n FROM #base_a),
total_b  AS (SELECT COUNT(*) AS n FROM #base_b),
em_ambos AS (
    SELECT COUNT(*) AS n
    FROM #base_a A
    INNER JOIN #base_b B
        ON B.cnpj=A.cnpj AND B.id_medico=A.id_medico
       AND B.dt_alerta=A.dt_alerta AND B.hr_janela=A.hr_janela
),
so_a AS (
    SELECT COUNT(*) AS n FROM #base_a A
    WHERE NOT EXISTS (
        SELECT 1 FROM #base_b B
        WHERE B.cnpj=A.cnpj AND B.id_medico=A.id_medico
          AND B.dt_alerta=A.dt_alerta AND B.hr_janela=A.hr_janela
    )
),
so_b AS (
    SELECT COUNT(*) AS n FROM #base_b B
    WHERE NOT EXISTS (
        SELECT 1 FROM #base_a A
        WHERE A.cnpj=B.cnpj AND A.id_medico=B.id_medico
          AND A.dt_alerta=B.dt_alerta AND A.hr_janela=B.hr_janela
    )
)
SELECT
    ta.n                                               AS total_bucket_horario,
    tb.n                                               AS total_sliding_window,
    ca.n                                               AS em_ambos,
    CAST(ca.n * 100.0 / NULLIF(ta.n, 0) AS DECIMAL(5,1)) AS pct_bucket_capturado_pelo_sliding,
    sa.n                                               AS so_bucket_perdidos_pelo_sliding,
    CAST(sa.n * 100.0 / NULLIF(ta.n, 0) AS DECIMAL(5,1)) AS pct_perdidos,
    sb.n                                               AS so_sliding_novos_alertas,
    CAST(sb.n * 100.0 / NULLIF(tb.n, 0) AS DECIMAL(5,1)) AS pct_novos_no_sliding
FROM total_a ta, total_b tb, em_ambos ca, so_a sa, so_b sb;
