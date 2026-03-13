
  USE [db_farmaciapopular_nf]
GO

-- Create the unified table in temp_CGUSC.dbo
CREATE TABLE [temp_CGUSC].[dbo].[aquisicoesFazenda](
    [chaveNFE] [char](44) NULL,
    [numeroNFE] [bigint] NULL,
    [dataEmissaoNFE] [date] NULL,
    [remetenteNFE] [char](14) NULL,
    [destinatarioNFE] [char](14) NULL,
    [tipooperacao] [tinyint] NULL,
    [codigoBarra] [bigint] NULL,
    [quantidade] [int] NULL
) ON [PRIMARY]
GO

-- Insert data from aquisicoesFazenda (2015-2021)
INSERT INTO [temp_CGUSC].[dbo].[aquisicoesFazenda] (
    chaveNFE,
    numeroNFE,
    dataEmissaoNFE,
    remetenteNFE,
    destinatarioNFE,
    tipooperacao,
    codigoBarra,
    quantidade
)
SELECT 
    CAST(chaveNFE AS char(44)) AS chaveNFE, -- Convert decimal(20,0) to char(44)
    CAST(numeroNFE AS bigint) AS numeroNFE, -- Convert int to bigint
    dataEmissaoNFE,
    remetenteNFE,
    destinatarioNFE,
    CAST(tipooperacao AS tinyint) AS tipooperacao, -- Convert smallint to tinyint
    codigoBarra,
    quantidade
FROM [dbo].[aquisicoesFazenda]
WHERE dataEmissaoNFE BETWEEN '2014-06-01' AND '2021-09-30'

UNION ALL

-- Insert data from aquisicoesFazenda2021_2024 (2021-2023)
SELECT 
    LEFT(chave_mascarada, 44) AS chaveNFE, -- Truncate varchar(500) to char(44)
    CAST(nnf AS bigint) AS numeroNFE, -- Convert int to bigint
    data_emissao AS dataEmissaoNFE,
    NULL AS remetenteNFE, -- Not present in this table
    CAST(cnpj_dest AS char(14)) AS destinatarioNFE, -- Convert varchar(14) to char(14)
    tpnf AS tipooperacao, -- Already tinyint
    cean AS codigoBarra, -- Already bigint
    CAST(qcom AS int) AS quantidade -- Convert numeric(19,4) to int
FROM [dbo].[aquisicoesFazenda2021_2024]
WHERE data_emissao BETWEEN '2021-10-01' AND '2023-07-31'

UNION ALL

-- Insert data from aquisicoesFazenda2023_2025 (2023-2025)
SELECT 
    chaveNFE,
    numeroNFE,
    dataEmissaoNFE,
    remetenteNFE,
    destinatarioNFE,
    tipooperacao,
    codigoBarra,
    quantidade
FROM [dbo].[aquisicoesFazenda2023_2025]
WHERE dataEmissaoNFE BETWEEN '2023-08-01' AND '2025-03-06';
GO

-- Create non-clustered indexes to optimize query performance
CREATE NONCLUSTERED INDEX IX_aquisicoesFazenda_dataEmissaoNFE 
ON [temp_CGUSC].[dbo].[aquisicoesFazenda] (dataEmissaoNFE);
GO

CREATE NONCLUSTERED INDEX IX_aquisicoesFazenda_destinatarioNFE 
ON [temp_CGUSC].[dbo].[aquisicoesFazenda] (destinatarioNFE);
GO

CREATE NONCLUSTERED INDEX IX_aquisicoesFazenda_numeroNFE 
ON [temp_CGUSC].[dbo].[aquisicoesFazenda] (numeroNFE);
GO

CREATE NONCLUSTERED INDEX IX_aquisicoesFazenda_tipooperacao 
ON [temp_CGUSC].[dbo].[aquisicoesFazenda] (tipooperacao);
GO

CREATE NONCLUSTERED INDEX IX_aquisicoesFazenda_codigoBarra 
ON [temp_CGUSC].[dbo].[aquisicoesFazenda] (codigoBarra);
GO