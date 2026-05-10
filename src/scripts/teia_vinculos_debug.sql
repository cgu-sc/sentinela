

DECLARE @cnpj CHAR(14) = '02647900000150';

-- Acumulado como a tela tende a ficar apos merge N2 -> N3 -> N4
WITH
SociosDiretos AS (
    SELECT *
    FROM temp_CGUSC.fp.dados_socios
    WHERE cnpj = @cnpj
      AND cpf_cnpj_socio IS NOT NULL
),
CpfsDiretos AS (
    SELECT DISTINCT cpf_cnpj_socio
    FROM SociosDiretos
),
Nivel2Empresas AS (
    SELECT T2.*
    FROM temp_CGUSC.fp.teia_fonte_nivel2 T2
    INNER JOIN CpfsDiretos S
        ON S.cpf_cnpj_socio = T2.cpf_cnpj_socio
),
CnpjsNivel2 AS (
    SELECT DISTINCT cnpj_empresa
    FROM Nivel2Empresas
    WHERE cnpj_empresa IS NOT NULL
),
Nivel3Socios AS (
    SELECT T3.*
    FROM temp_CGUSC.fp.teia_fonte_nivel3 T3
    INNER JOIN CnpjsNivel2 N2
        ON N2.cnpj_empresa = T3.cnpj_empresa
),
CpfsNivel3Trigger AS (
    SELECT DISTINCT cpf_cnpj_socio
    FROM Nivel3Socios
    WHERE cpf_cnpj_socio IS NOT NULL
),
Nivel4Empresas AS (
    SELECT T4.*
    FROM temp_CGUSC.fp.teia_fonte_nivel4 T4
    INNER JOIN CpfsNivel3Trigger N3
        ON N3.cpf_cnpj_socio = T4.cpf_cnpj_socio
),

NodesN2Endpoint AS (
    SELECT @cnpj AS id, 'PJ_ALVO' AS tipo
    UNION
    SELECT cpf_cnpj_socio, ISNULL(indicador_socio, 'PF')
    FROM SociosDiretos
    WHERE cpf_cnpj_socio IS NOT NULL
    UNION
    SELECT cnpj_empresa, 'PJ'
    FROM Nivel2Empresas
    WHERE cnpj_empresa IS NOT NULL
    UNION
    SELECT cpf_representante, 'PF'
    FROM SociosDiretos
    WHERE cpf_representante IS NOT NULL
      AND LTRIM(RTRIM(cpf_representante)) NOT IN ('', '00000000000')
      AND cpf_representante <> cpf_cnpj_socio
    UNION
    SELECT cpf_representante, 'PF'
    FROM Nivel2Empresas
    WHERE cpf_representante IS NOT NULL
      AND LTRIM(RTRIM(cpf_representante)) NOT IN ('', '00000000000')
      AND cpf_representante <> cpf_cnpj_socio
),
EdgesN2Endpoint AS (
    SELECT DISTINCT
        CAST(cpf_cnpj_socio AS VARCHAR(32)) + '->' + CAST(@cnpj AS VARCHAR(32)) AS id,
        'socio' AS tipo
    FROM SociosDiretos
    WHERE cpf_cnpj_socio IS NOT NULL
    UNION
    SELECT DISTINCT
        CAST(cpf_cnpj_socio AS VARCHAR(32)) + '->' + CAST(cnpj_empresa AS VARCHAR(32)) AS id,
        'socio' AS tipo
    FROM Nivel2Empresas
    WHERE cpf_cnpj_socio IS NOT NULL
      AND cnpj_empresa IS NOT NULL
    UNION
    SELECT DISTINCT
        CAST(cpf_representante AS VARCHAR(32)) + '->' + CAST(cpf_cnpj_socio AS VARCHAR(32)) + ':representante' AS id,
        'representante' AS tipo
    FROM SociosDiretos
    WHERE cpf_representante IS NOT NULL
      AND LTRIM(RTRIM(cpf_representante)) NOT IN ('', '00000000000')
      AND cpf_representante <> cpf_cnpj_socio
    UNION
    SELECT DISTINCT
        CAST(cpf_representante AS VARCHAR(32)) + '->' + CAST(cpf_cnpj_socio AS VARCHAR(32)) + ':representante' AS id,
        'representante' AS tipo
    FROM Nivel2Empresas
    WHERE cpf_representante IS NOT NULL
      AND LTRIM(RTRIM(cpf_representante)) NOT IN ('', '00000000000')
      AND cpf_representante <> cpf_cnpj_socio
),

NodesN3Endpoint AS (
    SELECT cpf_cnpj_socio AS id, ISNULL(indicador_socio, 'PF') AS tipo
    FROM Nivel3Socios
    WHERE cpf_cnpj_socio IS NOT NULL
      AND cpf_cnpj_socio NOT IN (SELECT id FROM NodesN2Endpoint)
    UNION
    SELECT cpf_representante AS id, 'PF' AS tipo
    FROM Nivel3Socios
    WHERE cpf_representante IS NOT NULL
      AND LTRIM(RTRIM(cpf_representante)) NOT IN ('', '00000000000')
      AND cpf_representante <> cpf_cnpj_socio
      AND cpf_representante NOT IN (SELECT id FROM NodesN2Endpoint)
),
EdgesN3Endpoint AS (
    SELECT DISTINCT
        CAST(cpf_cnpj_socio AS VARCHAR(32)) + '->' + CAST(cnpj_empresa AS VARCHAR(32)) AS id,
        'socio' AS tipo
    FROM Nivel3Socios
    WHERE cpf_cnpj_socio IS NOT NULL
      AND cnpj_empresa IS NOT NULL
    UNION
    SELECT DISTINCT
        CAST(cpf_representante AS VARCHAR(32)) + '->' + CAST(cpf_cnpj_socio AS VARCHAR(32)) + ':representante' AS id,
        'representante' AS tipo
    FROM Nivel3Socios
    WHERE cpf_representante IS NOT NULL
      AND LTRIM(RTRIM(cpf_representante)) NOT IN ('', '00000000000')
      AND cpf_representante <> cpf_cnpj_socio
),

NodesN4Endpoint AS (
    SELECT cnpj_empresa AS id, 'PJ' AS tipo
    FROM Nivel4Empresas
    WHERE cnpj_empresa IS NOT NULL
      AND cnpj_empresa NOT IN (SELECT id FROM NodesN2Endpoint)
    UNION
    SELECT cpf_representante AS id, 'PF' AS tipo
    FROM Nivel4Empresas
    WHERE cpf_representante IS NOT NULL
      AND LTRIM(RTRIM(cpf_representante)) NOT IN ('', '00000000000')
      AND cpf_representante <> cpf_cnpj_socio
      AND cpf_representante NOT IN (SELECT id FROM NodesN2Endpoint)
),
EdgesN4Endpoint AS (
    SELECT DISTINCT
        CAST(cpf_cnpj_socio AS VARCHAR(32)) + '->' + CAST(cnpj_empresa AS VARCHAR(32)) AS id,
        'socio' AS tipo
    FROM Nivel4Empresas
    WHERE cpf_cnpj_socio IS NOT NULL
      AND cnpj_empresa IS NOT NULL
    UNION
    SELECT DISTINCT
        CAST(cpf_representante AS VARCHAR(32)) + '->' + CAST(cpf_cnpj_socio AS VARCHAR(32)) + ':representante' AS id,
        'representante' AS tipo
    FROM Nivel4Empresas
    WHERE cpf_representante IS NOT NULL
      AND LTRIM(RTRIM(cpf_representante)) NOT IN ('', '00000000000')
      AND cpf_representante <> cpf_cnpj_socio
),

NodesAll AS (
    SELECT 'N2' AS nivel, id, tipo FROM NodesN2Endpoint
    UNION ALL
    SELECT 'N3', id, tipo FROM NodesN3Endpoint
    UNION ALL
    SELECT 'N4', id, tipo FROM NodesN4Endpoint
),
EdgesAll AS (
    SELECT 'N2' AS nivel, id, tipo FROM EdgesN2Endpoint
    UNION ALL
    SELECT 'N3', id, tipo FROM EdgesN3Endpoint
    UNION ALL
    SELECT 'N4', id, tipo FROM EdgesN4Endpoint
),
-- cole aqui os mesmos CTEs do SQL acima ate EdgesAll
ResumoNodes AS (
    SELECT 'N2 acumulado' AS nivel, COUNT(DISTINCT id) AS entidades
    FROM NodesAll WHERE nivel IN ('N2')
    UNION ALL
    SELECT 'N3 acumulado', COUNT(DISTINCT id)
    FROM NodesAll WHERE nivel IN ('N2', 'N3')
    UNION ALL
    SELECT 'N4 acumulado', COUNT(DISTINCT id)
    FROM NodesAll WHERE nivel IN ('N2', 'N3', 'N4')
),
ResumoEdges AS (
    SELECT 'N2 acumulado' AS nivel, COUNT(DISTINCT id) AS vinculos
    FROM EdgesAll WHERE nivel IN ('N2')
    UNION ALL
    SELECT 'N3 acumulado', COUNT(DISTINCT id)
    FROM EdgesAll WHERE nivel IN ('N2', 'N3')
    UNION ALL
    SELECT 'N4 acumulado', COUNT(DISTINCT id)
    FROM EdgesAll WHERE nivel IN ('N2', 'N3', 'N4')
)
SELECT N.nivel, N.entidades, E.vinculos
FROM ResumoNodes N
JOIN ResumoEdges E ON E.nivel = N.nivel
ORDER BY N.nivel;