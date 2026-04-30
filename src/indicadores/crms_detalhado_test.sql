-- ============================================================================
-- GERADOR DE DADOS PARA INDICADOR DE CRMs - VERSÃO 5
-- ============================================================================
-- ALTERAÇÕES v5 (sobre v4):
--   1. crm_unico_alertas: tabela master diária, fonte única de verdade
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
-- PASSO -1: MAPA DE MÉDICOS PARA ID INT
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.dados_medico;

SELECT 
    CAST(CAST(TRY_CAST(NU_CRM AS BIGINT) AS VARCHAR(10)) + '/' + SG_UF AS VARCHAR(20)) AS id_medico,
    TRY_CAST(NU_CRM AS BIGINT)                             AS nu_crm,
    SG_UF                                                  AS sg_uf,
    NM_MEDICO                                              AS no_medico,
    TRY_CONVERT(DATE, DT_INSCRICAO, 103)                   AS dt_inscricao
INTO temp_CGUSC.fp.dados_medico
FROM temp_CFM.dbo.medicos_jul_2025_mod
WHERE NU_CRM IS NOT NULL
  AND TRY_CAST(NU_CRM AS BIGINT) > 0;

CREATE CLUSTERED INDEX IDX_Join_Medico ON temp_CGUSC.fp.dados_medico(id_medico);


-- ============================================================================
-- PASSO 0: CONSOLIDAÇÃO HORÁRIA MESTRA (SCAN ÚNICO)
-- Agrupa 1 Bilhão de linhas em buckets horários para reduzir volume em ~95%.
-- Todas as agregações seguintes (Mensal, Diária, Estabelecimento) lerão daqui.
-- ============================================================================
PRINT '>> Passo 0: Criando #base_horaria_mestra (Único Scan de 1 Bi de linhas)...';
DECLARE @t_passo0 DATETIME = GETDATE();
DROP TABLE IF EXISTS #base_horaria_mestra;

SELECT
    M.cnpj                                            AS nu_cnpj,
    CAST(CAST(M.crm AS VARCHAR(10)) + '/' + M.crm_uf AS VARCHAR(20)) AS id_medico,
    YEAR(M.data_hora) * 100 + MONTH(M.data_hora)     AS competencia,
    CAST(M.data_hora AS DATE)                         AS dt_dia,
    DATEPART(HOUR, M.data_hora)                       AS hr_janela,
    -- Métricas Agregadas (Somáveis para as próximas etapas)
    COUNT(DISTINCT M.num_autorizacao)                 AS nu_prescricoes_hora,
    SUM(M.valor_pago)                                 AS vl_autorizacoes_hora,
    MIN(M.data_hora)                                  AS dt_ini_hora,
    MAX(M.data_hora)                                  AS dt_fim_hora,
    DATEDIFF(MINUTE, MIN(M.data_hora), MAX(M.data_hora)) AS nu_minutos_hora
INTO #base_horaria_mestra
FROM temp_CGUSC.fp.teste_mov_SC M 
INNER JOIN temp_CGUSC.fp.medicamentos_patologia PAT ON PAT.codigo_barra = M.codigo_barra
WHERE M.crm_uf IS NOT NULL AND M.crm IS NOT NULL AND M.crm_uf <> 'BR'
  AND M.data_hora >= @DataInicio AND M.data_hora <= @DataFim
GROUP BY 
    M.cnpj, M.crm, M.crm_uf, 
    YEAR(M.data_hora), MONTH(M.data_hora), 
    CAST(M.data_hora AS DATE), DATEPART(HOUR, M.data_hora);

CREATE CLUSTERED INDEX IDX_Mestra ON #base_horaria_mestra(nu_cnpj, id_medico, competencia);
GO
PRINT '   #base_horaria_mestra concluída.';
GO

-- ----------------------------------------------------------------------------
-- DERIVAÇÃO: #base_agregada_crm_cnpj (Agregação Mensal)
-- Gerada a partir da Mestra para manter compatibilidade com o restante do script.
-- ----------------------------------------------------------------------------
PRINT '>> Derivando #base_agregada_crm_cnpj (Mensal)...';
DROP TABLE IF EXISTS #base_agregada_crm_cnpj;

SELECT
    CONCAT(nu_cnpj, '|', id_medico, '|', CAST(competencia AS VARCHAR(6))) AS chave,
    id_medico, nu_cnpj, competencia,
    CAST(SUM(nu_prescricoes_hora) AS SMALLINT)  AS nu_prescricoes_medico,
    SUM(vl_autorizacoes_hora) AS vl_autorizacoes_medico,
    CAST(MIN(dt_ini_hora) AS DATE)          AS dt_prescricao_inicial_medico,
    CAST(MAX(dt_fim_hora) AS DATE)          AS dt_prescricao_final_medico
INTO #base_agregada_crm_cnpj
FROM #base_horaria_mestra
GROUP BY nu_cnpj, id_medico, competencia;

CREATE CLUSTERED INDEX IDX_BaseAgreg_Key ON #base_agregada_crm_cnpj(nu_cnpj, id_medico, competencia);
GO

-- ----------------------------------------------------------------------------
-- DERIVAÇÃO: #base_diaria_crm (Agregação Diária)
-- ----------------------------------------------------------------------------
PRINT '>> Derivando #base_diaria_crm (Diária)...';
DROP TABLE IF EXISTS #base_diaria_crm;
SELECT
    id_medico, nu_cnpj, competencia, dt_dia,
    SUM(nu_prescricoes_hora)  AS nu_prescricoes_dia,
    MIN(dt_ini_hora)          AS dt_ini_dia,
    MAX(dt_fim_hora)          AS dt_fim_dia,
    DATEDIFF(MINUTE, MIN(dt_ini_hora), MAX(dt_fim_hora)) AS nu_minutos_dia
INTO #base_diaria_crm
FROM #base_horaria_mestra
GROUP BY nu_cnpj, id_medico, competencia, dt_dia;

CREATE CLUSTERED INDEX IDX_BaseDiaria ON #base_diaria_crm(nu_cnpj, id_medico, competencia);
GO

-- ----------------------------------------------------------------------------
-- DERIVAÇÃO: #base_horaria_crm (Agregação Horária)
-- ----------------------------------------------------------------------------
PRINT '>> Derivando #base_horaria_crm (Horária)...';
DROP TABLE IF EXISTS #base_horaria_crm;
SELECT * INTO #base_horaria_crm FROM #base_horaria_mestra;

CREATE CLUSTERED INDEX IDX_BaseHora_Mestra ON #base_horaria_crm(nu_cnpj, id_medico, dt_dia, hr_janela);

-- ----------------------------------------------------------------------------
-- DERIVAÇÃO: #tb_info_estabelecimento (Estabelecimento)
-- ----------------------------------------------------------------------------
PRINT '>> Derivando #tb_info_estabelecimento...';
DROP TABLE IF EXISTS #tb_info_estabelecimento;
SELECT
    nu_cnpj                                   AS cnpj,
    competencia,
    SUM(nu_prescricoes_hora)                  AS nu_autorizacoes_estabelecimento,
    SUM(vl_autorizacoes_hora)                 AS vl_autorizacoes_estabelecimento,
    MIN(dt_ini_hora)                          AS dt_venda_inicial_estabelecimento,
    MAX(dt_fim_hora)                          AS dt_venda_final_estabelecimento
INTO #tb_info_estabelecimento
FROM #base_horaria_mestra
GROUP BY nu_cnpj, competencia;

CREATE CLUSTERED INDEX IDX_InfoEst ON #tb_info_estabelecimento(cnpj, competencia);



-- ============================================================================
-- PASSO 0.0: FILTRO DE RELEVÂNCIA (Whitelist)
-- Identifica médicos com >= 5 prescrições no TOTAL do período para este CNPJ.
-- Evita que médicos constantes mas de baixo volume mensal sejam descartados.
-- ============================================================================
PRINT '>> Passo 0.0: Criando #whitelist_crms_relevantes (Whitelist)...';
DECLARE @t_whitelist DATETIME = GETDATE();
DROP TABLE IF EXISTS #whitelist_crms_relevantes;
SELECT nu_cnpj, id_medico
INTO #whitelist_crms_relevantes
FROM #base_agregada_crm_cnpj
GROUP BY nu_cnpj, id_medico
HAVING SUM(nu_prescricoes_medico) >= 5;

CREATE CLUSTERED INDEX IDX_Whitelist ON #whitelist_crms_relevantes(nu_cnpj, id_medico);
GO



-- ============================================================================
-- PASSO 0.1: ESTABELECIMENTO - PERFIL HORÁRIO E DIÁRIO (Detecção de Surtos)
-- Agora derivado da Mestra, sem ler a tabela de 1 Bilhão de novo!
-- ============================================================================
PRINT '>> Passo 0.1: Criando #base_horaria (Derivado da Mestra)...';
DECLARE @t_scan_mov DATETIME = GETDATE();
DROP TABLE IF EXISTS #base_horaria;

-- Consolidamos os médicos para ter o volume total da farmácia/hora (apenas medicamentos patologia)
SELECT
    nu_cnpj                               AS cnpj,
    competencia,
    dt_dia                                AS dt_janela,
    hr_janela,
    SUM(nu_prescricoes_hora)              AS nu_prescricoes_hora,
    COUNT(DISTINCT id_medico)                AS nu_crms_distintos_hora
INTO #base_horaria
FROM #base_horaria_mestra
GROUP BY nu_cnpj, competencia, dt_dia, hr_janela;

CREATE CLUSTERED INDEX IDX_BH_Surto ON #base_horaria(cnpj, dt_janela, hr_janela);
PRINT '   #base_horaria concluída em: ' + CONVERT(VARCHAR(20), GETDATE() - @t_scan_mov, 114);





-- (Removido índice duplicado)


-- Cálculo de Medianas e Detecção de Surtos (Modified Z-Score — limiar MZS > 4.5)
PRINT '>> Calculando #mediana_hora...';
DECLARE @t_mediana_h DATETIME = GETDATE();
DROP TABLE IF EXISTS #mediana_hora;


SELECT DISTINCT
    cnpj, competencia, hr_janela,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY nu_prescricoes_hora)
        OVER (PARTITION BY cnpj, (competencia / 100), ((competencia % 100 - 1) / 3), hr_janela) AS mediana_hora
INTO #mediana_hora
FROM #base_horaria;

PRINT '   #mediana_hora concluída em: ' + CONVERT(VARCHAR(20), GETDATE() - @t_mediana_h, 114);



-- MAD (Median Absolute Deviation) por farmácia/trimestre/hora — base do MZS
PRINT '>> Calculando #mad_hora...';
DECLARE @t_mad_h DATETIME = GETDATE();
DROP TABLE IF EXISTS #mad_hora;


SELECT DISTINCT
    H.cnpj, H.competencia, H.hr_janela,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ABS(H.nu_prescricoes_hora - M.mediana_hora))
        OVER (PARTITION BY H.cnpj, (H.competencia / 100), ((H.competencia % 100 - 1) / 3), H.hr_janela) AS mad_hora
INTO #mad_hora
FROM #base_horaria H
INNER JOIN #mediana_hora M ON M.cnpj = H.cnpj
                          AND M.competencia = H.competencia
                          AND M.hr_janela = H.hr_janela;

PRINT '   #mad_hora concluída em: ' + CONVERT(VARCHAR(20), GETDATE() - @t_mad_h, 114);



PRINT '>> Detectando Surtos (#anomalias_horarias)...';
DECLARE @t_anomalias_h DATETIME = GETDATE();
DROP TABLE IF EXISTS #anomalias_horarias;
SELECT
    H.*,
    CAST(M.mediana_hora AS DECIMAL(10,2)) AS mediana_hora,
    CAST(MAD.mad_hora   AS DECIMAL(10,4)) AS mad_hora,
    -- MZS = 0.6745 × (xi − mediana) / MAD  →  anômalo se MZS > 4.5 e volume >= 10
    -- Quando MAD = 0 (farmácia perfeitamente constante): qualquer valor acima da mediana é anômalo
    CASE
        WHEN H.nu_prescricoes_hora >= 10
         AND MAD.mad_hora > 0
         AND (0.6745 * (H.nu_prescricoes_hora - M.mediana_hora) / MAD.mad_hora) > 4.5
        THEN 1
        WHEN H.nu_prescricoes_hora >= 10
         AND MAD.mad_hora = 0
         AND H.nu_prescricoes_hora > M.mediana_hora
        THEN 1
        ELSE 0
    END AS is_anomalo_hora
INTO #anomalias_horarias
FROM #base_horaria H
INNER JOIN #mediana_hora M   ON M.cnpj = H.cnpj
                            AND M.competencia = H.competencia
                            AND M.hr_janela = H.hr_janela
INNER JOIN #mad_hora    MAD  ON MAD.cnpj = H.cnpj
                            AND MAD.competencia = H.competencia
                            AND MAD.hr_janela = H.hr_janela;

PRINT '   #anomalias_horarias concluída em: ' + CONVERT(VARCHAR(20), GETDATE() - @t_anomalias_h, 114);

CREATE CLUSTERED INDEX IDX_AnomaliaH ON #anomalias_horarias(cnpj, dt_janela, hr_janela);
GO

-- ============================================================================
-- PASSO 0.4: PIOR HORA/DIA POR (CNPJ / CRM / MÊS)
-- Seleciona a janela (hora) com maior potencial de alerta dentro do mês.
-- ============================================================================
PRINT '>> Passo 0.4: Selecionando #pior_dia_crm (Baseado em Picos Horários)...';
DECLARE @t_pior_dia DATETIME = GETDATE();
DROP TABLE IF EXISTS #pior_dia_crm;

;WITH calc_taxa AS (
    SELECT
        nu_cnpj, id_medico, competencia,
        dt_dia, hr_janela, nu_prescricoes_hora, dt_ini_hora, dt_fim_hora, nu_minutos_hora,
        CASE
            WHEN nu_minutos_hora = 0 THEN CAST(nu_prescricoes_hora AS FLOAT) * 60.0
            ELSE CAST(nu_prescricoes_hora AS DECIMAL(10,2)) / (CAST(NULLIF(nu_minutos_hora, 0) AS DECIMAL(10,2)) / 60.0)
        END AS taxa_hora
    FROM #base_horaria_crm
    WHERE nu_prescricoes_hora >= 5
),
ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY nu_cnpj, id_medico, competencia
            ORDER BY
                CASE
                    WHEN nu_prescricoes_hora >= 5  AND nu_minutos_hora <= 5                                                                                                   THEN 1
                    WHEN nu_prescricoes_hora >= 5  AND taxa_hora >= 12                                                                                                       THEN 2
                    WHEN nu_prescricoes_hora >= 10 AND (taxa_hora >= 7 OR nu_minutos_hora <= 60)                                                                             THEN 3
                    ELSE 99
                END ASC,
                taxa_hora DESC,
                nu_prescricoes_hora DESC
        ) AS rn
    FROM calc_taxa
)
SELECT nu_cnpj, id_medico, competencia,
       dt_dia, CAST(nu_prescricoes_hora AS SMALLINT) AS nu_prescricoes_pico_h, dt_ini_hora AS dt_ini_dia, dt_fim_hora AS dt_fim_dia, 
       nu_minutos_hora AS nu_minutos_dia, CAST(taxa_hora AS DECIMAL(7,2)) AS taxa_dia
INTO #pior_dia_crm
FROM ranked
WHERE rn = 1;

CREATE CLUSTERED INDEX IDX_PiorDia ON #pior_dia_crm(nu_cnpj, id_medico, competencia);
GO

-- ============================================================================
-- MOTOR TEMPORAL: crm_unico_alertas (Master Temporal)
-- ============================================================================
PRINT '>> Criando temp_CGUSC.fp.crm_unico_alertas (Master Temporal)...';
DECLARE @t_alert_t DATETIME = GETDATE();
DROP TABLE IF EXISTS temp_CGUSC.fp.crm_unico_alertas;

;WITH base_com_taxa AS (
    SELECT
        nu_cnpj, id_medico, competencia,
        dt_dia, hr_janela, nu_prescricoes_hora, nu_minutos_hora,
        CASE WHEN nu_minutos_hora = 0 THEN CAST(nu_prescricoes_hora AS FLOAT) * 60.0
             ELSE CAST(nu_prescricoes_hora AS DECIMAL(10,2)) / (CAST(NULLIF(nu_minutos_hora, 0) AS DECIMAL(10,2)) / 60.0)
        END AS taxa_hora
    FROM #base_horaria_crm
),
alertas AS (
    SELECT
        nu_cnpj                                          AS cnpj,
        id_medico,
        competencia,
        dt_dia                                           AS dt_alerta,
        hr_janela,
        nu_prescricoes_hora                              AS nu_prescricoes_dia,
        nu_minutos_hora                                  AS nu_minutos_dia,
        CAST(taxa_hora AS DECIMAL(5,1))                   AS taxa_hora
    FROM base_com_taxa
    WHERE
        (nu_prescricoes_hora >= 5  AND (taxa_hora >= 12 OR nu_minutos_hora <= 5))
     OR (nu_prescricoes_hora >= 10 AND (taxa_hora >= 7 OR nu_minutos_hora <= 60))
)
SELECT * INTO temp_CGUSC.fp.crm_unico_alertas FROM alertas;

CREATE CLUSTERED INDEX IDX_ConcTemp ON temp_CGUSC.fp.crm_unico_alertas(cnpj, id_medico, dt_alerta);


-- Identifica quais CRMs participaram de algum surto no CNPJ/Competencia
PRINT '>> Identificando médicos em surto (#crms_em_surto)...';
DECLARE @t_crms_surto DATETIME = GETDATE();
DROP TABLE IF EXISTS #crms_em_surto_raw;
SELECT DISTINCT
    M.nu_cnpj,
    M.id_medico,
    M.competencia
INTO #crms_em_surto_raw
FROM #base_horaria_mestra M
INNER JOIN #anomalias_horarias A ON A.cnpj = M.nu_cnpj
    AND A.dt_janela = M.dt_dia
    AND A.hr_janela = M.hr_janela
WHERE A.is_anomalo_hora = 1;

PRINT '   #crms_em_surto concluída em: ' + CONVERT(VARCHAR(20), GETDATE() - @t_crms_surto, 114);


-- TOTAIS DIARIOS PARA MEDIANA DIARIA
PRINT '>> Criando #totais_diarios...';
DECLARE @t_totais_d DATETIME = GETDATE();
DROP TABLE IF EXISTS #totais_diarios;
SELECT
    cnpj, competencia, dt_janela,
    SUM(nu_prescricoes_hora) AS nu_prescricoes_dia,
    MAX(is_anomalo_hora)     AS dia_tem_anomalia_hora
INTO #totais_diarios
FROM #anomalias_horarias
GROUP BY cnpj, competencia, dt_janela;

PRINT '   #totais_diarios concluída em: ' + CONVERT(VARCHAR(20), GETDATE() - @t_totais_d, 114);

PRINT '>> Calculando #mediana_diaria...';
DECLARE @t_mediana_d DATETIME = GETDATE();
DROP TABLE IF EXISTS #mediana_diaria;
SELECT DISTINCT
    cnpj, competencia,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY nu_prescricoes_dia)
        OVER (PARTITION BY cnpj, (competencia / 100), ((competencia % 100 - 1) / 3)) AS mediana_diaria
INTO #mediana_diaria
FROM #totais_diarios;

PRINT '   #mediana_diaria concluída em: ' + CONVERT(VARCHAR(20), GETDATE() - @t_mediana_d, 114);

CREATE CLUSTERED INDEX IDX_MedianaDia ON #mediana_diaria(cnpj, competencia);

-- 4. Tabela Final 1: crm_multiplos_perfil_diario (Gráfico Principal)
PRINT '>> Passo 4: Criando crm_multiplos_perfil_diario (Gráfico Principal)...';
DECLARE @t_perfil_d DATETIME = GETDATE();
DROP TABLE IF EXISTS temp_CGUSC.fp.crm_multiplos_perfil_diario;

;WITH crms_distintos_dia AS (
    SELECT
        nu_cnpj AS cnpj, 
        dt_dia AS dt_janela,
        COUNT(DISTINCT id_medico) AS nu_crms_distintos
    FROM #base_horaria_mestra
    GROUP BY nu_cnpj, dt_dia
)

SELECT
    T.cnpj, T.competencia, T.dt_janela, T.nu_prescricoes_dia,
    ISNULL(C.nu_crms_distintos, 0) AS nu_crms_distintos,
    CAST(M.mediana_diaria AS DECIMAL(10,2)) AS mediana_diaria,
    -- O dia é anômalo se tiver uma rajada horária (Regra Standard 7x Mediana)
    T.dia_tem_anomalia_hora AS is_anomalo
INTO temp_CGUSC.fp.crm_multiplos_perfil_diario
FROM #totais_diarios T
INNER JOIN #mediana_diaria M ON M.cnpj = T.cnpj AND M.competencia = T.competencia
LEFT JOIN crms_distintos_dia C ON C.cnpj = T.cnpj AND C.dt_janela = T.dt_janela;

PRINT '   crm_multiplos_perfil_diario concluída em: ' + CONVERT(VARCHAR(20), GETDATE() - @t_perfil_d, 114);

CREATE CLUSTERED INDEX IDX_DailyProfile ON temp_CGUSC.fp.crm_multiplos_perfil_diario(cnpj, dt_janela);

-- 5. Tabela Final 2: crm_perfil_horario (Drill-down unificado: CRM Múltiplos + CRM Único)
-- is_crm_multiplos = 1 → dia tem surto horário detectado (volume MZS > 4.5)
-- is_crm_unico     = 1 → dia tem alerta de concentração temporal (médico com taxa/dia elevada)
-- Um dia pode ter ambos os flags ativos simultaneamente.
PRINT '>> Passo 5: Criando crm_perfil_horario (Drill-down Unificado)...';
DECLARE @t_perfil_h DATETIME = GETDATE();
DROP TABLE IF EXISTS temp_CGUSC.fp.crm_perfil_horario;

SELECT
    H.cnpj,
    H.dt_janela,
    H.hr_janela,
    H.nu_prescricoes_hora    AS nu_prescricoes,
    H.nu_crms_distintos_hora AS nu_crms_diferentes,
    H.mediana_hora,
    H.is_anomalo_hora,
    CAST(CASE WHEN D.is_anomalo = 1   THEN 1 ELSE 0 END AS BIT) AS is_crm_multiplos,
    CAST(CASE WHEN U.cnpj IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS is_crm_unico
INTO temp_CGUSC.fp.crm_perfil_horario
FROM #anomalias_horarias H
LEFT JOIN temp_CGUSC.fp.crm_multiplos_perfil_diario D
    ON  D.cnpj     = H.cnpj
    AND D.dt_janela = H.dt_janela
    AND D.is_anomalo = 1
LEFT JOIN (SELECT DISTINCT cnpj, dt_alerta FROM temp_CGUSC.fp.crm_unico_alertas) U
    ON  U.cnpj     = H.cnpj
    AND U.dt_alerta = H.dt_janela
WHERE D.is_anomalo = 1 OR U.cnpj IS NOT NULL;

PRINT '   crm_perfil_horario concluída em: ' + CONVERT(VARCHAR(20), GETDATE() - @t_perfil_h, 114);

CREATE CLUSTERED INDEX IDX_PerfilHorario ON temp_CGUSC.fp.crm_perfil_horario(cnpj, dt_janela, hr_janela);

-- 6. Tabela Final 3: crm_multiplos_alertas (Mestre de Surtos)
PRINT '>> Passo 6: Criando crm_multiplos_alertas (Mestre de Surtos)...';
DECLARE @t_alertas_m DATETIME = GETDATE();
DROP TABLE IF EXISTS temp_CGUSC.fp.crm_multiplos_alertas;



SELECT
    cnpj, competencia, dt_janela AS dt_alerta, hr_janela,
    nu_prescricoes_hora AS nu_prescricoes,
    nu_crms_distintos_hora AS nu_crms,
    mediana_hora,
    CAST(CAST(nu_prescricoes_hora AS DECIMAL(10,2)) / NULLIF(mediana_hora, 0) AS DECIMAL(10,1)) AS multiplicador
INTO temp_CGUSC.fp.crm_multiplos_alertas
FROM #anomalias_horarias
WHERE is_anomalo_hora = 1;

PRINT '   crm_multiplos_alertas concluída em: ' + CONVERT(VARCHAR(20), GETDATE() - @t_alertas_m, 114);



CREATE CLUSTERED INDEX IDX_AlertaSequencialCNPJ ON temp_CGUSC.fp.crm_multiplos_alertas(cnpj, dt_alerta, hr_janela);

-- 7. Tabela Final 4: crm_multiplos_detalhe (Raio-X Sub-horário)
-- Busca cirúrgica direto na fonte para as horas doentes detectadas.
-- ============================================================================
PRINT '>> Passo 7: Criando crm_multiplos_detalhe (Busca Cirúrgica)...';
DECLARE @t_detalhe_m DATETIME = GETDATE();
DROP TABLE IF EXISTS temp_CGUSC.fp.crm_multiplos_detalhe;

SELECT
    A.cnpj,
    A.competencia,
    A.dt_alerta                  AS dt_janela,
    A.hr_janela,
    M.data_hora,
    M.num_autorizacao,
    CAST(M.crm AS VARCHAR(10)) + '/' + M.crm_uf AS id_medico,
    M.codigo_barra,
    M.valor_pago
INTO temp_CGUSC.fp.crm_multiplos_detalhe
FROM temp_CGUSC.fp.crm_multiplos_alertas A
INNER JOIN temp_CGUSC.fp.teste_mov_SC M 
    ON  M.cnpj = A.cnpj
    AND CAST(M.data_hora AS DATE) = A.dt_alerta
    AND DATEPART(HOUR, M.data_hora) = A.hr_janela
INNER JOIN temp_CGUSC.fp.medicamentos_patologia PAT ON PAT.codigo_barra = M.codigo_barra
WHERE M.crm_uf IS NOT NULL AND M.crm IS NOT NULL AND M.crm_uf <> 'BR';

PRINT '   crm_multiplos_detalhe concluída em: ' + CONVERT(VARCHAR(20), GETDATE() - @t_detalhe_m, 114);

CREATE CLUSTERED INDEX IDX_AlertaSeqDetalhe ON temp_CGUSC.fp.crm_multiplos_detalhe(cnpj, dt_janela, hr_janela);


-- (As derivações foram movidas para o início do script para evitar erros de dependência)



-- (Removido daqui e movido para antes das visualizações)



-- (O Passo 0.5 foi movido para o início para alimentar a #lista_alertas_temp)




GO
-- GO: base_agregada_crm_cnpj e #tb_info_estabelecimento existem com schema novo antes do próximo batch.


-- ============================================================================
-- BASE TEMPORÁRIA PARA ALERTAS
-- (substitui #lista_medicos_farmacia_popularFP_temp e _temp2)
-- ============================================================================

PRINT '>> Criando #lista_alertas_temp (Base de Alertas)...';
DECLARE @t_lista_a DATETIME = GETDATE();
DROP TABLE IF EXISTS #lista_alertas_temp;

SELECT
    A.nu_cnpj,
    A.id_medico,
    A.competencia,
    A.nu_prescricoes_medico,
    A.vl_autorizacoes_medico,
    A.dt_prescricao_inicial_medico,
    A.dt_prescricao_final_medico,
    DATEDIFF(DAY, A.dt_prescricao_inicial_medico, A.dt_prescricao_final_medico) + 1 AS nu_dias,
    -- Dados do Pico Horário (Vem da #pior_dia_crm)
    ISNULL(P.nu_prescricoes_pico_h, 0)                                               AS nu_prescricoes_pico_h,
    ISNULL(P.nu_minutos_dia, 0)                                                  AS nu_minutos_pico_h,
    ISNULL(P.taxa_dia, 0)                                                        AS taxa_pico_h,
    -- Estatísticas do Estabelecimento
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
    AND P.id_medico   = A.id_medico
    AND P.competencia = A.competencia
WHERE EXISTS (
        SELECT 1 FROM #whitelist_crms_relevantes W 
        WHERE W.nu_cnpj = A.nu_cnpj AND W.id_medico = A.id_medico
    )
    OR EXISTS (
        SELECT 1 FROM #crms_em_surto_raw SR 
        WHERE SR.nu_cnpj = A.nu_cnpj 
            AND SR.id_medico = A.id_medico 
            AND SR.competencia = A.competencia
    );

PRINT '   #lista_alertas_temp concluída em: ' + CONVERT(VARCHAR(20), GETDATE() - @t_lista_a, 114);
GO




GO


-- ============================================================================
-- TOTAIS NACIONAIS POR MÉDICO / COMPETÊNCIA
-- ============================================================================
PRINT '>> Criando #prescricoes_todos_estabelecimentos (Base Nacional)...';
DECLARE @t_base_nac DATETIME = GETDATE();
DROP TABLE IF EXISTS #prescricoes_todos_estabelecimentos;



SELECT
    id_medico,
    competencia,
    SUM(nu_prescricoes_medico)                                    AS nu_prescricoes_medico_em_todos_estabelecimentos,
    COUNT(DISTINCT nu_cnpj)                                       AS nu_estabelecimentos_com_registro_mesmo_crm,
    CAST(SUM(nu_prescricoes_medico) AS DECIMAL(18,2)) /
        NULLIF(CAST(
            DATEDIFF(DAY, MIN(dt_prescricao_inicial_medico), MAX(dt_prescricao_final_medico)) + 1
        AS DECIMAL(18,2)), 0)                                     AS nu_prescricoes_pico_h_em_todos_estabelecimentos
INTO #prescricoes_todos_estabelecimentos
FROM #base_agregada_crm_cnpj
GROUP BY id_medico, competencia;

PRINT '   #prescricoes_todos_estabelecimentos concluída em: ' + CONVERT(VARCHAR(20), GETDATE() - @t_base_nac, 114);


GO


-- ============================================================================
-- NORMALIZAÇÃO: DIMENSÕES (Apenas Médicos para ID numérico)
-- ============================================================================

-- (Removido: dim_crm não é mais utilizado)

-- ============================================================================
-- TABELA FINAL: dados_crm_detalhado
-- ============================================================================
PRINT '>> Criando temp_CGUSC.fp.dados_crm_detalhado (Tabela de Estágio)...';
DECLARE @t_dados_det DATETIME = GETDATE();
DROP TABLE IF EXISTS temp_CGUSC.fp.dados_crm_detalhado;



SELECT
    A.nu_cnpj,
    A.competencia,
    A.id_medico,
    A.nu_prescricoes_medico,
    A.vl_autorizacoes_medico,
    A.nu_prescricoes_pico_h,
    A.taxa_pico_h,
    A.dt_prescricao_inicial_medico,
    A.dt_prescricao_final_medico
INTO temp_CGUSC.fp.dados_crm_detalhado
FROM #lista_alertas_temp A
LEFT JOIN temp_CGUSC.fp.dados_farmacia            F   ON F.cnpj     = A.nu_cnpj
INNER JOIN #prescricoes_todos_estabelecimentos    P
    ON  P.id_medico   = A.id_medico
    AND P.competencia = A.competencia;

PRINT '   temp_CGUSC.fp.dados_crm_detalhado concluída em: ' + CONVERT(VARCHAR(20), GETDATE() - @t_dados_det, 114);



CREATE CLUSTERED INDEX IDX_DadosDet ON temp_CGUSC.fp.dados_crm_detalhado(nu_cnpj, id_medico, competencia);
GO




-- (Removido daqui e movido para antes das visualizações)




-- ============================================================================
-- VISUALIZAÇÃO CRM ÚNICO: crm_unico_perfil_diario
-- Grain: (cnpj, dt_dia)
-- Série diária de prescrições da farmácia, com flag se houve anomalia
-- de QUALQUER médico naquele dia (Sequência/Concentração).
-- ============================================================================
PRINT '>> Criando temp_CGUSC.fp.crm_unico_perfil_diario (Perfil Diário)...';
DECLARE @t_perfil_u DATETIME = GETDATE();
DROP TABLE IF EXISTS temp_CGUSC.fp.crm_unico_perfil_diario;



;WITH anomalias_dia AS (
    SELECT DISTINCT cnpj, dt_alerta
    FROM temp_CGUSC.fp.crm_unico_alertas
),
daily_stats AS (
    SELECT 
        nu_cnpj AS cnpj,
        competencia,
        dt_dia AS dt_janela,
        SUM(nu_prescricoes_dia) AS nu_prescricoes_dia,
        COUNT(DISTINCT id_medico) AS nu_crms_distintos
    FROM #base_diaria_crm
    GROUP BY nu_cnpj, competencia, dt_dia
)
SELECT
    S.cnpj,
    S.competencia,
    S.dt_janela,
    S.nu_prescricoes_dia,
    S.nu_crms_distintos,
    CAST(M.mediana_diaria AS DECIMAL(10,2)) AS mediana_diaria,
    CASE WHEN A.dt_alerta IS NOT NULL THEN 1 ELSE 0 END AS is_anomalo
INTO temp_CGUSC.fp.crm_unico_perfil_diario
FROM daily_stats S
INNER JOIN #mediana_diaria M ON M.cnpj = S.cnpj AND M.competencia = S.competencia
LEFT JOIN anomalias_dia A ON A.cnpj = S.cnpj AND A.dt_alerta = S.dt_janela;

PRINT '   temp_CGUSC.fp.crm_unico_perfil_diario concluída em: ' + CONVERT(VARCHAR(20), GETDATE() - @t_perfil_u, 114);



CREATE CLUSTERED INDEX IDX_UnicoDaily ON temp_CGUSC.fp.crm_unico_perfil_diario(cnpj, dt_janela);

-- ============================================================================
-- DETALHAMENTO RAIO-X: crm_unico_detalhe
-- Grain: (num_autorizacao)
-- Salva TODAS as transações da farmácia nos dias em que houve alerta
-- de CRM único, para permitir visualizar as rajadas no contexto do dia.
-- ============================================================================

PRINT '>> Criando temp_CGUSC.fp.crm_unico_detalhe (Busca Cirúrgica Raio-X)...';
DECLARE @t_detalhe_u DATETIME = GETDATE();
DROP TABLE IF EXISTS temp_CGUSC.fp.crm_unico_detalhe;

;WITH dias_alerta AS (
    SELECT DISTINCT cnpj, dt_alerta
    FROM temp_CGUSC.fp.crm_unico_alertas
)
SELECT
    D.cnpj,
    D.dt_alerta                  AS dt_janela,
    M.data_hora,
    M.num_autorizacao,
    CAST(M.crm AS VARCHAR(10)) + '/' + M.crm_uf AS id_medico,
    M.codigo_barra,
    M.valor_pago
INTO temp_CGUSC.fp.crm_unico_detalhe
FROM dias_alerta D
INNER JOIN temp_CGUSC.fp.teste_mov_SC M 
    ON  M.cnpj = D.cnpj
    AND CAST(M.data_hora AS DATE) = D.dt_alerta
INNER JOIN temp_CGUSC.fp.medicamentos_patologia PAT ON PAT.codigo_barra = M.codigo_barra
WHERE M.crm_uf IS NOT NULL AND M.crm IS NOT NULL AND M.crm_uf <> 'BR';

PRINT '   temp_CGUSC.fp.crm_unico_detalhe concluída em: ' + CONVERT(VARCHAR(20), GETDATE() - @t_detalhe_u, 114);




CREATE CLUSTERED INDEX IDX_UnicoDetalhe ON temp_CGUSC.fp.crm_unico_detalhe(cnpj, dt_janela);

GO


-- ============================================================================
-- MOTOR GEOGRÁFICO: alertas_crm_geografico (v5 — Tabela Master)
-- Grain: (nu_crm, sg_uf_crm, competencia)
-- ============================================================================

PRINT '>> Criando temp_CGUSC.fp.alertas_crm_geografico (Master Geográfica)...';
DECLARE @t_geo DATETIME = GETDATE();
DROP TABLE IF EXISTS temp_CGUSC.fp.alertas_crm_geografico;
-- Seleciona apenas registros que atendem ao piso de 30 prescrições (pré-filtro para evitar explosão no self-join)
DROP TABLE IF EXISTS #base_com_geo;
SELECT 
    D.nu_cnpj,
    D.id_medico,
    D.competencia,
    D.nu_prescricoes_medico,
    D.dt_prescricao_inicial_medico,
    D.dt_prescricao_final_medico,
    G.latitude,
    G.longitude,
    F.uf                             AS sg_uf
INTO #base_com_geo
FROM temp_CGUSC.fp.dados_crm_detalhado D
LEFT JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = D.nu_cnpj
LEFT JOIN temp_CGUSC.sus.tb_ibge G ON G.id_ibge7 = F.codibge
WHERE D.nu_prescricoes_medico >= 30;

CREATE CLUSTERED INDEX IDX_GeoBase ON #base_com_geo(id_medico, competencia);

;WITH PairedWithDistance AS (
    SELECT
        T1.competencia,
        T1.id_medico,
        T1.nu_cnpj                      AS cnpj_a,
        T1.dt_prescricao_inicial_medico  AS dt_ini_a,
        T1.dt_prescricao_final_medico    AS dt_fim_a,
        T1.sg_uf                         AS sg_uf_a,
        T1.nu_prescricoes_medico         AS nu_prescricoes_a,
        T2.nu_cnpj                      AS cnpj_b,
        T2.dt_prescricao_inicial_medico  AS dt_ini_b,
        T2.dt_prescricao_final_medico    AS dt_fim_b,
        T2.sg_uf                         AS sg_uf_b,
        T2.nu_prescricoes_medico         AS nu_prescricoes_b,
        CASE
            WHEN (ABS(T1.latitude - T2.latitude) > 2.0 OR ABS(T1.longitude - T2.longitude) > 2.0)
            THEN temp_CGUSC.fp.fnCalcular_Distancia_KM(T1.latitude, T1.longitude, T2.latitude, T2.longitude)
            ELSE 0
        END AS distancia_km
    FROM #base_com_geo T1
    INNER JOIN #base_com_geo T2
        ON  T2.id_medico   = T1.id_medico
        AND T1.nu_cnpj     < T2.nu_cnpj
        AND T1.competencia = T2.competencia
),
ParesFiltrados AS (
    SELECT * FROM PairedWithDistance
    WHERE distancia_km > 400
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
    CAST(P.sg_uf_a AS VARCHAR(2))          AS sg_uf_a,
    P.dt_ini_a,
    P.dt_fim_a,
    P.nu_prescricoes_a,
    P.cnpj_b,
    CAST(P.sg_uf_b AS VARCHAR(2))          AS sg_uf_b,
    P.dt_ini_b,
    P.dt_fim_b,
    P.nu_prescricoes_b,
    CAST(P.distancia_km AS DECIMAL(10,2))  AS distancia_km,
    T.total_pares
INTO temp_CGUSC.fp.alertas_crm_geografico
FROM ParesPriorizados P
INNER JOIN TotaisPorMedico T 
    ON  T.id_medico   = P.id_medico 
    AND T.competencia = P.competencia
WHERE P.rn = 1;

PRINT '   temp_CGUSC.fp.alertas_crm_geografico concluída em: ' + CONVERT(VARCHAR(20), GETDATE() - @t_geo, 114);



CREATE CLUSTERED INDEX IDX_GeoAlerta ON temp_CGUSC.fp.alertas_crm_geografico(id_medico, competencia);
GO


GO


-- ============================================================================
-- MOTOR DE REGISTRO: alertas_crm_registro (v5 — Tabela Master)
-- ============================================================================
PRINT '>> Criando temp_CGUSC.fp.alertas_crm_registro (Master Registro)...';
DECLARE @t_reg DATETIME = GETDATE();
DROP TABLE IF EXISTS temp_CGUSC.fp.alertas_crm_registro;

-- INEXISTENTE: CRM não encontrado no mapeamento CFM
SELECT
    A.nu_cnpj                                                       AS cnpj,
    A.id_medico,
    A.competencia,
    CONVERT(VARCHAR(20), MIN(A.dt_prescricao_inicial_medico), 103)  AS dt_primeira_presc,
    CAST(NULL AS VARCHAR(20))                                        AS dt_registro_crm,
    CAST('INEXISTENTE' AS VARCHAR(20))                               AS tipo_anomalia,
    SUM(A.nu_prescricoes_medico)                                     AS nu_prescricoes,
    SUM(A.vl_autorizacoes_medico)                                    AS vl_prescricoes
INTO temp_CGUSC.fp.alertas_crm_registro
FROM temp_CGUSC.fp.dados_crm_detalhado A
LEFT JOIN temp_CGUSC.fp.dados_medico M ON M.id_medico = A.id_medico
WHERE M.id_medico IS NULL
GROUP BY A.nu_cnpj, A.id_medico, A.competencia;

GO

DECLARE @t_reg DATETIME = GETDATE();
-- IRREGULAR: CRM existe mas prescrição ocorreu antes da data de inscrição
INSERT INTO temp_CGUSC.fp.alertas_crm_registro
    (cnpj, id_medico, competencia,
     dt_primeira_presc, dt_registro_crm, tipo_anomalia,
     nu_prescricoes, vl_prescricoes)
SELECT
    A.nu_cnpj                                                              AS cnpj,
    A.id_medico,
    A.competencia,
    CONVERT(VARCHAR(20), MIN(A.dt_prescricao_inicial_medico), 103)         AS dt_primeira_presc,
    CONVERT(VARCHAR(20), M.dt_inscricao, 103)                              AS dt_registro_crm,
    'IRREGULAR'                                                            AS tipo_anomalia,
    SUM(A.nu_prescricoes_medico)                                           AS nu_prescricoes,
    SUM(A.vl_autorizacoes_medico)                                          AS vl_prescricoes
FROM temp_CGUSC.fp.dados_crm_detalhado A
INNER JOIN temp_CGUSC.fp.dados_medico M ON M.id_medico = A.id_medico
WHERE M.dt_inscricao > A.dt_prescricao_inicial_medico
GROUP BY A.nu_cnpj, A.id_medico, A.competencia, M.dt_inscricao;

PRINT '   temp_CGUSC.fp.alertas_crm_registro concluída em: ' + CONVERT(VARCHAR(20), GETDATE() - @t_reg, 114);

CREATE CLUSTERED INDEX IDX_Registro ON temp_CGUSC.fp.alertas_crm_registro(cnpj, id_medico, competencia);
GO


GO


-- ============================================================================
-- CONSOLIDADOR: alertas_crm (v5 — Tabela de Flags/Metadados)
PRINT '>> Criando temp_CGUSC.fp.alertas_crm (Consolidador)...';
DECLARE @t_cons DATETIME = GETDATE();
DROP TABLE IF EXISTS temp_CGUSC.fp.alertas_crm;



;WITH base AS (
    SELECT DISTINCT A1.cnpj AS nu_cnpj, A1.id_medico, A1.competencia
    FROM temp_CGUSC.fp.crm_unico_alertas A1
    UNION
    SELECT G1.cnpj_a AS nu_cnpj, G1.id_medico, G1.competencia
    FROM temp_CGUSC.fp.alertas_crm_geografico G1
    UNION
    SELECT G2.cnpj_b AS nu_cnpj, G2.id_medico, G2.competencia
    FROM temp_CGUSC.fp.alertas_crm_geografico G2
    UNION
    SELECT DISTINCT R1.cnpj AS nu_cnpj, R1.id_medico, R1.competencia
    FROM temp_CGUSC.fp.alertas_crm_registro R1
    UNION
    SELECT S1.nu_cnpj, S1.id_medico, S1.competencia
    FROM #crms_em_surto_raw S1
),
conc_agg AS (
    SELECT C1.cnpj, C1.id_medico, C1.competencia, COUNT(*) AS qtd_dias
    FROM temp_CGUSC.fp.crm_unico_alertas C1
    GROUP BY C1.cnpj, C1.id_medico, C1.competencia
),
geo_cnpj AS (
    SELECT T.nu_cnpj, T.id_medico, T.competencia FROM (
        SELECT G3.cnpj_a AS nu_cnpj, G3.id_medico, G3.competencia FROM temp_CGUSC.fp.alertas_crm_geografico G3
        UNION ALL
        SELECT G4.cnpj_b AS nu_cnpj, G4.id_medico, G4.competencia FROM temp_CGUSC.fp.alertas_crm_geografico G4
    ) T
)
SELECT
    B.nu_cnpj,
    B.id_medico,
    B.competencia,
    CAST(CASE WHEN CA.id_medico     IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS flag_concentracao,
    CAST(CASE WHEN GC.id_medico     IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS flag_geografico,
    CAST(CASE WHEN RE.id_medico     IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS flag_registro,
    CAST(CASE WHEN SR.id_medico     IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS flag_concentracao_estabelecimento,
    ISNULL(CA.qtd_dias, 0)                                             AS qtd_dias_concentracao
INTO temp_CGUSC.fp.alertas_crm
FROM base B
LEFT JOIN conc_agg CA
    ON  CA.cnpj       = B.nu_cnpj
    AND CA.id_medico  = B.id_medico
    AND CA.competencia = B.competencia
LEFT JOIN #crms_em_surto_raw SR
    ON  SR.nu_cnpj    = B.nu_cnpj
    AND SR.id_medico  = B.id_medico
    AND SR.competencia = B.competencia
LEFT JOIN geo_cnpj GC
    ON  GC.id_medico   = B.id_medico
    AND GC.competencia = B.competencia
    AND GC.nu_cnpj    = B.nu_cnpj
LEFT JOIN (
    SELECT DISTINCT R2.cnpj, R2.id_medico, R2.competencia
    FROM temp_CGUSC.fp.alertas_crm_registro R2
) RE ON RE.cnpj = B.nu_cnpj AND RE.id_medico = B.id_medico AND RE.competencia = B.competencia;

PRINT '   temp_CGUSC.fp.alertas_crm concluída em: ' + CONVERT(VARCHAR(20), GETDATE() - @t_cons, 114);
GO



CREATE CLUSTERED INDEX IDX_Alertas_Key ON temp_CGUSC.fp.alertas_crm(nu_cnpj, id_medico, competencia);
GO
GO


-- ============================================================================
-- TABELA DE EXPORTAÇÃO: crm_export (v5)
-- ============================================================================
PRINT '>> Criando temp_CGUSC.fp.crm_export (Tabela Final)...';
DECLARE @t_exp DATETIME = GETDATE();
DROP TABLE IF EXISTS temp_CGUSC.fp.crm_export;



SELECT
    A.id_medico,
    A.nu_cnpj                                                         AS cnpj,
    A.competencia,
    A.nu_prescricoes_medico                                           AS nu_prescricoes_mes,
    A.vl_autorizacoes_medico                                          AS vl_total_prescricoes,
    A.nu_prescricoes_pico_h,
    A.taxa_pico_h,
    P.nu_prescricoes_medico_em_todos_estabelecimentos                 AS nu_prescricoes_total_brasil,
    P.nu_estabelecimentos_com_registro_mesmo_crm                      AS nu_estabelecimentos,
    CAST(CASE WHEN CONC.cnpj IS NOT NULL THEN 1 ELSE 0 END AS BIT)   AS flag_concentracao_mesmo_crm,
    CAST(CASE WHEN G.id_medico IS NOT NULL THEN 1 ELSE 0 END AS BIT)   AS flag_distancia_geografica,
    A.dt_prescricao_inicial_medico                                     AS dt_primeira_prescricao,
    M.dt_inscricao                                                     AS dt_inscricao_crm,
    -- Flags CFM por competência
    CASE WHEN REG_INV.cnpj IS NOT NULL THEN 1 ELSE 0 END              AS flag_crm_invalido,
    CASE WHEN REG_IRR.cnpj IS NOT NULL THEN 1 ELSE 0 END              AS flag_prescricao_antes_registro,
    ISNULL(AL.flag_concentracao_estabelecimento, 0)                   AS flag_concentracao_estabelecimento
INTO temp_CGUSC.fp.crm_export
FROM temp_CGUSC.fp.dados_crm_detalhado A
LEFT JOIN temp_CGUSC.fp.dados_medico M ON M.id_medico = A.id_medico
LEFT JOIN temp_CGUSC.fp.alertas_crm AL
    ON  AL.nu_cnpj    = A.nu_cnpj 
    AND AL.id_medico  = A.id_medico 
    AND AL.competencia = A.competencia
LEFT JOIN #prescricoes_todos_estabelecimentos P
    ON  P.id_medico   = A.id_medico
    AND P.competencia = A.competencia
LEFT JOIN (
    SELECT DISTINCT cnpj, id_medico, competencia
    FROM temp_CGUSC.fp.crm_unico_alertas
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

PRINT '   temp_CGUSC.fp.crm_export concluída em: ' + CONVERT(VARCHAR(20), GETDATE() - @t_exp, 114);

GO




IF EXISTS (SELECT * FROM temp_CGUSC.sys.indexes WHERE name = 'IDX_CrmExport_Key' AND object_id = OBJECT_ID('temp_CGUSC.fp.crm_export'))
    DROP INDEX IDX_CrmExport_Key ON temp_CGUSC.fp.crm_export;

CREATE CLUSTERED INDEX IDX_CrmExport_Key
    ON temp_CGUSC.fp.crm_export(cnpj, id_medico, competencia);
GO


-- ============================================================================
-- BASE PARA BENCHMARKS: #indicador_crm (temp)
-- ============================================================================


PRINT '>> Criando #indicador_crm (Benchmark Base)...';
DECLARE @t_ind DATETIME = GETDATE();
DROP TABLE IF EXISTS #indicador_crm;

;WITH
Totais AS (
    SELECT
        nu_cnpj                     AS cnpj,
        competencia,
        SUM(nu_prescricoes_medico)   AS total_prescricoes,
        SUM(vl_autorizacoes_medico)  AS total_valor,
        COUNT(DISTINCT id_medico)    AS total_prescritores
    FROM temp_CGUSC.fp.dados_crm_detalhado
    GROUP BY nu_cnpj, competencia
),
Top5 AS (
    SELECT
        cnpj, competencia,
        MAX(CASE WHEN rk = 1 THEN id_medico END) AS id_top1,
        SUM(CASE WHEN rk = 1 THEN vl_total_prescricoes ELSE 0 END)         AS vl_top1,
        SUM(CASE WHEN rk <= 5 THEN vl_total_prescricoes ELSE 0 END)        AS vl_top5
    FROM (
        SELECT nu_cnpj AS cnpj, competencia, id_medico, vl_autorizacoes_medico AS vl_total_prescricoes,
               ROW_NUMBER() OVER (PARTITION BY nu_cnpj, competencia
                                  ORDER BY vl_autorizacoes_medico DESC) AS rk
        FROM temp_CGUSC.fp.dados_crm_detalhado
    ) R
    WHERE rk <= 5
    GROUP BY cnpj, competencia
),
Anomalias AS (
    SELECT
        A.nu_cnpj AS cnpj, A.competencia,
        COUNT(CASE WHEN REG_INV.cnpj IS NOT NULL THEN 1 END) AS qtd_crm_invalido,
        COUNT(CASE WHEN REG_IRR.cnpj IS NOT NULL THEN 1 END) AS qtd_antes_registro
    FROM temp_CGUSC.fp.dados_crm_detalhado A
    LEFT JOIN temp_CGUSC.fp.alertas_crm_registro REG_INV
        ON  REG_INV.cnpj          = A.nu_cnpj
        AND REG_INV.id_medico     = A.id_medico
        AND REG_INV.competencia   = A.competencia
        AND REG_INV.tipo_anomalia = 'INEXISTENTE'
    LEFT JOIN temp_CGUSC.fp.alertas_crm_registro REG_IRR
        ON  REG_IRR.cnpj          = A.nu_cnpj
        AND REG_IRR.id_medico     = A.id_medico
        AND REG_IRR.competencia   = A.competencia
        AND REG_IRR.tipo_anomalia = 'IRREGULAR'
    GROUP BY A.nu_cnpj, A.competencia
),
HHI AS (
    SELECT
        E.nu_cnpj AS cnpj, E.competencia,
        SUM(POWER(
            CAST(E.vl_autorizacoes_medico AS DECIMAL(18,4)) /
            NULLIF(CAST(T.total_valor   AS DECIMAL(18,4)), 0) * 100.0
        , 2)) AS indice_hhi
    FROM temp_CGUSC.fp.dados_crm_detalhado E
    INNER JOIN Totais T ON T.cnpj = E.nu_cnpj AND T.competencia = E.competencia
    GROUP BY E.nu_cnpj, E.competencia
),
Turistas AS (
    SELECT nu_cnpj AS cnpj, competencia,
           COUNT(DISTINCT id_medico) AS qtd_turistas
    FROM temp_CGUSC.fp.alertas_crm
    WHERE flag_geografico = 1
    GROUP BY nu_cnpj, competencia
)

SELECT
    I.cnpj,
    I.competencia,
    I.total_prescricoes         AS qtd_prescricoes_mes,
    I.total_valor               AS vl_total_prescricoes,
    I.total_prescritores        AS qtd_prescritores,
    T.id_top1,
    ISNULL(T.vl_top1, 0) AS vl_top1,
    ISNULL(T.vl_top5, 0) AS vl_top5,
    ISNULL(H.indice_hhi, 0) AS indice_hhi,
    ISNULL(AN.qtd_crm_invalido, 0) AS qtd_crm_invalido,
    ISNULL(AN.qtd_antes_registro, 0) AS qtd_crm_antes_registro,
    ISNULL(TU.qtd_turistas, 0)  AS qtd_prescritores_turistas
INTO #indicador_crm
FROM Totais I
LEFT JOIN Top5 T     ON T.cnpj = I.cnpj AND T.competencia = I.competencia
LEFT JOIN HHI H      ON H.cnpj = I.cnpj AND H.competencia = I.competencia
LEFT JOIN Anomalias AN ON AN.cnpj = I.cnpj AND AN.competencia = I.competencia
LEFT JOIN Turistas TU ON TU.cnpj = I.cnpj AND TU.competencia = I.competencia;

PRINT '   #indicador_crm concluída em: ' + CONVERT(VARCHAR(20), GETDATE() - @t_ind, 114);



CREATE CLUSTERED INDEX IDX_IndCrm ON #indicador_crm(cnpj, competencia);
GO


-- ============================================================================
-- BENCHMARK POR UF / COMPETÊNCIA
-- ============================================================================


PRINT '>> Criando temp_CGUSC.fp.indicador_crm_bench_uf...';
DECLARE @t_bench_uf DATETIME = GETDATE();
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crm_bench_uf;

;WITH CTE AS (
    SELECT 
        I.competencia,
        F.uf,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.indice_hhi, 0))                OVER (PARTITION BY F.uf, I.competencia) AS mediana_hhi_uf,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.vl_top1/NULLIF(I.vl_total_prescricoes,0)*100,0))    OVER (PARTITION BY F.uf, I.competencia) AS mediana_concentracao_top1_uf,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.vl_top5/NULLIF(I.vl_total_prescricoes,0)*100,0))    OVER (PARTITION BY F.uf, I.competencia) AS mediana_concentracao_top5_uf,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(CAST(
            CASE WHEN I.qtd_prescritores > 0
                 THEN I.qtd_crm_invalido * 100.0 / I.qtd_prescritores
                 ELSE 0 END AS DECIMAL(18,4)), 0))                               OVER (PARTITION BY F.uf, I.competencia) AS mediana_pct_crm_invalido_uf,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.qtd_prescritores_turistas, 0)) OVER (PARTITION BY F.uf, I.competencia) AS mediana_turistas_uf
    FROM #indicador_crm I
    INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj
)
SELECT * INTO temp_CGUSC.fp.indicador_crm_bench_uf FROM CTE;

PRINT '   temp_CGUSC.fp.indicador_crm_bench_uf concluída em: ' + CONVERT(VARCHAR(20), GETDATE() - @t_bench_uf, 114);



CREATE CLUSTERED INDEX IDX_BenchUF ON temp_CGUSC.fp.indicador_crm_bench_uf(uf, competencia);


-- ============================================================================
-- BENCHMARK POR REGIÃO DE SAÚDE / COMPETÊNCIA
-- ============================================================================


PRINT '>> Criando temp_CGUSC.fp.indicador_crm_bench_regiao...';
DECLARE @t_bench_reg DATETIME = GETDATE();
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crm_bench_regiao;

;WITH CTE AS (
    SELECT DISTINCT
        F.id_regiao_saude,
        I.competencia,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.indice_hhi, 0))                OVER (PARTITION BY F.id_regiao_saude, I.competencia) AS mediana_hhi_reg,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.vl_top1/NULLIF(I.vl_total_prescricoes,0)*100, 0))     OVER (PARTITION BY F.id_regiao_saude, I.competencia) AS mediana_concentracao_reg,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.vl_top5/NULLIF(I.vl_total_prescricoes,0)*100, 0))     OVER (PARTITION BY F.id_regiao_saude, I.competencia) AS mediana_concentracao_top5_reg,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(CAST(
            CASE WHEN I.qtd_prescritores > 0
                 THEN I.qtd_crm_invalido * 100.0 / I.qtd_prescritores
                 ELSE 0 END AS DECIMAL(18,4)), 0))                                           OVER (PARTITION BY F.id_regiao_saude, I.competencia) AS mediana_crm_invalido_reg,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.qtd_prescritores_turistas, 0)) OVER (PARTITION BY F.id_regiao_saude, I.competencia) AS mediana_turistas_reg
    FROM temp_CGUSC.fp.dados_farmacia F
    LEFT JOIN #indicador_crm I ON I.cnpj = F.cnpj
    WHERE F.id_regiao_saude IS NOT NULL
)
SELECT * INTO temp_CGUSC.fp.indicador_crm_bench_regiao FROM CTE;

PRINT '   temp_CGUSC.fp.indicador_crm_bench_regiao concluída em: ' + CONVERT(VARCHAR(20), GETDATE() - @t_bench_reg, 114);



CREATE CLUSTERED INDEX IDX_BenchReg ON temp_CGUSC.fp.indicador_crm_bench_regiao(id_regiao_saude, competencia);


-- ============================================================================
-- BENCHMARK NACIONAL / COMPETÊNCIA
-- ============================================================================


PRINT '>> Criando temp_CGUSC.fp.indicador_crm_bench_br...';
DECLARE @t_bench_br DATETIME = GETDATE();
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crm_bench_br;

;WITH CTE AS (
    SELECT DISTINCT
        I.competencia,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.vl_top1/NULLIF(I.vl_total_prescricoes,0)*100, 0))     OVER (PARTITION BY I.competencia) AS mediana_concentracao_br,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.vl_top5/NULLIF(I.vl_total_prescricoes,0)*100, 0))     OVER (PARTITION BY I.competencia) AS mediana_concentracao_top5_br,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.indice_hhi, 0))                OVER (PARTITION BY I.competencia) AS mediana_hhi_br,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(CAST(
            CASE WHEN I.qtd_prescritores > 0
                 THEN I.qtd_crm_invalido * 100.0 / I.qtd_prescritores
                 ELSE 0 END AS DECIMAL(18,4)), 0))                                           OVER (PARTITION BY I.competencia) AS mediana_pct_crm_invalido_br,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.qtd_prescritores_turistas, 0)) OVER (PARTITION BY I.competencia) AS mediana_turistas_br
    FROM #indicador_crm I
)
SELECT * INTO temp_CGUSC.fp.indicador_crm_bench_br FROM CTE;

PRINT '   temp_CGUSC.fp.indicador_crm_bench_br concluída em: ' + CONVERT(VARCHAR(20), GETDATE() - @t_bench_br, 114);



CREATE CLUSTERED INDEX IDX_BenchBR ON temp_CGUSC.fp.indicador_crm_bench_br(competencia);
GO


-- ============================================================================
-- TABELA PARA MATRIZ DE RISCO: indicador_crm_hhi
PRINT '>> Criando temp_CGUSC.fp.indicador_crm_hhi (Matriz de Risco)...';
DECLARE @t_hhi DATETIME = GETDATE();
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_crm_hhi;



;WITH HHI_por_cnpj AS (
    SELECT
        I.cnpj,
        AVG(I.indice_hhi)           AS indice_hhi,
        F.id_regiao_saude,
        CAST(F.uf AS VARCHAR(2))    AS uf
    FROM #indicador_crm I
    INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj
    GROUP BY I.cnpj, F.id_regiao_saude, F.uf
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

PRINT '   temp_CGUSC.fp.indicador_crm_hhi concluída em: ' + CONVERT(VARCHAR(20), GETDATE() - @t_hhi, 114);



CREATE CLUSTERED INDEX IDX_CrmHHI ON temp_CGUSC.fp.indicador_crm_hhi(cnpj);
GO


-- ============================================================================



GO
