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
_BENCH_CRM_UF_PATH     = os.path.join(_CACHE_DIR, "bench_crm_uf.parquet")
_BENCH_CRM_REGIAO_PATH = os.path.join(_CACHE_DIR, "bench_crm_regiao.parquet")
_BENCH_CRM_BR_PATH     = os.path.join(_CACHE_DIR, "bench_crm_br.parquet")
_DADOS_FARMACIA_PARQUET_PATH = os.path.join(_CACHE_DIR, "farmacias.parquet")
_DADOS_SOCIOS_PARQUET_PATH   = os.path.join(_CACHE_DIR, "socios.parquet")
_TEIA_FONTE_NIVEL2_PARQUET_PATH = os.path.join(_CACHE_DIR, "teia_fonte_nivel2.parquet")
_TEIA_FONTE_NIVEL3_PARQUET_PATH = os.path.join(_CACHE_DIR, "teia_fonte_nivel3.parquet")
_TEIA_FONTE_NIVEL4_PARQUET_PATH = os.path.join(_CACHE_DIR, "teia_fonte_nivel4.parquet")
_MEDICAMENTOS_PARQUET_PATH   = os.path.join(_CACHE_DIR, "medicamentos.parquet")

if not os.path.exists(_CACHE_DIR):
    os.makedirs(_CACHE_DIR, exist_ok=True)

# Estados Globais
_df_movimentacao: pl.DataFrame | None = None
_df_localidades: pl.DataFrame | None = None
_df_rede: pl.DataFrame | None = None
_df_matriz_risco: pl.DataFrame | None = None
_df_bench_crm_uf: pl.DataFrame | None = None
_df_bench_crm_regiao: pl.DataFrame | None = None
_df_bench_crm_br: pl.DataFrame | None = None
_df_dados_farmacia: pl.DataFrame | None = None
_df_dados_socios:   pl.DataFrame | None = None
_df_teia_fonte_nivel2: pl.DataFrame | None = None
_df_teia_fonte_nivel3: pl.DataFrame | None = None
_df_teia_fonte_nivel4: pl.DataFrame | None = None
_df_medicamentos:   pl.DataFrame | None = None

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
        WHERE I.sg_uf <> 'BR'
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
    _df_localidades.write_parquet(_LOCALIDADES_PARQUET_PATH, compression="zstd")

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
    ]).sort(["cnpj_raiz", "cnpj"])
    _df_rede.write_parquet(_REDE_PARQUET_PATH, compression="zstd")

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
        chunk_list.append(pl.from_pandas(chunk))
        rows_processed += len(chunk)
        p = int((rows_processed / total_rows) * 100) if total_rows > 0 else 100
        print(f"   -> Progresso Matriz: {p}% ({rows_processed:,} / {total_rows:,})")
        if progress_callback: progress_callback(p)
            
    _df_matriz_risco = pl.concat(chunk_list).sort("cnpj")
    _df_matriz_risco.write_parquet(_MATRIZ_PARQUET_PATH, compression="zstd")

def _sync_dados_farmacia(engine, progress_callback=None):
    """Tarefa 8: Sincroniza dados cadastrais e geográficos das farmácias."""
    global _df_dados_farmacia
    print("Sincronizando Dados Cadastrais das Farmácias...")
    sql = """
        SELECT D.cnpj,
               D.indMatriz as is_matriz,
               D.razaoSocial as razao_social,
               D.nomeFantasia as nome_fantasia,
               D.tipoLogradouro as tipo_logradouro,
               D.logradouro as logradouro, 
               D.numero as numero, 
               D.complemento as complemento, 
               D.bairro as bairro, 
               D.cep as cep,
               D.latitude as latitude, 
               D.longitude as longitude,
               D.codibge as id_ibge7,
               D.id_cnae_principal as id_cnae_principal, 
               D.cnae_principal as cnae_principal,
               D.id_cnae_secundario as id_cnae_secundario, 
               D.cnae_secundario as cnae_secundario,
               D.data_abertura as data_abertura,
               D.data_processamento as data_processamento,
               D.natureza_juridica as natureza_juridica,
               D.capital_social as capital_social,
               D.telefone_1 as telefone_1,
               D.telefone_2 as telefone_2,
               D.correio_eletronico as email,
               D.situacaoReceita as situacao_rf,
               D.ds_porte_empresa as porte_empresa,
               D.uf as uf,
               D.municipio as municipio
        FROM [temp_CGUSC].[fp].[dados_farmacia] D
    """
    with engine.connect() as conn:
        total_rows = conn.execute(text("SELECT COUNT(*) FROM [temp_CGUSC].[fp].[dados_farmacia]")).scalar()
    
    print(f"   -> Registros Cadastrais: {total_rows:,}")
    chunk_list = []
    rows_processed = 0
    CHUNK_SIZE = 5_000

    for chunk in pd.read_sql(sql, engine, chunksize=CHUNK_SIZE):
        chunk_list.append(pl.from_pandas(chunk))
        rows_processed += len(chunk)
        p = int((rows_processed / total_rows) * 100) if total_rows > 0 else 100
        print(f"   -> Progresso Dados Farmácias: {p}% ({rows_processed:,} / {total_rows:,})")
        if progress_callback: progress_callback(p)

    _df_dados_farmacia = pl.concat(chunk_list).with_columns([
        (pl.col("is_matriz") == "M").alias("is_matriz"),
        pl.col("id_cnae_principal").cast(pl.String),
        pl.col("id_cnae_secundario").cast(pl.Int64, strict=False).cast(pl.String),
    ]).sort("cnpj")
    _df_dados_farmacia.write_parquet(_DADOS_FARMACIA_PARQUET_PATH, compression="zstd")


def _sync_dados_socios(engine, progress_callback=None):
    """Tarefa: Sincroniza dados societários das farmácias."""
    global _df_dados_socios
    print("Sincronizando Dados Societários...")
    sql = "SELECT * FROM [temp_CGUSC].[fp].[dados_socios]"

    with engine.connect() as conn:
        total_rows = conn.execute(text("SELECT COUNT(*) FROM [temp_CGUSC].[fp].[dados_socios]")).scalar()

    print(f"   -> Registros Societários: {total_rows:,}")
    chunk_list = []
    rows_processed = 0
    CHUNK_SIZE = 5_000

    for chunk in pd.read_sql(sql, engine, chunksize=CHUNK_SIZE):
        chunk_list.append(pl.from_pandas(chunk))
        rows_processed += len(chunk)
        p = int((rows_processed / total_rows) * 100) if total_rows > 0 else 100
        if progress_callback: progress_callback(p)

    df_full = pl.concat(chunk_list)
    
    # Debug: Mostrar colunas reais antes do cast
    # print(f"DEBUG: Colunas encontradas: {df_full.columns}")

    _df_dados_socios = df_full.with_columns([
        pl.col("cnpj").cast(pl.String),
        pl.col("cpf_cnpj_socio").cast(pl.String),
        pl.col("nome_socio").cast(pl.String),
        pl.col("municipio").cast(pl.Categorical),
        pl.col("uf").cast(pl.Categorical),
        pl.col("cpf_representante").cast(pl.String),
        pl.col("id_qualificacao_representante").cast(pl.Int8, strict=False),
        pl.col("nome_representante").cast(pl.String),
        pl.col("descricao_qualificacao_representante").cast(pl.Categorical),
        pl.col("data_nascimento_socio").cast(pl.Date),
        pl.col("data_nascimento_representante").cast(pl.Date),
        pl.col("indicador_socio").cast(pl.Categorical),
        pl.col("descricao_qualificacao").cast(pl.Categorical),
        pl.col("data_entrada_sociedade").cast(pl.Date),
        pl.col("data_exclusao_sociedade").cast(pl.Date),
        pl.col("percentual_qualificacao").cast(pl.Float32),
        pl.col("data_processamento").cast(pl.Date),
        pl.col("is_falecido").cast(pl.Int8),
    ]).sort("cnpj")

    _df_dados_socios.write_parquet(_DADOS_SOCIOS_PARQUET_PATH, compression="zstd")
    print(f"   -> Sincronização de Sócios finalizada ({len(_df_dados_socios):,} registros).")


def _sync_teia_fonte_nivel2(engine, progress_callback=None):
    """Tarefa: Sincroniza participações externas dos sócios encontrados nas farmácias."""
    global _df_teia_fonte_nivel2
    print("Sincronizando Participações Externas dos Sócios...")
    sql = "SELECT * FROM [temp_CGUSC].[fp].[teia_fonte_nivel2]"

    with engine.connect() as conn:
        total_rows = conn.execute(text("SELECT COUNT(*) FROM [temp_CGUSC].[fp].[teia_fonte_nivel2]")).scalar()

    if total_rows == 0:
        print("   -> Nenhuma participação externa encontrada.")
        _df_teia_fonte_nivel2 = pl.DataFrame(schema={
            "cpf_cnpj_socio": pl.String, "cnpj_empresa": pl.String, 
            "razao_social": pl.String,
            "nome_fantasia": pl.String,
            "indicador_socio": pl.Categorical,
            "descricao_qualificacao": pl.Categorical,
            "cpf_representante": pl.String,
            "nome_representante": pl.String,
            "data_entrada_sociedade": pl.Date,
            "data_exclusao_sociedade": pl.Date, "situacao_rf": pl.Categorical,
            "municipio": pl.Categorical, "uf": pl.Categorical, "is_farmacia_fp": pl.Int8,
            "is_falecido": pl.Int8,
        })
        _df_teia_fonte_nivel2.write_parquet(_TEIA_FONTE_NIVEL2_PARQUET_PATH, compression="zstd")
        if progress_callback: progress_callback(100)
        return

    print(f"   -> Registros de Participações Externas: {total_rows:,}")
    chunk_list = []
    rows_processed = 0
    CHUNK_SIZE = 10_000

    for chunk in pd.read_sql(sql, engine, chunksize=CHUNK_SIZE):
        df_chunk = pl.from_pandas(chunk)
        # CAST DIRETO (SEM FALLBACKS)
        df_chunk = df_chunk.with_columns([
            pl.col("data_entrada_sociedade").cast(pl.Date, strict=False),
            pl.col("data_exclusao_sociedade").cast(pl.Date, strict=False)
        ])
            
        chunk_list.append(df_chunk)
        rows_processed += len(chunk)
        p = int((rows_processed / total_rows) * 100) if total_rows > 0 else 100
        if progress_callback: progress_callback(p)

    df_full = pl.concat(chunk_list)
    
    _df_teia_fonte_nivel2 = df_full.with_columns([
        pl.col("cpf_cnpj_socio").cast(pl.String),
        pl.col("cnpj_empresa").cast(pl.String),
        pl.col("razao_social").cast(pl.String),
        pl.col("nome_fantasia").cast(pl.String),
        pl.col("indicador_socio").cast(pl.Categorical),
        pl.col("descricao_qualificacao").cast(pl.Categorical),
        pl.col("cpf_representante").cast(pl.String),
        pl.col("nome_representante").cast(pl.String),
        pl.col("data_entrada_sociedade").cast(pl.Date),
        pl.col("data_exclusao_sociedade").cast(pl.Date),
        pl.col("situacao_rf").cast(pl.Categorical),
        pl.col("municipio").cast(pl.Categorical),
        pl.col("uf").cast(pl.Categorical),
        pl.col("is_farmacia_fp").cast(pl.Int8),
        pl.col("is_falecido").cast(pl.Int8),
    ]).sort("cpf_cnpj_socio")

    _df_teia_fonte_nivel2.write_parquet(_TEIA_FONTE_NIVEL2_PARQUET_PATH, compression="zstd")
    print(f"   -> Sincronização de Participações Externas finalizada ({len(_df_teia_fonte_nivel2):,} registros).")


def _sync_teia_fonte_nivel3(engine, progress_callback=None):
    """Tarefa: Sincroniza os sócios das empresas irmãs (Expansão de 3º Grau)."""
    global _df_teia_fonte_nivel3
    print("Sincronizando Sócios das Empresas Irmãs (Expansão Teia)...")
    sql = "SELECT * FROM [temp_CGUSC].[fp].[teia_fonte_nivel3]"

    with engine.connect() as conn:
        total_rows = conn.execute(text("SELECT COUNT(*) FROM [temp_CGUSC].[fp].[teia_fonte_nivel3]")).scalar()

    if total_rows == 0:
        print("   -> Nenhum sócio indireto encontrado.")
        _df_teia_fonte_nivel3 = pl.DataFrame(schema={
            "cnpj_empresa": pl.String, "cpf_cnpj_socio": pl.String,
            "nome_socio": pl.String, "indicador_socio": pl.Categorical,
            "descricao_qualificacao": pl.Categorical,
            "cpf_representante": pl.String,
            "nome_representante": pl.String,
            "data_entrada_sociedade": pl.Date, "data_exclusao_sociedade": pl.Date,
            "municipio": pl.String, "uf": pl.String,
        })
        _df_teia_fonte_nivel3.write_parquet(_TEIA_FONTE_NIVEL3_PARQUET_PATH, compression="zstd")
        if progress_callback: progress_callback(100)
        return

    print(f"   -> Registros de Sócios Indiretos: {total_rows:,}")
    chunk_list = []
    rows_processed = 0
    CHUNK_SIZE = 25_000

    for chunk in pd.read_sql(sql, engine, chunksize=CHUNK_SIZE):
        df_chunk = pl.from_pandas(chunk)
        # CAST DIRETO
        df_chunk = df_chunk.with_columns([
            pl.col("data_entrada_sociedade").cast(pl.Date, strict=False),
            pl.col("data_exclusao_sociedade").cast(pl.Date, strict=False)
        ])

        chunk_list.append(df_chunk)
        rows_processed += len(chunk)
        p = int((rows_processed / total_rows) * 100) if total_rows > 0 else 100
        if progress_callback: progress_callback(p)

    _df_teia_fonte_nivel3 = pl.concat(chunk_list).with_columns([
        pl.col("cnpj_empresa").cast(pl.String),
        pl.col("cpf_cnpj_socio").cast(pl.String),
        pl.col("indicador_socio").cast(pl.Categorical),
        pl.col("descricao_qualificacao").cast(pl.Categorical),
        pl.col("cpf_representante").cast(pl.String),
        pl.col("nome_representante").cast(pl.String),
        pl.col("municipio").cast(pl.String),
        pl.col("uf").cast(pl.String),
        pl.col("is_falecido").cast(pl.Int8),
    ]).sort(["cnpj_empresa", "cpf_cnpj_socio"])

    _df_teia_fonte_nivel3.write_parquet(_TEIA_FONTE_NIVEL3_PARQUET_PATH, compression="zstd")
    print(f"   -> Sincronização de Sócios Indiretos finalizada.")


def _sync_teia_fonte_nivel4(engine, progress_callback=None):
    """Tarefa: Sincroniza participações de 4º grau (Empresas dos sócios de 3º grau)."""
    global _df_teia_fonte_nivel4
    print("Sincronizando Expansão de 4º Grau (Teia Nacional)...")
    sql = "SELECT * FROM [temp_CGUSC].[fp].[teia_fonte_nivel4]"

    with engine.connect() as conn:
        total_rows = conn.execute(text("SELECT COUNT(*) FROM [temp_CGUSC].[fp].[teia_fonte_nivel4]")).scalar()

    if total_rows == 0:
        print("   -> Nenhuma participação de 4º grau encontrada.")
        _df_teia_fonte_nivel4 = pl.DataFrame(schema={
            "cpf_cnpj_socio": pl.String, "cnpj_empresa": pl.String, 
            "razao_social": pl.String,
            "nome_fantasia": pl.String,
            "indicador_socio": pl.Categorical,
            "descricao_qualificacao": pl.Categorical,
            "cpf_representante": pl.String,
            "nome_representante": pl.String,
            "data_entrada_sociedade": pl.Date,
            "data_exclusao_sociedade": pl.Date, "situacao_rf": pl.Categorical,
            "municipio": pl.Categorical, "uf": pl.Categorical, "is_farmacia_fp": pl.Int8,
            "is_falecido": pl.Int8
        })
        _df_teia_fonte_nivel4.write_parquet(_TEIA_FONTE_NIVEL4_PARQUET_PATH, compression="zstd")
        if progress_callback: progress_callback(100)
        return

    print(f"   -> Registros de 4º Grau: {total_rows:,}")
    chunk_list = []
    rows_processed = 0
    CHUNK_SIZE = 50_000 # Chunk maior para processar os 4M de linhas com eficiência

    for chunk in pd.read_sql(sql, engine, chunksize=CHUNK_SIZE):
        df_chunk = pl.from_pandas(chunk)
        # CAST DIRETO
        df_chunk = df_chunk.with_columns([
            pl.col("data_entrada_sociedade").cast(pl.Date, strict=False),
            pl.col("data_exclusao_sociedade").cast(pl.Date, strict=False)
        ])
            
        chunk_list.append(df_chunk)
        rows_processed += len(chunk)
        p = int((rows_processed / total_rows) * 100) if total_rows > 0 else 100
        if progress_callback: progress_callback(p)

    df_full = pl.concat(chunk_list)

    _df_teia_fonte_nivel4 = df_full.with_columns([
        pl.col("cpf_cnpj_socio").cast(pl.String),
        pl.col("cnpj_empresa").cast(pl.String),
        pl.col("razao_social").cast(pl.String),
        pl.col("nome_fantasia").cast(pl.String),
        pl.col("indicador_socio").cast(pl.Categorical),
        pl.col("descricao_qualificacao").cast(pl.Categorical),
        pl.col("cpf_representante").cast(pl.String),
        pl.col("nome_representante").cast(pl.String),
        pl.col("data_entrada_sociedade").cast(pl.Date),
        pl.col("data_exclusao_sociedade").cast(pl.Date),
        pl.col("situacao_rf").cast(pl.Categorical),
        pl.col("municipio").cast(pl.Categorical),
        pl.col("uf").cast(pl.Categorical),
        pl.col("is_farmacia_fp").cast(pl.Int8),
        pl.col("is_falecido").cast(pl.Int8),
    ]).sort("cpf_cnpj_socio")

    _df_teia_fonte_nivel4.write_parquet(_TEIA_FONTE_NIVEL4_PARQUET_PATH, compression="zstd")
    print(f"   -> Sincronização de 4º Grau finalizada ({len(_df_teia_fonte_nivel4):,} registros).")


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
    ]).sort("codigo_barra")
    _df_medicamentos.write_parquet(_MEDICAMENTOS_PARQUET_PATH, compression="zstd")


def _sync_movimentacao(engine, progress_callback):
    """Tarefa 2: Sincroniza a movimentação mensal (Tabela Grande)."""
    global _df_movimentacao
    with engine.connect() as conn:
        total_rows = conn.execute(text("SELECT COUNT(*) FROM [temp_CGUSC].[fp].[movimentacao_mensal_cnpj]")).scalar()
    
    # Query otimizada: busca geografia via JOIN para economizar espaço no SQL
    sql = """
        SELECT M.cnpj, P.uf, IB.id_regiao_saude, P.municipio AS no_municipio, M.periodo,
               CAST(M.total_vendas AS FLOAT) AS total_vendas,
               CAST(M.total_sem_comprovacao AS FLOAT) AS total_sem_comprovacao,
               M.total_qnt_vendas,
               M.total_qnt_sem_comprovacao,
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
        LEFT JOIN [temp_CGUSC].[fp].[dados_farmacia] DF ON DF.cnpj = M.cnpj
        LEFT JOIN [temp_CGUSC].[fp].[dados_ibge] IB ON IB.id_ibge7 = DF.codibge
    """
    
    chunk_list = []
    rows_processed = 0
    CHUNK_SIZE = 250_000
    
    print(f"Total de registros a baixar: {total_rows:,}")
    
    for chunk in pd.read_sql(sql, engine, chunksize=CHUNK_SIZE):
        chunk_list.append(pl.from_pandas(chunk))
        rows_processed += len(chunk)
        p = int((rows_processed / total_rows) * 100) if total_rows > 0 else 100
        print(f"   -> Progresso Movimentação: {p}% ({rows_processed:,} / {total_rows:,})")
        progress_callback(p)

    print("   -> Organizando e otimizando dados (Polars)...")
    _df_movimentacao = pl.concat(chunk_list).with_columns([
        pl.col("periodo").cast(pl.Date),
        pl.col("uf").cast(pl.Categorical),
        pl.col("id_regiao_saude").cast(pl.String),
        pl.col("no_municipio").cast(pl.Categorical),
        pl.col("razao_social").cast(pl.Categorical),  # Mudado para Categorical para compressão
        pl.col("situacao_rf").cast(pl.Categorical),
        pl.col("porte_empresa").cast(pl.Categorical),
        pl.col("unidade_pf").cast(pl.Categorical),
        pl.col("is_conexao_ativa").cast(pl.Boolean),
        pl.col("is_grande_rede").cast(pl.Boolean),
        pl.col("is_matriz").cast(pl.Boolean),
        pl.col("qtd_estabelecimentos_rede").cast(pl.Int64),
        pl.col("total_qnt_vendas").cast(pl.Int32),
        pl.col("total_qnt_sem_comprovacao").cast(pl.Int32),
        pl.col("total_vendas").cast(pl.Float64),
        pl.col("total_sem_comprovacao").cast(pl.Float64),
    ]).sort(["cnpj", "periodo"])  # ORDENAÇÃO é a chave para compressão Parquet
    
    _df_movimentacao.write_parquet(_PARQUET_PATH, compression="zstd")

def _sync_crm_benchmarks(engine, progress_callback=None):
    """Tarefa 5: Gera bench_uf, bench_regiao e bench_br como parquets a partir das tabelas de indicadores do banco."""
    print("Sincronizando Benchmarks CRM (Nacional, Estadual e Regional)...")
    
    tab_map = {
        "BR":     {"table": "temp_CGUSC.fp.indicador_crm_bench_br",     "path": _BENCH_CRM_BR_PATH},
        "UF":     {"table": "temp_CGUSC.fp.indicador_crm_bench_uf",     "path": _BENCH_CRM_UF_PATH},
        "REGIAO": {"table": "temp_CGUSC.fp.indicador_crm_bench_regiao", "path": _BENCH_CRM_REGIAO_PATH},
    }

    total = len(tab_map)
    for i, (key, info) in enumerate(tab_map.items()):
        try:
            sql = f"SELECT * FROM {info['table']}"
            pdf = pd.read_sql(sql, engine)
            
            df = pl.from_pandas(pdf).with_columns([
                pl.col("competencia").cast(pl.Int32)
            ])
            
            # Remove redundância (caso o SQL tenha retornado uma linha por CNPJ sem DISTINCT)
            subset_cols = ["competencia"]
            if "uf" in df.columns: subset_cols.append("uf")
            if "id_regiao_saude" in df.columns: subset_cols.append("id_regiao_saude")
            
            df = df.unique(subset=subset_cols)
            
            # UF e Região de Saúde são categóricos
            if "uf" in df.columns:
                df = df.with_columns(pl.col("uf").cast(pl.Categorical))
            if "id_regiao_saude" in df.columns:
                df = df.with_columns(pl.col("id_regiao_saude").cast(pl.String))
                
            df.write_parquet(info['path'], compression="zstd")
            print(f"   -> Benchmark {key} exportado: {len(df):,} registros únicos.")
            
            if progress_callback:
                progress_callback(int(((i+1)/total) * 100))
        except Exception as e:
            print(f"   [AVISO] Erro ao exportar benchmark {key}: {e}")

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
            print(f"[ERRO] Erro ao buscar lista de CNPJs: {e}")
            return

    total = len(cnpjs)
    print(f"Sincronizando parquets de CRMs para {total} estabelecimento(s)...")

    for i, cnpj in enumerate(cnpjs, 1):
        try:
            # 1. Lista de Médicos e Alertas (Gera 3 parquets: _prescritores, _crm_unico_alertas, _cnpj_alerts)
            AnalyticsService.get_crm_data(cnpj)
            
            # 2. Perfil Diário Unificado (is_dia_com_volume_horario_anomalo + is_anomalo_unico)
            AnalyticsService.get_crm_perfil_diario(cnpj)

            # 3. Detalhamento Horário de Anomalias (auto-warms medianas internamente)
            AnalyticsService.get_crm_perfil_horario(cnpj)

            # 4. Transações Raio-X (unificado: múltiplos + único)
            AnalyticsService.sync_crm_raiox_tx(cnpj)

            if progress_callback:
                p = int((i / total) * 100)
                progress_callback(p)
        except Exception as e:
            print(f"\n[AVISO]  Erro ao sincronizar CNPJ {cnpj}: {e}")

    if progress_callback:
        progress_callback(100)


# --- GERENCIADOR DE CACHE ---

def load_cache(engine, force_refresh: bool = False) -> None:
    global _df_movimentacao, _df_localidades, _df_rede, _df_matriz_risco, _df_bench_crm_uf, _df_bench_crm_regiao, _df_bench_crm_br, _df_dados_farmacia, _df_dados_socios, _df_teia_fonte_nivel2, _df_teia_fonte_nivel3, _df_teia_fonte_nivel4, _df_medicamentos, _cache_progress, _cache_status, _cache_error_message
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
                print(f"[ CACHE ] GLOBAL ● {name} ● [AVISO] ERRO DE LEITURA ({e})")
                missing.append(name)
                return None

        _df_movimentacao    = _try_load("movimentacao",    _PARQUET_PATH)
        _df_localidades     = _try_load("localidades",     _LOCALIDADES_PARQUET_PATH)
        _df_rede            = _try_load("rede",            _REDE_PARQUET_PATH)
        _df_matriz_risco    = _try_load("matriz_risco",    _MATRIZ_PARQUET_PATH)
        _df_bench_crm_uf    = _try_load("bench_crm_uf",   _BENCH_CRM_UF_PATH)
        _df_bench_crm_regiao= _try_load("bench_crm_regiao", _BENCH_CRM_REGIAO_PATH)
        _df_bench_crm_br    = _try_load("bench_crm_br",   _BENCH_CRM_BR_PATH)
        _df_dados_farmacia  = _try_load("dados_farmacia",  _DADOS_FARMACIA_PARQUET_PATH)
        _df_dados_socios    = _try_load("dados_socios",    _DADOS_SOCIOS_PARQUET_PATH)
        _df_teia_fonte_nivel2 = _try_load("teia_fonte_nivel2", _TEIA_FONTE_NIVEL2_PARQUET_PATH)

        _df_teia_fonte_nivel3 = _try_load("teia_fonte_nivel3", _TEIA_FONTE_NIVEL3_PARQUET_PATH)
        _df_teia_fonte_nivel4 = _try_load("teia_fonte_nivel4", _TEIA_FONTE_NIVEL4_PARQUET_PATH)
        _df_medicamentos    = _try_load("medicamentos",    _MEDICAMENTOS_PARQUET_PATH)

        if missing:
            print(f"[AVISO]  Cache incompleto — módulos ausentes: {', '.join(missing)}")
            print("[INFO]  Sistema iniciado em modo degradado. Sincronize pela interface para carregar os dados.")
            _cache_status = "idle"
            _cache_progress = 0
        else:
            _cache_progress = 100
            _cache_status = "ready"
            print(f"[OK] Caches carregados via Parquet.")
        return

    from typing import TypedDict, Callable, List

    class SyncTask(TypedDict):
        name: str
        weight: int
        func: Callable[[Callable[[int], None]], None]

    TASKS: List[SyncTask] = [
        {"name": "Cadastro Medicamentos", "weight": 5,  "func": lambda cb: _sync_medicamentos(engine, cb)},
        {"name": "Localidades",           "weight": 2,  "func": lambda cb: _sync_localidades(engine, cb)},
        {"name": "Rede Estabelecimentos", "weight": 3,  "func": lambda cb: _sync_rede(engine, cb)},
        {"name": "Matriz de Risco",       "weight": 11, "func": lambda cb: _sync_matriz_risco(engine, cb)},
        {"name": "Dados das Farmácias",   "weight": 5,  "func": lambda cb: _sync_dados_farmacia(engine, cb)},
        {"name": "Dados dos Sócios",      "weight": 5,  "func": lambda cb: _sync_dados_socios(engine, cb)},
        {"name": "Participações e Representantes", "weight": 5, "func": lambda cb: _sync_teia_fonte_nivel2(engine, cb)},
        {"name": "Sócios Indiretos (Expansão)", "weight": 4, "func": lambda cb: _sync_teia_fonte_nivel3(engine, cb)},
        {"name": "Expansão Nacional (N4)",  "weight": 8, "func": lambda cb: _sync_teia_fonte_nivel4(engine, cb)},
        {"name": "Movimentação (Vendas)", "weight": 52, "func": lambda cb: _sync_movimentacao(engine, cb)},
    ]

    t0 = time.perf_counter()
    acumulado_weight = 0

    try:
        for task in TASKS:
            _cache_status = task["name"]
            current_weight = task["weight"]
            print(f"[*] {task['name']}...")

            def update_global_progress(p_int: int, _base=acumulado_weight, _w=current_weight):
                global _cache_progress
                _cache_progress = int(_base + (p_int / 100 * _w))

            task["func"](update_global_progress)
            acumulado_weight += current_weight

        _cache_progress = 100
        _cache_status = "ready"
        print(f"[OK] Sincronização concluída em {time.perf_counter() - t0:.1f}s")

    except Exception as e:
        _cache_status = "error"
        _cache_progress = 0
        _cache_error_message = str(e)
        import traceback
        print(f"[ERRO] Erro Crítico na Sincronização: {e}")
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

def get_df_dados_socios() -> pl.DataFrame:
    if _df_dados_socios is None:
        raise RuntimeError("Cache de Dados dos Sócios não carregado. Execute uma sincronização.")
    return _df_dados_socios

def get_df_teia_fonte_nivel2() -> pl.DataFrame:
    if _df_teia_fonte_nivel2 is None:
        raise RuntimeError("Cache de Participações Externas dos Sócios não carregado. Execute uma sincronização.")
    return _df_teia_fonte_nivel2

def get_df_teia_fonte_nivel3() -> pl.DataFrame:
    if _df_teia_fonte_nivel3 is None:
        raise RuntimeError("Cache de Sócios Indiretos não carregado. Execute uma sincronização.")
    return _df_teia_fonte_nivel3

def get_df_teia_fonte_nivel4() -> pl.DataFrame:
    if _df_teia_fonte_nivel4 is None:
        raise RuntimeError("Cache de Teia Nacional (N4) não carregado. Execute uma sincronização.")
    return _df_teia_fonte_nivel4

def get_medicamentos_df() -> pl.DataFrame:
    global _df_medicamentos
    if _df_medicamentos is None:
        # Se não carregado, tentamos ler do parquet direto se existir
        if os.path.exists(_MEDICAMENTOS_PARQUET_PATH):
            try:
                _df_medicamentos = pl.read_parquet(_MEDICAMENTOS_PARQUET_PATH)
                return _df_medicamentos
            except Exception as e:
                print(f"[ CACHE ] GLOBAL ● medicamentos ● [AVISO] ERRO DE LEITURA ({e})")
        raise RuntimeError("Cache de Medicamentos não carregado. Execute uma sincronização.")
    return _df_medicamentos

def get_cache_status() -> dict:
    """Retorna o estado atual da sincronização para o frontend."""
    modules = {
        "movimentacao":   {"label": "Movimentação Mensal",     "path": _PARQUET_PATH,             "loaded": _df_movimentacao is not None},
        "localidades":    {"label": "Localidades (IBGE)",      "path": _LOCALIDADES_PARQUET_PATH, "loaded": _df_localidades is not None},
        "rede":           {"label": "Rede de Estabelecimentos","path": _REDE_PARQUET_PATH,        "loaded": _df_rede is not None},
        "matriz_risco":   {"label": "Matriz de Risco",         "path": _MATRIZ_PARQUET_PATH,      "loaded": _df_matriz_risco is not None},
        "bench_crm_uf":    {"label": "Benchmark CRM (UF)",      "path": _BENCH_CRM_UF_PATH,        "loaded": _df_bench_crm_uf is not None},
        "bench_crm_regiao":{"label": "Benchmark CRM (Região)", "path": _BENCH_CRM_REGIAO_PATH,    "loaded": _df_bench_crm_regiao is not None},
        "bench_crm_br":    {"label": "Benchmark CRM (Brasil)", "path": _BENCH_CRM_BR_PATH,        "loaded": _df_bench_crm_br is not None},
        "dados_farmacia": {"label": "Dados das Farmácias",     "path": _DADOS_FARMACIA_PARQUET_PATH,  "loaded": _df_dados_farmacia is not None},
        "dados_socios":   {"label": "Dados dos Sócios",        "path": _DADOS_SOCIOS_PARQUET_PATH,    "loaded": _df_dados_socios is not None},
        "teia_fonte_nivel2":{"label": "Participações Externas",  "path": _TEIA_FONTE_NIVEL2_PARQUET_PATH, "loaded": _df_teia_fonte_nivel2 is not None},
        "teia_fonte_nivel3":{"label": "Sócios Indiretos",        "path": _TEIA_FONTE_NIVEL3_PARQUET_PATH,   "loaded": _df_teia_fonte_nivel3 is not None},
        "teia_fonte_nivel4":{"label": "Expansão Nacional (N4)",  "path": _TEIA_FONTE_NIVEL4_PARQUET_PATH,   "loaded": _df_teia_fonte_nivel4 is not None},
        "medicamentos":   {"label": "Cadastro Medicamentos",   "path": _MEDICAMENTOS_PARQUET_PATH,    "loaded": _df_medicamentos is not None},
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
