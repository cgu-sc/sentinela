from fastapi import APIRouter

from ..schemas.preferences import (
    FiltersPayload,
    PreferencesSchema,
    UiPayload,
    WatchlistPayload,
)
from ..services.preferences import PreferencesService

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
