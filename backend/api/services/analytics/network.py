import os
import time
from datetime import date
from typing import Optional
import polars as pl
from data_cache import get_df, get_df_perfil_estabelecimento
from cache_files import (
    TEIA_GRAFO_NIVEL2_EDGES_PARQUET,
    TEIA_GRAFO_NIVEL2_NODES_PARQUET,
    TEIA_GRAFO_NIVEL3_EDGES_PARQUET,
    TEIA_GRAFO_NIVEL3_NODES_PARQUET,
    TEIA_GRAFO_NIVEL4_EDGES_PARQUET,
    TEIA_GRAFO_NIVEL4_NODES_PARQUET,
)
from ...schemas.analytics import NetworkNodeSchema, NetworkEdgeSchema, NetworkResponse, NetworkSummarySchema, NetworkLevelSummarySchema
from ._cache import _get_cnpj_cache_dir, sync_network
from .indicator_rules import (
    NAO_COMPROVACAO_PCT_ATENCAO,
    NAO_COMPROVACAO_PCT_CRITICO,
)

NETWORK_LEVEL_LABELS = {
    "root": "CNPJ analisado",
    "n1": "Sócios diretos",
    "n2": "Empresas dos sócios diretos",
    "n3": "Sócios das empresas N2",
    "n4": "Empresas dos sócios N3",
}

NETWORK_REQUIRED_MOVEMENT_COLUMNS = {
    "id_cnpj",
    "periodo",
    "total_vendas",
    "total_sem_comprovacao",
}
NETWORK_REQUIRED_PROFILE_COLUMNS = {"id_cnpj", "cnpj", "is_conexao_ativa"}


def _is_pf_node(node_type: Optional[str]) -> bool:
    return str(node_type or "").upper() == "PF"


def _normalize_document(value: object) -> str:
    return "".join(char for char in str(value or "") if char.isdigit()).zfill(14)


def _require_columns(df: pl.DataFrame, required: set[str], source: str) -> None:
    missing = sorted(required.difference(df.columns))
    if missing:
        raise RuntimeError(
            f"Cache {source} sem colunas obrigatorias para a teia: {', '.join(missing)}"
        )


def _classify_nao_comprovacao(percentual: float) -> str:
    if percentual >= NAO_COMPROVACAO_PCT_CRITICO:
        return "CRÍTICO"
    if percentual >= NAO_COMPROVACAO_PCT_ATENCAO:
        return "ATENÇÃO"
    return "NORMAL"


def _get_fp_audit_context_by_cnpj(
    rows: list[dict],
    data_inicio: Optional[date],
    data_fim: Optional[date],
) -> dict[str, dict]:
    fp_cnpjs = {
        _normalize_document(row.get("id"))
        for row in rows
        if (row.get("type") or "").upper() == "PJ_FARMACIA_POPULAR"
    }
    if not fp_cnpjs:
        return {}

    profile = get_df_perfil_estabelecimento()
    movement = get_df()
    _require_columns(profile, NETWORK_REQUIRED_PROFILE_COLUMNS, "perfil_estabelecimento")
    _require_columns(movement, NETWORK_REQUIRED_MOVEMENT_COLUMNS, "movimentacao")

    fp_profile = (
        profile
        .with_columns(
            pl.col("cnpj")
            .cast(pl.String)
            .str.replace_all(r"\D", "")
            .str.zfill(14)
            .alias("_network_cnpj")
        )
        .filter(pl.col("_network_cnpj").is_in(sorted(fp_cnpjs)))
        .select("id_cnpj", "_network_cnpj", "is_conexao_ativa")
        .unique(subset=["_network_cnpj"])
    )

    found_cnpjs = set(fp_profile["_network_cnpj"].to_list())
    missing_cnpjs = sorted(fp_cnpjs.difference(found_cnpjs))
    if missing_cnpjs:
        raise RuntimeError(
            "Farmacias Populares da teia ausentes no perfil_estabelecimento: "
            + ", ".join(missing_cnpjs)
        )

    invalid_connections = (
        fp_profile
        .filter(pl.col("is_conexao_ativa").is_null())
        .select("_network_cnpj", "is_conexao_ativa")
    )
    if not invalid_connections.is_empty():
        values = ", ".join(
            f"{row['_network_cnpj']}={row['is_conexao_ativa']}"
            for row in invalid_connections.iter_rows(named=True)
        )
        raise RuntimeError(
            "Farmacias Populares da teia com is_conexao_ativa invalida: " + values
        )

    period_expr = pl.col("periodo").cast(pl.Date)
    filtered_movement = movement
    if data_inicio is not None:
        filtered_movement = filtered_movement.filter(period_expr >= pl.lit(data_inicio))
    if data_fim is not None:
        filtered_movement = filtered_movement.filter(period_expr <= pl.lit(data_fim))

    aggregated = (
        filtered_movement
        .join(fp_profile, on="id_cnpj", how="inner")
        .group_by("_network_cnpj")
        .agg(
            pl.sum("total_vendas").alias("_total_vendas"),
            pl.sum("total_sem_comprovacao").alias("_total_sem_comprovacao"),
        )
    )

    result = (
        fp_profile
        .join(aggregated, on="_network_cnpj", how="left")
        .with_columns(
            pl.col("_total_vendas").fill_null(0),
            pl.col("_total_sem_comprovacao").fill_null(0),
        )
        .with_columns(
            pl.when(pl.col("_total_vendas") > 0)
            .then(
                pl.col("_total_sem_comprovacao")
                / pl.col("_total_vendas")
                * 100
            )
            .otherwise(0.0)
            .cast(pl.Float64)
            .alias("_percentual_nao_comprovacao")
        )
    )

    return {
        row["_network_cnpj"]: {
            "percentual_nao_comprovacao": float(
                row["_percentual_nao_comprovacao"]
            ),
            "conexao_ms": "Ativa" if row["is_conexao_ativa"] else "Inativa",
        }
        for row in result.iter_rows(named=True)
    }


def _build_network_nodes(
    df_nodes: pl.DataFrame,
    data_inicio: Optional[date],
    data_fim: Optional[date],
    default_type: Optional[str] = None,
) -> list[NetworkNodeSchema]:
    rows = list(df_nodes.iter_rows(named=True))
    audit_context = _get_fp_audit_context_by_cnpj(rows, data_inicio, data_fim)

    for row in rows:
        node_type = (row.get("type") or default_type or "").upper()
        if node_type == "PJ_FARMACIA_POPULAR":
            cnpj = _normalize_document(row.get("id"))
            if cnpj not in audit_context:
                raise RuntimeError(
                    f"Contexto de auditoria nao calculado para a farmacia {cnpj}"
                )
            context = audit_context[cnpj]
            percentual = context["percentual_nao_comprovacao"]
            row["percentual_nao_comprovacao"] = percentual
            row["criticidade_nao_comprovacao"] = _classify_nao_comprovacao(
                percentual
            )
            row["conexao_ms"] = context["conexao_ms"]

    return [_build_network_node(row, default_type=default_type) for row in rows]


def _build_network_node(row: dict, default_type: Optional[str] = None) -> NetworkNodeSchema:
    node_type = row.get("type") or default_type or "PF"
    is_pf = _is_pf_node(node_type)
    percentual_nao_comprovacao = row.get("percentual_nao_comprovacao")
    criticidade_nao_comprovacao = row.get("criticidade_nao_comprovacao")
    conexao_ms = row.get("conexao_ms")
    if node_type == "PJ_FARMACIA_POPULAR" and percentual_nao_comprovacao is None:
        raise RuntimeError(
            f"No de Farmacia Popular {row.get('id')} sem percentual de nao comprovacao"
        )
    if node_type == "PJ_FARMACIA_POPULAR" and criticidade_nao_comprovacao is None:
        raise RuntimeError(
            f"No de Farmacia Popular {row.get('id')} sem criticidade de nao comprovacao"
        )
    if node_type == "PJ_FARMACIA_POPULAR" and conexao_ms not in {"Ativa", "Inativa"}:
        raise RuntimeError(
            f"No de Farmacia Popular {row.get('id')} sem conexao_ms valida"
        )

    return NetworkNodeSchema(
        id=row["id"],
        label=row["label"] or "",
        type=node_type,
        network_level=row.get("network_level"),
        percentual_nao_comprovacao=percentual_nao_comprovacao,
        criticidade_nao_comprovacao=criticidade_nao_comprovacao,
        conexao_ms=conexao_ms,
        razao_social=None if is_pf else row.get("razao_social"),
        nome_socio=row.get("nome_socio") if is_pf else None,
        nome_fantasia=row.get("nome_fantasia"),
        id_cnae_principal=row.get("id_cnae_principal"),
        cnae_principal=None if is_pf else row.get("cnae_principal"),
        cnaes_secundarios=[] if is_pf else row.get("cnaes_secundarios", []),
        municipio=row.get("municipio"),
        uf=row.get("uf"),
        situacao_rf=row.get("situacao_rf"),
        is_falecido=row.get("is_falecido", False),
        is_cadunico=row["is_cadunico"],
        is_esocial=row["is_esocial"],
        is_seguro_defeso=row["is_seguro_defeso"],
        is_cnae_farmacia_ausente=row["is_cnae_farmacia_ausente"],
        is_par=False if is_pf else row.get("is_par", False),
        qtd_processos_par=0 if is_pf else row.get("qtd_processos_par", 0),
        par_situacoes=None if is_pf else row.get("par_situacoes"),
        par_primeira_instauracao=None if is_pf else row.get("par_primeira_instauracao"),
        par_ultima_instauracao=None if is_pf else row.get("par_ultima_instauracao"),
        par_ultima_conclusao=None if is_pf else row.get("par_ultima_conclusao"),
    )


def _build_network_edge(row: dict) -> NetworkEdgeSchema:
    return NetworkEdgeSchema(
        id=row["id"],
        source=row["source"],
        target=row["target"],
        label=row["label"] or None,
        type=row.get("type") or "socio",
        network_level=row.get("network_level"),
        is_ativo=row.get("is_ativo") if row.get("is_ativo") is not None else True,
        data_entrada_sociedade=row.get("data_entrada_sociedade"),
        data_exclusao_sociedade=row.get("data_exclusao_sociedade"),
    )


def _read_parquet_or_empty(path: str) -> pl.DataFrame:
    if not os.path.exists(path):
        return pl.DataFrame()
    try:
        return pl.read_parquet(path)
    except Exception:
        return pl.DataFrame()


def _level_count(df: pl.DataFrame, level: str) -> int:
    if df.is_empty() or "network_level" not in df.columns:
        return 0
    return df.filter(pl.col("network_level") == level).height


def _build_network_summary(cnpj: str) -> NetworkSummarySchema:
    cnpj_dir = _get_cnpj_cache_dir(cnpj)
    node_frames = [
        _read_parquet_or_empty(os.path.join(cnpj_dir, TEIA_GRAFO_NIVEL2_NODES_PARQUET)),
        _read_parquet_or_empty(os.path.join(cnpj_dir, TEIA_GRAFO_NIVEL3_NODES_PARQUET)),
        _read_parquet_or_empty(os.path.join(cnpj_dir, TEIA_GRAFO_NIVEL4_NODES_PARQUET)),
    ]
    edge_frames = [
        _read_parquet_or_empty(os.path.join(cnpj_dir, TEIA_GRAFO_NIVEL2_EDGES_PARQUET)),
        _read_parquet_or_empty(os.path.join(cnpj_dir, TEIA_GRAFO_NIVEL3_EDGES_PARQUET)),
        _read_parquet_or_empty(os.path.join(cnpj_dir, TEIA_GRAFO_NIVEL4_EDGES_PARQUET)),
    ]

    levels = {
        level: NetworkLevelSummarySchema(
            label=label,
            entities=sum(_level_count(df, level) for df in node_frames),
            links=sum(_level_count(df, level) for df in edge_frames),
        )
        for level, label in NETWORK_LEVEL_LABELS.items()
    }

    node_ids = set()
    for df in node_frames:
        if not df.is_empty() and "id" in df.columns:
            node_ids.update(str(v) for v in df["id"].drop_nulls().to_list())

    edge_ids = set()
    for df in edge_frames:
        if not df.is_empty() and "id" in df.columns:
            edge_ids.update(str(v) for v in df["id"].drop_nulls().to_list())

    return NetworkSummarySchema(
        total_entities=len(node_ids),
        total_links=len(edge_ids),
        levels=levels,
    )


def get_teia_grafo_nivel2(
    cnpj: str,
    engine,
    data_inicio: Optional[date] = None,
    data_fim: Optional[date] = None,
) -> NetworkResponse:
    """
    Retorna a rede de relacionamentos societários de um CNPJ.

    Estratégia cache-first (padrão do projeto):
      1. Verifica se o cache de teia nivel 2 existe e e valido.
      2. Cache hit  → lê do Parquet e reconstrói NetworkResponse (rápido, offline-safe).
      3. Cache miss → chama sync_network() para buscar do banco e salvar Parquet,
                      depois lê o Parquet recém-gerado.
    """
    t0 = time.perf_counter()

    cnpj_dir    = _get_cnpj_cache_dir(cnpj)
    NODES_PATH  = os.path.join(cnpj_dir, TEIA_GRAFO_NIVEL2_NODES_PARQUET)
    EDGES_PATH  = os.path.join(cnpj_dir, TEIA_GRAFO_NIVEL2_EDGES_PARQUET)

    # ── Cache miss: gera o Parquet ────────────────────────────────────────────
    # Agora o sync_network gera 4 arquivos (nodes, edges + expansion_nodes, expansion_edges) sob o novo padrão teia_grafo_*
    sync_network(cnpj)

    # ── Lê do Parquet ─────────────────────────────────────────────────────────
    try:
        df_nodes = pl.read_parquet(NODES_PATH)
        df_edges = pl.read_parquet(EDGES_PATH) if os.path.exists(EDGES_PATH) else pl.DataFrame()
    except Exception as e:
        raise RuntimeError(f"Erro ao ler Parquet de teia para {cnpj}: {e}") from e

    # ── Reconstrói os schemas a partir dos DataFrames ─────────────────────────
    nodes = _build_network_nodes(df_nodes, data_inicio, data_fim)

    edges = [_build_network_edge(row) for row in df_edges.iter_rows(named=True)] if not df_edges.is_empty() else []

    return NetworkResponse(
        cnpj=cnpj,
        nodes=nodes,
        edges=edges,
        summary=_build_network_summary(cnpj),
        query_time_ms=round((time.perf_counter() - t0) * 1000, 1),
    )


def get_teia_grafo_nivel3_expansao(
    cnpj_alvo: str,
    cnpj_para_expandir: str,
    data_inicio: Optional[date] = None,
    data_fim: Optional[date] = None,
) -> NetworkResponse:
    """
    Carrega os dados de expansão (Nível 3) para um nó específico que já está na teia.
    Lê os arquivos de expansão pré-gerados na pasta de cache do CNPJ alvo.
    """
    t0 = time.perf_counter()
    cnpj_dir = _get_cnpj_cache_dir(cnpj_alvo)
    EXP_NODES_PATH = os.path.join(cnpj_dir, TEIA_GRAFO_NIVEL3_NODES_PARQUET)
    EXP_EDGES_PATH = os.path.join(cnpj_dir, TEIA_GRAFO_NIVEL3_EDGES_PARQUET)

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

        nodes = _build_network_nodes(
            df_exp_nodes,
            data_inicio,
            data_fim,
            default_type="PF",
        )

        edges = [_build_network_edge(row) for row in df_exp_edges.iter_rows(named=True)]

        return NetworkResponse(
            cnpj=cnpj_alvo, 
            nodes=nodes, 
            edges=edges,
            summary=_build_network_summary(cnpj_alvo),
            query_time_ms=round((time.perf_counter() - t0) * 1000, 1)
        )

    except Exception as e:
        raise RuntimeError(
            f"Erro ao expandir no {cnpj_para_expandir} na teia {cnpj_alvo}: {e}"
        ) from e


def get_teia_grafo_nivel4_expansao(
    cnpj_alvo: str,
    cpf_para_expandir: str,
    data_inicio: Optional[date] = None,
    data_fim: Optional[date] = None,
) -> NetworkResponse:
    """
    Carrega os dados de expansão (Nível 4) para um SÓCIO específico.
    Lê os arquivos de expansão N4 pré-gerados na pasta de cache do CNPJ alvo.
    """
    t0 = time.perf_counter()
    cnpj_dir = _get_cnpj_cache_dir(cnpj_alvo)
    N4_NODES_PATH = os.path.join(cnpj_dir, TEIA_GRAFO_NIVEL4_NODES_PARQUET)
    N4_EDGES_PATH = os.path.join(cnpj_dir, TEIA_GRAFO_NIVEL4_EDGES_PARQUET)

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

        nodes = _build_network_nodes(
            df_n4_nodes,
            data_inicio,
            data_fim,
            default_type="PJ",
        )

        edges = [_build_network_edge(row) for row in df_n4_edges.iter_rows(named=True)]

        return NetworkResponse(
            cnpj=cnpj_alvo, 
            nodes=nodes, 
            edges=edges,
            summary=_build_network_summary(cnpj_alvo),
            query_time_ms=round((time.perf_counter() - t0) * 1000, 1)
        )

    except Exception as e:
        raise RuntimeError(
            f"Erro ao expandir socio {cpf_para_expandir} na teia {cnpj_alvo}: {e}"
        ) from e

def get_teia_grafo_nivel3_full(
    cnpj_alvo: str,
    data_inicio: Optional[date] = None,
    data_fim: Optional[date] = None,
) -> NetworkResponse:
    """Retorna TODOS os sócios de nível 3 (Sócios de N2) em lote."""
    CACHE_DIR = _get_cnpj_cache_dir(cnpj_alvo)
    NODES_PATH = os.path.join(CACHE_DIR, TEIA_GRAFO_NIVEL3_NODES_PARQUET)
    EDGES_PATH = os.path.join(CACHE_DIR, TEIA_GRAFO_NIVEL3_EDGES_PARQUET)

    sync_network(cnpj_alvo)
    if not os.path.exists(NODES_PATH):
        return NetworkResponse(cnpj=cnpj_alvo, nodes=[], edges=[])

    try:
        df_nodes = pl.read_parquet(NODES_PATH)
        df_edges = pl.read_parquet(EDGES_PATH)

        nodes = _build_network_nodes(
            df_nodes,
            data_inicio,
            data_fim,
            default_type="PF",
        )
        
        edges = [_build_network_edge(row) for row in df_edges.iter_rows(named=True)]

        return NetworkResponse(cnpj=cnpj_alvo, nodes=nodes, edges=edges, summary=_build_network_summary(cnpj_alvo))
    except Exception as e:
        raise RuntimeError(f"Erro batch N3 na teia {cnpj_alvo}: {e}") from e

def get_teia_grafo_nivel4_full(
    cnpj_alvo: str,
    data_inicio: Optional[date] = None,
    data_fim: Optional[date] = None,
) -> NetworkResponse:
    """Retorna TODAS as empresas de nível 4 (Participações de N3) em lote."""
    CACHE_DIR = _get_cnpj_cache_dir(cnpj_alvo)
    NODES_PATH = os.path.join(CACHE_DIR, TEIA_GRAFO_NIVEL4_NODES_PARQUET)
    EDGES_PATH = os.path.join(CACHE_DIR, TEIA_GRAFO_NIVEL4_EDGES_PARQUET)

    sync_network(cnpj_alvo)
    if not os.path.exists(NODES_PATH):
        return NetworkResponse(cnpj=cnpj_alvo, nodes=[], edges=[])

    try:
        df_nodes = pl.read_parquet(NODES_PATH)
        df_edges = pl.read_parquet(EDGES_PATH)

        nodes = _build_network_nodes(
            df_nodes,
            data_inicio,
            data_fim,
            default_type="PJ",
        )
        
        edges = [_build_network_edge(row) for row in df_edges.iter_rows(named=True)]

        return NetworkResponse(cnpj=cnpj_alvo, nodes=nodes, edges=edges, summary=_build_network_summary(cnpj_alvo))
    except Exception as e:
        raise RuntimeError(f"Erro batch N4 na teia {cnpj_alvo}: {e}") from e
