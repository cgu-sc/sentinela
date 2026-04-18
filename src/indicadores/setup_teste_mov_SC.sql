-- ============================================================================
-- CRIAÇÃO DA TABELA DE TESTE: temp_CGUSC.fp.teste_mov_SC
-- ============================================================================
-- Fonte : db_FarmaciaPopular.carga_2024.relatorio_movimentacaoFP_2021_2024
-- Filtro: Ano 2023 + Farmácias localizadas em SC (via JOIN com dados_farmacia)
-- ============================================================================

USE [temp_CGUSC]
GO

DROP TABLE IF EXISTS temp_CGUSC.fp.teste_mov_SC;

SELECT M.*
INTO temp_CGUSC.fp.teste_mov_SC
FROM db_FarmaciaPopular.carga_2024.relatorio_movimentacaoFP_2021_2024 M
INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = M.cnpj
WHERE M.data_hora >= '2023-01-01'
  AND M.data_hora <  '2024-01-01'
  AND F.uf = 'SC';

-- Índices para performance do crms_1
CREATE CLUSTERED INDEX IDX_TesteMov_cnpj   ON temp_CGUSC.fp.teste_mov_SC(cnpj);
CREATE NONCLUSTERED INDEX IDX_TesteMov_dt  ON temp_CGUSC.fp.teste_mov_SC(data_hora);
CREATE NONCLUSTERED INDEX IDX_TesteMov_crm ON temp_CGUSC.fp.teste_mov_SC(crm, crm_uf);

-- Verificação
SELECT
    COUNT(*)                    AS total_registros,
    COUNT(DISTINCT cnpj)        AS total_farmacias,
    COUNT(DISTINCT crm)         AS total_crms,
    MIN(data_hora)              AS periodo_inicio,
    MAX(data_hora)              AS periodo_fim
FROM temp_CGUSC.fp.teste_mov_SC;

PRINT 'teste_mov_SC criada com sucesso.';
GO
