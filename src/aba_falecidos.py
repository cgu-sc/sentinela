"""
aba_falecidos.py
================
Módulo responsável por buscar e renderizar a aba 'Falecidos' no
relatório Excel do Sentinela.

Funções exportadas:
    buscar_dados_falecidos(cursor, cnpj)  -> list[dict]
    gerar_aba_falecidos(wb, cnpj, dados, dados_farmacias, valor_total_auditado)
"""

import logging
from collections import defaultdict


def buscar_dados_falecidos(cursor, cnpj):
    """Busca as transações realizadas após a data de óbito do paciente."""
    try:
        cursor.execute("""
            SELECT
                main.cpf, main.nome_falecido, main.municipio_falecido, main.uf_falecido,
                main.dt_nascimento, main.dt_obito, main.fonte_obito,
                main.num_autorizacao, main.data_autorizacao,
                main.qtd_itens_na_autorizacao, main.valor_total_autorizacao, main.dias_apos_obito,
                (
                    SELECT STRING_AGG(CONCAT(o.cnpj, ' | ', df.municipio, '/', df.uf), '; ')
                    FROM (SELECT DISTINCT cpf, cnpj FROM temp_CGUSC.fp.falecidos_por_farmacia) o
                    JOIN temp_CGUSC.fp.dados_farmacia df ON o.cnpj = df.cnpj
                    WHERE o.cpf = main.cpf AND o.cnpj <> ?
                ) as outros_estabelecimentos
            FROM temp_CGUSC.fp.falecidos_por_farmacia main
            WHERE main.cnpj = ?
            ORDER BY main.cpf, main.data_autorizacao
        """, (cnpj, cnpj))
        cols = [c[0] for c in cursor.description]
        return [dict(zip(cols, row)) for row in cursor.fetchall()]
    except Exception as e:
        logging.error(f"Erro ao buscar dados de falecidos para {cnpj}: {e}")
        return []


def gerar_aba_falecidos(wb, cnpj_analise, dados_falecidos, dados_farmacias, valor_total_auditado=0):
    """
    Gera a aba 'Falecidos' no workbook Excel.

    Exibe 7 cards gerenciais no topo e tabela detalhada agrupada por CPF.
    Só deve ser chamada quando len(dados_falecidos) > 0.

    Args:
        wb: Workbook do xlsxwriter
        cnpj_analise: CNPJ da farmácia (string, apenas dígitos)
        dados_falecidos: Lista de dicts retornada por buscar_dados_falecidos()
        dados_farmacias: Dict {cnpj: {razaoSocial, municipio, uf}} carregado em memória
        valor_total_auditado: Valor total de vendas auditadas da farmácia (para % faturamento)
    """
    if not dados_falecidos:
        logging.warning(f"Sem dados de falecidos para {cnpj_analise}. Aba não será gerada.")
        return

    ws = wb.add_worksheet('Falecidos')
    ws.hide_gridlines(2)

    # ── Paleta de cores ──────────────────────────────────────────────────────
    COR_AZUL_ESCURO  = '#1F4E78'
    COR_VERMELHO_ESC = '#B71C1C'
    COR_VERMELHO_MED = '#E53935'
    COR_VERMELHO_CLR = '#FFF5F5'
    COR_CINZA        = '#F5F5F5'
    COR_LARANJA      = '#FFE0B2'
    COR_AMARELO      = '#FFF9C4'

    # ── Formatos ─────────────────────────────────────────────────────────────
    # Títulos (Padrão CRM)
    fmt_titulo = wb.add_format({
        'bold': True, 'font_size': 18, 'font_color': COR_AZUL_ESCURO,
        'align': 'left', 'valign': 'vcenter'
    })
    fmt_subtitulo = wb.add_format({
        'font_size': 10, 'font_color': '#555555', 'align': 'left', 'valign': 'vcenter'
    })
    fmt_link_doc = wb.add_format({
        'font_size': 9, 'font_color': 'blue', 'underline': True,
        'align': 'left', 'valign': 'top'
    })
    fmt_aviso_top = wb.add_format({
        'bold': True, 'font_size': 10, 'font_color': COR_VERMELHO_ESC,
        'align': 'left', 'valign': 'vcenter'
    })

    fmt_card_label = wb.add_format({
        'font_size': 9, 'font_color': '#757575', 'align': 'center', 'valign': 'top',
        'bg_color': COR_CINZA, 'top': 1, 'left': 1, 'right': 1,
        'top_color': '#BDBDBD', 'left_color': '#BDBDBD', 'right_color': '#BDBDBD'
    })
    fmt_card_val = wb.add_format({
        'bold': True, 'font_size': 18, 'align': 'center', 'valign': 'vcenter',
        'bg_color': COR_CINZA, 'font_color': COR_VERMELHO_ESC,
        'bottom': 1, 'left': 1, 'right': 1,
        'bottom_color': '#BDBDBD', 'left_color': '#BDBDBD', 'right_color': '#BDBDBD'
    })
    fmt_card_val_moeda = wb.add_format({
        'bold': True, 'font_size': 14, 'align': 'center', 'valign': 'vcenter',
        'bg_color': COR_CINZA, 'font_color': COR_VERMELHO_ESC,
        'num_format': 'R$ #,##0.00',
        'bottom': 1, 'left': 1, 'right': 1,
        'bottom_color': '#BDBDBD', 'left_color': '#BDBDBD', 'right_color': '#BDBDBD'
    })
    fmt_card_val_pct = wb.add_format({
        'bold': True, 'font_size': 18, 'align': 'center', 'valign': 'vcenter',
        'bg_color': COR_CINZA, 'font_color': COR_VERMELHO_ESC,
        'num_format': '0.00%',
        'bottom': 1, 'left': 1, 'right': 1,
        'bottom_color': '#BDBDBD', 'left_color': '#BDBDBD', 'right_color': '#BDBDBD'
    })
    fmt_hdr_col = wb.add_format({
        'bold': True, 'font_size': 9, 'bg_color': '#999999', 'font_color': 'white',
        'align': 'center', 'valign': 'vcenter', 'border': 1
    })
    fmt_hdr_col_left = wb.add_format({
        'bold': True, 'font_size': 9, 'bg_color': '#999999', 'font_color': 'white',
        'align': 'left', 'valign': 'vcenter', 'border': 1, 'indent': 1
    })
    fmt_cpf_header = wb.add_format({
        'bold': True, 'font_size': 10, 'bg_color': '#FFCDD2', 'font_color': 'black',
        'align': 'left', 'valign': 'vcenter', 'border': 1, 'indent': 1
    })
    fmt_row = wb.add_format({
        'bg_color': COR_VERMELHO_CLR, 'align': 'left', 'valign': 'vcenter', 'border': 1
    })
    fmt_row_center = wb.add_format({
        'bg_color': COR_VERMELHO_CLR, 'align': 'center', 'valign': 'vcenter', 'border': 1
    })
    fmt_row_int = wb.add_format({
        'bg_color': COR_VERMELHO_CLR, 'align': 'right', 'valign': 'vcenter',
        'border': 1, 'num_format': '#,##0'
    })
    fmt_row_moeda = wb.add_format({
        'bg_color': COR_VERMELHO_CLR, 'align': 'right', 'valign': 'vcenter',
        'border': 1, 'num_format': 'R$ #,##0.00'
    })
    fmt_dias_amarelo = wb.add_format({
        'bg_color': '#FFF9C4', 'align': 'center', 'valign': 'vcenter',
        'border': 1, 'num_format': '#,##0', 'bold': True
    })
    fmt_dias_laranja = wb.add_format({
        'bg_color': '#FFE0B2', 'align': 'center', 'valign': 'vcenter',
        'border': 1, 'num_format': '#,##0', 'bold': True
    })
    fmt_dias_vermelho = wb.add_format({
        'bg_color': '#FFCDD2', 'font_color': 'black', 'align': 'center',
        'valign': 'vcenter', 'border': 1, 'num_format': '#,##0', 'bold': True
    })

    # Novos formatos para o Painel de Distribuição
    fmt_painel_titulo = wb.add_format({
        'bold': True, 'font_size': 11, 'bg_color': COR_AZUL_ESCURO, 'font_color': 'white',
        'align': 'center', 'valign': 'vcenter', 'border': 1
    })
    fmt_painel_hdr = wb.add_format({
        'bold': True, 'font_size': 9, 'bg_color': '#D0D0D0', 'align': 'center', 'valign': 'vcenter', 'border': 1
    })
    fmt_painel_row = wb.add_format({
        'font_size': 9, 'align': 'left', 'valign': 'vcenter', 'border': 1, 'bg_color': 'white'
    })
    fmt_painel_row_center = wb.add_format({
        'font_size': 9, 'align': 'center', 'valign': 'vcenter', 'border': 1, 'bg_color': 'white'
    })
    fmt_painel_pct = wb.add_format({
        'font_size': 9, 'align': 'center', 'valign': 'vcenter', 'border': 1, 'bg_color': 'white', 'num_format': '0.0%'
    })
    fmt_subtotal = wb.add_format({
        'bg_color': COR_VERMELHO_CLR, 'align': 'left', 'valign': 'vcenter', 'border': 1
    })
    fmt_subtotal_num = wb.add_format({
        'bold': True, 'bg_color': COR_VERMELHO_CLR, 'align': 'right', 'valign': 'vcenter',
        'border': 1, 'num_format': '#,##0'
    })
    fmt_subtotal_moeda = wb.add_format({
        'bold': True, 'bg_color': COR_VERMELHO_CLR, 'align': 'right', 'valign': 'vcenter',
        'border': 1, 'num_format': 'R$ #,##0.00'
    })
    fmt_total_geral = wb.add_format({
        'bold': True, 'font_size': 11, 'bg_color': '#999999', 'font_color': 'white',
        'align': 'left', 'valign': 'vcenter',
        'left': 2, 'right': 2, 'top': 2, 'bottom': 2
    })
    fmt_total_geral_num = wb.add_format({
        'bold': True, 'font_size': 11, 'bg_color': '#999999', 'font_color': 'white',
        'align': 'right', 'valign': 'vcenter', 'num_format': '#,##0',
        'left': 2, 'right': 2, 'top': 2, 'bottom': 2
    })
    fmt_total_geral_moeda = wb.add_format({
        'bold': True, 'font_size': 11, 'bg_color': '#999999', 'font_color': 'white',
        'align': 'right', 'valign': 'vcenter', 'num_format': 'R$ #,##0.00',
        'left': 2, 'right': 2, 'top': 2, 'bottom': 2
    })

    # ── Informações da farmácia ──────────────────────────────────────────────
    cnpj_fmt = (f'{cnpj_analise[:2]}.{cnpj_analise[2:5]}.{cnpj_analise[5:8]}'
                f'/{cnpj_analise[8:12]}-{cnpj_analise[12:14]}')
    razao = dados_farmacias.get(cnpj_analise, {}).get('razaoSocial', 'DESCONHECIDO')
    mun   = dados_farmacias.get(cnpj_analise, {}).get('municipio', '')
    uf    = dados_farmacias.get(cnpj_analise, {}).get('uf', '')

    # ── Cálculo dos 7 cards (a partir dos dados em memória) ──────────────────
    cpfs_distintos     = len(set(r['cpf'] for r in dados_falecidos))
    total_autorizacoes = len(dados_falecidos)
    valor_total        = sum(float(r.get('valor_total_autorizacao') or 0) for r in dados_falecidos)
    maior_valor        = max(float(r.get('valor_total_autorizacao') or 0) for r in dados_falecidos)
    dias_lista         = [int(r['dias_apos_obito']) for r in dados_falecidos
                          if r.get('dias_apos_obito') is not None]
    media_dias         = round(sum(dias_lista) / len(dias_lista), 1) if dias_lista else 0
    max_dias           = max(dias_lista) if dias_lista else 0
    pct_faturamento    = (valor_total / float(valor_total_auditado)
                          if valor_total_auditado and valor_total_auditado > 0 else 0)

    # Cálculo específico para Multi-CNPJ (considera CPFs únicos)
    cpfs_vistos = {}
    for r in dados_falecidos:
        if r['cpf'] not in cpfs_vistos:
            cpfs_vistos[r['cpf']] = r
    
    cpfs_multi_cnpj = sum(1 for r in cpfs_vistos.values() if r.get('outros_estabelecimentos'))
    pct_multi_cnpj  = (cpfs_multi_cnpj / cpfs_distintos if cpfs_distintos > 0 else 0)

    # ── Distribuição por Outros Estabelecimentos ──────────────────────────
    distribuicao_set = defaultdict(set) # {estab_name: set(cpfs)}
    if cpfs_multi_cnpj > 0:
        for cpf, r in cpfs_vistos.items():
            outros_raw = r.get('outros_estabelecimentos')
            if outros_raw:
                estabelecimentos = outros_raw.split('; ')
                for estab in estabelecimentos:
                    try:
                        c_out, loc_out = estab.split(' | ')
                        c_m = f"{c_out[:2]}.{c_out[2:5]}.{c_out[5:8]}/{c_out[8:12]}-{c_out[12:]}"
                        nome_fmt = f"{c_m} - {loc_out}"
                        distribuicao_set[nome_fmt].add(cpf)
                    except:
                        distribuicao_set[estab].add(cpf)

    # Converte para lista ordenada por frequência descrescente
    ranking_dist = []
    for nome, cpfs in distribuicao_set.items():
        ranking_dist.append({
            'nome': nome,
            'qtd': len(cpfs),
            'pct': len(cpfs) / cpfs_multi_cnpj if cpfs_multi_cnpj > 0 else 0
        })
    ranking_dist.sort(key=lambda x: x['qtd'], reverse=True)

    NUM_COLS = 16  # Colunas A até P (0 a 15)

    # =================================================================
    # CABEÇALHO (PADRÃO ABA CRMs)
    # =================================================================
    ws.write('A2', "VENDAS PARA PACIENTES FALECIDOS", fmt_titulo)
    ws.write('A3', f"{razao} | CNPJ: {cnpj_fmt}", fmt_subtitulo)
    ws.write('A4', f"📍 {mun} - {uf}", fmt_subtitulo)
    ws.write_url('A5', 'https://cgu-sc.github.io/sentinela/', fmt_link_doc, string='📘 Acesse a Documentação')

    row_cards = 6
    # ── Cards — Linha Única (6 cards) ──
    ws.set_row(row_cards, 22)
    ws.set_row(row_cards + 1, 36)
    for col_s, col_e, val, label, tipo in [
        (0,   1,  str(cpfs_distintos),            'CPFs Distintos (Pacientes)',  'int'),
        (2,   3,  total_autorizacoes,             'Autorizações Afetadas',       'int'),
        (4,   5,  valor_total,                    'Valor Total (R$)',            'moeda'),
        (6,   7,  f'{media_dias:.1f} dias',       'Média de Dias após o Óbito',  'str'),
        (8,   9,  f'{max_dias} dias',             'Máximo de Dias após o Óbito', 'str'),
        (10, 12,  pct_faturamento,                '% do Faturamento Total',      'pct'),
        (13, 14,  f"{cpfs_multi_cnpj} ({pct_multi_cnpj:.1%})", 'Falecidos Multi-CNPJ', 'str'),
    ]:
        ws.merge_range(row_cards, col_s, row_cards, col_e, label, fmt_card_label)
        if tipo == 'moeda':
            fmt_v = fmt_card_val_moeda
        elif tipo == 'pct':
            fmt_v = fmt_card_val_pct
        else:
            fmt_v = fmt_card_val
        ws.merge_range(row_cards + 1, col_s, row_cards + 1, col_e, val, fmt_v)

    # ── Espaçador ────────────────────────────────────────────────────────────
    row_tabela = row_cards + 3
    ws.set_row(row_tabela - 1, 8)

    # =================================================================
    # PAINEL DE DISTRIBUIÇÃO (COLUNAS M A P)
    # =================================================================
    if ranking_dist:
        curr_row = row_tabela
        ws.merge_range(curr_row, 12, curr_row, 15, "FALECIDOS IDENTIFICADOS EM OUTROS CNPJs", fmt_painel_titulo)
        curr_row += 1
        ws.write(curr_row, 12, "Estabelecimento", fmt_painel_hdr)
        ws.write(curr_row, 13, "Qtd CPFs",      fmt_painel_hdr)
        ws.write(curr_row, 14, "Peso Visual",   fmt_painel_hdr)
        ws.write(curr_row, 15, "% do Total",    fmt_painel_hdr)
        curr_row += 1
        
        start_data_row = curr_row
        for item in ranking_dist[:20]: # Top 20
            ws.set_row(curr_row, 18)
            ws.write(curr_row, 12, item['nome'],  fmt_painel_row)
            ws.write(curr_row, 13, item['qtd'],   fmt_painel_row_center)
            ws.write(curr_row, 14, item['qtd'],   fmt_painel_row_center) # Valor para a barra
            ws.write(curr_row, 15, item['pct'],   fmt_painel_pct)
            curr_row += 1
        end_data_row = curr_row - 1
        
        # Barra de progresso visual (Formatação Condicional)
        if end_data_row >= start_data_row:
            ws.conditional_format(start_data_row, 14, end_data_row, 14, {
                'type': 'data_bar',
                'bar_only': True,    # Exibe apenas a barra, oculta o número
                'data_bar_2010': True,
                'bar_color': COR_VERMELHO_MED,
                'min_type': 'num', 'min_value': 0,
                'max_type': 'num', 'max_value': cpfs_multi_cnpj if cpfs_multi_cnpj > 0 else 1
            })

    # ── Header da tabela ─────────────────────────────────────────────────────
    ws.set_row(row_tabela, 30)
    for c, (txt, fmt) in enumerate([
        ('CPF',               fmt_hdr_col_left),
        ('Nome do Falecido',  fmt_hdr_col_left),
        ('Município / UF',    fmt_hdr_col),
        ('Dt. Nascimento',    fmt_hdr_col),
        ('Dt. Óbito',         fmt_hdr_col),
        ('Fonte Óbito',       fmt_hdr_col),
        ('Nº Autorização',    fmt_hdr_col),
        ('Data da Venda',     fmt_hdr_col),
        ('Itens',             fmt_hdr_col),
        ('Valor (R$)',        fmt_hdr_col),
        ('Dias após Óbito',   fmt_hdr_col),
    ]):
        ws.write(row_tabela, c, txt, fmt)

    # ── Tabela agrupada por CPF ───────────────────────────────────────────────
    grupos = defaultdict(list)
    for r in dados_falecidos:
        grupos[r['cpf']].append(r)

    def _fmt_data(d):
        if d is None:
            return '-'
        if hasattr(d, 'strftime'):
            return d.strftime('%d/%m/%Y')
        return str(d)[:10]

    row            = row_tabela + 1
    total_g_aut    = 0
    total_g_valor  = 0.0

    for cpf, transacoes in grupos.items():
        cpf_str  = str(cpf).zfill(11)
        cpf_mask = f'{cpf_str[:3]}.{cpf_str[3:6]}.{cpf_str[6:9]}-{cpf_str[9:11]}'

        primeiro   = transacoes[0]
        nome       = primeiro.get('nome_falecido') or '(não identificado)'
        mun_cpf    = primeiro.get('municipio_falecido') or ''
        uf_cpf     = primeiro.get('uf_falecido') or ''
        mun_uf     = f'{mun_cpf}/{uf_cpf}' if mun_cpf else uf_cpf
        dt_nasc    = _fmt_data(primeiro.get('dt_nascimento'))
        dt_obito   = _fmt_data(primeiro.get('dt_obito'))
        fonte_ob   = primeiro.get('fonte_obito') or '-'

        sub_aut    = len(transacoes)
        sub_valor  = sum(float(t.get('valor_total_autorizacao') or 0) for t in transacoes)

        # ── Informação de Multi-CNPJ ──────────────────────────────────────────
        multi_msg = ""
        outros_raw = primeiro.get('outros_estabelecimentos')
        if outros_raw:
            lista_raw = outros_raw.split('; ')
            qtd_outros = len(lista_raw)
            lista_fmt = []
            for item in lista_raw:
                try:
                    c_out, loc_out = item.split(' | ')
                    c_m = f"{c_out[:2]}.{c_out[2:5]}.{c_out[5:8]}/{c_out[8:12]}-{c_out[12:]}"
                    lista_fmt.append(f"{c_m} - {loc_out}")
                except:
                    lista_fmt.append(item)
            
            multi_msg = f"   |   ⚠️ Multi-CNPJ: {qtd_outros} estabelecimentos ({'; '.join(lista_fmt)})"

        # Linha-título do CPF (Merge apenas até coluna K - índice 10)
        ws.set_row(row, 22)
        ws.merge_range(row, 0, row, 10,
            f'  {cpf_mask}   {nome}   —   {sub_aut} autorização(ões)   |   '
            f'R$ {sub_valor:,.2f}   |   Óbito: {dt_obito}' + multi_msg,
            fmt_cpf_header)
        row += 1

        # Linhas de transação
        for t in transacoes:
            ws.set_row(row, 18)
            dias = int(t.get('dias_apos_obito') or 0)
            fmt_dias = (fmt_dias_amarelo  if dias <= 30 else
                        fmt_dias_laranja  if dias <= 365 else
                        fmt_dias_vermelho)

            dt_aut = t.get('data_autorizacao')
            if dt_aut and hasattr(dt_aut, 'strftime'):
                dt_aut_str = dt_aut.strftime('%d/%m/%Y %H:%M')
            else:
                dt_aut_str = str(dt_aut)[:16] if dt_aut else '-'

            ws.write(row, 0,  cpf_mask,                                           fmt_row)
            ws.write(row, 1,  nome,                                                fmt_row)
            ws.write(row, 2,  mun_uf,                                              fmt_row_center)
            ws.write(row, 3,  dt_nasc,                                             fmt_row_center)
            ws.write(row, 4,  dt_obito,                                            fmt_row_center)
            ws.write(row, 5,  fonte_ob,                                            fmt_row_center)
            ws.write(row, 6,  str(t.get('num_autorizacao') or '-'),                fmt_row)
            ws.write(row, 7,  dt_aut_str,                                          fmt_row_center)
            ws.write(row, 8,  int(t.get('qtd_itens_na_autorizacao') or 0),        fmt_row_int)
            ws.write(row, 9,  float(t.get('valor_total_autorizacao') or 0),       fmt_row_moeda)
            ws.write(row, 10, dias,                                                fmt_dias)
            row += 1

        # Subtotal do CPF
        ws.set_row(row, 20)
        ws.merge_range(row, 0, row, 7, '', fmt_subtotal)
        ws.write(row, 8,  sub_aut,   fmt_subtotal_num)
        ws.write(row, 9,  sub_valor, fmt_subtotal_moeda)
        ws.write(row, 10, '',        fmt_subtotal)
        row += 1

        total_g_aut   += sub_aut
        total_g_valor += sub_valor

    # ── Total Geral ───────────────────────────────────────────────────────────
    ws.set_row(row, 28)
    ws.merge_range(row, 0, row, 7,
        f'  TOTAL GERAL  —  {cpfs_distintos} CPF(s) distintos', fmt_total_geral)
    ws.write(row, 8,  total_g_aut,   fmt_total_geral_num)
    ws.write(row, 9,  total_g_valor, fmt_total_geral_moeda)
    ws.write(row, 10, '',            fmt_total_geral)

    # ── Largura das colunas ───────────────────────────────────────────────────
    ws.set_column(0,  0,  14)   # CPF (-2)
    ws.set_column(1,  1,  18)   # Nome
    ws.set_column(2,  2,  16)   # Município/UF (-2)
    ws.set_column(3,  3,  14)   # Dt. Nascimento (-2)
    ws.set_column(4,  4,  14)   # Dt. Óbito (-2)
    ws.set_column(5,  5,  12)   # Fonte
    ws.set_column(6,  6,  16)   # Nº Autorização
    ws.set_column(7,  7,  14)   # Data Venda (-2)
    ws.set_column(8,  8,  10)   # Itens (-2)
    ws.set_column(9,  9,  12)   # Valor (-2)
    ws.set_column(10, 10, 12)   # Dias (-2)
    ws.set_column(11, 11, 2)    # Espaço (reduzido para 2)
    ws.set_column(12, 12, 32)   # Estabelecimento Painel (reduzido em 3)
    ws.set_column(13, 13, 10)   # Qtd Painel
    ws.set_column(14, 14, 15)   # Barra Painel
    ws.set_column(15, 15, 12)   # % Painel

    ws.freeze_panes(row_tabela + 1, 0)  # Congela acima do header da tabela
