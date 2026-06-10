USE temp_CGUSC;
GO

DECLARE @ano_inicio SMALLINT = 2023;
DECLARE @ano_fim    SMALLINT = 2024;
DECLARE @uf CHAR(2) = 'MG';

IF OBJECT_ID('temp_CGUSC.fp.matriz_risco_consolidada', 'U') IS NULL
    THROW 50000, 'Tabela temp_CGUSC.fp.matriz_risco_consolidada nao encontrada.', 1;

IF OBJECT_ID('temp_CGUSC.fp.dados_farmacia', 'U') IS NULL
    THROW 50000, 'Tabela temp_CGUSC.fp.dados_farmacia nao encontrada.', 1;

WITH base AS (
    SELECT
        CAST(F.id AS INT) AS id_cnpj,
        F.cnpj,
        F.razaoSocial AS razao_social,
        F.municipio,
        F.uf,
        CAST(F.id_regiao_saude AS VARCHAR(20)) AS id_regiao_saude,

        SUM(M.valor_total_vendas) AS valor_total_vendas,
        SUM(M.valor_sem_comprovacao) AS valor_sem_comprovacao,
        SUM(M.falecidos_valor) AS falecidos_valor,
        SUM(M.clinico_valor_suspeito) AS clinico_valor_suspeito,
        SUM(M.clinico_valor_monitorado) AS clinico_valor_monitorado,
        SUM(M.teto_valor) AS teto_valor,
        SUM(M.teto_valor_total) AS teto_valor_total,
        SUM(M.polimedicamento_valor) AS polimedicamento_valor,
        SUM(M.ticket_total_autorizacoes) AS ticket_total_autorizacoes,
        SUM(M.receita_paciente_total_pacientes_distintos * M.receita_paciente_total_meses_ativos) AS receita_paciente_denominador,
        SUM(M.per_capita_denominador) AS per_capita_denominador,
        SUM(M.alto_custo_valor) AS alto_custo_valor,
        SUM(M.vendas_rapidas_valor) AS vendas_rapidas_valor,
        SUM(M.volume_atipico_soma_excesso_crescimento_pct) AS volume_atipico_soma_excesso_crescimento_pct,
        SUM(M.volume_atipico_total_semestres_comparaveis) AS volume_atipico_total_semestres_comparaveis,
        SUM(M.volume_atipico_valor_aumento_atipico) AS volume_atipico_valor_aumento_atipico,
        SUM(M.recorrencia_valor_sistemico) AS recorrencia_valor_sistemico,
        SUM(M.recorrencia_valor_total) AS recorrencia_valor_total,
        SUM(M.pico_valor_top3_dias) AS pico_valor_top3_dias,
        SUM(M.geografico_valor_outra_uf) AS geografico_valor_outra_uf,
        SUM(M.geografico_valor_total) AS geografico_valor_total,
        SUM(M.hhi_valor_top1 * M.hhi_valor_top1 / NULLIF(M.hhi_valor_total, 0)) AS hhi_valor_ponderado,
        SUM(M.hhi_valor_total) AS hhi_valor_total,
        SUM(M.crms_irregulares_valor) AS crms_irregulares_valor,
        SUM(M.crms_irregulares_valor_total) AS crms_irregulares_valor_total
    FROM temp_CGUSC.fp.matriz_risco_consolidada M
    INNER JOIN temp_CGUSC.fp.dados_farmacia F
        ON F.id = M.id_cnpj
    WHERE M.ano_base BETWEEN @ano_inicio AND @ano_fim
      AND F.uf = @uf
    GROUP BY
        F.id,
        F.cnpj,
        F.razaoSocial,
        F.municipio,
        F.uf,
        F.id_regiao_saude
),
indicadores AS (
    SELECT
        *,
        CAST(100.0 * valor_sem_comprovacao / NULLIF(valor_total_vendas, 0) AS FLOAT) AS pct_sem_comprovacao,
        CAST(100.0 * falecidos_valor / NULLIF(valor_total_vendas, 0) AS FLOAT) AS pct_falecidos,
        CAST(100.0 * clinico_valor_suspeito / NULLIF(clinico_valor_monitorado, 0) AS FLOAT) AS pct_clinico,
        CAST(100.0 * teto_valor / NULLIF(teto_valor_total, 0) AS FLOAT) AS pct_teto,
        CAST(100.0 * polimedicamento_valor / NULLIF(valor_total_vendas, 0) AS FLOAT) AS pct_polimedicamento,
        CAST(valor_total_vendas / NULLIF(ticket_total_autorizacoes, 0) AS FLOAT) AS val_ticket_medio,
        CAST(valor_total_vendas / NULLIF(receita_paciente_denominador, 0) AS FLOAT) AS val_receita_paciente,
        CAST(valor_total_vendas / NULLIF(per_capita_denominador, 0) AS FLOAT) AS val_per_capita,
        CAST(100.0 * alto_custo_valor / NULLIF(valor_total_vendas, 0) AS FLOAT) AS pct_alto_custo,
        CAST(100.0 * vendas_rapidas_valor / NULLIF(valor_total_vendas, 0) AS FLOAT) AS pct_vendas_rapidas,
        CAST(volume_atipico_soma_excesso_crescimento_pct / NULLIF(volume_atipico_total_semestres_comparaveis, 0) AS FLOAT) AS val_volume_atipico,
        CAST(100.0 * recorrencia_valor_sistemico / NULLIF(recorrencia_valor_total, 0) AS FLOAT) AS pct_recorrencia_sistemica,
        CAST(100.0 * pico_valor_top3_dias / NULLIF(valor_total_vendas, 0) AS FLOAT) AS pct_pico,
        CAST(100.0 * geografico_valor_outra_uf / NULLIF(geografico_valor_total, 0) AS FLOAT) AS pct_geografico,
        CAST(hhi_valor_ponderado / NULLIF(hhi_valor_total, 0) AS FLOAT) AS val_hhi_crm,
        CAST(100.0 * crms_irregulares_valor / NULLIF(crms_irregulares_valor_total, 0) AS FLOAT) AS pct_crms_irregulares
    FROM base
),
score_partes AS (
    SELECT
        *,
        PERCENT_RANK() OVER (ORDER BY pct_sem_comprovacao) * 100.0 AS s_sem_comprovacao,
        PERCENT_RANK() OVER (ORDER BY pct_falecidos) * 100.0 AS s_falecidos,
        PERCENT_RANK() OVER (ORDER BY pct_clinico) * 100.0 AS s_clinico,
        PERCENT_RANK() OVER (ORDER BY pct_teto) * 100.0 AS s_teto,
        PERCENT_RANK() OVER (ORDER BY pct_polimedicamento) * 100.0 AS s_polimedicamento,
        PERCENT_RANK() OVER (ORDER BY val_ticket_medio) * 100.0 AS s_ticket,
        PERCENT_RANK() OVER (ORDER BY val_receita_paciente) * 100.0 AS s_receita_paciente,
        PERCENT_RANK() OVER (ORDER BY val_per_capita) * 100.0 AS s_per_capita,
        PERCENT_RANK() OVER (ORDER BY pct_alto_custo) * 100.0 AS s_alto_custo,
        PERCENT_RANK() OVER (ORDER BY pct_vendas_rapidas) * 100.0 AS s_vendas_rapidas,
        PERCENT_RANK() OVER (ORDER BY val_volume_atipico) * 100.0 AS s_volume_atipico,
        PERCENT_RANK() OVER (ORDER BY pct_recorrencia_sistemica) * 100.0 AS s_recorrencia,
        PERCENT_RANK() OVER (ORDER BY pct_pico) * 100.0 AS s_pico,
        PERCENT_RANK() OVER (ORDER BY pct_geografico) * 100.0 AS s_geografico,
        PERCENT_RANK() OVER (ORDER BY val_hhi_crm) * 100.0 AS s_hhi,
        PERCENT_RANK() OVER (ORDER BY pct_crms_irregulares) * 100.0 AS s_crms_irregulares
    FROM indicadores
),
score AS (
    SELECT
        *,
        CAST((
            ISNULL(s_sem_comprovacao, 0)  * 5.0 +
            ISNULL(s_falecidos, 0)        * 2.5 +
            ISNULL(s_clinico, 0)          * 1.5 +
            ISNULL(s_teto, 0)             * 1.0 +
            ISNULL(s_polimedicamento, 0)  * 1.5 +
            ISNULL(s_ticket, 0)           * 1.0 +
            ISNULL(s_receita_paciente, 0) * 1.0 +
            ISNULL(s_per_capita, 0)       * 1.0 +
            ISNULL(s_alto_custo, 0)       * 1.5 +
            ISNULL(s_vendas_rapidas, 0)   * 2.0 +
            ISNULL(s_volume_atipico, 0)   * 2.5 +
            ISNULL(s_recorrencia, 0)      * 2.0 +
            ISNULL(s_pico, 0)             * 1.0 +
            ISNULL(s_geografico, 0)       * 1.0 +
            ISNULL(s_hhi, 0)              * 0.5 +
            ISNULL(s_crms_irregulares, 0) * 1.0
        ) / 26.0 AS DECIMAL(10,2)) AS score_base
    FROM score_partes
)
SELECT TOP (100)
    RANK() OVER (ORDER BY score_base DESC) AS rank_mg,
    id_cnpj,
    cnpj,
    razao_social,
    municipio,
    uf,
    id_regiao_saude,
    score_base,

    valor_total_vendas,
    valor_sem_comprovacao,

    pct_sem_comprovacao,
    pct_falecidos,
    pct_clinico,
    pct_teto,
    pct_polimedicamento,
    val_ticket_medio,
    val_receita_paciente,
    val_per_capita,
    pct_alto_custo,
    pct_vendas_rapidas,
    val_volume_atipico,
    volume_atipico_valor_aumento_atipico,
    pct_recorrencia_sistemica,
    pct_pico,
    pct_geografico,
    val_hhi_crm,
    pct_crms_irregulares,

    falecidos_valor,
    clinico_valor_suspeito,
    teto_valor,
    teto_valor_total,
    polimedicamento_valor,
    alto_custo_valor,
    vendas_rapidas_valor,
    recorrencia_valor_sistemico,
    recorrencia_valor_total,
    pico_valor_top3_dias,
    geografico_valor_outra_uf,
    geografico_valor_total,
    crms_irregulares_valor,
    crms_irregulares_valor_total
FROM score
ORDER BY score_base DESC, valor_total_vendas DESC;