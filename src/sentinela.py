
from datetime import date, datetime
import copy
import os
import zlib
import json
from decimal import Decimal
import sys
from collections import defaultdict
import pyodbc
import pandas as pd
import locale
import time
import decimal
from decimal import *
from tqdm import tqdm
import art
import logging

# =============================================================================
# CONFIGURAÇÃO DE LOGGING
# =============================================================================
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    filename='sentinela_processamento.log',
    filemode='a'
)

# =============================================================================
# CONFIGURAÇÃO DE LOCALE E PRECISÃO DECIMAL
# =============================================================================
try:
    locale.setlocale(locale.LC_ALL, 'pt_BR.UTF-8')
except locale.Error:
    try:
        locale.setlocale(locale.LC_ALL, 'Portuguese_Brazil.1252')
    except locale.Error:
        logging.warning("Não foi possível definir o locale para PT-BR. Usando padrão do sistema.")

decimal.getcontext().prec = 10

# =============================================================================
# CONSTANTES GLOBAIS E DE STATUS
# =============================================================================
DATA_INICIAL_ANALISE = '2015-07-01'
DATA_FINAL_ANALISE = datetime.strptime('2024-12-10', '%Y-%m-%d').date()
CRITERIO_ESTOQUE_INICIAL = 'Critério para estimativa do estoque inicial: Soma das duas últimas aquisições, considerando os 6 meses anteriores à primeira venda.'
TEMPO_ESPERA_ENTRE_CNPJS = 0

# Constantes de Status do Banco de Dados
SIT_SUCCESS = 1      # Concluído com sucesso
SIT_RUNNING = 2      # Processamento em andamento
SIT_FAILED = 3       # Falhou durante execução
SIT_NO_DATA = 4      # Sem dados para processar
SIT_NO_SALES = 5    #(Sem vendas no período)
SIT_NO_ISSUES = 6    # Processado mas sem irregularidades

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
# INICIALIZAÇÃO DA CONEXÃO
# =============================================================================
conn, cursor = conectar_bd()

# Variáveis globais de referência
total_cnpjs = 0
data_inicio_estoque = None
dados_farmacias = {}
dados_medicamentos = {}
contato_farmacia = {}
farmacia_inicio_venda = {}

# =============================================================================
# CARREGAMENTO DE DADOS INICIAIS (TABELAS AUXILIARES)
# =============================================================================
try:
    logging.info("Executando consultas iniciais para carregar tabelas acessorias")

    cursor.execute('select count(cnpj) from [temp_CGUSC].fp.classif')
    total_cnpjs = cursor.fetchone()[0]

    cursor.execute('select min(data_estoque_inicial) data from estoque_inicialFP')
    row = cursor.fetchone()
    data_inicio_estoque = row[0] if row and row[0] else datetime.strptime('2015-01-01', '%Y-%m-%d').date()

    cursor.execute('select cnpj,razaoSocial,municipio,uf from temp_CGUSC.[fp].dadosFarmaciasFP')
    cols = [column[0] for column in cursor.description]
    for row in cursor.fetchall():
        dados_farmacias[row[0]] = dict(zip(cols, row))

    cursor.execute('select codigo_barra,principio_ativo from temp_CGUSC.[fp].medicamentosPatologiaFP')
    cols = [column[0] for column in cursor.description]
    for row in cursor.fetchall():
        dados_medicamentos[row[0]] = dict(zip(cols, row))

    cursor.execute('select * from temp_CGUSC.[fp].contatoFarmacia')
    cols = [column[0] for column in cursor.description]
    for row in cursor.fetchall():
        contato_farmacia[row[0]] = dict(zip(cols, row))

    cursor.execute('select * from [temp_CGUSC].fp.farmacia_inicio_venda')
    cols = [column[0] for column in cursor.description]
    for row in cursor.fetchall():
        farmacia_inicio_venda[row[0]] = dict(zip(cols, row))

    logging.info("Dados iniciais carregados com sucesso.")

except (pyodbc.Error, IndexError, TypeError) as e:
    logging.critical(f"CRÍTICO: Falha ao carregar dados iniciais. Erro: {e}")
    sys.exit(1)


# =============================================================================
# FUNÇÃO: VERIFICAR PROCESSAMENTO PREVIO PARA OTIMIZAÇÃO
# =============================================================================
def verificar_processamento_existente(cursor, cnpj):
    """
    Verifica se o CNPJ já foi processado e finalizado com sucesso (1 ou 6).
    Retorna True se o CNPJ deve ser pulado, False caso contrário.
    """
    try:
        # Busca o status mais recente do CNPJ
        cursor.execute('''
            SELECT TOP 1 situacao, data_processamento
            FROM [temp_CGUSC].[fp].[processamentosFP]
            WHERE cnpj = ? 
            ORDER BY data_processamento DESC
        ''', cnpj)

        row = cursor.fetchone()

        if row:
            situacao = row[0]
            data_proc = row[1].strftime('%d/%m/%Y %H:%M')

            # Se a situação for 1 (SUCCESS com irregularidades) ou 6 (NO_ISSUES sem irregularidades), pule.
            if situacao in (SIT_SUCCESS, SIT_NO_ISSUES):  # (1 ou 6)
                logging.info(f"CNPJ {cnpj} já processado com sucesso (Status: {situacao}) em {data_proc}. Pulando...")
                return True

            logging.info(
                f"CNPJ {cnpj} encontrado com status pendente (Status: {situacao}) em {data_proc}. Reprocessando...")
            return False

        # Se não houver registro na tabela, retorne False para processar.
        return False

    except pyodbc.Error as e:
        # Em caso de erro de consulta, logar o erro e retornar False para forçar o processamento
        logging.error(f"Erro ao verificar processamento prévio para CNPJ {cnpj}: {e}. Forçando reprocessamento.")
        return False


# --- CLASSE AUXILIAR PARA TRADUZIR DATAS E DECIMAIS PARA JSON ---
class CustomJSONEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, (date, datetime)):
            return obj.isoformat()  # Converte data para string "2024-01-01"
        if isinstance(obj, Decimal):
            return float(obj)  # Converte Decimal para Float
        return super().default(obj)


def salvar_memoria_calculo(cursor, conn, id_processamento, cnpj, dados_brutos):
    """
    Serializa a memória de cálculo para JSON, COMPACTA (Zlib) e salva como binário.
    Redução de tamanho estimada: ~90%.
    """
    if not id_processamento or not dados_brutos:
        return

    try:
        # 1. Gera o texto JSON
        json_str = json.dumps(dados_brutos, cls=CustomJSONEncoder)

        # 2. Converte para Bytes e Comprime (Nível 9 = Máxima compressão)
        dados_comprimidos = zlib.compress(json_str.encode('utf-8'), level=9)

        # Opcional: Log para você ver a diferença (pode remover depois)
        # tamanho_original = len(json_str) / 1024
        # tamanho_final = len(dados_comprimidos) / 1024
        # logging.info(f"Compressão CNPJ {cnpj}: {tamanho_original:.1f}KB -> {tamanho_final:.1f}KB")

        # 3. Salva no Banco (Coluna VARBINARY)
        cursor.execute('''
            INSERT INTO temp_CGUSC.fp.memoria_calculo_consolidadaFP 
            (id_processamento, cnpj, dados_comprimidos)
            VALUES (?, ?, ?)
        ''', id_processamento, cnpj, dados_comprimidos)

        conn.commit()

    except Exception as e:
        logging.error(f"Erro ao salvar memória comprimida para {cnpj}: {e}")


# =============================================================================
# FUNÇÕES DE GERENCIAMENTO DE ESTADO DO PROCESSAMENTO (NOVO)
# =============================================================================

def iniciar_processamento_cnpj(cursor, conn, cnpj, dt_inicio, dt_final, dados_cnpj):
    """
    Registra o início do processamento de um CNPJ com status RUNNING.
    Retorna o ID do registro criado.
    """
    try:
        cursor.execute('''
            INSERT INTO [temp_CGUSC].[fp].[processamentosFP] 
            (cnpj, razao_social, nome_fantasia, municipio, uf, 
             periodo_inicial, periodo_final, data_processamento, 
             situacao, status_detalhado) 
            VALUES (?,?,?,?,?,?,?,?,?,?)
        ''',
        cnpj,
        dados_cnpj.get('razao_social'),
        dados_cnpj.get('nome_fantasia'),
        dados_cnpj.get('municipio'),
        dados_cnpj.get('uf'),
        dt_inicio,
        dt_final,
        datetime.now(),
        SIT_RUNNING,
        'Processamento iniciado')

        conn.commit()

        # Recupera o ID gerado
        cursor.execute('''
            SELECT TOP 1 id 
            FROM [temp_CGUSC].[fp].[processamentosFP] 
            WHERE cnpj = ? 
            ORDER BY data_processamento DESC
        ''', cnpj)

        result = cursor.fetchone()
        id_processamento = result[0] if result else None

        logging.info(f"CNPJ {cnpj} - Processamento iniciado. ID: {id_processamento}")
        return id_processamento

    except pyodbc.Error as e:
        logging.error(f"Erro ao iniciar processamento do CNPJ {cnpj}: {e}")
        return None


def finalizar_processamento_sucesso(cursor, conn, id_processamento, cnpj,
                                    tempo_total, total_registros, total_medicamentos,
                                    tem_irregularidades):
    """
    Atualiza o registro com status de SUCESSO e informações de execução.
    A mensagem detalhada é unificada para "Processamento concluído com sucesso".
    O código de status numérico (situacao) ainda distingue entre com/sem irregularidades.
    """
    try:
        if not id_processamento: return

        # O código de status numérico (situacao) ainda distingue (1 ou 6)
        status = SIT_SUCCESS if tem_irregularidades else SIT_NO_ISSUES

        # MENSAGEM UNIFICADA, conforme solicitado:
        msg = 'Processamento concluído com sucesso'

        cursor.execute('''
            UPDATE [temp_CGUSC].[fp].[processamentosFP]
            SET situacao = ?,
                status_detalhado = ?,
                tempo_processamento_segundos = ?,
                total_registros_processados = ?,
                total_medicamentos = ?
            WHERE id = ?
        ''', status, msg, tempo_total, total_registros, total_medicamentos, id_processamento)

        conn.commit()
        # O logging interno ainda pode mostrar o status numérico para fins de depuração
        logging.info(f"CNPJ {cnpj} - Finalizado com sucesso. Status numérico: {status}")

    except pyodbc.Error as e:
        logging.error(f"Erro ao finalizar processamento do CNPJ {cnpj}: {e}")


def finalizar_processamento_sem_dados(cursor, conn, id_processamento, cnpj,
                                     tempo_total, motivo):
    """
    Atualiza o registro quando não há dados para processar.
    """
    try:
        if not id_processamento: return

        status = SIT_NO_DATA if 'sem dados' in motivo.lower() else SIT_NO_SALES

        cursor.execute('''
            UPDATE [temp_CGUSC].[fp].[processamentosFP]
            SET situacao = ?,
                status_detalhado = ?,
                tempo_processamento_segundos = ?
            WHERE id = ?
        ''', status, motivo, tempo_total, id_processamento)

        conn.commit()
        logging.info(f"CNPJ {cnpj} - {motivo}. Status: {status}")

    except pyodbc.Error as e:
        logging.error(f"Erro ao atualizar status sem dados do CNPJ {cnpj}: {e}")


def finalizar_processamento_erro(cursor, conn, id_processamento, cnpj,
                                 tempo_total, erro):
    """
    Atualiza o registro com status de FALHA e detalhes do erro.
    """
    try:
        if not id_processamento: return

        erro_msg = f"ERRO: {str(erro)[:450]}"  # Limita tamanho da mensagem

        cursor.execute('''
            UPDATE [temp_CGUSC].[fp].[processamentosFP]
            SET situacao = ?,
                status_detalhado = ?,
                tempo_processamento_segundos = ?
            WHERE id = ?
        ''', SIT_FAILED, erro_msg, tempo_total, id_processamento)

        conn.commit()
        logging.error(f"CNPJ {cnpj} - FALHA registrada: {erro_msg}")

    except pyodbc.Error as e:
        logging.critical(f"ERRO CRÍTICO: Falha ao registrar erro do CNPJ {cnpj}: {e}")


def verificar_processamentos_pendentes(cursor):
    """
    Verifica se existem processamentos com status RUNNING de execuções anteriores.
    """
    try:
        cursor.execute('''
            SELECT cnpj, data_processamento, id
            FROM [temp_CGUSC].[fp].[processamentosFP]
            WHERE situacao = ?
            ORDER BY data_processamento DESC
        ''', SIT_RUNNING)

        pendentes = cursor.fetchall()

        if pendentes:
            logging.warning(f"ATENÇÃO: {len(pendentes)} processamento(s) encontrado(s) com status RUNNING.")
            logging.warning("Isso indica possível falha em execução anterior. Verifique o Log.")

            # Auto-cleanup (Opcional - Marcando como Falha Genérica)
            cursor.execute('''
                UPDATE [temp_CGUSC].[fp].[processamentosFP]
                SET situacao = ?,
                    status_detalhado = 'FALHA AUTOMÁTICA: Execução anterior interrompida abruptamente'
                WHERE situacao = ?
            ''', SIT_FAILED, SIT_RUNNING)
            cursor.connection.commit()
            logging.info("Processamentos pendentes marcados automaticamente como FAILED.")

    except pyodbc.Error as e:
        logging.error(f"Erro ao verificar processamentos pendentes: {e}")

# =============================================================================
# FUNÇÕES DE INTERFACE
# =============================================================================
def limpar_tela():
    os.system('cls' if os.name == 'nt' else 'clear')

def exibir_cabecalho():
    """
    Exibe o cabeçalho ASCII do sistema com informações de configuração.
    Mostra: total de CNPJs, período de análise, critérios e configurações.
    """
    limpar_tela()
    # Cria arte ASCII com o nome do sistema
    ascii_art = art.text2art("SENTINELA", font='tarty1')
    print(ascii_art)
    print("-" * 120)

    # Exibe informações de contexto
    print(f"Total de CNPJs a serem analisados: {total_cnpjs}")
    data_inicio_formatada = datetime.strptime(DATA_INICIAL_ANALISE, '%Y-%m-%d').strftime('%d/%m/%Y')
    data_fim_formatada = DATA_FINAL_ANALISE.strftime('%d/%m/%Y')
    data_inicio_estoque_formatada = data_inicio_estoque.strftime('%d/%m/%Y')
    print(f"Período da Análise: {data_inicio_formatada} a {data_fim_formatada}")
    print(f"Data mínima para definição dos estoques inicias: {data_inicio_estoque_formatada}")
    print(f"{CRITERIO_ESTOQUE_INICIAL}")
    print(f"Pausa configurada entre CNPJs: {TEMPO_ESPERA_ENTRE_CNPJS} segundos")
    print("-" * 120)

exibir_cabecalho()



# =============================================================================
# VERIFICAÇÃO DE PENDÊNCIAS (NOVO)
# =============================================================================
logging.info("Verificando processamentos pendentes...")
verificar_processamentos_pendentes(cursor)

# =============================================================================
# PREPARAÇÃO DOS LOTES (CLASSIF)
# =============================================================================
cursor.execute('select classif, count(*) from [temp_CGUSC].fp.classif group by classif order by classif')
classif_list = [row[0] for row in cursor.fetchall()]

# =============================================================================
# LOOP PRINCIPAL (MODIFICADO PARA ROBUSTEZ E LOGGING DE PERFORMANCE)
# =============================================================================
for i in tqdm(classif_list, desc=f"{'Progresso Geral:':<25}", position=0, ncols=120):
    valor_i = i[0] if isinstance(i, (tuple, list)) else i

    cursor.execute('select cnpj from [temp_CGUSC].fp.classif where classif = ? ORDER BY cnpj', valor_i)
    lista_cnpjs = [row[0] for row in cursor.fetchall()]

    logging.info(f"Executando [procPreparaDados] para Bloco: {valor_i}")
    start_proc = time.time()

    # Chama Procedure (SQL)
    try:
        cursor.execute("SET NOCOUNT ON; DECLARE @r INT; EXEC [fp].[procPreparaDados] @classif = ?, @rowcount = @r OUTPUT, @validar = 1; SELECT @r;", valor_i)
        row_saida = cursor.fetchone()[0]
    except pyodbc.Error as e:
        logging.error(f"Erro na Procedure do Bloco {valor_i}: {e}")
        continue

    logging.info(f"Bloco {valor_i} preparado. Linhas: {row_saida}. Tempo: {time.time() - start_proc:.2f}s")

    # Loop por CNPJ
    for cnpj in tqdm(lista_cnpjs, desc=f"Bloco {valor_i}:".ljust(25), position=1, leave=False, ncols=120):
        logging.info(f"============== INÍCIO CNPJ: {cnpj} ==============")

        if verificar_processamento_existente(cursor, cnpj):
            continue

        t_start_cnpj = time.time()
        id_proc_atual = None # ID do registro na tabela processamentosFP

        # Variáveis de Performance (RESTAURADAS)
        t_query_main = 0
        t_query_aux = 0
        t_logic = 0
        t_db_write = 0
        t_excel = 0

        try:  # BLOCO TRY PRINCIPAL DO CNPJ (ROBUSTEZ)

            # --- 0. PREPARAÇÃO DE DADOS CADASTRAIS ---
            rf = None
            tabela_dados_cnpj = {}
            try:
                cursor.execute('select * from temp_CGUSC.[fp].dadosFarmaciasFP where cnpj = ?', cnpj)
                rf = cursor.fetchone()
                tabela_dados_cnpj = {'razao_social': rf.razaoSocial, 'nome_fantasia': rf.nomeFantasia,
                                     'municipio': rf.municipio, 'uf': rf.uf} if rf else {}
            except Exception:
                tabela_dados_cnpj = {}

            inicio_info = farmacia_inicio_venda.get(cnpj)

            # =========================================================================
            # LÓGICA DE DATAS - VERSÃO BLINDADA (OBJETOS DATE)
            # =========================================================================
            # 1. Define o limite RÍGIDO (01/07/2015)
            data_corte_regra = datetime.strptime(DATA_INICIAL_ANALISE, '%Y-%m-%d').date()

            # 2. Define data inicial padrão
            dt_inicio_processamento = data_corte_regra

            if inicio_info:
                dt_real_farmacia = inicio_info['datavendainicial']
                if isinstance(dt_real_farmacia, datetime):
                    dt_real_farmacia = dt_real_farmacia.date()

                # Só usa a data da farmácia se for POSTERIOR ao corte (ex: abriu em 2018)
                if dt_real_farmacia > data_corte_regra:
                    dt_inicio_processamento = dt_real_farmacia

            # 3. Ajuste para DIA 01 (Evita bugs do Pandas e SQL)
            dt_objeto_inicio = dt_inicio_processamento.replace(day=1)

            # Variáveis Formatadas (Apenas para Logs e Pandas)
            dt_inicio_fmt = dt_objeto_inicio.strftime("%Y-%m-%d")
            dt_final_fmt = DATA_FINAL_ANALISE.strftime("%Y-%m-%d")

            # Variável para o Banco de Dados (ProcessamentosFP) - Mantém original
            dt_inicio_gravar_banco = dt_inicio_processamento

            logging.info(
                f"CNPJ {cnpj}: Abertura Real: {inicio_info['datavendainicial'] if inicio_info else 'N/A'} -> Filtro SQL: {dt_objeto_inicio}")

            # --- 1. INICIA ESTADO NO BANCO (RUNNING) ---
            id_proc_atual = iniciar_processamento_cnpj(cursor, conn, cnpj,
                                                       dt_inicio_gravar_banco,  # Grava data original
                                                       DATA_FINAL_ANALISE,
                                                       tabela_dados_cnpj)

            # Valida se tem data de início (mesmo com a regra fixa, precisa ter cadastro)
            if not inicio_info:
                msg = f"CNPJ {cnpj} ignorado (Sem data inicio venda)"
                logging.warning(msg)
                finalizar_processamento_sem_dados(cursor, conn, id_proc_atual, cnpj, time.time() - t_start_cnpj, msg)
                continue

            # --- 2. QUERY PRINCIPAL (PASSANDO OBJETOS DE DATA) ---
            t0 = time.time()
            results = []

            # ATENÇÃO: Passamos 'dt_objeto_inicio' (objeto date) e não a string.
            cursor.execute('''
                    select * from (
                        -- PARTE 1: VENDAS
                        SELECT NULL as numeroNFE, mov.valor_pago, mov.codigo_barra as codigoBarra, 
                               TRY_CAST(mov.data_hora as date) as data_movimentacao, 
                               mov.qnt_autorizada / TRY_CAST(medicamentos.qnt_comprimidos_caixa as decimal(10,0)) as qnt_caixas, 
                               'V' as compra_venda, -1 as tipo_operacao 
                        FROM temp_CGUSC.fp.movimentacaoFP mov
                        inner join temp_CGUSC.[fp].[medicamentosPatologiaFP] medicamentos on medicamentos.codigo_barra = mov.codigo_barra
                        where mov.data_hora >= ? and mov.data_hora <= ? and mov.cnpj = ?

                        union all

                        -- PARTE 2: AQUISIÇÕES
                        select numeroNFE, 0 as valor_pago, fazenda.codigoBarra, [dataEmissaoNFE] as data_movimentacao, 
                               quantidade as qnt_caixas, 'C' as compra_venda, tipoOperacao as tipo_operacao
                        from [db_farmaciapopular_nf].[fp].[aquisicoesFazenda_2015_2025] fazenda
                        inner join [temp_CGUSC].[fp].medicamentosPatologiaFP med on med.codigo_barra = fazenda.codigoBarra
                        inner join [temp_CGUSC].[fp].farmacia_inicio_venda_gtin B on B.cnpj = fazenda.destinatarioNFE and B.codigo_barra = fazenda.codigoBarra
                        where destinatarioNFE = ? and [dataEmissaoNFE] >= ? and [dataEmissaoNFE] <= ? and tipoOperacao in (1,-1,0)
                    ) as t1 where qnt_caixas <> 0 order by codigoBarra, data_movimentacao asc, compra_venda asc
                    ''',
                           dt_objeto_inicio, DATA_FINAL_ANALISE, cnpj,  # Parametros Vendas (Objetos date/datetime)
                           cnpj, dt_objeto_inicio, DATA_FINAL_ANALISE  # Parametros Aquisições (Objetos date/datetime)
                           )

            cols = [column[0] for column in cursor.description]
            results = [dict(zip(cols, r)) for r in cursor.fetchall()]


            t_query_main = time.time() - t0 # ATUALIZA VARIÁVEL DE PERFORMANCE
            print(f"  ⏱ Tempo da query: {t_query_main:.4f}s")

            if results:
                vendas = [r for r in results if r["compra_venda"] == "V"]
                compras = [r for r in results if r["compra_venda"] == "C"]

                if vendas:
                    data_min_venda = min(v["data_movimentacao"] for v in vendas)
                    data_max_venda = max(v["data_movimentacao"] for v in vendas)
                    total_vendas = len(vendas)
                    print(
                        f"  ✓ Vendas (movimentacaoFP): {total_vendas} registros | Período real: {data_min_venda:%d/%m/%Y} a {data_max_venda:%d/%m/%Y}")
                else:
                    print(f"  ⚠ Vendas (movimentacaoFP): 0 registros")

                if compras:
                    data_min_compra = min(c["data_movimentacao"] for c in compras)
                    data_max_compra = max(c["data_movimentacao"] for c in compras)
                    total_compras = len(compras)
                    print(
                        f"  ✓ Aquisições (fazenda): {total_compras} registros | Período real: {data_min_compra:%d/%m/%Y} a {data_max_compra:%d/%m/%Y}")
                else:
                    print(f"  ⚠ Aquisições (fazenda): 0 registros")

                print(f"  ✓ Total de registros retornados: {len(results)}")
            else:
                logging.warning(f"  ⚠ Nenhum registro retornado pela query principal")



            if not results:
                msg = f"CNPJ {cnpj} sem registros retornados na query principal"
                print(msg)
                finalizar_processamento_sem_dados(cursor, conn, id_proc_atual, cnpj, time.time() - t_start_cnpj, msg)
                continue

            # --- 3. QUERIES AUXILIARES ---
            t0 = time.time()
            cursor.execute('select codigo_barra,estoque_inicial from [temp_CGUSC].[fp].estoque_inicialFP where cnpj_estabelecimento = ?', cnpj)
            tabela_codigo_barra_estoque_inicial = {row.codigo_barra: row.estoque_inicial for row in cursor.fetchall()}
            t_query_aux = time.time() - t0 # ATUALIZA VARIÁVEL DE PERFORMANCE

            # =====================================================================
            # PROCESSAMENTO LÓGICO (IN-MEMORY)
            # =====================================================================
            t0 = time.time()
            movimentacao_codigo_barra = []
            tabela_completa = {}
            tabela_codigo_barra_datas_vendas = defaultdict(dict)
            range_periodos = pd.date_range(dt_inicio_fmt, dt_final_fmt, freq='MS').strftime("%Y-%m").tolist()

            estado = {
                'codigo_barra': 0,
                'estoque_inicial': 0, 'estoque_final': 0,
                'operacao_anterior': 0,
                'vendas_periodo': 0, 'vendas_sem_comprovacao': 0,
                'valor_movimentado': 0, 'valor_sem_comprovacao': 0,
                'periodo_inicial': 0, 'periodo_final': 0,
                'data_inicio_nao_comprovacao': '9999-01-01', 'flag_primeira_irregularidade': 1
            }

            def lookahead(iterable):
                it = iter(iterable)
                try: last = next(it)
                except StopIteration: return
                for val in it: yield last, True; last = val
                yield last, False

            def reset_venda():
                estado['vendas_periodo'] = 0
                estado['vendas_sem_comprovacao'] = 0
                estado['valor_movimentado'] = 0
                estado['valor_sem_comprovacao'] = 0
                estado['periodo_inicial'] = 0
                estado['periodo_final'] = 0
                estado['data_inicio_nao_comprovacao'] = '9999-01-01'
                estado['flag_primeira_irregularidade'] = 1

            def incluir_venda():
                movimentacao_codigo_barra.append({
                    'tipo': 'v', 'codigo_barra': estado['codigo_barra'],
                    'periodo_inicial': estado['periodo_inicial'], 'periodo_final': estado['periodo_final'],
                    'estoque_inicial': estado['estoque_inicial'], 'estoque_final': estado['estoque_final'],
                    'vendas_periodo': estado['vendas_periodo'], 'vendas_sem_comprovacao': estado['vendas_sem_comprovacao'],
                    'valor_movimentado': estado['valor_movimentado'], 'valor_sem_comprovacao': estado['valor_sem_comprovacao'],
                    'periodo_inicial_nao_comprovacao': estado['data_inicio_nao_comprovacao'],
                    'data_aquis_dev_estoq': None, 'qnt_aquis_dev': 0, 'numero_nfe': None
                })

            # -- LÓGICA CORE (PRESERVADA) --
            for row, has_more in lookahead(results):
                # Mudança de Medicamento (GTIN)
                if estado['codigo_barra'] == 0 or estado['codigo_barra'] != row["codigoBarra"]:
                    if estado['codigo_barra'] != 0 and estado['operacao_anterior'] == 'V':
                        incluir_venda()
                        tabela_completa[estado['codigo_barra']] = movimentacao_codigo_barra

                    movimentacao_codigo_barra = []
                    estado['codigo_barra'] = row["codigoBarra"]
                    tabela_completa[estado['codigo_barra']] = []
                    tabela_codigo_barra_datas_vendas[estado['codigo_barra']] = {p: {'qnt_vendas_mes':0,'valor_vendas_mes':0,'qnt_vendas_sc_mes':0,'valor_vendas_sc_mes':0} for p in range_periodos}

                    reset_venda()
                    estado['estoque_inicial'] = 0; estado['estoque_final'] = 0; estado['operacao_anterior'] = 0

                    if estado['codigo_barra'] in tabela_codigo_barra_estoque_inicial:
                        estado['estoque_inicial'] = tabela_codigo_barra_estoque_inicial[estado['codigo_barra']]
                        estado['estoque_final'] = estado['estoque_inicial']
                        dt_est = datetime.strptime('2015-07-01', '%Y-%m-%d').date()
                        movimentacao_codigo_barra.append({
                            'tipo':'e', 'codigo_barra': estado['codigo_barra'], 'estoque_inicial': estado['estoque_inicial'],
                            'data_estoque_inicial': dt_est, 'data_aquis_dev_estoq': dt_est, 'qnt_aquis_dev': 0, 'numero_nfe': None
                        })
                    else:
                        movimentacao_codigo_barra.append({
                            'tipo':'e', 'codigo_barra': estado['codigo_barra'], 'estoque_inicial': 0,
                            'data_aquis_dev_estoq': None, 'qnt_aquis_dev': 0, 'numero_nfe': None
                        })

                if estado['codigo_barra'] == row["codigoBarra"]:
                    # Venda
                    if row["compra_venda"] == "V":
                        mes = row["data_movimentacao"].strftime("%Y-%m")
                        if mes in tabela_codigo_barra_datas_vendas[estado['codigo_barra']]:
                            tabela_codigo_barra_datas_vendas[estado['codigo_barra']][mes]['qnt_vendas_mes'] += row["qnt_caixas"]
                            tabela_codigo_barra_datas_vendas[estado['codigo_barra']][mes]['valor_vendas_mes'] += row["valor_pago"]

                        val_unit = Decimal(str(row["valor_pago"])) / Decimal(str(row["qnt_caixas"])) if row["qnt_caixas"] else Decimal(0)
                        saldo = estado['estoque_final'] - row["qnt_caixas"]

                        if saldo < 0:
                            if estado['flag_primeira_irregularidade'] == 1:
                                estado['data_inicio_nao_comprovacao'] = row['data_movimentacao']
                                estado['flag_primeira_irregularidade'] = 0

                            qtd_sc = Decimal(str(abs(saldo)))
                            val_sc = qtd_sc * val_unit
                            estado['vendas_sem_comprovacao'] += qtd_sc
                            estado['valor_sem_comprovacao'] += val_sc

                            if mes in tabela_codigo_barra_datas_vendas[estado['codigo_barra']]:
                                tabela_codigo_barra_datas_vendas[estado['codigo_barra']][mes]['qnt_vendas_sc_mes'] += qtd_sc
                                tabela_codigo_barra_datas_vendas[estado['codigo_barra']][mes]['valor_vendas_sc_mes'] += val_sc

                        if estado['periodo_inicial'] == 0: estado['periodo_inicial'] = row["data_movimentacao"]
                        estado['periodo_final'] = row["data_movimentacao"]
                        estado['vendas_periodo'] += row["qnt_caixas"]
                        estado['valor_movimentado'] += row["valor_pago"]
                        estado['estoque_final'] -= row["qnt_caixas"]

                        if estado['estoque_final'] < 0: estado['estoque_final'] = 0
                        estado['operacao_anterior'] = "V"

                        if not has_more: incluir_venda()

                    # Compra/Devolução
                    elif row["compra_venda"] == "C":
                        is_compra = (row["tipo_operacao"] == 1)
                        if estado['operacao_anterior'] == "V":
                            incluir_venda()
                            reset_venda()

                        if estado['estoque_final'] >= 0:
                            movimentacao_codigo_barra.append({
                                'tipo': 'c' if is_compra else 'd', 'codigo_barra': estado['codigo_barra'],
                                'estoque_inicial': estado['estoque_final'],
                                'estoque_final': estado['estoque_final'] + row["qnt_caixas"] if is_compra else estado['estoque_final'] - row["qnt_caixas"],
                                'data_aquis_dev_estoq': row["data_movimentacao"], 'qnt_aquis_dev': row["qnt_caixas"], 'numero_nfe': row["numeroNFE"]
                            })

                        estado['estoque_inicial'] = estado['estoque_final'] + row["qnt_caixas"] if is_compra else estado['estoque_final'] - row["qnt_caixas"]
                        estado['estoque_final'] = estado['estoque_inicial']
                        estado['operacao_anterior'] = "C"

                    tabela_completa[estado['codigo_barra']] = movimentacao_codigo_barra
            # -- FIM LÓGICA CORE --

            # Consolidação (Sumários)
            tabelaSumario = {}
            irregularidade_geral_detectada = False # Flag para o Status Final

            for cod, moves in tabela_completa.items():
                total_compras_gtin = 0; total_vendas_gtin = 0; total_vendas_sc_gtin = 0; total_valor_vendas_gtin = Decimal(0); total_valor_vendas_sc_gtin = Decimal(0)
                for m in moves:
                    if m['tipo'] == 'c': total_compras_gtin += m['qnt_aquis_dev']
                    elif m['tipo'] == 'd': total_compras_gtin -= m['qnt_aquis_dev']
                    elif m['tipo'] == 'v':
                        total_vendas_gtin += m['vendas_periodo']; total_vendas_sc_gtin += m['vendas_sem_comprovacao']
                        total_valor_vendas_gtin += m['valor_movimentado']; total_valor_vendas_sc_gtin += m['valor_sem_comprovacao']

                        if m['vendas_sem_comprovacao'] > 0:
                            irregularidade_geral_detectada = True

                tabelaSumario[cod] = {'total_compras_gtin': total_compras_gtin, 'total_vendas_gtin': total_vendas_gtin, 'total_vendas_sc_gtin': total_vendas_sc_gtin, 'total_valor_vendas_gtin': total_valor_vendas_gtin, 'total_valor_vendas_sc_gtin': total_valor_vendas_sc_gtin}

            # Injeta Header/Sumario
            for cod, lista in tabela_completa.items():
                lista.insert(0, {'tipo': 'h', 'codigo_barra': cod, 'vendas_periodo':0, 'vendas_sem_comprovacao':0, 'qnt_aquis_dev':0, 'data_aquis_dev_estoq':None, 'numero_nfe':None})
                sm = tabelaSumario[cod]
                lista.append({'tipo': 's', 'codigo_barra': cod, 'vendas_periodo': sm['total_vendas_gtin'], 'vendas_sem_comprovacao': sm['total_vendas_sc_gtin'], 'valor_movimentado': sm['total_valor_vendas_gtin'], 'valor_sem_comprovacao': sm['total_valor_vendas_sc_gtin'], 'qnt_aquis_dev': sm['total_compras_gtin'], 'data_aquis_dev_estoq': None, 'numero_nfe': None})

            t_logic = time.time() - t0 # ATUALIZA VARIÁVEL DE PERFORMANCE


            # =====================================================================
            # GRAVAÇÃO NO BANCO (TABELAS FILHAS)
            # =====================================================================
            t0 = time.time()

            if id_proc_atual:
                for cod, periodos in tabela_codigo_barra_datas_vendas.items():
                    for per, vals in periodos.items():
                        if vals['qnt_vendas_mes'] > 0:
                            cursor.execute('''
                                            insert into [temp_CGUSC].[fp].movimentacaoMensalCodigoBarraFP 
                                            (id_processamento, codigo_barra, periodo, qnt_vendas, qnt_vendas_sem_comprovacao, [valor_vendas], [valor_sem_comprovacao]) 
                                            values (?,?,?,?,?,?,?)
                                        ''', id_proc_atual, cod, per + '-01', vals['qnt_vendas_mes'],
                                           vals['qnt_vendas_sc_mes'], vals['valor_vendas_mes'],
                                           vals['valor_vendas_sc_mes'])
                conn.commit()

            t_db_write = time.time() - t0  # ATUALIZA VARIÁVEL DE PERFORMANCE

            # =====================================================================
            # 5. BUSCA DADOS DA MATRIZ DE RISCO (NOVO BLOCO OBRIGATÓRIO)
            # =====================================================================
            dados_risco_cnpj = None
            try:
                # Busca os indicadores calculados no SQL Server (Tabela criada no passo anterior)
                cursor.execute('SELECT * FROM temp_CGUSC.fp.Matriz_Risco_Final WHERE cnpj = ?', cnpj)
                row_risco = cursor.fetchone()

                # Se encontrar, converte para dicionário para passar para o Excel
                if row_risco:
                    cols_risco = [column[0] for column in cursor.description]
                    dados_risco_cnpj = dict(zip(cols_risco, row_risco))
            except Exception as e:
                logging.error(f"Erro ao buscar matriz de risco para {cnpj}: {e}")

            # =====================================================================
            # GERAÇÃO DE RELATÓRIOS (EXCEL) - COM O 4º ARGUMENTO
            # =====================================================================
            t0 = time.time()
            d_rel = []
            for cod in sorted(tabela_completa.keys()): d_rel.extend(tabela_completa[cod])

            if id_proc_atual:
                # Grava o JSON com todo o histórico processado
                salvar_memoria_calculo(cursor, conn, id_proc_atual, cnpj, d_rel)

            t_db_write = time.time() - t0


            try:
                # AQUI MUDOU: Adicionamos ', dados_risco_cnpj' no final
                print('')
                # if gerarRelatorioMovimentacao(cnpj, d_rel, 1, dados_risco_cnpj) == "SALVO": pass
                # if gerarRelatorioMovimentacao(cnpj, d_rel, 2, dados_risco_cnpj) == "SALVO": pass
            except Exception as e:
                logging.error(f"Erro relatório {cnpj}: {e}")

            t_excel = time.time() - t0  # ATUALIZA VARIÁVEL DE PERFORMANCE

            # =====================================================================
            # FINALIZAÇÃO E ATUALIZAÇÃO DE STATUS (SUCESSO)
            # =====================================================================
            t_total = time.time() - t_start_cnpj
            total_medicamentos = len(tabela_completa)
            # CORREÇÃO: Usar o tamanho do resultado da Query Principal (Vendas + Aquisições)
            total_registros_mov = len(results)

            finalizar_processamento_sucesso(cursor, conn, id_proc_atual, cnpj,
                                            t_total, total_registros_mov, total_medicamentos,
                                            irregularidade_geral_detectada)

            # =====================================================================
            # LOG DE AUDITORIA DETALHADO (RESTAURADO)
            # =====================================================================
            logging.info(f"CNPJ {cnpj} FINALIZADO. Tempo Total: {t_total:.4f}s")
            logging.info(f"   > Query Principal: {t_query_main:.4f}s")
            logging.info(f"   > Queries Auxiliares: {t_query_aux:.4f}s")
            logging.info(f"   > Processamento Lógico: {t_logic:.4f}s")
            logging.info(f"   > Gravação Banco (Resumo): {t_db_write:.4f}s")
            logging.info(f"   > Geração Excel: {t_excel:.4f}s")

        except Exception as e:
            # =====================================================================
            # TRATAMENTO DE ERRO GLOBAL (FALHA)
            # =====================================================================
            t_total = time.time() - t_start_cnpj
            logging.critical(f"ERRO FATAL NO PROCESSAMENTO DO CNPJ {cnpj}: {e}", exc_info=True)
            if id_proc_atual:
                finalizar_processamento_erro(cursor, conn, id_proc_atual, cnpj, t_total, e)

        time.sleep(TEMPO_ESPERA_ENTRE_CNPJS)

# =============================================================================
# FIM DO SCRIPT
# =============================================================================
