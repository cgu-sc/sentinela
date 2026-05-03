-- ============================================================================
-- DIAGNÓSTICO: Casos em crm_unico_alertas NÃO capturados por crm_concentracao_alertas
-- ============================================================================
-- Explica POR QUÊ cada caso ficou de fora, com 3 categorias:
--   1. Sem cobertura alguma — CNPJ/dia sem nenhum evento de concentração
--   2. Multi-CRM na mesma hora — outros médicos diluíram nu_crms_distintos
--   3. Cobertura em hora diferente — concentração detectada em outra janela do dia
-- ============================================================================


-- ── 1. RESUMO POR MOTIVO ─────────────────────────────────────────────────────
;WITH perdidos AS (
    SELECT U.*
    FROM temp_CGUSC.fp.crm_unico_alertas U
    WHERE NOT EXISTS (
        SELECT 1
        FROM temp_CGUSC.fp.crm_concentracao_alertas C
        WHERE C.cnpj              = U.cnpj
          AND C.dt_dia            = U.dt_alerta
          AND C.nu_crms_distintos = 1
          AND C.id_medico_unico   = U.id_medico
    )
),
classificados AS (
    SELECT
        P.cnpj,
        P.id_medico,
        P.competencia,
        P.dt_alerta,
        P.hr_janela,
        P.nu_prescricoes_dia,
        P.nu_minutos_dia,
        P.taxa_hora,
        P.dt_ini_hora,
        P.dt_fim_hora,
        COUNT(C.cnpj)                                           AS qtd_eventos_concentracao,
        MAX(C.nu_crms_distintos)                                AS max_crms_vistos,
        MAX(C.nu_60min)                                         AS max_nu_60min,
        -- havia evento multi-CRM cobrindo exatamente a hora do alerta unico?
        MAX(CASE
                WHEN C.nu_crms_distintos > 1
                 AND DATEPART(HOUR, C.dt_ini_concentracao) = P.hr_janela
                THEN 1 ELSE 0
            END)                                                AS tinha_multi_crm_mesma_hora
    FROM perdidos P
    LEFT JOIN temp_CGUSC.fp.crm_concentracao_alertas C
        ON  C.cnpj   = P.cnpj
        AND C.dt_dia  = P.dt_alerta
    GROUP BY
        P.cnpj, P.id_medico, P.competencia, P.dt_alerta, P.hr_janela,
        P.nu_prescricoes_dia, P.nu_minutos_dia, P.taxa_hora,
        P.dt_ini_hora, P.dt_fim_hora
)
SELECT
    CASE
        WHEN qtd_eventos_concentracao = 0       THEN '1. Sem cobertura alguma'
        WHEN tinha_multi_crm_mesma_hora = 1     THEN '2. Multi-CRM na mesma hora (médico diluído)'
        ELSE                                         '3. Cobertura em hora diferente'
    END                         AS motivo,
    COUNT(*)                    AS qtd_casos,
    COUNT(DISTINCT cnpj)        AS qtd_cnpjs,
    COUNT(DISTINCT id_medico)   AS qtd_medicos,
    AVG(CAST(nu_prescricoes_dia AS FLOAT))  AS media_prescricoes,
    AVG(CAST(taxa_hora AS FLOAT))           AS media_taxa_hora,
    MIN(taxa_hora)              AS min_taxa_hora,
    MAX(taxa_hora)              AS max_taxa_hora
FROM classificados
GROUP BY
    CASE
        WHEN qtd_eventos_concentracao = 0       THEN '1. Sem cobertura alguma'
        WHEN tinha_multi_crm_mesma_hora = 1     THEN '2. Multi-CRM na mesma hora (médico diluído)'
        ELSE                                         '3. Cobertura em hora diferente'
    END
ORDER BY 1;


-- ── 2. DETALHE: TOP 200 por taxa_hora DESC ───────────────────────────────────
;WITH perdidos AS (
    SELECT U.*
    FROM temp_CGUSC.fp.crm_unico_alertas U
    WHERE NOT EXISTS (
        SELECT 1
        FROM temp_CGUSC.fp.crm_concentracao_alertas C
        WHERE C.cnpj              = U.cnpj
          AND C.dt_dia            = U.dt_alerta
          AND C.nu_crms_distintos = 1
          AND C.id_medico_unico   = U.id_medico
    )
)
SELECT TOP 200
    P.cnpj,
    P.id_medico,
    P.dt_alerta,
    P.hr_janela,
    P.nu_prescricoes_dia        AS nu_prescricoes_hora,
    P.nu_minutos_dia            AS nu_minutos_hora,
    CAST(P.taxa_hora AS DECIMAL(5,1)) AS taxa_hora,
    P.dt_ini_hora,
    P.dt_fim_hora,
    -- o que crm_concentracao viu nesse cnpj/dia
    C_agg.qtd_eventos_dia,
    C_agg.max_crms_distintos,
    C_agg.max_nu_60min,
    C_agg.severidade_max,
    -- motivo do gap
    CASE
        WHEN C_agg.qtd_eventos_dia = 0                  THEN '1. Sem cobertura alguma'
        WHEN C_agg.tinha_multi_crm_mesma_hora = 1       THEN '2. Multi-CRM na mesma hora'
        ELSE                                                 '3. Cobertura em hora diferente'
    END                         AS motivo_gap
FROM perdidos P
OUTER APPLY (
    SELECT
        COUNT(*)                                    AS qtd_eventos_dia,
        MAX(nu_crms_distintos)                      AS max_crms_distintos,
        MAX(nu_60min)                               AS max_nu_60min,
        -- severidade mais grave do dia para esse cnpj
        MIN(CASE severidade
                WHEN 'EXTREMO' THEN 1 WHEN 'CRÍTICO' THEN 2
                WHEN 'GRAVE'   THEN 3 WHEN 'ALTO'    THEN 4
            END)                                    AS _sev_ord,
        -- referência externa (P.hr_janela) não pode ficar dentro de MAX(): subconsulta separada
        (SELECT MAX(CASE WHEN nu_crms_distintos > 1 THEN 1 ELSE 0 END)
         FROM temp_CGUSC.fp.crm_concentracao_alertas x
         WHERE x.cnpj  = P.cnpj
           AND x.dt_dia = P.dt_alerta
           AND DATEPART(HOUR, x.dt_ini_concentracao) = P.hr_janela
        )                                           AS tinha_multi_crm_mesma_hora,
        (SELECT TOP 1 severidade
         FROM temp_CGUSC.fp.crm_concentracao_alertas x
         WHERE x.cnpj  = P.cnpj
           AND x.dt_dia = P.dt_alerta
         ORDER BY CASE x.severidade
                      WHEN 'EXTREMO' THEN 1 WHEN 'CRÍTICO' THEN 2
                      WHEN 'GRAVE'   THEN 3 ELSE 4
                  END)                              AS severidade_max
    FROM temp_CGUSC.fp.crm_concentracao_alertas C
    WHERE C.cnpj   = P.cnpj
      AND C.dt_dia  = P.dt_alerta
) C_agg
ORDER BY P.taxa_hora DESC;


-- ── 3. CNPJS COM MAIOR VOLUME DE GAPS (candidatos a investigação prioritária) ─
;WITH perdidos AS (
    SELECT cnpj, dt_alerta, id_medico, taxa_hora, nu_prescricoes_dia
    FROM temp_CGUSC.fp.crm_unico_alertas U
    WHERE NOT EXISTS (
        SELECT 1
        FROM temp_CGUSC.fp.crm_concentracao_alertas C
        WHERE C.cnpj              = U.cnpj
          AND C.dt_dia            = U.dt_alerta
          AND C.nu_crms_distintos = 1
          AND C.id_medico_unico   = U.id_medico
    )
)
SELECT TOP 30
    cnpj,
    COUNT(*)                            AS qtd_gaps,
    COUNT(DISTINCT id_medico)           AS qtd_medicos_perdidos,
    COUNT(DISTINCT dt_alerta)           AS qtd_dias_perdidos,
    MAX(CAST(taxa_hora AS DECIMAL(5,1))) AS max_taxa_hora,
    AVG(CAST(nu_prescricoes_dia AS FLOAT)) AS media_prescricoes
FROM perdidos
GROUP BY cnpj
ORDER BY qtd_gaps DESC;
