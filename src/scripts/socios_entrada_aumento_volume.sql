DECLARE @LimiteCrescimentoPct DECIMAL(9,2) = 50.0;
DECLARE @MaxSemestresAposEntrada INT = 2;

DECLARE @DataInicio DATE = NULL;
DECLARE @DataFim    DATE = NULL;

WITH movimento_periodo AS (
    SELECT
        df.id AS id_cnpj,
        m.cnpj,
        YEAR(m.periodo) * 100 +
            CASE WHEN MONTH(m.periodo) <= 6 THEN 1 ELSE 2 END AS chave_semestre,
        SUM(CAST(m.total_vendas AS DECIMAL(18,2))) AS valor_semestre_periodo,
        SUM(CAST(m.total_sem_comprovacao AS DECIMAL(18,2))) AS valor_sem_comprovacao_periodo
    FROM temp_CGUSC.fp.movimentacao_mensal_cnpj m
    INNER JOIN temp_CGUSC.fp.dados_farmacia df
        ON df.cnpj = m.cnpj
    WHERE (@DataInicio IS NULL OR m.periodo >= @DataInicio)
      AND (@DataFim IS NULL OR m.periodo <= @DataFim)
    GROUP BY
        df.id,
        m.cnpj,
        YEAR(m.periodo) * 100 +
            CASE WHEN MONTH(m.periodo) <= 6 THEN 1 ELSE 2 END
),
socios_ativos AS (
    SELECT
        s.cnpj,
        s.cpf_cnpj_socio,
        s.nome_socio,
        s.descricao_qualificacao,
        s.data_entrada_sociedade,
        YEAR(s.data_entrada_sociedade) * 100 +
            CASE WHEN MONTH(s.data_entrada_sociedade) <= 6 THEN 1 ELSE 2 END AS chave_semestre_entrada
    FROM temp_CGUSC.fp.dados_socios s
    WHERE s.data_entrada_sociedade IS NOT NULL
      AND s.data_exclusao_sociedade IS NULL
),
candidatos AS (
    SELECT
        mp.cnpj,
        df.razaoSocial AS razao_social,
        sa.nome_socio,
        sa.cpf_cnpj_socio,
        sa.descricao_qualificacao,
        sa.data_entrada_sociedade,
        sa.chave_semestre_entrada,
        v.chave_semestre AS chave_semestre_aumento,
        v.chave_semestre_anterior,
        v.taxa_crescimento_pct,
        mp.valor_semestre_periodo,
        mp.valor_sem_comprovacao_periodo,
        CAST(
            ((v.chave_semestre / 100) - (sa.chave_semestre_entrada / 100)) * 2
            + ((v.chave_semestre % 100) - (sa.chave_semestre_entrada % 100))
        AS INT) AS distancia_semestres
    FROM temp_CGUSC.fp.volume_atipico_semestral v
    INNER JOIN movimento_periodo mp
        ON mp.id_cnpj = v.id_cnpj
       AND mp.chave_semestre = v.chave_semestre
    INNER JOIN temp_CGUSC.fp.dados_farmacia df
        ON df.id = v.id_cnpj
    INNER JOIN socios_ativos sa
        ON sa.cnpj = df.cnpj
    WHERE v.taxa_crescimento_pct > @LimiteCrescimentoPct
)
SELECT TOP 50
    cnpj,
    razao_social,
    nome_socio,
    cpf_cnpj_socio,
    descricao_qualificacao,
    data_entrada_sociedade,
    chave_semestre_entrada,
    chave_semestre_aumento,
    chave_semestre_anterior,
    taxa_crescimento_pct,
    distancia_semestres,
    valor_semestre_periodo,
    valor_sem_comprovacao_periodo
FROM candidatos
WHERE distancia_semestres BETWEEN 0 AND @MaxSemestresAposEntrada
ORDER BY
    taxa_crescimento_pct DESC,
    distancia_semestres ASC,
    valor_semestre_periodo DESC;
