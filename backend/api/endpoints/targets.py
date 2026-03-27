from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from database import get_db
from ..schemas.targets import TargetResponse
from ..services.targets import TargetService

router = APIRouter()

@router.get("/summary", response_model=TargetResponse)
def get_target_summary(db: Session = Depends(get_db)):
    """
    Retorna o resumo dos alvos para o dashboard de Alvos.
    """
    return TargetService.get_target_summary(db)
