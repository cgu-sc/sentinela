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


INDICATOR_MAPPING: dict[str, tuple[str, str, str, str, str, str, str]] = {
    "percentual_nao_comprovacao": ("pct_auditado", "med_auditado_reg", "med_auditado_uf", "med_auditado_br", "risco_auditado_reg", "risco_auditado_uf", "risco_auditado_br"),
    "falecidos": ("pct_falecidos", "med_falecidos_reg", "med_falecidos_uf", "med_falecidos_br", "risco_falecidos_reg", "risco_falecidos_uf", "risco_falecidos_br"),
    "incompatibilidade_patologica": ("pct_clinico", "med_clinico_reg", "med_clinico_uf", "med_clinico_br", "risco_clinico_reg", "risco_clinico_uf", "risco_clinico_br"),
    "teto": ("pct_teto", "med_teto_reg", "med_teto_uf", "med_teto_br", "risco_teto_reg", "risco_teto_uf", "risco_teto_br"),
    "polimedicamento": ("pct_polimedicamento", "med_polimedicamento_reg", "med_polimedicamento_uf", "med_polimedicamento_br", "risco_polimedicamento_reg", "risco_polimedicamento_uf", "risco_polimedicamento_br"),
    "ticket_medio": ("val_ticket_medio", "med_ticket_reg", "med_ticket_uf", "med_ticket_br", "risco_ticket_reg", "risco_ticket_uf", "risco_ticket_br"),
    "receita_paciente": ("val_receita_paciente", "med_receita_paciente_reg", "med_receita_paciente_uf", "med_receita_paciente_br", "risco_receita_paciente_reg", "risco_receita_paciente_uf", "risco_receita_paciente_br"),
    "per_capita": ("val_per_capita", "med_per_capita_reg", "med_per_capita_uf", "med_per_capita_br", "risco_per_capita_reg", "risco_per_capita_uf", "risco_per_capita_br"),
    "alto_custo": ("pct_alto_custo", "med_alto_custo_reg", "med_alto_custo_uf", "med_alto_custo_br", "risco_alto_custo_reg", "risco_alto_custo_uf", "risco_alto_custo_br"),
    "vendas_rapidas": ("pct_vendas_rapidas", "med_vendas_rapidas_reg", "med_vendas_rapidas_uf", "med_vendas_rapidas_br", "risco_vendas_rapidas_reg", "risco_vendas_rapidas_uf", "risco_vendas_rapidas_br"),
    "volume_atipico": ("val_volume_atipico", "med_volume_atipico_reg", "med_volume_atipico_uf", "med_volume_atipico_br", "risco_volume_atipico_reg", "risco_volume_atipico_uf", "risco_volume_atipico_br"),
    "recorrencia_sistemica": ("pct_recorrencia_sistemica", "med_recorrencia_sistemica_reg", "med_recorrencia_sistemica_uf", "med_recorrencia_sistemica_br", "risco_recorrencia_sistemica_reg", "risco_recorrencia_sistemica_uf", "risco_recorrencia_sistemica_br"),
    "dias_pico": ("pct_pico", "med_pico_reg", "med_pico_uf", "med_pico_br", "risco_pico_reg", "risco_pico_uf", "risco_pico_br"),
    "dispersao_geografica": ("pct_geografico", "med_geografico_reg", "med_geografico_uf", "med_geografico_br", "risco_geografico_reg", "risco_geografico_uf", "risco_geografico_br"),
    "hhi_crm": ("val_hhi_crm", "med_hhi_crm_reg", "med_hhi_crm_uf", "med_hhi_crm_br", "risco_crm_reg", "risco_crm_uf", "risco_crm_br"),
    "crms_irregulares": ("pct_crms_irregulares", "med_crms_irregulares_reg", "med_crms_irregulares_uf", "med_crms_irregulares_br", "risco_crms_irregulares_reg", "risco_crms_irregulares_uf", "risco_crms_irregulares_br"),
}

_INDICATOR_FLAGS: dict[str, tuple[str, str]] = {
    "percentual_nao_comprovacao": ("flag_percentual_sem_comprovacao_atencao", "flag_percentual_sem_comprovacao_critico"),
    "falecidos": ("flag_falecidos_atencao", "flag_falecidos_critico"),
    "incompatibilidade_patologica": ("flag_incompatibilidade_patologica_atencao", "flag_incompatibilidade_patologica_critico"),
    "teto": ("flag_estouro_teto_atencao", "flag_estouro_teto_critico"),
    "polimedicamento": ("flag_polimedicamento_atencao", "flag_polimedicamento_critico"),
    "ticket_medio": ("flag_ticket_medio_atencao", "flag_ticket_medio_critico"),
    "receita_paciente": ("flag_receita_paciente_atencao", "flag_receita_paciente_critico"),
    "per_capita": ("flag_per_capita_atencao", "flag_per_capita_critico"),
    "alto_custo": ("flag_alto_custo_atencao", "flag_alto_custo_critico"),
    "vendas_rapidas": ("flag_vendas_rapidas_atencao", "flag_vendas_rapidas_critico"),
    "volume_atipico": ("flag_volume_atipico_atencao", "flag_volume_atipico_critico"),
    "recorrencia_sistemica": ("flag_recorrencia_sistemica_atencao", "flag_recorrencia_sistemica_critico"),
    "dias_pico": ("flag_concentracao_pico_atencao", "flag_concentracao_pico_critico"),
    "dispersao_geografica": ("flag_dispersao_geografica_atencao", "flag_dispersao_geografica_critico"),
    "hhi_crm": ("flag_hhi_crm_atencao", "flag_hhi_crm_critico"),
    "crms_irregulares": ("flag_crms_irregulares_atencao", "flag_crms_irregulares_critico"),
}

RISCO_REG_ATENCAO = 3.0
RISCO_REG_CRITICO = 5.0

_INDICATOR_AGGREGATIONS: dict[str, dict[str, object]] = {
    "percentual_nao_comprovacao": {"numerator": "auditado_valor_sem_comprovacao", "denominator": "auditado_valor_total", "factor": 100.0},
    "falecidos": {"numerator": "falecidos_valor", "denominator": "falecidos_valor_total", "factor": 100.0},
    "incompatibilidade_patologica": {"numerator": "clinico_valor_suspeito", "denominator": "clinico_valor_monitorado", "factor": 100.0},
    "teto": {"numerator": "teto_valor", "denominator": "teto_valor_total", "factor": 100.0},
    "polimedicamento": {"numerator": "polimedicamento_valor", "denominator": "polimedicamento_valor_total", "factor": 100.0},
    "ticket_medio": {"numerator": "ticket_valor_total", "denominator": "ticket_total_autorizacoes", "factor": 1.0},
    "receita_paciente": {"numerator": "receita_paciente_valor_total", "denominator": "receita_paciente_denominador", "factor": 1.0},
    "per_capita": {"numerator": "per_capita_valor_total", "denominator": "per_capita_denominador", "factor": 1.0},
    "alto_custo": {"numerator": "alto_custo_valor", "denominator": "alto_custo_valor_total", "factor": 100.0},
    "vendas_rapidas": {"numerator": "vendas_rapidas_valor", "denominator": "vendas_rapidas_valor_total", "factor": 100.0},
    "volume_atipico": {"numerator": "volume_atipico_soma_excesso_crescimento_pct", "denominator": "volume_atipico_total_semestres_comparaveis", "factor": 1.0},
    "recorrencia_sistemica": {"numerator": "recorrencia_valor_sistemico", "denominator": "recorrencia_valor_total", "factor": 100.0},
    "dias_pico": {"numerator": "pico_valor_top3_dias", "denominator": "pico_valor_total", "factor": 100.0},
    "dispersao_geografica": {"numerator": "geografico_valor_outra_uf", "denominator": "geografico_valor_total", "factor": 100.0},
    "hhi_crm": {"numerator": "hhi_valor_ponderado", "denominator": "hhi_valor_total", "factor": 1.0},
    "crms_irregulares": {"numerator": "crms_irregulares_valor", "denominator": "crms_irregulares_valor_total", "factor": 100.0},
}

_MATRIX_COMPONENT_COLUMNS = {
    "id_cnpj",
    "ano_base",
    "periodo_min",
    "periodo_max",
    "auditado_valor_total",
    "auditado_valor_sem_comprovacao",
    "auditado_total_caixas",
    "auditado_total_caixas_sem_comprovacao",
    "auditado_total_autorizacoes",
    "falecidos_total_autorizacoes",
    "falecidos_qtd_autorizacoes",
    "falecidos_valor_total",
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
    "polimedicamento_valor_total",
    "polimedicamento_valor",
    "ticket_valor_total",
    "ticket_total_autorizacoes",
    "receita_paciente_valor_total",
    "receita_paciente_total_pacientes_distintos",
    "receita_paciente_total_meses_ativos",
    "per_capita_valor_total",
    "per_capita_total_meses_ativos",
    "per_capita_populacao_municipio",
    "per_capita_denominador",
    "vendas_rapidas_total_intervalos",
    "vendas_rapidas_total",
    "vendas_rapidas_valor_total",
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
    "alto_custo_valor_total",
    "alto_custo_valor",
    "pico_valor_total",
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
    denominator = (
        pl.when(pl.col(median_col).is_not_null() & (pl.col(median_col) > 0))
        .then(pl.col(median_col))
        .otherwise(pl.lit(0.0001))
    )
    return (
        pl.when(pl.col(value_col).is_null() | pl.col(median_col).is_null())
        .then(pl.lit(None, dtype=pl.Float64))
        .otherwise(pl.col(value_col) / denominator)
        .alias(alias)
    )


def _rank_expr(scope_cols: list[str] | None, alias: str) -> pl.Expr:
    valid_score = pl.col("score_risco_final").is_not_null()
    rank = pl.col("score_risco_final").rank(method="ordinal", descending=True)
    if scope_cols:
        rank = rank.over(scope_cols)
    return pl.when(valid_score).then(rank).otherwise(pl.lit(None, dtype=pl.UInt32)).cast(pl.Int64).alias(alias)


def _total_expr(scope_cols: list[str] | None, alias: str) -> pl.Expr:
    total = pl.col("score_risco_final").is_not_null().sum()
    if scope_cols:
        total = total.over(scope_cols)
    return total.cast(pl.Int64).alias(alias)


def _with_classificacao_and_rankings(df: pl.DataFrame) -> pl.DataFrame:
    return (
        df.with_columns([
            pl.when(pl.col("score_risco_final").is_null())
            .then(pl.lit(None, dtype=pl.Utf8))
            .when(pl.col("score_risco_final") >= RISCO_REG_CRITICO)
            .then(pl.lit("CRÍTICO"))
            .when(pl.col("score_risco_final") >= RISCO_REG_ATENCAO)
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
            pl.col("periodo_min").min().alias("periodo_min"),
            pl.col("periodo_max").max().alias("periodo_max"),
            pl.col("auditado_valor_total").sum().alias("auditado_valor_total"),
            pl.col("auditado_valor_sem_comprovacao").sum().alias("auditado_valor_sem_comprovacao"),
            pl.col("auditado_total_caixas").sum().alias("auditado_total_caixas"),
            pl.col("auditado_total_caixas_sem_comprovacao").sum().alias("auditado_total_caixas_sem_comprovacao"),
            pl.col("auditado_total_autorizacoes").sum().alias("auditado_total_autorizacoes"),
            pl.col("falecidos_total_autorizacoes").sum().alias("falecidos_total_autorizacoes"),
            pl.col("falecidos_qtd_autorizacoes").sum().alias("falecidos_qtd_autorizacoes"),
            pl.col("falecidos_valor_total").sum().alias("falecidos_valor_total"),
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
            pl.col("polimedicamento_valor_total").sum().alias("polimedicamento_valor_total"),
            pl.col("polimedicamento_valor").sum().alias("polimedicamento_valor"),
            pl.col("ticket_valor_total").sum().alias("ticket_valor_total"),
            pl.col("ticket_total_autorizacoes").sum().alias("ticket_total_autorizacoes"),
            pl.col("receita_paciente_valor_total").sum().alias("receita_paciente_valor_total"),
            pl.col("receita_paciente_total_pacientes_distintos").sum().alias("receita_paciente_total_pacientes_distintos"),
            pl.col("receita_paciente_total_meses_ativos").sum().alias("receita_paciente_total_meses_ativos"),
            pl.col("_receita_paciente_denominador_ano").sum().alias("receita_paciente_denominador"),
            pl.col("per_capita_valor_total").sum().alias("per_capita_valor_total"),
            pl.col("per_capita_total_meses_ativos").sum().alias("per_capita_total_meses_ativos"),
            pl.col("per_capita_populacao_municipio").max().alias("per_capita_populacao_municipio"),
            pl.col("per_capita_denominador").sum().alias("per_capita_denominador"),
            pl.col("vendas_rapidas_total_intervalos").sum().alias("vendas_rapidas_total_intervalos"),
            pl.col("vendas_rapidas_total").sum().alias("vendas_rapidas_total"),
            pl.col("vendas_rapidas_valor_total").sum().alias("vendas_rapidas_valor_total"),
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
            pl.col("alto_custo_valor_total").sum().alias("alto_custo_valor_total"),
            pl.col("alto_custo_valor").sum().alias("alto_custo_valor"),
            pl.col("pico_valor_total").sum().alias("pico_valor_total"),
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

    median_exprs = []
    for _key, (c_val, c_mr, c_mu, c_mb, _c_rr, _c_ru, _c_rb) in INDICATOR_MAPPING.items():
        median_exprs.extend([
            pl.col(c_val).median().over("id_regiao_saude").alias(c_mr),
            pl.col(c_val).median().over("uf").alias(c_mu),
            pl.col(c_val).median().alias(c_mb),
        ])
    enriched = enriched.with_columns(median_exprs)

    risk_exprs = []
    flag_exprs = []
    for key, (c_val, c_mr, c_mu, c_mb, c_rr, c_ru, c_rb) in INDICATOR_MAPPING.items():
        c_aten, c_crit = _INDICATOR_FLAGS[key]
        risk_exprs.extend([
            _risk_ratio_expr(c_val, c_mr, c_rr),
            _risk_ratio_expr(c_val, c_mu, c_ru),
            _risk_ratio_expr(c_val, c_mb, c_rb),
        ])
        flag_exprs.extend([
            (
                pl.when(pl.col(c_rr).is_not_null() & (pl.col(c_rr) >= RISCO_REG_ATENCAO))
                .then(pl.lit(1))
                .otherwise(pl.lit(0))
                .cast(pl.Int8)
                .alias(c_aten)
            ),
            (
                pl.when(pl.col(c_rr).is_not_null() & (pl.col(c_rr) >= RISCO_REG_CRITICO))
                .then(pl.lit(1))
                .otherwise(pl.lit(0))
                .cast(pl.Int8)
                .alias(c_crit)
            ),
        ])
    enriched = enriched.with_columns(risk_exprs).with_columns(flag_exprs)

    risk_reg_cols = [cols[4] for cols in INDICATOR_MAPPING.values()]
    return _with_classificacao_and_rankings(
        enriched.with_columns(
            pl.max_horizontal(*(pl.col(col) for col in risk_reg_cols)).alias("score_risco_final")
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

    cache_key = (
        get_cache_generation(),
        data_inicio.isoformat() if data_inicio else None,
        data_fim.isoformat() if data_fim else None,
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

