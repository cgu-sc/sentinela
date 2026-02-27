-- ============================================================================
-- CRIAÇÃO DA TABELA DE CONFIGURAÇÃO E VERSÃO DO SISTEMA
-- ============================================================================
USE [temp_CGUSC]
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'config_sistema' AND schema_id = SCHEMA_ID('fp'))
BEGIN
    CREATE TABLE fp.config_sistema (
        id INT PRIMARY KEY IDENTITY(1,1),
        chave VARCHAR(50) UNIQUE NOT NULL,
        valor VARCHAR(MAX) NOT NULL,
        descricao VARCHAR(255),
        dt_atualizacao DATETIME DEFAULT GETDATE()
    );
    
    PRINT 'Tabela fp.config_sistema criada com sucesso.';
END
GO

-- Inserir a versão mínima obrigatória (Exemplo: 3.1.0)
-- Se já existir, atualiza.
IF NOT EXISTS (SELECT 1 FROM fp.config_sistema WHERE chave = 'versao_minima_obrigatoria')
BEGIN
    INSERT INTO fp.config_sistema (chave, valor, descricao)
    VALUES ('versao_minima_obrigatoria', '3.1.0', 'Define a versão mínima do executável permitida para rodar.');
END
ELSE
BEGIN
    UPDATE fp.config_sistema 
    SET valor = '3.1.0', dt_atualizacao = GETDATE()
    WHERE chave = 'versao_minima_obrigatoria';
END
GO

SELECT * FROM fp.config_sistema;
