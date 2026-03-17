USE [temp_CGUSC]
GO

-- ============================================================================
-- INDICADOR DE EXCLUSIVIDADE DE CRMs - VERSÃO 2
-- ============================================================================
-- OBJETIVO: Medir quantos prescritores atuam EXCLUSIVAMENTE nesta farmácia
--
-- INTERPRETAÇÃO:
--   - Alta exclusividade (>80%): Pode indicar CRMs "cativos" ou fictícios
--   - Baixa exclusividade (<20%): Médicos compartilhados (normal em grandes redes)
--   - Exclusividade moderada (40-60%): Padrão esperado para farmácias independentes
--
-- ALTERAÇÕES APLICADAS:
--   1. Fonte dupla: UNION ALL de db_FarmaciaPopular.dbo.Relatorio_movimentacaoFP
--      e db_FarmaciaPopular.carga_2024.relatorio_movimentacaoFP_2021_2024 nos
--      Passos 0 e 1, garantindo COUNT(DISTINCT) correto entre as duas bases
--   2. Join em #CRMsPorFarmacia feito pelos campos tipados (nu_crm, sg_uf_crm)
--      em vez de CONCAT, eliminando ambiguidade de tipo e aproveitando o índice
--   3. Adicionado nível município (Passo 4: mediana e média), alinhado ao padrão
--      venda_per_capita; passos seguintes renumerados
--   4. Adicionados rankings explícitos por Brasil, UF e Município
--      (percentual_exclusividade DESC) na tabela final
--   5. Corrigido risco_baixa_dispersao_uf/_br: CASE WHEN agora verifica IS NOT NULL
--      antes da divisão, evitando NULL silencioso quando o LEFT JOIN com UF
--      não encontra correspondência (retorna 99.0 como esperado)
-- ============================================================================

-- ============================================================================
-- DEFINIÇÃO DE VARIÁVEIS
-- (sem GO após o USE para manter @DataInicio/@DataFim acessíveis em todo o batch)
-- ============================================================================
DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim    DATE = '2024-12-10';


-- ============================================================================
-- PASSO 0: IDENTIFICAR TODOS OS CRMs E EM QUANTOS ESTABELECIMENTOS ATUAM
-- O UNION ALL é feito antes do COUNT(DISTINCT cnpj) para que um mesmo par
-- crm+farmácia presente nas duas bases seja contado apenas uma vez.
-- ============================================================================
DROP TABLE IF EXISTS #CRMsGlobal;

SELECT
    crm                             AS nu_crm,
    crm_uf                          AS sg_uf_crm,
    COUNT(DISTINCT cnpj)            AS qtd_estabelecimentos_atua,
    COUNT(DISTINCT num_autorizacao) AS total_prescricoes_brasil,
    SUM(valor_pago)                 AS total_valor_brasil
INTO #CRMsGlobal
FROM (
    SELECT crm, crm_uf, cnpj, num_autorizacao, valor_pago
    FROM db_FarmaciaPopular.dbo.Relatorio_movimentacaoFP
    WHERE data_hora >= @DataInicio
      AND data_hora <= @DataFim
      AND crm IS NOT NULL
      AND crm_uf IS NOT NULL
      AND crm_uf <> 'BR'
      AND crm > 0

    UNION ALL

    SELECT crm, crm_uf, cnpj, num_autorizacao, valor_pago
    FROM db_FarmaciaPopular.carga_2024.relatorio_movimentacaoFP_2021_2024
    WHERE data_hora >= @DataInicio
      AND data_hora <= @DataFim
      AND crm IS NOT NULL
      AND crm_uf IS NOT NULL
      AND crm_uf <> 'BR'
      AND crm > 0
) U
GROUP BY crm, crm_uf;

CREATE CLUSTERED INDEX IDX_CRMGlobal ON #CRMsGlobal(nu_crm, sg_uf_crm);


-- ============================================================================
-- PASSO 1: BASE DE PRESCRITORES POR FARMÁCIA COM INFO DE EXCLUSIVIDADE
-- COUNT(DISTINCT num_autorizacao) e SUM(valor_pago) sobre o UNION ALL
-- para não duplicar registros presentes nas duas bases.
-- Join em #CRMsGlobal pelos campos tipados (nu_crm, sg_uf_crm).
-- ============================================================================
DROP TABLE IF EXISTS #CRMsPorFarmacia;

SELECT
    U.cnpj,
    CONCAT(U.crm, '/', U.crm_uf)     AS id_medico,
    U.crm                             AS nu_crm,
    U.crm_uf                          AS sg_uf_crm,
    COUNT(DISTINCT U.num_autorizacao) AS nu_prescricoes,
    SUM(U.valor_pago)                 AS vl_total_prescricoes,

    -- Info global do CRM
    G.qtd_estabelecimentos_atua,
    G.total_prescricoes_brasil        AS total_prescricoes_crm_brasil,

    -- Flag de exclusividade
    CASE
        WHEN G.qtd_estabelecimentos_atua = 1 THEN 1
        ELSE 0
    END AS flag_exclusivo

INTO #CRMsPorFarmacia
FROM (
    SELECT cnpj, crm, crm_uf, num_autorizacao, valor_pago
    FROM db_FarmaciaPopular.dbo.Relatorio_movimentacaoFP
    WHERE data_hora >= @DataInicio
      AND data_hora <= @DataFim
      AND crm IS NOT NULL
      AND crm_uf IS NOT NULL
      AND crm_uf <> 'BR'
      AND crm > 0

    UNION ALL

    SELECT cnpj, crm, crm_uf, num_autorizacao, valor_pago
    FROM db_FarmaciaPopular.carga_2024.relatorio_movimentacaoFP_2021_2024
    WHERE data_hora >= @DataInicio
      AND data_hora <= @DataFim
      AND crm IS NOT NULL
      AND crm_uf IS NOT NULL
      AND crm_uf <> 'BR'
      AND crm > 0
) U
INNER JOIN #CRMsGlobal G
    ON  G.nu_crm    = U.crm
    AND G.sg_uf_crm = U.crm_uf
GROUP BY U.cnpj, U.crm, U.crm_uf, G.qtd_estabelecimentos_atua, G.total_prescricoes_brasil;

CREATE CLUSTERED INDEX IDX_CRMFarm_CNPJ ON #CRMsPorFarmacia(cnpj);

DROP TABLE IF EXISTS #CRMsGlobal;


-- ============================================================================
-- PASSO 2: AGREGAÇÃO POR FARMÁCIA
-- ============================================================================
DROP TABLE IF EXISTS #ExclusividadePorFarmacia;

SELECT
    cnpj,

    COUNT(DISTINCT id_medico) AS total_prescritores,

    SUM(flag_exclusivo) AS qtd_prescritores_exclusivos,

    COUNT(DISTINCT CASE
        WHEN qtd_estabelecimentos_atua > 1 THEN id_medico
    END) AS qtd_prescritores_compartilhados,

    COUNT(DISTINCT CASE
        WHEN qtd_estabelecimentos_atua > 10 THEN id_medico
    END) AS qtd_prescritores_multi_rede,

    AVG(CAST(qtd_estabelecimentos_atua AS DECIMAL(18,2))) AS media_estabelecimentos_por_crm,

    SUM(nu_prescricoes)       AS total_prescricoes_farmacia,
    SUM(vl_total_prescricoes) AS total_valor_farmacia,

    SUM(CASE WHEN flag_exclusivo = 1 THEN nu_prescricoes       ELSE 0 END) AS prescricoes_de_exclusivos,
    SUM(CASE WHEN flag_exclusivo = 1 THEN vl_total_prescricoes ELSE 0 END) AS valor_de_exclusivos

INTO #ExclusividadePorFarmacia
FROM #CRMsPorFarmacia
GROUP BY cnpj;

CREATE CLUSTERED INDEX IDX_Excl_CNPJ ON #ExclusividadePorFarmacia(cnpj);

DROP TABLE IF EXISTS #CRMsPorFarmacia;


-- ============================================================================
-- PASSO 3: CÁLCULO BASE POR FARMÁCIA (INDICADOR EXCLUSIVIDADE)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_exclusividade_crm;

SELECT
    cnpj,
    total_prescritores,
    qtd_prescritores_exclusivos,
    qtd_prescritores_compartilhados,
    qtd_prescritores_multi_rede,
    media_estabelecimentos_por_crm,
    total_prescricoes_farmacia,
    total_valor_farmacia,
    prescricoes_de_exclusivos,
    valor_de_exclusivos,

    -- ÍNDICE DE EXCLUSIVIDADE (% de CRMs que atuam só aqui)
    CAST(
        CASE
            WHEN total_prescritores > 0 THEN
                (CAST(qtd_prescritores_exclusivos AS DECIMAL(18,2)) /
                 CAST(total_prescritores          AS DECIMAL(18,2))) * 100.0
            ELSE 0
        END
    AS DECIMAL(18,4)) AS percentual_exclusividade,

    -- ÍNDICE DE COMPARTILHAMENTO (% de CRMs em múltiplos locais)
    CAST(
        CASE
            WHEN total_prescritores > 0 THEN
                (CAST(qtd_prescritores_compartilhados AS DECIMAL(18,2)) /
                 CAST(total_prescritores              AS DECIMAL(18,2))) * 100.0
            ELSE 0
        END
    AS DECIMAL(18,4)) AS percentual_compartilhamento,

    -- ÍNDICE DE DISPERSÃO (% de CRMs em >10 estabelecimentos)
    CAST(
        CASE
            WHEN total_prescritores > 0 THEN
                (CAST(qtd_prescritores_multi_rede AS DECIMAL(18,2)) /
                 CAST(total_prescritores          AS DECIMAL(18,2))) * 100.0
            ELSE 0
        END
    AS DECIMAL(18,4)) AS percentual_multi_rede,

    -- PARTICIPAÇÃO DE EXCLUSIVOS NO VOLUME
    CAST(
        CASE
            WHEN total_prescricoes_farmacia > 0 THEN
                (CAST(prescricoes_de_exclusivos  AS DECIMAL(18,2)) /
                 CAST(total_prescricoes_farmacia AS DECIMAL(18,2))) * 100.0
            ELSE 0
        END
    AS DECIMAL(18,4)) AS percentual_volume_exclusivos,

    -- PARTICIPAÇÃO DE EXCLUSIVOS NO VALOR
    CAST(
        CASE
            WHEN total_valor_farmacia > 0 THEN
                (CAST(valor_de_exclusivos  AS DECIMAL(18,2)) /
                 CAST(total_valor_farmacia AS DECIMAL(18,2))) * 100.0
            ELSE 0
        END
    AS DECIMAL(18,4)) AS percentual_valor_exclusivos

INTO temp_CGUSC.fp.indicador_exclusividade_crm
FROM #ExclusividadePorFarmacia
WHERE total_prescritores > 0;

CREATE CLUSTERED INDEX IDX_IndExcl_CNPJ ON temp_CGUSC.fp.indicador_exclusividade_crm(cnpj);

DROP TABLE IF EXISTS #ExclusividadePorFarmacia;


-- ============================================================================
-- PASSO 4: MÉTRICAS POR MUNICÍPIO (MEDIANA E MÉDIA)
-- NOVO: alinhado ao padrão venda_per_capita
-- ============================================================================
PRINT 'PASSO 4: Calculando metricas por municipio...';

DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_exclusividade_crm_mun;

SELECT DISTINCT
    F.uf,
    F.municipio,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.percentual_exclusividade, 0))
        OVER (PARTITION BY F.uf, F.municipio)
    AS DECIMAL(18,4)) AS mediana_municipio,
    CAST(
        AVG(ISNULL(I.percentual_exclusividade, 0))
        OVER (PARTITION BY F.uf, F.municipio)
    AS DECIMAL(18,4)) AS media_municipio
INTO temp_CGUSC.fp.indicador_exclusividade_crm_mun
FROM temp_CGUSC.fp.dados_farmacia F
LEFT JOIN temp_CGUSC.fp.indicador_exclusividade_crm I ON I.cnpj = F.cnpj;

CREATE CLUSTERED INDEX IDX_IndExclMun ON temp_CGUSC.fp.indicador_exclusividade_crm_mun(uf, municipio);


-- ============================================================================
-- PASSO 5: CÁLCULO DAS MÉDIAS POR ESTADO (UF)
-- Preserva todas as colunas originais + acrescenta mediana (padrão venda_per_capita)
-- Estratégia: AVG via GROUP BY em CTE_Medias; PERCENTILE_CONT via OVER() em
-- CTE_Mediana (sem GROUP BY); join final pelos dois resultados.
-- ============================================================================
PRINT 'PASSO 5: Calculando metricas por estado...';

DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_exclusividade_crm_uf;

WITH CTE_Base AS (
    SELECT 
        F.uf,
        ISNULL(I.total_prescritores, 0)          AS total_prescritores,
        ISNULL(I.qtd_prescritores_exclusivos, 0) AS qtd_prescritores_exclusivos,
        ISNULL(I.media_estabelecimentos_por_crm, 0) AS media_estabelecimentos_por_crm,
        ISNULL(I.percentual_exclusividade, 0)    AS percentual_exclusividade,
        ISNULL(I.percentual_compartilhamento, 0) AS percentual_compartilhamento,
        ISNULL(I.percentual_multi_rede, 0)       AS percentual_multi_rede,
        ISNULL(I.percentual_volume_exclusivos, 0) AS percentual_volume_exclusivos,
        ISNULL(I.percentual_valor_exclusivos, 0)  AS percentual_valor_exclusivos
    FROM temp_CGUSC.fp.dados_farmacia F
    LEFT JOIN temp_CGUSC.fp.indicador_exclusividade_crm I ON I.cnpj = F.cnpj
),
CTE_Medias AS (
    SELECT
        uf,
        AVG(CAST(total_prescritores AS DECIMAL(18,2)))          AS media_prescritores_uf,
        AVG(CAST(qtd_prescritores_exclusivos AS DECIMAL(18,2))) AS media_exclusivos_uf,
        AVG(media_estabelecimentos_por_crm)                     AS media_dispersao_crm_uf,
        AVG(percentual_exclusividade)                           AS percentual_exclusividade_uf,
        AVG(percentual_compartilhamento)                        AS percentual_compartilhamento_uf,
        AVG(percentual_multi_rede)                              AS percentual_multi_rede_uf,
        AVG(percentual_volume_exclusivos)                       AS percentual_volume_exclusivos_uf,
        AVG(percentual_valor_exclusivos)                        AS percentual_valor_exclusivos_uf
    FROM CTE_Base
    GROUP BY uf
),
CTE_Mediana AS (
    SELECT DISTINCT
        uf,
        CAST(
            PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY percentual_exclusividade)
            OVER (PARTITION BY uf)
        AS DECIMAL(18,4)) AS mediana_exclusividade_uf
    FROM CTE_Base
)
SELECT
    M.uf,
    M.media_prescritores_uf,
    M.media_exclusivos_uf,
    M.media_dispersao_crm_uf,
    M.percentual_exclusividade_uf,
    M.percentual_compartilhamento_uf,
    M.percentual_multi_rede_uf,
    M.percentual_volume_exclusivos_uf,
    M.percentual_valor_exclusivos_uf,
    D.mediana_exclusividade_uf
INTO temp_CGUSC.fp.indicador_exclusividade_crm_uf
FROM CTE_Medias M
INNER JOIN CTE_Mediana D ON D.uf = M.uf;

CREATE CLUSTERED INDEX IDX_IndExclUF_uf ON temp_CGUSC.fp.indicador_exclusividade_crm_uf(uf);


-- ============================================================================
-- PASSO 5B: METRICAS POR REGIAO DE SAUDE (MEDIA E MEDIANA)
-- ============================================================================
PRINT 'PASSO 5B: Calculando metricas por regiao de saude...';

DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_exclusividade_crm_regiao;

WITH CTE_Base_Reg AS (
    SELECT 
        F.id_regiao_saude,
        ISNULL(I.percentual_exclusividade, 0) AS percentual_exclusividade
    FROM temp_CGUSC.fp.dados_farmacia F
    LEFT JOIN temp_CGUSC.fp.indicador_exclusividade_crm I ON I.cnpj = F.cnpj
    WHERE F.id_regiao_saude IS NOT NULL
)
SELECT DISTINCT
    id_regiao_saude,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY percentual_exclusividade)
        OVER (PARTITION BY id_regiao_saude)
    AS DECIMAL(18,4)) AS mediana_regiao,
    CAST(
        AVG(percentual_exclusividade)
        OVER (PARTITION BY id_regiao_saude)
    AS DECIMAL(18,4)) AS media_regiao
INTO temp_CGUSC.fp.indicador_exclusividade_crm_regiao
FROM CTE_Base_Reg;

CREATE CLUSTERED INDEX IDX_IndExclReg ON temp_CGUSC.fp.indicador_exclusividade_crm_regiao(id_regiao_saude);


-- ============================================================================
-- PASSO 6: CÁLCULO DA MÉDIA NACIONAL (BRASIL)
-- Preserva todas as colunas originais + acrescenta mediana (padrão venda_per_capita)
-- Estratégia: AVG simples (sem OVER) para as médias; PERCENTILE_CONT OVER()
-- para a mediana; SELECT DISTINCT elimina a duplicação de linhas do OVER().
-- ============================================================================
PRINT 'PASSO 6: Calculando metricas nacionais...';

DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_exclusividade_crm_br;

WITH CTE_Base_BR AS (
    SELECT 
        ISNULL(total_prescritores, 0)          AS total_prescritores,
        ISNULL(qtd_prescritores_exclusivos, 0) AS qtd_prescritores_exclusivos,
        ISNULL(media_estabelecimentos_por_crm, 0) AS media_estabelecimentos_por_crm,
        ISNULL(percentual_exclusividade, 0)    AS percentual_exclusividade,
        ISNULL(percentual_compartilhamento, 0) AS percentual_compartilhamento,
        ISNULL(percentual_multi_rede, 0)       AS percentual_multi_rede,
        ISNULL(percentual_volume_exclusivos, 0) AS percentual_volume_exclusivos,
        ISNULL(percentual_valor_exclusivos, 0)  AS percentual_valor_exclusivos
    FROM temp_CGUSC.fp.dados_farmacia F
    LEFT JOIN temp_CGUSC.fp.indicador_exclusividade_crm I ON I.cnpj = F.cnpj
),
CTE_Medias_BR AS (
    SELECT
        AVG(CAST(total_prescritores          AS DECIMAL(18,2))) AS media_prescritores_br,
        AVG(CAST(qtd_prescritores_exclusivos AS DECIMAL(18,2))) AS media_exclusivos_br,
        AVG(media_estabelecimentos_por_crm)                     AS media_dispersao_crm_br,
        AVG(percentual_exclusividade)                           AS percentual_exclusividade_br,
        AVG(percentual_compartilhamento)                        AS percentual_compartilhamento_br,
        AVG(percentual_multi_rede)                              AS percentual_multi_rede_br,
        AVG(percentual_volume_exclusivos)                       AS percentual_volume_exclusivos_br,
        AVG(percentual_valor_exclusivos)                        AS percentual_valor_exclusivos_br
    FROM CTE_Base_BR
),
CTE_Mediana_BR AS (
    SELECT DISTINCT
        CAST(
            PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY percentual_exclusividade) OVER ()
        AS DECIMAL(18,4)) AS mediana_exclusividade_br
    FROM CTE_Base_BR
)
SELECT
    'BR'                        AS pais,
    M.media_prescritores_br,
    M.media_exclusivos_br,
    M.media_dispersao_crm_br,
    M.percentual_exclusividade_br,
    M.percentual_compartilhamento_br,
    M.percentual_multi_rede_br,
    M.percentual_volume_exclusivos_br,
    M.percentual_valor_exclusivos_br,
    D.mediana_exclusividade_br
INTO temp_CGUSC.fp.indicador_exclusividade_crm_br
FROM CTE_Medias_BR M
CROSS JOIN CTE_Mediana_BR D;


-- ============================================================================
-- PASSO 7: TABELA CONSOLIDADA FINAL
-- ============================================================================
PRINT 'PASSO 7: Gerando tabela consolidada com riscos relativos e rankings...';

DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_exclusividade_crm_detalhado;

SELECT
    F.cnpj,
    F.razaoSocial,
    F.municipio,
    F.uf,
    F.no_regiao_saude,
    F.id_regiao_saude,

    -- Metricas Absolutas
    ISNULL(I.total_prescritores, 0)          AS total_prescritores,
    ISNULL(I.qtd_prescritores_exclusivos, 0) AS qtd_prescritores_exclusivos,
    ISNULL(I.qtd_prescritores_compartilhados, 0) AS qtd_prescritores_compartilhados,
    ISNULL(I.qtd_prescritores_multi_rede, 0) AS qtd_prescritores_multi_rede,
    ISNULL(I.media_estabelecimentos_por_crm, 0) AS media_estabelecimentos_por_crm,
    ISNULL(I.total_prescricoes_farmacia, 0)  AS total_prescricoes_farmacia,
    ISNULL(I.total_valor_farmacia, 0)       AS total_valor_farmacia,
    ISNULL(I.prescricoes_de_exclusivos, 0)  AS prescricoes_de_exclusivos,
    ISNULL(I.valor_de_exclusivos, 0)       AS valor_de_exclusivos,

    -- Indices Principais
    ISNULL(I.percentual_exclusividade, 0)    AS percentual_exclusividade,
    ISNULL(I.percentual_compartilhamento, 0) AS percentual_compartilhamento,
    ISNULL(I.percentual_multi_rede, 0)       AS percentual_multi_rede,
    ISNULL(I.percentual_volume_exclusivos, 0) AS percentual_volume_exclusivos,
    ISNULL(I.percentual_valor_exclusivos, 0)  AS percentual_valor_exclusivos,

    -- Rankings (pior risco = posicao 1)
    RANK() OVER (
        ORDER BY ISNULL(I.percentual_exclusividade, 0) DESC
    ) AS ranking_br,
    RANK() OVER (
        PARTITION BY F.uf
        ORDER BY ISNULL(I.percentual_exclusividade, 0) DESC
    ) AS ranking_uf,
    RANK() OVER (
        PARTITION BY F.id_regiao_saude
        ORDER BY ISNULL(I.percentual_exclusividade, 0) DESC
    ) AS ranking_regiao_saude,
    RANK() OVER (
        PARTITION BY F.uf, F.municipio
        ORDER BY ISNULL(I.percentual_exclusividade, 0) DESC
    ) AS ranking_municipio,

    -- Benchmarks Municipio
    ISNULL(MUN.mediana_municipio, 0) AS municipio_mediana,
    ISNULL(MUN.media_municipio,   0) AS municipio_media,
    CAST((ISNULL(I.percentual_exclusividade, 0) + 0.01) / (ISNULL(MUN.mediana_municipio, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_mediana,
    CAST((ISNULL(I.percentual_exclusividade, 0) + 0.01) / (ISNULL(MUN.media_municipio,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_media,

    -- Benchmarks UF
    ISNULL(UF.mediana_exclusividade_uf, 0)      AS estado_mediana,
    ISNULL(UF.percentual_exclusividade_uf, 0) AS estado_media,
    CAST((ISNULL(I.percentual_exclusividade, 0) + 0.01) / (ISNULL(UF.mediana_exclusividade_uf, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_mediana,
    CAST((ISNULL(I.percentual_exclusividade, 0) + 0.01) / (ISNULL(UF.percentual_exclusividade_uf, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_media,

    -- Benchmarks Regional (Regiao de Saude)
    ISNULL(REG.mediana_regiao, 0) AS regiao_saude_mediana,
    ISNULL(REG.media_regiao,   0) AS regiao_saude_media,
    CAST((ISNULL(I.percentual_exclusividade, 0) + 0.01) / (ISNULL(REG.mediana_regiao, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_reg_mediana,
    CAST((ISNULL(I.percentual_exclusividade, 0) + 0.01) / (ISNULL(REG.media_regiao,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_reg_media,

    -- Benchmarks BR
    BR.mediana_exclusividade_br    AS pais_mediana,
    BR.percentual_exclusividade_br AS pais_media,
    CAST((ISNULL(I.percentual_exclusividade, 0) + 0.01) / (BR.mediana_exclusividade_br + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_mediana,
    CAST((ISNULL(I.percentual_exclusividade, 0) + 0.01) / (BR.percentual_exclusividade_br + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_media,

    -- RISCOS ADICIONAIS ORIGINAIS (Dispersao e Volume/Valor)
    ISNULL(UF.media_dispersao_crm_uf,          0) AS dispersao_estado,
    ISNULL(UF.percentual_volume_exclusivos_uf, 0) AS volume_exclusivos_estado,
    BR.media_dispersao_crm_br          AS dispersao_pais,
    BR.percentual_volume_exclusivos_br AS volume_exclusivos_pais,

    -- RISCO INVERSO DE DISPERSÃO (Quanto MENOR a dispersao, MAIOR o risco)
    CAST(
        CASE
            WHEN ISNULL(I.media_estabelecimentos_por_crm, 0) > 0
             AND UF.media_dispersao_crm_uf IS NOT NULL THEN
                UF.media_dispersao_crm_uf / I.media_estabelecimentos_por_crm
            ELSE 99.0
        END
    AS DECIMAL(18,4)) AS risco_baixa_dispersao_uf,

    CAST(
        CASE
            WHEN ISNULL(I.media_estabelecimentos_por_crm, 0) > 0
             AND BR.media_dispersao_crm_br IS NOT NULL THEN
                BR.media_dispersao_crm_br / I.media_estabelecimentos_por_crm
            ELSE 99.0
        END
    AS DECIMAL(18,4)) AS risco_baixa_dispersao_br,

    -- Classificacao de Risco (original preservado)
    CASE
        WHEN ISNULL(I.percentual_exclusividade, 0) >= 80 THEN 'MUITO ALTO'
        WHEN ISNULL(I.percentual_exclusividade, 0) >= 60 THEN 'ALTO'
        WHEN ISNULL(I.percentual_exclusividade, 0) >= 40 THEN 'MODERADO'
        WHEN ISNULL(I.percentual_exclusividade, 0) >= 20 THEN 'BAIXO'
        ELSE 'MUITO BAIXO'
    END AS classificacao_exclusividade

INTO temp_CGUSC.fp.indicador_exclusividade_crm_detalhado
FROM temp_CGUSC.fp.dados_farmacia F
LEFT JOIN temp_CGUSC.fp.indicador_exclusividade_crm I
    ON I.cnpj = F.cnpj
LEFT JOIN temp_CGUSC.fp.indicador_exclusividade_crm_mun MUN
    ON  F.uf        = MUN.uf
    AND F.municipio = MUN.municipio
LEFT JOIN temp_CGUSC.fp.indicador_exclusividade_crm_uf UF
    ON F.uf = UF.uf
LEFT JOIN temp_CGUSC.fp.indicador_exclusividade_crm_regiao REG
    ON F.id_regiao_saude = REG.id_regiao_saude
CROSS JOIN temp_CGUSC.fp.indicador_exclusividade_crm_br BR;

-- Índices Finais (originais preservados + novo por ranking_br)
CREATE CLUSTERED INDEX    IDX_FinalExcl_CNPJ       ON temp_CGUSC.fp.indicador_exclusividade_crm_detalhado(cnpj);
CREATE NONCLUSTERED INDEX IDX_FinalExcl_Risco       ON temp_CGUSC.fp.indicador_exclusividade_crm_detalhado(risco_relativo_uf_media DESC);
CREATE NONCLUSTERED INDEX IDX_FinalExcl_Percentual  ON temp_CGUSC.fp.indicador_exclusividade_crm_detalhado(percentual_exclusividade DESC);
CREATE NONCLUSTERED INDEX IDX_FinalExcl_RankBR      ON temp_CGUSC.fp.indicador_exclusividade_crm_detalhado(ranking_br);
GO


-- ============================================================================
-- LIMPEZA DAS TABELAS INTERMEDIARIAS
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_exclusividade_crm;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_exclusividade_crm_mun;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_exclusividade_crm_uf;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_exclusividade_crm_regiao;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_exclusividade_crm_br;
GO


-- ============================================================================
-- VERIFICAÇÃO RÁPIDA
-- ============================================================================
SELECT TOP 100 *
FROM temp_CGUSC.fp.indicador_exclusividade_crm_detalhado
ORDER BY ranking_br;
GO
