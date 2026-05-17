from datetime import date
from typing import Any, Optional

import polars as pl

from data_cache import get_df_matriz_risco
from .falecidos import get_falecidos_data
from .indicadores import _INDICATOR_FLAGS
from .nota_tecnica_docx_utils import _footnote_ref, _run
from .nota_tecnica_formatters import _format_decimal_pt

# ── Mapeamento da Seção 5 ──────────────────────────────────────────────────

_SECAO5_MAP = [
    ('falecidos',                    '5.5',  'Vendas de medicamento para pessoas falecidas'),
    ('incompatibilidade_patologica', '5.6',  'Vendas de medicamento com incompatibilidade patológica'),
    ('teto',                         '5.7',  'Vendas no “teto máximo” para clientes da Farmácia {farmacia} com percentual sobre suas vendas totais muito superior ao dos estabelecimentos de sua região'),
    ('polimedicamento',              '5.8',  'Vendas de quatro ou mais itens de medicamentos por cupom realizadas pela Farmácia {farmacia} com percentual sobre suas vendas totais muito superior ao dos estabelecimentos de sua região'),
    ('ticket_medio',                 '5.10', 'Valor do “ticket médio”, dos medicamentos vendidos pela Farmácia {farmacia}, muito superior ao dos estabelecimentos de sua região'),
    ('receita_paciente',             '5.11', 'Faturamento médio mensal por cliente, obtido pela Farmácia {farmacia}, muito superior ao dos estabelecimentos de sua região'),
    ('per_capita',                   '5.12', 'Faturamento mensal per capita, obtido pela Farmácia {farmacia}, muito superior ao dos estabelecimentos de sua região'),
    ('alto_custo',                   '5.13', 'Vendas de medicamentos de alto custo realizadas pela Farmácia {farmacia} com percentual sobre suas vendas totais muito superior ao dos estabelecimentos de sua região'),
    ('vendas_rapidas',               '5.14', 'Vendas de medicamentos em tempo inferior a 60 segundos'),
    ('recorrencia_sistemica',        '5.15', 'Vendas de medicamentos com precisão absoluta de 30 dias realizadas pela Farmácia {farmacia} com percentual sobre suas vendas totais muito superior ao dos estabelecimentos de sua região'),
    ('dias_pico',                    '5.16', 'Vendas de medicamentos em dias de pico realizadas pela Farmácia {farmacia} com percentual sobre suas vendas totais muito superior ao dos estabelecimentos de sua região'),
    ('dispersao_geografica',         '5.17', 'Vendas para pessoas residentes em outros Estados realizadas pela Farmácia {farmacia} com percentual sobre suas vendas totais muito superior ao dos estabelecimentos de sua região'),
    ('hhi_crm',                      '5.19', 'Concentração atípica de registros do mesmo médico (CRM) no Sistema Autorizador de Vendas do PFPB'),
    ('crms_irregulares',             '5.21', 'Vendas de medicamentos prescritos por médicos com irregularidade em seus CRMs'),
    ('exclusividade_crm',            '5.20', 'Vendas de medicamentos vinculados a CRMs de médicos cujos registros, no Sistema Autorizador de Vendas do PFPB, foram realizados exclusivamente pela Farmácia {farmacia}'),
]
_FORCAR_TODOS_CRITICOS_NOTA_TECNICA = True


def _get_criticos(cnpj: str) -> set[str]:
    """Identifica quais indicadores estão em nível CRÍTICO para o CNPJ."""
    if _FORCAR_TODOS_CRITICOS_NOTA_TECNICA:
        return {key for key, _, _ in _SECAO5_MAP}

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

    datas: list[date] = []
    for t in transacoes:
        data_autorizacao = getattr(t, "data_autorizacao", None)
        if isinstance(data_autorizacao, date):
            datas.append(data_autorizacao)
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
        "transacoes": transacoes,
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

    p2 = doc.add_paragraph()
    _run(
        p2,
        f'O ANEXO III desta Nota Técnica traz o detalhamento de todas as vendas realizadas pela Farmácia {razao_social}, '
        f'{periodo_desc}, na data do óbito da pessoa e/ou posteriormente a essa data.',
        color='0F172A',
        size=10,
    )


def _build_incompatibilidade_patologica_context(
    cnpj: str,
    data_inicio: Optional[date],
    data_fim: Optional[date],
) -> dict[str, Any] | None:
    """Busca os dados atuais da matriz para o texto da incompatibilidade patologica."""
    try:
        df = get_df_matriz_risco()
        df = df.rename({c: c.lower() for c in df.columns})
        rows = df.filter(pl.col("cnpj") == cnpj)
        if rows.is_empty():
            return None
        row = rows.row(0, named=True)
    except Exception as exc:
        print(f"[NOTA_TECNICA] Matriz de risco indisponivel para incompatibilidade patologica {cnpj}: {exc}")
        return None

    def as_float(key: str) -> float:
        value = row.get(key)
        try:
            return float(value or 0)
        except (TypeError, ValueError):
            return 0.0

    if data_inicio and data_fim:
        periodo_desc = (
            f'no ano de {data_inicio.year}'
            if data_inicio.year == data_fim.year
            else f'no periodo de {data_inicio.year} a {data_fim.year}'
        )
    else:
        periodo_desc = 'no periodo analisado'

    return {
        "periodo_desc": periodo_desc,
        "percentual": as_float("pct_clinico"),
        "mediana_regiao": as_float("med_clinico_reg"),
        "mediana_uf": as_float("med_clinico_uf"),
        "mediana_brasil": as_float("med_clinico_br"),
        "multiplicador_regiao": as_float("risco_clinico_reg"),
        "multiplicador_uf": as_float("risco_clinico_uf"),
        "multiplicador_brasil": as_float("risco_clinico_br"),
    }


def _add_incompatibilidade_patologica_text(doc, num: str, razao_social: str, clinico_comp: dict[str, Any]):
    """Adiciona texto analitico de incompatibilidade patologica usando a matriz atual."""
    periodo_desc = clinico_comp["periodo_desc"]
    percentual_fmt = _format_decimal_pt(clinico_comp["percentual"], 2)
    multiplicador_reg_fmt = _format_decimal_pt(clinico_comp["multiplicador_regiao"], 2)
    multiplicador_uf_fmt = _format_decimal_pt(clinico_comp["multiplicador_uf"], 2)
    multiplicador_br_fmt = _format_decimal_pt(clinico_comp["multiplicador_brasil"], 2)

    doc.add_heading(f'{num} Vendas de medicamento com incompatibilidade patológica', level=2)

    p1 = doc.add_paragraph()
    _run(
        p1,
        'O comportamento esperado, no âmbito do PFPB, é que alguns medicamentos destinados a doenças específicas sejam distribuídos guardando correlação com o perfil demográfico do beneficiário, como idade ou sexo. ',
        color='0F172A',
        size=10,
    )
    _run(
        p1,
        'Neste rol, o Sistema Sentinela realiza levantamento detalhado de medicamentos para doença de Parkinson (incomum em pessoas com menos de 50 anos), osteoporose (incomum em homens biológicos), diabetes (incomum em pessoas abaixo de 20 anos) e hipertensão (incomum em pessoas abaixo de 20 anos).',
        color='0F172A',
        size=10,
    )

    p2 = doc.add_paragraph()
    _run(p2, f'Em relação à Farmácia {razao_social}, verificou-se, {periodo_desc}, percentual atípico de vendas desses medicamentos, correspondente a ', color='0F172A', size=10)
    _run(p2, f'{percentual_fmt}%', color='334155', size=10, bold=True)
    _run(p2, ' das vendas monitoradas pelo indicador. Tal percentual é ', color='0F172A', size=10)
    _run(p2, f'{multiplicador_reg_fmt} vezes', color='334155', size=10, bold=True)
    _run(p2, ' superior à mediana dos percentuais de vendas com essa mesma criticidade realizadas pelas farmácias de sua região. ', color='0F172A', size=10)
    _run(p2, 'Ampliando-se o comparativo geográfico, o percentual é ', color='0F172A', size=10)
    _run(p2, f'{multiplicador_uf_fmt} vezes', color='334155', size=10, bold=True)
    _run(p2, ' o das farmácias localizadas em seu Estado e ', color='0F172A', size=10)
    _run(p2, f'{multiplicador_br_fmt} vezes', color='334155', size=10, bold=True)
    _run(p2, ' o das farmácias de todo o Brasil.', color='0F172A', size=10)


def _build_teto_context(
    cnpj: str,
    data_inicio: Optional[date],
    data_fim: Optional[date],
) -> dict[str, Any] | None:
    """Busca os dados atuais da matriz para o texto de vendas no teto maximo."""
    try:
        df = get_df_matriz_risco()
        df = df.rename({c: c.lower() for c in df.columns})
        rows = df.filter(pl.col("cnpj") == cnpj)
        if rows.is_empty():
            return None
        row = rows.row(0, named=True)
    except Exception as exc:
        print(f"[NOTA_TECNICA] Matriz de risco indisponivel para teto maximo {cnpj}: {exc}")
        return None

    def as_float(key: str) -> float:
        value = row.get(key)
        try:
            return float(value or 0)
        except (TypeError, ValueError):
            return 0.0

    if data_inicio and data_fim:
        periodo_desc = (
            f'no ano de {data_inicio.year}'
            if data_inicio.year == data_fim.year
            else f'no período de {data_inicio.year} a {data_fim.year}'
        )
    else:
        periodo_desc = 'no período analisado'

    return {
        "periodo_desc": periodo_desc,
        "percentual": as_float("pct_teto"),
        "mediana_regiao": as_float("med_teto_reg"),
        "mediana_uf": as_float("med_teto_uf"),
        "mediana_brasil": as_float("med_teto_br"),
        "multiplicador_regiao": as_float("risco_teto_reg"),
        "multiplicador_uf": as_float("risco_teto_uf"),
        "multiplicador_brasil": as_float("risco_teto_br"),
    }


def _add_teto_text(doc, num: str, razao_social: str, teto_comp: dict[str, Any]):
    """Adiciona texto analitico de vendas no teto maximo usando a matriz atual."""
    periodo_desc = teto_comp["periodo_desc"]
    percentual_fmt = _format_decimal_pt(teto_comp["percentual"], 2)
    multiplicador_reg_fmt = _format_decimal_pt(teto_comp["multiplicador_regiao"], 2)
    multiplicador_uf_fmt = _format_decimal_pt(teto_comp["multiplicador_uf"], 2)
    multiplicador_br_fmt = _format_decimal_pt(teto_comp["multiplicador_brasil"], 2)

    doc.add_heading(
        f'{num} Vendas no “teto máximo” para clientes da Farmácia {razao_social} com percentual sobre suas vendas totais muito superior ao dos estabelecimentos de sua região',
        level=2,
    )

    p1 = doc.add_paragraph()
    _run(
        p1,
        'O Programa Farmácia Popular do Brasil estabelece limites máximos de quantitativo de retirada mensal pelo cidadão de medicamentos, de acordo com cada um de seus princípios ativos. ',
        color='0F172A',
        size=10,
    )
    _run(
        p1,
        'Retiradas de medicamentos por um CPF no limite máximo mensal são consideradas, para fins de monitoramento, uma “venda no teto”. ',
        color='0F172A',
        size=10,
    )
    _run(
        p1,
        'A expectativa da análise é que o percentual levantado para vendas de medicamento “no teto” pelo estabelecimento acompanhe o padrão das demais farmácias localizadas na mesma região. Percentual muito acima da mediana da região sugere a ocorrência de vendas fictícias.',
        color='0F172A',
        size=10,
    )

    p2 = doc.add_paragraph()
    _run(p2, f'Em relação à Farmácia {razao_social}, verificou-se que, {periodo_desc}, ', color='0F172A', size=10)
    _run(p2, f'{percentual_fmt}%', color='334155', size=10, bold=True)
    _run(p2, ' das vendas de medicamentos por ela efetivadas no âmbito do PFPB foram realizadas no “teto máximo”. Tal percentual é ', color='0F172A', size=10)
    _run(p2, f'{multiplicador_reg_fmt} vezes', color='334155', size=10, bold=True)
    _run(p2, ' superior ao percentual mediano de vendas com esta configuração das farmácias de sua região. ', color='0F172A', size=10)
    _run(p2, 'Ampliando-se o comparativo geográfico, o percentual é ', color='0F172A', size=10)
    _run(p2, f'{multiplicador_uf_fmt} vezes', color='334155', size=10, bold=True)
    _run(p2, ' o das farmácias localizadas no seu Estado e ', color='0F172A', size=10)
    _run(p2, f'{multiplicador_br_fmt} vezes', color='334155', size=10, bold=True)
    _run(p2, ' o das farmácias de todo o Brasil.', color='0F172A', size=10)


def _build_polimedicamento_context(
    cnpj: str,
    data_inicio: Optional[date],
    data_fim: Optional[date],
) -> dict[str, Any] | None:
    """Busca os dados atuais da matriz para o texto de quatro ou mais itens por cupom."""
    try:
        df = get_df_matriz_risco()
        df = df.rename({c: c.lower() for c in df.columns})
        rows = df.filter(pl.col("cnpj") == cnpj)
        if rows.is_empty():
            return None
        row = rows.row(0, named=True)
    except Exception as exc:
        print(f"[NOTA_TECNICA] Matriz de risco indisponivel para polimedicamento {cnpj}: {exc}")
        return None

    def as_float(key: str) -> float:
        value = row.get(key)
        try:
            return float(value or 0)
        except (TypeError, ValueError):
            return 0.0

    if data_inicio and data_fim:
        periodo_desc = (
            f'no ano de {data_inicio.year}'
            if data_inicio.year == data_fim.year
            else f'no período de {data_inicio.year} a {data_fim.year}'
        )
    else:
        periodo_desc = 'no período analisado'

    return {
        "periodo_desc": periodo_desc,
        "percentual": as_float("pct_polimedicamento"),
        "mediana_regiao": as_float("med_polimedicamento_reg"),
        "mediana_uf": as_float("med_polimedicamento_uf"),
        "mediana_brasil": as_float("med_polimedicamento_br"),
        "multiplicador_regiao": as_float("risco_polimedicamento_reg"),
        "multiplicador_uf": as_float("risco_polimedicamento_uf"),
        "multiplicador_brasil": as_float("risco_polimedicamento_br"),
    }


def _add_polimedicamento_text(doc, num: str, razao_social: str, polimedicamento_comp: dict[str, Any]):
    """Adiciona texto analitico de cupons com quatro ou mais medicamentos usando a matriz atual."""
    periodo_desc = polimedicamento_comp["periodo_desc"]
    percentual_fmt = _format_decimal_pt(polimedicamento_comp["percentual"], 2)
    multiplicador_reg_fmt = _format_decimal_pt(polimedicamento_comp["multiplicador_regiao"], 2)
    multiplicador_uf_fmt = _format_decimal_pt(polimedicamento_comp["multiplicador_uf"], 2)
    multiplicador_br_fmt = _format_decimal_pt(polimedicamento_comp["multiplicador_brasil"], 2)

    doc.add_heading(
        f'{num} Vendas de quatro ou mais itens de medicamentos por cupom realizadas pela Farmácia {razao_social} com percentual sobre suas vendas totais muito superior ao dos estabelecimentos de sua região',
        level=2,
    )

    p1 = doc.add_paragraph()
    _run(
        p1,
        'O comportamento esperado, no âmbito do PFPB, é que a grande maioria das vendas contenha apenas um ou dois itens de medicamentos. ',
        color='0F172A',
        size=10,
    )
    _run(
        p1,
        'A ocorrência de cupons de vendas com quatro ou mais medicamentos foge do padrão epidemiológico esperado. Nesse sentido, cupons de vendas com essa composição e emitidos por uma farmácia num padrão muito acima dos demais estabelecimentos da sua região sugerem a ocorrência de vendas fictícias.',
        color='0F172A',
        size=10,
    )

    p2 = doc.add_paragraph()
    _run(p2, f'Em relação à Farmácia {razao_social}, verificou-se que, {periodo_desc}, ', color='0F172A', size=10)
    _run(p2, f'{percentual_fmt}%', color='334155', size=10, bold=True)
    _run(p2, ' das vendas de medicamentos por ela efetivadas no âmbito do PFPB correspondem a cupons de venda contendo quatro ou mais medicamentos. Tal percentual é ', color='0F172A', size=10)
    _run(p2, f'{multiplicador_reg_fmt} vezes', color='334155', size=10, bold=True)
    _run(p2, ' superior ao percentual mediano de vendas com este mesmo perfil das farmácias de sua região. ', color='0F172A', size=10)
    _run(p2, 'Ampliando-se o comparativo geográfico, o percentual é ', color='0F172A', size=10)
    _run(p2, f'{multiplicador_uf_fmt} vezes', color='334155', size=10, bold=True)
    _run(p2, ' o das farmácias localizadas no seu Estado e ', color='0F172A', size=10)
    _run(p2, f'{multiplicador_br_fmt} vezes', color='334155', size=10, bold=True)
    _run(p2, ' o das farmácias de todo o Brasil.', color='0F172A', size=10)


def _build_ticket_medio_context(
    cnpj: str,
    data_inicio: Optional[date],
    data_fim: Optional[date],
) -> dict[str, Any] | None:
    """Busca os dados atuais da matriz para o texto de ticket medio."""
    try:
        df = get_df_matriz_risco()
        df = df.rename({c: c.lower() for c in df.columns})
        rows = df.filter(pl.col("cnpj") == cnpj)
        if rows.is_empty():
            return None
        row = rows.row(0, named=True)
    except Exception as exc:
        print(f"[NOTA_TECNICA] Matriz de risco indisponivel para ticket medio {cnpj}: {exc}")
        return None

    def as_float(key: str) -> float:
        value = row.get(key)
        try:
            return float(value or 0)
        except (TypeError, ValueError):
            return 0.0

    if data_inicio and data_fim:
        periodo_desc = (
            f'no ano de {data_inicio.year}'
            if data_inicio.year == data_fim.year
            else f'no período de {data_inicio.year} a {data_fim.year}'
        )
    else:
        periodo_desc = 'no período analisado'

    return {
        "periodo_desc": periodo_desc,
        "valor": as_float("val_ticket_medio"),
        "mediana_regiao": as_float("med_ticket_reg"),
        "mediana_uf": as_float("med_ticket_uf"),
        "mediana_brasil": as_float("med_ticket_br"),
        "multiplicador_regiao": as_float("risco_ticket_reg"),
        "multiplicador_uf": as_float("risco_ticket_uf"),
        "multiplicador_brasil": as_float("risco_ticket_br"),
    }


def _add_ticket_medio_text(doc, num: str, razao_social: str, ticket_comp: dict[str, Any]):
    """Adiciona texto analitico de ticket medio usando a matriz atual."""
    periodo_desc = ticket_comp["periodo_desc"]
    valor_fmt = _format_decimal_pt(ticket_comp["valor"], 2)
    multiplicador_reg_fmt = _format_decimal_pt(ticket_comp["multiplicador_regiao"], 2)
    multiplicador_uf_fmt = _format_decimal_pt(ticket_comp["multiplicador_uf"], 2)
    multiplicador_br_fmt = _format_decimal_pt(ticket_comp["multiplicador_brasil"], 2)

    doc.add_heading(
        f'{num} Valor do “ticket médio”, dos medicamentos vendidos pela Farmácia {razao_social}, muito superior ao dos estabelecimentos de sua região',
        level=2,
    )

    p1 = doc.add_paragraph()
    _run(
        p1,
        'O comportamento esperado, no âmbito do PFPB, é de que o valor financeiro médio (“ticket médio”) das dispensações de medicamentos de uma farmácia para seus clientes acompanhe o padrão dos estabelecimentos de sua região, num determinado período. ',
        color='0F172A',
        size=10,
    )
    _run(
        p1,
        'A premissa é de baixa elasticidade-preço no mercado de medicamentos na região atendida pela farmácia credenciada. Nesse sentido, valores de ticket médio muito acima do padrão dos demais estabelecimentos sugerem a ocorrência de priorização de itens mais caros ou de uma maximização indevida nas vendas.',
        color='0F172A',
        size=10,
    )

    p2 = doc.add_paragraph()
    _run(p2, f'Em relação à Farmácia {razao_social}, verificou-se que o valor de ticket médio por ela registrado, {periodo_desc}, foi de ', color='0F172A', size=10)
    _run(p2, f'R$ {valor_fmt}', color='334155', size=10, bold=True)
    _run(p2, '. Tal valor é ', color='0F172A', size=10)
    _run(p2, f'{multiplicador_reg_fmt} vezes', color='334155', size=10, bold=True)
    _run(p2, ' superior à mediana dos valores das farmácias de sua região. ', color='0F172A', size=10)
    _run(p2, 'Ampliando-se o comparativo geográfico, o valor é ', color='0F172A', size=10)
    _run(p2, f'{multiplicador_uf_fmt} vezes', color='334155', size=10, bold=True)
    _run(p2, ' o valor mediano das farmácias do seu Estado e ', color='0F172A', size=10)
    _run(p2, f'{multiplicador_br_fmt} vezes', color='334155', size=10, bold=True)
    _run(p2, ' o das farmácias de todo o Brasil.', color='0F172A', size=10)


def _build_receita_paciente_context(
    cnpj: str,
    data_inicio: Optional[date],
    data_fim: Optional[date],
) -> dict[str, Any] | None:
    """Busca os dados atuais da matriz para o texto de faturamento medio mensal por cliente."""
    try:
        df = get_df_matriz_risco()
        df = df.rename({c: c.lower() for c in df.columns})
        rows = df.filter(pl.col("cnpj") == cnpj)
        if rows.is_empty():
            return None
        row = rows.row(0, named=True)
    except Exception as exc:
        print(f"[NOTA_TECNICA] Matriz de risco indisponivel para receita por paciente {cnpj}: {exc}")
        return None

    def as_float(key: str) -> float:
        value = row.get(key)
        try:
            return float(value or 0)
        except (TypeError, ValueError):
            return 0.0

    if data_inicio and data_fim:
        periodo_desc = (
            f'no ano de {data_inicio.year}'
            if data_inicio.year == data_fim.year
            else f'no período de {data_inicio.year} a {data_fim.year}'
        )
    else:
        periodo_desc = 'no período analisado'

    return {
        "periodo_desc": periodo_desc,
        "valor": as_float("val_receita_paciente"),
        "mediana_regiao": as_float("med_receita_paciente_reg"),
        "mediana_uf": as_float("med_receita_paciente_uf"),
        "mediana_brasil": as_float("med_receita_paciente_br"),
        "multiplicador_regiao": as_float("risco_receita_paciente_reg"),
        "multiplicador_uf": as_float("risco_receita_paciente_uf"),
        "multiplicador_brasil": as_float("risco_receita_paciente_br"),
    }


def _add_receita_paciente_text(doc, num: str, razao_social: str, receita_comp: dict[str, Any]):
    """Adiciona texto analitico de faturamento medio mensal por cliente usando a matriz atual."""
    periodo_desc = receita_comp["periodo_desc"]
    valor_fmt = _format_decimal_pt(receita_comp["valor"], 2)
    multiplicador_reg_fmt = _format_decimal_pt(receita_comp["multiplicador_regiao"], 2)
    multiplicador_uf_fmt = _format_decimal_pt(receita_comp["multiplicador_uf"], 2)
    multiplicador_br_fmt = _format_decimal_pt(receita_comp["multiplicador_brasil"], 2)

    doc.add_heading(
        f'{num} Faturamento médio mensal por cliente, obtido pela Farmácia {razao_social}, muito superior ao dos estabelecimentos de sua região',
        level=2,
    )

    p1 = doc.add_paragraph()
    _run(
        p1,
        'O comportamento esperado, no âmbito do PFPB, é que o gasto médio mensal por cliente (CPF) em um estabelecimento farmacêutico num determinado período acompanhe o padrão das demais farmácias localizadas em sua mesma região. ',
        color='0F172A',
        size=10,
    )
    _run(
        p1,
        'Nesse sentido, receita média mensal por paciente obtida por uma farmácia que esteja muito acima do padrão dos demais estabelecimentos sugere a ocorrência de vendas fictícias.',
        color='0F172A',
        size=10,
    )

    p2 = doc.add_paragraph()
    _run(p2, f'Em relação à Farmácia {razao_social}, verificou-se que o valor médio mensal por cliente, {periodo_desc}, foi de ', color='0F172A', size=10)
    _run(p2, f'R$ {valor_fmt}', color='334155', size=10, bold=True)
    _run(p2, '. Tal valor é ', color='0F172A', size=10)
    _run(p2, f'{multiplicador_reg_fmt} vezes', color='334155', size=10, bold=True)
    _run(p2, ' superior ao valor mediano das farmácias de sua região. ', color='0F172A', size=10)
    _run(p2, 'Ampliando-se o comparativo geográfico, o valor é ', color='0F172A', size=10)
    _run(p2, f'{multiplicador_uf_fmt} vezes', color='334155', size=10, bold=True)
    _run(p2, ' o valor mediano das farmácias do seu Estado e ', color='0F172A', size=10)
    _run(p2, f'{multiplicador_br_fmt} vezes', color='334155', size=10, bold=True)
    _run(p2, ' o das farmácias de todo o Brasil.', color='0F172A', size=10)


def _build_per_capita_context(
    cnpj: str,
    data_inicio: Optional[date],
    data_fim: Optional[date],
) -> dict[str, Any] | None:
    """Busca os dados atuais da matriz para o texto de faturamento mensal per capita."""
    try:
        df = get_df_matriz_risco()
        df = df.rename({c: c.lower() for c in df.columns})
        rows = df.filter(pl.col("cnpj") == cnpj)
        if rows.is_empty():
            return None
        row = rows.row(0, named=True)
    except Exception as exc:
        print(f"[NOTA_TECNICA] Matriz de risco indisponivel para per capita {cnpj}: {exc}")
        return None

    def as_float(key: str) -> float:
        value = row.get(key)
        try:
            return float(value or 0)
        except (TypeError, ValueError):
            return 0.0

    if data_inicio and data_fim:
        periodo_desc = (
            f'no ano de {data_inicio.year}'
            if data_inicio.year == data_fim.year
            else f'no período de {data_inicio.year} a {data_fim.year}'
        )
    else:
        periodo_desc = 'no período analisado'

    return {
        "periodo_desc": periodo_desc,
        "valor": as_float("val_per_capita"),
        "mediana_regiao": as_float("med_per_capita_reg"),
        "mediana_uf": as_float("med_per_capita_uf"),
        "mediana_brasil": as_float("med_per_capita_br"),
        "multiplicador_regiao": as_float("risco_per_capita_reg"),
        "multiplicador_uf": as_float("risco_per_capita_uf"),
        "multiplicador_brasil": as_float("risco_per_capita_br"),
    }


def _add_per_capita_text(doc, num: str, razao_social: str, per_capita_comp: dict[str, Any]):
    """Adiciona texto analitico de faturamento mensal per capita usando a matriz atual."""
    periodo_desc = per_capita_comp["periodo_desc"]
    valor_fmt = _format_decimal_pt(per_capita_comp["valor"], 2)
    multiplicador_reg_fmt = _format_decimal_pt(per_capita_comp["multiplicador_regiao"], 2)
    multiplicador_uf_fmt = _format_decimal_pt(per_capita_comp["multiplicador_uf"], 2)
    multiplicador_br_fmt = _format_decimal_pt(per_capita_comp["multiplicador_brasil"], 2)

    doc.add_heading(
        f'{num} Faturamento mensal per capita, obtido pela Farmácia {razao_social}, muito superior ao dos estabelecimentos de sua região',
        level=2,
    )

    p1 = doc.add_paragraph()
    _run(
        p1,
        'O comportamento esperado para o faturamento mensal de uma farmácia, advindo do PFPB, é que ele guarde uma proporção razoável com a população do município onde está localizada. ',
        color='0F172A',
        size=10,
    )
    _run(
        p1,
        'Quando o estabelecimento apresenta valores de vendas per capita mensal muito desproporcionais às farmácias da sua região, tal comportamento sugere forte probabilidade de que ele esteja captando e utilizando CPFs de pessoas residentes em outras regiões.',
        color='0F172A',
        size=10,
    )

    p2 = doc.add_paragraph()
    _run(p2, f'Em relação à Farmácia {razao_social}, verificou-se que seu faturamento mensal per capita, {periodo_desc}, foi de ', color='0F172A', size=10)
    _run(p2, f'R$ {valor_fmt}', color='334155', size=10, bold=True)
    _run(p2, '. Tal valor é ', color='0F172A', size=10)
    _run(p2, f'{multiplicador_reg_fmt} vezes', color='334155', size=10, bold=True)
    _run(p2, ' superior ao valor mediano das farmácias de sua região. ', color='0F172A', size=10)
    _run(p2, 'Ampliando-se o comparativo geográfico, o valor é ', color='0F172A', size=10)
    _run(p2, f'{multiplicador_uf_fmt} vezes', color='334155', size=10, bold=True)
    _run(p2, ' o valor mediano das farmácias do seu Estado e ', color='0F172A', size=10)
    _run(p2, f'{multiplicador_br_fmt} vezes', color='334155', size=10, bold=True)
    _run(p2, ' o das farmácias de todo o Brasil.', color='0F172A', size=10)


def _build_alto_custo_context(
    cnpj: str,
    data_inicio: Optional[date],
    data_fim: Optional[date],
) -> dict[str, Any] | None:
    """Busca os dados atuais da matriz para o texto de medicamentos de alto custo."""
    try:
        df = get_df_matriz_risco()
        df = df.rename({c: c.lower() for c in df.columns})
        rows = df.filter(pl.col("cnpj") == cnpj)
        if rows.is_empty():
            return None
        row = rows.row(0, named=True)
    except Exception as exc:
        print(f"[NOTA_TECNICA] Matriz de risco indisponivel para alto custo {cnpj}: {exc}")
        return None

    def as_float(key: str) -> float:
        value = row.get(key)
        try:
            return float(value or 0)
        except (TypeError, ValueError):
            return 0.0

    if data_inicio and data_fim:
        periodo_desc = (
            f'no ano de {data_inicio.year}'
            if data_inicio.year == data_fim.year
            else f'no período de {data_inicio.year} a {data_fim.year}'
        )
    else:
        periodo_desc = 'no período analisado'

    return {
        "periodo_desc": periodo_desc,
        "percentual": as_float("pct_alto_custo"),
        "mediana_regiao": as_float("med_alto_custo_reg"),
        "mediana_uf": as_float("med_alto_custo_uf"),
        "mediana_brasil": as_float("med_alto_custo_br"),
        "multiplicador_regiao": as_float("risco_alto_custo_reg"),
        "multiplicador_uf": as_float("risco_alto_custo_uf"),
        "multiplicador_brasil": as_float("risco_alto_custo_br"),
    }


def _add_alto_custo_text(doc, num: str, razao_social: str, alto_custo_comp: dict[str, Any]):
    """Adiciona texto analitico de medicamentos de alto custo usando a matriz atual."""
    periodo_desc = alto_custo_comp["periodo_desc"]
    percentual_fmt = _format_decimal_pt(alto_custo_comp["percentual"], 2)
    multiplicador_reg_fmt = _format_decimal_pt(alto_custo_comp["multiplicador_regiao"], 2)
    multiplicador_uf_fmt = _format_decimal_pt(alto_custo_comp["multiplicador_uf"], 2)
    multiplicador_br_fmt = _format_decimal_pt(alto_custo_comp["multiplicador_brasil"], 2)

    doc.add_heading(
        f'{num} Vendas de medicamentos de alto custo realizadas pela Farmácia {razao_social} com percentual sobre suas vendas totais muito superior ao dos estabelecimentos de sua região',
        level=2,
    )

    p1 = doc.add_paragraph()
    _run(
        p1,
        'Os preços dos medicamentos, no âmbito do PFPB, variam em virtude dos seus princípios ativos. O comportamento esperado é que as vendas de uma farmácia apresentem um mix equilibrado de produtos, e não uma concentração atípica apenas em itens de alto valor financeiro. ',
        color='0F172A',
        size=10,
    )
    _run(
        p1,
        'Nesse sentido, a expectativa é que o percentual de venda pela farmácia de medicamentos de alto custo, correspondentes aos 10% mais caros da tabela do PFPB, acompanhe o padrão dos demais estabelecimentos localizados na mesma região.',
        color='0F172A',
        size=10,
    )

    p2 = doc.add_paragraph()
    _run(p2, f'Em relação à Farmácia {razao_social}, verificou-se que, {periodo_desc}, ', color='0F172A', size=10)
    _run(p2, f'{percentual_fmt}%', color='334155', size=10, bold=True)
    _run(p2, ' das vendas de medicamentos por ela efetivadas no âmbito do PFPB correspondem a medicamentos de alto custo. Tal percentual é ', color='0F172A', size=10)
    _run(p2, f'{multiplicador_reg_fmt} vezes', color='334155', size=10, bold=True)
    _run(p2, ' superior ao percentual mediano de vendas com este mesmo perfil das farmácias de sua região. ', color='0F172A', size=10)
    _run(p2, 'Ampliando-se o comparativo geográfico, o percentual é ', color='0F172A', size=10)
    _run(p2, f'{multiplicador_uf_fmt} vezes', color='334155', size=10, bold=True)
    _run(p2, ' o percentual mediano das farmácias do seu Estado e ', color='0F172A', size=10)
    _run(p2, f'{multiplicador_br_fmt} vezes', color='334155', size=10, bold=True)
    _run(p2, ' o das farmácias de todo o Brasil.', color='0F172A', size=10)


def _build_vendas_rapidas_context(
    cnpj: str,
    data_inicio: Optional[date],
    data_fim: Optional[date],
) -> dict[str, Any] | None:
    """Busca os dados atuais da matriz para o texto de vendas em menos de 60 segundos."""
    try:
        df = get_df_matriz_risco()
        df = df.rename({c: c.lower() for c in df.columns})
        rows = df.filter(pl.col("cnpj") == cnpj)
        if rows.is_empty():
            return None
        row = rows.row(0, named=True)
    except Exception as exc:
        print(f"[NOTA_TECNICA] Matriz de risco indisponivel para vendas rapidas {cnpj}: {exc}")
        return None

    def as_float(key: str) -> float:
        value = row.get(key)
        try:
            return float(value or 0)
        except (TypeError, ValueError):
            return 0.0

    if data_inicio and data_fim:
        periodo_desc = (
            f'no ano de {data_inicio.year}'
            if data_inicio.year == data_fim.year
            else f'no período de {data_inicio.year} a {data_fim.year}'
        )
    else:
        periodo_desc = 'no período analisado'

    return {
        "periodo_desc": periodo_desc,
        "percentual": as_float("pct_vendas_rapidas"),
        "mediana_regiao": as_float("med_vendas_rapidas_reg"),
        "mediana_uf": as_float("med_vendas_rapidas_uf"),
        "mediana_brasil": as_float("med_vendas_rapidas_br"),
        "multiplicador_regiao": as_float("risco_vendas_rapidas_reg"),
        "multiplicador_uf": as_float("risco_vendas_rapidas_uf"),
        "multiplicador_brasil": as_float("risco_vendas_rapidas_br"),
    }


def _add_vendas_rapidas_text(doc, num: str, razao_social: str, vendas_rapidas_comp: dict[str, Any]):
    """Adiciona texto analitico de vendas em menos de 60 segundos usando a matriz atual."""
    periodo_desc = vendas_rapidas_comp["periodo_desc"]
    percentual_fmt = _format_decimal_pt(vendas_rapidas_comp["percentual"], 2)
    multiplicador_reg_fmt = _format_decimal_pt(vendas_rapidas_comp["multiplicador_regiao"], 2)
    multiplicador_uf_fmt = _format_decimal_pt(vendas_rapidas_comp["multiplicador_uf"], 2)
    multiplicador_br_fmt = _format_decimal_pt(vendas_rapidas_comp["multiplicador_brasil"], 2)

    doc.add_heading(f'{num} Vendas de medicamentos em tempo inferior a 60 segundos', level=2)

    p1 = doc.add_paragraph()
    _run(
        p1,
        'No âmbito do PFPB, o comportamento esperado é que a dispensação de medicamento para o cidadão, no balcão da farmácia, seja realizada em alguns minutos, tendo em vista o tempo envolvido num atendimento humano padrão, que envolve etapas logísticas como conferência de documentação, busca do produto e assinatura',
        color='0F172A',
        size=10,
    )
    _footnote_ref(
        doc,
        p1,
        16,
        'O art. 25 do Anexo LXXVIII da Portaria de Consolidação nº 5, de 28.09.2017, dispõe da seguinte maneira: “o paciente, obrigatoriamente, deve assinar o cupom vinculado, sendo que uma via deve ser mantida pelo estabelecimento e a outra entregue ao paciente.”',
    )
    _run(p1, '. ', color='0F172A', size=10)
    _run(
        p1,
        'Nesse sentido, dispensações de medicamentos sucessivas em intervalo de tempo inferior a 60 segundos e acima do padrão dos demais estabelecimentos localizados na mesma região sugerem a ocorrência de vendas fictícias.',
        color='0F172A',
        size=10,
    )

    p2 = doc.add_paragraph()
    _run(p2, f'Em relação à Farmácia {razao_social}, verificou-se que, {periodo_desc}, ', color='0F172A', size=10)
    _run(p2, f'{percentual_fmt}%', color='334155', size=10, bold=True)
    _run(p2, ' das vendas de medicamentos por ela efetivadas no âmbito do PFPB foram realizadas em tempo inferior a 60 segundos. Tal percentual é ', color='0F172A', size=10)
    _run(p2, f'{multiplicador_reg_fmt} vezes', color='334155', size=10, bold=True)
    _run(p2, ' superior ao percentual mediano de vendas com esta mesma criticidade das farmácias de sua região. ', color='0F172A', size=10)
    _run(p2, 'Ampliando-se o comparativo geográfico, o percentual é ', color='0F172A', size=10)
    _run(p2, f'{multiplicador_uf_fmt} vezes', color='334155', size=10, bold=True)
    _run(p2, ' o percentual mediano das farmácias do seu Estado e ', color='0F172A', size=10)
    _run(p2, f'{multiplicador_br_fmt} vezes', color='334155', size=10, bold=True)
    _run(p2, ' o das farmácias de todo o Brasil.', color='0F172A', size=10)


def _build_recorrencia_sistemica_context(
    cnpj: str,
    data_inicio: Optional[date],
    data_fim: Optional[date],
) -> dict[str, Any] | None:
    """Busca os dados atuais da matriz para o texto de recorrencia sistemica de 30 dias."""
    try:
        df = get_df_matriz_risco()
        df = df.rename({c: c.lower() for c in df.columns})
        rows = df.filter(pl.col("cnpj") == cnpj)
        if rows.is_empty():
            return None
        row = rows.row(0, named=True)
    except Exception as exc:
        print(f"[NOTA_TECNICA] Matriz de risco indisponivel para recorrencia sistemica {cnpj}: {exc}")
        return None

    def as_float(key: str) -> float:
        value = row.get(key)
        try:
            return float(value or 0)
        except (TypeError, ValueError):
            return 0.0

    if data_inicio and data_fim:
        periodo_desc = (
            f'no ano de {data_inicio.year}'
            if data_inicio.year == data_fim.year
            else f'no período de {data_inicio.year} a {data_fim.year}'
        )
    else:
        periodo_desc = 'no período analisado'

    return {
        "periodo_desc": periodo_desc,
        "percentual": as_float("pct_recorrencia_sistemica"),
        "mediana_regiao": as_float("med_recorrencia_sistemica_reg"),
        "mediana_uf": as_float("med_recorrencia_sistemica_uf"),
        "mediana_brasil": as_float("med_recorrencia_sistemica_br"),
        "multiplicador_regiao": as_float("risco_recorrencia_sistemica_reg"),
        "multiplicador_uf": as_float("risco_recorrencia_sistemica_uf"),
        "multiplicador_brasil": as_float("risco_recorrencia_sistemica_br"),
    }


def _add_recorrencia_sistemica_text(doc, num: str, razao_social: str, recorrencia_comp: dict[str, Any]):
    """Adiciona texto analitico de recorrencia sistemica de 30 dias usando a matriz atual."""
    periodo_desc = recorrencia_comp["periodo_desc"]
    percentual_fmt = _format_decimal_pt(recorrencia_comp["percentual"], 2)
    multiplicador_reg_fmt = _format_decimal_pt(recorrencia_comp["multiplicador_regiao"], 2)
    multiplicador_uf_fmt = _format_decimal_pt(recorrencia_comp["multiplicador_uf"], 2)
    multiplicador_br_fmt = _format_decimal_pt(recorrencia_comp["multiplicador_brasil"], 2)

    doc.add_heading(
        f'{num} Vendas de medicamentos com precisão absoluta de 30 dias realizadas pela Farmácia {razao_social} com percentual sobre suas vendas totais muito superior ao dos estabelecimentos de sua região',
        level=2,
    )

    p1 = doc.add_paragraph()
    _run(
        p1,
        'No âmbito do PFPB, os medicamentos têm limite exato de 30 dias para serem retirados pelos clientes. Uma tentativa de uma nova retirada de um medicamento, dentro desse prazo, ocasiona um bloqueio administrativo da sua dispensação. ',
        color='0F172A',
        size=10,
    )
    _run(
        p1,
        'A expectativa para as retiradas de medicamentos é de que siga um comportamento de consumo real, no qual as datas de retirada costumam variar alguns dias ao longo dos meses, e não de serem realizadas sistematicamente com precisão absoluta de 30 em 30 dias. Nesse sentido, a identificação de vendas de medicamentos realizadas precisamente no prazo de 30 dias e com percentual acima do padrão dos demais estabelecimentos localizados na mesma região sugere indício de agendamento automatizado para vendas fictícias.',
        color='0F172A',
        size=10,
    )

    p2 = doc.add_paragraph()
    _run(p2, f'Em relação à Farmácia {razao_social}, verificou-se que, {periodo_desc}, ', color='0F172A', size=10)
    _run(p2, f'{percentual_fmt}%', color='334155', size=10, bold=True)
    _run(p2, ' das vendas de medicamentos por ela efetivadas no âmbito do PFPB foram realizadas com prazos precisos de 30 dias. Tal percentual é ', color='0F172A', size=10)
    _run(p2, f'{multiplicador_reg_fmt} vezes', color='334155', size=10, bold=True)
    _run(p2, ' superior ao percentual mediano de vendas com esta mesma criticidade das farmácias de sua região. ', color='0F172A', size=10)
    _run(p2, 'Ampliando-se o comparativo geográfico, o percentual é ', color='0F172A', size=10)
    _run(p2, f'{multiplicador_uf_fmt} vezes', color='334155', size=10, bold=True)
    _run(p2, ' o percentual mediano das farmácias do seu Estado e ', color='0F172A', size=10)
    _run(p2, f'{multiplicador_br_fmt} vezes', color='334155', size=10, bold=True)
    _run(p2, ' o das farmácias de todo o Brasil.', color='0F172A', size=10)


def _build_dias_pico_context(
    cnpj: str,
    data_inicio: Optional[date],
    data_fim: Optional[date],
) -> dict[str, Any] | None:
    """Busca os dados atuais da matriz para o texto de vendas em dias de pico."""
    try:
        df = get_df_matriz_risco()
        df = df.rename({c: c.lower() for c in df.columns})
        rows = df.filter(pl.col("cnpj") == cnpj)
        if rows.is_empty():
            return None
        row = rows.row(0, named=True)
    except Exception as exc:
        print(f"[NOTA_TECNICA] Matriz de risco indisponivel para dias de pico {cnpj}: {exc}")
        return None

    def as_float(key: str) -> float:
        value = row.get(key)
        try:
            return float(value or 0)
        except (TypeError, ValueError):
            return 0.0

    if data_inicio and data_fim:
        periodo_desc = (
            f'no ano de {data_inicio.year}'
            if data_inicio.year == data_fim.year
            else f'no período de {data_inicio.year} a {data_fim.year}'
        )
    else:
        periodo_desc = 'no período analisado'

    return {
        "periodo_desc": periodo_desc,
        "percentual": as_float("pct_pico"),
        "mediana_regiao": as_float("med_pico_reg"),
        "mediana_uf": as_float("med_pico_uf"),
        "mediana_brasil": as_float("med_pico_br"),
        "multiplicador_regiao": as_float("risco_pico_reg"),
        "multiplicador_uf": as_float("risco_pico_uf"),
        "multiplicador_brasil": as_float("risco_pico_br"),
    }


def _add_dias_pico_text(doc, num: str, razao_social: str, dias_pico_comp: dict[str, Any]):
    """Adiciona texto analitico de vendas em dias de pico usando a matriz atual."""
    periodo_desc = dias_pico_comp["periodo_desc"]
    percentual_fmt = _format_decimal_pt(dias_pico_comp["percentual"], 2)
    multiplicador_reg_fmt = _format_decimal_pt(dias_pico_comp["multiplicador_regiao"], 2)
    multiplicador_uf_fmt = _format_decimal_pt(dias_pico_comp["multiplicador_uf"], 2)
    multiplicador_br_fmt = _format_decimal_pt(dias_pico_comp["multiplicador_brasil"], 2)

    doc.add_heading(
        f'{num} Vendas de medicamentos em dias de pico realizadas pela Farmácia {razao_social} com percentual sobre suas vendas totais muito superior ao dos estabelecimentos de sua região',
        level=2,
    )

    p1 = doc.add_paragraph()
    _run(
        p1,
        'No âmbito do PFPB, o comportamento esperado para as farmácias é de que suas vendas sejam distribuídas de forma homogênea ao longo do mês. ',
        color='0F172A',
        size=10,
    )
    _run(
        p1,
        'A identificação de registros baixos de venda na maior parte do tempo e altos volumes em dias específicos sugere a ocorrência de “lançamentos em lote”. Nesse sentido, a identificação de vendas em dias de pico realizadas por uma farmácia acima do padrão dos demais estabelecimentos localizados na mesma região sugere a ocorrência de vendas fictícias.',
        color='0F172A',
        size=10,
    )

    p2 = doc.add_paragraph()
    _run(p2, f'Em relação à Farmácia {razao_social}, verificou-se que, {periodo_desc}, ', color='0F172A', size=10)
    _run(p2, f'{percentual_fmt}%', color='334155', size=10, bold=True)
    _run(p2, ' das vendas de medicamentos por ela efetivadas no âmbito do PFPB foram realizadas em dias de pico. Tal percentual é ', color='0F172A', size=10)
    _run(p2, f'{multiplicador_reg_fmt} vezes', color='334155', size=10, bold=True)
    _run(p2, ' superior ao percentual mediano de vendas com esta mesma criticidade das farmácias de sua região. ', color='0F172A', size=10)
    _run(p2, 'Ampliando-se o comparativo geográfico, o percentual é ', color='0F172A', size=10)
    _run(p2, f'{multiplicador_uf_fmt} vezes', color='334155', size=10, bold=True)
    _run(p2, ' o percentual mediano das farmácias do seu Estado e ', color='0F172A', size=10)
    _run(p2, f'{multiplicador_br_fmt} vezes', color='334155', size=10, bold=True)
    _run(p2, ' o das farmácias de todo o Brasil.', color='0F172A', size=10)


def _build_dispersao_geografica_context(
    cnpj: str,
    data_inicio: Optional[date],
    data_fim: Optional[date],
) -> dict[str, Any] | None:
    """Busca os dados atuais da matriz para o texto de dispersao geografica."""
    try:
        df = get_df_matriz_risco()
        df = df.rename({c: c.lower() for c in df.columns})
        rows = df.filter(pl.col("cnpj") == cnpj)
        if rows.is_empty():
            return None
        row = rows.row(0, named=True)
    except Exception as exc:
        print(f"[NOTA_TECNICA] Matriz de risco indisponivel para dispersao geografica {cnpj}: {exc}")
        return None

    def as_float(key: str) -> float:
        value = row.get(key)
        try:
            return float(value or 0)
        except (TypeError, ValueError):
            return 0.0

    if data_inicio and data_fim:
        periodo_desc = (
            f'no ano de {data_inicio.year}'
            if data_inicio.year == data_fim.year
            else f'no período de {data_inicio.year} a {data_fim.year}'
        )
    else:
        periodo_desc = 'no período analisado'

    return {
        "periodo_desc": periodo_desc,
        "percentual": as_float("pct_geografico"),
        "mediana_regiao": as_float("med_geografico_reg"),
        "mediana_uf": as_float("med_geografico_uf"),
        "mediana_brasil": as_float("med_geografico_br"),
        "multiplicador_regiao": as_float("risco_geografico_reg"),
        "multiplicador_uf": as_float("risco_geografico_uf"),
        "multiplicador_brasil": as_float("risco_geografico_br"),
    }


def _add_dispersao_geografica_text(doc, num: str, razao_social: str, dispersao_comp: dict[str, Any]):
    """Adiciona texto analitico de vendas para residentes em outros Estados usando a matriz atual."""
    periodo_desc = dispersao_comp["periodo_desc"]
    percentual_fmt = _format_decimal_pt(dispersao_comp["percentual"], 2)
    multiplicador_reg_fmt = _format_decimal_pt(dispersao_comp["multiplicador_regiao"], 2)
    multiplicador_uf_fmt = _format_decimal_pt(dispersao_comp["multiplicador_uf"], 2)
    multiplicador_br_fmt = _format_decimal_pt(dispersao_comp["multiplicador_brasil"], 2)

    doc.add_heading(
        f'{num} Vendas de medicamentos para pessoas residentes em outros Estados realizadas pela Farmácia {razao_social} com percentual sobre suas vendas totais muito superior ao dos estabelecimentos de sua região',
        level=2,
    )

    p1 = doc.add_paragraph()
    _run(
        p1,
        'No âmbito do PFPB, o comportamento esperado é que a grande maioria dos clientes atendidos pelas farmácias residam no mesmo Estado do estabelecimento. ',
        color='0F172A',
        size=10,
    )
    _run(
        p1,
        'Para tal verificação, é realizado o comparativo entre o endereço do beneficiário, contido na base do Cadastro de Pessoa Física (CPF), e o endereço de registro do próprio estabelecimento, contido no Cadastro Nacional de Pessoa Jurídica (CNPJ). A identificação de vendas de medicamentos para pessoas de outros Estados acima do padrão dos demais estabelecimentos localizados na mesma região sugere a ocorrência de vendas fictícias.',
        color='0F172A',
        size=10,
    )

    p2 = doc.add_paragraph()
    _run(p2, f'Em relação à Farmácia {razao_social}, verificou-se que, {periodo_desc}, ', color='0F172A', size=10)
    _run(p2, f'{percentual_fmt}%', color='334155', size=10, bold=True)
    _run(p2, ' das vendas de medicamentos por ela efetivadas no âmbito do PFPB foram realizadas para pessoas residentes em outros Estados. Tal percentual é ', color='0F172A', size=10)
    _run(p2, f'{multiplicador_reg_fmt} vezes', color='334155', size=10, bold=True)
    _run(p2, ' superior ao percentual mediano de vendas com esta mesma criticidade das farmácias de sua região. ', color='0F172A', size=10)
    _run(p2, 'Ampliando-se o comparativo geográfico, o percentual é ', color='0F172A', size=10)
    _run(p2, f'{multiplicador_uf_fmt} vezes', color='334155', size=10, bold=True)
    _run(p2, ' o percentual mediano das farmácias do seu Estado e ', color='0F172A', size=10)
    _run(p2, f'{multiplicador_br_fmt} vezes', color='334155', size=10, bold=True)
    _run(p2, ' o das farmácias de todo o Brasil.', color='0F172A', size=10)
