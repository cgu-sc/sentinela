import io
import os
import polars as pl
from decimal import Decimal
from datetime import date
from statistics import median
from typing import Any, Optional
from docx import Document
from docx.shared import Emu, Inches, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_TAB_LEADER, WD_TAB_ALIGNMENT
from docx.enum.section import WD_SECTION
from docx.opc.constants import CONTENT_TYPE as CT, RELATIONSHIP_TYPE as RT
from docx.opc.packuri import PackURI
from docx.opc.part import XmlPart
from docx.oxml.ns import qn
from docx.oxml import OxmlElement, parse_xml
from PIL import Image, ImageDraw, ImageFont

from data_cache import get_df, get_df_matriz_risco, get_df_perfil_estabelecimento, get_localidades_df, get_medicamentos_df
from ._cache import _get_cnpj_cache_dir
from .farmacia import get_dados_farmacia
from .dashboard import get_dashboard_data
from .financeiro import get_evolucao_financeira, get_evolucao_mensal_gtin
from .socios import get_socios_farmacia
from .falecidos import get_falecidos_data
from .indicadores import _INDICATOR_FLAGS
from .regional import get_regional_benchmarking


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


def _row_cant_split(row):
    """Evita que uma linha da tabela seja quebrada entre paginas pelo Word."""
    trPr = row._tr.get_or_add_trPr()
    if trPr.find(qn('w:cantSplit')) is None:
        cant_split = OxmlElement('w:cantSplit')
        trPr.append(cant_split)


def _keep_small_table_together(title_para, table, trailing_paragraphs=None):
    """Mantem titulo e tabela curta juntos quando houver espaco na pagina."""
    title_para.paragraph_format.keep_with_next = True
    title_para.paragraph_format.keep_together = True

    table_paragraphs = []
    for row in table.rows:
        _row_cant_split(row)
        for cell in row.cells:
            table_paragraphs.extend(cell.paragraphs)

    for para in table_paragraphs:
        para.paragraph_format.keep_together = True
        para.paragraph_format.keep_with_next = True

    trailing_paragraphs = trailing_paragraphs or []
    for para in trailing_paragraphs:
        para.paragraph_format.keep_together = True
        para.paragraph_format.keep_with_next = True

    if trailing_paragraphs:
        trailing_paragraphs[-1].paragraph_format.keep_with_next = False
    elif table_paragraphs:
        table_paragraphs[-1].paragraph_format.keep_with_next = False


def _risk_color(classificacao: str | None, score: float) -> tuple[str, str]:
    """Retorna (hex_6chars, label) baseado na classificação de risco do sistema."""
    c = (classificacao or '').upper()
    if 'CRÍTICO' in c or 'CRITICO' in c or 'ALTO' in c:
        return '334155', 'CRÍTICO'
    if 'MÉDIO' in c or 'MEDIO' in c or 'ATENÇÃO' in c or 'ATENCAO' in c:
        return 'F97316', 'ATENÇÃO'
    if 'BAIXO' in c or 'NORMAL' in c:
        return '10B981', 'NORMAL'
    if score > 20:
        return '334155', 'CRÍTICO'
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


def _sup_note(para, number: int, *, color: str = '0F172A'):
    """Adiciona numero sobrescrito para nota manual de rodape."""
    run = para.add_run(str(number))
    run.font.superscript = True
    run.font.size = Pt(7)
    run.font.color.rgb = _rgb(color)
    return run


def _get_or_add_footnotes_part(doc):
    """Obtém ou cria a parte XML de footnotes reais do Word."""
    try:
        return doc.part.part_related_by(RT.FOOTNOTES)
    except KeyError:
        xml = (
            '<w:footnotes xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
            '<w:footnote w:type="separator" w:id="-1"><w:p><w:r><w:separator/></w:r></w:p></w:footnote>'
            '<w:footnote w:type="continuationSeparator" w:id="0"><w:p><w:r><w:continuationSeparator/></w:r></w:p></w:footnote>'
            '</w:footnotes>'
        )
        part = XmlPart(
            PackURI('/word/footnotes.xml'),
            CT.WML_FOOTNOTES,
            parse_xml(xml),
            doc.part.package,
        )
        doc.part.relate_to(part, RT.FOOTNOTES)
        return part


def _ensure_footnote(doc, number: int, text: str):
    """Garante a existencia de uma nota de rodape numerada."""
    part = _get_or_add_footnotes_part(doc)
    footnotes = part.element
    for existing in footnotes.findall(qn('w:footnote')):
        if existing.get(qn('w:id')) == str(number):
            return

    footnote = OxmlElement('w:footnote')
    footnote.set(qn('w:id'), str(number))
    p = OxmlElement('w:p')
    p_pr = OxmlElement('w:pPr')
    p_style = OxmlElement('w:pStyle')
    p_style.set(qn('w:val'), 'FootnoteText')
    spacing = OxmlElement('w:spacing')
    spacing.set(qn('w:before'), '0')
    spacing.set(qn('w:after'), '0')
    spacing.set(qn('w:line'), '240')
    spacing.set(qn('w:lineRule'), 'auto')
    p_pr.append(p_style)
    p_pr.append(spacing)
    p.append(p_pr)

    r_ref = OxmlElement('w:r')
    r_ref_pr = OxmlElement('w:rPr')
    r_ref_style = OxmlElement('w:rStyle')
    r_ref_style.set(qn('w:val'), 'FootnoteReference')
    r_ref_vert = OxmlElement('w:vertAlign')
    r_ref_vert.set(qn('w:val'), 'superscript')
    r_ref_size = OxmlElement('w:sz')
    r_ref_size.set(qn('w:val'), '20')
    r_ref_pr.append(r_ref_style)
    r_ref_pr.append(r_ref_vert)
    r_ref_pr.append(r_ref_size)
    r_ref.append(r_ref_pr)
    r_ref_note = OxmlElement('w:footnoteRef')
    r_ref.append(r_ref_note)
    p.append(r_ref)

    r_text = OxmlElement('w:r')
    r_text_pr = OxmlElement('w:rPr')
    r_text_size = OxmlElement('w:sz')
    r_text_size.set(qn('w:val'), '16')
    r_text_pr.append(r_text_size)
    r_text.append(r_text_pr)
    t = OxmlElement('w:t')
    t.set('{http://www.w3.org/XML/1998/namespace}space', 'preserve')
    t.text = f' {text}'
    r_text.append(t)
    p.append(r_text)

    footnote.append(p)
    footnotes.append(footnote)


def _footnote_ref(doc, para, number: int, text: str):
    """Insere referência de footnote real e garante seu texto."""
    _ensure_footnote(doc, number, text)
    run = para.add_run()
    r = run._r
    r_pr = r.get_or_add_rPr()
    r_style = OxmlElement('w:rStyle')
    r_style.set(qn('w:val'), 'FootnoteReference')
    r_pr.append(r_style)
    r_vert = OxmlElement('w:vertAlign')
    r_vert.set(qn('w:val'), 'superscript')
    r_pr.append(r_vert)
    r_size = OxmlElement('w:sz')
    r_size.set(qn('w:val'), '20')
    r_pr.append(r_size)
    ref = OxmlElement('w:footnoteReference')
    ref.set(qn('w:id'), str(number))
    r.append(ref)
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


def _format_decimal_pt(value: float, decimals: int = 2) -> str:
    """Formata numero decimal no padrao brasileiro."""
    return f"{value:,.{decimals}f}".replace(',', 'X').replace('.', ',').replace('X', '.')


def _format_month_year_pt(month_key: str) -> str:
    """Formata uma chave mensal YYYY-MM como MM/YYYY."""
    parts = str(month_key or "").split("-")
    if len(parts) != 2:
        return str(month_key or "—")
    year, month = parts
    if len(year) != 4 or len(month) != 2:
        return str(month_key or "—")
    return f"{month}/{year}"


def _format_month_year_long_pt(month_key: str) -> str:
    """Formata uma chave mensal YYYY-MM como mes por extenso e ano."""
    month_names = {
        "01": "janeiro",
        "02": "fevereiro",
        "03": "março",
        "04": "abril",
        "05": "maio",
        "06": "junho",
        "07": "julho",
        "08": "agosto",
        "09": "setembro",
        "10": "outubro",
        "11": "novembro",
        "12": "dezembro",
    }
    parts = str(month_key or "").split("-")
    if len(parts) != 2:
        return str(month_key or "—")
    year, month = parts
    month_name = month_names.get(month)
    if len(year) != 4 or month_name is None:
        return str(month_key or "—")
    return f"{month_name} de {year}"


def _format_date_month_year_long_pt(value: date) -> str:
    """Formata uma data como mes por extenso e ano."""
    return _format_month_year_long_pt(f"{value.year:04d}-{value.month:02d}")


def _format_semestre_pt(semestre: str) -> str:
    """Formata labels como 1S/2021 para 1º Semestre/2021."""
    label = str(semestre or "").strip()
    if len(label) >= 7 and label[0] in {"1", "2"} and label[1].upper() == "S" and label[2] == "/":
        return f"{label[0]}º Semestre/{label[3:]}"
    return label


def _semester_key_from_date(value: date) -> int:
    semestre = 1 if value.month <= 6 else 2
    return value.year * 100 + semestre


def _semester_key_from_label(semestre: str) -> int | None:
    label = str(semestre or "").strip()
    if len(label) >= 7 and label[0] in {"1", "2"} and label[1].upper() == "S" and label[2] == "/":
        try:
            return int(label[3:]) * 100 + int(label[0])
        except ValueError:
            return None
    if "-S" in label:
        year, sem = label.split("-S", 1)
        try:
            return int(year) * 100 + int(sem[:1])
        except ValueError:
            return None
    return None


def _semester_distance(start_key: int, end_key: int) -> int:
    start_year, start_sem = divmod(start_key, 100)
    end_year, end_sem = divmod(end_key, 100)
    return (end_year - start_year) * 2 + (end_sem - start_sem)


def _format_list_pt(items: list[str]) -> str:
    """Formata lista em portugues: A, B e C."""
    unique_items = list(dict.fromkeys(item for item in items if item))
    if not unique_items:
        raise RuntimeError("Lista de municipios obrigatoria para comparacao regional da Nota Tecnica.")
    if len(unique_items) == 1:
        return unique_items[0]
    if len(unique_items) == 2:
        return f"{unique_items[0]} e {unique_items[1]}"
    return f"{', '.join(unique_items[:-1])} e {unique_items[-1]}"


def _hex_rgb(hex_color: str) -> tuple[int, int, int]:
    """Converte cor hexadecimal para RGB."""
    clean = hex_color.strip().lstrip("#")
    return int(clean[0:2], 16), int(clean[2:4], 16), int(clean[4:6], 16)


def _load_chart_font(size: int, *, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    """Carrega fonte do sistema para graficos da Nota Tecnica."""
    candidates = [
        r"C:\Windows\Fonts\seguisb.ttf" if bold else r"C:\Windows\Fonts\segoeui.ttf",
        r"C:\Windows\Fonts\arialbd.ttf" if bold else r"C:\Windows\Fonts\arial.ttf",
    ]
    for path in candidates:
        if os.path.exists(path):
            return ImageFont.truetype(path, size=size)
    return ImageFont.load_default()


def _text_size(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.ImageFont) -> tuple[int, int]:
    """Mede texto em pixels com compatibilidade entre versoes do Pillow."""
    bbox = draw.textbbox((0, 0), text, font=font)
    return bbox[2] - bbox[0], bbox[3] - bbox[1]


def _draw_dashed_line(
    draw: ImageDraw.ImageDraw,
    start: tuple[int, int],
    end: tuple[int, int],
    *,
    fill: tuple[int, int, int, int],
    width: int = 2,
    dash: int = 12,
    gap: int = 10,
):
    """Desenha linha horizontal tracejada."""
    x1, y1 = start
    x2, y2 = end
    x = x1
    while x < x2:
        draw.line((x, y1, min(x + dash, x2), y2), fill=fill, width=width)
        x += dash + gap


def _draw_rotated_text(
    image: Image.Image,
    text: str,
    center: tuple[int, int],
    *,
    font: ImageFont.ImageFont,
    fill: tuple[int, int, int],
    angle: int = -38,
):
    """Desenha texto rotacionado com ancoragem central."""
    temp = Image.new("RGBA", (360, 90), (255, 255, 255, 0))
    temp_draw = ImageDraw.Draw(temp)
    text_w, text_h = _text_size(temp_draw, text, font)
    temp_draw.text(((temp.width - text_w) // 2, (temp.height - text_h) // 2), text, fill=(*fill, 255), font=font)
    rotated = temp.rotate(angle, expand=True, resample=Image.Resampling.BICUBIC)
    x = center[0] - rotated.width // 2
    y = center[1] - rotated.height // 2
    image.alpha_composite(rotated, (x, y))


def _axis_currency_label(value: float) -> str:
    """Formata valores compactos para eixo financeiro."""
    if value >= 1_000_000:
        return f'R$ {_format_decimal_pt(value / 1_000_000, 1)} mi'
    if value >= 1_000:
        return f'R$ {_format_decimal_pt(value / 1_000, 0)} mil'
    return f'R$ {_format_decimal_pt(value, 0)}'


def _nice_axis_max(value: float) -> float:
    """Calcula limite superior arredondado para o eixo Y."""
    if value <= 0:
        return 1.0
    magnitude = 10 ** (len(str(int(value))) - 1)
    normalized = value / magnitude
    if normalized <= 1:
        nice = 1
    elif normalized <= 2:
        nice = 2
    elif normalized <= 5:
        nice = 5
    else:
        nice = 10
    return nice * magnitude


def _draw_gradient_rect(
    image: Image.Image,
    box: tuple[int, int, int, int],
    *,
    top_color: str,
    bottom_color: str,
    radius: int = 0,
    top_only: bool = False,
):
    """Desenha retangulo vertical com gradiente e cantos opcionais."""
    x1, y1, x2, y2 = box
    width = max(1, x2 - x1)
    height = max(1, y2 - y1)
    top = _hex_rgb(top_color)
    bottom = _hex_rgb(bottom_color)

    gradient = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    grad_draw = ImageDraw.Draw(gradient)
    for y in range(height):
        ratio = y / max(height - 1, 1)
        color = tuple(int(top[i] * (1 - ratio) + bottom[i] * ratio) for i in range(3))
        grad_draw.line((0, y, width, y), fill=(*color, 255))

    mask = Image.new("L", (width, height), 0)
    mask_draw = ImageDraw.Draw(mask)
    if radius > 0:
        mask_draw.rounded_rectangle((0, 0, width, height), radius=radius, fill=255)
        if top_only:
            mask_draw.rectangle((0, min(radius, height), width, height), fill=255)
    else:
        mask_draw.rectangle((0, 0, width, height), fill=255)
    gradient.putalpha(mask)
    image.alpha_composite(gradient, (x1, y1))


def _build_evolucao_financeira_chart(evolucao_comp: dict[str, Any]) -> io.BytesIO:
    """Gera grafico PNG de evolucao financeira no estilo visual do ECharts."""
    rows = evolucao_comp["rows"]
    width, height = 1800, 900
    left, right, top, bottom = 165, 75, 120, 210
    plot_w = width - left - right
    plot_h = height - top - bottom
    plot_bottom = top + plot_h

    img = Image.new("RGBA", (width, height), (255, 255, 255, 255))
    draw = ImageDraw.Draw(img)

    font_title = _load_chart_font(34, bold=True)
    font_axis = _load_chart_font(24)
    font_axis_bold = _load_chart_font(20, bold=True)
    font_small = _load_chart_font(20)
    text_color = _hex_rgb("0F172A")
    muted = _hex_rgb("64748B")
    grid = (15, 23, 42, 24)
    regular_top = "34D399"
    regular_bottom = "10B981"
    irregular_top = "F43F5E"
    irregular_bottom = "E11D48"

    title = "Evolução semestral das transferências e vendas sem comprovação"
    title_w, _ = _text_size(draw, title, font_title)
    draw.text(((width - title_w) // 2, 34), title, fill=text_color, font=font_title)

    legend_y = 83
    legend_items = [
        ("Vendas regulares", regular_top, regular_bottom),
        ("Vendas sem comprovação", irregular_top, irregular_bottom),
    ]
    legend_total_w = 0
    for label, _, _ in legend_items:
        label_w, _ = _text_size(draw, label, font_small)
        legend_total_w += 34 + 10 + label_w + 36
    legend_x = (width - legend_total_w) // 2
    for label, top_c, bottom_c in legend_items:
        _draw_gradient_rect(img, (legend_x, legend_y + 4, legend_x + 34, legend_y + 22), top_color=top_c, bottom_color=bottom_c, radius=7)
        draw.text((legend_x + 44, legend_y), label, fill=muted, font=font_small)
        label_w, _ = _text_size(draw, label, font_small)
        legend_x += 34 + 10 + label_w + 36

    max_total = max(float(row["total"]) for row in rows)
    axis_max = _nice_axis_max(max_total * 1.10)
    tick_count = 5
    for idx in range(tick_count + 1):
        value = axis_max * idx / tick_count
        y = int(plot_bottom - (value / axis_max) * plot_h)
        _draw_dashed_line(draw, (left, y), (width - right, y), fill=grid, width=2)
        label = _axis_currency_label(value)
        label_w, label_h = _text_size(draw, label, font_axis)
        draw.text((left - label_w - 18, y - label_h // 2), label, fill=muted, font=font_axis)

    n = len(rows)
    slot = plot_w / max(n, 1)
    bar_w = int(min(58, max(22, slot * 0.58)))
    radius = max(8, min(18, bar_w // 3))

    for idx, row in enumerate(rows):
        center_x = int(left + slot * idx + slot / 2)
        x1 = center_x - bar_w // 2
        x2 = center_x + bar_w // 2
        regular = max(float(row["regular"]), 0.0)
        irregular = max(float(row["irregular"]), 0.0)
        total = max(float(row["total"]), 0.0)
        if total <= 0:
            continue

        total_h = max(2, int((total / axis_max) * plot_h))
        regular_h = int((regular / axis_max) * plot_h)
        irregular_h = max(0, total_h - regular_h)
        y_total = plot_bottom - total_h
        y_regular = plot_bottom - regular_h

        if regular_h > 0:
            regular_radius = radius if irregular_h == 0 else 0
            _draw_gradient_rect(
                img,
                (x1, y_regular, x2, plot_bottom),
                top_color=regular_top,
                bottom_color=regular_bottom,
                radius=regular_radius,
                top_only=irregular_h == 0,
            )
        if irregular_h > 0:
            _draw_gradient_rect(
                img,
                (x1, y_total, x2, y_regular),
                top_color=irregular_top,
                bottom_color=irregular_bottom,
                radius=radius,
                top_only=True,
            )

        label = row.get("semestre_fmt") or row["semestre"]
        _draw_rotated_text(
            img,
            label,
            (center_x + 9, plot_bottom + 54),
            font=font_axis_bold,
            fill=muted,
            angle=-38,
        )

    img = img.convert("RGB")
    stream = io.BytesIO()
    img.save(stream, format="PNG", optimize=True)
    stream.seek(0)
    return stream


def _add_figura_evolucao_financeira(doc, razao_social: str, cnpj_fmt: str, evolucao_comp: dict[str, Any]):
    """Insere figura da evolucao financeira no documento."""
    p_title = doc.add_paragraph()
    p_title.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p_title.paragraph_format.keep_with_next = True
    p_title.paragraph_format.keep_together = True
    _run(
        p_title,
        f'Figura 01 - Evolução semestral dos recursos recebidos e das “vendas sem comprovação” da Farmácia {razao_social} (CNPJ {cnpj_fmt}).',
        color='0F172A',
        size=10,
        bold=True,
    )

    chart_stream = _build_evolucao_financeira_chart(evolucao_comp)
    p_img = doc.add_paragraph()
    p_img.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p_img.paragraph_format.keep_with_next = False
    p_img.paragraph_format.keep_together = True
    run = p_img.add_run()
    run.add_picture(chart_stream, width=Inches(7.1))


def _resolve_regional_context(cadastro: dict) -> dict[str, Any]:
    """Resolve id_regiao_saude a partir do id_ibge7 cadastral da farmacia."""
    id_ibge7 = cadastro.get("id_ibge7")
    if id_ibge7 in (None, "", "None"):
        raise RuntimeError("id_ibge7 e obrigatorio para resolver a Regiao de Saude da Nota Tecnica.")

    df_loc = get_localidades_df()
    required_cols = {"id_ibge7", "id_regiao_saude", "sg_uf"}
    missing_cols = required_cols - set(df_loc.columns)
    if missing_cols:
        raise RuntimeError(
            f"Cache de localidades sem colunas obrigatorias para Nota Tecnica: {', '.join(sorted(missing_cols))}."
        )

    rows = df_loc.filter(pl.col("id_ibge7").cast(pl.String) == str(id_ibge7))
    if rows.is_empty():
        raise RuntimeError(f"id_ibge7 {id_ibge7} nao encontrado no cache de localidades.")

    row = rows.row(0, named=True)
    id_regiao_saude = row.get("id_regiao_saude")
    uf = row.get("sg_uf")
    if id_regiao_saude in (None, "", "None") or not uf:
        raise RuntimeError(f"Localidade {id_ibge7} sem id_regiao_saude/UF obrigatorios para Nota Tecnica.")

    nome_regiao = row.get("no_regiao_saude") or f"ID {id_regiao_saude}"

    return {
        "id_regiao_saude": int(id_regiao_saude),
        "uf": str(uf),
        "nome_regiao": str(nome_regiao),
    }


def _build_regional_comparison_context(
    cnpj_data: dict,
    cadastro: dict,
    data_inicio: Optional[date],
    data_fim: Optional[date],
) -> dict[str, Any]:
    """Calcula comparacao do percentual do CNPJ contra a mediana regional no periodo."""
    regional_context = _resolve_regional_context(cadastro)
    regional = get_regional_benchmarking(
        uf=regional_context["uf"],
        data_inicio=data_inicio,
        data_fim=data_fim,
        regiao_id=regional_context["id_regiao_saude"],
    )

    if not regional.farmacias:
        raise RuntimeError("Benchmarking regional sem farmacias para o periodo da Nota Tecnica.")

    percentual_cnpj = cnpj_data.get("percValSemComp")
    if percentual_cnpj is None:
        raise RuntimeError("percValSemComp e obrigatorio para comparacao regional da Nota Tecnica.")

    percentuais_regionais = [
        float(f.percValSemComp)
        for f in regional.farmacias
        if f.percValSemComp is not None
    ]
    if not percentuais_regionais:
        raise RuntimeError("Percentuais regionais obrigatorios ausentes para comparacao da Nota Tecnica.")

    mediana_regional = float(median(percentuais_regionais))
    if mediana_regional <= 0:
        raise RuntimeError("Mediana regional deve ser maior que zero para calcular o multiplicador da Nota Tecnica.")

    municipios = [m.municipio for m in regional.municipios if m.municipio]
    if not municipios:
        raise RuntimeError("Municipios regionais obrigatorios ausentes para comparacao da Nota Tecnica.")

    uf_comp = _build_scope_percentual_comparison(cnpj_data, data_inicio, data_fim, uf=regional_context["uf"])
    br_comp = _build_scope_percentual_comparison(cnpj_data, data_inicio, data_fim)

    return {
        **regional_context,
        "multiplicador": float(percentual_cnpj) / mediana_regional,
        "mediana_regional": mediana_regional,
        "qtd_farmacias": len(regional.farmacias),
        "municipios": municipios,
        "multiplicador_uf": uf_comp["multiplicador"],
        "mediana_uf": uf_comp["mediana"],
        "multiplicador_brasil": br_comp["multiplicador"],
        "mediana_brasil": br_comp["mediana"],
    }


def _build_scope_percentual_comparison(
    cnpj_data: dict,
    data_inicio: Optional[date],
    data_fim: Optional[date],
    *,
    uf: Optional[str] = None,
) -> dict[str, float]:
    """Calcula mediana de percentual sem comprovacao para UF ou Brasil no periodo."""
    percentual_cnpj = cnpj_data.get("percValSemComp")
    if percentual_cnpj is None:
        raise RuntimeError("percValSemComp e obrigatorio para comparacao geografica da Nota Tecnica.")

    df = get_df().join(get_df_perfil_estabelecimento(), on="id_cnpj", how="left")
    min_data = date(2015, 7, 1)
    max_data = date(2024, 12, 31)
    inicio = (data_inicio if data_inicio and data_inicio >= min_data else min_data) if data_inicio else min_data
    fim = data_fim if data_fim else max_data

    mask = pl.col("periodo").is_between(inicio, fim)
    if uf:
        mask = mask & (pl.col("uf") == uf)

    scoped = df.filter(mask)
    if scoped.is_empty():
        label = f"UF {uf}" if uf else "Brasil"
        raise RuntimeError(f"Sem movimentacao para calcular mediana de {label} da Nota Tecnica.")

    cnpj_agg = (
        scoped
        .group_by("id_cnpj")
        .agg([
            pl.sum("total_vendas").alias("totalMov"),
            pl.sum("total_sem_comprovacao").alias("valSemComp"),
        ])
        .with_columns(
            (
                pl.col("valSemComp") /
                pl.when(pl.col("totalMov") > 0)
                .then(pl.col("totalMov"))
                .otherwise(None) * 100
            ).alias("percValSemComp")
        )
        .filter(pl.col("percValSemComp").is_not_null())
    )
    if cnpj_agg.is_empty():
        label = f"UF {uf}" if uf else "Brasil"
        raise RuntimeError(f"Percentuais ausentes para calcular mediana de {label} da Nota Tecnica.")

    mediana = float(cnpj_agg.get_column("percValSemComp").median() or 0.0)
    if mediana <= 0:
        label = f"UF {uf}" if uf else "Brasil"
        raise RuntimeError(f"Mediana de {label} deve ser maior que zero para calcular o multiplicador da Nota Tecnica.")

    return {
        "mediana": mediana,
        "multiplicador": float(percentual_cnpj) / mediana,
    }


def _normalize_gtin(value: Any) -> str:
    """Normaliza GTIN/codigo de barras preservando zeros quando vier como texto."""
    text = str(value).strip()
    return text.split(".")[0] if "." in text else text


def _build_medicamentos_lookup() -> dict[str, str]:
    """Monta lookup GTIN -> descricao obrigatoria do medicamento."""
    df_med = get_medicamentos_df()
    required_cols = {"codigo_barra"}
    missing_cols = required_cols - set(df_med.columns)
    if missing_cols:
        raise RuntimeError(
            f"Cache de medicamentos sem colunas obrigatorias para Nota Tecnica: {', '.join(sorted(missing_cols))}."
        )

    lookup: dict[str, str] = {}
    for row in df_med.iter_rows(named=True):
        codigo = row.get("codigo_barra")
        if codigo in (None, "", "None"):
            continue
        descricao = row.get("principio_ativo") or row.get("produto") or row.get("descricao")
        if descricao in (None, "", "None"):
            continue
        gtin = _normalize_gtin(codigo)
        lookup[gtin] = str(descricao)

    if not lookup:
        raise RuntimeError("Cache de medicamentos sem descricoes validas para Nota Tecnica.")
    return lookup


def _build_gtin_sem_comprovacao_context(
    cnpj: str,
    data_inicio: Optional[date],
    data_fim: Optional[date],
    concentration_target: float = 0.80,
) -> dict[str, Any]:
    """Agrega todos os GTINs com valor sem comprovacao no periodo e calcula concentracao."""
    get_evolucao_mensal_gtin(cnpj, data_inicio, data_fim)

    parquet_path = os.path.join(_get_cnpj_cache_dir(cnpj), "movimentacao_mensal_gtin.parquet")
    if not os.path.exists(parquet_path):
        raise RuntimeError(f"Parquet mensal por GTIN obrigatorio nao encontrado para Nota Tecnica: {parquet_path}.")

    df = pl.read_parquet(parquet_path)
    required_cols = {
        "codigo_barra",
        "periodo",
        "qnt_vendas_sem_comprovacao",
        "valor_sem_comprovacao",
    }
    missing_cols = required_cols - set(df.columns)
    if missing_cols:
        raise RuntimeError(
            f"Parquet mensal por GTIN sem colunas obrigatorias para Nota Tecnica: {', '.join(sorted(missing_cols))}."
        )

    df = df.with_columns([
        pl.col("codigo_barra").cast(pl.String),
        pl.col("periodo").cast(pl.Date),
        pl.col("qnt_vendas_sem_comprovacao").cast(pl.Int64, strict=False).fill_null(0),
        pl.col("valor_sem_comprovacao").cast(pl.Float64, strict=False).fill_null(0.0),
    ])
    if data_inicio:
        df = df.filter(pl.col("periodo") >= pl.lit(data_inicio).cast(pl.Date))
    if data_fim:
        df = df.filter(pl.col("periodo") <= pl.lit(data_fim).cast(pl.Date))

    if df.is_empty():
        raise RuntimeError("Movimentacao mensal por GTIN vazia no periodo da Nota Tecnica.")

    agg = (
        df.group_by("codigo_barra")
        .agg([
            pl.sum("qnt_vendas_sem_comprovacao").alias("qtd_sem_comprovacao"),
            pl.sum("valor_sem_comprovacao").alias("valor_sem_comprovacao"),
        ])
        .filter(pl.col("valor_sem_comprovacao") > 0)
        .sort("valor_sem_comprovacao", descending=True)
    )
    if agg.is_empty():
        raise RuntimeError("Nenhum GTIN com valor sem comprovacao encontrado no periodo da Nota Tecnica.")

    medicamentos_lookup = _build_medicamentos_lookup()
    rows: list[dict[str, Any]] = []
    missing_descriptions: list[str] = []
    for r in agg.iter_rows(named=True):
        gtin = _normalize_gtin(r["codigo_barra"])
        descricao = medicamentos_lookup.get(gtin)
        if not descricao:
            missing_descriptions.append(gtin)
            continue
        rows.append({
            "gtin": gtin,
            "descricao": descricao,
            "qtd_sem_comprovacao": int(r["qtd_sem_comprovacao"] or 0),
            "valor_sem_comprovacao": round(float(r["valor_sem_comprovacao"] or 0.0), 2),
        })

    if missing_descriptions:
        preview = ", ".join(missing_descriptions[:10])
        raise RuntimeError(f"Descricao obrigatoria ausente para GTIN(s) da Nota Tecnica: {preview}.")
    if not rows:
        raise RuntimeError("Lista de GTINs sem comprovacao vazia apos enriquecimento de medicamentos.")

    total_valor = round(sum(r["valor_sem_comprovacao"] for r in rows), 2)
    total_qtd = sum(r["qtd_sem_comprovacao"] for r in rows)
    target_value = total_valor * concentration_target
    acumulado = 0.0
    representativos_count = 0
    for row in rows:
        if acumulado >= target_value and representativos_count > 0:
            break
        acumulado += row["valor_sem_comprovacao"]
        representativos_count += 1

    representativos_valor = round(acumulado, 2)
    representativos_pct = (representativos_valor / total_valor * 100) if total_valor > 0 else 0.0

    return {
        "rows": rows,
        "total_gtins": len(rows),
        "total_qtd": total_qtd,
        "total_valor": total_valor,
        "representativos_count": representativos_count,
        "representativos_valor": representativos_valor,
        "representativos_pct": representativos_pct,
        "concentration_target_pct": concentration_target * 100,
    }


def _model_to_dict(model: Any) -> dict[str, Any]:
    """Converte modelos Pydantic ou dicts em dicionario simples."""
    if isinstance(model, dict):
        return model
    if hasattr(model, "model_dump"):
        return model.model_dump()
    if hasattr(model, "dict"):
        return model.dict()
    raise TypeError(f"Objeto semestral inesperado para Nota Tecnica: {type(model)!r}.")


def _build_ultimo_mes_sav_context(
    cnpj: str,
    data_inicio: Optional[date],
    data_fim: Optional[date],
) -> dict[str, Any]:
    """Identifica o ultimo mes com vendas no SAV dentro do periodo analisado."""
    evolucao = get_evolucao_financeira(cnpj, data_inicio, data_fim)
    semestres_raw = getattr(evolucao, "semestres", None)
    if semestres_raw is None:
        raise RuntimeError("Resposta de evolucao financeira sem campo semestres para Nota Tecnica.")

    meses: list[dict[str, Any]] = []
    for sem in semestres_raw:
        sem_item = _model_to_dict(sem)
        for mes in sem_item.get("meses") or []:
            mes_item = _model_to_dict(mes)
            if mes_item.get("mes"):
                meses.append(mes_item)

    if not meses:
        raise RuntimeError("Evolucao financeira mensal obrigatoria vazia para Nota Tecnica.")

    ultimo_mes = max(meses, key=lambda item: str(item.get("mes") or ""))
    total = float(ultimo_mes.get("total") or 0.0)
    return {
        "mes": str(ultimo_mes["mes"]),
        "mes_formatado": _format_month_year_pt(str(ultimo_mes["mes"])),
        "total": round(total, 2),
    }


def _build_evolucao_financeira_context(
    cnpj: str,
    data_inicio: Optional[date],
    data_fim: Optional[date],
    growth_threshold_pct: float = 50.0,
) -> dict[str, Any]:
    """Monta a evolucao financeira semestral e identifica saltos relevantes."""
    evolucao = get_evolucao_financeira(cnpj, data_inicio, data_fim)
    semestres_raw = getattr(evolucao, "semestres", None)
    if semestres_raw is None:
        raise RuntimeError("Resposta de evolucao financeira sem campo semestres para Nota Tecnica.")
    if not semestres_raw:
        raise RuntimeError("Evolucao financeira obrigatoria vazia para Nota Tecnica.")

    rows: list[dict[str, Any]] = []
    for sem in semestres_raw:
        item = _model_to_dict(sem)
        for col in ("semestre", "total", "regular", "irregular", "pct_irregular"):
            if col not in item:
                raise RuntimeError(f"Evolucao financeira sem coluna obrigatoria para Nota Tecnica: {col}.")
        total = float(item["total"] or 0.0)
        irregular = float(item["irregular"] or 0.0)
        regular = float(item["regular"] or 0.0)
        pct_irregular = float(item["pct_irregular"] or 0.0)
        semestre = str(item["semestre"])
        taxa_crescimento_raw = item.get("taxa_crescimento_pct")
        limite_volume_atipico_raw = item.get("limite_volume_atipico_pct")
        chave_semestre = item.get("chave_semestre") or _semester_key_from_label(semestre)
        rows.append({
            "semestre": semestre,
            "semestre_fmt": _format_semestre_pt(semestre),
            "chave_semestre": int(chave_semestre) if chave_semestre is not None else None,
            "mes_inicio": item.get("mes_inicio"),
            "mes_fim": item.get("mes_fim"),
            "total": round(total, 2),
            "regular": round(regular, 2),
            "irregular": round(irregular, 2),
            "pct_irregular": round(pct_irregular, 2),
            "volume_atipico": bool(item.get("volume_atipico")),
            "taxa_crescimento_pct": round(float(taxa_crescimento_raw), 2) if taxa_crescimento_raw is not None else None,
            "chave_semestre_anterior": item.get("chave_semestre_anterior"),
            "limite_volume_atipico_pct": float(limite_volume_atipico_raw) if limite_volume_atipico_raw is not None else None,
        })

    if not rows:
        raise RuntimeError("Evolucao financeira sem linhas validas para Nota Tecnica.")

    total_geral = round(sum(row["total"] for row in rows), 2)
    irregular_geral = round(sum(row["irregular"] for row in rows), 2)
    regular_geral = round(sum(row["regular"] for row in rows), 2)
    pct_irregular_geral = (irregular_geral / total_geral * 100) if total_geral > 0 else 0.0

    semestres_atipicos = [row for row in rows if row["volume_atipico"]]
    limites_volume_atipico = [
        row["limite_volume_atipico_pct"]
        for row in rows
        if row["limite_volume_atipico_pct"] is not None
    ]
    limite_volume_atipico = limites_volume_atipico[0] if limites_volume_atipico else growth_threshold_pct

    semestres_irregulares = [
        row for row in rows
        if row["irregular"] > 0
    ]
    top_irregulares = sorted(semestres_irregulares, key=lambda row: row["irregular"], reverse=True)[:3]
    primeiro_mes = rows[0].get("mes_inicio")
    ultimo_mes = rows[-1].get("mes_fim")
    periodo_meses = (
        f'{_format_month_year_long_pt(primeiro_mes)} a {_format_month_year_long_pt(ultimo_mes)}'
        if primeiro_mes and ultimo_mes
        else (
            rows[0]["semestre_fmt"] if rows[0]["semestre"] == rows[-1]["semestre"]
            else f'{rows[0]["semestre_fmt"]} a {rows[-1]["semestre_fmt"]}'
        )
    )

    return {
        "rows": rows,
        "total": total_geral,
        "regular": regular_geral,
        "irregular": irregular_geral,
        "pct_irregular": pct_irregular_geral,
        "primeiro_semestre": rows[0]["semestre"],
        "ultimo_semestre": rows[-1]["semestre"],
        "primeiro_semestre_fmt": rows[0]["semestre_fmt"],
        "ultimo_semestre_fmt": rows[-1]["semestre_fmt"],
        "periodo_semestres": (
            rows[0]["semestre_fmt"] if rows[0]["semestre"] == rows[-1]["semestre"]
            else f'{rows[0]["semestre_fmt"]} a {rows[-1]["semestre_fmt"]}'
        ),
        "periodo_meses": periodo_meses,
        "growth_threshold_pct": limite_volume_atipico,
        "crescimento_relevante": semestres_atipicos,
        "semestres_atipicos": semestres_atipicos,
        "top_irregulares": top_irregulares,
    }


def _build_socios_volume_atipico_context(
    socios_ativos: list[Any],
    evolucao_comp: dict[str, Any],
    max_semestres_apos_entrada: int = 2,
) -> list[dict[str, Any]]:
    """Identifica aumentos atipicos proximos ao ingresso de socios ativos."""
    semestres_atipicos = evolucao_comp.get("semestres_atipicos") or []
    matches: list[dict[str, Any]] = []

    for socio in socios_ativos:
        entrada = getattr(socio, "data_entrada_sociedade", None)
        if not entrada:
            continue

        entrada_key = _semester_key_from_date(entrada)
        nome = getattr(socio, "nome_socio", None) or "sócio não identificado"

        for semestre in semestres_atipicos:
            semestre_key = semestre.get("chave_semestre") or _semester_key_from_label(semestre.get("semestre"))
            if semestre_key is None:
                continue

            distancia = _semester_distance(entrada_key, int(semestre_key))
            if 0 <= distancia <= max_semestres_apos_entrada:
                matches.append({
                    "nome_socio": nome,
                    "entrada": entrada,
                    "entrada_txt": _format_date_month_year_long_pt(entrada),
                    "semestre_fmt": semestre.get("semestre_fmt") or _format_semestre_pt(semestre.get("semestre")),
                    "taxa_crescimento_pct": semestre.get("taxa_crescimento_pct"),
                    "distancia_semestres": distancia,
                })

    return sorted(matches, key=lambda item: (item["entrada"], item["distancia_semestres"], item["nome_socio"]))


def _add_quadro_socios_volume_atipico(doc, socios_volume_atipico: list[dict[str, Any]]):
    """Adiciona quadro com ingressos societarios proximos a aumentos atipicos."""
    if not socios_volume_atipico:
        return

    p_title = doc.add_paragraph()
    p_title.alignment = WD_ALIGN_PARAGRAPH.CENTER
    _run(
        p_title,
        'Quadro 06 - Ingressos societários próximos a semestres com aumento atípico das transferências',
        color='0F172A',
        size=10,
        bold=True,
    )

    table = doc.add_table(rows=len(socios_volume_atipico) + 1, cols=5)
    table.style = 'Table Grid'

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

        values = [
            item.get("nome_socio") or '—',
            item.get("entrada_txt") or '—',
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
    p_title.alignment = WD_ALIGN_PARAGRAPH.CENTER
    _run(
        p_title,
        'Quadro 03 - Comparativo do percentual de vendas sem comprovação da farmácia auditada em relação à Região de Saúde',
        color='0F172A',
        size=10,
        bold=True,
    )

    table = doc.add_table(rows=5, cols=2)
    table.style = 'Table Grid'

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

    _keep_small_table_together(p_title, table)

    p_foot = doc.add_paragraph()
    _run(p_foot, f'Fonte: Sistema Sentinela, com base no SAV/PFPB e em NF-e, no período analisado ({periodo_txt}).', color='64748B', size=8)


def _add_quadro_gtins_sem_comprovacao(doc, razao_social: str, cnpj_fmt: str, gtin_comp: dict[str, Any], periodo_txt: str):
    """Adiciona quadro com todos os GTINs com vendas sem comprovacao no periodo."""
    p_title = doc.add_paragraph()
    p_title.alignment = WD_ALIGN_PARAGRAPH.CENTER
    _run(
        p_title,
        f'Quadro 04 - Relação de medicamentos supostamente distribuídos pela Farmácia {razao_social} (CNPJ {cnpj_fmt}) sem estoques amparados em notas fiscais de suas aquisições, no período de {periodo_txt}.',
        color='0F172A',
        size=10,
        bold=True,
    )

    rows_data = gtin_comp["rows"]
    table = doc.add_table(rows=len(rows_data) + 2, cols=4)
    table.style = 'Table Grid'

    headers = [
        'GTIN/Código de Barras',
        'Descrição',
        'Quantidade de vendas sem comprovação',
        'Valor em venda sem comprovação (R$)',
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
        _run(cells[3].paragraphs[0], _format_decimal_pt(item["valor_sem_comprovacao"], 2), color='0F172A', size=8)

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
    _run(p_foot, f'Fonte: informações acerca das dispensações informadas mensalmente pelas farmácias no Sistema Autorizador de Vendas do PFPB, no período de {periodo_txt}.', color='64748B', size=8)


def _add_quadro_evolucao_financeira(
    doc,
    razao_social: str,
    cnpj_fmt: str,
    evolucao_comp: dict[str, Any],
):
    """Adiciona quadro semestral de transferencias e vendas sem comprovacao."""
    p_title = doc.add_paragraph()
    p_title.alignment = WD_ALIGN_PARAGRAPH.CENTER
    _run(
        p_title,
        f'Quadro 05 - Recebimento de recursos do Ministério da Saúde e “vendas sem comprovação” relativas à Farmácia {razao_social} (CNPJ {cnpj_fmt}), no período de {evolucao_comp["periodo_semestres"]}.',
        color='0F172A',
        size=10,
        bold=True,
    )

    rows_data = evolucao_comp["rows"]
    table = doc.add_table(rows=len(rows_data) + 2, cols=6)
    table.style = 'Table Grid'

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
        if item.get("volume_atipico") and item.get("taxa_crescimento_pct") is not None:
            _run(
                cells[5].paragraphs[0],
                f'+{_format_decimal_pt(item["taxa_crescimento_pct"], 1)}%',
                color='334155',
                size=8,
                bold=True,
            )
        else:
            _run(cells[5].paragraphs[0], '-', color='64748B', size=8)

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

    p_obs = doc.add_paragraph()
    _run(
        p_obs,
        'Obs. De acordo com o SIAFI, esta empresa possui a conta bancária: xxxxx-x, agência: xxxx, banco: xxx. Informação pendente de integração/fonte.',
        color='334155',
        size=8,
        bold=True,
    )

    p_foot = doc.add_paragraph()
    _run(
        p_foot,
        'Fonte: Sistema Sentinela, aba “Evolução Financeira”, a partir das dispensações informadas no Sistema Autorizador de Vendas do PFPB e do levantamento de “vendas sem comprovação”.',
        color='64748B',
        size=8,
    )
    _keep_small_table_together(p_title, table, [p_obs, p_foot])


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


def _build_falecidos_context(
    cnpj: str,
    uf_farmacia: str | None,
    data_inicio: Optional[date],
    data_fim: Optional[date],
) -> dict[str, Any] | None:
    """Agrega transacoes de falecidos para a Nota Tecnica quando houver dados."""
    try:
        falecidos = get_falecidos_data(cnpj, data_inicio, data_fim)
    except Exception as exc:
        print(f"[NOTA_TECNICA] Falecidos indisponivel para {cnpj}: {exc}")
        return None

    transacoes = getattr(falecidos, "transacoes", None) or []
    if not transacoes:
        return None

    summary = getattr(falecidos, "summary", None)
    total_autorizacoes = int(getattr(summary, "total_autorizacoes", len(transacoes)) or 0)
    cpfs_distintos = int(getattr(summary, "cpfs_distintos", 0) or 0)
    valor_total = float(getattr(summary, "valor_total", 0.0) or 0.0)

    cpfs = {
        getattr(t, "cpf", None)
        for t in transacoes
        if getattr(t, "cpf", None)
    }
    if cpfs:
        cpfs_distintos = len(cpfs)

    datas = [
        getattr(t, "data_autorizacao", None)
        for t in transacoes
        if getattr(t, "data_autorizacao", None)
    ]
    inicio_ref = data_inicio or (min(datas) if datas else None)
    fim_ref = data_fim or (max(datas) if datas else None)
    if inicio_ref and fim_ref:
        periodo_desc = (
            f'no ano de {inicio_ref.year}'
            if inicio_ref.year == fim_ref.year
            else f'no período de {inicio_ref.year} a {fim_ref.year}'
        )
    elif inicio_ref:
        periodo_desc = f'a partir de {inicio_ref.year}'
    elif fim_ref:
        periodo_desc = f'até {fim_ref.year}'
    else:
        periodo_desc = 'no período analisado'

    return {
        "total_autorizacoes": total_autorizacoes,
        "cpfs_distintos": cpfs_distintos,
        "valor_total": valor_total,
        "periodo_desc": periodo_desc,
    }


def _add_falecidos_criticidade_text(doc, num: str, razao_social: str, falecidos_comp: dict[str, Any]):
    """Adiciona texto analitico de vendas para pessoas falecidas."""
    total_autorizacoes = falecidos_comp["total_autorizacoes"]
    cpfs_distintos = falecidos_comp["cpfs_distintos"]
    valor_total = falecidos_comp["valor_total"]
    periodo_desc = falecidos_comp["periodo_desc"]

    doc.add_heading(f'{num} Vendas de medicamento para pessoas falecidas', level=2)
    p1 = doc.add_paragraph()
    _run(p1, f'Em análise a informações contidas no Sistema Autorizador de Vendas (SAV) do PFPB, lançados pela Farmácia {razao_social} {periodo_desc}, foram identificados registros de vendas (distribuição) de medicamentos para pessoas na data de seus óbitos e/ou posteriormente a essa data, identificados nas bases de dados do SIRC', color='0F172A', size=10)
    _footnote_ref(
        doc,
        p1,
        14,
        'O Sistema Nacional de Informações de Registro Civil (Sirc) é uma base de governo federal que tem por finalidade captar, processar, arquivar e disponibilizar dados relativos a registros de nascimento, casamento, óbito e natimorto, produzidos pelos cartórios de registro civil das pessoas naturais. Sistema disponível em: https://sirc.gov.br/o-que-e/.',
    )
    _run(p1, ' e SISOBI', color='0F172A', size=10)
    _footnote_ref(
        doc,
        p1,
        15,
        'O Sistema de Controle de Óbitos (Sisobi) é ainda utilizado pelos cartórios para tratamento de certidões anteriores à implantação do Sistema Nacional de Informações de Registro Civil (Sirc). Sistema disponível em: https://www.dataprev.gov.br/sisobi/.',
    )
    _run(p1, '. Foram realizadas ', color='0F172A', size=10)
    _run(p1, f'{total_autorizacoes:,}'.replace(',', '.'), color='334155', size=10, bold=True)
    _run(p1, ' vendas em data posterior ao registro de morte de ', color='0F172A', size=10)
    _run(p1, f'{cpfs_distintos:,}'.replace(',', '.'), color='334155', size=10, bold=True)
    _run(p1, ' beneficiários. Estas vendas representaram um valor total de ', color='0F172A', size=10)
    _run(p1, f'R$ {_format_decimal_pt(valor_total, 2)}', color='334155', size=10, bold=True)
    _run(p1, ', no referido período.', color='0F172A', size=10)


def _configure_section(section, footer_lines: list[str] | None = None):
    """Configura margens e rodape independente para uma secao."""
    section.footer.is_linked_to_previous = False
    section.top_margin = Inches(0.5)
    section.bottom_margin = Inches(0.5)
    section.left_margin = Inches(0.7)
    section.right_margin = Inches(0.7)

    footer = section.footer.paragraphs[0]
    footer.alignment = WD_ALIGN_PARAGRAPH.LEFT
    footer.text = ''
    for idx, line in enumerate(footer_lines or []):
        if idx > 0:
            footer.add_run('\n')
        _run(footer, line, color='64748B', size=8)


def _start_section(doc, *, footer_lines: list[str] | None = None, start=WD_SECTION.CONTINUOUS):
    """Inicia uma secao com rodape proprio."""
    section = doc.add_section(start)
    _configure_section(section, footer_lines)
    return section


def _iter_criticidade_items(
    criticos: set[str],
    razao_social: str,
    *,
    start_index: int = 1,
    exclude_keys: set[str] | None = None,
) -> list[tuple[str, str, str]]:
    """Retorna criticidades criticas com numeracao da secao 7."""
    items: list[tuple[str, str, str]] = []
    exclude_keys = exclude_keys or set()
    for key, _, title in _SECAO5_MAP:
        if key in exclude_keys or key not in criticos:
            continue
        full_title = title.format(farmacia=razao_social) if '{farmacia}' in title else title
        items.append((key, f'7.{start_index + len(items)}', full_title))
    return items


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


def _build_sumario(doc, criticos: set[str], razao_social: str, cnpj_fmt: str, has_falecidos: bool = False):
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

    _add_toc_entry(doc, '5.', f'SOBRE A FARMÁCIA {razao_social} (CNPJ {cnpj_fmt})', page='6')
    _add_toc_entry(doc, '  5.1', f'Informações sobre a Farmácia {razao_social} (CNPJ {cnpj_fmt})', page='6')
    _add_toc_entry(doc, '6.', f'SOBRE “VENDAS SEM COMPROVAÇÃO” REALIZADAS PELA FARMÁCIA {razao_social}', page='6')
    _add_toc_entry(doc, '  6.1', f'Evolução das transferências do Programa Farmácia Popular do Brasil para a Farmácia {razao_social} e das possíveis “vendas sem comprovação” por ela realizadas', page='6')

    _add_toc_entry(doc, '7.', f'SOBRE OUTRAS CRITICIDADES RELATIVAS À FARMÁCIA {razao_social}, NO ÂMBITO DO PFPB', page='7')
    if has_falecidos:
        _add_toc_entry(doc, '  7.1', 'Vendas de medicamento para pessoas falecidas', page='7')
    criticidade_start = 2 if has_falecidos else 1
    for _, num, full_title in _iter_criticidade_items(criticos, razao_social, start_index=criticidade_start, exclude_keys={'falecidos'}):
        _add_toc_entry(doc, f'  {num}', full_title, page='7')

    _add_toc_entry(doc, '8.', 'CONCLUSÃO E ENCAMINHAMENTO', page='8')
    doc.add_page_break()


def _add_quadro_identificacao(doc, data: dict, capital_social: Decimal, periodo_txt: str):
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
    cap_social_dec = Decimal(str(capital_social))
    relacao_pct = (total_mov / cap_social_dec * 100) if capital_social > 0 else 0
    vezes = (total_mov / cap_social_dec) if capital_social > 0 else 0
    
    p_nota = doc.add_paragraph()
    p_nota.paragraph_format.space_before = Pt(6)
    relacao_txt = f"{relacao_pct:,.2f}%".replace(',', 'X').replace('.', ',').replace('X', '.')
    total_mov_txt = f"R$ {total_mov:,.2f}".replace(',', 'X').replace('.', ',').replace('X', '.')
    _run(p_nota, f"* A relação do valor de vendas no âmbito do PFPB sobre o capital social é de {relacao_txt}, ou seja, ela recebeu ", color='475569', size=8)
    _run(p_nota, total_mov_txt, color='0F172A', size=8, bold=True)
    _run(p_nota, f" do Programa, no período de {periodo_txt}, o que corresponde ", color='475569', size=8)
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
    _run(p_rais, '. Contudo, apenas ', color='0F172A', size=10)
    _run(p_rais, 'x', color='334155', size=10, bold=True)
    _run(p_rais, ' funcionário(s) consta(m) nos anos de ', color='0F172A', size=10)
    _run(p_rais, '20XX, 20YY e 20ZZ', color='334155', size=10, bold=True)
    _run(p_rais, ', período em que, conforme será visto mais adiante, a transferência de recursos aumentou de forma relevante.', color='0F172A', size=10)

    p_esocial = doc.add_paragraph()
    p_esocial.paragraph_format.space_before = Pt(6)
    _run(p_esocial, 'Destaca-se, também, o fato de que a legislação', color='0F172A', size=10)
    _footnote_ref(doc, p_esocial, 9, nota_farmaceutica_9)
    _run(p_esocial, ' sobre o exercício e a fiscalização das atividades farmacêuticas dispõe que a farmácia e a drogaria terão, obrigatoriamente, a responsabilidade e a assistência técnica de farmacêutico habilitado durante todo o horário de funcionamento do estabelecimento. Assim sendo, fica evidenciado mais uma possível irregularidade, pois em consulta ao eSocial', color='0F172A', size=10)
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
    p_title.alignment = WD_ALIGN_PARAGRAPH.CENTER
    _run(p_title, f'Quadro 02 – Dispensações de medicamentos, informadas no Sistema Autorizador de Vendas (SAV) pela Farmácia {razao_social} (CNPJ {cnpj_fmt}), sem comprovação de Notas Fiscais de aquisições.', color='0F172A', size=10, bold=True)
    
    table = doc.add_table(rows=4, cols=3)
    table.style = 'Table Grid'
    
    hdr_cells = table.rows[0].cells
    _run(hdr_cells[0].paragraphs[0], 'Situação', bold=True)
    _run(hdr_cells[1].paragraphs[0], 'Valor em R$', bold=True)
    _run(hdr_cells[2].paragraphs[0], 'Quantidades de Medicamentos', bold=True)
    
    for cell in hdr_cells:
        cell.paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.CENTER
        _cell_bg(cell, 'E2E8F0')

    r1 = table.rows[1].cells
    _run(r1[0].paragraphs[0], 'Dispensações totais informadas no SAV pela farmácia *')
    _run(r1[1].paragraphs[0], f'{cnpj_data.get("totalMov", 0):,.2f}'.replace(',', 'X').replace('.', ',').replace('X', '.'))
    _run(r1[2].paragraphs[0], f'{cnpj_data.get("totalQtde", 0):,.0f}'.replace(',', '.'))
    
    r2 = table.rows[2].cells
    _run(r2[0].paragraphs[0], 'Valor sem comprovação distribuído (R$) *')
    _run(r2[1].paragraphs[0], f'{cnpj_data.get("valSemComp", 0):,.2f}'.replace(',', 'X').replace('.', ',').replace('X', '.'))
    _run(r2[2].paragraphs[0], f'{cnpj_data.get("qtdeSemComp", 0):,.0f}'.replace(',', '.'))

    r3 = table.rows[3].cells
    _run(r3[0].paragraphs[0], '% de vendas no Programa Farmácia Popular sem comprovação *')
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
    p_foot.alignment = WD_ALIGN_PARAGRAPH.LEFT
    _run(p_foot, f'* Correspondente ao período {periodo_txt}.\n', color='64748B', size=8)
    _run(p_foot, 'Fonte: Relatório de Autorizações Consolidadas, emitido pelo Departamento de Assistência Farmacêutica - DAF/SCTICS/MS, e base de dados das notas fiscais eletrônicas (NF-e), mantida pela Receita Federal do Brasil.', color='64748B', size=8)
    _keep_small_table_together(p_title, table, [p_foot])


# ── Geração do documento ─────────────────────────────────────────────────────

def generate_nota_tecnica(db, cnpj: str, data_inicio: Optional[date] = None, data_fim: Optional[date] = None):
    """Gera a Nota Técnica Preliminar em formato .docx."""

    # 1. Coleta de dados
    cadastro_obj = get_dados_farmacia(cnpj)
    cadastro = cadastro_obj.model_dump() if cadastro_obj is not None else {}

    resumo = get_dashboard_data(db, data_inicio, data_fim, cnpjs=[cnpj])
    cnpj_data_obj = resumo.resultado_cnpjs[0] if hasattr(resumo, 'resultado_cnpjs') and resumo.resultado_cnpjs else None
    cnpj_data = cnpj_data_obj.model_dump() if cnpj_data_obj is not None else {}

    # Coleta de sócios
    socios_res = get_socios_farmacia(cnpj)
    socios_ativos = [s for s in socios_res.socios if not s.data_exclusao_sociedade]

    # 2. Campos derivados
    razao_social = (cadastro.get('razao_social') or cnpj_data.get('razao_social') or 'NÃO INFORMADO').upper()
    municipio = cnpj_data.get('municipio') or cadastro.get('municipio') or '—'
    uf = cnpj_data.get('uf') or cadastro.get('uf') or '—'
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

    falecidos_comp = _build_falecidos_context(cnpj, uf, data_inicio, data_fim)

    # 3. Documento e margens
    doc = Document()
    style_normal: Any = doc.styles['Normal']
    style_normal.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
    
    # Aplica o tema Grafite Médio (Slate 700) para as Seções/Títulos
    for i in range(1, 4):
        try:
            style_heading: Any = doc.styles[f'Heading {i}']
            style_heading.font.color.rgb = RGBColor(0x33, 0x41, 0x55)
        except Exception:
            pass

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
    tbl_resumo.columns[1].width = Emu(PAGE_W - Inches(4.5))
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
    _build_sumario(doc, criticos, razao_social, cnpj_fmt, has_falecidos=bool(falecidos_comp))

    # ── 5. Seção 2: Assunto e Referências (Rodapé 1) ────────────────────
    sec_ref = doc.add_section(WD_SECTION.CONTINUOUS)
    sec_ref.footer.is_linked_to_previous = False
    sec_ref.footer.paragraphs[0].text = ''
    
    sec_ref.top_margin = Inches(0.5); sec_ref.bottom_margin = Inches(0.5)
    sec_ref.left_margin = Inches(0.7); sec_ref.right_margin = Inches(0.7)

    # 1. ASSUNTO
    doc.add_heading('1. ASSUNTO', level=1)
    doc.add_paragraph(f'A presente Nota Técnica (NT), de caráter investigativo e sigiloso, tem como objetivo demonstrar indícios de fraudes cometidas pela Farmácia {razao_social} (CNPJ {cnpj_fmt}), credenciada junto ao Programa Farmácia Popular do Brasil (PFPB) do Ministério da Saúde (MS) para a dispensação gratuita de medicamentos para cidadãos.')

    # 2. REFERÊNCIAS
    h2 = doc.add_heading('2. REFERÊNCIAS', level=1)
    _footnote_ref(
        doc,
        h2,
        1,
        'De acordo com informações contidas no site do Ministério da Saúde a respeito do Programa Farmácia Popular do Brasil: '
        'https://www.gov.br/saude/pt-br/composicao/sectics/farmacia-popular/legislacao '
        f'(acessado em {date.today().strftime("%d/%m/%Y")}).',
    )
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
    
    snippets = [f'[Subitem 6.1] evolução atípica das transferências do Programa e das possíveis “vendas sem comprovação” realizadas pela Farmácia {razao_social}']
    criticidade_start = 1
    if falecidos_comp:
        snippets.append('[Subitem 7.1] vendas de medicamento para pessoas falecidas')
        criticidade_start = 2
    for _, num, full_title in _iter_criticidade_items(criticos, razao_social, start_index=criticidade_start, exclude_keys={'falecidos'}):
        snippets.append(f'[Subitem {num}] {full_title[:1].lower()}{full_title[1:]}')
    
    texto_snippets = (", ".join(snippets[:-1]) + " e " + snippets[-1]) if len(snippets) > 1 else snippets[0]
    doc.add_paragraph(f'Além disso, a presente NT revela criticidades que corroboram com o achado principal de “vendas sem comprovação”, como {texto_snippets}.')
    doc.add_paragraph('A NT traz ainda análise da empresa em relação aos seus sócios, capital social, porte, situação cadastral junto à Receita Federal do Brasil e junto ao PFPB e compatibilidade entre o número de empregados e volume de recursos recebidos do MS.')

    fontes = ['Cadastro Nacional de Pessoas Jurídicas (CNPJ) e Cadastro de Pessoa Física (CPF) da Receita Federal do Brasil', 'Relação Anual de Informações Sociais (RAIS) do Ministério do Trabalho e Emprego', 'Sistema de Escrituração Digital das Obrigações Fiscais, Previdenciárias e Trabalhistas (eSocial)', 'Sistema Integrado de Administração Financeira do Governo Federal (SIAFI)']
    if 'polimedicamento' in criticos or 'teto' in criticos: fontes.append('[Item 7] dados demográficos oficiais fornecidos pelo Instituto Brasileiro de Geografia e Estatística (IBGE)')
    if falecidos_comp: fontes.append('[Subitem 7.1] SIRC e SISOBI')
    if any(k in criticos for k in ['hhi_crm', 'exclusividade_crm', 'crms_irregulares']): fontes.append('[Item 7] Cadastros de médicos do Conselho Regional de Medicina (CRM)')
    doc.add_paragraph(f'Os achados advindos das análises realizadas, consignados no item 5 desta Nota Técnica, tomaram por base informações registradas pela Farmácia {razao_social} no Sistema Autorizador de Vendas (SAV) do Programa Farmácia Popular do Brasil e cópias de notas fiscais eletrônicas relativas à aquisição de medicamentos por parte das farmácias que aderiram ao Programa, compartilhadas pela Receita Federal do Brasil. Além dessas informações, foram utilizados dados extraídos das seguintes fontes: {"; ".join(fontes)}.')

    nota_pfpb_2 = (
        'Consulta ao site https://www.gov.br/saude/pt-br/composicao/sectics/farmacia-popular, '
        f'em {date.today().strftime("%d/%m/%Y")}.'
    )
    nota_pfpb_3 = (
        'A lista dos medicamentos e produtos do PFPB, atualizada em 02.09.2025, pode ser obtida no endereço: '
        'https://www.gov.br/saude/pt-br/composicao/sectics/farmacia-popular/arquivos/elenco-de-medicamentos-e-insumos.pdf'
    )
    nota_pfpb_4 = (
        'Após um intervalo sem a renovação anual obrigatória do credenciamento desde 2018, conforme o artigo 15 '
        'do Anexo LXXVII da Portaria de Consolidação nº 5, de 28 de setembro de 2017, o Ministério da Saúde '
        'reabriu a necessidade a partir de 17 de abril de 2025.'
    )
    nota_pfpb_5 = (
        'Cabe informar que existia também a modalidade de copagamento (em que o beneficiário arcava com uma parte '
        'do custo), que foi extinta após a edição da Portaria GM/MS nº 6.613, de 13.02.2025.'
    )
    nota_pfpb_6 = (
        'A Portaria GM/MS nº 111/2016, substituída pela Portaria GM/MS nº 2.898/2021, determinava em seu art. 22 '
        'que o estabelecimento deveria manter por cinco anos.'
    )

    # ── 7. Seção 4.1: Sobre o Programa ─────────────────────────────────────
    sec_41 = doc.add_section(WD_SECTION.CONTINUOUS)
    sec_41.footer.is_linked_to_previous = False
    sec_41.footer.paragraphs[0].text = ''
    sec_41.top_margin = Inches(0.5); sec_41.bottom_margin = Inches(0.5)
    sec_41.left_margin = Inches(0.7); sec_41.right_margin = Inches(0.7)

    # 4. SÍNTESE
    doc.add_heading('4. SÍNTESE DO PROGRAMA FARMÁCIA POPULAR DO BRASIL E DA METODOLOGIA DESENVOLVIDA PELA CGU PARA SEU MONITORAMENTO', level=1)
    doc.add_heading('4.1. Sobre o Programa Farmácia Popular do Brasil', level=2)
    p_intro_41 = doc.add_paragraph(
        'O Programa Farmácia Popular do Brasil, instituído em 2004 para ampliar o acesso a medicamentos essenciais, '
        'consolidou-se como um pilar da saúde pública brasileira. Segundo site do Ministério da Saúde'
    )
    _footnote_ref(doc, p_intro_41, 2, nota_pfpb_2)
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
    _footnote_ref(doc, p_quote2, 3, nota_pfpb_3)
    p_quote2.add_run('.')
    for run in p_quote2.runs:
        if not run.font.superscript: run.font.size = Pt(10)

    p_op = doc.add_paragraph('A operacionalização do programa ocorre com a participação de drogarias credenciadas pelo Ministério da Saúde (MS)')
    _footnote_ref(doc, p_op, 4, nota_pfpb_4)
    p_op.add_run(', que realizam a dispensação gratuita de medicamentos diretamente aos cidadãos. As drogarias são posteriormente ressarcidas pela União, de acordo com informações relativas às quantidades distribuídas de cada medicamento')
    _footnote_ref(doc, p_op, 5, nota_pfpb_5)
    p_op.add_run('.')

    p_sav = doc.add_paragraph('As informações acerca da dispensação são encaminhadas pelas drogarias credenciadas ao MS mensalmente por meio do Sistema Autorizador de Vendas (SAV), conforme disposto na Portaria de Consolidação GM/MS nº 5, de 28.09.2017, e anteriores. Por sua vez, o art. 22 da Portaria GM/MS nº 2.898, de 03.11.2021, dispõe que o estabelecimento deve manter por 10 (dez) anos')
    _footnote_ref(doc, p_sav, 6, nota_pfpb_6)
    p_sav.add_run(', em ordem cronológica de emissão, duas cópias mantidas em locais distintos, uma em meio físico e outra em arquivo digitalizado, dos cupons vinculados assinados, dos documentos fiscais, das prescrições, dos laudos ou atestados médicos e dos documentos de identidade oficial apresentados no ato da compra e, ainda, dos documentos fiscais de aquisição dos respectivos medicamentos e/ou fraldas geriátricas dispensados no âmbito do PFPB.')

    nota_cgu_7 = (
        'A CGU, em seu Relatório de Auditoria nº 823121, considerou "vendas sem comprovação" no âmbito do PFPB '
        'a diferença identificada por princípio ativo/insumo, após o batimento entre Notas Fiscais de entrada '
        '(compartilhadas pela Receita Federal do Brasil e relativas a aquisições de medicamentos do PFPB) e registro '
        'de saída no Sistema Autorizador de Vendas – SAV (onde as dispensações subsidiadas são informadas), tendo '
        'como elo os números que constam abaixo dos códigos de barra (Código GTIN).'
    )

    # ── 8. Seção 4.2: Metodologia CGU ───────────────────────────────────────
    sec_42 = doc.add_section(WD_SECTION.CONTINUOUS)
    sec_42.footer.is_linked_to_previous = False
    sec_42.footer.paragraphs[0].text = ''
    sec_42.top_margin = Inches(0.5); sec_42.bottom_margin = Inches(0.5)
    sec_42.left_margin = Inches(0.7); sec_42.right_margin = Inches(0.7)

    doc.add_heading('4.2. Sobre metodologia desenvolvida pela CGU para apuração de possíveis "vendas sem comprovação"', level=2)
    doc.add_paragraph('O crescimento exponencial do PFPB, com gastos que saltaram de R$ 34,7 milhões em 2006 para patamares próximos a R$ 6 bilhões em 2025, impôs desafios complexos ao controle governamental, dada a imensa capilaridade de mais de 30 mil estabelecimentos credenciados.')
    p_sent = doc.add_paragraph('Para enfrentar essa realidade, a CGU elaborou o ')
    p_sent.add_run('Relatório de Apuração nº 823121').bold = True
    p_sent.add_run(' (ANEXO I desta NT), fundamentado no desenvolvimento do ')
    p_sent.add_run('Sistema Sentinela').bold = True
    p_sent.add_run(', uma ferramenta de tecnologia da informação que automatiza o cruzamento de dados, em larga escala, do SAV com outras bases de informações.')
    p_cgu = doc.add_paragraph('De forma sintética, a premissa central de controle adotada pela CGU, apresentada de forma detalhada no referido relatório, é de natureza lógica e contábil: um estabelecimento não pode dispensar medicamentos que não adquiriu formalmente. Uma vez isto ocorrendo, a Farmácia estaria praticando uma “venda sem comprovação”')
    _footnote_ref(doc, p_cgu, 7, nota_cgu_7)
    p_cgu.add_run(', ou seja, uma distribuição de medicamentos para cidadãos, cobrada do Ministério da Saúde, sem comprovação de suas aquisições.')
    doc.add_paragraph('Para a aferição da regularidade das dispensações realizadas pelas farmácias, é necessário estimar um estoque inicial dos medicamentos para que seja possível, a partir desta informação e de suas compras posteriores, verificar a compatibilidade de suas vendas no âmbito do PFPB. Dada a limitação do SAV, de não existência de informação disponível sobre o estoque inicial de medicamentos de cada drogaria credenciada pelo MS, a CGU desenvolveu metodologia em que confronta as informações de vendas de medicamentos enviadas pelas farmácias ao Ministério da Saúde com as informações de suas compras contidas na base da Receita Federal do Brasil de Notas Fiscais Eletrônicas (NF-e), utilizada tanto para estimar seus estoques iniciais quanto para aferir a compatibilidade destes e suas compras posteriores com as vendas realizadas no âmbito do Programa.')
    p_cutoff = doc.add_paragraph('A metodologia técnica do Sistema Sentinela foi desenhada de forma conservadora para garantir a robustez dos achados. O sistema utiliza a técnica de ')
    p_cutoff.add_run('cut-off').italic = True
    p_cutoff.add_run(', estimando o estoque inicial como a soma das duas últimas compras anteriores à primeira venda registrada de cada medicamento. A partir desse ponto, o algoritmo realiza um balanço diário de entradas e saídas, considerando apenas as vendas do programa PFPB como débito no estoque e ignorando vendas privadas para o público geral, o que gera um saldo "virtual" favorável à farmácia. Em outras palavras, o conservadorismo da metodologia da CGU se ampara no fato de considerar, para os cálculos de estoque, que todos os medicamentos adquiridos pela farmácia, que fazem parte do rol do PFPB, somente foram vendidos para clientes que fizeram uso do Programa, ou seja, a metodologia não leva em conta a possibilidade real de que parte desses medicamentos tenha sido vendida para clientes comuns, que desembolsaram recursos próprios para suas aquisições.')

    p_gtin = doc.add_paragraph('Juridicamente, o controle sustenta-se na Portaria de Consolidação GM/MS nº 05/2017, que obriga a guarda das notas fiscais de aquisição por dez anos, e no Ajuste SINIEF nº 16/2010, que exige a identificação do produto pelo código ')
    p_gtin.add_run('GTIN/EAN').bold = True
    p_gtin.add_run('. Nesse sentido, reforça-se que a descrição textual do produto é insuficiente para a liquidação da despesa, sendo o código de barras a única chave capaz de vincular com precisão o medicamento comprado ao preço de referência pago pelo governo.')
    doc.add_paragraph('Além do levantamento de valores de “Vendas sem Comprovação” para todos as empresas que operam no PFPB, o Sistema Sentinela extrai dos dados do Sistema Autorizador de Vendas (SAV) do Programa uma série de informações que permitem apontar para outras criticidades que corroboram com a suspeita de possíveis registros fictícios de dispensações de medicamentos por parte dos estabelecimentos.')
    doc.add_paragraph(f'A seguir, são apresentadas informações sobre a Farmácia {razao_social} e o resultado das análises dos alertas para ela extraídos do Sistema Sentinela, tanto em relação a possíveis “vendas sem comprovação” quanto a outras criticidades que corroboram com este achado principal.')

    # ── Seção 5 intro (sem rodapé) ────────────────────────────────────────
    sec_5_intro = doc.add_section(WD_SECTION.CONTINUOUS)
    sec_5_intro.footer.is_linked_to_previous = False
    sec_5_intro.top_margin = Inches(0.5); sec_5_intro.bottom_margin = Inches(0.5)
    sec_5_intro.left_margin = Inches(0.7); sec_5_intro.right_margin = Inches(0.7)

    # 5. SOBRE A FARMACIA
    doc.add_heading(f'5. SOBRE A FARMÁCIA {razao_social} (CNPJ {cnpj_fmt})', level=1)
    ultimo_mes_sav = _build_ultimo_mes_sav_context(cnpj, data_inicio, data_fim)
    situacao_pfpb = "ATIVA" if cnpj_data.get("is_conexao_ativa") else "INATIVA"
    p_sav_5 = doc.add_paragraph(
        f'Informações extraídas do SAV, relativas ao período de {periodo_txt}, apontam que a Farmácia {razao_social} '
        'se encontra “'
    )
    _run(p_sav_5, situacao_pfpb, bold=True)
    _run(p_sav_5, '” no Programa Farmácia Popular do Brasil, tendo realizado vendas totais de ')
    _run(p_sav_5, f'R$ {_format_decimal_pt(ultimo_mes_sav["total"], 2)}', underline=True)
    _run(p_sav_5, ' em ')
    _run(p_sav_5, ultimo_mes_sav["mes_formatado"], underline=True)
    _run(p_sav_5, ', último mês com movimentação disponível para a Farmácia na base de dados.')

    # ── Seção de informações cadastrais ────────────────────────────────────
    sec_51 = doc.add_section(WD_SECTION.CONTINUOUS)
    sec_51.footer.is_linked_to_previous = False
    sec_51.footer.paragraphs[0].text = ''
    sec_51.top_margin = Inches(0.5); sec_51.bottom_margin = Inches(0.5)
    sec_51.left_margin = Inches(0.7); sec_51.right_margin = Inches(0.7)

    # Mapeamento do porte conforme padrões RFB/Filtros
    porte_raw = getattr(cnpj_data_obj, 'porte_empresa', 'ND') if cnpj_data_obj else "ND"
    porte_txt = "empresa"
    porte_lower = porte_raw.lower()
    if "microempresa" in porte_lower:
        porte_txt = "microempresa"
    elif "pequeno porte" in porte_lower:
        porte_txt = "empresa de pequeno porte"
    elif "médio" in porte_lower or "medio" in porte_lower:
        porte_txt = "empresa de médio porte"
    elif "grande" in porte_lower:
        porte_txt = "empresa de grande porte"
    elif "demais" in porte_lower:
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

    # ── 10. Seção 6 (rodapé limpo até o comparativo regional) ────────────────
    _start_section(doc)

    doc.add_heading(f'6. SOBRE “VENDAS SEM COMPROVAÇÃO” REALIZADAS PELA FARMÁCIA {razao_social}.', level=1)
    p_53 = doc.add_paragraph()
    _run(p_53, f'Em relação à Farmácia {razao_social}, verificou-se, conforme detalhamento contido no ANEXO II desta Nota Técnica, diferenças relevantes entre os estoques de medicamentos estimados e suas distribuições para os cidadãos subsidiadas pelo Programa Farmácia Popular do Brasil, ', color='0F172A', size=10)
    
    if data_inicio and data_fim:
        _run(p_53, 'no período de ', color='0F172A', size=10)
        _run(p_53, periodo_txt, color='0F172A', size=10, bold=True)
        _run(p_53, '. ', color='0F172A', size=10)
    else:
        _run(p_53, 'no período avaliado (', color='0F172A', size=10)
        _run(p_53, periodo_txt, color='0F172A', size=10, bold=True)
        _run(p_53, '). ', color='0F172A', size=10)
    _run(p_53, 'O quadro, a seguir, consolida os valores apurados para todas as dispensações de medicamentos realizadas pelo estabelecimento:', color='0F172A', size=10)
        
    _add_quadro_53(doc, razao_social, cnpj_fmt, cnpj_data, periodo_txt)
    
    p_conclusao_53 = doc.add_paragraph()
    _run(p_conclusao_53, f'Depreende-se do quadro anterior que a quantidade de dispensações de medicamentos informadas pela Farmácia {razao_social} no sistema SAV não se encontra compatível com seus estoques, contabilizado de acordo a metodologia adotada pela CGU, o que levou a estimativa de não comprovação de vendas no percentual de ', color='0F172A', size=10)
    
    perc_fmt = f"{cnpj_data.get('percValSemComp', 0):.2f}%".replace('.', ',')
    val_fmt = f"{cnpj_data.get('valSemComp', 0):,.2f}".replace(',', 'X').replace('.', ',').replace('X', '.')
    
    _run(p_conclusao_53, perc_fmt, color='334155', size=10, bold=True)
    _run(p_conclusao_53, ', que corresponde a um potencial desvio de recursos públicos no montante estimado de ', color='0F172A', size=10)
    _run(p_conclusao_53, f'R$ {val_fmt}', color='334155', size=10, bold=True)
    _run(p_conclusao_53, '.', color='0F172A', size=10)

    regional_comp = _build_regional_comparison_context(cnpj_data, cadastro, data_inicio, data_fim)
    multiplicador_fmt = _format_decimal_pt(regional_comp["multiplicador"], 2)
    multiplicador_uf_fmt = _format_decimal_pt(regional_comp["multiplicador_uf"], 2)
    multiplicador_brasil_fmt = _format_decimal_pt(regional_comp["multiplicador_brasil"], 2)
    qtd_farmacias = regional_comp["qtd_farmacias"]
    farmacia_txt = "farmácia" if qtd_farmacias == 1 else "farmácias"
    que_opera_txt = "que opera" if qtd_farmacias == 1 else "que operam"
    municipios_txt = _format_list_pt(regional_comp["municipios"])

    p_regional_53 = doc.add_paragraph()
    _run(p_regional_53, 'Tal percentual é ', color='0F172A', size=10)
    _run(p_regional_53, f'{multiplicador_fmt} vezes', color='334155', size=10, bold=True)
    _run(p_regional_53, ' a mediana dos percentuais de “vendas sem comprovação” das farmácias da sua região', color='0F172A', size=10)
    _footnote_ref(
        doc,
        p_regional_53,
        11,
        'A região de saúde utilizada para os comparativos do Sistema Sentinela segue a mesma estabelecida pelo Sistema Único de Saúde (ver https://www.gov.br/saude/pt-br/se/dgip/regionalizacao), que, em resumo, a considera como um espaço geográfico contínuo, formado pelo agrupamento de municípios limítrofes, que compartilham características culturais, econômicas e sociais semelhantes.',
    )
    _run(p_regional_53, ', que contempla ', color='0F172A', size=10)
    _run(p_regional_53, f'{qtd_farmacias} {farmacia_txt}', color='0F172A', size=10, bold=True)
    _run(p_regional_53, f' {que_opera_txt} no PFPB, localizadas nos seguintes municípios do Estado ({regional_comp["uf"]}): {municipios_txt}.', color='0F172A', size=10)

    p_geo_ampliado = doc.add_paragraph()
    _run(p_geo_ampliado, 'Ampliando-se o comparativo geográfico, o percentual é ', color='0F172A', size=10)
    _run(p_geo_ampliado, f'{multiplicador_uf_fmt} vezes', color='334155', size=10, bold=True)
    _run(p_geo_ampliado, f' a mediana dos percentuais de “vendas sem comprovação” das farmácias localizadas em seu Estado ({regional_comp["uf"]}) e ', color='0F172A', size=10)
    _run(p_geo_ampliado, f'{multiplicador_brasil_fmt} vezes', color='334155', size=10, bold=True)
    _run(p_geo_ampliado, ' a das farmácias de todo o Brasil.', color='0F172A', size=10)

    _add_quadro_comparativo_regional(doc, regional_comp, cnpj_data, periodo_txt)

    gtin_comp = _build_gtin_sem_comprovacao_context(cnpj, data_inicio, data_fim)
    p_gtin_intro = doc.add_paragraph()
    _run(p_gtin_intro, f'Do rol de medicamentos distribuídos pela Farmácia {razao_social} sem estoques amparados em notas fiscais de suas aquisições, constantes do levantamento apresentado no Quadro 01, destacam-se os seguintes:', color='0F172A', size=10)

    _add_quadro_gtins_sem_comprovacao(doc, razao_social, cnpj_fmt, gtin_comp, periodo_txt)

    p_gtin_conclusao = doc.add_paragraph()
    gtins_txt = "GTIN" if gtin_comp["total_gtins"] == 1 else "GTINs"
    representativos_txt = "GTIN" if gtin_comp["representativos_count"] == 1 else "GTINs"
    _run(p_gtin_conclusao, f'Conforme o Quadro 04, as “vendas sem comprovação” estão distribuídas em ', color='0F172A', size=10)
    _run(p_gtin_conclusao, f'{gtin_comp["total_gtins"]} {gtins_txt}', color='0F172A', size=10, bold=True)
    _run(p_gtin_conclusao, ', que totalizam ', color='0F172A', size=10)
    _run(p_gtin_conclusao, f'R$ {_format_decimal_pt(gtin_comp["total_valor"], 2)}', color='334155', size=10, bold=True)
    _run(p_gtin_conclusao, '. Observa-se, contudo, concentração relevante em ', color='0F172A', size=10)
    _run(p_gtin_conclusao, f'{gtin_comp["representativos_count"]} {representativos_txt}', color='0F172A', size=10, bold=True)
    _run(p_gtin_conclusao, ', que respondem por ', color='0F172A', size=10)
    _run(p_gtin_conclusao, f'R$ {_format_decimal_pt(gtin_comp["representativos_valor"], 2)}', color='334155', size=10, bold=True)
    _run(p_gtin_conclusao, ', equivalentes a ', color='0F172A', size=10)
    _run(p_gtin_conclusao, f'{_format_decimal_pt(gtin_comp["representativos_pct"], 1)}%', color='334155', size=10, bold=True)
    _run(p_gtin_conclusao, f' do total listado, considerando o menor conjunto de GTINs necessário para atingir ao menos {_format_decimal_pt(gtin_comp["concentration_target_pct"], 0)}% do valor sem comprovação.', color='0F172A', size=10)
    
    doc.add_heading(f'6.1 Evolução das transferências do Programa Farmácia Popular do Brasil para a Farmácia {razao_social} e das possíveis “vendas sem comprovação” por ela realizadas', level=2)

    evolucao_comp = _build_evolucao_financeira_context(cnpj, data_inicio, data_fim)
    socios_volume_atipico = _build_socios_volume_atipico_context(socios_ativos, evolucao_comp)

    semestres_atipicos = evolucao_comp["semestres_atipicos"]
    if semestres_atipicos:
        p_54_contexto = doc.add_paragraph()
        p_54_contexto.paragraph_format.space_before = Pt(6)
        _run(p_54_contexto, 'No âmbito do PFPB, espera-se que as distribuições de medicamentos para a população por parte das farmácias ocorram de forma orgânica, sem saltos repentinos e demasiados que sugiram práticas de faturamento fictício em lote.', color='0F172A', size=10)

        p_54_analise = doc.add_paragraph()
        _run(p_54_analise, f'A Farmácia {razao_social} recebeu recursos provenientes do Ministério da Saúde, referentes ao PFPB, no período de ', color='0F172A', size=10)
        _run(p_54_analise, evolucao_comp["periodo_meses"], color='0F172A', size=10)
        _run(p_54_analise, '. ', color='0F172A', size=10)
        crescimento_labels = _format_list_pt([
            (
                f'{row["semestre_fmt"]} (+{_format_decimal_pt(row["taxa_crescimento_pct"], 1)}%)'
                if row.get("taxa_crescimento_pct") is not None
                else row["semestre_fmt"]
            )
            for row in semestres_atipicos
        ])
        _run(p_54_analise, 'Nesse intervalo, chama a atenção o aumento expressivo das transferências no ', color='0F172A', size=10)
        _run(p_54_analise, crescimento_labels, color='334155', size=10, bold=True)
        _run(p_54_analise, ', sempre em comparação ao semestre imediatamente anterior. ', color='0F172A', size=10)

        top_irregulares = evolucao_comp["top_irregulares"]
        if top_irregulares:
            top_labels = _format_list_pt([row["semestre_fmt"] for row in top_irregulares])
            top_irregular_valor = round(sum(row["irregular"] for row in top_irregulares), 2)
            _run(p_54_analise, 'Também se verificam valores relevantes de “vendas sem comprovação” no ', color='0F172A', size=10)
            _run(p_54_analise, top_labels, color='334155', size=10)
            _run(p_54_analise, ', que somam ', color='0F172A', size=10)
            _run(p_54_analise, f'R$ {_format_decimal_pt(top_irregular_valor, 2)}', color='334155', size=10, bold=True)
            _run(p_54_analise, ', conforme quadro e figura a seguir.', color='0F172A', size=10)

    _add_quadro_evolucao_financeira(doc, razao_social, cnpj_fmt, evolucao_comp)
    if socios_volume_atipico:
        p_socios_volume = doc.add_paragraph()
        p_socios_volume.paragraph_format.space_before = Pt(6)
        _run(p_socios_volume, 'Também se observam ingressos societários próximos a semestres com aumento atípico das transferências, conforme detalhado no quadro a seguir.', color='0F172A', size=10)
    _add_quadro_socios_volume_atipico(doc, socios_volume_atipico)
    _add_figura_evolucao_financeira(doc, razao_social, cnpj_fmt, evolucao_comp)

    # Seção 7 sem rodapé herdado da seção 6.
    _start_section(doc)
    doc.add_heading(f'7. SOBRE OUTRAS CRITICIDADES RELATIVAS À FARMÁCIA {razao_social}, NO ÂMBITO DO PFPB.', level=1)
    doc.add_paragraph(f'Analisando-se informações declaradas pela Farmácia {razao_social} no Sistema SAV e, em alguns casos, cruzando-as com outras bases de dados, foram identificadas criticidades, a seguir detalhadas, que corroboram com o achado principal de “vendas sem comprovação” para ela apuradas.')
    criticidade_start = 1
    if falecidos_comp:
        _add_falecidos_criticidade_text(doc, '7.1', razao_social, falecidos_comp)
        criticidade_start = 2

    criticidade_items = _iter_criticidade_items(criticos, razao_social, start_index=criticidade_start, exclude_keys={'falecidos'})
    if criticidade_items:
        for _, num, full_title in criticidade_items:
            doc.add_heading(f'{num} {full_title}', level=2)
            doc.add_paragraph(f'Foi detectado um alerta CRÍTICO para o indicador "{full_title}". Este comportamento indica uma distorção estatística severa (Modified Z-Score > 3.0) que exige verificação documental imediata.')
    elif not falecidos_comp:
        doc.add_paragraph('Não foram identificadas outras criticidades em nível crítico para detalhamento nesta seção, sem prejuízo do acompanhamento sistêmico dos demais indicadores do Sistema Sentinela.')

    # 8. CONCLUSÃO
    doc.add_heading('8. CONCLUSÃO E ENCAMINHAMENTO', level=1)
    if risco_label in ('CRÍTICO', 'ATENÇÃO'):
        doc.add_paragraph('Considerando o elevado score de risco e os indícios de irregularidades detectados nas seções anteriores, sugere-se a priorização deste estabelecimento para auditoria in loco ou solicitação formal de documentos para comprovação das vendas realizadas.')
    else:
        doc.add_paragraph('O estabelecimento apresenta indicadores que, embora monitorados, não atingiram os limiares de priorização para fiscalização imediata, recomendando-se a manutenção do acompanhamento sistêmico.')

    file_stream = io.BytesIO()
    doc.save(file_stream)
    file_stream.seek(0)
    return file_stream
