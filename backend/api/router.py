from fastapi import APIRouter
from .endpoints import dashboard

api_router = APIRouter()

# Unificação de todos os domínios da API sob um único router principal.
# Aqui poderemos adicionar no futuro routers para /usuarios, /filtros, etc.
api_router.include_router(dashboard.router, prefix="/dashboard", tags=["Dashboard"])
