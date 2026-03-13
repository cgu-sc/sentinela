USE [temp_CGUSC]
GO

-- ============================================================================
-- DEFINICAO DE VARIAVEIS DO PERIODO
-- ============================================================================
DECLARE @DataInicio     DATE          = '2015-07-01';
DECLARE @DataFim        DATE          = '2024-09-30'; -- Parando em T3-2024 (completo)
DECLARE @ValorMinMensal DECIMAL(18,2) = 500.00;       -- Valor minimo mensal para semestre valido


-- ============================================================================
-- PASSO 1: VENDAS MENSAIS POR FARMACIA (MENSAGENS AUDITADOS)
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
-- Um semestre e valido se os 6 meses estao presentes e todos com valor > @ValorMinMensal
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.vol_semestres_validos;

WITH VendasSemestrais AS (
    SELECT
        cnpj,
        ano,
        CASE
            WHEN mes BETWEEN 1 AND 6 THEN 1
            ELSE 2
        END AS semestre,
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
    (ano * 10 + semestre) AS chave_semestre  -- ex: 20201=S1-2020, 20202=S2-2020
INTO temp_CGUSC.fp.vol_semestres_validos
FROM AgregadoSemestre
WHERE qtd_meses_presentes = 6   -- os 6 meses precisam existir na base
  AND qtd_meses_validos   = 6;  -- todos com valor > @ValorMinMensal

CREATE CLUSTERED INDEX IDX_SemValid_CNPJ ON temp_CGUSC.fp.vol_semestres_validos(cnpj, ano, semestre);


-- ============================================================================
-- PASSO 2B: PRE-CONTAGEM DE SEMESTRES VALIDOS POR FARMACIA
-- Necessario para calcular frequencia corretamente depois.
-- Uma farmacia precisa de >= 2 semestres validos para ter comparacao.
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
-- PASSO 3: CALCULO DE CRESCIMENTO SEMESTRAL
-- LAG sobre semestres validos: pula automaticamente os invalidos.
-- Apenas farmacias com >= 2 semestres validos geram comparacoes.
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.vol_crescimento_semestral;

WITH SemComAnterior AS (
    SELECT
        S.cnpj,
        S.ano,
        S.semestre,
        S.chave_semestre,
        S.valor_semestre AS valor_atual,
        LAG(S.valor_semestre) OVER (
            PARTITION BY S.cnpj
            ORDER BY S.chave_semestre
        ) AS valor_anterior,
        LAG(S.chave_semestre) OVER (
            PARTITION BY S.cnpj
            ORDER BY S.chave_semestre
        ) AS chave_anterior
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
    -- Taxa de crescimento em %
    CAST(
        ((valor_atual - valor_anterior) / CAST(valor_anterior AS DECIMAL(18,2))) * 100.0
    AS DECIMAL(18,4)) AS taxa_crescimento,
    -- Risco semestral com penalizacao progressiva (threshold 50%)
    CAST(
        CASE
            WHEN valor_anterior IS NULL OR valor_anterior = 0 THEN 0
            WHEN ((valor_atual - valor_anterior) / CAST(valor_anterior AS DECIMAL(18,2))) * 100.0 > 50
                THEN (((valor_atual - valor_anterior) / CAST(valor_anterior AS DECIMAL(18,2))) * 100.0) - 50
            ELSE 0
        END
    AS DECIMAL(18,4)) AS risco_semestral
INTO temp_CGUSC.fp.vol_crescimento_semestral
FROM SemComAnterior
-- Apenas comparacoes validas: precisa ter semestre anterior
WHERE valor_anterior IS NOT NULL
  AND valor_anterior > 0;

-- Neste ponto, cada linha representa UMA COMPARACAO entre dois semestres consecutivos validos.
-- Uma farmacia com N semestres validos gera (N-1) comparacoes aqui.

CREATE CLUSTERED INDEX IDX_Cresc_CNPJ ON temp_CGUSC.fp.vol_crescimento_semestral(cnpj, ano, semestre);


-- ============================================================================
-- PASSO 4: AGREGACAO FINAL POR CNPJ
--
-- qtd_semestres_validos vem da contagem real (Passo 2B), nao do numero de comparacoes.
-- risco_frequencia = qtd_semestres_risco / qtd_comparacoes
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_volume_atipico;

SELECT
    C_AGG.cnpj,
    SC.total_semestres_validos                                          AS qtd_semestres_validos,
    COUNT(C_AGG.cnpj)                                                   AS qtd_comparacoes,
    SUM(CASE WHEN C_AGG.risco_semestral > 0 THEN 1 ELSE 0 END)         AS qtd_semestres_risco,
    -- Magnitude: media dos riscos positivos
    CAST(
        CASE
            WHEN SUM(CASE WHEN C_AGG.risco_semestral > 0 THEN 1 ELSE 0 END) > 0
                THEN SUM(CASE WHEN C_AGG.risco_semestral > 0 THEN C_AGG.risco_semestral ELSE 0 END)
                   / CAST(SUM(CASE WHEN C_AGG.risco_semestral > 0 THEN 1 ELSE 0 END) AS DECIMAL(18,2))
            ELSE 0
        END
    AS DECIMAL(18,4)) AS risco_magnitude
INTO temp_CGUSC.fp.indicador_volume_atipico
FROM temp_CGUSC.fp.vol_crescimento_semestral C_AGG
INNER JOIN temp_CGUSC.fp.vol_semestres_validos_contagem SC
    ON SC.cnpj = C_AGG.cnpj
GROUP BY C_AGG.cnpj, SC.total_semestres_validos;

-- NOTA: Farmacias com apenas 1 semestre valido NAO aparecem aqui,
-- pois nao geram nenhuma linha em vol_crescimento_semestral.
-- Elas serao incluidas no Passo 8 com risco=0 via LEFT JOIN.

CREATE CLUSTERED INDEX IDX_IndVol_CNPJ ON temp_CGUSC.fp.indicador_volume_atipico(cnpj);


-- ============================================================================
-- PASSO 5: METRICAS POR MUNICIPIO (MEDIA E MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_volume_atipico_mun;

SELECT DISTINCT
    CAST(F.uf AS VARCHAR(2))          AS uf,
    CAST(F.municipio AS VARCHAR(255)) AS municipio,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.risco_magnitude)
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255)))
    AS DECIMAL(18,4)) AS mediana_municipio,
    CAST(
        AVG(I.risco_magnitude)
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255)))
    AS DECIMAL(18,4)) AS media_municipio
INTO temp_CGUSC.fp.indicador_volume_atipico_mun
FROM temp_CGUSC.fp.indicador_volume_atipico I
INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj;

CREATE CLUSTERED INDEX IDX_IndVolMun_mun ON temp_CGUSC.fp.indicador_volume_atipico_mun(uf, municipio);


-- ============================================================================
-- PASSO 6: METRICAS POR ESTADO (MEDIA E MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_volume_atipico_uf;

SELECT DISTINCT
    CAST(F.uf AS VARCHAR(2)) AS uf,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.risco_magnitude)
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)))
    AS DECIMAL(18,4)) AS mediana_estado,
    CAST(
        AVG(I.risco_magnitude)
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)))
    AS DECIMAL(18,4)) AS media_estado
INTO temp_CGUSC.fp.indicador_volume_atipico_uf
FROM temp_CGUSC.fp.indicador_volume_atipico I
INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj;

CREATE CLUSTERED INDEX IDX_IndVolUF_uf ON temp_CGUSC.fp.indicador_volume_atipico_uf(uf);


-- ============================================================================
-- PASSO 7: METRICA NACIONAL (MEDIA E MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_volume_atipico_br;

SELECT DISTINCT
    'BR' AS pais,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY risco_magnitude) OVER ()
    AS DECIMAL(18,4)) AS mediana_pais,
    CAST(
        AVG(risco_magnitude) OVER ()
    AS DECIMAL(18,4)) AS media_pais
INTO temp_CGUSC.fp.indicador_volume_atipico_br
FROM temp_CGUSC.fp.indicador_volume_atipico;


-- ============================================================================
-- PASSO 8: TABELA CONSOLIDADA FINAL
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_volume_atipico_detalhado;

SELECT
    SC.cnpj,
    F.razaoSocial,
    F.municipio,
    CAST(F.uf AS VARCHAR(2)) AS uf,

    -- Contagens
    SC.total_semestres_validos                              AS qtd_semestres_validos,
    ISNULL(I.qtd_comparacoes, 0)                           AS qtd_comparacoes,
    ISNULL(I.qtd_semestres_risco, 0)                       AS qtd_semestres_risco,

    -- Scores da farmacia
    ISNULL(I.risco_magnitude, 0)                           AS risco_magnitude,
    CAST(
        CASE
            WHEN ISNULL(I.qtd_comparacoes, 0) = 0 THEN 0
            ELSE (CAST(I.qtd_semestres_risco AS DECIMAL(18,2)) / I.qtd_comparacoes) * 100.0
        END
    AS DECIMAL(18,4))                                      AS risco_frequencia,
    CAST(
        CASE
            WHEN ISNULL(I.qtd_comparacoes, 0) = 0 THEN 0
            ELSE ISNULL(I.risco_magnitude, 0)
               * (CAST(I.qtd_semestres_risco AS DECIMAL(18,2)) / I.qtd_comparacoes)
        END
    AS DECIMAL(18,4))                                      AS risco_final,

    -- Rankings (pior risco = posicao 1)
    RANK() OVER (
        ORDER BY CASE
            WHEN ISNULL(I.qtd_comparacoes, 0) = 0 THEN 0
            ELSE ISNULL(I.risco_magnitude, 0)
               * (CAST(I.qtd_semestres_risco AS DECIMAL(18,2)) / I.qtd_comparacoes)
        END DESC
    )                                                      AS ranking_br,
    RANK() OVER (
        PARTITION BY CAST(F.uf AS VARCHAR(2))
        ORDER BY CASE
            WHEN ISNULL(I.qtd_comparacoes, 0) = 0 THEN 0
            ELSE ISNULL(I.risco_magnitude, 0)
               * (CAST(I.qtd_semestres_risco AS DECIMAL(18,2)) / I.qtd_comparacoes)
        END DESC
    )                                                      AS ranking_uf,
    RANK() OVER (
        PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255))
        ORDER BY CASE
            WHEN ISNULL(I.qtd_comparacoes, 0) = 0 THEN 0
            ELSE ISNULL(I.risco_magnitude, 0)
               * (CAST(I.qtd_semestres_risco AS DECIMAL(18,2)) / I.qtd_comparacoes)
        END DESC
    )                                                      AS ranking_municipio,

    -- Benchmarks municipais
    ISNULL(MUN.mediana_municipio, 0)                       AS municipio_mediana,
    ISNULL(MUN.media_municipio,   0)                       AS municipio_media,
    CAST((ISNULL(I.risco_magnitude, 0) + 0.01) / (ISNULL(MUN.mediana_municipio, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_mediana,
    CAST((ISNULL(I.risco_magnitude, 0) + 0.01) / (ISNULL(MUN.media_municipio,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_media,

    -- Benchmarks estaduais
    ISNULL(UF.mediana_estado, 0)                           AS estado_mediana,
    ISNULL(UF.media_estado,   0)                           AS estado_media,
    CAST((ISNULL(I.risco_magnitude, 0) + 0.01) / (ISNULL(UF.mediana_estado, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_mediana,
    CAST((ISNULL(I.risco_magnitude, 0) + 0.01) / (ISNULL(UF.media_estado,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_media,

    -- Benchmarks nacionais
    BR.mediana_pais                                        AS pais_mediana,
    BR.media_pais                                          AS pais_media,
    CAST((ISNULL(I.risco_magnitude, 0) + 0.01) / (BR.mediana_pais + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_mediana,
    CAST((ISNULL(I.risco_magnitude, 0) + 0.01) / (BR.media_pais   + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_media

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

-- Verificacao rapida
SELECT TOP 100 *
FROM temp_CGUSC.fp.indicador_volume_atipico_detalhado
ORDER BY ranking_br;