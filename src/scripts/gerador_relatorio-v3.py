"""
SENTINELA - Gerador de Relatórios a partir da Memória de Cálculo
================================================================
Este script lê os dados compactados da tabela memoria_calculo_consolidadaFP
e gera relatórios Excel idênticos aos gerados pelo script original.

Uso: python gerar_relatorio_memoria.py <CNPJ> [tipo_relatorio]
     tipo_relatorio: 1 = Completo (padrão), 2 = Resumido (só irregularidades)
     
Exemplo: python gerar_relatorio_memoria.py 98669864000103 1
"""

from datetime import date, datetime
import copy
import os
import zlib
import json
from decimal import Decimal, ROUND_HALF_UP
import sys
import pyodbc
import pandas as pd
import logging

# =============================================================================
# CONFIGURAÇÃO DE LOGGING
# =============================================================================
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

# =============================================================================
# CONSTANTES GLOBAIS
# =============================================================================
DATA_INICIAL_ANALISE = '2015-07-01'
DATA_FINAL_ANALISE = datetime.strptime('2024-12-10', '%Y-%m-%d').date()
CRITERIO_ESTOQUE_INICIAL = 'Critério para estimativa do estoque inicial: Soma das duas últimas aquisições, considerando os 6 meses anteriores à primeira venda.'


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
        print("ERRO CRÍTICO: Não foi possível conectar ao banco de dados.")
        sys.exit(1)


# =============================================================================
# FUNÇÃO: CARREGAR DADOS AUXILIARES
# =============================================================================
def carregar_dados_auxiliares(cursor):
    """Carrega tabelas auxiliares necessárias para o relatório."""
    dados_farmacias = {}
    dados_medicamentos = {}
    
    try:
        cursor.execute('select cnpj, razaoSocial, municipio, uf from temp_CGUSC.[dbo].dadosFarmaciasFP')
        cols = [column[0] for column in cursor.description]
        for row in cursor.fetchall():
            dados_farmacias[row[0]] = dict(zip(cols, row))
        
        cursor.execute('select codigo_barra, principio_ativo from temp_CGUSC.[dbo].medicamentosPatologiaFP')
        cols = [column[0] for column in cursor.description]
        for row in cursor.fetchall():
            dados_medicamentos[row[0]] = dict(zip(cols, row))
            
        logging.info("Dados auxiliares carregados com sucesso.")
        return dados_farmacias, dados_medicamentos
        
    except Exception as e:
        logging.error(f"Erro ao carregar dados auxiliares: {e}")
        return {}, {}


# =============================================================================
# FUNÇÃO: DESCOMPACTAR E CARREGAR MEMÓRIA DE CÁLCULO
# =============================================================================
def carregar_memoria_calculo(cursor, cnpj):
    """
    Busca os dados compactados da tabela memoria_calculo_consolidadaFP,
    descompacta e retorna como lista de dicionários.
    """
    try:
        cursor.execute('''
            SELECT TOP 1 dados_comprimidos, id_processamento
            FROM temp_CGUSC.dbo.memoria_calculo_consolidadaFP 
            WHERE cnpj = ?
            ORDER BY id_processamento DESC
        ''', cnpj)
        
        row = cursor.fetchone()
        
        if not row or not row[0]:
            logging.warning(f"Nenhum dado encontrado para CNPJ {cnpj}")
            return None, None
        
        dados_comprimidos = row[0]
        id_processamento = row[1]
        
        # Descompacta os dados
        json_str = zlib.decompress(dados_comprimidos).decode('utf-8')
        dados = json.loads(json_str)
        
        # Converte strings de data de volta para objetos date/datetime
        for item in dados:
            for key in ['periodo_inicial', 'periodo_final', 'periodo_inicial_nao_comprovacao', 
                       'data_aquis_dev_estoq', 'data_estoque_inicial', 'data_aquisicao', 'data_devolucao']:
                if key in item and item[key] and isinstance(item[key], str):
                    try:
                        if 'T' in item[key]:
                            item[key] = datetime.fromisoformat(item[key]).date()
                        else:
                            item[key] = datetime.strptime(item[key], '%Y-%m-%d').date()
                    except:
                        pass
            
            # Converte valores numéricos para Decimal onde apropriado
            for key in ['valor_movimentado', 'valor_sem_comprovacao']:
                if key in item and item[key] is not None:
                    item[key] = Decimal(str(item[key]))
        
        tamanho_kb = len(dados_comprimidos) / 1024
        logging.info(f"Dados carregados para CNPJ {cnpj}: {len(dados)} registros ({tamanho_kb:.1f} KB comprimido)")
        
        return dados, id_processamento
        
    except Exception as e:
        logging.error(f"Erro ao carregar memória de cálculo para {cnpj}: {e}")
        return None, None


# =============================================================================
# FUNÇÃO: BUSCAR DADOS DA MATRIZ DE RISCO
# =============================================================================
def buscar_dados_risco(cursor, cnpj):
    """Busca os indicadores da Matriz de Risco."""
    try:
        cursor.execute('SELECT * FROM temp_CGUSC.dbo.Matriz_Risco_Final WHERE cnpj = ?', cnpj)
        row = cursor.fetchone()
        
        if row:
            cols = [column[0] for column in cursor.description]
            return dict(zip(cols, row))
        return None
        
    except Exception as e:
        logging.error(f"Erro ao buscar matriz de risco para {cnpj}: {e}")
        return None


# =============================================================================
# FUNÇÃO: GERAR RELATÓRIO DE MOVIMENTAÇÃO (ADAPTADA)
# =============================================================================
def gerarRelatorioMovimentacao(cnpj_analise, dados_memoria, tipo_relatorio, cursor, 
                                dados_farmacias, dados_medicamentos, dados_risco=None):
    """
    Gera o Excel processando a lista 'dados_memoria'.
    Versão adaptada para funcionar sem dependência do script original.
    """
    results = copy.deepcopy(dados_memoria)

    # =================================================================
    # 1. PROCESSAMENTO LÓGICO DAS VENDAS
    # =================================================================
    contador = 0
    for i, j in enumerate(results):
        if j['tipo'] in ('c', 'd'):
            contador += 1
        if j['tipo'] in ('s', 'h'):
            contador = 0
        if j['tipo'] == 'v':
            lista = []
            for idx in range(1, contador + 1):
                item_ant = results[i - idx]
                if item_ant['tipo'] == 'c':
                    dt = item_ant['data_aquis_dev_estoq'].strftime("%d/%m/%Y") if item_ant['data_aquis_dev_estoq'] else ""
                    qtd = int(item_ant['qnt_aquis_dev']) if item_ant.get('qnt_aquis_dev') else 0
                    lista.append(f"NF Aquisição: {item_ant['numero_nfe']} - {dt} | Qtde: {qtd}")
                elif item_ant['tipo'] == 'd':
                    dt = item_ant['data_aquis_dev_estoq'].strftime("%d/%m/%Y") if item_ant['data_aquis_dev_estoq'] else ""
                    qtd = int(item_ant['qnt_aquis_dev']) if item_ant.get('qnt_aquis_dev') else 0
                    lista.append(f"NF Transferência: {item_ant['numero_nfe']} - {dt} | Qtde: {qtd}")
                elif item_ant['tipo'] == 'e':
                    est = int(item_ant.get('estoque_inicial', 0))
                    lista.append(f"Estoque Inicial Estimado: {est} - 01/07/2015")
            if not lista and i > 0:
                for idx in range(i - 1, -1, -1):
                    if results[idx]['tipo'] == 'e':
                        est = int(results[idx].get('estoque_inicial', 0))
                        lista.append(f"Estoque Inicial Estimado: {est} - 01/07/2015")
                        break
                    elif results[idx]['tipo'] == 'h':
                        break
            results[i]['notas'] = ", ".join(lista)
            contador = 0

    lista_vendas_sem_comprovacao = []

    # Carrega Dados Auxiliares do Estoque Inicial
    try:
        cursor.execute(
            'select * from temp_CGUSC.[dbo].notas_estoque_inicialFP where cnpj_estabelecimento = ? order by codigo_barra',
            cnpj_analise)
        notas_estoque_inicialFP = {}
        lista_temp = []
        codigo_barra_registro_anterior = -1
        for row in cursor.fetchall():
            codigo_barra_atual = row[2]
            if codigo_barra_atual != codigo_barra_registro_anterior:
                notas_estoque_inicialFP[codigo_barra_registro_anterior] = copy.deepcopy(lista_temp)
                lista_temp.clear()
            dt = row[3].strftime("%d/%m/%Y") if row[3] else ""
            lista_temp.append(f'NF {row[4]} - {dt} - | Qtde: {row[1]}')
            codigo_barra_registro_anterior = codigo_barra_atual
        if codigo_barra_registro_anterior != -1:
            notas_estoque_inicialFP[codigo_barra_registro_anterior] = copy.deepcopy(lista_temp)
    except:
        notas_estoque_inicialFP = {}

    tabela_codigo_barra_estoque_inicial = {}
    try:
        cursor.execute(
            'select codigo_barra, estoque_inicial from temp_CGUSC.[dbo].estoque_inicialFP where cnpj_estabelecimento = ?',
            cnpj_analise)
        tabela_codigo_barra_estoque_inicial = {row.codigo_barra: row.estoque_inicial for row in cursor.fetchall()}
    except:
        pass

    cnpj_fmt = f'{cnpj_analise[:2]}.{cnpj_analise[2:5]}.{cnpj_analise[5:8]}/{cnpj_analise[8:12]}-{cnpj_analise[12:14]}'
    razao = dados_farmacias.get(cnpj_analise, {}).get('razaoSocial', 'DESCONHECIDO')
    mun = dados_farmacias.get(cnpj_analise, {}).get('municipio', '')
    uf = dados_farmacias.get(cnpj_analise, {}).get('uf', '')
    dt_ini_fmt = datetime.strptime(DATA_INICIAL_ANALISE, '%Y-%m-%d').strftime('%d/%m/%Y')
    dt_fim_fmt = DATA_FINAL_ANALISE.strftime('%d/%m/%Y')

    texto_cabecalho_1 = f'Estabelecimento: {cnpj_fmt} - {razao} - {mun}/{uf} | Período: {dt_ini_fmt} a {dt_fim_fmt}'
    texto_cabecalho_2 = CRITERIO_ESTOQUE_INICIAL

    lista_vendas_sem_comprovacao.append({'periodo_inicial': texto_cabecalho_1, '_tipo_linha': 'cabecalho_principal'})
    lista_vendas_sem_comprovacao.append({'periodo_inicial': texto_cabecalho_2, '_tipo_linha': 'cabecalho_principal'})

    vendas_total_sem_comprovacao_cnpj = 0
    vendas_total_cnpj = 0
    valor_total_cnpj = Decimal(0)
    valor_total_sem_comprovacao_cnpj = Decimal(0)
    numero_vendas_gtin = 0
    lista_parcial = []
    ultimo_estoque_valido = 0
    dados_para_grafico = []

    for i, j in enumerate(results):
        if j['tipo'] == 'v':
            vendas_total_cnpj += j.get('vendas_periodo', 0)
            vendas_total_sem_comprovacao_cnpj += j.get('vendas_sem_comprovacao', 0)
            valor_total_cnpj += j.get('valor_movimentado', Decimal(0))
            valor_total_sem_comprovacao_cnpj += j.get('valor_sem_comprovacao', Decimal(0))
            dados_para_grafico.append({
                'data': j['periodo_inicial'],
                'valor_total': float(j['valor_movimentado']),
                'valor_sem_comp': float(j['valor_sem_comprovacao'])
            })

        if j['tipo'] == 'h':
            numero_vendas_gtin = 0
            cod = int(j['codigo_barra'])
            principio = dados_medicamentos.get(float(cod), {}).get('principio_ativo', 'DESCONHECIDO')
            notas = ', '.join(notas_estoque_inicialFP.get(cod, []))
            est = tabela_codigo_barra_estoque_inicial.get(cod, 0)
            ultimo_estoque_valido = est
            j_copy = copy.deepcopy(j)
            j_copy['periodo_inicial'] = f'GTIN: {cod} - {principio}. Estoque Inicial Estimado: {est} unidade(s). {notas}'
            j_copy['_tipo_linha'] = 'header_medicamento'
            for k in ['vendas_periodo', 'vendas_sem_comprovacao', 'valor_movimentado', 'valor_sem_comprovacao']:
                j_copy[k] = ""
            lista_parcial.append(j_copy)
            lista_parcial.append({
                'periodo_inicial': 'Data Primeira Venda',
                'periodo_inicial_nao_comprovacao': 'Data Início Não Comprovação',
                'periodo_final': 'Data Última Venda',
                'estoque_inicial': 'Estoque Inicial',
                'estoque_final': 'Estoque Final',
                'vendas_periodo': 'Vendas',
                'vendas_sem_comprovacao': 'Vendas sem Comprov.',
                'valor_movimentado': 'Valor Vendas',
                'valor_sem_comprovacao': 'Valor sem Comprov.',
                'notas': 'Notas Fiscais',
                '_tipo_linha': 'header_colunas'
            })

        elif j['tipo'] == 'e':
            ultimo_estoque_valido = j.get('estoque_inicial', 0)

        elif j['tipo'] == 'v':
            ultimo_estoque_valido = j.get('estoque_final', 0)
            tem_irregularidade = j.get('valor_sem_comprovacao', 0) > 0
            exibir = (tipo_relatorio == 1) or (tipo_relatorio == 2 and tem_irregularidade)
            if exibir:
                numero_vendas_gtin += 1
                j_copy = copy.deepcopy(j)
                j_copy['estoque_inicial'] = int(j.get('estoque_inicial', 0))
                j_copy['estoque_final'] = int(j.get('estoque_final', 0))
                j_copy['vendas_periodo'] = int(j.get('vendas_periodo', 0))
                j_copy['vendas_sem_comprovacao'] = int(j.get('vendas_sem_comprovacao', 0))
                j_copy['valor_movimentado'] = float(
                    Decimal(str(j.get('valor_movimentado', 0))).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP))
                j_copy['valor_sem_comprovacao'] = float(
                    Decimal(str(j.get('valor_sem_comprovacao', 0))).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP))
                j_copy['periodo_inicial'] = j['periodo_inicial'].strftime("%d/%m/%Y") if j.get('periodo_inicial') else "-"
                dt_nc = j.get('periodo_inicial_nao_comprovacao')
                j_copy['periodo_inicial_nao_comprovacao'] = '-' if str(dt_nc) == '9999-01-01' else (dt_nc.strftime("%d/%m/%Y") if dt_nc else "-")
                j_copy['periodo_final'] = j['periodo_final'].strftime("%d/%m/%Y") if j.get('periodo_final') else "-"
                j_copy['_tipo_linha'] = 'venda_irregular' if tem_irregularidade else 'venda_normal'
                lista_parcial.append(j_copy)

        elif j['tipo'] in ('c', 'd'):
            ultimo_estoque_valido = j.get('estoque_final', 0)

        elif j['tipo'] == 's':
            j_copy = copy.deepcopy(j)
            estoque_visual_final = int(ultimo_estoque_valido)
            if lista_parcial:
                for item_rev in reversed(lista_parcial):
                    if 'estoque_final' in item_rev and isinstance(item_rev['estoque_final'], (int, float)):
                        estoque_visual_final = item_rev['estoque_final']
                        break
            j_copy['estoque_final'] = int(estoque_visual_final)
            j_copy['vendas_periodo'] = int(j.get('vendas_periodo', 0))
            j_copy['vendas_sem_comprovacao'] = int(j.get('vendas_sem_comprovacao', 0))
            j_copy['valor_movimentado'] = float(
                Decimal(str(j.get('valor_movimentado', 0))).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP))
            j_copy['valor_sem_comprovacao'] = float(
                Decimal(str(j.get('valor_sem_comprovacao', 0))).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP))
            j_copy['periodo_inicial'] = "Resumo Parcial"
            j_copy['_tipo_linha'] = 'resumo_parcial'
            lista_parcial.append(j_copy)
            lista_parcial.append({'_tipo_linha': 'spacer'})
            if numero_vendas_gtin > 0:
                lista_vendas_sem_comprovacao.extend(copy.deepcopy(lista_parcial))
            lista_parcial.clear()
            numero_vendas_gtin = 0

    lista_vendas_sem_comprovacao.append({
        'periodo_inicial': 'Total Geral',
        'vendas_sem_comprovacao': int(vendas_total_sem_comprovacao_cnpj),
        'vendas_periodo': int(vendas_total_cnpj),
        'valor_movimentado': float(valor_total_cnpj.quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)),
        'valor_sem_comprovacao': float(valor_total_sem_comprovacao_cnpj.quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)),
        '_tipo_linha': 'total_geral'
    })

    # Gráfico de Evolução
    df_analise = None
    try:
        if dados_para_grafico:
            df_temp = pd.DataFrame(dados_para_grafico)
            df_temp['data'] = pd.to_datetime(df_temp['data'])
            df_temp = df_temp.set_index('data')
            df_semestral = df_temp.resample('6MS').sum().reset_index()

            def format_semestre(date):
                return f'{1 if date.month <= 6 else 2}S/{date.year}'

            df_semestral['periodo_fmt'] = df_semestral['data'].apply(format_semestre)
            df_semestral['valor_com_comp'] = df_semestral['valor_total'] - df_semestral['valor_sem_comp']
            df_semestral['pct_sem_comp_valor'] = (
                df_semestral['valor_sem_comp'] / df_semestral['valor_total'].replace(0, 1)).apply(lambda x: round(x, 4))
            df_semestral['valor_sem_comp'] = df_semestral['valor_sem_comp'].round(2)
            df_semestral['valor_total'] = df_semestral['valor_total'].round(2)
            df_analise = df_semestral[['periodo_fmt', 'valor_com_comp', 'valor_sem_comp', 'pct_sem_comp_valor', 'valor_total']]
    except Exception as e:
        logging.error(f"Erro ao calcular dados do gráfico: {e}")
        df_analise = None

    if vendas_total_cnpj == 0:
        return "SEM_VENDAS"

    # =================================================================
    # INÍCIO DA ESCRITA DO EXCEL
    # =================================================================
    output = f"{cnpj_analise} ({'Completo' if tipo_relatorio == 1 else 'Resumido'}).xlsx"
    writer = pd.ExcelWriter(output, engine='xlsxwriter')

    try:
        wb = writer.book

        # ESTILOS GERAIS
        fmt_cabecalho = wb.add_format({
            'bold': True, 'font_size': 12, 'bg_color': '#1F4E78', 'font_color': 'white',
            'align': 'left', 'valign': 'vcenter', 'text_wrap': True
        })
        fmt_header_medicamento = wb.add_format({
            'bold': True, 'font_size': 11, 'bg_color': '#777777', 'font_color': 'white',
            'align': 'left', 'valign': 'vcenter', 'text_wrap': True, 'border': 1
        })
        fmt_header_colunas = wb.add_format({
            'bold': True, 'font_size': 10, 'bg_color': '#F2F2F2', 'align': 'center',
            'valign': 'vcenter', 'text_wrap': True, 'border': 1
        })
        fmt_header_colunas_left = wb.add_format({
            'bold': True, 'font_size': 10, 'bg_color': '#F2F2F2', 'align': 'left',
            'valign': 'vcenter', 'text_wrap': True, 'border': 1
        })
        fmt_venda_normal = wb.add_format({'bg_color': '#F1F7ED', 'align': 'left', 'valign': 'vcenter', 'border': 1})
        fmt_venda_irregular = wb.add_format({'bg_color': '#FCE4D6', 'align': 'left', 'valign': 'vcenter', 'border': 1})
        fmt_resumo = wb.add_format({
            'bold': True, 'bg_color': '#F2F2F2', 'font_color': 'black',
            'align': 'left', 'valign': 'vcenter', 'border': 1
        })
        fmt_resumo_int = wb.add_format({
            'bold': True, 'bg_color': '#F2F2F2', 'font_color': 'black',
            'align': 'right', 'valign': 'vcenter', 'num_format': '#,##0', 'border': 1
        })
        fmt_resumo_moeda = wb.add_format({
            'bold': True, 'bg_color': '#F2F2F2', 'font_color': 'black',
            'align': 'right', 'valign': 'vcenter', 'num_format': 'R$ #,##0.00', 'border': 1
        })
        fmt_total = wb.add_format({
            'bold': True, 'font_size': 11, 'bg_color': '#203764', 'font_color': 'white',
            'align': 'left', 'valign': 'vcenter', 'left': 2, 'right': 2, 'top': 2, 'bottom': 2
        })
        fmt_total_int = wb.add_format({
            'bold': True, 'font_size': 11, 'bg_color': '#203764', 'font_color': 'white',
            'align': 'right', 'valign': 'vcenter', 'num_format': '#,##0',
            'left': 2, 'right': 2, 'top': 2, 'bottom': 2
        })
        fmt_total_moeda = wb.add_format({
            'bold': True, 'font_size': 11, 'bg_color': '#203764', 'font_color': 'white',
            'align': 'right', 'valign': 'vcenter', 'num_format': 'R$ #,##0.00',
            'left': 2, 'right': 2, 'top': 2, 'bottom': 2
        })
        fmt_int_norm = wb.add_format({'num_format': '#,##0', 'align': 'right', 'bg_color': '#F1F7ED', 'border': 1})
        fmt_int_irreg = wb.add_format({'num_format': '#,##0', 'align': 'right', 'bg_color': '#FCE4D6', 'border': 1})
        fmt_cur_norm = wb.add_format({'num_format': 'R$ #,##0.00', 'align': 'right', 'bg_color': '#F1F7ED', 'border': 1})
        fmt_cur_irreg = wb.add_format({'num_format': 'R$ #,##0.00', 'align': 'right', 'bg_color': '#FCE4D6', 'border': 1})
        fmt_cur_alert = wb.add_format({
            'num_format': 'R$ #,##0.00', 'align': 'right', 'bg_color': '#FCE4D6',
            'font_color': '#C00000', 'bold': True, 'border': 1
        })

        # =================================================================
        # ABA 1: MOVIMENTAÇÃO
        # =================================================================
        df = pd.DataFrame.from_records(lista_vendas_sem_comprovacao)
        cols_drop = ['numero_nfe', 'qnt_aquis_dev', 'data_aquis_dev_estoq', 'tipo', 'codigo_barra',
                     'data_estoque_inicial', 'data_aquisicao', 'data_devolucao']
        for c in cols_drop:
            if c in df.columns:
                df.drop(c, axis=1, inplace=True)
        tipo_linha = df['_tipo_linha'].tolist() if '_tipo_linha' in df.columns else []
        if '_tipo_linha' in df.columns:
            df.drop('_tipo_linha', axis=1, inplace=True)
        cols_order = ['periodo_inicial', 'periodo_inicial_nao_comprovacao', 'periodo_final', 'estoque_inicial',
                      'estoque_final', 'vendas_periodo', 'vendas_sem_comprovacao', 'valor_movimentado',
                      'valor_sem_comprovacao', 'notas']
        df = df.reindex([c for c in cols_order if c in df.columns], axis=1)
        df.to_excel(writer, sheet_name='Movimentacao', index=False, header=False)
        ws = writer.sheets['Movimentacao']

        col_map = {name: idx for idx, name in enumerate(df.columns)}
        last_col = len(df.columns) - 1

        for r, tipo in enumerate(tipo_linha):
            txt = df.iloc[r]['periodo_inicial'] if 'periodo_inicial' in df.columns else ''
            if tipo == 'cabecalho_principal':
                ws.merge_range(r, 0, r, last_col, txt, fmt_cabecalho)
                ws.set_row(r, 25)
            elif tipo == 'header_medicamento':
                ws.merge_range(r, 0, r, last_col, txt, fmt_header_medicamento)
                ws.set_row(r, 30)
            elif tipo == 'header_colunas':
                ws.set_row(r, 35, fmt_header_colunas)
                if 'notas' in col_map:
                    texto_nota = df.iloc[r]['notas']
                    ws.write(r, col_map['notas'], texto_nota, fmt_header_colunas_left)
            elif tipo == 'spacer':
                ws.set_row(r, 15)
            elif tipo == 'venda_normal':
                ws.set_row(r, 20, fmt_venda_normal)
                if 'estoque_inicial' in col_map:
                    ws.write(r, col_map['estoque_inicial'], df.iloc[r]['estoque_inicial'], fmt_int_norm)
                if 'estoque_final' in col_map:
                    ws.write(r, col_map['estoque_final'], df.iloc[r]['estoque_final'], fmt_int_norm)
                if 'vendas_periodo' in col_map:
                    ws.write(r, col_map['vendas_periodo'], df.iloc[r]['vendas_periodo'], fmt_int_norm)
                if 'vendas_sem_comprovacao' in col_map:
                    ws.write(r, col_map['vendas_sem_comprovacao'], df.iloc[r]['vendas_sem_comprovacao'], fmt_int_norm)
                if 'valor_movimentado' in col_map:
                    ws.write(r, col_map['valor_movimentado'], df.iloc[r]['valor_movimentado'], fmt_cur_norm)
                if 'valor_sem_comprovacao' in col_map:
                    ws.write(r, col_map['valor_sem_comprovacao'], df.iloc[r]['valor_sem_comprovacao'], fmt_cur_norm)
            elif tipo == 'venda_irregular':
                ws.set_row(r, 20, fmt_venda_irregular)
                if 'estoque_inicial' in col_map:
                    ws.write(r, col_map['estoque_inicial'], df.iloc[r]['estoque_inicial'], fmt_int_irreg)
                if 'estoque_final' in col_map:
                    ws.write(r, col_map['estoque_final'], df.iloc[r]['estoque_final'], fmt_int_irreg)
                if 'vendas_periodo' in col_map:
                    ws.write(r, col_map['vendas_periodo'], df.iloc[r]['vendas_periodo'], fmt_int_irreg)
                if 'vendas_sem_comprovacao' in col_map:
                    ws.write(r, col_map['vendas_sem_comprovacao'], df.iloc[r]['vendas_sem_comprovacao'], fmt_int_irreg)
                if 'valor_movimentado' in col_map:
                    ws.write(r, col_map['valor_movimentado'], df.iloc[r]['valor_movimentado'], fmt_cur_irreg)
                if 'valor_sem_comprovacao' in col_map:
                    ws.write(r, col_map['valor_sem_comprovacao'], df.iloc[r]['valor_sem_comprovacao'], fmt_cur_alert)
            elif tipo == 'resumo_parcial':
                ws.set_row(r, 25, fmt_resumo)
                if 'estoque_final' in col_map:
                    ws.write(r, col_map['estoque_final'], df.iloc[r]['estoque_final'], fmt_resumo_int)
                if 'vendas_periodo' in col_map:
                    ws.write(r, col_map['vendas_periodo'], df.iloc[r]['vendas_periodo'], fmt_resumo_int)
                if 'vendas_sem_comprovacao' in col_map:
                    ws.write(r, col_map['vendas_sem_comprovacao'], df.iloc[r]['vendas_sem_comprovacao'], fmt_resumo_int)
                if 'valor_movimentado' in col_map:
                    ws.write(r, col_map['valor_movimentado'], df.iloc[r]['valor_movimentado'], fmt_resumo_moeda)
                if 'valor_sem_comprovacao' in col_map:
                    ws.write(r, col_map['valor_sem_comprovacao'], df.iloc[r]['valor_sem_comprovacao'], fmt_resumo_moeda)
            elif tipo == 'total_geral':
                ws.set_row(r, 30, fmt_total)
                if 'vendas_periodo' in col_map:
                    ws.write(r, col_map['vendas_periodo'], df.iloc[r]['vendas_periodo'], fmt_total_int)
                if 'vendas_sem_comprovacao' in col_map:
                    ws.write(r, col_map['vendas_sem_comprovacao'], df.iloc[r]['vendas_sem_comprovacao'], fmt_total_int)
                if 'valor_movimentado' in col_map:
                    ws.write(r, col_map['valor_movimentado'], df.iloc[r]['valor_movimentado'], fmt_total_moeda)
                if 'valor_sem_comprovacao' in col_map:
                    ws.write(r, col_map['valor_sem_comprovacao'], df.iloc[r]['valor_sem_comprovacao'], fmt_total_moeda)

        # Ajuste de largura das colunas
        ws.set_column(0, 0, 25)
        if 'periodo_inicial_nao_comprovacao' in col_map:
            ws.set_column(col_map['periodo_inicial_nao_comprovacao'], col_map['periodo_inicial_nao_comprovacao'], 25)
        if 'periodo_final' in col_map:
            ws.set_column(col_map['periodo_final'], col_map['periodo_final'], 20)
        if 'estoque_inicial' in col_map:
            ws.set_column(col_map['estoque_inicial'], col_map['estoque_inicial'], 15)
        if 'estoque_final' in col_map:
            ws.set_column(col_map['estoque_final'], col_map['estoque_final'], 15)
        if 'vendas_periodo' in col_map:
            ws.set_column(col_map['vendas_periodo'], col_map['vendas_periodo'], 12)
        if 'vendas_sem_comprovacao' in col_map:
            ws.set_column(col_map['vendas_sem_comprovacao'], col_map['vendas_sem_comprovacao'], 18)
        if 'valor_movimentado' in col_map:
            ws.set_column(col_map['valor_movimentado'], col_map['valor_movimentado'], 18)
        if 'valor_sem_comprovacao' in col_map:
            ws.set_column(col_map['valor_sem_comprovacao'], col_map['valor_sem_comprovacao'], 20)
        if 'notas' in col_map:
            ws.set_column(col_map['notas'], col_map['notas'], 800)
        ws.freeze_panes(1, 0)

        # =================================================================
        # ABA 2: EVOLUÇÃO FINANCEIRA
        # =================================================================
        if df_analise is not None and not df_analise.empty:
            ws_analise = wb.add_worksheet('Evolucao_Financeira')
            ws_analise.hide_gridlines(2)

            fmt_linha_infinita = wb.add_format({'bg_color': '#1F4E78'})
            fmt_header = wb.add_format({
                'bold': True, 'font_size': 10, 'bg_color': '#E4E4E4', 'font_color': '#2E2E2E',
                'align': 'center', 'valign': 'vcenter', 'border': 1
            })
            fmt_moeda = wb.add_format({'num_format': 'R$ #,##0.00', 'align': 'right', 'border': 1})
            fmt_pct = wb.add_format({'num_format': '0.00%', 'align': 'center', 'border': 1})
            fmt_semestre = wb.add_format({'align': 'center', 'border': 1})
            fmt_cabecalho_dash = wb.add_format({
                'bold': True, 'font_size': 12, 'bg_color': '#1F4E78', 'font_color': 'white',
                'align': 'left', 'valign': 'vcenter', 'text_wrap': True, 'border': 1
            })

            ws_analise.set_row(0, 25, fmt_linha_infinita)
            ws_analise.merge_range('A1:AG1', texto_cabecalho_1, fmt_cabecalho_dash)

            start_row = 2
            start_col = 1
            headers = ['Semestre', 'Total', 'Vendas Regulares', 'Vendas Irreg.', '% Irregular']
            for c, h in enumerate(headers):
                ws_analise.write(start_row, start_col + c, h, fmt_header)

            for r, row_data in enumerate(df_analise.values):
                current_row = start_row + 1 + r
                ws_analise.write(current_row, start_col + 0, row_data[0], fmt_semestre)
                ws_analise.write(current_row, start_col + 1, row_data[4], fmt_moeda)
                ws_analise.write(current_row, start_col + 2, row_data[1], fmt_moeda)
                ws_analise.write(current_row, start_col + 3, row_data[2], fmt_moeda)
                ws_analise.write(current_row, start_col + 4, row_data[3], fmt_pct)

            row_total = start_row + 1 + len(df_analise)
            sum_regular = df_analise['valor_com_comp'].sum()
            sum_irregular = df_analise['valor_sem_comp'].sum()
            sum_total = df_analise['valor_total'].sum()
            pct_total = (sum_irregular / sum_total) if sum_total > 0 else 0

            fmt_total_label = wb.add_format({
                'bold': True, 'bg_color': '#E4E4E4', 'font_color': '#2E2E2E',
                'align': 'center', 'border': 1
            })
            fmt_total_moeda_ev = wb.add_format({
                'bold': True, 'bg_color': '#E4E4E4', 'font_color': '#2E2E2E',
                'num_format': 'R$ #,##0.00', 'align': 'right', 'border': 1
            })
            fmt_total_moeda_red = wb.add_format({
                'bold': True, 'bg_color': '#E4E4E4', 'num_format': 'R$ #,##0.00',
                'align': 'right', 'font_color': '#2E2E2E', 'border': 1
            })
            fmt_total_pct = wb.add_format({
                'bold': True, 'bg_color': '#E4E4E4', 'font_color': '#2E2E2E',
                'num_format': '0.00%', 'align': 'center', 'border': 1
            })

            ws_analise.write(row_total, start_col, "TOTAL", fmt_total_label)
            ws_analise.write(row_total, start_col + 1, sum_total, fmt_total_moeda_ev)
            ws_analise.write(row_total, start_col + 2, sum_regular, fmt_total_moeda_ev)
            ws_analise.write(row_total, start_col + 3, sum_irregular, fmt_total_moeda_red)
            ws_analise.write(row_total, start_col + 4, pct_total, fmt_total_pct)

            ws_analise.set_column('A:A', 4)
            ws_analise.set_column('B:B', 10)
            ws_analise.set_column('C:C', 17)
            ws_analise.set_column('D:D', 17)
            ws_analise.set_column('E:E', 15)
            ws_analise.set_column('F:F', 10)
            ws_analise.set_column('G:G', 3)
            ws_analise.set_column('H:H', 25)
            ws_analise.set_column('I:I', 2)
            ws_analise.set_column('J:J', 25)
            ws_analise.set_column('K:K', 2)
            ws_analise.set_column('L:L', 25)

            max_row = row_total
            chart1 = wb.add_chart({'type': 'column', 'subtype': 'stacked'})
            chart1.add_series({
                'name': f'=Evolucao_Financeira!$D${start_row + 1}',
                'categories': f'=Evolucao_Financeira!$B${start_row + 2}:$B${max_row}',
                'values': f'=Evolucao_Financeira!$D${start_row + 2}:$D${max_row}',
                'fill': {'color': '#F1F7ED'}, 'border': {'color': '#D9D9D9'}, 'gap': 30
            })
            chart1.add_series({
                'name': f'=Evolucao_Financeira!$E${start_row + 1}',
                'categories': f'=Evolucao_Financeira!$B${start_row + 2}:$B${max_row}',
                'values': f'=Evolucao_Financeira!$E${start_row + 2}:$E${max_row}',
                'fill': {'color': '#C00000'}, 'border': {'color': '#BFBFBF'}
            })
            chart1.set_title({'name': 'Volume Financeiro Auditado (R$)'})
            chart1.set_size({'width': 1000, 'height': 380})
            chart1.set_y_axis({'name': 'Volume (R$)', 'major_gridlines': {'visible': True, 'line': {'color': '#E0E0E0'}}})
            chart1.set_legend({'position': 'bottom'})
            chart1.set_chartarea({'border': {'none': True}})
            ws_analise.insert_chart('H6', chart1, {'x_offset': 10, 'y_offset': 10})

            chart2 = wb.add_chart({'type': 'area'})
            chart2.add_series({
                'name': f'=Evolucao_Financeira!$F${start_row + 1}',
                'categories': f'=Evolucao_Financeira!$B${start_row + 2}:$B${max_row}',
                'values': f'=Evolucao_Financeira!$F${start_row + 2}:$F${max_row}',
                'fill': {'color': '#B4C6E7'}, 'border': {'color': '#203764', 'width': 2},
                'marker': {'type': 'circle', 'size': 5, 'fill': {'color': '#203764'}}
            })
            chart2.set_title({'name': 'Evolução do Percentual de Irregularidade (%)'})
            chart2.set_size({'width': 1000, 'height': 380})
            chart2.set_y_axis({
                'name': '% Irregular', 'min': 0, 'max': 1.0,
                'major_gridlines': {'visible': True, 'line': {'color': '#E0E0E0'}}
            })
            chart2.set_legend({'none': True})
            chart2.set_chartarea({'border': {'none': True}})
            ws_analise.insert_chart('H27', chart2, {'x_offset': 10, 'y_offset': 10})

            # Cards de resumo
            fmt_card_t = wb.add_format({'font_size': 9, 'font_color': '#777777', 'align': 'center'})
            ws_analise.write('H3', 'TOTAL IRREGULAR', fmt_card_t)
            ws_analise.write('H4', sum_irregular, wb.add_format({
                'font_size': 14, 'font_color': '#C00000', 'bold': True,
                'align': 'center', 'num_format': 'R$ #,##0.00'
            }))
            ws_analise.write('J3', '% MÉDIA IRREGULARIDADE', fmt_card_t)
            ws_analise.write('J4', pct_total, wb.add_format({
                'font_size': 14, 'font_color': '#000000', 'bold': True,
                'align': 'center', 'num_format': '0.00%'
            }))
            ws_analise.write('L3', 'TOTAL MOVIMENTADO', fmt_card_t)
            ws_analise.write('L4', sum_total, wb.add_format({
                'font_size': 14, 'font_color': '#203764', 'bold': True,
                'align': 'center', 'num_format': 'R$ #,##0.00'
            }))

        # =================================================================
        # ABA 3: INDICADORES DE RISCO
        # =================================================================
        if dados_risco:
            ws_ind = wb.add_worksheet('Indicadores')
            ws_ind.hide_gridlines(2)

            COR_AZUL_ESCURO = '#1F4E78'
            COR_CINZA_CLARO = '#F2F2F2'
            COR_VERMELHO = '#C00000'
            COR_AMARELO = '#FFC000'
            COR_VERDE = '#548235'

            fmt_titulo = wb.add_format({
                'bold': True, 'font_size': 18, 'font_color': COR_AZUL_ESCURO,
                'align': 'left', 'valign': 'vcenter'
            })
            fmt_subtitulo = wb.add_format({
                'font_size': 10, 'font_color': '#555555', 'align': 'left', 'valign': 'vcenter'
            })
            fmt_score_label = wb.add_format({
                'bold': True, 'font_size': 12, 'align': 'center', 'valign': 'top', 'font_color': '#555555'
            })
            fmt_header_grupo = wb.add_format({
                'bold': True, 'font_size': 11, 'bg_color': COR_AZUL_ESCURO, 'font_color': 'white',
                'align': 'left', 'valign': 'vcenter', 'indent': 1, 'border': 1
            })
            fmt_header_col = wb.add_format({
                'bold': True, 'font_size': 9, 'bg_color': COR_CINZA_CLARO, 'font_color': 'black',
                'align': 'center', 'valign': 'vcenter', 'border': 1
            })
            fmt_label = wb.add_format({
                'font_size': 10, 'align': 'left', 'valign': 'vcenter',
                'indent': 1, 'border': 1, 'bg_color': 'white'
            })

            fmt_pct_ind = wb.add_format({'num_format': '0.00%', 'align': 'center', 'valign': 'vcenter', 'border': 1})
            fmt_dec = wb.add_format({'num_format': '0.00', 'align': 'center', 'valign': 'vcenter', 'border': 1})
            fmt_val = wb.add_format({'num_format': 'R$ #,##0.00', 'align': 'center', 'valign': 'vcenter', 'border': 1})

            fmt_risco_verde = wb.add_format({
                'bg_color': '#E2EFDA', 'font_color': '#006100', 'bold': True,
                'align': 'center', 'valign': 'vcenter', 'border': 1, 'num_format': '0.0x'
            })
            fmt_risco_amarelo = wb.add_format({
                'bg_color': '#FFF2CC', 'font_color': '#9C5700', 'bold': True,
                'align': 'center', 'valign': 'vcenter', 'border': 1, 'num_format': '0.0x'
            })
            fmt_risco_vermelho = wb.add_format({
                'bg_color': '#FFC7CE', 'font_color': '#9C0006', 'bold': True,
                'align': 'center', 'valign': 'vcenter', 'border': 1, 'num_format': '0.0x'
            })

            # Explicações Metodológicas (Profundas)
            explicacoes = {
                "Vendas p/ Falecidos": "METODOLOGIA: Confronto direto entre a data da dispensação do medicamento e a data oficial de óbito registrada nas bases governamentais (SIM/SIRC/SISOBI). A precisão é absoluta.\n\nRISCO: Este é um indicador de 'Tolerância Zero'. Um Risco Relativo (RR) acima de 1.0 é inadmissível, indicando falha grave de validação na ponta ou uso doloso e reiterado de base de dados de terceiros para simular vendas.",

                "Inconsistência Clínica": "METODOLOGIA: Análise farmacológica que cruza a indicação terapêutica do medicamento dispensado com o perfil demográfico (Idade e Sexo) do paciente no cadastro do CPF. Exemplos: Osteoporose em homens jovens, Parkinson em crianças.\n\nRISCO: Um RR elevado sugere a utilização massiva de CPFs aleatórios apenas para preencher requisitos do sistema, sem a presença real do paciente ou prescrição válida.",

                "Dispensação em Teto Máximo": "METODOLOGIA: Percentual de dispensações onde a quantidade vendida atinge exatamente o limite máximo mensal permitido pela Portaria do Ministério da Saúde. Em um cenário orgânico, as vendas variam conforme a necessidade.\n\nRISCO: Um RR > 5.0 indica comportamento robótico, onde o sistema busca extrair o valor financeiro máximo possível de cada CPF, ignorando a posologia real do tratamento.",

                "Concentração de Dispensação Simultânea": "METODOLOGIA: Percentual de autorizações (cupons fiscais) que contêm 4 ou mais medicamentos distintos dispensados no mesmo ato.\n\nRISCO: Indica a formação artificial de 'cestas' de medicamentos para aumentar o ticket médio por transação, maximizando o lucro sobre cada CPF capturado indevidamente.",

                "Média Itens/Autorização": "METODOLOGIA: Cálculo simples da quantidade média de itens dispensados por cupom fiscal (Total de Caixas / Total de Autorizações).\n\nRISCO: Médias muito superiores à do estado indicam prática sistêmica de 'empurroterapia' ou otimização de fraude para escoar estoque.",

                "Ticket Médio": "METODOLOGIA: Valor monetário médio de cada autorização de venda.\n\nRISCO: Valores anormais (RR > 3.0) indicam que a farmácia foca exclusivamente em produtos de alto custo (ex: fraldas geriátricas, medicamentos para asma), desprezando o mix natural de uma farmácia comunitária.",

                "Receita por Paciente": "METODOLOGIA: Faturamento total da farmácia dividido pelo número de CPFs distintos atendidos no período.\n\nRISCO: Um RR alto aponta para 'fidelidade artificial' ou 'esgotamento de cota', onde a farmácia extrai o limite financeiro máximo de uma base restrita de CPFs, em vez de atender uma comunidade ampla.",

                "Densidade de Venda Municipal": "METODOLOGIA: Faturamento total da farmácia dividido pela população total do município (estimativa IBGE). Cria um valor 'per capita' de venda.\n\nRISCO: Valores per capita irreais (ex: R$ 500,00 por habitante da cidade) indicam inequivocamente que a farmácia está importando dados de beneficiários de outros municípios ou estados para justificar o volume de vendas.",

                "Vendas Rápidas (<60s)": "METODOLOGIA: Percentual de vendas consecutivas realizadas em intervalo de tempo inferior a 60 segundos entre uma autorização e outra.\n\nRISCO: Marcador definitivo de uso de robôs (scripts de automação) para inserção em massa de dados. É humanamente impossível realizar o atendimento, conferência e digitação nesse tempo.",

                "Horário Atípico (Madrugada)": "METODOLOGIA: Volume percentual de vendas processadas entre 00h00 e 06h00.\n\nRISCO: Operação concentrada em horários de baixa fiscalização e baixo fluxo natural de clientes, característica comum em fraudes massivas automatizadas.",

                "Dispersão Geográfica Interestadual": "METODOLOGIA: Percentual de vendas realizadas para pacientes cuja Unidade da Federação (UF) de residência difere da UF da farmácia.\n\nRISCO: Um RR alto sugere a compra ou vazamento de listas de dados de beneficiários de outros estados ('Turismo de Medicamento Virtual')."
            }

            ws_ind.write('B2', "MATRIZ DE RISCO & FRAUDE", fmt_titulo)
            ws_ind.write('B3', f"{dados_risco.get('razaoSocial', '')} | CNPJ: {cnpj_analise}", fmt_subtitulo)
            ws_ind.write('B4', f"{dados_risco.get('municipio', '')} - {dados_risco.get('uf', '')}", fmt_subtitulo)

            # CONCEITO DE RISCO RELATIVO (TEXTO EXPLICATIVO NO TOPO)
            texto_rr = (
                "NOTA METODOLÓGICA: O Risco Relativo (RR) é um indexador estatístico que mensura a intensidade do desvio de comportamento. "
                "Ele elimina distorções regionais comparando a farmácia com seus pares. "
                "INTERPRETAÇÃO: RR < 1.0 (Sub-incidência/Normal); RR ≈ 1.0 (Padrão de Mercado); "
                "RR 2.0 a 5.0 (Desvio Moderado/Atenção); RR > 5.0 (Anomalia Grave/Indício de Manipulação Sistêmica)."
            )
            ws_ind.merge_range('B5:H7', texto_rr, wb.add_format({
                'font_size': 9, 'font_color': '#555555', 'italic': True, 'text_wrap': True,
                'valign': 'top', 'border': 1, 'bg_color': '#FAFAFA'
            }))

            # Score Geral
            score = float(dados_risco.get('SCORE_GERAL_RISCO', 0))
            cor_score = COR_VERDE
            txt_score = "BAIXO RISCO"
            if score >= 2:
                cor_score = COR_AMARELO
                txt_score = "RISCO MÉDIO"
            if score >= 5:
                cor_score = COR_VERMELHO
                txt_score = "ALTO RISCO"

            fmt_score_num = wb.add_format({
                'bold': True, 'font_size': 48, 'align': 'center', 'valign': 'vcenter',
                'font_color': cor_score, 'border': 0
            })
            fmt_score_txt = wb.add_format({
                'bold': True, 'font_size': 14, 'align': 'center', 'valign': 'top',
                'font_color': cor_score, 'border': 0
            })
            ws_ind.merge_range('I2:K4', score, fmt_score_num)
            ws_ind.merge_range('I5:K5', txt_score, fmt_score_txt)
            ws_ind.write('I6', "SCORE GERAL (0-10+)", fmt_score_label)

            # Grupos de Indicadores
            grupos = [
                ("1. ELEGIBILIDADE & CLÍNICA", [
                    ("Vendas p/ Falecidos", "pct_falecidos", "avg_falecidos_uf", "avg_falecidos_br",
                     "risco_falecidos_uf", "risco_falecidos_br", "pct"),
                    ("Inconsistência Clínica", "pct_clinico", "avg_clinico_uf", "avg_clinico_br",
                     "risco_clinico_uf", "risco_clinico_br", "pct")
                ]),
                ("2. PADRÕES DE QUANTIDADE", [
                    ("Dispensação em Teto Máximo", "pct_teto", "avg_teto_uf", "avg_teto_br",
                     "risco_teto_uf", "risco_teto_br", "pct"),
                    ("Concentração de Dispensação Simultânea", "pct_polimedicamento", "avg_polimedicamento_uf",
                     "avg_polimedicamento_br", "risco_polimedicamento_uf", "risco_polimedicamento_br", "pct"),
                    ("Média Itens/Autorização", "val_media_itens", "avg_media_itens_uf", "avg_media_itens_br",
                     "risco_media_itens_uf", "risco_media_itens_br", "dec")
                ]),
                ("3. PADRÕES FINANCEIROS", [
                    ("Ticket Médio", "val_ticket_medio", "avg_ticket_uf", "avg_ticket_br",
                     "risco_ticket_uf", "risco_ticket_br", "val"),
                    ("Receita por Paciente", "val_receita_paciente", "avg_receita_paciente_uf",
                     "avg_receita_paciente_br", "risco_receita_paciente_uf", "risco_receita_paciente_br", "val"),
                    ("Densidade de Venda Municipal", "val_per_capita", "avg_per_capita_uf", "avg_per_capita_br",
                     "risco_per_capita_uf", "risco_per_capita_br", "val")
                ]),
                ("4. AUTOMAÇÃO & GEOGRAFIA", [
                    ("Vendas Rápidas (<60s)", "pct_vendas_rapidas", "avg_vendas_rapidas_uf", "avg_vendas_rapidas_br",
                     "risco_vendas_rapidas_uf", "risco_vendas_rapidas_br", "pct"),
                    ("Horário Atípico (Madrugada)", "pct_madrugada", "avg_madrugada_uf", "avg_madrugada_br",
                     "risco_madrugada_uf", "risco_madrugada_br", "pct"),
                    ("Dispersão Geográfica Interestadual", "pct_geografico", "avg_geografico_uf", "avg_geografico_br",
                     "risco_geografico_uf", "risco_geografico_br", "pct")
                ])
            ]

            row = 9
            for titulo_grupo, indicadores in grupos:
                ws_ind.merge_range(row, 1, row, 7, titulo_grupo, fmt_header_grupo)
                row += 1
                ws_ind.write(row, 1, "INDICADOR", fmt_header_col)
                ws_ind.write(row, 2, "FARMÁCIA", fmt_header_col)
                ws_ind.write(row, 3, "MÉDIA UF", fmt_header_col)
                ws_ind.write(row, 4, "MÉDIA BR", fmt_header_col)
                ws_ind.write(row, 5, "RISCO (x) UF", fmt_header_col)
                ws_ind.write(row, 6, "RISCO (x) BR", fmt_header_col)
                ws_ind.write(row, 7, "STATUS", fmt_header_col)
                row += 1

                for nome, col_val, col_med_uf, col_med_br, col_r_uf, col_r_br, tipo_fmt in indicadores:
                    valor = float(dados_risco.get(col_val, 0) or 0)
                    med_uf = float(dados_risco.get(col_med_uf, 0) or 0)
                    med_br = float(dados_risco.get(col_med_br, 0) or 0)
                    r_uf = float(dados_risco.get(col_r_uf, 0) or 0)
                    r_br = float(dados_risco.get(col_r_br, 0) or 0)

                    if tipo_fmt == 'pct':
                        valor /= 100.0
                        med_uf /= 100.0
                        med_br /= 100.0

                    fmt_usado = fmt_pct_ind if tipo_fmt == 'pct' else fmt_val if tipo_fmt == 'val' else fmt_dec

                    risco_base = r_uf
                    fmt_risco_usado = fmt_risco_verde
                    texto_status = "NORMAL"
                    if risco_base >= 2:
                        fmt_risco_usado = fmt_risco_amarelo
                        texto_status = "ATENÇÃO"
                    if risco_base >= 5:
                        fmt_risco_usado = fmt_risco_vermelho
                        texto_status = "CRÍTICO"

                    # Adiciona ícone se houver explicação
                    nome_display = f"{nome} ℹ️" if nome in explicacoes else nome

                    ws_ind.write(row, 1, nome_display, fmt_label)
                    ws_ind.write(row, 2, valor, fmt_usado)
                    ws_ind.write(row, 3, med_uf, fmt_usado)
                    ws_ind.write(row, 4, med_br, fmt_usado)
                    ws_ind.write(row, 5, r_uf, fmt_risco_usado)
                    ws_ind.write(row, 6, r_br, fmt_risco_usado)
                    ws_ind.write(row, 7, texto_status, fmt_header_col)

                    # Comentário explicativo
                    if nome in explicacoes:
                        ws_ind.write_comment(row, 1, explicacoes[nome],
                                             {'width': 400, 'height': 120, 'font_name': 'Tahoma', 'font_size': 9})
                    row += 1
                row += 1

            ws_ind.set_column('A:A', 2)
            ws_ind.set_column('B:B', 38)
            ws_ind.set_column('C:E', 15)
            ws_ind.set_column('F:G', 15)
            ws_ind.set_column('H:H', 12)

    except Exception as e:
        print(f"\n❌ ERRO AO SALVAR EXCEL {output}: {e}")
        logging.error(f"Erro ao gerar Excel para {cnpj_analise}: {e}")
        import traceback
        traceback.print_exc()

    finally:
        try:
            writer.close()
        except:
            pass

    return "SALVO"


# =============================================================================
# FUNÇÃO PRINCIPAL
# =============================================================================
def main():
    if len(sys.argv) < 2:
        print("=" * 60)
        print("SENTINELA - Gerador de Relatórios a partir da Memória")
        print("=" * 60)
        print("\nUso: python gerar_relatorio_memoria.py <CNPJ> [tipo_relatorio]")
        print("\nParâmetros:")
        print("  CNPJ           - CNPJ da farmácia (apenas números)")
        print("  tipo_relatorio - 1 = Completo (padrão), 2 = Resumido")
        print("\nExemplo:")
        print("  python gerar_relatorio_memoria.py 98669864000103 1")
        print("=" * 60)
        sys.exit(1)

    cnpj = sys.argv[1].replace('.', '').replace('/', '').replace('-', '')
    tipo_relatorio = int(sys.argv[2]) if len(sys.argv) > 2 else 1

    print("=" * 60)
    print("SENTINELA - Gerador de Relatórios a partir da Memória")
    print("=" * 60)
    print(f"\nCNPJ: {cnpj}")
    print(f"Tipo: {'Completo' if tipo_relatorio == 1 else 'Resumido'}")
    print("-" * 60)

    # Conectar ao banco
    conn, cursor = conectar_bd()

    try:
        # Carregar dados auxiliares
        print("\n📊 Carregando dados auxiliares...")
        dados_farmacias, dados_medicamentos = carregar_dados_auxiliares(cursor)

        # Carregar memória de cálculo
        print(f"\n🔍 Buscando memória de cálculo para CNPJ {cnpj}...")
        dados_memoria, id_proc = carregar_memoria_calculo(cursor, cnpj)

        if not dados_memoria:
            print(f"\n❌ ERRO: Não foram encontrados dados para o CNPJ {cnpj}")
            print("   Verifique se o CNPJ foi processado pelo script original.")
            sys.exit(1)

        print(f"   ✅ Encontrados {len(dados_memoria)} registros (ID Processamento: {id_proc})")

        # Buscar dados de risco
        print("\n📈 Buscando indicadores de risco...")
        dados_risco = buscar_dados_risco(cursor, cnpj)
        if dados_risco:
            print(f"   ✅ Score de risco: {dados_risco.get('SCORE_GERAL_RISCO', 'N/A')}")
        else:
            print("   ⚠️ Dados de risco não encontrados")

        # Gerar relatório
        print("\n📝 Gerando relatório Excel...")
        resultado = gerarRelatorioMovimentacao(
            cnpj, dados_memoria, tipo_relatorio, cursor,
            dados_farmacias, dados_medicamentos, dados_risco
        )

        if resultado == "SEM_VENDAS":
            print("\n⚠️ CNPJ sem vendas no período analisado.")
        else:
            nome_arquivo = f"{cnpj} ({'Completo' if tipo_relatorio == 1 else 'Resumido'}).xlsx"
            print(f"\n✅ Relatório gerado com sucesso!")
            print(f"   📁 Arquivo: {nome_arquivo}")

    except Exception as e:
        logging.error(f"Erro no processamento: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

    finally:
        cursor.close()
        conn.close()
        print("\n" + "=" * 60)


if __name__ == "__main__":
    main()
