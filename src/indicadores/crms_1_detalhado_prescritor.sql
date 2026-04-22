-- ============================================================================
-- GERADOR DE DADOS PARA INDICADOR DE CRMs - VERSÃO 5
-- ============================================================================
-- ALTERAÇÕES v5 (sobre v4):
--   1. alertas_crm_concentracao: tabela master diária, fonte única de verdade
--      para alertas temporais. Inclui competencia para joins diretos.
--      Elimina alertas_crm_diario e a duplicação com #lista_alertas_temp.
--   2. alertas_crm_registro: unifica crm_invalido + crm_irregular_registro.
--      Adiciona competencia (grain mensal) e vl_prescricoes (impacto financeiro).
--      Elimina as tabelas crm_invalido e crm_irregular_registro.
--   3. alertas_crm_geografico: master geográfica — distancia_km DECIMAL,
--      pares de CNPJs estruturados. Self-join pesado roda uma única vez.
--   4. alertas_crm: refatorada para flags/BITs (flag_concentracao, flag_geografico,
--      flag_registro, qtd_dias_concentracao). Movida para após as 3 masters.
--   5. crm_export: textos gerados via LEFT JOIN nas masters; flags CFM por
--      competencia via alertas_crm_registro; JOIN em alertas_crm removido.
--   6. Turistas CTE: WHERE flag_geografico = 1 (antes: alerta_distancia_geografica IS NOT NULL).
--   7. alertas_pico_dispensacao → alertas_cnpj_pico (renomeada).
-- ============================================================================

DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim    DATE = '2024-12-31';


-- ============================================================================
-- PASSO 0: AGREGAÇÃO POR MÉDICO / FARMÁCIA / MÊS
-- Fonte dupla: histórico (até 2020) + recente (2021-2024)
-- ============================================================================
DROP TABLE IF EXISTS #base_agregada_crm_cnpj;

SELECT
    CONCAT(M.cnpj, '|', M.crm, '|', M.crm_uf, '|',
           CAST(YEAR(M.data_hora) * 100 + MONTH(M.data_hora) AS VARCHAR(6))) AS chave,
    M.crm                                         AS nu_crm,
    M.crm_uf                                      AS sg_uf_crm,
    M.cnpj                                        AS nu_cnpj,
    YEAR(M.data_hora) * 100 + MONTH(M.data_hora) AS competencia,
    COUNT(DISTINCT M.num_autorizacao)             AS nu_prescricoes_medico,
    SUM(M.valor_pago)                             AS vl_autorizacoes_medico,
    MIN(M.data_hora)                              AS dt_prescricao_inicial_medico,
    MAX(M.data_hora)                              AS dt_prescricao_final_medico
INTO #base_agregada_crm_cnpj
FROM temp_CGUSC.fp.teste_mov_SC M
INNER JOIN temp_CGUSC.fp.medicamentos_patologia PAT ON PAT.codigo_barra = M.codigo_barra
WHERE M.crm_uf IS NOT NULL AND M.crm IS NOT NULL AND M.crm_uf <> 'BR'
  AND M.data_hora >= @DataInicio AND M.data_hora <= @DataFim
GROUP BY M.crm, M.crm_uf, M.cnpj, YEAR(M.data_hora), MONTH(M.data_hora);

CREATE CLUSTERED INDEX IDX_BaseAgreg_Key ON #base_agregada_crm_cnpj(nu_cnpj, nu_crm, competencia);



-- ============================================================================
-- PASSO 0.1: ESTABELECIMENTO - PERFIL HORÁRIO E DIÁRIO (Detecção de Surtos)
-- Necessário calcular antes para identificar quais médicos participaram dos surtos.
-- ============================================================================

-- Scan Único na movimentação para base horária
DROP TABLE IF EXISTS #mov_surto_base;
SELECT
    cnpj,
    data_hora,
    crm,
    crm_uf,
    num_autorizacao,
    valor_pago
INTO #mov_surto_base
FROM temp_CGUSC.fp.teste_mov_SC
WHERE data_hora >= @DataInicio AND data_hora <= @DataFim
  AND crm IS NOT NULL AND crm_uf IS NOT NULL AND crm_uf <> 'BR';

CREATE CLUSTERED INDEX IDX_TempMov ON #mov_surto_base(cnpj, data_hora);

-- Materialização da base horária com volume e diversidade de CRMs
DROP TABLE IF EXISTS #base_horaria;
SELECT
    cnpj,
    YEAR(data_hora) * 100 + MONTH(data_hora) AS competencia,
    CAST(data_hora AS DATE)                   AS dt_janela,
    DATEPART(HOUR, data_hora)                 AS hr_janela,
    COUNT(DISTINCT num_autorizacao)           AS nu_prescricoes_hora,
    COUNT(DISTINCT crm)                       AS nu_crms_distintos_hora
INTO #base_horaria
FROM #mov_surto_base
GROUP BY cnpj, YEAR(data_hora), MONTH(data_hora), CAST(data_hora AS DATE), DATEPART(HOUR, data_hora);

CREATE CLUSTERED INDEX IDX_BH ON #base_horaria(cnpj, dt_janela, hr_janela);

-- Cálculo de Medianas e Detecção de Surtos (Regra: 7x Mediana e Min 10)
DROP TABLE IF EXISTS #mediana_hora;
SELECT DISTINCT
    cnpj, competencia, hr_janela,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY nu_prescricoes_hora)
        OVER (PARTITION BY cnpj, (competencia / 100), ((competencia % 100 - 1) / 3), hr_janela) AS mediana_hora
INTO #mediana_hora
FROM #base_horaria;

DROP TABLE IF EXISTS #anomalias_horarias;
SELECT
    H.*,
    CAST(M.mediana_hora AS DECIMAL(10,2)) AS mediana_hora,
    CASE WHEN H.nu_prescricoes_hora >= 10 
          AND H.nu_prescricoes_hora >= CAST(M.mediana_hora AS DECIMAL(10,2)) * 7 
         THEN 1 ELSE 0 END AS is_anomalo_hora
INTO #anomalias_horarias
FROM #base_horaria H
INNER JOIN #mediana_hora M ON M.cnpj = H.cnpj 
                         AND M.competencia = H.competencia 
                         AND M.hr_janela = H.hr_janela;

-- Identifica quais CRMs participaram de algum surto no CNPJ/Competencia
DROP TABLE IF EXISTS #crms_em_surto;
SELECT DISTINCT
    M.cnpj                                        AS nu_cnpj,
    CAST(M.crm AS VARCHAR(10)) + '/' + M.crm_uf   AS id_medico,
    YEAR(M.data_hora) * 100 + MONTH(M.data_hora)  AS competencia
INTO #crms_em_surto
FROM #mov_surto_base M
INNER JOIN #anomalias_horarias A ON A.cnpj = M.cnpj
    AND A.dt_janela = CAST(M.data_hora AS DATE)
    AND A.hr_janela = DATEPART(HOUR, M.data_hora)
WHERE A.is_anomalo_hora = 1;

CREATE CLUSTERED INDEX IDX_SurtoCRM ON #crms_em_surto(nu_cnpj, id_medico, competencia);

-- TOTAIS DIARIOS PARA MEDIANA DIARIA
DROP TABLE IF EXISTS #totais_diarios;
SELECT
    cnpj, competencia, dt_janela,
    SUM(nu_prescricoes_hora) AS nu_prescricoes_dia,
    MAX(is_anomalo_hora)     AS dia_tem_anomalia_hora
INTO #totais_diarios
FROM #anomalias_horarias
GROUP BY cnpj, competencia, dt_janela;

DROP TABLE IF EXISTS #mediana_diaria;
SELECT DISTINCT
    cnpj, competencia,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY nu_prescricoes_dia)
        OVER (PARTITION BY cnpj, (competencia / 100), ((competencia % 100 - 1) / 3)) AS mediana_diaria
INTO #mediana_diaria
FROM #totais_diarios;

-- 4. Tabela Final 1: crm_daily_profile (Gráfico Principal)
DROP TABLE IF EXISTS temp_CGUSC.fp.crm_daily_profile;

WITH pico_horario AS (
    SELECT
        cnpj, dt_janela,
        hr_janela AS hr_pico,
        nu_prescricoes_hora AS nu_prescricoes_hr_pico,
        ROW_NUMBER() OVER (PARTITION BY cnpj, dt_janela ORDER BY nu_prescricoes_hora DESC, hr_janela ASC) AS rn
    FROM #base_horaria
),
crms_distintos_dia AS (
    SELECT
        cnpj, 
        CAST(data_hora AS DATE) AS dt_janela,
        COUNT(DISTINCT crm) AS nu_crms_distintos
    FROM #mov_surto_base
    GROUP BY cnpj, CAST(data_hora AS DATE)
)
SELECT
    T.cnpj, T.competencia, T.dt_janela, T.nu_prescricoes_dia,
    ISNULL(C.nu_crms_distintos, 0) AS nu_crms_distintos,
    P.hr_pico, P.nu_prescricoes_hr_pico,
    CAST(M.mediana_diaria AS DECIMAL(10,2)) AS mediana_diaria,
    CAST(CAST(T.nu_prescricoes_dia AS DECIMAL(10,2)) / NULLIF(M.mediana_diaria, 0) AS DECIMAL(10,2)) AS multiplo,
    -- O dia é anômalo se tiver uma rajada horária (Regra Standard 7x Mediana)
    T.dia_tem_anomalia_hora AS is_anomalo
INTO temp_CGUSC.fp.crm_daily_profile
FROM #totais_diarios T
INNER JOIN #mediana_diaria M ON M.cnpj = T.cnpj AND M.competencia = T.competencia
INNER JOIN pico_horario P ON P.cnpj = T.cnpj AND P.dt_janela = T.dt_janela AND P.rn = 1
LEFT JOIN crms_distintos_dia C ON C.cnpj = T.cnpj AND C.dt_janela = T.dt_janela;

CREATE CLUSTERED INDEX IDX_DailyProfile ON temp_CGUSC.fp.crm_daily_profile(cnpj, dt_janela);

-- 5. Tabela Final 2: crm_hourly_profile_anomalo (Drill-down)
DROP TABLE IF EXISTS temp_CGUSC.fp.crm_hourly_profile_anomalo;

SELECT 
    H.cnpj,
    H.dt_janela,
    H.hr_janela,
    H.nu_prescricoes_hora AS nu_prescricoes,
    H.nu_crms_distintos_hora AS nu_crms_diferentes,
    H.mediana_hora AS mediana_hora,
    H.is_anomalo_hora
INTO temp_CGUSC.fp.crm_hourly_profile_anomalo
FROM #anomalias_horarias H
INNER JOIN temp_CGUSC.fp.crm_daily_profile D ON D.cnpj = H.cnpj AND D.dt_janela = H.dt_janela
WHERE D.is_anomalo = 1;

CREATE CLUSTERED INDEX IDX_HourlyAnomalo ON temp_CGUSC.fp.crm_hourly_profile_anomalo(cnpj, dt_janela, hr_janela);

-- 6. Tabela Final 3: alertas_cnpj_concentracao_sequencial (Mestre de Surtos)
DROP TABLE IF EXISTS temp_CGUSC.fp.alertas_cnpj_concentracao_sequencial;

SELECT
    cnpj, competencia, dt_janela AS dt_alerta, hr_janela,
    nu_prescricoes_hora AS nu_prescricoes,
    nu_crms_distintos_hora AS nu_crms,
    mediana_hora,
    CAST(CAST(nu_prescricoes_hora AS DECIMAL(10,2)) / NULLIF(mediana_hora, 0) AS DECIMAL(10,1)) AS multiplicador,
    'Surto de Volume' AS nivel,
    CAST(
        'Surto de Volume: ' + CAST(nu_prescricoes_hora AS VARCHAR(10)) + 
        ' prescrições às ' + RIGHT('0' + CAST(hr_janela AS VARCHAR(2)), 2) + 'h (' + 
        CAST(CAST(CAST(nu_prescricoes_hora AS DECIMAL(10,2)) / NULLIF(mediana_hora, 0) AS DECIMAL(10,1)) AS VARCHAR(10)) + 
        'x acima da mediana trimestral da farmácia: ' + CAST(CAST(mediana_hora AS DECIMAL(10,1)) AS VARCHAR(10)) + '/h).'
    AS VARCHAR(800)) AS descricao
INTO temp_CGUSC.fp.alertas_cnpj_concentracao_sequencial
FROM #anomalias_horarias
WHERE is_anomalo_hora = 1;

CREATE CLUSTERED INDEX IDX_AlertaSequencialCNPJ ON temp_CGUSC.fp.alertas_cnpj_concentracao_sequencial(cnpj, dt_alerta, hr_janela);

-- 7. Tabela Final 4: alertas_cnpj_concentracao_sequencial_detalhe (Raio-X Sub-horário)
-- Salva apenas o detalhamento das transações (minutos, segundos, numero nativo) das horas doentes.
DROP TABLE IF EXISTS temp_CGUSC.fp.alertas_cnpj_concentracao_sequencial_detalhe;

SELECT
    A.cnpj,
    A.competencia,
    A.dt_alerta                  AS dt_janela,
    A.hr_janela,
    MIN(M.data_hora)             AS data_hora,
    M.num_autorizacao,
    M.crm,
    M.crm_uf,
    COUNT(*)                     AS nu_medicamentos,
    SUM(M.valor_pago)            AS vl_autorizacao
INTO temp_CGUSC.fp.alertas_cnpj_concentracao_sequencial_detalhe
FROM temp_CGUSC.fp.alertas_cnpj_concentracao_sequencial A
INNER JOIN #mov_surto_base M
    ON  M.cnpj = A.cnpj
    AND CAST(M.data_hora AS DATE) = A.dt_alerta
    AND DATEPART(HOUR, M.data_hora) = A.hr_janela
GROUP BY A.cnpj, A.competencia, A.dt_alerta, A.hr_janela,
         M.num_autorizacao, M.crm, M.crm_uf;

CREATE CLUSTERED INDEX IDX_AlertaSeqDetalhe ON temp_CGUSC.fp.alertas_cnpj_concentracao_sequencial_detalhe(cnpj, dt_janela, hr_janela);

-- ============================================================================
-- PASSO 0.2: AGREGAÇÃO DIÁRIA POR MÉDICO / FARMÁCIA
-- O grain mensal do #base_agregada dilui rajadas intra-mês quando há
-- prescrições esparsas no mesmo mês (MIN/MAX do mês inteiro → taxa baixa).
-- Este passo detecta o pior dia de cada combinação (cnpj, crm, mês).
-- ============================================================================
DROP TABLE IF EXISTS #base_diaria_crm;

SELECT
    M.crm                                             AS nu_crm,
    M.crm_uf                                          AS sg_uf_crm,
    M.cnpj                                            AS nu_cnpj,
    YEAR(M.data_hora) * 100 + MONTH(M.data_hora)     AS competencia,
    CAST(M.data_hora AS DATE)                         AS dt_dia,
    COUNT(DISTINCT M.num_autorizacao)                 AS nu_prescricoes_dia,
    MIN(M.data_hora)                                  AS dt_ini_dia,
    MAX(M.data_hora)                                  AS dt_fim_dia,
    DATEDIFF(MINUTE, MIN(M.data_hora), MAX(M.data_hora)) AS nu_minutos_dia
INTO #base_diaria_crm
FROM temp_CGUSC.fp.teste_mov_SC M
INNER JOIN temp_CGUSC.fp.medicamentos_patologia PAT ON PAT.codigo_barra = M.codigo_barra
WHERE M.crm_uf IS NOT NULL AND M.crm IS NOT NULL AND M.crm_uf <> 'BR'
  AND M.data_hora >= @DataInicio AND M.data_hora <= @DataFim
GROUP BY M.crm, M.crm_uf, M.cnpj,
         YEAR(M.data_hora), MONTH(M.data_hora),
         CAST(M.data_hora AS DATE);

CREATE CLUSTERED INDEX IDX_BaseDiaria ON #base_diaria_crm(nu_cnpj, nu_crm, sg_uf_crm, competencia);


-- ============================================================================
-- PASSO 0.3: PIOR DIA POR (CNPJ / CRM / MÊS)
-- Seleciona o dia com maior potencial de alerta dentro do mês.
-- Prioridade: simultâneo > rajada/volume extremo > concentração > sem alerta.
-- Dentro do mesmo nível, prioriza maior taxa e maior volume.
-- ============================================================================
DROP TABLE IF EXISTS #pior_dia_crm;

WITH ranked AS (
    SELECT
        nu_cnpj, nu_crm, sg_uf_crm, competencia,
        dt_dia, nu_prescricoes_dia, dt_ini_dia, dt_fim_dia, nu_minutos_dia,
        CASE
            WHEN nu_minutos_dia = 0 THEN 999.0
            ELSE CAST(nu_prescricoes_dia AS DECIMAL(10,2)) /
                 (CAST(nu_minutos_dia AS DECIMAL(10,2)) / 60.0)
        END AS taxa_dia,
        ROW_NUMBER() OVER (
            PARTITION BY nu_cnpj, nu_crm, sg_uf_crm, competencia
            ORDER BY
                CASE
                    WHEN nu_prescricoes_dia >= 5  AND nu_minutos_dia = 0                                                                                                                                             THEN 1
                    WHEN nu_prescricoes_dia >= 5  AND nu_minutos_dia BETWEEN 1 AND 1440 AND CAST(nu_prescricoes_dia AS DECIMAL) / (CAST(nu_minutos_dia AS DECIMAL) / 60.0) >= 6                                      THEN 2
                    WHEN nu_prescricoes_dia >= 5  AND nu_minutos_dia > 1440             AND CAST(nu_prescricoes_dia AS DECIMAL) / (CAST(nu_minutos_dia AS DECIMAL) / 60.0) >= 6                                      THEN 3
                    WHEN nu_prescricoes_dia >= 10 AND (CAST(nu_prescricoes_dia AS DECIMAL) / NULLIF(CAST(nu_minutos_dia AS DECIMAL) / 60.0, 0) >= 3 OR nu_minutos_dia <= 120)                                        THEN 4
                    ELSE 99
                END ASC,
                CAST(nu_prescricoes_dia AS DECIMAL) / NULLIF(CAST(nu_minutos_dia AS DECIMAL) / 60.0, 0) DESC,
                nu_prescricoes_dia DESC
        ) AS rn
    FROM #base_diaria_crm
    WHERE nu_prescricoes_dia >= 5
)
SELECT nu_cnpj, nu_crm, sg_uf_crm, competencia,
       dt_dia, nu_prescricoes_dia, dt_ini_dia, dt_fim_dia, nu_minutos_dia, taxa_dia
INTO #pior_dia_crm
FROM ranked
WHERE rn = 1;

CREATE CLUSTERED INDEX IDX_PiorDia ON #pior_dia_crm(nu_cnpj, nu_crm, sg_uf_crm, competencia);


-- ============================================================================
-- PASSO 0.1: TOTAIS POR ESTABELECIMENTO / MÊS
-- Fonte dupla: histórico (até 2020) + recente (2021-2024)
-- ============================================================================
DROP TABLE IF EXISTS #tb_info_estabelecimento;

SELECT
    cnpj,
    YEAR(data_hora) * 100 + MONTH(data_hora) AS competencia,
    COUNT(DISTINCT num_autorizacao)           AS nu_autorizacoes_estabelecimento,
    SUM(valor_pago)                           AS vl_autorizacoes_estabelecimento,
    MIN(data_hora)                            AS dt_venda_inicial_estabelecimento,
    MAX(data_hora)                            AS dt_venda_final_estabelecimento
INTO #tb_info_estabelecimento
FROM temp_CGUSC.fp.teste_mov_SC M
WHERE data_hora >= @DataInicio AND data_hora <= @DataFim
GROUP BY cnpj, YEAR(data_hora), MONTH(data_hora);
GO
-- GO: base_agregada_crm_cnpj e #tb_info_estabelecimento existem com schema novo antes do próximo batch.


-- ============================================================================
-- BASE TEMPORÁRIA PARA ALERTAS
-- (substitui #lista_medicos_farmacia_popularFP_temp e _temp2)
-- ============================================================================
DROP TABLE IF EXISTS #lista_alertas_temp;
GO

SELECT
    A.nu_cnpj,
    A.nu_crm,
    A.sg_uf_crm,
    CAST(A.nu_crm AS VARCHAR(10)) + '/' + A.sg_uf_crm AS id_medico,
    A.competencia,
    A.nu_prescricoes_medico,
    A.vl_autorizacoes_medico,
    A.dt_prescricao_inicial_medico,
    A.dt_prescricao_final_medico,
    DATEDIFF(DAY, A.dt_prescricao_inicial_medico, A.dt_prescricao_final_medico) + 1 AS nu_dias,
    -- Para o alerta: usa o pior dia (evita diluição por prescrições esparsas no mês)
    ISNULL(P.nu_prescricoes_dia,
           A.nu_prescricoes_medico)                                                  AS nu_prescricoes_alerta,
    ISNULL(P.nu_minutos_dia,
           DATEDIFF(MINUTE, A.dt_prescricao_inicial_medico, A.dt_prescricao_final_medico)) AS nu_minutos,
    ISNULL(P.taxa_dia,
        CASE
            WHEN DATEDIFF(MINUTE, A.dt_prescricao_inicial_medico, A.dt_prescricao_final_medico) = 0 THEN 999.0
            ELSE CAST(A.nu_prescricoes_medico AS DECIMAL(10,2)) /
                 (CAST(DATEDIFF(MINUTE, A.dt_prescricao_inicial_medico, A.dt_prescricao_final_medico) AS DECIMAL(10,2)) / 60.0)
        END)                                                                         AS taxa_prescricoes_hora,
    C.nu_autorizacoes_estabelecimento,
    C.dt_venda_inicial_estabelecimento,
    C.dt_venda_final_estabelecimento,
    TRY_CAST(A.nu_prescricoes_medico AS DECIMAL(10,2)) /
        NULLIF(TRY_CAST(C.nu_autorizacoes_estabelecimento AS DECIMAL(10,2)), 0) AS percentual
INTO #lista_alertas_temp
FROM #base_agregada_crm_cnpj A
INNER JOIN #tb_info_estabelecimento C ON C.cnpj = A.nu_cnpj AND C.competencia = A.competencia
LEFT JOIN #pior_dia_crm P
    ON  P.nu_cnpj     = A.nu_cnpj
    AND P.nu_crm      = A.nu_crm
    AND P.sg_uf_crm   = A.sg_uf_crm
    AND P.competencia = A.competencia
-- Piso de 5 prescrições OU participação em surto detectado
WHERE (A.nu_prescricoes_medico >= 5)
   OR EXISTS (
        SELECT 1 FROM #crms_em_surto SR 
        WHERE SR.nu_cnpj = A.nu_cnpj 
          AND SR.id_medico = CAST(A.nu_crm AS VARCHAR(10)) + '/' + A.sg_uf_crm 
          AND SR.competencia = A.competencia
   );


GO


-- ============================================================================
-- TOTAIS NACIONAIS POR MÉDICO / COMPETÊNCIA
-- ============================================================================
DROP TABLE IF EXISTS #prescricoes_todos_estabelecimentos;

SELECT
    nu_crm,
    sg_uf_crm,
    competencia,
    SUM(nu_prescricoes_medico)                                    AS nu_prescricoes_medico_em_todos_estabelecimentos,
    COUNT(DISTINCT nu_cnpj)                                       AS nu_estabelecimentos_com_registro_mesmo_crm,
    CAST(SUM(nu_prescricoes_medico) AS DECIMAL(18,2)) /
        NULLIF(CAST(
            DATEDIFF(DAY, MIN(dt_prescricao_inicial_medico), MAX(dt_prescricao_final_medico)) + 1
        AS DECIMAL(18,2)), 0)                                     AS nu_prescricoes_dia_em_todos_estabelecimentos
INTO #prescricoes_todos_estabelecimentos
FROM #base_agregada_crm_cnpj
GROUP BY nu_crm, sg_uf_crm, competencia;
GO


-- ============================================================================
-- TABELA FINAL: dados_crm_detalhado
-- Sem colunas de alerta (ficam em alertas_crm) e sem nu_populacao.
-- Elimina a necessidade de #lista_medicos_farmacia_popularFP_temp2.
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.dados_crm_detalhado;

SELECT
    A.nu_cnpj,
    A.competencia,
    GEO.no_municipio,
    F.codibge,
    GEO.latitude,
    GEO.longitude,
    CAST(GEO.sg_uf AS VARCHAR(2))                                  AS sg_uf,
    A.nu_crm,
    A.sg_uf_crm,
    A.id_medico,
    A.nu_prescricoes_medico,
    P.nu_prescricoes_medico_em_todos_estabelecimentos,
    TRY_CAST(
        TRY_CAST(A.nu_prescricoes_medico AS DECIMAL(18,2)) /
        NULLIF(TRY_CAST(A.nu_dias AS DECIMAL(18,2)), 0)
    AS DECIMAL(18,2))                                              AS nu_prescricoes_dia,
    P.nu_prescricoes_dia_em_todos_estabelecimentos,
    P.nu_estabelecimentos_com_registro_mesmo_crm,
    A.nu_autorizacoes_estabelecimento,
    A.dt_prescricao_inicial_medico,
    A.dt_prescricao_final_medico,
    A.dt_venda_inicial_estabelecimento,
    A.dt_venda_final_estabelecimento,
    A.vl_autorizacoes_medico,
    A.percentual
INTO temp_CGUSC.fp.dados_crm_detalhado
FROM #lista_alertas_temp A
LEFT JOIN temp_CGUSC.fp.dados_farmacia            F   ON F.cnpj     = A.nu_cnpj
LEFT JOIN temp_CGUSC.sus.tb_ibge                  GEO ON GEO.id_ibge7 = F.codibge
INNER JOIN #prescricoes_todos_estabelecimentos    P
    ON  P.nu_crm      = A.nu_crm
    AND P.sg_uf_crm   = A.sg_uf_crm
    AND P.competencia = A.competencia;

CREATE NONCLUSTERED INDEX idx_dados_crm_detalhado_performance
    ON temp_CGUSC.fp.dados_crm_detalhado (id_medico, nu_cnpj, competencia)
    INCLUDE (latitude, longitude, dt_prescricao_inicial_medico, dt_prescricao_final_medico,
             no_municipio, sg_uf, nu_prescricoes_medico);
GO




-- ============================================================================
-- MOTOR TEMPORAL: alertas_crm_concentracao (v5 — Tabela Master Diária)
-- Grain: (cnpj, id_medico, dt_alerta)
-- Fonte única de verdade para alertas de concentração temporal.
-- Inclui competencia para joins diretos com a tabela de flags (Passo 4).
-- Elimina a duplicação de lógica entre #lista_alertas_temp e alertas_crm_diario.
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.alertas_crm_concentracao;

WITH base_com_taxa AS (
    SELECT
        nu_cnpj,
        nu_crm,
        sg_uf_crm,
        competencia,
        dt_dia,
        nu_prescricoes_dia,
        nu_minutos_dia,
        CASE WHEN nu_minutos_dia = 0 THEN 999.0
             ELSE CAST(nu_prescricoes_dia AS DECIMAL(10,2)) / (CAST(nu_minutos_dia AS DECIMAL(10,2)) / 60.0)
        END AS taxa_dia
    FROM #base_diaria_crm
),
alertas AS (
    SELECT
        nu_cnpj                                          AS cnpj,
        CAST(nu_crm AS VARCHAR(10)) + '/' + sg_uf_crm   AS id_medico,
        competencia,
        dt_dia                                           AS dt_alerta,
        nu_prescricoes_dia,
        nu_minutos_dia,
        CAST(taxa_dia AS DECIMAL(5,1))                   AS taxa_hora,
        CASE
            WHEN nu_prescricoes_dia >= 5  AND nu_minutos_dia = 0                                                                                             THEN 'Autorizações em Sequência'
            WHEN nu_prescricoes_dia >= 5  AND nu_minutos_dia BETWEEN 1 AND 1440 AND taxa_dia >= 6                                                            THEN 'Autorizações em Sequência'
            WHEN nu_prescricoes_dia >= 5  AND nu_minutos_dia > 1440             AND taxa_dia >= 6                                                            THEN 'Autorizações em Sequência'
            WHEN nu_prescricoes_dia >= 10 AND (taxa_dia >= 3 OR nu_minutos_dia <= 120)                                                                       THEN 'Autorizações em Sequência'
        END AS nivel
    FROM base_com_taxa
    WHERE
        (nu_prescricoes_dia >= 5  AND nu_minutos_dia = 0)
     OR (nu_prescricoes_dia >= 5  AND nu_minutos_dia BETWEEN 1 AND 1440 AND taxa_dia >= 6)
     OR (nu_prescricoes_dia >= 5  AND nu_minutos_dia > 1440             AND taxa_dia >= 6)
     OR (nu_prescricoes_dia >= 10 AND (taxa_dia >= 3 OR nu_minutos_dia <= 120))
)
SELECT * INTO temp_CGUSC.fp.alertas_crm_concentracao
FROM alertas
WHERE nivel IS NOT NULL;

CREATE CLUSTERED INDEX IDX_ConcTemp ON temp_CGUSC.fp.alertas_crm_concentracao(cnpj, id_medico, dt_alerta);

GO


-- ============================================================================
-- MOTOR GEOGRÁFICO: alertas_crm_geografico (v5 — Tabela Master)
-- Grain: (id_medico, competencia) — par mais crítico por médico/mês.
-- Armazena distancia_km como DECIMAL e os dois CNPJs como colunas estruturadas,
-- permitindo filtros, ordenação e analytics sem reprocessar o self-join.
-- O self-join pesado em dados_crm_detalhado agora roda uma única vez.
-- ============================================================================
PRINT '>> Processando Motor Geográfico (alertas_crm_geografico)...';

DROP TABLE IF EXISTS temp_CGUSC.fp.alertas_crm_geografico;

WITH
PairedWithDistance AS (
    SELECT
        T1.competencia,
        T1.id_medico,
        T1.nu_cnpj                      AS cnpj_a,
        T1.dt_prescricao_inicial_medico  AS dt_ini_a,
        T1.dt_prescricao_final_medico    AS dt_fim_a,
        T1.no_municipio                  AS no_municipio_a,
        T1.sg_uf                         AS sg_uf_a,
        T1.nu_prescricoes_medico         AS nu_prescricoes_a,
        T2.nu_cnpj                      AS cnpj_b,
        T2.dt_prescricao_inicial_medico  AS dt_ini_b,
        T2.dt_prescricao_final_medico    AS dt_fim_b,
        T2.no_municipio                  AS no_municipio_b,
        T2.sg_uf                         AS sg_uf_b,
        T2.nu_prescricoes_medico         AS nu_prescricoes_b,
        CASE
            WHEN (ABS(T1.latitude - T2.latitude) > 2.0 OR ABS(T1.longitude - T2.longitude) > 2.0)
            THEN temp_CGUSC.fp.fnCalcular_Distancia_KM(T1.latitude, T1.longitude, T2.latitude, T2.longitude)
            ELSE 0
        END AS distancia_km
    FROM temp_CGUSC.fp.dados_crm_detalhado T1
    INNER JOIN temp_CGUSC.fp.dados_crm_detalhado T2
        ON  T1.id_medico   = T2.id_medico
        AND T1.nu_cnpj     < T2.nu_cnpj
        AND T1.competencia = T2.competencia
),
ParesFiltrados AS (
    SELECT * FROM PairedWithDistance
    WHERE distancia_km > 400 AND nu_prescricoes_a >= 30 AND nu_prescricoes_b >= 30
),
ParesPriorizados AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY id_medico, competencia
            ORDER BY (nu_prescricoes_a + nu_prescricoes_b) DESC, distancia_km DESC
        ) AS rn
    FROM ParesFiltrados
),
TotaisPorMedico AS (
    SELECT id_medico, competencia, COUNT(*) AS total_pares
    FROM ParesPriorizados
    GROUP BY id_medico, competencia
)
SELECT
    P.id_medico,
    P.competencia,
    P.cnpj_a,
    P.no_municipio_a,
    CAST(P.sg_uf_a AS VARCHAR(2))          AS sg_uf_a,
    P.dt_ini_a,
    P.dt_fim_a,
    P.nu_prescricoes_a,
    P.cnpj_b,
    P.no_municipio_b,
    CAST(P.sg_uf_b AS VARCHAR(2))          AS sg_uf_b,
    P.dt_ini_b,
    P.dt_fim_b,
    P.nu_prescricoes_b,
    CAST(P.distancia_km AS DECIMAL(10,2))  AS distancia_km,
    T.total_pares
INTO temp_CGUSC.fp.alertas_crm_geografico
FROM ParesPriorizados P
INNER JOIN TotaisPorMedico T ON T.id_medico = P.id_medico AND T.competencia = P.competencia
WHERE P.rn = 1;

CREATE CLUSTERED INDEX IDX_GeoAlerta ON temp_CGUSC.fp.alertas_crm_geografico(id_medico, competencia);


GO


-- ============================================================================
-- MOTOR DE REGISTRO: alertas_crm_registro (v5 — Tabela Master)
-- Grain: (cnpj, id_medico, competencia, tipo_anomalia)
-- Unifica crm_invalido e crm_irregular_registro em entidade única.
-- Adiciona competencia (grain mensal) e vl_prescricoes (impacto financeiro),
-- permitindo ao dashboard mostrar "R$ X via CRMs inexistentes em competência Y".
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.alertas_crm_registro;

-- INEXISTENTE: CRM não encontrado no CFM
SELECT
    A.nu_cnpj                        AS cnpj,
    A.id_medico,
    A.nu_crm,
    A.sg_uf_crm,
    A.competencia,
    'INEXISTENTE'                    AS tipo_anomalia,
    CAST(NULL AS DATE)               AS dt_inscricao_crm,
    SUM(A.nu_prescricoes_medico)     AS nu_prescricoes,
    SUM(A.vl_autorizacoes_medico)    AS vl_prescricoes
INTO temp_CGUSC.fp.alertas_crm_registro
FROM #lista_alertas_temp A
LEFT JOIN temp_CFM.dbo.medicos_jul_2025_mod CFM
    ON  TRY_CAST(CFM.NU_CRM AS BIGINT) = TRY_CAST(A.nu_crm AS BIGINT)
    AND CFM.SG_uf = A.sg_uf_crm
WHERE CFM.NU_CRM IS NULL
GROUP BY A.nu_cnpj, A.id_medico, A.nu_crm, A.sg_uf_crm, A.competencia;

-- IRREGULAR: CRM existe no CFM mas prescrição ocorreu antes da data de inscrição
INSERT INTO temp_CGUSC.fp.alertas_crm_registro
    (cnpj, id_medico, nu_crm, sg_uf_crm, competencia,
     tipo_anomalia, dt_inscricao_crm, nu_prescricoes, vl_prescricoes)
SELECT
    A.nu_cnpj,
    A.id_medico,
    A.nu_crm,
    A.sg_uf_crm,
    A.competencia,
    'IRREGULAR'                              AS tipo_anomalia,
    TRY_CONVERT(DATE, CFM.DT_INSCRICAO, 103) AS dt_inscricao_crm,
    SUM(A.nu_prescricoes_medico)             AS nu_prescricoes,
    SUM(A.vl_autorizacoes_medico)            AS vl_prescricoes
FROM #lista_alertas_temp A
INNER JOIN temp_CFM.dbo.medicos_jul_2025_mod CFM
    ON  TRY_CAST(CFM.NU_CRM AS BIGINT) = TRY_CAST(A.nu_crm AS BIGINT)
    AND CFM.SG_uf = A.sg_uf_crm
WHERE A.dt_prescricao_inicial_medico < TRY_CONVERT(DATE, CFM.DT_INSCRICAO, 103)
GROUP BY A.nu_cnpj, A.id_medico, A.nu_crm, A.sg_uf_crm, A.competencia,
         TRY_CONVERT(DATE, CFM.DT_INSCRICAO, 103);

CREATE CLUSTERED INDEX IDX_Registro ON temp_CGUSC.fp.alertas_crm_registro(cnpj, id_medico, competencia);


GO


-- ============================================================================
-- CONSOLIDADOR: alertas_crm (v5 — Tabela de Flags/Metadados)
-- Grain: (nu_cnpj, id_medico, competencia) — uma linha por médico/farmácia/mês
-- com pelo menos um alerta ativo. Substitui VARCHAR(800) por flags BIT e
-- contador, permitindo dashboard instantâneo e lazy load de textos.
--   flag_concentracao:     1 se há alerta temporal ≥ 1 dia no mês
--   flag_geografico:       1 se este CNPJ é par em alerta de distância ≥ 400km
--   flag_registro:         1 se há anomalia CFM (INEXISTENTE ou IRREGULAR) no mês
--   qtd_dias_concentracao: total de dias com alerta temporal no mês
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.alertas_crm;

WITH base AS (
    SELECT DISTINCT cnpj AS nu_cnpj, id_medico, competencia
    FROM temp_CGUSC.fp.alertas_crm_concentracao
    UNION
    SELECT cnpj_a AS nu_cnpj, id_medico, competencia
    FROM temp_CGUSC.fp.alertas_crm_geografico
    UNION
    SELECT cnpj_b AS nu_cnpj, id_medico, competencia
    FROM temp_CGUSC.fp.alertas_crm_geografico
    UNION
    SELECT DISTINCT cnpj AS nu_cnpj, id_medico, competencia
    FROM temp_CGUSC.fp.alertas_crm_registro
    UNION
    SELECT nu_cnpj, id_medico, competencia
    FROM #crms_em_surto
),
conc_agg AS (
    SELECT cnpj, id_medico, competencia, COUNT(*) AS qtd_dias
    FROM temp_CGUSC.fp.alertas_crm_concentracao
    GROUP BY cnpj, id_medico, competencia
),
geo_cnpj AS (
    SELECT cnpj_a AS nu_cnpj, id_medico, competencia FROM temp_CGUSC.fp.alertas_crm_geografico
    UNION ALL
    SELECT cnpj_b AS nu_cnpj, id_medico, competencia FROM temp_CGUSC.fp.alertas_crm_geografico
)
SELECT
    B.nu_cnpj,
    B.id_medico,
    B.competencia,
    CAST(CASE WHEN CA.cnpj      IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS flag_concentracao,
    CAST(CASE WHEN GC.id_medico IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS flag_geografico,
    CAST(CASE WHEN RE.cnpj      IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS flag_registro,
    CAST(CASE WHEN SR.id_medico  IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS flag_concentracao_estabelecimento,
    ISNULL(CA.qtd_dias, 0)                                             AS qtd_dias_concentracao
INTO temp_CGUSC.fp.alertas_crm
FROM base B
LEFT JOIN conc_agg CA
    ON  CA.cnpj       = B.nu_cnpj
    AND CA.id_medico  = B.id_medico
    AND CA.competencia = B.competencia
LEFT JOIN #crms_em_surto SR
    ON  SR.nu_cnpj    = B.nu_cnpj
    AND SR.id_medico  = B.id_medico
    AND SR.competencia = B.competencia
LEFT JOIN geo_cnpj GC
    ON  GC.id_medico  = B.id_medico
    AND GC.competencia = B.competencia
    AND GC.nu_cnpj    = B.nu_cnpj
LEFT JOIN (
    SELECT DISTINCT cnpj, id_medico, competencia
    FROM temp_CGUSC.fp.alertas_crm_registro
) RE ON RE.cnpj = B.nu_cnpj AND RE.id_medico = B.id_medico AND RE.competencia = B.competencia;

CREATE CLUSTERED INDEX IDX_Alertas_Key ON temp_CGUSC.fp.alertas_crm(nu_cnpj, id_medico, competencia);
GO


-- ============================================================================
-- TABELA DE EXPORTAÇÃO: crm_export (v5)
-- Grain: (cnpj, id_medico, competencia) — base para geração dos parquets por CNPJ.
-- Textos de alerta gerados via LEFT JOIN nas master tables (sem reler alertas_crm).
-- Flags CFM derivadas de alertas_crm_registro por competencia (grain mensal).
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.crm_export;

SELECT
    A.nu_cnpj                                                         AS cnpj,
    A.id_medico,
    A.competencia,
    A.nu_prescricoes_medico                                           AS nu_prescricoes,
    A.vl_autorizacoes_medico                                          AS vl_total_prescricoes,
    TRY_CAST(
        TRY_CAST(A.nu_prescricoes_medico AS DECIMAL(18,2)) /
        NULLIF(TRY_CAST(A.nu_dias AS DECIMAL(18,2)), 0)
    AS DECIMAL(18,2))                                                 AS nu_prescricoes_dia,
    ISNULL(P.nu_prescricoes_dia_em_todos_estabelecimentos,  0)        AS prescricoes_dia_brasil,
    ISNULL(P.nu_prescricoes_medico_em_todos_estabelecimentos,
           A.nu_prescricoes_medico)                                   AS prescricoes_total_brasil,
    ISNULL(P.nu_estabelecimentos_com_registro_mesmo_crm, 1)           AS nu_estabelecimentos,
    CAST(CASE WHEN CONC.cnpj IS NOT NULL THEN 1 ELSE 0 END AS BIT)   AS flag_concentracao_mesmo_crm,
    -- Texto geográfico: gerado inline da master para este CNPJ
    CASE WHEN G.id_medico IS NOT NULL THEN
        'Em ' + RIGHT('0' + CAST(G.competencia % 100 AS VARCHAR(2)), 2) + '/' +
                CAST(G.competencia / 100 AS VARCHAR(4)) + ': ' +
        'A distância entre a farmácia ' +
            CASE WHEN LEN(G.cnpj_a) = 14
                 THEN SUBSTRING(G.cnpj_a,1,2)+'.'+SUBSTRING(G.cnpj_a,3,3)+'.'+
                      SUBSTRING(G.cnpj_a,6,3)+'/'+SUBSTRING(G.cnpj_a,9,4)+'-'+SUBSTRING(G.cnpj_a,13,2)
                 ELSE ISNULL(G.cnpj_a,'N/I') END +
        ' (' + ISNULL(G.no_municipio_a,'N/I') + '/' + ISNULL(G.sg_uf_a,'N/I') + ')' +
        ' - ' + CONVERT(VARCHAR, G.dt_ini_a, 103) + ' a ' + CONVERT(VARCHAR, G.dt_fim_a, 103) +
        ' (' + CAST(G.nu_prescricoes_a AS VARCHAR(10)) + ' prescrições)' +
        ' e a farmácia ' +
            CASE WHEN LEN(G.cnpj_b) = 14
                 THEN SUBSTRING(G.cnpj_b,1,2)+'.'+SUBSTRING(G.cnpj_b,3,3)+'.'+
                      SUBSTRING(G.cnpj_b,6,3)+'/'+SUBSTRING(G.cnpj_b,9,4)+'-'+SUBSTRING(G.cnpj_b,13,2)
                 ELSE ISNULL(G.cnpj_b,'N/I') END +
        ' (' + ISNULL(G.no_municipio_b,'N/I') + '/' + ISNULL(G.sg_uf_b,'N/I') + ')' +
        ' - ' + CONVERT(VARCHAR, G.dt_ini_b, 103) + ' a ' + CONVERT(VARCHAR, G.dt_fim_b, 103) +
        ' (' + CAST(G.nu_prescricoes_b AS VARCHAR(10)) + ' prescrições)' +
        ' é de ' + CAST(G.distancia_km AS VARCHAR(20)) + ' km.' +
        CASE WHEN G.total_pares > 1
             THEN ' Há também outros ' + CAST(G.total_pares - 1 AS VARCHAR(10)) +
                  ' pares de estabelecimentos com distância maior que 400km no mesmo período.'
             ELSE '' END
    END                                                               AS alerta_distancia_geografica,
    -- Flags CFM por competência (v5: grain mensal via alertas_crm_registro)
    CASE WHEN REG_INV.cnpj IS NOT NULL THEN 1 ELSE 0 END              AS flag_crm_invalido,
    CASE WHEN REG_IRR.cnpj IS NOT NULL THEN 1 ELSE 0 END              AS flag_prescricao_antes_registro,
    ISNULL(AL.flag_concentracao_estabelecimento, 0)                                           AS flag_concentracao_estabelecimento
INTO temp_CGUSC.fp.crm_export
FROM #lista_alertas_temp A
LEFT JOIN temp_CGUSC.fp.alertas_crm AL
    ON AL.nu_cnpj = A.nu_cnpj AND AL.id_medico = A.id_medico AND AL.competencia = A.competencia
INNER JOIN #prescricoes_todos_estabelecimentos P
    ON  P.nu_crm      = A.nu_crm
    AND P.sg_uf_crm   = A.sg_uf_crm
    AND P.competencia = A.competencia
LEFT JOIN (
    SELECT DISTINCT cnpj, id_medico, competencia
    FROM temp_CGUSC.fp.alertas_crm_concentracao
) CONC
    ON  CONC.cnpj        = A.nu_cnpj
    AND CONC.id_medico   = A.id_medico
    AND CONC.competencia = A.competencia
LEFT JOIN temp_CGUSC.fp.alertas_crm_geografico G
    ON  G.id_medico   = A.id_medico
    AND G.competencia = A.competencia
    AND (G.cnpj_a = A.nu_cnpj OR G.cnpj_b = A.nu_cnpj)
LEFT JOIN temp_CGUSC.fp.alertas_crm_registro REG_INV
    ON  REG_INV.cnpj          = A.nu_cnpj
    AND REG_INV.id_medico     = A.id_medico
    AND REG_INV.competencia   = A.competencia
    AND REG_INV.tipo_anomalia = 'INEXISTENTE'
LEFT JOIN temp_CGUSC.fp.alertas_crm_registro REG_IRR
    ON  REG_IRR.cnpj          = A.nu_cnpj
    AND REG_IRR.id_medico     = A.id_medico
    AND REG_IRR.competencia   = A.competencia
    AND REG_IRR.tipo_anomalia = 'IRREGULAR';

CREATE CLUSTERED INDEX IDX_CrmExport_Key
    ON temp_CGUSC.fp.crm_export(cnpj, competencia, id_medico);
GO


-- ============================================================================
-- BASE PARA BENCHMARKS: #indicador_crm (temp)
-- Grain: (cnpj, competencia) — métricas resumidas por farmácia/mês.
-- Colapsa os steps 1-12 do crms_2 em CTEs sobre crm_export.
-- Não é persistida: existe apenas para alimentar as 4 tabelas de benchmark abaixo.
-- ============================================================================
DROP TABLE IF EXISTS #indicador_crm;

WITH
Totais AS (
    SELECT
        cnpj,
        competencia,
        SUM(nu_prescricoes)       AS total_prescricoes,
        SUM(vl_total_prescricoes) AS total_valor,
        COUNT(DISTINCT id_medico) AS total_prescritores
    FROM temp_CGUSC.fp.crm_export
    GROUP BY cnpj, competencia
),
Top5 AS (
    SELECT
        cnpj, competencia,
        MAX(CASE WHEN rk = 1 THEN id_medico END)                           AS id_top1,
        SUM(CASE WHEN rk = 1 THEN vl_total_prescricoes ELSE 0 END)         AS vl_top1,
        SUM(CASE WHEN rk <= 5 THEN vl_total_prescricoes ELSE 0 END)        AS vl_top5
    FROM (
        SELECT cnpj, competencia, id_medico, vl_total_prescricoes,
               ROW_NUMBER() OVER (PARTITION BY cnpj, competencia
                                  ORDER BY vl_total_prescricoes DESC) AS rk
        FROM temp_CGUSC.fp.crm_export
    ) R
    WHERE rk <= 5
    GROUP BY cnpj, competencia
),
Anomalias AS (
    SELECT
        cnpj, competencia,
        COUNT(CASE WHEN nu_prescricoes_dia > 30                                          THEN 1 END) AS qtd_robos,
        COUNT(CASE WHEN flag_crm_invalido = 1                                            THEN 1 END) AS qtd_crm_invalido,
        COUNT(CASE WHEN flag_prescricao_antes_registro = 1                               THEN 1 END) AS qtd_antes_registro,
        COUNT(CASE WHEN nu_prescricoes_dia <= 30
                    AND prescricoes_dia_brasil > 30                                      THEN 1 END) AS qtd_robos_ocultos,
        COUNT(CASE WHEN nu_estabelecimentos > 70                                         THEN 1 END) AS qtd_multi_farmacia,
        AVG(CAST(nu_estabelecimentos AS DECIMAL(18,4)))                                             AS indice_rede_suspeita
    FROM temp_CGUSC.fp.crm_export
    GROUP BY cnpj, competencia
),
HHI AS (
    SELECT
        E.cnpj, E.competencia,
        SUM(POWER(
            CAST(E.vl_total_prescricoes AS DECIMAL(18,4)) /
            NULLIF(CAST(T.total_valor   AS DECIMAL(18,4)), 0) * 100.0
        , 2)) AS indice_hhi
    FROM temp_CGUSC.fp.crm_export E
    INNER JOIN Totais T ON T.cnpj = E.cnpj AND T.competencia = E.competencia
    GROUP BY E.cnpj, E.competencia
),
Turistas AS (
    SELECT nu_cnpj AS cnpj, competencia,
           COUNT(DISTINCT id_medico) AS qtd_turistas
    FROM temp_CGUSC.fp.alertas_crm
    WHERE flag_geografico = 1
    GROUP BY nu_cnpj, competencia
)

SELECT
    T.cnpj                                                                                      AS nu_cnpj,
    T.competencia,
    T.total_prescricoes,
    T.total_valor,
    T.total_prescritores,
    ISNULL(CAST(T5.vl_top1 AS DECIMAL(18,2)) / NULLIF(CAST(T.total_valor AS DECIMAL(18,2)), 0) * 100.0, 0) AS pct_concentracao_top1,
    ISNULL(T5.id_top1, '')                                                                      AS id_top1_prescritor,
    ISNULL(CAST(T5.vl_top5 AS DECIMAL(18,2)) / NULLIF(CAST(T.total_valor AS DECIMAL(18,2)), 0) * 100.0, 0) AS pct_concentracao_top5,
    ISNULL(H.indice_hhi, 0)                                                                     AS indice_hhi,
    ISNULL(AN.qtd_robos, 0)                                                                     AS qtd_prescritores_robos,
    ISNULL(AN.qtd_crm_invalido, 0)                                                              AS qtd_crm_invalido,
    ISNULL(AN.qtd_antes_registro, 0)                                                            AS qtd_crm_antes_registro,
    ISNULL(TU.qtd_turistas, 0)                                                                  AS qtd_prescritores_turistas,
    ISNULL(AN.qtd_robos_ocultos, 0)                                                             AS qtd_prescritores_robos_ocultos,
    ISNULL(AN.qtd_multi_farmacia, 0)                                                            AS qtd_prescritores_multi_farmacia,
    ISNULL(AN.indice_rede_suspeita, 1.0)                                                        AS indice_rede_suspeita
INTO #indicador_crm
FROM Totais T
LEFT JOIN Top5      T5 ON T5.cnpj = T.cnpj AND T5.competencia = T.competencia
LEFT JOIN HHI        H ON  H.cnpj = T.cnpj AND  H.competencia = T.competencia
LEFT JOIN Anomalias AN ON AN.cnpj = T.cnpj AND AN.competencia = T.competencia
LEFT JOIN Turistas  TU ON TU.cnpj = T.cnpj AND TU.competencia = T.competencia;

CREATE CLUSTERED INDEX IDX_IndCrm ON #indicador_crm(nu_cnpj, competencia);
GO


-- ============================================================================
-- BENCHMARK POR UF / COMPETÊNCIA
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crm_bench_uf;

WITH CTE AS (
    SELECT DISTINCT
        CAST(F.uf AS VARCHAR(2)) AS uf,
        I.competencia,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.pct_concentracao_top1, 0))  OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), I.competencia) AS mediana_concentracao_uf,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.pct_concentracao_top5, 0))  OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), I.competencia) AS mediana_concentracao_top5_uf,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.indice_hhi, 0))             OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), I.competencia) AS mediana_hhi_uf,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.qtd_prescritores_robos, 0)) OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), I.competencia) AS mediana_robos_uf,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(CAST(
            CASE WHEN I.total_prescritores > 0
                 THEN I.qtd_crm_invalido * 100.0 / I.total_prescritores
                 ELSE 0 END AS DECIMAL(18,4)), 0))                                        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), I.competencia) AS mediana_pct_crm_invalido_uf,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.qtd_prescritores_turistas, 0)) OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), I.competencia) AS mediana_turistas_uf,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.indice_rede_suspeita, 0))   OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), I.competencia) AS mediana_indice_rede_uf
    FROM #indicador_crm I
    INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.nu_cnpj
)
SELECT * INTO temp_CGUSC.fp.indicador_crm_bench_uf FROM CTE;

CREATE CLUSTERED INDEX IDX_BenchUF ON temp_CGUSC.fp.indicador_crm_bench_uf(uf, competencia);


-- ============================================================================
-- BENCHMARK POR REGIÃO DE SAÚDE / COMPETÊNCIA
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crm_bench_regiao;

WITH CTE AS (
    SELECT DISTINCT
        F.id_regiao_saude,
        I.competencia,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.indice_hhi, 0))                OVER (PARTITION BY F.id_regiao_saude, I.competencia) AS mediana_hhi_reg,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.pct_concentracao_top1, 0))     OVER (PARTITION BY F.id_regiao_saude, I.competencia) AS mediana_concentracao_reg,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.pct_concentracao_top5, 0))     OVER (PARTITION BY F.id_regiao_saude, I.competencia) AS mediana_concentracao_top5_reg,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(CAST(
            CASE WHEN I.total_prescritores > 0
                 THEN I.qtd_crm_invalido * 100.0 / I.total_prescritores
                 ELSE 0 END AS DECIMAL(18,4)), 0))                                           OVER (PARTITION BY F.id_regiao_saude, I.competencia) AS mediana_crm_invalido_reg,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.qtd_prescritores_robos, 0))    OVER (PARTITION BY F.id_regiao_saude, I.competencia) AS mediana_robos_reg,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.qtd_prescritores_turistas, 0)) OVER (PARTITION BY F.id_regiao_saude, I.competencia) AS mediana_turistas_reg,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.indice_rede_suspeita, 0))      OVER (PARTITION BY F.id_regiao_saude, I.competencia) AS mediana_indice_rede_reg
    FROM temp_CGUSC.fp.dados_farmacia F
    LEFT JOIN #indicador_crm I ON I.nu_cnpj = F.cnpj
    WHERE F.id_regiao_saude IS NOT NULL
)
SELECT * INTO temp_CGUSC.fp.indicador_crm_bench_regiao FROM CTE;

CREATE CLUSTERED INDEX IDX_BenchReg ON temp_CGUSC.fp.indicador_crm_bench_regiao(id_regiao_saude, competencia);


-- ============================================================================
-- BENCHMARK NACIONAL / COMPETÊNCIA
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crm_bench_br;

WITH CTE AS (
    SELECT DISTINCT
        I.competencia,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.pct_concentracao_top1, 0))     OVER (PARTITION BY I.competencia) AS mediana_concentracao_br,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.pct_concentracao_top5, 0))     OVER (PARTITION BY I.competencia) AS mediana_concentracao_top5_br,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.indice_hhi, 0))                OVER (PARTITION BY I.competencia) AS mediana_hhi_br,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.qtd_prescritores_robos, 0))    OVER (PARTITION BY I.competencia) AS mediana_robos_br,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(CAST(
            CASE WHEN I.total_prescritores > 0
                 THEN I.qtd_crm_invalido * 100.0 / I.total_prescritores
                 ELSE 0 END AS DECIMAL(18,4)), 0))                                           OVER (PARTITION BY I.competencia) AS mediana_pct_crm_invalido_br,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.qtd_prescritores_turistas, 0)) OVER (PARTITION BY I.competencia) AS mediana_turistas_br,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.indice_rede_suspeita, 0))      OVER (PARTITION BY I.competencia) AS mediana_indice_rede_br
    FROM #indicador_crm I
)
SELECT * INTO temp_CGUSC.fp.indicador_crm_bench_br FROM CTE;

CREATE CLUSTERED INDEX IDX_BenchBR ON temp_CGUSC.fp.indicador_crm_bench_br(competencia);
GO


-- ============================================================================
-- TABELA PARA MATRIZ DE RISCO: indicador_crm_hhi
-- Chave: cnpj (uma linha por farmácia, agregada sobre todas as competências)
-- Consumida por matriz_risco_final.sql como I15.
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crm_hhi;

WITH HHI_por_cnpj AS (
    SELECT
        I.nu_cnpj                   AS cnpj,
        AVG(I.indice_hhi)           AS indice_hhi,
        F.id_regiao_saude,
        CAST(F.uf AS VARCHAR(2))    AS uf
    FROM #indicador_crm I
    INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.nu_cnpj
    GROUP BY I.nu_cnpj, F.id_regiao_saude, F.uf
),
Bench AS (
    -- Mediana de HHI por UF (uma por UF, colapsa competencias)
    SELECT uf, AVG(mediana_hhi_uf) AS mediana_hhi_uf
    FROM temp_CGUSC.fp.indicador_crm_bench_uf
    GROUP BY uf
),
BenchReg AS (
    SELECT
        id_regiao_saude,
        AVG(mediana_hhi_reg)        AS mediana_hhi_reg
    FROM temp_CGUSC.fp.indicador_crm_bench_regiao
    GROUP BY id_regiao_saude
),
BenchBR AS (
    SELECT AVG(mediana_hhi_br) AS mediana_hhi_br
    FROM temp_CGUSC.fp.indicador_crm_bench_br
)

SELECT
    H.cnpj,
    CAST(H.indice_hhi AS DECIMAL(18,4))                                             AS indice_hhi,
    -- Medianas (compatíveis com os nomes que a matriz espera)
    ISNULL(CAST(BU.mediana_hhi_uf  AS DECIMAL(18,4)), 0)                            AS estado_mediana,
    ISNULL(CAST(BR.mediana_hhi_br  AS DECIMAL(18,4)), 0)                            AS pais_mediana,
    ISNULL(CAST(BR2.mediana_hhi_reg AS DECIMAL(18,4)), 0)                           AS regiao_saude_mediana,
    -- Riscos relativos
    CAST(CASE WHEN BU.mediana_hhi_uf  > 0 THEN (H.indice_hhi + 0.01) / (BU.mediana_hhi_uf  + 0.01) ELSE 0 END AS DECIMAL(18,4)) AS risco_relativo_uf_mediana,
    CAST(CASE WHEN BR.mediana_hhi_br  > 0 THEN (H.indice_hhi + 0.01) / (BR.mediana_hhi_br  + 0.01) ELSE 0 END AS DECIMAL(18,4)) AS risco_relativo_br_mediana,
    CAST(CASE WHEN BR2.mediana_hhi_reg > 0 THEN (H.indice_hhi + 0.01) / (BR2.mediana_hhi_reg + 0.01) ELSE 0 END AS DECIMAL(18,4)) AS risco_relativo_reg_mediana
INTO temp_CGUSC.fp.indicador_crm_hhi
FROM HHI_por_cnpj H
LEFT JOIN Bench   BU  ON BU.uf              = H.uf
LEFT JOIN BenchReg BR2 ON BR2.id_regiao_saude = H.id_regiao_saude
CROSS JOIN BenchBR BR;

CREATE CLUSTERED INDEX IDX_CrmHHI ON temp_CGUSC.fp.indicador_crm_hhi(cnpj);
GO


-- ============================================================================


-- ============================================================================
-- ALERTA PICO DE DISPENSAÇÃO: pior dia anômalo por (cnpj, competencia)
-- Derivado do crm_daily_profile — sem recalcular CTEs pesadas.
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.alertas_cnpj_pico;

SELECT
    cnpj,
    competencia,
    dt_janela,
    hr_pico,
    nu_prescricoes_dia,
    nu_prescricoes_hr_pico,
    nu_crms_distintos,
    mediana_diaria,
    multiplo,
    CAST(
        'Pico de dispensação: ' + CAST(nu_prescricoes_dia AS VARCHAR(10)) +
        ' prescrições em ' + CONVERT(VARCHAR, dt_janela, 103) +
        ' (pico às ' + RIGHT('0' + CAST(hr_pico AS VARCHAR(2)), 2) + 'h: ' +
        CAST(nu_prescricoes_hr_pico AS VARCHAR(10)) + ' prescrições), ' +
        CAST(nu_crms_distintos AS VARCHAR(10)) + ' CRMs distintos, ' +
        CAST(CAST(multiplo AS DECIMAL(5,1)) AS VARCHAR(10)) + 'x acima do padrão da farmácia'
    AS VARCHAR(800))                      AS alerta_pico_dispensacao
INTO temp_CGUSC.fp.alertas_cnpj_pico
FROM (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY cnpj, competencia
            ORDER BY nu_prescricoes_dia DESC
        ) AS rn
    FROM temp_CGUSC.fp.crm_daily_profile
    WHERE is_anomalo = 1
) X
WHERE rn = 1;

CREATE CLUSTERED INDEX IDX_PicoDispensacao
    ON temp_CGUSC.fp.alertas_cnpj_pico(cnpj, competencia);
GO


PRINT '============================================================================';
PRINT 'SCRIPT v5 EXECUTADO COM SUCESSO:';
PRINT '  - dados_crm_detalhado          : sem alertas, sem nu_populacao';
PRINT '  - alertas_crm_concentracao     : [v5] master diaria de alertas temporais (com competencia)';
PRINT '  - alertas_crm_geografico       : [v5] master geografica — distancia_km numerico + pares de CNPJs';
PRINT '  - alertas_crm                  : [v5] flags BIT — flag_concentracao/geografico/registro + qtd_dias_concentracao';
PRINT '  - alertas_crm_registro         : [v5] master CFM — INEXISTENTE/IRREGULAR por competencia + valor';
PRINT '  - crm_export                   : grain plano para exportacao de parquets por CNPJ';
PRINT '  - alertas_cnpj_pico            : [v5] pior dia anomalo por (cnpj, competencia)';
PRINT '  - indicador_crm_bench_{uf,regiao,br} : benchmarks de mediana por geografia/competencia';
PRINT '  - indicador_crm_hhi            : HHI por CNPJ (agregado) para matriz_risco_final.sql';
PRINT '============================================================================';
GO
