-- 19.017.344 sem filtro da Receita
-- 15.427.786  com Filtro de Obito 
-- 15.242.540  com Filtro de Obito e comparando a Data de Nascimento
DROP TABLE

IF EXISTS #sisobi_tcu
	SELECT max(A.DATA_OBITO) dt_obito
		,A.CPF_FALECIDO collate SQL_Latin1_General_CP1_CI_AI cpf
		,A.DATA_NASCIMENTO_FALECIDO dt_nascimento
		,'SISOBI_TCU' collate SQL_Latin1_General_CP1_CI_AI AS fonte
		,'db_obitos_tcu.dbo.SISOBI' collate SQL_Latin1_General_CP1_CI_AI AS endereco
	INTO #sisobi_tcu
	FROM db_obitos_tcu.dbo.SISOBI A
	INNER JOIN db_CPF.dbo.CPF B ON B.CPF = A.CPF_FALECIDO COLLATE SQL_Latin1_General_CP1_CI_AI
	-- O Collate da base db_CPF é SQL_Latin1_General_CP1_CI_AI e da base db_obitos_tcu é Latin1_General_CI_AI
	-- Na comparação de literais com collations diferentes é necessário converter uma das collations para igualar.
	-- NEsese caso optei por converter a collation da base Obitos_TCU para deixar com a mesma collation da base db_CPF.
	INNER JOIN (
		SELECT CPF_FALECIDO
			,DATA_NASCIMENTO_FALECIDO
			,max(dt_atualizacao_registro) dt_atualizacao_registro
		FROM db_obitos_tcu.dbo.SISOBI
		GROUP BY CPF_FALECIDO
			,DATA_NASCIMENTO_FALECIDO
		) C ON C.CPF_FALECIDO = A.CPF_FALECIDO
		AND C.DATA_NASCIMENTO_FALECIDO = A.DATA_NASCIMENTO_FALECIDO
		AND C.dt_atualizacao_registro = A.DT_ATUALIZACAO_REGISTRO
	WHERE A.data_Obito IS NOT NULL
		AND A.CPF_FALECIDO IS NOT NULL
		AND B.sitCadastral = 3
		AND B.anoObito = year(A.data_Obito)
		AND A.DATA_NASCIMENTO_FALECIDO = B.dataNascimento
	GROUP BY A.CPF_FALECIDO
		,A.DATA_NASCIMENTO_FALECIDO

--9.148.913  sem filtro da Receita
--9.147.809  com Filtro de Obito 
--9.033.057  com Filtro de Obito e comparando a Data de Nascimento
DROP TABLE

IF EXISTS #sirc
	SELECT max(A.dataObito) dt_obito
		,B.numero cpf
		,A.dataNascimento dt_nascimento
		,'SIRC' AS fonte
		,'[db_sirc_do].[obitos].[obitos]' AS endereco
	INTO #sirc
	FROM [db_sirc_do].[obitos].[obitos] A
	INNER JOIN [db_sirc_do].[obitos].documentos B ON B.obito_fk = A.id
	INNER JOIN db_CPF.dbo.CPF C ON C.CPF = B.numero
	INNER JOIN (
		SELECT Bb.numero cpf
			,Aa.dataNascimento dt_nascimento
			,max(Aa.dataHoraOperacao) dataHoraOperacao
		FROM [db_sirc_do].[obitos].[obitos] Aa
		INNER JOIN [db_sirc_do].[obitos].documentos Bb ON Bb.obito_fk = Aa.id
		GROUP BY Bb.numero
			,Aa.dataNascimento
		) D ON D.cpf = B.numero
		AND D.dt_nascimento = A.dataNascimento
		AND D.dataHoraOperacao = A.dataHoraOperacao
	WHERE B.tipo = 'CPF'
		AND A.dataObito IS NOT NULL
		AND A.dataLavratura >= A.dataObito
		AND C.sitCadastral = 3
		AND C.anoObito = year(A.dataObito)
		AND A.dataNascimento = C.dataNascimento
	GROUP BY B.numero
		,A.dataNascimento

DROP TABLE

IF EXISTS #sisobi_temp
	SELECT A.dt_obito dt_obito
		,A.num_termo
		,A.cpf
		,A.dt_nascimento
		,'SISOBI' AS fonte
		,'[db_obitos].[dbo].[sisobi]' AS endereco
	INTO #sisobi_temp
	FROM (
		SELECT dt_obito AS dt_obito
			,try_cast(num_termo AS INT) num_termo
			,Dt_NASCIMENTO dt_nascimento
			,CPF cpf
		FROM [db_obitos].[dbo].[sisobi]
		WHERE CPF IS NOT NULL
			AND Dt_Obito IS NOT NULL
			AND dt_nascimento IS NOT NULL
			AND dt_lavratura >= dt_obito
		
		UNION ALL
		
		SELECT dt_obito AS dt_obito
			,try_cast(num_termo AS INT) num_termo
			,Dt_NASCIMENTO dt_nascimento
			,CPF cpf
		FROM [db_obitos].[dbo].obitos_201609
		WHERE CPF IS NOT NULL
			AND Dt_Obito IS NOT NULL
			AND dt_nascimento IS NOT NULL
			AND dt_lavratura >= dt_obito
		
		UNION ALL
		
		SELECT dt_obito AS dt_obito
			,try_cast(num_termo AS INT) num_termo
			,Dt_NASCIMENTO dt_nascimento
			,CPF cpf
		FROM [db_obitos].[dbo].obitos_201610
		WHERE CPF IS NOT NULL
			AND Dt_Obito IS NOT NULL
			AND dt_nascimento IS NOT NULL
			AND dt_lavratura >= dt_obito
		
		UNION ALL
		
		SELECT dt_obito AS dt_obito
			,try_cast(num_termo AS INT) num_termo
			,Dt_NASCIMENTO dt_nascimento
			,CPF cpf
		FROM [db_obitos].[dbo].obitos_201611
		WHERE CPF IS NOT NULL
			AND Dt_Obito IS NOT NULL
			AND dt_nascimento IS NOT NULL
			AND dt_lavratura >= dt_obito
		
		UNION ALL
		
		SELECT dt_obito AS dt_obito
			,try_cast(num_termo AS INT) num_termo
			,Dt_NASCIMENTO dt_nascimento
			,CPF cpf
		FROM [db_obitos].[dbo].obitos_201612
		WHERE CPF IS NOT NULL
			AND Dt_Obito IS NOT NULL
			AND dt_nascimento IS NOT NULL
			AND dt_lavratura >= dt_obito
		
		UNION ALL
		
		SELECT dt_obito AS dt_obito
			,try_cast(num_termo AS INT) num_termo
			,Dt_NASCIMENTO dt_nascimento
			,CPF cpf
		FROM [db_obitos].[dbo].obitos_201701
		WHERE CPF IS NOT NULL
			AND Dt_Obito IS NOT NULL
			AND dt_nascimento IS NOT NULL
			AND dt_lavratura >= dt_obito
		
		UNION ALL
		
		SELECT dt_obito AS dt_obito
			,try_cast(num_termo AS INT) num_termo
			,Dt_NASCIMENTO dt_nascimento
			,CPF cpf
		FROM [db_obitos].[dbo].obitos_201702
		WHERE CPF IS NOT NULL
			AND Dt_Obito IS NOT NULL
			AND dt_nascimento IS NOT NULL
			AND dt_lavratura >= dt_obito
		
		UNION ALL
		
		SELECT dt_obito AS dt_obito
			,try_cast(num_termo AS INT) num_termo
			,Dt_NASCIMENTO dt_nascimento
			,CPF cpf
		FROM [db_obitos].[dbo].obitos_201703
		WHERE CPF IS NOT NULL
			AND Dt_Obito IS NOT NULL
			AND dt_nascimento IS NOT NULL
			AND dt_lavratura >= dt_obito
		
		UNION ALL
		
		SELECT dt_obito AS dt_obito
			,try_cast(num_termo AS INT) num_termo
			,Dt_NASCIMENTO dt_nascimento
			,CPF cpf
		FROM [db_obitos].[dbo].obitos_201704
		WHERE CPF IS NOT NULL
			AND Dt_Obito IS NOT NULL
			AND dt_nascimento IS NOT NULL
			AND dt_lavratura >= dt_obito
		
		UNION ALL
		
		SELECT dt_obito AS dt_obito
			,try_cast(num_termo AS INT) num_termo
			,Dt_NASCIMENTO dt_nascimento
			,CPF cpf
		FROM [db_obitos].[dbo].obitos_201705
		WHERE CPF IS NOT NULL
			AND Dt_Obito IS NOT NULL
			AND dt_nascimento IS NOT NULL
			AND dt_lavratura >= dt_obito
		
		UNION ALL
		
		SELECT dt_obito AS dt_obito
			,try_cast(num_termo AS INT) num_termo
			,Dt_NASCIMENTO dt_nascimento
			,CPF cpf
		FROM [db_obitos].[dbo].obitos_201706
		WHERE CPF IS NOT NULL
			AND Dt_Obito IS NOT NULL
			AND dt_nascimento IS NOT NULL
			AND dt_lavratura >= dt_obito
		
		UNION ALL
		
		SELECT dt_obito AS dt_obito
			,try_cast(num_termo AS INT) num_termo
			,Dt_NASCIMENTO dt_nascimento
			,CPF cpf
		FROM [db_obitos].[dbo].obitos_201707
		WHERE CPF IS NOT NULL
			AND Dt_Obito IS NOT NULL
			AND dt_nascimento IS NOT NULL
			AND dt_lavratura >= dt_obito
		
		UNION ALL
		
		SELECT dt_obito AS dt_obito
			,try_cast(num_termo AS INT) num_termo
			,Dt_NASCIMENTO dt_nascimento
			,CPF cpf
		FROM [db_obitos].[dbo].obitos_201708
		WHERE CPF IS NOT NULL
			AND Dt_Obito IS NOT NULL
			AND dt_nascimento IS NOT NULL
			AND dt_lavratura >= dt_obito
		
		UNION ALL
		
		SELECT dt_obito AS dt_obito
			,try_cast(num_termo AS INT) num_termo
			,Dt_NASCIMENTO dt_nascimento
			,CPF cpf
		FROM [db_obitos].[dbo].obitos_201709
		WHERE CPF IS NOT NULL
			AND Dt_Obito IS NOT NULL
			AND dt_nascimento IS NOT NULL
			AND dt_lavratura >= dt_obito
		
		UNION ALL
		
		SELECT dt_obito AS dt_obito
			,try_cast(num_termo AS INT) num_termo
			,Dt_NASCIMENTO dt_nascimento
			,CPF cpf
		FROM [db_obitos].[dbo].obitos_201710
		WHERE CPF IS NOT NULL
			AND Dt_Obito IS NOT NULL
			AND dt_nascimento IS NOT NULL
			AND dt_lavratura >= dt_obito
		
		UNION ALL
		
		SELECT dt_obito AS dt_obito
			,try_cast(num_termo AS INT) num_termo
			,Dt_NASCIMENTO dt_nascimento
			,CPF cpf
		FROM [db_obitos].[dbo].obitos_201711
		WHERE CPF IS NOT NULL
			AND Dt_Obito IS NOT NULL
			AND dt_nascimento IS NOT NULL
			AND dt_lavratura >= dt_obito
		
		UNION ALL
		
		SELECT dt_obito AS dt_obito
			,try_cast(num_termo AS INT) num_termo
			,Dt_NASCIMENTO dt_nascimento
			,CPF cpf
		FROM [db_obitos].[dbo].obitos_201712
		WHERE CPF IS NOT NULL
			AND Dt_Obito IS NOT NULL
			AND dt_nascimento IS NOT NULL
			AND dt_lavratura >= dt_obito
		
		UNION ALL
		
		SELECT dt_obito AS dt_obito
			,try_cast(num_termo AS INT) num_termo
			,Dt_NASCIMENTO dt_nascimento
			,CPF cpf
		FROM [db_obitos].[dbo].obitos_201801
		WHERE CPF IS NOT NULL
			AND Dt_Obito IS NOT NULL
			AND dt_nascimento IS NOT NULL
			AND dt_lavratura >= dt_obito
		
		UNION ALL
		
		SELECT dt_obito AS dt_obito
			,try_cast(num_termo AS INT) num_termo
			,Dt_NASCIMENTO dt_nascimento
			,CPF cpf
		FROM [db_obitos].[dbo].obitos_201802
		WHERE CPF IS NOT NULL
			AND Dt_Obito IS NOT NULL
			AND dt_nascimento IS NOT NULL
			AND dt_lavratura >= dt_obito
		
		UNION ALL
		
		SELECT dt_obito AS dt_obito
			,try_cast(num_termo AS INT) num_termo
			,Dt_NASCIMENTO dt_nascimento
			,CPF cpf
		FROM [db_obitos].[dbo].obitos_201803
		WHERE CPF IS NOT NULL
			AND Dt_Obito IS NOT NULL
			AND dt_nascimento IS NOT NULL
			AND dt_lavratura >= dt_obito
		
		UNION ALL
		
		SELECT dt_obito AS dt_obito
			,try_cast(num_termo AS INT) num_termo
			,Dt_NASCIMENTO dt_nascimento
			,CPF cpf
		FROM [db_obitos].[dbo].obitos_201804
		WHERE CPF IS NOT NULL
			AND Dt_Obito IS NOT NULL
			AND dt_nascimento IS NOT NULL
			AND dt_lavratura >= dt_obito
		
		UNION ALL
		
		SELECT dt_obito AS dt_obito
			,try_cast(num_termo AS INT) num_termo
			,Dt_NASCIMENTO dt_nascimento
			,CPF cpf
		FROM [db_obitos].[dbo].obitos_201805
		WHERE CPF IS NOT NULL
			AND Dt_Obito IS NOT NULL
			AND dt_nascimento IS NOT NULL
			AND dt_lavratura >= dt_obito
		
		UNION ALL
		
		SELECT dt_obito AS dt_obito
			,try_cast(num_termo AS INT) num_termo
			,Dt_NASCIMENTO dt_nascimento
			,CPF cpf
		FROM [db_obitos].[dbo].obitos_201806
		WHERE CPF IS NOT NULL
			AND Dt_Obito IS NOT NULL
			AND dt_nascimento IS NOT NULL
			AND dt_lavratura >= dt_obito
		
		UNION ALL
		
		SELECT dt_obito AS dt_obito
			,try_cast(num_termo AS INT) num_termo
			,Dt_NASCIMENTO dt_nascimento
			,CPF cpf
		FROM [db_obitos].[dbo].obitos_201807
		WHERE CPF IS NOT NULL
			AND Dt_Obito IS NOT NULL
			AND dt_nascimento IS NOT NULL
			AND dt_lavratura >= dt_obito
		
		UNION ALL
		
		SELECT dt_obito AS dt_obito
			,try_cast(num_termo AS INT) num_termo
			,Dt_NASCIMENTO dt_nascimento
			,CPF cpf
		FROM [db_obitos].[dbo].obitos_201808
		WHERE CPF IS NOT NULL
			AND Dt_Obito IS NOT NULL
			AND dt_nascimento IS NOT NULL
			AND dt_lavratura >= dt_obito
		
		UNION ALL
		
		SELECT dt_obito AS dt_obito
			,try_cast(num_termo AS INT) num_termo
			,Dt_NASCIMENTO dt_nascimento
			,CPF cpf
		FROM [db_obitos].[dbo].obitos_201809
		WHERE CPF IS NOT NULL
			AND Dt_Obito IS NOT NULL
			AND dt_nascimento IS NOT NULL
			AND dt_lavratura >= dt_obito
		
		UNION ALL
		
		SELECT dt_obito AS dt_obito
			,try_cast(num_termo AS INT) num_termo
			,Dt_NASCIMENTO dt_nascimento
			,CPF cpf
		FROM [db_obitos].[dbo].obitos_201810
		WHERE CPF IS NOT NULL
			AND Dt_Obito IS NOT NULL
			AND dt_nascimento IS NOT NULL
			AND dt_lavratura >= dt_obito
		
		UNION ALL
		
		SELECT dt_obito AS dt_obito
			,try_cast(num_termo AS INT) num_termo
			,Dt_NASCIMENTO dt_nascimento
			,CPF cpf
		FROM [db_obitos].[dbo].obitos_201811
		WHERE CPF IS NOT NULL
			AND Dt_Obito IS NOT NULL
			AND dt_nascimento IS NOT NULL
			AND dt_lavratura >= dt_obito
		
		UNION ALL
		
		SELECT dt_obito AS dt_obito
			,try_cast(num_termo AS INT) num_termo
			,Dt_NASCIMENTO dt_nascimento
			,CPF cpf
		FROM [db_obitos].[dbo].obitos_201812
		WHERE CPF IS NOT NULL
			AND Dt_Obito IS NOT NULL
			AND dt_nascimento IS NOT NULL
			AND dt_lavratura >= dt_obito
		
		UNION ALL
		
		SELECT dt_obito AS dt_obito
			,try_cast(num_termo AS INT) num_termo
			,Dt_NASCIMENTO dt_nascimento
			,CPF cpf
		FROM [db_obitos].[dbo].obitos_201901
		WHERE CPF IS NOT NULL
			AND Dt_Obito IS NOT NULL
			AND dt_nascimento IS NOT NULL
			AND dt_lavratura >= dt_obito
		
		UNION ALL
		
		SELECT dt_obito AS dt_obito
			,try_cast(num_termo AS INT) num_termo
			,Dt_NASCIMENTO dt_nascimento
			,CPF cpf
		FROM [db_obitos].[dbo].obitos_201902
		WHERE CPF IS NOT NULL
			AND Dt_Obito IS NOT NULL
			AND dt_nascimento IS NOT NULL
			AND dt_lavratura >= dt_obito
		
		UNION ALL
		
		SELECT dt_obito AS dt_obito
			,try_cast(num_termo AS INT) num_termo
			,Dt_NASCIMENTO dt_nascimento
			,CPF cpf
		FROM [db_obitos].[dbo].obitos_201903
		WHERE CPF IS NOT NULL
			AND Dt_Obito IS NOT NULL
			AND dt_nascimento IS NOT NULL
			AND dt_lavratura >= dt_obito
		
		UNION ALL
		
		SELECT dt_obito AS dt_obito
			,try_cast(num_termo AS INT) num_termo
			,Dt_NASCIMENTO dt_nascimento
			,CPF cpf
		FROM [db_obitos].[dbo].obitos_201904
		WHERE CPF IS NOT NULL
			AND Dt_Obito IS NOT NULL
			AND dt_nascimento IS NOT NULL
			AND dt_lavratura >= dt_obito
		
		UNION ALL
		
		SELECT dt_obito AS dt_obito
			,try_cast(num_termo AS INT) num_termo
			,Dt_NASCIMENTO dt_nascimento
			,CPF cpf
		FROM [db_obitos].[dbo].obitos_201905
		WHERE CPF IS NOT NULL
			AND Dt_Obito IS NOT NULL
			AND dt_nascimento IS NOT NULL
			AND dt_lavratura >= dt_obito
		
		UNION ALL
		
		SELECT dt_obito AS dt_obito
			,try_cast(num_termo AS INT) num_termo
			,Dt_NASCIMENTO dt_nascimento
			,CPF cpf
		FROM [db_obitos].[dbo].obitos_201906
		WHERE CPF IS NOT NULL
			AND Dt_Obito IS NOT NULL
			AND dt_nascimento IS NOT NULL
			AND dt_lavratura >= dt_obito
		
		UNION ALL
		
		SELECT dt_obito AS dt_obito
			,try_cast(num_termo AS INT) num_termo
			,Dt_NASCIMENTO dt_nascimento
			,CPF cpf
		FROM [db_obitos].[dbo].obitos_201907
		WHERE CPF IS NOT NULL
			AND Dt_Obito IS NOT NULL
			AND dt_nascimento IS NOT NULL
			AND dt_lavratura >= dt_obito
		
		UNION ALL
		
		SELECT dt_obito AS dt_obito
			,try_cast(num_termo AS INT) num_termo
			,Dt_NASCIMENTO dt_nascimento
			,CPF cpf
		FROM [db_obitos].[dbo].obitos_201908
		WHERE CPF IS NOT NULL
			AND Dt_Obito IS NOT NULL
			AND dt_nascimento IS NOT NULL
			AND dt_lavratura >= dt_obito
		
		UNION ALL
		
		SELECT dt_obito AS dt_obito
			,try_cast(num_termo AS INT) num_termo
			,Dt_NASCIMENTO dt_nascimento
			,CPF cpf
		FROM [db_obitos].[dbo].obitos_201909
		WHERE CPF IS NOT NULL
			AND Dt_Obito IS NOT NULL
			AND dt_nascimento IS NOT NULL
			AND dt_lavratura >= dt_obito
		
		UNION ALL
		
		SELECT dt_obito AS dt_obito
			,try_cast(num_termo AS INT) num_termo
			,Dt_NASCIMENTO dt_nascimento
			,CPF cpf
		FROM [db_obitos].[dbo].obitos_201910
		WHERE CPF IS NOT NULL
			AND Dt_Obito IS NOT NULL
			AND dt_nascimento IS NOT NULL
			AND dt_lavratura >= dt_obito
		
		UNION ALL
		
		SELECT dt_obito AS dt_obito
			,try_cast(num_termo AS INT) num_termo
			,Dt_NASCIMENTO dt_nascimento
			,CPF cpf
		FROM [db_obitos].[dbo].obitos_201911
		WHERE CPF IS NOT NULL
			AND Dt_Obito IS NOT NULL
			AND dt_nascimento IS NOT NULL
			AND dt_lavratura >= dt_obito
		
		UNION ALL
		
		SELECT dt_obito AS dt_obito
			,try_cast(num_termo AS INT) num_termo
			,Dt_NASCIMENTO dt_nascimento
			,CPF cpf
		FROM [db_obitos].[dbo].obitos_201912
		WHERE CPF IS NOT NULL
			AND Dt_Obito IS NOT NULL
			AND dt_nascimento IS NOT NULL
			AND dt_lavratura >= dt_obito
		
		UNION ALL
		
		SELECT dt_obito AS dt_obito
			,try_cast(num_termo AS INT) num_termo
			,Dt_NASCIMENTO dt_nascimento
			,CPF cpf
		FROM [db_obitos].[dbo].obitos_202001
		WHERE CPF IS NOT NULL
			AND Dt_Obito IS NOT NULL
			AND dt_nascimento IS NOT NULL
			AND dt_lavratura >= dt_obito
		
		UNION ALL
		
		SELECT dt_obito AS dt_obito
			,try_cast(num_termo AS INT) num_termo
			,Dt_NASCIMENTO dt_nascimento
			,CPF cpf
		FROM [db_obitos].[dbo].obitos_202002
		WHERE CPF IS NOT NULL
			AND Dt_Obito IS NOT NULL
			AND dt_nascimento IS NOT NULL
			AND dt_lavratura >= dt_obito
		
		UNION ALL
		
		SELECT dt_obito AS dt_obito
			,try_cast(num_termo AS INT) num_termo
			,Dt_NASCIMENTO dt_nascimento
			,CPF cpf
		FROM [db_obitos].[dbo].obitos_202003
		WHERE CPF IS NOT NULL
			AND Dt_Obito IS NOT NULL
			AND dt_nascimento IS NOT NULL
			AND dt_lavratura >= dt_obito
		) A

--13.161.877 sem filtro da Receita
--12.069.295 com Filtro de Obito 
--11.896.409 com Filtro de Obito e comparando a Data de Nascimento
DROP TABLE

IF EXISTS #sisobi
	SELECT A.cpf
		,A.dt_nascimento
		,max(A.dt_obito) dt_obito
		,A.fonte
	INTO #sisobi
	FROM #sisobi_temp A
	INNER JOIN db_CPF.dbo.CPF B ON B.CPF = A.cpf
	INNER JOIN (
		SELECT cpf
			,dt_nascimento
			,max(try_cast(num_termo AS INT)) max_num_termo
		FROM #sisobi_temp
		GROUP BY cpf
			,dt_nascimento
		) C ON C.cpf = A.cpf
		AND C.dt_nascimento = A.dt_nascimento
		AND C.max_num_termo = A.num_termo
	WHERE B.sitCadastral = 3
		AND B.anoObito = year(A.dt_obito)
		AND A.dt_nascimento = B.dataNascimento
	GROUP BY A.CPF
		,A.dt_nascimento
		,A.fonte

--34783922
DROP TABLE

IF EXISTS #temp_bases_obitos
	SELECT A.*
	INTO #temp_bases_obitos
	FROM (
		SELECT cpf
			,dt_obito
			,dt_nascimento
			,fonte
		FROM #sirc
		
		UNION ALL
		
		SELECT cpf
			,dt_obito
			,dt_nascimento
			,fonte
		FROM #sisobi
		
		UNION ALL
		
		SELECT cpf
			,dt_obito
			,dt_nascimento
			,fonte
		FROM #sisobi_tcu
		) A
	GROUP BY A.cpf
		,A.DT_OBITO
		,A.fonte
		,A.dt_nascimento

-- 23.587.245 Registros de Óbito
DROP TABLE

IF EXISTS #temp_obitos
	SELECT cpf
		,dt_obito
		,dt_nascimento
		,STUFF((
				SELECT DISTINCT ',' + fonte
				FROM #temp_bases_obitos B
				WHERE A.cpf = B.cpf
					AND A.dt_obito = B.dt_obito
					AND A.dt_nascimento = B.dt_nascimento
				FOR XML PATH('')
				), 1, 1, '') AS fonte
	INTO #temp_obitos
	FROM #temp_bases_obitos A
	GROUP BY cpf
		,dt_obito
		,dt_nascimento

DROP TABLE

IF EXISTS #cpfs_duplicados
	SELECT cpf
	INTO #cpfs_duplicados
	FROM #temp_obitos
	GROUP BY cpf
	HAVING count(*) > 1

DROP TABLE

IF EXISTS temp_CGUSC.fp.obito_unificada
	SELECT cpf
		,dt_obito
		,dt_nascimento
		,fonte
	INTO temp_CGUSC.fp.obito_unificada
	FROM #temp_obitos A
	WHERE cpf NOT IN (
			SELECT cpf
			FROM #cpfs_duplicados
			)


CREATE UNIQUE CLUSTERED INDEX IDX_Obitos_CPF 
ON temp_CGUSC.fp.obito_unificada(cpf);

-- Opcional: Índice Secundário se você for fazer consultas filtrando pela Data de Óbito
CREATE NONCLUSTERED INDEX IDX_Obitos_Data 
ON temp_CGUSC.fp.obito_unificada(dt_obito)
INCLUDE (cpf);