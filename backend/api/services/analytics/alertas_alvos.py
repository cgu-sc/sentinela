from datetime import date
from typing import Optional

import polars as pl
from fastapi import HTTPException

from data_cache import get_df_dados_socios
from .par_teia import apply_par_teia_filter as _apply_par_teia_filter
from .volume_atipico import get_volume_atipico_id_cnpjs_df


SOCIO_BENEFICIO_SCOPES = {
    "direto",
    "n3",
    "direto_n3",
}


SOCIO_BENEFICIO_REQUIRED_COLUMNS = {
    "has_cadunico_direto",
    "has_cadunico_n3",
    "has_seguro_defeso_direto",
    "has_seguro_defeso_n3",
}

SOCIO_ESOCIAL_SCOPES = {
    "direto",
    "n3",
    "direto_n3",
}

SOCIO_ESOCIAL_REQUIRED_COLUMNS = {
    "has_esocial_direto",
    "has_esocial_n3",
}


def _socio_beneficio_scope_expr(scope: str) -> pl.Expr:
    if scope == "direto":
        return pl.col("has_cadunico_direto") | pl.col("has_seguro_defeso_direto")
    if scope == "n3":
        return pl.col("has_cadunico_n3") | pl.col("has_seguro_defeso_n3")
    if scope == "direto_n3":
        return (
            pl.col("has_cadunico_direto")
            | pl.col("has_seguro_defeso_direto")
            | pl.col("has_cadunico_n3")
            | pl.col("has_seguro_defeso_n3")
        )
    raise HTTPException(
        status_code=400,
        detail=(
            f"Filtro socio_beneficio invalido: {scope}. "
            f"Valores aceitos: {sorted(SOCIO_BENEFICIO_SCOPES)}"
        ),
    )


def _socio_esocial_scope_expr(scope: str) -> pl.Expr:
    if scope == "direto":
        return pl.col("has_esocial_direto")
    if scope == "n3":
        return pl.col("has_esocial_n3")
    if scope == "direto_n3":
        return pl.col("has_esocial_direto") | pl.col("has_esocial_n3")
    raise HTTPException(
        status_code=400,
        detail=(
            f"Filtro socio_esocial invalido: {scope}. "
            f"Valores aceitos: {sorted(SOCIO_ESOCIAL_SCOPES)}"
        ),
    )


def apply_socio_beneficio_filter(
    df: pl.DataFrame,
    socio_beneficio: Optional[str],
) -> pl.DataFrame:
    if not socio_beneficio or socio_beneficio == "Todos":
        return df

    missing_columns = SOCIO_BENEFICIO_REQUIRED_COLUMNS - set(df.columns)
    if missing_columns:
        raise HTTPException(
            status_code=500,
            detail=(
                "Filtro socio_beneficio exige colunas no perfil do estabelecimento: "
                + ", ".join(sorted(missing_columns))
            ),
        )

    scope = socio_beneficio.strip().lower()
    filter_expr = _socio_beneficio_scope_expr(scope)
    return df.filter(filter_expr)


def apply_cnae_incompativel_filter(
    df: pl.DataFrame,
    cnae_incompativel: bool,
) -> pl.DataFrame:
    if not cnae_incompativel:
        return df
    if "is_cnae_incompativel_farmaceutico" not in df.columns:
        raise HTTPException(
            status_code=500,
            detail="Filtro cnae_incompativel exige coluna is_cnae_incompativel_farmaceutico no perfil do estabelecimento.",
        )
    return df.filter(pl.col("is_cnae_incompativel_farmaceutico") != 0)


def apply_socio_idade_atipica_filter(
    df: pl.DataFrame,
    socio_idade_atipica: bool,
    data_referencia: Optional[date] = None,
) -> pl.DataFrame:
    """
    Filtra o perfil para CNPJs com ao menos um sócio PF ativo (sem data de
    exclusao) cuja idade na `data_referencia` esteja fora de [21, 80] anos.

    A idade e calculada on-demand a partir de `dados_socios` para evitar
    inconsistência quando um socio cruza a fronteira dos 21 ou 80 anos
    depois que o Parquet foi gerado.
    """
    if not socio_idade_atipica:
        return df
    if "cnpj" not in df.columns:
        raise HTTPException(
            status_code=500,
            detail="Filtro socio_idade_atipica exige coluna 'cnpj' no perfil do estabelecimento.",
        )

    socios = get_df_dados_socios()
    required = {"cnpj", "indicador_socio", "data_exclusao_sociedade", "data_nascimento_socio"}
    if not required.issubset(set(socios.columns)):
        raise HTTPException(
            status_code=500,
            detail=(
                "Filtro socio_idade_atipica exige colunas em dados_socios: "
                + ", ".join(sorted(required - set(socios.columns)))
            ),
        )

    ref = data_referencia or date.today()
    idade_expr = (pl.lit(ref) - pl.col("data_nascimento_socio")).dt.total_days() / 365.25

    cnpjs_idade_atipica = (
        socios
        .filter(
            (pl.col("indicador_socio") == "PF")
            & pl.col("data_exclusao_sociedade").is_null()
            & pl.col("data_nascimento_socio").is_not_null()
        )
        .with_columns(idade_expr.alias("idade_anos"))
        .filter((pl.col("idade_anos") < 21) | (pl.col("idade_anos") > 80))
        .select("cnpj")
        .unique()
    )
    return df.join(cnpjs_idade_atipica, on="cnpj", how="semi")


def apply_socio_esocial_filter(
    df: pl.DataFrame,
    socio_esocial: Optional[str],
) -> pl.DataFrame:
    if not socio_esocial or socio_esocial == "Todos":
        return df

    missing_columns = SOCIO_ESOCIAL_REQUIRED_COLUMNS - set(df.columns)
    if missing_columns:
        raise HTTPException(
            status_code=500,
            detail=(
                "Filtro socio_esocial exige colunas no perfil do estabelecimento: "
                + ", ".join(sorted(missing_columns))
            ),
        )

    scope = socio_esocial.strip().lower()
    filter_expr = _socio_esocial_scope_expr(scope)
    return df.filter(filter_expr)


def apply_volume_atipico_filter(
    df: pl.DataFrame,
    volume_atipico: bool,
    data_inicio: Optional[date] = None,
    data_fim: Optional[date] = None,
    volume_atipico_limite: Optional[float] = None,
) -> pl.DataFrame:
    """
    Restringe o DataFrame a CNPJs com ao menos um semestre de crescimento
    atípico no período informado. Quando `volume_atipico` é False, não
    aplica nada.
    """
    if not volume_atipico:
        return df
    if "id_cnpj" not in df.columns:
        raise HTTPException(
            status_code=500,
            detail="Filtro volume_atipico exige coluna 'id_cnpj' no perfil do estabelecimento.",
        )
    id_cnpjs_volume = get_volume_atipico_id_cnpjs_df(
        data_inicio,
        data_fim,
        volume_atipico_limite,
    ).select(pl.col("id_cnpj").cast(pl.Int64))
    return df.join(id_cnpjs_volume, on="id_cnpj", how="semi")


def build_perfil_filtrado(
    perfil_df: pl.DataFrame,
    *,
    par_teia: Optional[str] = None,
    socio_beneficio: Optional[str] = None,
    socio_esocial: Optional[str] = None,
    cnae_incompativel: bool = False,
    socio_idade_atipica: bool = False,
    data_referencia: Optional[date] = None,
    volume_atipico: bool = False,
    volume_atipico_inicio: Optional[date] = None,
    volume_atipico_fim: Optional[date] = None,
    volume_atipico_limite: Optional[float] = None,
) -> pl.DataFrame:
    """
    Aplica em sequência os filtros de integridade (par_teia, socio_*, cnae,
    socio_idade_atipica) e, opcionalmente, o filtro de volume atípico, sobre
    um `perfil_df` que já deve ter passado pela filtragem geográfica do
    call site (não centraliza UF/regiao/municipio/CNPJ porque cada
    endpoint tem suas particularidades).

    `data_referencia` é a data usada para calcular idade do sócio no
    filtro de idade atípica (tipicamente `data_fim` do período). O
    filtro de volume atípico usa `volume_atipico_inicio` e
    `volume_atipico_fim` (período do crescimento semestral).

    Ordem de aplicação: par_teia → socio_beneficio → socio_esocial →
    cnae_incompativel → socio_idade_atipica → volume_atipico. Cada filtro
    é no-op quando o parâmetro correspondente é o default (None / False).
    """
    df = _apply_par_teia_filter(perfil_df, par_teia)
    df = apply_socio_beneficio_filter(df, socio_beneficio)
    df = apply_socio_esocial_filter(df, socio_esocial)
    df = apply_cnae_incompativel_filter(df, cnae_incompativel)
    df = apply_socio_idade_atipica_filter(df, socio_idade_atipica, data_referencia=data_referencia)
    df = apply_volume_atipico_filter(
        df,
        volume_atipico,
        data_inicio=volume_atipico_inicio,
        data_fim=volume_atipico_fim,
        volume_atipico_limite=volume_atipico_limite,
    )
    return df
