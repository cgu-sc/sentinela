from fastapi import APIRouter, Depends, BackgroundTasks
from sqlalchemy.orm import Session
from database import get_db, engine
from data_cache import refresh_cache, get_cache_status

router = APIRouter()

@router.get("/status")
def status():
    """Retorna o progresso atual da sincronização."""
    return get_cache_status()

@router.post("/refresh")
def refresh(background_tasks: BackgroundTasks):
    """
    Inicia a re-leitura do SQL Server em segundo plano.
    """
    # Dispara o processamento em background para não travar a requisição HTTP
    background_tasks.add_task(refresh_cache, engine)
    return {"status": "started", "message": "Sincronização iniciada em segundo plano."}
