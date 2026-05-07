import io
import os
import polars as pl
from decimal import Decimal
from datetime import date
from docx import Document
from docx.shared import Inches, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_TAB_LEADER, WD_TAB_ALIGNMENT
from docx.enum.section import WD_SECTION
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

from data_cache import get_df_matriz_risco
from .farmacia import get_dados_farmacia
from .dashboard import get_dashboard_data
from .socios import get_socios_farmacia
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


def _cell_bg_run(run, fill_hex: str):
    """Define cor de fundo (shading) para um Run específico (realce)."""
    r = run._r
    rPr = r.get_or_add_rPr()
    shd = OxmlElement('w:shd')
    shd.set(qn('w:val'), 'clear')
    shd.set(qn('w:color'), 'auto')
    shd.set(qn('w:fill'), fill_hex)
    rPr.append(shd)


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


def _run(para, text: str, *, color: str = '0F172A', size: float = 10, bold=False, italic=False, underline=False):
    run = para.add_run(text)
    run.bold = bold
    run.italic = italic
    run.underline = underline
    run.font.size = Pt(size)
    run.font.color.rgb = _rgb(color)
    return run



def _format_cpf_cnpj(v: str | None) -> str:
    """Formata CPF ou CNPJ com máscara padrão."""
    if not v: return "—"
    clean = "".join(filter(str.isdigit, v))
    if len(clean) == 11:
        return f"{clean[:3]}.{clean[3:6]}.{clean[6:9]}-{clean[9:]}"
    if len(clean) == 14:
        return f"{clean[:2]}.{clean[2:5]}.{clean[5:8]}/{clean[8:12]}-{clean[12:]}"
    return v


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
    """Adiciona uma entrada no sumário com tab stop, líder de pontos e recuo para evitar sobreposição."""
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.LEFT
    
    # Recuo à direita para forçar o wrap antes de chegar no número da página
    p.paragraph_format.right_indent = Inches(0.7)
    
    # Recuo deslocado (Hanging Indent) para que a quebra de linha fique elegante
    # Ajustamos conforme o nível (se tem espaço ou não no início)
    indent_base = 0.4 if num.startswith(' ') else 0.2
    p.paragraph_format.left_indent = Inches(indent_base)
    p.paragraph_format.first_line_indent = Inches(-0.2)
    
    p.paragraph_format.tab_stops.add_tab_stop(
        Inches(6.4), WD_TAB_ALIGNMENT.RIGHT, WD_TAB_LEADER.DOTS
    )
    _run(p, f"{num} {title}\t{page}", color='0F172A', size=10)
    p.paragraph_format.space_after = Pt(2)


def _build_sumario(doc, criticos: set[str], razao_social: str, cnpj_fmt: str):
    """Constrói a página de sumário dinâmica."""
    p_title = doc.add_paragraph()
    p_title.alignment = WD_ALIGN_PARAGRAPH.CENTER
    _run(p_title, 'SUMÁRIO', color='0F172A', size=14, bold=True)
    doc.add_paragraph()

    _add_toc_entry(doc, '1.', 'ASSUNTO', page='3')
    _add_toc_entry(doc, '2.', 'REFERÊNCIAS', page='3')
    _add_toc_entry(doc, '3.', 'INTRODUÇÃO', page='4')
    _add_toc_entry(doc, '4.', 'SÍNTESE DO PROGRAMA FARMÁCIA POPULAR DO BRASIL E DA METODOLOGIA DESENVOLVIDA PELA CGU PARA SEU MONITORAMENTO', page='5')
    _add_toc_entry(doc, '  4.1', 'Sobre o Programa Farmácia Popular do Brasil', page='5')
    _add_toc_entry(doc, '  4.2', 'Sobre metodologia desenvolvida pela CGU para apuração de possíveis “vendas sem comprovação”', page='5')

    _add_toc_entry(doc, '5.', 'ANÁLISE', page='6')
    _add_toc_entry(doc, '  5.1', f'Informações sobre a Farmácia {razao_social} (CNPJ {cnpj_fmt})', page='6')
    _add_toc_entry(doc, '  5.2', 'Informações obtidas no Portal de Gestão do Farmácia Popular', page='6')
    _add_toc_entry(doc, '  5.3', 'Indícios de estoque incompatível com as vendas subsidiadas pelo Programa Farmácia Popular do Brasil', page='6')
    _add_toc_entry(doc, '  5.4', f'Evolução atípica das transferências do Programa Farmácia Popular do Brasil para a Farmácia {razao_social} e das possíveis “vendas sem comprovação” por ela realizadas', page='6')

    for key, num, title in _SECAO5_MAP:
        if key in criticos:
            full_title = title.format(farmacia=razao_social) if '{farmacia}' in title else title
            _add_toc_entry(doc, f'  {num}', full_title, page='6')

    _add_toc_entry(doc, '6.', 'CONCLUSÃO E ENCAMINHAMENTO', page='7')
    doc.add_page_break()


def _add_quadro_identificacao(doc, data: dict, capital_social: float, periodo_txt: str):
    """Adiciona o Quadro 01 com as informações detalhadas da farmácia."""
    doc.add_paragraph()
    p_title = doc.add_paragraph()
    p_title.alignment = WD_ALIGN_PARAGRAPH.CENTER
    _run(p_title, f"Quadro 01 - Informações detalhadas da Farmácia {data.get('razao_social') or ''}", color='0F172A', size=9, bold=True)
    _run(p_title, f"\n(CNPJ {data.get('cnpj_fmt') or ''})", color='475569', size=8)

    tbl = doc.add_table(rows=0, cols=2)
    tbl.style = 'Table Grid'
    tbl.autofit = False
    
    # Configura larguras (Total ~7.1 inches)
    col_label_w = Inches(2.2)
    col_value_w = Inches(4.9)

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
    relacao_pct = (total_mov / capital_social * 100) if capital_social > 0 else 0
    vezes = (total_mov / capital_social) if capital_social > 0 else 0
    
    p_nota = doc.add_paragraph()
    p_nota.paragraph_format.space_before = Pt(6)
    _run(p_nota, f"* A relação do valor de vendas sobre o capital social é de {relacao_pct:,.2f}%".replace(',', 'X').replace('.', ',').replace('X', '.'), color='475569', size=8)
    _run(p_nota, f", ou seja, ela recebeu, no período analisado ({periodo_txt}), apenas por meio das vendas subsidiadas pelo Programa Farmácia Popular, ", color='475569', size=8)
    _run(p_nota, f"{vezes:,.1f} vezes".replace(',', 'X').replace('.', ',').replace('X', '.'), color='0F172A', size=8, bold=True)
    _run(p_nota, " o valor do seu capital social.", color='475569', size=8)

    p_fonte = doc.add_paragraph()
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
    doc.add_paragraph()
    p_rais = doc.add_paragraph()
    _run(p_rais, 'Segundo dados da Relação Anual de Informações Sociais (RAIS)', color='0F172A', size=10)
    run_sup8 = p_rais.add_run('8')
    run_sup8.font.superscript = True
    run_sup8.font.size = Pt(7)
    _run(p_rais, f' do Ministério do Trabalho e Emprego, a Farmácia {data.get("razao_social") or ""} possuía ', color='0F172A', size=10)
    _run(p_rais, 'yy', color='EF4444', size=10, bold=True)
    _run(p_rais, ' funcionários registrados em ', color='0F172A', size=10)
    _run(p_rais, 'XXXX', color='EF4444', size=10, bold=True)
    _run(p_rais, '. Contudo, apenas ', color='0F172A', size=10)
    _run(p_rais, 'x', color='EF4444', size=10, bold=True)
    _run(p_rais, ' funcionário(s) consta(m) nos anos de ', color='0F172A', size=10)
    _run(p_rais, '20XX, 20YY e 20ZZ', color='EF4444', size=10, bold=True)
    _run(p_rais, ', período em que, conforme será visto mais adiante, a transferência de recursos aumentou de forma relevante.', color='0F172A', size=10)

    p_esocial = doc.add_paragraph()
    p_esocial.paragraph_format.space_before = Pt(6)
    _run(p_esocial, 'Destaca-se, também, o fato de que a legislação', color='0F172A', size=10)
    run_sup9 = p_esocial.add_run('9')
    run_sup9.font.superscript = True
    run_sup9.font.size = Pt(7)
    _run(p_esocial, ' sobre o exercício e a fiscalização das atividades farmacêuticas dispõe que a farmácia e a drogaria terão, obrigatoriamente, a responsabilidade e a assistência técnica de farmacêutico habilitado durante todo o horário de funcionamento do estabelecimento. Assim sendo, fica evidenciado mais uma possível irregularidade, pois em consulta ao eSocial', color='0F172A', size=10)
    run_sup10 = p_esocial.add_run('10')
    run_sup10.font.superscript = True
    run_sup10.font.size = Pt(7)
    _run(p_esocial, ' (atualizado até ', color='0F172A', size=10)
    _run(p_esocial, 'XXXXX', color='EF4444', size=10, bold=True)
    _run(p_esocial, ') foi identificado que, no período de ', color='0F172A', size=10)
    _run(p_esocial, 'XXXX a YYYY', color='EF4444', size=10, bold=True)
    _run(p_esocial, ', a única empregada registrada era ', color='0F172A', size=10)
    _run(p_esocial, 'XXXX', color='EF4444', size=10, bold=True)
    _run(p_esocial, ', que havia sido admitida em ', color='0F172A', size=10)
    _run(p_esocial, 'XXX', color='EF4444', size=10, bold=True)
    _run(p_esocial, '.', color='0F172A', size=10)


# ── Geração do documento ─────────────────────────────────────────────────────

def generate_nota_tecnica(db, cnpj: str, data_inicio: date = None, data_fim: date = None):
    """Gera a Nota Técnica Preliminar em formato .docx."""

    # 1. Coleta de dados
    cadastro_obj = get_dados_farmacia(cnpj)
    cadastro = cadastro_obj.model_dump() if hasattr(cadastro_obj, 'model_dump') else cadastro_obj.dict() if hasattr(cadastro_obj, 'dict') else {}

    resumo = get_dashboard_data(db, data_inicio, data_fim, cnpjs=[cnpj])
    cnpj_data_obj = resumo.resultado_cnpjs[0] if hasattr(resumo, 'resultado_cnpjs') and resumo.resultado_cnpjs else None
    cnpj_data = cnpj_data_obj.model_dump() if cnpj_data_obj and hasattr(cnpj_data_obj, 'model_dump') else cnpj_data_obj.dict() if cnpj_data_obj and hasattr(cnpj_data_obj, 'dict') else {}

    # Coleta de sócios
    socios_res = get_socios_farmacia(cnpj)
    socios_ativos = [s for s in socios_res.socios if not s.data_exclusao_sociedade]

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

    # PÁGINA 1 — CAPA (Estilo Oficial)
    # ── 4. Cabeçalho Oficial ───────────────────────────────────────────
    p_brasao = doc.add_paragraph()
    p_brasao.alignment = WD_ALIGN_PARAGRAPH.CENTER
    
    # Busca a raiz do projeto (d:\sentinela) a partir deste arquivo (backend/api/services/analytics/nota_tecnica.py)
    root_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..', '..'))
    brasao_path = os.path.join(root_dir, 'frontend', 'public', 'img', 'brasao_republica_mini.jpg')
    
    if os.path.exists(brasao_path):
        p_brasao.add_run().add_picture(brasao_path, width=Inches(1.5))
    else:
        # Fallback para debug se não encontrar
        print(f"⚠️ Alerta: Brasão não encontrado em {brasao_path}")
    
    p_header = doc.add_paragraph()
    p_header.alignment = WD_ALIGN_PARAGRAPH.CENTER
    _run(p_header, 'CONTROLADORIA-GERAL DA UNIÃO', color='0F172A', size=14, bold=True)
    
    doc.add_paragraph('\n' * 3)
    
    # ── 5. Título da Nota Técnica ──────────────────────────────────────
    p_titulo = doc.add_paragraph()
    p_titulo.alignment = WD_ALIGN_PARAGRAPH.CENTER
    _run(p_titulo, 'NOTA TÉCNICA PRELIMINAR\n', color='0F172A', size=24, bold=True)
    _run(p_titulo, 'SISTEMA SENTINELA', color='0F172A', size=14, bold=True)
    _run(p_titulo, '\nPrograma Farmácia Popular do Brasil', color='64748B', size=10, italic=True)

    doc.add_paragraph('\n' * 2)

    # ── 6. Selo de Sigilo ──────────────────────────────────────────────
    p_sigilo = doc.add_paragraph()
    p_sigilo.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r_sigilo = _run(p_sigilo, ' DOCUMENTO SIGILOSO ', color='FFFFFF', size=10, bold=True)
    _cell_bg_run(r_sigilo, 'EF4444') # Fundo vermelho para o selo de sigilo
    
    doc.add_paragraph('\n')


    # ── 6. Resumo Executivo da Auditoria (Capa) ──────────────────────────
    tbl_resumo = doc.add_table(rows=1, cols=2)
    tbl_resumo.autofit = False
    tbl_resumo.columns[0].width = Inches(4.5)
    tbl_resumo.columns[1].width = PAGE_W - Inches(4.5)
    _tbl_no_borders(tbl_resumo)
    
    # Coluna 1: Dados do Estabelecimento
    c_info = tbl_resumo.rows[0].cells[0]
    _cell_borders(c_info, bottom={'sz': '6', 'color': 'CBD5E1'})
    p_info = c_info.paragraphs[0]
    p_info.alignment = WD_ALIGN_PARAGRAPH.LEFT
    _run(p_info, 'IDENTIFICAÇÃO DO ESTABELECIMENTO AUDITADO\n', color='64748B', size=7, bold=True)
    _run(p_info, f'{razao_social}\n', color='0F172A', size=13, bold=True)
    _run(p_info, f'CNPJ {cnpj_fmt}  •  {municipio} / {uf}\n', color='475569', size=9)
    if endereco: 
        _run(p_info, f'{endereco}\n', color='64748B', size=8)
    _run(p_info, f'Período sob análise: {periodo_txt}', color='64748B', size=8)

    # Coluna 2: Status do Risco
    c_risk = tbl_resumo.rows[0].cells[1]
    _cell_bg(c_risk, 'F8FAFC') # Cinza suave para contraste
    _cell_borders(c_risk, left={'sz': '6', 'color': 'CBD5E1'}, bottom={'sz': '6', 'color': 'CBD5E1'})
    p_risk = c_risk.paragraphs[0]
    p_risk.alignment = WD_ALIGN_PARAGRAPH.CENTER
    
    _run(p_risk, 'CLASSIFICAÇÃO DE RISCO\n', color='64748B', size=7, bold=True)
    _run(p_risk, f'{risco_label}\n', color=risco_hex, size=18, bold=True)
    
    # Pequena divisória interna por parágrafo
    p_metrics = c_risk.add_paragraph()
    p_metrics.alignment = WD_ALIGN_PARAGRAPH.CENTER
    _run(p_metrics, 'SCORE FINAL: ', color='64748B', size=7)
    _run(p_metrics, f'{score:.1f}   ', color='0F172A', size=10, bold=True)
    _run(p_metrics, 'IRREGULARIDADE: ', color='64748B', size=7)
    _run(p_metrics, f'{perc:.1f}%', color='0F172A', size=10, bold=True)

    doc.add_paragraph('\n')
    p_ts = doc.add_paragraph()
    p_ts.alignment = WD_ALIGN_PARAGRAPH.RIGHT
    _run(p_ts, f'Relatório extraído do Sistema Sentinela em {date.today().strftime("%d/%m/%Y")}', color='94A3B8', size=8, italic=True)

    # ── 4. Seção 1: Sumário (Sem Rodapé) ──────────────────────────────────
    sec_sumario = doc.add_section()
    sec_sumario.footer.is_linked_to_previous = False
    
    sec_sumario.top_margin = Inches(0.5); sec_sumario.bottom_margin = Inches(0.5)
    sec_sumario.left_margin = Inches(0.7); sec_sumario.right_margin = Inches(0.7)

    # SUMÁRIO
    criticos = _get_criticos(cnpj)
    _build_sumario(doc, criticos, razao_social, cnpj_fmt)

    # ── 5. Seção 2: Assunto e Referências (Rodapé 1) ────────────────────
    sec_ref = doc.add_section(WD_SECTION.CONTINUOUS)
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
    
    p_intro = doc.add_paragraph('A partir de metodologia desenvolvida pela CGU, consignada em seu Relatório de Auditoria nº 823121 (contido no ANEXO I desta Nota Técnica), foi identificada para a Farmácia ')
    p_intro.add_run(razao_social).bold = True
    p_intro.add_run(', no período de ')
    run_periodo = p_intro.add_run(periodo_txt)
    run_periodo.underline = True
    run_periodo.bold = True
    p_intro.add_run(', ausência significativa de estoque compatível com as vendas (distribuições) realizadas de medicamentos para a população (denominada pela CGU como “vendas sem comprovação”), o que sugere a possibilidade de fraudes cometidas pelo estabelecimento por meio de registro fictício de dispensações de medicamentos.')
    
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

    # ── 7. Seção 4.1: Sobre o Programa (Rodapé notas 2 a 6) ──────────────────
    sec_41 = doc.add_section(WD_SECTION.CONTINUOUS)
    sec_41.footer.is_linked_to_previous = False
    f_41 = sec_41.footer.paragraphs[0]
    f_41.alignment = WD_ALIGN_PARAGRAPH.LEFT
    _run(f_41, f'(2) Consulta ao site https://www.gov.br/saude/pt-br/composicao/sectics/farmacia-popular, em {date.today().strftime("%d/%m/%Y")}.\n', color='64748B', size=8)
    _run(f_41, '(3) A lista dos medicamentos e produtos do PFPB, atualizada em 02.09.2025, pode ser obtida no endereço: https://www.gov.br/saude/pt-br/composicao/sectics/farmacia-popular/arquivos/elenco-de-medicamentos-e-insumos.pdf\n', color='64748B', size=8)
    _run(f_41, '(4) Após um intervalo sem a renovação anual obrigatória do credenciamento desde 2018, conforme o artigo 15 do Anexo LXXVII da Portaria de Consolidação nº 5, de 28 de setembro de 2017, o Ministério da Saúde reabriu a necessidade a partir de 17 de abril de 2025.\n', color='64748B', size=8)
    _run(f_41, '(5) Cabe informar que existia também a modalidade de copagamento (em que o beneficiário arcava com uma parte do custo), que foi extinta após a edição da Portaria GM/MS nº 6.613, de 13.02.2025.\n', color='64748B', size=8)
    _run(f_41, '(6) A Portaria GM/MS nº 111/2016, substituída pela Portaria GM/MS nº 2.898/2021, determinava em seu art. 22 que o estabelecimento deveria manter por cinco anos.', color='64748B', size=8)
    sec_41.top_margin = Inches(0.5); sec_41.bottom_margin = Inches(0.5)
    sec_41.left_margin = Inches(0.7); sec_41.right_margin = Inches(0.7)

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
    p_quote2.add_run('A partir de 14 de fevereiro de 2025, o Programa Farmácia Popular passou a disponibilizar gratuitamente 100% dos medicamentos e insumos de seu elenco à população brasileira. O programa atende 12 indicações, contemplando medicamentos para hipertensão, diabetes, asma, osteoporose, dislipidemia (colesterol alto), rinite, doença de Parkinson, glaucoma, diabetes mellitus associada a doenças cardiovasculares e anticoncepção. Além disso, oferece fraldas geriátricas para pessoas com incontinência e absorventes higiênicos para beneficiárias do Programa Dignidade Menstrual')
    run_sup3 = p_quote2.add_run('3')
    run_sup3.font.superscript = True
    p_quote2.add_run('.')
    for run in p_quote2.runs:
        if not run.font.superscript: run.font.size = Pt(10)

    p_op = doc.add_paragraph('A operacionalização do programa ocorre com a participação de drogarias credenciadas pelo Ministério da Saúde (MS)')
    run_sup4 = p_op.add_run('4')
    run_sup4.font.superscript = True
    p_op.add_run(', que realizam a dispensação gratuita de medicamentos diretamente aos cidadãos. As drogarias são posteriormente ressarcidas pela União, de acordo com informações relativas às quantidades distribuídas de cada medicamento')
    run_sup5 = p_op.add_run('5')
    run_sup5.font.superscript = True
    p_op.add_run('.')

    p_sav = doc.add_paragraph('As informações acerca da dispensação são encaminhadas pelas drogarias credenciadas ao MS mensalmente por meio do Sistema Autorizador de Vendas (SAV), conforme disposto na Portaria de Consolidação GM/MS nº 5, de 28.09.2017, e anteriores. Por sua vez, o art. 22 da Portaria GM/MS nº 2.898, de 03.11.2021, dispõe que o estabelecimento deve manter por 10 (dez) anos')
    run_sup6 = p_sav.add_run('6')
    run_sup6.font.superscript = True
    p_sav.add_run(', em ordem cronológica de emissão, duas cópias mantidas em locais distintos, uma em meio físico e outra em arquivo digitalizado, dos cupons vinculados assinados, dos documentos fiscais, das prescrições, dos laudos ou atestados médicos e dos documentos de identidade oficial apresentados no ato da compra e, ainda, dos documentos fiscais de aquisição dos respectivos medicamentos e/ou fraldas geriátricas dispensados no âmbito do PFPB.')

    # ── 8. Seção 4.2: Metodologia CGU (Rodapé nota 7) ────────────────────────
    sec_42 = doc.add_section(WD_SECTION.CONTINUOUS)
    sec_42.footer.is_linked_to_previous = False
    f_42 = sec_42.footer.paragraphs[0]
    f_42.alignment = WD_ALIGN_PARAGRAPH.LEFT
    _run(f_42, '(7) A CGU, em seu Relatório de Auditoria nº 823121, considerou "vendas sem comprovação" no âmbito do PFPB a diferença identificada por princípio ativo/insumo, após o batimento entre Notas Fiscais de entrada (compartilhadas pela Receita Federal do Brasil e relativas a aquisições de medicamentos do PFPB) e registro de saída no Sistema Autorizador de Vendas – SAV (onde as dispensações subsidiadas são informadas), tendo como elo os números que constam abaixo dos códigos de barra (Código GTIN).', color='64748B', size=8)
    sec_42.top_margin = Inches(0.5); sec_42.bottom_margin = Inches(0.5)
    sec_42.left_margin = Inches(0.7); sec_42.right_margin = Inches(0.7)

    doc.add_heading('4.2. Sobre metodologia desenvolvida pela CGU para apuração de possíveis "vendas sem comprovação"', level=2)
    doc.add_paragraph('O crescimento exponencial do PFPB, com gastos que saltaram de R$ 34,7 milhões em 2006 para patamares próximos a R$ 6 bilhões em 2025, impôs desafios complexos ao controle governamental, dada a imensa capilaridade de mais de 30 mil estabelecimentos credenciados.')
    doc.add_paragraph('Para enfrentar essa realidade, a CGU elaborou o Relatório de Apuração nº 823121 (ANEXO I desta NT), fundamentado no desenvolvimento do Sistema Sentinela, uma ferramenta de tecnologia da informação que automatiza o cruzamento de dados, em larga escala, do SAV com outras bases de informações.')
    p_cgu = doc.add_paragraph('De forma sintética, a premissa central de controle adotada pela CGU, apresentada de forma detalhada no referido relatório, é de natureza lógica e contábil: um estabelecimento não pode dispensar medicamentos que não adquiriu formalmente. Uma vez isto ocorrendo, a Farmácia estaria praticando uma “venda sem comprovação”')
    run_sup7 = p_cgu.add_run('7')
    run_sup7.font.superscript = True
    p_cgu.add_run(', ou seja, uma distribuição de medicamentos para cidadãos, cobrada do Ministério da Saúde, sem comprovação de suas aquisições.')
    doc.add_paragraph('Para a aferição da regularidade das dispensações realizadas pelas farmácias, é necessário estimar um estoque inicial dos medicamentos para que seja possível, a partir desta informação e de suas compras posteriores, verificar a compatibilidade de suas vendas no âmbito do PFPB. Dada a limitação do SAV, de não existência de informação disponível sobre o estoque inicial de medicamentos de cada drogaria credenciada pelo MS, a CGU desenvolveu metodologia em que confronta as informações de vendas de medicamentos enviadas pelas farmácias ao Ministério da Saúde com as informações de suas compras contidas na base da Receita Federal do Brasil de Notas Fiscais Eletrônicas (NF-e), utilizada tanto para estimar seus estoques iniciais quanto para aferir a compatibilidade destes e suas compras posteriores com as vendas realizadas no âmbito do Programa.')
    doc.add_paragraph('A metodologia técnica do Sistema Sentinela foi desenhada de forma conservadora para garantir a robustez dos achados. O sistema utiliza a técnica de cut-off, estimando o estoque inicial como a soma das duas últimas compras anteriores à primeira venda registrada de cada medicamento. A partir desse ponto, o algoritmo realiza um balanço diário de entradas e saídas, considerando apenas as vendas do programa PFPB como débito no estoque e ignorando vendas privadas para o público geral, o que gera um saldo "virtual" favorável à farmácia. Em outras palavras, o conservadorismo da metodologia da CGU se ampara no fato de considerar, para os cálculos de estoque, que todos os medicamentos adquiridos pela farmácia, que fazem parte do rol do PFPB, somente foram vendidos para clientes que fizeram uso do Programa, ou seja, a metodologia não leva em conta a possibilidade real de que parte desses medicamentos tenha sido vendida para clientes comuns, que desembolsaram recursos próprios para suas aquisições.')
    doc.add_paragraph('Juridicamente, o controle sustenta-se na Portaria de Consolidação GM/MS nº 05/2017, que obriga a guarda das notas fiscais de aquisição por dez anos, e no Ajuste SINIEF nº 16/2010, que exige a identificação do produto pelo código GTIN/EAN. Nesse sentido, reforça-se que a descrição textual do produto é insuficiente para a liquidação da despesa, sendo o código de barras a única chave capaz de vincular com precisão o medicamento comprado ao preço de referência pago pelo governo.')
    doc.add_paragraph('Além do levantamento de valores de “Vendas sem Comprovação” para todos as empresas que operam no PFPB, o Sistema Sentinela extrai dos dados do Sistema Autorizador de Vendas (SAV) do Programa uma série de informações que permitem apontar para outras criticidades que corroboram com a suspeita de possíveis registros fictícios de dispensações de medicamentos por parte dos estabelecimentos.')

    # ── Seção 5 intro (sem rodapé) ────────────────────────────────────────
    sec_5_intro = doc.add_section(WD_SECTION.CONTINUOUS)
    sec_5_intro.footer.is_linked_to_previous = False
    sec_5_intro.top_margin = Inches(0.5); sec_5_intro.bottom_margin = Inches(0.5)
    sec_5_intro.left_margin = Inches(0.7); sec_5_intro.right_margin = Inches(0.7)

    # 5. ANÁLISE
    doc.add_heading('5. ANÁLISE', level=1)
    doc.add_paragraph(f'A presente Nota Técnica traz informações cadastrais e o resultado das análises dos alertas extraídos do Sistema Sentinela para a Farmácia {razao_social}, tanto em relação a possíveis “vendas sem comprovação” quanto a outras criticidades que corroboram com este achado principal.')

    # ── Seção 5.1 (Rodapé notas 8 e 9) ─────────────────────────────────
    sec_51 = doc.add_section(WD_SECTION.CONTINUOUS)
    sec_51.footer.is_linked_to_previous = False
    f_51 = sec_51.footer.paragraphs[0]
    f_51.alignment = WD_ALIGN_PARAGRAPH.LEFT
    _run(f_51, '(8) Relação Anual de Informações Sociais, atualização em ', color='64748B', size=8)
    _run(f_51, 'XXX de XXX', color='EF4444', size=8, bold=True)
    _run(f_51, '. Consulta realizada em ', color='64748B', size=8)
    _run(f_51, 'xx.xx.xxxx', color='EF4444', size=8, bold=True)
    _run(f_51, '.\n', color='64748B', size=8)
    _run(f_51, '(9) Art. 5º da Lei nº 13.021, de 08.08.2014.\n', color='64748B', size=8)
    _run(f_51, '(10) eSocial é o sistema de escrituração digital das obrigações fiscais, previdenciárias e trabalhistas do governo federal.', color='64748B', size=8)
    sec_51.top_margin = Inches(0.5); sec_51.bottom_margin = Inches(0.5)
    sec_51.left_margin = Inches(0.7); sec_51.right_margin = Inches(0.7)

    doc.add_heading(f'5.1 Informações sobre a Farmácia {razao_social} (CNPJ {cnpj_fmt})', level=2)    
    # Mapeamento do porte conforme padrões RFB/Filtros
    porte_raw = getattr(cnpj_data_obj, 'porte_empresa', 'ND') if cnpj_data_obj else "ND"
    porte_txt = "empresa"
    if "microempresa" in porte_raw.lower(): 
        porte_txt = "microempresa"
    elif "pequeno porte" in porte_raw.lower(): 
        porte_txt = "empresa de pequeno porte"
    elif "demais" in porte_raw.lower(): 
        porte_txt = "empresa de médio/grande porte"
    
    situacao = getattr(cnpj_data_obj, 'situacao_rf', 'ATIVA') if cnpj_data_obj else "ATIVA"
    
    cap_social_val = Decimal(str(cadastro.get('capital_social') or 0.0))
    cap_social_txt = f"R$ {cap_social_val:,.2f}".replace(',', 'X').replace('.', ',').replace('X', '.')

    p_intro_51 = doc.add_paragraph()
    _run(p_intro_51, f'De acordo com informações contidas no Cadastro Nacional de Pessoas Jurídicas da Receita Federal do Brasil (RFB), a seguir detalhada, a Farmácia {razao_social}, localizada no município de {municipio}/{uf}, é uma {porte_txt}, com capital social de ')
    _run(p_intro_51, cap_social_txt, bold=True)
    _run(p_intro_51, ' e com situação ')
    _run(p_intro_51, situacao.upper(), bold=True, underline=True)
    _run(p_intro_51, ':')

    # Adiciona o Quadro 01 (Informações Detalhadas)
    
    # Prepara dicionário para o quadro
    quadro_data = {
        'cnpj_fmt': cnpj_fmt,
        'razao_social': razao_social,
        'nome_fantasia': cadastro.get('nome_fantasia'),
        'natureza_juridica': cadastro.get('natureza_juridica'),
        'id_cnae_principal': cadastro.get('id_cnae_principal'),
        'cnae_principal': cadastro.get('cnae_principal'),
        'id_cnae_secundario': cadastro.get('id_cnae_secundario'),
        'cnae_secundario': cadastro.get('cnae_secundario'),
        'data_abertura': cadastro.get('data_abertura'),
        'situacao_rf': cnpj_data.get('situacao_rf') or 'ATIVA',
        'porte_empresa': cnpj_data.get('porte_empresa') or 'MICROEMPRESA',
        'endereco_completo': endereco,
        'bairro': bairro,
        'municipio': municipio,
        'uf': uf,
        'cep': cep,
        'telefone_1': cadastro.get('telefone_1'),
        'telefone_2': cadastro.get('telefone_2'),
        'email': cadastro.get('email'),
        'data_processamento': cadastro.get('data_processamento'),
        'total_mov': cnpj_data.get('totalMov') or 0.0,
        'socios_ativos': socios_ativos
    }
    # Inicia numeração de footnotes reais a partir de 8 (notas 1-7 estão nos rodapés de seção)
    _add_quadro_identificacao(doc, quadro_data, cap_social_val, periodo_txt)

    # ── 9. Seção 5.2+ (Rodapé nota 11) ──────────────
    sec_52 = doc.add_section(WD_SECTION.CONTINUOUS)
    sec_52.footer.is_linked_to_previous = False
    f_52 = sec_52.footer.paragraphs[0]
    f_52.alignment = WD_ALIGN_PARAGRAPH.LEFT
    _run(f_52, '(11) Disponível em: https://farmaciapopular-gestao.saude.gov.br/farmaciapopular-gestao/pages/login.jsf. Consulta realizada em xx.xx.xxxx.', color='64748B', size=8)
    sec_52.top_margin = Inches(0.5); sec_52.bottom_margin = Inches(0.5)
    sec_52.left_margin = Inches(0.7); sec_52.right_margin = Inches(0.7)

    doc.add_heading('5.2 Informações obtidas no Portal de Gestão do Farmácia Popular', level=2)
    
    # Texto condicional e instrutivo para o auditor
    p_gestao_intro = doc.add_paragraph()
    _run(p_gestao_intro, '(ATENÇÃO: Este item 5.2 só deve ser mantido se o estabelecimento estiver inativo junto ao PFPB. Caso contrário, remova esta seção.)', color='EF4444', size=8, italic=True)
    
    doc.add_paragraph()
    p_gestao_corpo = doc.add_paragraph()
    _run(p_gestao_corpo, f'Identificou-se, por meio de consulta ao Portal de Gestão do Farmácia Popular (Módulo Gestão', color='0F172A', size=10)
    run_sup11 = p_gestao_corpo.add_run('11')
    run_sup11.font.superscript = True
    run_sup11.font.size = Pt(7)
    _run(p_gestao_corpo, f'), que a Farmácia {razao_social} foi colocada na situação de ', color='0F172A', size=10)
    _run(p_gestao_corpo, '“inativa”', color='EF4444', size=10, bold=True)
    _run(p_gestao_corpo, ', em ', color='0F172A', size=10)
    _run(p_gestao_corpo, 'xx.xx.xxxx', color='EF4444', size=10, bold=True)
    _run(p_gestao_corpo, ', por ações de controle e monitoramento especificadas na ', color='0F172A', size=10)
    _run(p_gestao_corpo, 'Nota Técnica nº 786/2024 – CGPFP/DAF/SECTICS/MS e no Ofício nº 3435/2024/CGPFP/DAF/SECTICS/MS', color='EF4444', size=10, bold=True)
    _run(p_gestao_corpo, ', encaminhado à empresa pela Coordenação Geral do Programa Farmácia Popular do Brasil, do Ministério da Saúde. ', color='0F172A', size=10)
    _run(p_gestao_corpo, '(ATENÇÃO: cabe ao auditor checar se não existem documentos mais recentes). ', color='F97316', size=9, bold=True, italic=True)
    _run(p_gestao_corpo, 'Em que pese não ter sido identificados os respectivos documentos anexados informando as causas, bem como as respostas, tal situação reforça a hipótese de funcionamento inadequado ou existência de irregularidades cometidos pelo estabelecimento.', color='0F172A', size=10)

    doc.add_paragraph()
    p_reitera = doc.add_paragraph()
    _run(p_reitera, f'A Farmácia {razao_social} também foi notificada (reiteração) pela Coordenação Geral do Programa Farmácia Popular do Brasil, em ', color='0F172A', size=10)
    _run(p_reitera, 'xx.xx.xxxx', color='EF4444', size=10, bold=True)
    _run(p_reitera, ', em decorrência deste monitoramento, mas a resposta e o ofício de solicitação de informações não foram anexados ao sistema, até a última consulta. ', color='0F172A', size=10)
    _run(p_reitera, '(ATENÇÃO: Somente para casos de reiteração, cabendo ao auditor tal checagem).', color='F97316', size=9, bold=True, italic=True)
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
