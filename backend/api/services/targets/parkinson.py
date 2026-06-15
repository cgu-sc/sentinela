from dataclasses import dataclass
from datetime import date
from typing import Iterable

import polars as pl
from fastapi import HTTPException

from data_cache import (
    get_df_dados_ibge_demografia,
    get_df_perfil_estabelecimento,
    scan_analise_gtin_inconsistencia_clinica,
)
from ..analytics.indicator_rules import (
    DIABETES_PREVALENCIA_MENOR_20,
    IBGE_ANO_CENSO_DEMOGRAFIA,
    PARKINSON_PREVALENCIA_50_MAIS,
)
from ...schemas.targets import (
    ClinicalTargetResponse,
    ClinicalTargetRowSchema,
    TargetKpiSchema,
    TargetMapRowSchema,
)


@dataclass(frozen=True)
class ClinicalTargetConfig:
    key: str
    label: str
    patologia: str
    regra_clinica: str


_TARGETS = {
    "parkinson_menor_50": ClinicalTargetConfig(
        key="parkinson_menor_50",
        label="Parkinson em menores de 50 anos",
        patologia="DOENCA DE PARKINSON",
        regra_clinica="IDADE_MENOR_50",
    ),
    "diabetes_menor_20": ClinicalTargetConfig(
        key="diabetes_menor_20",
        label="Diabetes em menores de 20 anos",
        patologia="DIABETES",
        regra_clinica="IDADE_MENOR_20",
    ),
    "hipertensao_menor_20": ClinicalTargetConfig(
        key="hipertensao_menor_20",
        label="Hipertensao em menores de 20 anos",
        patologia="HIPERTENSÃO",
        regra_clinica="IDADE_MENOR_20",
    ),
}

_CLINICO_REQUIRED = {
    "id_cnpj",
    "id_ibge7",
    "patologia",
    "regra_clinica",
    "ano_base",
    "qtd_cpfs_incompativeis",
    "qtd_autorizacoes_incompativeis",
    "valor_incompativel_pago",
}

_CLINICO_REGIONAL_EXPECTED_REQUIRED = {"cpfs_incompativeis_esperados_regiao"}

_DEMOGRAFIA_REQUIRED = {
    "id_ibge7",
    "ano_censo",
    "idade_min",
    "nu_populacao",
    "sexo",
}

_PERFIL_REQUIRED = {
    "id_cnpj",
    "cnpj",
    "razao_social",
    "uf",
    "id_ibge7",
    "id_regiao_saude",
    "no_municipio",
    "is_matriz",
    "is_conexao_ativa",
}

_SORT_FIELDS = {
    "razao_social",
    "is_conexao_ativa",
    "municipio",
    "uf",
    "ano_base",
    "casos_esperados",
    "casos_observados",
    "casos_observados_municipio",
    "razao_observado_esperado",
    "valor_incompativel",
    "autorizacoes",
    "participacao_municipio",
}


def _require_columns(columns: Iterable[str], required: set[str], source: str) -> None:
    missing = sorted(required.difference(set(columns)))
    if missing:
        raise HTTPException(
            status_code=500,
            detail=f"Contrato de cache invalido em {source}. Colunas ausentes: {', '.join(missing)}.",
        )


def _year_start(data_inicio: date | None) -> int | None:
    return data_inicio.year if data_inicio else None


def _year_end(data_fim: date | None) -> int | None:
    return data_fim.year if data_fim else None


def _empty_response(
    *,
    page: int,
    page_size: int,
    sort_field: str,
    sort_order: str,
    mapa: list[TargetMapRowSchema] | None = None,
) -> ClinicalTargetResponse:
    return ClinicalTargetResponse(
        kpis=[
            TargetKpiSchema(key="farmacias", label="Farmacias", value=0),
            TargetKpiSchema(key="valor_incompativel", label="Valor incompativel", value=0.0),
            TargetKpiSchema(key="cpfs_envolvidos", label="CPFs envolvidos", value=0),
            TargetKpiSchema(key="municipios", label="Municipios", value=0),
            TargetKpiSchema(key="ufs", label="UFs", value=0),
        ],
        mapa=mapa or [],
        items=[],
        total=0,
        page=page,
        page_size=page_size,
        sort_field=sort_field,
        sort_order=sort_order,
    )


def _build_profile_filter(
    perfil: pl.DataFrame,
    uf: str | None,
    regiao_id: int | None,
    id_ibge7: int | None,
) -> pl.DataFrame:
    profile = perfil.select(
        [
            pl.col("id_cnpj").cast(pl.Int32),
            pl.col("cnpj").cast(pl.Utf8),
            pl.col("razao_social").cast(pl.Utf8),
            pl.col("is_matriz").cast(pl.Boolean),
            pl.col("is_conexao_ativa").cast(pl.Boolean),
            pl.col("uf").cast(pl.Utf8).str.to_uppercase(),
            pl.col("id_ibge7").cast(pl.Int32),
            pl.col("id_regiao_saude").cast(pl.Int32),
            pl.col("no_municipio").cast(pl.Utf8).alias("municipio"),
        ]
    )

    if uf:
        profile = profile.filter(pl.col("uf") == uf.upper())
    if regiao_id is not None:
        profile = profile.filter(pl.col("id_regiao_saude") == int(regiao_id))
    if id_ibge7 is not None:
        profile = profile.filter(pl.col("id_ibge7") == int(id_ibge7))

    return profile


def _sort_and_page(
    df: pl.DataFrame,
    page: int,
    page_size: int,
    sort_field: str,
    sort_order: str,
) -> pl.DataFrame:
    if sort_field not in _SORT_FIELDS:
        raise HTTPException(status_code=422, detail=f"Campo de ordenacao invalido para alvo clinico: {sort_field}.")
    if sort_order not in {"asc", "desc"}:
        raise HTTPException(status_code=422, detail="sort_order deve ser asc ou desc.")

    return (
        df.sort(sort_field, descending=sort_order == "desc", nulls_last=True)
        .slice((page - 1) * page_size, page_size)
    )


def _get_target_demografia(
    cnpj_base: pl.DataFrame,
    target_label: str,
) -> tuple[pl.DataFrame, pl.DataFrame]:
    demografia = get_df_dados_ibge_demografia()
    _require_columns(demografia.columns, _DEMOGRAFIA_REQUIRED, "dados_ibge_demografia")

    municipios_alvo = cnpj_base.select("id_ibge7").unique()
    demografia_municipios = (
        demografia
        .with_columns(
            [
                pl.col("id_ibge7").cast(pl.Int32, strict=False),
                pl.col("ano_censo").cast(pl.Int16, strict=False),
                pl.col("idade_min").cast(pl.Int16, strict=False),
                pl.col("nu_populacao").cast(pl.Int64, strict=False),
                pl.col("sexo").cast(pl.Utf8).str.to_uppercase(),
            ]
        )
        .filter(pl.col("ano_censo") == IBGE_ANO_CENSO_DEMOGRAFIA)
        .join(municipios_alvo, on="id_ibge7", how="inner")
    )

    if demografia_municipios.filter(
        pl.col("id_ibge7").is_null()
        | pl.col("idade_min").is_null()
        | pl.col("sexo").is_null()
    ).height > 0:
        raise HTTPException(
            status_code=500,
            detail=f"Demografia IBGE possui municipio, idade ou sexo nulo para o alvo {target_label}.",
        )

    invalid_sex = demografia_municipios.filter(~pl.col("sexo").is_in(["F", "M"]))
    if invalid_sex.height > 0:
        raise HTTPException(
            status_code=500,
            detail=f"Demografia IBGE possui sexo invalido para o alvo {target_label}.",
        )

    invalid_grid = (
        demografia_municipios
        .group_by(["id_ibge7", "idade_min"])
        .agg(
            [
                pl.len().alias("qtd_linhas"),
                pl.col("sexo").n_unique().alias("qtd_sexos"),
            ]
        )
        .filter((pl.col("qtd_linhas") != 2) | (pl.col("qtd_sexos") != 2))
    )
    if invalid_grid.height > 0:
        ids = invalid_grid.get_column("id_ibge7").unique().sort().to_list()
        raise HTTPException(
            status_code=500,
            detail=f"Grade demografica IBGE incompleta para municipios do alvo {target_label}: id_ibge7={ids[:10]}.",
        )

    # Na grade completa idade/sexo do IBGE, celulas nulas representam ausencia
    # de habitantes naquela combinacao, nao uma faixa demografica ausente.
    demografia_municipios = demografia_municipios.with_columns(
        pl.col("nu_populacao").fill_null(0)
    )
    if demografia_municipios.filter(pl.col("nu_populacao") < 0).height > 0:
        raise HTTPException(
            status_code=500,
            detail=f"Demografia IBGE possui populacao negativa para o alvo {target_label}.",
        )

    return municipios_alvo, demografia_municipios


def _validate_demographic_coverage(
    municipios_alvo: pl.DataFrame,
    municipal_data: pl.DataFrame,
    value_column: str,
    target_label: str,
) -> None:
    missing_demografia = municipios_alvo.join(
        municipal_data.select("id_ibge7"),
        on="id_ibge7",
        how="anti",
    )
    if missing_demografia.height > 0:
        ids = missing_demografia.get_column("id_ibge7").sort().to_list()
        raise HTTPException(
            status_code=500,
            detail=(
                f"Demografia IBGE {IBGE_ANO_CENSO_DEMOGRAFIA} ausente para municipios "
                f"do alvo {target_label}: id_ibge7={ids[:10]}."
            ),
        )

    invalid_demografia = municipal_data.filter(pl.col(value_column) <= 0)
    if invalid_demografia.height > 0:
        ids = invalid_demografia.get_column("id_ibge7").sort().to_list()
        raise HTTPException(
            status_code=500,
            detail=f"Demografia IBGE invalida para municipios do alvo {target_label}: id_ibge7={ids[:10]}.",
        )


def _add_parkinson_municipal_expected(cnpj_base: pl.DataFrame) -> pl.DataFrame:
    municipios_alvo, demografia_municipios = _get_target_demografia(
        cnpj_base,
        "Parkinson",
    )
    esperados_municipio = (
        demografia_municipios
        .filter(pl.col("idade_min") >= 50)
        .group_by("id_ibge7")
        .agg(pl.col("nu_populacao").sum().alias("populacao_50_mais"))
        .with_columns(
            (
                pl.col("populacao_50_mais").cast(pl.Float64)
                * pl.lit(PARKINSON_PREVALENCIA_50_MAIS)
            ).alias("casos_esperados")
        )
    )

    _validate_demographic_coverage(
        municipios_alvo,
        esperados_municipio,
        "casos_esperados",
        "Parkinson",
    )

    return cnpj_base.join(
        esperados_municipio.select(["id_ibge7", "casos_esperados"]),
        on="id_ibge7",
        how="left",
    )


def _add_diabetes_municipal_expected(cnpj_base: pl.DataFrame) -> pl.DataFrame:
    municipios_alvo, demografia_municipios = _get_target_demografia(
        cnpj_base,
        "Diabetes em menores de 20 anos",
    )
    populacao_municipio = (
        demografia_municipios
        .filter(pl.col("idade_min") < 20)
        .group_by("id_ibge7")
        .agg(pl.col("nu_populacao").sum().alias("populacao_referencia"))
        .with_columns(
            (
                pl.col("populacao_referencia").cast(pl.Float64)
                * pl.lit(DIABETES_PREVALENCIA_MENOR_20)
            ).alias("casos_esperados")
        )
    )
    _validate_demographic_coverage(
        municipios_alvo,
        populacao_municipio,
        "casos_esperados",
        "Diabetes em menores de 20 anos",
    )

    return cnpj_base.join(
        populacao_municipio,
        on="id_ibge7",
        how="left",
    )


def _get_clinical_target(
    config: ClinicalTargetConfig,
    *,
    data_inicio: date | None = None,
    data_fim: date | None = None,
    uf: str | None = None,
    regiao_id: int | None = None,
    id_ibge7: int | None = None,
    page: int = 1,
    page_size: int = 20,
    sort_field: str = "valor_incompativel",
    sort_order: str = "desc",
) -> ClinicalTargetResponse:
    if page < 1:
        raise HTTPException(status_code=422, detail="page deve ser maior ou igual a 1.")
    if page_size < 1 or page_size > 200:
        raise HTTPException(status_code=422, detail="page_size deve estar entre 1 e 200.")
    if data_inicio and data_fim and data_inicio > data_fim:
        raise HTTPException(status_code=422, detail="data_inicio nao pode ser maior que data_fim.")

    clinico_lf = scan_analise_gtin_inconsistencia_clinica()
    clinico_required = set(_CLINICO_REQUIRED)
    if config.key not in {"parkinson_menor_50", "diabetes_menor_20"}:
        clinico_required.update(_CLINICO_REGIONAL_EXPECTED_REQUIRED)
    _require_columns(
        clinico_lf.collect_schema().names(),
        clinico_required,
        "analise_gtin_inconsistencia_clinica",
    )

    ano_inicio = _year_start(data_inicio)
    ano_fim = _year_end(data_fim)

    filtered_lf = (
        clinico_lf
        .with_columns(
            [
                pl.col("patologia").cast(pl.Utf8).str.to_uppercase().alias("_patologia_norm"),
                pl.col("regra_clinica").cast(pl.Utf8).str.to_uppercase().alias("_regra_norm"),
                pl.col("id_cnpj").cast(pl.Int32, strict=False).alias("id_cnpj"),
                pl.col("id_ibge7").cast(pl.Int32, strict=False).alias("id_ibge7"),
                pl.col("ano_base").cast(pl.Int16, strict=False).alias("ano_base"),
            ]
        )
        .filter(
            (pl.col("_patologia_norm") == config.patologia)
            & (pl.col("_regra_norm") == config.regra_clinica)
        )
    )
    if ano_inicio is not None:
        filtered_lf = filtered_lf.filter(pl.col("ano_base").cast(pl.Int16) >= ano_inicio)
    if ano_fim is not None:
        filtered_lf = filtered_lf.filter(pl.col("ano_base").cast(pl.Int16) <= ano_fim)

    aggregations = [
        pl.col("qtd_cpfs_incompativeis").sum().alias("casos_observados"),
        pl.col("qtd_autorizacoes_incompativeis").sum().alias("autorizacoes"),
        pl.col("valor_incompativel_pago").sum().alias("valor_incompativel"),
    ]
    if config.key not in {"parkinson_menor_50", "diabetes_menor_20"}:
        aggregations.append(
            pl.col("cpfs_incompativeis_esperados_regiao").sum().alias("casos_esperados")
        )

    cnpj_base = (
        filtered_lf
        .group_by(["id_cnpj", "id_ibge7", "ano_base"])
        .agg(aggregations)
        .filter((pl.col("casos_observados") > 0) | (pl.col("valor_incompativel") > 0))
        .collect()
    )

    if cnpj_base.filter(pl.col("id_cnpj").is_null() | pl.col("id_ibge7").is_null() | pl.col("ano_base").is_null()).height > 0:
        raise HTTPException(status_code=500, detail=f"Alvo {config.label} possui id_cnpj/id_ibge7/ano_base invalido no cache clinico.")

    if cnpj_base.is_empty():
        return _empty_response(page=page, page_size=page_size, sort_field=sort_field, sort_order=sort_order)

    if config.key == "parkinson_menor_50":
        cnpj_base = _add_parkinson_municipal_expected(cnpj_base)
    elif config.key == "diabetes_menor_20":
        cnpj_base = _add_diabetes_municipal_expected(cnpj_base)

    if cnpj_base.filter(pl.col("casos_esperados").is_null()).height > 0:
        raise HTTPException(status_code=500, detail=f"Alvo {config.label} possui casos_esperados nulo no cache clinico.")

    perfil = get_df_perfil_estabelecimento()
    _require_columns(perfil.columns, _PERFIL_REQUIRED, "perfil_estabelecimento")

    full_profile = _build_profile_filter(perfil, None, None, None)
    missing_profile = cnpj_base.join(full_profile.select("id_cnpj"), on="id_cnpj", how="anti")
    if missing_profile.height > 0:
        ids = missing_profile.select("id_cnpj").head(10).to_series().to_list()
        raise HTTPException(status_code=500, detail=f"Perfil ausente para alvo {config.label}: id_cnpj={ids}.")

    invalid_profile = (
        cnpj_base
        .join(full_profile.select(["id_cnpj", "is_matriz", "is_conexao_ativa"]), on="id_cnpj", how="inner")
        .filter(pl.col("is_matriz").is_null() | pl.col("is_conexao_ativa").is_null())
    )
    if invalid_profile.height > 0:
        ids = invalid_profile.select("id_cnpj").head(10).to_series().to_list()
        raise HTTPException(
            status_code=500,
            detail=f"Perfil sem is_matriz/is_conexao_ativa para alvo {config.label}: id_cnpj={ids}.",
        )

    map_profile = _build_profile_filter(perfil, uf, regiao_id, None)
    map_rows = cnpj_base.join(map_profile, on=["id_cnpj", "id_ibge7"], how="inner")
    map_total_valor = float(map_rows.select(pl.sum("valor_incompativel")).item() or 0.0)
    mapa_df = (
        map_rows
        .group_by(["id_ibge7", "municipio", "uf"])
        .agg(
            [
                pl.n_unique("id_cnpj").alias("total_farmacias"),
                pl.col("valor_incompativel").sum().alias("valor_incompativel"),
                pl.col("casos_observados").sum().alias("casos_observados"),
            ]
        )
        .with_columns(
            pl.when(pl.lit(map_total_valor) > 0)
            .then(pl.col("valor_incompativel") / pl.lit(map_total_valor))
            .otherwise(None)
            .alias("participacao_uf")
        )
        .sort("valor_incompativel", descending=True)
    )

    profile = _build_profile_filter(perfil, uf, regiao_id, id_ibge7)
    rows = cnpj_base.join(profile, on=["id_cnpj", "id_ibge7"], how="inner")

    if rows.is_empty():
        return _empty_response(
            page=page,
            page_size=page_size,
            sort_field=sort_field,
            sort_order=sort_order,
            mapa=[TargetMapRowSchema(**item) for item in mapa_df.to_dicts()],
        )

    municipal_totals = (
        rows
        .group_by(["id_ibge7", "ano_base"])
        .agg(
            [
                pl.col("casos_observados").sum().alias("casos_observados_municipio"),
                pl.col("valor_incompativel").sum().alias("valor_incompativel_municipio"),
            ]
        )
    )

    metric_columns = [
        pl.col("ano_base").cast(pl.Int16),
        pl.col("casos_observados").cast(pl.Int64),
        pl.col("casos_observados_municipio").cast(pl.Int64),
        pl.col("valor_incompativel").cast(pl.Float64),
        pl.col("autorizacoes").cast(pl.Int64),
        pl.when(pl.col("valor_incompativel_municipio") > 0)
        .then(pl.col("valor_incompativel") / pl.col("valor_incompativel_municipio"))
        .otherwise(None)
        .alias("participacao_municipio"),
    ]
    if config.key == "diabetes_menor_20":
        metric_columns.extend(
            [
                pl.col("casos_esperados").cast(pl.Float64),
                pl.when(pl.col("casos_esperados") > 0)
                .then(pl.col("casos_observados") / pl.col("casos_esperados"))
                .otherwise(None)
                .alias("razao_observado_esperado"),
                pl.col("populacao_referencia").cast(pl.Int64),
                pl.when(pl.col("populacao_referencia") > 0)
                .then(pl.col("casos_observados") / pl.col("populacao_referencia"))
                .otherwise(None)
                .alias("percentual_observado_populacao"),
            ]
        )
    else:
        metric_columns.extend(
            [
                pl.col("casos_esperados").cast(pl.Float64),
                pl.when(pl.col("casos_esperados") > 0)
                .then(pl.col("casos_observados") / pl.col("casos_esperados"))
                .otherwise(None)
                .alias("razao_observado_esperado"),
                pl.lit(None).cast(pl.Int64).alias("populacao_referencia"),
                pl.lit(None).cast(pl.Float64).alias("percentual_observado_populacao"),
            ]
        )

    rows = rows.join(
        municipal_totals,
        on=["id_ibge7", "ano_base"],
        how="left",
    ).with_columns(metric_columns)

    total_records = rows.height
    total_valor = float(rows.select(pl.sum("valor_incompativel")).item() or 0.0)
    total_cpfs = int(rows.select(pl.sum("casos_observados")).item() or 0)
    total_farmacias = int(rows.select(pl.n_unique("id_cnpj")).item() or 0)
    page_df = _sort_and_page(rows, page, page_size, sort_field, sort_order)

    return ClinicalTargetResponse(
        kpis=[
            TargetKpiSchema(key="farmacias", label="Farmacias", value=total_farmacias),
            TargetKpiSchema(key="valor_incompativel", label="Valor incompativel", value=round(total_valor, 2)),
            TargetKpiSchema(key="cpfs_envolvidos", label="CPFs envolvidos", value=total_cpfs),
            TargetKpiSchema(key="municipios", label="Municipios", value=rows.select(pl.n_unique("id_ibge7")).item()),
            TargetKpiSchema(key="ufs", label="UFs", value=rows.select(pl.n_unique("uf")).item()),
        ],
        mapa=[TargetMapRowSchema(**item) for item in mapa_df.to_dicts()],
        items=[ClinicalTargetRowSchema(**item) for item in page_df.to_dicts()],
        total=total_records,
        page=page,
        page_size=page_size,
        sort_field=sort_field,
        sort_order=sort_order,
    )


def get_parkinson_menor_50(**kwargs) -> ClinicalTargetResponse:
    return _get_clinical_target(_TARGETS["parkinson_menor_50"], **kwargs)


def get_diabetes_menor_20(**kwargs) -> ClinicalTargetResponse:
    return _get_clinical_target(_TARGETS["diabetes_menor_20"], **kwargs)


def get_hipertensao_menor_20(**kwargs) -> ClinicalTargetResponse:
    return _get_clinical_target(_TARGETS["hipertensao_menor_20"], **kwargs)
