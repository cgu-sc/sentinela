-- ==========================================================================================
-- SCRIPT DE AUDITORIA E TESTE DE INTEGRIDADE - TEIA SOCIETÁRIA (SENTINELA)
-- Objetivo: Validar unicidade, conectividade e abrangência das tabelas fp.teia_fonte_*
-- ==========================================================================================

--------------------------------------------------------------------------------------------
-- TESTE 1: UNICIDADE (BUSCA POR DUPLICATAS)
-- Não deve haver o mesmo par (Sócio, Empresa) mais de uma vez na mesma tabela.
--------------------------------------------------------------------------------------------

-- 1.1 Nível 1 (Dados Sócios Base)
SELECT 'Duplicatas N1' as teste, cpf_cnpj_socio, cnpj, data_entrada_sociedade, COUNT(*) as qtd
FROM temp_CGUSC.fp.dados_socios
GROUP BY cpf_cnpj_socio, cnpj, data_entrada_sociedade
HAVING COUNT(*) > 1;

-- 1.2 Nível 2
SELECT 'Duplicatas N2' as teste, cpf_cnpj_socio, cnpj_empresa, COUNT(*) as qtd
FROM temp_CGUSC.fp.teia_fonte_nivel2
GROUP BY cpf_cnpj_socio, cnpj_empresa
HAVING COUNT(*) > 1;

-- 1.3 Nível 3
SELECT 'Duplicatas N3' as teste, cnpj_empresa, cpf_cnpj_socio, COUNT(*) as qtd
FROM temp_CGUSC.fp.teia_fonte_nivel3
GROUP BY cnpj_empresa, cpf_cnpj_socio
HAVING COUNT(*) > 1;

-- 1.4 Nível 4
SELECT 'Duplicatas N4' as teste, cpf_cnpj_socio, cnpj_empresa, COUNT(*) as qtd
FROM temp_CGUSC.fp.teia_fonte_nivel4
GROUP BY cpf_cnpj_socio, cnpj_empresa
HAVING COUNT(*) > 1;


--------------------------------------------------------------------------------------------
-- TESTE 2: VALIDAÇÃO DE EMPRESAS INDIVIDUAIS (NOVA LÓGICA)
-- Garante que o INSERT da Etapa 2.1 funcionou e não deixou "buracos".
--------------------------------------------------------------------------------------------

-- 2.1 Farmácias sem nenhum sócio (Deve ser ZERO agora após a Etapa 2.1)
SELECT 'Farmácias Órfãs' as teste, COUNT(*) as qtd
FROM temp_CGUSC.fp.dados_farmacia f
LEFT JOIN temp_CGUSC.fp.dados_socios s ON s.cnpj = f.cnpj
WHERE s.cnpj IS NULL;

-- 2.2 Verificar se os responsáveis inseridos estão corretos (Amostra de EIs)
SELECT TOP 10 'Amostra EI' as teste, f.cnpj, f.razaoSocial, s.nome_socio, s.descricao_qualificacao
FROM temp_CGUSC.fp.dados_farmacia f
INNER JOIN temp_CGUSC.fp.dados_socios s ON s.cnpj = f.cnpj
WHERE f.indPossuiSocio = '0' -- Coluna original que indica ausência de QSA
ORDER BY f.data_abertura DESC;


--------------------------------------------------------------------------------------------
-- TESTE 3: MÉTRICAS DE EXPANSÃO (SAÚDE DA REDE)
--------------------------------------------------------------------------------------------

SELECT 'Volume' as Categoria, 'Nivel 1 (Socios Farmacias)' as Tabela, COUNT(*) as Total FROM temp_CGUSC.fp.dados_socios
UNION ALL
SELECT 'Volume', 'Nivel 2 (Empresas dos Socios)', COUNT(*) FROM temp_CGUSC.fp.teia_fonte_nivel2
UNION ALL
SELECT 'Volume', 'Nivel 3 (Socios das Empresas N2)', COUNT(*) FROM temp_CGUSC.fp.teia_fonte_nivel3
UNION ALL
SELECT 'Volume', 'Nivel 4 (Outras Empresas N3)', COUNT(*) FROM temp_CGUSC.fp.teia_fonte_nivel4;


--------------------------------------------------------------------------------------------
-- TESTE 4: QUALIDADE DOS DADOS
--------------------------------------------------------------------------------------------

-- 4.1 Registros sem identificação de sócio (Geralmente indica erro na fonte ou tratamento)
SELECT 'Sócios sem CPF/CNPJ' as teste, COUNT(*) as qtd FROM temp_CGUSC.fp.dados_socios WHERE cpf_cnpj_socio IS NULL;

-- 4.2 Verificação de integridade da flag is_farmacia_fp (Níveis 2 e 4)
SELECT 'Erros Flag Farmacia N2' as teste, COUNT(*) as qtd FROM temp_CGUSC.fp.teia_fonte_nivel2 WHERE is_farmacia_fp IS NULL;
SELECT 'Erros Flag Farmacia N4' as teste, COUNT(*) as qtd FROM temp_CGUSC.fp.teia_fonte_nivel4 WHERE is_farmacia_fp IS NULL;
