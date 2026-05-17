from datetime import date, datetime
from typing import Any, Optional

from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.shared import Inches

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

    top_crms = sorted(
        crms,
        key=lambda row: (
            _as_int(row.get("nu_prescricoes")),
            _as_float(row.get("vl_total_prescricoes")),
        ),
        reverse=True,
    )[:3]
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
        f" médicos lançados pela Farmácia {razao_social} como responsáveis pelas receitas prescritas de medicamentos supostamente retirados no estabelecimento, foi identificado que poucos CRMs concentraram grande quantidade de lançamentos, conforme apresentado a seguir:",
        color="0F172A",
        size=10,
    )

    title = doc.add_paragraph()
    _run(
        title,
        f"Quadro 07 - Médicos (CRM) com maiores números de registros no Sistema Autorizador de Vendas, lançados pela Farmácia {razao_social} (CNPJ {cnpj_fmt}), no período {periodo_intervalo}.",
        color="0F172A",
        size=9,
        bold=True,
    )

    headers = [
        "CRM",
        "UF",
        "Nome",
        "Data da inscrição no CFM",
        "Número de autorizações vinculadas ao CRM",
        "Valor total pago pelo PFPB tendo como base o CRM",
    ]
    table = doc.add_table(rows=1, cols=len(headers))
    table.style = "Table Grid"
    widths = [Inches(0.75), Inches(0.35), Inches(1.75), Inches(0.85), Inches(1.15), Inches(1.35)]
    _set_table_fixed_widths(table, widths)

    for idx, header in enumerate(headers):
        cell = table.rows[0].cells[idx]
        _cell_bg(cell, "E2E8F0")
        _write_cell(cell, header, size=7.0, bold=True, align=WD_ALIGN_PARAGRAPH.CENTER)

    for row in hhi_crm_comp["top_crms"]:
        cells = table.add_row().cells
        crm_row, uf_row = _crm_num_uf(row.get("id_medico"))
        values = [
            crm_row,
            uf_row,
            str(row.get("no_medico") or "Não localizado"),
            _format_date_br(row.get("dt_inscricao_crm")),
            str(_as_int(row.get("nu_prescricoes"))),
            f'R$ {_format_decimal_pt(_as_float(row.get("vl_total_prescricoes")), 2)}',
        ]
        for idx, value in enumerate(values):
            align = WD_ALIGN_PARAGRAPH.RIGHT if idx in (4, 5) else WD_ALIGN_PARAGRAPH.CENTER if idx in (0, 1, 3) else None
            _write_cell(cells[idx], value, size=7.0, align=align)

    fonte = doc.add_paragraph()
    _run(
        fonte,
        "Fonte: Consulta ao CRM (https://portal.cfm.org.br/busca-medicos) e Sistema Autorizador de Vendas (SAV).",
        color="475569",
        size=8,
        italic=True,
    )

    p3 = doc.add_paragraph()
    _run(p3, "Conforme Quadro 07, foi identificada uma concentração atípica de registros relacionados com o médico ", color="0F172A", size=10)
    _run(p3, nome_medico, color="334155", size=10, bold=True)
    _run(p3, ", CRM ", color="0F172A", size=10)
    _run(p3, crm_ident, color="334155", size=10, bold=True)
    _run(p3, f". Das {total_autorizacoes} autorizações verificadas no período, ", color="0F172A", size=10)
    _run(p3, f'{principal_autorizacoes} autorizações ({_format_decimal_pt(hhi_crm_comp["pct_autorizacoes"], 2)}%)', color="334155", size=10, bold=True)
    _run(
        p3,
        f" estavam associadas ao mesmo médico. Nota-se que a média foi de {_format_decimal_pt(media_autorizacoes, 2)} autorizações por CRM (= {total_autorizacoes} autorizações / {total_medicos} médicos), logo o CRM {crm_ident} teve número de autorizações a ele atreladas ",
        color="0F172A",
        size=10,
    )
    _run(p3, f'{_format_decimal_pt(hhi_crm_comp["mult_autorizacoes"], 2)} vezes', color="334155", size=10, bold=True)
    _run(p3, f" maior que a média ({principal_autorizacoes} autorizações).", color="0F172A", size=10)

    p4 = doc.add_paragraph()
    _run(p4, f"Já o valor recebido pela Farmácia por medicamentos prescritos pelo médico {nome_medico} foi de ", color="0F172A", size=10)
    _run(p4, f"R$ {_format_decimal_pt(principal_valor, 2)}", color="334155", size=10, bold=True)
    _run(p4, ", ou seja ", color="0F172A", size=10)
    _run(p4, f'{_format_decimal_pt(hhi_crm_comp["pct_valor"], 2)}%', color="334155", size=10, bold=True)
    _run(
        p4,
        f" dos R$ {_format_decimal_pt(valor_total, 2)} analisados no período. Destaca-se que a média foi de R$ {_format_decimal_pt(media_valor, 2)} por CRM (= R$ {_format_decimal_pt(valor_total, 2)} / {total_medicos} médicos), logo, o CRM {crm_ident} teve o valor ",
        color="0F172A",
        size=10,
    )
    _run(p4, f'{_format_decimal_pt(hhi_crm_comp["mult_valor"], 2)} vezes', color="334155", size=10, bold=True)
    _run(p4, " maior que a média.", color="0F172A", size=10)
