USE [temp_CGUSC]
GO

-- ============================================================================
-- PASSO 1: PRÉ-CÁLCULO 
-- (Variáveis declaradas apenas neste bloco onde são usadas)
-- ============================================================================
DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim DATE = '2024-12-10';

DROP TABLE IF EXISTS #ConsolidadoPacientes;

SELECT 
    A.cnpj,
    COUNT(DISTINCT A.cpf) AS qtd_pacientes_distintos,
    SUM(A.valor_pago) AS valor_total_periodo,
    -- NOVO: Conta quantos meses distintos houve movimentação
    COUNT(DISTINCT FORMAT(A.data_hora, 'yyyyMM')) AS qtd_meses_ativos
INTO #ConsolidadoPacientes
FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
INNER JOIN temp_CGUSC.dbo.medicamentosPatologiaFP C 
    ON C.codigo_barra = A.codigo_barra
WHERE 
    A.data_hora >= @DataInicio 
    AND A.data_hora <= @DataFim
GROUP BY A.cnpj;

CREATE CLUSTERED INDEX IDX_TempPacientes_CNPJ ON #ConsolidadoPacientes(cnpj);
GO 
-- O comando GO acima obriga o SQL a criar a tabela temporária antes de prosseguir


-- ============================================================================
-- PASSO 2: CÁLCULO BASE POR FARMÁCIA
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.dbo.indicadorReceitaPorPaciente;

SELECT 
    cnpj,
    valor_total_periodo,
    qtd_pacientes_distintos,
    qtd_meses_ativos, 
    
    -- MÉTRICA 1 (LEGADO)
    CAST(
        CASE 
            WHEN qtd_pacientes_distintos > 0 THEN 
                valor_total_periodo / qtd_pacientes_distintos
            ELSE 0 
        END 
    AS DECIMAL(18,2)) AS receita_por_paciente,

    -- MÉTRICA 2 (NOVA - MENSAL)
    CAST(
        CASE 
            WHEN qtd_pacientes_distintos > 0 AND qtd_meses_ativos > 0 THEN 
                (valor_total_periodo / qtd_pacientes_distintos) / qtd_meses_ativos
            ELSE 0 
        END 
    AS DECIMAL(18,2)) AS receita_por_paciente_mensal

INTO temp_CGUSC.dbo.indicadorReceitaPorPaciente
FROM #ConsolidadoPacientes;

CREATE CLUSTERED INDEX IDX_IndRecPac_CNPJ ON temp_CGUSC.dbo.indicadorReceitaPorPaciente(cnpj);

-- Limpeza da temp table (opcional aqui, pois ela morre com a sessão, mas boa prática)
DROP TABLE #ConsolidadoPacientes;
GO
-- O comando GO garante que a tabela 'indicadorReceitaPorPaciente' esteja atualizada com as novas colunas


-- ============================================================================
-- PASSO 3: CÁLCULO DAS MÉDIAS POR ESTADO (UF)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.dbo.indicadorReceitaPorPaciente_UF;

SELECT 
    CAST(F.uf AS VARCHAR(2)) AS uf,
    
    SUM(I.valor_total_periodo) AS total_valor_uf,
    SUM(I.qtd_pacientes_distintos) AS total_pacientes_uf,
    SUM(I.qtd_meses_ativos) AS total_meses_uf, 
    
    -- Média Acumulada
    CAST(
        CASE 
            WHEN SUM(I.qtd_pacientes_distintos) > 0 THEN 
                SUM(I.valor_total_periodo) / SUM(I.qtd_pacientes_distintos)
            ELSE 0 
        END 
    AS DECIMAL(18,2)) AS receita_por_paciente_uf,

    -- Média Mensal (Benchmark)
    CAST(
        AVG(I.receita_por_paciente_mensal)
    AS DECIMAL(18,2)) AS receita_por_paciente_mensal_uf

INTO temp_CGUSC.dbo.indicadorReceitaPorPaciente_UF
FROM temp_CGUSC.dbo.indicadorReceitaPorPaciente I
INNER JOIN temp_CGUSC.dbo.dadosFarmaciasFP F 
    ON F.cnpj = I.cnpj
GROUP BY CAST(F.uf AS VARCHAR(2));

CREATE CLUSTERED INDEX IDX_IndRecPacUF_UF ON temp_CGUSC.dbo.indicadorReceitaPorPaciente_UF(uf);
GO


-- ============================================================================
-- PASSO 4: CÁLCULO DA MÉDIA NACIONAL (BRASIL)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.dbo.indicadorReceitaPorPaciente_BR;

SELECT 
    'BR' AS pais,
    SUM(valor_total_periodo) AS total_valor_br,
    SUM(qtd_pacientes_distintos) AS total_pacientes_br,
    
    -- Média Nacional Acumulada
    CAST(
        CASE 
            WHEN SUM(qtd_pacientes_distintos) > 0 THEN 
                SUM(valor_total_periodo) / SUM(qtd_pacientes_distintos)
            ELSE 0 
        END 
    AS DECIMAL(18,2)) AS receita_por_paciente_br,

    -- Média Nacional Mensal
    CAST(
        AVG(receita_por_paciente_mensal)
    AS DECIMAL(18,2)) AS receita_por_paciente_mensal_br

INTO temp_CGUSC.dbo.indicadorReceitaPorPaciente_BR
FROM temp_CGUSC.dbo.indicadorReceitaPorPaciente;
GO


-- ============================================================================
-- PASSO 5: TABELA CONSOLIDADA FINAL
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.dbo.indicadorReceitaPorPaciente_Completo;

SELECT 
    I.cnpj,
    F.razaoSocial,
    F.municipio,
    CAST(F.uf AS VARCHAR(2)) AS uf,
    
    I.valor_total_periodo,
    I.qtd_pacientes_distintos,
    I.qtd_meses_ativos, 
    I.receita_por_paciente,
    I.receita_por_paciente_mensal,
    
    ISNULL(UF.receita_por_paciente_mensal_uf, 0) AS media_mensal_estado,
    BR.receita_por_paciente_mensal_br AS media_mensal_pais,
    
    -- RISCO RELATIVO
    CAST(
        CASE 
            WHEN UF.receita_por_paciente_mensal_uf > 0 THEN 
                I.receita_por_paciente_mensal / UF.receita_por_paciente_mensal_uf
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS risco_relativo_uf,

    CAST(
        CASE 
            WHEN BR.receita_por_paciente_mensal_br > 0 THEN 
                I.receita_por_paciente_mensal / BR.receita_por_paciente_mensal_br
            ELSE 0 
        END 
    AS DECIMAL(18,4)) AS risco_relativo_br

INTO temp_CGUSC.dbo.indicadorReceitaPorPaciente_Completo
FROM temp_CGUSC.dbo.indicadorReceitaPorPaciente I
INNER JOIN temp_CGUSC.dbo.dadosFarmaciasFP F 
    ON F.cnpj = I.cnpj
LEFT JOIN temp_CGUSC.dbo.indicadorReceitaPorPaciente_UF UF 
    ON CAST(F.uf AS VARCHAR(2)) = UF.uf
CROSS JOIN temp_CGUSC.dbo.indicadorReceitaPorPaciente_BR BR;

CREATE CLUSTERED INDEX IDX_FinalRecPac_CNPJ ON temp_CGUSC.dbo.indicadorReceitaPorPaciente_Completo(cnpj);
CREATE NONCLUSTERED INDEX IDX_FinalRecPac_Risco ON temp_CGUSC.dbo.indicadorReceitaPorPaciente_Completo(risco_relativo_uf DESC);
GO

-- Verificação final
SELECT TOP 100 * FROM temp_CGUSC.dbo.indicadorReceitaPorPaciente_Completo ORDER BY risco_relativo_uf DESC;