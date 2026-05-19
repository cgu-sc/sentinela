from datetime import date
from decimal import Decimal
from typing import Any

from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.shared import Inches, Pt

from .nota_tecnica_docx_utils import (
    _cell_bg,
    _footnote_ref,
    _format_block_footnote,
    _format_block_title,
    _keep_small_table_together,
    _run,
    _set_table_fixed_widths,
)
from .nota_tecnica_formatters import _format_cpf_cnpj, _format_decimal_pt


def _format_quadro_title(paragraph, *, space_before: float = 16, space_after: float = 8):
    _format_block_title(
        paragraph,
        space_before=space_before,
        space_after=space_after,
        alignment=WD_ALIGN_PARAGRAPH.CENTER,
    )


def _format_quadro_footnote(paragraph, *, space_before: float = 5, space_after: float = 18):
    _format_block_footnote(
        paragraph,
        space_before=space_before,
        space_after=space_after,
        alignment=WD_ALIGN_PARAGRAPH.CENTER,
    )


def _add_quadro_socios_volume_atipico(doc, socios_volume_atipico: list[dict[str, Any]]):
    """Adiciona quadro com ingressos societarios proximos a aumentos atipicos."""
    if not socios_volume_atipico:
        return

    p_title = doc.add_paragraph()
    _format_quadro_title(p_title)
    _run(
        p_title,
        'Quadro 06 - Ingressos societários próximos a semestres com aumento atípico das transferências',
        color='0F172A',
        size=9,
        bold=True,
    )

    table = doc.add_table(rows=len(socios_volume_atipico) + 1, cols=5)
    table.style = 'Table Grid'
    _set_table_fixed_widths(table, [Inches(1.9), Inches(1.25), Inches(1.25), Inches(1.0), Inches(1.7)])

    headers = [
        'Sócio',
        'Entrada na sociedade',
        'Semestre do aumento',
        'Crescimento',
        'Distância temporal',
    ]
    for idx, header in enumerate(headers):
        para = table.rows[0].cells[idx].paragraphs[0]
        para.alignment = WD_ALIGN_PARAGRAPH.CENTER
        _run(para, header, color='0F172A', size=8, bold=True)
        _cell_bg(table.rows[0].cells[idx], 'E2E8F0')

    for row_idx, item in enumerate(socios_volume_atipico, start=1):
        cells = table.rows[row_idx].cells
        distancia = int(item.get("distancia_semestres") or 0)
        if distancia == 0:
            distancia_txt = 'Mesmo semestre'
        elif distancia == 1:
            distancia_txt = '1 semestre após a entrada'
        else:
            distancia_txt = f'{distancia} semestres após a entrada'

        taxa = item.get("taxa_crescimento_pct")
        taxa_txt = f'+{_format_decimal_pt(float(taxa), 1)}%' if taxa is not None else '-'
        entrada_txt = item.get("entrada_txt") or '—'
        if entrada_txt != '—':
            entrada_txt = entrada_txt[:1].upper() + entrada_txt[1:]

        values = [
            item.get("nome_socio") or '—',
            entrada_txt,
            item.get("semestre_fmt") or '—',
            taxa_txt,
            distancia_txt,
        ]
        for col_idx, value in enumerate(values):
            para = cells[col_idx].paragraphs[0]
            para.alignment = WD_ALIGN_PARAGRAPH.CENTER if col_idx in (1, 2, 3, 4) else WD_ALIGN_PARAGRAPH.LEFT
            _run(para, value, color='0F172A', size=8, bold=col_idx == 3 and taxa is not None)

    for row in table.rows:
        for cell in row.cells:
            for p in cell.paragraphs:
                p.paragraph_format.space_before = Pt(1)
                p.paragraph_format.space_after = Pt(1)

    p_foot = doc.add_paragraph()
    _format_quadro_footnote(p_foot)
    _run(
        p_foot,
        'Fonte: Sistema Sentinela, a partir do quadro societário cadastral e da evolução semestral das transferências do PFPB. A distância temporal considera o mesmo semestre de entrada e até dois semestres posteriores.',
        color='64748B',
        size=8,
    )
    _keep_small_table_together(p_title, table, [p_foot])


def _add_quadro_comparativo_regional(doc, regional_comp: dict[str, Any], cnpj_data: dict, periodo_txt: str):
    """Adiciona quadro compacto comparando a farmacia auditada com a mediana regional."""
    p_title = doc.add_paragraph()
    _format_quadro_title(p_title)
    _run(
        p_title,
        'Quadro 03 - Comparativo do percentual de vendas sem comprovação da farmácia auditada em relação à Região de Saúde',
        color='0F172A',
        size=9,
        bold=True,
    )

    table = doc.add_table(rows=5, cols=2)
    table.style = 'Table Grid'
    _set_table_fixed_widths(table, [Inches(4.7), Inches(2.4)])

    hdr_cells = table.rows[0].cells
    _run(hdr_cells[0].paragraphs[0], 'Métrica', bold=True)
    _run(hdr_cells[1].paragraphs[0], 'Valor', bold=True)
    for cell in hdr_cells:
        cell.paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.CENTER
        _cell_bg(cell, 'E2E8F0')

    rows = [
        ('Percentual da farmácia auditada', f'{_format_decimal_pt(float(cnpj_data["percValSemComp"]), 2)}%'),
        ('Mediana regional', f'{_format_decimal_pt(regional_comp["mediana_regional"], 2)}%'),
        ('Multiplicador sobre a mediana regional', f'{_format_decimal_pt(regional_comp["multiplicador"], 2)} vezes'),
        ('Farmácias consideradas na região', f'{regional_comp["qtd_farmacias"]}'),
    ]

    for idx, (label, value) in enumerate(rows, start=1):
        cells = table.rows[idx].cells
        _run(cells[0].paragraphs[0], label, color='475569', size=9)
        value_para = cells[1].paragraphs[0]
        value_para.alignment = WD_ALIGN_PARAGRAPH.CENTER
        _run(value_para, value, color='0F172A', size=9, bold=True)

    for row in table.rows:
        for cell in row.cells:
            for p in cell.paragraphs:
                p.paragraph_format.space_before = Pt(2)
                p.paragraph_format.space_after = Pt(2)

    p_foot = doc.add_paragraph()
    _format_quadro_footnote(p_foot)
    _run(p_foot, f'Fonte: Sistema Sentinela, com base no SAV/PFPB e em NF-e, no período analisado ({periodo_txt}).', color='64748B', size=8)
    _keep_small_table_together(p_title, table, [p_foot])


def _add_quadro_gtins_sem_comprovacao(doc, razao_social: str, cnpj_fmt: str, gtin_comp: dict[str, Any], periodo_txt: str):
    """Adiciona quadro com todos os GTINs com vendas sem comprovacao no periodo."""
    p_title = doc.add_paragraph()
    _format_quadro_title(p_title)
    _run(
        p_title,
        f'Quadro 04 - Relação de medicamentos supostamente distribuídos pela Farmácia {razao_social} (CNPJ {cnpj_fmt}) sem estoque amparado em notas fiscais de aquisição, no período de {periodo_txt}.',
        color='0F172A',
        size=9,
        bold=True,
    )

    rows_data = gtin_comp["rows"]
    table = doc.add_table(rows=len(rows_data) + 2, cols=4)
    table.style = 'Table Grid'
    _set_table_fixed_widths(table, [Inches(1.05), Inches(3.65), Inches(1.1), Inches(1.3)])

    headers = [
        'GTIN',
        'Descrição',
        'Quantidade de medicamentos sem comprovação',
        'Valor de vendas sem comprovação (R$)',
    ]
    for idx, header in enumerate(headers):
        para = table.rows[0].cells[idx].paragraphs[0]
        para.alignment = WD_ALIGN_PARAGRAPH.CENTER
        _run(para, header, color='0F172A', size=8, bold=True)
        _cell_bg(table.rows[0].cells[idx], 'E2E8F0')

    for row_idx, item in enumerate(rows_data, start=1):
        cells = table.rows[row_idx].cells
        _run(cells[0].paragraphs[0], item["gtin"], color='0F172A', size=8)
        _run(cells[1].paragraphs[0], item["descricao"], color='0F172A', size=8)
        cells[2].paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.CENTER
        _run(cells[2].paragraphs[0], f'{item["qtd_sem_comprovacao"]:,}'.replace(',', '.'), color='0F172A', size=8)
        cells[3].paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.RIGHT
        _run(cells[3].paragraphs[0], f'R$ {_format_decimal_pt(item["valor_sem_comprovacao"], 2)}', color='0F172A', size=8)

    total_cells = table.rows[-1].cells
    total_cells[0].merge(total_cells[1])
    _run(total_cells[0].paragraphs[0], 'TOTAIS', color='0F172A', size=8, bold=True)
    total_cells[0].paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.RIGHT
    total_cells[2].paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.CENTER
    _run(total_cells[2].paragraphs[0], f'{gtin_comp["total_qtd"]:,}'.replace(',', '.'), color='0F172A', size=8, bold=True)
    total_cells[3].paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.RIGHT
    _run(total_cells[3].paragraphs[0], f'R$ {_format_decimal_pt(gtin_comp["total_valor"], 2)}', color='0F172A', size=8, bold=True)
    for cell in total_cells:
        _cell_bg(cell, 'F8FAFC')

    for row in table.rows:
        for cell in row.cells:
            for p in cell.paragraphs:
                p.paragraph_format.space_before = Pt(1)
                p.paragraph_format.space_after = Pt(1)

    p_foot = doc.add_paragraph()
    _format_quadro_footnote(p_foot)
    _run(p_foot, f'Fonte: informações sobre as dispensações informadas mensalmente pelas farmácias no Sistema Autorizador de Vendas do PFPB, no período de {periodo_txt}.', color='64748B', size=8)


def _add_quadro_evolucao_financeira(
    doc,
    razao_social: str,
    cnpj_fmt: str,
    evolucao_comp: dict[str, Any],
):
    """Adiciona quadro semestral de transferencias e vendas sem comprovacao."""
    periodo_semestres = (
        f'no {evolucao_comp["primeiro_semestre_fmt"]}'
        if evolucao_comp["primeiro_semestre"] == evolucao_comp["ultimo_semestre"]
        else f'do {evolucao_comp["primeiro_semestre_fmt"]} ao {evolucao_comp["ultimo_semestre_fmt"]}'
    )
    p_title = doc.add_paragraph()
    _format_quadro_title(p_title)
    _run(
        p_title,
        f'Quadro 05 - Evolução semestral dos recursos recebidos do Ministério da Saúde e das “vendas sem comprovação” da Farmácia {razao_social} (CNPJ {cnpj_fmt}), {periodo_semestres}.',
        color='0F172A',
        size=9,
        bold=True,
    )

    rows_data = evolucao_comp["rows"]
    table = doc.add_table(rows=len(rows_data) + 2, cols=6)
    table.style = 'Table Grid'
    _set_table_fixed_widths(table, [Inches(1.05), Inches(1.2), Inches(1.2), Inches(1.3), Inches(1.05), Inches(1.3)])

    headers = [
        'Semestre',
        'Total',
        'Vendas regulares',
        'Vendas sem comprovação',
        '% sem comprovação',
        'Aumento atípico',
    ]
    for idx, header in enumerate(headers):
        para = table.rows[0].cells[idx].paragraphs[0]
        para.alignment = WD_ALIGN_PARAGRAPH.CENTER
        _run(para, header, color='0F172A', size=8, bold=True)
        _cell_bg(table.rows[0].cells[idx], 'E2E8F0')

    for row_idx, item in enumerate(rows_data, start=1):
        cells = table.rows[row_idx].cells
        has_aumento_atipico = item.get("volume_atipico") and item.get("taxa_crescimento_pct") is not None
        cells[0].paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.CENTER
        _run(cells[0].paragraphs[0], item.get("semestre_fmt") or item["semestre"], color='0F172A', size=8)
        for col_idx, key in enumerate(("total", "regular", "irregular"), start=1):
            cells[col_idx].paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.RIGHT
            _run(cells[col_idx].paragraphs[0], f'R$ {_format_decimal_pt(item[key], 2)}', color='0F172A', size=8)
        cells[4].paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.CENTER
        pct_color = '334155' if item["pct_irregular"] >= 50 else '0F172A'
        _run(
            cells[4].paragraphs[0],
            f'{_format_decimal_pt(item["pct_irregular"], 2)}%',
            color=pct_color,
            size=8,
            bold=item["pct_irregular"] >= 50,
        )
        cells[5].paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.CENTER
        if has_aumento_atipico:
            _run(
                cells[5].paragraphs[0],
                f'+{_format_decimal_pt(item["taxa_crescimento_pct"], 1)}%',
                color='991B1B',
                size=8,
                bold=True,
            )
        else:
            _run(cells[5].paragraphs[0], '-', color='64748B', size=8)
        if has_aumento_atipico:
            for cell in cells:
                _cell_bg(cell, 'FEE2E2')

    total_cells = table.rows[-1].cells
    _run(total_cells[0].paragraphs[0], 'TOTAL', color='0F172A', size=8, bold=True)
    total_cells[0].paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.CENTER
    totals = [
        f'R$ {_format_decimal_pt(evolucao_comp["total"], 2)}',
        f'R$ {_format_decimal_pt(evolucao_comp["regular"], 2)}',
        f'R$ {_format_decimal_pt(evolucao_comp["irregular"], 2)}',
        f'{_format_decimal_pt(evolucao_comp["pct_irregular"], 2)}%',
        '-',
    ]
    for col_idx, value in enumerate(totals, start=1):
        total_cells[col_idx].paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.RIGHT if col_idx < 4 else WD_ALIGN_PARAGRAPH.CENTER
        _run(total_cells[col_idx].paragraphs[0], value, color='0F172A', size=8, bold=True)
    for cell in total_cells:
        _cell_bg(cell, 'F8FAFC')

    for row in table.rows:
        for cell in row.cells:
            for p in cell.paragraphs:
                p.paragraph_format.space_before = Pt(1)
                p.paragraph_format.space_after = Pt(1)

    p_foot = doc.add_paragraph()
    _format_quadro_footnote(p_foot)
    _run(
        p_foot,
        'Fonte: Sistema Sentinela, aba “Evolução Financeira”, a partir das dispensações informadas no Sistema Autorizador de Vendas do PFPB e do levantamento de “vendas sem comprovação”.',
        color='64748B',
        size=8,
    )
    _keep_small_table_together(p_title, table, [p_foot])


def _add_quadro_medicamentos_aumento_atipico(doc, medicamentos_aumento_atipico: list[dict[str, Any]]):
    """Adiciona quadro com medicamentos que mais contribuiram para semestres atipicos."""
    if not medicamentos_aumento_atipico:
        return

    p_title = doc.add_paragraph()
    _format_quadro_title(p_title)
    _run(
        p_title,
        'Quadro 05-A - Medicamentos associados aos semestres com aumento atípico de volume financeiro',
        color='0F172A',
        size=9,
        bold=True,
    )

    table = doc.add_table(rows=len(medicamentos_aumento_atipico) + 1, cols=7)
    table.style = 'Table Grid'
    _set_table_fixed_widths(table, [Inches(0.95), Inches(0.85), Inches(2.0), Inches(0.7), Inches(0.85), Inches(1.0), Inches(0.75)])

    headers = [
        'Semestre',
        'GTIN',
        'Medicamento',
        'Valor anterior',
        'Valor no semestre',
        'Aumento no semestre',
        'Sem comprovação',
    ]
    for idx, header in enumerate(headers):
        para = table.rows[0].cells[idx].paragraphs[0]
        para.alignment = WD_ALIGN_PARAGRAPH.CENTER
        _run(para, header, color='0F172A', size=7, bold=True)
        _cell_bg(table.rows[0].cells[idx], 'E2E8F0')

    semestre_block_index: dict[str, int] = {}
    next_block_index = 0

    for row_idx, item in enumerate(medicamentos_aumento_atipico, start=1):
        cells = table.rows[row_idx].cells
        is_demais = bool(item.get("is_demais"))
        semestre_key = str(item.get("semestre_fmt") or item.get("semestre") or "")
        if semestre_key not in semestre_block_index:
            semestre_block_index[semestre_key] = next_block_index
            next_block_index += 1
        semestre_bg = 'E2E8F0' if semestre_block_index[semestre_key] % 2 == 0 else 'F8FAFC'
        text_color = '0F172A'
        increase_color = '334155'
        cells[0].paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.CENTER
        _run(cells[0].paragraphs[0], item["semestre_fmt"], color='334155', size=7, bold=True)
        _cell_bg(cells[0], semestre_bg)
        cells[1].paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.CENTER
        _run(cells[1].paragraphs[0], item["gtin"], color=text_color, size=7)
        _run(cells[2].paragraphs[0], item["descricao"], color=text_color, size=7)

        for col_idx, key in enumerate(("valor_anterior", "valor_atual"), start=3):
            cells[col_idx].paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.RIGHT
            _run(cells[col_idx].paragraphs[0], f'R$ {_format_decimal_pt(item[key], 2)}', color=text_color, size=7)

        cells[5].paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.RIGHT
        aumento_txt = f'R$ {_format_decimal_pt(item["aumento_valor"], 2)}'
        if item.get("aumento_relativo_pct") is not None:
            aumento_txt += f'\n(+{_format_decimal_pt(item["aumento_relativo_pct"], 1)}%)'
        _run(
            cells[5].paragraphs[0],
            aumento_txt,
            color=increase_color,
            size=7,
            bold=True,
        )
        cells[6].paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.RIGHT
        _run(cells[6].paragraphs[0], f'R$ {_format_decimal_pt(item["valor_sem_comprovacao"], 2)}', color=text_color, size=7)

    for row in table.rows:
        for cell in row.cells:
            for p in cell.paragraphs:
                p.paragraph_format.space_before = Pt(1)
                p.paragraph_format.space_after = Pt(1)

    p_foot = doc.add_paragraph()
    _format_quadro_footnote(p_foot)
    _run(
        p_foot,
        'Fonte: Sistema Sentinela, a partir da evolução mensal por GTIN. O percentual indicado no campo “Aumento no semestre” representa o crescimento do GTIN em relação ao semestre anterior e é exibido apenas quando o valor anterior é superior a R$ 1,00. GTINs com participação individual menor ou igual a 0,1% no aumento positivo do semestre são consolidados em uma linha agregada.',
        color='64748B',
        size=8,
    )
    _keep_small_table_together(p_title, table, [p_foot])


def _add_quadro_identificacao(doc, data: dict, capital_social: Decimal, periodo_txt: str):
    """Adiciona o Quadro 01 com as informações detalhadas da farmácia."""
    p_title = doc.add_paragraph()
    _format_quadro_title(p_title)
    _run(p_title, f"Quadro 01 - Informações detalhadas da Farmácia {data.get('razao_social') or ''}", color='0F172A', size=9, bold=True)
    _run(p_title, f"\n(CNPJ {data.get('cnpj_fmt') or ''})", color='475569', size=8)

    tbl = doc.add_table(rows=0, cols=2)
    tbl.style = 'Table Grid'
    tbl.autofit = False
    
    # Configura larguras (Total ~7.1 inches)
    col_label_w = Inches(2.2)
    col_value_w = Inches(4.9)
    _set_table_fixed_widths(tbl, [col_label_w, col_value_w])

    rows_to_add = [
        ('CNPJ', data.get('cnpj_fmt')),
        ('Razão Social', data.get('razao_social')),
        ('Nome Fantasia', data.get('nome_fantasia') or '—'),
        ('Natureza Jurídica', data.get('natureza_juridica') or '—'),
        ('CNAE Principal', f"{data.get('id_cnae_principal') or ''} - {data.get('cnae_principal') or ''}"),
        ('CNAE Secundária', f"{data.get('id_cnae_secundario') or ''} - {data.get('cnae_secundario') or ''}"),
        ('Abertura', data.get('data_abertura').strftime('%d/%m/%Y') if data.get('data_abertura') else '—'),
        ('Situação', data.get('situacao_rf') or '—'),
        ('Porte', data.get('porte_empresa') or '—'),
        ('Capital Social *', f"R$ {capital_social:,.2f}".replace(',', 'X').replace('.', ',').replace('X', '.')),
        ('Endereço', data.get('endereco_completo') or '—'),
        ('Bairro', data.get('bairro') or '—'),
        ('Município/UF', f"{data.get('municipio') or '—'} / {data.get('uf') or '—'}"),
        ('CEP', data.get('cep') or '—'),
        ('Telefone(s)', ' / '.join(filter(None, [data.get('telefone_1'), data.get('telefone_2')])) or '—'),
        ('E-mail', data.get('email') or '—'),
    ]

    for label, value in rows_to_add:
        row = tbl.add_row()
        row.cells[0].width = col_label_w
        row.cells[1].width = col_value_w
        
        # Estilo Rótulo
        c0 = row.cells[0]
        _cell_bg(c0, 'F8FAFC')
        p0 = c0.paragraphs[0]
        _run(p0, label, color='475569', size=8, bold=True)
        p0.paragraph_format.space_before = Pt(2)
        p0.paragraph_format.space_after = Pt(2)

        # Estilo Valor
        c1 = row.cells[1]
        p1 = c1.paragraphs[0]
        _run(p1, str(value) if value else '—', color='0F172A', size=8)
        p1.paragraph_format.space_before = Pt(2)
        p1.paragraph_format.space_after = Pt(2)

    # Nota de Rodapé do Quadro
    total_mov = Decimal(str(data.get('total_mov') or 0.0))
    cap_social_dec = Decimal(str(capital_social))
    relacao_pct = (total_mov / cap_social_dec * 100) if capital_social > 0 else 0
    vezes = (total_mov / cap_social_dec) if capital_social > 0 else 0
    
    p_nota = doc.add_paragraph()
    p_nota.paragraph_format.space_before = Pt(6)
    p_nota.paragraph_format.space_after = Pt(2)
    relacao_txt = f"{relacao_pct:,.2f}%".replace(',', 'X').replace('.', ',').replace('X', '.')
    total_mov_txt = f"R$ {total_mov:,.2f}".replace(',', 'X').replace('.', ',').replace('X', '.')
    _run(p_nota, f"* A relação do valor de vendas no âmbito do PFPB sobre o capital social é de {relacao_txt}, ou seja, ela recebeu ", color='475569', size=8)
    _run(p_nota, total_mov_txt, color='0F172A', size=8, bold=True)
    _run(p_nota, f" do Programa, no período de {periodo_txt}, o que corresponde ", color='475569', size=8)
    _run(p_nota, f"{vezes:,.1f} vezes".replace(',', 'X').replace('.', ',').replace('X', '.'), color='0F172A', size=8, bold=True)
    _run(p_nota, " o valor do seu capital social.", color='475569', size=8)

    p_fonte = doc.add_paragraph()
    _format_quadro_footnote(p_fonte)
    dt_extracao = data.get('data_processamento')
    dt_extracao_txt = dt_extracao.strftime('%d/%m/%Y') if dt_extracao else date.today().strftime('%d/%m/%Y')
    _run(p_fonte, f"Fonte: Dados registrados no Cadastro Nacional de Pessoas Jurídicas da RFB, com atualização em {dt_extracao_txt}.", color='94A3B8', size=7, italic=True)

    # ── Quadro Societário Atual ──────────────────────────────────────────
    p_socio_intro = doc.add_paragraph()
    p_socio_intro.paragraph_format.space_before = Pt(12)
    _run(p_socio_intro, f"O quadro societário atual da Farmácia {data.get('razao_social') or ''} conta com os seguintes sócios:", color='0F172A', size=10)

    if data.get('socios_ativos'):
        for s in data['socios_ativos']:
            p_s = doc.add_paragraph(style='List Bullet')
            p_s.paragraph_format.left_indent = Inches(0.5)
            cpf_fmt = _format_cpf_cnpj(s.cpf_cnpj_socio)
            entrada_fmt = s.data_entrada_sociedade.strftime('%d/%m/%Y') if s.data_entrada_sociedade else '—'
            _run(p_s, f"{s.nome_socio}, CPF: {cpf_fmt} (entrada em {entrada_fmt})", color='0F172A', size=10)
    else:
        p_s = doc.add_paragraph(style='List Bullet')
        _run(p_s, "Informação de sócios não disponível ou nenhum sócio ativo identificado.", color='475569', size=10, italic=True)

    # Disclaimer de Operações Especiais (Transição)
    p_ops = doc.add_paragraph()
    p_ops.paragraph_format.space_before = Pt(12)
    _run(p_ops, 'Os parágrafos, a seguir, trazem problemas identificados em trabalhos de Operações Especiais sobre o programa.', color='0F172A', size=10)

    # Seção de Mão de Obra e RT (Placeholders em vermelho)
    nota_rais_8 = 'Relação Anual de Informações Sociais, atualização em XXX de XXX. Consulta realizada em xx.xx.xxxx.'
    nota_farmaceutica_9 = 'Art. 5º da Lei nº 13.021, de 08.08.2014.'
    nota_esocial_10 = (
        'eSocial é o sistema de escrituração digital das obrigações fiscais, previdenciárias e trabalhistas '
        'do governo federal.'
    )

    doc.add_paragraph()
    p_rais = doc.add_paragraph()
    _run(p_rais, 'Segundo dados da Relação Anual de Informações Sociais (RAIS)', color='0F172A', size=10)
    _footnote_ref(doc, p_rais, 8, nota_rais_8)
    _run(p_rais, f' do Ministério do Trabalho e Emprego, a Farmácia {data.get("razao_social") or ""} possuía ', color='0F172A', size=10)
    _run(p_rais, 'yy', color='334155', size=10, bold=True)
    _run(p_rais, ' funcionários registrados em ', color='0F172A', size=10)
    _run(p_rais, 'XXXX', color='334155', size=10, bold=True)
    _run(p_rais, '. Contudo, há registro de apenas ', color='0F172A', size=10)
    _run(p_rais, 'x', color='334155', size=10, bold=True)
    _run(p_rais, ' funcionário(s) nos anos de ', color='0F172A', size=10)
    _run(p_rais, '20XX, 20YY e 20ZZ', color='334155', size=10, bold=True)
    _run(p_rais, ', período em que, conforme será visto mais adiante, a transferência de recursos aumentou de forma relevante.', color='0F172A', size=10)

    p_esocial = doc.add_paragraph()
    p_esocial.paragraph_format.space_before = Pt(6)
    _run(p_esocial, 'Destaca-se, também, o fato de que a legislação', color='0F172A', size=10)
    _footnote_ref(doc, p_esocial, 9, nota_farmaceutica_9)
    _run(p_esocial, ' sobre o exercício e a fiscalização das atividades farmacêuticas dispõe que a farmácia e a drogaria terão, obrigatoriamente, a responsabilidade e a assistência técnica de farmacêutico habilitado durante todo o horário de funcionamento do estabelecimento. Assim sendo, fica evidenciada mais uma possível irregularidade, pois em consulta ao eSocial', color='0F172A', size=10)
    _footnote_ref(doc, p_esocial, 10, nota_esocial_10)
    _run(p_esocial, ' (atualizado até ', color='0F172A', size=10)
    _run(p_esocial, 'XXXXX', color='334155', size=10, bold=True)
    _run(p_esocial, ') foi identificado que, no período de ', color='0F172A', size=10)
    _run(p_esocial, 'XXXX a YYYY', color='334155', size=10, bold=True)
    _run(p_esocial, ', a única empregada registrada era ', color='0F172A', size=10)
    _run(p_esocial, 'XXXX', color='334155', size=10, bold=True)
    _run(p_esocial, ', que havia sido admitida em ', color='0F172A', size=10)
    _run(p_esocial, 'XXX', color='334155', size=10, bold=True)
    _run(p_esocial, '.', color='0F172A', size=10)


def _add_quadro_53(doc, razao_social, cnpj_fmt, cnpj_data, periodo_txt):
    p_title = doc.add_paragraph()
    _format_quadro_title(p_title)
    _run(p_title, f'Quadro 02 – Dispensações de medicamentos informadas no Sistema Autorizador de Vendas (SAV) pela Farmácia {razao_social} (CNPJ {cnpj_fmt}), sem comprovação em notas fiscais de aquisição.', color='0F172A', size=9, bold=True)
    
    table = doc.add_table(rows=4, cols=3)
    table.style = 'Table Grid'
    _set_table_fixed_widths(table, [Inches(3.4), Inches(1.85), Inches(1.85)])
    
    hdr_cells = table.rows[0].cells
    _run(hdr_cells[0].paragraphs[0], 'Situação', bold=True)
    _run(hdr_cells[1].paragraphs[0], 'Valor em R$', bold=True)
    _run(hdr_cells[2].paragraphs[0], 'Quantidades de Medicamentos', bold=True)
    
    for cell in hdr_cells:
        cell.paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.CENTER
        _cell_bg(cell, 'E2E8F0')

    r1 = table.rows[1].cells
    _run(r1[0].paragraphs[0], 'Dispensações totais informadas no SAV pela farmácia')
    _run(r1[1].paragraphs[0], f'{cnpj_data.get("totalMov", 0):,.2f}'.replace(',', 'X').replace('.', ',').replace('X', '.'))
    _run(r1[2].paragraphs[0], f'{cnpj_data.get("totalQtde", 0):,.0f}'.replace(',', '.'))
    
    r2 = table.rows[2].cells
    _run(r2[0].paragraphs[0], 'Valor de dispensações sem comprovação (R$)')
    _run(r2[1].paragraphs[0], f'{cnpj_data.get("valSemComp", 0):,.2f}'.replace(',', 'X').replace('.', ',').replace('X', '.'))
    _run(r2[2].paragraphs[0], f'{cnpj_data.get("qtdeSemComp", 0):,.0f}'.replace(',', '.'))

    r3 = table.rows[3].cells
    _run(r3[0].paragraphs[0], '% de vendas no Programa Farmácia Popular sem comprovação')
    _run(r3[1].paragraphs[0], f'{cnpj_data.get("percValSemComp", 0):.2f}%'.replace('.', ','))
    _run(r3[2].paragraphs[0], f'{cnpj_data.get("percQtdeSemComp", 0):.2f}%'.replace('.', ','))
    
    for row in table.rows[1:]:
        row.cells[1].paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.CENTER
        row.cells[2].paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.CENTER

    for row in table.rows:
        for cell in row.cells:
            for p in cell.paragraphs:
                p.paragraph_format.space_before = Pt(2)
                p.paragraph_format.space_after = Pt(2)

    p_foot = doc.add_paragraph()
    _format_quadro_footnote(p_foot)
    p_foot.alignment = WD_ALIGN_PARAGRAPH.LEFT
    _run(p_foot, 'Fonte: Relatório de Autorizações Consolidadas, emitido pelo Departamento de Assistência Farmacêutica - DAF/SCTICS/MS, e base de dados das notas fiscais eletrônicas (NF-e), mantida pela Receita Federal do Brasil.', color='64748B', size=8)
    _keep_small_table_together(p_title, table, [p_foot])
