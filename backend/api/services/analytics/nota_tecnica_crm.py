from datetime import date, datetime
from typing import Any, Optional

from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.shared import Inches

from data_cache import get_df_matriz_risco
from .crm import get_crm_data
from .nota_tecnica_docx_utils import _cell_bg, _run, _set_table_fixed_widths, _write_cell
from .nota_tecnica_formatters import _format_decimal_pt


def _as_float(value: Any) -> float:
    try:
        return float(value or 0)
    except (TypeError, ValueError):
        return 0.0


def _as_int(value: Any) -> int:
    try:
        return int(float(value or 0))
    except (TypeError, ValueError):
        return 0


def _format_date_br(value: Any) -> str:
    if value is None:
        return "Não localizada"
    if isinstance(value, datetime):
        return value.strftime("%d/%m/%Y")
    if isinstance(value, date):
        return value.strftime("%d/%m/%Y")
    text = str(value).strip()
    if not text:
        return "Não localizada"
    for fmt in ("%Y-%m-%d", "%Y-%m-%d %H:%M:%S", "%d/%m/%Y"):
        try:
            return datetime.strptime(text[:19], fmt).strftime("%d/%m/%Y")
        except ValueError:
            continue
    return text


def _vez_ou_vezes(value: float) -> str:
    return "vez" if abs(value) <= 1 else "vezes"


def _crm_num_uf(id_medico: Any) -> tuple[str, str]:
    text = str(id_medico or "").strip()
    if "/" not in text:
        return text or "Não informado", ""
    numero, uf = text.split("/", 1)
    return numero.strip() or "Não informado", uf.strip()


def _build_hhi_crm_context(
    cnpj: str,
    data_inicio: Optional[date],
    data_fim: Optional[date],
) -> dict[str, Any] | None:
    """Monta o contexto do subitem de concentração atípica de CRM."""
    try:
        crm_data = get_crm_data(
            cnpj,
            data_inicio.isoformat() if data_inicio else None,
            data_fim.isoformat() if data_fim else None,
        )
    except Exception as exc:
        print(f"[NOTA_TECNICA] CRM indisponivel para {cnpj}: {exc}")
        return None

    crms = list(getattr(crm_data, "crms_interesse", None) or [])
    if not crms:
        return None

    total_medicos = len(crms)
    total_autorizacoes = sum(_as_int(row.get("nu_prescricoes")) for row in crms)
    valor_total = sum(_as_float(row.get("vl_total_prescricoes")) for row in crms)
    if total_medicos <= 0 or total_autorizacoes <= 0:
        return None

    crms_ordenados = sorted(
        crms,
        key=lambda row: (
            _as_float(row.get("vl_total_prescricoes")),
            _as_int(row.get("nu_prescricoes")),
        ),
        reverse=True,
    )
    top_crms: list[dict[str, Any]] = []
    autorizacoes_acumuladas = 0
    for row in crms_ordenados:
        if len(top_crms) >= 10:
            break
        top_crms.append(row)
        autorizacoes_acumuladas += _as_int(row.get("nu_prescricoes"))
        if len(top_crms) >= 5 and (autorizacoes_acumuladas / total_autorizacoes * 100) >= 80:
            break
    principal = top_crms[0]
    principal_autorizacoes = _as_int(principal.get("nu_prescricoes"))
    principal_valor = _as_float(principal.get("vl_total_prescricoes"))

    media_autorizacoes = total_autorizacoes / total_medicos
    media_valor = valor_total / total_medicos if valor_total else 0.0

    if data_inicio and data_fim:
        periodo_intervalo = f'de {data_inicio.strftime("%d.%m.%Y")} a {data_fim.strftime("%d.%m.%Y")}'
    elif data_inicio:
        periodo_intervalo = f'a partir de {data_inicio.strftime("%d.%m.%Y")}'
    elif data_fim:
        periodo_intervalo = f'até {data_fim.strftime("%d.%m.%Y")}'
    else:
        periodo_intervalo = "no período analisado"

    return {
        "periodo_intervalo": periodo_intervalo,
        "total_medicos": total_medicos,
        "total_autorizacoes": total_autorizacoes,
        "valor_total": valor_total,
        "media_autorizacoes": media_autorizacoes,
        "media_valor": media_valor,
        "top_crms": top_crms,
        "principal": principal,
        "principal_autorizacoes": principal_autorizacoes,
        "principal_valor": principal_valor,
        "pct_autorizacoes": principal_autorizacoes / total_autorizacoes * 100,
        "pct_valor": (principal_valor / valor_total * 100) if valor_total else 0.0,
        "mult_autorizacoes": principal_autorizacoes / media_autorizacoes,
        "mult_valor": (principal_valor / media_valor) if media_valor else 0.0,
    }


def _build_exclusividade_crm_context(
    cnpj: str,
    data_inicio: Optional[date],
    data_fim: Optional[date],
    total_mov_quadro_02: Any = None,
) -> dict[str, Any] | None:
    """Monta o contexto do subitem de CRMs exclusivos."""
    matriz_row: dict[str, Any] = {}
    try:
        df_matriz = get_df_matriz_risco()
        df_matriz = df_matriz.rename({c: c.lower() for c in df_matriz.columns})
        rows = df_matriz.filter(df_matriz["cnpj"] == cnpj)
        if not rows.is_empty():
            matriz_row = rows.row(0, named=True)
    except Exception as exc:
        print(f"[NOTA_TECNICA] Matriz de risco indisponivel para exclusividade CRM {cnpj}: {exc}")

    def matriz_float(key: str) -> float:
        try:
            return float(matriz_row.get(key) or 0)
        except (TypeError, ValueError):
            return 0.0

    try:
        crm_data = get_crm_data(
            cnpj,
            data_inicio.isoformat() if data_inicio else None,
            data_fim.isoformat() if data_fim else None,
        )
    except Exception as exc:
        print(f"[NOTA_TECNICA] CRM indisponivel para {cnpj}: {exc}")
        crm_data = None

    crms = list(getattr(crm_data, "crms_interesse", None) or [])

    total_medicos = len(crms)
    total_autorizacoes = sum(_as_int(row.get("nu_prescricoes")) for row in crms)
    valor_total = sum(_as_float(row.get("vl_total_prescricoes")) for row in crms)

    def is_exclusivo(row: dict[str, Any]) -> bool:
        return (
            _as_int(row.get("flag_crm_exclusivo")) > 0
            or _as_int(row.get("nu_estabelecimentos")) == 1
            or _as_float(row.get("pct_volume_aqui_vs_total")) >= 99.99
        )

    crms_exclusivos = [row for row in crms if is_exclusivo(row)]

    exclusivos_ordenados = sorted(
        crms_exclusivos,
        key=lambda row: (
            _as_float(row.get("vl_total_prescricoes")),
            _as_int(row.get("nu_prescricoes")),
        ),
        reverse=True,
    )
    top_exclusivos = exclusivos_ordenados[:10]
    exclusivos_autorizacoes = sum(_as_int(row.get("nu_prescricoes")) for row in crms_exclusivos)
    exclusivos_valor = sum(_as_float(row.get("vl_total_prescricoes")) for row in crms_exclusivos)
    total_mov_quadro_02_float = _as_float(total_mov_quadro_02)
    total_financeiro_base = total_mov_quadro_02_float if total_mov_quadro_02_float > 0 else valor_total
    pct_medicos_exclusivos = (
        len(crms_exclusivos) / total_medicos * 100
        if total_medicos > 0
        else matriz_float("pct_exclusividade_crm")
    )
    pct_autorizacoes_exclusivas = (
        exclusivos_autorizacoes / total_autorizacoes * 100
        if total_autorizacoes > 0
        else 0.0
    )
    pct_valor_exclusivo = (
        exclusivos_valor / total_financeiro_base * 100
        if total_financeiro_base > 0 and exclusivos_valor > 0
        else 0.0
    )

    if not matriz_row and not crms_exclusivos:
        return None

    if data_inicio and data_fim:
        periodo_intervalo = f'de {data_inicio.strftime("%d.%m.%Y")} a {data_fim.strftime("%d.%m.%Y")}'
    elif data_inicio:
        periodo_intervalo = f'a partir de {data_inicio.strftime("%d.%m.%Y")}'
    elif data_fim:
        periodo_intervalo = f'até {data_fim.strftime("%d.%m.%Y")}'
    else:
        periodo_intervalo = "no período analisado"

    return {
        "periodo_intervalo": periodo_intervalo,
        "total_medicos": total_medicos,
        "total_autorizacoes": total_autorizacoes,
        "valor_total": valor_total,
        "total_financeiro_base": total_financeiro_base,
        "crms_exclusivos": crms_exclusivos,
        "top_exclusivos": top_exclusivos,
        "qtd_exclusivos": len(crms_exclusivos),
        "exclusivos_autorizacoes": exclusivos_autorizacoes,
        "exclusivos_valor": exclusivos_valor,
        "pct_medicos_exclusivos": pct_medicos_exclusivos,
        "pct_autorizacoes_exclusivas": pct_autorizacoes_exclusivas,
        "pct_valor_exclusivo": pct_valor_exclusivo,
        "matriz_pct_exclusividade": matriz_float("pct_exclusividade_crm"),
        "multiplicador_regiao": matriz_float("risco_exclusividade_crm_reg"),
        "multiplicador_uf": matriz_float("risco_exclusividade_crm_uf"),
        "multiplicador_brasil": matriz_float("risco_exclusividade_crm_br"),
    }


def _build_crms_irregulares_context(
    cnpj: str,
    data_inicio: Optional[date],
    data_fim: Optional[date],
    total_mov_quadro_02: Any = None,
) -> dict[str, Any] | None:
    """Monta o contexto do subitem de CRMs irregulares ou invalidos."""
    matriz_row: dict[str, Any] = {}
    try:
        df_matriz = get_df_matriz_risco()
        df_matriz = df_matriz.rename({c: c.lower() for c in df_matriz.columns})
        rows = df_matriz.filter(df_matriz["cnpj"] == cnpj)
        if not rows.is_empty():
            matriz_row = rows.row(0, named=True)
    except Exception as exc:
        print(f"[NOTA_TECNICA] Matriz de risco indisponivel para CRMs irregulares {cnpj}: {exc}")

    def matriz_float(key: str) -> float:
        try:
            return float(matriz_row.get(key) or 0)
        except (TypeError, ValueError):
            return 0.0

    try:
        crm_data = get_crm_data(
            cnpj,
            data_inicio.isoformat() if data_inicio else None,
            data_fim.isoformat() if data_fim else None,
        )
    except Exception as exc:
        print(f"[NOTA_TECNICA] CRM indisponivel para {cnpj}: {exc}")
        crm_data = None

    crms = list(getattr(crm_data, "crms_interesse", None) or [])
    total_autorizacoes = sum(_as_int(row.get("nu_prescricoes")) for row in crms)
    valor_total_crm = sum(_as_float(row.get("vl_total_prescricoes")) for row in crms)
    total_mov_quadro_02_float = _as_float(total_mov_quadro_02)
    total_financeiro_base = total_mov_quadro_02_float if total_mov_quadro_02_float > 0 else valor_total_crm

    crms_irregulares = [
        row
        for row in crms
        if _as_int(row.get("flag_crm_invalido")) > 0
        or _as_int(row.get("flag_prescricao_antes_registro")) > 0
    ]
    irregulares_ordenados = sorted(
        crms_irregulares,
        key=lambda row: (
            _as_float(row.get("vl_total_prescricoes")),
            _as_int(row.get("nu_prescricoes")),
        ),
        reverse=True,
    )
    top_irregulares = irregulares_ordenados[:10]

    qtd_invalidos = sum(1 for row in crms if _as_int(row.get("flag_crm_invalido")) > 0)
    qtd_antes_registro = sum(1 for row in crms if _as_int(row.get("flag_prescricao_antes_registro")) > 0)
    valor_irregular = sum(_as_float(row.get("vl_total_prescricoes")) for row in crms_irregulares)
    pct_irregular = (
        valor_irregular / total_financeiro_base * 100
        if total_financeiro_base > 0 and valor_irregular > 0
        else matriz_float("pct_crms_irregulares")
    )
    if valor_irregular <= 0 and total_financeiro_base > 0 and pct_irregular > 0:
        valor_irregular = total_financeiro_base * pct_irregular / 100

    if not matriz_row and not crms_irregulares:
        return None

    if data_inicio and data_fim:
        periodo_intervalo = f'de {data_inicio.strftime("%d.%m.%Y")} a {data_fim.strftime("%d.%m.%Y")}'
    elif data_inicio:
        periodo_intervalo = f'a partir de {data_inicio.strftime("%d.%m.%Y")}'
    elif data_fim:
        periodo_intervalo = f'até {data_fim.strftime("%d.%m.%Y")}'
    else:
        periodo_intervalo = "no período analisado"

    return {
        "periodo_intervalo": periodo_intervalo,
        "total_autorizacoes": total_autorizacoes,
        "total_financeiro_base": total_financeiro_base,
        "top_irregulares": top_irregulares,
        "qtd_invalidos": qtd_invalidos,
        "qtd_antes_registro": qtd_antes_registro,
        "valor_irregular": valor_irregular,
        "pct_irregular": pct_irregular,
        "multiplicador_regiao": matriz_float("risco_crms_irregulares_reg"),
        "multiplicador_uf": matriz_float("risco_crms_irregulares_uf"),
        "multiplicador_brasil": matriz_float("risco_crms_irregulares_br"),
    }


def _add_hhi_crm_text(doc, num: str, razao_social: str, cnpj_fmt: str, hhi_crm_comp: dict[str, Any]):
    """Adiciona o subitem de concentração atípica de registros do mesmo CRM."""
    periodo_intervalo = hhi_crm_comp["periodo_intervalo"]
    total_medicos = hhi_crm_comp["total_medicos"]
    total_autorizacoes = hhi_crm_comp["total_autorizacoes"]
    valor_total = hhi_crm_comp["valor_total"]
    media_autorizacoes = hhi_crm_comp["media_autorizacoes"]
    media_valor = hhi_crm_comp["media_valor"]
    principal = hhi_crm_comp["principal"]
    principal_autorizacoes = hhi_crm_comp["principal_autorizacoes"]
    principal_valor = hhi_crm_comp["principal_valor"]
    top_autorizacoes = sum(_as_int(row.get("nu_prescricoes")) for row in hhi_crm_comp["top_crms"])
    top_pct_autorizacoes = (top_autorizacoes / total_autorizacoes * 100) if total_autorizacoes else 0.0

    crm_num, crm_uf = _crm_num_uf(principal.get("id_medico"))
    crm_ident = f"{crm_num}/{crm_uf}" if crm_uf else crm_num
    nome_medico = str(principal.get("no_medico") or "Não localizado")

    doc.add_heading(
        f"{num} Concentração atípica de registros do mesmo médico (CRM) no Sistema Autorizador de Vendas do PFPB",
        level=2,
    )

    p1 = doc.add_paragraph()
    _run(
        p1,
        "Dentre os dados lançados pelas farmácias credenciadas no PFPB no Sistema Auxiliar de Venda (SAV) está o número de inscrição do médico no Conselho Regional de Medicina (CRM) e sua respectiva unidade federativa, a fim de respaldar as dispensações de medicamentos por meio das prescrições (receitas). ",
        color="0F172A",
        size=10,
    )
    _run(
        p1,
        'O comportamento esperado para os estabelecimentos é de que diversos pacientes apresentem receitas de médicos distintos. Concentração excessiva pode indicar a ocorrência de acordos entre pacientes e médicos para prescrição de receitas falsas, médicos "parceiros" de fraudes cometidas pelo estabelecimento e/ou ainda uso indevidos de CRMs por parte da farmácia.',
        color="0F172A",
        size=10,
    )

    p2 = doc.add_paragraph()
    _run(p2, f"No período {periodo_intervalo}, de um universo de ", color="0F172A", size=10)
    _run(p2, f"{total_medicos}", color="334155", size=10, bold=True)
    _run(
        p2,
        f" médicos lançados pela Farmácia {razao_social} como responsáveis pelas receitas prescritas de medicamentos supostamente retirados no estabelecimento. O quadro a seguir apresenta os principais CRMs por valor pago, com indicação da participação individual e acumulada de cada um na produção total da farmácia, observado o mínimo de 5 e o máximo de 10 médicos:",
        color="0F172A",
        size=10,
    )

    title = doc.add_paragraph()
    _run(
        title,
        f"Quadro 07 - Médicos (CRM) com maiores valores pagos pelo PFPB no Sistema Autorizador de Vendas, lançados pela Farmácia {razao_social} (CNPJ {cnpj_fmt}), no período {periodo_intervalo}.",
        color="0F172A",
        size=9,
        bold=True,
    )

    headers = [
        "CRM/UF",
        "Nome",
        "Data da inscrição no CFM",
        "Número de autorizações vinculadas ao CRM",
        "% sobre a produção total da farmácia",
        "% acumulado da produção total",
        "Valor total pago pelo PFPB tendo como base o CRM",
    ]
    table = doc.add_table(rows=1, cols=len(headers))
    table.style = "Table Grid"
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    widths = [Inches(0.9), Inches(1.55), Inches(0.75), Inches(0.95), Inches(0.8), Inches(0.8), Inches(1.15)]
    _set_table_fixed_widths(table, widths)

    for idx, header in enumerate(headers):
        cell = table.rows[0].cells[idx]
        _cell_bg(cell, "E2E8F0")
        _write_cell(cell, header, size=7.0, bold=True, align=WD_ALIGN_PARAGRAPH.CENTER)

    autorizacoes_acumuladas_tabela = 0
    for row in hhi_crm_comp["top_crms"]:
        cells = table.add_row().cells
        crm_row, uf_row = _crm_num_uf(row.get("id_medico"))
        row_autorizacoes = _as_int(row.get("nu_prescricoes"))
        autorizacoes_acumuladas_tabela += row_autorizacoes
        pct_producao_total = (row_autorizacoes / total_autorizacoes * 100) if total_autorizacoes else 0.0
        pct_acumulado = (autorizacoes_acumuladas_tabela / total_autorizacoes * 100) if total_autorizacoes else 0.0
        crm_uf = f"{crm_row}/{uf_row}" if uf_row else crm_row
        values = [
            crm_uf,
            str(row.get("no_medico") or "Não localizado"),
            _format_date_br(row.get("dt_inscricao_crm")),
            str(row_autorizacoes),
            f'{_format_decimal_pt(pct_producao_total, 2)}%',
            f'{_format_decimal_pt(pct_acumulado, 2)}%',
            f'R$ {_format_decimal_pt(_as_float(row.get("vl_total_prescricoes")), 2)}',
        ]
        for idx, value in enumerate(values):
            align = WD_ALIGN_PARAGRAPH.RIGHT if idx in (3, 4, 5, 6) else WD_ALIGN_PARAGRAPH.CENTER if idx in (0, 2) else None
            _write_cell(cells[idx], value, size=7.0, align=align)

    fonte = doc.add_paragraph()
    fonte.alignment = WD_ALIGN_PARAGRAPH.CENTER
    _run(
        fonte,
        "Fonte: Consulta ao CFM (https://portal.cfm.org.br/busca-medicos) e Sistema Autorizador de Vendas (SAV).",
        color="475569",
        size=8,
        italic=True,
    )

    p3 = doc.add_paragraph()
    _run(p3, "Conforme o Quadro 07, observa-se concentração relevante das dispensações no médico ", color="0F172A", size=10)
    _run(p3, nome_medico, color="334155", size=10, bold=True)
    _run(p3, ", CRM ", color="0F172A", size=10)
    _run(p3, crm_ident, color="334155", size=10, bold=True)
    _run(p3, ". No período analisado, esse CRM concentrou ", color="0F172A", size=10)
    _run(p3, f"{principal_autorizacoes}", color="334155", size=10, bold=True)
    _run(p3, f" das {total_autorizacoes} autorizações verificadas, correspondendo a ", color="0F172A", size=10)
    _run(p3, f'{_format_decimal_pt(hhi_crm_comp["pct_autorizacoes"], 2)}%', color="334155", size=10, bold=True)
    _run(
        p3,
        f" da produção da farmácia. Embora tenham sido identificados {total_medicos} médicos no período, com média de {_format_decimal_pt(media_autorizacoes, 2)} autorizações por CRM, o volume associado ao CRM {crm_ident} foi ",
        color="0F172A",
        size=10,
    )
    _run(p3, f'{_format_decimal_pt(hhi_crm_comp["mult_autorizacoes"], 2)} vezes superior a essa média', color="334155", size=10, bold=True)
    _run(p3, ".", color="0F172A", size=10)

    p4 = doc.add_paragraph()
    _run(p4, f"Em termos financeiros, as vendas vinculadas ao referido CRM somaram ", color="0F172A", size=10)
    _run(p4, f"R$ {_format_decimal_pt(principal_valor, 2)}", color="334155", size=10, bold=True)
    _run(p4, ", equivalentes a ", color="0F172A", size=10)
    _run(p4, f'{_format_decimal_pt(hhi_crm_comp["pct_valor"], 2)}%', color="334155", size=10, bold=True)
    _run(
        p4,
        f" dos R$ {_format_decimal_pt(valor_total, 2)} analisados. Esse montante também se mostra destoante da distribuição média por médico, uma vez que supera em ",
        color="0F172A",
        size=10,
    )
    _run(p4, f'{_format_decimal_pt(hhi_crm_comp["mult_valor"], 2)} vezes', color="334155", size=10, bold=True)
    _run(p4, f" a média de R$ {_format_decimal_pt(media_valor, 2)} por CRM. A coincidência entre concentração de autorizações e concentração de valores reforça o caráter atípico do padrão observado.", color="0F172A", size=10)

    if top_pct_autorizacoes >= 80:
        p5 = doc.add_paragraph()
        _run(p5, "Ademais, os CRMs listados no Quadro 07 concentram conjuntamente ", color="0F172A", size=10)
        _run(p5, f"{_format_decimal_pt(top_pct_autorizacoes, 2)}%", color="334155", size=10, bold=True)
        _run(p5, " da produção total da farmácia, alcançando o patamar de concentração definido para a seleção do quadro e indicando que a dispersão esperada entre prescritores não se verificou de forma regular no período analisado.", color="0F172A", size=10)


def _add_crms_irregulares_text(doc, num: str, razao_social: str, cnpj_fmt: str, irregulares_comp: dict[str, Any]):
    """Adiciona o subitem de vendas vinculadas a CRMs irregulares."""
    periodo_intervalo = irregulares_comp["periodo_intervalo"]
    total_autorizacoes = irregulares_comp["total_autorizacoes"]
    total_financeiro_base = irregulares_comp["total_financeiro_base"]
    qtd_invalidos = irregulares_comp["qtd_invalidos"]
    qtd_antes_registro = irregulares_comp["qtd_antes_registro"]
    valor_irregular = irregulares_comp["valor_irregular"]
    pct_irregular = irregulares_comp["pct_irregular"]
    has_detalhe_irregulares = bool(irregulares_comp["top_irregulares"])
    multiplicador_reg_fmt = _format_decimal_pt(irregulares_comp["multiplicador_regiao"], 2)
    multiplicador_uf_fmt = _format_decimal_pt(irregulares_comp["multiplicador_uf"], 2)
    multiplicador_br_fmt = _format_decimal_pt(irregulares_comp["multiplicador_brasil"], 2)
    multiplicador_reg_unidade = _vez_ou_vezes(_as_float(irregulares_comp["multiplicador_regiao"]))
    multiplicador_uf_unidade = _vez_ou_vezes(_as_float(irregulares_comp["multiplicador_uf"]))
    multiplicador_br_unidade = _vez_ou_vezes(_as_float(irregulares_comp["multiplicador_brasil"]))

    doc.add_heading(f"{num} Vendas de medicamentos prescritos por médicos com irregularidade em seus CRMs", level=2)

    p1 = doc.add_paragraph()
    _run(
        p1,
        "No âmbito do PFPB, as dispensações devem estar respaldadas por prescrições emitidas por médicos com registro ativo e regular no Conselho Regional de Medicina (CRM). Para este indicador, foram consideradas duas situações de irregularidade: CRMs inválidos ou não localizados na base do Conselho Federal de Medicina (CFM), e prescrições com data anterior à inscrição do médico no respectivo conselho. A ocorrência de qualquer dessas situações aponta para o processamento de dispensações com prescrição médica incompatível com os requisitos legais do Programa.",
        color="0F172A",
        size=10,
    )

    p2 = doc.add_paragraph()
    _run(p2, f"Em relação à Farmácia {razao_social}, verificou-se que, do total de ", color="0F172A", size=10)
    _run(p2, f"R$ {_format_decimal_pt(total_financeiro_base, 2)}", color="334155", size=10, bold=True)
    _run(p2, f" em vendas de medicamentos efetivadas no âmbito do PFPB no período {periodo_intervalo}, ", color="0F172A", size=10)
    _run(p2, f"{_format_decimal_pt(pct_irregular, 2)}%", color="334155", size=10, bold=True)
    _run(p2, " (", color="0F172A", size=10)
    _run(p2, f"R$ {_format_decimal_pt(valor_irregular, 2)}", color="334155", size=10, bold=True)
    _run(p2, ") foram realizadas com receitas prescritas por médicos com CRMs irregulares ou inválidos", color="0F172A", size=10)
    if has_detalhe_irregulares:
        _run(p2, ", sendo ", color="0F172A", size=10)
        _run(p2, f"{qtd_invalidos}", color="334155", size=10, bold=True)
        _run(p2, " com números inválidos e ", color="0F172A", size=10)
        _run(p2, f"{qtd_antes_registro}", color="334155", size=10, bold=True)
        _run(p2, " com prescrição médica emitida antes do registro do CRM", color="0F172A", size=10)
    _run(p2, ". Tal percentual corresponde a ", color="0F172A", size=10)
    _run(p2, f"{multiplicador_reg_fmt} {multiplicador_reg_unidade}", color="334155", size=10, bold=True)
    _run(p2, " o percentual mediano de vendas com essa mesma criticidade entre as farmácias de sua região. Ampliando-se o comparativo geográfico, o percentual equivale a ", color="0F172A", size=10)
    _run(p2, f"{multiplicador_uf_fmt} {multiplicador_uf_unidade}", color="334155", size=10, bold=True)
    _run(p2, " o percentual mediano das farmácias do seu Estado e a ", color="0F172A", size=10)
    _run(p2, f"{multiplicador_br_fmt} {multiplicador_br_unidade}", color="334155", size=10, bold=True)
    _run(p2, " o das farmácias de todo o Brasil.", color="0F172A", size=10)

    title = doc.add_paragraph()
    _run(
        title,
        f"Quadro 08 - Médicos com CRM irregular ou inválido vinculados a vendas lançadas pela Farmácia {razao_social} (CNPJ {cnpj_fmt}) no Sistema Autorizador de Vendas, no período {periodo_intervalo}.",
        color="0F172A",
        size=9,
        bold=True,
    )

    headers = [
        "CRM/UF",
        "Nome",
        "Data da inscrição no CFM",
        "Irregularidade identificada",
        "Número de autorizações vinculadas ao CRM",
        "% sobre a produção total da farmácia",
        "Valor total pago pelo PFPB tendo como base o CRM",
    ]
    table = doc.add_table(rows=1, cols=len(headers))
    table.style = "Table Grid"
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    widths = [Inches(0.75), Inches(1.35), Inches(0.75), Inches(1.05), Inches(0.85), Inches(0.75), Inches(1.15)]
    _set_table_fixed_widths(table, widths)

    for idx, header in enumerate(headers):
        cell = table.rows[0].cells[idx]
        _cell_bg(cell, "E2E8F0")
        _write_cell(cell, header, size=7.0, bold=True, align=WD_ALIGN_PARAGRAPH.CENTER)

    linhas_irregulares = irregulares_comp["top_irregulares"] if has_detalhe_irregulares else [None]
    for row in linhas_irregulares:
        cells = table.add_row().cells
        if row is None:
            values = [
                "Consolidado",
                "Detalhamento por CRM não disponível",
                "Não localizada",
                "CRMs irregulares ou inválidos",
                "Não disponível",
                f"{_format_decimal_pt(pct_irregular, 2)}%",
                f"R$ {_format_decimal_pt(valor_irregular, 2)}",
            ]
        else:
            crm_row, uf_row = _crm_num_uf(row.get("id_medico"))
            crm_uf = f"{crm_row}/{uf_row}" if uf_row else crm_row
            row_autorizacoes = _as_int(row.get("nu_prescricoes"))
            row_valor = _as_float(row.get("vl_total_prescricoes"))
            pct_producao_total = (row_autorizacoes / total_autorizacoes * 100) if total_autorizacoes else 0.0
            motivos = []
            if _as_int(row.get("flag_crm_invalido")) > 0:
                motivos.append("CRM inválido")
            if _as_int(row.get("flag_prescricao_antes_registro")) > 0:
                motivos.append("Prescrição antes do registro")
            values = [
                crm_uf,
                str(row.get("no_medico") or "Não localizado"),
                _format_date_br(row.get("dt_inscricao_crm")),
                "; ".join(motivos) or "Irregularidade CRM",
                str(row_autorizacoes),
                f"{_format_decimal_pt(pct_producao_total, 2)}%",
                f"R$ {_format_decimal_pt(row_valor, 2)}",
            ]
        for idx, value in enumerate(values):
            align = WD_ALIGN_PARAGRAPH.RIGHT if idx in (4, 5, 6) else WD_ALIGN_PARAGRAPH.CENTER if idx in (0, 2, 3) else None
            _write_cell(cells[idx], value, size=7.0, align=align)

    fonte = doc.add_paragraph()
    fonte.alignment = WD_ALIGN_PARAGRAPH.CENTER
    _run(
        fonte,
        "Fonte: Consulta ao CFM (https://portal.cfm.org.br/busca-medicos) e Sistema Autorizador de Vendas (SAV).",
        color="475569",
        size=8,
        italic=True,
    )


def _add_exclusividade_crm_text(doc, num: str, razao_social: str, cnpj_fmt: str, exclusividade_comp: dict[str, Any]):
    """Adiciona o subitem de CRMs exclusivos."""
    periodo_intervalo = exclusividade_comp["periodo_intervalo"]
    total_medicos = exclusividade_comp["total_medicos"]
    total_autorizacoes = exclusividade_comp["total_autorizacoes"]
    total_financeiro_base = exclusividade_comp["total_financeiro_base"]
    qtd_exclusivos = exclusividade_comp["qtd_exclusivos"]
    exclusivos_valor = exclusividade_comp["exclusivos_valor"]
    pct_medicos_exclusivos = exclusividade_comp["pct_medicos_exclusivos"]
    pct_valor_exclusivo = exclusividade_comp["pct_valor_exclusivo"]
    has_detalhe_exclusivos = bool(exclusividade_comp["top_exclusivos"])
    multiplicador_reg_fmt = _format_decimal_pt(exclusividade_comp["multiplicador_regiao"], 2)
    multiplicador_uf_fmt = _format_decimal_pt(exclusividade_comp["multiplicador_uf"], 2)
    multiplicador_br_fmt = _format_decimal_pt(exclusividade_comp["multiplicador_brasil"], 2)
    multiplicador_reg_unidade = _vez_ou_vezes(_as_float(exclusividade_comp["multiplicador_regiao"]))
    multiplicador_uf_unidade = _vez_ou_vezes(_as_float(exclusividade_comp["multiplicador_uf"]))
    multiplicador_br_unidade = _vez_ou_vezes(_as_float(exclusividade_comp["multiplicador_brasil"]))
    crm_exclusivo_desc = "CRM de médico" if qtd_exclusivos == 1 else "CRMs de médicos"
    crm_exclusivo_quant = "CRM exclusivo" if qtd_exclusivos == 1 else "CRMs exclusivos"
    identificados_intro = "Foi identificado" if qtd_exclusivos == 1 else "Foram identificados"
    equivalente_txt = "equivalente" if qtd_exclusivos == 1 else "equivalentes"

    doc.add_heading(
        f"{num} Vendas de medicamentos vinculadas a CRMs registrados exclusivamente pela Farmácia {razao_social} no Sistema Autorizador de Vendas do PFPB",
        level=2,
    )

    p1 = doc.add_paragraph()
    _run(
        p1,
        "No âmbito do PFPB, espera-se que médicos prescritores tenham dispensações registradas em mais de uma farmácia, em razão da diversidade esperada de pacientes e estabelecimentos. A identificação de retiradas de medicamentos associadas a um médico em apenas um estabelecimento farmacêutico pode indicar atuação direcionada junto à farmácia ou uso indevido de CRM pelo estabelecimento.",
        color="0F172A",
        size=10,
    )

    p2 = doc.add_paragraph()
    if has_detalhe_exclusivos:
        _run(p2, f"Em relação à Farmácia {razao_social}, verificou-se que, do total de ", color="0F172A", size=10)
        _run(p2, f"R$ {_format_decimal_pt(total_financeiro_base, 2)}", color="334155", size=10, bold=True)
        _run(p2, f" em vendas de medicamentos efetivadas no âmbito do PFPB no período {periodo_intervalo}, ", color="0F172A", size=10)
        _run(p2, f"R$ {_format_decimal_pt(exclusivos_valor, 2)}", color="334155", size=10, bold=True)
        _run(p2, ", equivalente a ", color="0F172A", size=10)
        _run(p2, f"{_format_decimal_pt(pct_valor_exclusivo, 2)}%", color="334155", size=10, bold=True)
        _run(p2, f", esteve associado a {crm_exclusivo_desc} cujos clientes retiraram seus medicamentos exclusivamente nesse estabelecimento. {identificados_intro} ", color="0F172A", size=10)
        _run(p2, f"{qtd_exclusivos}", color="334155", size=10, bold=True)
        _run(p2, f" {crm_exclusivo_quant}, {equivalente_txt} a ", color="0F172A", size=10)
    else:
        _run(p2, f"Em relação à Farmácia {razao_social}, o indicador de exclusividade de CRMs foi classificado como crítico na matriz de risco do Sistema Sentinela. O percentual de CRMs exclusivos observado foi de ", color="0F172A", size=10)
    _run(p2, f"{_format_decimal_pt(pct_medicos_exclusivos, 2)}%", color="334155", size=10, bold=True)
    if has_detalhe_exclusivos:
        _run(p2, f" dos {total_medicos} médicos observados. Esse percentual corresponde a ", color="0F172A", size=10)
    else:
        _run(p2, ". Esse percentual corresponde a ", color="0F172A", size=10)
    _run(p2, f"{multiplicador_reg_fmt} {multiplicador_reg_unidade}", color="334155", size=10, bold=True)
    _run(p2, " o percentual mediano de CRMs exclusivos das farmácias de sua região. Ampliando-se o comparativo geográfico, o percentual equivale a ", color="0F172A", size=10)
    _run(p2, f"{multiplicador_uf_fmt} {multiplicador_uf_unidade}", color="334155", size=10, bold=True)
    _run(p2, " o percentual mediano das farmácias do seu Estado e a ", color="0F172A", size=10)
    _run(p2, f"{multiplicador_br_fmt} {multiplicador_br_unidade}", color="334155", size=10, bold=True)
    _run(p2, " o das farmácias de todo o Brasil.", color="0F172A", size=10)

    if not has_detalhe_exclusivos:
        return

    title = doc.add_paragraph()
    _run(
        title,
        f"Quadro 09 - Médicos com CRMs registrados exclusivamente pela Farmácia {razao_social} (CNPJ {cnpj_fmt}) no Sistema Autorizador de Vendas, no período {periodo_intervalo}.",
        color="0F172A",
        size=9,
        bold=True,
    )

    headers = [
        "CRM/UF",
        "Nome",
        "Data da inscrição no CFM",
        "Número de autorizações vinculadas ao CRM",
        "% sobre a produção total da farmácia",
        "Valor total pago pelo PFPB tendo como base o CRM",
        "% sobre o valor total da farmácia",
    ]
    table = doc.add_table(rows=1, cols=len(headers))
    table.style = "Table Grid"
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    widths = [Inches(0.85), Inches(1.45), Inches(0.75), Inches(0.9), Inches(0.8), Inches(1.1), Inches(0.9)]
    _set_table_fixed_widths(table, widths)

    for idx, header in enumerate(headers):
        cell = table.rows[0].cells[idx]
        _cell_bg(cell, "E2E8F0")
        _write_cell(cell, header, size=7.0, bold=True, align=WD_ALIGN_PARAGRAPH.CENTER)

    for row in exclusividade_comp["top_exclusivos"]:
        cells = table.add_row().cells
        crm_row, uf_row = _crm_num_uf(row.get("id_medico"))
        crm_uf = f"{crm_row}/{uf_row}" if uf_row else crm_row
        row_autorizacoes = _as_int(row.get("nu_prescricoes"))
        row_valor = _as_float(row.get("vl_total_prescricoes"))
        pct_producao_total = (row_autorizacoes / total_autorizacoes * 100) if total_autorizacoes else 0.0
        pct_valor_total = (row_valor / total_financeiro_base * 100) if total_financeiro_base else 0.0
        values = [
            crm_uf,
            str(row.get("no_medico") or "Não localizado"),
            _format_date_br(row.get("dt_inscricao_crm")),
            str(row_autorizacoes),
            f"{_format_decimal_pt(pct_producao_total, 2)}%",
            f"R$ {_format_decimal_pt(row_valor, 2)}",
            f"{_format_decimal_pt(pct_valor_total, 2)}%",
        ]
        for idx, value in enumerate(values):
            align = WD_ALIGN_PARAGRAPH.RIGHT if idx in (3, 4, 5, 6) else WD_ALIGN_PARAGRAPH.CENTER if idx in (0, 2) else None
            _write_cell(cells[idx], value, size=7.0, align=align)

    fonte = doc.add_paragraph()
    fonte.alignment = WD_ALIGN_PARAGRAPH.CENTER
    _run(
        fonte,
        "Fonte: Consulta ao CFM (https://portal.cfm.org.br/busca-medicos) e Sistema Autorizador de Vendas (SAV).",
        color="475569",
        size=8,
        italic=True,
    )
