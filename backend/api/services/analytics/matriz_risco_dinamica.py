from __future__ import annotations

import time
from datetime import date
from threading import RLock

import polars as pl

from data_cache import (
    get_cache_generation,
    get_df_matriz_risco,
    get_df_perfil_estabelecimento,
)
from .indicator_config import (
    INDICATOR_AGGREGATIONS as _INDICATOR_AGGREGATIONS,
    INDICATOR_FLAGS as _INDICATOR_FLAGS,
    INDICATOR_MAPPING,
    INDICATOR_MZ_THRESHOLDS as _INDICATOR_MZ_THRESHOLDS,
    INDICATOR_SCORE_WEIGHTS as _INDICATOR_SCORE_WEIGHTS,
    ZERO_BASELINE_CRITICAL_INDICATORS as _ZERO_BASELINE_CRITICAL_INDICATORS,
)
from .indicator_rules import (
    FALECIDOS_VALOR_LIMITE_ATENCAO,
    NAO_COMPROVACAO_PCT_ATENCAO,
    NAO_COMPROVACAO_PCT_CRITICO,
    VOLUME_ATIPICO_AUMENTO_MINIMO,
)


MZ_SCALE = 0.6745
MIN_REGIAO_BENCHMARK = 40

_MATRIX_COMPONENT_COLUMNS = {
    "id_cnpj",
    "ano_base",
    "valor_total_vendas",
    "valor_sem_comprovacao",
    "total_caixas",
    "total_caixas_sem_comprovacao",
    "total_autorizacoes",
    "falecidos_total_autorizacoes",
    "falecidos_qtd_autorizacoes",
    "falecidos_valor",
    "clinico_total_vendas_monitoradas",
    "clinico_qtd_vendas_suspeitas",
    "clinico_valor_monitorado",
    "clinico_valor_suspeito",
    "teto_total_itens_monitorados",
    "teto_total_itens",
    "teto_valor_total",
    "teto_valor",
    "polimedicamento_total_autorizacoes",
    "polimedicamento_total_autorizacoes_4mais",
    "polimedicamento_valor",
    "ticket_total_autorizacoes",
    "receita_paciente_total_pacientes_distintos",
    "receita_paciente_total_meses_ativos",
    "per_capita_total_meses_ativos",
    "per_capita_populacao_municipio",
    "per_capita_denominador",
    "vendas_rapidas_total_intervalos",
    "vendas_rapidas_total",
    "vendas_rapidas_valor",
    "volume_atipico_total_semestres_comparaveis",
    "volume_atipico_total_semestres_atipicos",
    "volume_atipico_soma_excesso_crescimento_pct",
    "volume_atipico_valor_aumento_total",
    "volume_atipico_valor_aumento_atipico",
    "volume_atipico_maior_taxa_crescimento_pct",
    "geografico_total_vendas_monitoradas",
    "geografico_qtd_vendas_outra_uf",
    "geografico_valor_total",
    "geografico_valor_outra_uf",
    "alto_custo_valor",
    "pico_valor_top3_dias",
    "hhi_total_prescritores",
    "hhi_total_prescricoes",
    "hhi_valor_total",
    "hhi_valor_top1",
    "hhi_valor_top5",
    "val_hhi_crm",
    "crms_irregulares_total_prescritores",
    "crms_irregulares_total_prescricoes",
    "crms_irregulares_valor_total",
    "crms_irregulares_qtd_nao_localizados",
    "crms_irregulares_valor_nao_localizados",
    "crms_irregulares_qtd_antes_registro",
    "crms_irregulares_valor_antes_registro",
    "crms_irregulares_qtd",
    "crms_irregulares_valor",
    "recorrencia_total_renovacoes_monitoradas",
    "recorrencia_total_renovacoes_sistemicas",
    "recorrencia_valor_total",
    "recorrencia_valor_sistemico",
}

_DYNAMIC_CACHE_TTL_SECONDS = 300
_DYNAMIC_CACHE_MAX_ENTRIES = 24
_DYNAMIC_CACHE_LOCK = RLock()
_DYNAMIC_CACHE: dict[tuple[object, ...], tuple[float, pl.DataFrame]] = {}


def _period_year_bounds(data_inicio: date | None, data_fim: date | None) -> tuple[int | None, int | None]:
    return (
        data_inicio.year if data_inicio is not None else None,
        data_fim.year if data_fim is not None else None,
    )


def _metric_ratio_expr(numerator: str, denominator: str, factor: float, alias: str) -> pl.Expr:
    return (
        pl.when(pl.col(denominator).is_not_null() & (pl.col(denominator) > 0))
        .then(pl.col(numerator) / pl.col(denominator) * factor)
        .otherwise(pl.lit(None, dtype=pl.Float64))
        .alias(alias)
    )


def _risk_ratio_expr(value_col: str, median_col: str, alias: str) -> pl.Expr:
    return (
        pl.when(pl.col(value_col).is_null() | pl.col(median_col).is_null() | (pl.col(median_col) <= 0))
        .then(pl.lit(None, dtype=pl.Float64))
        .otherwise(pl.col(value_col) / pl.col(median_col))
        .alias(alias)
    )


def _deviation_expr(value_col: str, median_col: str, alias: str) -> pl.Expr:
    return (
        pl.when(pl.col(value_col).is_not_null() & pl.col(median_col).is_not_null())
        .then((pl.col(value_col) - pl.col(median_col)).abs())
        .otherwise(pl.lit(None, dtype=pl.Float64))
        .alias(alias)
    )


def _modified_z_expr(value_col: str, median_col: str, mad_col: str, alias: str) -> pl.Expr:
    return (
        pl.when(
            pl.col(value_col).is_not_null()
            & pl.col(median_col).is_not_null()
            & pl.col(mad_col).is_not_null()
            & (pl.col(mad_col) > 0)
        )
        .then((pl.lit(MZ_SCALE) * (pl.col(value_col) - pl.col(median_col))) / pl.col(mad_col))
        .otherwise(pl.lit(None, dtype=pl.Float64))
        .alias(alias)
    )


def _percent_rank_expr(order_col: str, scope_cols: list[str] | None, alias: str) -> pl.Expr:
    order_expr = pl.col(order_col).fill_null(0.0)
    rank = order_expr.rank(method="min")
    total = pl.len()
    if scope_cols:
        rank = rank.over(scope_cols)
        total = total.over(scope_cols)
    return (
        pl.when(total > 1)
        .then(((rank - 1) / (total - 1)) * 100.0)
        .otherwise(pl.lit(0.0))
        .cast(pl.Float64)
        .alias(alias)
    )


def _rank_expr(scope_cols: list[str] | None, alias: str) -> pl.Expr:
    valid_score = pl.col("score_risco_final").is_not_null()
    rank = pl.col("score_risco_final").rank(method="min", descending=True)
    if scope_cols:
        rank = rank.over(scope_cols)
    return pl.when(valid_score).then(rank).otherwise(pl.lit(None, dtype=pl.UInt32)).cast(pl.Int64).alias(alias)


def _total_expr(scope_cols: list[str] | None, alias: str) -> pl.Expr:
    total = pl.col("score_risco_final").is_not_null().sum()
    if scope_cols:
        total = total.over(scope_cols)
    return total.cast(pl.Int64).alias(alias)


def _with_classificacao_and_rankings(df: pl.DataFrame) -> pl.DataFrame:
    critical_cols = [cols[1] for cols in _INDICATOR_FLAGS.values()]
    attention_cols = [cols[0] for cols in _INDICATOR_FLAGS.values()]
    return (
        df.with_columns([
            pl.sum_horizontal(*(pl.col(col).fill_null(0).cast(pl.Int32) for col in critical_cols)).alias("qtd_indicadores_criticos"),
            pl.sum_horizontal(*(pl.col(col).fill_null(0).cast(pl.Int32) for col in attention_cols)).alias("qtd_indicadores_atencao"),
        ])
        .with_columns([
            pl.when(pl.col("qtd_indicadores_criticos") > 0)
            .then(pl.lit("CRÍTICO"))
            .when(pl.col("qtd_indicadores_atencao") > 0)
            .then(pl.lit("ATENÇÃO"))
            .otherwise(pl.lit("NORMAL"))
            .alias("classificacao_risco"),
        ])
        .with_columns([
            _rank_expr(None, "rank_nacional"),
            _total_expr(None, "total_nacional"),
            _rank_expr(["uf"], "rank_uf"),
            _total_expr(["uf"], "total_uf"),
            _rank_expr(["id_regiao_saude"], "rank_regiao_saude"),
            _total_expr(["id_regiao_saude"], "total_regiao_saude"),
            _rank_expr(["id_ibge7"], "rank_municipio"),
            _total_expr(["id_ibge7"], "total_municipio"),
        ])
    )


def _compute_dynamic_matriz_risco(
    *,
    data_inicio: date | None = None,
    data_fim: date | None = None,
    perfil_df: pl.DataFrame | None = None,
) -> pl.DataFrame:
    matriz_raw = get_df_matriz_risco()
    matriz = matriz_raw.rename({c: c.lower() for c in matriz_raw.columns})
    ano_inicio, ano_fim = _period_year_bounds(data_inicio, data_fim)
    if ano_inicio is not None:
        matriz = matriz.filter(pl.col("ano_base") >= ano_inicio)
    if ano_fim is not None:
        matriz = matriz.filter(pl.col("ano_base") <= ano_fim)
    if matriz.is_empty():
        return pl.DataFrame()

    missing_cols = _MATRIX_COMPONENT_COLUMNS - set(matriz.columns)
    if missing_cols:
        raise RuntimeError(
            "matriz_risco.parquet sem colunas obrigatorias para calculo dinamico: "
            + ", ".join(sorted(missing_cols))
        )

    aggregated = (
        matriz
        .with_columns([
            (
                pl.col("receita_paciente_total_pacientes_distintos").cast(pl.Float64)
                * pl.col("receita_paciente_total_meses_ativos").cast(pl.Float64)
            ).alias("_receita_paciente_denominador_ano"),
            (
                pl.col("val_hhi_crm").cast(pl.Float64)
                * pl.col("hhi_valor_total").cast(pl.Float64)
            ).alias("_hhi_valor_ponderado_ano"),
        ])
        .group_by("id_cnpj")
        .agg([
            pl.col("valor_total_vendas").sum().alias("valor_total_vendas"),
            pl.col("valor_sem_comprovacao").sum().alias("valor_sem_comprovacao"),
            pl.col("total_caixas").sum().alias("total_caixas"),
            pl.col("total_caixas_sem_comprovacao").sum().alias("total_caixas_sem_comprovacao"),
            pl.col("total_autorizacoes").sum().alias("total_autorizacoes"),
            pl.col("falecidos_total_autorizacoes").sum().alias("falecidos_total_autorizacoes"),
            pl.col("falecidos_qtd_autorizacoes").sum().alias("falecidos_qtd_autorizacoes"),
            pl.col("falecidos_valor").sum().alias("falecidos_valor"),
            pl.col("clinico_total_vendas_monitoradas").sum().alias("clinico_total_vendas_monitoradas"),
            pl.col("clinico_qtd_vendas_suspeitas").sum().alias("clinico_qtd_vendas_suspeitas"),
            pl.col("clinico_valor_monitorado").sum().alias("clinico_valor_monitorado"),
            pl.col("clinico_valor_suspeito").sum().alias("clinico_valor_suspeito"),
            pl.col("teto_total_itens_monitorados").sum().alias("teto_total_itens_monitorados"),
            pl.col("teto_total_itens").sum().alias("teto_total_itens"),
            pl.col("teto_valor_total").sum().alias("teto_valor_total"),
            pl.col("teto_valor").sum().alias("teto_valor"),
            pl.col("polimedicamento_total_autorizacoes").sum().alias("polimedicamento_total_autorizacoes"),
            pl.col("polimedicamento_total_autorizacoes_4mais").sum().alias("polimedicamento_total_autorizacoes_4mais"),
            pl.col("polimedicamento_valor").sum().alias("polimedicamento_valor"),
            pl.col("ticket_total_autorizacoes").sum().alias("ticket_total_autorizacoes"),
            pl.col("receita_paciente_total_pacientes_distintos").sum().alias("receita_paciente_total_pacientes_distintos"),
            pl.col("receita_paciente_total_meses_ativos").sum().alias("receita_paciente_total_meses_ativos"),
            pl.col("_receita_paciente_denominador_ano").sum().alias("receita_paciente_denominador"),
            pl.col("per_capita_total_meses_ativos").sum().alias("per_capita_total_meses_ativos"),
            pl.col("per_capita_populacao_municipio").max().alias("per_capita_populacao_municipio"),
            pl.col("per_capita_denominador").sum().alias("per_capita_denominador"),
            pl.col("vendas_rapidas_total_intervalos").sum().alias("vendas_rapidas_total_intervalos"),
            pl.col("vendas_rapidas_total").sum().alias("vendas_rapidas_total"),
            pl.col("vendas_rapidas_valor").sum().alias("vendas_rapidas_valor"),
            pl.col("volume_atipico_total_semestres_comparaveis").sum().alias("volume_atipico_total_semestres_comparaveis"),
            pl.col("volume_atipico_total_semestres_atipicos").sum().alias("volume_atipico_total_semestres_atipicos"),
            pl.col("volume_atipico_soma_excesso_crescimento_pct").sum().alias("volume_atipico_soma_excesso_crescimento_pct"),
            pl.col("volume_atipico_valor_aumento_total").sum().alias("volume_atipico_valor_aumento_total"),
            pl.col("volume_atipico_valor_aumento_atipico").sum().alias("volume_atipico_valor_aumento_atipico"),
            pl.col("volume_atipico_maior_taxa_crescimento_pct").max().alias("volume_atipico_maior_taxa_crescimento_pct"),
            pl.col("geografico_total_vendas_monitoradas").sum().alias("geografico_total_vendas_monitoradas"),
            pl.col("geografico_qtd_vendas_outra_uf").sum().alias("geografico_qtd_vendas_outra_uf"),
            pl.col("geografico_valor_total").sum().alias("geografico_valor_total"),
            pl.col("geografico_valor_outra_uf").sum().alias("geografico_valor_outra_uf"),
            pl.col("alto_custo_valor").sum().alias("alto_custo_valor"),
            pl.col("pico_valor_top3_dias").sum().alias("pico_valor_top3_dias"),
            pl.col("hhi_total_prescritores").sum().alias("hhi_total_prescritores"),
            pl.col("hhi_total_prescricoes").sum().alias("hhi_total_prescricoes"),
            pl.col("hhi_valor_total").sum().alias("hhi_valor_total"),
            pl.col("hhi_valor_top1").sum().alias("hhi_valor_top1"),
            pl.col("hhi_valor_top5").sum().alias("hhi_valor_top5"),
            pl.col("_hhi_valor_ponderado_ano").sum().alias("hhi_valor_ponderado"),
            pl.col("crms_irregulares_total_prescritores").sum().alias("crms_irregulares_total_prescritores"),
            pl.col("crms_irregulares_total_prescricoes").sum().alias("crms_irregulares_total_prescricoes"),
            pl.col("crms_irregulares_valor_total").sum().alias("crms_irregulares_valor_total"),
            pl.col("crms_irregulares_qtd_nao_localizados").sum().alias("crms_irregulares_qtd_nao_localizados"),
            pl.col("crms_irregulares_valor_nao_localizados").sum().alias("crms_irregulares_valor_nao_localizados"),
            pl.col("crms_irregulares_qtd_antes_registro").sum().alias("crms_irregulares_qtd_antes_registro"),
            pl.col("crms_irregulares_valor_antes_registro").sum().alias("crms_irregulares_valor_antes_registro"),
            pl.col("crms_irregulares_qtd").sum().alias("crms_irregulares_qtd"),
            pl.col("crms_irregulares_valor").sum().alias("crms_irregulares_valor"),
            pl.col("recorrencia_total_renovacoes_monitoradas").sum().alias("recorrencia_total_renovacoes_monitoradas"),
            pl.col("recorrencia_total_renovacoes_sistemicas").sum().alias("recorrencia_total_renovacoes_sistemicas"),
            pl.col("recorrencia_valor_total").sum().alias("recorrencia_valor_total"),
            pl.col("recorrencia_valor_sistemico").sum().alias("recorrencia_valor_sistemico"),
        ])
    )

    value_exprs = [
        _metric_ratio_expr(
            str(spec["numerator"]),
            str(spec["denominator"]),
            float(spec["factor"]),
            INDICATOR_MAPPING[key][0],
        )
        for key, spec in _INDICATOR_AGGREGATIONS.items()
    ]
    aggregated = aggregated.with_columns(value_exprs)

    perfil = perfil_df if perfil_df is not None else get_df_perfil_estabelecimento()
    perfil_required = {"id_cnpj", "cnpj", "uf", "id_regiao_saude", "id_ibge7"}
    missing_perfil = perfil_required - set(perfil.columns)
    if missing_perfil:
        raise RuntimeError(
            "perfil_estabelecimento.parquet sem colunas obrigatorias para matriz dinamica: "
            + ", ".join(sorted(missing_perfil))
        )

    enriched = aggregated.join(
        perfil.select(["id_cnpj", "cnpj", "uf", "id_regiao_saude", "id_ibge7"]).with_columns([
            pl.col("id_regiao_saude").cast(pl.Utf8),
            pl.col("uf").cast(pl.Utf8),
        ]),
        on="id_cnpj",
        how="inner",
    )
    enriched = enriched.with_columns(
        pl.len().over("id_regiao_saude").cast(pl.Int64).alias("_total_regiao_benchmark")
    )

    median_exprs = []
    for _key, (c_val, c_mr, c_mu, c_mb, _c_rr, _c_ru, _c_rb) in INDICATOR_MAPPING.items():
        median_exprs.extend([
            pl.col(c_val).median().over("id_regiao_saude").alias(c_mr),
            pl.col(c_val).median().over("uf").alias(c_mu),
            pl.col(c_val).median().alias(c_mb),
        ])
    enriched = enriched.with_columns(median_exprs)

    deviation_exprs = []
    for key, (c_val, c_mr, c_mu, _c_mb, _c_rr, _c_ru, _c_rb) in INDICATOR_MAPPING.items():
        deviation_exprs.extend([
            _deviation_expr(c_val, c_mr, f"_dev_{key}_reg"),
            _deviation_expr(c_val, c_mu, f"_dev_{key}_uf"),
        ])
    enriched = enriched.with_columns(deviation_exprs)

    mad_exprs = []
    for key in INDICATOR_MAPPING:
        mad_exprs.extend([
            pl.col(f"_dev_{key}_reg").median().over("id_regiao_saude").alias(f"_mad_{key}_reg"),
            pl.col(f"_dev_{key}_uf").median().over("uf").alias(f"_mad_{key}_uf"),
        ])
    enriched = enriched.with_columns(mad_exprs)

    risk_exprs = []
    mz_exprs = []
    modified_z_exprs = []
    flag_exprs = []
    score_percentile_exprs = []
    score_scope_exprs = []
    for key, (c_val, c_mr, c_mu, c_mb, c_rr, c_ru, c_rb) in INDICATOR_MAPPING.items():
        c_aten, c_crit = _INDICATOR_FLAGS[key]
        mz_col = f"mz_{key}"
        benchmark_value_col = f"_bench_val_{key}"
        benchmark_median_col = f"_bench_med_{key}"
        benchmark_mad_col = f"_bench_mad_{key}"
        zero_baseline_critical_col = f"_zero_baseline_crit_{key}"
        score_pct_reg_col = f"_score_pct_{key}_reg"
        score_pct_uf_col = f"_score_pct_{key}_uf"
        score_pct_col = f"_score_pct_{key}"
        risk_exprs.extend([
            _risk_ratio_expr(c_val, c_mr, c_rr),
            _risk_ratio_expr(c_val, c_mu, c_ru),
            _risk_ratio_expr(c_val, c_mb, c_rb),
        ])
        mz_exprs.extend([
            pl.col(c_val).alias(benchmark_value_col),
            (
                pl.when(pl.col("_total_regiao_benchmark") >= MIN_REGIAO_BENCHMARK)
                .then(pl.col(c_mr))
                .otherwise(pl.col(c_mu))
                .alias(benchmark_median_col)
            ),
            (
                pl.when(pl.col("_total_regiao_benchmark") >= MIN_REGIAO_BENCHMARK)
                .then(pl.col(f"_mad_{key}_reg"))
                .otherwise(pl.col(f"_mad_{key}_uf"))
                .alias(benchmark_mad_col)
            ),
        ])
        modified_z_exprs.extend([
            _modified_z_expr(benchmark_value_col, benchmark_median_col, benchmark_mad_col, mz_col),
        ])
        zero_baseline_condition = pl.col(benchmark_median_col).is_null() | (pl.col(benchmark_median_col) <= 0)

        if key == "falecidos":
            zero_baseline_attention_condition = (
                zero_baseline_condition
                & pl.col("falecidos_valor").is_not_null()
                & (pl.col("falecidos_valor") > 0)
                & (pl.col("falecidos_valor") <= FALECIDOS_VALOR_LIMITE_ATENCAO)
            )
            zero_baseline_critical_condition = (
                zero_baseline_condition
                & pl.col("falecidos_valor").is_not_null()
                & (pl.col("falecidos_valor") > FALECIDOS_VALOR_LIMITE_ATENCAO)
            )
        elif key == "volume_atipico":
            zero_baseline_attention_condition = (
                zero_baseline_condition
                & pl.col("volume_atipico_valor_aumento_atipico").is_not_null()
                & (pl.col("volume_atipico_valor_aumento_atipico") > 0)
                & (pl.col("volume_atipico_valor_aumento_atipico") < VOLUME_ATIPICO_AUMENTO_MINIMO)
            )
            zero_baseline_critical_condition = (
                zero_baseline_condition
                & pl.col("volume_atipico_valor_aumento_atipico").is_not_null()
                & (pl.col("volume_atipico_valor_aumento_atipico") >= VOLUME_ATIPICO_AUMENTO_MINIMO)
            )
        else:
            zero_baseline_attention_condition = pl.lit(False)
            zero_baseline_critical_condition = (
                (pl.lit(key in _ZERO_BASELINE_CRITICAL_INDICATORS))
                & pl.col(c_val).is_not_null()
                & (pl.col(c_val) > 0)
                & zero_baseline_condition
            )

        modified_z_exprs.append(
            zero_baseline_critical_condition.cast(pl.Int8).alias(zero_baseline_critical_col)
        )
        if key == "percentual_nao_comprovacao":
            flag_exprs.extend([
                (
                    pl.when(
                        pl.col(c_val).is_not_null()
                        & (pl.col(c_val) >= NAO_COMPROVACAO_PCT_ATENCAO)
                        & (pl.col(c_val) < NAO_COMPROVACAO_PCT_CRITICO)
                    )
                    .then(pl.lit(1))
                    .otherwise(pl.lit(0))
                    .cast(pl.Int8)
                    .alias(c_aten)
                ),
                (
                    pl.when(
                        pl.col(c_val).is_not_null()
                        & (pl.col(c_val) >= NAO_COMPROVACAO_PCT_CRITICO)
                    )
                    .then(pl.lit(1))
                    .otherwise(pl.lit(0))
                    .cast(pl.Int8)
                    .alias(c_crit)
                ),
            ])
        else:
            attention_threshold, critical_threshold = _INDICATOR_MZ_THRESHOLDS[key]
            flag_exprs.extend([
                (
                    pl.when(
                        zero_baseline_attention_condition
                        | (
                        (pl.col(zero_baseline_critical_col) == 0)
                        & pl.col(mz_col).is_not_null()
                        & (pl.col(mz_col) >= attention_threshold)
                        & (pl.col(mz_col) < critical_threshold)
                        )
                    )
                    .then(pl.lit(1))
                    .otherwise(pl.lit(0))
                    .cast(pl.Int8)
                    .alias(c_aten)
                ),
                (
                    pl.when(
                        zero_baseline_critical_condition
                        | (pl.col(mz_col).is_not_null() & (pl.col(mz_col) >= critical_threshold))
                    )
                    .then(pl.lit(1))
                    .otherwise(pl.lit(0))
                    .cast(pl.Int8)
                    .alias(c_crit)
                ),
            ])
        score_percentile_exprs.extend([
            _percent_rank_expr(c_val, ["id_regiao_saude"], score_pct_reg_col),
            _percent_rank_expr(c_val, ["uf"], score_pct_uf_col),
        ])
        score_scope_exprs.append(
            pl.when((pl.col("id_regiao_saude").is_not_null()) & (pl.col("_total_regiao_benchmark") >= MIN_REGIAO_BENCHMARK))
            .then(pl.col(score_pct_reg_col))
            .otherwise(pl.col(score_pct_uf_col))
            .alias(score_pct_col)
        )
    enriched = (
        enriched
        .with_columns(risk_exprs)
        .with_columns(mz_exprs)
        .with_columns(modified_z_exprs)
        .with_columns(flag_exprs)
        .with_columns(score_percentile_exprs)
        .with_columns(score_scope_exprs)
    )

    critical_cols = [cols[1] for cols in _INDICATOR_FLAGS.values()]
    attention_cols = [cols[0] for cols in _INDICATOR_FLAGS.values()]
    score_numerator_terms = []
    score_denominator_terms = []
    for key, (c_val, *_rest) in INDICATOR_MAPPING.items():
        weight = _INDICATOR_SCORE_WEIGHTS[key]
        active_weight = (
            pl.when(pl.col(c_val).is_not_null())
            .then(pl.lit(weight))
            .otherwise(pl.lit(0.0))
        )
        score_denominator_terms.append(active_weight)
        score_numerator_terms.append(pl.col(f"_score_pct_{key}").fill_null(0.0) * active_weight)

    return _with_classificacao_and_rankings(
        enriched.with_columns([
            pl.sum_horizontal(*(pl.col(col).fill_null(0).cast(pl.Int32) for col in critical_cols)).alias("qtd_indicadores_criticos"),
            pl.sum_horizontal(*(pl.col(col).fill_null(0).cast(pl.Int32) for col in attention_cols)).alias("qtd_indicadores_atencao"),
            pl.sum_horizontal(*score_numerator_terms).alias("_score_numerador"),
            pl.sum_horizontal(*score_denominator_terms).alias("soma_pesos_ativos"),
        ]).with_columns([
            (pl.col("qtd_indicadores_criticos") * 10 + pl.col("qtd_indicadores_atencao") * 3).cast(pl.Float64).alias("pontos_penalidade"),
            (
                pl.when(pl.col("soma_pesos_ativos") > 0)
                .then(pl.col("_score_numerador") / pl.col("soma_pesos_ativos"))
                .otherwise(pl.lit(0.0))
                .round(2)
                .alias("score_base")
            ),
        ]).with_columns(
            (pl.col("score_base") + pl.col("pontos_penalidade")).round(2).alias("score_risco_final")
        )
    )


def build_dynamic_matriz_risco(
    *,
    data_inicio: date | None = None,
    data_fim: date | None = None,
    perfil_df: pl.DataFrame | None = None,
) -> pl.DataFrame:
    if perfil_df is not None:
        return _compute_dynamic_matriz_risco(data_inicio=data_inicio, data_fim=data_fim, perfil_df=perfil_df)

    ano_inicio, ano_fim = _period_year_bounds(data_inicio, data_fim)
    cache_key = (
        get_cache_generation(),
        ano_inicio,
        ano_fim,
    )
    now = time.monotonic()
    with _DYNAMIC_CACHE_LOCK:
        cached = _DYNAMIC_CACHE.get(cache_key)
        if cached is not None and now - cached[0] <= _DYNAMIC_CACHE_TTL_SECONDS:
            return cached[1]

    df = _compute_dynamic_matriz_risco(data_inicio=data_inicio, data_fim=data_fim)
    with _DYNAMIC_CACHE_LOCK:
        if len(_DYNAMIC_CACHE) >= _DYNAMIC_CACHE_MAX_ENTRIES:
            oldest_key = min(_DYNAMIC_CACHE.items(), key=lambda item: item[1][0])[0]
            _DYNAMIC_CACHE.pop(oldest_key, None)
        _DYNAMIC_CACHE[cache_key] = (now, df)
    return df


_build_dynamic_matriz_risco = build_dynamic_matriz_risco
