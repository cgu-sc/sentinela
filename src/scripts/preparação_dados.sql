

--**************************************************************************************************************************************
-- Criar lista de CNPJs que serão analisados
--**************************************************************************************************************************************

DROP TABLE IF EXISTS temp_CGUSC.dbo.lista_cnpjs
SELECT DISTINCT A.cnpj
INTO temp_CGUSC.dbo.lista_cnpjs
FROM db_farmaciaPopular.dbo.relatorio_movimentacao_2015_2024 A
WHERE A.data_hora BETWEEN '2015-07-01' AND '2024-12-10'
GROUP BY A.cnpj;




--**************************************************************************************************************************************
-- Particionamento dos CNPJs para processamento em pequenos lotes
--**************************************************************************************************************************************

-- Verifica se a tabela temporária existe e a remove, se necessário
IF OBJECT_ID('temp_CGUSC.dbo.classif', 'U') IS NOT NULL
    DROP TABLE temp_CGUSC.dbo.classif;

-- Cria uma tabela temporária com CNPJs classificados em 50 grupos
SELECT 
    cnpj,
    NTILE(50) OVER (ORDER BY cnpj) AS classif
INTO temp_CGUSC.dbo.classif
FROM temp_CGUSC.dbo.lista_cnpjs;

-- Cria índice no campo classif para otimizar JOINs
CREATE NONCLUSTERED INDEX IX_classif_classif 
ON temp_CGUSC.dbo.classif (classif) 
INCLUDE (cnpj);





--***************************************************************************************************************
--Criar Tabela com CNPJ da Farmácia e a data da primeira venda
--***************************************************************************************************************



-- Verifica se a tabela temporária existe e a remove, se necessário
IF OBJECT_ID('temp_CGUSC.dbo.farmaciasInicioVendas', 'U') IS NOT NULL
    DROP TABLE temp_CGUSC.dbo.farmaciasInicioVendas;

-- Cria uma tabela temporária com o CNPJ e a data inicial de vendas
SELECT 
    A.cnpj,
    MIN(A.data_hora) AS datavendainicial
INTO temp_CGUSC.dbo.farmaciasInicioVendas
FROM db_farmaciaPopular.dbo.relatorio_movimentacao_2015_2024 A
INNER JOIN temp_CGUSC.dbo.lista_cnpjs B 
    ON B.cnpj = A.cnpj
WHERE A.data_hora BETWEEN '2015-07-01' AND '2024-12-10'
GROUP BY A.cnpj;




--***************************************************************************************************************
--Criar lista de Contatos das Farmácias Analisadas. Informação utilizada na geração dos relatórios.
--***************************************************************************************************************

-- Verifica se a tabela temporária existe e a remove, se necessário
IF OBJECT_ID('temp_CGUSC.dbo.ContatoFarmacia', 'U') IS NOT NULL
    DROP TABLE temp_CGUSC.dbo.ContatoFarmacia;

-- Seleciona os dados de contato das farmácias e insere na tabela temporária
SELECT 
    B.cnpj, -- CNPJ da lista de entrada
    COALESCE(A.nu_ddd, '#') AS nu_ddd, -- DDD, substituindo nulos por '#'
    COALESCE(A.nu_telefone, '#') AS nu_telefone, -- Telefone, substituindo nulos por '#'
    COALESCE(A.ds_email, '#') AS ds_email -- E-mail, substituindo nulos por '#'
INTO temp_CGUSC.dbo.ContatoFarmacia -- Insere o resultado na tabela temporária
FROM temp_CGUSC.dbo.lista_cnpjs B -- Tabela com a lista de CNPJs a serem consultados
LEFT JOIN (
    -- Subconsulta para combinar dados das duas tabelas de farmácia e evitar duplicatas
    SELECT 
        NU_CNPJ, 
        NU_DDD, 
        NU_TELEFONE, 
        DS_EMAIL,
        -- Atribui um número de linha para cada registro por CNPJ, ordenando por prioridade da fonte
        ROW_NUMBER() OVER (PARTITION BY NU_CNPJ ORDER BY 
            CASE WHEN fonte = 'carga_2024' THEN 1 ELSE 2 END) AS rn
    FROM (
        -- Combina os dados das duas tabelas de farmácia
        SELECT 
            NU_CNPJ, 
            NU_DDD, 
            NU_TELEFONE, 
            DS_EMAIL, 
            'carga_2024' AS fonte -- Identifica a origem como carga_2024
        FROM db_farmaciaPopular.carga_2024.tb_farmacia
        WHERE NU_CNPJ IS NOT NULL -- Filtra apenas registros com CNPJ válido
        UNION ALL
        SELECT 
            NU_CNPJ, 
            NU_DDD, 
            NU_TELEFONE, 
            DS_EMAIL, 
            'dbo' AS fonte -- Identifica a origem como dbo
        FROM db_farmaciaPopular.dbo.tb_farmacia
        WHERE NU_CNPJ IS NOT NULL -- Filtra apenas registros com CNPJ válido
    ) combined -- Nome da subconsulta que combina os dados
) A 
    ON B.cnpj = A.NU_CNPJ -- Junta com a lista de CNPJs usando LEFT JOIN
WHERE A.rn = 1 OR A.rn IS NULL; -- Seleciona apenas o primeiro registro por CNPJ ou nulos (sem correspondência)







--**************************************************************************************************************************************
-- criar tabelas [processamentosFP], dadosProcessamentosFP e movimentacaoMensalCodigoBarraFP
--**************************************************************************************************************************************





-- Verifica e remove a tabela temporária dadosProcessamentosFP, se existir
IF OBJECT_ID('temp_cgusc.dbo.dadosProcessamentosFP', 'U') IS NOT NULL
    DROP TABLE temp_cgusc.dbo.dadosProcessamentosFP;

-- Verifica e remove a tabela temporária movimentacaoMensalCodigoBarraFP, se existir
IF OBJECT_ID('temp_cgusc.dbo.movimentacaoMensalCodigoBarraFP', 'U') IS NOT NULL
    DROP TABLE temp_cgusc.dbo.movimentacaoMensalCodigoBarraFP;

-- Verifica e remove a tabela temporária processamentosFP, se existir
IF OBJECT_ID('temp_cgusc.dbo.processamentosFP', 'U') IS NOT NULL
    DROP TABLE temp_cgusc.dbo.processamentosFP;
    
IF OBJECT_ID('dbo.memoria_calculo_consolidadaFP', 'U') IS NOT NULL
    DROP TABLE dbo.memoria_calculo_consolidadaFP;




CREATE TABLE dbo.memoria_calculo_consolidadaFP (
    id BIGINT IDENTITY(1,1) PRIMARY KEY,
    id_processamento BIGINT NOT NULL, -- Link com a tabela processamentosFP
    cnpj VARCHAR(14) NOT NULL,
    
    -- O "Coração" da Auditoria: Todo o cálculo do Python em formato JSON
    dados_comprimidos VARBINARY(MAX),
    
    data_carga DATETIME DEFAULT GETDATE()
);

-- Índice para recuperação rápida por CNPJ (ex: para refazer um Excel específico)
CREATE NONCLUSTERED INDEX IDX_Memoria_CNPJ ON dbo.memoria_calculo_consolidadaFP(cnpj);



-- Cria a tabela temporária processamentosFP para armazenar dados de processamento de farmácias      
CREATE TABLE temp_cgusc.[dbo].[processamentosFP](
	[id] [int] PRIMARY KEY IDENTITY(1,1) NOT NULL,
	[cnpj] [varchar](max) NOT NULL,
	razao_social [varchar](max)  NULL,
	nome_fantasia [varchar](max)  NULL,
	municipio [varchar](max)  NULL,
	uf [varchar](max)  NULL,
	[periodo_inicial] [datetime2] NOT NULL,
	[periodo_final] [datetime2] NOT NULL,
	[data_processamento] [datetime2] NOT NULL,
	situacao integer not null,
    status_detalhado VARCHAR(500),  
    tempo_processamento_segundos DECIMAL(10,2), 
    total_registros_processados INT,  
    total_medicamentos INT
	);

-- Cria a tabela temporária dadosProcessamentosFP para armazenar detalhes dos processamentos
CREATE TABLE temp_cgusc.[dbo].dadosProcessamentosFP(
	[id] INT Identity(1,1) Primary Key,
	[id_processamento] INT NULL,
	[codigo_barra] [varchar](max) NOT NULL,
	[tipo] [char](1) NOT NULL,
	[periodo_inicial] [date] NULL,
	[periodo_inicial_nao_comprovacao] [date] NULL,
	[periodo_final] [date] NULL,
	[estoque_inicial] [int] NULL,
	[estoque_final] [int] NULL,
	[vendas_periodo] [int] NULL,
	[vendas_sem_comprovacao] [int] NULL,
	[valor_movimentado] [decimal](11, 2) NULL,
	[valor_sem_comprovacao] [decimal](11, 2) NULL,
	[data_aquis_dev_estoq] [date] NULL,
	[qnt_aquis_dev] [int] NULL,
	[numero_nfe] [varchar](max) NULL,
	constraint fk2_id_processamento_movimentacao foreign key (id_processamento) references temp_cgusc.[dbo].[processamentosFP] (id)
	);

-- Cria a tabela temporária movimentacaoMensalCodigoBarraFP para movimentações mensais por código de barra
	drop table if exists temp_cgusc.[dbo].movimentacaoMensalCodigoBarraFP	   
	CREATE TABLE temp_cgusc.[dbo].movimentacaoMensalCodigoBarraFP(
	[id] INT Identity(1,1) Primary Key,
	[id_processamento] INT NULL,
	[codigo_barra] [varchar](max) NOT NULL,
	[periodo] [date] NULL,
	[qnt_vendas] [int] NULL,
	[qnt_vendas_sem_comprovacao] [int] NULL,
	[valor_vendas] [decimal](11, 2) NULL,
	[valor_sem_comprovacao] [decimal](11, 2) NULL,
	constraint fk2_id_processamento_movimentacao_codigo_barra foreign key (id_processamento) references temp_cgusc.[dbo].[processamentosFP] (id))


	
--------------------------------------------------------------
-- Criação da Tabela dos Socios das Farmácias
--------------------------------------------------------------
   
   
-- Cria a tabela temporária tb_sociosFP com informações dos sócios
drop table if exists temp_CGUSC.dbo.tb_sociosFP

SELECT 
    A.cpfcnpjSocio AS cpf_cnpj_socio,
    A.cnpj,
    A.indSocio AS indicador_socio,
    temp_CGUSC.dbo.InitCapEachWord(A.nomeSocio) AS nome_socio,
    temp_CGUSC.dbo.InitCapEachWord(A.descricaoLogradouro) AS descricao_logradouro,
    A.numero,
    temp_CGUSC.dbo.InitCapEachWord(A.complemento) AS complemento,
    temp_CGUSC.dbo.InitCapEachWord(A.bairro) AS bairro,
    A.cep,
    temp_CGUSC.dbo.InitCapEachWord(C.municipio) AS municipio,
    A.dataEntradaSociedade AS data_entrada_sociedade,
    A.dataExclusaoSociedade AS data_exclusao_sociedade,
    A.percentualQualificacao AS percentual_qualificacao,
    temp_CGUSC.dbo.InitCapEachWord(A.descQualificacaoSocio) AS descricao_qualificacao,
    GETDATE() AS data_processamento
INTO temp_CGUSC.dbo.tb_sociosFP
FROM db_CNPJ.dbo.socios A
LEFT JOIN db_CNPJ.dbo.Municipio B 
    ON B.SkMunicipio = A.CodMunicipio
LEFT JOIN temp_CGUSC.dbo.municipiosIBGE C 
    ON C.codibge = B.CodIbge
INNER JOIN db_CNPJ.dbo.CNPJ D 
    ON D.cnpj = A.cnpj
INNER JOIN temp_CGUSC.dbo.lista_cnpjs E
    ON A.cnpj = E.cnpj    
WHERE 
    A.dataExclusaoSociedade IS NULL
    AND A.percentualQualificacao > 0
    AND D.SituacaoCadastral = 2;
   
   
   
-- Geração dos dados básicos das farmácias 

DROP TABLE

IF EXISTS #tempDadosFarmacias
	SELECT A.[cnpj]
		,[indMatriz]
		,temp_CGUSC.dbo.InitCapEachWord([RazaoSocial]) AS razaoSocial
		,temp_CGUSC.dbo.InitCapEachWord([NomeFantasia]) AS nomeFantasia
		,A.CodPorteEmpresa
		,temp_CGUSC.dbo.InitCapEachWord([TipoLogradouro]) AS tipoLogradouro
		,temp_CGUSC.dbo.InitCapEachWord([Logradouro]) AS logradouro
		,[Numero]
		,temp_CGUSC.dbo.InitCapEachWord([Complemento]) AS complemento
		,temp_CGUSC.dbo.InitCapEachWord([Bairro]) AS bairro
		,try_cast(cep as varchar(8)) cep
		,F.codibge
		,F.municipio
		,F.uf
		,F.populacao2019
		,[IndPossuiSocio]
		,[SituacaoCadastral]
		,temp_CGUSC.dbo.InitCapEachWord(C.[ds_situacao_cnpj]) AS descricaoSituacaoCadastral
		,[DataSituacaoCadastral]
		,[CodNaturezaJuridica]
		,temp_CGUSC.dbo.InitCapEachWord(B.DescNaturezaJuridica) AS natuezaJuridica
		,[CpfResponsavel]
		,temp_CGUSC.dbo.InitCapEachWord([NomeResponsavel]) AS nomeResponsavel
		,[QualificacaoResponsavel]
		,temp_CGUSC.dbo.InitCapEachWord(D.DescricaoQualificacao) AS descricaoQualificacaoResponsavel
		,GETDATE() AS data_processamento
	INTO #tempDadosFarmacias
	FROM [db_CNPJ].[dbo].[cnpj] A
	LEFT JOIN [db_CNPJ].[dbo].naturezaJuridica B ON B.idNaturezaJuridica = A.CodNaturezaJuridica
	LEFT JOIN [db_CNPJ].[dbo].[dime_situacao_cadastral_cnpj] C ON C.cd_situacao_cnpj = A.SituacaoCadastral
	LEFT JOIN [db_CNPJ].[dbo].qualificacao D ON D.idQualificacao = A.QualificacaoResponsavel
	LEFT JOIN [db_CNPJ].[dbo].Municipio E ON E.SkMunicipio = A.CodMunicipio
	LEFT JOIN temp_CGUSC.dbo.municipiosIBGE F ON F.codibge = E.CodIbge
    INNER JOIN temp_CGUSC.dbo.lista_cnpjs G ON A.cnpj = G.cnpj  



 DROP TABLE

IF EXISTS #tempDadosFarmacias2
	SELECT [cnpj]
		,[indMatriz]
		,[razaoSocial]
		,[nomeFantasia]
		,CodPorteEmpresa
		,[tipoLogradouro]
		,[logradouro]
		,[numero]
		,[complemento]
		,[bairro]
		,RIGHT('00000000' + CONVERT(VARCHAR(8), LTRIM(RTRIM(cep))), 8) cep
		,[codibge]
		,[municipio]
		,uf
		,populacao2019
		,[indPossuiSocio]
		,[situacaoCadastral]
		,[descricaoSituacaoCadastral] AS situacaoReceita
		,[dataSituacaoCadastral]
		,[codNaturezaJuridica]
		,[natuezaJuridica]
		,[cpfResponsavel]
		,[nomeResponsavel]
		,[qualificacaoResponsavel]
		,[descricaoQualificacaoResponsavel]
		,[data_processamento]
		,CASE 
			WHEN outrasSociedades > 0
				THEN 'Sim'
			WHEN outrasSociedades = 0
				THEN 'Não'
			END AS outrasSociedades
	INTO #tempDadosFarmacias2
	FROM (
		SELECT A.*
			,(
				SELECT count(*) AS outros_vinculos
				FROM (
					SELECT cnpj
					FROM temp_CGUSC.dbo.tb_sociosFP sub2
					WHERE sub2.cpf_cnpj_Socio IN (
							SELECT sub.cpf_cnpj_Socio
							FROM temp_CGUSC.dbo.tb_sociosFP sub
							WHERE sub.cnpj = A.cnpj
							)
						AND sub2.cnpj IN (
							SELECT cnpj
							FROM #tempDadosFarmacias
							GROUP BY cnpj
							)
					) AS t1
				WHERE t1.cnpj <> A.cnpj
				) AS outrasSociedades
		FROM #tempDadosFarmacias A
		) AS t1

ALTER TABLE #tempDadosFarmacias2 ADD id BIGINT IDENTITY;

ALTER TABLE #tempDadosFarmacias2 ADD latitude DECIMAL(9, 6);

ALTER TABLE #tempDadosFarmacias2 ADD longitude DECIMAL(9, 6);

ALTER TABLE #tempDadosFarmacias2 ADD CONSTRAINT pkdadosFarmacias PRIMARY KEY (id)


DROP TABLE

IF EXISTS #tempDatasInicialeFinalMovimentacao
	SELECT A.cnpj
		,min(A.data_hora) dataInicialDadosMovimentacao
		,max(A.data_hora) dataFinalDadosMovimentacao
	INTO #tempDatasInicialeFinalMovimentacao
	FROM [db_FarmaciaPopular].[dbo].[relatorio_movimentacao_2015_2024] A
	GROUP BY A.cnpj

DROP TABLE

IF EXISTS temp_CGUSC.dbo.dadosFarmaciasFP
	SELECT A.*
		,B.dataInicialDadosMovimentacao
		,B.dataFinalDadosMovimentacao
	INTO temp_CGUSC.dbo.dadosFarmaciasFP
	FROM #tempDadosFarmacias2 A
	LEFT JOIN #tempDatasInicialeFinalMovimentacao B ON B.cnpj = A.cnpj



---------------------------------------------------------------------------------------------------------------
-- Gerar Lista de CNPJs e Endereços.
-- Arquivo deve ser salvo em XLS para ser lido no script python Coordenadas.py, a fim de se obter as coordenadas de cada 
-- estabelecimento
----------------------------------------------------------------------------------------------------------------


SELECT A.cnpj
	,isnull(A.logradouro, '') + ', ' + try_cast(isnull(A.numero, '') AS VARCHAR(50)) + ', ' + isnull(A.bairro, '') + ', ' + isnull(A.municipio, '') + ', ' + isnull(A.uf, '') AS endereco
FROM temp_CGUSC.dbo.dadosFarmaciasFP A

----------------------------------------------------------------------------------------------------------------------




----------------------------------------------------------------------------------------------------------------------
-- Após fazer a carga das coordenadas de cada CNPJ na tabela temp_CGUSC.dbo.coordenadas, atualizar a tabela dadosFarmaciasFP.
-- com os dados de latitude e longitude
----------------------------------------------------------------------------------------------------------------------
UPDATE farmacias -- Alias para a tabela de destino
SET
    farmacias.latitude = coords.latitude,
    farmacias.longitude = coords.longitude
FROM
    temp_CGUSC.dbo.dadosFarmaciasFP AS farmacias -- Tabela que será atualizada (destino)
INNER JOIN
    temp_CGUSC.dbo.coordenadas AS coords -- Tabela com os dados de origem
ON
    farmacias.CNPJ = coords.CNPJ; -- Condição de junção (chave)





-- definir os estoques iniciais com critério da soma das duas últimas aquisições anteriores a primeira venda na base de --producao



DROP TABLE IF EXISTS TEMP_CGUSC.dbo.farmacia_inicio_venda_gtin
select a.cnpj, a.codigo_barra, min(data_hora) as data_inicio_venda
into TEMP_CGUSC.dbo.farmacia_inicio_venda_gtin
from FROM db_farmaciaPopular.dbo.relatorio_movimentacao_2015_2024 A
inner join temp_CGUSC.dbo.medicamentosPatologiaFP B on B.codigo_barra = A.codigo_barra
inner join temp_CGUSC.dbo.lista_cnpjs C on C.cnpj = A.cnpj
WHERE 
a.data_hora >= '2015-07-01' and a.data_hora <= '2024-12-10'
group by A.cnpj,A.codigo_barra


CREATE NONCLUSTERED INDEX indiceCodigoBarra ON TEMP_CGUSC.dbo.farmacia_inicio_venda_gtin(codigo_barra)
CREATE NONCLUSTERED INDEX indicecnpj ON TEMP_CGUSC.dbo.farmacia_inicio_venda_gtin(cnpj)
CREATE NONCLUSTERED INDEX indiceDataHora ON TEMP_CGUSC.dbo.farmacia_inicio_venda_gtin(data_inicio_venda)




drop table if exists #datas_estoques_inicio_contagem
select A.cnpj as cnpj_estabelecimento,A.codigo_barra,
DATEADD(m,-6,data_inicio_venda) as 'data_estoque_inicial',
DATEADD(d,-1,data_inicio_venda) as 'data_estoque_final'
into #datas_estoques_inicio_contagem
from temp_CGUSC.dbo.farmacia_inicio_venda_gtin A 


drop table if exists #notas_estoque_inicialFP
select A.destinatarioNFE as cnpj_estabelecimento,codigoBarra as codigo_barra, A.numeroNFE, A.dataEmissaoNFE, A.quantidade
into #notas_estoque_inicialFP
from db_farmaciapopular_nf.dbo.aquisicoesFazenda_2015_2025 A
inner join #datas_estoques_inicio_contagem B on B.cnpj_estabelecimento = A.destinatarioNFE and B.codigo_barra = A.codigoBarra
where A.dataEmissaoNFE>=B.data_estoque_inicial and A.dataEmissaoNFE<=B.data_estoque_final and A.tipooperacao = 1


CREATE NONCLUSTERED INDEX index1 ON #notas_estoque_inicialFP(cnpj_estabelecimento)
CREATE NONCLUSTERED INDEX index2 ON #notas_estoque_inicialFP(codigo_barra)
CREATE NONCLUSTERED INDEX index3 ON #notas_estoque_inicialFP(dataEmissaoNFE)


drop table if exists #notas_estoque_inicialFP_temp2
select cnpj_estabelecimento,codigo_barra,numeroNFE,dataEmissaoNFE, quantidade,
    ROW_NUMBER() OVER (
        PARTITION BY codigo_barra,cnpj_estabelecimento
        ORDER BY dataEmissaoNFE desc
    ) row_num
into #notas_estoque_inicialFP_temp2
from #notas_estoque_inicialFP


CREATE NONCLUSTERED INDEX index1 ON #notas_estoque_inicialFP_temp2(cnpj_estabelecimento)
CREATE NONCLUSTERED INDEX index2 ON #notas_estoque_inicialFP_temp2(codigo_barra)
CREATE NONCLUSTERED INDEX index3 ON #notas_estoque_inicialFP_temp2(dataEmissaoNFE)

drop table if exists temp_CGUSC.dbo.estoque_inicialFP
select cnpj_estabelecimento,a.codigo_barra,sum(quantidade) as estoque_inicial, b.data_inicio_venda as 'data_estoque_inicial' 
into temp_CGUSC.dbo.estoque_inicialFP
from #notas_estoque_inicialFP_temp2 A
inner join temp_CGUSC.dbo.farmacia_inicio_venda_gtin B on B.cnpj = A.cnpj_estabelecimento and B.codigo_barra = A.codigo_barra
where row_num < 3 
group by a.cnpj_estabelecimento,a.codigo_barra,b.data_inicio_venda
order by a.codigo_barra asc

CREATE NONCLUSTERED INDEX index1 ON temp_CGUSC.dbo.estoque_inicialFP(cnpj_estabelecimento)
CREATE NONCLUSTERED INDEX index2 ON temp_CGUSC.dbo.estoque_inicialFP(codigo_barra)


-- Salvar as notas de fiscais de aquisição consideradas na Estimativa do Estoque Inicial

drop table if exists temp_CGUSC.dbo.notas_estoque_inicialFP
select A.cnpj_estabelecimento,A.quantidade as qnt, A.codigo_barra, A.dataEmissaoNFE, A.numeroNFE, b.estoque_inicial
into temp_CGUSC.dbo.notas_estoque_inicialFP
from #notas_estoque_inicialFP_temp2 A
inner join temp_CGUSC.dbo.estoque_inicialFP b on b.cnpj_estabelecimento = A.cnpj_estabelecimento and b.codigo_barra = A.codigo_barra
where row_num < 3 

CREATE NONCLUSTERED INDEX index1 ON temp_CGUSC.dbo.notas_estoque_inicialFP(cnpj_estabelecimento)
CREATE NONCLUSTERED INDEX index2 ON temp_CGUSC.dbo.notas_estoque_inicialFP(codigo_barra)
   
   



   
      