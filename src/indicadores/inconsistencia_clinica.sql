USE [temp_CGUSC]
GO

-- ============================================================================
-- DEFINIÇÃO DE VARIÁVEIS
-- ============================================================================
DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim DATE = '2024-12-10';

-- ============================================================================
-- PASSO 1: CÁLCULO BASE POR FARMÁCIA (INDICADOR DEMOGRÁFICO)
-- Tabela: temp_CGUSC.fp.indicador_inconsistencia_clinica
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_inconsistencia_clinica;

WITH CalculoDemografico AS (
    SELECT 
        A.cnpj,
        A.num_autorizacao,
        MIN(A.data_hora) AS data_hora_venda,
        
        -- Identifica se ESTA VENDA tem pelo menos 1 item suspeito
        MAX(CASE 
            WHEN C.Patologia = 'Osteoporose' AND B.idSexo = 'M' THEN 1
            WHEN C.Patologia = 'Diabetes' AND (FLOOR(DATEDIFF(DAY, B.dataNascimento, A.data_hora) / 365.25) < 20) THEN 1
            WHEN C.Patologia = 'Doenca De Parkinson' AND (FLOOR(DATEDIFF(DAY, B.dataNascimento, A.data_hora) / 365.25) < 50) THEN 1
            WHEN C.Patologia = 'Hipertensão' AND (FLOOR(DATEDIFF(DAY, B.dataNascimento, A.data_hora) / 365.25) < 20) THEN 1
            ELSE 0 
        END) AS flag_venda_suspeita

    FROM db_farmaciapopular.fp.relatorio_movimentacao_2015_2024 A
    INNER JOIN temp_CGUSC.fp.medicamentos_patologia C 
        ON C.codigo_barra = A.codigo_barra
    INNER JOIN db_CPF.fp.CPF B 
        ON B.CPF = A.cpf

    WHERE 
        A.data_hora >= @DataInicio 
        AND A.data_hora <= @DataFim
        AND B.dataNascimento IS NOT NULL 

    GROUP BY A.cnpj, A.num_autorizacao
),
AgregadoPorFarmacia AS (
    SELECT 
        cnpj,
        COUNT(*) AS total_vendas_monitoradas,
        SUM(flag_venda_suspeita) AS qtd_vendas_suspeitas
    FROM CalculoDemografico
    GROUP BY cnpj
)

SELECT 
    cnpj,
    total_vendas_monitoradas,
    qtd_vendas_suspeitas,
    
    CAST(
        CASE 
            WHEN total_vendas_monitoradas > 0 THEN 
                (CAST(qtd_vendas_suspeitas AS DECIMAL(18,2)) / CAST(total_vendas_monitoradas AS DECIMAL(18,2))) * 100.0
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS percentual_demografico

INTO temp_CGUSC.fp.indicador_inconsistencia_clinica
FROM AgregadoPorFarmacia
WHERE total_vendas_monitoradas > 0;

CREATE CLUSTERED INDEX IDX_IndDemo_CNPJ ON temp_CGUSC.fp.indicador_inconsistencia_clinica(cnpj);


-- ============================================================================
-- PASSO 2: CÁLCULO DAS MÉDIAS POR ESTADO (UF)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_inconsistencia_clinica_uf;

SELECT 
    CAST(F.uf AS VARCHAR(2)) AS uf,
    
    SUM(I.total_vendas_monitoradas) AS total_vendas_uf,
    SUM(I.qtd_vendas_suspeitas) AS total_suspeitas_uf,
    
    -- Média do Estado
    CAST(
        CASE 
            WHEN SUM(I.total_vendas_monitoradas) > 0 THEN 
                (CAST(SUM(I.qtd_vendas_suspeitas) AS DECIMAL(18,2)) / CAST(SUM(I.total_vendas_monitoradas) AS DECIMAL(18,2))) * 100.0
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS percentual_demografico_uf

INTO temp_CGUSC.fp.indicador_inconsistencia_clinica_uf
FROM temp_CGUSC.fp.indicador_inconsistencia_clinica I
INNER JOIN temp_CGUSC.fp.dados_farmacia F 
    ON F.cnpj = I.cnpj
GROUP BY CAST(F.uf AS VARCHAR(2));

CREATE CLUSTERED INDEX IDX_IndDemoUF_uf ON temp_CGUSC.fp.indicador_inconsistencia_clinica_uf(uf);


-- ============================================================================
-- PASSO 3: CÁLCULO DA MÉDIA NACIONAL (BRASIL)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_inconsistencia_clinica_br;

SELECT 
    'BR' AS pais,
    SUM(total_vendas_monitoradas) AS total_vendas_br,
    SUM(qtd_vendas_suspeitas) AS total_suspeitas_br,
    
    -- Média Nacional
    CAST(
        CASE 
            WHEN SUM(total_vendas_monitoradas) > 0 THEN 
                (CAST(SUM(qtd_vendas_suspeitas) AS DECIMAL(18,2)) / CAST(SUM(total_vendas_monitoradas) AS DECIMAL(18,2))) * 100.0
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS percentual_demografico_br

INTO temp_CGUSC.fp.indicador_inconsistencia_clinica_br
FROM temp_CGUSC.fp.indicador_inconsistencia_clinica;


-- ============================================================================
-- PASSO 4: TABELA CONSOLIDADA FINAL (COMPARATIVO DE RISCO)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_inconsistencia_clinica_detalhado;

SELECT 
    I.cnpj,
    F.razaoSocial,
    F.municipio,
    CAST(F.uf AS VARCHAR(2)) AS uf,
    
    I.total_vendas_monitoradas,
    I.qtd_vendas_suspeitas,
    I.percentual_demografico,
    
    -- Comparativos
    ISNULL(UF.percentual_demografico_uf, 0) AS media_estado,
    BR.percentual_demografico_br AS media_pais,
    
    -- RISCO RELATIVO
    CAST(
        CASE 
            WHEN UF.percentual_demografico_uf > 0 THEN 
                I.percentual_demografico / UF.percentual_demografico_uf
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS risco_relativo_uf,

    CAST(
        CASE 
            WHEN BR.percentual_demografico_br > 0 THEN 
                I.percentual_demografico / BR.percentual_demografico_br
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS risco_relativo_br

INTO temp_CGUSC.fp.indicador_inconsistencia_clinica_detalhado
FROM temp_CGUSC.fp.indicador_inconsistencia_clinica I
INNER JOIN temp_CGUSC.fp.dados_farmacia F 
    ON F.cnpj = I.cnpj
LEFT JOIN temp_CGUSC.fp.indicador_inconsistencia_clinica_uf UF 
    ON CAST(F.uf AS VARCHAR(2)) = UF.uf
CROSS JOIN temp_CGUSC.fp.indicador_inconsistencia_clinica_br BR;

-- Índices Finais
CREATE CLUSTERED INDEX IDX_FinalDemo_CNPJ ON temp_CGUSC.fp.indicador_inconsistencia_clinica_detalhado(cnpj);
CREATE NONCLUSTERED INDEX IDX_FinalDemo_Risco ON temp_CGUSC.fp.indicador_inconsistencia_clinica_detalhado(risco_relativo_uf DESC);
GO

-- Verificação rápida
SELECT TOP 100 * FROM temp_CGUSC.fp.indicador_inconsistencia_clinica_detalhado ORDER BY risco_relativo_uf DESC;

