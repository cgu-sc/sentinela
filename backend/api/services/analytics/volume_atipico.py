from datetime import date
from typing import Optional

import polars as pl

from data_cache import get_df_dados_farmacia, get_df_volume_atipico_semestral

from .indicator_rules import get_volume_atipico_aumento_minimo

DEFAULT_VOLUME_ATIPICO_LIMITE = 50.0
MIN_VOLUME_ATIPICO_LIMITE = 40.0
MAX_VOLUME_ATIPICO_LIMITE = 2000.0
STATUS_SEMESTRE_COMPARAVEL = 1
_VOLUME_ATIPICO_ID_CNPJS_CACHE: dict[
    tuple[int, Optional[int], Optional[int], float, float],
    pl.DataFrame,
] = {}


def normalize_volume_atipico_limite(value: Optional[float]) -> float:
    """Normaliza o limite dinamico de crescimento atipico aceito pela sidebar."""
    if value is None:
        return DEFAULT_VOLUME_ATIPICO_LIMITE
    return max(MIN_VOLUME_ATIPICO_LIMITE, min(MAX_VOLUME_ATIPICO_LIMITE, float(value)))


def _date_to_semester_key(value: date) -> int:
    semestre = 1 if value.month <= 6 else 2
    return value.year * 100 + semestre


def _period_to_semester_keys(
    data_inicio: Optional[date],
    data_fim: Optional[date],
) -> tuple[Optional[int], Optional[int]]:
    inicio_key = _date_to_semester_key(data_inicio) if data_inicio is not None else None
    fim_key = _date_to_semester_key(data_fim) if data_fim is not None else None
    return inicio_key, fim_key


def _assert_volume_schema(df: pl.DataFrame) -> None:
    required = {
        "id_cnpj",
        "chave_semestre",
        "status_semestre",
        "aumento_valor_semestre",
        "taxa_crescimento_pct",
    }
    missing = required - set(df.columns)
    if missing:
        raise RuntimeError(
            "Cache de Volume Atipico Semestral sem colunas obrigatorias: "
            + ", ".join(sorted(missing))
        )


def _cnpj_lookup_df() -> pl.DataFrame:
    farmacias_df = get_df_dados_farmacia()
    required = {"id_cnpj", "cnpj"}
    missing = required - set(farmacias_df.columns)
    if missing:
        raise RuntimeError(
            "Cache de Dados das Farmacias sem colunas obrigatorias para Volume Atipico: "
            + ", ".join(sorted(missing))
        )

    return (
        farmacias_df
        .select([
            pl.col("id_cnpj").cast(pl.Int32),
            pl.col("cnpj").cast(pl.String),
        ])
        .unique(subset=["id_cnpj"])
    )


def _volume_df_for_period(
    data_inicio: Optional[date],
    data_fim: Optional[date],
) -> pl.DataFrame:
    df = get_df_volume_atipico_semestral()
    _assert_volume_schema(df)

    if df.is_empty():
        return df

    inicio_key, fim_key = _period_to_semester_keys(data_inicio, data_fim)
    mask = pl.col("status_semestre").eq(STATUS_SEMESTRE_COMPARAVEL)

    if inicio_key is not None:
        mask = mask & (pl.col("chave_semestre") >= inicio_key)
    if fim_key is not None:
        mask = mask & (pl.col("chave_semestre") <= fim_key)

    return df.filter(mask)


def volume_atipico_flag_expr(limite_percentual: float, aumento_minimo: float | None = None) -> pl.Expr:
    """Regra unica: crescimento percentual acima do limite e aumento material."""
    aumento_minimo = get_volume_atipico_aumento_minimo() if aumento_minimo is None else aumento_minimo
    return (
        (pl.col("taxa_crescimento_pct") > limite_percentual)
        & (pl.col("aumento_valor_semestre") >= aumento_minimo)
    ).fill_null(False)


def is_volume_atipico_relevante(
    taxa_crescimento_pct: Optional[float],
    aumento_valor_semestre: Optional[float],
    limite_percentual: float,
    aumento_minimo: Optional[float] = None,
) -> bool:
    """Aplica a mesma regra para linhas ja materializadas em dict."""
    if taxa_crescimento_pct is None or aumento_valor_semestre is None:
        return False
    aumento_minimo = get_volume_atipico_aumento_minimo() if aumento_minimo is None else aumento_minimo
    return (
        taxa_crescimento_pct > limite_percentual
        and aumento_valor_semestre >= aumento_minimo
    )


def get_volume_atipico_period_metrics(
    data_inicio: Optional[date],
    data_fim: Optional[date],
    limite_percentual: Optional[float] = None,
) -> pl.DataFrame:
    """
    Calcula metricas dinamicas de volume atipico por CNPJ no periodo informado.

    O semestre avaliado precisa estar dentro do periodo. A tabela semestral ja
    traz a chave do ultimo semestre valido anterior para exibicao da transicao.
    """
    limite = normalize_volume_atipico_limite(limite_percentual)
    aumento_minimo = get_volume_atipico_aumento_minimo()
    df_periodo = _volume_df_for_period(data_inicio, data_fim)

    if df_periodo.is_empty():
        return pl.DataFrame()

    flag_expr = volume_atipico_flag_expr(limite, aumento_minimo)
    excesso_expr = (
        pl.when(flag_expr)
        .then(pl.col("taxa_crescimento_pct") - limite)
        .otherwise(0.0)
        .alias("excesso_volume_atipico")
    )

    metrics_df = (
        df_periodo
        .with_columns([
            excesso_expr,
            flag_expr.cast(pl.Int8).alias("flag_semestre_atipico"),
        ])
        .group_by("id_cnpj")
        .agg([
            pl.len().alias("qtd_comparacoes_volume_atipico"),
            pl.sum("flag_semestre_atipico").alias("qtd_semestres_atipicos"),
            pl.max("taxa_crescimento_pct").alias("maior_crescimento_pct"),
            pl.sum("excesso_volume_atipico").alias("soma_excesso_volume_atipico"),
        ])
        .with_columns([
            (
                pl.col("soma_excesso_volume_atipico") /
                pl.when(pl.col("qtd_comparacoes_volume_atipico") > 0)
                .then(pl.col("qtd_comparacoes_volume_atipico").cast(pl.Float64))
                .otherwise(None)
            ).fill_null(0.0).alias("risco_final_volume_atipico"),
            (
                pl.col("soma_excesso_volume_atipico") /
                pl.when(pl.col("qtd_semestres_atipicos") > 0)
                .then(pl.col("qtd_semestres_atipicos").cast(pl.Float64))
                .otherwise(None)
            ).fill_null(0.0).alias("risco_magnitude_volume_atipico"),
            (
                pl.col("qtd_semestres_atipicos").cast(pl.Float64) /
                pl.when(pl.col("qtd_comparacoes_volume_atipico") > 0)
                .then(pl.col("qtd_comparacoes_volume_atipico").cast(pl.Float64))
                .otherwise(None)
            ).fill_null(0.0).alias("risco_frequencia_volume_atipico"),
        ])
    )

    return metrics_df.join(_cnpj_lookup_df(), on="id_cnpj", how="inner")


def get_volume_atipico_id_cnpjs_df(
    data_inicio: Optional[date],
    data_fim: Optional[date],
    limite_percentual: Optional[float] = None,
) -> pl.DataFrame:
    """Retorna id_cnpj de estabelecimentos com ao menos um semestre acima do limite."""
    limite = normalize_volume_atipico_limite(limite_percentual)
    aumento_minimo = get_volume_atipico_aumento_minimo()
    df = get_df_volume_atipico_semestral()
    empty = pl.DataFrame({"id_cnpj": []}, schema={"id_cnpj": pl.Int32})

    inicio_key, fim_key = _period_to_semester_keys(data_inicio, data_fim)
    cache_key = (
        id(df),
        inicio_key,
        fim_key,
        limite,
        aumento_minimo,
    )
    cached = _VOLUME_ATIPICO_ID_CNPJS_CACHE.get(cache_key)
    if cached is not None:
        return cached

    df_periodo = _volume_df_for_period(data_inicio, data_fim)
    if df_periodo.is_empty():
        return empty

    result = (
        df_periodo
        .filter(volume_atipico_flag_expr(limite, aumento_minimo))
        .select(pl.col("id_cnpj").cast(pl.Int32))
        .unique()
    )

    if len(_VOLUME_ATIPICO_ID_CNPJS_CACHE) >= 64:
        _VOLUME_ATIPICO_ID_CNPJS_CACHE.clear()
    _VOLUME_ATIPICO_ID_CNPJS_CACHE[cache_key] = result
    return result
