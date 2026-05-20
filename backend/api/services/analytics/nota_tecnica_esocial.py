from typing import Any

from docx.shared import Pt

from .nota_tecnica_docx_utils import _run
from .nota_tecnica_formatters import _format_list_pt
from .nota_tecnica_quadros import _add_quadro_esocial


def _plural(value: int, singular: str, plural: str) -> str:
    return singular if value == 1 else plural


def _format_annual_summary(rows: list[dict[str, Any]]) -> str:
    partes: list[str] = []
    for row in rows:
        qtd_trab = int(row.get("qtd_trabalhadores") or 0)
        qtd_farm = int(row.get("qtd_farmaceuticos") or 0)
        partes.append(
            f'{row["ano_base"]} ({qtd_trab} {_plural(qtd_trab, "trabalhador", "trabalhadores")}, '
            f'{qtd_farm} {_plural(qtd_farm, "farmacêutico", "farmacêuticos")})'
        )
    return _format_list_pt(partes)


def _format_single_worker_summary(rows: list[dict[str, Any]]) -> str:
    partes: list[str] = []
    for row in rows:
        cbo_txt = row.get("trabalhador_unico_cbo_txt") or "CBO não identificado"
        admissao_txt = row.get("trabalhador_unico_dt_admissao_txt") or "—"
        if admissao_txt != "—":
            partes.append(f'{row["ano_base"]} ({cbo_txt}, admissão em {admissao_txt})')
        else:
            partes.append(f'{row["ano_base"]} ({cbo_txt})')
    return _format_list_pt(partes)


def _add_esocial_context_text(doc, razao_social: str, cnpj_fmt: str, esocial_comp: dict[str, Any]):
    """Renderiza o contexto trabalhista/eSocial na seção cadastral da Nota Técnica."""
    doc.add_heading('5.2 Contexto trabalhista e assistência técnica farmacêutica', level=2)

    if not esocial_comp.get("has_data"):
        p = doc.add_paragraph()
        _run(
            p,
            f'Não foram identificados registros anuais de vínculos trabalhistas no eSocial para a Farmácia {razao_social} (CNPJ {cnpj_fmt}) no período analisado.',
            color='0F172A',
            size=10,
        )
        return

    rows = list(esocial_comp.get("rows") or [])
    annual_summary = _format_annual_summary(rows)
    periodo_anos_txt = esocial_comp.get("periodo_anos_txt") or "período analisado"
    dt_carga_txt = esocial_comp.get("dt_carga_fonte_txt") or "—"

    p_intro = doc.add_paragraph()
    _run(
        p_intro,
        f'Em consulta ao eSocial, cuja base disponível encontra-se atualizada até {dt_carga_txt}, foram identificados vínculos trabalhistas associados à Farmácia {razao_social} no período de {periodo_anos_txt}. ',
        color='0F172A',
        size=10,
    )
    _run(p_intro, 'Os registros anuais indicam ', color='0F172A', size=10)
    _run(p_intro, annual_summary, color='334155', size=10, bold=True)
    _run(p_intro, '.', color='0F172A', size=10)

    p_leg = doc.add_paragraph()
    p_leg.paragraph_format.space_before = Pt(6)
    _run(
        p_leg,
        'Destaca-se que a legislação aplicável ao exercício e à fiscalização das atividades farmacêuticas exige responsabilidade e assistência técnica de farmacêutico habilitado durante todo o horário de funcionamento do estabelecimento. ',
        color='0F172A',
        size=10,
    )

    anos_sem_farm = list(esocial_comp.get("anos_sem_farmaceutico") or [])
    if anos_sem_farm:
        anos_txt = _format_list_pt([str(row["ano_base"]) for row in anos_sem_farm])
        _run(
            p_leg,
            f'Nos anos de {anos_txt}, os registros considerados não indicam trabalhador com CBO de farmacêutico (223405), circunstância que deve ser confrontada com a documentação de responsabilidade técnica e de funcionamento da farmácia.',
            color='0F172A',
            size=10,
        )
    else:
        _run(
            p_leg,
            'Nos anos considerados, os registros do eSocial indicam ao menos um trabalhador com CBO de farmacêutico (223405).',
            color='0F172A',
            size=10,
        )

    anos_um_trabalhador = list(esocial_comp.get("anos_um_trabalhador") or [])
    if anos_um_trabalhador:
        p_unico = doc.add_paragraph()
        p_unico.paragraph_format.space_before = Pt(6)
        _run(
            p_unico,
            'Também se observa que, em ',
            color='0F172A',
            size=10,
        )
        _run(
            p_unico,
            _format_single_worker_summary(anos_um_trabalhador),
            color='334155',
            size=10,
            bold=True,
        )
        _run(
            p_unico,
            ', havia registro anual de apenas um trabalhador vinculado ao estabelecimento.',
            color='0F172A',
            size=10,
        )

    _add_quadro_esocial(doc, razao_social, cnpj_fmt, esocial_comp)
