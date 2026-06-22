import asyncio
import logging
import sys

from fastapi import APIRouter, HTTPException

from api.schemas.system_update import UpdateStatusResponse
from api.services.system_update import (
    check_for_updates,
    download_and_apply_update,
    apply_update,
    cancel_update,
    get_cached_status,
    get_download_state,
)

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


@router.post("/download-update")
async def trigger_download_update(body: dict | None = None) -> dict:
    """
    Inicia o download automático e a aplicação da nova versão em background.

    Restrito exclusivamente ao modo Desktop (sys.frozen=True).
    Em modo de desenvolvimento (web), retorna HTTP 400.

    Após o download, o backend gera um script update.bat, o lança desvinculado
    e encerra seu próprio processo. O script .bat aguarda o processo pai
    terminar, substitui o .exe e reinicia o Sentinela.
    """
    # Permite override de URL via body (usado apenas para testes)
    override_url = (body or {}).get("download_url")

    cached = get_cached_status()
    download_url = override_url or (cached.download_url if cached else None)

    if not download_url:
        raise HTTPException(
            status_code=409,
            detail="URL de download não disponível. Verifique o manifesto de atualizações.",
        )

    try:
        download_and_apply_update(download_url)
    except RuntimeError as exc:
        is_frozen = getattr(sys, "frozen", False)
        status_code = 400 if not is_frozen else 409
        raise HTTPException(status_code=status_code, detail=str(exc)) from exc

    return {"ok": True, "message": "Download iniciado em segundo plano."}


@router.get("/download-progress")
async def get_download_progress() -> dict:
    """
    Retorna o estado atual do download automático.

    Resposta:
      - status: idle | downloading | applying | done | error
      - progress: float 0.0–1.0
      - error: string | null
    """
    return get_download_state()


@router.post("/apply-update")
async def trigger_apply_update() -> dict:
    """Lança o bat de atualização e encerra o servidor. Chamado pelo frontend após contagem regressiva."""
    try:
        await asyncio.get_event_loop().run_in_executor(None, apply_update)
    except RuntimeError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    return {"ok": True}


@router.post("/cancel-update")
async def trigger_cancel_update() -> dict:
    """Cancela a atualização pendente, removendo o .tmp baixado."""
    cancel_update()
    return {"ok": True}
