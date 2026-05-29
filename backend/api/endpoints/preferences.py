from fastapi import APIRouter, HTTPException

from ..schemas.preferences import (
    FiltersPayload,
    NotaTecnicaPayload,
    PreferencesSchema,
    UiPayload,
    WatchlistPayload,
)
from ..services.preferences import PreferencesService
from ..services.analytics.nota_tecnica_regionais import resolve_nota_tecnica_regional

router = APIRouter()


@router.get("", response_model=PreferencesSchema)
def get_preferences():
    return PreferencesService.read()


@router.put("", response_model=PreferencesSchema)
def save_preferences(payload: PreferencesSchema):
    return PreferencesService.write(payload.model_dump())


@router.put("/filters", response_model=PreferencesSchema)
def save_filters(payload: FiltersPayload):
    return PreferencesService.update_filters(payload.filters)


@router.put("/watchlist", response_model=PreferencesSchema)
def save_watchlist(payload: WatchlistPayload):
    return PreferencesService.update_watchlist(
        [item.model_dump() for item in payload.interesse]
    )


@router.put("/ui", response_model=PreferencesSchema)
def save_ui(payload: UiPayload):
    return PreferencesService.update_ui(payload.ui)


@router.put("/nota-tecnica", response_model=PreferencesSchema)
def save_nota_tecnica(payload: NotaTecnicaPayload):
    try:
        resolve_nota_tecnica_regional(payload.nota_tecnica.get("regional_codigo"))
    except RuntimeError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    return PreferencesService.update_nota_tecnica(payload.nota_tecnica)
