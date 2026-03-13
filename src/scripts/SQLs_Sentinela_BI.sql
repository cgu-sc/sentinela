-- d_num_estab_municipio

SELECT A.id_ibge7 codIBGE
	,num_estabelecimentos_mesmo_municipio
FROM temp_CGUSC.dbo.resultado_Sentinela_2021_2024 A
GROUP BY A.id_ibge7
	,num_estabelecimentos_mesmo_municipio


-- d_localizacao


SELECT A.id_ibge7 AS codIBGE
	,A.no_municipio AS Cidade
	,A.sg_uf AS Estado
	,CONCAT (
		A.no_municipio
		,', '
		,A.sg_uf
		,', Brasil'
		) AS 'Localização'
FROM temp_CGUSC.sus.tb_ibge A
INNER JOIN temp_CGUSC.sus.tb_ibge_estados B ON B.id_uf = A.id_uf
where id_ibge7 <> '0000000'

-- d_ibge

SELECT A.sg_uf AS uf
	,A.id_ibge7 codIBGE
	,A.no_municipio municipio
	,A.nu_populacao nu_populacao_municipio
	,B.nu_populacao nu_populacao_uf
	,CONCAT (
		A.no_municipio
		,', '
		,A.sg_uf 
		) municipio_uf
FROM temp_CGUSC.sus.tb_ibge A
INNER JOIN temp_CGUSC.sus.tb_ibge_estados B ON B.id_uf = A.id_uf
where id_ibge7 <> '0000000'


-- População UF

SELECT A.sg_uf
	,nu_populacao
FROM temp_CGUSC.sus.tb_ibge_estados A


-- Socios

SELECT A.CpfCnpjSocio cpf
	,A.cnpj
	,A.NomeSocio
	,A.Municipio
	,A.DataEntradaSociedade
	,A.DataExclusaoSociedade
	,A.descricaoQualificacao
	,(
		SELECT count(*)
		FROM temp_CGUSC.dbo.sociosFP B
		WHERE B.DataExclusaoSociedade IS NULL
			AND B.cpfcnpjSocio = A.cpfcnpjSocio
		) AS nu_sociedades
FROM temp_CGUSC.dbo.sociosFP A


-- CpfCadUnico

SELECT CPF_CAD_UNICO cpf
FROM db_CadUnico.dbo.tb_00_consolid
WHERE CPF_CAD_UNICO IN (
		SELECT cpfcnpjSocio
		FROM temp_CGUSC.dbo.sociosFP
		)


-- CadUnico

SELECT *
FROM temp_CGUSC.dbo.BI_socios_cadunico


/* Criar tabela local com:

drop table if exists temp_CGUSC.dbo.BI_socios_cadunico
SELECT A.cpfcnpjSocio
    ,A.cnpj
    ,C.municipio
    ,C.uf
    ,C.valor_sem_comprovacao
    ,B.VLR_RENDA_FAM renda_familiar
    ,B.DAT_ATUAL_FAM data_atualizacao_familiar
    ,(
        SELECT count(*)
        FROM temp_CGUSC.dbo.sociosFP D
        WHERE D.DataExclusaoSociedade IS NULL
            AND D.cpfcnpjSocio = A.cpfcnpjSocio
        ) AS num_sociedades
into temp_CGUSC.dbo.BI_socios_cadunico
FROM temp_CGUSC.dbo.sociosFP A

INNER JOIN temp_CGUSC.dbo.BI_socios_cadunico B ON B.CPF_CAD_UNICO = A.cpfcnpjSocio
LEFT JOIN temp_CGUSC.dbo.resultado_Sentinela_2021_2024 C ON C.cnpj = A.cnpj*/

--utilizar no BI o objeto BI_socios_cadunico




-- d_credenciamento

DROP TABLE

IF EXISTS #temp
	SELECT A.NU_CNPJ cnpj
		,A.ST_BLOQUEIO
		,A.CO_MOTIVO_BLOQUEIO
		,C.DS_MOTIVO_BLOQUEIO
		,A.DT_BLOQUEIO
		-- Campo situação_DAF veio de um arquivo Excel que eles nos enviaram na época, no momento não temos essa informação.
	INTO #temp
	FROM [db_FarmaciaPopular].[carga_2024].AU_TBFARMACIA A
	INNER JOIN temp_CGUSC.dbo.resultado_Sentinela_2021_2024 B ON B.cnpj = A.NU_CNPJ
	LEFT JOIN [db_FarmaciaPopular].dbo.tb_motivo_bloqueio C ON C.CO_MOTIVO_BLOQUEIO = A.CO_MOTIVO_BLOQUEIO
	INNER JOIN (
		SELECT Aa.NU_CNPJ
			,max(Aa.DT_BLOQUEIO) max_dt_bloqueio
		FROM [db_FarmaciaPopular].[carga_2024].AU_TBFARMACIA Aa
		GROUP BY Aa.nu_cnpj
		) t ON t.max_dt_bloqueio = A.DT_BLOQUEIO
		AND t.NU_CNPJ = A.NU_CNPJ
	WHERE st_bloqueio IS NOT NULL
		AND A.CO_MOTIVO_BLOQUEIO IS NOT NULL
	GROUP BY A.NU_CNPJ
		,C.DS_MOTIVO_BLOQUEIO
		,A.CO_MOTIVO_BLOQUEIO
		,A.dt_bloqueio
		,A.ST_BLOQUEIO

DROP TABLE

IF EXISTS #cnpjs_duplicados
	SELECT cnpj
	INTO #cnpjs_duplicados
	FROM #temp A
	GROUP BY A.CNPJ
	HAVING count(*) > 1

SELECT *
FROM #temp
WHERE cnpj NOT IN (
		SELECT cnpj
		FROM #cnpjs_duplicados
		)



--  dike_farmaciapopular

SELECT A.cnpj, A.IRT indice_risco_total, A.grau_risco_relativo
  FROM [db_dike_cnpj].[dbo].[07_risco_empresas_completa] A
  where A.cnpj in (select B.cnpj from temp_CGUSC.dbo.processamentosFP B)


-- f_Resultados

SELECT 
    SUBSTRING(cnpj,1,8) AS cnpj_raiz
	,M.cnpj_matriz
	,M.razao_social_matriz
	,M.porte_matriz
    ,a.cnpj
	,a.razao_social
	,a.CodPorteEmpresa
	,p.descricao AS porte_empresa
	,qnt_vendas
	,qnt_vendas_sem_comprovacao
	,valor_vendas
	,valor_sem_comprovacao
	,id_ibge7 AS codibge
	-- Tratar casos identificados com percentual maior do que 100%
	,CASE 
		WHEN percentual_sem_comprovacao > 1 THEN 1
		ELSE percentual_sem_comprovacao
	END AS percentual
	,CASE
		WHEN percentual_sem_comprovacao = 0 THEN '0'
		WHEN percentual_sem_comprovacao <= 0.1 THEN '<=10%'
		WHEN percentual_sem_comprovacao <= 0.2 THEN '>10 e <=20%'
		WHEN percentual_sem_comprovacao <= 0.3 THEN '>20 e <=30%' 
		WHEN percentual_sem_comprovacao <= 0.4 THEN '>30 e<=40%' 
		WHEN percentual_sem_comprovacao <= 0.5 THEN '>40 e <=50%' 
		WHEN percentual_sem_comprovacao <= 0.6 THEN '>50 e <=60%' 
		WHEN percentual_sem_comprovacao <= 0.7 THEN '>60 e <=70%' 
		WHEN percentual_sem_comprovacao <= 0.8 THEN '>70 e <=80%' 
		WHEN percentual_sem_comprovacao <= 0.9 THEN '>80 e <=90%' 
		ELSE '>90 e <=100%'
	END AS 'Categoria de Risco'
	,num_estabelecimentos_mesmo_municipio
	,num_meses_movimentacao AS num_meses
	,MedicamentosporCupom AS MediaMedicamentosPorCupom
	,percentual4Medicamentos AS percentual4ouMaisMedicamentosporCupom
	,valor_ticketMedio AS ValorTicketMedio
	,percentual_falecidos
	,municipio
	,uf
	,nu_populacao
	,nu_autorizacoes
    ,valor_multa
FROM temp_CGUSC.dbo.resultado_Sentinela_2021_2024 AS a
LEFT JOIN temp_CGUSC.dbo.CNPJ_matrizes AS M
  ON M.cnpj_raiz = LEFT(a.cnpj, 8)
LEFT JOIN [temp_CGUSC].[dbo].[porteEmpresa] as p
  ON a.CodPorteEmpresa = p.codPorteEmpresa

-- comparativo_farmacias

SELECT 
    LEFT(A.cnpj, 8)               AS cnpj_raiz
    ,M.cnpj_matriz                    AS cnpj_matriz
    ,A.cnpj                        AS cnpj_filial
	,M.razao_social_matriz           AS razao_social_matriz
    ,temp_CGUSC.dbo.FirstLetterUpperCase(B.razao_social)           AS razao_social_filial
    ,A.valor_sem_comprovacao / A.valor_vendas AS percentual_sem_comprovacao_2015_2020
	-- Tratar casos identificados com percentual maior do que 100%
	,CASE 
		WHEN B.valor_sem_comprovacao / B.valor_vendas > 1 THEN 1
		ELSE B.valor_sem_comprovacao / B.valor_vendas
	END AS percentual_sem_comprovacao_2021_2023
	,A.valor_vendas AS vendas_2015_2020
	,A.valor_sem_comprovacao AS sem_comprovacao_2015_2020
	,B.valor_vendas AS vendas_2021_2023
	,B.valor_sem_comprovacao AS sem_comprovacao_2021_2023
FROM temp_CGUSC.dbo.resultado_processamento_brasil A
INNER JOIN temp_CGUSC.dbo.resultado_Sentinela_2021_2024 B 
    ON B.cnpj = A.cnpj

   
LEFT JOIN temp_CGUSC.dbo.CNPJ_matrizes AS M -- razão social da matriz 
  ON M.cnpj_raiz = LEFT(A.cnpj, 8)



-- f_Resultado_2015_2020

SELECT 
    SUBSTRING(cnpj,1,8) AS cnpj_raiz
	,M.cnpj_matriz
	,M.razao_social_matriz
    ,cnpj
	,razao_social
	,qnt_vendas
	,qnt_vendas_sem_comprovacao
	,valor_vendas
	,valor_sem_comprovacao
	,codibge
	,p.descricao AS porte_empresa
FROM temp_CGUSC.dbo.resultado_processamento_brasil AS r

LEFT JOIN temp_CGUSC.dbo.CNPJ_matrizes AS M
  ON M.cnpj_raiz = LEFT(cnpj, 8)

LEFT JOIN [temp_CGUSC].[dbo].[porteEmpresa] as p
  ON r.CodPorteEmpresa = p.codPorteEmpresa


-- d_categoria_risco

SELECT
    r.id_ibge7                                               AS codIBGE,

    /* ─────────── índice numérico 0 … 10 ─────────── */
    CASE
        WHEN r.percentual_sem_comprovacao = 0   THEN 0
        WHEN r.percentual_sem_comprovacao <= 0.1 THEN 1
        WHEN r.percentual_sem_comprovacao <= 0.2 THEN 2
        WHEN r.percentual_sem_comprovacao <= 0.3 THEN 3
        WHEN r.percentual_sem_comprovacao <= 0.4 THEN 4
        WHEN r.percentual_sem_comprovacao <= 0.5 THEN 5
        WHEN r.percentual_sem_comprovacao <= 0.6 THEN 6
        WHEN r.percentual_sem_comprovacao <= 0.7 THEN 7
        WHEN r.percentual_sem_comprovacao <= 0.8 THEN 8
        WHEN r.percentual_sem_comprovacao <= 0.9 THEN 9
        ELSE 10
    END                                                     AS d_indiceRisco,

    /* ─────────── texto da faixa (igual ao Power BI) ─────────── */
    CASE
        WHEN r.percentual_sem_comprovacao = 0   THEN '0'
        WHEN r.percentual_sem_comprovacao <= 0.1 THEN '<=10%'
        WHEN r.percentual_sem_comprovacao <= 0.2 THEN '>10 e <=20%'
        WHEN r.percentual_sem_comprovacao <= 0.3 THEN '>20 e <=30%'
        WHEN r.percentual_sem_comprovacao <= 0.4 THEN '>30 e <=40%'
        WHEN r.percentual_sem_comprovacao <= 0.5 THEN '>40 e <=50%'
        WHEN r.percentual_sem_comprovacao <= 0.6 THEN '>50 e <=60%'
        WHEN r.percentual_sem_comprovacao <= 0.7 THEN '>60 e <=70%'
        WHEN r.percentual_sem_comprovacao <= 0.8 THEN '>70 e <=80%'
        WHEN r.percentual_sem_comprovacao <= 0.9 THEN '>80 e <=90%'
        ELSE '>90 e <=100%'
    END                                                     AS categoria_risco_txt,

    COUNT (DISTINCT r.cnpj)                                 AS qtde_estab_faixa,
    MAX   (r.num_estabelecimentos_mesmo_municipio)          AS qtde_estab_total
FROM
    temp_CGUSC.dbo.resultado_Sentinela_2021_2024  AS r
GROUP BY
    r.id_ibge7,
    CASE
        WHEN r.percentual_sem_comprovacao = 0   THEN 0
        WHEN r.percentual_sem_comprovacao <= 0.1 THEN 1
        WHEN r.percentual_sem_comprovacao <= 0.2 THEN 2
        WHEN r.percentual_sem_comprovacao <= 0.3 THEN 3
        WHEN r.percentual_sem_comprovacao <= 0.4 THEN 4
        WHEN r.percentual_sem_comprovacao <= 0.5 THEN 5
        WHEN r.percentual_sem_comprovacao <= 0.6 THEN 6
        WHEN r.percentual_sem_comprovacao <= 0.7 THEN 7
        WHEN r.percentual_sem_comprovacao <= 0.8 THEN 8
        WHEN r.percentual_sem_comprovacao <= 0.9 THEN 9
        ELSE 10
    END,
    CASE
        WHEN r.percentual_sem_comprovacao = 0   THEN '0'
        WHEN r.percentual_sem_comprovacao <= 0.1 THEN '<=10%'
        WHEN r.percentual_sem_comprovacao <= 0.2 THEN '>10 e <=20%'
        WHEN r.percentual_sem_comprovacao <= 0.3 THEN '>20 e <=30%'
        WHEN r.percentual_sem_comprovacao <= 0.4 THEN '>30 e <=40%'
        WHEN r.percentual_sem_comprovacao <= 0.5 THEN '>40 e <=50%'
        WHEN r.percentual_sem_comprovacao <= 0.6 THEN '>50 e <=60%'
        WHEN r.percentual_sem_comprovacao <= 0.7 THEN '>60 e <=70%'
        WHEN r.percentual_sem_comprovacao <= 0.8 THEN '>70 e <=80%'
        WHEN r.percentual_sem_comprovacao <= 0.9 THEN '>80 e <=90%'
        ELSE '>90 e <=100%'
    END;


 