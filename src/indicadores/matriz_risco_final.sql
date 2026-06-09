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
       OR COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'cnpj') IS NULL
    BEGIN
        RAISERROR('Tabela temp_CGUSC.fp.dados_farmacia sem colunas obrigatorias id/cnpj.', 16, 1);
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

    IF EXISTS (
        SELECT 1
        FROM temp_CGUSC.fp.dados_farmacia
        GROUP BY cnpj
        HAVING COUNT_BIG(*) > 1
    )
    BEGIN
        RAISERROR('Tabela temp_CGUSC.fp.dados_farmacia possui CNPJs duplicados.', 16, 1);
        RETURN;
    END;

    DECLARE @Contrato TABLE (
        tabela SYSNAME NOT NULL,
        coluna SYSNAME NOT NULL
    );

    INSERT INTO @Contrato (tabela, coluna)
    VALUES
        ('movimentacao_mensal_cnpj', 'cnpj'),
        ('movimentacao_mensal_cnpj', 'periodo'),
        ('movimentacao_mensal_cnpj', 'total_vendas'),
        ('movimentacao_mensal_cnpj', 'total_sem_comprovacao'),
        ('movimentacao_mensal_cnpj', 'total_qnt_caixas_vendidas'),
        ('movimentacao_mensal_cnpj', 'total_qnt_caixas_sem_comprovacao'),
        ('movimentacao_mensal_cnpj', 'total_num_autorizacoes'),

        ('indicador_falecidos_detalhado', 'id_cnpj'),
        ('indicador_falecidos_detalhado', 'ano_base'),
        ('indicador_falecidos_detalhado', 'total_autorizacoes'),
        ('indicador_falecidos_detalhado', 'qtd_autorizacoes_falecidos'),
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
        ('indicador_polimedicamento_detalhado', 'valor_autorizacoes_suspeitas'),

        ('indicador_ticket_medio_detalhado', 'id_cnpj'),
        ('indicador_ticket_medio_detalhado', 'ano_base'),
        ('indicador_ticket_medio_detalhado', 'valor_total_auditado'),
        ('indicador_ticket_medio_detalhado', 'total_autorizacoes'),

        ('indicador_receita_por_paciente_detalhado', 'id_cnpj'),
        ('indicador_receita_por_paciente_detalhado', 'ano_base'),
        ('indicador_receita_por_paciente_detalhado', 'total_pacientes_distintos'),
        ('indicador_receita_por_paciente_detalhado', 'total_meses_ativos'),

        ('indicador_venda_per_capita_detalhado', 'id_cnpj'),
        ('indicador_venda_per_capita_detalhado', 'ano_base'),
        ('indicador_venda_per_capita_detalhado', 'total_meses_ativos'),
        ('indicador_venda_per_capita_detalhado', 'populacao_municipio'),
        ('indicador_venda_per_capita_detalhado', 'denominador_per_capita'),

        ('indicador_vendas_consecutivas_detalhado', 'id_cnpj'),
        ('indicador_vendas_consecutivas_detalhado', 'ano_base'),
        ('indicador_vendas_consecutivas_detalhado', 'total_intervalos_analisados'),
        ('indicador_vendas_consecutivas_detalhado', 'total_vendas_rapidas'),
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
        ('indicador_alto_custo_detalhado', 'valor_vendas_alto_custo'),

        ('indicador_concentracao_pico_detalhado', 'id_cnpj'),
        ('indicador_concentracao_pico_detalhado', 'ano_base'),
        ('indicador_concentracao_pico_detalhado', 'valor_top3_dias'),

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

    -- ========================================================================
    -- BASE ANUAL
    -- ========================================================================
    ;WITH MovimentacaoAnual AS (
        SELECT
            CAST(F.id AS INT) AS id_cnpj,
            CAST(YEAR(M.periodo) AS SMALLINT) AS ano_base,
            CAST(SUM(CAST(M.total_vendas AS DECIMAL(19,2))) AS DECIMAL(19,2)) AS valor_total_vendas,
            CAST(SUM(CAST(M.total_sem_comprovacao AS DECIMAL(19,2))) AS DECIMAL(19,2)) AS valor_sem_comprovacao,
            CAST(SUM(CAST(M.total_qnt_caixas_vendidas AS BIGINT)) AS INT) AS total_caixas,
            CAST(SUM(CAST(M.total_qnt_caixas_sem_comprovacao AS BIGINT)) AS INT) AS total_caixas_sem_comprovacao,
            CAST(SUM(CAST(M.total_num_autorizacoes AS BIGINT)) AS INT) AS total_autorizacoes
        FROM temp_CGUSC.fp.movimentacao_mensal_cnpj AS M
        INNER JOIN temp_CGUSC.fp.dados_farmacia AS F
            ON F.cnpj = M.cnpj
        WHERE M.periodo IS NOT NULL
        GROUP BY
            F.id,
            YEAR(M.periodo)
        HAVING SUM(CAST(M.total_vendas AS DECIMAL(19,2))) > 0
    ),
    BaseAnual AS (
        SELECT
            id_cnpj,
            ano_base
        FROM MovimentacaoAnual
    )
    SELECT
        B.id_cnpj,
        B.ano_base,

        -- Movimentacao financeira
        MVA.valor_total_vendas,
        MVA.valor_sem_comprovacao,
        MVA.total_caixas,
        MVA.total_caixas_sem_comprovacao,
        MVA.total_autorizacoes,

        -- Falecidos
        CAST(FAL.total_autorizacoes AS INT) AS falecidos_total_autorizacoes,
        CAST(FAL.qtd_autorizacoes_falecidos AS INT) AS falecidos_qtd_autorizacoes,
        CAST(FAL.valor_falecidos AS DECIMAL(19,2)) AS falecidos_valor,

        -- Inconsistencia clinica
        CAST(CLI.total_vendas_monitoradas AS INT) AS clinico_total_vendas_monitoradas,
        CAST(CLI.qtd_vendas_suspeitas AS INT) AS clinico_qtd_vendas_suspeitas,
        CAST(CLI.valor_vendas_monitoradas AS DECIMAL(19,2)) AS clinico_valor_monitorado,
        CAST(CLI.valor_vendas_suspeitas AS DECIMAL(19,2)) AS clinico_valor_suspeito,

        -- Teto
        CAST(TET.total_itens_monitorados AS INT) AS teto_total_itens_monitorados,
        CAST(TET.total_itens_teto_maximo AS INT) AS teto_total_itens,
        CAST(TET.valor_total_auditado AS DECIMAL(19,2)) AS teto_valor_total,
        CAST(TET.valor_itens_teto_maximo AS DECIMAL(19,2)) AS teto_valor,

        -- Polimedicamento
        CAST(POL.total_autorizacoes_monitoradas AS INT) AS polimedicamento_total_autorizacoes,
        CAST(POL.total_autorizacoes_suspeitas AS INT) AS polimedicamento_total_autorizacoes_4mais,
        CAST(POL.valor_autorizacoes_suspeitas AS DECIMAL(19,2)) AS polimedicamento_valor,

        -- Ticket medio
        CAST(TIC.total_autorizacoes AS INT) AS ticket_total_autorizacoes,

        -- Receita por paciente
        CAST(RCP.total_pacientes_distintos AS INT) AS receita_paciente_total_pacientes_distintos,
        CAST(RCP.total_meses_ativos AS TINYINT) AS receita_paciente_total_meses_ativos,

        -- Venda per capita
        CAST(VPC.total_meses_ativos AS TINYINT) AS per_capita_total_meses_ativos,
        CAST(VPC.populacao_municipio AS INT) AS per_capita_populacao_municipio,
        CAST(VPC.denominador_per_capita AS INT) AS per_capita_denominador,

        -- Vendas rapidas
        CAST(VR.total_intervalos_analisados AS INT) AS vendas_rapidas_total_intervalos,
        CAST(VR.total_vendas_rapidas AS INT) AS vendas_rapidas_total,
        CAST(VR.valor_vendas_rapidas AS DECIMAL(19,2)) AS vendas_rapidas_valor,

        -- Volume atipico
        CAST(VA.total_semestres_comparaveis AS TINYINT) AS volume_atipico_total_semestres_comparaveis,
        CAST(VA.total_semestres_atipicos AS TINYINT) AS volume_atipico_total_semestres_atipicos,
        CAST(VA.soma_excesso_crescimento_pct AS DECIMAL(18,4)) AS volume_atipico_soma_excesso_crescimento_pct,
        CAST(VA.valor_aumento_total AS DECIMAL(19,2)) AS volume_atipico_valor_aumento_total,
        CAST(VA.valor_aumento_atipico AS DECIMAL(19,2)) AS volume_atipico_valor_aumento_atipico,
        CAST(VA.maior_taxa_crescimento_pct AS DECIMAL(18,4)) AS volume_atipico_maior_taxa_crescimento_pct,

        -- Dispersao geografica
        CAST(GEO.total_vendas_monitoradas AS INT) AS geografico_total_vendas_monitoradas,
        CAST(GEO.qtd_vendas_outra_uf AS INT) AS geografico_qtd_vendas_outra_uf,
        CAST(GEO.valor_total_auditado AS DECIMAL(19,2)) AS geografico_valor_total,
        CAST(GEO.valor_vendas_outra_uf AS DECIMAL(19,2)) AS geografico_valor_outra_uf,

        -- Medicamentos de alto custo
        CAST(AC.valor_vendas_alto_custo AS DECIMAL(19,2)) AS alto_custo_valor,

        -- Dias de pico
        CAST(PIC.valor_top3_dias AS DECIMAL(19,2)) AS pico_valor_top3_dias,

        -- CRM HHI
        CAST(HHI.total_prescritores AS INT) AS hhi_total_prescritores,
        CAST(HHI.total_prescricoes AS INT) AS hhi_total_prescricoes,
        CAST(HHI.valor_total_prescricoes AS DECIMAL(19,2)) AS hhi_valor_total,
        CAST(HHI.valor_top1 AS DECIMAL(19,2)) AS hhi_valor_top1,
        CAST(HHI.valor_top5 AS DECIMAL(19,2)) AS hhi_valor_top5,
        CAST(HHI.participacao_top1_pct AS DECIMAL(18,4)) AS hhi_participacao_top1_pct,
        CAST(HHI.participacao_top5_pct AS DECIMAL(18,4)) AS hhi_participacao_top5_pct,
        CAST(HHI.indice_hhi AS DECIMAL(18,4)) AS val_hhi_crm,

        -- CRMs irregulares
        CAST(CI.total_prescritores AS INT) AS crms_irregulares_total_prescritores,
        CAST(CI.total_prescricoes AS INT) AS crms_irregulares_total_prescricoes,
        CAST(CI.valor_total_auditado AS DECIMAL(19,2)) AS crms_irregulares_valor_total,
        CAST(CI.qtd_crms_nao_localizados AS INT) AS crms_irregulares_qtd_nao_localizados,
        CAST(CI.valor_crms_nao_localizados AS DECIMAL(19,2)) AS crms_irregulares_valor_nao_localizados,
        CAST(CI.qtd_crms_antes_registro AS INT) AS crms_irregulares_qtd_antes_registro,
        CAST(CI.valor_crms_antes_registro AS DECIMAL(19,2)) AS crms_irregulares_valor_antes_registro,
        CAST(CI.qtd_crms_irregulares AS INT) AS crms_irregulares_qtd,
        CAST(CI.valor_crms_irregulares AS DECIMAL(19,2)) AS crms_irregulares_valor,

        -- Recorrencia sistemica
        CAST(RS.total_renovacoes_monitoradas AS INT) AS recorrencia_total_renovacoes_monitoradas,
        CAST(RS.total_renovacoes_sistemicas AS INT) AS recorrencia_total_renovacoes_sistemicas,
        CAST(RS.valor_total_auditado AS DECIMAL(19,2)) AS recorrencia_valor_total,
        CAST(RS.valor_renovacoes_sistemicas AS DECIMAL(19,2)) AS recorrencia_valor_sistemico

    INTO temp_CGUSC.fp.matriz_risco_consolidada
    FROM BaseAnual AS B
    INNER JOIN MovimentacaoAnual AS MVA
        ON MVA.id_cnpj = B.id_cnpj
       AND MVA.ano_base = B.ano_base
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
    COUNT(DISTINCT id_cnpj) AS qtd_cnpjs
FROM temp_CGUSC.fp.matriz_risco_consolidada
GROUP BY ano_base
ORDER BY ano_base;
GO
