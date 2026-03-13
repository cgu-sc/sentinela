USE [temp_CGUSC]
GO

-- ============================================================================
-- INDICADOR DE FALECIDOS - VERSÃO 3 (DETALHAMENTO POR AUTORIZAÇÃO)
-- ============================================================================
-- OBJETIVO: Identificar dispensações registradas APÓS a data de óbito dos 
--           pacientes e gerar a lista detalhada por AUTORIZAÇÃO.
--
-- ALTERAÇÕES APLICADAS:
--   1. Denominador Ajustado: O cálculo de faturamento total agora considera 
--      apenas medicamentos auditados (JOIN com medicamentos_patologia), 
--      garantindo que os números batam com o relatório do Sentinela.
--   2. Detalhamento Máximo: A lista nominal falecidos_por_farmacia agora é 
--      agrupada por autorização (Passo 2), permitindo auditoria direta.
--   3. Novas Métricas: Adicionada contagem de CPFs distintos e 
--      Autozições distintas por CNPJ no indicador final.
--   4. Dados Cadastrais: Nome, município e UF do falecido via db_CPF.
--
-- FONTES:
--   Movimentação  : db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024
--   Óbitos        : temp_CGUSC.fp.obito_unificada
--   CPF (cadastro): db_CPF.dbo.CPF
--   Medicamentos  : temp_CGUSC.fp.medicamentos_patologia
-- ============================================================================

-- ============================================================================
-- DEFINIÇÃO DE VARIÁVEIS
-- ============================================================================
DECLARE @DataInicio DATE = '2015-07-01';
DECLARE @DataFim    DATE = '2024-12-10';


-- ============================================================================
-- PASSO 1: TOTAIS POR FARMÁCIA (MEDICAMENTOS AUDITADOS NO PERÍODO)
-- Base para o denominador do indicador. Filtrada por medicamentos_patologia
-- para consistência com o cronograma de auditoria da CGU.
-- ============================================================================
DROP TABLE IF EXISTS #TotaisPorFarmacia;

SELECT
    A.cnpj,
    COUNT(DISTINCT A.num_autorizacao) AS total_prescricoes_auditadas,
    SUM(A.valor_pago)                 AS valor_total_vendas_auditadas
INTO #TotaisPorFarmacia
FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A
INNER JOIN temp_CGUSC.fp.medicamentos_patologia C 
    ON C.codigo_barra = A.codigo_barra
WHERE A.data_hora >= @DataInicio
  AND A.data_hora <= @DataFim
GROUP BY A.cnpj;

CREATE CLUSTERED INDEX IDX_Totais_CNPJ ON #TotaisPorFarmacia(cnpj);


-- ============================================================================
-- PASSO 2: LISTA DETALHADA DE TRANSACÕES (FALECIDOS POR AUTORIZAÇÃO)
-- Um registro por combinação CNPJ × CPF falecido × num_autorizacao.
-- Permite ver exatamente quais autorizacoes foram geradas apos a morte.
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.falecidos_por_farmacia;

SELECT
    -- Identificação da Farmácia
    A.cnpj,

    -- Identificação do Falecido
    A.cpf,
    CPF.nome                                        AS nome_falecido,
    CPF.nomeMunicipio                               AS municipio_falecido,
    CPF.unidadeFederacao                            AS uf_falecido,
    OB.dt_nascimento,
    OB.dt_obito,
    OB.fonte                                        AS fonte_obito,

    -- Identificação da Transação
    A.num_autorizacao,
    A.data_hora                                     AS data_autorizacao,

    -- Estatísticas da Autorização
    COUNT(*)                                        AS qtd_itens_na_autorizacao,
    SUM(A.valor_pago)                               AS valor_total_autorizacao,
    
    -- Distância temporal: quanto tempo após o óbito a venda ocorreu
    DATEDIFF(DAY, OB.dt_obito, A.data_hora)         AS dias_apos_obito

INTO temp_CGUSC.fp.falecidos_por_farmacia
FROM db_farmaciapopular.dbo.relatorio_movimentacao_2015_2024 A

-- Filtra apenas medicamentos do escopo do programa auditado (igual ao Passo 1)
INNER JOIN temp_CGUSC.fp.medicamentos_patologia C
    ON C.codigo_barra = A.codigo_barra

-- Cruza com a base de óbitos (REGRA CENTRAL: dispensação após o óbito)
INNER JOIN temp_CGUSC.fp.obito_unificada OB
    ON OB.cpf = A.cpf

-- Dados cadastrais do falecido (nome, município e UF de domicílio)
LEFT JOIN db_CPF.dbo.CPF CPF
    ON CPF.CPF = A.cpf

WHERE
    A.data_hora >= @DataInicio
    AND A.data_hora <= @DataFim
    AND OB.dt_obito IS NOT NULL
    AND A.data_hora > OB.dt_obito   -- dispensação ocorreu APÓS a morte

GROUP BY
    A.cnpj,
    A.cpf,
    CPF.nome,
    CPF.nomeMunicipio,
    CPF.unidadeFederacao,
    OB.dt_nascimento,
    OB.dt_obito,
    OB.fonte,
    A.num_autorizacao,
    A.data_hora;

-- Índices para performance
CREATE CLUSTERED INDEX IDX_FalecFarm_CNPJ ON temp_CGUSC.fp.falecidos_por_farmacia(cnpj);
CREATE NONCLUSTERED INDEX IDX_FalecFarm_Auto ON temp_CGUSC.fp.falecidos_por_farmacia(num_autorizacao);
CREATE NONCLUSTERED INDEX IDX_FalecFarm_CPF ON temp_CGUSC.fp.falecidos_por_farmacia(cpf);


-- ============================================================================
-- PASSO 3: INDICADOR AGREGADO POR FARMÁCIA
-- Agrupa os dados detalhados para o nível de CNPJ.
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_falecidos;

SELECT
    T.cnpj,
    T.valor_total_vendas_auditadas AS valor_total_vendas,
    T.total_prescricoes_auditadas AS total_prescricoes,
    
    ISNULL(I.valor_falecidos, 0) AS valor_falecidos,
    ISNULL(I.qtd_vendas_falecidos, 0) AS qtd_itens_falecidos,
    ISNULL(I.qtd_autorizacoes_falecidos, 0) AS qtd_autorizacoes_falecidos,
    ISNULL(I.qtd_cpfs_falecidos, 0) AS qtd_cpfs_falecidos,

    CAST(
        CASE
            WHEN T.valor_total_vendas_auditadas > 0 THEN
                (CAST(ISNULL(I.valor_falecidos, 0) AS DECIMAL(18,2)) /
                 CAST(T.valor_total_vendas_auditadas AS DECIMAL(18,2))) * 100.0
            ELSE 0
        END
    AS DECIMAL(18,4)) AS percentual_falecidos

INTO temp_CGUSC.fp.indicador_falecidos
FROM #TotaisPorFarmacia T
LEFT JOIN (
    -- Agrega os dados transacionais do Passo 2 por CNPJ
    SELECT
        cnpj,
        SUM(valor_total_autorizacao) AS valor_falecidos,
        SUM(qtd_itens_na_autorizacao) AS qtd_vendas_falecidos,
        COUNT(DISTINCT num_autorizacao) AS qtd_autorizacoes_falecidos,
        COUNT(DISTINCT cpf) AS qtd_cpfs_falecidos
    FROM temp_CGUSC.fp.falecidos_por_farmacia
    GROUP BY cnpj
) I ON I.cnpj = T.cnpj
WHERE T.valor_total_vendas_auditadas > 0;

CREATE CLUSTERED INDEX IDX_IndFalecidos_CNPJ ON temp_CGUSC.fp.indicador_falecidos(cnpj);

DROP TABLE IF EXISTS #TotaisPorFarmacia;


-- ============================================================================
-- PASSO 4: MÉTRICAS GEOGRÁFICAS (MUNICÍPIO, UF, BR)
-- ============================================================================

-- Municipios
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_falecidos_mun;
SELECT DISTINCT
    CAST(F.uf AS VARCHAR(2)) AS uf,
    CAST(F.municipio AS VARCHAR(255)) AS municipio,
    CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.percentual_falecidos) 
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255))) AS DECIMAL(18,4)) AS mediana_municipio,
    CAST(CASE WHEN SUM(I.valor_total_vendas) OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255))) > 0 
        THEN (SUM(I.valor_falecidos) OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255))) / 
              SUM(I.valor_total_vendas) OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255)))) * 100.0
        ELSE 0 END AS DECIMAL(18,4)) AS media_municipio
INTO temp_CGUSC.fp.indicador_falecidos_mun
FROM temp_CGUSC.fp.indicador_falecidos I
INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj;

CREATE CLUSTERED INDEX IDX_IndFalecidosMun ON temp_CGUSC.fp.indicador_falecidos_mun(uf, municipio);

-- Estados
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_falecidos_uf;
SELECT DISTINCT
    CAST(F.uf AS VARCHAR(2)) AS uf,
    CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY I.percentual_falecidos) 
        OVER (PARTITION BY CAST(F.uf AS VARCHAR(2))) AS DECIMAL(18,4)) AS mediana_estado,
    CAST(CASE WHEN SUM(I.valor_total_vendas) OVER (PARTITION BY CAST(F.uf AS VARCHAR(2))) > 0 
        THEN (SUM(I.valor_falecidos) OVER (PARTITION BY CAST(F.uf AS VARCHAR(2))) / 
              SUM(I.valor_total_vendas) OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)))) * 100.0
        ELSE 0 END AS DECIMAL(18,4)) AS media_estado
INTO temp_CGUSC.fp.indicador_falecidos_uf
FROM temp_CGUSC.fp.indicador_falecidos I
INNER JOIN temp_CGUSC.fp.dados_farmacia F ON F.cnpj = I.cnpj;

CREATE CLUSTERED INDEX IDX_IndFalecidosUF ON temp_CGUSC.fp.indicador_falecidos_uf(uf);

-- Brasil
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_falecidos_br;
SELECT DISTINCT
    'BR' AS pais,
    CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY percentual_falecidos) OVER () AS DECIMAL(18,4)) AS mediana_pais,
    CAST(CASE WHEN SUM(valor_total_vendas) OVER () > 0 
        THEN (SUM(valor_falecidos) OVER () / SUM(valor_total_vendas) OVER ()) * 100.0
        ELSE 0 END AS DECIMAL(18,4)) AS media_pais
INTO temp_CGUSC.fp.indicador_falecidos_br
FROM temp_CGUSC.fp.indicador_falecidos;


-- ============================================================================
-- PASSO 5: TABELA CONSOLIDADA FINAL
-- ============================================================================
DROP TABLE IF EXISTS temp_CGUSC.fp.indicador_falecidos_detalhado;

SELECT
    I.cnpj,
    F.razaoSocial,
    F.municipio,
    CAST(F.uf AS VARCHAR(2))    AS uf,
    I.valor_total_vendas,
    I.total_prescricoes,
    I.valor_falecidos,
    I.qtd_itens_falecidos,
    I.qtd_autorizacoes_falecidos,
    I.qtd_cpfs_falecidos,
    I.percentual_falecidos,

    -- Rankings (pior risco = posição 1)
    RANK() OVER (ORDER BY I.percentual_falecidos DESC)                                                                           AS ranking_br,
    RANK() OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)) ORDER BY I.percentual_falecidos DESC)                                    AS ranking_uf,
    RANK() OVER (PARTITION BY CAST(F.uf AS VARCHAR(2)), CAST(F.municipio AS VARCHAR(255)) ORDER BY I.percentual_falecidos DESC)  AS ranking_municipio,

    -- Comparativos Municipais
    ISNULL(MUN.mediana_municipio, 0) AS municipio_mediana,
    ISNULL(MUN.media_municipio,   0) AS municipio_media,
    CAST((I.percentual_falecidos + 0.01) / (ISNULL(MUN.mediana_municipio, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_mediana,
    CAST((I.percentual_falecidos + 0.01) / (ISNULL(MUN.media_municipio,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_mun_media,

    -- Comparativos Estaduais
    ISNULL(UF.mediana_estado, 0) AS estado_mediana,
    ISNULL(UF.media_estado,   0) AS estado_media,
    CAST((I.percentual_falecidos + 0.01) / (ISNULL(UF.mediana_estado, 0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_mediana,
    CAST((I.percentual_falecidos + 0.01) / (ISNULL(UF.media_estado,   0) + 0.01) AS DECIMAL(18,4)) AS risco_relativo_uf_media,

    -- Comparativos Nacionais
    BR.mediana_pais,
    BR.media_pais AS pais_media,
    CAST((I.percentual_falecidos + 0.01) / (BR.mediana_pais + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_mediana,
    CAST((I.percentual_falecidos + 0.01) / (BR.media_pais   + 0.01) AS DECIMAL(18,4)) AS risco_relativo_br_media

INTO temp_CGUSC.fp.indicador_falecidos_detalhado
FROM temp_CGUSC.fp.indicador_falecidos I
INNER JOIN temp_CGUSC.fp.dados_farmacia F
    ON F.cnpj = I.cnpj
LEFT JOIN temp_CGUSC.fp.indicador_falecidos_mun MUN
    ON CAST(F.uf AS VARCHAR(2)) = MUN.uf
    AND CAST(F.municipio AS VARCHAR(255)) = MUN.municipio
LEFT JOIN temp_CGUSC.fp.indicador_falecidos_uf UF
    ON CAST(F.uf AS VARCHAR(2)) = UF.uf
CROSS JOIN temp_CGUSC.fp.indicador_falecidos_br BR;

CREATE CLUSTERED INDEX    IDX_Final_CNPJ  ON temp_CGUSC.fp.indicador_falecidos_detalhado(cnpj);
CREATE NONCLUSTERED INDEX IDX_Final_Risco ON temp_CGUSC.fp.indicador_falecidos_detalhado(risco_relativo_mun_mediana DESC);
CREATE NONCLUSTERED INDEX IDX_Final_Rank  ON temp_CGUSC.fp.indicador_falecidos_detalhado(ranking_br);
GO


-- ============================================================================
-- VERIFICAÇÕES
-- ============================================================================

-- 1. Resumo estratégico (Destaque para o CPF de teste)
DECLARE @CNPJ_TESTE VARCHAR(14) = '18241834000154';
SELECT * FROM temp_CGUSC.fp.indicador_falecidos_detalhado WHERE cnpj = @CNPJ_TESTE;

-- 2. Destaque dos 10 maiores faturamentos para falecidos
SELECT TOP 10 * FROM temp_CGUSC.fp.indicador_falecidos_detalhado ORDER BY valor_falecidos DESC;

-- 3. Detalhe nominal (Exemplo das primeiras autorizacoes irregulares do CNPJ teste)
SELECT TOP 50 * FROM temp_CGUSC.fp.falecidos_por_farmacia WHERE cnpj = @CNPJ_TESTE ORDER BY data_autorizacao DESC;
GO
