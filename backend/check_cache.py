import polars as pl
import os

CACHE_PATH = r"d:\sentinela\sentinela_cache\cache_matriz_risco.parquet"

if os.path.exists(CACHE_PATH):
    df = pl.read_parquet(CACHE_PATH)
    print(f"Colunas encontradas: {df.columns}")
    print(f"Exemplo de dados (primeiras 5 linhas):\n{df.head(5)}")
    
    # Verifica especificamente o score
    score_cols = [c for c in df.columns if 'score' in c.lower()]
    if score_cols:
        print(f"\nValores das colunas de score:\n{df.select(score_cols).head(10)}")
        null_count = df.select(score_cols).null_count()
        print(f"\nContagem de nulos nas colunas de score:\n{null_count}")
    else:
        print("\nNenhuma coluna com 'score' no nome foi encontrada no cache.")
else:
    print(f"O arquivo de cache {CACHE_PATH} não existe.")
