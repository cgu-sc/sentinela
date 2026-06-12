from ...schemas.analytics import IntegrityAlertSchema, IntegrityAlertsResponse
from .socios import get_socios_farmacia


def get_integrity_alerts(cnpj: str) -> IntegrityAlertsResponse:
    socios_response = get_socios_farmacia(cnpj)
    alertas: list[IntegrityAlertSchema] = []

    for socio in socios_response.socios:
        if socio.indicador_socio != "PF" or socio.data_exclusao_sociedade is not None:
            continue

        entidade_nome = socio.nome_socio or socio.cpf_cnpj_socio

        if socio.is_falecido:
            alertas.append(
                IntegrityAlertSchema(
                    tipo="socio_falecido",
                    escopo="socio",
                    entidade_id=socio.cpf_cnpj_socio,
                    entidade_nome=entidade_nome,
                    severidade="critico",
                    titulo="Socio falecido",
                    fonte="Base unificada de obitos",
                    data_referencia=socios_response.data_processamento,
                    aba_destino="socios",
                )
            )

        if socio.is_cadunico:
            alertas.append(
                IntegrityAlertSchema(
                    tipo="socio_cadunico",
                    escopo="socio",
                    entidade_id=socio.cpf_cnpj_socio,
                    entidade_nome=entidade_nome,
                    severidade="atencao",
                    titulo="Socio inscrito no CadUnico",
                    fonte="Cadastro Unico",
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
