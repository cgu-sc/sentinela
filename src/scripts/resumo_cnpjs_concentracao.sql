DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim DATE = '2024-12-31';
DECLARE @pipeline_versao VARCHAR(40) = 'v3_2026_05_12';

;WITH universo AS (
    SELECT
        F.uf,
        F.id AS id_cnpj,
        F.cnpj
    FROM temp_CGUSC.fp.crm_concentracao_multiplo_controle C
    INNER JOIN temp_CGUSC.fp.dados_farmacia F
        ON F.id = C.id_cnpj
    WHERE C.status = 'OK'
),
alertas AS (
    SELECT
        F.uf,
        A.id_cnpj,
        A.id_severidade,
        CASE A.id_severidade
            WHEN 4 THEN 'EXTREMO'
            WHEN 3 THEN 'CRITICO'
            WHEN 2 THEN 'GRAVE'
            WHEN 1 THEN 'ALTO'
        END AS severidade
    FROM temp_CGUSC.fp.crm_concentracao_multiplo_alertas A
    INNER JOIN temp_CGUSC.fp.dados_farmacia F
        ON F.id = A.id_cnpj
),
resumo AS (
    SELECT
        U.uf,
        COUNT(DISTINCT U.id_cnpj) AS cnpjs_processados,

        COUNT(DISTINCT CASE WHEN A.id_cnpj IS NULL THEN U.id_cnpj END) AS cnpjs_sem_alerta,

        COUNT(CASE WHEN A.id_severidade = 1 THEN 1 END) AS ocorrencias_alto,
        COUNT(DISTINCT CASE WHEN A.id_severidade = 1 THEN U.id_cnpj END) AS cnpjs_com_alto,

        COUNT(CASE WHEN A.id_severidade = 2 THEN 1 END) AS ocorrencias_grave,
        COUNT(DISTINCT CASE WHEN A.id_severidade = 2 THEN U.id_cnpj END) AS cnpjs_com_grave,

        COUNT(CASE WHEN A.id_severidade = 3 THEN 1 END) AS ocorrencias_critico,
        COUNT(DISTINCT CASE WHEN A.id_severidade = 3 THEN U.id_cnpj END) AS cnpjs_com_critico,

        COUNT(CASE WHEN A.id_severidade = 4 THEN 1 END) AS ocorrencias_extremo,
        COUNT(DISTINCT CASE WHEN A.id_severidade = 4 THEN U.id_cnpj END) AS cnpjs_com_extremo,

        COUNT(A.id_cnpj) AS ocorrencias_total,
        COUNT(DISTINCT A.id_cnpj) AS cnpjs_com_algum_alerta
    FROM universo U
    LEFT JOIN alertas A
        ON A.id_cnpj = U.id_cnpj
    GROUP BY U.uf
)
SELECT
    uf,
    cnpjs_processados,
    cnpjs_sem_alerta,
    cnpjs_com_algum_alerta,
    ocorrencias_total,

    cnpjs_com_alto,
    ocorrencias_alto,

    cnpjs_com_grave,
    ocorrencias_grave,

    cnpjs_com_critico,
    ocorrencias_critico,

    cnpjs_com_extremo,
    ocorrencias_extremo
FROM resumo
ORDER BY uf;
