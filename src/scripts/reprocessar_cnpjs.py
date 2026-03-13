"""
REPROCESSAMENTO DE CNPJS - SENTINELA
=====================================

Este script é uma ferramenta de correção para o sistema Sentinela.
Seu objetivo é reprocessar uma lista específica de CNPJs que podem ter sido
processados incorretamente devido a problemas de comunicação com o banco de dados
(e.g., timeouts que resultaram em dados de vendas ausentes).

COMO FUNCIONA:
1.  **Lista de CNPJs:** O script lê uma lista de CNPJs fornecida na variável `lista_cnpjs_reprocessar`.
2.  **Limpeza:** Para cada CNPJ, ele primeiro apaga todos os registros de processamento anteriores
    das tabelas `processamentosFP` e `dadosProcessamentosFP` para evitar duplicidade.
3.  **Reprocessamento:** Em seguida, ele executa a mesma lógica de análise do script principal
    `08 - sentinela.py`, mas com um tempo de espera aumentado entre as consultas (10 segundos)
    para garantir que o banco de dados tenha tempo de retornar os dados completos.
4.  **Gravação:** Os novos dados, agora corretos, são salvos no banco de dados.

COMO USAR:
1.  **Preencha a Lista:** A etapa mais importante é preencher a variável `lista_cnpjs_reprocessar`
    com os CNPJs que você precisa corrigir. Você pode obter essa lista do arquivo de log
    `sentinela_processamento.log`, procurando pelas mensagens "não possui vendas".
2.  **Execute o Script:** Salve o arquivo e execute-o via terminal. O script irá iterar
    pela lista e reprocessar cada CNPJ.

"""
import pyodbc
import time
import decimal
from collections import defaultdict
import pandas as pd
from tqdm import tqdm
import logging
import datetime
import copy
import sys

# =============================================================================
# CONFIGURAÇÃO DE LOGGING
# =============================================================================
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    filename='reprocessamento.log',
    filemode='w'
)

# =============================================================================
# CONFIGURAÇÃO DE PRECISÃO DECIMAL
# =============================================================================
decimal.getcontext().prec = 10

# =============================================================================
# CONSTANTES GLOBAIS
# =============================================================================
DATA_INICIAL_ANALISE = '2015-07-01'
DATA_FINAL_ANALISE = datetime.datetime.strptime('2024-12-10', '%Y-%m-%d').date()
TEMPO_ESPERA_ENTRE_CNPJS = 10

# =============================================================================
# LISTA DE CNPJS PARA REPROCESSAR
# =============================================================================
# IMPORTANTE: Esta lista é apenas um exemplo.
# Você deve preenchê-la com todos os CNPJs que apresentaram a mensagem "não possui vendas".
lista_cnpjs_reprocessar = [
    "19984518000135",
    "19986033000180",
    "19987783000177",
    "19988584000183",
    "19989477000170"
]

# =============================================================================
# FUNÇÃO: CONECTAR AO BANCO DE DADOS
# =============================================================================
def conectar_bd():
    try:
        conn_str = (
            'Driver={ODBC Driver 17 for SQL Server};'
            'Server=SDH-DIE-BD;'
            'Database=temp_CGUSC;'
            'Trusted_Connection=yes;'
        )
        conn = pyodbc.connect(conn_str)
        cursor = conn.cursor()
        logging.info("Conexão com o banco de dados estabelecida com sucesso.")
        return conn, cursor
    except pyodbc.Error as ex:
        logging.critical(f"CRÍTICO: Falha ao conectar ao banco de dados. Erro: {ex}")
        print("ERRO CRÍTICO: Não foi possível conectar ao banco de dados. Verifique o log.")
        sys.exit(1)

# =============================================================================
# INICIALIZAÇÃO DA CONEXÃO E VARIÁVEIS GLOBAIS
# =============================================================================
conn, cursor = conectar_bd()

farmacia_inicio_venda = {}
try:
    cursor.execute('select * from [temp_CGUSC].dbo.farmacia_inicio_venda')
    columns = [column[0] for column in cursor.description]
    for row in cursor.fetchall():
        farmacia_inicio_venda[row[0]] = {}
        farmacia_inicio_venda[row[0]] = dict(zip(columns, row))
except (pyodbc.Error, IndexError, TypeError) as e:
    logging.critical(f"CRÍTICO: Falha ao carregar dados iniciais. O script não pode continuar. Erro: {e}")
    sys.exit(1)

# =============================================================================
# FUNÇÕES AUXILIARES
# =============================================================================
def lookahead(iterable):
    it = iter(iterable)
    last = next(it)
    for val in it:
        yield last, True
        last = val
    yield last, False

# =============================================================================
# LOOP DE REPROCESSAMENTO
# =============================================================================
for cnpj in tqdm(lista_cnpjs_reprocessar, desc="Reprocessando CNPJs"):
    logging.info(f"Iniciando reprocessamento para o CNPJ: {cnpj}")

    # Limpa dados anteriores do CNPJ
    try:
        cursor.execute("DELETE FROM [temp_CGUSC].[dbo].[dadosProcessamentosFP] WHERE id_processamento IN (SELECT id FROM [temp_CGUSC].[dbo].[processamentosFP] WHERE cnpj = ?)", cnpj)
        cursor.execute("DELETE FROM [temp_CGUSC].[dbo].[processamentosFP] WHERE cnpj = ?", cnpj)
        conn.commit()
        logging.info(f"Dados anteriores do CNPJ {cnpj} removidos com sucesso.")
    except pyodbc.Error as e:
        logging.error(f"Erro ao limpar dados anteriores do CNPJ {cnpj}. Erro: {e}")
        conn.rollback()
        continue

    start = time.time()

    inicio_venda_info = farmacia_inicio_venda.get(cnpj)
    if not inicio_venda_info:
        logging.error(f"DADOS AUSENTES: CNPJ {cnpj} não encontrado em 'farmacia_inicio_venda'. Pulando este CNPJ.")
        continue
    data_inicio_vendas_estabelecimento = inicio_venda_info['datavendainicial']
    data_inicio_vendas_estabelecimento_formated = data_inicio_vendas_estabelecimento.strftime("%Y-%m-%d")
    data_final_analise_formated = DATA_FINAL_ANALISE.strftime("%Y-%m-%d")

    results = []
    try:
        cursor.execute('''
        select * from
        (
        SELECT NULL as numeroNFE, mov.valor_pago ,mov.codigo_barra as codigoBarra, TRY_CAST( mov.data_hora as date) as data_movimentacao,
        mov.qnt_autorizada / TRY_CAST( medicamentos.qnt_comprimidos_caixa as decimal(10,0)) as qnt_caixas, 'V' as compra_venda, -1 as tipo_operacao
        FROM temp_CGUSC.dbo.movimentacaoFP mov
        inner join temp_CGUSC.[dbo].[medicamentosPatologiaFP] medicamentos on medicamentos.codigo_barra = mov.codigo_barra
        where mov.data_hora >=? and mov.data_hora <=? and mov.cnpj=?
        union all
        select numeroNFE, 0 as valor_pago ,fazenda.codigoBarra, [dataEmissaoNFE] as data_movimentacao, quantidade as qnt_caixas, 'C' as compra_venda,tipoOperacao as tipo_operacao
        from [db_farmaciapopular_nf].[dbo].[aquisicoesFazenda_2015_2025] fazenda
        inner join [temp_CGUSC].[dbo].medicamentosPatologiaFP med on med.codigo_barra = fazenda.codigoBarra
        inner join [temp_CGUSC].[dbo].farmacia_inicio_venda_gtin B on B.cnpj = fazenda.destinatarioNFE and B.codigo_barra = fazenda.codigoBarra
        where destinatarioNFE = ?
        and [dataEmissaoNFE] >= b.data_inicio_venda and [dataEmissaoNFE] <= ?
        and tipoOperacao in (1,-1,0)
        ) as t1
        where qnt_caixas <> 0
        order by codigoBarra, data_movimentacao asc, compra_venda asc
        ''', data_inicio_vendas_estabelecimento_formated, data_final_analise_formated, cnpj, cnpj, data_final_analise_formated)

        columns = [column[0] for column in cursor.description]
        for row in cursor.fetchall():
            results.append(dict(zip(columns, row)))
    except pyodbc.Error as e:
        logging.error(f"ERRO DE BANCO DE DADOS explícito ao consultar o CNPJ: {cnpj}. Erro: {e}")
        continue

    if not results:
        logging.warning(f"DIAGNÓSTICO: A consulta principal para o CNPJ {cnpj} retornou 0 linhas no reprocessamento. Pulando.")
        continue

    # =====================================================================
    # CARREGA ESTOQUES INICIAIS DESTA FARMÁCIA
    # =====================================================================

    cursor.execute('''
    select codigo_barra,estoque_inicial,cnpj_estabelecimento,data_estoque_inicial
    from [temp_CGUSC].[dbo].estoque_inicialFP
    where cnpj_estabelecimento = ? 
    ''', cnpj)

    tabela_codigo_barra_estoque_inicial = {}
    for row in cursor.fetchall():
        tabela_codigo_barra_estoque_inicial[row.codigo_barra] = row.estoque_inicial

    # =====================================================================
    # CARREGA DADOS CADASTRAIS DA FARMÁCIA
    # =====================================================================

    cursor.execute('''
    select *
    from temp_CGUSC.[dbo].dadosFarmaciasFP
    where cnpj = ? 
    ''', cnpj)

    tabela_dados_cnpj = {}
    for row in cursor.fetchall():
        tabela_dados_cnpj['cnpj'] = row.cnpj
        tabela_dados_cnpj['razao_social'] = row.razaoSocial
        tabela_dados_cnpj['nome_fantasia'] = row.nomeFantasia
        tabela_dados_cnpj['municipio'] = row.municipio
        tabela_dados_cnpj['uf'] = row.uf

    # =====================================================================
    # INICIALIZAÇÃO DE VARIÁVEIS DE CONTROLE
    # =====================================================================
    movimentacao_codigo_barra = []
    tabela_completa = {}
    codigo_barra = 0
    estoque_inicial = 0
    estoque_final = 0
    vendas_periodo = 0
    vendas_sem_comprovacao = 0
    valor_movimentado = 0
    valor_individual_medicamento = 0
    valor_sem_comprovacao = 0
    data_inicio_nao_comprovacao_codigo_barra = '9999-01-01'
    flag_primeira_venda_sem_comprovacao = 1
    periodo_inicial = 0
    periodo_final = 0
    operacao_anterior = 0
    tabela_codigo_barra_datas_vendas = defaultdict(dict)
    range_periodos_analise = pd.date_range(data_inicio_vendas_estabelecimento_formated, data_final_analise_formated, freq=pd.DateOffset(months=1)).strftime("%Y-%m").tolist()

    # =====================================================================
    # PROCESSAMENTO PRINCIPAL: ANÁLISE DE MOVIMENTAÇÕES
    # =====================================================================
    for row, has_more in lookahead(results):
        if codigo_barra == 0 or codigo_barra != row["codigoBarra"]:
            if (codigo_barra != 0 and codigo_barra != row["codigoBarra"]) and operacao_anterior == 'V':
                incluir_movimentacao_venda()
                tabela_completa[codigo_barra] = movimentacao_codigo_barra

            movimentacao_codigo_barra = []
            codigo_barra = row["codigoBarra"]
            tabela_completa[codigo_barra] = []
            tabela_codigo_barra_datas_vendas[codigo_barra] = {}

            dict_temporario = {}
            dict_temporario['qnt_vendas'] = 0
            dict_temporario['valor_vendas'] = 0
            dict_temporario['qnt_vendas_sem_comprovacao'] = 0
            dict_temporario['valor_sem_comprovacao'] = 0
            for i in range_periodos_analise:
                tabela_codigo_barra_datas_vendas[codigo_barra][i] = dict_temporario

            reset_variaveis_venda()
            reset_variaveis_estoque()

            if codigo_barra in tabela_codigo_barra_estoque_inicial.keys():
                estoque_inicial = tabela_codigo_barra_estoque_inicial[codigo_barra]
                estoque_final = tabela_codigo_barra_estoque_inicial[codigo_barra]
                data_estoque_inicial = datetime.datetime.strptime('2015-07-01', '%Y-%m-%d').date()
                movimentacao_codigo_barra.append(
                    {'tipo': 'e', 'estoque_inicial': estoque_inicial, 'data_estoque_inicial': data_estoque_inicial})
            else:
                movimentacao_codigo_barra.append(
                    {'tipo': 'e', 'estoque_inicial': 0})

        if (codigo_barra == row["codigoBarra"]):
            if (row["compra_venda"] == "V"):
                data = row["data_movimentacao"]
                mes_ano = data.strftime("%Y-%m")

                if mes_ano in tabela_codigo_barra_datas_vendas[codigo_barra].keys():
                    dict_temp = {}
                    dict_temp['qnt_vendas'] = tabela_codigo_barra_datas_vendas[codigo_barra][mes_ano]['qnt_vendas'] + row["qnt_caixas"]
                    dict_temp['valor_vendas'] = tabela_codigo_barra_datas_vendas[codigo_barra][mes_ano]['valor_vendas'] + row["valor_pago"]
                    dict_temp['qnt_vendas_sem_comprovacao'] = tabela_codigo_barra_datas_vendas[codigo_barra][mes_ano]['qnt_vendas_sem_comprovacao']
                    dict_temp['valor_sem_comprovacao'] = tabela_codigo_barra_datas_vendas[codigo_barra][mes_ano]['valor_sem_comprovacao']
                    tabela_codigo_barra_datas_vendas[codigo_barra][mes_ano] = dict_temp
                else:
                    dict_temp = {}
                    dict_temp['qnt_vendas'] = row["qnt_caixas"]
                    dict_temp['valor_vendas'] = row["valor_pago"]
                    dict_temp['qnt_vendas_sem_comprovacao'] = 0
                    dict_temp['valor_sem_comprovacao'] = 0
                    tabela_codigo_barra_datas_vendas[codigo_barra][mes_ano] = dict_temp

                valor_individual_medicamento = row["valor_pago"] / row["qnt_caixas"]
                devolucao_temp = estoque_final - row["qnt_caixas"]

                if (devolucao_temp < 0):
                    if flag_primeira_venda_sem_comprovacao == 1:
                        data_inicio_nao_comprovacao_codigo_barra = row['data_movimentacao']
                        flag_primeira_venda_sem_comprovacao = 0

                    valor_sem_comprovacao += (abs(devolucao_temp) * valor_individual_medicamento)
                    vendas_sem_comprovacao += abs(devolucao_temp)

                    tabela_codigo_barra_datas_vendas[codigo_barra][mes_ano]['qnt_vendas_sem_comprovacao'] += abs(devolucao_temp)
                    tabela_codigo_barra_datas_vendas[codigo_barra][mes_ano]['valor_sem_comprovacao'] += (abs(devolucao_temp) * valor_individual_medicamento)

                if (periodo_inicial == 0):
                    periodo_inicial = row["data_movimentacao"]
                vendas_periodo += row["qnt_caixas"]
                periodo_final = row["data_movimentacao"]
                estoque_final -= row["qnt_caixas"]

                if (estoque_final < 0):
                    estoque_final = 0
                valor_movimentado += row["valor_pago"]
                operacao_anterior = "V"

                if (has_more == False):
                    incluir_movimentacao_venda()

            elif (row["compra_venda"] == "C" and row["tipo_operacao"] == 1):
                if (operacao_anterior == "V"):
                    incluir_movimentacao_venda()
                    reset_variaveis_venda()

                if (estoque_final >= 0):
                    data_aquisicao = row["data_movimentacao"]
                    movimentacao_codigo_barra.append(
                        {'tipo': 'c', 'estoque_inicial': estoque_final, 'data_aquisicao': data_aquisicao,
                         'qnt_aquisicao': row["qnt_caixas"], 'numeroNFE': row["numeroNFE"],
                         'estoque_final': estoque_final + row["qnt_caixas"]})

                estoque_inicial = estoque_final + row["qnt_caixas"]
                estoque_final = estoque_inicial
                operacao_anterior = "C"

            elif (row["compra_venda"] == "C" and row["tipo_operacao"] == 0):
                if operacao_anterior == "V":
                    incluir_movimentacao_venda()
                    reset_variaveis_venda()

                if estoque_final >= 0:
                    data_devolucao = row["data_movimentacao"]
                    movimentacao_codigo_barra.append(
                        {'tipo': 'd', 'estoque_inicial': estoque_final, 'data_devolucao': data_devolucao,
                         'qnt_devolucao': row["qnt_caixas"], 'numeroNFE': row["numeroNFE"],
                         'estoque_final': estoque_final - row["qnt_caixas"]})

                estoque_inicial = estoque_final - row["qnt_caixas"]
                estoque_final = estoque_inicial
                operacao_anterior = "C"

            tabela_completa[codigo_barra] = movimentacao_codigo_barra

    # =====================================================================
    # GRAVAÇÃO DOS RESULTADOS NO BANCO DE DADOS
    # =====================================================================
    data_hora_processamento = datetime.datetime.now()
    cursor.execute('''
    insert into [temp_CGUSC].[dbo].[processamentosFP] (cnpj, razao_social, nome_fantasia, municipio, uf, periodo_inicial, periodo_final,data_processamento, situacao) values (?,?,?,?,?,?,?,?,?)
    ''', cnpj, tabela_dados_cnpj['razao_social'], tabela_dados_cnpj['nome_fantasia'],
                   tabela_dados_cnpj['municipio'],
                   tabela_dados_cnpj['uf'], data_inicio_vendas_estabelecimento, DATA_FINAL_ANALISE, data_hora_processamento, 1)
    conn.commit()

    id_processamento = None
    cursor.execute('''
    select top 1 id from [temp_CGUSC].[dbo].[processamentosFP]
    where cnpj = ?
    order by data_processamento desc
    ''', cnpj)

    rows = cursor.fetchall()
    for row in rows:
        id_processamento = row.id

    for i in tabela_completa.items():
        cursor.execute('''
        insert into [temp_CGUSC].[dbo].dadosProcessamentosFP(id_processamento,codigo_barra, tipo, vendas_periodo, vendas_sem_comprovacao, qnt_aquis_dev) values (?,?, ?, ?, ?, ?)
        ''', id_processamento, i[0], 'h', 1, 1, 1)
        conn.commit()

        for j, has_more in lookahead(i[1]):
            tipo = j['tipo']
            bar_code = i[0]

            if tipo == 'c':
                cursor.execute('''
                insert into [temp_CGUSC].[dbo].dadosProcessamentosFP(id_processamento,codigo_barra, tipo, estoque_inicial, estoque_final,data_aquis_dev_estoq, qnt_aquis_dev,numero_nfe) values (?,?, ?, ?, ?, ?, ?, ?)
                ''', id_processamento, bar_code, tipo, j['estoque_inicial'], j['estoque_final'],
                               j['data_aquisicao'],
                               j['qnt_aquisicao'], j['numeroNFE'])
                conn.commit()

            elif tipo == 'v':
                cursor.execute('''
                insert into [temp_CGUSC].[dbo].dadosProcessamentosFP(id_processamento,codigo_barra, tipo, periodo_inicial, periodo_inicial_nao_comprovacao, periodo_final, estoque_inicial, vendas_periodo, estoque_final, vendas_sem_comprovacao, valor_movimentado, valor_sem_comprovacao) values (?,?, ?, ?, ?,?,?,?, ?, ?, ?,?)
                ''', id_processamento, bar_code, tipo, j['periodo_inicial'],
                               j['data_inicio_nao_comprovacao_codigo_barra'], j['periodo_final'],
                               j['estoque_inicial'],
                               j['vendas_periodo'], j['estoque_final'], j['vendas_sem_comprovacao'],
                               j['valor_movimentado'], j['valor_sem_comprovacao'], )
                conn.commit()

            elif tipo == 'd':
                cursor.execute('''
                insert into [temp_CGUSC].[dbo].dadosProcessamentosFP(id_processamento,codigo_barra, tipo, estoque_inicial, estoque_final,data_aquis_dev_estoq, qnt_aquis_dev,numero_nfe) values (?,?, ?, ?, ?, ?, ?, ?)
                ''', id_processamento, bar_code, tipo, j['estoque_inicial'], j['estoque_final'],
                               j['data_devolucao'],
                               j['qnt_devolucao'], j['numeroNFE'])
                conn.commit()

            elif tipo == 'e':
                data_estoque = None
                if j['estoque_inicial'] > 0:
                    data_estoque = j['data_estoque_inicial']
                cursor.execute('''
                insert into [temp_CGUSC].[dbo].dadosProcessamentosFP(id_processamento,codigo_barra, tipo, estoque_inicial, data_aquis_dev_estoq) values (?,?, ?, ?, ?)
                ''', id_processamento, bar_code, tipo, j['estoque_inicial'], data_estoque)
                conn.commit()

    logging.info(f"CNPJ {cnpj} reprocessado com sucesso em {time.time() - start:.2f} segundos.")
    logging.info(f"Aguardando {TEMPO_ESPERA_ENTRE_CNPJS} segundos antes do próximo CNPJ...")
    time.sleep(TEMPO_ESPERA_ENTRE_CNPJS)

print("Reprocessamento concluído.")