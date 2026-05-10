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
            type=row["type"],
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

    sync_network(cnpj_alvo)
    if not os.path.exists(EXP_NODES_PATH) or not os.path.exists(EXP_EDGES_PATH):
        return NetworkResponse(cnpj=cnpj_alvo, nodes=[], edges=[])

    try:
        df_all_edges = pl.read_parquet(EXP_EDGES_PATH)
        df_soc_edges = df_all_edges.filter(pl.col("target") == cnpj_para_expandir)
        
        if df_soc_edges.is_empty():
            return NetworkResponse(cnpj=cnpj_alvo, nodes=[], edges=[])

        # Pega os IDs dos sócios encontrados para esta expansão
        cpfs_socios = df_soc_edges["source"].unique().to_list()
        df_rep_edges = df_all_edges.filter(
            (pl.col("type") == "representante") &
            (pl.col("target").is_in(cpfs_socios))
        )
        df_exp_edges = pl.concat([df_soc_edges, df_rep_edges]).unique(subset=["id"], keep="first")
        
        # Busca os detalhes destes nós no arquivo de expansão
        node_ids = set(df_exp_edges["source"].to_list()) | set(df_exp_edges["target"].to_list())
        node_ids.discard(cnpj_para_expandir)
        df_exp_nodes = pl.read_parquet(EXP_NODES_PATH).filter(pl.col("id").is_in(list(node_ids)))

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


def get_teia_grafo_nivel4_expansao(cnpj_alvo: str, cpf_para_expandir: str) -> NetworkResponse:
    """
    Carrega os dados de expansão (Nível 4) para um SÓCIO específico.
    Lê os arquivos de expansão N4 pré-gerados na pasta de cache do CNPJ alvo.
    """
    t0 = time.perf_counter()
    cnpj_dir = _get_cnpj_cache_dir(cnpj_alvo)
    N4_NODES_PATH = os.path.join(cnpj_dir, "teia_grafo_nivel4_nodes.parquet")
    N4_EDGES_PATH = os.path.join(cnpj_dir, "teia_grafo_nivel4_edges.parquet")

    sync_network(cnpj_alvo)
    if not os.path.exists(N4_NODES_PATH) or not os.path.exists(N4_EDGES_PATH):
        return NetworkResponse(cnpj=cnpj_alvo, nodes=[], edges=[])

    try:
        df_all_edges = pl.read_parquet(N4_EDGES_PATH)
        df_company_edges = df_all_edges.filter(pl.col("source") == cpf_para_expandir)
        df_rep_edges = df_all_edges.filter(
            (pl.col("type") == "representante") &
            (pl.col("target") == cpf_para_expandir)
        )
        df_n4_edges = pl.concat([df_company_edges, df_rep_edges]).unique(subset=["id"], keep="first")
        
        if df_n4_edges.is_empty():
            return NetworkResponse(cnpj=cnpj_alvo, nodes=[], edges=[])

        # Pega os IDs das empresas encontradas
        node_ids = set(df_n4_edges["source"].to_list()) | set(df_n4_edges["target"].to_list())
        node_ids.discard(cpf_para_expandir)
        
        # Busca detalhes das empresas
        df_n4_nodes = pl.read_parquet(N4_NODES_PATH).filter(pl.col("id").is_in(list(node_ids)))

        nodes = [
            NetworkNodeSchema(
                id=row["id"],
                label=row["label"] or "",
                type=row["type"],
                razao_social=row.get("razao_social"),
                municipio=row.get("municipio"),
                uf=row.get("uf"),
                situacao_rf=row.get("situacao_rf"),
                is_ativo=row.get("is_ativo") if row.get("is_ativo") is not None else True
            )
            for row in df_n4_nodes.iter_rows(named=True)
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
            for row in df_n4_edges.iter_rows(named=True)
        ]

        return NetworkResponse(
            cnpj=cnpj_alvo, 
            nodes=nodes, 
            edges=edges,
            query_time_ms=round((time.perf_counter() - t0) * 1000, 1)
        )

    except Exception as e:
        print(f"⚠️ Erro ao expandir sócio {cpf_para_expandir} na teia {cnpj_alvo}: {e}")
        return NetworkResponse(cnpj=cnpj_alvo, nodes=[], edges=[])

def get_teia_grafo_nivel3_full(cnpj_alvo: str) -> NetworkResponse:
    """Retorna TODOS os sócios de nível 3 (Sócios de N2) em lote."""
    CACHE_DIR = _get_cnpj_cache_dir(cnpj_alvo)
    NODES_PATH = os.path.join(CACHE_DIR, "teia_grafo_nivel3_nodes.parquet")
    EDGES_PATH = os.path.join(CACHE_DIR, "teia_grafo_nivel3_edges.parquet")

    sync_network(cnpj_alvo)
    if not os.path.exists(NODES_PATH):
        return NetworkResponse(cnpj=cnpj_alvo, nodes=[], edges=[])

    try:
        df_nodes = pl.read_parquet(NODES_PATH)
        df_edges = pl.read_parquet(EDGES_PATH)

        nodes = [
            NetworkNodeSchema(
                id=row["id"],
                label=row["label"] or "",
                type=row.get("type") or "PF",
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
                type=row.get("type") or "socio",
                is_ativo=row.get("is_ativo") if row.get("is_ativo") is not None else True
            )
            for row in df_edges.iter_rows(named=True)
        ]

        return NetworkResponse(cnpj=cnpj_alvo, nodes=nodes, edges=edges)
    except Exception as e:
        print(f"[ NETWORK ] ERRO BATCH N3 EM {cnpj_alvo}: {e}")
        return NetworkResponse(cnpj=cnpj_alvo, nodes=[], edges=[])

def get_teia_grafo_nivel4_full(cnpj_alvo: str) -> NetworkResponse:
    """Retorna TODAS as empresas de nível 4 (Participações de N3) em lote."""
    CACHE_DIR = _get_cnpj_cache_dir(cnpj_alvo)
    NODES_PATH = os.path.join(CACHE_DIR, "teia_grafo_nivel4_nodes.parquet")
    EDGES_PATH = os.path.join(CACHE_DIR, "teia_grafo_nivel4_edges.parquet")

    sync_network(cnpj_alvo)
    if not os.path.exists(NODES_PATH):
        return NetworkResponse(cnpj=cnpj_alvo, nodes=[], edges=[])

    try:
        df_nodes = pl.read_parquet(NODES_PATH)
        df_edges = pl.read_parquet(EDGES_PATH)

        nodes = [
            NetworkNodeSchema(
                id=row["id"],
                label=row["label"] or "",
                type=row.get("type") or "PJ",
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
                type=row.get("type") or "socio",
                is_ativo=row.get("is_ativo") if row.get("is_ativo") is not None else True
            )
            for row in df_edges.iter_rows(named=True)
        ]

        return NetworkResponse(cnpj=cnpj_alvo, nodes=nodes, edges=edges)
    except Exception as e:
        print(f"[ NETWORK ] ERRO BATCH N4 EM {cnpj_alvo}: {e}")
        return NetworkResponse(cnpj=cnpj_alvo, nodes=[], edges=[])
