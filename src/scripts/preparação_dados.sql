

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
-- ETAPA 1: Sócios das farmácias credenciadas
--------------------------------------------------------------

DROP TABLE IF EXISTS temp_CGUSC.fp.dados_socios;

SELECT
    soc.cpfcnpjSocio                                          AS cpf_cnpj_socio,
    soc.cnpj,
    CAST(soc.indSocio AS CHAR(2))                             AS indicador_socio,
    temp_CGUSC.dbo.InitCapEachWord(LEFT(soc.nomeSocio, 100))   AS nome_socio,
    temp_CGUSC.dbo.InitCapEachWord(soc.descricaoLogradouro)   AS descricao_logradouro,
    soc.numero,
    temp_CGUSC.dbo.InitCapEachWord(soc.complemento)           AS complemento,
    temp_CGUSC.dbo.InitCapEachWord(soc.bairro)                AS bairro,
    CAST(soc.cep AS CHAR(8))                                  AS cep,
    temp_CGUSC.dbo.InitCapEachWord(mun_ibge.municipio)        AS municipio,
    CAST(soc.dataEntradaSociedade AS DATE)                    AS data_entrada_sociedade,
    CAST(soc.dataExclusaoSociedade AS DATE)                   AS data_exclusao_sociedade,
    soc.percentualQualificacao                                AS percentual_qualificacao,
    temp_CGUSC.dbo.InitCapEachWord(soc.descQualificacaoSocio) AS descricao_qualificacao,
    GETDATE()                                                 AS data_processamento
INTO temp_CGUSC.fp.dados_socios
FROM temp_CGUSC.fp.lista_cnpjs    AS lst
INNER JOIN db_CNPJ.dbo.socios             AS soc       ON soc.cnpj           = lst.cnpj
INNER JOIN db_CNPJ.dbo.CNPJ               AS cnpj      ON cnpj.cnpj          = lst.cnpj
LEFT JOIN  db_CNPJ.dbo.Municipio          AS mun       ON mun.SkMunicipio    = soc.CodMunicipio
LEFT JOIN  temp_CGUSC.dbo.municipiosIBGE  AS mun_ibge  ON mun_ibge.codibge   = mun.CodIbge
WHERE
    soc.dataExclusaoSociedade   IS NULL
    AND cnpj.SituacaoCadastral  = 2;

-- Índices em tb_sociosFP
-- Busca por CNPJ da empresa (JOIN principal com dados_farmacia)
CREATE INDEX ix_sociosFP_cnpj
    ON temp_CGUSC.fp.dados_socios (cnpj);

-- Busca por CPF/CNPJ do sócio (subquery de outras sociedades)
CREATE INDEX ix_sociosFP_cpf_cnpj_socio
    ON temp_CGUSC.fp.dados_socios (cpf_cnpj_socio);

-- Índice composto para o padrão de consulta mais frequente:
-- "sócios ativos de um determinado CNPJ"
CREATE INDEX ix_sociosFP_cnpj_cpf
    ON temp_CGUSC.fp.dados_socios (cnpj, cpf_cnpj_socio);


--------------------------------------------------------------
-- ETAPA 2: Dados cadastrais das farmácias (1ª passagem)
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
    temp_CGUSC.dbo.InitCapEachWord(nat.DescNaturezaJuridica)   AS natuezaJuridica,
    c.CpfResponsavel,
    temp_CGUSC.dbo.InitCapEachWord(c.NomeResponsavel)          AS nomeResponsavel,
    c.QualificacaoResponsavel,
    temp_CGUSC.dbo.InitCapEachWord(qua.DescricaoQualificacao)  AS descricaoQualificacaoResponsavel,
    c.CnaeFiscal                                               AS id_cnae_principal,
    temp_CGUSC.dbo.InitCapEachWord(cnae_p.DescSubClasseCNAE)   AS cnae_principal,
    cnae_s_base.idSubClasseCNAE                                AS id_cnae_secundario,
    temp_CGUSC.dbo.InitCapEachWord(cnae_s.DescSubClasseCNAE)   AS cnae_secundario,
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
-- ETAPA 3: Enriquecimento — flag de outras sociedades
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
    f.natuezaJuridica,
    f.CpfResponsavel                                                 AS cpfResponsavel,
    f.nomeResponsavel,
    f.QualificacaoResponsavel                                        AS qualificacaoResponsavel,
    f.descricaoQualificacaoResponsavel,
    f.id_cnae_principal,
    f.cnae_principal,
    f.id_cnae_secundario,
    f.cnae_secundario,
    f.data_processamento,
    CASE f.CodPorteEmpresa
        WHEN '01' THEN 'Microempresa (ME)'
        WHEN '03' THEN 'Empresa de Pequeno Porte (EPP)'
        WHEN '05' THEN 'Demais'
        ELSE 'Não Informado'
    END AS ds_porte_empresa,
    CASE
        WHEN outras.outrasSociedades > 0 THEN 'Sim'
        ELSE 'Não'
    END AS outrasSociedades
INTO #tempDadosFarmacias2
FROM #tempDadosFarmacias AS f
CROSS APPLY (
    SELECT COUNT(*) AS outrasSociedades
    FROM (
        SELECT DISTINCT soc2.cnpj
        FROM temp_CGUSC.fp.socios_farmacia AS soc2
        INNER JOIN #tempDadosFarmacias     AS farm ON farm.cnpj = soc2.cnpj
        WHERE soc2.cnpj <> f.cnpj
          AND soc2.cpf_cnpj_Socio IN (
              SELECT soc1.cpf_cnpj_Socio
              FROM temp_CGUSC.fp.socios_farmacia AS soc1
              WHERE soc1.cnpj = f.cnpj
          )
    ) AS t
) AS outras;

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
    mov.dataFinalDadosMovimentacao
INTO temp_CGUSC.fp.dados_farmacia
FROM #tempDadosFarmacias2          AS f
LEFT JOIN #tempDatasMovimentacao   AS mov ON mov.cnpj = f.cnpj;

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





-- definir os estoques iniciais com critério da soma das duas últimas aquisições anteriores a primeira venda na base de --producao



DROP TABLE IF EXISTS TEMP_CGUSC.dbo.farmacia_inicio_venda_gtin
select a.cnpj, a.codigo_barra, min(data_hora) as data_inicio_venda
into TEMP_CGUSC.dbo.farmacia_inicio_venda_gtin
from FROM db_farmaciaPopular.dbo.relatorio_movimentacao_2015_2024 A
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
   
   



   
      