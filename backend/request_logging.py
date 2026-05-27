from __future__ import annotations

import time
from pathlib import Path
from typing import Any

from fastapi import FastAPI, Request
from loguru import logger
from pydantic import BaseModel, Field

_REQUEST_SINK_ID: int | None = None
_FRONTEND_SINK_ID: int | None = None


class FrontendPerformanceEvent(BaseModel):
    cnpj: str = Field(..., min_length=1)
    event: str = Field(..., min_length=1)
    elapsed_ms: float = Field(..., ge=0)
    session_id: str = Field(..., min_length=1)
    detail: dict[str, Any] = Field(default_factory=dict)


def _project_root() -> Path:
    return Path(__file__).resolve().parent.parent


def _should_log_request(request: Request) -> bool:
    path = request.url.path
    if path.startswith("/api/v1/analytics/cnpj/"):
        return True
    if path == "/api/v1/analytics/resumo" and request.query_params.get("cnpj_raiz"):
        return True
    return False


def _extract_cnpj(request: Request) -> str:
    path_parts = request.url.path.strip("/").split("/")
    if "cnpj" in path_parts:
        index = path_parts.index("cnpj")
        if index + 1 < len(path_parts):
            return path_parts[index + 1]
    return request.query_params.get("cnpj_raiz") or "-"


def _query_params(request: Request) -> dict[str, Any]:
    keys = (
        "data_inicio",
        "data_fim",
        "periodo",
        "date_str",
        "hour",
        "scope",
        "metric",
        "uf",
        "regiao_id",
        "cnpj_raiz",
    )
    return {key: request.query_params[key] for key in keys if key in request.query_params}


def configure_request_timing_logger(app: FastAPI) -> None:
    global _REQUEST_SINK_ID

    log_dir = _project_root() / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    log_file = log_dir / "cnpj_detail_requests.log"

    if _REQUEST_SINK_ID is None:
        _REQUEST_SINK_ID = logger.add(
            log_file,
            rotation="20 MB",
            retention="30 days",
            enqueue=True,
            encoding="utf-8",
            format="{time:YYYY-MM-DD HH:mm:ss.SSS} | {message}",
            filter=lambda record: record["extra"].get("sentinela_log") == "request_timing",
        )

    @app.middleware("http")
    async def request_timing_middleware(request: Request, call_next):
        if not _should_log_request(request):
            return await call_next(request)

        started = time.perf_counter()
        status_code = 500
        error_text = None
        try:
            response = await call_next(request)
            status_code = response.status_code
            return response
        except Exception as exc:
            error_text = f"{type(exc).__name__}: {exc}"
            raise
        finally:
            elapsed_ms = round((time.perf_counter() - started) * 1000, 2)
            logger.bind(sentinela_log="request_timing").info(
                "cnpj={} | {} {} | params={} | status={} | tempo_ms={}{}",
                _extract_cnpj(request),
                request.method,
                request.url.path,
                _query_params(request),
                status_code,
                elapsed_ms,
                f" | erro={error_text}" if error_text else "",
            )


def configure_frontend_performance_logger() -> None:
    global _FRONTEND_SINK_ID

    log_dir = _project_root() / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    log_file = log_dir / "cnpj_detail_frontend.log"

    if _FRONTEND_SINK_ID is None:
        _FRONTEND_SINK_ID = logger.add(
            log_file,
            rotation="20 MB",
            retention="30 days",
            enqueue=True,
            encoding="utf-8",
            format="{time:YYYY-MM-DD HH:mm:ss.SSS} | {message}",
            filter=lambda record: record["extra"].get("sentinela_log") == "frontend_perf",
        )


def log_frontend_performance(event: FrontendPerformanceEvent) -> dict[str, bool]:
    configure_frontend_performance_logger()
    logger.bind(sentinela_log="frontend_perf").info(
        "session={} | cnpj={} | evento={} | tempo_ms={} | detail={}",
        event.session_id,
        event.cnpj,
        event.event,
        round(event.elapsed_ms, 2),
        event.detail,
    )
    return {"ok": True}
