import os
import time
import polars as pl
from ...schemas.analytics import NetworkNodeSchema, NetworkEdgeSchema, NetworkResponse
from ._cache import _get_cnpj_cache_dir, sync_network


def get_socios_network(cnpj: str, engine) -> NetworkResponse:
    """
    Retorna a rede de relacionamentos societários de um CNPJ.

    Estratégia cache-first (padrão do projeto):
      1. Verifica se sentinela_cache/{cnpj}/network_nodes.parquet existe e é válido.
      2. Cache hit  → lê do Parquet e reconstrói NetworkResponse (rápido, offline-safe).
      3. Cache miss → chama sync_network() para buscar do banco e salvar Parquet,
                      depois lê o Parquet recém-gerado.
    """
    t0 = time.perf_counter()

    cnpj_dir    = _get_cnpj_cache_dir(cnpj)
    NODES_PATH  = os.path.join(cnpj_dir, "network_nodes.parquet")
    EDGES_PATH  = os.path.join(cnpj_dir, "network_edges.parquet")

    # ── Cache miss: gera o Parquet ────────────────────────────────────────────
    cache_exists = os.path.exists(NODES_PATH) and os.path.exists(EDGES_PATH)
    if not cache_exists:
        sync_network(cnpj)

    # ── Lê do Parquet ─────────────────────────────────────────────────────────
    try:
        df_nodes = pl.read_parquet(NODES_PATH)
        df_edges = pl.read_parquet(EDGES_PATH) if os.path.exists(EDGES_PATH) else pl.DataFrame()
    except Exception as e:
        print(f"⚠️ Erro ao ler Parquet de teia para {cnpj}: {e}")
        return NetworkResponse(cnpj=cnpj, nodes=[], edges=[])

    # ── Reconstrói os schemas a partir dos DataFrames ─────────────────────────
    nodes = [
        NetworkNodeSchema(
            id=row["id"],
            label=row["label"] or "",
            type=row["type"] or "PJ_OUTRA",
            razao_social=row.get("razao_social"),
            nome_fantasia=row.get("nome_fantasia"),
            id_cnae_principal=row.get("id_cnae_principal"),
            municipio=row.get("municipio"),
            uf=row.get("uf"),
            situacao_rf=row.get("situacao_rf"),
            is_ativo=row.get("is_ativo", True)
        )
        for row in df_nodes.iter_rows(named=True)
    ]

    edges = [
        NetworkEdgeSchema(
            id=row["id"],
            source=row["source"],
            target=row["target"],
            label=row["label"] or None,
            type=row["type"] or "socio",
            is_ativo=row.get("is_ativo", True)
        )
        for row in df_edges.iter_rows(named=True)
    ] if not df_edges.is_empty() else []

    return NetworkResponse(
        cnpj=cnpj,
        nodes=nodes,
        edges=edges,
        query_time_ms=round((time.perf_counter() - t0) * 1000, 1),
    )
