from dataclasses import dataclass
from datetime import date
from typing import Iterable

import polars as pl
from fastapi import HTTPException

from data_cache import (
    get_df_perfil_estabelecimento,
    scan_analise_gtin_inconsistencia_clinica,
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
    "osteoporose_homens": ClinicalTargetConfig(
        key="osteoporose_homens",
        label="Osteoporose em homens",
        patologia="OSTEOPOROSE",
        regra_clinica="SEXO_MASCULINO",
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
    "cpfs_incompativeis_esperados_regiao",
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
    _require_columns(clinico_lf.collect_schema().names(), _CLINICO_REQUIRED, "analise_gtin_inconsistencia_clinica")

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

    cnpj_base = (
        filtered_lf
        .group_by(["id_cnpj", "id_ibge7", "ano_base"])
        .agg(
            [
                pl.col("qtd_cpfs_incompativeis").sum().alias("casos_observados"),
                pl.col("cpfs_incompativeis_esperados_regiao").sum().alias("casos_esperados"),
                pl.col("qtd_autorizacoes_incompativeis").sum().alias("autorizacoes"),
                pl.col("valor_incompativel_pago").sum().alias("valor_incompativel"),
            ]
        )
        .filter((pl.col("casos_observados") > 0) | (pl.col("valor_incompativel") > 0))
        .collect()
    )

    if cnpj_base.filter(pl.col("id_cnpj").is_null() | pl.col("id_ibge7").is_null() | pl.col("ano_base").is_null()).height > 0:
        raise HTTPException(status_code=500, detail=f"Alvo {config.label} possui id_cnpj/id_ibge7/ano_base invalido no cache clinico.")
    if cnpj_base.filter(pl.col("casos_esperados").is_null()).height > 0:
        raise HTTPException(status_code=500, detail=f"Alvo {config.label} possui casos_esperados nulo no cache clinico.")

    if cnpj_base.is_empty():
        return _empty_response(page=page, page_size=page_size, sort_field=sort_field, sort_order=sort_order)

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

    rows = (
        rows
        .join(municipal_totals, on=["id_ibge7", "ano_base"], how="left")
        .with_columns(
            [
                pl.col("ano_base").cast(pl.Int16),
                pl.col("casos_esperados").cast(pl.Float64),
                pl.col("casos_observados").cast(pl.Int64),
                pl.col("casos_observados_municipio").cast(pl.Int64),
                pl.col("valor_incompativel").cast(pl.Float64),
                pl.col("autorizacoes").cast(pl.Int64),
                pl.when(pl.col("casos_esperados") > 0)
                .then(pl.col("casos_observados") / pl.col("casos_esperados"))
                .otherwise(None)
                .alias("razao_observado_esperado"),
                pl.when(pl.col("valor_incompativel_municipio") > 0)
                .then(pl.col("valor_incompativel") / pl.col("valor_incompativel_municipio"))
                .otherwise(None)
                .alias("participacao_municipio"),
            ]
        )
    )

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


def get_osteoporose_homens(**kwargs) -> ClinicalTargetResponse:
    return _get_clinical_target(_TARGETS["osteoporose_homens"], **kwargs)
