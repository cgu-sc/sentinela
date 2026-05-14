from typing import List, Optional
from datetime import date
import calendar
import time
from threading import RLock
import polars as pl
from sqlalchemy.orm import Session
from sqlalchemy import text
from fastapi import HTTPException
import os
import zlib
import json
import copy
from decimal import Decimal, ROUND_HALF_UP
from data_cache import get_df, get_rede_df, get_df_matriz_risco, get_df_bench_crm_regiao, get_df_bench_crm_br, get_df_dados_farmacia, get_df_perfil_estabelecimento, get_cache_dir, get_cache_generation
from .par_teia import apply_par_teia_filter
from ...utils.text_search import apply_token_search
from ...schemas.analytics import (
    AnalyticsKPISchema,
    ResultadoSentinelaUFSchema,
    AnalyticsResponse,
    ResultadoSentinelaSchema,
    ResultadoSentinelaMunicipioSchema,
    ResultadoSentinelaCnpjSchema,
    RedeEstabelecimentoSchema,
    FatorRiscoResponseSchema,
    FatorRiscoBucketSchema,
    EvolucaoSemestreSchema,
    EvolucaoFinanceiraResponse,
    IndicadorDataSchema,
    IndicadoresResponse,
    FalecidoTransactionSchema,
    FalecidosRankingSchema,
    FalecidosSummarySchema,
    FalecidosResponse,
    TimelineEventSchema,
    MultiCnpjTimelineResponse,
    RegionalMunicipioSchema,
    RegionalFarmaciaSchema,
    RegionalResponse,
    RegionalAnimationQuarterSchema,
    RegionalAnimationResponse,
    PrescritoresResponse,
    DadosFarmaciaSchema,
    MovimentacaoRowSchema,
    MovimentacaoSummarySchema,
    MovimentacaoResponse,
    IndicadorKpiSummarySchema,
    IndicadorCnpjRowSchema,
    IndicadorMunicipioRowSchema,
    IndicadorAnaliseResponse,
    IndicadorCnpjPageResponse,
    CrmDailyProfileResponse,
    CrmHourlyProfileResponse,
    MesMensalGtinItem,
    EvolucaoMensalGtinResponse,
    GtinDetalhamentoMensalResponse,
    GtinDetalhamentoMensalSummary,
    GtinDetalhamentoMensalItem,
)

INDICATOR_MAPPING: dict[str, tuple[str, str, str, str, str, str, str]] = {
    'percentual_nao_comprovacao': ('pct_auditado',              'med_auditado_reg',             'med_auditado_uf',             'med_auditado_br',             'risco_auditado_reg',             'risco_auditado_uf',             'risco_auditado_br'),
    'falecidos':                   ('pct_falecidos',             'med_falecidos_reg',            'med_falecidos_uf',            'med_falecidos_br',            'risco_falecidos_reg',            'risco_falecidos_uf',            'risco_falecidos_br'),
    'incompatibilidade_patologica':('pct_clinico',               'med_clinico_reg',              'med_clinico_uf',              'med_clinico_br',              'risco_clinico_reg',              'risco_clinico_uf',              'risco_clinico_br'),
    'teto':                  ('pct_teto',                  'med_teto_reg',                 'med_teto_uf',                 'med_teto_br',                 'risco_teto_reg',                 'risco_teto_uf',                 'risco_teto_br'),
    'polimedicamento':       ('pct_polimedicamento',       'med_polimedicamento_reg',      'med_polimedicamento_uf',      'med_polimedicamento_br',      'risco_polimedicamento_reg',      'risco_polimedicamento_uf',      'risco_polimedicamento_br'),
    'ticket_medio':               ('val_ticket_medio',          'med_ticket_reg',               'med_ticket_uf',               'med_ticket_br',               'risco_ticket_reg',               'risco_ticket_uf',               'risco_ticket_br'),
    'receita_paciente':      ('val_receita_paciente',      'med_receita_paciente_reg',     'med_receita_paciente_uf',     'med_receita_paciente_br',     'risco_receita_paciente_reg',     'risco_receita_paciente_uf',     'risco_receita_paciente_br'),
    'per_capita':            ('val_per_capita',            'med_per_capita_reg',           'med_per_capita_uf',           'med_per_capita_br',           'risco_per_capita_reg',           'risco_per_capita_uf',           'risco_per_capita_br'),
    'alto_custo':            ('pct_alto_custo',            'med_alto_custo_reg',           'med_alto_custo_uf',           'med_alto_custo_br',           'risco_alto_custo_reg',           'risco_alto_custo_uf',           'risco_alto_custo_br'),
    'vendas_rapidas':        ('pct_vendas_rapidas',        'med_vendas_rapidas_reg',       'med_vendas_rapidas_uf',       'med_vendas_rapidas_br',       'risco_vendas_rapidas_reg',       'risco_vendas_rapidas_uf',       'risco_vendas_rapidas_br'),
    'volume_atipico':        ('val_volume_atipico',        'med_volume_atipico_reg',       'med_volume_atipico_uf',       'med_volume_atipico_br',       'risco_volume_atipico_reg',       'risco_volume_atipico_uf',       'risco_volume_atipico_br'),
    'recorrencia_sistemica': ('pct_recorrencia_sistemica', 'med_recorrencia_sistemica_reg','med_recorrencia_sistemica_uf','med_recorrencia_sistemica_br','risco_recorrencia_sistemica_reg','risco_recorrencia_sistemica_uf','risco_recorrencia_sistemica_br'),
    'dias_pico':                  ('pct_pico',                  'med_pico_reg',                 'med_pico_uf',                 'med_pico_br',                 'risco_pico_reg',                 'risco_pico_uf',                 'risco_pico_br'),
    'dispersao_geografica':       ('pct_geografico',            'med_geografico_reg',           'med_geografico_uf',           'med_geografico_br',           'risco_geografico_reg',           'risco_geografico_uf',           'risco_geografico_br'),
    'compra_unica':      ('pct_compra_unica',          'med_compra_unica_reg',         'med_compra_unica_uf',         'med_compra_unica_br',         'risco_compra_unica_reg',         'risco_compra_unica_uf',         'risco_compra_unica_br'),
    'hhi_crm':               ('val_hhi_crm',               'med_hhi_crm_reg',              'med_hhi_crm_uf',              'med_hhi_crm_br',              'risco_crm_reg',                  'risco_crm_uf',                  'risco_crm_br'),
    'exclusividade_crm':     ('pct_exclusividade_crm',     'med_exclusividade_crm_reg',    'med_exclusividade_crm_uf',    'med_exclusividade_crm_br',    'risco_exclusividade_crm_reg',    'risco_exclusividade_crm_uf',    'risco_exclusividade_crm_br'),
    'crms_irregulares':      ('pct_crms_irregulares',      'med_crms_irregulares_reg',     'med_crms_irregulares_uf',     'med_crms_irregulares_br',     'risco_crms_irregulares_reg',     'risco_crms_irregulares_uf',     'risco_crms_irregulares_br'),
}

# Mapeamento indicador → (col_flag_atencao, col_flag_critico) na fp.matriz_risco_consolidada.
# Flags calculadas via Modified Z-Score (MAD) no SQL — fonte de verdade para Status na UI.
_INDICATOR_FLAGS: dict[str, tuple[str, str]] = {
    # 1. Auditoria Financeira
    'percentual_nao_comprovacao':   ('flag_percentual_sem_comprovacao_atencao', 'flag_percentual_sem_comprovacao_critico'),
    # 2. Elegibilidade & Clínica
    'falecidos':                    ('flag_falecidos_atencao',                  'flag_falecidos_critico'),
    'incompatibilidade_patologica': ('flag_incompatibilidade_patologica_atencao', 'flag_incompatibilidade_patologica_critico'),
    # 3. Padrões de Quantidade
    'teto':                         ('flag_estouro_teto_atencao',               'flag_estouro_teto_critico'),
    'polimedicamento':               ('flag_polimedicamento_atencao',            'flag_polimedicamento_critico'),
    # 4. Padrões Financeiros
    'ticket_medio':                  ('flag_ticket_medio_atencao',               'flag_ticket_medio_critico'),
    'receita_paciente':              ('flag_receita_paciente_atencao',           'flag_receita_paciente_critico'),
    'per_capita':                    ('flag_per_capita_atencao',                 'flag_per_capita_critico'),
    'alto_custo':                    ('flag_alto_custo_atencao',                 'flag_alto_custo_critico'),
    # 5. Automação & Geografia
    'vendas_rapidas':                ('flag_vendas_rapidas_atencao',             'flag_vendas_rapidas_critico'),
    'volume_atipico':                ('flag_volume_atipico_atencao',             'flag_volume_atipico_critico'),
    'recorrencia_sistemica':         ('flag_recorrencia_sistemica_atencao',      'flag_recorrencia_sistemica_critico'),
    'dias_pico':                     ('flag_concentracao_pico_atencao',          'flag_concentracao_pico_critico'),
    'dispersao_geografica':          ('flag_dispersao_geografica_atencao',       'flag_dispersao_geografica_critico'),
    'compra_unica':                  ('flag_compra_unica_atencao',               'flag_compra_unica_critico'),
    # 6. Integridade Médica
    'hhi_crm':                       ('flag_hhi_crm_atencao',                   'flag_hhi_crm_critico'),
    'exclusividade_crm':             ('flag_exclusividade_crm_atencao',          'flag_exclusividade_crm_critico'),
    'crms_irregulares':              ('flag_crms_irregulares_atencao',           'flag_crms_irregulares_critico'),
}

def _optional_float(value: object) -> float | None:
    if value is None or isinstance(value, bool):
        return None
    if isinstance(value, (int, float, Decimal)):
        return float(value)
    if isinstance(value, str):
        try:
            return float(value)
        except ValueError:
            return None
    return None

def _apply_estabelecimento_search(df: pl.DataFrame, estabelecimento: str | None) -> pl.DataFrame:
    return apply_token_search(df, estabelecimento, ("cnpj", "razao_social", "nome_fantasia"))


_INDICADOR_CACHE_TTL_SECONDS = 300
_INDICADOR_CACHE_MAX_ENTRIES = 64
_INDICADOR_CACHE_LOCK = RLock()

_INDICADOR_SCOPE_BASE_CACHE: dict[
    tuple[object, ...],
    tuple[float, tuple[pl.DataFrame, pl.DataFrame]],
] = {}

_INDICADOR_DATASET_CACHE: dict[tuple[object, ...], tuple[float, tuple[
    pl.DataFrame,
    pl.DataFrame,
    pl.DataFrame,
    str,
    str,
    str | None,
    str,
]]] = {}


def _normalize_cache_text(value: object) -> str | None:
    if value is None:
        return None
    normalized = str(value).strip()
    if not normalized or normalized == "Todos":
        return None
    return normalized


def _normalize_cache_int(value: object) -> int | None:
    if value is None:
        return None
    return int(value)


def _normalize_cache_float(value: object) -> float | None:
    if value is None:
        return None
    return float(value)


def _normalize_cache_cnpj(value: object) -> str | None:
    normalized = _normalize_cache_text(value)
    if normalized is None:
        return None
    return normalized.replace(".", "").replace("/", "").replace("-", "")


_INDICADOR_SCOPE_FILTER_FIELDS = (
    ("uf", _normalize_cache_text),
    ("regiao_id", _normalize_cache_int),
    ("id_ibge7", _normalize_cache_int),
    ("situacao_rf", _normalize_cache_text),
    ("conexao_ms", _normalize_cache_text),
    ("porte_empresa", _normalize_cache_text),
    ("grande_rede", _normalize_cache_text),
    ("cnpj_raiz", _normalize_cache_cnpj),
    ("estabelecimento", _normalize_cache_text),
    ("unidade_pf", _normalize_cache_text),
    ("par_teia", _normalize_cache_text),
    ("perc_min", _normalize_cache_float),
    ("perc_max", _normalize_cache_float),
    ("val_min", _normalize_cache_float),
)


def _make_indicador_scope_base_cache_key(
    *,
    filters: dict[str, object],
) -> tuple[object, ...]:
    return (
        get_cache_generation(),
        *(
            normalizer(filters.get(field_name))
            for field_name, normalizer in _INDICADOR_SCOPE_FILTER_FIELDS
        ),
    )


def _make_indicador_dataset_cache_key(
    *,
    indicador: str,
    filters: dict[str, object],
) -> tuple[object, ...]:
    return (
        get_cache_generation(),
        indicador,
        *(
            normalizer(filters.get(field_name))
            for field_name, normalizer in _INDICADOR_SCOPE_FILTER_FIELDS
        ),
    )


def _prune_indicador_cache(cache: dict[tuple[object, ...], tuple[float, object]], now: float, generation: int) -> None:
    expired_keys = [
        key
        for key, (created_at, _result) in cache.items()
        if key[0] != generation or now - created_at > _INDICADOR_CACHE_TTL_SECONDS
    ]
    for key in expired_keys:
        del cache[key]

    if len(cache) <= _INDICADOR_CACHE_MAX_ENTRIES:
        return

    keys_by_age = sorted(
        cache,
        key=lambda key: cache[key][0],
    )
    overflow = len(cache) - _INDICADOR_CACHE_MAX_ENTRIES
    for key in keys_by_age[:overflow]:
        del cache[key]


def get_indicadores(cnpj: str) -> IndicadoresResponse:
    """Retorna os 18 indicadores de risco para um CNPJ a partir da matriz_risco_consolidada."""
    try:
        df = get_df_matriz_risco()
        df = df.rename({c: c.lower() for c in df.columns})
        rows = df.filter(pl.col("cnpj") == cnpj)
        if rows.is_empty():
            return IndicadoresResponse(cnpj=cnpj, indicadores={})
        row = rows.row(0, named=True)

        indicadores = {
            key: IndicadorDataSchema(
                valor=_optional_float(row.get(c_val)),
                med_reg=_optional_float(row.get(c_mr)),
                med_uf=_optional_float(row.get(c_mu)),
                med_br=_optional_float(row.get(c_mb)),
                risco_reg=_optional_float(row.get(c_rr)),
                risco_uf=_optional_float(row.get(c_ru)),
                risco_br=_optional_float(row.get(c_rb)),
            )
            for key, (c_val, c_mr, c_mu, c_mb, c_rr, c_ru, c_rb) in INDICATOR_MAPPING.items()
        }
        return IndicadoresResponse(cnpj=cnpj, indicadores=indicadores)
    except Exception:
        print(f"[ ANALYTICS ] {cnpj} ● INDICADORES ● ❌ INDISPONÍVEL (Sem Cache e Banco Offline)")
        return IndicadoresResponse(cnpj=cnpj, indicadores={})

def _build_indicador_scope_base(
    uf: str | None = None,
    situacao_rf: str | None = None,
    conexao_ms: str | None = None,
    porte_empresa: str | None = None,
    grande_rede: str | None = None,
    cnpj_raiz: str | None = None,
    estabelecimento: str | None = None,
    unidade_pf: str | None = None,
    perc_min: float | None = None,
    perc_max: float | None = None,
    val_min: float | None = None,
    regiao_id: int | None = None,
    id_ibge7: int | None = None,
    par_teia: str | None = None,
) -> tuple[pl.DataFrame, pl.DataFrame]:
    df_mov = get_df()
    perfil_df = get_df_perfil_estabelecimento()
    scope_base = df_mov.group_by("id_cnpj").agg([
        pl.col("total_vendas").sum().alias("total_vendas"),
        pl.col("total_sem_comprovacao").sum().alias("total_sem_comprovacao"),
    ]).join(perfil_df, on="id_cnpj", how="inner").with_columns([
        pl.when(pl.col("total_vendas") > 0)
          .then((pl.col("total_sem_comprovacao") / pl.col("total_vendas") * 100).round(2))
          .otherwise(pl.lit(None))
          .alias("perc_val_sem_comp")
    ])

    mask = pl.lit(True)
    if uf and uf != 'Todos':
        mask = mask & (pl.col("uf") == uf)
    if regiao_id is not None:
        mask = mask & (pl.col("id_regiao_saude") == str(regiao_id))
    if id_ibge7 is not None:
        mask = mask & (pl.col("id_ibge7") == id_ibge7)
    if situacao_rf and situacao_rf != 'Todos':
        mask = mask & (pl.col("situacao_rf") == situacao_rf)
    if conexao_ms and conexao_ms != 'Todos':
        mask = mask & (pl.col("is_conexao_ativa") == (conexao_ms == 'Ativa'))
    if porte_empresa and porte_empresa != 'Todos':
        mask = mask & (pl.col("porte_empresa") == porte_empresa)
    if grande_rede and grande_rede != 'Todos':
        mask = mask & (pl.col("is_grande_rede") == (grande_rede == 'Sim'))
    if unidade_pf and unidade_pf != 'Todos':
        mask = mask & (pl.col("unidade_pf") == unidade_pf)
    if cnpj_raiz:
        cnpj_raiz_clean = cnpj_raiz.replace(".", "").replace("/", "").replace("-", "")
        if len(cnpj_raiz_clean) == 14:
            mask = mask & (pl.col("cnpj") == cnpj_raiz_clean)
        elif len(cnpj_raiz_clean) >= 8:
            mask = mask & (pl.col("cnpj").str.slice(0, 8) == cnpj_raiz_clean[:8])

    scope_base = _apply_estabelecimento_search(scope_base.filter(mask), estabelecimento)
    scope_base = apply_par_teia_filter(scope_base, par_teia)
    if perc_min is not None:
        scope_base = scope_base.filter(pl.col("perc_val_sem_comp") >= perc_min)
    if perc_max is not None:
        scope_base = scope_base.filter(pl.col("perc_val_sem_comp") <= perc_max)
    if val_min is not None:
        scope_base = scope_base.filter(pl.col("total_sem_comprovacao") >= val_min)

    return scope_base, perfil_df


def _build_indicador_dataset(
    indicador: str,
    scope_base: pl.DataFrame,
    perfil_df: pl.DataFrame,
) -> tuple[pl.DataFrame, pl.DataFrame, pl.DataFrame, str, str, str | None, str]:
    if indicador not in INDICATOR_MAPPING:
        raise HTTPException(
            status_code=400,
            detail=f"Indicador '{indicador}' inválido. Valores aceitos: {sorted(INDICATOR_MAPPING.keys())}"
        )

    c_val, c_mr, _c_mu, _c_mb, c_rr, _c_ru, _c_rb = INDICATOR_MAPPING[indicador]
    c_aten, c_crit = _INDICATOR_FLAGS[indicador]
    score_col = "score_risco_final"

    if scope_base.is_empty():
        return scope_base, perfil_df, pl.DataFrame(), c_val, c_mr, None, score_col

    df_risco = get_df_matriz_risco()
    df_risco = df_risco.rename({c: c.lower() for c in df_risco.columns})
    risco_cols = ["cnpj", c_val, c_mr, c_rr, c_aten, c_crit, score_col]
    risco_cols_available = [c for c in risco_cols if c in df_risco.columns]
    indicador_dataset = scope_base.join(df_risco.select(risco_cols_available), on="cnpj", how="inner")
    if indicador_dataset.is_empty():
        return indicador_dataset, perfil_df, df_risco, c_val, c_mr, None, score_col

    rr_col = c_rr if c_rr in indicador_dataset.columns else None
    has_flags = c_crit in indicador_dataset.columns and c_aten in indicador_dataset.columns
    if has_flags:
        indicador_dataset = indicador_dataset.with_columns([
            pl.when(pl.col(c_val).is_null())
              .then(pl.lit("SEM DADOS"))
              .when(pl.col(c_crit).cast(pl.Int32) == 1)
              .then(pl.lit("CRÍTICO"))
              .when(pl.col(c_aten).cast(pl.Int32) == 1)
              .then(pl.lit("ATENÇÃO"))
              .otherwise(pl.lit("NORMAL"))
              .alias("status")
        ])
    else:
        indicador_dataset = indicador_dataset.with_columns(pl.lit("SEM DADOS").alias("status"))

    return indicador_dataset, perfil_df, df_risco, c_val, c_mr, rr_col, score_col


def _build_indicador_dataset_cached(
    indicador: str,
    uf: str | None = None,
    situacao_rf: str | None = None,
    conexao_ms: str | None = None,
    porte_empresa: str | None = None,
    grande_rede: str | None = None,
    cnpj_raiz: str | None = None,
    estabelecimento: str | None = None,
    unidade_pf: str | None = None,
    perc_min: float | None = None,
    perc_max: float | None = None,
    val_min: float | None = None,
    regiao_id: int | None = None,
    id_ibge7: int | None = None,
    par_teia: str | None = None,
) -> tuple[pl.DataFrame, pl.DataFrame, pl.DataFrame, str, str, str | None, str]:
    raw_values = locals()
    filters = {
        field_name: raw_values[field_name]
        for field_name, _normalizer in _INDICADOR_SCOPE_FILTER_FIELDS
    }
    scope_cache_key = _make_indicador_scope_base_cache_key(filters=filters)
    dataset_cache_key = _make_indicador_dataset_cache_key(
        indicador=indicador,
        filters=filters,
    )
    generation = dataset_cache_key[0]
    now = time.monotonic()

    with _INDICADOR_CACHE_LOCK:
        _prune_indicador_cache(_INDICADOR_SCOPE_BASE_CACHE, now, generation)
        _prune_indicador_cache(_INDICADOR_DATASET_CACHE, now, generation)

        cached_dataset = _INDICADOR_DATASET_CACHE.get(dataset_cache_key)
        if cached_dataset is not None:
            return cached_dataset[1]

        cached_scope = _INDICADOR_SCOPE_BASE_CACHE.get(scope_cache_key)

    if cached_scope is not None:
        scope_base, perfil_df = cached_scope[1]
    else:
        scope_base, perfil_df = _build_indicador_scope_base(**filters)
        with _INDICADOR_CACHE_LOCK:
            now = time.monotonic()
            _prune_indicador_cache(_INDICADOR_SCOPE_BASE_CACHE, now, generation)
            _INDICADOR_SCOPE_BASE_CACHE[scope_cache_key] = (now, (scope_base, perfil_df))

    result = _build_indicador_dataset(indicador, scope_base, perfil_df)

    with _INDICADOR_CACHE_LOCK:
        now = time.monotonic()
        _prune_indicador_cache(_INDICADOR_DATASET_CACHE, now, generation)
        _INDICADOR_DATASET_CACHE[dataset_cache_key] = (now, result)

    return result


def _build_indicador_cnpj_rows(
    df: pl.DataFrame,
    c_val: str,
    c_mr: str,
    rr_col: str | None,
    score_col: str,
) -> list[IndicadorCnpjRowSchema]:
    rows: list[IndicadorCnpjRowSchema] = []
    for row in df.iter_rows(named=True):
        rows.append(IndicadorCnpjRowSchema(
            cnpj=str(row["cnpj"]),
            razao_social=row.get("razao_social"),
            municipio=str(row["no_municipio"]).title() if row.get("no_municipio") else None,
            uf=row.get("uf"),
            id_ibge7=int(row["id_ibge7"]) if row.get("id_ibge7") is not None else None,
            valor=_optional_float(row.get(c_val)),
            med_reg=_optional_float(row.get(c_mr)),
            risco_reg=_optional_float(row.get(rr_col)) if rr_col else None,
            status=row.get("status", "SEM DADOS"),
            is_grande_rede=bool(row.get("is_grande_rede", False)),
            situacao_rf=row.get("situacao_rf"),
            is_conexao_ativa=bool(row.get("is_conexao_ativa", False)),
            score_risco_final=_optional_float(row.get(score_col)) if score_col in df.columns else None,
            val_sem_comp=_optional_float(row.get("total_sem_comprovacao")),
            perc_val_sem_comp=_optional_float(row.get("perc_val_sem_comp")),
        ))
    return rows


def _build_status_kpis(df: pl.DataFrame) -> IndicadorKpiSummarySchema:
    if df.is_empty():
        return IndicadorKpiSummarySchema()
    status_counts = df["status"].value_counts().to_dicts()
    counts = {r["status"]: r["count"] for r in status_counts}
    total_com_dados = counts.get("CRÍTICO", 0) + counts.get("ATENÇÃO", 0) + counts.get("NORMAL", 0)
    pct_acima_limiar = (
        (counts.get("CRÍTICO", 0) + counts.get("ATENÇÃO", 0)) / total_com_dados * 100
        if total_com_dados > 0 else None
    )
    return IndicadorKpiSummarySchema(
        total_critico=counts.get("CRÍTICO", 0),
        total_atencao=counts.get("ATENÇÃO", 0),
        total_normal=counts.get("NORMAL", 0),
        total_sem_dados=counts.get("SEM DADOS", 0),
        pct_acima_limiar=round(pct_acima_limiar, 2) if pct_acima_limiar is not None else None,
    )


def _normalizar_sort_order(sort_order: str | int | None) -> tuple[str, bool]:
    raw = str(sort_order or "desc").lower()
    descending = raw in {"desc", "descending", "-1"}
    return ("desc" if descending else "asc"), descending


def get_indicadores_analise(
    indicador: str,
    uf: str | None = None,
    regiao_saude: str | None = None,
    municipio: str | None = None,
    situacao_rf: str | None = None,
    conexao_ms: str | None = None,
    porte_empresa: str | None = None,
    grande_rede: str | None = None,
    cnpj_raiz: str | None = None,
    estabelecimento: str | None = None,
    unidade_pf: str | None = None,
    perc_min: float | None = None,
    perc_max: float | None = None,
    val_min: float | None = None,
    regiao_id: int | None = None,
    id_ibge7: int | None = None,
    par_teia: str | None = None,
) -> IndicadorAnaliseResponse:
    """
    Análise cruzada de um indicador de risco: retorna KPIs, mapa municipal
    filtrados pelo escopo geográfico.

    Operação 100% em memória (Polars) sobre df_matriz_risco + df_movimentacao.
    Não usa filtros de período — a matriz_risco é um snapshot consolidado.
    Mas aceita filtros de percentual e valor mínimo acumulado.

    Args:
        indicador: Chave do indicador (ex: 'auditado', 'teto'). Deve existir em INDICATOR_MAPPING.
        uf: Sigla da UF ou None.
        regiao_saude: Nome da Região de Saúde ou None.
        municipio: Nome do município ou None.
        situacao_rf: Situação na Receita Federal ou None.
        conexao_ms: 'Ativa' | 'Inativa' | None.
        porte_empresa: Porte CNPJ ou None.
        grande_rede: 'Sim' | 'Não' | None.
        cnpj_raiz: 8 ou 14 dígitos ou None.
        unidade_pf: Nome da Unidade PF ou None.
        perc_min: Limiar mínimo de não comprovação (%)
        perc_max: Limiar máximo de não comprovação (%)
        val_min: Valor bruto mínimo sem comprovação (R$)

    Returns:
        IndicadorAnaliseResponse com kpis e municipios.

    Raises:
        HTTPException 400 se a chave do indicador for inválida.
    """
    if indicador not in INDICATOR_MAPPING:
        raise HTTPException(
            status_code=400,
            detail=f"Indicador '{indicador}' inválido. Valores aceitos: {sorted(INDICATOR_MAPPING.keys())}"
        )

    try:
        df_joined, perfil_df, df_risco, c_val, _c_mr, rr_col, _score_col = _build_indicador_dataset_cached(
            indicador,
            uf=uf,
            situacao_rf=situacao_rf,
            conexao_ms=conexao_ms,
            porte_empresa=porte_empresa,
            grande_rede=grande_rede,
            cnpj_raiz=cnpj_raiz,
            estabelecimento=estabelecimento,
            unidade_pf=unidade_pf,
            perc_min=perc_min,
            perc_max=perc_max,
            val_min=val_min,
            regiao_id=regiao_id,
            id_ibge7=id_ibge7,
            par_teia=par_teia,
        )

        if df_joined.is_empty():
            empty_kpis = IndicadorKpiSummarySchema()
            return IndicadorAnaliseResponse(indicador=indicador, kpis=empty_kpis, municipios=[])

        if rr_col is None:
            raise RuntimeError(f"Coluna de risco regional obrigatoria ausente para indicador '{indicador}'.")

        # ── 6. Agregação por município para o mapa ──
        mun_agg = (
            df_joined
            .group_by(["no_municipio", "uf", "id_ibge7"])
            .agg([
                pl.len().alias("total_cnpjs"),
                (pl.col("status") == "CRÍTICO").sum().alias("total_critico"),
            ])
            .with_columns([
                (
                    pl.col("total_critico").cast(pl.Float64) /
                    pl.when(pl.col("total_cnpjs") > 0)
                    .then(pl.col("total_cnpjs").cast(pl.Float64))
                    .otherwise(pl.lit(1.0)) * 100
                ).round(2).alias("pct_critico")
            ])
            .sort("pct_critico", descending=True)
        )

        municipios_list: list[IndicadorMunicipioRowSchema] = []
        for row in mun_agg.iter_rows(named=True):
            municipios_list.append(IndicadorMunicipioRowSchema(
                municipio=str(row["no_municipio"]).title() if row.get("no_municipio") else "",
                uf=row.get("uf"),
                id_ibge7=int(row["id_ibge7"]) if row.get("id_ibge7") is not None else None,
                total_cnpjs=int(row["total_cnpjs"] or 0),
                total_critico=int(row["total_critico"] or 0),
                pct_critico=_optional_float(row.get("pct_critico")) or 0.0,
            ))

        # ── 7. KPIs de resumo com Contexto Regional de Benchmarking ──
        status_counts = df_joined["status"].value_counts().to_dicts()
        counts = {r["status"]: r["count"] for r in status_counts}

        total_com_dados = counts.get("CRÍTICO", 0) + counts.get("ATENÇÃO", 0) + counts.get("NORMAL", 0)
        pct_acima_limiar = (
            (counts.get("CRÍTICO", 0) + counts.get("ATENÇÃO", 0)) / total_com_dados * 100
            if total_com_dados > 0 else None
        )

        # Identifica a Região de Saúde de referência (mesmo se filtro for municipal)
        context_regiao_id = str(regiao_id) if regiao_id is not None else None
        if context_regiao_id is None and id_ibge7 is not None:
            sample = df_joined.select("id_regiao_saude").unique().limit(1)
            if not sample.is_empty():
                context_regiao_id = str(sample.item(0, 0))

        # Cálculo de Mediana/MAD sobre o CONTEXTO (UF + opcionalmente Região de Saúde)
        context_mask = pl.lit(True)
        if uf and uf != 'Todos':
            context_mask = context_mask & (pl.col("uf") == uf)
        if context_regiao_id is not None:
            context_mask = context_mask & (pl.col("id_regiao_saude") == context_regiao_id)

        # Buscamos a mediana e MAD do indicador para o contexto regional completo
        mediana_reg = None
        mad_reg = None
        # df_geo original contém todos os CNPJs com geo; filtramos os do contexto
        df_context_geo = perfil_df.select(["id_cnpj", "cnpj", "uf", "id_regiao_saude"]).filter(context_mask)
        
        df_context = df_context_geo.join(df_risco.select(["cnpj", c_val, rr_col]), on="cnpj", how="inner")
        
        if not df_context.is_empty():
            s_valores = df_context.select(c_val).drop_nulls().to_series().sort()
            s_riscos = df_context.select(rr_col).drop_nulls().to_series().sort()
            
            if not s_valores.is_empty():
                mediana_reg = _optional_float(s_valores.median()) or 0.0
            
            if not s_riscos.is_empty():
                # Para o MAD/Z-Score, usamos os scores (ratios) onde a mediana teórica é 1.0
                m_r = _optional_float(s_riscos.median()) or 1.0
                mad_reg = _optional_float((s_riscos - m_r).abs().median()) or 0.0001

        kpis = IndicadorKpiSummarySchema(
            total_critico=counts.get("CRÍTICO", 0),
            total_atencao=counts.get("ATENÇÃO", 0),
            total_normal=counts.get("NORMAL", 0),
            total_sem_dados=counts.get("SEM DADOS", 0),
            mediana_reg=mediana_reg,
            mad_reg=mad_reg,
            pct_acima_limiar=round(pct_acima_limiar, 2) if pct_acima_limiar is not None else None,
            limiar_atencao=None,
            limiar_critico=None
        )

        return IndicadorAnaliseResponse(
            indicador=indicador,
            kpis=kpis,
            municipios=municipios_list,
        )

    except HTTPException:
        raise
    except Exception as e:
        import traceback
        print(f"❌ ERRO EM get_indicadores_analise (indicador={indicador}): {e}")
        print(traceback.format_exc())
        raise HTTPException(status_code=500, detail="Erro interno ao processar análise de indicadores.")

def get_indicadores_analise_cnpjs(
    indicador: str,
    uf: str | None = None,
    regiao_saude: str | None = None,
    municipio: str | None = None,
    situacao_rf: str | None = None,
    conexao_ms: str | None = None,
    porte_empresa: str | None = None,
    grande_rede: str | None = None,
    cnpj_raiz: str | None = None,
    estabelecimento: str | None = None,
    unidade_pf: str | None = None,
    perc_min: float | None = None,
    perc_max: float | None = None,
    val_min: float | None = None,
    regiao_id: int | None = None,
    id_ibge7: int | None = None,
    par_teia: str | None = None,
    page: int = 1,
    page_size: int = 20,
    sort_field: str = "risco_reg",
    sort_order: str | int | None = "desc",
) -> IndicadorCnpjPageResponse:
    try:
        df_joined, _perfil_df, _df_risco, c_val, c_mr, rr_col, score_col = _build_indicador_dataset_cached(
            indicador,
            uf=uf,
            situacao_rf=situacao_rf,
            conexao_ms=conexao_ms,
            porte_empresa=porte_empresa,
            grande_rede=grande_rede,
            cnpj_raiz=cnpj_raiz,
            estabelecimento=estabelecimento,
            unidade_pf=unidade_pf,
            perc_min=perc_min,
            perc_max=perc_max,
            val_min=val_min,
            regiao_id=regiao_id,
            id_ibge7=id_ibge7,
            par_teia=par_teia,
        )

        normalized_order, descending = _normalizar_sort_order(sort_order)
        page = max(1, int(page or 1))
        page_size = min(200, max(1, int(page_size or 20)))

        if df_joined.is_empty():
            return IndicadorCnpjPageResponse(
                indicador=indicador,
                items=[],
                kpis=IndicadorKpiSummarySchema(),
                total=0,
                page=page,
                page_size=page_size,
                sort_field=sort_field,
                sort_order=normalized_order,
            )

        sort_columns = {
            "cnpj": "cnpj",
            "razao_social": "razao_social",
            "municipio": "no_municipio",
            "uf": "uf",
            "valor": c_val,
            "med_reg": c_mr,
            "risco_reg": rr_col,
            "status": "status",
            "is_conexao_ativa": "is_conexao_ativa",
            "situacao_rf": "situacao_rf",
            "score_risco_final": score_col,
            "val_sem_comp": "total_sem_comprovacao",
            "perc_val_sem_comp": "perc_val_sem_comp",
        }
        sort_col = sort_columns.get(sort_field) or rr_col or "cnpj"
        if sort_col not in df_joined.columns:
            raise HTTPException(status_code=400, detail=f"Campo de ordenacao invalido: {sort_field}")

        total = df_joined.height
        offset = (page - 1) * page_size
        df_page = (
            df_joined
            .sort(sort_col, descending=descending, nulls_last=True)
            .slice(offset, page_size)
        )

        return IndicadorCnpjPageResponse(
            indicador=indicador,
            items=_build_indicador_cnpj_rows(df_page, c_val, c_mr, rr_col, score_col),
            kpis=_build_status_kpis(df_joined),
            total=total,
            page=page,
            page_size=page_size,
            sort_field=sort_field,
            sort_order=normalized_order,
        )

    except HTTPException:
        raise
    except Exception as e:
        import traceback
        print(f"ERRO EM get_indicadores_analise_cnpjs (indicador={indicador}): {e}")
        print(traceback.format_exc())
        raise HTTPException(status_code=500, detail="Erro interno ao paginar CNPJs do indicador.")
