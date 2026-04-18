USE [temp_CGUSC]
GO

-- ==========================================================================================
-- SCRIPT: Matriz de Risco Final - PFPB / CGU
-- OBJETIVO: Consolidação, Score de Risco e Detecção em Duas Camadas (Atenção e Crítico)
-- Sistema Multinível: Alerta de Atenção (+3 pts) e Alerta Crítico (+10 pts)
-- Motor: Modified Z-Score (MAD) calibrado por região/UF com benchmark hierárquico
-- ==========================================================================================

SET NOCOUNT ON;
PRINT '>> INICIANDO GERAÇÃO DA MATRIZ DE RISCO FINAL...';

-- ============================================================================
-- MATRIZ DE PESOS (0.1 a 5.0) - AJUSTE A IMPORTÂNCIA DE CADA INDICADOR AQUI
-- ============================================================================
DECLARE @PESO_FALECIDOS                      FLOAT = 2.5; 
DECLARE @PESO_PERCENTUAL_SEM_COMPROVACAO      FLOAT = 5.0; -- Peso Máximo
DECLARE @PESO_RECORRENCIA_SISTEMICA             FLOAT = 2.0; 
DECLARE @PESO_COMPRA_UNICA                   FLOAT = 1.0; 
DECLARE @PESO_CRMS_IRREGULARES               FLOAT = 1.0; 
DECLARE @PESO_INCONSISTENCIA_CLINICA         FLOAT = 1.5; 
DECLARE @PESO_POLIMEDICAMENTO                FLOAT = 1.5; 
DECLARE @PESO_ESTOURO_TETO                   FLOAT = 1.0; 
DECLARE @PESO_ALTO_CUSTO                     FLOAT = 1.5; 
DECLARE @PESO_VOLUME_ATIPICO                 FLOAT = 2.5; 
DECLARE @PESO_DISTANCIA_GEOGRAFICA           FLOAT = 1.0; 
DECLARE @PESO_RECEITA_POR_PACIENTE           FLOAT = 1.0; 
DECLARE @PESO_VALOR_PER_CAPITA               FLOAT = 1.0; 
DECLARE @PESO_EXCLUSIVIDADE_CRM              FLOAT = 0.5; 
DECLARE @PESO_CONCENTRACAO_CRM_HHI           FLOAT = 0.5; 
DECLARE @PESO_CONCENTRACAO_PICO              FLOAT = 1.0; 
DECLARE @PESO_VENDAS_CONSECUTIVAS_RAPIDAS    FLOAT = 2.0; 
DECLARE @PESO_TICKET_MEDIO                   FLOAT = 1.0;

-- ----------------------------------------------------------------------------
-- MATRIZ DE CALIBRAÇÃO MULTINÍVEL (BASEADA NA TABELA HISTÓRICA)
-- ----------------------------------------------------------------------------
-- ATENCAO (+3 pts) | CRITICO (+10 pts)
-- ----------------------------------------------------------------------------
DECLARE @MAD_ATEN_FALECIDOS              FLOAT = 2; DECLARE @MAD_CRIT_FALECIDOS              FLOAT = 3;
DECLARE @MAD_ATEN_AUDITORIA              FLOAT = 3.5; DECLARE @MAD_CRIT_AUDITORIA              FLOAT = 5;
DECLARE @MAD_ATEN_CRMS_IRREGULARES       FLOAT = 2.50; DECLARE @MAD_CRIT_CRMS_IRREGULARES       FLOAT = 3.50;
DECLARE @MAD_ATEN_CLINICO                FLOAT = 2.00; DECLARE @MAD_CRIT_CLINICO                FLOAT = 2.8;
DECLARE @MAD_ATEN_VENDAS_RAPIDAS         FLOAT = 3; DECLARE @MAD_CRIT_VENDAS_RAPIDAS         FLOAT = 4;
DECLARE @MAD_ATEN_VOLUME_ATIPICO         FLOAT = 1.8; DECLARE @MAD_CRIT_VOLUME_ATIPICO         FLOAT = 2;
DECLARE @MAD_ATEN_ALTO_CUSTO             FLOAT = 1.40; DECLARE @MAD_CRIT_ALTO_CUSTO             FLOAT = 1.7;
DECLARE @MAD_ATEN_TETO                   FLOAT = 1.17; DECLARE @MAD_CRIT_TETO                   FLOAT = 1.25;
DECLARE @MAD_ATEN_POLIMEDICAMENTO        FLOAT = 2; DECLARE @MAD_CRIT_POLIMEDICAMENTO        FLOAT = 2.4;
DECLARE @MAD_ATEN_TICKET_MEDIO           FLOAT = 1.6; DECLARE @MAD_CRIT_TICKET_MEDIO           FLOAT = 2;
DECLARE @MAD_ATEN_RECEITA_PACIENTE       FLOAT = 2.5; DECLARE @MAD_CRIT_RECEITA_PACIENTE       FLOAT = 3.5;
DECLARE @MAD_ATEN_PER_CAPITA             FLOAT = 2.5; DECLARE @MAD_CRIT_PER_CAPITA             FLOAT = 3.5;
DECLARE @MAD_ATEN_DISTANCIA_GEOGRAFICA   FLOAT = 1.85; DECLARE @MAD_CRIT_DISTANCIA_GEOGRAFICA   FLOAT = 2.49;
DECLARE @MAD_ATEN_CONCENTRACAO_PICO      FLOAT = 2.5; DECLARE @MAD_CRIT_CONCENTRACAO_PICO      FLOAT = 3;
DECLARE @MAD_ATEN_COMPRA_UNICA           FLOAT = 1.40; DECLARE @MAD_CRIT_COMPRA_UNICA           FLOAT = 1.70;
DECLARE @MAD_ATEN_CRM_HHI                FLOAT = 2.5; DECLARE @MAD_CRIT_CRM_HHI                FLOAT = 3.5;
DECLARE @MAD_ATEN_EXCLUSIVIDADE_CRM      FLOAT = 2.00; DECLARE @MAD_CRIT_EXCLUSIVIDADE_CRM      FLOAT = 2.5;
DECLARE @MAD_ATEN_RECORRENCIA_SISTEMICA  FLOAT = 1.50; DECLARE @MAD_CRIT_RECORRENCIA_SISTEMICA  FLOAT = 1.9;

BEGIN TRY
    BEGIN TRANSACTION;

    -- 1. LIMPEZA DE AMBIENTE
    IF OBJECT_ID('temp_CGUSC.fp.matriz_risco_consolidada', 'U') IS NOT NULL
    BEGIN
        DROP TABLE temp_CGUSC.fp.matriz_risco_consolidada;
        PRINT '   > Tabela anterior removida.';
    END;

-- CTE 0: POPULAÇÃO TOTAL POR REGIÃO (EVITANDO DUPLICIDADE DE CIDADES)
;WITH PopRegiao AS (
    SELECT id_regiao_saude, SUM(pop_mun) as populacao_total_regiao
    FROM (
        SELECT DISTINCT municipio, uf, id_regiao_saude, ISNULL(populacao2019, 0) as pop_mun
        FROM temp_CGUSC.fp.dados_farmacia
    ) T
    GROUP BY id_regiao_saude
),

-- ====================================================================================
-- CTE DE SUPORTE - CONTAGEM DE FARMÁCIAS POR REGIÃO (BASE DA NORMALIZAÇÃO HIERÁRQUICA)
-- Decide o nível de normalização: >= 20 farmácias => usa Região; < 20 => usa UF
-- Limiar de 20 garante que o PERCENT_RANK() tenha granularidade mínima de ~5%
-- ====================================================================================
ContadorRegiao AS (
    SELECT
        id_regiao_saude,
        COUNT(*)                                               AS qtd_farmacias_regiao,
        CASE WHEN COUNT(*) >= 40 THEN 'REGIAO' ELSE 'UF' END AS escopo_benchmark
    FROM temp_CGUSC.fp.dados_farmacia
    WHERE id_regiao_saude IS NOT NULL
    GROUP BY id_regiao_saude
),

-- 2. CTE 1: CONSOLIDAÇÃO DOS DADOS BRUTOS (VALORES REAIS PARA EXIBIÇÃO)
IndicadoresPresenca AS (
    SELECT 
        F.cnpj,
        F.razaoSocial,
        F.nomeFantasia,
        CAST(F.municipio AS VARCHAR(255)) AS municipio,
        CAST(F.uf AS VARCHAR(2)) AS uf,
        F.no_regiao_saude,
        F.id_regiao_saude,
        F.situacaoCadastral,
        
        -- POPULAÇÃO
        ISNULL(F.populacao2019, 0) AS populacao,
        PR.populacao_total_regiao,

        -- FLAGS DE PRESENÇA
        CASE WHEN I01.cnpj IS NOT NULL THEN 1 ELSE 0 END AS tem_falecidos,
        CASE WHEN I02.cnpj IS NOT NULL THEN 1 ELSE 0 END AS tem_clinico,
        CASE WHEN I03.cnpj IS NOT NULL THEN 1 ELSE 0 END AS tem_teto,
        CASE WHEN I04.cnpj IS NOT NULL THEN 1 ELSE 0 END AS tem_polimedicamento,
        CASE WHEN I06.cnpj IS NOT NULL THEN 1 ELSE 0 END AS tem_ticket,
        CASE WHEN I07.cnpj IS NOT NULL THEN 1 ELSE 0 END AS tem_receita_paciente,
        CASE WHEN I08.cnpj IS NOT NULL THEN 1 ELSE 0 END AS tem_per_capita,
        CASE WHEN I09.cnpj IS NOT NULL THEN 1 ELSE 0 END AS tem_vendas_rapidas,
        CASE WHEN I10.cnpj IS NOT NULL THEN 1 ELSE 0 END AS tem_volume_atipico,
        CASE WHEN I11.cnpj IS NOT NULL THEN 1 ELSE 0 END AS tem_geografico,
        CASE WHEN I12.cnpj IS NOT NULL THEN 1 ELSE 0 END AS tem_alto_custo,
        CASE WHEN I13.cnpj IS NOT NULL THEN 1 ELSE 0 END AS tem_pico,
        CASE WHEN I14.cnpj IS NOT NULL THEN 1 ELSE 0 END AS tem_compra_unica,
        CASE WHEN I15.nu_cnpj IS NOT NULL THEN 1 ELSE 0 END AS tem_crm,
        CASE WHEN I16.cnpj IS NOT NULL THEN 1 ELSE 0 END AS tem_exclusividade_crm,
        CASE WHEN I17.cnpj IS NOT NULL THEN 1 ELSE 0 END AS tem_crms_irregulares,
        CASE WHEN I19.cnpj IS NOT NULL THEN 1 ELSE 0 END AS tem_recorrencia_sistemica,
        CASE WHEN IA.cnpj IS NOT NULL THEN 1 ELSE 0 END AS tem_auditado,
        
        -- ====================================================================================
        -- DADOS ORIGINAIS REAIS (SEM TETO AQUI - PARA EXIBIÇÃO NO RELATÓRIO)
        -- ====================================================================================
        
        I01.percentual_falecidos AS pct_falecidos,
        I01.municipio_mediana AS med_falecidos_mun, I01.estado_mediana AS med_falecidos_uf, I01.pais_mediana AS med_falecidos_br, I01.regiao_saude_mediana AS med_falecidos_reg,
        I01.risco_relativo_mun_mediana AS risco_falecidos_mun, I01.risco_relativo_uf_mediana AS risco_falecidos_uf, I01.risco_relativo_br_mediana AS risco_falecidos_br, I01.risco_relativo_reg_mediana AS risco_falecidos_reg,

        I02.percentual_inconsistencia AS pct_clinico,
        I02.municipio_mediana AS med_clinico_mun, I02.estado_mediana AS med_clinico_uf, I02.pais_mediana AS med_clinico_br, I02.regiao_saude_mediana AS med_clinico_reg,
        I02.risco_relativo_mun_mediana AS risco_clinico_mun, I02.risco_relativo_uf_mediana AS risco_clinico_uf, I02.risco_relativo_br_mediana AS risco_clinico_br, I02.risco_relativo_reg_mediana AS risco_clinico_reg,

        I03.percentual_teto AS pct_teto,
        I03.municipio_mediana AS med_teto_mun, I03.estado_mediana AS med_teto_uf, I03.pais_mediana AS med_teto_br, I03.regiao_saude_mediana AS med_teto_reg,
        I03.risco_relativo_mun_mediana AS risco_teto_mun, I03.risco_relativo_uf_mediana AS risco_teto_uf, I03.risco_relativo_br_mediana AS risco_teto_br, I03.risco_relativo_reg_mediana AS risco_teto_reg,

        I04.percentual_polimedicamento AS pct_polimedicamento,
        I04.municipio_mediana AS med_polimedicamento_mun, I04.estado_mediana AS med_polimedicamento_uf, I04.pais_mediana AS med_polimedicamento_br, I04.regiao_saude_mediana AS med_polimedicamento_reg,
        I04.risco_relativo_mun_mediana AS risco_polimedicamento_mun, I04.risco_relativo_uf_mediana AS risco_polimedicamento_uf, I04.risco_relativo_br_mediana AS risco_polimedicamento_br, I04.risco_relativo_reg_mediana AS risco_polimedicamento_reg,

        I06.valor_ticket_medio AS val_ticket_medio,
        I06.municipio_mediana AS med_ticket_mun, I06.estado_mediana AS med_ticket_uf, I06.pais_mediana AS med_ticket_br, I06.regiao_saude_mediana AS med_ticket_reg,
        I06.risco_relativo_mun_mediana AS risco_ticket_mun, I06.risco_relativo_uf_mediana AS risco_ticket_uf, I06.risco_relativo_br_mediana AS risco_ticket_br, I06.risco_relativo_reg_mediana AS risco_ticket_reg,

        I07.receita_por_paciente_mensal AS val_receita_paciente,
        I07.municipio_mediana AS med_receita_paciente_mun, I07.estado_mediana AS med_receita_paciente_uf, I07.pais_mediana AS med_receita_paciente_br, I07.regiao_saude_mediana AS med_receita_paciente_reg,
        I07.risco_relativo_mun_mediana AS risco_receita_paciente_mun, I07.risco_relativo_uf_mediana AS risco_receita_paciente_uf, I07.risco_relativo_br_mediana AS risco_receita_paciente_br, I07.risco_relativo_reg_mediana AS risco_receita_paciente_reg,

        I08.valor_per_capita_mensal AS val_per_capita,
        I08.municipio_mediana AS med_per_capita_mun, I08.estado_mediana AS med_per_capita_uf, I08.pais_mediana AS med_per_capita_br, I08.regiao_saude_mediana AS med_per_capita_reg,
        I08.risco_relativo_mun_mediana AS risco_per_capita_mun, I08.risco_relativo_uf_mediana AS risco_per_capita_uf, I08.risco_relativo_br_mediana AS risco_per_capita_br, I08.risco_relativo_reg_mediana AS risco_per_capita_reg,

        I09.percentual_vendas_consecutivas AS pct_vendas_rapidas,
        I09.municipio_mediana AS med_vendas_rapidas_mun, I09.estado_mediana AS med_vendas_rapidas_uf, I09.pais_mediana AS med_vendas_rapidas_br, I09.regiao_saude_mediana AS med_vendas_rapidas_reg,
        I09.risco_relativo_mun_mediana AS risco_vendas_rapidas_mun, I09.risco_relativo_uf_mediana AS risco_vendas_rapidas_uf, I09.risco_relativo_br_mediana AS risco_vendas_rapidas_br, I09.risco_relativo_reg_mediana AS risco_vendas_rapidas_reg,

        I10.risco_final AS val_volume_atipico,
        I10.municipio_mediana AS med_volume_atipico_mun, I10.estado_mediana AS med_volume_atipico_uf, I10.pais_mediana AS med_volume_atipico_br, I10.regiao_saude_mediana AS med_volume_atipico_reg,
        I10.risco_relativo_mun_mediana AS risco_volume_atipico_mun, I10.risco_relativo_uf_mediana AS risco_volume_atipico_uf, I10.risco_relativo_br_mediana AS risco_volume_atipico_br, I10.risco_relativo_reg_mediana AS risco_volume_atipico_reg,

        I11.percentual_geografico AS pct_geografico,
        I11.municipio_mediana AS med_geografico_mun, I11.estado_mediana AS med_geografico_uf, I11.pais_mediana AS med_geografico_br, I11.regiao_saude_mediana AS med_geografico_reg,
        I11.risco_relativo_mun_mediana AS risco_geografico_mun, I11.risco_relativo_uf_mediana AS risco_geografico_uf, I11.risco_relativo_br_mediana AS risco_geografico_br, I11.risco_relativo_reg_mediana AS risco_geografico_reg,

        I12.percentual_alto_custo AS pct_alto_custo,
        I12.municipio_mediana AS med_alto_custo_mun, I12.estado_mediana AS med_alto_custo_uf, I12.pais_mediana AS med_alto_custo_br, I12.regiao_saude_mediana AS med_alto_custo_reg,
        I12.risco_relativo_mun_mediana AS risco_alto_custo_mun, I12.risco_relativo_uf_mediana AS risco_alto_custo_uf, I12.risco_relativo_br_mediana AS risco_alto_custo_br, I12.risco_relativo_reg_mediana AS risco_alto_custo_reg,

        I13.media_concentracao AS pct_pico,
        I13.municipio_mediana AS med_pico_mun, I13.estado_mediana AS med_pico_uf, I13.pais_mediana AS med_pico_br, I13.regiao_saude_mediana AS med_pico_reg,
        I13.risco_relativo_mun_mediana AS risco_pico_mun, I13.risco_relativo_uf_mediana AS risco_pico_uf, I13.risco_relativo_br_mediana AS risco_pico_br, I13.risco_relativo_reg_mediana AS risco_pico_reg,

        I14.pct_compra_unica AS pct_compra_unica,
        I14.municipio_mediana AS med_compra_unica_mun, I14.estado_mediana AS med_compra_unica_uf, I14.pais_mediana AS med_compra_unica_br, I14.regiao_saude_mediana AS med_compra_unica_reg,
        I14.risco_relativo_mun_mediana AS risco_compra_unica_mun, I14.risco_relativo_uf_mediana AS risco_compra_unica_uf, I14.risco_relativo_br_mediana AS risco_compra_unica_br, I14.risco_relativo_reg_mediana AS risco_compra_unica_reg,

        CAST(I15.indice_hhi AS DECIMAL(18,2)) AS val_hhi_crm,
        -- avg_hhi_crm_mun (media_hhi_mun) removido — era a única média real do bloco I15.
        -- As três abaixo eram mal nomeadas como avg_ mas vêm de colunas _mediana na fonte.
        CAST(I15.estado_mediana AS DECIMAL(18,2)) AS med_hhi_crm_uf,
        CAST(I15.pais_mediana AS DECIMAL(18,2)) AS med_hhi_crm_br,
        CAST(I15.regiao_saude_mediana AS DECIMAL(18,2)) AS med_hhi_crm_reg,
        I15.risco_relativo_reg_mediana AS risco_crm_reg,
        I15.risco_relativo_uf_mediana AS risco_crm_uf,
        I15.risco_relativo_br_mediana AS risco_crm_br,
        -- indicador_crm_detalhado (HHI) não tem granularidade municipal na fonte CNES;
        -- apenas Região/UF/Brasil estão disponíveis (risco_crm_reg/uf/br acima).
        NULL AS risco_crm_mun,

        I16.percentual_exclusividade AS pct_exclusividade_crm,
        I16.municipio_mediana AS med_exclusividade_crm_mun, I16.estado_mediana AS med_exclusividade_crm_uf, I16.pais_mediana AS med_exclusividade_crm_br, I16.regiao_saude_mediana AS med_exclusividade_crm_reg,
        I16.risco_relativo_mun_mediana AS risco_exclusividade_crm_mun, I16.risco_relativo_uf_mediana AS risco_exclusividade_crm_uf, I16.risco_relativo_br_mediana AS risco_exclusividade_crm_br, I16.risco_relativo_reg_mediana AS risco_exclusividade_crm_reg,

        I17.pct_risco_irregularidade AS pct_crms_irregulares,
        I17.municipio_mediana AS med_crms_irregulares_mun, I17.estado_mediana AS med_crms_irregulares_uf, I17.pais_mediana AS med_crms_irregulares_br, I17.regiao_saude_mediana AS med_crms_irregulares_reg,
        I17.risco_relativo_mun_mediana AS risco_crms_irregulares_mun, I17.risco_relativo_uf_mediana AS risco_crms_irregulares_uf, I17.risco_relativo_br_mediana AS risco_crms_irregulares_br, I17.risco_relativo_reg_mediana AS risco_crms_irregulares_reg,

        I19.percentual_recorrencia_sistemica AS pct_recorrencia_sistemica,
        I19.municipio_mediana AS med_recorrencia_sistemica_mun, I19.estado_mediana AS med_recorrencia_sistemica_uf, I19.pais_mediana AS med_recorrencia_sistemica_br, I19.regiao_saude_mediana AS med_recorrencia_sistemica_reg,
        I19.risco_relativo_mun_mediana AS risco_recorrencia_sistemica_mun, I19.risco_relativo_uf_mediana AS risco_recorrencia_sistemica_uf, I19.risco_relativo_br_mediana AS risco_recorrencia_sistemica_br, I19.risco_relativo_reg_mediana AS risco_recorrencia_sistemica_reg,

        -- NOVO: AUDITORIA (PCT NÃO COMPROVAÇÃO)
        IA.pct_auditado,
        IA.municipio_mediana AS med_auditado_mun, IA.estado_mediana AS med_auditado_uf, IA.pais_mediana AS med_auditado_br, IA.regiao_saude_mediana AS med_auditado_reg,
        IA.risco_relativo_mun_mediana AS risco_auditado_mun, IA.risco_relativo_uf_mediana AS risco_auditado_uf, IA.risco_relativo_br_mediana AS risco_auditado_br, IA.risco_relativo_reg_mediana AS risco_auditado_reg
        
    FROM temp_CGUSC.fp.dados_farmacia F
    LEFT JOIN PopRegiao PR ON PR.id_regiao_saude = F.id_regiao_saude
    LEFT JOIN temp_CGUSC.fp.indicador_falecidos_detalhado I01 ON I01.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicador_inconsistencia_clinica_detalhado I02 ON I02.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicador_teto_detalhado I03 ON I03.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicador_polimedicamento_detalhado I04 ON I04.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicador_ticket_medio_detalhado I06 ON I06.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicador_receita_por_paciente_detalhado I07 ON I07.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicador_venda_per_capita_detalhado I08 ON I08.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicador_vendas_consecutivas_detalhado I09 ON I09.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicador_volume_atipico_detalhado I10 ON I10.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicador_geografico_detalhado I11 ON I11.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicador_alto_custo_detalhado I12 ON I12.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicador_concentracao_pico_detalhado I13 ON I13.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicador_compra_unica_detalhado I14 ON I14.cnpj = F.cnpj
    -- I15: indicador_crm_hhi — HHI agregado por CNPJ, gerado por crms_1_detalhado_prescritor.sql.
    LEFT JOIN temp_CGUSC.fp.indicador_crm_hhi I15 ON I15.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicador_exclusividade_crm_detalhado I16 ON I16.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicador_crms_irregulares_detalhado I17 ON I17.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicador_recorrencia_sistemica_detalhado I19 ON I19.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicador_auditado_detalhado IA ON IA.cnpj = F.cnpj
),

-- 3. CTE 2: CÁLCULO DE FLAGS CRÍTICOS (BASEADO EM LIMITES ESTATÍSTICOS BRUTOS)
-- Mantemos os flags para fins de visualização no Dashboard e penalidade do score.
CalculoFlagsRisco AS (
    SELECT 
        *,
        -- FLAGS CRÍTICOS: Identificam se o risco bruto atingiu o limiar de alerta (>= 5x a média)
        CASE WHEN tem_falecidos=1            AND ISNULL(risco_falecidos_reg,0)            >= 5 THEN 1 ELSE 0 END AS flag_falecidos_critico,
        CASE WHEN tem_clinico=1              AND ISNULL(risco_clinico_reg,0)              >= 5 THEN 1 ELSE 0 END AS flag_clinico_critico,
        CASE WHEN tem_teto=1                 AND ISNULL(risco_teto_reg,0)                 >= 5 THEN 1 ELSE 0 END AS flag_teto_critico,
        CASE WHEN tem_polimedicamento=1      AND ISNULL(risco_polimedicamento_reg,0)      >= 5 THEN 1 ELSE 0 END AS flag_polimedicamento_critico,
        CASE WHEN tem_ticket=1               AND ISNULL(risco_ticket_reg,0)               >= 5 THEN 1 ELSE 0 END AS flag_ticket_critico,
        CASE WHEN tem_receita_paciente=1     AND ISNULL(risco_receita_paciente_reg,0)     >= 5 THEN 1 ELSE 0 END AS flag_receita_paciente_critico,
        CASE WHEN tem_per_capita=1           AND ISNULL(risco_per_capita_reg,0)           >= 5 THEN 1 ELSE 0 END AS flag_per_capita_critico,
        CASE WHEN tem_vendas_rapidas=1       AND ISNULL(risco_vendas_rapidas_reg,0)       >= 5 THEN 1 ELSE 0 END AS flag_vendas_rapidas_critico,
        CASE WHEN tem_volume_atipico=1       AND ISNULL(risco_volume_atipico_reg,0)       >= 5 THEN 1 ELSE 0 END AS flag_volume_atipico_critico,
        CASE WHEN tem_geografico=1           AND ISNULL(risco_geografico_reg,0)           >= 5 THEN 1 ELSE 0 END AS flag_geografico_critico,
        CASE WHEN tem_alto_custo=1           AND ISNULL(risco_alto_custo_reg,0)           >= 5 THEN 1 ELSE 0 END AS flag_alto_custo_critico,
        CASE WHEN tem_pico=1                 AND ISNULL(risco_pico_reg,0)                 >= 5 THEN 1 ELSE 0 END AS flag_pico_critico,
        CASE WHEN tem_compra_unica=1         AND ISNULL(risco_compra_unica_reg,0)         >= 5 THEN 1 ELSE 0 END AS flag_compra_unica_critico,
        CASE WHEN tem_crm=1                  AND ISNULL(risco_crm_reg,0)                  >= 5 THEN 1 ELSE 0 END AS flag_crm_critico,
        CASE WHEN tem_exclusividade_crm=1    AND ISNULL(risco_exclusividade_crm_reg,0)    >= 5 THEN 1 ELSE 0 END AS flag_exclusividade_crm_critico,
        CASE WHEN tem_crms_irregulares=1     AND ISNULL(risco_crms_irregulares_reg,0)     >= 5 THEN 1 ELSE 0 END AS flag_crms_irregulares_critico,
        CASE WHEN tem_recorrencia_sistemica=1 AND ISNULL(risco_recorrencia_sistemica_reg,0) >= 5 THEN 1 ELSE 0 END AS flag_recorrencia_sistemica_critico,
        CASE WHEN tem_auditado=1             AND ISNULL(risco_auditado_reg,0)             >= 5 THEN 1 ELSE 0 END AS flag_auditado_critico
    FROM IndicadoresPresenca
),

-- ====================================================================================
-- MOTOR MAD (MEDIAN ABSOLUTE DEVIATION)
-- Etapa 1: Calcular as Medianas Brutas por Região/UF
-- Etapa 2: Calcular o Desvio Absoluto em relação à Mediana
-- Etapa 3: Calcular o MAD (Mediana dos Desvios) e aplicar o Modified Z-Score
-- ====================================================================================
MedianasBasicas AS (
    SELECT 
        CP.cnpj, 
        CP.id_regiao_saude, 
        CP.uf,
        CR.escopo_benchmark,
        
        -- Mediana dos indicadores (usada como âncora central)
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(pct_falecidos,0))            OVER (PARTITION BY (CASE WHEN CR.escopo_benchmark='REGIAO' THEN CAST(CP.id_regiao_saude AS VARCHAR(20)) ELSE CP.uf END)) AS med_falecidos,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(pct_clinico,0))              OVER (PARTITION BY (CASE WHEN CR.escopo_benchmark='REGIAO' THEN CAST(CP.id_regiao_saude AS VARCHAR(20)) ELSE CP.uf END)) AS med_clinico,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(pct_teto,0))                 OVER (PARTITION BY (CASE WHEN CR.escopo_benchmark='REGIAO' THEN CAST(CP.id_regiao_saude AS VARCHAR(20)) ELSE CP.uf END)) AS med_teto,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(pct_polimedicamento,0))      OVER (PARTITION BY (CASE WHEN CR.escopo_benchmark='REGIAO' THEN CAST(CP.id_regiao_saude AS VARCHAR(20)) ELSE CP.uf END)) AS med_polimedicamento,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(val_ticket_medio,0))         OVER (PARTITION BY (CASE WHEN CR.escopo_benchmark='REGIAO' THEN CAST(CP.id_regiao_saude AS VARCHAR(20)) ELSE CP.uf END)) AS med_ticket,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(val_receita_paciente,0))    OVER (PARTITION BY (CASE WHEN CR.escopo_benchmark='REGIAO' THEN CAST(CP.id_regiao_saude AS VARCHAR(20)) ELSE CP.uf END)) AS med_receita,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(val_per_capita,0))          OVER (PARTITION BY (CASE WHEN CR.escopo_benchmark='REGIAO' THEN CAST(CP.id_regiao_saude AS VARCHAR(20)) ELSE CP.uf END)) AS med_per_capita,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(pct_vendas_rapidas,0))      OVER (PARTITION BY (CASE WHEN CR.escopo_benchmark='REGIAO' THEN CAST(CP.id_regiao_saude AS VARCHAR(20)) ELSE CP.uf END)) AS med_vendas_rapidas,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(val_volume_atipico,0))      OVER (PARTITION BY (CASE WHEN CR.escopo_benchmark='REGIAO' THEN CAST(CP.id_regiao_saude AS VARCHAR(20)) ELSE CP.uf END)) AS med_volume_atipico,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(pct_geografico,0))          OVER (PARTITION BY (CASE WHEN CR.escopo_benchmark='REGIAO' THEN CAST(CP.id_regiao_saude AS VARCHAR(20)) ELSE CP.uf END)) AS med_geografico,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(pct_alto_custo,0))          OVER (PARTITION BY (CASE WHEN CR.escopo_benchmark='REGIAO' THEN CAST(CP.id_regiao_saude AS VARCHAR(20)) ELSE CP.uf END)) AS med_alto_custo,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(pct_pico,0))                OVER (PARTITION BY (CASE WHEN CR.escopo_benchmark='REGIAO' THEN CAST(CP.id_regiao_saude AS VARCHAR(20)) ELSE CP.uf END)) AS med_pico,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(pct_compra_unica,0))        OVER (PARTITION BY (CASE WHEN CR.escopo_benchmark='REGIAO' THEN CAST(CP.id_regiao_saude AS VARCHAR(20)) ELSE CP.uf END)) AS med_compra_unica,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(val_hhi_crm,0))             OVER (PARTITION BY (CASE WHEN CR.escopo_benchmark='REGIAO' THEN CAST(CP.id_regiao_saude AS VARCHAR(20)) ELSE CP.uf END)) AS med_crm_hhi,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(pct_exclusividade_crm,0))   OVER (PARTITION BY (CASE WHEN CR.escopo_benchmark='REGIAO' THEN CAST(CP.id_regiao_saude AS VARCHAR(20)) ELSE CP.uf END)) AS med_exclusividade,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(pct_crms_irregulares,0))    OVER (PARTITION BY (CASE WHEN CR.escopo_benchmark='REGIAO' THEN CAST(CP.id_regiao_saude AS VARCHAR(20)) ELSE CP.uf END)) AS med_crms_irregulares,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(pct_recorrencia_sistemica,0)) OVER (PARTITION BY (CASE WHEN CR.escopo_benchmark='REGIAO' THEN CAST(CP.id_regiao_saude AS VARCHAR(20)) ELSE CP.uf END)) AS med_recorrencia,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(pct_auditado,0))            OVER (PARTITION BY (CASE WHEN CR.escopo_benchmark='REGIAO' THEN CAST(CP.id_regiao_saude AS VARCHAR(20)) ELSE CP.uf END)) AS med_auditado
    FROM IndicadoresPresenca CP
    LEFT JOIN ContadorRegiao CR ON CR.id_regiao_saude = CP.id_regiao_saude
),

DesviosIndividuais AS (
    SELECT 
        MB.cnpj,
        MB.id_regiao_saude,
        MB.uf,
        MB.escopo_benchmark,
        MB.med_falecidos, MB.med_clinico, MB.med_teto, MB.med_polimedicamento, MB.med_ticket, MB.med_receita, MB.med_per_capita, MB.med_vendas_rapidas, MB.med_volume_atipico, MB.med_geografico, MB.med_alto_custo, MB.med_pico, MB.med_compra_unica, MB.med_crm_hhi, MB.med_exclusividade, MB.med_crms_irregulares, MB.med_recorrencia, MB.med_auditado,
        ABS(ISNULL(IP.pct_falecidos,0) - MB.med_falecidos) AS dev_falecidos,
        ABS(ISNULL(IP.pct_clinico,0) - MB.med_clinico) AS dev_clinico,
        ABS(ISNULL(IP.pct_teto,0) - MB.med_teto) AS dev_teto,
        ABS(ISNULL(IP.pct_polimedicamento,0) - MB.med_polimedicamento) AS dev_polimedicamento,
        ABS(ISNULL(IP.val_ticket_medio,0) - MB.med_ticket) AS dev_ticket,
        ABS(ISNULL(IP.val_receita_paciente,0) - MB.med_receita) AS dev_receita,
        ABS(ISNULL(IP.val_per_capita,0) - MB.med_per_capita) AS dev_per_capita,
        ABS(ISNULL(IP.pct_vendas_rapidas,0) - MB.med_vendas_rapidas) AS dev_vendas_rapidas,
        ABS(ISNULL(IP.val_volume_atipico,0) - MB.med_volume_atipico) AS dev_volume_atipico,
        ABS(ISNULL(IP.pct_geografico,0) - MB.med_geografico) AS dev_geografico,
        ABS(ISNULL(IP.pct_alto_custo,0) - MB.med_alto_custo) AS dev_alto_custo,
        ABS(ISNULL(IP.pct_pico,0) - MB.med_pico) AS dev_pico,
        ABS(ISNULL(IP.pct_compra_unica,0) - MB.med_compra_unica) AS dev_compra_unica,
        ABS(ISNULL(IP.val_hhi_crm,0) - MB.med_crm_hhi) AS dev_crm_hhi,
        ABS(ISNULL(IP.pct_exclusividade_crm,0) - MB.med_exclusividade) AS dev_exclusividade,
        ABS(ISNULL(IP.pct_crms_irregulares,0) - MB.med_crms_irregulares) AS dev_crms_irregulares,
        ABS(ISNULL(IP.pct_recorrencia_sistemica,0) - MB.med_recorrencia) AS dev_recorrencia,
        ABS(ISNULL(IP.pct_auditado,0) - MB.med_auditado) AS dev_auditado
    FROM MedianasBasicas MB
    INNER JOIN IndicadoresPresenca IP ON IP.cnpj = MB.cnpj
),

PassoCalculoMAD AS (
    SELECT 
        *,
        -- MAD: Mediana dos Desvios Absolutos
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY dev_falecidos)     OVER (PARTITION BY (CASE WHEN escopo_benchmark='REGIAO' THEN CAST(id_regiao_saude AS VARCHAR(20)) ELSE uf END)) AS mad_falecidos,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY dev_clinico)       OVER (PARTITION BY (CASE WHEN escopo_benchmark='REGIAO' THEN CAST(id_regiao_saude AS VARCHAR(20)) ELSE uf END)) AS mad_clinico,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY dev_teto)          OVER (PARTITION BY (CASE WHEN escopo_benchmark='REGIAO' THEN CAST(id_regiao_saude AS VARCHAR(20)) ELSE uf END)) AS mad_teto,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY dev_polimedicamento) OVER (PARTITION BY (CASE WHEN escopo_benchmark='REGIAO' THEN CAST(id_regiao_saude AS VARCHAR(20)) ELSE uf END)) AS mad_polimedicamento,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY dev_ticket)        OVER (PARTITION BY (CASE WHEN escopo_benchmark='REGIAO' THEN CAST(id_regiao_saude AS VARCHAR(20)) ELSE uf END)) AS mad_ticket,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY dev_receita)       OVER (PARTITION BY (CASE WHEN escopo_benchmark='REGIAO' THEN CAST(id_regiao_saude AS VARCHAR(20)) ELSE uf END)) AS mad_receita,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY dev_per_capita)     OVER (PARTITION BY (CASE WHEN escopo_benchmark='REGIAO' THEN CAST(id_regiao_saude AS VARCHAR(20)) ELSE uf END)) AS mad_per_capita,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY dev_vendas_rapidas) OVER (PARTITION BY (CASE WHEN escopo_benchmark='REGIAO' THEN CAST(id_regiao_saude AS VARCHAR(20)) ELSE uf END)) AS mad_vendas_rapidas,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY dev_volume_atipico) OVER (PARTITION BY (CASE WHEN escopo_benchmark='REGIAO' THEN CAST(id_regiao_saude AS VARCHAR(20)) ELSE uf END)) AS mad_volume_atipico,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY dev_geografico)     OVER (PARTITION BY (CASE WHEN escopo_benchmark='REGIAO' THEN CAST(id_regiao_saude AS VARCHAR(20)) ELSE uf END)) AS mad_geografico,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY dev_alto_custo)     OVER (PARTITION BY (CASE WHEN escopo_benchmark='REGIAO' THEN CAST(id_regiao_saude AS VARCHAR(20)) ELSE uf END)) AS mad_alto_custo,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY dev_pico)           OVER (PARTITION BY (CASE WHEN escopo_benchmark='REGIAO' THEN CAST(id_regiao_saude AS VARCHAR(20)) ELSE uf END)) AS mad_pico,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY dev_compra_unica)   OVER (PARTITION BY (CASE WHEN escopo_benchmark='REGIAO' THEN CAST(id_regiao_saude AS VARCHAR(20)) ELSE uf END)) AS mad_compra_unica,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY dev_crm_hhi)        OVER (PARTITION BY (CASE WHEN escopo_benchmark='REGIAO' THEN CAST(id_regiao_saude AS VARCHAR(20)) ELSE uf END)) AS mad_crm_hhi,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY dev_exclusividade)  OVER (PARTITION BY (CASE WHEN escopo_benchmark='REGIAO' THEN CAST(id_regiao_saude AS VARCHAR(20)) ELSE uf END)) AS mad_exclusividade,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY dev_crms_irregulares) OVER (PARTITION BY (CASE WHEN escopo_benchmark='REGIAO' THEN CAST(id_regiao_saude AS VARCHAR(20)) ELSE uf END)) AS mad_crms_irregulares,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY dev_recorrencia) OVER (PARTITION BY (CASE WHEN escopo_benchmark='REGIAO' THEN CAST(id_regiao_saude AS VARCHAR(20)) ELSE uf END)) AS mad_recorrencia,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY dev_auditado)      OVER (PARTITION BY (CASE WHEN escopo_benchmark='REGIAO' THEN CAST(id_regiao_saude AS VARCHAR(20)) ELSE uf END)) AS mad_auditado
    FROM DesviosIndividuais
),

CalculoFlagsMAD AS (
    SELECT 
        IP.*,
        PM.escopo_benchmark,
        
        -- Modified Z-Score Base (Reutilizado no CASE)
        ISNULL((0.6745 * (ISNULL(IP.pct_falecidos,0) - PM.med_falecidos)) / NULLIF(PM.mad_falecidos,0),0) AS mz_falecidos,
        ISNULL((0.6745 * (ISNULL(IP.pct_clinico,0) - PM.med_clinico)) / NULLIF(PM.mad_clinico,0),0) AS mz_clinico,
        ISNULL((0.6745 * (ISNULL(IP.pct_teto,0) - PM.med_teto)) / NULLIF(PM.mad_teto,0),0) AS mz_teto,
        ISNULL((0.6745 * (ISNULL(IP.pct_polimedicamento,0) - PM.med_polimedicamento)) / NULLIF(PM.mad_polimedicamento,0),0) AS mz_polimedicamento,
        ISNULL((0.6745 * (ISNULL(IP.val_ticket_medio,0) - PM.med_ticket)) / NULLIF(PM.mad_ticket,0),0) AS mz_ticket,
        ISNULL((0.6745 * (ISNULL(IP.val_receita_paciente,0) - PM.med_receita)) / NULLIF(PM.mad_receita,0),0) AS mz_receita,
        ISNULL((0.6745 * (ISNULL(IP.val_per_capita,0) - PM.med_per_capita)) / NULLIF(PM.mad_per_capita,0),0) AS mz_per_capita,
        ISNULL((0.6745 * (ISNULL(IP.pct_vendas_rapidas,0) - PM.med_vendas_rapidas)) / NULLIF(PM.mad_vendas_rapidas,0),0) AS mz_vendas_rapidas,
        ISNULL((0.6745 * (ISNULL(IP.val_volume_atipico,0) - PM.med_volume_atipico)) / NULLIF(PM.mad_volume_atipico,0),0) AS mz_volume_atipico,
        ISNULL((0.6745 * (ISNULL(IP.pct_geografico,0) - PM.med_geografico)) / NULLIF(PM.mad_geografico,0),0) AS mz_geografico,
        ISNULL((0.6745 * (ISNULL(IP.pct_alto_custo,0) - PM.med_alto_custo)) / NULLIF(PM.mad_alto_custo,0),0) AS mz_alto_custo,
        ISNULL((0.6745 * (ISNULL(IP.pct_pico,0) - PM.med_pico)) / NULLIF(PM.mad_pico,0),0) AS mz_pico,
        ISNULL((0.6745 * (ISNULL(IP.pct_compra_unica,0) - PM.med_compra_unica)) / NULLIF(PM.mad_compra_unica,0),0) AS mz_compra_unica,
        ISNULL((0.6745 * (ISNULL(IP.val_hhi_crm,0) - PM.med_crm_hhi)) / NULLIF(PM.mad_crm_hhi,0),0) AS mz_crm_hhi,
        ISNULL((0.6745 * (ISNULL(IP.pct_exclusividade_crm,0) - PM.med_exclusividade)) / NULLIF(PM.mad_exclusividade,0),0) AS mz_exclusividade,
        ISNULL((0.6745 * (ISNULL(IP.pct_crms_irregulares,0) - PM.med_crms_irregulares)) / NULLIF(PM.mad_crms_irregulares,0),0) AS mz_crms_irregulares,
        ISNULL((0.6745 * (ISNULL(IP.pct_recorrencia_sistemica,0) - PM.med_recorrencia)) / NULLIF(PM.mad_recorrencia,0),0) AS mz_recorrencia,
        ISNULL((0.6745 * (ISNULL(IP.pct_auditado,0) - PM.med_auditado)) / NULLIF(PM.mad_auditado,0),0) AS mz_auditado
    FROM IndicadoresPresenca IP
    INNER JOIN PassoCalculoMAD PM ON PM.cnpj = IP.cnpj
),

-- Adiciona os Flags Multinível (Atenção / Crítico)
ConsolidacaoFlagsMultinivel AS (
    SELECT 
        *,
        -- FLAGS CRÍTICO (Vermelho)
        CASE WHEN mz_falecidos >= @MAD_CRIT_FALECIDOS THEN 1 ELSE 0 END AS flag_falecidos_critico,
        CASE WHEN mz_clinico >= @MAD_CRIT_CLINICO THEN 1 ELSE 0 END AS flag_incompatibilidade_patologica_critico,
        CASE WHEN mz_teto >= @MAD_CRIT_TETO THEN 1 ELSE 0 END AS flag_estouro_teto_critico,
        CASE WHEN mz_polimedicamento >= @MAD_CRIT_POLIMEDICAMENTO THEN 1 ELSE 0 END AS flag_polimedicamento_critico,
        CASE WHEN mz_ticket >= @MAD_CRIT_TICKET_MEDIO THEN 1 ELSE 0 END AS flag_ticket_medio_critico,
        CASE WHEN mz_receita >= @MAD_CRIT_RECEITA_PACIENTE THEN 1 ELSE 0 END AS flag_receita_paciente_critico,
        CASE WHEN mz_per_capita >= @MAD_CRIT_PER_CAPITA THEN 1 ELSE 0 END AS flag_per_capita_critico,
        CASE WHEN mz_vendas_rapidas >= @MAD_CRIT_VENDAS_RAPIDAS THEN 1 ELSE 0 END AS flag_vendas_rapidas_critico,
        CASE WHEN mz_volume_atipico >= @MAD_CRIT_VOLUME_ATIPICO THEN 1 ELSE 0 END AS flag_volume_atipico_critico,
        CASE WHEN mz_geografico >= @MAD_CRIT_DISTANCIA_GEOGRAFICA THEN 1 ELSE 0 END AS flag_dispersao_geografica_critico,
        CASE WHEN mz_alto_custo >= @MAD_CRIT_ALTO_CUSTO THEN 1 ELSE 0 END AS flag_alto_custo_critico,
        CASE WHEN mz_pico >= @MAD_CRIT_CONCENTRACAO_PICO THEN 1 ELSE 0 END AS flag_concentracao_pico_critico,
        CASE WHEN mz_compra_unica >= @MAD_CRIT_COMPRA_UNICA THEN 1 ELSE 0 END AS flag_compra_unica_critico,
        CASE WHEN mz_crm_hhi >= @MAD_CRIT_CRM_HHI THEN 1 ELSE 0 END AS flag_hhi_crm_critico,
        CASE WHEN mz_exclusividade >= @MAD_CRIT_EXCLUSIVIDADE_CRM THEN 1 ELSE 0 END AS flag_exclusividade_crm_critico,
        CASE WHEN mz_crms_irregulares >= @MAD_CRIT_CRMS_IRREGULARES THEN 1 ELSE 0 END AS flag_crms_irregulares_critico,
        CASE WHEN mz_recorrencia >= @MAD_CRIT_RECORRENCIA_SISTEMICA THEN 1 ELSE 0 END AS flag_recorrencia_sistemica_critico,
        CASE WHEN mz_auditado >= @MAD_CRIT_AUDITORIA THEN 1 ELSE 0 END AS flag_percentual_sem_comprovacao_critico,

        -- FLAGS ATENÇÃO (Amarelo) - Só marca se não for Crítico
        CASE WHEN mz_falecidos >= @MAD_ATEN_FALECIDOS AND mz_falecidos < @MAD_CRIT_FALECIDOS THEN 1 ELSE 0 END AS flag_falecidos_atencao,
        CASE WHEN mz_clinico >= @MAD_ATEN_CLINICO AND mz_clinico < @MAD_CRIT_CLINICO THEN 1 ELSE 0 END AS flag_incompatibilidade_patologica_atencao,
        CASE WHEN mz_teto >= @MAD_ATEN_TETO AND mz_teto < @MAD_CRIT_TETO THEN 1 ELSE 0 END AS flag_estouro_teto_atencao,
        CASE WHEN mz_polimedicamento >= @MAD_ATEN_POLIMEDICAMENTO AND mz_polimedicamento < @MAD_CRIT_POLIMEDICAMENTO THEN 1 ELSE 0 END AS flag_polimedicamento_atencao,
        CASE WHEN mz_ticket >= @MAD_ATEN_TICKET_MEDIO AND mz_ticket < @MAD_CRIT_TICKET_MEDIO THEN 1 ELSE 0 END AS flag_ticket_medio_atencao,
        CASE WHEN mz_receita >= @MAD_ATEN_RECEITA_PACIENTE AND mz_receita < @MAD_CRIT_RECEITA_PACIENTE THEN 1 ELSE 0 END AS flag_receita_paciente_atencao,
        CASE WHEN mz_per_capita >= @MAD_ATEN_PER_CAPITA AND mz_per_capita < @MAD_CRIT_PER_CAPITA THEN 1 ELSE 0 END AS flag_per_capita_atencao,
        CASE WHEN mz_vendas_rapidas >= @MAD_ATEN_VENDAS_RAPIDAS AND mz_vendas_rapidas < @MAD_CRIT_VENDAS_RAPIDAS THEN 1 ELSE 0 END AS flag_vendas_rapidas_atencao,
        CASE WHEN mz_volume_atipico >= @MAD_ATEN_VOLUME_ATIPICO AND mz_volume_atipico < @MAD_CRIT_VOLUME_ATIPICO THEN 1 ELSE 0 END AS flag_volume_atipico_atencao,
        CASE WHEN mz_geografico >= @MAD_ATEN_DISTANCIA_GEOGRAFICA AND mz_geografico < @MAD_CRIT_DISTANCIA_GEOGRAFICA THEN 1 ELSE 0 END AS flag_dispersao_geografica_atencao,
        CASE WHEN mz_alto_custo >= @MAD_ATEN_ALTO_CUSTO AND mz_alto_custo < @MAD_CRIT_ALTO_CUSTO THEN 1 ELSE 0 END AS flag_alto_custo_atencao,
        CASE WHEN mz_pico >= @MAD_ATEN_CONCENTRACAO_PICO AND mz_pico < @MAD_CRIT_CONCENTRACAO_PICO THEN 1 ELSE 0 END AS flag_concentracao_pico_atencao,
        CASE WHEN mz_compra_unica >= @MAD_ATEN_COMPRA_UNICA AND mz_compra_unica < @MAD_CRIT_COMPRA_UNICA THEN 1 ELSE 0 END AS flag_compra_unica_atencao,
        CASE WHEN mz_crm_hhi >= @MAD_ATEN_CRM_HHI AND mz_crm_hhi < @MAD_CRIT_CRM_HHI THEN 1 ELSE 0 END AS flag_hhi_crm_atencao,
        CASE WHEN mz_exclusividade >= @MAD_ATEN_EXCLUSIVIDADE_CRM AND mz_exclusividade < @MAD_CRIT_EXCLUSIVIDADE_CRM THEN 1 ELSE 0 END AS flag_exclusividade_crm_atencao,
        CASE WHEN mz_crms_irregulares >= @MAD_ATEN_CRMS_IRREGULARES AND mz_crms_irregulares < @MAD_CRIT_CRMS_IRREGULARES THEN 1 ELSE 0 END AS flag_crms_irregulares_atencao,
        CASE WHEN mz_recorrencia >= @MAD_ATEN_RECORRENCIA_SISTEMICA AND mz_recorrencia < @MAD_CRIT_RECORRENCIA_SISTEMICA THEN 1 ELSE 0 END AS flag_recorrencia_sistemica_atencao,
        CASE WHEN mz_auditado >= @MAD_ATEN_AUDITORIA AND mz_auditado < @MAD_CRIT_AUDITORIA THEN 1 ELSE 0 END AS flag_percentual_sem_comprovacao_atencao
    FROM CalculoFlagsMAD
),

-- 4. CTE 3: CONSOLIDAÇÃO DE ALERTA (COUNT E LISTA)
ConsolidacaoFlags AS (
    SELECT
        *,
        (flag_falecidos_critico + flag_incompatibilidade_patologica_critico + flag_estouro_teto_critico + flag_polimedicamento_critico + flag_ticket_medio_critico + flag_receita_paciente_critico + flag_per_capita_critico + flag_vendas_rapidas_critico + flag_volume_atipico_critico + flag_dispersao_geografica_critico + flag_alto_custo_critico + flag_concentracao_pico_critico + flag_compra_unica_critico + flag_hhi_crm_critico + flag_exclusividade_crm_critico + flag_crms_irregulares_critico + flag_recorrencia_sistemica_critico + flag_percentual_sem_comprovacao_critico) AS qtd_criticos,
        (flag_falecidos_atencao + flag_incompatibilidade_patologica_atencao + flag_estouro_teto_atencao + flag_polimedicamento_atencao + flag_ticket_medio_atencao + flag_receita_paciente_atencao + flag_per_capita_atencao + flag_vendas_rapidas_atencao + flag_volume_atipico_atencao + flag_dispersao_geografica_atencao + flag_alto_custo_atencao + flag_concentracao_pico_atencao + flag_compra_unica_atencao + flag_hhi_crm_atencao + flag_exclusividade_crm_atencao + flag_crms_irregulares_atencao + flag_recorrencia_sistemica_atencao + flag_percentual_sem_comprovacao_atencao) AS qtd_atencao,

        -- Pontuação cumulativa baseada nos níveis (+10 Crítico, +3 Atenção)
        (
          ((flag_falecidos_critico + flag_incompatibilidade_patologica_critico + flag_estouro_teto_critico + flag_polimedicamento_critico + flag_ticket_medio_critico + flag_receita_paciente_critico + flag_per_capita_critico + flag_vendas_rapidas_critico + flag_volume_atipico_critico + flag_dispersao_geografica_critico + flag_alto_custo_critico + flag_concentracao_pico_critico + flag_compra_unica_critico + flag_hhi_crm_critico + flag_exclusividade_crm_critico + flag_crms_irregulares_critico + flag_recorrencia_sistemica_critico + flag_percentual_sem_comprovacao_critico) * 10) +
          ((flag_falecidos_atencao + flag_incompatibilidade_patologica_atencao + flag_estouro_teto_atencao + flag_polimedicamento_atencao + flag_ticket_medio_atencao + flag_receita_paciente_atencao + flag_per_capita_atencao + flag_vendas_rapidas_atencao + flag_volume_atipico_atencao + flag_dispersao_geografica_atencao + flag_alto_custo_atencao + flag_concentracao_pico_atencao + flag_compra_unica_atencao + flag_hhi_crm_atencao + flag_exclusividade_crm_atencao + flag_crms_irregulares_atencao + flag_recorrencia_sistemica_atencao + flag_percentual_sem_comprovacao_atencao) * 3)
        ) AS pontos_penalidade

        -- CAMPO COMENTADO: lista textual de indicadores disparados por farmácia (ex: "🔴Vendas p/ Falecidos, 🟡Policompra")
        -- Útil para relatórios/tooltips, mas redundante com as colunas fl_* individuais para uso em BI.
        -- Descomentar se necessário para exportação ou exibição direta.
        /*
        STUFF(
            (CASE WHEN flag_falecidos_critico=1 THEN ', 🔴Vendas p/ Falecidos' WHEN flag_falecidos_atencao=1 THEN ', 🟡Vendas p/ Falecidos' ELSE '' END) +
            (CASE WHEN flag_incompatibilidade_patologica_critico=1 THEN ', 🔴Incompatibilidade Patológica' WHEN flag_incompatibilidade_patologica_atencao=1 THEN ', 🟡Incompatibilidade Patológica' ELSE '' END) +
            (CASE WHEN flag_estouro_teto_critico=1 THEN ', 🔴Dispensação em Teto Máximo' WHEN flag_estouro_teto_atencao=1 THEN ', 🟡Dispensação em Teto Máximo' ELSE '' END) +
            (CASE WHEN flag_polimedicamento_critico=1 THEN ', 🔴4+ Itens por Autorização' WHEN flag_polimedicamento_atencao=1 THEN ', 🟡4+ Itens por Autorização' ELSE '' END) +
            (CASE WHEN flag_ticket_medio_critico=1 THEN ', 🔴Valor do Ticket Médio' WHEN flag_ticket_medio_atencao=1 THEN ', 🟡Valor do Ticket Médio' ELSE '' END) +
            (CASE WHEN flag_receita_paciente_critico=1 THEN ', 🔴Faturamento Médio por Cliente' WHEN flag_receita_paciente_atencao=1 THEN ', 🟡Faturamento Médio por Cliente' ELSE '' END) +
            (CASE WHEN flag_per_capita_critico=1 THEN ', 🔴Venda Per Capita Mensal' WHEN flag_per_capita_atencao=1 THEN ', 🟡Venda Per Capita Mensal' ELSE '' END) +
            (CASE WHEN flag_vendas_rapidas_critico=1 THEN ', 🔴Vendas Rápidas (<60s)' WHEN flag_vendas_rapidas_atencao=1 THEN ', 🟡Vendas Rápidas (<60s)' ELSE '' END) +
            (CASE WHEN flag_volume_atipico_critico=1 THEN ', 🔴Volume Atípico' WHEN flag_volume_atipico_atencao=1 THEN ', 🟡Volume Atípico' ELSE '' END) +
            (CASE WHEN flag_dispersao_geografica_critico=1 THEN ', 🔴Dispersão Geográfica Interestadual' WHEN flag_dispersao_geografica_atencao=1 THEN ', 🟡Dispersão Geográfica Interestadual' ELSE '' END) +
            (CASE WHEN flag_alto_custo_critico=1 THEN ', 🔴Medicamentos de Alto Custo' WHEN flag_alto_custo_atencao=1 THEN ', 🟡Medicamentos de Alto Custo' ELSE '' END) +
            (CASE WHEN flag_concentracao_pico_critico=1 THEN ', 🔴Concentração em Dias de Pico' WHEN flag_concentracao_pico_atencao=1 THEN ', 🟡Concentração em Dias de Pico' ELSE '' END) +
            (CASE WHEN flag_compra_unica_critico=1 THEN ', 🔴Compra Única' WHEN flag_compra_unica_atencao=1 THEN ', 🟡Compra Única' ELSE '' END) +
            (CASE WHEN flag_hhi_crm_critico=1 THEN ', 🔴Concentração de CRMs (HHI)' WHEN flag_hhi_crm_atencao=1 THEN ', 🟡Concentração de CRMs (HHI)' ELSE '' END) +
            (CASE WHEN flag_exclusividade_crm_critico=1 THEN ', 🔴Exclusividade de CRMs' WHEN flag_exclusividade_crm_atencao=1 THEN ', 🟡Exclusividade de CRMs' ELSE '' END) +
            (CASE WHEN flag_crms_irregulares_critico=1 THEN ', 🔴Faturamento Atrelado a CRMs Irregulares' WHEN flag_crms_irregulares_atencao=1 THEN ', 🟡Faturamento Atrelado a CRMs Irregulares' ELSE '' END) +
            (CASE WHEN flag_recorrencia_sistemica_critico=1 THEN ', 🔴Recorrência Sistêmica' WHEN flag_recorrencia_sistemica_atencao=1 THEN ', 🟡Recorrência Sistêmica' ELSE '' END) +
            (CASE WHEN flag_percentual_sem_comprovacao_critico=1 THEN ', 🔴Percentual de Não Comprovação' WHEN flag_percentual_sem_comprovacao_atencao=1 THEN ', 🟡Percentual de Não Comprovação' ELSE '' END)
        , 1, 2, '') AS indicadores_risco_lista
        */
    FROM ConsolidacaoFlagsMultinivel
),

-- ====================================================================================
-- BASE DE NORMALIZAÇÃO
-- Calcula CUME_DIST (percentil 0-100) por REGIÃO e por UF para cada indicador.
-- Ambos são calculados sempre; a escolha entre eles ocorre na CTE seguinte.
-- ASC = menor risco = menor percentil = menos suspeito
-- ====================================================================================
NormalizacaoBase AS (
    SELECT
        IP.cnpj,
        IP.uf,
        IP.id_regiao_saude,
        CR.escopo_benchmark,

        -- 1. FALECIDOS
        CAST(PERCENT_RANK() OVER (PARTITION BY IP.id_regiao_saude ORDER BY ISNULL(IP.risco_falecidos_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_reg_falecidos,
        CAST(PERCENT_RANK() OVER (PARTITION BY IP.uf             ORDER BY ISNULL(IP.risco_falecidos_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_uf_falecidos,

        -- 2. CLÍNICO
        CAST(PERCENT_RANK() OVER (PARTITION BY IP.id_regiao_saude ORDER BY ISNULL(IP.risco_clinico_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_reg_clinico,
        CAST(PERCENT_RANK() OVER (PARTITION BY IP.uf             ORDER BY ISNULL(IP.risco_clinico_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_uf_clinico,

        -- 3. TETO
        CAST(PERCENT_RANK() OVER (PARTITION BY IP.id_regiao_saude ORDER BY ISNULL(IP.risco_teto_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_reg_teto,
        CAST(PERCENT_RANK() OVER (PARTITION BY IP.uf             ORDER BY ISNULL(IP.risco_teto_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_uf_teto,

        -- 4. POLIMEDICAMENTO
        CAST(PERCENT_RANK() OVER (PARTITION BY IP.id_regiao_saude ORDER BY ISNULL(IP.risco_polimedicamento_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_reg_polimedicamento,
        CAST(PERCENT_RANK() OVER (PARTITION BY IP.uf             ORDER BY ISNULL(IP.risco_polimedicamento_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_uf_polimedicamento,

        -- 5. TICKET MÉDIO
        CAST(PERCENT_RANK() OVER (PARTITION BY IP.id_regiao_saude ORDER BY ISNULL(IP.risco_ticket_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_reg_ticket,
        CAST(PERCENT_RANK() OVER (PARTITION BY IP.uf             ORDER BY ISNULL(IP.risco_ticket_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_uf_ticket,

        -- 6. RECEITA POR PACIENTE
        CAST(PERCENT_RANK() OVER (PARTITION BY IP.id_regiao_saude ORDER BY ISNULL(IP.risco_receita_paciente_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_reg_receita_paciente,
        CAST(PERCENT_RANK() OVER (PARTITION BY IP.uf             ORDER BY ISNULL(IP.risco_receita_paciente_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_uf_receita_paciente,

        -- 7. PER CAPITA
        CAST(PERCENT_RANK() OVER (PARTITION BY IP.id_regiao_saude ORDER BY ISNULL(IP.risco_per_capita_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_reg_per_capita,
        CAST(PERCENT_RANK() OVER (PARTITION BY IP.uf             ORDER BY ISNULL(IP.risco_per_capita_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_uf_per_capita,

        -- 8. VENDAS RÁPIDAS
        CAST(PERCENT_RANK() OVER (PARTITION BY IP.id_regiao_saude ORDER BY ISNULL(IP.risco_vendas_rapidas_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_reg_vendas_rapidas,
        CAST(PERCENT_RANK() OVER (PARTITION BY IP.uf             ORDER BY ISNULL(IP.risco_vendas_rapidas_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_uf_vendas_rapidas,

        -- 9. VOLUME ATÍPICO
        CAST(PERCENT_RANK() OVER (PARTITION BY IP.id_regiao_saude ORDER BY ISNULL(IP.risco_volume_atipico_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_reg_volume_atipico,
        CAST(PERCENT_RANK() OVER (PARTITION BY IP.uf             ORDER BY ISNULL(IP.risco_volume_atipico_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_uf_volume_atipico,

        -- 10. GEOGRÁFICO
        CAST(PERCENT_RANK() OVER (PARTITION BY IP.id_regiao_saude ORDER BY ISNULL(IP.risco_geografico_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_reg_geografico,
        CAST(PERCENT_RANK() OVER (PARTITION BY IP.uf             ORDER BY ISNULL(IP.risco_geografico_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_uf_geografico,

        -- 11. ALTO CUSTO
        CAST(PERCENT_RANK() OVER (PARTITION BY IP.id_regiao_saude ORDER BY ISNULL(IP.risco_alto_custo_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_reg_alto_custo,
        CAST(PERCENT_RANK() OVER (PARTITION BY IP.uf             ORDER BY ISNULL(IP.risco_alto_custo_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_uf_alto_custo,

        -- 12. PICO
        CAST(PERCENT_RANK() OVER (PARTITION BY IP.id_regiao_saude ORDER BY ISNULL(IP.risco_pico_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_reg_pico,
        CAST(PERCENT_RANK() OVER (PARTITION BY IP.uf             ORDER BY ISNULL(IP.risco_pico_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_uf_pico,

        -- 13. COMPRA ÚNICA
        CAST(PERCENT_RANK() OVER (PARTITION BY IP.id_regiao_saude ORDER BY ISNULL(IP.risco_compra_unica_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_reg_compra_unica,
        CAST(PERCENT_RANK() OVER (PARTITION BY IP.uf             ORDER BY ISNULL(IP.risco_compra_unica_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_uf_compra_unica,

        -- 14. CRM HHI
        CAST(PERCENT_RANK() OVER (PARTITION BY IP.id_regiao_saude ORDER BY ISNULL(IP.risco_crm_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_reg_crm,
        CAST(PERCENT_RANK() OVER (PARTITION BY IP.uf             ORDER BY ISNULL(IP.risco_crm_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_uf_crm,

        -- 15. EXCLUSIVIDADE CRM
        CAST(PERCENT_RANK() OVER (PARTITION BY IP.id_regiao_saude ORDER BY ISNULL(IP.risco_exclusividade_crm_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_reg_exclusividade_crm,
        CAST(PERCENT_RANK() OVER (PARTITION BY IP.uf             ORDER BY ISNULL(IP.risco_exclusividade_crm_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_uf_exclusividade_crm,

        -- 16. CRMs IRREGULARES
        CAST(PERCENT_RANK() OVER (PARTITION BY IP.id_regiao_saude ORDER BY ISNULL(IP.risco_crms_irregulares_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_reg_crms_irregulares,
        CAST(PERCENT_RANK() OVER (PARTITION BY IP.uf             ORDER BY ISNULL(IP.risco_crms_irregulares_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_uf_crms_irregulares,

        -- 17. RECORRÊNCIA SISTÊMICA
        CAST(PERCENT_RANK() OVER (PARTITION BY IP.id_regiao_saude ORDER BY ISNULL(IP.risco_recorrencia_sistemica_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_reg_recorrencia_sistemica,
        CAST(PERCENT_RANK() OVER (PARTITION BY IP.uf             ORDER BY ISNULL(IP.risco_recorrencia_sistemica_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_uf_recorrencia_sistemica,

        -- 18. AUDITORIA
        CAST(PERCENT_RANK() OVER (PARTITION BY IP.id_regiao_saude ORDER BY ISNULL(IP.risco_auditado_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_reg_auditado,
        CAST(PERCENT_RANK() OVER (PARTITION BY IP.uf             ORDER BY ISNULL(IP.risco_auditado_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_uf_auditado

    FROM IndicadoresPresenca IP
    LEFT JOIN ContadorRegiao CR ON CR.id_regiao_saude = IP.id_regiao_saude
),

-- ====================================================================================
-- NORMALIZAÇÃO FINAL (ESCOLHA DO ESCOPO CORRETO)
-- Seleciona o percentil de Região ou UF conforme o escopo_benchmark.
-- Farmácias sem id_regiao_saude sempre usam UF.
-- ====================================================================================
Normalizacao AS (
    SELECT
        cnpj,
        escopo_benchmark,
        CASE WHEN escopo_benchmark = 'REGIAO' THEN pct_reg_falecidos           ELSE pct_uf_falecidos           END AS score_pct_falecidos,
        CASE WHEN escopo_benchmark = 'REGIAO' THEN pct_reg_clinico             ELSE pct_uf_clinico             END AS score_pct_clinico,
        CASE WHEN escopo_benchmark = 'REGIAO' THEN pct_reg_teto                ELSE pct_uf_teto                END AS score_pct_teto,
        CASE WHEN escopo_benchmark = 'REGIAO' THEN pct_reg_polimedicamento     ELSE pct_uf_polimedicamento     END AS score_pct_polimedicamento,
        CASE WHEN escopo_benchmark = 'REGIAO' THEN pct_reg_ticket              ELSE pct_uf_ticket              END AS score_pct_ticket,
        CASE WHEN escopo_benchmark = 'REGIAO' THEN pct_reg_receita_paciente    ELSE pct_uf_receita_paciente    END AS score_pct_receita_paciente,
        CASE WHEN escopo_benchmark = 'REGIAO' THEN pct_reg_per_capita          ELSE pct_uf_per_capita          END AS score_pct_per_capita,
        CASE WHEN escopo_benchmark = 'REGIAO' THEN pct_reg_vendas_rapidas      ELSE pct_uf_vendas_rapidas      END AS score_pct_vendas_rapidas,
        CASE WHEN escopo_benchmark = 'REGIAO' THEN pct_reg_volume_atipico      ELSE pct_uf_volume_atipico      END AS score_pct_volume_atipico,
        CASE WHEN escopo_benchmark = 'REGIAO' THEN pct_reg_geografico          ELSE pct_uf_geografico          END AS score_pct_geografico,
        CASE WHEN escopo_benchmark = 'REGIAO' THEN pct_reg_alto_custo          ELSE pct_uf_alto_custo          END AS score_pct_alto_custo,
        CASE WHEN escopo_benchmark = 'REGIAO' THEN pct_reg_pico                ELSE pct_uf_pico                END AS score_pct_pico,
        CASE WHEN escopo_benchmark = 'REGIAO' THEN pct_reg_compra_unica        ELSE pct_uf_compra_unica        END AS score_pct_compra_unica,
        CASE WHEN escopo_benchmark = 'REGIAO' THEN pct_reg_crm                 ELSE pct_uf_crm                 END AS score_pct_crm,
        CASE WHEN escopo_benchmark = 'REGIAO' THEN pct_reg_exclusividade_crm   ELSE pct_uf_exclusividade_crm   END AS score_pct_exclusividade_crm,
        CASE WHEN escopo_benchmark = 'REGIAO' THEN pct_reg_crms_irregulares    ELSE pct_uf_crms_irregulares    END AS score_pct_crms_irregulares,
        CASE WHEN escopo_benchmark = 'REGIAO' THEN pct_reg_recorrencia_sistemica ELSE pct_uf_recorrencia_sistemica END AS score_pct_recorrencia_sistemica,
        CASE WHEN escopo_benchmark = 'REGIAO' THEN pct_reg_auditado            ELSE pct_uf_auditado            END AS score_pct_auditado
    FROM NormalizacaoBase
),

-- Pré-computa soma_pesos_ativos para reutilização no score_base e nas 18 contrib_*
-- Evita repetição da expressão de 18 termos em cada coluna de contribuição individual
PesosCalculados AS (
    SELECT
        cnpj,
        (
            (tem_falecidos            * @PESO_FALECIDOS) +
            (tem_clinico              * @PESO_INCONSISTENCIA_CLINICA) +
            (tem_teto                 * @PESO_ESTOURO_TETO) +
            (tem_polimedicamento      * @PESO_POLIMEDICAMENTO) +
            (tem_ticket               * @PESO_TICKET_MEDIO) +
            (tem_receita_paciente     * @PESO_RECEITA_POR_PACIENTE) +
            (tem_per_capita           * @PESO_VALOR_PER_CAPITA) +
            (tem_vendas_rapidas       * @PESO_VENDAS_CONSECUTIVAS_RAPIDAS) +
            (tem_volume_atipico       * @PESO_VOLUME_ATIPICO) +
            (tem_geografico           * @PESO_DISTANCIA_GEOGRAFICA) +
            (tem_alto_custo           * @PESO_ALTO_CUSTO) +
            (tem_pico                 * @PESO_CONCENTRACAO_PICO) +
            (tem_compra_unica         * @PESO_COMPRA_UNICA) +
            (tem_crm                  * @PESO_CONCENTRACAO_CRM_HHI) +
            (tem_exclusividade_crm    * @PESO_EXCLUSIVIDADE_CRM) +
            (tem_crms_irregulares     * @PESO_CRMS_IRREGULARES) +
            (tem_recorrencia_sistemica* @PESO_RECORRENCIA_SISTEMICA) +
            (tem_auditado             * @PESO_PERCENTUAL_SEM_COMPROVACAO)
        ) AS soma_pesos_ativos
    FROM ConsolidacaoFlags
),

-- Calcula a nota base (0-100) via média ponderada e as contribuições individuais
ScoreBaseCalculado AS (
    SELECT
        CF.*,
        PC.soma_pesos_ativos,

        -- NOTA BASE FINAL
        CAST(
            (
                (ISNULL(NV.score_pct_falecidos,            0) * @PESO_FALECIDOS) +
                (ISNULL(NV.score_pct_clinico,              0) * @PESO_INCONSISTENCIA_CLINICA) +
                (ISNULL(NV.score_pct_teto,                 0) * @PESO_ESTOURO_TETO) +
                (ISNULL(NV.score_pct_polimedicamento,      0) * @PESO_POLIMEDICAMENTO) +
                (ISNULL(NV.score_pct_ticket,               0) * @PESO_TICKET_MEDIO) +
                (ISNULL(NV.score_pct_receita_paciente,     0) * @PESO_RECEITA_POR_PACIENTE) +
                (ISNULL(NV.score_pct_per_capita,           0) * @PESO_VALOR_PER_CAPITA) +
                (ISNULL(NV.score_pct_vendas_rapidas,       0) * @PESO_VENDAS_CONSECUTIVAS_RAPIDAS) +
                (ISNULL(NV.score_pct_volume_atipico,       0) * @PESO_VOLUME_ATIPICO) +
                (ISNULL(NV.score_pct_geografico,           0) * @PESO_DISTANCIA_GEOGRAFICA) +
                (ISNULL(NV.score_pct_alto_custo,           0) * @PESO_ALTO_CUSTO) +
                (ISNULL(NV.score_pct_pico,                 0) * @PESO_CONCENTRACAO_PICO) +
                (ISNULL(NV.score_pct_compra_unica,         0) * @PESO_COMPRA_UNICA) +
                (ISNULL(NV.score_pct_crm,                  0) * @PESO_CONCENTRACAO_CRM_HHI) +
                (ISNULL(NV.score_pct_exclusividade_crm,    0) * @PESO_EXCLUSIVIDADE_CRM) +
                (ISNULL(NV.score_pct_crms_irregulares,     0) * @PESO_CRMS_IRREGULARES) +
                (ISNULL(NV.score_pct_recorrencia_sistemica,0) * @PESO_RECORRENCIA_SISTEMICA) +
                (ISNULL(NV.score_pct_auditado,             0) * @PESO_PERCENTUAL_SEM_COMPROVACAO)
            )
            /
            NULLIF(PC.soma_pesos_ativos, 0)
        AS DECIMAL(7,2)) AS score_base,

        -- CONTRIBUIÇÕES INDIVIDUAIS (Para análise Waterfall no BI)
        CAST((ISNULL(NV.score_pct_falecidos, 0) * @PESO_FALECIDOS) / NULLIF(PC.soma_pesos_ativos, 0) AS DECIMAL(5,2)) AS contrib_falecidos,
        CAST((ISNULL(NV.score_pct_clinico,   0) * @PESO_INCONSISTENCIA_CLINICA) / NULLIF(PC.soma_pesos_ativos, 0) AS DECIMAL(5,2)) AS contrib_clinico,
        CAST((ISNULL(NV.score_pct_teto,      0) * @PESO_ESTOURO_TETO) / NULLIF(PC.soma_pesos_ativos, 0) AS DECIMAL(5,2)) AS contrib_teto,
        CAST((ISNULL(NV.score_pct_polimedicamento, 0) * @PESO_POLIMEDICAMENTO) / NULLIF(PC.soma_pesos_ativos, 0) AS DECIMAL(5,2)) AS contrib_polimedicamento,
        CAST((ISNULL(NV.score_pct_ticket,    0) * @PESO_TICKET_MEDIO) / NULLIF(PC.soma_pesos_ativos, 0) AS DECIMAL(5,2)) AS contrib_ticket,
        CAST((ISNULL(NV.score_pct_receita_paciente, 0) * @PESO_RECEITA_POR_PACIENTE) / NULLIF(PC.soma_pesos_ativos, 0) AS DECIMAL(5,2)) AS contrib_receita_paciente,
        CAST((ISNULL(NV.score_pct_per_capita, 0) * @PESO_VALOR_PER_CAPITA) / NULLIF(PC.soma_pesos_ativos, 0) AS DECIMAL(5,2)) AS contrib_per_capita,
        CAST((ISNULL(NV.score_pct_vendas_rapidas, 0) * @PESO_VENDAS_CONSECUTIVAS_RAPIDAS) / NULLIF(PC.soma_pesos_ativos, 0) AS DECIMAL(5,2)) AS contrib_vendas_rapidas,
        CAST((ISNULL(NV.score_pct_volume_atipico, 0) * @PESO_VOLUME_ATIPICO) / NULLIF(PC.soma_pesos_ativos, 0) AS DECIMAL(5,2)) AS contrib_volume_atipico,
        CAST((ISNULL(NV.score_pct_geografico,     0) * @PESO_DISTANCIA_GEOGRAFICA) / NULLIF(PC.soma_pesos_ativos, 0) AS DECIMAL(5,2)) AS contrib_geografico,
        CAST((ISNULL(NV.score_pct_alto_custo,    0) * @PESO_ALTO_CUSTO) / NULLIF(PC.soma_pesos_ativos, 0) AS DECIMAL(5,2)) AS contrib_alto_custo,
        CAST((ISNULL(NV.score_pct_pico,          0) * @PESO_CONCENTRACAO_PICO) / NULLIF(PC.soma_pesos_ativos, 0) AS DECIMAL(5,2)) AS contrib_pico,
        CAST((ISNULL(NV.score_pct_compra_unica,  0) * @PESO_COMPRA_UNICA) / NULLIF(PC.soma_pesos_ativos, 0) AS DECIMAL(5,2)) AS contrib_compra_unica,
        CAST((ISNULL(NV.score_pct_crm,           0) * @PESO_CONCENTRACAO_CRM_HHI) / NULLIF(PC.soma_pesos_ativos, 0) AS DECIMAL(5,2)) AS contrib_crm_hhi,
        CAST((ISNULL(NV.score_pct_exclusividade_crm, 0) * @PESO_EXCLUSIVIDADE_CRM) / NULLIF(PC.soma_pesos_ativos, 0) AS DECIMAL(5,2)) AS contrib_exclusividade_crm,
        CAST((ISNULL(NV.score_pct_crms_irregulares, 0) * @PESO_CRMS_IRREGULARES) / NULLIF(PC.soma_pesos_ativos, 0) AS DECIMAL(5,2)) AS contrib_crms_irregulares,
        CAST((ISNULL(NV.score_pct_recorrencia_sistemica, 0) * @PESO_RECORRENCIA_SISTEMICA) / NULLIF(PC.soma_pesos_ativos, 0) AS DECIMAL(5,2)) AS contrib_recorrencia_sistemica,
        CAST((ISNULL(NV.score_pct_auditado,      0) * @PESO_PERCENTUAL_SEM_COMPROVACAO) / NULLIF(PC.soma_pesos_ativos, 0) AS DECIMAL(5,2)) AS contrib_auditado
    FROM ConsolidacaoFlags CF
    INNER JOIN PesosCalculados PC ON PC.cnpj = CF.cnpj
    LEFT JOIN Normalizacao NV ON NV.cnpj = CF.cnpj
),

ScoreFinal AS (
    SELECT
        *,

        -- SCORE FINAL
        -- Formula: Média Ponderada Percentil (0-100) + Bônus Cumulativo (Atenção/Crítico)
        -- ISNULL(score_base, 0): farmácias sem nenhum indicador ativo têm soma_pesos=0,
        --   o que causa score_base=NULL via NULLIF. Tratado aqui para garantir score numérico.
        CAST(
            (ISNULL(score_base, 0) + ISNULL(pontos_penalidade, 0))
        AS DECIMAL(18,2)) AS score_risco_final,

        -- CLASSIFICAÇÃO DE RISCO
        -- Lógica de pisos por qtd_criticos (trava independente do score percentil):
        --   1-2 críticos → mínimo MÉDIO | 3-4 críticos → mínimo ALTO | 5+ → mínimo CRÍTICO
        -- O score percentil pode elevar a classificação acima do piso, nunca abaixo.
        CASE
            WHEN (ISNULL(score_base, 0) + ISNULL(pontos_penalidade, 0)) >= 90  OR qtd_criticos >= 5 THEN 'RISCO CRITICO'
            WHEN (ISNULL(score_base, 0) + ISNULL(pontos_penalidade, 0)) >= 70  OR qtd_criticos >= 3 THEN 'RISCO ALTO'
            WHEN (ISNULL(score_base, 0) + ISNULL(pontos_penalidade, 0)) >= 50  OR qtd_criticos >= 1 THEN 'RISCO MEDIO'
            ELSE 'RISCO BAIXO'
        END AS classificacao_risco
    FROM ScoreBaseCalculado
)

-- 7. SELEÇÃO FINAL E CRIAÇÃO DA TABELA FÍSICA
SELECT 
    S.*,
    
    -- RANKINGS
    RANK() OVER (ORDER BY score_risco_final DESC) AS rank_nacional,
    COUNT(*) OVER () AS total_nacional,
    RANK() OVER (PARTITION BY uf ORDER BY score_risco_final DESC) AS rank_uf,
    COUNT(*) OVER (PARTITION BY uf) AS total_uf,

    -- REGIAO DE SAUDE
    RANK() OVER (PARTITION BY id_regiao_saude ORDER BY score_risco_final DESC) AS rank_regiao_saude,
    COUNT(*) OVER (PARTITION BY id_regiao_saude) AS total_regiao_saude,
    CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY score_risco_final) OVER (PARTITION BY id_regiao_saude) AS DECIMAL(18,2)) AS mediana_score_regiao_saude,
    CAST(MAX(score_risco_final) OVER (PARTITION BY id_regiao_saude) AS DECIMAL(18,2)) AS max_score_regiao_saude,

    -- INTELIGÊNCIA MUNICIPAL
    RANK() OVER (PARTITION BY uf, municipio ORDER BY score_risco_final DESC) AS rank_municipio,
    COUNT(*) OVER (PARTITION BY uf, municipio) AS total_municipio,

    -- ESTATÍSTICAS LOCAIS
    CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY score_risco_final) OVER (PARTITION BY uf, municipio) AS DECIMAL(18,2)) AS mediana_score_municipio,
    CAST(MAX(score_risco_final) OVER (PARTITION BY uf, municipio) AS DECIMAL(18,2)) AS max_score_municipio,

    -- PERCENTIL
    CAST(PERCENT_RANK() OVER (ORDER BY score_risco_final ASC) * 100 AS DECIMAL(5,2)) AS percentil_risco

INTO temp_CGUSC.fp.matriz_risco_consolidada
FROM ScoreFinal S;

PRINT '   > Tabela temp_CGUSC.fp.matriz_risco_consolidada criada com sucesso.';

-- ============================================================================
-- CRIAÇÃO DE ÍNDICES OTIMIZADOS
-- ============================================================================
PRINT '   > Recriando índices...';

CREATE CLUSTERED INDEX IDX_MatrizFinal_CNPJ 
    ON temp_CGUSC.fp.matriz_risco_consolidada(cnpj);

CREATE NONCLUSTERED INDEX IDX_MatrizFinal_ScoreRiscoFinal 
    ON temp_CGUSC.fp.matriz_risco_consolidada(score_risco_final DESC)
    INCLUDE (razaoSocial, uf, rank_nacional);

CREATE NONCLUSTERED INDEX IDX_MatrizFinal_Municipio 
    ON temp_CGUSC.fp.matriz_risco_consolidada(uf, municipio, score_risco_final DESC)
    INCLUDE (rank_municipio, mediana_score_municipio);

CREATE NONCLUSTERED INDEX IDX_MatrizFinal_Regiao
    ON temp_CGUSC.fp.matriz_risco_consolidada(id_regiao_saude, score_risco_final DESC)
    INCLUDE (no_regiao_saude, rank_regiao_saude, mediana_score_regiao_saude);

    COMMIT TRANSACTION;
    PRINT '>> PROCESSO CONCLUÍDO COM SUCESSO.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT '>> ERRO FATAL: ' + ERROR_MESSAGE() + ' (Linha: ' + CAST(ERROR_LINE() AS VARCHAR(10)) + ')';
    THROW;
END CATCH;
GO

-- ============================================================================
-- VALIDAÇÃO RÁPIDA
-- ============================================================================
SELECT classificacao_risco, COUNT(*) as Qtd, 
       CAST(AVG(score_risco_final) as DECIMAL(10,2)) as Media_Score,
       MIN(score_risco_final) as Min_Score,
       MAX(score_risco_final) as Max_Score
FROM temp_CGUSC.fp.matriz_risco_consolidada
GROUP BY classificacao_risco
ORDER BY Media_Score DESC;
