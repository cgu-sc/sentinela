-- ============================================================================
-- GERADOR DE DADOS PARA INDICADOR DE CRMs - VERSÃO 3
-- ============================================================================
-- ALTERAÇÕES v3:
--   1. Adicionada dimensão COMPETENCIA (YYYYMM INT) em toda a cadeia de agregação
--   2. Granularidade muda de (cnpj, crm) acumulado para (cnpj, crm, competencia)
--   3. Alerta 5: verificação de sobreposição de datas substituída por
--      T1.competencia = T2.competencia (mesmo mês = simultaneidade garantida)
--   4. Detecção de robô nacional calculada por (crm, crm_uf, competencia)
--   5. Coluna 'Conexao' removida (redundante com granularidade mensal)
-- ============================================================================

DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim    DATE = '2024-12-31';


-- ============================================================================
-- PASSO 0: AGREGAÇÃO POR MÉDICO / FARMÁCIA / MÊS
-- ============================================================================

-- A. Base Histórica (2015-2020)
DROP TABLE IF EXISTS #Medicos_Hist;
SELECT
    M.cnpj,
    M.crm,
    M.crm_uf,
    YEAR(M.data_hora) * 100 + MONTH(M.data_hora) AS competencia,
    COUNT(DISTINCT M.num_autorizacao)             AS nu_prescricoes,
    SUM(M.valor_pago)                             AS vl_pago,
    MIN(M.data_hora)                              AS dt_ini,
    MAX(M.data_hora)                              AS dt_fim
INTO #Medicos_Hist
FROM db_FarmaciaPopular.dbo.Relatorio_movimentacaoFP M
INNER JOIN temp_CGUSC.fp.medicamentos_patologia PAT ON PAT.codigo_barra = M.codigo_barra
WHERE M.crm_uf IS NOT NULL AND M.crm IS NOT NULL AND M.crm_uf <> 'BR'
  AND M.data_hora >= @DataInicio AND M.data_hora <= @DataFim
GROUP BY M.crm, M.crm_uf, M.cnpj, YEAR(M.data_hora), MONTH(M.data_hora);

-- B. Base Recente (2021-2024)
DROP TABLE IF EXISTS #Medicos_Recente;
SELECT
    M.cnpj,
    M.crm,
    M.crm_uf,
    YEAR(M.data_hora) * 100 + MONTH(M.data_hora) AS competencia,
    COUNT(DISTINCT M.num_autorizacao)             AS nu_prescricoes,
    SUM(M.valor_pago)                             AS vl_pago,
    MIN(M.data_hora)                              AS dt_ini,
    MAX(M.data_hora)                              AS dt_fim
INTO #Medicos_Recente
FROM db_FarmaciaPopular.carga_2024.relatorio_movimentacaoFP_2021_2024 M
INNER JOIN temp_CGUSC.fp.medicamentos_patologia PAT ON PAT.codigo_barra = M.codigo_barra
WHERE M.crm_uf IS NOT NULL AND M.crm IS NOT NULL AND M.crm_uf <> 'BR'
  AND M.data_hora >= @DataInicio AND M.data_hora <= @DataFim
GROUP BY M.crm, M.crm_uf, M.cnpj, YEAR(M.data_hora), MONTH(M.data_hora);

-- C. União Final dos Médicos
DROP TABLE IF EXISTS temp_CGUSC.fp.base_agregada_crm_cnpj;
SELECT
    CONCAT(cnpj, '|', crm, '|', crm_uf, '|', CAST(competencia AS VARCHAR(6))) AS chave,
    crm        AS nu_crm,
    crm_uf     AS sg_uf_crm,
    cnpj       AS nu_cnpj,
    competencia,
    SUM(nu_prescricoes) AS nu_prescricoes_medico,
    SUM(vl_pago)        AS vl_autorizacoes_medico,
    MIN(dt_ini)         AS dt_prescricao_inicial_medico,
    MAX(dt_fim)         AS dt_prescricao_final_medico
INTO temp_CGUSC.fp.base_agregada_crm_cnpj
FROM (
    SELECT * FROM #Medicos_Hist
    UNION ALL
    SELECT * FROM #Medicos_Recente
) U
GROUP BY crm, crm_uf, cnpj, competencia;

CREATE CLUSTERED INDEX IDX_BaseAgreg_Key ON temp_CGUSC.fp.base_agregada_crm_cnpj(nu_cnpj, nu_crm, competencia);


-- ============================================================================
-- PASSO 0.1: AGREGAÇÃO POR ESTABELECIMENTO / MÊS
-- ============================================================================
DROP TABLE IF EXISTS #Estab_Hist;
SELECT
    cnpj,
    YEAR(data_hora) * 100 + MONTH(data_hora) AS competencia,
    COUNT(DISTINCT num_autorizacao)           AS nu_aut,
    SUM(valor_pago)                           AS vl_pago,
    MIN(data_hora)                            AS dt_ini,
    MAX(data_hora)                            AS dt_fim
INTO #Estab_Hist
FROM db_FarmaciaPopular.dbo.Relatorio_movimentacaoFP
WHERE data_hora >= @DataInicio AND data_hora <= @DataFim
GROUP BY cnpj, YEAR(data_hora), MONTH(data_hora);

DROP TABLE IF EXISTS #Estab_Recente;
SELECT
    cnpj,
    YEAR(data_hora) * 100 + MONTH(data_hora) AS competencia,
    COUNT(DISTINCT num_autorizacao)           AS nu_aut,
    SUM(valor_pago)                           AS vl_pago,
    MIN(data_hora)                            AS dt_ini,
    MAX(data_hora)                            AS dt_fim
INTO #Estab_Recente
FROM db_FarmaciaPopular.carga_2024.relatorio_movimentacaoFP_2021_2024
WHERE data_hora >= @DataInicio AND data_hora <= @DataFim
GROUP BY cnpj, YEAR(data_hora), MONTH(data_hora);

DROP TABLE IF EXISTS #tb_info_estabelecimento;
SELECT
    cnpj,
    competencia,
    SUM(nu_aut)  AS nu_autorizacoes_estabelecimento,
    SUM(vl_pago) AS vl_autorizacoes_estabelecimento,
    MIN(dt_ini)  AS dt_venda_inicial_estabelecimento,
    MAX(dt_fim)  AS dt_venda_final_estabelecimento
INTO #tb_info_estabelecimento
FROM (SELECT * FROM #Estab_Hist UNION ALL SELECT * FROM #Estab_Recente) U
GROUP BY cnpj, competencia;


-- ============================================================================
-- TABELA TEMPORÁRIA COM ALERTAS
-- ============================================================================
DROP TABLE IF EXISTS #lista_medicos_farmacia_popularFP_temp;
SELECT
    CONCAT(A.nu_cnpj, '|', A.nu_crm, '|', A.sg_uf_crm, '|', CAST(A.competencia AS VARCHAR(6))) AS chave,
    A.nu_cnpj,
    A.nu_crm,
    A.sg_uf_crm,
    A.competencia,
    A.nu_prescricoes_medico,
    A.dt_prescricao_inicial_medico,
    A.dt_prescricao_final_medico,
    DATEDIFF(DAY,    A.dt_prescricao_inicial_medico, A.dt_prescricao_final_medico) + 1 AS nu_dias_prescricao_inicial_final,
    DATEDIFF(MINUTE, A.dt_prescricao_inicial_medico, A.dt_prescricao_final_medico)     AS nu_minutos_prescricao_inicial_final,
    C.nu_autorizacoes_estabelecimento,
    C.dt_venda_inicial_estabelecimento,
    C.dt_venda_final_estabelecimento,
    A.vl_autorizacoes_medico,
    (TRY_CAST(A.nu_prescricoes_medico AS DECIMAL(10,2)) / NULLIF(TRY_CAST(C.nu_autorizacoes_estabelecimento AS DECIMAL(10,2)), 0)) AS percentual,
    TRY_CAST('' AS VARCHAR(800)) AS alerta2,
    TRY_CAST('' AS VARCHAR(800)) AS alerta5
INTO #lista_medicos_farmacia_popularFP_temp
FROM temp_CGUSC.fp.base_agregada_crm_cnpj A
INNER JOIN #tb_info_estabelecimento C ON C.cnpj = A.nu_cnpj AND C.competencia = A.competencia
WHERE A.nu_prescricoes_medico >= 5;


-- ============================================================================
-- ALERTA 2: TODAS AS PRESCRIÇÕES EM PERÍODO MUITO CURTO (dentro do mês)
-- ============================================================================
-- Caso: todas as prescrições em uma janela de 2 dias
UPDATE #lista_medicos_farmacia_popularFP_temp
SET alerta2 = 'Todas as ' + CAST(nu_prescricoes_medico AS VARCHAR(10)) +
              ' prescrições lançadas em ' +
              CAST(nu_minutos_prescricao_inicial_final / 60 AS VARCHAR(10)) + ' hora(s) e ' +
              CAST(nu_minutos_prescricao_inicial_final % 60 AS VARCHAR(10)) + ' minuto(s)'
WHERE nu_dias_prescricao_inicial_final = 2
  AND nu_prescricoes_medico > 5;

-- Caso: todas no mesmo dia
UPDATE #lista_medicos_farmacia_popularFP_temp
SET alerta2 = 'Todas as ' + CAST(nu_prescricoes_medico AS VARCHAR(10)) +
              ' prescrições lançadas no mesmo dia, em ' +
              CAST(nu_minutos_prescricao_inicial_final / 60 AS VARCHAR(10)) + ' hora(s) e ' +
              CAST(nu_minutos_prescricao_inicial_final % 60 AS VARCHAR(10)) + ' minuto(s)'
WHERE nu_dias_prescricao_inicial_final = 1
  AND nu_prescricoes_medico > 5;


-- ============================================================================
-- TABELA TEMPORÁRIA 2 COM DADOS GEOGRÁFICOS
-- ============================================================================
DROP TABLE IF EXISTS #lista_medicos_farmacia_popularFP_temp2;
SELECT
    A.nu_cnpj,
    A.competencia,
    C.no_municipio,
    C.sg_uf,
    C.nu_populacao,
    B.codibge,
    C.latitude,
    C.longitude,
    A.nu_prescricoes_medico,
    TRY_CAST(
        TRY_CAST(A.nu_prescricoes_medico AS DECIMAL(18,2)) /
        NULLIF(TRY_CAST(A.nu_dias_prescricao_inicial_final AS DECIMAL(18,2)), 0)
    AS DECIMAL(18,2))                   AS nu_prescricoes_dia,
    A.nu_autorizacoes_estabelecimento,
    A.dt_prescricao_inicial_medico,
    A.dt_prescricao_final_medico,
    A.dt_venda_inicial_estabelecimento,
    A.dt_venda_final_estabelecimento,
    A.vl_autorizacoes_medico,
    A.percentual,
    A.nu_crm,
    A.sg_uf_crm,
    A.alerta2,
    A.alerta5
INTO #lista_medicos_farmacia_popularFP_temp2
FROM #lista_medicos_farmacia_popularFP_temp A
LEFT JOIN temp_CGUSC.fp.dados_farmacia   B ON B.cnpj     = A.nu_cnpj
LEFT JOIN temp_CGUSC.sus.tb_ibge         C ON C.id_ibge7 = B.codibge;


-- ============================================================================
-- TOTAIS NACIONAIS POR MÉDICO / COMPETÊNCIA
-- ============================================================================
DROP TABLE IF EXISTS #prescricoes_todos_estabelecimentos;
SELECT
    nu_crm,
    sg_uf_crm,
    competencia,
    SUM(nu_prescricoes_medico)                                          AS nu_prescricoes_medico_em_todos_estabelecimentos,
    COUNT(DISTINCT nu_cnpj)                                             AS nu_estabelecimentos_com_registro_mesmo_crm,
    CAST(SUM(nu_prescricoes_medico) AS DECIMAL(18,2)) /
        NULLIF(CAST(
            DATEDIFF(DAY, MIN(dt_prescricao_inicial_medico), MAX(dt_prescricao_final_medico)) + 1
        AS DECIMAL(18,2)), 0)                                           AS nu_prescricoes_dia_em_todos_estabelecimentos
INTO #prescricoes_todos_estabelecimentos
FROM temp_CGUSC.fp.base_agregada_crm_cnpj
GROUP BY nu_crm, sg_uf_crm, competencia;


-- ============================================================================
-- TABELA FINAL: dados_crm_detalhado
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.dados_crm_detalhado;
SELECT
    A.nu_cnpj,
    A.competencia,
    A.no_municipio,
    A.codIBGE,
    A.latitude,
    A.longitude,
    A.sg_uf,
    A.nu_populacao,
    A.nu_crm,
    A.sg_uf_crm,
    CAST(A.nu_crm AS VARCHAR(10)) + '/' + A.sg_uf_crm AS id_medico,
    A.nu_prescricoes_medico,
    B.nu_prescricoes_medico_em_todos_estabelecimentos,
    A.nu_prescricoes_dia,
    B.nu_prescricoes_dia_em_todos_estabelecimentos,
    B.nu_estabelecimentos_com_registro_mesmo_crm,
    A.nu_autorizacoes_estabelecimento,
    A.dt_prescricao_inicial_medico,
    A.dt_prescricao_final_medico,
    A.dt_venda_inicial_estabelecimento,
    A.dt_venda_final_estabelecimento,
    A.vl_autorizacoes_medico,
    A.percentual,
    A.alerta2,
    A.alerta5
INTO temp_CGUSC.fp.dados_crm_detalhado
FROM #lista_medicos_farmacia_popularFP_temp2 A
INNER JOIN #prescricoes_todos_estabelecimentos B
    ON  B.nu_crm      = A.nu_crm
    AND B.sg_uf_crm   = A.sg_uf_crm
    AND B.competencia = A.competencia;

CREATE NONCLUSTERED INDEX idx_dados_crm_detalhado_performance
ON temp_CGUSC.fp.dados_crm_detalhado (id_medico, nu_cnpj, competencia)
INCLUDE (latitude, longitude, dt_prescricao_inicial_medico, dt_prescricao_final_medico, no_municipio, sg_uf, nu_prescricoes_medico);
GO


-- ============================================================================
-- ALERTA 5: DISTÂNCIA >400KM NO MESMO MÊS (competencia = simultaneidade)
-- ============================================================================
PRINT '>> Processando Alerta 5 (Geográfico)...';

WITH
-- 1. Pares de CNPJs do mesmo médico na mesma competência
PairedWithDistance AS (
    SELECT
        T1.competencia,
        T1.id_medico,
        T1.nu_cnpj               AS CNPJ1_orig,
        T1.dt_prescricao_inicial_medico AS DI1,
        T1.dt_prescricao_final_medico   AS DF1,
        T1.no_municipio          AS M1,
        T1.sg_uf                 AS UF1,
        T1.nu_prescricoes_medico AS P1,
        T2.nu_cnpj               AS CNPJ2_orig,
        T2.dt_prescricao_inicial_medico AS DI2,
        T2.dt_prescricao_final_medico   AS DF2,
        T2.no_municipio          AS M2,
        T2.sg_uf                 AS UF2,
        T2.nu_prescricoes_medico AS P2,
        -- Só chama a função pesada se a diferença geográfica for grande
        CASE
            WHEN (ABS(T1.latitude - T2.latitude) > 2.0 OR ABS(T1.longitude - T2.longitude) > 2.0)
            THEN temp_CGUSC.fp.fnCalcular_Distancia_KM(T1.latitude, T1.longitude, T2.latitude, T2.longitude)
            ELSE 0
        END AS DistanciaKM
    FROM temp_CGUSC.fp.dados_crm_detalhado T1
    INNER JOIN temp_CGUSC.fp.dados_crm_detalhado T2
        ON  T1.id_medico   = T2.id_medico
        AND T1.nu_cnpj     < T2.nu_cnpj
        AND T1.competencia = T2.competencia   -- mesmo mês garante simultaneidade
),

-- 2. Filtra pares com distância >400km e volume mínimo
AllValidPairsFiltered AS (
    SELECT *
    FROM PairedWithDistance
    WHERE DistanciaKM > 400
      AND P1 >= 30
      AND P2 >= 30
),

-- 3. Ranqueia o par mais relevante por (médico, competência)
RankedValidPairs AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY id_medico, competencia
            ORDER BY (P1 + P2) DESC, DistanciaKM DESC
        ) AS rn
    FROM AllValidPairsFiltered
),

-- 4. Total de pares válidos por (médico, competência)
DoctorOverallStats AS (
    SELECT
        id_medico,
        competencia,
        COUNT(*) AS TotalValidPairsInDoctor
    FROM RankedValidPairs
    GROUP BY id_medico, competencia
),

-- 5. Dados finais para montar a mensagem
FinalAlertInfo AS (
    SELECT
        RP.competencia,
        RP.id_medico,
        RP.CNPJ1_orig AS Top_CNPJ1_orig,
        RP.DI1, RP.DF1, RP.M1, RP.UF1, RP.P1,
        RP.CNPJ2_orig AS Top_CNPJ2_orig,
        RP.DI2, RP.DF2, RP.M2, RP.UF2, RP.P2,
        RP.DistanciaKM AS Top_DistanciaKM,
        CASE WHEN DOS.TotalValidPairsInDoctor > 0
             THEN DOS.TotalValidPairsInDoctor - 1
             ELSE 0
        END AS CountOtherActualValidPairs,
        CASE WHEN RP.CNPJ1_orig IS NOT NULL AND LEN(RP.CNPJ1_orig) = 14
             THEN SUBSTRING(RP.CNPJ1_orig,1,2)+'.'+SUBSTRING(RP.CNPJ1_orig,3,3)+'.'+
                  SUBSTRING(RP.CNPJ1_orig,6,3)+'/'+SUBSTRING(RP.CNPJ1_orig,9,4)+'-'+SUBSTRING(RP.CNPJ1_orig,13,2)
             ELSE ISNULL(RP.CNPJ1_orig, 'N/I CNPJ')
        END AS Fmtd_Top_CNPJ1,
        CASE WHEN RP.CNPJ2_orig IS NOT NULL AND LEN(RP.CNPJ2_orig) = 14
             THEN SUBSTRING(RP.CNPJ2_orig,1,2)+'.'+SUBSTRING(RP.CNPJ2_orig,3,3)+'.'+
                  SUBSTRING(RP.CNPJ2_orig,6,3)+'/'+SUBSTRING(RP.CNPJ2_orig,9,4)+'-'+SUBSTRING(RP.CNPJ2_orig,13,2)
             ELSE ISNULL(RP.CNPJ2_orig, 'N/I CNPJ')
        END AS Fmtd_Top_CNPJ2
    FROM RankedValidPairs RP
    LEFT JOIN DoctorOverallStats DOS
        ON  RP.id_medico   = DOS.id_medico
        AND RP.competencia = DOS.competencia
    WHERE RP.rn = 1
)

-- Atualiza alerta5 com contexto do mês
UPDATE AM
SET AM.alerta5 =
    'Em ' + RIGHT('0' + CAST(FAI.competencia % 100 AS VARCHAR(2)), 2) + '/' + CAST(FAI.competencia / 100 AS VARCHAR(4)) + ': ' +
    'A distância entre a farmácia ' + FAI.Fmtd_Top_CNPJ1 +
    ' (' + ISNULL(FAI.M1, 'N/I') + '/' + ISNULL(FAI.UF1, 'N/I') + ')' +
    ' - ' + CONVERT(VARCHAR, FAI.DI1, 103) + ' a ' + CONVERT(VARCHAR, FAI.DF1, 103) +
    ' (' + ISNULL(CAST(FAI.P1 AS VARCHAR(10)), 'N/I') + ' Prescrições no período)' +
    ' e a farmácia ' + FAI.Fmtd_Top_CNPJ2 +
    ' (' + ISNULL(FAI.M2, 'N/I') + '/' + ISNULL(FAI.UF2, 'N/I') + ')' +
    ' - ' + CONVERT(VARCHAR, FAI.DI2, 103) + ' a ' + CONVERT(VARCHAR, FAI.DF2, 103) +
    ' (' + ISNULL(CAST(FAI.P2 AS VARCHAR(10)), 'N/I') + ' Prescrições no período)' +
    ' é de ' + CAST(CAST(FAI.Top_DistanciaKM AS DECIMAL(10,2)) AS VARCHAR(20)) + ' km.' +
    CASE
        WHEN FAI.CountOtherActualValidPairs > 0
        THEN ' Há também outros ' + CAST(FAI.CountOtherActualValidPairs AS VARCHAR(10)) +
             ' pares de estabelecimentos com distância maior que 400km no mesmo período.'
        ELSE ''
    END
FROM temp_CGUSC.fp.dados_crm_detalhado AM
INNER JOIN FinalAlertInfo FAI
    ON  AM.id_medico   = FAI.id_medico
    AND AM.competencia = FAI.competencia
    AND (AM.nu_cnpj = FAI.Top_CNPJ1_orig OR AM.nu_cnpj = FAI.Top_CNPJ2_orig);

PRINT 'Coluna "alerta5" atualizada com sucesso.';
GO


PRINT '============================================================================';
PRINT 'SCRIPT v3 EXECUTADO COM SUCESSO:';
PRINT '  - Dimensão COMPETENCIA (YYYYMM) adicionada em toda a cadeia';
PRINT '  - base_agregada_crm_cnpj: granularidade (cnpj, crm, competencia)';
PRINT '  - dados_crm_detalhado:    granularidade (cnpj, crm, competencia)';
PRINT '  - Alerta 5: simultaneidade por competencia (mesmo mês)';
PRINT '  - Robô nacional: calculado por (crm, crm_uf, competencia)';
PRINT '============================================================================';
GO
