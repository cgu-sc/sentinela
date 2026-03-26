

USE temp_CGUSC;
GO

-- 1. LIMPEZA TOTAL (Apaga a tabela se ela existir)
IF OBJECT_ID('fp.movimentacao_mensal_cnpj', 'U') IS NOT NULL 
    DROP TABLE fp.movimentacao_mensal_cnpj;
GO

-- 2. CRIAÇÃO DA TABELA DE AGREGAÇÃO (Denormalizada com CNPJ + UF + Geo + Quantidades)
CREATE TABLE fp.movimentacao_mensal_cnpj (
    id_processamento INT NOT NULL,
    cnpj VARCHAR(14) NOT NULL,          -- Incluído para evitar JOINs pesados no Gráfico
    uf VARCHAR(2) NULL,                  -- Denormalizado para filtros por UF sem JOIN
    no_regiao_saude VARCHAR(100) NULL,   -- Denormalizado para filtros por Região de Saúde sem JOIN
    no_municipio VARCHAR(100) NULL,      -- Denormalizado para filtros por Município sem JOIN
    periodo DATE NOT NULL,
    total_vendas DECIMAL(18, 2),
    total_sem_comprovacao DECIMAL(18, 2),
    total_qnt_vendas INT,               -- Qtde total de medicamentos vendidos no mês
    total_qnt_sem_comprovacao INT       -- Qtde de medicamentos sem comprovação no mês
);
GO

-- 3. CARGA INICIAL DOS DADOS (Enriquecendo com CNPJ, UF, Região de Saúde, Município e Quantidades)
INSERT INTO fp.movimentacao_mensal_cnpj (
    id_processamento, cnpj, uf, no_regiao_saude, no_municipio, periodo,
    total_vendas, total_sem_comprovacao,
    total_qnt_vendas, total_qnt_sem_comprovacao
)
SELECT
    m.id_processamento,
    p.cnpj,
    r.uf,
    g.no_regiao_saude,
    g.no_municipio,
    m.periodo,
    SUM(m.valor_vendas),
    SUM(m.valor_sem_comprovacao),
    SUM(m.qnt_vendas),
    SUM(m.qnt_vendas_sem_comprovacao)
FROM fp.movimentacao_mensal_gtin m
INNER JOIN fp.processamento p ON p.id = m.id_processamento
LEFT JOIN fp.resultado_sentinela r ON r.cnpj = p.cnpj
LEFT JOIN fp.dados_ibge g ON g.id_ibge7 = r.id_ibge7
GROUP BY m.id_processamento, p.cnpj, r.uf, g.no_regiao_saude, g.no_municipio, m.periodo;
GO

-- 4. ÍNDICE CLUSTERIZADO (Acesso principal por Período + CNPJ)
-- Cobre: fator-risco, KPIs globais por período — range scan eficiente
CREATE CLUSTERED INDEX IX_mov_cnpj_periodo_cnpj
ON fp.movimentacao_mensal_cnpj (periodo, cnpj);
GO

-- 5. ÍNDICE NÃO-CLUSTERIZADO (Período + UF com colunas cobertas)
-- Cobre: ranking UF por período (WHERE periodo BETWEEN ... GROUP BY uf)
CREATE NONCLUSTERED INDEX IX_mov_cnpj_periodo_uf
ON fp.movimentacao_mensal_cnpj (periodo, uf)
INCLUDE (cnpj, total_vendas, total_sem_comprovacao, total_qnt_vendas, total_qnt_sem_comprovacao);
GO

-- 6. ÍNDICE NÃO-CLUSTERIZADO (UF + Período)
-- Cobre: filtros por UF específica + período
CREATE NONCLUSTERED INDEX IX_mov_cnpj_uf_periodo
ON fp.movimentacao_mensal_cnpj (uf, periodo)
INCLUDE (cnpj, total_vendas, total_sem_comprovacao, total_qnt_vendas, total_qnt_sem_comprovacao);
GO

-- 7. ÍNDICE NÃO-CLUSTERIZADO (Região de Saúde + Período)
-- Cobre: filtros por Região de Saúde específica + período
CREATE NONCLUSTERED INDEX IX_mov_cnpj_regiao_periodo
ON fp.movimentacao_mensal_cnpj (no_regiao_saude, periodo)
INCLUDE (cnpj, uf, total_vendas, total_sem_comprovacao, total_qnt_vendas, total_qnt_sem_comprovacao);
GO

-- 8. ÍNDICE NÃO-CLUSTERIZADO (Município + Período)
-- Cobre: filtros por Município específico + período
CREATE NONCLUSTERED INDEX IX_mov_cnpj_municipio_periodo
ON fp.movimentacao_mensal_cnpj (no_municipio, periodo)
INCLUDE (cnpj, uf, total_vendas, total_sem_comprovacao, total_qnt_vendas, total_qnt_sem_comprovacao);
GO

-- 9. COLUMNSTORE INDEX (O maior ganho de performance para queries analíticas)
-- Para SUMs, COUNTs e GROUP BYs em grandes volumes, pode ser 10x mais rápido
-- que índices B-tree tradicionais. O SQL Server usa compressão por coluna e
-- processamento em batch — ideal para o padrão OLAP do Sentinela.
CREATE NONCLUSTERED COLUMNSTORE INDEX IX_mov_cnpj_columnstore
ON fp.movimentacao_mensal_cnpj (
    periodo,
    uf,
    no_regiao_saude,
    no_municipio,
    cnpj,
    total_vendas,
    total_sem_comprovacao,
    total_qnt_vendas,
    total_qnt_sem_comprovacao
);
GO




USE temp_CGUSC;
GO

-- 10. PERFIL CONSOLIDADO (Dicionário Master do Estabelecimento)
-- Tabela para enriquecimento de filtros e flags por CNPJ no Dashboard.

-- Identifica dinamicamente qual é o último mês disponível nos dados de vendas
DECLARE @MaxPeriodo DATE = (SELECT MAX(periodo) FROM fp.movimentacao_mensal_cnpj);

DROP TABLE IF EXISTS fp.perfil_consolidado_estabelecimento;

SELECT 
    DF.cnpj,
    DF.razaoSocial               AS razao_social,
    DF.uf,
    DF.municipio,
    DF.ds_porte_empresa           AS porte_empresa,
    DF.outrasSociedades           AS flag_outras_sociedades,
    DF.situacaoReceita            AS situacao_rf,
    DF.dataSituacaoCadastral      AS data_situacao_rf,
    DF.data_processamento         AS data_ultimo_processamento,
    
    -- LÓGICA CONEXÃO MS (Ativa se vendeu nos últimos 30 dias em relação ao limite da base)
    CASE 
        WHEN DF.dataFinalDadosMovimentacao >= DATEADD(DAY, -30, @MaxPeriodo) 
        THEN 'Ativa' ELSE 'Inativa' 
    END AS conexao_ms

INTO fp.perfil_consolidado_estabelecimento
FROM fp.dados_farmacia DF
INNER JOIN (SELECT DISTINCT cnpj FROM fp.movimentacao_mensal_cnpj) M ON M.cnpj = DF.cnpj;

-- Criar índice para performance de JOIN instantâneo no Polars
CREATE UNIQUE CLUSTERED INDEX IX_perfil_cnpj ON fp.perfil_consolidado_estabelecimento (cnpj);
GO




			   
--**********************************************************************************************************
-- "Numero de Autorizacoes".
--***********************************************************************************************************


DROP TABLE IF EXISTS #autorizacoes;

SELECT 
    A.cnpj,
    COUNT(DISTINCT A.num_autorizacao) AS total_autorizacoes
INTO #autorizacoes 
FROM db_farmaciapopular.DBO.relatorio_movimentacao_2015_2024 AS A
INNER JOIN temp_CGUSC.dbo.medicamentosPatologiaFP AS C 
    ON C.codigo_barra = A.codigo_barra
WHERE A.data_hora >= '2015-07-01' AND A.data_hora <= '2024-12-10'
GROUP BY A.cnpj
OPTION (MAXDOP 8); -- Força paralelismo se o servidor permitir


-----------------------------------------------------------------------------------------------------------------------
-- Resultados
---------------------------------------------------------------------------------------------------------------------------------------


DROP TABLE

IF EXISTS #movimentacao_gerencial_temp
	SELECT distinct B.id
		--,B.uf
		--,B.municipio
		,B.cnpj
		,B.razao_social
		,sum(A.qnt_vendas) AS qnt_vendas
		,sum(A.qnt_vendas_sem_comprovacao) AS qnt_vendas_sem_comprovacao
		,sum(A.valor_vendas) AS valor_vendas
		,sum(valor_sem_comprovacao) AS valor_sem_comprovacao
	INTO #movimentacao_gerencial_temp
	FROM temp_CGUSC.fp.movimentacao_mensal_gtin A
	INNER JOIN temp_CGUSC.dbo.processamentosFP B
		ON B.id = A.id_processamento
	GROUP BY B.cnpj
		,B.razao_social
		--,B.uf
		--,B.municipio
		,B.id
		

DROP TABLE

IF EXISTS #movimentacao_gerencial_temp2
	SELECT A.*
		,B.codibge
		,B.municipio
		,B.uf
		,A.valor_sem_comprovacao / A.valor_vendas AS percentual_sem_comprovacao
		,B.CodPorteEmpresa
	INTO #movimentacao_gerencial_temp2
	FROM #movimentacao_gerencial_temp A
	LEFT JOIN temp_CGUSC.fp.dados_farmacia B
		ON B.cnpj = A.cnpj



DROP TABLE

IF EXISTS #movimentacao_gerencial_temp3
	SELECT A.id
		,A.uf
		,A.municipio
		,A.cnpj
		,A.razao_social
		,A.qnt_vendas
		,A.qnt_vendas_sem_comprovacao
		,A.valor_vendas
		,A.valor_sem_comprovacao
		,A.codibge
		,A.percentual_sem_comprovacao
		,A.CodPorteEmpresa
		,(
			select count(*) from(
   			                      SELECT C.cnpj,codibge FROM #movimentacao_gerencial_temp2 C group by C.CNPJ,C.codibge 
			                     ) B
			WHERE A.codibge = B.codibge
			) AS num_estabelecimentos_mesmo_municipio
		,(
			SELECT count(*)
			FROM (
				SELECT periodo
				FROM temp_CGUSC.fp.movimentacao_mensal_gtin
				WHERE id_processamento = A.id
				GROUP BY periodo
				) AS t
			) AS num_meses_movimentacao
	INTO #movimentacao_gerencial_temp3
	FROM #movimentacao_gerencial_temp2 A
	GROUP BY A.uf
		,A.municipio
		,A.cnpj
		,A.razao_social
		,A.qnt_vendas
		,A.qnt_vendas_sem_comprovacao
		,A.valor_vendas
		,A.valor_sem_comprovacao
		,A.codibge
		,A.percentual_sem_comprovacao
		,A.CodPorteEmpresa
		,A.id




DROP TABLE

IF EXISTS #movimentacao_gerencial
	SELECT A.uf
		,A.municipio
		,A.cnpj
		,A.razao_social
		,A.qnt_vendas
		,A.qnt_vendas_sem_comprovacao
		,A.valor_vendas
		,A.valor_sem_comprovacao
		,A.codibge
		,A.percentual_sem_comprovacao
		,A.CodPorteEmpresa
		,A.num_estabelecimentos_mesmo_municipio
		,A.num_meses_movimentacao
	INTO #movimentacao_gerencial
	FROM #movimentacao_gerencial_temp3 A
	GROUP BY A.uf
		,A.municipio
		,A.cnpj
		,A.razao_social
		,A.qnt_vendas
		,A.qnt_vendas_sem_comprovacao
		,A.valor_vendas
		,A.valor_sem_comprovacao
		,A.codibge
		,A.percentual_sem_comprovacao
		,A.CodPorteEmpresa
		,num_estabelecimentos_mesmo_municipio
		,num_meses_movimentacao




-- Calcular o valor da Multa
DROP TABLE

IF EXISTS #tres_ultimos_meses
	SELECT DATEADD(month, - 3, t.periodo_final) AS periodo_inicial
		,t.*
	INTO #tres_ultimos_meses
	FROM (
		SELECT max(periodo) AS periodo_final
			,id_processamento
		FROM temp_CGUSC.fp.movimentacao_mensal_gtin
		GROUP BY id_processamento
		) t

DROP TABLE

IF EXISTS #valor_multa
	SELECT cnpj
		,sum(valor_vendas) AS valor_vendas_ultimos_tres_meses
		,sum(valor_vendas) * 0.1 AS valor_multa
	INTO #valor_multa
	FROM temp_CGUSC.fp.movimentacao_mensal_gtin A
	LEFT JOIN #tres_ultimos_meses B
		ON B.id_processamento = A.id_processamento
	LEFT JOIN temp_CGUSC.dbo.processamentosFP C
		ON C.id = A.id_processamento
	WHERE A.periodo >= B.periodo_inicial
		AND A.periodo <= B.periodo_final
	GROUP BY C.cnpj







-- ============================================================================
-- 7. RESULTADO FINAL CONSOLIDADO (COM RISCO UF E BR)
-- ============================================================================
PRINT 'Gerando resultado final enriquecido (UF e Brasil)...';

DROP TABLE IF EXISTS temp_CGUSC.dbo.resultado_Sentinela_2015_2024;

SELECT DISTINCT 
    A.uf,
    F.id_ibge7,
    A.municipio,
    F.nu_populacao,
    A.cnpj,
    A.razao_social,
    
    -- DADOS BÁSICOS DE MOVIMENTAÇÃO
    A.qnt_vendas AS qnt_medicamentos_vendidos,
    A.qnt_vendas_sem_comprovacao AS qnt_medicamentos_vendidos_sem_comprovacao,
    h.total_autorizacoes AS nu_autorizacoes,
    A.valor_vendas,
    A.valor_sem_comprovacao,
    A.percentual_sem_comprovacao,
    A.num_estabelecimentos_mesmo_municipio,
    A.num_meses_movimentacao,
    A.CodPorteEmpresa,
    G.valor_multa,
    
    -- DADOS DE FALECIDOS (ORIGINAIS)
    ISNULL(E.percentual_falecidos, 0) AS percentual_falecidos_gerencial,
    ISNULL(E.vendas_falecidos, 0) AS valor_vendas_falecidos,

    -- ========================================================================
    -- NOVOS INDICADORES (RISCO & INTELIGÊNCIA)
    -- Adicionado sufixo _uf e _br para clareza
    -- ========================================================================
    
    -- 1. SCORE GERAL
    ISNULL(MAX(RISCO.SCORE_GERAL_RISCO), 0) AS SCORE_GERAL_RISCO,

    -- 2. FALECIDOS (Completo)
    ISNULL(MAX(I_FALECIDOS.risco_relativo_uf), 0) AS rr_falecidos_uf,
    ISNULL(MAX(I_FALECIDOS.risco_relativo_br), 0) AS rr_falecidos_br,

    -- 3. PACIENTES FANTASMA
    ISNULL(MAX(I_FANTASMA.percentual_fantasma), 0) AS pct_pacientes_fantasma,
    ISNULL(MAX(I_FANTASMA.risco_relativo_uf), 0) AS rr_pacientes_fantasma_uf,
    ISNULL(MAX(I_FANTASMA.risco_relativo_br), 0) AS rr_pacientes_fantasma_br,
    
    -- 4. INCONSISTÊNCIA CLÍNICA
    ISNULL(MAX(I_CLINICA.percentual_demografico), 0) AS pct_inconsistencia_clinica,
    ISNULL(MAX(I_CLINICA.risco_relativo_uf), 0) AS rr_inconsistencia_clinica_uf,
    ISNULL(MAX(I_CLINICA.risco_relativo_br), 0) AS rr_inconsistencia_clinica_br,

    -- 5. TETO MÁXIMO
    ISNULL(MAX(I_TETO.percentual_teto), 0) AS pct_teto_maximo,
    ISNULL(MAX(I_TETO.risco_relativo_uf), 0) AS rr_teto_maximo_uf,
    ISNULL(MAX(I_TETO.risco_relativo_br), 0) AS rr_teto_maximo_br,
    
    -- 6. POLIMEDICAMENTO (CESTA CHEIA)
    ISNULL(MAX(I_POLI.percentual_polimedicamento), 0) AS pct_polimedicamento,
    ISNULL(MAX(I_POLI.risco_relativo_uf), 0) AS rr_polimedicamento_uf,
    ISNULL(MAX(I_POLI.risco_relativo_br), 0) AS rr_polimedicamento_br,
    
    -- 7. MÉDIA ITENS
    ISNULL(MAX(I_MEDIA_ITENS.media_itens_autorizacao), 0) AS val_media_itens,
    ISNULL(MAX(I_MEDIA_ITENS.risco_relativo_uf), 0) AS rr_media_itens_uf,
    ISNULL(MAX(I_MEDIA_ITENS.risco_relativo_br), 0) AS rr_media_itens_br,

    -- 8. VENDAS CONSECUTIVAS (ROBÔS)
    ISNULL(MAX(I_CONSEC.percentual_vendas_consecutivas), 0) AS pct_vendas_rapidas_60s,
    ISNULL(MAX(I_CONSEC.risco_relativo_uf), 0) AS rr_vendas_rapidas_uf,
    ISNULL(MAX(I_CONSEC.risco_relativo_br), 0) AS rr_vendas_rapidas_br,

    -- 9. HORÁRIO ATÍPICO
    ISNULL(MAX(I_HORA.percentual_madrugada), 0) AS pct_horario_atipico,
    ISNULL(MAX(I_HORA.risco_relativo_uf), 0) AS rr_horario_atipico_uf,
    ISNULL(MAX(I_HORA.risco_relativo_br), 0) AS rr_horario_atipico_br,
    
    -- 10. CONCENTRAÇÃO EM DIAS DE PICO
    ISNULL(MAX(I_PICO.percentual_concentracao_pico), 0) AS pct_concentracao_pico,
    ISNULL(MAX(I_PICO.risco_relativo_uf), 0) AS rr_concentracao_pico_uf,
    ISNULL(MAX(I_PICO.risco_relativo_br), 0) AS rr_concentracao_pico_br,

    -- 11. TICKET MÉDIO
    ISNULL(MAX(I_TICKET.valor_ticket_medio), 0) AS val_ticket_medio,
    ISNULL(MAX(I_TICKET.risco_relativo_uf), 0) AS rr_ticket_medio_uf,
    ISNULL(MAX(I_TICKET.risco_relativo_br), 0) AS rr_ticket_medio_br,
    
    -- 12. RECEITA POR PACIENTE
    ISNULL(MAX(I_RECPAC.receita_por_paciente), 0) AS val_receita_por_paciente,
    ISNULL(MAX(I_RECPAC.risco_relativo_uf), 0) AS rr_receita_por_paciente_uf,
    ISNULL(MAX(I_RECPAC.risco_relativo_br), 0) AS rr_receita_por_paciente_br,
    
    -- 13. VENDA PER CAPITA
    ISNULL(MAX(I_PERCAPITA.valor_per_capita), 0) AS val_venda_per_capita_municipio,
    ISNULL(MAX(I_PERCAPITA.risco_relativo_uf), 0) AS rr_venda_per_capita_uf,
    ISNULL(MAX(I_PERCAPITA.risco_relativo_br), 0) AS rr_venda_per_capita_br,
    
    -- 14. ALTO CUSTO
    ISNULL(MAX(I_ALTO.percentual_alto_custo), 0) AS pct_alto_custo,
    ISNULL(MAX(I_ALTO.risco_relativo_uf), 0) AS rr_alto_custo_uf,
    ISNULL(MAX(I_ALTO.risco_relativo_br), 0) AS rr_alto_custo_br


INTO temp_CGUSC.dbo.resultado_Sentinela_2015_2024
FROM #movimentacao_gerencial A

-- JOINS ORIGINAIS
LEFT JOIN #vendas_falecidos_gerencial E ON E.cnpj = A.cnpj
INNER JOIN temp_CGUSC.sus.tb_ibge F ON F.id_ibge7 = A.codibge
INNER JOIN #valor_multa G ON G.cnpj = A.cnpj
INNER JOIN #autorizacoes h ON h.cnpj = A.cnpj

-- JOINS DOS NOVOS INDICADORES (Tabelas Permanentes)
LEFT JOIN temp_CGUSC.dbo.Matriz_Risco_Final RISCO ON RISCO.cnpj = A.cnpj
LEFT JOIN temp_CGUSC.dbo.indicadorFalecidos_Completo I_FALECIDOS ON I_FALECIDOS.cnpj = A.cnpj
LEFT JOIN temp_CGUSC.dbo.indicadorPacientesFantasma_Completo I_FANTASMA ON I_FANTASMA.cnpj = A.cnpj
LEFT JOIN temp_CGUSC.dbo.indicadorInconsistenciaClinica_Completo I_CLINICA ON I_CLINICA.cnpj = A.cnpj
LEFT JOIN temp_CGUSC.dbo.indicadorTeto_Completo I_TETO ON I_TETO.cnpj = A.cnpj
LEFT JOIN temp_CGUSC.dbo.indicadorPolimedicamento_Completo I_POLI ON I_POLI.cnpj = A.cnpj
LEFT JOIN temp_CGUSC.dbo.indicadorMediaItens_Completo I_MEDIA_ITENS ON I_MEDIA_ITENS.cnpj = A.cnpj
LEFT JOIN temp_CGUSC.dbo.indicadorVendasConsecutivas_Completo I_CONSEC ON I_CONSEC.cnpj = A.cnpj
LEFT JOIN temp_CGUSC.dbo.indicadorHorarioAtipico_Completo I_HORA ON I_HORA.cnpj = A.cnpj
LEFT JOIN temp_CGUSC.dbo.indicadorConcentracaoPico_Completo I_PICO ON I_PICO.cnpj = A.cnpj
LEFT JOIN temp_CGUSC.dbo.indicadorTicketMedio_Completo I_TICKET ON I_TICKET.cnpj = A.cnpj
LEFT JOIN temp_CGUSC.dbo.indicadorReceitaPorPaciente_Completo I_RECPAC ON I_RECPAC.cnpj = A.cnpj
LEFT JOIN temp_CGUSC.dbo.indicadorVendaPerCapita_Completo I_PERCAPITA ON I_PERCAPITA.cnpj = A.cnpj
LEFT JOIN temp_CGUSC.dbo.indicadorAltoCusto_Completo I_ALTO ON I_ALTO.cnpj = A.cnpj

GROUP BY 
    A.uf,
    F.id_ibge7,
    A.municipio,
    F.nu_populacao,
    A.cnpj,
    A.razao_social,
    A.qnt_vendas,
    A.qnt_vendas_sem_comprovacao,
    h.total_autorizacoes,
    A.valor_vendas,
    A.valor_sem_comprovacao,
    A.percentual_sem_comprovacao,
    A.num_estabelecimentos_mesmo_municipio,
    A.num_meses_movimentacao,
    A.CodPorteEmpresa,
    G.valor_multa,
    E.percentual_falecidos,
    E.vendas_falecidos;


SELECT *
FROM temp_CGUSC.dbo.resultado_Sentinela_2021_2024




























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
DECLARE @data_inicial DATE = '2015-07-01';
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
LEFT JOIN temp_CGUSC.dbo.obitos_unificada B ON B.cpf = A.CPF
INNER JOIN temp_CGUSC.dbo.medicamentosPatologiaFP C ON C.codigo_barra = A.codigo_barra
INNER JOIN temp_CGUSC.dbo.processamentosFP D ON D.cnpj = A.cnpj
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
INNER JOIN temp_CGUSC.dbo.medicamentosPatologiaFP C ON C.codigo_barra = A.codigo_barra
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
FROM db_farmaciapopular.DBO.relatorio_movimentacao_2015_2024 AS A
INNER JOIN temp_CGUSC.dbo.medicamentosPatologiaFP AS C ON C.codigo_barra = A.codigo_barra
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
INNER JOIN temp_CGUSC.dbo.processamentosFP B ON B.id = A.id_processamento
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
LEFT JOIN temp_CGUSC.dbo.dadosFarmaciasFP B ON B.cnpj = A.cnpj;

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
INNER JOIN temp_CGUSC.dbo.processamentosFP C ON C.id = A.id_processamento
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

DROP TABLE IF EXISTS temp_CGUSC.dbo.resultado_Sentinela_2015_2024;

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
INTO temp_CGUSC.dbo.resultado_Sentinela_2015_2024
FROM #movimentacao_gerencial A
LEFT JOIN #vendas_falecidos_gerencial E ON E.cnpj = A.cnpj
INNER JOIN temp_CGUSC.sus.tb_ibge F ON F.id_ibge7 = A.codibge
INNER JOIN #valor_multa G ON G.cnpj = A.cnpj
INNER JOIN #autorizacoes H ON H.cnpj = A.cnpj;




-- ============================================================================
-- 7. RESULTADO FINAL CONSOLIDADO (COM RISCO UF E BR)
-- ============================================================================
PRINT 'Gerando resultado final enriquecido (UF e Brasil)...';

DROP TABLE IF EXISTS temp_CGUSC.dbo.resultado_Sentinela_2015_2024;

SELECT DISTINCT 
    A.uf,
    F.id_ibge7,
    A.municipio,
    F.nu_populacao,
    A.cnpj,
    A.razao_social,
    
    -- DADOS BÁSICOS DE MOVIMENTAÇÃO
    A.qnt_vendas AS qnt_medicamentos_vendidos,
    A.qnt_vendas_sem_comprovacao AS qnt_medicamentos_vendidos_sem_comprovacao,
    h.total_autorizacoes AS nu_autorizacoes,
    A.valor_vendas,
    A.valor_sem_comprovacao,
    A.percentual_sem_comprovacao,
    A.num_estabelecimentos_mesmo_municipio,
    A.num_meses_movimentacao,
    A.CodPorteEmpresa,
    G.valor_multa,
    
    -- DADOS DE FALECIDOS (ORIGINAIS)
    ISNULL(E.percentual_falecidos, 0) AS percentual_falecidos_gerencial,
    ISNULL(E.vendas_falecidos, 0) AS valor_vendas_falecidos,

    -- ========================================================================
    -- NOVOS INDICADORES (RISCO & INTELIGÊNCIA)
    -- Adicionado sufixo _uf e _br para clareza
    -- ========================================================================
    
    -- 1. SCORE GERAL
    ISNULL(MAX(RISCO.SCORE_GERAL_RISCO), 0) AS SCORE_GERAL_RISCO,

    -- 2. FALECIDOS (Completo)
    ISNULL(MAX(I_FALECIDOS.risco_relativo_uf), 0) AS rr_falecidos_uf,
    ISNULL(MAX(I_FALECIDOS.risco_relativo_br), 0) AS rr_falecidos_br,

    -- 3. PACIENTES FANTASMA
    ISNULL(MAX(I_FANTASMA.percentual_fantasma), 0) AS pct_pacientes_fantasma,
    ISNULL(MAX(I_FANTASMA.risco_relativo_uf), 0) AS rr_pacientes_fantasma_uf,
    ISNULL(MAX(I_FANTASMA.risco_relativo_br), 0) AS rr_pacientes_fantasma_br,
    
    -- 4. INCONSISTÊNCIA CLÍNICA
    ISNULL(MAX(I_CLINICA.percentual_demografico), 0) AS pct_inconsistencia_clinica,
    ISNULL(MAX(I_CLINICA.risco_relativo_uf), 0) AS rr_inconsistencia_clinica_uf,
    ISNULL(MAX(I_CLINICA.risco_relativo_br), 0) AS rr_inconsistencia_clinica_br,

    -- 5. TETO MÁXIMO
    ISNULL(MAX(I_TETO.percentual_teto), 0) AS pct_teto_maximo,
    ISNULL(MAX(I_TETO.risco_relativo_uf), 0) AS rr_teto_maximo_uf,
    ISNULL(MAX(I_TETO.risco_relativo_br), 0) AS rr_teto_maximo_br,
    
    -- 6. POLIMEDICAMENTO (CESTA CHEIA)
    ISNULL(MAX(I_POLI.percentual_polimedicamento), 0) AS pct_polimedicamento,
    ISNULL(MAX(I_POLI.risco_relativo_uf), 0) AS rr_polimedicamento_uf,
    ISNULL(MAX(I_POLI.risco_relativo_br), 0) AS rr_polimedicamento_br,
    
    -- 7. MÉDIA ITENS
    ISNULL(MAX(I_MEDIA_ITENS.media_itens_autorizacao), 0) AS val_media_itens,
    ISNULL(MAX(I_MEDIA_ITENS.risco_relativo_uf), 0) AS rr_media_itens_uf,
    ISNULL(MAX(I_MEDIA_ITENS.risco_relativo_br), 0) AS rr_media_itens_br,

    -- 8. VENDAS CONSECUTIVAS (ROBÔS)
    ISNULL(MAX(I_CONSEC.percentual_vendas_consecutivas), 0) AS pct_vendas_rapidas_60s,
    ISNULL(MAX(I_CONSEC.risco_relativo_uf), 0) AS rr_vendas_rapidas_uf,
    ISNULL(MAX(I_CONSEC.risco_relativo_br), 0) AS rr_vendas_rapidas_br,

    -- 9. HORÁRIO ATÍPICO
    ISNULL(MAX(I_HORA.percentual_madrugada), 0) AS pct_horario_atipico,
    ISNULL(MAX(I_HORA.risco_relativo_uf), 0) AS rr_horario_atipico_uf,
    ISNULL(MAX(I_HORA.risco_relativo_br), 0) AS rr_horario_atipico_br,
    
    -- 10. CONCENTRAÇÃO EM DIAS DE PICO
    ISNULL(MAX(I_PICO.percentual_concentracao_pico), 0) AS pct_concentracao_pico,
    ISNULL(MAX(I_PICO.risco_relativo_uf), 0) AS rr_concentracao_pico_uf,
    ISNULL(MAX(I_PICO.risco_relativo_br), 0) AS rr_concentracao_pico_br,

    -- 11. TICKET MÉDIO
    ISNULL(MAX(I_TICKET.valor_ticket_medio), 0) AS val_ticket_medio,
    ISNULL(MAX(I_TICKET.risco_relativo_uf), 0) AS rr_ticket_medio_uf,
    ISNULL(MAX(I_TICKET.risco_relativo_br), 0) AS rr_ticket_medio_br,
    
    -- 12. RECEITA POR PACIENTE
    ISNULL(MAX(I_RECPAC.receita_por_paciente), 0) AS val_receita_por_paciente,
    ISNULL(MAX(I_RECPAC.risco_relativo_uf), 0) AS rr_receita_por_paciente_uf,
    ISNULL(MAX(I_RECPAC.risco_relativo_br), 0) AS rr_receita_por_paciente_br,
    
    -- 13. VENDA PER CAPITA
    ISNULL(MAX(I_PERCAPITA.valor_per_capita), 0) AS val_venda_per_capita_municipio,
    ISNULL(MAX(I_PERCAPITA.risco_relativo_uf), 0) AS rr_venda_per_capita_uf,
    ISNULL(MAX(I_PERCAPITA.risco_relativo_br), 0) AS rr_venda_per_capita_br,
    
    -- 14. ALTO CUSTO
    ISNULL(MAX(I_ALTO.percentual_alto_custo), 0) AS pct_alto_custo,
    ISNULL(MAX(I_ALTO.risco_relativo_uf), 0) AS rr_alto_custo_uf,
    ISNULL(MAX(I_ALTO.risco_relativo_br), 0) AS rr_alto_custo_br


INTO temp_CGUSC.dbo.resultado_Sentinela_2015_2024
FROM #movimentacao_gerencial A

-- JOINS ORIGINAIS
LEFT JOIN #vendas_falecidos_gerencial E ON E.cnpj = A.cnpj
INNER JOIN temp_CGUSC.sus.tb_ibge F ON F.id_ibge7 = A.codibge
INNER JOIN #valor_multa G ON G.cnpj = A.cnpj
INNER JOIN #autorizacoes h ON h.cnpj = A.cnpj

-- JOINS DOS NOVOS INDICADORES (Tabelas Permanentes)
LEFT JOIN temp_CGUSC.dbo.Matriz_Risco_Final RISCO ON RISCO.cnpj = A.cnpj
LEFT JOIN temp_CGUSC.dbo.indicadorFalecidos_Completo I_FALECIDOS ON I_FALECIDOS.cnpj = A.cnpj
LEFT JOIN temp_CGUSC.dbo.indicadorPacientesFantasma_Completo I_FANTASMA ON I_FANTASMA.cnpj = A.cnpj
LEFT JOIN temp_CGUSC.dbo.indicadorInconsistenciaClinica_Completo I_CLINICA ON I_CLINICA.cnpj = A.cnpj
LEFT JOIN temp_CGUSC.dbo.indicadorTeto_Completo I_TETO ON I_TETO.cnpj = A.cnpj
LEFT JOIN temp_CGUSC.dbo.indicadorPolimedicamento_Completo I_POLI ON I_POLI.cnpj = A.cnpj
LEFT JOIN temp_CGUSC.dbo.indicadorMediaItens_Completo I_MEDIA_ITENS ON I_MEDIA_ITENS.cnpj = A.cnpj
LEFT JOIN temp_CGUSC.dbo.indicadorVendasConsecutivas_Completo I_CONSEC ON I_CONSEC.cnpj = A.cnpj
LEFT JOIN temp_CGUSC.dbo.indicadorHorarioAtipico_Completo I_HORA ON I_HORA.cnpj = A.cnpj
LEFT JOIN temp_CGUSC.dbo.indicadorConcentracaoPico_Completo I_PICO ON I_PICO.cnpj = A.cnpj
LEFT JOIN temp_CGUSC.dbo.indicadorTicketMedio_Completo I_TICKET ON I_TICKET.cnpj = A.cnpj
LEFT JOIN temp_CGUSC.dbo.indicadorReceitaPorPaciente_Completo I_RECPAC ON I_RECPAC.cnpj = A.cnpj
LEFT JOIN temp_CGUSC.dbo.indicadorVendaPerCapita_Completo I_PERCAPITA ON I_PERCAPITA.cnpj = A.cnpj
LEFT JOIN temp_CGUSC.dbo.indicadorAltoCusto_Completo I_ALTO ON I_ALTO.cnpj = A.cnpj

GROUP BY 
    A.uf,
    F.id_ibge7,
    A.municipio,
    F.nu_populacao,
    A.cnpj,
    A.razao_social,
    A.qnt_vendas,
    A.qnt_vendas_sem_comprovacao,
    h.total_autorizacoes,
    A.valor_vendas,
    A.valor_sem_comprovacao,
    A.percentual_sem_comprovacao,
    A.num_estabelecimentos_mesmo_municipio,
    A.num_meses_movimentacao,
    A.CodPorteEmpresa,
    G.valor_multa,
    E.percentual_falecidos,
    E.vendas_falecidos;




