"""
aba_regiao.py
=============
Módulo responsável por buscar e renderizar a aba 'Região de Saúde' no
relatório Excel do Sentinela.

Funções exportadas:
    buscar_resumo_municipios(cursor, id_regiao) -> list[dict]
    buscar_farmacias_regiao(cursor, id_regiao) -> list[dict]
    gerar_aba_regiao(wb, cursor, id_regiao, nome_reg, cnpj_analise=None, municipio_analise=None)
"""

import logging
from datetime import datetime, date

DATA_FINAL_ANALISE = date(2024, 12, 10)

def buscar_resumo_municipios(cursor, id_regiao):
    """
    Busca o resumo de municípios da Região de Saúde: população, farmácias e densidade.
    """
    try:
        sql = """
            SELECT 
                MAX(uf) as uf,
                municipio,
                MAX(populacao) as populacao,
                COUNT(*) as qtd_farmacias,
                CAST(MAX(populacao) * 1.0 / COUNT(*) AS DECIMAL(18,2)) as densidade
            FROM temp_CGUSC.fp.matriz_risco_consolidada
            WHERE id_regiao_saude = ?
            GROUP BY municipio
            ORDER BY municipio
        """
        cursor.execute(sql, (id_regiao,))
        colunas = [column[0] for column in cursor.description]
        return [dict(zip(colunas, row)) for row in cursor.fetchall()]
    except Exception as e:
        logging.error(f"⚠️ Erro ao buscar resumo de municípios: {e}")
        return []

def buscar_farmacias_regiao(cursor, id_regiao):
    """
    Busca todas as farmácias da Região de Saúde ordenadas por Score de Risco.
    """
    try:
        sql = """
            SELECT 
                M.rank_regiao_saude,
                M.razaoSocial,
                M.municipio,
                M.SCORE_RISCO_FINAL,
                M.CLASSIFICACAO_RISCO,
                M.cnpj,
                ISNULL(S.valor_sem_comprovacao, 0) as valor_sem_comprovacao,
                ISNULL(S.valor_vendas, 0) as valor_vendas,
                D.dataFinalDadosMovimentacao as data_ultima_venda
            FROM temp_CGUSC.fp.matriz_risco_consolidada M
            LEFT JOIN temp_CGUSC.fp.resultado_sentinela_2015_2024 S 
                ON S.cnpj = M.cnpj
            LEFT JOIN temp_CGUSC.fp.dados_farmacia D
                ON M.cnpj = D.cnpj
            WHERE M.id_regiao_saude = ?
            ORDER BY M.SCORE_RISCO_FINAL DESC
        """
        cursor.execute(sql, (id_regiao,))
        colunas = [column[0] for column in cursor.description]
        return [dict(zip(colunas, row)) for row in cursor.fetchall()]
    except Exception as e:
        logging.error(f"⚠️ Erro ao buscar farmácias da região: {e}")
        return []

def gerar_aba_regiao(wb, cursor, id_regiao, nome_reg, cnpj_analise=None, municipio_analise=None):
    """
    Gera a aba de análise regional no relatório Excel.
    Exibe o ranking das farmácias de maior risco na mesma Região de Saúde.
    """
    if not id_regiao:
        logging.warning("ID da Região de Saúde não fornecido. Aba 'Região de Saúde' não será gerada.")
        return

    ws = wb.add_worksheet('Região de Saúde')
    ws.hide_gridlines(2)
    ws.ignore_errors({'number_stored_as_text': 'B6:B1000'})  # Remove o alerta verde do Excel no CNPJ

    # ── Paleta de cores ──────────────────────────────────────────────────────
    COR_AZUL_ESCURO = '#1F4E78'
    COR_CINZA_CLARO = '#F2F2F2'
    COR_VERMELHO    = '#C00000'
    COR_AMARELO     = '#FFC000'
    COR_VERDE       = '#548235'

    # ── Formatos ─────────────────────────────────────────────────────────────
    fmt_titulo = wb.add_format({
        'bold': True, 'font_size': 18, 'font_color': COR_AZUL_ESCURO,
        'align': 'left', 'valign': 'vcenter'
    })
    fmt_subtitulo = wb.add_format({
        'font_size': 10, 'font_color': '#555555', 'align': 'left', 'valign': 'vcenter'
    })
    fmt_header_secao = wb.add_format({
        'bold': True, 'font_size': 11, 'bg_color': COR_AZUL_ESCURO, 'font_color': 'white',
        'align': 'left', 'valign': 'vcenter', 'indent': 1, 'border': 1
    })
    fmt_th = wb.add_format({
        'bold': True, 'font_size': 9, 'bg_color': COR_CINZA_CLARO, 'font_color': 'black',
        'align': 'center', 'valign': 'vcenter', 'border': 1
    })
    fmt_th_esq = wb.add_format({
        'bold': True, 'font_size': 9, 'bg_color': COR_CINZA_CLARO, 'font_color': 'black',
        'align': 'left', 'valign': 'vcenter', 'border': 1, 'indent': 1
    })
    fmt_celula = wb.add_format({
        'font_size': 9, 'align': 'left', 'valign': 'vcenter', 'border': 1, 'indent': 1
    })
    fmt_celula_center = wb.add_format({
        'font_size': 9, 'align': 'center', 'valign': 'vcenter', 'border': 1
    })
    fmt_celula_moeda = wb.add_format({
        'font_size': 9, 'align': 'right', 'valign': 'vcenter', 'border': 1,
        'num_format': 'R$ #,##0.00'
    })
    fmt_celula_pct = wb.add_format({
        'font_size': 9, 'align': 'center', 'valign': 'vcenter', 'border': 1,
        'num_format': '0.00%'
    })
    fmt_celula_score = wb.add_format({
        'font_size': 10, 'bold': True, 'align': 'center', 'valign': 'vcenter', 'border': 1,
        'num_format': '0.00'
    })
    fmt_link_doc = wb.add_format({
        'font_size': 9, 'font_color': 'blue', 'underline': True, 
        'align': 'left', 'valign': 'top'
    })
    fmt_seta = wb.add_format({
        'font_size': 14, 'bold': True, 'font_color': COR_VERMELHO,
        'align': 'right', 'valign': 'vcenter'
    })

    # ── Cabeçalho ────────────────────────────────────────────────────────────
    ws.write('B2', "ANÁLISE REGIONAL DE RISCO", fmt_titulo)
    ws.write('B3', f"Região de Saúde: {nome_reg} (ID: {id_regiao})", fmt_subtitulo)
    ws.write_url('B4', 'https://cgu-sc.github.io/sentinela/', fmt_link_doc, string='📘 Acesse a Documentação')

    # ── Buscar Dados ─────────────────────────────────────────────────────────
    resumo_mun = buscar_resumo_municipios(cursor, id_regiao)
    farmacias = buscar_farmacias_regiao(cursor, id_regiao)
    
    if not farmacias:
        ws.write('B6', "Nenhuma farmácia encontrada nesta região para comparação.", fmt_subtitulo)
        return

    # ── Resumo de Municípios ─────────────────────────────────────────────────
    row = 6
    ws.merge_range(row, 1, row, 5, f'MUNICÍPIOS DA REGIÃO "{nome_reg.upper()}"', fmt_header_secao)
    row += 1
    
    headers_resumo = ["UF", "Município", "População", "Qtd. Farmácias", "Habitantes/Farmácia"]
    for c, h in enumerate(headers_resumo):
        ws.write(row, c + 1, h, fmt_th)
    row += 1

    for mun in resumo_mun:
        # --- LÓGICA DA SETA NO MUNICÍPIO ---
        if municipio_analise and str(mun.get('municipio', '')).upper().strip() == str(municipio_analise).upper().strip():
            ws.write(row, 0, "►", fmt_seta)
            
        ws.write(row, 1, mun['uf'], fmt_celula_center)
        ws.write(row, 2, mun['municipio'], fmt_celula)
        ws.write(row, 3, mun['populacao'], fmt_celula_center)
        ws.write(row, 4, mun['qtd_farmacias'], fmt_celula_center)
        ws.write(row, 5, mun['densidade'], fmt_celula_center)
        row += 1

    # ── Linha de Totalizador ────────────────────────────────────────────────
    total_pop = sum(m.get('populacao', 0) for m in resumo_mun)
    total_far = sum(m.get('qtd_farmacias', 0) for m in resumo_mun)
    total_mun = len(resumo_mun)
    dens_reg = (total_pop / total_far) if total_far > 0 else 0
    
    ws.write(row, 1, "TOTAL", fmt_th)
    ws.write(row, 2, f"{total_mun} Municípios", fmt_th_esq)
    ws.write(row, 3, total_pop, fmt_th)
    ws.write(row, 4, total_far, fmt_th)
    ws.write(row, 5, round(dens_reg, 2), fmt_th)
    row += 2  # Espaço entre as tabelas

    # ── Tabela Completa de Farmácias ─────────────────────────────────────────
    ws.merge_range(row, 1, row, 11, f'RANKING DE RISCO DOS ESTABELECIMENTOS NA REGIÃO "{nome_reg.upper()}"', fmt_header_secao)
    row += 1
    
    # Cabeçalhos
    headers_principais = ["CNPJ", "Razão Social", "Município", "Score", "Classificação", "Valor s/ Comp.", "Faturamento"]
    for c, h in enumerate(headers_principais):
        ws.write(row, c + 1, h, fmt_th)
    ws.merge_range(row, 8, row, 9, "% s/ Comp.", fmt_th)
    ws.write(row, 10, "Última Venda", fmt_th)
    ws.write(row, 11, "Conexão", fmt_th)
    row += 1
    
    for farm in farmacias:
        ws.set_row(row, 20)
        
        # --- LÓGICA DA SETA ---
        cnpj_item = str(farm.get('cnpj', '')).strip()
        eh_eu = (cnpj_item == str(cnpj_analise).strip())
        if eh_eu:
            ws.write(row, 0, "►", fmt_seta)
        
        # Formato de Score baseado na classificação
        score = float(farm.get('SCORE_RISCO_FINAL', 0))
        classif = str(farm.get('CLASSIFICACAO_RISCO', ''))
        
        fmt_score_local = fmt_celula_score
        if 'CRÍTICO' in classif.upper() or 'CRITICO' in classif.upper():
            fmt_score_local = wb.add_format({
                'font_size': 10, 'bold': True, 'align': 'center', 'valign': 'vcenter', 
                'border': 1, 'num_format': '0.00', 'font_color': COR_VERMELHO, 'bg_color': '#F4B0B0'
            })
        elif 'ALTO' in classif.upper():
            fmt_score_local = wb.add_format({
                'font_size': 10, 'bold': True, 'align': 'center', 'valign': 'vcenter', 
                'border': 1, 'num_format': '0.00', 'font_color': COR_VERMELHO, 'bg_color': '#FFEBEE'
            })
        elif 'MÉDIO' in classif.upper() or 'MEDIO' in classif.upper():
            fmt_score_local = wb.add_format({
                'font_size': 10, 'bold': True, 'align': 'center', 'valign': 'vcenter', 
                'border': 1, 'num_format': '0.00', 'font_color': '#9C5700', 'bg_color': '#FFF2CC'
            })

        ws.write(row, 1, farm['cnpj'], fmt_celula_center)
        ws.write(row, 2, farm['razaoSocial'], fmt_celula)
        ws.write(row, 3, farm['municipio'], fmt_celula)
        ws.write(row, 4, score, fmt_celula_score)
        ws.write(row, 5, classif, fmt_score_local)
        
        v_sem = float(farm.get('valor_sem_comprovacao', 0))
        v_tot = float(farm.get('valor_vendas', 0))
        pct = (v_sem / v_tot) if v_tot > 0 else 0
        
        # --- LÓGICA DE CONEXÃO (STATUS) ---
        dt = farm.get('data_ultima_venda')
        status_texto = "-"
        fmt_status = fmt_celula_center
        
        if dt:
            if isinstance(dt, str):
                try: dt = datetime.strptime(dt, '%Y-%m-%d').date()
                except: pass
            if isinstance(dt, datetime): dt = dt.date()
            
            if isinstance(dt, date):
                dias = (DATA_FINAL_ANALISE - dt).days
                if dias > 30:
                    status_texto = "INATIVA"
                    fmt_status = wb.add_format({
                        'font_size': 8, 'bold': True, 'align': 'center', 'valign': 'vcenter', 'border': 1,
                        'bg_color': '#FFC7CE', 'font_color': '#9C0006'
                    })
                else:
                    status_texto = "ATIVA"
                    fmt_status = wb.add_format({
                        'font_size': 8, 'bold': True, 'align': 'center', 'valign': 'vcenter', 'border': 1,
                        'bg_color': '#E2EFDA', 'font_color': '#006100'
                    })
        
        ws.write(row, 6, v_sem, fmt_celula_moeda)
        ws.write(row, 7, v_tot, fmt_celula_moeda)
        ws.merge_range(row, 8, row, 9, pct, fmt_celula_pct)
        
        dt_str = dt.strftime('%d/%m/%Y') if dt and hasattr(dt, 'strftime') else '-'
        ws.write(row, 10, dt_str, fmt_celula_center)
        ws.write(row, 11, status_texto, fmt_status)
        row += 1
        
    # ── Barra de Progresso (% s/ Comp.) ──────────────────────────────────────
    ws.conditional_format(row - len(farmacias), 8, row - 1, 9, {
        'type': 'data_bar', 'bar_color': '#63C384', 'bar_solid': True,
        'min_type': 'num', 'min_value': 0, 'max_type': 'num', 'max_value': 1, 'bar_no_border': True
    })

    # ── Mensagem de Contexto ─────────────────────────────────────────────────
    row += 1
    msg_contexto = (
        "Este ranking apresenta todas as farmácias da mesma Região de Saúde ordenadas pelo índice de anomalias. "
        "A posição relativa ajuda a identificar se o comportamento da farmácia analisada é um desvio local ou regional."
    )
    ws.merge_range(row, 1, row + 1, 11, msg_contexto, wb.add_format({
        'font_size': 9, 'italic': True, 'text_wrap': True, 'valign': 'top', 'font_color': '#777777'
    }))

    # ── Ajuste de Colunas ─────────────────────────────────────────────────────
    ws.set_column(0, 0, 3)   # Seta (Coluna A)
    ws.set_column(1, 1, 18)  # CNPJ
    ws.set_column(2, 2, 40)  # Razão Social
    ws.set_column(3, 3, 20)  # Município
    ws.set_column(4, 4, 10)  # Score
    ws.set_column(5, 5, 20)  # Classificação
    ws.set_column(6, 6, 15)  # Valor s/ Comp.
    ws.set_column(7, 7, 15)  # Faturamento
    ws.set_column(8, 9, 8)   # % s/ Comp. (Duas colunas)
    ws.set_column(10, 10, 12) # Última Venda
    ws.set_column(11, 11, 12) # Conexão
