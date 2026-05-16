import io
import os
from typing import Any

from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.shared import Inches
from PIL import Image, ImageDraw, ImageFont

from .nota_tecnica_docx_utils import _run
from .nota_tecnica_formatters import _format_decimal_pt


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


def _text_size(
    draw: ImageDraw.ImageDraw,
    text: str,
    font: ImageFont.FreeTypeFont | ImageFont.ImageFont,
) -> tuple[int, int]:
    """Mede texto em pixels com compatibilidade entre versoes do Pillow."""
    bbox = draw.textbbox((0, 0), text, font=font)
    return int(bbox[2] - bbox[0]), int(bbox[3] - bbox[1])


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
    font: ImageFont.FreeTypeFont | ImageFont.ImageFont,
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
