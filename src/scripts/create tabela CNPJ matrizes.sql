/* Script SQL para criar a tabela temp_CGUSC.dbo.CNPJ_matrizes com os CNPJs de matrizes (sufixo '0001')
 * e suas respectivas razões sociais, utilizada pelo painel do Sentinela para otimizar e agilizar
 * as consultas de informação da matriz.
 * Esse script só precisa ser reexecutado quando da atualização do Sentinela */ 


-- Apaga a tabela de matrizes se já existir
IF OBJECT_ID('temp_CGUSC.dbo.CNPJ_matrizes','U') IS NOT NULL
  DROP TABLE temp_CGUSC.dbo.CNPJ_matrizes;
GO

-- Cria a staging table com as matrizes (sufixo 0001)
SELECT
  LEFT(Cnpj, 8)        AS cnpj_raiz,
  Cnpj                 AS cnpj_matriz,
  RazaoSocial          AS razao_social_matriz,
  p.descricao          AS porte_matriz

INTO temp_CGUSC.dbo.CNPJ_matrizes
FROM db_CNPJ.dbo.CNPJ as c
LEFT JOIN [temp_CGUSC].[dbo].[porteEmpresa] as p
  ON C.CodPorteEmpresa = p.codPorteEmpresa

WHERE SUBSTRING(Cnpj, 9, 4) = '0001';
GO

-- Índice na coluna de raiz para acelerar os joins
CREATE INDEX ix_CNPJ_matrizes_cnpj_raiz
  ON temp_CGUSC.dbo.CNPJ_matrizes (cnpj_raiz);
GO