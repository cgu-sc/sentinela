from typing import Any

from docx.shared import Pt

from .nota_tecnica_docx_utils import _run
from .nota_tecnica_formatters import _format_decimal_pt, _format_list_pt
from .nota_tecnica_quadros import _add_quadro_esocial, _add_quadro_esocial_trabalhadores


def _plural(value: int, singular: str, plural: str) -> str:
    return singular if value == 1 else plural


def _format_annual_summary(rows: list[dict[str, Any]]) -> str:
    partes: list[str] = []
    for row in rows:
        qtd_trab = int(row.get("qtd_trabalhadores_vinculo_ano") or 0)
        qtd_farm = int(row.get("qtd_farmaceuticos_vinculo_ano") or 0)
        partes.append(
            f'{row["ano_base"]} ({qtd_trab} {_plural(qtd_trab, "trabalhador com vínculo", "trabalhadores com vínculo")}, '
            f'{qtd_farm} {_plural(qtd_farm, "farmacêutico com vínculo", "farmacêuticos com vínculo")})'
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


def _add_movimentacao_sem_funcionario_alerta(doc, esocial_comp: dict[str, Any]):
    alerta = esocial_comp.get("movimentacao_sem_funcionario_alerta")
    if not alerta:
        return

    campos_obrigatorios = {
        "ultimo_periodo_movimentacao_txt",
        "ultimo_mes_trabalhador_ativo_txt",
        "qtd_dias_sem_funcionario_ate_ultima_movimentacao",
        "valor_pfpb_periodo_sem_funcionario",
        "qtd_autorizacoes_periodo_sem_funcionario",
    }
    missing_alerta = [campo for campo in campos_obrigatorios if alerta.get(campo) is None]
    if missing_alerta:
        raise RuntimeError(
            "Contexto eSocial sem campos obrigatorios para alerta de movimentacao sem funcionario: "
            + ", ".join(sorted(missing_alerta))
        )

    periodo_txt = str(alerta["ultimo_periodo_movimentacao_txt"])
    ultimo_mes_ativo_txt = str(alerta["ultimo_mes_trabalhador_ativo_txt"])
    qtd_dias_sem_funcionario = int(alerta["qtd_dias_sem_funcionario_ate_ultima_movimentacao"])
    qtd_dias_txt = _format_decimal_pt(float(qtd_dias_sem_funcionario), 0)
    valor_periodo_txt = _format_decimal_pt(float(alerta["valor_pfpb_periodo_sem_funcionario"]), 2)
    qtd_autorizacoes_periodo = int(alerta["qtd_autorizacoes_periodo_sem_funcionario"])
    qtd_autorizacoes_periodo_txt = _format_decimal_pt(float(qtd_autorizacoes_periodo), 0)
    ano_ultima_mov = int(alerta.get("ano_ultima_movimentacao") or 0)
    ano_ref_esocial = int(alerta.get("ano_esocial_referencia_ultima_movimentacao") or 0)
    sem_esocial_no_ano = bool(alerta.get("is_sem_esocial_no_ano_ultima_movimentacao"))

    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(6)
    _run(
        p,
        f'Observa-se, adicionalmente, que o último mês com movimentação de venda registrada no PFPB para o estabelecimento foi {periodo_txt}, enquanto o último mês com trabalhador ativo vinculado ao estabelecimento na base do eSocial foi {ultimo_mes_ativo_txt}. ',
        color='0F172A',
        size=10,
    )
    _run(
        p,
        f'Assim, foram identificados {qtd_dias_txt} {_plural(qtd_dias_sem_funcionario, "dia", "dias")} sem trabalhador ativo no estabelecimento até a última movimentação registrada. Nesse período, a farmácia apresentou faturamento de R$ {valor_periodo_txt} e {qtd_autorizacoes_periodo_txt} {_plural(qtd_autorizacoes_periodo, "autorização", "autorizações")} no PFPB.',
        color='0F172A',
        size=10,
    )
    if sem_esocial_no_ano and ano_ultima_mov and ano_ref_esocial:
        _run(
            p,
            f' Não foram identificados vínculos no eSocial para {ano_ultima_mov}; por isso, a verificação considerou o último ano trabalhista disponível, {ano_ref_esocial}.',
            color='0F172A',
            size=10,
        )
    _run(
        p,
        ' A situação deve ser confrontada com a documentação operacional, de funcionamento e de responsabilidade técnica da farmácia no período.',
        color='0F172A',
        size=10,
    )


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
        qtd_trab_vinculo = int(row.get("qtd_trabalhadores_vinculo_ano") or 0)
        qtd_farm_vinculo = int(row.get("qtd_farmaceuticos_vinculo_ano") or 0)
        qtd_trab_ativo = int(row.get("qtd_trabalhadores_ativos_competencia") or 0)
        qtd_farm_ativo = int(row.get("qtd_farmaceuticos_ativos_competencia") or 0)
        competencia_txt = row.get("competencia_txt") or "competência-base"
        _run(
            p_intro,
            f'Em consulta à base do eSocial disponível no Sistema Sentinela, atualizada até {dt_carga_txt}, foram identificados vínculos trabalhistas associados à Farmácia {razao_social} somente no ano de {ano}. ',
            color='0F172A',
            size=10,
        )
        if qtd_farm_vinculo > 0:
            _run(
                p_intro,
                f'Para esse exercício, foram apurados {qtd_trab_vinculo} {_plural(qtd_trab_vinculo, "trabalhador com vínculo", "trabalhadores com vínculo")}, com identificação de {qtd_farm_vinculo} {_plural(qtd_farm_vinculo, "trabalhador", "trabalhadores")} com CBO de farmacêutico (223405).',
                color='0F172A',
                size=10,
            )
        else:
            _run(
                p_intro,
                f'Para esse exercício, foram apurados {qtd_trab_vinculo} {_plural(qtd_trab_vinculo, "trabalhador com vínculo", "trabalhadores com vínculo")}, nenhum deles com CBO de farmacêutico (223405).',
                color='0F172A',
                size=10,
            )
            _add_legal_context(
                doc,
                'Assim, a ausência de trabalhador com CBO de farmacêutico entre os vínculos identificados deve ser confrontada com a documentação de responsabilidade técnica e de funcionamento da farmácia.',
            )
        if qtd_trab_ativo == 0 and qtd_trab_vinculo > 0:
            p_ativos = doc.add_paragraph()
            p_ativos.paragraph_format.space_before = Pt(6)
            _run(
                p_ativos,
                f'Na competência-base de {competencia_txt}, contudo, não havia trabalhadores ativos vinculados ao estabelecimento, pois os vínculos localizados possuíam data de rescisão anterior ao encerramento da competência.',
                color='0F172A',
                size=10,
            )
        elif qtd_trab_ativo != qtd_trab_vinculo or qtd_farm_ativo != qtd_farm_vinculo:
            p_ativos = doc.add_paragraph()
            p_ativos.paragraph_format.space_before = Pt(6)
            _run(
                p_ativos,
                f'Na competência-base de {competencia_txt}, permaneciam ativos {qtd_trab_ativo} {_plural(qtd_trab_ativo, "trabalhador", "trabalhadores")}, sendo {qtd_farm_ativo} com CBO de farmacêutico (223405).',
                color='0F172A',
                size=10,
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
    _add_movimentacao_sem_funcionario_alerta(doc, esocial_comp)
