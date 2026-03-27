from fastapi import APIRouter
from .endpoints import analytics, targets, geo, cache

api_router = APIRouter()

api_router.include_router(analytics.router, prefix="/analytics", tags=["Analytics"])
api_router.include_router(targets.router, prefix="/targets", tags=["Targets"])
api_router.include_router(geo.router, prefix="/geo", tags=["Geo"])
api_router.include_router(cache.router, prefix="/cache", tags=["Cache"])

