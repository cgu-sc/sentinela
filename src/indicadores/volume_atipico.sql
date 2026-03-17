USE [temp_CGUSC]
GO

-- ============================================================================
-- INDICADOR: VOLUME ATIPICO DE FATURAMENTO
-- Versao: 2.0 (Refatorado - Benchmarks sobre risco_final)
--
-- METODOLOGIA:
--   Detecta explosoes de crescimento semestral atipicas no faturamento.
--   Um semestre e considerado de "risco" quando cresce mais de 50% sobre o
--   semestre valido anterior.
--
--   RISCO_MAGNITUDE : Media dos excessos (quanto acima de 50% foi o salto)
--                     nos semestres onde houve risco. Mede a INTENSIDADE.
--   RISCO_FINAL     : Soma de todos os excessos / total de comparacoes feitas.
--                     Equivale a magnitude * frequencia. Mede o IMPACTO GERAL.
--                     Este e o valor exibido no relatorio e usado nos benchmarks.
-- ============================================================================

-- ============================================================================
-- PARAMETROS DO PERIODO E FILTROS
-- ============================================================================
DECLARE @DataInicio     DATE          = '2015-07-01';
DECLARE @DataFim        DATE          = '2024-09-30'; -- Parando em T3-2024 (completo)
DECLARE @ValorMinMensal DECIMAL(18,2) = 500.00;       -- Valor minimo mensal para semestre valido

-- ============================================================================
-- PASSO 1: VENDAS MENSAIS POR FARMACIA
-- Agrega o valor pago por farmacia, ano e mes dentro do periodo analisado.
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.vol_vendas_mensais;

SELECT
    A.cnpj,
    YEAR(A.data_hora)   AS ano,
    MONTH(A.data_hora)  AS mes,
    SUM(A.valor_pago)   AS valor_mes
INTO temp_CGUSC.fp.vol_vendas_mensais
FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
INNER JOIN temp_CGUSC.fp.medicamentos_patologia C
    ON C.codigo_barra = A.codigo_barra
WHERE A.data_hora >= @DataInicio
  AND A.data_hora <= @DataFim
GROUP BY A.cnpj, YEAR(A.data_hora), MONTH(A.data_hora);

CREATE CLUSTERED INDEX IDX_VendasMensais_CNPJ ON temp_CGUSC.fp.vol_vendas_mensais(cnpj, ano, mes);


-- ============================================================================
-- PASSO 2: SEMESTRES VALIDOS POR FARMACIA
-- Um semestre e valido se os 6 meses estao presentes E todos com valor > R$500.
-- Isso evita que meses de abertura/encerramento distorcam os calculos.
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.vol_semestres_validos;

WITH VendasSemestrais AS (
    SELECT
        cnpj,
        ano,
        CASE WHEN mes BETWEEN 1 AND 6 THEN 1 ELSE 2 END AS semestre,
        valor_mes,
        CASE WHEN valor_mes > @ValorMinMensal THEN 1 ELSE 0 END AS mes_valido
    FROM temp_CGUSC.fp.vol_vendas_mensais
),
AgregadoSemestre AS (
    SELECT
        cnpj,
        ano,
        semestre,
        SUM(valor_mes)  AS valor_semestre,
        COUNT(*)        AS qtd_meses_presentes,
        SUM(mes_valido) AS qtd_meses_validos
    FROM VendasSemestrais
    GROUP BY cnpj, ano, semestre
)
SELECT
    cnpj,
    ano,
    semestre,
    valor_semestre,
    (ano * 100 + semestre) AS chave_semestre  -- ex: 201901 = S1-2019, 201902 = S2-2019
INTO temp_CGUSC.fp.vol_semestres_validos
FROM AgregadoSemestre
WHERE qtd_meses_presentes = 6   -- todos os 6 meses devem estar presentes na base
  AND qtd_meses_validos   = 6;  -- todos com faturamento acima de R$500

CREATE CLUSTERED INDEX IDX_SemValid_CNPJ ON temp_CGUSC.fp.vol_semestres_validos(cnpj, ano, semestre);


-- ============================================================================
-- PASSO 2B: CONTAGEM DE SEMESTRES VALIDOS POR FARMACIA
-- Necessario para incluir farmacias com apenas 1 semestre valido no resultado
-- final (via LEFT JOIN no Passo 8), onde elas recebem risco = 0.
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.vol_semestres_validos_contagem;

SELECT
    cnpj,
    COUNT(*) AS total_semestres_validos
INTO temp_CGUSC.fp.vol_semestres_validos_contagem
FROM temp_CGUSC.fp.vol_semestres_validos
GROUP BY cnpj;

CREATE CLUSTERED INDEX IDX_SemCount_CNPJ ON temp_CGUSC.fp.vol_semestres_validos_contagem(cnpj);


-- ============================================================================
-- PASSO 3: CRESCIMENTO SEMESTRAL ENTRE SEMESTRES VALIDOS CONSECUTIVOS
-- Usa LAG para comparar cada semestre valido com o seu anterior.
-- Apenas farmacias com >= 2 semestres validos geram linhas aqui.
--
-- RISCO_SEMESTRAL: Excesso de crescimento alem do limite de 50%.
--   Cresceu 120% => risco_semestral = 120 - 50 = 70
--   Cresceu 30%  => risco_semestral = 0 (dentro do normal)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.vol_crescimento_semestral;

WITH SemComAnterior AS (
    SELECT
        S.cnpj,
        S.ano,
        S.semestre,
        S.chave_semestre,
        S.valor_semestre AS valor_atual,
        LAG(S.valor_semestre) OVER (PARTITION BY S.cnpj ORDER BY S.chave_semestre) AS valor_anterior,
        LAG(S.chave_semestre) OVER (PARTITION BY S.cnpj ORDER BY S.chave_semestre) AS chave_anterior
    FROM temp_CGUSC.fp.vol_semestres_validos S
)
SELECT
    cnpj,
    ano,
    semestre,
    chave_semestre,
    valor_atual,
    valor_anterior,
    chave_anterior,
    CAST(
        ((valor_atual - valor_anterior) / CAST(valor_anterior AS DECIMAL(18,2))) * 100.0
    AS DECIMAL(18,4)) AS taxa_crescimento,
    CAST(
        CASE
            WHEN ((valor_atual - valor_anterior) / CAST(valor_anterior AS DECIMAL(18,2))) * 100.0 > 50
                THEN (((valor_atual - valor_anterior) / CAST(valor_anterior AS DECIMAL(18,2))) * 100.0) - 50
            ELSE 0
        END
    AS DECIMAL(18,4)) AS risco_semestral
INTO temp_CGUSC.fp.vol_crescimento_semestral
FROM SemComAnterior
WHERE valor_anterior IS NOT NULL
  AND valor_anterior > 0;

CREATE CLUSTERED INDEX IDX_Cresc_CNPJ ON temp_CGUSC.fp.vol_crescimento_semestral(cnpj, ano, semestre);


-- ============================================================================
-- PASSO 4: AGREGACAO POR CNPJ
--
-- RISCO_MAGNITUDE : Media dos excessos apenas nos semestres com risco (> 0).
--                   Responde: "quando essa farmacia explode, o quao grave e?"
--
-- RISCO_FINAL     : Soma de todos os excessos / total de comparacoes.
--                   Equivale a risco_magnitude * (qtd_semestres_risco / qtd_comparacoes).
--                   Responde: "qual o impacto geral ao longo do historico?"
--                   >>> ESTE E O VALOR EXIBIDO NO RELATORIO E USADO NOS BENCHMARKS. <<<
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_volume_atipico;

SELECT
    C_AGG.cnpj,
    SC.total_semestres_validos                                              AS qtd_semestres_validos,
    COUNT(*)                                                                AS qtd_comparacoes,
    SUM(CASE WHEN C_AGG.risco_semestral > 0 THEN 1 ELSE 0 END)            AS qtd_semestres_risco,

    -- Magnitude: intensidade media dos saltos (considera apenas semestres com risco)
    CAST(
        CASE
            WHEN SUM(CASE WHEN C_AGG.risco_semestral > 0 THEN 1 ELSE 0 END) > 0
                THEN SUM(CASE WHEN C_AGG.risco_semestral > 0 THEN C_AGG.risco_semestral ELSE 0 END)
                   / CAST(SUM(CASE WHEN C_AGG.risco_semestral > 0 THEN 1 ELSE 0 END) AS DECIMAL(18,2))
            ELSE 0
        END
    AS DECIMAL(18,4)) AS risco_magnitude,

    -- Risco Final: impacto geral ponderado pela frequencia
    -- Formula simplificada: SUM(risco_semestral) / COUNT(*) comparacoes
    -- Isso e equivalente a: magnitude * (qtd_semestres_risco / qtd_comparacoes)
    CAST(
        SUM(C_AGG.risco_semestral) / CAST(COUNT(*) AS DECIMAL(18,2))
    AS DECIMAL(18,4)) AS risco_final

INTO temp_CGUSC.fp.indicador_volume_atipico
FROM temp_CGUSC.fp.vol_crescimento_semestral C_AGG
INNER JOIN temp_CGUSC.fp.vol_semestres_validos_contagem SC
    ON SC.cnpj = C_AGG.cnpj
GROUP BY C_AGG.cnpj, SC.total_semestres_validos;

-- Farmacias com apenas 1 semestre valido nao geram comparacoes e ficam de fora.
-- Elas serao incluidas no Passo 8 com risco = 0 via LEFT JOIN.

CREATE CLUSTERED INDEX IDX_IndVol_CNPJ ON temp_CGUSC.fp.indicador_volume_atipico(cnpj);


-- ============================================================================
-- PASSO 5: BENCHMARKS MUNICIPAIS (sobre risco_final)
-- Base: todas as farmacias com >= 1 semestre valido (inclui risco=0).
-- Usar ISNULL(risco_final, 0) garante que farmácias sem saltos atipicos entram
-- na media, evitando distorcao dos benchmarks para cima.
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_volume_atipico_mun;

SELECT DISTINCT
    CAST(F.uf AS VARCHAR(2))          AS uf,
    CAST(F.municipio AS VARCHAR(255)) AS municipio,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.risco_final, 0))
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255)))
    AS DECIMAL(18,4)) AS mediana_municipio,
    CAST(
        AVG(ISNULL(I.risco_final, 0))
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255)))
    AS DECIMAL(18,4)) AS media_municipio
INTO temp_CGUSC.fp.indicador_volume_atipico_mun
FROM temp_CGUSC.fp.vol_semestres_validos_contagem SC
INNER JOIN temp_CGUSC.fp.dados_farmacia F
    ON F.cnpj = SC.cnpj
LEFT JOIN temp_CGUSC.fp.indicador_volume_atipico I
    ON I.cnpj = SC.cnpj;

CREATE CLUSTERED INDEX IDX_IndVolMun_mun ON temp_CGUSC.fp.indicador_volume_atipico_mun(uf, municipio);


-- ============================================================================
-- PASSO 6: BENCHMARKS ESTADUAIS (sobre risco_final)
-- Base: todas as farmacias com >= 1 semestre valido (inclui risco=0).
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_volume_atipico_uf;

SELECT DISTINCT
    CAST(F.uf AS VARCHAR(2)) AS uf,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.risco_final, 0))
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)))
    AS DECIMAL(18,4)) AS mediana_estado,
    CAST(
        AVG(ISNULL(I.risco_final, 0))
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)))
    AS DECIMAL(18,4)) AS media_estado
INTO temp_CGUSC.fp.indicador_volume_atipico_uf
FROM temp_CGUSC.fp.vol_semestres_validos_contagem SC
INNER JOIN temp_CGUSC.fp.dados_farmacia F
    ON F.cnpj = SC.cnpj
LEFT JOIN temp_CGUSC.fp.indicador_volume_atipico I
    ON I.cnpj = SC.cnpj;

CREATE CLUSTERED INDEX IDX_IndVolUF_uf ON temp_CGUSC.fp.indicador_volume_atipico_uf(uf);


-- ============================================================================
-- PASSO 7: BENCHMARKS NACIONAIS (sobre risco_final)
-- Base: todas as farmacias com >= 1 semestre valido (inclui risco=0).
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_volume_atipico_br;

SELECT DISTINCT
    'BR' AS pais,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ISNULL(I.risco_final, 0)) OVER ()
    AS DECIMAL(18,4)) AS mediana_pais,
    CAST(
        AVG(ISNULL(I.risco_final, 0)) OVER ()
    AS DECIMAL(18,4)) AS media_pais
INTO temp_CGUSC.fp.indicador_volume_atipico_br
FROM temp_CGUSC.fp.vol_semestres_validos_contagem SC
LEFT JOIN temp_CGUSC.fp.indicador_volume_atipico I
    ON I.cnpj = SC.cnpj;


-- ============================================================================
-- PASSO 8: TABELA CONSOLIDADA FINAL
--
-- Base: vol_semestres_validos_contagem (inclui todas as farmacias com >= 1 semestre)
-- risco = 0 para farmacias sem comparacoes (LEFT JOIN com indicador_volume_atipico).
-- Risco Relativo: risco_final da farmacia vs media/mediana do grupo de referencia.
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_volume_atipico_detalhado;

SELECT
    SC.cnpj,
    F.razaoSocial,
    F.municipio,
    CAST(F.uf AS VARCHAR(2))                                AS uf,

    -- Contagens
    SC.total_semestres_validos                              AS qtd_semestres_validos,
    ISNULL(I.qtd_comparacoes, 0)                           AS qtd_comparacoes,
    ISNULL(I.qtd_semestres_risco, 0)                       AS qtd_semestres_risco,

    -- Scores auxiliares (para analise avancada)
    ISNULL(I.risco_magnitude, 0)                           AS risco_magnitude,
    CAST(
        CASE
            WHEN ISNULL(I.qtd_comparacoes, 0) = 0 THEN 0
            ELSE (CAST(ISNULL(I.qtd_semestres_risco, 0) AS DECIMAL(18,2)) / I.qtd_comparacoes) * 100.0
        END
    AS DECIMAL(18,4))                                      AS risco_frequencia,

    -- Score principal: ja calculado no Passo 4 e reutilizado aqui
    ISNULL(I.risco_final, 0)                               AS risco_final,

    -- Rankings (pior risco = posicao 1)
    RANK() OVER (
        ORDER BY ISNULL(I.risco_final, 0) DESC
    )                                                      AS ranking_br,
    RANK() OVER (
        PARTITION BY CAST(F.uf AS VARCHAR(2))
        ORDER BY ISNULL(I.risco_final, 0) DESC
    )                                                      AS ranking_uf,
    RANK() OVER (
        PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255))
        ORDER BY ISNULL(I.risco_final, 0) DESC
    )                                                      AS ranking_municipio,

    -- Benchmarks municipais
    ISNULL(MUN.mediana_municipio, 0)                       AS municipio_mediana,
    ISNULL(MUN.media_municipio,   0)                       AS municipio_media,
    CAST((ISNULL(I.risco_final, 0) + 0.01) / (ISNULL(MUN.mediana_municipio, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_mediana,
    CAST((ISNULL(I.risco_final, 0) + 0.01) / (ISNULL(MUN.media_municipio,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_media,

    -- Benchmarks estaduais
    ISNULL(UF.mediana_estado, 0)                           AS estado_mediana,
    ISNULL(UF.media_estado,   0)                           AS estado_media,
    CAST((ISNULL(I.risco_final, 0) + 0.01) / (ISNULL(UF.mediana_estado, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_mediana,
    CAST((ISNULL(I.risco_final, 0) + 0.01) / (ISNULL(UF.media_estado,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_media,

    -- Benchmarks nacionais
    BR.mediana_pais                                        AS pais_mediana,
    BR.media_pais                                          AS pais_media,
    CAST((ISNULL(I.risco_final, 0) + 0.01) / (BR.mediana_pais + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_mediana,
    CAST((ISNULL(I.risco_final, 0) + 0.01) / (BR.media_pais   + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_media

INTO temp_CGUSC.fp.indicador_volume_atipico_detalhado
FROM temp_CGUSC.fp.vol_semestres_validos_contagem SC
INNER JOIN temp_CGUSC.fp.dados_farmacia F
    ON F.cnpj = SC.cnpj
LEFT JOIN temp_CGUSC.fp.indicador_volume_atipico I
    ON I.cnpj = SC.cnpj
LEFT JOIN temp_CGUSC.fp.indicador_volume_atipico_mun MUN
    ON CAST(F.uf AS VARCHAR(2))          = MUN.uf
   AND CAST(F.municipio AS VARCHAR(255)) = MUN.municipio
LEFT JOIN temp_CGUSC.fp.indicador_volume_atipico_uf UF
    ON CAST(F.uf AS VARCHAR(2)) = UF.uf
CROSS JOIN temp_CGUSC.fp.indicador_volume_atipico_br BR;

CREATE CLUSTERED INDEX IDX_FinalVol_CNPJ     ON temp_CGUSC.fp.indicador_volume_atipico_detalhado(cnpj);
CREATE NONCLUSTERED INDEX IDX_FinalVol_Risco  ON temp_CGUSC.fp.indicador_volume_atipico_detalhado(risco_final DESC);
CREATE NONCLUSTERED INDEX IDX_FinalVol_RankBR ON temp_CGUSC.fp.indicador_volume_atipico_detalhado(ranking_br);
GO

-- ============================================================================
-- LIMPEZA DAS TABELAS INTERMEDIARIAS
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.vol_vendas_mensais;
DROP TABLE IF EXISTS temp_CGUSC.fp.vol_semestres_validos;
DROP TABLE IF EXISTS temp_CGUSC.fp.vol_semestres_validos_contagem;
DROP TABLE IF EXISTS temp_CGUSC.fp.vol_crescimento_semestral;
GO

-- ============================================================================
-- VERIFICACAO RAPIDA: TOP 100 por ranking nacional
-- ============================================================================
SELECT TOP 100 *
FROM temp_CGUSC.fp.indicador_volume_atipico_detalhado
ORDER BY ranking_br;

-- ============================================================================
-- DIAGNOSTICO: Todas as farmácias de um municipio especifico
-- Util para entender por que a media municipal esta alta.
-- Troque 'Dores do Turvo' e 'MG' pelo municipio de interesse.
-- ============================================================================
SELECT
    D.cnpj,
    D.razaoSocial,
    D.municipio,
    D.uf,
    D.qtd_semestres_validos,
    D.qtd_comparacoes,
    D.qtd_semestres_risco,
    D.risco_magnitude,
    D.risco_frequencia,
    D.risco_final,
    D.municipio_media,
    D.ranking_municipio
FROM temp_CGUSC.fp.indicador_volume_atipico_detalhado D
WHERE D.municipio = 'Dores do Turvo'
  AND D.uf       = 'MG'
ORDER BY D.risco_final DESC;