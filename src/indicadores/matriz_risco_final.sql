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
IF OBJECT_ID('temp_CGUSC.fp.Matriz_Risco_Final', 'U') IS NOT NULL
BEGIN
    DROP TABLE temp_CGUSC.fp.Matriz_Risco_Final;
    PRINT '   > Tabela anterior removida.';
END;

-- 2. CTE 1: CONSOLIDAÇÃO DOS DADOS BRUTOS (VALORES REAIS PARA EXIBIÇÃO)
;WITH IndicadoresPresenca AS (
    SELECT 
        F.cnpj,
        F.razaoSocial,
        F.nomeFantasia,
        CAST(F.municipio AS VARCHAR(255)) AS municipio,
        CAST(F.uf AS VARCHAR(2)) AS uf,
        F.situacaoCadastral,
        
        -- POPULAÇÃO
        ISNULL(F.populacao2019, 0) AS populacao,

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
        CASE WHEN I10.cnpj IS NOT NULL THEN 1 ELSE 0 END AS tem_madrugada,
        CASE WHEN I11.cnpj IS NOT NULL THEN 1 ELSE 0 END AS tem_geografico,
        CASE WHEN I12.cnpj IS NOT NULL THEN 1 ELSE 0 END AS tem_alto_custo,
        CASE WHEN I13.cnpj IS NOT NULL THEN 1 ELSE 0 END AS tem_pico,
        CASE WHEN I14.cnpj IS NOT NULL THEN 1 ELSE 0 END AS tem_fantasma,
        CASE WHEN I15.cnpj IS NOT NULL THEN 1 ELSE 0 END AS tem_crm,
        CASE WHEN I16.cnpj IS NOT NULL THEN 1 ELSE 0 END AS tem_exclusividade_crm,
        CASE WHEN I17.cnpj IS NOT NULL THEN 1 ELSE 0 END AS tem_crms_irregulares,
        
        -- ====================================================================================
        -- DADOS ORIGINAIS REAIS (SEM TETO AQUI - PARA EXIBIÇÃO NO RELATÓRIO)
        -- ====================================================================================
        
        I01.percentual_falecidos AS pct_falecidos,
        I01.media_estado AS avg_falecidos_uf, I01.media_pais AS avg_falecidos_br,
        I01.risco_relativo_uf AS risco_falecidos_uf, I01.risco_relativo_br AS risco_falecidos_br,
        
        I02.percentual_demografico AS pct_clinico,
        I02.media_estado AS avg_clinico_uf, I02.media_pais AS avg_clinico_br,
        I02.risco_relativo_uf AS risco_clinico_uf, I02.risco_relativo_br AS risco_clinico_br,

        I03.percentual_teto AS pct_teto,
        I03.media_estado AS avg_teto_uf, I03.media_pais AS avg_teto_br,
        I03.risco_relativo_uf AS risco_teto_uf, I03.risco_relativo_br AS risco_teto_br,

        I04.percentual_polimedicamento AS pct_polimedicamento,
        I04.media_estado AS avg_polimedicamento_uf, I04.media_pais AS avg_polimedicamento_br,
        I04.risco_relativo_uf AS risco_polimedicamento_uf, I04.risco_relativo_br AS risco_polimedicamento_br,

        I05.media_itens_autorizacao AS val_media_itens,
        I05.media_estado AS avg_media_itens_uf, I05.media_pais AS avg_media_itens_br,
        I05.risco_relativo_uf AS risco_media_itens_uf, I05.risco_relativo_br AS risco_media_itens_br,

        I06.valor_ticket_medio AS val_ticket_medio,
        I06.media_estado AS avg_ticket_uf, I06.media_pais AS avg_ticket_br,
        I06.risco_relativo_uf AS risco_ticket_uf, I06.risco_relativo_br AS risco_ticket_br,

        I07.receita_por_paciente_mensal AS val_receita_paciente,
        I07.media_mensal_estado AS avg_receita_paciente_uf, I07.media_mensal_pais AS avg_receita_paciente_br,
        I07.risco_relativo_uf AS risco_receita_paciente_uf, I07.risco_relativo_br AS risco_receita_paciente_br,

        I08.valor_per_capita_mensal AS val_per_capita,
        I08.media_mensal_estado AS avg_per_capita_uf, I08.media_mensal_pais AS avg_per_capita_br,
        I08.risco_relativo_uf AS risco_per_capita_uf, I08.risco_relativo_br AS risco_per_capita_br,

        I09.percentual_vendas_consecutivas AS pct_vendas_rapidas,
        I09.media_estado AS avg_vendas_rapidas_uf, I09.media_pais AS avg_vendas_rapidas_br,
        I09.risco_relativo_uf AS risco_vendas_rapidas_uf, I09.risco_relativo_br AS risco_vendas_rapidas_br,

        I10.percentual_madrugada AS pct_madrugada,
        I10.media_estado AS avg_madrugada_uf, I10.media_pais AS avg_madrugada_br,
        I10.risco_relativo_uf AS risco_madrugada_uf, I10.risco_relativo_br AS risco_madrugada_br,

        I11.percentual_geografico AS pct_geografico,
        I11.media_estado AS avg_geografico_uf, I11.media_pais AS avg_geografico_br,
        I11.risco_relativo_uf AS risco_geografico_uf, I11.risco_relativo_br AS risco_geografico_br,

        I12.percentual_alto_custo AS pct_alto_custo,
        I12.media_estado AS avg_alto_custo_uf, I12.media_pais AS avg_alto_custo_br,
        I12.risco_relativo_uf AS risco_alto_custo_uf, I12.risco_relativo_br AS risco_alto_custo_br,

        I13.percentual_concentracao_pico AS pct_pico,
        I13.media_estado AS avg_pico_uf, I13.media_pais AS avg_pico_br,
        I13.risco_relativo_uf AS risco_pico_uf, I13.risco_relativo_br AS risco_pico_br,

        I14.percentual_pacientes_unicos AS pct_pacientes_unicos,
        I14.media_estado AS avg_pacientes_unicos_uf, I14.media_pais AS avg_pacientes_unicos_br,
        I14.risco_relativo_uf AS risco_pacientes_unicos_uf, I14.risco_relativo_br AS risco_pacientes_unicos_br,

        CAST(I15.indice_hhi AS DECIMAL(18,2)) AS val_hhi_crm,
        CAST(I15.media_hhi_uf AS DECIMAL(18,2)) AS avg_hhi_crm_uf, CAST(I15.media_hhi_br AS DECIMAL(18,2)) AS avg_hhi_crm_br,
        I15.risco_hhi_uf AS risco_crm_uf, I15.risco_hhi_br AS risco_crm_br,

        I16.percentual_exclusividade AS pct_exclusividade_crm,
        I16.media_estado AS avg_exclusividade_crm_uf, I16.media_pais AS avg_exclusividade_crm_br,
        I16.risco_relativo_uf AS risco_exclusividade_crm_uf, I16.risco_relativo_br AS risco_exclusividade_crm_br,

        I17.pct_risco_irregularidade AS pct_crms_irregulares,
        I17.media_estado AS avg_crms_irregulares_uf, I17.media_pais AS avg_crms_irregulares_br,
        I17.risco_relativo_uf AS risco_crms_irregulares_uf, I17.risco_relativo_br AS risco_crms_irregulares_br
        
    FROM temp_CGUSC.fp.dadosFarmaciasFP F
    LEFT JOIN temp_CGUSC.fp.indicadorFalecidos_Completo I01 ON I01.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicadorDemografico_Completo I02 ON I02.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicadorTeto_Completo I03 ON I03.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicadorPolimedicamento_Completo I04 ON I04.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicadorMediaItens_Completo I05 ON I05.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicadorTicketMedio_Completo I06 ON I06.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicadorReceitaPorPaciente_Completo I07 ON I07.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicadorVendaPerCapita_Completo I08 ON I08.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicadorVendasConsecutivas_Completo I09 ON I09.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicadorHorarioAtipico_Completo I10 ON I10.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicadorGeografico_Completo I11 ON I11.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicadorAltoCusto_Completo I12 ON I12.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicadorConcentracaoPico_Completo I13 ON I13.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicadorPacientesUnicos_Completo I14 ON I14.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicadorCRM_Completo I15 ON I15.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicadorExclusividadeCRM_Completo I16 ON I16.cnpj = F.cnpj
    LEFT JOIN temp_CGUSC.fp.indicadorCRMsIrregulares_Completo I17 ON I17.cnpj = F.cnpj
),

-- 3. CTE 2: CÁLCULO DE SCORE COM TETO (AQUI É A MÁGICA)
RiscosAjustados AS (
    SELECT 
        *,
        (tem_falecidos + tem_clinico + tem_teto + tem_polimedicamento + tem_media_itens + 
         tem_ticket + tem_receita_paciente + tem_per_capita + tem_vendas_rapidas + 
         tem_madrugada + tem_geografico + tem_alto_custo + tem_pico + tem_fantasma + 
         tem_crm + tem_exclusividade_crm + tem_crms_irregulares) AS qtd_indicadores_preenchidos,
        
        -- LÓGICA DO TETO: "CASE WHEN risco > 10 THEN 10 ELSE risco END" aplicado APENAS NO CÁLCULO
        
        -- 1. FALECIDOS
        CASE 
            WHEN tem_falecidos=1 AND (CASE WHEN risco_falecidos_uf > 10 THEN 10 ELSE ISNULL(risco_falecidos_uf,0) END) >= 5 THEN (CASE WHEN risco_falecidos_uf > 10 THEN 10 ELSE ISNULL(risco_falecidos_uf,0) END) * 3
            WHEN tem_falecidos=1 AND (CASE WHEN risco_falecidos_uf > 10 THEN 10 ELSE ISNULL(risco_falecidos_uf,0) END) >= 3 THEN (CASE WHEN risco_falecidos_uf > 10 THEN 10 ELSE ISNULL(risco_falecidos_uf,0) END) * 2
            WHEN tem_falecidos=1 AND (CASE WHEN risco_falecidos_uf > 10 THEN 10 ELSE ISNULL(risco_falecidos_uf,0) END) >= 1.5 THEN (CASE WHEN risco_falecidos_uf > 10 THEN 10 ELSE ISNULL(risco_falecidos_uf,0) END) * 1.5
            ELSE (CASE WHEN risco_falecidos_uf > 10 THEN 10 ELSE ISNULL(risco_falecidos_uf,0) END) 
        END AS risco_falecidos_ajustado,
        CASE WHEN tem_falecidos=1 AND (CASE WHEN risco_falecidos_uf > 10 THEN 10 ELSE ISNULL(risco_falecidos_uf,0) END) >= 5 THEN 1 ELSE 0 END AS flag_falecidos_critico,
        
        -- 2. CLÍNICO
        CASE 
            WHEN tem_clinico=1 AND (CASE WHEN risco_clinico_uf > 10 THEN 10 ELSE ISNULL(risco_clinico_uf,0) END) >= 5 THEN (CASE WHEN risco_clinico_uf > 10 THEN 10 ELSE ISNULL(risco_clinico_uf,0) END) * 3
            WHEN tem_clinico=1 AND (CASE WHEN risco_clinico_uf > 10 THEN 10 ELSE ISNULL(risco_clinico_uf,0) END) >= 3 THEN (CASE WHEN risco_clinico_uf > 10 THEN 10 ELSE ISNULL(risco_clinico_uf,0) END) * 2
            WHEN tem_clinico=1 AND (CASE WHEN risco_clinico_uf > 10 THEN 10 ELSE ISNULL(risco_clinico_uf,0) END) >= 1.5 THEN (CASE WHEN risco_clinico_uf > 10 THEN 10 ELSE ISNULL(risco_clinico_uf,0) END) * 1.5
            ELSE (CASE WHEN risco_clinico_uf > 10 THEN 10 ELSE ISNULL(risco_clinico_uf,0) END) 
        END AS risco_clinico_ajustado,
        CASE WHEN tem_clinico=1 AND (CASE WHEN risco_clinico_uf > 10 THEN 10 ELSE ISNULL(risco_clinico_uf,0) END) >= 5 THEN 1 ELSE 0 END AS flag_clinico_critico,
        
        -- 3. TETO
        CASE 
            WHEN tem_teto=1 AND (CASE WHEN risco_teto_uf > 10 THEN 10 ELSE ISNULL(risco_teto_uf,0) END) >= 5 THEN (CASE WHEN risco_teto_uf > 10 THEN 10 ELSE ISNULL(risco_teto_uf,0) END) * 3
            WHEN tem_teto=1 AND (CASE WHEN risco_teto_uf > 10 THEN 10 ELSE ISNULL(risco_teto_uf,0) END) >= 3 THEN (CASE WHEN risco_teto_uf > 10 THEN 10 ELSE ISNULL(risco_teto_uf,0) END) * 2
            WHEN tem_teto=1 AND (CASE WHEN risco_teto_uf > 10 THEN 10 ELSE ISNULL(risco_teto_uf,0) END) >= 1.5 THEN (CASE WHEN risco_teto_uf > 10 THEN 10 ELSE ISNULL(risco_teto_uf,0) END) * 1.5
            ELSE (CASE WHEN risco_teto_uf > 10 THEN 10 ELSE ISNULL(risco_teto_uf,0) END) 
        END AS risco_teto_ajustado,
        CASE WHEN tem_teto=1 AND (CASE WHEN risco_teto_uf > 10 THEN 10 ELSE ISNULL(risco_teto_uf,0) END) >= 5 THEN 1 ELSE 0 END AS flag_teto_critico,

        -- 4. POLIMEDICAMENTO
        CASE 
            WHEN tem_polimedicamento=1 AND (CASE WHEN risco_polimedicamento_uf > 10 THEN 10 ELSE ISNULL(risco_polimedicamento_uf,0) END) >= 5 THEN (CASE WHEN risco_polimedicamento_uf > 10 THEN 10 ELSE ISNULL(risco_polimedicamento_uf,0) END) * 3
            WHEN tem_polimedicamento=1 AND (CASE WHEN risco_polimedicamento_uf > 10 THEN 10 ELSE ISNULL(risco_polimedicamento_uf,0) END) >= 3 THEN (CASE WHEN risco_polimedicamento_uf > 10 THEN 10 ELSE ISNULL(risco_polimedicamento_uf,0) END) * 2
            WHEN tem_polimedicamento=1 AND (CASE WHEN risco_polimedicamento_uf > 10 THEN 10 ELSE ISNULL(risco_polimedicamento_uf,0) END) >= 1.5 THEN (CASE WHEN risco_polimedicamento_uf > 10 THEN 10 ELSE ISNULL(risco_polimedicamento_uf,0) END) * 1.5
            ELSE (CASE WHEN risco_polimedicamento_uf > 10 THEN 10 ELSE ISNULL(risco_polimedicamento_uf,0) END) 
        END AS risco_polimedicamento_ajustado,
        CASE WHEN tem_polimedicamento=1 AND (CASE WHEN risco_polimedicamento_uf > 10 THEN 10 ELSE ISNULL(risco_polimedicamento_uf,0) END) >= 5 THEN 1 ELSE 0 END AS flag_polimedicamento_critico,

        -- 5. MEDIA ITENS
        CASE 
            WHEN tem_media_itens=1 AND (CASE WHEN risco_media_itens_uf > 10 THEN 10 ELSE ISNULL(risco_media_itens_uf,0) END) >= 5 THEN (CASE WHEN risco_media_itens_uf > 10 THEN 10 ELSE ISNULL(risco_media_itens_uf,0) END) * 3
            WHEN tem_media_itens=1 AND (CASE WHEN risco_media_itens_uf > 10 THEN 10 ELSE ISNULL(risco_media_itens_uf,0) END) >= 3 THEN (CASE WHEN risco_media_itens_uf > 10 THEN 10 ELSE ISNULL(risco_media_itens_uf,0) END) * 2
            WHEN tem_media_itens=1 AND (CASE WHEN risco_media_itens_uf > 10 THEN 10 ELSE ISNULL(risco_media_itens_uf,0) END) >= 1.5 THEN (CASE WHEN risco_media_itens_uf > 10 THEN 10 ELSE ISNULL(risco_media_itens_uf,0) END) * 1.5
            ELSE (CASE WHEN risco_media_itens_uf > 10 THEN 10 ELSE ISNULL(risco_media_itens_uf,0) END) 
        END AS risco_media_itens_ajustado,
        CASE WHEN tem_media_itens=1 AND (CASE WHEN risco_media_itens_uf > 10 THEN 10 ELSE ISNULL(risco_media_itens_uf,0) END) >= 5 THEN 1 ELSE 0 END AS flag_media_itens_critico,

        -- 6. TICKET
        CASE 
            WHEN tem_ticket=1 AND (CASE WHEN risco_ticket_uf > 10 THEN 10 ELSE ISNULL(risco_ticket_uf,0) END) >= 5 THEN (CASE WHEN risco_ticket_uf > 10 THEN 10 ELSE ISNULL(risco_ticket_uf,0) END) * 3
            WHEN tem_ticket=1 AND (CASE WHEN risco_ticket_uf > 10 THEN 10 ELSE ISNULL(risco_ticket_uf,0) END) >= 3 THEN (CASE WHEN risco_ticket_uf > 10 THEN 10 ELSE ISNULL(risco_ticket_uf,0) END) * 2
            WHEN tem_ticket=1 AND (CASE WHEN risco_ticket_uf > 10 THEN 10 ELSE ISNULL(risco_ticket_uf,0) END) >= 1.5 THEN (CASE WHEN risco_ticket_uf > 10 THEN 10 ELSE ISNULL(risco_ticket_uf,0) END) * 1.5
            ELSE (CASE WHEN risco_ticket_uf > 10 THEN 10 ELSE ISNULL(risco_ticket_uf,0) END) 
        END AS risco_ticket_ajustado,
        CASE WHEN tem_ticket=1 AND (CASE WHEN risco_ticket_uf > 10 THEN 10 ELSE ISNULL(risco_ticket_uf,0) END) >= 5 THEN 1 ELSE 0 END AS flag_ticket_critico,

        -- 7. RECEITA PACIENTE
        CASE 
            WHEN tem_receita_paciente=1 AND (CASE WHEN risco_receita_paciente_uf > 10 THEN 10 ELSE ISNULL(risco_receita_paciente_uf,0) END) >= 5 THEN (CASE WHEN risco_receita_paciente_uf > 10 THEN 10 ELSE ISNULL(risco_receita_paciente_uf,0) END) * 3
            WHEN tem_receita_paciente=1 AND (CASE WHEN risco_receita_paciente_uf > 10 THEN 10 ELSE ISNULL(risco_receita_paciente_uf,0) END) >= 3 THEN (CASE WHEN risco_receita_paciente_uf > 10 THEN 10 ELSE ISNULL(risco_receita_paciente_uf,0) END) * 2
            WHEN tem_receita_paciente=1 AND (CASE WHEN risco_receita_paciente_uf > 10 THEN 10 ELSE ISNULL(risco_receita_paciente_uf,0) END) >= 1.5 THEN (CASE WHEN risco_receita_paciente_uf > 10 THEN 10 ELSE ISNULL(risco_receita_paciente_uf,0) END) * 1.5
            ELSE (CASE WHEN risco_receita_paciente_uf > 10 THEN 10 ELSE ISNULL(risco_receita_paciente_uf,0) END) 
        END AS risco_receita_paciente_ajustado,
        CASE WHEN tem_receita_paciente=1 AND (CASE WHEN risco_receita_paciente_uf > 10 THEN 10 ELSE ISNULL(risco_receita_paciente_uf,0) END) >= 5 THEN 1 ELSE 0 END AS flag_receita_paciente_critico,

        -- 8. PER CAPITA
        CASE 
            WHEN tem_per_capita=1 AND (CASE WHEN risco_per_capita_uf > 10 THEN 10 ELSE ISNULL(risco_per_capita_uf,0) END) >= 5 THEN (CASE WHEN risco_per_capita_uf > 10 THEN 10 ELSE ISNULL(risco_per_capita_uf,0) END) * 3
            WHEN tem_per_capita=1 AND (CASE WHEN risco_per_capita_uf > 10 THEN 10 ELSE ISNULL(risco_per_capita_uf,0) END) >= 3 THEN (CASE WHEN risco_per_capita_uf > 10 THEN 10 ELSE ISNULL(risco_per_capita_uf,0) END) * 2
            WHEN tem_per_capita=1 AND (CASE WHEN risco_per_capita_uf > 10 THEN 10 ELSE ISNULL(risco_per_capita_uf,0) END) >= 1.5 THEN (CASE WHEN risco_per_capita_uf > 10 THEN 10 ELSE ISNULL(risco_per_capita_uf,0) END) * 1.5
            ELSE (CASE WHEN risco_per_capita_uf > 10 THEN 10 ELSE ISNULL(risco_per_capita_uf,0) END) 
        END AS risco_per_capita_ajustado,
        CASE WHEN tem_per_capita=1 AND (CASE WHEN risco_per_capita_uf > 10 THEN 10 ELSE ISNULL(risco_per_capita_uf,0) END) >= 5 THEN 1 ELSE 0 END AS flag_per_capita_critico,

        -- 9. VENDAS RAPIDAS
        CASE 
            WHEN tem_vendas_rapidas=1 AND (CASE WHEN risco_vendas_rapidas_uf > 10 THEN 10 ELSE ISNULL(risco_vendas_rapidas_uf,0) END) >= 5 THEN (CASE WHEN risco_vendas_rapidas_uf > 10 THEN 10 ELSE ISNULL(risco_vendas_rapidas_uf,0) END) * 3
            WHEN tem_vendas_rapidas=1 AND (CASE WHEN risco_vendas_rapidas_uf > 10 THEN 10 ELSE ISNULL(risco_vendas_rapidas_uf,0) END) >= 3 THEN (CASE WHEN risco_vendas_rapidas_uf > 10 THEN 10 ELSE ISNULL(risco_vendas_rapidas_uf,0) END) * 2
            WHEN tem_vendas_rapidas=1 AND (CASE WHEN risco_vendas_rapidas_uf > 10 THEN 10 ELSE ISNULL(risco_vendas_rapidas_uf,0) END) >= 1.5 THEN (CASE WHEN risco_vendas_rapidas_uf > 10 THEN 10 ELSE ISNULL(risco_vendas_rapidas_uf,0) END) * 1.5
            ELSE (CASE WHEN risco_vendas_rapidas_uf > 10 THEN 10 ELSE ISNULL(risco_vendas_rapidas_uf,0) END) 
        END AS risco_vendas_rapidas_ajustado,
        CASE WHEN tem_vendas_rapidas=1 AND (CASE WHEN risco_vendas_rapidas_uf > 10 THEN 10 ELSE ISNULL(risco_vendas_rapidas_uf,0) END) >= 5 THEN 1 ELSE 0 END AS flag_vendas_rapidas_critico,

        -- 10. MADRUGADA
        CASE 
            WHEN tem_madrugada=1 AND (CASE WHEN risco_madrugada_uf > 10 THEN 10 ELSE ISNULL(risco_madrugada_uf,0) END) >= 5 THEN (CASE WHEN risco_madrugada_uf > 10 THEN 10 ELSE ISNULL(risco_madrugada_uf,0) END) * 3
            WHEN tem_madrugada=1 AND (CASE WHEN risco_madrugada_uf > 10 THEN 10 ELSE ISNULL(risco_madrugada_uf,0) END) >= 3 THEN (CASE WHEN risco_madrugada_uf > 10 THEN 10 ELSE ISNULL(risco_madrugada_uf,0) END) * 2
            WHEN tem_madrugada=1 AND (CASE WHEN risco_madrugada_uf > 10 THEN 10 ELSE ISNULL(risco_madrugada_uf,0) END) >= 1.5 THEN (CASE WHEN risco_madrugada_uf > 10 THEN 10 ELSE ISNULL(risco_madrugada_uf,0) END) * 1.5
            ELSE (CASE WHEN risco_madrugada_uf > 10 THEN 10 ELSE ISNULL(risco_madrugada_uf,0) END) 
        END AS risco_madrugada_ajustado,
        CASE WHEN tem_madrugada=1 AND (CASE WHEN risco_madrugada_uf > 10 THEN 10 ELSE ISNULL(risco_madrugada_uf,0) END) >= 5 THEN 1 ELSE 0 END AS flag_madrugada_critico,

        -- 11. GEOGRAFICO
        CASE 
            WHEN tem_geografico=1 AND (CASE WHEN risco_geografico_uf > 10 THEN 10 ELSE ISNULL(risco_geografico_uf,0) END) >= 5 THEN (CASE WHEN risco_geografico_uf > 10 THEN 10 ELSE ISNULL(risco_geografico_uf,0) END) * 3
            WHEN tem_geografico=1 AND (CASE WHEN risco_geografico_uf > 10 THEN 10 ELSE ISNULL(risco_geografico_uf,0) END) >= 3 THEN (CASE WHEN risco_geografico_uf > 10 THEN 10 ELSE ISNULL(risco_geografico_uf,0) END) * 2
            WHEN tem_geografico=1 AND (CASE WHEN risco_geografico_uf > 10 THEN 10 ELSE ISNULL(risco_geografico_uf,0) END) >= 1.5 THEN (CASE WHEN risco_geografico_uf > 10 THEN 10 ELSE ISNULL(risco_geografico_uf,0) END) * 1.5
            ELSE (CASE WHEN risco_geografico_uf > 10 THEN 10 ELSE ISNULL(risco_geografico_uf,0) END) 
        END AS risco_geografico_ajustado,
        CASE WHEN tem_geografico=1 AND (CASE WHEN risco_geografico_uf > 10 THEN 10 ELSE ISNULL(risco_geografico_uf,0) END) >= 5 THEN 1 ELSE 0 END AS flag_geografico_critico,

        -- 12. ALTO CUSTO
        CASE 
            WHEN tem_alto_custo=1 AND (CASE WHEN risco_alto_custo_uf > 10 THEN 10 ELSE ISNULL(risco_alto_custo_uf,0) END) >= 5 THEN (CASE WHEN risco_alto_custo_uf > 10 THEN 10 ELSE ISNULL(risco_alto_custo_uf,0) END) * 3
            WHEN tem_alto_custo=1 AND (CASE WHEN risco_alto_custo_uf > 10 THEN 10 ELSE ISNULL(risco_alto_custo_uf,0) END) >= 3 THEN (CASE WHEN risco_alto_custo_uf > 10 THEN 10 ELSE ISNULL(risco_alto_custo_uf,0) END) * 2
            WHEN tem_alto_custo=1 AND (CASE WHEN risco_alto_custo_uf > 10 THEN 10 ELSE ISNULL(risco_alto_custo_uf,0) END) >= 1.5 THEN (CASE WHEN risco_alto_custo_uf > 10 THEN 10 ELSE ISNULL(risco_alto_custo_uf,0) END) * 1.5
            ELSE (CASE WHEN risco_alto_custo_uf > 10 THEN 10 ELSE ISNULL(risco_alto_custo_uf,0) END) 
        END AS risco_alto_custo_ajustado,
        CASE WHEN tem_alto_custo=1 AND (CASE WHEN risco_alto_custo_uf > 10 THEN 10 ELSE ISNULL(risco_alto_custo_uf,0) END) >= 5 THEN 1 ELSE 0 END AS flag_alto_custo_critico,

        -- 13. PICO
        CASE 
            WHEN tem_pico=1 AND (CASE WHEN risco_pico_uf > 10 THEN 10 ELSE ISNULL(risco_pico_uf,0) END) >= 5 THEN (CASE WHEN risco_pico_uf > 10 THEN 10 ELSE ISNULL(risco_pico_uf,0) END) * 3
            WHEN tem_pico=1 AND (CASE WHEN risco_pico_uf > 10 THEN 10 ELSE ISNULL(risco_pico_uf,0) END) >= 3 THEN (CASE WHEN risco_pico_uf > 10 THEN 10 ELSE ISNULL(risco_pico_uf,0) END) * 2
            WHEN tem_pico=1 AND (CASE WHEN risco_pico_uf > 10 THEN 10 ELSE ISNULL(risco_pico_uf,0) END) >= 1.5 THEN (CASE WHEN risco_pico_uf > 10 THEN 10 ELSE ISNULL(risco_pico_uf,0) END) * 1.5
            ELSE (CASE WHEN risco_pico_uf > 10 THEN 10 ELSE ISNULL(risco_pico_uf,0) END) 
        END AS risco_pico_ajustado,
        CASE WHEN tem_pico=1 AND (CASE WHEN risco_pico_uf > 10 THEN 10 ELSE ISNULL(risco_pico_uf,0) END) >= 5 THEN 1 ELSE 0 END AS flag_pico_critico,

        -- 14. PACIENTES UNICOS (FANTASMA)
        CASE 
            WHEN tem_fantasma=1 AND (CASE WHEN risco_pacientes_unicos_uf > 10 THEN 10 ELSE ISNULL(risco_pacientes_unicos_uf,0) END) >= 5 THEN (CASE WHEN risco_pacientes_unicos_uf > 10 THEN 10 ELSE ISNULL(risco_pacientes_unicos_uf,0) END) * 3
            WHEN tem_fantasma=1 AND (CASE WHEN risco_pacientes_unicos_uf > 10 THEN 10 ELSE ISNULL(risco_pacientes_unicos_uf,0) END) >= 3 THEN (CASE WHEN risco_pacientes_unicos_uf > 10 THEN 10 ELSE ISNULL(risco_pacientes_unicos_uf,0) END) * 2
            WHEN tem_fantasma=1 AND (CASE WHEN risco_pacientes_unicos_uf > 10 THEN 10 ELSE ISNULL(risco_pacientes_unicos_uf,0) END) >= 1.5 THEN (CASE WHEN risco_pacientes_unicos_uf > 10 THEN 10 ELSE ISNULL(risco_pacientes_unicos_uf,0) END) * 1.5
            ELSE (CASE WHEN risco_pacientes_unicos_uf > 10 THEN 10 ELSE ISNULL(risco_pacientes_unicos_uf,0) END) 
        END AS risco_pacientes_unicos_ajustado,
        CASE WHEN tem_fantasma=1 AND (CASE WHEN risco_pacientes_unicos_uf > 10 THEN 10 ELSE ISNULL(risco_pacientes_unicos_uf,0) END) >= 5 THEN 1 ELSE 0 END AS flag_pacientes_unicos_critico,

        -- 15. CRM HHI
        CASE 
            WHEN tem_crm=1 AND (CASE WHEN risco_crm_uf > 10 THEN 10 ELSE ISNULL(risco_crm_uf,0) END) >= 5 THEN (CASE WHEN risco_crm_uf > 10 THEN 10 ELSE ISNULL(risco_crm_uf,0) END) * 3
            WHEN tem_crm=1 AND (CASE WHEN risco_crm_uf > 10 THEN 10 ELSE ISNULL(risco_crm_uf,0) END) >= 3 THEN (CASE WHEN risco_crm_uf > 10 THEN 10 ELSE ISNULL(risco_crm_uf,0) END) * 2
            WHEN tem_crm=1 AND (CASE WHEN risco_crm_uf > 10 THEN 10 ELSE ISNULL(risco_crm_uf,0) END) >= 1.5 THEN (CASE WHEN risco_crm_uf > 10 THEN 10 ELSE ISNULL(risco_crm_uf,0) END) * 1.5
            ELSE (CASE WHEN risco_crm_uf > 10 THEN 10 ELSE ISNULL(risco_crm_uf,0) END) 
        END AS risco_crm_ajustado,
        CASE WHEN tem_crm=1 AND (CASE WHEN risco_crm_uf > 10 THEN 10 ELSE ISNULL(risco_crm_uf,0) END) >= 5 THEN 1 ELSE 0 END AS flag_crm_critico,

        -- 16. EXCLUSIVIDADE CRM
        CASE 
            WHEN tem_exclusividade_crm=1 AND (CASE WHEN risco_exclusividade_crm_uf > 10 THEN 10 ELSE ISNULL(risco_exclusividade_crm_uf,0) END) >= 5 THEN (CASE WHEN risco_exclusividade_crm_uf > 10 THEN 10 ELSE ISNULL(risco_exclusividade_crm_uf,0) END) * 3
            WHEN tem_exclusividade_crm=1 AND (CASE WHEN risco_exclusividade_crm_uf > 10 THEN 10 ELSE ISNULL(risco_exclusividade_crm_uf,0) END) >= 3 THEN (CASE WHEN risco_exclusividade_crm_uf > 10 THEN 10 ELSE ISNULL(risco_exclusividade_crm_uf,0) END) * 2
            WHEN tem_exclusividade_crm=1 AND (CASE WHEN risco_exclusividade_crm_uf > 10 THEN 10 ELSE ISNULL(risco_exclusividade_crm_uf,0) END) >= 1.5 THEN (CASE WHEN risco_exclusividade_crm_uf > 10 THEN 10 ELSE ISNULL(risco_exclusividade_crm_uf,0) END) * 1.5
            ELSE (CASE WHEN risco_exclusividade_crm_uf > 10 THEN 10 ELSE ISNULL(risco_exclusividade_crm_uf,0) END) 
        END AS risco_exclusividade_crm_ajustado,
        CASE WHEN tem_exclusividade_crm=1 AND (CASE WHEN risco_exclusividade_crm_uf > 10 THEN 10 ELSE ISNULL(risco_exclusividade_crm_uf,0) END) >= 5 THEN 1 ELSE 0 END AS flag_exclusividade_crm_critico,

        -- 17. CRMS IRREGULARES
        CASE 
            WHEN tem_crms_irregulares=1 AND (CASE WHEN risco_crms_irregulares_uf > 10 THEN 10 ELSE ISNULL(risco_crms_irregulares_uf,0) END) >= 5 THEN (CASE WHEN risco_crms_irregulares_uf > 10 THEN 10 ELSE ISNULL(risco_crms_irregulares_uf,0) END) * 3
            WHEN tem_crms_irregulares=1 AND (CASE WHEN risco_crms_irregulares_uf > 10 THEN 10 ELSE ISNULL(risco_crms_irregulares_uf,0) END) >= 3 THEN (CASE WHEN risco_crms_irregulares_uf > 10 THEN 10 ELSE ISNULL(risco_crms_irregulares_uf,0) END) * 2
            WHEN tem_crms_irregulares=1 AND (CASE WHEN risco_crms_irregulares_uf > 10 THEN 10 ELSE ISNULL(risco_crms_irregulares_uf,0) END) >= 1.5 THEN (CASE WHEN risco_crms_irregulares_uf > 10 THEN 10 ELSE ISNULL(risco_crms_irregulares_uf,0) END) * 1.5
            ELSE (CASE WHEN risco_crms_irregulares_uf > 10 THEN 10 ELSE ISNULL(risco_crms_irregulares_uf,0) END) 
        END AS risco_crms_irregulares_ajustado,
        CASE WHEN tem_crms_irregulares=1 AND (CASE WHEN risco_crms_irregulares_uf > 10 THEN 10 ELSE ISNULL(risco_crms_irregulares_uf,0) END) >= 5 THEN 1 ELSE 0 END AS flag_crms_irregulares_critico

    FROM IndicadoresPresenca
),

-- 4. CTE 3: CONSOLIDAÇÃO DOS RISCOS (SOMA)
ScoreCalculado AS (
    SELECT 
        *,
        CAST(qtd_indicadores_preenchidos * 100.0 / 17.0 AS DECIMAL(5,2)) AS pct_completude,
        
        -- Soma dos riscos ajustados (JÁ COM TETO APLICADO NA ETAPA ANTERIOR)
        (risco_falecidos_ajustado + risco_clinico_ajustado + risco_teto_ajustado +
         risco_polimedicamento_ajustado + risco_media_itens_ajustado + risco_ticket_ajustado +
         risco_receita_paciente_ajustado + risco_per_capita_ajustado + risco_vendas_rapidas_ajustado +
         risco_madrugada_ajustado + risco_geografico_ajustado + risco_alto_custo_ajustado +
         risco_pico_ajustado + risco_pacientes_unicos_ajustado + risco_crm_ajustado +
         risco_exclusividade_crm_ajustado + risco_crms_irregulares_ajustado
        ) AS soma_riscos_ajustados,
        
        -- Contagem de flags críticos
        (flag_falecidos_critico + flag_clinico_critico + flag_teto_critico +
         flag_polimedicamento_critico + flag_media_itens_critico + flag_ticket_critico +
         flag_receita_paciente_critico + flag_per_capita_critico + flag_vendas_rapidas_critico +
         flag_madrugada_critico + flag_geografico_critico + flag_alto_custo_critico +
         flag_pico_critico + flag_pacientes_unicos_critico + flag_crm_critico +
         flag_exclusividade_crm_critico + flag_crms_irregulares_critico
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
            THEN soma_riscos_ajustados / (qtd_indicadores_preenchidos * 1.0) ELSE 0 END 
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
        LTRIM(RTRIM(
            CASE WHEN flag_falecidos_critico = 1 THEN 'Falecidos, ' ELSE '' END +
            CASE WHEN flag_clinico_critico = 1 THEN 'Clínico, ' ELSE '' END +
            CASE WHEN flag_teto_critico = 1 THEN 'Teto, ' ELSE '' END +
            CASE WHEN flag_polimedicamento_critico = 1 THEN 'Polimedicamento, ' ELSE '' END +
            CASE WHEN flag_media_itens_critico = 1 THEN 'Média Itens, ' ELSE '' END +
            CASE WHEN flag_ticket_critico = 1 THEN 'Ticket Médio, ' ELSE '' END +
            CASE WHEN flag_receita_paciente_critico = 1 THEN 'Receita/Paciente, ' ELSE '' END +
            CASE WHEN flag_per_capita_critico = 1 THEN 'Per Capita, ' ELSE '' END +
            CASE WHEN flag_vendas_rapidas_critico = 1 THEN 'Vendas Rápidas, ' ELSE '' END +
            CASE WHEN flag_madrugada_critico = 1 THEN 'Madrugada, ' ELSE '' END +
            CASE WHEN flag_geografico_critico = 1 THEN 'Geográfico, ' ELSE '' END +
            CASE WHEN flag_alto_custo_critico = 1 THEN 'Alto Custo, ' ELSE '' END +
            CASE WHEN flag_pico_critico = 1 THEN 'Pico, ' ELSE '' END +
            CASE WHEN flag_pacientes_unicos_critico = 1 THEN 'Pacientes Únicos, ' ELSE '' END +
            CASE WHEN flag_crm_critico = 1 THEN 'CRM HHI, ' ELSE '' END +
            CASE WHEN flag_exclusividade_crm_critico = 1 THEN 'Exclusividade CRM, ' ELSE '' END +
            CASE WHEN flag_crms_irregulares_critico = 1 THEN 'CRMs Irregulares, ' ELSE '' END + ''
        )) AS indicadores_criticos_lista
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
    
    -- INTELIGÊNCIA MUNICIPAL
    RANK() OVER (PARTITION BY uf, municipio ORDER BY SCORE_RISCO_FINAL DESC) AS rank_municipio,
    COUNT(*) OVER (PARTITION BY uf, municipio) AS total_municipio,
    
    -- ESTATÍSTICAS LOCAIS
    CAST(AVG(SCORE_RISCO_FINAL) OVER (PARTITION BY uf, municipio) AS DECIMAL(18,2)) AS avg_score_municipio,
    CAST(MAX(SCORE_RISCO_FINAL) OVER (PARTITION BY uf, municipio) AS DECIMAL(18,2)) AS max_score_municipio,

    -- PERCENTIL
    CAST(CUME_DIST() OVER (ORDER BY SCORE_RISCO_FINAL ASC) * 100 AS DECIMAL(5,2)) AS percentil_risco

INTO temp_CGUSC.fp.Matriz_Risco_Final
FROM ClassificacaoFinal S;

PRINT '   > Tabela temp_CGUSC.fp.Matriz_Risco_Final (V5.5) criada com sucesso.';

-- ============================================================================
-- CRIAÇÃO DE ÍNDICES OTIMIZADOS
-- ============================================================================
PRINT '   > Recriando índices...';

CREATE CLUSTERED INDEX IDX_MatrizFinal_CNPJ 
    ON temp_CGUSC.fp.Matriz_Risco_Final(cnpj);

CREATE NONCLUSTERED INDEX IDX_MatrizFinal_ScoreRiscoFinal 
    ON temp_CGUSC.fp.Matriz_Risco_Final(SCORE_RISCO_FINAL DESC)
    INCLUDE (razaoSocial, uf, rank_nacional, CLASSIFICACAO_RISCO);

CREATE NONCLUSTERED INDEX IDX_MatrizFinal_Municipio 
    ON temp_CGUSC.fp.Matriz_Risco_Final(uf, municipio, SCORE_RISCO_FINAL DESC)
    INCLUDE (rank_municipio, avg_score_municipio);

PRINT '>> PROCESSO CONCLUÍDO COM SUCESSO.';
GO

-- ============================================================================
-- VALIDAÇÃO RÁPIDA
-- ============================================================================
SELECT CLASSIFICACAO_RISCO, COUNT(*) as Qtd, 
       CAST(AVG(SCORE_RISCO_FINAL) as DECIMAL(10,2)) as Media_Score,
       MIN(SCORE_RISCO_FINAL) as Min_Score,
       MAX(SCORE_RISCO_FINAL) as Max_Score
FROM temp_CGUSC.fp.Matriz_Risco_Final
GROUP BY CLASSIFICACAO_RISCO
ORDER BY Media_Score DESC;

select top 100 *  FROM temp_CGUSC.fp.Matriz_Risco_Final where municipio = 'Florianópolis' 


select top 10 * from dadosFarmaciasFP


select top 10 * from resultado_Sentinela_2015_2024


select CLASSIFICACAO_RISCO  FROM temp_CGUSC.fp.Matriz_Risco_Final group by CLASSIFICACAO_RISCO

