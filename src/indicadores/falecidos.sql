USE [temp_CGUSC]
GO

-- ============================================================================
-- DEFINIÇÃO DE VARIÁVEIS DO PERÍODO
-- ============================================================================
DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim DATE = '2024-12-10';

-- ============================================================================
-- PASSO 1: CÁLCULO BASE POR FARMÁCIA (INDICADOR INDIVIDUAL)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_falecidos;

-- 1.1 Calculamos o faturamento apenas dos itens auditados
WITH TotaisPorFarmacia AS (
    SELECT 
        A.cnpj,
        SUM(A.valor_pago) AS valor_total_vendas
    FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
    INNER JOIN temp_CGUSC.fp.medicamentos_patologia C ON C.codigo_barra = A.codigo_barra
    WHERE A.data_hora >= @DataInicio AND A.data_hora <= @DataFim
    GROUP BY A.cnpj
),
-- 1.2 Calculamos o valor das vendas para falecidos
Irregularidades AS (
    SELECT 
        A.cnpj,
        SUM(A.valor_pago) AS valor_falecidos,
        COUNT(*) AS qtd_vendas_falecidos
    FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
    INNER JOIN temp_CGUSC.fp.medicamentos_patologia C ON C.codigo_barra = A.codigo_barra
    INNER JOIN temp_CGUSC.fp.obito_unificada B ON B.cpf = A.CPF
    WHERE A.data_hora >= @DataInicio AND A.data_hora <= @DataFim
      AND B.dt_obito IS NOT NULL AND A.data_hora > B.dt_obito
    GROUP BY A.cnpj
)
SELECT 
    T.cnpj,
    T.valor_total_vendas,
    ISNULL(I.valor_falecidos, 0) AS valor_falecidos,
    ISNULL(I.qtd_vendas_falecidos, 0) AS qtd_vendas_falecidos,
    CAST(
        CASE 
            WHEN T.valor_total_vendas > 0 THEN 
                (CAST(ISNULL(I.valor_falecidos, 0) AS DECIMAL(18,2)) / CAST(T.valor_total_vendas AS DECIMAL(18,2))) * 100.0
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS percentual_falecidos
INTO temp_CGUSC.fp.indicador_falecidos
FROM TotaisPorFarmacia T
LEFT JOIN Irregularidades I ON I.cnpj = T.cnpj
WHERE T.valor_total_vendas > 0;

CREATE CLUSTERED INDEX IDX_IndFalecidos_CNPJ ON temp_CGUSC.fp.indicador_falecidos(cnpj);


-- ============================================================================
-- PASSO 2: CÁLCULO DAS MÉTRICAS POR MUNICÍPIO (MÉDIA + MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_falecidos_mun;

SELECT DISTINCT
    CAST(F.uf AS VARCHAR(2)) AS uf,
    CAST(F.municipio AS VARCHAR(255)) AS municipio,
    -- Mediana (Base para o Risco Estável)
    CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.percentual_falecidos) OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255))) AS DECIMAL(18,4)) AS mediana_municipio,
    -- Média Ponderada (Visão de Impacto Financeiro)
    CAST(
        CASE 
            WHEN SUM(I.valor_total_vendas) OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255))) > 0 THEN 
                (SUM(I.valor_falecidos) OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255))) / SUM(I.valor_total_vendas) OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255)))) * 100.0
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS media_municipio
INTO temp_CGUSC.fp.indicador_falecidos_mun
FROM temp_CGUSC.fp.indicador_falecidos I
INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj;

CREATE CLUSTERED INDEX IDX_IndFalecidosMun_mun ON temp_CGUSC.fp.indicador_falecidos_mun(uf, municipio);


-- ============================================================================
-- PASSO 3: CÁLCULO DAS MÉTRICAS POR ESTADO (MÉDIA + MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_falecidos_uf;

SELECT DISTINCT
    CAST(F.uf AS VARCHAR(2)) AS uf,
    -- Mediana
    CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.percentual_falecidos) OVER (PARTITION BY CAST(F.uf AS VARCHAR(2))) AS DECIMAL(18,4)) AS mediana_estado,
    -- Média Ponderada
    CAST(
        CASE 
            WHEN SUM(I.valor_total_vendas) OVER (PARTITION BY CAST(F.uf AS VARCHAR(2))) > 0 THEN 
                (SUM(I.valor_falecidos) OVER (PARTITION BY CAST(F.uf AS VARCHAR(2))) / SUM(I.valor_total_vendas) OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)))) * 100.0
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS media_estado
INTO temp_CGUSC.fp.indicador_falecidos_uf
FROM temp_CGUSC.fp.indicador_falecidos I
INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj;


-- ============================================================================
-- PASSO 4: CÁLCULO DA MÉTRICA NACIONAL (MÉDIA + MEDIANA)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_falecidos_br;

SELECT DISTINCT
    'BR' AS pais,
    -- Mediana
    CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY percentual_falecidos) OVER () AS DECIMAL(18,4)) AS mediana_pais,
    -- Média Ponderada
    CAST(
        CASE 
            WHEN SUM(valor_total_vendas) OVER () > 0 THEN 
                (SUM(valor_falecidos) OVER () / SUM(valor_total_vendas) OVER ()) * 100.0
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS media_pais
INTO temp_CGUSC.fp.indicador_falecidos_br
FROM temp_CGUSC.fp.indicador_falecidos;


-- ============================================================================
-- PASSO 5: TABELA CONSOLIDADA FINAL (COM DUPLO RISCO)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_falecidos_detalhado;

SELECT 
    I.cnpj,
    F.razaoSocial,
    F.municipio,
    CAST(F.uf AS VARCHAR(2)) AS uf,
    I.valor_total_vendas,
    I.valor_falecidos,
    I.qtd_vendas_falecidos,
    I.percentual_falecidos,
    
    -- Comparativos Municipais
    ISNULL(MUN.mediana_municipio, 0) AS municipio_mediana,
    ISNULL(MUN.media_municipio, 0) AS municipio_media,
    CAST((I.percentual_falecidos + 0.01) / (ISNULL(MUN.mediana_municipio, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_mediana,
    CAST((I.percentual_falecidos + 0.01) / (ISNULL(MUN.media_municipio, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_media,

    -- Comparativos Estaduais
    ISNULL(UF.mediana_estado, 0) AS estado_mediana,
    ISNULL(UF.media_estado, 0) AS estado_media,
    CAST((I.percentual_falecidos + 0.01) / (ISNULL(UF.mediana_estado, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_mediana,
    CAST((I.percentual_falecidos + 0.01) / (ISNULL(UF.media_estado, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_media,

    -- Comparativos Nacionais
    BR.mediana_pais AS pais_mediana,
    BR.media_pais AS pais_media,
    CAST((I.percentual_falecidos + 0.01) / (BR.mediana_pais + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_mediana,
    CAST((I.percentual_falecidos + 0.01) / (BR.media_pais + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_media

INTO temp_CGUSC.fp.indicador_falecidos_detalhado
FROM temp_CGUSC.fp.indicador_falecidos I
INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj
LEFT JOIN temp_CGUSC.fp.indicador_falecidos_mun MUN ON CAST(F.uf AS VARCHAR(2)) = MUN.uf AND CAST(F.municipio AS VARCHAR(255)) = MUN.municipio
LEFT JOIN temp_CGUSC.fp.indicador_falecidos_uf UF ON CAST(F.uf AS VARCHAR(2)) = UF.uf
CROSS JOIN temp_CGUSC.fp.indicador_falecidos_br BR;

CREATE CLUSTERED INDEX IDX_Final_CNPJ ON temp_CGUSC.fp.indicador_falecidos_detalhado(cnpj);
CREATE NONCLUSTERED INDEX IDX_Final_Risco ON temp_CGUSC.fp.indicador_falecidos_detalhado(risco_relativo_mun_mediana DESC);
GO

SELECT TOP 100 * FROM temp_CGUSC.fp.indicador_falecidos_detalhado ORDER BY risco_relativo_mun_mediana DESC;
