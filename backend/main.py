import mimetypes

# Corrigindo tipos MIME no Windows (evita erro de text/plain no JS/CSS)
mimetypes.add_type('application/javascript', '.js')
mimetypes.add_type('text/css', '.css')

from contextlib import asynccontextmanager
from fastapi import FastAPI, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import text
from database import get_db, engine
from api.router import api_router
from fastapi.middleware.cors import CORSMiddleware
from data_cache import load_cache

@asynccontextmanager
async def lifespan(app: FastAPI):
    load_cache(engine)
    yield

# =============================================================================
# INICIALIZAÇÃO DO APP FASTAPI
# =============================================================================
app = FastAPI(
    title="Sentinela API",
    description="Backend oficial para o Projeto Sentinela (Web/Desktop)",
    version="0.1.0",
    lifespan=lifespan
)

# Configuração de CORS para permitir que o Frontend (Vue) em modo DEV
# acesse a API rodando no FastAPI sem erros de segurança.
origins = [
    "http://localhost:5173",
    "http://127.0.0.1:5173",
    "*"
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Registro do Roteador Modular (Onde todas as rotas estão organizadas)
app.include_router(api_router, prefix="/api/v1")

from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
import os
import sys

# =============================================================================
# SERVIR FRONTEND (BUILD)
# =============================================================================
if getattr(sys, 'frozen', False):
    # Se rodando como EXE (PyInstaller), a base é a pasta temporária de extração (sys._MEIPASS)
    # ou a pasta do executável se não for modo onefile (sys.executable)
    BASE_DIR = getattr(sys, '_MEIPASS', os.path.dirname(sys.executable))
    FRONTEND_PATH = os.path.join(BASE_DIR, "frontend", "dist")
else:
    # Se rodando como script, a base é a raiz do projeto
    BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    FRONTEND_PATH = os.path.join(BASE_DIR, "frontend", "dist")

# Debug para o console do usuário ver onde o sistema está procurando
print(f"📂 Procurando frontend em: {FRONTEND_PATH}")

if os.path.exists(FRONTEND_PATH):
    app.mount("/assets", StaticFiles(directory=os.path.join(FRONTEND_PATH, "assets")), name="static")

    @app.get("/")
    async def serve_index():
        return FileResponse(os.path.join(FRONTEND_PATH, "index.html"))

    # Rota de captura para todas as outras URLs (necessário para Vue Router History Mode)
    @app.get("/{full_path:path}")
    async def catch_all(full_path: str):
        # Se o arquivo existir na pasta assets, o mount acima já pegou.
        # Se não existir, mandamos o index.html pro Vue Router se achar.
        return FileResponse(os.path.join(FRONTEND_PATH, "index.html"))
else:
    print("⚠️ Pasta frontend/dist não encontrada! Verifique se rodou o build_sentinela.ps1.")

# @app.get("/")
# def read_root():
#     return {
#         "status": "Online",
#         "app": "Sentinela API",
#         "version": "0.1.0",
#         "db": "Conectado ao SQL Server (SDH-DIE-BD)"
#     }

@app.get("/saude")
def testar_conexao(db: Session = Depends(get_db)):
    """
    Endpoint simples para validar se a conexão com o banco está ok.
    """
    try:
        result = db.execute(text("SELECT 1")).fetchone()
        return {"status": "Database OK", "timestamp": "Conexão está ativa"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Erro de conexão: {str(e)}")

# =============================================================================
# INFORMAÇÕES DE EXECUÇÃO COMO EXECUTÁVEL (ENTRY POINT)
# =============================================================================
if __name__ == "__main__":
    import uvicorn

    # Iniciamos o servidor na porta 8002
    # Quando rodando via Tauri, este executável é iniciado automaticamente.
    print("🚀 Sentinela Sidecar Backend rodando na porta 8002...")
    uvicorn.run(app, host="127.0.0.1", port=8002)
