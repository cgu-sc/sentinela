from fastapi import APIRouter, HTTPException
from typing import Any

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


def _validate_assinantes_tecnicos(value: Any) -> list[dict[str, str]]:
    if value is None:
        return []
    if not isinstance(value, list):
        raise HTTPException(status_code=422, detail="assinantes_tecnicos deve ser uma lista.")
    if len(value) > 3:
        raise HTTPException(status_code=422, detail="Informe no maximo 3 assinaturas tecnicas.")

    normalized: list[dict[str, str]] = []
    for item in value:
        if not isinstance(item, dict):
            raise HTTPException(status_code=422, detail="Cada assinatura tecnica deve ser um objeto.")
        nome = str(item.get("nome", "")).strip()
        cargo = str(item.get("cargo", "")).strip()
        if (nome and not cargo) or (cargo and not nome):
            raise HTTPException(
                status_code=422,
                detail="Cada assinatura tecnica deve conter nome e cargo.",
            )
        if nome and cargo:
            normalized.append({"nome": nome, "cargo": cargo})
    return normalized


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
    payload.nota_tecnica["assinantes_tecnicos"] = _validate_assinantes_tecnicos(
        payload.nota_tecnica.get("assinantes_tecnicos")
    )
    return PreferencesService.update_nota_tecnica(payload.nota_tecnica)
