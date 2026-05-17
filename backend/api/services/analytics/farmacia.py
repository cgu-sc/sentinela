import polars as pl
from fastapi import HTTPException

from cache_producers.farmacia import load_or_sync_memoria_calculo
from data_cache import get_df_dados_farmacia
from ...schemas.analytics import (
    CnpjAccessStatusSchema,
    DadosFarmaciaSchema,
    MovimentacaoResponse,
    MovimentacaoRowSchema,
    MovimentacaoSummarySchema,
)


def _clean_cnpj(value: str) -> str:
    return "".join(ch for ch in value if ch.isdigit())


def get_cnpj_access_status(cnpj: str) -> CnpjAccessStatusSchema:
    clean_cnpj = _clean_cnpj(cnpj)
    if len(clean_cnpj) != 14:
        raise HTTPException(
            status_code=422,
            detail={
                "status": "invalid_format",
                "message": "A tela de estabelecimento aceita apenas CNPJ com 14 digitos.",
                "cnpj": clean_cnpj,
            },
        )

    df = get_df_dados_farmacia()
    rows = df.filter(pl.col("cnpj") == clean_cnpj)
    if rows.is_empty():
        raise HTTPException(
            status_code=404,
            detail={
                "status": "not_in_program",
                "message": "CNPJ nao encontrado na base carregada do Programa Farmacia Popular.",
                "cnpj": clean_cnpj,
            },
        )

    row = rows.select([
        "cnpj",
        "razao_social",
        "nome_fantasia",
        "municipio",
        "uf",
    ]).row(0, named=True)
    return CnpjAccessStatusSchema(
        cnpj=row["cnpj"],
        status="valid",
        in_program=True,
        razao_social=row.get("razao_social"),
        nome_fantasia=row.get("nome_fantasia"),
        municipio=row.get("municipio"),
        uf=row.get("uf"),
    )


def get_dados_farmacia(cnpj: str) -> DadosFarmaciaSchema:
    """Retorna os dados cadastrais e geograficos de uma farmacia especifica."""
    try:
        clean_cnpj = _clean_cnpj(cnpj)
        if len(clean_cnpj) != 14:
            raise HTTPException(
                status_code=422,
                detail="A tela de estabelecimento aceita apenas CNPJ com 14 digitos.",
            )
        df = get_df_dados_farmacia()
        rows = df.filter(pl.col("cnpj") == clean_cnpj)
        if rows.is_empty():
            raise HTTPException(
                status_code=404,
                detail="CNPJ nao encontrado na base carregada do Programa Farmacia Popular.",
            )
        return DadosFarmaciaSchema(**rows.row(0, named=True))
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=f"Erro ao buscar dados cadastrais da farmacia: {exc}",
        ) from exc


def _build_movimentacao_response_from_df(
    cnpj: str,
    df: pl.DataFrame,
    from_cache: bool,
    read_time_ms: float | None = None,
    query_time_ms: float | None = None,
    save_time_ms: float | None = None,
    error: str | None = None,
) -> MovimentacaoResponse:
    """Converte DataFrame Polars para o schema de resposta."""
    rows = [
        MovimentacaoRowSchema(
            tipo_linha=r["tipo_linha"],
            gtin=r.get("gtin"),
            medicamento=r.get("medicamento"),
            periodo_inicial=r.get("periodo_inicial"),
            periodo_inicio_irregular=r.get("periodo_inicio_irregular"),
            periodo_final=r.get("periodo_final"),
            estoque_inicial=int(r["estoque_inicial"]) if r.get("estoque_inicial") is not None else None,
            estoque_final=int(r["estoque_final"]) if r.get("estoque_final") is not None else None,
            vendas=int(r["vendas"]) if r.get("vendas") is not None else None,
            vendas_irregular=int(r["vendas_irregular"]) if r.get("vendas_irregular") is not None else None,
            valor=float(r["valor"]) if r.get("valor") is not None else None,
            valor_irregular=float(r["valor_irregular"]) if r.get("valor_irregular") is not None else None,
            notas=r.get("notas"),
        )
        for r in df.iter_rows(named=True)
    ]

    vendas_rows = [r for r in rows if r.tipo_linha in ("venda_normal", "venda_irregular")]
    total_vendas = sum(r.vendas or 0 for r in vendas_rows)
    total_vendas_irregular = sum(r.vendas_irregular or 0 for r in vendas_rows)
    valor_total = sum(r.valor or 0.0 for r in vendas_rows)
    valor_irregular = sum(r.valor_irregular or 0.0 for r in vendas_rows)
    pct_irregular = (valor_irregular / valor_total * 100) if valor_total else 0.0

    return MovimentacaoResponse(
        cnpj=cnpj,
        summary=MovimentacaoSummarySchema(
            total_vendas=total_vendas,
            total_vendas_irregular=total_vendas_irregular,
            valor_total=round(valor_total, 2),
            valor_irregular=round(valor_irregular, 2),
            pct_irregular=round(pct_irregular, 2),
            from_cache=from_cache,
        ),
        rows=rows,
        from_cache=from_cache,
        read_time_ms=read_time_ms,
        query_time_ms=query_time_ms,
        save_time_ms=save_time_ms,
        error=error,
    )


def get_movimentacao_data(cnpj: str, engine, check_cache: bool = False) -> MovimentacaoResponse:
    """
    Retorna a memoria de calculo processada (movimentacao por GTIN) de um CNPJ.

    A geracao/leitura do parquet fica no producer; este service apenas monta
    o contrato HTTP da API.
    """
    result = load_or_sync_memoria_calculo(cnpj, engine, check_cache=check_cache)
    if result.error:
        raise HTTPException(
            status_code=503,
            detail=f"Memoria de calculo indisponivel: {result.error}",
        )

    return _build_movimentacao_response_from_df(
        cnpj=cnpj,
        df=result.df,
        from_cache=result.from_cache,
        read_time_ms=result.read_time_ms,
        query_time_ms=result.query_time_ms,
        save_time_ms=result.save_time_ms,
        error=result.error,
    )
