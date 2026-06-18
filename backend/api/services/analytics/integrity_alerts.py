from datetime import date, datetime

import polars as pl

from ...schemas.analytics import IntegrityAlertSchema, IntegrityAlertsResponse
from data_cache import get_df_perfil_estabelecimento
from .farmacia import get_dados_farmacia
from .financeiro import get_evolucao_financeira
from .socios import get_socios_farmacia


def _as_date(value: date | datetime | None) -> date | None:
    if value is None:
        return None
    if isinstance(value, datetime):
        return value.date()
    return value


def _calcular_idade(data_nascimento: date, data_referencia: date) -> int:
    idade = data_referencia.year - data_nascimento.year
    aniversario_nao_ocorreu = (
        data_referencia.month,
        data_referencia.day,
    ) < (
        data_nascimento.month,
        data_nascimento.day,
    )
    if aniversario_nao_ocorreu:
        idade -= 1
    return idade


def _build_alerta_idade_socio(
    *,
    socio,
    entidade_nome: str,
    idade: int,
    data_referencia: date,
) -> IntegrityAlertSchema | None:
    if idade < 18:
        return IntegrityAlertSchema(
            tipo="socio_menor_idade",
            escopo="socio",
            entidade_id=socio.cpf_cnpj_socio,
            entidade_nome=entidade_nome,
            severidade="critico",
            titulo="Sócio menor de idade",
            fonte="Cadastro CPF",
            data_referencia=data_referencia,
            aba_destino="socios",
        )

    if idade < 21:
        return IntegrityAlertSchema(
            tipo="socio_menor_21",
            escopo="socio",
            entidade_id=socio.cpf_cnpj_socio,
            entidade_nome=entidade_nome,
            severidade="atencao",
            titulo="Sócio com menos de 21 anos",
            fonte="Cadastro CPF",
            data_referencia=data_referencia,
            aba_destino="socios",
        )

    if idade > 80:
        return IntegrityAlertSchema(
            tipo="socio_maior_80",
            escopo="socio",
            entidade_id=socio.cpf_cnpj_socio,
            entidade_nome=entidade_nome,
            severidade="atencao",
            titulo="Sócio com mais de 80 anos",
            fonte="Cadastro CPF",
            data_referencia=data_referencia,
            aba_destino="socios",
        )

    return None


def _build_alerta_volume_atipico(
    *,
    cadastro,
    data_inicio: date | None = None,
    data_fim: date | None = None,
    volume_atipico_limite: float | None = None,
) -> IntegrityAlertSchema | None:
    evolucao = get_evolucao_financeira(
        cadastro.cnpj,
        data_inicio=data_inicio,
        data_fim=data_fim,
        volume_atipico_limite=volume_atipico_limite,
    )
    semestres = list(getattr(evolucao, "semestres", None) or [])
    if not semestres:
        return None

    semestres_atipicos = [sem for sem in semestres if bool(getattr(sem, "volume_atipico", False))]
    if not semestres_atipicos:
        return None

    return IntegrityAlertSchema(
        tipo="volume_atipico",
        escopo="cnpj",
        entidade_id=cadastro.cnpj,
        entidade_nome=cadastro.nome_fantasia or cadastro.razao_social or cadastro.cnpj,
        severidade="critico",
        titulo="Crescimento semestral atípico",
        fonte="Evolução financeira semestral",
        data_referencia=(
            cadastro.data_processamento.date()
            if cadastro.data_processamento is not None
            else None
        ),
        aba_destino="movimentacao",
    )


def get_integrity_alerts(
    cnpj: str,
    data_inicio: date | None = None,
    data_fim: date | None = None,
    volume_atipico_limite: float | None = None,
) -> IntegrityAlertsResponse:
    cadastro = get_dados_farmacia(cnpj)
    socios_response = get_socios_farmacia(cnpj)
    alertas: list[IntegrityAlertSchema] = []
    data_referencia_socios = _as_date(socios_response.data_processamento)

    alerta_volume_atipico = _build_alerta_volume_atipico(
        cadastro=cadastro,
        data_inicio=data_inicio,
        data_fim=data_fim,
        volume_atipico_limite=volume_atipico_limite,
    )
    if alerta_volume_atipico is not None:
        alertas.append(alerta_volume_atipico)

    if cadastro.is_cnae_farmacia_ausente:
        alertas.append(
            IntegrityAlertSchema(
                tipo="cnpj_cnae_farmacia_ausente",
                escopo="cnpj",
                entidade_id=cadastro.cnpj,
                entidade_nome=cadastro.nome_fantasia or cadastro.razao_social or cadastro.cnpj,
                severidade="atencao",
                titulo="CNAE incompatível com atividade farmacêutica",
                fonte="Cadastro Nacional da Pessoa Jurídica",
                data_referencia=(
                    cadastro.data_processamento.date()
                    if cadastro.data_processamento is not None
                    else None
                ),
                aba_destino="teia",
            )
        )

    alerta_uf_nao_vizinha = {
        "is_dispersao_uf_nao_vizinha": cadastro.is_dispersao_uf_nao_vizinha,
        "pct_dispersao_uf_nao_vizinha": cadastro.pct_dispersao_uf_nao_vizinha,
        "valor_dispersao_uf_nao_vizinha": cadastro.valor_dispersao_uf_nao_vizinha,
    }
    if data_inicio is not None or data_fim is not None:
        from .geografico import calcular_alerta_uf_nao_vizinha

        perfil_df = get_df_perfil_estabelecimento()
        for coluna in ("cnpj", "id_cnpj", "uf"):
            if coluna not in perfil_df.columns:
                raise RuntimeError(f"Perfil consolidado sem coluna obrigatoria para alerta geografico: {coluna}.")
        perfil = perfil_df.filter(pl.col("cnpj") == cadastro.cnpj)
        if perfil.is_empty():
            raise RuntimeError("Perfil consolidado ausente para calcular alerta geografico por periodo.")
        perfil_row = perfil.select(["id_cnpj", "uf"]).row(0, named=True)
        alerta_uf_nao_vizinha = calcular_alerta_uf_nao_vizinha(
            id_cnpj=int(perfil_row["id_cnpj"]),
            uf_farmacia=str(perfil_row["uf"]),
            data_inicio=data_inicio,
            data_fim=data_fim,
        )

    if alerta_uf_nao_vizinha["is_dispersao_uf_nao_vizinha"]:
        alertas.append(
            IntegrityAlertSchema(
                tipo="cnpj_dispersao_uf_nao_vizinha",
                escopo="cnpj",
                entidade_id=cadastro.cnpj,
                entidade_nome=cadastro.nome_fantasia or cadastro.razao_social or cadastro.cnpj,
                severidade="atencao",
                titulo="Vendas para UFs sem fronteira",
                fonte="Dispersao geografica por UF",
                data_referencia=(
                    cadastro.data_processamento.date()
                    if cadastro.data_processamento is not None
                    else None
                ),
                aba_destino="indicadores",
            )
        )

    for socio in socios_response.socios:
        if socio.indicador_socio != "PF":
            continue

        entidade_nome = socio.nome_socio or socio.cpf_cnpj_socio
        vinculo_ativo = socio.data_exclusao_sociedade is None

        if vinculo_ativo and socio.data_nascimento_socio is not None and data_referencia_socios is not None:
            idade = _calcular_idade(socio.data_nascimento_socio, data_referencia_socios)
            alerta_idade = _build_alerta_idade_socio(
                socio=socio,
                entidade_nome=entidade_nome,
                idade=idade,
                data_referencia=data_referencia_socios,
            )
            if alerta_idade is not None:
                alertas.append(alerta_idade)

        if socio.is_falecido and vinculo_ativo:
            alertas.append(
                IntegrityAlertSchema(
                    tipo="socio_falecido",
                    escopo="socio",
                    entidade_id=socio.cpf_cnpj_socio,
                    entidade_nome=entidade_nome,
                    severidade="critico",
                    titulo="Sócio falecido",
                    fonte="Base unificada de óbitos",
                    data_referencia=socios_response.data_processamento,
                    aba_destino="socios",
                )
            )

        if socio.is_cadunico and vinculo_ativo:
            alertas.append(
                IntegrityAlertSchema(
                    tipo="socio_cadunico",
                    escopo="socio",
                    entidade_id=socio.cpf_cnpj_socio,
                    entidade_nome=entidade_nome,
                    severidade="atencao",
                    titulo="Sócio inscrito no CadÚnico",
                    fonte="CadÚnico",
                    data_referencia=socios_response.data_processamento,
                    aba_destino="socios",
                )
            )

        if socio.is_esocial:
            alertas.append(
                IntegrityAlertSchema(
                    tipo="socio_esocial",
                    escopo="socio",
                    entidade_id=socio.cpf_cnpj_socio,
                    entidade_nome=entidade_nome,
                    severidade="atencao",
                    titulo="Sócio com vínculo trabalhista em outro CNPJ",
                    fonte="eSocial",
                    data_referencia=socios_response.data_processamento,
                    aba_destino="socios",
                )
            )

        if socio.is_seguro_defeso and vinculo_ativo:
            alertas.append(
                IntegrityAlertSchema(
                    tipo="socio_seguro_defeso",
                    escopo="socio",
                    entidade_id=socio.cpf_cnpj_socio,
                    entidade_nome=entidade_nome,
                    severidade="atencao",
                    titulo="Sócio beneficiário do Seguro Defeso",
                    fonte="Seguro Defeso",
                    data_referencia=socios_response.data_processamento,
                    aba_destino="socios",
                )
            )

    alertas.sort(
        key=lambda alerta: (
            0 if alerta.severidade == "critico" else 1,
            alerta.titulo,
            alerta.entidade_nome,
        )
    )

    return IntegrityAlertsResponse(
        cnpj=cnpj,
        total=len(alertas),
        total_criticos=sum(alerta.severidade == "critico" for alerta in alertas),
        total_atencao=sum(alerta.severidade == "atencao" for alerta in alertas),
        alertas=alertas,
        data_processamento=socios_response.data_processamento,
    )
