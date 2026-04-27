-- ============================================================================
-- COMPARAÇÃO DE METODOLOGIAS: ×7 Mediana  vs  Modified Z-Score (MZS > 4.0)
-- Escopo: CNPJ 10201388000142 | CRM 27381/SC | Dia 14/08/2024
-- Medianas/MAD calculados sobre o trimestre inteiro (Q3 2024) — só os resultados são filtrados ao dia.
-- ============================================================================

DECLARE @CNPJ      VARCHAR(14) = '10201388000142';
DECLARE @CRM       VARCHAR(10) = '27381';
DECLARE @CRM_UF    VARCHAR(2)  = 'SC';
DECLARE @DataAlvo  DATE        = '2024-08-14';  -- foco da análise (medianas usam o trimestre inteiro)

-- ============================================================================
-- PASSO 1: BASE HORÁRIA (scan único, filtrado ao CNPJ alvo)
-- ============================================================================
DROP TABLE IF EXISTS #bh;
SELECT
    cnpj,
    YEAR(data_hora) * 100 + MONTH(data_hora)   AS competencia,
    CAST(data_hora AS DATE)                     AS dt_janela,
    DATEPART(HOUR, data_hora)                   AS hr_janela,
    COUNT(DISTINCT num_autorizacao)             AS nu_prescricoes_hora,
    COUNT(DISTINCT crm)                         AS nu_crms_distintos_hora
INTO #bh
FROM temp_CGUSC.fp.teste_mov_SC
WHERE cnpj = @CNPJ
  AND crm IS NOT NULL AND crm_uf IS NOT NULL AND crm_uf <> 'BR'
GROUP BY cnpj,
         YEAR(data_hora), MONTH(data_hora),
         CAST(data_hora AS DATE),
         DATEPART(HOUR, data_hora);

-- ============================================================================
-- PASSO 2: MEDIANA TRIMESTRAL POR HORA
-- ============================================================================
DROP TABLE IF EXISTS #med;
SELECT DISTINCT
    cnpj, competencia, hr_janela,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY nu_prescricoes_hora)
        OVER (PARTITION BY cnpj,
                           (competencia / 100),
                           ((competencia % 100 - 1) / 3),
                           hr_janela)           AS mediana_hora
INTO #med
FROM #bh;

-- ============================================================================
-- PASSO 3: MAD TRIMESTRAL POR HORA
-- ============================================================================
DROP TABLE IF EXISTS #mad;
SELECT DISTINCT
    H.cnpj, H.competencia, H.hr_janela,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ABS(H.nu_prescricoes_hora - M.mediana_hora))
        OVER (PARTITION BY H.cnpj,
                           (H.competencia / 100),
                           ((H.competencia % 100 - 1) / 3),
                           H.hr_janela)         AS mad_hora
INTO #mad
FROM #bh H
INNER JOIN #med M ON M.cnpj = H.cnpj
                 AND M.competencia = H.competencia
                 AND M.hr_janela = H.hr_janela;

-- ============================================================================
-- PASSO 4: CLASSIFICAÇÃO DUPLA — cada hora recebe flag de ambos os métodos
-- ============================================================================
DROP TABLE IF EXISTS #classificacao;
SELECT
    H.cnpj,
    H.competencia,
    H.dt_janela,
    H.hr_janela,
    H.nu_prescricoes_hora,
    H.nu_crms_distintos_hora,
    CAST(M.mediana_hora AS DECIMAL(10,2))   AS mediana_hora,
    CAST(MAD.mad_hora   AS DECIMAL(10,4))   AS mad_hora,

    -- MZS calculado (NULL quando MAD = 0)
    CASE
        WHEN MAD.mad_hora > 0
        THEN CAST(0.6745 * (H.nu_prescricoes_hora - M.mediana_hora) / MAD.mad_hora AS DECIMAL(10,4))
        ELSE NULL
    END AS mzs_valor,

    -- FLAG: método antigo (×7 mediana, mínimo 10 prescrições)
    CASE
        WHEN H.nu_prescricoes_hora >= 10
         AND H.nu_prescricoes_hora >= M.mediana_hora * 7
        THEN 1 ELSE 0
    END AS flag_metodo_x7,

    -- FLAG: novo método (MZS > 4.0, mínimo 10 prescrições)
    CASE
        WHEN H.nu_prescricoes_hora >= 10 AND MAD.mad_hora > 0
         AND (0.6745 * (H.nu_prescricoes_hora - M.mediana_hora) / MAD.mad_hora) > 4.0
        THEN 1
        WHEN H.nu_prescricoes_hora >= 10 AND MAD.mad_hora = 0
         AND H.nu_prescricoes_hora > M.mediana_hora
        THEN 1
        ELSE 0
    END AS flag_metodo_mzs
INTO #classificacao
FROM #bh H
INNER JOIN #med M   ON M.cnpj = H.cnpj AND M.competencia = H.competencia AND M.hr_janela = H.hr_janela
INNER JOIN #mad MAD ON MAD.cnpj = H.cnpj AND MAD.competencia = H.competencia AND MAD.hr_janela = H.hr_janela;

-- ============================================================================
-- RESULTADO 1: RESUMO — horas anômalas por método (somente horas com >= 10 rx)
-- ============================================================================
SELECT '=== RESUMO POR MÉTODO ===' AS info;

SELECT
    SUM(flag_metodo_x7)  AS total_horas_x7,
    SUM(flag_metodo_mzs) AS total_horas_mzs,
    SUM(CASE WHEN flag_metodo_x7 = 1 AND flag_metodo_mzs = 1 THEN 1 ELSE 0 END) AS ambos,
    SUM(CASE WHEN flag_metodo_x7 = 0 AND flag_metodo_mzs = 1 THEN 1 ELSE 0 END) AS somente_mzs,
    SUM(CASE WHEN flag_metodo_x7 = 1 AND flag_metodo_mzs = 0 THEN 1 ELSE 0 END) AS somente_x7
FROM #classificacao
WHERE dt_janela = @DataAlvo;

-- ============================================================================
-- RESULTADO 2: TODAS AS HORAS FLAGRADAS POR QUALQUER MÉTODO
-- (inclui horas com >= 10 rx para ver o MZS mesmo quando nenhum flag ativo)
-- ============================================================================
SELECT '=== TODAS AS HORAS ANÔMALAS (qualquer método) ===' AS info;

SELECT
    dt_janela,
    hr_janela,
    nu_prescricoes_hora,
    nu_crms_distintos_hora,
    mediana_hora,
    mad_hora,
    mzs_valor,
    CAST(nu_prescricoes_hora AS DECIMAL(10,1)) / NULLIF(mediana_hora, 0) AS multiplicador_x7,
    flag_metodo_x7,
    flag_metodo_mzs,
    CASE
        WHEN flag_metodo_x7 = 1 AND flag_metodo_mzs = 1 THEN 'AMBOS'
        WHEN flag_metodo_x7 = 0 AND flag_metodo_mzs = 1 THEN 'SOMENTE MZS'
        WHEN flag_metodo_x7 = 1 AND flag_metodo_mzs = 0 THEN 'SOMENTE ×7'
        ELSE '-'
    END AS diferenca
FROM #classificacao
WHERE dt_janela = @DataAlvo
  AND (flag_metodo_x7 = 1 OR flag_metodo_mzs = 1)
ORDER BY hr_janela;

-- ============================================================================
-- RESULTADO 3: HORAS COM >= 10 PRESCRIÇÕES (radar completo — mesmo sem flag)
-- Permite ver o MZS de horas que ficaram abaixo do limiar.
-- ============================================================================
SELECT '=== HORAS COM >= 10 PRESCRIÇÕES (radar completo) ===' AS info;

SELECT
    dt_janela,
    hr_janela,
    nu_prescricoes_hora,
    mediana_hora,
    mad_hora,
    mzs_valor,
    CAST(nu_prescricoes_hora AS DECIMAL(10,1)) / NULLIF(mediana_hora, 0) AS multiplicador_x7,
    flag_metodo_x7,
    flag_metodo_mzs
FROM #classificacao
WHERE dt_janela = @DataAlvo
  AND nu_prescricoes_hora >= 10
ORDER BY hr_janela;

-- ============================================================================
-- RESULTADO 4: LANÇAMENTOS DO CRM 27381/SC EM HORAS FLAGRADAS PELO MZS
-- ============================================================================
SELECT '=== LANÇAMENTOS — CRM 27381/SC — MÉTODO MZS ===' AS info;

SELECT
    MOV.cnpj,
    MOV.data_hora,
    CAST(MOV.data_hora AS DATE)        AS dt_janela,
    DATEPART(HOUR, MOV.data_hora)      AS hr_janela,
    MOV.crm,
    MOV.crm_uf,
    MOV.num_autorizacao,
    MOV.codigo_barra,
    MOV.valor_pago,
    C.nu_prescricoes_hora,
    C.mediana_hora,
    C.mad_hora,
    C.mzs_valor,
    'MZS' AS metodo
FROM temp_CGUSC.fp.teste_mov_SC MOV
INNER JOIN #classificacao C
    ON  C.cnpj     = MOV.cnpj
    AND C.dt_janela = CAST(MOV.data_hora AS DATE)
    AND C.hr_janela = DATEPART(HOUR, MOV.data_hora)
WHERE MOV.cnpj   = @CNPJ
  AND MOV.crm    = @CRM
  AND MOV.crm_uf = @CRM_UF
  AND CAST(MOV.data_hora AS DATE) = @DataAlvo
  AND C.flag_metodo_mzs = 1
ORDER BY MOV.data_hora;

-- ============================================================================
-- RESULTADO 5: LANÇAMENTOS DO CRM 27381/SC EM HORAS FLAGRADAS PELO ×7
-- ============================================================================
SELECT '=== LANÇAMENTOS — CRM 27381/SC — MÉTODO ×7 ===' AS info;

SELECT
    MOV.cnpj,
    MOV.data_hora,
    CAST(MOV.data_hora AS DATE)        AS dt_janela,
    DATEPART(HOUR, MOV.data_hora)      AS hr_janela,
    MOV.crm,
    MOV.crm_uf,
    MOV.num_autorizacao,
    MOV.codigo_barra,
    MOV.valor_pago,
    C.nu_prescricoes_hora,
    C.mediana_hora,
    C.mzs_valor,
    CAST(C.nu_prescricoes_hora AS DECIMAL(10,1)) / NULLIF(C.mediana_hora, 0) AS multiplicador_x7,
    '×7' AS metodo
FROM temp_CGUSC.fp.teste_mov_SC MOV
INNER JOIN #classificacao C
    ON  C.cnpj     = MOV.cnpj
    AND C.dt_janela = CAST(MOV.data_hora AS DATE)
    AND C.hr_janela = DATEPART(HOUR, MOV.data_hora)
WHERE MOV.cnpj   = @CNPJ
  AND MOV.crm    = @CRM
  AND MOV.crm_uf = @CRM_UF
  AND CAST(MOV.data_hora AS DATE) = @DataAlvo
  AND C.flag_metodo_x7 = 1
ORDER BY MOV.data_hora;

-- ============================================================================
-- RESULTADO 6: DIFERENÇA — lançamentos EXCLUSIVOS DO MZS (não detectados pelo ×7)
-- ============================================================================
SELECT '=== DIFERENÇA: LANÇAMENTOS SOMENTE NO MZS (novos casos) ===' AS info;

SELECT
    MOV.cnpj,
    MOV.data_hora,
    CAST(MOV.data_hora AS DATE)        AS dt_janela,
    DATEPART(HOUR, MOV.data_hora)      AS hr_janela,
    MOV.crm,
    MOV.crm_uf,
    MOV.num_autorizacao,
    MOV.codigo_barra,
    MOV.valor_pago,
    C.nu_prescricoes_hora,
    C.mediana_hora,
    C.mad_hora,
    C.mzs_valor,
    CAST(C.nu_prescricoes_hora AS DECIMAL(10,1)) / NULLIF(C.mediana_hora, 0) AS multiplicador_x7
FROM temp_CGUSC.fp.teste_mov_SC MOV
INNER JOIN #classificacao C
    ON  C.cnpj     = MOV.cnpj
    AND C.dt_janela = CAST(MOV.data_hora AS DATE)
    AND C.hr_janela = DATEPART(HOUR, MOV.data_hora)
WHERE MOV.cnpj   = @CNPJ
  AND MOV.crm    = @CRM
  AND MOV.crm_uf = @CRM_UF
  AND CAST(MOV.data_hora AS DATE) = @DataAlvo
  AND C.flag_metodo_mzs = 1
  AND C.flag_metodo_x7  = 0
ORDER BY MOV.data_hora;

-- ============================================================================
-- RESULTADO 7: DIFERENÇA — lançamentos EXCLUSIVOS DO ×7 (perdidos pelo MZS)
-- ============================================================================
SELECT '=== DIFERENÇA: LANÇAMENTOS SOMENTE NO ×7 (casos perdidos pelo MZS) ===' AS info;

SELECT
    MOV.cnpj,
    MOV.data_hora,
    CAST(MOV.data_hora AS DATE)        AS dt_janela,
    DATEPART(HOUR, MOV.data_hora)      AS hr_janela,
    MOV.crm,
    MOV.crm_uf,
    MOV.num_autorizacao,
    MOV.codigo_barra,
    MOV.valor_pago,
    C.nu_prescricoes_hora,
    C.mediana_hora,
    C.mad_hora,
    C.mzs_valor,
    CAST(C.nu_prescricoes_hora AS DECIMAL(10,1)) / NULLIF(C.mediana_hora, 0) AS multiplicador_x7
FROM temp_CGUSC.fp.teste_mov_SC MOV
INNER JOIN #classificacao C
    ON  C.cnpj     = MOV.cnpj
    AND C.dt_janela = CAST(MOV.data_hora AS DATE)
    AND C.hr_janela = DATEPART(HOUR, MOV.data_hora)
WHERE MOV.cnpj   = @CNPJ
  AND MOV.crm    = @CRM
  AND MOV.crm_uf = @CRM_UF
  AND CAST(MOV.data_hora AS DATE) = @DataAlvo
  AND C.flag_metodo_x7  = 1
  AND C.flag_metodo_mzs = 0
ORDER BY MOV.data_hora;

-- Limpeza
DROP TABLE IF EXISTS #bh;
DROP TABLE IF EXISTS #med;
DROP TABLE IF EXISTS #mad;
DROP TABLE IF EXISTS #classificacao;
