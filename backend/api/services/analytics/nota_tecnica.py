import io
import os
import polars as pl
from datetime import date
from docx import Document
from docx.shared import Inches, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_TAB_LEADER, WD_TAB_ALIGNMENT
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

from data_cache import get_df_matriz_risco
from .farmacia import get_dados_farmacia
from .dashboard import get_dashboard_data
from .indicadores import _INDICATOR_FLAGS


# ── Helpers XML ──────────────────────────────────────────────────────────────

def _cell_bg(cell, fill_hex: str):
    """Define cor de fundo de uma célula."""
    tc = cell._tc
    tcPr = tc.get_or_add_tcPr()
    for existing in tcPr.findall(qn('w:shd')):
        tcPr.remove(existing)
    shd = OxmlElement('w:shd')
    shd.set(qn('w:val'), 'clear')
    shd.set(qn('w:color'), 'auto')
    shd.set(qn('w:fill'), fill_hex)
    tcPr.append(shd)


def _cell_borders(cell, left=None, right=None, top=None, bottom=None):
    """Define bordas coloridas em lados específicos da célula. None = sem borda."""
    tc = cell._tc
    tcPr = tc.get_or_add_tcPr()
    for existing in tcPr.findall(qn('w:tcBorders')):
        tcPr.remove(existing)
    tcBorders = OxmlElement('w:tcBorders')
    for side, spec in (('left', left), ('right', right), ('top', top), ('bottom', bottom)):
        el = OxmlElement(f'w:{side}')
        if spec:
            el.set(qn('w:val'), 'single')
            el.set(qn('w:sz'), spec['sz'])
            el.set(qn('w:space'), '0')
            el.set(qn('w:color'), spec['color'])
        else:
            el.set(qn('w:val'), 'none')
        tcBorders.append(el)
    tcPr.append(tcBorders)


def _tbl_no_borders(tbl):
    """Remove todas as bordas visíveis de uma tabela no nível da tabela."""
    tblEl = tbl._tbl
    tblPr = tblEl.find(qn('w:tblPr'))
    if tblPr is None:
        tblPr = OxmlElement('w:tblPr')
        tblEl.insert(0, tblPr)
    for existing in tblPr.findall(qn('w:tblBorders')):
        tblPr.remove(existing)
    tblBorders = OxmlElement('w:tblBorders')
    for side in ('top', 'left', 'bottom', 'right', 'insideH', 'insideV'):
        el = OxmlElement(f'w:{side}')
        el.set(qn('w:val'), 'none')
        tblBorders.append(el)
    tblPr.append(tblBorders)


def _risk_color(classificacao: str | None, score: float) -> tuple[str, str]:
    """Retorna (hex_6chars, label) baseado na classificação de risco do sistema."""
    c = (classificacao or '').upper()
    if 'CRÍTICO' in c or 'CRITICO' in c or 'ALTO' in c:
        return 'EF4444', 'CRÍTICO'
    if 'MÉDIO' in c or 'MEDIO' in c or 'ATENÇÃO' in c or 'ATENCAO' in c:
        return 'F97316', 'ATENÇÃO'
    if 'BAIXO' in c or 'NORMAL' in c:
        return '10B981', 'NORMAL'
    if score > 20:
        return 'EF4444', 'CRÍTICO'
    if score > 10:
        return 'F97316', 'ATENÇÃO'
    return '10B981', 'NORMAL'


def _rgb(hex6: str) -> RGBColor:
    return RGBColor(int(hex6[0:2], 16), int(hex6[2:4], 16), int(hex6[4:6], 16))


def _run(para, text: str, *, color: str, size: float, bold=False, italic=False):
    run = para.add_run(text)
    run.bold = bold
    run.italic = italic
    run.font.size = Pt(size)
    run.font.color.rgb = _rgb(color)
    return run


# ── Mapeamento da Seção 5 ──────────────────────────────────────────────────

_SECAO5_MAP = [
    ('falecidos',                    '5.5',  'Vendas de medicamento para pessoas falecidas'),
    ('incompatibilidade_patologica', '5.6',  'Vendas de medicamento com incompatibilidade patológica'),
    ('teto',                         '5.7',  'Vendas no “teto máximo” para clientes da Farmácia {farmacia} com percentual sobre suas vendas totais muito superior ao dos estabelecimentos de sua região'),
    ('polimedicamento',              '5.8',  'Vendas de quatro ou mais itens de medicamentos por cupom realizadas pela Farmácia {farmacia} com percentual sobre suas vendas totais muito superior ao dos estabelecimentos de sua região'),
    ('polimedicamento',              '5.9',  'Quantidade média de medicamentos por cupom, vendidos pela Farmácia {farmacia}, muito superior ao dos estabelecimentos de sua região'),
    ('ticket_medio',                 '5.10', 'Valor do “ticket médio”, dos medicamentos vendidos pela Farmácia {farmacia}, muito superior ao dos estabelecimentos de sua região'),
    ('receita_paciente',             '5.11', 'Faturamento médio mensal por cliente, obtido pela Farmácia {farmacia}, muito superior ao dos estabelecimentos de sua região'),
    ('per_capita',                   '5.12', 'Faturamento mensal per capita, obtido pela Farmácia {farmacia}, muito superior ao dos estabelecimentos de sua região'),
    ('alto_custo',                   '5.13', 'Vendas de medicamentos de alto custo realizadas pela Farmácia {farmacia} com percentual sobre suas vendas totais muito superior ao dos estabelecimentos de sua região'),
    ('vendas_rapidas',               '5.14', 'Vendas de medicamentos em tempo inferior a 60 segundos'),
    ('recorrencia_sistemica',        '5.15', 'Vendas de medicamentos com precisão absoluta de 30 dias realizadas pela Farmácia {farmacia} com percentual sobre suas vendas totais muito superior ao dos estabelecimentos de sua região'),
    ('dias_pico',                    '5.16', 'Vendas de medicamentos em dias de pico realizadas pela Farmácia {farmacia} com percentual sobre suas vendas totais muito superior ao dos estabelecimentos de sua região'),
    ('dispersao_geografica',         '5.17', 'Vendas para pessoas residentes em outros Estados realizadas pela Farmácia {farmacia} com percentual sobre suas vendas totais muito superior ao dos estabelecimentos de sua região'),
    ('compra_unica',                 '5.18', 'Volume elevado de pacientes com registro de venda única de medicamento'),
    ('hhi_crm',                      '5.19', 'Concentração atípica de registros do mesmo médico (CRM) no Sistema Autorizador de Vendas do PFPB'),
    ('exclusividade_crm',            '5.20', 'Vendas de medicamentos vinculados a CRMs de médicos cujos registros, no Sistema Autorizador de Vendas do PFPB, foram realizados exclusivamente pela Farmácia {farmacia}'),
    ('crms_irregulares',             '5.21', 'Vendas de medicamentos prescritos por médicos com irregularidade em seus CRMs'),
]


def _get_criticos(cnpj: str) -> set[str]:
    """Identifica quais indicadores estão em nível CRÍTICO para o CNPJ."""
    try:
        df = get_df_matriz_risco()
        df = df.rename({c: c.lower() for c in df.columns})
        rows = df.filter(pl.col("cnpj") == cnpj)
        if rows.is_empty():
            return set()
        row = rows.row(0, named=True)
        return {
            key for key, (_, flag_c) in _INDICATOR_FLAGS.items()
            if row.get(flag_c.lower()) == 1
        }
    except Exception:
        return set()


def _add_toc_entry(doc, num: str, title: str, page: str = 'xx'):
    """Adiciona uma entrada no sumário com tab stop e líder de pontos."""
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.LEFT
    p.paragraph_format.tab_stops.add_tab_stop(
        Inches(6.4), WD_TAB_ALIGNMENT.RIGHT, WD_TAB_LEADER.DOTS
    )
    _run(p, f"{num} {title}\t{page}", color='0F172A', size=10)
    p.paragraph_format.space_after = Pt(2)


def _build_sumario(doc, criticos: set[str], razao_social: str, cnpj_fmt: str):
    """Constrói a página de sumário dinâmica."""
    doc.add_page_break()
    p_title = doc.add_paragraph()
    p_title.alignment = WD_ALIGN_PARAGRAPH.CENTER
    _run(p_title, 'SUMÁRIO', color='0F172A', size=14, bold=True)
    doc.add_paragraph()

    _add_toc_entry(doc, '1.', 'ASSUNTO')
    _add_toc_entry(doc, '2.', 'REFERÊNCIAS')
    _add_toc_entry(doc, '3.', 'INTRODUÇÃO')
    _add_toc_entry(doc, '4.', 'SÍNTESE DO PROGRAMA FARMÁCIA POPULAR DO BRASIL E DA METODOLOGIA DESENVOLVIDA PELA CGU PARA SEU MONITORAMENTO')
    _add_toc_entry(doc, '  4.1', 'Sobre o Programa Farmácia Popular do Brasil')
    _add_toc_entry(doc, '  4.2', 'Sobre metodologia desenvolvida pela CGU para apuração de possíveis “vendas sem comprovação”')

    _add_toc_entry(doc, '5.', 'ANÁLISE')
    _add_toc_entry(doc, '  5.1', f'Informações sobre a Farmácia {razao_social} (CNPJ {cnpj_fmt})')
    _add_toc_entry(doc, '  5.2', 'Informações obtidas no Portal de Gestão do Farmácia Popular')
    _add_toc_entry(doc, '  5.3', 'Indícios de estoque incompatível com as vendas subsidiadas pelo Programa Farmácia Popular do Brasil')
    _add_toc_entry(doc, '  5.4', f'Evolução atípica das transferências do Programa Farmácia Popular do Brasil para a Farmácia {razao_social} e das possíveis “vendas sem comprovação” por ela realizadas')

    for key, num, title in _SECAO5_MAP:
        if key in criticos:
            full_title = title.format(farmacia=razao_social) if '{farmacia}' in title else title
            _add_toc_entry(doc, f'  {num}', full_title)

    _add_toc_entry(doc, '6.', 'CONCLUSÃO E ENCAMINHAMENTO')
    doc.add_page_break()


# ── Geração do documento ─────────────────────────────────────────────────────

def generate_nota_tecnica(db, cnpj: str, data_inicio: date = None, data_fim: date = None):
    """Gera a Nota Técnica Preliminar em formato .docx."""

    # 1. Coleta de dados
    cadastro_obj = get_dados_farmacia(cnpj)
    cadastro = cadastro_obj.model_dump() if hasattr(cadastro_obj, 'model_dump') else cadastro_obj.dict() if hasattr(cadastro_obj, 'dict') else {}

    resumo = get_dashboard_data(db, data_inicio, data_fim, cnpjs=[cnpj])
    cnpj_data_obj = resumo.resultado_cnpjs[0] if hasattr(resumo, 'resultado_cnpjs') and resumo.resultado_cnpjs else None
    cnpj_data = cnpj_data_obj.model_dump() if cnpj_data_obj and hasattr(cnpj_data_obj, 'model_dump') else cnpj_data_obj.dict() if cnpj_data_obj and hasattr(cnpj_data_obj, 'dict') else {}

    # 2. Campos derivados
    razao_social = (cadastro.get('razao_social') or cnpj_data.get('razao_social') or 'NÃO INFORMADO').upper()
    municipio = cnpj_data.get('municipio') or cadastro.get('municipio') or '—'
    uf = cnpj_data.get('uf') or cadastro.get('uf') or '—'
    regiao_saude = cadastro.get('no_regiao_saude') or cnpj_data.get('no_regiao_saude') or ''
    cnpj_fmt = f'{cnpj[:2]}.{cnpj[2:5]}.{cnpj[5:8]}/{cnpj[8:12]}-{cnpj[12:]}' if len(cnpj) == 14 and cnpj.isdigit() else cnpj

    logradouro = ' '.join(p for p in [cadastro.get('tipo_logradouro') or '', cadastro.get('logradouro') or ''] if p).strip()
    numero = cadastro.get('numero') or ''
    bairro = cadastro.get('bairro') or ''
    cep = cadastro.get('cep') or ''
    endereco_parts = [f'{logradouro} {numero}'.strip(), bairro]
    endereco = ', '.join(p for p in endereco_parts if p and p not in ('None',))
    if cep and cep not in ('None', ''): endereco += f' — CEP {cep}'

    perc = float(cnpj_data.get('percValSemComp') or 0)
    score = float(cnpj_data.get('score_risco_final') or 0)
    classificacao = cnpj_data.get('classificacao_risco') or ''
    risco_hex, risco_label = _risk_color(classificacao, score)

    if data_inicio and data_fim:
        periodo_txt = f'{data_inicio.strftime("%d/%m/%Y")} a {data_fim.strftime("%d/%m/%Y")}'
    elif data_inicio:
        periodo_txt = f'A partir de {data_inicio.strftime("%d/%m/%Y")}'
    elif data_fim:
        periodo_txt = f'Até {data_fim.strftime("%d/%m/%Y")}'
    else:
        periodo_txt = 'Histórico completo'

    # 3. Documento e margens
    doc = Document()
    style_normal = doc.styles['Normal']
    style_normal.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY

    for section in doc.sections:
        section.top_margin = Inches(0.5)
        section.bottom_margin = Inches(0.5)
        section.left_margin = Inches(0.7)
        section.right_margin = Inches(0.7)

    PAGE_W = Inches(7.1)
    BAR_W = Inches(0.18)
    MAIN_W = PAGE_W - BAR_W

    # PÁGINA 1 — CAPA
    tbl_banner = doc.add_table(rows=1, cols=2)
    tbl_banner.autofit = False
    tbl_banner.columns[0].width = BAR_W
    tbl_banner.columns[1].width = MAIN_W
    _tbl_no_borders(tbl_banner)

    cell_bar = tbl_banner.rows[0].cells[0]
    cell_main = tbl_banner.rows[0].cells[1]
    _cell_bg(cell_bar, '6366F1')
    _cell_bg(cell_main, '0F172A')

    p_main = cell_main.paragraphs[0]
    p_main.alignment = WD_ALIGN_PARAGRAPH.CENTER

    logo_path = os.path.abspath(os.path.join(os.getcwd(), 'frontend', 'public', 'img', 'logo_cgu.png'))
    if os.path.exists(logo_path):
        p_main.add_run().add_picture(logo_path, width=Inches(2.0))
        p_main.add_run('\n')

    _run(p_main, 'SENTINELA', color='CBD5E1', size=22, bold=True)
    _run(p_main, '  /  Sistema de Auditoria Contínua', color='94A3B8', size=11)
    p_main.add_run('\n')
    _run(p_main, 'Programa Farmácia Popular do Brasil — PFPB', color='94A3B8', size=10)
    p_main.add_run('\n\n')
    _run(p_main, 'Nota Técnica Preliminar', color='6366F1', size=20, bold=True)
    p_main.add_run('\n')

    tbl_card = doc.add_table(rows=1, cols=1)
    tbl_card.autofit = False
    tbl_card.columns[0].width = PAGE_W
    _tbl_no_borders(tbl_card)
    cell_card = tbl_card.rows[0].cells[0]
    _cell_bg(cell_card, '1E293B')
    _cell_borders(cell_card, left={'sz': '24', 'color': risco_hex})

    cp = cell_card.paragraphs[0]
    cp.alignment = WD_ALIGN_PARAGRAPH.LEFT
    _run(cp, razao_social + '\n', color='CBD5E1', size=13, bold=True)
    _run(cp, f'CNPJ {cnpj_fmt}     {municipio} / {uf}\n', color='94A3B8', size=9)
    if endereco: _run(cp, f'{endereco}\n', color='64748B', size=8)
    _run(cp, f'Período: {periodo_txt}\n', color='64748B', size=8)
    cp.add_run('\n')
    _run(cp, '% SEM COMPROVAÇÃO   ', color='64748B', size=7)
    _run(cp, f'{perc:.1f}%       ', color=risco_hex, size=18, bold=True)
    _run(cp, 'SCORE DE RISCO   ', color='64748B', size=7)
    _run(cp, f'{score:.1f}       ', color=risco_hex, size=18, bold=True)
    _run(cp, risco_label, color=risco_hex, size=9, bold=True)

    p_ts = doc.add_paragraph()
    _run(p_ts, f'Gerado em: {date.today().strftime("%d/%m/%Y")}', color='64748B', size=8)

    # ── 4. Seção 1: Sumário (Sem Rodapé) ──────────────────────────────────
    sec_sumario = doc.add_section()
    sec_sumario.footer.is_linked_to_previous = False
    
    sec_sumario.top_margin = Inches(0.5); sec_sumario.bottom_margin = Inches(0.5)
    sec_sumario.left_margin = Inches(0.7); sec_sumario.right_margin = Inches(0.7)

    # SUMÁRIO
    criticos = _get_criticos(cnpj)
    _build_sumario(doc, criticos, razao_social, cnpj_fmt)

    # ── 5. Seção 2: Assunto e Referências (Rodapé 1) ────────────────────
    sec_ref = doc.add_section()
    sec_ref.footer.is_linked_to_previous = False
    f_ref = sec_ref.footer.paragraphs[0]
    f_ref.alignment = WD_ALIGN_PARAGRAPH.LEFT
    _run(f_ref, '(1) De acordo com informações contidas no site do Ministério da Saúde a respeito do Programa Farmácia Popular do Brasil: ', color='64748B', size=8)
    _run(f_ref, 'https://www.gov.br/saude/pt-br/composicao/sectics/farmacia-popular/legislacao', color='64748B', size=8)
    _run(f_ref, f' (acessado em {date.today().strftime("%d/%m/%Y")}).', color='64748B', size=8)
    
    sec_ref.top_margin = Inches(0.5); sec_ref.bottom_margin = Inches(0.5)
    sec_ref.left_margin = Inches(0.7); sec_ref.right_margin = Inches(0.7)

    # 1. ASSUNTO
    doc.add_heading('1. ASSUNTO', level=1)
    doc.add_paragraph(f'A presente Nota Técnica (NT), de caráter investigativo e sigiloso, tem como objetivo demonstrar indícios de fraudes cometidas pela Farmácia {razao_social} (CNPJ {cnpj_fmt}), credenciada junto ao Programa Farmácia Popular do Brasil (PFPB) do Ministério da Saúde (MS) para a dispensação gratuita de medicamentos para cidadãos.')

    # 2. REFERÊNCIAS
    h2 = doc.add_heading('2. REFERÊNCIAS', level=1)
    run_sup = h2.add_run('(1)')
    run_sup.font.superscript = True
    doc.add_paragraph('As principais referências normativas e técnicas utilizadas nesta análise incluem:')
    ref_list = [
        'Lei nº 10.858, de 06.05.2004 (deu origem ao Programa Farmácia Popular do Brasil - PFPB);',
        'Decreto 5.909 de 20.05.2004 (regulamentou o PFPB);',
        'Portaria GM/MS nº 491 de 09.03.2006 (habilitou farmácias e drogarias privadas);',
        'Portaria GM/MS nº 184, de 03.02.2011 (normas operacionais);',
        'Portaria de Consolidação GM/MS nº 5, de 28.09.2017 (marco regulatório atual do Programa Farmácia Popular do Brasil);',
        'Portaria GM/MS nº 2.898, de 03.11.2021 (aumenta o prazo para guarda da documentação comprobatória das dispensações para um período de dez anos);',
        'Portaria GM/MS nº 1.053, de 12.05.2022 (regulamenta o procedimento de averiguação dos fatos relacionados a indícios ou notícias de irregularidades no âmbito do PFPB);',
        'Relatório de Apuração da CGU nº 823121, publicado em 04.01.2024;',
        'Portaria GM/MS nº 6.613, de 13.02.2025 (extinguiu a modalidade do copagamento do Programa).',
    ]
    for ref in ref_list: doc.add_paragraph(ref, style='List Bullet')

    # ── 6. Seção 3: Introdução (Sem rodapé específico) ──────────────────
    sec_intro = doc.add_section()
    sec_intro.footer.is_linked_to_previous = False
    
    sec_intro.top_margin = Inches(0.5); sec_intro.bottom_margin = Inches(0.5)
    sec_intro.left_margin = Inches(0.7); sec_intro.right_margin = Inches(0.7)

    # 3. INTRODUÇÃO
    doc.add_heading('3. INTRODUÇÃO', level=1)
    doc.add_paragraph(f'No âmbito dos trabalhos realizados pela CGU de monitoramento e avaliação de gastos do Ministério da Saúde com o Programa Farmácia Popular do Brasil, trata a presente Nota Técnica (NT) de indícios de fraudes cometidas pela Farmácia {razao_social} (CNPJ {cnpj_fmt}).')
    doc.add_paragraph(f'A partir de metodologia desenvolvida pela CGU, consignada em seu Relatório de Auditoria nº 823121 (contido no ANEXO I desta Nota Técnica), foi identificada para a Farmácia {razao_social}, no período de {periodo_txt}, ausência significativa de estoque compatível com as vendas (distribuições) realizadas de medicamentos para a população (denominada pela CGU como “vendas sem comprovação”), o que sugere a possibilidade de fraudes cometidas pelo estabelecimento por meio de registro fictício de dispensações de medicamentos.')
    
    snippets = [f'[Subitem 5.4] evolução atípica das transferências do Programa e das possíveis “vendas sem comprovação” realizadas pela Farmácia {razao_social}', '[Subitem 5.4.1] crescimento excessivo de dispensação do medicamento para tratamento da doença de Parkinson']
    mapping_intro = {
        'falecidos': '[Subitem 5.5] vendas de medicamentos para pessoas falecidas',
        'incompatibilidade_patologica': '[Subitem 5.6] vendas de medicamento com incompatibilidade patológica',
        'teto': '[Subitem 5.7] vendas no “teto máximo” para clientes com percentual excessivo',
        'polimedicamento': ['[Subitem 5.8] vendas desproporcionais de quatro ou mais itens de medicamentos por cupom', '[Subitem 5.9] quantidade média de medicamentos por cupom vendidos muito superior ao dos estabelecimentos da região'],
        'ticket_medio': '[Subitem 5.10] valor exorbitante do “ticket médio” dos medicamentos vendidos',
        'receita_paciente': '[Subitem 5.11] faturamento médio mensal por cliente demasiado',
        'per_capita': '[Subitem 5.12] faturamento mensal per capita bem acima dos estabelecimentos da região',
        'alto_custo': '[Subitem 5.13] vendas excessiva de medicamentos de alto custo',
        'vendas_rapidas': '[Subitem 5.14] vendas de medicamentos em tempo inferior a 60 segundos',
        'recorrencia_sistemica': '[Subitem 5.15] vendas de medicamentos com precisão absoluta de 30 dias muito superior aos dos estabelecimentos de sua região',
        'dias_pico': '[Subitem 5.16] vendas de medicamentos em dias de pico com percentual elevado',
        'dispersao_geografica': '[Subitem 5.17] vendas exageradas de medicamentos para pessoas residentes em outros Estados',
        'compra_unica': '[Subitem 5.18] volume elevado de pacientes com registro de venda única de medicamento',
        'hhi_crm': '[Subitem 5.19] concentração atípica de registros do mesmo médico (CRM) no Sistema Autorizador de Vendas do PFPB',
        'exclusividade_crm': f'[Subitem 5.20] vendas de medicamentos vinculados a CRMs de médicos cujos registros foram realizados exclusivamente pela Farmácia {razao_social}',
        'crms_irregulares': '[Subitem 5.21] vendas de medicamentos prescritos por médicos com irregularidade em seus CRMs',
    }
    for key, snippet in mapping_intro.items():
        if key in criticos:
            if isinstance(snippet, list): snippets.extend(snippet)
            else: snippets.append(snippet)
    
    texto_snippets = (", ".join(snippets[:-1]) + " e " + snippets[-1]) if len(snippets) > 1 else snippets[0]
    doc.add_paragraph(f'Além disso, a presente NT revela criticidades que corroboram com o achado principal de “vendas sem comprovação”, como {texto_snippets}.')
    doc.add_paragraph('A NT traz ainda análise da empresa em relação aos seus sócios, capital social, porte, situação cadastral junto à Receita Federal do Brasil e junto ao PFPB e compatibilidade entre o número de empregados e volume de recursos recebidos do MS.')

    fontes = ['Cadastro Nacional de Pessoas Jurídicas (CNPJ) e Cadastro de Pessoa Física (CPF) da Receita Federal do Brasil', 'Relação Anual de Informações Sociais (RAIS) do Ministério do Trabalho e Emprego', 'Sistema de Escrituração Digital das Obrigações Fiscais, Previdenciárias e Trabalhistas (eSocial)', 'Sistema Integrado de Administração Financeira do Governo Federal (SIAFI)']
    if 'polimedicamento' in criticos or 'teto' in criticos: fontes.append('[Subitem 5.4.1] dados demográficos oficiais fornecidos pelo Instituto Brasileiro de Geografia e Estatística (IBGE)')
    if 'falecidos' in criticos: fontes.append('[Subitem 5.5] Sistema de Informações sobre Mortalidade (SIM), SIRC e SISOB')
    if any(k in criticos for k in ['hhi_crm', 'exclusividade_crm', 'crms_irregulares']): fontes.append('[Subitem 5.19] [Subitem 5.20] [Subitem 5.21] e Cadastros de médicos do Conselho Regional de Medicina (CRM)')

    doc.add_paragraph(f'Os achados advindos das análises realizadas, consignados no item 5 desta Nota Técnica, tomaram por base informações registradas pela Farmácia {razao_social} no Sistema Autorizador de Vendas (SAV) do Programa Farmácia Popular do Brasil e cópias de notas fiscais eletrônicas relativas à aquisição de medicamentos por parte das farmácias que aderiram ao Programa, compartilhadas pela Receita Federal do Brasil. Além dessas informações, foram utilizados dados extraídos das seguintes fontes: {"; ".join(fontes)}.')

    # ── 7. Seção 4: Síntese (Rodapé 2) ───────────────────────────────────
    sec_sintese = doc.add_section()
    sec_sintese.footer.is_linked_to_previous = False
    f_sintese = sec_sintese.footer.paragraphs[0]
    f_sintese.alignment = WD_ALIGN_PARAGRAPH.LEFT
    _run(f_sintese, f'(2) Consulta ao site https://www.gov.br/saude/pt-br/composicao/sectics/farmacia-popular, em {date.today().strftime("%d/%m/%Y")}.', color='64748B', size=8)

    sec_sintese.top_margin = Inches(0.5); sec_sintese.bottom_margin = Inches(0.5)
    sec_sintese.left_margin = Inches(0.7); sec_sintese.right_margin = Inches(0.7)

    # 4. SÍNTESE
    doc.add_heading('4. SÍNTESE DO PROGRAMA FARMÁCIA POPULAR DO BRASIL E DA METODOLOGIA DESENVOLVIDA PELA CGU PARA SEU MONITORAMENTO', level=1)
    doc.add_heading('4.1. Sobre o Programa Farmácia Popular do Brasil', level=2)
    p_intro_41 = doc.add_paragraph(
        'O Programa Farmácia Popular do Brasil, instituído em 2004 para ampliar o acesso a medicamentos essenciais, '
        'consolidou-se como um pilar da saúde pública brasileira. Segundo site do Ministério da Saúde'
    )
    run_sup2 = p_intro_41.add_run('2')
    run_sup2.font.superscript = True
    p_intro_41.add_run(', o Programa Farmácia Popular do Brasil – PFPB é:')
    # Bloco de Citação 1
    p_quote1 = doc.add_paragraph(style='Quote')
    p_quote1.paragraph_format.left_indent = Inches(1.57) # ~4cm
    p_quote1.paragraph_format.space_after = Pt(12)       # Adiciona espaço de uma linha entre os blocos
    run_quote1 = p_quote1.add_run(
        '... programa do Governo Federal que visa complementar a disponibilização de medicamentos utilizados na '
        'Atenção Primária à Saúde, por meio de parceria com farmácias da rede privada. Dessa forma, além das '
        'Unidades Básicas de Saúde e farmácias municipais, o cidadão pode obter medicamentos nas farmácias '
        'credenciadas ao Farmácia Popular.'
    )
    run_quote1.font.size = Pt(10)

    # Bloco de Citação 2 (Continuação na linha de baixo)
    p_quote2 = doc.add_paragraph(style='Quote')
    p_quote2.paragraph_format.left_indent = Inches(1.57) # ~4cm
    run_quote2 = p_quote2.add_run(
        'A partir de 14 de fevereiro de 2025, o Programa Farmácia Popular passou a disponibilizar gratuitamente 100% '
        'dos medicamentos e insumos de seu elenco à população brasileira. O programa atende 12 indicações, '
        'contemplando medicamentos para hipertensão, diabetes, asma, osteoporose, dislipidemia (colesterol alto), '
        'rinite, doença de Parkinson, glaucoma, diabetes mellitus associada a doenças cardiovasculares e anticoncepção. '
        'Além disso, oferece fraldas geriátricas para pessoas com incontinência e absorventes higiênicos para '
        'beneficiárias do Programa Dignidade Menstrual.'
    )
    run_quote2.font.size = Pt(10)
    doc.add_paragraph('A operacionalização do programa ocorre com a participação de drogarias credenciadas pelo Ministério da Saúde (MS), que realizam a dispensação gratuita de medicamentos diretamente aos cidadãos. As drogarias são posteriormente ressarcidas pela União, de acordo com informações relativas às quantidades distribuídas de cada medicamento.')
    doc.add_paragraph('As informações acerca da dispensação são encaminhadas pelas drogarias credenciadas ao MS mensalmente por meio do Sistema Autorizador de Vendas (SAV), conforme disposto na Portaria de Consolidação GM/MS nº 5, de 28.09.2017, e anteriores. Por sua vez, o art. 22 da Portaria GM/MS nº 2.898, de 03.11.2021, dispõe que o estabelecimento deve manter por 10 (dez) anos, em ordem cronológica de emissão, duas cópias mantidas em locais distintos, uma em meio físico e outra em arquivo digitalizado, dos cupons vinculados assinados, dos documentos fiscais, das prescrições, dos laudos ou atestados médicos e dos documentos de identidade oficial apresentados no ato da compra e, ainda, dos documentos fiscais de aquisição dos respectivos medicamentos e/ou fraldas geriátricas dispensados no âmbito do PFPB.')

    doc.add_heading('4.2. Sobre metodologia desenvolvida pela CGU para apuração de possíveis “vendas sem comprovação”', level=2)
    doc.add_paragraph('O crescimento exponencial do PFPB, com gastos que saltaram de R$ 34,7 milhões em 2006 para patamares próximos a R$ 6 bilhões em 2025, impôs desafios complexos ao controle governamental, dada a imensa capilaridade de mais de 30 mil estabelecimentos credenciados.')
    doc.add_paragraph('Para enfrentar essa realidade, a CGU elaborou o Relatório de Apuração nº 823121 (ANEXO I desta NT), fundamentado no desenvolvimento do Sistema Sentinela, uma ferramenta de tecnologia da informação que automatiza o cruzamento de dados, em larga escala, do SAV com outras bases de informações.')
    doc.add_paragraph('De forma sintética, a premissa central de controle adotada pela CGU, apresentada de forma detalhada no referido relatório, é de natureza lógica e contábil: um estabelecimento não pode dispensar medicamentos que não adquiriu formalmente. Uma vez isto ocorrendo, a Farmácia estaria praticando uma “venda sem comprovação”, ou seja, uma distribuição de medicamentos para cidadãos, cobrada do Ministério da Saúde, sem comprovação de suas aquisições.')
    doc.add_paragraph('Para a aferição da regularidade das dispensações realizadas pelas farmácias, é necessário estimar um estoque inicial dos medicamentos para que seja possível, a partir desta informação e de suas compras posteriores, verificar a compatibilidade de suas vendas no âmbito do PFPB. Dada a limitação do SAV, de não existência de informação disponível sobre o estoque inicial de medicamentos de cada drogaria credenciada pelo MS, a CGU desenvolveu metodologia em que confronta as informações de vendas de medicamentos enviadas pelas farmácias ao Ministério da Saúde com as informações de suas compras contidas na base da Receita Federal do Brasil de Notas Fiscais Eletrônicas (NF-e), utilizada tanto para estimar seus estoques iniciais quanto para aferir a compatibilidade destes e suas compras posteriores com as vendas realizadas no âmbito do Programa.')
    doc.add_paragraph('A metodologia técnica do Sistema Sentinela foi desenhada de forma conservadora para garantir a robustez dos achados. O sistema utiliza a técnica de cut-off, estimando o estoque inicial como a soma das duas últimas compras anteriores à primeira venda registrada de cada medicamento. A partir desse ponto, o algoritmo realiza um balanço diário de entradas e saídas, considerando apenas as vendas do programa PFPB como débito no estoque e ignorando vendas privadas para o público geral, o que gera um saldo "virtual" favorável à farmácia. Em outras palavras, o conservadorismo da metodologia da CGU se ampara no fato de considerar, para os cálculos de estoque, que todos os medicamentos adquiridos pela farmácia, que fazem parte do rol do PFPB, somente foram vendidos para clientes que fizeram uso do Programa, ou seja, a metodologia não leva em conta a possibilidade real de que parte desses medicamentos tenha sido vendida para clientes comuns, que desembolsaram recursos próprios para suas aquisições.')
    doc.add_paragraph('Juridicamente, o controle sustenta-se na Portaria de Consolidação GM/MS nº 05/2017, que obriga a guarda das notas fiscais de aquisição por dez anos, e no Ajuste SINIEF nº 16/2010, que exige a identificação do produto pelo código GTIN/EAN. Nesse sentido, reforça-se que a descrição textual do produto é insuficiente para a liquidação da despesa, sendo o código de barras a única chave capaz de vincular com precisão o medicamento comprado ao preço de referência pago pelo governo.')
    doc.add_paragraph('Além do levantamento de valores de “Vendas sem Comprovação” para todos as empresas que operam no PFPB, o Sistema Sentinela extrai dos dados do Sistema Autorizador de Vendas (SAV) do Programa uma série de informações que permitem apontar para outras criticidades que corroboram com a suspeita de possíveis registros fictícios de dispensações de medicamentos por parte dos estabelecimentos.')

    # ── 8. Seção 5: Análise e Conclusão (Sem Rodapé específico) ──────────
    sec_analise = doc.add_section()
    sec_analise.footer.is_linked_to_previous = False
    
    sec_analise.top_margin = Inches(0.5); sec_analise.bottom_margin = Inches(0.5)
    sec_analise.left_margin = Inches(0.7); sec_analise.right_margin = Inches(0.7)

    # 5. ANÁLISE
    doc.add_heading('5. ANÁLISE', level=1)
    doc.add_heading(f'5.1 Informações sobre a Farmácia {razao_social} (CNPJ {cnpj_fmt})', level=2)
    doc.add_paragraph(f'O estabelecimento está localizado em {municipio}/{uf}. A análise detalhada das operações durante o período de {periodo_txt} revelou os pontos de auditoria descritos a seguir.')
    doc.add_heading('5.2 Informações obtidas no Portal de Gestão do Farmácia Popular', level=2)
    doc.add_paragraph('Análise de regularidade cadastral e histórico de pagamentos...')
    doc.add_heading('5.3 Indícios de estoque incompatível com as vendas subsidiadas pelo Programa Farmácia Popular do Brasil', level=2)
    doc.add_paragraph('Cruzamento de notas fiscais de entrada com cupons fiscais de saída...')
    doc.add_heading(f'5.4 Evolução atípica das transferências do Programa Farmácia Popular do Brasil para a Farmácia {razao_social} e das possíveis “vendas sem comprovação” por ela realizadas', level=2)
    doc.add_paragraph('Monitoramento de picos de faturamento incompatíveis com a média histórica ou regional...')

    for key, num, title in _SECAO5_MAP:
        if key in criticos:
            full_title = title.format(farmacia=razao_social) if '{farmacia}' in title else title
            doc.add_heading(f'{num} {full_title}', level=2)
            doc.add_paragraph(f'Foi detectado um alerta CRÍTICO para o indicador "{full_title}". Este comportamento indica uma distorção estatística severa (Modified Z-Score > 3.0) que exige verificação documental imediata.')

    # 6. CONCLUSÃO
    doc.add_heading('6. CONCLUSÃO E ENCAMINHAMENTO', level=1)
    if risco_label in ('CRÍTICO', 'ATENÇÃO'):
        doc.add_paragraph('Considerando o elevado score de risco e os indícios de irregularidades detectados nas seções anteriores, sugere-se a priorização deste estabelecimento para auditoria in loco ou solicitação formal de documentos para comprovação das vendas realizadas.')
    else:
        doc.add_paragraph('O estabelecimento apresenta indicadores que, embora monitorados, não atingiram os limiares de priorização para fiscalização imediata, recomendando-se a manutenção do acompanhamento sistêmico.')

    file_stream = io.BytesIO()
    doc.save(file_stream)
    file_stream.seek(0)
    return file_stream
