import polars as pl
import json

try:
    df = pl.read_parquet('d:/sentinela/sentinela_cache/cache_matriz_risco.parquet')
    columns = df.columns
    with open('d:/sentinela/columns.json', 'w') as f:
        json.dump(columns, f)
    print("Success")
except Exception as e:
    print(f"Error: {e}")
