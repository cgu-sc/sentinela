from datetime import date

from fastapi import APIRouter, Query

from ..schemas.targets import ClinicalTargetResponse
from ..services.targets import (
    get_diabetes_menor_20,
    get_hipertensao_menor_20,
    get_osteoporose_homens,
    get_parkinson_menor_50,
)

router = APIRouter()


@router.get("/parkinson-menor-50", response_model=ClinicalTargetResponse)
def get_parkinson_menor_50_target(
    data_inicio: date | None = Query(None),
    data_fim: date | None = Query(None),
    uf: str | None = Query(None, min_length=2, max_length=2),
    regiao_id: int | None = Query(None),
    id_ibge7: int | None = Query(None),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=200),
    sort_field: str = Query("valor_incompativel"),
    sort_order: str = Query("desc", pattern="^(asc|desc)$"),
) -> ClinicalTargetResponse:
    return get_parkinson_menor_50(
        data_inicio=data_inicio,
        data_fim=data_fim,
        uf=uf,
        regiao_id=regiao_id,
        id_ibge7=id_ibge7,
        page=page,
        page_size=page_size,
        sort_field=sort_field,
        sort_order=sort_order,
    )


@router.get("/diabetes-menor-20", response_model=ClinicalTargetResponse)
def get_diabetes_menor_20_target(
    data_inicio: date | None = Query(None),
    data_fim: date | None = Query(None),
    uf: str | None = Query(None, min_length=2, max_length=2),
    regiao_id: int | None = Query(None),
    id_ibge7: int | None = Query(None),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=200),
    sort_field: str = Query("valor_incompativel"),
    sort_order: str = Query("desc", pattern="^(asc|desc)$"),
) -> ClinicalTargetResponse:
    return get_diabetes_menor_20(
        data_inicio=data_inicio,
        data_fim=data_fim,
        uf=uf,
        regiao_id=regiao_id,
        id_ibge7=id_ibge7,
        page=page,
        page_size=page_size,
        sort_field=sort_field,
        sort_order=sort_order,
    )


@router.get("/hipertensao-menor-20", response_model=ClinicalTargetResponse)
def get_hipertensao_menor_20_target(
    data_inicio: date | None = Query(None),
    data_fim: date | None = Query(None),
    uf: str | None = Query(None, min_length=2, max_length=2),
    regiao_id: int | None = Query(None),
    id_ibge7: int | None = Query(None),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=200),
    sort_field: str = Query("valor_incompativel"),
    sort_order: str = Query("desc", pattern="^(asc|desc)$"),
) -> ClinicalTargetResponse:
    return get_hipertensao_menor_20(
        data_inicio=data_inicio,
        data_fim=data_fim,
        uf=uf,
        regiao_id=regiao_id,
        id_ibge7=id_ibge7,
        page=page,
        page_size=page_size,
        sort_field=sort_field,
        sort_order=sort_order,
    )


@router.get("/osteoporose-homens", response_model=ClinicalTargetResponse)
def get_osteoporose_homens_target(
    data_inicio: date | None = Query(None),
    data_fim: date | None = Query(None),
    uf: str | None = Query(None, min_length=2, max_length=2),
    regiao_id: int | None = Query(None),
    id_ibge7: int | None = Query(None),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=200),
    sort_field: str = Query("valor_incompativel"),
    sort_order: str = Query("desc", pattern="^(asc|desc)$"),
) -> ClinicalTargetResponse:
    return get_osteoporose_homens(
        data_inicio=data_inicio,
        data_fim=data_fim,
        uf=uf,
        regiao_id=regiao_id,
        id_ibge7=id_ibge7,
        page=page,
        page_size=page_size,
        sort_field=sort_field,
        sort_order=sort_order,
    )
