import mimetypes

# Corrigindo tipos MIME no Windows (evita erro de text/plain no JS/CSS)
mimetypes.add_type('application/javascript', '.js')
mimetypes.add_type('text/css', '.css')

from fastapi import FastAPI, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import text
from database import get_db

# =============================================================================
# INICIALIZAÇÃO DO APP FASTAPI
# =============================================================================
app = FastAPI(
    title="Sentinela API",
    description="Backend oficial para o Projeto Sentinela (Web/Desktop)",
    version="0.1.0"
)

# =============================================================================
# ENDPOINTS BÁSICOS
# =============================================================================

from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
import os
import sys

# =============================================================================
# SERVIR FRONTEND (BUILD)
# =============================================================================
if getattr(sys, 'frozen', False):
    # Se rodando como EXE, a base é a pasta do próprio executável
    BASE_DIR = os.path.dirname(sys.executable)
    # No seu script de build, o frontend vai para dist/frontend/dist
    FRONTEND_PATH = os.path.join(BASE_DIR, "frontend", "dist")
else:
    # Se rodando como script, a base é a raiz do projeto
    BASE_DIR = os.path.dirname(os.path.dirname(__file__))
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
def testar_conexão(db: Session = Depends(get_db)):
    """
    Endpoint simples para validar se a conexão com o banco está ok.
    Executa uma query simples de teste no SQL Server.
    """
    try:
        # Testa a conexão executando um SELECT 1
        result = db.execute(text("SELECT 1")).fetchone()
        if result:
            return {"status": "Database OK", "timestamp": "Conexão estabelecida com sucesso"}
        else:
            raise HTTPException(status_code=500, detail="Banco retornou vazio no teste")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Erro de conexão com o banco: {str(e)}")

# =============================================================================
# EXEMPLO DE ENDPOINT PARA INDICADORES (Esboço)
# =============================================================================

@app.get("/indicadores/crm/{cnpj}")
def buscar_indicadores_crm(cnpj: str, db: Session = Depends(get_db)):
    """
    Exemplo de como buscaremos os dados da tabela indicador_crm_detalhado
    que acabamos de organizar!
    """
    query = text("SELECT * FROM temp_CGUSC.fp.indicador_crm_detalhado WHERE nu_cnpj = :cnpj")
    result = db.execute(query, {"cnpj": cnpj}).fetchone()
    
    if not result:
        raise HTTPException(status_code=404, detail="CNPJ não encontrado na tabela de indicadores CRM")
    
    # Converte o resultado para dicionário (usando as chaves que definimos no SQL)
    return dict(result._mapping)

# =============================================================================
# INFORMAÇÕES DE EXECUÇÃO COMO EXECUTÁVEL (ENTRY POINT)
# =============================================================================
if __name__ == "__main__":
    import uvicorn
    # Iniciamos o servidor na porta 8000
    print("🚀 Sentinela API iniciando na porta 8000...")
    uvicorn.run(app, host="0.0.0.0", port=8000)
