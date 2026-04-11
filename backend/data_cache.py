import sys
import os
import pandas as pd
import polars as pl
from sqlalchemy import text

# --- LÓGICA DE CAMINHO PARA CACHE ---
# Se rodando via EXE (PyInstaller), sys.frozen é True
if getattr(sys, 'frozen', False):
    # Pasta onde o executável foi disparado
    BASE_DIR = os.path.dirname(sys.executable)
else:
    # Pasta raiz do projeto em desenvolvimento (um nível acima de /backend)
    BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

_CACHE_DIR = os.path.join(BASE_DIR, "sentinela_cache")
_PARQUET_PATH = os.path.join(_CACHE_DIR, "cache_movimentacao.parquet")
_LOCALIDADES_PARQUET_PATH = os.path.join(_CACHE_DIR, "cache_localidades.parquet")
_REDE_PARQUET_PATH = os.path.join(_CACHE_DIR, "cache_rede_estabelecimentos.parquet")
_MATRIZ_PARQUET_PATH = os.path.join(_CACHE_DIR, "cache_matriz_risco.parquet")
_FALECIDOS_PARQUET_PATH = os.path.join(_CACHE_DIR, "cache_falecidos.parquet")
_CRMS_DETALHADO_PARQUET_PATH = os.path.join(_CACHE_DIR, "cache_crms_detalhado.parquet")
_TOP20_CRMS_PARQUET_PATH = os.path.join(_CACHE_DIR, "cache_top20_crms.parquet")
_DADOS_FARMACIA_PARQUET_PATH = os.path.join(_CACHE_DIR, "cache_dados_farmacia.parquet")


if not os.path.exists(_CACHE_DIR):
    os.makedirs(_CACHE_DIR, exist_ok=True)

# Estados Globais
_df_movimentacao: pl.DataFrame | None = None
_df_localidades: pl.DataFrame | None = None
_df_rede: pl.DataFrame | None = None
_df_matriz_risco: pl.DataFrame | None = None
_df_falecidos: pl.DataFrame | None = None
_df_crms_detalhado: pl.DataFrame | None = None
_df_top20_crms: pl.DataFrame | None = None
_df_dados_farmacia: pl.DataFrame | None = None

_cache_progress: int = 0
_cache_status: str = "idle"

# --- MOTOR DE SINCRONIZAÇÃO (SYNC ENGINE) ---

def _sync_localidades(engine, progress_callback=None):
    """Tarefa 1: Sincroniza dados geográficos (IBGE)."""
    global _df_localidades
    print("Sincronizando Localidades (IBGE)...")
    sql = "SELECT sg_uf, no_regiao_saude, id_regiao_saude, no_municipio, id_ibge7, nu_populacao FROM [temp_CGUSC].[fp].[dados_ibge] ORDER BY sg_uf, no_regiao_saude, no_municipio"
    pdf = pd.read_sql(sql, engine)
    print(f"   -> Localidades carregadas: {len(pdf):,} registros.")
    if progress_callback: progress_callback(100)
    _df_localidades = pl.from_pandas(pdf).with_columns([
        pl.col("sg_uf").cast(pl.Categorical),
        pl.col("no_regiao_saude").cast(pl.Categorical),
        pl.col("no_municipio").cast(pl.Categorical),
    ])
    _df_localidades.write_parquet(_LOCALIDADES_PARQUET_PATH, compression="lz4")

def _sync_rede(engine, progress_callback=None):
    """Tarefa 2: Sincroniza a tabela de rede de estabelecimentos."""
    global _df_rede
    print("Sincronizando Rede de Estabelecimentos...")
    sql = "SELECT * FROM [temp_CGUSC].[fp].[rede_estabelecimentos]"
    
    pdf = pd.read_sql(sql, engine)
    print(f"   -> Rede carregada com sucesso: {len(pdf):,} registros.")
    if progress_callback: progress_callback(100)
    
    _df_rede = pl.from_pandas(pdf).with_columns([
        pl.col("cnpj_raiz").cast(pl.String),
        pl.col("cnpj").cast(pl.String),
        pl.col("razao_social").cast(pl.String),
        pl.col("uf").cast(pl.Categorical),
        pl.col("municipio").cast(pl.String),
        pl.col("is_matriz").cast(pl.Boolean),
        pl.col("qtd_estabelecimentos_rede").cast(pl.Int64),
        pl.col("flag_grandes_redes").cast(pl.Categorical),
    ])
    _df_rede.write_parquet(_REDE_PARQUET_PATH, compression="lz4")

def _sync_matriz_risco(engine, progress_callback=None):
    """Tarefa 4: Sincroniza a matriz de risco consolidada por CNPJ em chunks."""
    global _df_matriz_risco
    print("Sincronizando Matriz de Risco Consolidada (Matriz Resultados)...")
    sql = "SELECT * FROM [temp_CGUSC].[fp].[matriz_risco_consolidada]"
    
    with engine.connect() as conn:
        total_rows = conn.execute(text("SELECT COUNT(*) FROM [temp_CGUSC].[fp].[matriz_risco_consolidada]")).scalar()
    
    print(f"   -> Registros na Matriz: {total_rows:,}")
    chunk_list = []
    rows_processed = 0
    CHUNK_SIZE = 2_000
    
    for chunk in pd.read_sql(sql, engine, chunksize=CHUNK_SIZE):
        chunk_list.append(chunk)
        rows_processed += len(chunk)
        p = int((rows_processed / total_rows) * 100)
        print(f"   -> Progresso Matriz: {p}% ({rows_processed:,} / {total_rows:,})")
        if progress_callback:
            progress_callback(p)
            
    pdf = pd.concat(chunk_list, ignore_index=True) if chunk_list else pd.DataFrame()
    _df_matriz_risco = pl.from_pandas(pdf)
    _df_matriz_risco.write_parquet(_MATRIZ_PARQUET_PATH, compression="lz4")

def _sync_falecidos(engine, progress_callback=None):
    """Tarefa 5: Sincroniza a tabela de falecidos por farmácia em chunks."""
    global _df_falecidos
    print("Sincronizando Dados de Falecidos...")
    sql = "SELECT * FROM [temp_CGUSC].[fp].[falecidos_por_farmacia]"
    
    with engine.connect() as conn:
        total_rows = conn.execute(text("SELECT COUNT(*) FROM [temp_CGUSC].[fp].[falecidos_por_farmacia]")).scalar()
    
    print(f"   -> Registros Falecidos: {total_rows:,}")
    chunk_list = []
    rows_processed = 0
    CHUNK_SIZE = 2_000
    
    for chunk in pd.read_sql(sql, engine, chunksize=CHUNK_SIZE):
        chunk_list.append(chunk)
        rows_processed += len(chunk)
        p = int((rows_processed / total_rows) * 100)
        print(f"   -> Progresso Falecidos: {p}% ({rows_processed:,} / {total_rows:,})")
        if progress_callback:
            progress_callback(p)
            
    pdf = pd.concat(chunk_list, ignore_index=True) if chunk_list else pd.DataFrame()
    _df_falecidos = pl.from_pandas(pdf).with_columns([
        pl.col("dt_nascimento").cast(pl.Date, strict=False),
        pl.col("dt_obito").cast(pl.Date, strict=False),
        pl.col("data_autorizacao").cast(pl.Date, strict=False),
    ])
    _df_falecidos.write_parquet(_FALECIDOS_PARQUET_PATH, compression="lz4")

def _sync_crms_detalhado(engine, progress_callback=None):
    """Tarefa 6: Sincroniza indicadores detalhados de CRMs."""
    global _df_crms_detalhado
    print("Sincronizando Indicadores CRMs...")
    sql = "SELECT * FROM [temp_CGUSC].[fp].[indicador_crm_detalhado]"
    with engine.connect() as conn:
        total_rows = conn.execute(text("SELECT COUNT(*) FROM [temp_CGUSC].[fp].[indicador_crm_detalhado]")).scalar()
    print(f"   -> Registros CRMs Detalhado: {total_rows:,}")
    chunk_list = []
    rows_processed = 0
    CHUNK_SIZE = 5_000
    for chunk in pd.read_sql(sql, engine, chunksize=CHUNK_SIZE):
        chunk_list.append(chunk)
        rows_processed += len(chunk)
        p = int((rows_processed / total_rows) * 100)
        print(f"   -> Progresso CRMs Detalhado: {p}% ({rows_processed:,} / {total_rows:,})")
        if progress_callback: progress_callback(p)
    pdf = pd.concat(chunk_list, ignore_index=True) if chunk_list else pd.DataFrame()
    _df_crms_detalhado = pl.from_pandas(pdf)
    _df_crms_detalhado.write_parquet(_CRMS_DETALHADO_PARQUET_PATH, compression="lz4")

def _sync_top20_crms(engine, progress_callback=None):
    """Tarefa 7: Sincroniza top 20 CRMs."""
    global _df_top20_crms
    print("Sincronizando Top 20 CRMs...")
    sql = "SELECT * FROM [temp_CGUSC].[fp].[top_20_crms_farmacia]"
    with engine.connect() as conn:
        total_rows = conn.execute(text("SELECT COUNT(*) FROM [temp_CGUSC].[fp].[top_20_crms_farmacia]")).scalar()
    print(f"   -> Registros Top 20 CRMs: {total_rows:,}")
    chunk_list = []
    rows_processed = 0
    CHUNK_SIZE = 10_000
    for chunk in pd.read_sql(sql, engine, chunksize=CHUNK_SIZE):
        chunk_list.append(chunk)
        rows_processed += len(chunk)
        p = int((rows_processed / total_rows) * 100)
        print(f"   -> Progresso Top 20 CRMs: {p}% ({rows_processed:,} / {total_rows:,})")
        if progress_callback: progress_callback(p)
    pdf = pd.concat(chunk_list, ignore_index=True) if chunk_list else pd.DataFrame()
    _df_top20_crms = pl.from_pandas(pdf).with_columns([
        pl.col("dt_primeira_prescricao").cast(pl.Date, strict=False),
        pl.col("dt_inscricao_crm").cast(pl.Date, strict=False)
    ]) if not pdf.empty else pl.from_pandas(pdf)
    _df_top20_crms.write_parquet(_TOP20_CRMS_PARQUET_PATH, compression="lz4")

def _sync_dados_farmacia(engine, progress_callback=None):
    """Tarefa 8: Sincroniza dados cadastrais e geográficos das farmácias."""
    global _df_dados_farmacia
    print("Sincronizando Dados Cadastrais das Farmácias...")
    sql = """
        SELECT cnpj,
               razaoSocial as razao_social,
               nomeFantasia as nome_fantasia,
               tipoLogradouro as tipo_logradouro,
               logradouro, numero, complemento, bairro, cep,
               latitude, longitude,
               codibge as id_ibge7
        FROM [temp_CGUSC].[fp].[dados_farmacia]
    """
    with engine.connect() as conn:
        total_rows = conn.execute(text("SELECT COUNT(*) FROM [temp_CGUSC].[fp].[dados_farmacia]")).scalar()
    
    print(f"   -> Registros Cadastrais: {total_rows:,}")
    chunk_list = []
    rows_processed = 0
    CHUNK_SIZE = 5_000

    for chunk in pd.read_sql(sql, engine, chunksize=CHUNK_SIZE):
        chunk_list.append(chunk)
        rows_processed += len(chunk)
        p = int((rows_processed / total_rows) * 100) if total_rows > 0 else 100
        print(f"   -> Progresso Dados Farmácias: {p}% ({rows_processed:,} / {total_rows:,})")
        if progress_callback: progress_callback(p)

    pdf = pd.concat(chunk_list, ignore_index=True) if chunk_list else pd.DataFrame()
    _df_dados_farmacia = pl.from_pandas(pdf)
    _df_dados_farmacia.write_parquet(_DADOS_FARMACIA_PARQUET_PATH, compression="lz4")


def _sync_movimentacao(engine, progress_callback):
    """Tarefa 2: Sincroniza a movimentação mensal (Tabela Grande)."""
    global _df_movimentacao
    with engine.connect() as conn:
        total_rows = conn.execute(text("SELECT COUNT(*) FROM [temp_CGUSC].[fp].[movimentacao_mensal_cnpj]")).scalar()
    
    sql = """
        SELECT M.cnpj, M.uf, M.no_regiao_saude, M.no_municipio, M.periodo,
               CAST(M.total_vendas AS FLOAT) AS total_vendas,
               CAST(M.total_sem_comprovacao AS FLOAT) AS total_sem_comprovacao,
               CAST(M.total_qnt_vendas AS FLOAT) AS total_qnt_vendas,
               CAST(M.total_qnt_sem_comprovacao AS FLOAT) AS total_qnt_sem_comprovacao,
               P.razao_social,
               P.situacao_rf,
               P.is_conexao_ativa,
               P.porte_empresa,
               P.is_grande_rede,
               P.qtd_estabelecimentos_rede,
               P.is_matriz
        FROM [temp_CGUSC].[fp].[movimentacao_mensal_cnpj] M
        LEFT JOIN [temp_CGUSC].[fp].[perfil_consolidado_estabelecimento] P ON P.cnpj = M.cnpj
    """
    
    chunk_list = []
    rows_processed = 0
    CHUNK_SIZE = 250_000
    
    print(f"Total de registros a baixar: {total_rows:,}")
    
    for chunk in pd.read_sql(sql, engine, chunksize=CHUNK_SIZE):
        chunk_list.append(chunk)
        rows_processed += len(chunk)
        p = int((rows_processed / total_rows) * 100)
        print(f"   -> Progresso Movimentação: {p}% ({rows_processed:,} / {total_rows:,})")
        progress_callback(p)

    print("   -> Organizando e otimizando dados (Polars)...")
    pdf = pd.concat(chunk_list, ignore_index=True)
    _df_movimentacao = pl.from_pandas(pdf).with_columns([
        pl.col("periodo").cast(pl.Date),
        pl.col("uf").cast(pl.Categorical),
        pl.col("no_regiao_saude").cast(pl.Categorical),
        pl.col("no_municipio").cast(pl.Categorical),
        pl.col("total_vendas").cast(pl.Float64),
        pl.col("total_sem_comprovacao").cast(pl.Float64),
        pl.col("total_qnt_vendas").cast(pl.Float64),
        pl.col("total_qnt_sem_comprovacao").cast(pl.Float64),
        pl.col("razao_social").cast(pl.String),
        pl.col("situacao_rf").cast(pl.Categorical),
        pl.col("is_conexao_ativa").cast(pl.Boolean),
        pl.col("porte_empresa").cast(pl.Categorical),
        pl.col("is_grande_rede").cast(pl.Boolean),
        pl.col("is_matriz").cast(pl.Boolean),
        pl.col("qtd_estabelecimentos_rede").cast(pl.Int64),
    ])
    _df_movimentacao.write_parquet(_PARQUET_PATH, compression="lz4")

# --- GERENCIADOR DE CACHE ---

def load_cache(engine, force_refresh: bool = False) -> None:
    global _df_movimentacao, _df_localidades, _df_rede, _df_matriz_risco, _df_falecidos, _df_crms_detalhado, _df_top20_crms, _df_dados_farmacia, _cache_progress, _cache_status
    import time

    # 1. Boot Rápido (Se os arquivos já existem)
    if not force_refresh:
        try:
            all_exist = (
                os.path.exists(_PARQUET_PATH) and
                os.path.exists(_LOCALIDADES_PARQUET_PATH) and
                os.path.exists(_REDE_PARQUET_PATH) and
                os.path.exists(_MATRIZ_PARQUET_PATH) and
                os.path.exists(_FALECIDOS_PARQUET_PATH) and
                os.path.exists(_CRMS_DETALHADO_PARQUET_PATH) and
                os.path.exists(_TOP20_CRMS_PARQUET_PATH) and
                os.path.exists(_DADOS_FARMACIA_PARQUET_PATH)
            )
            if all_exist:
                _cache_status = "loading_parquet"
                _df_movimentacao   = pl.read_parquet(_PARQUET_PATH)
                _df_localidades    = pl.read_parquet(_LOCALIDADES_PARQUET_PATH)
                _df_rede           = pl.read_parquet(_REDE_PARQUET_PATH)
                _df_matriz_risco   = pl.read_parquet(_MATRIZ_PARQUET_PATH)
                _df_falecidos      = pl.read_parquet(_FALECIDOS_PARQUET_PATH)
                _df_crms_detalhado = pl.read_parquet(_CRMS_DETALHADO_PARQUET_PATH)
                _df_top20_crms     = pl.read_parquet(_TOP20_CRMS_PARQUET_PATH)
                _df_dados_farmacia = pl.read_parquet(_DADOS_FARMACIA_PARQUET_PATH)
                _cache_progress = 100
                _cache_status = "ready"
                print("🚀 Caches carregados via Parquet.")
                return
        except Exception as e:
            print(f"⚠️ Erro ao carregar Parquets: {e}")

    if not force_refresh:
        _cache_status = "idle"
        _cache_progress = 0
        return

    # 2. Sincronização Inteligente (Task-Based) com Pesos Ponderados
    # Definimos pesos baseados no tempo estimado de execução (total = 100)
    TASKS = [
        {"name": "Localidades",           "weight": 2,  "func": lambda cb: _sync_localidades(engine, cb)},
        {"name": "Rede Estabelecimentos", "weight": 3,  "func": lambda cb: _sync_rede(engine, cb)},
        {"name": "Matriz de Risco",       "weight": 11, "func": lambda cb: _sync_matriz_risco(engine, cb)},
        {"name": "Falecidos",             "weight": 5,  "func": lambda cb: _sync_falecidos(engine, cb)},
        {"name": "CRMs Detalhado",        "weight": 5,  "func": lambda cb: _sync_crms_detalhado(engine, cb)},
        {"name": "CRMs de Interesse",      "weight": 46, "func": lambda cb: _sync_top20_crms(engine, cb)},
        {"name": "Dados das Farmácias",   "weight": 5,  "func": lambda cb: _sync_dados_farmacia(engine, cb)},
        {"name": "Movimentação",          "weight": 23, "func": lambda cb: _sync_movimentacao(engine, cb)},
    ]

    t0 = time.perf_counter()
    total_tasks = len(TASKS)
    acumulado_weight = 0

    try:
        for index, task in enumerate(TASKS):
            _cache_status = task["name"]
            current_weight = task["weight"]
            print(f"[{index+1}/{total_tasks}] {task['name']}...")

            def update_global_progress(task_internal_p, _base=acumulado_weight, _w=current_weight):
                global _cache_progress
                _cache_progress = int(_base + (task_internal_p / 100 * _w))

            task["func"](update_global_progress)
            acumulado_weight += current_weight

        _cache_progress = 100
        _cache_status = "ready"
        print(f"🚀 Sincronização concluída em {time.perf_counter() - t0:.1f}s")

    except Exception as e:
        _cache_status = "error"
        _cache_progress = 0
        import traceback
        print(f"❌ Erro Crítico na Sincronização: {e}")
        print(traceback.format_exc())
        raise e

def refresh_cache(engine) -> None:
    """Força re-leitura do SQL e regera os Parquets."""
    load_cache(engine, force_refresh=True)

def get_df() -> pl.DataFrame:
    if _df_movimentacao is None: 
        raise RuntimeError("Cache de Movimentação não carregado. Verifique a sincronização.")
    return _df_movimentacao

def get_rede_df() -> pl.DataFrame:
    if _df_rede is None:
        raise RuntimeError("Cache de Rede de Estabelecimentos não carregado. Verifique a sincronização.")
    return _df_rede

def get_localidades_df() -> pl.DataFrame:
    if _df_localidades is None:
        raise RuntimeError("Cache de Localidades não carregado. Verifique a sincronização.")
    return _df_localidades

def get_df_matriz_risco() -> pl.DataFrame:
    if _df_matriz_risco is None:
        raise RuntimeError("Cache de Matriz de Risco não carregado. Execute uma sincronização.")
    return _df_matriz_risco

def get_df_falecidos() -> pl.DataFrame:
    if _df_falecidos is None:
        raise RuntimeError("Cache de Falecidos não carregado. Execute uma sincronização.")
    return _df_falecidos

def get_df_crms_detalhado() -> pl.DataFrame:
    if _df_crms_detalhado is None:
        raise RuntimeError("Cache de CRMs Detalhado não carregado. Execute uma sincronização.")
    return _df_crms_detalhado

def get_df_top20_crms() -> pl.DataFrame:
    if _df_top20_crms is None:
        raise RuntimeError("Cache de Top 20 CRMs não carregado. Execute uma sincronização.")
    return _df_top20_crms

def get_df_dados_farmacia() -> pl.DataFrame:
    if _df_dados_farmacia is None:
        raise RuntimeError("Cache de Dados das Farmácias não carregado. Execute uma sincronização.")
    return _df_dados_farmacia

def get_cache_status() -> dict:
    """Retorna o estado atual da sincronização para o frontend."""
    return {
        "progress": _cache_progress,
        "status": _cache_status,
        "is_ready": (
            _df_movimentacao is not None and 
            _df_localidades is not None and 
            _df_rede is not None and
            _df_matriz_risco is not None and
            _df_falecidos is not None and
            _df_crms_detalhado is not None and
            _df_top20_crms is not None and
            _df_dados_farmacia is not None
        )
    }
