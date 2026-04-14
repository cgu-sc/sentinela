USE [temp_CGUSC]
GO

-- ==========================================================================================
-- SCRIPT: Matriz de Risco Final - Versão 7.0 (NORMALIZAÇÃO PERCENTIL + PENALIDADE LINEAR)
-- OBJETIVO: Consolidação, Score de Risco Baseado em Percentil Nacional/Regional, Rankings
-- MUDANÇAS V7.0:
--   1. Normalização CUME_DIST: Scores relativos ao benchmark local (0-100).
--   2. Penalidade Linear: +10 pontos por flag crítico (linear e auditável).
--   3. Remoção de V6: Exclusão de multiplicadores exponenciais e tetos de 10x.
-- ==========================================================================================

SET NOCOUNT ON;
PRINT '>> INICIANDO GERAÇÃO DA MATRIZ DE RISCO V7.0 (FINAL - PERCENTIL)...';

-- ============================================================================
-- MATRIZ DE PESOS (0.1 a 5.0) - AJUSTE A IMPORTÂNCIA DE CADA INDICADOR AQUI
-- ============================================================================
DECLARE @PESO_FALECIDOS                      FLOAT = 2.5; 
DECLARE @PESO_AUDITORIA_NAO_COMPROVACAO      FLOAT = 5.0; -- Peso Máximo
DECLARE @PESO_RECORRENCIA_HORARIOS_SISTEMICA FLOAT = 2.0; 
DECLARE @PESO_COMPRA_UNICA                   FLOAT = 1.0; 
DECLARE @PESO_CRMS_IRREGULARES               FLOAT = 0.5; 
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
-- V7: CTE DE SUPORTE - CONTAGEM DE FARMÁCIAS POR REGIÃO (BASE DA NORMALIZAÇÃO HIERÁRQUICA)
-- Decide o nível de normalização: >= 20 farmácias => usa Região; < 20 => usa UF
-- Limiar de 20 garante que o CUME_DIST() tenha granularidade mínima de ~5%
-- ====================================================================================
ContadorRegiao AS (
    SELECT
        id_regiao_saude,
        COUNT(*)                                               AS qtd_farmacias_regiao,
        CASE WHEN COUNT(*) >= 20 THEN 'REGIAO' ELSE 'UF' END AS escopo_benchmark
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
        I01.municipio_media AS avg_falecidos_mun, I01.estado_media AS avg_falecidos_uf, I01.pais_media AS avg_falecidos_br, I01.regiao_saude_media AS avg_falecidos_reg,
        I01.municipio_mediana AS med_falecidos_mun, I01.estado_mediana AS med_falecidos_uf, I01.pais_mediana AS med_falecidos_br, I01.regiao_saude_mediana AS med_falecidos_reg,
        I01.risco_relativo_mun_mediana AS risco_falecidos_mun, I01.risco_relativo_uf_mediana AS risco_falecidos_uf, I01.risco_relativo_br_mediana AS risco_falecidos_br, I01.risco_relativo_reg_mediana AS risco_falecidos_reg,

        I02.percentual_inconsistencia AS pct_clinico,
        I02.municipio_media AS avg_clinico_mun, I02.estado_media AS avg_clinico_uf, I02.pais_media AS avg_clinico_br, I02.regiao_saude_media AS avg_clinico_reg,
        I02.municipio_mediana AS med_clinico_mun, I02.estado_mediana AS med_clinico_uf, I02.pais_mediana AS med_clinico_br, I02.regiao_saude_mediana AS med_clinico_reg,
        I02.risco_relativo_mun_mediana AS risco_clinico_mun, I02.risco_relativo_uf_mediana AS risco_clinico_uf, I02.risco_relativo_br_mediana AS risco_clinico_br, I02.risco_relativo_reg_mediana AS risco_clinico_reg,

        I03.percentual_teto AS pct_teto,
        I03.municipio_media AS avg_teto_mun, I03.estado_media AS avg_teto_uf, I03.pais_media AS avg_teto_br, I03.regiao_saude_media AS avg_teto_reg,
        I03.municipio_mediana AS med_teto_mun, I03.estado_mediana AS med_teto_uf, I03.pais_mediana AS med_teto_br, I03.regiao_saude_mediana AS med_teto_reg,
        I03.risco_relativo_mun_mediana AS risco_teto_mun, I03.risco_relativo_uf_mediana AS risco_teto_uf, I03.risco_relativo_br_mediana AS risco_teto_br, I03.risco_relativo_reg_mediana AS risco_teto_reg,

        I04.percentual_polimedicamento AS pct_polimedicamento,
        I04.municipio_media AS avg_polimedicamento_mun, I04.estado_media AS avg_polimedicamento_uf, I04.pais_media AS avg_polimedicamento_br, I04.regiao_saude_media AS avg_polimedicamento_reg,
        I04.municipio_mediana AS med_polimedicamento_mun, I04.estado_mediana AS med_polimedicamento_uf, I04.pais_mediana AS med_polimedicamento_br, I04.regiao_saude_mediana AS med_polimedicamento_reg,
        I04.risco_relativo_mun_mediana AS risco_polimedicamento_mun, I04.risco_relativo_uf_mediana AS risco_polimedicamento_uf, I04.risco_relativo_br_mediana AS risco_polimedicamento_br, I04.risco_relativo_reg_mediana AS risco_polimedicamento_reg,

        I06.valor_ticket_medio AS val_ticket_medio,
        I06.municipio_media AS avg_ticket_mun, I06.estado_media AS avg_ticket_uf, I06.pais_media AS avg_ticket_br, I06.regiao_saude_media AS avg_ticket_reg,
        I06.municipio_mediana AS med_ticket_mun, I06.estado_mediana AS med_ticket_uf, I06.pais_mediana AS med_ticket_br, I06.regiao_saude_mediana AS med_ticket_reg,
        I06.risco_relativo_mun_mediana AS risco_ticket_mun, I06.risco_relativo_uf_mediana AS risco_ticket_uf, I06.risco_relativo_br_mediana AS risco_ticket_br, I06.risco_relativo_reg_mediana AS risco_ticket_reg,

        I07.receita_por_paciente_mensal AS val_receita_paciente,
        I07.municipio_media AS avg_receita_paciente_mun, I07.estado_media AS avg_receita_paciente_uf, I07.pais_media AS avg_receita_paciente_br, I07.regiao_saude_media AS avg_receita_paciente_reg,
        I07.municipio_mediana AS med_receita_paciente_mun, I07.estado_mediana AS med_receita_paciente_uf, I07.pais_mediana AS med_receita_paciente_br, I07.regiao_saude_mediana AS med_receita_paciente_reg,
        I07.risco_relativo_mun_mediana AS risco_receita_paciente_mun, I07.risco_relativo_uf_mediana AS risco_receita_paciente_uf, I07.risco_relativo_br_mediana AS risco_receita_paciente_br, I07.risco_relativo_reg_mediana AS risco_receita_paciente_reg,

        I08.valor_per_capita_mensal AS val_per_capita,
        I08.municipio_media AS avg_per_capita_mun, I08.estado_media AS avg_per_capita_uf, I08.pais_media AS avg_per_capita_br, I08.regiao_saude_media AS avg_per_capita_reg,
        I08.municipio_mediana AS med_per_capita_mun, I08.estado_mediana AS med_per_capita_uf, I08.pais_mediana AS med_per_capita_br, I08.regiao_saude_mediana AS med_per_capita_reg,
        I08.risco_relativo_mun_mediana AS risco_per_capita_mun, I08.risco_relativo_uf_mediana AS risco_per_capita_uf, I08.risco_relativo_br_mediana AS risco_per_capita_br, I08.risco_relativo_reg_mediana AS risco_per_capita_reg,

        I09.percentual_vendas_consecutivas AS pct_vendas_rapidas,
        I09.municipio_media AS avg_vendas_rapidas_mun, I09.estado_media AS avg_vendas_rapidas_uf, I09.pais_media AS avg_vendas_rapidas_br, I09.regiao_saude_media AS avg_vendas_rapidas_reg,
        I09.municipio_mediana AS med_vendas_rapidas_mun, I09.estado_mediana AS med_vendas_rapidas_uf, I09.pais_mediana AS med_vendas_rapidas_br, I09.regiao_saude_mediana AS med_vendas_rapidas_reg,
        I09.risco_relativo_mun_mediana AS risco_vendas_rapidas_mun, I09.risco_relativo_uf_mediana AS risco_vendas_rapidas_uf, I09.risco_relativo_br_mediana AS risco_vendas_rapidas_br, I09.risco_relativo_reg_mediana AS risco_vendas_rapidas_reg,

        I10.risco_final AS val_volume_atipico,
        I10.municipio_media AS avg_volume_atipico_mun, I10.estado_media AS avg_volume_atipico_uf, I10.pais_media AS avg_volume_atipico_br, I10.regiao_saude_media AS avg_volume_atipico_reg,
        I10.municipio_mediana AS med_volume_atipico_mun, I10.estado_mediana AS med_volume_atipico_uf, I10.pais_mediana AS med_volume_atipico_br, I10.regiao_saude_mediana AS med_volume_atipico_reg,
        I10.risco_relativo_mun_mediana AS risco_volume_atipico_mun, I10.risco_relativo_uf_mediana AS risco_volume_atipico_uf, I10.risco_relativo_br_mediana AS risco_volume_atipico_br, I10.risco_relativo_reg_mediana AS risco_volume_atipico_reg,

        I11.percentual_geografico AS pct_geografico,
        I11.municipio_media AS avg_geografico_mun, I11.estado_media AS avg_geografico_uf, I11.pais_media AS avg_geografico_br, I11.regiao_saude_media AS avg_geografico_reg,
        I11.municipio_mediana AS med_geografico_mun, I11.estado_mediana AS med_geografico_uf, I11.pais_mediana AS med_geografico_br, I11.regiao_saude_mediana AS med_geografico_reg,
        I11.risco_relativo_mun_mediana AS risco_geografico_mun, I11.risco_relativo_uf_mediana AS risco_geografico_uf, I11.risco_relativo_br_mediana AS risco_geografico_br, I11.risco_relativo_reg_mediana AS risco_geografico_reg,

        I12.percentual_alto_custo AS pct_alto_custo,
        I12.municipio_media AS avg_alto_custo_mun, I12.estado_media AS avg_alto_custo_uf, I12.pais_media AS avg_alto_custo_br, I12.regiao_saude_media AS avg_alto_custo_reg,
        I12.municipio_mediana AS med_alto_custo_mun, I12.estado_mediana AS med_alto_custo_uf, I12.pais_mediana AS med_alto_custo_br, I12.regiao_saude_mediana AS med_alto_custo_reg,
        I12.risco_relativo_mun_mediana AS risco_alto_custo_mun, I12.risco_relativo_uf_mediana AS risco_alto_custo_uf, I12.risco_relativo_br_mediana AS risco_alto_custo_br, I12.risco_relativo_reg_mediana AS risco_alto_custo_reg,

        I13.media_concentracao AS pct_pico,
        I13.municipio_media AS avg_pico_mun, I13.estado_media AS avg_pico_uf, I13.pais_media AS avg_pico_br, I13.regiao_saude_media AS avg_pico_reg,
        I13.municipio_mediana AS med_pico_mun, I13.estado_mediana AS med_pico_uf, I13.pais_mediana AS med_pico_br, I13.regiao_saude_mediana AS med_pico_reg,
        I13.risco_relativo_mun_mediana AS risco_pico_mun, I13.risco_relativo_uf_mediana AS risco_pico_uf, I13.risco_relativo_br_mediana AS risco_pico_br, I13.risco_relativo_reg_mediana AS risco_pico_reg,

        I14.pct_compra_unica AS pct_compra_unica,
        I14.municipio_media AS avg_compra_unica_mun, I14.estado_media AS avg_compra_unica_uf, I14.pais_media AS avg_compra_unica_br, I14.regiao_saude_media AS avg_compra_unica_reg,
        I14.municipio_mediana AS med_compra_unica_mun, I14.estado_mediana AS med_compra_unica_uf, I14.pais_mediana AS med_compra_unica_br, I14.regiao_saude_mediana AS med_compra_unica_reg,
        I14.risco_relativo_mun_mediana AS risco_compra_unica_mun, I14.risco_relativo_uf_mediana AS risco_compra_unica_uf, I14.risco_relativo_br_mediana AS risco_compra_unica_br, I14.risco_relativo_reg_mediana AS risco_compra_unica_reg,

        CAST(I15.indice_hhi AS DECIMAL(18,2)) AS val_hhi_crm,
        CAST(I15.media_hhi_mun AS DECIMAL(18,2)) AS avg_hhi_crm_mun,
        CAST(I15.estado_mediana AS DECIMAL(18,2)) AS avg_hhi_crm_uf,
        CAST(I15.pais_mediana AS DECIMAL(18,2)) AS avg_hhi_crm_br,
        CAST(I15.regiao_saude_mediana AS DECIMAL(18,2)) AS avg_hhi_crm_reg,
        I15.risco_relativo_reg_mediana AS risco_crm_reg,
        I15.risco_relativo_uf_mediana AS risco_crm_uf,
        I15.risco_relativo_br_mediana AS risco_crm_br,
        NULL AS risco_crm_mun,

        I16.percentual_exclusividade AS pct_exclusividade_crm,
        I16.municipio_media AS avg_exclusividade_crm_mun, I16.estado_media AS avg_exclusividade_crm_uf, I16.pais_media AS avg_exclusividade_crm_br, I16.regiao_saude_media AS avg_exclusividade_crm_reg,
        I16.municipio_mediana AS med_exclusividade_crm_mun, I16.estado_mediana AS med_exclusividade_crm_uf, I16.pais_mediana AS med_exclusividade_crm_br, I16.regiao_saude_mediana AS med_exclusividade_crm_reg,
        I16.risco_relativo_mun_mediana AS risco_exclusividade_crm_mun, I16.risco_relativo_uf_mediana AS risco_exclusividade_crm_uf, I16.risco_relativo_br_mediana AS risco_exclusividade_crm_br, I16.risco_relativo_reg_mediana AS risco_exclusividade_crm_reg,

        I17.pct_risco_irregularidade AS pct_crms_irregulares,
        I17.municipio_media AS avg_crms_irregulares_mun, I17.estado_media AS avg_crms_irregulares_uf, I17.pais_media AS avg_crms_irregulares_br, I17.regiao_saude_media AS avg_crms_irregulares_reg,
        I17.municipio_mediana AS med_crms_irregulares_mun, I17.estado_mediana AS med_crms_irregulares_uf, I17.pais_mediana AS med_crms_irregulares_br, I17.regiao_saude_mediana AS med_crms_irregulares_reg,
        I17.risco_relativo_mun_mediana AS risco_crms_irregulares_mun, I17.risco_relativo_uf_mediana AS risco_crms_irregulares_uf, I17.risco_relativo_br_mediana AS risco_crms_irregulares_br, I17.risco_relativo_reg_mediana AS risco_crms_irregulares_reg,

        I19.percentual_recorrencia_sistemica AS pct_recorrencia_sistemica,
        I19.municipio_media AS avg_recorrencia_sistemica_mun, I19.estado_media AS avg_recorrencia_sistemica_uf, I19.pais_media AS avg_recorrencia_sistemica_br, I19.regiao_saude_media AS avg_recorrencia_sistemica_reg,
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
    LEFT JOIN temp_CGUSC.fp.indicador_crm_detalhado I15 ON I15.nu_cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicador_exclusividade_crm_detalhado I16 ON I16.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicador_crms_irregulares_detalhado I17 ON I17.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicador_recorrencia_sistemica_detalhado I19 ON I19.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicador_auditado_detalhado IA ON IA.cnpj = F.cnpj
),

-- 3. CTE 2: CÁLCULO DE FLAGS CRÍTICOS (BASEADO EM LIMITES ESTATÍSTICOS BRUTOS)
-- Mantemos os flags para fins de visualização no Dashboard e penalidade do score.
CalculoFlagsV7 AS (
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

-- 4. CTE 3: CONSOLIDAÇÃO DE ALERTA (COUNT E LISTA)
ConsolidacaoFlags AS (
    SELECT
        *,
        (flag_falecidos_critico + flag_clinico_critico + flag_teto_critico + flag_polimedicamento_critico + 
         flag_ticket_critico + flag_receita_paciente_critico + flag_per_capita_critico + flag_vendas_rapidas_critico + 
         flag_volume_atipico_critico + flag_geografico_critico + flag_alto_custo_critico + flag_pico_critico + 
         flag_compra_unica_critico + flag_crm_critico + flag_exclusividade_crm_critico + flag_crms_irregulares_critico + 
         flag_recorrencia_sistemica_critico + flag_auditado_critico) AS qtd_indicadores_criticos,

        SUBSTRING(
            (CASE WHEN flag_falecidos_critico=1 THEN ', Falecidos' ELSE '' END) +
            (CASE WHEN flag_clinico_critico=1 THEN ', Clinico' ELSE '' END) +
            (CASE WHEN flag_teto_critico=1 THEN ', Estouro Teto' ELSE '' END) +
            (CASE WHEN flag_polimedicamento_critico=1 THEN ', Polimedicamento' ELSE '' END) +
            (CASE WHEN flag_ticket_critico=1 THEN ', Ticket Medio' ELSE '' END) +
            (CASE WHEN flag_receita_paciente_critico=1 THEN ', Receita Paciente' ELSE '' END) +
            (CASE WHEN flag_per_capita_critico=1 THEN ', Valor Per Capita' ELSE '' END) +
            (CASE WHEN flag_vendas_rapidas_critico=1 THEN ', Vendas Rapidas' ELSE '' END) +
            (CASE WHEN flag_volume_atipico_critico=1 THEN ', Volume Atipico' ELSE '' END) +
            (CASE WHEN flag_geografico_critico=1 THEN ', Distancia Geografica' ELSE '' END) +
            (CASE WHEN flag_alto_custo_critico=1 THEN ', Alto Custo' ELSE '' END) +
            (CASE WHEN flag_pico_critico=1 THEN ', Concentracao Pico' ELSE '' END) +
            (CASE WHEN flag_compra_unica_critico=1 THEN ', Compra Unica' ELSE '' END) +
            (CASE WHEN flag_crm_critico=1 THEN ', Concentracao CRM' ELSE '' END) +
            (CASE WHEN flag_exclusividade_crm_critico=1 THEN ', Exclusividade CRM' ELSE '' END) +
            (CASE WHEN flag_crms_irregulares_critico=1 THEN ', CRMs Irregulares' ELSE '' END) +
            (CASE WHEN flag_recorrencia_sistemica_critico=1 THEN ', Recorrencia Sistemica' ELSE '' END) +
            (CASE WHEN flag_auditado_critico=1 THEN ', Auditoria Financeira' ELSE '' END)
        , 3, 500) AS indicadores_criticos_lista
    FROM CalculoFlagsV7
),

-- ====================================================================================
-- V7 - CTE 2a: BASE DE NORMALIZAÇÃO
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
        CAST(CUME_DIST() OVER (PARTITION BY IP.id_regiao_saude ORDER BY ISNULL(IP.risco_falecidos_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_reg_falecidos,
        CAST(CUME_DIST() OVER (PARTITION BY IP.uf             ORDER BY ISNULL(IP.risco_falecidos_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_uf_falecidos,

        -- 2. CLÍNICO
        CAST(CUME_DIST() OVER (PARTITION BY IP.id_regiao_saude ORDER BY ISNULL(IP.risco_clinico_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_reg_clinico,
        CAST(CUME_DIST() OVER (PARTITION BY IP.uf             ORDER BY ISNULL(IP.risco_clinico_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_uf_clinico,

        -- 3. TETO
        CAST(CUME_DIST() OVER (PARTITION BY IP.id_regiao_saude ORDER BY ISNULL(IP.risco_teto_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_reg_teto,
        CAST(CUME_DIST() OVER (PARTITION BY IP.uf             ORDER BY ISNULL(IP.risco_teto_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_uf_teto,

        -- 4. POLIMEDICAMENTO
        CAST(CUME_DIST() OVER (PARTITION BY IP.id_regiao_saude ORDER BY ISNULL(IP.risco_polimedicamento_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_reg_polimedicamento,
        CAST(CUME_DIST() OVER (PARTITION BY IP.uf             ORDER BY ISNULL(IP.risco_polimedicamento_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_uf_polimedicamento,

        -- 5. TICKET MÉDIO
        CAST(CUME_DIST() OVER (PARTITION BY IP.id_regiao_saude ORDER BY ISNULL(IP.risco_ticket_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_reg_ticket,
        CAST(CUME_DIST() OVER (PARTITION BY IP.uf             ORDER BY ISNULL(IP.risco_ticket_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_uf_ticket,

        -- 6. RECEITA POR PACIENTE
        CAST(CUME_DIST() OVER (PARTITION BY IP.id_regiao_saude ORDER BY ISNULL(IP.risco_receita_paciente_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_reg_receita_paciente,
        CAST(CUME_DIST() OVER (PARTITION BY IP.uf             ORDER BY ISNULL(IP.risco_receita_paciente_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_uf_receita_paciente,

        -- 7. PER CAPITA
        CAST(CUME_DIST() OVER (PARTITION BY IP.id_regiao_saude ORDER BY ISNULL(IP.risco_per_capita_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_reg_per_capita,
        CAST(CUME_DIST() OVER (PARTITION BY IP.uf             ORDER BY ISNULL(IP.risco_per_capita_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_uf_per_capita,

        -- 8. VENDAS RÁPIDAS
        CAST(CUME_DIST() OVER (PARTITION BY IP.id_regiao_saude ORDER BY ISNULL(IP.risco_vendas_rapidas_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_reg_vendas_rapidas,
        CAST(CUME_DIST() OVER (PARTITION BY IP.uf             ORDER BY ISNULL(IP.risco_vendas_rapidas_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_uf_vendas_rapidas,

        -- 9. VOLUME ATÍPICO
        CAST(CUME_DIST() OVER (PARTITION BY IP.id_regiao_saude ORDER BY ISNULL(IP.risco_volume_atipico_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_reg_volume_atipico,
        CAST(CUME_DIST() OVER (PARTITION BY IP.uf             ORDER BY ISNULL(IP.risco_volume_atipico_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_uf_volume_atipico,

        -- 10. GEOGRÁFICO
        CAST(CUME_DIST() OVER (PARTITION BY IP.id_regiao_saude ORDER BY ISNULL(IP.risco_geografico_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_reg_geografico,
        CAST(CUME_DIST() OVER (PARTITION BY IP.uf             ORDER BY ISNULL(IP.risco_geografico_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_uf_geografico,

        -- 11. ALTO CUSTO
        CAST(CUME_DIST() OVER (PARTITION BY IP.id_regiao_saude ORDER BY ISNULL(IP.risco_alto_custo_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_reg_alto_custo,
        CAST(CUME_DIST() OVER (PARTITION BY IP.uf             ORDER BY ISNULL(IP.risco_alto_custo_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_uf_alto_custo,

        -- 12. PICO
        CAST(CUME_DIST() OVER (PARTITION BY IP.id_regiao_saude ORDER BY ISNULL(IP.risco_pico_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_reg_pico,
        CAST(CUME_DIST() OVER (PARTITION BY IP.uf             ORDER BY ISNULL(IP.risco_pico_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_uf_pico,

        -- 13. COMPRA ÚNICA
        CAST(CUME_DIST() OVER (PARTITION BY IP.id_regiao_saude ORDER BY ISNULL(IP.risco_compra_unica_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_reg_compra_unica,
        CAST(CUME_DIST() OVER (PARTITION BY IP.uf             ORDER BY ISNULL(IP.risco_compra_unica_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_uf_compra_unica,

        -- 14. CRM HHI
        CAST(CUME_DIST() OVER (PARTITION BY IP.id_regiao_saude ORDER BY ISNULL(IP.risco_crm_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_reg_crm,
        CAST(CUME_DIST() OVER (PARTITION BY IP.uf             ORDER BY ISNULL(IP.risco_crm_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_uf_crm,

        -- 15. EXCLUSIVIDADE CRM
        CAST(CUME_DIST() OVER (PARTITION BY IP.id_regiao_saude ORDER BY ISNULL(IP.risco_exclusividade_crm_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_reg_exclusividade_crm,
        CAST(CUME_DIST() OVER (PARTITION BY IP.uf             ORDER BY ISNULL(IP.risco_exclusividade_crm_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_uf_exclusividade_crm,

        -- 16. CRMs IRREGULARES
        CAST(CUME_DIST() OVER (PARTITION BY IP.id_regiao_saude ORDER BY ISNULL(IP.risco_crms_irregulares_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_reg_crms_irregulares,
        CAST(CUME_DIST() OVER (PARTITION BY IP.uf             ORDER BY ISNULL(IP.risco_crms_irregulares_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_uf_crms_irregulares,

        -- 17. RECORRÊNCIA SISTÊMICA
        CAST(CUME_DIST() OVER (PARTITION BY IP.id_regiao_saude ORDER BY ISNULL(IP.risco_recorrencia_sistemica_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_reg_recorrencia_sistemica,
        CAST(CUME_DIST() OVER (PARTITION BY IP.uf             ORDER BY ISNULL(IP.risco_recorrencia_sistemica_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_uf_recorrencia_sistemica,

        -- 18. AUDITORIA
        CAST(CUME_DIST() OVER (PARTITION BY IP.id_regiao_saude ORDER BY ISNULL(IP.risco_auditado_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_reg_auditado,
        CAST(CUME_DIST() OVER (PARTITION BY IP.uf             ORDER BY ISNULL(IP.risco_auditado_reg, 0) ASC) * 100 AS DECIMAL(5,2)) AS pct_uf_auditado

    FROM IndicadoresPresenca IP
    LEFT JOIN ContadorRegiao CR ON CR.id_regiao_saude = IP.id_regiao_saude
),

-- ====================================================================================
-- V7 - CTE 2b: NORMALIZAÇÃO FINAL (ESCOLHA DO ESCOPO CORRETO)
-- Seleciona o percentil de Região ou UF conforme o escopo_benchmark.
-- Farmácias sem id_regiao_saude sempre usam UF.
-- ====================================================================================
NormalizacaoV7 AS (
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

-- ====================================================================================
-- V7 - CTE 3: SCORE FINAL PONDERADO V7
-- Fórmula: média ponderada dos percentis normalizados (0-100) + penalidade linear de flags
--
-- PESOS: usa as variáveis @PESO_ declaradas no topo — qualquer ajuste aqui aplica ao V7.
-- PENALIDADE: cada flag_critico adiciona +10 pontos (linear, auditável, defensável).
-- RESULTADO: score_v7 em escala de 0 a ~100+ (pode ultrapassar 100 com penalidade).
-- ====================================================================================
ScoreV7 AS (
    SELECT
        CF.*,
        NV.escopo_benchmark,

        -- SCORE_V7_BASE: Média ponderada pura dos percentis (sem penalidade)
        -- Cada score_pct_X já é 0-100. A média ponderada fica em 0-100.
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
                (ISNULL(NV.score_pct_recorrencia_sistemica,0) * @PESO_RECORRENCIA_HORARIOS_SISTEMICA) +
                (ISNULL(NV.score_pct_auditado,             0) * @PESO_AUDITORIA_NAO_COMPROVACAO)
            )
            /
            -- Divide apenas pelos pesos dos indicadores com dado (tem_X = 1)
            NULLIF(
                (CF.tem_falecidos            * @PESO_FALECIDOS) +
                (CF.tem_clinico              * @PESO_INCONSISTENCIA_CLINICA) +
                (CF.tem_teto                 * @PESO_ESTOURO_TETO) +
                (CF.tem_polimedicamento      * @PESO_POLIMEDICAMENTO) +
                (CF.tem_ticket               * @PESO_TICKET_MEDIO) +
                (CF.tem_receita_paciente     * @PESO_RECEITA_POR_PACIENTE) +
                (CF.tem_per_capita           * @PESO_VALOR_PER_CAPITA) +
                (CF.tem_vendas_rapidas       * @PESO_VENDAS_CONSECUTIVAS_RAPIDAS) +
                (CF.tem_volume_atipico       * @PESO_VOLUME_ATIPICO) +
                (CF.tem_geografico           * @PESO_DISTANCIA_GEOGRAFICA) +
                (CF.tem_alto_custo           * @PESO_ALTO_CUSTO) +
                (CF.tem_pico                 * @PESO_CONCENTRACAO_PICO) +
                (CF.tem_compra_unica         * @PESO_COMPRA_UNICA) +
                (CF.tem_crm                  * @PESO_CONCENTRACAO_CRM_HHI) +
                (CF.tem_exclusividade_crm    * @PESO_EXCLUSIVIDADE_CRM) +
                (CF.tem_crms_irregulares     * @PESO_CRMS_IRREGULARES) +
                (CF.tem_recorrencia_sistemica* @PESO_RECORRENCIA_HORARIOS_SISTEMICA) +
                (CF.tem_auditado             * @PESO_AUDITORIA_NAO_COMPROVACAO)
            , 0)
        AS DECIMAL(7,2)) AS score_v7_base,

        -- SCORE FINAL (V7 consumindo nome legado)
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
                (ISNULL(NV.score_pct_recorrencia_sistemica,0) * @PESO_RECORRENCIA_HORARIOS_SISTEMICA) +
                (ISNULL(NV.score_pct_auditado,             0) * @PESO_AUDITORIA_NAO_COMPROVACAO)
            )
            /
            NULLIF(
                (CF.tem_falecidos            * @PESO_FALECIDOS) +
                (CF.tem_clinico              * @PESO_INCONSISTENCIA_CLINICA) +
                (CF.tem_teto                 * @PESO_ESTOURO_TETO) +
                (CF.tem_polimedicamento      * @PESO_POLIMEDICAMENTO) +
                (CF.tem_ticket               * @PESO_TICKET_MEDIO) +
                (CF.tem_receita_paciente     * @PESO_RECEITA_POR_PACIENTE) +
                (CF.tem_per_capita           * @PESO_VALOR_PER_CAPITA) +
                (CF.tem_vendas_rapidas       * @PESO_VENDAS_CONSECUTIVAS_RAPIDAS) +
                (CF.tem_volume_atipico       * @PESO_VOLUME_ATIPICO) +
                (CF.tem_geografico           * @PESO_DISTANCIA_GEOGRAFICA) +
                (CF.tem_alto_custo           * @PESO_ALTO_CUSTO) +
                (CF.tem_pico                 * @PESO_CONCENTRACAO_PICO) +
                (CF.tem_compra_unica         * @PESO_COMPRA_UNICA) +
                (CF.tem_crm                  * @PESO_CONCENTRACAO_CRM_HHI) +
                (CF.tem_exclusividade_crm    * @PESO_EXCLUSIVIDADE_CRM) +
                (CF.tem_crms_irregulares     * @PESO_CRMS_IRREGULARES) +
                (CF.tem_recorrencia_sistemica* @PESO_RECORRENCIA_HORARIOS_SISTEMICA) +
                (CF.tem_auditado             * @PESO_AUDITORIA_NAO_COMPROVACAO)
            , 0)
            + (CF.qtd_indicadores_criticos * 10.0)
        AS DECIMAL(7,2)) AS score_risco_final,

        -- CLASSIFICAÇÃO (Nome legado)
        CASE
            WHEN CF.qtd_indicadores_criticos >= 3 THEN 'RISCO CRITICO'
            WHEN CF.qtd_indicadores_criticos >= 2 THEN 'RISCO ALTO'
            WHEN (
                (ISNULL(NV.score_pct_falecidos,0)*@PESO_FALECIDOS + ISNULL(NV.score_pct_clinico,0)*@PESO_INCONSISTENCIA_CLINICA +
                 ISNULL(NV.score_pct_teto,0)*@PESO_ESTOURO_TETO + ISNULL(NV.score_pct_polimedicamento,0)*@PESO_POLIMEDICAMENTO +
                 ISNULL(NV.score_pct_ticket,0)*@PESO_TICKET_MEDIO + ISNULL(NV.score_pct_receita_paciente,0)*@PESO_RECEITA_POR_PACIENTE +
                 ISNULL(NV.score_pct_per_capita,0)*@PESO_VALOR_PER_CAPITA + ISNULL(NV.score_pct_vendas_rapidas,0)*@PESO_VENDAS_CONSECUTIVAS_RAPIDAS +
                 ISNULL(NV.score_pct_volume_atipico,0)*@PESO_VOLUME_ATIPICO + ISNULL(NV.score_pct_geografico,0)*@PESO_DISTANCIA_GEOGRAFICA +
                 ISNULL(NV.score_pct_alto_custo,0)*@PESO_ALTO_CUSTO + ISNULL(NV.score_pct_pico,0)*@PESO_CONCENTRACAO_PICO +
                 ISNULL(NV.score_pct_compra_unica,0)*@PESO_COMPRA_UNICA + ISNULL(NV.score_pct_crm,0)*@PESO_CONCENTRACAO_CRM_HHI +
                 ISNULL(NV.score_pct_exclusividade_crm,0)*@PESO_EXCLUSIVIDADE_CRM + ISNULL(NV.score_pct_crms_irregulares,0)*@PESO_CRMS_IRREGULARES +
                 ISNULL(NV.score_pct_recorrencia_sistemica,0)*@PESO_RECORRENCIA_HORARIOS_SISTEMICA + ISNULL(NV.score_pct_auditado,0)*@PESO_AUDITORIA_NAO_COMPROVACAO)
                / NULLIF(
                    (CF.tem_falecidos*@PESO_FALECIDOS)+(CF.tem_clinico*@PESO_INCONSISTENCIA_CLINICA)+(CF.tem_teto*@PESO_ESTOURO_TETO)+
                    (CF.tem_polimedicamento*@PESO_POLIMEDICAMENTO)+(CF.tem_ticket*@PESO_TICKET_MEDIO)+(CF.tem_receita_paciente*@PESO_RECEITA_POR_PACIENTE)+
                    (CF.tem_per_capita*@PESO_VALOR_PER_CAPITA)+(CF.tem_vendas_rapidas*@PESO_VENDAS_CONSECUTIVAS_RAPIDAS)+(CF.tem_volume_atipico*@PESO_VOLUME_ATIPICO)+
                    (CF.tem_geografico*@PESO_DISTANCIA_GEOGRAFICA)+(CF.tem_alto_custo*@PESO_ALTO_CUSTO)+(CF.tem_pico*@PESO_CONCENTRACAO_PICO)+
                    (CF.tem_compra_unica*@PESO_COMPRA_UNICA)+(CF.tem_crm*@PESO_CONCENTRACAO_CRM_HHI)+(CF.tem_exclusividade_crm*@PESO_EXCLUSIVIDADE_CRM)+
                    (CF.tem_crms_irregulares*@PESO_CRMS_IRREGULARES)+(CF.tem_recorrencia_sistemica*@PESO_RECORRENCIA_HORARIOS_SISTEMICA)+(CF.tem_auditado*@PESO_AUDITORIA_NAO_COMPROVACAO)
                , 0)
            ) >= 75 THEN 'RISCO ALTO'
            WHEN CF.qtd_indicadores_criticos >= 1 THEN 'RISCO MEDIO'
            WHEN (
                (ISNULL(NV.score_pct_falecidos,0)*@PESO_FALECIDOS + ISNULL(NV.score_pct_clinico,0)*@PESO_INCONSISTENCIA_CLINICA +
                 ISNULL(NV.score_pct_teto,0)*@PESO_ESTOURO_TETO + ISNULL(NV.score_pct_polimedicamento,0)*@PESO_POLIMEDICAMENTO +
                 ISNULL(NV.score_pct_ticket,0)*@PESO_TICKET_MEDIO + ISNULL(NV.score_pct_receita_paciente,0)*@PESO_RECEITA_POR_PACIENTE +
                 ISNULL(NV.score_pct_per_capita,0)*@PESO_VALOR_PER_CAPITA + ISNULL(NV.score_pct_vendas_rapidas,0)*@PESO_VENDAS_CONSECUTIVAS_RAPIDAS +
                 ISNULL(NV.score_pct_volume_atipico,0)*@PESO_VOLUME_ATIPICO + ISNULL(NV.score_pct_geografico,0)*@PESO_DISTANCIA_GEOGRAFICA +
                 ISNULL(NV.score_pct_alto_custo,0)*@PESO_ALTO_CUSTO + ISNULL(NV.score_pct_pico,0)*@PESO_CONCENTRACAO_PICO +
                 ISNULL(NV.score_pct_compra_unica,0)*@PESO_COMPRA_UNICA + ISNULL(NV.score_pct_crm,0)*@PESO_CONCENTRACAO_CRM_HHI +
                 ISNULL(NV.score_pct_exclusividade_crm,0)*@PESO_EXCLUSIVIDADE_CRM + ISNULL(NV.score_pct_crms_irregulares,0)*@PESO_CRMS_IRREGULARES +
                 ISNULL(NV.score_pct_recorrencia_sistemica,0)*@PESO_RECORRENCIA_HORARIOS_SISTEMICA + ISNULL(NV.score_pct_auditado,0)*@PESO_AUDITORIA_NAO_COMPROVACAO)
                / NULLIF(
                    (CF.tem_falecidos*@PESO_FALECIDOS)+(CF.tem_clinico*@PESO_INCONSISTENCIA_CLINICA)+(CF.tem_teto*@PESO_ESTOURO_TETO)+
                    (CF.tem_polimedicamento*@PESO_POLIMEDICAMENTO)+(CF.tem_ticket*@PESO_TICKET_MEDIO)+(CF.tem_receita_paciente*@PESO_RECEITA_POR_PACIENTE)+
                    (CF.tem_per_capita*@PESO_VALOR_PER_CAPITA)+(CF.tem_vendas_rapidas*@PESO_VENDAS_CONSECUTIVAS_RAPIDAS)+(CF.tem_volume_atipico*@PESO_VOLUME_ATIPICO)+
                    (CF.tem_geografico*@PESO_DISTANCIA_GEOGRAFICA)+(CF.tem_alto_custo*@PESO_ALTO_CUSTO)+(CF.tem_pico*@PESO_CONCENTRACAO_PICO)+
                    (CF.tem_compra_unica*@PESO_COMPRA_UNICA)+(CF.tem_crm*@PESO_CONCENTRACAO_CRM_HHI)+(CF.tem_exclusividade_crm*@PESO_EXCLUSIVIDADE_CRM)+
                    (CF.tem_crms_irregulares*@PESO_CRMS_IRREGULARES)+(CF.tem_recorrencia_sistemica*@PESO_RECORRENCIA_HORARIOS_SISTEMICA)+(CF.tem_auditado*@PESO_AUDITORIA_NAO_COMPROVACAO)
                , 0)
            ) >= 50 THEN 'RISCO MEDIO'
            WHEN (
                (ISNULL(NV.score_pct_falecidos,0)*@PESO_FALECIDOS + ISNULL(NV.score_pct_clinico,0)*@PESO_INCONSISTENCIA_CLINICA +
                 ISNULL(NV.score_pct_teto,0)*@PESO_ESTOURO_TETO + ISNULL(NV.score_pct_polimedicamento,0)*@PESO_POLIMEDICAMENTO +
                 ISNULL(NV.score_pct_ticket,0)*@PESO_TICKET_MEDIO + ISNULL(NV.score_pct_receita_paciente,0)*@PESO_RECEITA_POR_PACIENTE +
                 ISNULL(NV.score_pct_per_capita,0)*@PESO_VALOR_PER_CAPITA + ISNULL(NV.score_pct_vendas_rapidas,0)*@PESO_VENDAS_CONSECUTIVAS_RAPIDAS +
                 ISNULL(NV.score_pct_volume_atipico,0)*@PESO_VOLUME_ATIPICO + ISNULL(NV.score_pct_geografico,0)*@PESO_DISTANCIA_GEOGRAFICA +
                 ISNULL(NV.score_pct_alto_custo,0)*@PESO_ALTO_CUSTO + ISNULL(NV.score_pct_pico,0)*@PESO_CONCENTRACAO_PICO +
                 ISNULL(NV.score_pct_compra_unica,0)*@PESO_COMPRA_UNICA + ISNULL(NV.score_pct_crm,0)*@PESO_CONCENTRACAO_CRM_HHI +
                 ISNULL(NV.score_pct_exclusividade_crm,0)*@PESO_EXCLUSIVIDADE_CRM + ISNULL(NV.score_pct_crms_irregulares,0)*@PESO_CRMS_IRREGULARES +
                 ISNULL(NV.score_pct_recorrencia_sistemica,0)*@PESO_RECORRENCIA_HORARIOS_SISTEMICA + ISNULL(NV.score_pct_auditado,0)*@PESO_AUDITORIA_NAO_COMPROVACAO)
                / NULLIF(
                    (CF.tem_falecidos*@PESO_FALECIDOS)+(CF.tem_clinico*@PESO_INCONSISTENCIA_CLINICA)+(CF.tem_teto*@PESO_ESTOURO_TETO)+
                    (CF.tem_polimedicamento*@PESO_POLIMEDICAMENTO)+(CF.tem_ticket*@PESO_TICKET_MEDIO)+(CF.tem_receita_paciente*@PESO_RECEITA_POR_PACIENTE)+
                    (CF.tem_per_capita*@PESO_VALOR_PER_CAPITA)+(CF.tem_vendas_rapidas*@PESO_VENDAS_CONSECUTIVAS_RAPIDAS)+(CF.tem_volume_atipico*@PESO_VOLUME_ATIPICO)+
                    (CF.tem_geografico*@PESO_DISTANCIA_GEOGRAFICA)+(CF.tem_alto_custo*@PESO_ALTO_CUSTO)+(CF.tem_pico*@PESO_CONCENTRACAO_PICO)+
                    (CF.tem_compra_unica*@PESO_COMPRA_UNICA)+(CF.tem_crm*@PESO_CONCENTRACAO_CRM_HHI)+(CF.tem_exclusividade_crm*@PESO_EXCLUSIVIDADE_CRM)+
                    (CF.tem_crms_irregulares*@PESO_CRMS_IRREGULARES)+(CF.tem_recorrencia_sistemica*@PESO_RECORRENCIA_HORARIOS_SISTEMICA)+(CF.tem_auditado*@PESO_AUDITORIA_NAO_COMPROVACAO)
                , 0)
            ) >= 25 THEN 'RISCO BAIXO'
            ELSE 'RISCO MINIMO'
        END AS classificacao_risco

    FROM ConsolidacaoFlags CF
    LEFT JOIN NormalizacaoV7 NV ON NV.cnpj = CF.cnpj
)

-- 7. SELEÇÃO FINAL E CRIAÇÃO DA TABELA FÍSICA
SELECT 
    S.*,
    
    -- RANKINGS (Mantendo nomes de colunas originais mas usando lógica V7)
    RANK() OVER (ORDER BY score_risco_final DESC) AS rank_nacional,
    COUNT(*) OVER () AS total_nacional,
    RANK() OVER (PARTITION BY uf ORDER BY score_risco_final DESC) AS rank_uf,
    COUNT(*) OVER (PARTITION BY uf) AS total_uf,

    -- REGIAO DE SAUDE
    RANK() OVER (PARTITION BY id_regiao_saude ORDER BY score_risco_final DESC) AS rank_regiao_saude,
    COUNT(*) OVER (PARTITION BY id_regiao_saude) AS total_regiao_saude,
    CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY score_risco_final) OVER (PARTITION BY id_regiao_saude) AS DECIMAL(18,2)) AS avg_score_regiao_saude,
    CAST(MAX(score_risco_final) OVER (PARTITION BY id_regiao_saude) AS DECIMAL(18,2)) AS max_score_regiao_saude,

    -- INTELIGÊNCIA MUNICIPAL
    RANK() OVER (PARTITION BY uf, municipio ORDER BY score_risco_final DESC) AS rank_municipio,
    COUNT(*) OVER (PARTITION BY uf, municipio) AS total_municipio,

    -- ESTATÍSTICAS LOCAIS
    CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY score_risco_final) OVER (PARTITION BY uf, municipio) AS DECIMAL(18,2)) AS avg_score_municipio,
    CAST(MAX(score_risco_final) OVER (PARTITION BY uf, municipio) AS DECIMAL(18,2)) AS max_score_municipio,

    -- PERCENTIL
    CAST(CUME_DIST() OVER (ORDER BY score_risco_final ASC) * 100 AS DECIMAL(5,2)) AS percentil_risco

INTO temp_CGUSC.fp.matriz_risco_consolidada
FROM ScoreV7 S;

PRINT '   > Tabela temp_CGUSC.fp.matriz_risco_consolidada (V7 - FINAL) criada com sucesso.';

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
    INCLUDE (rank_municipio, avg_score_municipio);

CREATE NONCLUSTERED INDEX IDX_MatrizFinal_Regiao
    ON temp_CGUSC.fp.matriz_risco_consolidada(id_regiao_saude, score_risco_final DESC)
    INCLUDE (no_regiao_saude, rank_regiao_saude, avg_score_regiao_saude);

PRINT '>> PROCESSO CONCLUÍDO COM SUCESSO.';
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
