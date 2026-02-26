import logging
from decimal import Decimal


def buscar_dados_prescritores(cursor, cnpj):
    """
    Busca os indicadores consolidados de prescritores para um CNPJ.
    Retorna dict com todas as métricas ou None se não encontrar.
    """
    try:
        cursor.execute('''
            SELECT * FROM temp_CGUSC.fp.indicadorCRM_Completo 
            WHERE cnpj = ?
        ''', cnpj)
        row = cursor.fetchone()

        if row:
            cols = [column[0] for column in cursor.description]
            return dict(zip(cols, row))
        return None

    except Exception as e:
        logging.error(f"Erro ao buscar dados de prescritores para {cnpj}: {e}")
        return None


def buscar_top20_prescritores(cursor, cnpj):
    """
    Busca a lista dos prescritores de interesse de uma farmácia.
    Inclui: Top 20 por volume + todos os prescritores com alertas ativos.
    Retorna lista de dicts ou lista vazia se não encontrar.
    """
    try:
        cursor.execute('''
            SELECT * FROM temp_CGUSC.fp.top20CRMsPorFarmacia 
            WHERE cnpj = ?
            ORDER BY ranking
        ''', cnpj)

        rows = cursor.fetchall()
        if rows:
            cols = [column[0] for column in cursor.description]
            return [dict(zip(cols, row)) for row in rows]
        return []

    except Exception as e:
        logging.error(f"Erro ao buscar prescritores de interesse para {cnpj}: {e}")
        return []


def _get_valor(dados, campo, default=0):
    """Helper para extrair valor de um dict, tratando None e Decimal."""
    val = dados.get(campo, default)
    if val is None:
        return default
    if isinstance(val, Decimal):
        return float(val)
    return val


def gerar_aba_prescritores(wb, cnpj, dados_prescritores, top20_prescritores):
    """
    Gera a aba 'análise de crms' no workbook Excel.

    Args:
        wb: Workbook do xlsxwriter
        cnpj: CNPJ da farmácia (string)
        dados_prescritores: Dict com métricas consolidadas
        top20_prescritores: Lista de dicts com Top 20 prescritores
    """
    if not dados_prescritores:
        logging.warning(f"Sem dados de prescritores para {cnpj}. Aba não será gerada.")
        return

    ws = wb.add_worksheet('Análise de CRMs')
    ws.hide_gridlines(2)

    # =================================================================
    # CONSTANTES DE CRITÉRIOS
    # =================================================================
    LIMITE_ROBO_DIA = 30  # >30 prescrições/dia
    LIMITE_MULTI_FARMACIA = 20  # >20 estabelecimentos

    # =================================================================
    # DEFINIÇÃO DE CORES
    # =================================================================
    COR_AZUL_ESCURO = '#1F4E78'
    COR_CINZA_CLARO = '#F2F2F2'
    COR_VERMELHO = '#860010'
    COR_VERMELHO_BG = '#FFABB5'
    COR_AMARELO = '#FFC000'
    COR_AMARELO_BG = '#FFF2CC'

    COR_VERDE = '#548235'
    COR_VERDE_BG = '#F1F7ED'

    COR_ROXO = '#7030A0'
    COR_ROXO_BG = '#E4DFEC'

    COR_LARANJA = '#B45210'
    COR_LARANJA_BG = '#FFCA7D'

    COR_AZUL_GEO = '#2F75B5'  # Azul forte para texto
    COR_AZUL_GEO_BG = '#DDEBF7'  # Azul claro para fundo

    COR_VERMELHO_CARDS = '#860010'
    COR_VERMELHO_CARDS_BG = '#FFC9CF'

    COR_MAGENTA = '#C00060'  # Um rosa/magenta bem escuro e sério
    COR_MAGENTA_BG = '#FFB9E3'  # Fundo rosa claro

    COR_LINHA_COM_ALERTA = '#FFEBEE'  # Vermelho claro para linhas com problema
    COR_LINHA_SEM_ALERTA = '#F1F7ED'  # Verde bem claro para linhas OK

    # =================================================================
    # FORMATOS
    # =================================================================

    # Títulos
    fmt_titulo = wb.add_format({
        'bold': True, 'font_size': 18, 'font_color': COR_AZUL_ESCURO,
        'align': 'left', 'valign': 'vcenter'
    })
    fmt_subtitulo = wb.add_format({
        'font_size': 10, 'font_color': '#555555', 'align': 'left', 'valign': 'vcenter'
    })

    # Cards
    fmt_card_titulo = wb.add_format({
        'bold': True, 'font_size': 9, 'font_color': '#555555',
        'align': 'center', 'valign': 'vcenter', 'text_wrap': True
    })
    fmt_card_valor_normal = wb.add_format({
        'bold': True, 'font_size': 18, 'font_color': COR_VERDE,
        'align': 'center', 'valign': 'vcenter', 'bg_color': COR_VERDE_BG,
        'border': 1, 'border_color': COR_VERDE
    })
    fmt_card_valor_atencao = wb.add_format({
        'bold': True, 'font_size': 18, 'font_color': '#9C5700',
        'align': 'center', 'valign': 'vcenter', 'bg_color': COR_AMARELO_BG,
        'border': 1, 'border_color': COR_AMARELO
    })
    fmt_card_valor_critico = wb.add_format({
        'bold': True, 'font_size': 18, 'font_color': '#9C0006',
        'align': 'center', 'valign': 'vcenter', 'bg_color': COR_VERMELHO_CARDS_BG,
        'border': 1, 'border_color': COR_VERMELHO_CARDS
    })
    fmt_card_valor_rede = wb.add_format({
        'bold': True, 'font_size': 18, 'font_color': COR_ROXO,
        'align': 'center', 'valign': 'vcenter', 'bg_color': COR_ROXO_BG,
        'border': 1, 'border_color': COR_ROXO
    })
    fmt_card_detalhe = wb.add_format({
        'font_size': 8, 'font_color': '#777777',
        'align': 'center', 'valign': 'vcenter', 'text_wrap': True
    })

    # Seções
    fmt_secao_titulo = wb.add_format({
        'bold': True, 'font_size': 11, 'bg_color': COR_AZUL_ESCURO, 'font_color': 'white',
        'align': 'left', 'valign': 'vcenter', 'indent': 1, 'border': 1
    })

    # Tabelas
    fmt_header_tabela = wb.add_format({
        'bold': True, 'font_size': 9, 'bg_color': COR_CINZA_CLARO, 'font_color': 'black',
        'align': 'center', 'valign': 'vcenter', 'border': 1, 'text_wrap': True
    })
    fmt_header_rede = wb.add_format({
        'bold': True, 'font_size': 9, 'bg_color': COR_ROXO_BG, 'font_color': COR_ROXO,
        'align': 'center', 'valign': 'vcenter', 'border': 1, 'text_wrap': True
    })
    fmt_celula = wb.add_format({
        'font_size': 9, 'align': 'left', 'valign': 'vcenter', 'border': 1
    })
    fmt_celula_center = wb.add_format({
        'font_size': 9, 'align': 'center', 'valign': 'vcenter', 'border': 1
    })
    fmt_celula_numero = wb.add_format({
        'font_size': 9, 'align': 'right', 'valign': 'vcenter', 'border': 1,
        'num_format': '#,##0'
    })
    fmt_celula_moeda = wb.add_format({
        'font_size': 9, 'align': 'right', 'valign': 'vcenter', 'border': 1,
        'num_format': 'R$ #,##0.00'
    })
    fmt_celula_pct = wb.add_format({
        'font_size': 9, 'align': 'center', 'valign': 'vcenter', 'border': 1,
        'num_format': '0.00%'
    })
    fmt_celula_decimal = wb.add_format({
        'font_size': 9, 'align': 'center', 'valign': 'vcenter', 'border': 1,
        'num_format': '0.00'
    })
    fmt_celula_data = wb.add_format({
        'font_size': 9, 'align': 'center', 'valign': 'vcenter', 'border': 1,
        'num_format': 'DD/MM/YYYY'
    })

    # Alertas
    fmt_alerta_vermelho = wb.add_format({
        'font_size': 9, 'align': 'center', 'valign': 'vcenter', 'border': 1,
        'bg_color': COR_VERMELHO_BG, 'font_color': COR_VERMELHO, 'bold': True
    })
    fmt_alerta_vermelho_data = wb.add_format({
        'font_size': 9, 'align': 'center', 'valign': 'vcenter', 'border': 1,
        'bg_color': COR_VERMELHO_BG, 'font_color': COR_VERMELHO, 'bold': True,
        'num_format': 'DD/MM/YYYY'
    })
    fmt_alerta_roxo = wb.add_format({
        'font_size': 9, 'align': 'center', 'valign': 'vcenter', 'border': 1,
        'bg_color': COR_ROXO_BG, 'font_color': COR_ROXO, 'bold': True
    })
    fmt_alerta_laranja = wb.add_format({
        'font_size': 9, 'align': 'center', 'valign': 'vcenter', 'border': 1,
        'bg_color': COR_LARANJA_BG, 'font_color': COR_LARANJA, 'bold': True
    })

    fmt_alerta_azul_geo = wb.add_format({
        'font_size': 9, 'align': 'center', 'valign': 'vcenter', 'border': 1,
        'bg_color': COR_AZUL_GEO_BG, 'font_color': COR_AZUL_GEO, 'bold': True
    })

    fmt_alerta_magenta = wb.add_format({
        'font_size': 9, 'align': 'center', 'valign': 'vcenter', 'border': 1,
        'bg_color': COR_MAGENTA_BG, 'font_color': COR_MAGENTA, 'bold': True
    })

    fmt_alerta_ok = wb.add_format({
        'font_size': 9, 'align': 'center', 'valign': 'vcenter', 'border': 1,
        'bg_color': COR_VERDE_BG, 'font_color': COR_VERDE
    })

    # Notas
    fmt_nota = wb.add_format({
        'font_size': 9, 'font_color': '#555555', 'italic': True, 'text_wrap': True,
        'valign': 'top', 'border': 1, 'bg_color': '#FAFAFA'
    })

    fmt_alerta_celula = wb.add_format({
        'font_size': 9, 'align': 'left', 'valign': 'vcenter', 'border': 1,
        'bg_color': COR_LINHA_COM_ALERTA
    })
    fmt_alerta_celula_center = wb.add_format({
        'font_size': 9, 'align': 'center', 'valign': 'vcenter', 'border': 1,
        'bg_color': COR_LINHA_COM_ALERTA
    })
    fmt_alerta_celula_numero = wb.add_format({
        'font_size': 9, 'align': 'right', 'valign': 'vcenter', 'border': 1,
        'num_format': '#,##0', 'bg_color': COR_LINHA_COM_ALERTA
    })
    fmt_alerta_celula_moeda = wb.add_format({
        'font_size': 9, 'align': 'right', 'valign': 'vcenter', 'border': 1,
        'num_format': 'R$ #,##0.00', 'bg_color': COR_LINHA_COM_ALERTA
    })
    fmt_alerta_celula_pct = wb.add_format({
        'font_size': 9, 'align': 'center', 'valign': 'vcenter', 'border': 1,
        'num_format': '0.00%', 'bg_color': COR_LINHA_COM_ALERTA
    })
    fmt_alerta_celula_decimal = wb.add_format({
        'font_size': 9, 'align': 'center', 'valign': 'vcenter', 'border': 1,
        'num_format': '0.00', 'bg_color': COR_LINHA_COM_ALERTA
    })
    fmt_alerta_celula_data = wb.add_format({
        'font_size': 9, 'align': 'center', 'valign': 'vcenter', 'border': 1,
        'num_format': 'DD/MM/YYYY', 'bg_color': COR_LINHA_COM_ALERTA
    })

    fmt_ok_celula = wb.add_format({
        'font_size': 9, 'align': 'left', 'valign': 'vcenter', 'border': 1,
        'bg_color': COR_LINHA_SEM_ALERTA
    })
    fmt_ok_celula_center = wb.add_format({
        'font_size': 9, 'align': 'center', 'valign': 'vcenter', 'border': 1,
        'bg_color': COR_LINHA_SEM_ALERTA
    })
    fmt_ok_celula_numero = wb.add_format({
        'font_size': 9, 'align': 'right', 'valign': 'vcenter', 'border': 1,
        'num_format': '#,##0', 'bg_color': COR_LINHA_SEM_ALERTA
    })
    fmt_ok_celula_moeda = wb.add_format({
        'font_size': 9, 'align': 'right', 'valign': 'vcenter', 'border': 1,
        'num_format': 'R$ #,##0.00', 'bg_color': COR_LINHA_SEM_ALERTA
    })
    fmt_ok_celula_pct = wb.add_format({
        'font_size': 9, 'align': 'center', 'valign': 'vcenter', 'border': 1,
        'num_format': '0.00%', 'bg_color': COR_LINHA_SEM_ALERTA
    })
    fmt_ok_celula_decimal = wb.add_format({
        'font_size': 9, 'align': 'center', 'valign': 'vcenter', 'border': 1,
        'num_format': '0.00', 'bg_color': COR_LINHA_SEM_ALERTA
    })
    fmt_ok_celula_data = wb.add_format({
        'font_size': 9, 'align': 'center', 'valign': 'vcenter', 'border': 1,
        'num_format': 'DD/MM/YYYY', 'bg_color': COR_LINHA_SEM_ALERTA
    })

    # Função para formato de risco
    def get_formato_risco(valor):
        if valor >= 5:
            return wb.add_format({
                'bg_color': COR_VERMELHO_CARDS_BG, 'font_color': COR_VERMELHO_CARDS, 'bold': True,
                'align': 'center', 'valign': 'vcenter', 'border': 1, 'num_format': '0.00x'
            })
        elif valor >= 2:
            return wb.add_format({
                'bg_color': COR_AMARELO_BG, 'font_color': '#9C5700', 'bold': True,
                'align': 'center', 'valign': 'vcenter', 'border': 1, 'num_format': '0.00x'
            })
        else:
            return wb.add_format({
                'bg_color': COR_VERDE_BG, 'font_color': '#006100', 'bold': True,
                'align': 'center', 'valign': 'vcenter', 'border': 1, 'num_format': '0.00x'
            })

    # =================================================================
    # EXTRAÇÃO DE VALORES
    # =================================================================
    pct_top1 = _get_valor(dados_prescritores, 'pct_concentracao_top1')
    pct_top5 = _get_valor(dados_prescritores, 'pct_concentracao_top5')
    id_top1 = dados_prescritores.get('id_top1_prescritor', '') or ''
    indice_hhi = _get_valor(dados_prescritores, 'indice_hhi')

    # Isso garante que os cards e a tabela mostrem os mesmos números
    qtd_robos = sum(1 for p in top20_prescritores if p.get('flag_robo', 0) == 1)
    qtd_robos_rede = sum(1 for p in top20_prescritores if p.get('flag_robo_oculto', 0) == 1)
    qtd_crm_inv = sum(1 for p in top20_prescritores if p.get('flag_crm_invalido', 0) == 1)
    qtd_alerta_geo = sum(1 for p in top20_prescritores
                         if p.get('alerta5_geografico', '') or p.get('alerta_geografico', '') or p.get('alerta5', ''))
    qtd_multi_farmacia = sum(1 for p in top20_prescritores if p.get('flag_multi_farmacia', 0) == 1)
    qtd_tempo_concentrado = sum(1 for p in top20_prescritores
                                if p.get('alerta2_tempo_concentrado', '') or p.get('alerta2', ''))
    qtd_prescricao_antes_registro = sum(1 for p in top20_prescritores
                                        if p.get('flag_prescricao_antes_registro', 0) == 1)

    # NOVA MÉTRICA: CRMs EXCLUSIVOS (Só atuam nesta farmácia)
    # Regra: qtd_estabelecimentos_atua == 1
    qtd_exclusivos = sum(1 for p in top20_prescritores if int(_get_valor(p, 'qtd_estabelecimentos_atua')) == 1)

    # Percentuais calculados sobre o total GERAL de prescritores da farmácia
    total_prescritores = int(_get_valor(dados_prescritores, 'total_prescritores_distintos', 1))
    pct_crm_inv = (qtd_crm_inv / total_prescritores) * 100 if total_prescritores > 0 else 0
    pct_multi_farmacia = (qtd_multi_farmacia / total_prescritores) * 100 if total_prescritores > 0 else 0

    # Dados que ainda vêm da indicadorCRM_Completo (métricas agregadas)
    indice_rede = _get_valor(dados_prescritores, 'indice_rede_suspeita')
    media_presc_dia_rede = _get_valor(dados_prescritores, 'media_prescricoes_dia_rede')

    # Médias
    media_top5_br = _get_valor(dados_prescritores, 'media_concentracao_top5_br', 40)
    media_rede_uf = _get_valor(dados_prescritores, 'media_indice_rede_uf', 1)

    # =================================================================
    # CABEÇALHO
    # =================================================================
    cnpj_fmt = f'{cnpj[:2]}.{cnpj[2:5]}.{cnpj[5:8]}/{cnpj[8:12]}-{cnpj[12:14]}'

    ws.write('B2', "ANÁLISE DE CRMs", fmt_titulo)
    ws.write('B3', f"{dados_prescritores.get('razaoSocial', '')} | CNPJ: {cnpj_fmt}", fmt_subtitulo)
    ws.write('B4', f"{dados_prescritores.get('municipio', '')} - {dados_prescritores.get('uf', '')}", fmt_subtitulo)

    # --- Link para Documentação ---
    fmt_link_doc = wb.add_format({
        'font_size': 9, 'font_color': 'blue', 'underline': True, 
        'align': 'left', 'valign': 'top'
    })
    ws.write_url('B5', 'https://cgu-sc.github.io/sentinela/', fmt_link_doc, string='📘 Acesse a Documentação')

    # =================================================================
    # CARDS DE RESUMO - LINHA 1 (Concentração e Anomalias)
    # =================================================================
    row_cards = 6

    # Card 1: Concentração Top 1
    ws.merge_range(row_cards, 1, row_cards, 2, "CONCENTRAÇÃO TOP 1", fmt_card_titulo)
    fmt_card = fmt_card_valor_critico if pct_top1 > 40 else (
        fmt_card_valor_atencao if pct_top1 > 20 else fmt_card_valor_normal)
    ws.merge_range(row_cards + 1, 1, row_cards + 2, 2, f"{pct_top1:.1f}%", fmt_card)
    ws.merge_range(row_cards + 3, 1, row_cards + 3, 2, f"CRM: {id_top1}", fmt_card_detalhe)

    # Card 2: Concentração Top 5
    ws.merge_range(row_cards, 3, row_cards, 4, "CONCENTRAÇÃO TOP 5", fmt_card_titulo)
    fmt_card = fmt_card_valor_critico if pct_top5 > 70 else (
        fmt_card_valor_atencao if pct_top5 > 50 else fmt_card_valor_normal)
    ws.merge_range(row_cards + 1, 3, row_cards + 2, 4, f"{pct_top5:.1f}%", fmt_card)
    ws.merge_range(row_cards + 3, 3, row_cards + 3, 4, f"Média BR: {media_top5_br:.1f}%", fmt_card_detalhe)

    # Card 3: >30/dia Aqui
    ws.merge_range(row_cards, 5, row_cards, 6, ">30/DIA AQUI", fmt_card_titulo)
    fmt_card = fmt_card_valor_critico if qtd_robos > 0 else fmt_card_valor_normal
    ws.merge_range(row_cards + 1, 5, row_cards + 2, 6, str(qtd_robos), fmt_card)
    ws.merge_range(row_cards + 3, 5, row_cards + 3, 6, "Nesta farmácia", fmt_card_detalhe)

    # Card 4: >30/dia Rede
    ws.merge_range(row_cards, 7, row_cards, 8, ">30/DIA REDE", fmt_card_titulo)
    fmt_card = fmt_card_valor_critico if qtd_robos_rede > 0 else fmt_card_valor_normal
    ws.merge_range(row_cards + 1, 7, row_cards + 2, 8, str(qtd_robos_rede), fmt_card)
    ws.merge_range(row_cards + 3, 7, row_cards + 3, 8, "Em Todos os Estabelecimentos", fmt_card_detalhe)

    # Card 5: CRMs Inválidos
    ws.merge_range(row_cards, 9, row_cards, 10, "CRMs INVÁLIDOS", fmt_card_titulo)
    fmt_card = fmt_card_valor_critico if qtd_crm_inv > 0 else fmt_card_valor_normal
    ws.merge_range(row_cards + 1, 9, row_cards + 2, 10, f"{qtd_crm_inv}", fmt_card)
    ws.merge_range(row_cards + 3, 9, row_cards + 3, 10, f"({pct_crm_inv:.1f}% do total)", fmt_card_detalhe)

    # Card 6: CRMs EXCLUSIVOS (NOVO - Substituiu Alerta >400km que foi para baixo)
    ws.merge_range(row_cards, 11, row_cards, 12, "CRMs EXCLUSIVOS", fmt_card_titulo)
    fmt_card = fmt_card_valor_atencao if qtd_exclusivos > 0 else fmt_card_valor_normal
    ws.merge_range(row_cards + 1, 11, row_cards + 2, 12, str(qtd_exclusivos), fmt_card)
    ws.merge_range(row_cards + 3, 11, row_cards + 3, 12, "Atuação única nesta farmácia", fmt_card_detalhe)

    # =================================================================
    # CARDS DE RESUMO - LINHA 2 (Rede)
    # =================================================================
    row_cards2 = row_cards + 5

    # Card 7: Multi-Farmácia
    ws.merge_range(row_cards2, 1, row_cards2, 2, "MULTI-FARMÁCIA", fmt_card_titulo)
    fmt_card = fmt_card_valor_rede if qtd_multi_farmacia > 0 else fmt_card_valor_normal
    ws.merge_range(row_cards2 + 1, 1, row_cards2 + 2, 2, str(qtd_multi_farmacia), fmt_card)
    ws.merge_range(row_cards2 + 3, 1, row_cards2 + 3, 2, f"({pct_multi_farmacia:.1f}%) em >20 farm.", fmt_card_detalhe)

    # Card 8: Índice de Rede Suspeita
    ws.merge_range(row_cards2, 3, row_cards2, 4, "ÍNDICE DE REDE", fmt_card_titulo)
    risco_rede = indice_rede / media_rede_uf if media_rede_uf > 0 else 0
    fmt_card = fmt_card_valor_critico if risco_rede > 3 else (
        fmt_card_valor_atencao if risco_rede > 1.5 else fmt_card_valor_normal)
    ws.merge_range(row_cards2 + 1, 3, row_cards2 + 2, 4, f"{indice_rede:.1f}", fmt_card)
    ws.merge_range(row_cards2 + 3, 3, row_cards2 + 3, 4, f"Média estab./CRMs", fmt_card_detalhe)

    # Card 9: HHI
    ws.merge_range(row_cards2, 5, row_cards2, 6, "ÍNDICE HHI", fmt_card_titulo)
    fmt_card = fmt_card_valor_critico if indice_hhi > 2500 else (
        fmt_card_valor_atencao if indice_hhi > 1500 else fmt_card_valor_normal)
    ws.merge_range(row_cards2 + 1, 5, row_cards2 + 2, 6, f"{indice_hhi:.0f}", fmt_card)
    ws.merge_range(row_cards2 + 3, 5, row_cards2 + 3, 6, ">2500 = Alta conc.", fmt_card_detalhe)

    # Card 10: Presc. Concentradas
    ws.merge_range(row_cards2, 7, row_cards2, 8, "PRESC. CONCENTRADAS", fmt_card_titulo)
    fmt_card_tempo = wb.add_format({
        'bold': True, 'font_size': 18, 'font_color': COR_LARANJA,
        'align': 'center', 'valign': 'vcenter', 'bg_color': COR_LARANJA_BG,
        'border': 1, 'border_color': COR_LARANJA
    })
    fmt_card = fmt_card_tempo if qtd_tempo_concentrado > 0 else fmt_card_valor_normal
    ws.merge_range(row_cards2 + 1, 7, row_cards2 + 2, 8, str(qtd_tempo_concentrado), fmt_card)
    ws.merge_range(row_cards2 + 3, 7, row_cards2 + 3, 8, "Presc. em curto período", fmt_card_detalhe)

    # Card 11: Alerta >400km (MOVIDO DA LINHA 1 PARA AQUI)
    ws.merge_range(row_cards2, 9, row_cards2, 10, "ALERTA >400KM", fmt_card_titulo)
    fmt_card = fmt_card_valor_critico if qtd_alerta_geo > 0 else fmt_card_valor_normal
    ws.merge_range(row_cards2 + 1, 9, row_cards2 + 2, 10, str(qtd_alerta_geo), fmt_card)
    ws.merge_range(row_cards2 + 3, 9, row_cards2 + 3, 10, "Atividade distante", fmt_card_detalhe)

    # =================================================================
    # INDICADORES DE RISCO (Tabela comparativa)
    # =================================================================
    row_ind = row_cards2 + 6
    ws.merge_range(row_ind, 1, row_ind, 7, "INDICADORES DE RISCO VS MÉDIAS", fmt_secao_titulo)
    row_ind += 1

    # Headers
    ws.write(row_ind, 1, "INDICADOR", fmt_header_tabela)
    ws.write(row_ind, 2, "FARMÁCIA", fmt_header_tabela)
    ws.write(row_ind, 3, "MÉDIA UF", fmt_header_tabela)
    ws.write(row_ind, 4, "MÉDIA BR", fmt_header_tabela)
    ws.write(row_ind, 5, "RISCO (x) UF", fmt_header_tabela)
    ws.write(row_ind, 6, "RISCO (x) BR", fmt_header_tabela)
    ws.write(row_ind, 7, "STATUS", fmt_header_tabela)
    row_ind += 1

    # Dados dos indicadores
    indicadores = [
        ("Concentração Top 1 (%)", pct_top1,
         _get_valor(dados_prescritores, 'media_concentracao_uf'),
         _get_valor(dados_prescritores, 'media_concentracao_br'),
         _get_valor(dados_prescritores, 'risco_concentracao_uf'),
         _get_valor(dados_prescritores, 'risco_concentracao_br')),
        ("Concentração Top 5 (%)", pct_top5,
         _get_valor(dados_prescritores, 'media_concentracao_top5_uf'),
         _get_valor(dados_prescritores, 'media_concentracao_top5_br'),
         _get_valor(dados_prescritores, 'risco_concentracao_top5_uf'),
         _get_valor(dados_prescritores, 'risco_concentracao_top5_br')),
        ("Índice HHI", indice_hhi,
         _get_valor(dados_prescritores, 'media_hhi_uf'),
         _get_valor(dados_prescritores, 'media_hhi_br'),
         _get_valor(dados_prescritores, 'risco_hhi_uf'),
         _get_valor(dados_prescritores, 'risco_hhi_br')),
        ("CRMs Inválidos (%)", pct_crm_inv,
         _get_valor(dados_prescritores, 'media_crm_invalido_uf'),
         _get_valor(dados_prescritores, 'media_crm_invalido_br'),
         _get_valor(dados_prescritores, 'risco_crm_invalido_uf'),
         _get_valor(dados_prescritores, 'risco_crm_invalido_br')),
        ("Prescritores Robô (>30/dia)", qtd_robos,
         _get_valor(dados_prescritores, 'media_robos_uf'),
         _get_valor(dados_prescritores, 'media_robos_br'),
         _get_valor(dados_prescritores, 'risco_robos_uf'),
         _get_valor(dados_prescritores, 'risco_robos_br')),
        ("Índice de Rede Suspeita", indice_rede,
         _get_valor(dados_prescritores, 'media_indice_rede_uf'),
         _get_valor(dados_prescritores, 'media_indice_rede_br'),
         _get_valor(dados_prescritores, 'risco_rede_uf'),
         _get_valor(dados_prescritores, 'risco_rede_br')),
    ]

    for nome, valor, media_uf, media_br, risco_uf, risco_br in indicadores:
        status = "CRÍTICO" if risco_uf >= 5 else ("ATENÇÃO" if risco_uf >= 2 else "NORMAL")
        ws.write(row_ind, 1, nome, fmt_celula)
        ws.write(row_ind, 2, valor, fmt_celula_decimal)
        ws.write(row_ind, 3, media_uf, fmt_celula_decimal)
        ws.write(row_ind, 4, media_br, fmt_celula_decimal)

        ws.write(row_ind, 5, risco_uf, get_formato_risco(risco_uf))
        ws.write(row_ind, 6, risco_br, get_formato_risco(risco_br))
        ws.write(row_ind, 7, status, fmt_header_tabela)
        row_ind += 1

    # =================================================================
    # TABELA CRMs DE INTERESSE
    # =================================================================
    row_top = row_ind + 2
    ws.merge_range(row_top, 1, row_top, 19, "TOP 20 CRMs DE INTERESSE - DETALHAMENTO", fmt_secao_titulo)
    row_top += 1

    # Header - Colunas básicas
    headers_top = [
        "#", "CRM/UF", "1ª Prescrição", "Data Reg. CRM", "Prescrições", "Valor (R$)", "% Part.", "% Acum.", "Presc/Dia"
    ]
    # Header - Colunas de rede (destacadas)
    headers_rede = [
        "Presc. Total BR", "Presc/Dia BR", "Nº Farmácias", "% Aqui"
    ]
    # Header - Flags
    # ADICIONADO "Exclusivo?"
    headers_flags = [
        ">30 Aqui?", ">30 Rede?", "Multi-Farm", "Tempo Conc.", "Exclusivo?", "> 400km"
    ]

    col = 1
    for h in headers_top:
        ws.write(row_top, col, h, fmt_header_tabela)
        col += 1
    for h in headers_rede:
        ws.write(row_top, col, h, fmt_header_rede)
        col += 1
    for h in headers_flags:
        ws.write(row_top, col, h, fmt_header_tabela)
        col += 1

    ws.set_row(row_top, 30)
    row_top += 1

    # Dados
    if top20_prescritores:
        for presc in top20_prescritores:
            ranking = int(_get_valor(presc, 'ranking'))
            id_medico = presc.get('id_medico', '') or ''
            nu_prescricoes = int(_get_valor(presc, 'nu_prescricoes'))
            vl_total = _get_valor(presc, 'vl_total_prescricoes')
            pct_part = _get_valor(presc, 'pct_participacao') / 100
            pct_acum = _get_valor(presc, 'pct_acumulado') / 100
            presc_dia = _get_valor(presc, 'nu_prescricoes_dia')

            # Dados de rede
            presc_total_br = int(_get_valor(presc, 'prescricoes_total_brasil'))
            presc_dia_br = _get_valor(presc, 'prescricoes_dia_total_brasil')
            qtd_estabelecimentos = int(_get_valor(presc, 'qtd_estabelecimentos_atua'))
            pct_aqui_vs_total = _get_valor(presc, 'pct_volume_aqui_vs_total') / 100 if _get_valor(presc,
                                                                                                  'pct_volume_aqui_vs_total') else 0

            # LÓGICA DE EXCLUSIVIDADE
            is_exclusivo = (qtd_estabelecimentos == 1)

            # Flags
            flag_robo = int(_get_valor(presc, 'flag_robo'))
            flag_robo_rede = int(_get_valor(presc, 'flag_robo_oculto'))
            flag_crm_inv = int(_get_valor(presc, 'flag_crm_invalido'))

            dt_primeira_prescricao = presc.get('dt_primeira_prescricao', None)

            dt_inscricao_crm = presc.get('dt_inscricao_crm', None)

            alerta1 = presc.get('alerta1_crm_invalido', '') or presc.get('alerta1', '') or ''
            alerta2 = presc.get('alerta2_tempo_concentrado', '') or presc.get('alerta2', '') or ''
            alerta3 = presc.get('alerta3_robo_estabelecimento', '') or presc.get('alerta3', '') or ''
            alerta4 = presc.get('alerta4_robo_rede', '') or presc.get('alerta4', '') or ''
            alerta_geo = presc.get('alerta5_geografico', '') or presc.get('alerta_geografico', '') or presc.get(
                'alerta5', '') or ''

            flag_prescricao_antes_registro = int(_get_valor(presc, 'flag_prescricao_antes_registro'))
            alerta6 = presc.get('alerta6_prescricao_antes_registro', '') or ''

            tem_alerta_linha = (
                    flag_crm_inv == 1 or
                    flag_robo == 1 or
                    flag_robo_rede == 1 or
                    flag_prescricao_antes_registro == 1 or
                    alerta2 or
                    alerta_geo or
                    qtd_estabelecimentos > LIMITE_MULTI_FARMACIA or
                    is_exclusivo or
                    not dt_inscricao_crm  # CRM inexistente
            )

            if tem_alerta_linha:
                f_celula = fmt_alerta_celula
                f_celula_center = fmt_alerta_celula_center
                f_celula_numero = fmt_alerta_celula_numero
                f_celula_moeda = fmt_alerta_celula_moeda
                f_celula_pct = fmt_alerta_celula_pct
                f_celula_decimal = fmt_alerta_celula_decimal
                f_celula_data = fmt_alerta_celula_data
            else:
                f_celula = fmt_ok_celula
                f_celula_center = fmt_ok_celula_center
                f_celula_numero = fmt_ok_celula_numero
                f_celula_moeda = fmt_ok_celula_moeda
                f_celula_pct = fmt_ok_celula_pct
                f_celula_decimal = fmt_ok_celula_decimal
                f_celula_data = fmt_ok_celula_data

            col = 1

            # Colunas básicas
            ws.write(row_top, col, ranking, f_celula_center);
            col += 1
            ws.write(row_top, col, id_medico, f_celula);
            col += 1

            if dt_primeira_prescricao:
                ws.write(row_top, col, dt_primeira_prescricao, f_celula_data)
            else:
                ws.write(row_top, col, "-", f_celula_center)
            col += 1

            if dt_inscricao_crm:
                # Converte ambas as datas para date() para comparação segura
                try:
                    data_inscricao = dt_inscricao_crm.date() if hasattr(dt_inscricao_crm, 'date') else dt_inscricao_crm
                    data_primeira = dt_primeira_prescricao.date() if hasattr(dt_primeira_prescricao,
                                                                             'date') else dt_primeira_prescricao

                    # Isso significa que o médico prescreveu ANTES de ter CRM registrado = PROBLEMA!
                    if dt_primeira_prescricao and data_inscricao > data_primeira:
                        # Usa formato vermelho COM formato de data (célula com problema)
                        ws.write(row_top, col, dt_inscricao_crm, fmt_alerta_vermelho_data)
                    else:
                        ws.write(row_top, col, dt_inscricao_crm, f_celula_data)
                except (AttributeError, TypeError):
                    # Se houver erro na conversão, exibe normalmente
                    ws.write(row_top, col, dt_inscricao_crm, f_celula_data)
            else:
                ws.write(row_top, col, "Inexistente", fmt_alerta_vermelho)
            col += 1

            ws.write(row_top, col, nu_prescricoes, f_celula_numero);
            col += 1
            ws.write(row_top, col, vl_total, f_celula_moeda);
            col += 1
            ws.write(row_top, col, pct_part, f_celula_pct);
            col += 1
            ws.write(row_top, col, pct_acum, f_celula_pct);
            col += 1

            if presc_dia > LIMITE_ROBO_DIA:
                ws.write(row_top, col, presc_dia, fmt_alerta_vermelho)
            elif presc_dia > 20:
                ws.write(row_top, col, presc_dia, fmt_alerta_laranja)
            else:
                ws.write(row_top, col, presc_dia, f_celula_decimal)
            col += 1

            # Colunas de rede
            ws.write(row_top, col, presc_total_br, f_celula_numero);
            col += 1

            # Presc/Dia BR (destacar se alto - célula com problema)
            if presc_dia_br > LIMITE_ROBO_DIA:
                ws.write(row_top, col, presc_dia_br, fmt_alerta_vermelho)

            else:
                ws.write(row_top, col, presc_dia_br, f_celula_decimal)
            col += 1

            # Nº Farmácias (destacar em roxo se >20 - célula com problema)
            if qtd_estabelecimentos > LIMITE_MULTI_FARMACIA:
                ws.write(row_top, col, qtd_estabelecimentos, f_celula_center)
            else:
                ws.write(row_top, col, qtd_estabelecimentos, f_celula_center)
            col += 1

            ws.write(row_top, col, pct_aqui_vs_total, f_celula_pct);
            col += 1

            # Flags
            if flag_robo == 1:
                ws.write(row_top, col, "SIM", fmt_alerta_magenta)
            else:
                ws.write(row_top, col, "-", f_celula_center)
            col += 1

            if flag_robo_rede == 1:
                ws.write(row_top, col, "SIM", fmt_alerta_roxo)
            else:
                ws.write(row_top, col, "-", f_celula_center)
            col += 1

            if qtd_estabelecimentos > LIMITE_MULTI_FARMACIA:
                ws.write(row_top, col, qtd_estabelecimentos, fmt_alerta_roxo)
            else:
                ws.write(row_top, col, "-", f_celula_center)
            col += 1

            if alerta2:
                ws.write(row_top, col, "SIM", fmt_alerta_laranja)
            else:
                ws.write(row_top, col, "-", f_celula_center)
            col += 1

            # NOVO: EXCLUSIVO?
            if is_exclusivo:
                ws.write(row_top, col, "SIM", fmt_alerta_laranja)
            else:
                ws.write(row_top, col, "-", f_celula_center)
            col += 1

            # Detalhe Geo (alerta5 - célula com problema se presente)
            if alerta_geo:
                ws.write(row_top, col, "SIM", fmt_alerta_azul_geo)
            else:
                ws.write(row_top, col, "-", f_celula_center)

            row_top += 1
    else:
        ws.merge_range(row_top, 1, row_top, 19, "Nenhum prescritor encontrado para este CNPJ.", fmt_celula)
        row_top += 1

    # =================================================================
    # ALERTAS IDENTIFICADOS
    # =================================================================

    row_alertas = row_top + 2

    # Verifica se há alertas
    tem_alertas = (qtd_crm_inv > 0 or qtd_robos > 0 or qtd_robos_rede > 0 or
                   qtd_alerta_geo > 0 or qtd_multi_farmacia > 0 or qtd_tempo_concentrado > 0 or
                   qtd_prescricao_antes_registro > 0 or qtd_exclusivos > 0)

    if tem_alertas:
        ws.merge_range(row_alertas, 1, row_alertas, 7, "⚠️ ALERTAS IDENTIFICADOS", fmt_secao_titulo)
        row_alertas += 2

        fmt_alerta_titulo = wb.add_format({
            'bold': True, 'font_size': 10, 'font_color': COR_VERMELHO,
            'align': 'left', 'valign': 'vcenter'
        })
        fmt_alerta_titulo_rede = wb.add_format({
            'bold': True, 'font_size': 10, 'font_color': COR_ROXO,
            'align': 'left', 'valign': 'vcenter'
        })
        fmt_alerta_titulo_laranja = wb.add_format({
            'bold': True, 'font_size': 10, 'font_color': COR_LARANJA,
            'align': 'left', 'valign': 'vcenter'
        })
        fmt_alerta_texto = wb.add_format({
            'font_size': 9, 'font_color': '#333333',
            'align': 'left', 'valign': 'vcenter', 'text_wrap': True, 'indent': 1
        })
        fmt_alerta_detalhe = wb.add_format({
            'font_size': 10, 'font_color': '#333333',
            'align': 'left', 'valign': 'top', 'text_wrap': True, 'indent': 2
            # Sem bg_color = fundo branco padrão
        })
        fmt_alerta_titulo_azul = wb.add_format({
            'bold': True, 'font_size': 10,
            'font_color': COR_AZUL_GEO,  # Usando a cor azul que definimos antes
            'align': 'left', 'valign': 'vcenter'
        })

        fmt_alerta_titulo_magenta = wb.add_format({
            'bold': True, 'font_size': 10,
            'font_color': COR_MAGENTA,
            'align': 'left', 'valign': 'vcenter'
        })

        # Alertas de anomalias diretas
        if qtd_crm_inv > 0:
            ws.write(row_alertas, 1, f"🔴 CRMs Inválidos: {qtd_crm_inv} médico(s) ({pct_crm_inv:.1f}% do total)",
                     fmt_alerta_titulo)
            row_alertas += 1
            crms_invalidos = [p.get('id_medico', '') for p in top20_prescritores if p.get('flag_crm_invalido', 0) == 1]
            if crms_invalidos:
                ws.merge_range(row_alertas, 1, row_alertas, 7, f"      • CRMs {', '.join(crms_invalidos[:10])}",
                               fmt_alerta_texto)
            row_alertas += 2

        if qtd_robos > 0:
            ws.merge_range(row_alertas, 1, row_alertas, 7,
                           f"🔴 >30 Prescrições por dia neste CNPJ: {qtd_robos} médico(s)",
                           fmt_alerta_titulo_magenta)
            row_alertas += 1
            robos = [f"{p.get('id_medico', '')} ({p.get('nu_prescricoes_dia', 0):.1f}/dia)"
                     for p in top20_prescritores if p.get('flag_robo', 0) == 1]
            if robos:
                ws.merge_range(row_alertas, 1, row_alertas, 7, f"      • CRMs {', '.join(robos[:5])}", fmt_alerta_texto)
            row_alertas += 2

        # Alertas de rede
        if qtd_robos_rede > 0:
            ws.merge_range(row_alertas, 1, row_alertas, 7,
                           f"🔴 >30 Prescrições por dia em todos os estabelecimentos em que atuam: {qtd_robos_rede} médico(s).",
                           fmt_alerta_titulo_rede)
            row_alertas += 1
            robos_rede = [f"{p.get('id_medico', '')} ({p.get('prescricoes_dia_total_brasil', 0):.1f}/dia)"
                          for p in top20_prescritores if p.get('flag_robo_oculto', 0) == 1]
            if robos_rede:
                ws.merge_range(row_alertas, 1, row_alertas, 7, f"      • CRMs {', '.join(robos_rede[:5])}",
                               fmt_alerta_texto)
            row_alertas += 2

        if qtd_tempo_concentrado > 0:
            ws.write(row_alertas, 1,
                     f"🔴 Todas as Prescrições em Período muito curto: {qtd_tempo_concentrado} médico(s).",
                     fmt_alerta_titulo_laranja)
            row_alertas += 1

            # Lista dos CRMs com tempo concentrado
            prescritores_com_tempo_conc = [
                p for p in top20_prescritores
                if p.get('alerta2_tempo_concentrado', '') or p.get('alerta2', '')
            ]

            for p in prescritores_com_tempo_conc:
                id_medico = p.get('id_medico', '')
                alerta2 = p.get('alerta2_tempo_concentrado', '') or p.get('alerta2', '')

                # Escreve o detalhe do alerta (pode ocupar múltiplas linhas se necessário)
                ws.merge_range(row_alertas, 1, row_alertas, 7,
                               f"      • CRM {id_medico}: {alerta2}",
                               fmt_alerta_detalhe)

            row_alertas += 2  # Espaço extra após os detalhes

        if qtd_prescricao_antes_registro > 0:
            ws.write(row_alertas, 1,
                     f"🔴 Prescrição emitida antes do Registro do CRM: {qtd_prescricao_antes_registro} médico(s).",
                     fmt_alerta_titulo)
            row_alertas += 1
            presc_antes_reg = [p.get('id_medico', '') for p in top20_prescritores
                               if p.get('flag_prescricao_antes_registro', 0) == 1]
            if presc_antes_reg:
                ws.merge_range(row_alertas, 1, row_alertas, 7, f"      • CRMs {', '.join(presc_antes_reg[:5])}",
                               fmt_alerta_texto)
            row_alertas += 2

        if qtd_multi_farmacia > 0:
            ws.write(row_alertas, 1,
                     f"🔴 Médicos com prescrições em >20 estabelecimentos: {qtd_multi_farmacia} médico(s). ({pct_multi_farmacia:.1f}%)",
                     fmt_alerta_titulo_rede)
            row_alertas += 1
            multi_farm_list = [
                f"{p.get('id_medico', '')} ({p.get('qtd_estabelecimentos_atua', 0)} farm.)"
                for p in top20_prescritores
                if int(_get_valor(p, 'qtd_estabelecimentos_atua')) > LIMITE_MULTI_FARMACIA
            ]

            if multi_farm_list:
                ws.merge_range(row_alertas, 1, row_alertas, 7, f"   No Top 20: {', '.join(multi_farm_list[:5])}",
                               fmt_alerta_texto)
            row_alertas += 2

        # NOVO: ALERTA DE EXCLUSIVIDADE
        if qtd_exclusivos > 0:
            ws.write(row_alertas, 1,
                     f"🔴 Médicos com atuação Exclusiva nesta Farmácia (100% do volume): {qtd_exclusivos} médico(s).",
                     fmt_alerta_titulo_laranja)
            row_alertas += 1
            exclusivos_list = [
                f"{p.get('id_medico', '')}"
                for p in top20_prescritores
                if int(_get_valor(p, 'qtd_estabelecimentos_atua')) == 1
            ]
            if exclusivos_list:
                ws.merge_range(row_alertas, 1, row_alertas, 7, f"      • CRMs {', '.join(exclusivos_list[:10])}",
                               fmt_alerta_texto)
            row_alertas += 2

        if qtd_alerta_geo > 0:
            ws.write(row_alertas, 1,
                     f"🔴 CRMs localizados em estabelecimentos > 400km de distância: {qtd_alerta_geo} médico(s).",
                     fmt_alerta_titulo_azul)
            row_alertas += 1

            # 1. Filtra os prescritores que têm o alerta geográfico
            prescritores_geo = [
                p for p in top20_prescritores
                if p.get('alerta_geografico', '') or p.get('alerta5', '') or p.get('alerta5_geografico', '')
            ]

            if prescritores_geo:

                for p in prescritores_geo:
                    id_medico = p.get('id_medico', '')
                    # Pega o texto completo do alerta
                    texto_alerta = p.get('alerta_geografico', '') or p.get('alerta5', '') or p.get('alerta5_geografico',
                                                                                                   '')

                    # Escreve o texto usando MERGE para ocupar a largura e quebrar linha
                    # Usamos 'fmt_alerta_detalhe' (que definimos na rodada anterior)
                    ws.merge_range(row_alertas, 1, row_alertas, 7,
                                   f"      • {id_medico}: {texto_alerta}",
                                   fmt_alerta_detalhe)

                    # Cálculo simples para ajustar altura da linha (Wrap Text)
                    # Considera aprox 90 caracteres por linha
                    altura_estimada = max(15, (len(texto_alerta) // 70 + 1) * 18)
                    ws.set_row(row_alertas, altura_estimada)

                    row_alertas += 1

            row_alertas += 1  # Espaço extra após o bloco

    # =================================================================
    # AJUSTE DE LARGURA DAS COLUNAS
    # =================================================================
    ws.set_column('A:A', 2)  # Margem
    ws.set_column('B:B', 24)  # # (Ranking) / INDICADOR
    ws.set_column('C:C', 14)  # CRM/UF
    ws.set_column('D:D', 12)  # 1ª Prescrição
    ws.set_column('E:E', 14)  # Data Reg. CRM (aumentado para caber "Inexistente")
    ws.set_column('F:F', 12)  # Prescrições
    ws.set_column('G:G', 14)  # Valor
    ws.set_column('H:H', 10)  # % Part
    ws.set_column('I:I', 10)  # % Acum
    ws.set_column('J:J', 10)  # Presc/Dia
    ws.set_column('K:K', 14)  # Presc Total BR
    ws.set_column('L:L', 11)  # Presc/Dia BR
    ws.set_column('M:M', 11)  # Nº Farmácias
    ws.set_column('N:N', 10)  # % Aqui
    ws.set_column('O:O', 10)  # >30 Aqui?
    ws.set_column('P:P', 10)  # >30 Rede?
    ws.set_column('Q:Q', 10)  # Multi-Farm
    ws.set_column('R:R', 11)  # Tempo Conc.
    ws.set_column('S:S', 10)  # Exclusivo?
    ws.set_column('T:T', 10)  # Detalhe Geo (Ajustado)

    ws.freeze_panes(6, 0)

    logging.info(f"Aba 'Análise de CRMs' v5.0 gerada com sucesso para CNPJ {cnpj}")
