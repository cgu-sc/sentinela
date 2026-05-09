import os
import time
import polars as pl
from ...schemas.analytics import NetworkNodeSchema, NetworkEdgeSchema, NetworkResponse
from ._cache import _get_cnpj_cache_dir, sync_network


def get_teia_grafo_nivel2(cnpj: str, engine) -> NetworkResponse:
    """
    Retorna a rede de relacionamentos societários de um CNPJ.

    Estratégia cache-first (padrão do projeto):
      1. Verifica se sentinela_cache/{cnpj}/teia_grafo_nivel2_nodes.parquet existe e é válido.
      2. Cache hit  → lê do Parquet e reconstrói NetworkResponse (rápido, offline-safe).
      3. Cache miss → chama sync_network() para buscar do banco e salvar Parquet,
                      depois lê o Parquet recém-gerado.
    """
    t0 = time.perf_counter()

    cnpj_dir    = _get_cnpj_cache_dir(cnpj)
    NODES_PATH  = os.path.join(cnpj_dir, "teia_grafo_nivel2_nodes.parquet")
    EDGES_PATH  = os.path.join(cnpj_dir, "teia_grafo_nivel2_edges.parquet")

    # ── Cache miss: gera o Parquet ────────────────────────────────────────────
    # Agora o sync_network gera 4 arquivos (nodes, edges + expansion_nodes, expansion_edges) sob o novo padrão teia_grafo_*
    if not os.path.exists(NODES_PATH):
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
            is_ativo=row.get("is_ativo") if row.get("is_ativo") is not None else True
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
            is_ativo=row.get("is_ativo") if row.get("is_ativo") is not None else True
        )
        for row in df_edges.iter_rows(named=True)
    ] if not df_edges.is_empty() else []

    return NetworkResponse(
        cnpj=cnpj,
        nodes=nodes,
        edges=edges,
        query_time_ms=round((time.perf_counter() - t0) * 1000, 1),
    )


def get_teia_grafo_nivel3_expansao(cnpj_alvo: str, cnpj_para_expandir: str) -> NetworkResponse:
    """
    Carrega os dados de expansão (Nível 3) para um nó específico que já está na teia.
    Lê os arquivos de expansão pré-gerados na pasta de cache do CNPJ alvo.
    """
    t0 = time.perf_counter()
    cnpj_dir = _get_cnpj_cache_dir(cnpj_alvo)
    EXP_NODES_PATH = os.path.join(cnpj_dir, "teia_grafo_nivel3_nodes.parquet")
    EXP_EDGES_PATH = os.path.join(cnpj_dir, "teia_grafo_nivel3_edges.parquet")

    if not os.path.exists(EXP_NODES_PATH) or not os.path.exists(EXP_EDGES_PATH):
        # Se não existe, tenta rodar o sync uma vez (caso o cache seja de versão antiga)
        sync_network(cnpj_alvo)
        if not os.path.exists(EXP_NODES_PATH):
            return NetworkResponse(cnpj=cnpj_alvo, nodes=[], edges=[])

    try:
        # Filtra apenas as arestas que saem ou entram na empresa sendo expandida
        # (Neste nível de cache, o target é sempre o CNPJ_IRMÃ que queremos abrir)
        df_exp_edges = pl.read_parquet(EXP_EDGES_PATH).filter(pl.col("target") == cnpj_para_expandir)
        
        if df_exp_edges.is_empty():
            return NetworkResponse(cnpj=cnpj_alvo, nodes=[], edges=[])

        # Pega os IDs dos sócios encontrados para esta expansão
        cpfs_socios = df_exp_edges["source"].unique().to_list()
        
        # Busca os detalhes destes nós no arquivo de expansão
        df_exp_nodes = pl.read_parquet(EXP_NODES_PATH).filter(pl.col("id").is_in(cpfs_socios))

        nodes = [
            NetworkNodeSchema(
                id=row["id"],
                label=row["label"] or "",
                type=row["type"] or "PF",
                razao_social=row.get("razao_social"),
                is_ativo=row.get("is_ativo") if row.get("is_ativo") is not None else True
            )
            for row in df_exp_nodes.iter_rows(named=True)
        ]

        edges = [
            NetworkEdgeSchema(
                id=row["id"],
                source=row["source"],
                target=row["target"],
                label=row["label"] or None,
                type=row["type"] or "socio",
                is_ativo=row.get("is_ativo") if row.get("is_ativo") is not None else True
            )
            for row in df_exp_edges.iter_rows(named=True)
        ]

        return NetworkResponse(
            cnpj=cnpj_alvo, 
            nodes=nodes, 
            edges=edges,
            query_time_ms=round((time.perf_counter() - t0) * 1000, 1)
        )

    except Exception as e:
        print(f"⚠️ Erro ao expandir nó {cnpj_para_expandir} na teia {cnpj_alvo}: {e}")
        return NetworkResponse(cnpj=cnpj_alvo, nodes=[], edges=[])
