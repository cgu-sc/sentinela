from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from database import get_db, engine
from data_cache import refresh_cache, get_df

router = APIRouter()


@router.post("/refresh")
def refresh(db: Session = Depends(get_db)):
    """
    Força a re-leitura do SQL Server e regera o cache Parquet.
    Chamar após executar o pos_processamento.sql.
    """
    try:
        refresh_cache(engine)
        df = get_df()
        return {
            "status": "ok",
            "linhas": len(df),
            "tamanho_mb": round(df.estimated_size("mb"), 1),
        }
    except Exception as e:
        return {"status": "erro", "detalhe": str(e)}
