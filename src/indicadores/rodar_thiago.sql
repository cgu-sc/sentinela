
/*
================================================================================
Script: Análise de Vendas - Farmácia Popular (Projeto Sentinela)
Descrição: Identifica irregularidades em vendas e calcula multas
Período: Julho/2015 a Dezembro/2024
================================================================================
*/

-- ============================================================================
-- PARÂMETROS GLOBAIS
-- ============================================================================
DECLARE @data_inicial DATE = '2021-01-01';
DECLARE @data_final DATE = '2024-12-10';

PRINT '================================';
PRINT 'Iniciando processamento...';
PRINT 'Período: ' + CONVERT(VARCHAR, @data_inicial, 103) + ' a ' + CONVERT(VARCHAR, @data_final, 103);
PRINT '================================';

-- ============================================================================
-- 1. VENDAS PARA FALECIDOS
-- ============================================================================
PRINT 'Processando vendas para falecidos...';

DROP TABLE IF EXISTS #vendas_falecidos;

SELECT 
    num_autorizacao,
    a.cpf,
    a.cnpj,
    data_hora,
    a.codigo_barra,
    qnt_autorizada,
    valor_pago,
    B.dt_obito
INTO #vendas_falecidos
FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
LEFT JOIN temp_CGUSC.fp.obitos_unificada B ON B.cpf = A.CPF
INNER JOIN temp_CGUSC.fp.medicamentos_patologia C ON C.codigo_barra = A.codigo_barra
INNER JOIN temp_CGUSC.fp.processamento D ON D.cnpj = A.cnpj
WHERE a.data_hora >= @data_inicial
    AND a.data_hora <= @data_final
    AND A.data_hora > B.dt_obito
ORDER BY A.cnpj, A.cpf, A.codigo_barra;

-- ============================================================================
-- 2. TOTAL DE VENDAS POR CNPJ
-- ============================================================================
PRINT 'Calculando total de vendas por estabelecimento...';

DROP TABLE IF EXISTS #cnpj_falecidos;

SELECT DISTINCT cnpj
INTO #cnpj_falecidos
FROM #vendas_falecidos;

DROP TABLE IF EXISTS #vendas_total;

SELECT 
    a.cnpj,
    SUM(valor_pago) AS valor_total_vendas
INTO #vendas_total
FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
INNER JOIN temp_CGUSC.fp.medicamentos_patologia C ON C.codigo_barra = A.codigo_barra
INNER JOIN #cnpj_falecidos D ON D.cnpj = A.cnpj
WHERE a.data_hora >= @data_inicial
    AND a.data_hora <= @data_final
GROUP BY A.cnpj;

-- ============================================================================
-- 3. VENDAS PARA FALECIDOS - VISÃO GERENCIAL
-- ============================================================================
PRINT 'Gerando visão gerencial de vendas para falecidos...';

DROP TABLE IF EXISTS #vendas_falecidos_gerencial;

SELECT 
    A.cnpj,
    SUM(A.valor_pago) AS vendas_falecidos,
    SUM(A.valor_pago) * 1.0 / B.valor_total_vendas AS percentual_falecidos
INTO #vendas_falecidos_gerencial
FROM #vendas_falecidos A
INNER JOIN #vendas_total B ON B.cnpj = A.cnpj
GROUP BY A.cnpj, B.valor_total_vendas;

-- ============================================================================
-- 4. NÚMERO DE AUTORIZAÇÕES POR CNPJ
-- ============================================================================
PRINT 'Contabilizando autorizações...';

DROP TABLE IF EXISTS #autorizacoes;

SELECT 
    A.cnpj,
    COUNT(DISTINCT A.num_autorizacao) AS total_autorizacoes
INTO #autorizacoes 
FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 AS A
INNER JOIN temp_CGUSC.fp.medicamentos_patologia AS C ON C.codigo_barra = A.codigo_barra
WHERE A.data_hora >= @data_inicial 
    AND A.data_hora <= @data_final
GROUP BY A.cnpj
OPTION (MAXDOP 8);

-- ============================================================================
-- 5. MOVIMENTAÇÃO GERENCIAL - AGREGAÇÕES
-- ============================================================================
PRINT 'Processando movimentação gerencial...';

-- 5.1 - Agregação inicial
DROP TABLE IF EXISTS #movimentacao_gerencial_temp;

SELECT 
    B.id,
    B.cnpj,
    B.razao_social,
    SUM(A.qnt_vendas) AS qnt_vendas,
    SUM(A.qnt_vendas_sem_comprovacao) AS qnt_vendas_sem_comprovacao,
    SUM(A.valor_vendas) AS valor_vendas,
    SUM(A.valor_sem_comprovacao) AS valor_sem_comprovacao
INTO #movimentacao_gerencial_temp
FROM temp_CGUSC.fp.movimentacao_mensal_gtin A
INNER JOIN temp_CGUSC.fp.processamento B ON B.id = A.id_processamento
where year(periodo) in (2021,2022,2023,2024) 
GROUP BY B.cnpj, B.razao_social, B.id;

-- 5.2 - Adiciona dados geográficos e percentuais
DROP TABLE IF EXISTS #movimentacao_gerencial_temp2;

SELECT 
    A.id,
    A.cnpj,
    A.razao_social,
    A.qnt_vendas,
    A.qnt_vendas_sem_comprovacao,
    A.valor_vendas,
    A.valor_sem_comprovacao,
    B.codibge,
    B.municipio,
    B.uf,
    B.CodPorteEmpresa,
    A.valor_sem_comprovacao * 1.0 / A.valor_vendas AS percentual_sem_comprovacao
INTO #movimentacao_gerencial_temp2
FROM #movimentacao_gerencial_temp A
LEFT JOIN temp_CGUSC.fp.dados_farmacia B ON B.cnpj = A.cnpj;

-- 5.3 - Calcula estabelecimentos por município
DROP TABLE IF EXISTS #estabelecimentos_municipio;

SELECT 
    codibge,
    COUNT(DISTINCT cnpj) AS num_estabelecimentos
INTO #estabelecimentos_municipio
FROM #movimentacao_gerencial_temp2
WHERE codibge IS NOT NULL
GROUP BY codibge;

-- 5.4 - Calcula meses de movimentação por processamento
DROP TABLE IF EXISTS #meses_movimentacao;

SELECT 
    id_processamento,
    COUNT(DISTINCT periodo) AS num_meses
INTO #meses_movimentacao
FROM temp_CGUSC.fp.movimentacao_mensal_gtin
GROUP BY id_processamento;

-- 5.5 - Adiciona contadores de estabelecimentos e meses
DROP TABLE IF EXISTS #movimentacao_gerencial_temp3;

SELECT 
    A.id,
    A.uf,
    A.municipio,
    A.cnpj,
    A.razao_social,
    A.qnt_vendas,
    A.qnt_vendas_sem_comprovacao,
    A.valor_vendas,
    A.valor_sem_comprovacao,
    A.codibge,
    A.percentual_sem_comprovacao,
    A.CodPorteEmpresa,
    ISNULL(E.num_estabelecimentos, 0) AS num_estabelecimentos_mesmo_municipio,
    ISNULL(M.num_meses, 0) AS num_meses_movimentacao
INTO #movimentacao_gerencial_temp3
FROM #movimentacao_gerencial_temp2 A
LEFT JOIN #estabelecimentos_municipio E ON E.codibge = A.codibge
LEFT JOIN #meses_movimentacao M ON M.id_processamento = A.id;

-- 5.6 - Consolidação final da movimentação
DROP TABLE IF EXISTS #movimentacao_gerencial;

SELECT 
    uf,
    municipio,
    cnpj,
    razao_social,
    MAX(qnt_vendas) AS qnt_vendas,
    MAX(qnt_vendas_sem_comprovacao) AS qnt_vendas_sem_comprovacao,
    MAX(valor_vendas) AS valor_vendas,
    MAX(valor_sem_comprovacao) AS valor_sem_comprovacao,
    codibge,
    MAX(percentual_sem_comprovacao) AS percentual_sem_comprovacao,
    MAX(CodPorteEmpresa) AS CodPorteEmpresa,
    MAX(num_estabelecimentos_mesmo_municipio) AS num_estabelecimentos_mesmo_municipio,
    MAX(num_meses_movimentacao) AS num_meses_movimentacao
INTO #movimentacao_gerencial
FROM #movimentacao_gerencial_temp3
GROUP BY uf, municipio, cnpj, razao_social, codibge;

-- ============================================================================
-- 6. CÁLCULO DE MULTA (10% DOS ÚLTIMOS 3 MESES)
-- ============================================================================
PRINT 'Calculando valores de multa...';

-- 6.1 - Identifica o período final de cada estabelecimento
DROP TABLE IF EXISTS #periodo_final_processamento;

SELECT 
    id_processamento,
    MAX(periodo) AS periodo_final
INTO #periodo_final_processamento
FROM temp_CGUSC.fp.movimentacao_mensal_gtin
GROUP BY id_processamento;

-- 6.2 - Calcula período inicial (3 meses antes)
DROP TABLE IF EXISTS #tres_ultimos_meses;

SELECT 
    id_processamento,
    DATEADD(MONTH, -3, periodo_final) AS periodo_inicial,
    periodo_final
INTO #tres_ultimos_meses
FROM #periodo_final_processamento;

-- 6.3 - Vendas nos últimos 3 meses
DROP TABLE IF EXISTS #vendas_ultimos_meses;

SELECT 
    C.cnpj,
    A.valor_vendas
INTO #vendas_ultimos_meses
FROM temp_CGUSC.fp.movimentacao_mensal_gtin A
INNER JOIN #tres_ultimos_meses B ON B.id_processamento = A.id_processamento
INNER JOIN temp_CGUSC.fp.processamento C ON C.id = A.id_processamento
WHERE A.periodo >= B.periodo_inicial
    AND A.periodo <= B.periodo_final;

-- 6.4 - Calcula multa de 10%
DROP TABLE IF EXISTS #valor_multa;

SELECT 
    cnpj,
    SUM(valor_vendas) AS valor_vendas_ultimos_tres_meses,
    SUM(valor_vendas) * 0.1 AS valor_multa
INTO #valor_multa
FROM #vendas_ultimos_meses
GROUP BY cnpj;

-- ============================================================================
-- 7. RESULTADO FINAL
-- ============================================================================
PRINT 'Gerando resultado final...';

DROP TABLE IF EXISTS temp_CGUSC.fp.resultado_Sentinela_2021_2024_thiago;

SELECT DISTINCT
    A.uf,
    F.id_ibge7,
    A.municipio,
    F.nu_populacao,
    A.cnpj,
    A.razao_social,
    A.qnt_vendas AS qnt_medicamentos_vendidos,
    A.qnt_vendas_sem_comprovacao AS qnt_medicamentos_vendidos_sem_comprovacao,
    H.total_autorizacoes AS nu_autorizacoes,
    A.valor_vendas,
    A.valor_sem_comprovacao,
    A.percentual_sem_comprovacao,
    A.num_estabelecimentos_mesmo_municipio,
    A.num_meses_movimentacao,
    A.CodPorteEmpresa,
    G.valor_multa,
    ISNULL(E.percentual_falecidos, 0) AS percentual_falecidos,
    ISNULL(E.vendas_falecidos, 0) AS vendas_falecidos
INTO temp_CGUSC.fp.resultado_Sentinela_2021_2024_thiago
FROM #movimentacao_gerencial A
LEFT JOIN #vendas_falecidos_gerencial E ON E.cnpj = A.cnpj
INNER JOIN temp_CGUSC.sus.tb_ibge F ON F.id_ibge7 = A.codibge
INNER JOIN #valor_multa G ON G.cnpj = A.cnpj
INNER JOIN #autorizacoes H ON H.cnpj = A.cnpj;





select * from temp_CGUSC.fp.resultado_Sentinela_2021_2024_thiago







select top 1000 * from temp_CGUSC.fp.resultado_Sentinela_2021_2024_thiago where cnpj='10411527000162';
select top 1000 * from temp_CGUSC.fp.resultado_sentinela_2015_2024 where cnpj='10411527000162';



