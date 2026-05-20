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
FROM temp_CGUSC.fp.dados_farmacia AS F
WHERE F.cnpj = '16883403000166';

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

DROP TABLE IF EXISTS temp_CGUSC.fp.esocial_cnpj_mes;
DROP TABLE IF EXISTS temp_CGUSC.fp.esocial_cnpj_mes_unico_trabalhador;
DROP TABLE IF EXISTS temp_CGUSC.fp.esocial_cnpj_ano_unico_trabalhador;
DROP TABLE IF EXISTS temp_CGUSC.fp.esocial_cnpj_resumo;
DROP TABLE IF EXISTS temp_CGUSC.fp.esocial_cnpj_trabalhador_ano;

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

SELECT
    id_cnpj,
    ano_base,
    MAX(mes_base) AS mes_base,
    MAX(competencia_base) AS competencia_base,
    COUNT_BIG(*) AS qtd_registros,
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
    CASE WHEN COUNT(DISTINCT cpf_trabalhador) = 1 THEN MAX(titulo_cbo) END AS titulo_cbo_unico_trabalhador,
    MAX(dt_carga_fonte) AS dt_carga_fonte,
    GETDATE() AS dt_processamento
INTO temp_CGUSC.fp.esocial_cnpj_ano
FROM #trabalhadores_esocial_ano
GROUP BY id_cnpj, ano_base;

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
  AND nome_artefato IN (N'esocial_cnpj_trabalhador_ano', N'esocial_cnpj_ano');

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
FROM temp_CGUSC.fp.esocial_cnpj_ano;

SET @linhas_esocial = (
    SELECT COUNT_BIG(*)
    FROM temp_CGUSC.fp.sentinela_metadados_base
    WHERE nome_base = N'esocial'
      AND nome_artefato IN (N'esocial_cnpj_trabalhador_ano', N'esocial_cnpj_ano')
);
SET @msg_esocial = CONCAT(
    '[eSocial] 13 - metadados de base atualizados | linhas=',
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






