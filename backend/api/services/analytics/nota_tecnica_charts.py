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


def _build_evolucao_financeira_chart_pillow(evolucao_comp: dict[str, Any]) -> io.BytesIO:
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


def _add_gradient_bar_segment(
    ax,
    *,
    x_center: float,
    bottom: float,
    height: float,
    width: float,
    bottom_color: str,
    top_color: str,
    np,
    rounded: bool = False,
    zorder: int = 3,
):
    """Desenha um segmento de barra com degrade vertical recortado por patch."""
    if height <= 0:
        return

    from matplotlib.colors import to_rgba
    from matplotlib.patches import FancyBboxPatch, Rectangle

    x0 = x_center - width / 2
    y0 = bottom
    y1 = bottom + height

    if rounded:
        patch = FancyBboxPatch(
            (x0, y0),
            width,
            height,
            boxstyle=f"round,pad=0,rounding_size={min(width * 0.18, height * 0.18)}",
            linewidth=0,
            facecolor="none",
            transform=ax.transData,
            zorder=zorder,
        )
    else:
        patch = Rectangle(
            (x0, y0),
            width,
            height,
            linewidth=0,
            facecolor="none",
            transform=ax.transData,
            zorder=zorder,
        )
    ax.add_patch(patch)

    c0 = np.array(to_rgba(bottom_color))
    c1 = np.array(to_rgba(top_color))
    gradient = np.zeros((256, 1, 4), dtype=float)
    for idx, ratio in enumerate(np.linspace(0, 1, 256)):
        gradient[idx, 0, :] = c0 * (1 - ratio) + c1 * ratio

    image = ax.imshow(
        gradient,
        extent=[x0, x0 + width, y0, y1],
        origin="lower",
        aspect="auto",
        interpolation="bicubic",
        zorder=zorder,
    )
    image.set_clip_path(patch)


def _build_evolucao_financeira_chart(evolucao_comp: dict[str, Any]) -> io.BytesIO:
    """Gera grafico PNG de evolucao financeira com matplotlib."""
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import numpy as np
    from matplotlib.patches import Patch
    from matplotlib.ticker import FuncFormatter

    rows = evolucao_comp["rows"]
    labels = [row.get("semestre_fmt") or row.get("semestre") or "" for row in rows]
    regular_values = [max(float(row.get("regular") or 0.0), 0.0) for row in rows]
    irregular_values = [max(float(row.get("irregular") or 0.0), 0.0) for row in rows]
    total_values = [
        max(float(row.get("total") or (regular_values[idx] + irregular_values[idx])), 0.0)
        for idx, row in enumerate(rows)
    ]

    fig, ax = plt.subplots(figsize=(11.0, 5.4), dpi=180)
    fig.patch.set_facecolor("white")
    ax.set_facecolor("white")

    text_color = "#0F172A"
    muted = "#64748B"
    grid_color = "#CBD5E1"
    regular_bottom = "#10B981"
    regular_top = "#6EE7B7"
    irregular_bottom = "#E11D48"
    irregular_top = "#FB7185"

    x_positions = np.arange(len(rows), dtype=float)
    bar_width = min(0.64, max(0.38, 7.0 / max(len(rows), 1)))

    for idx, x_pos in enumerate(x_positions):
        regular = regular_values[idx]
        irregular = irregular_values[idx]
        total = total_values[idx]
        if total <= 0:
            continue
        _add_gradient_bar_segment(
            ax,
            x_center=x_pos,
            bottom=0.0,
            height=regular,
            width=bar_width,
            bottom_color=regular_bottom,
            top_color=regular_top,
            np=np,
            rounded=irregular <= 0,
            zorder=3,
        )
        _add_gradient_bar_segment(
            ax,
            x_center=x_pos,
            bottom=regular,
            height=irregular,
            width=bar_width,
            bottom_color=irregular_bottom,
            top_color=irregular_top,
            np=np,
            rounded=True,
            zorder=4,
        )

    axis_max = _nice_axis_max(max(total_values or [1.0]) * 1.12)
    ax.set_ylim(0, axis_max)
    ax.set_xlim(-0.65, len(rows) - 0.35 if rows else 0.65)

    ax.set_title(
        "Evolução semestral das transferências e vendas sem comprovação",
        fontsize=15,
        fontweight="bold",
        color=text_color,
        pad=18,
    )
    ax.set_ylabel("Valor movimentado", fontsize=10.5, color=muted, labelpad=10)
    ax.set_xticks(x_positions)
    ax.set_xticklabels(labels, rotation=35, ha="right", fontsize=9.4, color=muted)
    ax.yaxis.set_major_formatter(FuncFormatter(lambda value, _: _axis_currency_label(float(value))))
    ax.tick_params(axis="y", colors=muted, labelsize=9.5, length=0)
    ax.tick_params(axis="x", length=0)

    ax.grid(axis="y", color=grid_color, linestyle=(0, (5, 7)), linewidth=0.8, alpha=0.72)
    ax.grid(axis="x", visible=False)
    for spine in ("top", "right"):
        ax.spines[spine].set_visible(False)
    ax.spines["left"].set_color("#E2E8F0")
    ax.spines["bottom"].set_color("#E2E8F0")

    legend_handles = [
        Patch(facecolor=regular_top, edgecolor="none", label="Vendas regulares"),
        Patch(facecolor=irregular_bottom, edgecolor="none", label="Vendas sem comprovação"),
    ]
    legend = ax.legend(
        handles=legend_handles,
        loc="upper center",
        bbox_to_anchor=(0.5, 1.02),
        ncol=2,
        frameon=False,
        fontsize=9.8,
        handlelength=1.4,
        columnspacing=1.8,
    )
    for text in legend.get_texts():
        text.set_color(muted)

    fig.tight_layout(pad=1.7)
    stream = io.BytesIO()
    fig.savefig(stream, format="png", dpi=180, bbox_inches="tight", facecolor="white")
    plt.close(fig)
    stream.seek(0)
    return stream


def _monotone_smooth_curve(x_values: list[int], y_values: list[float], *, np):
    """Gera pontos intermediarios para uma curva visual suave e monotona."""
    if len(x_values) < 3 or len(x_values) != len(y_values):
        return x_values, y_values

    x = np.asarray(x_values, dtype=float)
    y = np.asarray(y_values, dtype=float)
    order = np.argsort(x)
    x = x[order]
    y = y[order]

    unique_x, unique_idx = np.unique(x, return_index=True)
    x = unique_x
    y = y[unique_idx]
    n = len(x)
    if n < 3:
        return x.tolist(), y.tolist()

    y = np.maximum.accumulate(y)

    # Percentis de regioes pequenas costumam gerar muitos valores repetidos.
    # Para a figura, criamos ancoras no centro de cada patamar e interpolamos
    # entre elas com smoothstep. Isso adiciona pontos e remove o aspecto de escada.
    anchors_x = [float(x[0])]
    anchors_y = [float(y[0])]
    start = 0
    tolerance = 1e-9
    for idx in range(1, n + 1):
        if idx == n or abs(float(y[idx]) - float(y[start])) > tolerance:
            end = idx - 1
            center_x = float((x[start] + x[end]) / 2)
            anchors_x.append(center_x)
            anchors_y.append(float(y[start]))
            start = idx
    anchors_x.append(float(x[-1]))
    anchors_y.append(float(y[-1]))

    anchors_x = np.asarray(anchors_x, dtype=float)
    anchors_y = np.asarray(anchors_y, dtype=float)
    order = np.argsort(anchors_x)
    anchors_x = anchors_x[order]
    anchors_y = np.maximum.accumulate(anchors_y[order])

    unique_anchor_x, unique_anchor_idx = np.unique(anchors_x, return_index=True)
    anchors_x = unique_anchor_x
    anchors_y = anchors_y[unique_anchor_idx]
    if len(anchors_x) < 2:
        return x.tolist(), y.tolist()

    x_smooth = np.linspace(float(anchors_x[0]), float(anchors_x[-1]), max(1200, len(anchors_x) * 80))
    segment_idx = np.searchsorted(anchors_x, x_smooth, side="right") - 1
    segment_idx = np.clip(segment_idx, 0, len(anchors_x) - 2)
    x0 = anchors_x[segment_idx]
    x1 = anchors_x[segment_idx + 1]
    y0 = anchors_y[segment_idx]
    y1 = anchors_y[segment_idx + 1]
    t = (x_smooth - x0) / np.maximum(x1 - x0, 1e-9)
    t = np.clip(t, 0.0, 1.0)
    eased = (3 * t**2) - (2 * t**3)
    y_smooth = y0 + (y1 - y0) * eased

    y_smooth = np.maximum.accumulate(y_smooth)
    y_smooth = np.clip(y_smooth, min(float(np.nanmin(y)), 0.0), max(float(np.nanmax(y)), 100.0))
    return x_smooth.tolist(), y_smooth.tolist()


def _add_gradient_area(ax, x_values: list[float], y_values: list[float], *, np, color_hex: str, y_max: float):
    """Preenche a area sob a curva com degrade vertical recortado pelo poligono."""
    from matplotlib.colors import to_rgba
    from matplotlib.path import Path
    from matplotlib.patches import PathPatch

    x = np.asarray(x_values, dtype=float)
    y = np.asarray(y_values, dtype=float)
    if len(x) < 2:
        return

    rgba = np.array(to_rgba(color_hex))
    gradient = np.zeros((256, 1, 4), dtype=float)
    gradient[:, 0, :3] = rgba[:3]
    gradient[:, 0, 3] = np.linspace(0.03, 0.24, 256)

    image = ax.imshow(
        gradient,
        extent=[float(np.nanmin(x)), float(np.nanmax(x)), 0, y_max],
        origin="lower",
        aspect="auto",
        interpolation="bicubic",
        zorder=2,
    )

    vertices = [(float(x[0]), 0.0), *zip(x.astype(float), y.astype(float)), (float(x[-1]), 0.0), (float(x[0]), 0.0)]
    codes = [Path.MOVETO] + [Path.LINETO] * len(x) + [Path.LINETO, Path.CLOSEPOLY]
    clip_path = PathPatch(Path(vertices, codes), facecolor="none", edgecolor="none", transform=ax.transData)
    ax.add_patch(clip_path)
    image.set_clip_path(clip_path)


def _build_percentil_risco_chart(percentil_comp: dict[str, Any]) -> io.BytesIO:
    """Gera grafico PNG da posicao percentilica do CNPJ com matplotlib."""
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import numpy as np
    from matplotlib.ticker import FuncFormatter

    percentiles = percentil_comp.get("percentiles") or []
    x_values = [int(point.get("percentile") or 0) for point in percentiles]
    y_values = [float(point.get("score") or 0.0) for point in percentiles]
    current_value = float(percentil_comp.get("current_value") or 0.0)
    percentile_rank = int(percentil_comp.get("percentile_rank") or 100)
    metric_label = percentil_comp.get("metric_label") or "% de vendas sem comprovação"

    fig, ax = plt.subplots(figsize=(11.0, 5.4), dpi=180)
    fig.patch.set_facecolor("white")
    ax.set_facecolor("white")

    line_color = "#E11D48"
    area_color = "#F43F5E"
    text_color = "#0F172A"
    muted = "#64748B"
    grid_color = "#CBD5E1"

    x_curve, y_curve = _monotone_smooth_curve(x_values, y_values, np=np)
    ax.plot(x_curve, y_curve, color=line_color, linewidth=2.8, solid_capstyle="round", zorder=3)

    marker_y = current_value
    ax.axvline(percentile_rank, color=line_color, linestyle=(0, (5, 5)), linewidth=1.5, alpha=0.72, zorder=1)
    ax.axhline(marker_y, color=line_color, linestyle=(0, (5, 5)), linewidth=1.3, alpha=0.42, zorder=1)
    ax.scatter([percentile_rank], [marker_y], s=94, color="white", edgecolor=line_color, linewidth=2.4, zorder=5)
    ax.scatter([percentile_rank], [marker_y], s=28, color=line_color, zorder=6)

    current_txt = f"{_format_decimal_pt(current_value, 1)}%"
    badge_txt = f"Estabelecimento\nPercentil {percentile_rank} - {current_txt}"
    ax.annotate(
        badge_txt,
        xy=(percentile_rank, marker_y),
        xytext=(18, 28),
        textcoords="offset points",
        fontsize=10,
        fontweight="bold",
        color=line_color,
        bbox=dict(boxstyle="round,pad=0.55,rounding_size=0.25", fc="white", ec=line_color, lw=1.35),
        arrowprops=dict(arrowstyle="-", color=line_color, lw=1.2, shrinkA=0, shrinkB=8),
        zorder=7,
    )

    ax.set_title(
        "Distribuição percentílica regional do percentual de vendas sem comprovação",
        fontsize=15,
        fontweight="bold",
        color=text_color,
        pad=18,
    )
    ax.set_xlabel("Percentil dos estabelecimentos da Região de Saúde", fontsize=10.5, color=muted, labelpad=10)
    ax.set_ylabel(metric_label, fontsize=10.5, color=muted, labelpad=10)

    max_y = max([current_value, *y_values, 1.0])
    upper = min(100.0, max_y * 1.16 if max_y < 90 else 100.0)
    ax.set_xlim(1, 100)
    ax.set_ylim(0, upper)
    _add_gradient_area(ax, x_curve, y_curve, np=np, color_hex=area_color, y_max=upper)
    ax.set_xticks([1, 20, 40, 60, 80, 100])
    ax.set_xticklabels(["1%", "20%", "40%", "60%", "80%", "100%"])
    ax.yaxis.set_major_formatter(FuncFormatter(lambda value, _: f"{_format_decimal_pt(value, 0)}%"))

    ax.grid(axis="y", color=grid_color, linestyle=(0, (5, 7)), linewidth=0.8, alpha=0.72)
    ax.grid(axis="x", visible=False)
    for spine in ("top", "right"):
        ax.spines[spine].set_visible(False)
    ax.spines["left"].set_color("#E2E8F0")
    ax.spines["bottom"].set_color("#E2E8F0")
    ax.tick_params(axis="both", colors=muted, labelsize=9.5, length=0)

    fig.tight_layout(pad=1.7)
    stream = io.BytesIO()
    fig.savefig(stream, format="png", dpi=180, bbox_inches="tight", facecolor="white")
    plt.close(fig)
    stream.seek(0)
    return stream


def _add_figura_percentil_risco(doc, razao_social: str, cnpj_fmt: str, percentil_comp: dict[str, Any], figure_number: int = 1):
    """Insere figura de percentil de risco no documento."""
    p_title = doc.add_paragraph()
    p_title.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p_title.paragraph_format.keep_with_next = True
    p_title.paragraph_format.keep_together = True
    _run(
        p_title,
        f'Figura {figure_number:02d} - Posição percentílica da Farmácia {razao_social} (CNPJ {cnpj_fmt}) quanto ao percentual de vendas sem comprovação na Região de Saúde.',
        color='0F172A',
        size=10,
        bold=True,
    )

    chart_stream = _build_percentil_risco_chart(percentil_comp)
    p_img = doc.add_paragraph()
    p_img.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p_img.paragraph_format.keep_with_next = False
    p_img.paragraph_format.keep_together = True
    run = p_img.add_run()
    run.add_picture(chart_stream, width=Inches(7.1))

    p_foot = doc.add_paragraph()
    p_foot.alignment = WD_ALIGN_PARAGRAPH.CENTER
    _run(
        p_foot,
        'Fonte: Dispensações informadas no SAV e NF-e de aquisição de medicamentos.',
        color='64748B',
        size=8,
    )


def _add_figura_evolucao_financeira(doc, razao_social: str, cnpj_fmt: str, evolucao_comp: dict[str, Any], figure_number: int = 1):
    """Insere figura da evolucao financeira no documento."""
    p_title = doc.add_paragraph()
    p_title.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p_title.paragraph_format.keep_with_next = True
    p_title.paragraph_format.keep_together = True
    _run(
        p_title,
        f'Figura {figure_number:02d} - Evolução semestral dos recursos recebidos e das “vendas sem comprovação” da Farmácia {razao_social} (CNPJ {cnpj_fmt}).',
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
