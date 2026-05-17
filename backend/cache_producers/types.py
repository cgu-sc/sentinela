from dataclasses import dataclass

import polars as pl


@dataclass(frozen=True)
class CacheLoadResult:
    df: pl.DataFrame | None
    from_cache: bool
    read_time_ms: float | None = None
    query_time_ms: float | None = None
    save_time_ms: float | None = None
    error: str | None = None
