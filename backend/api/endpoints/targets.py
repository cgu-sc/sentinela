from datetime import date

from fastapi import APIRouter, Query

from ..schemas.targets import ParkinsonTargetResponse
from ..services.targets import get_parkinson_menor_50

router = APIRouter()


@router.get("/parkinson-menor-50", response_model=ParkinsonTargetResponse)
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
) -> ParkinsonTargetResponse:
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
