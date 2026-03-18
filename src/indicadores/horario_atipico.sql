USE [temp_CGUSC]
GO

-- ============================================================================
-- INDICADOR DE HORÁRIO ATÍPICO - VERSÃO 2
-- ============================================================================
-- OBJETIVO: Identificar farmácias com alto volume de vendas realizadas em
--           horário de madrugada (00:00 até 05:59)
--
-- FONTE: Todas as vendas do programa Farmácia Popular
--
-- INTERPRETAÇÃO DO percentual_madrugada:
--   - Alta concentração de vendas na madrugada pode indicar registro fraudulento
--     de dispensações fora do horário de funcionamento real da farmácia
--
-- ALTERAÇÕES APLICADAS:
--   1. Fonte dupla: UNION ALL de db_FarmaciaPopular.dbo.Relatorio_movimentacaoFP
--      e db_FarmaciaPopular.carga_2024.relatorio_movimentacaoFP_2021_2024 no
--      Passo 1 (todas as vendas, sem filtro por medicamento)
--   2. Adicionado nível município (Passo 3), seguindo a mesma lógica ponderada
--      por volume (SUM/SUM) dos passos UF e BR, com mediana via CTE
--   3. Passos UF e BR acrescidos de mediana via CTE (padrão venda_per_capita)
--   4. Adicionados rankings explícitos por Brasil, UF e Município
--      (percentual_madrugada DESC) na tabela final
--   4. Limpeza de tabelas intermediárias feita ao longo do script
-- ============================================================================

-- ============================================================================
-- DEFINIÇÃO DE VARIÁVEIS
-- (sem GO após o USE para manter @DataInicio/@DataFim acessíveis em todo o batch)
-- ============================================================================
DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim    DATE = '2024-12-10';


-- ============================================================================
-- PASSO 1: CÁLCULO BASE POR FARMÁCIA (HORÁRIO ATÍPICO)
-- Madrugada: 00:00 até 05:59
-- A CTE VendasPorHorario deduplica por num_autorizacao antes de agregar,
-- garantindo que cada autorização seja contada uma única vez mesmo com
-- múltiplos itens por prescrição.
-- O UNION ALL é feito dentro da CTE, antes do GROUP BY, para que
-- MAX(flag_madrugada) opere sobre o conjunto completo das duas bases.
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_horario_atipico;

WITH VendasPorHorario AS (
    SELECT
        A.cnpj,
        A.num_autorizacao,
        MIN(A.data_hora) AS data_hora_venda,

        -- Flag se qualquer registro dessa autorização caiu na madrugada
        MAX(CASE
            WHEN DATEPART(HOUR, A.data_hora) BETWEEN 0 AND 5 THEN 1
            ELSE 0
        END) AS flag_madrugada

    FROM (
        SELECT R.cnpj, R.num_autorizacao, R.data_hora
        FROM db_FarmaciaPopular.dbo.Relatorio_movimentacaoFP R
        WHERE R.data_hora >= @DataInicio
          AND R.data_hora <= @DataFim

        UNION ALL

        SELECT R.cnpj, R.num_autorizacao, R.data_hora
        FROM db_FarmaciaPopular.carga_2024.relatorio_movimentacaoFP_2021_2024 R
        WHERE R.data_hora >= @DataInicio
          AND R.data_hora <= @DataFim
    ) A
    GROUP BY A.cnpj, A.num_autorizacao
),
AgregadoPorFarmacia AS (
    SELECT
        cnpj,
        COUNT(*)              AS total_vendas_monitoradas,
        SUM(flag_madrugada)   AS qtd_vendas_madrugada
    FROM VendasPorHorario
    GROUP BY cnpj
)

SELECT
    cnpj,
    total_vendas_monitoradas,
    qtd_vendas_madrugada,

    CAST(
        CASE
            WHEN total_vendas_monitoradas > 0 THEN
                (CAST(qtd_vendas_madrugada        AS DECIMAL(18,2)) /
                 CAST(total_vendas_monitoradas    AS DECIMAL(18,2))) * 100.0
            ELSE 0
        END
    AS DECIMAL(18,4)) AS percentual_madrugada

INTO temp_CGUSC.fp.indicador_horario_atipico
FROM AgregadoPorFarmacia
WHERE total_vendas_monitoradas > 0;

CREATE CLUSTERED INDEX IDX_IndHora_CNPJ ON temp_CGUSC.fp.indicador_horario_atipico(cnpj);


-- ============================================================================
-- PASSO 2: MÉTRICAS POR MUNICÍPIO
-- Média ponderada por volume (SUM/SUM) + mediana via CTE separada,
-- evitando conflito entre GROUP BY e PERCENTILE_CONT OVER().
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_horario_atipico_mun;

WITH CTE_Media_Mun AS (
    SELECT
        CAST(F.uf        AS VARCHAR(2))   AS uf,
        CAST(F.municipio AS VARCHAR(255)) AS municipio,
        SUM(I.total_vendas_monitoradas)   AS total_vendas_municipio,
        SUM(I.qtd_vendas_madrugada)       AS total_madrugada_municipio,
        CAST(
            CASE
                WHEN SUM(I.total_vendas_monitoradas) > 0 THEN
                    (CAST(SUM(I.qtd_vendas_madrugada)     AS DECIMAL(18,2)) /
                     CAST(SUM(I.total_vendas_monitoradas) AS DECIMAL(18,2))) * 100.0
                ELSE 0
            END
        AS DECIMAL(18,4)) AS percentual_madrugada_mun
    FROM temp_CGUSC.fp.indicador_horario_atipico I
    INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj
    GROUP BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255))
),
CTE_Mediana_Mun AS (
    SELECT DISTINCT
        CAST(F.uf        AS VARCHAR(2))   AS uf,
        CAST(F.municipio AS VARCHAR(255)) AS municipio,
        CAST(
            PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.percentual_madrugada)
            OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255)))
        AS DECIMAL(18,4)) AS mediana_madrugada_mun
    FROM temp_CGUSC.fp.indicador_horario_atipico I
    INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj
)
SELECT
    M.uf,
    M.municipio,
    M.total_vendas_municipio,
    M.total_madrugada_municipio,
    M.percentual_madrugada_mun,
    D.mediana_madrugada_mun
INTO temp_CGUSC.fp.indicador_horario_atipico_mun
FROM CTE_Media_Mun M
INNER JOIN CTE_Mediana_Mun D ON D.uf = M.uf AND D.municipio = M.municipio;

CREATE CLUSTERED INDEX IDX_IndHoraMun ON temp_CGUSC.fp.indicador_horario_atipico_mun(uf, municipio);


-- ============================================================================
-- PASSO 3: MÉTRICAS POR ESTADO (UF)
-- Média ponderada por volume + mediana via CTE separada.
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_horario_atipico_uf;

WITH CTE_Media_UF AS (
    SELECT
        CAST(F.uf AS VARCHAR(2))        AS uf,
        SUM(I.total_vendas_monitoradas) AS total_vendas_uf,
        SUM(I.qtd_vendas_madrugada)     AS total_madrugada_uf,
        CAST(
            CASE
                WHEN SUM(I.total_vendas_monitoradas) > 0 THEN
                    (CAST(SUM(I.qtd_vendas_madrugada)     AS DECIMAL(18,2)) /
                     CAST(SUM(I.total_vendas_monitoradas) AS DECIMAL(18,2))) * 100.0
                ELSE 0
            END
        AS DECIMAL(18,4)) AS percentual_madrugada_uf
    FROM temp_CGUSC.fp.indicador_horario_atipico I
    INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj
    GROUP BY CAST(F.uf AS VARCHAR(2))
),
CTE_Mediana_UF AS (
    SELECT DISTINCT
        CAST(F.uf AS VARCHAR(2)) AS uf,
        CAST(
            PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.percentual_madrugada)
            OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)))
        AS DECIMAL(18,4)) AS mediana_madrugada_uf
    FROM temp_CGUSC.fp.indicador_horario_atipico I
    INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj
)
SELECT
    M.uf,
    M.total_vendas_uf,
    M.total_madrugada_uf,
    M.percentual_madrugada_uf,
    D.mediana_madrugada_uf
INTO temp_CGUSC.fp.indicador_horario_atipico_uf
FROM CTE_Media_UF M
INNER JOIN CTE_Mediana_UF D ON D.uf = M.uf;

CREATE CLUSTERED INDEX IDX_IndHoraUF_uf ON temp_CGUSC.fp.indicador_horario_atipico_uf(uf);


-- ============================================================================
-- PASSO 4: MÉTRICAS NACIONAIS (BRASIL)
-- Média ponderada por volume + mediana via CTE separada.
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_horario_atipico_br;

WITH CTE_Media_BR AS (
    SELECT
        SUM(total_vendas_monitoradas) AS total_vendas_br,
        SUM(qtd_vendas_madrugada)     AS total_madrugada_br,
        CAST(
            CASE
                WHEN SUM(total_vendas_monitoradas) > 0 THEN
                    (CAST(SUM(qtd_vendas_madrugada)     AS DECIMAL(18,2)) /
                     CAST(SUM(total_vendas_monitoradas) AS DECIMAL(18,2))) * 100.0
                ELSE 0
            END
        AS DECIMAL(18,4)) AS percentual_madrugada_br
    FROM temp_CGUSC.fp.indicador_horario_atipico
),
CTE_Mediana_BR AS (
    SELECT DISTINCT
        CAST(
            PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY percentual_madrugada) OVER ()
        AS DECIMAL(18,4)) AS mediana_madrugada_br
    FROM temp_CGUSC.fp.indicador_horario_atipico
)
SELECT
    'BR'                    AS pais,
    M.total_vendas_br,
    M.total_madrugada_br,
    M.percentual_madrugada_br,
    D.mediana_madrugada_br
INTO temp_CGUSC.fp.indicador_horario_atipico_br
FROM CTE_Media_BR M
CROSS JOIN CTE_Mediana_BR D;


-- ============================================================================
-- PASSO 4B: MÉTRICAS POR REGIÃO DE SAÚDE
-- Média ponderada por volume + mediana via PERCENTILE_CONT OVER().
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_horario_atipico_regiao;

WITH CTE_Media_Reg AS (
    SELECT
        F.id_regiao_saude,
        SUM(I.total_vendas_monitoradas) AS total_vendas_regiao,
        SUM(I.qtd_vendas_madrugada)     AS total_madrugada_regiao,
        CAST(
            CASE
                WHEN SUM(I.total_vendas_monitoradas) > 0 THEN
                    (CAST(SUM(I.qtd_vendas_madrugada)     AS DECIMAL(18,2)) /
                     CAST(SUM(I.total_vendas_monitoradas) AS DECIMAL(18,2))) * 100.0
                ELSE 0
            END
        AS DECIMAL(18,4)) AS media_regiao
    FROM temp_CGUSC.fp.indicador_horario_atipico I
    INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj
    WHERE F.id_regiao_saude IS NOT NULL
    GROUP BY F.id_regiao_saude
),
CTE_Mediana_Reg AS (
    SELECT DISTINCT
        F.id_regiao_saude,
        CAST(
            PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.percentual_madrugada)
            OVER (PARTITION BY F.id_regiao_saude)
        AS DECIMAL(18,4)) AS mediana_regiao
    FROM temp_CGUSC.fp.indicador_horario_atipico I
    INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj
    WHERE F.id_regiao_saude IS NOT NULL
)
SELECT
    M.id_regiao_saude,
    M.total_vendas_regiao,
    M.total_madrugada_regiao,
    M.media_regiao AS regiao_saude_media,
    D.mediana_regiao AS regiao_saude_mediana
INTO temp_CGUSC.fp.indicador_horario_atipico_regiao
FROM CTE_Media_Reg M
INNER JOIN CTE_Mediana_Reg D ON D.id_regiao_saude = M.id_regiao_saude;

CREATE CLUSTERED INDEX IDX_IndHoraReg ON temp_CGUSC.fp.indicador_horario_atipico_regiao(id_regiao_saude);



-- ============================================================================
-- PASSO 5: TABELA CONSOLIDADA FINAL
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_horario_atipico_detalhado;

SELECT
    I.cnpj,
    F.razaoSocial,
    F.municipio,
    CAST(F.uf AS VARCHAR(2)) AS uf,
    F.no_regiao_saude,
    F.id_regiao_saude,

    -- Métricas Absolutas
    I.total_vendas_monitoradas,
    I.qtd_vendas_madrugada,
    I.percentual_madrugada,

    -- Rankings (pior risco = posição 1)
    RANK() OVER (
        ORDER BY I.percentual_madrugada DESC
    ) AS ranking_br,
    RANK() OVER (
        PARTITION BY CAST(F.uf AS VARCHAR(2))
        ORDER BY I.percentual_madrugada DESC
    ) AS ranking_uf,
    RANK() OVER (
        PARTITION BY F.id_regiao_saude
        ORDER BY I.percentual_madrugada DESC
    ) AS ranking_regiao_saude,
    RANK() OVER (
        PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255))
        ORDER BY I.percentual_madrugada DESC
    ) AS ranking_municipio,

    -- Comparativos Município
    ISNULL(MUN.percentual_madrugada_mun, 0) AS municipio_media,
    ISNULL(MUN.mediana_madrugada_mun,    0) AS municipio_mediana,

    -- Comparativos UF
    ISNULL(UF.percentual_madrugada_uf, 0) AS estado_media,
    ISNULL(UF.mediana_madrugada_uf,    0) AS estado_mediana,

    -- Comparativos Região de Saúde
    ISNULL(REG.regiao_saude_media,    0) AS regiao_saude_media,
    ISNULL(REG.regiao_saude_mediana,  0) AS regiao_saude_mediana,

    -- Comparativos BR
    BR.percentual_madrugada_br AS pais_media,
    BR.mediana_madrugada_br    AS pais_mediana,

    -- RISCO RELATIVO MUN
    CAST((I.percentual_madrugada + 0.01) / (ISNULL(MUN.percentual_madrugada_mun, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_media,

    -- RISCO RELATIVO UF
    CAST((I.percentual_madrugada + 0.01) / (ISNULL(UF.percentual_madrugada_uf, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_media,

    -- RISCO RELATIVO REGIÃO
    CAST((I.percentual_madrugada + 0.01) / (ISNULL(REG.regiao_saude_media, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_reg_media,

    -- RISCO RELATIVO BR
    CAST((I.percentual_madrugada + 0.01) / (BR.percentual_madrugada_br + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_media

INTO temp_CGUSC.fp.indicador_horario_atipico_detalhado
FROM temp_CGUSC.fp.indicador_horario_atipico I
INNER JOIN temp_CGUSC.fp.dados_farmacia F
    ON F.cnpj = I.cnpj
LEFT JOIN temp_CGUSC.fp.indicador_horario_atipico_mun MUN
    ON  CAST(F.uf        AS VARCHAR(2))   = MUN.uf
    AND CAST(F.municipio AS VARCHAR(255)) = MUN.municipio
LEFT JOIN temp_CGUSC.fp.indicador_horario_atipico_uf UF
    ON CAST(F.uf AS VARCHAR(2)) = UF.uf
LEFT JOIN temp_CGUSC.fp.indicador_horario_atipico_regiao REG
    ON F.id_regiao_saude = REG.id_regiao_saude
CROSS JOIN temp_CGUSC.fp.indicador_horario_atipico_br BR;

-- Índices Finais
CREATE CLUSTERED INDEX    IDX_FinalHora_CNPJ   ON temp_CGUSC.fp.indicador_horario_atipico_detalhado(cnpj);
CREATE NONCLUSTERED INDEX IDX_FinalHora_Risco  ON temp_CGUSC.fp.indicador_horario_atipico_detalhado(risco_relativo_uf_media DESC);
CREATE NONCLUSTERED INDEX IDX_FinalHora_Reg    ON temp_CGUSC.fp.indicador_horario_atipico_detalhado(risco_relativo_reg_media DESC);
CREATE NONCLUSTERED INDEX IDX_FinalHora_Pct    ON temp_CGUSC.fp.indicador_horario_atipico_detalhado(percentual_madrugada DESC);
CREATE NONCLUSTERED INDEX IDX_FinalHora_Rank   ON temp_CGUSC.fp.indicador_horario_atipico_detalhado(ranking_br);
GO


-- ============================================================================
-- LIMPEZA DAS TABELAS INTERMEDIÁRIAS
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_horario_atipico;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_horario_atipico_mun;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_horario_atipico_uf;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_horario_atipico_regiao;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_horario_atipico_br;
GO


-- ============================================================================
-- VERIFICAÇÃO RÁPIDA
-- ============================================================================
SELECT TOP 100 *
FROM temp_CGUSC.fp.indicador_horario_atipico_detalhado
ORDER BY ranking_br;
GO