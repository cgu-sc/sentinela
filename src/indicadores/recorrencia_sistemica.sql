USE [temp_CGUSC]
GO

-- ============================================================================
-- INDICADOR DE RECORRENCIA SISTEMICA
-- ============================================================================
-- OBJETIVO: Identificar farmacias com alta proporcao de compras de medicamentos
--           de uso continuo realizadas exatamente no limite do bloqueio legal.
--
-- METRICA PRINCIPAL:
--   percentual_recorrencia_sistemica representa o percentual anual de renovacoes
--   que ocorreram entre PROXIMA_COMPRA e PROXIMA_COMPRA + 1 dia.
--
-- FONTE DE DADOS:
--   - db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024
--   - temp_CGUSC.fp.medicamentos_patologia
--   - temp_CGUSC.fp.posologia_tempo_bloqueio
--   - temp_CGUSC.fp.dados_farmacia (id_cnpj e contexto territorial)
-- ============================================================================

-- ============================================================================
-- LIMPEZA PREVIA DE TABELAS
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_recorrencia_sistemica;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_recorrencia_sistemica_mun;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_recorrencia_sistemica_uf;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_recorrencia_sistemica_regiao;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_recorrencia_sistemica_br;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_recorrencia_sistemica_detalhado;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_controle_recorrencia_sistemica;
GO

-- ============================================================================
-- DEFINICAO DE VARIAVEIS
-- ============================================================================
DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim    DATE = '2024-12-10';


-- ============================================================================
-- PASSO 0: DIMENSOES E FONTES OBRIGATORIAS
-- ============================================================================
IF OBJECT_ID('temp_CGUSC.fp.medicamentos_patologia', 'U') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.medicamentos_patologia nao encontrada.', 16, 1);
    RETURN;
END;

IF COL_LENGTH('temp_CGUSC.fp.medicamentos_patologia', 'codigo_barra') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.medicamentos_patologia', 'principio_ativo') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.medicamentos_patologia sem colunas obrigatorias codigo_barra/principio_ativo.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('temp_CGUSC.fp.posologia_tempo_bloqueio', 'U') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.posologia_tempo_bloqueio nao encontrada.', 16, 1);
    RETURN;
END;

IF COL_LENGTH('temp_CGUSC.fp.posologia_tempo_bloqueio', 'PRINCIPIO_ATIVO') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.posologia_tempo_bloqueio', 'PROXIMA_COMPRA') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.posologia_tempo_bloqueio sem colunas obrigatorias PRINCIPIO_ATIVO/PROXIMA_COMPRA.', 16, 1);
    RETURN;
END;

IF EXISTS (
    SELECT 1
    FROM temp_CGUSC.fp.posologia_tempo_bloqueio
    WHERE NULLIF(LTRIM(RTRIM(CAST(PRINCIPIO_ATIVO AS VARCHAR(255)))), '') IS NULL
       OR PROXIMA_COMPRA IS NULL
       OR TRY_CAST(PROXIMA_COMPRA AS INT) IS NULL
)
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.posologia_tempo_bloqueio possui PRINCIPIO_ATIVO/PROXIMA_COMPRA invalidos.', 16, 1);
    RETURN;
END;

IF EXISTS (
    SELECT 1
    FROM temp_CGUSC.fp.posologia_tempo_bloqueio
    GROUP BY UPPER(LTRIM(RTRIM(CAST(PRINCIPIO_ATIVO AS VARCHAR(255)))))
    HAVING COUNT(DISTINCT TRY_CAST(PROXIMA_COMPRA AS INT)) > 1
)
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.posologia_tempo_bloqueio possui PROXIMA_COMPRA conflitante para o mesmo PRINCIPIO_ATIVO.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('temp_CGUSC.fp.dados_farmacia', 'U') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.dados_farmacia nao encontrada.', 16, 1);
    RETURN;
END;

IF COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'id') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'cnpj') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'municipio') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'uf') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'id_regiao_saude') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.dados_farmacia sem colunas obrigatorias id/cnpj/municipio/uf/id_regiao_saude.', 16, 1);
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

IF OBJECT_ID('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'U') IS NULL
BEGIN
    RAISERROR('Tabela db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 nao encontrada.', 16, 1);
    RETURN;
END;

IF COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'cnpj') IS NULL
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'cpf') IS NULL
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'data_hora') IS NULL
   OR COL_LENGTH('db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024', 'codigo_barra') IS NULL
BEGIN
    RAISERROR('Tabela db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 sem colunas obrigatorias para recorrencia sistemica.', 16, 1);
    RETURN;
END;

DROP TABLE IF EXISTS #farmacias_dim;

SELECT
    CAST(F.id AS INT) AS id_cnpj,
    CAST(F.cnpj AS VARCHAR(14)) AS cnpj,
    CAST(F.municipio AS VARCHAR(255)) AS municipio,
    CAST(UPPER(LTRIM(RTRIM(F.uf))) AS VARCHAR(2)) AS uf,
    CAST(F.id_regiao_saude AS INT) AS id_regiao_saude
INTO #farmacias_dim
FROM temp_CGUSC.fp.dados_farmacia AS F;

IF EXISTS (
    SELECT 1
    FROM #farmacias_dim
    WHERE id_cnpj IS NULL
       OR NULLIF(LTRIM(RTRIM(cnpj)), '') IS NULL
       OR NULLIF(LTRIM(RTRIM(municipio)), '') IS NULL
       OR NULLIF(LTRIM(RTRIM(uf)), '') IS NULL
       OR id_regiao_saude IS NULL
)
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.dados_farmacia possui valores obrigatorios nulos para contexto territorial.', 16, 1);
    RETURN;
END;

CREATE UNIQUE CLUSTERED INDEX IDX_farmacias_dim_cnpj
ON #farmacias_dim(cnpj);

CREATE UNIQUE NONCLUSTERED INDEX IDX_farmacias_dim_id
ON #farmacias_dim(id_cnpj);

DROP TABLE IF EXISTS #medicamentos_recorrencia;

SELECT DISTINCT
    MP.codigo_barra,
    CAST(UPPER(LTRIM(RTRIM(MP.principio_ativo))) AS VARCHAR(255)) AS principio_ativo,
    CAST(P.PROXIMA_COMPRA AS INT) AS dias_para_bloqueio
INTO #medicamentos_recorrencia
FROM temp_CGUSC.fp.medicamentos_patologia MP
INNER JOIN temp_CGUSC.fp.posologia_tempo_bloqueio P
    ON UPPER(LTRIM(RTRIM(P.PRINCIPIO_ATIVO))) = UPPER(LTRIM(RTRIM(MP.principio_ativo)))
WHERE MP.codigo_barra IS NOT NULL
  AND NULLIF(LTRIM(RTRIM(MP.principio_ativo)), '') IS NOT NULL;

IF NOT EXISTS (SELECT 1 FROM #medicamentos_recorrencia)
BEGIN
    RAISERROR('Nao ha medicamentos auditados com posologia de bloqueio valida para recorrencia sistemica.', 16, 1);
    RETURN;
END;

CREATE CLUSTERED INDEX IDX_medicamentos_recorrencia_gtin
ON #medicamentos_recorrencia(codigo_barra);


-- ============================================================================
-- PASSO 1: HISTORICO DE COMPRAS POR FARMACIA/CPF/PRINCIPIO ATIVO
-- ============================================================================
DROP TABLE IF EXISTS #ComprasBase;

SELECT DISTINCT
    F.id_cnpj,
    CAST(A.cpf AS VARCHAR(20)) AS cpf,
    M.principio_ativo,
    M.dias_para_bloqueio,
    CAST(A.data_hora AS DATETIME) AS data_compra
INTO #ComprasBase
FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
INNER JOIN #farmacias_dim F
    ON F.cnpj = A.cnpj
INNER JOIN #medicamentos_recorrencia M
    ON M.codigo_barra = A.codigo_barra
WHERE A.data_hora >= @DataInicio
  AND A.data_hora < DATEADD(DAY, 1, @DataFim)
  AND NULLIF(LTRIM(RTRIM(CAST(A.cpf AS VARCHAR(20)))), '') IS NOT NULL
  AND A.codigo_barra IS NOT NULL;

CREATE CLUSTERED INDEX IDX_ComprasBase_CNPJ_CPF
ON #ComprasBase(id_cnpj, cpf, principio_ativo, data_compra);

DROP TABLE IF EXISTS #HistoricoCompras;

SELECT
    id_cnpj,
    CAST(YEAR(data_compra) AS SMALLINT) AS ano_base,
    cpf,
    principio_ativo,
    dias_para_bloqueio,
    data_compra AS data_compra_atual,
    LAG(data_compra) OVER (
        PARTITION BY id_cnpj, cpf, principio_ativo
        ORDER BY data_compra ASC
    ) AS data_compra_anterior
INTO #HistoricoCompras
FROM #ComprasBase;

CREATE CLUSTERED INDEX IDX_HistoricoCompras_CNPJ_Ano
ON #HistoricoCompras(id_cnpj, ano_base);

DROP TABLE IF EXISTS #ComprasBase;
DROP TABLE IF EXISTS #medicamentos_recorrencia;


-- ============================================================================
-- PASSO 2: CALCULO BASE POR FARMACIA/ANO
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_recorrencia_sistemica;

SELECT
    id_cnpj,
    ano_base,
    CAST(COUNT(*) AS INT) AS qtd_renovacoes_totais,
    CAST(
        SUM(
            CASE
                WHEN DATEDIFF(DAY, data_compra_anterior, data_compra_atual)
                     BETWEEN dias_para_bloqueio AND (dias_para_bloqueio + 1)
                    THEN 1
                ELSE 0
            END
        ) AS INT
    ) AS qtd_renovacoes_sistemicas,
    CAST(
        CASE
            WHEN COUNT(*) >= 10 THEN
                (
                    CAST(
                        SUM(
                            CASE
                                WHEN DATEDIFF(DAY, data_compra_anterior, data_compra_atual)
                                     BETWEEN dias_para_bloqueio AND (dias_para_bloqueio + 1)
                                    THEN 1
                                ELSE 0
                            END
                        ) AS DECIMAL(18,4)
                    ) /
                    CAST(COUNT(*) AS DECIMAL(18,4))
                ) * 100.0
            ELSE 0
        END AS DECIMAL(7,4)
    ) AS percentual_recorrencia_sistemica
INTO temp_CGUSC.fp.indicador_recorrencia_sistemica
FROM #HistoricoCompras
WHERE data_compra_anterior IS NOT NULL
GROUP BY
    id_cnpj,
    ano_base
HAVING COUNT(*) > 0;

CREATE UNIQUE CLUSTERED INDEX IDX_IndRecorrencia_CNPJ_Ano
ON temp_CGUSC.fp.indicador_recorrencia_sistemica(id_cnpj, ano_base);

DROP TABLE IF EXISTS #HistoricoCompras;


-- ============================================================================
-- PASSO 3: METRICAS POR MUNICIPIO (MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_recorrencia_sistemica_mun;

SELECT DISTINCT
    I.ano_base,
    F.uf,
    F.municipio,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.percentual_recorrencia_sistemica)
        OVER (PARTITION BY I.ano_base, F.uf, F.municipio)
    AS DECIMAL(7,4)) AS mediana_municipio
INTO temp_CGUSC.fp.indicador_recorrencia_sistemica_mun
FROM temp_CGUSC.fp.indicador_recorrencia_sistemica I
INNER JOIN #farmacias_dim F
    ON F.id_cnpj = I.id_cnpj;

CREATE CLUSTERED INDEX IDX_IndRecorrMun
ON temp_CGUSC.fp.indicador_recorrencia_sistemica_mun(ano_base, uf, municipio);


-- ============================================================================
-- PASSO 4: METRICAS POR ESTADO (MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_recorrencia_sistemica_uf;

SELECT DISTINCT
    I.ano_base,
    F.uf,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.percentual_recorrencia_sistemica)
        OVER (PARTITION BY I.ano_base, F.uf)
    AS DECIMAL(7,4)) AS mediana_estado
INTO temp_CGUSC.fp.indicador_recorrencia_sistemica_uf
FROM temp_CGUSC.fp.indicador_recorrencia_sistemica I
INNER JOIN #farmacias_dim F
    ON F.id_cnpj = I.id_cnpj;

CREATE CLUSTERED INDEX IDX_IndRecorrUF
ON temp_CGUSC.fp.indicador_recorrencia_sistemica_uf(ano_base, uf);


-- ============================================================================
-- PASSO 4B: METRICAS POR REGIAO DE SAUDE (MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_recorrencia_sistemica_regiao;

SELECT DISTINCT
    I.ano_base,
    F.id_regiao_saude,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.percentual_recorrencia_sistemica)
        OVER (PARTITION BY I.ano_base, F.id_regiao_saude)
    AS DECIMAL(7,4)) AS mediana_regiao
INTO temp_CGUSC.fp.indicador_recorrencia_sistemica_regiao
FROM temp_CGUSC.fp.indicador_recorrencia_sistemica I
INNER JOIN #farmacias_dim F
    ON F.id_cnpj = I.id_cnpj;

CREATE CLUSTERED INDEX IDX_IndRecorrReg
ON temp_CGUSC.fp.indicador_recorrencia_sistemica_regiao(ano_base, id_regiao_saude);


-- ============================================================================
-- PASSO 5: METRICAS NACIONAIS (MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_recorrencia_sistemica_br;

SELECT DISTINCT
    ano_base,
    CAST(
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY percentual_recorrencia_sistemica)
        OVER (PARTITION BY ano_base)
    AS DECIMAL(7,4)) AS mediana_pais
INTO temp_CGUSC.fp.indicador_recorrencia_sistemica_br
FROM temp_CGUSC.fp.indicador_recorrencia_sistemica;

CREATE CLUSTERED INDEX IDX_IndRecorrBR
ON temp_CGUSC.fp.indicador_recorrencia_sistemica_br(ano_base);


-- ============================================================================
-- PASSO 6: TABELA CONSOLIDADA FINAL
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_recorrencia_sistemica_detalhado;

SELECT
    I.id_cnpj,
    I.ano_base,
    I.qtd_renovacoes_totais,
    I.qtd_renovacoes_sistemicas,
    I.percentual_recorrencia_sistemica,

    MUN.mediana_municipio AS municipio_mediana,
    CAST((I.percentual_recorrencia_sistemica + 0.01) / (MUN.mediana_municipio + 0.01) AS DECIMAL(9,4)) AS risco_relativo_mun_mediana,

    UF.mediana_estado AS estado_mediana,
    CAST((I.percentual_recorrencia_sistemica + 0.01) / (UF.mediana_estado + 0.01) AS DECIMAL(9,4)) AS risco_relativo_uf_mediana,

    REG.mediana_regiao AS regiao_saude_mediana,
    CAST((I.percentual_recorrencia_sistemica + 0.01) / (REG.mediana_regiao + 0.01) AS DECIMAL(9,4)) AS risco_relativo_reg_mediana,

    BR.mediana_pais AS pais_mediana,
    CAST((I.percentual_recorrencia_sistemica + 0.01) / (BR.mediana_pais + 0.01) AS DECIMAL(9,4)) AS risco_relativo_br_mediana
INTO temp_CGUSC.fp.indicador_recorrencia_sistemica_detalhado
FROM temp_CGUSC.fp.indicador_recorrencia_sistemica I
INNER JOIN #farmacias_dim F
    ON F.id_cnpj = I.id_cnpj
INNER JOIN temp_CGUSC.fp.indicador_recorrencia_sistemica_mun MUN
    ON I.ano_base = MUN.ano_base
   AND F.uf = MUN.uf
   AND F.municipio = MUN.municipio
INNER JOIN temp_CGUSC.fp.indicador_recorrencia_sistemica_uf UF
    ON I.ano_base = UF.ano_base
   AND F.uf = UF.uf
INNER JOIN temp_CGUSC.fp.indicador_recorrencia_sistemica_regiao REG
    ON I.ano_base = REG.ano_base
   AND F.id_regiao_saude = REG.id_regiao_saude
INNER JOIN temp_CGUSC.fp.indicador_recorrencia_sistemica_br BR
    ON I.ano_base = BR.ano_base;

CREATE UNIQUE CLUSTERED INDEX IDX_FinalRecorrencia_CNPJ
ON temp_CGUSC.fp.indicador_recorrencia_sistemica_detalhado(id_cnpj, ano_base);
GO


-- ============================================================================
-- LIMPEZA DAS TABELAS INTERMEDIARIAS
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_recorrencia_sistemica;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_recorrencia_sistemica_mun;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_recorrencia_sistemica_uf;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_recorrencia_sistemica_regiao;
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_recorrencia_sistemica_br;
DROP TABLE IF EXISTS #farmacias_dim;
GO
