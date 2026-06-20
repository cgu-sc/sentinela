import asyncio
import logging

from fastapi import APIRouter

from api.schemas.system_update import UpdateStatusResponse
from api.services.system_update import check_for_updates, get_cached_status

logger = logging.getLogger(__name__)

router = APIRouter()


@router.get("/update-status", response_model=UpdateStatusResponse)
async def get_update_status() -> UpdateStatusResponse:
    """
    Retorna o estado de atualização conhecido (do cache em memória).
    Não dispara nova consulta remota; use POST /check-update para forçar.
    """
    status = get_cached_status()
    if status is not None:
        return status
    # Estado ainda não inicializado — computa de forma síncrona
    return await asyncio.get_event_loop().run_in_executor(None, check_for_updates)


@router.post("/check-update", response_model=UpdateStatusResponse)
async def force_check_update() -> UpdateStatusResponse:
    """Força nova consulta remota ao manifesto de atualizações."""
    return await asyncio.get_event_loop().run_in_executor(
        None, lambda: check_for_updates(force_remote=True)
    )
