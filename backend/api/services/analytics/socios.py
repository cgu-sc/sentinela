import polars as pl
from fastapi import HTTPException

from cache_producers.socios import load_socios
from ...schemas.analytics import SocioSchema, SociosResponse


def get_socios_farmacia(cnpj: str) -> SociosResponse:
    """
    Retorna o quadro societario de uma farmacia a partir do cache/produtor.
    """
    result = load_socios(cnpj)
    if result.error:
        raise HTTPException(
            status_code=503,
            detail=f"Base de dados societaria indisponivel: {result.error}",
        )

    df_all = result.df
    from_cache = result.from_cache

    if df_all is None or len(df_all.columns) == 0:
        raise HTTPException(
            status_code=503,
            detail="Base de dados societaria indisponivel no momento (Sem cache local e banco de dados offline).",
        )

    df_target = df_all.filter(pl.col("cnpj") == cnpj)

    if df_target.is_empty():
        return SociosResponse(cnpj=cnpj, socios=[], from_cache=from_cache)

    df_target = df_target.sort("data_entrada_sociedade", descending=True)
    data_proc = df_target["data_processamento"][0] if "data_processamento" in df_target.columns else None

    return SociosResponse(
        cnpj=cnpj,
        socios=[SocioSchema(**s) for s in df_target.to_dicts()],
        data_processamento=data_proc,
        from_cache=from_cache,
    )
