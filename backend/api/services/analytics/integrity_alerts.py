from ...schemas.analytics import IntegrityAlertSchema, IntegrityAlertsResponse
from .farmacia import get_dados_farmacia
from .socios import get_socios_farmacia


def get_integrity_alerts(cnpj: str) -> IntegrityAlertsResponse:
    cadastro = get_dados_farmacia(cnpj)
    socios_response = get_socios_farmacia(cnpj)
    alertas: list[IntegrityAlertSchema] = []

    if cadastro.is_cnae_farmacia_ausente:
        alertas.append(
            IntegrityAlertSchema(
                tipo="cnpj_cnae_farmacia_ausente",
                escopo="cnpj",
                entidade_id=cadastro.cnpj,
                entidade_nome=cadastro.nome_fantasia or cadastro.razao_social or cadastro.cnpj,
                severidade="atencao",
                titulo="CNAE compatível com atividade farmacêutica não identificado",
                fonte="Cadastro Nacional da Pessoa Jurídica",
                data_referencia=(
                    cadastro.data_processamento.date()
                    if cadastro.data_processamento is not None
                    else None
                ),
                aba_destino="teia",
            )
        )

    for socio in socios_response.socios:
        if socio.indicador_socio != "PF":
            continue

        entidade_nome = socio.nome_socio or socio.cpf_cnpj_socio
        vinculo_ativo = socio.data_exclusao_sociedade is None

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

        if socio.is_seguro_defeso:
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
