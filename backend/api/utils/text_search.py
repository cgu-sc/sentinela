import unicodedata

import polars as pl


def normalize_search_text(value: object) -> str:
    if value is None:
        return ""
    normalized = unicodedata.normalize("NFKD", str(value))
    without_accents = "".join(ch for ch in normalized if not unicodedata.combining(ch))
    return " ".join(without_accents.lower().split())


def tokenize_search_text(value: str | None, min_length: int = 2) -> list[str]:
    normalized = normalize_search_text(value)
    return [token for token in normalized.split(" ") if len(token) >= min_length]


def apply_token_search(
    df: pl.DataFrame,
    query: str | None,
    columns: tuple[str, ...] | list[str],
    *,
    min_token_length: int = 2,
) -> pl.DataFrame:
    tokens = tokenize_search_text(query, min_token_length)
    if not tokens or df.is_empty():
        return df

    search_cols = [col for col in columns if col in df.columns]
    if not search_cols:
        return df

    search_expr = pl.concat_str(
        [pl.col(col).cast(pl.Utf8).fill_null("") for col in search_cols],
        separator=" ",
    ).map_elements(normalize_search_text, return_dtype=pl.Utf8)

    filtered = df.with_columns(search_expr.alias("_token_search"))
    for token in tokens:
        filtered = filtered.filter(pl.col("_token_search").str.contains(token, literal=True))
    return filtered.drop("_token_search")
