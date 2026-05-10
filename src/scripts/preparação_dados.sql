

--**************************************************************************************************************************************
-- Criar lista de CNPJs que serão analisados
--**************************************************************************************************************************************

DROP TABLE IF EXISTS temp_CGUSC.fp.lista_cnpjs
SELECT DISTINCT A.cnpj
INTO temp_CGUSC.fp.lista_cnpjs
FROM db_farmaciaPopular.dbo.relatorio_movimentacao_2015_2024 A
WHERE A.data_hora BETWEEN '2015-07-01' AND '2024-12-10'
GROUP BY A.cnpj;

-- Cria índice clusterizado para performance máxima nos JOINs subsequentes
CREATE CLUSTERED INDEX IX_lista_cnpjs_cnpj 
ON temp_CGUSC.fp.lista_cnpjs (cnpj);




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
FROM temp_CGUSC.fp.lista_cnpjs;

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
INNER JOIN temp_CGUSC.fp.lista_cnpjs B 
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
FROM temp_CGUSC.fp.lista_cnpjs B -- Tabela com a lista de CNPJs a serem consultados
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





-- Verifica e remove a tabela temporária movimentacaoMensalCodigoBarraFP, se existir
IF OBJECT_ID('temp_cgusc.fp.movimentacao_mensal_gtin', 'U') IS NOT NULL
    DROP TABLE temp_cgusc.fp.movimentacao_mensal_gtin;

-- Verifica e remove a tabela temporária processamentosFP, se existir
IF OBJECT_ID('temp_cgusc.fp.processamentosFP', 'U') IS NOT NULL
    DROP TABLE temp_cgusc.fp.processamentosFP;
    
IF OBJECT_ID('fp.memoria_calculo_consolidada', 'U') IS NOT NULL
    DROP TABLE fp.memoria_calculo_consolidada;




CREATE TABLE fp.memoria_calculo_consolidada (
    id BIGINT IDENTITY(1,1) PRIMARY KEY,
    id_processamento BIGINT NOT NULL, -- Link com a tabela processamentosFP
    cnpj VARCHAR(14) NOT NULL,
    
    -- O "Coração" da Auditoria: Todo o cálculo do Python em formato JSON
    dados_comprimidos VARBINARY(MAX),
    
    data_carga DATETIME DEFAULT GETDATE()
);

-- Índice para recuperação rápida por CNPJ (ex: para refazer um Excel específico)
CREATE NONCLUSTERED INDEX IDX_Memoria_CNPJ ON fp.memoria_calculo_consolidada(cnpj);



-- Cria a tabela temporária processamento para armazenar dados de auditoria das farmácias
	drop table if exists temp_cgusc.fp.processamento
	CREATE TABLE temp_cgusc.fp.processamento(
	[id] [int] PRIMARY KEY IDENTITY(1,1) NOT NULL,
	[cnpj] [varchar](14) NOT NULL,
	razao_social [varchar](200) NULL,
	nome_fantasia [varchar](200) NULL,
	municipio [varchar](100) NULL,
	uf [char](2) NULL,
	[periodo_inicial] [date] NOT NULL,
	[periodo_final] [date] NOT NULL,
	[data_processamento] [datetime2] NOT NULL,
	situacao [tinyint] not null,
    status_detalhado VARCHAR(500),  
    tempo_processamento_segundos DECIMAL(10,2), 
    total_registros_processados INT,  
    total_medicamentos INT
	);

	CREATE INDEX ix_processamento_cnpj ON temp_cgusc.fp.processamento(cnpj);
	CREATE INDEX ix_processamento_data ON temp_cgusc.fp.processamento(data_processamento);

-- Cria a tabela temporária dados_processamento_gtin para armazenar detalhes dos processamentos
	drop table if exists temp_cgusc.fp.dados_processamento_gtin
	CREATE TABLE temp_cgusc.fp.dados_processamento_gtin(
	[id] INT Identity(1,1) Primary Key,
	[id_processamento] INT NULL,
	[codigo_barra] [VARCHAR](14) NOT NULL,
	[tipo] [char](1) NOT NULL,
	[periodo_inicial] [date] NULL,
	[periodo_inicial_nao_comprovacao] [date] NULL,
	[periodo_final] [date] NULL,
	[estoque_inicial] [int] NULL,
	[estoque_final] [int] NULL,
	[vendas_periodo] [int] NULL,
	[vendas_sem_comprovacao] [int] NULL,
	[valor_movimentado] [DECIMAL](11, 2) NULL,
	[valor_sem_comprovacao] [DECIMAL](11, 2) NULL,
	[data_aquis_dev_estoq] [date] NULL,
	[qnt_aquis_dev] [int] NULL,
	[numero_nfe] [varchar](max) NULL,
	constraint fk2_id_processamento_movimentacao foreign key (id_processamento) references temp_cgusc.[fp].[processamento](id)
	);

	CREATE INDEX ix_dadosProcGtin_proc ON temp_cgusc.fp.dados_processamento_gtin(id_processamento);

-- Cria a tabela temporária movimentacaoMensalCodigoBarraFP para movimentações mensais por código de barra
	drop table if exists temp_cgusc.fp.movimentacao_mensal_gtin
	CREATE TABLE temp_cgusc.fp.movimentacao_mensal_gtin(
	[id] INT Identity(1,1) Primary Key,
	[id_processamento] INT NULL,
	[codigo_barra] [VARCHAR](14) NOT NULL,
	[periodo] [date] NULL,
	[qnt_vendas] [int] NULL,
	[qnt_vendas_sem_comprovacao] [int] NULL,
	[valor_vendas] [DECIMAL](11, 2) NULL,
	[valor_sem_comprovacao] [DECIMAL](11, 2) NULL,
	constraint fk2_id_processamento_movimentacao_codigo_barra foreign key (id_processamento) references temp_cgusc.[fp].[processamento](id)
	);

	-- Índices para performance de consulta por GTIN e Auditoria
	CREATE INDEX ix_movMensalGtin_proc ON temp_cgusc.fp.movimentacao_mensal_gtin(id_processamento);
	CREATE INDEX ix_movMensalGtin_periodo ON temp_cgusc.fp.movimentacao_mensal_gtin(periodo);


	--------------------------------------------------------------
-- MÓDULO: Farmácia Popular
-- OBJETIVO: Criação das tabelas de dados de farmácias e sócios
-- BASE: db_CNPJ / db_FarmaciaPopular
--------------------------------------------------------------


--------------------------------------------------------------
-- ETAPA 1: Dados cadastrais das farmácias (1ª passagem)
--------------------------------------------------------------

DROP TABLE IF EXISTS #tempDadosFarmacias;

SELECT
    CAST(c.cnpj AS CHAR(14))                                   AS cnpj,
    CAST(c.indMatriz AS CHAR(1))                               AS indMatriz,
    CAST(temp_CGUSC.dbo.InitCapEachWord(LEFT(c.RazaoSocial, 100)) AS VARCHAR(100)) AS razaoSocial,
    CAST(temp_CGUSC.dbo.InitCapEachWord(LEFT(c.NomeFantasia, 100)) AS VARCHAR(100)) AS nomeFantasia,
    CAST(c.CodPorteEmpresa AS TINYINT)                         AS CodPorteEmpresa,
    temp_CGUSC.dbo.InitCapEachWord(c.TipoLogradouro)           AS tipoLogradouro,
    temp_CGUSC.dbo.InitCapEachWord(c.Logradouro)               AS logradouro,
    c.Numero                                                   AS numero,
    temp_CGUSC.dbo.InitCapEachWord(c.Complemento)              AS complemento,
    temp_CGUSC.dbo.InitCapEachWord(c.Bairro)                   AS bairro,
    CAST(c.cep AS CHAR(8))                                     AS cep,
    CAST(ibge.id_ibge7 AS CHAR(7))                             AS codibge,
    CAST(ibge.no_municipio    AS VARCHAR(100))                 AS municipio,
    ibge.sg_uf                                                 AS uf,
    CAST(ibge.nu_populacao    AS INT)                          AS populacao2019,
    CAST(ibge.no_regiao_saude AS VARCHAR(100))                 AS no_regiao_saude,
    CAST(ibge.id_regiao_saude AS VARCHAR(20))                  AS id_regiao_saude,
    c.IndPossuiSocio                                           AS indPossuiSocio,
    CAST(c.SituacaoCadastral AS TINYINT)                       AS situacaoCadastral,
    temp_CGUSC.dbo.InitCapEachWord(sit.ds_situacao_cnpj)       AS descricaoSituacaoCadastral,
    CAST(c.DataSituacaoCadastral AS DATE)                      AS DataSituacaoCadastral,
    CAST(c.DataAbertura AS DATE)                               AS data_abertura,
    CAST(c.CodNaturezaJuridica AS SMALLINT)                    AS CodNaturezaJuridica,
    temp_CGUSC.dbo.InitCapEachWord(nat.DescNaturezaJuridica)   AS natureza_juridica,
    c.CpfResponsavel,
    temp_CGUSC.dbo.InitCapEachWord(c.NomeResponsavel)          AS nome_responsavel,
    c.QualificacaoResponsavel,
    temp_CGUSC.dbo.InitCapEachWord(qua.DescricaoQualificacao)  AS descricaoQualificacaoResponsavel,
    c.CnaeFiscal                                               AS id_cnae_principal,
    temp_CGUSC.dbo.InitCapEachWord(cnae_p.DescSubClasseCNAE)   AS cnae_principal,
    cnae_s_base.idSubClasseCNAE                                AS id_cnae_secundario,
    temp_CGUSC.dbo.InitCapEachWord(cnae_s.DescSubClasseCNAE)   AS cnae_secundario,
    c.Telefone1                                                AS telefone_1,
    c.Telefone2                                                AS telefone_2,
    LOWER(c.CorreioEletronico)                                 AS correio_eletronico,
    GETDATE()                                                  AS data_processamento
INTO #tempDadosFarmacias
FROM temp_CGUSC.fp.lista_cnpjs                     AS lst
INNER JOIN db_CNPJ.dbo.cnpj                            AS c    ON c.cnpj               = lst.cnpj
LEFT JOIN  db_CNPJ.dbo.naturezaJuridica                  AS nat  ON nat.idNaturezaJuridica  = c.CodNaturezaJuridica
LEFT JOIN  db_CNPJ.dbo.dime_situacao_cadastral_cnpj      AS sit  ON sit.cd_situacao_cnpj   = c.SituacaoCadastral
LEFT JOIN  db_CNPJ.dbo.qualificacao                      AS qua  ON qua.idQualificacao      = c.QualificacaoResponsavel
LEFT JOIN  db_CNPJ.dbo.Municipio                         AS mun  ON mun.SkMunicipio         = c.CodMunicipio
LEFT JOIN  temp_CGUSC.fp.dados_ibge                      AS ibge ON ibge.id_ibge7           = mun.CodIbge
LEFT JOIN  db_CNPJ.dbo.SubClasseCNAE                     AS cnae_p ON cnae_p.idSubClasseCNAE = c.CnaeFiscal
LEFT JOIN  (
    SELECT CNPJ, idSubClasseCNAE, ROW_NUMBER() OVER(PARTITION BY CNPJ ORDER BY idSubClasseCNAE) as rn 
    FROM db_CNPJ.dbo.CNAESecundaria
) AS cnae_s_base ON cnae_s_base.CNPJ = lst.cnpj AND cnae_s_base.rn = 1
LEFT JOIN  db_CNPJ.dbo.SubClasseCNAE                     AS cnae_s ON cnae_s.idSubClasseCNAE = cnae_s_base.idSubClasseCNAE;

-- Índice em #tempDadosFarmacias
-- Chave principal de acesso: CNPJ
CREATE INDEX ix_tempFarmacias_cnpj
    ON #tempDadosFarmacias (cnpj);


--------------------------------------------------------------
-- ETAPA 1.1: Enriquecimento — Dados Geográficos e Porte
--------------------------------------------------------------

DROP TABLE IF EXISTS #tempDadosFarmacias2;

SELECT
    f.cnpj,
    f.indMatriz,
    f.razaoSocial,
    f.nomeFantasia,
    f.CodPorteEmpresa,
    f.tipoLogradouro,
    f.logradouro,
    f.numero,
    f.complemento,
    f.bairro,
    RIGHT('00000000' + CONVERT(VARCHAR(8), LTRIM(RTRIM(f.cep))), 8) AS cep,
    f.codibge,
    f.municipio,
    f.uf,
    f.populacao2019,
    f.no_regiao_saude,
    f.id_regiao_saude,
    f.indPossuiSocio,
    f.situacaoCadastral,
    f.descricaoSituacaoCadastral                                     AS situacaoReceita,
    f.data_abertura,
    f.DataSituacaoCadastral                                          AS dataSituacaoCadastral,
    f.CodNaturezaJuridica                                            AS codNaturezaJuridica,
    f.natureza_juridica,
    f.CpfResponsavel                                                 AS cpfResponsavel,
    f.nome_responsavel,
    f.QualificacaoResponsavel                                        AS qualificacaoResponsavel,
    f.descricaoQualificacaoResponsavel,
    f.id_cnae_principal,
    f.cnae_principal,
    f.id_cnae_secundario,
    f.cnae_secundario,
    f.telefone_1,
    f.telefone_2,
    f.correio_eletronico,
    f.data_processamento,
    CASE f.CodPorteEmpresa
        WHEN '01' THEN 'Microempresa (ME)'
        WHEN '03' THEN 'Empresa de Pequeno Porte (EPP)'
        WHEN '05' THEN 'Demais'
        ELSE 'Não Informado'
    END AS ds_porte_empresa
INTO #tempDadosFarmacias2
FROM #tempDadosFarmacias AS f;

-- Colunas de controle e georreferenciamento
ALTER TABLE #tempDadosFarmacias2 ADD id        INT IDENTITY;
ALTER TABLE #tempDadosFarmacias2 ADD latitude  DECIMAL(9, 6);
ALTER TABLE #tempDadosFarmacias2 ADD longitude DECIMAL(9, 6);

ALTER TABLE #tempDadosFarmacias2
    ADD PRIMARY KEY (id);

-- Índice em #tempDadosFarmacias2
-- CNPJ é a chave de negócio usada em todos os JOINs posteriores
CREATE INDEX ix_tempFarmacias2_cnpj
    ON #tempDadosFarmacias2 (cnpj);


--------------------------------------------------------------
-- ETAPA 4: Datas de movimentação por farmácia
--------------------------------------------------------------

DROP TABLE IF EXISTS #tempDatasMovimentacao;

SELECT
    mov.cnpj,
    MIN(mov.data_hora) AS dataInicialDadosMovimentacao,
    MAX(mov.data_hora) AS dataFinalDadosMovimentacao
INTO #tempDatasMovimentacao
FROM db_FarmaciaPopular.dbo.relatorio_movimentacao_2015_2024 AS mov
GROUP BY mov.cnpj;

-- Índice em #tempDatasMovimentacao
-- CNPJ é a única chave de JOIN desta tabela
CREATE INDEX ix_tempDatasMovimentacao_cnpj
    ON #tempDatasMovimentacao (cnpj);


--------------------------------------------------------------
-- ETAPA 5: Tabela final consolidada
--------------------------------------------------------------

DROP TABLE IF EXISTS temp_CGUSC.fp.dados_farmacia;

SELECT
    f.*,
    mov.dataInicialDadosMovimentacao,
    mov.dataFinalDadosMovimentacao,
    cs.VlrCapitalSocial AS capital_social
INTO temp_CGUSC.fp.dados_farmacia
FROM #tempDadosFarmacias2                  AS f
LEFT JOIN #tempDatasMovimentacao           AS mov ON mov.cnpj = f.cnpj
LEFT JOIN db_CNPJ_CapitalSocial.dbo.CNPJ_CapitalSocial AS cs  ON cs.NumCNPJ = f.cnpj;

-- Adiciona a Chave Primária e garante o IDENTITY (se o SELECT INTO não manteve)
-- No SQL Server, o IDENTITY costuma ser mantido no SELECT INTO se a origem for IDENTITY.
-- Vamos apenas garantir a PK e o índice.
ALTER TABLE temp_CGUSC.fp.dados_farmacia
    ADD PRIMARY KEY (id);



-- Índices na tabela final
-- O ID já é Clustered por ser Primary Key.

-- Chave de negócio: CNPJ
CREATE NONCLUSTERED INDEX ix_dadosFarmacia_cnpj
    ON temp_CGUSC.fp.dados_farmacia (cnpj);

-- Filtros geográficos frequentes: UF e município
CREATE INDEX ix_dadosFarmacia_uf_municipio
    ON temp_CGUSC.fp.dados_farmacia (uf, municipio);

-- Georreferenciamento: suporte a queries espaciais aproximadas
CREATE INDEX ix_dadosFarmacia_geo
    ON temp_CGUSC.fp.dados_farmacia (latitude, longitude)
    WHERE latitude IS NOT NULL AND longitude IS NOT NULL;




---------------------------------------------------------------------------------------------------------------
-- Gerar Lista de CNPJs e Endereços.
-- Arquivo deve ser salvo em XLS para ser lido no script python Coordenadas.py, a fim de se obter as coordenadas de cada 
-- estabelecimento
----------------------------------------------------------------------------------------------------------------


SELECT A.cnpj
	,isnull(A.logradouro, '') + ', ' + try_cast(isnull(A.numero, '') AS VARCHAR(50)) + ', ' + isnull(A.bairro, '') + ', ' + isnull(A.municipio, '') + ', ' + isnull(A.uf, '') AS endereco
FROM temp_CGUSC.fp.dados_farmacia A

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
    temp_CGUSC.fp.dados_farmacia AS farmacias -- Tabela que será atualizada (destino)
INNER JOIN
    temp_CGUSC.dbo.coordenadas AS coords -- Tabela com os dados de origem
ON
    farmacias.CNPJ = coords.CNPJ; -- Condição de junção (chave)







--------------------------------------------------------------
-- ETAPA 1.2: Dicionário Central de CPFs (Otimização)
-- Coleta metadados apenas para os CPFs envolvidos neste audit
--------------------------------------------------------------
DROP TABLE IF EXISTS #cpfs_vivos;
SELECT DISTINCT cpf_cnpj_socio AS cpf INTO #cpfs_vivos 
FROM (
    -- CPFs das farmácias (Responsáveis)
    SELECT cpfResponsavel AS cpf_cnpj_socio FROM temp_CGUSC.fp.dados_farmacia WHERE cpfResponsavel IS NOT NULL
    UNION
    -- CPFs dos sócios formais
    SELECT soc.cpfcnpjSocio FROM temp_CGUSC.fp.lista_cnpjs lst
    INNER JOIN db_CNPJ.dbo.socios soc ON soc.cnpj = lst.cnpj WHERE soc.indSocio = 'PF'
) AS u;

CREATE CLUSTERED INDEX ix_cpfs_vivos ON #cpfs_vivos(cpf);

DROP TABLE IF EXISTS #temp_metadata_cpfs;
SELECT 
    c.CPF,
    temp_CGUSC.dbo.InitCapEachWord(LEFT(c.nome, 100)) AS nome,
    CAST(c.dataNascimento AS DATE) AS dataNascimento
INTO #temp_metadata_cpfs
FROM #cpfs_vivos v
INNER JOIN db_CPF.dbo.CPF c ON c.CPF = v.cpf
WHERE c.CPF IS NOT NULL;

-- Remove duplicatas históricas da tabela de metadados
WITH CTE AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY CPF ORDER BY dataNascimento DESC) as rn
    FROM #temp_metadata_cpfs
)
DELETE FROM CTE WHERE rn > 1;

CREATE CLUSTERED INDEX ix_meta_cpfs ON #temp_metadata_cpfs(CPF);

--------------------------------------------------------------
-- ETAPA 2: Sócios das farmácias credenciadas
--------------------------------------------------------------

DROP TABLE IF EXISTS temp_CGUSC.fp.dados_socios;

SELECT DISTINCT
    soc.cpfcnpjSocio                                          AS cpf_cnpj_socio,
    soc.cnpj,
    CAST(soc.indSocio AS CHAR(2))                             AS indicador_socio,
    temp_CGUSC.dbo.InitCapEachWord(LEFT(soc.nomeSocio, 100))   AS nome_socio,
    CAST(temp_CGUSC.dbo.InitCapEachWord(ibge.no_municipio) AS VARCHAR(60))         AS municipio,
    CAST(ibge.sg_uf AS CHAR(2))                                                   AS uf,
    CAST(soc.dataEntradaSociedade AS DATE)                    AS data_entrada_sociedade,
    CAST(soc.dataExclusaoSociedade AS DATE)                   AS data_exclusao_sociedade,
    CAST(soc.percentualQualificacao / 100.0 AS DECIMAL(5,2)) AS percentual_qualificacao,
    CAST(temp_CGUSC.dbo.InitCapEachWord(soc.descQualificacaoSocio) AS VARCHAR(60)) AS descricao_qualificacao,
    NULLIF(CAST(soc.CpfRepresentante AS CHAR(11)), '00000000000')                  AS cpf_representante,
    NULLIF(TRY_CAST(soc.IdQualificacaoRepresentante AS TINYINT), 0)                AS id_qualificacao_representante,
    cobi_rep.nome                                                  AS nome_representante,
    CAST(temp_CGUSC.dbo.InitCapEachWord(qua_rep.DescricaoQualificacao) AS VARCHAR(60)) AS descricao_qualificacao_representante,
    CAST(cobi.dataNascimento AS DATE)                                              AS data_nascimento_socio,
    CAST(cobi_rep.dataNascimento AS DATE)                                          AS data_nascimento_representante,
    CAST(GETDATE() AS SMALLDATETIME)                                               AS data_processamento
INTO temp_CGUSC.fp.dados_socios
FROM temp_CGUSC.fp.lista_cnpjs lst
INNER JOIN db_CNPJ.dbo.socios soc ON soc.cnpj = lst.cnpj
INNER JOIN db_CNPJ.dbo.CNPJ cnpj ON cnpj.cnpj = soc.cnpj
LEFT JOIN db_CNPJ.dbo.Municipio mun ON mun.SkMunicipio = soc.CodMunicipio
LEFT JOIN temp_CGUSC.fp.dados_ibge ibge ON ibge.id_ibge7 = mun.CodIbge
LEFT JOIN #temp_metadata_cpfs cobi ON cobi.CPF = soc.cpfcnpjSocio AND soc.indSocio = 'PF'
LEFT JOIN #temp_metadata_cpfs cobi_rep ON cobi_rep.CPF = soc.CpfRepresentante AND soc.CpfRepresentante <> '00000000000'
LEFT JOIN db_CNPJ.dbo.Qualificacao AS qua_rep ON qua_rep.IdQualificacao = TRY_CAST(soc.IdQualificacaoRepresentante AS INT);

--------------------------------------------------------------
-- ETAPA 2.1: Incluir Responsáveis de Empresas Individuais/MEI
-- (Empresas que não possuem registros na db_CNPJ.dbo.socios)
--------------------------------------------------------------
INSERT INTO temp_CGUSC.fp.dados_socios (
    cpf_cnpj_socio,
    cnpj,
    indicador_socio,
    nome_socio,
    municipio,
    uf,
    data_entrada_sociedade,
    percentual_qualificacao,
    descricao_qualificacao,
    data_nascimento_socio,
    data_processamento
)
SELECT 
    f.cpfResponsavel,
    f.cnpj,
    'PF'                                    AS indicador_socio,
    f.nome_responsavel,
    f.municipio,
    f.uf,
    f.dataSituacaoCadastral                  AS data_entrada_sociedade,
    100.00                                  AS percentual_qualificacao,
    f.descricaoQualificacaoResponsavel,
    CAST(cobi.dataNascimento AS DATE)       AS data_nascimento_socio,
    CAST(GETDATE() AS SMALLDATETIME)        AS data_processamento
FROM temp_CGUSC.fp.dados_farmacia f
LEFT JOIN temp_CGUSC.fp.dados_socios s ON s.cnpj = f.cnpj
LEFT JOIN #temp_metadata_cpfs cobi ON cobi.CPF = f.cpfResponsavel
WHERE s.cnpj IS NULL
  AND f.cpfResponsavel IS NOT NULL;

-- Índice CLUSTERED: Organiza a tabela fisicamente por CPF para performance máxima em JOINs
CREATE CLUSTERED INDEX cx_sociosFP_cpf_cnpj_socio
    ON temp_CGUSC.fp.dados_socios (cpf_cnpj_socio, cnpj);

-- Padrão de consulta por farmácia
CREATE INDEX ix_sociosFP_cnpj
    ON temp_CGUSC.fp.dados_socios (cnpj);


--------------------------------------------------------------
-- ETAPA 3: Mapeamento das Participações Externas (Nível 2 e 4)
--------------------------------------------------------------

-- 1. CPFs dos sócios das farmácias FP
DROP TABLE IF EXISTS #cpfs_socios_fp;
SELECT DISTINCT cpf_cnpj_socio INTO #cpfs_socios_fp FROM temp_CGUSC.fp.dados_socios WHERE cpf_cnpj_socio IS NOT NULL;
CREATE CLUSTERED INDEX ix_cpfs_lookup ON #cpfs_socios_fp (cpf_cnpj_socio);

-- 2. Identificar CPFs Representantes do Nível 2 que ainda não estão no dicionário
INSERT INTO #temp_metadata_cpfs (CPF, nome, dataNascimento)
SELECT 
    c.CPF,
    temp_CGUSC.dbo.InitCapEachWord(LEFT(c.nome, 100)) AS nome,
    CAST(c.dataNascimento AS DATE) AS dataNascimento
FROM (
    SELECT DISTINCT CpfRepresentante FROM db_CNPJ.dbo.socios s
    INNER JOIN #cpfs_socios_fp fp ON fp.cpf_cnpj_socio = s.cpfcnpjSocio
    WHERE s.CpfRepresentante <> '00000000000' AND s.CpfRepresentante IS NOT NULL
) AS novos
INNER JOIN db_CPF.dbo.CPF c ON c.CPF = novos.CpfRepresentante
WHERE NOT EXISTS (SELECT 1 FROM #temp_metadata_cpfs m WHERE m.CPF = novos.CpfRepresentante);

-- Limpa possíveis duplicatas da nova inserção
WITH CTE AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY CPF ORDER BY dataNascimento DESC) as rn
    FROM #temp_metadata_cpfs
)
DELETE FROM CTE WHERE rn > 1;

-- 3. Nível 2 Raw (Outras empresas dos sócios originais)
DROP TABLE IF EXISTS #teia_fonte_nivel2_raw;
SELECT
    raw.cpfcnpjSocio                                         AS cpf_cnpj_socio,
    CAST(raw.cnpj AS VARCHAR(14))                             AS cnpj_empresa,
    CAST(raw.indSocio AS CHAR(2))                             AS indicador_socio,
    CAST(raw.descQualificacaoSocio AS VARCHAR(60))             AS descricao_qualificacao,
    NULLIF(CAST(raw.CpfRepresentante AS CHAR(11)), '00000000000') AS cpf_representante,
    cobi_rep.nome                                            AS nome_representante,
    CAST(raw.dataEntradaSociedade AS DATE)                    AS data_entrada_sociedade,
    CAST(raw.dataExclusaoSociedade AS DATE)                   AS data_exclusao_sociedade
INTO #teia_fonte_nivel2_raw
FROM (
    SELECT 
        s.*,
        ROW_NUMBER() OVER (PARTITION BY s.cpfcnpjSocio, s.cnpj ORDER BY s.dataEntradaSociedade DESC) as rn_hist
    FROM #cpfs_socios_fp fp
    INNER JOIN db_CNPJ.dbo.socios s ON s.cpfcnpjSocio = fp.cpf_cnpj_socio
) AS raw
LEFT JOIN #temp_metadata_cpfs cobi_rep ON cobi_rep.CPF = raw.CpfRepresentante AND raw.CpfRepresentante <> '00000000000'
WHERE raw.rn_hist = 1;

CREATE CLUSTERED INDEX ix_t2_raw_cnpj ON #teia_fonte_nivel2_raw (cnpj_empresa);

-- 3. Universo de CNPJs para Enriquecimento (Para garantir que só expandimos o que existe)
DROP TABLE IF EXISTS #universo_cnpjs;
SELECT DISTINCT cnpj_empresa INTO #universo_cnpjs FROM #teia_fonte_nivel2_raw;

-- 4. Dicionário de Metadados (Garantindo 1:1 com DISTINCT)
DROP TABLE IF EXISTS #metadata_empresas;
SELECT DISTINCT
    u.cnpj_empresa,
    CAST(LEFT(c.RazaoSocial, 100) AS VARCHAR(100)) AS razao_social,
    CAST(LEFT(c.NomeFantasia, 100) AS VARCHAR(100)) AS nome_fantasia,
    TRY_CAST(c.CnaeFiscal AS INT) AS id_cnae_principal,
    CAST(sit.ds_situacao_cnpj AS VARCHAR(60)) AS situacao_rf,
    CAST(ibge.no_municipio AS VARCHAR(60)) AS municipio,
    CAST(ibge.sg_uf AS CHAR(2)) AS uf
INTO #metadata_empresas
FROM #universo_cnpjs u
INNER JOIN db_CNPJ.dbo.CNPJ c ON c.cnpj = u.cnpj_empresa
LEFT JOIN db_CNPJ.dbo.dime_situacao_cadastral_cnpj sit ON sit.cd_situacao_cnpj = c.SituacaoCadastral
LEFT JOIN db_CNPJ.dbo.Municipio mun ON mun.SkMunicipio = c.CodMunicipio
LEFT JOIN temp_CGUSC.fp.dados_ibge ibge ON ibge.id_ibge7 = mun.CodIbge;

CREATE CLUSTERED INDEX ix_meta_cnpj ON #metadata_empresas (cnpj_empresa);

--------------------------------------------------------------
-- ETAPA 4: Montagem Final Nível 2 e Expansão Nível 3
--------------------------------------------------------------

-- Gerar Teia Nível 2 Final (Apenas o que tem metadados, para manter paridade)
DROP TABLE IF EXISTS temp_CGUSC.fp.teia_fonte_nivel2;
SELECT DISTINCT
    raw.cpf_cnpj_socio,
    raw.cnpj_empresa,
    m.razao_social,
    m.nome_fantasia,
    m.id_cnae_principal,
    raw.indicador_socio,
    raw.descricao_qualificacao,
    raw.cpf_representante,
    raw.nome_representante,
    raw.data_entrada_sociedade,
    raw.data_exclusao_sociedade,
    m.situacao_rf,
    m.municipio,
    m.uf,
    CASE WHEN lst.cnpj IS NOT NULL THEN CAST(1 AS TINYINT) ELSE CAST(0 AS TINYINT) END AS is_farmacia_fp
INTO temp_CGUSC.fp.teia_fonte_nivel2
FROM #teia_fonte_nivel2_raw raw
INNER JOIN #metadata_empresas m ON m.cnpj_empresa = raw.cnpj_empresa
LEFT JOIN temp_CGUSC.fp.lista_cnpjs lst ON lst.cnpj = raw.cnpj_empresa;

CREATE CLUSTERED INDEX cx_t2_final ON temp_CGUSC.fp.teia_fonte_nivel2 (cpf_cnpj_socio, cnpj_empresa);

-- Gerar Teia Nível 3 (Sócios das empresas que REALMENTE apareceram no Nível 2)
-- Primeiro, alimentar o dicionário com os novos sócios do N3
INSERT INTO #temp_metadata_cpfs (CPF, nome, dataNascimento)
SELECT 
    c.CPF,
    temp_CGUSC.dbo.InitCapEachWord(LEFT(c.nome, 100)) AS nome,
    CAST(c.dataNascimento AS DATE) AS dataNascimento
FROM (
    SELECT DISTINCT s.cpfcnpjSocio FROM (SELECT DISTINCT cnpj_empresa FROM temp_CGUSC.fp.teia_fonte_nivel2) n2
    INNER JOIN db_CNPJ.dbo.socios s ON s.cnpj = n2.cnpj_empresa
    WHERE s.indSocio = 'PF' AND s.cpfcnpjSocio <> '99999999999999'
    UNION
    SELECT DISTINCT s.CpfRepresentante FROM (SELECT DISTINCT cnpj_empresa FROM temp_CGUSC.fp.teia_fonte_nivel2) n2
    INNER JOIN db_CNPJ.dbo.socios s ON s.cnpj = n2.cnpj_empresa
    WHERE s.CpfRepresentante <> '00000000000' AND s.CpfRepresentante IS NOT NULL
) AS novos
INNER JOIN db_CPF.dbo.CPF c ON c.CPF = novos.cpfcnpjSocio
WHERE NOT EXISTS (SELECT 1 FROM #temp_metadata_cpfs m WHERE m.CPF = novos.cpfcnpjSocio);

-- Limpa possíveis duplicatas
WITH CTE AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY CPF ORDER BY dataNascimento DESC) as rn
    FROM #temp_metadata_cpfs
)
DELETE FROM CTE WHERE rn > 1;

DROP TABLE IF EXISTS temp_CGUSC.fp.teia_fonte_nivel3;
SELECT
    CAST(raw.cnpj AS VARCHAR(14))                             AS cnpj_empresa,
    CAST(raw.cpfcnpjSocio AS VARCHAR(14))                     AS cpf_cnpj_socio,
    cobi.nome                                                AS nome_socio,
    CAST(raw.indSocio AS CHAR(2))                             AS indicador_socio,
    CAST(LEFT(raw.descQualificacaoSocio, 50) AS VARCHAR(50))   AS descricao_qualificacao,
    NULLIF(CAST(raw.CpfRepresentante AS CHAR(11)), '00000000000') AS cpf_representante,
    cobi_rep.nome                                            AS nome_representante,
    CAST(raw.dataEntradaSociedade AS DATE)                    AS data_entrada_sociedade,
    CAST(raw.dataExclusaoSociedade AS DATE)                   AS data_exclusao_sociedade,
    CAST(ibge.no_municipio AS VARCHAR(60))                  AS municipio,
    CAST(ibge.sg_uf AS CHAR(2))                             AS uf
INTO temp_CGUSC.fp.teia_fonte_nivel3
FROM (
    SELECT 
        s.*,
        ROW_NUMBER() OVER (PARTITION BY s.cnpj, s.cpfcnpjSocio ORDER BY s.dataEntradaSociedade DESC) as rn_hist
    FROM (SELECT DISTINCT cnpj_empresa FROM temp_CGUSC.fp.teia_fonte_nivel2) n2
    INNER JOIN db_CNPJ.dbo.socios s ON s.cnpj = n2.cnpj_empresa
    WHERE s.cpfcnpjSocio <> '99999999999999'
) AS raw
LEFT JOIN #temp_metadata_cpfs cobi ON cobi.CPF = raw.cpfcnpjSocio AND raw.indSocio = 'PF'
LEFT JOIN #temp_metadata_cpfs cobi_rep ON cobi_rep.CPF = raw.CpfRepresentante AND raw.CpfRepresentante <> '00000000000'
LEFT JOIN db_CNPJ.dbo.Municipio mun ON mun.SkMunicipio = raw.CodMunicipio
LEFT JOIN temp_CGUSC.fp.dados_ibge ibge ON ibge.id_ibge7 = mun.CodIbge
WHERE raw.rn_hist = 1;

CREATE CLUSTERED INDEX cx_t3_final ON temp_CGUSC.fp.teia_fonte_nivel3 (cnpj_empresa, cpf_cnpj_socio);

--------------------------------------------------------------
-- ETAPA 5: Mapeamento e Montagem Final Nível 4
--------------------------------------------------------------

-- 1. Raw Nível 4
-- Alimentar dicionário com novos representantes do N4
INSERT INTO #temp_metadata_cpfs (CPF, nome, dataNascimento)
SELECT 
    c.CPF,
    temp_CGUSC.dbo.InitCapEachWord(LEFT(c.nome, 100)) AS nome,
    CAST(c.dataNascimento AS DATE) AS dataNascimento
FROM (
    SELECT DISTINCT s.CpfRepresentante FROM (SELECT DISTINCT cpf_cnpj_socio FROM temp_CGUSC.fp.teia_fonte_nivel3 WHERE cpf_cnpj_socio IS NOT NULL) n3
    INNER JOIN db_CNPJ.dbo.socios s ON s.cpfcnpjSocio = n3.cpf_cnpj_socio
    WHERE s.CpfRepresentante <> '00000000000' AND s.CpfRepresentante IS NOT NULL
) AS novos
INNER JOIN db_CPF.dbo.CPF c ON c.CPF = novos.CpfRepresentante
WHERE NOT EXISTS (SELECT 1 FROM #temp_metadata_cpfs m WHERE m.CPF = novos.CpfRepresentante);

-- Limpa possíveis duplicatas
WITH CTE AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY CPF ORDER BY dataNascimento DESC) as rn
    FROM #temp_metadata_cpfs
)
DELETE FROM CTE WHERE rn > 1;

DROP TABLE IF EXISTS #teia_fonte_nivel4_raw;
SELECT
    raw.cpfcnpjSocio                                         AS cpf_cnpj_socio,
    CAST(raw.cnpj AS VARCHAR(14))                             AS cnpj_empresa,
    CAST(raw.indSocio AS CHAR(2))                             AS indicador_socio,
    CAST(LEFT(raw.descQualificacaoSocio, 60) AS VARCHAR(60))   AS descricao_qualificacao,
    NULLIF(CAST(raw.CpfRepresentante AS CHAR(11)), '00000000000') AS cpf_representante,
    cobi_rep.nome                                            AS nome_representante,
    CAST(raw.dataEntradaSociedade AS DATE)                    AS data_entrada_sociedade,
    CAST(raw.dataExclusaoSociedade AS DATE)                   AS data_exclusao_sociedade
INTO #teia_fonte_nivel4_raw
FROM (
    SELECT 
        s.*,
        ROW_NUMBER() OVER (PARTITION BY s.cpfcnpjSocio, s.cnpj ORDER BY s.dataEntradaSociedade DESC) as rn_hist
    FROM (SELECT DISTINCT cpf_cnpj_socio FROM temp_CGUSC.fp.teia_fonte_nivel3 WHERE cpf_cnpj_socio IS NOT NULL) n3
    INNER JOIN db_CNPJ.dbo.socios s ON s.cpfcnpjSocio = n3.cpf_cnpj_socio
) AS raw
LEFT JOIN #temp_metadata_cpfs cobi_rep ON cobi_rep.CPF = raw.CpfRepresentante AND raw.CpfRepresentante <> '00000000000'
WHERE raw.rn_hist = 1;

-- 2. Enriquecer metadados apenas para as NOVAS empresas do Nível 4
DROP TABLE IF EXISTS #universo_n4;
SELECT DISTINCT cnpj_empresa INTO #universo_n4 FROM #teia_fonte_nivel4_raw;

INSERT INTO #metadata_empresas (
    cnpj_empresa,
    razao_social,
    nome_fantasia,
    id_cnae_principal,
    situacao_rf,
    municipio,
    uf
)
SELECT DISTINCT
    u.cnpj_empresa,
    CAST(LEFT(c.RazaoSocial, 100) AS VARCHAR(100)),
    CAST(LEFT(c.NomeFantasia, 100) AS VARCHAR(100)),
    TRY_CAST(c.CnaeFiscal AS INT),
    CAST(sit.ds_situacao_cnpj AS VARCHAR(60)),
    CAST(ibge.no_municipio AS VARCHAR(60)),
    CAST(ibge.sg_uf AS CHAR(2))
FROM #universo_n4 u
INNER JOIN db_CNPJ.dbo.CNPJ c ON c.cnpj = u.cnpj_empresa
LEFT JOIN db_CNPJ.dbo.dime_situacao_cadastral_cnpj sit ON sit.cd_situacao_cnpj = c.SituacaoCadastral
LEFT JOIN db_CNPJ.dbo.Municipio mun ON mun.SkMunicipio = c.CodMunicipio
LEFT JOIN temp_CGUSC.fp.dados_ibge ibge ON ibge.id_ibge7 = mun.CodIbge
WHERE NOT EXISTS (SELECT 1 FROM #metadata_empresas m WHERE m.cnpj_empresa = u.cnpj_empresa);

-- 3. Gerar Teia Nível 4 Final
DROP TABLE IF EXISTS temp_CGUSC.fp.teia_fonte_nivel4;
SELECT DISTINCT
    raw.cpf_cnpj_socio,
    raw.cnpj_empresa,
    m.razao_social,
    m.nome_fantasia,
    m.id_cnae_principal,
    raw.indicador_socio,
    raw.descricao_qualificacao,
    raw.cpf_representante,
    raw.nome_representante,
    raw.data_entrada_sociedade,
    raw.data_exclusao_sociedade,
    m.situacao_rf,
    m.municipio,
    m.uf,
    CASE WHEN lst.cnpj IS NOT NULL THEN CAST(1 AS TINYINT) ELSE CAST(0 AS TINYINT) END AS is_farmacia_fp
INTO temp_CGUSC.fp.teia_fonte_nivel4
FROM #teia_fonte_nivel4_raw raw
INNER JOIN #metadata_empresas m ON m.cnpj_empresa = raw.cnpj_empresa
LEFT JOIN temp_CGUSC.fp.lista_cnpjs lst ON lst.cnpj = raw.cnpj_empresa;

CREATE CLUSTERED INDEX cx_t4_final ON temp_CGUSC.fp.teia_fonte_nivel4 (cpf_cnpj_socio, cnpj_empresa);


--------------------------------------------------------------
-- ETAPA 6: Estimativa de Estoque Inicial
--------------------------------------------------------------
-- definir os estoques iniciais com critério da soma das duas últimas aquisições anteriores a primeira venda na base de --producao


DROP TABLE IF EXISTS TEMP_CGUSC.dbo.farmacia_inicio_venda_gtin
select a.cnpj, a.codigo_barra, min(data_hora) as data_inicio_venda
into TEMP_CGUSC.dbo.farmacia_inicio_venda_gtin
from db_farmaciaPopular.dbo.relatorio_movimentacao_2015_2024 A
inner join temp_CGUSC.dbo.medicamentosPatologiaFP B on B.codigo_barra = A.codigo_barra
inner join temp_CGUSC.fp.lista_cnpjs C on C.cnpj = A.cnpj
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
