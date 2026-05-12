-- ============================================================================
-- CRIAÇÃO DA TABELA DE TESTE COMPLETA (SC)
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.teste_mov_SC;

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
INTO temp_CGUSC.fp.teste_mov_SC
FROM (
    SELECT num_autorizacao, cupom_fiscal, cpf, crm, crm_uf, cnpj, data_hora, codigo_barra, qnt_autorizada, valor_referencia, valor_pago 
    FROM db_FarmaciaPopular.dbo.Relatorio_movimentacaoFP
    UNION ALL
    SELECT num_autorizacao, cupom_fiscal, cpf, crm, crm_uf, cnpj, data_hora, codigo_barra, qnt_autorizada, valor_referencia, valor_pago 
    FROM db_FarmaciaPopular.carga_2024.relatorio_movimentacaoFP_2021_2024
) M
INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = M.cnpj
WHERE F.uf = 'SC'
  AND M.cnpj IN (
      '03929808000146',
      '05363613000107',
      '05363613000298',
      '05363613000379',
      '27185347000102',
      '30207376000132',
      '10800567000104',
      '17212938000178',
      '50679903000119',
      '39242516000188',
      '11371183000178',
      '32637306000140',
      '11130518000166'
  );

-- Índice para garantir que o script de teste voe
CREATE CLUSTERED INDEX IDX_TesteSC_Cnpj ON temp_CGUSC.fp.teste_mov_SC(cnpj, data_hora);
CREATE NONCLUSTERED INDEX IDX_TesteSC_Crm ON temp_CGUSC.fp.teste_mov_SC(crm, crm_uf);
