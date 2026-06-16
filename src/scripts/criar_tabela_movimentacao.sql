-- ============================================================================
-- CRIAÇÃO DA TABELA DE TESTE COMPLETA (SC)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.mov;

SELECT 
    M.num_autorizacao,
    M.cupom_fiscal,
    M.cpf,
    M.crm,
    M.crm_uf,
    M.cnpj,
    M.data_hora,
    M.codigo_barra,
    M.qnt_autorizada,
    M.valor_referencia,
    M.valor_pago
INTO temp_CGUSC.fp.mov
FROM (
    SELECT num_autorizacao, cupom_fiscal, cpf, crm, crm_uf, cnpj, data_hora, codigo_barra, qnt_autorizada, valor_referencia, valor_pago 
    FROM db_FarmaciaPopular.dbo.Relatorio_movimentacaoFP
    UNION ALL
    SELECT num_autorizacao, cupom_fiscal, cpf, crm, crm_uf, cnpj, data_hora, codigo_barra, qnt_autorizada, valor_referencia, valor_pago 
    FROM db_FarmaciaPopular.carga_2024.relatorio_movimentacaoFP_2021_2024
) M
INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = M.cnpj
WHERE F.id_regiao_saude = '31062'

-- Índice para garantir que o script de teste voe
CREATE CLUSTERED INDEX IDX_MovSC_Cnpj ON temp_CGUSC.fp.mov(cnpj, data_hora);
CREATE NONCLUSTERED INDEX IDX_MovSC_Crm ON temp_CGUSC.fp.mov(crm, crm_uf);
