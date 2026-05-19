USE [temp_CGUSC]
GO

-- ============================================================================
-- TABELA BASE: VOLUME ATIPICO SEMESTRAL
-- Objetivo:
--   Materializar os fatos semestrais crus para permitir que a aplicacao filtre
--   dinamicamente o percentual de crescimento atipico (ex: 40%, 50%, 500%)
--   sem recriar a matriz de risco.
--
-- Grao:
--   Uma linha por id_cnpj e semestre do calendario avaliado.
--
-- Importante:
--   Esta tabela NAO fixa limite de crescimento percentual. Ela guarda
--   taxa_crescimento_pct e o aumento absoluto para que a API aplique tambem
--   a regra de materialidade minima (ex: R$ 5.000).
--   O excesso acima dos limites escolhidos deve ser calculado na API:
--
--     CASE WHEN taxa_crescimento_pct > @limite
--           AND aumento_valor_semestre >= @limite_absoluto
--          THEN taxa_crescimento_pct - @limite
--          ELSE 0
--     END
--
-- Regra de periodo na aplicacao:
--   A API converte o periodo selecionado em chaves semestrais e filtra pelo
--   semestre avaliado. A chave anterior permite exibir a transicao no frontend.
--
-- status_semestre:
--   1 = comparavel
--   2 = sem_comparacao_anterior
--   3 = sem_movimentacao
--   4 = inicio_parcial_insuficiente
--
-- Regra de comparacao:
--   - O primeiro semestre com venda so vira base se tiver 4+ meses com venda.
--   - Se o primeiro semestre tiver 1 a 3 meses, ele nao compara e nao vira base.
--   - Apos existir uma base inicial, qualquer semestre com movimentacao compara
--     contra a base anterior aceita.
-- ============================================================================

SET NOCOUNT ON;

DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim    DATE = '2024-12-31';

PRINT '>> GERANDO temp_CGUSC.fp.volume_atipico_semestral...';

DROP TABLE IF EXISTS temp_CGUSC.fp.volume_atipico_semestral;
DROP TABLE IF EXISTS #medicamentos_patologia_gtin;
DROP TABLE IF EXISTS #vol_base_vendas_mensais;
DROP TABLE IF EXISTS #vol_cnpjs_universo;
DROP TABLE IF EXISTS #calendario_semestres;
DROP TABLE IF EXISTS #vol_base_semestres;

-- ============================================================================
-- PASSO 0: UNIVERSO DE GTINS ELEGIVEIS
-- Garante uma linha por codigo_barra para evitar multiplicar vendas no join.
-- ============================================================================
SELECT DISTINCT
    C.codigo_barra
INTO #medicamentos_patologia_gtin
FROM temp_CGUSC.fp.medicamentos_patologia C
WHERE C.codigo_barra IS NOT NULL;

CREATE UNIQUE CLUSTERED INDEX IDX_medicamentos_patologia_gtin
ON #medicamentos_patologia_gtin(codigo_barra);

-- ============================================================================
-- PASSO 1: VENDAS MENSAIS POR FARMACIA
-- ============================================================================
SELECT
    CAST(A.cnpj AS VARCHAR(14)) AS cnpj,
    YEAR(A.data_hora)  AS ano,
    MONTH(A.data_hora) AS mes,
    SUM(A.valor_pago)  AS valor_mes
INTO #vol_base_vendas_mensais
FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
INNER JOIN #medicamentos_patologia_gtin C
    ON C.codigo_barra = A.codigo_barra
WHERE A.data_hora >= @DataInicio
  AND A.data_hora < DATEADD(DAY, 1, @DataFim)
GROUP BY CAST(A.cnpj AS VARCHAR(14)), YEAR(A.data_hora), MONTH(A.data_hora);

CREATE CLUSTERED INDEX IDX_vol_base_vendas_mensais_cnpj
ON #vol_base_vendas_mensais(cnpj, ano, mes);

SELECT DISTINCT
    cnpj
INTO #vol_cnpjs_universo
FROM #vol_base_vendas_mensais;

CREATE UNIQUE CLUSTERED INDEX IDX_vol_cnpjs_universo_cnpj
ON #vol_cnpjs_universo(cnpj);

WITH Anos AS (
    SELECT YEAR(@DataInicio) AS ano
    UNION ALL
    SELECT ano + 1
    FROM Anos
    WHERE ano < YEAR(@DataFim)
),
Semestres AS (
    SELECT
        ano,
        CAST(1 AS TINYINT) AS semestre,
        DATEFROMPARTS(ano, 1, 1) AS data_inicio_semestre,
        EOMONTH(DATEFROMPARTS(ano, 6, 1)) AS data_fim_semestre
    FROM Anos

    UNION ALL

    SELECT
        ano,
        CAST(2 AS TINYINT) AS semestre,
        DATEFROMPARTS(ano, 7, 1) AS data_inicio_semestre,
        EOMONTH(DATEFROMPARTS(ano, 12, 1)) AS data_fim_semestre
    FROM Anos
)
SELECT
    ano,
    semestre,
    CAST(ano * 100 + semestre AS INT) AS chave_semestre,
    CAST(ano * 2 + semestre AS INT) AS ordem_semestre
INTO #calendario_semestres
FROM Semestres
WHERE data_fim_semestre >= @DataInicio
  AND data_inicio_semestre <= @DataFim
OPTION (MAXRECURSION 100);

CREATE UNIQUE CLUSTERED INDEX IDX_calendario_semestres_chave
ON #calendario_semestres(chave_semestre);

-- ============================================================================
-- PASSO 2: SEMESTRES COM MOVIMENTACAO
-- A regra nao exige valor minimo mensal. qtd_meses_presentes equivale a meses
-- com venda no semestre.
-- ============================================================================
WITH VendasSemestrais AS (
    SELECT
        cnpj,
        ano,
        CASE WHEN mes BETWEEN 1 AND 6 THEN 1 ELSE 2 END AS semestre,
        valor_mes
    FROM #vol_base_vendas_mensais
),
AgregadoSemestre AS (
    SELECT
        cnpj,
        ano,
        semestre,
        SUM(valor_mes)  AS valor_semestre,
        COUNT(*)        AS qtd_meses_presentes
    FROM VendasSemestrais
    GROUP BY cnpj, ano, semestre
)
SELECT
    U.cnpj,
    C.ano,
    C.semestre,
    C.chave_semestre,
    C.ordem_semestre,
    CAST(ISNULL(A.qtd_meses_presentes, 0) AS TINYINT) AS qtd_meses_presentes,
    CAST(ISNULL(A.valor_semestre, 0) AS DECIMAL(18,2)) AS valor_semestre
INTO #vol_base_semestres
FROM #vol_cnpjs_universo U
CROSS JOIN #calendario_semestres C
LEFT JOIN AgregadoSemestre A
    ON A.cnpj = U.cnpj
   AND A.ano = C.ano
   AND A.semestre = C.semestre;

CREATE CLUSTERED INDEX IDX_vol_base_semestres_cnpj
ON #vol_base_semestres(cnpj, chave_semestre);

IF EXISTS (
    SELECT 1
    FROM #vol_base_semestres S
    LEFT JOIN temp_CGUSC.fp.dados_farmacia F
        ON F.cnpj = S.cnpj
    WHERE F.id IS NULL
)
BEGIN
    THROW 51000, 'dados_farmacia sem id_cnpj obrigatorio para CNPJ com movimentacao.', 1;
END;

-- ============================================================================
-- PASSO 3: MATERIALIZACAO SEMESTRAL
-- ============================================================================
WITH SemestresComVenda AS (
    SELECT
        S.cnpj,
        S.chave_semestre,
        S.ordem_semestre,
        S.valor_semestre,
        S.qtd_meses_presentes,
        ROW_NUMBER() OVER (PARTITION BY S.cnpj ORDER BY S.ordem_semestre) AS rank_vendas
    FROM #vol_base_semestres S
    WHERE S.valor_semestre > 0
),
SemestresBase AS (
    SELECT
        V.cnpj,
        V.chave_semestre,
        V.valor_semestre,
        LAG(V.chave_semestre) OVER (PARTITION BY V.cnpj ORDER BY V.ordem_semestre) AS chave_semestre_anterior,
        LAG(V.valor_semestre) OVER (PARTITION BY V.cnpj ORDER BY V.ordem_semestre) AS valor_semestre_anterior
    FROM SemestresComVenda V
    WHERE NOT (V.rank_vendas = 1 AND V.qtd_meses_presentes < 4)
)
SELECT
    CAST(F.id AS INT) AS id_cnpj,
    S.chave_semestre,
    CAST(
        CASE
            WHEN S.valor_semestre <= 0 THEN 3
            WHEN V.rank_vendas = 1 AND S.qtd_meses_presentes < 4 THEN 4
            WHEN B.chave_semestre_anterior IS NOT NULL AND B.valor_semestre_anterior > 0 THEN 1
            ELSE 2
        END
    AS TINYINT) AS status_semestre,
    S.qtd_meses_presentes,
    B.chave_semestre_anterior,
    CAST(
        CASE
            WHEN B.valor_semestre_anterior > 0
                THEN S.valor_semestre - B.valor_semestre_anterior
            ELSE NULL
        END
    AS DECIMAL(18,2)) AS aumento_valor_semestre,
    CAST(
        CASE
            WHEN B.valor_semestre_anterior > 0
                THEN ((S.valor_semestre - B.valor_semestre_anterior) / CAST(B.valor_semestre_anterior AS DECIMAL(18,2))) * 100.0
            ELSE NULL
        END
    AS DECIMAL(9,2)) AS taxa_crescimento_pct
INTO temp_CGUSC.fp.volume_atipico_semestral
FROM #vol_base_semestres S
INNER JOIN temp_CGUSC.fp.dados_farmacia F
    ON F.cnpj = S.cnpj
LEFT JOIN SemestresComVenda V
    ON V.cnpj = S.cnpj
   AND V.chave_semestre = S.chave_semestre
LEFT JOIN SemestresBase B
    ON B.cnpj = S.cnpj
   AND B.chave_semestre = S.chave_semestre;

CREATE CLUSTERED INDEX IDX_volume_atipico_semestral_cnpj
ON temp_CGUSC.fp.volume_atipico_semestral(id_cnpj, chave_semestre);

CREATE NONCLUSTERED INDEX IDX_volume_atipico_semestral_filtro
ON temp_CGUSC.fp.volume_atipico_semestral(status_semestre, chave_semestre)
INCLUDE (id_cnpj, qtd_meses_presentes, chave_semestre_anterior, aumento_valor_semestre, taxa_crescimento_pct);

DROP TABLE IF EXISTS #vol_base_vendas_mensais;
DROP TABLE IF EXISTS #vol_cnpjs_universo;
DROP TABLE IF EXISTS #calendario_semestres;
DROP TABLE IF EXISTS #vol_base_semestres;
DROP TABLE IF EXISTS #medicamentos_patologia_gtin;

PRINT '>> temp_CGUSC.fp.volume_atipico_semestral criada com sucesso.';

GO

-- ============================================================================
-- VALIDACOES OBJETIVAS DO PIPELINE
-- ============================================================================
SELECT
    COUNT(*) AS total_linhas,
    COUNT(DISTINCT id_cnpj) AS total_cnpjs,
    COUNT(DISTINCT chave_semestre) AS total_semestres,
    MIN(chave_semestre) AS menor_chave_semestre,
    MAX(chave_semestre) AS maior_chave_semestre,
    SUM(CASE WHEN status_semestre = 1 THEN 1 ELSE 0 END) AS linhas_comparaveis,
    SUM(CASE WHEN status_semestre IN (3, 4) THEN 1 ELSE 0 END) AS linhas_nao_comparaveis
FROM temp_CGUSC.fp.volume_atipico_semestral;

SELECT
    COUNT(*) AS chaves_duplicadas
FROM (
    SELECT id_cnpj, chave_semestre
    FROM temp_CGUSC.fp.volume_atipico_semestral
    GROUP BY id_cnpj, chave_semestre
    HAVING COUNT(*) > 1
) D;

SELECT
    status_semestre,
    COUNT(*) AS total_linhas
FROM temp_CGUSC.fp.volume_atipico_semestral
GROUP BY status_semestre
ORDER BY status_semestre;
GO
