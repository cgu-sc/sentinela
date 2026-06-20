from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, HttpUrl


class UpdateManifest(BaseModel):
    schema_version: int
    product: str
    channel: str
    latest_version: str
    minimum_supported_version: str
    published_at: datetime
    download_url: HttpUrl
    release_notes_url: HttpUrl


class UpdateStatusResponse(BaseModel):
    current_version: str
    latest_version: str | None
    minimum_supported_version: str | None
    status: Literal[
        "current",
        "update_available",
        "update_required",
        "offline_cached",
        "verification_unavailable",
    ]
    checked_at: datetime | None
    source: Literal["remote", "cache", "none"]
    download_url: str | None
    release_notes_url: str | None
    message: str
