DROP TABLE IF EXISTS #cnpjs;

IF OBJECT_ID('temp_CGUSC.fp.dados_farmacia', 'U') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.dados_farmacia nao encontrada para mapear id_cnpj.', 16, 1);
    RETURN;
END;

IF COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'id') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'cnpj') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.dados_farmacia sem colunas obrigatorias id/cnpj para contexto eSocial.', 16, 1);
    RETURN;
END;

SELECT
    CAST(F.id AS INT) AS id_cnpj,
    CAST(F.cnpj AS VARCHAR(14)) AS cnpj
INTO #cnpjs
FROM temp_CGUSC.fp.dados_farmacia AS F;

DECLARE @tempo_total_esocial DATETIME2(7) = SYSDATETIME();
DECLARE @tempo_etapa_esocial DATETIME2(7) = @tempo_total_esocial;
DECLARE @linhas_esocial BIGINT;
DECLARE @msg_esocial NVARCHAR(4000);

SET @linhas_esocial = (SELECT COUNT_BIG(*) FROM #cnpjs);
SET @msg_esocial = CONCAT(
    '[eSocial] 00 - lista de CNPJs preparada | linhas=',
    @linhas_esocial,
    ' | total_ms=',
    DATEDIFF(MILLISECOND, @tempo_total_esocial, SYSDATETIME())
);
RAISERROR(@msg_esocial, 0, 1) WITH NOWAIT;
SET @tempo_etapa_esocial = SYSDATETIME();


--**************************************************************************************************************************************
-- Contexto trabalhista eSocial por CNPJ
--**************************************************************************************************************************************

IF OBJECT_ID('db_eSocial.dbo.trabalhadores', 'U') IS NULL
BEGIN
    RAISERROR('Tabela fonte db_eSocial.dbo.trabalhadores nao encontrada.', 16, 1);
    RETURN;
END;

IF OBJECT_ID('db_eSocial.auxiliares.cbo_ocupacao', 'U') IS NULL
BEGIN
    RAISERROR('Tabela auxiliar db_eSocial.auxiliares.cbo_ocupacao nao encontrada.', 16, 1);
    RETURN;
END;

IF COL_LENGTH('db_eSocial.auxiliares.cbo_ocupacao', 'codigo') IS NULL
   OR COL_LENGTH('db_eSocial.auxiliares.cbo_ocupacao', 'titulo') IS NULL
BEGIN
    RAISERROR('Tabela db_eSocial.auxiliares.cbo_ocupacao sem colunas obrigatorias codigo/titulo.', 16, 1);
    RETURN;
END;

IF EXISTS (
    SELECT 1
    FROM db_eSocial.auxiliares.cbo_ocupacao
    GROUP BY codigo
    HAVING COUNT_BIG(*) > 1
)
BEGIN
    RAISERROR('Tabela db_eSocial.auxiliares.cbo_ocupacao possui codigos duplicados.', 16, 1);
    RETURN;
END;

DROP TABLE IF EXISTS #trabalhadores_esocial_base;

CREATE TABLE #trabalhadores_esocial_base (
    id_cnpj INT NOT NULL,
    ANO_BASE SMALLINT NULL,
    MES_BASE TINYINT NULL,
    cpf_trabalhador VARCHAR(11) NULL,
    matricula VARCHAR(30) NULL,
    cbo INT NULL,
    dt_admissao DATE NULL,
    dt_rescisao DATE NULL,
    dt_carga_fonte DATE NULL
);

SET @msg_esocial = CONCAT(
    '[eSocial] 01 - tabela temporaria base criada | etapa_ms=',
    DATEDIFF(MILLISECOND, @tempo_etapa_esocial, SYSDATETIME()),
    ' | total_ms=',
    DATEDIFF(MILLISECOND, @tempo_total_esocial, SYSDATETIME())
);
RAISERROR(@msg_esocial, 0, 1) WITH NOWAIT;
SET @tempo_etapa_esocial = SYSDATETIME();

DECLARE @id_cnpj_esocial INT;
DECLARE @cnpj_esocial VARCHAR(14);

DECLARE cnpjs_esocial CURSOR LOCAL FAST_FORWARD FOR
SELECT id_cnpj, cnpj
FROM #cnpjs
ORDER BY id_cnpj;

OPEN cnpjs_esocial;

FETCH NEXT FROM cnpjs_esocial INTO @id_cnpj_esocial, @cnpj_esocial;

WHILE @@FETCH_STATUS = 0
BEGIN
    INSERT INTO #trabalhadores_esocial_base (
        id_cnpj,
        ANO_BASE,
        MES_BASE,
        cpf_trabalhador,
        matricula,
        cbo,
        dt_admissao,
        dt_rescisao,
        dt_carga_fonte
    )
    SELECT
        @id_cnpj_esocial,
        T.ANO_BASE,
        T.MES_BASE,
        CAST(T.NU_CPF_TRABALHADOR AS VARCHAR(11)),
        CAST(NULLIF(LTRIM(RTRIM(T.NU_MATRICULA)), '') AS VARCHAR(30)),
        TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(CAST(T.NU_CBO AS VARCHAR(20)))), '')),
        T.DT_ADMISSAO,
        T.DT_RESCISAO,
        T.DT_CARGA
    FROM db_eSocial.dbo.trabalhadores AS T
    WHERE T.NU_CNPJ_CPF_TOMADOR_COMPLETO = @cnpj_esocial
    OPTION (RECOMPILE);

    FETCH NEXT FROM cnpjs_esocial INTO @id_cnpj_esocial, @cnpj_esocial;
END;

CLOSE cnpjs_esocial;
DEALLOCATE cnpjs_esocial;

SET @linhas_esocial = (SELECT COUNT_BIG(*) FROM #trabalhadores_esocial_base);
SET @msg_esocial = CONCAT(
    '[eSocial] 02 - carga base concluida | linhas=',
    @linhas_esocial,
    ' | etapa_ms=',
    DATEDIFF(MILLISECOND, @tempo_etapa_esocial, SYSDATETIME()),
    ' | total_ms=',
    DATEDIFF(MILLISECOND, @tempo_total_esocial, SYSDATETIME())
);
RAISERROR(@msg_esocial, 0, 1) WITH NOWAIT;
SET @tempo_etapa_esocial = SYSDATETIME();

CREATE CLUSTERED INDEX IX_tmp_trab_esocial_base
ON #trabalhadores_esocial_base (id_cnpj, ANO_BASE, MES_BASE, cpf_trabalhador, matricula);

SET @msg_esocial = CONCAT(
    '[eSocial] 03 - indice da base temporaria criado | etapa_ms=',
    DATEDIFF(MILLISECOND, @tempo_etapa_esocial, SYSDATETIME()),
    ' | total_ms=',
    DATEDIFF(MILLISECOND, @tempo_total_esocial, SYSDATETIME())
);
RAISERROR(@msg_esocial, 0, 1) WITH NOWAIT;
SET @tempo_etapa_esocial = SYSDATETIME();

IF EXISTS (
    SELECT 1
    FROM #trabalhadores_esocial_base
    WHERE ANO_BASE IS NULL
       OR MES_BASE IS NULL
       OR MES_BASE NOT BETWEEN 1 AND 12
       OR NULLIF(LTRIM(RTRIM(cpf_trabalhador)), '') IS NULL
       OR cbo IS NULL
)
BEGIN
    RAISERROR('Dados obrigatorios ausentes ou invalidos em db_eSocial.dbo.trabalhadores para CNPJs analisados.', 16, 1);
    RETURN;
END;

SET @msg_esocial = CONCAT(
    '[eSocial] 04 - validacao de dados obrigatorios concluida | etapa_ms=',
    DATEDIFF(MILLISECOND, @tempo_etapa_esocial, SYSDATETIME()),
    ' | total_ms=',
    DATEDIFF(MILLISECOND, @tempo_total_esocial, SYSDATETIME())
);
RAISERROR(@msg_esocial, 0, 1) WITH NOWAIT;
SET @tempo_etapa_esocial = SYSDATETIME();

DROP TABLE IF EXISTS #trabalhadores_esocial_ano;

SELECT
    id_cnpj,
    CAST(ANO_BASE AS SMALLINT) AS ano_base,
    CAST(MES_BASE AS TINYINT) AS mes_base,
    CAST((ANO_BASE * 100) + MES_BASE AS INT) AS competencia_base,
    cpf_trabalhador,
    matricula,
    B.cbo,
    C.titulo AS titulo_cbo,
    dt_admissao,
    dt_rescisao,
    CAST(CASE WHEN B.cbo = 223405 THEN 1 ELSE 0 END AS BIT) AS is_farmaceutico,
    CAST(CASE WHEN B.cbo = 0 OR NULLIF(LTRIM(RTRIM(C.titulo)), '') IS NULL THEN 1 ELSE 0 END AS BIT) AS is_cbo_sem_titulo,
    dt_carga_fonte
INTO #trabalhadores_esocial_ano
FROM #trabalhadores_esocial_base AS B
LEFT JOIN db_eSocial.auxiliares.cbo_ocupacao AS C
    ON C.codigo = B.cbo;

SET @linhas_esocial = (
    SELECT COUNT_BIG(*)
    FROM #trabalhadores_esocial_ano
    WHERE is_cbo_sem_titulo = 1
);

IF @linhas_esocial > 0
BEGIN
    SET @msg_esocial = CONCAT(
        '[eSocial] aviso - CBO de trabalhador sem titulo valido | registros=',
        @linhas_esocial
    );
    RAISERROR(@msg_esocial, 0, 1) WITH NOWAIT;
END;

SET @linhas_esocial = (SELECT COUNT_BIG(*) FROM #trabalhadores_esocial_ano);
SET @msg_esocial = CONCAT(
    '[eSocial] 05 - base anual de trabalhadores gerada | linhas=',
    @linhas_esocial,
    ' | etapa_ms=',
    DATEDIFF(MILLISECOND, @tempo_etapa_esocial, SYSDATETIME()),
    ' | total_ms=',
    DATEDIFF(MILLISECOND, @tempo_total_esocial, SYSDATETIME())
);
RAISERROR(@msg_esocial, 0, 1) WITH NOWAIT;
SET @tempo_etapa_esocial = SYSDATETIME();

CREATE CLUSTERED INDEX IX_tmp_trab_esocial_ano
ON #trabalhadores_esocial_ano (id_cnpj, ano_base, cpf_trabalhador, matricula);

CREATE NONCLUSTERED INDEX IX_tmp_trab_esocial_ano_cbo
ON #trabalhadores_esocial_ano (cbo, id_cnpj, ano_base)
INCLUDE (titulo_cbo, is_farmaceutico, is_cbo_sem_titulo, dt_admissao, dt_rescisao);

SET @msg_esocial = CONCAT(
    '[eSocial] 06 - indices da base anual criados | etapa_ms=',
    DATEDIFF(MILLISECOND, @tempo_etapa_esocial, SYSDATETIME()),
    ' | total_ms=',
    DATEDIFF(MILLISECOND, @tempo_total_esocial, SYSDATETIME())
);
RAISERROR(@msg_esocial, 0, 1) WITH NOWAIT;
SET @tempo_etapa_esocial = SYSDATETIME();

IF EXISTS (
    SELECT 1
    FROM #trabalhadores_esocial_ano
    WHERE dt_admissao IS NULL
)
BEGIN
    SET @linhas_esocial = (
        SELECT COUNT_BIG(*)
        FROM #trabalhadores_esocial_ano
        WHERE dt_admissao IS NULL
    );
    SET @msg_esocial = CONCAT(
        '[eSocial] aviso - vinculos sem data de admissao considerados na apuracao de ativos quando compativeis com a competencia-base | registros=',
        @linhas_esocial
    );
    RAISERROR(@msg_esocial, 0, 1) WITH NOWAIT;
END;

DROP TABLE IF EXISTS #competencias_esocial_ano;

SELECT
    id_cnpj,
    ano_base,
    MAX(mes_base) AS mes_base,
    MAX(competencia_base) AS competencia_base,
    MAX(dt_carga_fonte) AS dt_carga_fonte,
    EOMONTH(DATEFROMPARTS(ano_base, MAX(mes_base), 1)) AS dt_referencia_competencia
INTO #competencias_esocial_ano
FROM #trabalhadores_esocial_ano
GROUP BY id_cnpj, ano_base;

CREATE UNIQUE CLUSTERED INDEX IX_tmp_competencias_esocial_ano
ON #competencias_esocial_ano (id_cnpj, ano_base);

DROP TABLE IF EXISTS #trabalhadores_esocial_ativos_competencia;

SELECT
    T.id_cnpj,
    T.ano_base,
    C.mes_base,
    C.competencia_base,
    C.dt_referencia_competencia,
    T.cpf_trabalhador,
    T.matricula,
    T.cbo,
    T.titulo_cbo,
    T.dt_admissao,
    T.dt_rescisao,
    T.is_farmaceutico,
    T.is_cbo_sem_titulo,
    T.dt_carga_fonte
INTO #trabalhadores_esocial_ativos_competencia
FROM #trabalhadores_esocial_ano AS T
INNER JOIN #competencias_esocial_ano AS C
    ON C.id_cnpj = T.id_cnpj
   AND C.ano_base = T.ano_base
WHERE (
      T.dt_admissao IS NULL
      OR T.dt_admissao <= C.dt_referencia_competencia
  )
  AND (
      T.dt_rescisao IS NULL
      OR T.dt_rescisao >= C.dt_referencia_competencia
  );

CREATE CLUSTERED INDEX IX_tmp_trab_esocial_ativos_comp
ON #trabalhadores_esocial_ativos_competencia (id_cnpj, ano_base, cpf_trabalhador, matricula);

DROP TABLE IF EXISTS #trabalhadores_esocial_ativos_unicos;

WITH ativos_ordenados AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY id_cnpj, ano_base, cpf_trabalhador
            ORDER BY
                is_farmaceutico DESC,
                is_cbo_sem_titulo ASC,
                CASE WHEN dt_rescisao IS NULL THEN 1 ELSE 0 END DESC,
                dt_rescisao DESC,
                dt_admissao DESC,
                matricula DESC
        ) AS rn
    FROM #trabalhadores_esocial_ativos_competencia
)
SELECT
    id_cnpj,
    ano_base,
    mes_base,
    competencia_base,
    dt_referencia_competencia,
    cpf_trabalhador,
    matricula,
    cbo,
    titulo_cbo,
    dt_admissao,
    dt_rescisao,
    is_farmaceutico,
    is_cbo_sem_titulo,
    dt_carga_fonte
INTO #trabalhadores_esocial_ativos_unicos
FROM ativos_ordenados
WHERE rn = 1;

CREATE UNIQUE CLUSTERED INDEX IX_tmp_trab_esocial_ativos_unicos
ON #trabalhadores_esocial_ativos_unicos (id_cnpj, ano_base, cpf_trabalhador);

SET @linhas_esocial = (SELECT COUNT_BIG(*) FROM #trabalhadores_esocial_ativos_competencia);
SET @msg_esocial = CONCAT(
    '[eSocial] 06b - vinculos ativos na competencia-base apurados | linhas=',
    @linhas_esocial,
    ' | etapa_ms=',
    DATEDIFF(MILLISECOND, @tempo_etapa_esocial, SYSDATETIME()),
    ' | total_ms=',
    DATEDIFF(MILLISECOND, @tempo_total_esocial, SYSDATETIME())
);
RAISERROR(@msg_esocial, 0, 1) WITH NOWAIT;
SET @tempo_etapa_esocial = SYSDATETIME();

DROP TABLE IF EXISTS temp_CGUSC.fp.esocial_cnpj_mes;
DROP TABLE IF EXISTS temp_CGUSC.fp.esocial_cnpj_mes_unico_trabalhador;
DROP TABLE IF EXISTS temp_CGUSC.fp.esocial_cnpj_ano_unico_trabalhador;
DROP TABLE IF EXISTS temp_CGUSC.fp.esocial_cnpj_resumo;
DROP TABLE IF EXISTS temp_CGUSC.fp.esocial_cnpj_trabalhador_ano;
DROP TABLE IF EXISTS temp_CGUSC.fp.esocial_cnpj_movimentacao_ano;
DROP TABLE IF EXISTS temp_CGUSC.fp.esocial_cnpj_ultima_movimentacao;

SET @msg_esocial = CONCAT(
    '[eSocial] 07 - drop tabelas antigas e trabalhador_ano concluido | etapa_ms=',
    DATEDIFF(MILLISECOND, @tempo_etapa_esocial, SYSDATETIME()),
    ' | total_ms=',
    DATEDIFF(MILLISECOND, @tempo_total_esocial, SYSDATETIME())
);
RAISERROR(@msg_esocial, 0, 1) WITH NOWAIT;
SET @tempo_etapa_esocial = SYSDATETIME();

SELECT
    id_cnpj,
    ano_base,
    mes_base,
    competencia_base,
    cpf_trabalhador,
    matricula,
    cbo,
    titulo_cbo,
    dt_admissao,
    dt_rescisao,
    is_farmaceutico,
    is_cbo_sem_titulo,
    dt_carga_fonte,
    GETDATE() AS dt_processamento
INTO temp_CGUSC.fp.esocial_cnpj_trabalhador_ano
FROM #trabalhadores_esocial_ano;

SET @linhas_esocial = (SELECT COUNT_BIG(*) FROM temp_CGUSC.fp.esocial_cnpj_trabalhador_ano);
SET @msg_esocial = CONCAT(
    '[eSocial] 08 - tabela esocial_cnpj_trabalhador_ano persistida | linhas=',
    @linhas_esocial,
    ' | etapa_ms=',
    DATEDIFF(MILLISECOND, @tempo_etapa_esocial, SYSDATETIME()),
    ' | total_ms=',
    DATEDIFF(MILLISECOND, @tempo_total_esocial, SYSDATETIME())
);
RAISERROR(@msg_esocial, 0, 1) WITH NOWAIT;
SET @tempo_etapa_esocial = SYSDATETIME();

CREATE CLUSTERED INDEX IX_esocial_cnpj_trabalhador_ano
ON temp_CGUSC.fp.esocial_cnpj_trabalhador_ano (id_cnpj, ano_base, cpf_trabalhador, matricula);

CREATE NONCLUSTERED INDEX IX_esocial_cnpj_trabalhador_ano_cbo
ON temp_CGUSC.fp.esocial_cnpj_trabalhador_ano (cbo, id_cnpj, ano_base)
INCLUDE (titulo_cbo, is_farmaceutico, is_cbo_sem_titulo, dt_admissao, dt_rescisao);

SET @msg_esocial = CONCAT(
    '[eSocial] 09 - indices esocial_cnpj_trabalhador_ano criados | etapa_ms=',
    DATEDIFF(MILLISECOND, @tempo_etapa_esocial, SYSDATETIME()),
    ' | total_ms=',
    DATEDIFF(MILLISECOND, @tempo_total_esocial, SYSDATETIME())
);
RAISERROR(@msg_esocial, 0, 1) WITH NOWAIT;
SET @tempo_etapa_esocial = SYSDATETIME();

DROP TABLE IF EXISTS temp_CGUSC.fp.esocial_cnpj_ano;

SET @msg_esocial = CONCAT(
    '[eSocial] 10 - drop esocial_cnpj_ano concluido | etapa_ms=',
    DATEDIFF(MILLISECOND, @tempo_etapa_esocial, SYSDATETIME()),
    ' | total_ms=',
    DATEDIFF(MILLISECOND, @tempo_total_esocial, SYSDATETIME())
);
RAISERROR(@msg_esocial, 0, 1) WITH NOWAIT;
SET @tempo_etapa_esocial = SYSDATETIME();

DROP TABLE IF EXISTS #ativos_esocial_agg;

SELECT
    id_cnpj,
    ano_base,
    COUNT_BIG(cpf_trabalhador) AS qtd_registros,
    COUNT(DISTINCT cpf_trabalhador) AS qtd_trabalhadores,
    COUNT(DISTINCT CASE WHEN is_farmaceutico = 1 THEN cpf_trabalhador END) AS qtd_farmaceuticos,
    COUNT(DISTINCT CASE WHEN is_cbo_sem_titulo = 1 THEN cpf_trabalhador END) AS qtd_trabalhadores_cbo_sem_titulo,
    SUM(CASE WHEN is_farmaceutico = 1 THEN 1 ELSE 0 END) AS qtd_registros_farmaceuticos,
    SUM(CASE WHEN is_cbo_sem_titulo = 1 THEN 1 ELSE 0 END) AS qtd_registros_cbo_sem_titulo,
    CAST(MAX(CASE WHEN is_farmaceutico = 1 THEN 1 ELSE 0 END) AS BIT) AS has_farmaceutico,
    CAST(MAX(CASE WHEN is_cbo_sem_titulo = 1 THEN 1 ELSE 0 END) AS BIT) AS has_cbo_sem_titulo,
    CAST(CASE WHEN COUNT(DISTINCT cpf_trabalhador) = 1 THEN 1 ELSE 0 END AS BIT) AS is_um_trabalhador,
    CAST(CASE WHEN COUNT(DISTINCT cpf_trabalhador) = 1 AND COUNT(DISTINCT CASE WHEN is_farmaceutico = 1 THEN cpf_trabalhador END) = 0 THEN 1 ELSE 0 END AS BIT) AS is_um_trabalhador_sem_farmaceutico,
    CAST(CASE WHEN COUNT(DISTINCT cpf_trabalhador) = 1 AND COUNT(DISTINCT CASE WHEN is_cbo_sem_titulo = 1 THEN cpf_trabalhador END) > 0 THEN 1 ELSE 0 END AS BIT) AS is_um_trabalhador_cbo_sem_titulo,
    CASE WHEN COUNT(DISTINCT cpf_trabalhador) = 1 THEN MAX(cbo) END AS cbo_unico_trabalhador,
    CASE WHEN COUNT(DISTINCT cpf_trabalhador) = 1 THEN MAX(titulo_cbo) END AS titulo_cbo_unico_trabalhador
INTO #ativos_esocial_agg
FROM #trabalhadores_esocial_ativos_unicos
GROUP BY id_cnpj, ano_base;

CREATE UNIQUE CLUSTERED INDEX IX_tmp_ativos_esocial_agg
ON #ativos_esocial_agg (id_cnpj, ano_base);

SET @linhas_esocial = (SELECT COUNT_BIG(*) FROM #ativos_esocial_agg);
SET @msg_esocial = CONCAT(
    '[eSocial] 10a - agregacao de ativos por ano criada | linhas=',
    @linhas_esocial,
    ' | etapa_ms=',
    DATEDIFF(MILLISECOND, @tempo_etapa_esocial, SYSDATETIME()),
    ' | total_ms=',
    DATEDIFF(MILLISECOND, @tempo_total_esocial, SYSDATETIME())
);
RAISERROR(@msg_esocial, 0, 1) WITH NOWAIT;
SET @tempo_etapa_esocial = SYSDATETIME();

DROP TABLE IF EXISTS #vinculos_esocial_agg;

SELECT
    id_cnpj,
    ano_base,
    COUNT_BIG(*) AS qtd_registros_vinculo_ano,
    COUNT(DISTINCT cpf_trabalhador) AS qtd_trabalhadores_vinculo_ano,
    COUNT(DISTINCT CASE WHEN is_farmaceutico = 1 THEN cpf_trabalhador END) AS qtd_farmaceuticos_vinculo_ano,
    COUNT(DISTINCT CASE WHEN is_cbo_sem_titulo = 1 THEN cpf_trabalhador END) AS qtd_trabalhadores_cbo_sem_titulo_vinculo_ano
INTO #vinculos_esocial_agg
FROM #trabalhadores_esocial_ano
GROUP BY id_cnpj, ano_base;

CREATE UNIQUE CLUSTERED INDEX IX_tmp_vinculos_esocial_agg
ON #vinculos_esocial_agg (id_cnpj, ano_base);

SET @linhas_esocial = (SELECT COUNT_BIG(*) FROM #vinculos_esocial_agg);
SET @msg_esocial = CONCAT(
    '[eSocial] 10b - agregacao de vinculos por ano criada | linhas=',
    @linhas_esocial,
    ' | etapa_ms=',
    DATEDIFF(MILLISECOND, @tempo_etapa_esocial, SYSDATETIME()),
    ' | total_ms=',
    DATEDIFF(MILLISECOND, @tempo_total_esocial, SYSDATETIME())
);
RAISERROR(@msg_esocial, 0, 1) WITH NOWAIT;
SET @tempo_etapa_esocial = SYSDATETIME();

SELECT
    C.id_cnpj,
    C.ano_base,
    C.mes_base,
    C.competencia_base,
    COALESCE(A.qtd_registros, 0) AS qtd_registros,
    COALESCE(A.qtd_trabalhadores, 0) AS qtd_trabalhadores,
    COALESCE(A.qtd_farmaceuticos, 0) AS qtd_farmaceuticos,
    COALESCE(A.qtd_trabalhadores_cbo_sem_titulo, 0) AS qtd_trabalhadores_cbo_sem_titulo,
    COALESCE(A.qtd_registros_farmaceuticos, 0) AS qtd_registros_farmaceuticos,
    COALESCE(A.qtd_registros_cbo_sem_titulo, 0) AS qtd_registros_cbo_sem_titulo,
    CAST(COALESCE(A.has_farmaceutico, 0) AS BIT) AS has_farmaceutico,
    CAST(COALESCE(A.has_cbo_sem_titulo, 0) AS BIT) AS has_cbo_sem_titulo,
    CAST(COALESCE(A.is_um_trabalhador, 0) AS BIT) AS is_um_trabalhador,
    CAST(COALESCE(A.is_um_trabalhador_sem_farmaceutico, 0) AS BIT) AS is_um_trabalhador_sem_farmaceutico,
    CAST(COALESCE(A.is_um_trabalhador_cbo_sem_titulo, 0) AS BIT) AS is_um_trabalhador_cbo_sem_titulo,
    A.cbo_unico_trabalhador,
    A.titulo_cbo_unico_trabalhador,
    COALESCE(V.qtd_registros_vinculo_ano, 0) AS qtd_registros_vinculo_ano,
    COALESCE(V.qtd_trabalhadores_vinculo_ano, 0) AS qtd_trabalhadores_vinculo_ano,
    COALESCE(V.qtd_farmaceuticos_vinculo_ano, 0) AS qtd_farmaceuticos_vinculo_ano,
    COALESCE(V.qtd_trabalhadores_cbo_sem_titulo_vinculo_ano, 0) AS qtd_trabalhadores_cbo_sem_titulo_vinculo_ano,
    C.dt_carga_fonte,
    GETDATE() AS dt_processamento
INTO temp_CGUSC.fp.esocial_cnpj_ano
FROM #competencias_esocial_ano AS C
LEFT JOIN #ativos_esocial_agg AS A
    ON A.id_cnpj = C.id_cnpj
   AND A.ano_base = C.ano_base
LEFT JOIN #vinculos_esocial_agg AS V
    ON V.id_cnpj = C.id_cnpj
   AND V.ano_base = C.ano_base;

SET @linhas_esocial = (SELECT COUNT_BIG(*) FROM temp_CGUSC.fp.esocial_cnpj_ano);
SET @msg_esocial = CONCAT(
    '[eSocial] 11 - tabela esocial_cnpj_ano persistida | linhas=',
    @linhas_esocial,
    ' | etapa_ms=',
    DATEDIFF(MILLISECOND, @tempo_etapa_esocial, SYSDATETIME()),
    ' | total_ms=',
    DATEDIFF(MILLISECOND, @tempo_total_esocial, SYSDATETIME())
);
RAISERROR(@msg_esocial, 0, 1) WITH NOWAIT;
SET @tempo_etapa_esocial = SYSDATETIME();

CREATE UNIQUE CLUSTERED INDEX IX_esocial_cnpj_ano
ON temp_CGUSC.fp.esocial_cnpj_ano (id_cnpj, ano_base);

SET @msg_esocial = CONCAT(
    '[eSocial] 12 - indice esocial_cnpj_ano criado | etapa_ms=',
    DATEDIFF(MILLISECOND, @tempo_etapa_esocial, SYSDATETIME()),
    ' | total_ms=',
    DATEDIFF(MILLISECOND, @tempo_total_esocial, SYSDATETIME())
);
RAISERROR(@msg_esocial, 0, 1) WITH NOWAIT;
SET @tempo_etapa_esocial = SYSDATETIME();

IF OBJECT_ID('temp_CGUSC.fp.movimentacao_mensal_cnpj', 'U') IS NULL
BEGIN
    RAISERROR('Tabela fonte temp_CGUSC.fp.movimentacao_mensal_cnpj nao encontrada.', 16, 1);
    RETURN;
END;

IF COL_LENGTH('temp_CGUSC.fp.movimentacao_mensal_cnpj', 'cnpj') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.movimentacao_mensal_cnpj', 'periodo') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.movimentacao_mensal_cnpj', 'total_vendas') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.movimentacao_mensal_cnpj', 'total_sem_comprovacao') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.movimentacao_mensal_cnpj', 'total_qnt_caixas_vendidas') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.movimentacao_mensal_cnpj', 'total_qnt_caixas_sem_comprovacao') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.movimentacao_mensal_cnpj', 'total_num_autorizacoes') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.movimentacao_mensal_cnpj sem colunas obrigatorias para contexto eSocial/movimentacao.', 16, 1);
    RETURN;
END;

IF COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'id_regiao_saude') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.dados_farmacia', 'uf') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.dados_farmacia sem colunas obrigatorias id_regiao_saude/uf para contexto eSocial/movimentacao.', 16, 1);
    RETURN;
END;

IF EXISTS (
    SELECT 1
    FROM temp_CGUSC.fp.esocial_cnpj_ano AS E
    INNER JOIN temp_CGUSC.fp.dados_farmacia AS F
        ON F.id = E.id_cnpj
    WHERE F.id_regiao_saude IS NULL
       OR NULLIF(LTRIM(RTRIM(F.uf)), '') IS NULL
)
BEGIN
    RAISERROR('CNPJ com contexto eSocial sem id_regiao_saude/uf em temp_CGUSC.fp.dados_farmacia.', 16, 1);
    RETURN;
END;

IF EXISTS (
    SELECT 1
    FROM temp_CGUSC.fp.movimentacao_mensal_cnpj AS M
    INNER JOIN temp_CGUSC.fp.dados_farmacia AS F
        ON F.cnpj = M.cnpj
    INNER JOIN temp_CGUSC.fp.esocial_cnpj_ano AS E
        ON E.id_cnpj = F.id
       AND E.ano_base = YEAR(M.periodo)
    WHERE M.total_vendas IS NULL
       OR M.total_sem_comprovacao IS NULL
       OR M.total_qnt_caixas_vendidas IS NULL
       OR M.total_qnt_caixas_sem_comprovacao IS NULL
       OR M.total_num_autorizacoes IS NULL
)
BEGIN
    RAISERROR('Movimentacao mensal com valores obrigatorios nulos para CNPJs/anos do contexto eSocial.', 16, 1);
    RETURN;
END;

IF EXISTS (
    SELECT 1
    FROM temp_CGUSC.fp.movimentacao_mensal_cnpj AS M
    INNER JOIN temp_CGUSC.fp.dados_farmacia AS F
        ON F.cnpj = M.cnpj
    INNER JOIN temp_CGUSC.fp.esocial_cnpj_ano AS E
        ON E.id_cnpj = F.id
    WHERE M.total_vendas > 0
      AND M.periodo = (
          SELECT MAX(M2.periodo)
          FROM temp_CGUSC.fp.movimentacao_mensal_cnpj AS M2
          INNER JOIN temp_CGUSC.fp.dados_farmacia AS F2
              ON F2.cnpj = M2.cnpj
          WHERE F2.id = F.id
            AND M2.total_vendas > 0
      )
      AND M.total_num_autorizacoes IS NULL
)
BEGIN
    RAISERROR('Ultima movimentacao mensal com valores obrigatorios nulos para CNPJs do contexto eSocial.', 16, 1);
    RETURN;
END;

DROP TABLE IF EXISTS #movimentacao_esocial_ano;

SELECT
    CAST(F.id AS INT) AS id_cnpj,
    CAST(YEAR(M.periodo) AS SMALLINT) AS ano_base,
    CAST(F.id_regiao_saude AS INT) AS id_regiao_saude,
    CAST(UPPER(LTRIM(RTRIM(F.uf))) AS CHAR(2)) AS uf,
    MIN(CAST(M.periodo AS DATE)) AS periodo_min,
    MAX(CAST(M.periodo AS DATE)) AS periodo_max,
    CAST(SUM(M.total_vendas) AS DECIMAL(19,2)) AS valor_pfpb_ano,
    CAST(SUM(M.total_sem_comprovacao) AS DECIMAL(19,2)) AS valor_sem_comprovacao_ano,
    SUM(CAST(M.total_num_autorizacoes AS BIGINT)) AS qtd_autorizacoes_ano,
    SUM(CAST(M.total_qnt_caixas_vendidas AS BIGINT)) AS qtd_caixas_ano,
    SUM(CAST(M.total_qnt_caixas_sem_comprovacao AS BIGINT)) AS qtd_caixas_sem_comprovacao_ano
INTO #movimentacao_esocial_ano
FROM temp_CGUSC.fp.movimentacao_mensal_cnpj AS M
INNER JOIN temp_CGUSC.fp.dados_farmacia AS F
    ON F.cnpj = M.cnpj
INNER JOIN temp_CGUSC.fp.esocial_cnpj_ano AS E
    ON E.id_cnpj = F.id
   AND E.ano_base = YEAR(M.periodo)
GROUP BY
    F.id,
    YEAR(M.periodo),
    F.id_regiao_saude,
    UPPER(LTRIM(RTRIM(F.uf)));

IF NOT EXISTS (SELECT 1 FROM #movimentacao_esocial_ano)
BEGIN
    RAISERROR('Nenhuma movimentacao anual encontrada para cruzar com contexto eSocial.', 16, 1);
    RETURN;
END;

CREATE UNIQUE CLUSTERED INDEX IX_tmp_mov_esocial_ano
ON #movimentacao_esocial_ano (id_cnpj, ano_base);

DROP TABLE IF EXISTS #ultima_movimentacao_esocial;

SELECT
    CAST(F.id AS INT) AS id_cnpj,
    MAX(CAST(M.periodo AS DATE)) AS ultimo_periodo_movimentacao
INTO #ultima_movimentacao_esocial
FROM temp_CGUSC.fp.movimentacao_mensal_cnpj AS M
INNER JOIN temp_CGUSC.fp.dados_farmacia AS F
    ON F.cnpj = M.cnpj
WHERE M.total_vendas > 0
GROUP BY F.id;

CREATE UNIQUE CLUSTERED INDEX IX_tmp_ultima_mov_esocial
ON #ultima_movimentacao_esocial (id_cnpj);

DROP TABLE IF EXISTS #ultima_movimentacao_esocial_valores;

SELECT
    U.id_cnpj,
    CAST(YEAR(U.ultimo_periodo_movimentacao) AS SMALLINT) AS ano_base,
    U.ultimo_periodo_movimentacao,
    CAST(DATEFROMPARTS(YEAR(U.ultimo_periodo_movimentacao), MONTH(U.ultimo_periodo_movimentacao), 1) AS DATE) AS dt_inicio_ultimo_mes_movimentacao,
    EOMONTH(U.ultimo_periodo_movimentacao) AS dt_referencia_ultima_movimentacao,
    CAST(SUM(M.total_vendas) AS DECIMAL(19,2)) AS valor_pfpb_ultimo_mes,
    SUM(CAST(M.total_num_autorizacoes AS BIGINT)) AS qtd_autorizacoes_ultimo_mes
INTO #ultima_movimentacao_esocial_valores
FROM #ultima_movimentacao_esocial AS U
INNER JOIN temp_CGUSC.fp.dados_farmacia AS F
    ON F.id = U.id_cnpj
INNER JOIN temp_CGUSC.fp.movimentacao_mensal_cnpj AS M
    ON M.cnpj = F.cnpj
   AND CAST(M.periodo AS DATE) = U.ultimo_periodo_movimentacao
GROUP BY
    U.id_cnpj,
    U.ultimo_periodo_movimentacao;

CREATE UNIQUE CLUSTERED INDEX IX_tmp_ultima_mov_esocial_valores
ON #ultima_movimentacao_esocial_valores (id_cnpj, ano_base);

DROP TABLE IF EXISTS #ultima_movimentacao_esocial_referencia;

SELECT
    U.id_cnpj,
    U.ano_base AS ano_ultima_movimentacao,
    R.ano_base AS ano_esocial_referencia_ultima_movimentacao,
    CAST(CASE WHEN R.ano_base = U.ano_base THEN 0 ELSE 1 END AS BIT) AS is_sem_esocial_no_ano_ultima_movimentacao,
    U.ultimo_periodo_movimentacao,
    U.dt_inicio_ultimo_mes_movimentacao,
    U.dt_referencia_ultima_movimentacao,
    U.valor_pfpb_ultimo_mes,
    U.qtd_autorizacoes_ultimo_mes
INTO #ultima_movimentacao_esocial_referencia
FROM #ultima_movimentacao_esocial_valores AS U
OUTER APPLY (
    SELECT MAX(C.ano_base) AS ano_base
    FROM #competencias_esocial_ano AS C
    WHERE C.id_cnpj = U.id_cnpj
      AND C.ano_base <= U.ano_base
) AS R
WHERE R.ano_base IS NOT NULL;

CREATE UNIQUE CLUSTERED INDEX IX_tmp_ultima_mov_esocial_ref
ON #ultima_movimentacao_esocial_referencia (id_cnpj, ano_esocial_referencia_ultima_movimentacao);

DROP TABLE IF EXISTS #ultima_movimentacao_esocial_ativos;

SELECT
    U.id_cnpj,
    U.ano_ultima_movimentacao,
    U.ano_esocial_referencia_ultima_movimentacao,
    U.is_sem_esocial_no_ano_ultima_movimentacao,
    COUNT(DISTINCT CASE
        WHEN (
              T.dt_admissao IS NULL
              OR T.dt_admissao <= U.dt_referencia_ultima_movimentacao
          )
          AND (
              T.dt_rescisao IS NULL
              OR T.dt_rescisao >= U.dt_inicio_ultimo_mes_movimentacao
          )
            THEN T.cpf_trabalhador
    END) AS qtd_trabalhadores_ativos_ultima_movimentacao,
    COUNT(DISTINCT CASE
        WHEN T.is_farmaceutico = 1
          AND (
              T.dt_admissao IS NULL
              OR T.dt_admissao <= U.dt_referencia_ultima_movimentacao
          )
          AND (
              T.dt_rescisao IS NULL
              OR T.dt_rescisao >= U.dt_inicio_ultimo_mes_movimentacao
          )
            THEN T.cpf_trabalhador
    END) AS qtd_farmaceuticos_ativos_ultima_movimentacao,
    MAX(CASE
        WHEN T.dt_rescisao < U.dt_inicio_ultimo_mes_movimentacao
            THEN T.dt_rescisao
    END) AS dt_ultima_rescisao_antes_ultima_movimentacao
INTO #ultima_movimentacao_esocial_ativos
FROM #ultima_movimentacao_esocial_referencia AS U
LEFT JOIN #trabalhadores_esocial_ano AS T
    ON T.id_cnpj = U.id_cnpj
   AND T.ano_base = U.ano_esocial_referencia_ultima_movimentacao
GROUP BY
    U.id_cnpj,
    U.ano_ultima_movimentacao,
    U.ano_esocial_referencia_ultima_movimentacao,
    U.is_sem_esocial_no_ano_ultima_movimentacao;

CREATE UNIQUE CLUSTERED INDEX IX_tmp_ultima_mov_esocial_ativos
ON #ultima_movimentacao_esocial_ativos (id_cnpj, ano_esocial_referencia_ultima_movimentacao);

SET @linhas_esocial = (SELECT COUNT_BIG(*) FROM #ultima_movimentacao_esocial_referencia);
SET @msg_esocial = CONCAT(
    '[eSocial] 12a - ultima movimentacao PFPB por CNPJ com referencia eSocial apurada | linhas=',
    @linhas_esocial,
    ' | etapa_ms=',
    DATEDIFF(MILLISECOND, @tempo_etapa_esocial, SYSDATETIME()),
    ' | total_ms=',
    DATEDIFF(MILLISECOND, @tempo_total_esocial, SYSDATETIME())
);
RAISERROR(@msg_esocial, 0, 1) WITH NOWAIT;
SET @tempo_etapa_esocial = SYSDATETIME();

DROP TABLE IF EXISTS temp_CGUSC.fp.esocial_cnpj_ultima_movimentacao;

SELECT
    U.id_cnpj,
    U.ano_ultima_movimentacao,
    U.ano_esocial_referencia_ultima_movimentacao,
    U.is_sem_esocial_no_ano_ultima_movimentacao,
    U.ultimo_periodo_movimentacao,
    U.dt_inicio_ultimo_mes_movimentacao,
    U.dt_referencia_ultima_movimentacao,
    U.valor_pfpb_ultimo_mes,
    U.qtd_autorizacoes_ultimo_mes,
    COALESCE(A.qtd_trabalhadores_ativos_ultima_movimentacao, 0) AS qtd_trabalhadores_ativos_ultima_movimentacao,
    COALESCE(A.qtd_farmaceuticos_ativos_ultima_movimentacao, 0) AS qtd_farmaceuticos_ativos_ultima_movimentacao,
    A.dt_ultima_rescisao_antes_ultima_movimentacao,
    CAST(
        CASE
            WHEN U.valor_pfpb_ultimo_mes > 0
                 AND COALESCE(A.qtd_trabalhadores_ativos_ultima_movimentacao, 0) = 0
                THEN 1
            ELSE 0
        END AS BIT
    ) AS has_movimentacao_sem_funcionario_ativo,
    CAST(
        CASE
            WHEN U.valor_pfpb_ultimo_mes > 0
                 AND COALESCE(A.qtd_trabalhadores_ativos_ultima_movimentacao, 0) = 0
                THEN 'forte'
            ELSE 'sem_alerta'
        END AS VARCHAR(20)
    ) AS classificacao_mov_sem_funcionario,
    CAST(
        CASE
            WHEN U.valor_pfpb_ultimo_mes > 0
                 AND COALESCE(A.qtd_trabalhadores_ativos_ultima_movimentacao, 0) = 0
                THEN 'Ultimo mes com movimentacao PFPB sem trabalhador ativo identificado no eSocial para a competencia.'
            ELSE 'Ultimo mes com movimentacao PFPB possui trabalhador ativo identificado no eSocial para a competencia.'
        END AS NVARCHAR(300)
    ) AS motivo_mov_sem_funcionario,
    GETDATE() AS dt_processamento
INTO temp_CGUSC.fp.esocial_cnpj_ultima_movimentacao
FROM #ultima_movimentacao_esocial_referencia AS U
LEFT JOIN #ultima_movimentacao_esocial_ativos AS A
    ON A.id_cnpj = U.id_cnpj
   AND A.ano_esocial_referencia_ultima_movimentacao = U.ano_esocial_referencia_ultima_movimentacao;

SET @linhas_esocial = (SELECT COUNT_BIG(*) FROM temp_CGUSC.fp.esocial_cnpj_ultima_movimentacao);
SET @msg_esocial = CONCAT(
    '[eSocial] 12b - tabela esocial_cnpj_ultima_movimentacao persistida | linhas=',
    @linhas_esocial,
    ' | etapa_ms=',
    DATEDIFF(MILLISECOND, @tempo_etapa_esocial, SYSDATETIME()),
    ' | total_ms=',
    DATEDIFF(MILLISECOND, @tempo_total_esocial, SYSDATETIME())
);
RAISERROR(@msg_esocial, 0, 1) WITH NOWAIT;
SET @tempo_etapa_esocial = SYSDATETIME();

CREATE UNIQUE CLUSTERED INDEX IX_esocial_cnpj_ultima_movimentacao
ON temp_CGUSC.fp.esocial_cnpj_ultima_movimentacao (id_cnpj);

CREATE NONCLUSTERED INDEX IX_esocial_cnpj_ultima_movimentacao_alerta
ON temp_CGUSC.fp.esocial_cnpj_ultima_movimentacao (has_movimentacao_sem_funcionario_ativo, ano_ultima_movimentacao)
INCLUDE (ultimo_periodo_movimentacao, valor_pfpb_ultimo_mes, qtd_autorizacoes_ultimo_mes);

SET @msg_esocial = CONCAT(
    '[eSocial] 12c - indices esocial_cnpj_ultima_movimentacao criados | etapa_ms=',
    DATEDIFF(MILLISECOND, @tempo_etapa_esocial, SYSDATETIME()),
    ' | total_ms=',
    DATEDIFF(MILLISECOND, @tempo_total_esocial, SYSDATETIME())
);
RAISERROR(@msg_esocial, 0, 1) WITH NOWAIT;
SET @tempo_etapa_esocial = SYSDATETIME();

DROP TABLE IF EXISTS #movimentacao_esocial_metricas;

SELECT
    M.id_cnpj,
    M.ano_base,
    M.id_regiao_saude,
    M.uf,
    M.periodo_min,
    M.periodo_max,
    M.valor_pfpb_ano,
    M.valor_sem_comprovacao_ano,
    M.qtd_autorizacoes_ano,
    M.qtd_caixas_ano,
    M.qtd_caixas_sem_comprovacao_ano,
    E.qtd_trabalhadores,
    E.qtd_farmaceuticos,
    CAST(CASE WHEN E.qtd_trabalhadores > 0 THEN M.valor_pfpb_ano / E.qtd_trabalhadores END AS DECIMAL(19,2)) AS valor_pfpb_por_trabalhador,
    CAST(CASE WHEN E.qtd_trabalhadores > 0 THEN M.valor_sem_comprovacao_ano / E.qtd_trabalhadores END AS DECIMAL(19,2)) AS valor_sem_comprovacao_por_trabalhador,
    CAST(CASE WHEN E.qtd_trabalhadores > 0 THEN CAST(M.qtd_autorizacoes_ano AS DECIMAL(19,4)) / E.qtd_trabalhadores END AS DECIMAL(19,2)) AS autorizacoes_por_trabalhador,
    CAST(CASE WHEN E.qtd_trabalhadores > 0 THEN CAST(M.qtd_caixas_ano AS DECIMAL(19,4)) / E.qtd_trabalhadores END AS DECIMAL(19,2)) AS caixas_por_trabalhador
INTO #movimentacao_esocial_metricas
FROM #movimentacao_esocial_ano AS M
INNER JOIN temp_CGUSC.fp.esocial_cnpj_ano AS E
    ON E.id_cnpj = M.id_cnpj
   AND E.ano_base = M.ano_base;

IF EXISTS (
    SELECT 1
    FROM #movimentacao_esocial_metricas
    WHERE qtd_trabalhadores IS NULL
       OR qtd_farmaceuticos IS NULL
)
BEGIN
    RAISERROR('Metricas eSocial/movimentacao sem quantidades obrigatorias para referencia regional.', 16, 1);
    RETURN;
END;

CREATE UNIQUE CLUSTERED INDEX IX_tmp_mov_esocial_metricas
ON #movimentacao_esocial_metricas (id_cnpj, ano_base);

DROP TABLE IF EXISTS #movimentacao_esocial_regional;

WITH referencias_base AS (
    SELECT
        id_cnpj,
        ano_base,
        id_regiao_saude,
        uf,
        valor_pfpb_ano,
        valor_pfpb_por_trabalhador
    FROM #movimentacao_esocial_metricas
    WHERE qtd_trabalhadores > 0
),
regional_ref AS (
    SELECT DISTINCT
        ano_base,
        id_regiao_saude,
        CAST(PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY valor_pfpb_ano) OVER (PARTITION BY ano_base, id_regiao_saude) AS DECIMAL(19,2)) AS p90_regional_valor_pfpb_ano,
        CAST(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY valor_pfpb_por_trabalhador) OVER (PARTITION BY ano_base, id_regiao_saude) AS DECIMAL(19,2)) AS p95_regional_valor_por_trabalhador,
        COUNT_BIG(*) OVER (PARTITION BY ano_base, id_regiao_saude) AS qtd_cnpjs_referencia_regional
    FROM referencias_base
),
uf_ref AS (
    SELECT DISTINCT
        ano_base,
        uf,
        CAST(PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY valor_pfpb_ano) OVER (PARTITION BY ano_base, uf) AS DECIMAL(19,2)) AS p90_uf_valor_pfpb_ano,
        CAST(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY valor_pfpb_por_trabalhador) OVER (PARTITION BY ano_base, uf) AS DECIMAL(19,2)) AS p95_uf_valor_por_trabalhador,
        COUNT_BIG(*) OVER (PARTITION BY ano_base, uf) AS qtd_cnpjs_referencia_uf
    FROM referencias_base
)
SELECT
    M.ano_base,
    M.id_regiao_saude,
    M.uf,
    CAST(
        CASE WHEN R.qtd_cnpjs_referencia_regional >= 10
            THEN R.p90_regional_valor_pfpb_ano
            ELSE U.p90_uf_valor_pfpb_ano
        END AS DECIMAL(19,2)
    ) AS p90_referencia_valor_pfpb_ano,
    CAST(
        CASE WHEN R.qtd_cnpjs_referencia_regional >= 10
            THEN R.p95_regional_valor_por_trabalhador
            ELSE U.p95_uf_valor_por_trabalhador
        END AS DECIMAL(19,2)
    ) AS p95_referencia_valor_por_trabalhador,
    CAST(
        CASE WHEN R.qtd_cnpjs_referencia_regional >= 10
            THEN R.qtd_cnpjs_referencia_regional
            ELSE U.qtd_cnpjs_referencia_uf
        END AS BIGINT
    ) AS qtd_cnpjs_referencia,
    CAST(
        CASE WHEN R.qtd_cnpjs_referencia_regional >= 10
            THEN 'regional'
            ELSE 'uf'
        END AS VARCHAR(20)
    ) AS escopo_referencia
INTO #movimentacao_esocial_regional
FROM (
    SELECT DISTINCT ano_base, id_regiao_saude, uf
    FROM #movimentacao_esocial_metricas
) AS M
LEFT JOIN regional_ref AS R
    ON R.ano_base = M.ano_base
   AND R.id_regiao_saude = M.id_regiao_saude
LEFT JOIN uf_ref AS U
    ON U.ano_base = M.ano_base
   AND U.uf = M.uf;

IF EXISTS (
    SELECT 1
    FROM #movimentacao_esocial_regional
    WHERE p90_referencia_valor_pfpb_ano IS NULL
       OR p95_referencia_valor_por_trabalhador IS NULL
       OR qtd_cnpjs_referencia IS NULL
)
BEGIN
    RAISERROR('Referencias regional/UF eSocial/movimentacao nao calculadas para todos os escopos/anos.', 16, 1);
    RETURN;
END;

IF EXISTS (
    SELECT 1
    FROM #movimentacao_esocial_regional
    WHERE escopo_referencia = 'uf'
      AND qtd_cnpjs_referencia < 10
)
BEGIN
    RAISERROR('Referencia UF eSocial/movimentacao com menos de 10 CNPJs com trabalhadores ativos.', 16, 1);
    RETURN;
END;

CREATE UNIQUE CLUSTERED INDEX IX_tmp_mov_esocial_regional
ON #movimentacao_esocial_regional (ano_base, id_regiao_saude, uf);

DROP TABLE IF EXISTS temp_CGUSC.fp.esocial_cnpj_movimentacao_ano;

SELECT
    M.id_cnpj,
    M.ano_base,
    M.id_regiao_saude,
    M.uf,
    M.periodo_min,
    M.periodo_max,
    M.valor_pfpb_ano,
    M.valor_sem_comprovacao_ano,
    M.qtd_autorizacoes_ano,
    M.qtd_caixas_ano,
    M.qtd_caixas_sem_comprovacao_ano,
    M.qtd_trabalhadores,
    M.qtd_farmaceuticos,
    M.valor_pfpb_por_trabalhador,
    M.valor_sem_comprovacao_por_trabalhador,
    M.autorizacoes_por_trabalhador,
    M.caixas_por_trabalhador,
    R.p90_referencia_valor_pfpb_ano,
    R.p95_referencia_valor_por_trabalhador,
    R.qtd_cnpjs_referencia,
    R.escopo_referencia,
    CAST(
        CASE
            WHEN M.qtd_trabalhadores = 0
                 AND M.valor_pfpb_ano > 0
                THEN 'forte'
            WHEN M.qtd_trabalhadores > 0
                 AND M.qtd_farmaceuticos = 0
                 AND M.valor_pfpb_por_trabalhador >= R.p95_referencia_valor_por_trabalhador
                THEN 'forte'
            WHEN M.qtd_trabalhadores BETWEEN 1 AND 2
                 AND M.qtd_farmaceuticos > 0
                 AND M.valor_pfpb_por_trabalhador >= R.p95_referencia_valor_por_trabalhador
                THEN 'moderada'
            WHEN M.qtd_trabalhadores BETWEEN 1 AND 2
                 AND M.valor_pfpb_ano >= R.p90_referencia_valor_pfpb_ano
                 AND M.valor_pfpb_por_trabalhador < R.p95_referencia_valor_por_trabalhador
                THEN 'atencao'
            ELSE 'sem_alerta'
        END AS VARCHAR(20)
    ) AS classificacao_mov_trabalhista,
    CAST(
        CASE
            WHEN M.qtd_trabalhadores = 0
                 AND M.valor_pfpb_ano > 0
                THEN 'Sem trabalhador ativo na competencia-base e com movimentacao PFPB no ano.'
            WHEN M.qtd_trabalhadores > 0
                 AND M.qtd_farmaceuticos = 0
                 AND M.valor_pfpb_por_trabalhador >= R.p95_referencia_valor_por_trabalhador
                THEN CONCAT('Sem farmaceutico e valor PFPB por trabalhador igual ou superior ao p95 do escopo ', R.escopo_referencia, '.')
            WHEN M.qtd_trabalhadores BETWEEN 1 AND 2
                 AND M.qtd_farmaceuticos > 0
                 AND M.valor_pfpb_por_trabalhador >= R.p95_referencia_valor_por_trabalhador
                THEN CONCAT('Ate dois trabalhadores e valor PFPB por trabalhador igual ou superior ao p95 do escopo ', R.escopo_referencia, '.')
            WHEN M.qtd_trabalhadores BETWEEN 1 AND 2
                 AND M.valor_pfpb_ano >= R.p90_referencia_valor_pfpb_ano
                 AND M.valor_pfpb_por_trabalhador < R.p95_referencia_valor_por_trabalhador
                THEN CONCAT('Ate dois trabalhadores e valor PFPB anual igual ou superior ao p90 do escopo ', R.escopo_referencia, '.')
            ELSE 'Sem alerta pelas regras eSocial/movimentacao.'
        END AS NVARCHAR(300)
    ) AS motivo_classificacao,
    GETDATE() AS dt_processamento
INTO temp_CGUSC.fp.esocial_cnpj_movimentacao_ano
FROM #movimentacao_esocial_metricas AS M
INNER JOIN #movimentacao_esocial_regional AS R
    ON R.ano_base = M.ano_base
   AND R.id_regiao_saude = M.id_regiao_saude
   AND R.uf = M.uf;

SET @linhas_esocial = (SELECT COUNT_BIG(*) FROM temp_CGUSC.fp.esocial_cnpj_movimentacao_ano);
SET @msg_esocial = CONCAT(
    '[eSocial] 13 - tabela esocial_cnpj_movimentacao_ano persistida | linhas=',
    @linhas_esocial,
    ' | etapa_ms=',
    DATEDIFF(MILLISECOND, @tempo_etapa_esocial, SYSDATETIME()),
    ' | total_ms=',
    DATEDIFF(MILLISECOND, @tempo_total_esocial, SYSDATETIME())
);
RAISERROR(@msg_esocial, 0, 1) WITH NOWAIT;
SET @tempo_etapa_esocial = SYSDATETIME();

CREATE UNIQUE CLUSTERED INDEX IX_esocial_cnpj_movimentacao_ano
ON temp_CGUSC.fp.esocial_cnpj_movimentacao_ano (id_cnpj, ano_base);

CREATE NONCLUSTERED INDEX IX_esocial_cnpj_movimentacao_ano_classificacao
ON temp_CGUSC.fp.esocial_cnpj_movimentacao_ano (classificacao_mov_trabalhista, id_regiao_saude, ano_base)
INCLUDE (uf, escopo_referencia, valor_pfpb_ano, valor_pfpb_por_trabalhador, qtd_trabalhadores, qtd_farmaceuticos);

SET @msg_esocial = CONCAT(
    '[eSocial] 14 - indices esocial_cnpj_movimentacao_ano criados | etapa_ms=',
    DATEDIFF(MILLISECOND, @tempo_etapa_esocial, SYSDATETIME()),
    ' | total_ms=',
    DATEDIFF(MILLISECOND, @tempo_total_esocial, SYSDATETIME())
);
RAISERROR(@msg_esocial, 0, 1) WITH NOWAIT;
SET @tempo_etapa_esocial = SYSDATETIME();

IF OBJECT_ID('temp_CGUSC.fp.sentinela_metadados_base', 'U') IS NULL
BEGIN
    CREATE TABLE temp_CGUSC.fp.sentinela_metadados_base (
        nome_base NVARCHAR(80) NOT NULL,
        nome_artefato NVARCHAR(160) NOT NULL,
        fonte_origem NVARCHAR(300) NOT NULL,
        dt_referencia_min DATETIME2(7) NULL,
        dt_referencia_max DATETIME2(7) NULL,
        competencia_min INT NULL,
        competencia_max INT NULL,
        qtd_registros BIGINT NOT NULL,
        qtd_chaves BIGINT NULL,
        schema_versao INT NOT NULL,
        dt_processamento_inicio DATETIME2(7) NOT NULL,
        dt_processamento_fim DATETIME2(7) NOT NULL,
        observacao NVARCHAR(1000) NULL
    );
END;

IF COL_LENGTH('temp_CGUSC.fp.sentinela_metadados_base', 'nome_base') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.sentinela_metadados_base', 'nome_artefato') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.sentinela_metadados_base', 'fonte_origem') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.sentinela_metadados_base', 'dt_referencia_min') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.sentinela_metadados_base', 'dt_referencia_max') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.sentinela_metadados_base', 'competencia_min') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.sentinela_metadados_base', 'competencia_max') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.sentinela_metadados_base', 'qtd_registros') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.sentinela_metadados_base', 'qtd_chaves') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.sentinela_metadados_base', 'schema_versao') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.sentinela_metadados_base', 'dt_processamento_inicio') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.sentinela_metadados_base', 'dt_processamento_fim') IS NULL
   OR COL_LENGTH('temp_CGUSC.fp.sentinela_metadados_base', 'observacao') IS NULL
BEGIN
    RAISERROR('Tabela temp_CGUSC.fp.sentinela_metadados_base sem colunas obrigatorias.', 16, 1);
    RETURN;
END;

IF NOT EXISTS (
    SELECT 1
    FROM temp_CGUSC.sys.indexes
    WHERE object_id = OBJECT_ID('temp_CGUSC.fp.sentinela_metadados_base')
      AND name = 'UX_sentinela_metadados_base'
)
BEGIN
    CREATE UNIQUE INDEX UX_sentinela_metadados_base
    ON temp_CGUSC.fp.sentinela_metadados_base (nome_base, nome_artefato);
END;

DECLARE @tempo_fim_esocial DATETIME2(7) = SYSDATETIME();

DELETE FROM temp_CGUSC.fp.sentinela_metadados_base
WHERE nome_base = N'esocial'
  AND nome_artefato IN (
      N'esocial_cnpj_trabalhador_ano',
      N'esocial_cnpj_ano',
      N'esocial_cnpj_movimentacao_ano',
      N'esocial_cnpj_ultima_movimentacao'
  );

INSERT INTO temp_CGUSC.fp.sentinela_metadados_base (
    nome_base,
    nome_artefato,
    fonte_origem,
    dt_referencia_min,
    dt_referencia_max,
    competencia_min,
    competencia_max,
    qtd_registros,
    qtd_chaves,
    schema_versao,
    dt_processamento_inicio,
    dt_processamento_fim,
    observacao
)
SELECT
    N'esocial' AS nome_base,
    N'esocial_cnpj_trabalhador_ano' AS nome_artefato,
    N'db_eSocial.dbo.trabalhadores' AS fonte_origem,
    MIN(CAST(dt_carga_fonte AS DATETIME2(7))) AS dt_referencia_min,
    MAX(CAST(dt_carga_fonte AS DATETIME2(7))) AS dt_referencia_max,
    MIN(competencia_base) AS competencia_min,
    MAX(competencia_base) AS competencia_max,
    COUNT_BIG(*) AS qtd_registros,
    COUNT_BIG(DISTINCT id_cnpj) AS qtd_chaves,
    1 AS schema_versao,
    @tempo_total_esocial AS dt_processamento_inicio,
    @tempo_fim_esocial AS dt_processamento_fim,
    CONCAT(
        N'qtd_registros_cbo_sem_titulo=',
        SUM(CASE WHEN is_cbo_sem_titulo = 1 THEN 1 ELSE 0 END)
    ) AS observacao
FROM temp_CGUSC.fp.esocial_cnpj_trabalhador_ano
UNION ALL
SELECT
    N'esocial' AS nome_base,
    N'esocial_cnpj_ano' AS nome_artefato,
    N'temp_CGUSC.fp.esocial_cnpj_trabalhador_ano' AS fonte_origem,
    MIN(CAST(dt_carga_fonte AS DATETIME2(7))) AS dt_referencia_min,
    MAX(CAST(dt_carga_fonte AS DATETIME2(7))) AS dt_referencia_max,
    MIN(competencia_base) AS competencia_min,
    MAX(competencia_base) AS competencia_max,
    COUNT_BIG(*) AS qtd_registros,
    COUNT_BIG(DISTINCT id_cnpj) AS qtd_chaves,
    1 AS schema_versao,
    @tempo_total_esocial AS dt_processamento_inicio,
    @tempo_fim_esocial AS dt_processamento_fim,
    CONCAT(
        N'qtd_cnpjs_ano_com_cbo_sem_titulo=',
        SUM(CASE WHEN has_cbo_sem_titulo = 1 THEN 1 ELSE 0 END)
    ) AS observacao
FROM temp_CGUSC.fp.esocial_cnpj_ano
UNION ALL
SELECT
    N'esocial' AS nome_base,
    N'esocial_cnpj_movimentacao_ano' AS nome_artefato,
    N'temp_CGUSC.fp.movimentacao_mensal_cnpj + temp_CGUSC.fp.esocial_cnpj_ano' AS fonte_origem,
    MIN(CAST(periodo_min AS DATETIME2(7))) AS dt_referencia_min,
    MAX(CAST(periodo_max AS DATETIME2(7))) AS dt_referencia_max,
    MIN((YEAR(periodo_min) * 100) + MONTH(periodo_min)) AS competencia_min,
    MAX((YEAR(periodo_max) * 100) + MONTH(periodo_max)) AS competencia_max,
    COUNT_BIG(*) AS qtd_registros,
    COUNT_BIG(DISTINCT id_cnpj) AS qtd_chaves,
    1 AS schema_versao,
    @tempo_total_esocial AS dt_processamento_inicio,
    @tempo_fim_esocial AS dt_processamento_fim,
    CONCAT(
        N'qtd_alertas_movimentacao_trabalhista=',
        SUM(CASE WHEN classificacao_mov_trabalhista <> N'sem_alerta' THEN 1 ELSE 0 END)
    ) AS observacao
FROM temp_CGUSC.fp.esocial_cnpj_movimentacao_ano
UNION ALL
SELECT
    N'esocial' AS nome_base,
    N'esocial_cnpj_ultima_movimentacao' AS nome_artefato,
    N'temp_CGUSC.fp.movimentacao_mensal_cnpj + temp_CGUSC.fp.esocial_cnpj_trabalhador_ano' AS fonte_origem,
    MIN(CAST(ultimo_periodo_movimentacao AS DATETIME2(7))) AS dt_referencia_min,
    MAX(CAST(ultimo_periodo_movimentacao AS DATETIME2(7))) AS dt_referencia_max,
    MIN((YEAR(ultimo_periodo_movimentacao) * 100) + MONTH(ultimo_periodo_movimentacao)) AS competencia_min,
    MAX((YEAR(ultimo_periodo_movimentacao) * 100) + MONTH(ultimo_periodo_movimentacao)) AS competencia_max,
    COUNT_BIG(*) AS qtd_registros,
    COUNT_BIG(DISTINCT id_cnpj) AS qtd_chaves,
    1 AS schema_versao,
    @tempo_total_esocial AS dt_processamento_inicio,
    @tempo_fim_esocial AS dt_processamento_fim,
    CONCAT(
        N'qtd_alertas_ultimo_mes_sem_funcionario=',
        SUM(CASE WHEN has_movimentacao_sem_funcionario_ativo = 1 THEN 1 ELSE 0 END)
    ) AS observacao
FROM temp_CGUSC.fp.esocial_cnpj_ultima_movimentacao;

SET @linhas_esocial = (
    SELECT COUNT_BIG(*)
    FROM temp_CGUSC.fp.sentinela_metadados_base
    WHERE nome_base = N'esocial'
      AND nome_artefato IN (
          N'esocial_cnpj_trabalhador_ano',
          N'esocial_cnpj_ano',
          N'esocial_cnpj_movimentacao_ano',
          N'esocial_cnpj_ultima_movimentacao'
      )
);
SET @msg_esocial = CONCAT(
    '[eSocial] 15 - metadados de base atualizados | linhas=',
    @linhas_esocial,
    ' | etapa_ms=',
    DATEDIFF(MILLISECOND, @tempo_etapa_esocial, SYSDATETIME()),
    ' | total_ms=',
    DATEDIFF(MILLISECOND, @tempo_total_esocial, SYSDATETIME())
);
RAISERROR(@msg_esocial, 0, 1) WITH NOWAIT;
SET @tempo_etapa_esocial = SYSDATETIME();

SET @msg_esocial = CONCAT(
    '[eSocial] fim - processamento concluido | total_ms=',
    DATEDIFF(MILLISECOND, @tempo_total_esocial, SYSDATETIME())
);
RAISERROR(@msg_esocial, 0, 1) WITH NOWAIT;






