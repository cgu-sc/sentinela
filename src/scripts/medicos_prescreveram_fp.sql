-- CRIAR LISTA DE MEDICOS QUE PRESCREVERAM PARA O FARMACIA POPULAR E SEUS RESPECTIVOS REGISTROS NO CRM
DROP TABLE

IF EXISTS #cnpj_registros_farmacia
	SELECT cnpj
		,count(*) num_solicitacoes_estabelecimento
	INTO #cnpj_registros_farmacia
	FROM db_FarmaciaPopular.carga_2024.relatorio_movimentacaoFP_2021_2024
	GROUP BY cnpj

DROP TABLE

IF EXISTS #lista_cnpj_crm
	SELECT cnpj
		,crm
		,crm_uf
		,count(*) num_solicitacoes_medico
		,sum(valor_pago) AS soma_autorizacoes
	INTO #lista_cnpj_crm
	FROM db_FarmaciaPopular.carga_2024.relatorio_movimentacaoFP_2021_2024
	GROUP BY cnpj
		,crm
		,crm_uf

DROP TABLE

IF EXISTS #temp
	SELECT max(nomeprof) nome_profissional
		,registro crm
		,B.sg_uf crm_uf
		,max(cns_prof) AS cns
	INTO #temp
	FROM [db_CNES].[mm].[PF] A
	INNER JOIN temp_CGUSC.sus.tb_ibge_estados B ON B.id_uf = substring(codufmun, 1, 2)
	WHERE conselho = '71'
		AND cns_prof IS NOT NULL
		AND nomeprof IS NOT NULL
	GROUP BY substring(codufmun, 1, 2)
		,registro
		,B.sg_uf

DROP TABLE

IF EXISTS #temp2
	SELECT A.*
		,B.cpf
		,B.dtnascimento dt_nascimento
	INTO #temp2
	FROM #temp A
	LEFT JOIN [db_CADSUS].[dbo].[SBYN_PESSOASBR] B ON B.CARTAODEFINITIVO = A.cns

DROP TABLE

IF EXISTS temp_CGUSC.dbo.lista_medicos_farmacia_popularFP_temp
	SELECT A.cnpj
		,A.crm
		,A.crm_uf
		,A.num_solicitacoes_medico
		,C.num_solicitacoes_estabelecimento
		,A.soma_autorizacoes
		,(try_cast(A.num_solicitacoes_medico AS DECIMAL(10, 2)) / try_cast(C.num_solicitacoes_estabelecimento AS DECIMAL(10, 2))) AS percentual
		,ISNULL(B.nome_profissional, '-') AS nome_profissional
		,ISNULL(B.cns, '-') AS cns
		,ISNULL(B.cpf, '-') AS cpf
	INTO temp_CGUSC.dbo.lista_medicos_farmacia_popularFP_temp
	FROM #lista_cnpj_crm A
	LEFT JOIN #temp2 B ON B.crm = A.crm
		AND B.crm_uf = A.crm_uf
	INNER JOIN #cnpj_registros_farmacia C ON C.cnpj = A.cnpj
	WHERE num_solicitacoes_medico > 150
	ORDER BY percentual DESC

SELECT A.cnpj
	,C.no_municipio
	,C.sg_uf
	,C.nu_populacao
	,A.num_solicitacoes_medico
	,A.num_solicitacoes_estabelecimento
	,A.soma_autorizacoes
	,A.percentual
	,A.crm
	,A.crm_uf
	,A.nome_profissional
	,A.cns
	,A.cpf
--,(select count(*) from temp_CGUSC.dbo.sociosFP B where B.cpfcnpjSocio = A.cpf) as socio_FP
FROM temp_CGUSC.dbo.lista_medicos_farmacia_popularFP_temp A
LEFT JOIN temp_CGUSC.dbo.dadosFarmaciasFP B ON B.cnpj = A.cnpj
LEFT JOIN temp_CGUSC.sus.tb_ibge C ON C.id_ibge7 = B.codibge
WHERE A.cnpj = '73217168000127'
GROUP BY C.sg_uf
	,C.no_municipio
	,C.nu_populacao
	,A.cnpj
	,crm
	,crm_uf
	,num_solicitacoes_medico
	,num_solicitacoes_estabelecimento
	,percentual
	,nome_profissional
	,cns
	,cpf
	,A.soma_autorizacoes
ORDER BY percentual DESC
