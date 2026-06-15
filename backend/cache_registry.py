"""Registro central dos caches Parquet do Sentinela."""

from dataclasses import dataclass

import polars as pl

import cache_files


@dataclass(frozen=True)
class CacheDefinition:
    key: str
    filename: str
    scope: str
    schema: dict | None = None
    producer: str | None = None


def _falecidos_schema() -> dict:
    return {
        "cpf": pl.Utf8,
        "cnpj": pl.Utf8,
        "nome_falecido": pl.Utf8,
        "municipio_falecido": pl.Utf8,
        "uf_falecido": pl.Utf8,
        "dt_nascimento": pl.Date,
        "dt_obito": pl.Date,
        "fonte_obito": pl.Utf8,
        "data_autorizacao": pl.Date,
        "num_autorizacao": pl.Utf8,
        "qtd_itens_na_autorizacao": pl.Int64,
        "valor_total_autorizacao": pl.Float64,
        "dias_apos_obito": pl.Int64,
    }


def _geografico_origem_uf_schema() -> dict:
    return {
        "id_cnpj": pl.Int32,
        "ano_base": pl.Int16,
        "uf_farmacia": pl.Utf8,
        "uf_paciente": pl.Utf8,
        "is_outra_uf": pl.Boolean,
        "qtd_autorizacoes": pl.Int32,
        "valor_autorizado": pl.Float64,
    }


def _crm_prescricoes_brasil_semestre_schema() -> dict:
    return {
        "id_medico": pl.Utf8,
        "chave_semestre": pl.Int32,
        "nu_prescricoes_total_brasil": pl.Int32,
        "dias_ativos_brasil": pl.Int16,
    }


def _dados_medico_schema() -> dict:
    return {
        "id_medico": pl.Utf8,
        "nu_crm": pl.Int64,
        "sg_uf": pl.Utf8,
        "no_medico": pl.Utf8,
        "dt_primeira_inscricao_uf": pl.Date,
    }


def _matriz_risco_schema() -> dict:
    return {
        "id_cnpj": pl.Int32,
        "ano_base": pl.Int16,
        "valor_total_vendas": pl.Float64,
        "valor_sem_comprovacao": pl.Float64,
        "total_caixas": pl.Int32,
        "total_caixas_sem_comprovacao": pl.Int32,
        "total_autorizacoes": pl.Int32,
        "falecidos_total_autorizacoes": pl.Int32,
        "falecidos_qtd_autorizacoes": pl.Int32,
        "falecidos_valor": pl.Float64,
        "clinico_total_vendas_monitoradas": pl.Int32,
        "clinico_qtd_vendas_suspeitas": pl.Int32,
        "clinico_valor_monitorado": pl.Float64,
        "clinico_valor_suspeito": pl.Float64,
        "teto_total_itens_monitorados": pl.Int32,
        "teto_total_itens": pl.Int32,
        "teto_valor_total": pl.Float64,
        "teto_valor": pl.Float64,
        "polimedicamento_total_autorizacoes": pl.Int32,
        "polimedicamento_total_autorizacoes_4mais": pl.Int32,
        "polimedicamento_valor": pl.Float64,
        "ticket_total_autorizacoes": pl.Int32,
        "receita_paciente_total_pacientes_distintos": pl.Int32,
        "receita_paciente_total_meses_ativos": pl.Int8,
        "per_capita_total_meses_ativos": pl.Int8,
        "per_capita_populacao_municipio": pl.Int32,
        "per_capita_denominador": pl.Int32,
        "vendas_rapidas_total_intervalos": pl.Int32,
        "vendas_rapidas_total": pl.Int32,
        "vendas_rapidas_valor": pl.Float64,
        "volume_atipico_total_semestres_comparaveis": pl.Int8,
        "volume_atipico_total_semestres_atipicos": pl.Int8,
        "volume_atipico_soma_excesso_crescimento_pct": pl.Float64,
        "volume_atipico_valor_aumento_total": pl.Float64,
        "volume_atipico_valor_aumento_atipico": pl.Float64,
        "volume_atipico_maior_taxa_crescimento_pct": pl.Float64,
        "geografico_total_vendas_monitoradas": pl.Int32,
        "geografico_qtd_vendas_outra_uf": pl.Int32,
        "geografico_valor_total": pl.Float64,
        "geografico_valor_outra_uf": pl.Float64,
        "alto_custo_valor": pl.Float64,
        "pico_valor_top3_dias": pl.Float64,
        "hhi_total_prescritores": pl.Int32,
        "hhi_total_prescricoes": pl.Int32,
        "hhi_valor_total": pl.Float64,
        "hhi_valor_top1": pl.Float64,
        "hhi_valor_top5": pl.Float64,
        "hhi_participacao_top1_pct": pl.Float64,
        "hhi_participacao_top5_pct": pl.Float64,
        "val_hhi_crm": pl.Float64,
        "crms_irregulares_total_prescritores": pl.Int32,
        "crms_irregulares_total_prescricoes": pl.Int32,
        "crms_irregulares_valor_total": pl.Float64,
        "crms_irregulares_qtd_nao_localizados": pl.Int32,
        "crms_irregulares_valor_nao_localizados": pl.Float64,
        "crms_irregulares_qtd_antes_registro": pl.Int32,
        "crms_irregulares_valor_antes_registro": pl.Float64,
        "crms_irregulares_qtd": pl.Int32,
        "crms_irregulares_valor": pl.Float64,
        "recorrencia_total_renovacoes_monitoradas": pl.Int32,
        "recorrencia_total_renovacoes_sistemicas": pl.Int32,
        "recorrencia_valor_total": pl.Float64,
        "recorrencia_valor_sistemico": pl.Float64,
    }


GLOBAL_CACHE_DEFINITIONS = (
    CacheDefinition("movimentacao", cache_files.MOVIMENTACAO_PARQUET, "global"),
    CacheDefinition("localidades", cache_files.LOCALIDADES_PARQUET, "global"),
    CacheDefinition("rede", cache_files.REDES_FARMACEUTICAS_PARQUET, "global"),
    CacheDefinition("matriz_risco", cache_files.MATRIZ_RISCO_PARQUET, "global", _matriz_risco_schema()),
    CacheDefinition("bench_crm_uf", cache_files.BENCH_CRM_UF_PARQUET, "global"),
    CacheDefinition("bench_crm_regiao", cache_files.BENCH_CRM_REGIAO_PARQUET, "global"),
    CacheDefinition("bench_crm_br", cache_files.BENCH_CRM_BR_PARQUET, "global"),
    CacheDefinition("crm_prescricoes_brasil_semestre", cache_files.CRM_PRESCRICOES_BRASIL_SEMESTRE_PARQUET, "global", _crm_prescricoes_brasil_semestre_schema()),
    CacheDefinition("dados_medico", cache_files.DADOS_MEDICO_PARQUET, "global", _dados_medico_schema()),
    CacheDefinition("dados_farmacia", cache_files.FARMACIAS_PARQUET, "global"),
    CacheDefinition("perfil_estabelecimento", cache_files.PERFIL_ESTABELECIMENTO_PARQUET, "global"),
    CacheDefinition("dados_socios", cache_files.SOCIOS_PARQUET, "global"),
    CacheDefinition("teia_fonte_nivel2", cache_files.TEIA_FONTE_NIVEL2_PARQUET, "global"),
    CacheDefinition("teia_fonte_nivel3", cache_files.TEIA_FONTE_NIVEL3_PARQUET, "global"),
    CacheDefinition("teia_fonte_nivel4", cache_files.TEIA_FONTE_NIVEL4_PARQUET, "global"),
    CacheDefinition("medicamentos", cache_files.MEDICAMENTOS_PARQUET, "global"),
    CacheDefinition("analise_gtin_inconsistencia_clinica", cache_files.ANALISE_GTIN_INCONSISTENCIA_CLINICA_PARQUET, "global"),
    CacheDefinition("analise_gtin_inconsistencia_clinica_municipio", cache_files.ANALISE_GTIN_INCONSISTENCIA_CLINICA_MUNICIPIO_PARQUET, "global"),
    CacheDefinition("analise_gtin_inconsistencia_clinica_regiao", cache_files.ANALISE_GTIN_INCONSISTENCIA_CLINICA_REGIAO_PARQUET, "global"),
    CacheDefinition("dados_ibge_demografia", cache_files.DADOS_IBGE_DEMOGRAFIA_PARQUET, "global"),
    CacheDefinition("volume_atipico_semestral", cache_files.VOLUME_ATIPICO_SEMESTRAL_PARQUET, "global"),
    CacheDefinition("geografico_origem_uf", cache_files.GEOGRAFICO_ORIGEM_UF_PARQUET, "global", _geografico_origem_uf_schema()),
    CacheDefinition("esocial_cnpj_ano", cache_files.ESOCIAL_CNPJ_ANO_PARQUET, "global"),
    CacheDefinition("esocial_cnpj_trabalhador_ano", cache_files.ESOCIAL_CNPJ_TRABALHADOR_ANO_PARQUET, "global"),
    CacheDefinition("esocial_cnpj_movimentacao_ano", cache_files.ESOCIAL_CNPJ_MOVIMENTACAO_ANO_PARQUET, "global"),
    CacheDefinition("esocial_cnpj_ultima_movimentacao", cache_files.ESOCIAL_CNPJ_ULTIMA_MOVIMENTACAO_PARQUET, "global"),
    CacheDefinition("sentinela_metadados_base", cache_files.SENTINELA_METADADOS_BASE_PARQUET, "global"),
    CacheDefinition("dados_par", cache_files.DADOS_PAR_PARQUET, "global"),
    CacheDefinition("par_teia_alvos", cache_files.PAR_TEIA_ALVOS_PARQUET, "global"),
    CacheDefinition("falecidos", cache_files.FALECIDOS_PARQUET, "global", _falecidos_schema()),
)


def _par_fields() -> dict:
    return {
        "is_par": pl.Boolean,
        "qtd_processos_par": pl.Int32,
        "par_situacoes": pl.Utf8,
        "par_primeira_instauracao": pl.Date,
        "par_ultima_instauracao": pl.Date,
        "par_ultima_conclusao": pl.Date,
    }


def _edge_schema() -> dict:
    return {
        "id": pl.Utf8,
        "source": pl.Utf8,
        "target": pl.Utf8,
        "label": pl.Utf8,
        "type": pl.Utf8,
        "network_level": pl.Utf8,
        "is_ativo": pl.Boolean,
        "data_entrada_sociedade": pl.Date,
        "data_exclusao_sociedade": pl.Date,
    }


def _n2_n4_node_schema() -> dict:
    return {
        "id": pl.Utf8,
        "label": pl.Utf8,
        "type": pl.Utf8,
        "network_level": pl.Utf8,
        "razao_social": pl.Utf8,
        "nome_socio": pl.Utf8,
        "nome_fantasia": pl.Utf8,
        "id_cnae_principal": pl.Int32,
        "cnae_principal": pl.Utf8,
        "id_cnae_secundario": pl.Int32,
        "cnae_secundario": pl.Utf8,
        "municipio": pl.Utf8,
        "uf": pl.Utf8,
        "situacao_rf": pl.Utf8,
        "classification_version": pl.Int16,
        "is_falecido": pl.Boolean,
        "is_cadunico": pl.Boolean,
        "is_esocial": pl.Boolean,
        "is_seguro_defeso": pl.Boolean,
        "is_cnae_farmacia_ausente": pl.Boolean,
        **_par_fields(),
    }


def _n3_node_schema() -> dict:
    return {
        "id": pl.Utf8,
        "label": pl.Utf8,
        "type": pl.Utf8,
        "network_level": pl.Utf8,
        "nome_socio": pl.Utf8,
        "municipio": pl.Utf8,
        "uf": pl.Utf8,
        "is_falecido": pl.Boolean,
        "is_cadunico": pl.Boolean,
        "is_esocial": pl.Boolean,
        "is_seguro_defeso": pl.Boolean,
        "is_cnae_farmacia_ausente": pl.Boolean,
        **_par_fields(),
    }


def _build_cnpj_cache_definitions() -> tuple[CacheDefinition, ...]:
    return (
        CacheDefinition(
            key="memoria_calculo",
            filename=cache_files.MEMORIA_CALCULO_PARQUET,
            scope="cnpj",
            producer="cache_producers.farmacia.load_or_sync_memoria_calculo",
            schema={
                "tipo_linha": pl.Utf8,
                "gtin": pl.Utf8,
                "medicamento": pl.Utf8,
                "periodo_inicial": pl.Utf8,
                "periodo_inicio_irregular": pl.Utf8,
                "periodo_final": pl.Utf8,
                "estoque_inicial": pl.Int64,
                "estoque_final": pl.Int64,
                "vendas": pl.Int64,
                "vendas_irregular": pl.Int64,
                "valor": pl.Float64,
                "valor_irregular": pl.Float64,
                "notas": pl.Utf8,
            },
        ),
        CacheDefinition(
            key="movimentacao_mensal_gtin",
            filename=cache_files.MOVIMENTACAO_MENSAL_GTIN_PARQUET,
            scope="cnpj",
            producer="cache_producers.financeiro.load_or_sync_movimentacao_mensal_gtin",
            schema={
                "codigo_barra": pl.Utf8,
                "periodo": pl.Date,
                "qnt_caixas_vendidas": pl.Int64,
                "qnt_caixas_sem_comprovacao": pl.Int64,
                "num_autorizacoes": pl.Int64,
                "valor_vendas": pl.Float64,
                "valor_sem_comprovacao": pl.Float64,
            },
        ),
        CacheDefinition(
            key="crm_prescritores",
            filename=cache_files.CRM_PRESCRITORES_PARQUET,
            scope="cnpj",
            producer="cache_producers.crm.load_or_sync_crm_data",
            schema={
                "id_medico": pl.Utf8,
                "no_medico": pl.Utf8,
                "competencia": pl.Int32,
                "vl_total_prescricoes": pl.Float64,
                "nu_prescricoes_mes": pl.Int64,
                "nu_prescricoes_total_brasil": pl.Int64,
                "flag_crm_invalido": pl.Int8,
                "flag_prescricao_antes_registro": pl.Int8,
                "alerta_concentracao_multiplos_crms": pl.Int8,
                "flag_concentracao_mesmo_crm": pl.Int8,
                "flag_distancia_geografica": pl.Int8,
                "dt_primeira_prescricao": pl.Utf8,
                "dt_inscricao_crm": pl.Date,
                "nu_estabelecimentos": pl.Int64,
                "_crm_prescritores_cache_version": pl.Int32,
            },
        ),
        CacheDefinition(
            key="geografico",
            filename=cache_files.GEOGRAFICO_PARQUET,
            scope="cnpj",
            producer="cache_producers.crm.load_or_sync_geografico",
            schema={
                "id_medico": pl.Utf8,
                "competencia": pl.Int32,
                "cnpj_a": pl.Utf8,
                "no_municipio_a": pl.Utf8,
                "sg_uf_a": pl.Utf8,
                "dt_ini_a": pl.Utf8,
                "dt_fim_a": pl.Utf8,
                "nu_prescricoes_a": pl.Int32,
                "vl_autorizacoes_a": pl.Float64,
                "cnpj_b": pl.Utf8,
                "no_municipio_b": pl.Utf8,
                "sg_uf_b": pl.Utf8,
                "dt_ini_b": pl.Utf8,
                "dt_fim_b": pl.Utf8,
                "nu_prescricoes_b": pl.Int32,
                "vl_autorizacoes_b": pl.Float64,
                "vl_autorizacoes_total": pl.Float64,
                "distancia_km": pl.Float64,
            },
        ),
        CacheDefinition(
            key="crm_raiox_tx",
            filename=cache_files.CRM_RAIOX_TX_PARQUET,
            scope="cnpj",
            producer="cache_producers.crm.sync_crm_raiox_tx",
            schema={
                "dt_janela": pl.Utf8,
                "hr_janela": pl.Int32,
                "data_hora": pl.Utf8,
                "num_autorizacao": pl.Utf8,
                "id_medico": pl.Utf8,
                "codigo_barra": pl.Utf8,
                "valor_pago": pl.Float64,
                "_crm_raiox_tx_cache_version": pl.Int32,
            },
        ),
        CacheDefinition(
            key="crm_concentracao_unico_alertas",
            filename=cache_files.CRM_CONCENTRACAO_UNICO_ALERTAS_PARQUET,
            scope="cnpj",
            producer="cache_producers.crm.load_or_sync_crm_unico_alertas",
            schema={
                "id_medico": pl.Utf8,
                "competencia": pl.Int32,
                "dt_alerta": pl.Utf8,
                "hr_janela": pl.Int32,
                "nu_prescricoes_dia": pl.Int32,
                "nu_minutos_dia": pl.Int32,
                "nu_minutos_intervalo": pl.Int32,
                "taxa_hora": pl.Float64,
                "dt_ini_hora": pl.Datetime,
                "dt_fim_hora": pl.Datetime,
                "id_severidade": pl.Int32,
                "severidade": pl.Utf8,
                "criterio_pior_ritmo": pl.Utf8,
                "_crm_alerts_cache_version": pl.Int32,
                "nu_5min": pl.Int32,
                "nu_10min": pl.Int32,
                "nu_15min": pl.Int32,
                "nu_20min": pl.Int32,
                "nu_25min": pl.Int32,
                "nu_30min": pl.Int32,
                "nu_60min": pl.Int32,
            },
        ),
        CacheDefinition(
            key="crm_concentracao_multiplo_alertas",
            filename=cache_files.CRM_CONCENTRACAO_MULTIPLO_ALERTAS_PARQUET,
            scope="cnpj",
            producer="cache_producers.crm.load_or_sync_crm_multi_alertas",
            schema={
                "id_cnpj": pl.Int32,
                "competencia": pl.Int32,
                "dt_dia": pl.Utf8,
                "dt_alerta": pl.Utf8,
                "hr_janela": pl.Int32,
                "dt_ini_concentracao": pl.Utf8,
                "dt_fim_concentracao": pl.Utf8,
                "nu_prescricoes": pl.Int32,
                "nu_crms": pl.Int32,
                "nu_60min": pl.Int32,
                "nu_minutos_intervalo": pl.Int32,
                "nu_minutos_span": pl.Int32,
                "taxa_hora": pl.Float64,
                "id_severidade": pl.Int32,
                "nu_crms_distintos": pl.Int32,
                "severidade": pl.Utf8,
                "criterio_pior_ritmo": pl.Utf8,
                "_crm_alerts_cache_version": pl.Int32,
                "nu_5min": pl.Int32,
                "nu_10min": pl.Int32,
                "nu_15min": pl.Int32,
                "nu_20min": pl.Int32,
                "nu_25min": pl.Int32,
                "nu_30min": pl.Int32,
            },
        ),
        CacheDefinition(
            key="crm_perfil_diario",
            filename=cache_files.CRM_PERFIL_DIARIO_PARQUET,
            scope="cnpj",
            producer="cache_producers.crm.load_or_sync_crm_perfil_diario",
            schema={
                "dt_janela": pl.Utf8,
                "competencia": pl.Int32,
                "nu_prescricoes_dia": pl.Int32,
                "nu_crms_distintos": pl.Int32,
                "mediana_diaria": pl.Float64,
                "is_dia_com_volume_horario_anomalo": pl.Int8,
                "is_anomalo_unico": pl.Int8,
                "is_crm_multiplo": pl.Int8,
            },
        ),
        CacheDefinition(
            key="crm_horario",
            filename=cache_files.CRM_HORARIO_PARQUET,
            scope="cnpj",
            producer="cache_producers.crm.load_or_sync_crm_perfil_horario",
            schema={
                "dt_janela": pl.Utf8,
                "hr_janela": pl.Int32,
                "nu_prescricoes": pl.Int32,
                "nu_crms_diferentes": pl.Int32,
                "mediana_hora": pl.Float64,
                "is_hora_com_alerta": pl.Int8,
                "is_volume_horario_anomalo": pl.Int8,
                "is_crm_unico": pl.Int8,
                "is_crm_multiplo": pl.Int8,
            },
        ),
        CacheDefinition(
            key="crm_horario_eventos",
            filename=cache_files.CRM_HORARIO_EVENTOS_PARQUET,
            scope="cnpj",
            producer="cache_producers.crm.load_or_sync_crm_horario_eventos",
            schema={
                "tipo": pl.Utf8,
                "dt_dia": pl.Utf8,
                "id_medico": pl.Utf8,
                "nu_crms_distintos": pl.Int32,
                "dt_ini_concentracao": pl.Datetime,
                "dt_fim_concentracao": pl.Datetime,
                "severidade": pl.Utf8,
                "hora_inicio": pl.Utf8,
                "hora_fim": pl.Utf8,
                "minuto_inicio": pl.Int32,
                "minuto_fim": pl.Int32,
                "_crm_severity_cache_version": pl.Int32,
            },
        ),
        CacheDefinition(
            key="crm_timeline_dia",
            filename=cache_files.CRM_TIMELINE_DIA_PARQUET,
            scope="cnpj",
            producer="cache_producers.crm.load_or_sync_crm_timeline_dia",
            schema={
                "dt_janela": pl.Utf8,
                "competencia": pl.Int32,
                "nu_prescricoes_dia": pl.Int32,
                "nu_crms_distintos": pl.Int32,
                "mediana_diaria": pl.Float64,
                "is_dia_com_volume_horario_anomalo": pl.Int8,
                "is_anomalo_unico": pl.Int8,
                "is_crm_multiplo": pl.Int8,
                "score_crm_unico_hora": pl.Float64,
                "score_crm_unico_qtd": pl.Int32,
                "score_crm_unico_minutos": pl.Int32,
                "score_crm_unico_medico": pl.Utf8,
                "score_crm_multiplo_hora": pl.Float64,
                "score_crm_multiplo_qtd": pl.Int32,
                "score_crm_multiplo_minutos": pl.Int32,
                "score_crm_multiplo_crms": pl.Int32,
            },
        ),
        CacheDefinition(
            key="crm_timeline_hora",
            filename=cache_files.CRM_TIMELINE_HORA_PARQUET,
            scope="cnpj",
            producer="cache_producers.crm.load_or_sync_crm_timeline_hora",
            schema={
                "dt_janela": pl.Utf8,
                "hr_janela": pl.Int32,
                "nu_prescricoes": pl.Int32,
                "nu_crms_diferentes": pl.Int32,
                "mediana_hora": pl.Float64,
                "mad_hora": pl.Float64,
                "is_hora_com_alerta": pl.Int8,
                "is_volume_horario_anomalo": pl.Int8,
                "is_crm_unico": pl.Int8,
                "is_crm_multiplo": pl.Int8,
            },
        ),
        CacheDefinition(
            key="crm_timeline_eventos",
            filename=cache_files.CRM_TIMELINE_EVENTOS_PARQUET,
            scope="cnpj",
            producer="cache_producers.crm.load_or_sync_crm_timeline_eventos",
            schema={
                "dt_janela": pl.Utf8,
                "tipo": pl.Utf8,
                "hora_inicio": pl.Utf8,
                "hora_fim": pl.Utf8,
                "minuto_inicio": pl.Int32,
                "minuto_fim": pl.Int32,
                "severidade": pl.Utf8,
                "id_medico": pl.Utf8,
                "nu_crms_distintos": pl.Int32,
            },
        ),
        CacheDefinition(
            key="mediana_autorizacoes_horaria",
            filename=cache_files.MEDIANA_AUTORIZACOES_HORARIA_PARQUET,
            scope="cnpj",
            producer="cache_producers.crm.sync_mediana_autorizacoes_horaria",
            schema={
                "ano": pl.Int32,
                "trimestre": pl.Int32,
                "hr_janela": pl.Int32,
                "mediana_hora": pl.Float64,
            },
        ),
        CacheDefinition(
            key="mediana_autorizacoes_horaria_movel",
            filename=cache_files.MEDIANA_AUTORIZACOES_HORARIA_MOVEL_PARQUET,
            scope="cnpj",
            producer="cache_producers.crm.sync_mediana_autorizacoes_horaria_movel",
            schema={
                "dt_janela": pl.Date,
                "hr_janela": pl.Int32,
                "mediana_hora_movel": pl.Float64,
                "mad_hora_movel": pl.Float64,
            },
        ),
        CacheDefinition(
            "teia_nivel2_nodes",
            cache_files.TEIA_GRAFO_NIVEL2_NODES_PARQUET,
            "cnpj",
            _n2_n4_node_schema(),
            "cache_producers.network.sync_network",
        ),
        CacheDefinition(
            "teia_nivel2_edges",
            cache_files.TEIA_GRAFO_NIVEL2_EDGES_PARQUET,
            "cnpj",
            _edge_schema(),
            "cache_producers.network.sync_network",
        ),
        CacheDefinition(
            "teia_nivel3_nodes",
            cache_files.TEIA_GRAFO_NIVEL3_NODES_PARQUET,
            "cnpj",
            _n3_node_schema(),
            "cache_producers.network.sync_network",
        ),
        CacheDefinition(
            "teia_nivel3_edges",
            cache_files.TEIA_GRAFO_NIVEL3_EDGES_PARQUET,
            "cnpj",
            _edge_schema(),
            "cache_producers.network.sync_network",
        ),
        CacheDefinition(
            "teia_nivel4_nodes",
            cache_files.TEIA_GRAFO_NIVEL4_NODES_PARQUET,
            "cnpj",
            _n2_n4_node_schema(),
            "cache_producers.network.sync_network",
        ),
        CacheDefinition(
            "teia_nivel4_edges",
            cache_files.TEIA_GRAFO_NIVEL4_EDGES_PARQUET,
            "cnpj",
            _edge_schema(),
            "cache_producers.network.sync_network",
        ),
    )


CNPJ_CACHE_DEFINITIONS = _build_cnpj_cache_definitions()


def get_global_parquet_files_by_key() -> dict[str, str]:
    return {
        definition.key: definition.filename
        for definition in GLOBAL_CACHE_DEFINITIONS
    }


def get_cnpj_parquet_files() -> tuple[str, ...]:
    return tuple(definition.filename for definition in CNPJ_CACHE_DEFINITIONS)


def get_cnpj_cache_definition(key: str) -> CacheDefinition:
    for definition in CNPJ_CACHE_DEFINITIONS:
        if definition.key == key:
            return definition
    raise KeyError(f"Cache CNPJ nao registrado: {key}")


def get_cnpj_parquet_schemas() -> dict[str, dict]:
    schemas: dict[str, dict] = {}
    for definition in CNPJ_CACHE_DEFINITIONS:
        if definition.schema is None:
            raise RuntimeError(f"Cache CNPJ sem schema registrado: {definition.key}")
        schemas[definition.filename] = definition.schema
    return schemas
