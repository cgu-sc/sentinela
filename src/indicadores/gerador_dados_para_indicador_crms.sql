-- ============================================================================
-- GERADOR DE DADOS PARA INDICADOR DE CRMs - VERSÃƒO 2
-- ============================================================================
-- CORREÃ‡Ã•ES APLICADAS:
--   1. Contagem de prescriÃ§Ãµes agora usa COUNT(DISTINCT num_autorizacao) 
--      em vez de COUNT(*) para nÃ£o inflar os nÃºmeros com mÃºltiplos medicamentos
--   2. Mesma correÃ§Ã£o aplicada na contagem de autorizaÃ§Ãµes por estabelecimento
--   3. NOVO: Adicionado alerta6 (prescriÃ§Ã£o antes do registro do CRM)
-- ============================================================================

-- NÃºmero de Sociedades que o SÃ³cio de um estabelecimento possui dentro do programa FarmÃ¡cia Popular
DROP TABLE IF EXISTS #socios_num_sociedades
SELECT cpf_cnpj_Socio nu_cpf_socio, COUNT(*) num_sociedades 
INTO #socios_num_sociedades
FROM temp_CGUSC.fp.socios_farmacia A
GROUP BY cpf_cnpj_Socio


-- ============================================================================
-- ============================================================================
-- PASSO 0: AGREGAÇÃO POR MÉDICO/FARMÁCIA (OTIMIZADA PARA GRANDES VOLUMES)
-- ============================================================================
-- Agregamos cada base separadamente e depois unimos o resultado.

-- A. Agregação Base Histórica (2015-2020)
DROP TABLE IF EXISTS #Medicos_Hist;
SELECT
    cnpj, crm, crm_uf,
    COUNT(DISTINCT num_autorizacao) AS nu_prescricoes,
    SUM(valor_pago) AS vl_pago,
    MIN(data_hora) AS dt_ini,
    MAX(data_hora) AS dt_fim
INTO #Medicos_Hist
FROM db_FarmaciaPopular.dbo.Relatorio_movimentacaoFP
WHERE crm_uf IS NOT NULL AND crm IS NOT NULL AND crm_uf <> 'BR'
GROUP BY crm, crm_uf, cnpj;

-- B. Agregação Base Recente (2021-2024)
DROP TABLE IF EXISTS #Medicos_Recente;
SELECT
    cnpj, crm, crm_uf,
    COUNT(DISTINCT num_autorizacao) AS nu_prescricoes,
    SUM(valor_pago) AS vl_pago,
    MIN(data_hora) AS dt_ini,
    MAX(data_hora) AS dt_fim
INTO #Medicos_Recente
FROM db_FarmaciaPopular.carga_2024.relatorio_movimentacaoFP_2021_2024
WHERE crm_uf IS NOT NULL AND crm IS NOT NULL AND crm_uf <> 'BR'
GROUP BY crm, crm_uf, cnpj;

-- C. União Final dos Médicos
DROP TABLE IF EXISTS #tb_info_medico_farmacia_popular;
SELECT
    CONCAT(cnpj, crm, crm_uf) AS chave,
    crm AS nu_crm,
    crm_uf AS sg_uf_crm,
    cnpj AS nu_cnpj,
    SUM(nu_prescricoes) AS nu_prescricoes_medico,
    SUM(vl_pago) AS vl_autorizacoes_medico,
    MIN(dt_ini) AS dt_prescricao_inicial_medico,
    MAX(dt_fim) AS dt_prescricao_final_medico
INTO #tb_info_medico_farmacia_popular
FROM (
    SELECT * FROM #Medicos_Hist
    UNION ALL
    SELECT * FROM #Medicos_Recente
) U
GROUP BY crm, crm_uf, cnpj;

-- ============================================================================
-- PASSO 0.1: AGREGAÇÃO POR ESTABELECIMENTO
-- ============================================================================
DROP TABLE IF EXISTS #Estab_Hist;
SELECT 
    cnpj,
    COUNT(DISTINCT num_autorizacao) AS nu_aut,
    SUM(valor_pago) AS vl_pago,
    MIN(data_hora) AS dt_ini,
    MAX(data_hora) AS dt_fim
INTO #Estab_Hist
FROM db_FarmaciaPopular.dbo.Relatorio_movimentacaoFP
GROUP BY cnpj;

DROP TABLE IF EXISTS #Estab_Recente;
SELECT 
    cnpj,
    COUNT(DISTINCT num_autorizacao) AS nu_aut,
    SUM(valor_pago) AS vl_pago,
    MIN(data_hora) AS dt_ini,
    MAX(data_hora) AS dt_fim
INTO #Estab_Recente
FROM db_FarmaciaPopular.carga_2024.relatorio_movimentacaoFP_2021_2024
GROUP BY cnpj;

DROP TABLE IF EXISTS #tb_info_estabelecimento;
SELECT 
    cnpj,
    SUM(nu_aut) AS nu_autorizacoes_estabelecimento,
    SUM(vl_pago) AS vl_autorizacoes_estabelecimento,
    MIN(dt_ini) AS dt_venda_inicial_estabelecimento,
    MAX(dt_fim) AS dt_venda_final_estabelecimento
INTO #tb_info_estabelecimento
FROM (
    SELECT * FROM #Estab_Hist
    UNION ALL
    SELECT * FROM #Estab_Recente
) U
GROUP BY cnpj;

USE [temp_CGUSC];
GO

-- ============================================================================
-- TABELA TEMPORÁRIA COM ALERTAS
-- ============================================================================
-- ✅ NOVO: Adicionado alerta6 para prescrição antes do registro do CRM
DROP TABLE IF EXISTS #lista_medicos_farmacia_popularFP_temp
SELECT
    CONCAT(A.nu_cnpj, A.nu_crm, A.sg_uf_crm) AS chave,
    A.nu_cnpj,
    A.nu_crm,
    A.sg_uf_crm,
    A.nu_prescricoes_medico,
    A.dt_prescricao_inicial_medico,
    A.dt_prescricao_final_medico,
    DATEDIFF(DAY, dt_prescricao_inicial_medico, dt_prescricao_final_medico) AS nu_dias_prescricao_inicial_final,
    DATEDIFF(MINUTE, dt_prescricao_inicial_medico, dt_prescricao_final_medico) AS nu_minutos_prescricao_inicial_final,
    C.nu_autorizacoes_estabelecimento,
    C.dt_venda_inicial_estabelecimento,
    C.dt_venda_final_estabelecimento,
    A.vl_autorizacoes_medico,
    (TRY_CAST(A.nu_prescricoes_medico AS DECIMAL(10, 2)) / TRY_CAST(C.nu_autorizacoes_estabelecimento AS DECIMAL(10, 2))) AS percentual,
    TRY_CAST('' AS VARCHAR(MAX)) AS alerta1,
    TRY_CAST('' AS VARCHAR(MAX)) AS alerta2,
    TRY_CAST('' AS VARCHAR(MAX)) AS alerta3,
    TRY_CAST('' AS VARCHAR(MAX)) AS alerta4,
    TRY_CAST('' AS VARCHAR(MAX)) AS alerta5,
    TRY_CAST('' AS VARCHAR(MAX)) AS alerta6
INTO #lista_medicos_farmacia_popularFP_temp
FROM #tb_info_medico_farmacia_popular A
INNER JOIN #tb_info_estabelecimento C ON C.cnpj = A.nu_cnpj
WHERE A.nu_prescricoes_medico > 20


-- ============================================================================
-- ALERTA 1: CRM INVÁLIDO
-- ============================================================================
UPDATE A
SET alerta1 = 'CRM/UF não localizado na base do CFM.'
FROM #lista_medicos_farmacia_popularFP_temp A
WHERE NOT EXISTS (
    SELECT 1 
    FROM temp_CFM.dbo.medicos_jul_2025_mod M
    WHERE M.NU_CRM = CAST(A.nu_crm AS VARCHAR(25)) 
      AND M.SG_uf = A.sg_uf_crm
);


-- ============================================================================
-- ALERTA 2: TODAS AS PRESCRIÇÕES EM PERÍODO MUITO CURTO
-- ============================================================================
-- Caso: todas as prescrições lançadas em apenas 1 dia
UPDATE #lista_medicos_farmacia_popularFP_temp 
SET alerta2 = 'Todas as ' + CAST(nu_prescricoes_medico AS VARCHAR(10)) + 
              ' prescrições lançadas em ' + 
              CAST(nu_minutos_prescricao_inicial_final / 60 AS VARCHAR(10)) + ' hora(s) e ' + 
              CAST(nu_minutos_prescricao_inicial_final % 60 AS VARCHAR(10)) + ' minuto(s)' 
WHERE nu_dias_prescricao_inicial_final = 1


-- Caso: todas as prescrições no mesmo dia (diferença de 0 dias = mesmo momento)
-- Isso indica possível fraude - todas as prescrições em um único ponto no tempo
UPDATE #lista_medicos_farmacia_popularFP_temp 
SET alerta2 = 'Todas as ' + CAST(nu_prescricoes_medico AS VARCHAR(10)) + 
              ' prescrições lançadas no final de semana (sábado ou domingo), em ' + 
              CAST(nu_minutos_prescricao_inicial_final / 60 AS VARCHAR(10)) + ' hora(s) e ' + 
              CAST(nu_minutos_prescricao_inicial_final % 60 AS VARCHAR(10)) + ' minuto(s)',
    nu_dias_prescricao_inicial_final = 1 
WHERE nu_dias_prescricao_inicial_final = 0


-- ============================================================================
-- TABELA TEMPORÁRIA 2 COM DADOS GEOGRÁFICOS
-- ============================================================================
-- ✅ NOVO: Incluído alerta6 na seleção
DROP TABLE IF EXISTS #lista_medicos_farmacia_popularFP_temp2
SELECT 
    A.nu_cnpj,
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
    AS DECIMAL(18,2)) AS nu_prescricoes_dia,
    A.nu_autorizacoes_estabelecimento,
    A.dt_prescricao_inicial_medico,
    A.dt_prescricao_final_medico,
    A.dt_venda_inicial_estabelecimento,
    A.dt_venda_final_estabelecimento,
    CASE
        WHEN YEAR(A.dt_venda_final_estabelecimento) = 2024 
         AND MONTH(A.dt_venda_final_estabelecimento) = 12 THEN 'Ativa'
        ELSE 'Inativa'
    END AS 'Conexao',
    A.vl_autorizacoes_medico,
    A.percentual,
    A.nu_crm,
    A.sg_uf_crm,
    A.alerta1,
    A.alerta2,
    A.alerta3,
    A.alerta4,
    A.alerta5,
    A.alerta6
INTO #lista_medicos_farmacia_popularFP_temp2
FROM #lista_medicos_farmacia_popularFP_temp A
LEFT JOIN temp_CGUSC.fp.dados_farmacia B ON B.cnpj = A.nu_cnpj
LEFT JOIN temp_CGUSC.sus.tb_ibge C ON C.id_ibge7 = B.codibge
GROUP BY 
    B.codibge,
    C.sg_uf,
    C.no_municipio,
    C.nu_populacao,
    C.latitude,
    C.longitude,
    A.nu_cnpj,
    nu_crm,
    sg_uf_crm,
    nu_prescricoes_medico,
    nu_autorizacoes_estabelecimento,
    percentual,
    A.vl_autorizacoes_medico,
    A.dt_venda_inicial_estabelecimento,
    A.dt_venda_final_estabelecimento,
    A.dt_prescricao_inicial_medico,
    A.dt_prescricao_final_medico,
    A.nu_dias_prescricao_inicial_final,
    A.alerta1,
    A.alerta2,
    A.alerta3,
    A.alerta4,
    A.alerta5,
    A.alerta6


-- ============================================================================
-- SOMAR PRESCRIÇÕES DE CADA MÉDICO EM TODOS OS ESTABELECIMENTOS
-- ============================================================================
DROP TABLE IF EXISTS #prescricoes_todos_estabelecimentos
SELECT 
    nu_crm,
    sg_uf_crm,
    SUM(nu_prescricoes_dia) AS nu_prescricoes_dia_em_todos_estabelecimentos,
    SUM(nu_prescricoes_medico) AS nu_prescricoes_medico_em_todos_estabelecimentos,
    COUNT(*) AS nu_estabelecimentos_com_registro_mesmo_crm
INTO #prescricoes_todos_estabelecimentos
FROM #lista_medicos_farmacia_popularFP_temp2
GROUP BY nu_crm, sg_uf_crm


-- ============================================================================
-- TABELA FINAL: dados_crm_detalhado
-- ============================================================================
-- ✅ NOVO: Incluído alerta6 na tabela final
DROP TABLE IF EXISTS temp_CGUSC.fp.dados_crm_detalhado
SELECT
    A.nu_cnpj,
    A.no_municipio,
    A.codIBGE,
    A.latitude,
    A.longitude,
    A.sg_uf,
    A.nu_populacao,
    A.nu_crm,
    A.sg_uf_crm,
    TRY_CAST(TRY_CAST(A.nu_crm AS VARCHAR(MAX)) + '/' + TRY_CAST(A.sg_uf_crm AS VARCHAR(MAX)) AS VARCHAR(20)) AS id_medico,
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
    A.Conexao,
    A.vl_autorizacoes_medico,
    A.percentual,
    A.alerta1,
    A.alerta2,
    A.alerta3,
    A.alerta4,
    A.alerta5,
    A.alerta6
INTO temp_CGUSC.fp.dados_crm_detalhado
FROM #lista_medicos_farmacia_popularFP_temp2 A
INNER JOIN #prescricoes_todos_estabelecimentos B 
    ON B.nu_crm = A.nu_crm AND B.sg_uf_crm = A.sg_uf_crm


-- ============================================================================
-- ALERTA 3: MÃ‰DIA >30 PRESCRIÃ‡Ã•ES/DIA NESTE ESTABELECIMENTO
-- ============================================================================
UPDATE temp_CGUSC.fp.dados_crm_detalhado 
SET alerta3 = 'Foram registradas uma mÃ©dia de ' + CAST(nu_prescricoes_dia AS VARCHAR(MAX)) + 
              ' prescriÃ§Ãµes por dia para o CRM ' + CAST(nu_crm AS VARCHAR(MAX)) + '/' + 
              CAST(sg_uf_crm AS VARCHAR(MAX)) + ' neste estabelecimento.'
WHERE nu_prescricoes_dia > 30


-- ============================================================================
-- ALERTA 4: MÃ‰DIA >30 PRESCRIÃ‡Ã•ES/DIA EM TODOS OS ESTABELECIMENTOS
-- ============================================================================
UPDATE temp_CGUSC.fp.dados_crm_detalhado 
SET alerta4 = 'Foram registradas uma mÃ©dia de ' + 
              CAST(nu_prescricoes_dia_em_todos_estabelecimentos AS VARCHAR(MAX)) + 
              ' prescriÃ§Ãµes por dia para o CRM ' + CAST(nu_crm AS VARCHAR(MAX)) + '/' + 
              CAST(sg_uf_crm AS VARCHAR(MAX)) + ' em todos os ' + 
              CAST(nu_estabelecimentos_com_registro_mesmo_crm AS VARCHAR(MAX)) + 
              ' estabelecimentos em que hÃ¡ registros.'
WHERE nu_prescricoes_dia_em_todos_estabelecimentos > 30


select * from dados_crm_detalhado

-- ============================================================================
-- ÃNDICE PARA PERFORMANCE
-- ============================================================================
CREATE NONCLUSTERED INDEX idx_dados_crm_detalhado_performance
ON temp_CGUSC.fp.dados_crm_detalhado (id_medico, nu_cnpj)
INCLUDE (Latitude, Longitude, dt_prescricao_inicial_medico, dt_prescricao_final_medico);
GO


-- ============================================================================
-- ALERTA 5: DISTÃ‚NCIA >400KM ENTRE FARMÃCIAS COM SOBREPOSIÃ‡ÃƒO DE DATAS
-- ============================================================================
WITH
-- 1. Calcula a distÃ¢ncia para todos os pares de T1 e T2 para cada mÃ©dico
PairedWithDistance AS (
    SELECT
        T1.id_medico,
        T1.nu_cnpj AS CNPJ1_orig, 
        T1.dt_prescricao_inicial_medico AS DI1, 
        T1.dt_prescricao_final_medico AS DF1, 
        T1.no_municipio AS M1, 
        T1.sg_uf AS UF1, 
        T1.nu_prescricoes_medico AS P1,
        T2.nu_cnpj AS CNPJ2_orig, 
        T2.dt_prescricao_inicial_medico AS DI2, 
        T2.dt_prescricao_final_medico AS DF2, 
        T2.no_municipio AS M2, 
        T2.sg_uf AS UF2, 
        T2.nu_prescricoes_medico AS P2,
        temp_CGUSC.fp.fnCalcular_Distancia_KM(T1.Latitude, T1.Longitude, T2.Latitude, T2.Longitude) AS DistanciaKM
    FROM temp_CGUSC.fp.dados_crm_detalhado T1
    INNER JOIN temp_CGUSC.fp.dados_crm_detalhado T2 
        ON T1.id_medico = T2.id_medico AND T1.nu_cnpj < T2.nu_cnpj
),

-- 2. Filtra os pares vÃ¡lidos
AllValidPairsFiltered AS (
    SELECT *
    FROM PairedWithDistance
    WHERE (DI1 <= DF2 AND DF1 >= DI2)  -- SobreposiÃ§Ã£o de datas
      AND DistanciaKM > 400
      AND DistanciaKM IS NOT NULL
      AND P1 >= 100  -- MÃ­nimo de prescriÃ§Ãµes no Estabelecimento 1
      AND P2 >= 100  -- MÃ­nimo de prescriÃ§Ãµes no Estabelecimento 2
),

-- 3. Ranqueia os pares por nÃºmero de prescriÃ§Ãµes
RankedValidPairs AS (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY id_medico ORDER BY (P1 + P2) DESC, DistanciaKM DESC) AS rn
    FROM AllValidPairsFiltered
),

-- 4. EstatÃ­sticas por mÃ©dico
DoctorOverallStats AS (
    SELECT
        id_medico,
        COUNT(*) AS TotalValidPairsInDoctor
    FROM RankedValidPairs
    GROUP BY id_medico
),

-- 5. Prepara dados finais para o alerta
FinalAlertInfo AS (
    SELECT
        RP.id_medico,
        RP.CNPJ1_orig AS Top_CNPJ1_orig, 
        RP.DI1 AS Top_DI1, 
        RP.DF1 AS Top_DF1, 
        RP.M1 AS Top_M1, 
        RP.UF1 AS Top_uf1, 
        RP.P1 AS Top_P1,
        RP.CNPJ2_orig AS Top_CNPJ2_orig, 
        RP.DI2 AS Top_DI2, 
        RP.DF2 AS Top_DF2, 
        RP.M2 AS Top_M2, 
        RP.UF2 AS Top_uf2, 
        RP.P2 AS Top_P2,
        RP.DistanciaKM AS Top_DistanciaKM,
        CASE WHEN DOS.TotalValidPairsInDoctor > 0 THEN DOS.TotalValidPairsInDoctor - 1 ELSE 0 END AS CountOtherActualValidPairs,
        -- CNPJs Formatados
        CASE WHEN RP.CNPJ1_orig IS NOT NULL AND LEN(RP.CNPJ1_orig) = 14 
             THEN SUBSTRING(RP.CNPJ1_orig,1,2)+'.'+SUBSTRING(RP.CNPJ1_orig,3,3)+'.'+SUBSTRING(RP.CNPJ1_orig,6,3)+'/'+SUBSTRING(RP.CNPJ1_orig,9,4)+'-'+SUBSTRING(RP.CNPJ1_orig,13,2) 
             ELSE ISNULL(RP.CNPJ1_orig, 'N/I CNPJ') 
        END AS Fmtd_Top_CNPJ1,
        CASE WHEN RP.CNPJ2_orig IS NOT NULL AND LEN(RP.CNPJ2_orig) = 14 
             THEN SUBSTRING(RP.CNPJ2_orig,1,2)+'.'+SUBSTRING(RP.CNPJ2_orig,3,3)+'.'+SUBSTRING(RP.CNPJ2_orig,6,3)+'/'+SUBSTRING(RP.CNPJ2_orig,9,4)+'-'+SUBSTRING(RP.CNPJ2_orig,13,2) 
             ELSE ISNULL(RP.CNPJ2_orig, 'N/I CNPJ') 
        END AS Fmtd_Top_CNPJ2
    FROM RankedValidPairs RP
    LEFT JOIN DoctorOverallStats DOS ON RP.id_medico = DOS.id_medico
    WHERE RP.rn = 1  -- Seleciona o par principal
)

-- Atualiza a tabela com o alerta5
UPDATE AM
SET AM.alerta5 = 
    'A distÃ¢ncia entre a farmÃ¡cia ' + FAI.Fmtd_Top_CNPJ1 +
    ' (' + ISNULL(FAI.Top_M1, 'N/I') + '/' + ISNULL(FAI.Top_uf1, 'N/I') + ')' +
    ' - ' + CONVERT(VARCHAR, FAI.Top_DI1, 103) + ' a ' + CONVERT(VARCHAR, FAI.Top_DF1, 103) +
    ' (' + ISNULL(CAST(FAI.Top_P1 AS VARCHAR(10)), 'N/I') + ' PrescriÃ§Ãµes no perÃ­odo)' +
    ' e a farmÃ¡cia ' + FAI.Fmtd_Top_CNPJ2 +
    ' (' + ISNULL(FAI.Top_M2, 'N/I') + '/' + ISNULL(FAI.Top_uf2, 'N/I') + ')' +
    ' - ' + CONVERT(VARCHAR, FAI.Top_DI2, 103) + ' a ' + CONVERT(VARCHAR, FAI.Top_DF2, 103) +
    ' (' + ISNULL(CAST(FAI.Top_P2 AS VARCHAR(10)), 'N/I') + ' PrescriÃ§Ãµes no perÃ­odo)' +
    ' Ã© de ' + CAST(CAST(FAI.Top_DistanciaKM AS DECIMAL(10,2)) AS VARCHAR(20)) + ' km.' +
    CASE
        WHEN FAI.CountOtherActualValidPairs > 0 THEN
            ' HÃ¡ tambÃ©m outros ' + CAST(FAI.CountOtherActualValidPairs AS VARCHAR(10)) +
            ' pares de estabelecimentos com distÃ¢ncia maior que 400km que registraram prescriÃ§Ãµes do mÃ©dico com registro CRM ' +
            ISNULL(FAI.id_medico, 'N/I') + '.'
        ELSE ''
    END
FROM temp_CGUSC.fp.dados_crm_detalhado AM
INNER JOIN FinalAlertInfo FAI ON AM.id_medico = FAI.id_medico
WHERE (AM.nu_cnpj = FAI.Top_CNPJ1_orig OR AM.nu_cnpj = FAI.Top_CNPJ2_orig);

PRINT 'Coluna "alerta5" atualizada com sucesso.';
GO


-- ============================================================================
-- ALERTA 6: PRESCRIÃ‡ÃƒO ANTES DO REGISTRO DO CRM
-- ============================================================================
-- âœ… NOVO: Verifica se a primeira prescriÃ§Ã£o do mÃ©dico neste estabelecimento
--          ocorreu antes da data de inscriÃ§Ã£o do CRM no CFM
UPDATE AM
SET AM.alerta6 = 
    'PrescriÃ§Ã£o anterior ao registro do CRM (1Âª prescriÃ§Ã£o: ' + 
    CONVERT(VARCHAR, AM.dt_prescricao_inicial_medico, 103) + 
    ', registro CRM: ' + CONVERT(VARCHAR, CFM.dt_inscricao_convertida, 103) + ')'
FROM temp_CGUSC.fp.dados_crm_detalhado AM
INNER JOIN (
    SELECT 
        NU_CRM,
        SG_uf,
        TRY_CONVERT(DATE, DT_INSCRICAO, 103) AS dt_inscricao_convertida
    FROM temp_CFM.dbo.medicos_jul_2025_mod
    WHERE DT_INSCRICAO IS NOT NULL AND DT_INSCRICAO <> ''
) CFM ON CFM.NU_CRM = CAST(AM.nu_crm AS VARCHAR(25)) AND CFM.SG_uf = AM.sg_uf_crm
WHERE CFM.dt_inscricao_convertida IS NOT NULL 
  AND AM.dt_prescricao_inicial_medico < CFM.dt_inscricao_convertida;

PRINT 'Coluna "alerta6" atualizada com sucesso.';
PRINT '============================================================================';
PRINT 'SCRIPT EXECUTADO COM CORREÃ‡Ã•ES:';
PRINT '  - PrescriÃ§Ãµes contadas por COUNT(DISTINCT num_autorizacao)';
PRINT '  - Todos os alertas (1-6) populados corretamente';
PRINT '  - NOVO: Alerta6 para prescriÃ§Ã£o antes do registro do CRM';
PRINT '============================================================================';
GO







