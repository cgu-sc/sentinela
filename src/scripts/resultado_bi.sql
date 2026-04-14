SELECT df.[cnpj]
      ,df.[razaoSocial]
    ,df.[nomeFantasia]
      ,[codibge]
    ,p.descricao AS porte_empresa
      ,[indPossuiSocio]
      ,[situacaoCadastral]
      ,[situacaoReceita]
      ,[dataSituacaoCadastral]
      ,[codNaturezaJuridica]
      ,[natuezaJuridica]
    ,M.cnpj_matriz
    ,M.razao_social_matriz
    ,r.[qnt_medicamentos_vendidos] AS qnt_medicamentos_vendidos_TOTAL
      ,r.[qnt_medicamentos_vendidos_sem_comprovacao] AS qnt_medicamentos_vendidos_sem_comprovacao_TOTAL
      ,r.[nu_autorizacoes] AS nu_autorizacoes_TOTAL
      ,r.[valor_vendas] AS valor_vendas_TOTAL
      ,r.[valor_sem_comprovacao] AS valor_sem_comprovacao_TOTAL
      ,CASE
    WHEN r.percentual_sem_comprovacao > 1 THEN 1
    ELSE r.percentual_sem_comprovacao
    END AS percentual
    ,CASE
    WHEN r.percentual_sem_comprovacao = 0 THEN '0'
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
    END AS '% Não Comprovado'
    ,CASE
      WHEN r.percentual_sem_comprovacao = 0 THEN 0
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
      END AS 'Categoria Risco'
      ,[num_meses_movimentacao]
      ,[valor_multa] AS valor_multa_TOTAL
      ,[percentual_falecidos_gerencial]
      ,[valor_vendas_falecidos]
      ,[SCORE_GERAL_RISCO]
      ,[rr_falecidos_uf]
      ,[rr_falecidos_br]
      ,[pct_compra_unica]
      ,[rr_compra_unica_uf]
      ,[rr_compra_unica_br]
      ,[pct_inconsistencia_clinica]
      ,[rr_inconsistencia_clinica_uf]
      ,[rr_inconsistencia_clinica_br]
      ,[pct_teto_maximo]
      ,[rr_teto_maximo_uf]
      ,[rr_teto_maximo_br]
      ,[pct_polimedicamento]
      ,[rr_polimedicamento_uf]
      ,[rr_polimedicamento_br]

      ,[pct_vendas_rapidas_60s]
      ,[rr_vendas_rapidas_uf]
      ,[rr_vendas_rapidas_br]
      ,[pct_horario_atipico]
      ,[rr_horario_atipico_uf]
      ,[rr_horario_atipico_br]
      ,[pct_concentracao_pico]
      ,[rr_concentracao_pico_uf]
      ,[rr_concentracao_pico_br]
      ,[val_ticket_medio]
      ,[rr_ticket_medio_uf]
      ,[rr_ticket_medio_br]
      ,[val_receita_por_paciente]
      ,[rr_receita_por_paciente_uf]
      ,[rr_receita_por_paciente_br]
      ,[val_venda_per_capita_municipio]
      ,[rr_venda_per_capita_uf]
      ,[rr_venda_per_capita_br]
      ,[pct_alto_custo]
      ,[rr_alto_custo_uf]
      ,[rr_alto_custo_br]
      ,ISNULL(V.risco_final, 0) AS val_volume_atipico
      ,CASE WHEN V.risco_final > 0 THEN 1 ELSE 0 END AS tem_volume_atipico
      ,ISNULL(V.qtd_semestres_risco, 0) AS qtd_semestres_risco_atipico
      ,ISNULL(V.qtd_comparacoes, 0) AS total_comparacoes_volume
      ,ISNULL(V.risco_relativo_reg_mediana, 0) AS rr_volume_atipico_reg
  FROM [temp_CGUSC].[dbo].[dadosFarmaciasFP] AS df
  INNER JOIN [temp_CGUSC].[fp].[resultado_Sentinela_2015_2024] AS r
    ON df.cnpj = r.cnpj
  LEFT JOIN temp_CGUSC.dbo.CNPJ_matrizesFP AS M
    ON df.cnpj = M.cnpj_filial
  LEFT JOIN [temp_CGUSC].[dbo].[porteEmpresa] as p
    ON df.CodPorteEmpresa = p.codPorteEmpresa
  LEFT JOIN temp_CGUSC.fp.indicador_volume_atipico_detalhado V
    ON df.cnpj = V.cnpj