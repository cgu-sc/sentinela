USE [temp_CGUSC]
GO

-- ============================================================================
-- MATRIZ ANUAL DE COMPONENTES DOS INDICADORES
-- ============================================================================
-- OBJETIVO:
--   Consolidar, por id_cnpj e ano_base, os componentes brutos anuais dos
--   indicadores do Sentinela.
--
-- IMPORTANTE:
--   Esta matriz nao calcula nem persiste medianas territoriais, riscos
--   relativos, flags de atencao/critico, score, classificacao, rankings ou
--   percentis. Esses valores dependem do periodo e do universo filtrado pelo
--   usuario e devem ser calculados dinamicamente no backend/Polars.
--
-- GRAO:
--   Uma linha por id_cnpj + ano_base.
-- ============================================================================

SET NOCOUNT ON;

PRINT '>> INICIANDO GERACAO DA MATRIZ ANUAL DE COMPONENTES...';

BEGIN TRY
    BEGIN TRANSACTION;

    DROP TABLE IF EXISTS temp_CGUSC.fp.matriz_risco_consolidada;

    -- ========================================================================
    -- VALIDACOES DE CONTRATO
    -- ========================================================================
    IF OBJECT_ID('temp_CGUSC.fp.dados_farmacia', 'U') IS NULL
    BEGIN
        RAISERROR('Tabela temp_CGUSC.fp.dados_farmacia nao encontrada.', 16, 1);
        RETURN;
    END;

    IF COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'id') IS NULL
    BEGIN
        RAISERROR('Tabela temp_CGUSC.fp.dados_farmacia sem coluna obrigatoria id.', 16, 1);
        RETURN;
    END;

    IF EXISTS (
        SELECT 1
        FROM temp_CGUSC.fp.dados_farmacia
        GROUP BY id
        HAVING COUNT_BIG(*) > 1
    )
    BEGIN
        RAISERROR('Tabela temp_CGUSC.fp.dados_farmacia possui ids duplicados.', 16, 1);
        RETURN;
    END;

    IF OBJECT_ID('temp_CGUSC.fp.indicador_auditado_detalhado', 'U') IS NULL
    BEGIN
        RAISERROR('Tabela temp_CGUSC.fp.indicador_auditado_detalhado nao encontrada.', 16, 1);
        RETURN;
    END;

    DECLARE @Contrato TABLE (
        tabela SYSNAME NOT NULL,
        coluna SYSNAME NOT NULL
    );

    INSERT INTO @Contrato (tabela, coluna)
    VALUES
        ('indicador_auditado_detalhado', 'id_cnpj'),
        ('indicador_auditado_detalhado', 'ano_base'),
        ('indicador_auditado_detalhado', 'periodo_min'),
        ('indicador_auditado_detalhado', 'periodo_max'),
        ('indicador_auditado_detalhado', 'valor_total_auditado'),
        ('indicador_auditado_detalhado', 'valor_sem_comprovacao'),
        ('indicador_auditado_detalhado', 'total_caixas_vendidas'),
        ('indicador_auditado_detalhado', 'total_caixas_sem_comprovacao'),
        ('indicador_auditado_detalhado', 'total_autorizacoes'),
        ('indicador_auditado_detalhado', 'pct_auditado'),

        ('indicador_falecidos_detalhado', 'id_cnpj'),
        ('indicador_falecidos_detalhado', 'ano_base'),
        ('indicador_falecidos_detalhado', 'total_autorizacoes'),
        ('indicador_falecidos_detalhado', 'qtd_autorizacoes_falecidos'),
        ('indicador_falecidos_detalhado', 'valor_total_auditado'),
        ('indicador_falecidos_detalhado', 'valor_falecidos'),

        ('indicador_inconsistencia_clinica_detalhado', 'id_cnpj'),
        ('indicador_inconsistencia_clinica_detalhado', 'ano_base'),
        ('indicador_inconsistencia_clinica_detalhado', 'total_vendas_monitoradas'),
        ('indicador_inconsistencia_clinica_detalhado', 'qtd_vendas_suspeitas'),
        ('indicador_inconsistencia_clinica_detalhado', 'valor_vendas_monitoradas'),
        ('indicador_inconsistencia_clinica_detalhado', 'valor_vendas_suspeitas'),

        ('indicador_teto_detalhado', 'id_cnpj'),
        ('indicador_teto_detalhado', 'ano_base'),
        ('indicador_teto_detalhado', 'total_itens_monitorados'),
        ('indicador_teto_detalhado', 'total_itens_teto_maximo'),
        ('indicador_teto_detalhado', 'valor_total_auditado'),
        ('indicador_teto_detalhado', 'valor_itens_teto_maximo'),

        ('indicador_polimedicamento_detalhado', 'id_cnpj'),
        ('indicador_polimedicamento_detalhado', 'ano_base'),
        ('indicador_polimedicamento_detalhado', 'total_autorizacoes_monitoradas'),
        ('indicador_polimedicamento_detalhado', 'total_autorizacoes_suspeitas'),
        ('indicador_polimedicamento_detalhado', 'valor_total_auditado'),
        ('indicador_polimedicamento_detalhado', 'valor_autorizacoes_suspeitas'),

        ('indicador_ticket_medio_detalhado', 'id_cnpj'),
        ('indicador_ticket_medio_detalhado', 'ano_base'),
        ('indicador_ticket_medio_detalhado', 'valor_total_auditado'),
        ('indicador_ticket_medio_detalhado', 'total_autorizacoes'),
        ('indicador_ticket_medio_detalhado', 'valor_ticket_medio'),

        ('indicador_receita_por_paciente_detalhado', 'id_cnpj'),
        ('indicador_receita_por_paciente_detalhado', 'ano_base'),
        ('indicador_receita_por_paciente_detalhado', 'valor_total_auditado'),
        ('indicador_receita_por_paciente_detalhado', 'total_pacientes_distintos'),
        ('indicador_receita_por_paciente_detalhado', 'total_meses_ativos'),
        ('indicador_receita_por_paciente_detalhado', 'receita_por_paciente_mensal'),

        ('indicador_venda_per_capita_detalhado', 'id_cnpj'),
        ('indicador_venda_per_capita_detalhado', 'ano_base'),
        ('indicador_venda_per_capita_detalhado', 'valor_total_auditado'),
        ('indicador_venda_per_capita_detalhado', 'total_meses_ativos'),
        ('indicador_venda_per_capita_detalhado', 'populacao_municipio'),
        ('indicador_venda_per_capita_detalhado', 'denominador_per_capita'),

        ('indicador_vendas_consecutivas_detalhado', 'id_cnpj'),
        ('indicador_vendas_consecutivas_detalhado', 'ano_base'),
        ('indicador_vendas_consecutivas_detalhado', 'total_intervalos_analisados'),
        ('indicador_vendas_consecutivas_detalhado', 'total_vendas_rapidas'),
        ('indicador_vendas_consecutivas_detalhado', 'valor_total_auditado'),
        ('indicador_vendas_consecutivas_detalhado', 'valor_vendas_rapidas'),

        ('indicador_volume_atipico_detalhado', 'id_cnpj'),
        ('indicador_volume_atipico_detalhado', 'ano_base'),
        ('indicador_volume_atipico_detalhado', 'total_semestres_comparaveis'),
        ('indicador_volume_atipico_detalhado', 'total_semestres_atipicos'),
        ('indicador_volume_atipico_detalhado', 'soma_excesso_crescimento_pct'),
        ('indicador_volume_atipico_detalhado', 'valor_aumento_total'),
        ('indicador_volume_atipico_detalhado', 'valor_aumento_atipico'),
        ('indicador_volume_atipico_detalhado', 'maior_taxa_crescimento_pct'),

        ('indicador_geografico_detalhado', 'id_cnpj'),
        ('indicador_geografico_detalhado', 'ano_base'),
        ('indicador_geografico_detalhado', 'total_vendas_monitoradas'),
        ('indicador_geografico_detalhado', 'qtd_vendas_outra_uf'),
        ('indicador_geografico_detalhado', 'valor_total_auditado'),
        ('indicador_geografico_detalhado', 'valor_vendas_outra_uf'),

        ('indicador_alto_custo_detalhado', 'id_cnpj'),
        ('indicador_alto_custo_detalhado', 'ano_base'),
        ('indicador_alto_custo_detalhado', 'valor_total_auditado'),
        ('indicador_alto_custo_detalhado', 'valor_vendas_alto_custo'),

        ('indicador_concentracao_pico_detalhado', 'id_cnpj'),
        ('indicador_concentracao_pico_detalhado', 'ano_base'),
        ('indicador_concentracao_pico_detalhado', 'valor_top3_dias'),
        ('indicador_concentracao_pico_detalhado', 'valor_total_auditado'),
        ('indicador_concentracao_pico_detalhado', 'mediana_concentracao'),

        ('indicador_crm_hhi_detalhado', 'id_cnpj'),
        ('indicador_crm_hhi_detalhado', 'ano_base'),
        ('indicador_crm_hhi_detalhado', 'total_prescritores'),
        ('indicador_crm_hhi_detalhado', 'total_prescricoes'),
        ('indicador_crm_hhi_detalhado', 'valor_total_prescricoes'),
        ('indicador_crm_hhi_detalhado', 'valor_top1'),
        ('indicador_crm_hhi_detalhado', 'valor_top5'),
        ('indicador_crm_hhi_detalhado', 'participacao_top1_pct'),
        ('indicador_crm_hhi_detalhado', 'participacao_top5_pct'),
        ('indicador_crm_hhi_detalhado', 'indice_hhi'),

        ('indicador_crms_irregulares_detalhado', 'id_cnpj'),
        ('indicador_crms_irregulares_detalhado', 'ano_base'),
        ('indicador_crms_irregulares_detalhado', 'total_prescritores'),
        ('indicador_crms_irregulares_detalhado', 'total_prescricoes'),
        ('indicador_crms_irregulares_detalhado', 'valor_total_auditado'),
        ('indicador_crms_irregulares_detalhado', 'qtd_crms_nao_localizados'),
        ('indicador_crms_irregulares_detalhado', 'valor_crms_nao_localizados'),
        ('indicador_crms_irregulares_detalhado', 'qtd_crms_antes_registro'),
        ('indicador_crms_irregulares_detalhado', 'valor_crms_antes_registro'),
        ('indicador_crms_irregulares_detalhado', 'qtd_crms_irregulares'),
        ('indicador_crms_irregulares_detalhado', 'valor_crms_irregulares'),

        ('indicador_recorrencia_sistemica_detalhado', 'id_cnpj'),
        ('indicador_recorrencia_sistemica_detalhado', 'ano_base'),
        ('indicador_recorrencia_sistemica_detalhado', 'total_renovacoes_monitoradas'),
        ('indicador_recorrencia_sistemica_detalhado', 'total_renovacoes_sistemicas'),
        ('indicador_recorrencia_sistemica_detalhado', 'valor_total_auditado'),
        ('indicador_recorrencia_sistemica_detalhado', 'valor_renovacoes_sistemicas');

    IF EXISTS (
        SELECT 1
        FROM @Contrato C
        WHERE OBJECT_ID('temp_CGUSC.fp.' + C.tabela, 'U') IS NULL
    )
    BEGIN
        DECLARE @TabelaAusente NVARCHAR(MAX);

        SELECT @TabelaAusente = STRING_AGG(C.tabela, ', ')
        FROM (
            SELECT DISTINCT C.tabela
            FROM @Contrato C
            WHERE OBJECT_ID('temp_CGUSC.fp.' + C.tabela, 'U') IS NULL
        ) C;

        RAISERROR('Tabelas obrigatorias ausentes para matriz anual: %s', 16, 1, @TabelaAusente);
        RETURN;
    END;

    IF EXISTS (
        SELECT 1
        FROM @Contrato C
        WHERE COL_LENGTH('temp_CGUSC.fp.' + C.tabela, C.coluna) IS NULL
    )
    BEGIN
        DECLARE @ColunasAusentes NVARCHAR(MAX);

        SELECT @ColunasAusentes = STRING_AGG(CONCAT(C.tabela, '.', C.coluna), ', ')
        FROM @Contrato C
        WHERE COL_LENGTH('temp_CGUSC.fp.' + C.tabela, C.coluna) IS NULL;

        RAISERROR('Colunas obrigatorias ausentes para matriz anual: %s', 16, 1, @ColunasAusentes);
        RETURN;
    END;

    IF EXISTS (
        SELECT id_cnpj, ano_base
        FROM temp_CGUSC.fp.indicador_auditado_detalhado
        GROUP BY id_cnpj, ano_base
        HAVING COUNT_BIG(*) > 1
    )
    BEGIN
        RAISERROR('indicador_auditado_detalhado possui duplicidade por id_cnpj/ano_base.', 16, 1);
        RETURN;
    END;

    -- ========================================================================
    -- BASE ANUAL
    -- ========================================================================
    ;WITH BaseAnual AS (
        SELECT
            CAST(IA.id_cnpj AS INT) AS id_cnpj,
            CAST(IA.ano_base AS SMALLINT) AS ano_base,
            CAST(IA.periodo_min AS DATE) AS periodo_min,
            CAST(IA.periodo_max AS DATE) AS periodo_max
        FROM temp_CGUSC.fp.indicador_auditado_detalhado AS IA
        WHERE IA.id_cnpj IS NOT NULL
          AND IA.ano_base IS NOT NULL
    )
    SELECT
        B.id_cnpj,
        B.ano_base,
        B.periodo_min,
        B.periodo_max,

        -- Auditoria financeira
        CAST(IA.valor_total_auditado AS DECIMAL(19,2)) AS auditado_valor_total,
        CAST(IA.valor_sem_comprovacao AS DECIMAL(19,2)) AS auditado_valor_sem_comprovacao,
        CAST(IA.total_caixas_vendidas AS BIGINT) AS auditado_total_caixas,
        CAST(IA.total_caixas_sem_comprovacao AS BIGINT) AS auditado_total_caixas_sem_comprovacao,
        CAST(IA.total_autorizacoes AS BIGINT) AS auditado_total_autorizacoes,
        CAST(IA.pct_auditado AS DECIMAL(18,4)) AS pct_auditado,

        -- Falecidos
        CAST(FAL.total_autorizacoes AS INT) AS falecidos_total_autorizacoes,
        CAST(FAL.qtd_autorizacoes_falecidos AS INT) AS falecidos_qtd_autorizacoes,
        CAST(FAL.valor_total_auditado AS DECIMAL(19,2)) AS falecidos_valor_total,
        CAST(FAL.valor_falecidos AS DECIMAL(19,2)) AS falecidos_valor,
        CAST((FAL.valor_falecidos * 100.0) / NULLIF(FAL.valor_total_auditado, 0) AS DECIMAL(18,4)) AS pct_falecidos,

        -- Inconsistencia clinica
        CAST(CLI.total_vendas_monitoradas AS INT) AS clinico_total_vendas_monitoradas,
        CAST(CLI.qtd_vendas_suspeitas AS INT) AS clinico_qtd_vendas_suspeitas,
        CAST(CLI.valor_vendas_monitoradas AS DECIMAL(19,2)) AS clinico_valor_monitorado,
        CAST(CLI.valor_vendas_suspeitas AS DECIMAL(19,2)) AS clinico_valor_suspeito,
        CAST((CLI.valor_vendas_suspeitas * 100.0) / NULLIF(CLI.valor_vendas_monitoradas, 0) AS DECIMAL(18,4)) AS pct_clinico,

        -- Teto
        CAST(TET.total_itens_monitorados AS INT) AS teto_total_itens_monitorados,
        CAST(TET.total_itens_teto_maximo AS INT) AS teto_total_itens,
        CAST(TET.valor_total_auditado AS DECIMAL(19,2)) AS teto_valor_total,
        CAST(TET.valor_itens_teto_maximo AS DECIMAL(19,2)) AS teto_valor,
        CAST((TET.valor_itens_teto_maximo * 100.0) / NULLIF(TET.valor_total_auditado, 0) AS DECIMAL(18,4)) AS pct_teto,

        -- Polimedicamento
        CAST(POL.total_autorizacoes_monitoradas AS INT) AS polimedicamento_total_autorizacoes,
        CAST(POL.total_autorizacoes_suspeitas AS INT) AS polimedicamento_total_autorizacoes_4mais,
        CAST(POL.valor_total_auditado AS DECIMAL(19,2)) AS polimedicamento_valor_total,
        CAST(POL.valor_autorizacoes_suspeitas AS DECIMAL(19,2)) AS polimedicamento_valor,
        CAST((POL.valor_autorizacoes_suspeitas * 100.0) / NULLIF(POL.valor_total_auditado, 0) AS DECIMAL(18,4)) AS pct_polimedicamento,

        -- Ticket medio
        CAST(TIC.valor_total_auditado AS DECIMAL(19,2)) AS ticket_valor_total,
        CAST(TIC.total_autorizacoes AS BIGINT) AS ticket_total_autorizacoes,
        CAST(TIC.valor_ticket_medio AS DECIMAL(18,4)) AS val_ticket_medio,

        -- Receita por paciente
        CAST(RCP.valor_total_auditado AS DECIMAL(19,2)) AS receita_paciente_valor_total,
        CAST(RCP.total_pacientes_distintos AS INT) AS receita_paciente_total_pacientes_distintos,
        CAST(RCP.total_meses_ativos AS INT) AS receita_paciente_total_meses_ativos,
        CAST(RCP.receita_por_paciente_mensal AS DECIMAL(18,4)) AS val_receita_paciente,

        -- Venda per capita
        CAST(VPC.valor_total_auditado AS DECIMAL(19,2)) AS per_capita_valor_total,
        CAST(VPC.total_meses_ativos AS INT) AS per_capita_total_meses_ativos,
        CAST(VPC.populacao_municipio AS INT) AS per_capita_populacao_municipio,
        CAST(VPC.denominador_per_capita AS BIGINT) AS per_capita_denominador,
        CAST(VPC.valor_total_auditado / NULLIF(CAST(VPC.denominador_per_capita AS DECIMAL(19,4)), 0) AS DECIMAL(18,4)) AS val_per_capita,

        -- Vendas rapidas
        CAST(VR.total_intervalos_analisados AS INT) AS vendas_rapidas_total_intervalos,
        CAST(VR.total_vendas_rapidas AS INT) AS vendas_rapidas_total,
        CAST(VR.valor_total_auditado AS DECIMAL(19,2)) AS vendas_rapidas_valor_total,
        CAST(VR.valor_vendas_rapidas AS DECIMAL(19,2)) AS vendas_rapidas_valor,
        CAST((VR.valor_vendas_rapidas * 100.0) / NULLIF(VR.valor_total_auditado, 0) AS DECIMAL(18,4)) AS pct_vendas_rapidas,

        -- Volume atipico
        CAST(VA.total_semestres_comparaveis AS INT) AS volume_atipico_total_semestres_comparaveis,
        CAST(VA.total_semestres_atipicos AS INT) AS volume_atipico_total_semestres_atipicos,
        CAST(VA.soma_excesso_crescimento_pct AS DECIMAL(18,4)) AS volume_atipico_soma_excesso_crescimento_pct,
        CAST(VA.valor_aumento_total AS DECIMAL(19,2)) AS volume_atipico_valor_aumento_total,
        CAST(VA.valor_aumento_atipico AS DECIMAL(19,2)) AS volume_atipico_valor_aumento_atipico,
        CAST(VA.maior_taxa_crescimento_pct AS DECIMAL(18,4)) AS volume_atipico_maior_taxa_crescimento_pct,
        CAST(VA.soma_excesso_crescimento_pct / NULLIF(CAST(VA.total_semestres_comparaveis AS DECIMAL(18,4)), 0) AS DECIMAL(18,4)) AS val_volume_atipico,

        -- Dispersao geografica
        CAST(GEO.total_vendas_monitoradas AS INT) AS geografico_total_vendas_monitoradas,
        CAST(GEO.qtd_vendas_outra_uf AS INT) AS geografico_qtd_vendas_outra_uf,
        CAST(GEO.valor_total_auditado AS DECIMAL(19,2)) AS geografico_valor_total,
        CAST(GEO.valor_vendas_outra_uf AS DECIMAL(19,2)) AS geografico_valor_outra_uf,
        CAST((GEO.valor_vendas_outra_uf * 100.0) / NULLIF(GEO.valor_total_auditado, 0) AS DECIMAL(18,4)) AS pct_geografico,

        -- Medicamentos de alto custo
        CAST(AC.valor_total_auditado AS DECIMAL(19,2)) AS alto_custo_valor_total,
        CAST(AC.valor_vendas_alto_custo AS DECIMAL(19,2)) AS alto_custo_valor,
        CAST((AC.valor_vendas_alto_custo * 100.0) / NULLIF(AC.valor_total_auditado, 0) AS DECIMAL(18,4)) AS pct_alto_custo,

        -- Dias de pico
        CAST(PIC.valor_total_auditado AS DECIMAL(19,2)) AS pico_valor_total,
        CAST(PIC.valor_top3_dias AS DECIMAL(19,2)) AS pico_valor_top3_dias,
        CAST(PIC.mediana_concentracao AS DECIMAL(18,4)) AS pct_pico,

        -- CRM HHI
        CAST(HHI.total_prescritores AS INT) AS hhi_total_prescritores,
        CAST(HHI.total_prescricoes AS BIGINT) AS hhi_total_prescricoes,
        CAST(HHI.valor_total_prescricoes AS DECIMAL(19,2)) AS hhi_valor_total,
        CAST(HHI.valor_top1 AS DECIMAL(19,2)) AS hhi_valor_top1,
        CAST(HHI.valor_top5 AS DECIMAL(19,2)) AS hhi_valor_top5,
        CAST(HHI.participacao_top1_pct AS DECIMAL(18,4)) AS hhi_participacao_top1_pct,
        CAST(HHI.participacao_top5_pct AS DECIMAL(18,4)) AS hhi_participacao_top5_pct,
        CAST(HHI.indice_hhi AS DECIMAL(18,4)) AS val_hhi_crm,

        -- CRMs irregulares
        CAST(CI.total_prescritores AS INT) AS crms_irregulares_total_prescritores,
        CAST(CI.total_prescricoes AS BIGINT) AS crms_irregulares_total_prescricoes,
        CAST(CI.valor_total_auditado AS DECIMAL(19,2)) AS crms_irregulares_valor_total,
        CAST(CI.qtd_crms_nao_localizados AS INT) AS crms_irregulares_qtd_nao_localizados,
        CAST(CI.valor_crms_nao_localizados AS DECIMAL(19,2)) AS crms_irregulares_valor_nao_localizados,
        CAST(CI.qtd_crms_antes_registro AS INT) AS crms_irregulares_qtd_antes_registro,
        CAST(CI.valor_crms_antes_registro AS DECIMAL(19,2)) AS crms_irregulares_valor_antes_registro,
        CAST(CI.qtd_crms_irregulares AS INT) AS crms_irregulares_qtd,
        CAST(CI.valor_crms_irregulares AS DECIMAL(19,2)) AS crms_irregulares_valor,
        CAST((CI.valor_crms_irregulares * 100.0) / NULLIF(CI.valor_total_auditado, 0) AS DECIMAL(18,4)) AS pct_crms_irregulares,

        -- Recorrencia sistemica
        CAST(RS.total_renovacoes_monitoradas AS INT) AS recorrencia_total_renovacoes_monitoradas,
        CAST(RS.total_renovacoes_sistemicas AS INT) AS recorrencia_total_renovacoes_sistemicas,
        CAST(RS.valor_total_auditado AS DECIMAL(19,2)) AS recorrencia_valor_total,
        CAST(RS.valor_renovacoes_sistemicas AS DECIMAL(19,2)) AS recorrencia_valor_sistemico,
        CAST((RS.valor_renovacoes_sistemicas * 100.0) / NULLIF(RS.valor_total_auditado, 0) AS DECIMAL(18,4)) AS pct_recorrencia_sistemica

    INTO temp_CGUSC.fp.matriz_risco_consolidada
    FROM BaseAnual AS B
    INNER JOIN temp_CGUSC.fp.indicador_auditado_detalhado AS IA
        ON IA.id_cnpj = B.id_cnpj
       AND IA.ano_base = B.ano_base
    LEFT JOIN temp_CGUSC.fp.indicador_falecidos_detalhado AS FAL
        ON FAL.id_cnpj = B.id_cnpj
       AND FAL.ano_base = B.ano_base
    LEFT JOIN temp_CGUSC.fp.indicador_inconsistencia_clinica_detalhado AS CLI
        ON CLI.id_cnpj = B.id_cnpj
       AND CLI.ano_base = B.ano_base
    LEFT JOIN temp_CGUSC.fp.indicador_teto_detalhado AS TET
        ON TET.id_cnpj = B.id_cnpj
       AND TET.ano_base = B.ano_base
    LEFT JOIN temp_CGUSC.fp.indicador_polimedicamento_detalhado AS POL
        ON POL.id_cnpj = B.id_cnpj
       AND POL.ano_base = B.ano_base
    LEFT JOIN temp_CGUSC.fp.indicador_ticket_medio_detalhado AS TIC
        ON TIC.id_cnpj = B.id_cnpj
       AND TIC.ano_base = B.ano_base
    LEFT JOIN temp_CGUSC.fp.indicador_receita_por_paciente_detalhado AS RCP
        ON RCP.id_cnpj = B.id_cnpj
       AND RCP.ano_base = B.ano_base
    LEFT JOIN temp_CGUSC.fp.indicador_venda_per_capita_detalhado AS VPC
        ON VPC.id_cnpj = B.id_cnpj
       AND VPC.ano_base = B.ano_base
    LEFT JOIN temp_CGUSC.fp.indicador_vendas_consecutivas_detalhado AS VR
        ON VR.id_cnpj = B.id_cnpj
       AND VR.ano_base = B.ano_base
    LEFT JOIN temp_CGUSC.fp.indicador_volume_atipico_detalhado AS VA
        ON VA.id_cnpj = B.id_cnpj
       AND VA.ano_base = B.ano_base
    LEFT JOIN temp_CGUSC.fp.indicador_geografico_detalhado AS GEO
        ON GEO.id_cnpj = B.id_cnpj
       AND GEO.ano_base = B.ano_base
    LEFT JOIN temp_CGUSC.fp.indicador_alto_custo_detalhado AS AC
        ON AC.id_cnpj = B.id_cnpj
       AND AC.ano_base = B.ano_base
    LEFT JOIN temp_CGUSC.fp.indicador_concentracao_pico_detalhado AS PIC
        ON PIC.id_cnpj = B.id_cnpj
       AND PIC.ano_base = B.ano_base
    LEFT JOIN temp_CGUSC.fp.indicador_crm_hhi_detalhado AS HHI
        ON HHI.id_cnpj = B.id_cnpj
       AND HHI.ano_base = B.ano_base
    LEFT JOIN temp_CGUSC.fp.indicador_crms_irregulares_detalhado AS CI
        ON CI.id_cnpj = B.id_cnpj
       AND CI.ano_base = B.ano_base
    LEFT JOIN temp_CGUSC.fp.indicador_recorrencia_sistemica_detalhado AS RS
        ON RS.id_cnpj = B.id_cnpj
       AND RS.ano_base = B.ano_base;

    IF NOT EXISTS (SELECT 1 FROM temp_CGUSC.fp.matriz_risco_consolidada)
    BEGIN
        RAISERROR('Matriz anual de componentes criada sem linhas.', 16, 1);
        RETURN;
    END;

    CREATE UNIQUE CLUSTERED INDEX IDX_MatrizRisco_Componentes_CNPJ_Ano
        ON temp_CGUSC.fp.matriz_risco_consolidada(id_cnpj, ano_base);

    CREATE NONCLUSTERED INDEX IDX_MatrizRisco_Componentes_Ano
        ON temp_CGUSC.fp.matriz_risco_consolidada(ano_base, id_cnpj);

    COMMIT TRANSACTION;

    PRINT '>> MATRIZ ANUAL DE COMPONENTES CONCLUIDA COM SUCESSO.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    PRINT '>> ERRO FATAL NA MATRIZ ANUAL: ' + ERROR_MESSAGE()
        + ' (Linha: ' + CAST(ERROR_LINE() AS VARCHAR(10)) + ')';
    THROW;
END CATCH;
GO

SELECT
    ano_base,
    COUNT(*) AS qtd_linhas,
    COUNT(DISTINCT id_cnpj) AS qtd_cnpjs,
    MIN(periodo_min) AS periodo_min,
    MAX(periodo_max) AS periodo_max
FROM temp_CGUSC.fp.matriz_risco_consolidada
GROUP BY ano_base
ORDER BY ano_base;
GO
