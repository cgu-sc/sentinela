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

def get_cache_dir() -> str:
    """Retorna o diretório de cache, priorizando o local onde os dados realmente existem."""
    # Opção 1: Raiz do projeto (Padrão)
    path_root = os.path.join(BASE_DIR, "sentinela_cache")
    # Opção 2: Dentro da pasta backend (Caso de desenvolvimento específico)
    path_backend = os.path.join(BASE_DIR, "backend", "sentinela_cache")
    
    if not os.path.exists(path_root) and os.path.exists(path_backend):
        return path_backend
    return path_root

_CACHE_DIR = get_cache_dir()
_PARQUET_PATH = os.path.join(_CACHE_DIR, "movimentacao.parquet")
_LOCALIDADES_PARQUET_PATH = os.path.join(_CACHE_DIR, "localidades.parquet")
_REDE_PARQUET_PATH = os.path.join(_CACHE_DIR, "redes_farmaceuticas.parquet")
_MATRIZ_PARQUET_PATH = os.path.join(_CACHE_DIR, "matriz_risco.parquet")
_FALECIDOS_PARQUET_PATH = os.path.join(_CACHE_DIR, "falecidos.parquet")
_BENCH_CRM_UF_PATH     = os.path.join(_CACHE_DIR, "benchmarks", "bench_crm_uf.parquet")
_BENCH_CRM_REGIAO_PATH = os.path.join(_CACHE_DIR, "benchmarks", "bench_crm_regiao.parquet")
_BENCH_CRM_BR_PATH     = os.path.join(_CACHE_DIR, "benchmarks", "bench_crm_br.parquet")
_DADOS_FARMACIA_PARQUET_PATH = os.path.join(_CACHE_DIR, "farmacias.parquet")
_MEDICAMENTOS_PARQUET_PATH = os.path.join(_CACHE_DIR, "medicamentos.parquet")

if not os.path.exists(_CACHE_DIR):
    os.makedirs(_CACHE_DIR, exist_ok=True)

# Estados Globais
_df_movimentacao: pl.DataFrame | None = None
_df_localidades: pl.DataFrame | None = None
_df_rede: pl.DataFrame | None = None
_df_matriz_risco: pl.DataFrame | None = None
_df_falecidos: pl.DataFrame | None = None
_df_bench_crm_uf: pl.DataFrame | None = None
_df_bench_crm_regiao: pl.DataFrame | None = None
_df_bench_crm_br: pl.DataFrame | None = None
_df_dados_farmacia: pl.DataFrame | None = None
_df_medicamentos: pl.DataFrame | None = None

_cache_progress: int = 0
_cache_status: str = "idle"
_cache_error_message: str = ""

# --- MOTOR DE SINCRONIZAÇÃO (SYNC ENGINE) ---

def _sync_localidades(engine, progress_callback=None):
    """Tarefa 1: Sincroniza dados geográficos (IBGE)."""
    global _df_localidades
    print("Sincronizando Localidades (IBGE)...")
    sql = """
        SELECT I.sg_uf, I.no_regiao_saude, I.id_regiao_saude, I.no_municipio, I.id_ibge7, I.nu_populacao,
               J.unidade_pf
        FROM [temp_CGUSC].[fp].[dados_ibge] I
        LEFT JOIN (
            SELECT codIBGE, MIN(nome_unidade_PF) as unidade_pf 
            FROM [temp_CGUSC].[fp].[jurisdicoes_pf] 
            GROUP BY codIBGE
        ) J ON J.codIBGE = I.id_ibge7
        ORDER BY I.sg_uf, I.no_regiao_saude, I.no_municipio
    """
    pdf = pd.read_sql(sql, engine)
    print(f"   -> Localidades carregadas: {len(pdf):,} registros.")
    if progress_callback: progress_callback(100)
    _df_localidades = pl.from_pandas(pdf).with_columns([
        pl.col("sg_uf").cast(pl.Categorical),
        pl.col("no_regiao_saude").cast(pl.Categorical),
        pl.col("no_municipio").cast(pl.Categorical),
        pl.col("unidade_pf").cast(pl.Categorical),
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
        pl.col("is_grande_rede").cast(pl.Boolean),
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


def _sync_dados_farmacia(engine, progress_callback=None):
    """Tarefa 8: Sincroniza dados cadastrais e geográficos das farmácias."""
    global _df_dados_farmacia
    print("Sincronizando Dados Cadastrais das Farmácias...")
    sql = """
        SELECT D.cnpj,
               D.razaoSocial as razao_social,
               D.nomeFantasia as nome_fantasia,
               D.tipoLogradouro as tipo_logradouro,
               D.logradouro, D.numero, D.complemento, D.bairro, D.cep,
               D.latitude, D.longitude,
               D.codibge as id_ibge7,
               I.sg_uf as uf,
               I.no_municipio as municipio,
               CAST(ISNULL(R.total_mov, 0) AS FLOAT) as total_mov,
               CAST(ISNULL(R.val_sem_comp, 0) AS FLOAT) as val_sem_comp,
               CAST(CASE WHEN ISNULL(R.total_mov, 0) > 0 
                         THEN LEAST((ISNULL(R.val_sem_comp, 0) / R.total_mov) * 100, 100)
                         ELSE 0 END AS FLOAT) as perc_val_sem_comp,
               CAST(ISNULL(M.score_risco_final, 0) AS FLOAT) as score_risco_final,
               ISNULL(M.classificacao_risco, 'N/A') as classificacao_risco
        FROM [temp_CGUSC].[fp].[dados_farmacia] D
        LEFT JOIN [temp_CGUSC].[fp].[dados_ibge] I ON I.id_ibge7 = D.codibge
        LEFT JOIN (
            SELECT cnpj, 
                   SUM(total_vendas) as total_mov, 
                   SUM(total_sem_comprovacao) as val_sem_comp
            FROM [temp_CGUSC].[fp].[movimentacao_mensal_cnpj]
            GROUP BY cnpj
        ) R ON R.cnpj = D.cnpj
        LEFT JOIN [temp_CGUSC].[fp].[matriz_risco_consolidada] M ON M.cnpj = D.cnpj
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


def _sync_medicamentos(engine, progress_callback=None):
    """Tarefa 9: Sincroniza a tabela mestra de medicamentos e patologias."""
    global _df_medicamentos
    print("Sincronizando Cadastro de Medicamentos (Dicionário GTIN)...")
    sql = "SELECT codigo_barra, principio_ativo, produto, descricao, laboratorio, Patologia as patologia FROM [temp_CGUSC].[fp].[medicamentos_patologia]"
    
    pdf = pd.read_sql(sql, engine)
    print(f"   -> Cadastro carregado: {len(pdf):,} medicamentos.")
    if progress_callback: progress_callback(100)
    
    _df_medicamentos = pl.from_pandas(pdf).with_columns([
        pl.col("codigo_barra").cast(pl.String),
        pl.col("principio_ativo").cast(pl.Categorical),
        pl.col("produto").cast(pl.Categorical),
        pl.col("laboratorio").cast(pl.Categorical),
        pl.col("patologia").cast(pl.Categorical),
    ])
    _df_medicamentos.write_parquet(_MEDICAMENTOS_PARQUET_PATH, compression="lz4")


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
               P.is_matriz,
               P.unidade_pf
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
        pl.col("unidade_pf").cast(pl.Categorical),
    ])
    _df_movimentacao.write_parquet(_PARQUET_PATH, compression="lz4")

def _sync_crm_benchmarks(engine, progress_callback=None):
    """Tarefa: Gera bench_uf, bench_regiao e bench_br como parquets."""
    import importlib, sys as _sys
    # exportar_crms está no mesmo diretório (backend/)
    if "exportar_crms" not in _sys.modules:
        importlib.import_module("exportar_crms")
    from exportar_crms import exportar_benchmarks
    exportar_benchmarks()
    if progress_callback:
        progress_callback(100)


def _sync_crm_parquets(engine, progress_callback=None, cnpjs: list[str] | None = None):
    """Tarefa: Gera todos os parquets (médicos, diário, horário, alertas) para os CNPJs selecionados."""
    from api.services.analytics import AnalyticsService
    
    # Se não informar CNPJs, busca os que já processaram o índice de risco (ativos)
    if not cnpjs:
        try:
            with engine.connect() as conn:
                res = conn.execute(text("SELECT DISTINCT cnpj FROM temp_CGUSC.fp.matriz_risco_consolidada"))
                cnpjs = [r[0] for r in res]
        except Exception as e:
            print(f"❌ Erro ao buscar lista de CNPJs: {e}")
            return

    total = len(cnpjs)
    print(f"Sincronizando parquets de CRMs para {total} estabelecimento(s)...")

    for i, cnpj in enumerate(cnpjs, 1):
        try:
            # 1. Lista de Médicos e Alertas Sequenciais (Gera 3 parquets: _prescritores, _alertas_diarios, _cnpj_alerts)
            AnalyticsService.get_crm_data(cnpj)
            
            # 2. Histórico Diário (Gera _daily.parquet)
            AnalyticsService.get_crm_daily_profile(cnpj)
            
            # 3. Detalhamento Horário de Anomalias (Gera _hourly.parquet)
            AnalyticsService.get_crm_hourly_profile(cnpj)

            # 4. Transações Literais (Raio-X) (Gera _hourly_tx.parquet)
            AnalyticsService.sync_crm_hourly_transactions(cnpj)

            if progress_callback:
                p = int((i / total) * 100)
                progress_callback(p)
        except Exception as e:
            print(f"\n⚠️  Erro ao sincronizar CNPJ {cnpj}: {e}")

    if progress_callback:
        progress_callback(100)


# --- GERENCIADOR DE CACHE ---

def load_cache(engine, force_refresh: bool = False) -> None:
    global _df_movimentacao, _df_localidades, _df_rede, _df_matriz_risco, _df_falecidos, _df_bench_crm_uf, _df_bench_crm_regiao, _df_bench_crm_br, _df_dados_farmacia, _cache_progress, _cache_status, _cache_error_message
    import time

    # 1. Boot Rápido (carrega cada Parquet individualmente)
    if not force_refresh:
        _cache_status = "loading_parquet"
        missing = []

        def _try_load(name, path):
            if not os.path.exists(path):
                missing.append(name)
                return None
            try:
                return pl.read_parquet(path)
            except Exception as e:
                print(f"⚠️  Erro ao ler parquet '{name}': {e}")
                missing.append(name)
                return None

        _df_movimentacao    = _try_load("movimentacao",    _PARQUET_PATH)
        _df_localidades     = _try_load("localidades",     _LOCALIDADES_PARQUET_PATH)
        _df_rede            = _try_load("rede",            _REDE_PARQUET_PATH)
        _df_matriz_risco    = _try_load("matriz_risco",    _MATRIZ_PARQUET_PATH)
        _df_falecidos       = _try_load("falecidos",       _FALECIDOS_PARQUET_PATH)
        _df_bench_crm_uf    = _try_load("bench_crm_uf",   _BENCH_CRM_UF_PATH)
        _df_bench_crm_regiao= _try_load("bench_crm_regiao", _BENCH_CRM_REGIAO_PATH)
        _df_bench_crm_br    = _try_load("bench_crm_br",   _BENCH_CRM_BR_PATH)
        _df_dados_farmacia  = _try_load("dados_farmacia",  _DADOS_FARMACIA_PARQUET_PATH)
        _df_medicamentos    = _try_load("medicamentos",    _MEDICAMENTOS_PARQUET_PATH)

        if missing:
            print(f"⚠️  Cache incompleto — módulos ausentes: {', '.join(missing)}")
            print("ℹ️  Sistema iniciado em modo degradado. Sincronize pela interface para carregar os dados.")
            _cache_status = "idle"
            _cache_progress = 0
        else:
            _cache_progress = 100
            _cache_status = "ready"
            print(f"🚀 Caches carregados via Parquet.")
        return

    # 2. Sincronização Inteligente (Task-Based) com Pesos Ponderados
    # Definimos pesos baseados no tempo estimado de execução (total = 100)
    TASKS = [
        {"name": "Localidades",           "weight": 2,  "func": lambda cb: _sync_localidades(engine, cb)},
        {"name": "Rede Estabelecimentos", "weight": 3,  "func": lambda cb: _sync_rede(engine, cb)},
        {"name": "Matriz de Risco",       "weight": 11, "func": lambda cb: _sync_matriz_risco(engine, cb)},
        {"name": "Falecidos",             "weight": 5,  "func": lambda cb: _sync_falecidos(engine, cb)},
        {"name": "Benchmarks CRM",        "weight": 3,  "func": lambda cb: _sync_crm_benchmarks(engine, cb)},
        {"name": "Dados das Farmácias",   "weight": 5,  "func": lambda cb: _sync_dados_farmacia(engine, cb)},
        {"name": "Cadastro Medicamentos", "weight": 5,  "func": lambda cb: _sync_medicamentos(engine, cb)},
        {"name": "Movimentação",          "weight": 66, "func": lambda cb: _sync_movimentacao(engine, cb)},
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
        _cache_error_message = str(e)
        import traceback
        print(f"❌ Erro Crítico na Sincronização: {e}")
        print(traceback.format_exc())

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

def get_df_bench_crm_uf() -> pl.DataFrame:
    if _df_bench_crm_uf is None:
        raise RuntimeError("Cache de Benchmark CRM (UF) não carregado. Execute uma sincronização.")
    return _df_bench_crm_uf

def get_df_bench_crm_regiao() -> pl.DataFrame:
    if _df_bench_crm_regiao is None:
        raise RuntimeError("Cache de Benchmark CRM (Região) não carregado. Execute uma sincronização.")
    return _df_bench_crm_regiao

def get_df_bench_crm_br() -> pl.DataFrame:
    if _df_bench_crm_br is None:
        raise RuntimeError("Cache de Benchmark CRM (Brasil) não carregado. Execute uma sincronização.")
    return _df_bench_crm_br

def get_df_dados_farmacia() -> pl.DataFrame:
    if _df_dados_farmacia is None:
        raise RuntimeError("Cache de Dados das Farmácias não carregado. Execute uma sincronização.")
    return _df_dados_farmacia

def get_medicamentos_df() -> pl.DataFrame:
    global _df_medicamentos
    if _df_medicamentos is None:
        # Se não carregado, tentamos ler do parquet direto se existir
        if os.path.exists(_MEDICAMENTOS_PARQUET_PATH):
            _df_medicamentos = pl.read_parquet(_MEDICAMENTOS_PARQUET_PATH)
            return _df_medicamentos
        raise RuntimeError("Cache de Medicamentos não carregado. Execute uma sincronização.")
    return _df_medicamentos

def get_cache_status() -> dict:
    """Retorna o estado atual da sincronização para o frontend."""
    modules = {
        "movimentacao":   {"label": "Movimentação Mensal",     "path": _PARQUET_PATH,             "loaded": _df_movimentacao is not None},
        "localidades":    {"label": "Localidades (IBGE)",      "path": _LOCALIDADES_PARQUET_PATH, "loaded": _df_localidades is not None},
        "rede":           {"label": "Rede de Estabelecimentos","path": _REDE_PARQUET_PATH,        "loaded": _df_rede is not None},
        "matriz_risco":   {"label": "Matriz de Risco",         "path": _MATRIZ_PARQUET_PATH,      "loaded": _df_matriz_risco is not None},
        "falecidos":      {"label": "Falecidos por Farmácia",  "path": _FALECIDOS_PARQUET_PATH,   "loaded": _df_falecidos is not None},
        "bench_crm_uf":    {"label": "Benchmark CRM (UF)",      "path": _BENCH_CRM_UF_PATH,        "loaded": _df_bench_crm_uf is not None},
        "bench_crm_regiao":{"label": "Benchmark CRM (Região)", "path": _BENCH_CRM_REGIAO_PATH,    "loaded": _df_bench_crm_regiao is not None},
        "bench_crm_br":    {"label": "Benchmark CRM (Brasil)", "path": _BENCH_CRM_BR_PATH,        "loaded": _df_bench_crm_br is not None},
        "dados_farmacia": {"label": "Dados das Farmácias",     "path": _DADOS_FARMACIA_PARQUET_PATH, "loaded": _df_dados_farmacia is not None},
        "medicamentos":   {"label": "Cadastro Medicamentos",   "path": _MEDICAMENTOS_PARQUET_PATH,   "loaded": _df_medicamentos is not None},
    }
    modules_status = {
        key: {"label": v["label"], "exists": os.path.exists(v["path"]), "loaded": v["loaded"]}
        for key, v in modules.items()
    }
    is_ready = all(v["loaded"] for v in modules_status.values())
    return {
        "progress": _cache_progress,
        "status": _cache_status,
        "is_ready": is_ready,
        "error_message": _cache_error_message if _cache_status == "error" else "",
        "modules": modules_status,
    }
