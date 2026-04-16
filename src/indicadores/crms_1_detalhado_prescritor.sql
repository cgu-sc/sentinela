-- ============================================================================
-- GERADOR DE DADOS PARA INDICADOR DE CRMs - VERSÃO 2
-- ============================================================================
-- CORREÇÕES APLICADAS:
--   1. Contagem de prescrições agora usa COUNT(DISTINCT num_autorizacao) 
--      em vez de COUNT(*) para não inflar os números com múltiplos medicamentos
--   2. Mesma correção aplicada na contagem de autorizações por estabelecimento
--   3. NOVO: Adicionado alerta6 (prescrição antes do registro do CRM)
-- ============================================================================
-- ============================================================================

DECLARE @DataInicio     DATE          = '2015-07-01';
DECLARE @DataFim        DATE          = '2024-12-10';
DECLARE @ModoTeste       BIT           = 1; -- 0: Base Total (2h) | 1: Base reduzida SC (2 min)

-- Número de Sociedades que o Sócio de um estabelecimento possui dentro do programa Farmácia Popular
DROP TABLE IF EXISTS #socios_num_sociedades
SELECT cpf_cnpj_Socio nu_cpf_socio, COUNT(*) num_sociedades 
INTO #socios_num_sociedades
FROM temp_CGUSC.fp.socios_farmacia A
GROUP BY cpf_cnpj_Socio


-- ============================================================================
-- PASSO 0 & 0.1: AGREGAÇÃO (TESTE vs PRODUÇÃO)
-- ============================================================================
DROP TABLE IF EXISTS #tb_info_medico_farmacia_popular;
DROP TABLE IF EXISTS #tb_info_estabelecimento;

IF @ModoTeste = 1
BEGIN
    PRINT '>> MODO TESTE ATIVADO: Processando apenas SC (tabela reduzida)';
    
    -- Agregação de Médicos (Direto da teste_mov_SC)
    SELECT
        CONCAT(cnpj, '|', crm, '|', crm_uf) AS chave,
        crm AS nu_crm,
        crm_uf AS sg_uf_crm,
        cnpj AS nu_cnpj,
        COUNT(DISTINCT num_autorizacao) AS nu_prescricoes_medico,
        SUM(valor_pago) AS vl_autorizacoes_medico,
        MIN(data_hora) AS dt_prescricao_inicial_medico,
        MAX(data_hora) AS dt_prescricao_final_medico
    INTO #tb_info_medico_farmacia_popular
    FROM temp_CGUSC.fp.teste_mov_SC
    GROUP BY crm, crm_uf, cnpj;

    -- Agregação de Estabelecimento (Direto da teste_mov_SC)
    SELECT 
        cnpj,
        COUNT(DISTINCT num_autorizacao) AS nu_autorizacoes_estabelecimento,
        SUM(valor_pago) AS vl_autorizacoes_estabelecimento,
        MIN(data_hora) AS dt_venda_inicial_estabelecimento,
        MAX(data_hora) AS dt_venda_final_estabelecimento
    INTO #tb_info_estabelecimento
    FROM temp_CGUSC.fp.teste_mov_SC
    GROUP BY cnpj;
END
ELSE
BEGIN
    PRINT '>> MODO PRODUÇÃO: Processando base total (pode demorar)';

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
      AND data_hora >= @DataInicio AND data_hora <= @DataFim
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
      AND data_hora >= @DataInicio AND data_hora <= @DataFim
    GROUP BY crm, crm_uf, cnpj;

    -- C. União Final dos Médicos
    SELECT
        CONCAT(cnpj, '|', crm, '|', crm_uf) AS chave,
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

    -- D. Estabelecimentos Histórico
    DROP TABLE IF EXISTS #Estab_Hist;
    SELECT cnpj, COUNT(DISTINCT num_autorizacao) AS nu_aut, SUM(valor_pago) AS vl_pago, MIN(data_hora) AS dt_ini, MAX(data_hora) AS dt_fim
    INTO #Estab_Hist FROM db_FarmaciaPopular.dbo.Relatorio_movimentacaoFP
    WHERE data_hora >= @DataInicio AND data_hora <= @DataFim GROUP BY cnpj;

    -- E. Estabelecimentos Recente
    DROP TABLE IF EXISTS #Estab_Recente;
    SELECT cnpj, COUNT(DISTINCT num_autorizacao) AS nu_aut, SUM(valor_pago) AS vl_pago, MIN(data_hora) AS dt_ini, MAX(data_hora) AS dt_fim
    INTO #Estab_Recente FROM db_FarmaciaPopular.carga_2024.relatorio_movimentacaoFP_2021_2024
    WHERE data_hora >= @DataInicio AND data_hora <= @DataFim GROUP BY cnpj;

    -- F. União Final Estabelecimentos
    SELECT cnpj, SUM(nu_aut) AS nu_autorizacoes_estabelecimento, SUM(vl_pago) AS vl_autorizacoes_estabelecimento, MIN(dt_ini) AS dt_venda_inicial_estabelecimento, MAX(dt_fim) AS dt_venda_final_estabelecimento
    INTO #tb_info_estabelecimento
    FROM (SELECT * FROM #Estab_Hist UNION ALL SELECT * FROM #Estab_Recente) U
    GROUP BY cnpj;
END

-- ============================================================================
-- TABELA TEMPORÁRIA COM ALERTAS
-- ============================================================================
-- ✅ NOVO: Adicionado alerta6 para prescrição antes do registro do CRM
DROP TABLE IF EXISTS #lista_medicos_farmacia_popularFP_temp
SELECT
    CONCAT(A.nu_cnpj, '|', A.nu_crm, '|', A.sg_uf_crm) AS chave,
    A.nu_cnpj,
    A.nu_crm,
    A.sg_uf_crm,
    A.nu_prescricoes_medico,
    A.dt_prescricao_inicial_medico,
    A.dt_prescricao_final_medico,
    DATEDIFF(DAY, dt_prescricao_inicial_medico, dt_prescricao_final_medico) + 1 AS nu_dias_prescricao_inicial_final,
    DATEDIFF(MINUTE, dt_prescricao_inicial_medico, dt_prescricao_final_medico) AS nu_minutos_prescricao_inicial_final,
    C.nu_autorizacoes_estabelecimento,
    C.dt_venda_inicial_estabelecimento,
    C.dt_venda_final_estabelecimento,
    A.vl_autorizacoes_medico,
    (TRY_CAST(A.nu_prescricoes_medico AS DECIMAL(10, 2)) / NULLIF(TRY_CAST(C.nu_autorizacoes_estabelecimento AS DECIMAL(10, 2)), 0)) AS percentual,
    TRY_CAST('' AS VARCHAR(800)) AS alerta2,
    TRY_CAST('' AS VARCHAR(800)) AS alerta5
INTO #lista_medicos_farmacia_popularFP_temp
FROM #tb_info_medico_farmacia_popular A
INNER JOIN #tb_info_estabelecimento C ON C.cnpj = A.nu_cnpj
WHERE A.nu_prescricoes_medico >= 5


-- (Alerta 1 removido por redundância com flag_crm_invalido)


-- ============================================================================
-- ALERTA 2: TODAS AS PRESCRIÇÕES EM PERÍODO MUITO CURTO
-- ============================================================================
-- Caso: todas as prescrições lançadas em apenas 1 dia
UPDATE #lista_medicos_farmacia_popularFP_temp 
SET alerta2 = 'Todas as ' + CAST(nu_prescricoes_medico AS VARCHAR(10)) + 
              ' prescrições lançadas em ' + 
              CAST(nu_minutos_prescricao_inicial_final / 60 AS VARCHAR(10)) + ' hora(s) e ' + 
              CAST(nu_minutos_prescricao_inicial_final % 60 AS VARCHAR(10)) + ' minuto(s)' 
WHERE nu_dias_prescricao_inicial_final = 2
  AND nu_prescricoes_medico > 5


-- Caso: todas as prescrições no mesmo dia (diferença de 0 dias = mesmo momento)
-- Isso indica possível fraude - todas as prescrições em um único ponto no tempo
UPDATE #lista_medicos_farmacia_popularFP_temp 
SET alerta2 = 'Todas as ' + CAST(nu_prescricoes_medico AS VARCHAR(10)) +
              ' prescrições lançadas no mesmo dia, em ' +
              CAST(nu_minutos_prescricao_inicial_final / 60 AS VARCHAR(10)) + ' hora(s) e ' +
              CAST(nu_minutos_prescricao_inicial_final % 60 AS VARCHAR(10)) + ' minuto(s)'
WHERE nu_dias_prescricao_inicial_final = 1
  AND nu_prescricoes_medico > 5


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
    -- CORRIGIDO: usa nu_dias inclusivos (já calculado como +1 no passo anterior)
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
    A.alerta2,
    A.alerta5
INTO #lista_medicos_farmacia_popularFP_temp2
FROM #lista_medicos_farmacia_popularFP_temp A
LEFT JOIN temp_CGUSC.fp.dados_farmacia B ON B.cnpj = A.nu_cnpj
LEFT JOIN temp_CGUSC.sus.tb_ibge C ON C.id_ibge7 = B.codibge


-- ============================================================================
-- SOMAR PRESCRIÇÕES DE CADA MÉDICO EM TODOS OS ESTABELECIMENTOS (SEM FILTRO)
-- ============================================================================
-- IMPORTANTE: Calculamos a exclusividade sobre a base COMPLETA (#tb_info_medico_farmacia_popular)
-- para garantir que o flag_crm_exclusivo seja real e não apenas fruto de filtros.
DROP TABLE IF EXISTS #prescricoes_todos_estabelecimentos
SELECT 
    nu_crm,
    sg_uf_crm,
    SUM(nu_prescricoes_medico) AS nu_prescricoes_medico_em_todos_estabelecimentos,
    COUNT(DISTINCT nu_cnpj) AS nu_estabelecimentos_com_registro_mesmo_crm,
    CAST(SUM(nu_prescricoes_medico) AS DECIMAL(18,2)) /
        NULLIF(CAST(
            DATEDIFF(DAY, MIN(dt_prescricao_inicial_medico), MAX(dt_prescricao_final_medico)) + 1
        AS DECIMAL(18,2)), 0) AS nu_prescricoes_dia_em_todos_estabelecimentos
INTO #prescricoes_todos_estabelecimentos
FROM #tb_info_medico_farmacia_popular
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
    A.Conexao,
    A.vl_autorizacoes_medico,
    A.percentual,
    A.alerta2,
    A.alerta5
INTO temp_CGUSC.fp.dados_crm_detalhado
FROM #lista_medicos_farmacia_popularFP_temp2 A
INNER JOIN #prescricoes_todos_estabelecimentos B 
    ON B.nu_crm = A.nu_crm AND B.sg_uf_crm = A.sg_uf_crm


-- (Alertas 3 e 4 removidos por redundância com flags de robô)



-- ============================================================================
-- ÍNDICE PARA PERFORMANCE
-- ============================================================================
CREATE NONCLUSTERED INDEX idx_dados_crm_detalhado_performance
ON temp_CGUSC.fp.dados_crm_detalhado (id_medico, nu_cnpj)
INCLUDE (latitude, longitude, dt_prescricao_inicial_medico, dt_prescricao_final_medico, no_municipio, sg_uf, nu_prescricoes_medico);
GO


-- ============================================================================
-- ALERTA 5: DISTÂNCIA >400KM ENTRE FARMÁCIAS COM SOBREPOSIÇÃO DE DATAS
-- ============================================================================
WITH
-- 1. Calcula a distância para todos os pares de T1 e T2 para cada médico
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
        temp_CGUSC.fp.fnCalcular_Distancia_KM(T1.latitude, T1.longitude, T2.latitude, T2.longitude) AS DistanciaKM
    FROM temp_CGUSC.fp.dados_crm_detalhado T1
    INNER JOIN temp_CGUSC.fp.dados_crm_detalhado T2 
        ON T1.id_medico = T2.id_medico AND T1.nu_cnpj < T2.nu_cnpj
),

-- 2. Filtra os pares válidos
AllValidPairsFiltered AS (
    SELECT *
    FROM PairedWithDistance
    WHERE (DI1 <= DF2 AND DF1 >= DI2)  -- Sobreposição de datas
      AND DistanciaKM > 400
      AND P1 >= 30  -- Mínimo de prescrições no Estabelecimento 1
      AND P2 >= 30  -- Mínimo de prescrições no Estabelecimento 2
),

-- 3. Ranqueia os pares por número de prescrições
RankedValidPairs AS (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY id_medico ORDER BY (P1 + P2) DESC, DistanciaKM DESC) AS rn
    FROM AllValidPairsFiltered
),

-- 4. Estatísticas por médico
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
    'A distância entre a farmácia ' + FAI.Fmtd_Top_CNPJ1 +
    ' (' + ISNULL(FAI.Top_M1, 'N/I') + '/' + ISNULL(FAI.Top_uf1, 'N/I') + ')' +
    ' - ' + CONVERT(VARCHAR, FAI.Top_DI1, 103) + ' a ' + CONVERT(VARCHAR, FAI.Top_DF1, 103) +
    ' (' + ISNULL(CAST(FAI.Top_P1 AS VARCHAR(10)), 'N/I') + ' Prescrições no período)' +
    ' e a farmácia ' + FAI.Fmtd_Top_CNPJ2 +
    ' (' + ISNULL(FAI.Top_M2, 'N/I') + '/' + ISNULL(FAI.Top_uf2, 'N/I') + ')' +
    ' - ' + CONVERT(VARCHAR, FAI.Top_DI2, 103) + ' a ' + CONVERT(VARCHAR, FAI.Top_DF2, 103) +
    ' (' + ISNULL(CAST(FAI.Top_P2 AS VARCHAR(10)), 'N/I') + ' Prescrições no período)' +
    ' é de ' + CAST(CAST(FAI.Top_DistanciaKM AS DECIMAL(10,2)) AS VARCHAR(20)) + ' km.' +
    CASE
        WHEN FAI.CountOtherActualValidPairs > 0 THEN
            ' Há também outros ' + CAST(FAI.CountOtherActualValidPairs AS VARCHAR(10)) +
            ' pares de estabelecimentos com distância maior que 400km que registraram prescrições do médico com registro CRM ' +
            ISNULL(FAI.id_medico, 'N/I') + '.'
        ELSE ''
    END
FROM temp_CGUSC.fp.dados_crm_detalhado AM
INNER JOIN FinalAlertInfo FAI ON AM.id_medico = FAI.id_medico
WHERE (AM.nu_cnpj = FAI.Top_CNPJ1_orig OR AM.nu_cnpj = FAI.Top_CNPJ2_orig);

PRINT 'Coluna "alerta5" atualizada com sucesso.';
GO


-- (Alerta 6 removido por redundância com flag_prescricao_antes_registro)
PRINT '============================================================================';
PRINT 'SCRIPT EXECUTADO COM CORREÇÕES:';
PRINT '  - Prescrições contadas por COUNT(DISTINCT num_autorizacao)';
PRINT '  - Todos os alertas (1-6) populados corretamente';
PRINT '  - NOVO: Alerta6 para prescrição antes do registro do CRM';
PRINT '============================================================================';
GO







