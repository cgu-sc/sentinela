USE [temp_CGUSC]
GO

-- ==========================================================================================
-- SCRIPT: Matriz de Risco Final - Versão 5.5 (VISUAL REAL / CÁLCULO CAPADO)
-- OBJETIVO: Consolidação, Score de Risco, Rankings e Classificação
-- MUDANÇAS:
--   1. Visualização: Mostra o Risco Relativo REAL (ex: 34x) na tabela final.
--   2. Cálculo: Aplica TETO DE 10x internamente apenas para calcular o Score e Multiplicadores.
--   3. Mantém a lógica de "Sem Dados" (NULL) nas colunas originais.
-- ==========================================================================================

SET NOCOUNT ON;
PRINT '>> INICIANDO GERAÇÃO DA MATRIZ DE RISCO V5.5...';

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
        CASE WHEN I05.cnpj IS NOT NULL THEN 1 ELSE 0 END AS tem_media_itens,
        CASE WHEN I06.cnpj IS NOT NULL THEN 1 ELSE 0 END AS tem_ticket,
        CASE WHEN I07.cnpj IS NOT NULL THEN 1 ELSE 0 END AS tem_receita_paciente,
        CASE WHEN I08.cnpj IS NOT NULL THEN 1 ELSE 0 END AS tem_per_capita,
        CASE WHEN I09.cnpj IS NOT NULL THEN 1 ELSE 0 END AS tem_vendas_rapidas,
        CASE WHEN I10.cnpj IS NOT NULL THEN 1 ELSE 0 END AS tem_volume_atipico,
        CASE WHEN I11.cnpj IS NOT NULL THEN 1 ELSE 0 END AS tem_geografico,
        CASE WHEN I12.cnpj IS NOT NULL THEN 1 ELSE 0 END AS tem_alto_custo,
        CASE WHEN I13.cnpj IS NOT NULL THEN 1 ELSE 0 END AS tem_pico,
        CASE WHEN I14.cnpj IS NOT NULL THEN 1 ELSE 0 END AS tem_fantasma,
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

        I05.media_itens_autorizacao AS val_media_itens,
        I05.municipio_media AS avg_media_itens_mun, I05.estado_media AS avg_media_itens_uf, I05.pais_media AS avg_media_itens_br, I05.regiao_saude_media AS avg_media_itens_reg,
        I05.municipio_mediana AS med_media_itens_mun, I05.estado_mediana AS med_media_itens_uf, I05.pais_mediana AS med_media_itens_br, I05.regiao_saude_mediana AS med_media_itens_reg,
        I05.risco_relativo_mun_mediana AS risco_media_itens_mun, I05.risco_relativo_uf_mediana AS risco_media_itens_uf, I05.risco_relativo_br_mediana AS risco_media_itens_br, I05.risco_relativo_reg_mediana AS risco_media_itens_reg,

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

        I14.percentual_pacientes_unicos AS pct_pacientes_unicos,
        I14.municipio_media AS avg_pacientes_unicos_mun, I14.estado_media AS avg_pacientes_unicos_uf, I14.pais_media AS avg_pacientes_unicos_br, I14.regiao_saude_media AS avg_pacientes_unicos_reg,
        I14.municipio_mediana AS med_pacientes_unicos_mun, I14.estado_mediana AS med_pacientes_unicos_uf, I14.pais_mediana AS med_pacientes_unicos_br, I14.regiao_saude_mediana AS med_pacientes_unicos_reg,
        I14.risco_relativo_mun_mediana AS risco_pacientes_unicos_mun, I14.risco_relativo_uf_mediana AS risco_pacientes_unicos_uf, I14.risco_relativo_br_mediana AS risco_pacientes_unicos_br, I14.risco_relativo_reg_mediana AS risco_pacientes_unicos_reg,

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
    LEFT JOIN temp_CGUSC.fp.indicador_media_itens_detalhado I05 ON I05.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicador_ticket_medio_detalhado I06 ON I06.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicador_receita_por_paciente_detalhado I07 ON I07.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicador_venda_per_capita_detalhado I08 ON I08.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicador_vendas_consecutivas_detalhado I09 ON I09.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicador_volume_atipico_detalhado I10 ON I10.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicador_geografico_detalhado I11 ON I11.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicador_alto_custo_detalhado I12 ON I12.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicador_concentracao_pico_detalhado I13 ON I13.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicador_pacientes_unicos_detalhado I14 ON I14.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicador_crm_detalhado I15 ON I15.nu_cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicador_exclusividade_crm_detalhado I16 ON I16.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicador_crms_irregulares_detalhado I17 ON I17.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicador_recorrencia_sistemica_detalhado I19 ON I19.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicador_auditado_detalhado IA ON IA.cnpj = F.cnpj
),

-- 3. CTE 2: CÁLCULO DE SCORE COM TETO (AQUI É A MÁGICA)
RiscosAjustados AS (
    SELECT 
        *,
        (tem_falecidos + tem_clinico + tem_teto + tem_polimedicamento + tem_media_itens + 
         tem_ticket + tem_receita_paciente + tem_per_capita + tem_vendas_rapidas + 
         tem_volume_atipico + tem_geografico + tem_alto_custo + tem_pico + tem_fantasma + 
         tem_crm + tem_exclusividade_crm + tem_crms_irregulares + tem_recorrencia_sistemica + tem_auditado) AS qtd_indicadores_preenchidos,
        
        -- LÓGICA DO TETO: "CASE WHEN risco > 10 THEN 10 ELSE risco END" aplicado APENAS NO CÁLCULO
        
        -- 1. FALECIDOS
        CASE 
            WHEN tem_falecidos=1 AND (CASE WHEN risco_falecidos_reg > 10 THEN 10 ELSE ISNULL(risco_falecidos_reg,0) END) >= 5 THEN (CASE WHEN risco_falecidos_reg > 10 THEN 10 ELSE ISNULL(risco_falecidos_reg,0) END) * 3
            WHEN tem_falecidos=1 AND (CASE WHEN risco_falecidos_reg > 10 THEN 10 ELSE ISNULL(risco_falecidos_reg,0) END) >= 3 THEN (CASE WHEN risco_falecidos_reg > 10 THEN 10 ELSE ISNULL(risco_falecidos_reg,0) END) * 2
            WHEN tem_falecidos=1 AND (CASE WHEN risco_falecidos_reg > 10 THEN 10 ELSE ISNULL(risco_falecidos_reg,0) END) >= 1.5 THEN (CASE WHEN risco_falecidos_reg > 10 THEN 10 ELSE ISNULL(risco_falecidos_reg,0) END) * 1.5
            ELSE (CASE WHEN risco_falecidos_reg > 10 THEN 10 ELSE ISNULL(risco_falecidos_reg,0) END) 
        END AS risco_falecidos_ajustado,
        CASE WHEN tem_falecidos=1 AND (CASE WHEN risco_falecidos_reg > 10 THEN 10 ELSE ISNULL(risco_falecidos_reg,0) END) >= 5 THEN 1 ELSE 0 END AS flag_falecidos_critico,
        
        -- 2. CLÍNICO
        CASE 
            WHEN tem_clinico=1 AND (CASE WHEN risco_clinico_reg > 10 THEN 10 ELSE ISNULL(risco_clinico_reg,0) END) >= 5 THEN (CASE WHEN risco_clinico_reg > 10 THEN 10 ELSE ISNULL(risco_clinico_reg,0) END) * 3
            WHEN tem_clinico=1 AND (CASE WHEN risco_clinico_reg > 10 THEN 10 ELSE ISNULL(risco_clinico_reg,0) END) >= 3 THEN (CASE WHEN risco_clinico_reg > 10 THEN 10 ELSE ISNULL(risco_clinico_reg,0) END) * 2
            WHEN tem_clinico=1 AND (CASE WHEN risco_clinico_reg > 10 THEN 10 ELSE ISNULL(risco_clinico_reg,0) END) >= 1.5 THEN (CASE WHEN risco_clinico_reg > 10 THEN 10 ELSE ISNULL(risco_clinico_reg,0) END) * 1.5
            ELSE (CASE WHEN risco_clinico_reg > 10 THEN 10 ELSE ISNULL(risco_clinico_reg,0) END) 
        END AS risco_clinico_ajustado,
        CASE WHEN tem_clinico=1 AND (CASE WHEN risco_clinico_reg > 10 THEN 10 ELSE ISNULL(risco_clinico_reg,0) END) >= 5 THEN 1 ELSE 0 END AS flag_clinico_critico,
        
        -- 3. TETO
        CASE 
            WHEN tem_teto=1 AND (CASE WHEN risco_teto_reg > 10 THEN 10 ELSE ISNULL(risco_teto_reg,0) END) >= 5 THEN (CASE WHEN risco_teto_reg > 10 THEN 10 ELSE ISNULL(risco_teto_reg,0) END) * 3
            WHEN tem_teto=1 AND (CASE WHEN risco_teto_reg > 10 THEN 10 ELSE ISNULL(risco_teto_reg,0) END) >= 3 THEN (CASE WHEN risco_teto_reg > 10 THEN 10 ELSE ISNULL(risco_teto_reg,0) END) * 2
            WHEN tem_teto=1 AND (CASE WHEN risco_teto_reg > 10 THEN 10 ELSE ISNULL(risco_teto_reg,0) END) >= 1.5 THEN (CASE WHEN risco_teto_reg > 10 THEN 10 ELSE ISNULL(risco_teto_reg,0) END) * 1.5
            ELSE (CASE WHEN risco_teto_reg > 10 THEN 10 ELSE ISNULL(risco_teto_reg,0) END) 
        END AS risco_teto_ajustado,
        CASE WHEN tem_teto=1 AND (CASE WHEN risco_teto_reg > 10 THEN 10 ELSE ISNULL(risco_teto_reg,0) END) >= 5 THEN 1 ELSE 0 END AS flag_teto_critico,

        -- 4. POLIMEDICAMENTO
        CASE 
            WHEN tem_polimedicamento=1 AND (CASE WHEN risco_polimedicamento_reg > 10 THEN 10 ELSE ISNULL(risco_polimedicamento_reg,0) END) >= 5 THEN (CASE WHEN risco_polimedicamento_reg > 10 THEN 10 ELSE ISNULL(risco_polimedicamento_reg,0) END) * 3
            WHEN tem_polimedicamento=1 AND (CASE WHEN risco_polimedicamento_reg > 10 THEN 10 ELSE ISNULL(risco_polimedicamento_reg,0) END) >= 3 THEN (CASE WHEN risco_polimedicamento_reg > 10 THEN 10 ELSE ISNULL(risco_polimedicamento_reg,0) END) * 2
            WHEN tem_polimedicamento=1 AND (CASE WHEN risco_polimedicamento_reg > 10 THEN 10 ELSE ISNULL(risco_polimedicamento_reg,0) END) >= 1.5 THEN (CASE WHEN risco_polimedicamento_reg > 10 THEN 10 ELSE ISNULL(risco_polimedicamento_reg,0) END) * 1.5
            ELSE (CASE WHEN risco_polimedicamento_reg > 10 THEN 10 ELSE ISNULL(risco_polimedicamento_reg,0) END) 
        END AS risco_polimedicamento_ajustado,
        CASE WHEN tem_polimedicamento=1 AND (CASE WHEN risco_polimedicamento_reg > 10 THEN 10 ELSE ISNULL(risco_polimedicamento_reg,0) END) >= 5 THEN 1 ELSE 0 END AS flag_polimedicamento_critico,

        -- 5. MEDIA ITENS
        CASE 
            WHEN tem_media_itens=1 AND (CASE WHEN risco_media_itens_reg > 10 THEN 10 ELSE ISNULL(risco_media_itens_reg,0) END) >= 5 THEN (CASE WHEN risco_media_itens_reg > 10 THEN 10 ELSE ISNULL(risco_media_itens_reg,0) END) * 3
            WHEN tem_media_itens=1 AND (CASE WHEN risco_media_itens_reg > 10 THEN 10 ELSE ISNULL(risco_media_itens_reg,0) END) >= 3 THEN (CASE WHEN risco_media_itens_reg > 10 THEN 10 ELSE ISNULL(risco_media_itens_reg,0) END) * 2
            WHEN tem_media_itens=1 AND (CASE WHEN risco_media_itens_reg > 10 THEN 10 ELSE ISNULL(risco_media_itens_reg,0) END) >= 1.5 THEN (CASE WHEN risco_media_itens_reg > 10 THEN 10 ELSE ISNULL(risco_media_itens_reg,0) END) * 1.5
            ELSE (CASE WHEN risco_media_itens_reg > 10 THEN 10 ELSE ISNULL(risco_media_itens_reg,0) END) 
        END AS risco_media_itens_ajustado,
        CASE WHEN tem_media_itens=1 AND (CASE WHEN risco_media_itens_reg > 10 THEN 10 ELSE ISNULL(risco_media_itens_reg,0) END) >= 5 THEN 1 ELSE 0 END AS flag_media_itens_critico,

        -- 6. TICKET
        CASE 
            WHEN tem_ticket=1 AND (CASE WHEN risco_ticket_reg > 10 THEN 10 ELSE ISNULL(risco_ticket_reg,0) END) >= 5 THEN (CASE WHEN risco_ticket_reg > 10 THEN 10 ELSE ISNULL(risco_ticket_reg,0) END) * 3
            WHEN tem_ticket=1 AND (CASE WHEN risco_ticket_reg > 10 THEN 10 ELSE ISNULL(risco_ticket_reg,0) END) >= 3 THEN (CASE WHEN risco_ticket_reg > 10 THEN 10 ELSE ISNULL(risco_ticket_reg,0) END) * 2
            WHEN tem_ticket=1 AND (CASE WHEN risco_ticket_reg > 10 THEN 10 ELSE ISNULL(risco_ticket_reg,0) END) >= 1.5 THEN (CASE WHEN risco_ticket_reg > 10 THEN 10 ELSE ISNULL(risco_ticket_reg,0) END) * 1.5
            ELSE (CASE WHEN risco_ticket_reg > 10 THEN 10 ELSE ISNULL(risco_ticket_reg,0) END) 
        END AS risco_ticket_ajustado,
        CASE WHEN tem_ticket=1 AND (CASE WHEN risco_ticket_reg > 10 THEN 10 ELSE ISNULL(risco_ticket_reg,0) END) >= 5 THEN 1 ELSE 0 END AS flag_ticket_critico,

        -- 7. RECEITA PACIENTE
        CASE 
            WHEN tem_receita_paciente=1 AND (CASE WHEN risco_receita_paciente_reg > 10 THEN 10 ELSE ISNULL(risco_receita_paciente_reg,0) END) >= 5 THEN (CASE WHEN risco_receita_paciente_reg > 10 THEN 10 ELSE ISNULL(risco_receita_paciente_reg,0) END) * 3
            WHEN tem_receita_paciente=1 AND (CASE WHEN risco_receita_paciente_reg > 10 THEN 10 ELSE ISNULL(risco_receita_paciente_reg,0) END) >= 3 THEN (CASE WHEN risco_receita_paciente_reg > 10 THEN 10 ELSE ISNULL(risco_receita_paciente_reg,0) END) * 2
            WHEN tem_receita_paciente=1 AND (CASE WHEN risco_receita_paciente_reg > 10 THEN 10 ELSE ISNULL(risco_receita_paciente_reg,0) END) >= 1.5 THEN (CASE WHEN risco_receita_paciente_reg > 10 THEN 10 ELSE ISNULL(risco_receita_paciente_reg,0) END) * 1.5
            ELSE (CASE WHEN risco_receita_paciente_reg > 10 THEN 10 ELSE ISNULL(risco_receita_paciente_reg,0) END) 
        END AS risco_receita_paciente_ajustado,
        CASE WHEN tem_receita_paciente=1 AND (CASE WHEN risco_receita_paciente_reg > 10 THEN 10 ELSE ISNULL(risco_receita_paciente_reg,0) END) >= 5 THEN 1 ELSE 0 END AS flag_receita_paciente_critico,

        -- 8. PER CAPITA
        CASE 
            WHEN tem_per_capita=1 AND (CASE WHEN risco_per_capita_reg > 10 THEN 10 ELSE ISNULL(risco_per_capita_reg,0) END) >= 5 THEN (CASE WHEN risco_per_capita_reg > 10 THEN 10 ELSE ISNULL(risco_per_capita_reg,0) END) * 3
            WHEN tem_per_capita=1 AND (CASE WHEN risco_per_capita_reg > 10 THEN 10 ELSE ISNULL(risco_per_capita_reg,0) END) >= 3 THEN (CASE WHEN risco_per_capita_reg > 10 THEN 10 ELSE ISNULL(risco_per_capita_reg,0) END) * 2
            WHEN tem_per_capita=1 AND (CASE WHEN risco_per_capita_reg > 10 THEN 10 ELSE ISNULL(risco_per_capita_reg,0) END) >= 1.5 THEN (CASE WHEN risco_per_capita_reg > 10 THEN 10 ELSE ISNULL(risco_per_capita_reg,0) END) * 1.5
            ELSE (CASE WHEN risco_per_capita_reg > 10 THEN 10 ELSE ISNULL(risco_per_capita_reg,0) END) 
        END AS risco_per_capita_ajustado,
        CASE WHEN tem_per_capita=1 AND (CASE WHEN risco_per_capita_reg > 10 THEN 10 ELSE ISNULL(risco_per_capita_reg,0) END) >= 5 THEN 1 ELSE 0 END AS flag_per_capita_critico,

        -- 9. VENDAS RAPIDAS
        CASE 
            WHEN tem_vendas_rapidas=1 AND (CASE WHEN risco_vendas_rapidas_reg > 10 THEN 10 ELSE ISNULL(risco_vendas_rapidas_reg,0) END) >= 5 THEN (CASE WHEN risco_vendas_rapidas_reg > 10 THEN 10 ELSE ISNULL(risco_vendas_rapidas_reg,0) END) * 3
            WHEN tem_vendas_rapidas=1 AND (CASE WHEN risco_vendas_rapidas_reg > 10 THEN 10 ELSE ISNULL(risco_vendas_rapidas_reg,0) END) >= 3 THEN (CASE WHEN risco_vendas_rapidas_reg > 10 THEN 10 ELSE ISNULL(risco_vendas_rapidas_reg,0) END) * 2
            WHEN tem_vendas_rapidas=1 AND (CASE WHEN risco_vendas_rapidas_reg > 10 THEN 10 ELSE ISNULL(risco_vendas_rapidas_reg,0) END) >= 1.5 THEN (CASE WHEN risco_vendas_rapidas_reg > 10 THEN 10 ELSE ISNULL(risco_vendas_rapidas_reg,0) END) * 1.5
            ELSE (CASE WHEN risco_vendas_rapidas_reg > 10 THEN 10 ELSE ISNULL(risco_vendas_rapidas_reg,0) END) 
        END AS risco_vendas_rapidas_ajustado,
        CASE WHEN tem_vendas_rapidas=1 AND (CASE WHEN risco_vendas_rapidas_reg > 10 THEN 10 ELSE ISNULL(risco_vendas_rapidas_reg,0) END) >= 5 THEN 1 ELSE 0 END AS flag_vendas_rapidas_critico,

        -- 10. VOLUME ATIPICO
        CASE 
            WHEN tem_volume_atipico=1 AND (CASE WHEN risco_volume_atipico_reg > 10 THEN 10 ELSE ISNULL(risco_volume_atipico_reg,0) END) >= 5 THEN (CASE WHEN risco_volume_atipico_reg > 10 THEN 10 ELSE ISNULL(risco_volume_atipico_reg,0) END) * 3
            WHEN tem_volume_atipico=1 AND (CASE WHEN risco_volume_atipico_reg > 10 THEN 10 ELSE ISNULL(risco_volume_atipico_reg,0) END) >= 3 THEN (CASE WHEN risco_volume_atipico_reg > 10 THEN 10 ELSE ISNULL(risco_volume_atipico_reg,0) END) * 2
            WHEN tem_volume_atipico=1 AND (CASE WHEN risco_volume_atipico_reg > 10 THEN 10 ELSE ISNULL(risco_volume_atipico_reg,0) END) >= 1.5 THEN (CASE WHEN risco_volume_atipico_reg > 10 THEN 10 ELSE ISNULL(risco_volume_atipico_reg,0) END) * 1.5
            ELSE (CASE WHEN risco_volume_atipico_reg > 10 THEN 10 ELSE ISNULL(risco_volume_atipico_reg,0) END) 
        END AS risco_volume_atipico_ajustado,
        CASE WHEN tem_volume_atipico=1 AND (CASE WHEN risco_volume_atipico_reg > 10 THEN 10 ELSE ISNULL(risco_volume_atipico_reg,0) END) >= 5 THEN 1 ELSE 0 END AS flag_volume_atipico_critico,

        -- 11. GEOGRAFICO
        CASE 
            WHEN tem_geografico=1 AND (CASE WHEN risco_geografico_reg > 10 THEN 10 ELSE ISNULL(risco_geografico_reg,0) END) >= 5 THEN (CASE WHEN risco_geografico_reg > 10 THEN 10 ELSE ISNULL(risco_geografico_reg,0) END) * 3
            WHEN tem_geografico=1 AND (CASE WHEN risco_geografico_reg > 10 THEN 10 ELSE ISNULL(risco_geografico_reg,0) END) >= 3 THEN (CASE WHEN risco_geografico_reg > 10 THEN 10 ELSE ISNULL(risco_geografico_reg,0) END) * 2
            WHEN tem_geografico=1 AND (CASE WHEN risco_geografico_reg > 10 THEN 10 ELSE ISNULL(risco_geografico_reg,0) END) >= 1.5 THEN (CASE WHEN risco_geografico_reg > 10 THEN 10 ELSE ISNULL(risco_geografico_reg,0) END) * 1.5
            ELSE (CASE WHEN risco_geografico_reg > 10 THEN 10 ELSE ISNULL(risco_geografico_reg,0) END) 
        END AS risco_geografico_ajustado,
        CASE WHEN tem_geografico=1 AND (CASE WHEN risco_geografico_reg > 10 THEN 10 ELSE ISNULL(risco_geografico_reg,0) END) >= 5 THEN 1 ELSE 0 END AS flag_geografico_critico,

        -- 12. ALTO CUSTO
        CASE 
            WHEN tem_alto_custo=1 AND (CASE WHEN risco_alto_custo_reg > 10 THEN 10 ELSE ISNULL(risco_alto_custo_reg,0) END) >= 5 THEN (CASE WHEN risco_alto_custo_reg > 10 THEN 10 ELSE ISNULL(risco_alto_custo_reg,0) END) * 3
            WHEN tem_alto_custo=1 AND (CASE WHEN risco_alto_custo_reg > 10 THEN 10 ELSE ISNULL(risco_alto_custo_reg,0) END) >= 3 THEN (CASE WHEN risco_alto_custo_reg > 10 THEN 10 ELSE ISNULL(risco_alto_custo_reg,0) END) * 2
            WHEN tem_alto_custo=1 AND (CASE WHEN risco_alto_custo_reg > 10 THEN 10 ELSE ISNULL(risco_alto_custo_reg,0) END) >= 1.5 THEN (CASE WHEN risco_alto_custo_reg > 10 THEN 10 ELSE ISNULL(risco_alto_custo_reg,0) END) * 1.5
            ELSE (CASE WHEN risco_alto_custo_reg > 10 THEN 10 ELSE ISNULL(risco_alto_custo_reg,0) END) 
        END AS risco_alto_custo_ajustado,
        CASE WHEN tem_alto_custo=1 AND (CASE WHEN risco_alto_custo_reg > 10 THEN 10 ELSE ISNULL(risco_alto_custo_reg,0) END) >= 5 THEN 1 ELSE 0 END AS flag_alto_custo_critico,

        -- 13. PICO
        CASE 
            WHEN tem_pico=1 AND (CASE WHEN risco_pico_reg > 10 THEN 10 ELSE ISNULL(risco_pico_reg,0) END) >= 5 THEN (CASE WHEN risco_pico_reg > 10 THEN 10 ELSE ISNULL(risco_pico_reg,0) END) * 3
            WHEN tem_pico=1 AND (CASE WHEN risco_pico_reg > 10 THEN 10 ELSE ISNULL(risco_pico_reg,0) END) >= 3 THEN (CASE WHEN risco_pico_reg > 10 THEN 10 ELSE ISNULL(risco_pico_reg,0) END) * 2
            WHEN tem_pico=1 AND (CASE WHEN risco_pico_reg > 10 THEN 10 ELSE ISNULL(risco_pico_reg,0) END) >= 1.5 THEN (CASE WHEN risco_pico_reg > 10 THEN 10 ELSE ISNULL(risco_pico_reg,0) END) * 1.5
            ELSE (CASE WHEN risco_pico_reg > 10 THEN 10 ELSE ISNULL(risco_pico_reg,0) END) 
        END AS risco_pico_ajustado,
        CASE WHEN tem_pico=1 AND (CASE WHEN risco_pico_reg > 10 THEN 10 ELSE ISNULL(risco_pico_reg,0) END) >= 5 THEN 1 ELSE 0 END AS flag_pico_critico,

        -- 14. PACIENTES UNICOS (FANTASMA)
        CASE 
            WHEN tem_fantasma=1 AND (CASE WHEN risco_pacientes_unicos_reg > 10 THEN 10 ELSE ISNULL(risco_pacientes_unicos_reg,0) END) >= 5 THEN (CASE WHEN risco_pacientes_unicos_reg > 10 THEN 10 ELSE ISNULL(risco_pacientes_unicos_reg,0) END) * 3
            WHEN tem_fantasma=1 AND (CASE WHEN risco_pacientes_unicos_reg > 10 THEN 10 ELSE ISNULL(risco_pacientes_unicos_reg,0) END) >= 3 THEN (CASE WHEN risco_pacientes_unicos_reg > 10 THEN 10 ELSE ISNULL(risco_pacientes_unicos_reg,0) END) * 2
            WHEN tem_fantasma=1 AND (CASE WHEN risco_pacientes_unicos_reg > 10 THEN 10 ELSE ISNULL(risco_pacientes_unicos_reg,0) END) >= 1.5 THEN (CASE WHEN risco_pacientes_unicos_reg > 10 THEN 10 ELSE ISNULL(risco_pacientes_unicos_reg,0) END) * 1.5
            ELSE (CASE WHEN risco_pacientes_unicos_reg > 10 THEN 10 ELSE ISNULL(risco_pacientes_unicos_reg,0) END) 
        END AS risco_pacientes_unicos_ajustado,
        CASE WHEN tem_fantasma=1 AND (CASE WHEN risco_pacientes_unicos_reg > 10 THEN 10 ELSE ISNULL(risco_pacientes_unicos_reg,0) END) >= 5 THEN 1 ELSE 0 END AS flag_pacientes_unicos_critico,

        -- 15. CRM HHI
        CASE 
            WHEN tem_crm=1 AND (CASE WHEN risco_crm_reg > 10 THEN 10 ELSE ISNULL(risco_crm_reg,0) END) >= 5 THEN (CASE WHEN risco_crm_reg > 10 THEN 10 ELSE ISNULL(risco_crm_reg,0) END) * 3
            WHEN tem_crm=1 AND (CASE WHEN risco_crm_reg > 10 THEN 10 ELSE ISNULL(risco_crm_reg,0) END) >= 3 THEN (CASE WHEN risco_crm_reg > 10 THEN 10 ELSE ISNULL(risco_crm_reg,0) END) * 2
            WHEN tem_crm=1 AND (CASE WHEN risco_crm_reg > 10 THEN 10 ELSE ISNULL(risco_crm_reg,0) END) >= 1.5 THEN (CASE WHEN risco_crm_reg > 10 THEN 10 ELSE ISNULL(risco_crm_reg,0) END) * 1.5
            ELSE (CASE WHEN risco_crm_reg > 10 THEN 10 ELSE ISNULL(risco_crm_reg,0) END) 
        END AS risco_crm_ajustado,
        CASE WHEN tem_crm=1 AND (CASE WHEN risco_crm_reg > 10 THEN 10 ELSE ISNULL(risco_crm_reg,0) END) >= 5 THEN 1 ELSE 0 END AS flag_crm_critico,

        -- 16. EXCLUSIVIDADE CRM
        CASE 
            WHEN tem_exclusividade_crm=1 AND (CASE WHEN risco_exclusividade_crm_reg > 10 THEN 10 ELSE ISNULL(risco_exclusividade_crm_reg,0) END) >= 5 THEN (CASE WHEN risco_exclusividade_crm_reg > 10 THEN 10 ELSE ISNULL(risco_exclusividade_crm_reg,0) END) * 3
            WHEN tem_exclusividade_crm=1 AND (CASE WHEN risco_exclusividade_crm_reg > 10 THEN 10 ELSE ISNULL(risco_exclusividade_crm_reg,0) END) >= 3 THEN (CASE WHEN risco_exclusividade_crm_reg > 10 THEN 10 ELSE ISNULL(risco_exclusividade_crm_reg,0) END) * 2
            WHEN tem_exclusividade_crm=1 AND (CASE WHEN risco_exclusividade_crm_reg > 10 THEN 10 ELSE ISNULL(risco_exclusividade_crm_reg,0) END) >= 1.5 THEN (CASE WHEN risco_exclusividade_crm_reg > 10 THEN 10 ELSE ISNULL(risco_exclusividade_crm_reg,0) END) * 1.5
            ELSE (CASE WHEN risco_exclusividade_crm_reg > 10 THEN 10 ELSE ISNULL(risco_exclusividade_crm_reg,0) END) 
        END AS risco_exclusividade_crm_ajustado,
        CASE WHEN tem_exclusividade_crm=1 AND (CASE WHEN risco_exclusividade_crm_reg > 10 THEN 10 ELSE ISNULL(risco_exclusividade_crm_reg,0) END) >= 5 THEN 1 ELSE 0 END AS flag_exclusividade_crm_critico,

        -- 17. CRMS IRREGULARES
        CASE 
            WHEN tem_crms_irregulares=1 AND (CASE WHEN risco_crms_irregulares_reg > 10 THEN 10 ELSE ISNULL(risco_crms_irregulares_reg,0) END) >= 5 THEN (CASE WHEN risco_crms_irregulares_reg > 10 THEN 10 ELSE ISNULL(risco_crms_irregulares_reg,0) END) * 3
            WHEN tem_crms_irregulares=1 AND (CASE WHEN risco_crms_irregulares_reg > 10 THEN 10 ELSE ISNULL(risco_crms_irregulares_reg,0) END) >= 3 THEN (CASE WHEN risco_crms_irregulares_reg > 10 THEN 10 ELSE ISNULL(risco_crms_irregulares_reg,0) END) * 2
            WHEN tem_crms_irregulares=1 AND (CASE WHEN risco_crms_irregulares_reg > 10 THEN 10 ELSE ISNULL(risco_crms_irregulares_reg,0) END) >= 1.5 THEN (CASE WHEN risco_crms_irregulares_reg > 10 THEN 10 ELSE ISNULL(risco_crms_irregulares_reg,0) END) * 1.5
            ELSE (CASE WHEN risco_crms_irregulares_reg > 10 THEN 10 ELSE ISNULL(risco_crms_irregulares_reg,0) END) 
        END AS risco_crms_irregulares_ajustado,
        CASE WHEN tem_crms_irregulares=1 AND (CASE WHEN risco_crms_irregulares_reg > 10 THEN 10 ELSE ISNULL(risco_crms_irregulares_reg,0) END) >= 5 THEN 1 ELSE 0 END AS flag_crms_irregulares_critico,

        -- 18. RECORRÊNCIA SISTÊMICA (RELÓGIO SUÍÇO)
        CASE 
            WHEN tem_recorrencia_sistemica=1 AND (CASE WHEN risco_recorrencia_sistemica_reg > 10 THEN 10 ELSE ISNULL(risco_recorrencia_sistemica_reg,0) END) >= 5 THEN (CASE WHEN risco_recorrencia_sistemica_reg > 10 THEN 10 ELSE ISNULL(risco_recorrencia_sistemica_reg,0) END) * 3
            WHEN tem_recorrencia_sistemica=1 AND (CASE WHEN risco_recorrencia_sistemica_reg > 10 THEN 10 ELSE ISNULL(risco_recorrencia_sistemica_reg,0) END) >= 3 THEN (CASE WHEN risco_recorrencia_sistemica_reg > 10 THEN 10 ELSE ISNULL(risco_recorrencia_sistemica_reg,0) END) * 2
            WHEN tem_recorrencia_sistemica=1 AND (CASE WHEN risco_recorrencia_sistemica_reg > 10 THEN 10 ELSE ISNULL(risco_recorrencia_sistemica_reg,0) END) >= 1.5 THEN (CASE WHEN risco_recorrencia_sistemica_reg > 10 THEN 10 ELSE ISNULL(risco_recorrencia_sistemica_reg,0) END) * 1.5
            ELSE (CASE WHEN risco_recorrencia_sistemica_reg > 10 THEN 10 ELSE ISNULL(risco_recorrencia_sistemica_reg,0) END) 
        END AS risco_recorrencia_sistemica_ajustado,
        CASE WHEN tem_recorrencia_sistemica=1 AND (CASE WHEN risco_recorrencia_sistemica_reg > 10 THEN 10 ELSE ISNULL(risco_recorrencia_sistemica_reg,0) END) >= 5 THEN 1 ELSE 0 END AS flag_recorrencia_sistemica_critico,

        -- 19. AUDITORIA FINANCEIRA (MUITO PESADO)
        CASE 
            WHEN tem_auditado=1 AND (CASE WHEN risco_auditado_reg > 10 THEN 10 ELSE ISNULL(risco_auditado_reg,0) END) >= 8 THEN (CASE WHEN risco_auditado_reg > 10 THEN 10 ELSE ISNULL(risco_auditado_reg,0) END) * 5
            WHEN tem_auditado=1 AND (CASE WHEN risco_auditado_reg > 10 THEN 10 ELSE ISNULL(risco_auditado_reg,0) END) >= 4 THEN (CASE WHEN risco_auditado_reg > 10 THEN 10 ELSE ISNULL(risco_auditado_reg,0) END) * 3
            WHEN tem_auditado=1 AND (CASE WHEN risco_auditado_reg > 10 THEN 10 ELSE ISNULL(risco_auditado_reg,0) END) >= 2 THEN (CASE WHEN risco_auditado_reg > 10 THEN 10 ELSE ISNULL(risco_auditado_reg,0) END) * 2
            ELSE (CASE WHEN risco_auditado_reg > 10 THEN 10 ELSE ISNULL(risco_auditado_reg,0) END) 
        END AS risco_auditado_ajustado,
        CASE WHEN tem_auditado=1 AND (CASE WHEN risco_auditado_reg > 10 THEN 10 ELSE ISNULL(risco_auditado_reg,0) END) >= 5 THEN 1 ELSE 0 END AS flag_auditado_critico

    FROM IndicadoresPresenca
),

-- 4. CTE 3: CONSOLIDAÇÃO DOS RISCOS (SOMA)
ScoreCalculado AS (
    SELECT 
        *,
        CAST(qtd_indicadores_preenchidos * 100.0 / 19.0 AS DECIMAL(5,2)) AS pct_completude,
        
        -- Soma dos riscos ajustados (JÁ COM TETO APLICADO NA ETAPA ANTERIOR)
        (risco_falecidos_ajustado + risco_clinico_ajustado + risco_teto_ajustado +
         risco_polimedicamento_ajustado + risco_media_itens_ajustado + risco_ticket_ajustado +
         risco_receita_paciente_ajustado + risco_per_capita_ajustado + risco_vendas_rapidas_ajustado +
         risco_volume_atipico_ajustado + risco_geografico_ajustado + risco_alto_custo_ajustado +
         risco_pico_ajustado + risco_pacientes_unicos_ajustado + risco_crm_ajustado +
         risco_exclusividade_crm_ajustado + risco_crms_irregulares_ajustado + risco_recorrencia_sistemica_ajustado + risco_auditado_ajustado
        ) AS soma_riscos_ajustados,
        
        -- Contagem de flags críticos
        (flag_falecidos_critico + flag_clinico_critico + flag_teto_critico +
         flag_polimedicamento_critico + flag_media_itens_critico + flag_ticket_critico +
         flag_receita_paciente_critico + flag_per_capita_critico + flag_vendas_rapidas_critico +
         flag_volume_atipico_critico + flag_geografico_critico + flag_alto_custo_critico +
         flag_pico_critico + flag_pacientes_unicos_critico + flag_crm_critico +
         flag_exclusividade_crm_critico + flag_crms_irregulares_critico + flag_recorrencia_sistemica_critico + flag_auditado_critico
        ) AS qtd_indicadores_criticos
    FROM RiscosAjustados
),

-- 5. CTE 4: CÁLCULO DOS SCORES FINAIS
ScoreCalculadoFim AS (
    SELECT
        *,
        -- Score Base
        CAST(
            CASE WHEN qtd_indicadores_preenchidos > 0 
            THEN soma_riscos_ajustados / 19.0 ELSE 0 END 
        AS DECIMAL(18,4)) AS SCORE_BASE,

        -- Score Final (com bônus de reincidência aplicados)
        CAST(
            CASE WHEN qtd_indicadores_preenchidos > 0 THEN
                (soma_riscos_ajustados / (qtd_indicadores_preenchidos * 1.0)) *
                CASE 
                    WHEN qtd_indicadores_criticos >= 5 THEN 4.0
                    WHEN qtd_indicadores_criticos >= 3 THEN 2.0
                    WHEN qtd_indicadores_criticos >= 1 THEN 1.5
                    ELSE 1.0
                END
            ELSE 0 END
        AS DECIMAL(18,4)) AS SCORE_RISCO_FINAL,

        -- Qualidade dos Dados
        CASE 
            WHEN qtd_indicadores_preenchidos >= 15 THEN 'ALTA'
            WHEN qtd_indicadores_preenchidos >= 10 THEN 'MEDIA'
            WHEN qtd_indicadores_preenchidos >= 1 THEN 'BAIXA'
            ELSE 'SEM_DADOS'
        END AS flag_qualidade_dados,

        -- Lista textual de problemas
        STUFF(
            CASE WHEN flag_falecidos_critico = 1 THEN ', Falecidos' ELSE '' END +
            CASE WHEN flag_clinico_critico = 1 THEN ', Clínico' ELSE '' END +
            CASE WHEN flag_teto_critico = 1 THEN ', Teto' ELSE '' END +
            CASE WHEN flag_polimedicamento_critico = 1 THEN ', Polimedicamento' ELSE '' END +
            CASE WHEN flag_media_itens_critico = 1 THEN ', Média Itens' ELSE '' END +
            CASE WHEN flag_ticket_critico = 1 THEN ', Ticket Médio' ELSE '' END +
            CASE WHEN flag_receita_paciente_critico = 1 THEN ', Receita/Paciente' ELSE '' END +
            CASE WHEN flag_per_capita_critico = 1 THEN ', Per Capita' ELSE '' END +
            CASE WHEN flag_vendas_rapidas_critico = 1 THEN ', Vendas Rápidas' ELSE '' END +
            CASE WHEN flag_volume_atipico_critico = 1 THEN ', Volume Atípico' ELSE '' END +
            CASE WHEN flag_geografico_critico = 1 THEN ', Geográfico' ELSE '' END +
            CASE WHEN flag_alto_custo_critico = 1 THEN ', Alto Custo' ELSE '' END +
            CASE WHEN flag_pico_critico = 1 THEN ', Pico' ELSE '' END +
            CASE WHEN flag_pacientes_unicos_critico = 1 THEN ', Pacientes Únicos' ELSE '' END +
            CASE WHEN flag_crm_critico = 1 THEN ', CRM HHI' ELSE '' END +
            CASE WHEN flag_exclusividade_crm_critico = 1 THEN ', Exclusividade CRM' ELSE '' END +
            CASE WHEN flag_crms_irregulares_critico = 1 THEN ', CRMs Irregulares' ELSE '' END +
            CASE WHEN flag_recorrencia_sistemica_critico = 1 THEN ', Recorrência Sistêmica' ELSE '' END +
            CASE WHEN flag_auditado_critico = 1 THEN ', Auditoria Financeira' ELSE '' END,
        1, 2, '') AS indicadores_criticos_lista
    FROM ScoreCalculado
),

-- 6. CTE 5: CLASSIFICAÇÃO FINAL
ClassificacaoFinal AS (
    SELECT 
        *,
        CASE 
            -- 1. CRÍTICO (Fraude Sistêmica)
            WHEN qtd_indicadores_criticos >= 3 THEN 'RISCO CRITICO'

            -- 2. ALTO (2 problemas graves OU Score alto)
            WHEN qtd_indicadores_criticos >= 2 THEN 'RISCO ALTO'
            WHEN SCORE_RISCO_FINAL >= 4.0 THEN 'RISCO ALTO' 

            -- 3. MÉDIO (1 problema grave OU Score moderado)
            WHEN qtd_indicadores_criticos = 1 THEN 'RISCO MEDIO'
            WHEN SCORE_RISCO_FINAL >= 2.0 THEN 'RISCO MEDIO'

            -- 4. BAIXO
            WHEN SCORE_RISCO_FINAL >= 1.0 THEN 'RISCO BAIXO'

            -- 5. MÍNIMO
            ELSE 'RISCO MINIMO'
        END AS CLASSIFICACAO_RISCO
    FROM ScoreCalculadoFim
)

-- 7. SELEÇÃO FINAL E CRIAÇÃO DA TABELA FÍSICA
SELECT 
    S.*,
    
    -- RANKINGS NACIONAIS E ESTADUAIS
    RANK() OVER (ORDER BY SCORE_RISCO_FINAL DESC) AS rank_nacional,
    COUNT(*) OVER () AS total_nacional,
    RANK() OVER (PARTITION BY uf ORDER BY SCORE_RISCO_FINAL DESC) AS rank_uf,
    COUNT(*) OVER (PARTITION BY uf) AS total_uf,

    -- REGIAO DE SAUDE
    RANK() OVER (PARTITION BY id_regiao_saude ORDER BY SCORE_RISCO_FINAL DESC) AS rank_regiao_saude,
    COUNT(*) OVER (PARTITION BY id_regiao_saude) AS total_regiao_saude,
    CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY SCORE_RISCO_FINAL) OVER (PARTITION BY id_regiao_saude) AS DECIMAL(18,2)) AS avg_score_regiao_saude,
    CAST(MAX(SCORE_RISCO_FINAL) OVER (PARTITION BY id_regiao_saude) AS DECIMAL(18,2)) AS max_score_regiao_saude,

    -- INTELIGÊNCIA MUNICIPAL
    RANK() OVER (PARTITION BY uf, municipio ORDER BY SCORE_RISCO_FINAL DESC) AS rank_municipio,
    COUNT(*) OVER (PARTITION BY uf, municipio) AS total_municipio,

    -- ESTATÍSTICAS LOCAIS
    CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY SCORE_RISCO_FINAL) OVER (PARTITION BY uf, municipio) AS DECIMAL(18,2)) AS avg_score_municipio,
    CAST(MAX(SCORE_RISCO_FINAL) OVER (PARTITION BY uf, municipio) AS DECIMAL(18,2)) AS max_score_municipio,

    -- PERCENTIL
    CAST(CUME_DIST() OVER (ORDER BY SCORE_RISCO_FINAL ASC) * 100 AS DECIMAL(5,2)) AS percentil_risco

INTO temp_CGUSC.fp.matriz_risco_consolidada
FROM ClassificacaoFinal S;

PRINT '   > Tabela temp_CGUSC.fp.matriz_risco_consolidada (V5.5) criada com sucesso.';

-- ============================================================================
-- CRIAÇÃO DE ÍNDICES OTIMIZADOS
-- ============================================================================
PRINT '   > Recriando índices...';

CREATE CLUSTERED INDEX IDX_MatrizFinal_CNPJ 
    ON temp_CGUSC.fp.matriz_risco_consolidada(cnpj);

CREATE NONCLUSTERED INDEX IDX_MatrizFinal_ScoreRiscoFinal 
    ON temp_CGUSC.fp.matriz_risco_consolidada(SCORE_RISCO_FINAL DESC)
    INCLUDE (razaoSocial, uf, rank_nacional, CLASSIFICACAO_RISCO);

CREATE NONCLUSTERED INDEX IDX_MatrizFinal_Municipio 
    ON temp_CGUSC.fp.matriz_risco_consolidada(uf, municipio, SCORE_RISCO_FINAL DESC)
    INCLUDE (rank_municipio, avg_score_municipio);

CREATE NONCLUSTERED INDEX IDX_MatrizFinal_Regiao
    ON temp_CGUSC.fp.matriz_risco_consolidada(id_regiao_saude, SCORE_RISCO_FINAL DESC)
    INCLUDE (no_regiao_saude, rank_regiao_saude, avg_score_regiao_saude);

PRINT '>> PROCESSO CONCLUÍDO COM SUCESSO.';
GO

-- ============================================================================
-- VALIDAÇÃO RÁPIDA
-- ============================================================================
SELECT CLASSIFICACAO_RISCO, COUNT(*) as Qtd, 
       CAST(AVG(SCORE_RISCO_FINAL) as DECIMAL(10,2)) as Media_Score,
       MIN(SCORE_RISCO_FINAL) as Min_Score,
       MAX(SCORE_RISCO_FINAL) as Max_Score
FROM temp_CGUSC.fp.matriz_risco_consolidada
GROUP BY CLASSIFICACAO_RISCO
ORDER BY Media_Score DESC;
