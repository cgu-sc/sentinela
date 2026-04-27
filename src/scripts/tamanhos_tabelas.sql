USE [temp_CGUSC];
GO

/* 
   Relatório de Tabelas: Tamanho, Índices e Data de Criação 
   Ordenado pelas tabelas mais recentes.
*/
SELECT 
    t.NAME AS [Nome da Tabela],
    t.create_date AS [Data de Criação],
    FORMAT(p.rows, '#,###', 'pt-BR') AS [Total de Linhas],
    CAST(ROUND(((SUM(a.total_pages) * 8) / 1024.0), 2) AS NUMERIC(36, 2)) AS [Total Reservado (MB)],
    CAST(ROUND(((SUM(a.data_pages) * 8) / 1024.0), 2) AS NUMERIC(36, 2)) AS [Espaço de Dados (MB)],
    CAST(ROUND((((SUM(a.used_pages) - SUM(a.data_pages)) * 8) / 1024.0), 2) AS NUMERIC(36, 2)) AS [Espaço de Índices (MB)],
    CAST(ROUND((((SUM(a.total_pages) - SUM(a.used_pages)) * 8) / 1024.0), 2) AS NUMERIC(36, 2)) AS [Espaço Não Utilizado (MB)]
FROM 
    sys.tables t
INNER JOIN      
    sys.indexes i ON t.OBJECT_ID = i.object_id
INNER JOIN 
    sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
INNER JOIN 
    sys.allocation_units a ON p.partition_id = a.container_id
WHERE 
    t.is_ms_shipped = 0      -- Ignora tabelas de sistema da Microsoft
    AND i.OBJECT_ID > 255   -- Ignora objetos internos
GROUP BY 
    t.Name, t.create_date, p.Rows
ORDER BY 
    t.create_date DESC;     -- Tabelas criadas recentemente primeiro
GO
