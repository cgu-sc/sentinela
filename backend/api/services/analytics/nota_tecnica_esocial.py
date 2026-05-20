from typing import Any

from docx.shared import Pt

from .nota_tecnica_docx_utils import _run
from .nota_tecnica_formatters import _format_list_pt
from .nota_tecnica_quadros import _add_quadro_esocial, _add_quadro_esocial_trabalhadores


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


def _add_legal_context(doc, suffix: str | None = None):
    p_leg = doc.add_paragraph()
    p_leg.paragraph_format.space_before = Pt(6)
    _run(
        p_leg,
        'Esse achado deve ser analisado à luz da legislação aplicável às atividades farmacêuticas, que exige responsabilidade e assistência técnica de farmacêutico habilitado durante todo o horário de funcionamento do estabelecimento.',
        color='0F172A',
        size=10,
    )
    if suffix:
        _run(p_leg, ' ' + suffix, color='0F172A', size=10)


def _add_esocial_context_text(doc, razao_social: str, cnpj_fmt: str, esocial_comp: dict[str, Any]):
    """Renderiza o contexto trabalhista/eSocial na seção cadastral da Nota Técnica."""
    doc.add_heading('5.2 Vínculos trabalhistas', level=2)

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
    dt_carga_txt = esocial_comp.get("dt_carga_fonte_txt") or "—"
    anos_sem_farm = list(esocial_comp.get("anos_sem_farmaceutico") or [])
    qtd_anos = len(rows)
    qtd_anos_sem_farm = len(anos_sem_farm)

    p_intro = doc.add_paragraph()

    if qtd_anos == 1:
        row = rows[0]
        ano = row["ano_base"]
        qtd_trab = int(row.get("qtd_trabalhadores") or 0)
        qtd_farm = int(row.get("qtd_farmaceuticos") or 0)
        _run(
            p_intro,
            f'Em consulta à base do eSocial disponível no Sistema Sentinela, atualizada até {dt_carga_txt}, foram identificados vínculos trabalhistas associados à Farmácia {razao_social} somente no ano de {ano}. ',
            color='0F172A',
            size=10,
        )
        if qtd_farm > 0:
            _run(
                p_intro,
                f'Para esse exercício, foram apurados {qtd_trab} {_plural(qtd_trab, "trabalhador registrado", "trabalhadores registrados")}, com identificação de {qtd_farm} {_plural(qtd_farm, "trabalhador", "trabalhadores")} com CBO de farmacêutico (223405).',
                color='0F172A',
                size=10,
            )
        else:
            _run(
                p_intro,
                f'Para esse exercício, foram apurados {qtd_trab} {_plural(qtd_trab, "trabalhador registrado", "trabalhadores registrados")}, nenhum deles com CBO de farmacêutico (223405).',
                color='0F172A',
                size=10,
            )
            _add_legal_context(
                doc,
                'Assim, a ausência de trabalhador com CBO de farmacêutico nos registros considerados deve ser confrontada com a documentação de responsabilidade técnica e de funcionamento da farmácia.',
            )
    else:
        periodo_anos_txt = esocial_comp.get("periodo_anos_txt") or "período analisado"
        _run(
            p_intro,
            f'Em consulta à base do eSocial disponível no Sistema Sentinela, atualizada até {dt_carga_txt}, foram identificados vínculos trabalhistas associados à Farmácia {razao_social} entre {periodo_anos_txt}. ',
            color='0F172A',
            size=10,
        )
        _run(p_intro, 'No período, os registros indicam a seguinte composição anual: ', color='0F172A', size=10)
        _run(p_intro, annual_summary, color='334155', size=10, bold=True)
        _run(p_intro, '.', color='0F172A', size=10)

        if qtd_anos_sem_farm == qtd_anos:
            p_status = doc.add_paragraph()
            p_status.paragraph_format.space_before = Pt(6)
            _run(
                p_status,
                'Em nenhum dos anos considerados foi identificado trabalhador com CBO de farmacêutico (223405).',
                color='0F172A',
                size=10,
            )
            _add_legal_context(
                doc,
                'A ausência desse CBO nos registros considerados deve ser confrontada com a documentação de responsabilidade técnica e de funcionamento da farmácia.',
            )
        elif anos_sem_farm:
            anos_txt = _format_list_pt([str(row["ano_base"]) for row in anos_sem_farm])
            p_status = doc.add_paragraph()
            p_status.paragraph_format.space_before = Pt(6)
            _run(
                p_status,
                f'Nos anos de {anos_txt}, não foi identificado trabalhador com CBO de farmacêutico (223405).',
                color='0F172A',
                size=10,
            )
            _add_legal_context(
                doc,
                'A ausência desse CBO nos anos indicados deve ser confrontada com a documentação de responsabilidade técnica e de funcionamento da farmácia.',
            )
        else:
            p_status = doc.add_paragraph()
            p_status.paragraph_format.space_before = Pt(6)
            _run(
                p_status,
                'Em todos os anos considerados, houve identificação de ao menos um trabalhador com CBO de farmacêutico (223405). A informação é apresentada como elemento de contexto sobre a força de trabalho registrada para o estabelecimento.',
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
    _add_quadro_esocial_trabalhadores(doc, razao_social, cnpj_fmt, esocial_comp)
