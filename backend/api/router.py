from fastapi import APIRouter
from .endpoints import dashboard, geo, cache

api_router = APIRouter()

api_router.include_router(dashboard.router, prefix="/dashboard", tags=["Dashboard"])
api_router.include_router(geo.router, prefix="/geo", tags=["Geo"])
api_router.include_router(cache.router, prefix="/cache", tags=["Cache"])
