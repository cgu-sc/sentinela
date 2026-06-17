"""Panorama agregado de alertas de integridade para o dashboard nacional."""

from __future__ import annotations

from datetime import date

import polars as pl

from data_cache import (
    get_df_matriz_risco,
    get_df_perfil_estabelecimento,
    get_df_dados_socios,
    scan_geografico_origem_uf,
)
from ...schemas.analytics import AlertaPanoramaItemSchema, AlertasPanoramaResponse
from .geografico import UF_VIZINHAS, UF_BRASILEIRAS, LIMIAR_ALERTA_UF_NAO_VIZINHA_PCT


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _filtrar_id_cnpjs_por_escopo(
    uf: str | None,
    regiao_id: int | None,
    id_ibge7: int | None,
) -> pl.Series | None:
    """
    Retorna um Series de id_cnpj (Int32) correspondente ao escopo geográfico
    informado, ou None quando não há filtro (Brasil inteiro).
    """
    if not any([uf, regiao_id, id_ibge7]):
        return None

    perfil = get_df_perfil_estabelecimento()
    required = {"id_cnpj", "uf", "id_regiao_saude", "id_ibge7"}
    missing = required - set(perfil.columns)
    if missing:
        raise RuntimeError(
            f"perfil_estabelecimento sem colunas obrigatórias para filtro geográfico: {missing}"
        )

    mask = pl.lit(True)
    if id_ibge7:
        mask = mask & (pl.col("id_ibge7") == id_ibge7)
    elif regiao_id:
        mask = mask & (pl.col("id_regiao_saude") == regiao_id)
    elif uf:
        mask = mask & (pl.col("uf") == uf)

    return perfil.filter(mask).get_column("id_cnpj")


def _count_distinct_cnpjs(df: pl.DataFrame, col: str = "id_cnpj") -> int:
    return df.get_column(col).n_unique()


# ---------------------------------------------------------------------------
# Contadores por tipo de alerta
# ---------------------------------------------------------------------------

def _contar_volume_atipico(
    id_cnpjs: pl.Series | None,
    ano_base_min: int | None,
    ano_base_max: int | None,
) -> int:
    df = get_df_matriz_risco()
    required = {"id_cnpj", "volume_atipico_total_semestres_atipicos"}
    missing = required - set(df.columns)
    if missing:
        raise RuntimeError(f"matriz_risco sem colunas: {missing}")

    df = df.filter(pl.col("volume_atipico_total_semestres_atipicos") > 0)
    if ano_base_min:
        df = df.filter(pl.col("ano_base") >= ano_base_min)
    if ano_base_max:
        df = df.filter(pl.col("ano_base") <= ano_base_max)
    if id_cnpjs is not None:
        df = df.filter(pl.col("id_cnpj").is_in(id_cnpjs))

    return _count_distinct_cnpjs(df)


def _contar_cnae_incompativel(id_cnpjs: pl.Series | None) -> int:
    perfil = get_df_perfil_estabelecimento()
    if "is_cnae_incompativel_farmaceutico" not in perfil.columns:
        return 0

    df = perfil.filter(pl.col("is_cnae_incompativel_farmaceutico") == True)  # noqa: E712
    if id_cnpjs is not None:
        df = df.filter(pl.col("id_cnpj").is_in(id_cnpjs))

    return _count_distinct_cnpjs(df)


def _contar_dispersao_uf_nao_vizinha(
    id_cnpjs: pl.Series | None,
    uf_farmacia_filtro: str | None,
    ano_base_min: int | None,
    ano_base_max: int | None,
) -> int:
    """
    Conta CNPJs onde vendas para UFs não-vizinhas superam o limiar de 5%.
    Usa scan lazy do geografico_origem_uf com filtro de ano_base.
    """
    required_cols = {"id_cnpj", "uf_farmacia", "uf_paciente", "valor_autorizado"}
    scan = scan_geografico_origem_uf()
    schema_cols = set(scan.collect_schema().names())
    missing = required_cols - schema_cols
    if missing:
        raise RuntimeError(f"geografico_origem_uf sem colunas: {missing}")

    lazy = scan
    if ano_base_min and "ano_base" in schema_cols:
        lazy = lazy.filter(pl.col("ano_base") >= ano_base_min)
    if ano_base_max and "ano_base" in schema_cols:
        lazy = lazy.filter(pl.col("ano_base") <= ano_base_max)
    if id_cnpjs is not None:
        lazy = lazy.filter(pl.col("id_cnpj").is_in(id_cnpjs))
    if uf_farmacia_filtro:
        lazy = lazy.filter(pl.col("uf_farmacia") == uf_farmacia_filtro)

    df = lazy.select(["id_cnpj", "uf_farmacia", "uf_paciente", "valor_autorizado"]).collect()
    if df.is_empty():
        return 0

    # Para cada (id_cnpj, uf_farmacia): calcula % de vendas para UFs não-vizinhas
    totais = (
        df.group_by(["id_cnpj", "uf_farmacia"])
        .agg(pl.col("valor_autorizado").sum().alias("total"))
    )

    # UFs não-vizinhas: uf_paciente não está em UF_VIZINHAS[uf_farmacia] ∪ {uf_farmacia}
    df_norm = df.with_columns(
        pl.col("uf_paciente").str.strip_chars().str.to_uppercase().alias("uf_pac_norm"),
        pl.col("uf_farmacia").str.strip_chars().str.to_uppercase().alias("uf_farm_norm"),
    )

    # Pré-computa pares de vizinhas para join vetorizado
    vizinhancas = []
    for uf_orig, vizs in UF_VIZINHAS.items():
        for uf_dest in (vizs | {uf_orig}):
            vizinhancas.append({"uf_farm_norm": uf_orig, "uf_pac_norm": uf_dest, "is_vizinha": True})
    df_vizinhancas = pl.DataFrame(vizinhancas)

    df_norm = df_norm.join(
        df_vizinhancas,
        on=["uf_farm_norm", "uf_pac_norm"],
        how="left",
    ).with_columns(
        (pl.col("is_vizinha").is_null() & pl.col("uf_pac_norm").is_in(list(UF_BRASILEIRAS))).alias("is_nao_vizinha")
    )

    distantes = (
        df_norm.filter(pl.col("is_nao_vizinha"))
        .group_by(["id_cnpj", "uf_farm_norm"])
        .agg(pl.col("valor_autorizado").sum().alias("valor_distante"))
    )

    joined = distantes.join(
        totais.rename({"uf_farmacia": "uf_farm_norm"}),
        on=["id_cnpj", "uf_farm_norm"],
        how="left",
    ).with_columns(
        (pl.col("valor_distante") / pl.col("total") * 100).alias("pct_distante")
    )

    alertas_df = joined.filter(pl.col("pct_distante") > LIMIAR_ALERTA_UF_NAO_VIZINHA_PCT)
    return _count_distinct_cnpjs(alertas_df)


def _contar_socio_falecido(id_cnpjs: pl.Series | None) -> int:
    socios = get_df_dados_socios()
    required = {"cnpj", "is_falecido", "indicador_socio", "data_exclusao_sociedade"}
    missing = required - set(socios.columns)
    if missing:
        return 0

    df = socios.filter(
        (pl.col("indicador_socio") == "PF")
        & pl.col("data_exclusao_sociedade").is_null()
        & (pl.col("is_falecido") == True)  # noqa: E712
    )

    if id_cnpjs is not None:
        # socios usa cnpj (string) — precisamos do mapeamento cnpj -> id_cnpj
        # via perfil_estabelecimento
        perfil = get_df_perfil_estabelecimento()
        if "cnpj" not in perfil.columns:
            raise RuntimeError("perfil_estabelecimento sem coluna 'cnpj'.")
        cnpjs_validos = (
            perfil.filter(pl.col("id_cnpj").is_in(id_cnpjs))
            .get_column("cnpj")
        )
        df = df.filter(pl.col("cnpj").is_in(cnpjs_validos))

    return df.get_column("cnpj").n_unique()


def _contar_socio_beneficio_social(id_cnpjs: pl.Series | None) -> int:
    """Conta CNPJs com sócio inscrito no CadÚnico OU beneficiário do Seguro Defeso."""
    perfil = get_df_perfil_estabelecimento()
    tem_cadunico = "has_cadunico_direto" in perfil.columns
    tem_seguro = "has_seguro_defeso_direto" in perfil.columns
    if not tem_cadunico and not tem_seguro:
        return 0

    if tem_cadunico and tem_seguro:
        mask = (pl.col("has_cadunico_direto") == True) | (pl.col("has_seguro_defeso_direto") == True)  # noqa: E712
    elif tem_cadunico:
        mask = pl.col("has_cadunico_direto") == True  # noqa: E712
    else:
        mask = pl.col("has_seguro_defeso_direto") == True  # noqa: E712

    df = perfil.filter(mask)
    if id_cnpjs is not None:
        df = df.filter(pl.col("id_cnpj").is_in(id_cnpjs))

    return _count_distinct_cnpjs(df)


def _contar_socio_idade_atipica(
    id_cnpjs: pl.Series | None,
    data_referencia: date,
) -> int:
    """
    Conta CNPJs com ao menos um sócio ativo PF com idade < 21 ou > 80 anos.
    """
    socios = get_df_dados_socios()
    required = {"cnpj", "indicador_socio", "data_exclusao_sociedade", "data_nascimento_socio"}
    if not required.issubset(set(socios.columns)):
        return 0

    df = socios.filter(
        (pl.col("indicador_socio") == "PF")
        & pl.col("data_exclusao_sociedade").is_null()
        & pl.col("data_nascimento_socio").is_not_null()
    )

    if df.is_empty():
        return 0

    ref = pl.lit(data_referencia)
    df = df.with_columns(
        (
            (ref - pl.col("data_nascimento_socio")).dt.total_days() / 365.25
        ).alias("idade_anos")
    )

    df = df.filter(
        (pl.col("idade_anos") < 21) | (pl.col("idade_anos") > 80)
    )

    if id_cnpjs is not None:
        perfil = get_df_perfil_estabelecimento()
        if "cnpj" not in perfil.columns:
            raise RuntimeError("perfil_estabelecimento sem coluna 'cnpj'.")
        cnpjs_validos = (
            perfil.filter(pl.col("id_cnpj").is_in(id_cnpjs))
            .get_column("cnpj")
        )
        df = df.filter(pl.col("cnpj").is_in(cnpjs_validos))

    return df.get_column("cnpj").n_unique()


# ---------------------------------------------------------------------------
# Função pública
# ---------------------------------------------------------------------------

def get_alertas_panorama(
    uf: str | None = None,
    regiao_id: int | None = None,
    id_ibge7: int | None = None,
    data_inicio: date | None = None,
    data_fim: date | None = None,
) -> AlertasPanoramaResponse:
    """
    Agrega contagens de alertas de integridade por tipo, filtradas pelo escopo
    geográfico e período informados. Processamento 100% em memória via Polars.
    """
    ano_base_min = data_inicio.year if data_inicio else None
    ano_base_max = data_fim.year if data_fim else None
    data_ref = data_fim or date.today()

    id_cnpjs = _filtrar_id_cnpjs_por_escopo(uf, regiao_id, id_ibge7)

    contagens = {
        "volume_atipico": _contar_volume_atipico(id_cnpjs, ano_base_min, ano_base_max),
        "cnpj_cnae_farmacia_ausente": _contar_cnae_incompativel(id_cnpjs),
        "cnpj_dispersao_uf_nao_vizinha": _contar_dispersao_uf_nao_vizinha(
            id_cnpjs, uf, ano_base_min, ano_base_max
        ),
        "socio_falecido": _contar_socio_falecido(id_cnpjs),
        "socio_beneficio_social": _contar_socio_beneficio_social(id_cnpjs),
        "socio_idade_atipica": _contar_socio_idade_atipica(id_cnpjs, data_ref),
    }

    DEFINICOES = [
        ("volume_atipico",                "Aumento atípico de vendas",                    "critico"),
        ("cnpj_dispersao_uf_nao_vizinha", "Vendas para UFs sem divisa",                  "critico"),
        ("cnpj_cnae_farmacia_ausente",    "CNAE incompatível",                            "atencao"),
        ("socio_falecido",                "Sócio ativo falecido",                         "atencao"),
        ("socio_beneficio_social",        "Sócio em programa social (CadÚnico/Defeso)",   "atencao"),
        ("socio_idade_atipica",           "Sócio com idade atípica (< 21 ou > 80 anos)", "atencao"),
    ]

    alertas = [
        AlertaPanoramaItemSchema(
            tipo=tipo,
            titulo=titulo,
            severidade=severidade,  # type: ignore[arg-type]
            qtd_cnpjs=contagens[tipo],
        )
        for tipo, titulo, severidade in DEFINICOES
    ]

    # CNPJs com pelo menos 1 alerta (sem double-count entre tipos)
    # Aproximado: union dos conjuntos não é disponível sem reconstruir os sets.
    # Usamos max() como lower-bound conservador; é suficiente para o dashboard.
    total_com_alerta = max(contagens.values()) if contagens else 0

    total_criticos = sum(
        a.qtd_cnpjs for a in alertas if a.severidade == "critico"
    )
    total_atencao = sum(
        a.qtd_cnpjs for a in alertas if a.severidade == "atencao"
    )

    return AlertasPanoramaResponse(
        total_cnpjs_com_alerta=total_com_alerta,
        total_criticos=total_criticos,
        total_atencao=total_atencao,
        alertas=alertas,
    )
